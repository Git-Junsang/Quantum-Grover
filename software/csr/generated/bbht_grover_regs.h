/*
 * bbht_grover_regs.h -- BBHT/Grover CSR 레지스터 정의
 *
 * 이 파일은 gen_csr.py 가 bbht_grover_csr.json 에서 생성했습니다. 직접 고치지 마십시오.
 *
 * 정본 버전 0.9.8 (2026-09-01)
 */
#ifndef BBHT_GROVER_REGS_H
#define BBHT_GROVER_REGS_H

/*
 * base address 는 RVX 가 플랫폼에서 생성한 매크로를 씁니다.
 * 숫자를 직접 박으면 플랫폼 XML 이 바뀔 때 조용히 엉뚱한 주소를 두드립니다.
 * (현재 생성값 0xE2020000 -- 참고용이고 코드에서 쓰지 마십시오)
 *
 * BBHT_HOST_TEST 를 정의하면 CSR 접근이 함수 호출로 바뀝니다. 드라이버를
 * 보드가 아니라 verilator 모델에 붙여 회귀를 돌리기 위한 갈래이고,
 * 펌웨어 빌드에는 영향이 없습니다.
 */
#ifdef BBHT_HOST_TEST
extern unsigned int bbht_host_rd(unsigned int off);
extern void         bbht_host_wr(unsigned int off, unsigned int val);
#define BBHT_CSR_BASE       0u
#define bbht_rd(off)        bbht_host_rd(off)
#define bbht_wr(off, val)   bbht_host_wr((off), (unsigned int)(val))
#else
#include "platform_info.h"
#define BBHT_CSR_BASE       I_GROVER_CSR_SLAVE_BASEADDR
#define BBHT_REG(off)       (*(volatile unsigned int *)(BBHT_CSR_BASE + (off)))
#define bbht_rd(off)        BBHT_REG(off)
#define bbht_wr(off, val)   do { BBHT_REG(off) = (unsigned int)(val); } while (0)
#endif

#define BBHT_CSR_SIZE       0x1000
#define BBHT_CSR_STRIDE     4

/* 탐색 공간과 시스템 상수 */
#define BBHT_Q_BITS         14
#define BBHT_N_ENTRIES      16384u
#define BBHT_RESULT_BITS    14
#define BBHT_FIFO_DEPTH     256u
#define BBHT_ACCEL_CLK_HZ   100000000u
/* 호스트 회귀는 자기 버퍼 주소를 쓰므로 덮어쓸 수 있게 둡니다. */
#ifndef BBHT_SRAM_BASE
#define BBHT_SRAM_BASE      0xE0000000u
#endif
#ifndef BBHT_SRAM_LAST
#define BBHT_SRAM_LAST      0xE001FFFFu
#endif

/* 레지스터 오프셋 */
#define BBHT_COMMAND                    0x000u   /* W1P  탐색 시작 */
#define BBHT_CONTROL                    0x004u   /* RW   동작 모드 */
#define BBHT_J_TARGET                   0x008u   /* RW   manual requested j (0~127) */
#define BBHT_THRESHOLD_A                0x00Cu   /* RW   임계값 A */
#define BBHT_THRESHOLD_B                0x010u   /* RW   임계값 B */
#define BBHT_DATA_COUNT                 0x014u   /* RW   유효 데이터 개수 1~16384 */
#define BBHT_SHOT_CAP                   0x018u   /* RW   BBHT shot 상한 */
#define BBHT_SEED_J                     0x01Cu   /* RW   requested-j PRNG 시드 */
#define BBHT_SEED_MEAS                  0x020u   /* RW   측정 PRNG 시드 */
#define BBHT_STATUS                     0x024u   /* RO   실행 상태 */
#define BBHT_RESULT_INDEX               0x028u   /* RO   Single 모드 결과 인덱스 */
#define BBHT_TRIAL_COUNT                0x02Cu   /* RO   run 전체의 logical trial 수 */
#define BBHT_L_BBHT                     0x030u   /* RO   Sum of requested j - 알고리즘 지표 */
#define BBHT_ACTUAL_ITER                0x034u   /* RO   실제로 돌린 물리 Grover 반복 수 - checkpoint 가 줄이는 대상 */
#define BBHT_CYCLE_COUNT                0x038u   /* RO   run 소비 사이클 */
#define BBHT_ENUM_CFG                   0x03Cu   /* RW   열거 모드 설정 */
#define BBHT_FIFO_DATA                  0x040u   /* RPOP Result FIFO head */
#define BBHT_FIFO_COUNT                 0x044u   /* RO   현재 FIFO occupancy */
#define BBHT_FOUND_COUNT                0x048u   /* RO   unique target 누적 */
#define BBHT_CONSEC_FAIL                0x04Cu   /* RO   complete BBHT failure 연속 횟수 */
#define BBHT_MAX_FIFO_OCC               0x050u   /* RO   run 중 최대 occupancy */
#define BBHT_FIFO_STALL                 0x054u   /* RO   FIFO full 로 멈춘 사이클 */
#define BBHT_DATA_ADDR                  0x058u   /* RW   System SRAM 원본 주소 */
#define BBHT_DMA_COMMAND                0x05Cu   /* W1P  DMA 적재 시작 */
#define BBHT_DMA_STATUS                 0x060u   /* RO   DMA 상태 */
#define BBHT_POLICY_CYCLES_TOTAL        0x064u   /* RO   policy 총 사이클 */
#define BBHT_POLICY_STALL_CYCLES        0x068u   /* RO   policy stall */
#define BBHT_POLICY_ACTIONS_EVAL        0x06Cu   /* RO   평가한 action 수 */
#define BBHT_POLICY_MEMO_HIT            0x070u   /* RO   memo hit */
#define BBHT_POLICY_MEMO_MISS           0x074u   /* RO   memo miss */
#define BBHT_POLICY_MAX_LATENCY         0x078u   /* RO   policy 최대 지연 */
#define BBHT_PLAN_FIFO_LEVEL            0x07Cu   /* RO   현재 plan FIFO 레벨 */
#define BBHT_PLAN_FIFO_HIGHWATER        0x080u   /* RO   plan FIFO 최고 수위 */
#define BBHT_PLAN_FIFO_EMPTY_DEMAND     0x084u   /* RO   demand 시 empty 횟수 */
#define BBHT_PLAN_FIFO_HIT_COUNT        0x088u   /* RO   speculative plan hit */
#define BBHT_PLAN_FIFO_MISMATCH_COUNT   0x08Cu   /* RO   정상 기대값 0 */
#define BBHT_POLICY_COLD_SOLVE_COUNT    0x090u   /* RO   cold solve 횟수 */
#define BBHT_POLICY_SPEC_SOLVE_COUNT    0x094u   /* RO   speculative solve */

/* STATUS 비트 */
#define BBHT_ST_BUSY                 (1u << 0 )  /* search/main busy */
#define BBHT_ST_LOAD_BUSY            (1u << 1 )  /* Main IP loader busy */
#define BBHT_ST_DONE_STICKY          (1u << 2 )  /* search 완료 sticky. COMMAND 쓰기로 클리어 */
#define BBHT_ST_RESULT_VALID         (1u << 3 )  /* Single result 유효 */
#define BBHT_ST_CONFIG_ERROR         (1u << 4 )  /* 설정 오류 sticky */
#define BBHT_ST_SHOT_LIMIT           (1u << 5 )  /* shot cap 도달 sticky */
#define BBHT_ST_BUDGET_LIMIT         (1u << 6 )  /* BBHT logical budget 도달 sticky */
#define BBHT_ST_AMP_OVERFLOW         (1u << 7 )  /* 진폭 포화 sticky. 진단용이며 종료 사유가 아님 */
#define BBHT_ST_ZERO_WEIGHT_ERROR    (1u << 8 )  /* Born total-weight 오류 sticky */
#define BBHT_ST_LOAD_ERROR           (1u << 9 )  /* loader 검증 오류 sticky */
#define BBHT_ST_ENUM_DONE            (1u << 10)  /* Enumeration 종료 sticky */
#define BBHT_ST_FIFO_EMPTY           (1u << 11)  /* Result FIFO 비어 있음 */

/* 종료 사유 판별에 쓰는 묶음. amp_overflow 는 진단용이라 뺐습니다 -- 이것이
 * 서 있어도 결과는 유효할 수 있습니다(PJK 벤치마크 앱과 같은 취급). */
#define BBHT_ST_FATAL_MASK  (BBHT_ST_CONFIG_ERROR | \
                             BBHT_ST_ZERO_WEIGHT_ERROR | \
                             BBHT_ST_LOAD_ERROR)
#define BBHT_ST_LIMIT_MASK  (BBHT_ST_SHOT_LIMIT | BBHT_ST_BUDGET_LIMIT)

/* DMA_STATUS 비트 */
#define BBHT_DMA_DMA_BUSY            (1u << 0 )  /* DMA 진행 중 */
#define BBHT_DMA_DMA_ERROR           (1u << 1 )  /* 아래 오류들의 OR */
#define BBHT_DMA_ALIGN_ERROR         (1u << 2 )  /* DATA_ADDR 4바이트 정렬 위반 */
#define BBHT_DMA_COUNT_ERROR         (1u << 3 )  /* DATA_COUNT 범위 위반 */
#define BBHT_DMA_RESP_ERROR          (1u << 4 )  /* AHB 응답 오류 */
#define BBHT_DMA_BUSY_ERROR          (1u << 5 )  /* Main IP busy 라서 DMA 거절 */
#define BBHT_DMA_RANGE_ERROR         (1u << 6 )  /* System SRAM 범위 밖 */
#define BBHT_DMA_DMA_DONE_STICKY     (1u << 7 )  /* DMA 완료 sticky */

/* CONTROL / ENUM_CFG 필드 */
#define BBHT_COMMAND_SEARCH_START_SHIFT  0
#define BBHT_COMMAND_SEARCH_START_MASK   0x00000001u
#define BBHT_CONTROL_AUTO_SHOT_SHIFT  0
#define BBHT_CONTROL_AUTO_SHOT_MASK   0x00000001u
#define BBHT_CONTROL_BURST_ENABLE_SHIFT  1
#define BBHT_CONTROL_BURST_ENABLE_MASK   0x00000002u
#define BBHT_CONTROL_PREDICATE_MODE_SHIFT  2
#define BBHT_CONTROL_PREDICATE_MODE_MASK   0x0000000Cu
#define BBHT_ENUM_CFG_ENUM_ENABLE_SHIFT  0
#define BBHT_ENUM_CFG_ENUM_ENABLE_MASK   0x00000001u
#define BBHT_ENUM_CFG_FAIL_REPEAT_LIMIT_SHIFT  4
#define BBHT_ENUM_CFG_FAIL_REPEAT_LIMIT_MASK   0x000000F0u
#define BBHT_DMA_COMMAND_DMA_START_SHIFT  0
#define BBHT_DMA_COMMAND_DMA_START_MASK   0x00000001u

/* 술어 */
#define BBHT_PRED_LT       0   /* data < A */
#define BBHT_PRED_GT       1   /* data > A */
#define BBHT_PRED_EQ       2   /* data == A */
#define BBHT_PRED_RANGE    3   /* A < data < B (열린구간) */

/* CONTROL 레지스터 조립 */
#define BBHT_CONTROL_WORD(auto_shot, burst, pred) \
    ((((unsigned int)(auto_shot) & 1u) << 0) | \
     (((unsigned int)(burst)     & 1u) << 1) | \
     (((unsigned int)(pred)      & 3u) << 2))

/* ENUM_CFG 레지스터 조립 */
#define BBHT_ENUM_CFG_WORD(enable, fail_limit) \
    ((((unsigned int)(enable)     &  1u) << 0) | \
     (((unsigned int)(fail_limit) & 15u) << 4))

/* 권장 운용 모드 (auto_shot, burst_enable, enum_enable) */
/*   MANUAL_SINGLE  auto=0 burst=0 enum=0  J_TARGET 을 펌웨어가 지정 */
/*   NORMAL_SINGLE  auto=1 burst=0 enum=0  표준 BBHT */
/*   K4H8_SINGLE    auto=1 burst=1 enum=0  checkpoint 모드 (K·H·E·M 은 RTL 빌드에 컴파일됨. 현 정본은 K3/H3-E4-M2. 이름의 K4H8 은 옛 표기) */
/*   NORMAL_ENUM    auto=1 burst=0 enum=1  표준 BBHT 열거 */
/*   K4H8_ENUM      auto=1 burst=1 enum=1  checkpoint 열거 (K·H·E·M 은 RTL 빌드에 컴파일됨. 현 정본은 K3/H3-E4-M2. 이름의 K4H8 은 옛 표기) */

#endif /* BBHT_GROVER_REGS_H */
