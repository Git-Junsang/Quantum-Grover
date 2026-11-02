#include "platform_info.h"
#include "ervp_printf.h"
#include "seed_roster.h"
#include <stdint.h>

#define GROVER_CSR_BASE I_GROVER_CSR_SLAVE_BASEADDR
#define REG32(addr) (*(volatile unsigned int *)(addr))

/*
 * Paper benchmark stage control.
 *
 * Stage 1 : BENCH_SEED_COUNT=10,  BENCH_INCLUDE_256=1
 * Stage 2 : BENCH_SEED_COUNT=30,  BENCH_INCLUDE_256=0
 * Stage 3 : BENCH_SEED_COUNT=30,  BENCH_INCLUDE_256=1
 * Stage 4 : BENCH_SEED_COUNT=100, BENCH_INCLUDE_256=1
 */
#ifndef BENCH_SEED_COUNT
#define BENCH_SEED_COUNT 50u
#endif

#ifndef BENCH_INCLUDE_256
#define BENCH_INCLUDE_256 1
#endif

/* Full Q14 search space: no padding region in this benchmark. */
#define DATA_COUNT          16384u
#define DATA_WORD_COUNT      8192u
#define MAX_TARGET_COUNT      256u
#define TARGET_VALUE        12345u
#define SHOT_CAP              100u

/* Fixed dataset / target-position seeds for reproducibility. */
#define BACKGROUND_SEED 0x5EED1234u
#define TARGET_POS_SEED 0xA17E2026u

/* Polling timeout. Existing K4/H8 app used 1,000,000. */
#define TIMEOUT 2000000u

/* CSR map */
#define CSR_COMMAND          0x00
#define CSR_CONTROL          0x04
#define CSR_J_TARGET         0x08
#define CSR_THRESHOLD_A      0x0C
#define CSR_THRESHOLD_B      0x10
#define CSR_DATA_COUNT       0x14
#define CSR_SHOT_CAP         0x18
#define CSR_SEED_J           0x1C
#define CSR_SEED_MEAS        0x20

#define CSR_STATUS           0x24
#define CSR_RESULT_INDEX     0x28
#define CSR_TRIAL_COUNT      0x2C
#define CSR_L_BBHT           0x30
#define CSR_ACTUAL_ITER      0x34
#define CSR_CYCLE_COUNT      0x38
#define CSR_ENUM_CFG         0x3C

#define CSR_DATA_ADDR        0x58
#define CSR_DMA_COMMAND      0x5C
#define CSR_DMA_STATUS       0x60

/* K4/H8 telemetry */
#define CSR_POLICY_CYCLES       0x64
#define CSR_POLICY_STALL        0x68
#define CSR_POLICY_ACTIONS      0x6C
#define CSR_POLICY_MEMO_HIT     0x70
#define CSR_POLICY_MEMO_MISS    0x74
#define CSR_POLICY_MAX_LAT      0x78
#define CSR_PLAN_FIFO_LEVEL     0x7C
#define CSR_PLAN_FIFO_HIGH      0x80
#define CSR_PLAN_FIFO_EMPTY     0x84
#define CSR_PLAN_FIFO_HIT       0x88
#define CSR_PLAN_FIFO_MISMATCH  0x8C
#define CSR_POLICY_COLD_SOLVE   0x90
#define CSR_POLICY_SPEC_SOLVE   0x94

/* STATUS */
#define STATUS_BUSY_BIT          (1u << 0)
#define STATUS_LOAD_BUSY_BIT     (1u << 1)
#define STATUS_DONE_BIT          (1u << 2)
#define STATUS_RESULT_VALID_BIT  (1u << 3)
#define STATUS_CONFIG_ERROR_BIT  (1u << 4)
#define STATUS_SHOT_LIMIT_BIT    (1u << 5)
#define STATUS_BUDGET_LIMIT_BIT  (1u << 6)
#define STATUS_AMP_OVERFLOW_BIT  (1u << 7)
#define STATUS_ZERO_WEIGHT_BIT   (1u << 8)
#define STATUS_LOAD_ERROR_BIT    (1u << 9)

#define STATUS_UNEXPECTED_ERROR_MASK \
    (STATUS_CONFIG_ERROR_BIT |       \
     STATUS_ZERO_WEIGHT_BIT |        \
     STATUS_LOAD_ERROR_BIT)

/* DMA_STATUS */
#define DMA_ERROR_BIT  (1u << 1)
#define DMA_DONE_BIT   (1u << 7)

/*
 * CONTROL bits:
 * bit0     auto_shot
 * bit1     burst_enable
 * bits3:2  predicate_mode
 *
 * EQ = 2:
 * Normal BBHT  = auto=1, burst=0, EQ => 0x9
 * K4/H8 spec   = auto=1, burst=1, EQ => 0xB
 */
#define CONTROL_NORMAL_EQ 0x00000009u
#define CONTROL_K4H8_EQ   0x0000000Bu

#define MODE_NORMAL 0u
#define MODE_K4H8   1u

static unsigned int dataset_words[DATA_WORD_COUNT]
    __attribute__((aligned(4)));

static unsigned int target_indices[MAX_TARGET_COUNT];

typedef struct {
    unsigned int mode;
    unsigned int status;
    unsigned int result_valid;
    unsigned int result_index;
    unsigned int trial_count;
    unsigned int l_bbht;
    unsigned int actual_iter;
    unsigned int cycle_count;

    unsigned int policy_cycles;
    unsigned int policy_stall;
    unsigned int policy_actions;
    unsigned int policy_memo_hit;
    unsigned int policy_memo_miss;
    unsigned int policy_max_lat;

    unsigned int plan_level;
    unsigned int plan_high;
    unsigned int plan_empty;
    unsigned int plan_hit;
    unsigned int plan_mismatch;
    unsigned int cold_solve;
    unsigned int spec_solve;

    unsigned int terminal_limit;
    unsigned int unexpected_error;
    unsigned int timeout;
    unsigned int result_is_target;
} run_result_t;

static unsigned int xorshift32(unsigned int *state)
{
    unsigned int x = *state;

    if (x == 0u)
        x = 0x6D2B79F5u;

    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;

    *state = x;
    return x;
}

static void set_data16(unsigned int index, unsigned int value)
{
    unsigned int word_index = index >> 1;
    unsigned int v = value & 0xFFFFu;

    if ((index & 1u) == 0u)
        dataset_words[word_index] =
            (dataset_words[word_index] & 0xFFFF0000u) | v;
    else
        dataset_words[word_index] =
            (dataset_words[word_index] & 0x0000FFFFu) | (v << 16);
}

static unsigned int get_data16(unsigned int index)
{
    unsigned int word = dataset_words[index >> 1];

    if ((index & 1u) == 0u)
        return word & 0xFFFFu;
    else
        return (word >> 16) & 0xFFFFu;
}

static void generate_background(void)
{
    unsigned int state = BACKGROUND_SEED;
    unsigned int i;

    for (i = 0u; i < DATA_COUNT; i++) {
        unsigned int value = xorshift32(&state) & 0xFFFFu;

        if (value == (TARGET_VALUE & 0xFFFFu))
            value ^= 1u;

        set_data16(i, value);
    }
}

static int index_already_used(unsigned int count, unsigned int index)
{
    unsigned int i;

    for (i = 0u; i < count; i++) {
        if (target_indices[i] == index)
            return 1;
    }

    return 0;
}

static void generate_target_indices(void)
{
    unsigned int state = TARGET_POS_SEED;
    unsigned int count = 0u;

    while (count < MAX_TARGET_COUNT) {
        unsigned int index = xorshift32(&state) & (DATA_COUNT - 1u);

        if (!index_already_used(count, index)) {
            target_indices[count] = index;
            count++;
        }
    }
}

static unsigned int dataset_checksum(void)
{
    unsigned int h = 2166136261u;
    unsigned int i;

    for (i = 0u; i < DATA_WORD_COUNT; i++) {
        h ^= dataset_words[i];
        h *= 16777619u;
    }

    return h;
}

static int dma_load_dataset(void)
{
    unsigned int timeout = TIMEOUT;
    unsigned int dma_status;

    REG32(GROVER_CSR_BASE + CSR_DATA_ADDR) =
        (unsigned int)(uintptr_t)dataset_words;

    REG32(GROVER_CSR_BASE + CSR_DATA_COUNT) =
        DATA_COUNT;

    REG32(GROVER_CSR_BASE + CSR_DMA_COMMAND) = 1u;

    while (timeout--) {
        dma_status = REG32(GROVER_CSR_BASE + CSR_DMA_STATUS);

        if (dma_status & DMA_ERROR_BIT)
            break;

        if (dma_status & DMA_DONE_BIT)
            break;
    }

    dma_status = REG32(GROVER_CSR_BASE + CSR_DMA_STATUS);

    if ((dma_status & DMA_DONE_BIT) == 0u)
        return 0;

    if (dma_status & DMA_ERROR_BIT)
        return 0;

    return 1;
}

static void clear_result(run_result_t *r)
{
    unsigned int *p = (unsigned int *)r;
    unsigned int i;

    for (i = 0u; i < (sizeof(run_result_t) / sizeof(unsigned int)); i++)
        p[i] = 0u;
}

static void run_search(
    unsigned int mode,
    unsigned int seed_j,
    unsigned int seed_meas,
    run_result_t *r)
{
    unsigned int timeout = TIMEOUT;
    unsigned int status;
    unsigned int control;

    clear_result(r);
    r->mode = mode;

    control = (mode == MODE_K4H8) ?
        CONTROL_K4H8_EQ : CONTROL_NORMAL_EQ;

    REG32(GROVER_CSR_BASE + CSR_CONTROL) = control;
    REG32(GROVER_CSR_BASE + CSR_J_TARGET) = 0u;
    REG32(GROVER_CSR_BASE + CSR_THRESHOLD_A) = TARGET_VALUE;
    REG32(GROVER_CSR_BASE + CSR_THRESHOLD_B) = 0u;
    REG32(GROVER_CSR_BASE + CSR_DATA_COUNT) = DATA_COUNT;
    REG32(GROVER_CSR_BASE + CSR_SHOT_CAP) = SHOT_CAP;
    REG32(GROVER_CSR_BASE + CSR_SEED_J) = seed_j;
    REG32(GROVER_CSR_BASE + CSR_SEED_MEAS) = seed_meas;
    REG32(GROVER_CSR_BASE + CSR_ENUM_CFG) = 0u;

    REG32(GROVER_CSR_BASE + CSR_COMMAND) = 1u;

    while (timeout--) {
        status = REG32(GROVER_CSR_BASE + CSR_STATUS);

        if (status & STATUS_DONE_BIT)
            break;
    }

    status = REG32(GROVER_CSR_BASE + CSR_STATUS);
    r->status = status;

    if ((status & STATUS_DONE_BIT) == 0u) {
        r->timeout = 1u;
        return;
    }

    if (status & STATUS_UNEXPECTED_ERROR_MASK)
        r->unexpected_error = 1u;

    if (status & (STATUS_SHOT_LIMIT_BIT | STATUS_BUDGET_LIMIT_BIT))
        r->terminal_limit = 1u;

    r->result_valid =
        (status & STATUS_RESULT_VALID_BIT) ? 1u : 0u;

    r->result_index =
        REG32(GROVER_CSR_BASE + CSR_RESULT_INDEX);

    r->trial_count =
        REG32(GROVER_CSR_BASE + CSR_TRIAL_COUNT);

    r->l_bbht =
        REG32(GROVER_CSR_BASE + CSR_L_BBHT);

    r->actual_iter =
        REG32(GROVER_CSR_BASE + CSR_ACTUAL_ITER);

    r->cycle_count =
        REG32(GROVER_CSR_BASE + CSR_CYCLE_COUNT);

    r->policy_cycles =
        REG32(GROVER_CSR_BASE + CSR_POLICY_CYCLES);

    r->policy_stall =
        REG32(GROVER_CSR_BASE + CSR_POLICY_STALL);

    r->policy_actions =
        REG32(GROVER_CSR_BASE + CSR_POLICY_ACTIONS);

    r->policy_memo_hit =
        REG32(GROVER_CSR_BASE + CSR_POLICY_MEMO_HIT);

    r->policy_memo_miss =
        REG32(GROVER_CSR_BASE + CSR_POLICY_MEMO_MISS);

    r->policy_max_lat =
        REG32(GROVER_CSR_BASE + CSR_POLICY_MAX_LAT);

    r->plan_level =
        REG32(GROVER_CSR_BASE + CSR_PLAN_FIFO_LEVEL);

    r->plan_high =
        REG32(GROVER_CSR_BASE + CSR_PLAN_FIFO_HIGH);

    r->plan_empty =
        REG32(GROVER_CSR_BASE + CSR_PLAN_FIFO_EMPTY);

    r->plan_hit =
        REG32(GROVER_CSR_BASE + CSR_PLAN_FIFO_HIT);

    r->plan_mismatch =
        REG32(GROVER_CSR_BASE + CSR_PLAN_FIFO_MISMATCH);

    r->cold_solve =
        REG32(GROVER_CSR_BASE + CSR_POLICY_COLD_SOLVE);

    r->spec_solve =
        REG32(GROVER_CSR_BASE + CSR_POLICY_SPEC_SOLVE);

    if (r->result_valid &&
        r->result_index < DATA_COUNT &&
        get_data16(r->result_index) == (TARGET_VALUE & 0xFFFFu))
        r->result_is_target = 1u;
}

static unsigned int pair_is_consistent(
    const run_result_t *normal,
    const run_result_t *k4)
{
    if (normal->timeout || k4->timeout)
        return 0u;

    if (normal->unexpected_error || k4->unexpected_error)
        return 0u;

    if (normal->result_valid != k4->result_valid)
        return 0u;

    if (normal->trial_count != k4->trial_count)
        return 0u;

    if (normal->l_bbht != k4->l_bbht)
        return 0u;

    if (normal->result_valid) {
        if (!normal->result_is_target || !k4->result_is_target)
            return 0u;

        if (normal->result_index != k4->result_index)
            return 0u;
    }

    if (normal->actual_iter != normal->l_bbht)
        return 0u;

    if (k4->actual_iter > k4->l_bbht)
        return 0u;

    if (k4->plan_mismatch != 0u)
        return 0u;

    return 1u;
}

static unsigned int target_profile_count(void)
{
#if BENCH_INCLUDE_256
    return 5u;
#else
    return 4u;
#endif
}

int main()
{
    static const unsigned int target_counts[5] = {
        1u, 4u, 16u, 64u, 256u
    };

    unsigned int target_profile_n;
    unsigned int applied_targets = 0u;
    unsigned int ti;
    unsigned int si;
    unsigned int global_pair_fail = 0u;

    if (BENCH_SEED_COUNT == 0u ||
        BENCH_SEED_COUNT > 100u) {
        printf("CONFIG ERROR: BENCH_SEED_COUNT must be 1..100\n");
        return 1;
    }

    printf("============================================================\n");
    printf(" BBHT BOARD BENCHMARK : 50 SEEDS, NORMAL vs K4/H8\n");
    printf("============================================================\n");
    printf("DATA_COUNT=%u, TARGET_VALUE=%u\n", DATA_COUNT, TARGET_VALUE);
    printf("TARGETS=1/4/16/64/256, SEEDS=%u\n", BENCH_SEED_COUNT);
    printf("BACKGROUND_SEED=0x%08x, TARGET_POS_SEED=0x%08x\n",
           BACKGROUND_SEED, TARGET_POS_SEED);

    /*
     * One deterministic random background is used for every target-count
     * condition. Target sets are nested:
     * 1 subset 4 subset 16 subset 64 subset 256.
     */
    generate_background();
    generate_target_indices();

    target_profile_n = target_profile_count();

    for (ti = 0u; ti < target_profile_n; ti++) {
        unsigned int target_count = target_counts[ti];
        unsigned int pair_fail = 0u;
        unsigned int normal_success = 0u;
        unsigned int k4_success = 0u;
        unsigned int sum_normal_iter = 0u;
        unsigned int sum_k4_iter = 0u;
        unsigned int sum_normal_cycle = 0u;
        unsigned int sum_k4_cycle = 0u;
        unsigned int sum_k4_policy_stall = 0u;
        unsigned int sum_k4_plan_mismatch = 0u;

        while (applied_targets < target_count) {
            set_data16(
                target_indices[applied_targets],
                TARGET_VALUE);
            applied_targets++;
        }

        printf(
            "DATASET,target_count,%u,checksum,0x%08x,first_target,%u\n",
            target_count,
            dataset_checksum(),
            target_indices[0]);

        if (!dma_load_dataset()) {
            printf("DMA_FAIL,target_count,%u\n", target_count);
            return 1;
        }

        for (si = 0u; si < BENCH_SEED_COUNT; si++) {
            run_result_t normal;
            run_result_t k4;
            unsigned int consistent;

            /*
             * Paired order is deliberately NORMAL -> K4/H8.
             * The auto-checkpoint mode transition invalidates any previous
             * checkpoint state before K4/H8 starts, so each seed is an
             * independent paired run without changing RTL.
             */
            run_search(
                MODE_NORMAL,
                bbht_seed_roster[si].seed_j,
                bbht_seed_roster[si].seed_meas,
                &normal);

            run_search(
                MODE_K4H8,
                bbht_seed_roster[si].seed_j,
                bbht_seed_roster[si].seed_meas,
                &k4);

            consistent = pair_is_consistent(&normal, &k4);

            if (!consistent) {
                printf(
                    "PAIR_FAIL,target=%u,seed=%u,N_status=0x%08x,K4_status=0x%08x,"
                    "N_iter=%u,K4_iter=%u,N_cycle=%u,K4_cycle=%u\n",
                    target_count,
                    si,
                    normal.status,
                    k4.status,
                    normal.actual_iter,
                    k4.actual_iter,
                    normal.cycle_count,
                    k4.cycle_count);
            }

            if (!consistent) {
                pair_fail++;
                global_pair_fail++;
            }

            if (normal.result_valid && normal.result_is_target)
                normal_success++;

            if (k4.result_valid && k4.result_is_target)
                k4_success++;

            sum_normal_iter += normal.actual_iter;
            sum_k4_iter += k4.actual_iter;
            sum_normal_cycle += normal.cycle_count;
            sum_k4_cycle += k4.cycle_count;
            sum_k4_policy_stall += k4.policy_stall;
            sum_k4_plan_mismatch += k4.plan_mismatch;

            if (((si + 1u) % 10u) == 0u || (si + 1u) == BENCH_SEED_COUNT) {
                printf(
                    "PROGRESS,target=%u,seed=%u/%u,pair_fail=%u,mismatch=%u\n",
                    target_count,
                    si + 1u,
                    BENCH_SEED_COUNT,
                    pair_fail,
                    sum_k4_plan_mismatch);
            }
        }

        {
            unsigned int iter_red_x100 = 0u;
            unsigned int cycle_red_x100 = 0u;

            if (sum_normal_iter != 0u && sum_k4_iter <= sum_normal_iter) {
                iter_red_x100 =
                    (unsigned int)(
                        ((unsigned long long)(sum_normal_iter - sum_k4_iter) * 10000ull)
                        / sum_normal_iter);
            }

            if (sum_normal_cycle != 0u && sum_k4_cycle <= sum_normal_cycle) {
                cycle_red_x100 =
                    (unsigned int)(
                        ((unsigned long long)(sum_normal_cycle - sum_k4_cycle) * 10000ull)
                        / sum_normal_cycle);
            }

            printf("\nRESULT target=%u\n", target_count);
            printf("  pair_pass    = %u/%u\n",
                   BENCH_SEED_COUNT - pair_fail, BENCH_SEED_COUNT);
            printf("  success      = Normal %u/%u, K4/H8 %u/%u\n",
                   normal_success, BENCH_SEED_COUNT,
                   k4_success, BENCH_SEED_COUNT);
            printf("  physical_iter= Normal %u, K4/H8 %u, reduction %u.%02u%%\n",
                   sum_normal_iter, sum_k4_iter,
                   iter_red_x100 / 100u, iter_red_x100 % 100u);
            printf("  cycles       = Normal %u, K4/H8 %u, reduction %u.%02u%%\n",
                   sum_normal_cycle, sum_k4_cycle,
                   cycle_red_x100 / 100u, cycle_red_x100 % 100u);
            printf("  policy_stall = %u\n", sum_k4_policy_stall);
            printf("  plan_mismatch= %u\n", sum_k4_plan_mismatch);

            printf(
                "SUMMARY_CSV,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u\n",
                target_count,
                BENCH_SEED_COUNT,
                pair_fail,
                normal_success,
                k4_success,
                sum_normal_iter,
                sum_k4_iter,
                iter_red_x100,
                sum_normal_cycle,
                sum_k4_cycle,
                cycle_red_x100,
                sum_k4_policy_stall,
                sum_k4_plan_mismatch);
        }
    }

    if (global_pair_fail == 0u) {
        printf("BBHT PAPER BOARD BENCHMARK PASS\n");
        return 0;
    }

    printf("BBHT PAPER BOARD BENCHMARK FAIL,pair_fail,%u\n",
           global_pair_fail);
    return 1;
}
