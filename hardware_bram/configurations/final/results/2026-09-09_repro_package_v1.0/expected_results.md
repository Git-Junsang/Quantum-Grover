# Expected results

## Official 6-stage cycle-accurate RTL ablation (500 workloads)

| Stage | Aggregate cycles | Speedup vs Normal-E1 |
|---|---:|---:|
| Normal-E1 | 42,308,335 | 1.0000× |
| K4/H4-E1 | 18,349,320 | 2.3057× |
| K4/H4-E4 | 11,246,755 | 3.7618× |
| K3/H3-E4 | 10,385,795 | 4.0737× |
| K3/H3-E4-M1 | 8,500,620 | 4.9771× |
| K3/H3-E4-M2 | 6,890,470 | 6.1401× |

Anchor target=256 seed0: `18108, 14898, 12209, 11100, 9052, 7045` in paper-stage order.

## K/H isolated E1
- K4/H4-E1: 8,836,298 cycles
- K3/H4-E1: 8,818,101 cycles
- K3/H3-E1: 8,596,609 cycles
- semantic mismatch: 0

## Main-IP resource synthesis (Vivado 2024.2 common-condition)
K4/H4-E1 `13804 LUT / 13611 FF / 66 BRAM tile / 64 DSP`; K4/H4-E4 `30294 / 25822 / 83 / 64`; K3/H3-E4 `29959 / 25655 / 83 / 64`; M1 `33547 / 28195 / 84 / 128`; M2 `33730 / 28258 / 84 / 128`.

## Final standalone reference
WNS `+0.224 ns`, TNS `0`; LUT `34,399`; FF `28,847`; BRAM tile `84.5`; DSP `128`.

## Final full-RVX reference
WNS `+0.126 ns`, TNS `0`; WHS `+0.016 ns`; LUT `45,284`; FF `45,223`; Slice `15,214`; BRAM tile `116`; DSP `132`.
