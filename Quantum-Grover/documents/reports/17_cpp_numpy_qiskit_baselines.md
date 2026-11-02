# 실험 17. C++ · NumPy · Qiskit baseline 비교

> [← 실험 16 세 revision의 board Predicate500](16_three_revisions_board_predicate500.md) · [index](index.md) · [실험 18 Six-Stage Ablation configuration과 implementation 방식별 비교 →](18_six_stage_ablation_comparison.md)

---

| 확인한 것 | 근거의 축 |
|---|---|
| 같은 algorithm을 최적화한 CPU software(C++ · NumPy · Qiskit Aer) 대비 FPGA의 위치 | server wall-clock time (i5-14600K E-core, 2026-10-05) 대 board `wall_us` (Arty A7-100T) |

accelerator와 같은 BBHT search를 C++ · NumPy · Qiskit Aer로 짜서 server에서 재고, board benchmark와 맞댄 실험입니다.
도구는 [`software/pc_grover_develop/`](../../software/pc_grover_develop/)에 있습니다. 기준 data는 둘입니다.

- 주 실험 Predicate500 (네 predicate × 다섯 가지 number of solutions × 100 seeds = 2,000) 대 2026-10-04 board
  ([실험 16](16_three_revisions_board_predicate500.md))
- 연속성 확인용 Common500 (`EQ` × 500) 대 2026-09-08 Board-Verified Build ([실험 12](12_board_verified_build_500_runs.md))

같은 C code를 ORCA와 server core 하나에서 돌린 비교는 [실험 19](19_orca_server_software_baseline.md)이고, 이 실험과
baseline code · board · 실행 환경이 달라 섞지 않습니다.

---

## 요약

- 같은 2,000 workloads에서 최종 FPGA(final configuration, 221.0 ms)는 policy 없는 Optimized C++ float32 1 core
  (764.6 ms)보다 3.46×, 가장 빠른 multi-core 실행(4 threads, 414.1 ms)보다 1.87× 빠릅니다.
- software에 같은 checkpoint policy나 all-j 재사용을 넣으면 차이는 1.03~1.55×로 줄어듭니다.
- policy 없는 Restart mode끼리는 Optimized C++ 4 threads(414.1 ms)가 FPGA Restart mode(479.0 ms)보다 빠릅니다.
- 독립 search를 동시에 돌리는 throughput은 CPU가 더 높습니다.
- 정확성: Bit-Exact C++와 board 결과가 2,000/2,000 같고, 교차 검사 33개가 모두 통과했습니다.

---

## 비교 model

| backend | 구현 | 수치 형식 | policy | 역할 |
|---|---|---|---|---|
| Optimized C++ | 공개 기법으로 최적화한 C++ | float32 / float64 | Restart mode | policy 없는 CPU baseline (주 기준) |
| State-Reuse C++ | Optimized C++ + state 재사용 | float32 / float64 | a Checkpoint-Capacity of 3 and 3-shot Lookahead · a Checkpoint-Capacity of 4 and 4-shot Lookahead · all-j | policy 효과 분리, software 재사용 성능 |
| Bit-Exact C++ | RTL과 bit 단위로 같은 C++ | Q1.22 integer | Restart mode · a Checkpoint-Capacity of 3 and 3-shot Lookahead · a Checkpoint-Capacity of 4 and 4-shot Lookahead · all-j | FPGA와 결과가 같은 software (같은 일 비교) |
| Qiskit Aer | circuit simulator | complex128 | Restart mode · a Checkpoint-Capacity of 3 and 3-shot Lookahead · all-j | circuit simulator 참고값 |
| NumPy | array 연산 | float64 | Restart mode · a Checkpoint-Capacity of 3 and 3-shot Lookahead · all-j | array 연산 참고값 |
| Python Reference Model | 팀 Python reference model | Q1.22 integer | Restart mode · a Checkpoint-Capacity of 3 and 3-shot Lookahead · a Checkpoint-Capacity of 4 and 4-shot Lookahead · all-j | 판정 기준. 시간도 같은 방식으로 잼 (참고) |
| FPGA | board benchmark | Q1.22 | a Checkpoint-Capacity of 3 and 3-shot Lookahead · Restart mode · DRAM all-j | 비교 대상 |

- policy `normal`은 shot마다 uniform superposition에서 다시 시작해 정해진 number of iterations를 모두 돌고, `k3h3` · `k4h4`는 hardware와 같은 checkpoint policy
  ([11장](../design_references/11_checkpoint_and_policy_engine.md)), `allj`는 만든 state를 전부 남기는 DRAM Variant 방식입니다.
  policy는 어디서 이어 계산할지만 바꾸므로 논리 결과는 같고 executed iterations만 줄어듭니다.
- 결과가 board와 bit 단위로 같은 backend는 Bit-Exact C++와 Python Reference Model뿐입니다. Optimized C++ · State-Reuse C++ · Qiskit Aer · NumPy는 float 계열이라 같은 policy끼리는
  workload마다 결과가 같지만, board와는 seed별 경로가 달라 distribution으로 비교합니다.
- FPGA 쪽 final configuration의 Checkpoint mode와 Restart mode는 같은 bitstream에서 mode만 바꾼 것입니다. 그 밖에 checkpoint memory가
  없는 No-Checkpoint Baseline([20장](../design_references/20_no_checkpoint_baseline.md)), DDR3의 DRAM all-j session
  ([21장](../design_references/21_dram_variant.md)), Common500 전용 1-PE bitstream(2026-09-08)이 있습니다.
- DRAM board 결과는 한 dataset의 100 seeds 사이에 state table을 계속 들고 있어 workload 사이에 caching하는 셈이므로
  software baseline과 직접 맞대지 않습니다. 같은 동작을 재현하는 Bit-Exact C++의 `--session` mode는 verification에만 씁니다.
- Qiskit Aer에 policy를 넣은 것(all-j · a Checkpoint-Capacity of 3 and 3-shot Lookahead)은 저장한 state에서 이어 돌리는 방식이라 simulator 안에서만 가능합니다. 실제
  quantum hardware는 state를 복사할 수 없습니다. 인용할 때 이 점을 밝힙니다.
- 팀 원본 `software/pc_grover_develop/team_models/numpy_model` · `qiskit_model`은 속도 비교에 쓰지 않고, 같은 workload · 같은 시계로
  맞대는 도구(`tools/compare_team_baselines.py`)로만 비교합니다.

### baseline을 이렇게 잡은 이유

- **Optimized C++가 주 기준인 이유.** Optimized C++는 표준 BBHT를 이미 공개된 기법(inversion about the mean으로 구현한 O(number of states) diffusion operator, loop fusion + SIMD, group
  prefix sum sampler)만으로 최적화했습니다. algorithm 전용 hardware는 같은 algorithm의 최적화 software와 맞대는 것이
  관행입니다(El-Araby 2023, Choi & Lee 2024, Hoefler & Belli 규칙 1). 우리 policy를 baseline에 넣으면 policy의 몫이
  사라지므로 State-Reuse C++로 따로 뒀습니다.
- **float32를 headline으로 쓴 이유.** x86에서는 float32가 가장 빠릅니다. Q1.22를 그대로 재현한 Bit-Exact C++ Restart mode는
  Optimized C++ float32보다 1.53× 느립니다. float32 기준 speedup이 가장 작게 나오는 보수적인 선택이고, 같은 fixed-point끼리의
  비교는 Bit-Exact C++로 합니다.
- **Python 대신 C++ 인 이유.** Grover iteration 1회당 search 시간은 Python Reference Model 152.9 µs, NumPy 23.5 µs, C++ 6.0~7.6 µs,
  FPGA 3.8 µs입니다. Python 계열은 언어 비용이 benchmark 대상보다 커서 주 기준으로 쓰지 않습니다.

---

## benchmark 규칙과 환경

| 열 | 재는 범위 | FPGA 대응 |
|---|---|---|
| `compute_ns` | state vector 계산만 (C++ · NumPy iteration loop, Qiskit은 Aer simulation 시간) | 별도 counter 없음 |
| `search_ns` | **search 전체**: number of iterations 뽑기 · policy · 계산 · measurement · 종료 판정. data · mask는 미리 준비해 둠 | `wall_us` (COMMAND ~ DONE) |
| `prep_ns` | dataset file 읽기 + oracle mask (dataset당) | DMA load (재지 않음) |
| `build_ns` | Qiskit circuit 생성 · transpile | — |
| `e2e_ns` | `prep_ns` + `build_ns` + `search_ns` | DMA + 설정 + search + 결과 읽기 (재지 않음) |

- 주 지표는 `search_ns`입니다. DMA · 설정 · 결과 읽기는 양쪽 모두 뺐습니다. board `wall_us`는 accelerator cycle
  시간보다 5~7 µs 큽니다(CPU polling).
- workload마다 warm-up 1회 뒤 C++ 5회, NumPy 3회, Qiskit Aer · Python Reference Model 1회 돌려 median을 씁니다. 속도비는 같은
  workload 집합의 sum끼리 나눕니다. workload별로 짝지은 비율은 경로가 같은 Bit-Exact C++와 board 사이에서만 뜻이 있습니다.
- 병렬 실행은 두 가지입니다. thread mode(`--threads`)는 한 state vector의 iteration을 여러 core가 나눠 latency를 줄이고 FPGA 4 PEs에
  대응합니다(4 threads가 4 PEs에 해당하는 software 구성). worker mode(`--workers`)는 독립 search 여러 개를 동시에 돌려 throughput을 높입니다.
  Two-Level Select에 해당하는 두 단 선택은 모든 C++ kernel의 기본 sampler가 이미 하고 있어 따로 켜지 않습니다. 그래서
  `CPP_SW_BEST_K3H3_*_T4` · `CPP_RTL_EXACT_K3H3_T4`가 final configuration과 같은 설계의 software 구현입니다.
- CPU는 Intel Core i5-14600K입니다. container(lxc)에서는 8 E-cores(CPU 12~19, 최대 4.0 GHz)만 쓸 수 있어 1 core
  실행을 CPU 13에 고정했습니다. P-core(5.3 GHz)에서 재면 software가 더 빨라질 수 있으므로, 인용할 때 "E-core"를
  밝힙니다. g++ 13.3, `-O3 -march=native`(AVX2), Python 3.12, numpy 2.4.6, qiskit 2.5.2, aer 0.17.2입니다.
- FPGA는 Arty A7-100T, accelerator 100 MHz입니다.

---

## 정확성 verification

| 검사 | 결과 |
|---|---|
| Bit-Exact C++ kernel ↔ RTL request number of iterations test vector | 256/256 bits 일치 |
| Bit-Exact C++ ↔ Python Reference Model (Common500, Restart mode · a Checkpoint-Capacity of 4 and 4-shot Lookahead · a Checkpoint-Capacity of 3 and 3-shot Lookahead) ↔ 2026-09-08 board | 7,403 shots의 number of iterations · 재개 위치 · executed iterations · measurement random number까지 불일치 0 |
| Bit-Exact C++ ↔ reference model expected result ↔ 2026-10-04 board 네 mode (Predicate500) | 각 2,000/2,000 일치 |
| Optimized C++ · Bit-Exact C++ oracle 네 종 (`DATA_COUNT` padding 포함) ↔ reference model | 통과 |
| 동봉 20 datasets ↔ 팀 generator 결과 (FNV-1a, SHA-256) | 일치 |
| backend · multi-core 교차 검사 (NumPy · Qiskit Aer = float C++, Python Reference Model = Bit-Exact C++, thread · worker 실행 = 1 core 실행) | 33개 모두 통과 |
| float ↔ RTL 경로 (최종 결과 · number of shots · requested iterations) | 96/2,000 일치 |
| float ↔ FPGA distribution test (조건 20개 × Mann-Whitney · KS) | p < 0.05가 2개, Bonferroni correction 뒤 0개 |

float 계열(Optimized C++ · State-Reuse C++ · NumPy · Qiskit Aer)과 RTL 계열(Bit-Exact C++ · Python Reference Model · FPGA)은 수치 형식과 measurement sampler가 달라 seed별 경로가
다릅니다. amplitude가 모두 같은 uniform superposition(0 iterations)에서도 `seed_meas = 1`이면 float 계열은 index 0, RTL 계열은 6을 고릅니다.
distribution test는 이번 sample에서 유의한 차이를 찾지 못했다는 뜻이지 distribution이 같다는 증명이 아닙니다. 96/2,000이 일치한
원인은 나눠 보지 않았습니다.

---

## 결과

### single search 시간 (Predicate500 2,000개, 1 core)

| backend | search total (ms) | FPGA final configuration 대비 | FPGA Restart mode 대비 |
|---|--:|--:|--:|
| FPGA final configuration (Checkpoint mode) | 221.0 | 1.00 | 0.46 |
| State-Reuse C++ all-j float32 | 228.1 | 1.03 | 0.48 |
| Bit-Exact C++ all-j | 337.3 | 1.53 | 0.70 |
| State-Reuse C++ a Checkpoint-Capacity of 3 and 3-shot Lookahead float32 | 404.6 | 1.83 | 0.84 |
| FPGA final configuration in Restart mode | 479.0 | 2.17 | 1.00 |
| Bit-Exact C++ a Checkpoint-Capacity of 3 and 3-shot Lookahead | 521.1 | 2.36 | 1.09 |
| FPGA No-Checkpoint Baseline | 621.2 | 2.81 | 1.30 |
| Optimized C++ float32 (주 기준) | 764.6 | 3.46 | 1.60 |
| Optimized C++ float64 | 976.6 | 4.42 | 2.04 |
| Bit-Exact C++ Restart mode | 1,169.4 | 5.29 | 2.44 |
| NumPy Restart mode | 3,006.5 | 13.60 | 6.28 |
| FPGA DRAM all-j session | 3,459.0 | 15.65 | 7.22 |
| Python Reference Model Restart mode | 19,133.9 | 86.57 | 39.95 |

FPGA 항목의 값은 [실험 16](16_three_revisions_board_predicate500.md)의 board wall-clock time sum입니다. float32는 float64보다
1.19~1.34× 빠릅니다. Qiskit Aer Restart mode(seed 앞 20개, 400 workloads)는 225,573 ms로 Optimized C++ float64의 1,197×이고, 약
65%가 Aer 호출 overhead라 headline에 쓰지 않습니다.

### checkpoint policy의 효과

| policy | executed iterations (float 계열) | executed iterations (RTL 계열) | Restart mode 대비 |
|---|--:|--:|--:|
| Restart mode | 127,976 | 125,106 | 1.00 |
| a Checkpoint-Capacity of 3 and 3-shot Lookahead | 38,373 | 37,659 | 0.30 |
| all-j (workload마다 새로) | 34,364 | 33,823 | 0.27 |

policy는 FPGA와 software 모두에서 효과가 있습니다. executed iterations는 3.3× 줄지만 measurement · 제어 비용은 그대로라 시간은 같은
bitstream에서 2.17×, software에서 1.89× 줄었습니다. number of solutions별로 Optimized C++ 1 core ÷ FPGA final configuration은 1 solution에서 4.17×로 가장
크고 256 solutions에서 1.86×로 가장 작습니다. search가 짧을수록 고정 비용의 비중이 커집니다.

### multi-core: search 안의 병렬화 (thread mode)

| backend · policy, 4 threads | search (ms) | 비교 FPGA | FPGA speedup |
|---|--:|---|--:|
| State-Reuse C++ a Checkpoint-Capacity of 3 and 3-shot Lookahead float32 | 316.1 | final configuration 221.0 | 1.43 |
| Bit-Exact C++ a Checkpoint-Capacity of 3 and 3-shot Lookahead | 342.7 | final configuration 221.0 | 1.55 |
| Bit-Exact C++ Restart mode | 491.5 | final configuration in Restart mode 479.0 | 1.03 |
| Optimized C++ Restart mode float32 | 414.1 | final configuration in Restart mode 479.0 | 0.86 (CPU가 빠름) |

core를 늘려도 FPGA final configuration에는 닿지 못합니다. 병렬화로 연산 부분은 줄지만 measurement · 제어 부분(약 163 ms)은 그대로
남습니다. Optimized C++ float32는 8 threads가 491.6 ms로 4 threads보다 느렸습니다. 8 threads가 L2를 따로 쓰는 E-core 두 묶음에 걸치기
때문으로 보이나 hardware counter로 확인하지 않았습니다.

### throughput: 독립 search 동시 실행 (8 workers)

초당 완료 search는 C++ float32 Restart mode 13,183회, all-j 34,476회, FPGA final configuration 9,048회(DMA 제외 환산)입니다. 8 workers는
한 search를 빠르게 하는 설정이 아니라 완료 건수를 늘리는 설정이라, CPU의 throughput 우위와 FPGA의 latency 우위가 함께
성립합니다. FPGA는 accelerator 하나가 135 BRAM tiles 중 116을 써서 같은 board에 accelerator를 더 넣기 어렵습니다. throughput으로
맞대려면 power당 throughput이 필요합니다.

### 시간 구성

iteration 1회 연산은 FPGA 4 PEs가 약 2.68 µs(RTL cycle 환산), software 4 cores가 1.96~2.61 µs로 비슷합니다. FPGA의 이점은
연산 바깥 부분(measurement · policy · 제어를 hardware에서 처리)에 있는 것으로 보이나, FPGA에 부분별 counter가 없어
추정입니다. FPGA DMA는 재지 않았습니다. dataset마다 load하면(20회) 결론이 바뀌지 않지만, workload마다
load하면(2,000회) 전체 시간이 A1 1 core와 비슷해질 수 있습니다.

### Common500 (Board-Verified Build와의 연속성)

Optimized C++ float32 1 core(186.7 ms) 대비 FPGA final configuration(55.8 ms)은 3.35×로 Predicate500의 3.46×와 비슷합니다. software all-j
float32(55.5 ms)는 FPGA와 거의 같습니다. 이전 1 PE bitstream의 Restart mode(425.5 ms)은 server E-core 하나의
Optimized C++ float32보다 2.28× 느렸습니다. ORCA 1 core 대비 speedup은 이 실험과 다른 축이라 섞지 않습니다
([1장 1.5절](../design_references/01_project_overview.md#15-성능-지표와-인용-기준)).

### 개발 VM의 예비 benchmark

같은 code를 2026-10-05에 개발 VM(cloud Xeon 2.8 GHz, 2 vCPU, `REPS=1 QISKIT_SEEDS=2`)에서도 돌렸습니다. run마다
20% 정도 흔들리는 환경이라 흐름 확인용이고 인용하지 않습니다. verification 항목은 위 표와 같이 모두 통과했습니다.
보고서는 [`pc_grover_result/2026-10-05_devvm/`](../../software/pc_grover_result/2026-10-05_devvm/2026-10-05_devvm.md)에 있습니다.

---

## 인용할 때

- 쓸 수 있는 주장은 셋입니다. 같은 algorithm을 공개 기법으로 최적화한 CPU software보다 1 core 기준 3.46×, 가장 빠른
  multi-core 실행(4 threads)보다 1.87× 빠릅니다. checkpoint policy는 executed iterations를 약 3.3× 줄이고 search 시간을 같은 bitstream에서
  2.17×, software에서 1.89× 줄입니다. 같은 일을 하는 Bit-Exact C++의 4 cores 구성보다 1.55× 빠릅니다.
- baseline의 절대 시간 · CPU(E-core) · number of cores · compile option을 함께 적습니다.
- policy 없는 Restart mode끼리는 CPU 4 threads가 빠르고, throughput은 CPU가 높다는 결과를 같이 밝힙니다.
- classical linear scan과는 비교하지 않습니다.

### 남은 일

| 작업 | 목적 |
|---|---|
| power benchmark (CPU RAPL · power meter, FPGA XADC) | search당 energy. 14 qubits에서는 CPU가 강해 energy efficiency가 가장 유력한 주장 축 |
| FPGA DMA · 설정 · 결과 읽기 benchmark | system 전체(E2E) 비교 |
| campaign 3회 이상 반복 | 시간 편차와 confidence interval |
| FPGA 부분별 counter | iteration · measurement · policy 병목 확정 |
| P-core benchmark, a Checkpoint-Capacity of 3 and 3-shot Lookahead의 2 · 8 threads 등 병렬 조합 추가 | 더 강한 CPU 구성에서 재평가 |
| No-Checkpoint Baseline과 DRAM session이 느린 원인, sampler 일치 실험 | Restart mode 사이 차이와 수치 형식 · sampler 영향 분리 |

---

## 다시 돌리는 법

```bash
cd software/pc_grover_develop/campaign
pip install -r requirements.txt     # numpy, scipy, qiskit, qiskit-aer (Python 3.10+)
bash run_all.sh                     # C++ build → verification → measurement → 교차 verification → 보고서
                                    # 결과는 software/pc_grover_result/<YYYY-MM-DD>_<호스트>/
```

`run_all.sh`는 `software/pc_grover_develop/cpp/build/`와 `software/pc_grover_result/` 에만 씁니다. reference model(`reference_model_develop/`),
Common500 · Predicate500 입력(`testbench_data/`), Predicate500 expected result · RTL test vector(`reference_model_data/`)는 제자리에서 읽기만 합니다. environment variable은 이렇습니다.

| variable | 기본 | 뜻 |
|---|---|---|
| `WORKLOAD` | `both` | `predicate500` · `common500` · `both` |
| `CORE` | 쓸 수 있는 CPU 중 두 번째 | 1 core 실행을 고정할 CPU. P-core를 쓸 수 있으면 P-core 번호를 줍니다 |
| `REPS` | `5` | C++ benchmark 반복 횟수 (NumPy 3, Qiskit 1 고정) |
| `SKIP_QISKIT` · `QISKIT_SEEDS` | `0` · `100` | Qiskit 생략, Qiskit은 seed 앞에서 지정한 개수만 (1 thread Predicate500 전체는 몇 시간) |
| `BASELINE_POLICIES` · `GOLDEN_POLICIES` | `normal allj k3h3` · `normal k3h3 allj` | NumPy · Qiskit과 reference model에서 돌릴 policy (`k4h4` 추가 가능) |
| `SKIP_GOLDEN` | `0` | reference model 시간 benchmark 생략 |
| `ENERGY` | `0` | `perf stat -e power/energy-pkg/`로 energy benchmark |
| `OUT` | `results/<호스트>_<날짜>` | 결과 directory |

결과 directory에서 볼 곳은 셋입니다.

| 무엇 | file |
|---|---|
| 결과가 맞는가 | `verification/*.txt`와 `*/verify_baselines_vs_cpp.txt`가 모두 PASS |
| 숫자 | `predicate500/report/report.md` |
| graph용 원자료 | `predicate500/report/summary_by_backend.csv` · `all_backends.csv` |
| benchmark 환경 | `environment.txt` (CPU · 쓸 수 있는 core · 고정 CPU와 최대 clock · virtualization · compiler · version) |

`runs/`의 file 이름은 `<configuration>_<정책>[_<정밀도>]_<실행 모드>[_<오라클>].csv`입니다. backend는 `cpp_sw`(Optimized C++ · State-Reuse C++) ·
`cpp_rtl`(Bit-Exact C++) · `numpy`(NumPy) · `qiskit`(Qiskit Aer) · `golden`(Python Reference Model), execution mode는 `1c`(1 core) · `T<n>`(thread mode, latency) · `W<n>`(worker mode, throughput)
입니다. file 한 줄이 workload 하나이고, 같은 이름의 `.json`이 합계 · 초당 search 수 · 환경을 담습니다.

### source 구성

| directory | 내용 |
|---|---|
| `cpp/include/` | 공통 계약(constant · random number · sampling range 경계 · oracle · timer), checkpoint policy · all-j library, Bit-Exact C++ integer kernel, Optimized C++ float kernel(SIMD), 상주 thread team(`spin_team.hpp`), BBHT search loop |
| `cpp/src/` · `cpp/Makefile` | `grover_bench.cpp` benchmark 실행기, `grover_single_run.cpp` verification용 단일 실행기. build는 `cpp/build/` |
| `python/` | Python 공통 benchmark 틀(`campaign.py`), NumPy · Qiskit Aer 공통 BBHT, NumPy · Qiskit Aer · Python Reference Model 실행기 |
| `tools/` | 경로 정의, Predicate500 dataset 생성과 hash 대조, verification 다섯 종, 팀 원본 비교, 보고서 생성 |
| `team_models/` | 팀 원본 NumPy · Qiskit model. 속도 비교에는 쓰지 않고 `tools/compare_team_baselines.py` 로만 맞댐 |
| `campaign/` | `run_all.sh`, `requirements.txt`. Predicate500 20 datasets는 `software/testbench_data/2026-10-05_predicate500/` |
| `software/pc_grover_result/` | `2026-10-05_server/` (server benchmark) · `2026-10-05_devvm/` (개발 VM 예비 benchmark) |

implementation에서 시간이 크게 갈린 곳입니다.

- C++ iteration kernel은 `noinline`입니다. inline되면 `__restrict` 정보가 사라져 scalar 경로로 빠지고 iteration당 6 µs가
  20 µs가 됐습니다.
- Grover iteration 1회가 state vector 1 pass입니다. state vector마다 다음 iteration의 2 × mean에 필요한 oracle 적용 sum을 같이 들고 다닙니다.
- thread mode는 search 실행기마다 한 번 만드는 상주 thread team이 vector의 고정된 부분을 맡고, iteration마다 spin barrier 한 번으로
  동기화합니다. 처음 쓴 OpenMP 방식은 iteration마다 barrier와 thread 깨우기 비용이 붙어 server E-core에서 8 threads가
  1 thread보다 7× 느렸습니다. 쓸 수 있는 CPU보다 많은 `--threads`는 시작 전에 거부합니다.
- measurement sampler는 Bit-Exact C++만 RTL integer sampler이고 나머지는 float sampler(128-group prefix sum)를 공유해 Optimized C++ · State-Reuse C++ · Qiskit Aer · NumPy가 1:1로
  대조됩니다.
- NumPy all-j는 미리 잡은 128-row library에 바로 계산합니다. 저장마다 128 KB를 새로 잡으면 iteration당 19 µs가
  165 µs가 됐습니다.

---

## 근거

- server benchmark(2026-10-05, `Intern-Ubuntu`): [`pc_grover_result/2026-10-05_server/`](../../software/pc_grover_result/2026-10-05_server/2026-10-05_server.md).
  위 표의 수치는 그 안의 [`predicate500/report/report.md`](../../software/pc_grover_result/2026-10-05_server/predicate500/report/report.md)
  와 같고, benchmark 환경은 `environment.txt`, campaign console 출력은 `run.log`입니다. 다시 만들 수 있는
  `verification/predicate500_datasets_regenerated/`만 빼고 올렸습니다.
- 개발 VM 예비 benchmark: [`pc_grover_result/2026-10-05_devvm/`](../../software/pc_grover_result/2026-10-05_devvm/2026-10-05_devvm.md)
- 비교한 board 결과: [실험 16](16_three_revisions_board_predicate500.md) (Predicate500), [실험 12](12_board_verified_build_500_runs.md) (Common500)
