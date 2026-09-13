//==============================================================================
// bbht_grover_main_ip.v -- BBHT/Grover Main IP, parameterized K/H checkpoint execution
//
// Default CHECKPOINT_ENABLE=0 preserves the verified v0.8.x Main-IP datapath.
// CHECKPOINT_ENABLE=1 enables packed checkpoint storage. Runtime
// checkpoint_manual_enable selects the Phase-4B manual policy path:
// external canonical (source_j,S') -> Planner -> Executor -> real Grover datapath.
// Phase-6C keeps the exact same K4/restricted-B/Rolling-H6 policy semantics
// and the V8 Shadow-J + plan-FIFO overlap, then enables that autonomous path
// inside Enumeration.  A unique result changes found_mask and therefore the
// Oracle: checkpoint metadata is invalidated and speculative plans are flushed.
// A failed BBHT segment with unchanged found_mask preserves checkpoint state,
// but starts a fresh BBHT control segment; its speculative continuation is
// flushed because the BBHT round/m context restarts even though the Oracle does
// not. The production autonomous planner is internally pipelined
// (metadata/predecessor -> boundary/slot allocation) by one additional cycle.
// No timing optimization changes requested-j, trial, L_BBHT, physical work,
// checkpoint semantics, policy tie-break, or RNG rules.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module bbht_grover_main_ip #(
    parameter integer CHECKPOINT_ENABLE = 0,
    parameter integer CKPT_K            = 4,
    // Rolling-policy lookahead.  Default 4 preserves frozen K4/H4.
    // E4 K3/H3 branch sets POLICY_H_FUTURE=3.
    parameter integer POLICY_H_FUTURE    = 4,
    // 1 keeps the Phase-4B manual checkpoint-policy injection path.
    // 0 compile-time removes that verification-only path and its wide
    // manual/auto select cone from the production autonomous K4/H6 build.
    parameter integer CKPT_MANUAL_ENABLE = 1,
    // 0 reproduces the Phase-6A V7 demand-driven cold policy behavior.
    // 1 enables Phase-6B V8 one-shot-ahead Shadow-J + plan-FIFO overlap.
    parameter integer AUTO_SPEC_ENABLE  = 1,
    // E2 branch default: two P=32 engines cooperate inside each physical
    // Grover iteration. Set to 1 to reproduce the frozen physical kernel.
    parameter integer INTRA_ENGINES     = 1,
    // Paper-ablation measurement controls.
    // M1: E4 two-row/cycle Born BUILD.
    // M2: M1 + hierarchical 16x32 row selection.
    parameter integer MEAS_M1_ENABLE    = 1,
    parameter integer MEAS_M2_ENABLE    = 1
) (
    input  wire                                  clk,
    input  wire                                  rstn,

    // Search control.
    input  wire                                  start,
    input  wire                                  auto_shot,
    input  wire [`GP_J_W-1:0]                   j_target,
    input  wire                                  burst_enable,
    input  wire                                  enum_enable,
    input  wire [`GP_ENUM_FAIL_W-1:0]           fail_repeat_limit,

    // Phase-4B manual checkpoint-policy interface.  This path is legal only
    // with CHECKPOINT_ENABLE=1, burst_enable=1, auto_shot=0, enum_enable=0.
    // The policy is slot-agnostic: S' must be canonical/sorted and include j.
    input  wire                                  checkpoint_manual_enable,
    input  wire                                  policy_valid,
    input  wire [`GP_J_W-1:0]                   policy_source_j,
    input  wire [2:0]                            policy_next_count,
    input  wire [4*`GP_J_W-1:0]                 policy_next_j_flat,

    // Phase-6 autonomous checkpoint-policy mode.  Omitted/Z is treated as 0
    // for backward compatibility. Both Single and Enumeration are permitted when
    // CHECKPOINT_ENABLE=1, CKPT_K=4, burst_enable=1, and auto_shot=1.
    input  wire                                  checkpoint_auto_enable,

    // Oracle / verification configuration.
    input  wire [1:0]                            predicate_mode,
    input  wire signed [`GP_DATA_W-1:0]          threshold_a,
    input  wire signed [`GP_DATA_W-1:0]          threshold_b,
    input  wire [`GP_DATA_COUNT_W-1:0]           data_count,

    // BBHT / random configuration.
    input  wire [`GP_SHOT_CAP_W-1:0]             shot_cap,
    input  wire [31:0]                           seed_j,
    input  wire [31:0]                           seed_meas,

    // Generic dataset loader.
    input  wire                                  load_start,
    input  wire                                  data_wr_en,
    input  wire [`GP_INDEX_W-1:0]                data_wr_addr,
    input  wire signed [`GP_DATA_W-1:0]          data_wr_data,
    input  wire                                  load_done,
    output wire                                  load_busy,

    // Result FIFO consumer interface.  RVX wrapper converts FIFO_DATA CSR read
    // completion into a one-cycle res_pop pulse.
    input  wire                                  res_pop,
    output wire [`GP_INDEX_W-1:0]                res_dout,
    output wire                                  res_empty,
    output wire [`GP_RESULT_FIFO_CNT_W-1:0]      res_count,

    // Aggregate execution/result interface.
    output wire                                  busy,
    output wire                                  done,
    output wire                                  result_valid,
    output wire [`GP_INDEX_W-1:0]                result_index,

    // Enumeration status/result summary.
    output reg                                   enum_done,
    output reg  [`GP_FOUND_COUNT_W-1:0]          found_count,
    output reg  [`GP_ENUM_FAIL_W-1:0]            consecutive_fail_count,
    output reg  [`GP_RESULT_FIFO_CNT_W-1:0]      max_fifo_occupancy,
    output reg  [31:0]                           fifo_stall_cycles,

    // Sticky status until next accepted external start.
    output wire                                  config_error,
    output wire                                  shot_limit,
    output wire                                  budget_limit,
    output wire                                  amp_overflow,
    output wire                                  zero_weight_error,
    output wire                                  load_error,

    // Performance counters.  In Enumeration these are run-global totals.
    output wire [31:0]                           trial_count,
    output wire [31:0]                           L_BBHT,
    output wire [31:0]                           actual_grover_iterations,
    output wire [31:0]                           cycle_count,

    // Phase-6 autonomous-policy observability.  These are run-level counters
    // reset on each accepted external start.
    output wire [31:0]                           policy_cycles_total,
    output wire [31:0]                           policy_stall_cycles,
    output wire [31:0]                           policy_actions_eval,
    output wire [31:0]                           policy_memo_hit,
    output wire [31:0]                           policy_memo_miss,
    output wire [31:0]                           policy_max_latency,

    // Speculative-plan observability. These counters do not alter
    // BBHT logical state; they only expose overlap effectiveness.
    output wire [2:0]                            plan_fifo_level,
    output wire [2:0]                            plan_fifo_highwater,
    output wire [31:0]                           plan_fifo_empty_demand,
    output wire [31:0]                           plan_fifo_hit_count,
    output wire [31:0]                           plan_fifo_mismatch_count,
    output wire [31:0]                           policy_cold_solve_count,
    output wire [31:0]                           policy_spec_solve_count
);
    localparam integer AMP_ROW_BITS  = `GP_P * `GP_AMP_W;
    localparam integer DATA_ROW_BITS = `GP_P * `GP_DATA_W;

    // Simulation/backward-compatibility normalization: an omitted legacy
    // enum_enable port appears as Z and is treated as Single Search.  In
    // synthesized 0/1 hardware this is equivalent to enum_enable itself.
    wire enum_request = (enum_enable === 1'b1);
    wire ckpt_manual_request = (CHECKPOINT_ENABLE != 0) &&
                               (CKPT_MANUAL_ENABLE != 0) &&
                               (checkpoint_manual_enable === 1'b1);
    wire ckpt_auto_request = (CHECKPOINT_ENABLE != 0) &&
                             ((CKPT_K == 3) || (CKPT_K == 4)) &&
                             (checkpoint_auto_enable === 1'b1);

    //==========================================================================
    // Loader
    //==========================================================================
    wire loader_mem_wr_en;
    wire [`GP_INDEX_W-1:0] loader_mem_wr_addr;
    wire signed [`GP_DATA_W-1:0] loader_mem_wr_data;
    wire data_valid;
    wire accepted_load_start;
    wire loader_cache_invalidate;
    wire [`GP_DATA_COUNT_W-1:0] load_expected_count;
    wire [`GP_DATA_COUNT_W-1:0] load_write_count;
    wire [`GP_DATA_COUNT_W-1:0] loaded_count;

    // Forward declarations used by loader interlock.
    wire bbht_busy;
    wire bbht_done;
    reg  enum_active;
    reg  enum_terminal_pulse;
    wire search_busy = enum_active | enum_terminal_pulse | bbht_busy | bbht_done;

    // Result FIFO state participates in the external-start interlock.
    wire fifo_full;
    wire fifo_push_accept;
    wire fifo_pop_accept;
    reg  pending_valid;

    wire accepted_start = start && !search_busy && !load_busy &&
                          res_empty && !pending_valid;

    assign busy = search_busy | load_busy;

    grover_loader_ctrl u_loader (
        .clk                 (clk),
        .rstn                (rstn),
        .load_start          (load_start),
        .search_busy         (search_busy),
        .data_count          (data_count),
        .data_wr_en          (data_wr_en),
        .data_wr_addr        (data_wr_addr),
        .data_wr_data        (data_wr_data),
        .load_done           (load_done),
        .mem_wr_en           (loader_mem_wr_en),
        .mem_wr_addr         (loader_mem_wr_addr),
        .mem_wr_data         (loader_mem_wr_data),
        .load_busy           (load_busy),
        .data_valid          (data_valid),
        .load_error          (load_error),
        .accepted_load_start (accepted_load_start),
        .cache_invalidate    (loader_cache_invalidate),
        .expected_count      (load_expected_count),
        .write_count         (load_write_count),
        .loaded_count        (loaded_count)
    );

    //==========================================================================
    // Per-run configuration snapshot
    //==========================================================================
    reg                                  run_enum_mode;
    reg                                  run_auto_shot;
    reg [`GP_J_W-1:0]                   run_j_target;
    reg                                  run_burst_mode;
    reg [1:0]                            run_predicate_mode;
    reg signed [`GP_DATA_W-1:0]          run_threshold_a;
    reg signed [`GP_DATA_W-1:0]          run_threshold_b;
    reg [`GP_DATA_COUNT_W-1:0]           run_data_count;
    reg [`GP_SHOT_CAP_W-1:0]             run_shot_cap;
    reg [`GP_ENUM_FAIL_W-1:0]            run_fail_repeat_limit;
    reg                                  run_ckpt_manual_mode;
    reg                                  run_ckpt_auto_mode;
    reg                                  run_policy_valid;
    reg [`GP_J_W-1:0]                   run_policy_source_j;
    reg [2:0]                            run_policy_next_count;
    reg [4*`GP_J_W-1:0]                 run_policy_next_j_flat;

    always @(posedge clk) begin
        if (!rstn) begin
            run_enum_mode         <= 1'b0;
            run_auto_shot         <= 1'b0;
            run_j_target          <= {`GP_J_W{1'b0}};
            run_burst_mode        <= 1'b0;
            run_predicate_mode    <= `GP_MODE_LT;
            run_threshold_a       <= {`GP_DATA_W{1'b0}};
            run_threshold_b       <= {`GP_DATA_W{1'b0}};
            run_data_count        <= {`GP_DATA_COUNT_W{1'b0}};
            run_shot_cap          <= `GP_SHOT_CAP_DEFAULT;
            run_fail_repeat_limit <= `GP_ENUM_FAIL_DEFAULT;
            run_ckpt_manual_mode  <= 1'b0;
            run_ckpt_auto_mode    <= 1'b0;
            run_policy_valid      <= 1'b0;
            run_policy_source_j   <= {`GP_J_W{1'b0}};
            run_policy_next_count <= 3'd0;
            run_policy_next_j_flat<= {(4*`GP_J_W){1'b0}};
        end else if (accepted_start) begin
            run_enum_mode         <= enum_request;
            run_auto_shot         <= auto_shot;
            run_j_target          <= j_target;
            run_burst_mode        <= burst_enable;
            run_predicate_mode    <= predicate_mode;
            run_threshold_a       <= threshold_a;
            run_threshold_b       <= threshold_b;
            run_data_count        <= data_count;
            run_shot_cap          <= shot_cap;
            run_fail_repeat_limit <= fail_repeat_limit;
            run_ckpt_manual_mode  <= (CKPT_MANUAL_ENABLE != 0) ?
                                     ckpt_manual_request : 1'b0;
            run_ckpt_auto_mode    <= ckpt_auto_request;
            run_policy_valid      <= policy_valid;
            run_policy_source_j   <= policy_source_j;
            run_policy_next_count <= policy_next_count;
            run_policy_next_j_flat<= policy_next_j_flat;
        end
    end

    wire run_data_count_valid =
        (run_data_count != {`GP_DATA_COUNT_W{1'b0}}) &&
        (run_data_count <= `GP_N);
    wire ckpt_plan_valid;
    // Compile-time folded manual-mode view.  With CKPT_MANUAL_ENABLE=0 this
    // becomes constant 0 at elaboration, allowing Vivado to remove the
    // Phase-4B manual/auto mux/select cone from the production timing build.
    wire run_ckpt_manual_active =
        (CKPT_MANUAL_ENABLE != 0) ? run_ckpt_manual_mode : 1'b0;

    wire run_ckpt_modes_exclusive = !(run_ckpt_manual_active && run_ckpt_auto_mode);
    wire run_manual_mode_legal = !run_ckpt_manual_active ||
        (run_burst_mode && !run_auto_shot && !run_enum_mode);
    // The autonomous checkpoint path also supports Enumeration.
    // Enumeration itself still requires auto_shot in E_CONFIG below.
    wire run_auto_mode_legal = !run_ckpt_auto_mode ||
        (run_burst_mode && run_auto_shot &&
         ((CKPT_K == 3) || (CKPT_K == 4)));
    wire run_config_ok = data_valid && run_data_count_valid &&
                         (run_data_count == loaded_count) &&
                         run_ckpt_modes_exclusive &&
                         run_manual_mode_legal && run_auto_mode_legal &&
                         (!run_ckpt_manual_active || ckpt_plan_valid);

    //==========================================================================
    // Cache invalidation: only accepted-run semantic changes affect a running
    // snapshot.  Live SW writes during busy do not alter the current run.
    //==========================================================================
    reg                                    accepted_cfg_seen;
    reg                                    prev_enum_mode;
    reg                                    prev_ckpt_manual_mode;
    reg                                    prev_ckpt_auto_mode;
    reg [1:0]                              prev_predicate_mode;
    reg signed [`GP_DATA_W-1:0]            prev_threshold_a;
    reg signed [`GP_DATA_W-1:0]            prev_threshold_b;
    reg [`GP_DATA_COUNT_W-1:0]             prev_data_count;

    wire semantic_cfg_change_on_start = accepted_start && accepted_cfg_seen &&
        ((predicate_mode != prev_predicate_mode) ||
         (threshold_a    != prev_threshold_a)    ||
         (threshold_b    != prev_threshold_b)    ||
         (data_count     != prev_data_count));
    wire mode_change_on_start = accepted_start && accepted_cfg_seen &&
                                (enum_request != prev_enum_mode);
    wire manual_mode_change_on_start = accepted_start && accepted_cfg_seen &&
                                (ckpt_manual_request != prev_ckpt_manual_mode);
    wire auto_mode_change_on_start = accepted_start && accepted_cfg_seen &&
                                (ckpt_auto_request != prev_ckpt_auto_mode);
    wire enum_new_run_invalidate = accepted_start && enum_request;

    always @(posedge clk) begin
        if (!rstn) begin
            accepted_cfg_seen    <= 1'b0;
            prev_enum_mode       <= 1'b0;
            prev_ckpt_manual_mode<= 1'b0;
            prev_ckpt_auto_mode  <= 1'b0;
            prev_predicate_mode  <= `GP_MODE_LT;
            prev_threshold_a     <= {`GP_DATA_W{1'b0}};
            prev_threshold_b     <= {`GP_DATA_W{1'b0}};
            prev_data_count      <= {`GP_DATA_COUNT_W{1'b0}};
        end else if (accepted_start) begin
            accepted_cfg_seen    <= 1'b1;
            prev_enum_mode       <= enum_request;
            prev_ckpt_manual_mode<= ckpt_manual_request;
            prev_ckpt_auto_mode  <= ckpt_auto_request;
            prev_predicate_mode  <= predicate_mode;
            prev_threshold_a    <= threshold_a;
            prev_threshold_b    <= threshold_b;
            prev_data_count     <= data_count;
        end
    end

    reg enum_cache_invalidate;
    wire cache_invalidate = loader_cache_invalidate |
                            semantic_cfg_change_on_start |
                            mode_change_on_start |
                            manual_mode_change_on_start |
                            auto_mode_change_on_start |
                            enum_new_run_invalidate |
                            enum_cache_invalidate;

    //==========================================================================
    // Existing BBHT engine.  External seed reload is independent of each BBHT
    // start so internal Enumeration retries continue the J random stream.
    //==========================================================================
    wire cache_shot_start;
    wire [`GP_J_W-1:0] bbht_j_req;
    wire cache_iter_do_init;
    wire [15:0] cache_iter_count;

    wire bbht_iter_start;
    wire bbht_iter_do_init;
    wire [15:0] bbht_iter_count;
    wire bbht_iter_done;

    wire physical_iter_start;
    wire physical_iter_do_init;
    wire [15:0] physical_iter_count;
    wire physical_iter_done;
    wire iter_busy;

    wire meas_start;
    wire meas_done;
    wire meas_verify_hit;
    wire meas_zero_weight_error;
    wire [`GP_INDEX_W-1:0] meas_candidate;

    wire term_success;
    wire term_config_error;
    wire term_shot_limit;
    wire term_budget_limit;
    wire term_zero_weight_error;
    wire [`GP_INDEX_W-1:0] success_index;

    wire [`GP_RROM_IDX_W-1:0] bbht_round_idx;
    wire [7:0]                 bbht_m_bound;
    wire [`GP_J_W-1:0]        bbht_current_j;
    wire [31:0]                bbht_trial_count;
    wire [31:0]                bbht_L_BBHT;
    wire                       j_rnd_draw;
    wire [31:0]                j_rnd_state;

    reg enum_bbht_start;
    wire bbht_start = (accepted_start && !enum_request) | enum_bbht_start;

    grover_bbht_shot_fsm u_bbht (
        .clk                    (clk),
        .rstn                   (rstn),
        .start                  (bbht_start),
        .config_ok              (run_config_ok),
        .auto_shot              (run_auto_shot),
        .j_target               (run_j_target),
        .shot_cap               (run_shot_cap),
        .seed_j                 (seed_j),
        .seed_reload            (accepted_start),

        .cache_shot_start       (cache_shot_start),
        .j_req                  (bbht_j_req),
        .cache_iter_do_init     (cache_iter_do_init),
        .cache_iter_count       (cache_iter_count),

        .iter_start             (bbht_iter_start),
        .iter_do_init           (bbht_iter_do_init),
        .iter_count             (bbht_iter_count),
        .iter_done              (bbht_iter_done),

        .meas_start             (meas_start),
        .meas_done              (meas_done),
        .meas_verify_hit        (meas_verify_hit),
        .meas_zero_weight_error (meas_zero_weight_error),
        .meas_candidate         (meas_candidate),

        .busy                   (bbht_busy),
        .done                   (bbht_done),
        .term_success           (term_success),
        .term_config_error      (term_config_error),
        .term_shot_limit        (term_shot_limit),
        .term_budget_limit      (term_budget_limit),
        .term_zero_weight_error (term_zero_weight_error),
        .success_index          (success_index),

        .round_idx              (bbht_round_idx),
        .current_m_bound        (bbht_m_bound),
        .current_j              (bbht_current_j),
        .trial_count            (bbht_trial_count),
        .L_BBHT                 (bbht_L_BBHT),
        .j_rnd_draw             (j_rnd_draw),
        .j_rnd_state            (j_rnd_state)
    );

    //==========================================================================
    // Existing 1-entry amp-state checkpoint metadata (no v0.3 optimization).
    //==========================================================================
    wire [`GP_J_W-1:0] cache_delta_j;
    wire cache_valid;
    wire [`GP_J_W-1:0] cache_j;

    grover_cache_ctrl u_cache (
        .clk              (clk),
        .rstn             (rstn),
        .shot_start       (cache_shot_start),
        .burst_enable     (run_burst_mode),
        .j_req            (bbht_j_req),
        .cache_invalidate (cache_invalidate),
        .iter_done        (bbht_iter_done),
        .iter_do_init     (cache_iter_do_init),
        .iter_count       (cache_iter_count),
        .delta_j          (cache_delta_j),
        .cache_valid      (cache_valid),
        .cache_j          (cache_j)
    );

    //==========================================================================
    // Phase-4B manual K3/K4 checkpoint Planner + Executor
    //==========================================================================
    wire [3:0] ckpt_slot_valid;
    wire [4*`GP_J_W-1:0] ckpt_slot_j_flat;
    wire [2:0] ckpt_sorted_count;
    wire [4*`GP_J_W-1:0] ckpt_sorted_j_flat;

    wire ckpt_plan_error;
    wire ckpt_plan_exact_hit;
    wire ckpt_plan_source_is_anchor;
    wire ckpt_plan_source_materialized;
    wire ckpt_plan_source_retain;
    wire [1:0] ckpt_plan_source_slot;
    wire [3:0] ckpt_plan_retain_mask;
    wire [3:0] ckpt_plan_clear_mask;
    wire [2:0] ckpt_plan_boundary_count;
    wire [4*`GP_J_W-1:0] ckpt_plan_boundary_j_flat;
    wire [7:0] ckpt_plan_boundary_slot_flat;
    wire [1:0] ckpt_plan_endpoint_slot;

    wire ckpt_exec_iter_start;
    wire ckpt_exec_iter_do_init;
    wire [15:0] ckpt_exec_iter_count;
    wire [1:0] ckpt_exec_src_slot;
    wire [1:0] ckpt_exec_dst_slot;
    wire ckpt_exec_bridge;
    wire ckpt_exec_meta_clear_en;
    wire [3:0] ckpt_exec_meta_clear_mask;
    wire ckpt_exec_meta_commit_en;
    wire [1:0] ckpt_exec_meta_commit_slot;
    wire [`GP_J_W-1:0] ckpt_exec_meta_commit_j;
    wire ckpt_exec_busy;
    wire ckpt_exec_done;
    wire ckpt_exec_aborted;
    wire [1:0] ckpt_exec_endpoint_slot;
    wire [31:0] ckpt_exec_physical_iter_issued;
    wire [15:0] ckpt_exec_bridge_count;
    wire [15:0] ckpt_exec_intermediate_commit_count;

    //==========================================================================
    // Autonomous checkpoint controller
    //
    // Functional contract is unchanged from V7: BBHT owns requested-j,
    // trial_count, L_BBHT and the real J RNG.  The only new behavior is that
    // the failure-continuation next-shot policy may be solved in the background
    // and queued. The controller additionally flushes that speculative continuation at each
    // internal Enumeration BBHT-segment restart.  A queued plan is consumed only
    // when three guards all match:
    //   (oracle/spec epoch, expected requested-j, canonical input checkpoint S).
    // Otherwise the queue is flushed and the exact V7 cold solve is used.
    //==========================================================================
    localparam [3:0]
        AP_IDLE             = 4'd0,
        AP_DEMAND_CHECK     = 4'd1,
        AP_COLD_WAIT_SHADOW = 4'd2,
        AP_COLD_POLICY_REQ  = 4'd3,
        AP_COLD_POLICY_WAIT = 4'd4,
        AP_WAIT_LATE_SPEC   = 4'd5,
        AP_EXEC_REQ         = 4'd6,
        AP_EXEC_WAIT        = 4'd7,
        AP_ERROR            = 4'd8,
        AP_EXEC_LAUNCH      = 4'd9,
        AP_EXEC_PLAN_WAIT   = 4'd10,
        AP_INPUT_SORT       = 4'd11;

    localparam [2:0]
        SH_IDLE  = 3'd0,
        SH1_REQ  = 3'd1,
        SH1_WAIT = 3'd2,
        SH_READY = 3'd3;

    localparam [1:0]
        SP_IDLE = 2'd0,
        SP_PREP = 2'd1,
        SP_REQ  = 2'd2,
        SP_WAIT = 2'd3;

    function [3:0] count_to_valid4;
        input [2:0] c;
        begin
            case (c)
                3'd0: count_to_valid4 = 4'b0000;
                3'd1: count_to_valid4 = 4'b0001;
                3'd2: count_to_valid4 = 4'b0011;
                3'd3: count_to_valid4 = 4'b0111;
                default: count_to_valid4 = 4'b1111;
            endcase
        end
    endfunction

    reg [3:0] auto_policy_state;
    reg [2:0] auto_shadow_state;
    reg [1:0] auto_spec_state;
    reg auto_controller_error;

    // Current real BBHT demand snapshot.
    reg [`GP_J_W-1:0] auto_current_j;
    reg [31:0] auto_post_j_state;
    reg [`GP_RROM_IDX_W-1:0] auto_round_after_current;
    reg [31:0] auto_L_after_current;
    reg [`GP_SHOT_CAP_W-1:0] auto_trial_after_current;
    reg [2:0] auto_input_s_count;
    reg [4*`GP_J_W-1:0] auto_input_s_flat;

    // Checkpoint-set sorting pipeline.
    // Level-1 pairwise compare results are captured at bbht_iter_start.
    // AP_INPUT_SORT performs levels 2/3 and registers the canonical S.
    reg [7:0] auto_sort_p0;
    reg [7:0] auto_sort_p1;
    reg [7:0] auto_sort_p2;
    reg [7:0] auto_sort_p3;
    reg [2:0] auto_sort_count;

    wire [7:0] ckpt_sort_i0 =
        ((CKPT_K > 0) && ckpt_slot_valid[0]) ?
        {1'b0,ckpt_slot_j_flat[0*`GP_J_W +: `GP_J_W]} : 8'hFF;
    wire [7:0] ckpt_sort_i1 =
        ((CKPT_K > 1) && ckpt_slot_valid[1]) ?
        {1'b0,ckpt_slot_j_flat[1*`GP_J_W +: `GP_J_W]} : 8'hFF;
    wire [7:0] ckpt_sort_i2 =
        ((CKPT_K > 2) && ckpt_slot_valid[2]) ?
        {1'b0,ckpt_slot_j_flat[2*`GP_J_W +: `GP_J_W]} : 8'hFF;
    wire [7:0] ckpt_sort_i3 =
        ((CKPT_K > 3) && ckpt_slot_valid[3]) ?
        {1'b0,ckpt_slot_j_flat[3*`GP_J_W +: `GP_J_W]} : 8'hFF;

    // Sorting-network level 1: (0,1) and (2,3).
    wire [7:0] ckpt_sort_l1_0 = (ckpt_sort_i0 <= ckpt_sort_i1) ?
                                 ckpt_sort_i0 : ckpt_sort_i1;
    wire [7:0] ckpt_sort_l1_1 = (ckpt_sort_i0 <= ckpt_sort_i1) ?
                                 ckpt_sort_i1 : ckpt_sort_i0;
    wire [7:0] ckpt_sort_l1_2 = (ckpt_sort_i2 <= ckpt_sort_i3) ?
                                 ckpt_sort_i2 : ckpt_sort_i3;
    wire [7:0] ckpt_sort_l1_3 = (ckpt_sort_i2 <= ckpt_sort_i3) ?
                                 ckpt_sort_i3 : ckpt_sort_i2;

    // Sorting-network level 2 from Stage-1 registers: (0,2) and (1,3).
    wire [7:0] auto_sort_l2_0 = (auto_sort_p0 <= auto_sort_p2) ?
                                 auto_sort_p0 : auto_sort_p2;
    wire [7:0] auto_sort_l2_2 = (auto_sort_p0 <= auto_sort_p2) ?
                                 auto_sort_p2 : auto_sort_p0;
    wire [7:0] auto_sort_l2_1 = (auto_sort_p1 <= auto_sort_p3) ?
                                 auto_sort_p1 : auto_sort_p3;
    wire [7:0] auto_sort_l2_3 = (auto_sort_p1 <= auto_sort_p3) ?
                                 auto_sort_p3 : auto_sort_p1;

    // Sorting-network level 3: compare the two middle elements.
    wire [7:0] auto_sort_f0 = auto_sort_l2_0;
    wire [7:0] auto_sort_f1 = (auto_sort_l2_1 <= auto_sort_l2_2) ?
                               auto_sort_l2_1 : auto_sort_l2_2;
    wire [7:0] auto_sort_f2 = (auto_sort_l2_1 <= auto_sort_l2_2) ?
                               auto_sort_l2_2 : auto_sort_l2_1;
    wire [7:0] auto_sort_f3 = auto_sort_l2_3;

    wire [2:0] ckpt_sort_count_now =
        {2'b00,((CKPT_K > 0) && ckpt_slot_valid[0])} +
        {2'b00,((CKPT_K > 1) && ckpt_slot_valid[1])} +
        {2'b00,((CKPT_K > 2) && ckpt_slot_valid[2])} +
        {2'b00,((CKPT_K > 3) && ckpt_slot_valid[3])};

    // Current plan is always latched before Planner/Executor use.  This lets
    // the single policy engine immediately begin the next speculative solve.
    reg auto_current_plan_valid;
    reg [`GP_J_W-1:0] auto_current_plan_source_j;
    reg [2:0] auto_current_plan_next_count;
    reg [4*`GP_J_W-1:0] auto_current_plan_next_j_flat;
    reg [10:0] auto_current_plan_root_cost;
    reg [2:0] auto_current_plan_root_segment_count;

    // Timing-fix1: registered Planner -> Executor packet for autonomous K4/H6.
    // This breaks the long auto_current_j -> combinational Planner -> Executor
    // launch cone without changing any Planner/Executor semantics.
    wire [`GP_J_W-1:0] selected_policy_source_j =
        run_ckpt_manual_active ? run_policy_source_j : auto_current_plan_source_j;
    wire [`GP_J_W-1:0] selected_plan_j_req =
        run_ckpt_manual_active ? run_j_target : auto_current_j;

    reg auto_plan_pipe_valid;
    reg auto_plan_pipe_error;
    reg auto_plan_pipe_exact_hit;
    reg auto_plan_pipe_source_is_anchor;
    reg auto_plan_pipe_source_materialized;
    reg auto_plan_pipe_source_retain;
    reg [1:0] auto_plan_pipe_source_slot;
    reg [`GP_J_W-1:0] auto_plan_pipe_source_j;
    reg [`GP_J_W-1:0] auto_plan_pipe_j_req;
    reg [3:0] auto_plan_pipe_clear_mask;
    reg [2:0] auto_plan_pipe_boundary_count;
    reg [4*`GP_J_W-1:0] auto_plan_pipe_boundary_j_flat;
    reg [7:0] auto_plan_pipe_boundary_slot_flat;
    reg [1:0] auto_plan_pipe_endpoint_slot;

    // Per-demand Shadow-J lookahead.  One verified Shadow-J engine already
    // produces j[t+1]..j[t+8].  That is sufficient for both H6 windows:
    //   cold root: current j[t] + future j[t+1]..j[t+7]
    //   next root: current j[t+1] + future j[t+2]..j[t+8]
    // The legacy 9-slice policy bus is retained; its highest slice is padding.
    reg auto_shadow1_ready;
    reg [8*`GP_J_W-1:0] auto_lookahead_future8;

    wire [9*`GP_J_W-1:0] auto_cold_window_flat =
        {auto_lookahead_future8, auto_current_j};
    wire [9*`GP_J_W-1:0] auto_spec_window_flat =
        {{`GP_J_W{1'b0}}, auto_lookahead_future8};

    // Single Shadow-J engine for K4/H6.
    wire auto_shadow_busy;

    wire auto_shadow_start = run_ckpt_auto_mode &&
                             (auto_shadow_state == SH1_REQ) &&
                             !auto_shadow_busy;

    wire auto_shadow_done;
    wire [8*`GP_J_W-1:0] auto_future_j_flat;
    wire [31:0] auto_shadow_state_final;
    wire [`GP_RROM_IDX_W-1:0] auto_shadow_round_final;
    wire [31:0] auto_shadow_L_final;
    wire [`GP_SHOT_CAP_W-1:0] auto_shadow_trial_final;
    wire [15:0] auto_shadow_candidate_draws;

    // Shared Rolling-H6 policy engine (legacy RTL module name retained).
    wire auto_policy_busy;
    wire auto_policy_done;
    wire auto_policy_error;
    wire [`GP_J_W-1:0] auto_policy_source_j;
    wire [2:0] auto_policy_next_count;
    wire [4*`GP_J_W-1:0] auto_policy_next_j_flat;
    wire [10:0] auto_policy_root_cost;
    wire [2:0] auto_policy_root_segment_count;
    wire [31:0] auto_policy_cycles_last;
    wire [31:0] auto_policy_actions_last;
    wire [31:0] auto_policy_memo_hit_last;
    wire [31:0] auto_policy_memo_miss_last;
    wire [31:0] auto_policy_cycles_hw_total;
    wire [31:0] auto_policy_actions_hw_total;
    wire [31:0] auto_policy_hw_max_latency;
    wire [7:0] auto_policy_epoch;

    // Speculative policy input is captured before start so policy sees a stable
    // canonical predicted checkpoint set and a stable next-root H6 window.
    reg [7:0] spec_plan_epoch;
    reg [`GP_J_W-1:0] spec_expected_j;
    reg [2:0] spec_input_s_count;
    reg [4*`GP_J_W-1:0] spec_input_s_flat;
    reg [3:0] spec_policy_slot_valid;
    reg [4*`GP_J_W-1:0] spec_policy_slot_j_flat;
    reg [9*`GP_J_W-1:0] spec_policy_window_flat;
    reg spec_launched_for_demand;

    // Policy-start ownership.  Cold demand always has priority over a new
    // background launch.  An already-running speculative solve is allowed to
    // finish; if its epoch becomes stale its result is simply discarded.
    wire auto_policy_start_cold = run_ckpt_auto_mode &&
                                  (auto_policy_state == AP_COLD_POLICY_REQ) &&
                                  !auto_policy_busy;
    wire spec_start_context_ok = (auto_policy_state == AP_INPUT_SORT) ||
                                 (auto_policy_state == AP_EXEC_REQ) ||
                                 (auto_policy_state == AP_EXEC_PLAN_WAIT) ||
                                 (auto_policy_state == AP_EXEC_LAUNCH) ||
                                 (auto_policy_state == AP_EXEC_WAIT) ||
                                 (auto_policy_state == AP_IDLE);
    reg [7:0] auto_plan_epoch;

    wire auto_policy_start_spec = run_ckpt_auto_mode && (AUTO_SPEC_ENABLE != 0) &&
                                  (auto_spec_state == SP_REQ) &&
                                  (spec_plan_epoch == auto_plan_epoch) &&
                                  spec_start_context_ok &&
                                  !auto_policy_busy && !auto_policy_start_cold;
    wire auto_policy_start = auto_policy_start_cold | auto_policy_start_spec;
    // Timing-fix1: the autonomous Planner result is first captured in a
    // dedicated plan-packet register stage.  Executor launch therefore occurs
    // one cycle after AP_EXEC_REQ and depends only on registered plan fields.
    wire auto_exec_start = run_ckpt_auto_mode &&
                           (auto_policy_state == AP_EXEC_LAUNCH) &&
                           auto_plan_pipe_valid && !auto_plan_pipe_error;

    wire [3:0] auto_policy_slot_valid_in = auto_policy_start_spec ?
                                            spec_policy_slot_valid : ckpt_slot_valid;
    wire [4*`GP_J_W-1:0] auto_policy_slot_j_flat_in = auto_policy_start_spec ?
                                            spec_policy_slot_j_flat : ckpt_slot_j_flat;
    wire [9*`GP_J_W-1:0] auto_policy_window_flat_in = auto_policy_start_spec ?
                                            spec_policy_window_flat : auto_cold_window_flat;

    reg policy_active_is_spec;
    reg [7:0] policy_active_plan_epoch;

    // Speculative plan FIFO (the module itself was unit-tested in Phase 5).
    wire planq_empty;
    wire planq_full;
    wire [2:0] planq_level;
    wire [2:0] planq_highwater;
    wire [31:0] planq_empty_on_demand;
    wire [7:0] planq_head_epoch;
    wire [`GP_J_W-1:0] planq_head_expected_j;
    wire [2:0] planq_head_input_s_count;
    wire [4*`GP_J_W-1:0] planq_head_input_s_flat;
    wire [`GP_J_W-1:0] planq_head_source_j;
    wire [2:0] planq_head_next_count;
    wire [4*`GP_J_W-1:0] planq_head_next_flat;
    wire [10:0] planq_head_root_cost;
    wire [2:0] planq_head_segment_count;


    wire planq_head_match = !planq_empty &&
                            (planq_head_epoch == auto_plan_epoch) &&
                            (planq_head_expected_j == auto_current_j) &&
                            (planq_head_input_s_count == auto_input_s_count) &&
                            (planq_head_input_s_flat == auto_input_s_flat);

    wire spec_generation_active_raw = (auto_spec_state != SP_IDLE) ||
                                      (auto_policy_busy && policy_active_is_spec);
    // An Oracle/Enumeration epoch advance deliberately makes an in-flight old
    // speculation stale.  Do not classify that expected discard as a prediction
    // mismatch at the first demand of the new epoch.
    wire spec_generation_active = spec_generation_active_raw &&
                                  (spec_plan_epoch == auto_plan_epoch);
    wire spec_inflight_match = spec_generation_active &&
                               (spec_plan_epoch == auto_plan_epoch) &&
                               (spec_expected_j == auto_current_j) &&
                               (spec_input_s_count == auto_input_s_count) &&
                               (spec_input_s_flat == auto_input_s_flat);

    wire planq_check_state = (auto_policy_state == AP_DEMAND_CHECK) ||
                             (auto_policy_state == AP_WAIT_LATE_SPEC);
    wire planq_nonempty_mismatch = run_ckpt_auto_mode && (AUTO_SPEC_ENABLE != 0) &&
                                   planq_check_state && !planq_empty &&
                                   !planq_head_match;
    wire spec_inflight_mismatch = run_ckpt_auto_mode && (AUTO_SPEC_ENABLE != 0) &&
                                  (auto_policy_state == AP_DEMAND_CHECK) &&
                                  planq_empty && spec_generation_active &&
                                  !spec_inflight_match;
    wire speculation_mismatch_event = planq_nonempty_mismatch |
                                      spec_inflight_mismatch;

    // A local speculation epoch may advance without invalidating checkpoint
    // amplitudes.  Its sole purpose is to make any in-flight stale policy
    // result unconsumable after a prediction mismatch/flush.
    // Fresh Enumeration BBHT segments reset the BBHT round/m context.
    // Even when found_mask is unchanged (failed-segment retry), a prediction made
    // for the old segment continuation is no longer the correct future-j window.
    // Flush only speculative plans here; checkpoint amplitudes remain valid unless
    // cache_invalidate is separately asserted by an Oracle semantic change.
    wire enum_segment_plan_restart = run_ckpt_auto_mode && run_enum_mode &&
                                     enum_bbht_start;
    wire auto_context_restart = cache_invalidate | enum_segment_plan_restart;
    wire plan_epoch_advance = accepted_start | cache_invalidate |
                              enum_segment_plan_restart |
                              speculation_mismatch_event;
    wire planq_flush = plan_epoch_advance;
    wire planq_demand = run_ckpt_auto_mode && (AUTO_SPEC_ENABLE != 0) &&
                        (auto_policy_state == AP_DEMAND_CHECK);
    wire planq_pop = run_ckpt_auto_mode && (AUTO_SPEC_ENABLE != 0) &&
                     planq_head_match && planq_check_state;

    wire planq_push = run_ckpt_auto_mode && (AUTO_SPEC_ENABLE != 0) &&
                      auto_policy_done && policy_active_is_spec &&
                      !auto_policy_error &&
                      (policy_active_plan_epoch == auto_plan_epoch) &&
                      !planq_full;

    // Run-level observability.
    reg [31:0] policy_cycles_run;
    reg [31:0] policy_stall_run;
    reg [31:0] policy_actions_run;
    reg [31:0] policy_memo_hit_run;
    reg [31:0] policy_memo_miss_run;
    reg [31:0] policy_max_latency_run;
    reg [31:0] planq_hit_run;
    reg [31:0] planq_mismatch_run;
    reg [31:0] policy_cold_solve_run;
    reg [31:0] policy_spec_solve_run;

    assign policy_cycles_total       = policy_cycles_run;
    assign policy_stall_cycles       = policy_stall_run;
    assign policy_actions_eval       = policy_actions_run;
    assign policy_memo_hit           = policy_memo_hit_run;
    assign policy_memo_miss          = policy_memo_miss_run;
    assign policy_max_latency        = policy_max_latency_run;
    assign plan_fifo_level           = planq_level;
    assign plan_fifo_highwater       = planq_highwater;
    assign plan_fifo_empty_demand    = planq_empty_on_demand;
    assign plan_fifo_hit_count       = planq_hit_run;
    assign plan_fifo_mismatch_count  = planq_mismatch_run;
    assign policy_cold_solve_count   = policy_cold_solve_run;
    assign policy_spec_solve_count   = policy_spec_solve_run;

    // Failure-continuation round after the current real BBHT draw.
    wire [`GP_RROM_IDX_W-1:0] bbht_round_after_current =
        (bbht_round_idx >= `GP_RROM_LAST_IDX) ? `GP_RROM_LAST_IDX :
        (bbht_round_idx + {{(`GP_RROM_IDX_W-1){1'b0}},1'b1});

    wire new_auto_demand = run_ckpt_auto_mode &&
                           (auto_policy_state == AP_IDLE) &&
                           bbht_iter_start;

    // Speculation epoch.
    always @(posedge clk) begin
        if (!rstn)
            auto_plan_epoch <= 8'd1;
        else if (plan_epoch_advance)
            auto_plan_epoch <= (auto_plan_epoch == 8'hFF) ? 8'd1 :
                               (auto_plan_epoch + 1'b1);
    end

    // Shadow-J pipeline.  It runs for every real demand, including FIFO hits,
    // because that is what allows the next policy to be prepared while the
    // current Grover execution is in flight.
    always @(posedge clk) begin
        if (!rstn) begin
            auto_shadow_state     <= SH_IDLE;
            auto_shadow1_ready    <= 1'b0;
            auto_lookahead_future8<= {(8*`GP_J_W){1'b0}};
        end else if (accepted_start) begin
            auto_shadow_state     <= SH_IDLE;
            auto_shadow1_ready    <= 1'b0;
        end else if (auto_context_restart) begin
            // Oracle changes and fresh Enumeration BBHT segments invalidate
            // the previous Shadow-J continuation context.
            auto_shadow_state     <= SH_IDLE;
            auto_shadow1_ready    <= 1'b0;
            auto_lookahead_future8<= {(8*`GP_J_W){1'b0}};
        end else if (new_auto_demand) begin
            auto_shadow_state     <= SH1_REQ;
            auto_shadow1_ready    <= 1'b0;
            auto_lookahead_future8<= {(8*`GP_J_W){1'b0}};
        end else begin
            case (auto_shadow_state)
                SH_IDLE: begin end
                SH1_REQ: begin
                    if (!auto_shadow_busy)
                        auto_shadow_state <= SH1_WAIT;
                end
                SH1_WAIT: begin
                    if (auto_shadow_done) begin
                        auto_lookahead_future8 <= auto_future_j_flat;
                        auto_shadow1_ready <= 1'b1;
                        auto_shadow_state <= SH_READY;
                    end
                end
                default: auto_shadow_state <= SH_READY;
            endcase
        end
    end

    // Main demand -> current-plan -> Executor controller.
    always @(posedge clk) begin
        if (!rstn) begin
            auto_policy_state                   <= AP_IDLE;
            auto_current_j                      <= {`GP_J_W{1'b0}};
            auto_post_j_state                   <= 32'd0;
            auto_round_after_current            <= {`GP_RROM_IDX_W{1'b0}};
            auto_L_after_current                <= 32'd0;
            auto_trial_after_current            <= {`GP_SHOT_CAP_W{1'b0}};
            auto_input_s_count                  <= 3'd0;
            auto_input_s_flat                   <= {(4*`GP_J_W){1'b0}};
            auto_sort_p0                        <= 8'hFF;
            auto_sort_p1                        <= 8'hFF;
            auto_sort_p2                        <= 8'hFF;
            auto_sort_p3                        <= 8'hFF;
            auto_sort_count                     <= 3'd0;
            auto_current_plan_valid             <= 1'b0;
            auto_current_plan_source_j          <= {`GP_J_W{1'b0}};
            auto_current_plan_next_count        <= 3'd0;
            auto_current_plan_next_j_flat       <= {(4*`GP_J_W){1'b0}};
            auto_current_plan_root_cost         <= 11'd0;
            auto_current_plan_root_segment_count<= 3'd0;
            auto_plan_pipe_valid                <= 1'b0;
            auto_plan_pipe_error                <= 1'b0;
            auto_plan_pipe_exact_hit            <= 1'b0;
            auto_plan_pipe_source_is_anchor     <= 1'b0;
            auto_plan_pipe_source_materialized  <= 1'b0;
            auto_plan_pipe_source_retain        <= 1'b0;
            auto_plan_pipe_source_slot          <= 2'd0;
            auto_plan_pipe_source_j             <= {`GP_J_W{1'b0}};
            auto_plan_pipe_j_req                <= {`GP_J_W{1'b0}};
            auto_plan_pipe_clear_mask           <= 4'b0000;
            auto_plan_pipe_boundary_count       <= 3'd0;
            auto_plan_pipe_boundary_j_flat      <= {(4*`GP_J_W){1'b0}};
            auto_plan_pipe_boundary_slot_flat   <= 8'd0;
            auto_plan_pipe_endpoint_slot        <= 2'd0;
            auto_controller_error               <= 1'b0;
            planq_hit_run                       <= 32'd0;
            planq_mismatch_run                  <= 32'd0;
        end else if (accepted_start) begin
            auto_policy_state        <= AP_IDLE;
            auto_current_plan_valid  <= 1'b0;
            auto_plan_pipe_valid     <= 1'b0;
            auto_plan_pipe_error     <= 1'b0;
            auto_controller_error    <= 1'b0;
            planq_hit_run            <= 32'd0;
            planq_mismatch_run       <= 32'd0;
        end else if (auto_context_restart) begin
            // No current Grover request is active at Enumeration segment/Oracle
            // boundaries.  Retire the old logical plan context; checkpoint
            // metadata itself is preserved on same-Oracle segment retries.
            auto_policy_state       <= AP_IDLE;
            auto_current_plan_valid <= 1'b0;
            auto_plan_pipe_valid    <= 1'b0;
            auto_plan_pipe_error    <= 1'b0;
        end else begin
            case (auto_policy_state)
                AP_IDLE: begin
                    if (run_ckpt_auto_mode && bbht_iter_start) begin
                        auto_current_j           <= bbht_j_req;
                        // j_rnd_state is post-accepted-draw when iter_start fires.
                        auto_post_j_state        <= j_rnd_state;
                        auto_round_after_current <= bbht_round_after_current;
                        auto_L_after_current     <= bbht_L_BBHT;
                        auto_trial_after_current <= bbht_trial_count[`GP_SHOT_CAP_W-1:0];

                        // Capture sorting-network level 1 at this register boundary
                        // here.  The previous direct slot_valid -> full sort ->
                        // auto_input_s_flat path was the fix4 WNS=-0.945 ns path.
                        auto_sort_p0             <= ckpt_sort_l1_0;
                        auto_sort_p1             <= ckpt_sort_l1_1;
                        auto_sort_p2             <= ckpt_sort_l1_2;
                        auto_sort_p3             <= ckpt_sort_l1_3;
                        auto_sort_count          <= ckpt_sort_count_now;

                        auto_current_plan_valid  <= 1'b0;
                        auto_policy_state        <= AP_INPUT_SORT;
                    end
                end

                AP_INPUT_SORT: begin
                    // Finish sorting-network levels 2/3 from Stage-1 regs and
                    // register the exact canonical checkpoint set.
                    auto_input_s_count <= auto_sort_count;
                    auto_input_s_flat[0*`GP_J_W +: `GP_J_W] <=
                        (auto_sort_f0 != 8'hFF) ?
                        auto_sort_f0[`GP_J_W-1:0] : {`GP_J_W{1'b0}};
                    auto_input_s_flat[1*`GP_J_W +: `GP_J_W] <=
                        (auto_sort_f1 != 8'hFF) ?
                        auto_sort_f1[`GP_J_W-1:0] : {`GP_J_W{1'b0}};
                    auto_input_s_flat[2*`GP_J_W +: `GP_J_W] <=
                        (auto_sort_f2 != 8'hFF) ?
                        auto_sort_f2[`GP_J_W-1:0] : {`GP_J_W{1'b0}};
                    auto_input_s_flat[3*`GP_J_W +: `GP_J_W] <=
                        (auto_sort_f3 != 8'hFF) ?
                        auto_sort_f3[`GP_J_W-1:0] : {`GP_J_W{1'b0}};
                    auto_policy_state <= AP_DEMAND_CHECK;
                end

                AP_DEMAND_CHECK: begin
                    if ((AUTO_SPEC_ENABLE != 0) && planq_head_match) begin
                        auto_current_plan_valid              <= 1'b1;
                        auto_current_plan_source_j           <= planq_head_source_j;
                        auto_current_plan_next_count         <= planq_head_next_count;
                        auto_current_plan_next_j_flat        <= planq_head_next_flat;
                        auto_current_plan_root_cost          <= planq_head_root_cost;
                        auto_current_plan_root_segment_count <= planq_head_segment_count;
                        planq_hit_run <= planq_hit_run + 1'b1;
                        auto_policy_state <= AP_EXEC_REQ;
                    end else if ((AUTO_SPEC_ENABLE != 0) && !planq_empty) begin
                        // Nonempty-but-wrong head is never consumed.
                        planq_mismatch_run <= planq_mismatch_run + 1'b1;
                        auto_policy_state <= AP_COLD_WAIT_SHADOW;
                    end else if ((AUTO_SPEC_ENABLE != 0) && spec_inflight_match) begin
                        // The prediction exists but completed too late to be in
                        // FIFO at demand time.  Wait for that exact solve rather
                        // than launch a duplicate cold solve.
                        auto_policy_state <= AP_WAIT_LATE_SPEC;
                    end else begin
                        if ((AUTO_SPEC_ENABLE != 0) && spec_generation_active &&
                            !spec_inflight_match)
                            planq_mismatch_run <= planq_mismatch_run + 1'b1;
                        auto_policy_state <= AP_COLD_WAIT_SHADOW;
                    end
                end

                AP_WAIT_LATE_SPEC: begin
                    if (planq_head_match) begin
                        auto_current_plan_valid              <= 1'b1;
                        auto_current_plan_source_j           <= planq_head_source_j;
                        auto_current_plan_next_count         <= planq_head_next_count;
                        auto_current_plan_next_j_flat        <= planq_head_next_flat;
                        auto_current_plan_root_cost          <= planq_head_root_cost;
                        auto_current_plan_root_segment_count <= planq_head_segment_count;
                        planq_hit_run <= planq_hit_run + 1'b1;
                        auto_policy_state <= AP_EXEC_REQ;
                    end else if (!planq_empty) begin
                        planq_mismatch_run <= planq_mismatch_run + 1'b1;
                        auto_policy_state <= AP_COLD_WAIT_SHADOW;
                    end else if (!spec_generation_active) begin
                        // Speculation was discarded/errored; exact fallback.
                        auto_policy_state <= AP_COLD_WAIT_SHADOW;
                    end
                end

                AP_COLD_WAIT_SHADOW: begin
                    if (auto_shadow1_ready && !auto_policy_busy)
                        auto_policy_state <= AP_COLD_POLICY_REQ;
                end

                AP_COLD_POLICY_REQ: begin
                    if (auto_policy_start_cold)
                        auto_policy_state <= AP_COLD_POLICY_WAIT;
                end

                AP_COLD_POLICY_WAIT: begin
                    if (auto_policy_done && !policy_active_is_spec &&
                        (policy_active_plan_epoch == auto_plan_epoch)) begin
                        if (auto_policy_error) begin
                            auto_controller_error <= 1'b1;
                            auto_policy_state <= AP_ERROR;
                        end else begin
                            auto_current_plan_valid              <= 1'b1;
                            auto_current_plan_source_j           <= auto_policy_source_j;
                            auto_current_plan_next_count         <= auto_policy_next_count;
                            auto_current_plan_next_j_flat        <= auto_policy_next_j_flat;
                            auto_current_plan_root_cost          <= auto_policy_root_cost;
                            auto_current_plan_root_segment_count <= auto_policy_root_segment_count;
                            auto_policy_state <= AP_EXEC_REQ;
                        end
                    end
                end

                AP_EXEC_REQ: begin
                    if (CKPT_MANUAL_ENABLE == 0) begin
                        // Production autonomous planner path:
                        // u_ckpt_planner_pipe captures Stage-1 at this edge.
                        // Wait one cycle before capturing its Stage-2 packet.
                        auto_policy_state <= AP_EXEC_PLAN_WAIT;
                    end else begin
                        // Backward-compatible auto path when the Phase-4B
                        // manual planner is compiled in.
                        auto_plan_pipe_valid               <= auto_current_plan_valid &&
                                                              ckpt_plan_valid;
                        auto_plan_pipe_error               <= ckpt_plan_error;
                        auto_plan_pipe_exact_hit           <= ckpt_plan_exact_hit;
                        auto_plan_pipe_source_is_anchor    <= ckpt_plan_source_is_anchor;
                        auto_plan_pipe_source_materialized <= ckpt_plan_source_materialized;
                        auto_plan_pipe_source_retain       <= ckpt_plan_source_retain;
                        auto_plan_pipe_source_slot         <= ckpt_plan_source_slot;
                        auto_plan_pipe_source_j            <= selected_policy_source_j;
                        auto_plan_pipe_j_req               <= selected_plan_j_req;
                        auto_plan_pipe_clear_mask          <= ckpt_plan_clear_mask;
                        auto_plan_pipe_boundary_count      <= ckpt_plan_boundary_count;
                        auto_plan_pipe_boundary_j_flat     <= ckpt_plan_boundary_j_flat;
                        auto_plan_pipe_boundary_slot_flat  <= ckpt_plan_boundary_slot_flat;
                        auto_plan_pipe_endpoint_slot       <= ckpt_plan_endpoint_slot;
                        auto_policy_state                  <= AP_EXEC_LAUNCH;
                    end
                end

                AP_EXEC_PLAN_WAIT: begin
                    // Stage-2 of grover_ckpt_planner_pipe is now stable
                    // from registered Stage-1 data.  Capture the complete packet.
                    auto_plan_pipe_valid               <= auto_current_plan_valid &&
                                                          ckpt_plan_valid;
                    auto_plan_pipe_error               <= ckpt_plan_error;
                    auto_plan_pipe_exact_hit           <= ckpt_plan_exact_hit;
                    auto_plan_pipe_source_is_anchor    <= ckpt_plan_source_is_anchor;
                    auto_plan_pipe_source_materialized <= ckpt_plan_source_materialized;
                    auto_plan_pipe_source_retain       <= ckpt_plan_source_retain;
                    auto_plan_pipe_source_slot         <= ckpt_plan_source_slot;
                    auto_plan_pipe_source_j            <= auto_current_plan_source_j;
                    auto_plan_pipe_j_req               <= auto_current_j;
                    auto_plan_pipe_clear_mask          <= ckpt_plan_clear_mask;
                    auto_plan_pipe_boundary_count      <= ckpt_plan_boundary_count;
                    auto_plan_pipe_boundary_j_flat     <= ckpt_plan_boundary_j_flat;
                    auto_plan_pipe_boundary_slot_flat  <= ckpt_plan_boundary_slot_flat;
                    auto_plan_pipe_endpoint_slot       <= ckpt_plan_endpoint_slot;
                    auto_policy_state                  <= AP_EXEC_LAUNCH;
                end

                AP_EXEC_LAUNCH: begin
                    if (!auto_plan_pipe_valid || auto_plan_pipe_error) begin
                        auto_plan_pipe_valid  <= 1'b0;
                        auto_controller_error <= 1'b1;
                        auto_policy_state     <= AP_ERROR;
                    end else begin
                        // u_ckpt_executor samples start and the registered packet
                        // at this edge; retire the packet for the following cycle.
                        auto_plan_pipe_valid <= 1'b0;
                        auto_policy_state    <= AP_EXEC_WAIT;
                    end
                end

                AP_EXEC_WAIT: begin
                    if (ckpt_exec_aborted) begin
                        auto_controller_error <= 1'b1;
                        auto_policy_state <= AP_ERROR;
                    end else if (ckpt_exec_done) begin
                        auto_policy_state <= AP_IDLE;
                    end
                end

                default: begin
                    auto_controller_error <= 1'b1;
                    auto_policy_state <= AP_ERROR;
                end
            endcase
        end
    end

    // Background next-shot speculation controller.  It predicts exactly one
    // next root per current demand; therefore FIFO depth 4 remains conservative.
    // One-shot-ahead fill is retained while preserving Enumeration epoch correctness.
    always @(posedge clk) begin
        if (!rstn) begin
            auto_spec_state           <= SP_IDLE;
            spec_plan_epoch           <= 8'd0;
            spec_expected_j           <= {`GP_J_W{1'b0}};
            spec_input_s_count        <= 3'd0;
            spec_input_s_flat         <= {(4*`GP_J_W){1'b0}};
            spec_policy_slot_valid    <= 4'b0000;
            spec_policy_slot_j_flat   <= {(4*`GP_J_W){1'b0}};
            spec_policy_window_flat   <= {(9*`GP_J_W){1'b0}};
            spec_launched_for_demand  <= 1'b0;
        end else if (accepted_start) begin
            auto_spec_state          <= SP_IDLE;
            spec_launched_for_demand <= 1'b0;
        end else if (auto_context_restart) begin
            // A running policy engine cannot be cancelled, but changing the
            // local plan epoch makes its result stale and planq_push rejects it.
            auto_spec_state          <= SP_IDLE;
            spec_launched_for_demand <= 1'b0;
        end else begin
            if (new_auto_demand)
                spec_launched_for_demand <= 1'b0;

            case (auto_spec_state)
                SP_IDLE: begin
                    if (run_ckpt_auto_mode && (AUTO_SPEC_ENABLE != 0) &&
                        !new_auto_demand && auto_current_plan_valid && auto_shadow1_ready &&
                        !spec_launched_for_demand && !planq_full &&
                        !auto_controller_error) begin
                        spec_plan_epoch         <= auto_plan_epoch;
                        spec_expected_j         <= auto_lookahead_future8[0*`GP_J_W +: `GP_J_W];
                        spec_input_s_count      <= auto_current_plan_next_count;
                        spec_input_s_flat       <= auto_current_plan_next_j_flat;
                        spec_policy_slot_valid  <= count_to_valid4(auto_current_plan_next_count);
                        spec_policy_slot_j_flat <= auto_current_plan_next_j_flat;
                        spec_policy_window_flat <= auto_spec_window_flat;
                        spec_launched_for_demand<= 1'b1;
                        auto_spec_state         <= SP_PREP;
                    end
                end
                SP_PREP: begin
                    // One register boundary ensures the muxed policy inputs are
                    // stable before the one-cycle start pulse.
                    if (spec_plan_epoch != auto_plan_epoch)
                        auto_spec_state <= SP_IDLE;
                    else
                        auto_spec_state <= SP_REQ;
                end
                SP_REQ: begin
                    if (spec_plan_epoch != auto_plan_epoch)
                        auto_spec_state <= SP_IDLE;
                    else if (auto_policy_start_spec)
                        auto_spec_state <= SP_WAIT;
                end
                SP_WAIT: begin
                    if (auto_policy_done && policy_active_is_spec) begin
                        auto_spec_state <= SP_IDLE;
                    end
                end
                default: auto_spec_state <= SP_IDLE;
            endcase
        end
    end

    // Policy ownership and run-level counters.  Background policy work counts
    // as real hardware work, but policy_stall_run counts only cycles in which a
    // real BBHT demand is blocked waiting for a usable plan.
    always @(posedge clk) begin
        if (!rstn) begin
            policy_active_is_spec    <= 1'b0;
            policy_active_plan_epoch <= 8'd0;
            policy_cycles_run        <= 32'd0;
            policy_stall_run         <= 32'd0;
            policy_actions_run       <= 32'd0;
            policy_memo_hit_run      <= 32'd0;
            policy_memo_miss_run     <= 32'd0;
            policy_max_latency_run   <= 32'd0;
            policy_cold_solve_run    <= 32'd0;
            policy_spec_solve_run    <= 32'd0;
        end else if (accepted_start) begin
            policy_cycles_run        <= 32'd0;
            policy_stall_run         <= 32'd0;
            policy_actions_run       <= 32'd0;
            policy_memo_hit_run      <= 32'd0;
            policy_memo_miss_run     <= 32'd0;
            policy_max_latency_run   <= 32'd0;
            policy_cold_solve_run    <= 32'd0;
            policy_spec_solve_run    <= 32'd0;
        end else begin
            if (auto_policy_start_cold) begin
                policy_active_is_spec    <= 1'b0;
                policy_active_plan_epoch <= auto_plan_epoch;
                policy_cold_solve_run    <= policy_cold_solve_run + 1'b1;
            end else if (auto_policy_start_spec) begin
                policy_active_is_spec    <= 1'b1;
                policy_active_plan_epoch <= spec_plan_epoch;
                policy_spec_solve_run    <= policy_spec_solve_run + 1'b1;
            end

            if (run_ckpt_auto_mode &&
                ((auto_policy_state == AP_DEMAND_CHECK) ||
                 (auto_policy_state == AP_COLD_WAIT_SHADOW) ||
                 (auto_policy_state == AP_COLD_POLICY_REQ) ||
                 (auto_policy_state == AP_COLD_POLICY_WAIT) ||
                 (auto_policy_state == AP_WAIT_LATE_SPEC)))
                policy_stall_run <= policy_stall_run + 1'b1;

            if (run_ckpt_auto_mode && auto_policy_done &&
                (policy_active_plan_epoch == auto_plan_epoch)) begin
                policy_cycles_run    <= policy_cycles_run + auto_policy_cycles_last;
                policy_actions_run   <= policy_actions_run + auto_policy_actions_last;
                policy_memo_hit_run  <= policy_memo_hit_run + auto_policy_memo_hit_last;
                policy_memo_miss_run <= policy_memo_miss_run + auto_policy_memo_miss_last;
                if (auto_policy_cycles_last > policy_max_latency_run)
                    policy_max_latency_run <= auto_policy_cycles_last;
            end
        end
    end

    // Planner sees either the preserved external Phase-4B vector or the
    // latched current autonomous plan.  Latching is essential in V8 because
    // u_auto_policy may already be solving the next speculative root while the
    // current plan is executing.
    wire ckpt_exec_mode = run_ckpt_manual_active | run_ckpt_auto_mode;
    wire selected_policy_valid = run_ckpt_manual_active ? run_policy_valid :
                                 (run_ckpt_auto_mode &&
                                  (auto_policy_state == AP_EXEC_REQ) &&
                                  auto_current_plan_valid &&
                                  !auto_controller_error);
    wire [2:0] selected_policy_next_count =
        run_ckpt_manual_active ? run_policy_next_count : auto_current_plan_next_count;
    wire [4*`GP_J_W-1:0] selected_policy_next_j_flat =
        run_ckpt_manual_active ? run_policy_next_j_flat : auto_current_plan_next_j_flat;

    // The production autonomous planner captures its Stage-1 packet
    // only on AP_EXEC_REQ.  CKPT_MANUAL_ENABLE=1 keeps the original
    // combinational Phase-4B planner and does not use this capture pulse.
    wire auto_planner_capture =
        (CKPT_MANUAL_ENABLE == 0) &&
        run_ckpt_auto_mode &&
        (auto_policy_state == AP_EXEC_REQ) &&
        auto_current_plan_valid &&
        !auto_controller_error;

    // Registered planner boundary:
    //   * CKPT_MANUAL_ENABLE=1: preserve the verified Phase-4B manual path.
    //   * CKPT_MANUAL_ENABLE=0: compile-time remove every direct
    //     combinational Planner -> Executor path.  The production K4/H6
    //     Executor can observe only the registered autonomous plan packet.
    //
    // Using the compile-time parameter here (not run_ckpt_auto_mode) is
    // intentional: Vivado can constant-fold the manual branch completely.
    wire exec_plan_valid =
        (CKPT_MANUAL_ENABLE != 0) ?
            (run_ckpt_auto_mode ? auto_plan_pipe_valid : ckpt_plan_valid) :
            auto_plan_pipe_valid;

    wire exec_plan_exact_hit =
        (CKPT_MANUAL_ENABLE != 0) ?
            (run_ckpt_auto_mode ? auto_plan_pipe_exact_hit : ckpt_plan_exact_hit) :
            auto_plan_pipe_exact_hit;

    wire exec_plan_source_is_anchor =
        (CKPT_MANUAL_ENABLE != 0) ?
            (run_ckpt_auto_mode ? auto_plan_pipe_source_is_anchor :
                                  ckpt_plan_source_is_anchor) :
            auto_plan_pipe_source_is_anchor;

    wire exec_plan_source_materialized =
        (CKPT_MANUAL_ENABLE != 0) ?
            (run_ckpt_auto_mode ? auto_plan_pipe_source_materialized :
                                  ckpt_plan_source_materialized) :
            auto_plan_pipe_source_materialized;

    wire exec_plan_source_retain =
        (CKPT_MANUAL_ENABLE != 0) ?
            (run_ckpt_auto_mode ? auto_plan_pipe_source_retain :
                                  ckpt_plan_source_retain) :
            auto_plan_pipe_source_retain;

    wire [1:0] exec_plan_source_slot =
        (CKPT_MANUAL_ENABLE != 0) ?
            (run_ckpt_auto_mode ? auto_plan_pipe_source_slot :
                                  ckpt_plan_source_slot) :
            auto_plan_pipe_source_slot;


    wire [`GP_J_W-1:0] exec_plan_source_j =
        (CKPT_MANUAL_ENABLE != 0) ?
            (run_ckpt_auto_mode ? auto_plan_pipe_source_j :
                                  selected_policy_source_j) :
            auto_plan_pipe_source_j;

    wire [`GP_J_W-1:0] exec_plan_j_req =
        (CKPT_MANUAL_ENABLE != 0) ?
            (run_ckpt_auto_mode ? auto_plan_pipe_j_req :
                                  selected_plan_j_req) :
            auto_plan_pipe_j_req;

    wire [3:0] exec_plan_clear_mask =
        (CKPT_MANUAL_ENABLE != 0) ?
            (run_ckpt_auto_mode ? auto_plan_pipe_clear_mask :
                                  ckpt_plan_clear_mask) :
            auto_plan_pipe_clear_mask;

    wire [2:0] exec_plan_boundary_count =
        (CKPT_MANUAL_ENABLE != 0) ?
            (run_ckpt_auto_mode ? auto_plan_pipe_boundary_count :
                                  ckpt_plan_boundary_count) :
            auto_plan_pipe_boundary_count;

    wire [4*`GP_J_W-1:0] exec_plan_boundary_j_flat =
        (CKPT_MANUAL_ENABLE != 0) ?
            (run_ckpt_auto_mode ? auto_plan_pipe_boundary_j_flat :
                                  ckpt_plan_boundary_j_flat) :
            auto_plan_pipe_boundary_j_flat;

    wire [7:0] exec_plan_boundary_slot_flat =
        (CKPT_MANUAL_ENABLE != 0) ?
            (run_ckpt_auto_mode ? auto_plan_pipe_boundary_slot_flat :
                                  ckpt_plan_boundary_slot_flat) :
            auto_plan_pipe_boundary_slot_flat;

    wire [1:0] exec_plan_endpoint_slot =
        (CKPT_MANUAL_ENABLE != 0) ?
            (run_ckpt_auto_mode ? auto_plan_pipe_endpoint_slot :
                                  ckpt_plan_endpoint_slot) :
            auto_plan_pipe_endpoint_slot;

    generate
        if (CHECKPOINT_ENABLE != 0) begin : g_ckpt_plan_exec
            grover_ckpt_meta #(.CKPT_K(CKPT_K)) u_ckpt_meta (
                .clk          (clk),
                .rstn         (rstn),
                .invalidate_all(cache_invalidate),
                .clear_en     (ckpt_exec_meta_clear_en),
                .clear_mask   (ckpt_exec_meta_clear_mask),
                .commit_en    (ckpt_exec_meta_commit_en),
                .commit_slot  (ckpt_exec_meta_commit_slot),
                .commit_j     (ckpt_exec_meta_commit_j),
                .slot_valid   (ckpt_slot_valid),
                .slot_j_flat  (ckpt_slot_j_flat),
                .sorted_count (ckpt_sorted_count),
                .sorted_j_flat(ckpt_sorted_j_flat)
            );

            if ((CKPT_K == 3) || (CKPT_K == 4)) begin : g_auto_policy_k34
                grover_shadow_j u_shadow_j (
                    .clk                 (clk),
                    .rstn                (rstn),
                    .start               (auto_shadow_start),
                    .post_j_state        (auto_post_j_state),
                    .round_after_current (auto_round_after_current),
                    .L_after_current     (auto_L_after_current),
                    .trial_after_current (auto_trial_after_current),
                    .busy                (auto_shadow_busy),
                    .done                (auto_shadow_done),
                    .future_j_flat       (auto_future_j_flat),
                    .shadow_state_final  (auto_shadow_state_final),
                    .round_final         (auto_shadow_round_final),
                    .L_final             (auto_shadow_L_final),
                    .trial_final         (auto_shadow_trial_final),
                    .candidate_draws     (auto_shadow_candidate_draws)
                );


                grover_ckpt_policy_rolling #(
                    .CKPT_K      (CKPT_K),
                    .H_FUTURE    (POLICY_H_FUTURE)
                ) u_auto_policy (
                    .clk                  (clk),
                    .rstn                 (rstn),
                    .start                (auto_policy_start),
                    .slot_valid           (auto_policy_slot_valid_in),
                    .slot_j_flat          (auto_policy_slot_j_flat_in),
                    .j_window_flat        (auto_policy_window_flat_in),
                    .busy                 (auto_policy_busy),
                    .done                 (auto_policy_done),
                    .policy_error         (auto_policy_error),
                    .source_j             (auto_policy_source_j),
                    .next_count           (auto_policy_next_count),
                    .next_j_flat          (auto_policy_next_j_flat),
                    .root_cost            (auto_policy_root_cost),
                    .root_segment_count   (auto_policy_root_segment_count),
                    .policy_cycles_last   (auto_policy_cycles_last),
                    .policy_actions_last  (auto_policy_actions_last),
                    .policy_memo_hit_last (auto_policy_memo_hit_last),
                    .policy_memo_miss_last(auto_policy_memo_miss_last),
                    .policy_cycles_total  (auto_policy_cycles_hw_total),
                    .policy_actions_total (auto_policy_actions_hw_total),
                    .policy_max_latency   (auto_policy_hw_max_latency),
                    .policy_epoch         (auto_policy_epoch)
                );

                grover_ckpt_plan_fifo #(.DEPTH(4), .PTR_W(2)) u_plan_fifo (
                    .clk                    (clk),
                    .rstn                   (rstn),
                    .flush                  (planq_flush),
                    .push                   (planq_push),
                    .push_oracle_epoch      (policy_active_plan_epoch),
                    .push_expected_j        (spec_expected_j),
                    .push_input_s_count     (spec_input_s_count),
                    .push_input_s_flat      (spec_input_s_flat),
                    .push_source_j          (auto_policy_source_j),
                    .push_next_count        (auto_policy_next_count),
                    .push_next_flat         (auto_policy_next_j_flat),
                    .push_root_cost         (auto_policy_root_cost),
                    .push_segment_count     (auto_policy_root_segment_count),
                    .pop                    (planq_pop),
                    .demand                 (planq_demand),
                    .empty                  (planq_empty),
                    .full                   (planq_full),
                    .level                  (planq_level),
                    .highwater              (planq_highwater),
                    .empty_on_demand_count  (planq_empty_on_demand),
                    .head_oracle_epoch      (planq_head_epoch),
                    .head_expected_j        (planq_head_expected_j),
                    .head_input_s_count     (planq_head_input_s_count),
                    .head_input_s_flat      (planq_head_input_s_flat),
                    .head_source_j          (planq_head_source_j),
                    .head_next_count        (planq_head_next_count),
                    .head_next_flat         (planq_head_next_flat),
                    .head_root_cost         (planq_head_root_cost),
                    .head_segment_count     (planq_head_segment_count)
                );
            end else begin : g_no_auto_policy_k34
                assign auto_shadow_busy            = 1'b0;
                assign auto_shadow_done            = 1'b0;
                assign auto_future_j_flat          = {(8*`GP_J_W){1'b0}};
                assign auto_shadow_state_final     = 32'd0;
                assign auto_shadow_round_final     = {`GP_RROM_IDX_W{1'b0}};
                assign auto_shadow_L_final         = 32'd0;
                assign auto_shadow_trial_final     = {`GP_SHOT_CAP_W{1'b0}};
                assign auto_shadow_candidate_draws = 16'd0;
                assign auto_policy_busy            = 1'b0;
                assign auto_policy_done            = 1'b0;
                assign auto_policy_error           = 1'b0;
                assign auto_policy_source_j        = {`GP_J_W{1'b0}};
                assign auto_policy_next_count      = 3'd0;
                assign auto_policy_next_j_flat     = {(4*`GP_J_W){1'b0}};
                assign auto_policy_root_cost       = 11'd0;
                assign auto_policy_root_segment_count = 3'd0;
                assign auto_policy_cycles_last     = 32'd0;
                assign auto_policy_actions_last    = 32'd0;
                assign auto_policy_memo_hit_last   = 32'd0;
                assign auto_policy_memo_miss_last  = 32'd0;
                assign auto_policy_cycles_hw_total = 32'd0;
                assign auto_policy_actions_hw_total= 32'd0;
                assign auto_policy_hw_max_latency  = 32'd0;
                assign auto_policy_epoch           = 8'd0;
                assign planq_empty                 = 1'b1;
                assign planq_full                  = 1'b0;
                assign planq_level                 = 3'd0;
                assign planq_highwater             = 3'd0;
                assign planq_empty_on_demand       = 32'd0;
                assign planq_head_epoch            = 8'd0;
                assign planq_head_expected_j       = {`GP_J_W{1'b0}};
                assign planq_head_input_s_count    = 3'd0;
                assign planq_head_input_s_flat     = {(4*`GP_J_W){1'b0}};
                assign planq_head_source_j         = {`GP_J_W{1'b0}};
                assign planq_head_next_count       = 3'd0;
                assign planq_head_next_flat        = {(4*`GP_J_W){1'b0}};
                assign planq_head_root_cost        = 11'd0;
                assign planq_head_segment_count    = 3'd0;
            end

            if (CKPT_MANUAL_ENABLE != 0) begin : g_ckpt_planner_manual_compat
                // Original combinational planner is retained unchanged for the
                // Phase-4B manual verification path and backward compatibility.
                grover_ckpt_planner #(.CKPT_K(CKPT_K)) u_ckpt_planner (
                    .policy_valid          (selected_policy_valid),
                    .slot_valid            (ckpt_slot_valid),
                    .slot_j_flat           (ckpt_slot_j_flat),
                    .j_req                 (selected_plan_j_req),
                    .policy_source_j       (selected_policy_source_j),
                    .policy_next_count     (selected_policy_next_count),
                    .policy_next_j_flat    (selected_policy_next_j_flat),
                    .plan_valid            (ckpt_plan_valid),
                    .plan_error            (ckpt_plan_error),
                    .exact_hit             (ckpt_plan_exact_hit),
                    .source_is_anchor      (ckpt_plan_source_is_anchor),
                    .source_materialized   (ckpt_plan_source_materialized),
                    .source_retain         (ckpt_plan_source_retain),
                    .source_slot           (ckpt_plan_source_slot),
                    .retain_mask           (ckpt_plan_retain_mask),
                    .clear_mask            (ckpt_plan_clear_mask),
                    .boundary_count        (ckpt_plan_boundary_count),
                    .boundary_j_flat       (ckpt_plan_boundary_j_flat),
                    .boundary_slot_flat    (ckpt_plan_boundary_slot_flat),
                    .endpoint_slot         (ckpt_plan_endpoint_slot)
                );
            end else begin : g_ckpt_planner_auto_pipe
                // Production K4/H6 path.  The stage boundary cuts the fix3
                // metadata -> predecessor -> allocation -> plan-packet path.
                grover_ckpt_planner_pipe #(.CKPT_K(CKPT_K)) u_ckpt_planner_pipe (
                    .clk                   (clk),
                    .rstn                  (rstn),
                    .capture               (auto_planner_capture),
                    .policy_valid          (auto_current_plan_valid),
                    .slot_valid            (ckpt_slot_valid),
                    .slot_j_flat           (ckpt_slot_j_flat),
                    .j_req                 (auto_current_j),
                    .policy_source_j       (auto_current_plan_source_j),
                    .policy_next_count     (auto_current_plan_next_count),
                    .policy_next_j_flat    (auto_current_plan_next_j_flat),
                    .plan_valid            (ckpt_plan_valid),
                    .plan_error            (ckpt_plan_error),
                    .exact_hit             (ckpt_plan_exact_hit),
                    .source_is_anchor      (ckpt_plan_source_is_anchor),
                    .source_materialized   (ckpt_plan_source_materialized),
                    .source_retain         (ckpt_plan_source_retain),
                    .source_slot           (ckpt_plan_source_slot),
                    .retain_mask           (ckpt_plan_retain_mask),
                    .clear_mask            (ckpt_plan_clear_mask),
                    .boundary_count        (ckpt_plan_boundary_count),
                    .boundary_j_flat       (ckpt_plan_boundary_j_flat),
                    .boundary_slot_flat    (ckpt_plan_boundary_slot_flat),
                    .endpoint_slot         (ckpt_plan_endpoint_slot)
                );
            end

            grover_ckpt_executor u_ckpt_executor (
                .clk                      (clk),
                .rstn                     (rstn),
                .start                    ((bbht_iter_start && run_ckpt_manual_active) |
                                           auto_exec_start),
                .invalidate               (cache_invalidate),
                .plan_valid               (exec_plan_valid),
                .plan_exact_hit           (exec_plan_exact_hit),
                .plan_source_is_anchor    (exec_plan_source_is_anchor),
                .plan_source_materialized (exec_plan_source_materialized),
                .plan_source_retain       (exec_plan_source_retain),
                .plan_source_slot         (exec_plan_source_slot),
                .plan_source_j            (exec_plan_source_j),
                .plan_j_req               (exec_plan_j_req),
                .plan_clear_mask          (exec_plan_clear_mask),
                .plan_boundary_count      (exec_plan_boundary_count),
                .plan_boundary_j_flat     (exec_plan_boundary_j_flat),
                .plan_boundary_slot_flat  (exec_plan_boundary_slot_flat),
                .plan_endpoint_slot       (exec_plan_endpoint_slot),
                .iter_start               (ckpt_exec_iter_start),
                .iter_do_init             (ckpt_exec_iter_do_init),
                .iter_count               (ckpt_exec_iter_count),
                .iter_src_slot            (ckpt_exec_src_slot),
                .iter_dst_slot            (ckpt_exec_dst_slot),
                .iter_bridge              (ckpt_exec_bridge),
                .iter_busy                (iter_busy),
                .iter_done                (physical_iter_done),
                .meta_clear_en            (ckpt_exec_meta_clear_en),
                .meta_clear_mask          (ckpt_exec_meta_clear_mask),
                .meta_commit_en           (ckpt_exec_meta_commit_en),
                .meta_commit_slot         (ckpt_exec_meta_commit_slot),
                .meta_commit_j            (ckpt_exec_meta_commit_j),
                .busy                     (ckpt_exec_busy),
                .done                     (ckpt_exec_done),
                .aborted                  (ckpt_exec_aborted),
                .endpoint_slot            (ckpt_exec_endpoint_slot),
                .physical_iter_issued     (ckpt_exec_physical_iter_issued),
                .bridge_count             (ckpt_exec_bridge_count),
                .intermediate_commit_count(ckpt_exec_intermediate_commit_count)
            );
        end else begin : g_no_ckpt_plan_exec
            assign ckpt_slot_valid                    = 4'b0000;
            assign ckpt_slot_j_flat                   = {(4*`GP_J_W){1'b0}};
            assign ckpt_sorted_count                  = 3'd0;
            assign ckpt_sorted_j_flat                 = {(4*`GP_J_W){1'b0}};
            assign ckpt_plan_valid                    = 1'b0;
            assign ckpt_plan_error                    = 1'b0;
            assign ckpt_plan_exact_hit                = 1'b0;
            assign ckpt_plan_source_is_anchor         = 1'b0;
            assign ckpt_plan_source_materialized      = 1'b0;
            assign ckpt_plan_source_retain            = 1'b0;
            assign ckpt_plan_source_slot              = 2'd0;
            assign ckpt_plan_retain_mask              = 4'b0000;
            assign ckpt_plan_clear_mask               = 4'b0000;
            assign ckpt_plan_boundary_count           = 3'd0;
            assign ckpt_plan_boundary_j_flat          = {(4*`GP_J_W){1'b0}};
            assign ckpt_plan_boundary_slot_flat       = 8'd0;
            assign ckpt_plan_endpoint_slot            = 2'd0;
            assign ckpt_exec_iter_start               = 1'b0;
            assign ckpt_exec_iter_do_init             = 1'b0;
            assign ckpt_exec_iter_count               = 16'd0;
            assign ckpt_exec_src_slot                 = 2'd0;
            assign ckpt_exec_dst_slot                 = 2'd0;
            assign ckpt_exec_bridge                   = 1'b0;
            assign ckpt_exec_meta_clear_en            = 1'b0;
            assign ckpt_exec_meta_clear_mask          = 4'b0000;
            assign ckpt_exec_meta_commit_en           = 1'b0;
            assign ckpt_exec_meta_commit_slot         = 2'd0;
            assign ckpt_exec_meta_commit_j            = {`GP_J_W{1'b0}};
            assign ckpt_exec_busy                     = 1'b0;
            assign ckpt_exec_done                     = 1'b0;
            assign ckpt_exec_aborted                  = 1'b0;
            assign ckpt_exec_endpoint_slot            = 2'd0;
            assign ckpt_exec_physical_iter_issued     = 32'd0;
            assign ckpt_exec_bridge_count             = 16'd0;
            assign ckpt_exec_intermediate_commit_count= 16'd0;
            assign auto_shadow_busy            = 1'b0;
            assign auto_shadow_done            = 1'b0;
            assign auto_future_j_flat          = {(8*`GP_J_W){1'b0}};
            assign auto_shadow_state_final     = 32'd0;
            assign auto_shadow_round_final     = {`GP_RROM_IDX_W{1'b0}};
            assign auto_shadow_L_final         = 32'd0;
            assign auto_shadow_trial_final     = {`GP_SHOT_CAP_W{1'b0}};
            assign auto_shadow_candidate_draws = 16'd0;
            assign auto_policy_busy            = 1'b0;
            assign auto_policy_done            = 1'b0;
            assign auto_policy_error           = 1'b0;
            assign auto_policy_source_j        = {`GP_J_W{1'b0}};
            assign auto_policy_next_count      = 3'd0;
            assign auto_policy_next_j_flat     = {(4*`GP_J_W){1'b0}};
            assign auto_policy_root_cost       = 11'd0;
            assign auto_policy_root_segment_count = 3'd0;
            assign auto_policy_cycles_last     = 32'd0;
            assign auto_policy_actions_last    = 32'd0;
            assign auto_policy_memo_hit_last   = 32'd0;
            assign auto_policy_memo_miss_last  = 32'd0;
            assign auto_policy_cycles_hw_total = 32'd0;
            assign auto_policy_actions_hw_total= 32'd0;
            assign auto_policy_hw_max_latency  = 32'd0;
            assign auto_policy_epoch           = 8'd0;
            assign planq_empty                 = 1'b1;
            assign planq_full                  = 1'b0;
            assign planq_level                 = 3'd0;
            assign planq_highwater             = 3'd0;
            assign planq_empty_on_demand       = 32'd0;
            assign planq_head_epoch            = 8'd0;
            assign planq_head_expected_j       = {`GP_J_W{1'b0}};
            assign planq_head_input_s_count    = 3'd0;
            assign planq_head_input_s_flat     = {(4*`GP_J_W){1'b0}};
            assign planq_head_source_j         = {`GP_J_W{1'b0}};
            assign planq_head_next_count       = 3'd0;
            assign planq_head_next_flat        = {(4*`GP_J_W){1'b0}};
            assign planq_head_root_cost        = 11'd0;
            assign planq_head_segment_count    = 3'd0;
        end
    endgenerate

    assign bbht_iter_done = ckpt_exec_mode ? ckpt_exec_done
                                            : physical_iter_done;
    assign physical_iter_start = ckpt_exec_mode ? ckpt_exec_iter_start
                                                 : bbht_iter_start;
    assign physical_iter_do_init = ckpt_exec_mode ? ckpt_exec_iter_do_init
                                                   : bbht_iter_do_init;
    assign physical_iter_count = ckpt_exec_mode ? ckpt_exec_iter_count
                                                 : bbht_iter_count;

    //==========================================================================
    // Inner Grover physical kernel.
    // INTRA_ENGINES=1 preserves frozen K4/H4; 2 and 4 enable E2/E4.
    // E2/E4 change only the physical Grover state-vector throughput; BBHT,
    // K4/H4 policy/checkpoint semantics remain unchanged. Multi-engine modes
    // are enabled only when CHECKPOINT_ENABLE!=0.
    //==========================================================================
    wire [3:0] iter_state;
    wire iter_pass_tick;
    wire signed [`GP_ACC_W-1:0] dp_global_sum;
    wire signed [`GP_TWO_MEAN_W-1:0] dp_two_mean;
    wire dp_sat_event;

    wire [AMP_ROW_BITS-1:0] amp_mem_rdata;
    wire ckpt_amp_rd_valid;

    // Common classical-verify ports.
    wire [`GP_INDEX_W-1:0] data_verify_index;
    wire signed [`GP_DATA_W-1:0] data_verify_value;
    wire found_mask_verify_found;

    // Found-mask maintenance is shared by E1/E2 memory variants.
    reg mask_clear_start;
    reg mask_set_start;
    reg [`GP_INDEX_W-1:0] mask_set_index;
    wire mask_maint_busy;
    wire mask_clear_done;
    wire mask_set_done;

    //==========================================================================
    // Measurement PRNG: reload once per external run only.
    //==========================================================================
    wire [31:0] meas_rnd_state;
    wire meas_rnd_draw;

    grover_meas_prng64_adapter #(
        .FALLBACK_SEED(`GP_FALLBACK_MEAS)
    ) u_meas_lfsr (
        .clk     (clk),
        .rstn    (rstn),
        .seed_we (accepted_start),
        .seed    (seed_meas),
        .draw    (meas_rnd_draw),
        .rnd     (meas_rnd_state)
    );

    //==========================================================================
    // Born + classical verify. E2 checkpoint single-row read preserves the
    // same two-cycle checkpoint read latency seen by the frozen measurement.
    //==========================================================================
    wire meas_busy;
    wire meas_amp_write_forbid;
    wire [`GP_ROW_W-1:0] meas_amp_rd_row;
    wire meas_amp_rd_en;

    // E4 Measurement M1: BUILD can consume the existing four-row checkpoint
    // read path as a two-row/cycle Born-square stream.  E1/E2 tie these off.
    wire [AMP_ROW_BITS-1:0] meas_amp_quad0;
    wire [AMP_ROW_BITS-1:0] meas_amp_quad1;
    wire [AMP_ROW_BITS-1:0] meas_amp_quad2;
    wire [AMP_ROW_BITS-1:0] meas_amp_quad3;
    wire meas_amp_quad_valid;
    wire [6:0] meas_amp_quad_rd_index;
    wire meas_amp_quad_rd_en;

    wire [`GP_TOTAL_WEIGHT_W-1:0] meas_total_weight;
    wire [`GP_TOTAL_WEIGHT_W-1:0] meas_threshold;
    wire [`GP_ROW_W-1:0] meas_selected_row;

    grover_measure_verify #(
        .AMP_READ_LATENCY((CHECKPOINT_ENABLE != 0) ? 2 : 1),
        .E4_DUAL_BUILD   (((INTRA_ENGINES == 4) &&
                           (CHECKPOINT_ENABLE != 0) &&
                           (MEAS_M1_ENABLE != 0)) ? 1 : 0),
        .E4_HIER_SELECT  (((INTRA_ENGINES == 4) &&
                           (CHECKPOINT_ENABLE != 0) &&
                           (MEAS_M1_ENABLE != 0) &&
                           (MEAS_M2_ENABLE != 0)) ? 1 : 0)
    ) u_measure_verify (
        .clk                  (clk),
        .rstn                 (rstn),
        .start                (meas_start),
        .predicate_mode       (run_predicate_mode),
        .threshold_a          (run_threshold_a),
        .threshold_b          (run_threshold_b),
        .data_count           (run_data_count),
        .enum_enable          (run_enum_mode),
        .found_mask_verify_found(found_mask_verify_found),
        .rnd                  (meas_rnd_state),
        .rnd_draw             (meas_rnd_draw),
        .amp_rdata            (amp_mem_rdata),
        .amp_rd_row           (meas_amp_rd_row),
        .amp_rd_en            (meas_amp_rd_en),
        .amp_quad0            (meas_amp_quad0),
        .amp_quad1            (meas_amp_quad1),
        .amp_quad2            (meas_amp_quad2),
        .amp_quad3            (meas_amp_quad3),
        .amp_quad_valid       (meas_amp_quad_valid),
        .amp_quad_rd_index    (meas_amp_quad_rd_index),
        .amp_quad_rd_en       (meas_amp_quad_rd_en),
        .data_verify_index    (data_verify_index),
        .data_verify_value    (data_verify_value),
        .busy                 (meas_busy),
        .done                 (meas_done),
        .verify_hit           (meas_verify_hit),
        .zero_weight_error    (meas_zero_weight_error),
        .candidate            (meas_candidate),
        .amp_write_forbid     (meas_amp_write_forbid),
        .total_weight         (meas_total_weight),
        .measurement_threshold(meas_threshold),
        .selected_row         (meas_selected_row)
    );

    generate
        if ((INTRA_ENGINES == 4) && (CHECKPOINT_ENABLE != 0)) begin : g_intra_e4
            // ---------------------------------------------------------------
            // E4 controller: 128 quads x 4 rows cover the frozen 512 rows.
            // ---------------------------------------------------------------
            wire [6:0] e4_quad_index;
            wire e4_ckpt_quad_rd_en;
            wire e4_scratch_quad_rd_en;
            wire e4_data_quad_rd_en;
            wire [1:0] e4_dp_op;
            wire e4_dp_quad_valid;
            wire [6:0] e4_dp_quad_index;
            wire e4_acc_clear;
            wire e4_dp_quad_out_valid;
            wire [6:0] e4_dp_quad_out_index;
            wire e4_sum_commit;

            grover_ctrl_fsm_ckpt_e4 u_iter_ctrl (
                .clk(clk), .rstn(rstn),
                .iter_start(physical_iter_start),
                .iter_do_init(physical_iter_do_init),
                .iter_count(physical_iter_count),
                .dp_quad_out_valid(e4_dp_quad_out_valid),
                .dp_sum_commit(e4_sum_commit),
                .iter_busy(iter_busy), .iter_done(physical_iter_done),
                .state(iter_state), .quad_index(e4_quad_index),
                .ckpt_quad_rd_en(e4_ckpt_quad_rd_en),
                .scratch_quad_rd_en(e4_scratch_quad_rd_en),
                .data_quad_rd_en(e4_data_quad_rd_en),
                .dp_op(e4_dp_op), .dp_quad_valid(e4_dp_quad_valid),
                .dp_quad_index(e4_dp_quad_index), .acc_clear(e4_acc_clear),
                .pass_tick(iter_pass_tick)
            );

            wire [1:0] e4_src_slot=ckpt_exec_mode?ckpt_exec_src_slot:2'd0;
            wire [1:0] e4_dst_slot=ckpt_exec_mode?ckpt_exec_dst_slot:2'd0;
            wire e4_bridge=ckpt_exec_mode?ckpt_exec_bridge:1'b0;
            wire [1:0] e4_quad_rd_slot=
                (e4_bridge&&(iter_state==4'd2))?e4_src_slot:e4_dst_slot;
            wire [1:0] e4_meas_slot=ckpt_exec_mode?ckpt_exec_endpoint_slot:2'd0;

            // Measurement and physical iteration are mutually exclusive.
            // During M1 BUILD, reuse the same interleaved four-bank quad read
            // port instead of the legacy single-row measurement read port.
            wire e4_meas_quad_active = meas_busy && meas_amp_quad_rd_en;
            wire [1:0] e4_mem_quad_rd_slot = meas_busy ?
                                                e4_meas_slot : e4_quad_rd_slot;
            wire [6:0] e4_mem_quad_rd_index = meas_busy ?
                                                meas_amp_quad_rd_index : e4_quad_index;
            wire e4_mem_quad_rd_en = meas_busy ? meas_amp_quad_rd_en :
                                                e4_ckpt_quad_rd_en;

            // Tag measurement-originated quad reads so a residual physical
            // checkpoint response can never be mistaken for BUILD row 0.
            reg e4_meas_req_d1;
            reg e4_meas_req_d2;
            always @(posedge clk) begin
                if (!rstn) begin
                    e4_meas_req_d1 <= 1'b0;
                    e4_meas_req_d2 <= 1'b0;
                end else begin
                    e4_meas_req_d1 <= e4_meas_quad_active;
                    e4_meas_req_d2 <= e4_meas_req_d1;
                end
            end

            wire [AMP_ROW_BITS-1:0] e4_ckpt0,e4_ckpt1,e4_ckpt2,e4_ckpt3;
            wire e4_ckpt_quad_valid;
            wire [AMP_ROW_BITS-1:0] e4_out0,e4_out1,e4_out2,e4_out3;

            // BRAM-efficient E4 keeps PASS1 Oracle state directly in the
            // destination checkpoint, exactly like the frozen E1 segment
            // semantics (bridge: PASS1 src->dst, PASS2 dst->dst).  Therefore
            // no extra full-state scratch memory is required.
            wire e4_ckpt_quad_wr_en=e4_dp_quad_out_valid&&
                ((iter_state==4'd1)||(iter_state==4'd2)||(iter_state==4'd4))&&
                !meas_amp_write_forbid;

            grover_ckpt_mem_interleaved_e4 #(.CKPT_K(CKPT_K)) u_amp_mem (
                .clk(clk),
                .quad_rd_slot(e4_mem_quad_rd_slot), .quad_rd_index(e4_mem_quad_rd_index),
                .quad_rd_en(e4_mem_quad_rd_en),
                .quad_rd0(e4_ckpt0),.quad_rd1(e4_ckpt1),.quad_rd2(e4_ckpt2),.quad_rd3(e4_ckpt3),
                .quad_rd_valid(e4_ckpt_quad_valid),
                .quad_wr_slot(e4_dst_slot), .quad_wr_index(e4_dp_quad_out_index),
                .quad_wr_en(e4_ckpt_quad_wr_en),
                .quad_wr0(e4_out0),.quad_wr1(e4_out1),.quad_wr2(e4_out2),.quad_wr3(e4_out3),
                .single_rd_slot(e4_meas_slot), .single_rd_row(meas_amp_rd_row),
                .single_rd_en(meas_busy&&meas_amp_rd_en),
                .single_rd_amp(amp_mem_rdata), .single_rd_valid(ckpt_amp_rd_valid)
            );

            assign meas_amp_quad0      = e4_ckpt0;
            assign meas_amp_quad1      = e4_ckpt1;
            assign meas_amp_quad2      = e4_ckpt2;
            assign meas_amp_quad3      = e4_ckpt3;
            assign meas_amp_quad_valid = e4_ckpt_quad_valid && e4_meas_req_d2;

            wire [DATA_ROW_BITS-1:0] e4_data0_raw,e4_data1_raw,e4_data2_raw,e4_data3_raw;
            grover_data_mem_e4 u_data_mem (
                .clk(clk), .quad_rd_index(e4_quad_index), .quad_rd_en(e4_data_quad_rd_en),
                .quad_data0(e4_data0_raw),.quad_data1(e4_data1_raw),
                .quad_data2(e4_data2_raw),.quad_data3(e4_data3_raw),
                .wr_index(loader_mem_wr_addr),.wr_en(loader_mem_wr_en),.wr_data(loader_mem_wr_data),
                .verify_index(data_verify_index),.verify_data(data_verify_value)
            );

            wire [`GP_P-1:0] e4_mask0_raw,e4_mask1_raw,e4_mask2_raw,e4_mask3_raw;
            grover_found_mask_mem_e4 u_found_mask (
                .clk(clk),.rstn(rstn),.quad_rd_index(e4_quad_index),.quad_rd_en(e4_data_quad_rd_en),
                .quad_mask0(e4_mask0_raw),.quad_mask1(e4_mask1_raw),
                .quad_mask2(e4_mask2_raw),.quad_mask3(e4_mask3_raw),
                .verify_index(data_verify_index),.verify_found(found_mask_verify_found),
                .clear_start(mask_clear_start),.set_start(mask_set_start),.set_index(mask_set_index),
                .maint_busy(mask_maint_busy),.clear_done(mask_clear_done),.set_done(mask_set_done)
            );

            wire [DATA_ROW_BITS-1:0] e4_data0,e4_data1,e4_data2,e4_data3;
            wire [`GP_P-1:0] e4_mask0,e4_mask1,e4_mask2,e4_mask3;
            wire e4_oracle_aligned_valid;
            grover_e4_oracle_align_quad u_oracle_align (
                .clk(clk),.rstn(rstn),.req_en(e4_data_quad_rd_en),
                .data0_raw(e4_data0_raw),.data1_raw(e4_data1_raw),
                .data2_raw(e4_data2_raw),.data3_raw(e4_data3_raw),
                .mask0_raw(e4_mask0_raw),.mask1_raw(e4_mask1_raw),
                .mask2_raw(e4_mask2_raw),.mask3_raw(e4_mask3_raw),
                .data0_aligned(e4_data0),.data1_aligned(e4_data1),
                .data2_aligned(e4_data2),.data3_aligned(e4_data3),
                .mask0_aligned(e4_mask0),.mask1_aligned(e4_mask1),
                .mask2_aligned(e4_mask2),.mask3_aligned(e4_mask3),
                .aligned_valid(e4_oracle_aligned_valid)
            );

            // PASS1 and PASS2 both consume the selected checkpoint memory.
            // PASS1 writes Oracle state to dst; PASS2 rereads that dst state.
            wire [AMP_ROW_BITS-1:0] e4_amp0=e4_ckpt0;
            wire [AMP_ROW_BITS-1:0] e4_amp1=e4_ckpt1;
            wire [AMP_ROW_BITS-1:0] e4_amp2=e4_ckpt2;
            wire [AMP_ROW_BITS-1:0] e4_amp3=e4_ckpt3;

            grover_iter_datapath_e4 u_iter_dp (
                .clk(clk),.rstn(rstn),.op(e4_dp_op),.quad_valid(e4_dp_quad_valid),
                .quad_index(e4_dp_quad_index),.acc_clear(e4_acc_clear),
                .amp0_in(e4_amp0),.amp1_in(e4_amp1),.amp2_in(e4_amp2),.amp3_in(e4_amp3),
                .data0_in(e4_data0),.data1_in(e4_data1),.data2_in(e4_data2),.data3_in(e4_data3),
                .mask0_in(e4_mask0),.mask1_in(e4_mask1),.mask2_in(e4_mask2),.mask3_in(e4_mask3),
                .predicate_mode(run_predicate_mode),.threshold_a(run_threshold_a),.threshold_b(run_threshold_b),
                .data_count(run_data_count),.enum_enable(run_enum_mode),
                .amp0_out(e4_out0),.amp1_out(e4_out1),.amp2_out(e4_out2),.amp3_out(e4_out3),
                .quad_out_valid(e4_dp_quad_out_valid),.quad_out_index(e4_dp_quad_out_index),
                .global_sum(dp_global_sum),.two_mean(dp_two_mean),.sum_commit(e4_sum_commit),.sat_event(dp_sat_event)
            );

            wire _unused_e4_valid_guard=e4_ckpt_quad_valid^e4_oracle_aligned_valid^e4_scratch_quad_rd_en;
        end else if ((INTRA_ENGINES == 2) && (CHECKPOINT_ENABLE != 0)) begin : g_intra_e2
            assign meas_amp_quad0      = {AMP_ROW_BITS{1'b0}};
            assign meas_amp_quad1      = {AMP_ROW_BITS{1'b0}};
            assign meas_amp_quad2      = {AMP_ROW_BITS{1'b0}};
            assign meas_amp_quad3      = {AMP_ROW_BITS{1'b0}};
            assign meas_amp_quad_valid = 1'b0;

            // ---------------------------------------------------------------
            // E2 controller: 256 row-pairs cover the frozen 512-row state.
            // ---------------------------------------------------------------
            wire [7:0] e2_pair_index;
            wire e2_ckpt_pair_rd_en;
            wire e2_scratch_pair_rd_en;
            wire e2_data_pair_rd_en;
            wire [1:0] e2_dp_op;
            wire e2_dp_pair_valid;
            wire [7:0] e2_dp_pair_index;
            wire e2_acc_clear;
            wire e2_dp_pair_out_valid;
            wire [7:0] e2_dp_pair_out_index;
            wire e2_sum_commit;

            grover_ctrl_fsm_ckpt_e2 u_iter_ctrl (
                .clk               (clk),
                .rstn              (rstn),
                .iter_start        (physical_iter_start),
                .iter_do_init      (physical_iter_do_init),
                .iter_count        (physical_iter_count),
                .dp_pair_out_valid (e2_dp_pair_out_valid),
                .dp_sum_commit     (e2_sum_commit),
                .iter_busy         (iter_busy),
                .iter_done         (physical_iter_done),
                .state             (iter_state),
                .pair_index        (e2_pair_index),
                .ckpt_pair_rd_en   (e2_ckpt_pair_rd_en),
                .scratch_pair_rd_en(e2_scratch_pair_rd_en),
                .data_pair_rd_en   (e2_data_pair_rd_en),
                .dp_op             (e2_dp_op),
                .dp_pair_valid     (e2_dp_pair_valid),
                .dp_pair_index     (e2_dp_pair_index),
                .acc_clear         (e2_acc_clear),
                .pass_tick         (iter_pass_tick)
            );

            // K4 segment ownership is unchanged. A bridge reads src only in
            // PASS1; INIT/PASS2 commit to dst exactly like the frozen router.
            wire [1:0] e2_src_slot = ckpt_exec_mode ? ckpt_exec_src_slot : 2'd0;
            wire [1:0] e2_dst_slot = ckpt_exec_mode ? ckpt_exec_dst_slot : 2'd0;
            wire e2_bridge = ckpt_exec_mode ? ckpt_exec_bridge : 1'b0;
            wire [1:0] e2_pair_rd_slot =
                (e2_bridge && (iter_state == 4'd2)) ? e2_src_slot : e2_dst_slot;
            wire [1:0] e2_meas_slot = ckpt_exec_mode ? ckpt_exec_endpoint_slot : 2'd0;

            wire [AMP_ROW_BITS-1:0] e2_ckpt_even;
            wire [AMP_ROW_BITS-1:0] e2_ckpt_odd;
            wire e2_ckpt_pair_valid;
            wire [AMP_ROW_BITS-1:0] e2_scratch_even;
            wire [AMP_ROW_BITS-1:0] e2_scratch_odd;
            wire [AMP_ROW_BITS-1:0] e2_dp_even_out;
            wire [AMP_ROW_BITS-1:0] e2_dp_odd_out;

            wire e2_ckpt_pair_wr_en = e2_dp_pair_out_valid &&
                                      ((iter_state == 4'd1) || (iter_state == 4'd4)) &&
                                      !meas_amp_write_forbid;
            wire e2_scratch_pair_wr_en = e2_dp_pair_out_valid &&
                                         (iter_state == 4'd2);

            grover_ckpt_mem_tdp_e2 #(.CKPT_K(CKPT_K)) u_amp_mem (
                .clk            (clk),
                .pair_rd_slot   (e2_pair_rd_slot),
                .pair_rd_index  (e2_pair_index),
                .pair_rd_en     (e2_ckpt_pair_rd_en),
                .pair_rd_even   (e2_ckpt_even),
                .pair_rd_odd    (e2_ckpt_odd),
                .pair_rd_valid  (e2_ckpt_pair_valid),
                .pair_wr_slot   (e2_dst_slot),
                .pair_wr_index  (e2_dp_pair_out_index),
                .pair_wr_en     (e2_ckpt_pair_wr_en),
                .pair_wr_even   (e2_dp_even_out),
                .pair_wr_odd    (e2_dp_odd_out),
                .single_rd_slot (e2_meas_slot),
                .single_rd_row  (meas_amp_rd_row),
                .single_rd_en   (meas_busy && meas_amp_rd_en),
                .single_rd_amp  (amp_mem_rdata),
                .single_rd_valid(ckpt_amp_rd_valid)
            );

            grover_e2_oracle_scratch_tdp u_oracle_scratch (
                .clk          (clk),
                .pair_rd_index(e2_pair_index),
                .pair_rd_en   (e2_scratch_pair_rd_en),
                .pair_rd_even (e2_scratch_even),
                .pair_rd_odd  (e2_scratch_odd),
                .pair_wr_index(e2_dp_pair_out_index),
                .pair_wr_en   (e2_scratch_pair_wr_en),
                .pair_wr_even (e2_dp_even_out),
                .pair_wr_odd  (e2_dp_odd_out)
            );

            // ---------------------------------------------------------------
            // Dataset: during PASS1, Port A reads even row and Port B reads
            // odd row. Outside PASS1, Port B resumes loader/verify behavior.
            // ---------------------------------------------------------------
            wire [DATA_ROW_BITS-1:0] e2_data_even_raw;
            wire [DATA_ROW_BITS-1:0] e2_data_odd_raw;
            grover_data_mem_e2 u_data_mem (
                .clk           (clk),
                .pair_rd_index (e2_pair_index),
                .pair_rd_en    (e2_data_pair_rd_en),
                .pair_even_data(e2_data_even_raw),
                .pair_odd_data (e2_data_odd_raw),
                .wr_index      (loader_mem_wr_addr),
                .wr_en         (loader_mem_wr_en),
                .wr_data       (loader_mem_wr_data),
                .verify_index  (data_verify_index),
                .verify_data   (data_verify_value)
            );

            wire [`GP_P-1:0] e2_mask_even_raw;
            wire [`GP_P-1:0] e2_mask_odd_raw;
            grover_found_mask_mem_e2 u_found_mask (
                .clk           (clk),
                .rstn          (rstn),
                .pair_rd_index (e2_pair_index),
                .pair_rd_en    (e2_data_pair_rd_en),
                .pair_even_mask(e2_mask_even_raw),
                .pair_odd_mask (e2_mask_odd_raw),
                .verify_index  (data_verify_index),
                .verify_found  (found_mask_verify_found),
                .clear_start   (mask_clear_start),
                .set_start     (mask_set_start),
                .set_index     (mask_set_index),
                .maint_busy    (mask_maint_busy),
                .clear_done    (mask_clear_done),
                .set_done      (mask_set_done)
            );

            // Data/mask BRAMs respond in one cycle, checkpoint pair read in two.
            wire [DATA_ROW_BITS-1:0] e2_data_even;
            wire [DATA_ROW_BITS-1:0] e2_data_odd;
            wire [`GP_P-1:0] e2_mask_even;
            wire [`GP_P-1:0] e2_mask_odd;
            wire e2_oracle_aligned_valid;
            grover_e2_oracle_align_pair u_oracle_align (
                .clk              (clk),
                .rstn             (rstn),
                .req_en           (e2_data_pair_rd_en),
                .data_even_raw    (e2_data_even_raw),
                .data_odd_raw     (e2_data_odd_raw),
                .mask_even_raw    (e2_mask_even_raw),
                .mask_odd_raw     (e2_mask_odd_raw),
                .data_even_aligned(e2_data_even),
                .data_odd_aligned (e2_data_odd),
                .mask_even_aligned(e2_mask_even),
                .mask_odd_aligned (e2_mask_odd),
                .aligned_valid    (e2_oracle_aligned_valid)
            );

            wire [AMP_ROW_BITS-1:0] e2_amp_even_in =
                (iter_state == 4'd2) ? e2_ckpt_even : e2_scratch_even;
            wire [AMP_ROW_BITS-1:0] e2_amp_odd_in =
                (iter_state == 4'd2) ? e2_ckpt_odd : e2_scratch_odd;

            grover_iter_datapath_e2 u_iter_dp (
                .clk             (clk),
                .rstn            (rstn),
                .op              (e2_dp_op),
                .pair_valid      (e2_dp_pair_valid),
                .pair_index      (e2_dp_pair_index),
                .acc_clear       (e2_acc_clear),
                .amp_even_in     (e2_amp_even_in),
                .amp_odd_in      (e2_amp_odd_in),
                .data_even_in    (e2_data_even),
                .data_odd_in     (e2_data_odd),
                .mask_even_in    (e2_mask_even),
                .mask_odd_in     (e2_mask_odd),
                .predicate_mode  (run_predicate_mode),
                .threshold_a     (run_threshold_a),
                .threshold_b     (run_threshold_b),
                .data_count      (run_data_count),
                .enum_enable     (run_enum_mode),
                .amp_even_out    (e2_dp_even_out),
                .amp_odd_out     (e2_dp_odd_out),
                .pair_out_valid  (e2_dp_pair_out_valid),
                .pair_out_index  (e2_dp_pair_out_index),
                .global_sum      (dp_global_sum),
                .two_mean        (dp_two_mean),
                .sum_commit      (e2_sum_commit),
                .sat_event       (dp_sat_event)
            );

            wire _unused_e2_valid_guard = e2_ckpt_pair_valid ^
                                          e2_oracle_aligned_valid ^ 1'b0;
        end else begin : g_intra_e1
            assign meas_amp_quad0      = {AMP_ROW_BITS{1'b0}};
            assign meas_amp_quad1      = {AMP_ROW_BITS{1'b0}};
            assign meas_amp_quad2      = {AMP_ROW_BITS{1'b0}};
            assign meas_amp_quad3      = {AMP_ROW_BITS{1'b0}};
            assign meas_amp_quad_valid = 1'b0;

            // ---------------------------------------------------------------
            // Frozen one-row-per-cycle physical kernel.
            // ---------------------------------------------------------------
            wire [`GP_ROW_W-1:0] iter_amp_rd_row;
            wire iter_amp_rd_en;
            wire [`GP_ROW_W-1:0] iter_data_rd_row;
            wire iter_data_rd_en;
            wire [1:0] dp_op;
            wire dp_row_valid;
            wire [`GP_ROW_W-1:0] dp_row_index;
            wire dp_acc_clear;
            wire ctrl_amp_wr_en;
            wire [`GP_ROW_W-1:0] ctrl_amp_wr_row;

            if (CHECKPOINT_ENABLE != 0) begin : g_ckpt_iter_ctrl
                grover_ctrl_fsm_ckpt u_iter_ctrl (
                    .clk(clk), .rstn(rstn),
                    .iter_start(physical_iter_start),
                    .iter_do_init(physical_iter_do_init),
                    .iter_count(physical_iter_count),
                    .iter_busy(iter_busy), .iter_done(physical_iter_done),
                    .state(iter_state),
                    .amp_rd_row(iter_amp_rd_row), .amp_rd_en(iter_amp_rd_en),
                    .data_rd_row(iter_data_rd_row), .data_rd_en(iter_data_rd_en),
                    .dp_op(dp_op), .dp_row_valid(dp_row_valid),
                    .dp_row_index(dp_row_index), .acc_clear(dp_acc_clear),
                    .amp_wr_en(ctrl_amp_wr_en), .amp_wr_row(ctrl_amp_wr_row),
                    .pass_tick(iter_pass_tick)
                );
            end else begin : g_legacy_iter_ctrl
                grover_ctrl_fsm u_iter_ctrl (
                    .clk(clk), .rstn(rstn),
                    .iter_start(physical_iter_start),
                    .iter_do_init(physical_iter_do_init),
                    .iter_count(physical_iter_count),
                    .iter_busy(iter_busy), .iter_done(physical_iter_done),
                    .state(iter_state),
                    .amp_rd_row(iter_amp_rd_row), .amp_rd_en(iter_amp_rd_en),
                    .data_rd_row(iter_data_rd_row), .data_rd_en(iter_data_rd_en),
                    .dp_op(dp_op), .dp_row_valid(dp_row_valid),
                    .dp_row_index(dp_row_index), .acc_clear(dp_acc_clear),
                    .amp_wr_en(ctrl_amp_wr_en), .amp_wr_row(ctrl_amp_wr_row),
                    .pass_tick(iter_pass_tick)
                );
            end

            wire [DATA_ROW_BITS-1:0] data_mem_row_rdata_raw;
            wire [`GP_P-1:0] found_mask_oracle_row_raw;
            wire [DATA_ROW_BITS-1:0] data_mem_row_rdata;
            wire [`GP_P-1:0] found_mask_oracle_row;
            wire ckpt_oracle_aligned_valid;

            if (CHECKPOINT_ENABLE != 0) begin : g_ckpt_oracle_align
                grover_ckpt_oracle_align u_oracle_align (
                    .clk(clk), .rstn(rstn), .req_en(iter_data_rd_en),
                    .data_row_raw(data_mem_row_rdata_raw),
                    .found_mask_row_raw(found_mask_oracle_row_raw),
                    .data_row_aligned(data_mem_row_rdata),
                    .found_mask_row_aligned(found_mask_oracle_row),
                    .aligned_valid(ckpt_oracle_aligned_valid)
                );
            end else begin : g_legacy_oracle_align
                assign data_mem_row_rdata = data_mem_row_rdata_raw;
                assign found_mask_oracle_row = found_mask_oracle_row_raw;
                assign ckpt_oracle_aligned_valid = 1'b0;
            end

            wire [AMP_ROW_BITS-1:0] dp_amp_row_out;
            wire dp_row_out_valid;
            wire [`GP_ROW_W-1:0] dp_row_out_index;
            wire signed [`GP_PARTIAL_SUM_W-1:0] dp_row_partial_sum;

            grover_iter_datapath u_iter_dp (
                .clk(clk), .rstn(rstn), .op(dp_op),
                .row_valid(dp_row_valid), .row_index(dp_row_index),
                .acc_clear(dp_acc_clear), .amp_row_in(amp_mem_rdata),
                .data_row_in(data_mem_row_rdata),
                .found_mask_row_in(found_mask_oracle_row),
                .predicate_mode(run_predicate_mode),
                .threshold_a(run_threshold_a), .threshold_b(run_threshold_b),
                .data_count(run_data_count), .enum_enable(run_enum_mode),
                .amp_row_out(dp_amp_row_out), .row_out_valid(dp_row_out_valid),
                .row_out_index(dp_row_out_index),
                .row_partial_sum(dp_row_partial_sum),
                .global_sum(dp_global_sum), .two_mean(dp_two_mean),
                .sat_event(dp_sat_event)
            );

            wire ckpt_pass1_active = (iter_state == 4'd2);
            wire [1:0] ckpt_iter_rd_slot;
            wire [1:0] ckpt_iter_wr_slot;
            grover_ckpt_segment_router u_ckpt_segment_router (
                .pass1_active(ckpt_pass1_active), .bridge(ckpt_exec_bridge),
                .src_slot(ckpt_exec_src_slot), .dst_slot(ckpt_exec_dst_slot),
                .amp_rd_slot(ckpt_iter_rd_slot), .amp_wr_slot(ckpt_iter_wr_slot)
            );
            wire [1:0] ckpt_amp_rd_slot = ckpt_exec_mode ?
                (meas_busy ? ckpt_exec_endpoint_slot : ckpt_iter_rd_slot) : 2'd0;
            wire [1:0] ckpt_amp_wr_slot = ckpt_exec_mode ? ckpt_iter_wr_slot : 2'd0;
            wire [`GP_ROW_W-1:0] amp_mem_rd_row = meas_busy ? meas_amp_rd_row : iter_amp_rd_row;
            wire amp_mem_rd_en = meas_busy ? meas_amp_rd_en : iter_amp_rd_en;
            wire amp_mem_wr_en = ctrl_amp_wr_en && dp_row_out_valid && !meas_amp_write_forbid;

            if (CHECKPOINT_ENABLE != 0) begin : g_ckpt_amp_mem
                grover_ckpt_mem #(.CKPT_K(CKPT_K)) u_amp_mem (
                    .clk(clk), .rd_slot(ckpt_amp_rd_slot),
                    .rd_row(amp_mem_rd_row), .rd_en(amp_mem_rd_en),
                    .rd_amp(amp_mem_rdata), .rd_valid(ckpt_amp_rd_valid),
                    .wr_slot(ckpt_amp_wr_slot), .wr_row(ctrl_amp_wr_row),
                    .wr_en(amp_mem_wr_en), .wr_amp(dp_amp_row_out)
                );
            end else begin : g_legacy_amp_mem
                grover_amp_mem u_amp_mem (
                    .clk(clk), .rd_row(amp_mem_rd_row), .rd_en(amp_mem_rd_en),
                    .rd_amp(amp_mem_rdata), .wr_row(ctrl_amp_wr_row),
                    .wr_en(amp_mem_wr_en), .wr_amp(dp_amp_row_out)
                );
                assign ckpt_amp_rd_valid = 1'b0;
            end

            grover_data_mem u_data_mem (
                .clk(clk), .rd_row(iter_data_rd_row), .rd_en(iter_data_rd_en),
                .rd_data(data_mem_row_rdata_raw),
                .wr_index(loader_mem_wr_addr), .wr_en(loader_mem_wr_en),
                .wr_data(loader_mem_wr_data),
                .verify_index(data_verify_index), .verify_data(data_verify_value)
            );

            grover_found_mask_mem u_found_mask (
                .clk(clk), .rstn(rstn),
                .oracle_rd_row(iter_data_rd_row), .oracle_rd_en(iter_data_rd_en),
                .oracle_mask_row(found_mask_oracle_row_raw),
                .verify_index(data_verify_index), .verify_found(found_mask_verify_found),
                .clear_start(mask_clear_start), .set_start(mask_set_start),
                .set_index(mask_set_index), .maint_busy(mask_maint_busy),
                .clear_done(mask_clear_done), .set_done(mask_set_done)
            );

            wire _unused_e1_align_valid = ckpt_oracle_aligned_valid;
            wire _unused_e1_partial = |dp_row_partial_sum;
        end
    endgenerate

    // Result FIFO.  Clear only on accepted Enumeration start; memory bits are
    // not cleared, only pointers/count.
    wire fifo_clear = accepted_start && enum_request;
    wire fifo_push_req;
    reg [`GP_INDEX_W-1:0] pending_result;

    grover_result_fifo #(
        .DEPTH (`GP_RESULT_FIFO_DEPTH),
        .CNT_W (`GP_RESULT_FIFO_CNT_W)
    ) u_result_fifo (
        .clk         (clk),
        .rstn        (rstn),
        .clear       (fifo_clear),
        .push        (fifo_push_req),
        .push_data   (pending_result),
        .push_accept (fifo_push_accept),
        .pop         (res_pop),
        .dout        (res_dout),
        .pop_accept  (fifo_pop_accept),
        .empty       (res_empty),
        .full        (fifo_full),
        .count       (res_count)
    );

    //==========================================================================
    // Autonomous Enumeration controller
    //==========================================================================
    localparam [2:0]
        E_IDLE       = 3'd0,
        E_CONFIG     = 3'd1,
        E_CLEAR_WAIT = 3'd2,
        E_BBHT_WAIT  = 3'd3,
        E_MASK_WAIT  = 3'd4,
        E_FIFO_WAIT  = 3'd5,
        E_FIFO_PUSH  = 3'd6;

    reg [2:0] enum_st;
    reg enum_term_config_error;
    reg enum_term_zero_weight_error;

    // Push is accepted only from E_FIFO_PUSH and only when space exists.  A
    // full queue therefore causes a deliberate wait; full+pop is not combined
    // with a same-cycle push.
    assign fifo_push_req = enum_active && (enum_st == E_FIFO_PUSH) && !fifo_full;

    wire [`GP_FOUND_COUNT_W-1:0] found_count_plus_one =
        found_count + {{(`GP_FOUND_COUNT_W-1){1'b0}},1'b1};
    wire [`GP_ENUM_FAIL_W-1:0] fail_count_plus_one =
        consecutive_fail_count + {{(`GP_ENUM_FAIL_W-1){1'b0}},1'b1};

    always @(posedge clk) begin
        if (!rstn) begin
            enum_st                    <= E_IDLE;
            enum_active                <= 1'b0;
            enum_terminal_pulse        <= 1'b0;
            enum_term_config_error     <= 1'b0;
            enum_term_zero_weight_error<= 1'b0;
            enum_bbht_start            <= 1'b0;
            enum_cache_invalidate      <= 1'b0;
            mask_clear_start           <= 1'b0;
            mask_set_start             <= 1'b0;
            mask_set_index             <= {`GP_INDEX_W{1'b0}};
            pending_result             <= {`GP_INDEX_W{1'b0}};
            pending_valid              <= 1'b0;
            enum_done                  <= 1'b0;
            found_count                <= {`GP_FOUND_COUNT_W{1'b0}};
            consecutive_fail_count     <= {`GP_ENUM_FAIL_W{1'b0}};
            max_fifo_occupancy         <= {`GP_RESULT_FIFO_CNT_W{1'b0}};
            fifo_stall_cycles          <= 32'd0;
        end else begin
            // Default one-cycle control/event pulses.
            enum_terminal_pulse         <= 1'b0;
            enum_term_config_error      <= 1'b0;
            enum_term_zero_weight_error <= 1'b0;
            enum_bbht_start             <= 1'b0;
            enum_cache_invalidate       <= 1'b0;
            mask_clear_start            <= 1'b0;
            mask_set_start              <= 1'b0;

            // A new external run retires all previous Enumeration summaries.
            if (accepted_start) begin
                enum_done              <= 1'b0;
                found_count            <= {`GP_FOUND_COUNT_W{1'b0}};
                consecutive_fail_count <= {`GP_ENUM_FAIL_W{1'b0}};
                max_fifo_occupancy     <= {`GP_RESULT_FIFO_CNT_W{1'b0}};
                fifo_stall_cycles      <= 32'd0;
                pending_valid          <= 1'b0;

                if (enum_request) begin
                    enum_active <= 1'b1;
                    enum_st     <= E_CONFIG;
                end else begin
                    enum_active <= 1'b0;
                    enum_st     <= E_IDLE;
                end
            end else if (enum_active) begin
                // Observe FIFO occupancy throughout the Enumeration run.
                if (res_count > max_fifo_occupancy)
                    max_fifo_occupancy <= res_count;

                case (enum_st)
                    E_CONFIG: begin
                        // Enumeration is autonomous BBHT only.  fail_limit=0 is
                        // invalid.  Dataset/data_count/shot_cap use the same
                        // validity contract as Single BBHT.
                        if (!run_config_ok || !run_auto_shot ||
                            (run_shot_cap == {`GP_SHOT_CAP_W{1'b0}}) ||
                            (run_fail_repeat_limit == {`GP_ENUM_FAIL_W{1'b0}})) begin
                            enum_active            <= 1'b0;
                            enum_terminal_pulse    <= 1'b1;
                            enum_term_config_error <= 1'b1;
                            enum_st                <= E_IDLE;
                        end else begin
                            mask_clear_start <= 1'b1;
                            enum_st          <= E_CLEAR_WAIT;
                        end
                    end

                    E_CLEAR_WAIT: begin
                        if (mask_clear_done) begin
                            enum_bbht_start <= 1'b1;
                            enum_st         <= E_BBHT_WAIT;
                        end
                    end

                    E_BBHT_WAIT: begin
                        if (bbht_done) begin
                            if (term_zero_weight_error) begin
                                enum_active                 <= 1'b0;
                                enum_terminal_pulse         <= 1'b1;
                                enum_term_zero_weight_error <= 1'b1;
                                enum_st                     <= E_IDLE;
                            end else if (term_config_error) begin
                                enum_active            <= 1'b0;
                                enum_terminal_pulse    <= 1'b1;
                                enum_term_config_error <= 1'b1;
                                enum_st                <= E_IDLE;
                            end else if (term_success) begin
                                pending_result         <= success_index;
                                pending_valid          <= 1'b1;
                                mask_set_index         <= success_index;
                                mask_set_start         <= 1'b1;
                                found_count            <= found_count_plus_one;
                                consecutive_fail_count <= {`GP_ENUM_FAIL_W{1'b0}};
                                // New mask means a new Oracle; the old amp state
                                // is not a valid Burst checkpoint.
                                enum_cache_invalidate  <= 1'b1;
                                enum_st                <= E_MASK_WAIT;
                            end else if (term_shot_limit || term_budget_limit) begin
                                consecutive_fail_count <= fail_count_plus_one;
                                if (fail_count_plus_one >= run_fail_repeat_limit) begin
                                    enum_active         <= 1'b0;
                                    enum_done           <= 1'b1;
                                    enum_terminal_pulse <= 1'b1;
                                    enum_st             <= E_IDLE;
                                end else begin
                                    // Same found_mask/Oracle.  Start a fresh
                                    // BBHT control search but continue PRNGs.
                                    enum_bbht_start <= 1'b1;
                                    enum_st         <= E_BBHT_WAIT;
                                end
                            end else begin
                                // Manual miss cannot be legal in Enumeration.
                                enum_active            <= 1'b0;
                                enum_terminal_pulse    <= 1'b1;
                                enum_term_config_error <= 1'b1;
                                enum_st                <= E_IDLE;
                            end
                        end
                    end

                    E_MASK_WAIT: begin
                        if (mask_set_done) begin
                            if (fifo_full)
                                enum_st <= E_FIFO_WAIT;
                            else
                                enum_st <= E_FIFO_PUSH;
                        end
                    end

                    E_FIFO_WAIT: begin
                        if (fifo_full) begin
                            fifo_stall_cycles <= fifo_stall_cycles + 32'd1;
                        end else begin
                            enum_st <= E_FIFO_PUSH;
                        end
                    end

                    E_FIFO_PUSH: begin
                        if (!fifo_full) begin
                            // fifo_push_req is high in this state, so the entry
                            // is accepted on this edge.
                            pending_valid <= 1'b0;
                            if ((fifo_pop_accept ? res_count :
                                 (res_count + {{(`GP_RESULT_FIFO_CNT_W-1){1'b0}},1'b1}))
                                > max_fifo_occupancy)
                                max_fifo_occupancy <= fifo_pop_accept ? res_count :
                                    (res_count + {{(`GP_RESULT_FIFO_CNT_W-1){1'b0}},1'b1});

                            // Only this equality is deterministic all-found:
                            // every valid data index has become a unique result.
                            if (found_count >= run_data_count) begin
                                enum_active         <= 1'b0;
                                enum_done           <= 1'b1;
                                enum_terminal_pulse <= 1'b1;
                                enum_st             <= E_IDLE;
                            end else begin
                                enum_bbht_start <= 1'b1;
                                enum_st         <= E_BBHT_WAIT;
                            end
                        end else begin
                            enum_st <= E_FIFO_WAIT;
                        end
                    end

                    default: begin
                        enum_active            <= 1'b0;
                        enum_terminal_pulse    <= 1'b1;
                        enum_term_config_error <= 1'b1;
                        enum_st                <= E_IDLE;
                    end
                endcase
            end
        end
    end

    //==========================================================================
    // Enumeration run-global trial/L_BBHT accumulation.  The local BBHT FSM
    // resets these counters on each internal bbht_start.
    //==========================================================================
    reg [31:0] enum_trial_base;
    reg [31:0] enum_L_base;
    reg        enum_segment_active;

    always @(posedge clk) begin
        if (!rstn) begin
            enum_trial_base     <= 32'd0;
            enum_L_base         <= 32'd0;
            enum_segment_active <= 1'b0;
        end else if (accepted_start) begin
            enum_trial_base     <= 32'd0;
            enum_L_base         <= 32'd0;
            enum_segment_active <= 1'b0;
        end else if (run_enum_mode) begin
            if (enum_bbht_start)
                enum_segment_active <= 1'b1;

            if (bbht_done && enum_segment_active) begin
                enum_trial_base     <= enum_trial_base + bbht_trial_count;
                enum_L_base         <= enum_L_base + bbht_L_BBHT;
                enum_segment_active <= 1'b0;
            end
        end
    end

    wire [31:0] enum_trial_visible = enum_trial_base +
        (enum_segment_active ? bbht_trial_count : 32'd0);
    wire [31:0] enum_L_visible = enum_L_base +
        (enum_segment_active ? bbht_L_BBHT : 32'd0);
    wire [31:0] algorithm_trial_count = run_enum_mode ? enum_trial_visible
                                                      : bbht_trial_count;
    wire [31:0] algorithm_L_BBHT = run_enum_mode ? enum_L_visible
                                                  : bbht_L_BBHT;

    //==========================================================================
    // Run-level final/status events
    //==========================================================================
    wire single_terminal = (!run_enum_mode) && bbht_done;
    wire overall_terminal_done = single_terminal | enum_terminal_pulse;

    wire overall_term_success = single_terminal && term_success;
    wire overall_term_config_error =
        (single_terminal && term_config_error) | enum_term_config_error;
    wire overall_term_zero_weight_error =
        (single_terminal && term_zero_weight_error) |
        enum_term_zero_weight_error;
    wire overall_term_shot_limit = single_terminal && term_shot_limit;
    wire overall_term_budget_limit = single_terminal && term_budget_limit;

    wire shot_limit_event = bbht_done && term_shot_limit;
    wire budget_limit_event = bbht_done && term_budget_limit;

    grover_status_counters u_status (
        .clk                    (clk),
        .rstn                   (rstn),
        .accepted_start         (accepted_start),
        .terminal_done          (overall_terminal_done),
        .term_success           (overall_term_success),
        .term_config_error      (overall_term_config_error),
        .term_shot_limit        (overall_term_shot_limit),
        .term_budget_limit      (overall_term_budget_limit),
        .term_zero_weight_error (overall_term_zero_weight_error),
        .success_index          (success_index),
        .shot_limit_event       (shot_limit_event),
        .budget_limit_event     (budget_limit_event),
        .amp_sat_event          (dp_sat_event),
        .algorithm_trial_count  (algorithm_trial_count),
        .algorithm_L_BBHT       (algorithm_L_BBHT),
        .iter_done              (physical_iter_done),
        .iter_count_completed   (physical_iter_count),
        .done                   (done),
        .result_valid           (result_valid),
        .result_index           (result_index),
        .config_error           (config_error),
        .shot_limit             (shot_limit),
        .budget_limit           (budget_limit),
        .amp_overflow           (amp_overflow),
        .zero_weight_error      (zero_weight_error),
        .trial_count            (trial_count),
        .L_BBHT                 (L_BBHT),
        .actual_grover_iterations(actual_grover_iterations),
        .cycle_count            (cycle_count)
    );

    // Integration observability guards retained during active verification.
    wire _unused_ckpt_rd_valid = ckpt_amp_rd_valid;
    wire _unused_ckpt_plan_error = ckpt_plan_error;
    wire _unused_ckpt_exec_aborted = ckpt_exec_aborted;
    wire _unused_ckpt_exec_busy = ckpt_exec_busy;
    wire _unused_ckpt_plan_retain = |ckpt_plan_retain_mask;
    wire _unused_ckpt_exec_debug = |ckpt_exec_physical_iter_issued |
                                   |ckpt_exec_bridge_count |
                                   |ckpt_exec_intermediate_commit_count |
                                   |ckpt_sorted_count | |ckpt_sorted_j_flat;

endmodule
