# 여섯 configuration implementation — Arty 100T 실제 implementation과 200T(100T 예산) implementation

## 무엇인가

configuration 사이 board 비교를 위해 여섯 configuration을 두 번씩 구현한 결과를 한 표에 모았습니다.

- **Arty A7-100T(`xc7a100tcsg324-1`)**: 논문의 "100T resource · timing" 근거. 굽지 않았습니다. final configuration `final` 은 새로 돌리지 않고 2026-09-16 rebuild report를 씁니다.
- **AX7A200B(`xc7a200tfbg484-2`), 100T 예산**: 200T board에서 실제로 benchmark할 bitstream. `/fpga-syn-rvx --budget-100t` 로 Available을 100T와 같게 맞췄습니다.

개별 report는 각 configuration의 `vivado/vivado_<프로젝트>/2026-10-07_*` 에 있습니다.

## Arty 100T — 인용 값

| configuration | WNS (ns) | WHS (ns) | LUT | FF | BRAM tile | DSP | Accelerator Core LUT / FF / RAMB36 / RAMB18 / DSP |
|---|---:|---:|---:|---:|---:|---:|---|
| `capacity4_lookahead4_pes1_singlerow_linear` | +0.186 | +0.014 | 25,273 | 30,549 | 98 | 68 | 13,624 / 13,610 / 50 / 32 / 64 |
| `capacity3_lookahead3_pes1_singlerow_linear` | +0.267 | +0.010 | 25,049 | 30,339 | 87 | 68 | 13,404 / 13,398 / 39 / 32 / 64 |
| `capacity4_lookahead4_pes4_singlerow_linear` | +0.193 | +0.008 | 42,495 | 42,809 | 115 | 68 | 29,080 / 25,820 / 51 / 64 / 64 |
| `capacity3_lookahead3_pes4_singlerow_linear` | +0.083 | +0.028 | 42,277 | 42,606 | 115 | 68 | 28,842 / 25,617 / 51 / 64 / 64 |
| `capacity3_lookahead3_pes4_dualrow_linear` | +0.056 | +0.016 | 45,347 | 45,167 | 116 | 132 | 32,419 / 28,178 / 52 / 64 / 128 |
| `final` | +0.196 | +0.017 | 45,116 | 45,210 | 116 | 132 | 32,180 / 28,221 / 52 / 64 / 128 |

Available: LUT 63,400 · FF 126,800 · BRAM tile 135 · DSP 240. 여섯 모두 "All user specified timing constraints are met"입니다.

## 200T, 100T 예산 — benchmark 대상 build

| configuration | WNS (ns) | WHS (ns) | LUT | FF | BRAM tile | DSP | Available 일치 |
|---|---:|---:|---:|---:|---:|---:|:-:|
| `capacity4_lookahead4_pes1_singlerow_linear` | +0.879 | +0.042 | 25,499 | 30,551 | 98 | 68 | 예 |
| `capacity3_lookahead3_pes1_singlerow_linear` | +0.620 | +0.024 | 25,230 | 30,339 | 87 | 68 | 예 |
| `capacity4_lookahead4_pes4_singlerow_linear` | +0.121 | +0.051 | 42,759 | 42,812 | 115 | 68 | 예 |
| `capacity3_lookahead3_pes4_singlerow_linear` | +0.169 | +0.031 | 42,463 | 42,614 | 115 | 68 | 예 |
| `capacity3_lookahead3_pes4_dualrow_linear` | +0.100 | +0.042 | 45,487 | 45,146 | 116 | 132 | 예 |
| `final` | +0.052 | +0.030 | 45,316 | 45,210 | 116 | 132 | 예 |

## checkpoint를 뺀 revision까지 — Accelerator Core resource ablation study (Arty 100T)

checkpoint hardware 자체의 resource를 보려면 checkpoint를 끈 build가 필요합니다. checkpoint build를 mode0으로 돌리면 cycle은 같지만 checkpoint 저장소 · Policy Engine · memo table은 chip에 그대로 남기 때문입니다. `capacity0_pes1_singlerow_linear` 는 2026-10-08에 같은 흐름으로 구현했고([report](../../configurations/capacity0_pes1_singlerow_linear/vivado/vivado_bbht_grover_normal_e1/2026-10-08_arty100t_build/evidence.md)), No-Checkpoint Baseline은 `no_checkpoint_baseline` 의 2026-09-25 build([report](../../configurations/no_checkpoint_baseline/vivado/vivado_bbht_grover_nocheckpoint/2026-09-25_nocheckpoint_build/evidence.md))입니다.

| configuration | build | Accelerator Core LUT | FF | RAMB36 | RAMB18 | DSP | SoC LUT | SoC BRAM tile | WNS (ns) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Stage 1 | `capacity0_pes1_singlerow_linear` (2026-10-08) | 8,601 | 8,631 | 2 | 64 | 64 | 20,185 | 66 | +0.094 |
| Stage 2 | `capacity4_lookahead4_pes1_singlerow_linear` | 13,624 | 13,610 | 50 | 32 | 64 | 25,273 | 98 | +0.186 |
| a Checkpoint-Capacity of 3, 3-shot Lookahead and 1 PE | `capacity3_lookahead3_pes1_singlerow_linear` | 13,404 | 13,398 | 39 | 32 | 64 | 25,049 | 87 | +0.267 |
| No-Checkpoint Baseline | `no_checkpoint_baseline` (2026-09-25) | 24,846 | 21,650 | 47 | 64 | 64 | 38,133 | 111 | +0.193 |
| Stage 3 | `capacity4_lookahead4_pes4_singlerow_linear` | 29,080 | 25,820 | 51 | 64 | 64 | 42,495 | 115 | +0.193 |
| Stage 4 | `capacity3_lookahead3_pes4_singlerow_linear` | 28,842 | 25,617 | 51 | 64 | 64 | 42,277 | 115 | +0.083 |
| Stage 5 | `capacity3_lookahead3_pes4_dualrow_linear` | 32,419 | 28,178 | 52 | 64 | 128 | 45,347 | 116 | +0.056 |
| final configuration | `final` (2026-09-16) | 32,180 | 28,221 | 52 | 64 | 128 | 45,116 | 116 | +0.196 |

- **checkpoint(a Checkpoint-Capacity of 4, 4-shot Lookahead)를 넣는 값**은 Accelerator Core 기준으로 1 PE에서 LUT +5,023 · FF +4,979 · RAMB36 +48 · RAMB18 -32 (Stage 1 → Stage 2), 4 PEs에서 LUT +4,234 · FF +4,170 · RAMB36 +4 (No-Checkpoint Baseline → Stage 3)입니다. 논리는 두 경우가 비슷하고, BRAM은 1 PE에서만 크게 늘어납니다. 4 PEs는 checkpoint가 없어도 amplitude memory를 넓은 RAMB36으로 두기 때문입니다([20장 20.6절](../../../documents/design_references/20_no_checkpoint_baseline.md#206-resource)).
- **a Checkpoint-Capacity of 4, 4-shot Lookahead → a Checkpoint-Capacity of 3, 3-shot Lookahead**에서는 1 PE의 Accelerator Core RAMB36이 50 → 39로 줄고, 4 PEs에서는 51로 같습니다.
- 여덟 configuration 모두 100T에서 timing을 통과합니다.
- `no_checkpoint_baseline` 은 Vivado version(2026.1)과 흐름은 같지만 이 묶음과 다른 날(2026-09-25) build입니다.

## 읽는 법

- **1 PE → 4 PEs**에서 SoC LUT가 약 2.5만에서 4.2만으로 늘고 BRAM이 98·87에서 115로 늡니다. 4 PEs의 값입니다.
- **a Checkpoint-Capacity of 4, 4-shot Lookahead → a Checkpoint-Capacity of 3, 3-shot Lookahead**에서는 1 PE의 BRAM tile이 98 → 87로 줄고, 4 PEs에서는 115로 같습니다. 4 PEs의 amplitude memory는 row width로 RAMB36 개수가 정해져 checkpoint slot 하나를 줄여도 BRAM tile이 줄지 않습니다.
- **Dual-Row Build**에서 DSP가 68 → 132로 늘어납니다. Measurement Unit이 cycle당 두 row의 amplitude square를 구하기 때문입니다. Two-Level Select는 그 위에서 resource가 거의 늘지 않습니다.
- 가장 빠듯한 resource는 BRAM이고, 4 PEs 이상에서 100T의 85~86%입니다.
- 200T(100T 예산) 사용량은 Arty 100T와 LUT 1% 안, BRAM · DSP는 같습니다.

## 인용할 때

- resource · timing 인용은 **Arty 100T** 표에서 합니다. 200T build의 WNS는 0 이상인지만 봅니다.
- accelerator resource를 말할 때는 Accelerator Core(`u_main_ip`) 열을, SoC 전체를 말할 때는 앞 열을 쓰고 둘을 섞지 마십시오. 2026-09-08 resource ablation study(synthesis, Vivado 2024.2, standalone top 안 hierarchy)와는 조건이 달라 직접 맞대지 마십시오.
- `final` 의 100T 값은 2026-09-16 build입니다. 그 뒤 2026-09-25의 Accelerator Core 변경(4 PEs generate 조건)은 `CHECKPOINT_ENABLE=1` 에서 같은 값이 되어 이 구성의 논리를 바꾸지 않습니다([20장 20.2절](../../../documents/design_references/20_no_checkpoint_baseline.md#202-source를-어떻게-나눴나)).
- 전력은 활동률 없는 추정이라 인용하지 않습니다.
- 200T build의 `fpga_syn_rvx.sh result` 는 판정 script bug로 "timing 위반"을 냈습니다. 위 값은 report에서 직접 읽었습니다.

## file

| file | 내용 |
|---|---|
| `summary.csv` | 여섯 configuration × build 한 줄씩. SoC 전체 · Available · Accelerator Core · 전력. Stage 1 · No-Checkpoint Baseline은 각자의 report 묶음에 있습니다 |
