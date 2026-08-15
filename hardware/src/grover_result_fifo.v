//=====================================================================
// grover_result_fifo.v -- 열거 결과 큐 (소유자 D)
//
// 열거 모드에서 찾아낸 인덱스를 담아 두고 펌웨어가 하나씩 빼 갑니다.
//
// !! 깊이는 잠정값입니다 !!  해설서 17.8절 6번(열거 결과 반환 경로를
// FIFO 로 둘지 호스트가 M번 호출할지)과 7번(M_max)이 미정이라
// grover_param.vh 의 GP_RESQ_DEPTH 로 빼 두었습니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_result_fifo #(
    parameter DEPTH = `GP_RESQ_DEPTH
) (
    input  wire                clk,
    input  wire                rstn,
    input  wire                clr,
    input  wire                push,
    input  wire [`GP_NB-1:0]   din,
    input  wire                pop,
    output wire [`GP_NB-1:0]   dout,
    output wire                empty,
    output wire                full,
    output reg  [7:0]          count
);
    localparam AW = (DEPTH <= 2)  ? 1 :
                    (DEPTH <= 4)  ? 2 :
                    (DEPTH <= 8)  ? 3 :
                    (DEPTH <= 16) ? 4 :
                    (DEPTH <= 32) ? 5 :
                    (DEPTH <= 64) ? 6 : 8;

    reg [`GP_NB-1:0] mem [0:DEPTH-1];
    reg [AW-1:0]     wptr, rptr;

    assign empty = (count == 8'd0);
    assign full  = (count >= DEPTH[7:0]);
    assign dout  = mem[rptr];

    wire do_push = push && !full;
    wire do_pop  = pop  && !empty;

    always @(posedge clk) begin
        if (!rstn || clr) begin
            wptr  <= {AW{1'b0}};
            rptr  <= {AW{1'b0}};
            count <= 8'd0;
        end else begin
            if (do_push) begin
                mem[wptr] <= din;
                wptr <= (wptr == DEPTH[AW-1:0] - 1'b1) ? {AW{1'b0}} : wptr + 1'b1;
            end
            if (do_pop)
                rptr <= (rptr == DEPTH[AW-1:0] - 1'b1) ? {AW{1'b0}} : rptr + 1'b1;

            case ({do_push, do_pop})
                2'b10 : count <= count + 8'd1;
                2'b01 : count <= count - 8'd1;
                default : ;
            endcase
        end
    end
endmodule
