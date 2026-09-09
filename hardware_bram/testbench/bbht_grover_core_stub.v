//=====================================================================
// bbht_grover_core_stub.v -- Main IP 자리 채우개 (시뮬 전용)
//
// **이것은 알고리즘이 아닙니다.** PJK 의 Main IP 소스가 아직 이쪽 트리에
// 없어서, 통신 계층(mmio / loader / wrapper)을 단독으로 돌려 보기 위해
// 인수인계 §3.4 의 포트 계약만 그대로 갖춘 껍데기를 둔 것입니다.
//
// 하는 일은 셋뿐입니다.
//   1. loader 가 밀어 넣는 16비트 쓰기를 메모리에 받습니다
//   2. start 가 들어오면 data[0..data_count-1] 을 앞에서부터 훑어
//      술어를 만족하는 인덱스를 찾습니다 (그로버가 아니라 선형 스캔)
//   3. 열거 모드면 만족하는 인덱스를 전부 Result FIFO 에 넣습니다
//
// 그래서 이 스텁으로 검증되는 것은 **통신 계층의 계약 준수**뿐입니다.
// 탐색 결과의 알고리즘적 정확성은 PJK 의 실물 IP 로만 검증됩니다.
// 술어 판정과 loader 매핑은 실물과 같아야 하므로 그 둘만 진짜로 맞춥니다.
//=====================================================================
`timescale 1ns/1ps
`include "bbht_grover_csr.vh"

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
    output reg         load_busy,

    // Result FIFO
    input  wire        res_pop,
    output wire [13:0] res_dout,
    output wire        res_empty,
    output wire [8:0]  res_count,

    // Execution
    output wire        busy,
    output reg         done,
    output reg         result_valid,
    output reg  [13:0] result_index,

    // Enumeration
    output reg         enum_done,
    output reg  [14:0] found_count,
    output reg  [3:0]  consecutive_fail_count,
    output reg  [8:0]  max_fifo_occupancy,
    output reg  [31:0] fifo_stall_cycles,

    // Status (sticky)
    output reg         config_error,
    output reg         shot_limit,
    output reg         budget_limit,
    output reg         amp_overflow,
    output reg         zero_weight_error,
    output reg         load_error,

    // Counters
    output reg  [31:0] trial_count,
    output reg  [31:0] L_BBHT,
    output reg  [31:0] actual_grover_iterations,
    output reg  [31:0] cycle_count,

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

    //-----------------------------------------------------------------
    // 데이터 메모리. loader 매핑이 맞는지 확인하는 것이 목적이므로 실물과
    // 같은 16비트 signed 배열입니다.
    //-----------------------------------------------------------------
    reg signed [15:0] mem [0:`BBHT_N_ENTRIES-1];

    //-----------------------------------------------------------------
    // 적재
    //-----------------------------------------------------------------
    always @(posedge clk or negedge rstnn) begin
        if (!rstnn) begin
            load_busy  <= 1'b0;
            load_error <= 1'b0;
        end else begin
            if (load_start) load_busy <= 1'b1;
            if (load_done)  load_busy <= 1'b0;
            if (data_wr_en) mem[data_wr_addr] <= data_wr_data;
        end
    end

    //-----------------------------------------------------------------
    // 술어. 실물과 같은 규약이어야 합니다.
    //   LT    data <  A
    //   GT    data >  A
    //   EQ    data == A
    //   RANGE A <  data <  B   (열린구간)
    //-----------------------------------------------------------------
    reg signed [15:0] probe;
    reg               hit;

    always @* begin
        case (predicate_mode)
        `BBHT_PRED_LT    : hit = (probe <  threshold_a);
        `BBHT_PRED_GT    : hit = (probe >  threshold_a);
        `BBHT_PRED_EQ    : hit = (probe == threshold_a);
        `BBHT_PRED_RANGE : hit = (probe >  threshold_a) && (probe < threshold_b);
        default          : hit = 1'b0;
        endcase
    end

    //-----------------------------------------------------------------
    // Result FIFO (14비트 x 256, 실물과 같은 깊이)
    //-----------------------------------------------------------------
    reg [13:0] fifo [0:255];
    reg [8:0]  fifo_wptr, fifo_rptr;
    wire [8:0] occ = fifo_wptr - fifo_rptr;

    assign res_count = occ;
    assign res_empty = (occ == 9'd0);
    assign res_dout  = fifo[fifo_rptr[7:0]];

    //-----------------------------------------------------------------
    // 스캔 FSM
    //-----------------------------------------------------------------
    localparam S_IDLE = 2'd0, S_SCAN = 2'd1, S_FIN = 2'd2;

    reg [1:0]  state;
    reg [14:0] scan_idx;

    assign busy = (state != S_IDLE) | load_busy;

    integer i;

    always @(posedge clk or negedge rstnn) begin
        if (!rstnn) begin
            state                    <= S_IDLE;
            scan_idx                 <= 15'd0;
            done                     <= 1'b0;
            enum_done                <= 1'b0;
            result_valid             <= 1'b0;
            result_index             <= 14'd0;
            found_count              <= 15'd0;
            consecutive_fail_count   <= 4'd0;
            max_fifo_occupancy       <= 9'd0;
            fifo_stall_cycles        <= 32'd0;
            config_error             <= 1'b0;
            shot_limit               <= 1'b0;
            budget_limit             <= 1'b0;
            amp_overflow             <= 1'b0;
            zero_weight_error        <= 1'b0;
            trial_count              <= 32'd0;
            L_BBHT                   <= 32'd0;
            actual_grover_iterations <= 32'd0;
            cycle_count              <= 32'd0;
            fifo_wptr                <= 9'd0;
            fifo_rptr                <= 9'd0;
            probe                    <= 16'sd0;
        end else begin
            done <= 1'b0;

            if (res_pop && !res_empty)
                fifo_rptr <= fifo_rptr + 9'd1;

            case (state)
            S_IDLE: begin
                if (start) begin
                    // start 는 직전 실행의 결과와 카운터를 전부 지웁니다.
                    state                    <= S_SCAN;
                    scan_idx                 <= 15'd0;
                    result_valid             <= 1'b0;
                    result_index             <= 14'd0;
                    enum_done                <= 1'b0;
                    found_count              <= 15'd0;
                    consecutive_fail_count   <= 4'd0;
                    max_fifo_occupancy       <= 9'd0;
                    fifo_stall_cycles        <= 32'd0;
                    trial_count              <= 32'd0;
                    L_BBHT                   <= 32'd0;
                    actual_grover_iterations <= 32'd0;
                    cycle_count              <= 32'd0;
                    shot_limit               <= 1'b0;
                    budget_limit             <= 1'b0;
                    // fail_repeat_limit 0 은 설정 오류 (§1.2)
                    config_error             <= enum_enable && (fail_repeat_limit == 4'd0);
                    probe                    <= mem[0];
                end
            end

            S_SCAN: begin
                cycle_count <= cycle_count + 32'd1;

                if (config_error) begin
                    state <= S_FIN;
                end else if (scan_idx >= data_count) begin
                    state <= S_FIN;
                end else begin
                    if (hit) begin
                        trial_count              <= trial_count + 32'd1;
                        L_BBHT                   <= L_BBHT + 32'd1;
                        actual_grover_iterations <= actual_grover_iterations + 32'd1;

                        if (enum_enable) begin
                            if (occ != 9'd256) begin
                                fifo[fifo_wptr[7:0]] <= scan_idx[13:0];
                                fifo_wptr            <= fifo_wptr + 9'd1;
                                found_count          <= found_count + 15'd1;
                                if (occ + 9'd1 > max_fifo_occupancy)
                                    max_fifo_occupancy <= occ + 9'd1;
                            end else begin
                                fifo_stall_cycles <= fifo_stall_cycles + 32'd1;
                            end
                        end else begin
                            result_valid <= 1'b1;
                            result_index <= scan_idx[13:0];
                            found_count  <= 15'd1;
                            state        <= S_FIN;
                        end
                    end

                    scan_idx <= scan_idx + 15'd1;
                    probe    <= mem[scan_idx[13:0] + 14'd1];
                end
            end

            S_FIN: begin
                done  <= 1'b1;
                state <= S_IDLE;
                if (enum_enable) enum_done <= 1'b1;
                // 아무것도 못 찾았으면 상한 도달로 표시합니다.
                if (!result_valid && !enum_enable) shot_limit <= 1'b1;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

    //-----------------------------------------------------------------
    // 텔레메트리는 스텁에 없습니다. 0 이 나오는 것이 정상이고, 실물에서는
    // plan_fifo_mismatch_count 만 0 이어야 합니다.
    //-----------------------------------------------------------------
    assign policy_cycles_total      = 32'd0;
    assign policy_stall_cycles      = 32'd0;
    assign policy_actions_eval      = 32'd0;
    assign policy_memo_hit          = 32'd0;
    assign policy_memo_miss         = 32'd0;
    assign policy_max_latency       = 32'd0;
    assign plan_fifo_level          = 3'd0;
    assign plan_fifo_highwater      = 3'd0;
    assign plan_fifo_empty_demand   = 32'd0;
    assign plan_fifo_hit_count      = 32'd0;
    assign plan_fifo_mismatch_count = 32'd0;
    assign policy_cold_solve_count  = 32'd0;
    assign policy_spec_solve_count  = 32'd0;

endmodule
