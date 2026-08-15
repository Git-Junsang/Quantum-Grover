//=====================================================================
// grover_data_mem.v -- 탐색 대상 데이터 32뱅크 (소유자 C)
//
// 계약 4.11. 32뱅크 x 1024 x 16b = RAMB18 32개 = BRAM36 16개. true dual port.
//   포트 A : ctrl_fsm 의 병렬 스트리밍 읽기 (뱅크 내 주소 AW)
//   포트 B : 적재 쓰기(ahb_master / data_gen)와 검증 1칸 읽기(verify)
//
// 포트 B 의 두 용도는 시간적으로 겹치지 않습니다 -- 적재 중에는 실행을
// 받지 않는다는 것이 통신 규약 4.4 이고, 검증은 실행 중에만 일어납니다.
// 그래서 먹스 하나로 충분합니다.
//
// 인덱스 -> 뱅크 사상은 "하위 LOGP 비트가 뱅크, 상위가 뱅크 내 주소" 입니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_data_mem (
    input  wire                        clk,
    // 포트 A -- 병렬 읽기
    input  wire [`GP_AW-1:0]           addr,
    input  wire                        re,
    output wire [`GP_P*`GP_W-1:0]      rdata,
    // 포트 B -- 적재 쓰기
    input  wire [`GP_NB-1:0]           wr_addr,
    input  wire                        we,
    input  wire signed [`GP_W-1:0]     wdata,
    // 포트 B -- 검증 1칸 읽기
    input  wire [`GP_NB-1:0]           one_addr,
    output wire signed [`GP_W-1:0]     one_rdata
);
    localparam P     = `GP_P;
    localparam W     = `GP_W;
    localparam AW    = `GP_AW;
    localparam LOGP  = `GP_LOGP;
    localparam DEPTH = `GP_DEPTH;

    wire [LOGP-1:0] wr_bank = wr_addr[LOGP-1:0];
    wire [AW-1:0]   wr_row  = wr_addr[`GP_NB-1:LOGP];
    wire [LOGP-1:0] one_bank = one_addr[LOGP-1:0];
    wire [AW-1:0]   one_row  = one_addr[`GP_NB-1:LOGP];

    // 포트 B 주소 먹스: 쓸 때는 적재 주소, 그 외에는 검증 주소.
    wire [AW-1:0] pb_addr = we ? wr_row : one_row;

    wire [W-1:0] pb_rd [0:P-1];

    genvar b;
    generate
        for (b = 0; b < P; b = b + 1) begin : g_bank
            (* ram_style = "block" *) reg [W-1:0] mem [0:DEPTH-1];
            reg [W-1:0] rd_a;
            reg [W-1:0] rd_b;
            wire bank_we = we && (wr_bank == b[LOGP-1:0]);
            always @(posedge clk) begin
                if (re) rd_a <= mem[addr];          // 포트 A: 읽기 전용
                if (bank_we) mem[pb_addr] <= wdata; // 포트 B: 쓰기
                rd_b <= mem[pb_addr];               // 포트 B: 읽기 (상시)
            end
            assign rdata[b*W +: W] = rd_a;
            assign pb_rd[b] = rd_b;
        end
    endgenerate

    // 검증은 주소를 낸 다음 사이클에 값을 받습니다. 뱅크 선택은 그 사이에
    // 바뀌지 않으므로(verify 가 cand 를 붙들고 있음) 레지스터를 두지 않습니다.
    reg [LOGP-1:0] one_bank_d;
    always @(posedge clk) one_bank_d <= one_bank;
    assign one_rdata = pb_rd[one_bank_d];
endmodule
