//=====================================================================
// tb_bbht_rvx.v -- 통신 계층 회귀 테스트벤치
//
// 검증 대상은 bbht_grover_mmio + bbht_ahb_loader + bbht_rvx_wrapper 이고,
// Main IP 자리에는 스텁이 들어갑니다. 그래서 여기서 통과한다는 것은
// "통신 계층이 인수인계 계약을 지킨다" 는 뜻이지 "탐색이 맞다" 는 뜻이
// 아닙니다. 후자는 PJK 의 실물 IP 로만 확인됩니다.
//
// 확인하는 것 아홉 가지:
//   T1  RW 레지스터 write-read 라운드트립
//   T2  W1P 레지스터는 읽으면 0
//   T3  정렬 위반 / 미할당 주소는 pslverr
//   T4  DMA 정상 경로 + 16비트 매핑 (word[k][15:0] -> data[2k])
//   T5  DMA 거절 -- 정렬 / 개수 / 범위
//   T6  Single 탐색: done_sticky, result_valid, RESULT_INDEX
//   T7  done_sticky 는 COMMAND 쓰기로만 클리어
//   T8  Enumeration: FIFO read-to-pop, FIFO_COUNT 감소, 인덱스 0 도 정상값
//   T9  start 수락 조건 -- 직전 결과를 안 읽고 다시 start 하면 거절
//=====================================================================
`timescale 1ns/1ps
`include "bbht_grover_csr.vh"

// STATUS 폴링 상한 (apb_read 한 번이 3사이클).
`ifndef GUARD_POLLS
  `define GUARD_POLLS 20000
`endif

// 전역 워치독 (ns). 100 MHz 이므로 5_000_000 ns = 50만 사이클입니다.
`ifndef SIM_TIMEOUT_NS
  `define SIM_TIMEOUT_NS 5_000_000
`endif

module tb_bbht_rvx;

    localparam [31:0] SRAM_BASE = 32'hE000_0000;
    localparam [31:0] SRAM_LAST = 32'hE001_FFFF;

    reg clk = 1'b0;
    reg rstnn = 1'b0;
    always #5 clk = ~clk;              // 100 MHz

    integer errors = 0;

    //-----------------------------------------------------------------
    // APB
    //-----------------------------------------------------------------
    reg         psel = 1'b0;
    reg         penable = 1'b0;
    reg         pwrite = 1'b0;
    reg  [31:0] paddr = 32'd0;
    reg  [31:0] pwdata = 32'd0;
    wire        pready;
    wire [31:0] prdata;
    wire        pslverr;

    //-----------------------------------------------------------------
    // AHB
    //-----------------------------------------------------------------
    wire [31:0] shaddr;
    wire [2:0]  shburst;
    wire        shmasterlock;
    wire [3:0]  shprot;
    wire [2:0]  shsize;
    wire [1:0]  shtrans;
    wire        shwrite;
    wire [31:0] shwdata;
    wire        shready;
    wire [31:0] shrdata;
    wire        shresp;

    reg         bk_we = 1'b0;
    reg  [31:0] bk_addr = 32'd0;
    reg  [31:0] bk_data = 32'd0;

    bbht_rvx_wrapper #(
        .SRAM_BASE (SRAM_BASE),
        .SRAM_LAST (SRAM_LAST)
    ) dut (
        .clk (clk), .rstnn (rstnn),
        .psel (psel), .penable (penable), .pwrite (pwrite),
        .paddr (paddr), .pwdata (pwdata),
        .pready (pready), .prdata (prdata), .pslverr (pslverr),
        .shready (shready), .shrdata (shrdata), .shresp (shresp),
        .shaddr (shaddr), .shburst (shburst), .shmasterlock (shmasterlock),
        .shprot (shprot), .shsize (shsize), .shtrans (shtrans),
        .shwrite (shwrite), .shwdata (shwdata)
    );

    // 대기 사이클을 1 로 둡니다. loader 가 shready 를 제대로 기다리는지
    // (주소 위상을 놓치지 않는지) 확인하는 것이 목적입니다.
    ahb_sram_model #(
        .BASE_ADDR   (SRAM_BASE),
        .WORDS       (256),
        .WAIT_CYCLES (1)
    ) sram (
        .clk (clk), .rstnn (rstnn),
        .haddr (shaddr), .htrans (shtrans), .hwrite (shwrite),
        .hsize (shsize), .hburst (shburst), .hwdata (shwdata),
        .hready (shready), .hresp (shresp), .hrdata (shrdata),
        .bk_we (bk_we), .bk_addr (bk_addr), .bk_data (bk_data)
    );

    //-----------------------------------------------------------------
    // APB 마스터
    //
    // pready 가 상수 1 이므로 access 위상이 정확히 한 사이클입니다.
    //
    // 자극은 전부 negedge 에서 줍니다. posedge 에서 주면 DUT 가 같은 에지에
    // 그 값을 보게 되어 전송이 한 사이클 당겨지고, FIFO_DATA 처럼 읽기에
    // 부작용이 있는 레지스터에서 pop 이 샘플링보다 먼저 일어납니다.
    //-----------------------------------------------------------------
    task apb_write(input [31:0] off, input [31:0] data);
    begin
        @(negedge clk);
        psel = 1'b1; penable = 1'b0; pwrite = 1'b1;
        paddr = off; pwdata = data;
        @(negedge clk);
        penable = 1'b1;               // access 위상. 다음 posedge 에서 완료
        @(negedge clk);
        psel = 1'b0; penable = 1'b0; pwrite = 1'b0;
    end
    endtask

    task apb_read(input [31:0] off, output [31:0] data);
    begin
        @(negedge clk);
        psel = 1'b1; penable = 1'b0; pwrite = 1'b0; paddr = off;
        @(negedge clk);
        penable = 1'b1;
        #1 data = prdata;             // access 위상 안. 완료 posedge 이전
        @(negedge clk);
        psel = 1'b0; penable = 1'b0;
    end
    endtask

    task check(input [255:0] name, input [31:0] got, input [31:0] exp);
    begin
        if (got !== exp) begin
            $display("  FAIL %0s : got 0x%08x, expected 0x%08x", name, got, exp);
            errors = errors + 1;
        end else begin
            $display("  ok   %0s = 0x%08x", name, got);
        end
    end
    endtask

    //-----------------------------------------------------------------
    // 테스트 데이터
    //   data[i] = i * 3   (i = 0..63)
    //   EQ 33  -> 인덱스 11 하나
    //   GT 180 -> 인덱스 61,62,63 셋 (183,186,189)
    //-----------------------------------------------------------------
    localparam integer NDATA = 64;

    task fill_sram;
        integer k;
        reg [15:0] lo, hi;
    begin
        for (k = 0; k < NDATA/2; k = k + 1) begin
            lo = 16'((2*k)     * 3);
            hi = 16'((2*k + 1) * 3);
            @(negedge clk);
            bk_we = 1'b1;
            bk_addr = SRAM_BASE + k*4;
            bk_data = {hi, lo};
        end
        @(negedge clk);
        bk_we = 1'b0;
    end
    endtask

    task do_dma(input [31:0] addr, input [31:0] count, output [31:0] st);
        integer guard;
    begin
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_DATA_ADDR,   addr);
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_DATA_COUNT,  count);
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_DMA_COMMAND, 32'd1);
        guard = 0;
        st = 32'd0;
        // 폴링 상한. 스텁은 101 사이클에 끝나지만 실물 Main IP 는 탐색 한
        // 번이 수십만 사이클입니다. 빌드에서 -DGUARD_POLLS 로 올립니다.
        while (guard < `GUARD_POLLS) begin
            apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_DMA_STATUS, st);
            if (st[`BBHT_DMA_DMA_DONE_STICKY] || st[`BBHT_DMA_DMA_ERROR])
                guard = `GUARD_POLLS;
            else
                guard = guard + 1;
        end
    end
    endtask

    // 실행 카운터 일괄 덤프. 합격/불합격 판정이 아니라 RVX 실행 결과와
    // 맞춰 보기 위한 기록입니다. 스텁은 대부분 0 을 냅니다.
    task dump_counters(input [255:0] tag);
        reg [31:0] v;
    begin
        $display("  -- 카운터 [%0s]", tag);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_TRIAL_COUNT,  v);
        $display("     trial_count              = %0d", v);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_L_BBHT,       v);
        $display("     L_BBHT                   = %0d", v);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_ACTUAL_ITER,  v);
        $display("     actual_grover_iterations = %0d", v);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_CYCLE_COUNT,  v);
        $display("     cycle_count              = %0d", v);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_POLICY_CYCLES_TOTAL, v);
        $display("     policy_cycles_total      = %0d", v);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_POLICY_STALL_CYCLES,  v);
        $display("     policy_stall_cycles      = %0d", v);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_POLICY_ACTIONS_EVAL, v);
        $display("     policy_actions_eval      = %0d", v);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_POLICY_MEMO_HIT,  v);
        $display("     policy_memo_hit          = %0d", v);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_POLICY_MEMO_MISS, v);
        $display("     policy_memo_miss         = %0d", v);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_PLAN_FIFO_HIT_COUNT,      v);
        $display("     plan_fifo_hit_count      = %0d", v);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_PLAN_FIFO_EMPTY_DEMAND,    v);
        $display("     plan_fifo_empty_demand   = %0d", v);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_PLAN_FIFO_MISMATCH_COUNT, v);
        $display("     plan_fifo_mismatch_count = %0d", v);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_PLAN_FIFO_HIGHWATER,     v);
        $display("     plan_fifo_highwater      = %0d", v);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_POLICY_COLD_SOLVE_COUNT,  v);
        $display("     policy_cold_solve_count  = %0d", v);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_POLICY_SPEC_SOLVE_COUNT,  v);
        $display("     policy_spec_solve_count  = %0d", v);
    end
    endtask

    task wait_done(output [31:0] st);
        integer guard;
    begin
        guard = 0;
        st = 32'd0;
        // 폴링 상한. 스텁은 101 사이클에 끝나지만 실물 Main IP 는 탐색 한
        // 번이 수십만 사이클입니다. 빌드에서 -DGUARD_POLLS 로 올립니다.
        while (guard < `GUARD_POLLS) begin
            apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_STATUS, st);
            if (st[`BBHT_ST_DONE_STICKY]) guard = `GUARD_POLLS;
            else guard = guard + 1;
        end
    end
    endtask

    //-----------------------------------------------------------------
    reg [31:0] d, st;
    reg [2:0]  seen;                   // 열거 결과 집합 확인용
    integer    i;

    initial begin
        $display("=== tb_bbht_rvx : 통신 계층 회귀 ===");
        repeat (5) @(negedge clk);
        rstnn = 1'b1;
        repeat (5) @(negedge clk);

        //-------------------------------------------------------------
        $display("[T1] RW 라운드트립");
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_CONTROL,     32'h0000000B);
        apb_read (`BBHT_CSR_STRIDE * `CSR_IDX_CONTROL,     d);
        check("CONTROL", d, 32'h0000000B);

        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_THRESHOLD_A, 32'h0000FFFF);   // -1
        apb_read (`BBHT_CSR_STRIDE * `CSR_IDX_THRESHOLD_A, d);
        check("THRESHOLD_A(-1)", d, 32'h0000FFFF);

        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_SEED_J,      32'hDEADBEEF);
        apb_read (`BBHT_CSR_STRIDE * `CSR_IDX_SEED_J,      d);
        check("SEED_J", d, 32'hDEADBEEF);

        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_SHOT_CAP,    32'd12345);
        apb_read (`BBHT_CSR_STRIDE * `CSR_IDX_SHOT_CAP,    d);
        check("SHOT_CAP", d, 32'd12345);

        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_ENUM_CFG,    32'h00000041);   // limit=4, enable=1
        apb_read (`BBHT_CSR_STRIDE * `CSR_IDX_ENUM_CFG,    d);
        check("ENUM_CFG", d, 32'h00000041);
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_ENUM_CFG,    32'h00000040);   // 다시 Single

        // J_TARGET 은 7비트라 상위가 잘려야 합니다.
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_J_TARGET,    32'hFFFFFFFF);
        apb_read (`BBHT_CSR_STRIDE * `CSR_IDX_J_TARGET,    d);
        check("J_TARGET(7b clip)", d, 32'd127);

        //-------------------------------------------------------------
        $display("[T2] W1P 는 읽으면 0");
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_COMMAND,     d);
        check("COMMAND rd", d, 32'd0);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_DMA_COMMAND, d);
        check("DMA_COMMAND rd", d, 32'd0);
        // COMMAND 를 읽는 것만으로 탐색이 시작되면 안 됩니다.
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_STATUS, d);
        if (d[`BBHT_ST_BUSY] || d[`BBHT_ST_DONE_STICKY]) begin
            $display("  FAIL COMMAND 읽기가 탐색을 시작시켰습니다 (STATUS=0x%08x)", d);
            errors = errors + 1;
        end else $display("  ok   COMMAND 읽기는 부작용 없음");

        //-------------------------------------------------------------
        $display("[T3] 정렬 위반 / 미할당 주소");
        @(negedge clk);
        psel = 1'b1; penable = 1'b0; pwrite = 1'b0; paddr = 32'h00000002;
        @(negedge clk);
        penable = 1'b1;
        #1;
        if (!pslverr) begin
            $display("  FAIL 정렬 위반(0x002)에 pslverr 가 안 섰습니다");
            errors = errors + 1;
        end else $display("  ok   정렬 위반 -> pslverr");
        @(negedge clk); psel = 1'b0; penable = 1'b0;

        @(negedge clk);
        psel = 1'b1; penable = 1'b0; pwrite = 1'b0; paddr = 32'h00000800;
        @(negedge clk);
        penable = 1'b1;
        #1;
        if (!pslverr) begin
            $display("  FAIL 미할당 주소(0x800)에 pslverr 가 안 섰습니다");
            errors = errors + 1;
        end else $display("  ok   미할당 주소 -> pslverr");
        @(negedge clk); psel = 1'b0; penable = 1'b0;

        //-------------------------------------------------------------
        $display("[T4] DMA 정상 경로");
        fill_sram;
        do_dma(SRAM_BASE, NDATA, st);
        check("DMA_STATUS", st, 32'h00000080);      // done_sticky 만

        //-------------------------------------------------------------
        $display("[T5] DMA 거절");
        do_dma(SRAM_BASE + 32'd2, NDATA, st);       // 정렬 위반
        if (!st[`BBHT_DMA_ALIGN_ERROR] || !st[`BBHT_DMA_DMA_ERROR]) begin
            $display("  FAIL 정렬 위반 DMA 가 거절되지 않았습니다 (0x%08x)", st);
            errors = errors + 1;
        end else $display("  ok   정렬 위반 -> align_error");

        do_dma(SRAM_BASE, 32'd0, st);               // 개수 0
        if (!st[`BBHT_DMA_COUNT_ERROR]) begin
            $display("  FAIL count=0 DMA 가 거절되지 않았습니다 (0x%08x)", st);
            errors = errors + 1;
        end else $display("  ok   count=0 -> count_error");

        do_dma(32'hF000_0000, NDATA, st);           // 범위 밖
        if (!st[`BBHT_DMA_RANGE_ERROR]) begin
            $display("  FAIL 범위 밖 DMA 가 거절되지 않았습니다 (0x%08x)", st);
            errors = errors + 1;
        end else $display("  ok   범위 밖 -> range_error");

        // 다시 정상 적재로 되돌립니다.
        do_dma(SRAM_BASE, NDATA, st);
        check("DMA_STATUS 복구", st, 32'h00000080);

        //-------------------------------------------------------------
        $display("[T6] Single 탐색 -- EQ 33 은 인덱스 11");
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_CONTROL,
                  {28'd0, `BBHT_PRED_EQ, 1'b0, 1'b1});     // auto=1, burst=0, EQ
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_THRESHOLD_A, 32'd33);
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_DATA_COUNT,  NDATA);
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_ENUM_CFG,    32'h00000040);
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_COMMAND,     32'd1);
        wait_done(st);
        if (!st[`BBHT_ST_RESULT_VALID]) begin
            $display("  FAIL result_valid 가 안 섰습니다 (STATUS=0x%08x)", st);
            errors = errors + 1;
        end else $display("  ok   result_valid");
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_RESULT_INDEX, d);
        check("RESULT_INDEX", d, 32'd11);
        dump_counters("T6 single");
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_CYCLE_COUNT, d);
        if (d == 32'd0) begin
            $display("  FAIL CYCLE_COUNT 가 0 입니다");
            errors = errors + 1;
        end else $display("  ok   CYCLE_COUNT = %0d", d);

        //-------------------------------------------------------------
        $display("[T7] done_sticky 는 COMMAND 쓰기로만 클리어");
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_STATUS, d);
        if (!d[`BBHT_ST_DONE_STICKY]) begin
            $display("  FAIL STATUS 읽기가 done_sticky 를 지웠습니다");
            errors = errors + 1;
        end else $display("  ok   STATUS 읽기는 done_sticky 를 안 지움");

        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_THRESHOLD_A, 32'd33);
        apb_read (`BBHT_CSR_STRIDE * `CSR_IDX_STATUS, d);
        if (!d[`BBHT_ST_DONE_STICKY]) begin
            $display("  FAIL 설정 레지스터 쓰기가 done_sticky 를 지웠습니다");
            errors = errors + 1;
        end else $display("  ok   설정 쓰기는 done_sticky 를 안 지움");

        //-------------------------------------------------------------
        $display("[T9] start 수락 -- 직전 결과가 남은 채로 다시 start");
        // done_sticky 가 선 상태에서 COMMAND 를 쓰면, 그 쓰기가 sticky 를
        // 지우고 start 가 수락되는 것이 정상 동작입니다. 여기서 확인하는
        // 것은 "새 실행이 직전 결과 위에 겹치지 않는다" 는 쪽입니다.
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_CONTROL,
                  {28'd0, `BBHT_PRED_EQ, 1'b0, 1'b1});
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_THRESHOLD_A, 32'd999);   // 없는 값
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_COMMAND,     32'd1);
        wait_done(st);
        if (st[`BBHT_ST_RESULT_VALID]) begin
            $display("  FAIL 못 찾았는데 result_valid 가 남아 있습니다 (0x%08x)", st);
            errors = errors + 1;
        end else $display("  ok   새 실행이 직전 result_valid 를 지웠음");

        //-------------------------------------------------------------
`ifdef SKIP_ENUM
        $display("[T8] Enumeration -- 건너뜀 (SKIP_ENUM)");
`else
        $display("[T8] Enumeration -- GT 180 은 61,62,63");
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_CONTROL,
                  {28'd0, `BBHT_PRED_GT, 1'b0, 1'b1});
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_THRESHOLD_A, 32'd180);
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_ENUM_CFG,    32'h00000041);  // enable, limit 4
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_COMMAND,     32'd1);
        wait_done(st);
        if (!st[`BBHT_ST_ENUM_DONE]) begin
            $display("  FAIL enum_done 이 안 섰습니다 (0x%08x)", st);
            errors = errors + 1;
        end else $display("  ok   enum_done");

        dump_counters("T8 enum");
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_FOUND_COUNT, d);
        check("FOUND_COUNT", d, 32'd3);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_FIFO_COUNT, d);
        check("FIFO_COUNT", d, 32'd3);

        // read-to-pop. FIFO_COUNT 가 읽을 때마다 하나씩 줄어야 합니다.
        //
        // 순서는 검사하지 않고 집합만 봅니다. 열거는 Born 측정이 뽑아 낸
        // 발견 순서대로 FIFO 에 들어가므로 오름차순이 아닙니다. 스텁이
        // 선형 스캔이라 61,62,63 순으로 나왔을 뿐입니다.
        seen = 3'b000;
        for (i = 0; i < 3; i = i + 1) begin
            apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_FIFO_DATA, d);
            if (d >= 61 && d <= 63) seen[d - 61] = 1'b1;
            else begin
                $display("  FAIL FIFO_DATA : 61~63 밖의 값 %0d", d);
                errors = errors + 1;
            end
            apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_FIFO_COUNT, st);
            check("FIFO_COUNT after pop", st, 2 - i);
        end
        if (seen != 3'b111) begin
            $display("  FAIL 열거 집합이 {61,62,63} 이 아닙니다 (seen=%b)", seen);
            errors = errors + 1;
        end else $display("  ok   열거 집합 {61,62,63} (순서 무관)");

        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_STATUS, d);
        if (!d[`BBHT_ST_FIFO_EMPTY]) begin
            $display("  FAIL drain 후 fifo_empty 가 안 섰습니다 (0x%08x)", d);
            errors = errors + 1;
        end else $display("  ok   drain 후 fifo_empty");

        // 인덱스 0 이 정상 결과일 수 있음을 확인합니다. LT 3 은 data[0]=0 하나.
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_CONTROL,
                  {28'd0, `BBHT_PRED_LT, 1'b0, 1'b1});
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_THRESHOLD_A, 32'd3);
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_COMMAND,     32'd1);
        wait_done(st);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_FIFO_COUNT, d);
        check("FIFO_COUNT (idx 0 만)", d, 32'd1);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_FIFO_DATA, d);
        check("FIFO_DATA = 0 은 정상값", d, 32'd0);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_STATUS, d);
        if (!d[`BBHT_ST_FIFO_EMPTY]) begin
            $display("  FAIL 인덱스 0 을 pop 한 뒤 fifo_empty 가 안 섰습니다");
            errors = errors + 1;
        end else $display("  ok   인덱스 0 pop 후 fifo_empty");
`endif

        //-------------------------------------------------------------
        // [T10] Normal vs K4 체크포인트 -- 같은 자극, burst 비트만 다름
        //
        // wrapper 가 checkpoint_auto_enable = burst_enable & auto_shot 로
        // 묶어 두었으므로 CONTROL 비트1 하나가 두 모드를 가릅니다.
        // T6 과 완전히 같은 조건(EQ 33, seed 고정)이라 두 카운터를 그대로
        // 짝지어 비교할 수 있습니다. 판정은 하지 않고 기록만 합니다.
        $display("[T10] Normal vs K4 -- EQ 33, 같은 seed");

        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_ENUM_CFG,    32'h00000040);
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_THRESHOLD_A, 32'd33);
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_DATA_COUNT,  NDATA);

        // Normal : auto_shot=1, burst=0
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_CONTROL,
                  {28'd0, `BBHT_PRED_EQ, 1'b0, 1'b1});
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_COMMAND, 32'd1);
        wait_done(st);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_RESULT_INDEX, d);
        check("Normal RESULT_INDEX", d, 32'd11);
        dump_counters("T10 normal");

        // K4 : auto_shot=1, burst=1 -> checkpoint_auto_enable
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_CONTROL,
                  {28'd0, `BBHT_PRED_EQ, 1'b1, 1'b1});
        apb_write(`BBHT_CSR_STRIDE * `CSR_IDX_COMMAND, 32'd1);
        wait_done(st);
        apb_read(`BBHT_CSR_STRIDE * `CSR_IDX_RESULT_INDEX, d);
        check("K4 RESULT_INDEX", d, 32'd11);
        dump_counters("T10 K4");

        //-------------------------------------------------------------
        repeat (10) @(negedge clk);
        $display("=== 결과: 오류 %0d 건 ===", errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $finish;
    end

    // 무한 루프 방지
    initial begin
        #`SIM_TIMEOUT_NS;
        $display("FAIL: 타임아웃");
        $finish;
    end

endmodule
