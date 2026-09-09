/*
 * bbht_grover_driver.h -- BBHT/Grover 공용 드라이버
 *
 * PJK 인수인계 §2.1 요청분입니다. 지금까지 proof app 다섯 개(APB / DMA /
 * Single / Enumeration / K4H8)가 각자 CSR 접근 코드를 복사해 갖고 있었는데,
 * 그것을 하나로 모읍니다. 다섯째 앱 이름의 K4H8 은 그 시절 표기이고,
 * 지금 CSR 실행 모드 이름은 CKPT_SINGLE / CKPT_ENUM 입니다.
 *
 * 이 드라이버가 강제하는 규약 다섯:
 *   1. base address 는 RVX 생성 매크로. 숫자를 박지 않습니다
 *   2. 모든 대기에 timeout 이 있습니다. 무한 폴링이 없습니다
 *   3. DMA 전에 정렬 / 범위 / 개수를 SW 에서 먼저 검사합니다
 *   4. 결과는 STATUS.busy 가 내려간 뒤에만 읽습니다
 *   5. Enumeration 은 실행 중에도 FIFO 를 계속 뽑습니다
 */
#ifndef BBHT_GROVER_DRIVER_H
#define BBHT_GROVER_DRIVER_H

#include "bbht_grover_regs.h"

/*--------------------------------------------------------------------
 * 반환 코드
 *------------------------------------------------------------------*/
typedef enum {
    BBHT_OK            =  0,
    BBHT_ERR_TIMEOUT   = -1,   /* 폴링 상한 초과 */
    BBHT_ERR_DMA       = -2,   /* DMA_STATUS 에 오류 비트 */
    BBHT_ERR_STATUS    = -3,   /* STATUS 에 치명 오류 비트 */
    BBHT_ERR_ARG       = -4,   /* 호출자가 넘긴 값이 규격 밖 */
    BBHT_ERR_BUSY      = -5,   /* 시작 조건 불충족 */
    BBHT_ERR_NOT_FOUND = -6    /* 정상 종료했으나 해가 없음 */
} bbht_status_t;

/*--------------------------------------------------------------------
 * 설정
 *------------------------------------------------------------------*/
typedef struct {
    unsigned int predicate;      /* BBHT_PRED_LT / GT / EQ / RANGE */
    int          threshold_a;
    int          threshold_b;    /* RANGE 에서만 씀 */
    unsigned int data_count;     /* 1 ~ BBHT_N_ENTRIES */
    unsigned int shot_cap;
    unsigned int seed_j;
    unsigned int seed_meas;
    unsigned int auto_shot;      /* 0: manual j, 1: BBHT 자율 */
    unsigned int burst_enable;   /* 1: true K4/H8 checkpoint */
    unsigned int j_target;       /* auto_shot=0 일 때만 의미 있음 (0~127) */
    unsigned int enum_enable;    /* 1: 열거 */
    unsigned int fail_limit;     /* 열거 실패 반복 한계 1~15 */
} bbht_config_t;

/*--------------------------------------------------------------------
 * 실행 결과 + 텔레메트리
 *------------------------------------------------------------------*/
typedef struct {
    unsigned int status;              /* STATUS 원본 */
    unsigned int result_valid;
    unsigned int result_index;

    unsigned int trial_count;
    unsigned int l_bbht;              /* 알고리즘 지표 -- checkpoint 로 안 줄어듦 */
    unsigned int actual_iter;         /* 물리 반복 -- checkpoint 가 줄이는 대상 */
    unsigned int cycle_count;         /* clk_accel 사이클 */

    unsigned int found_count;
    unsigned int consec_fail;
    unsigned int max_fifo_occ;
    unsigned int fifo_stall;

    /* K4/H8 텔레메트리 */
    unsigned int policy_cycles;
    unsigned int policy_stall;
    unsigned int policy_actions;
    unsigned int policy_memo_hit;
    unsigned int policy_memo_miss;
    unsigned int policy_max_latency;
    unsigned int plan_level;
    unsigned int plan_highwater;
    unsigned int plan_empty_demand;
    unsigned int plan_hit;
    unsigned int plan_mismatch;       /* 정상 기대값 0 */
    unsigned int cold_solve;
    unsigned int spec_solve;

    /* 판정 요약 */
    unsigned int timed_out;
    unsigned int fatal_error;         /* config / zero_weight / load */
    unsigned int limit_hit;           /* shot_cap / budget */
    unsigned int amp_overflow;        /* 진단용. 결과 무효를 뜻하지 않습니다 */
} bbht_result_t;

/*--------------------------------------------------------------------
 * 폴링 상한. 100 MHz 에서 넉넉히 잡은 값입니다. RTL 시뮬은 느리므로
 * 앱에서 필요하면 키우십시오.
 *------------------------------------------------------------------*/
#ifndef BBHT_TIMEOUT
#define BBHT_TIMEOUT 2000000u
#endif

/*--------------------------------------------------------------------
 * API
 *------------------------------------------------------------------*/

/* 설정 구조체를 기본값으로 채웁니다. Normal BBHT Single, EQ, 전체 범위. */
void bbht_config_init(bbht_config_t *cfg);

/* CSR 이 살아 있는지 확인합니다. CONTROL 에 패턴을 쓰고 되읽습니다.
 * 부작용이 없는 레지스터만 건드리므로 브링업 첫 단계로 안전합니다. */
bbht_status_t bbht_probe(void);

/* System SRAM 의 배열을 DMA 로 적재합니다.
 *   words      32비트 워드 버퍼. 4바이트 정렬이어야 합니다
 *   data_count 16비트 항목 수. 워드 수는 (data_count+1)/2
 * 정렬 / 범위 / 개수를 여기서 먼저 검사하고, 통과해야 DMA_COMMAND 를 씁니다. */
bbht_status_t bbht_dma_load(const unsigned int *words, unsigned int data_count);

/* 16비트 항목을 32비트 워드 버퍼에 넣고 빼는 도우미.
 * word[k][15:0] -> data[2k], word[k][31:16] -> data[2k+1] 규약입니다. */
void         bbht_pack16(unsigned int *words, unsigned int index, int value);
int          bbht_unpack16(const unsigned int *words, unsigned int index);

/* 설정을 CSR 에 씁니다. COMMAND 는 쓰지 않습니다. */
bbht_status_t bbht_apply_config(const bbht_config_t *cfg);

/* Single 탐색 한 번. 설정 -> COMMAND -> 폴링 -> 결과 수집까지 합니다. */
bbht_status_t bbht_search_single(const bbht_config_t *cfg, bbht_result_t *res);

/* 열거. 실행 중에도 FIFO 를 뽑아 out[] 에 채웁니다.
 *   out / max   결과를 받을 버퍼와 그 크기
 *   n_out       실제로 받은 개수
 * FIFO 는 256칸이라 열거 대상이 그보다 많으면 실행 중에 뽑지 않는 한
 * full stall 이 걸립니다. 그래서 done 만 기다리면 안 됩니다. */
bbht_status_t bbht_search_enum(const bbht_config_t *cfg,
                               unsigned short *out, unsigned int max,
                               unsigned int *n_out, bbht_result_t *res);

/* 마지막 실행의 카운터와 텔레메트리를 다시 읽습니다.
 * busy 가 내려간 뒤에만 부르십시오 -- 실행 중에 읽으면 서로 다른 시점의
 * 값이 섞인 스냅샷이 나옵니다. */
void bbht_read_result(bbht_result_t *res);

/* 사람이 읽는 진단 문자열. NULL 을 반환하지 않습니다. */
const char *bbht_status_str(bbht_status_t rc);

/* STATUS / DMA_STATUS 의 선 비트를 한 줄로 찍습니다. 브링업용입니다. */
void bbht_dump_status(void);

/* 사이클 -> 마이크로초. clk_accel 기준이라 100 MHz 에서 cycles/100 입니다.
 * 클럭을 바꾸면 bbht_grover_csr.json 의 accel_clk_hz 만 고치면 됩니다. */
unsigned int bbht_cycles_to_us(unsigned int cycles);

#endif /* BBHT_GROVER_DRIVER_H */
