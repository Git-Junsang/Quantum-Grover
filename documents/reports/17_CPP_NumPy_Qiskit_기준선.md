# 실험 17. C++ · NumPy · Qiskit 기준선 비교

> [← 실험 16 세 판의 보드 Predicate500](16_세_판_보드_Predicate500.md) · [index](index.md) · [실험 18 6단계 모델과 구현 방식별 비교 →](18_6단계_모델_비교.md)

---

| 확인한 것 | 근거의 축 |
|---|---|
| 같은 알고리즘을 최적화한 CPU 소프트웨어(C++ · NumPy · Qiskit Aer) 대비 FPGA 의 위치 | 서버 실경과 시간 (i5-14600K E 코어, 2026-10-05) 대 보드 `wall_us` (Arty A7-100T) |

가속기와 같은 BBHT 탐색을 C++ · NumPy · Qiskit Aer 로 짜서 서버에서 재고, 보드 실측과 맞댄 실험입니다.
도구는 [`software/pc_grover_develop/`](../../software/pc_grover_develop/) 에 있습니다. 기준 데이터는 둘입니다.

- 주 실험 Predicate500 (네 술어 × M 5종 × 시드 100 = 2,000) 대 2026-10-04 보드
  ([실험 16](16_세_판_보드_Predicate500.md))
- 연속성 확인용 Common500 (`EQ` × 500) 대 2026-09-08 보드 정본 ([실험 12](12_보드_정본_500런.md))

같은 C 를 ORCA 와 서버 코어 하나에서 돌린 비교는 [실험 19](19_ORCA_서버_SW_기준선.md)이고, 이 실험과
기준선 코드 · 보드 · 실행 환경이 달라 섞지 않습니다.

---

## 요약

- 같은 2,000 워크로드에서 최종 FPGA(K3/H3-E4-M2, 221.0 ms)는 정책 없는 최적화 C++ float32 1코어
  (764.6 ms)보다 3.46배, 가장 빠른 멀티코어(T4, 414.1 ms)보다 1.87배 빠릅니다.
- SW 에 같은 체크포인트 정책이나 all-j 재사용을 넣으면 차이는 1.03~1.55배로 줄어듭니다.
- 정책 없는 Normal 끼리는 C++ T4(414.1 ms)가 FPGA Normal(479.0 ms)보다 빠릅니다.
- 독립 탐색을 동시에 돌리는 처리량은 CPU 가 더 높습니다.
- 정확성: 비트 정확 C++ 와 보드 결과가 2,000/2,000 같고, 교차 검사 33개가 모두 통과했습니다.

---

## 비교 모델

| ID | 모델 | 수치 형식 | 정책 | 역할 |
|---|---|---|---|---|
| A1 | 최적화 C++ | float32 / float64 | Normal | 정책 없는 CPU 기준선 (주 기준) |
| A2 | A1 + 상태 재사용 | float32 / float64 | K3H3 · K4H4 · all-j | 정책 효과 분리, SW 재사용 성능 |
| B | 비트 정확 C++ | Q1.22 정수 | Normal · K3H3 · K4H4 · all-j | FPGA 와 결과가 같은 SW (같은 일 비교) |
| C | Qiskit Aer | complex128 | Normal · K3H3 · all-j | 회로 시뮬레이터 참고값 |
| D | NumPy | float64 | Normal · K3H3 · all-j | 배열 연산 참고값 |
| G | 팀 Python 기준모델 | Q1.22 정수 | Normal · K3H3 · K4H4 · all-j | 판정 기준. 시간도 같은 방식으로 잼 (참고) |
| FPGA | 보드 실측 | Q1.22 | K3H3 · Normal · DRAM all-j | 비교 대상 |

- 정책 `normal` 은 시도마다 처음부터 `j` 번 반복, `k3h3` · `k4h4` 는 하드웨어와 같은 체크포인트 정책
  ([11장](../design_references/11_체크포인트와_정책_엔진.md)), `allj` 는 만든 상태를 전부 남기는 DRAM 갈래 방식입니다.
  정책은 어디서 이어 계산할지만 바꾸므로 논리 결과는 같고 물리 반복만 줄어듭니다.
- 결과가 보드와 비트 단위로 같은 모델은 B 와 G 뿐입니다. A1 · A2 · C · D 는 float 계열이라 같은 정책끼리는
  워크로드마다 결과가 같지만, 보드와는 시드별 경로가 달라 분포로 비교합니다.
- FPGA 쪽 K3/H3-E4-M2 와 Normal-E4-M2 는 같은 비트스트림에서 모드만 바꾼 것입니다. 그 밖에 체크포인트 메모리가
  없는 Normal-E4([20장](../design_references/20_체크포인트_없는_BRAM_판.md)), DDR3 의 DRAM all-j 세션
  ([21장](../design_references/21_DRAM_갈래.md)), Common500 전용 E1(2026-09-08) 이 있습니다.
- DRAM 보드 결과는 한 데이터셋의 시드 100개 사이에 상태 표를 계속 들고 있어 워크로드 사이에 캐싱하는 셈이므로
  SW 기준선과 직접 맞대지 않습니다. 같은 동작을 재현하는 B 의 `--session` 모드는 검증에만 씁니다.
- Qiskit + 정책(C 의 all-j · K3H3)은 저장한 상태에서 이어 돌리는 방식이라 시뮬레이터 안에서만 가능합니다. 실제
  양자 장치는 상태를 복사할 수 없습니다. 인용할 때 이 점을 밝힙니다.
- 팀 원본 `software/pc_grover_develop/team_models/numpy_model` · `qiskit_model` 은 속도 비교에 쓰지 않고, 같은 워크로드 · 같은 시계로
  맞대는 도구(`tools/compare_team_baselines.py`)로만 비교합니다.

### 기준선을 이렇게 잡은 이유

- **A1 이 주 기준인 이유.** A1 은 표준 BBHT 를 이미 공개된 기법(평균 반사 O(N) 확산, 루프 융합 + SIMD, 그룹
  누적합 샘플러)만으로 최적화했습니다. 알고리즘 전용 하드웨어는 같은 알고리즘의 최적화 SW 와 맞대는 것이
  관행입니다(El-Araby 2023, Choi & Lee 2024, Hoefler & Belli 규칙 1). 우리 정책을 기준선에 넣으면 정책의 몫이
  사라지므로 A2 로 따로 뒀습니다.
- **float32 를 헤드라인으로 쓴 이유.** x86 에서는 float32 가 가장 빠릅니다. Q1.22 를 그대로 재현한 B Normal 은
  A1 float32 보다 1.53배 느립니다. float32 기준 배수가 가장 작게 나오는 보수적인 선택이고, 같은 고정소수점끼리의
  비교는 B 로 합니다.
- **Python 대신 C++ 인 이유.** 반복 1회당 탐색 시간은 Python 기준모델 152.9 µs, NumPy 23.5 µs, C++ 6.0~7.6 µs,
  FPGA 3.8 µs 입니다. Python 계열은 언어 비용이 측정 대상보다 커서 주 기준으로 쓰지 않습니다.

---

## 측정 규칙과 환경

| 열 | 구간 | FPGA 대응 |
|---|---|---|
| `compute_ns` | 상태벡터 계산만 (C++ · NumPy 반복 루프, Qiskit 은 Aer 시뮬레이션 시간) | 별도 카운터 없음 |
| `search_ns` | **탐색 전체**: `j` 뽑기 · 정책 · 계산 · 측정 · 종료 판정. 데이터 · 마스크는 준비된 상태 | `wall_us` (COMMAND ~ DONE) |
| `prep_ns` | 데이터셋 파일 읽기 + 오라클 마스크 (데이터셋당) | DMA 적재 (미측정) |
| `build_ns` | Qiskit 회로 생성 · transpile | — |
| `e2e_ns` | `prep_ns` + `build_ns` + `search_ns` | DMA + 설정 + 탐색 + 결과 읽기 (미측정) |

- 주 지표는 `search_ns` 입니다. DMA · 설정 · 결과 읽기는 양쪽 모두 뺐습니다. 보드 `wall_us` 는 가속기 사이클
  시간보다 5~7 µs 큽니다(CPU 폴링).
- 워크로드마다 워밍업 1회 뒤 C++ 5회, NumPy 3회, Qiskit · 기준모델 1회 반복해 중앙값을 씁니다. 속도비는 같은
  워크로드 집합의 합끼리 나눕니다. 워크로드별로 짝지은 비율은 경로가 같은 B 와 보드 사이에서만 뜻이 있습니다.
- 병렬 실행은 두 가지입니다. T 모드(`--threads`)는 한 상태벡터의 반복을 여러 코어가 나눠 지연을 줄이고 FPGA E4 에
  대응합니다(`T4` 가 E4 의 SW 판). W 모드(`--workers`)는 독립 탐색 여러 개를 동시에 돌려 처리량을 높입니다.
  M2 의 계층 선택은 모든 C++ 코어의 기본 샘플러가 이미 계층 탐색이라 따로 켜지 않습니다. 그래서
  `CPP_SW_BEST_K3H3_*_T4` · `CPP_RTL_EXACT_K3H3_T4` 가 K3/H3-E4-M2 와 같은 설계의 SW 판입니다.
- CPU 는 Intel Core i5-14600K 입니다. 컨테이너(lxc)에서는 E 코어 8개(CPU 12~19, 최대 4.0 GHz)만 쓸 수 있어 1코어
  실행을 CPU 13 에 고정했습니다. P 코어(5.3 GHz)에서 재면 SW 가 더 빨라질 수 있으므로, 인용할 때 "E 코어" 를
  밝힙니다. g++ 13.3, `-O3 -march=native`(AVX2), Python 3.12, numpy 2.4.6, qiskit 2.5.2, aer 0.17.2 입니다.
- FPGA 는 Arty A7-100T, 가속기 100 MHz 입니다.

---

## 정확성 검증

| 검사 | 결과 |
|---|---|
| B 코어 ↔ RTL 요청 `j` 정답 벡터 | 256/256 비트 일치 |
| B ↔ Python 기준모델 (Common500, Normal · K4H4 · K3H3) ↔ 2026-09-08 보드 | attempt 7,403개의 `j` · 재개 위치 · 물리 반복 · 측정 임계값까지 불일치 0 |
| B ↔ 기준모델 기대값 ↔ 2026-10-04 보드 네 모드 (Predicate500) | 각 2,000/2,000 일치 |
| A · B 오라클 네 종 (`DATA_COUNT` 패딩 포함) ↔ 기준모델 | 통과 |
| 동봉 데이터셋 20개 ↔ 팀 생성기 결과 (FNV-1a, SHA-256) | 일치 |
| 백엔드 · 멀티코어 교차 검사 (NumPy · Qiskit = C++ float, 기준모델 = B, T · W = 1코어) | 33개 모두 통과 |
| float ↔ RTL 경로 (최종 결과 · 시도 수 · L) | 96/2,000 일치 |
| float ↔ FPGA 분포 검정 (조건 20개 × Mann-Whitney · KS) | p < 0.05 가 2개, Bonferroni 보정 뒤 0개 |

float 계열(A · NumPy · Qiskit)과 RTL 계열(B · 기준모델 · FPGA)은 수치 형식과 측정 샘플러가 달라 시드별 경로가
다릅니다. 진폭이 같은 `j = 0` 균일 상태에서도 `seed_meas = 1` 이면 float 는 인덱스 0, RTL 은 6 을 고릅니다.
분포 검정은 이번 표본에서 유의한 차이를 찾지 못했다는 뜻이지 분포가 같다는 증명이 아닙니다. 96/2,000 이 일치한
원인은 나눠 보지 않았습니다.

---

## 결과

### 단일 탐색 시간 (Predicate500 2,000개, 1코어)

| 모델 | 탐색 합계 (ms) | 최종 FPGA 대비 | FPGA Normal 대비 |
|---|--:|--:|--:|
| FPGA K3/H3-E4-M2 (최종) | 221.0 | 1.00 | 0.46 |
| A2 all-j float32 | 228.1 | 1.03 | 0.48 |
| B all-j | 337.3 | 1.53 | 0.70 |
| A2 K3H3 float32 | 404.6 | 1.83 | 0.84 |
| FPGA Normal-E4-M2 | 479.0 | 2.17 | 1.00 |
| B K3H3 | 521.1 | 2.36 | 1.09 |
| FPGA 체크포인트 없는 Normal-E4 | 621.2 | 2.81 | 1.30 |
| A1 float32 (주 기준) | 764.6 | 3.46 | 1.60 |
| A1 float64 | 976.6 | 4.42 | 2.04 |
| B Normal | 1,169.4 | 5.29 | 2.44 |
| NumPy Normal | 3,006.5 | 13.60 | 6.28 |
| FPGA DRAM all-j 세션 | 3,459.0 | 15.65 | 7.22 |
| Python 기준모델 Normal | 19,133.9 | 86.57 | 39.95 |

FPGA 행의 값은 [실험 16](16_세_판_보드_Predicate500.md)의 보드 실경과 합입니다. float32 는 float64 보다
1.19~1.34배 빠릅니다. Qiskit Normal(시드 앞 20개, 400 워크로드)은 225,573 ms 로 A1 float64 의 1,197배이고, 약
65% 가 Aer 호출 오버헤드라 헤드라인에 쓰지 않습니다.

### 체크포인트 정책의 효과

| 정책 | 실제 반복 (float 계열) | 실제 반복 (RTL 계열) | Normal 대비 |
|---|--:|--:|--:|
| Normal | 127,976 | 125,106 | 1.00 |
| K3H3 | 38,373 | 37,659 | 0.30 |
| all-j (워크로드마다 새로) | 34,364 | 33,823 | 0.27 |

정책은 FPGA 와 SW 모두에서 효과가 있습니다. 반복은 3.3배 줄지만 측정 · 제어 비용은 그대로라 시간은 같은
비트스트림에서 2.17배, SW 에서 1.89배 줄었습니다. 타겟 수별로 A1 1코어 ÷ 최종 FPGA 는 M = 1 에서 4.17배로 가장
크고 M = 256 에서 1.86배로 가장 작습니다. 탐색이 짧을수록 고정 비용의 비중이 커집니다.

### 멀티코어: 탐색 안의 병렬화 (T 모드)

| 정책 · 모델, T4 | 탐색 (ms) | 비교 FPGA | FPGA 가 빠른 배수 |
|---|--:|---|--:|
| A2 K3H3 float32 | 316.1 | K3/H3-E4-M2 221.0 | 1.43 |
| B K3H3 (비트 정확) | 342.7 | K3/H3-E4-M2 221.0 | 1.55 |
| B Normal (비트 정확) | 491.5 | Normal-E4-M2 479.0 | 1.03 |
| A1 Normal float32 | 414.1 | Normal-E4-M2 479.0 | 0.86 (CPU 가 빠름) |

코어를 늘려도 최종 FPGA 에는 닿지 못합니다. 병렬화로 연산 구간은 줄지만 측정 · 제어 구간(약 163 ms)은 그대로
남습니다. A1 float32 는 T8 이 491.6 ms 로 T4 보다 느렸습니다. 8스레드가 L2 를 따로 쓰는 E 코어 두 묶음에 걸치기
때문으로 보이나 하드웨어 카운터로 확인하지 않았습니다.

### 처리량: 독립 탐색 동시 실행 (W8)

초당 완료 탐색은 C++ float32 Normal 13,183회, all-j 34,476회, FPGA 최종 구성 9,048회(DMA 제외 환산)입니다. W8 은
한 탐색을 빠르게 하는 설정이 아니라 완료 건수를 늘리는 설정이라, CPU 의 처리량 우위와 FPGA 의 지연 우위가 함께
성립합니다. FPGA 는 엔진 하나가 BRAM 135타일 중 116을 써서 같은 보드에 엔진을 더 넣기 어렵습니다. 처리량으로
맞대려면 전력당 처리량이 필요합니다.

### 시간 구간

반복 1회 연산은 FPGA E4 가 약 2.68 µs(RTL 사이클 환산), SW 4코어가 1.96~2.61 µs 로 비슷합니다. FPGA 의 이점은
연산 바깥 구간(측정 · 정책 · 제어를 하드웨어에서 처리)에 있는 것으로 보이나, FPGA 에 구간별 카운터가 없어
추정입니다. FPGA DMA 는 재지 않았습니다. 데이터셋마다 적재하면(20회) 결론이 바뀌지 않지만, 워크로드마다
적재하면(2,000회) 전체 시간이 A1 1코어와 비슷해질 수 있습니다.

### Common500 (보드 정본과의 연속성)

A1 float32 1코어(186.7 ms) 대비 최종 FPGA(55.8 ms)는 3.35배로 Predicate500 의 3.46배와 비슷합니다. SW all-j
float32(55.5 ms)는 FPGA 와 거의 같습니다. 이전 E1 비트스트림의 Normal(425.5 ms)은 서버 E 코어 하나의 A1 float32
보다 2.28배 느렸습니다. ORCA 1코어 대비 배수는 이 실험과 다른 축이라 섞지 않습니다
([1장 1.5절](../design_references/01_프로젝트_개요.md#15-성능-지표와-인용-기준)).

### 개발 VM 의 예비 측정

같은 코드를 2026-10-05 에 개발 VM(클라우드 Xeon 2.8 GHz, 2 vCPU, `REPS=1 QISKIT_SEEDS=2`)에서도 돌렸습니다. 실행마다
20% 정도 흔들리는 환경이라 흐름 확인용이고 인용하지 않습니다. 검증 항목은 위 표와 같이 모두 통과했습니다.
보고서는 [`pc_grover_result/2026-10-05_devvm/`](../../software/pc_grover_result/2026-10-05_devvm/2026-10-05_devvm.md) 에 있습니다.

---

## 인용할 때

- 쓸 수 있는 주장은 셋입니다. 같은 알고리즘을 공개 기법으로 최적화한 CPU SW 보다 1코어 기준 3.46배, 가장 빠른
  멀티코어(T4)보다 1.87배 빠릅니다. 체크포인트 정책은 실제 반복을 약 3.3배 줄이고 탐색 시간을 같은 비트스트림에서
  2.17배, SW 에서 1.89배 줄입니다. 같은 일을 하는 비트 정확 C++ 의 4코어 구성보다 1.55배 빠릅니다.
- 기준선의 절대 시간 · CPU(E 코어) · 코어 수 · 컴파일 옵션을 함께 적습니다.
- 정책 없는 Normal 끼리는 CPU T4 가 빠르고, 처리량은 CPU 가 높다는 결과를 같이 밝힙니다.
- 고전 선형 스캔과는 비교하지 않습니다.

### 남은 일

| 작업 | 목적 |
|---|---|
| 전력 측정 (CPU RAPL · 전력계, FPGA XADC) | 탐색당 에너지. Q14 에서는 CPU 가 강해 에너지 효율이 가장 유력한 주장 축 |
| FPGA DMA · 설정 · 결과 읽기 측정 | 시스템 전체(E2E) 비교 |
| 캠페인 3회 이상 반복 | 시간 편차와 신뢰구간 |
| FPGA 구간 카운터 | 반복 · 측정 · 정책 병목 확정 |
| P 코어 측정, K3H3 T2 · T8 등 병렬 조합 추가 | 더 강한 CPU 구성에서 재평가 |
| 체크포인트 없는 빌드와 DRAM 세션이 느린 원인, 샘플러 일치 실험 | Normal 사이 차이와 수치 형식 · 샘플러 영향 분리 |

---

## 다시 돌리는 법

```bash
cd software/pc_grover_develop/campaign
pip install -r requirements.txt     # numpy, scipy, qiskit, qiskit-aer (Python 3.10+)
bash run_all.sh                     # C++ 빌드 → 검증 → 측정 → 교차 검증 → 보고서
                                    # 결과는 software/pc_grover_result/<YYYY-MM-DD>_<호스트>/
```

`run_all.sh` 는 `software/pc_grover_develop/cpp/build/` 와 `software/pc_grover_result/` 에만 씁니다. 골든 모델(`golden_develop/`),
Common500 · Predicate500 입력(`testbench_data/`), Predicate500 기대값 · RTL 벡터(`golden_data/`)는 제자리에서 읽기만 합니다. 환경 변수는 이렇습니다.

| 변수 | 기본 | 뜻 |
|---|---|---|
| `WORKLOAD` | `both` | `predicate500` · `common500` · `both` |
| `CORE` | 쓸 수 있는 CPU 중 두 번째 | 1코어 실행을 고정할 CPU. P 코어를 쓸 수 있으면 P 코어 번호를 줍니다 |
| `REPS` | `5` | C++ 반복 측정 횟수 (NumPy 3, Qiskit 1 고정) |
| `SKIP_QISKIT` · `QISKIT_SEEDS` | `0` · `100` | Qiskit 생략, Qiskit 은 시드 앞 K개만 (1스레드 Predicate500 전체는 몇 시간) |
| `BASELINE_POLICIES` · `GOLDEN_POLICIES` | `normal allj k3h3` · `normal k3h3 allj` | NumPy · Qiskit 과 기준모델에서 돌릴 정책 (`k4h4` 추가 가능) |
| `SKIP_GOLDEN` | `0` | 기준모델 시간 측정 생략 |
| `ENERGY` | `0` | `perf stat -e power/energy-pkg/` 로 에너지 측정 |
| `OUT` | `results/<호스트>_<날짜>` | 결과 폴더 |

결과 폴더에서 볼 곳은 셋입니다.

| 무엇 | 파일 |
|---|---|
| 결과가 맞는가 | `verification/*.txt` 와 `*/verify_baselines_vs_cpp.txt` 가 모두 PASS |
| 숫자 | `predicate500/report/report.md` |
| 그래프용 원자료 | `predicate500/report/summary_by_backend.csv` · `all_backends.csv` |
| 측정 환경 | `environment.txt` (CPU · 쓸 수 있는 코어 · 고정 CPU 와 최대 클럭 · 가상화 · 컴파일러 · 판본) |

`runs/` 의 파일 이름은 `<모델>_<정책>[_<정밀도>]_<실행 모드>[_<오라클>].csv` 입니다. 모델은 `cpp_sw`(A) ·
`cpp_rtl`(B) · `numpy`(D) · `qiskit`(C) · `golden`(G), 실행 모드는 `1c`(1코어) · `T<n>`(지연) · `W<n>`(처리량)
입니다. 파일 한 행이 워크로드 하나이고, 같은 이름의 `.json` 이 합계 · 초당 탐색 수 · 환경을 담습니다.

### 소스 구성

| 폴더 | 내용 |
|---|---|
| `cpp/include/` | 공통 계약(상수 · 난수 · m 경계 · 오라클 · 타이머), 체크포인트 정책 · all-j 라이브러리, B 정수 코어, A float 코어(SIMD), 상주 스레드 팀(`spin_team.hpp`), BBHT 탐색 루프 |
| `cpp/src/` · `cpp/Makefile` | `grover_bench.cpp` 벤치 실행기, `grover_single_run.cpp` 검증용 단일 실행기. 빌드는 `cpp/build/` |
| `python/` | Python 공통 측정 틀(`campaign.py`), NumPy · Qiskit 공통 BBHT, 모델 D · C · G 실행기 |
| `tools/` | 경로 정의, Predicate500 데이터셋 생성과 해시 대조, 검증 다섯 종, 팀 원본 비교, 보고서 생성 |
| `team_models/` | 팀 원본 NumPy · Qiskit 모델. 속도 비교에는 쓰지 않고 `tools/compare_team_baselines.py` 로만 맞댐 |
| `campaign/` | `run_all.sh`, `requirements.txt`. Predicate500 데이터셋 20개는 `software/testbench_data/2026-10-05_predicate500/` |
| `software/pc_grover_result/` | `2026-10-05_server/` (서버 측정) · `2026-10-05_devvm/` (개발 VM 예비 측정) |

구현에서 시간이 크게 갈린 곳입니다.

- C++ 반복 커널은 `noinline` 입니다. 인라인되면 `__restrict` 정보가 사라져 스칼라 경로로 빠지고 반복당 6 µs 가
  20 µs 가 됐습니다.
- 반복 1회가 상태 1패스입니다. 상태마다 다음 반복의 2 × 평균에 필요한 오라클 적용 합을 같이 들고 다닙니다.
- 지연 모드는 엔진당 한 번 만드는 상주 스레드 팀이 벡터의 고정 구간을 맡고, 반복마다 스핀 barrier 한 번으로
  동기화합니다. 처음 쓴 OpenMP 방식은 반복마다 barrier 와 스레드 깨우기 비용이 붙어 서버 E 코어에서 8스레드가
  1스레드보다 7배 느렸습니다. 쓸 수 있는 CPU 보다 많은 `--threads` 는 시작 전에 거부합니다.
- 측정 샘플러는 B 만 RTL 정수 샘플러이고 나머지는 float 샘플러(128그룹 누적분포)를 공유해 A · C · D 가 1:1 로
  대조됩니다.
- NumPy all-j 는 미리 잡은 128행 라이브러리에 바로 계산합니다. 저장마다 128 KB 를 새로 잡으면 반복당 19 µs 가
  165 µs 가 됐습니다.

---

## 근거

- 서버 측정(2026-10-05, `Intern-Ubuntu`): [`pc_grover_result/2026-10-05_server/`](../../software/pc_grover_result/2026-10-05_server/2026-10-05_server.md).
  위 표의 수치는 그 안의 [`predicate500/report/report.md`](../../software/pc_grover_result/2026-10-05_server/predicate500/report/report.md)
  와 같고, 측정 환경은 `environment.txt`, 캠페인 콘솔 출력은 `run.log` 입니다. 다시 만들 수 있는
  `verification/predicate500_datasets_regenerated/` 만 빼고 올렸습니다.
- 개발 VM 예비 측정: [`pc_grover_result/2026-10-05_devvm/`](../../software/pc_grover_result/2026-10-05_devvm/2026-10-05_devvm.md)
- 비교한 보드 결과: [실험 16](16_세_판_보드_Predicate500.md) (Predicate500), [실험 12](12_보드_정본_500런.md) (Common500)
