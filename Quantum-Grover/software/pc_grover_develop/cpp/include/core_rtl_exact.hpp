// core_rtl_exact.hpp : model B, RTL-identical Grover core.
//
//   signed Q1.22 integer datapath (ties-even 2*mean, symmetric saturation) and the
//   integer Born CDF sampler (64-bit block rejection, row CDF then lane).
//   Bit-exact with fixed_point_statevector.rtl_run_core and
//   checkpoint_bbht_model.measure_v098_state (= the RTL).
//   The state carries the oracle-signed amplitude sum the NEXT iteration needs
//   (its 2*mean), so every iteration is exactly one pass over the vector.
#pragma once

#include <algorithm>
#include <array>
#include <cstdint>
#include <vector>

#include <atomic>
#include <memory>

#include "q14_contract.hpp"
#include "spin_team.hpp"

namespace grover {

inline int64_t round_shift_ties_even(int64_t value, int shift) {
    int64_t den = int64_t(1) << shift;
    int64_t q = value >> shift;               // arithmetic shift = floor division
    int64_t r = value - q * den;              // 0 <= r < den
    int64_t doubled = r << 1;
    if (doubled > den || (doubled == den && (q & 1))) ++q;
    return q;
}

struct RtlCore {
    struct State {
        std::vector<int32_t> a;
        int64_t osum = 0;   // sum of oracle-applied amplitudes (RTL global_sum)
    };
    struct Cdf {
        std::array<int64_t, ROWS> row_cdf{};
        int64_t total = 0;
    };

    std::vector<int32_t> sign;   // -1 on targets, +1 elsewhere
    int64_t saturations = 0;

    int threads = 1;   // members of the SpinTeam inside one iteration (E4 counterpart)

    explicit RtlCore(const std::vector<uint8_t>& mask, int threads_ = 1) : sign(N), threads(threads_) {
        if (threads > 1) team_ = std::make_unique<SpinTeam>(threads);
        for (int i = 0; i < N; ++i) sign[i] = mask[i] ? -1 : 1;
        for (int i = 0; i < N; ++i) init_osum_ += int64_t(sign[i]) * INIT_AMP_RAW;
    }
    int64_t init_osum_ = 0;

    void reset_state(State& st) const {
        if (st.a.size() != size_t(N)) st.a.resize(N);
        std::fill(st.a.begin(), st.a.end(), int32_t(INIT_AMP_RAW));
        st.osum = init_osum_;
    }

    // after_oracle = s*a ; two_mean = round_ties_even(sum, Q-1) ; a' = sat(two_mean - s*a)
    // |two_mean| < 2^24 and |a| < 2^22, so the difference fits int32; the sum is int64.
    // Elementwise, so in == out (in place) is allowed.
    // noinline: compiled once as a standalone loop, so the vectorizer never has to
    // version it with runtime alias checks after inlining into a caller.
    __attribute__((noinline)) void iterate(const int32_t* in, int32_t* out, int64_t& osum) {
        const int32_t two_mean = int32_t(round_shift_ties_even(osum, Q_BITS - 1));
        const int32_t* sg = sign.data();
        const int32_t hi = int32_t(AMP_MAX), lo = int32_t(AMP_MIN);
        int64_t acc = 0, sat = 0;
#pragma omp simd reduction(+ : acc, sat)
        for (int i = 0; i < N; ++i) {
            int32_t d = two_mean - sg[i] * in[i];
            int32_t c = d > hi ? hi : (d < lo ? lo : d);
            sat += (c != d);
            out[i] = c;
            acc += int64_t(sg[i] * c);
        }
        osum = acc;
        saturations += sat;
    }

    void run(State& st, int iterations, int64_t& compute_ns) {
        if (iterations <= 0) return;
        int64_t t0 = now_ns();
        if (threads > 1) run_team(st, iterations);
        else for (int k = 0; k < iterations; ++k) iterate(st.a.data(), st.a.data(), st.osum);
        compute_ns += now_ns() - t0;
    }

    // E4 counterpart: the iteration is split over a persistent SpinTeam. Integer
    // partial sums are exact, so the result is bit-identical for any team size.
    void run_team(State& st, int iterations) {
        int32_t* const a = st.a.data();
        const int32_t* const sg = sign.data();
        const int64_t osum0 = st.osum;
        SpinTeam& tm = *team_;
        const int T = tm.size();
        int64_t final_osum = osum0;
        std::atomic<int64_t> sat_total{0};
        tm.run([&](int tid) {
            int lo, hi;
            SpinTeam::chunk(N, T, tid, 64, lo, hi);
            int64_t os = osum0, sat = 0;
            for (int k = 0; k < iterations; ++k) {
                const int32_t two_mean = int32_t(round_shift_ties_even(os, Q_BITS - 1));
                tm.partial<int64_t>(k & 1, tid) = slice(a, sg, two_mean, lo, hi, sat);
                tm.barrier(tid);
                os = tm.sum_partials<int64_t>(k & 1);
            }
            sat_total.fetch_add(sat, std::memory_order_relaxed);
            if (tid == 0) final_osum = os;
        });
        st.osum = final_osum;
        saturations += sat_total.load();
    }

    // One member's slice of an iteration, in place; same arithmetic as iterate().
    __attribute__((noinline)) static int64_t slice(int32_t* a, const int32_t* __restrict sg, int32_t two_mean,
                                                   int lo, int hi, int64_t& sat_out) {
        const int32_t hi_v = int32_t(AMP_MAX), lo_v = int32_t(AMP_MIN);
        int64_t acc = 0, sat = 0;
#pragma omp simd reduction(+ : acc, sat)
        for (int i = lo; i < hi; ++i) {
            int32_t d = two_mean - sg[i] * a[i];
            int32_t c = d > hi_v ? hi_v : (d < lo_v ? lo_v : d);
            sat += (c != d);
            a[i] = c;
            acc += int64_t(sg[i] * c);
        }
        sat_out += sat;
        return acc;
    }

    void step(const State& in, State& out, int64_t& compute_ns) {
        int64_t t0 = now_ns();
        out.a.resize(N);
        out.osum = in.osum;
        iterate(in.a.data(), out.a.data(), out.osum);
        compute_ns += now_ns() - t0;
    }

    void prepare(const State& st, Cdf& c) const {
        int64_t run = 0;
        for (int r = 0; r < ROWS; ++r) {
            int64_t w = 0;
            const int32_t* p = st.a.data() + r * P;
            for (int l = 0; l < P; ++l) w += int64_t(p[l]) * p[l];
            run += w;
            c.row_cdf[r] = run;
        }
        c.total = run;
    }

    // measure_v098_state: dynamic-width rejection on 64-bit blocks, then
    // FIRST row cumulative > threshold, FIRST lane cumulative > local threshold.
    int sample(const State& st, const Cdf& c, MeasRandomSource& rng, int64_t& threshold) const {
        if (c.total == 0) { threshold = -1; return -1; }
        uint64_t total = uint64_t(c.total);
        uint64_t thr = 0;
        if (total > 1) {
            int width = bit_length(total - 1);
            uint64_t mask = width >= 64 ? ~uint64_t(0) : ((uint64_t(1) << width) - 1);
            for (;;) {
                uint64_t cand = rng.draw_block() & mask;
                if (cand < total) { thr = cand; break; }
            }
        }
        threshold = int64_t(thr);
        int row = int(std::upper_bound(c.row_cdf.begin(), c.row_cdf.end(), int64_t(thr)) - c.row_cdf.begin());
        int64_t before = row ? c.row_cdf[row - 1] : 0;
        int64_t local = int64_t(thr) - before;
        const int32_t* p = st.a.data() + row * P;
        int64_t cum = 0;
        for (int l = 0; l < P; ++l) {
            cum += int64_t(p[l]) * p[l];
            if (cum > local) return row * P + l;
        }
        return row * P + P - 1;
    }
private:
    std::unique_ptr<SpinTeam> team_;
};

}  // namespace grover
