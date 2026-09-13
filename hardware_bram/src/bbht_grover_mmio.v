//=====================================================================
// bbht_grover_mmio.v -- BBHT/Grover APB CSR 블록 (통신 담당 소유)
//
// RVX 가 user_slaveif_apb_clkout 으로 뽑아 주는 APB 슬레이브 포트를 받아
// 레지스터 파일로 만듭니다. 포트 이름은 인수인계 §3.3 계약(psel/penable/...)을
// 따릅니다 -- RVX 쪽 배선 이름(i_grover_csr_rp*)과의 매핑은 user_region 에서
// 한 번만 합니다. 주소 맵의 정본은 software/csr/bbht_grover_csr.json
// 이고, 이 파일이 include 하는 bbht_grover_csr.vh 는 거기서 생성됩니다.
// 오프셋 숫자를 이 파일에 직접 쓰지 마십시오.
//
// RVX 가 network 쪽(gclk_noc)과 이 블록(clk_accel) 사이에 sni_apb_asynch 를
// 이미 넣어 줍니다. 여기에 CDC 를 또 넣으면 안 됩니다.
//
// 레지스터 성격이 셋으로 갈립니다.
//   RW   설정. 여기 저장되고 값이 출력 와이어로 상시 나갑니다.
//   W1P  명령. 저장 공간이 없고 쓰면 1사이클 펄스만 나갑니다. 읽으면 0 입니다.
//        무엇을 썼는지는 무시합니다 -- 쓰는 행위 자체가 명령입니다.
//   RO   상태. 저장하지 않고 코어가 내보내는 와이어를 읽기 응답에 실어 보냅니다.
//
// FIFO_DATA 만 예외입니다. 읽기 완료 자체가 pop 이라 부작용이 있는 유일한
// 읽기이고, 그래서 별도 POP 레지스터가 없습니다. 값 0 이 정상 결과일 수
// 있으므로(인덱스 0) 0 을 empty 로 해석하면 안 됩니다.
//=====================================================================
`timescale 1ns/1ps
`include "bbht_grover_csr.vh"

module bbht_grover_mmio (
    input  wire        clk,
    input  wire        rstnn,

    //-----------------------------------------------------------------
    // APB 슬레이브 -- 인수인계 §3.3 계약 이름
    //-----------------------------------------------------------------
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] paddr,
    input  wire [31:0] pwdata,
    output wire        pready,
    output reg  [31:0] prdata,
    output wire        pslverr,

    //-----------------------------------------------------------------
    // 명령 펄스 (W1P)
    //-----------------------------------------------------------------
    output reg         cmd_search_start,
    output reg         cmd_dma_start,

    // 직전 실행의 완료가 아직 남아 있는가. wrapper 의 start 수락 조건에서
    // "pending result 없음" 항으로 쓰입니다.
    output wire        done_pending,

    //-----------------------------------------------------------------
    // 설정 출력 (RW)
    //-----------------------------------------------------------------
    output reg         cfg_auto_shot,
    output reg         cfg_burst_enable,
    output reg  [1:0]  cfg_predicate_mode,
    output reg  [6:0]  cfg_j_target,
    output reg  signed [15:0] cfg_threshold_a,
    output reg  signed [15:0] cfg_threshold_b,
    output reg  [14:0] cfg_data_count,
    output reg  [15:0] cfg_shot_cap,
    output reg  [31:0] cfg_seed_j,
    output reg  [31:0] cfg_seed_meas,
    output reg         cfg_enum_enable,
    output reg  [3:0]  cfg_fail_repeat_limit,
    output reg  [31:0] cfg_data_addr,

    //-----------------------------------------------------------------
    // 코어 상태 입력 (RO)
    //-----------------------------------------------------------------
    input  wire        st_busy,
    input  wire        st_load_busy,
    input  wire        st_done,               // 완료. 펄스든 레벨이든 받습니다
    input  wire        st_result_valid,
    input  wire        st_config_error,       // 아래 여섯은 코어에서 이미 sticky
    input  wire        st_shot_limit,
    input  wire        st_budget_limit,
    input  wire        st_amp_overflow,
    input  wire        st_zero_weight_error,
    input  wire        st_load_error,
    input  wire        st_enum_done,          // 완료. 펄스든 레벨이든 받습니다
    input  wire [13:0] st_result_index,
    input  wire [31:0] st_trial_count,
    input  wire [31:0] st_l_bbht,
    input  wire [31:0] st_actual_iter,
    input  wire [31:0] st_cycle_count,
    input  wire [14:0] st_found_count,
    input  wire [3:0]  st_consecutive_fail,
    input  wire [8:0]  st_max_fifo_occupancy,
    input  wire [31:0] st_fifo_stall_cycles,

    //-----------------------------------------------------------------
    // Result FIFO -- 읽기 완료가 곧 pop
    //-----------------------------------------------------------------
    input  wire [13:0] res_dout,
    input  wire        res_empty,
    input  wire [8:0]  res_count,
    output wire        res_pop,

    //-----------------------------------------------------------------
    // DMA 상태 (loader 가 만듦)
    //-----------------------------------------------------------------
    input  wire [7:0]  dma_status,

    //-----------------------------------------------------------------
    // K4/H8 텔레메트리 (전부 RO)
    //-----------------------------------------------------------------
    input  wire [31:0] tm_policy_cycles_total,
    input  wire [31:0] tm_policy_stall_cycles,
    input  wire [31:0] tm_policy_actions_eval,
    input  wire [31:0] tm_policy_memo_hit,
    input  wire [31:0] tm_policy_memo_miss,
    input  wire [31:0] tm_policy_max_latency,
    input  wire [2:0]  tm_plan_fifo_level,
    input  wire [2:0]  tm_plan_fifo_highwater,
    input  wire [31:0] tm_plan_fifo_empty_demand,
    input  wire [31:0] tm_plan_fifo_hit_count,
    input  wire [31:0] tm_plan_fifo_mismatch_count,
    input  wire [31:0] tm_policy_cold_solve_count,
    input  wire [31:0] tm_policy_spec_solve_count
);

    //-----------------------------------------------------------------
    // APB 디코드
    //
    // pready 는 상수 1 입니다. 따라서 access phase 가 정확히 한 사이클이고,
    // FIFO pop 을 그 한 사이클에 딱 한 번 내보낼 수 있습니다.
    //-----------------------------------------------------------------
    assign pready = 1'b1;

    localparam IW = `BBHT_CSR_IDX_BITS;

    wire [IW-1:0] ridx    = paddr[IW+1:2];          // 4바이트 간격이므로 [1:0] 은 정렬 비트
    wire          aligned = (paddr[1:0] == 2'b00);
    wire          in_map  = (paddr[11:IW+2] == 0) && (ridx < `BBHT_CSR_NUM_REG);
    wire          mapped  = aligned && in_map;

    wire access = psel & penable;
    wire wr     = access &  pwrite & mapped;
    wire rd     = access & ~pwrite & mapped;

    // 정렬되지 않은 접근과 미할당 주소는 오류로 떨어집니다.
    assign pslverr = access && !mapped;

    //-----------------------------------------------------------------
    // 읽기 완료가 곧 pop. 비어 있으면 pop 하지 않습니다 -- 빈 FIFO 를
    // 읽어도 언더플로가 나지 않아야 합니다.
    //-----------------------------------------------------------------
    assign res_pop = rd && (ridx == `CSR_IDX_FIFO_DATA) && !res_empty;

    //-----------------------------------------------------------------
    // 완료 비트의 sticky latch
    //
    // 코어의 done / enum_done 을 상승 에지로 잡습니다. 코어가 펄스를 주든
    // 레벨을 계속 물고 있든 같게 동작하게 하려는 것입니다. 레벨을 물고 있는
    // 코어에 대해 레벨을 그대로 latch 하면, COMMAND 로 클리어한 다음 사이클에
    // 곧바로 다시 서서 "직전 실행의 done" 이 새 실행 시작 시점에 보입니다.
    // 폴링하는 펌웨어는 그것을 자기 실행의 완료로 착각하고 낡은 결과를
    // 읽습니다. 에지로 잡으면 그 부류가 통째로 없어집니다.
    //-----------------------------------------------------------------
    reg done_d, enum_done_d;
    reg done_sticky, enum_done_sticky;

    wire cmd_wr_start = wr && (ridx == `CSR_IDX_COMMAND);
    wire cmd_wr_dma   = wr && (ridx == `CSR_IDX_DMA_COMMAND);

    always @(posedge clk or negedge rstnn) begin
        if (!rstnn) begin
            done_d           <= 1'b0;
            enum_done_d      <= 1'b0;
            done_sticky      <= 1'b0;
            enum_done_sticky <= 1'b0;
        end else begin
            done_d      <= st_done;
            enum_done_d <= st_enum_done;

            // COMMAND 쓰기가 클리어보다 우선입니다. 새 실행을 시작하는 그
            // 사이클에 직전 실행의 완료 비트가 남아 있으면 안 됩니다.
            if (cmd_wr_start)                  done_sticky <= 1'b0;
            else if (st_done && !done_d)       done_sticky <= 1'b1;

            if (cmd_wr_start)                        enum_done_sticky <= 1'b0;
            else if (st_enum_done && !enum_done_d)   enum_done_sticky <= 1'b1;
        end
    end

    assign done_pending = done_sticky;

    //-----------------------------------------------------------------
    // 명령 펄스와 설정 레지스터
    //-----------------------------------------------------------------
    always @(posedge clk or negedge rstnn) begin
        if (!rstnn) begin
            cmd_search_start      <= 1'b0;
            cmd_dma_start         <= 1'b0;

            cfg_auto_shot         <= 1'b1;      // 기본은 BBHT 자율
            cfg_burst_enable      <= 1'b0;
            cfg_predicate_mode    <= `BBHT_PRED_LT;
            cfg_j_target          <= 7'd0;
            cfg_threshold_a       <= 16'sd0;
            cfg_threshold_b       <= 16'sd0;
            cfg_data_count        <= `BBHT_N_ENTRIES;   // 15비트 폭에 맞춰 잘립니다
            cfg_shot_cap          <= 16'd100;
            cfg_seed_j            <= 32'h1;
            cfg_seed_meas         <= 32'h1;
            cfg_enum_enable       <= 1'b0;
            cfg_fail_repeat_limit <= 4'd4;
            cfg_data_addr         <= 32'd0;
        end else begin
            cmd_search_start <= 1'b0;
            cmd_dma_start    <= 1'b0;

            if (cmd_wr_start) cmd_search_start <= 1'b1;
            if (cmd_wr_dma)   cmd_dma_start    <= 1'b1;

            if (wr) begin
                case (ridx)
                `CSR_IDX_CONTROL: begin
                    cfg_auto_shot      <= pwdata[0];
                    cfg_burst_enable   <= pwdata[1];
                    cfg_predicate_mode <= pwdata[3:2];
                end
                `CSR_IDX_J_TARGET   : cfg_j_target    <= pwdata[6:0];
                `CSR_IDX_THRESHOLD_A: cfg_threshold_a <= pwdata[15:0];
                `CSR_IDX_THRESHOLD_B: cfg_threshold_b <= pwdata[15:0];
                `CSR_IDX_DATA_COUNT : cfg_data_count  <= pwdata[14:0];
                `CSR_IDX_SHOT_CAP   : cfg_shot_cap    <= pwdata[15:0];
                `CSR_IDX_SEED_J     : cfg_seed_j      <= pwdata;
                `CSR_IDX_SEED_MEAS  : cfg_seed_meas   <= pwdata;
                `CSR_IDX_ENUM_CFG   : begin
                    cfg_enum_enable       <= pwdata[0];
                    cfg_fail_repeat_limit <= pwdata[7:4];
                end
                `CSR_IDX_DATA_ADDR  : cfg_data_addr   <= pwdata;
                default             : ;   // W1P 와 RO 는 저장하지 않습니다
                endcase
            end
        end
    end

    //-----------------------------------------------------------------
    // STATUS 조립
    //-----------------------------------------------------------------
    wire [31:0] status_word;

    assign status_word[`BBHT_ST_BUSY]              = st_busy;
    assign status_word[`BBHT_ST_LOAD_BUSY]         = st_load_busy;
    assign status_word[`BBHT_ST_DONE_STICKY]       = done_sticky;
    assign status_word[`BBHT_ST_RESULT_VALID]      = st_result_valid;
    assign status_word[`BBHT_ST_CONFIG_ERROR]      = st_config_error;
    assign status_word[`BBHT_ST_SHOT_LIMIT]        = st_shot_limit;
    assign status_word[`BBHT_ST_BUDGET_LIMIT]      = st_budget_limit;
    assign status_word[`BBHT_ST_AMP_OVERFLOW]      = st_amp_overflow;
    assign status_word[`BBHT_ST_ZERO_WEIGHT_ERROR] = st_zero_weight_error;
    assign status_word[`BBHT_ST_LOAD_ERROR]        = st_load_error;
    assign status_word[`BBHT_ST_ENUM_DONE]         = enum_done_sticky;
    assign status_word[`BBHT_ST_FIFO_EMPTY]        = res_empty;
    assign status_word[31:12]                      = 20'd0;

    //-----------------------------------------------------------------
    // 읽기 먹스
    //
    // 명령형 레지스터는 읽으면 0 입니다. default 가 그것을 담당합니다.
    //-----------------------------------------------------------------
    always @* begin
        case (ridx)
        `CSR_IDX_CONTROL      : prdata = {28'd0, cfg_predicate_mode,
                                           cfg_burst_enable, cfg_auto_shot};
        `CSR_IDX_J_TARGET     : prdata = {25'd0, cfg_j_target};
        `CSR_IDX_THRESHOLD_A  : prdata = {16'd0, cfg_threshold_a};
        `CSR_IDX_THRESHOLD_B  : prdata = {16'd0, cfg_threshold_b};
        `CSR_IDX_DATA_COUNT   : prdata = {17'd0, cfg_data_count};
        `CSR_IDX_SHOT_CAP     : prdata = {16'd0, cfg_shot_cap};
        `CSR_IDX_SEED_J       : prdata = cfg_seed_j;
        `CSR_IDX_SEED_MEAS    : prdata = cfg_seed_meas;
        `CSR_IDX_STATUS       : prdata = status_word;
        `CSR_IDX_RESULT_INDEX : prdata = {18'd0, st_result_index};
        `CSR_IDX_TRIAL_COUNT  : prdata = st_trial_count;
        `CSR_IDX_L_BBHT       : prdata = st_l_bbht;
        `CSR_IDX_ACTUAL_ITER  : prdata = st_actual_iter;
        `CSR_IDX_CYCLE_COUNT  : prdata = st_cycle_count;
        `CSR_IDX_ENUM_CFG     : prdata = {24'd0, cfg_fail_repeat_limit,
                                           3'd0, cfg_enum_enable};
        `CSR_IDX_FIFO_DATA    : prdata = {18'd0, res_dout};
        `CSR_IDX_FIFO_COUNT   : prdata = {23'd0, res_count};
        `CSR_IDX_FOUND_COUNT  : prdata = {17'd0, st_found_count};
        `CSR_IDX_CONSEC_FAIL  : prdata = {28'd0, st_consecutive_fail};
        `CSR_IDX_MAX_FIFO_OCC : prdata = {23'd0, st_max_fifo_occupancy};
        `CSR_IDX_FIFO_STALL   : prdata = st_fifo_stall_cycles;
        `CSR_IDX_DATA_ADDR    : prdata = cfg_data_addr;
        `CSR_IDX_DMA_STATUS   : prdata = {24'd0, dma_status};

        `CSR_IDX_POLICY_CYCLES_TOTAL      : prdata = tm_policy_cycles_total;
        `CSR_IDX_POLICY_STALL_CYCLES      : prdata = tm_policy_stall_cycles;
        `CSR_IDX_POLICY_ACTIONS_EVAL      : prdata = tm_policy_actions_eval;
        `CSR_IDX_POLICY_MEMO_HIT          : prdata = tm_policy_memo_hit;
        `CSR_IDX_POLICY_MEMO_MISS         : prdata = tm_policy_memo_miss;
        `CSR_IDX_POLICY_MAX_LATENCY       : prdata = tm_policy_max_latency;
        `CSR_IDX_PLAN_FIFO_LEVEL          : prdata = {29'd0, tm_plan_fifo_level};
        `CSR_IDX_PLAN_FIFO_HIGHWATER      : prdata = {29'd0, tm_plan_fifo_highwater};
        `CSR_IDX_PLAN_FIFO_EMPTY_DEMAND   : prdata = tm_plan_fifo_empty_demand;
        `CSR_IDX_PLAN_FIFO_HIT_COUNT      : prdata = tm_plan_fifo_hit_count;
        `CSR_IDX_PLAN_FIFO_MISMATCH_COUNT : prdata = tm_plan_fifo_mismatch_count;
        `CSR_IDX_POLICY_COLD_SOLVE_COUNT  : prdata = tm_policy_cold_solve_count;
        `CSR_IDX_POLICY_SPEC_SOLVE_COUNT  : prdata = tm_policy_spec_solve_count;

        default : prdata = 32'd0;
        endcase
    end

endmodule
