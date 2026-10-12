# 실험 14. Common500 소프트웨어 · FPGA 비교

> [← 실험 13 Main IP 최종 발표 (v1.3)](13_Main_IP_최종_발표.md) · [index](index.md) · [실험 15 통신 계층 교체판 보드 콘솔 →](15_교체판_보드_콘솔.md)

---

| 확인한 것 | 근거의 축 |
|---|---|
| 소프트웨어 기준모델(고정소수점 · 체크포인트 정책)이 보드 세 구성과 워크로드마다 같은 궤적 · 물리 반복을 내는가, NumPy 와 Qiskit 이 서로 같은가 | 보드 실경과 시간(2026-09-08 보드 정본 CSV) · 서버 소프트웨어 실행(2026-09-11) |

2026-09-08 보드 정본([실험 12](12_보드_정본_500런.md))과 같은 500 워크로드를 소프트웨어 백엔드 다섯과 보드 실측
셋에 걸어 4,000행을 냈습니다. 서버 실행은 2026-09-11 입니다. 기준모델 자체의 구조는
[4장](../design_references/04_소프트웨어_기준모델과_정답_벡터.md)에 있습니다.

보드와 같은 500 워크로드를 백엔드 여덟에 걸어 4,000행을 냅니다.

| 축 | 값 |
|---|---|
| M (타겟 수) | 1, 4, 16, 64, 256 |
| 시드 | M 마다 공식 로스터 100쌍 |
| 워크로드 | 총 500 |
| 데이터셋과 오라클 | 보드와 같은 5개 데이터셋, `EQ` |
| 소프트웨어 backend | NumPy, Qiskit Aer, Fixed Normal, K4/H4, K3/H3 |
| 입력 | 데이터셋 5개 · 시드 로스터 [`software/testbench_data/2026-09-08_common500/`](../../software/testbench_data/2026-09-08_common500/2026-09-08_common500.md) |
| FPGA backend | Normal, K4/H4, K3/H3-E4-M2. 2026-09-08 보드 500런 묶음의 `per_run_*.csv` 원본을 그대로 읽음 ([board_500run](../../hardware_bram/models/hardware_bram_K3H3_E4_M2/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/evidence.md)) |

## 다시 돌리기

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r software/golden_develop/common500/requirements.txt
bash software/golden_develop/common500/run_full_benchmark.sh
bash software/golden_develop/common500/check_benchmark_status.sh    # 진행 상황
```

스크립트는 자기 위치를 기준으로 경로를 잡으므로 저장소 어디서 불러도 됩니다. `python` 을
부르므로 가상환경을 켜 둔 상태여야 하고, NumPy · Aer 스레드는 1로 고정합니다. 중간에
끊겨도 같은 명령을 다시 부르면 `software_resume_records.jsonl` 을 읽고 끝난 backend 를
건너뜁니다.

## 정합성 결과

비교는 짝을 지어 합니다. NumPy · Qiskit 은 float64 측정이라 Q1.22 쪽과 궤적이 같을 이유가
없으므로 둘끼리만 맞대고, 고정소수점 모델은 같은 정책의 보드 구성과 맞댑니다.

| 검사 | 비교 필드 | 결과 |
|---|---|---:|
| NumPy ↔ Qiskit | `result_index` · `trial_count` · `L_BBHT` | 500/500 |
| Fixed Normal ↔ 보드 Normal | 위 셋 + `actual_grover_iterations` | 500/500 |
| K4/H4 모델 ↔ 보드 K4/H4 | 논리 셋 / 물리 반복 | 500/500 / 500/500 |
| K3/H3 모델 ↔ 보드 K3/H3-E4-M2 | 논리 셋 / 물리 반복 | 500/500 / 500/500 |
| 보드 세 구성끼리 | 논리 셋 | 500/500 |

체크포인트는 논리 결과를 바꾸면 안 되고, 같은 정책이면 모델과 보드의 물리 반복 수도 같아야
합니다. 두 조건이 모두 500/500 입니다.

## 시간은 측정 경계가 서로 다릅니다

| backend | 무엇을 쟀나 |
|---|---|
| NumPy | 상태벡터 계산 코어만 |
| Qiskit | Aer 실행만 (회로 build · transpile 은 원시 결과의 별도 열) |
| 고정소수점 모델들 | 파이썬 벽시계 |
| FPGA | 보드의 명령 발행부터 결과까지. DMA 적재 제외 |

FPGA 구성끼리의 배수만 성능 주장에 씁니다(M = 1 에서 Normal 대비 9.192x, 전체 7.626x).
서버 소프트웨어와 보드의 절대시간 비율은 플랫폼과 측정 경계가 달라 참고값입니다. 같은 칩
위의 대조군은 ORCA 1코어 기준선이고, 그 배수에 붙일 단서는
[1장 1.5절](../design_references/01_프로젝트_개요.md#15-성능-지표와-인용-기준)에 있습니다.

## 결과 파일

모두 [`software/golden_data/2026-09-11_common500/`](../../software/golden_data/2026-09-11_common500/)에 있습니다.

| 파일 | 내용 |
|---|---|
| [`2026-09-11_common500.md`](../../software/golden_data/2026-09-11_common500/2026-09-11_common500.md) | 실험 조건, 정합성, 성능표, 해석 규칙 |
| `common500_all_backend_results.csv` | 4,000행 워크로드별 원시 결과 |
| `common500_summary_by_target_count.csv` | M · backend 별 성공률, trial, 반복 수, 시간 |
| `common500_workload_correctness.csv` | NumPy↔Qiskit · 모델↔FPGA 일치 여부 |
| `fpga_configuration_speedup.csv` | FPGA Normal · K4/H4 · 최종 구성 시간과 배수 |
| `checkpoint_model_fpga_iteration_delta.csv` | 체크포인트 모델과 FPGA 물리 반복 수 차이 |
| `fpga_runtime_by_target_count.svg` · `software_runtime_by_target_count.svg` | M 별 시간 그래프 |
| `software_resume_records.jsonl` | 중단 복구용 실행 기록 |
| `experiment_manifest.json` | 서버 환경(Python 3.12.3, qiskit 2.5.2, qiskit-aer 0.17.2, numpy 2.5.3)과 입력 SHA-256 |

---
