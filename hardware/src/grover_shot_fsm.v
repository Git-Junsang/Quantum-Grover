//=====================================================================
// grover_shot_fsm.v -- 바깥 샷 루프 · BBHT (소유자 D)
//
// 계약 4.10. 두 모드가 공존합니다.
//   auto_shot=1  BBHT 자율 모드. 하드웨어가 m 을 키우고 j 를 추첨하고
//                캐시 판정까지 합니다. 펌웨어는 설정 -> start -> 폴링만.
//   auto_shot=0  펌웨어 구동 모드. 앱이 절대값 j_target 을 쓰고 start 를
//                누르며, 한 번의 start 가 정확히 한 샷입니다. 캐시 정확성
//                증명 · M 을 아는 비교 · 골든 비트정확 재생에 계속 씁니다.
//
// 어느 쪽이든 j_cur 과 cache_valid 는 grover_cache_ctrl 이 소유합니다.
// 그래서 상태가 두 곳에 생기지 않습니다.
//
// CSR 의 j_target 레지스터를 하드웨어가 되쓰지 않습니다. 생성된 MMIO 의
// 설정 레지스터는 APB 쓰기로만 바뀌므로 IP 가 거꾸로 쓸 포트가 없고,
// j_req = auto_shot ? 추첨값 : csr_j_target 이라는 먹스 하나로 정리됩니다.
// 실제로 무엇을 돌았는지는 RO 인 j_cur 이 알려 줍니다.
//
// !! j 추첨은 잠정입니다 !!  계약 9절이 미정입니다. 지금은 m 의 비트폭만큼
// 마스킹한 뒤 m 이상이면 버리는 기각 샘플링이고, 한 시도마다 32비트 추출을
// 정확히 1회 소비합니다. 단순 마스킹은 균등하지 않으므로 기각이 필요합니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_shot_fsm (
    input  wire                clk,
    input  wire                rstn,
    // CSR 설정 · 명령
    input  wire                start,          // W1P 펄스
    input  wire                auto_shot,
    input  wire                enum_mode,
    input  wire [15:0]         cfg_j_target,
    input  wire [4:0]          n_qubits,
    input  wire [15:0]         shot_cap,
    // cache_ctrl
    output reg                 shot_start,
    output wire [15:0]         j_req,
    input  wire                do_init,
    input  wire [15:0]         delta_j,
    // ctrl_fsm
    output reg                 iter_start,
    output reg                 iter_do_init,
    output reg  [15:0]         iter_count,
    input  wire                iter_done,
    input  wire                pass_tick,
    // born_sampler
    output reg                 meas_start,
    input  wire                meas_done,
    input  wire [`GP_NB-1:0]   meas_cand,
    // verify
    output reg                 vfy_start,
    input  wire                vfy_done,
    input  wire                vfy_hit,
    // mask_mem
    output reg                 mask_set,
    output wire [`GP_NB-1:0]   mask_idx,
    input  wire                mclr_busy,
    // lfsr
    input  wire [31:0]         rnd,
    output wire                rnd_draw,
    // iter_rom
    output wire [4:0]          rom_idx,
    input  wire [15:0]         rom_m,
    // result_fifo
    output reg                 res_push,
    output wire [`GP_NB-1:0]   res_data,
    input  wire                res_full,
    // status
    output wire                busy,
    output reg                 done,
    output reg                 too_many,
    output reg                 verify_hit,
    output reg  [`GP_NB-1:0]   cand,
    output reg  [15:0]         shots,
    output reg  [31:0]         cycle_cnt,
    output reg  [31:0]         passes_run
);
    localparam NB = `GP_NB;

    localparam T_IDLE  = 4'd0,  T_DRAW  = 4'd1,  T_CACHE = 4'd2,
               T_ITER  = 4'd3,  T_ITERW = 4'd4,  T_MEAS  = 4'd5,
               T_MEASW = 4'd6,  T_VFY   = 4'd7,  T_VFYW  = 4'd8,
               T_MASK  = 4'd9,  T_FIN   = 4'd10;

    reg [3:0]  st;
    reg        busy_r;
    reg [4:0]  k;             // iter_rom 인덱스 = BBHT 라운드 번호
    reg [15:0] j_draw;
    reg [`GP_NB-1:0] cand_r;
    reg [1:0]  mwait;         // mask_mem 의 read-modify-write 대기
    integer    kk;

    // ── j ~ U[0, m) 기각 샘플링 ─────────────────────────────────────
    wire [15:0] m_minus1 = rom_m - 16'd1;
    reg  [4:0]  mw;
    always @* begin
        mw = 5'd0;
        for (kk = 0; kk < 16; kk = kk + 1)
            if (m_minus1[kk]) mw = kk[4:0] + 5'd1;
    end
    wire [15:0] jmask = (mw == 5'd0) ? 16'd0 : ((16'd1 << mw) - 16'd1);
    wire [15:0] jr    = rnd[15:0] & jmask;
    wire        j_ok  = (jr < rom_m);

    assign rom_idx  = k;
    assign j_req    = auto_shot ? j_draw : cfg_j_target;
    assign mask_idx = cand_r;
    assign res_data = cand_r;
    assign rnd_draw = (st == T_DRAW);
    assign busy     = busy_r;

    // 이번 샷을 끝으로 실행을 닫아야 하는가
    wire [15:0] shots_next = shots + 16'd1;
    wire        cap_hit    = (shots_next >= shot_cap);

    always @(posedge clk) begin
        if (!rstn) begin
            st           <= T_IDLE;
            busy_r       <= 1'b0;
            done         <= 1'b0;
            too_many     <= 1'b0;
            verify_hit   <= 1'b0;
            cand         <= {NB{1'b0}};
            cand_r       <= {NB{1'b0}};
            shots        <= 16'd0;
            k            <= 5'd0;
            j_draw       <= 16'd0;
            cycle_cnt    <= 32'd0;
            passes_run   <= 32'd0;
            shot_start   <= 1'b0;
            iter_start   <= 1'b0;
            iter_do_init <= 1'b0;
            iter_count   <= 16'd0;
            meas_start   <= 1'b0;
            vfy_start    <= 1'b0;
            mask_set     <= 1'b0;
            res_push     <= 1'b0;
            mwait        <= 2'd0;
        end else begin
            // 1사이클 펄스들
            shot_start <= 1'b0;
            iter_start <= 1'b0;
            meas_start <= 1'b0;
            vfy_start  <= 1'b0;
            mask_set   <= 1'b0;
            res_push   <= 1'b0;
            done       <= 1'b0;

            // 두 카운터는 start 로 클리어되고 done 까지 셉니다 (통신 규약 5).
            // cycle_cnt 는 벽시계, passes_run 은 알고리즘 지표입니다.
            if (busy_r) begin
                cycle_cnt <= cycle_cnt + 32'd1;
                if (pass_tick) passes_run <= passes_run + 32'd1;
            end

            case (st)
                T_IDLE : begin
                    // 적재 중이거나 마스크 스윕 중이면 start 를 조용히 버립니다.
                    // 펌웨어가 start 전에 busy 를 확인하는 것이 규약입니다.
                    if (start && !mclr_busy) begin
                        busy_r     <= 1'b1;
                        shots      <= 16'd0;
                        k          <= 5'd0;
                        too_many   <= 1'b0;
                        verify_hit <= 1'b0;
                        cycle_cnt  <= 32'd0;
                        passes_run <= 32'd0;
                        st         <= auto_shot ? T_DRAW : T_CACHE;
                    end
                end

                // 기각되면 이 상태에 머물며 다음 난수로 다시 시도합니다.
                T_DRAW : begin
                    if (j_ok) begin
                        j_draw <= jr;
                        st     <= T_CACHE;
                    end
                end

                // 캐시 판정. do_init / delta_j 는 조합으로 나오므로 여기서 붙듭니다.
                T_CACHE : begin
                    shot_start   <= 1'b1;
                    iter_do_init <= do_init;
                    iter_count   <= delta_j;
                    st           <= T_ITER;
                end

                T_ITER  : begin iter_start <= 1'b1; st <= T_ITERW; end
                T_ITERW : if (iter_done) st <= T_MEAS;

                T_MEAS  : begin meas_start <= 1'b1; st <= T_MEASW; end
                T_MEASW : if (meas_done) begin
                    cand_r <= meas_cand;
                    st     <= T_VFY;
                end

                T_VFY   : begin vfy_start <= 1'b1; st <= T_VFYW; end
                T_VFYW  : if (vfy_done) begin
                    shots <= shots_next;
                    if (vfy_hit) begin
                        verify_hit <= 1'b1;
                        cand       <= cand_r;
                        if (enum_mode) begin
                            mask_set <= 1'b1;      // found 비트를 세웁니다
                            res_push <= 1'b1;
                            mwait    <= 2'd3;
                            st       <= T_MASK;
                        end else begin
                            st <= T_FIN;
                        end
                    end else if (!auto_shot) begin
                        // 펌웨어 구동 모드는 실패해도 한 샷으로 끝냅니다.
                        st <= T_FIN;
                    end else if (cap_hit) begin
                        too_many <= 1'b1;
                        st       <= T_FIN;
                    end else begin
                        k  <= (k < 5'd29) ? k + 5'd1 : 5'd29;   // m 확대
                        st <= T_DRAW;
                    end
                end

                // mask_mem 의 read-modify-write 가 끝나기를 기다립니다.
                // 마스크가 바뀌면 오라클이 바뀌므로 캐시는 grover_top 에서
                // mask_set 을 cfg_we 로 OR 해 그 자리에서 무효화됩니다.
                T_MASK : begin
                    if (mwait != 2'd0) mwait <= mwait - 2'd1;
                    else if (!auto_shot || cap_hit || res_full) begin
                        if (auto_shot && cap_hit) too_many <= 1'b1;
                        st <= T_FIN;
                    end else begin
                        k  <= 5'd0;          // 새 라운드는 m=1 에서 다시
                        st <= T_DRAW;
                    end
                end

                T_FIN : begin
                    busy_r <= 1'b0;
                    done   <= 1'b1;          // busy 가 내려가는 같은 사이클
                    st     <= T_IDLE;
                end

                default : st <= T_IDLE;
            endcase
        end
    end
endmodule
