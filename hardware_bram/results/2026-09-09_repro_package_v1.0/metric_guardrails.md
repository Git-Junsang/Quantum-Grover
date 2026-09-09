# Metric guardrails

1. The 6-stage `6.1401×` result is **cycle-accurate RTL simulation**, measured from DUT `CSR_CYCLE_COUNT` under identical datasets/seed pairs.
2. Actual-board K4/H4 and final-M2 numbers are **elapsed-time board measurements** and form a different evidence axis.
3. ORCA pure-software comparison is a **single-ORCA-core same-platform actual-board elapsed-time** comparison; do not call the RTL 6.1401× result an FPGA elapsed-time speedup.
4. Resource ablation is Vivado 2024.2 common-condition standalone-top synthesis with accelerator-only `u_main_ip` hierarchy extracted for the primary resource table. Full-RVX final implementation is a separate implementation/P&R result.
