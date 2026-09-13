//==============================================================================
// bbht_standalone_top.v -- LPSoC BBHT/Grover K4/H4 standalone top (Arty A7-100T)
//
// bbht_rvx_wrapper.v 를 RVX 없이 성립하도록 바꾼 것이다.
// 코어 IP(lpsoc_bbht_grover_main_ip)와 CSR 블록(bbht_grover_mmio)은 수정하지
// 않는다.  교체된 것은 두 가지뿐이다.
//
//   RVX APB 슬레이브   ->  bbht_uart_apb_bridge  (호스트 UART가 APB 마스터가 됨)
//   RVX AHB 마스터 DMA ->  bbht_dataset_gen      (데이터셋을 IP 안에서 생성)
//
// 따라서 CSR 맵/오프셋/비트 배치가 RVX 빌드와 완전히 동일하다.  같은 시드로
// 돌린 결과를 두 빌드 사이에서 직접 대조할 수 있다.
//
//------------------------------------------------------------------------------
// 클럭
//------------------------------------------------------------------------------
// RVX 빌드에서 BBHT IP는 PLL 출력(50 MHz)이 아니라 E3 원시 클럭
// sys_clk_pin(100 MHz)에 BUFG 직결로 물려 있었다 (route_timing_summary.rpt:
// sys_clk_pin period=10.000 WNS=+0.236, 최악 경로가 u_main_ip/.../u_born).
// 50 MHz 도메인은 rvc_orca 코어/주변장치 전용이었으므로 여기서는 사라진다.
// MMCM/PLL이 필요 없고 CDC도 없다.  Vivado가 클럭 포트에 IBUF+BUFG를 자동
// 삽입하므로 명시적 프리미티브 인스턴스도 두지 않는다 (시뮬레이션 호환).
//
//------------------------------------------------------------------------------
// 생성기 제어를 위한 CSR 재사용
//------------------------------------------------------------------------------
// bbht_grover_mmio.v 를 고치지 않기 위해, 기존 DMA CSR을 그대로 쓴다.
//
//   DMA_COMMAND (0x5C) 쓰기  ->  cmd_dma_start  ->  생성기 gen_start
//   DATA_ADDR   (0x58) [8:0] ->  cfg_data_addr  ->  생성기 target_count
//   DMA_STATUS  (0x60)       <-  {done_sticky, error_bits[4:0], error, busy}
//
// 펌웨어는 DATA_ADDR 에 SRAM 포인터를 썼고, 여기서는 타깃 개수를 쓴다.
// 상태 워드의 비트 배치는 그대로이므로 호스트의 폴링 논리도 동일하다
// (DMA_DONE_BIT = 1<<7, DMA_ERROR_BIT = 1<<1).
//
//------------------------------------------------------------------------------
// LED
//------------------------------------------------------------------------------
//   led[0]  heartbeat  약 1 Hz.  클럭이 살아 있고 리셋이 풀렸음을 뜻한다.
//   led[1]  busy       탐색 또는 데이터셋 생성 진행 중
//   led[2]  result     result_valid (마지막 탐색이 해를 찾음)
//   led[3]  error      설정/샷/예산/포화/영가중치/적재/생성 오류 중 하나
//
// 버튼은 둘 다 보조 리셋이다 (ck_rst 와 동일 효과).
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module bbht_standalone_top #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 1_000_000
) (
    input  wire        CLK100MHZ,     // E3, 100 MHz
    input  wire        ck_rst,        // C2, active-low

    input  wire        uart_txd_in,   // A9,  PC -> FPGA
    output wire        uart_rxd_out,  // D10, FPGA -> PC

    input  wire [1:0]  btn,           // D9 / C9, 보조 리셋
    output wire [3:0]  led            // H5 / J5 / T9 / T10
);

    wire clk = CLK100MHZ;

    //==========================================================================
    // 리셋 -- 비동기 인가, 동기 해제.  해제 후 최소 16사이클 유지.
    //==========================================================================
    wire rst_req = (~ck_rst) | btn[0] | btn[1];

    reg [1:0] rst_sync;
    reg [3:0] rst_hold;
    reg       rstn;

    always @(posedge clk or posedge rst_req) begin
        if (rst_req) begin
            rst_sync <= 2'b00;
            rst_hold <= 4'd0;
            rstn     <= 1'b0;
        end
        else begin
            rst_sync <= {rst_sync[0], 1'b1};
            if (rst_sync[1]) begin
                if (rst_hold == 4'hF) rstn <= 1'b1;
                else                  rst_hold <= rst_hold + 4'd1;
            end
        end
    end

    //==========================================================================
    // APB (브리지 -> MMIO)
    //==========================================================================
    wire        psel, penable, pwrite;
    wire [31:0] paddr, pwdata;
    wire        pready, pslverr;
    wire [31:0] prdata;

    bbht_uart_apb_bridge #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) u_bridge (
        .clk(clk),
        .rstnn(rstn),

        .uart_rx(uart_txd_in),
        .uart_tx(uart_rxd_out),

        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .paddr(paddr),
        .pwdata(pwdata),

        .pready(pready),
        .prdata(prdata),
        .pslverr(pslverr)
    );

    //==========================================================================
    // MMIO -> Main IP 설정
    //==========================================================================
    wire                         cmd_start;

    wire                         cfg_auto_shot;
    wire [`GP_J_W-1:0]           cfg_j_target;
    wire                         cfg_burst_enable;
    wire [1:0]                   cfg_predicate_mode;

    wire signed [`GP_DATA_W-1:0] cfg_threshold_a;
    wire signed [`GP_DATA_W-1:0] cfg_threshold_b;

    wire [`GP_DATA_COUNT_W-1:0]  cfg_data_count;
    wire [`GP_SHOT_CAP_W-1:0]    cfg_shot_cap;

    wire [31:0]                  cfg_seed_j;
    wire [31:0]                  cfg_seed_meas;

    wire                         cfg_enum_enable;
    wire [`GP_ENUM_FAIL_W-1:0]   cfg_fail_repeat_limit;

    wire                         cmd_res_pop;

    // 생성기 제어 (DMA CSR 재사용)
    wire [31:0]                  cfg_data_addr;
    wire                         cmd_dma_start;

    //==========================================================================
    // 생성기 -> Main IP 적재 스트림
    //==========================================================================
    wire                         mip_load_start;
    wire                         mip_data_wr_en;
    wire [`GP_INDEX_W-1:0]       mip_data_wr_addr;
    wire signed [`GP_DATA_W-1:0] mip_data_wr_data;
    wire                         mip_load_done;

    //==========================================================================
    // Main IP -> MMIO 상태
    //==========================================================================
    wire                         st_busy;
    wire                         st_load_busy;
    wire                         st_done;
    wire                         st_result_valid;
    wire [`GP_INDEX_W-1:0]       st_result_index;

    wire                         st_enum_done;
    wire [`GP_FOUND_COUNT_W-1:0] st_found_count;
    wire [`GP_ENUM_FAIL_W-1:0]   st_consecutive_fail_count;
    wire [`GP_RESULT_FIFO_CNT_W-1:0] st_max_fifo_occupancy;
    wire [31:0]                  st_fifo_stall_cycles;

    wire [`GP_INDEX_W-1:0]       st_res_dout;
    wire                         st_res_empty;
    wire [`GP_RESULT_FIFO_CNT_W-1:0] st_res_count;

    wire                         st_config_error;
    wire                         st_shot_limit;
    wire                         st_budget_limit;
    wire                         st_amp_overflow;
    wire                         st_zero_weight_error;
    wire                         st_load_error;

    wire [31:0]                  st_trial_count;
    wire [31:0]                  st_L_BBHT;
    wire [31:0]                  st_actual_grover_iterations;
    wire [31:0]                  st_cycle_count;

    wire [31:0]                  st_policy_cycles_total;
    wire [31:0]                  st_policy_stall_cycles;
    wire [31:0]                  st_policy_actions_eval;
    wire [31:0]                  st_policy_memo_hit;
    wire [31:0]                  st_policy_memo_miss;
    wire [31:0]                  st_policy_max_latency;

    wire [2:0]                   st_plan_fifo_level;
    wire [2:0]                   st_plan_fifo_highwater;
    wire [31:0]                  st_plan_fifo_empty_demand;
    wire [31:0]                  st_plan_fifo_hit_count;
    wire [31:0]                  st_plan_fifo_mismatch_count;
    wire [31:0]                  st_policy_cold_solve_count;
    wire [31:0]                  st_policy_spec_solve_count;

    //==========================================================================
    // 생성기 상태 (기존 DMA 상태 포트에 그대로 매핑)
    //==========================================================================
    wire                         st_gen_busy;
    wire                         st_gen_error;
    wire [4:0]                   st_gen_error_bits;

    //==========================================================================
    // CSR 블록 -- 수정 없음
    //==========================================================================
    bbht_grover_mmio u_mmio (
        .clk(clk),
        .rstnn(rstn),

        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .paddr(paddr),
        .pwdata(pwdata),

        .pready(pready),
        .prdata(prdata),
        .pslverr(pslverr),

        .cmd_start(cmd_start),

        .cfg_auto_shot(cfg_auto_shot),
        .cfg_j_target(cfg_j_target),
        .cfg_burst_enable(cfg_burst_enable),
        .cfg_predicate_mode(cfg_predicate_mode),

        .cfg_threshold_a(cfg_threshold_a),
        .cfg_threshold_b(cfg_threshold_b),

        .cfg_data_count(cfg_data_count),
        .cfg_shot_cap(cfg_shot_cap),

        .cfg_seed_j(cfg_seed_j),
        .cfg_seed_meas(cfg_seed_meas),

        .cfg_enum_enable(cfg_enum_enable),
        .cfg_fail_repeat_limit(cfg_fail_repeat_limit),

        .cmd_res_pop(cmd_res_pop),

        .cfg_data_addr(cfg_data_addr),
        .cmd_dma_start(cmd_dma_start),

        .st_busy(st_busy),
        .st_load_busy(st_load_busy),
        .st_done_pulse(st_done),
        .st_result_valid(st_result_valid),
        .st_result_index(st_result_index),

        .st_enum_done(st_enum_done),
        .st_found_count(st_found_count),
        .st_consecutive_fail_count(st_consecutive_fail_count),
        .st_max_fifo_occupancy(st_max_fifo_occupancy),
        .st_fifo_stall_cycles(st_fifo_stall_cycles),

        .st_res_dout(st_res_dout),
        .st_res_empty(st_res_empty),
        .st_res_count(st_res_count),

        .st_config_error(st_config_error),
        .st_shot_limit(st_shot_limit),
        .st_budget_limit(st_budget_limit),
        .st_amp_overflow(st_amp_overflow),
        .st_zero_weight_error(st_zero_weight_error),
        .st_load_error(st_load_error),

        .st_trial_count(st_trial_count),
        .st_L_BBHT(st_L_BBHT),
        .st_actual_grover_iterations(st_actual_grover_iterations),
        .st_cycle_count(st_cycle_count),

        .st_policy_cycles_total(st_policy_cycles_total),
        .st_policy_stall_cycles(st_policy_stall_cycles),
        .st_policy_actions_eval(st_policy_actions_eval),
        .st_policy_memo_hit(st_policy_memo_hit),
        .st_policy_memo_miss(st_policy_memo_miss),
        .st_policy_max_latency(st_policy_max_latency),

        .st_plan_fifo_level(st_plan_fifo_level),
        .st_plan_fifo_highwater(st_plan_fifo_highwater),
        .st_plan_fifo_empty_demand(st_plan_fifo_empty_demand),
        .st_plan_fifo_hit_count(st_plan_fifo_hit_count),
        .st_plan_fifo_mismatch_count(st_plan_fifo_mismatch_count),
        .st_policy_cold_solve_count(st_policy_cold_solve_count),
        .st_policy_spec_solve_count(st_policy_spec_solve_count),

        // 생성기 상태를 기존 DMA 상태 자리에 매핑
        .st_dma_busy(st_gen_busy),
        .st_dma_error(st_gen_error),
        .st_dma_error_bits(st_gen_error_bits),
        .st_dma_done_pulse(mip_load_done)
    );

    //==========================================================================
    // 데이터셋 생성기 -- bbht_ahb_loader 를 대체
    //==========================================================================
    bbht_dataset_gen u_gen (
        .clk(clk),
        .rstnn(rstn),

        .data_count(cfg_data_count),
        .target_count(cfg_data_addr[8:0]),
        .gen_start(cmd_dma_start),

        .gen_busy(st_gen_busy),
        .gen_error(st_gen_error),
        .gen_error_bits(st_gen_error_bits),

        .load_start(mip_load_start),
        .data_wr_en(mip_data_wr_en),
        .data_wr_addr(mip_data_wr_addr),
        .data_wr_data(mip_data_wr_data),
        .load_done(mip_load_done),
        .load_busy(st_load_busy),
        .main_busy(st_busy)
    );

    //==========================================================================
    // BBHT / Grover Main IP -- E4 physical kernel enabled; K4/H4 semantics unchanged.
    //==========================================================================
    bbht_grover_main_ip #(
        .CHECKPOINT_ENABLE(1),
        .CKPT_K(4),
        .POLICY_H_FUTURE(4),
        .CKPT_MANUAL_ENABLE(0),
        .AUTO_SPEC_ENABLE(1),
        .INTRA_ENGINES(1),
        .MEAS_M1_ENABLE(0),
        .MEAS_M2_ENABLE(0)
    ) u_main_ip (
        .clk(clk),
        .rstn(rstn),

        .start(cmd_start),
        .auto_shot(cfg_auto_shot),
        .j_target(cfg_j_target),
        .burst_enable(cfg_burst_enable),

        .enum_enable(cfg_enum_enable),
        .fail_repeat_limit(cfg_fail_repeat_limit),

        .checkpoint_manual_enable(1'b0),
        .policy_valid(1'b0),
        .policy_source_j({`GP_J_W{1'b0}}),
        .policy_next_count(3'd0),
        .policy_next_j_flat({(4*`GP_J_W){1'b0}}),
        .checkpoint_auto_enable(cfg_burst_enable && cfg_auto_shot),

        .predicate_mode(cfg_predicate_mode),
        .threshold_a(cfg_threshold_a),
        .threshold_b(cfg_threshold_b),
        .data_count(cfg_data_count),

        .shot_cap(cfg_shot_cap),
        .seed_j(cfg_seed_j),
        .seed_meas(cfg_seed_meas),

        .load_start(mip_load_start),
        .data_wr_en(mip_data_wr_en),
        .data_wr_addr(mip_data_wr_addr),
        .data_wr_data(mip_data_wr_data),
        .load_done(mip_load_done),
        .load_busy(st_load_busy),

        .res_pop(cmd_res_pop),
        .res_dout(st_res_dout),
        .res_empty(st_res_empty),
        .res_count(st_res_count),

        .busy(st_busy),
        .done(st_done),
        .result_valid(st_result_valid),
        .result_index(st_result_index),

        .enum_done(st_enum_done),
        .found_count(st_found_count),
        .consecutive_fail_count(st_consecutive_fail_count),
        .max_fifo_occupancy(st_max_fifo_occupancy),
        .fifo_stall_cycles(st_fifo_stall_cycles),

        .config_error(st_config_error),
        .shot_limit(st_shot_limit),
        .budget_limit(st_budget_limit),
        .amp_overflow(st_amp_overflow),
        .zero_weight_error(st_zero_weight_error),
        .load_error(st_load_error),

        .trial_count(st_trial_count),
        .L_BBHT(st_L_BBHT),
        .actual_grover_iterations(st_actual_grover_iterations),
        .cycle_count(st_cycle_count),

        .policy_cycles_total(st_policy_cycles_total),
        .policy_stall_cycles(st_policy_stall_cycles),
        .policy_actions_eval(st_policy_actions_eval),
        .policy_memo_hit(st_policy_memo_hit),
        .policy_memo_miss(st_policy_memo_miss),
        .policy_max_latency(st_policy_max_latency),

        .plan_fifo_level(st_plan_fifo_level),
        .plan_fifo_highwater(st_plan_fifo_highwater),
        .plan_fifo_empty_demand(st_plan_fifo_empty_demand),
        .plan_fifo_hit_count(st_plan_fifo_hit_count),
        .plan_fifo_mismatch_count(st_plan_fifo_mismatch_count),
        .policy_cold_solve_count(st_policy_cold_solve_count),
        .policy_spec_solve_count(st_policy_spec_solve_count)
    );

    //==========================================================================
    // LED
    //==========================================================================
    // heartbeat: 100 MHz / 2^25 = 약 3 Hz 토글
    reg [24:0] hb;
    always @(posedge clk) begin
        if (!rstn) hb <= 25'd0;
        else       hb <= hb + 25'd1;
    end

    // 마지막 탐색의 result_valid 를 유지한다 (done 시점에 래치)
    reg result_hold;
    always @(posedge clk) begin
        if (!rstn)          result_hold <= 1'b0;
        else if (cmd_start) result_hold <= 1'b0;
        else if (st_done)   result_hold <= st_result_valid;
    end

    wire any_error = st_config_error      |
                     st_shot_limit        |
                     st_budget_limit      |
                     st_amp_overflow      |
                     st_zero_weight_error |
                     st_load_error        |
                     st_gen_error;

    assign led[0] = hb[24];
    assign led[1] = st_busy | st_load_busy | st_gen_busy;
    assign led[2] = result_hold;
    assign led[3] = any_error;

endmodule
