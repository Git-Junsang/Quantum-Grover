# 체크포인트 없는 판 — 네 술어 × 500 워크로드, SW 기준모델과 2,000/2,000

## 무엇인가

`hardware_bram_nocheckpoint` 의 구성(연산기 네 벌 E4 만 켜고 체크포인트 · 정책 엔진 ·
측정 최적화 M1/M2 를 끈 것)을 `make -C hardware_bram/models/hardware_bram_nocheckpoint/sim predicate500` 으로
LT · GT · EQ · RANGE 각각 500 워크로드에 걸어 돌린 결과입니다. 이 판에는 체크포인트가
없으므로 Normal 만 돌렸고, 실행은 2,000 번입니다.

- 하네스·자극·기댓값은 체크포인트 판
  [`2026-09-25_predicate500_rtl`](../../../hardware_bram_K3H3_E4_M2/results/2026-09-25_predicate500_rtl/evidence.md)
  과 같습니다 (`tb_predicate500.cpp` 에 `PRED500_MODES=normal`)
- RTL 은 `hardware_bram/src/` 의 통신 계층 · Main IP 에 이 판의 어댑터
  (`hardware_bram/models/hardware_bram_nocheckpoint/src/bbht_grover_core_adapter.v`) 를 끼운 것입니다

## 확정 수치 1 — SW 기준모델 대조

| 술어 | 실행 | rc | result_index | 술어 검증 | trial_count | L_BBHT | actual_iter |
|---|---:|---:|---:|---:|---:|---:|---:|
| LT | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| GT | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| EQ | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |
| RANGE | 500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 | 500/500 |

`actual_iter` 는 기준모델 `NORMAL` 열과 맞댔습니다(`predicate500_report.py --branch nocheckpoint`).

## 확정 수치 2 — 체크포인트만 뺐고 다른 것은 안 바뀌었다

이 판이 "체크포인트 판에서 체크포인트만 뺀 것" 인지를 사이클로 확인했습니다. 기준은
체크포인트 판 Main IP(K3/H3, E4)를 **M1=M2=0 으로 빌드해 Normal 로 돌린 것**입니다
(`make predicate500-ref`). 체크포인트 판의 Normal 은 E4 진폭 메모리의 슬롯 0 만 쓰고
Planner · Executor · 정책 엔진을 거치지 않으므로, 그 하드웨어를 generate 로 뺀 이 판과
모든 열이 같아야 합니다.

| 술어 | 워크로드 | 8 열 전부 같음 | 사이클 합 |
|---|---:|---:|---:|
| LT | 500 | 500/500 | 15,185,717 |
| GT | 500 | 500/500 | 15,847,085 |
| EQ | 500 | 500/500 | 15,324,548 |
| RANGE | 500 | 500/500 | 14,752,240 |
| 합 | 2,000 | **2,000/2,000** | 61,109,590 |

8 열은 `rc` · `result_index` · `result_value` · `trial` · `l_bbht` · `iter` · `cycles` ·
`status` 입니다 (`equiv.txt`, `sim/equiv_check.py`).

## 최적화 유무에 따른 속도 (RTL 사이클, 같은 2,000 워크로드)

세 열 모두 같은 하네스로 돌린 RTL 사이클(clk_accel 100 MHz)입니다. 가운데와 오른쪽은
[체크포인트 판 묶음](../../../hardware_bram_K3H3_E4_M2/results/2026-09-25_predicate500_rtl/per_workload.csv)의
Normal · 체크포인트 열입니다.

| 술어 | 이 판 (E4) | 체크포인트 판 Normal (E4-M2) | 체크포인트 판 (K3/H3-E4-M2) | E4 → E4-M2 | E4-M2 → K3/H3 | E4 → K3/H3-E4-M2 |
|---|---:|---:|---:|---:|---:|---:|
| LT | 15,185,717 | 11,625,100 | 5,274,562 | 1.306x | 2.204x | **2.879x** |
| GT | 15,847,085 | 12,241,889 | 5,456,355 | 1.295x | 2.244x | **2.904x** |
| EQ | 15,324,548 | 11,785,382 | 5,328,877 | 1.300x | 2.212x | **2.876x** |
| RANGE | 14,752,240 | 11,234,306 | 5,033,332 | 1.313x | 2.232x | **2.931x** |
| 합 | 61,109,590 | 46,886,677 | 21,093,126 | 1.303x | 2.223x | **2.897x** |

M 별 (네 술어 합):

| M | 이 판 (E4) | 체크포인트 판 (K3/H3-E4-M2) | 배수 |
|---:|---:|---:|---:|
| 1 | 27,115,030 | 8,933,416 | 3.035x |
| 4 | 15,522,312 | 5,280,002 | 2.940x |
| 16 | 9,515,432 | 3,401,845 | 2.797x |
| 64 | 5,766,444 | 2,181,551 | 2.643x |
| 256 | 3,190,372 | 1,296,312 | 2.461x |

읽는 법:

- **체크포인트(K3/H3)가 2.2배, 측정 최적화(M1/M2)가 1.3배** 를 벌고, 둘을 합치면 같은 E4
  연산기 위에서 약 2.9배입니다. 희소할수록(M 이 작을수록) 체크포인트 몫이 큽니다
- 물리 반복은 이 판과 체크포인트 판 Normal 이 같고(LT 30,875 등), 체크포인트 판
  체크포인트 열은 그 30% 정도입니다(LT 9,355). 체크포인트는 반복 수를, M1/M2 는 측정
  한 번의 사이클을 줄입니다
- 체크포인트 판 체크포인트 열에는 술어마다 리셋 뒤 첫 체크포인트 탐색의 memo 청소
  3,279 사이클이 한 번씩 들어 있습니다 (그 묶음의 "인용할 때")

## 인용할 때

- 이것은 **RTL 사이클 축**입니다. 보드 실경과 시간이나 Common500 소프트웨어 시간과
  배수를 만들지 마십시오 (CLAUDE.md 2절).
- 6단계 ablation([`2026-09-08_publication_6stage`](../../../../results/2026-09-08_publication_6stage/evidence.md))
  은 EQ 한 술어 · 워크로드마다 새로 시작 · K4/H4 를 거친 사다리라 이 표와 단계가
  다릅니다. 두 표의 배수를 섞지 마십시오. 이 표는 **같은 E4 연산기 위에서 최적화를 켜고
  끈 것** 하나만 말합니다.
- 보드 실측은 아직입니다. 비트스트림은
  [`bitstream/2026-09-25_nocheckpoint/`](../../bitstream/2026-09-25_nocheckpoint/evidence.md),
  보드에서는 `software/host/bbht_predicate500.py` 가 이 판을 알아보고 Normal 2,000 을 돕니다.

## 재현

```bash
python3 software/experiments/predicate500_benchmark/run_predicate500_golden.py   # 기댓값 (30초)
make -C hardware_bram/models/hardware_bram_nocheckpoint/sim predicate500        # 이 판 (술어 넷 동시, 2분쯤)
make -C hardware_bram/models/hardware_bram_nocheckpoint/sim predicate500-ref    # 기준 (2분쯤)
make -C hardware_bram/models/hardware_bram_nocheckpoint/sim equiv
```

## 파일

| 파일 | 내용 |
|---|---|
| `per_workload.csv` | 실행 2,000행. 열은 체크포인트 판 묶음과 같음 |
| `report.txt` | `predicate500_report.py --branch nocheckpoint` 출력 |
| `equiv.txt` | `equiv_check.py` 출력 (기준 대조 2,000/2,000) |
