//=====================================================================
// bbht_grover_core_adapter.v -- K3/H3-E4-M3-S6 Main IP 통신 어댑터
//
// 통신 계층(같은 폴더의 bbht_rvx_wrapper.v)은 인수인계 §3.4 계약 이름 그대로인
// bbht_grover_core 를 인스턴스합니다. 정본 Main IP 의 모듈 이름은
// bbht_grover_main_ip 이고 리셋 이름이 rstn 이라, 그 둘만 맞춰 주는 얇은
// 껍데기를 둡니다. 신호는 61개 전부 1:1 이고 폭 변환도 논리도 없습니다.
//
// 이 파일이 있는 이유:
//   - Main IP 는 보드 정본과 같은 모듈 이름을 그대로 둡니다
//   - 우리 wrapper 도 계약 이름을 유지해야 check_ports 가 그대로 돕니다
//   - 그래서 이름·리셋 차이만 여기서 흡수합니다
//
// 보드에 구운 정본 wrapper(태그 board-k3h3-e4-m2 의 src/bbht_rvx_wrapper.v)는
// 어댑터 없이 bbht_grover_main_ip 를 직접 물었습니다. 2026-09-13 에 통신
// 계층을 우리 판 하나로 합치면서 이 어댑터가 합성 경로에 들어갑니다.
//
// capacity3_lookahead3_pes4_triplerow_twolevel 모델과 같은 Main IP 구성(M2 + 세 번째 Born square32)에
// 정책 탐색만 seed-first 로 바꾼 모델입니다. 다른 파라미터는 M3 와 같습니다.
//   CHECKPOINT_CAPACITY=3           체크포인트 3벌
//   LOOKAHEAD_SHOTS=3  정책 지평 3
//   POLICY_SEARCH_MODE=6
//                       full-horizon admissible lower bound + seed-first
//                       exact DFS (grover_policy.v 의 EXACT_PRUNE=5) 에,
//                       현재 요청의 legal action 이 하나뿐이면 그 아래를
//                       탐색하지 않고 바로 결정하는 단축을 더한 모드입니다.
//                       고르는 source / 체크포인트 tuple 은 exhaustive 정책과
//                       같습니다. 그 단축 결정에서만 root_cost 가 정확한 DP
//                       비용 대신 하한(즉시 비용 + bound)으로 나오며, Main IP
//                       는 root_cost 를 래치만 하고 읽지 않습니다.
//   NUMBER_OF_PES=4    반복 한 번에 P=32 연산기 4벌이 협력 (E4)
//   BUILD_ROWS_PER_CYCLE=2   Dual-Row Build
//   USE_TWO_LEVEL_SELECT=1   M1 + 16x32 계층 행 선택 (M2)
//   BUILD_ROWS_PER_CYCLE=3   Triple-Row Build (Two-Level Select 유지)
//   M1·M2 스위치는 2026-09-13 에 Main IP 를 6단계 ablation 공통소스 판으로
//   올리면서 생긴 파라미터입니다. 둘 다 1 이면 보드에 구운 Main IP 와 동작이
//   같고, 하나라도 0 이면 ablation 의 앞 단계 구성이 됩니다.
//
// src/ 에서 Main IP 로 합성 경로에 들어가는 파일은 아래 열하나입니다
// (통신 계층 셋과 이 어댑터는 따로 들어갑니다).
//   bbht_grover_main_ip.v         최상위
//   grover_iteration.v            데이터패스 · 제어 FSM
//   grover_arithmetic.v           술어 · 가산트리 · 평균 · 확산
//   grover_memories.v             data / amp / found_mask / result FIFO
//   grover_measurement.v          Born 측정 · verify (M1·M2 포함)
//   grover_bbht.v                 LFSR · m ROM · shot FSM
//   grover_checkpoint.v           K3 저장 · Planner · Executor
//   grover_policy.v               memo · Shadow-J · plan FIFO
//   grover_status.v               카운터
//   grover_loader.v               Main IP 내부 적재 제어
//   grover_param.vh               헤더
//
// 같은 폴더에 있어도 합성 경로에 넣지 않는 것
//   bbht_bram_top.v
//       어댑터 없이 Main IP 를 직접 무는 다른 최상단입니다. wrapper 와 둘 중
//       하나만 넣어야 최상위가 하나로 남습니다.
//   grover_policy_ooc_top.v / grover_policy_impl_wrapper.v
//       policy OOC 합성 전용입니다. 최상위가 둘이 됩니다.
//=====================================================================
`timescale 1ns/1ps

`ifndef GP_BUILD_ROWS_PER_CYCLE_DEFAULT
`define GP_BUILD_ROWS_PER_CYCLE_DEFAULT 3
`endif

module bbht_grover_core #(
    parameter integer CHECKPOINT_ENABLE  = 1,
    parameter integer CHECKPOINT_CAPACITY             = 3,
    parameter integer LOOKAHEAD_SHOTS    = 3,
    parameter integer POLICY_SEARCH_MODE = 6,
    parameter integer CHECKPOINT_MANUAL_ENABLE = 0,
    parameter integer SPECULATIVE_PLANNING_ENABLE   = 1,
    parameter integer NUMBER_OF_PES      = 4,
    parameter integer BUILD_ROWS_PER_CYCLE = `GP_BUILD_ROWS_PER_CYCLE_DEFAULT,
    parameter integer USE_TWO_LEVEL_SELECT     = 1
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
        .POLICY_SEARCH_MODE (POLICY_SEARCH_MODE),
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
