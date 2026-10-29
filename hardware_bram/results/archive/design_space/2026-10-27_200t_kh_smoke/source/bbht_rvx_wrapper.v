//=====================================================================
// bbht_rvx_wrapper.v -- RVX 와 Main IP 사이의 결선판 (통신 담당 소유)
//
// RVX 가 뽑아 주는 두 포트와 PJK 의 Main IP 를 이어 붙입니다.
//
//   i_grover_csr (APB slave, rp*) --> bbht_grover_mmio  --> Main IP 설정/상태
//   i_grover_dma (AHB master, sh*) <-- bbht_ahb_loader  --> Main IP loader
//
// 클럭 하나(clk_accel = 100 MHz)만 씁니다. network 쪽(gclk_noc)과의 CDC 는
// RVX 가 sni_apb_asynch / mni_ahbm_asynch 로 이미 넣어 준 것이고, 실보드에서
// 검증된 구조입니다. 여기에 CDC 를 또 넣으면 안 됩니다 (인수인계 §3.2).
//
// 이 파일이 실제로 "판단" 하는 것은 셋뿐이고, 나머지는 배선입니다.
//   1. start 수락 조건 -- 아래 §start
//   2. checkpoint_auto_enable = burst_enable && auto_shot
//   3. manual checkpoint 입력 전부 0 tie-off (production 설정)
//=====================================================================
`timescale 1ns/1ps
`include "bbht_grover_csr.vh"

module bbht_rvx_wrapper #(
    parameter [31:0] SRAM_BASE = 32'hE000_0000,
    parameter [31:0] SRAM_LAST = 32'hE001_FFFF
) (
    input  wire        clk,        // clk_accel
    input  wire        rstnn,

    //-----------------------------------------------------------------
    // APB 슬레이브 (i_grover_csr) -- 인수인계 §3.3 계약 이름
    //-----------------------------------------------------------------
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] paddr,
    input  wire [31:0] pwdata,
    output wire        pready,
    output wire [31:0] prdata,
    output wire        pslverr,

    //-----------------------------------------------------------------
    // AHB 마스터 (i_grover_dma) -- 인수인계 §3.3 계약 이름
    //-----------------------------------------------------------------
    input  wire        shready,
    input  wire [31:0] shrdata,
    input  wire        shresp,
    output wire [31:0] shaddr,
    output wire [2:0]  shburst,
    output wire        shmasterlock,
    output wire [3:0]  shprot,
    output wire [2:0]  shsize,
    output wire [1:0]  shtrans,
    output wire        shwrite,
    output wire [31:0] shwdata
);

    //=================================================================
    // CSR
    //=================================================================
    wire        cmd_search_start;
    wire        cmd_dma_start;
    wire        done_pending;

    wire        cfg_auto_shot;
    wire        cfg_burst_enable;
    wire [1:0]  cfg_predicate_mode;
    wire [6:0]  cfg_j_target;
    wire signed [15:0] cfg_threshold_a;
    wire signed [15:0] cfg_threshold_b;
    wire [14:0] cfg_data_count;
    wire [15:0] cfg_shot_cap;
    wire [31:0] cfg_seed_j;
    wire [31:0] cfg_seed_meas;
    wire        cfg_enum_enable;
    wire [3:0]  cfg_fail_repeat_limit;
    wire [31:0] cfg_data_addr;

    //=================================================================
    // Main IP 접점
    //=================================================================
    wire        core_busy;
    wire        core_load_busy;
    wire        core_done;
    wire        core_result_valid;
    wire [13:0] core_result_index;
    wire        core_enum_done;
    wire [14:0] core_found_count;
    wire [3:0]  core_consecutive_fail_count;
    wire [8:0]  core_max_fifo_occupancy;
    wire [31:0] core_fifo_stall_cycles;

    wire        core_config_error;
    wire        core_shot_limit;
    wire        core_budget_limit;
    wire        core_amp_overflow;
    wire        core_zero_weight_error;
    wire        core_load_error;

    wire [31:0] core_trial_count;
    wire [31:0] core_l_bbht;
    wire [31:0] core_actual_grover_iterations;
    wire [31:0] core_cycle_count;

    wire [13:0] res_dout;
    wire        res_empty;
    wire [8:0]  res_count;
    wire        res_pop;

    wire [31:0] tm_policy_cycles_total;
    wire [31:0] tm_policy_stall_cycles;
    wire [31:0] tm_policy_actions_eval;
    wire [31:0] tm_policy_memo_hit;
    wire [31:0] tm_policy_memo_miss;
    wire [31:0] tm_policy_max_latency;
    wire [2:0]  tm_plan_fifo_level;
    wire [2:0]  tm_plan_fifo_highwater;
    wire [31:0] tm_plan_fifo_empty_demand;
    wire [31:0] tm_plan_fifo_hit_count;
    wire [31:0] tm_plan_fifo_mismatch_count;
    wire [31:0] tm_policy_cold_solve_count;
    wire [31:0] tm_policy_spec_solve_count;

    // loader -> Main IP
    wire        load_start;
    wire        data_wr_en;
    wire [13:0] data_wr_addr;
    wire signed [15:0] data_wr_data;
    wire        load_done;
    wire [7:0]  dma_status;

    // 인수인계 §3.4 는 busy = search_busy | load_busy 로 정의하고 load_busy 를
    // 따로 내보냅니다. search_busy 라는 포트는 계약에 없으므로 여기서 뺍니다.
    wire core_search_busy = core_busy & ~core_load_busy;

    //=================================================================
    // §start -- 외부 start 수락 조건
    //
    // start queue 를 두지 않습니다. 조건이 안 맞으면 그 펄스는 조용히
    // 버려지고, 펌웨어가 COMMAND 를 쓰기 전에 STATUS 를 먼저 확인하는 것이
    // 규약입니다. 큐를 두면 "언제 시작했는지" 가 소프트웨어에서 안 보이고,
    // 그 상태에서 카운터를 읽으면 서로 다른 시점의 값이 섞입니다.
    //
    //   !search_busy   실행 중이 아닐 것
    //   !load_busy     적재 중이 아닐 것 -- 절반만 채워진 배열 위에서
    //                  오라클을 돌리면 경고 없이 틀린 답이 나옵니다
    //   res_empty      직전 열거 결과가 FIFO 에 남아 있지 않을 것
    //   !done_pending  직전 실행의 완료가 아직 안 읽힌 상태가 아닐 것
    //
    // done_pending 은 mmio 의 done_sticky 입니다. COMMAND 쓰기가 그것을
    // 클리어하고 한 사이클 뒤에 cmd_search_start 가 나오므로, 정상 순서
    // (설정 -> COMMAND -> 폴링)는 항상 통과합니다. 걸리는 것은 앞 실행을
    // 읽지 않고 곧바로 다음 start 를 밀어 넣는 경우뿐입니다.
    //=================================================================
    wire start_accept = cmd_search_start
                     && !core_search_busy
                     && !core_load_busy
                     && res_empty
                     && !done_pending;

    //=================================================================
    // checkpoint 게이트
    //
    // production 파라미터는 CHECKPOINT_ENABLE=1, CKPT_K=4,
    // CKPT_MANUAL_ENABLE=0, AUTO_SPEC_ENABLE=1 로 고정입니다. 통신 계층은
    // autonomous 게이트만 만들고 manual 경로는 전부 0 으로 묶습니다.
    //=================================================================
    wire checkpoint_auto_enable = cfg_burst_enable & cfg_auto_shot;

    //=================================================================
    bbht_grover_mmio u_mmio (
        .clk                (clk),
        .rstnn              (rstnn),

        .psel              (psel),
        .penable           (penable),
        .pwrite            (pwrite),
        .paddr             (paddr),
        .pwdata            (pwdata),
        .pready            (pready),
        .prdata            (prdata),
        .pslverr           (pslverr),

        .cmd_search_start   (cmd_search_start),
        .cmd_dma_start      (cmd_dma_start),
        .done_pending       (done_pending),

        .cfg_auto_shot          (cfg_auto_shot),
        .cfg_burst_enable       (cfg_burst_enable),
        .cfg_predicate_mode     (cfg_predicate_mode),
        .cfg_j_target           (cfg_j_target),
        .cfg_threshold_a        (cfg_threshold_a),
        .cfg_threshold_b        (cfg_threshold_b),
        .cfg_data_count         (cfg_data_count),
        .cfg_shot_cap           (cfg_shot_cap),
        .cfg_seed_j             (cfg_seed_j),
        .cfg_seed_meas          (cfg_seed_meas),
        .cfg_enum_enable        (cfg_enum_enable),
        .cfg_fail_repeat_limit  (cfg_fail_repeat_limit),
        .cfg_data_addr          (cfg_data_addr),

        .st_busy                (core_busy),
        .st_load_busy           (core_load_busy),
        .st_done                (core_done),
        .st_result_valid        (core_result_valid),
        .st_config_error        (core_config_error),
        .st_shot_limit          (core_shot_limit),
        .st_budget_limit        (core_budget_limit),
        .st_amp_overflow        (core_amp_overflow),
        .st_zero_weight_error   (core_zero_weight_error),
        .st_load_error          (core_load_error),
        .st_enum_done           (core_enum_done),
        .st_result_index        (core_result_index),
        .st_trial_count         (core_trial_count),
        .st_l_bbht              (core_l_bbht),
        .st_actual_iter         (core_actual_grover_iterations),
        .st_cycle_count         (core_cycle_count),
        .st_found_count         (core_found_count),
        .st_consecutive_fail    (core_consecutive_fail_count),
        .st_max_fifo_occupancy  (core_max_fifo_occupancy),
        .st_fifo_stall_cycles   (core_fifo_stall_cycles),

        .res_dout               (res_dout),
        .res_empty              (res_empty),
        .res_count              (res_count),
        .res_pop                (res_pop),

        .dma_status             (dma_status),

        .tm_policy_cycles_total      (tm_policy_cycles_total),
        .tm_policy_stall_cycles      (tm_policy_stall_cycles),
        .tm_policy_actions_eval      (tm_policy_actions_eval),
        .tm_policy_memo_hit          (tm_policy_memo_hit),
        .tm_policy_memo_miss         (tm_policy_memo_miss),
        .tm_policy_max_latency       (tm_policy_max_latency),
        .tm_plan_fifo_level          (tm_plan_fifo_level),
        .tm_plan_fifo_highwater      (tm_plan_fifo_highwater),
        .tm_plan_fifo_empty_demand   (tm_plan_fifo_empty_demand),
        .tm_plan_fifo_hit_count      (tm_plan_fifo_hit_count),
        .tm_plan_fifo_mismatch_count (tm_plan_fifo_mismatch_count),
        .tm_policy_cold_solve_count  (tm_policy_cold_solve_count),
        .tm_policy_spec_solve_count  (tm_policy_spec_solve_count)
    );

    //=================================================================
    bbht_ahb_loader #(
        .SRAM_BASE (SRAM_BASE),
        .SRAM_LAST (SRAM_LAST)
    ) u_loader (
        .clk            (clk),
        .rstnn          (rstnn),

        .dma_start      (cmd_dma_start),
        .data_addr      (cfg_data_addr),
        .data_count     (cfg_data_count),
        .main_busy      (core_search_busy),
        .dma_status     (dma_status),

        .shready        (shready),
        .shrdata        (shrdata),
        .shresp         (shresp),
        .shaddr         (shaddr),
        .shburst        (shburst),
        .shmasterlock   (shmasterlock),
        .shprot         (shprot),
        .shsize         (shsize),
        .shtrans        (shtrans),
        .shwrite        (shwrite),
        .shwdata        (shwdata),

        .load_start     (load_start),
        .data_wr_en     (data_wr_en),
        .data_wr_addr   (data_wr_addr),
        .data_wr_data   (data_wr_data),
        .load_done      (load_done)
    );

    //=================================================================
    // Main IP (PJK 소유. 여기서는 인수인계 §3.4 의 포트 계약대로 인스턴스만
    // 합니다). 알고리즘/고정소수점/requested-j/RNG/checkpoint 의미는 freeze
    // 대상이므로 통신 계층에서 건드리지 않습니다.
    //=================================================================
    bbht_grover_core u_core (
        .clk                        (clk),
        .rstnn                      (rstnn),

        // Search / Mode
        .start                      (start_accept),
        .auto_shot                  (cfg_auto_shot),
        .j_target                   (cfg_j_target),
        .burst_enable               (cfg_burst_enable),
        .enum_enable                (cfg_enum_enable),
        .fail_repeat_limit          (cfg_fail_repeat_limit),

        // Checkpoint (manual) -- production 에서는 전부 0
        .checkpoint_manual_enable   (1'b0),
        .policy_valid               (1'b0),
        .policy_source_j            (7'd0),
        .policy_next_count          (3'd0),
        .policy_next_j_flat         (28'd0),

        // Checkpoint (auto)
        .checkpoint_auto_enable     (checkpoint_auto_enable),

        // Oracle
        .predicate_mode             (cfg_predicate_mode),
        .threshold_a                (cfg_threshold_a),
        .threshold_b                (cfg_threshold_b),
        .data_count                 (cfg_data_count),

        // BBHT / RNG
        .shot_cap                   (cfg_shot_cap),
        .seed_j                     (cfg_seed_j),
        .seed_meas                  (cfg_seed_meas),

        // Loader
        .load_start                 (load_start),
        .data_wr_en                 (data_wr_en),
        .data_wr_addr               (data_wr_addr),
        .data_wr_data               (data_wr_data),
        .load_done                  (load_done),
        .load_busy                  (core_load_busy),

        // Result FIFO
        .res_pop                    (res_pop),
        .res_dout                   (res_dout),
        .res_empty                  (res_empty),
        .res_count                  (res_count),

        // Execution
        .busy                       (core_busy),
        .done                       (core_done),
        .result_valid               (core_result_valid),
        .result_index               (core_result_index),

        // Enumeration
        .enum_done                  (core_enum_done),
        .found_count                (core_found_count),
        .consecutive_fail_count     (core_consecutive_fail_count),
        .max_fifo_occupancy         (core_max_fifo_occupancy),
        .fifo_stall_cycles          (core_fifo_stall_cycles),

        // Status (전부 코어에서 sticky)
        .config_error               (core_config_error),
        .shot_limit                 (core_shot_limit),
        .budget_limit               (core_budget_limit),
        .amp_overflow               (core_amp_overflow),
        .zero_weight_error          (core_zero_weight_error),
        .load_error                 (core_load_error),

        // Counters
        .trial_count                (core_trial_count),
        .L_BBHT                     (core_l_bbht),
        .actual_grover_iterations   (core_actual_grover_iterations),
        .cycle_count                (core_cycle_count),

        // Policy telemetry
        .policy_cycles_total        (tm_policy_cycles_total),
        .policy_stall_cycles        (tm_policy_stall_cycles),
        .policy_actions_eval        (tm_policy_actions_eval),
        .policy_memo_hit            (tm_policy_memo_hit),
        .policy_memo_miss           (tm_policy_memo_miss),
        .policy_max_latency         (tm_policy_max_latency),

        // Plan telemetry
        .plan_fifo_level            (tm_plan_fifo_level),
        .plan_fifo_highwater        (tm_plan_fifo_highwater),
        .plan_fifo_empty_demand     (tm_plan_fifo_empty_demand),
        .plan_fifo_hit_count        (tm_plan_fifo_hit_count),
        .plan_fifo_mismatch_count   (tm_plan_fifo_mismatch_count),
        .policy_cold_solve_count    (tm_policy_cold_solve_count),
        .policy_spec_solve_count    (tm_policy_spec_solve_count)
    );

endmodule
