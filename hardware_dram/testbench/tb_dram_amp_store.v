//=====================================================================
// tb_dram_amp_store.v -- grover_dram_amp_store.v 단위 회귀
//
// 확인하는 것
//   A1  store 한 512행이 restore 로 비트 하나 안 틀리고 돌아오는가
//   A2  슬롯 주소가 GD_AMP_BASE + j * GD_ITER_STRIDE 인가
//   A3  슬롯이 서로 안 겹치는가 (j=1 을 덮어써도 j=127 이 멀쩡한가)
//   A4  DRAM 이 백프레셔를 걸어도 (wr_ready 지연, beat 간격, 불규칙 stall)
//       행이 밀리거나 겹쳐 쓰이지 않는가
//   A5  store/restore 가 각각 512 beat 를 정확히 한 버스트로 끝내는가
//
// A4 가 이 파일의 핵심입니다. STORE 는 사이클당 한 행을 흘려보내면서
// grover_amp_mem 의 rd_q 자체를 skid 버퍼로 씁니다 -- rd_en 을 안 걸면
// 출력이 그대로 멈춰 있다는 성질에 기대는 구조라, 백프레셔가 걸릴 때만
// 행이 어긋날 수 있습니다. 지연 0 인 모델로는 절대 안 잡힙니다.
// 실제로 3사이클/beat 를 1사이클/beat 로 바꿨을 때 여기서만 드러난 결함이
// 있었습니다 (그때는 DRAM 모델 쪽이 ready 를 든 채 안 받은 것이었습니다).
//
// 파라미터는 verilator -G 로 밖에서 덮어씁니다. sim/Makefile 이 같은
// 테스트벤치를 지연 0 / 지연 큼+백프레셔 두 벌로 돌립니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_dram_param.vh"

module tb_dram_amp_store #(
    parameter integer WR_LAT   = 0,
    parameter integer RD_LAT   = 1,
    parameter integer BEAT_GAP = 0,
    parameter integer STALL_EN = 0
);
    localparam integer ROW_BITS = `GP_P * `GP_AMP_W;
    localparam integer ROWS     = `GP_ROWS;

    reg clk  = 1'b0;
    reg rstn = 1'b0;

    always #5 clk = ~clk;      // 100 MHz

    integer errors = 0;

    //-----------------------------------------------------------------
    // 검사용 진폭 패턴. tag 마다 완전히 다른 512x32 표가 나옵니다.
    // 23비트 안에서만 움직이게 마스크합니다.
    //-----------------------------------------------------------------
    function [`GP_AMP_W-1:0] pat;
        input integer row;
        input integer lane;
        input integer tag;
        begin
            pat = (row * 32 + lane + tag * 7919 + (row ^ (lane * 131)))
                  & ((1 << `GP_AMP_W) - 1);
        end
    endfunction

    function [ROW_BITS-1:0] pat_row;
        input integer row;
        input integer tag;
        integer l;
        begin
            pat_row = {ROW_BITS{1'b0}};
            for (l = 0; l < `GP_P; l = l + 1)
                pat_row[l*`GP_AMP_W +: `GP_AMP_W] = pat(row, l, tag);
        end
    endfunction

    //-----------------------------------------------------------------
    // DUT 와 주변
    //-----------------------------------------------------------------
    reg                    store_start   = 1'b0;
    reg  [`GP_J_W-1:0]     store_j       = 7'd0;
    wire                   store_busy;
    wire                   store_done;

    reg                    restore_start = 1'b0;
    reg  [`GP_J_W-1:0]     restore_j     = 7'd0;
    wire                   restore_busy;
    wire                   restore_done;

    wire [`GP_ROW_W-1:0]   store_rd_row;
    wire                   store_rd_en;
    wire [ROW_BITS-1:0]    store_rd_data;

    wire [`GP_ROW_W-1:0]   restore_wr_row;
    wire                   restore_wr_en;
    wire [ROW_BITS-1:0]    restore_wr_data;

    wire                        dram_wr_req, dram_wr_valid, dram_wr_last, dram_wr_ready;
    wire [`GD_ADDR_W-1:0]       dram_wr_addr;
    wire [`GD_BURST_LEN_W-1:0]  dram_wr_len;
    wire [ROW_BITS-1:0]         dram_wr_data;

    wire                        dram_rd_req, dram_rd_valid, dram_rd_ready, dram_rd_last;
    wire [`GD_ADDR_W-1:0]       dram_rd_addr;
    wire [`GD_BURST_LEN_W-1:0]  dram_rd_len;
    wire [ROW_BITS-1:0]         dram_rd_data;

    wire [31:0] store_bursts, restore_bursts, dram_errors;

    grover_dram_amp_store u_dut (
        .clk             (clk),
        .rstn            (rstn),
        .store_start     (store_start),
        .store_j         (store_j),
        .store_busy      (store_busy),
        .store_done      (store_done),
        .store_rd_row    (store_rd_row),
        .store_rd_en     (store_rd_en),
        .store_rd_data   (store_rd_data),
        .restore_start   (restore_start),
        .restore_j       (restore_j),
        .restore_busy    (restore_busy),
        .restore_done    (restore_done),
        .restore_wr_row  (restore_wr_row),
        .restore_wr_en   (restore_wr_en),
        .restore_wr_data (restore_wr_data),
        .dram_wr_req     (dram_wr_req),
        .dram_wr_addr    (dram_wr_addr),
        .dram_wr_len     (dram_wr_len),
        .dram_wr_valid   (dram_wr_valid),
        .dram_wr_data    (dram_wr_data),
        .dram_wr_last    (dram_wr_last),
        .dram_wr_ready   (dram_wr_ready),
        .dram_rd_req     (dram_rd_req),
        .dram_rd_addr    (dram_rd_addr),
        .dram_rd_len     (dram_rd_len),
        .dram_rd_valid   (dram_rd_valid),
        .dram_rd_data    (dram_rd_data),
        .dram_rd_ready   (dram_rd_ready),
        .dram_rd_last    (dram_rd_last)
    );

    dram_burst_model #(
        .WR_LAT   (WR_LAT),
        .RD_LAT   (RD_LAT),
        .BEAT_GAP (BEAT_GAP),
        .STALL_EN (STALL_EN)
    ) u_dram (
        .clk            (clk),
        .rstn           (rstn),
        .wr_req         (dram_wr_req),
        .wr_addr        (dram_wr_addr),
        .wr_len         (dram_wr_len),
        .wr_valid       (dram_wr_valid),
        .wr_data        (dram_wr_data),
        .wr_last        (dram_wr_last),
        .wr_ready       (dram_wr_ready),
        .rd_req         (dram_rd_req),
        .rd_addr        (dram_rd_addr),
        .rd_len         (dram_rd_len),
        .rd_valid       (dram_rd_valid),
        .rd_data        (dram_rd_data),
        .rd_ready       (dram_rd_ready),
        .rd_last        (dram_rd_last),
        .store_bursts   (store_bursts),
        .restore_bursts (restore_bursts),
        .err_count      (dram_errors)
    );

    // 원본 버퍼: 테스트벤치가 채우고 amp_store 가 읽어 갑니다.
    reg  [`GP_ROW_W-1:0] src_wr_row = 9'd0;
    reg                  src_wr_en  = 1'b0;
    reg  [ROW_BITS-1:0]  src_wr_amp = {ROW_BITS{1'b0}};

    grover_amp_mem u_src (
        .clk    (clk),
        .rd_row (store_rd_row), .rd_en (store_rd_en), .rd_amp (store_rd_data),
        .wr_row (src_wr_row),   .wr_en (src_wr_en),   .wr_amp (src_wr_amp)
    );

    // 목적 버퍼: amp_store 가 복원해 넣고 테스트벤치가 읽어 검사합니다.
    reg  [`GP_ROW_W-1:0] dst_rd_row = 9'd0;
    reg                  dst_rd_en  = 1'b0;
    wire [ROW_BITS-1:0]  dst_rd_amp;

    grover_amp_mem u_dst (
        .clk    (clk),
        .rd_row (dst_rd_row),     .rd_en (dst_rd_en),     .rd_amp (dst_rd_amp),
        .wr_row (restore_wr_row), .wr_en (restore_wr_en), .wr_amp (restore_wr_data)
    );

    //-----------------------------------------------------------------
    // A2: 버스트 요청이 뜰 때 주소를 직접 대조합니다. store 와 restore 가
    // 똑같이 틀린 주소를 계산하면 왕복 검사만으로는 안 잡히기 때문에,
    // 버스 위의 숫자 자체를 봅니다.
    //-----------------------------------------------------------------
    reg [63:0] expect_wr_addr = 64'd0;
    reg [63:0] expect_rd_addr = 64'd0;

    always @(posedge clk) begin
        if (rstn && dram_wr_req) begin
            if (dram_wr_addr !== expect_wr_addr[`GD_ADDR_W-1:0]) begin
                errors = errors + 1;
                $display("FAIL A2: 저장 주소 0x%08x, 기대 0x%08x",
                         dram_wr_addr, expect_wr_addr[`GD_ADDR_W-1:0]);
            end
            if (dram_wr_len !== (ROWS - 1)) begin
                errors = errors + 1;
                $display("FAIL A5: 저장 len=%0d, 기대 %0d", dram_wr_len, ROWS - 1);
            end
        end
        if (rstn && dram_rd_req) begin
            if (dram_rd_addr !== expect_rd_addr[`GD_ADDR_W-1:0]) begin
                errors = errors + 1;
                $display("FAIL A2: 복원 주소 0x%08x, 기대 0x%08x",
                         dram_rd_addr, expect_rd_addr[`GD_ADDR_W-1:0]);
            end
            if (dram_rd_len !== (ROWS - 1)) begin
                errors = errors + 1;
                $display("FAIL A5: 복원 len=%0d, 기대 %0d", dram_rd_len, ROWS - 1);
            end
        end
    end

    //-----------------------------------------------------------------
    // 태스크
    //-----------------------------------------------------------------
    integer r, l;

    task fill_src;
        input integer tag;
        begin
            for (r = 0; r < ROWS; r = r + 1) begin
                @(negedge clk);
                src_wr_row = r[`GP_ROW_W-1:0];
                src_wr_amp = pat_row(r, tag);
                src_wr_en  = 1'b1;
            end
            @(negedge clk);
            src_wr_en = 1'b0;
        end
    endtask

    task do_store;
        input integer j;
        begin
            expect_wr_addr = `GD_AMP_BASE + j * `GD_ITER_STRIDE;
            @(negedge clk);
            store_j     = j[`GP_J_W-1:0];
            store_start = 1'b1;
            @(negedge clk);
            store_start = 1'b0;
            wait (store_done === 1'b1);
            @(negedge clk);
        end
    endtask

    task do_restore;
        input integer j;
        begin
            expect_rd_addr = `GD_AMP_BASE + j * `GD_ITER_STRIDE;
            @(negedge clk);
            restore_j     = j[`GP_J_W-1:0];
            restore_start = 1'b1;
            @(negedge clk);
            restore_start = 1'b0;
            wait (restore_done === 1'b1);
            @(negedge clk);
        end
    endtask

    // 목적 버퍼 전체가 tag 패턴과 같은지 봅니다. 첫 불일치만 찍고
    // 나머지는 개수만 셉니다 (512행 x 32레인이라 다 찍으면 못 읽습니다).
    task check_dst;
        input integer tag;
        input [255:0] label;
        integer bad;
        reg [ROW_BITS-1:0] got;
        begin
            bad = 0;
            for (r = 0; r < ROWS; r = r + 1) begin
                @(negedge clk);
                dst_rd_row = r[`GP_ROW_W-1:0];
                dst_rd_en  = 1'b1;
                @(negedge clk);
                dst_rd_en  = 1'b0;
                @(negedge clk);
                got = dst_rd_amp;
                if (got !== pat_row(r, tag)) begin
                    if (bad == 0) begin
                        $display("FAIL %0s: 행 %0d 불일치", label, r);
                        for (l = 0; l < `GP_P; l = l + 1)
                            if (got[l*`GP_AMP_W +: `GP_AMP_W] !== pat(r, l, tag))
                                $display("        레인 %0d: 받은 0x%06x, 기대 0x%06x",
                                         l, got[l*`GP_AMP_W +: `GP_AMP_W], pat(r, l, tag));
                    end
                    bad = bad + 1;
                end
            end
            if (bad != 0) begin
                errors = errors + 1;
                $display("FAIL %0s: %0d행이 어긋났습니다", label, bad);
            end else begin
                $display("  ok  %0s (512행 x 32레인 일치)", label);
            end
        end
    endtask

    //-----------------------------------------------------------------
    // 본체
    //-----------------------------------------------------------------
    initial begin
        $display("=== tb_dram_amp_store (WR_LAT=%0d RD_LAT=%0d BEAT_GAP=%0d STALL_EN=%0d) ===",
                 WR_LAT, RD_LAT, BEAT_GAP, STALL_EN);
        repeat (4) @(negedge clk);
        rstn = 1'b1;
        repeat (4) @(negedge clk);

        // --- A1/A2: 슬롯 1 왕복 -------------------------------------
        fill_src(1);
        do_store(1);
        fill_src(2);          // 원본을 바꿔 놔야 "원본을 그냥 읽은 것"이 아님이 확실해집니다
        do_restore(1);
        check_dst(1, "A1 슬롯1 왕복");

        // --- A3: 다른 슬롯이 서로 안 겹치는가 -----------------------
        // 127 이 실제로 도달 가능한 마지막 슬롯입니다. GP_J_W = 7 이라
        // store_j/restore_j 가 0..127 밖을 표현하지 못합니다 (GP_M_MAX = 128
        // 은 m_bound 의 상한이지 j 의 상한이 아닙니다). 주소 stride 계산이
        // 넘치면 여기서 걸립니다.
        do_store(127);        // 지금 원본은 tag=2
        fill_src(3);
        do_store(1);          // 슬롯 1 을 tag=3 으로 덮어씀
        do_restore(127);
        check_dst(2, "A3 슬롯127 보존");
        do_restore(1);
        check_dst(3, "A3 슬롯1 덮어쓰기");

        // --- A5: 버스트 횟수 ----------------------------------------
        if (store_bursts !== 32'd3) begin
            errors = errors + 1;
            $display("FAIL A5: 저장 버스트 %0d회, 기대 3회", store_bursts);
        end
        if (restore_bursts !== 32'd3) begin
            errors = errors + 1;
            $display("FAIL A5: 복원 버스트 %0d회, 기대 3회", restore_bursts);
        end

        if (dram_errors !== 32'd0) begin
            errors = errors + 1;
            $display("FAIL: DRAM 모델이 프로토콜 오류 %0d건을 보고했습니다", dram_errors);
        end

        repeat (10) @(negedge clk);
        $display("=== 결과: 오류 %0d 건 ===", errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $finish;
    end

    // 무한 루프 방지. 512 beat x 3 버스트 x 최악 지연을 넉넉히 덮습니다.
    initial begin
        #20_000_000;
        $display("FAIL: 타임아웃");
        $finish;
    end

endmodule
