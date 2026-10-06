// checkpoint_policy.hpp : restricted-B rolling K/H checkpoint policy and the all-j library,
// shared by the RTL-exact model (B) and the SW float model with policy (A2).
//
// Line-by-line port of checkpoint_bbht_model.py:
//   _deposit_options, _next_states, _window_cost (memoized), _select_policy_action,
//   V098CheckpointReference.execute, V098AllJCheckpointReference.execute.
// The policy only decides WHICH states are kept and from where a request is
// resumed. It never changes the requested j, so logical BBHT results are
// identical to Normal; only the physical Grover work changes.
#pragma once

#include <algorithm>
#include <climits>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

#include "q14_contract.hpp"

namespace grover {

using Positions = std::vector<int>;   // always sorted ascending

namespace detail {

// All size-k combinations of `items` in lexicographic index order
// (same order as itertools.combinations).
inline void combinations(const std::vector<int>& items, int k, std::vector<std::vector<int>>& out) {
    std::vector<int> idx(k);
    int n = int(items.size());
    if (k > n) return;
    for (int i = 0; i < k; ++i) idx[i] = i;
    for (;;) {
        std::vector<int> c(k);
        for (int i = 0; i < k; ++i) c[i] = items[idx[i]];
        out.push_back(std::move(c));
        int i = k - 1;
        while (i >= 0 && idx[i] == n - k + i) --i;
        if (i < 0) return;
        ++idx[i];
        for (int j = i + 1; j < k; ++j) idx[j] = idx[j - 1] + 1;
    }
}

inline bool contains(const std::vector<int>& v, int x) {
    return std::find(v.begin(), v.end(), x) != v.end();
}

}  // namespace detail

class PolicySolver {
public:
    PolicySolver(int capacity, int horizon) : capacity_(capacity), horizon_(horizon) {}
    int capacity() const { return capacity_; }
    int horizon() const { return horizon_; }

    // _select_policy_action: returns (source_j, next checkpoint positions).
    std::pair<int, Positions> select(const Positions& held, int request, const std::vector<int>& future) {
        std::vector<int> pool;   // dict.fromkeys((request, *future)) keeps first occurrence order
        pool.push_back(request);
        for (int f : future) if (!detail::contains(pool, f)) pool.push_back(f);
        int source = closest_source(held, request);
        int immediate = request - source;
        long best_cost = LONG_MAX;
        int best_segments = INT_MAX;
        Positions best_state;
        bool have = false;
        Positions chosen = held;
        for (const Positions& state : next_states(held, source, request, pool)) {
            long tail = window_cost(state, future, 0, pool);
            int segments = 1;
            for (int v : state) if (source < v && v < request) ++segments;
            long cost = immediate + tail;
            // Root-only tie-break (grover_policy.v): (total cost, segments, sorted S').
            bool better = !have || cost < best_cost ||
                          (cost == best_cost && (segments < best_segments ||
                           (segments == best_segments && state < best_state)));
            if (better) {
                have = true;
                best_cost = cost; best_segments = segments; best_state = state;
                chosen = state;
            }
        }
        return {source, chosen};
    }

    static int closest_source(const Positions& held, int request) {
        int s = 0;
        for (int v : held) if (v <= request) s = std::max(s, v);
        return s;
    }

private:
    int capacity_, horizon_;
    std::unordered_map<std::string, int> memo_;

    std::vector<Positions> deposit_options(int source, int request, const std::vector<int>& pool,
                                           const Positions& held) const {
        std::vector<int> in_path;
        for (int v : pool)
            if (source < v && v < request && !detail::contains(held, v) && !detail::contains(in_path, v))
                in_path.push_back(v);
        std::sort(in_path.begin(), in_path.end());
        std::vector<Positions> options{{request}};
        for (int size = 1; size < capacity_; ++size) {
            if (size > int(in_path.size())) break;
            std::vector<std::vector<int>> combos;
            detail::combinations(in_path, size, combos);
            for (auto& c : combos) {
                c.push_back(request);
                std::sort(c.begin(), c.end());
                options.push_back(c);
            }
        }
        return options;
    }

    std::vector<Positions> next_states(const Positions& held, int source, int request,
                                       const std::vector<int>& pool) const {
        std::vector<Positions> result;
        std::vector<int> keep_pool;
        for (int v : held) if (v != request) keep_pool.push_back(v);
        for (const Positions& deposit : deposit_options(source, request, pool, held)) {
            int room = capacity_ - int(deposit.size());
            if (room <= 0) {
                result.push_back(deposit);
            } else if (int(keep_pool.size()) <= room) {
                Positions s = keep_pool;
                s.insert(s.end(), deposit.begin(), deposit.end());
                std::sort(s.begin(), s.end());
                result.push_back(s);
            } else {
                std::vector<std::vector<int>> keeps;
                detail::combinations(keep_pool, room, keeps);
                for (auto& k : keeps) {
                    Positions s = k;
                    s.insert(s.end(), deposit.begin(), deposit.end());
                    std::sort(s.begin(), s.end());
                    result.push_back(s);
                }
            }
        }
        std::sort(result.begin(), result.end());
        result.erase(std::unique(result.begin(), result.end()), result.end());
        return result;
    }

    // _window_cost(capacity, held, window[offset:], pool), memoized.
    long window_cost(const Positions& held, const std::vector<int>& window, size_t offset,
                     const std::vector<int>& pool) {
        if (offset >= window.size()) return 0;
        std::string key;
        key.reserve(32);
        for (int v : held) key.push_back(char(v));
        key.push_back(char(-1));
        for (size_t i = offset; i < window.size(); ++i) key.push_back(char(window[i]));
        key.push_back(char(-2));
        for (int v : pool) key.push_back(char(v));
        auto it = memo_.find(key);
        if (it != memo_.end()) return it->second;
        int request = window[offset];
        int source = closest_source(held, request);
        long immediate = request - source;
        long best = LONG_MAX;
        for (const Positions& state : next_states(held, source, request, pool))
            best = std::min(best, immediate + window_cost(state, window, offset + 1, pool));
        memo_.emplace(std::move(key), int(best));
        return best;
    }
};

// ---------------------------------------------------------------------------
// Checkpoint executors, generic over an engine core.
//
// Core must provide:
//   using State;
//   void reset_state(State&) const;                       // uniform superposition
//   void run(State&, int iterations, int64_t& compute_ns); // Grover iterations in place
//   void step(const State& in, State& out, int64_t& compute_ns); // one iteration
// ---------------------------------------------------------------------------
template <class Core>
class KHCheckpoint {
public:
    using State = typename Core::State;
    KHCheckpoint(int capacity, int horizon) : solver_(capacity, horizon) {}
    int horizon() const { return solver_.horizon(); }
    void invalidate() { slots_.clear(); }

    Positions positions() const {
        Positions p;
        for (auto& s : slots_) p.push_back(s.first);
        std::sort(p.begin(), p.end());
        return p;
    }

    // Returns the state at requested_j; sets physical iterations and source_j.
    const State& execute(Core& core, int requested, const std::vector<int>& future,
                         int& physical, int& source_out, int64_t& compute_ns) {
        Positions before = positions();
        std::vector<int> fut(future.begin(), future.begin() + std::min<size_t>(future.size(), solver_.horizon()));
        auto [source, next_positions] = solver_.select(before, requested, fut);
        if (State* hit = find(requested)) {   // exact hit: measure the stored state
            physical = 0; source_out = requested;
            return *hit;
        }
        if (State* src = find(source)) work_ = *src; else core.reset_state(work_);
        std::vector<std::pair<int, State>> generated;
        if (detail::contains(next_positions, 0) && !find(0)) {
            State init; core.reset_state(init);
            generated.emplace_back(0, std::move(init));
        }
        int cursor = source;
        for (int b : next_positions) {
            if (find(b) || !(source < b && b <= requested)) continue;
            core.run(work_, b - cursor, compute_ns);
            generated.emplace_back(b, work_);
            cursor = b;
        }
        if (cursor != requested) throw std::runtime_error("checkpoint policy did not reach requested j");
        std::vector<std::pair<int, State>> new_slots;   // old slots are discarded: move, don't copy
        for (int p : next_positions) {
            if (State* s = find(p)) { new_slots.emplace_back(p, std::move(*s)); continue; }
            bool ok = false;
            for (auto& g : generated) if (g.first == p) { new_slots.emplace_back(p, std::move(g.second)); ok = true; break; }
            if (!ok) throw std::runtime_error("missing checkpoint state");
        }
        slots_ = std::move(new_slots);
        physical = requested - source;
        source_out = source;
        return work_;
    }

private:
    PolicySolver solver_;
    std::vector<std::pair<int, State>> slots_;
    State work_;
    State* find(int j) {
        for (auto& s : slots_) if (s.first == j) return &s.second;
        return nullptr;
    }
};

// Keeps every materialized state (V098AllJCheckpointReference). SW memory makes
// this cheap: 128 states x 128 KB (float64) = 16 MB.
template <class Core>
class AllJCheckpoint {
public:
    using State = typename Core::State;
    void invalidate() { top_ = 0; have_.assign(128, 0); }
    AllJCheckpoint() : lib_(128), have_(128, 0) {}

    // Returns index into the library; the caller measures lib(j).
    const State& execute(Core& core, int requested, int& physical, int& source_out,
                         int64_t& compute_ns, bool& fresh) {
        if (!have_[0]) { core.reset_state(lib_[0]); have_[0] = 1; top_ = 0; }
        if (requested <= top_) {
            physical = 0; source_out = requested; fresh = false;
            return lib_[requested];
        }
        int source = top_;
        for (int j = top_; j < requested; ++j) {
            core.step(lib_[j], lib_[j + 1], compute_ns);   // one iteration, out of place
            have_[j + 1] = 1;
        }
        top_ = requested;
        physical = requested - source; source_out = source; fresh = true;
        return lib_[requested];
    }

private:
    std::vector<State> lib_;
    std::vector<uint8_t> have_;
    int top_ = 0;
};

}  // namespace grover
