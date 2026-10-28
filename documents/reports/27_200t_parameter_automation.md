# 실험 27. 200T 기준 checkpoint policy와 parameter 실험 자동화

> [← 실험 26](26_policy_seed_first_rtl.md) · [실험 보고서 index](index.md) · [실험 28 →](28_policy_single_action_exit.md)

| 정한 것 / 확인할 것 | 근거의 축 | 상태 |
|---|---|---|
| 200T의 실제 부품과 clock을 설정으로 받고 Checkpoint-Capacity · Lookahead-Shots · number of PEs · Build row 수를 같은 runner로 변경 | JSON → adapter → RTL simulation → OOC synthesis·routing → 표·heatmap | implementation 완료 |
| Build를 4 rows/cycle로 확장하고 기존 Born rule을 보존 | 단독 RTL 비교, Common500 통합 RTL | [evidence bundle](../../hardware_bram/results/2026-10-27_200t_dse/evidence.md) |
| 7-shot · 8-shot Lookahead에서 speculative planning root까지 Lookahead-Shots 전체를 공급 | Iteration-Count Predictor 독립 test vector, Checkpoint-Capacity · Lookahead-Shots 변경 통합 RTL | [Checkpoint-Capacity · Lookahead-Shots 확인 evidence bundle](../../hardware_bram/results/2026-10-27_200t_kh_smoke/evidence.md) |
| 200T에서 policy · Measurement Microarchitecture · number of PEs 최적화 후 최종 Checkpoint-Capacity · Lookahead-Shots를 선택 | full RVX SoC routing, 전체 workload, board | 후속 단계 |

## 목표와 이름

전체 block는 **checkpoint policy engine**, 그 안에서 demand·예측·search·계획 공급을
조정하는 controller는 **Policy Scheduler**라고 부릅니다. 현재의 exact restricted-B policy,
Iteration-Count Predictor, Plan Queue, Checkpoint Planner, Checkpoint Executor가 각각 policy 선택·예측·queue·checkpoint slot 할당·실행을
맡습니다. 이번 변경은 이 block들을 새 이름으로 한 번 더 감싸는 대신, 기존 RTL의 Lookahead-Shots와
measurement 병렬도를 실제로 설정 가능하게 하고 재현 가능한 실행 경로를 연결합니다.

순서는 다음과 같습니다.

1. 200T에서 기존 4 PEs · Triple-Row Build · Seed-First Branch and Bound with Single-Action Exit policy를 기준점으로 재현합니다.
2. policy의 선택 결과를 Exhaustive DFS reference model과 맞대고, 노출된 stall을 줄입니다.
3. Build row 수 또는 number of PEs를 올리고 실제 memory bandwidth·DSP·BRAM·routing 한계를 확인합니다.
4. 같은 workload로 Checkpoint-Capacity · Lookahead-Shots 전 범위를 실행하고, Build row 수 · number of PEs 조합마다 heatmap을 만듭니다.
5. RTL 정확성·전체 SoC resource·timing을 통과한 cell 중 실제 실행 시간이 가장 짧은 것을 고릅니다.

Measurement Unit이나 Iteration Datapath가 빨라지면 policy를 숨길 실행 시간이 줄어들므로 policy 단독 cycle만으로 최적점을
고르지 않습니다. Checkpoint-Capacity · Lookahead-Shots를 바꾸면 policy latency와 실제 Grover iteration이 함께 바뀝니다. 전체 cycle,
policy stall, resource와 timing을 함께 보아야 합니다. 200T에 맞는 최종 policy나 최적 Checkpoint-Capacity · Lookahead-Shots를
이번 확인만으로 확정하지는 않습니다.

## RTL 변경

### Lookahead-Shots 전달

기존 `grover_shadow_j`는 출력 bus가 여덟 request 폭이어도 실제로는 일곱 request에서
멈췄습니다. 한 request 앞서 계산하는 speculative planning root는 첫 미래 request를 자신의 현재 request로
소비하므로 미래 request를 Lookahead-Shots만큼 더 보려면 총 (Lookahead-Shots + 1)개가 필요합니다. `FUTURE_COUNT`로 생성 개수를
정하고, Accelerator Core는 7-shot · 8-shot Lookahead에 필요한 request를 끝까지 보존합니다. Lookahead-Shots가 작을 때에는 기존 생성
개수와 latency를 유지합니다. 독립 verification은 BBHT budget·shot cap 경계의 문맥 재시작과 rejection sampling에서 버린
random number도 포함합니다.

### measurement 병렬도

`bbht_grover_main_ip.BUILD_ROWS_PER_CYCLE`이 Build의 실제 rows/cycle 수(1~4)를 선택합니다.
이 실험 당시 이름은 `MEAS_BUILD_ROWS`였고, 0이면 옛 `MEAS_M1_ENABLE` · `MEAS_M3_ENABLE` 설정을 따랐습니다(2026-10-28에 `BUILD_ROWS_PER_CYCLE` 하나로 합침).
Two-Level Select는 Build 병렬도와 다른 축의 최적화이므로 Build 병렬도
variable에 섞지 않습니다. runner의 `build_rows`와 `hier_select`를 따로 둡니다.

4 rows 경로는 기존 4 PEs의 row group memory 응답을 매 cycle 받아 squarer 네 개에 공급합니다.
row weight는 `row mod 4`로 나눈 네 BRAM bank에 한 번씩 씁니다. 네 row의 sum은 균형 adder tree로
만들어 prefix sum에 더하며, 32 rows group의 끝은 항상 네 번째 lane에 있으므로 그때 정확한
prefix sum을 기록합니다. Select·Reread와 Measurement PRNG 규칙은 그대로 사용합니다. 4→3 변환용 residual
FIFO는 이 경로에 필요하지 않습니다.

### WNS를 위한 register

확인한 source의 PREP·memo table·tie-break pipeline은 남아 있습니다. 최근 변경은 memo table 응답이
search 제어 clock enable을 늦추던 분기 의존성을 정리한 것이며, WNS 때문에 추가한 register 전부를
제거한 변경이 아닙니다([실험 26](26_policy_seed_first_rtl.md)). 200T에서 단계별 latency와
routing 결과를 확인한 뒤, 불필요한 단계만 별도 실험으로 합칠 수 있습니다. Plan Queue,
BRAM read alignment, Triple-Row Build residual FIFO와 timing 분할 register는 역할이 서로 다릅니다.

## 설정 하나로 실행

runner는 [dse.py](../../hardware_bram/sim/dse.py), 시작 설정은
[dse_200t.json](../../hardware_bram/sim/dse_200t.json)입니다. 기본값은 AX7A200B의 실제 부품,
accelerator 100 MHz, a Checkpoint-Capacity of 3 · 3-shot Lookahead · 4 PEs, Build 3·4 rows, Seed-First Branch and Bound with Single-Action Exit, Common500 전체입니다.
**100T resource 제한을 적용하지 않습니다.**

```bash
python3 hardware_bram/sim/test_dse.py
python3 hardware_bram/sim/dse.py \
  --config hardware_bram/sim/dse_200t.json \
  --out hardware_bram/results/YYYY-MM-DD_200t_dse \
  --stages prepare,policy,sim,synth,route,report \
  --vivado /path/to/Vivado/bin/vivado
```

Vivado 없는 host에서는 `--stages prepare,policy,sim,report`로 RTL까지 확인할 수 있습니다.
`sim`은 해당 cell의 policy 대조가 없으면 먼저 실행합니다. `synth`·`route`는 성공한 policy·통합
verification이 있어야 실행합니다. 전체 RVX SoC implementation과 board 운용은 별도이며
[17장](../design_references/17_board_operation.md#179-원격-200t-board-ax7a200b)의 경로를 사용합니다.
이 runner의 OOC timing은 내부 accelerator clock 경로의 결과이고, SoC·CDC·외부 I/O timing의
통과를 뜻하지 않습니다.

`grid`의 array를 바꾸면 Cartesian product로 cell을 만듭니다. 예를 들어 Checkpoint-Capacity는 `[3,4]`, Lookahead-Shots는
`[1,2,3,4,5,6,7,8]`, `build_rows`는 `[2,3,4]`로 두면 48 cells입니다. RTL 본문이나 configuration별
directory를 손으로 복사하지 않습니다. configuration별 adapter는 실행 directory에 생성됩니다.

각 directory에는 설정·parameter·source hash·source 사본, Exhaustive DFS policy 대조, workload별 예상
executed iterations, 통합 CSV와 단계별 log가 남습니다. source·설정을 바꾸면 새 실행 directory를 요구하며,
같은 실행을 다시 부르면 성공한 단계를 건너뜁니다. policy 단독 시험은 실험의 source 사본을
compile합니다. 통합 시험은 결과 · shot count · requested iterations를 외부 기준 trace와, executed iterations를 그 Checkpoint-Capacity · Lookahead-Shots의
정확한 policy replay와 맞댑니다. `BENCH_LIMIT`은 Common500 순서를 유지한 앞부분만 실행하며,
짧은 실행 결과에는 workload 수를 명시합니다.

`summary.csv`와 configuration별 Checkpoint-Capacity · Lookahead-Shots PNG를 생성합니다. `nominal_time_us`는 설정 clock을 가정한
RTL cycle 환산이고 benchmark 시간이 아닙니다. routing WNS/WHS는 routing이 끝난 경우에만 넣고,
미실행 cell은 `unmeasured`로 표시합니다. 실패한 timing을 통과한 cell로 취급하지 않습니다.

## 현재 범위와 다음 구조 확장

| 축 | 현재 자동 실행 가능 | 그 밖의 값에 필요한 RTL 작업 |
|---|---|---|
| Checkpoint-Capacity | 3, 4 | a Checkpoint-Capacity of 5 이상: metadata·tuple·Checkpoint Planner/Checkpoint Executor·slot address·정렬·memo table rank와 실제 amplitude 저장까지 확장 |
| Lookahead-Shots | 1~8 | 9-shot Lookahead 이상: Lookahead window·단계 address·비용 폭·memo table 범위 확장 |
| number of PEs | 1, 2, 4 | 8 PEs 이상: 8-bank read/write·adder tree·accumulator 제어 확장 |
| Build rows/cycle | 1~4, 병렬 Build는 4 PEs | 5 rows 이상: amplitude memory bandwidth·squarer·row weight 쓰기 bank 확장 |

200T에 자리가 있다고 해서 고정 폭의 네 checkpoint slot이 다섯 checkpoint slot으로 바뀌지는 않습니다.
이 범위를 벗어난 설정은 조용히 기존 경로로 돌아가지 않고 실행 전에 거부합니다.
a Checkpoint-Capacity of 5와 8 PEs의 구조 확장이 끝나면 runner의 지원 범위를 넓혀 같은 pipeline을 사용합니다.
policy의 후속 최적화 후보는 일반화된 compact memo table, epoch 청소 비용, 후보 Scan throughput과
실행 중 겹침입니다. 실제 stall profile을 먼저 보고 implementation 순서를 정합니다.
