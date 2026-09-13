//=====================================================================
// bbht_bram_top.v -- hardware_bram 갈래 최상단 (호스트 통신 + 정본 Main IP)
//
// hardware_dram/src/bbht_dram_top.v 와 짝입니다. 두 파일은 결선이 한
// 줄씩 같고 다른 것은 둘뿐입니다.
//
//   Main IP    이쪽은 src/bbht_grover_main_ip.v (보드 정본 K3/H3-E4-M2,
//              freeze), 저쪽은 hardware_dram/src 의 DRAM 전량저장 초안
//   DRAM 포트  이쪽은 없음 (BRAM 만 씀), 저쪽은 최상단 포트로 나감
//
// 호스트 PC 에서 가속기까지의 경로
//
//   호스트 PC --UART--> RVX RISC-V (bbht_console 펌웨어)
//             --APB--> bbht_grover_mmio  --> Main IP 설정/상태   (CSR 38개)
//             <-AHB--  bbht_ahb_loader   --> Main IP 데이터 적재 (System SRAM)
//
// 포트는 clk/rstnn + APB 8 + AHB 11 로 bbht_rvx_wrapper 와 이름·폭이 전부
// 같습니다. 그래서 RVX user region 에서 모듈 이름만 바꿔 끼울 수 있습니다
// (user_region.vh 는 아직 bbht_rvx_wrapper 를 뭅니다).
//
// 같은 폴더의 bbht_rvx_wrapper.v + bbht_grover_core_adapter.v 와의 관계
//   기능은 같습니다. 그쪽은 인수인계 계약 이름 bbht_grover_core 를 무는
//   판이라 check_ports.py real 이 포트 계약(wrapper 19 + core 61)을 대조할
//   때 쓰고, 이 파일은 어댑터를 거치지 않고 Main IP 를 바로 뭅니다.
//   dram 갈래는 계약판이 DRAM 을 안쪽에서 묶어 두어 따로 최상단이
//   필요했고, 두 갈래의 최상단 모양을 맞추려고 이쪽에도 같은 파일을 둡니다.
//
//   보드에 구운 src/bbht_rvx_wrapper.v 와는 mmio 가 다른 판입니다. 이쪽
//   mmio·loader 는 CSR 정본 JSON 에서 생성한 헤더를 쓰는 우리 것이고
//   hardware_dram/src 의 것과 바이트 동일합니다. CSR 주소와 비트는 두
//   판이 같다는 것을 make final / make real 이 같은 TB 로 확인합니다.
//
// 결선 판단
//   1. start 수락 조건        아래 §start
//   2. checkpoint_auto_enable = burst_enable && auto_shot   (§checkpoint)
//   3. 수동 체크포인트 입력   전부 0 (CKPT_MANUAL_ENABLE=0)
//
// 클럭
//   전부 clk 하나(clk_accel = 100 MHz)입니다. APB/AHB 쪽 CDC 는 RVX 가
//   sni_apb_asynch / mni_ahbm_asynch 로 이미 넣어 주므로 여기에 또 넣지
//   않습니다 (인수인계 §3.2).
//
// 호스트 규약 한 가지 (src/grover_loader.v 에서 오는 것)
//   적재가 끝난 뒤 DATA_COUNT 를 적재 때와 다른 값으로 한 번이라도 쓰면
//   배열이 무효가 됩니다(data_count_mismatch -> data_valid=0). 값을
//   되돌려도 다시 살아나지 않으므로 재적재 전까지 탐색은 config_error
//   입니다. DMA 개수 거절(0 이나 N 초과)도 DATA_COUNT 를 쓰는 순간 이
//   경우에 들어갑니다. 정렬·범위 거절은 개수를 안 바꾸면 무해합니다.
//
// 리셋
//   rstnn 하나를 세 블록이 나눠 씁니다. mmio 와 loader 는 비동기 리셋,
//   Main IP 는 동기 리셋입니다. -Wall 로 lint 하면 SYNCASYNCNET 경고로
//   나오는데, 같은 폴더의 wrapper + 어댑터 조합도 똑같이 섞여 있습니다.
//   (주석 줄을 v-e-r-i-l-a-t-o-r 라는 단어로 시작하지 마십시오. 그 도구가
//   지시문으로 읽고 빌드를 멈춥니다.)
//=====================================================================
`timescale 1ns/1ps
`include "bbht_grover_csr.vh"

module bbht_bram_top #(
    // System SRAM 범위. RVX 플랫폼 XML 의 sram_size(128 KiB)와 맞춥니다.
    parameter [31:0] SRAM_BASE = 32'hE000_0000,
    parameter [31:0] SRAM_LAST = 32'hE001_FFFF
) (
    input  wire        clk,        // clk_accel
    input  wire        rstnn,

    //-----------------------------------------------------------------
    // APB 슬레이브 (RVX i_grover_csr) -- 인수인계 §3.3 이름 그대로
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
    // AHB 마스터 (RVX i_grover_dma) -- 인수인계 §3.3 이름 그대로
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
    // CSR 쪽 신호
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
    // Main IP 쪽 신호
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

    // 정책·plan 텔레메트리. CKPT_SINGLE / CKPT_ENUM 에서 정책 엔진과
    // speculative plan FIFO 가 채웁니다. NORMAL_* 에서는 움직이지 않습니다.
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

    // Main IP 의 busy 는 탐색과 적재를 합친 것입니다 (인수인계 §3.4).
    // 적재기의 "탐색 중에는 DMA 거절" 과 아래 start 조건은 탐색만 따로
    // 봐야 하므로 여기서 나눕니다.
    wire core_search_busy = core_busy & ~core_load_busy;

    //=================================================================
    // §start -- 외부 start 수락 조건 (bbht_rvx_wrapper.v 와 같음)
    //
    // 큐를 두지 않습니다. 조건이 안 맞으면 COMMAND 펄스는 조용히 버려지고,
    // 펌웨어는 COMMAND 를 쓰기 전에 STATUS 를 먼저 보는 것이 규약입니다.
    //
    //   !search_busy   실행 중이 아닐 것
    //   !load_busy     적재 중이 아닐 것. 절반만 채워진 배열 위에서 오라클을
    //                  돌리면 경고 없이 그럴듯한 오답이 나옵니다
    //   res_empty      직전 열거 결과가 FIFO 에 남아 있지 않을 것
    //   !done_pending  직전 완료가 읽히지 않은 채 남아 있지 않을 것
    //=================================================================
    wire start_accept = cmd_search_start
                     && !core_search_busy
                     && !core_load_busy
                     && res_empty
                     && !done_pending;

    //=================================================================
    // §checkpoint 게이트 (src_comm/bbht_rvx_wrapper.v, 정본 wrapper 와 같음)
    //
    // CONTROL 의 burst 비트 하나가 Normal 과 체크포인트를 가릅니다
    // (CSR 정본 run_modes).
    //   auto_shot=0, burst=0  MANUAL_SINGLE
    //   auto_shot=1, burst=0  NORMAL_SINGLE / NORMAL_ENUM
    //   auto_shot=1, burst=1  CKPT_SINGLE   / CKPT_ENUM
    // 수동 실행에 체크포인트를 붙이는 경로는 정본 구성에 없으므로
    // auto_shot 으로 같이 막습니다.
    //=================================================================
    wire checkpoint_auto_enable = cfg_burst_enable & cfg_auto_shot;

    //=================================================================
    // CSR 블록. bbht_rvx_wrapper.v 와 파일도 결선도 같습니다.
    //=================================================================
    bbht_grover_mmio u_mmio (
        .clk                (clk),
        .rstnn              (rstnn),

        .psel               (psel),
        .penable            (penable),
        .pwrite             (pwrite),
        .paddr              (paddr),
        .pwdata             (pwdata),
        .pready             (pready),
        .prdata             (prdata),
        .pslverr            (pslverr),

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
    // 데이터셋 DMA. 적재가 시작되면(load_start) Main IP 안의 grover_loader
    // 가 cache_invalidate 를 세웁니다. 거절된 DMA 는 load_start 를 내지
    // 않으므로 이미 적재된 배열이 그대로 남습니다.
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
    // Main IP (보드 정본 K3/H3-E4-M2, src/ freeze). 어댑터를 거치지 않고
    // 직접 뭅니다. 파라미터는 정본 wrapper(src/bbht_rvx_wrapper.v 301행)가
    // 넘기는 값과 같고, 리셋 이름만 다릅니다 (Main IP 는 rstn).
    //=================================================================
    bbht_grover_main_ip #(
        .CHECKPOINT_ENABLE  (1),      // 체크포인트 하드웨어를 합성에 넣음
        .CKPT_K             (3),      // 체크포인트 3벌
        .POLICY_H_FUTURE    (3),      // 정책 지평 3
        .CKPT_MANUAL_ENABLE (0),      // 수동 체크포인트 경로 없음
        .AUTO_SPEC_ENABLE   (1),      // speculative plan FIFO 켬
        .INTRA_ENGINES      (4)       // 반복 한 번에 연산기 4벌 (E4)
    ) u_main_ip (
        .clk                        (clk),
        .rstn                       (rstnn),

        // Search / Mode
        .start                      (start_accept),
        .auto_shot                  (cfg_auto_shot),
        .j_target                   (cfg_j_target),
        .burst_enable               (cfg_burst_enable),
        .enum_enable                (cfg_enum_enable),
        .fail_repeat_limit          (cfg_fail_repeat_limit),

        // Checkpoint (manual). CKPT_MANUAL_ENABLE=0 이라 전부 0 으로 묶습니다.
        .checkpoint_manual_enable   (1'b0),
        .policy_valid               (1'b0),
        .policy_source_j            (7'd0),
        .policy_next_count          (3'd0),
        .policy_next_j_flat         (28'd0),

        // Checkpoint (auto). 위 §checkpoint 게이트.
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

        // Status (코어 안에서 sticky, 다음 수락된 start 까지 유지)
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

        // Policy / Plan telemetry
        .policy_cycles_total        (tm_policy_cycles_total),
        .policy_stall_cycles        (tm_policy_stall_cycles),
        .policy_actions_eval        (tm_policy_actions_eval),
        .policy_memo_hit            (tm_policy_memo_hit),
        .policy_memo_miss           (tm_policy_memo_miss),
        .policy_max_latency         (tm_policy_max_latency),
        .plan_fifo_level            (tm_plan_fifo_level),
        .plan_fifo_highwater        (tm_plan_fifo_highwater),
        .plan_fifo_empty_demand     (tm_plan_fifo_empty_demand),
        .plan_fifo_hit_count        (tm_plan_fifo_hit_count),
        .plan_fifo_mismatch_count   (tm_plan_fifo_mismatch_count),
        .policy_cold_solve_count    (tm_policy_cold_solve_count),
        .policy_spec_solve_count    (tm_policy_spec_solve_count)
    );

endmodule
