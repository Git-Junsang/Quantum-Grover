#pragma once
#include "Vbbht_rvx_wrapper___024root.h"
#include <cstdint>
#include <cstdio>
#include <map>
#include <string>

// Read-only, settled-state observer for this K3/H3 Common500 build. The RTL
// archive is unchanged; only the C++ harness includes this sampling function.
struct PolicyProfile {
    std::map<std::string,uint64_t> counters;
    unsigned seed_ids[9] = {};
    bool seed_valid[9] = {};
    void add(const std::string& name,uint64_t n=1) { counters[name]+=n; }
    ~PolicyProfile() {
        for (const auto& entry:counters)
            std::fprintf(stderr,"PROFILE,%s,%llu\n",entry.first.c_str(),
                         static_cast<unsigned long long>(entry.second));
    }
};
static PolicyProfile profile;
#define M(name) r->bbht_rvx_wrapper__DOT__u_core__DOT__u_main_ip__DOT__##name
#define P(name) r->bbht_rvx_wrapper__DOT__u_core__DOT__u_main_ip__DOT__g_ckpt_plan_exec__DOT__g_auto_policy_k34__DOT__u_auto_policy__DOT__##name

static void profile_sample(Vbbht_rvx_wrapper* top) {
    if (!top->rstnn) return;
    auto* r=top->rootp;
    const bool active=M(run_ckpt_auto_mode) && M(search_busy);
    if (active) {
        profile.add("run.cycles");
        const unsigned ap=M(auto_policy_state);
        profile.add("scheduler.state."+std::to_string(ap));
        profile.add("fifo.level."+std::to_string(M(planq_level)));
        if (M(bbht_iter_start)) profile.add("demand.count");
        if (M(auto_policy_start_cold)) profile.add("start.cold");
        if (M(auto_policy_start_spec)) profile.add("start.spec");
        if (M(planq_push)) profile.add("fifo.push");
        if (M(planq_pop)) profile.add("fifo.pop");
        if (ap==1) {
            if (M(planq_head_match)) profile.add("demand.fifo_hit");
            else if (M(spec_inflight_match)) profile.add("demand.matching_inflight");
            else profile.add("demand.cold");
        }
        if (ap==2) {
            if (!M(auto_shadow1_ready)) profile.add("cold_wait.shadow_not_ready");
            if (M(auto_shadow1_ready) && !M(auto_policy_busy)) profile.add("cold_wait.ready_transition");
        }
        if (ap>=1 && ap<=5) {
            profile.add("stall.sampled");
            if (M(auto_policy_busy)) {
                profile.add("stall.solver_busy");
                profile.add("stall.solver_state."+std::to_string(P(fsm_state)));
                if (M(policy_active_plan_epoch)!=M(auto_plan_epoch)) profile.add("stall.stale_solver_busy");
            } else profile.add("stall.no_solver_busy");
        }
    }
    if (M(auto_policy_done)) {
        profile.add("solver.done_all");
        if (M(policy_active_plan_epoch)!=M(auto_plan_epoch)) {
            profile.add("solver.done_stale");
            profile.add("solver.done_stale_cycles",M(auto_policy_cycles_last));
        }
    }
    if (!M(auto_policy_busy)) return;
    profile.add("solver.busy_all");
    const unsigned state=P(fsm_state), depth=P(sp);
    profile.add("solver.state."+std::to_string(state));
    if (state==2 && P(build_idx)==0) {
        // early_root_single was inlined by Verilator. Recompute it from the
        // immutable input snapshot for classification, without touching RTL.
        const unsigned mask=P(in_slot_valid), flat=P(in_slot_j_flat);
        const uint64_t window=P(in_window_flat);
        const unsigned j=window & 127;
        unsigned held[4], count=0, pred=0;
        bool endpoint=false, duplicate=false, extra=false;
        for (unsigned i=0;i<4;++i) if (mask&(1u<<i)) {
            const unsigned v=(flat>>(7*i))&127;
            for (unsigned p=0;p<count;++p) duplicate|=held[p]==v;
            held[count++]=v; endpoint|=v==j;
            if (v<=j && v>pred) pred=v;
        }
        for (unsigned t=1;t<=3;++t) {
            const unsigned v=(window>>(7*t))&127;
            bool present=false;
            for (unsigned p=0;p<count;++p) present|=held[p]==v;
            extra|=!present && v>pred && v<j;
        }
        if (!duplicate && !extra && count<=3 && count+!endpoint<=3)
            profile.add("solver.early_single");
    }
    if (state==8) {
        profile.seed_valid[depth]=false;
        if (P(prep_two_left)) profile.add("solver.exact_two_request_suffix");
    }
    if (state==9 && P(a_phase)==1 && P(seed_return_optimal))
        profile.add("solver.certificate.return.depth."+std::to_string(depth));
    if (P(cache_read_en)) profile.add("solver.cache.reads");
    if (P(cache_walk_fire) && P(cache_read_en)) profile.add("solver.cache.overlapped_reads");
    if (state!=4) return;
    if (P(bound_capture)) profile.add("solver.scan.batch."+std::to_string(P(scan_input_count)));
    if (P(a_phase)==1 && P(mresp_valid) && P(memo_pipe_hit) && P(seed_hit_optimal))
        profile.add("solver.certificate.hit.depth."+std::to_string(depth));
    if (P(top_terminal)) { profile.add("solver.run.terminal"); return; }
    const unsigned phase=P(a_phase);
    if (phase==0) profile.add(P(a_gen_valid)?"solver.run.scan_issue":"solver.run.scan_drain");
    else if (phase==1) profile.add("solver.run.seed_wait");
    else if (P(cache_walk_fire)) {
        profile.add("solver.run.canon_filter");
        profile.add("solver.cache.pruned",P(cache_pruned_count));
        profile.add("solver.cache.pruned_batch."+std::to_string(P(cache_pruned_count)));
    } else if (P(cache_read_en)) profile.add("solver.run.cache_fetch");
    else if (P(mresp_valid)) profile.add("solver.run.canon_memo_response");
    else profile.add("solver.run.canon_finish");
    if (P(mresp_valid)) {
        if (!P(memo_pipe_hit)) {
            profile.add("solver.memo_miss");
            profile.add("solver.flush_younger_packets",__builtin_popcount(unsigned(P(scan_valid0)))+
                __builtin_popcount(unsigned(P(scan_valid1)))+__builtin_popcount(unsigned(P(scan_valid2))));
        } else profile.add("solver.memo_hit_or_direct");
    }
    if (P(seed_issue_from_scan)) {
        profile.seed_valid[depth]=true; profile.seed_ids[depth]=P(seed_issue_ids);
    }
    if (phase==2 && P(seed_memo_issue)) {
        profile.add("solver.canonical_memo_requests");
        if (profile.seed_valid[depth] && profile.seed_ids[depth]==P(seed_issue_ids))
            profile.add("solver.canonical_seed_replay");
    }
    if (P(scan_valid2) && (!P(mresp_valid)||P(memo_pipe_hit))) profile.add("solver.bound_outputs",P(scan_output_count));
}
#undef P
#undef M
