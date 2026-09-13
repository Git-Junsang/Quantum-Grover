//=====================================================================
// bbht_grover_core_adapter.v -- hardware_dram 갈래, 통신 계층 <-> Main IP
// 어댑터.
//
// hardware_bram/src/bbht_grover_core_adapter.v 와 목적이 같습니다: 통신
// 계층(bbht_rvx_wrapper.v)은 인수인계 §3.4 계약 이름 그대로인
// bbht_grover_core 를 인스턴스하는데, 실제 Main IP 모듈 이름과 리셋
// 이름이 다르므로 그 차이만 흡수합니다. 신호는 61개 전부 1:1 이고
// 폭 변환도 논리도 없습니다.
//
// hardware_bram 판과의 차이는 실체뿐입니다: 이쪽은
// 같은 폴더의 lpsoc_bbht_grover_main_ip.v (DRAM 전량저장 초안, 단일탐색
// 범위)를 감쌉니다. CHECKPOINT_ENABLE/CKPT_K/CKPT_MANUAL_ENABLE/
// AUTO_SPEC_ENABLE 파라미터는 이 갈래에 없는 개념이라 아예 선언하지
// 않습니다 -- checkpoint_manual_enable/policy_*/checkpoint_auto_enable
// 입력은 계약 호환을 위해 그대로 받아 Main IP 쪽에서 미사용으로 둡니다.
//
// 이 초안이 실제로 인스턴스하는 파일은 다음과 같습니다 (전부 같은 폴더.
// 2026-09-11 에 src_v2 를 src 로 합쳤습니다).
//   lpsoc_bbht_grover_main_ip.v   최상위 (신규)
//   grover_dram_shot_fsm.v        외곽 BBHT 라운드 제어 (신규)
//   grover_dram_prep_seq.v        버퍼-A 준비 시퀀서 -- 체크포인트 대체 (신규)
//   grover_dram_amp_store.v       DRAM store/restore 엔진 (신규)
//   grover_dram_queue.v           버퍼 A/B 포트 뮤x ("BRAM 큐") (신규)
//   grover_dram_random.v          LFSR·m ROM (hardware_bram 재사용, 무변경)
//   grover_iteration.v            데이터패스 · 제어 FSM (hardware_bram 재사용, 무변경)
//   grover_arithmetic.v           술어 · 가산트리 · 평균 · 확산 (재사용, 무변경)
//   grover_memories.v             data / amp / found_mask / result FIFO (재사용, 무변경)
//   grover_measurement.v          Born 측정 · verify (재사용, 무변경)
//   grover_loader.v               Main IP 내부 적재 제어 (재사용, 무변경)
//   grover_status.v               카운터 (재사용, 무변경)
//   grover_param.vh / grover_dram_param.vh  헤더
//=====================================================================
`timescale 1ns/1ps

module bbht_grover_core (
    input  wire        clk,
    input  wire        rstnn,

    // Search / Mode
    input  wire        start,
    input  wire        auto_shot,
    input  wire [6:0]  j_target,
    input  wire        burst_enable,
    input  wire        enum_enable,
    input  wire [3:0]  fail_repeat_limit,

    // Checkpoint (manual) -- 계약 호환용, 이 갈래에서는 미사용.
    input  wire        checkpoint_manual_enable,
    input  wire        policy_valid,
    input  wire [6:0]  policy_source_j,
    input  wire [2:0]  policy_next_count,
    input  wire [27:0] policy_next_j_flat,

    // Checkpoint (auto) -- 계약 호환용, 이 갈래에서는 미사용.
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

    // Enumeration -- v1 에서는 항상 미구현 상태 값(0)만 나갑니다.
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

    // Policy telemetry -- 이 갈래에는 정책 엔진이 없어 항상 0.
    output wire [31:0] policy_cycles_total,
    output wire [31:0] policy_stall_cycles,
    output wire [31:0] policy_actions_eval,
    output wire [31:0] policy_memo_hit,
    output wire [31:0] policy_memo_miss,
    output wire [31:0] policy_max_latency,

    // Plan telemetry -- 이 갈래에는 speculative plan FIFO 가 없어 항상 0.
    output wire [2:0]  plan_fifo_level,
    output wire [2:0]  plan_fifo_highwater,
    output wire [31:0] plan_fifo_empty_demand,
    output wire [31:0] plan_fifo_hit_count,
    output wire [31:0] plan_fifo_mismatch_count,
    output wire [31:0] policy_cold_solve_count,
    output wire [31:0] policy_spec_solve_count
);

    // 이 어댑터 경계 밖(RVX 통합 전)까지는 아직 안 나갑니다: 물리 DRAM
    // 바인딩이 미정이라 grover_dram_param.vh 의 GD_ADDR_W/GD_BURST_LEN_W
    // 폭으로 로컬에 열어 두고 항상-준비(always-ready) 로 묶습니다.
    // MIG/AXI 브리지가 정해지면 이 자리에서 실제 포트로 뚫으면 됩니다.
    wire                         dram_wr_req_u;
    wire [31:0]                  dram_wr_addr_u;
    wire [9:0]                   dram_wr_len_u;
    wire                         dram_wr_valid_u;
    wire [32*23-1:0]             dram_wr_data_u;
    wire                         dram_wr_last_u;
    wire                         dram_rd_req_u;
    wire [31:0]                  dram_rd_addr_u;
    wire [9:0]                   dram_rd_len_u;
    // 이 어댑터는 bram 갈래와 마찬가지로 grover_param.vh 를 include 하지
    // 않습니다. 포트 폭을 전부 리터럴로 적어 두어야 include 순서와 무관하게
    // 컴파일되기 때문입니다. GP_J_W = 7 (j = 0..127) 에 해당합니다.
    wire [6:0]                   dram_frontier_j_u;

    lpsoc_bbht_grover_main_ip u_main_ip (
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
        .policy_spec_solve_count    (policy_spec_solve_count),

        .dram_wr_req                (dram_wr_req_u),
        .dram_wr_addr               (dram_wr_addr_u),
        .dram_wr_len                (dram_wr_len_u),
        .dram_wr_valid              (dram_wr_valid_u),
        .dram_wr_data               (dram_wr_data_u),
        .dram_wr_last               (dram_wr_last_u),
        .dram_wr_ready              (1'b1),

        .dram_rd_req                (dram_rd_req_u),
        .dram_rd_addr               (dram_rd_addr_u),
        .dram_rd_len                (dram_rd_len_u),
        .dram_rd_valid              (1'b0),
        .dram_rd_data               ({(32*23){1'b0}}),
        .dram_rd_ready              (),
        .dram_rd_last               (1'b0),

        .dram_frontier_j            (dram_frontier_j_u)
    );

endmodule
