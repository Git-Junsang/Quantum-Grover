# Checkpoint-Capacity · Lookahead-Shots × Measurement Microarchitecture × policy search mode 비교 근거

상태: **진행 중.** Exhaustive DFS(policy 최적화 전)의 Checkpoint-Capacity · Lookahead-Shots 전 범위 통합 benchmark가 아직 돌고 있어,
"최적화 전" 열은 a Checkpoint-Capacity of 3 · 3-shot Lookahead 한 cell만 있습니다.

아래에서 Dual-Row Build는 Dual-Row Build · Two-Level Select, Triple-Row Build는 Triple-Row Build · Two-Level Select를 줄여 부른 것입니다.

| 항목 | 내용 |
|---|---|
| workload | Common500 (500 workloads, 7,403 결정) |
| 축 | RTL cycle, Verilator 통합 bench500. board benchmark 없음 |
| configuration | Triple-Row Build / Dual-Row Build Accelerator Core × policy search mode 0 · 5 · 6 × Checkpoint-Capacity 3 · 4 × Lookahead-Shots 1~8 |
| 만드는 법 | policy search mode 6 configuration의 adapter 사본에서 Checkpoint-Capacity · Lookahead-Shots · policy search mode만 바꾸고 `BENCH_VDEFS=-DGP_MEAS_M3_DEFAULT=0` 으로 Dual-Row Build를 만듦 (`scripts/`) |

## 1. 통합 benchmark (`integrated_bench500.csv`)

모든 실행이 BBHT trajectory 500/500, Plan Queue miss 0 입니다. 아래는 Checkpoint mode cycle 합계입니다.

| Checkpoint-Capacity | Lookahead-Shots | Dual-Row Build, Exhaustive DFS | Triple-Row Build, Exhaustive DFS | Triple-Row Build, policy search mode 6 | Dual-Row Build, policy search mode 6 |
|:-:|:-:|---:|---:|---:|---:|
| 3 | 3 | 5,255,084 | 4,680,014 | **4,566,996** | 5,195,091 |
| 4 | 3 | benchmark 중 | benchmark 중 | 4,568,102 | 5,186,381 |
| 4 | 4 | benchmark 중 | benchmark 중 | 4,579,695 | **5,173,588** |
| 4 | 5 | benchmark 중 | benchmark 중 | 4,629,844 | 5,206,040 |

- policy 최적화 후 최적 cell은 Triple-Row Build에서 a Checkpoint-Capacity of 3 · 3-shot Lookahead, Dual-Row Build에서 a Checkpoint-Capacity of 4 · 4-shot Lookahead입니다. Triple-Row Build는 policy를 숨길 시간이 짧아
  최적 cell이 작은 쪽으로 옮겨갑니다.
- **Triple-Row Build의 a Checkpoint-Capacity of 3 · 3-shot Lookahead는 잰 모든 Dual-Row Build cell보다 11.7 % 이상 빠릅니다.** Dual-Row Build는 stall 0 · 최소 executed iterations(8,668)를
  가정해도 4,913,780 으로 Triple-Row Build의 a Checkpoint-Capacity of 3 · 3-shot Lookahead보다 7.6 % 느립니다(아래 model 계수).
- 7-shot · 8-shot Lookahead는 Iteration-Count Predictor가 미래 request를 7개만 만들어 통합 실행에서 6-shot Lookahead와 같은 선택을 합니다
  (executed iterations가 6-shot Lookahead와 같음). 이 두 열은 "7-shot · 8-shot Lookahead를 쓴 hardware" 가 아니라 "지금 구조에서
  7-shot · 8-shot Lookahead로 설정한 결과" 입니다.

## 2. model (`fit_m3.json`, `fit_m2.json`, `scripts/fit40.py`)

| model | 식 | 맞춘 data | verification |
|---|---|---|---|
| 결정별 policy latency | software Seed-First Branch and Bound search 특징의 선형 결합 (policy search mode별) | Checkpoint-Capacity 3 · 4 × Lookahead-Shots 1~8 policy 단독 RTL, 결정별 | cell 하나 빼고 예측: cell 합계 ±11 % |
| stall | `c0·결정수 + c1·Σ첫결정latency + c2·Σmax(0, latency − tau)` | 통합 benchmark, Checkpoint-Capacity 3 · 4 × Lookahead-Shots 1~6 | — |
| 전체 cycle | `F + b·executed iterations + stall` | 같음 | cell 하나 빼고 예측: Triple-Row Build 0.30 %, Dual-Row Build 0.26 % 이내 |

| 계수 | Triple-Row Build | Dual-Row Build |
|---|---:|---:|
| `tau` (숨길 수 있는 latency) | 220 | 400 |
| `F` (고정 부분) | 2,019,166 | 2,648,421 |
| `b` (executed iterations당 cycle) | 261.35 | 261.35 |

고정 부분(`F`)의 차이 629,255 는 실험 25 가 구조 계산으로 예측한 Triple-Row Build 절감량과 같습니다.

## 3. 40 cells 추정 (`kh40_m3.csv`, `kh40_m2.csv`, `heatmap_*.png`)

Checkpoint-Capacity 1 · 2 · 5는 RTL 이 없어 software 특징 + model로 추정했습니다(그림의 `E`). Checkpoint-Capacity 3 · 4 × Lookahead-Shots 1~6은 benchmark(`M`),
Lookahead-Shots 7~8은 policy 단독 benchmark + stall model(`R`)입니다.

Triple-Row Build, policy search mode 6 상위: a Checkpoint-Capacity of 5 · 4-shot Lookahead 4,465,910(`E`) · a Checkpoint-Capacity of 5 · 3-shot Lookahead 4,481,368(`E`) · a Checkpoint-Capacity of 5 · 5-shot Lookahead 4,531,442(`E`) · a Checkpoint-Capacity of 3 · 3-shot Lookahead 4,566,996(`M`).
a Checkpoint-Capacity of 5는 다섯 번째 amplitude checkpoint slot이 100T BRAM 을 넘어 지금은 만들 수 없습니다(실험 25).

## 4. resource 무제한 가정, Checkpoint-Capacity 1~10 × Lookahead-Shots 1~10 (`kh100_m3_mode6_whatif.csv`, `scripts/fit100.py`)

가정: memo table initialization 없음(epoch tag 확장), Iteration-Count Predictor가 Lookahead-Shots만큼 미래 request를 공급, amplitude 저장 무제한.
Checkpoint-Capacity > 4 또는 Lookahead-Shots > 8의 policy latency는 model 외삽입니다.

- Checkpoint-Capacity ≥ 3이면 모두 4-shot Lookahead가 최적. Checkpoint-Capacity는 5~6부터 saturation(4-shot Lookahead에서 a Checkpoint-Capacity of 5의 8,953 → a Checkpoint-Capacity of 10의 8,802 executed iterations)
- 최소: a Checkpoint-Capacity of 10 · 4-shot Lookahead 4,390,683. 4-shot Lookahead에서 Checkpoint-Capacity 7~10은 0.2 % 안이라 순위는 의미 없음
- 같은 가정의 a Checkpoint-Capacity of 3 · 3-shot Lookahead 4,559,238 대비 약 3.7 %. 최소 executed iterations(8,586) · stall 0의 lower bound는 4,263,091

## 5. stall 분해 (Triple-Row Build, policy search mode 6, model)

| cell | stall | 첫 결정 | `tau` 초과분 | 그중 memo table initialization 몫 |
|---|---:|---:|---:|---:|
| a Checkpoint-Capacity of 3 · 3-shot Lookahead | 41,466 | 23,214 | 4,477 | 5,624 |
| a Checkpoint-Capacity of 4 · 4-shot Lookahead | 206,051 | 37,230 | 155,046 | 95,558 |

a Checkpoint-Capacity of 4 · 4-shot Lookahead stall의 절반 가까이가 255 결정마다 memo table 전체(4,372 entries)를 지우는 비용입니다.
a Checkpoint-Capacity of 3 · 3-shot Lookahead는 실험 21 의 compact memo table(381 entries) 덕에 이 비용이 작습니다. a Checkpoint-Capacity of 4 · 4-shot Lookahead에도 같은 압축을
적용하면 a Checkpoint-Capacity of 3 · 3-shot Lookahead보다 약 1.8 % 빨라질 것으로 추정되지만 아직 해 보지 않았습니다.

## 재현

`scripts/` 의 도구는 작업 당시 scratch 경로를 그대로 담고 있습니다. 저장소에서 다시 쓰려면
경로 constant(`S`)를 바꿔야 합니다. Exhaustive DFS 기준 trace 는 `make_traces.py`, policy 단독 RTL 은
`run_cell_vl.sh`(testbench 에 결정별 `ROW` 출력을 더한 사본 사용), 결정별 software 특징은
`sw_features.py`, model · 표 · 그림은 `fit40.py` · `plot40.py` · `compare4.py` · `fit100.py` 입니다.
`kh_sweep.py` · `policy_search_method1.py` · `tb_policy_kh_sweep.sv` 는 실험 22~24 의 도구로,
아직 저장소에 commit되지 않았습니다.
