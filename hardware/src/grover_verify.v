//=====================================================================
// grover_verify.v -- 후보 1칸 고전 검증 (소유자 B)
//
// 계약 4.8. grover_predicate 를 한 벌 더 인스턴스화합니다. 오라클과 완전히
// 같은 식이고 적용 범위만 다릅니다 -- 오라클은 N칸, 검증은 1칸.
//
// 측정이 돌려준 후보가 진짜 해인지 고전적으로 확인하는 자리입니다.
// 이것이 있어서 진폭이 조금 틀려도 "틀린 답"이 나오지 않고 "실패한 샷"이
// 되며, BBHT 가 다음 샷으로 넘어갑니다.
//
// 주소를 낸 다음 사이클에 값이 오므로 start 에서 done 까지 2사이클입니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_verify (
    input  wire                    clk,
    input  wire                    rstn,
    input  wire                    vfy_start,
    input  wire [`GP_NB-1:0]       cand,
    // 술어 설정 (CSR 에서 옴)
    input  wire [1:0]              mode,
    input  wire signed [`GP_W-1:0] thr_a,
    input  wire signed [`GP_W-1:0] thr_b,
    // data_mem / mask_mem 1칸 포트
    output wire [`GP_NB-1:0]       one_addr,
    input  wire signed [`GP_W-1:0] one_rdata,
    input  wire                    mask_bit,
    // 계약 2절 핸드셰이크
    output wire                    vfy_busy,
    output reg                     vfy_done,
    output reg                     vfy_hit
);
    localparam S_IDLE = 2'd0, S_EVAL = 2'd1;

    reg [1:0]        st;
    reg [`GP_NB-1:0] cand_r;

    // start 사이클에 곧바로 주소를 내밀어야 다음 사이클에 값이 옵니다.
    assign one_addr = vfy_start ? cand : cand_r;

    wire pred_hit;
    grover_predicate u_pred (
        .mode  (mode),
        .value (one_rdata),
        .thr_a (thr_a),
        .thr_b (thr_b),
        .found (mask_bit),
        .hit   (pred_hit)
    );

    always @(posedge clk) begin
        if (!rstn) begin
            st       <= S_IDLE;
            cand_r   <= {`GP_NB{1'b0}};
            vfy_done <= 1'b0;
            vfy_hit  <= 1'b0;
        end else begin
            vfy_done <= 1'b0;
            case (st)
                S_IDLE : if (vfy_start) begin
                    cand_r <= cand;
                    st     <= S_EVAL;
                end
                S_EVAL : begin
                    vfy_hit  <= pred_hit;
                    vfy_done <= 1'b1;
                    st       <= S_IDLE;
                end
                default : st <= S_IDLE;
            endcase
        end
    end

    assign vfy_busy = (st != S_IDLE);
endmodule
