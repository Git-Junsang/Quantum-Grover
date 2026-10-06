# K4/H4 single-operator final — 2026-09-04 보드 실측

## 무엇인가

`LPSoC_BBHT_K4H4_SINGLE_OPERATOR_FINAL_20260904` 릴리스입니다. 다중 연산기 갈래로
넘어가기 전에 **단일 Grover 연산기 K4/H4 설계를 동결한** 묶음입니다.

## 같은 폴더의 2026-09-01 묶음과 다른 점 — 헷갈리기 쉬움

`2026-09-01_board_benchmark_50seed/` 는 **K4/H8** 입니다. workload 는 둘이 같고
(M = 1/4/16/64/256 × 50 seed = 250쌍, EQ(12345), DATA_COUNT 16384, SHOT_CAP 100)
policy horizon 만 다릅니다.

| | K4/H8 (2026-09-01) | K4/H4 (이 폴더) |
|---|---:|---:|
| 물리 Grover 반복 | 4,134 | 4,247 |
| 총 사이클 | 13,824,806 | 7,796,908 |
| policy stall | 6,416,368 | 276,027 |
| stall 비중 | 46.4% | 3.54% |
| Normal 대비 사이클 단축 | 31.66% | 61.46% |

`grover_policy.v` 의 `MEM_ENTRIES = 미래단계수 x 1093` 이라 H8 의 DP 는 8,744
엔트리, H4 는 4,372 엔트리입니다. 깊은 DP 는 결정당 오래 걸려 stall 이 23배가
됩니다. 대신 멀리 봐서 Grover 반복을 2.7% 덜 씁니다. 즉 **H8 은 반복 2.7% 를
사려고 policy 지연을 23배 지불해 총 사이클에서 77% 손해를 봅니다.**

성능을 인용할 때는 어느 쪽 묶음인지 반드시 밝히십시오.

## 확정 수치

- 물리 반복 Normal 14,883 -> K4/H4 4,247 (-71.46%)
- 사이클 Normal 20,229,755 -> K4/H4 7,796,908 (-61.46%, 2.595x)
- 성공 Normal 250/250, K4/H4 250/250, paired 250/250, PLAN_MISMATCH 0
- policy 연산 1,508,706 (샷당 413.684), 그중 노출 stall 276,027
- 투기 은닉률 89.61% (PLAN_HIT 3397, late 353, hidden 3044)
- 구현 LUT 25,440 / FF 30,528 / BRAM 98 / DSP 68
- 타이밍 WNS +0.236 ns, TNS 0, WHS +0.015 ns, 100 MHz 클로즈
- 전력 0.465 W (dynamic 0.362 / static 0.103)

## 파일

| 파일 | 내용 |
|---|---|
| `result.txt` | 릴리스 README 원문 |
| `summary.csv` | target 별 집계 (speedup 분포 포함) |
| `per_seed.csv` | 250쌍 workload 별 반복·사이클 |
| `semantic_equivalence.csv` | 250쌍 논리 필드 일치 확인 |
| `uart_perf50.log` · `uart_perf_clean.log` | 보드 UART 원본 |
| `release.tar.gz` | 릴리스 전체 (RTL·구현 리포트·비트스트림·frozen 아카이브) |
| `paper_prep.tar.gz` | 논문용 추출물 |

`release.tar.gz` 안의 `rtl/{grover_policy,lpsoc_bbht_grover_main_ip,bbht_rvx_wrapper}.v`
는 `hardware_bram/src_v2/` 의 같은 파일들과 **바이트 동일**합니다.

## 릴리스가 스스로 그은 경계

> K4/H4 is the practical design-space knee.
> Do NOT claim exhaustive/global optimality over every K/H combination.

성능 수치는 최소 계측 clean run 에서만 나온 것이고, trace/validation 데이터는
기전·정합성 분석에만 씁니다. 샷별 requested-j 가 전부 보드에서 추적됐다고
주장하면 안 됩니다.
