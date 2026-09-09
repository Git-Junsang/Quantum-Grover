#ifndef BBHT_SW_BASELINE_CONFIG_H
#define BBHT_SW_BASELINE_CONFIG_H

/*
 * 0: boardless/RTL-sim smoke: target_count=256, seed_index=0 only.
 * 1: publication campaign: target_count={1,4,16,64,256} x seeds [0, SEED_COUNT).
 *
 * Start with 0 in RVX RTL simulation.  Use 1 for the final actual-board ORCA run.
 */
#define BBHT_SW_RUN_FULL 1

/* Valid range: 1..100.  Used only when BBHT_SW_RUN_FULL=1. */
#define BBHT_SW_SEED_COUNT 100u

#endif
