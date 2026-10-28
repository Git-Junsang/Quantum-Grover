# 여섯 configuration RTL bench500 — board app과 같은 순서로 500 workloads × 두 mode

## 무엇인가

board에서 configuration 사이 비교를 하기 전에, 같은 공용 RTL(`hardware_bram/src/`)을 configuration adapter parameter만 달리 물린 여섯 configuration을 `make -C hardware_bram/sim bench500 CONFIGURATION=<configuration>`로 돌린 결과입니다. 이 testbench는 board app `bbht_paper_bench`와 같은 순서(number of solutions 바깥 · seed 안쪽 · seed마다 Restart mode 다음 Checkpoint mode, reset 없이 연달아)로 500 workloads(1/4/16/64/256 solutions × 100 seeds, EQ)를 돌립니다. final configuration에서는 이 testbench와 board benchmark가 cycle까지 500/500 일치했으므로([2026-09-10_bench500_final_core](../../configurations/final/results/2026-09-10_bench500_final_core/evidence.md)), 다른 configuration도 board 결과를 이 표와 맞대 판정할 수 있습니다.

모든 build의 mode0(Restart mode)은 checkpoint hardware가 쉬는 경로로 돌아, number of PEs와 Measurement Microarchitecture가 같은 checkpoint 없는 revision과 cycle이 같습니다([20장](../../../documents/design_references/20_no_checkpoint_baseline.md)). 그래서 여섯 build × 두 mode로 checkpoint 유무 · number of PEs · Measurement Microarchitecture의 조합이 함께 나옵니다.

## 확정 수치

| configuration | mode0 Restart mode cycle | mode1 Checkpoint mode cycle | Checkpoint mode executed iterations | policy stall | BBHT trajectory |
|---|---:|---:|---:|---:|:-:|
| `capacity4_lookahead4_pes1_singlerow_linear` | 42,308,335 | 16,249,048 | 9,058 | 538,433 (3.31%) | 500/500 |
| `capacity3_lookahead3_pes1_singlerow_linear` | 42,308,335 | 16,386,112 | 9,582 | 104,009 (0.63%) | 500/500 |
| `capacity4_lookahead4_pes4_singlerow_linear` | 15,324,548 | 9,161,217 | 9,058 | 611,581 (6.68%) | 500/500 |
| `capacity3_lookahead3_pes4_singlerow_linear` | 15,324,548 | 8,812,672 | 9,582 | 116,695 (1.32%) | 500/500 |
| `capacity3_lookahead3_pes4_dualrow_linear` | 13,429,380 | 6,933,385 | 9,582 | 132,576 (1.91%) | 500/500 |
| `final` | 11,785,382 | 5,328,877 | 9,582 | 172,066 (3.23%) | 500/500 |

Restart mode executed iterations는 여섯 모두 31,424, 총 shot은 두 mode 모두 7,403입니다. `plan_fifo_mismatch`는 여섯 모두 0입니다. BBHT trajectory는 같은 seed에서 Restart mode와 Checkpoint mode의 `result_index` · `trial_count` · `L_BBHT`가 같은 쌍의 수입니다.

## Six-Stage Ablation과의 대조

| configuration | Six-Stage Ablation executed iterations | 이 testbench | Six-Stage Ablation cycle | 이 testbench cycle | 차이 |
|---|---:|---:|---:|---:|---:|
| Stage 1 (`capacity4_lookahead4_pes1_singlerow_linear` mode0) | 31,424 | 31,424 | 42,308,335 | 42,308,335 | +0 |
| Stage 2 (`capacity4_lookahead4_pes1_singlerow_linear` mode1) | 9,058 | 9,058 | 18,349,320 | 16,249,048 | -2,100,272 |
| Stage 3 (`capacity4_lookahead4_pes4_singlerow_linear` mode1) | 9,058 | 9,058 | 11,246,755 | 9,161,217 | -2,085,538 |
| Stage 4 (`capacity3_lookahead3_pes4_singlerow_linear` mode1) | 9,582 | 9,582 | 10,385,795 | 8,812,672 | -1,573,123 |
| Stage 5 (`capacity3_lookahead3_pes4_dualrow_linear` mode1) | 9,582 | 9,582 | 8,500,620 | 6,933,385 | -1,567,235 |
| final configuration (`final` mode1) | 9,582 | 9,582 | 6,890,470 | 5,328,877 | -1,561,593 |

- **executed iterations는 다섯 configuration 모두 Six-Stage Ablation과 정확히 같습니다.** configuration adapter가 tag `board-k3h3-e4-m2`의 standalone top이 넘기던 policy parameter를 그대로 옮겼다는 근거입니다.
- **Restart mode cycle은 Six-Stage Ablation Stage 1과 한 자리까지 같습니다.**
- **Checkpoint mode cycle은 이 testbench가 모두 작고, 차이가 policy별로 거의 일정합니다**(a Checkpoint-Capacity of 3 and 3-shot Lookahead 계열 약 157만, a Checkpoint-Capacity of 4 and 4-shot Lookahead 계열 약 209만). Restart mode에서는 차이가 0이므로 checkpoint 경로에서만 생기는 차이입니다. Six-Stage Ablation은 workload마다 따로 simulation했고 이 testbench는 reset 없이 연달아 도므로, policy memo table state가 이어지는 효과([11장 11.5절](../../../documents/design_references/11_checkpoint_and_policy_engine.md#115-memo-table-initialization-3279--381-cycles))로 보이지만 **확인하지 않은 추정**입니다.
- final configuration의 Checkpoint mode 5,328,877 · Restart mode 11,785,382는 2026-09-10 bench500과 2026-09-08 board 500 runs benchmark cycle과 같습니다. 그 뒤 main의 `src/` 변경이 final configuration의 동작을 바꾸지 않았습니다.

## 이 숫자를 쓸 때의 경계

- **RTL cycle 축**입니다. Six-Stage Ablation의 cycle과 섞어 speedup을 만들지 마십시오. board와 맞는 쪽은 이 testbench입니다.
- 성능 세 축의 인용은 지금처럼 Board-Verified Build(2026-09-07)에서 합니다. 이 표는 configuration 사이 비교와 200T board benchmark의 expected result입니다.
- 이 campaign을 돌릴 때의 `bench500_report.py`는 모든 configuration을 final configuration의 기준값과만 대조해서, `capacity4_lookahead4_pes1_singlerow_linear` · `capacity4_lookahead4_pes4_singlerow_linear`가 executed iterations가 a Checkpoint-Capacity of 3 and 3-shot Lookahead와 달라 `actual_iter 343/500`으로 FAIL을 내고 exit 2로 끝났습니다. a Checkpoint-Capacity of 4 and 4-shot Lookahead policy에서는 정상인 차이입니다. 2026-10-08에 보고를 configuration별로 고쳤습니다(`CONFIGURATION`을 받아 Six-Stage Ablation의 해당 stage와 대조하고, board 500 runs · 250쌍 대조는 final configuration에서만 함). 고친 보고로 여섯 CSV를 다시 읽으면 여섯 모두 통과하고, Six-Stage Ablation 대조가 있는 다섯 configuration은 논리 넷이 500/500입니다.
- 원본 CSV의 `mode` 열은 Checkpoint mode를 configuration과 무관하게 `k4`로 적습니다(옛 이름). 위 표의 mode1입니다.

## board 결과를 맞대는 법

200T board에서 `bbht_paper_bench`로 잰 결과는 `hardware_bram/sim/board_vs_bench500.py <UART log 또는 raw CSV> --configuration <configuration>`로 이 묶음의 CSV와 workload마다 맞댑니다. 논리 넷이 어긋나면 실패이고, cycle은 일치 수만 보여 주며 `--strict-cycles`로 실패에 넣을 수 있습니다.

같은 script로 100T board의 2026-09-08 500 runs를 맞대 본 결과입니다.

| board benchmark | 맞댄 configuration | 논리 넷 | cycle_count | cycle sum (board / testbench) |
|---|---|:-:|:-:|---:|
| final configuration (mode1) | `final` | 500/500 | **500/500** | 5,328,877 / 5,328,877 |
| a Checkpoint-Capacity of 4 and 4-shot Lookahead (mode1) | `capacity4_lookahead4_pes1_singlerow_linear` | 500/500 | 0/500 | 16,242,353 / 16,249,048 (-0.04%) |
| Restart mode (mode0) | `capacity4_lookahead4_pes1_singlerow_linear` | 500/500 | 0/500 | 42,300,932 / 42,308,335 (-0.02%) |

a Checkpoint-Capacity of 4 and 4-shot Lookahead와 Restart mode board benchmark는 1 PE 시절의 옛 RTL bitstream으로 낸 것이라 cycle이 byte 단위로 같을 이유가 없습니다. 그래도 BBHT trajectory가 500/500 같고 cycle이 0.04% 안이라, 현행 `capacity4_lookahead4_pes1_singlerow_linear` configuration이 그 옛 configuration을 충실히 옮겼다는 보조 근거가 됩니다.

## 실행 조건

- 2026-10-07 22:25~22:38 KST, 세 configuration씩 두 묶음, configuration 사이 2분 간격으로 시작. configuration마다 workload directory를 따로 줬습니다(`BENCH500_WL=/tmp/sjs_bench500_wl_<configuration>`).
- configuration당 2~6분 걸렸습니다(Makefile의 "40분쯤" 은 이 server 기준으로 맞지 않습니다). 최대 memory `capacity4_lookahead4_pes1_singlerow_linear` 0.26 GiB · `capacity3_lookahead3_pes1_singlerow_linear` 0.26 GiB · `capacity4_lookahead4_pes4_singlerow_linear` 0.38 GiB · `capacity3_lookahead3_pes4_singlerow_linear` 0.38 GiB · `capacity3_lookahead3_pes4_dualrow_linear` 0.37 GiB · `final` 0.37 GiB.
- dataset 5벌의 sha256과 seed roster가 Six-Stage Ablation campaign과 같음을 testbench가 매번 확인했습니다.

## file

| file | 내용 |
|---|---|
| `summary.csv` | configuration × mode 총계 |
| `by_target.csv` | configuration × mode × number of solutions |
| `k4h4_e1.csv` 등 여섯 (옛 configuration 이름) | testbench 원본 1,000 rows (500 workloads × 두 mode) |
