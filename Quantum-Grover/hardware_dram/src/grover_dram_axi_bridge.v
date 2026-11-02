//=====================================================================
// grover_dram_axi_bridge.v -- 추상 DRAM burst 포트를 AXI4 마스터로 바꾸는 브리지
//
// hardware_dram 의 Main IP 는 진폭표 한 슬롯(512행 x 736비트)을 "한 beat =
// 한 행" 인 추상 포트(dram_wr_* / dram_rd_*)로 내보냅니다. 이 모듈이 그
// 스트림을 RVX 의 user_masterif_axi4_clkout(32비트 AXI4) 로 옮기고, NoC 를
// 거쳐 Arty A7-100T 의 DDR3L(MIG xilinx_ddr3_ctrl_axi32)에 닿게 합니다.
//
//   Main IP --dram_wr/rd (736b/beat)--> [이 브리지] --AXI4 32b--> RVX NoC --> MIG
//
// 폭 변환이 딱 떨어집니다
//   한 행 736비트 = 32비트 워드 23개 = 92바이트 = GD_ROW_BYTES
//   한 슬롯 = 512행 x 23워드 = 11,776워드 = 47,104바이트 = GD_ITER_STRIDE
//   그래서 grover_dram_param.vh 의 주소 맵을 한 글자도 안 바꾸고 워드 단위로
//   빈틈없이 채웁니다. 행 k 의 워드 w 는 슬롯 시작 + (k*23 + w)*4 바이트에
//   있고, 워드 0 이 행의 [31:0], 워드 22 가 [735:704] 입니다.
//
// AXI4 버스트 모양
//   INCR, 4바이트(awsize=2), 최대 MAX_BEATS beat(기본 16 = 64 B). 4 KiB 경계는
//   절대 넘지 않게 자릅니다(AXI 규칙). 슬롯 크기 47,104 = 736 x 64 라 AXI_BASE
//   가 64 B 정렬이면 한 슬롯은 정확히 16 beat 버스트 736개입니다.
//   ID 는 0 하나만 씁니다. 같은 ID 의 R 은 순서대로 오므로 재정렬이 없습니다.
//
//   왜 16 beat 인가 (2026-09-25 SoC RTL 시뮬에서 확인)
//   처음에는 AXI4 최대인 256 beat 를 썼습니다. AXI 모델 위 verilator 에서는
//   다 맞았지만, 실제 RVX SoC(micro NoC 4.5 + DDR) 위에서는 첫 탐색이
//   멈췄습니다. NoC 가 256 beat 쓰기를 DDR 쪽에서 16 beat 조각으로 쪼개고,
//   **조각마다 B 응답을 마스터에게 돌려줬습니다** -- AW 46개에 B 736개. AW
//   하나에 B 하나를 세던 b_pending 이 음수로 넘어가 AR 을 영영 못 냈습니다.
//   NoC 가 쪼개지 않는 16 beat 이하로 보내면 AW 하나에 B 하나가 다시 성립하고,
//   읽기의 rlast 도 AR 하나에 하나입니다. axi4_mem_model 은 MAX_BEATS 를 넘는
//   버스트를 오류로 세어 verilator 에서도 이 제약을 지킵니다.
//
// 쓰기 (STORE)
//   dram_wr_req 펄스에 주소를 받아 두고, AW 는 W 보다 최대 두 버스트 앞서
//   냅니다. W 는 자기 AW 가 이미 수락된 버스트만 보냅니다(AW 전에 W 를 보내는
//   것도 AXI 에서 합법이지만, 인터커넥트에 따라 막힐 수 있어서 피합니다).
//   AW 가 수락될 때 그 awlen 을 깊이 4 큐(lenq)에 넣고, W 는 큐 머리와 beat
//   카운터를 맞대 wlast 를 냅니다. W 쪽에서 버스트 길이를 다시 계산하지
//   않으므로 긴 조합 경로도, 버스트 사이 빈 사이클도 없습니다(첫 구현은 W 쪽에서
//   같은 함수를 다시 불러 100 MHz 에서 2.1 ns 모자랐습니다).
//   Main IP 쪽은 행 하나를 받아 23워드로 풀어 보내는 동안 dram_wr_ready 를
//   내립니다. 행마다 한 사이클이 비지만(23/24), 대신 wready 에서 Main IP 의
//   amp_mem 읽기까지 이어지는 조합 경로가 생기지 않습니다.
//   B 응답은 늘 받습니다(bready=1). 받은 수는 아래 "순서" 에 씁니다.
//
// 읽기 (RESTORE)
//   dram_rd_req 펄스에 주소를 받아 두고 AR 을 최대 RD_OUTSTANDING 개까지
//   띄웁니다. R 워드 23개를 모아 한 행이 되면 dram_rd_valid 를 한 사이클
//   올립니다. Main IP 는 복원 중 dram_rd_ready 를 계속 1 로 두므로 보통 바로
//   받지만, 0 이면 행을 붙들고 rready 를 내려 기다립니다. 마지막 행에
//   dram_rd_last 를 겁니다.
//
// 순서 -- 쓴 것을 곧바로 읽을 때
//   Main IP 는 쓰기와 읽기를 동시에 열지 않지만(grover_dram_shot_fsm 이
//   직렬로 냄), 쓰기 마지막 행을 넘긴 직후 같은 슬롯을 읽으러 올 수는
//   있습니다. AXI 는 다른 채널 사이의 순서를 보장하지 않으므로, 앞선 쓰기의
//   B 응답이 전부 돌아오기 전에는 AR 을 내지 않습니다. 읽기 요청 펄스는
//   래치해 두므로 잃지 않습니다.
//
// 오류
//   bresp / rresp 가 OKAY 가 아니면 axi_error 를 세웁니다(리셋까지 유지).
//   CSR 은 두 갈래가 공유하는 정본이라 여기에 새 비트를 만들지 않았습니다.
//   user region 에서 관측점으로만 씁니다.
//
// 클럭·리셋
//   전부 clk 하나(clk_accel). user_masterif_axi4_clkout 은 "유저가 클럭을
//   넣는" 인터페이스라 NoC 쪽 CDC 는 RVX 가 만들어 줍니다. 리셋은 Main IP 와
//   같은 동기식 active-low 입니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_dram_param.vh"

module grover_dram_axi_bridge #(
    // 추상 주소 0 이 닿는 AXI 주소. RVX 가 DDR 을 NoC 주소 0x0000_0000 에
    // 1 GiB 창으로 붙이고, 링커는 use_large_ram_manually 로 DRAM 을 안 쓰게
    // 해 두었으므로 0 부터 써도 소프트웨어와 겹치지 않습니다. MAX_BEATS x 4 B
    // (기본 64 B) 정렬이어야 한 슬롯이 최대 길이 버스트로 딱 떨어집니다.
    parameter [31:0] AXI_BASE       = 32'h0000_0000,
    parameter integer BW_TID        = 4,
    // 버스트 하나의 최대 beat 수. RVX micro NoC 가 쪼개지 않는 16 이하여야
    // 합니다(머리말 "왜 16 beat 인가"). 2 의 거듭제곱, 1..256.
    parameter integer MAX_BEATS     = 16,
    // 읽기 버스트를 동시에 몇 개까지 띄워 둘지. NoC 왕복 지연을 가립니다.
    // 버스트가 16 beat 로 짧아져 둘로는 R 사이가 비어서 넷으로 올렸습니다.
    parameter integer RD_OUTSTANDING = 4,
    // 쓰기에서 AW 가 W 보다 몇 버스트까지 앞설 수 있는지. lenq 깊이(4) 이하.
    parameter integer AW_AHEAD      = 4
) (
    input  wire                            clk,
    input  wire                            rstn,

    //-----------------------------------------------------------------
    // 추상 DRAM 포트 (Main IP 쪽). grover_dram_amp_store.v 의 계약 그대로.
    //-----------------------------------------------------------------
    input  wire                            dram_wr_req,
    input  wire [`GD_ADDR_W-1:0]           dram_wr_addr,
    input  wire [`GD_BURST_LEN_W-1:0]      dram_wr_len,
    input  wire                            dram_wr_valid,
    input  wire [`GP_P*`GP_AMP_W-1:0]      dram_wr_data,
    input  wire                            dram_wr_last,
    output wire                            dram_wr_ready,

    input  wire                            dram_rd_req,
    input  wire [`GD_ADDR_W-1:0]           dram_rd_addr,
    input  wire [`GD_BURST_LEN_W-1:0]      dram_rd_len,
    output wire                            dram_rd_valid,
    output wire [`GP_P*`GP_AMP_W-1:0]      dram_rd_data,
    input  wire                            dram_rd_ready,
    output wire                            dram_rd_last,

    //-----------------------------------------------------------------
    // AXI4 마스터 (RVX user_masterif_axi4_clkout 의 sx4* 이름 순서)
    //-----------------------------------------------------------------
    output reg                             awvalid,
    input  wire                            awready,
    output reg  [31:0]                     awaddr,
    output wire [BW_TID-1:0]               awid,
    output reg  [7:0]                      awlen,
    output wire [2:0]                      awsize,
    output wire [1:0]                      awburst,

    output wire                            wvalid,
    input  wire                            wready,
    output wire [31:0]                     wdata,
    output wire [3:0]                      wstrb,
    output wire                            wlast,

    output wire                            bready,
    input  wire                            bvalid,
    input  wire [BW_TID-1:0]               bid,
    input  wire [1:0]                      bresp,

    output reg                             arvalid,
    input  wire                            arready,
    output reg  [31:0]                     araddr,
    output wire [BW_TID-1:0]               arid,
    output reg  [7:0]                      arlen,
    output wire [2:0]                      arsize,
    output wire [1:0]                      arburst,

    output wire                            rready,
    input  wire                            rvalid,
    input  wire [BW_TID-1:0]               rid,
    input  wire [31:0]                     rdata,
    input  wire                            rlast,
    input  wire [1:0]                      rresp,

    //-----------------------------------------------------------------
    // 관측점
    //-----------------------------------------------------------------
    output wire                            busy,
    output reg                             axi_error
);
    localparam integer ROW_BITS = `GP_P * `GP_AMP_W;     // 736
    localparam integer WPR      = ROW_BITS / 32;         // 23 워드/행
    localparam integer CNT_W    = 16;                    // 워드 카운터 폭 (11,776 < 65,536)

    // 이 브리지의 전제. 736 이 32 의 배수가 아니면 행 경계가 워드 중간에
    // 걸리므로 주소 맵부터 다시 짜야 합니다.
    initial begin
        if (ROW_BITS % 32 != 0) begin
            $display("grover_dram_axi_bridge: ROW_BITS=%0d 가 32 의 배수가 아닙니다", ROW_BITS);
            $finish;
        end
        if (AW_AHEAD < 1 || AW_AHEAD > 4 || MAX_BEATS < 1 || MAX_BEATS > 256) begin
            $display("grover_dram_axi_bridge: AW_AHEAD=%0d (1..4), MAX_BEATS=%0d (1..256)",
                     AW_AHEAD, MAX_BEATS);
            $finish;
        end
    end

    assign awid    = {BW_TID{1'b0}};
    assign arid    = {BW_TID{1'b0}};
    assign awsize  = 3'd2;          // 4바이트
    assign arsize  = 3'd2;
    assign awburst = 2'b01;         // INCR
    assign arburst = 2'b01;
    assign wstrb   = 4'hF;
    assign bready  = 1'b1;

    //-----------------------------------------------------------------
    // 버스트 길이 규칙. 남은 워드, MAX_BEATS, 4 KiB 경계까지의 워드 중 가장
    // 작은 값. AW 와 AR 만 부릅니다(W 는 lenq 로 AW 의 길이를 받습니다).
    //-----------------------------------------------------------------
    function [8:0] burst_words;         // 1..MAX_BEATS
        input [31:0]       addr;
        input [CNT_W-1:0]  remaining;
        reg   [12:0]       to_4k;       // 4 KiB 경계까지 남은 워드 (1..1024)
        reg   [CNT_W-1:0]  n;
        begin
            to_4k = 13'd1024 - {3'd0, addr[11:2]};
            n = remaining;
            if (n > MAX_BEATS)           n = MAX_BEATS;
            if (n > {3'd0, to_4k})       n = {3'd0, to_4k};
            burst_words = n[8:0];
        end
    endfunction

    //=================================================================
    // 쓰기 쪽
    //=================================================================
    reg              w_active;            // 이번 슬롯의 W 를 아직 다 못 보냄
    reg [31:0]       w_base;
    reg [CNT_W-1:0]  w_total;             // 이번 슬롯 전체 워드 수
    reg [CNT_W-1:0]  aw_words;            // AW 로 이미 덮은 워드 수
    reg [CNT_W-1:0]  w_words;             // W 로 이미 보낸 워드 수
    reg [7:0]        w_beat;              // 지금 W 버스트에서 보낸 beat (0..awlen)
    reg [15:0]       b_pending;           // B 를 아직 못 받은 AW 수 (슬롯을 넘어 누적)

    // 수락된 AW 의 awlen 큐. AW 가 수락될 때 넣고 W 가 wlast 를 보낼 때 뺍니다.
    // 큐에 든 것이 곧 "AW 는 수락됐는데 W 를 다 못 보낸 버스트" 라서, 비어
    // 있지 않은 것이 W 를 보내도 된다는 조건이고 개수가 AW 가 앞선 정도입니다.
    // 포인터는 3비트(깊이 4 + 가득/빔 구분)이고 세션을 넘어 계속 돕니다 -- 세션이
    // 끝날 때는 모든 버스트의 W 를 보냈으므로 늘 비어 있습니다.
    reg [7:0]        lenq [0:3];
    reg [2:0]        lq_wp, lq_rp;
    wire [2:0]       lq_count = lq_wp - lq_rp;
    wire [7:0]       w_cur_len = lenq[lq_rp[1:0]];

    // 행 버퍼. 오른쪽으로 32비트씩 밀어 내므로 wdata 는 늘 [31:0] 입니다
    // -- 23:1 멀티플렉서 대신 시프트 레지스터를 씁니다.
    reg [ROW_BITS-1:0] w_row;
    reg                w_row_full;
    reg [4:0]          w_word_idx;        // 0..22

    wire aw_fire = awvalid && awready;
    wire w_fire  = wvalid && wready;
    wire b_fire  = bvalid;                // bready 는 상수 1

    // 이 W 버스트의 AW 가 이미 수락됐는가.
    wire w_has_aw = (lq_count != 3'd0);

    assign dram_wr_ready = w_active && !w_row_full;
    assign wvalid        = w_active && w_row_full && w_has_aw;
    assign wdata         = w_row[31:0];
    assign wlast         = (w_beat == w_cur_len);

    // 쓰기 요청 래치. Main IP 는 마지막 행을 넘기는 순간 저장이 끝났다고
    // 보는데, 이 브리지는 그 행의 23워드를 아직 보내는 중일 수 있습니다. 그
    // 사이 다음 저장의 dram_wr_req 펄스가 오면 여기 붙들어 두었다가 앞 세션이
    // 끝나는 대로 시작합니다. 펄스를 흘리면 그 슬롯의 행이 영영 안 받아져
    // Main IP 가 멈춥니다.
    reg                         w_req_q;
    reg [`GD_ADDR_W-1:0]        w_req_addr_q;
    reg [`GD_BURST_LEN_W-1:0]   w_req_len_q;

    wire                        w_start     = !w_active && (dram_wr_req || w_req_q);
    wire [`GD_ADDR_W-1:0]       w_start_addr = w_req_q ? w_req_addr_q : dram_wr_addr;
    wire [`GD_BURST_LEN_W-1:0]  w_start_len  = w_req_q ? w_req_len_q  : dram_wr_len;

    wire [CNT_W-1:0] wr_total_words =
        ({{(CNT_W-`GD_BURST_LEN_W){1'b0}}, w_start_len} + 1'b1) * WPR;

    always @(posedge clk) begin
        if (!rstn) begin
            w_active   <= 1'b0;
            w_base     <= 32'd0;
            w_total    <= {CNT_W{1'b0}};
            aw_words   <= {CNT_W{1'b0}};
            w_words    <= {CNT_W{1'b0}};
            w_beat     <= 8'd0;
            lq_wp      <= 3'd0;
            lq_rp      <= 3'd0;
            awvalid    <= 1'b0;
            awaddr     <= 32'd0;
            awlen      <= 8'd0;
            w_row      <= {ROW_BITS{1'b0}};
            w_row_full <= 1'b0;
            w_word_idx <= 5'd0;
            w_req_q      <= 1'b0;
            w_req_addr_q <= {`GD_ADDR_W{1'b0}};
            w_req_len_q  <= {`GD_BURST_LEN_W{1'b0}};
        end else begin
            //---------------- 세션 시작 ----------------
            if (w_start) begin
                w_active   <= 1'b1;
                w_base     <= AXI_BASE + w_start_addr;
                w_total    <= wr_total_words;
                aw_words   <= {CNT_W{1'b0}};
                w_words    <= {CNT_W{1'b0}};
                w_beat     <= 8'd0;
                w_row_full <= 1'b0;
                w_word_idx <= 5'd0;
                w_req_q    <= 1'b0;
            end else if (dram_wr_req) begin
                // 앞 세션이 아직 도는 중. 끝나면 위 분기가 이어받습니다.
                w_req_q      <= 1'b1;
                w_req_addr_q <= dram_wr_addr;
                w_req_len_q  <= dram_wr_len;
            end

            //---------------- AW ----------------
            if (aw_fire) begin
                awvalid   <= 1'b0;
                aw_words  <= aw_words + {{(CNT_W-9){1'b0}}, ({1'b0, awlen} + 9'd1)};
                lenq[lq_wp[1:0]] <= awlen;
                lq_wp     <= lq_wp + 3'd1;
            end else if (w_active && !awvalid && (aw_words < w_total) &&
                         (lq_count < AW_AHEAD)) begin
                awvalid <= 1'b1;
                awaddr  <= w_base + {aw_words, 2'b00};
                awlen   <= burst_words(w_base + {aw_words, 2'b00}, w_total - aw_words) - 9'd1;
            end

            //---------------- 행 받기 ----------------
            if (dram_wr_valid && dram_wr_ready) begin
                w_row      <= dram_wr_data;
                w_row_full <= 1'b1;
                w_word_idx <= 5'd0;
            end

            //---------------- W ----------------
            if (w_fire) begin
                w_row   <= {32'd0, w_row[ROW_BITS-1:32]};
                w_words <= w_words + 1'b1;
                if (w_word_idx == WPR - 1) begin
                    w_row_full <= 1'b0;
                    w_word_idx <= 5'd0;
                end else begin
                    w_word_idx <= w_word_idx + 5'd1;
                end
                if (wlast) begin
                    w_beat <= 8'd0;
                    lq_rp  <= lq_rp + 3'd1;
                end else begin
                    w_beat <= w_beat + 8'd1;
                end
                if (w_words + 1'b1 == w_total)
                    w_active <= 1'b0;
            end

        end
    end

    //---------------- B ----------------
    always @(posedge clk) begin
        if (!rstn)
            b_pending <= 16'd0;
        else
            b_pending <= b_pending + (aw_fire ? 16'd1 : 16'd0) - (b_fire ? 16'd1 : 16'd0);
    end

    //=================================================================
    // 읽기 쪽
    //=================================================================
    reg              r_active;
    reg [31:0]       r_base;
    reg [CNT_W-1:0]  r_total;
    reg [CNT_W-1:0]  ar_words;            // AR 로 이미 요청한 워드 수
    // 한 슬롯이 버스트 736개라 8비트로는 돕니다. CNT_W 로 두면 세션 안에서
    // 돌지 않으므로 뺄셈이 그대로 "띄워 둔 AR 수" 입니다.
    reg [CNT_W-1:0]  ar_bursts;           // 수락된 AR 수
    reg [CNT_W-1:0]  r_bursts;            // rlast 까지 받은 버스트 수
    wire [CNT_W-1:0] ar_inflight = ar_bursts - r_bursts;
    reg [9:0]        rows_total;          // len + 1
    reg [9:0]        rows_out;            // Main IP 가 받아 간 행 수

    reg [ROW_BITS-1:0] r_acc;             // 오른쪽으로 밀며 채웁니다
    reg [4:0]          r_word_idx;
    reg                r_row_valid;

    wire ar_fire  = arvalid && arready;
    wire row_take = r_row_valid && dram_rd_ready;
    wire r_fire   = rvalid && rready;

    // 행 하나를 붙들고 있고 Main IP 가 이번 사이클에 안 가져가면 R 을 멈춥니다.
    assign rready        = r_active && (!r_row_valid || dram_rd_ready);
    assign dram_rd_valid = r_row_valid;
    assign dram_rd_data  = r_acc;
    assign dram_rd_last  = r_row_valid && (rows_out == rows_total - 10'd1);

    wire [CNT_W-1:0] rd_total_words =
        ({{(CNT_W-`GD_BURST_LEN_W){1'b0}}, dram_rd_len} + 1'b1) * WPR;

    // 앞선 쓰기가 DRAM 에 다 닿은 뒤에만 AR 을 냅니다 (머리말 "순서").
    wire writes_settled = !w_active && !w_req_q && (b_pending == 16'd0);

    always @(posedge clk) begin
        if (!rstn) begin
            r_active    <= 1'b0;
            r_base      <= 32'd0;
            r_total     <= {CNT_W{1'b0}};
            ar_words    <= {CNT_W{1'b0}};
            ar_bursts   <= {CNT_W{1'b0}};
            r_bursts    <= {CNT_W{1'b0}};
            rows_total  <= 10'd0;
            rows_out    <= 10'd0;
            arvalid     <= 1'b0;
            araddr      <= 32'd0;
            arlen       <= 8'd0;
            r_acc       <= {ROW_BITS{1'b0}};
            r_word_idx  <= 5'd0;
            r_row_valid <= 1'b0;
        end else begin
            if (dram_rd_req && !r_active) begin
                r_active    <= 1'b1;
                r_base      <= AXI_BASE + dram_rd_addr;
                r_total     <= rd_total_words;
                ar_words    <= {CNT_W{1'b0}};
                ar_bursts   <= {CNT_W{1'b0}};
                r_bursts    <= {CNT_W{1'b0}};
                rows_total  <= {1'b0, dram_rd_len[8:0]} + 10'd1;
                rows_out    <= 10'd0;
                r_word_idx  <= 5'd0;
                r_row_valid <= 1'b0;
            end

            //---------------- AR ----------------
            if (ar_fire) begin
                arvalid   <= 1'b0;
                ar_words  <= ar_words + {{(CNT_W-9){1'b0}}, ({1'b0, arlen} + 9'd1)};
                ar_bursts <= ar_bursts + 1'b1;
            end else if (r_active && !arvalid && writes_settled &&
                         (ar_words < r_total) &&
                         (ar_inflight < RD_OUTSTANDING)) begin
                arvalid <= 1'b1;
                araddr  <= r_base + {ar_words, 2'b00};
                arlen   <= burst_words(r_base + {ar_words, 2'b00}, r_total - ar_words) - 9'd1;
            end

            //---------------- 행 내보내기 ----------------
            if (row_take) begin
                r_row_valid <= 1'b0;
                rows_out    <= rows_out + 10'd1;
                if (rows_out == rows_total - 10'd1)
                    r_active <= 1'b0;
            end

            //---------------- R ----------------
            // row_take 와 같은 사이클에 새 워드가 들어와도 됩니다. Main IP 는
            // 이 에지 전의 r_acc 를 가져가고, r_acc 는 이 에지에서 다음 행의
            // 첫 워드로 밀립니다.
            if (r_fire) begin
                r_acc <= {rdata, r_acc[ROW_BITS-1:32]};
                if (rlast)
                    r_bursts <= r_bursts + 1'b1;
                if (r_word_idx == WPR - 1) begin
                    r_word_idx  <= 5'd0;
                    r_row_valid <= 1'b1;
                end else begin
                    r_word_idx <= r_word_idx + 5'd1;
                end
            end
        end
    end

    //=================================================================
    // 오류 (sticky)
    //=================================================================
    always @(posedge clk) begin
        if (!rstn)
            axi_error <= 1'b0;
        else if ((b_fire && (bresp != 2'b00)) || (r_fire && (rresp != 2'b00)))
            axi_error <= 1'b1;
    end

    assign busy = w_active || w_req_q || r_active || (b_pending != 16'd0);

    // 이 브리지는 ID 를 하나만 쓰므로 bid/rid 는 볼 필요가 없습니다.
    // dram_wr_last 는 행 수로 이미 세고 있어 참고하지 않습니다.
    wire _unused = |{bid, rid, dram_wr_last};

endmodule
