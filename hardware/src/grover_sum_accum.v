//=====================================================================
// grover_sum_accum.v -- 패스 누산기 (소유자 C)
//
// 계약 4.4. adder_tree 의 부분합을 한 패스 동안 모읍니다.
// ACCW=35 는 진폭 크기 2^17 * N(=2^15) < 2^32 에 부호 1비트와 여유 2비트를
// 더한 값입니다. born_sampler 의 total(TOTW=51)과는 자릿수 계산이 처음부터
// 다른, 서로 다른 누산기입니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_sum_accum (
    input  wire                        clk,
    input  wire                        rstn,      // 동기 액티브 로우
    input  wire                        clear,
    input  wire                        en,
    input  wire signed [`GP_PSW-1:0]   partial,
    output reg  signed [`GP_ACCW-1:0]  total
);
    localparam PSW  = `GP_PSW;
    localparam ACCW = `GP_ACCW;

    wire signed [ACCW-1:0] partial_ext =
        {{(ACCW-PSW){partial[PSW-1]}}, partial};

    always @(posedge clk) begin
        if (!rstn)      total <= {ACCW{1'b0}};
        else if (clear) total <= {ACCW{1'b0}};   // clear 가 en 보다 우선입니다
        else if (en)    total <= total + partial_ext;
    end
endmodule
