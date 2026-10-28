# 여섯 configuration 200T board Predicate500 — 네 predicate × 500 × 두 mode, reference model과 24,000/24,000

## 무엇인가

Six-Stage Ablation의 여섯 build를 원격 board AX7A200B 한 장에 차례로 굽고, `bbht_console` 과 host 도구
`software/host_fpga_develop/bbht_predicate500.py` 로 네 predicate(LT · GT · EQ · RANGE) × 500 workloads를 Restart mode · Checkpoint mode로
돌렸습니다(2026-10-08, final configuration 19:16~19:45, 나머지 다섯 21:10~23:30 KST). EQ만 잰
[2026-10-08_board500_6models](../2026-10-08_board500_6models/evidence.md) 를 네 predicate로 넓힌 것입니다.

## 확정 수치

| configuration | reference model 대비 | Restart mode cycle (RTL 대비) | Checkpoint mode cycle (RTL 대비) | Restart mode wall-clock time sum (µs) | Checkpoint mode wall-clock time sum (µs) |
|---|:-:|:-:|:-:|--:|--:|
| `capacity4_lookahead4_pes1_singlerow_linear` | 4,000/4,000 | 2,000/2,000 | 1,842/2,000 | 1,695,140 | 655,650 |
| `capacity3_lookahead3_pes1_singlerow_linear` | 4,000/4,000 | 2,000/2,000 | 1,853/2,000 | 1,695,152 | 658,677 |
| `capacity4_lookahead4_pes4_singlerow_linear` | 4,000/4,000 | 2,000/2,000 | 1,828/2,000 | 621,189 | 375,555 |
| `capacity3_lookahead3_pes4_singlerow_linear` | 4,000/4,000 | 2,000/2,000 | 1,833/2,000 | 621,202 | 360,952 |
| `capacity3_lookahead3_pes4_dualrow_linear` | 4,000/4,000 | 2,000/2,000 | 1,832/2,000 | 545,998 | 286,397 |
| `final` | 4,000/4,000 | 2,000/2,000 | 1,831/2,000 | 478,949 | 221,021 |

- **여섯 configuration 모두 결과 index · BBHT trajectory · executed iterations · predicate 판정이 reference model과 실행마다 같습니다**(sum 24,000/24,000).
  a Checkpoint-Capacity of 4, 4-shot Lookahead인 configuration의 Checkpoint mode executed iterations는 reference model이 같은 Checkpoint-Capacity · Lookahead-Shots의 policy로 낸 열과 맞댔습니다.
- **Restart mode cycle은 여섯 모두 RTL과 2,000/2,000 같습니다.**
- Checkpoint mode cycle은 1,828~1,853/2,000이 RTL과 같습니다. 어긋난 실행의 대부분은 memo table 청소 한 번의 값만큼으로,
  a Checkpoint-Capacity of 3, 3-shot Lookahead는 ±3,279 cycles, **a Checkpoint-Capacity of 4, 4-shot Lookahead는 ±4,372 cycles**입니다. board는 네 predicate를 reset 없이 이어 돌고 RTL harness는 predicate마다
  따로 돌아 청소가 일어나는 실행이 다른 것이고, 합계 차이는 configuration마다 0.1% 미만입니다.

## Six-Stage Ablation — 네 predicate sum, board wall-clock time 축

| 단계 | build · mode | wall-clock time (µs) | Stage 1 대비 | 직전 단계 대비 |
|---|---|---:|---:|---:|
| Stage 1 | `capacity4_lookahead4_pes1_singlerow_linear` mode0 | 1,695,140 | 1.000× | — |
| Stage 2 | `capacity4_lookahead4_pes1_singlerow_linear` mode1 | 655,650 | 2.585× | -61.32% |
| Stage 3 | `capacity4_lookahead4_pes4_singlerow_linear` mode1 | 375,555 | 4.514× | -42.72% |
| Stage 4 | `capacity3_lookahead3_pes4_singlerow_linear` mode1 | 360,952 | 4.696× | -3.89% |
| Stage 5 | `capacity3_lookahead3_pes4_dualrow_linear` mode1 | 286,397 | 5.919× | -20.66% |
| final configuration | `final` mode1 | 221,021 | 7.670× | -22.83% |

predicate별로 보면 Stage 1 대비 final configuration의 speedup은 predicate가 바뀌어도 거의 같습니다.

| predicate | Stage 1 (µs) | final configuration (µs) | speedup |
|---|---:|---:|---:|
| LT | 419,836 | 55,292 | 7.593× |
| GT | 443,960 | 57,055 | 7.781× |
| EQ | 425,622 | 55,919 | 7.611× |
| RANGE | 405,722 | 52,755 | 7.691× |

## 읽는 법

- EQ 한 predicate의 ablation study([board500_6models](../2026-10-08_board500_6models/evidence.md), 7.659×)와 네 predicate 합의 ablation study가
  같은 모양입니다. implementation 방식별 이득이 특정 predicate에 기대지 않는다는 근거입니다.
- final configuration의 네 predicate sum은 100T board의 2026-10-04 benchmark(Restart mode 478,975 · Checkpoint mode 221,032 µs)와 거의 같고,
  4 PEs의 Restart mode(`capacity4_lookahead4_pes4_singlerow_linear` · `capacity3_lookahead3_pes4_singlerow_linear` mode0, 621,189 · 621,202 µs)는 100T board의 2026-10-04 No-Checkpoint Baseline(621,210 µs)과 거의 같습니다.

## 인용할 때

- **board wall-clock time 축, 200T board**입니다. 성능 세 축의 Board-Verified Build(2026-09-07 build, 100T, EQ 500)와 섞어 speedup을 만들지 마십시오.
- 합계를 인용할 때는 네 predicate 2,000 실행의 sum인지, EQ 500의 sum인지 함께 적으십시오.
- RTL은 [2026-10-08_predicate500_rtl_6models](../2026-10-08_predicate500_rtl_6models/evidence.md) 입니다.

## file

| file | 내용 |
|---|---|
| `summary.csv` | configuration × predicate × mode: reference model 일치 · RTL cycle 일치 · cycle sum · wall-clock time sum |

실행별 원본은 각 configuration의 `vivado/vivado_<프로젝트>/2026-10-08_ax7a200b_board_predicate500/` 에 있습니다.
