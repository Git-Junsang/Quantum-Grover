//==============================================================================
// lpsoc_bbht_grover_main_ip.v -- hardware_dram branch, BBHT/Grover Main IP
// with per-iteration full-history DRAM amplitude storage.
//
// This replaces hardware_bram/src_v2/lpsoc_bbht_grover_main_ip.v's K3/K4
// checkpoint execution (grover_checkpoint.v) and rolling-H lookahead policy
// engine (grover_policy.v) with a much smaller mechanism: every completed
// Grover iteration's full 512-row amplitude table is streamed to DRAM
// (grover_dram_amp_store.v), so reaching any j in [0, GP_M_MAX] again is one
// direct burst restore, never a replay. See grover_dram_prep_seq.v for the
// decision logic and grover_dram_param.vh for why this needs no policy
// engine at all. The external CSR/port contract is kept byte-identical to
// hardware_bram's bbht_grover_core (software/contract/port_contract.tsv
// §3.4) so the shared communication layer and CSR map do not change.
//
// v1 scope -- Single Search only (MANUAL_SINGLE / NORMAL_SINGLE)
//   enum_enable=1 is rejected as a config_error rather than silently
//   ignored. Enumeration needs its own multi-candidate result stream and
//   found-mask exclusion; more importantly it is the mode that actually
//   wants cross-round speculation (drawing/preparing the next candidate
//   before the current one's verify result is known), and
//   grover_dram_prep_seq.v deliberately does not attempt that yet (see its
//   header comment: BBHT's round_idx/m_bound schedule only advances after a
//   confirmed failure, so speculating past that boundary needs the same
//   kind of speculative-epoch bookkeeping hardware_bram's AUTO_SPEC_ENABLE
//   path uses). Wiring Enumeration on top of grover_dram_shot_fsm.v is
//   future work once that is designed.
//
//   checkpoint_manual_enable / policy_* / checkpoint_auto_enable are
//   accepted as ports (contract compatibility) and otherwise unused: this
//   branch has no checkpoint concept to configure. Policy/plan telemetry
//   outputs are tied to 0 for the same reason; this branch's own DRAM
//   store/restore telemetry is exposed separately (dram_frontier_j etc.)
//   and is not yet mapped to a CSR register.
//==============================================================================
`timescale 1ns/1ps
`include "grover_dram_param.vh"

module lpsoc_bbht_grover_main_ip (
    input  wire                                  clk,
    input  wire                                  rstn,

    // Search control.
    input  wire                                  start,
    input  wire                                  auto_shot,
    input  wire [`GP_J_W-1:0]                   j_target,
    input  wire                                  burst_enable,
    input  wire                                  enum_enable,
    input  wire [`GP_ENUM_FAIL_W-1:0]           fail_repeat_limit,

    // Checkpoint (manual) -- contract compatibility only, unused in this
    // branch. See top comment.
    input  wire                                  checkpoint_manual_enable,
    input  wire                                  policy_valid,
    input  wire [`GP_J_W-1:0]                   policy_source_j,
    input  wire [2:0]                            policy_next_count,
    input  wire [4*`GP_J_W-1:0]                 policy_next_j_flat,

    // Checkpoint (auto) -- contract compatibility only, unused.
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

    // Result FIFO consumer interface. Never pushed in v1 (Enumeration only);
    // stays permanently empty, matching hardware_bram's own Single-Search
    // behavior (Single Search reports through result_valid/result_index,
    // not the FIFO).
    input  wire                                  res_pop,
    output wire [`GP_INDEX_W-1:0]                res_dout,
    output wire                                  res_empty,
    output wire [`GP_RESULT_FIFO_CNT_W-1:0]      res_count,

    // Aggregate execution/result interface.
    output wire                                  busy,
    output wire                                  done,
    output wire                                  result_valid,
    output wire [`GP_INDEX_W-1:0]                result_index,

    // Enumeration status/result summary -- not implemented in v1, tied off.
    output wire                                  enum_done,
    output wire [`GP_FOUND_COUNT_W-1:0]          found_count,
    output wire [`GP_ENUM_FAIL_W-1:0]            consecutive_fail_count,
    output wire [`GP_RESULT_FIFO_CNT_W-1:0]      max_fifo_occupancy,
    output wire [31:0]                           fifo_stall_cycles,

    // Sticky status until next accepted external start.
    output wire                                  config_error,
    output wire                                  shot_limit,
    output wire                                  budget_limit,
    output wire                                  amp_overflow,
    output wire                                  zero_weight_error,
    output wire                                  load_error,

    // Performance counters.
    output wire [31:0]                           trial_count,
    output wire [31:0]                           L_BBHT,
    output wire [31:0]                           actual_grover_iterations,
    output wire [31:0]                           cycle_count,

    // Policy telemetry -- not implemented in v1, tied off.
    output wire [31:0]                           policy_cycles_total,
    output wire [31:0]                           policy_stall_cycles,
    output wire [31:0]                           policy_actions_eval,
    output wire [31:0]                           policy_memo_hit,
    output wire [31:0]                           policy_memo_miss,
    output wire [31:0]                           policy_max_latency,

    // Plan telemetry -- not implemented in v1, tied off.
    output wire [2:0]                            plan_fifo_level,
    output wire [2:0]                            plan_fifo_highwater,
    output wire [31:0]                           plan_fifo_empty_demand,
    output wire [31:0]                           plan_fifo_hit_count,
    output wire [31:0]                           plan_fifo_mismatch_count,
    output wire [31:0]                           policy_cold_solve_count,
    output wire [31:0]                           policy_spec_solve_count,

    //--------------------------------------------------------------------
    // Abstract DRAM burst port (grover_dram_amp_store.v). NOT part of the
    // bbht_grover_core contract -- physical binding (MIG native UI, AXI4,
    // ...) is undecided; see grover_dram_param.vh. Left unconnected at the
    // RVX integration boundary until that is designed.
    //--------------------------------------------------------------------
    output wire                                  dram_wr_req,
    output wire [`GD_ADDR_W-1:0]                 dram_wr_addr,
    output wire [`GD_BURST_LEN_W-1:0]            dram_wr_len,
    output wire                                  dram_wr_valid,
    output wire [`GP_P*`GP_AMP_W-1:0]            dram_wr_data,
    output wire                                  dram_wr_last,
    input  wire                                  dram_wr_ready,

    output wire                                  dram_rd_req,
    output wire [`GD_ADDR_W-1:0]                 dram_rd_addr,
    output wire [`GD_BURST_LEN_W-1:0]            dram_rd_len,
    input  wire                                  dram_rd_valid,
    input  wire [`GP_P*`GP_AMP_W-1:0]            dram_rd_data,
    output wire                                  dram_rd_ready,
    input  wire                                  dram_rd_last,

    // DRAM store/restore debug visibility (not yet a CSR).
    output wire [`GP_J_W-1:0]                    dram_frontier_j
);
    // burst_enable/policy_*/checkpoint_* ports are accepted for contract
    // compatibility and intentionally unused: this branch has no burst/
    // checkpoint concept (every reachable j is always available from DRAM
    // once grown, unconditionally).
    wire _unused_contract_ports = burst_enable | checkpoint_manual_enable |
        policy_valid | (|policy_source_j) | (|policy_next_count) |
        (|policy_next_j_flat) | checkpoint_auto_enable | (|fail_repeat_limit);

    assign policy_cycles_total      = 32'd0;
    assign policy_stall_cycles      = 32'd0;
    assign policy_actions_eval      = 32'd0;
    assign policy_memo_hit          = 32'd0;
    assign policy_memo_miss         = 32'd0;
    assign policy_max_latency       = 32'd0;
    assign plan_fifo_level          = 3'd0;
    assign plan_fifo_highwater      = 3'd0;
    assign plan_fifo_empty_demand   = 32'd0;
    assign plan_fifo_hit_count      = 32'd0;
    assign plan_fifo_mismatch_count = 32'd0;
    assign policy_cold_solve_count  = 32'd0;
    assign policy_spec_solve_count  = 32'd0;
    assign enum_done                = 1'b0;
    assign found_count              = {`GP_FOUND_COUNT_W{1'b0}};
    assign consecutive_fail_count   = {`GP_ENUM_FAIL_W{1'b0}};
    assign max_fifo_occupancy       = {`GP_RESULT_FIFO_CNT_W{1'b0}};
    assign fifo_stall_cycles        = 32'd0;

    //==========================================================================
    // Loader (byte-identical wiring to hardware_bram).
    //==========================================================================
    wire loader_mem_wr_en;
    wire [`GP_INDEX_W-1:0] loader_mem_wr_addr;
    wire signed [`GP_DATA_W-1:0] loader_mem_wr_data;
    wire data_valid;
    wire loader_cache_invalidate;
    wire [`GP_DATA_COUNT_W-1:0] load_expected_count;
    wire [`GP_DATA_COUNT_W-1:0] load_write_count;
    wire [`GP_DATA_COUNT_W-1:0] loaded_count;

    wire shot_busy;
    wire shot_done_pulse;
    wire search_busy = shot_busy | shot_done_pulse;

    wire accepted_start = start && !search_busy && !load_busy;
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
        .accepted_load_start (),
        .cache_invalidate    (loader_cache_invalidate),
        .expected_count      (load_expected_count),
        .write_count         (load_write_count),
        .loaded_count        (loaded_count)
    );

    //==========================================================================
    // Per-run configuration snapshot.
    //==========================================================================
    reg                                  run_auto_shot;
    reg [`GP_J_W-1:0]                   run_j_target;
    reg [1:0]                            run_predicate_mode;
    reg signed [`GP_DATA_W-1:0]          run_threshold_a;
    reg signed [`GP_DATA_W-1:0]          run_threshold_b;
    reg [`GP_DATA_COUNT_W-1:0]           run_data_count;
    reg [`GP_SHOT_CAP_W-1:0]             run_shot_cap;
    reg                                  run_enum_request;

    always @(posedge clk) begin
        if (!rstn) begin
            run_auto_shot       <= 1'b0;
            run_j_target        <= {`GP_J_W{1'b0}};
            run_predicate_mode  <= `GP_MODE_LT;
            run_threshold_a     <= {`GP_DATA_W{1'b0}};
            run_threshold_b     <= {`GP_DATA_W{1'b0}};
            run_data_count      <= {`GP_DATA_COUNT_W{1'b0}};
            run_shot_cap        <= `GP_SHOT_CAP_DEFAULT;
            run_enum_request    <= 1'b0;
        end else if (accepted_start) begin
            run_auto_shot       <= auto_shot;
            run_j_target        <= j_target;
            run_predicate_mode  <= predicate_mode;
            run_threshold_a     <= threshold_a;
            run_threshold_b     <= threshold_b;
            run_data_count      <= data_count;
            run_shot_cap        <= shot_cap;
            run_enum_request    <= (enum_enable === 1'b1);
        end
    end

    wire run_data_count_valid =
        (run_data_count != {`GP_DATA_COUNT_W{1'b0}}) &&
        (run_data_count <= `GP_N);
    wire run_config_ok = data_valid && run_data_count_valid &&
                         (run_data_count == loaded_count) &&
                         !run_enum_request;

    //==========================================================================
    // DRAM-table invalidation: any accepted-run semantic change forces the
    // next grover_dram_prep_seq request to rebuild from j=0 instead of
    // trusting a DRAM table written under old Oracle/threshold semantics.
    // Same trigger set as hardware_bram's cache_invalidate, minus the
    // checkpoint/enum-mode terms that do not exist in this branch.
    //==========================================================================
    reg                                    accepted_cfg_seen;
    reg [1:0]                              prev_predicate_mode;
    reg signed [`GP_DATA_W-1:0]            prev_threshold_a;
    reg signed [`GP_DATA_W-1:0]            prev_threshold_b;
    reg [`GP_DATA_COUNT_W-1:0]             prev_data_count;

    wire semantic_cfg_change_on_start = accepted_start && accepted_cfg_seen &&
        ((predicate_mode != prev_predicate_mode) ||
         (threshold_a    != prev_threshold_a)    ||
         (threshold_b    != prev_threshold_b)    ||
         (data_count     != prev_data_count));

    always @(posedge clk) begin
        if (!rstn) begin
            accepted_cfg_seen   <= 1'b0;
            prev_predicate_mode <= `GP_MODE_LT;
            prev_threshold_a    <= {`GP_DATA_W{1'b0}};
            prev_threshold_b    <= {`GP_DATA_W{1'b0}};
            prev_data_count     <= {`GP_DATA_COUNT_W{1'b0}};
        end else if (accepted_start) begin
            accepted_cfg_seen   <= 1'b1;
            prev_predicate_mode <= predicate_mode;
            prev_threshold_a    <= threshold_a;
            prev_threshold_b    <= threshold_b;
            prev_data_count     <= data_count;
        end
    end

    wire dram_invalidate = loader_cache_invalidate | semantic_cfg_change_on_start;

    //==========================================================================
    // Outer BBHT shot controller.
    //==========================================================================
    wire prep_start;
    wire [`GP_J_W-1:0] prep_target_j;
    wire prep_done;

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

    grover_dram_shot_fsm u_shot (
        .clk                    (clk),
        .rstn                   (rstn),
        // 등록본(run_enum_request)이 아니라 입력 그대로를 봐야 합니다.
        // run_enum_request 는 accepted_start 와 같은 엣지에 갱신되므로 이
        // 시점에는 아직 "직전 실행" 의 값입니다. 등록본으로 게이팅하면
        // enum 요청으로 한 번 거절된 뒤의 평범한 실행이 시작조차 못 하고,
        // shot FSM 이 안 돌면 terminal done 도 없어 호스트가 영영 done 을
        // 기다립니다 (tb_dram_core C7).
        .start                  (accepted_start && (enum_enable !== 1'b1)),
        .config_ok              (run_config_ok),
        .auto_shot              (run_auto_shot),
        .j_target               (run_j_target),
        .shot_cap               (run_shot_cap),
        .seed_j                 (seed_j),
        .seed_reload            (accepted_start),

        .prep_start             (prep_start),
        .prep_target_j          (prep_target_j),
        .prep_done              (prep_done),

        .meas_start             (meas_start),
        .meas_done              (meas_done),
        .meas_verify_hit        (meas_verify_hit),
        .meas_zero_weight_error (meas_zero_weight_error),
        .meas_candidate         (meas_candidate),

        .busy                   (shot_busy),
        .done                   (shot_done_pulse),
        .term_success           (term_success),
        .term_config_error      (term_config_error),
        .term_shot_limit        (term_shot_limit),
        .term_budget_limit      (term_budget_limit),
        .term_zero_weight_error (term_zero_weight_error),
        .success_index          (success_index),

        .round_idx              (),
        .current_m_bound        (),
        .current_j              (),
        .trial_count            (bbht_trial_count),
        .L_BBHT                 (bbht_L_BBHT),
        .j_rnd_draw             (),
        .j_rnd_state            ()
    );

    wire [31:0] bbht_trial_count;
    wire [31:0] bbht_L_BBHT;

    // A start with enum_enable=1 is a config error, not a silent Single
    // Search fallback: Enumeration is not implemented in this branch (see
    // top comment). The shot FSM never starts for such a request, so this
    // must be raised independently, on the same accepted_start edge.
    reg  enum_reject_pulse;
    always @(posedge clk) begin
        if (!rstn)
            enum_reject_pulse <= 1'b0;
        else
            enum_reject_pulse <= accepted_start && (enum_enable === 1'b1);
    end

    //==========================================================================
    // DRAM store/restore engine + buffer-A prep sequencer.
    //==========================================================================
    wire prep_iter_start, prep_iter_do_init;
    wire [15:0] prep_iter_count;
    wire prep_store_start, prep_restore_start;
    wire [`GP_J_W-1:0] prep_store_j, prep_restore_j;
    wire store_done, restore_done;
    wire a_role_grow, a_role_store, a_role_restore;

    grover_dram_prep_seq u_prep (
        .clk             (clk),
        .rstn            (rstn),
        .dram_invalidate (dram_invalidate),
        .prep_start      (prep_start),
        .prep_target_j   (prep_target_j),
        .prep_busy       (),
        .prep_done       (prep_done),
        .iter_start      (prep_iter_start),
        .iter_do_init    (prep_iter_do_init),
        .iter_count      (prep_iter_count),
        .iter_done       (iter_done),
        .store_start     (prep_store_start),
        .store_j         (prep_store_j),
        .store_done      (store_done),
        .restore_start   (prep_restore_start),
        .restore_j       (prep_restore_j),
        .restore_done    (restore_done),
        .a_role_grow     (a_role_grow),
        .a_role_store    (a_role_store),
        .a_role_restore  (a_role_restore),
        .frontier_j      (dram_frontier_j),
        .buf_a_valid     (),
        .buf_a_j         ()
    );

    wire [`GP_ROW_W-1:0] store_rd_row;
    wire store_rd_en;
    wire [`GP_P*`GP_AMP_W-1:0] store_rd_data;
    wire [`GP_ROW_W-1:0] restore_wr_row;
    wire restore_wr_en;
    wire [`GP_P*`GP_AMP_W-1:0] restore_wr_data;

    grover_dram_amp_store u_amp_store (
        .clk            (clk),
        .rstn           (rstn),
        .store_start    (prep_store_start),
        .store_j        (prep_store_j),
        .store_busy     (),
        .store_done     (store_done),
        .store_rd_row   (store_rd_row),
        .store_rd_en    (store_rd_en),
        .store_rd_data  (store_rd_data),
        .restore_start  (prep_restore_start),
        .restore_j      (prep_restore_j),
        .restore_busy   (),
        .restore_done   (restore_done),
        .restore_wr_row (restore_wr_row),
        .restore_wr_en  (restore_wr_en),
        .restore_wr_data(restore_wr_data),
        .dram_wr_req    (dram_wr_req),
        .dram_wr_addr   (dram_wr_addr),
        .dram_wr_len    (dram_wr_len),
        .dram_wr_valid  (dram_wr_valid),
        .dram_wr_data   (dram_wr_data),
        .dram_wr_last   (dram_wr_last),
        .dram_wr_ready  (dram_wr_ready),
        .dram_rd_req    (dram_rd_req),
        .dram_rd_addr   (dram_rd_addr),
        .dram_rd_len    (dram_rd_len),
        .dram_rd_valid  (dram_rd_valid),
        .dram_rd_data   (dram_rd_data),
        .dram_rd_ready  (dram_rd_ready),
        .dram_rd_last   (dram_rd_last)
    );

    //==========================================================================
    // Inner Grover controller + v0.7g datapath (byte-identical to
    // hardware_bram's plain, non-checkpoint grover_ctrl_fsm).
    //==========================================================================
    wire [3:0] iter_state;
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
    wire iter_pass_tick;
    wire iter_busy;
    wire iter_done;

    grover_ctrl_fsm u_iter_ctrl (
        .clk            (clk),
        .rstn           (rstn),
        .iter_start     (prep_iter_start),
        .iter_do_init   (prep_iter_do_init),
        .iter_count     (prep_iter_count),
        .iter_busy      (iter_busy),
        .iter_done      (iter_done),
        .state          (iter_state),
        .amp_rd_row     (iter_amp_rd_row),
        .amp_rd_en      (iter_amp_rd_en),
        .data_rd_row    (iter_data_rd_row),
        .data_rd_en     (iter_data_rd_en),
        .dp_op          (dp_op),
        .dp_row_valid   (dp_row_valid),
        .dp_row_index   (dp_row_index),
        .acc_clear      (dp_acc_clear),
        .amp_wr_en      (ctrl_amp_wr_en),
        .amp_wr_row     (ctrl_amp_wr_row),
        .pass_tick      (iter_pass_tick)
    );

    localparam integer AMP_ROW_BITS  = `GP_P * `GP_AMP_W;
    localparam integer DATA_ROW_BITS = `GP_P * `GP_DATA_W;

    wire [AMP_ROW_BITS-1:0] grow_rd_amp;
    wire [DATA_ROW_BITS-1:0] data_mem_row_rdata;
    wire [AMP_ROW_BITS-1:0] dp_amp_row_out;
    wire dp_row_out_valid;
    wire [`GP_ROW_W-1:0] dp_row_out_index;
    wire signed [`GP_PARTIAL_SUM_W-1:0] dp_row_partial_sum;
    wire signed [`GP_ACC_W-1:0] dp_global_sum;
    wire signed [`GP_TWO_MEAN_W-1:0] dp_two_mean;
    wire dp_sat_event;
    wire [`GP_P-1:0] found_mask_row_zero = {`GP_P{1'b0}};

    // Growth never touches amp_mem's writeback path directly; the datapath's
    // registered oracle/diffusion row output feeds it. row_out_valid gates
    // the write exactly as hardware_bram does; there is no concurrent
    // measurement write-forbid to AND in because a_role_grow / a_role_measure
    // are mutually exclusive on buffer A by grover_dram_shot_fsm's
    // PREP-then-MEASURE sequencing (never both at once).
    wire grow_wr_en = ctrl_amp_wr_en && dp_row_out_valid;

    grover_iter_datapath u_iter_dp (
        .clk              (clk),
        .rstn             (rstn),
        .op               (dp_op),
        .row_valid        (dp_row_valid),
        .row_index        (dp_row_index),
        .acc_clear        (dp_acc_clear),
        .amp_row_in       (grow_rd_amp),
        .data_row_in      (data_mem_row_rdata),
        .found_mask_row_in(found_mask_row_zero),
        .predicate_mode   (run_predicate_mode),
        .threshold_a      (run_threshold_a),
        .threshold_b      (run_threshold_b),
        .data_count       (run_data_count),
        .enum_enable      (1'b0),
        .amp_row_out      (dp_amp_row_out),
        .row_out_valid    (dp_row_out_valid),
        .row_out_index    (dp_row_out_index),
        .row_partial_sum  (dp_row_partial_sum),
        .global_sum       (dp_global_sum),
        .two_mean         (dp_two_mean),
        .sat_event        (dp_sat_event)
    );

    //==========================================================================
    // Measurement PRNG: reload once per accepted external run.
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
    // Born + classical verify.
    //==========================================================================
    wire meas_busy;
    wire meas_amp_write_forbid;
    wire [`GP_ROW_W-1:0] meas_amp_rd_row;
    wire meas_amp_rd_en;
    wire [`GP_INDEX_W-1:0] data_verify_index;
    wire signed [`GP_DATA_W-1:0] data_verify_value;
    wire [`GP_TOTAL_WEIGHT_W-1:0] meas_total_weight;
    wire [`GP_TOTAL_WEIGHT_W-1:0] meas_threshold;
    wire [`GP_ROW_W-1:0] meas_selected_row;
    wire [AMP_ROW_BITS-1:0] meas_rd_amp;

    grover_measure_verify #(
        .AMP_READ_LATENCY(1)
    ) u_measure_verify (
        .clk                    (clk),
        .rstn                   (rstn),
        .start                  (meas_start),
        .predicate_mode         (run_predicate_mode),
        .threshold_a            (run_threshold_a),
        .threshold_b            (run_threshold_b),
        .data_count             (run_data_count),
        .enum_enable            (1'b0),
        .found_mask_verify_found(1'b0),
        .rnd                    (meas_rnd_state),
        .rnd_draw               (meas_rnd_draw),
        .amp_rdata              (meas_rd_amp),
        .amp_rd_row             (meas_amp_rd_row),
        .amp_rd_en              (meas_amp_rd_en),
        .data_verify_index      (data_verify_index),
        .data_verify_value      (data_verify_value),
        .busy                   (meas_busy),
        .done                   (meas_done),
        .verify_hit             (meas_verify_hit),
        .zero_weight_error      (meas_zero_weight_error),
        .candidate              (meas_candidate),
        .amp_write_forbid       (meas_amp_write_forbid),
        .total_weight           (meas_total_weight),
        .measurement_threshold  (meas_threshold),
        .selected_row           (meas_selected_row)
    );

    //==========================================================================
    // Candidate buffer queue (grover_dram_queue.v). v1 drives buffer A only;
    // buffer B's role selects are tied off (see grover_dram_prep_seq.v top
    // comment for why cross-round prefetch is deferred).
    //==========================================================================
    grover_dram_queue u_queue (
        .clk             (clk),

        .a_role_grow     (a_role_grow),
        .a_role_store    (a_role_store),
        .a_role_restore  (a_role_restore),
        .a_role_measure  (meas_busy),

        .b_role_grow     (1'b0),
        .b_role_store    (1'b0),
        .b_role_restore  (1'b0),
        .b_role_measure  (1'b0),

        .grow_rd_row     (iter_amp_rd_row),
        .grow_rd_en      (iter_amp_rd_en),
        .grow_rd_amp     (grow_rd_amp),
        .grow_wr_row     (ctrl_amp_wr_row),
        .grow_wr_en      (grow_wr_en),
        .grow_wr_amp     (dp_amp_row_out),

        .store_rd_row    (store_rd_row),
        .store_rd_en     (store_rd_en),
        .store_rd_amp    (store_rd_data),

        .restore_wr_row  (restore_wr_row),
        .restore_wr_en   (restore_wr_en),
        .restore_wr_amp  (restore_wr_data),

        .meas_rd_row     (meas_amp_rd_row),
        .meas_rd_en      (meas_amp_rd_en),
        .meas_rd_amp     (meas_rd_amp)
    );

    //==========================================================================
    // Dataset + result memories (byte-identical to hardware_bram).
    //==========================================================================
    grover_data_mem u_data_mem (
        .clk          (clk),
        .rd_row       (iter_data_rd_row),
        .rd_en        (iter_data_rd_en),
        .rd_data      (data_mem_row_rdata),
        .wr_index     (loader_mem_wr_addr),
        .wr_en        (loader_mem_wr_en),
        .wr_data      (loader_mem_wr_data),
        .verify_index (data_verify_index),
        .verify_data  (data_verify_value)
    );

    // v1 never pushes (Enumeration only); stays permanently empty.
    grover_result_fifo #(
        .DEPTH (`GP_RESULT_FIFO_DEPTH),
        .CNT_W (`GP_RESULT_FIFO_CNT_W)
    ) u_result_fifo (
        .clk         (clk),
        .rstn        (rstn),
        .clear       (accepted_start),
        .push        (1'b0),
        .push_data   ({`GP_INDEX_W{1'b0}}),
        .push_accept (),
        .pop         (res_pop),
        .dout        (res_dout),
        .pop_accept  (),
        .empty       (res_empty),
        .full        (),
        .count       (res_count)
    );

    //==========================================================================
    // Run-level status/counters.
    //==========================================================================
    wire overall_terminal_done       = shot_done_pulse | enum_reject_pulse;
    wire overall_term_success        = shot_done_pulse && term_success;
    wire overall_term_config_error   =
        (shot_done_pulse && term_config_error) | enum_reject_pulse;
    wire overall_term_zero_weight_error = shot_done_pulse && term_zero_weight_error;
    wire overall_term_shot_limit     = shot_done_pulse && term_shot_limit;
    wire overall_term_budget_limit   = shot_done_pulse && term_budget_limit;

    grover_status_counters u_status (
        .clk                     (clk),
        .rstn                    (rstn),
        .accepted_start          (accepted_start),
        .terminal_done           (overall_terminal_done),
        .term_success            (overall_term_success),
        .term_config_error       (overall_term_config_error),
        .term_shot_limit         (overall_term_shot_limit),
        .term_budget_limit       (overall_term_budget_limit),
        .term_zero_weight_error  (overall_term_zero_weight_error),
        .success_index           (success_index),
        .shot_limit_event        (overall_term_shot_limit),
        .budget_limit_event      (overall_term_budget_limit),
        .amp_sat_event           (dp_sat_event),
        // enum 거절로 끝난 실행은 shot FSM 이 아예 안 돌았으므로 그 안의
        // trial_count/L_BBHT 는 직전 실행 값 그대로입니다. 그대로 넘기면
        // 거절된 실행의 카운터가 남의 숫자를 들고 있게 되므로 0 으로
        // 덮습니다 (config_error 실행의 카운터는 의미가 없어야 합니다).
        .algorithm_trial_count   (enum_reject_pulse ? 32'd0 : bbht_trial_count),
        .algorithm_L_BBHT        (enum_reject_pulse ? 32'd0 : bbht_L_BBHT),
        .iter_done               (iter_done),
        .iter_count_completed    (prep_iter_count),
        .done                    (done),
        .result_valid            (result_valid),
        .result_index            (result_index),
        .config_error            (config_error),
        .shot_limit              (shot_limit),
        .budget_limit            (budget_limit),
        .amp_overflow            (amp_overflow),
        .zero_weight_error       (zero_weight_error),
        .trial_count             (trial_count),
        .L_BBHT                  (L_BBHT),
        .actual_grover_iterations(actual_grover_iterations),
        .cycle_count             (cycle_count)
    );

    // Debug/Golden-trace signals with no external port in v1. Referencing
    // them here keeps lint from flagging dead nets without discarding the
    // observability for a future waveform/ILA hook.
    wire _unused_debug_bus =
        iter_busy | iter_pass_tick | (|iter_state) |
        meas_amp_write_forbid | (|meas_total_weight) | (|meas_threshold) |
        (|meas_selected_row) | (|dp_row_out_index) | (|dp_row_partial_sum) |
        (|dp_global_sum) | (|dp_two_mean) | (|load_expected_count) |
        (|load_write_count);

endmodule
