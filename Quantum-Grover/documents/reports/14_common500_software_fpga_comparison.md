# 실험 14. Common500 software · FPGA 비교

> [← 실험 13 Accelerator Core 최종 발표 (v1.3)](13_accelerator_core_final_presentation.md) · [index](index.md) · [실험 15 Bus Interface revision board console →](15_revised_bus_interface_board_console.md)

---

| 확인한 것 | 근거의 축 |
|---|---|
| software reference model(fixed-point · checkpoint policy)이 board 세 구성과 workload마다 같은 BBHT trajectory · executed iterations를 내는가, NumPy와 Qiskit이 서로 같은가 | board wall-clock time(2026-09-08 Board-Verified Build CSV) · server software 실행(2026-09-11) |

2026-09-08 Board-Verified Build([실험 12](12_board_verified_build_500_runs.md))와 같은 500 workloads를 software backend 다섯과 board benchmark
셋에 걸어 4,000 rows를 냈습니다. server 실행은 2026-09-11입니다. reference model 자체의 구조는
[4장](../design_references/04_software_reference_model_and_test_vectors.md)에 있습니다.

board와 같은 500 workloads를 backend 여덟에 걸어 4,000 rows를 냅니다.

| 축 | 값 |
|---|---|
| number of solutions | 1, 4, 16, 64, 256 |
| seed | number of solutions 값마다 공식 seed roster 100쌍 |
| workload | 총 500 |
| dataset과 oracle | board와 같은 5 datasets, `EQ` |
| software backend | NumPy, Qiskit Aer, Fixed Restart mode, a Checkpoint-Capacity of 4 and 4-shot Lookahead, a Checkpoint-Capacity of 3 and 3-shot Lookahead |
| 입력 | 5 datasets · seed roster [`software/testbench_data/2026-09-08_common500/`](../../software/testbench_data/2026-09-08_common500/2026-09-08_common500.md) |
| FPGA backend | Restart mode, a Checkpoint-Capacity of 4 and 4-shot Lookahead, final configuration. 2026-09-08 board 500 runs 묶음의 `per_run_*.csv` 원본을 그대로 읽음 ([board_500run](../../hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/evidence.md)) |

## 다시 돌리기

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r software/reference_model_develop/common500/requirements.txt
bash software/reference_model_develop/common500/run_full_benchmark.sh
bash software/reference_model_develop/common500/check_benchmark_status.sh    # 진행 상황
```

script는 자기 위치를 기준으로 경로를 잡으므로 저장소 어디서 불러도 됩니다. `python`을
부르므로 virtual environment를 켜 둔 상태여야 하고, NumPy · Aer thread는 1로 고정합니다. 중간에
끊겨도 같은 명령을 다시 부르면 `software_resume_records.jsonl`을 읽고 끝난 backend를
건너뜁니다.

## 정합성 결과

비교는 짝을 지어 합니다. NumPy · Qiskit은 float64 measurement라 Q1.22 쪽과 BBHT trajectory가 같을 이유가
없으므로 둘끼리만 맞대고, fixed-point model은 같은 policy의 board 구성과 맞댑니다.

| 검사 | 비교 field | 결과 |
|---|---|---:|
| NumPy ↔ Qiskit | `result_index` · `trial_count` · `L_BBHT` | 500/500 |
| Fixed Restart mode ↔ board Restart mode | 위 셋 + `actual_grover_iterations` | 500/500 |
| a Checkpoint-Capacity of 4 and 4-shot Lookahead model ↔ board a Checkpoint-Capacity of 4 and 4-shot Lookahead | 논리 셋 / executed iterations | 500/500 / 500/500 |
| a Checkpoint-Capacity of 3 and 3-shot Lookahead model ↔ board final configuration | 논리 셋 / executed iterations | 500/500 / 500/500 |
| board 세 구성끼리 | 논리 셋 | 500/500 |

checkpoint는 논리 결과를 바꾸면 안 되고, 같은 policy면 model과 board의 executed iterations도 같아야
합니다. 두 조건이 모두 500/500입니다.

## 시간은 benchmark 경계가 서로 다릅니다

| backend | 무엇을 쟀나 |
|---|---|
| NumPy | state vector 계산 kernel만 |
| Qiskit | Aer 실행만 (circuit build · transpile은 원시 결과의 별도 열) |
| fixed-point model들 | Python wall-clock time |
| FPGA | board의 명령 발행부터 결과까지. DMA load 제외 |

FPGA 구성끼리의 speedup만 성능 주장에 씁니다(1 solution에서 Restart mode 대비 9.192×, 전체 7.626×).
server software와 board의 절대시간 비율은 platform과 benchmark 경계가 달라 참고값입니다. 같은 chip
위의 대조군은 ORCA 1 core baseline이고, 그 speedup에 붙일 단서는
[1장 1.5절](../design_references/01_project_overview.md#15-성능-지표와-인용-기준)에 있습니다.

## 결과 file

모두 [`software/reference_model_data/2026-09-11_common500/`](../../software/reference_model_data/2026-09-11_common500/)에 있습니다.

| file | 내용 |
|---|---|
| [`2026-09-11_common500.md`](../../software/reference_model_data/2026-09-11_common500/2026-09-11_common500.md) | 실험 조건, 정합성, 성능표, 해석 규칙 |
| `common500_all_backend_results.csv` | 4,000 rows workload별 원시 결과 |
| `common500_summary_by_target_count.csv` | number of solutions · backend별 성공률, shots, iterations, 시간 |
| `common500_workload_correctness.csv` | NumPy↔Qiskit · model↔FPGA 일치 여부 |
| `fpga_configuration_speedup.csv` | FPGA Restart mode · a Checkpoint-Capacity of 4 and 4-shot Lookahead · final configuration 시간과 speedup |
| `checkpoint_model_fpga_iteration_delta.csv` | checkpoint model과 FPGA executed iterations 차이 |
| `fpga_runtime_by_target_count.svg` · `software_runtime_by_target_count.svg` | number of solutions별 시간 graph |
| `software_resume_records.jsonl` | 중단 복구용 실행 기록 |
| `experiment_manifest.json` | server 환경(Python 3.12.3, qiskit 2.5.2, qiskit-aer 0.17.2, numpy 2.5.3)과 입력 SHA-256 |

---
