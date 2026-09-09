//==============================================================================
// lpsoc_bbht_grover_timing_wrapper.v
//
// LPSoC BBHT/Grover Main IP timing wrapper
// K4 / restricted-B / Rolling-H6 checkpoint configuration
// autonomous speculative IMPLEMENTATION/TIMING-ONLY wrapper
//
// Purpose
//   The Main IP has a wide generic core-level interface.  When it is used
//   directly as the FPGA top, Vivado maps those internal-system signals to
//   physical package pins and exceeds the xc7a100tcsg324-1 IOB budget.
//
//   This wrapper converts all wide Main-IP ports into INTERNAL registered
//   signals so place/route can be run on the real core logic with only a tiny
//   external pin count.
//
// IMPORTANT
//   * This is NOT the final board/AHB/CSR/DMA wrapper.
//   * Do not use this wrapper as the functional software interface.
//   * It exists only to obtain placed/routed timing for the current Main IP.
//   * Compile-time configuration is FORCED to CHECKPOINT_ENABLE=1,
//     CKPT_K=4, CKPT_MANUAL_ENABLE=0, AUTO_SPEC_ENABLE=1 so the K4/H6
//     checkpoint/policy hardware is retained while the Phase-4B manual
//     verification-only select cone is compile-time removed.  The hardware
//     cannot disappear through the Main-IP default CHECKPOINT_ENABLE=0.
//   * The core instance is DONT_TOUCH/KEEP_HIERARCHY so Vivado does not remove
//     the timing target merely because the internal stimulus is synthetic.
//
// External pins:
//   clk
//   rstn
//   activity_out   -- simple observable bit; not a functional result interface
//
// Clock constraint:
//   The existing core 100-MHz XDC still applies:
//       create_clock -period 10.000 -name clk [get_ports clk]
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module lpsoc_bbht_grover_timing_wrapper (
    input  wire clk,
    input  wire rstn,
    output wire activity_out
);

    //--------------------------------------------------------------------------
    // Synthetic INTERNAL registered stimulus
    //
    // These signals are intentionally registers, not constants.  That prevents
    // constant propagation from turning the implementation-only timing model
    // into a highly simplified special case.
    //--------------------------------------------------------------------------
    reg [31:0] stim_lfsr;

    reg                                  start_i;
    reg                                  auto_shot_i;
    reg [`GP_J_W-1:0]                   j_target_i;
    reg                                  burst_enable_i;
    reg                                  enum_enable_i;
    reg [`GP_ENUM_FAIL_W-1:0]            fail_repeat_limit_i;
    reg                                  res_pop_i;

    reg [1:0]                            predicate_mode_i;
    reg signed [`GP_DATA_W-1:0]          threshold_a_i;
    reg signed [`GP_DATA_W-1:0]          threshold_b_i;
    reg [`GP_DATA_COUNT_W-1:0]           data_count_i;

    reg [`GP_SHOT_CAP_W-1:0]             shot_cap_i;
    reg [31:0]                           seed_j_i;
    reg [31:0]                           seed_meas_i;

    reg                                  load_start_i;
    reg                                  data_wr_en_i;
    reg [`GP_INDEX_W-1:0]                data_wr_addr_i;
    reg signed [`GP_DATA_W-1:0]          data_wr_data_i;
    reg                                  load_done_i;

    // Same 32-bit LFSR recurrence used by the project PRNGs.  Here it is only
    // synthetic implementation stimulus; it is not architecturally visible.
    wire stim_feedback =
        stim_lfsr[31] ^ stim_lfsr[21] ^ stim_lfsr[1] ^ stim_lfsr[0];

    always @(posedge clk) begin
        if (!rstn) begin
            stim_lfsr       <= 32'h1ACE_B00C;

            start_i          <= 1'b0;
            auto_shot_i      <= 1'b0;
            j_target_i       <= {{(`GP_J_W-1){1'b0}},1'b1};
            burst_enable_i   <= 1'b0;
            enum_enable_i    <= 1'b0;
            fail_repeat_limit_i <= `GP_ENUM_FAIL_DEFAULT;
            res_pop_i        <= 1'b0;

            predicate_mode_i <= `GP_MODE_EQ;
            threshold_a_i    <= {`GP_DATA_W{1'b0}};
            threshold_b_i    <= {`GP_DATA_W{1'b0}};
            data_count_i     <= {{(`GP_DATA_COUNT_W-1){1'b0}},1'b1};

            shot_cap_i       <= `GP_SHOT_CAP_DEFAULT;
            seed_j_i         <= `GP_FALLBACK_J;
            seed_meas_i      <= `GP_FALLBACK_MEAS;

            load_start_i     <= 1'b0;
            data_wr_en_i     <= 1'b0;
            data_wr_addr_i   <= {`GP_INDEX_W{1'b0}};
            data_wr_data_i   <= {`GP_DATA_W{1'b0}};
            load_done_i      <= 1'b0;
        end else begin
            stim_lfsr <= {stim_lfsr[30:0], stim_feedback};

            // All Main-IP inputs remain flop-driven.  The exact stimulus is not
            // functionally important for STA; it only prevents constant-folding.
            start_i          <= stim_lfsr[0] & stim_lfsr[5];
            auto_shot_i      <= stim_lfsr[1];
            j_target_i       <= stim_lfsr[`GP_J_W-1:0];
            burst_enable_i   <= stim_lfsr[2];
            enum_enable_i    <= stim_lfsr[9];
            fail_repeat_limit_i <= {1'b0, stim_lfsr[12:10]} | 4'd1;
            res_pop_i        <= stim_lfsr[14];

            predicate_mode_i <= stim_lfsr[4:3];
            threshold_a_i    <= stim_lfsr[`GP_DATA_W-1:0];
            threshold_b_i    <= stim_lfsr[31 -: `GP_DATA_W];

            // Force the count non-zero while still allowing the width to toggle.
            data_count_i     <= {1'b0,
                                 stim_lfsr[`GP_DATA_COUNT_W-2:0]} |
                                {{(`GP_DATA_COUNT_W-1){1'b0}},1'b1};

            shot_cap_i       <= stim_lfsr[`GP_SHOT_CAP_W-1:0] |
                                {{(`GP_SHOT_CAP_W-1){1'b0}},1'b1};
            seed_j_i         <= stim_lfsr ^ 32'hA5A5_5A5A;
            seed_meas_i      <= {stim_lfsr[15:0], stim_lfsr[31:16]}
                                ^ 32'h5A5A_A5A5;

            load_start_i     <= stim_lfsr[6] & stim_lfsr[11];
            data_wr_en_i     <= stim_lfsr[7];
            data_wr_addr_i   <= stim_lfsr[`GP_INDEX_W-1:0];
            data_wr_data_i   <= stim_lfsr[`GP_DATA_W-1:0];
            load_done_i      <= stim_lfsr[8] & stim_lfsr[13];
        end
    end

    //--------------------------------------------------------------------------
    // Core outputs stay internal to avoid package-pin explosion.
    //--------------------------------------------------------------------------
    wire                                  load_busy_o;
    wire                                  busy_o;
    wire                                  done_o;
    wire                                  result_valid_o;
    wire [`GP_INDEX_W-1:0]                result_index_o;
    wire                                  enum_done_o;
    wire [`GP_FOUND_COUNT_W-1:0]          found_count_o;
    wire [`GP_ENUM_FAIL_W-1:0]            consecutive_fail_count_o;
    wire [`GP_INDEX_W-1:0]                res_dout_o;
    wire                                  res_empty_o;
    wire [`GP_RESULT_FIFO_CNT_W-1:0]      res_count_o;
    wire [`GP_RESULT_FIFO_CNT_W-1:0]      max_fifo_occupancy_o;
    wire [31:0]                           fifo_stall_cycles_o;

    wire                                  config_error_o;
    wire                                  shot_limit_o;
    wire                                  budget_limit_o;
    wire                                  amp_overflow_o;
    wire                                  zero_weight_error_o;
    wire                                  load_error_o;

    wire [31:0]                           trial_count_o;
    wire [31:0]                           L_BBHT_o;
    wire [31:0]                           actual_grover_iterations_o;
    wire [31:0]                           cycle_count_o;

    // Phase-6 autonomous-policy observability.
    wire [31:0]                           policy_cycles_total_o;
    wire [31:0]                           policy_stall_cycles_o;
    wire [31:0]                           policy_actions_eval_o;
    wire [31:0]                           policy_memo_hit_o;
    wire [31:0]                           policy_memo_miss_o;
    wire [31:0]                           policy_max_latency_o;

    // Speculative-plan observability.
    wire [2:0]                            plan_fifo_level_o;
    wire [2:0]                            plan_fifo_highwater_o;
    wire [31:0]                           plan_fifo_empty_demand_o;
    wire [31:0]                           plan_fifo_hit_count_o;
    wire [31:0]                           plan_fifo_mismatch_count_o;
    wire [31:0]                           policy_cold_solve_count_o;
    wire [31:0]                           policy_spec_solve_count_o;

    // Preserve the real Main-IP hierarchy/logic for placed-and-routed timing.
    (* DONT_TOUCH = "yes", KEEP_HIERARCHY = "yes" *)
    lpsoc_bbht_grover_main_ip #(
        .CHECKPOINT_ENABLE  (1),
        .CKPT_K             (4),
        .CKPT_MANUAL_ENABLE (0),
        .AUTO_SPEC_ENABLE   (1)
    ) u_core (
        .clk                     (clk),
        .rstn                    (rstn),

        .start                   (start_i),
        .auto_shot               (auto_shot_i),
        .j_target                (j_target_i),
        .burst_enable            (burst_enable_i),
        .enum_enable             (enum_enable_i),
        .fail_repeat_limit       (fail_repeat_limit_i),

        // Primary K4/H6 autonomous mode.  Manual-policy inputs are tied off.
        .checkpoint_manual_enable(1'b0),
        .policy_valid            (1'b0),
        .policy_source_j         ({`GP_J_W{1'b0}}),
        .policy_next_count       (3'd0),
        .policy_next_j_flat      ({(4*`GP_J_W){1'b0}}),
        .checkpoint_auto_enable  (1'b1),

        .predicate_mode          (predicate_mode_i),
        .threshold_a             (threshold_a_i),
        .threshold_b             (threshold_b_i),
        .data_count              (data_count_i),

        .shot_cap                (shot_cap_i),
        .seed_j                  (seed_j_i),
        .seed_meas               (seed_meas_i),

        .load_start              (load_start_i),
        .data_wr_en              (data_wr_en_i),
        .data_wr_addr            (data_wr_addr_i),
        .data_wr_data            (data_wr_data_i),
        .load_done               (load_done_i),
        .load_busy               (load_busy_o),

        .res_pop                 (res_pop_i),
        .res_dout                (res_dout_o),
        .res_empty               (res_empty_o),
        .res_count               (res_count_o),

        .busy                    (busy_o),
        .done                    (done_o),
        .result_valid            (result_valid_o),
        .result_index            (result_index_o),
        .enum_done               (enum_done_o),
        .found_count             (found_count_o),
        .consecutive_fail_count  (consecutive_fail_count_o),
        .max_fifo_occupancy      (max_fifo_occupancy_o),
        .fifo_stall_cycles       (fifo_stall_cycles_o),

        .config_error            (config_error_o),
        .shot_limit              (shot_limit_o),
        .budget_limit            (budget_limit_o),
        .amp_overflow            (amp_overflow_o),
        .zero_weight_error       (zero_weight_error_o),
        .load_error              (load_error_o),

        .trial_count             (trial_count_o),
        .L_BBHT                  (L_BBHT_o),
        .actual_grover_iterations(actual_grover_iterations_o),
        .cycle_count             (cycle_count_o),

        .policy_cycles_total     (policy_cycles_total_o),
        .policy_stall_cycles     (policy_stall_cycles_o),
        .policy_actions_eval     (policy_actions_eval_o),
        .policy_memo_hit         (policy_memo_hit_o),
        .policy_memo_miss        (policy_memo_miss_o),
        .policy_max_latency      (policy_max_latency_o),

        .plan_fifo_level         (plan_fifo_level_o),
        .plan_fifo_highwater     (plan_fifo_highwater_o),
        .plan_fifo_empty_demand  (plan_fifo_empty_demand_o),
        .plan_fifo_hit_count     (plan_fifo_hit_count_o),
        .plan_fifo_mismatch_count(plan_fifo_mismatch_count_o),
        .policy_cold_solve_count (policy_cold_solve_count_o),
        .policy_spec_solve_count (policy_spec_solve_count_o)
    );

    // One small observable pin.  Keeping this combinational avoids introducing
    // an artificial wide output-reduction setup path into the timing analysis.
    assign activity_out = busy_o ^ done_o ^ result_valid_o ^
                          config_error_o ^ shot_limit_o ^ budget_limit_o ^
                          amp_overflow_o ^ zero_weight_error_o ^ load_error_o ^
                          enum_done_o ^ res_empty_o ^ found_count_o[0] ^
                          plan_fifo_level_o[0] ^ policy_spec_solve_count_o[0];

endmodule
