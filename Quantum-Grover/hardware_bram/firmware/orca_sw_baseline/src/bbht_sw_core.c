#include "bbht_sw_core.h"

/*
 * Pure-software Q14 BBHT/Grover emulator baseline.
 *
 * Contract intentionally matches the frozen/current hardware-visible search
 * semantics rather than the checkpoint implementation:
 *   - Q14, N=16384
 *   - signed Q1.22 amplitudes stored in int32_t
 *   - BBHT m0=1, lambda=6/5, m_max=128, logical budget=576
 *   - J LFSR: pre-state word, then 7 ordinary LFSR steps per draw
 *   - measurement PRNG: current 64-bit block first, then xorshift64(13,7,17)
 *     with seed expansion {seed, seed ^ 0x9E3779B9}
 *   - oracle/diffusion/round-to-nearest-ties-even/symmetric saturation
 *
 * For the paper EQ(12345) benchmark the background generator excludes 12345,
 * so the Oracle is fully determined by the target-position bitset.  We retain
 * the exact target-position generator and avoid storing the unused background
 * values; this saves SRAM without changing the Oracle for this workload.
 */

#define TARGET_WORDS (BBHT_SW_N / 32u)
#define INITIAL_AMP (1 << (BBHT_SW_FRAC_BITS - BBHT_SW_Q_BITS / 2u))
#define J_FALLBACK 0xACE12345u
#define MEAS_FALLBACK 0xBEEFC0DEu
#define MEAS_MIX 0x9E3779B9u

static int32_t g_amp[BBHT_SW_N];
static uint32_t g_target_bits[TARGET_WORDS];
static uint16_t g_target_indices[BBHT_SW_MAX_TARGETS];

static const uint8_t g_m_bounds[28] = {
    1,2,2,2,3,3,3,4,5,6,7,8,9,11,13,16,19,23,27,32,39,47,56,67,80,96,115,128
};

static uint32_t xorshift32_dataset(uint32_t *state)
{
    uint32_t x = *state;
    if (x == 0u)
        x = 0x6D2B79F5u;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    return x;
}

static int target_index_used(uint32_t count, uint32_t index)
{
    uint32_t i;
    for (i = 0; i < count; ++i) {
        if ((uint32_t)g_target_indices[i] == index)
            return 1;
    }
    return 0;
}

void bbht_sw_prepare_target_mask(uint32_t target_count)
{
    uint32_t i;
    uint32_t state = BBHT_SW_TARGET_POS_SEED;
    uint32_t count = 0;

    for (i = 0; i < TARGET_WORDS; ++i)
        g_target_bits[i] = 0u;

    while (count < BBHT_SW_MAX_TARGETS) {
        uint32_t index = xorshift32_dataset(&state) & (BBHT_SW_N - 1u);
        if (!target_index_used(count, index)) {
            g_target_indices[count] = (uint16_t)index;
            ++count;
        }
    }

    if (target_count > BBHT_SW_MAX_TARGETS)
        target_count = BBHT_SW_MAX_TARGETS;
    for (i = 0; i < target_count; ++i) {
        uint32_t index = (uint32_t)g_target_indices[i];
        g_target_bits[index >> 5] |= (1u << (index & 31u));
    }
}

int bbht_sw_is_target(uint32_t index)
{
    return (int)((g_target_bits[index >> 5] >> (index & 31u)) & 1u);
}

static uint32_t lfsr_step(uint32_t value)
{
    uint32_t fb = ((value >> 31) ^ (value >> 21) ^ (value >> 1) ^ value) & 1u;
    return (value << 1) | fb;
}

typedef struct { uint32_t state; } j_rng_t;

static void j_rng_init(j_rng_t *r, uint32_t seed)
{
    r->state = seed ? seed : J_FALLBACK;
}

static uint32_t j_draw_word(j_rng_t *r)
{
    uint32_t value = r->state;
    unsigned i;
    for (i = 0; i < 7u; ++i)
        r->state = lfsr_step(r->state);
    return value;
}

static uint32_t ceil_log2_u32(uint32_t x)
{
    uint32_t bits = 0;
    uint32_t v = x - 1u;
    while (v) {
        ++bits;
        v >>= 1;
    }
    return bits;
}

static uint32_t draw_uniform_j(j_rng_t *r, uint32_t bound)
{
    uint32_t bits = ceil_log2_u32(bound);
    uint32_t mask = bits ? ((1u << bits) - 1u) : 0u;
    for (;;) {
        uint32_t candidate = (j_draw_word(r) & 0xFFu) & mask;
        if (candidate < bound)
            return candidate;
    }
}

typedef struct { uint64_t state; } meas_rng_t;

static void meas_rng_init(meas_rng_t *r, uint32_t seed)
{
    uint32_t effective = seed ? seed : MEAS_FALLBACK;
    r->state = ((uint64_t)effective << 32) | (uint64_t)(effective ^ MEAS_MIX);
}

static uint64_t meas_draw_block(meas_rng_t *r)
{
    uint64_t block = r->state;
    uint64_t x = block;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    r->state = x;
    return block;
}

static unsigned bit_length_u64(uint64_t v)
{
    unsigned n = 0;
    while (v) {
        ++n;
        v >>= 1;
    }
    return n;
}

static int64_t round_shift_ties_even(int64_t value, unsigned shift)
{
    uint64_t den = ((uint64_t)1u << shift);
    int64_t q;
    uint64_t rem;

    if (shift == 0u)
        return value;

    if (value >= 0) {
        q = value >> shift;
        rem = (uint64_t)value & (den - 1u);
    } else {
        uint64_t a = (uint64_t)(-value);
        uint64_t ceilq = (a + den - 1u) >> shift;
        q = -(int64_t)ceilq;
        rem = (uint64_t)(value - q * (int64_t)den);
    }

    if ((rem << 1) > den || (((rem << 1) == den) && (q & 1)))
        ++q;
    return q;
}

static uint32_t run_grover(uint32_t iterations)
{
    uint32_t i, it;
    uint32_t saturations = 0;

    for (i = 0; i < BBHT_SW_N; ++i)
        g_amp[i] = INITIAL_AMP;

    for (it = 0; it < iterations; ++it) {
        int64_t sum = 0;
        int64_t two_mean;

        for (i = 0; i < BBHT_SW_N; ++i) {
            int32_t a = g_amp[i];
            if (bbht_sw_is_target(i))
                a = -a;
            g_amp[i] = a;
            sum += (int64_t)a;
        }

        two_mean = round_shift_ties_even(sum, BBHT_SW_Q_BITS - 1u);

        for (i = 0; i < BBHT_SW_N; ++i) {
            int64_t d = two_mean - (int64_t)g_amp[i];
            if (d > BBHT_SW_AMP_MAX) {
                d = BBHT_SW_AMP_MAX;
                ++saturations;
            } else if (d < BBHT_SW_AMP_MIN) {
                d = BBHT_SW_AMP_MIN;
                ++saturations;
            }
            g_amp[i] = (int32_t)d;
        }
    }
    return saturations;
}

static uint32_t measure_state(meas_rng_t *rng)
{
    uint32_t i;
    uint64_t total = 0;
    uint64_t threshold;
    uint64_t cdf = 0;

    for (i = 0; i < BBHT_SW_N; ++i) {
        int64_t a = (int64_t)g_amp[i];
        total += (uint64_t)(a * a);
    }

    if (total == 0u)
        return 0u;

    if (total == 1u) {
        threshold = 0u;
    } else {
        unsigned width = bit_length_u64(total - 1u);
        uint64_t mask = (((uint64_t)1u << width) - 1u);
        for (;;) {
            uint64_t candidate = meas_draw_block(rng) & mask;
            if (candidate < total) {
                threshold = candidate;
                break;
            }
        }
    }

    for (i = 0; i < BBHT_SW_N; ++i) {
        int64_t a = (int64_t)g_amp[i];
        cdf += (uint64_t)(a * a);
        if (cdf > threshold)
            return i;
    }
    return BBHT_SW_N - 1u;
}

void bbht_sw_run(uint32_t seed_j, uint32_t seed_meas, bbht_sw_result_t *out)
{
    j_rng_t jrng;
    meas_rng_t mrng;
    uint32_t round_idx = 0;
    uint32_t trial = 0;
    uint32_t l_bbht = 0;
    uint32_t sat_total = 0;

    out->success = 0;
    out->result_index = 0;
    out->trial_count = 0;
    out->l_bbht = 0;
    out->grover_iterations = 0;
    out->termination = 1;
    out->saturation_count = 0;

    j_rng_init(&jrng, seed_j);
    meas_rng_init(&mrng, seed_meas);

    for (;;) {
        uint32_t bound = g_m_bounds[round_idx < 28u ? round_idx : 27u];
        uint32_t j = draw_uniform_j(&jrng, bound);
        uint32_t index;

        l_bbht += j;
        sat_total += run_grover(j);
        index = measure_state(&mrng);
        ++trial;

        if (bbht_sw_is_target(index)) {
            out->success = 1;
            out->result_index = index;
            out->termination = 0;
            break;
        }
        if (trial >= BBHT_SW_SHOT_CAP) {
            out->termination = 1;
            break;
        }
        if (l_bbht + 1u >= BBHT_SW_LOGICAL_BUDGET) {
            out->termination = 2;
            break;
        }
        if (round_idx < 27u)
            ++round_idx;
    }

    out->trial_count = trial;
    out->l_bbht = l_bbht;
    out->grover_iterations = l_bbht; /* pure-SW Normal has no checkpoint reuse */
    out->saturation_count = sat_total;
}
