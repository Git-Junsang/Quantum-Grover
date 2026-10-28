# 10장. Measurement Unit과 Dual-Row Build · Two-Level Select

> [← 9장 Iteration Datapath와 4 PEs](09_iteration_datapath_and_number_of_pes.md) · [index](index.md) · [11장 checkpoint와 Policy Engine →](11_checkpoint_and_policy_engine.md)

`BUILD_ROWS_PER_CYCLE` = 4(Quad-Row Build) 경로와 200T 실험용 설정 생성은
[실험 27](../reports/27_200t_parameter_automation.md)에 있습니다. 이 장의 Dual-Row Build · Two-Level Select는 Board-Verified Build에 들어 있는 구성입니다.

---

iteration이 끝나면 Born-rule sampling으로 index 하나를 선택합니다. 기존 구조는 512 rows를 두 차례
순회하므로 measurement 비용이 iteration 연산에 버금갔습니다. Six-Stage Ablation에서 Dual-Row Build와 Two-Level Select를 적용한
결과, Stage 4 대비 cycle이 33.7% 감소했습니다.

---

## 10.1 세 단계

| 단계 | 무엇을 |
|:-:|---|
| Build | 512 rows를 훑으며 row마다 32 lanes amplitude를 square해 더한 row weight로 prefix sum을 만듦 |
| Select | Measurement PRNG 출력과 total weight로 random number를 만들고, prefix sum을 훑어 그 random number를 넘는 첫 row를 찾음 |
| Reread | 그 row를 다시 읽어 lane 하나를 고르고 index를 확정 |

그 뒤에 solution check가 붙습니다. 확정된 index의 data 값을 predicate로 다시 검사하고,
틀리면 실패한 shot이 됩니다([8장 8.6절](08_accelerator_core_top_and_bbht_control.md)).

solution check는 oracle과 같은 Predicate Unit(`grover_predicate`)을 씁니다. 둘이 다른 implementation을 쓰면
경계 조건에서 어긋날 수 있기 때문입니다.

### integer 절차

amplitude를 float probability로 바꾸지 않고 raw integer를 직접 square합니다. 칸 하나의 weight는 raw의 square이고,
total weight는 16,384칸 weight의 sum입니다.

```text
1. 512 amplitude rows를 읽어 32 squares와 row weight 계산
2. 모든 row weight를 합해 total weight 계산
3. Measurement PRNG 출력 두 번을 {high, low} 64-bit 값으로 결합
4. rejection sampling 으로 0 <= r < total weight 인 random number r 생성
5. row weight의 prefix sum이 처음으로 r 을 넘는 row 선택
6. 그 row를 다시 읽어 lane prefix sum이 처음으로 local_r 을 넘는 lane 선택
7. candidate = {row, lane}
8. data_mem Port-B 로 candidate 값을 다시 읽음
9. oracle과 같은 padding + predicate로 solution check
```

1~2단계의 512 rows rescan이 Measurement Unit의 병목이고, Dual-Row Build · Two-Level Select가 이 자리를 줄입니다(10.3 · 10.4절).

같은 seed에서 RTL과 reference model이 같은 index를 얻으려면 다음이 전부 같아야 합니다.

- Measurement PRNG(xorshift64)의 shift constant와 fallback seed
- Measurement PRNG 출력을 뽑는 시점과 소비 개수
- 64-bit 결합 순서
- rejection sampling 규칙
- 엄격한 `prefix sum > random number` 비교
- row를 먼저, lane을 나중에 고르는 순서

---

## 10.2 probability를 보존하는 square 연산

square는 23×23 multiplication을 DSP로 합니다. 32 lanes를 더할 때 47/48/49/50/51 bits로 정확히 필요한
폭만 써서 adder tree로 줄입니다([6장 6.4절](06_data_representation_and_memory_map.md)).

truncation도 round-half-to-even도 normalization도 없고 lane 순서도 바뀌지 않습니다. 그래서 probability가 이론값에서
벗어나지 않습니다. Born rule을 지키는 것이 이 설계의 전제이므로
([3장 3.4절](03_grover_and_bbht_algorithm.md)), 여기서 precision을 깎으면 BBHT 통계가
어긋나고 software reference model과의 500/500 대조가 무너집니다.

timing을 위해 pipeline register를 네 곳에 넣었습니다.

1. memory 출력 → register
2. square → register
3. 32→16→8 adder tree → register
4. 8→4→2→1 → row weight register

값을 바꾸지 않고 latency만 늘리는 pipeline register입니다.

---

## 10.3 Dual-Row Build: cycle당 2 rows

4 PEs의 4 rows 동시 읽기 port가 이미 있습니다([9장 9.4절](09_iteration_datapath_and_number_of_pes.md)). 그러니
squarer 한 벌을 더 두고 row weight memory의 write port를 두 개로 늘리면 Build가 절반이 됩니다.

| | Build |
|---|---|
| Single-Row Build | 512 cycles |
| Dual-Row Build | 256 cycles |

`grover_row_weight_mem_m1_2w`가 그 write port 두 개짜리 memory입니다.

이 단계에서 DSP가 64 → 128로 두 배가 됩니다. squarer를 한 벌 더 두는 값이고,
이것이 project 전체에서 DSP를 쓰는 거의 유일한 자리입니다(diffusion operator·oracle·Init 경로에는
multiplier가 없습니다).

---

## 10.4 Two-Level Select: 두 단계 Select

512 rows를 32 rows씩 16 groups로 나눕니다. Build 중에 각 group의 마지막 row에서 그때까지의
prefix sum을 그대로 group prefix sum으로 기록해 둡니다.

추가 square도, Build cycle 추가도 없습니다. 이미 만들고 있던 prefix sum을 16번 더 적어 두는
것뿐입니다.

Select는 두 단으로 바뀝니다.

```
① 16 groups의 group prefix sum만 훑어 random number를 넘는 첫 group을 찾음
② 그 group 안의 32 rows만 기존 방식으로 훑음
```

| | Select worst case |
|---|---|
| Linear Select (Stage 5까지) | 512회 비교 |
| Two-Level Select | 16 + 32 = 48회 비교 |

Two-Level Select는 resource 대비 효과가 가장 큰 단계입니다. LUT 183개를 추가해 cycle을 18.94%
줄였습니다.

---

## 10.5 두 switch

`BUILD_ROWS_PER_CYCLE` · `USE_TWO_LEVEL_SELECT`는 main의 `src/`에만 있는 compile parameter입니다.
기본값(2 · 1)이면 Board-Verified Build와 동작이 같습니다. Six-Stage Ablation을 한 벌의 source로
돌리려고 추가한 것이고, board에 구운 Board-Verified Build에는 이 parameter가 없습니다.

---

## 10.6 resource와 이득

| configuration | LUT | FF | BRAM tile | DSP | 직전 대비 cycle |
|---|---:|---:|---:|---:|---:|
| Stage 4 | 29,959 | 25,655 | 83.0 | 64 | — |
| Stage 5 | 33,547 | 28,195 | 84.0 | 128 | -18.15% |
| final configuration | 33,730 | 28,258 | 84.0 | 128 | -18.94% |

Dual-Row Build는 DSP 사용량을 두 배로 늘리고 LUT 3,588개를 추가해 cycle을 18.15% 줄였습니다.
Two-Level Select는 LUT 183개를 추가해 다시 18.94% 줄였습니다. 두 단계를 함께 적용하면 Stage 4 대비
33.7% 감소합니다.

근거는 [resource_ablation_5config](../../hardware_bram/results/2026-09-08_resource_ablation_5config/evidence.md)
와 [publication_6stage](../../hardware_bram/results/2026-09-08_publication_6stage/evidence.md)
입니다.

---

## 10.7 zero-weight 오류

total weight가 0이면 random number를 만들 수 없습니다. amplitude가 전부 0이라는 뜻이고,
정상 동작에서는 나오지 않습니다. `STATUS`의 `zero_weight_error`가 서고 search가 즉시
끝납니다. 종료 우선순위에서 성공 바로 다음입니다
([8장 8.6절](08_accelerator_core_top_and_bbht_control.md)).
