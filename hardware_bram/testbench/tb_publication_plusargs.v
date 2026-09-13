//==============================================================================
// tb_standalone_top.v -- bbht_standalone_top 전체 시스템 시뮬레이션
//
// 호스트 PC를 TB가 흉내낸다.  UART 프레임만으로 다음을 수행한다.
//
//   1. PING 으로 동기 확인
//   2. DATA_COUNT / DATA_ADDR(=target_count) 쓰고 DMA_COMMAND 로 데이터셋 생성
//   3. DMA_STATUS 폴링 (bit7 done, bit1 error)
//   4. CONTROL / THRESHOLD / SHOT_CAP / SEED 설정
//   5. COMMAND 로 탐색 시작
//   6. STATUS 폴링 (bit2 done)
//   7. RESULT_INDEX / TRIAL_COUNT / L_BBHT / ACTUAL_ITER / CYCLE_COUNT 읽기
//
// 이 흐름은 main_clean.c 의 dma_load_dataset() + run_search() 와 같다.
// 다른 것은 CSR 접근 경로뿐이다 (RISC-V 코어 -> APB  vs  호스트 UART -> APB).
//
// 시드는 RVX 실험과 같은 seed_roster[0] 을 쓴다.
// 타깃 256개 조건은 평균 반복 횟수가 가장 작아 시뮬레이션이 가장 빠르다
// (RVX 로그: SUMMARY,256,50,... normal_iter=310 -> 50샷 평균 약 6.2회).
//==============================================================================
`timescale 1ns/1ps

module tb_standalone_top;

    localparam integer BAUD   = 1_000_000;
    localparam integer BIT_NS = 1_000_000_000 / BAUD;

    // ---- CSR 오프셋 (main_clean.c 와 동일) ----
    localparam [15:0] CSR_COMMAND      = 16'h0000;
    localparam [15:0] CSR_CONTROL      = 16'h0004;
    localparam [15:0] CSR_J_TARGET     = 16'h0008;
    localparam [15:0] CSR_THRESHOLD_A  = 16'h000C;
    localparam [15:0] CSR_THRESHOLD_B  = 16'h0010;
    localparam [15:0] CSR_DATA_COUNT   = 16'h0014;
    localparam [15:0] CSR_SHOT_CAP     = 16'h0018;
    localparam [15:0] CSR_SEED_J       = 16'h001C;
    localparam [15:0] CSR_SEED_MEAS    = 16'h0020;
    localparam [15:0] CSR_STATUS       = 16'h0024;
    localparam [15:0] CSR_RESULT_INDEX = 16'h0028;
    localparam [15:0] CSR_TRIAL_COUNT  = 16'h002C;
    localparam [15:0] CSR_L_BBHT       = 16'h0030;
    localparam [15:0] CSR_ACTUAL_ITER  = 16'h0034;
    localparam [15:0] CSR_CYCLE_COUNT  = 16'h0038;
    localparam [15:0] CSR_ENUM_CFG     = 16'h003C;
    localparam [15:0] CSR_DATA_ADDR    = 16'h0058;
    localparam [15:0] CSR_DMA_COMMAND  = 16'h005C;
    localparam [15:0] CSR_DMA_STATUS   = 16'h0060;

    // CONTROL: bit0 auto_shot, bit1 burst_enable, bits3:2 predicate_mode
    // EQ = 2 -> normal 0x9, K4/H4 0xB
    localparam [31:0] CONTROL_NORMAL_EQ = 32'h0000_0009;
    localparam [31:0] CONTROL_K4H4_EQ   = 32'h0000_000B;

    localparam [31:0] TARGET_VALUE = 32'd12345;

    reg CLK100MHZ = 1'b0;
    always #5 CLK100MHZ = ~CLK100MHZ;      // 100 MHz

    reg  ck_rst = 1'b0;
    reg  host_tx = 1'b1;
    wire fpga_tx;
    reg  [1:0] btn = 2'b00;
    wire [3:0] led;

    bbht_standalone_top u_top (
        .CLK100MHZ(CLK100MHZ),
        .ck_rst(ck_rst),
        .uart_txd_in(host_tx),
        .uart_rxd_out(fpga_tx),
        .btn(btn),
        .led(led)
    );

    //--------------------------------------------------------------------------
    // 호스트 UART 모델
    //--------------------------------------------------------------------------
    reg [7:0] rxq [0:1023];
    integer   rxq_wr, rxq_rd;
    reg [7:0] cap;
    integer   ci;

    initial begin
        rxq_wr = 0;
        rxq_rd = 0;
        forever begin
            @(negedge fpga_tx);
            #(BIT_NS + BIT_NS/2);
            for (ci = 0; ci < 8; ci = ci + 1) begin
                cap[ci] = fpga_tx;
                #(BIT_NS);
            end
            rxq[rxq_wr] = cap;
            rxq_wr = rxq_wr + 1;
            wait (fpga_tx == 1'b1);
        end
    end

    task host_send;
        input [7:0] b;
        integer k;
        begin
            host_tx = 1'b0;
            #(BIT_NS);
            for (k = 0; k < 8; k = k + 1) begin
                host_tx = b[k];
                #(BIT_NS);
            end
            host_tx = 1'b1;
            #(BIT_NS);
        end
    endtask

    reg [7:0] got;
    task host_recv;
        begin
            wait (rxq_wr != rxq_rd);
            got    = rxq[rxq_rd];
            rxq_rd = rxq_rd + 1;
        end
    endtask

    reg [31:0] rdval;
    reg [7:0]  rdst;
    integer    fail;

    task csr_write;
        input [15:0] a;
        input [31:0] d;
        begin
            host_send(8'h57);
            host_send(a[7:0]);   host_send(a[15:8]);
            host_send(d[7:0]);   host_send(d[15:8]);
            host_send(d[23:16]); host_send(d[31:24]);
            host_recv(); rdst = got;
            if (rdst !== 8'h4B) begin
                $display("  !! CSR write 0x%04X 응답 0x%02X (기대 'K')", a, rdst);
                fail = fail + 1;
            end
        end
    endtask

    task csr_read;
        input [15:0] a;
        begin
            host_send(8'h52);
            host_send(a[7:0]); host_send(a[15:8]);
            host_recv(); rdval[7:0]   = got;
            host_recv(); rdval[15:8]  = got;
            host_recv(); rdval[23:16] = got;
            host_recv(); rdval[31:24] = got;
            host_recv(); rdst         = got;
            if (rdst !== 8'h4B) begin
                $display("  !! CSR read 0x%04X 응답 0x%02X (기대 'K')", a, rdst);
                fail = fail + 1;
            end
        end
    endtask

    //--------------------------------------------------------------------------
    // 실행 결과
    //--------------------------------------------------------------------------
    reg [31:0] r_status, r_index, r_trial, r_lbbht, r_iter, r_cycle;
    integer    poll;

    task load_dataset;
        input [31:0] tcount;
        begin
            $display("[데이터셋] target_count = %0d", tcount);
            csr_write(CSR_DATA_COUNT, 32'd16384);
            csr_write(CSR_DATA_ADDR,  tcount);
            csr_write(CSR_DMA_COMMAND, 32'd1);

            poll = 0;
            rdval = 32'd0;
            while (((rdval & 32'h80) == 32'd0) && (poll < 2000)) begin
                csr_read(CSR_DMA_STATUS);
                poll = poll + 1;
            end

            $display("  DMA_STATUS = 0x%08X  (bit7 done, bit1 error)  폴링 %0d회",
                     rdval, poll);
            if ((rdval & 32'h80) == 32'd0) begin
                $display("  !! 데이터셋 생성 미완료");
                fail = fail + 1;
            end
            if ((rdval & 32'h02) != 32'd0) begin
                $display("  !! 생성 오류");
                fail = fail + 1;
            end
        end
    endtask

    task run_search;
        input [31:0] control;
        input [31:0] seed_j;
        input [31:0] seed_meas;
        begin
            csr_write(CSR_CONTROL,     control);
            csr_write(CSR_J_TARGET,    32'd0);
            csr_write(CSR_THRESHOLD_A, TARGET_VALUE);
            csr_write(CSR_THRESHOLD_B, 32'd0);
            csr_write(CSR_DATA_COUNT,  32'd16384);
            csr_write(CSR_SHOT_CAP,    32'd100);
            csr_write(CSR_SEED_J,      seed_j);
            csr_write(CSR_SEED_MEAS,   seed_meas);
            csr_write(CSR_ENUM_CFG,    32'd0);

            csr_write(CSR_COMMAND,     32'd1);

            poll = 0;
            rdval = 32'd0;
            while (((rdval & 32'h04) == 32'd0) && (poll < 20000)) begin
                csr_read(CSR_STATUS);
                poll = poll + 1;
            end
            r_status = rdval;

            csr_read(CSR_RESULT_INDEX); r_index = rdval;
            csr_read(CSR_TRIAL_COUNT);  r_trial = rdval;
            csr_read(CSR_L_BBHT);       r_lbbht = rdval;
            csr_read(CSR_ACTUAL_ITER);  r_iter  = rdval;
            csr_read(CSR_CYCLE_COUNT);  r_cycle = rdval;
        end
    endtask

    task report;
        input [255:0] tag;
        begin
            $display("  status       = 0x%08X", r_status);
            $display("    busy=%0d load_busy=%0d done=%0d result_valid=%0d",
                     r_status[0], r_status[1], r_status[2], r_status[3]);
            $display("    config_err=%0d shot_limit=%0d budget_limit=%0d",
                     r_status[4], r_status[5], r_status[6]);
            $display("    amp_ovf=%0d zero_w=%0d load_err=%0d",
                     r_status[7], r_status[8], r_status[9]);
            $display("  result_index = %0d", r_index);
            $display("  trial_count  = %0d", r_trial);
            $display("  L_BBHT       = %0d", r_lbbht);
            $display("  actual_iter  = %0d", r_iter);
            $display("  cycle_count  = %0d", r_cycle);
        end
    endtask

    // seed_roster[0]
    localparam [31:0] SEED_J_0    = 32'h7B1DCDAF;
    localparam [31:0] SEED_MEAS_0 = 32'h24370DF2;
    integer pub_tc;
    integer pub_seed_idx;
    reg [31:0] pub_seed_j;
    reg [31:0] pub_seed_meas;

    reg [31:0] n_index, n_trial, n_lbbht, n_iter, n_cycle;
    reg [31:0] k_index, k_trial, k_lbbht, k_iter, k_cycle;

    initial begin
        fail = 0;

        #200;
        ck_rst = 1'b1;          // 리셋 해제 (active-low)
        #(BIT_NS * 4);

        $display("=== bbht_standalone_top : UART 만으로 전체 흐름 ===");
        $display("");

        // ---- PING ----
        host_send(8'h50);
        host_recv();
        if (got !== 8'h4B) begin
            $display("[PING] FAIL (0x%02X)", got);
            fail = fail + 1;
        end
        else begin
            host_recv();
            $display("[PING] OK, 버전 0x%02X", got);
        end
        $display("");

        // ---- 데이터셋 ----
        
        pub_tc        = 256;
        pub_seed_idx  = 0;
        pub_seed_j    = SEED_J_0;
        pub_seed_meas = SEED_MEAS_0;

        if (!$value$plusargs("TC=%d", pub_tc))
            pub_tc = 256;
        if (!$value$plusargs("SEED_IDX=%d", pub_seed_idx))
            pub_seed_idx = 0;
        if (!$value$plusargs("SEED_J=%h", pub_seed_j))
            pub_seed_j = SEED_J_0;
        if (!$value$plusargs("SEED_MEAS=%h", pub_seed_meas))
            pub_seed_meas = SEED_MEAS_0;

        $display(
            "PUB_CASE,target=%0d,seed_index=%0d,seed_j=%08x,seed_meas=%08x",
            pub_tc, pub_seed_idx, pub_seed_j, pub_seed_meas
        );

        load_dataset(pub_tc);
        $display("");

        // ---- NORMAL ----
        $display("[탐색] NORMAL  (auto_shot=1, burst=0, EQ)");
        run_search(CONTROL_NORMAL_EQ, pub_seed_j, pub_seed_meas);
        report("normal");
        n_index = r_index; n_trial = r_trial; n_lbbht = r_lbbht;
        n_iter  = r_iter;  n_cycle = r_cycle;
        $display("");

        // ---- K4/H4 ----
        $display("[탐색] K4/H4  (auto_shot=1, burst=1, EQ)");
        run_search(CONTROL_K4H4_EQ, pub_seed_j, pub_seed_meas);
        report("k4h4");
        k_index = r_index; k_trial = r_trial; k_lbbht = r_lbbht;
        k_iter  = r_iter;  k_cycle = r_cycle;
        $display("");

        // ---- 쌍 일관성 (pair_is_consistent 와 동일 기준) ----
        $display("=== 쌍 일관성 검사 ===");

        $write("  trial_count 일치      %0d vs %0d  ", n_trial, k_trial);
        if (n_trial === k_trial) $display("PASS");
        else begin $display("FAIL"); fail = fail + 1; end

        $write("  L_BBHT 일치           %0d vs %0d  ", n_lbbht, k_lbbht);
        if (n_lbbht === k_lbbht) $display("PASS");
        else begin $display("FAIL"); fail = fail + 1; end

        $write("  result_index 일치     %0d vs %0d  ", n_index, k_index);
        if (n_index === k_index) $display("PASS");
        else begin $display("FAIL"); fail = fail + 1; end

        $write("  normal actual==L_BBHT %0d vs %0d  ", n_iter, n_lbbht);
        if (n_iter === n_lbbht) $display("PASS");
        else begin $display("FAIL"); fail = fail + 1; end

        $write("  k4h4 actual <= L_BBHT %0d <= %0d  ", k_iter, k_lbbht);
        if (k_iter <= k_lbbht) $display("PASS");
        else begin $display("FAIL"); fail = fail + 1; end

        $display("");
        $display("  물리 반복 절감  %0d -> %0d", n_iter, k_iter);
        $display("  사이클          %0d -> %0d", n_cycle, k_cycle);
        $display("");

        $display("  LED = %b (hb, busy, result, error)", led);

        if (fail == 0) $display("=== ALL PASS ===");
        else           $display("=== %0d FAILURE(S) ===", fail);

        $finish;
    end

    // 안전장치
    initial begin
        #500_000_000;
        $display("!! TIMEOUT");
        $finish;
    end

endmodule
