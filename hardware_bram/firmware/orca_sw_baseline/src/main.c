#include "platform_info.h"
#include "ervp_printf.h"
#include "baseline_config.h"
#include "bbht_sw_core.h"
#include "seed_roster.h"
#include <stdint.h>
#include "ervp_real_clock.h"

/*
 * ORCA pure-software BBHT/Grover baseline.
 *
 * IMPORTANT TIMING CONTRACT
 * -------------------------
 * - No accelerator CSR is accessed by this application.
 * - Target-mask preparation and printf are outside the timed region.
 * - RVX real-clock timing covers bbht_sw_run() only: search start -> success/termination.
 * - timer_hi/timer_lo are emitted separately so RV32 printf does not need
 *   64-bit format support.
 */

static uint64_t read_sw_timer64(void)
{
    return get_real_clock_tick();
}

static void print_run(uint32_t target_count, uint32_t seed_index,
                      const bbht_sw_result_t *r, uint64_t cycles)
{
    uint32_t hi = (uint32_t)(cycles >> 32);
    uint32_t lo = (uint32_t)cycles;
    const bbht_seed_pair_t *sp = &bbht_seed_roster[seed_index];

    printf("SW_RUN,%u,%u,0x%08x,0x%08x,%u,%u,%u,%u,%u,%u,%u,%u,%u\n",
           target_count,
           seed_index,
           sp->seed_j,
           sp->seed_meas,
           r->success,
           r->result_index,
           r->trial_count,
           r->l_bbht,
           r->grover_iterations,
           r->termination,
           r->saturation_count,
           hi,
           lo);
}

static int run_one(uint32_t target_count, uint32_t seed_index)
{
    bbht_sw_result_t r;
    uint64_t t0, t1, cycles;

    bbht_sw_prepare_target_mask(target_count);

    t0 = read_sw_timer64();
    bbht_sw_run(bbht_seed_roster[seed_index].seed_j,
                bbht_seed_roster[seed_index].seed_meas,
                &r);
    t1 = read_sw_timer64();
    cycles = t1 - t0;

    print_run(target_count, seed_index, &r, cycles);

    if (!r.success || !bbht_sw_is_target(r.result_index))
        return 0;
    return 1;
}

int main(void)
{
    static const uint32_t targets[5] = {1u, 4u, 16u, 64u, 256u};
    uint32_t ti, si;
    uint32_t pass = 0u;
    uint32_t total = 0u;

    printf("[RVX/START] ORCA_PURE_SW_BBHT\n");
    printf("SW_BASELINE,Q14,N=16384,FRAC=22,BUDGET=576,SHOT_CAP=100\n");
    printf("SW_TIMING_SOURCE,RVX_REAL_CLOCK\n");
    printf("SW_TIMING_UNIT,microsecond_tick\n");
    printf("SW_TIMING_CORE_CLK_HZ,50000000\n");
    printf("SW_TIMING_SCOPE,bbht_sw_run_only,target_setup_and_printf_excluded\n");
    printf("SW_RUN_HEADER,target_count,seed_index,seed_j,seed_meas,success,result_index,trial_count,L_BBHT,grover_iterations,termination,saturations,timer_hi,timer_lo\n");

#if BBHT_SW_RUN_FULL
    {
        uint32_t seed_count = BBHT_SW_SEED_COUNT;
        if (seed_count > 100u)
            seed_count = 100u;
        printf("SW_PROFILE,FULL,target_groups=5,seeds=%u\n", seed_count);
        for (ti = 0u; ti < 5u; ++ti) {
            for (si = 0u; si < seed_count; ++si) {
                ++total;
                if (run_one(targets[ti], si))
                    ++pass;
            }
        }
    }
#else
    printf("SW_PROFILE,SMOKE,target_count=256,seed_index=0\n");
    total = 1u;
    pass = run_one(256u, 0u) ? 1u : 0u;
#endif

    printf("SW_SUMMARY,pass=%u,total=%u\n", pass, total);

#if !BBHT_SW_RUN_FULL
    /* Frozen/publication semantic anchor for target=256, seed0. */
    {
        bbht_sw_result_t r;
        bbht_sw_prepare_target_mask(256u);
        bbht_sw_run(bbht_seed_roster[0].seed_j,
                    bbht_seed_roster[0].seed_meas,
                    &r);
        if (r.success && r.result_index == 15288u &&
            r.trial_count == 8u && r.l_bbht == 7u) {
            printf("SW_SMOKE_SEMANTIC,PASS,expected_result=15288,trial=8,L=7\n");
        } else {
            printf("SW_SMOKE_SEMANTIC,FAIL,result=%u,trial=%u,L=%u\n",
                   r.result_index, r.trial_count, r.l_bbht);
            return 2;
        }
    }
#endif

    printf("[RVX/END] ORCA_PURE_SW_BBHT\n");
    return (pass == total) ? 0 : 1;
}
