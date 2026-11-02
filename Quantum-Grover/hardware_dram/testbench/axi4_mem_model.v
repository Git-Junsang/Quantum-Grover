//=====================================================================
// axi4_mem_model.v -- 32비트 AXI4 슬레이브 메모리 모델 (시뮬 전용)
//
// grover_dram_axi_bridge 뒤에서 RVX NoC + MIG(DDR3) 자리를 대신합니다.
// dram_burst_model.v 가 추상 포트의 심판이었듯, 이 모델은 AXI4 쪽 심판입니다.
//
//   저장소  SIZE_WORDS 개의 32비트 워드. 기본 2 Mi 워드 = 8 MiB 로 진폭표
//           (129 슬롯 x 47,104 B = 5.8 MiB)가 다 들어갑니다.
//   심판    다음을 오류로 셉니다 (err_count).
//             - awsize/arsize 가 4바이트(2)가 아님, burst 가 INCR 이 아님
//             - 4 KiB 경계를 넘는 버스트 (AXI 규칙 위반)
//             - MAX_BEATS 를 넘는 버스트. AXI4 는 256 beat 까지 허용하지만 RVX
//               micro NoC 는 16 beat 넘는 쓰기를 쪼개고 조각마다 B 를 돌려줍니다
//               (2026-09-25 SoC RTL 시뮬). 이 모델은 쪼개지 않고 AXI 대로 B 하나를
//               주므로, 제약을 어기는 브리지도 여기서는 멀쩡히 돕니다 -- 그래서
//               길이 자체를 오류로 셉니다
//             - 주소 범위 밖
//             - wlast 가 awlen 과 다른 자리에 옴
//             - 한 번도 쓴 적 없는 워드를 읽음 -- 브리지나 Main IP 가 빈
//               슬롯을 복원하려 들면 실물은 쓰레기를 읽고도 조용히 계속
//               돌아가므로, 여기서 잡아야 합니다
//
// 타이밍은 파라미터입니다.
//   AR_LAT   AR 수락부터 첫 R beat 까지 (DDR 활성화·CAS + NoC 왕복 자리)
//   B_LAT    wlast 부터 B 응답까지
//   STALL_EN 1 이면 LFSR 로 awready / wready / arready / rvalid 에 불규칙한
//            빈틈을 넣어 핸드셰이크 결함을 드러냅니다
//
// ID 는 하나만 가정합니다(브리지가 0 만 씀). 그래서 R 과 B 가 요청 순서대로
// 나갑니다. 요청 큐는 깊이 4 입니다.
//=====================================================================
`timescale 1ns/1ps

module axi4_mem_model #(
    parameter integer SIZE_WORDS = 2097152,
    parameter integer BW_TID     = 4,
    parameter integer AR_LAT     = 20,
    parameter integer B_LAT      = 8,
    parameter integer STALL_EN   = 0,
    parameter integer MAX_BEATS  = 16
) (
    input  wire              clk,
    input  wire              rstn,

    output wire              awready,
    input  wire              awvalid,
    input  wire [31:0]       awaddr,
    input  wire [BW_TID-1:0] awid,
    input  wire [7:0]        awlen,
    input  wire [2:0]        awsize,
    input  wire [1:0]        awburst,
    output wire              wready,
    input  wire              wvalid,
    input  wire [31:0]       wdata,
    input  wire [3:0]        wstrb,
    input  wire              wlast,
    input  wire              bready,
    output wire              bvalid,
    output wire [BW_TID-1:0] bid,
    output wire [1:0]        bresp,
    output wire              arready,
    input  wire              arvalid,
    input  wire [31:0]       araddr,
    input  wire [BW_TID-1:0] arid,
    input  wire [7:0]        arlen,
    input  wire [2:0]        arsize,
    input  wire [1:0]        arburst,
    input  wire              rready,
    output wire              rvalid,
    output wire [BW_TID-1:0] rid,
    output wire [31:0]       rdata,
    output wire              rlast,
    output wire [1:0]        rresp,

    output wire [31:0]       err_count,
    output reg  [31:0]       wr_bursts,
    output reg  [31:0]       rd_bursts
);
    reg [31:0] mem     [0:SIZE_WORDS-1];
    reg        written [0:SIZE_WORDS-1];

    integer i;
    initial begin
        for (i = 0; i < SIZE_WORDS; i = i + 1) begin
            mem[i]     = 32'hDEAD_BEEF;
            written[i] = 1'b0;
        end
    end

    // 오류 카운터는 채널마다 따로 둡니다 (한 레지스터를 여러 always 에서
    // 올리면 다중 구동).
    reg [31:0] err_aw, err_w, err_ar, err_r;
    assign err_count = err_aw + err_w + err_ar + err_r;

    reg [15:0] lfsr;
    always @(posedge clk) begin
        if (!rstn) lfsr <= 16'hBEEF;
        else       lfsr <= {lfsr[0] ^ lfsr[2] ^ lfsr[3] ^ lfsr[5], lfsr[15:1]};
    end
    wire stall_a = (STALL_EN != 0) && lfsr[0];
    wire stall_b = (STALL_EN != 0) && lfsr[3];
    wire stall_c = (STALL_EN != 0) && lfsr[7] && lfsr[1];

    function burst_bad;
        input [31:0] addr;
        input [7:0]  len;
        input [2:0]  size;
        input [1:0]  burst;
        reg   [31:0] last_byte;
        begin
            last_byte = addr + ({24'd0, len} + 32'd1) * 32'd4 - 32'd1;
            burst_bad = (size != 3'd2) || (burst != 2'b01) || (addr[1:0] != 2'b00) ||
                        (addr[31:12] != last_byte[31:12]) ||
                        ({24'd0, len} >= MAX_BEATS) ||
                        ((last_byte >> 2) >= SIZE_WORDS);
        end
    endfunction

    //=================================================================
    // 쓰기: AW 큐 -> W 소비 -> B 지연 큐
    //=================================================================
    reg [31:0] awq_addr [0:3];
    reg [7:0]  awq_len  [0:3];
    reg [2:0]  awq_wp, awq_rp;          // 3비트 포인터 (깊이 4 + 가득/빔 구분)
    wire       awq_empty = (awq_wp == awq_rp);
    wire       awq_full  = (awq_wp[1:0] == awq_rp[1:0]) && (awq_wp[2] != awq_rp[2]);

    assign awready = !awq_full && !stall_a;
    wire   aw_fire = awvalid && awready;

    reg [7:0]  w_beat;
    assign wready  = !awq_empty && !stall_b;
    wire   w_fire  = wvalid && wready;
    wire [31:0] w_word = (awq_addr[awq_rp[1:0]] >> 2) + {24'd0, w_beat};

    // B 는 wlast 뒤 B_LAT 사이클에 나갑니다. 버스트마다 만기 시각을 큐에 둡니다.
    reg [31:0] cyc;
    reg [31:0] bq_due [0:7];
    reg [3:0]  bq_wp, bq_rp;
    wire       bq_empty = (bq_wp == bq_rp);
    assign bvalid = !bq_empty && (cyc >= bq_due[bq_rp[2:0]]);
    assign bid    = {BW_TID{1'b0}};
    assign bresp  = 2'b00;
    wire   b_fire = bvalid && bready;

    always @(posedge clk) begin
        if (!rstn) begin
            awq_wp <= 3'd0; awq_rp <= 3'd0;
            w_beat <= 8'd0;
            bq_wp  <= 4'd0; bq_rp <= 4'd0;
            cyc    <= 32'd0;
            err_aw <= 32'd0; err_w <= 32'd0;
            wr_bursts <= 32'd0;
        end else begin
            cyc <= cyc + 32'd1;

            if (aw_fire) begin
                awq_addr[awq_wp[1:0]] <= awaddr;
                awq_len[awq_wp[1:0]]  <= awlen;
                awq_wp <= awq_wp + 3'd1;
                if (burst_bad(awaddr, awlen, awsize, awburst)) begin
                    err_aw <= err_aw + 32'd1;
                    $display("axi4_mem_model: 잘못된 AW addr=%h len=%0d size=%0d burst=%0d",
                             awaddr, awlen, awsize, awburst);
                end
            end

            if (w_fire) begin
                if (w_word < SIZE_WORDS) begin
                    mem[w_word]     <= wdata;
                    written[w_word] <= 1'b1;
                end
                if (wstrb != 4'hF) err_w <= err_w + 32'd1;
                if (wlast != (w_beat == awq_len[awq_rp[1:0]])) begin
                    err_w <= err_w + 32'd1;
                    $display("axi4_mem_model: wlast 위치 오류 beat=%0d len=%0d wlast=%0d",
                             w_beat, awq_len[awq_rp[1:0]], wlast);
                end
                if (w_beat == awq_len[awq_rp[1:0]]) begin
                    w_beat <= 8'd0;
                    awq_rp <= awq_rp + 3'd1;
                    bq_due[bq_wp[2:0]] <= cyc + B_LAT;
                    bq_wp  <= bq_wp + 4'd1;
                    wr_bursts <= wr_bursts + 32'd1;
                end else begin
                    w_beat <= w_beat + 8'd1;
                end
            end

            if (b_fire)
                bq_rp <= bq_rp + 4'd1;
        end
    end

    //=================================================================
    // 읽기: AR 큐 -> AR_LAT 뒤 R 스트림
    //=================================================================
    reg [31:0] arq_addr [0:3];
    reg [7:0]  arq_len  [0:3];
    reg [31:0] arq_due  [0:3];
    reg [2:0]  arq_wp, arq_rp;
    wire       arq_empty = (arq_wp == arq_rp);
    wire       arq_full  = (arq_wp[1:0] == arq_rp[1:0]) && (arq_wp[2] != arq_rp[2]);

    assign arready = !arq_full && !stall_a;
    wire   ar_fire = arvalid && arready;

    reg [7:0]  r_beat;
    wire [31:0] r_word = (arq_addr[arq_rp[1:0]] >> 2) + {24'd0, r_beat};
    assign rvalid = !arq_empty && (cyc >= arq_due[arq_rp[1:0]]) && !stall_c;
    assign rdata  = (r_word < SIZE_WORDS) ? mem[r_word] : 32'hBAD0_BAD0;
    assign rlast  = (r_beat == arq_len[arq_rp[1:0]]);
    assign rid    = {BW_TID{1'b0}};
    assign rresp  = 2'b00;
    wire   r_fire = rvalid && rready;

    always @(posedge clk) begin
        if (!rstn) begin
            arq_wp <= 3'd0; arq_rp <= 3'd0;
            r_beat <= 8'd0;
            err_ar <= 32'd0; err_r <= 32'd0;
            rd_bursts <= 32'd0;
        end else begin
            if (ar_fire) begin
                arq_addr[arq_wp[1:0]] <= araddr;
                arq_len[arq_wp[1:0]]  <= arlen;
                arq_due[arq_wp[1:0]]  <= cyc + AR_LAT;
                arq_wp <= arq_wp + 3'd1;
                if (burst_bad(araddr, arlen, arsize, arburst)) begin
                    err_ar <= err_ar + 32'd1;
                    $display("axi4_mem_model: 잘못된 AR addr=%h len=%0d size=%0d burst=%0d",
                             araddr, arlen, arsize, arburst);
                end
            end

            if (r_fire) begin
                if (r_word >= SIZE_WORDS || !written[r_word]) begin
                    if (err_r < 32'd4)
                        $display("axi4_mem_model: 쓴 적 없는 워드를 읽음 word=%0d", r_word);
                    err_r <= err_r + 32'd1;
                end
                if (rlast) begin
                    r_beat <= 8'd0;
                    arq_rp <= arq_rp + 3'd1;
                    rd_bursts <= rd_bursts + 32'd1;
                end else begin
                    r_beat <= r_beat + 8'd1;
                end
            end
        end
    end

    wire _unused = |{awid, arid};
endmodule
