# 실험 09. measurement 병목과 Dual-Row Build · Two-Level Select

> [← 실험 08 1 PE profiling과 4 PEs](08_one_pe_profiling_and_four_pes.md) · [index](index.md) · [실험 10 Two-Track Execution과 Pass 2–Build Fusion: 채택하지 않은 두 시도 →](10_two_track_execution_and_pass2_build_fusion.md)

---

| 정한 것 | 근거의 축 |
|---|---|
| Measurement Unit Dual-Row Build · Two-Level Select | RTL cycle 분해 |

첫 결과를 Result FIFO에 넣을 때까지를 배타적으로 나눈 RTL cycle입니다(14 qubits, 1 solution, 23 shots,
179 requested iterations(`REQUESTED_ITERATIONS`), 55 executed iterations).

| 항목 | Stage 2 | Stage 4 |
|---|---:|---:|
| Init + Grover iteration (executed) | 57,329 (68.2%) | 14,649 (38.9%) |
| measurement | 18,955 (22.6%) | 18,955 (50.3%) |
| policy만 드러난 시간 | 6,808 (8.1%) | 3,353 (8.9%) |
| 제어 · 기타 | 918 | 700 |
| sum | 84,010 | 37,657 |

4 PEs가 Init과 Grover iteration 시간을 3.91× 줄이자 measurement가 절반을 넘는 병목이 됐습니다. measurement 안에서는 Build가 shot당
518 cycles(512 rows rescan), row 선택(ROW_SCAN)이 약 269, lane 선택이 약 17.5였습니다. 그래서 Checkpoint-Capacity · Lookahead-Shots
미세조정보다 measurement를 먼저 줄였습니다.

| 단계 | 무엇 | measurement cycles / shot | 첫 결과까지 total cycles |
|---|---|---:|---:|
| 이전 (Single-Row Build · Linear Select) | Build는 한 cycle에 한 row, 512 rows를 차례로 선택 | 824.1 | 37,657 |
| Dual-Row Build | 4 PEs의 4 rows 동시 읽기를 measurement에도 쓰고 squarer 한 벌을 더해 Build를 cycle당 2 rows로 | 568.1 | 31,769 |
| Two-Level Select | Build 중 32-row group의 group prefix sum을 적어 두고 16 groups → 32 rows 두 단으로 선택 | 327.9 | 26,392 |

Dual-Row Build의 비용은 두 번째 squarer의 DSP(64 → 128)였고, Two-Level Select는 row 선택을 약 269 → 28.9 cycles/shot으로
줄이면서 square 연산도 Build cycle도 늘리지 않았습니다. enumeration 전체로는 253,622 → 192,874 cycles(−23.95%)
이었고 병목은 다시 Init과 Grover iteration(약 75%)으로 돌아갔습니다. 8 × 8 × 8 같은 더 깊은 선택은 이득이
줄어들어 보류했습니다. 구조는 [10장](../design_references/10_measurement_unit_and_microarchitecture.md)에 있습니다.
