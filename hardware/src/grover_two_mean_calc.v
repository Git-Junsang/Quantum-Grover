//=====================================================================
// grover_two_mean_calc.v -- 배럴 시프터 + round-half-to-even (소유자 C)
//
// 계약 4.5. 확산이 필요로 하는 값은 평균의 두 배이므로 누산기를 n-1 만큼
// 산술 우시프트하는 것으로 끝납니다. 곱셈기도 나눗셈기도 쓰지 않습니다.
//
// >>> n 한 뒤 <<< 1 로 되미는 2단 구현은 금지입니다. 떨어져 나간 최하위
// 비트가 0 으로 채워지고 반올림 지점이 두 곳으로 갈라져 골든 모델과 영원히
// 어긋납니다. 한 반복에서 소수부가 깎이는 곳은 여기 한 순간뿐이고,
// round-half-to-even 이 적용되는 자리도 오직 여기입니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_two_mean_calc (
    input  wire signed [`GP_ACCW-1:0]  total,
    input  wire [4:0]                  n_qubits,
    output wire signed [`GP_TMW-1:0]   two_mean
);
    localparam ACCW = `GP_ACCW;
    localparam TMW  = `GP_TMW;

    wire [4:0] K = n_qubits - 5'd1;          // n=15 -> 14

    wire signed [ACCW-1:0] q     = total >>> K;
    wire [ACCW-1:0]        tot_u = total;

    // 잘려 나가는 비트들. K=0 이면 자를 것이 없어 반올림도 없습니다.
    wire rbit = (K == 5'd0) ? 1'b0 : tot_u[K - 5'd1];

    wire [ACCW-1:0] one = {{(ACCW-1){1'b0}}, 1'b1};
    wire [ACCW-1:0] mask_lo = (K >= 5'd2) ? ((one << (K - 5'd1)) - one)
                                          : {ACCW{1'b0}};
    wire sticky = |(tot_u & mask_lo);

    // 정확히 절반이면 짝수 쪽으로. 그 외에는 rbit 만으로 올림 결정.
    wire inc = rbit & (sticky | q[0]);

    wire signed [ACCW-1:0] tm = q + {{(ACCW-1){1'b0}}, inc};

    // 2*mean 의 이론 상한이 4.0 이라 TMW 안에 언제나 들어옵니다.
    assign two_mean = tm[TMW-1:0];
endmodule
