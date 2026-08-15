//=====================================================================
// grover_ctrl_fsm.v -- 안쪽 반복 FSM · 주소 생성 (소유자 C)
//
// 계약 4.6.  S_IDLE -> S_INIT -> (S_PASS1 -> S_MEAN -> S_PASS2) x dj -> S_IDLE
//
// 파이프라인 정렬 (PIPE_LAT = 2, grover_param.vh 에서 확정)
//   t   : amp_raddr / data_addr 제시, amp_re
//   t+1 : rdata 유효 -> predicate -> lane -> adder_tree (전부 조합).
//         레인 출력을 grover_top 의 레지스터에 받고, 부분합은 이 사이클에 누적
//   t+2 : 그 레지스터를 amp_mem 에 되쓰기. 주소는 2사이클 지연시킨 ac_d2
// 패스 하나가 depth_eff + 2 사이클, 반복 1회가 2*(depth_eff+2) + 1 사이클입니다.
// n=15, P=32 이면 2,053 사이클이고 계약이 허용한 ITER_OVH <= 8 안에 듭니다.
//
// n_qubits 는 런타임 가변입니다. 유효 깊이 depth_eff = 2^(n-LOGP) 이므로
// n=8,10,12 회귀에서는 배열의 앞쪽만 돌게 됩니다.
//
// 계약 4.6 표에 없는 포트가 하나 있습니다 -- amp_waddr. 위 파이프라인이
// 읽기 주소와 쓰기 주소를 같은 사이클에 서로 다르게 요구하므로 필요하고,
// grover_amp_mem 머리의 설명과 같은 이유입니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_ctrl_fsm (
    input  wire                clk,
    input  wire                rstn,
    // 상위(shot_fsm)와의 핸드셰이크 -- 계약 2절 규약
    input  wire                iter_start,     // 1사이클 펄스. busy 중이면 무시
    input  wire                iter_do_init,   // 1이면 INIT 먼저
    input  wire [15:0]         iter_count,     // 돌릴 반복 수 dj
    input  wire [4:0]          n_qubits,
    output wire                iter_busy,
    output reg                 iter_done,
    // 트레이스 · INIT 구간 디코드용
    output wire [3:0]          state,
    // 메모리 주소
    output wire [`GP_AW-1:0]   amp_raddr,
    output wire [`GP_AW-1:0]   amp_waddr,
    output wire                amp_re,
    output wire                amp_we,
    output wire [`GP_AW-1:0]   data_addr,
    output wire                data_re,
    // 데이터패스 제어
    output wire                phase,          // 0 = 1패스, 1 = 2패스
    output wire                acc_clear,
    output wire                acc_en,
    output reg                 pass_tick       // 패스 하나가 끝날 때 펄스
);
    localparam AW   = `GP_AW;
    localparam LOGP = `GP_LOGP;

    // 유효 깊이. n <= LOGP 인 퇴화 구성은 한 행으로 클램프합니다.
    wire [AW:0] depth_eff = (n_qubits > LOGP[4:0])
                          ? ({{AW{1'b0}}, 1'b1} << (n_qubits - LOGP[4:0]))
                          : {{AW{1'b0}}, 1'b1};

    reg [3:0]    st;
    reg [AW:0]   cnt;
    reg [15:0]   left;
    reg          v_d1, v_d2;      // 읽기 발행이 파이프라인을 따라 내려온 표시
    reg [AW-1:0] ac_d1, ac_d2;

    always @(posedge clk) begin
        if (!rstn) begin
            st        <= `GP_ST_IDLE;
            cnt       <= {(AW+1){1'b0}};
            left      <= 16'd0;
            v_d1      <= 1'b0;
            v_d2      <= 1'b0;
            ac_d1     <= {AW{1'b0}};
            ac_d2     <= {AW{1'b0}};
            iter_done <= 1'b0;
            pass_tick <= 1'b0;
        end else begin
            iter_done <= 1'b0;
            pass_tick <= 1'b0;

            // 파이프라인은 상태와 무관하게 항상 흐릅니다. 패스가 아닌
            // 상태에서는 issue 가 0 이라 저절로 비워집니다.
            v_d1  <= issue;
            v_d2  <= v_d1;
            ac_d1 <= cnt[AW-1:0];
            ac_d2 <= ac_d1;

            case (st)
                `GP_ST_IDLE : begin
                    if (iter_start) begin
                        left <= iter_count;
                        cnt  <= {(AW+1){1'b0}};
                        if (iter_do_init)          st <= `GP_ST_INIT;
                        else if (iter_count != 16'd0) st <= `GP_ST_PASS1;
                        else                       iter_done <= 1'b1;  // 할 일 없음
                    end
                end

                // 전 칸에 초기 진폭을 씁니다. 쓰기 데이터는 grover_top 이
                // state 를 디코드해 INIT 상수로 먹스합니다.
                `GP_ST_INIT : begin
                    cnt <= cnt + 1'b1;
                    if (cnt == depth_eff - 1'b1) begin
                        cnt <= {(AW+1){1'b0}};
                        if (left != 16'd0) st <= `GP_ST_PASS1;
                        else begin
                            st        <= `GP_ST_IDLE;
                            iter_done <= 1'b1;
                        end
                    end
                end

                `GP_ST_PASS1 : begin
                    cnt <= cnt + 1'b1;
                    // depth_eff 번 읽고 파이프라인이 두 칸 빠져나갈 때까지
                    if (cnt == depth_eff + 1'b1) begin
                        pass_tick <= 1'b1;
                        st        <= `GP_ST_MEAN;
                    end
                end

                // two_mean_calc 는 조합이고 total 은 이 시점에 굳어 있으므로
                // 한 사이클만 지나면 2패스 내내 값이 안정합니다.
                `GP_ST_MEAN : begin
                    cnt <= {(AW+1){1'b0}};
                    st  <= `GP_ST_PASS2;
                end

                `GP_ST_PASS2 : begin
                    cnt <= cnt + 1'b1;
                    if (cnt == depth_eff + 1'b1) begin
                        pass_tick <= 1'b1;
                        left      <= left - 1'b1;
                        if (left == 16'd1) begin
                            st        <= `GP_ST_IDLE;
                            iter_done <= 1'b1;
                        end else begin
                            st  <= `GP_ST_PASS1;
                            cnt <= {(AW+1){1'b0}};
                        end
                    end
                end

                default : st <= `GP_ST_IDLE;
            endcase
        end
    end

    wire in_pass = (st == `GP_ST_PASS1) || (st == `GP_ST_PASS2);
    wire issue   = in_pass && (cnt < depth_eff);

    assign state     = st;
    assign amp_raddr = cnt[AW-1:0];
    assign data_addr = cnt[AW-1:0];
    assign amp_re    = issue;
    assign data_re   = issue;
    // INIT 은 읽지 않으므로 지연이 없습니다. 패스에서는 t+2 에 되씁니다.
    assign amp_we    = (st == `GP_ST_INIT) ? 1'b1 : v_d2;
    assign amp_waddr = (st == `GP_ST_INIT) ? cnt[AW-1:0] : ac_d2;
    assign phase     = (st == `GP_ST_PASS2);
    assign acc_clear = (st == `GP_ST_PASS1) && (cnt == {(AW+1){1'b0}});
    assign acc_en    = (st == `GP_ST_PASS1) && v_d1;
    // done 과 겹치지 않게 -- done 은 IDLE 로 돌아온 사이클에 펄스합니다.
    assign iter_busy = (st != `GP_ST_IDLE);
endmodule
