/*
 * bbht_core.c : random streams, rounding, oracle, the optimized Grover core and
 * the measurement (shared by every model).
 */
#include "bbht_q14.h"

int32_t bbht_work[Q14_N];

/* ----------------------------------------------------------- random streams */
#define J_FALLBACK_SEED 0xACE12345u
#define MEAS_FALLBACK_SEED 0xBEEFC0DEu
#define MEAS_SEED_MIX 0x9E3779B9u

static const uint8_t g_m_bounds[Q14_M_ROUNDS] = {
    1, 2, 2, 2, 3, 3, 3, 4, 5, 6, 7, 8, 9, 11, 13, 16, 19, 23, 27, 32,
    39, 47, 56, 67, 80, 96, 115, 128
};

int bbht_m_bound(int round_index)
{
    if (round_index > Q14_M_ROUNDS - 1)
        round_index = Q14_M_ROUNDS - 1;
    return g_m_bounds[round_index];
}

static int bit_length64(uint64_t v)
{
    int n = 0;
    while (v) {
        ++n;
        v >>= 1;
    }
    return n;
}

static uint32_t lfsr_step(uint32_t v)
{
    uint32_t fb = ((v >> 31) ^ (v >> 21) ^ (v >> 1) ^ v) & 1u;
    return (v << 1) | fb;
}

void bbht_jrng_init(bbht_jrng_t *r, uint32_t seed)
{
    r->state = seed ? seed : J_FALLBACK_SEED;
}

/* Pre-state word, then 7 LFSR steps per draw; low byte & mask, reject >= bound. */
int bbht_jrng_uniform(bbht_jrng_t *r, int bound)
{
    int bits = bit_length64((uint64_t)(bound - 1));
    uint32_t mask = bits ? ((1u << bits) - 1u) : 0u;
    for (;;) {
        uint32_t word = r->state;
        int i;
        for (i = 0; i < 7; ++i)
            r->state = lfsr_step(r->state);
        {
            uint32_t c = (word & 0xFFu) & mask;
            if ((int)c < bound)
                return (int)c;
        }
    }
}

void bbht_mrng_init(bbht_mrng_t *r, uint32_t seed)
{
    uint64_t e = seed ? seed : MEAS_FALLBACK_SEED;
    r->state = (e << 32) | (e ^ MEAS_SEED_MIX);
}

/* Current 64-bit block first, then xorshift64(13, 7, 17). */
uint64_t bbht_mrng_block(bbht_mrng_t *r)
{
    uint64_t block = r->state, v = r->state;
    v ^= v << 13;
    v ^= v >> 7;
    v ^= v << 17;
    r->state = v;
    return block;
}

/* --------------------------------------------------------------- arithmetic */
/* round(value / 2^shift), ties to even, in one step (as the RTL two_mean). */
int64_t bbht_round_shift_ties_even(int64_t value, int shift)
{
    const int64_t den = (int64_t)1 << shift;
    int64_t q = value >> shift;                 /* arithmetic shift = floor (GCC, Clang) */
    int64_t r = value - q * den;                /* 0 <= r < den */
    int64_t doubled = r * 2;
    if (doubled > den || (doubled == den && (q & 1)))
        ++q;
    return q;
}

/* ------------------------------------------------------------------- oracle */
void bbht_oracle_init(bbht_oracle_t *o, const uint16_t *targets, uint32_t count)
{
    uint32_t i;
    o->targets = targets;
    o->count = count;
    for (i = 0; i < Q14_N / 32u; ++i)
        o->bits[i] = 0u;
    for (i = 0; i < count; ++i)
        o->bits[targets[i] >> 5] |= 1u << (targets[i] & 31u);
}

/* Uniform superposition 2^-7 and its oracle-signed sum (N - 2M) * 2^-7. */
void bbht_state_reset(int32_t *a, int64_t *osum, const bbht_oracle_t *o)
{
    uint32_t i;
    for (i = 0; i < Q14_N; ++i)
        a[i] = Q14_INIT_AMP;
    *osum = ((int64_t)Q14_N - 2 * (int64_t)o->count) * Q14_INIT_AMP;
}

/* ----------------------------------------------------------- optimized core */
/*
 * One Grover iteration in a single pass over a[]:
 *   two_mean = round_half_even(osum / 2^13)            (osum carried from the previous pass)
 *   a_i'     = sat(two_mean - s_i * a_i)                (oracle sign s and diffusion together)
 *   osum'    = sum_i s_i * a_i'                         (accumulated while writing a_i')
 * The oracle is sparse (M <= 256 targets): the main loop treats every element as a
 * non-target (s = +1, no sign test, no multiply) and the targets are fixed up before
 * and after it. Partial sums of 256 elements fit int32 (256 * 2^22 < 2^31), so the
 * 64-bit adds that rv32 splits into several instructions happen once per block.
 */
#define OPT_BLOCK 256u
static int32_t g_target_new[Q14_MAX_TARGETS];

void bbht_core_opt_iterate(int32_t *a, int64_t *osum, const bbht_oracle_t *o, uint32_t *saturations)
{
    const int32_t two_mean = (int32_t)bbht_round_shift_ties_even(*osum, Q14_QBITS - 1);
    int64_t corr_sum = 0, acc = 0;
    int32_t corr_sat = 0;
    uint32_t sat = 0, k, b;

    /* targets: correct value (s = -1) and the value the main loop will write (s = +1) */
    for (k = 0; k < o->count; ++k) {
        int32_t at = a[o->targets[k]];
        int32_t d_ok = two_mean + at, c_ok = bbht_clamp(d_ok);
        int32_t d_wr = two_mean - at, c_wr = bbht_clamp(d_wr);
        g_target_new[k] = c_ok;
        corr_sum += (int64_t)(-c_ok) - c_wr;
        corr_sat += (int32_t)(c_ok != d_ok) - (int32_t)(c_wr != d_wr);
    }
    /* every element as a non-target */
    for (b = 0; b < Q14_N; b += OPT_BLOCK) {
        int32_t *p = a + b;
        int32_t block_sum = 0;
        uint32_t i;
        for (i = 0; i < OPT_BLOCK; ++i) {
            int32_t d = two_mean - p[i];
            int32_t c = bbht_clamp(d);
            sat += (uint32_t)(c != d);
            p[i] = c;
            block_sum += c;
        }
        acc += block_sum;
    }
    for (k = 0; k < o->count; ++k)
        a[o->targets[k]] = g_target_new[k];
    *osum = acc + corr_sum;
    *saturations += (uint32_t)((int32_t)sat + corr_sat);
}

/* -------------------------------------------------------------- measurement */
const int32_t *bbht_row_from_array(const void *src, uint32_t row, int32_t *tmp)
{
    (void)tmp;
    return (const int32_t *)src + row * Q14_P;
}

const int32_t *bbht_row_uniform(const void *src, uint32_t row, int32_t *tmp)
{
    uint32_t l;
    (void)src;
    (void)row;
    for (l = 0; l < Q14_P; ++l)
        tmp[l] = Q14_INIT_AMP;
    return tmp;
}

void bbht_cdf_prepare_uniform(bbht_cdf_t *c)
{
    const int64_t w = (int64_t)Q14_P * Q14_INIT_AMP * Q14_INIT_AMP;   /* 2^35 */
    uint32_t r;
    for (r = 0; r < Q14_ROWS; ++r)
        c->row_cdf[r] = (int64_t)(r + 1u) * w;
    c->total = (int64_t)Q14_ROWS * w;                                  /* 2^44 */
}

/* Row weights sum |a|^2 over the 32 lanes of each of the 512 rows (exact, int64). */
void bbht_cdf_prepare_rows(bbht_row_fetch_t fetch, const void *src, bbht_cdf_t *c)
{
    int32_t tmp[Q14_P];
    int64_t run = 0;
    uint32_t r;
    for (r = 0; r < Q14_ROWS; ++r) {
        const int32_t *p = fetch(src, r, tmp);
        int64_t w = 0;
        uint32_t l;
        for (l = 0; l < Q14_P; ++l)
            w += (int64_t)p[l] * p[l];
        run += w;
        c->row_cdf[r] = run;
    }
    c->total = run;
}

/*
 * measure_v098_state: threshold = low bit_length(total-1) bits of a 64-bit block,
 * redrawn while >= total (no draw when total == 1); then the FIRST row whose
 * cumulative weight > threshold and the FIRST lane whose cumulative weight >
 * the remaining threshold.
 */
int32_t bbht_sample_rows(bbht_row_fetch_t fetch, const void *src, const bbht_cdf_t *c, bbht_mrng_t *rng,
                         int64_t *threshold, int row_search)
{
    int32_t tmp[Q14_P];
    uint64_t total, thr = 0;
    uint32_t row, l;
    int64_t before, local, cum;
    const int32_t *p;

    if (c->total == 0) {
        *threshold = -1;
        return -1;
    }
    total = (uint64_t)c->total;
    if (total > 1) {
        int width = bit_length64(total - 1);
        uint64_t mask = width >= 64 ? ~(uint64_t)0 : (((uint64_t)1 << width) - 1);
        for (;;) {
            uint64_t cand = bbht_mrng_block(rng) & mask;
            if (cand < total) {
                thr = cand;
                break;
            }
        }
    }
    *threshold = (int64_t)thr;

    if (row_search) {                       /* binary search: first row_cdf > thr */
        uint32_t lo = 0, hi = Q14_ROWS;
        while (lo < hi) {
            uint32_t mid = (lo + hi) >> 1;
            if (c->row_cdf[mid] > (int64_t)thr)
                hi = mid;
            else
                lo = mid + 1;
        }
        row = lo;
    } else {                                /* linear scan, as written in the contract */
        row = 0;
        while (row < Q14_ROWS - 1 && !(c->row_cdf[row] > (int64_t)thr))
            ++row;
    }
    before = row ? c->row_cdf[row - 1] : 0;
    local = (int64_t)thr - before;
    p = fetch(src, row, tmp);
    cum = 0;
    for (l = 0; l < Q14_P; ++l) {
        cum += (int64_t)p[l] * p[l];
        if (cum > local)
            return (int32_t)(row * Q14_P + l);
    }
    return (int32_t)(row * Q14_P + Q14_P - 1);
}
