#ifndef BBHT_BASELINE_CONFIG_H
#define BBHT_BASELINE_CONFIG_H

/*
 * Build configuration of the ORCA same-core baselines.
 * tools/make_rvx_apps.sh writes one app per model by changing BBHT_MODEL only.
 *
 * BBHT_MODEL
 *   1  NAIVE       dense matrix x vector, Normal          SRAM >= 256 KB (two state buffers)
 *   2  OPT + K3H3  one pass + checkpoint policy           SRAM >= 256 KB (work + 2 packed checkpoints + 3 CDFs)
 *   3  OPT NORMAL  one pass, no policy                    fits the current 128 KB SRAM
 */
#ifndef BBHT_MODEL
#define BBHT_MODEL 3
#endif

/*
 * BBHT_PROFILE
 *   0  SMOKE      Predicate500 EQ, M=256, seed 0 only, checked against the expected result
 *   1  FULL       Predicate500: 4 predicates x M {1,4,16,64,256} x seeds [0, BBHT_SEED_COUNT)
 *   2  CALIBRATE  times BBHT_CALIB_ITERS Grover iterations and one measurement on
 *                 Predicate500 EQ M=1 (use with model 1: the full naive campaign is
 *                 estimated from these per-iteration costs, see README)
 *   3  SUBSET     like FULL but only BBHT_SUBSET_PRED_MASK / _M_MASK / seeds
 *                 [BBHT_SUBSET_SEED_FIRST, BBHT_SUBSET_SEED_END)
 */
#ifndef BBHT_PROFILE
#define BBHT_PROFILE 0
#endif

#ifndef BBHT_SEED_COUNT
#define BBHT_SEED_COUNT 100u            /* FULL: 1..100 */
#endif
#ifndef BBHT_CALIB_ITERS
#define BBHT_CALIB_ITERS 2u             /* CALIBRATE: iterations timed (naive: minutes each) */
#endif
#ifndef BBHT_SUBSET_PRED_MASK
#define BBHT_SUBSET_PRED_MASK 0xFu      /* bit0 LT, bit1 GT, bit2 EQ, bit3 RANGE */
#endif
#ifndef BBHT_SUBSET_M_MASK
#define BBHT_SUBSET_M_MASK 0x10u        /* bit0 M=1, bit1 M=4, bit2 M=16, bit3 M=64, bit4 M=256 */
#endif
#ifndef BBHT_SUBSET_SEED_FIRST
#define BBHT_SUBSET_SEED_FIRST 0u
#endif
#ifndef BBHT_SUBSET_SEED_END
#define BBHT_SUBSET_SEED_END 1u
#endif

/* Which code and buffers are compiled in (only what the model needs, to fit SRAM). */
#ifndef BBHT_ENABLE_NAIVE
#define BBHT_ENABLE_NAIVE (BBHT_MODEL == 1)
#endif
#ifndef BBHT_ENABLE_K3H3
#define BBHT_ENABLE_K3H3 (BBHT_MODEL == 2)
#endif

#endif
