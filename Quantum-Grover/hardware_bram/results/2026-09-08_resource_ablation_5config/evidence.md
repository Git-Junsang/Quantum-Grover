# resource ablation study — 다섯 configuration 공통조건 synthesis

## 무엇인가

Six-Stage Ablation 의 다섯 compile configuration을 **같은 조건으로 synthesis**해서 각 단계가
resource를 얼마나 더 쓰는지 잰 표입니다. 조건은 Vivado 2024.2,
`xc7a100tcsg324-1`, 공통 source·공통 XDC, synthesis까지만(implementation·placement and routing 없음)입니다.

논문에 쓰는 주 수치는 **accelerator만 떼어 낸 `u_main_ip` hierarchy 사용량**입니다.
standalone top 전체 수치는 참고용으로 같이 둡니다.

## 확정 수치 — Accelerator Core hierarchy

| 단계 | LUT | FF | BRAM tile | DSP |
|---|---:|---:|---:|---:|
| Stage 1 / Stage 2 | 13,804 | 13,611 | 66.0 | 64 |
| Stage 3 | 30,294 | 25,822 | 83.0 | 64 |
| Stage 4 | 29,959 | 25,655 | 83.0 | 64 |
| Stage 5 | 33,547 | 28,195 | 84.0 | 128 |
| **final configuration** | **33,730** | **28,258** | **84.0** | **128** |

Stage 1과 Stage 2가 같은 줄인 이유는 둘이 같은 bitstream이기 때문입니다 —
runtime mode 로만 갈립니다.

읽는 법:

- **1 PE → 4 PEs에서 LUT 이 2.2×** 뜁니다 (13,804 → 30,294). PE를 네 벌 두는
  값이고, Six-Stage Ablation 표에서 이 단계가 -38.71% 를 벌었습니다.
- **a Checkpoint-Capacity of 4 · 4-shot Lookahead → a Checkpoint-Capacity of 3 · 3-shot Lookahead는 오히려 조금 줄어듭니다** (30,294 → 29,959). Checkpoint-Capacity와
  Lookahead-Shots를 줄였으니 당연하고, 그러면서 cycle은 -7.66% 벌었습니다. 공짜 이득입니다.
- **Dual-Row Build에서 DSP 가 64 → 128** 로 두 배가 됩니다. Measurement Unit에서 한 cycle에
  두 row를 처리하게 만든 대가입니다. Two-Level Select는 그 위에 hierarchical row 선택을 얹은
  것이라 resource가 거의 안 늘고(LUT +183) cycle만 -18.94% 벌었습니다.

## 확정 수치 — standalone top 전체

| 단계 | LUT | FF | BRAM tile | DSP |
|---|---:|---:|---:|---:|
| Stage 1 / Stage 2 | 14,684 | 14,168 | 66.5 | 64 |
| Stage 3 | 32,409 | 26,445 | 83.5 | 64 |
| Stage 4 | 32,073 | 26,278 | 83.5 | 64 |
| Stage 5 | 35,159 | 28,819 | 84.5 | 128 |
| final configuration | 35,342 | 28,882 | 84.5 | 128 |

## 저장소 source로 확인한 것

`hardware_bram/synth/run_main_ip.sh` 로 우리 `src/` 를 final configuration
parameter로 OOC synthesis해 봤습니다. 2026-09-09, Vivado 2026.1, synthesis 2분 14초.

| | OOC synthesis | 위 표 (공통조건) | 차이 |
|---|---:|---:|---:|
| LUT | 34,713 | 33,730 | +2.9% |
| FF | 28,202 | 28,258 | -0.2% |
| BRAM tile | 84.0 | 84.0 | 0 |
| DSP | 128 | 128 | 0 |

BRAM 과 DSP 가 정확히 맞고 FF 가 0.2% 안에 듭니다. LUT 이 2.9% 더 나오는 것은
OOC 단독 synthesis와 standalone top 안의 hierarchy 추출이라는 조건 차이 때문입니다
(Vivado version도 2026.1 대 2024.2 로 다릅니다). **우리 `src/` 가 final configuration이
맞다는 확인**으로는 충분하지만, 논문에 인용할 값은 위 표 쪽입니다.

## 이 숫자를 쓸 때의 경계

- **synthesis 결과이지 implementation 결과가 아닙니다.** placement and routing을 거친 최종 수치는
  `hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/reports/` 에 있고, 그쪽은
  RVX SoC 까지 포함한 전체라 LUT 45,284 / FF 45,223 / BRAM 116 / DSP 132 입니다.
- Vivado version과 synthesis 전략이 바뀌면 값이 달라집니다. 같은 조건으로 다섯을
  나란히 재는 것이 이 표의 목적이지 절대값을 못박는 것이 아닙니다.
- synthesis script(`synth/run_resource.sh`)와 대상 top 5벌 · 공통 XDC 는 tag
  `board-verified-build-2026-09-07` 에 있습니다. main 에서는 `hardware_bram/synth/run_main_ip.sh`
  로 final configuration 하나만 OOC 로 잴 수 있습니다.

## file

| file | 내용 |
|---|---|
| `main_ip_6stage.csv` | Accelerator Core hierarchy, Six-Stage Ablation 표 (LUT 세부·SRL·RAMB 포함) |
| `main_ip_5config.csv` | 같은 값을 다섯 configuration으로 (중복 제거) |
| `top_6stage.csv` · `top_5config.csv` | standalone top 전체 |
