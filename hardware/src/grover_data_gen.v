//=====================================================================
// grover_data_gen.v -- 온칩 xorshift 데이터 생성기 (소유자 A)
//
// 실물 보드와 호스트 없이도 data_mem 을 채워 회귀를 돌리기 위한 경로입니다.
// AHB DMA 와 같은 쓰기 포트를 쓰고 data_sel 로 고릅니다. 시드가 같으면
// 언제나 같은 배열이 나오므로 테스트벤치와 골든 모델이 같은 수열을 재생할
// 수 있습니다 -- 그게 이 블록의 존재 이유입니다.
//
// xorshift32:  x ^= x<<13;  x ^= x>>17;  x ^= x<<5
// 한 번의 스텝이 32비트를 만들고 그것이 데이터 두 칸입니다. data_mem 의 적재
// 쓰기 포트가 16비트 하나라 두 사이클에 나눠 씁니다.
//
// 엔디안: 하위 16비트가 짝수 인덱스입니다. grover_ahb_master 가 SRAM 에서
// 읽어 올 때의 배치와 같은 규약이라, 두 적재 경로가 같은 배열을 만듭니다.
// 어긋나면 데이터가 통째로 뒤섞이고 골든과 영원히 안 맞습니다.
//
// words 는 CSR 의 data_words 이고 32비트 워드 수입니다 (데이터 칸은 그 두 배).
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_data_gen (
    input  wire                    clk,
    input  wire                    rstn,
    input  wire                    gen_start,
    input  wire [31:0]             seed,
    input  wire [31:0]             words,      // 32비트 워드 수
    output reg                     wr_en,
    output reg  [`GP_NB-1:0]       wr_addr,
    output reg  signed [`GP_W-1:0] wr_data,
    output wire                    gen_busy,
    output reg                     gen_done
);
    reg        run;
    reg        half;      // 0 = 하위 16비트, 1 = 상위 16비트
    reg [31:0] x;
    reg [31:0] cur;       // 이번 스텝이 만든 32비트
    reg [31:0] cidx;      // 데이터 칸 번호
    reg [31:0] ncidx;

    wire [31:0] x1 = x  ^ (x  << 13);
    wire [31:0] x2 = x1 ^ (x1 >> 17);
    wire [31:0] x3 = x2 ^ (x2 << 5);

    always @(posedge clk) begin
        if (!rstn) begin
            run      <= 1'b0;
            half     <= 1'b0;
            wr_en    <= 1'b0;
            gen_done <= 1'b0;
            x        <= 32'd1;
            cur      <= 32'd0;
            cidx     <= 32'd0;
            ncidx    <= 32'd0;
        end else begin
            wr_en    <= 1'b0;
            gen_done <= 1'b0;
            if (!run) begin
                if (gen_start && (words != 32'd0)) begin
                    x     <= (seed == 32'd0) ? 32'd1 : seed;
                    cidx  <= 32'd0;
                    ncidx <= words << 1;
                    half  <= 1'b0;
                    run   <= 1'b1;
                end
            end else begin
                wr_en   <= 1'b1;
                wr_addr <= cidx[`GP_NB-1:0];
                if (!half) begin
                    x       <= x3;
                    cur     <= x3;
                    wr_data <= x3[`GP_W-1:0];
                end else begin
                    wr_data <= cur[31:`GP_W];
                end
                half <= ~half;
                cidx <= cidx + 32'd1;
                if (cidx == ncidx - 32'd1) begin
                    run      <= 1'b0;
                    gen_done <= 1'b1;
                end
            end
        end
    end

    assign gen_busy = run;
endmodule
