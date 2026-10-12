/*
 * bbht_naive.c : model 1, the naive baseline (Choi & Lee 2024 "sw_naive" counterpart).
 *
 * Grover iteration written as matrix x vector products, without our techniques:
 *   1. oracle  : v = O a, O = diag(s), s_i = -1 on targets      (diagonal matrix)
 *   2. diffuse : a = D v, D = (2/N) J - I                        (dense N x N matrix)
 * Every row i of D is computed as a full dot product over all N columns, so one
 * iteration costs N^2 = 2.7e8 multiply-accumulates (the O(N) "2*mean - a" form is
 * one of the optimizations the hardware and model 2/3 use).
 *
 * Fixed point follows the hardware contract so that results stay bit-exact:
 * the (2/N) J part of row i is accumulated exactly in int64 (matrix element 2/N is
 * kept as the integer 2 with the scale N = 2^14 folded into the final shift), rounded
 * half-to-even once, and the -I part is applied exactly before the symmetric
 * saturation. The matrix cannot be stored (16384^2 entries), so its elements are
 * generated on the fly.
 */
#include "bbht_q14.h"

#if BBHT_ENABLE_NAIVE

#define DJ_SCALED 2   /* element of (2/N) J, times N */

static int32_t g_v[Q14_N];   /* oracle-applied vector (the dense product needs the whole input) */

void bbht_core_naive_iterate(int32_t *a, const bbht_oracle_t *o, int64_t *global_sum_out,
                             uint32_t *saturations)
{
    uint32_t i, j, sat = 0;

    for (i = 0; i < Q14_N; ++i)                                /* v = O a */
        g_v[i] = bbht_is_target(o, i) ? -a[i] : a[i];

    for (i = 0; i < Q14_N; ++i) {                              /* a = D v, row by row */
        int64_t acc = 0;
        int32_t two_mean, d, c;
        /* Each row is an independent dot product: keep the compiler from reusing the
         * previous row's sum (the matrix rows happen to share their off-diagonal part). */
        __asm__ __volatile__("" ::: "memory");
        for (j = 0; j < Q14_N; ++j)
            acc += (int64_t)DJ_SCALED * g_v[j];
        if (i == 0 && global_sum_out)
            *global_sum_out = acc / DJ_SCALED;                 /* the RTL global_sum */
        two_mean = (int32_t)bbht_round_shift_ties_even(acc, Q14_QBITS);   /* (2/N) J v, rounded */
        d = two_mean - g_v[i];                                 /* - I v */
        c = bbht_clamp(d);
        sat += (uint32_t)(c != d);
        a[i] = c;
    }
    *saturations += sat;
}

#endif
