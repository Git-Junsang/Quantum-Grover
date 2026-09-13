//=====================================================================
// tb_dram_bench500.v -- 보드 500런과 같은 500 워크로드를 통신 계층 없이
// Main IP 레벨에서 재현합니다.
//
// tb_dram_bench250.v 와 하는 일은 같고 시드 로스터만 100쌍입니다
// (정답 개수 M in {1,4,16,64,256} x 시드 100쌍 = 500). 따로 만든 이유는
// 250쌍 TB 가 NSEED=50 으로 고정돼 있고, 그쪽이 이미 낸 근거를 건드리지
// 않기 위해서입니다.
//
// 500 워크로드로 올린 이유는 두 갈래를 같은 표본에서 맞대기 위해서입니다.
// 정본 K3/H3-E4-M2 의 보드 실측·6단계 ablation 이 전부 이 500 워크로드를
// 쓰므로, DRAM 갈래도 같은 표본으로 재야 "DRAM 이 체크포인트를 이기냐
// 지냐" 를 정본 근거와 같은 자리에서 말할 수 있습니다.
//
//   predicate = EQ, threshold_a = 12345, data_count = 16384, auto_shot = 1,
//   shot_cap = 100, enum_enable = 0
//
// 통신 계층(APB/AHB, C 드라이버)은 DRAM 갈래에 아직 없으므로 여기서는
// tb_dram_core.v 와 같은 방식으로 Main IP 포트를 직접 흔듭니다. 답과 궤적은
// 그 계층을 거치든 안 거치든 바뀌지 않습니다.
//
//   GD_DRAM_BRANCH 정의  -> hardware_dram/src (burst_enable 은 계약
//                           호환용, DRAM 표를 무조건 씁니다)
//   정의 안 함           -> hardware_bram/src, CHECKPOINT_ENABLE=1 로
//                           한 번만 빌드하고 burst_enable 을 0/1 로 매
//                           케이스마다 바꿔 같은 빌드에서 Normal 과
//                           K3/H3-E4-M2 를 둘 다 얻습니다 (실물 보드가
//                           런타임에 CSR 로 고르는 것과 같습니다)
//
// 데이터셋은 GD_WL_DIR 에 있는 data_m<M>.hex (bin_to_hex.py 로 변환) 와
// seeds.txt 를 읽습니다. 원본은
// software/golden/tools/dump_bench500_workload.py 가 만듭니다.
//=====================================================================
`timescale 1ns/1ps
`ifdef GD_DRAM_BRANCH
`include "grover_dram_param.vh"
`else
`include "grover_param.vh"
`endif

module tb_dram_bench500 #(
    parameter integer WR_LAT   = 4,
    parameter integer RD_LAT   = 12,
    parameter integer BEAT_GAP = 0,
    parameter integer STALL_EN = 0
);
    localparam integer ROW_BITS = `GP_P * `GP_AMP_W;
    localparam integer NDATA    = `GP_N;
    localparam integer NSEED    = 100;

    reg clk  = 1'b0;
    reg rstn = 1'b0;
    always #5 clk = ~clk;

    //-----------------------------------------------------------------
    // 데이터셋 5벌을 미리 메모리에 올려 둡니다. M 이 바뀔 때마다 다시
    // $readmemh 하는 대신, 전부 읽어 두고 do_load 에서 골라 씁니다.
    //-----------------------------------------------------------------
    localparam integer NM = 5;
    reg signed [`GP_DATA_W-1:0] mem_m1   [0:NDATA-1];
    reg signed [`GP_DATA_W-1:0] mem_m4   [0:NDATA-1];
    reg signed [`GP_DATA_W-1:0] mem_m16  [0:NDATA-1];
    reg signed [`GP_DATA_W-1:0] mem_m64  [0:NDATA-1];
    reg signed [`GP_DATA_W-1:0] mem_m256 [0:NDATA-1];

    integer m_values [0:NM-1];
    initial begin
        m_values[0] = 1;   m_values[1] = 4;   m_values[2] = 16;
        m_values[3] = 64;  m_values[4] = 256;
    end

    reg [31:0] seed_j_arr [0:NSEED-1];
    reg [31:0] seed_m_arr [0:NSEED-1];

    //-----------------------------------------------------------------
    // Main IP 포트 (tb_dram_core.v 와 같은 목록)
    //-----------------------------------------------------------------
    reg                                start = 1'b0;
    reg                                auto_shot = 1'b1;
    reg  [`GP_J_W-1:0]                 j_target = 7'd0;
    reg                                enum_enable = 1'b0;
    reg                                burst_enable_r = 1'b1;

    reg  [1:0]                         predicate_mode = `GP_MODE_EQ;
    reg  signed [`GP_DATA_W-1:0]       threshold_a = 16'sd12345;
    reg  signed [`GP_DATA_W-1:0]       threshold_b = 16'sd0;
    reg  [`GP_DATA_COUNT_W-1:0]        data_count = NDATA[`GP_DATA_COUNT_W-1:0];
    reg  [`GP_SHOT_CAP_W-1:0]          shot_cap = 16'd100;
    reg  [31:0]                        seed_j = 32'd0;
    reg  [31:0]                        seed_meas = 32'd0;

    reg                                load_start = 1'b0;
    reg                                data_wr_en = 1'b0;
    reg  [`GP_INDEX_W-1:0]             data_wr_addr = 14'd0;
    reg  signed [`GP_DATA_W-1:0]       data_wr_data = 16'sd0;
    reg                                load_done = 1'b0;
    wire                               load_busy;

    wire                               busy, done, result_valid;
    wire [`GP_INDEX_W-1:0]             result_index;
    wire                               config_error, shot_limit, budget_limit;
    wire                               amp_overflow, zero_weight_error, load_error;
    wire [31:0]                        trial_count, L_BBHT;
    wire [31:0]                        actual_grover_iterations, cycle_count;

    wire                               enum_done;
    wire [`GP_FOUND_COUNT_W-1:0]       found_count;
    wire [`GP_ENUM_FAIL_W-1:0]         consecutive_fail_count;
    wire [`GP_RESULT_FIFO_CNT_W-1:0]   max_fifo_occupancy, res_count;
    wire [31:0]                        fifo_stall_cycles;
    wire [`GP_INDEX_W-1:0]             res_dout;
    wire                               res_empty;

    wire [31:0] policy_cycles_total, policy_stall_cycles, policy_actions_eval;
    wire [31:0] policy_memo_hit, policy_memo_miss, policy_max_latency;
    wire [2:0]  plan_fifo_level, plan_fifo_highwater;
    wire [31:0] plan_fifo_empty_demand, plan_fifo_hit_count, plan_fifo_mismatch_count;
    wire [31:0] policy_cold_solve_count, policy_spec_solve_count;

`ifdef GD_DRAM_BRANCH
    wire                        dw_req, dw_valid, dw_last, dw_ready;
    wire [`GD_ADDR_W-1:0]       dw_addr;
    wire [`GD_BURST_LEN_W-1:0]  dw_len;
    wire [ROW_BITS-1:0]         dw_data;
    wire                        dr_req, dr_valid, dr_ready, dr_last;
    wire [`GD_ADDR_W-1:0]       dr_addr;
    wire [`GD_BURST_LEN_W-1:0]  dr_len;
    wire [ROW_BITS-1:0]         dr_data;
    wire [`GP_J_W-1:0]          dram_frontier_j;
    wire [31:0] store_bursts, restore_bursts, dram_errors;
`endif

`ifdef GD_DRAM_BRANCH
    lpsoc_bbht_grover_main_ip u_ip (
`else
    // 실물 칩과 같은 조건입니다: CHECKPOINT_ENABLE 은 컴파일타임에 항상
    // 켜 두고, Normal/체크포인트는 checkpoint_auto_enable(=burst_enable)
    // 런타임 비트 하나로 매 케이스 고릅니다.
    //
    // 2026-09-09 부터 대조 상대가 보드 정본 K3/H3-E4-M2 입니다
    // (그전에는 hardware_bram/src_v2 의 K4/H4 였습니다).
    bbht_grover_main_ip #(
        .CHECKPOINT_ENABLE  (1),
        .CKPT_K             (3),
        .POLICY_H_FUTURE    (3),
        .CKPT_MANUAL_ENABLE (0),
        .AUTO_SPEC_ENABLE   (1),
        .INTRA_ENGINES      (4)
    ) u_ip (
`endif
        .clk                      (clk),
        .rstn                     (rstn),

        .start                    (start),
        .auto_shot                (auto_shot),
        .j_target                 (j_target),
        .burst_enable             (burst_enable_r),
        .enum_enable              (enum_enable),
        .fail_repeat_limit        ({`GP_ENUM_FAIL_W{1'b0}}),

        .checkpoint_manual_enable (1'b0),
        .policy_valid             (1'b0),
        .policy_source_j          ({`GP_J_W{1'b0}}),
        .policy_next_count        (3'd0),
        .policy_next_j_flat       ({(4*`GP_J_W){1'b0}}),
`ifdef GD_DRAM_BRANCH
        .checkpoint_auto_enable   (1'b0),
`else
        // bbht_rvx_wrapper.v 의 실제 배선: checkpoint_auto_enable =
        // burst_enable & auto_shot. 여기서는 Main IP 를 직접 흔드니 그
        // AND 를 우리가 대신 해 줘야 합니다.
        .checkpoint_auto_enable   (burst_enable_r & auto_shot),
`endif

        .predicate_mode           (predicate_mode),
        .threshold_a              (threshold_a),
        .threshold_b              (threshold_b),
        .data_count               (data_count),

        .shot_cap                 (shot_cap),
        .seed_j                   (seed_j),
        .seed_meas                (seed_meas),

        .load_start               (load_start),
        .data_wr_en               (data_wr_en),
        .data_wr_addr             (data_wr_addr),
        .data_wr_data             (data_wr_data),
        .load_done                (load_done),
        .load_busy                (load_busy),

        .res_pop                  (1'b0),
        .res_dout                 (res_dout),
        .res_empty                (res_empty),
        .res_count                (res_count),

        .busy                     (busy),
        .done                     (done),
        .result_valid             (result_valid),
        .result_index             (result_index),

        .enum_done                (enum_done),
        .found_count              (found_count),
        .consecutive_fail_count   (consecutive_fail_count),
        .max_fifo_occupancy       (max_fifo_occupancy),
        .fifo_stall_cycles        (fifo_stall_cycles),

        .config_error             (config_error),
        .shot_limit               (shot_limit),
        .budget_limit             (budget_limit),
        .amp_overflow             (amp_overflow),
        .zero_weight_error        (zero_weight_error),
        .load_error               (load_error),

        .trial_count              (trial_count),
        .L_BBHT                   (L_BBHT),
        .actual_grover_iterations (actual_grover_iterations),
        .cycle_count              (cycle_count),

        .policy_cycles_total      (policy_cycles_total),
        .policy_stall_cycles      (policy_stall_cycles),
        .policy_actions_eval      (policy_actions_eval),
        .policy_memo_hit          (policy_memo_hit),
        .policy_memo_miss         (policy_memo_miss),
        .policy_max_latency       (policy_max_latency),

        .plan_fifo_level          (plan_fifo_level),
        .plan_fifo_highwater      (plan_fifo_highwater),
        .plan_fifo_empty_demand   (plan_fifo_empty_demand),
        .plan_fifo_hit_count      (plan_fifo_hit_count),
        .plan_fifo_mismatch_count (plan_fifo_mismatch_count),
        .policy_cold_solve_count  (policy_cold_solve_count),
        .policy_spec_solve_count  (policy_spec_solve_count)

`ifdef GD_DRAM_BRANCH
        ,
        .dram_wr_req              (dw_req),
        .dram_wr_addr             (dw_addr),
        .dram_wr_len              (dw_len),
        .dram_wr_valid            (dw_valid),
        .dram_wr_data             (dw_data),
        .dram_wr_last             (dw_last),
        .dram_wr_ready            (dw_ready),
        .dram_rd_req              (dr_req),
        .dram_rd_addr             (dr_addr),
        .dram_rd_len              (dr_len),
        .dram_rd_valid            (dr_valid),
        .dram_rd_data             (dr_data),
        .dram_rd_ready            (dr_ready),
        .dram_rd_last             (dr_last),
        .dram_frontier_j          (dram_frontier_j)
`endif
    );

`ifdef GD_DRAM_BRANCH
    dram_burst_model #(
        .WR_LAT (WR_LAT), .RD_LAT (RD_LAT),
        .BEAT_GAP (BEAT_GAP), .STALL_EN (STALL_EN)
    ) u_dram (
        .clk (clk), .rstn (rstn),
        .wr_req (dw_req), .wr_addr (dw_addr), .wr_len (dw_len),
        .wr_valid (dw_valid), .wr_data (dw_data), .wr_last (dw_last),
        .wr_ready (dw_ready),
        .rd_req (dr_req), .rd_addr (dr_addr), .rd_len (dr_len),
        .rd_valid (dr_valid), .rd_data (dr_data), .rd_ready (dr_ready),
        .rd_last (dr_last),
        .store_bursts (store_bursts), .restore_bursts (restore_bursts),
        .err_count (dram_errors)
    );
`endif

    //-----------------------------------------------------------------
    // 데이터 적재. mem_sel 로 다섯 벌 중 하나를 고릅니다 (Verilog 는 메모리
    // 배열을 함수 인자로 못 넘기므로 이렇게 풀었습니다).
    //-----------------------------------------------------------------
    integer li;
    reg [2:0] mem_sel;

    task do_load;
        input integer count;
        begin
            @(negedge clk);
            data_count = count[`GP_DATA_COUNT_W-1:0];
            load_start = 1'b1;
            @(negedge clk);
            load_start = 1'b0;
            for (li = 0; li < count; li = li + 1) begin
                @(negedge clk);
                data_wr_en   = 1'b1;
                data_wr_addr = li[`GP_INDEX_W-1:0];
                case (mem_sel)
                    3'd0: data_wr_data = mem_m1[li];
                    3'd1: data_wr_data = mem_m4[li];
                    3'd2: data_wr_data = mem_m16[li];
                    3'd3: data_wr_data = mem_m64[li];
                    default: data_wr_data = mem_m256[li];
                endcase
            end
            @(negedge clk);
            data_wr_en = 1'b0;
            @(negedge clk);
            load_done = 1'b1;
            @(negedge clk);
            load_done = 1'b0;
            @(negedge clk);
            if (load_error !== 1'b0) begin
                $display("FAIL 적재: load_error 가 떴습니다 (count=%0d)", count);
                errors = errors + 1;
            end
        end
    endtask

    task wait_done;
        input integer max_cycles;
        output integer timed_out;
        integer n;
        begin
            n = 0;
            timed_out = 0;
            while ((done !== 1'b1) && (n < max_cycles)) begin
                @(negedge clk);
                n = n + 1;
            end
            if (done !== 1'b1) timed_out = 1;
        end
    endtask

    // 한 케이스 실행 + CSV 한 줄. bench500_report.py 가 이 형식을 읽습니다.
    task run_one;
        input integer m_idx;
        input integer seed_idx;
        input [31:0] sj;
        input [31:0] sm;
        input [63:0] mode_tag;   // "dram"/"normal"/"ckpt" 를 8글자로 왼쪽 정렬
        input        be;         // burst_enable (bram 갈래만 의미 있음)
        integer to;
        begin
            @(negedge clk);
            seed_j         = sj;
            seed_meas      = sm;
            burst_enable_r = be;
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            wait_done(2_000_000, to);
            if (to) begin
                $display("FAIL m=%0d seed=%0d %0s: 2,000,000 사이클 안에 안 끝났습니다",
                          m_values[m_idx], seed_idx, mode_tag);
                errors = errors + 1;
            end else begin
                $fdisplay(csv, "%0d,%0d,%0s,%0d,%0d,%0d,%0d,%0d,%0d",
                          m_values[m_idx], seed_idx, mode_tag,
                          result_valid ? result_index : {`GP_INDEX_W{1'b1}},
                          trial_count, L_BBHT, actual_grover_iterations,
                          cycle_count, config_error);
            end
            @(negedge clk);
        end
    endtask

    //-----------------------------------------------------------------
    // 시드 파일 읽기
    //-----------------------------------------------------------------
    integer seed_fd, seed_cnt, sj_rd, sm_rd, sc_ret;
    integer errors = 0;
    integer csv;
    integer mi, si;

    initial begin
`ifdef GD_DRAM_BRANCH
        $readmemh({`GD_WL_DIR, "/data_m1.hex"},   mem_m1);
        $readmemh({`GD_WL_DIR, "/data_m4.hex"},   mem_m4);
        $readmemh({`GD_WL_DIR, "/data_m16.hex"},  mem_m16);
        $readmemh({`GD_WL_DIR, "/data_m64.hex"},  mem_m64);
        $readmemh({`GD_WL_DIR, "/data_m256.hex"}, mem_m256);
        seed_fd = $fopen({`GD_WL_DIR, "/seeds.txt"}, "r");
        csv = $fopen({`GD_CSV_OUT}, "w");
`else
        $readmemh({`GD_WL_DIR, "/data_m1.hex"},   mem_m1);
        $readmemh({`GD_WL_DIR, "/data_m4.hex"},   mem_m4);
        $readmemh({`GD_WL_DIR, "/data_m16.hex"},  mem_m16);
        $readmemh({`GD_WL_DIR, "/data_m64.hex"},  mem_m64);
        $readmemh({`GD_WL_DIR, "/data_m256.hex"}, mem_m256);
        seed_fd = $fopen({`GD_WL_DIR, "/seeds.txt"}, "r");
        csv = $fopen({`GD_CSV_OUT}, "w");
`endif
        if (seed_fd == 0) begin
            $display("FAIL: seeds.txt 를 못 열었습니다");
            $finish;
        end
        seed_cnt = 0;
        while (seed_cnt < NSEED) begin
            sc_ret = $fscanf(seed_fd, "%d %d", sj_rd, sm_rd);
            if (sc_ret != 2) begin
                $display("FAIL: seeds.txt 형식이 이상합니다 (%0d줄째)", seed_cnt);
                $finish;
            end
            seed_j_arr[seed_cnt] = sj_rd[31:0];
            seed_m_arr[seed_cnt] = sm_rd[31:0];
            seed_cnt = seed_cnt + 1;
        end
        $fclose(seed_fd);

        $fdisplay(csv, "m,seed_idx,mode,result_index,trial,l_bbht,iter,cycles,cfgerr");

        rstn = 1'b0;
        repeat (5) @(negedge clk);
        rstn = 1'b1;
        repeat (5) @(negedge clk);

        for (mi = 0; mi < NM; mi = mi + 1) begin
            mem_sel = mi[2:0];
            do_load(NDATA);
            for (si = 0; si < NSEED; si = si + 1) begin
`ifdef GD_DRAM_BRANCH
                run_one(mi, si, seed_j_arr[si], seed_m_arr[si], "dram", 1'b1);
`else
                run_one(mi, si, seed_j_arr[si], seed_m_arr[si], "normal", 1'b0);
                run_one(mi, si, seed_j_arr[si], seed_m_arr[si], "ckpt",   1'b1);
`endif
            end
            $display("M=%0d 완료 (%0t)", m_values[mi], $time);
        end

        $fclose(csv);
        $display("=== 결과: 오류 %0d 건 ===", errors);
        if (errors == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
endmodule
