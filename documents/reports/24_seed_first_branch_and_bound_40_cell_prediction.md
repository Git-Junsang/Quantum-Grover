# 실험 24. full-bound seed-first 40 cells 계산과 후보 선정

## 결론

Restricted-B, Rolling Lookahead, Iteration-Count Predictor와 root tie-break를 그대로 유지한 채
`full-horizon admissible lower bound + seed-first exact DFS`(Seed-First Branch and Bound)를 Common500 전체에
적용했습니다. Checkpoint-Capacity 1~5와 Lookahead-Shots 1~8의 40 cells, policy 결정 총 296,120회 비교에서 기존 exact
policy와 checkpoint 선택 불일치는 **0건**입니다.

모든 cell에 같은 full-bound search를 적용한 a Checkpoint-Capacity of 3 and 3-shot Lookahead 예상 총 cycles 5,242,686을 공정한
기준으로 사용하면 다음 14 cells가 더 빠릅니다.

- a Checkpoint-Capacity of 3과 4-shot ~ 5-shot Lookahead
- a Checkpoint-Capacity of 4와 3-shot ~ 8-shot Lookahead
- a Checkpoint-Capacity of 5와 3-shot ~ 8-shot Lookahead

현재 RTL interface가 지원하는 Checkpoint-Capacity 3 · 4만 보면 **a Checkpoint-Capacity of 4 and 5-shot Lookahead가 5,110,637 cycles로 최저**입니다.
a Checkpoint-Capacity of 5까지 이론적으로 허용하면 a Checkpoint-Capacity of 5 and 6-shot Lookahead가 5,083,988 cycles로 최저지만, a Checkpoint-Capacity of 5 and 5-shot Lookahead보다 겨우
1,231 cycles 빠른 대신 bound pipeline이 약 440 LUT 더 필요합니다. 또한 현재
checkpoint slot과 tuple interface는 Checkpoint-Capacity 4까지만 구현되어 있으므로 a Checkpoint-Capacity of 5 결과는 algorithm
후보이지 즉시 synthesis 가능한 configuration은 아닙니다.

## 1. 40 cells의 exact search 양

각 결정에서 모든 legal action의 full-horizon relaxed bound를 먼저 계산하고, 가장 작은
bound의 action 하나를 exact DFS로 먼저 평가한 뒤 canonical order로 나머지를 안전하게
pruning했습니다. relaxed bound는 Checkpoint-Capacity 제한만 제거하므로 admissible하고, 결과 policy는
변하지 않습니다.

아래는 pruning 후 실제 생성된 action 수/결정입니다.

| Checkpoint-Capacity \ Lookahead-Shots | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2.00 | 3.00 | 4.00 | 5.00 | 6.00 | 7.00 | 8.00 | 9.00 |
| 2 | 2.87 | 4.36 | 6.05 | 8.17 | 10.83 | 14.62 | 19.84 | 26.93 |
| 3 | 3.31 | 5.07 | 6.93 | 9.08 | 11.69 | 15.42 | 21.17 | 30.77 |
| 4 | 3.57 | 5.52 | 7.68 | 10.03 | 12.70 | 16.02 | 20.53 | 27.43 |
| 5 | 3.68 | 5.80 | 8.16 | 10.84 | 13.86 | 17.49 | 22.11 | 28.57 |

a Checkpoint-Capacity of 4 and 8-shot Lookahead는 기존 985.09 actions/결정에서 27.43으로 97.22% 감소했고, a Checkpoint-Capacity of 5 and 8-shot Lookahead는
2,566.47에서 28.57로 98.89% 감소했습니다. a Checkpoint-Capacity of 1은 legal branch가 사실상 하나이므로
full-bound로 줄일 search가 없습니다.

## 2. pre-scan을 포함한 policy cycles

기존 Checkpoint-Capacity 3 · 4, 1-shot ~ 8-shot Lookahead standalone RTL 16 cells에서 다음 core cycle model을 얻었습니다.

```text
core = 0.88710657 × actions
     + 15.19916609 × states
     + 21.52000029 × decisions
R² = 0.999886
```

hardware는 후보별 bound를 모두 저장하지 않고 최소 후보 하나만 저장하는 저저장
2-pass 구조로 가정했습니다. 각 frame에서 첫 pass는 seed를 찾고, seed의 exact 값을
얻은 뒤 canonical action을 다시 생성합니다. bound pipeline은 후보를 1 cycle마다 받고,
현재 남은 Lookahead 깊이만큼 drain한다고 계산했습니다.

```text
예상 policy cycles
  = core
  + number of pre-scan candidates
  + 2 × 각 frame의 실제 remaining-depth sum
```

즉 pre-scan의 후보 issue와 첫/둘째 pass의 pipeline drain을 모두 포함한 값입니다.
모든 bound를 frame별로 저장하는 1-pass 구조보다 느리지만 추가 대형 action/bound 저장소가
필요하지 않습니다.

| Checkpoint-Capacity \ Lookahead-Shots | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 284,966 | 404,053 | 523,140 | 642,227 | 761,313 | 880,400 | 999,487 | 1,118,573 |
| 2 | 302,775 | 443,389 | 598,536 | 788,022 | 1,019,117 | 1,337,140 | 1,763,802 | 2,334,163 |
| 3 | 304,917 | 444,729 | **590,569** | 750,309 | 931,559 | 1,168,860 | 1,497,418 | 1,993,548 |
| 4 | 306,539 | 446,556 | 593,099 | 746,274 | **909,928** | 1,094,578 | 1,317,737 | 1,617,333 |
| 5 | 306,801 | 447,889 | 595,109 | 750,100 | 913,906 | **1,091,587** | 1,290,571 | 1,528,986 |

a Checkpoint-Capacity of 4 and 8-shot Lookahead는 현재 2-step early-prune RTL의 18,354,629 cycles보다 91.19% 작을 것으로
예상됩니다. 다만 위 값은 cycle model이며 새 search logic의 RTL benchmark 값은 아닙니다.

## 3. Lookahead 단계별 bound pipeline LUT/FF

후보마다 Checkpoint-Capacity + Lookahead-Shots + 1개(아래 식의 `U`)의 universe entry를 두고 다음을 한 stage에서 수행하는 구조로
계산했습니다.

- 7-bit predecessor eligibility 비교와 balanced max tree
- relaxed pool interval 포함 여부 계산
- 11-bit 누적 비용 갱신
- relaxed mask, 원래 candidate mask, valid/tag 등록

구조식은 다음과 같습니다.

```text
LUT_est = Lookahead-Shots × (24U + 32),  U = Checkpoint-Capacity + Lookahead-Shots + 1
FF_est  = Lookahead-Shots × (2U + 14)
```

LUT는 synthesis mapping error를 고려해 ±25% 범위로 사용해야 합니다. 아래 표는 median
`LUT/FF`이며 기존 memo table, action generator, seed controller는 포함하지 않은 bound
pipeline 단독 증가량입니다. 추가 BRAM은 0으로 가정합니다.

| Checkpoint-Capacity \ Lookahead-Shots | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 104/20 | 256/44 | 456/72 | 704/104 | 1,000/140 | 1,344/180 | 1,736/224 | 2,176/272 |
| 2 | 128/22 | 304/48 | 528/78 | 800/112 | 1,120/150 | 1,488/192 | 1,904/238 | 2,368/288 |
| 3 | 152/24 | 352/52 | 600/84 | 896/120 | 1,240/160 | 1,632/204 | 2,072/252 | 2,560/304 |
| 4 | 176/26 | 400/56 | 672/90 | 992/128 | **1,360/170** | 1,776/216 | 2,240/266 | 2,752/320 |
| 5 | 200/28 | 448/60 | 744/96 | 1,088/136 | 1,480/180 | **1,920/228** | 2,408/280 | 2,944/336 |

verification용 pipeline microkernel도 만들었지만 현재 환경은 유효한 Vivado license가 없어
OOC synthesis가 시작되지 않았습니다. 따라서 이 표는 구조 기반 예상치이며 implementation resource로
인용하면 안 됩니다. 특히 기존 Arty A7-100T implementation은 slice 94.45%였으므로 LUT 숫자가
남더라도 placement · routing 위험은 큽니다.

## 4. a Checkpoint-Capacity of 3 and 3-shot Lookahead보다 빠른 cell

system 총 cycles은 기존 final configuration Common500 benchmark를 anchor로 계산했습니다.

```text
기준 benchmark total     = 5,328,877
기준 executed iterations = 9,582
기준 policy stall        = 172,066
고정 부분                = 2,588,835
iteration 비용           = 268 cycles/iteration
stall 노출계수           = 172,066 / 1,183,308 = 0.145411

total_est(Checkpoint-Capacity, Lookahead-Shots)
  = 2,588,835
  + 268 × executed_iterations(Checkpoint-Capacity, Lookahead-Shots)
  + 0.145411 × estimated_policy_cycles(Checkpoint-Capacity, Lookahead-Shots)
```

stall 노출계수는 집계 기반 근사입니다. policy와 Grover 실행의 실제 overlap은 workload마다
다르므로 최종 판단에는 integrated RTL이 필요합니다. 현재 단계에서는 모든 cell을 같은
가정으로 비교하기 위한 예상치입니다.

| Checkpoint-Capacity \ Lookahead-Shots | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 7,923,808 | 7,941,125 | 7,958,441 | 7,975,758 | 7,993,074 | 8,010,391 | 8,027,707 | 8,045,024 |
| 2 | 5,907,554 | 5,632,397 | 5,560,621 | 5,565,394 | 5,608,914 | 5,646,046 | 5,701,119 | 5,784,324 |
| 3 | 5,761,537 | 5,395,143 | **5,242,686** | 5,210,170 | 5,213,210 | 5,243,964 | 5,284,236 | 5,358,255 |
| 4 | 5,634,473 | 5,326,265 | 5,168,818 | 5,124,896 | **5,110,637** | 5,116,315 | 5,140,992 | 5,186,701 |
| 5 | 5,544,463 | 5,277,147 | 5,139,898 | 5,097,312 | 5,085,219 | **5,083,988** | 5,101,130 | 5,134,190 |

공정 기준인 full-bound a Checkpoint-Capacity of 3 and 3-shot Lookahead보다 빠른 14 cells는 다음과 같습니다.

| Checkpoint-Capacity | Lookahead-Shots | policy 예상 | total 예상 | a Checkpoint-Capacity of 3 and 3-shot Lookahead 대비 절감 | bound LUT/FF | 현재 RTL 지원 |
|:-:|:-:|---:|---:|---:|---:|---:|
| 3 | 4 | 750,309 | 5,210,170 | 32,516 | 896/120 | 지원 |
| 3 | 5 | 931,559 | 5,213,210 | 29,476 | 1,240/160 | 지원 |
| 4 | 3 | 593,099 | 5,168,818 | 73,868 | 672/90 | 지원 |
| 4 | 4 | 746,274 | 5,124,896 | 117,790 | 992/128 | 지원 |
| **4** | **5** | **909,928** | **5,110,637** | **132,049** | **1,360/170** | **지원** |
| 4 | 6 | 1,094,578 | 5,116,315 | 126,371 | 1,776/216 | 지원 |
| 4 | 7 | 1,317,737 | 5,140,992 | 101,694 | 2,240/266 | 지원 |
| 4 | 8 | 1,617,333 | 5,186,701 | 55,985 | 2,752/320 | 지원 |
| 5 | 3 | 595,109 | 5,139,898 | 102,788 | 744/96 | 미지원 |
| 5 | 4 | 750,100 | 5,097,312 | 145,374 | 1,088/136 | 미지원 |
| 5 | 5 | 913,906 | 5,085,219 | 157,467 | 1,480/180 | 미지원 |
| **5** | **6** | **1,091,587** | **5,083,988** | **158,698** | **1,920/228** | **미지원** |
| 5 | 7 | 1,290,571 | 5,101,130 | 141,556 | 2,408/280 | 미지원 |
| 5 | 8 | 1,528,986 | 5,134,190 | 108,496 | 2,944/336 | 미지원 |

기존 benchmark(a Checkpoint-Capacity of 3 and 3-shot Lookahead) 5,328,877과만 비교하면 a Checkpoint-Capacity of 4 and 2-shot Lookahead와 a Checkpoint-Capacity of 5 and 2-shot Lookahead도 각각 2,612 cycles,
51,730 cycles 빠르게 나오지만, 이는 기존 a Checkpoint-Capacity of 3 and 3-shot Lookahead에는 full-bound 개선을 적용하지 않은
비대칭 비교입니다. 따라서 최종 survivor에는 넣지 않았습니다.

## 판단

- **첫 RTL 대상:** a Checkpoint-Capacity of 4 and 5-shot Lookahead. 현재 지원 범위에서 예상 총 cycles 최저입니다.
- **저위험 대안:** a Checkpoint-Capacity of 4 and 4-shot Lookahead. a Checkpoint-Capacity of 4 and 5-shot Lookahead보다 14,259 cycles만 느리고 pipeline 예상량은
  368 LUT, 42 FF 작습니다.
- **a Checkpoint-Capacity of 4 and 6-shot Lookahead 이상:** a Checkpoint-Capacity of 4 and 5-shot Lookahead보다 resource도 많고 예상 총 cycles도 크므로 현재 model에서는
  성능 implementation 후보가 아니라 heatmap/정확도 자료용입니다.
- **a Checkpoint-Capacity of 5 후보:** a Checkpoint-Capacity of 5 and 5-shot Lookahead가 실용적인 균형점입니다. a Checkpoint-Capacity of 5 and 6-shot Lookahead의 추가 이득은 1,231 cycles뿐이라
  fifth checkpoint slot과 tuple 확장을 정당화하지 못합니다.

다음 implementation 단계에서는 a Checkpoint-Capacity of 4 and 4-shot Lookahead와 a Checkpoint-Capacity of 4 and 5-shot Lookahead 두 cell만 full-bound RTL로 만들어 standalone cycle,
통합 policy stall, placement · routing resource를 확인하는 것이 가장 안전합니다.

## 재현 자료

- 40 cells exact search script: `hardware_bram/sim/policy_search_method1.py`
- cycle/resource 분석기: `hardware_bram/sim/policy_full40_analysis.py`
- bound pipeline 추정 microkernel: `hardware_bram/sim/full_bound_pipeline_estimate.v`
- 40 cells 원시 search 결과: `hardware_bram/results/2026-10-26_policy_search_full40_seedfull/method1_search.csv`
- 전체 예상치: `hardware_bram/results/2026-10-26_policy_search_full40_seedfull/full40_estimates.csv`
- survivor CSV: `hardware_bram/results/2026-10-26_policy_search_full40_seedfull/survivors_vs_fullbound_k3h3.csv`
- heatmap: `hardware_bram/results/2026-10-26_policy_search_full40_seedfull/full40_estimates_heatmap.png`
