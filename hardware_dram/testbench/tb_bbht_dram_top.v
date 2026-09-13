//=====================================================================
// tb_bbht_dram_top.v -- hardware_dram 최상단 회귀 (호스트 경로 통째)
//
// 검증 대상은 src/bbht_dram_top.v 입니다. 짝은
// hardware_bram/testbench/tb_bbht_bram_top.v 입니다. 그 안에 CSR(mmio), 데이터셋
// DMA(loader), DRAM 전량저장 Main IP 가 전부 들어 있고, 바깥에는 세 가지만
// 붙습니다.
//
//   APB 마스터       이 테스트벤치의 태스크. RVX 위 펌웨어가 CSR 을 읽고
//                    쓰는 순서를 그대로 흉내 냅니다. 호스트 PC 의 UART
//                    명령(SET / LOAD / RUN)은 펌웨어 안에서 결국 이 순서가
//                    됩니다 (documents/design_references/호스트_조작_방법.md)
//   ahb_sram_model   RVX System SRAM 흉내. hardware_bram/testbench 것을
//                    그대로 물립니다 (두 갈래 통신 계층이 같으므로)
//   dram_burst_model DRAM 흉내. 저장한 슬롯이 복원 때 비트 하나 안 틀리고
//                    돌아오는지, 쓴 적 없는 슬롯을 읽지 않는지 심판도 봅니다
//
// 탐색 결과는 두 겹으로 확인합니다.
//   1. 호스트 쪽 판정   RESULT_INDEX 가 가리키는 값이 이 TB 가 SRAM 에 넣은
//                       배열에서 정말 술어를 만족하는가. 통신 계층의 배선
//                       (16비트 매핑, 인덱스 폭, 부호)이 틀리면 여기서 걸립니다
//   2. 궤적 대조        C1~C7 은 tb_dram_core.v 와 레이블·자극·시드가 같습니다.
//                       Makefile 의 top 타깃이 두 로그의 CASE 줄을 맞대서
//                       valid/idx/trials/lbbht/cfgerr/shotlim/budlim 이 같은지
//                       봅니다. 같으면 "통신 계층을 거쳐도 코어를 직접 흔든
//                       것과 같은 계산을 한다" 는 뜻입니다. result_index 만
//                       보면 안 되는 이유는 tb_dram_core.v 머리말에 있습니다
//
// 확인하는 것
//   H1   RW 레지스터 write-read 라운드트립
//   H2   W1P 레지스터는 읽으면 0, COMMAND 를 읽어도 탐색이 안 시작됨
//   H3   정렬 위반 / 미할당 주소는 pslverr
//   H4   DMA 로 Q14 전체(16,384개) 적재 -- 매핑 검사용 배열 A
//   H5   16비트 매핑 -- 배열 A 에서 LT 256 은 짝수 인덱스만 정답
//   H6   DMA 거절. 정렬·범위 거절은 배열과 DRAM 표를 보존하고, 개수
//        거절은 DATA_COUNT 가 바뀌므로 배열을 무효화한다 (재적재 전 탐색은
//        config_error)
//   H7   재적재(배열 B) 하면 DRAM 표가 버려지는가 (frontier_j -> 0)
//   H8   C1~C3 -- CSR 로 수동/자동 탐색, 재실행 때 DRAM 복원 경로가 실제로
//        최상단 포트를 타는가
//   H9   done_sticky 는 COMMAND 쓰기로만 클리어
//   H10  탐색 중 DMA 는 busy_error, 탐색 중 COMMAND 는 버려짐 (C4 에 겹쳐서)
//   H11  C5 / C5b / C6(Enumeration 거절) / C7
//   H12  적재 중 COMMAND 는 버려짐 (start 수락 조건)
//   H13  정답이 없는 술어 -- shot_cap 에서 멈추고 직전 result_valid 를 지움
//   H14  DRAM 심판 -- 프로토콜 오류 0, 쓰기·읽기 버스트 겹침 0,
//        저장·복원이 둘 다 일어났음
//=====================================================================
`timescale 1ns/1ps
`include "bbht_grover_csr.vh"
`include "grover_dram_param.vh"

// 전역 워치독 (ns). 100 MHz 라 2_000_000_000 ns = 2억 사이클입니다.
// 정상 실행은 이것의 몇 분의 일 안에 끝납니다.
`ifndef SIM_TIMEOUT_NS
  `define SIM_TIMEOUT_NS 2_000_000_000
`endif

// 탐색 하나의 STATUS 폴링 상한. 폴링 간격이 POLL_GAP+3 사이클이므로
// 200_000 x 35 = 700만 사이클입니다. tb_dram_core 의 케이스들은 수십만
// 사이클 안에 끝납니다.
`ifndef GUARD_POLLS
  `define GUARD_POLLS 200_000
`endif

module tb_bbht_dram_top #(
    // DRAM 지연. Makefile 이 -G 로 바꿔 끼웁니다 (tb_dram_core 와 같은 이름).
    parameter integer WR_LAT   = 4,
    parameter integer RD_LAT   = 12,
    parameter integer BEAT_GAP = 0,
    parameter integer STALL_EN = 0
);

    localparam [31:0] SRAM_BASE = 32'hE000_0000;
    localparam [31:0] SRAM_LAST = 32'hE001_FFFF;
    localparam integer NDATA    = `GP_N;           // 16,384
    localparam integer NWORDS   = NDATA / 2;       // 8,192 워드 = 32 KiB
    localparam integer ROW_BITS = `GP_P * `GP_AMP_W;

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
    // DRAM
    //-----------------------------------------------------------------
    wire                        dw_req, dw_valid, dw_last, dw_ready;
    wire [`GD_ADDR_W-1:0]       dw_addr;
    wire [`GD_BURST_LEN_W-1:0]  dw_len;
    wire [ROW_BITS-1:0]         dw_data;
    wire                        dr_req, dr_valid, dr_ready, dr_last;
    wire [`GD_ADDR_W-1:0]       dr_addr;
    wire [`GD_BURST_LEN_W-1:0]  dr_len;
    wire [ROW_BITS-1:0]         dr_data;
    wire [`GP_J_W-1:0]          frontier_j;
    wire [31:0]                 store_bursts, restore_bursts, dram_errors;

    //-----------------------------------------------------------------
    // DUT
    //-----------------------------------------------------------------
    bbht_dram_top #(
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
        .shwrite (shwrite), .shwdata (shwdata),

        .dram_wr_req (dw_req), .dram_wr_addr (dw_addr), .dram_wr_len (dw_len),
        .dram_wr_valid (dw_valid), .dram_wr_data (dw_data),
        .dram_wr_last (dw_last), .dram_wr_ready (dw_ready),

        .dram_rd_req (dr_req), .dram_rd_addr (dr_addr), .dram_rd_len (dr_len),
        .dram_rd_valid (dr_valid), .dram_rd_data (dr_data),
        .dram_rd_ready (dr_ready), .dram_rd_last (dr_last),

        .dram_frontier_j (frontier_j)
    );

    // 대기 사이클 1. loader 가 shready 를 기다리며 주소 위상을 붙드는지를
    // 같이 봅니다 (hardware_bram 의 tb_bbht_rvx 와 같은 설정).
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

    dram_burst_model #(
        .WR_LAT (WR_LAT), .RD_LAT (RD_LAT),
        .BEAT_GAP (BEAT_GAP), .STALL_EN (STALL_EN)
    ) u_dram (
        .clk (clk), .rstn (rstnn),
        .wr_req (dw_req), .wr_addr (dw_addr), .wr_len (dw_len),
        .wr_valid (dw_valid), .wr_data (dw_data), .wr_last (dw_last),
        .wr_ready (dw_ready),
        .rd_req (dr_req), .rd_addr (dr_addr), .rd_len (dr_len),
        .rd_valid (dr_valid), .rd_data (dr_data), .rd_ready (dr_ready),
        .rd_last (dr_last),
        .store_bursts (store_bursts), .restore_bursts (restore_bursts),
        .err_count (dram_errors)
    );

    //-----------------------------------------------------------------
    // DRAM 버스트 겹침 감시
    //
    // 추상 DRAM 포트는 한 줄짜리(single-ported)라 쓰기 버스트와 읽기
    // 버스트를 동시에 열면 안 됩니다. 직렬화는 호출 쪽(grover_dram_shot_fsm)
    // 책임이고 grover_dram_amp_store.v 머리말에 적혀 있습니다. 나중에 붙을
    // MIG/AXI 브리지는 이 전제에 기대도 되므로, 최상단 포트에서 직접 봅니다.
    // dram_burst_model 은 쓰기·읽기 FSM 이 따로라 겹쳐도 못 잡습니다.
    //
    //   wr_open  wr_req 에서 1, 마지막 beat 가 받아지면 0
    //   rd_open  rd_req 에서 1, 마지막 beat 가 받아지면 0
    //   둘이 같은 사이클에 열려 있으면(요청 펄스 사이클 포함) 겹침 1 사이클
    //
    // 읽기 쪽 마지막 beat 는 rd_last 로 판정합니다. 이 모델은 rd_last 를
    // 제대로 내므로 감시 목적에는 충분합니다.
    //-----------------------------------------------------------------
    reg     wr_open = 1'b0;
    reg     rd_open = 1'b0;
    integer overlap_cycles = 0;

    always @(posedge clk) begin
        if (!rstnn) begin
            wr_open <= 1'b0;
            rd_open <= 1'b0;
        end else begin
            if (dw_req)                             wr_open <= 1'b1;
            else if (dw_valid && dw_ready && dw_last) wr_open <= 1'b0;
            if (dr_req)                             rd_open <= 1'b1;
            else if (dr_valid && dr_ready && dr_last) rd_open <= 1'b0;

            if ((wr_open || dw_req) && (rd_open || dr_req)) begin
                if (overlap_cycles == 0)
                    $display("  FAIL DRAM 쓰기·읽기 버스트가 겹쳤습니다 (t=%0t)", $time);
                overlap_cycles = overlap_cycles + 1;
            end
        end
    end

    //-----------------------------------------------------------------
    // 데이터셋 두 벌
    //
    //   배열 A (매핑 검사용)   짝수 i -> i,   홀수 i -> i + 16384
    //       한 AHB 워드의 하위 16비트가 짝수 칸, 상위 16비트가 홀수 칸입니다.
    //       LT 256 을 걸면 정답이 짝수 인덱스 0..254 뿐(128개)이라, 적재기가
    //       두 반쪽을 바꿔 넣거나 인덱스를 한 칸 밀면 IP 가 홀수 인덱스를
    //       내놓고 호스트 쪽 판정에서 그 즉시 걸립니다. 홀수 쪽 최대값이
    //       16383 + 16384 = 32767 이라 16비트 signed 에 딱 들어갑니다.
    //
    //   배열 B (궤적 대조용)   data[i] = i
    //       tb_dram_core.v 와 같은 배열입니다. 같은 배열·같은 시드여야 두
    //       로그의 궤적을 맞댈 수 있습니다.
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

    // 주소를 바이트 단위로 직접 주는 판. pslverr 검사(H3)에만 씁니다.
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

    // 이름 인자를 1024비트(128바이트)로 둡니다. 한글은 UTF-8 로 글자당
    // 3바이트라 256비트면 열 글자 남짓에서 잘립니다.
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

    // DMA_COMMAND 를 쓰고 끝(done_sticky)이나 거절(dma_error)을 기다립니다.
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
    // burst 비트는 이 갈래 Main IP 가 읽지 않지만, 펌웨어 CKPT_SINGLE 모드가
    // 켜는 비트라 1 로 둡니다 (tb_dram_core 도 burst_enable=1 입니다).
    task configure(input a_shot, input integer jt, input [1:0] mode,
                   input signed [15:0] ta, input signed [15:0] tb,
                   input [31:0] sj, input [31:0] sm, input [15:0] cap,
                   input en_enum);
    begin
        apb_write(`CSR_IDX_CONTROL,     {28'd0, mode, 1'b1, a_shot});
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
    reg [31:0] r_status, r_idx, r_trials, r_lbbht, r_iters, r_cyc;

    task read_result;
    begin
        apb_read(`CSR_IDX_STATUS,       r_status);
        apb_read(`CSR_IDX_RESULT_INDEX, r_idx);
        apb_read(`CSR_IDX_TRIAL_COUNT,  r_trials);
        apb_read(`CSR_IDX_L_BBHT,       r_lbbht);
        apb_read(`CSR_IDX_ACTUAL_ITER,  r_iters);
        apb_read(`CSR_IDX_CYCLE_COUNT,  r_cyc);
    end
    endtask

    // 탐색 한 번을 호스트가 하듯이: 설정 -> COMMAND -> STATUS 폴링 -> 결과.
    // CASE 줄 형식은 tb_dram_core.v 와 똑같습니다. equiv_report.py 가 이 줄을
    // 레이블로 짝지어 맞댑니다.
    //
    // mid_busy 가 1 이면 탐색이 도는 동안 두 가지를 밀어 넣습니다 (H10).
    //   DMA_COMMAND  busy_error 로 거절되어야 하고 배열·DRAM 표는 그대로
    //   COMMAND      start 수락 조건의 !search_busy 항에 걸려 버려져야 함
    // 어느 쪽이든 탐색은 흔들리면 안 됩니다. 궤적은 equiv 대조가 봅니다.
    task run_case(input [1023:0] label,
                  input a_shot, input integer jt, input [1:0] mode,
                  input signed [15:0] ta, input signed [15:0] tb,
                  input [31:0] sj, input [31:0] sm, input [15:0] cap,
                  input integer expect_success, input integer expect_cfgerr,
                  input en_enum, input mid_busy);
        integer to;
        integer ok;
        reg [31:0] st, dst;
        reg [31:0] frontier_before;
    begin
        configure(a_shot, jt, mode, ta, tb, sj, sm, cap, en_enum);
        apb_write(`CSR_IDX_COMMAND, 32'd1);

        if (mid_busy) begin
            // busy 가 선 것을 확인한 다음에 DMA 를 넣어야 "탐색 중" 이 됩니다.
            st = 32'd0;
            while (!st[`BBHT_ST_BUSY] && !st[`BBHT_ST_DONE_STICKY])
                apb_read(`CSR_IDX_STATUS, st);
            if (!st[`BBHT_ST_BUSY]) begin
                $display("  FAIL %0s: busy 를 보기 전에 끝났습니다 (H10 불성립)", label);
                errors = errors + 1;
            end
            frontier_before = {25'd0, frontier_j};
            do_dma(SRAM_BASE, NDATA, dst);
            if (!dst[`BBHT_DMA_BUSY_ERROR] || !dst[`BBHT_DMA_DMA_ERROR]) begin
                $display("  FAIL [H10] 탐색 중 DMA 가 거절되지 않았습니다 (DMA_STATUS=0x%08x)", dst);
                errors = errors + 1;
            end else $display("  ok   [H10] 탐색 중 DMA -> busy_error (DMA_STATUS=0x%02x)", dst[7:0]);
            // 거절된 DMA 는 load_start 를 내지 않으므로 표가 버려지면 안 됩니다.
            // 탐색이 계속 도는 중이라 frontier 는 그대로이거나 더 자라야 합니다.
            if ({25'd0, frontier_j} < frontier_before) begin
                $display("  FAIL [H10] 거절된 DMA 뒤 frontier 가 %0d -> %0d 로 줄었습니다",
                         frontier_before, frontier_j);
                errors = errors + 1;
            end else $display("  ok   [H10] 거절된 DMA 가 DRAM 표를 건드리지 않음 (frontier %0d -> %0d)",
                              frontier_before, frontier_j);

            // 두 번째 COMMAND. 받아들여졌다면 탐색이 처음부터 다시 돌거나
            // 끝난 뒤 busy 가 한 번 더 섭니다.
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

        $display("CASE %0s valid=%0d idx=%0d trials=%0d lbbht=%0d cfgerr=%0d shotlim=%0d budlim=%0d | iters=%0d cyc=%0d",
                 label, r_status[`BBHT_ST_RESULT_VALID], r_idx, r_trials, r_lbbht,
                 r_status[`BBHT_ST_CONFIG_ERROR], r_status[`BBHT_ST_SHOT_LIMIT],
                 r_status[`BBHT_ST_BUDGET_LIMIT], r_iters, r_cyc);
        $display("      DRAM 저장누적=%0d 복원누적=%0d frontier=%0d 오류=%0d",
                 store_bursts, restore_bursts, frontier_j, dram_errors);
        if (ok != 0) $display("  ok   %0s", label);
    end
    endtask

    //-----------------------------------------------------------------
    // 본체
    //-----------------------------------------------------------------
    reg [31:0] d, st;
    reg [31:0] c2_trials, c2_lbbht, c2_idx, c2_iters;
    reg [31:0] c5_trials, c5_lbbht, c5_idx, c5_iters;
    reg [31:0] restore_before, store_before, cyc_before;
    reg [6:0]  fj_keep;
    integer    to;

    initial begin
        $display("=== tb_bbht_dram_top : hardware_dram 최상단 (WR_LAT=%0d RD_LAT=%0d BEAT_GAP=%0d STALL_EN=%0d) ===",
                 WR_LAT, RD_LAT, BEAT_GAP, STALL_EN);
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
        // 이 갈래는 정책 엔진이 없으므로 정책 텔레메트리 자리는 0 이어야
        // 합니다. CSR 주소는 hardware_bram 과 같게 남아 있습니다.
        apb_read(`CSR_IDX_POLICY_CYCLES_TOTAL, d);
        check("POLICY_CYCLES_TOTAL (정책 엔진 없음)", d, 32'd0);

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
        expect_true("DRAM 표는 비어 있음 (frontier_j=0)", frontier_j == 7'd0);

        //-------------------------------------------------------------
        $display("[H5] 16비트 매핑 -- 배열 A 에서 LT 256 은 짝수 인덱스만");
        run_case("H5 매핑 LT256", 1'b1, 0, `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 16'd100, 1, 0, 1'b0, 1'b0);
        expect_true("RESULT_INDEX 가 짝수 (하위 16비트 = 짝수 칸)", r_idx[0] == 1'b0);
        expect_true("DRAM 표가 자랐음 (frontier_j > 0)", frontier_j != 7'd0);
        expect_true("DRAM 저장 버스트가 최상단 포트로 나갔음", store_bursts != 32'd0);

        //-------------------------------------------------------------
        $display("[H6] DMA 거절");
        // (가) 정렬·범위 거절. DATA_COUNT 는 적재 때와 같은 N 으로 둡니다.
        //     거절된 DMA 는 load_start 를 내지 않으므로 배열도 DRAM 표도
        //     그대로 남아야 합니다.
        fj_keep      = frontier_j;
        store_before = store_bursts;

        do_dma(SRAM_BASE + 32'd2, NDATA, st);           // 정렬 위반
        expect_true("정렬 위반 -> align_error",
                    st[`BBHT_DMA_ALIGN_ERROR] && st[`BBHT_DMA_DMA_ERROR]);
        do_dma(32'hF000_0000, NDATA, st);               // SRAM 밖
        expect_true("SRAM 밖 주소 -> range_error", st[`BBHT_DMA_RANGE_ERROR]);
        // 시작은 SRAM 안이지만 끝이 SRAM_LAST 를 넘는 경우.
        do_dma(SRAM_LAST - 32'd3, NDATA, st);
        expect_true("끝이 SRAM 을 넘음 -> range_error", st[`BBHT_DMA_RANGE_ERROR]);

        expect_true("정렬·범위 거절 뒤 frontier_j 그대로 (DRAM 표 보존)",
                    frontier_j == fj_keep && fj_keep != 7'd0);
        expect_true("거절 중 DRAM 쓰기 없음", store_bursts == store_before);
        apb_read(`CSR_IDX_DMA_STATUS, d);
        expect_true("거절 뒤 dma_busy=0", !d[`BBHT_DMA_DMA_BUSY]);

        // (나) 개수 거절. 이쪽은 DATA_COUNT 레지스터 자체를 0 이나 N+1 로
        //     바꿔 쓰게 되고, grover_loader 는 적재가 끝난 뒤 data_count 가
        //     바뀌면 배열을 무효로 칩니다 (data_count_mismatch -> data_valid=0,
        //     cache_invalidate). 반쯤 다른 개수로 오라클을 돌리지 않으려는
        //     설계라, DRAM 표도 같이 버려지는 것이 맞습니다. DATA_COUNT 를
        //     N 으로 되돌려도 data_valid 는 다시 서지 않으므로 재적재 없이
        //     탐색하면 config_error 여야 합니다. 펌웨어 입장에서는 "개수
        //     거절을 받으면 LOAD 부터 다시" 라는 뜻입니다.
        do_dma(SRAM_BASE, 32'd0, st);                   // 개수 0
        expect_true("count=0 -> count_error", st[`BBHT_DMA_COUNT_ERROR]);
        do_dma(SRAM_BASE, NDATA + 1, st);               // 개수 초과
        expect_true("count=N+1 -> count_error", st[`BBHT_DMA_COUNT_ERROR]);
        expect_true("DATA_COUNT 가 바뀌어 DRAM 표가 버려짐 (frontier_j=0)",
                    frontier_j == 7'd0);
        run_case("H6 개수 거절 뒤 재적재 없이 탐색", 1'b1, 0, `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 16'd100, 0, 1, 1'b0, 1'b0);

        //-------------------------------------------------------------
        $display("[H7] 재적재 (배열 B) -- DRAM 표가 버려져야 함");
        fill_sram(1'b0);
        do_dma(SRAM_BASE, NDATA, st);
        check("DMA_STATUS", st, 32'h00000080);
        ds_is_a = 1'b0;
        expect_true("재적재 뒤 frontier_j = 0", frontier_j == 7'd0);

        //-------------------------------------------------------------
        // 여기부터 C1~C7 은 tb_dram_core.v 와 레이블·자극·시드·순서가 같습니다.
        // shot_cap 100, data_count N, 배열 B 도 같습니다.
        //-------------------------------------------------------------
        $display("[H8] 수동/자동 탐색, 재실행 때 DRAM 복원");
        run_case("C1 MANUAL j=6 LT256", 1'b0, 6, `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 16'd100, 1, 0, 1'b0, 1'b0);

        run_case("C2 NORMAL LT256", 1'b1, 0, `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 16'd100, 1, 0, 1'b0, 1'b0);
        c2_trials = r_trials; c2_lbbht = r_lbbht; c2_idx = r_idx; c2_iters = r_iters;
        dump_counters();

        restore_before = restore_bursts;
        run_case("C3 NORMAL LT256 재실행", 1'b1, 0, `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 16'd100, 1, 0, 1'b0, 1'b0);
        expect_true("C3 궤적이 C2 와 같음 (idx / trials / L_BBHT)",
                    r_idx == c2_idx && r_trials == c2_trials && r_lbbht == c2_lbbht);
        // C1 이 이미 j=6 까지 키워 두어 C2 부터 반복이 0 일 수 있습니다.
        // 그래서 여기서는 "늘지 않음" 만 봅니다 (tb_dram_core 와 같은 기준).
        // 표를 새로 키운 직후의 엄격한 비교는 C5 / C5b 가 합니다.
        expect_true("C3 Grover 반복이 C2 보다 늘지 않음 (DRAM 표 재사용)", r_iters <= c2_iters);
        expect_true("C3 에서 DRAM 복원이 최상단 포트를 탔음", restore_bursts > restore_before);

        //-------------------------------------------------------------
        $display("[H9] done_sticky 는 COMMAND 쓰기로만 클리어");
        apb_read(`CSR_IDX_STATUS, d);
        expect_true("STATUS 읽기는 done_sticky 를 안 지움", d[`BBHT_ST_DONE_STICKY]);
        apb_write(`CSR_IDX_THRESHOLD_A, 32'd256);
        apb_read (`CSR_IDX_STATUS, d);
        expect_true("설정 쓰기는 done_sticky 를 안 지움", d[`BBHT_ST_DONE_STICKY]);

        //-------------------------------------------------------------
        $display("[H10] 탐색 중 DMA / COMMAND -- C4 에 겹쳐서");
        run_case("C4 NORMAL GT16128", 1'b1, 0, `BBHT_PRED_GT, 16'sd16128, 16'sd0,
                 32'h0BAD_F00D, 32'h5EED_1234, 16'd100, 1, 0, 1'b0, 1'b1);

        //-------------------------------------------------------------
        $display("[H11] RANGE, 재실행, Enumeration 거절, 거절 뒤 정상 실행");
        run_case("C5 NORMAL RANGE", 1'b1, 0, `BBHT_PRED_RANGE, 16'sd1000, 16'sd1300,
                 32'hFEED_BEEF, 32'h1357_9BDF, 16'd100, 1, 0, 1'b0, 1'b0);
        c5_trials = r_trials; c5_lbbht = r_lbbht; c5_idx = r_idx; c5_iters = r_iters;

        run_case("C5b RANGE 재실행", 1'b1, 0, `BBHT_PRED_RANGE, 16'sd1000, 16'sd1300,
                 32'hFEED_BEEF, 32'h1357_9BDF, 16'd100, 1, 0, 1'b0, 1'b0);
        expect_true("C5b 궤적이 C5 와 같음",
                    r_idx == c5_idx && r_trials == c5_trials && r_lbbht == c5_lbbht);
        expect_true("C5b Grover 반복이 C5 보다 적음", r_iters < c5_iters);

        // 이 갈래는 단일탐색 전용입니다. ENUM_CFG.enable=1 은 조용히
        // 단일탐색으로 떨어지지 말고 config_error 로 거절되어야 합니다.
        run_case("C6 ENUM 거절", 1'b1, 0, `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 16'd100, 0, 1, 1'b1, 1'b0);
        expect_true("C6 enum_done 은 안 섬", !r_status[`BBHT_ST_ENUM_DONE]);
        expect_true("C6 결과 FIFO 는 비어 있음", r_status[`BBHT_ST_FIFO_EMPTY]);
        apb_read(`CSR_IDX_FIFO_COUNT, d);
        check("C6 FIFO_COUNT", d, 32'd0);

        run_case("C7 거절 후 정상 실행", 1'b1, 0, `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h2468_ACE0, 32'h1122_3344, 16'd100, 1, 0, 1'b0, 1'b0);

        //-------------------------------------------------------------
        $display("[H12] 적재 중 COMMAND 는 버려짐");
        // 여기서 적재를 다시 하므로 DRAM 표가 버려집니다. 그래서 궤적 대조
        // 케이스(C1~C7)를 전부 끝낸 뒤에 둡니다.
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
        expect_true("재적재 뒤 frontier_j = 0", frontier_j == 7'd0);

        // 버려진 다음 정상 COMMAND 는 받아야 합니다.
        run_case("H12 버려진 뒤 정상 실행", 1'b1, 0, `BBHT_PRED_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 16'd100, 1, 0, 1'b0, 1'b0);
        expect_true("궤적이 C2 와 같음 (같은 배열·같은 시드)",
                    r_idx == c2_idx && r_trials == c2_trials && r_lbbht == c2_lbbht);

        //-------------------------------------------------------------
        $display("[H13] 정답이 없는 술어 -- shot_cap 에서 멈춤");
        // 배열 B 는 0..16383 이라 EQ -1 은 정답이 없습니다. shot_cap 을 작게
        // 두어 짧게 끝냅니다. 직전 실행의 result_valid 가 남으면 안 됩니다.
        run_case("H13 EQ -1 shot_cap=4", 1'b1, 0, `BBHT_PRED_EQ, -16'sd1, 16'sd0,
                 32'hCAFE_0001, 32'hCAFE_0002, 16'd4, 0, 0, 1'b0, 1'b0);
        expect_true("result_valid=0 (직전 결과가 안 남음)", !r_status[`BBHT_ST_RESULT_VALID]);
        expect_true("shot_limit=1", r_status[`BBHT_ST_SHOT_LIMIT]);

        //-------------------------------------------------------------
        $display("[H14] DRAM 심판");
        $display("  저장 버스트 %0d / 복원 버스트 %0d / 프로토콜 오류 %0d",
                 store_bursts, restore_bursts, dram_errors);
        check("DRAM 프로토콜 오류", dram_errors, 32'd0);
        check("DRAM 쓰기·읽기 버스트 겹침 사이클", overlap_cycles, 32'd0);
        expect_true("저장과 복원이 둘 다 일어났음",
                    store_bursts != 32'd0 && restore_bursts != 32'd0);

        //-------------------------------------------------------------
        repeat (10) @(negedge clk);
        $display("=== 결과: 오류 %0d 건 ===", errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $finish;
    end

    // 실행 카운터 덤프. 판정이 아니라 기록입니다. 정책·plan 텔레메트리는
    // 이 갈래에 없어서 0 이어야 하므로 그것만 판정합니다.
    task dump_counters;
        reg [31:0] v;
    begin
        $display("  -- 카운터");
        $display("     trial_count              = %0d", r_trials);
        $display("     L_BBHT                   = %0d", r_lbbht);
        $display("     actual_grover_iterations = %0d", r_iters);
        $display("     cycle_count              = %0d", r_cyc);
        apb_read(`CSR_IDX_POLICY_MEMO_HIT, v);
        check("POLICY_MEMO_HIT (정책 엔진 없음)", v, 32'd0);
        apb_read(`CSR_IDX_PLAN_FIFO_HIT_COUNT, v);
        check("PLAN_FIFO_HIT_COUNT (plan FIFO 없음)", v, 32'd0);
    end
    endtask

    // 무한 루프 방지
    initial begin
        #`SIM_TIMEOUT_NS;
        $display("FAIL: 타임아웃");
        $finish;
    end

endmodule
