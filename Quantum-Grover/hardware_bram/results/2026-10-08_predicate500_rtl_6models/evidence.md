# 여섯 configuration RTL Predicate500 — 네 predicate × 500 × 두 mode, reference model과 24,000/24,000

## 무엇인가

Six-Stage Ablation 의 여섯 build를 `make -C hardware_bram/sim predicate500 CONFIGURATION=<configuration>` 로 네 predicate(LT · GT · EQ · RANGE)
× 500 workloads × Restart mode · Checkpoint mode로 돌려 software reference model(Q1.22 bit-exact) expected result와 맞댄 결과입니다(2026-10-08).
a Checkpoint-Capacity of 4 · 4-shot Lookahead configuration의 Checkpoint mode executed iterations는 이날 expected result file에 더한 `actual_iter_k4h4` 열과 맞댑니다
(`run_predicate500_golden.py` 가 reference model의 a Checkpoint-Capacity of 4 · 4-shot Lookahead 설정으로 계산. 기존 열은 byte 단위로 그대로이고, 새 열의 EQ sum 9,058 은
Six-Stage Ablation · bench500 의 a Checkpoint-Capacity of 4 · 4-shot Lookahead executed iterations와 같습니다).

## 확정 수치

| configuration | Restart mode cycle sum (네 predicate) | Checkpoint mode cycle sum (네 predicate) | reference model 대비 |
|---|---:|---:|:-:|
| `capacity4_lookahead4_pes1_singlerow_linear` | 168,503,068 | 64,560,342 | 4,000/4,000 |
| `capacity3_lookahead3_pes1_singlerow_linear` | 168,503,068 | 64,872,728 | 4,000/4,000 |
| `capacity4_lookahead4_pes4_singlerow_linear` | 61,109,590 | 36,551,388 | 4,000/4,000 |
| `capacity3_lookahead3_pes4_singlerow_linear` | 61,109,590 | 35,090,716 | 4,000/4,000 |
| `capacity3_lookahead3_pes4_dualrow_linear` | 53,587,798 | 27,637,369 | 4,000/4,000 |
| `final` | 46,886,677 | 21,093,126 | 4,000/4,000 |

여섯 모두 `result_index` · `trial_count` · `L_BBHT` · executed iterations · predicate 판정이 실행마다 reference model과 같습니다(판정 PASS).
predicate · mode별 sum은 `summary.csv`, configuration별 보고는 `<옛 이름>_report.txt` 입니다(`k3h3_e4_m2_report.txt`처럼 file 이름은 옛 configuration 이름).

## 인용할 때

- **RTL cycle 축**입니다. harness가 predicate마다 process를 따로 돌려(reset 뒤 시작) Checkpoint mode cycle은 네 predicate를 이어 도는
  board와 memo table 청소 위치만큼 다를 수 있습니다(11장 11.5절). Restart mode cycle은 실행 이력과 무관합니다.
- EQ 열은 [2026-10-07_bench500_6models](../2026-10-07_bench500_6models/evidence.md) 와 같습니다.

## file

| file | 내용 |
|---|---|
| `<옛 이름>.csv` | harness 원본 4,000 rows (네 predicate 이어 붙임) |
| `<옛 이름>_report.txt` | `predicate500_report.py` 출력 |
| `summary.csv` | configuration × predicate × mode sum |
