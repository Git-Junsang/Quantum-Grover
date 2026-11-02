//=====================================================================
// tb_dram_prep_seq.v -- grover_dram_prep_seq.v 회귀
//
// 이 갈래에서 hardware_bram 의 체크포인트 planner/executor(K)와 rolling
// 정책 엔진(H)을 통째로 대신하는 물건이 prep 시퀀서입니다. "임의의 j 를
// 어떻게 준비할 것인가" 라는 질문에 K/H 는 "어느 체크포인트에서 몇 번
// 되돌려 돌릴지 계획한다" 로 답했고, 여기서는 "이미 지나온 j 면 DRAM 에서
// 한 번에 읽고, 아직 안 가 본 j 면 앞으로 자라면서 매 반복을 적는다" 로
// 답합니다. 그러니 이 파일이 곧 두 갈래의 차이를 검증하는 자리입니다.
//
// 검증 대상은 prep 시퀀서 + amp_store + queue + DRAM 모델을 다 물린 상태
// 입니다. Grover 연산기 자리에는 iter_engine_stub 을 넣습니다. 진짜
// 연산기는 여기서 볼 필요가 없고(그건 tb_dram_core 가 봅니다), 대신
// "반복 j 의 상태" 를 눈으로 확인 가능한 값 base(row,lane) + j 로 만들어
// 두면 복원이 한 칸이라도 밀렸을 때 즉시 드러납니다.
//
// 확인하는 것
//   P1  j=0 은 항상 로컬 INIT 으로 풀고 DRAM 을 건드리지 않는가
//       (슬롯 0 은 기록된 적이 없으므로 restore 하면 쓰레기를 읽습니다)
//   P2  frontier 를 넘는 j 는 한 반복씩 자라며 매번 DRAM 에 적는가
//   P3  이미 버퍼에 있는 j 를 다시 요청하면 아무 일도 안 하는가
//   P4  frontier 이하의 j 는 반복 재계산 없이 restore 한 번으로 끝나는가
//   P5  버퍼가 frontier 와 어긋난 상태에서 더 큰 j 를 요청하면
//       frontier 를 restore 한 뒤 거기서부터 자라는가
//   P6  frontier 가 이미 올라간 뒤에 j=0 이 다시 뽑혀도 (BBHT 에서 흔한
//       일입니다) 엉뚱한 슬롯에 저장하지 않는가
//   P7  dram_invalidate 후에는 frontier 가 0 으로 돌아가 처음부터 다시
//       만드는가
//   P8  준비가 끝난 버퍼 A 의 512행 x 32레인이 실제로 그 j 의 상태인가
//
// P8 이 매 단계마다 붙기 때문에, 위 경로 중 하나라도 엉뚱한 슬롯을 읽거나
// 저장을 빠뜨리면 값으로 잡힙니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_dram_param.vh"

module tb_dram_prep_seq #(
    parameter integer WR_LAT   = 4,
    parameter integer RD_LAT   = 12,
    parameter integer BEAT_GAP = 0,
    parameter integer STALL_EN = 0
);
    localparam integer ROW_BITS = `GP_P * `GP_AMP_W;
    localparam integer ROWS     = `GP_ROWS;

    reg clk  = 1'b0;
    reg rstn = 1'b0;

    always #5 clk = ~clk;

    integer errors = 0;

    //-----------------------------------------------------------------
    // 반복 j 의 진폭 상태 모형: lane 값 = base(row,lane) + j
    // base 는 0..16383 이라 j 를 127 까지 더해도 23비트 안에서 놉니다.
    //-----------------------------------------------------------------
    function [`GP_AMP_W-1:0] base_val;
        input integer row;
        input integer lane;
        begin
            base_val = (row * `GP_P + lane);
        end
    endfunction

    //-----------------------------------------------------------------
    // DUT
    //-----------------------------------------------------------------
    reg                  dram_invalidate = 1'b0;
    reg                  prep_start      = 1'b0;
    reg  [`GP_J_W-1:0]   prep_target_j   = 7'd0;
    wire                 prep_busy;
    wire                 prep_done;

    wire                 iter_start;
    wire                 iter_do_init;
    wire [15:0]          iter_count;
    wire                 iter_done;

    wire                 store_start, restore_start;
    wire [`GP_J_W-1:0]   store_j, restore_j;
    wire                 store_done, restore_done;

    wire                 a_role_grow, a_role_store, a_role_restore;
    wire [`GP_J_W-1:0]   frontier_j;
    wire                 buf_a_valid;
    wire [`GP_J_W-1:0]   buf_a_j;

    grover_dram_prep_seq u_prep (
        .clk             (clk),
        .rstn            (rstn),
        .dram_invalidate (dram_invalidate),
        .prep_start      (prep_start),
        .prep_target_j   (prep_target_j),
        .prep_busy       (prep_busy),
        .prep_done       (prep_done),
        .iter_start      (iter_start),
        .iter_do_init    (iter_do_init),
        .iter_count      (iter_count),
        .iter_done       (iter_done),
        .store_start     (store_start),
        .store_j         (store_j),
        .store_done      (store_done),
        .restore_start   (restore_start),
        .restore_j       (restore_j),
        .restore_done    (restore_done),
        .a_role_grow     (a_role_grow),
        .a_role_store    (a_role_store),
        .a_role_restore  (a_role_restore),
        .frontier_j      (frontier_j),
        .buf_a_valid     (buf_a_valid),
        .buf_a_j         (buf_a_j)
    );

    //-----------------------------------------------------------------
    // DRAM store/restore 엔진 + DRAM 모델
    //-----------------------------------------------------------------
    wire [`GP_ROW_W-1:0]  store_rd_row;
    wire                  store_rd_en;
    wire [ROW_BITS-1:0]   store_rd_data;
    wire [`GP_ROW_W-1:0]  restore_wr_row;
    wire                  restore_wr_en;
    wire [ROW_BITS-1:0]   restore_wr_data;

    wire                        dw_req, dw_valid, dw_last, dw_ready;
    wire [`GD_ADDR_W-1:0]       dw_addr;
    wire [`GD_BURST_LEN_W-1:0]  dw_len;
    wire [ROW_BITS-1:0]         dw_data;

    wire                        dr_req, dr_valid, dr_ready, dr_last;
    wire [`GD_ADDR_W-1:0]       dr_addr;
    wire [`GD_BURST_LEN_W-1:0]  dr_len;
    wire [ROW_BITS-1:0]         dr_data;

    wire [31:0] store_bursts, restore_bursts, dram_errors;

    grover_dram_amp_store u_amp_store (
        .clk             (clk),
        .rstn            (rstn),
        .store_start     (store_start),
        .store_j         (store_j),
        .store_busy      (),
        .store_done      (store_done),
        .store_rd_row    (store_rd_row),
        .store_rd_en     (store_rd_en),
        .store_rd_data   (store_rd_data),
        .restore_start   (restore_start),
        .restore_j       (restore_j),
        .restore_busy    (),
        .restore_done    (restore_done),
        .restore_wr_row  (restore_wr_row),
        .restore_wr_en   (restore_wr_en),
        .restore_wr_data (restore_wr_data),
        .dram_wr_req     (dw_req),
        .dram_wr_addr    (dw_addr),
        .dram_wr_len     (dw_len),
        .dram_wr_valid   (dw_valid),
        .dram_wr_data    (dw_data),
        .dram_wr_last    (dw_last),
        .dram_wr_ready   (dw_ready),
        .dram_rd_req     (dr_req),
        .dram_rd_addr    (dr_addr),
        .dram_rd_len     (dr_len),
        .dram_rd_valid   (dr_valid),
        .dram_rd_data    (dr_data),
        .dram_rd_ready   (dr_ready),
        .dram_rd_last    (dr_last)
    );

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

    //-----------------------------------------------------------------
    // 버퍼 큐 + Grover 연산기 자리의 스텁
    //-----------------------------------------------------------------
    wire [`GP_ROW_W-1:0]  grow_rd_row;
    wire                  grow_rd_en;
    wire [ROW_BITS-1:0]   grow_rd_amp;
    wire [`GP_ROW_W-1:0]  grow_wr_row;
    wire                  grow_wr_en;
    wire [ROW_BITS-1:0]   grow_wr_amp;

    reg  [`GP_ROW_W-1:0]  meas_rd_row = 9'd0;
    reg                   meas_rd_en  = 1'b0;
    reg                   tb_role_measure = 1'b0;
    wire [ROW_BITS-1:0]   meas_rd_amp;

    grover_dram_queue u_queue (
        .clk            (clk),
        .a_role_grow    (a_role_grow),
        .a_role_store   (a_role_store),
        .a_role_restore (a_role_restore),
        .a_role_measure (tb_role_measure),
        .b_role_grow    (1'b0),
        .b_role_store   (1'b0),
        .b_role_restore (1'b0),
        .b_role_measure (1'b0),
        .grow_rd_row    (grow_rd_row),
        .grow_rd_en     (grow_rd_en),
        .grow_rd_amp    (grow_rd_amp),
        .grow_wr_row    (grow_wr_row),
        .grow_wr_en     (grow_wr_en),
        .grow_wr_amp    (grow_wr_amp),
        .store_rd_row   (store_rd_row),
        .store_rd_en    (store_rd_en),
        .store_rd_amp   (store_rd_data),
        .restore_wr_row (restore_wr_row),
        .restore_wr_en  (restore_wr_en),
        .restore_wr_amp (restore_wr_data),
        .meas_rd_row    (meas_rd_row),
        .meas_rd_en     (meas_rd_en),
        .meas_rd_amp    (meas_rd_amp)
    );

    iter_engine_stub u_iter (
        .clk          (clk),
        .rstn         (rstn),
        .iter_start   (iter_start),
        .iter_do_init (iter_do_init),
        .iter_count   (iter_count),
        .iter_done    (iter_done),
        .grow_rd_row  (grow_rd_row),
        .grow_rd_en   (grow_rd_en),
        .grow_rd_amp  (grow_rd_amp),
        .grow_wr_row  (grow_wr_row),
        .grow_wr_en   (grow_wr_en),
        .grow_wr_amp  (grow_wr_amp)
    );

    //-----------------------------------------------------------------
    // 역할 선택이 서로 겹치지 않는지 상시 감시. grover_dram_queue.v 가
    // "동시에 하나만 켜진다" 를 호출자 책임으로 미뤄 두었기 때문에,
    // 그 불변식은 여기서 봐 줘야 합니다.
    //-----------------------------------------------------------------
    wire role_overlap =
        (a_role_grow + a_role_store + a_role_restore + tb_role_measure) > 1;
    reg  role_overlap_d = 1'b0;

    // 겹침이 시작되는 순간에만 한 줄 찍습니다. 매 사이클 찍으면 수만 줄이
    // 나와 정작 어느 단계에서 시작됐는지가 안 보입니다.
    always @(posedge clk) begin
        if (!rstn) begin
            role_overlap_d <= 1'b0;
        end else begin
            role_overlap_d <= role_overlap;
            if (role_overlap && !role_overlap_d) begin
                errors = errors + 1;
                $display("FAIL: 버퍼 A 역할이 겹쳤습니다 grow=%0b store=%0b restore=%0b meas=%0b (t=%0t)",
                         a_role_grow, a_role_store, a_role_restore, tb_role_measure, $time);
            end
        end
    end

    //-----------------------------------------------------------------
    // 태스크
    //-----------------------------------------------------------------
    integer r, l;
    integer step_no = 0;

    task do_prep;
        input integer target;
        begin
            step_no = step_no + 1;
            @(negedge clk);
            prep_target_j = target[`GP_J_W-1:0];
            prep_start    = 1'b1;
            @(negedge clk);
            prep_start = 1'b0;
            wait (prep_done === 1'b1);
            @(negedge clk);
        end
    endtask

    task pulse_invalidate;
        begin
            @(negedge clk);
            dram_invalidate = 1'b1;
            @(negedge clk);
            dram_invalidate = 1'b0;
            @(negedge clk);
        end
    endtask

    // 버퍼 A 가 정말 반복 j 의 상태를 담고 있는지 512행 전부 확인합니다.
    task check_buf;
        input integer j;
        input [255:0] label;
        integer bad;
        reg [ROW_BITS-1:0] got;
        begin
            bad = 0;
            tb_role_measure = 1'b1;
            for (r = 0; r < ROWS; r = r + 1) begin
                @(negedge clk);
                meas_rd_row = r[`GP_ROW_W-1:0];
                meas_rd_en  = 1'b1;
                @(negedge clk);
                meas_rd_en  = 1'b0;
                @(negedge clk);
                got = meas_rd_amp;
                for (l = 0; l < `GP_P; l = l + 1) begin
                    if (got[l*`GP_AMP_W +: `GP_AMP_W] !==
                        (base_val(r, l) + j[`GP_AMP_W-1:0])) begin
                        if (bad == 0)
                            $display("FAIL %0s: 행 %0d 레인 %0d 값 0x%06x, 기대 0x%06x",
                                     label, r, l, got[l*`GP_AMP_W +: `GP_AMP_W],
                                     base_val(r, l) + j[`GP_AMP_W-1:0]);
                        bad = bad + 1;
                    end
                end
            end
            tb_role_measure = 1'b0;
            @(negedge clk);
            if (bad != 0) begin
                errors = errors + 1;
                $display("FAIL %0s: %0d개 레인이 어긋났습니다 (기대 상태 j=%0d)", label, bad, j);
            end
        end
    endtask

    // 단계마다 frontier 와 DRAM 접근 횟수를 대조합니다. 값이 맞아도 접근
    // 횟수가 다르면 "우연히 맞은" 것이므로 둘 다 봅니다.
    task check_step;
        input [255:0] label;
        input integer exp_frontier;
        input integer exp_store;
        input integer exp_restore;
        integer err_before;
        begin
            err_before = errors;
            if (frontier_j !== exp_frontier[`GP_J_W-1:0]) begin
                errors = errors + 1;
                $display("FAIL %0s: frontier=%0d, 기대 %0d", label, frontier_j, exp_frontier);
            end
            if (store_bursts !== exp_store[31:0]) begin
                errors = errors + 1;
                $display("FAIL %0s: 누적 저장 %0d회, 기대 %0d회", label, store_bursts, exp_store);
            end
            if (restore_bursts !== exp_restore[31:0]) begin
                errors = errors + 1;
                $display("FAIL %0s: 누적 복원 %0d회, 기대 %0d회", label, restore_bursts, exp_restore);
            end
            if (errors == err_before)
                $display("  ok  %0s (frontier=%0d 저장누적=%0d 복원누적=%0d)",
                         label, frontier_j, store_bursts, restore_bursts);
        end
    endtask

    //-----------------------------------------------------------------
    // 본체
    //-----------------------------------------------------------------
    initial begin
        $display("=== tb_dram_prep_seq (WR_LAT=%0d RD_LAT=%0d BEAT_GAP=%0d STALL_EN=%0d) ===",
                 WR_LAT, RD_LAT, BEAT_GAP, STALL_EN);
        repeat (4) @(negedge clk);
        rstn = 1'b1;
        repeat (4) @(negedge clk);

        // P1: j=0 은 INIT 만. DRAM 접근이 한 번도 없어야 합니다.
        do_prep(0);
        check_buf(0, "P1 j=0 상태");
        check_step("P1 j=0 은 로컬 INIT", 0, 0, 0);

        // P2: frontier 0 -> 3. 반복 1,2,3 을 자라며 매번 저장.
        do_prep(3);
        check_buf(3, "P2 j=3 상태");
        check_step("P2 frontier 0->3 성장", 3, 3, 0);

        // P3: 이미 버퍼에 있는 j. 아무 일도 없어야 합니다.
        do_prep(3);
        check_buf(3, "P3 j=3 재요청 상태");
        check_step("P3 버퍼 적중", 3, 3, 0);

        // P4: frontier 이하 -> 복원 한 번. 반복 재계산이 없어야 합니다.
        do_prep(2);
        check_buf(2, "P4 j=2 상태");
        check_step("P4 frontier 이하 복원", 3, 3, 1);

        // P5: 버퍼(2)가 frontier(3)와 어긋난 채 5 요청.
        //     frontier 복원 1회 + 반복 4,5 성장 2회 저장.
        do_prep(5);
        check_buf(5, "P5 j=5 상태");
        check_step("P5 frontier 복원 후 성장", 5, 5, 2);

        // P6: frontier 가 올라간 뒤 j=0 재추첨. BBHT 에서 매 라운드 j 를
        //     새로 뽑으므로 실제로 자주 일어납니다. 슬롯 0 을 읽거나
        //     엉뚱한 슬롯에 저장하면 DRAM 모델이 잡습니다.
        do_prep(0);
        check_buf(0, "P6 j=0 재추첨 상태");
        check_step("P6 j=0 재추첨", 5, 5, 2);

        // P7: 다시 frontier 이하 복원, 그리고 frontier 를 넘겨 성장.
        do_prep(4);
        check_buf(4, "P7 j=4 상태");
        check_step("P7 j=4 복원", 5, 5, 3);

        do_prep(7);
        check_buf(7, "P7 j=7 상태");
        check_step("P7 frontier 5 복원 후 6,7 성장", 7, 7, 4);

        // P8: 무효화. 술어나 데이터셋이 바뀌면 DRAM 표는 의미가 없어집니다.
        //     frontier 가 0 으로 돌아가 처음부터 다시 만들어야 합니다.
        pulse_invalidate();
        do_prep(2);
        check_buf(2, "P8 무효화 후 j=2 상태");
        check_step("P8 무효화 후 재구축", 2, 9, 4);

        if (dram_errors !== 32'd0) begin
            errors = errors + 1;
            $display("FAIL: DRAM 모델이 프로토콜 오류 %0d건을 보고했습니다", dram_errors);
        end

        repeat (10) @(negedge clk);
        $display("=== 결과: 오류 %0d 건 ===", errors);
        if (errors == 0) $display("PASS");
        else             $display("FAIL");
        $finish;
    end

    initial begin
        #200_000_000;
        $display("FAIL: 타임아웃");
        $finish;
    end

endmodule


//=====================================================================
// iter_engine_stub -- grover_ctrl_fsm + grover_iter_datapath 자리 채우개
//
// 진짜 Grover 한 반복 대신, "반복 j 의 상태 = base(row,lane) + j" 라는
// 눈에 보이는 규칙을 지킵니다.
//   iter_do_init=1  버퍼를 base(row,lane) 으로 채웁니다 (j=0)
//   iter_do_init=0  iter_count 번, 모든 레인에 1 을 더합니다 (j -> j+1)
//
// 더하기가 버퍼의 현재 내용에 의존한다는 점이 중요합니다. 복원이 한 칸
// 밀리거나 엉뚱한 슬롯을 읽어 오면 그 뒤의 성장 결과가 통째로 어긋나므로
// 값 검사에서 반드시 드러납니다.
//
// 포트 이름과 handshake 는 grover_ctrl_fsm 과 같습니다 (iter_start 는
// 유휴일 때만 수락, iter_done 은 1사이클 펄스, amp 읽기 지연 1사이클).
//=====================================================================
module iter_engine_stub (
    input  wire                         clk,
    input  wire                         rstn,

    input  wire                         iter_start,
    input  wire                         iter_do_init,
    input  wire [15:0]                  iter_count,
    output reg                          iter_done,

    output reg  [`GP_ROW_W-1:0]         grow_rd_row,
    output reg                          grow_rd_en,
    input  wire [`GP_P*`GP_AMP_W-1:0]   grow_rd_amp,

    output reg  [`GP_ROW_W-1:0]         grow_wr_row,
    output reg                          grow_wr_en,
    output reg  [`GP_P*`GP_AMP_W-1:0]   grow_wr_amp
);
    localparam integer ROW_BITS = `GP_P * `GP_AMP_W;
    localparam integer ROWS     = `GP_ROWS;

    localparam [2:0]
        E_IDLE = 3'd0,
        E_INIT = 3'd1,
        E_RD   = 3'd2,
        E_WAIT = 3'd3,
        E_WR   = 3'd4,
        E_NEXT = 3'd5,
        E_DONE = 3'd6;

    reg [2:0]  st;
    reg [15:0] left;             // 남은 반복 수
    reg [`GP_ROW_W-1:0] row;
    reg row_last;

    integer k;

    // INIT 값: base(row,lane) = row*32 + lane
    function [ROW_BITS-1:0] init_row;
        input [`GP_ROW_W-1:0] r;
        integer l;
        begin
            init_row = {ROW_BITS{1'b0}};
            for (l = 0; l < `GP_P; l = l + 1)
                init_row[l*`GP_AMP_W +: `GP_AMP_W] = (r * `GP_P + l);
        end
    endfunction

    always @(posedge clk) begin
        if (!rstn) begin
            st          <= E_IDLE;
            left        <= 16'd0;
            row         <= {`GP_ROW_W{1'b0}};
            row_last    <= 1'b0;
            iter_done   <= 1'b0;
            grow_rd_en  <= 1'b0;
            grow_wr_en  <= 1'b0;
            grow_rd_row <= {`GP_ROW_W{1'b0}};
            grow_wr_row <= {`GP_ROW_W{1'b0}};
            grow_wr_amp <= {ROW_BITS{1'b0}};
        end else begin
            iter_done  <= 1'b0;
            grow_rd_en <= 1'b0;
            grow_wr_en <= 1'b0;

            case (st)
                E_IDLE: begin
                    if (iter_start) begin
                        row  <= {`GP_ROW_W{1'b0}};
                        left <= iter_count;
                        if (iter_do_init) st <= E_INIT;
                        else if (iter_count == 16'd0) st <= E_DONE;
                        else st <= E_RD;
                    end
                end

                // INIT: 매 사이클 한 행씩 채웁니다.
                E_INIT: begin
                    grow_wr_row <= row;
                    grow_wr_amp <= init_row(row);
                    grow_wr_en  <= 1'b1;
                    if (row == (ROWS - 1)) begin
                        row <= {`GP_ROW_W{1'b0}};
                        // do_init 과 함께 온 iter_count 만큼 이어서 돌립니다.
                        st  <= (left == 16'd0) ? E_DONE : E_RD;
                    end else begin
                        row <= row + 1'b1;
                    end
                end

                // 한 행 읽기 요청. rd_en 은 다음 사이클에 버스에 실립니다.
                E_RD: begin
                    grow_rd_row <= row;
                    grow_rd_en  <= 1'b1;
                    st          <= E_WAIT;
                end

                // rd_en 이 실려 있는 사이클. amp_mem 이 이 사이클 끝의
                // posedge 에 rd_q 를 잡으므로 데이터는 그다음에 유효합니다.
                E_WAIT: begin
                    st <= E_WR;
                end

                // 이제 grow_rd_amp 가 유효합니다. 레인마다 1 을 더해 되씁니다.
                E_WR: begin
                    for (k = 0; k < `GP_P; k = k + 1)
                        grow_wr_amp[k*`GP_AMP_W +: `GP_AMP_W] <=
                            grow_rd_amp[k*`GP_AMP_W +: `GP_AMP_W] + 1'b1;
                    grow_wr_row <= row;
                    grow_wr_en  <= 1'b1;
                    row_last    <= (row == (ROWS - 1));
                    st          <= E_NEXT;
                end

                E_NEXT: begin
                    if (row_last) begin
                        row  <= {`GP_ROW_W{1'b0}};
                        left <= left - 16'd1;
                        st   <= (left == 16'd1) ? E_DONE : E_RD;
                    end else begin
                        row <= row + 1'b1;
                        st  <= E_RD;
                    end
                end

                E_DONE: begin
                    iter_done <= 1'b1;
                    st        <= E_IDLE;
                end

                default: st <= E_IDLE;
            endcase
        end
    end
endmodule
