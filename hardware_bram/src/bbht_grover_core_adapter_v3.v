//=====================================================================
// bbht_grover_core_adapter_v3.v -- PASS2 융합판 Main IP 를 끼우는 어댑터
//
// src/bbht_grover_core_adapter.v 와 몸통이 같습니다. 다른 것은 어느
// 소스 트리를 합성 경로에 넣느냐 하나뿐이라, 모듈 이름과 61신호 배선은
// 그대로 두고 이 파일을 따로 둡니다. 빌드 스크립트가 CORE=v3 일 때
// src_v3/ 을 쓰면서 이 어댑터를 고릅니다.
//
// src_v3 은 src_v2 의 포크입니다. 바뀐 것은 측정 경로 하나입니다.
//
//   grover_iteration.v      row_out_is_pass2 출력 추가
//   lpsoc_bbht_grover_main_ip.v
//                           grover_born_square32 를 한 벌 더 두고, PASS2
//                           쓰기와 같이 row_weight 를 만듭니다
//   grover_measurement.v    fuse_* 입력과 S_FUSE_WAIT 추가. 융합이
//                           유효하면 S_BUILD 512행 스캔을 건너뜁니다
//
// 나머지 일곱 파일은 src_v2 와 바이트 동일합니다.
//
// 융합이 유효한 조건은 셋입니다. 하나라도 어긋나면 기존 S_BUILD 로
// 폴백하므로 결과는 언제나 정본과 같습니다.
//   1. PASS2 가 행 0부터 512행을 빠짐없이 채웠을 것
//   2. 그 누산이 지금 측정하는 checkpoint 슬롯의 것일 것
//      (checkpoint 복원은 amp_mem 에 쓰지 않고 읽는 슬롯만 바꿉니다)
//   3. 그 사이 S_BUILD 폴백이 row_weight 메모리를 덮어쓰지 않았을 것
//
// 2·3 을 빠뜨리면 250쌍 중 59쌍에서 탐색 궤적이 어긋납니다. TB 27
// 트라이얼로는 안 드러나고, result_index 로도 안 드러납니다 -- BBHT 가
// 후보를 술어로 자가 검증하기 때문입니다. 검증은 trial_count 와 L_BBHT
// 를 Normal 과 대조해야 합니다 (sim/bench250_report.py).
//
// 파라미터는 아래 몸통에 있는 production 구성 그대로입니다.
//=====================================================================
`timescale 1ns/1ps

module bbht_grover_core #(
    parameter integer CHECKPOINT_ENABLE  = 1,
    parameter integer CKPT_K             = 4,
    parameter integer CKPT_MANUAL_ENABLE = 0,
    parameter integer AUTO_SPEC_ENABLE   = 1
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

    lpsoc_bbht_grover_main_ip #(
        .CHECKPOINT_ENABLE  (CHECKPOINT_ENABLE),
        .CKPT_K             (CKPT_K),
        .CKPT_MANUAL_ENABLE (CKPT_MANUAL_ENABLE),
        .AUTO_SPEC_ENABLE   (AUTO_SPEC_ENABLE)
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
