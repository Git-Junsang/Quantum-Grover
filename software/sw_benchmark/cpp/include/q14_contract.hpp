// q14_contract.hpp : shared contract for every C++ model (constants, j and measurement
// random streams, m bounds, oracle mask, dataset/seed loading, timer, result structs).
//
// Everything in this header must match the frozen v0.9.8 hardware contract
// (software/models/.../final_hardware_contract.py, checkpoint_bbht_model.py):
//   Q14, N = 16384, P = 32 lanes, signed Q1.22 amplitudes,
//   BBHT m0 = 1, lambda = 6/5, m_max = 128, logical budget 576, shot cap 100,
//   J stream  : 32-bit LFSR, pre-state word then 7 ordinary steps per draw,
//   measurement: xorshift64(13,7,17) block stream, seed {s, s ^ 0x9E3779B9}.
#pragma once

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace grover {

constexpr int Q_BITS = 14;
constexpr int N = 1 << Q_BITS;            // 16384 basis states
constexpr int P = 32;                     // lanes per row (RTL parallelism)
constexpr int ROWS = N / P;               // 512
constexpr int FRAC_BITS = 22;             // Q1.22
constexpr int64_t AMP_MAX = (int64_t(1) << FRAC_BITS) - 1;
constexpr int64_t AMP_MIN = -AMP_MAX;
constexpr int64_t INIT_AMP_RAW = int64_t(1) << (FRAC_BITS - Q_BITS / 2);  // 32768
constexpr int LOGICAL_BUDGET = 576;
constexpr int DEFAULT_SHOT_CAP = 100;
constexpr uint32_t J_FALLBACK_SEED = 0xACE12345u;
constexpr uint32_t MEAS_FALLBACK_SEED = 0xBEEFC0DEu;
constexpr uint32_t MEAS_SEED_MIX = 0x9E3779B9u;

// m sequence for m0 = 1, lambda = 6/5, m_max = 128 (v098_m_bounds()).
constexpr std::array<int, 28> M_BOUNDS = {1,  2,  2,  2,  3,  3,  3,  4,  5,  6,
                                          7,  8,  9,  11, 13, 16, 19, 23, 27, 32,
                                          39, 47, 56, 67, 80, 96, 115, 128};

inline int bit_length(uint64_t v) {
    int n = 0;
    while (v) { ++n; v >>= 1; }
    return n;
}

// ---------------------------------------------------------------- J stream
inline uint32_t lfsr_step(uint32_t v) {
    uint32_t fb = ((v >> 31) ^ (v >> 21) ^ (v >> 1) ^ v) & 1u;
    return (v << 1) | fb;
}

struct JRandomSource {
    uint32_t state;
    explicit JRandomSource(uint32_t seed) : state(seed ? seed : J_FALLBACK_SEED) {}
    uint32_t draw_word() {
        uint32_t value = state;
        for (int i = 0; i < 7; ++i) state = lfsr_step(state);
        return value;
    }
    // Exact-uniform j in [0, bound) by low-byte rejection (grover_j_reject.v).
    int draw_uniform(int bound) {
        int bits = bit_length(uint64_t(bound - 1));
        uint32_t mask = bits ? (1u << bits) - 1u : 0u;
        for (;;) {
            uint32_t c = (draw_word() & 0xFFu) & mask;
            if (int(c) < bound) return int(c);
        }
    }
};

inline int m_bound_for_round(int round_index) {
    return M_BOUNDS[std::min<size_t>(round_index, M_BOUNDS.size() - 1)];
}

// Future requested_j values seen by the RTL shadow-J generator.
inline std::vector<int> predict_future_j(const JRandomSource& src, int next_round, int count) {
    JRandomSource clone = src;
    std::vector<int> out;
    int r = next_round;
    for (int i = 0; i < count; ++i) {
        out.push_back(clone.draw_uniform(m_bound_for_round(r)));
        r = std::min<int>(r + 1, int(M_BOUNDS.size()) - 1);
    }
    return out;
}

// ------------------------------------------------------ measurement stream
struct MeasRandomSource {
    uint64_t state;
    explicit MeasRandomSource(uint32_t seed) {
        uint64_t e = seed ? seed : MEAS_FALLBACK_SEED;
        state = (e << 32) | (e ^ MEAS_SEED_MIX);
    }
    uint64_t draw_block() {
        uint64_t block = state, v = state;
        v ^= v << 13;
        v ^= v >> 7;
        v ^= v << 17;
        state = v;
        return block;
    }
    // Uniform double in [0, 1) from one 64-bit block (float engines only).
    double draw_unit() { return double(draw_block() >> 11) * 0x1.0p-53; }
};

// ----------------------------------------------------------------- oracle
enum class Predicate { LT = 0, GT = 1, EQ = 2, RANGE = 3 };

inline Predicate parse_predicate(const std::string& s) {
    if (s == "LT") return Predicate::LT;
    if (s == "GT") return Predicate::GT;
    if (s == "EQ") return Predicate::EQ;
    if (s == "RANGE") return Predicate::RANGE;
    throw std::invalid_argument("predicate must be LT, GT, EQ or RANGE");
}

struct OracleConfig {
    Predicate predicate = Predicate::EQ;
    int threshold_a = 12345;   // official Common500 target value
    int threshold_b = 0;
    int data_count = N;
};

// predicate && valid (v098_target_mask). RANGE is strict: a < x < b.
inline std::vector<uint8_t> build_target_mask(const std::vector<int16_t>& data, const OracleConfig& c) {
    std::vector<uint8_t> mask(N, 0);
    for (int i = 0; i < N; ++i) {
        int v = data[i];
        bool m = false;
        switch (c.predicate) {
            case Predicate::LT: m = v < c.threshold_a; break;
            case Predicate::GT: m = v > c.threshold_a; break;
            case Predicate::EQ: m = v == c.threshold_a; break;
            case Predicate::RANGE: m = v > c.threshold_a && v < c.threshold_b; break;
        }
        mask[i] = uint8_t(m && i < c.data_count);
    }
    return mask;
}

// ------------------------------------------------------------ input files
inline std::vector<int16_t> load_dataset(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) throw std::runtime_error("cannot open dataset " + path);
    std::vector<int16_t> d(N);
    f.read(reinterpret_cast<char*>(d.data()), N * sizeof(int16_t));
    if (f.gcount() != N * 2) throw std::runtime_error("dataset must hold 16384 int16 values: " + path);
    return d;
}

struct SeedPair { int index; uint32_t seed_j; uint32_t seed_meas; };

inline std::vector<SeedPair> load_seed_roster(const std::string& path) {
    std::ifstream f(path);
    if (!f) throw std::runtime_error("cannot open roster " + path);
    std::stringstream ss; ss << f.rdbuf();
    std::string text = ss.str();
    std::regex re("\\{\\s*(0x[0-9A-Fa-f]+)u?\\s*,\\s*(0x[0-9A-Fa-f]+)u?\\s*\\}");
    std::vector<SeedPair> out;
    int i = 0;
    for (std::sregex_iterator it(text.begin(), text.end(), re), end; it != end; ++it)
        out.push_back({i++, uint32_t(std::stoul((*it)[1], nullptr, 16)), uint32_t(std::stoul((*it)[2], nullptr, 16))});
    if (out.empty()) throw std::runtime_error("no seed pairs in " + path);
    return out;
}

// ----------------------------------------------------------------- timing
using Clock = std::chrono::steady_clock;
inline int64_t now_ns() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now().time_since_epoch()).count();
}

// ----------------------------------------------------------------- result
enum class Termination { SUCCESS, SHOT_LIMIT, BUDGET_LIMIT };
inline const char* termination_name(Termination t) {
    switch (t) {
        case Termination::SUCCESS: return "SUCCESS";
        case Termination::SHOT_LIMIT: return "SHOT_LIMIT";
        default: return "BUDGET_LIMIT";
    }
}

struct Attempt {
    int requested_j;
    int source_j;
    int physical;
    int64_t threshold;     // integer CDF threshold (RTL engine); -1 for float engines
    int result_index;
    bool success;
};

struct SearchResult {
    bool success = false;
    Termination termination = Termination::SHOT_LIMIT;
    int result_index = -1;
    int trial_count = 0;
    int L_BBHT = 0;
    int physical_iterations = 0;
    int64_t compute_ns = 0;      // Grover iterations only
    std::vector<Attempt> attempts;   // filled only when tracing
};

}  // namespace grover
