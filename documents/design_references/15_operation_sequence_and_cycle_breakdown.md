# 15장. 동작 과정과 cycle 구성

> [← 14장 host interface와 UART protocol](14_host_interface_and_uart_protocol.md) · [index](index.md) · [16장 verification 체계 →](16_verification_framework.md)

---

이 장에서는 host가 `RUN`을 전송한 뒤 결과를 받을 때까지의 전체 처리 순서와 각 단계의
cycle 비용을 설명합니다.

---

## 15.1 `RUN` 처리 순서

| 단계 | 누가 | 무엇을 | 장 |
|:-:|---|---|:-:|
| 1 | host → core | predicate · threshold · seed · mode를 한 줄로 보냄 | 14 |
| 2 | core | dataset을 system SRAM에 배치하고 CSR에 설정값을 씀 | 13 |
| 3 | core → mmio | `DMA_COMMAND`로 load 시작 | 7 |
| 4 | DMA Engine | AHB SINGLE로 16-bit data word를 순서대로 읽어 data memory를 채움 | 7 |
| 5 | core → mmio | `COMMAND`로 search 시작. 조건이 안 맞으면 거절 | 5 |
| 6 | Accelerator Core | amplitude를 uniform superposition으로 `S_INIT` | 9 |
| 7 | Accelerator Core | sampling range 안에서 number of iterations를 뽑음 (Iteration-Count LFSR, 7-step jump) | 8 |
| 8 | Accelerator Core | 뽑은 number of iterations만큼 Grover iteration: oracle → mean 계산 → inversion about the mean | 9 |
| 9 | Accelerator Core | Born-rule sampling으로 index 하나를 뽑음 | 10 |
| 10 | Accelerator Core | 그 index의 data 값을 predicate로 다시 확인 (solution check) | 10 |
| 11 | Accelerator Core | 맞으면 결과 확정. 틀리면 sampling range를 키워 7로 되돌아감 | 8 |
| 12 | Accelerator Core → mmio | counter 갱신, `done_sticky` | 13 |
| 13 | core → host | CSR을 읽어 응답 줄을 만들어 보냄 | 14 |

7~11이 BBHT 한 shot입니다.

확정 설계에서 8번은 매번 처음부터 돌지 않습니다. checkpoint가 있으면 이미 돌려 둔
state에서 차이만큼만 이어 돌립니다([11장](11_checkpoint_and_policy_engine.md)).

enumeration mode에서는 결과를 하나 찾을 때마다 `found_mask`에 표시하고 sampling range를 1로 되돌려 다음
enumeration round를 시작합니다. checkpoint는 무효화됩니다.

---

## 15.2 iteration 관련 counter

| 이름 | CSR | 뜻 | checkpoint가 줄이나 |
|---|---|---|:-:|
| requested iterations `REQUESTED_ITERATIONS` | `0x030` | 뽑힌 number of iterations의 sum | 아니오 |
| executed iterations `EXECUTED_ITERATIONS` | `0x034` | 실제로 돌린 number of iterations | 예 |
| number of shots `SHOT_COUNT` | `0x02C` | 돌린 shot 전체 | 아니오 |

2026-09-17 board session의 한 workload에서 세 counter의 차이를 확인할 수 있습니다.

| 실행 | `trials` | `l` (requested) | `iters` (executed) | `cyc` |
|---|---:|---:|---:|---:|
| Restart mode (`BURST=0`) | 21 | 119 | 119 | 41,310 |
| checkpoint (첫째) | 21 | 119 | 38 | 20,935 |
| checkpoint (둘째) | 21 | 119 | 38 | 17,847 |

논리 축 셋(`trials` · `l`)이 같고 executed iterations만 119 → 38로 줄었습니다. checkpoint는
BBHT trajectory를 바꾸지 않고 계산만 재활용하기 때문입니다. 이것이 regression의 핵심 invariant이고,
500/500으로 검증되어 있습니다([16장](16_verification_framework.md)).

같은 설정·data·seed인데 checkpoint 두 줄의 cycle이 다른 것은 실행 이력 차이입니다
(20,935 − 17,847 = 3,088). reset 뒤 첫 search만 memo table 청소를 치릅니다
([11장 11.5절](11_checkpoint_and_policy_engine.md)).

---

## 15.3 단계별 cycle 비용

| 자리 | 비용 | 근거 |
|---|---|---|
| dataset load | data word당 3 cycles × 8,192 data words = 24,576 cycles (약 246 µs) | [6장 6.8절](06_data_representation_and_memory_map.md#68-system-sram과-load) |
| Grover iteration 한 번 (1 PE) | Pass 1 512 + Pass 2 512 = 1,024 issue + drain | [9장](09_iteration_datapath_and_number_of_pes.md) |
| Grover iteration 한 번 (4 PEs) | Pass 1 128 + Pass 2 128 = 256 issue | [9장 9.4절](09_iteration_datapath_and_number_of_pes.md) |
| measurement Build (Single-Row Build → Dual-Row Build) | 512 → 256 cycles | [10장 10.3절](10_measurement_unit_and_microarchitecture.md) |
| measurement Select (Linear Select → Two-Level Select) | 최악 512 → 48회 비교 | [10장 10.4절](10_measurement_unit_and_microarchitecture.md) |
| policy memo table 청소 | 최신 main(a Checkpoint-Capacity of 3, 3-shot Lookahead) 381 cycles, Board-Verified Build 3,279 cycles (reset 뒤 첫 search와 epoch 한 바퀴) | [11장 11.5절](11_checkpoint_and_policy_engine.md) |

load는 search에 비하면 작습니다. 14-qubit dataset 전체 load가 246 µs 인데 Restart mode search 500개가
425,502 µs입니다. AHB를 burst로 올리지 않은 이유가 이것입니다
([7장 7.3절](07_bus_interface.md)).

---

## 15.4 Six-Stage Ablation

같은 500 workloads를 여섯 configuration으로 돌려 RTL cycle을 쟀습니다
([publication_6stage](../../hardware_bram/results/2026-09-08_publication_6stage/evidence.md)).

| 단계 | 총 cycle | 직전 대비 | 무엇이 바뀌었나 |
|---|---:|---:|---|
| Stage 1 | 42,308,335 | — | baseline. checkpoint 없음 |
| Stage 2 | 18,349,320 | -56.63% | checkpoint 도입 |
| Stage 3 | 11,246,755 | -38.71% | 4 PEs |
| Stage 4 | 10,385,795 | -7.66% | Checkpoint-Capacity · Lookahead-Shots를 줄임 |
| Stage 5 | 8,500,620 | -18.15% | Dual-Row Build |
| final configuration | 6,890,470 | -18.94% | Two-Level Select |

전체 6.1401×입니다.

결과를 요약하면 다음과 같습니다.

- checkpoint 도입으로 cycle이 56.63% 감소했습니다. 나머지 다섯 단계의 효과를 합친
  것보다 큰 폭입니다.
- Dual-Row Build와 Two-Level Select를 함께 적용하면 Stage 4 대비 33.7% 감소합니다. Measurement Unit도 512 rows를 두 번
  순회하므로 주요 병목에 해당합니다.
- Checkpoint-Capacity · Lookahead-Shots를 줄이면 cycle이 7.66% 감소하며 resource 사용량도 함께 줄어듭니다
  ([11장 11.6절](11_checkpoint_and_policy_engine.md)). 이 campaign은 workload마다 reset해 memo table 청소를 매번 치르므로
  Checkpoint-Capacity · Lookahead-Shots 축소의 몫이 크게 잡힙니다. 연달아 도는 bench500 · board에서는 -3.8% 입니다
  ([실험 18 「단계별 손익」](../reports/18_six_stage_ablation_comparison.md#단계별-손익)).

---

## 15.5 성능 지표 구분

위 표는 RTL cycle 축입니다. board wall-clock time 축의 speedup은 7.626×로 다릅니다.

| 축 | 값 |
|---|---|
| RTL cycle | 6.1401× |
| board wall-clock time | 7.626× |
| ORCA 1 core 대비 | 116,426× (단서 필요) |

서로 다른 세 지표를 섞어 speedup을 계산하지 않습니다. board와 RTL은 BBHT trajectory가 500/500 같지만 cycle
값 자체는 다릅니다: 과거 final configuration benchmark의 473/500이 정확히 3,279 cycles 차이입니다. 이 값은
compact memo table 적용 전 Board-Verified Build와 RTL의 기록입니다. Six-Stage Ablation campaign은
workload마다 새로 시작해서 memo table 청소를 매번 치르고, board와 `bench500`은 연달아 돌아 한
번만 치르기 때문입니다.

`bench250`과 `bench500` harness는 driver를 통해 workload를 연속 실행하므로 board 실행
조건에 더 가깝습니다. 같은 250 workloads에서 논리 결과는 250/250, cycle은 230/250건
일치합니다.

ORCA speedup에 붙일 단서는 [1장 1.5절](01_project_overview.md)에 있습니다.
