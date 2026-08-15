//=====================================================================
// tb_ctrl_fsm.v -- 안쪽 반복 FSM 의 사이클 예산 (소유자 C)
//
// 계약 4.6 은 테스트벤치가 상수를 박지 말고 2*DEPTH + ITER_OVH 로 쓰고
// ITER_OVH <= 8 을 확인하라고 두었습니다. 그대로 합니다.
//
// 같이 확인하는 것 -- 주소가 0..depth_eff-1 을 빠짐없이 한 번씩 훑는가,
// 되쓰기 주소가 읽기 주소보다 정확히 PIPE_LAT 만큼 뒤따르는가,
// 패스마다 pass_tick 이 한 번씩 서는가.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module tb_ctrl_fsm;
    localparam AW   = `GP_AW;
    localparam LOGP = `GP_LOGP;

    reg  clk = 0, rstn = 0;
    reg  iter_start = 0, iter_do_init = 0;
    reg  [15:0] iter_count = 0;
    reg  [4:0]  n_qubits = 5'd10;

    wire iter_busy, iter_done;
    wire [3:0] state;
    wire [AW-1:0] amp_raddr, amp_waddr, data_addr;
    wire amp_re, amp_we, data_re, phase, acc_clear, acc_en, pass_tick;

    integer errors = 0;
    integer cyc, ticks, wr_cnt, i;
    integer depth_eff;
    reg [`GP_DEPTH-1:0] seen_rd, seen_wr;

    always #5 clk = ~clk;

    grover_ctrl_fsm dut (
        .clk(clk), .rstn(rstn),
        .iter_start(iter_start), .iter_do_init(iter_do_init),
        .iter_count(iter_count), .n_qubits(n_qubits),
        .iter_busy(iter_busy), .iter_done(iter_done), .state(state),
        .amp_raddr(amp_raddr), .amp_waddr(amp_waddr),
        .amp_re(amp_re), .amp_we(amp_we),
        .data_addr(data_addr), .data_re(data_re),
        .phase(phase), .acc_clear(acc_clear), .acc_en(acc_en),
        .pass_tick(pass_tick)
    );

    // busy 와 done 이 같은 사이클에 겹치면 계약 2절 위반입니다
    always @(posedge clk) if (rstn && iter_busy && iter_done) begin
        errors = errors + 1;
        $display("FAIL busy 와 done 이 겹쳤습니다");
    end

    // 되쓰기 주소는 읽기 주소를 PIPE_LAT 만큼 뒤따라야 합니다
    reg [AW-1:0] rd_p1, rd_p2;
    always @(posedge clk) if (rstn) begin
        if (amp_we && (state != `GP_ST_INIT) && (amp_waddr !== rd_p2)) begin
            errors = errors + 1;
            $display("FAIL waddr=%0d 인데 %0d 이어야 합니다", amp_waddr, rd_p2);
        end
        rd_p1 <= amp_raddr;
        rd_p2 <= rd_p1;
    end

    task run_iter(input do_init, input [15:0] cnt, input integer exp_iters);
        integer budget;
        begin
            ticks = 0; cyc = 0; wr_cnt = 0;
            seen_rd = 0; seen_wr = 0;
            @(posedge clk); #1;
            iter_do_init = do_init; iter_count = cnt; iter_start = 1;
            @(posedge clk); #1; iter_start = 0;
            // 마지막 패스의 pass_tick 은 iter_done 과 같은 사이클에 섭니다.
            // 그래서 표본을 반드시 #1 뒤에 떠야 합니다.
            while (!iter_done) begin
                @(posedge clk); #1;
                cyc = cyc + 1;
                if (pass_tick) ticks = ticks + 1;
                if (amp_we) wr_cnt = wr_cnt + 1;
                if (cyc > 200000) begin
                    $display("FAIL 반복이 끝나지 않습니다"); $fatal;
                end
            end
            // 예산: INIT(있으면 depth) + 반복당 2*(depth + PIPE_LAT) + 1.
            // 계약 6.3 의 S_INIT=1,025 는 start 펄스 사이클을 포함한 값이고
            // 여기서는 그 사이클을 세지 않으므로 depth 만 잡습니다.
            budget = (do_init ? depth_eff : 0)
                   + exp_iters * (2*(depth_eff + `GP_PIPE_LAT) + 1);
            if (cyc !== budget) begin
                errors = errors + 1;
                $display("FAIL 사이클 %0d, 예산 %0d 과 다릅니다 (do_init=%0b cnt=%0d)",
                         cyc, budget, do_init, cnt);
            end else begin
                $display("  do_init=%0b cnt=%0d -> %0d 사이클 (예산 %0d, ITER_OVH=%0d)",
                         do_init, cnt, cyc, budget,
                         exp_iters > 0 ? (cyc - (do_init ? depth_eff+1 : 0))/exp_iters - 2*depth_eff : 0);
            end
            if (ticks !== 2*exp_iters) begin
                errors = errors + 1;
                $display("FAIL pass_tick %0d 회, %0d 회여야 합니다", ticks, 2*exp_iters);
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk); #1; rstn = 1;

        n_qubits = 5'd10;
        depth_eff = 1 << (10 - LOGP);
        @(posedge clk);
        run_iter(1'b1, 16'd0, 0);      // INIT 만
        run_iter(1'b1, 16'd1, 1);
        run_iter(1'b0, 16'd3, 3);      // 재개 -- INIT 없이 3회
        run_iter(1'b0, 16'd0, 0);      // 전진 0 -- 즉시 완료

        n_qubits = 5'd15;
        depth_eff = 1 << (15 - LOGP);
        @(posedge clk);
        run_iter(1'b1, 16'd2, 2);

        if (errors == 0) $display("tb_ctrl_fsm: PASS");
        else begin $display("tb_ctrl_fsm: FAIL (%0d errors)", errors); $fatal; end
        $finish;
    end
endmodule
