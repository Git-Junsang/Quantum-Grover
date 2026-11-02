//=====================================================================
// ahb_sram_model.v -- AHB-Lite 슬레이브 SRAM 모델 (시뮬 전용)
//
// bbht_ahb_loader 를 돌려 보기 위한 System SRAM 흉내입니다. RVX 의 실제
// 시스템 SRAM 이 아니라, 주소 위상 -> 데이터 위상 타이밍만 맞춘 모델입니다.
//
// WAIT_CYCLES 로 hready 를 늦출 수 있습니다. loader 가 shready 를 제대로
// 기다리는지(주소 위상을 놓치지 않는지) 확인하는 데 씁니다.
//=====================================================================
`timescale 1ns/1ps

module ahb_sram_model #(
    parameter [31:0] BASE_ADDR   = 32'hE000_0000,
    parameter integer WORDS      = 8192,
    parameter integer WAIT_CYCLES = 0
) (
    input  wire        clk,
    input  wire        rstnn,

    input  wire [31:0] haddr,
    input  wire [1:0]  htrans,
    input  wire        hwrite,
    input  wire [2:0]  hsize,
    input  wire [2:0]  hburst,
    input  wire [31:0] hwdata,
    output reg         hready,
    output reg         hresp,
    output reg  [31:0] hrdata,

    // 테스트벤치가 직접 채워 넣는 뒷문
    input  wire        bk_we,
    input  wire [31:0] bk_addr,
    input  wire [31:0] bk_data
);
    localparam [1:0] TRANS_IDLE = 2'b00;

    reg [31:0] mem [0:WORDS-1];

    // 주소 위상을 데이터 위상으로 넘기는 파이프
    reg        d_valid;
    reg [31:0] d_addr;
    reg [31:0] wait_cnt;

    wire [31:0] widx = (haddr - BASE_ADDR) >> 2;
    wire        in_range = (haddr >= BASE_ADDR) &&
                           (haddr < BASE_ADDR + WORDS*4);

    integer k;
    initial begin
        for (k = 0; k < WORDS; k = k + 1) mem[k] = 32'd0;
    end

    always @(posedge clk) begin
        if (bk_we) mem[(bk_addr - BASE_ADDR) >> 2] <= bk_data;
    end

    always @(posedge clk or negedge rstnn) begin
        if (!rstnn) begin
            hready   <= 1'b1;
            hresp    <= 1'b0;
            hrdata   <= 32'd0;
            d_valid  <= 1'b0;
            d_addr   <= 32'd0;
            wait_cnt <= 32'd0;
        end else begin
            hresp <= 1'b0;

            if (hready) begin
                // 주소 위상 수락
                d_valid <= (htrans != TRANS_IDLE);
                d_addr  <= haddr;
                if (htrans != TRANS_IDLE && WAIT_CYCLES != 0) begin
                    hready   <= 1'b0;
                    wait_cnt <= WAIT_CYCLES[31:0];
                end
            end else begin
                if (wait_cnt <= 32'd1) hready <= 1'b1;
                wait_cnt <= wait_cnt - 32'd1;
            end

            // 데이터 위상 응답
            if (d_valid) begin
                if (((d_addr - BASE_ADDR) >> 2) < WORDS)
                    hrdata <= mem[(d_addr - BASE_ADDR) >> 2];
                else begin
                    hrdata <= 32'hDEAD_BEEF;
                    hresp  <= 1'b1;
                end
            end
        end
    end

    // 사용하지 않는 입력. lint 침묵용입니다.
    wire _unused = &{1'b0, hwrite, hsize, hburst, hwdata, in_range, widx, 1'b0};

endmodule
