//=====================================================================
// tb_cache_ctrl.v -- 재개 캐시 판정 규칙 세 줄 (소유자 D)
//
// 붙일 데이터패스가 없어도 이 블록은 단독으로 전부 검증됩니다. 그래서
// D 가 C 를 기다리지 않아도 됩니다.
//
//   do_init = !cache_valid || force_init || (j_req < j_cur)
//   delta_j = do_init ? j_req : (j_req - j_cur)
//   무효화(cfg_we)는 완료 갱신(iter_done)보다 우선
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module tb_cache_ctrl;
    reg         clk = 0, rstn = 0;
    reg         shot_start = 0, force_init = 0, cfg_we = 0, iter_done = 0;
    reg  [15:0] j_req = 0;
    wire        do_init, cache_valid;
    wire [15:0] delta_j, j_cur;

    integer errors = 0;

    always #5 clk = ~clk;

    grover_cache_ctrl dut (
        .clk(clk), .rstn(rstn),
        .shot_start(shot_start), .j_req(j_req),
        .force_init(force_init), .cfg_we(cfg_we), .iter_done(iter_done),
        .do_init(do_init), .delta_j(delta_j),
        .j_cur(j_cur), .cache_valid(cache_valid)
    );

    // 한 샷을 흉내 냅니다: 목표 j 로 시작 -> 반복 완료
    task run_shot(input [15:0] j, input exp_init, input [15:0] exp_delta);
        begin
            @(posedge clk); #1;
            j_req = j; shot_start = 1;
            #1;                      // do_init / delta_j 는 조합이라 전파를 기다립니다
            if (do_init !== exp_init) begin
                errors = errors + 1;
                $display("FAIL j=%0d do_init=%0b exp=%0b (j_cur=%0d valid=%0b)",
                         j, do_init, exp_init, j_cur, cache_valid);
            end
            if (delta_j !== exp_delta) begin
                errors = errors + 1;
                $display("FAIL j=%0d delta=%0d exp=%0d", j, delta_j, exp_delta);
            end
            @(posedge clk); #1; shot_start = 0;
            @(posedge clk); #1; iter_done = 1;
            @(posedge clk); #1; iter_done = 0;
        end
    endtask

    task pulse_cfg_we;
        begin @(posedge clk); #1; cfg_we = 1; @(posedge clk); #1; cfg_we = 0; end
    endtask

    task pulse_force;
        begin @(posedge clk); #1; force_init = 1; @(posedge clk); #1; force_init = 0; end
    endtask

    initial begin
        repeat (3) @(posedge clk); #1; rstn = 1;
        @(posedge clk);

        // 규칙 1 -- 캐시가 없으면 초기화부터
        run_shot(16'd3, 1'b1, 16'd3);
        if (j_cur !== 16'd3 || cache_valid !== 1'b1) begin
            errors = errors + 1; $display("FAIL 완료 후 j_cur=%0d valid=%0b", j_cur, cache_valid);
        end

        // 규칙 2 -- 앞으로 갈 때는 차이만큼만
        run_shot(16'd7, 1'b0, 16'd4);
        run_shot(16'd8, 1'b0, 16'd1);

        // 같은 자리에 다시 -- 전진 0
        run_shot(16'd8, 1'b0, 16'd0);

        // 규칙 3 -- 뒤로 갈 때는 초기화부터
        run_shot(16'd2, 1'b1, 16'd2);

        // force_init 은 캐시가 멀쩡해도 초기화
        pulse_force;
        run_shot(16'd5, 1'b1, 16'd5);

        // 설정 레지스터 쓰기가 캐시를 그 자리에서 내립니다
        pulse_cfg_we;
        if (cache_valid !== 1'b0) begin
            errors = errors + 1; $display("FAIL cfg_we 가 cache_valid 를 못 내림");
        end
        run_shot(16'd4, 1'b1, 16'd4);

        // 무효화가 완료 갱신보다 우선인가 -- 같은 사이클에 둘 다
        @(posedge clk); #1; j_req = 16'd9; shot_start = 1;
        @(posedge clk); #1; shot_start = 0;
        @(posedge clk); #1; iter_done = 1; cfg_we = 1;
        @(posedge clk); #1; iter_done = 0; cfg_we = 0;
        if (cache_valid !== 1'b0) begin
            errors = errors + 1;
            $display("FAIL 무효화가 완료 갱신에 졌습니다 (valid=%0b)", cache_valid);
        end

        if (errors == 0) $display("tb_cache_ctrl: PASS");
        else begin $display("tb_cache_ctrl: FAIL (%0d errors)", errors); $fatal; end
        $finish;
    end
endmodule
