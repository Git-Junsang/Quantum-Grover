#pragma once
#include "Vbbht_rvx_wrapper___024root.h"
#include <cstdint>
#include <cstdio>
#include <map>
#include <string>

// Observation only: sample the settled model immediately before each rising
// edge. No RTL inputs or internal model fields are written by this monitor.
struct PolicyProfile {
    std::map<std::string, uint64_t> counters;
    unsigned seed_ids[9] = {};
    bool seed_valid[9] = {};
    void add(const std::string& name, uint64_t n = 1) { counters[name] += n; }
    ~PolicyProfile() {
        for (const auto& item : counters)
            std::fprintf(stderr, "PROFILE,%s,%llu\n", item.first.c_str(),
                         static_cast<unsigned long long>(item.second));
    }
};
static PolicyProfile profile;

#define M(name) r->bbht_rvx_wrapper__DOT__u_core__DOT__u_main_ip__DOT__##name
#define P(name) r->bbht_rvx_wrapper__DOT__u_core__DOT__u_main_ip__DOT__g_ckpt_plan_exec__DOT__g_auto_policy_k34__DOT__u_auto_policy__DOT__##name

static void profile_sample(Vbbht_rvx_wrapper* top) {
    if (!top->rstnn) return;
    auto* r = top->rootp;
    const bool active = M(run_ckpt_auto_mode) && M(search_busy);
    if (active) {
        profile.add("run.cycles");
        const unsigned ap = M(auto_policy_state);
        profile.add("scheduler.state." + std::to_string(ap));
        profile.add("fifo.level." + std::to_string(M(planq_level)));
        if (M(bbht_iter_start)) profile.add("demand.count");
        if (M(auto_policy_start_cold)) profile.add("start.cold");
        if (M(auto_policy_start_spec)) profile.add("start.spec");
        if (M(planq_push)) profile.add("fifo.push");
        if (M(planq_pop)) profile.add("fifo.pop");
        if (M(auto_context_restart)) profile.add("context.restart");
        if (M(planq_check_state) && !M(planq_empty) && !M(planq_head_match))
            profile.add("context.nonempty_mismatch");
        if (ap == 1) {
            if (M(planq_head_match)) profile.add("demand.fifo_hit");
            else if (M(spec_inflight_match)) profile.add("demand.matching_inflight");
            else profile.add("demand.cold");
        }
        if (ap == 2) {
            if (!M(auto_shadow1_ready)) profile.add("cold_wait.shadow_not_ready");
            if (M(auto_policy_busy)) profile.add("cold_wait.solver_busy");
            if (M(auto_shadow1_ready) && !M(auto_policy_busy)) profile.add("cold_wait.ready_transition");
        }
        const bool demand_wait = (ap >= 1 && ap <= 5);
        if (demand_wait) {
            profile.add("stall.sampled");
            if (M(auto_policy_busy)) {
                profile.add("stall.solver_busy");
                profile.add("stall.solver_state." + std::to_string(P(fsm_state)));
                if (P(fsm_state) == 4)
                    profile.add("stall.solver_phase." + std::to_string(P(a_phase)));
                if (M(policy_active_plan_epoch) != M(auto_plan_epoch))
                    profile.add("stall.stale_solver_busy");
            } else profile.add("stall.no_solver_busy");
        }
        // This is opportunity time, not a proven number of recoverable cycles:
        // every registered launch input is ready, but the one-per-demand guard
        // prevents launching another speculative root.
        if (ap == 7 && !M(auto_policy_busy) && M(auto_spec_state) == 0 &&
            M(auto_current_plan_valid) && M(auto_shadow1_ready) &&
            M(spec_launched_for_demand) && !M(planq_full))
            profile.add("scheduler.idle_after_one_spec");
    }
    if (M(auto_policy_done)) {
        profile.add("solver.done_all");
        if (M(policy_active_plan_epoch) != M(auto_plan_epoch)) {
            profile.add("solver.done_stale");
            profile.add("solver.done_stale_cycles", M(auto_policy_cycles_last));
        }
    }
    if (!M(auto_policy_busy)) return;
    profile.add("solver.busy_all");
    if (M(policy_active_is_spec)) profile.add("solver.busy_spec");
    const unsigned state = P(fsm_state);
    const unsigned depth = P(sp);
    profile.add("solver.state." + std::to_string(state));
    if (active) profile.add("solver.busy_in_run");
    if (state == 8 && depth < 9) profile.seed_valid[depth] = false;
    if (state != 4) return;
    if (P(root_single_action)) {
        profile.add("solver.root_single_candidate");
        profile.add("solver.run.root_single");
        return;
    }
    if (P(top_terminal)) {
        profile.add("solver.run.terminal");
        return;
    }
    const unsigned phase = P(a_phase);
    // These combinational wires were optimized away by Verilator. Derive
    // them from settled registers without writing any model state.
    const unsigned generator_key = (unsigned(P(a_rmask)) << 14) |
        (unsigned(P(a_rsize)) << 11) | (unsigned(P(a_dmask)) << 2) | unsigned(P(a_dsize));
    const bool seed_repeat = phase == 2 && P(a_gen_valid) && generator_key == P(a_seed_pre);
    if (seed_repeat) profile.add("solver.canonical_seed_skip");
    if (P(a_gen_valid) && (phase == 0 || phase == 2) && !seed_repeat)
        profile.add("solver.bound_capture");
    const bool issuing = P(a_gen_valid) && (phase == 0 || phase == 2);
    if (phase == 0) profile.add(issuing ? "solver.run.scan_issue" : "solver.run.scan_drain");
    else if (phase == 1) profile.add("solver.run.seed_wait");
    else profile.add(issuing ? "solver.run.canon_issue" : "solver.run.canon_drain");
    if (P(mresp_valid)) {
        if (!P(memo_pipe_hit)) {
            profile.add("solver.memo_miss");
            const unsigned younger = __builtin_popcount(unsigned(P(bp_v))) + unsigned(P(bo_v));
            profile.add("solver.flush_events");
            profile.add("solver.flush_younger_packets", younger);
        } else {
            profile.add("solver.memo_hit_or_direct");
            if (P(mresp_direct)) profile.add("solver.direct_result");
            else profile.add("solver.real_memo_hit");
        }
    }
    if (P(seed_issue_from_scan) && depth < 9) {
        profile.seed_ids[depth] = P(seed_issue_ids);
        profile.seed_valid[depth] = true;
        if (depth == 0 && !P(scan_multi)) profile.add("solver.root_single_candidate");
    }
    if (P(bo_v) && !P(bo_kind) && (!P(mresp_valid) || P(memo_pipe_hit))) {
        profile.add("solver.canonical_bound_outputs");
        if (depth < 9 && profile.seed_valid[depth] && P(bo_ids) == profile.seed_ids[depth])
            profile.add("solver.canonical_seed_replay");
    }
}
#undef P
#undef M
