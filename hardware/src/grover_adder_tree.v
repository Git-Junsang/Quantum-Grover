//=====================================================================
// grover_adder_tree.v -- P입력 log2(P)단 이진 트리 (소유자 C)
//
// 계약 4.3. 짝짓기 순서가 계약 항목 6 으로 동결되어 있습니다.
//   1단 (0,1)(2,3)...(30,31)   2단 (01,23)(45,67)...   5단까지 같은 규칙
// 골든 모델이 정확히 같은 순서로 더해야 float 참조와 마지막 비트가 맞습니다.
//
// 구현 노트: 단마다 폭을 1비트씩 늘리는 대신 전 단을 PSW(=DW+LOGP) 폭으로
// 부호확장해 더합니다. PSW 가 최악의 경우를 정확히 담는 폭이라 중간에서
// 넘칠 수 없고, 결과는 폭을 키워 가며 더한 것과 비트 단위로 같습니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_adder_tree (
    input  wire [`GP_P*`GP_DW-1:0]  din,      // 레인 0 이 최하위 비트 쪽
    output wire signed [`GP_PSW-1:0] partial
);
    localparam P    = `GP_P;
    localparam DW   = `GP_DW;
    localparam PSW  = `GP_PSW;
    localparam LOGP = `GP_LOGP;

    // node[s*P + i] = s단의 i번째 마디. 0단이 잎입니다.
    wire signed [PSW-1:0] node [0:(LOGP+1)*P-1];

    genvar s, i;
    generate
        for (i = 0; i < P; i = i + 1) begin : g_leaf
            wire signed [DW-1:0] leaf = din[i*DW +: DW];
            assign node[i] = {{(PSW-DW){leaf[DW-1]}}, leaf};
        end
        for (s = 1; s <= LOGP; s = s + 1) begin : g_stage
            for (i = 0; i < (P >> s); i = i + 1) begin : g_node
                assign node[s*P + i] = node[(s-1)*P + 2*i] + node[(s-1)*P + 2*i + 1];
            end
        end
    endgenerate

    assign partial = node[LOGP*P];
endmodule
