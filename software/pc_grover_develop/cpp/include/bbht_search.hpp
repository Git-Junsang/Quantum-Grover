// bbht_search.hpp : the BBHT search loop shared by every C++ core.
//
//   Engine<Core> = j draw -> policy (NORMAL / K3H3 / K4H4 / ALLJ) -> core iterations
//   -> measurement -> stop rules (SUCCESS, then shot cap 100, then logical budget 576),
//   exactly V098AutomaticCore._run_episode in checkpoint_bbht_model.py.
#pragma once

#include <string>
#include <vector>

#include "q14_contract.hpp"
#include "checkpoint_policy.hpp"

namespace grover {

enum class Policy { NORMAL, K4H4, K3H3, ALLJ };

inline Policy parse_policy(const std::string& s) {
    if (s == "normal") return Policy::NORMAL;
    if (s == "k4h4") return Policy::K4H4;
    if (s == "k3h3") return Policy::K3H3;
    if (s == "allj") return Policy::ALLJ;
    throw std::invalid_argument("policy must be normal, k4h4, k3h3 or allj");
}
inline const char* policy_name(Policy p) {
    switch (p) {
        case Policy::NORMAL: return "normal";
        case Policy::K4H4: return "k4h4";
        case Policy::K3H3: return "k3h3";
        default: return "allj";
    }
}

template <class Core>
class Engine {
public:
    using State = typename Core::State;
    using Cdf = typename Core::Cdf;

    template <class... Args>
    Engine(Policy policy, const std::vector<uint8_t>& mask, Args&&... core_args)
        : policy_(policy), mask_(mask), core_(mask, std::forward<Args>(core_args)...),
          kh_(policy == Policy::K4H4 ? 4 : 3, policy == Policy::K4H4 ? 4 : 3),
          cdf_cache_(128), cdf_valid_(128, 0) {}

    Core& core() { return core_; }

    // _run_episode of V098AutomaticCore.run_single (single search, no enumeration).
    // keep_states = true keeps the all-j state library (and its CDFs) from the
    // previous search: the DRAM build keeps its amplitude table until the
    // dataset or oracle changes ("dram session", actual_iter_dram_session).
    SearchResult search(uint32_t seed_j, uint32_t seed_meas, int shot_cap = DEFAULT_SHOT_CAP,
                        bool trace = false, bool keep_states = false) {
        SearchResult r;
        JRandomSource js(seed_j);
        MeasRandomSource ms(seed_meas);
        kh_.invalidate();
        if (!keep_states) {
            allj_.invalidate();
            std::fill(cdf_valid_.begin(), cdf_valid_.end(), 0);
        }
        int round = 0, episode_l = 0;
        for (;;) {
            int requested = js.draw_uniform(m_bound_for_round(round));
            int physical = requested, source = 0;
            const State* st = nullptr;
            const Cdf* cdf = nullptr;
            if (policy_ == Policy::NORMAL) {
                core_.reset_state(work_);
                core_.run(work_, requested, r.compute_ns);
                st = &work_;
            } else if (policy_ == Policy::ALLJ) {
                bool fresh = false;
                st = &allj_.execute(core_, requested, physical, source, r.compute_ns, fresh);
                if (cdf_valid_[requested]) cdf = &cdf_cache_[requested];
                else { core_.prepare(*st, cdf_cache_[requested]); cdf_valid_[requested] = 1; cdf = &cdf_cache_[requested]; }
            } else {
                std::vector<int> future = predict_future_j(js, round + 1, kh_.horizon());
                st = &kh_.execute(core_, requested, future, physical, source, r.compute_ns);
            }
            if (!cdf) { core_.prepare(*st, cdf_); cdf = &cdf_; }
            int64_t threshold = -1;
            int index = core_.sample(*st, *cdf, ms, threshold);
            bool success = index >= 0 && mask_[index];
            episode_l += requested;
            r.L_BBHT += requested;
            r.physical_iterations += physical;
            r.trial_count += 1;
            if (trace) r.attempts.push_back({requested, source, physical, threshold, index, success});
            if (success) { r.success = true; r.termination = Termination::SUCCESS; r.result_index = index; break; }
            if (r.trial_count >= shot_cap) { r.termination = Termination::SHOT_LIMIT; break; }
            if (episode_l + 1 >= LOGICAL_BUDGET) { r.termination = Termination::BUDGET_LIMIT; break; }
            round = std::min<int>(round + 1, int(M_BOUNDS.size()) - 1);
        }
        return r;
    }

private:
    Policy policy_;
    std::vector<uint8_t> mask_;
    Core core_;
    KHCheckpoint<Core> kh_;
    AllJCheckpoint<Core> allj_;
    State work_;
    Cdf cdf_;
    std::vector<Cdf> cdf_cache_;
    std::vector<uint8_t> cdf_valid_;
};


}  // namespace grover
