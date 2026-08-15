//=====================================================================
// grover_amp_mem.v -- 진폭 32뱅크 (소유자 C)
//
// 32뱅크 x 1024 x 18b = RAMB18 32개 = BRAM36 16개.
//
// 계약 4.11 과의 차이 하나를 여기에 적어 둡니다. 계약은 이 메모리를
// "단일 포트(읽기/쓰기 배타)"에 주소 하나(addr)로 적었지만, 같은 절 4.6 의
// 파이프라인은 같은 사이클에 주소 k 를 읽으면서 주소 k-1 을 되쓰라고
// 요구합니다. 주소가 둘 필요하므로 여기서는 simple dual port 로 둡니다 --
// 읽기 포트(addr/re/rdata)와 쓰기 포트(waddr/we/wdata)를 따로 냅니다.
// Xilinx RAMB18 은 원래 true dual port 라 포트를 하나 더 써도 BRAM 개수가
// 늘지 않으므로 6.4절 자원 예산은 그대로입니다. 계약 4.12 의 주소 먹스는
// 읽기 포트에 그대로 적용되고, 측정 중 amp_we=0 규칙도 그대로입니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_amp_mem (
    input  wire                        clk,
    // 읽기 포트 -- 반복(ctrl_fsm)과 측정(born_sampler)이 먹스로 나눠 씁니다
    input  wire [`GP_AW-1:0]           raddr,
    input  wire                        re,
    output wire [`GP_P*`GP_DW-1:0]     rdata,
    // 쓰기 포트 -- INIT · 1패스 · 2패스만 씁니다. 측정은 절대 쓰지 않습니다
    input  wire [`GP_AW-1:0]           waddr,
    input  wire                        we,
    input  wire [`GP_P*`GP_DW-1:0]     wdata
);
    localparam P     = `GP_P;
    localparam DW    = `GP_DW;
    localparam DEPTH = `GP_DEPTH;

    genvar b;
    generate
        for (b = 0; b < P; b = b + 1) begin : g_bank
            (* ram_style = "block" *) reg [DW-1:0] mem [0:DEPTH-1];
            reg [DW-1:0] rd;
            // 포트 A 읽기 / 포트 B 쓰기. 배열에 리셋을 걸지 않습니다 --
            // 걸면 BRAM 추론이 깨지고 32뱅크가 LUTRAM 으로 샙니다.
            always @(posedge clk) if (re) rd <= mem[raddr];
            always @(posedge clk) if (we) mem[waddr] <= wdata[b*DW +: DW];
            assign rdata[b*DW +: DW] = rd;
        end
    endgenerate
endmodule
