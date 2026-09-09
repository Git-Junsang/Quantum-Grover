# Qiskit·NumPy·FPGA 3자 비교 가이드

## 1. 목적

동일한 Grover 문제를 세 구현에 입력해 **정답성**과 **실행 시간**을 분리 비교한다.

| 구현 | 역할 | 현재 상태 |
| --- | --- | --- |
| NumPy Float64 | 수치 기준 상태벡터 | 실행 가능 |
| Qiskit Aer Statevector | 범용 양자 시뮬레이터 기준선 | 실행 가능 |
| FPGA v0.9.8 Q14/P32/F22 | 하드웨어 측정 대상 | 결과 입력 양식 생성 |

## 2. 공통 비교 조건

세 구현에 다음 값이 모두 같아야 한다.

| 조건 | 설명 |
| --- | --- |
| `N=2^Q` | 전체 상태 수 |
| `M` | 타겟 수 |
| `requested_j` | Grover 반복 수 |
| `target_mask` | 위상을 반전할 상태 집합 |
| Oracle·Diffusion 순서 | Oracle 후 Diffusion |
| 초기상태 | 매 실행마다 균일상태에서 시작 |

Qiskit 회로는 다음 순서다.

```text
H^Q -> [Diagonal phase Oracle -> Diffusion]^j -> Statevector 저장
```

Oracle은 타겟 상태의 대각 원소만 `-1`로 두며, Diffusion은 NumPy의
`A_next[i] = 2*mean(A_oracle) - A_oracle[i]`와 같은 연산이다.

## 3. 구간별 비교 구조

| 구간 | NumPy | Qiskit | FPGA |
| --- | --- | --- | --- |
| 입력·Oracle 준비 | 배열·target mask 생성 | target mask·회로 생성 | dataset 생성·DMA 전송 |
| 실행 준비 | 함수 호출 준비 | Aer용 transpile | CSR 설정·진폭 초기화 |
| Grover 연산 | NumPy 배열 Oracle·Diffusion | Aer 상태벡터 실행 | Main IP Oracle·Diffusion |
| 측정·검증 | Born sampling·predicate 검증 | sampling 또는 statevector 확률 분석 | Born 측정·후보 검증 |
| 결과 반환 | Python 결과 객체 | Aer result 객체 | CSR/FIFO 결과 읽기 |
| 전체 실행 | 위 구간의 합 | 위 구간의 합 | DMA부터 결과 수신까지 |

### 3.1 비교 수준

| 비교 수준 | 포함 범위 | 용도 |
| --- | --- | --- |
| 수치 정답성 | 동일 target mask와 j의 최종 상태벡터 | 알고리즘 구현 검증 |
| Grover kernel | 균일 초기화와 j회 Oracle·Diffusion | 연산 코어 속도 비교 |
| Search core | Grover + Born 측정 + 후보 검증 | 한 shot의 가속기 비교 |
| BBHT algorithm | 여러 attempt + m/j 제어 + 측정·검증 | 전체 탐색 알고리즘 비교 |
| End-to-End | 입력 생성·전송부터 결과 수신까지 | 실제 시스템 사용시간 비교 |

서로 다른 수준의 시간을 하나의 speedup으로 나누지 않는다. 예를 들어 Qiskit
`transpile`이 포함된 시간을 FPGA의 Grover 반복 cycle과 직접 비교하거나,
FPGA DMA 시간이 포함된 전체 시간을 NumPy 배열 연산만과 비교하면 안 된다.

### 3.2 현재 자동 기록 범위

| 구간 | 현재 기록 | 비고 |
| --- | --- | --- |
| 공통 입력 준비 | `shared_input_prepare_seconds` | Q14는 HEX 생성 포함 |
| NumPy Grover kernel | `execution_seconds` | 균일 초기화와 j회 반복 포함, 측정 제외 |
| Qiskit 회로 생성 | `build_seconds` | target mask를 DiagonalGate로 구성 |
| Qiskit transpile | `transpile_seconds` | 실행 준비 비용 |
| Qiskit 준비 후 실행 | `execution_seconds` | 초기 H, j회 반복, statevector 저장 |
| Qiskit cold start | `cold_start_total_seconds` | 생성 + transpile + 실행 중앙값 |
| BBHT 제어·측정 | `bbht_raw.csv`의 `wall_seconds` | 다중 attempt 전체 |
| FPGA Main IP 전체 | `cycle_count` | 현재 CSR에서 제공하는 총 cycle |
| FPGA 세부 구간 | `*_cycles_optional` | RTL이 별도 카운터를 제공할 때 입력 |
| FPGA E2E | 미측정 | DMA 시작 전·결과 수신 후 타임스탬프 필요 |

현재 v0.9.8 CSR의 `CYCLE_COUNT`가 세부 구간을 모두 분리해 주는 것은 아니다.
따라서 별도 하드웨어 카운터가 없으면 `FPGA Main-IP total`로 표기하고,
Grover-only 시간이라고 부르지 않는다.

## 4. 비교 지표

| 구분 | 지표 | 판정 의미 |
| --- | --- | --- |
| 수치 정답성 | 전역위상 보정 L2 | 상태벡터 전체가 같은지 |
| 수치 정답성 | 최대 진폭 오차 | 가장 크게 어긋난 상태 |
| 알고리즘 결과 | 성공확률 오차 | 타겟 전체 Born 확률 차이 |
| 안정성 | 정규화 오차 | 전체 확률 합이 1인지 |
| 시간 | NumPy 실행 | `run_grover` 실행 시간 |
| 시간 | Qiskit 생성 | 논리 회로 생성 시간 |
| 시간 | Qiskit 변환 | Aer용 transpile 시간 |
| 시간 | Qiskit 실행 | 준비된 회로 실행 시간 |
| 시간 | FPGA | `CYCLE_COUNT / 100,000,000` |

회로 생성과 transpile을 Qiskit 실행 시간에 섞지 않는다. 원시 반복값을 모두
보존하고 같은 조건 안에서 중앙값, p95, 최솟값, 최댓값을 계산한다.

## 5. 실행

Qiskit은 선택 의존성이다.

```powershell
python -m venv .venv-qiskit
.venv-qiskit\Scripts\python -m pip install -r requirements-qiskit.txt
```

빠른 기능 확인:

```powershell
.venv-qiskit\Scripts\python qiskit_three_way_benchmark.py `
  --preset SMOKE `
  --output verification_results/qiskit_three_way_smoke
```

서버 기준 반복 측정:

```bash
python3 -m venv .venv-qiskit
.venv-qiskit/bin/python -m pip install -r requirements-qiskit.txt
.venv-qiskit/bin/python qiskit_three_way_benchmark.py \
  --preset SERVER \
  --threads 1 \
  --repeats 10 \
  --warmups 2 \
  --output verification_results/qiskit_three_way_server
```

첫 공식 결과는 `--threads 1`로 측정한다. 모든 CPU 코어를 쓰는 결과가 필요하면
별도 폴더에서 추가 실행하고, 두 결과를 같은 표본으로 섞지 않는다.

## 6. 출력 파일

| 파일 | 내용 |
| --- | --- |
| `raw_timings.csv` | 반복별 NumPy·Qiskit 시간과 정확도 |
| `timing_summary.csv` | 조건별 중앙값·p95·최소·최대 |
| `scenarios.json` | N·M·j·mask hash·환경·Qiskit 회로 정보 |
| `benchmark_manifest.json` | 비교 범위와 시간 측정 규칙 |
| `fpga_inputs/*/data_signed16.hex` | Q14 동일 입력 데이터 |
| `fpga_results_template.csv` | 보드 결과 입력 표 |

## 7. FPGA 결과 결합

`fpga_results_template.csv`에 동일 시나리오의 `cycle_count`를 채운다. 여러 번
측정했다면 같은 행을 복제하고 각 측정값을 기록한다. 이후 다음을 실행한다.

```powershell
python merge_fpga_benchmark.py verification_results/qiskit_three_way_server
```

| 생성 파일 | 내용 |
| --- | --- |
| `three_way_timing_summary.csv` | NumPy·Qiskit·FPGA 통합 시간표 |
| `three_way_speedup.csv` | FPGA/NumPy, FPGA/Qiskit 속도비 |

mask SHA-256이 다르면 결합을 거부하므로 서로 다른 문제의 시간을 실수로 비교하지
않는다.

## 8. BBHT 비교 범위

`qiskit_bbht.py`는 v0.9.8의 J-LFSR, m 증가표, shot cap, 논리 예산 576을
사용한다. 스케줄러에는 실제 M을 전달하지 않으며, 각 attempt는 균일상태에서 다시
시작한다.

Qiskit과 FPGA의 측정 난수기는 서로 다르므로 BBHT의 `result_index`를 seed별로
동일하다고 요구하지 않는다. BBHT는 여러 seed에서 최종 성공률, trial 수,
`L_BBHT`, 실행 시간의 분포를 비교한다. 반면 requested-j 코어는 상태벡터와
성공확률을 직접 비교한다.

BBHT 전체 실행 비교:

```bash
.venv-qiskit/bin/python qiskit_bbht_benchmark.py \
  --targets 1,4,16,64,256 \
  --seed-start 1 \
  --seed-count 50 \
  --threads 1 \
  --output verification_results/qiskit_bbht_server
```

| 파일 | 내용 |
| --- | --- |
| `bbht_raw.csv` | seed별 최종 성공·종료·trial·L_BBHT·시간 |
| `bbht_attempts.csv` | 모든 attempt의 m·j·측정·성공 여부 |
| `bbht_summary.csv` | M별 성공률과 trial·L_BBHT·시간의 중앙값/p95 |
| `bbht_fpga_results_template.csv` | 동일 M·seed의 보드 결과 입력 양식 |
| `bbht_manifest.json` | 알고리즘 규칙과 해석 기준 |

## 9. 해석 제한

- 현재 Qiskit 기준선은 target mask를 대각 위상 게이트로 표현한다. signed16
  비교기를 양자 게이트로 합성한 회로의 게이트 비용을 측정하는 실험은 아니다.
- NumPy와 Qiskit은 PC 소프트웨어이고 FPGA는 100 MHz 독립 하드웨어이므로,
  커널 시간과 데이터 전송 포함 E2E 시간을 구분해 보고해야 한다.
- Qiskit 회로 캐시는 컴파일 결과만 재사용한다. 이전 BBHT 진폭을 재사용하지
  않으므로 표준 BBHT의 재초기화 의미를 훼손하지 않는다.
- 대표 Q14 1회 결과는 기능 확인값이다. 공식 성능 수치는 서버에서 같은 조건을
  여러 번 실행한 중앙값과 p95로 확정한다.

## 10. 현재 확인 결과

| 조건 | 전역위상 보정 L2 | 성공확률 오차 | NumPy 1회 | Qiskit 준비 후 1회 |
| --- | ---: | ---: | ---: | ---: |
| Q14, N=16,384, M=256, j=6 | `1.043e-14` | `2.076e-14` | 1.005 ms | 44.569 ms |

측정 환경은 로컬 Windows PC, Python 3.13.2, NumPy 2.5.3, Qiskit 2.5.2,
Qiskit Aer 0.17.2, CPU thread 1이다. 이 시간은 서버 또는 FPGA 성능 주장에
그대로 사용하지 않는다.

BBHT 기능 확인 결과:

| 조건 | seed | 최종 성공 | trial 수 | L_BBHT | NumPy 코어 합 | Qiskit 코어 합 |
| --- | ---: | --- | ---: | ---: | ---: | ---: |
| Q14, M=1 | 1 | 성공 | 20 | 99 | 9.261 ms | 784.234 ms |
| Q14, M=256 | 1 | 성공 | 5 | 4 | 1.092 ms | 51.240 ms |

M=1의 마지막 성공 attempt는 `m_bound=32`에서 `j=27`을 뽑은 경우였다.
이 표의 시간은 여러 attempt의 상태벡터 실행 시간 합이며, Qiskit 회로 생성과
transpile은 포함하지 않는다. 공식 통계는 서버에서 50개 이상의 seed로 다시
측정한다.
