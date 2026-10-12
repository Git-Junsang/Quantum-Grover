// core_sw_float.hpp : model A, "SW best" float Grover core (float64 or float32).
//
//   Fused one-pass oracle + diffusion (inversion about the mean, O(N)), SIMD,
//   ping-pong buffers, optional SpinTeam inside an iteration (latency mode, E4 counterpart),
//   grouped cumulative-sum sampler (128 groups x 128) on |a|^2.
//   A1 = this core with the NORMAL policy (standard BBHT, main SW baseline).
//   A2 = this core with the all-j / K3H3 / K4H4 policy (auxiliary result).
#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <memory>
#include <vector>

#include "q14_contract.hpp"
#include "spin_team.hpp"

namespace grover {

template <class F>
struct FloatCore {
    static constexpr int GROUPS = 128;
    static constexpr int GSIZE = N / GROUPS;
    struct State {
        std::vector<F> a;
        double osum = 0;
    };
    struct Cdf {
        std::array<double, GROUPS> group_cdf{};
        double total = 0;
    };

    std::vector<F> sign;
    int threads = 1;   // members of the SpinTeam inside one iteration (latency mode / E4 counterpart)

    FloatCore(const std::vector<uint8_t>& mask, int threads_) : sign(N), threads(threads_) {
        if (threads > 1) team_ = std::make_unique<SpinTeam>(threads);
        a0_ = F(1.0 / std::sqrt(double(N)));
        for (int i = 0; i < N; ++i) sign[i] = mask[i] ? F(-1) : F(1);
        for (int i = 0; i < N; ++i) init_osum_ += double(sign[i]) * double(a0_);
    }
    F a0_;
    double init_osum_ = 0;

    void reset_state(State& st) const {
        if (st.a.size() != size_t(N)) st.a.resize(N);
        std::fill(st.a.begin(), st.a.end(), a0_);
        st.osum = init_osum_;
    }

    // out = 2*mean(s*in) - s*in ; accumulate s*out for the next iteration.
    // noinline: see RtlCore::iterate.
    __attribute__((noinline)) void iterate(const F* __restrict in, F* __restrict out, double& osum) const {
        const F m2 = F(2.0 * osum / double(N));
        const F* __restrict sg = sign.data();
        double acc = 0;
#pragma omp simd reduction(+ : acc)
        for (int i = 0; i < N; ++i) {
            F o = m2 - sg[i] * in[i];
            out[i] = o;
            acc += double(sg[i] * o);
        }
        osum = acc;
    }

    // Ping-pong between the state buffer and a scratch buffer (out-of-place
    // vectorizes best); an odd count ends with an O(1) vector swap, no copy.
    void run(State& st, int iterations, int64_t& compute_ns) {
        if (iterations <= 0) return;
        int64_t t0 = now_ns();
        if (scratch_.size() != size_t(N)) scratch_.resize(N);
        if (threads > 1) {
            run_team(st, iterations);
        } else {
            for (int k = 0; k < iterations; ++k) {
                iterate(st.a.data(), scratch_.data(), st.osum);
                st.a.swap(scratch_);
            }
        }
        compute_ns += now_ns() - t0;
    }

    // Latency mode (the SW counterpart of RTL E4): the iteration is split over
    // a persistent SpinTeam (spin_team.hpp). Every member owns a fixed slice of
    // the vector; the only shared value is the next 2*mean, so each iteration
    // costs one barrier. Partial sums are added in member order.
    void run_team(State& st, int iterations) {
        F* const x0 = st.a.data();
        F* const y0 = scratch_.data();
        const F* const sg = sign.data();
        const double osum0 = st.osum;
        SpinTeam& tm = *team_;
        const int T = tm.size();
        double final_osum = osum0;
        F* final_x = x0;
        tm.run([&](int tid) {
            int lo, hi;
            SpinTeam::chunk(N, T, tid, 64, lo, hi);
            F* a = x0;
            F* b = y0;
            double os = osum0;
            for (int k = 0; k < iterations; ++k) {
                const F m2 = F(2.0 * os / double(N));
                tm.partial<double>(k & 1, tid) = slice(a, b, sg, m2, lo, hi);
                tm.barrier(tid);
                os = tm.sum_partials<double>(k & 1);
                std::swap(a, b);
            }
            if (tid == 0) { final_osum = os; final_x = a; }
        });
        st.osum = final_osum;
        if (final_x != st.a.data()) st.a.swap(scratch_);
    }

    // One member's slice of an iteration; same arithmetic as iterate().
    __attribute__((noinline)) static double slice(const F* __restrict in, F* __restrict out,
                                                  const F* __restrict sg, F m2, int lo, int hi) {
        double acc = 0;
#pragma omp simd reduction(+ : acc)
        for (int i = lo; i < hi; ++i) {
            F o = m2 - sg[i] * in[i];
            out[i] = o;
            acc += double(sg[i] * o);
        }
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
        double run = 0;
        for (int g = 0; g < GROUPS; ++g) {
            double s = 0;
            const F* p = st.a.data() + g * GSIZE;
#pragma omp simd reduction(+ : s)
            for (int i = 0; i < GSIZE; ++i) s += double(p[i]) * double(p[i]);
            run += s;
            c.group_cdf[g] = run;
        }
        c.total = run;
    }

    int sample(const State& st, const Cdf& c, MeasRandomSource& rng, int64_t& threshold) const {
        threshold = -1;
        double t = rng.draw_unit() * c.total;
        int g = int(std::upper_bound(c.group_cdf.begin(), c.group_cdf.end(), t) - c.group_cdf.begin());
        if (g >= GROUPS) g = GROUPS - 1;
        double cum = g ? c.group_cdf[g - 1] : 0.0;
        const F* p = st.a.data() + g * GSIZE;
        for (int i = 0; i < GSIZE; ++i) {
            cum += double(p[i]) * double(p[i]);
            if (cum > t) return g * GSIZE + i;
        }
        return g * GSIZE + GSIZE - 1;
    }

private:
    std::vector<F> scratch_;
    std::unique_ptr<SpinTeam> team_;
};

}  // namespace grover
