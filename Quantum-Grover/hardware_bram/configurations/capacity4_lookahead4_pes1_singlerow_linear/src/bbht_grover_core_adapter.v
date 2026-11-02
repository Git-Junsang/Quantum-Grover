//=====================================================================
// bbht_grover_core_adapter.v -- K4/H4-E1 모델 (hardware_bram/configurations/capacity4_lookahead4_pes1_singlerow_linear)
//
// final/src/bbht_grover_core_adapter.v 와 포트 · 결선이
// 같고, 다른 것은 파라미터 기본값뿐입니다. 이름 · 리셋을 맞춰 주는 이 어댑터의
// 역할과 합성 경로에 들어가는 파일 목록은 그 파일 머리말에 있습니다.
// Main IP 와 통신 계층은 hardware_bram/src/ 의 공용 소스를 그대로 씁니다.
// 모든 모델이 같은 RTL 을 파라미터만 달리 컴파일해야 모델 사이 비교가
// 공정하므로, 모델 폴더에는 이 어댑터 하나만 둡니다.
//
// 이 모델의 구성
//   CHECKPOINT_ENABLE=1  체크포인트 저장 · Planner · Executor · 정책 엔진을 합성에 넣음
//   CHECKPOINT_CAPACITY=4             체크포인트 4벌
//   LOOKAHEAD_SHOTS=4    정책 지평 4
//   NUMBER_OF_PES=1      연산기 한 벌 (E1)
//   BUILD_ROWS_PER_CYCLE=1     Single-Row Build
//   USE_TWO_LEVEL_SELECT=0     계층 행 선택 끔 (M2 끔)
//   CHECKPOINT_MANUAL_ENABLE=0 · SPECULATIVE_PLANNING_ENABLE=1 은 모든 모델이 같습니다.
//
// 어디서 나온 조합인가
//   6단계 ablation 의 둘째 단계(K4/H4-E1)이고, K/H 단독 실험
//   (hardware_bram/results/2026-09-09_kh_isolated_e1/)의 대조군입니다. 태그
//   board-k3h3-e4-m2 의 src_ablation/k4h4_e1_top.v 가 넘기던 값과 같습니다.
//   2026-09-04 보드 실측(K4/H4 single operator)도 이 구성인데, 그 비트스트림은
//   옛 RTL 로 만든 것입니다. 실측 묶음은 이 모델의 vivado/ 에 있습니다.
//=====================================================================
`timescale 1ns/1ps

module bbht_grover_core #(
    parameter integer CHECKPOINT_ENABLE  = 1,
    parameter integer CHECKPOINT_CAPACITY             = 4,
    parameter integer LOOKAHEAD_SHOTS    = 4,
    parameter integer CHECKPOINT_MANUAL_ENABLE = 0,
    parameter integer SPECULATIVE_PLANNING_ENABLE   = 1,
    parameter integer NUMBER_OF_PES      = 1,
    parameter integer BUILD_ROWS_PER_CYCLE = 1,
    parameter integer USE_TWO_LEVEL_SELECT     = 0
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
    output wire [31:0] shot_count,
    output wire [31:0] requested_iterations,
    output wire [31:0] executed_iterations,
    output wire [31:0] cycle_count,

    // Policy telemetry
    output wire [31:0] policy_cycles_total,
    output wire [31:0] policy_stall_cycles,
    output wire [31:0] policy_actions_eval,
    output wire [31:0] policy_memo_hit,
    output wire [31:0] policy_memo_miss,
    output wire [31:0] policy_max_latency,

    // Plan telemetry
    output wire [2:0]  plan_queue_level,
    output wire [2:0]  plan_queue_highwater,
    output wire [31:0] plan_queue_empty_demand,
    output wire [31:0] plan_queue_hit_count,
    output wire [31:0] plan_queue_miss_count,
    output wire [31:0] policy_cold_solve_count,
    output wire [31:0] policy_spec_solve_count
);

    bbht_grover_main_ip #(
        .CHECKPOINT_ENABLE  (CHECKPOINT_ENABLE),
        .CHECKPOINT_CAPACITY             (CHECKPOINT_CAPACITY),
        .LOOKAHEAD_SHOTS    (LOOKAHEAD_SHOTS),
        .CHECKPOINT_MANUAL_ENABLE (CHECKPOINT_MANUAL_ENABLE),
        .SPECULATIVE_PLANNING_ENABLE   (SPECULATIVE_PLANNING_ENABLE),
        .NUMBER_OF_PES      (NUMBER_OF_PES),
        .BUILD_ROWS_PER_CYCLE (BUILD_ROWS_PER_CYCLE),
        .USE_TWO_LEVEL_SELECT     (USE_TWO_LEVEL_SELECT)
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

        .shot_count                (shot_count),
        .requested_iterations                     (requested_iterations),
        .executed_iterations   (executed_iterations),
        .cycle_count                (cycle_count),

        .policy_cycles_total        (policy_cycles_total),
        .policy_stall_cycles        (policy_stall_cycles),
        .policy_actions_eval        (policy_actions_eval),
        .policy_memo_hit            (policy_memo_hit),
        .policy_memo_miss           (policy_memo_miss),
        .policy_max_latency         (policy_max_latency),

        .plan_queue_level            (plan_queue_level),
        .plan_queue_highwater        (plan_queue_highwater),
        .plan_queue_empty_demand     (plan_queue_empty_demand),
        .plan_queue_hit_count        (plan_queue_hit_count),
        .plan_queue_miss_count   (plan_queue_miss_count),
        .policy_cold_solve_count    (policy_cold_solve_count),
        .policy_spec_solve_count    (policy_spec_solve_count)
    );

endmodule
