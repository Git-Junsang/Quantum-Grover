//=====================================================================
// tb_grover_amp.v -- 진폭 배열을 직접 들여다보는 데이터패스 검증 (소유자 C)
//
// CSR 로는 진폭을 읽을 수 없으므로 amp_mem 을 계층 참조로 평탄화해 봅니다.
// 골든 벡터가 나오기 전까지 확산·오라클이 실제로 증폭을 하는지 확인하는
// 자리이고, 벡터가 나오면 여기에 expect_amp_j*.hex 전 워드 비교가 붙습니다.
//
// n=8 (N=256, 뱅크당 8행) 로 돌립니다. 확인하는 것 넷입니다.
//   1. INIT 직후 전 칸이 초기 진폭과 같은가 (n=8 이면 4096, 오차 0)
//   2. 노름이 보존되는가 -- 제곱합이 1.0(Q4.32 에서 2^32) 근방인가
//   3. 최적 반복수 j = floor(pi/4 * sqrt(N/M)) 에서 해의 확률이 90% 를 넘는가
//   4. 그 확률이 j 를 더 늘리면 다시 떨어지는가 (과회전 -- 증폭이 회전임을
//      보이는 증거이고, 우연히 커진 값이 아님을 말해 줍니다)
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module tb_grover_amp;
    localparam NQ    = 8;
    localparam NW    = 1 << NQ;                 // 256
    localparam ROWS  = NW / `GP_P;              // 8
    localparam SEED  = 32'h0BAD_C0DE;

    localparam A_MODE = 8'h00, A_THR_A = 8'h08, A_THR_B = 8'h10, A_NQ = 8'h18,
               A_ENUM = 8'h20, A_AUTO  = 8'h28, A_JTGT  = 8'h30,
               A_DWORDS= 8'h40, A_DSEED = 8'h48, A_DSEL = 8'h50,
               A_LOAD  = 8'h60, A_FINIT = 8'h68, A_START= 8'h70,
               A_STAT  = 8'h78, A_CAND  = 8'h80;

    reg clk = 0, rstn = 0;
    always #5 clk = ~clk;

    reg         psel = 0, penable = 0, pwrite = 0;
    reg  [7:0]  paddr = 0;
    reg  [31:0] pwdata = 0;
    wire [31:0] prdata;

    integer errors = 0;
    integer i, j;

    grover_top dut (
        .clk(clk), .rstn(rstn),
        .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr),
        .pwdata(pwdata), .prdata(prdata), .pready(), .pslverr(),
        .haddr(), .htrans(), .hwrite(), .hsize(), .hburst(), .hprot(), .hwdata(),
        .hready(1'b1), .hresp(1'b0), .hrdata(32'd0),
        .res_pop(1'b0), .res_dout(), .res_empty(), .res_count()
    );

    // amp_mem 을 인덱스 순으로 평탄화합니다. 뱅크와 행이 둘 다 상수여야
    // 계층 참조가 되므로 generate 로 폅니다.
    wire signed [`GP_DW-1:0] amp_flat [0:NW-1];
    genvar gb, gr;
    generate
        for (gb = 0; gb < `GP_P; gb = gb + 1) begin : g_pb
            for (gr = 0; gr < ROWS; gr = gr + 1) begin : g_pr
                assign amp_flat[gr*`GP_P + gb] = dut.u_amp.g_bank[gb].mem[gr];
            end
        end
    endgenerate

    task apb_write(input [7:0] a, input [31:0] d);
        begin
            @(posedge clk); #1; psel = 1; pwrite = 1; paddr = a; pwdata = d; penable = 0;
            @(posedge clk); #1; penable = 1;
            @(posedge clk); #1; psel = 0; penable = 0; pwrite = 0;
        end
    endtask

    task apb_read(input [7:0] a, output [31:0] d);
        begin
            @(posedge clk); #1; psel = 1; pwrite = 0; paddr = a; penable = 0;
            @(posedge clk); #1; penable = 1; #1; d = prdata;
            @(posedge clk); #1; psel = 0; penable = 0;
        end
    endtask

    task poll_idle;
        reg [31:0] s;
        integer n;
        begin
            n = 0; s = 32'd1;
            while (s[0] && n < 200000) begin apb_read(A_STAT, s); n = n + 1; end
            if (s[0]) begin $display("FAIL busy 가 안 내려갑니다"); $fatal; end
        end
    endtask

    // 해의 확률을 백분율로. 제곱합은 64비트면 충분합니다 (2^36 x 256).
    function integer prob_pct(input integer sol);
        reg [63:0] tot, sq;
        integer k;
        reg signed [63:0] a;
        begin
            tot = 0;
            for (k = 0; k < NW; k = k + 1) begin
                a = amp_flat[k];
                tot = tot + a*a;
            end
            a = amp_flat[sol];
            sq = a*a;
            prob_pct = (sq * 100) / tot;
        end
    endfunction

    function [63:0] norm_sq(input dummy);
        integer k;
        reg signed [63:0] a;
        reg [63:0] t;
        begin
            t = 0;
            for (k = 0; k < NW; k = k + 1) begin a = amp_flat[k]; t = t + a*a; end
            norm_sq = t;
        end
    endfunction

    reg signed [15:0] dat [0:NW-1];
    reg [31:0] x;
    integer sol, occ, best_pct, pct_at [0:31];
    reg signed [15:0] target;

    initial begin
        // 값이 정확히 한 번만 나오는 자리를 골라 M=1 을 만듭니다
        x = SEED;
        for (i = 0; i < NW; i = i + 2) begin
            x = x ^ (x << 13); x = x ^ (x >> 17); x = x ^ (x << 5);
            dat[i]   = x[15:0];      // 하위 16비트가 짝수 인덱스
            dat[i+1] = x[31:16];
        end
        sol = -1;
        for (i = 0; i < NW && sol < 0; i = i + 1) begin
            occ = 0;
            for (j = 0; j < NW; j = j + 1) if (dat[j] == dat[i]) occ = occ + 1;
            if (occ == 1) sol = i;
        end
        if (sol < 0) begin $display("FAIL 유일한 값을 못 찾았습니다"); $fatal; end
        target = dat[sol];
        $display("  해: 인덱스 %0d, 값 %0d (M=1)", sol, target);

        repeat (5) @(posedge clk); #1; rstn = 1;
        repeat (5) @(posedge clk);

        apb_write(A_NQ,     NQ);
        apb_write(A_DSEL,   32'd1);
        apb_write(A_DSEED,  SEED);
        apb_write(A_DWORDS, NW/2);   // CSR 은 32비트 워드 수
        apb_write(A_ENUM,   32'd0);
        apb_write(A_MODE,   32'd2);              // EQ
        apb_write(A_THR_A,  {16'd0, target});
        apb_write(A_THR_B,  32'd0);
        apb_write(A_AUTO,   32'd0);              // 펌웨어 구동 모드
        apb_write(A_LOAD,   32'd0);
        poll_idle;

        // ── 1. INIT 직후 ────────────────────────────────────────────
        apb_write(A_FINIT, 32'd0);
        apb_write(A_JTGT,  32'd0);
        apb_write(A_START, 32'd0);
        poll_idle;
        for (i = 0; i < NW; i = i + 1)
            if (amp_flat[i] !== 18'sd4096) begin
                errors = errors + 1;
                $display("FAIL INIT: amp[%0d]=%0d, 4096 이어야 합니다", i, amp_flat[i]);
                i = NW;
            end
        $display("  j= 0  노름제곱=%0d (2^32=%0d), 해 확률=%0d%%",
                 norm_sq(1'b0), 64'd4294967296, prob_pct(sol));

        // ── 2·3·4. j 를 늘려 가며 확률 추적 ─────────────────────────
        best_pct = 0;
        for (j = 1; j <= 20; j = j + 1) begin
            apb_write(A_JTGT,  j);
            apb_write(A_START, 32'd0);
            poll_idle;
            pct_at[j] = prob_pct(sol);
            if (pct_at[j] > best_pct) best_pct = pct_at[j];
            $display("  j=%2d  노름제곱=%0d  해 확률=%0d%%", j, norm_sq(1'b0), pct_at[j]);
            // 노름은 회전이므로 보존되어야 합니다. 5% 안쪽이면 통과로 봅니다.
            if (norm_sq(1'b0) < 64'd4080000000 || norm_sq(1'b0) > 64'd4510000000) begin
                errors = errors + 1;
                $display("FAIL j=%0d 에서 노름이 무너졌습니다 (%0d)", j, norm_sq(1'b0));
            end
        end

        // 최적 반복수 floor(pi/4 * sqrt(256)) = 12 근방에서 90% 를 넘어야 합니다
        if (best_pct < 90) begin
            errors = errors + 1;
            $display("FAIL 최대 확률이 %0d%% 뿐입니다 -- 증폭이 안 되고 있습니다", best_pct);
        end
        // 과회전 -- 최적을 지나면 다시 떨어져야 합니다
        if (pct_at[20] >= best_pct) begin
            errors = errors + 1;
            $display("FAIL j=20 에서 확률이 안 떨어집니다 -- 회전이 아닙니다");
        end

        apb_read(A_STAT, x);
        if (x[4]) begin
            errors = errors + 1; $display("FAIL sat_sticky 가 섰습니다");
        end

        if (errors == 0) $display("tb_grover_amp: PASS (최대 확률 %0d%%)", best_pct);
        else begin $display("tb_grover_amp: FAIL (%0d errors)", errors); $fatal; end
        $finish;
    end

    initial begin #20_000_000; $display("tb_grover_amp: TIMEOUT"); $fatal; end
endmodule
