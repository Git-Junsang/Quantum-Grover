# 실험 01. reference model campaign: 기능 정합성

> [← index](index.md) · [실험 02 amplitudes precision: 14 qubits와 fraction bits 22-bit →](02_amplitude_precision.md)

---

| 정한 것 | 근거의 축 |
|---|---|
| padding gate, predicate comparator 하나, paired comparison 불변식으로 verification | Python reference model 671,600 runs |

2026-08에 당시 RTL(v0.7g, 14 qubits · 32 lanes · 16-bit data word · Q1.22) 규칙을 옮긴 Python reference model로 돌린
campaign입니다. FPGA benchmark가 아니고, 전체 RTL을 671,600회 돌렸다는 뜻도 아닙니다. checkpoint는
checkpoint slot 하나짜리 옛 구조인 Single-Slot Checkpoint(`BBHT_BURST`)였습니다.

| 축 | 값 |
|---|---|
| profile | 14 qubits (당시 확장 후보 16 qubits도 함께. 16 qubits는 뒤에 폐기) |
| `DATA_COUNT` | number of states의 25 · 50 · 75 · 100% |
| number of solutions | 0, 1, powers of 2, `DATA_COUNT`/number of states의 25 · 50 · 75 · 90 · 100% |
| predicate | EQ · GT · LT · RANGE |
| padding | SAFE, POISON (padding 자리에 predicate를 만족하는 값을 일부러 넣음) |
| solution 배치 | HEAD, BANK_STRIDED, RANDOM |
| search | Manual(최적의 number of iterations로 한 번), BBHT Restart mode, BBHT Single-Slot Checkpoint |
| number of seeds | Manual 30, BBHT 100 |
| 규모 | 8,760 조건 · 671,600 runs · 6,397,040 BBHT shots |

| 항목 | 결과 |
|---|---:|
| solution mask 오류 (requested number of solutions 대 popcount) | 0 / 671,600 |
| padding 오판정 | 0 / 671,600 |
| SAFE / POISON 불일치 | 0 / 287,040쌍 |
| 네 predicate 불일치 (같은 mask를 네 경로로 만든 비교) | 0 / 503,700 |
| Restart mode / Single-Slot Checkpoint 결과 · 종료 · amplitude hash 불일치 | 0 / 292,000쌍 |
| 0 solutions 정상 비성공 | 12,880 / 12,880 |
| solution이 있을 때 BBHT 최종 성공 | 572,800 / 572,800 |
| solution이 있을 때 Manual 1회 성공 | 84,884 / 85,920 (98.79%) |

이 campaign에서 굳은 것은 셋입니다.

- padding 보호는 특정 sentinel 값에 기대지 않고 `index < DATA_COUNT` gate로 합니다. POISON이
  SAFE와 모두 같았습니다.
- 네 predicate는 같은 comparator 하나로 oracle과 solution check에 씁니다. 같은 mask면 결과 · amplitude · iteration이 모두
  같았습니다([9장 9.2절](../design_references/09_iteration_datapath_and_number_of_pes.md#92-산술-조각)).
- checkpoint의 정합성은 paired comparison 불변식으로 봅니다. 같은 seed에서 Restart mode와 Checkpoint mode는 number of iterations 순서,
  requested iterations, 결과가 같고 executed iterations만 줄어야 합니다. 최종 index만으로 PASS를 선언하지 않습니다.
  BBHT가 후보를 predicate로 직접 verification하므로 amplitude가 깨져도 답은 맞을 수 있고, 실제로 [실험 10](10_two_track_execution_and_pass2_build_fusion.md)의 공유
  checkpoint slot 실험이 그랬습니다.

Manual의 비성공 1,036회는 모두 확률적 1회 measurement입니다. BBHT 100%는 shot 한 번이 늘 성공했다는
뜻이 아니라 재시도 뒤의 최종 성공률입니다. 0 solutions에서 BBHT가 BBHT budget까지 도는 것(14 qubits에서 mean shots
32.32, requested iterations 614.53)은 오류가 아니라 number of solutions를 모르는 search의 비용입니다.

같은 무렵 전달 RTL 8 cases(Restart mode / Single-Slot Checkpoint × 1 · 4 · 8 · 6 iterations)를 reference model이 index · Born-rule sampling의
total weight(`2^44`) · `REQUESTED_ITERATIONS` · executed iterations까지 그대로 재현했습니다. 이 8 cases는 지금도 유효한
bit-exact regression 기준입니다.
