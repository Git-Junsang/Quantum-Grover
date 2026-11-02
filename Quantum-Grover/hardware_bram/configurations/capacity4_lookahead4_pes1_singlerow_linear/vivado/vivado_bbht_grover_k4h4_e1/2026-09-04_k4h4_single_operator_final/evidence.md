# single-PE final release with a Checkpoint-Capacity of 4 and 4-shot Lookahead — 2026-09-04 board benchmark

## 무엇인가

`LPSoC_BBHT_K4H4_SINGLE_OPERATOR_FINAL_20260904` release입니다. 여러 PE를 쓰는 설계로
넘어가기 전에 **1 PE, a Checkpoint-Capacity of 4, 4-shot Lookahead인 설계를 동결한** 묶음입니다.

## 같은 directory의 2026-09-01 묶음과 다른 점 — 헷갈리기 쉬움

`2026-09-01_board_benchmark_50seed/`는 **a Checkpoint-Capacity of 4 and 8-shot Lookahead**입니다. workload는 둘이 같고
(1/4/16/64/256 solutions × 50 seeds = 250쌍, EQ(12345), DATA_COUNT 16384, SHOT_CAP 100)
Lookahead-Shots만 다릅니다.

| | a Checkpoint-Capacity of 4 and 8-shot Lookahead (2026-09-01) | a Checkpoint-Capacity of 4 and 4-shot Lookahead (이 directory) |
|---|---:|---:|
| executed iterations | 4,134 | 4,247 |
| 총 cycle | 13,824,806 | 7,796,908 |
| policy stall | 6,416,368 | 276,027 |
| stall 비중 | 46.4% | 3.54% |
| Restart mode 대비 cycle 단축 | 31.66% | 61.46% |

`grover_policy.v`의 `MEM_ENTRIES = 미래단계수 x 1093`이라 8-shot Lookahead의 DP는 8,744 entries, 4-shot Lookahead는 4,372 entries입니다. 깊은 DP는 결정당 오래 걸려 stall이 23×로
늘어납니다. 대신 멀리 봐서 Grover iteration을 2.7% 덜 씁니다. 즉 **8-shot Lookahead는 iteration 2.7%를
사려고 policy latency를 23× 지불해 총 cycle에서 77% 손해를 봅니다.**

성능을 인용할 때는 어느 쪽 묶음인지 반드시 밝히십시오.

## 확정 수치

- executed iterations Restart mode 14,883 -> a Checkpoint-Capacity of 4 and 4-shot Lookahead 4,247 (-71.46%)
- cycle Restart mode 20,229,755 -> a Checkpoint-Capacity of 4 and 4-shot Lookahead 7,796,908 (-61.46%, 2.595×)
- 성공 Restart mode 250/250, a Checkpoint-Capacity of 4 and 4-shot Lookahead 250/250, paired 250/250, PLAN_MISMATCH 0
- policy 연산 1,508,706 (shot당 413.684), 그중 노출 stall 276,027
- speculative planning 은닉률 89.61% (PLAN_HIT 3397, late 353, hidden 3044)
- implementation LUT 25,440 / FF 30,528 / BRAM 98 / DSP 68
- timing WNS +0.236 ns, TNS 0, WHS +0.015 ns, 100 MHz timing closure
- 전력 0.465 W (dynamic 0.362 / static 0.103)

## file

| file | 내용 |
|---|---|
| `result.txt` | release README 원문 |
| `summary.csv` | number of solutions별 집계 (speedup 분포 포함) |
| `per_seed.csv` | 250쌍 workload별 iteration · cycle |
| `semantic_equivalence.csv` | 250쌍 논리 field 일치 확인 |
| `uart_perf50.log` · `uart_perf_clean.log` | board UART 원본 |
| `release.tar.gz` | release 전체 (RTL · implementation report · bitstream · frozen archive) |
| `paper_prep.tar.gz` | 논문용 추출물 |

`release.tar.gz` 안의 `rtl/{grover_policy,lpsoc_bbht_grover_main_ip,bbht_rvx_wrapper}.v`
는 `hardware_bram/src_v2/`의 같은 file들과 **byte 동일**합니다.

## release가 스스로 그은 경계

> K4/H4 is the practical design-space knee.
> Do NOT claim exhaustive/global optimality over every K/H combination.

성능 수치는 최소 계측 clean run 에서만 나온 것이고, trace/validation data는
기전·정합성 분석에만 씁니다. shot별 requested iterations 값이 전부 board에서 추적됐다고
주장하면 안 됩니다.
