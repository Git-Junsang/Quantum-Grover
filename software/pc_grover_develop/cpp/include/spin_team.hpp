// spin_team.hpp : persistent worker team for intra-iteration parallelism (the SW
// counterpart of the RTL E4 option: one Grover iteration split over several
// compute units).
//
// Why not OpenMP: an OpenMP parallel region per run() plus a work-shared loop
// with a reduction costs several barriers (and thread wake-ups) per iteration.
// At N = 16384 one iteration is only a few microseconds, so that overhead grew
// with the thread count and made 8 threads ~7x slower than 1 (server, E-cores).
//
// This team is created once per engine and lives for the whole campaign:
//   * T-1 worker threads spin on a job counter (no sleep, no futex wake-up);
//     the calling thread is member 0.
//   * one sense-reversing spin barrier per Grover iteration;
//   * per-thread partial sums in padded slots, double-buffered by iteration
//     parity, summed in fixed order 0..T-1 by every member (deterministic for
//     a given T; exact for the integer RTL core).
//   * members are pinned to consecutive CPUs of the process affinity mask read
//     at program start (member t -> t-th allowed CPU), like OMP_PROC_BIND=close;
//     the calling thread's own mask is restored when the team is destroyed.
// Idle workers keep spinning between runs: latency mode owns its cores.
#pragma once

#include <pthread.h>
#include <sched.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <stdexcept>
#include <string>
#include <thread>
#include <type_traits>
#include <vector>

#if defined(__x86_64__) || defined(__i386__)
#include <immintrin.h>
#define GROVER_CPU_RELAX() _mm_pause()
#else
#define GROVER_CPU_RELAX() ((void)0)
#endif

namespace grover {

namespace detail {
// CPUs the process may use, read once at program start (before any member is
// pinned). Reading it later from a pinned thread would return just that CPU.
inline std::vector<int> read_affinity() {
    std::vector<int> out;
    cpu_set_t set;
    CPU_ZERO(&set);
    if (sched_getaffinity(0, sizeof(set), &set) == 0)
        for (int c = 0; c < CPU_SETSIZE; ++c)
            if (CPU_ISSET(c, &set)) out.push_back(c);
    return out;
}
inline const std::vector<int> kProcessCpus = read_affinity();
}  // namespace detail

class SpinTeam {
public:
    explicit SpinTeam(int n) : n_(n < 1 ? 1 : n), partial_(2 * size_t(n_)), cpus_(detail::kProcessCpus) {
        if (!cpus_.empty() && size_t(n_) > cpus_.size())
            throw std::invalid_argument("--threads " + std::to_string(n_) + " needs " + std::to_string(n_) +
                                        " CPUs, but only " + std::to_string(cpus_.size()) +
                                        " are available (spinning members must not share a CPU)");
        CPU_ZERO(&caller_mask_);
        sched_getaffinity(0, sizeof(caller_mask_), &caller_mask_);   // restored in the destructor
        pin(0);
        for (int t = 1; t < n_; ++t) workers_.emplace_back([this, t] { worker(t); });
    }
    ~SpinTeam() {
        stop_.store(true, std::memory_order_release);
        job_gen_.fetch_add(1, std::memory_order_acq_rel);
        for (auto& w : workers_) w.join();
        pthread_setaffinity_np(pthread_self(), sizeof(caller_mask_), &caller_mask_);
    }
    SpinTeam(const SpinTeam&) = delete;
    SpinTeam& operator=(const SpinTeam&) = delete;

    int size() const { return n_; }

    // Run body(tid) on every member (caller = member 0) and wait for all.
    void run(const std::function<void(int)>& body) {
        job_ = &body;
        job_gen_.fetch_add(1, std::memory_order_acq_rel);
        body(0);
        barrier(0);                       // join: every member finished the job
    }

    // Sense-reversing barrier; call with the member's tid.
    void barrier(int tid) {
        int s = sense_[tid].v ^= 1;
        if (arrived_.fetch_add(1, std::memory_order_acq_rel) == n_ - 1) {
            arrived_.store(0, std::memory_order_relaxed);
            release_.store(s, std::memory_order_release);
        } else {
            while (release_.load(std::memory_order_acquire) != s) GROVER_CPU_RELAX();
        }
    }

    // Partial sums: slot (parity, tid). Members write their own slot, barrier,
    // then everyone reads all slots of that parity.
    template <class T>
    T& partial(int parity, int tid) { return get<T>(partial_[size_t(parity) * n_ + tid]); }
    template <class T>
    T sum_partials(int parity) {
        T s = 0;
        for (int t = 0; t < n_; ++t) s += get<T>(partial_[size_t(parity) * n_ + t]);
        return s;
    }

    // Static block partition of [0, n) for member tid, aligned to `align` elements.
    static void chunk(int n, int members, int tid, int align, int& lo, int& hi) {
        int blocks = n / align;
        int b0 = int(int64_t(blocks) * tid / members), b1 = int(int64_t(blocks) * (tid + 1) / members);
        lo = b0 * align;
        hi = (tid == members - 1) ? n : b1 * align;
    }

private:
    struct alignas(64) Slot { union { int64_t i; double d; }; char pad[64 - sizeof(int64_t)]; };
    template <class T>
    static T& get(Slot& s) {
        static_assert(std::is_same<T, int64_t>::value || std::is_same<T, double>::value, "int64_t or double");
        if constexpr (std::is_same<T, double>::value) return s.d; else return s.i;
    }
    struct alignas(64) Flag { int v = 0; char pad[64 - sizeof(int)]; };

    int n_;
    std::vector<Slot> partial_;
    Flag sense_[256];
    alignas(64) std::atomic<int> arrived_{0};
    alignas(64) std::atomic<int> release_{0};
    alignas(64) std::atomic<uint64_t> job_gen_{0};
    alignas(64) std::atomic<bool> stop_{false};
    const std::function<void(int)>* job_ = nullptr;
    std::vector<std::thread> workers_;
    std::vector<int> cpus_;
    cpu_set_t caller_mask_;

    void worker(int tid) {
        pin(tid);
        uint64_t seen = 0;
        for (;;) {
            uint64_t g;
            while ((g = job_gen_.load(std::memory_order_acquire)) == seen) GROVER_CPU_RELAX();
            seen = g;
            if (stop_.load(std::memory_order_acquire)) return;
            (*job_)(tid);
            barrier(tid);
        }
    }

    void pin(int tid) const {
        if (cpus_.empty()) return;
        cpu_set_t one;
        CPU_ZERO(&one);
        CPU_SET(cpus_[size_t(tid) % cpus_.size()], &one);
        pthread_setaffinity_np(pthread_self(), sizeof(one), &one);
    }
};

}  // namespace grover
