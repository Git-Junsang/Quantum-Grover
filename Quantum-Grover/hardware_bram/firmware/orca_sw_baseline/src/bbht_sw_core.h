#ifndef BBHT_SW_CORE_H
#define BBHT_SW_CORE_H

#include <stdint.h>

#define BBHT_SW_Q_BITS 14u
#define BBHT_SW_N (1u << BBHT_SW_Q_BITS)
#define BBHT_SW_FRAC_BITS 22u
#define BBHT_SW_AMP_MAX ((1 << 22) - 1)
#define BBHT_SW_AMP_MIN (-BBHT_SW_AMP_MAX)
#define BBHT_SW_SHOT_CAP 100u
#define BBHT_SW_LOGICAL_BUDGET 576u
#define BBHT_SW_MAX_TARGETS 256u
#define BBHT_SW_TARGET_VALUE 12345u
#define BBHT_SW_TARGET_POS_SEED 0xA17E2026u

typedef struct {
    uint32_t success;
    uint32_t result_index;
    uint32_t trial_count;
    uint32_t l_bbht;
    uint32_t grover_iterations;
    uint32_t termination; /* 0 success, 1 shot limit, 2 budget limit */
    uint32_t saturation_count;
} bbht_sw_result_t;

void bbht_sw_prepare_target_mask(uint32_t target_count);
int bbht_sw_is_target(uint32_t index);
void bbht_sw_run(uint32_t seed_j, uint32_t seed_meas, bbht_sw_result_t *out);

#endif
