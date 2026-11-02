# 실험 04. enumeration 두 방식 비교

> [← 실험 03 random number seed coverage](03_random_seed_coverage.md) · [index](index.md) · [실험 05 checkpoint policy algorithm 선정 →](05_checkpoint_policy_selection.md)

---

| 정한 것 | 근거의 축 |
|---|---|
| enumeration은 Found Mask 방식, Accelerator Core 안 | reference model 두 방식 대조 |

enumeration에서 이미 찾은 solution을 빼는 방식을 둘 두고 reference model로 나란히 돌렸습니다
([3장 3.5절](../design_references/03_grover_and_bbht_algorithm.md#35-enumeration-solution을-전부-찾기)).

| 지표 | 결과 |
|---|---:|
| 조건 | 1,280 |
| runs | 5,888 |
| 요청한 결과 개수 충족 | 5,888 / 5,888 |
| 중복 · 유효 범위 밖 결과 | 0 · 0 |
| backend 비교 쌍 | 2,944 |
| 발견 결과 · shot · requested iterations · executed iterations 불일치 | 0 |

두 방식이 모든 쌍에서 같은 결과를 냈으므로 차이는 제어 비용과 data 이동 비용뿐입니다.
dataset을 다시 보내지 않는 `PROJECTED_MASK_MEM`을 골랐고, v0.9.8에서 Found Mask(`found_mask`) · enumeration FSM ·
256-entry Result FIFO가 Accelerator Core 안으로 들어갔습니다. enumeration test vector(두 방식 × 5 cases)는
[4장 4.5절](../design_references/04_software_reference_model_and_test_vectors.md#45-rtl-test-vector)에 있습니다.
