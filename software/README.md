# Q14 BBHT/Grover 소프트웨어 최종본

이 폴더는 **NumPy·Qiskit·RTL 기준모델**, 동일 workload 비교 실험,
RTL 회귀용 정답 벡터, FPGA 연동 계약, 최종 결과만 모은 공유본이다.

## 1. 기준 구성

| 항목 | 기준값 |
| --- | --- |
| 검색공간 | Q14, `N=16,384` |
| 병렬도 | P32 |
| 입력 | signed 16-bit |
| 진폭 | signed Q1.22, 23-bit |
| Oracle | EQ/LT/GT/RANGE 지원 |
| BBHT | `m0=1`, `lambda=6/5`, `m_max=128`, logical budget 576 |
| 최종 checkpoint | K3/H3 |
| 비교용 이전 checkpoint | K4/H4 |
| FPGA 최종 구성 | K3/H3-E4-M2, 100 MHz |


## 2. 폴더 구조

```text
software/
├── README.md
├── requirements.txt
├── models/
│   ├── common/                 공통 설정·결과 자료형·데이터·BBHT 계약
│   ├── numpy_model/            Float64 상태벡터 기준모델
│   ├── qiskit_model/           Qiskit Aer 상태벡터 및 BBHT 실행기
│   └── rtl_reference_model/    Q1.22 bit-exact 및 checkpoint 기준모델
├── experiments/
│   └── common500_benchmark/    동일 500-workload 전체 비교 실험
├── rtl_vectors/
│   ├── requested_j_bit_exact/  requested-j RTL 정답 벡터 256개
│   └── enumeration/            다중 결과 열거 방식 2종 정답 벡터
├── results/
   └── common500_final/        서버·보드 최종 결과, 표, 그래프, 보고서

```

## 3. 모델 파일

| 파일 | 역할 |
| --- | --- |
| `models/common/final_hardware_contract.py` | Q14/P32/Q1.22, CSR 입력 범위, 실행 모드, checkpoint 상수 |
| `models/common/benchmark_dataset.py` | 공식 M별 dataset 생성·검증과 Oracle target mask |
| `models/common/bbht_control_semantics.py` | BBHT m 경계, logical budget, attempt·FIFO 의미 검사 |
| `models/common/model_config.py` | 범용 실험 설정 자료형 |
| `models/common/result_records.py` | 실행·attempt·trace 결과 자료형과 일관성 검사 |
| `models/common/trace_recorder.py` | Oracle 전후·Diffusion 후 상태 기록 |
| `models/numpy_model/numpy_grover_backend.py` | Float64 Oracle·Diffusion 상태벡터 계산 |
| `models/qiskit_model/qiskit_grover_backend.py` | Qiskit Aer requested-j 회로 준비·실행 |
| `models/qiskit_model/bbht_qiskit_runner.py` | 동일 J-LFSR·측정 규칙으로 NumPy/Qiskit BBHT 수행 |
| `models/rtl_reference_model/fixed_point_statevector.py` | RTL Q1.22 산술, LFSR, 측정의 bit-exact 기준 |
| `models/rtl_reference_model/checkpoint_bbht_model.py` | Normal, K4/H4, 최종 K3/H3, DRAM all-j 정책 모델 |

`DRAM_ALL_J`는 알고리즘 비교용 소프트웨어 정책 모델이다. Common500 결과와
팀원 FPGA 실측에는 포함되지 않았고, DRAM 전송 지연도 모델링하지 않는다.

## 4. Common500 실험

| 축 | 값 |
| --- | --- |
| M | 1, 4, 16, 64, 256 |
| seed | M마다 공식 100쌍 |
| workload | 총 500개 |
| dataset/Oracle | 보드와 동일한 5개 dataset, EQ `0xA55A` |
| 소프트웨어 backend | NumPy, Qiskit Aer, Fixed Normal, K4/H4, K3/H3 |
| FPGA backend | Normal, K4/H4, K3/H3-E4-M2 |
| 전체 결과 | 500 workload × 8 backend = 4,000행 |

### 전체 재실행

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt
bash experiments/common500_benchmark/run_full_benchmark.sh
```

실행 스크립트는 NumPy/Aer thread 수를 1로 고정한다. 중단 후 같은 명령을
다시 실행하면 `results/common500_final/software_resume_records.jsonl`을
읽고 완료된 소프트웨어 backend를 건너뛴다.

진행 기록 확인:

```bash
bash experiments/common500_benchmark/check_benchmark_status.sh
```


## 5. 최종 결과 파일

| 파일 | 내용 |
| --- | --- |
| `common500_validation_report.md` | 실험 계약, 정합성, 성능표, 해석 기준 |
| `common500_all_backend_results.csv` | 4,000행 workload별 전체 원시 결과 |
| `common500_summary_by_target_count.csv` | M·backend별 성공률, trial, 반복 수, 시간 |
| `common500_workload_correctness.csv` | NumPy-Qiskit·Golden-FPGA 일치 여부 |
| `fpga_configuration_speedup.csv` | FPGA Normal/K4-H4/최종 구성 시간과 speedup |
| `checkpoint_model_fpga_iteration_delta.csv` | checkpoint 모델과 FPGA 물리 반복 수 차이 |
| `fpga_runtime_by_target_count.svg` | M별 FPGA 구성 시간 그래프 |
| `software_runtime_by_target_count.svg` | M별 NumPy·Qiskit 시간 그래프 |
| `software_resume_records.jsonl` | 중단 복구용 소프트웨어 실행 기록 |
| `experiment_manifest.json` | 서버 환경·패키지 버전·입력 SHA-256 |

핵심 결과는 `results/common500_final/common500_validation_report.md`에 있다.
500개 workload에서 NumPy-Qiskit 논리 결과, Fixed-FPGA Normal, K4/H4 및
K3/H3 checkpoint 물리 반복 수가 모두 일치했다.

시간 경계는 서로 다르다. NumPy는 core 계산, Qiskit은 Aer 실행, FPGA는 보드
command-to-result이다. FPGA 내부 구성 간 speedup은 직접 비교할 수 있지만,
서버와 FPGA의 절대시간 비율은 측정 경계를 함께 표시한 참고값이다.

## 6. RTL 정답 벡터

### Requested-j bit-exact 256개

`rtl_vectors/requested_j_bit_exact/requested_j_bit_exact_256_cases.zip`

- 입력 dataset과 AHB word
- target mask
- 초기 Q1.22 진폭
- iteration별 Oracle·Diffusion·부분합
- 최종 진폭과 expected core 결과

이 패키지는 requested-j 데이터패스의 RTL 회귀 정답지다.

### Enumeration 2종

| 폴더 | 의미 |
| --- | --- |
| `software_reload/` | 찾은 값을 비타겟으로 바꾸고 SW가 dataset을 다시 적재 |
| `projected_mask_mem/` | HW found-mask를 가정한 확장 후보 |

Q14 EQ/GT/LT/RANGE, M=0/1/4/8, padding, Q16 projected 사례를 포함한다.
각 case의 `expected_result.json`과 라운드별 mask 전후 파일을 비교한다.
Q16 및 projected mask-memory 자료는 확장 검토용이며 Q14 최종 보드 구현
검증 완료를 뜻하지 않는다.


## 7. 검증 상태

| 항목 | 상태 |
| --- | --- |
| Common500 4,000행 결과 | 완료 |
| NumPy-Qiskit 논리 정합성 | 500/500 PASS |
| Fixed Normal-FPGA 정합성 | 500/500 PASS |
| K4/H4 Golden-FPGA 물리 반복 수 | 500/500 PASS |
| K3/H3 Golden-FPGA 물리 반복 수 | 500/500 PASS |
| Requested-j 벡터 | 256개 포함 |
| Enumeration 벡터 | 2방식 10개 case 포함 |
| DRAM all-j 보드 시간 | 미측정 |
| Q15/Q16 실제 RTL·보드 검증 | 미포함 |

원본 보드 CSV는 팀원이 측정한 값이며 수정하지 않았다. 모델·결과 파일명만
역할 중심으로 정리했고 원시 수치와 SHA-256은 보존했다.
