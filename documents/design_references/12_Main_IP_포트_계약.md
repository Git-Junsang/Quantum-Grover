# 12장. Main IP 포트 계약

> [← 11장 체크포인트와 정책 엔진](11_체크포인트와_정책_엔진.md) · [문서 지도](00_문서_지도.md) · [13장 CSR 레지스터와 실행 모드 →](13_CSR_레지스터와_실행_모드.md)

---

8~11장이 Main IP 안에서 무엇이 어떻게 도는지를 다뤘다면, 이 장은 밖으로 드러나는 계약만
다룹니다. 포트의 이름 · 폭 · 방향과, 그 포트로 주고받는 트랜잭션의 순서입니다.

---

## 12.1 적용 범위

기준은 보드에서 검증된 K3/H3-E4-M2 Main IP 이고 실물 RTL 은
[`hardware_bram/src/`](../../hardware_bram/src/)에 있습니다. 2026-09-13 에
6단계 ablation 공통소스 판으로 올려서 보드 정본에 `MEAS_M1_ENABLE` · `MEAS_M2_ENABLE` 스위치(기본
1)만 더해졌고, 둘 다 1이면 동작이 같습니다. 비트스트림과 바이트 동일한 판은 태그
`board-k3h3-e4-m2` 에 있습니다.

- 합성 프로파일: Q14 / P32 / signed DATA16 / signed 23비트 진폭(소수부 22)
- 실제 top module: `bbht_grover_main_ip`
- `bbht_rvx_wrapper` 는 계약 이름 `bbht_grover_core` 를 물고, 어댑터가 이름 · 리셋
  (`rstn` → `rstnn`) 차이를 흡수합니다. 포트 61개는 1:1 로 같습니다
- `bbht_bram_top` 은 이 모듈을 어댑터 없이 직접 뭅니다

---

## 12.2 근거와 계약 파일

| 항목 | 값 |
|---|---|
| 계약 원본 | 인수인계 docx `LPSoC_BBHT_Grover_팀원_Handoff_SW_통신_v0.9.8반영_2026-09-01.docx` (`software/contract/`) |
| docx SHA-256 | `46a5d17805e52caecff4cebbfd1240f9ae7976a54e06b81d2bc391455ba748da` |
| 기계 판독 계약 | [`software/contract/port_contract.tsv`](../../software/contract/port_contract.tsv) (docx §3.3 wrapper 19개 · §3.4 Main IP 61개를 `extract_contract.py` 가 뽑음) |
| 실물 RTL | `hardware_bram/src/` |
| 소프트웨어 기준모델 | `software/models/rtl_reference_model/` ([4장](04_소프트웨어_기준모델과_정답_벡터.md)) |

`check_ports.py` 가 tsv 와 RTL 을 대조합니다(`make -C hardware_bram/sim ports ports-real`,
DRAM 갈래는 `check_ports.py dram`, 체크포인트 없는 판은 `check_ports.py nocheckpoint`). 네 갈래
모두 wrapper 19 + core 61 로 일치합니다. 아래 표는 그 tsv 를 사람이 읽으라고 옮긴 것이고, 표와
실물이 어긋나면 실물 RTL 을 따르고 표를 고칩니다. 우선순위는 실물 RTL → 이 장 → 소프트웨어
기준모델입니다.

---

## 12.3 확정 합성 파라미터

`grover_param.vh` 와 어댑터 · 최상단이 넘기는 파라미터에서 직접 뽑은 값입니다.

| 항목 | 값 |
|---|---:|
| `Q` / `INDEX_W` | 14 |
| 상태 수 `N` | 16,384 |
| 병렬도 `P` | 32 |
| 행 수 | 512 |
| `DATA_W` | signed 16 |
| `FRAC_BITS` | 22 |
| `AMP_W` | signed 23 |
| `DATA_COUNT_W` | 15 |
| `J_W` | 7 |
| BBHT `m_max` | 128 |
| BBHT 예산 | 576 |
| 기본 `shot_cap` | 100 |
| Result FIFO 깊이 | 256 |
| 체크포인트 슬롯 `CKPT_K` | 3 |
| 정책 지평 `POLICY_H_FUTURE` | 3 |
| 반복 내 연산기 `INTRA_ENGINES` | 4 |
| 측정 최적화 `MEAS_M1_ENABLE` · `MEAS_M2_ENABLE` | 1 · 1 |
| 열거 기본 `fail_repeat_limit` | 3 |

K · H · E · M 은 `grover_param.vh` 가 아니라 인스턴스에 넘기는 파라미터입니다(어댑터 기본값,
`bbht_bram_top` 의 인스턴스). CSR 실행 모드 이름은 `CKPT_SINGLE` · `CKPT_ENUM` 이고, 값이 빌드마다
달라지므로 이름에 K · H 를 박지 않습니다. 파라미터 여덟 개의 뜻은
[8장 8.2절](08_Main_IP_최상위와_BBHT_제어.md#82-컴파일-파라미터-8개)에 있습니다.

---

## 12.4 입력 포트

`clk` 과 `rstn` 은 계약표에 없습니다. 실물이 `posedge clk` 에서 `!rstn` 을 보는 동기 리셋이고,
어댑터가 RVX 쪽 이름과 맞춰 줍니다.

### 검색 · 모드

| 포트 | 폭 | 형식 | 의미 | 사용 규칙 |
|---|---:|---|---|---|
| `start` | 1 | pulse | 검색 시작 요청 | search · load 가 모두 idle 일 때만 수락 |
| `auto_shot` | 1 | unsigned | 1: BBHT 자율, 0: manual `j_target` | busy 중 변경 금지 |
| `j_target` | 7 | unsigned | manual Grover 반복 수 `0..127` | `auto_shot=0` 에서 사용 |
| `burst_enable` | 1 | unsigned | 체크포인트 재사용 | busy 중 변경 금지 |
| `enum_enable` | 1 | unsigned | 1: 열거, 0: 단일 검색 | busy 중 변경 금지 |
| `fail_repeat_limit` | 4 | unsigned | 열거에서 연속 실패 허용 횟수 `1..15` | busy 중 변경 금지 |

### 체크포인트

| 포트 | 폭 | 의미 |
|---|---:|---|
| `checkpoint_auto_enable` | 1 | 내부 정책이 슬롯을 관리 (production 설정) |
| `checkpoint_manual_enable` | 1 | 바깥에서 계획을 밀어 넣는 시험용 경로 |
| `policy_valid` | 1 | manual 계획 유효 |
| `policy_source_j` | 7 | 어느 체크포인트에서 출발할지 |
| `policy_next_count` | 3 | 이번 전진 뒤 채울 슬롯 수 |
| `policy_next_j_flat` | 28 | 그 슬롯들의 `j` (7비트 × 4. 폭은 물리 슬롯 4개 분량이고 K3 은 3개까지 씀) |

wrapper 는 `checkpoint_auto_enable = burst_enable && auto_shot` 로 유도하고 manual 쪽 입력은
전부 0으로 묶습니다([7장 7.1절](07_통신_계층.md#71-wrapper-의-제어-로직)).

### 오라클과 난수

| 포트 | 폭 | 형식 | 의미 |
|---|---:|---|---|
| `predicate_mode` | 2 | unsigned | 술어 선택 |
| `threshold_a` | 16 | signed | 술어 기준 A |
| `threshold_b` | 16 | signed | RANGE 기준 B |
| `data_count` | 15 | unsigned | 유효 데이터 수 `1..16384` |
| `shot_cap` | 16 | unsigned | 최대 BBHT attempt 수. 0이면 `config_error` |
| `seed_j` | 32 | unsigned | requested-`j` LFSR 시드. accepted `start` 에서 reload |
| `seed_meas` | 32 | unsigned | Born LFSR 시드. accepted `start` 에서 reload |

시드가 0이면 내부 대체 시드를 씁니다. 두 스트림은 독립이고, 같은 시드 쌍이면 전체 실행이
재현됩니다.

모든 비교는 signed16 이고 RANGE 는 열린 구간입니다.

| `predicate_mode` | 조건 |
|---|---|
| `2'b00` | `data < threshold_a` |
| `2'b01` | `data > threshold_a` |
| `2'b10` | `data == threshold_a` |
| `2'b11` | `threshold_a < data < threshold_b` |

`threshold_a >= threshold_b` 인 RANGE 는 config error 가 아닙니다. 타겟이 없는 조건으로 정상
동작합니다(콘솔의 `SET` 은 이것을 미리 거절합니다. [14장](14_호스트_인터페이스와_UART_프로토콜.md)).

### Loader

| 포트 | 폭 | 형식 | 의미 |
|---|---:|---|---|
| `load_start` | 1 | pulse | loader 세션 시작 |
| `data_wr_en` | 1 | enable | signed16 한 개 쓰기 |
| `data_wr_addr` | 14 | unsigned | 전역 인덱스 |
| `data_wr_data` | 16 | signed | 입력 데이터 |
| `load_done` | 1 | pulse | 적재 종료 및 개수 검사 |

---

## 12.5 출력 포트

### 실행과 결과

| 포트 | 폭 | 종류 | 의미 | 유지 규칙 |
|---|---:|---|---|---|
| `load_busy` | 1 | level | loader 세션 진행 중 | `load_done` 처리까지 |
| `busy` | 1 | level | search 또는 load 진행 중 | 전체 트랜잭션 동안 |
| `done` | 1 | pulse | 검색 종료 이벤트 | 정확히 1클록 |
| `result_valid` | 1 | sticky | 성공 결과가 존재 | 다음 accepted `start` 까지 |
| `result_index` | 14 | unsigned | 성공한 인덱스 | `result_valid=1` 에서만 유효 |

`search_busy` 는 따로 나오지 않습니다. 계약이 `busy = search_busy | load_busy` 로 정의하므로
wrapper 가 `busy & ~load_busy` 로 유도합니다.

### 결과 FIFO 와 열거

| 포트 | 폭 | 종류 | 의미 |
|---|---:|---|---|
| `res_pop` | 1 (IN) | pulse | 한 칸 꺼내기 |
| `res_dout` | 14 | data | FIFO 머리 |
| `res_empty` | 1 | level | 비었음 |
| `res_count` | 9 | counter | 남은 개수 `0..256` |
| `enum_done` | 1 | level | 열거 종료 |
| `found_count` | 15 | counter | 찾은 개수 |
| `consecutive_fail_count` | 4 | counter | 연속 실패 |
| `max_fifo_occupancy` | 9 | counter | FIFO 최대 점유 |
| `fifo_stall_cycles` | 32 | counter | FIFO full 로 멈춘 사이클 |

FIFO 가 256칸이므로 해가 그보다 많으면 full stall 이 납니다. 열거에서는 `enum_done` 만 기다리지
말고 `busy` 인 동안에도 계속 뽑아야 하고, `fifo_stall_cycles` 가 0이 아니면 소프트웨어가 늦게
뽑았다는 뜻입니다.

### 상태 비트 (전부 sticky)

| 포트 | 의미 | 해제 시점 |
|---|---|---|
| `config_error` | 설정 또는 적재된 데이터셋 불일치 | 다음 accepted `start` |
| `shot_limit` | `shot_cap` 도달 | 다음 accepted `start` |
| `budget_limit` | BBHT 예산(576) 도달 | 다음 accepted `start` |
| `amp_overflow` | 진폭 포화 발생. 진단용이고 결과 무효가 아님 | 다음 accepted `start` |
| `zero_weight_error` | Born 전체 가중치가 0 | 다음 accepted `start` |
| `load_error` | loader 개수 검사 실패 | 다음 accepted `load_start` |

### 카운터

| 포트 | 폭 | 의미 |
|---|---:|---|
| `trial_count` | 32 | 실행한 attempt 수 |
| `L_BBHT` | 32 | 요청된 `j` 의 누적합. 알고리즘 비용 |
| `actual_grover_iterations` | 32 | 체크포인트 적용 후 실제 계산량. 에뮬레이션 비용 |
| `cycle_count` | 32 | accepted start 부터 종료까지 (`clk_accel` 100 MHz) |

`L_BBHT` 와 `actual_grover_iterations` 를 섞지 않습니다. 체크포인트는 뒤엣것만 줄이고
앞엣것은 그대로 둡니다. 짝맞춤 검증이 이 성질 위에 서 있습니다.

### 정책 · plan 텔레메트리

| 포트 | 폭 | 의미 |
|---|---:|---|
| `policy_cycles_total` | 32 | 정책이 돈 총 사이클 |
| `policy_stall_cycles` | 32 | 그중 탐색을 실제로 멈춰 세운 사이클 |
| `policy_actions_eval` | 32 | 평가한 행동 수 |
| `policy_memo_hit` · `policy_memo_miss` | 32 | DP memo 적중 · 실패 |
| `policy_max_latency` | 32 | 결정 하나의 최대 지연 |
| `plan_fifo_level` · `plan_fifo_highwater` | 3 | 투기 계획 큐 |
| `plan_fifo_empty_demand` | 32 | 계획이 없어 기다린 횟수 |
| `plan_fifo_hit_count` | 32 | 투기 계획 적중 |
| `plan_fifo_mismatch_count` | 32 | 투기 계획과 실제 요청이 어긋난 횟수 |
| `policy_cold_solve_count` · `policy_spec_solve_count` | 32 | 즉시 풀이 · 투기 풀이 |

`plan_fifo_mismatch_count == 0` 은 sign-off 조건입니다. 0이 아니면 정책이 예측한 다음 요청이
실제와 달랐다는 직접 증거입니다. `policy_stall_cycles` 는 정책 지평을 고를 때의 판단 근거였고,
그 실험은 [23장 23.7절](23_설계_근거_실험.md#237-지평-h-를-줄인-이유-h8--h6--h4--h3)에 있습니다.

---

## 12.6 검색 트랜잭션

```text
Wrapper: 설정값 고정
       -> busy=0, load_busy=0 확인
       -> start 를 1클록 발생
Main IP: accepted_start
       -> 두 LFSR 시드 reload
       -> 검색 상태/카운터 클리어
       -> busy=1
       -> Grover / 측정 / 검증 수행
       -> 종료
       -> busy=0, done=1클록
       -> sticky 결과/상태와 카운터 유지
```

필수 규칙입니다.

1. `start` 는 `busy=0 && load_busy=0` 일 때만 발생시킵니다.
2. busy 중의 `start` 는 무시됩니다.
3. 설정 입력은 shadow register 가 아니라 live input 이므로 busy 중에 바꾸면 안 됩니다.
4. 폴링하는 wrapper 는 `done` 펄스를 `done_sticky` 로 바꿔 잡아야 합니다.
5. `result_index` 는 반드시 `result_valid` 와 함께 읽습니다.

`start` 뒤 다음 중 하나라도 어긋나면 `config_error=1` 로 끝납니다.

- 성공한 loader 세션으로 `data_valid=1` 이어야 함
- `1 <= data_count <= 16384`
- 현재 `data_count == loaded_count`
- `shot_cap != 0`

수동 1샷에서 측정 후보가 비타겟이면 `done=1`, `result_valid=0` 이지만 오류 · limit 비트는 서지
않습니다. 정상적인 실패입니다.

---

## 12.7 Loader 트랜잭션

```text
data_count 설정
-> load_start 1클록
-> load_busy=1 확인
-> 주소 0..data_count-1 을 한 번씩 순차 쓰기
-> 마지막 쓰기와 같은 클록 또는 그 뒤에 load_done 1클록
-> load_busy=0
-> load_error=0 확인
-> search start 허용
```

RTL 이 보장하는 것입니다.

- `addr >= expected_count` 쓰기는 무시하고 개수에도 넣지 않습니다.
- 마지막 유효 쓰기와 같은 클록의 `load_done` 도 그 쓰기를 포함해 검사합니다.
- 유효 쓰기 개수가 부족하면 `load_error=1`, `data_valid=0` 입니다.
- 적재 성공 뒤 `data_count` 가 바뀌면 `data_valid` 와 체크포인트가 무효화됩니다.

RTL loader 는 서로 다른 주소를 모두 썼는지 검사하지 않습니다. 같은 주소를 여러 번 써도 쓰기
개수가 올라가므로, wrapper 는 각 주소를 정확히 한 번씩 생성해야 합니다. 권장 assertion 입니다.

```text
data_wr_en -> load_busy
data_wr_en -> data_wr_addr < latched_data_count
accepted writes 의 주소 = 0,1,2,...,data_count-1
load_done -> accepted_write_count == data_count
```

---

## 12.8 체크포인트 계약

진폭 상태를 슬롯 3개(`CKPT_K = 3`)에 두고, 정책이 요청 `j` 마다 두 가지를 정합니다. 메모리는
물리 슬롯 4개 분량(행 위상 4뱅크 인터리브, RAMB36 44개)이고 K3 은 그중 3개를 씁니다.

1. 어느 슬롯에서 출발할 것인가 (`source_j`)
2. 이번 전진이 끝난 뒤 슬롯을 무엇으로 채울 것인가

```text
이번 요청의 물리 비용 = j - source_j        (source_j <= j)
출발할 슬롯이 없으면 균일 상태에서 시작하므로 비용 = j
```

경로 중간 상태를 슬롯에 남기는 것은 공짜입니다. `source_j` 에서 `j` 까지 전진하는 동안 그
상태가 실제로 데이터패스를 지나가기 때문입니다.

| 모드 / 조건 | 처리 | 실제 반복 수 |
|---|---|---:|
| Normal | 균일 상태 INIT 후 `j` 회 | `j` |
| 체크포인트, 쓸 슬롯 없음 | INIT 후 `j` 회 | `j` |
| 체크포인트, `j > source_j` | 그 슬롯에서 이어 계산 | `j - source_j` |
| 체크포인트, `j == source_j` | 그대로 다시 측정 | 0 |

무효화 조건은 accepted `load_start`, `predicate_mode` 변경, `threshold_a/b` 변경, `data_count`
변경입니다. 열거에서 새 타겟을 찾아 `found_mask` 가 바뀔 때도 무효화됩니다. `seed`,
`shot_cap`, `auto_shot`, `j_target`, `burst_enable` 만 바꾸는 것은 진폭의 의미를 바꾸지 않으므로
무효화하지 않습니다.

실패한 `j` 를 다음 추첨에서 빼지 않습니다. 같은 `j` 가 다시 뽑히면 같은 진폭 상태에서 새 측정
난수로 독립적으로 다시 측정합니다. 체크포인트는 진폭을 어떻게 만드느냐만 바꾸지 탐색 궤적을
바꾸지 않으므로, 같은 시드에서 Normal 과 체크포인트 모드의 `trial_count` · `L_BBHT` ·
`result_index` 가 같아야 합니다. 안쪽에서 슬롯을 어떻게 고르는지는
[11장](11_체크포인트와_정책_엔진.md)에 있습니다.
