# a Checkpoint-Capacity of 3, 3-shot Lookahead and 1 PE — AX7A200B implementation, 100T resource 예산 (WNS +0.620 ns)

## 무엇인가

`capacity3_lookahead3_pes1_singlerow_linear` 을 그때의 RVX platform `bbht_grover_k3h3_e1` 로 원격 board AX7A200B(`xc7a200tfbg484-2`)에 구현한 report입니다. `/fpga-syn-rvx --budget-100t` 로 200T의 site를 막아 Available을 100T와 같게 맞췄습니다. 이 bitstream이 200T board에서 configuration 사이 benchmark를 할 대상입니다.

## 확정 수치

| 항목 | 값 |
|---|---:|
| setup WNS / TNS | **+0.620 ns** / 0.000 |
| hold WHS / THS | +0.024 ns / 0.000 |
| Vivado 판정 | All user specified timing constraints are met |
| LUT | 25,230 / 63,400 |
| FF | 30,339 / 126,800 |
| BRAM tile | 87 / 135 |
| DSP | 68 / 240 |
| Accelerator Core (`u_main_ip`) LUT / FF / RAMB36 / RAMB18 / DSP | 13,456 / 13,398 / 39 / 32 / 64 |
| 전력 (추정, 활동률 없음) | 0.481 W |

Available은 report의 값입니다 (200T에서 100T 예산을 건 결과라 100T와 같음).

## 인용할 때

- **WNS는 0 이상인지만 봅니다.** placement · routing이 100T와 달라 값 자체를 인용하지 않습니다. timing과 resource 인용은 Arty 100T report에서 합니다.
- `fpga_syn_rvx.sh result` 는 이 build에서 "timing 위반"으로 exit 1을 냈지만 오판입니다. script가 Design Timing Summary의 값 줄 대신 그 아래 빈 줄을 읽습니다(`grep -A3 … | tail -1`). 위 값은 `route_timing_summary.rpt` 에서 직접 읽은 것입니다.
- `bitstream_sha256.txt` 에 bitstream과 함께 build한 app hex의 sha256이 있습니다. board benchmark 결과는 이 hash로 build와 묶습니다.
- 여섯 configuration을 맞댄 표는 [2026-10-07_impl_6models](../../../../../results/2026-10-07_impl_6models/evidence.md) 에 있습니다.
- 같은 configuration의 RTL cycle은 [2026-10-07_bench500_6models](../../../../../results/2026-10-07_bench500_6models/evidence.md) 에 있습니다.

## file

| file | 내용 |
|---|---|
| `route_util.rpt` · `route_util_hier.rpt` | routing 뒤 resource (전체 · hierarchy) |
| `route_timing_summary.rpt` | routing 뒤 timing |
| `route_power.rpt` | 전력 추정 |
| `build_info.txt` | build 조건 |
| `bitstream_sha256.txt` | bitstream · app hex hash |
| `source_sha256.txt` | platform에 들어간 RTL의 hash |
| `summary.csv` | 위 수치 한 줄 |
