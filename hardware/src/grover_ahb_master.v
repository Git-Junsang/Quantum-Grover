//=====================================================================
// grover_ahb_master.v -- 데이터 배열 DMA (소유자 A)
//
// 계약 4절 4번, 6.2절. AHB-Lite 마스터로 INCR16 버스트를 냅니다.
//
// 계약 6.2 는 HSIZE=4B 로 1 beat/cycle, 64 KB 에 16,384 사이클을 적었지만
// data_mem 의 적재 쓰기 포트가 16비트 하나(계약 4.11 에서 동결)라 32비트
// beat 하나를 받으면 쓰기가 두 사이클 걸립니다. 버스에 BUSY 를 끼워 넣는
// 대신 HSIZE 를 halfword 로 낮췄습니다 -- 코드가 훨씬 단순하고, 대가는
// 적재가 0.164 ms 에서 0.33 ms 로 늘어나는 것뿐입니다. UART 로 같은 배열을
// 보내면 5.7 초이므로 이 차이는 의미가 없습니다.
//
// 엔디안은 grover_data_gen 과 같은 규약입니다 -- 하위 16비트가 짝수 인덱스.
// halfword 전송이라 hrdata 의 어느 절반을 취할지가 haddr[1] 로 정해지고,
// 그것이 곧 이 규약입니다.
//
// 데이터 위상은 주소 위상보다 한 사이클 뒤에 오므로, 어느 인덱스에 써야
// 하는지를 파이프라인 레지스터로 따라 보냅니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_ahb_master (
    input  wire                    clk,
    input  wire                    rstn,
    // 제어
    input  wire                    load_start,
    input  wire [31:0]             src_addr,
    input  wire [31:0]             words,       // CSR data_words -- 32비트 워드 수
    output wire                    load_busy,
    output reg                     load_done,
    output reg                     load_err,
    // data_mem 적재 포트
    output reg                     wr_en,
    output reg  [`GP_NB-1:0]       wr_addr,
    output reg  signed [`GP_W-1:0] wr_data,
    // AHB-Lite 마스터
    output reg  [31:0]             haddr,
    output reg  [1:0]              htrans,
    output wire                    hwrite,
    output wire [2:0]              hsize,
    output wire [2:0]              hburst,
    output wire [3:0]              hprot,
    output wire [31:0]             hwdata,
    input  wire                    hready,
    input  wire                    hresp,
    input  wire [31:0]             hrdata
);
    localparam TRANS_IDLE   = 2'b00;
    localparam TRANS_NONSEQ = 2'b10;
    localparam TRANS_SEQ    = 2'b11;

    assign hwrite = 1'b0;
    assign hsize  = 3'b001;      // halfword
    assign hburst = 3'b111;      // INCR16
    assign hprot  = 4'b0011;     // data, privileged, non-bufferable, non-cacheable
    assign hwdata = 32'd0;

    reg        run;
    reg [31:0] issued;           // 주소 위상을 낸 워드 수
    reg [31:0] nwords;
    reg [3:0]  beat;
    // 데이터 위상 추적
    reg        d_valid;
    reg [`GP_NB-1:0] d_idx;
    reg        d_lane;           // 32비트 버스에서 어느 절반인가

    always @(posedge clk) begin
        if (!rstn) begin
            run       <= 1'b0;
            issued    <= 32'd0;
            nwords    <= 32'd0;
            beat      <= 4'd0;
            haddr     <= 32'd0;
            htrans    <= TRANS_IDLE;
            d_valid   <= 1'b0;
            d_idx     <= {`GP_NB{1'b0}};
            d_lane    <= 1'b0;
            wr_en     <= 1'b0;
            load_done <= 1'b0;
            load_err  <= 1'b0;
        end else begin
            wr_en     <= 1'b0;
            load_done <= 1'b0;

            if (!run) begin
                htrans <= TRANS_IDLE;
                if (load_start && (words != 32'd0)) begin
                    run      <= 1'b1;
                    issued   <= 32'd0;
                    nwords   <= words << 1;   // 32비트 워드 하나가 데이터 두 칸
                    beat     <= 4'd0;
                    haddr    <= src_addr;
                    htrans   <= TRANS_NONSEQ;
                    load_err <= 1'b0;
                end
            end else if (hready) begin
                // 직전 주소 위상의 데이터가 이번 사이클에 돌아옵니다
                if (d_valid) begin
                    if (hresp) load_err <= 1'b1;
                    wr_en   <= 1'b1;
                    wr_addr <= d_idx;
                    wr_data <= d_lane ? hrdata[31:16] : hrdata[15:0];
                end

                if (htrans != TRANS_IDLE) begin
                    d_valid <= 1'b1;
                    d_idx   <= issued[`GP_NB-1:0];
                    d_lane  <= haddr[1];
                    issued  <= issued + 32'd1;
                    beat    <= beat + 4'd1;
                    haddr   <= haddr + 32'd2;
                    // 마지막 워드의 주소를 이미 냈으면 주소 위상을 닫습니다
                    if (issued + 32'd1 >= nwords) htrans <= TRANS_IDLE;
                    else htrans <= (beat == 4'd15) ? TRANS_NONSEQ : TRANS_SEQ;
                end else begin
                    d_valid <= 1'b0;
                    // 마지막 데이터까지 받았으면 종료
                    if (d_valid) begin
                        run       <= 1'b0;
                        load_done <= 1'b1;
                    end
                end
            end
        end
    end

    assign load_busy = run;
endmodule
