//=====================================================================
// tb_bbht_bram_top.v -- hardware_bram 최상단 회귀 (호스트 경로 통째)
//
// 검증 대상은 src_comm/bbht_bram_top.v 입니다. 그 안에 CSR(mmio), 데이터셋
// DMA(loader), 보드 정본 Main IP(K3/H3-E4-M2)가 들어 있고, 바깥에는 둘만
// 붙습니다.
//
//   APB 마스터       이 테스트벤치의 태스크. RVX 위 펌웨어가 CSR 을 읽고
//                    쓰는 순서를 그대로 흉내 냅니다. 호스트 PC 의 UART
//                    명령(SET / LOAD / RUN / ENUM)은 펌웨어 안에서 결국 이
//                    순서가 됩니다 (documents/design_references/호스트_조작_방법.md)
//   ahb_sram_model   RVX System SRAM 흉내
//
// hardware_dram/testbench/tb_bbht_dram_top.v 와 짝입니다. 호스트 쪽 자극과
// 판정은 가능한 한 같게 두고, 갈래마다 다른 것만 바꿨습니다.
//
//   dram 쪽에만 있는 것   DRAM 모델, 버스트 겹침 감시, frontier_j 판정
//   bram 쪽에만 있는 것   열거(Enumeration) 와 결과 FIFO,
//                         NORMAL / CKPT 두 모드 짝 비교, 정책 텔레메트리
//
// 탐색 결과는 두 겹으로 확인합니다.
//   1. 호스트 쪽 판정   RESULT_INDEX 나 FIFO_DATA 가 가리키는 값이 이 TB 가
//                       SRAM 에 넣은 배열에서 정말 술어를 만족하는가
//   2. 모드 짝 비교     같은 설정·같은 시드를 NORMAL_SINGLE 과 CKPT_SINGLE
//                       로 한 번씩 돌려 궤적(valid/idx/trials/L_BBHT/상태
//                       비트)이 같은지 봅니다. 체크포인트는 psi 를 어떻게
//                       계산하느냐만 바꾸지 탐색 궤적을 바꾸지 않습니다
//                       (sim/Makefile 의 bench250 주석과 같은 불변식).
//                       result_index 만 보면 안 되는 이유도 거기 있습니다
//
// C1~C7 레이블·자극·시드는 hardware_dram/testbench/tb_dram_core.v 와 같습니다.
// NORMAL 판은 "CASE", 체크포인트 판은 "CKPT" 로 시작하는 줄을 찍으므로,
// 필요하면 그 파일의 bram 판 로그와 손으로 맞대 볼 수 있습니다 (CKPT 줄은
// 머리를 CASE 로 바꿔서).
//
// 확인하는 것
//   H1   RW 레지스터 write-read 라운드트립
//   H2   W1P 레지스터는 읽으면 0, COMMAND 를 읽어도 탐색이 안 시작됨
//   H3   정렬 위반 / 미할당 주소는 pslverr
//   H4   DMA 로 Q14 전체(16,384개) 적재 -- 매핑 검사용 배열 A
//   H5   16비트 매핑 -- 배열 A 에서 LT 256 은 짝수 인덱스만 정답
//   H6   DMA 거절. 정렬·범위 거절은 배열을 보존하고, 개수 거절은
//        DATA_COUNT 가 바뀌므로 배열을 무효화한다 (재적재 전 탐색은
//        config_error)
//   H7   재적재 (배열 B)
//   H8   C1~C3 -- 수동 / NORMAL / CKPT, 재실행
//   H9   done_sticky 는 COMMAND 쓰기로만 클리어
//   H10  탐색 중 DMA 는 busy_error, 탐색 중 COMMAND 는 버려짐 (C4 에 겹쳐서)
//   H11  C5 / C5b / C7 -- RANGE, 재실행, 정상 실행
//   H12  적재 중 COMMAND 는 버려짐 (start 수락 조건의 !load_busy 항)
//   H13  정답이 없는 술어 -- shot_cap 에서 멈추고 직전 result_valid 를 지움
//   H14  열거 (NORMAL_ENUM / CKPT_ENUM) -- FIFO read-to-pop, FIFO_COUNT
//        감소, 인덱스 0 도 정상값, 결과가 남아 있으면 COMMAND 가 버려짐
//        (start 수락 조건의 res_empty 항)
//   H15  체크포인트 경로가 CSR burst 비트로 실제로 켜지는가
//        (정책 텔레메트리)
//=====================================================================
`timescale 1ns/1ps
`include "bbht_grover_csr.vh"
`include "grover_param.vh"

// 전역 워치독 (ns). 100 MHz 라 4_000_000_000 ns = 4억 사이클입니다.
`ifndef SIM_TIMEOUT_NS
  `define SIM_TIMEOUT_NS 4_000_000_000
`endif

// 탐색 하나의 STATUS 폴링 상한. 폴링 간격이 POLL_GAP+3 사이클이므로
// 400_000 x 35 = 1,400만 사이클입니다.
`ifndef GUARD_POLLS
  `define GUARD_POLLS 400_000
`endif

module tb_bbht_bram_top;

    localparam [31:0] SRAM_BASE = 32'hE000_0000;
    localparam [31:0] SRAM_LAST = 32'hE001_FFFF;
    localparam integer NDATA    = `GP_N;           // 16,384
    localparam integer NWORDS   = NDATA / 2;       // 8,192 워드 = 32 KiB

    // STATUS 폴링 사이에 쉬는 사이클. 폴링은 CSR 을 읽기만 하므로 Main IP 의
    // cycle_count 에는 영향이 없고, 시뮬 시간만 줄여 줍니다.
    localparam integer POLL_GAP = 32;

    reg clk   = 1'b0;
    reg rstnn = 1'b0;
    always #5 clk = ~clk;              // 100 MHz

    integer errors = 0;

    //-----------------------------------------------------------------
    // APB
    //-----------------------------------------------------------------
    reg         psel    = 1'b0;
    reg         penable = 1'b0;
    reg         pwrite  = 1'b0;
    reg  [31:0] paddr   = 32'd0;
    reg  [31:0] pwdata  = 32'd0;
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

    reg         bk_we   = 1'b0;
    reg  [31:0] bk_addr = 32'd0;
    reg  [31:0] bk_data = 32'd0;

    //-----------------------------------------------------------------
    // DUT
    //-----------------------------------------------------------------
    bbht_bram_top #(
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

    // 대기 사이클 1. loader 가 shready 를 기다리며 주소 위상을 붙드는지를
    // 같이 봅니다 (tb_bbht_rvx 와 같은 설정).
    ahb_sram_model #(
        .BASE_ADDR   (SRAM_BASE),
        .WORDS       (NWORDS),
        .WAIT_CYCLES (1)
    ) sram (
        .clk (clk), .rstnn (rstnn),
        .haddr (shaddr), .htrans (shtrans), .hwrite (shwrite),
        .hsize (shsize), .hburst (shburst), .hwdata (shwdata),
        .hready (shready), .hresp (shresp), .hrdata (shrdata),
        .bk_we (bk_we), .bk_addr (bk_addr), .bk_data (bk_data)
    );

    //-----------------------------------------------------------------
    // 데이터셋 두 벌 (tb_bbht_dram_top 과 같음)
    //
    //   배열 A (매핑 검사용)   짝수 i -> i,   홀수 i -> i + 16384
    //       한 AHB 워드의 하위 16비트가 짝수 칸, 상위 16비트가 홀수 칸입니다.
    //       LT 256 을 걸면 정답이 짝수 인덱스 0..254 뿐(128개)이라, 적재기가
    //       두 반쪽을 바꿔 넣거나 인덱스를 한 칸 밀면 IP 가 홀수 인덱스를
    //       내놓고 호스트 쪽 판정에서 그 즉시 걸립니다. 홀수 쪽 최대값이
    //       16383 + 16384 = 32767 이라 16비트 signed 에 딱 들어갑니다.
    //
    //   배열 B (궤적 대조용)   data[i] = i  (tb_dram_core.v 와 같은 배열)
    //-----------------------------------------------------------------
    reg ds_is_a;                       // 지금 IP 에 들어 있는 배열이 A 인가

    function signed [15:0] val_a;
        input integer idx;
        begin
            if (idx[0]) val_a = 16'(idx + 16384);
            else        val_a = 16'(idx);
        end
    endfunction

    function signed [15:0] val_b;
        input integer idx;
        begin
            val_b = 16'(idx);
        end
    endfunction

    function signed [15:0] host_val;
        input integer idx;
        begin
            host_val = ds_is_a ? val_a(idx) : val_b(idx);
        end
    endfunction

    function pred_ok;
        input [1:0] mode;
        input signed [15:0] ta;
        input signed [15:0] tb;
        input signed [15:0] v;
        begin
            case (mode)
                `BBHT_PRED_LT: pred_ok = (v <  ta);
                `BBHT_PRED_GT: pred_ok = (v >  ta);
                `BBHT_PRED_EQ: pred_ok = (v == ta);
                default:       pred_ok = (v >  ta) && (v < tb);   // RANGE
            endcase
        end
    endfunction

    // SRAM 뒷문으로 배열을 채웁니다. 펌웨어가 보드 SRAM 에 배열을 만들어
    // 두는 것(GEN)에 해당합니다.
    task fill_sram(input sel_a);
        integer k;
        reg [15:0] lo, hi;
    begin
        for (k = 0; k < NWORDS; k = k + 1) begin
            lo = sel_a ? val_a(2*k)     : val_b(2*k);
            hi = sel_a ? val_a(2*k + 1) : val_b(2*k + 1);
            @(negedge clk);
            bk_we   = 1'b1;
            bk_addr = SRAM_BASE + k*4;
            bk_data = {hi, lo};
        end
        @(negedge clk);
        bk_we = 1'b0;
    end
    endtask

    //-----------------------------------------------------------------
    // APB 마스터
    //
    // 자극은 전부 negedge 에서 줍니다. posedge 에서 주면 DUT 가 같은 에지에
    // 그 값을 보게 되어 전송이 한 사이클 당겨지고, FIFO_DATA 처럼 읽기에
    // 부작용이 있는 레지스터에서 pop 이 샘플링보다 먼저 일어납니다.
    // mmio 의 pready 는 상수 1 이라 access 위상이 정확히 한 사이클입니다.
    //-----------------------------------------------------------------
    task apb_write(input [5:0] idx, input [31:0] data);
    begin
        @(negedge clk);
        psel = 1'b1; penable = 1'b0; pwrite = 1'b1;
        paddr = `BBHT_CSR_STRIDE * idx; pwdata = data;
        @(negedge clk);
        penable = 1'b1;
        @(negedge clk);
        psel = 1'b0; penable = 1'b0; pwrite = 1'b0;
    end
    endtask

    task apb_read(input [5:0] idx, output [31:0] data);
    begin
        @(negedge clk);
        psel = 1'b1; penable = 1'b0; pwrite = 1'b0;
        paddr = `BBHT_CSR_STRIDE * idx;
        @(negedge clk);
        penable = 1'b1;
        #1 data = prdata;             // access 위상 안, 완료 posedge 이전
        @(negedge clk);
        psel = 1'b0; penable = 1'b0;
    end
    endtask

    // 이름 인자를 1024비트(128바이트)로 둡니다. 한글은 UTF-8 로 글자당
    // 3바이트라 256비트면 열 글자 남짓에서 잘립니다.
    task apb_probe_err(input [31:0] addr, input [1023:0] name);
    begin
        @(negedge clk);
        psel = 1'b1; penable = 1'b0; pwrite = 1'b0; paddr = addr;
        @(negedge clk);
        penable = 1'b1;
        #1;
        if (!pslverr) begin
            $display("  FAIL %0s (0x%03x) 에 pslverr 가 안 섰습니다", name, addr);
            errors = errors + 1;
        end else $display("  ok   %0s (0x%03x) -> pslverr", name, addr);
        @(negedge clk);
        psel = 1'b0; penable = 1'b0;
    end
    endtask

    task check(input [1023:0] name, input [31:0] got, input [31:0] exp);
    begin
        if (got !== exp) begin
            $display("  FAIL %0s : got 0x%08x, expected 0x%08x", name, got, exp);
            errors = errors + 1;
        end else begin
            $display("  ok   %0s = 0x%08x", name, got);
        end
    end
    endtask

    task expect_true(input [1023:0] name, input cond);
    begin
        if (cond !== 1'b1) begin
            $display("  FAIL %0s", name);
            errors = errors + 1;
        end else begin
            $display("  ok   %0s", name);
        end
    end
    endtask

    //-----------------------------------------------------------------
    // 펌웨어 동작 단위 (bbht_grover_driver.c 의 load / run 과 같은 순서)
    //-----------------------------------------------------------------
    task dma_issue(input [31:0] addr, input [31:0] count);
    begin
        apb_write(`CSR_IDX_DATA_ADDR,   addr);
        apb_write(`CSR_IDX_DATA_COUNT,  count);
        apb_write(`CSR_IDX_DMA_COMMAND, 32'd1);
    end
    endtask

    task dma_wait(output [31:0] st);
        integer guard;
    begin
        guard = 0;
        st = 32'd0;
        while (guard < `GUARD_POLLS) begin
            apb_read(`CSR_IDX_DMA_STATUS, st);
            if (st[`BBHT_DMA_DMA_DONE_STICKY] || st[`BBHT_DMA_DMA_ERROR])
                guard = `GUARD_POLLS;
            else begin
                guard = guard + 1;
                repeat (POLL_GAP) @(negedge clk);
            end
        end
    end
    endtask

    task do_dma(input [31:0] addr, input [31:0] count, output [31:0] st);
    begin
        dma_issue(addr, count);
        dma_wait(st);
    end
    endtask

    // 탐색 설정. CONTROL = {predicate[3:2], burst[1], auto_shot[0]}.
    // 실행 모드는 CSR 정본(run_modes)을 따릅니다.
    //   MANUAL_SINGLE  auto=0 burst=0
    //   NORMAL_*       auto=1 burst=0
    //   CKPT_*         auto=1 burst=1
    task configure(input ckpt, input a_shot, input integer jt, input [1:0] mode,
                   input signed [15:0] ta, input signed [15:0] tb,
                   input [31:0] sj, input [31:0] sm, input [15:0] cap,
                   input en_enum);
    begin
        apb_write(`CSR_IDX_CONTROL,     {28'd0, mode, ckpt, a_shot});
        apb_write(`CSR_IDX_J_TARGET,    jt);
        apb_write(`CSR_IDX_THRESHOLD_A, {16'd0, ta});
        apb_write(`CSR_IDX_THRESHOLD_B, {16'd0, tb});
        apb_write(`CSR_IDX_DATA_COUNT,  NDATA);
        apb_write(`CSR_IDX_SHOT_CAP,    {16'd0, cap});
        apb_write(`CSR_IDX_SEED_J,      sj);
        apb_write(`CSR_IDX_SEED_MEAS,   sm);
        apb_write(`CSR_IDX_ENUM_CFG,    {24'd0, 4'd4, 3'd0, en_enum});
    end
    endtask

    task wait_done(output [31:0] st, output integer timed_out);
        integer guard;
    begin
        guard = 0;
        st = 32'd0;
        timed_out = 1;
        while (guard < `GUARD_POLLS) begin
            apb_read(`CSR_IDX_STATUS, st);
            if (st[`BBHT_ST_DONE_STICKY]) begin
                timed_out = 0;
                guard = `GUARD_POLLS;
            end else begin
                guard = guard + 1;
                repeat (POLL_GAP) @(negedge clk);
            end
        end
    end
    endtask

    // 탐색이 끝난 뒤 CSR 에서 읽어 둔 값. 케이스끼리 비교할 때 씁니다.
    reg [31:0] r_status, r_idx, r_trials, r_lbbht, r_iters, r_cyc, r_pol;

    task read_result;
    begin
        apb_read(`CSR_IDX_STATUS,              r_status);
        apb_read(`CSR_IDX_RESULT_INDEX,        r_idx);
        apb_read(`CSR_IDX_TRIAL_COUNT,         r_trials);
        apb_read(`CSR_IDX_L_BBHT,              r_lbbht);
        apb_read(`CSR_IDX_ACTUAL_ITER,         r_iters);
        apb_read(`CSR_IDX_CYCLE_COUNT,         r_cyc);
        apb_read(`CSR_IDX_POLICY_CYCLES_TOTAL, r_pol);
    end
    endtask

    // 탐색 한 번을 호스트가 하듯이: 설정 -> COMMAND -> STATUS 폴링 -> 결과.
    // CASE 줄 형식은 tb_dram_core.v 와 똑같습니다. 체크포인트 판은 줄 머리만
    // CKPT 입니다.
    //
    // mid_busy 가 1 이면 탐색이 도는 동안 두 가지를 밀어 넣습니다 (H10).
    //   DMA_COMMAND  busy_error 로 거절되어야 하고 배열은 그대로
    //   COMMAND      start 수락 조건의 !search_busy 항에 걸려 버려져야 함
    task run_case(input [1023:0] label, input ckpt,
                  input a_shot, input integer jt, input [1:0] mode,
                  input signed [15:0] ta, input signed [15:0] tb,
                  input [31:0] sj, input [31:0] sm, input [15:0] cap,
                  input integer expect_success, input integer expect_cfgerr,
                  input mid_busy);
        integer to;
        integer ok;
        reg [31:0] st, dst;
    begin
        configure(ckpt, a_shot, jt, mode, ta, tb, sj, sm, cap, 1'b0);
        apb_write(`CSR_IDX_COMMAND, 32'd1);

        if (mid_busy) begin
            // busy 가 선 것을 확인한 다음에 넣어야 "탐색 중" 이 됩니다.
            st = 32'd0;
            while (!st[`BBHT_ST_BUSY] && !st[`BBHT_ST_DONE_STICKY])
                apb_read(`CSR_IDX_STATUS, st);
            if (!st[`BBHT_ST_BUSY]) begin
                $display("  FAIL %0s: busy 를 보기 전에 끝났습니다 (H10 불성립)", label);
                errors = errors + 1;
            end
            do_dma(SRAM_BASE, NDATA, dst);
            if (!dst[`BBHT_DMA_BUSY_ERROR] || !dst[`BBHT_DMA_DMA_ERROR]) begin
                $display("  FAIL [H10] 탐색 중 DMA 가 거절되지 않았습니다 (DMA_STATUS=0x%08x)", dst);
                errors = errors + 1;
            end else $display("  ok   [H10] 탐색 중 DMA -> busy_error (DMA_STATUS=0x%02x)", dst[7:0]);

            apb_read(`CSR_IDX_STATUS, st);
            if (!st[`BBHT_ST_BUSY])
                $display("  note [H10] 탐색이 이미 끝나 탐색 중 COMMAND 시험이 약해졌습니다");
            apb_write(`CSR_IDX_COMMAND, 32'd1);
        end

        wait_done(st, to);

        if (mid_busy) begin
            repeat (200) @(negedge clk);
            apb_read(`CSR_IDX_STATUS, st);
            if (st[`BBHT_ST_BUSY] || !st[`BBHT_ST_DONE_STICKY]) begin
                $display("  FAIL [H10] 탐색 중 COMMAND 가 받아들여졌습니다 (STATUS=0x%08x)", st);
                errors = errors + 1;
            end else $display("  ok   [H10] 탐색 중 COMMAND 는 버려짐 (끝난 뒤 busy 재기동 없음)");
        end

        read_result;

        ok = 1;
        if (to != 0) begin
            ok = 0; errors = errors + 1;
            $display("  FAIL %0s: done_sticky 가 안 섰습니다 (멈춤, STATUS=0x%08x)", label, st);
        end else if (expect_cfgerr != 0) begin
            if (!r_status[`BBHT_ST_CONFIG_ERROR]) begin
                ok = 0; errors = errors + 1;
                $display("  FAIL %0s: config_error 를 기대했는데 안 떴습니다", label);
            end
            if (r_status[`BBHT_ST_RESULT_VALID]) begin
                ok = 0; errors = errors + 1;
                $display("  FAIL %0s: 거절된 실행인데 result_valid 가 떴습니다", label);
            end
        end else begin
            if (r_status[`BBHT_ST_CONFIG_ERROR]) begin
                ok = 0; errors = errors + 1;
                $display("  FAIL %0s: 예상 못 한 config_error", label);
            end
            if ((expect_success != 0) && !r_status[`BBHT_ST_RESULT_VALID]) begin
                ok = 0; errors = errors + 1;
                $display("  FAIL %0s: 정답을 못 찾았습니다 (STATUS=0x%08x)", label, r_status);
            end
            // 호스트 쪽 판정. IP 가 찾았다고 한 인덱스를 이 TB 가 SRAM 에
            // 넣은 배열에서 직접 꺼내 술어에 대 봅니다.
            if (r_status[`BBHT_ST_RESULT_VALID]) begin
                if (r_idx >= NDATA) begin
                    ok = 0; errors = errors + 1;
                    $display("  FAIL %0s: RESULT_INDEX %0d 가 범위 밖입니다", label, r_idx);
                end else if (!pred_ok(mode, ta, tb, host_val(r_idx))) begin
                    ok = 0; errors = errors + 1;
                    $display("  FAIL %0s: RESULT_INDEX %0d (호스트 배열 값 %0d) 가 술어를 만족하지 않습니다",
                             label, r_idx, host_val(r_idx));
                end
            end
            if (r_status[`BBHT_ST_ZERO_WEIGHT_ERROR] || r_status[`BBHT_ST_AMP_OVERFLOW]) begin
                ok = 0; errors = errors + 1;
                $display("  FAIL %0s: zero_weight/amp_overflow (STATUS=0x%08x)", label, r_status);
            end
        end

        $display("%0s %0s valid=%0d idx=%0d trials=%0d lbbht=%0d cfgerr=%0d shotlim=%0d budlim=%0d | iters=%0d cyc=%0d",
                 ckpt ? "CKPT" : "CASE",
                 label, r_status[`BBHT_ST_RESULT_VALID], r_idx, r_trials, r_lbbht,
                 r_status[`BBHT_ST_CONFIG_ERROR], r_status[`BBHT_ST_SHOT_LIMIT],
                 r_status[`BBHT_ST_BUDGET_LIMIT], r_iters, r_cyc);
        if (ok != 0) $display("  ok   %0s%0s", label, ckpt ? " [CKPT]" : "");
    end
    endtask

    // NORMAL_SINGLE 로 한 번, CKPT_SINGLE 로 한 번. 궤적이 같아야 합니다.
    // 반복 수와 사이클은 달라야 정상이고(그게 체크포인트의 이득), 기록만
    // 합니다. CKPT 판의 결과가 r_* 에 남습니다.
    reg [31:0] n_status, n_idx, n_trials, n_lbbht, n_iters, n_cyc;
    integer    ckpt_cyc_sum = 0, normal_cyc_sum = 0;

    task run_pair(input [1023:0] label,
                  input [1:0] mode, input signed [15:0] ta, input signed [15:0] tb,
                  input [31:0] sj, input [31:0] sm);
        reg [11:0] traj_mask;
    begin
        run_case(label, 1'b0, 1'b1, 0, mode, ta, tb, sj, sm, 16'd100, 1, 0, 1'b0);
        n_status = r_status; n_idx = r_idx; n_trials = r_trials;
        n_lbbht = r_lbbht; n_iters = r_iters; n_cyc = r_cyc;
        run_case(label, 1'b1, 1'b1, 0, mode, ta, tb, sj, sm, 16'd100, 1, 0, 1'b0);

        // 비교할 상태 비트: result_valid, config_error, shot_limit,
        // budget_limit, amp_overflow, zero_weight_error.
        traj_mask = 12'h0F8 | 12'h100;
        if (n_idx !== r_idx || n_trials !== r_trials || n_lbbht !== r_lbbht ||
            (n_status & {20'd0, traj_mask}) !== (r_status & {20'd0, traj_mask})) begin
            $display("  FAIL %0s: NORMAL 과 CKPT 의 궤적이 갈라졌습니다 (idx %0d/%0d trials %0d/%0d L_BBHT %0d/%0d)",
                     label, n_idx, r_idx, n_trials, r_trials, n_lbbht, r_lbbht);
            errors = errors + 1;
        end else begin
            $display("  ok   %0s: NORMAL = CKPT 궤적 (반복 %0d -> %0d, 사이클 %0d -> %0d)",
                     label, n_iters, r_iters, n_cyc, r_cyc);
        end
        normal_cyc_sum = normal_cyc_sum + n_cyc;
        ckpt_cyc_sum   = ckpt_cyc_sum + r_cyc;
    end
    endtask

    //-----------------------------------------------------------------
    // 열거 한 번 (H14). LT 4 는 배열 B 에서 {0,1,2,3} 네 개입니다.
    // 결과는 FIFO 로 나오고 FIFO_DATA 읽기가 곧 pop 입니다.
    //-----------------------------------------------------------------
    reg [31:0] e_found, e_trials;
    reg [3:0]  e_seen;

    task run_enum(input ckpt, input [31:0] sj, input [31:0] sm);
        integer to, k;
        reg [31:0] st, d, cnt;
    begin
        configure(ckpt, 1'b1, 0, `BBHT_PRED_LT, 16'sd4, 16'sd0, sj, sm, 16'd100, 1'b1);
        apb_write(`CSR_IDX_COMMAND, 32'd1);
        wait_done(st, to);
        if (to != 0) begin
            $display("  FAIL %0s: 열거가 끝나지 않았습니다 (STATUS=0x%08x)",
                     ckpt ? "CKPT_ENUM" : "NORMAL_ENUM", st);
            errors = errors + 1;
        end
        expect_true("enum_done", st[`BBHT_ST_ENUM_DONE]);
        expect_true("config_error 없음", !st[`BBHT_ST_CONFIG_ERROR]);

        apb_read(`CSR_IDX_FOUND_COUNT, e_found);
        apb_read(`CSR_IDX_TRIAL_COUNT, e_trials);
        apb_read(`CSR_IDX_FIFO_COUNT,  cnt);
        check("FOUND_COUNT", e_found, 32'd4);
        check("FIFO_COUNT = FOUND_COUNT", cnt, e_found);
        $display("CASE %0s LT4 found=%0d trials=%0d",
                 ckpt ? "CKPT_ENUM" : "NORMAL_ENUM", e_found, e_trials);

        // 결과가 FIFO 에 남아 있는 동안 COMMAND 는 버려져야 합니다
        // (res_empty 항). COMMAND 쓰기가 done_sticky 를 지우므로, 버려졌다면
        // done_sticky 는 0 인 채로 남고 FIFO 도 그대로입니다.
        apb_write(`CSR_IDX_COMMAND, 32'd1);
        repeat (200) @(negedge clk);
        apb_read(`CSR_IDX_STATUS, st);
        expect_true("결과가 남은 채 COMMAND -> 버려짐 (busy=0, done_sticky=0)",
                    !st[`BBHT_ST_BUSY] && !st[`BBHT_ST_DONE_STICKY]);
        apb_read(`CSR_IDX_FIFO_COUNT, d);
        check("FIFO_COUNT 그대로", d, cnt);

        // read-to-pop. 순서는 보지 않고 집합만 봅니다 (Born 측정이 뽑은
        // 발견 순서대로 들어가므로 오름차순이 아닙니다).
        e_seen = 4'b0000;
        for (k = 0; k < 4; k = k + 1) begin
            apb_read(`CSR_IDX_FIFO_DATA, d);
            if (d < 4 && pred_ok(`BBHT_PRED_LT, 16'sd4, 16'sd0, host_val(d)))
                e_seen[d] = 1'b1;
            else begin
                $display("  FAIL FIFO_DATA : 정답 {0,1,2,3} 밖의 값 %0d", d);
                errors = errors + 1;
            end
            apb_read(`CSR_IDX_FIFO_COUNT, cnt);
            check("FIFO_COUNT after pop", cnt, 3 - k);
        end
        // 인덱스 0 이 결과 집합에 들어 있어야 합니다. FIFO_DATA = 0 이
        // "비었음" 이 아니라 정상값으로 읽혔다는 뜻입니다.
        expect_true("열거 집합 = {0,1,2,3} (인덱스 0 포함, 순서 무관)", e_seen == 4'b1111);
        apb_read(`CSR_IDX_STATUS, st);
        expect_true("drain 후 fifo_empty", st[`BBHT_ST_FIFO_EMPTY]);
    end
    endtask

    //-----------------------------------------------------------------
    // 본체
    //-----------------------------------------------------------------
    reg [31:0] d, st;
    reg [31:0] c2_trials, c2_lbbht, c2_idx;
    reg [31:0] c5_trials, c5_lbbht, c5_idx;
    reg [31:0] cyc_before, en_found, en_trials;
    integer    to;

    initial begin
        $display("=== tb_bbht_bram_top : hardware_bram 최상단 (K3/H3-E4-M2) ===");
        ds_is_a = 1'b0;
        repeat (5) @(negedge clk);
        rstnn = 1'b1;
        repeat (5) @(negedge clk);

        //-------------------------------------------------------------
        $display("[H1] RW 라운드트립");
        apb_write(`CSR_IDX_CONTROL, 32'h0000000B);
        apb_read (`CSR_IDX_CONTROL, d);
        check("CONTROL", d, 32'h0000000B);

        apb_write(`CSR_IDX_THRESHOLD_A, 32'h0000FFFF);          // -1
        apb_read (`CSR_IDX_THRESHOLD_A, d);
        check("THRESHOLD_A(-1)", d, 32'h0000FFFF);

        apb_write(`CSR_IDX_SEED_J, 32'hDEADBEEF);
        apb_read (`CSR_IDX_SEED_J, d);
        check("SEED_J", d, 32'hDEADBEEF);

        apb_write(`CSR_IDX_SHOT_CAP, 32'd12345);
        apb_read (`CSR_IDX_SHOT_CAP, d);
        check("SHOT_CAP", d, 32'd12345);

        apb_write(`CSR_IDX_ENUM_CFG, 32'h00000041);             // limit=4, enable=1
        apb_read (`CSR_IDX_ENUM_CFG, d);
        check("ENUM_CFG", d, 32'h00000041);

        apb_write(`CSR_IDX_DATA_ADDR, SRAM_BASE + 32'h100);
        apb_read (`CSR_IDX_DATA_ADDR, d);
        check("DATA_ADDR", d, SRAM_BASE + 32'h100);

        // J_TARGET 은 7비트라 상위가 잘려야 합니다.
        apb_write(`CSR_IDX_J_TARGET, 32'hFFFFFFFF);
        apb_read (`CSR_IDX_J_TARGET, d);
        check("J_TARGET(7b clip)", d, 32'd127);

        //-------------------------------------------------------------
        $display("[H2] W1P 는 읽으면 0");
        apb_read(`CSR_IDX_COMMAND, d);
        check("COMMAND rd", d, 32'd0);
        apb_read(`CSR_IDX_DMA_COMMAND, d);
        check("DMA_COMMAND rd", d, 32'd0);
        apb_read(`CSR_IDX_STATUS, d);
        expect_true("COMMAND 읽기는 부작용 없음",
                    !d[`BBHT_ST_BUSY] && !d[`BBHT_ST_DONE_STICKY]);

        //-------------------------------------------------------------
        $display("[H3] 정렬 위반 / 미할당 주소");
        apb_probe_err(32'h0000_0002, "정렬 위반");
        apb_probe_err(32'h0000_0800, "미할당 주소");

        //-------------------------------------------------------------
        $display("[H4] DMA -- Q14 전체 %0d개 (배열 A)", NDATA);
        fill_sram(1'b1);
        do_dma(SRAM_BASE, NDATA, st);
        check("DMA_STATUS", st, 32'h00000080);          // done_sticky 만
        ds_is_a = 1'b1;
        apb_read(`CSR_IDX_STATUS, d);
        expect_true("적재 뒤 load_busy=0, load_error=0",
                    !d[`BBHT_ST_LOAD_BUSY] && !d[`BBHT_ST_LOAD_ERROR]);

        //-------------------------------------------------------------
        $display("[H5] 16비트 매핑 -- 배열 A 에서 LT 256 은 짝수 인덱스만");
        run_case("H5 매핑 LT256", 1'b0, 1'b1, 0, `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 16'd100, 1, 0, 1'b0);
        expect_true("RESULT_INDEX 가 짝수 (하위 16비트 = 짝수 칸)", r_idx[0] == 1'b0);

        //-------------------------------------------------------------
        $display("[H6] DMA 거절");
        // (가) 정렬·범위 거절. DATA_COUNT 는 적재 때와 같은 N 으로 둡니다.
        //     거절된 DMA 는 load_start 를 내지 않으므로 배열이 그대로 남아
        //     재적재 없이 탐색이 되어야 합니다.
        do_dma(SRAM_BASE + 32'd2, NDATA, st);           // 정렬 위반
        expect_true("정렬 위반 -> align_error",
                    st[`BBHT_DMA_ALIGN_ERROR] && st[`BBHT_DMA_DMA_ERROR]);
        do_dma(32'hF000_0000, NDATA, st);               // SRAM 밖
        expect_true("SRAM 밖 주소 -> range_error", st[`BBHT_DMA_RANGE_ERROR]);
        do_dma(SRAM_LAST - 32'd3, NDATA, st);           // 끝이 SRAM 을 넘음
        expect_true("끝이 SRAM 을 넘음 -> range_error", st[`BBHT_DMA_RANGE_ERROR]);
        apb_read(`CSR_IDX_DMA_STATUS, d);
        expect_true("거절 뒤 dma_busy=0", !d[`BBHT_DMA_DMA_BUSY]);

        run_case("H6 정렬·범위 거절 뒤 탐색", 1'b0, 1'b1, 0, `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 16'd100, 1, 0, 1'b0);
        expect_true("거절 뒤에도 배열 A 그대로 (짝수 인덱스)", r_idx[0] == 1'b0);

        // (나) 개수 거절. DATA_COUNT 레지스터 자체를 0 이나 N+1 로 바꿔 쓰게
        //     되고, grover_loader 는 적재가 끝난 뒤 data_count 가 바뀌면
        //     배열을 무효로 칩니다 (data_count_mismatch -> data_valid=0).
        //     DATA_COUNT 를 N 으로 되돌려도 다시 서지 않으므로 재적재 없이
        //     탐색하면 config_error 여야 합니다.
        do_dma(SRAM_BASE, 32'd0, st);                   // 개수 0
        expect_true("count=0 -> count_error", st[`BBHT_DMA_COUNT_ERROR]);
        do_dma(SRAM_BASE, NDATA + 1, st);               // 개수 초과
        expect_true("count=N+1 -> count_error", st[`BBHT_DMA_COUNT_ERROR]);
        run_case("H6 개수 거절 뒤 재적재 없이 탐색", 1'b0, 1'b1, 0, `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 16'd100, 0, 1, 1'b0);

        //-------------------------------------------------------------
        $display("[H7] 재적재 (배열 B)");
        fill_sram(1'b0);
        do_dma(SRAM_BASE, NDATA, st);
        check("DMA_STATUS", st, 32'h00000080);
        ds_is_a = 1'b0;

        //-------------------------------------------------------------
        // 여기부터 C1~C7 은 tb_dram_core.v 와 레이블·자극·시드가 같습니다.
        // shot_cap 100, data_count N, 배열 B 도 같습니다.
        //-------------------------------------------------------------
        $display("[H8] 수동 / NORMAL / CKPT, 재실행");
        // MANUAL_SINGLE 은 체크포인트를 쓰지 않는 모드라 한 번만 돌립니다.
        run_case("C1 MANUAL j=6 LT256", 1'b0, 1'b0, 6, `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 16'd100, 1, 0, 1'b0);

        run_pair("C2 NORMAL LT256", `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0);
        c2_trials = r_trials; c2_lbbht = r_lbbht; c2_idx = r_idx;

        run_pair("C3 NORMAL LT256 재실행", `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0);
        expect_true("C3 궤적이 C2 와 같음 (idx / trials / L_BBHT)",
                    r_idx == c2_idx && r_trials == c2_trials && r_lbbht == c2_lbbht);

        //-------------------------------------------------------------
        $display("[H9] done_sticky 는 COMMAND 쓰기로만 클리어");
        apb_read(`CSR_IDX_STATUS, d);
        expect_true("STATUS 읽기는 done_sticky 를 안 지움", d[`BBHT_ST_DONE_STICKY]);
        apb_write(`CSR_IDX_THRESHOLD_A, 32'd256);
        apb_read (`CSR_IDX_STATUS, d);
        expect_true("설정 쓰기는 done_sticky 를 안 지움", d[`BBHT_ST_DONE_STICKY]);

        //-------------------------------------------------------------
        $display("[H10] 탐색 중 DMA / COMMAND -- C4 에 겹쳐서");
        // 끼어들기는 CKPT 판에 겁니다. 체크포인트 실행이 거절된 DMA 나
        // 버려진 COMMAND 에 흔들리면 NORMAL 판과 궤적이 갈라져 드러납니다.
        run_case("C4 NORMAL GT16128", 1'b0, 1'b1, 0, `BBHT_PRED_GT, 16'sd16128, 16'sd0,
                 32'h0BAD_F00D, 32'h5EED_1234, 16'd100, 1, 0, 1'b0);
        n_idx = r_idx; n_trials = r_trials; n_lbbht = r_lbbht;
        run_case("C4 NORMAL GT16128", 1'b1, 1'b1, 0, `BBHT_PRED_GT, 16'sd16128, 16'sd0,
                 32'h0BAD_F00D, 32'h5EED_1234, 16'd100, 1, 0, 1'b1);
        expect_true("C4 끼어든 CKPT 판도 NORMAL 과 궤적이 같음",
                    r_idx == n_idx && r_trials == n_trials && r_lbbht == n_lbbht);

        //-------------------------------------------------------------
        $display("[H11] RANGE, 재실행, 정상 실행");
        run_pair("C5 NORMAL RANGE", `BBHT_PRED_RANGE, 16'sd1000, 16'sd1300,
                 32'hFEED_BEEF, 32'h1357_9BDF);
        c5_trials = r_trials; c5_lbbht = r_lbbht; c5_idx = r_idx;

        run_pair("C5b RANGE 재실행", `BBHT_PRED_RANGE, 16'sd1000, 16'sd1300,
                 32'hFEED_BEEF, 32'h1357_9BDF);
        expect_true("C5b 궤적이 C5 와 같음",
                    r_idx == c5_idx && r_trials == c5_trials && r_lbbht == c5_lbbht);

        // tb_dram_core 의 C6 은 dram 갈래의 열거 거절이라 여기에는 없습니다.
        // 이 갈래는 열거가 실제로 구현되어 있어 H14 에서 따로 봅니다.
        run_pair("C7 거절 후 정상 실행", `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h2468_ACE0, 32'h1122_3344);

        //-------------------------------------------------------------
        $display("[H12] 적재 중 COMMAND 는 버려짐");
        apb_read(`CSR_IDX_CYCLE_COUNT, cyc_before);
        dma_issue(SRAM_BASE, NDATA);
        apb_read(`CSR_IDX_STATUS, d);
        expect_true("DMA 직후 load_busy=1", d[`BBHT_ST_LOAD_BUSY]);
        apb_write(`CSR_IDX_COMMAND, 32'd1);             // 이건 버려져야 합니다
        dma_wait(st);
        check("DMA_STATUS", st, 32'h00000080);
        repeat (20) @(negedge clk);
        apb_read(`CSR_IDX_STATUS, d);
        expect_true("적재 중 COMMAND 로 탐색이 시작되지 않음 (busy=0, done_sticky=0)",
                    !d[`BBHT_ST_BUSY] && !d[`BBHT_ST_DONE_STICKY]);
        apb_read(`CSR_IDX_CYCLE_COUNT, d);
        check("CYCLE_COUNT 그대로", d, cyc_before);

        // 버려진 다음 정상 COMMAND 는 받아야 합니다. 재적재로 체크포인트
        // 캐시가 비었으므로 CKPT 판은 처음부터 다시 쌓습니다.
        run_pair("H12 버려진 뒤 정상 실행", `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0);
        expect_true("궤적이 C2 와 같음 (같은 배열·같은 시드)",
                    r_idx == c2_idx && r_trials == c2_trials && r_lbbht == c2_lbbht);

        //-------------------------------------------------------------
        $display("[H13] 정답이 없는 술어 -- shot_cap 에서 멈춤");
        // 배열 B 는 0..16383 이라 EQ -1 은 정답이 없습니다. shot_cap 을 작게
        // 두어 짧게 끝냅니다. 직전 실행의 result_valid 가 남으면 안 됩니다.
        run_case("H13 EQ -1 shot_cap=4", 1'b0, 1'b1, 0, `BBHT_PRED_EQ, -16'sd1, 16'sd0,
                 32'hCAFE_0001, 32'hCAFE_0002, 16'd4, 0, 0, 1'b0);
        expect_true("result_valid=0 (직전 결과가 안 남음)", !r_status[`BBHT_ST_RESULT_VALID]);
        expect_true("shot_limit=1", r_status[`BBHT_ST_SHOT_LIMIT]);

        //-------------------------------------------------------------
        $display("[H14] 열거 -- LT 4 는 {0,1,2,3}");
        $display("  -- NORMAL_ENUM");
        run_enum(1'b0, 32'h1357_2468, 32'h8642_9753);
        en_found = e_found; en_trials = e_trials;
        $display("  -- CKPT_ENUM");
        run_enum(1'b1, 32'h1357_2468, 32'h8642_9753);
        expect_true("NORMAL_ENUM 과 CKPT_ENUM 의 발견 수·시도 수가 같음",
                    e_found == en_found && e_trials == en_trials);

        //-------------------------------------------------------------
        $display("[H15] 체크포인트 경로가 CSR burst 비트로 켜지는가");
        // NORMAL 판 하나, CKPT 판 하나를 연달아 돌려 정책 엔진 사이클을
        // 봅니다. CKPT 판에서 0 이면 burst 비트가 Main IP 까지 안 간 것이고,
        // NORMAL 판에서 0 이 아니면 burst=0 인데도 체크포인트가 켜진 것입니다.
        // 이 카운터는 수락된 start 마다 비워지므로(바로 앞이 CKPT_ENUM 인데도
        // NORMAL 판이 0 으로 읽힘) 두 값을 따로 판정할 수 있습니다.
        run_case("H15 NORMAL", 1'b0, 1'b1, 0, `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 16'd100, 1, 0, 1'b0);
        check("NORMAL_SINGLE 에서 정책 엔진 안 돎 (POLICY_CYCLES_TOTAL)", r_pol, 32'd0);
        d = r_pol;
        run_case("H15 CKPT", 1'b1, 1'b1, 0, `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 16'd100, 1, 0, 1'b0);
        $display("  CKPT_SINGLE POLICY_CYCLES_TOTAL = %0d", r_pol);
        expect_true("CKPT_SINGLE 에서 정책 엔진이 돌았음 (POLICY_CYCLES_TOTAL > 0)",
                    r_pol > d);

        $display("  -- 모드 짝 사이클 합계: NORMAL %0d / CKPT %0d (기록만, 판정 아님)",
                 normal_cyc_sum, ckpt_cyc_sum);

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
