//=====================================================================
// bbht_dram_top.v -- hardware_dram 갈래 최상단 (호스트 통신 + DRAM 이음매)
//
// 호스트 PC 에서 가속기까지의 경로는 hardware_bram 과 같습니다.
//
//   호스트 PC --UART--> RVX RISC-V (bbht_console 펌웨어)
//             --APB--> bbht_grover_mmio  --> Main IP 설정/상태   (CSR 38개)
//             <-AHB--  bbht_ahb_loader   --> Main IP 데이터 적재 (System SRAM)
//
// 이 파일이 hardware_bram 쪽과 다른 점은 하나, DRAM burst 포트를 최상단
// 포트로 끌어낸다는 것입니다. 짝은 hardware_bram/src/bbht_bram_top.v
// 이고, 두 파일의 결선은 DRAM 포트와 Main IP 를 빼면 한 줄씩 같습니다.
//
//   Main IP --dram_wr_* / dram_rd_*--> (이 모듈의 포트) --> MIG/AXI 브리지
//
// 왜 bbht_rvx_wrapper.v 를 고치지 않고 파일을 새로 두는가
//   같은 폴더의 bbht_rvx_wrapper.v 와 bbht_grover_core_adapter.v 는
//   인수인계 계약(wrapper 19 + core 61 신호)을 그대로 지키는 판입니다.
//   check_ports.py dram 이 두 파일의 포트 목록을 계약표와 한 글자씩
//   대조하고, 계약에 없는 포트가 하나라도 있으면 실패로 봅니다. 그래서
//   DRAM 포트를 그 두 파일에 뚫을 수 없고, 어댑터는 DRAM 을 안쪽에서
//   rd_valid=0 / wr_ready=1 로 묶어 둘 수밖에 없습니다.
//
//   묶인 채로는 탐색이 제대로 돌지 않습니다. grover_dram_prep_seq 가 이미
//   자란 j 를 다시 뽑으면 grover_dram_amp_store 가 RESTORE 로 들어가
//   dram_rd_valid 를 기다리는데, 그 값이 0 으로 고정이라 영원히 안 옵니다.
//   시도가 두 번 이상인 탐색은 대개 이 경로를 탑니다. 실제로 계약판에
//   hardware_bram 의 tb_bbht_rvx 를 물리면 T6(EQ 33)이 여섯 번째 시도에서
//   busy 인 채(STATUS=0x801) 멈추고 cycle_count 만 계속 올라갑니다
//   (2026-09-11 확인).
//
//   그래서 이 모듈은 어댑터를 거치지 않고 lpsoc_bbht_grover_main_ip 를
//   직접 물고, DRAM 포트를 밖으로 냅니다. 통신 계층(mmio, loader)은
//   bbht_rvx_wrapper.v 와 같은 파일을 같은 결선으로 씁니다. 계약판은
//   check_ports 대조용으로, 이 파일은 실제로 도는 최상단으로 역할을
//   나눕니다.
//
// 결선 판단 (bbht_rvx_wrapper.v 와 같은 규칙입니다)
//   1. start 수락 조건        아래 §start
//   2. checkpoint_* 입력      이 갈래 Main IP 는 읽지 않으므로 0 으로 묶음
//   3. burst_enable           계약 호환으로 CSR 값을 그대로 넘김 (미사용)
//
// 클럭
//   전부 clk 하나(clk_accel = 100 MHz)입니다. DRAM 포트도 이 클럭 영역에
//   있습니다. MIG 는 자기 ui_clk 로 돌기 때문에 브리지 쪽에서 CDC 를 해야
//   합니다. APB/AHB 쪽 CDC 는 RVX 가 sni_apb_asynch / mni_ahbm_asynch 로
//   이미 넣어 주므로 여기에 또 넣지 않습니다 (인수인계 §3.2).
//
// DRAM 이음매 계약 (grover_dram_param.vh, grover_dram_amp_store.v)
//   한 beat = 진폭 한 행 = 32 레인 x 23비트 = 736비트
//   한 버스트 = 512 beat = 한 슬롯. len 은 beat 수 - 1 (= 511)
//   슬롯 j 의 시작 주소 = GD_AMP_BASE + j * 47,104 바이트
//   쓰기: wr_req 는 한 사이클 펄스이고 그때 wr_addr/wr_len 이 유효합니다.
//         이어서 wr_valid 가 선 beat 를 wr_ready 가 설 때까지 붙들고
//         있습니다 (valid/ready 핸드셰이크). 마지막 beat 에 wr_last.
//   읽기: rd_req 도 한 사이클 펄스입니다. 복원하는 동안 rd_ready 가 1 로
//         서 있고 그 사이 복원 버퍼는 매 사이클 beat 를 받을 수 있습니다.
//         브리지는 rd_valid 를 정확히 len+1 번 올려야 합니다. rd_last 는
//         지금 참고용으로만 받습니다.
//   슬롯 0 은 절대 안 씁니다. j=0 은 균등 초기 상태라 늘 새로 만듭니다.
//   쓰기 버스트와 읽기 버스트는 동시에 열리지 않습니다. 포트가 한 줄짜리라
//   호출 쪽(grover_dram_shot_fsm)이 직렬로 냅니다. 브리지는 이 전제에
//   기대도 되고, tb_bbht_dram_top 이 최상단 포트에서 매 사이클 감시합니다.
//
// 호스트 규약 한 가지 (grover_loader.v 에서 오는 것)
//   적재가 끝난 뒤 DATA_COUNT 를 적재 때와 다른 값으로 한 번이라도 쓰면
//   배열이 무효가 되고(data_count_mismatch -> data_valid=0) DRAM 표도 같이
//   버려집니다. 값을 되돌려도 다시 살아나지 않으므로 재적재 전까지 탐색은
//   config_error 입니다. DMA 개수 거절(0 이나 N 초과)도 DATA_COUNT 를 쓰는
//   순간 이 경우에 들어갑니다. 정렬·범위 거절은 개수를 안 바꾸면 무해합니다.
//
// 리셋
//   rstnn 하나를 세 블록이 나눠 씁니다. mmio 와 loader 는 비동기 리셋,
//   Main IP(hardware_bram 에서 재사용한 파일들)는 동기 리셋입니다.
//   -Wall 로 lint 하면 이것이 SYNCASYNCNET 경고로 나옵니다. 같은 폴더의
//   bbht_rvx_wrapper.v + 어댑터 조합도 똑같이 섞여 있어서 이 파일이 새로
//   만든 구조는 아닙니다. 리셋 해제 타이밍은 RVX 쪽 리셋 시퀀서에 달려
//   있으므로 보드 통합 때 한 번 확인할 자리입니다.
//   (주석 줄을 v-e-r-i-l-a-t-o-r 라는 단어로 시작하지 마십시오. 그 도구가
//   지시문으로 읽고 빌드를 멈춥니다.)
//
// 아직 없는 것
//   - 물리 DRAM 바인딩. 이 포트에 MIG native UI 나 AXI4 브리지를 붙이는
//     일은 따로 남아 있습니다. 시뮬에서는 testbench/dram_burst_model.v 가
//     이 자리에 들어갑니다.
//   - DRAM 관측 CSR. dram_frontier_j 를 포트로만 내고 CSR 에는 올리지
//     않았습니다. CSR 은 software/csr/bbht_grover_csr.json 한 곳에서
//     나오고 두 갈래가 공유하므로, 한 갈래 전용 레지스터를 넣으려면
//     그 정본부터 손봐야 합니다.
//   - Enumeration. Main IP 가 enum_enable=1 을 config_error 로 거절합니다.
//     CSR 과 결과 FIFO 는 계약대로 다 붙어 있고 FIFO 는 늘 비어 있습니다.
//=====================================================================
`timescale 1ns/1ps
`include "bbht_grover_csr.vh"
`include "grover_dram_param.vh"

module bbht_dram_top #(
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
    output wire [31:0] shwdata,

    //-----------------------------------------------------------------
    // DRAM burst 포트 -- MIG/AXI 브리지가 붙을 자리 (clk 영역)
    //-----------------------------------------------------------------
    output wire                            dram_wr_req,
    output wire [`GD_ADDR_W-1:0]           dram_wr_addr,
    output wire [`GD_BURST_LEN_W-1:0]      dram_wr_len,
    output wire                            dram_wr_valid,
    output wire [`GP_P*`GP_AMP_W-1:0]      dram_wr_data,
    output wire                            dram_wr_last,
    input  wire                            dram_wr_ready,

    output wire                            dram_rd_req,
    output wire [`GD_ADDR_W-1:0]           dram_rd_addr,
    output wire [`GD_BURST_LEN_W-1:0]      dram_rd_len,
    input  wire                            dram_rd_valid,
    input  wire [`GP_P*`GP_AMP_W-1:0]      dram_rd_data,
    output wire                            dram_rd_ready,
    input  wire                            dram_rd_last,

    // 이번 세션에서 DRAM 에 저장된 가장 큰 반복 수 j. 0 이면 표가 비어
    // 있습니다. 적재(DMA)나 술어 변경으로 표가 버려지면 0 으로 돌아갑니다.
    // 보드에서는 ILA 나 LED 로 볼 관측점입니다.
    output wire [`GP_J_W-1:0]              dram_frontier_j
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

    // 정책·plan 텔레메트리. 이 갈래에는 정책 엔진이 없어 Main IP 가 전부
    // 0 을 냅니다. CSR 주소는 두 갈래가 같아야 하므로 자리는 그대로 둡니다.
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
    //   !load_busy     적재 중이 아닐 것. 이 갈래에서는 한 가지 이유가 더
    //                  있습니다 -- 적재가 시작되면 DRAM 표가 버려지는데,
    //                  그 사이에 탐색이 돌면 반쯤 채운 배열로 표를 다시
    //                  키우고 그 표가 다음 탐색까지 살아남습니다
    //   res_empty      결과 FIFO 가 비었을 것 (이 갈래에서는 늘 참)
    //   !done_pending  직전 완료가 읽히지 않은 채 남아 있지 않을 것
    //=================================================================
    wire start_accept = cmd_search_start
                     && !core_search_busy
                     && !core_load_busy
                     && res_empty
                     && !done_pending;

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
    // 데이터셋 DMA. 적재가 시작되면(load_start) Main IP 안에서
    // loader_cache_invalidate 가 서고, 그것이 DRAM 표 무효화
    // (dram_invalidate -> frontier_j = 0)로 이어집니다. 거절된 DMA 는
    // load_start 를 내지 않으므로 표가 그대로 남습니다.
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
    // Main IP (DRAM 전량저장판). 어댑터를 거치지 않고 직접 뭅니다.
    // 리셋 이름만 다릅니다 (Main IP 는 rstn).
    //=================================================================
    lpsoc_bbht_grover_main_ip u_main_ip (
        .clk                        (clk),
        .rstn                       (rstnn),

        // Search / Mode
        .start                      (start_accept),
        .auto_shot                  (cfg_auto_shot),
        .j_target                   (cfg_j_target),
        .burst_enable               (cfg_burst_enable),
        .enum_enable                (cfg_enum_enable),
        .fail_repeat_limit          (cfg_fail_repeat_limit),

        // Checkpoint (manual/auto). 이 갈래에는 체크포인트가 없습니다.
        // Main IP 가 읽지 않는 포트라 0 으로 묶어 두는 것이 가장 정직합니다.
        .checkpoint_manual_enable   (1'b0),
        .policy_valid               (1'b0),
        .policy_source_j            (7'd0),
        .policy_next_count          (3'd0),
        .policy_next_j_flat         (28'd0),
        .checkpoint_auto_enable     (1'b0),

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

        // Enumeration (이 갈래는 미구현, 상수만 나옵니다)
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

        // Policy / Plan telemetry (항상 0)
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
        .policy_spec_solve_count    (tm_policy_spec_solve_count),

        // DRAM burst 포트. 이 모듈의 포트로 그대로 나갑니다.
        .dram_wr_req                (dram_wr_req),
        .dram_wr_addr               (dram_wr_addr),
        .dram_wr_len                (dram_wr_len),
        .dram_wr_valid              (dram_wr_valid),
        .dram_wr_data               (dram_wr_data),
        .dram_wr_last               (dram_wr_last),
        .dram_wr_ready              (dram_wr_ready),

        .dram_rd_req                (dram_rd_req),
        .dram_rd_addr               (dram_rd_addr),
        .dram_rd_len                (dram_rd_len),
        .dram_rd_valid              (dram_rd_valid),
        .dram_rd_data               (dram_rd_data),
        .dram_rd_ready              (dram_rd_ready),
        .dram_rd_last               (dram_rd_last),

        .dram_frontier_j            (dram_frontier_j)
    );

endmodule
