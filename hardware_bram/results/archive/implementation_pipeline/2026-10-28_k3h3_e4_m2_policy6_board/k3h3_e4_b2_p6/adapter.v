// Generated from manifest.json; parameter defaults below are authoritative.
`timescale 1ns/1ps

`ifndef GP_MEAS_M3_DEFAULT
`define GP_MEAS_M3_DEFAULT 1
`endif

module bbht_grover_core #(
    parameter integer CHECKPOINT_ENABLE  = 1,
    parameter integer CKPT_K             = 3,
    parameter integer POLICY_H_FUTURE    = 3,
    parameter integer POLICY_EXACT_PRUNE = 6,
    parameter integer CKPT_MANUAL_ENABLE = 0,
    parameter integer AUTO_SPEC_ENABLE   = 1,
    parameter integer INTRA_ENGINES      = 4,
    parameter integer MEAS_M1_ENABLE     = 1,
    parameter integer MEAS_M2_ENABLE     = 1,
    parameter integer MEAS_M3_ENABLE     = `GP_MEAS_M3_DEFAULT,
    parameter integer MEAS_BUILD_ROWS = 2
) (
    input  wire        clk,
    input  wire        rstnn,

    // Search / Mode
    input  wire        start,
    input  wire        auto_shot,
    input  wire [6:0]  j_target,
    input  wire        burst_enable,
    input  wire        enum_enable,
    input  wire [3:0]  fail_repeat_limit,

    // Checkpoint (manual)
    input  wire        checkpoint_manual_enable,
    input  wire        policy_valid,
    input  wire [6:0]  policy_source_j,
    input  wire [2:0]  policy_next_count,
    input  wire [27:0] policy_next_j_flat,

    // Checkpoint (auto)
    input  wire        checkpoint_auto_enable,

    // Oracle
    input  wire [1:0]  predicate_mode,
    input  wire signed [15:0] threshold_a,
    input  wire signed [15:0] threshold_b,
    input  wire [14:0] data_count,

    // BBHT / RNG
    input  wire [15:0] shot_cap,
    input  wire [31:0] seed_j,
    input  wire [31:0] seed_meas,

    // Loader
    input  wire        load_start,
    input  wire        data_wr_en,
    input  wire [13:0] data_wr_addr,
    input  wire signed [15:0] data_wr_data,
    input  wire        load_done,
    output wire        load_busy,

    // Result FIFO
    input  wire        res_pop,
    output wire [13:0] res_dout,
    output wire        res_empty,
    output wire [8:0]  res_count,

    // Execution
    output wire        busy,
    output wire        done,
    output wire        result_valid,
    output wire [13:0] result_index,

    // Enumeration
    output wire        enum_done,
    output wire [14:0] found_count,
    output wire [3:0]  consecutive_fail_count,
    output wire [8:0]  max_fifo_occupancy,
    output wire [31:0] fifo_stall_cycles,

    // Status (sticky)
    output wire        config_error,
    output wire        shot_limit,
    output wire        budget_limit,
    output wire        amp_overflow,
    output wire        zero_weight_error,
    output wire        load_error,

    // Counters
    output wire [31:0] trial_count,
    output wire [31:0] L_BBHT,
    output wire [31:0] actual_grover_iterations,
    output wire [31:0] cycle_count,

    // Policy telemetry
    output wire [31:0] policy_cycles_total,
    output wire [31:0] policy_stall_cycles,
    output wire [31:0] policy_actions_eval,
    output wire [31:0] policy_memo_hit,
    output wire [31:0] policy_memo_miss,
    output wire [31:0] policy_max_latency,

    // Plan telemetry
    output wire [2:0]  plan_fifo_level,
    output wire [2:0]  plan_fifo_highwater,
    output wire [31:0] plan_fifo_empty_demand,
    output wire [31:0] plan_fifo_hit_count,
    output wire [31:0] plan_fifo_mismatch_count,
    output wire [31:0] policy_cold_solve_count,
    output wire [31:0] policy_spec_solve_count
);

    bbht_grover_main_ip #(
        .CHECKPOINT_ENABLE  (CHECKPOINT_ENABLE),
        .CKPT_K             (CKPT_K),
        .POLICY_H_FUTURE    (POLICY_H_FUTURE),
        .POLICY_EXACT_PRUNE (POLICY_EXACT_PRUNE),
        .CKPT_MANUAL_ENABLE (CKPT_MANUAL_ENABLE),
        .AUTO_SPEC_ENABLE   (AUTO_SPEC_ENABLE),
        .INTRA_ENGINES      (INTRA_ENGINES),
        .MEAS_M1_ENABLE     (MEAS_M1_ENABLE),
        .MEAS_M2_ENABLE     (MEAS_M2_ENABLE),
        .MEAS_M3_ENABLE     (MEAS_M3_ENABLE),
        .MEAS_BUILD_ROWS    (MEAS_BUILD_ROWS)
    ) u_main_ip (
        .clk                        (clk),
        .rstn                       (rstnn),

        .start                      (start),
        .auto_shot                  (auto_shot),
        .j_target                   (j_target),
        .burst_enable               (burst_enable),
        .enum_enable                (enum_enable),
        .fail_repeat_limit          (fail_repeat_limit),

        .checkpoint_manual_enable   (checkpoint_manual_enable),
        .policy_valid               (policy_valid),
        .policy_source_j            (policy_source_j),
        .policy_next_count          (policy_next_count),
        .policy_next_j_flat         (policy_next_j_flat),

        .checkpoint_auto_enable     (checkpoint_auto_enable),

        .predicate_mode             (predicate_mode),
        .threshold_a                (threshold_a),
        .threshold_b                (threshold_b),
        .data_count                 (data_count),

        .shot_cap                   (shot_cap),
        .seed_j                     (seed_j),
        .seed_meas                  (seed_meas),

        .load_start                 (load_start),
        .data_wr_en                 (data_wr_en),
        .data_wr_addr               (data_wr_addr),
        .data_wr_data               (data_wr_data),
        .load_done                  (load_done),
        .load_busy                  (load_busy),

        .res_pop                    (res_pop),
        .res_dout                   (res_dout),
        .res_empty                  (res_empty),
        .res_count                  (res_count),

        .busy                       (busy),
        .done                       (done),
        .result_valid               (result_valid),
        .result_index               (result_index),

        .enum_done                  (enum_done),
        .found_count                (found_count),
        .consecutive_fail_count     (consecutive_fail_count),
        .max_fifo_occupancy         (max_fifo_occupancy),
        .fifo_stall_cycles          (fifo_stall_cycles),

        .config_error               (config_error),
        .shot_limit                 (shot_limit),
        .budget_limit               (budget_limit),
        .amp_overflow               (amp_overflow),
        .zero_weight_error          (zero_weight_error),
        .load_error                 (load_error),

        .trial_count                (trial_count),
        .L_BBHT                     (L_BBHT),
        .actual_grover_iterations   (actual_grover_iterations),
        .cycle_count                (cycle_count),

        .policy_cycles_total        (policy_cycles_total),
        .policy_stall_cycles        (policy_stall_cycles),
        .policy_actions_eval        (policy_actions_eval),
        .policy_memo_hit            (policy_memo_hit),
        .policy_memo_miss           (policy_memo_miss),
        .policy_max_latency         (policy_max_latency),

        .plan_fifo_level            (plan_fifo_level),
        .plan_fifo_highwater        (plan_fifo_highwater),
        .plan_fifo_empty_demand     (plan_fifo_empty_demand),
        .plan_fifo_hit_count        (plan_fifo_hit_count),
        .plan_fifo_mismatch_count   (plan_fifo_mismatch_count),
        .policy_cold_solve_count    (policy_cold_solve_count),
        .policy_spec_solve_count    (policy_spec_solve_count)
    );

endmodule
