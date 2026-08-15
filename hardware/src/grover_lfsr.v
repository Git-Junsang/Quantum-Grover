//=====================================================================
// grover_lfsr.v -- 난수원 (소유자 D)
//
// !! 잠정 구현입니다 !!
// 계약 9절(난수 소비 규약)이 아직 미정이라 다항식 · 시드 출처 · 샷당 추출
// 횟수 · 범위 매핑이 확정되지 않았습니다. 여기 박아 둔 다항식은 자리를
// 막아 두기 위한 것이고, 규약이 정해지면 이 파일과 software/golden/bbht.py
// 의 lfsr32() 를 같이 고쳐야 합니다. 어긋난 채로 두면 골든 모델과 RTL 이
// 영원히 비트정확이 되지 않습니다.
//
// 현재: 32비트 최대길이 LFSR, x^32 + x^22 + x^2 + x + 1 (탭 31,21,1,0).
// rnd 는 현재 상태를 조합으로 내보내고, draw 펄스가 클럭 경계에서 상태를
// 한 칸 전진시킵니다. 즉 사이클 t 에 draw 를 올리면 t+1 에 새 값이 보입니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_lfsr (
    input  wire        clk,
    input  wire        rstn,
    input  wire        seed_we,
    input  wire [31:0] seed,
    input  wire        draw,
    output wire [31:0] rnd
);
    localparam [31:0] SEED_RESET = 32'hACE1_2345;   // 잠정

    reg [31:0] state;

    wire fb = state[31] ^ state[21] ^ state[1] ^ state[0];

    always @(posedge clk) begin
        if (!rstn)          state <= SEED_RESET;
        else if (seed_we)   state <= (seed == 32'd0) ? SEED_RESET : seed;
        else if (draw)      state <= {state[30:0], fb};
    end

    assign rnd = state;
endmodule
