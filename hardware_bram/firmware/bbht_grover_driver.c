/*
 * bbht_grover_driver.c -- BBHT/Grover 공용 드라이버 구현
 *
 * 규약과 배경은 bbht_grover_driver.h 머리말에 있습니다.
 */
#include "bbht_grover_driver.h"

/*--------------------------------------------------------------------*/
void bbht_config_init(bbht_config_t *cfg)
{
    cfg->predicate    = BBHT_PRED_EQ;
    cfg->threshold_a  = 0;
    cfg->threshold_b  = 0;
    cfg->data_count   = BBHT_N_ENTRIES;
    cfg->shot_cap     = 100u;
    cfg->seed_j       = 0x1u;
    cfg->seed_meas    = 0x1u;
    cfg->auto_shot    = 1u;      /* Normal BBHT */
    cfg->burst_enable = 0u;
    cfg->j_target     = 0u;
    cfg->enum_enable  = 0u;
    cfg->fail_limit   = 4u;
}

/*--------------------------------------------------------------------*/
unsigned int bbht_cycles_to_us(unsigned int cycles)
{
    return cycles / (BBHT_ACCEL_CLK_HZ / 1000000u);
}

/*--------------------------------------------------------------------
 * CSR 이 살아 있는지.
 *
 * CONTROL 은 설정 레지스터라 쓰고 되읽어도 아무것도 시작되지 않습니다.
 * 원래 값을 되돌려 놓고 나옵니다.
 *------------------------------------------------------------------*/
bbht_status_t bbht_probe(void)
{
    unsigned int saved = bbht_rd(BBHT_CONTROL);
    unsigned int rb;

    bbht_wr(BBHT_CONTROL, 0x0000000Bu);
    rb = bbht_rd(BBHT_CONTROL) & 0xFu;
    bbht_wr(BBHT_CONTROL, saved);

    return (rb == 0xBu) ? BBHT_OK : BBHT_ERR_STATUS;
}

/*--------------------------------------------------------------------*/
void bbht_pack16(unsigned int *words, unsigned int index, int value)
{
    unsigned int w = index >> 1;
    unsigned int v = ((unsigned int)value) & 0xFFFFu;

    if ((index & 1u) == 0u)
        words[w] = (words[w] & 0xFFFF0000u) | v;
    else
        words[w] = (words[w] & 0x0000FFFFu) | (v << 16);
}

int bbht_unpack16(const unsigned int *words, unsigned int index)
{
    unsigned int w = words[index >> 1];
    unsigned int v = ((index & 1u) == 0u) ? (w & 0xFFFFu) : ((w >> 16) & 0xFFFFu);

    /* signed 16비트로 부호 확장. 이걸 빼먹으면 음수 임계값 테스트가
     * 통째로 조용히 틀립니다. */
    return (int)(short)v;
}

/*--------------------------------------------------------------------
 * DMA 적재
 *
 * 하드웨어도 같은 검사를 하지만 SW 에서 먼저 걸러 냅니다. DMA_STATUS 의
 * 오류 비트를 보고 원인을 되짚는 것보다, 부르는 자리에서 BBHT_ERR_ARG 로
 * 튕기는 편이 브링업에서 훨씬 빠릅니다.
 *------------------------------------------------------------------*/
bbht_status_t bbht_dma_load(const unsigned int *words, unsigned int data_count)
{
    unsigned int addr = (unsigned int)(unsigned long)words;
    unsigned int nwords, last;
    unsigned int timeout = BBHT_TIMEOUT;
    unsigned int st;

    if (data_count == 0u || data_count > BBHT_N_ENTRIES)
        return BBHT_ERR_ARG;
    if ((addr & 3u) != 0u)
        return BBHT_ERR_ARG;

    nwords = (data_count + 1u) >> 1;
    last   = addr + nwords * 4u - 1u;

    if (addr < BBHT_SRAM_BASE || last > BBHT_SRAM_LAST)
        return BBHT_ERR_ARG;

    /* 적재 중에는 탐색이 돌면 안 됩니다. */
    if (bbht_rd(BBHT_STATUS) & (BBHT_ST_BUSY | BBHT_ST_LOAD_BUSY))
        return BBHT_ERR_BUSY;

    bbht_wr(BBHT_DATA_ADDR,   addr);
    bbht_wr(BBHT_DATA_COUNT,  data_count);
    bbht_wr(BBHT_DMA_COMMAND, 1u);

    while (timeout--) {
        st = bbht_rd(BBHT_DMA_STATUS);
        if (st & (BBHT_DMA_DMA_DONE_STICKY | BBHT_DMA_DMA_ERROR))
            break;
    }

    st = bbht_rd(BBHT_DMA_STATUS);

    if (st & BBHT_DMA_DMA_ERROR)
        return BBHT_ERR_DMA;
    if ((st & BBHT_DMA_DMA_DONE_STICKY) == 0u)
        return BBHT_ERR_TIMEOUT;

    return BBHT_OK;
}

/*--------------------------------------------------------------------*/
bbht_status_t bbht_apply_config(const bbht_config_t *cfg)
{
    if (cfg->predicate > BBHT_PRED_RANGE)
        return BBHT_ERR_ARG;
    if (cfg->data_count == 0u || cfg->data_count > BBHT_N_ENTRIES)
        return BBHT_ERR_ARG;
    if (cfg->j_target > 127u)
        return BBHT_ERR_ARG;
    /* fail_repeat_limit 0 은 하드웨어가 config_error 로 잡습니다.
     * 열거 모드에서만 의미가 있으므로 그때만 막습니다. */
    if (cfg->enum_enable && (cfg->fail_limit == 0u || cfg->fail_limit > 15u))
        return BBHT_ERR_ARG;

    bbht_wr(BBHT_CONTROL,
            BBHT_CONTROL_WORD(cfg->auto_shot, cfg->burst_enable, cfg->predicate));
    bbht_wr(BBHT_J_TARGET,    cfg->j_target);
    bbht_wr(BBHT_THRESHOLD_A, (unsigned int)cfg->threshold_a & 0xFFFFu);
    bbht_wr(BBHT_THRESHOLD_B, (unsigned int)cfg->threshold_b & 0xFFFFu);
    bbht_wr(BBHT_DATA_COUNT,  cfg->data_count);
    bbht_wr(BBHT_SHOT_CAP,    cfg->shot_cap);
    bbht_wr(BBHT_SEED_J,      cfg->seed_j);
    bbht_wr(BBHT_SEED_MEAS,   cfg->seed_meas);
    bbht_wr(BBHT_ENUM_CFG,
            BBHT_ENUM_CFG_WORD(cfg->enum_enable, cfg->fail_limit));

    return BBHT_OK;
}

/*--------------------------------------------------------------------*/
void bbht_read_result(bbht_result_t *res)
{
    unsigned int st = bbht_rd(BBHT_STATUS);

    res->status       = st;
    res->result_valid = (st & BBHT_ST_RESULT_VALID) ? 1u : 0u;
    res->result_index = bbht_rd(BBHT_RESULT_INDEX);

    res->trial_count  = bbht_rd(BBHT_TRIAL_COUNT);
    res->l_bbht       = bbht_rd(BBHT_L_BBHT);
    res->actual_iter  = bbht_rd(BBHT_ACTUAL_ITER);
    res->cycle_count  = bbht_rd(BBHT_CYCLE_COUNT);

    res->found_count  = bbht_rd(BBHT_FOUND_COUNT);
    res->consec_fail  = bbht_rd(BBHT_CONSEC_FAIL);
    res->max_fifo_occ = bbht_rd(BBHT_MAX_FIFO_OCC);
    res->fifo_stall   = bbht_rd(BBHT_FIFO_STALL);

    res->policy_cycles      = bbht_rd(BBHT_POLICY_CYCLES_TOTAL);
    res->policy_stall       = bbht_rd(BBHT_POLICY_STALL_CYCLES);
    res->policy_actions     = bbht_rd(BBHT_POLICY_ACTIONS_EVAL);
    res->policy_memo_hit    = bbht_rd(BBHT_POLICY_MEMO_HIT);
    res->policy_memo_miss   = bbht_rd(BBHT_POLICY_MEMO_MISS);
    res->policy_max_latency = bbht_rd(BBHT_POLICY_MAX_LATENCY);
    res->plan_level         = bbht_rd(BBHT_PLAN_FIFO_LEVEL);
    res->plan_highwater     = bbht_rd(BBHT_PLAN_FIFO_HIGHWATER);
    res->plan_empty_demand  = bbht_rd(BBHT_PLAN_FIFO_EMPTY_DEMAND);
    res->plan_hit           = bbht_rd(BBHT_PLAN_FIFO_HIT_COUNT);
    res->plan_mismatch      = bbht_rd(BBHT_PLAN_FIFO_MISMATCH_COUNT);
    res->cold_solve         = bbht_rd(BBHT_POLICY_COLD_SOLVE_COUNT);
    res->spec_solve         = bbht_rd(BBHT_POLICY_SPEC_SOLVE_COUNT);

    res->fatal_error  = (st & BBHT_ST_FATAL_MASK) ? 1u : 0u;
    res->limit_hit    = (st & BBHT_ST_LIMIT_MASK) ? 1u : 0u;
    res->amp_overflow = (st & BBHT_ST_AMP_OVERFLOW) ? 1u : 0u;
}

/*--------------------------------------------------------------------
 * 시작 조건.
 *
 * 하드웨어는 조건이 안 맞으면 start 펄스를 조용히 버립니다. 큐가 없으므로
 * 펌웨어가 먼저 확인하는 것이 규약입니다. 확인하지 않으면 "시작한 줄 알고
 * 폴링하다가 직전 실행의 done 을 보고 낡은 결과를 읽는" 형태로 틀립니다.
 *------------------------------------------------------------------*/
static bbht_status_t bbht_wait_ready(void)
{
    unsigned int timeout = BBHT_TIMEOUT;
    unsigned int st;

    while (timeout--) {
        st = bbht_rd(BBHT_STATUS);
        if ((st & (BBHT_ST_BUSY | BBHT_ST_LOAD_BUSY)) == 0u)
            return BBHT_OK;
    }
    return BBHT_ERR_TIMEOUT;
}

/* 남아 있는 FIFO 를 비웁니다. res_empty 를 봐야 합니다 -- 인덱스 0 이
 * 정상 결과일 수 있으므로 값 0 을 empty 로 해석하면 안 됩니다. */
static void bbht_fifo_flush(void)
{
    unsigned int guard = BBHT_FIFO_DEPTH + 8u;

    while (guard-- && !(bbht_rd(BBHT_STATUS) & BBHT_ST_FIFO_EMPTY))
        (void)bbht_rd(BBHT_FIFO_DATA);
}

/*--------------------------------------------------------------------*/
bbht_status_t bbht_search_single(const bbht_config_t *cfg, bbht_result_t *res)
{
    unsigned int timeout = BBHT_TIMEOUT;
    unsigned int st;
    bbht_status_t rc;

    rc = bbht_wait_ready();
    if (rc != BBHT_OK) return rc;

    bbht_fifo_flush();

    rc = bbht_apply_config(cfg);
    if (rc != BBHT_OK) return rc;

    bbht_wr(BBHT_COMMAND, 1u);

    while (timeout--) {
        st = bbht_rd(BBHT_STATUS);
        if (st & BBHT_ST_DONE_STICKY)
            break;
    }

    bbht_read_result(res);
    res->timed_out = (res->status & BBHT_ST_DONE_STICKY) ? 0u : 1u;

    if (res->timed_out)   return BBHT_ERR_TIMEOUT;
    if (res->fatal_error) return BBHT_ERR_STATUS;
    if (!res->result_valid) return BBHT_ERR_NOT_FOUND;

    return BBHT_OK;
}

/*--------------------------------------------------------------------
 * 열거.
 *
 * done 만 기다리면 안 됩니다. Result FIFO 가 256칸이라 그보다 많은 해가
 * 나오면 하드웨어가 full stall 에 걸려 진행이 멈춥니다. 그래서 busy 인
 * 동안에도 계속 뽑습니다 (인수인계 §1.6).
 *------------------------------------------------------------------*/
bbht_status_t bbht_search_enum(const bbht_config_t *cfg,
                               unsigned short *out, unsigned int max,
                               unsigned int *n_out, bbht_result_t *res)
{
    unsigned int timeout = BBHT_TIMEOUT;
    unsigned int st;
    unsigned int n = 0u;
    bbht_config_t local = *cfg;
    bbht_status_t rc;

    *n_out = 0u;

    local.enum_enable = 1u;

    rc = bbht_wait_ready();
    if (rc != BBHT_OK) return rc;

    bbht_fifo_flush();

    rc = bbht_apply_config(&local);
    if (rc != BBHT_OK) return rc;

    bbht_wr(BBHT_COMMAND, 1u);

    while (timeout--) {
        st = bbht_rd(BBHT_STATUS);

        /* 먼저 뽑고, 그 다음에 종료를 봅니다. 순서가 반대면 done 과 같은
         * 사이클에 들어온 마지막 결과를 흘립니다. */
        while (!(bbht_rd(BBHT_STATUS) & BBHT_ST_FIFO_EMPTY)) {
            unsigned int v = bbht_rd(BBHT_FIFO_DATA) & 0x3FFFu;
            if (n < max) out[n] = (unsigned short)v;
            n++;
        }

        if (st & BBHT_ST_DONE_STICKY)
            break;
    }

    /* done 이 선 뒤에 남은 것까지 마저 뽑습니다. */
    while (!(bbht_rd(BBHT_STATUS) & BBHT_ST_FIFO_EMPTY)) {
        unsigned int v = bbht_rd(BBHT_FIFO_DATA) & 0x3FFFu;
        if (n < max) out[n] = (unsigned short)v;
        n++;
    }

    bbht_read_result(res);
    res->timed_out = (res->status & BBHT_ST_DONE_STICKY) ? 0u : 1u;
    *n_out = (n < max) ? n : max;

    if (res->timed_out)   return BBHT_ERR_TIMEOUT;
    if (res->fatal_error) return BBHT_ERR_STATUS;

    return BBHT_OK;
}

/*--------------------------------------------------------------------*/
const char *bbht_status_str(bbht_status_t rc)
{
    switch (rc) {
    case BBHT_OK:            return "OK";
    case BBHT_ERR_TIMEOUT:   return "TIMEOUT";
    case BBHT_ERR_DMA:       return "DMA_ERROR";
    case BBHT_ERR_STATUS:    return "STATUS_ERROR";
    case BBHT_ERR_ARG:       return "BAD_ARG";
    case BBHT_ERR_BUSY:      return "BUSY";
    case BBHT_ERR_NOT_FOUND: return "NOT_FOUND";
    default:                 return "UNKNOWN";
    }
}

/*--------------------------------------------------------------------
 * 브링업용 상태 덤프.
 *
 * printf 는 RVX 의 것을 씁니다. 호스트에서 드라이버만 따로 컴파일해
 * 문법을 확인할 때는 BBHT_NO_PRINTF 를 정의하십시오.
 *------------------------------------------------------------------*/
#ifndef BBHT_NO_PRINTF
#include "ervp_printf.h"

static const char *const bbht_status_names[12] = {
    "busy", "load_busy", "done", "result_valid",
    "config_error", "shot_limit", "budget_limit", "amp_overflow",
    "zero_weight_error", "load_error", "enum_done", "fifo_empty"
};

static const char *const bbht_dma_names[8] = {
    "dma_busy", "dma_error", "align_error", "count_error",
    "resp_error", "busy_error", "range_error", "dma_done"
};

void bbht_dump_status(void)
{
    unsigned int st  = bbht_rd(BBHT_STATUS);
    unsigned int dst = bbht_rd(BBHT_DMA_STATUS);
    int i;

    printf("STATUS=0x%08x :", st);
    for (i = 0; i < 12; i++)
        if (st & (1u << i)) printf(" %s", bbht_status_names[i]);
    printf("\n");

    printf("DMA_STATUS=0x%08x :", dst);
    for (i = 0; i < 8; i++)
        if (dst & (1u << i)) printf(" %s", bbht_dma_names[i]);
    printf("\n");
}
#else
void bbht_dump_status(void) { }
#endif
