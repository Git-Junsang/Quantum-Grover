//=====================================================================
// bbht_grover_core_adapter.v -- 체크포인트 없는 판 (no_checkpoint_baseline)
//
// hardware_bram/configurations/final/src/bbht_grover_core_adapter.v 와 포트·결선이 한
// 글자도 다르지 않고, 다른 것은 둘뿐입니다.
//
//   1. 파라미터 기본값 -- 연산기 네 벌(E4)만 켜고 나머지 최적화는 전부 끕니다.
//        CHECKPOINT_ENABLE=0  체크포인트 저장 · Planner · Executor · 정책 엔진이
//                             generate 로 통째로 빠집니다
//        NUMBER_OF_PES=4      반복 한 번에 P=32 연산기 4벌이 협력 (E4)
//        BUILD_ROWS_PER_CYCLE=1     Single-Row Build
//        USE_TWO_LEVEL_SELECT=0     계층 행 선택 끔 (M2 끔)
//      CHECKPOINT_CAPACITY · LOOKAHEAD_SHOTS 는 CHECKPOINT_ENABLE=0 이면 쓰이지 않습니다.
//      값은 체크포인트 판과 같게 두었습니다.
//
//   2. burst_enable 을 Main IP 에 0 으로 넘깁니다.
//      CHECKPOINT_ENABLE=0 인 Main IP 에 burst_enable=1 을 주면 grover_bbht 의
//      옛 "한 벌 캐시 이어 돌리기"(v0.8 burst) 가 살아납니다. 그것도 진폭을
//      재활용하는 최적화라 이 판의 취지(최적화 없는 비교 기준)와 맞지 않고,
//      E4 위에서는 검증한 적도 없습니다. 그래서 호스트가 SET BURST=1
//      (CHECKPOINT_SINGLE) 을 보내도 NORMAL 로 돕니다. DRAM 갈래가 BURST 를 무시하는
//      것과 같은 약속이고, 호스트 자동 테스트는 ID 의 platform= 을 보고 이
//      판에서는 NORMAL 만 돌립니다. mmio 의 CTRL 레지스터 값은 그대로 읽힙니다.
//
// 이 판의 NORMAL 은 체크포인트 판(K3/H3-E4)을 M1=M2=0 으로 빌드해 NORMAL 로
// 돌린 것과 사이클까지 같아야 합니다. NORMAL 은 체크포인트 판에서도 E4 진폭
// 메모리의 슬롯 0 만 쓰기 때문입니다 (bbht_grover_main_ip.v 의 E4 generate
// 설명). hardware_bram/configurations/no_checkpoint_baseline/sim 의 predicate500-ref 가 그것을 대조합니다.
//
// Main IP 와 통신 계층 소스는 hardware_bram/src/ 의 것을 그대로
// 씁니다. 두 판이 같은 RTL 을 파라미터만 달리 컴파일하므로 이 파일 하나만
// 따로 둡니다. 합성 경로에 들어가는 파일 목록은 체크포인트 판 어댑터 머리말과
// 같고, 그중 이 판에서 실제로 인스턴스되지 않는 것은 grover_policy.v 와
// grover_checkpoint.v 의 Planner/Executor 입니다 (E4 진폭 메모리
// grover_ckpt_mem_interleaved_e4 는 grover_checkpoint.v 에 있어 파일은 필요).
//=====================================================================
`timescale 1ns/1ps

module bbht_grover_core #(
    parameter integer CHECKPOINT_ENABLE  = 0,
    parameter integer CHECKPOINT_CAPACITY             = 3,
    parameter integer LOOKAHEAD_SHOTS    = 3,
    parameter integer CHECKPOINT_MANUAL_ENABLE = 0,
    parameter integer SPECULATIVE_PLANNING_ENABLE   = 1,
    parameter integer NUMBER_OF_PES      = 4,
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

    // burst_enable 은 머리말 2번 이유로 Main IP 에 넘기지 않습니다.
    wire _unused_burst_enable = burst_enable;

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
        .burst_enable               (1'b0),          // 머리말 2번
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
