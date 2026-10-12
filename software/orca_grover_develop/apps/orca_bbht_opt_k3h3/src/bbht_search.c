/*
 * bbht_search.c : the BBHT search loop (V098AutomaticCore._run_episode order),
 * shared by the three models.
 *
 *   j draw -> state at j (Normal: from uniform; K3H3: checkpoint policy) ->
 *   measurement -> stop rules: SUCCESS, then shot cap 100, then L + 1 >= 576.
 *
 * Work skipped without changing any result:
 * - model 3, j = 0: the uniform state is measured directly (no reset, CDF in closed form);
 * - model 2, exact hit: the kept state is measured as is (no prediction, no policy);
 * - model 2: a kept state's CDF is reused when it is measured again.
 * Model 1 keeps the plain flow (reset, iterate, full CDF pass, linear row scan).
 */
#include "bbht_q14.h"

static bbht_cdf_t g_cdf;

#if BBHT_ENABLE_K3H3
/* Future requests seen by the RTL shadow-J generator: a copy of the j stream,
 * assuming every following attempt fails. */
static int predict_future_j(const bbht_jrng_t *src, int next_round, int *out, int count)
{
    bbht_jrng_t clone = *src;
    int i, r = next_round;
    for (i = 0; i < count; ++i) {
        out[i] = bbht_jrng_uniform(&clone, bbht_m_bound(r));
        if (r < Q14_M_ROUNDS - 1)
            ++r;
    }
    return count;
}
#endif

void bbht_search(int model, const bbht_oracle_t *o, uint32_t seed_j, uint32_t seed_meas,
                 bbht_result_t *out, bbht_attempt_hook_t hook, void *hook_ctx)
{
    bbht_jrng_t js;
    bbht_mrng_t ms;
    int round = 0;
    uint32_t episode_l = 0;
    int64_t osum = 0;

    bbht_jrng_init(&js, seed_j);
    bbht_mrng_init(&ms, seed_meas);
    out->success = 0;
    out->result_index = -1;
    out->trial_count = 0;
    out->l_bbht = 0;
    out->physical_iterations = 0;
    out->termination = BBHT_TERM_SHOT_LIMIT;
    out->saturations = 0;
#if BBHT_ENABLE_K3H3
    if (model == BBHT_MODEL_OPT_K3H3)
        bbht_k3h3_invalidate();
#endif

    for (;;) {
        bbht_attempt_t at;
        int requested = bbht_jrng_uniform(&js, bbht_m_bound(round));
        int physical = requested, source = 0, k;
        bbht_row_fetch_t fetch = bbht_row_from_array;   /* the state to measure */
        const void *src = bbht_work;
        const bbht_cdf_t *cdf = &g_cdf;

        if (model == BBHT_MODEL_OPT_NORMAL) {
            if (requested == 0) {                        /* the uniform state itself */
                fetch = bbht_row_uniform;
                src = 0;
                bbht_cdf_prepare_uniform(&g_cdf);
            } else {
                bbht_state_reset(bbht_work, &osum, o);
                for (k = 0; k < requested; ++k)
                    bbht_core_opt_iterate(bbht_work, &osum, o, &out->saturations);
                bbht_cdf_prepare_rows(fetch, src, &g_cdf);
            }
        }
#if BBHT_ENABLE_NAIVE
        else if (model == BBHT_MODEL_NAIVE) {
            bbht_state_reset(bbht_work, &osum, o);
            for (k = 0; k < requested; ++k)
                bbht_core_naive_iterate(bbht_work, o, 0, &out->saturations);
            bbht_cdf_prepare_rows(fetch, src, &g_cdf);
        }
#endif
#if BBHT_ENABLE_K3H3
        else if (model == BBHT_MODEL_OPT_K3H3) {
            if (bbht_k3h3_lookup(requested)) {          /* exact hit */
                physical = 0;
                source = requested;
            } else {
                int future[3];
                predict_future_j(&js, round + 1, future, 3);
                physical = bbht_k3h3_execute(requested, future, 3, bbht_work, &osum, o, &source,
                                             &out->saturations);
            }
            bbht_k3h3_view(&fetch, &src);
            cdf = bbht_k3h3_cdf();
        }
#endif

        at.result_index = bbht_sample_rows(fetch, src, cdf, &ms, &at.threshold, model != BBHT_MODEL_NAIVE);
        at.success = at.result_index >= 0 && bbht_is_target(o, (uint32_t)at.result_index);
        at.requested_j = requested;
        at.source_j = source;
        at.physical = physical;

        episode_l += (uint32_t)requested;
        out->l_bbht += (uint32_t)requested;
        out->physical_iterations += (uint32_t)physical;
        out->trial_count += 1;
        if (hook)
            hook(&at, hook_ctx);
        if (at.success) {
            out->success = 1;
            out->termination = BBHT_TERM_SUCCESS;
            out->result_index = at.result_index;
            break;
        }
        if (out->trial_count >= Q14_SHOT_CAP) {
            out->termination = BBHT_TERM_SHOT_LIMIT;
            break;
        }
        if (episode_l + 1 >= Q14_BUDGET) {
            out->termination = BBHT_TERM_BUDGET_LIMIT;
            break;
        }
        if (round < Q14_M_ROUNDS - 1)
            ++round;
    }
}
