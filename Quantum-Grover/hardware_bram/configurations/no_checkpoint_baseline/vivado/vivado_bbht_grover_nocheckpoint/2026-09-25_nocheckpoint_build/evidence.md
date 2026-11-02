# No-Checkpoint Baseline bitstream — 100 MHz timing closure (WNS +0.193 ns)

## 무엇인가

`no_checkpoint_baseline` 을 RVX platform `bbht_grover_nocheckpoint`(지금 `bbht_grover_no_checkpoint_baseline`)로 Arty A7-100T 에
구현한 build의 report입니다. configuration은 4 PEs만 켜고 checkpoint · Policy Engine ·
Dual-Row Build · Two-Level Select를 끈 No-Checkpoint Baseline입니다. SoC 구성과 placement · routing 흐름은 final configuration
rebuild([`2026-09-16_comm_layer_rebuild`](../../../../final/vivado/vivado_bbht_grover_fpga/2026-09-16_comm_layer_rebuild/))
와 같게 두고 adapter parameter만 바꿨습니다. 구운 실물은
[`../../../bitstream/2026-09-25_nocheckpoint/`](../../../bitstream/2026-09-25_nocheckpoint/evidence.md)
에 있습니다.

## 확정 수치

| 항목 | No-Checkpoint Baseline | final configuration (2026-09-16) |
|---|---:|---:|
| setup WNS / TNS | **+0.193 ns** / 0.000 | +0.196 ns / 0.000 |
| hold WHS / THS | +0.012 ns / 0.000 | +0.017 ns / 0.000 |
| Vivado 판정 | All user specified timing constraints are met | 같음 |
| LUT / FF | 38,133 / 38,634 | 45,116 / 45,210 |
| BRAM tile / DSP | 111 / 68 | 116 / 132 |
| Slice | 14,342 (90.49%) | 14,971 |
| 전력 (추정) | 0.624 W | 0.568 W |

clock별 setup WNS: `sys_clk_pin`(accelerator 100 MHz) +0.193, `clk_50000000`(core · peripheral
50 MHz) +5.374.

Accelerator Core(`u_main_ip`)만 보면:

| 항목 | No-Checkpoint Baseline | final configuration | 차이의 출처 |
|---|---:|---:|---|
| LUT | 24,846 | 32,180 | Policy Engine(3,077) · Checkpoint Planner/Checkpoint Executor/metadata · Dual-Row Build · Two-Level Select |
| FF | 21,650 | 28,221 | Policy Engine(2,921) · Measurement Unit row buffer |
| RAMB36 / RAMB18 | 47 / 64 | 52 / 64 | Policy Engine memo table(4)과 Measurement Unit(1) |
| DSP | 64 | 128 | **전부 Measurement Unit**. Dual-Row Build는 amplitude square를 cycle당 두 rows 계산하므로 multiplier가 두 배 |

4 PEs amplitude memory(`g_intra_e4.u_amp_mem`)는 두 configuration 모두 RAMB36 44 개입니다. No-Checkpoint Baseline은 checkpoint slot 0
하나만 쓰지만, 736-bit row를 담는 RAMB36 은 폭으로 개수가 정해져 깊이를 줄여도
BRAM tile이 줄지 않습니다.

전력은 두 configuration 모두 simulation 활동률 없이 낸 추정(Vivado 신뢰도 Medium)입니다. No-Checkpoint Baseline이 더 높게
나왔지만 configuration 사이 전력 차이로 인용하지 마십시오.

## 인용할 때

- 이 build는 **board에서 돌리지 않았습니다.** timing closure까지가 근거입니다.
- 속도 비교(checkpoint · Dual-Row Build/Two-Level Select 유무)는 RTL cycle로
  [`results/2026-09-25_predicate500_rtl/`](../../../results/2026-09-25_predicate500_rtl/evidence.md)
  에 있습니다. board wall-clock time 비교는 두 bitstream을 같은 board에서
  `bbht_predicate500.py` 로 돌린 뒤에 합니다.

## file

| file | 내용 |
|---|---|
| `route_timing_summary.rpt` · `route_timing_max.rpt` | timing |
| `route_util.rpt` · `route_util_hier.rpt` | resource |
| `route_power.rpt` | 전력 추정 |
| `summary.csv` | 한 줄 요약 (final configuration 묶음과 같은 열) |
| `build_info.txt` | build 조건 · clock · 순서 |
| `source_sha256.txt` | platform에 설치된 RTL 17개의 sha256. 저장소 원본과 17/17 같음 |
| `bitstream_sha256.txt` | bitstream sha256 |
