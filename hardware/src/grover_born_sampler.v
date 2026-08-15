//=====================================================================
// grover_born_sampler.v -- 2단 병렬 Born 측정 (소유자 C)
//
// 계약 4.7. 측정은 argmax 가 아니라 확률 |amp|^2 에 비례한 추출입니다.
// 오라클과 확산이 해집합을 완벽히 대칭으로 다루므로 M 개 해의 진폭은 매
// 반복에서 정확히 같습니다. 가장 큰 진폭을 고르는 회로였다면 언제나 같은
// 인덱스를 돌려줘 열거가 성립하지 않습니다.
//
// 3단 동작
//   1단  32뱅크 동시 읽기 -> 제곱기 32개 -> 뱅크별 누산 S[b] 와 전체 total
//        (depth_eff + PIPE_LAT 사이클)
//   2단  32항 prefix-sum 으로 뱅크 b* 선택                       (P 사이클)
//   3단  b* 뱅크만 직렬 스캔해 인덱스 확정        (depth_eff + PIPE_LAT 사이클)
//   n=15 기준 약 2,084 사이클. 32,768 사이클을 직렬로 도는 대신입니다.
//
// 안전망 두 줄이 필수입니다. 초기 진폭이 홀수 n 에서 1/sqrt(2) 를 반올림한
// 값이라 노름이 정확히 1 이 아니고, 그래서 prefix-sum 이 문턱을 끝까지 못
// 넘거나 스캔이 배열 끝에 닿는 경우가 실제로 생깁니다. 그때 b*=P-1,
// 마지막 인덱스로 떨어뜨리지 않으면 FSM 이 배열 끝에서 매답니다.
//
// 제곱기 32개가 이 IP 에서 DSP 를 쓰는 유일한 곳입니다 (DSP 32/120).
// SQW=36 을 자르지 않습니다 -- 작은 칸일수록 상대오차가 커져 분포가 기웁니다.
//
// !! 문턱 r 을 뽑는 방법은 잠정입니다 !!  계약 9절(난수 소비 규약)이
// 미정입니다. 지금은 total 의 비트폭만큼 마스킹한 뒤 total 이상이면 버리는
// 기각 샘플링이고, 한 시도마다 32비트 추출을 정확히 2회 소비합니다.
// 규약이 확정되면 이 부분과 골든 measure() 를 같이 고쳐야 합니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_born_sampler (
    input  wire                      clk,
    input  wire                      rstn,
    input  wire                      meas_start,
    input  wire [4:0]                n_qubits,
    // 난수 (계약 9절 미정 -- 머리 설명 참조)
    input  wire [31:0]               rnd,
    output wire                      rnd_draw,
    // amp_mem 읽기 포트 (grover_top 이 meas_busy 로 먹스)
    input  wire [`GP_P*`GP_DW-1:0]   amp_rdata,
    output wire [`GP_AW-1:0]         meas_addr,
    output wire                      meas_re,
    // 계약 2절 핸드셰이크
    output wire                      meas_busy,
    output reg                       meas_done,
    output reg  [`GP_NB-1:0]         cand
);
    localparam P     = `GP_P;
    localparam DW    = `GP_DW;
    localparam AW    = `GP_AW;
    localparam NB    = `GP_NB;
    localparam LOGP  = `GP_LOGP;
    localparam SQW   = `GP_SQW;              // 36
    localparam SUMW  = `GP_SQW + `GP_LOGP;   // 41  한 행 32칸의 제곱합
    localparam MACCW = `GP_MACCW;            // 46  뱅크별 제곱합
    localparam TOTW  = `GP_TOTW;             // 51  전체 제곱합

    wire [AW:0] depth_eff = (n_qubits > LOGP[4:0])
                          ? ({{AW{1'b0}}, 1'b1} << (n_qubits - LOGP[4:0]))
                          : {{AW{1'b0}}, 1'b1};

    // ── 제곱기 32개 ──────────────────────────────────────────────────
    wire [SQW-1:0] sq [0:P-1];
    genvar b;
    generate
        for (b = 0; b < P; b = b + 1) begin : g_sq
            wire signed [DW-1:0] a = amp_rdata[b*DW +: DW];
            assign sq[b] = a * a;
        end
    endgenerate

    // ── 한 행 32칸의 제곱합 (adder_tree 와 같은 짝짓기 순서) ─────────
    wire [SUMW-1:0] tnode [0:(LOGP+1)*P-1];
    genvar s, i;
    generate
        for (i = 0; i < P; i = i + 1) begin : g_tleaf
            assign tnode[i] = {{(SUMW-SQW){1'b0}}, sq[i]};
        end
        for (s = 1; s <= LOGP; s = s + 1) begin : g_tstage
            for (i = 0; i < (P >> s); i = i + 1) begin : g_tnode
                assign tnode[s*P + i] = tnode[(s-1)*P + 2*i] + tnode[(s-1)*P + 2*i + 1];
            end
        end
    endgenerate
    wire [SUMW-1:0] row_sum = tnode[LOGP*P];

    // ── 상태 ─────────────────────────────────────────────────────────
    localparam S_IDLE = 4'd0, S_ACC  = 4'd1, S_RND0 = 4'd2, S_RND1 = 4'd3,
               S_RCHK = 4'd4, S_PRE  = 4'd5, S_SCAN = 4'd6, S_FIN  = 4'd7;

    reg [3:0]      st;
    reg [AW:0]     cnt;
    reg            v1;
    reg [AW-1:0]   addr_d1;

    reg [MACCW-1:0] S [0:P-1];
    reg [TOTW-1:0]  tot;

    reg [31:0]      rnd_hi, rnd_lo;
    reg [TOTW-1:0]  r;

    reg [LOGP:0]    bcnt;
    reg [TOTW-1:0]  run;
    reg [TOTW-1:0]  rloc;
    reg [LOGP-1:0]  bsel;
    reg             sel_valid;

    reg [TOTW-1:0]  acc3;
    reg [AW-1:0]    row;
    reg             row_found;

    integer k;

    // ── 기각 샘플링 -- total 의 유효 비트폭만큼만 남깁니다 ───────────
    reg [5:0] tw;
    always @* begin
        tw = 6'd0;
        for (k = 0; k < TOTW; k = k + 1)
            if (tot[k]) tw = k[5:0] + 6'd1;
    end
    wire [63:0] rnd64   = {rnd_hi, rnd_lo};
    wire [63:0] mask64  = (tw == 6'd0) ? 64'd0 : ((64'd1 << tw) - 64'd1);
    wire [TOTW-1:0] r_try = (rnd64 & mask64);
    wire accept = (tot == {TOTW{1'b0}}) || (r_try < tot);

    // ── 2단 prefix-sum 의 한 걸음 ────────────────────────────────────
    wire [TOTW:0] next_run = {1'b0, run} + {{(TOTW+1-MACCW){1'b0}}, S[bcnt[LOGP-1:0]]};
    wire          take_bank = (!sel_valid) &&
                              ((next_run > {1'b0, r}) || (bcnt == P-1));

    // ── 3단 스캔의 한 걸음 ───────────────────────────────────────────
    wire [SQW-1:0] sq_sel  = sq[bsel];
    wire [TOTW:0]  next_a3 = {1'b0, acc3} + {{(TOTW+1-SQW){1'b0}}, sq_sel};
    wire           take_row = (!row_found) &&
                              ((next_a3 > {1'b0, rloc}) || (addr_d1 == depth_eff[AW-1:0] - 1'b1));

    always @(posedge clk) begin
        if (!rstn) begin
            st        <= S_IDLE;
            cnt       <= {(AW+1){1'b0}};
            v1        <= 1'b0;
            addr_d1   <= {AW{1'b0}};
            tot       <= {TOTW{1'b0}};
            meas_done <= 1'b0;
            cand      <= {NB{1'b0}};
            bsel      <= {LOGP{1'b0}};
            row       <= {AW{1'b0}};
            for (k = 0; k < P; k = k + 1) S[k] <= {MACCW{1'b0}};
        end else begin
            meas_done <= 1'b0;
            case (st)
                S_IDLE : begin
                    v1 <= 1'b0;
                    if (meas_start) begin
                        cnt <= {(AW+1){1'b0}};
                        tot <= {TOTW{1'b0}};
                        for (k = 0; k < P; k = k + 1) S[k] <= {MACCW{1'b0}};
                        st  <= S_ACC;
                    end
                end

                // 1단 -- 전 행을 훑으며 뱅크별 제곱합과 전체 제곱합을 만듭니다
                S_ACC : begin
                    v1      <= (cnt < depth_eff);
                    addr_d1 <= cnt[AW-1:0];
                    cnt     <= cnt + 1'b1;
                    if (v1) begin
                        for (k = 0; k < P; k = k + 1)
                            S[k] <= S[k] + {{(MACCW-SQW){1'b0}}, sq[k]};
                        tot <= tot + {{(TOTW-SUMW){1'b0}}, row_sum};
                    end
                    if (cnt == depth_eff) begin
                        v1 <= 1'b0;
                        st <= S_RND0;
                    end
                end

                // 문턱 뽑기 -- 32비트 두 번 소비하고 넘치면 통째로 다시
                S_RND0 : begin rnd_hi <= rnd; st <= S_RND1; end
                S_RND1 : begin rnd_lo <= rnd; st <= S_RCHK; end
                S_RCHK : begin
                    if (accept) begin
                        r         <= r_try;
                        run       <= {TOTW{1'b0}};
                        rloc      <= {TOTW{1'b0}};
                        bcnt      <= {(LOGP+1){1'b0}};
                        sel_valid <= 1'b0;
                        st        <= S_PRE;
                    end else begin
                        st <= S_RND0;
                    end
                end

                // 2단 -- 뱅크 하나를 고릅니다. 안전망: 끝까지 못 넘으면 P-1
                S_PRE : begin
                    if (take_bank) begin
                        bsel      <= bcnt[LOGP-1:0];
                        rloc      <= r - run;
                        sel_valid <= 1'b1;
                    end
                    run  <= next_run[TOTW-1:0];
                    bcnt <= bcnt + 1'b1;
                    if (bcnt == P-1) begin
                        cnt       <= {(AW+1){1'b0}};
                        acc3      <= {TOTW{1'b0}};
                        row_found <= 1'b0;
                        v1        <= 1'b0;
                        st        <= S_SCAN;
                    end
                end

                // 3단 -- 고른 뱅크 안을 훑습니다. 안전망: 끝에 닿으면 마지막 행
                S_SCAN : begin
                    v1      <= (cnt < depth_eff);
                    addr_d1 <= cnt[AW-1:0];
                    cnt     <= cnt + 1'b1;
                    if (v1) begin
                        if (take_row) begin
                            row       <= addr_d1;
                            row_found <= 1'b1;
                        end
                        acc3 <= next_a3[TOTW-1:0];
                    end
                    if (cnt == depth_eff) begin
                        v1 <= 1'b0;
                        st <= S_FIN;
                    end
                end

                S_FIN : begin
                    // 인덱스 하위 LOGP 비트가 뱅크, 상위가 뱅크 내 주소입니다
                    cand      <= {row, bsel};
                    meas_done <= 1'b1;
                    st        <= S_IDLE;
                end

                default : st <= S_IDLE;
            endcase
        end
    end

    wire scanning = (st == S_ACC) || (st == S_SCAN);
    assign meas_addr = cnt[AW-1:0];
    assign meas_re   = scanning && (cnt < depth_eff);
    assign rnd_draw  = (st == S_RND0) || (st == S_RND1);
    // done 과 겹치지 않게 -- S_FIN 다음 사이클에 IDLE 로 돌아오며 펄스합니다
    assign meas_busy = (st != S_IDLE);
endmodule
