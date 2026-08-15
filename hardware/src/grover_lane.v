//=====================================================================
// grover_lane.v -- 부호 반전 + 확산, 레인 하나 (소유자 C)
//
// 계약 4.2. 조합논리입니다. P 벌이 병렬로 놓입니다.
//
//   1패스 : amp_out = (amp_in ^ {DW{hit}}) + hit     조건부 2의 보수
//           amp_tree 로 같은 값을 내보내 adder_tree 가 합을 만듭니다.
//           평균은 오라클을 적용한 뒤의 진폭에서 구합니다.
//   2패스 : amp_out = sat(two_mean - amp_in)
//           TMW(20비트)로 계산한 뒤 DW(18비트)로 대칭 포화시킵니다.
//
// 곱셈기가 하나도 없습니다. 확산이 필요로 하는 것은 평균의 두 배뿐이고
// 그 두 배는 누산기를 n-1 만큼 오른쪽으로 미는 것으로 얻습니다(two_mean_calc).
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_lane (
    input  wire                        phase,      // 0 = 1패스, 1 = 2패스
    input  wire                        hit,        // predicate 출력
    input  wire signed [`GP_DW-1:0]    amp_in,     // amp_mem 읽기
    input  wire signed [`GP_TMW-1:0]   two_mean,   // 2패스에서만 유효
    output wire signed [`GP_DW-1:0]    amp_out,    // amp_mem 되쓰기
    output wire signed [`GP_DW-1:0]    amp_tree,   // adder_tree 로 (= 부호 반전 결과)
    output wire                        sat         // 포화 발생
);
    localparam DW  = `GP_DW;
    localparam TMW = `GP_TMW;

    localparam signed [TMW-1:0] SAT_HI = `GP_AMP_MAX;  // +2.0 직전
    localparam signed [TMW-1:0] SAT_LO = `GP_AMP_MIN;  // 대칭 포화 (계약 1.2)

    // ── 1패스: hit 이면 2의 보수, 아니면 항등 ────────────────────────
    wire [DW-1:0] flipped = (amp_in ^ {DW{hit}}) + {{(DW-1){1'b0}}, hit};

    // ── 2패스: 평균 둘레의 반사 ──────────────────────────────────────
    wire signed [TMW-1:0] amp_ext = {{(TMW-DW){amp_in[DW-1]}}, amp_in};
    wire signed [TMW-1:0] diff    = two_mean - amp_ext;

    wire ovf_hi = (diff > SAT_HI);
    wire ovf_lo = (diff < SAT_LO);

    wire signed [DW-1:0] diff_sat = ovf_hi ? SAT_HI[DW-1:0] :
                                    ovf_lo ? SAT_LO[DW-1:0] : diff[DW-1:0];

    assign amp_out  = phase ? diff_sat : $signed(flipped);
    assign amp_tree = $signed(flipped);
    // 1패스는 대칭 포화 덕에 부호 반전이 언제나 정확하므로 포화가 나지 않습니다.
    assign sat      = phase & (ovf_hi | ovf_lo);
endmodule
