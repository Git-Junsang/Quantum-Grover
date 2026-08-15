//=====================================================================
// tb_grover_top.v -- IP 전체 end-to-end (통합 지점 1·2 의 뼈대)
//
// 골든 벡터가 아직 없으므로(software/golden/ 은 스프린트 1) 여기서는
// 벡터 없이도 성립하는 성질들을 확인합니다.
//
//   1. 온칩 생성기로 data_mem 을 채우고 BBHT 자율 모드로 탐색한 결과가
//      정말 술어를 만족하는 인덱스인가. 테스트벤치가 xorshift 를 같은
//      규칙으로 재생해 스스로 답을 알고 있습니다.
//   2. 측정 중에 amp_we 가 한 번도 서지 않는가. 이 한 줄이 재개 캐시가
//      성립하는 물리적 근거이고, 깨지면 캐시의 정당화가 통째로 무너집니다.
//   3. 펌웨어 구동 모드에서 재개가 실제로 일을 줄이는가.
//      j=3 을 돌린 뒤 j=5 를 요청하면 반복 2회분만 돌아야 합니다.
//   4. ● 레지스터에 쓰면 그 자리에서 캐시가 무효화되는가.
//
// 골든 모델이 나오면 여기에 expect_amp_j*.hex 전 워드 비교가 붙습니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module tb_grover_top;
    localparam NB = `GP_NB;

    // CSR 오프셋 (통신_명령_데이터패스.md 3.3절)
    localparam A_MODE = 8'h00, A_THR_A = 8'h08, A_THR_B = 8'h10, A_NQ = 8'h18,
               A_ENUM = 8'h20, A_AUTO  = 8'h28, A_JTGT  = 8'h30,
               A_DADDR= 8'h38, A_DWORDS= 8'h40, A_DSEED = 8'h48, A_DSEL = 8'h50,
               A_CLRM = 8'h58, A_LOAD  = 8'h60, A_FINIT = 8'h68, A_START= 8'h70,
               A_STAT = 8'h78, A_CAND  = 8'h80, A_JCUR  = 8'h88,
               A_CYC  = 8'h90, A_PASS  = 8'h98;

    reg clk = 0, rstn = 0;
    always #5 clk = ~clk;

    reg         psel = 0, penable = 0, pwrite = 0;
    reg  [7:0]  paddr = 0;
    reg  [31:0] pwdata = 0;
    wire [31:0] prdata;
    wire        pready, pslverr;

    wire [31:0] haddr, hwdata;
    wire [1:0]  htrans;
    wire        hwrite;
    wire [2:0]  hsize, hburst;
    wire [3:0]  hprot;

    integer errors = 0;
    integer i;

    grover_top dut (
        .clk(clk), .rstn(rstn),
        .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr),
        .pwdata(pwdata), .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .haddr(haddr), .htrans(htrans), .hwrite(hwrite), .hsize(hsize),
        .hburst(hburst), .hprot(hprot), .hwdata(hwdata),
        .hready(1'b1), .hresp(1'b0), .hrdata(32'd0),
        .res_pop(1'b0), .res_dout(), .res_empty(), .res_count()
    );

    // ── 성질 2 -- 측정 중에는 진폭에 쓰지 않는다 ─────────────────────
    always @(posedge clk) if (rstn && dut.meas_busy && dut.amp_we) begin
        errors = errors + 1;
        $display("FAIL 측정 중에 amp_we 가 섰습니다 -- 재개 캐시의 근거가 깨집니다");
    end

    // ── APB ──────────────────────────────────────────────────────────
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
            @(posedge clk); #1; penable = 1;
            #1; d = prdata;
            @(posedge clk); #1; psel = 0; penable = 0;
        end
    endtask

    // 완료 판정은 done 이 서는 것이 아니라 busy 가 내려가는 것으로 합니다
    task poll_idle(input integer limit);
        reg [31:0] s;
        integer n;
        begin
            n = 0;
            s = 32'd1;
            while (s[0] && n < limit) begin
                apb_read(A_STAT, s);
                n = n + 1;
            end
            if (s[0]) begin
                $display("FAIL busy 가 내려가지 않습니다"); $fatal;
            end
        end
    endtask

    // ── 테스트벤치가 재생하는 xorshift 데이터 ────────────────────────
    localparam NW   = 256;           // n=8. 회귀를 짧게 유지하려는 값입니다
    localparam SEED = 32'h1234_5678;
    reg signed [15:0] dat [0:NW-1];
    reg [31:0] x;
    integer maxv, cntM;
    reg signed [15:0] thr;

    reg [31:0] s, c, cyc1, cyc2, pass1, pass2, jcur;

    initial begin
        // 골든과 같은 규칙으로 배열을 재생합니다
        x = SEED;
        maxv = -32769;
        for (i = 0; i < NW; i = i + 2) begin
            x = x ^ (x << 13);
            x = x ^ (x >> 17);
            x = x ^ (x << 5);
            dat[i]   = x[15:0];      // 하위 16비트가 짝수 인덱스
            dat[i+1] = x[31:16];
            if (dat[i]   > maxv) maxv = dat[i];
            if (dat[i+1] > maxv) maxv = dat[i+1];
        end
        thr = maxv - 1;
        cntM = 0;
        for (i = 0; i < NW; i = i + 1) if (dat[i] > thr) cntM = cntM + 1;
        $display("  데이터 재생 완료: max=%0d, thr_a=%0d, M=%0d", maxv, thr, cntM);

        repeat (5) @(posedge clk); #1; rstn = 1;
        repeat (5) @(posedge clk);

        // ── 설정과 적재 ─────────────────────────────────────────────
        apb_write(A_NQ,     32'd8);
        apb_write(A_DSEL,   32'd1);          // 온칩 생성기
        apb_write(A_DSEED,  SEED);
        apb_write(A_DWORDS, NW/2);   // CSR 은 32비트 워드 수
        apb_write(A_ENUM,   32'd0);
        apb_write(A_THR_B,  32'd0);
        apb_write(A_MODE,   32'd1);          // GT
        apb_write(A_THR_A,  {16'd0, thr});
        apb_write(A_CLRM,   32'd0);          // 마스크 스윕은 즉시가 아닙니다
        poll_idle(100000);
        apb_write(A_LOAD,   32'd0);
        poll_idle(100000);

        // ── 성질 1 -- BBHT 자율 모드 탐색 ───────────────────────────
        apb_write(A_AUTO,  32'd1);
        apb_write(A_START, 32'd0);
        poll_idle(2000000);

        apb_read(A_STAT, s);
        apb_read(A_CAND, c);
        apb_read(A_CYC,  cyc1);
        apb_read(A_PASS, pass1);
        $display("  자율 모드: status=%b cand=%0d cycle_cnt=%0d passes_run=%0d",
                 s[5:0], c, cyc1, pass1);

        if (!s[2]) begin
            errors = errors + 1;
            $display("FAIL verify_hit 가 서지 않았습니다 (too_many=%0b)", s[5]);
        end else if (dat[c[7:0]] <= thr) begin
            errors = errors + 1;
            $display("FAIL 돌려준 인덱스 %0d 의 값 %0d 가 술어를 만족하지 않습니다",
                     c, dat[c[7:0]]);
        end else begin
            $display("  OK  인덱스 %0d 의 값 %0d > %0d", c, dat[c[7:0]], thr);
        end
        if (s[4]) begin
            errors = errors + 1;
            $display("FAIL sat_sticky 가 섰습니다 -- Q2.16 이 모자랍니다");
        end

        // ── 성질 3 -- 재개가 일을 줄이는가 ──────────────────────────
        apb_write(A_AUTO,  32'd0);           // 펌웨어 구동 모드
        apb_write(A_FINIT, 32'd0);           // 캐시를 버리고 시작
        apb_write(A_JTGT,  32'd3);
        apb_write(A_START, 32'd0);
        poll_idle(2000000);
        apb_read(A_PASS, pass1);
        apb_read(A_CYC,  cyc1);
        apb_read(A_JCUR, jcur);
        $display("  j_target=3 (초기화부터): passes_run=%0d cycle_cnt=%0d j_cur=%0d",
                 pass1, cyc1, jcur);
        if (pass1 !== 32'd6) begin
            errors = errors + 1;
            $display("FAIL 반복 3회면 패스 6회여야 합니다");
        end
        if (jcur !== 32'd3) begin
            errors = errors + 1; $display("FAIL j_cur 가 3 이 아닙니다");
        end

        // j_target 은 ● 가 아니므로 캐시가 살아 있어야 합니다
        apb_write(A_JTGT,  32'd5);
        apb_write(A_START, 32'd0);
        poll_idle(2000000);
        apb_read(A_PASS, pass2);
        apb_read(A_CYC,  cyc2);
        apb_read(A_JCUR, jcur);
        $display("  j_target=5 (재개):       passes_run=%0d cycle_cnt=%0d j_cur=%0d",
                 pass2, cyc2, jcur);
        if (pass2 !== 32'd4) begin
            errors = errors + 1;
            $display("FAIL 재개면 반복 2회 = 패스 4회여야 하는데 %0d 입니다", pass2);
        end
        if (cyc2 >= cyc1) begin
            errors = errors + 1;
            $display("FAIL 재개했는데 사이클이 줄지 않았습니다");
        end
        if (jcur !== 32'd5) begin
            errors = errors + 1; $display("FAIL j_cur 가 5 가 아닙니다");
        end

        // ── 성질 4 -- ● 레지스터 쓰기가 캐시를 무효화하는가 ─────────
        apb_read(A_STAT, s);
        if (!s[3]) begin
            errors = errors + 1; $display("FAIL 이 시점에 cache_valid 가 서 있어야 합니다");
        end
        apb_write(A_THR_A, {16'd0, thr});    // ● 레지스터
        apb_read(A_STAT, s);
        if (s[3]) begin
            errors = errors + 1;
            $display("FAIL thr_a 를 썼는데 cache_valid 가 안 내려갔습니다");
        end
        apb_write(A_JTGT,  32'd5);
        apb_write(A_START, 32'd0);
        poll_idle(2000000);
        apb_read(A_PASS, pass2);
        $display("  무효화 후 j_target=5:    passes_run=%0d", pass2);
        if (pass2 !== 32'd10) begin
            errors = errors + 1;
            $display("FAIL 무효화 뒤에는 5회 = 패스 10회를 돌아야 합니다");
        end

        if (errors == 0) $display("tb_grover_top: PASS");
        else begin $display("tb_grover_top: FAIL (%0d errors)", errors); $fatal; end
        $finish;
    end

    initial begin
        #50_000_000;
        $display("tb_grover_top: TIMEOUT");
        $fatal;
    end
endmodule
