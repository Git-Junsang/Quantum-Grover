# No-Checkpoint Baseline — 네 predicate × 500 workloads, software reference model과 2,000/2,000

## 무엇인가

`no_checkpoint_baseline` 의 configuration(4 PEs만 켜고 checkpoint · Policy Engine ·
Measurement Unit 최적화(Dual-Row Build · Two-Level Select)를 끈 것)을 `make -C hardware_bram/configurations/no_checkpoint_baseline/sim predicate500` 으로
LT · GT · EQ · RANGE 각각 500 workloads에 걸어 돌린 결과입니다. 이 revision에는 checkpoint가
없으므로 Restart mode만 돌렸고, 실행은 2,000번입니다.

- harness·stimulus·expected result는 checkpoint revision
  [`2026-09-25_predicate500_rtl`](../../../final/results/2026-09-25_predicate500_rtl/evidence.md)
  과 같습니다 (`tb_predicate500.cpp` 에 `PRED500_MODES=normal`)
- RTL은 `hardware_bram/src/` 의 Bus Interface · Accelerator Core에 이 revision의 adapter
  (`hardware_bram/configurations/no_checkpoint_baseline/src/bbht_grover_core_adapter.v`) 를 끼운 것입니다

## 확정 수치 1 — software reference model 대조

| predicate | 실행 | rc | result_index | predicate verification | trial_count | L_BBHT | actual_iter |
|---|---:|---:|---:|---:|---:|---:|---:|
| LT | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| GT | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| EQ | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| RANGE | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |

`actual_iter` 는 expected result의 `NORMAL` 열과 맞댔습니다(`predicate500_report.py --branch no_checkpoint_baseline`).

## 확정 수치 2 — checkpoint만 뺐고 다른 것은 안 바뀌었다

이 revision이 "checkpoint revision에서 checkpoint만 뺀 것"인지를 cycle로 확인했습니다. 기준은
checkpoint revision의 Accelerator Core(a Checkpoint-Capacity of 3, 3-shot Lookahead, 4 PEs)를 **Single-Row Build · Linear Select로 build해 Restart mode로 돌린 것**입니다
(`make predicate500-ref`). checkpoint revision의 Restart mode는 4 PEs의 amplitude memory 중 checkpoint slot 0만 쓰고
Checkpoint Planner · Checkpoint Executor · Policy Engine을 거치지 않으므로, 그 hardware를 generate로 뺀 이 revision과
모든 열이 같아야 합니다.

| predicate | workload | 8 열 전부 같음 | cycle sum |
|---|---:|---:|---:|
| LT | 500 | 500/500 | 15,185,717 |
| GT | 500 | 500/500 | 15,847,085 |
| EQ | 500 | 500/500 | 15,324,548 |
| RANGE | 500 | 500/500 | 14,752,240 |
| sum | 2,000 | **2,000/2,000** | 61,109,590 |

8 열은 `rc` · `result_index` · `result_value` · `trial` · `l_bbht` · `iter` · `cycles` ·
`status` 입니다 (`equiv.txt`, `sim/equiv_check.py`).

## 최적화 유무에 따른 속도 (RTL cycle, 같은 2,000 workloads)

세 열 모두 같은 harness로 돌린 RTL cycle(clk_accel 100 MHz)입니다. 가운데와 오른쪽은
[checkpoint revision 묶음](../../../final/results/2026-09-25_predicate500_rtl/per_workload.csv)의
Restart mode · Checkpoint mode 열입니다.

| predicate | 이 revision (4 PEs) | checkpoint revision의 Restart mode (4 PEs, Dual-Row Build · Two-Level Select) | checkpoint revision (final configuration) | 첫째 → 둘째 열 | 둘째 → 셋째 열 | 첫째 → 셋째 열 |
|---|---:|---:|---:|---:|---:|---:|
| LT | 15,185,717 | 11,625,100 | 5,274,562 | 1.306× | 2.204× | **2.879×** |
| GT | 15,847,085 | 12,241,889 | 5,456,355 | 1.295× | 2.244× | **2.904×** |
| EQ | 15,324,548 | 11,785,382 | 5,328,877 | 1.300× | 2.212× | **2.876×** |
| RANGE | 14,752,240 | 11,234,306 | 5,033,332 | 1.313× | 2.232× | **2.931×** |
| sum | 61,109,590 | 46,886,677 | 21,093,126 | 1.303× | 2.223× | **2.897×** |

number of solutions별 (네 predicate sum):

| number of solutions | 이 revision (4 PEs) | checkpoint revision (final configuration) | speedup |
|---:|---:|---:|---:|
| 1 | 27,115,030 | 8,933,416 | 3.035× |
| 4 | 15,522,312 | 5,280,002 | 2.940× |
| 16 | 9,515,432 | 3,401,845 | 2.797× |
| 64 | 5,766,444 | 2,181,551 | 2.643× |
| 256 | 3,190,372 | 1,296,312 | 2.461× |

읽는 법:

- **checkpoint(a Checkpoint-Capacity of 3, 3-shot Lookahead)가 2.2×, Measurement Unit 최적화(Dual-Row Build · Two-Level Select)가 1.3×**를 벌고, 둘을 합치면 같은 4 PEs
  위에서 약 2.9×입니다. 희소할수록(solution이 적을수록) checkpoint 몫이 큽니다
- executed iterations는 이 revision과 checkpoint revision의 Restart mode가 같고(LT 30,875 등), checkpoint revision의
  Checkpoint mode 열은 그 30% 정도입니다(LT 9,355). checkpoint는 executed iterations를, Dual-Row Build · Two-Level Select는 measurement
  한 번의 cycle을 줄입니다
- checkpoint revision의 Checkpoint mode 열에는 predicate마다 reset 뒤 첫 checkpoint search의 memo table 청소
  3,279 cycles가 한 번씩 들어 있습니다 (그 묶음의 "인용할 때")

## 인용할 때

- 이것은 **RTL cycle 축**입니다. board wall-clock time이나 Common500 software 시간과
  speedup을 만들지 마십시오 (CLAUDE.md 2절).
- Six-Stage Ablation([`2026-09-08_publication_6stage`](../../../../results/2026-09-08_publication_6stage/evidence.md))
  은 EQ 한 predicate · workload마다 새로 시작 · a Checkpoint-Capacity of 4, 4-shot Lookahead 단계를 거친 ablation study라 이 표와 단계가
  다릅니다. 두 표의 speedup을 섞지 마십시오. 이 표는 **같은 4 PEs 위에서 최적화를 켜고
  끈 것** 하나만 말합니다.
- board benchmark는 아직입니다. bitstream은
  [`bitstream/2026-09-25_nocheckpoint/`](../../bitstream/2026-09-25_nocheckpoint/evidence.md),
  board에서는 `software/host_fpga_develop/bbht_predicate500.py` 가 이 revision을 알아보고 Restart mode 2,000 실행을 돕니다.

## 재현

```bash
python3 software/reference_model_develop/predicate500/run_predicate500_golden.py   # 기댓값 (30초)
make -C hardware_bram/configurations/no_checkpoint_baseline/sim predicate500        # 이 판 (술어 넷 동시, 2분쯤)
make -C hardware_bram/configurations/no_checkpoint_baseline/sim predicate500-ref    # 기준 (2분쯤)
make -C hardware_bram/configurations/no_checkpoint_baseline/sim equiv
```

## file

| file | 내용 |
|---|---|
| `per_workload.csv` | 실행 2,000 rows. 열은 checkpoint revision 묶음과 같음 |
| `report.txt` | `predicate500_report.py --branch no_checkpoint_baseline` 출력 |
| `equiv.txt` | `equiv_check.py` 출력 (기준 대조 2,000/2,000) |
