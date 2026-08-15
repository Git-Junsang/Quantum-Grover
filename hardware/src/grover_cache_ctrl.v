//=====================================================================
// grover_cache_ctrl.v -- 재개 캐시 판정 · 무효화 (소유자 D)
//
// 계약 4.9. 이 프로젝트의 핵심 기여가 사는 곳이고, 자원은 레지스터 둘
// (j_cur 16b, cache_valid 1b) 과 비교기 · 감산기 하나씩입니다. BRAM 0개.
//
//   do_init = !cache_valid || force_init || (j_req < j_cur)
//   delta_j = do_init ? j_req : (j_req - j_cur)
//   iter_done 에서 : j_cur <= j_req,  cache_valid <= 1
//   cfg_we 에서    : cache_valid <= 0
//
// 진폭 배열에 쓰는 연산은 INIT · 오라클 · 확산 셋뿐이고 측정은 읽기만,
// 검증은 data_mem 한 칸만 건드립니다. 그래서 실패한 샷이 남긴 상태가
// 그대로 유효하고, 재개한 경로는 새로 초기화해 j 회 돈 것과 비트 단위로
// 같은 연산열을 실행합니다.
//
// 무효화를 펌웨어에 맡기지 않는 이유는 해설서 16.7절에 있습니다. 나중에
// 술어를 하나 더 추가한 사람이 무효화를 빼먹으면 크래시도 타임아웃도 아닌
// 그럴듯한 인덱스 하나가 나옵니다.
//=====================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_cache_ctrl (
    input  wire        clk,
    input  wire        rstn,
    input  wire        shot_start,    // 샷 시작 펄스
    input  wire [15:0] j_req,         // 이번 샷의 목표 (절대값)
    input  wire        force_init,    // CSR 펄스
    input  wire        cfg_we,        // 무효화 대상 레지스터 쓰기 스트로브 OR
    input  wire        iter_done,     // 반복 완료 -> j_cur 확정
    output wire        do_init,
    output wire [15:0] delta_j,
    output reg  [15:0] j_cur,
    output reg         cache_valid
);
    reg [15:0] j_lat;      // 이번 샷이 요청한 값. iter_done 에서 j_cur 로 굳습니다
    reg        force_pend; // force_init 펄스를 샷이 소비할 때까지 붙들어 둡니다

    assign do_init = (!cache_valid) || force_pend || (j_req < j_cur);
    assign delta_j = do_init ? j_req : (j_req - j_cur);

    always @(posedge clk) begin
        if (!rstn) begin
            j_cur       <= 16'd0;
            j_lat       <= 16'd0;
            cache_valid <= 1'b0;
            force_pend  <= 1'b0;
        end else begin
            if (force_init) force_pend <= 1'b1;
            if (shot_start) j_lat <= j_req;

            // 무효화가 완료 갱신보다 우선입니다. 설정이 바뀐 뒤에 끝난 반복은
            // 이미 낡은 오라클로 돈 것이라 재개의 근거가 되지 못합니다.
            if (cfg_we || force_init) begin
                cache_valid <= 1'b0;
            end else if (iter_done) begin
                j_cur       <= j_lat;
                cache_valid <= 1'b1;
                force_pend  <= 1'b0;
            end
        end
    end
endmodule
