# sw_benchmark — Q14 BBHT/Grover SW 비교 모델·측정

팀 SW 트리(`software/`) 안에 **추가만 한** 폴더다. FPGA Grover 가속기와 비교할 SW 모델 전부와, 그 모델들을 같은 기준으로 검증하고 재는 도구가 들어 있다.

- **팀 파일은 하나도 고치지 않는다.** `software/` 안의 기존 폴더(`contract/`, `host/`, `models/`, `experiments/`, `results/`, `rtl_vectors/`)는 그대로 둔다. CSR 생성 파일과 보드 호스트 연동도 영향받지 않는다.
- **팀 코드와 데이터는 제자리에서 읽기만 한다.** 기준모델, Common500 입력, Predicate500 기대값, RTL 벡터가 여기에 해당하고, 사본을 만들지 않는다.
- **쓰는 곳은 `sw_benchmark/` 안뿐이다.** `build/`와 `results/`에만 쓰고, 팀 폴더에 `__pycache__`도 만들지 않는다.

```bash
cd software/sw_benchmark
pip install -r requirements.txt
bash run_all.sh            # 빌드 → 검증 → 측정 → 교차검증 → 보고서 (results/<host>_<날짜>/)
```

---

## 1. 모델 한눈에 보기

| ID           | 모델                                              | 논문에서 역할                                                   | 구현                                                                                                             | 결과 CSV의`backend` 이름                                                                                                                          |
| ------------ | ------------------------------------------------- | --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| **A1** | C++ SW 최고, 표준 BBHT                            | **메인 SW 기준선** (FPGA와 맞붙는 상대)                   | `cpp/` → `build/grover_bench --engine sw --policy normal`                                                   | `CPP_SW_BEST_NORMAL_F64` / `_F32`                                                                                                               |
| A2           | C++ SW 최고 + 우리 정책                           | 보조: 정책이 SW에서도 효과 있는지                               | `cpp/` → `--engine sw --policy allj\|k3h3\|k4h4`                                                              | `CPP_SW_BEST_ALLJ_F64`, `CPP_SW_BEST_K3H3_F64` …                                                                                               |
| A2-E4        | A2 K3H3를 4코어로 (**K3/H3-E4-M2의 SW 판**) | 보드 최종 구성과 같은 설계를 SW로                               | `--engine sw --policy k3h3 --threads 4`                                                                        | `CPP_SW_BEST_K3H3_F32_T4` / `_F64_T4`                                                                                                           |
| B-E4         | B K3H3를 4코어로 (같은 설계, 비트 단위 동일)      | 보드와 결과까지 같은 SW 판                                      | `--engine rtl --policy k3h3 --threads 4`                                                                       | `CPP_RTL_EXACT_K3H3_T4`                                                                                                                           |
| **B**  | C++ RTL 동일                                      | 정확성 근거: 보드와 결과가 비트 단위로 같음                     | `cpp/` → `--engine rtl --policy normal\|k3h3\|k4h4\|allj`                                                      | `CPP_RTL_EXACT_NORMAL`, `CPP_RTL_EXACT_K3H3` …                                                                                                 |
| C            | Qiskit Aer (표준 / + 정책)                        | 참고값: 양자 회로 시뮬레이터로 하면                             | `baselines/qiskit_baseline.py --policy …`                                                                     | `QISKIT_AER_NORMAL_F64`, `QISKIT_AER_K3H3_F64` …                                                                                               |
| D            | NumPy (표준 / + 정책)                             | 참고값: 흔한 Python 수치 라이브러리로 하면                      | `baselines/numpy_baseline.py --policy …`                                                                      | `NUMPY_NORMAL_F64`, `NUMPY_ALLJ_F64` …                                                                                                         |
| G            | 팀 Python 기준모델                                | 정답지: B와 보드를 판정하는 기준. 시간도 같은 방식으로 잼(참고) | 팀`models/rtl_reference_model/` 그대로, 실행은 `baselines/golden_baseline.py --policy normal\|k3h3\|k4h4\|allj` | `GOLDEN_PY_NORMAL`, `GOLDEN_PY_K3H3` …                                                                                                         |
| FPGA         | Arty A7-100T 보드                                 | 비교 대상                                                       | 보드 실측 CSV (6절)                                                                                              | `FPGA_K3H3_E4_M2`, `FPGA_NORMAL_E4_M2`, `FPGA_NOCKPT_NORMAL_E4`, `FPGA_DRAM_ALLJ_SESSION`, (Common500) `FPGA_NORMAL_E1`, `FPGA_K4H4_E1` |

정책 이름은 다음과 같다.

- `normal`: 표준 BBHT. 시도마다 처음부터 j번 반복한다.
- `k3h3` / `k4h4`: HW와 같은 체크포인트 정책. 중간 상태 3개/4개를 남기고, 앞으로 3/4개 요청을 내다본다.
- `allj`: 탐색 중 만든 상태를 전부 남긴다(DRAM 빌드 방식).

정책은 어떤 상태에서 이어 계산할지만 바꾼다. 요청 j와 측정은 그대로라서 논리 결과는 같고 물리 반복 수만 줄어든다.

### 헷갈리기 쉬운 것

- **결과가 보드와 "완전히" 같은 모델은 B와 G뿐이다.** 둘은 RTL과 같은 정수 연산(Q1.22)과 정수 샘플러를 쓴다.
- **A1·A2·C·D는 소수점(float) 계열이다.** 이 넷은 같은 정책끼리 workload별 결과가 완전히 같다(결과 위치, 시도 수, L, 물리 반복 수). 보드와는 seed별 경로가 달라서 분포(통계 검정)로 비교한다. 정수와 소수점의 반올림 차이 때문이다.
- **메인 비교는 두 줄이다.**
  - A1 ↔ `FPGA_NORMAL_E4_M2`: 같은 알고리즘, HW 가속만의 효과
  - A1 ↔ `FPGA_K3H3_E4_M2`: 설계 전체의 효과
- **DRAM 보드(`FPGA_DRAM_ALLJ_SESSION`)는 SW 기준선과 직접 비교하지 않는다.** 한 데이터셋의 seed 100개 사이에 상태 표를 계속 들고 있어서 workload 사이에 캐싱하는 셈이다. 같은 동작을 재현하는 B의 `--session` 모드는 검증에만 쓴다.
- **Qiskit + 정책(C의 allj/k3h3)은 시뮬레이터 안에서만 가능한 방식이다.** 저장한 상태에서 이어 돌리는데, 실제 양자 장치는 상태를 복사할 수 없다. 논문에 쓸 때 이 점을 밝힌다.
- **`software/models/numpy_model`, `software/models/qiskit_model`(팀 원본)은 속도 비교에 쓰지 않는다.** 속도 비교에는 D·C를 쓴다. 이유는 `docs/TEAM_CODE_REVIEW.md`에 있다. 팀 원본과의 비교는 `tools/compare_team_baselines.py`로 한다.

---

## 2. 폴더 구조

```text
software/                          (팀 SW 트리 — 기존 폴더는 그대로, 수정 없음)
├── contract/  host/  models/  experiments/  results/  rtl_vectors/  requirements.txt
└── sw_benchmark/                  ← 새로 추가한 폴더 (이 문서)
    ├── README.md
    ├── Makefile                   C++ 빌드 → build/grover_bench, build/grover_single_run
    ├── run_all.sh                 전체 캠페인: 빌드 → 검증 → 측정 → 교차검증 → 보고서
    ├── requirements.txt           numpy, scipy, qiskit, qiskit-aer
    │
    ├── cpp/                       ── C++ 모델 A1 · A2 · B
    │   ├── include/
    │   │   ├── q14_contract.hpp       공통 계약: 상수, j·측정 난수, m 경계, 오라클 4종, 데이터·seed 읽기, 타이머
    │   │   ├── checkpoint_policy.hpp  K3H3/K4H4 체크포인트 정책, all-j 라이브러리 (A2와 B가 같이 씀)
    │   │   ├── core_rtl_exact.hpp     모델 B 코어: Q1.22 정수 반복 + 정수 측정 (RTL과 비트 단위 동일)
    │   │   ├── core_sw_float.hpp      모델 A 코어: float64/float32 반복(SIMD) + float 측정
    │   │   ├── spin_team.hpp          반복 하나를 여러 코어가 나누는 상주 스레드 팀 (E4의 SW 판, A·B 공통)
    │   │   └── bbht_search.hpp        BBHT 탐색 루프 (j 뽑기 → 정책 → 반복 → 측정 → 종료 규칙)
    │   └── src/
    │       ├── grover_bench.cpp       벤치 실행기: 시간 구간, 반복, 1코어/멀티코어, CSV·JSON, RAPL 에너지
    │       └── grover_single_run.cpp  검증 도구용 단일 실행기 (마스크 / 탐색 1회 / 코어만)
    │
    ├── baselines/                 ── Python 백엔드 (모델 C · D · G)
    │   ├── campaign.py                Python 백엔드 공통 측정 틀: workload 순회, 워밍업·반복·중앙값, 처리량(프로세스) 모드, CSV·JSON
    │   ├── bbht_float_common.py       NumPy·Qiskit 공통: 난수, BBHT 루프, 정책, float 샘플러
    │   ├── numpy_baseline.py          모델 D: NumPy 엔진 + 실행 명령
    │   ├── qiskit_baseline.py         모델 C: Qiskit Aer 엔진 + 실행 명령
    │   └── golden_baseline.py         모델 G: 팀 기준모델을 그대로 불러 같은 방식으로 시간 측정
    │
    ├── tools/                     ── 검증·보고서 도구
    │   ├── repo_paths.py                         모든 경로(팀 폴더 포함)를 한곳에서 정의
    │   ├── make_predicate500_datasets.py         Predicate500 데이터셋 20개 생성 + 해시 대조 (팀 생성기 사용)
    │   ├── verify_cpp_rtl_vs_golden_predicate500.py   B ↔ G 기대값 ↔ 10/04 보드 3종
    │   ├── verify_cpp_rtl_vs_golden_common500.py      B ↔ G (attempt 단위) ↔ 09/08 보드
    │   ├── verify_cpp_rtl_vectors.py             B 코어 ↔ RTL 요청 j 벡터 256개 (비트 단위)
    │   ├── verify_cpp_oracles.py                 A·B 오라클 4종 (EQ/LT/GT/RANGE, DATA_COUNT 패딩) ↔ G
    │   ├── verify_baselines_vs_cpp.py            C·D ↔ 같은 정책의 A (workload별 결과·물리 반복 수)
    │   ├── compare_team_baselines.py             팀 원본 NumPy·Qiskit ↔ C·D, 같은 workload·같은 시계
    │   └── summarize_results.py                  전체 CSV + 보드 결과 → 시간·처리량·동치성·분포 검정 보고서
    │
    ├── data/                      ── 팀 트리에 없는 입력만
    │   ├── predicate500_datasets/          Predicate500 데이터셋 20개 (팀 생성기로 만든 것, 해시 검증됨)
    │   └── board_20261004_predicate500/    10/04 보드 result.csv 3개 사본 (하드웨어 폴더가 없을 때 사용)
    │
    ├── docs/
    │ 
    └── results/                   실행 결과 (run_all.sh가 여기에만 씀)
```

---

## 3. 빠른 시작

```bash
cd software/sw_benchmark
pip install -r requirements.txt     # Python 3.10+
make                                # g++ (C++17, OpenMP)
bash run_all.sh                     # 전체: results/<host>_<날짜>/
```

`run_all.sh` 옵션(환경 변수):

| 변수                  | 기본                      | 뜻                                                                             |
| --------------------- | ------------------------- | ------------------------------------------------------------------------------ |
| `WORKLOAD`          | `both`                  | `predicate500`(메인) / `common500` / `both`                              |
| `CORE`              | 쓸 수 있는 CPU 중 두 번째 | 1코어 실행을 고정할 CPU 번호. 이 프로세스가 쓸 수 없는 번호면 시작 전에 멈춘다 |
| `REPS`              | `5`                     | C++ 반복 측정 횟수 (NumPy 3, Qiskit 1 고정)                                    |
| `SKIP_QISKIT`       | `0`                     | `1`이면 Qiskit 생략 (1스레드 Predicate500 전체는 몇 시간)                    |
| `QISKIT_SEEDS`      | `100`                   | Qiskit은 seed 앞 K개만                                                         |
| `BASELINE_POLICIES` | `normal allj k3h3`      | NumPy·Qiskit에서 돌릴 정책 (`k4h4` 추가 가능)                               |
| `GOLDEN_POLICIES`   | `normal k3h3 allj`      | 팀 기준모델에서 돌릴 정책 (`k4h4` 추가 가능)                                 |
| `SKIP_GOLDEN`       | `0`                     | `1`이면 팀 기준모델 시간 측정 생략                                           |
| `ENERGY`            | `0`                     | `1`이면 `perf stat -e power/energy-pkg/`로 에너지 측정                     |
| `OUT`               | `results/<host>_<날짜>` | 결과 폴더                                                                      |

결과물: 자세한 설명은 아래 **4.1 결과 폴더 구조**에 있다.

### 4.1 결과 폴더 구조

`bash run_all.sh`를 돌리면 `sw_benchmark/results/<호스트>_<날짜_시각>/` 하나가 생긴다(`OUT`으로 바꿀 수 있다). 다른 곳에는 아무것도 쓰지 않는다. 그 밖에 `make`가 `sw_benchmark/build/`에 실행 파일 두 개를 만든다.

```text
results/<호스트>_<날짜_시각>/
├── environment.txt              측정 환경: CPU 모델, 물리/논리 코어 수, 쓸 수 있는 CPU, 1코어 고정 CPU와 최대 클럭,
│                                가상화 종류, lscpu -e 표, 컴파일러, Python·numpy·qiskit 버전, governor
├── energy/                      ENERGY=1일 때만 채워짐: 실행마다 perf stat 에너지 기록(<label>.txt)
│
├── verification/                ── 2단계 검증 (모두 PASS여야 함)
│   ├── predicate500_datasets.txt          동봉 데이터셋 20개 = 팀 생성기 결과 (FNV-1a, SHA-256)
│   ├── predicate500_datasets_regenerated/ 위 대조에 쓴 재생성 파일 (지워도 됨)
│   ├── cpp_rtl_vectors.txt                B 코어 ↔ RTL 벡터 256개 (비트 단위)
│   ├── cpp_oracles.txt                    오라클 4종 ↔ 팀 기준모델
│   ├── cpp_rtl_vs_golden_predicate500.txt B ↔ 팀 기대값 ↔ 10/04 보드 3종
│   ├── cpp_rtl_vs_golden_common500.txt    B ↔ 팀 기준모델(attempt 단위) ↔ 09/08 보드
│   └── runs/                              검증에 쓴 B 실행 원자료 (CSV, JSON, attempt 추적 JSONL)
│
├── predicate500/                ── 메인 workload (오라클 4종 × 500)
│   ├── runs/                    백엔드·구성마다 오라클별 CSV + JSON (아래 이름 규칙)
│   ├── verify_baselines_vs_cpp.txt   교차 검증: NumPy·Qiskit = C++ float, 기준모델 = C++ RTL 동일,
│   │                                 처리량·4코어 실행 = 1코어 실행 (모두 PASS여야 함)
│   └── report/
│       ├── report.md            보고서: 시간 표(총합, FPGA 대비 배수), 처리량 표, 동치성 표, float↔FPGA 분포 검정
│       ├── summary_by_backend.csv   백엔드별 합계 (총 시간, 반복 수, 성공 수 …) — 그래프·표 만들 때 쓰는 파일
│       └── all_backends.csv     모든 백엔드 + 보드의 workload별 행을 한 파일로 합친 것
│
└── common500/                   ── 같은 구성 (EQ 12345 × 500, 09/08 보드와 비교)
```

`runs/` 파일 이름 규칙: `<모델>_<정책>[_<정밀도>]_<실행 모드>[_<오라클>].csv`

| 부분      | 값                                                             | 뜻                                                        |
| --------- | -------------------------------------------------------------- | --------------------------------------------------------- |
| 모델      | `cpp_sw` / `cpp_rtl` / `numpy` / `qiskit` / `golden` | A1·A2 / B / D / C / G                                    |
| 정책      | `normal` / `k3h3` / `k4h4` / `allj`                    | 표준 BBHT / 체크포인트 / all-j                            |
| 정밀도    | `f64` / `f32`                                              | C++ float 모델만                                          |
| 실행 모드 | `1c` / `1t`                                                | 1코어 (Qiskit은 1스레드)                                  |
|           | `T<n>`                                                       | 지연 모드: 탐색 하나를 n코어가 나눔 (`T4` = E4의 SW 판) |
|           | `W<n>`                                                       | 처리량 모드: 탐색 n개를 동시에                            |
| 오라클    | `LT` / `GT` / `EQ` / `RANGE`                           | Predicate500만                                            |

예:

- `cpp_sw_normal_f32_1c_EQ.csv`: A1 f32, 1코어, EQ 오라클 500개
- `cpp_rtl_k3h3_T4_RANGE.csv`: B K3H3, 4코어(K3/H3-E4-M2의 SW 판), RANGE

파일 하나는 workload 한 행이고, 열은 다음과 같다.

- `predicate`, `target_count`, `seed_index`, seed 값
- `backend`, `policy`, `precision`, `threads`, `workers`, `reps`
- 결과: `success`, `termination_reason`, `result_index`, `trial_count`, `L_BBHT`, `actual_grover_iterations`
- 시간(ns): `compute_ns`, `search_ns`, `search_ns_min`, `prep_ns`, `build_ns`, `e2e_ns`

같은 이름의 `.json`은 그 실행의 요약이다. 합계, 초당 탐색 수(`throughput_searches_per_s`), 캠페인 벽시계 시간, 에너지(가능할 때), 실행 환경이 들어 있다.

논문용으로 볼 곳은 세 군데다.

- **결과가 맞는지:** `verification/*.txt`와 `*/verify_baselines_vs_cpp.txt`가 모두 PASS인지 본다.
- **숫자:** `predicate500/report/report.md`
- **그래프용 원자료:** `predicate500/report/summary_by_backend.csv`, `all_backends.csv`

개별 실행 예 (`software/sw_benchmark`에서):

```bash
IN=../experiments/common500_benchmark/inputs
# A1 메인, 1코어, Predicate500 RANGE
taskset -c 13 build/grover_bench --engine sw --policy normal --prec f64 --inputs $IN \
    --pred RANGE --a -4096 --b 4096 --datasets data/predicate500_datasets --reps 5 --out a1.csv --summary a1.json
# B, K3H3, Common500, attempt 추적 포함
build/grover_bench --engine rtl --policy k3h3 --inputs $IN --reps 1 --out b.csv --summary b.json --trace b.jsonl
# A1 멀티코어: 지연(반복 하나를 T스레드로) / 처리량(workload W개 동시)
build/grover_bench --engine sw --policy normal --threads 8 --inputs $IN --out lat.csv --summary lat.json
build/grover_bench --engine sw --policy normal --workers 8 --inputs $IN --out thr.csv --summary thr.json
# D NumPy, C Qiskit (입력 경로는 기본값으로 팀 폴더를 읽음, --pred만 주면 임계값 자동)
python3 baselines/numpy_baseline.py  --policy normal --pred EQ --reps 3 --out d.csv --summary d.json
python3 baselines/qiskit_baseline.py --policy k3h3   --pred EQ --threads 1 --reps 1 --seeds 5 --out c.csv --summary c.json
# 팀 원본 NumPy·Qiskit과 비교
python3 tools/compare_team_baselines.py --seeds 10 --qiskit-seeds 2
```

---

## 4. 시간 측정 정의 (모든 모델 공통)

| 열                 | 구간                                                                                   | FPGA 대응                                    |
| ------------------ | -------------------------------------------------------------------------------------- | -------------------------------------------- |
| `compute_ns`     | 상태벡터 계산만 (C++·NumPy: 반복 루프, Qiskit: Aer C++ 시뮬레이션 시간)               | 별도 카운터 없음                             |
| `search_ns`      | **탐색 전체**: j 뽑기, 정책, 계산, 측정, 종료 판정. 데이터·마스크는 준비된 상태 | `wall_us` / `elapsed_us` (COMMAND~DONE)  |
| `prep_ns`        | 데이터셋 파일 읽기 + 오라클 마스크 (데이터셋당, 5회 이상 중앙값)                       | DMA 적재 (미측정)                            |
| `build_ns`       | Qiskit 회로 생성·transpile (데이터셋당 합 ÷ workload 수)                             | —                                           |
| `e2e_ns`         | `prep_ns` + `build_ns` + `search_ns`                                             | DMA + 설정 + 탐색 + 결과 읽기 (HW 측정 필요) |
| `engine_call_ns` | Python 기준선만: 엔진 호출 벽시계 (Qiskit은 Aer의 회로 변환 포함)                      | —                                           |

규칙:

- **반복 측정:** workload마다 워밍업 1회 후 반복하고 중앙값을 쓴다. C++는 `--reps`(기본 5), NumPy 3, Qiskit 1이다. `search_ns_min`도 남긴다.
- **속도비:** 같은 workload 집합의 총합 비율로 낸다. workload별 짝지은 비율은 경로가 같은 B와 보드 사이에서만 의미가 있다.
- **처리량:** 탐색 수 ÷ 캠페인 벽시계 시간이다(`throughput_searches_per_s`).
- **에너지:**

  - 요약 JSON의 `rapl_package_energy_j`에 기록한다. RAPL을 읽을 권한이 있어야 한다.
  - 또는 `ENERGY=1`로 `perf stat`을 감싼다. 컨테이너 안에서는 보통 읽을 수 없다.
- **멀티코어:** `run_all.sh`가 이 프로세스가 쓸 수 있는 CPU 안에서 물리 코어 수와 논리 CPU 수를 읽는다.

  | 모드                                   | 하는 일                                                                                                      | 재는 개수 (예: 물리 16 / 논리 32) |
  | -------------------------------------- | ------------------------------------------------------------------------------------------------------------ | --------------------------------- |
  | 지연 (`--threads`)                   | 탐색 하나를 여러 코어가 나눔 (`spin_team.hpp`). A1 표준은 아래 개수 전부, A2·B의 K3H3는 4코어(E4의 SW 판) | 2, 4, 8, 물리 전체, 논리 전체     |
  | 처리량 (`--workers`)                 | workload를 동시에 돌림                                                                                       | 물리 전체, 논리 전체              |
  | Qiskit (`--threads`)                 | Aer 스레드. 1보다 크면`statevector_parallel_threshold=1`                                                   | 1, 논리 전체                      |
  | NumPy·기준모델 처리량 (`--workers`) | 프로세스 여러 개가 workload를 나눠 동시에 실행. 프로세스마다 CPU 하나에 고정                                 | 1, 물리 전체, 논리 전체           |


  - 하이퍼스레딩이 없으면 물리 전체와 논리 전체가 같으므로 한 번만 잰다.
  - 스레드는 `OMP_PLACES=cores`, `OMP_PROC_BIND=close`로 코어에 고정한다.
- **E4·M2의 SW 판:**

  - **E4**(반복 하나를 연산기 4벌이 나눔) → `--threads 4`(반복 하나를 4코어가 나눔)
  - **M2**(측정 행을 16×32 계층으로 선택) → 모든 C++ 코어의 기본 샘플러가 이미 계층 탐색이다. A는 128그룹 이진 탐색 후 그룹 안 탐색, B는 512행 누적분포 이진 탐색 후 행 안 탐색이다.
  - 그래서 `CPP_SW_BEST_K3H3_*_T4`, `CPP_RTL_EXACT_K3H3_T4`가 보드 최종 구성(K3/H3-E4-M2)과 같은 설계의 SW 판이다.
- **하이브리드 CPU와 컨테이너:**

  - P코어/E코어가 섞인 CPU(예: i5-14600K, P 6개 5.3 GHz + E 8개 4.0 GHz)는 코어 종류에 따라 1코어 성능이 크게 다르다.
  - `environment.txt`에 쓸 수 있는 CPU 목록, 고정한 CPU와 최대 클럭, 가상화 종류, `lscpu -e` 표가 남는다.
  - SW 기준선을 가장 빠른 코어에서 재야 비교가 공정하다. P코어를 쓸 수 있으면 `CORE`를 P코어 번호로 준다.
  - E코어만 쓸 수 있으면 논문에 "E코어 N개"로 적는다.

---

## 6. 검증 체계

| 무엇을                         | 무엇과                        | 도구                                         | 범위                                                                        |
| ------------------------------ | ----------------------------- | -------------------------------------------- | --------------------------------------------------------------------------- |
| B (RTL 동일)                   | G 기대값 + 10/04 보드 3종     | `verify_cpp_rtl_vs_golden_predicate500.py` | 4정책(normal, k3h3, allj, session) × 2,000, 보드 4모드 × 2,000            |
| B                              | G (attempt 단위) + 09/08 보드 | `verify_cpp_rtl_vs_golden_common500.py`    | 3정책 × 500, attempt 7,403개 (j, 재개 위치, 물리 반복, 정수 임계값, index) |
| B 코어                         | RTL 요청 j 벡터               | `verify_cpp_rtl_vectors.py`                | 256개, 최종 진폭 비트 단위                                                  |
| A·B 오라클                    | G 마스크·탐색                | `verify_cpp_oracles.py`                    | 무작위 40개 (EQ/LT/GT/RANGE, DATA_COUNT 패딩)                               |
| C·D                           | 같은 정책의 A (f64)           | `verify_baselines_vs_cpp.py`               | workload별 결과 위치·시도 수·L·물리 반복 수                              |
| float 계열 ↔ FPGA             | 분포                          | `summarize_results.py`                     | (오라클, M)별 Mann-Whitney(시도 수), KS(L)                                  |
| `data/predicate500_datasets` | 팀 생성기 + 기대값 해시       | `make_predicate500_datasets.py`            | 20개, FNV-1a + SHA-256                                                      |

**보드 결과 파일**

- 같은 저장소에 `hardware_bram/models/hardware_bram_K3H3_E4_M2/`, `hardware_bram/models/hardware_bram_nocheckpoint/`, `hardware_dram/`가 있으면 그 안의 `2026-10-04_board_predicate500/result.csv`를 직접 읽는다.
- 없으면 `data/board_20261004_predicate500/`의 사본을 읽는다. 같은 파일이다.
- 보드 `wall_us`는 보드 실시간 클럭(1 MHz)으로 COMMAND부터 DONE까지 잰 값이다. 가속기 사이클 시간보다 5~7 µs 크다(CPU 폴링). DMA 적재, 설정, 결과 읽기는 들어 있지 않다.

---

## 7. 개발 VM 결과 (2026-10-05, 참고)

같은 코드를 개발 VM에서 `REPS=1 QISKIT_SEEDS=2`로 돌린 결과다. 실행 환경은 클라우드 Xeon 2.8 GHz, 2 vCPU, 1코어 고정이다. 실행마다 20% 정도 흔들리는 VM이라 흐름 확인용이다. **논문 값은 팀 서버에서 다시 잰다.** 보고서는 `results/dev_vm_20261005/`에 있다.

**검증 (전부 PASS)**

- B ↔ G ↔ 10/04 보드: 4정책 × 2,000 일치, 보드 bram/ckpt · bram/normal · nocheckpoint · dram 각 2,000/2,000
- B ↔ G (attempt 단위) ↔ 09/08 보드: normal · k4h4 · k3h3 각 500 workload, attempt 7,403개 전부 일치
- B 코어 ↔ RTL 벡터: 256/256 비트 단위 일치
- 오라클 4종: PASS
- 동봉 데이터셋 = 팀 생성기 결과
- D(NumPy) ↔ A: normal · allj · k3h3 각 2,000/2,000(Predicate500), 500/500(Common500) 일치. C(Qiskit) ↔ A: 각 40/40, 10/10 일치(seed 2개)

**Predicate500 총 탐색시간 (2,000 workload, 1코어)**

| 백엔드                                       |         총 탐색시간 | FPGA K3/H3가 빠른 배수 | FPGA NORMAL이 빠른 배수 |
| -------------------------------------------- | ------------------: | ---------------------: | ----------------------: |
| FPGA K3/H3-E4-M2                             |            221.0 ms |                  1.00x |                   0.46x |
| A2 all-j f32                                 |            326.8 ms |                  1.48x |                   0.68x |
| FPGA NORMAL E4-M2 (같은 비트스트림, 정책 끔) |            479.0 ms |                  2.17x |                   1.00x |
| FPGA 체크포인트 없는 Normal-E4               |            621.2 ms |                  2.81x |                   1.30x |
| **A1 f32 (메인)**                      |  **908.3 ms** |        **4.11x** |         **1.90x** |
| **A1 f64 (메인)**                      | **1337.0 ms** |        **6.05x** |         **2.79x** |
| B RTL 동일 Normal                            |           1417.0 ms |                  6.41x |                   2.96x |
| D NumPy + all-j                              |           3360.9 ms |                 15.21x |                   7.02x |
| FPGA DRAM all-j (세션)                       |           3459.0 ms |                 15.65x |                   7.22x |
| D NumPy 표준                                 |           4205.7 ms |                 19.03x |                   8.78x |
| D NumPy + K3/H3                              |           4514.2 ms |                 20.42x |                   9.42x |

- C(Qiskit)는 seed 2개(40 workload)만 돌렸다. 같은 40개 기준으로 표준 44.9초, all-j 13.6초, K3/H3 14.5초다.
- 그중 Aer 실제 시뮬레이션(`compute_ns`)은 각각 16.3초, 4.7초, 4.9초다. 나머지는 Aer의 회로 변환 시간이다.
- 팀 원본 NumPy와 비교하면 반복 1회당 팀 80–114 µs, 우리 16 µs다(`results/dev_vm_20261005/compare_team_baselines.txt`).

---

## 8. 구현 메모

- **C++ 반복 커널은 `noinline`이다.** 인라인되면 `__restrict` 정보가 사라져 컴파일러가 런타임 alias 검사 뒤 스칼라 경로로 빠졌다. 그때는 반복당 6 µs가 20 µs가 됐다.
- **반복 1회 = 상태 1패스다.** 상태마다 다음 반복의 2·평균에 필요한 오라클 적용 합을 같이 들고 다니기 때문이다.
- **지연 모드(E4의 SW 판)는 상주 스레드 팀(`spin_team.hpp`)을 쓴다.**
  - 엔진당 한 번 만들고, 각 코어가 벡터의 고정 구간을 맡는다. 반복마다 공유하는 값은 다음 2·평균 하나뿐이라 동기화는 반복당 스핀 barrier 1번이다.
  - 작업 스레드는 쉬지 않고 대기하며(잠들지 않음), 프로그램 시작 때 읽은 CPU 목록에 하나씩 고정한다.
  - 처음 쓴 OpenMP 방식은 반복마다 barrier가 여러 번 들고 스레드를 깨우는 비용까지 붙었다. 그래서 서버 E코어에서 8스레드가 1스레드보다 7배 느렸다.
  - 정수 부분합은 정확해서 B는 코어 수와 상관없이 비트 단위로 같고, float는 같은 경로를 낸다. `run_all.sh`가 4코어 결과를 1코어 결과와 대조한다.
  - 쓸 수 있는 CPU보다 많은 `--threads`는 시작 전에 거부한다. 대기 스레드끼리 CPU를 나눠 쓰면 극단적으로 느려지기 때문이다.
- **K3/H3 정책 계산은 기준모델과 같은 재귀 탐색 + 메모이제이션이다.** C++에서는 시도당 비용이 작다. Python(NumPy·Qiskit)에서는 시도당 약 100 µs라서, NumPy K3/H3는 표준과 시간이 비슷하다.
- **측정 샘플러는 B만 RTL 정수 샘플러이고, 나머지는 float 샘플러(128그룹 누적분포)다.** float 계열이 정수 샘플러를 쓰면 총 가중치가 2^44 경계에서 갈려 어차피 경로가 달라진다. 반대로 float 샘플러를 공유하면 A·C·D가 1:1로 대조된다.
- **NumPy all-j는 미리 잡은 128행 라이브러리에 바로 계산한다.** 상태를 저장할 때마다 128 KB를 새로 할당하면 반복당 19 µs가 165 µs가 됐다.
