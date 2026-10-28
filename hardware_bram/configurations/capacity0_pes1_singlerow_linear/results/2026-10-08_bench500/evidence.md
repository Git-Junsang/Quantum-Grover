# Stage 1 build bench500 — checkpoint build의 mode0보다 executed iterations · shot마다 2 cycles 적음

## 무엇인가

checkpoint hardware를 뺀 `capacity0_pes1_singlerow_linear` build(`CHECKPOINT_ENABLE=0`, 1 PE, Single-Row Build · Linear Select)를 2026-10-07 여섯 configuration과 같은
`make -C hardware_bram/sim bench500 CONFIGURATION=capacity0_pes1_singlerow_linear` 로 돌렸습니다. Six-Stage Ablation 과 board benchmark의
"Stage 1"은 이 build가 아니라 `capacity4_lookahead4_pes1_singlerow_linear` build를 mode0으로 돌린 값이라, 둘이 cycle까지 같은지
확인하려는 것입니다. 이 build는 checkpoint가 없어 mode1 request도 Restart mode로 돕니다.

## 확정 수치

| | `capacity0_pes1_singlerow_linear` build | `capacity4_lookahead4_pes1_singlerow_linear` build mode0 | 차이 |
|---|---:|---:|---:|
| executed iterations | 31,424 | 31,424 | 0 |
| 총 shot 수 | 7,403 | 7,403 | 0 |
| cycle | **42,230,681** | 42,308,335 | **-77,654 (-0.18%)** |
| 논리 넷 (result_index · trial_count · L_BBHT · actual_iter) | — | — | 500/500 같음 |

workload별로 보면 500개 모두 `capacity0_pes1_singlerow_linear` 쪽이 정확히 **2 × (executed iterations + shot 수)** cycles 적습니다.
합계로 2 × (31,424 + 7,403) = 77,654 cycles입니다. 이 build의 mode0 · mode1은 500/500 같습니다.

## 읽는 법

checkpoint가 없는 1 PE build는 옛 단일 amplitude memory를 쓰고, Measurement Unit의 `AMP_READ_LATENCY` 가 1입니다.
checkpoint build는 checkpoint memory를 거쳐 2입니다(`hardware_bram/src/bbht_grover_main_ip.v` 의
`grover_measure_verify` parameter). 차이가 executed iterations와 shot 수에 정확히 비례하는 것이 이 읽기 latency와
맞습니다. 다만 iteration · shot마다 2 cycles가 어느 읽기에서 나오는지는 파형으로 확인하지 않았습니다.

4 PEs에서는 이런 차이가 없습니다. `no_checkpoint_baseline`(checkpoint 없는 4 PEs)는 checkpoint build의 Restart mode와 cycle까지
같았습니다([20장](../../../../../documents/design_references/20_no_checkpoint_baseline.md)). 4 PEs는 checkpoint
유무와 무관하게 같은 amplitude memory를 쓰기 때문입니다.

## 인용할 때

- 논문의 Stage 1 시간은 지금처럼 `capacity4_lookahead4_pes1_singlerow_linear` mode0(Six-Stage Ablation · board benchmark와 같은 정의)을 쓰고, resource는
  `capacity0_pes1_singlerow_linear` build를 씁니다. 그 경우 "Stage 1의 시간은 checkpoint build의 Restart mode" 라고 적어
  두십시오. checkpoint를 뺀 build의 시간은 0.18% 빠릅니다.
- RTL cycle 축입니다. 이 build는 board에서 돌리지 않았습니다.

## file

| file | 내용 |
|---|---|
| `bench500.csv` | testbench 원본 1,000 rows (500 workloads × 두 mode, 두 mode 모두 Restart mode 경로) |
