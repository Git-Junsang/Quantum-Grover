//=====================================================================
// grover_mask_mem.v -- 열거 마스크 (소유자 B)
//
// 계약 4.11. 1024 x 32b = RAMB18 2개 = BRAM36 1개.
// 한 워드가 한 행(row)의 32뱅크분 found 비트를 담습니다. 비트 b 가 뱅크 b.
//
//   포트 A : 오라클이 쓰는 병렬 읽기 (addr -> rdata[31:0])
//   포트 B : 그 밖의 전부 -- 검증 1비트 읽기 · set 의 read-modify-write ·
//            mclr 전체 스윕. BRAM 은 비트 단위 쓰기 인에이블이 없으므로
//            해 하나를 표시하는 set 은 읽고 고쳐 되쓰는 2사이클입니다.
//
// mclr 은 즉시가 아니라 DEPTH 사이클 스윕이고 mclr_busy/mclr_done 으로
// 알립니다. set 은 실행이 멈춘 사이(검증 성공 직후)에만 들어오므로 별도
// busy 를 내지 않고, shot_fsm 이 3사이클을 비워 둡니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_mask_mem (
    input  wire                clk,
    input  wire                rstn,
    // 포트 A -- 오라클 병렬 읽기
    input  wire [`GP_AW-1:0]   addr,
    input  wire                re,
    output wire [`GP_P-1:0]    rdata,
    // 포트 B -- 해 하나 표시
    input  wire                set,
    input  wire [`GP_NB-1:0]   set_idx,
    // 포트 B -- 검증 1비트 읽기
    input  wire [`GP_NB-1:0]   one_addr,
    output wire                one_bit,
    // 포트 B -- 전체 클리어
    input  wire                mclr_start,
    output wire                mclr_busy,
    output reg                 mclr_done
);
    localparam P     = `GP_P;
    localparam AW    = `GP_AW;
    localparam LOGP  = `GP_LOGP;
    localparam DEPTH = `GP_DEPTH;

    (* ram_style = "block" *) reg [P-1:0] mem [0:DEPTH-1];

    // ── 포트 A ───────────────────────────────────────────────────────
    reg [P-1:0] rd_a;
    always @(posedge clk) if (re) rd_a <= mem[addr];
    assign rdata = rd_a;

    // ── 포트 B 상태기: IDLE / SET 읽기 / SET 쓰기 / 클리어 스윕 ──────
    localparam B_IDLE = 2'd0, B_SET_RD = 2'd1, B_SET_WR = 2'd2, B_CLR = 2'd3;

    reg [1:0]      bst;
    reg [AW-1:0]   sweep;
    reg [AW-1:0]   set_row;
    reg [LOGP-1:0] set_bank;
    reg [P-1:0]    rd_b;

    wire [AW-1:0]   one_row  = one_addr[`GP_NB-1:LOGP];
    wire [LOGP-1:0] one_bank = one_addr[LOGP-1:0];

    // 포트 B 가 이번 사이클에 실제로 볼 주소.
    reg [AW-1:0] pb_addr;
    always @* begin
        case (bst)
            B_SET_RD : pb_addr = set_row;
            B_SET_WR : pb_addr = set_row;
            B_CLR    : pb_addr = sweep;
            default  : pb_addr = one_row;
        endcase
    end

    wire pb_we = (bst == B_SET_WR) || (bst == B_CLR);
    wire [P-1:0] pb_wdata = (bst == B_CLR) ? {P{1'b0}}
                                           : (rd_b | ({{(P-1){1'b0}}, 1'b1} << set_bank));

    always @(posedge clk) begin
        rd_b <= mem[pb_addr];
        if (pb_we) mem[pb_addr] <= pb_wdata;
    end

    reg [LOGP-1:0] one_bank_d;
    always @(posedge clk) one_bank_d <= one_bank;
    assign one_bit = rd_b[one_bank_d];

    always @(posedge clk) begin
        if (!rstn) begin
            bst       <= B_IDLE;
            sweep     <= {AW{1'b0}};
            mclr_done <= 1'b0;
        end else begin
            mclr_done <= 1'b0;
            case (bst)
                B_IDLE : begin
                    if (mclr_start) begin
                        sweep <= {AW{1'b0}};
                        bst   <= B_CLR;
                    end else if (set) begin
                        set_row  <= set_idx[`GP_NB-1:LOGP];
                        set_bank <= set_idx[LOGP-1:0];
                        bst      <= B_SET_RD;
                    end
                end
                // 읽기를 낸 사이클. 다음 사이클에 rd_b 가 유효해집니다.
                B_SET_RD : bst <= B_SET_WR;
                B_SET_WR : bst <= B_IDLE;
                B_CLR : begin
                    if (sweep == DEPTH[AW-1:0] - 1'b1) begin
                        bst       <= B_IDLE;
                        mclr_done <= 1'b1;
                    end
                    sweep <= sweep + 1'b1;
                end
                default : bst <= B_IDLE;
            endcase
        end
    end

    assign mclr_busy = (bst != B_IDLE);
endmodule
