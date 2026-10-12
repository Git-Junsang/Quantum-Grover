#include "platform_info.h"
#include "ervp_printf.h"
#include "ervp_real_clock.h"
#include <stdint.h>

#include "baseline_config.h"
#include "bbht_q14.h"
#include "p500_workloads.h"

/*
 * ORCA same-core software baselines for the Q14 BBHT/Grover accelerator.
 * Model and profile: baseline_config.h (BBHT_MODEL, BBHT_PROFILE).
 *
 * TIMING CONTRACT (same as the team orca_sw_baseline)
 * - No accelerator CSR is accessed; run it on an ORCA-only build.
 * - Oracle preparation (target bitset) and printf are outside the timed region.
 * - The RVX real clock covers bbht_search() only: search start -> result,
 *   the same interval as the FPGA wall_us (data already loaded).
 * - timer_hi/timer_lo are printed separately (no 64-bit printf on RV32).
 */

#if BBHT_MODEL == 1
#define MODEL_NAME "NAIVE_DENSE_MATRIX_NORMAL"
#elif BBHT_MODEL == 2
#define MODEL_NAME "OPT_ONEPASS_K3H3"
#else
#define MODEL_NAME "OPT_ONEPASS_NORMAL"
#endif

static bbht_oracle_t g_oracle;

static uint64_t now_tick(void) { return get_real_clock_tick(); }

static void print_ticks(uint64_t t)
{
    printf(",%u,%u\n", (unsigned)(t >> 32), (unsigned)t);
}

static void set_oracle(int p, int mi)
{
    bbht_oracle_init(&g_oracle, &p500_targets[p500_target_offset[p][mi]], p500_m[mi]);
}

#if BBHT_PROFILE != 2
static int run_one(int p, int mi, int s, bbht_result_t *r)
{
    uint64_t t0, t1;
    set_oracle(p, mi);
    t0 = now_tick();
    bbht_search(BBHT_MODEL, &g_oracle, p500_seed_j[s], p500_seed_meas[s], r, 0, 0);
    t1 = now_tick();
    printf("SW_RUN,%d,%s,%u,%d,0x%08x,0x%08x,%u,%d,%u,%u,%u,%u,%u", BBHT_MODEL, p500_pred_name[p],
           (unsigned)p500_m[mi], s, (unsigned)p500_seed_j[s], (unsigned)p500_seed_meas[s], (unsigned)r->success,
           (int)r->result_index, (unsigned)r->trial_count, (unsigned)r->l_bbht, (unsigned)r->physical_iterations,
           (unsigned)r->termination, (unsigned)r->saturations);
    print_ticks(t1 - t0);
    return r->success && r->result_index >= 0 && bbht_is_target(&g_oracle, (uint32_t)r->result_index);
}

#endif

#if BBHT_PROFILE == 1 || BBHT_PROFILE == 3
static void run_set(uint32_t pred_mask, uint32_t m_mask, int s0, int s1, uint32_t *pass, uint32_t *total)
{
    int p, mi, s;
    bbht_result_t r;
    for (p = 0; p < P500_NPRED; ++p) {
        if (!((pred_mask >> p) & 1u))
            continue;
        for (mi = 0; mi < P500_NM; ++mi) {
            if (!((m_mask >> mi) & 1u))
                continue;
            for (s = s0; s < s1; ++s) {
                ++*total;
                if (run_one(p, mi, s, &r))
                    ++*pass;
            }
        }
    }
}
#endif

#if BBHT_PROFILE == 2
/* Per-iteration and per-measurement cost on Predicate500 EQ, M = 1. */
static void calibrate(void)
{
    static bbht_cdf_t cdf;
    bbht_mrng_t ms;
    int64_t osum, thr;
    uint32_t k, sat = 0;
    uint64_t t0, t1;
    set_oracle(2, 0);
    bbht_state_reset(bbht_work, &osum, &g_oracle);
    t0 = now_tick();
    for (k = 0; k < BBHT_CALIB_ITERS; ++k) {
#if BBHT_ENABLE_NAIVE
        bbht_core_naive_iterate(bbht_work, &g_oracle, 0, &sat);
#else
        bbht_core_opt_iterate(bbht_work, &osum, &g_oracle, &sat);
#endif
    }
    t1 = now_tick();
    printf("SW_CALIB_ITER,%d,iterations=%u", BBHT_MODEL, (unsigned)BBHT_CALIB_ITERS);
    print_ticks(t1 - t0);
    bbht_mrng_init(&ms, p500_seed_meas[0]);
    t0 = now_tick();
    bbht_cdf_prepare(bbht_work, &cdf);
    (void)bbht_sample(bbht_work, &cdf, &ms, &thr, BBHT_MODEL != 1);
    t1 = now_tick();
    printf("SW_CALIB_MEASURE,%d,measurements=1", BBHT_MODEL);
    print_ticks(t1 - t0);
}
#endif

int main(void)
{
    uint32_t pass = 0, total = 0;

    printf("[RVX/START] ORCA_BBHT_BASELINE\n");
    printf("SW_MODEL,%d,%s\n", BBHT_MODEL, MODEL_NAME);
    printf("SW_SOURCE,orca_bbht_c,%s\n", BBHT_SRC_VERSION);
    printf("SW_CONTRACT,Q14,N=16384,Q1.22,BUDGET=576,SHOT_CAP=100,WORKLOAD=PREDICATE500\n");
    printf("SW_TIMING_SOURCE,RVX_REAL_CLOCK\n");
    printf("SW_TIMING_UNIT,microsecond_tick\n");
    printf("SW_TIMING_CORE_CLK_HZ,50000000\n");
    printf("SW_TIMING_SCOPE,bbht_search_only,oracle_setup_and_printf_excluded\n");
    printf("SW_RUN_HEADER,model,predicate,target_count,seed_index,seed_j,seed_meas,success,result_index,"
           "trial_count,L_BBHT,actual_grover_iterations,termination,saturations,timer_hi,timer_lo\n");

#if BBHT_PROFILE == 1
    {
        int seeds = BBHT_SEED_COUNT > 100u ? 100 : (int)BBHT_SEED_COUNT;
        printf("SW_PROFILE,FULL,predicates=4,target_groups=5,seeds=%d\n", seeds);
        run_set(0xFu, 0x1Fu, 0, seeds, &pass, &total);
    }
#elif BBHT_PROFILE == 2
    printf("SW_PROFILE,CALIBRATE,EQ,M=1\n");
    calibrate();
#elif BBHT_PROFILE == 3
    printf("SW_PROFILE,SUBSET,pred_mask=0x%x,m_mask=0x%x,seeds=%u..%u\n", (unsigned)BBHT_SUBSET_PRED_MASK,
           (unsigned)BBHT_SUBSET_M_MASK, (unsigned)BBHT_SUBSET_SEED_FIRST, (unsigned)BBHT_SUBSET_SEED_END - 1u);
    run_set(BBHT_SUBSET_PRED_MASK, BBHT_SUBSET_M_MASK, (int)BBHT_SUBSET_SEED_FIRST, (int)BBHT_SUBSET_SEED_END,
            &pass, &total);
#else
    {   /* SMOKE: EQ, M = 256, seed 0. Expected (model B, FPGA board): result 15288, 8 trials, L 7,
           physical iterations 7 (Normal) or 3 (K3H3). */
        bbht_result_t r;
        uint32_t phys = BBHT_MODEL == 2 ? 3u : 7u;
        printf("SW_PROFILE,SMOKE,EQ,M=256,seed=0\n");
        total = 1;
        pass = (uint32_t)run_one(2, 4, 0, &r);
        if (r.success && r.result_index == 15288 && r.trial_count == 8u && r.l_bbht == 7u &&
            r.physical_iterations == phys) {
            printf("SW_SMOKE_SEMANTIC,PASS,result=15288,trial=8,L=7,physical=%u\n", (unsigned)phys);
        } else {
            printf("SW_SMOKE_SEMANTIC,FAIL,result=%d,trial=%u,L=%u,physical=%u\n", (int)r.result_index,
                   (unsigned)r.trial_count, (unsigned)r.l_bbht, (unsigned)r.physical_iterations);
            pass = 0;
        }
    }
#endif

#if BBHT_PROFILE != 2
    printf("SW_SUMMARY,pass=%u,total=%u\n", (unsigned)pass, (unsigned)total);
#endif
    printf("[RVX/END] ORCA_BBHT_BASELINE\n");
    return (pass == total) ? 0 : 1;
}
