//=====================================================================
// bbht_ahb_loader.v -- 데이터셋 DMA (통신 담당 소유)
//
// System SRAM 에 놓인 signed 16비트 배열을 AHB 마스터로 읽어 Main IP 의
// generic loader 포트(data_wr_en / data_wr_addr / data_wr_data)로 넘깁니다.
// RVX 의 user_masterif_ahb_clkout 이 뽑아 주는 sh* 포트를 그대로 씁니다.
//
// 전송 방식은 32비트 AHB SINGLE read, single outstanding 입니다. PJK 의
// sign-off baseline 이 이것이고, 구문서에 남아 있는 INCR16 계획이 아닙니다.
// 버스트로 올리는 것은 DMA 가 실제 병목임이 측정된 뒤에 볼 일입니다
// (인수인계 §4.3) -- 지금은 적재가 Q14 전체에서 246 us 정도이고 탐색 한
// 번이 그보다 훨씬 깁니다.
//
// 워드 매핑은 리틀엔디안입니다.
//   word[k][15:0]  -> data[2k]
//   word[k][31:16] -> data[2k+1]
// data_count 가 홀수면 마지막 워드의 상위 16비트는 쓰지 않습니다.
//
// 시작 전에 네 가지를 검사하고, 하나라도 걸리면 전송을 시작하지 않은 채
// 오류 비트만 세웁니다. 절반만 채워진 배열 위에서 오라클을 돌리면 아무
// 경고 없이 그럴듯한 오답이 나오기 때문입니다.
//   정렬   data_addr[1:0] == 0
//   개수   1 <= data_count <= N
//   범위   [data_addr, data_addr + 4*words) 가 System SRAM 안
//   상태   Main IP 가 busy 가 아닐 것
//=====================================================================
`timescale 1ns/1ps
`include "bbht_grover_csr.vh"

module bbht_ahb_loader #(
    // System SRAM 범위. 플랫폼 XML 의 sram_size 를 바꾸면 같이 바뀝니다.
    // 정본은 RVX 생성물 arch/ssw/src/memorymap_info.h 입니다.
    parameter [31:0] SRAM_BASE = 32'hE000_0000,
    parameter [31:0] SRAM_LAST = 32'hE001_FFFF
) (
    input  wire        clk,
    input  wire        rstnn,

    //-----------------------------------------------------------------
    // CSR 접점
    //-----------------------------------------------------------------
    input  wire        dma_start,        // DMA_COMMAND 쓰기 펄스
    input  wire [31:0] data_addr,
    input  wire [14:0] data_count,
    input  wire        main_busy,        // Main IP search busy
    output wire [7:0]  dma_status,

    //-----------------------------------------------------------------
    // AHB 마스터 -- RVX user 쪽 이름 그대로 (i_grover_dma_sh*)
    //-----------------------------------------------------------------
    input  wire        shready,
    input  wire [31:0] shrdata,
    input  wire        shresp,
    output reg  [31:0] shaddr,
    output wire [2:0]  shburst,
    output wire        shmasterlock,
    output wire [3:0]  shprot,
    output wire [2:0]  shsize,
    output reg  [1:0]  shtrans,
    output wire        shwrite,
    output wire [31:0] shwdata,

    //-----------------------------------------------------------------
    // Main IP generic loader 포트
    //-----------------------------------------------------------------
    output reg         load_start,
    output reg         data_wr_en,
    output reg  [13:0] data_wr_addr,
    output reg  signed [15:0] data_wr_data,
    output reg         load_done
);

    //-----------------------------------------------------------------
    // AHB 상수. 읽기 전용 마스터라 대부분 고정입니다.
    //-----------------------------------------------------------------
    localparam [1:0] TRANS_IDLE   = 2'b00;
    localparam [1:0] TRANS_NONSEQ = 2'b10;

    assign shwrite      = 1'b0;
    assign shwdata      = 32'd0;
    assign shsize       = 3'b010;     // 4바이트
    assign shburst      = 3'b000;     // SINGLE
    assign shmasterlock = 1'b0;
    assign shprot       = 4'b0011;    // data, privileged, non-bufferable, non-cacheable

    //-----------------------------------------------------------------
    // 세션 상태
    //-----------------------------------------------------------------
    localparam [2:0] S_IDLE = 3'd0,
                     S_ADDR = 3'd1,   // 주소 위상
                     S_DATA = 3'd2,   // 데이터 위상 + 하위 16비트 쓰기
                     S_WR1  = 3'd3,   // 상위 16비트 쓰기
                     S_END  = 3'd4;

    reg [2:0]  state;
    reg [13:0] word_idx;              // 지금 읽고 있는 32비트 워드 번호
    reg [13:0] word_total;            // ceil(data_count / 2)
    reg [31:0] hold;                  // 방금 받은 워드
    reg [14:0] count_lat;             // 세션 시작 시점의 data_count

    // 오류 비트 (sticky). 새 DMA_COMMAND 가 클리어합니다.
    reg err_align, err_count, err_resp, err_busy, err_range;
    reg done_sticky;
    reg busy;

    wire any_err = err_align | err_count | err_resp | err_busy | err_range;

    assign dma_status[`BBHT_DMA_DMA_BUSY]        = busy;
    assign dma_status[`BBHT_DMA_DMA_ERROR]       = any_err;
    assign dma_status[`BBHT_DMA_ALIGN_ERROR]     = err_align;
    assign dma_status[`BBHT_DMA_COUNT_ERROR]     = err_count;
    assign dma_status[`BBHT_DMA_RESP_ERROR]      = err_resp;
    assign dma_status[`BBHT_DMA_BUSY_ERROR]      = err_busy;
    assign dma_status[`BBHT_DMA_RANGE_ERROR]     = err_range;
    assign dma_status[`BBHT_DMA_DMA_DONE_STICKY] = done_sticky;

    //-----------------------------------------------------------------
    // 시작 조건 검사 -- dma_start 가 뜬 사이클에 조합으로 판정합니다.
    //-----------------------------------------------------------------
    wire [14:0] words_needed = (data_count + 15'd1) >> 1;      // ceil(count/2)
    wire [32:0] end_addr     = {1'b0, data_addr} + {16'd0, words_needed, 2'b00} - 33'd1;

    wire chk_align = (data_addr[1:0] != 2'b00);
    wire chk_count = (data_count == 15'd0) || (data_count > `BBHT_N_ENTRIES);
    wire chk_busy  = main_busy;
    wire chk_range = (data_addr < SRAM_BASE) || (end_addr > {1'b0, SRAM_LAST});
    wire chk_any   = chk_align | chk_count | chk_busy | chk_range;

    //-----------------------------------------------------------------
    // 마지막 항목이 워드의 하위 절반에서 끝나는가.
    // data_count 가 홀수면 마지막 워드의 상위 16비트는 버립니다.
    //-----------------------------------------------------------------
    wire last_word     = (word_idx + 14'd1 == word_total);
    wire upper_valid   = !(last_word && count_lat[0]);

    always @(posedge clk or negedge rstnn) begin
        if (!rstnn) begin
            state        <= S_IDLE;
            shaddr       <= 32'd0;
            shtrans      <= TRANS_IDLE;
            word_idx     <= 14'd0;
            word_total   <= 14'd0;
            hold         <= 32'd0;
            count_lat    <= 15'd0;
            busy         <= 1'b0;
            done_sticky  <= 1'b0;
            err_align    <= 1'b0;
            err_count    <= 1'b0;
            err_resp     <= 1'b0;
            err_busy     <= 1'b0;
            err_range    <= 1'b0;
            load_start   <= 1'b0;
            load_done    <= 1'b0;
            data_wr_en   <= 1'b0;
            data_wr_addr <= 14'd0;
            data_wr_data <= 16'sd0;
        end else begin
            load_start <= 1'b0;
            load_done  <= 1'b0;
            data_wr_en <= 1'b0;

            case (state)
            //---------------------------------------------------------
            S_IDLE: begin
                shtrans <= TRANS_IDLE;

                if (dma_start) begin
                    // 새 명령은 직전 세션의 상태를 전부 지우고 시작합니다.
                    done_sticky <= 1'b0;
                    err_align   <= chk_align;
                    err_count   <= chk_count;
                    err_busy    <= chk_busy;
                    err_range   <= chk_range;
                    err_resp    <= 1'b0;

                    if (!chk_any) begin
                        busy       <= 1'b1;
                        load_start <= 1'b1;
                        shaddr     <= data_addr;
                        shtrans    <= TRANS_NONSEQ;
                        word_idx   <= 14'd0;
                        word_total <= words_needed[13:0];
                        count_lat  <= data_count;
                        state      <= S_ADDR;
                    end
                    // 검사에 걸리면 busy 도 서지 않고 오류 비트만 남습니다.
                end
            end

            //---------------------------------------------------------
            // 주소 위상. shready 가 설 때까지 NONSEQ 를 유지합니다.
            //---------------------------------------------------------
            S_ADDR: begin
                shtrans <= TRANS_NONSEQ;
                if (shready) begin
                    shtrans <= TRANS_IDLE;
                    state   <= S_DATA;
                end
            end

            //---------------------------------------------------------
            // 데이터 위상. single outstanding 이라 이 동안 주소 위상을
            // 내지 않습니다.
            //---------------------------------------------------------
            S_DATA: begin
                shtrans <= TRANS_IDLE;
                if (shready) begin
                    if (shresp) begin
                        err_resp <= 1'b1;
                        busy     <= 1'b0;
                        state    <= S_IDLE;
                    end else begin
                        hold         <= shrdata;
                        data_wr_en   <= 1'b1;
                        data_wr_addr <= {word_idx[12:0], 1'b0};   // 2k
                        data_wr_data <= shrdata[15:0];
                        state        <= S_WR1;
                    end
                end
            end

            //---------------------------------------------------------
            // 상위 16비트를 쓰고 다음 워드로 넘어갑니다.
            //---------------------------------------------------------
            S_WR1: begin
                if (upper_valid) begin
                    data_wr_en   <= 1'b1;
                    data_wr_addr <= {word_idx[12:0], 1'b1};      // 2k+1
                    data_wr_data <= hold[31:16];
                end

                if (last_word) begin
                    state <= S_END;
                end else begin
                    word_idx <= word_idx + 14'd1;
                    shaddr   <= shaddr + 32'd4;
                    shtrans  <= TRANS_NONSEQ;
                    state    <= S_ADDR;
                end
            end

            //---------------------------------------------------------
            S_END: begin
                shtrans     <= TRANS_IDLE;
                busy        <= 1'b0;
                done_sticky <= 1'b1;
                load_done   <= 1'b1;
                state       <= S_IDLE;
            end

            default: state <= S_IDLE;
            endcase
        end
    end

endmodule
