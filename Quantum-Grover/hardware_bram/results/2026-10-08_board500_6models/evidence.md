# 여섯 configuration 200T board 500 runs — 같은 board에서 implementation 방식별 wall-clock time

## 무엇인가

Six-Stage Ablation의 여섯 build(현행 `hardware_bram/src/` 에 configuration adapter만 달리 물림)를 원격 board
AX7A200B 한 장에 2026-10-08 18:28~18:49 KST에 차례로 굽고, 같은 app `bbht_paper_bench` 로 같은 500 workloads
(1 · 4 · 16 · 64 · 256 solutions × 100 seeds, EQ)를 Restart mode · Checkpoint mode 두 mode로 잰 결과입니다. bitstream은 200T에서
100T resource 예산을 걸어 구현했습니다([2026-10-07_impl_6models](../2026-10-07_impl_6models/evidence.md)).

**여섯 configuration 모두 board와 RTL bench500이 논리 넷과 cycle까지 1,000/1,000 같습니다**
([2026-10-07_bench500_6models](../2026-10-07_bench500_6models/evidence.md)). app 자체 판정도 여섯 모두 PASS입니다.

## 확정 수치 — build별

| configuration | mode0 cycle | mode0 wall-clock time (µs) | mode1 cycle | mode1 wall-clock time (µs) | Stage 1 대비 (mode1) |
|---|---:|---:|---:|---:|---:|
| `capacity4_lookahead4_pes1_singlerow_linear` | 42,308,335 | 425,322 | 16,249,048 | 164,725 | 2.582× |
| `capacity3_lookahead3_pes1_singlerow_linear` | 42,308,335 | 425,310 | 16,386,112 | 166,103 | 2.561× |
| `capacity4_lookahead4_pes4_singlerow_linear` | 15,324,548 | 155,476 | 9,161,217 | 93,841 | 4.532× |
| `capacity3_lookahead3_pes4_singlerow_linear` | 15,324,548 | 155,483 | 8,812,672 | 90,350 | 4.707× |
| `capacity3_lookahead3_pes4_dualrow_linear` | 13,429,380 | 136,532 | 6,933,385 | 71,551 | 5.944× |
| `final` | 11,785,382 | 120,077 | 5,328,877 | 55,529 | 7.659× |

## Six-Stage Ablation — board wall-clock time 축

| 단계 | build · mode | wall-clock time (µs) | Stage 1 대비 | 직전 단계 대비 |
|---|---|---:|---:|---:|
| Stage 1 | `capacity4_lookahead4_pes1_singlerow_linear` mode0 | 425,322 | 1.000× | — |
| Stage 2 | `capacity4_lookahead4_pes1_singlerow_linear` mode1 | 164,725 | 2.582× | -61.27% |
| Stage 3 | `capacity4_lookahead4_pes4_singlerow_linear` mode1 | 93,841 | 4.532× | -43.03% |
| Stage 4 | `capacity3_lookahead3_pes4_singlerow_linear` mode1 | 90,350 | 4.707× | -3.72% |
| Stage 5 | `capacity3_lookahead3_pes4_dualrow_linear` mode1 | 71,551 | 5.944× | -20.81% |
| final configuration | `final` mode1 | 55,529 | 7.659× | -22.39% |

Stage 1은 Six-Stage Ablation과 같게 `capacity4_lookahead4_pes1_singlerow_linear` build의 mode0입니다. checkpoint hardware를 뺀 `capacity0_pes1_singlerow_linear` build는
resource 근거로만 썼고 board에서 돌리지 않았습니다. 그 build는 bench500에서 executed iterations · shot마다 2 cycles씩,
합계 0.18% 빠릅니다([capacity0_pes1_singlerow_linear bench500](../../configurations/capacity0_pes1_singlerow_linear/results/2026-10-08_bench500/evidence.md)).

## 읽는 법

- 같은 board · 같은 app · 같은 workload라 **implementation 방식만 다른 비교**입니다. 논문의 "동일 hardware에서 implementation
  방식별 비교"가 이 표입니다.
- 200T의 Stage 1 → final configuration speedup은 100T Board-Verified Build(425,502 → 55,798 µs, 7.626×)와 거의 같습니다. 같은
  cycle에 실행마다 붙는 고정 시간만 조금 다릅니다.
- 1 PE에서는 a Checkpoint-Capacity of 3, 3-shot Lookahead가 a Checkpoint-Capacity of 4, 4-shot Lookahead보다 조금 느립니다. bench500 cycle도 같은 방향이라 benchmark 오차가 아닙니다.
  Checkpoint-Capacity · Lookahead-Shots 축소의 이득은 4 PEs에서 나옵니다.
- final configuration은 세 번 쟀습니다(18:28, 18:47, 18:49). cycle은 세 번 모두 bench500과 같고, wall-clock time은
  Checkpoint mode 55,535 · 55,531 · 55,529 µs, Restart mode 120,083 · 120,074 · 120,077 µs로 6 µs 안입니다.
  이 표의 final configuration 값은 18:49 benchmark입니다.

## 인용할 때

- **board wall-clock time 축, 200T board**입니다. 성능 세 축의 Board-Verified Build(2026-09-07 build, 100T)와 섞어 speedup을 만들지
  마십시오. 이 묶음은 2026-10-04 묶음처럼 같은 board 위 revision 사이 비교의 인용처입니다.
- RTL cycle 축은 bench500 묶음, resource는 impl 묶음(Arty 100T)에서 인용합니다.
- ORCA 1 core 대비 speedup은 아직 200T에서 재지 않았습니다.

## file

| file | 내용 |
|---|---|
| `summary.csv` | configuration × mode 총계 (cycle · wall-clock time · bench500 일치) |
| `by_target.csv` | configuration × mode × number of solutions |

실행별 원본과 UART log는 각 configuration의 `vivado/vivado_<프로젝트>/2026-10-08_ax7a200b_board_500run/` 에 있습니다.
