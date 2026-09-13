//=====================================================================
// tb_dram_core.v -- Main IP 통합 회귀 (통신 계층 없이 코어만)
//
// 여기서는 lpsoc_bbht_grover_main_ip 의 포트를 직접 흔들고, DRAM 자리에는
// dram_burst_model 을 답니다. 통신 계층(APB CSR / AHB 적재기)을 거친 판은
// tb_bbht_dram_top.v 이고, 그쪽 C1~C7 이 이 파일과 레이블·자극이 같아서
// make top 이 두 로그를 맞댑니다. 이 파일의 C1~C7 을 바꾸면 그쪽도 같이
// 바꿔야 합니다.
//
// 같은 파일을 hardware_bram 쪽 Main IP 에도 씁니다. 두 갈래의 포트 목록이
// dram_* 를 빼면 완전히 같기 때문입니다 (dram 쪽이 진부분집합이 아니라
// 상위집합). 그래서
//
//   GD_DRAM_BRANCH 정의  -> hardware_dram/src + DRAM 모델
//   정의 안 함           -> hardware_bram/src (CKPT_AUTO 로 Normal/K3H3-E4-M2)
//
// 두 벌을 같은 자극으로 돌려서 CASE 줄을 맞대면, hardware_dram 이
// 검증된 v0.9.8 과 "같은 답을 같은 궤적으로" 내는지가 확인됩니다.
//
// 궤적 불변식 (hardware_bram/sim/Makefile 의 bench250 주석과 같은 논리)
//   result_index 만 보면 안 됩니다. BBHT 는 뽑은 후보를 술어로 자가 검증
//   하므로 진폭이 깨져도 답 자체는 맞게 나옵니다. 진폭이 정말 맞는지는
//   trial_count 와 L_BBHT 로 봅니다 -- 이 둘은 "몇 번째 시도에서 맞췄나" 라
//   진폭이 조금이라도 다르면 측정 결과가 달라지고 즉시 갈라집니다.
//   반대로 actual_grover_iterations 와 cycle_count 는 갈라져야 정상입니다.
//   그게 이 갈래가 노리는 이득이기 때문입니다.
//
// 확인하는 것
//   C1  MANUAL_SINGLE (j 고정) 이 정답을 내는가
//   C2  NORMAL_SINGLE (BBHT 자동) 이 정답을 내는가
//   C3  같은 설정으로 다시 돌리면 DRAM 표를 재사용하는가
//       (궤적은 같고 Grover 반복 수는 줄어야 합니다)
//   C4  술어가 바뀌면 DRAM 표를 버리고 다시 만드는가
//   C5  RANGE 술어
//   C6  enum_enable=1 은 config_error 로 거절되는가
//   C7  거절된 다음 평범한 탐색이 다시 되는가
//   C8  data_count=0 은 config_error 인가
//=====================================================================
`timescale 1ns/1ps
`ifdef GD_DRAM_BRANCH
`include "grover_dram_param.vh"
`else
`include "grover_param.vh"
`endif

module tb_dram_core #(
    parameter integer WR_LAT    = 4,
    parameter integer RD_LAT    = 12,
    parameter integer BEAT_GAP  = 0,
    parameter integer STALL_EN  = 0,
    // hardware_bram 갈래에서만 의미가 있습니다. 1 이면 K4/H4 자동 체크포인트.
    parameter integer CKPT_AUTO = 0
);
    localparam integer ROW_BITS = `GP_P * `GP_AMP_W;
    localparam integer NDATA    = `GP_N;

    reg clk  = 1'b0;
    reg rstn = 1'b0;
    always #5 clk = ~clk;

    integer errors = 0;

    //-----------------------------------------------------------------
    // 데이터셋: data[i] = i. 인덱스와 값이 같아서 어떤 술어를 걸어도
    // 정답 집합이 연속 구간으로 딱 떨어지고, 손으로 개수를 셀 수 있습니다.
    //-----------------------------------------------------------------
    function signed [`GP_DATA_W-1:0] dataset;
        input integer idx;
        begin
            dataset = idx[`GP_DATA_W-1:0];
        end
    endfunction

    function pred_ok;
        input [1:0] mode;
        input signed [`GP_DATA_W-1:0] ta;
        input signed [`GP_DATA_W-1:0] tb;
        input signed [`GP_DATA_W-1:0] v;
        begin
            case (mode)
                `GP_MODE_LT:    pred_ok = (v <  ta);
                `GP_MODE_GT:    pred_ok = (v >  ta);
                `GP_MODE_EQ:    pred_ok = (v == ta);
                default:        pred_ok = (v >  ta) && (v < tb);   // RANGE
            endcase
        end
    endfunction

    //-----------------------------------------------------------------
    // Main IP 포트
    //-----------------------------------------------------------------
    reg                                start = 1'b0;
    reg                                auto_shot = 1'b0;
    reg  [`GP_J_W-1:0]                 j_target = 7'd0;
    reg                                enum_enable = 1'b0;

    reg  [1:0]                         predicate_mode = `GP_MODE_LT;
    reg  signed [`GP_DATA_W-1:0]       threshold_a = 16'sd0;
    reg  signed [`GP_DATA_W-1:0]       threshold_b = 16'sd0;
    reg  [`GP_DATA_COUNT_W-1:0]        data_count = 15'd0;
    reg  [`GP_SHOT_CAP_W-1:0]          shot_cap = 16'd100;
    reg  [31:0]                        seed_j = 32'h1234_5678;
    reg  [31:0]                        seed_meas = 32'h9ABC_DEF0;

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
    // hardware_bram 의 Main IP 는 체크포인트 하드웨어 자체가 컴파일
    // 파라미터로 붙었다 떨어졌다 합니다. CHECKPOINT_ENABLE 기본값이 0 이라
    // 그냥 물리면 checkpoint_auto_enable 을 아무리 올려도 체크포인트 경로가
    // 안 켜집니다 (실물 경로에서는 wrapper 가 1 로 올려 줍니다).
    // 여기서는 CKPT_AUTO 로 같이 묶어, 0 이면 순수 Normal, 1 이면 보드
    // 정본과 같은 K3/H3-E4-M2 가 되게 합니다.
    //
    // 2026-09-09 이전에는 이 자리가 hardware_bram/src_v2 의 K4/H4 였습니다. 대조 상대가
    // 바뀌었으므로 옛 로그의 사이클과 맞대지 마십시오.
    bbht_grover_main_ip #(
        .CHECKPOINT_ENABLE  (CKPT_AUTO),
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
        // hardware_bram 의 K4/H4 경로는 burst_enable 과 auto_shot 을 같이
        // 요구합니다 (run_auto_mode_legal). hardware_dram 은 이 포트를
        // 계약 호환용으로만 받고 쓰지 않으므로, 세 갈래에 같은 자극을
        // 주려면 그냥 1 로 두는 쪽이 맞습니다.
        .burst_enable             (1'b1),
        .enum_enable              (enum_enable),
        .fail_repeat_limit        ({`GP_ENUM_FAIL_W{1'b0}}),

        // 수동 체크포인트/정책 포트는 두 갈래 모두 여기서는 안 씁니다.
        // hardware_dram 은 계약 호환용으로만 받고, hardware_bram 은
        // CKPT_AUTO 로 내부 자동 정책만 켭니다.
        .checkpoint_manual_enable (1'b0),
        .policy_valid             (1'b0),
        .policy_source_j          ({`GP_J_W{1'b0}}),
        .policy_next_count        (3'd0),
        .policy_next_j_flat       ({(4*`GP_J_W){1'b0}}),
        .checkpoint_auto_enable   (CKPT_AUTO[0]),

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
    // 태스크
    //-----------------------------------------------------------------
    integer i;

    // 데이터셋 적재. grover_loader_ctrl 계약대로 load_start -> 쓰기들 ->
    // load_done 순서입니다. data_count 를 바꾸면 이전 적재가 무효가 되므로
    // 반드시 다시 불러야 합니다.
    task do_load;
        input integer count;
        begin
            @(negedge clk);
            data_count = count[`GP_DATA_COUNT_W-1:0];
            load_start = 1'b1;
            @(negedge clk);
            load_start = 1'b0;
            for (i = 0; i < count; i = i + 1) begin
                @(negedge clk);
                data_wr_en   = 1'b1;
                data_wr_addr = i[`GP_INDEX_W-1:0];
                data_wr_data = dataset(i);
            end
            @(negedge clk);
            data_wr_en = 1'b0;
            @(negedge clk);
            load_done = 1'b1;
            @(negedge clk);
            load_done = 1'b0;
            @(negedge clk);
            if (load_error !== 1'b0) begin
                errors = errors + 1;
                $display("FAIL 적재: load_error 가 떴습니다 (count=%0d)", count);
            end
        end
    endtask

    // done 을 기다립니다. 정해진 사이클 안에 안 오면 timed_out 을 세워
    // 그 케이스만 실패로 처리하고 다음으로 넘어갑니다.
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

    // 한 번의 탐색. 결과를 CASE 한 줄로 찍습니다. 이 줄을 두 갈래에서
    // 맞대는 것이 equiv 회귀입니다.
    task run_case;
        input [255:0] label;
        input         a_shot;        // 1 = NORMAL_SINGLE, 0 = MANUAL_SINGLE
        input integer jt;
        input [1:0]   mode;
        input signed [`GP_DATA_W-1:0] ta;
        input signed [`GP_DATA_W-1:0] tb;
        input [31:0]  sj;
        input [31:0]  sm;
        input integer expect_success;  // 1 이면 정답을 내야 함
        input integer expect_cfgerr;   // 1 이면 config_error 여야 함
        input integer en_enum;
        integer to;
        integer ok;
        begin
            @(negedge clk);
            auto_shot      = a_shot;
            j_target       = jt[`GP_J_W-1:0];
            predicate_mode = mode;
            threshold_a    = ta;
            threshold_b    = tb;
            seed_j         = sj;
            seed_meas      = sm;
            enum_enable    = en_enum[0];

            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            wait_done(20_000_000, to);

            ok = 1;
            if (to) begin
                ok = 0;
                errors = errors + 1;
                $display("FAIL %0s: done 이 안 왔습니다 (멈춤)", label);
            end else begin
                if (expect_cfgerr) begin
                    if (config_error !== 1'b1) begin
                        ok = 0; errors = errors + 1;
                        $display("FAIL %0s: config_error 를 기대했는데 안 떴습니다", label);
                    end
                    if (result_valid === 1'b1) begin
                        ok = 0; errors = errors + 1;
                        $display("FAIL %0s: 거절된 실행인데 result_valid 가 떴습니다", label);
                    end
                end else begin
                    if (config_error !== 1'b0) begin
                        ok = 0; errors = errors + 1;
                        $display("FAIL %0s: 예상 못 한 config_error", label);
                    end
                    if (expect_success && (result_valid !== 1'b1)) begin
                        ok = 0; errors = errors + 1;
                        $display("FAIL %0s: 정답을 못 찾았습니다 (shot_limit=%0b budget_limit=%0b)",
                                 label, shot_limit, budget_limit);
                    end
                    // 찾았다고 했으면 정말 술어를 만족하는 인덱스여야 합니다.
                    if (result_valid === 1'b1) begin
                        if (result_index >= data_count) begin
                            ok = 0; errors = errors + 1;
                            $display("FAIL %0s: 결과 인덱스 %0d 가 data_count %0d 밖입니다",
                                     label, result_index, data_count);
                        end else if (!pred_ok(mode, ta, tb, dataset(result_index))) begin
                            ok = 0; errors = errors + 1;
                            $display("FAIL %0s: 결과 인덱스 %0d (값 %0d) 가 술어를 만족하지 않습니다",
                                     label, result_index, dataset(result_index));
                        end
                    end
                    if (zero_weight_error !== 1'b0) begin
                        ok = 0; errors = errors + 1;
                        $display("FAIL %0s: zero_weight_error", label);
                    end
                    if (amp_overflow !== 1'b0) begin
                        ok = 0; errors = errors + 1;
                        $display("FAIL %0s: amp_overflow (진폭 포화)", label);
                    end
                end
            end

            // 두 갈래를 맞댈 한 줄. 앞의 네 항목(정답/인덱스/시도/L_BBHT)은
            // 반드시 같아야 하고, 뒤의 두 항목(반복 수/사이클)은 달라도
            // 됩니다 -- 그 차이가 이 갈래의 이득입니다.
            $display("CASE %0s valid=%0b idx=%0d trials=%0d lbbht=%0d cfgerr=%0b shotlim=%0b budlim=%0b | iters=%0d cyc=%0d",
                     label, result_valid, result_index, trial_count, L_BBHT,
                     config_error, shot_limit, budget_limit,
                     actual_grover_iterations, cycle_count);
`ifdef GD_DRAM_BRANCH
            $display("      DRAM 저장누적=%0d 복원누적=%0d frontier=%0d 오류=%0d",
                     store_bursts, restore_bursts, dram_frontier_j, dram_errors);
`endif
            if (ok) $display("  ok  %0s", label);

            repeat (8) @(negedge clk);
        end
    endtask

    //-----------------------------------------------------------------
    // 본체
    //-----------------------------------------------------------------
    reg [31:0] iters_c2, iters_c3;
    reg [31:0] iters_fresh, iters_reuse;
    reg [31:0] trials_fresh, lbbht_fresh;
    reg [31:0] trials_reuse, lbbht_reuse;
    reg [`GP_INDEX_W-1:0] idx_fresh, idx_reuse;

    initial begin
`ifdef GD_DRAM_BRANCH
        $display("=== tb_dram_core [hardware_dram] (WR_LAT=%0d RD_LAT=%0d BEAT_GAP=%0d STALL_EN=%0d) ===",
                 WR_LAT, RD_LAT, BEAT_GAP, STALL_EN);
`else
        $display("=== tb_dram_core [hardware_bram, checkpoint_auto=%0d] ===", CKPT_AUTO);
`endif
        repeat (4) @(negedge clk);
        rstn = 1'b1;
        repeat (4) @(negedge clk);

        do_load(NDATA);
        $display("  적재 완료: %0d개", NDATA);

        // C1 수동. LT 256 이면 정답이 256개라 최적 반복이 6 근처입니다.
        //    K4/H4 갈래에서는 이 케이스를 건너뜁니다. 그쪽 자동 체크포인트
        //    경로가 auto_shot 을 요구해서(run_auto_mode_legal) 수동 지정
        //    실행 자체를 config_error 로 거절하기 때문입니다. 비교에서
        //    빠질 뿐, hardware_dram 쪽 검사에는 그대로 들어갑니다.
        if (CKPT_AUTO == 0)
            run_case("C1 MANUAL j=6 LT256", 1'b0, 6, `GP_MODE_LT, 16'sd256, 16'sd0,
                     32'h1234_5678, 32'h9ABC_DEF0, 1, 0, 0);

        // C2 자동. 여기서 DRAM 표가 처음 만들어집니다.
        run_case("C2 NORMAL LT256", 1'b1, 0, `GP_MODE_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 1, 0, 0);
        iters_c2 = actual_grover_iterations;

        // C3 같은 설정, 같은 시드로 재실행. 궤적은 C2 와 똑같아야 하고,
        //    DRAM 표가 살아 있으므로 Grover 반복은 줄어야 합니다.
        run_case("C3 NORMAL LT256 재실행", 1'b1, 0, `GP_MODE_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 1, 0, 0);
        iters_c3 = actual_grover_iterations;

        // C4 술어 변경. DRAM 표는 옛 술어로 만든 것이라 버려야 합니다.
        run_case("C4 NORMAL GT16128", 1'b1, 0, `GP_MODE_GT, 16'sd16128, 16'sd0,
                 32'h0BAD_F00D, 32'h5EED_1234, 1, 0, 0);

        // C5 RANGE. 1000 < v < 1300 이라 정답이 299개입니다. 바로 앞이
        //    GT 였으므로 여기서 DRAM 표가 다시 버려지고 새로 자랍니다.
        run_case("C5 NORMAL RANGE", 1'b1, 0, `GP_MODE_RANGE, 16'sd1000, 16'sd1300,
                 32'hFEED_BEEF, 32'h1357_9BDF, 1, 0, 0);
        iters_fresh  = actual_grover_iterations;
        trials_fresh = trial_count;
        lbbht_fresh  = L_BBHT;
        idx_fresh    = result_index;

        // C5b 같은 설정, 같은 시드로 재실행. 이 갈래의 주장이 그대로 걸린
        //     자리입니다. 궤적(시도 수 / L_BBHT / 답)은 한 치도 안 달라야
        //     하고, Grover 반복은 DRAM 표를 다시 읽는 것으로 대체되어야
        //     합니다. 둘 중 하나만 만족하면 실패입니다 -- 궤적이 같은데
        //     반복이 그대로면 재사용을 안 한 것이고, 반복이 줄었는데 궤적이
        //     달라졌으면 복원한 진폭이 원본과 다른 것입니다.
        run_case("C5b RANGE 재실행", 1'b1, 0, `GP_MODE_RANGE, 16'sd1000, 16'sd1300,
                 32'hFEED_BEEF, 32'h1357_9BDF, 1, 0, 0);
        // 뒤 케이스들이 카운터를 덮으므로 여기서 바로 떠 둡니다.
        iters_reuse  = actual_grover_iterations;
        trials_reuse = trial_count;
        lbbht_reuse  = L_BBHT;
        idx_reuse    = result_index;

`ifdef GD_DRAM_BRANCH
        // C6 Enumeration 은 이 갈래에 없습니다. 조용히 단일탐색으로
        //    떨어지지 말고 config_error 로 거절해야 합니다.
        //    hardware_bram 은 Enumeration 이 실제로 구현돼 있어 같은 자극에
        //    전혀 다른(정상적인) 동작을 하므로 이 케이스는 dram 에서만
        //    돌립니다. 뒤의 C7 은 두 갈래 모두 평범한 단일탐색이라 그대로
        //    맞대 볼 수 있습니다.
        run_case("C6 ENUM 거절", 1'b1, 0, `GP_MODE_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 0, 1, 1);
`endif

        // C7 거절 직후 평범한 탐색. 거절이 상태를 물고 늘어지면 여기서 멈춥니다.
        run_case("C7 거절 후 정상 실행", 1'b1, 0, `GP_MODE_LT, 16'sd256, 16'sd0,
                 32'h2468_ACE0, 32'h1122_3344, 1, 0, 0);

        // C9 어려운 워크로드. LT 4 면 정답이 4개뿐이라 최적 반복이 50 근처로
        //    올라가고, BBHT 가 j 를 0..127 에서 여러 라운드 뽑습니다. 위의
        //    C1~C7 은 정답이 250~300개라 j 가 7 을 안 넘었는데, 그 구간에서는
        //    애초에 아낄 재계산이 없어서 이 갈래의 이득이 드러나지 않습니다.
        //    DRAM 전량저장이 노리는 것은 "같은 j 를 여러 번 방문" 이 아니라
        //    "큰 j 를 매번 처음부터 다시 돌리지 않는 것" 이므로, 비교는
        //    이쪽 숫자로 해야 합니다.
        run_case("C9 NORMAL LT4 (큰 j)", 1'b1, 0, `GP_MODE_LT, 16'sd4, 16'sd0,
                 32'hC0FF_EE01, 32'hDEAD_1234, 1, 0, 0);

        // C8 data_count=0. 적재가 무효가 되므로 마지막에 둡니다.
        @(negedge clk);
        data_count = 15'd0;
        run_case("C8 data_count=0", 1'b1, 0, `GP_MODE_LT, 16'sd256, 16'sd0,
                 32'h1234_5678, 32'h9ABC_DEF0, 0, 1, 0);

        //-------------------------------------------------------------
        // 갈래 안에서만 볼 수 있는 것들
        //-------------------------------------------------------------
        if (iters_c3 > iters_c2) begin
            errors = errors + 1;
            $display("FAIL C3: 재실행이 오히려 반복을 더 썼습니다 (%0d > %0d)", iters_c3, iters_c2);
        end

        // 궤적은 그대로, 반복만 줄어야 합니다.
        if ((trials_reuse !== trials_fresh) || (lbbht_reuse !== lbbht_fresh) ||
            (idx_reuse !== idx_fresh)) begin
            errors = errors + 1;
            $display("FAIL C5b: 궤적이 갈라졌습니다 (시도 %0d/%0d, L_BBHT %0d/%0d, 인덱스 %0d/%0d)",
                     trials_reuse, trials_fresh, lbbht_reuse, lbbht_fresh, idx_reuse, idx_fresh);
`ifdef GD_DRAM_BRANCH
        // 반복이 줄어야 한다는 주장은 이 갈래만의 것입니다. hardware_bram
        // 은 Normal 이면 매 실행을 처음부터 다시 계산하는 게 정상이라
        // 같은 잣대를 대면 안 됩니다.
        end else if (iters_reuse >= iters_fresh) begin
            errors = errors + 1;
            $display("FAIL C5b: 재사용 이득이 없습니다 (Grover 반복 %0d -> %0d)",
                     iters_fresh, iters_reuse);
`endif
        end else begin
            $display("  ok  C5b 궤적 동일 (Grover 반복 %0d -> %0d)",
                     iters_fresh, iters_reuse);
        end

`ifdef GD_DRAM_BRANCH
        if (dram_errors !== 32'd0) begin
            errors = errors + 1;
            $display("FAIL: DRAM 모델이 프로토콜 오류 %0d건을 보고했습니다", dram_errors);
        end
`endif

        repeat (10) @(negedge clk);
        $display("=== 결과: 오류 %0d 건 ===", errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $finish;
    end

endmodule
