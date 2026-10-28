# Stage 2 — Arty A7-100T implementation (WNS +0.186 ns)

## 무엇인가

`capacity4_lookahead4_pes1_singlerow_linear`를 RVX platform `bbht_grover_k4h4_e1`로 Arty A7-100T(`xc7a100tcsg324-1`)에 구현한 report입니다. 공용 `hardware_bram/src/`에 이 configuration adapter의 parameter만 넣었고, SoC 구성과 흐름은 final configuration rebuild(2026-09-16)와 같습니다. **board에 굽지 않았습니다.** 논문의 "100T resource · timing" 근거로 쓰려고 낸 build입니다.

## 확정 수치

| 항목 | 값 |
|---|---:|
| setup WNS / TNS | **+0.186 ns** / 0.000 |
| hold WHS / THS | +0.014 ns / 0.000 |
| Vivado 판정 | All user specified timing constraints are met |
| LUT | 25,273 / 63,400 |
| FF | 30,549 / 126,800 |
| BRAM tile | 98 / 135 |
| DSP | 68 / 240 |
| Accelerator Core (`u_main_ip`) LUT / FF / RAMB36 / RAMB18 / DSP | 13,624 / 13,610 / 50 / 32 / 64 |
| 전력 (추정, 활동률 없음) | 0.436 W |

Available은 report의 값입니다.

## 인용할 때

- resource · timing은 이 report에서 인용합니다. 다만 Accelerator Core만의 resource를 논문 표에 쓸 때는 `u_main_ip` row를 쓰고, SoC 전체와 섞지 마십시오.
- 전력은 simulation 활동률 없이 낸 추정(Vivado 신뢰도 Medium)이라 configuration 사이 전력 차이로 인용하지 마십시오.
- 여섯 configuration을 맞댄 표는 [2026-10-07_impl_6models](../../../../../results/2026-10-07_impl_6models/evidence.md)에 있습니다.
- 같은 configuration의 RTL cycle은 [2026-10-07_bench500_6models](../../../../../results/2026-10-07_bench500_6models/evidence.md)에 있습니다.

## file

| file | 내용 |
|---|---|
| `route_util.rpt` · `route_util_hier.rpt` | routing 뒤 resource (전체 · hierarchy) |
| `route_timing_summary.rpt` | routing 뒤 timing |
| `route_power.rpt` | 전력 추정 |
| `build_info.txt` | build 조건 |
| `bitstream_sha256.txt` | bitstream hash |
| `source_sha256.txt` | platform에 들어간 RTL의 hash |
| `summary.csv` | 위 수치 한 줄 |
