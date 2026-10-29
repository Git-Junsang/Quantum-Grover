# 최적성 증명 조기 종료와 병렬 Scan — 2026-10-28

a Checkpoint-Capacity of 3 · 3-shot Lookahead · 4 PEs · Triple-Row Build · policy search mode 6의 같은 Common500에서 후보 순회·필터와 응답·종료 구간을 각각
절반 이하로 줄였습니다. restricted-B 후보 공간, root 비용·segment·tuple 동점 규칙,
실제 실행 결과와 executed iterations는 유지했습니다. 큰 Checkpoint-Capacity · Lookahead-Shots에서의 전체 성능과 새 RTL의 200T PPA는 별도입니다.

## source와 조건

설정은 `config.json`, DSE 입력 hash는 `manifest.json`, benchmark에 쓴 source는 `source/`입니다.
a Checkpoint-Capacity of 3 · 3-shot Lookahead · 4 PEs · Triple-Row Build 한 configuration만 Common500 전체를 실행했습니다. 부품은 `xc7a200tfbg484-2`,
accelerator 목표는 100 MHz이며 이 조건만으로 routing timing 통과를 뜻하지 않습니다.

| RTL | SHA-256 |
|---|---|
| grover_policy.v | 5aa95f551cc74e0b5ff5454df775fc13bf241ed0557bc792fa348ba347818b3d |
| bbht_grover_main_ip.v | d949759b1dc3ae85b4d1b4f336f00f3636c1e94c8c47bee0737eb42f8b306712 |

baseline은 [직전 검증 revision](../2026-10-28_policy_parallel_paths_verified/evidence.md)입니다.
profile은 같은 최종 Verilator model archive에 읽기 전용 관측기만 연결합니다.
`bench_profile.csv`와 최종 `bench.csv`가 byte-identical인지 `summarize.py`에서 검사합니다.

## RTL 변경과 정확성

### 최소 lower bound를 달성한 seed의 즉시 종료

Scan은 root에서 lower bound 비용, segment 수, 값으로 정렬한 checkpoint tuple 순서의 최소 후보를
선택합니다. 값의 대소 관계와 insertion ID 순서는 다르므로 ID 순서를 동점 비교에 쓰지 않습니다.
내부 state는 비용만 비교합니다. seed의 정확한 비용이 Scan의 최소 lower bound와 같으면 어떤 후보도
더 좋은 결과를 낼 수 없습니다. root에서도 나머지 두 동점 field를 포함한 최소 optimistic key를
선택했으므로 같은 증명이 성립합니다. 그때 CANON 전체를 생략합니다.

최소 lower bound는 DFS frame에 보존하고 child 반환 시 hot mirror로 복원합니다. 전역 Scan accumulator를
그대로 비교하면 child의 Scan 값과 혼동하므로 사용하지 않습니다. 직접 memo table 응답과 child 반환
경로 모두 검사합니다. 증명으로 생략한 나머지 후보 수는 prune counter에 반영합니다.

### request 두 개가 남은 내부 state의 정확한 직접 계산

현재 request를 처리한 다음 마지막 request 하나만 남으면, 마지막 request의 비용은 만들 수 있는 가장
가까운 predecessor 하나에만 의존합니다. endpoint는 항상 선택 가능하고, 각 기존 checkpoint는
zero-deposit action에서 선택할 수 있습니다. 각 eligible intermediate도 one-deposit action에서
선택할 수 있습니다. Checkpoint-Capacity ≥ 2이면 이 값 각각은 적어도 하나의 합법 후보에서 실현 가능합니다.
따라서 이 합집합의 가장 가까운 predecessor로 정확한 minimum을 구할 수 있습니다.

이 단축은 선택 tuple이 필요 없는 내부 state에만 적용합니다. root는 실제 tuple과 동점 규칙을
반환해야 하므로 그대로 Scan합니다. 남은 비용을 lower bound로 대체하는 근사가 아닙니다.
해당 state의 Scan·SEED·CANON을 생략하고 정확한 값을 memo table에 기록합니다.

### 후보 생성부터 저장까지 4개 병렬 처리

독립 lane마다 후보 compaction, gap bound와 tuple canonicalization을 수행하고, 균형 잡힌
reduction으로 묶음의 최소 후보를 고릅니다. cache도 묶음의 후보를 서로 다른 bank에 동시에 씁니다.
기존 numeric-mask 후보 순서, deposit-size 경계, 마지막 부분 묶음을 보존합니다.

solver의 `SCAN_LANES`와 Accelerator Core의 `POLICY_SCAN_LANES`를 추가했습니다. 기본값은 각각
`CANON_LANES`·`POLICY_CANON_LANES`이며 현재 생산 기본값은 모두 4입니다. 1/2/4를 지원하고
Scan 폭은 CANON cache bank 수 이하여야 합니다. 유한 action budget은 Scan 1개씩 처리하며,
이번 두 조기 종료는 ACTION_LIMIT=0일 때 사용합니다. budget 동작 전체를 새로 검증한 것은 아닙니다.

lower bound의 유용한 3단 data 계산 pipeline register와 동기 memo table 응답 정렬은 유지합니다. WNS용 actionq/mreq/areq를
복구하거나 제어 latency 단계를 추가하지 않았습니다. segment 비용 사전 계산표는 추가하지 않았습니다.
우선 search 자체를 줄이고 병렬 Scan을 적용한 결과로 두 구간의 절반 감소를 달성했습니다.

### cache 선행 읽기와 종료 통합

현재 묶음을 소비하는 edge에서 다음 묶음을 읽습니다. seed 결과 수신 또는 부모 복귀 평가 중에도
첫 replay 묶음을 미리 읽습니다. 마지막 후보가 모두 탈락하면 별도 빈 종료 판정 edge를 생략합니다.
miss·frame 전환 시 유효성을 지우고 frame별 address를 유지합니다.

### root initialization의 작업 이동

이전 200T implementation의 최악 경로는 root ID를 universe 값으로 바꾸고 정렬한 뒤 frame 값에 쓰는 경로입니다.
입력 snapshot의 실제 checkpoint 값을 기존 Build 시간에 정렬해 보존하고 ROOT_INIT에서 사용하도록
옮겼습니다. 정렬은 universe Build와 병행하며 새 제어 cycle은 없습니다. 이 변경의 실제 PPA 효과는
새 implementation으로 확인해야 합니다.

## Common500 RTL 결과

| 지표 | 직전 revision | 수정 revision | 감소 |
|---|---:|---:|---:|
| 후보 순회·필터 | 34,304 | 5,089 | 85.1650%, 6.74× |
| 응답·종료 처리 | 46,378 | 13,080 | 71.7970%, 3.55× |
| 통합 policy cycles | 161,272 | 80,719 | 49.9485% |
| 단독 policy cycles, 7,403 decisions | 146,666 | 74,068 | 49.4989% |
| 실제 policy stall | 17,715 | 17,483 | 1.3096% |
| 전체 Checkpoint mode 실행 cycles | 4,523,062 | 4,522,830 | 232 cycles |
| 단독 최대 latency | 466 | 410 | 56 cycles |
| executed iterations | 9,582 | 9,582 | 동일 |

원자료는 `summary.csv`, `target_comparison.csv`, `profile.json`, `comparison.json`입니다.
`summarize.py`는 두 목표 구간이 각각 절반 이하인지 assert합니다. Restart mode · Checkpoint mode 1,000 rows의
결과, shot, requested · executed iterations, mismatch가 같고 Restart mode row는 모든 field가 같습니다.
`dse.validate_bench`의 reference model BBHT trajectory와 workload별 executed iterations verification도 통과합니다.

이번에는 계산 대부분이 Grover iteration 실행과 겹쳐서, policy 작업 감소가 전체 실행 시간 감소로 그대로
이어지지 않습니다. solver와 scheduler 시간을 독립 항목처럼 더하면 중복 계산입니다.

### 구간 정의와 관측

후보 순회는 Scan 발행 cycle과 CANON filter cycle의 sum입니다. 응답·종료는 Scan drain,
cache fetch, CANON memo table response, CANON finish cycle의 sum입니다. 유효한 응답 처리도 포함하며,
전부 불필요한 빈 cycle을 뜻하지 않습니다. SEED wait와 DFS RETURN/PREP/FINISH는 이 두 항목 밖입니다.
이는 직전 revision의 분류와 같습니다.

- Scan 발행 28,166 → 5,089 cycles. 실제 lower bound 출력 후보 수는 28,166 → 13,048개입니다.
- Scan drain 31,512 → 13,080 cycles. 4,360 frames에 3 cycles씩 남습니다.
- 관측한 3-shot Lookahead에서 root 2,180개와 내부 2,180개가 seed 최적성 증명으로 종료했습니다.
- 내부 2,180개는 두 request suffix를 직접 계산했습니다. 이 Common500에서는 CANON replay 자체가
  필요 없어 cache fetch/filter/memo response/finish가 모두 0입니다. 8-shot Lookahead에도 항상 0이라는 뜻은 아닙니다.
- Scan 묶음 크기 1/2/3/4의 cycle 수는 각각 1,143/667/2,545/734입니다.
- raw solver busy 81,483과 집계 policy 80,719의 차이 764는 stale 완료 두 건입니다.
- 실제 stall 17,483 중 solver busy 3,956, solver가 busy가 아닌 구간 13,527입니다.
- scheduler의 Planner 준비 state는 직전 revision과 같은 7,403 cycles이며 이번에는 변경하지 않았습니다.

## 정확성 verification

`run_units.py`는 frozen source로 15개 변형, 총 2,232 cases를 실행하며 모두 errors=0입니다.
결정은 별도 Exhaustive DFS(policy search mode 0)와 대조하고, 각 lane의 모든 bound와 replay cache의 bound는
순차 relaxed algorithm으로 독립 계산해 대조합니다. `unit_results.json`과 각 log에 보존합니다.

- a Checkpoint-Capacity of 3 · 3-shot Lookahead, policy search mode 5 · 6, Scan · CANON lanes 1/2/4 및 SCAN1/CANON4.
- 1-shot · 2-shot Lookahead 경계, a Checkpoint-Capacity of 3 · 4-shot Lookahead와 a Checkpoint-Capacity of 4 · 4-shot Lookahead, maximum · zero · 중복 request · 비연속 checkpoint slot · 값/ID 순서 차이.
- a Checkpoint-Capacity of 4 · 8-shot Lookahead, policy search mode 5 · 6 각 37 cases. universe 13, root 후보 220, child miss 후 부모 복구와 root equal-cost 검사.
- 8-shot Lookahead cache 1/2/4 bank 및 SCAN1/CANON4 추가 집중 검사 각 13 cases. 실제 CANON miss·memo table hit,
  seed skip·4개 후보 pruning과 cache 선행 읽기를 관측합니다. policy search mode 5의 4-lane 8-shot Lookahead에서 겹친 읽기 409회입니다.
- 단일 root shortcut 268 cases. initial·epoch wrap·soft reset의 memo table clear 3회와 1-cycle 반환을 확인했습니다.

Verilator 경고는 92 → 94개입니다. 추가 2개는 폭이 정해진 constant parameter 변환 경고이며
지원하는 Checkpoint-Capacity · Lookahead-Shots 범위에서 값 손실은 없습니다. 새 latch·UNOPTFLAT·SIDEEFFECT 경고는 없습니다.
기존 arithmetic의 pre_node UNOPTFLAT와 기존 latch 경고는 남아 있습니다.

## 전체 SoC와 200T

최종 source를 `/opt/rvx/platform/bbht_grover_policy_scan_verified_20261028`에 설치했습니다.
생성 adapter를 포함한 RTL 14개가 snapshot과 byte-identical이며 `soc_source_sha256.json`에 보존했습니다.
최종 Questa console은 5분 07초, Errors 0 / Warnings 0으로 완료했습니다. RUN·STAT·ENUM 출력을
같은 최종 source의 Verilator console replay와 대조해 90개 항목이 모두 일치합니다.
`soc_qtsim.log`, `console_reference.csv`, `soc_equivalence.json`, `verify_soc.py`가 근거입니다.
ENUM index 순서는 8685, 2852, 507, 4724입니다.

기존 historical checker는 같은 source 비교를 통과하지만 과거 final configuration cycle 값과 차이 5건으로 exit 5를
반환합니다. `soc_crosscheck.txt`에 보존했으며 현재 configuration은 별도 `verify_soc.py`로 검증했습니다.
과거 기록의 cycle 기준을 변경해 통과시킨 것은 아닙니다.

앞서 요청받아 한 번 조회한 기존 200T implementation은 bitstream을 생성했지만 WNS -0.321 ns로
setup 미통과, WHS +0.048 ns로 hold 통과입니다. 이는 policy SHA 77e2f67d…의 이전 revision 결과이며
새 RTL의 timing·resource로 인용하지 않습니다. 조회한 사실은 `prior_200t_result.json`에 보존했습니다.

최종 source의 200T implementation을 같은 platform에서 `--threads=2 --app=bbht_console`로 background에서 시작했습니다.
`implementation_start.log`와 `implementation_manifest.json`에 시작과 입력을 기록했습니다.
시작 뒤에는 사용자 request에 따라 완료 여부·진행 log·PPA 결과를 조회하지 않았습니다.
따라서 새 RTL의 timing·resource는 아직 판단하지 않으며 commit하지 않았습니다. 전체 Checkpoint-Capacity · Lookahead-Shots sweep 및 board benchmark는
이번 작업에 포함하지 않습니다. 큰 Checkpoint-Capacity · Lookahead-Shots에서도 Common500 총 policy 300,000 cycles 이하라는
목표를 달성했다고 판단할 근거는 아직 없습니다.

## 문서 검사

전체 문서 검사의 오류 62건·경고 6건은 기존 papers 이동 경로와 memo table 절 anchor 등의 진단입니다.
이번 변경 전후 진단 목록은 같으며 새 진단은 없습니다. 전체 문서 검사가 통과한 것은 아닙니다.

## 재현

Common500은 `dse.py --config config.json --out <새 결과 directory> --stages policy,sim,report`입니다.
단일 solver 변형은 `python3 run_units.py --case k4h8_mode6`처럼 선택합니다. 관측기는
`run_observers.py`, 두 감소 목표와 BBHT trajectory 비교는 `summarize.py`, SoC console 비교는 `verify_soc.py`입니다.
과거 benchmark value와 historical checker의 cycle 기준은 바꾸지 않습니다.
