# 소프트웨어 기준모델과 Common500 비교 실험

> 2026-09-13 `software/` 재편 때 폴더 안에 있던 `README.md` 를 이 문서로 옮겼습니다.
> 저장소 규칙상 README 는 루트의 두 개뿐입니다.

`software/` 에는 두 갈래(`hardware_bram` · `hardware_dram`)가 함께 쓰는 소프트웨어가
있습니다. 무엇이 들어 있는지는 넷으로 요약됩니다.

- **기준모델** — NumPy float64, Qiskit Aer, Q1.22 bit-exact 고정소수점, 체크포인트 정책 모델
- **Common500 비교 실험** — 보드 실측과 같은 500 워크로드를 소프트웨어 backend 다섯에 걸고, 보드 결과 셋과 한 표로 합친 것
- **RTL 정답 벡터** — requested-j bit-exact 256케이스와 열거 두 방식
- **최종 결과** — Common500 의 원시 결과·집계·그래프·검증 보고서

---

## 1. 기준 구성

| 항목 | 값 |
|---|---|
| 검색공간 | Q14, N = 16,384 |
| 병렬도 | P = 32 |
| 입력 | signed 16비트 |
| 진폭 | signed Q1.22, 23비트 |
| 오라클 | `EQ` · `LT` · `GT` · `RANGE` |
| BBHT | `m0 = 1`, `λ = 6/5`, `m_max = 128`, logical budget 576 |
| 최종 체크포인트 | K3/H3 |
| 비교용 이전 체크포인트 | K4/H4 |
| FPGA 최종 구성 | K3/H3-E4-M2, 가속기 100 MHz |

값은 `software/models/common/final_hardware_contract.py` 에 있고 CSR 쪽 기록인
[CSR_레지스터_규격.md](CSR_레지스터_규격.md) 와 같습니다.

## 2. 폴더 구조

```text
software/
├── requirements.txt
├── models/
│   ├── common/                 공통 설정·결과 자료형·데이터셋·BBHT 계약
│   ├── numpy_model/            Float64 상태벡터 기준
│   ├── qiskit_model/           Qiskit Aer 상태벡터와 BBHT 실행기
│   └── rtl_reference_model/    Q1.22 bit-exact 와 체크포인트 정책 모델
├── experiments/
│   └── common500_benchmark/    500 워크로드 전체 비교 실험
├── rtl_vectors/
│   ├── requested_j_bit_exact/  requested-j RTL 정답 벡터 256케이스 (zip)
│   └── enumeration/            열거 두 방식 정답 벡터
├── results/
│   └── common500_final/        서버·보드 최종 결과, 표, 그래프, 보고서
└── contract/
    └── check_ports.py          포트 대조기 (대조 기준 tsv 가 빠져 지금은 멈춤)
```

## 3. 모델 파일

| 파일 | 역할 |
|---|---|
| `models/common/final_hardware_contract.py` | Q14 · P32 · Q1.22, CSR 오프셋(`CSR_OFFSETS`)과 입력 범위, 실행 모드(`RUN_MODES`), 체크포인트 상수 |
| `models/common/benchmark_dataset.py` | M 별 공식 데이터셋 생성·검증과 오라클 target mask |
| `models/common/bbht_control_semantics.py` | BBHT `m` 경계, logical budget, attempt · FIFO 의미 검사 |
| `models/common/model_config.py` | 실험 설정 자료형 |
| `models/common/result_records.py` | 실행 · attempt · trace 결과 자료형과 일관성 검사 |
| `models/common/trace_recorder.py` | 오라클 전후 · 확산 후 상태 기록 |
| `models/numpy_model/numpy_grover_backend.py` | Float64 오라클 · 확산 상태벡터 계산 |
| `models/qiskit_model/qiskit_grover_backend.py` | Qiskit Aer 로 requested-j 회로를 준비·실행 |
| `models/qiskit_model/bbht_qiskit_runner.py` | 같은 J-LFSR · 측정 규칙으로 NumPy/Qiskit BBHT 수행 |
| `models/rtl_reference_model/fixed_point_statevector.py` | RTL Q1.22 산술, LFSR, 측정의 bit-exact 기준 |
| `models/rtl_reference_model/checkpoint_bbht_model.py` | BBHT · 열거 실행 기준. Normal · K4/H4 · 최종 K3/H3 · DRAM all-j 정책 |

체크포인트 모델이 재현하는 것과 일부러 재현하지 않는 것을 구분해 두십시오.
측정 난수(xorshift64)와 K3/H3 정책의 결정 규칙은 RTL 식 그대로라 **탐색 궤적과 물리
반복 수가 보드와 같게** 나옵니다. 반면 정책 풀이 지연, plan FIFO 대기, E4 · M2 의
사이클 효과는 하드웨어 타이밍이라 모델에 넣지 않았습니다. `cycle_count` 는 RTL 이나
보드에서 인용합니다.

`DRAM_ALL_J` 는 `hardware_dram` 갈래의 발상을 알고리즘 수준에서 비교하려는 정책
모델입니다. DRAM 전송 지연은 모델링하지 않았고, Common500 결과와 보드 실측에는
들어 있지 않습니다.

실행 모드 이름은 CSR 쪽(`CKPT_SINGLE` 등)과 다릅니다. 모델은 정책 이름으로 부르며
`RUN_MODES` 에 `K3H3_*` · `K3H3_E4_M2_*` · `K4H4_*` · `K4H8_*` 가 있습니다.
`K4H8` 은 옛 K4/H4 정책으로 옮겨 받습니다.

## 4. Common500 실험

| 축 | 값 |
|---|---|
| M | 1, 4, 16, 64, 256 |
| 시드 | M 마다 공식 로스터 100쌍 |
| 워크로드 | 총 500 |
| 데이터셋과 오라클 | 보드와 같은 5개 데이터셋, `EQ 0xA55A` |
| 소프트웨어 backend | NumPy, Qiskit Aer, Fixed Normal, K4/H4, K3/H3 |
| FPGA backend | Normal, K4/H4, K3/H3-E4-M2 (보드 실측 CSV) |
| 전체 결과 | 500 워크로드 × 8 backend = 4,000행 |

보드 쪽 세 열은 2026-09-08 보드 실측
([`vivado/.../2026-09-08_k3h3_e4_m2_board_500run/`](../../hardware_bram/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/))
과 같은 워크로드이고, 원본 CSV 는 고치지 않고 합쳤습니다.

### 4.1 다시 돌리기

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r software/requirements.txt
bash software/experiments/common500_benchmark/run_full_benchmark.sh
```

스크립트는 자기 위치를 기준으로 경로를 잡으므로 저장소 어디서 불러도 됩니다. `python`
을 부르므로 가상환경을 켜 둔 상태여야 합니다. NumPy · Aer 스레드는 1로 고정합니다.

중간에 끊겨도 같은 명령을 다시 부르면
`results/common500_final/software_resume_records.jsonl` 을 읽고 끝난 backend 를
건너뜁니다. 진행 상황은 이렇게 봅니다.

```bash
bash software/experiments/common500_benchmark/check_benchmark_status.sh
```

## 5. 결과

### 5.1 결과 파일

모두 `software/results/common500_final/` 에 있습니다.

| 파일 | 내용 |
|---|---|
| [`common500_validation_report.md`](../../software/results/common500_final/common500_validation_report.md) | 실험 계약, 정합성, 성능표, 해석 규칙 |
| `common500_all_backend_results.csv` | 4,000행 워크로드별 원시 결과 |
| `common500_summary_by_target_count.csv` | M · backend 별 성공률, trial, 반복 수, 시간 |
| `common500_workload_correctness.csv` | NumPy↔Qiskit · 모델↔FPGA 일치 여부 |
| `fpga_configuration_speedup.csv` | FPGA Normal · K4/H4 · 최종 구성 시간과 배수 |
| `checkpoint_model_fpga_iteration_delta.csv` | 체크포인트 모델과 FPGA 물리 반복 수 차이 |
| `fpga_runtime_by_target_count.svg` · `software_runtime_by_target_count.svg` | M 별 시간 그래프 |
| `software_resume_records.jsonl` | 중단 복구용 실행 기록 |
| `experiment_manifest.json` | 서버 환경(Python 3.12.3, qiskit 2.5.2, qiskit-aer 0.17.2, numpy 2.5.3)과 입력 SHA-256 |

### 5.2 정합성

비교는 짝을 지어 합니다. NumPy · Qiskit 은 float64 측정이라 Q1.22 쪽과 궤적이 같을
이유가 없으므로 둘끼리만 맞대고, 고정소수점 모델은 같은 정책의 보드 구성과 맞댑니다.

| 검사 | 비교 필드 | 결과 |
|---|---|---:|
| NumPy ↔ Qiskit | `result_index` · `trial_count` · `L_BBHT` | 500/500 |
| Fixed Normal 모델 ↔ 보드 Normal | 위 셋 + `actual_grover_iterations` | 500/500 |
| K4/H4 모델 ↔ 보드 K4/H4 | 논리 셋 / 물리 반복 | 500/500 / 500/500 |
| K3/H3 모델 ↔ 보드 K3/H3-E4-M2 | 논리 셋 / 물리 반복 | 500/500 / 500/500 |
| 보드 세 구성끼리 | 논리 셋 | 500/500 |

체크포인트는 논리 결과를 바꾸면 안 되고, 같은 정책이면 모델과 보드의 물리 반복 수도
같아야 합니다. 두 조건이 모두 500/500 으로 섰습니다.

### 5.3 시간 — 측정 경계가 서로 다릅니다

| backend | 무엇을 쟀나 |
|---|---|
| NumPy | 상태벡터 계산 코어만 |
| Qiskit | Aer 실행만 (회로 build · transpile 은 원시 결과의 별도 열) |
| Fixed · K4/H4 · K3/H3 모델 | 파이썬 모델 벽시계 |
| FPGA | 보드의 명령 발행부터 결과까지. DMA 적재 제외 |

**FPGA 구성끼리의 배수만 성능 주장에 씁니다.** 보드 세 구성의 M 별 시간과 배수는
보드 실측 묶음과 같은 값입니다 (M = 1 에서 Normal 대비 9.192x, 전체 7.626x).
서버 소프트웨어와 보드의 절대시간 비율은 플랫폼과 측정 경계가 달라 참고값입니다.
같은 칩 위의 순수 소프트웨어 대조군은 ORCA 1코어 기준선
([`vivado/.../2026-09-08_orca_1core_baseline/`](../../hardware_bram/vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/))
이고, 그 배수가 십만 단위인 것은 P = 32 병렬과 클럭 2배 때문이지 알고리즘 우위가
아닙니다. 고전 선형 스캔과는 비교하지 않습니다.

## 6. RTL 정답 벡터

### 6.1 requested-j bit-exact 256케이스

`software/rtl_vectors/requested_j_bit_exact/requested_j_bit_exact_256_cases.zip`

방향성 케이스 28개(`dir_*`), 앵커 1개(`anchor_*`), 무작위 227개(`rnd_*`)입니다.
케이스마다 들어 있는 파일은 이렇습니다.

| 파일 | 내용 |
|---|---|
| `config.json` | 술어 · 임계값 · `DATA_COUNT` · `j_target` 과 프로파일(Q14 · P32 · F22 · AMP_W 23) |
| `data_signed16.hex` · `data_ahb_words.hex` · `data_memory_image.hex` | 같은 데이터셋의 세 표현 (인덱스 순 · AHB 워드 · P32 메모리 이미지) |
| `target_mask_p32.hex` | 오라클 target mask |
| `initial_amp.hex` | 초기 Q1.22 진폭 |
| `iter_###_after_oracle.hex` · `iter_###_row_partial_sum.hex` · `iter_###_after_diffusion.hex` | 반복별 중간값 (FULL trace 56케이스만) |
| `expected_final_amp.hex` · `expected_core.json` | 최종 진폭과 결과 · 물리 반복 · 포화 횟수 |

범위는 `expected_core.json` 의 `scope` 가 말하듯 **수동 j 코어의 bit-exact**
(`MANUAL_CORE_BIT_EXACT`)입니다. 자동 BBHT 의 J 난수, 측정 난수, 정책 텔레메트리,
`cycle_count` 는 이 벡터의 주장에서 빠져 있습니다 (`excluded_from_claim`).

### 6.2 열거 두 방식

| 폴더 | 뜻 |
|---|---|
| `enumeration/software_reload/` | 찾은 값을 비타겟으로 바꾸고 소프트웨어가 데이터셋을 다시 적재 |
| `enumeration/projected_mask_mem/` | 하드웨어 found-mask 방식 (최종 RTL 이 채택한 쪽) |

두 방식에 같은 다섯 케이스(`q14_eq_m1` · `q14_range_m4_pad50` · `q14_gt_m8_pad75` ·
`q14_lt_m0` · `q16_eq_m2`)가 있고, 케이스마다 `expected_result.json` 과 라운드별
mask 전후 파일을 비교합니다. mask 워드는 `row = index>>5`, `bit = index&31` 입니다.
`q16_eq_m2` 는 폐기된 Q16 확장의 기록이라 Q14 보드 구현의 검증으로 인용하지 않습니다.
두 방식을 고른 경위는
[다중결과탐색_Enumeration_두방식_골든모델.md](다중결과탐색_Enumeration_두방식_골든모델.md)
에 있습니다.

## 7. 검증 상태

| 항목 | 상태 |
|---|---|
| Common500 4,000행 결과 | 완료 |
| NumPy ↔ Qiskit 논리 정합성 | 500/500 |
| Fixed Normal ↔ 보드 Normal | 500/500 |
| K4/H4 · K3/H3 모델 ↔ 보드 물리 반복 수 | 각 500/500 |
| requested-j 벡터 | 256케이스 포함 |
| 열거 벡터 | 두 방식 × 5케이스 |
| DRAM all-j 보드 시간 | 측정 안 함 |
| Q15/Q16 RTL · 보드 검증 | 없음 (폐기된 확장) |

## 8. 재편 때 빠졌다가 되살린 것

2026-09-13 재편에서 아래가 저장소에서 빠졌습니다. 파이프라인이 쓰는 것은 2026-09-16 에
되살렸습니다. 되살릴 때 커밋 `79b7410` 에서 꺼냈습니다 — main 의 정규 조상이라
`git show 79b7410:<경로>` 로 언제든 볼 수 있습니다.

| 빠졌던 것 | 하던 일 | 지금 |
|---|---|---|
| `csr/` (정본 JSON · `gen_csr.py` · `generated/`) | CSR 헤더와 [CSR_레지스터_규격.md](CSR_레지스터_규격.md) 생성 | **`software/contract/` 로 합쳐 복구.** 같은 깊이라 생성기 내부 경로를 안 고쳤습니다. `--check` 에 교차대조 셋을 더했습니다 |
| `contract/port_contract.tsv` · `extract_contract.py` · 인수인계 docx | 포트 계약 자동 대조 | **제자리 복구.** `check_ports.py` 가 세 갈래 모두 wrapper 19 + core 61 로 통과합니다 |
| `golden/` (옛 골든 모델과 `tools/`) | 옛 검증 벡터 · 캠페인 · bench 워크로드 생성 | **복구하지 않았습니다.** 기준모델은 `models/` 가 승계했고, 워크로드 생성기는 `rtl_vectors/tools/dump_bench_workload.py` 로 새로 썼습니다 |
| `bin/` | 옛 벡터 | `rtl_vectors/` 로 바뀌었습니다 |
| `bbht_cli.py` | 호스트 CLI (`--port mock` 포함) | **`software/host/` 로 복구.** `selftest` 와 `--port replay:<파일>` 을 더했습니다 |
| `Qiskit_Server/` · `research/` | 서버 캠페인 사본 · 다중 엔진 탐색 원본 | 복구하지 않았습니다. `experiments/` 와 `results/` 로 대체 · 결론은 [PASS2_융합과_다중엔진_탐색_실측.md](PASS2_융합과_다중엔진_탐색_실측.md) |

`golden/` 을 되살리지 않아도 되는 이유는 둘입니다. 보드 벤치가 쓴 데이터셋 다섯 개가
`experiments/common500_benchmark/inputs/datasets/` 와
`hardware_bram/firmware/bbht_paper_bench/tools/reference_dataset/` 에 sha256 이 같은
채로 남아 있어 다시 계산할 이유가 없고, 시드 로스터 100쌍도
`inputs/official_board_seed_roster.h` 와
`hardware_bram/results/2026-09-08_publication_6stage/seeds.csv` 두 곳에 같은 값으로
있습니다. 새 생성기는 그 둘을 서로 대조한 뒤 데이터셋을 복사만 하므로 numpy 도
필요 없습니다.
