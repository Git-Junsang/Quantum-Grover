//=====================================================================
// grover_param.vh -- 전 모듈이 include 하는 파라미터 헤더
//
// 소유자 C. 정본은 documents/design/인터페이스_계약.md 1절이고,
// 수치의 최종 정본은 해설서 15.4절 확정 설계 결정표입니다.
// 이 파일의 값을 바꾸면 골든 모델 · 기대 벡터 · BRAM 예산이 전부
// 다시 계산되어야 하므로, 계약 11절의 변경 절차를 밟으십시오.
//=====================================================================
`ifndef GROVER_PARAM_VH
`define GROVER_PARAM_VH

// ── 합성 시 고르는 것 (보드 · 스테이징에 따라 바뀜) ──────────────────
`define GP_NB     15          // 인덱스 폭 = 지원하는 최대 큐비트 수
`define GP_DW     18          // 진폭 폭 (Q2.16)
`define GP_QF     16          // 소수부 비트 수
`define GP_W      16          // 데이터 워드 폭 (signed)
`define GP_P      32          // 병렬 레인 수
`define GP_LOGP   5           // log2(P). P 를 바꾸면 이 값도 같이 고칠 것

// ── 유도값 — 손으로 고치지 말 것 ────────────────────────────────────
`define GP_AW     (`GP_NB - `GP_LOGP)      // 10   뱅크 내 주소 폭
`define GP_DEPTH  (1 << `GP_AW)            // 1024 뱅크 깊이
`define GP_N      (1 << `GP_NB)            // 32768
`define GP_PSW    (`GP_DW + `GP_LOGP)      // 23   adder_tree 부분합
`define GP_ACCW   (`GP_DW + `GP_NB + 2)    // 35   진폭 합 누산기
`define GP_TMW    (`GP_DW + 2)             // 20   two_mean · 확산 중간값
`define GP_SQW    (2 * `GP_DW)             // 36   진폭 제곱 (Q4.32)
`define GP_MACCW  (`GP_SQW + `GP_AW)       // 46   뱅크별 제곱합
`define GP_TOTW   (`GP_MACCW + `GP_LOGP)   // 51   전체 제곱합 total

// ── 상수 ────────────────────────────────────────────────────────────
`define GP_ONE_Q216        18'sd65536      // 1.0
`define GP_INV_SQRT2_Q216  18'sd46341      // 1/sqrt(2) = round(0.70710678 * 2^16)
`define GP_AMP_MAX         18'sd131071     // +2.0 직전
`define GP_AMP_MIN        -18'sd131071     // 대칭 포화 (계약 1.2)

// ── 술어 인코딩 (계약 5절, 소유자 B) ────────────────────────────────
// 네 술어 모두 강부등호입니다. 열린 구간으로 고정한 것은 약속의 문제입니다.
`define GP_MODE_LT     2'b00      // value <  thr_a
`define GP_MODE_GT     2'b01      // value >  thr_a
`define GP_MODE_EQ     2'b10      // value == thr_a
`define GP_MODE_RANGE  2'b11      // thr_a < value < thr_b

// ── ctrl_fsm 상태 인코딩 ────────────────────────────────────────────
// state 출력은 트레이스용이면서 동시에 grover_top 이 INIT 구간을 알아내는
// 유일한 수단입니다. top 이 amp_mem 쓰기 데이터를 INIT 상수로 먹스해야 하는데,
// 그 판정을 새 포트 대신 이 인코딩 디코드로 합니다.
`define GP_ST_IDLE   4'd0
`define GP_ST_INIT   4'd1
`define GP_ST_PASS1  4'd2
`define GP_ST_MEAN   4'd3
`define GP_ST_PASS2  4'd4

// ── 파이프라인 깊이 ─────────────────────────────────────────────────
// RTL_모듈_명세 4.6 의 3단 흐름입니다.
//   t   : amp_raddr / data_addr 제시, amp_re=1
//   t+1 : rdata 유효 -> predicate -> lane -> adder_tree (전부 조합).
//         레인 출력을 레지스터에 받고, 부분합은 같은 사이클에 누적
//   t+2 : 그 레지스터를 amp_mem 에 되쓰기 (주소는 2사이클 지연)
// 되쓰기 앞에 레지스터를 두는 것이 요점입니다. BRAM 읽기부터 BRAM 쓰기까지가
// 한 사이클에 다 들어가면 100 MHz 에서 임계 경로가 술어와 레인과 트리를
// 통째로 지나게 됩니다.
//   패스 하나   = DEPTH + PIPE_LAT      = 1026
//   반복 1회    = 2*(DEPTH+PIPE_LAT)+1  = 2053   (ITER_OVH = 5)
`define GP_PIPE_LAT  2

// ── 잠정값 — 아직 확정되지 않은 항목 ────────────────────────────────
// 해설서 17.8절 7번(M_max)과 16.9절 1번(M=0 종료 조건)이 미결입니다.
// 아래 둘은 그 자리를 막아 두기 위한 잠정값이고, 확정되면 계약을 고칩니다.
`define GP_SHOT_CAP    16'd256    // 샷 상한. 넘으면 status.too_many
`define GP_RESQ_DEPTH  16         // result_fifo 깊이

`endif
