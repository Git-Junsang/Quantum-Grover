/*
 * bbht_q14.h : Q14 BBHT/Grover software baselines for the ORCA core (RVX SoC).
 *
 * Three same-core baselines, all bit-exact with the RTL numeric contract
 * (same amplitudes, measurement thresholds, policy decisions and results as
 * the C++ RTL-exact model B and the FPGA board):
 *
 *   model 1  NAIVE       dense diffusion-matrix x vector (O(N^2) per iteration),
 *                        oracle as a diagonal matrix, linear row scan, Normal policy
 *   model 2  OPT + K3H3  one pass per iteration, sparse oracle, binary row search,
 *                        K3H3 checkpoint policy (same decisions as the RTL)
 *   model 3  OPT NORMAL  model 2 without the checkpoint policy
 *
 * Freestanding C99: no malloc, no floating point, no 64-bit printf.
 * Integer contract (frozen v0.9.8 hardware contract):
 *   N = 16384 amplitudes, signed Q1.22 (|a| <= 2^22 - 1, symmetric saturation),
 *   two_mean = round_half_even(global_sum / 2^13), a' = sat(two_mean - s*a),
 *   BBHT m0 = 1, lambda = 6/5, m_max = 128, logical budget 576, shot cap 100,
 *   j: 32-bit LFSR (pre-state word, then 7 steps per draw),
 *   measurement: xorshift64(13,7,17) blocks, seed {s, s ^ 0x9E3779B9}.
 */
#ifndef BBHT_Q14_H
#define BBHT_Q14_H

#include <stdint.h>
#include "baseline_config.h"

#define Q14_QBITS 14
#define Q14_N (1u << Q14_QBITS)                 /* 16384 */
#define Q14_P 32u                               /* lanes per row (RTL) */
#define Q14_ROWS (Q14_N / Q14_P)                /* 512 */
#define Q14_FRAC 22
#define Q14_AMP_MAX ((int32_t)((1 << 22) - 1))
#define Q14_AMP_MIN (-Q14_AMP_MAX)
#define Q14_INIT_AMP ((int32_t)1 << (Q14_FRAC - Q14_QBITS / 2))   /* 32768 = 2^-7 */
#define Q14_BUDGET 576u
#define Q14_SHOT_CAP 100u
#define Q14_MAX_TARGETS 256u
#define Q14_M_ROUNDS 28

/* Source version, printed in the UART log (SW_SOURCE) so a log names the code that made it. */
#define BBHT_SRC_VERSION "2026-10-10b"

enum { BBHT_TERM_SUCCESS = 0, BBHT_TERM_SHOT_LIMIT = 1, BBHT_TERM_BUDGET_LIMIT = 2 };
enum { BBHT_MODEL_NAIVE = 1, BBHT_MODEL_OPT_K3H3 = 2, BBHT_MODEL_OPT_NORMAL = 3 };

/* Target set of one dataset: sorted index list plus the same set as a bitset. */
typedef struct {
    const uint16_t *targets;
    uint32_t count;
    uint32_t bits[Q14_N / 32u];
} bbht_oracle_t;

typedef struct {
    uint32_t success;
    int32_t result_index;          /* -1 when the search did not succeed */
    uint32_t trial_count;
    uint32_t l_bbht;               /* sum of requested j */
    uint32_t physical_iterations;  /* Grover iterations actually computed */
    uint32_t termination;          /* BBHT_TERM_* */
    uint32_t saturations;          /* clamped amplitudes, all iterations */
} bbht_result_t;

/* One attempt (shot), reported through an optional hook for verification. */
typedef struct {
    int32_t requested_j;
    int32_t source_j;              /* state the iterations started from (0 = uniform) */
    int32_t physical;
    int64_t threshold;             /* integer CDF threshold (-1 if total weight is 0) */
    int32_t result_index;
    uint32_t success;
} bbht_attempt_t;

typedef void (*bbht_attempt_hook_t)(const bbht_attempt_t *attempt, void *ctx);

/* ---------------------------------------------------------------- random streams */
typedef struct { uint32_t state; } bbht_jrng_t;
typedef struct { uint64_t state; } bbht_mrng_t;

void bbht_jrng_init(bbht_jrng_t *r, uint32_t seed);
int bbht_jrng_uniform(bbht_jrng_t *r, int bound);
void bbht_mrng_init(bbht_mrng_t *r, uint32_t seed);
uint64_t bbht_mrng_block(bbht_mrng_t *r);
int bbht_m_bound(int round_index);

/* ------------------------------------------------------------------- arithmetic */
int64_t bbht_round_shift_ties_even(int64_t value, int shift);

static inline int32_t bbht_clamp(int32_t d)
{
    return d > Q14_AMP_MAX ? Q14_AMP_MAX : (d < Q14_AMP_MIN ? Q14_AMP_MIN : d);
}

/* ----------------------------------------------------------------------- oracle */
void bbht_oracle_init(bbht_oracle_t *o, const uint16_t *targets, uint32_t count);

static inline uint32_t bbht_is_target(const bbht_oracle_t *o, uint32_t index)
{
    return (o->bits[index >> 5] >> (index & 31u)) & 1u;
}

/* ------------------------------------------------------------------------ cores */
/* State = amplitudes a[N] plus osum, the oracle-signed amplitude sum
 * sum_i s_i*a_i that the next iteration needs (the RTL global_sum).        */
void bbht_state_reset(int32_t *a, int64_t *osum, const bbht_oracle_t *o);

/* Optimized core: one pass over a[], sparse oracle fix-up, in place.       */
void bbht_core_opt_iterate(int32_t *a, int64_t *osum, const bbht_oracle_t *o, uint32_t *saturations);

#if BBHT_ENABLE_NAIVE
/* Naive core: v = O*a (diagonal oracle), then a = sat(D*v) with the dense
 * diffusion matrix D = (2/N)J - I, every row computed as a full dot product.
 * global_sum_out receives the sum the RTL would have used (for tracing).   */
void bbht_core_naive_iterate(int32_t *a, const bbht_oracle_t *o, int64_t *global_sum_out,
                             uint32_t *saturations);
#endif

/* ------------------------------------------------------------------ measurement */
typedef struct {
    int64_t row_cdf[Q14_ROWS];
    int64_t total;
} bbht_cdf_t;

/* A state is read row by row (32 amplitudes); fetch returns a pointer to the row,
 * either into the state itself or into tmp after decoding (packed checkpoints). */
typedef const int32_t *(*bbht_row_fetch_t)(const void *src, uint32_t row, int32_t *tmp);
const int32_t *bbht_row_from_array(const void *src, uint32_t row, int32_t *tmp);
const int32_t *bbht_row_uniform(const void *src, uint32_t row, int32_t *tmp);   /* the j = 0 state */

void bbht_cdf_prepare_rows(bbht_row_fetch_t fetch, const void *src, bbht_cdf_t *c);
/* CDF of the uniform state in closed form (every row weighs 32 * 32768^2 = 2^35):
 * the same table bbht_cdf_prepare_rows builds from the amplitudes, without the pass. */
void bbht_cdf_prepare_uniform(bbht_cdf_t *c);
/* row_search: 0 = linear scan over rows (naive), 1 = binary search (optimized). */
int32_t bbht_sample_rows(bbht_row_fetch_t fetch, const void *src, const bbht_cdf_t *c, bbht_mrng_t *rng,
                         int64_t *threshold, int row_search);

static inline void bbht_cdf_prepare(const int32_t *a, bbht_cdf_t *c)
{
    bbht_cdf_prepare_rows(bbht_row_from_array, a, c);
}
static inline int32_t bbht_sample(const int32_t *a, const bbht_cdf_t *c, bbht_mrng_t *rng, int64_t *threshold,
                                  int row_search)
{
    return bbht_sample_rows(bbht_row_from_array, a, c, rng, threshold, row_search);
}

/* ----------------------------------------------------------------------- policy */
#if BBHT_ENABLE_K3H3
void bbht_k3h3_invalidate(void);
/* Exact hit: 1 when the state at `requested` is already kept. It is then measured as
 * stored: no policy decision, no future-j prediction, no iterations (the policy
 * result would be discarded on a hit, so skipping it changes nothing).          */
int bbht_k3h3_lookup(int requested);
/* Miss: policy decision, then brings the state at `requested` up to date; returns
 * the physical iterations. Call only after bbht_k3h3_lookup() returned 0.      */
int bbht_k3h3_execute(int requested, const int *future, int nfuture, int32_t *work, int64_t *work_osum,
                      const bbht_oracle_t *o, int *source_out, uint32_t *saturations);
/* After lookup/execute: the state to measure (work buffer, packed checkpoint or
 * the uniform state) and its CDF. The CDF is kept with the checkpoint, so a state
 * measured again is not re-weighed (the measurement random draw is still new).  */
void bbht_k3h3_view(bbht_row_fetch_t *fetch, const void **src);
const bbht_cdf_t *bbht_k3h3_cdf(void);
#endif

/* ----------------------------------------------------------------------- search */
void bbht_search(int model, const bbht_oracle_t *o, uint32_t seed_j, uint32_t seed_meas,
                 bbht_result_t *out, bbht_attempt_hook_t hook, void *hook_ctx);

/* Work buffer shared by every model (the state being iterated / measured). */
extern int32_t bbht_work[Q14_N];

#endif
