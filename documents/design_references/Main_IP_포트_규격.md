# LPSoC BBHT/Grover Main IP 포트 규격

## 1. 적용 범위

기준은 **보드에서 검증된 K3/H3-E4-M2 Main IP** 이고, 실물 RTL 은
`hardware_bram/src/` 에 있습니다. 2026-09-13 에 6단계 ablation 공통소스 판으로
올려서 보드 정본에 `MEAS_M1_ENABLE` · `MEAS_M2_ENABLE` 스위치(기본 1)만 더해졌고,
둘 다 1 이면 동작이 같습니다. 비트스트림과 바이트 동일한 판은 태그
`board-k3h3-e4-m2` 에 있습니다.

- 합성 프로파일: Q14 / P32 / signed DATA16 / signed 23비트 진폭(소수부 22)
- 실제 top module: `bbht_grover_main_ip`
- `src/bbht_rvx_wrapper.v` 는 계약 이름 `bbht_grover_core` 를 물고,
  `src/bbht_grover_core_adapter.v` 가 이름·리셋(`rstn` → `rstnn`) 차이를
  흡수합니다. 포트 61개는 1:1 로 같습니다
- 최상단 `src/bbht_bram_top.v` 는 이 모듈을 **어댑터 없이 직접** 뭅니다
  (보드에 구운 정본 wrapper 도 그렇게 물었습니다)
- 단일 검색과 열거, 결과 FIFO(256칸), checkpoint policy 가 **전부 Main IP 안**에
  있습니다. 바깥에 둘 것은 APB CSR·AHB 적재·UART 뿐입니다

### 이 문서와 계약 파일의 관계

포트 계약의 정본은 문서가 아니라 **`software/contract/port_contract.tsv`** 입니다.
인수인계 docx §3.3(wrapper 19개) · §3.4(Main IP 61개)에서 `extract_contract.py` 가
뽑아 커밋한 것이고, `check_ports.py` 가 RTL 과 매번 대조합니다.

```bash
make -C hardware_bram/sim ports        # 스텁을 물린 상태
make -C hardware_bram/sim ports-real   # 실물 코어를 물린 상태
```

아래 표는 그 tsv 를 사람이 읽으라고 옮긴 것입니다. **둘이 어긋나면 tsv 가
맞습니다.**

## 2. 근거

| 항목 | 값 |
|---|---|
| 계약 원본 | `software/contract/LPSoC_BBHT_Grover_팀원_Handoff_SW_통신_v0.9.8반영_2026-09-01.docx` |
| docx SHA-256 | `46a5d17805e52caecff4cebbfd1240f9ae7976a54e06b81d2bc391455ba748da` |
| 실물 RTL | `hardware_bram/src/` (비트스트림과 sha256 동일한 판은 태그 `board-k3h3-e4-m2`) |
| 골든 모델 | `software/golden/rtl_v098_auto.py` 외 `rtl_v098_*` |
| 보드 실측 | `hardware_bram/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/` |

소스가 충돌하면 우선순위는 **실물 RTL → 포트 계약 tsv → 골든 모델 → 이 문서** 입니다.

v0.7g(2026-08-20 전달본) 기준으로 쓰인 옛 판은 폐기했습니다. 그 세대의 8-case
골든벡터는 `software/bin/v07g_handoff_8cases/` 에 회귀용으로 남아 있습니다.

## 3. 확정 합성 파라미터

`hardware_bram/src/grover_param.vh` 와 어댑터·최상단이 넘기는
파라미터에서 직접 뽑은 값입니다.

| 항목 | 값 |
|---|---:|
| `Q` / `INDEX_W` | 14 |
| 상태 수 `N` | 16,384 |
| 병렬도 `P` | 32 |
| row 수 | 512 |
| `DATA_W` | signed 16 |
| `FRAC_BITS` | 22 |
| `AMP_W` | signed 23 |
| `DATA_COUNT_W` | 15 |
| `J_W` | 7 |
| BBHT `m_max` | 128 |
| BBHT budget | 576 |
| 기본 `shot_cap` | 100 |
| Result FIFO 깊이 | 256 |
| checkpoint 슬롯 `CKPT_K` | 3 |
| policy horizon `POLICY_H_FUTURE` | 3 |
| 반복 내 연산기 `INTRA_ENGINES` | 4 |
| 열거 기본 `fail_repeat_limit` | 3 |

`CKPT_K = 3` · `POLICY_H_FUTURE = 3` · `INTRA_ENGINES = 4` · `MEAS_M1_ENABLE = 1` ·
`MEAS_M2_ENABLE = 1` 이라 현재 구성은 **K3/H3-E4-M2** 입니다. 이 값들은
`grover_param.vh` 가 아니라 인스턴스에 넘기는 파라미터입니다
(`src/bbht_grover_core_adapter.v` 의 기본값, `src/bbht_bram_top.v` 의 인스턴스). CSR 실행 모드 이름은 `CKPT_SINGLE` ·
`CKPT_ENUM` 입니다 — 값이 빌드마다 달라지므로 이름에 K·H 를 박지 않습니다.

## 4. 입력 포트

### 4.1 검색·모드

| 포트 | 폭 | 형식 | 의미 | 사용 규칙 |
|---|---:|---|---|---|
| `start` | 1 | pulse | 검색 시작 요청 | search·load 가 모두 idle 일 때만 수락 |
| `auto_shot` | 1 | unsigned | 1: BBHT 자율, 0: manual `j_target` | busy 중 변경 금지 |
| `j_target` | 7 | unsigned | manual Grover 반복 수 `0..127` | `auto_shot=0` 에서 사용 |
| `burst_enable` | 1 | unsigned | checkpoint 재사용 | busy 중 변경 금지 |
| `enum_enable` | 1 | unsigned | 1: 열거, 0: 단일 검색 | busy 중 변경 금지 |
| `fail_repeat_limit` | 4 | unsigned | 열거에서 연속 실패 허용 횟수 `1..15` | busy 중 변경 금지 |

`clk` 과 `rstn` 은 계약표에 없습니다. 실물이 `posedge clk` 에서 `!rstn` 을 보는
동기 리셋이고, 어댑터가 RVX 쪽 이름과 맞춰 줍니다.

### 4.2 Checkpoint

| 포트 | 폭 | 의미 |
|---|---:|---|
| `checkpoint_auto_enable` | 1 | 내부 policy 가 슬롯을 관리 (production 설정) |
| `checkpoint_manual_enable` | 1 | 바깥에서 계획을 밀어 넣는 시험용 경로 |
| `policy_valid` | 1 | manual 계획 유효 |
| `policy_source_j` | 7 | 어느 checkpoint 에서 출발할지 |
| `policy_next_count` | 3 | 이번 전진 뒤 채울 슬롯 수 |
| `policy_next_j_flat` | 28 | 그 슬롯들의 `j` 4개 (7비트 × 4) |

wrapper 는 `checkpoint_auto_enable = burst_enable && auto_shot` 로 유도하고
**manual 쪽 입력은 전부 0 으로 묶습니다.** 두 경로를 동시에 열면 계획 출처가
둘이 되어 policy 통계가 의미를 잃습니다.

### 4.3 오라클과 난수

| 포트 | 폭 | 형식 | 의미 |
|---|---:|---|---|
| `predicate_mode` | 2 | unsigned | 술어 선택 |
| `threshold_a` | 16 | signed | 술어 기준 A |
| `threshold_b` | 16 | signed | RANGE 기준 B |
| `data_count` | 15 | unsigned | 유효 데이터 수 `1..16384` |
| `shot_cap` | 16 | unsigned | 최대 BBHT attempt 수. 0이면 `config_error` |
| `seed_j` | 32 | unsigned | requested-`j` LFSR seed. accepted `start` 에서 reload |
| `seed_meas` | 32 | unsigned | Born LFSR seed. accepted `start` 에서 reload |

seed 가 0이면 내부 fallback 을 씁니다. 두 스트림은 독립이고, 같은 seed 쌍이면
전체 실행이 재현됩니다.

### 4.4 Loader

| 포트 | 폭 | 형식 | 의미 |
|---|---:|---|---|
| `load_start` | 1 | pulse | loader session 시작 |
| `data_wr_en` | 1 | enable | signed16 한 개 write |
| `data_wr_addr` | 14 | unsigned | global index |
| `data_wr_data` | 16 | signed | 입력 데이터 |
| `load_done` | 1 | pulse | 적재 종료 및 개수 검사 |

### 4.5 Predicate 인코딩

모든 비교는 signed16 이며 RANGE 는 열린 구간입니다.

| `predicate_mode` | 조건 |
|---|---|
| `2'b00` | `data < threshold_a` |
| `2'b01` | `data > threshold_a` |
| `2'b10` | `data == threshold_a` |
| `2'b11` | `threshold_a < data < threshold_b` |

`threshold_a >= threshold_b` 인 RANGE 는 config error 가 아닙니다. 타겟이 없는
조건으로 정상 동작합니다.

## 5. 출력 포트

### 5.1 실행과 결과

| 포트 | 폭 | 종류 | 의미 | 유지 규칙 |
|---|---:|---|---|---|
| `load_busy` | 1 | level | loader session 진행 중 | `load_done` 처리까지 |
| `busy` | 1 | level | search 또는 load 진행 중 | 전체 transaction 동안 |
| `done` | 1 | pulse | 검색 terminal event | 정확히 1클록 |
| `result_valid` | 1 | sticky | 성공 결과가 존재 | 다음 accepted `start` 까지 |
| `result_index` | 14 | unsigned | 성공한 index | `result_valid=1` 에서만 유효 |

`search_busy` 는 따로 나오지 않습니다. 계약이 `busy = search_busy | load_busy` 로
정의하므로 wrapper 가 `busy & ~load_busy` 로 유도합니다.

### 5.2 Result FIFO와 열거

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

**FIFO 가 256칸이므로 해가 그보다 많으면 full stall 이 납니다.** 열거에서는
`enum_done` 만 기다리지 말고 `busy` 인 동안에도 계속 뽑아야 합니다.
`fifo_stall_cycles` 가 0이 아니면 소프트웨어가 늦게 뽑았다는 뜻입니다.

### 5.3 상태 비트 (전부 sticky)

| 포트 | 의미 | 해제 시점 |
|---|---|---|
| `config_error` | config 또는 적재된 dataset 불일치 | 다음 accepted `start` |
| `shot_limit` | `shot_cap` 도달 | 다음 accepted `start` |
| `budget_limit` | BBHT budget(576) 도달 | 다음 accepted `start` |
| `amp_overflow` | 진폭 saturation 발생. **진단용이고 결과 무효가 아닙니다** | 다음 accepted `start` |
| `zero_weight_error` | Born total weight 가 0 | 다음 accepted `start` |
| `load_error` | loader count 검사 실패 | 다음 accepted `load_start` |

### 5.4 카운터

| 포트 | 폭 | 의미 |
|---|---:|---|
| `trial_count` | 32 | 실행한 attempt 수 |
| `L_BBHT` | 32 | 요청된 `j` 의 누적합. **알고리즘 비용** |
| `actual_grover_iterations` | 32 | checkpoint 적용 후 실제 계산량. **에뮬레이션 비용** |
| `cycle_count` | 32 | accepted start 부터 terminal 까지 (clk_accel 100 MHz) |

`L_BBHT` 와 `actual_grover_iterations` 를 섞지 마십시오. checkpoint 는 뒤엣것만
줄이고 앞엣것은 그대로 둡니다. 짝맞춤 검증이 이 성질 위에 서 있습니다.

### 5.5 Policy·Plan 텔레메트리

| 포트 | 폭 | 의미 |
|---|---:|---|
| `policy_cycles_total` | 32 | policy 가 돈 총 사이클 |
| `policy_stall_cycles` | 32 | 그중 탐색을 실제로 멈춰 세운 사이클 |
| `policy_actions_eval` | 32 | 평가한 행동 수 |
| `policy_memo_hit` · `policy_memo_miss` | 32 | DP memo 적중·실패 |
| `policy_max_latency` | 32 | 결정 하나의 최대 지연 |
| `plan_fifo_level` · `plan_fifo_highwater` | 3 | 투기 계획 큐 |
| `plan_fifo_empty_demand` | 32 | 계획이 없어 기다린 횟수 |
| `plan_fifo_hit_count` | 32 | 투기 계획 적중 |
| `plan_fifo_mismatch_count` | 32 | **투기 계획과 실제 요청이 어긋난 횟수** |
| `policy_cold_solve_count` · `policy_spec_solve_count` | 32 | 즉시 풀이 · 투기 풀이 |

`plan_fifo_mismatch_count == 0` 은 sign-off 조건입니다. 0이 아니면 policy 가 예측한
다음 요청이 실제와 달랐다는 직접 증거입니다.

`policy_stall_cycles` 는 policy horizon 을 고를 때의 판단 근거입니다 — H8 은
반복을 2.7% 덜 쓰는 대신 stall 을 23배 물어 총 사이클에서 손해를 봤고, 그래서
freeze 가 H4 입니다.

## 6. Search transaction

```text
Wrapper: 설정값 고정
       -> busy=0, load_busy=0 확인
       -> start를 1클록 발생
Main IP: accepted_start
       -> 두 LFSR seed reload
       -> search status/counter clear
       -> busy=1
       -> Grover/측정/검증 수행
       -> terminal
       -> busy=0, done=1클록
       -> sticky result/status와 counter 유지
```

필수 규칙:

1. `start` 는 `busy=0 && load_busy=0` 일 때만 발생시킨다.
2. busy 중의 `start` 는 무시된다.
3. config 입력은 shadow register 가 아니라 live input 이므로 busy 중 변경하면 안 된다.
4. polling wrapper 는 `done` pulse 를 `done_sticky` 로 변환해야 한다.
5. `result_index` 는 반드시 `result_valid` 와 함께 읽는다.

### 검색 config 검사

`start` 후 다음 조건 중 하나라도 실패하면 `config_error=1` 로 종료합니다.

- 성공한 loader session 으로 `data_valid=1` 이어야 함
- `1 <= data_count <= 16384`
- 현재 `data_count == loaded_count`
- `shot_cap != 0`

수동 1-shot 에서 측정 후보가 비타겟이면 `done=1`, `result_valid=0` 이지만 오류·limit
비트는 서지 않습니다. 정상적인 실패입니다.

## 7. Loader transaction

```text
data_count 설정
-> load_start 1클록
-> load_busy=1 확인
-> address 0..data_count-1을 한 번씩 순차 write
-> 마지막 write와 같은 클록 또는 이후에 load_done 1클록
-> load_busy=0
-> load_error=0 확인
-> search start 허용
```

### RTL이 보장하는 것

- `addr >= expected_count` write 는 무시하고 count 에도 넣지 않는다.
- 마지막 유효 write 와 같은 클록의 `load_done` 도 그 write 를 포함해 검사한다.
- 유효 write count 가 부족하면 `load_error=1`, `data_valid=0` 이다.
- load 성공 후 `data_count` 가 바뀌면 `data_valid` 와 checkpoint 가 무효화된다.

### Wrapper/SW가 보장해야 하는 것

RTL loader 는 **서로 다른 주소를 모두 썼는지 검사하지 않습니다.** 같은 주소를
여러 번 써도 write count 가 올라갑니다. 따라서 wrapper 는 각 주소를 정확히 한
번씩 생성해야 합니다.

권장 assertion:

```text
data_wr_en -> load_busy
data_wr_en -> data_wr_addr < latched_data_count
accepted writes의 address = 0,1,2,...,data_count-1
load_done -> accepted_write_count == data_count
```

## 8. Checkpoint 계약

진폭 상태를 **슬롯 4개**(`CKPT_K = 4`)에 두고, policy 가 요청 `j` 마다 두 가지를
정합니다.

1. 어느 슬롯에서 출발할 것인가 (`source_j`)
2. 이번 전진이 끝난 뒤 슬롯을 무엇으로 채울 것인가

```text
이번 요청의 물리 비용 = j - source_j        (source_j <= j)
출발할 슬롯이 없으면 균등상태에서 시작하므로 비용 = j
```

경로 중간 상태를 슬롯에 떨구는 것은 **공짜**입니다. `source_j` 에서 `j` 까지
전진하는 동안 그 상태가 실제로 데이터패스를 지나가기 때문입니다.

| 모드/조건 | 처리 | 실제 반복 수 |
|---|---|---:|
| Normal | 균등상태 INIT 후 `j` 회 | `j` |
| checkpoint, 쓸 슬롯 없음 | INIT 후 `j` 회 | `j` |
| checkpoint, `j > source_j` | 그 슬롯에서 이어 계산 | `j - source_j` |
| checkpoint, `j == source_j` | 그대로 다시 측정 | 0 |

무효화 조건은 accepted `load_start`, `predicate_mode` 변경, `threshold_a/b` 변경,
`data_count` 변경입니다. `seed`, `shot_cap`, `auto_shot`, `j_target`,
`burst_enable` 만 바꾸는 것은 진폭의 의미를 바꾸지 않으므로 무효화하지 않습니다.

**실패한 `j` 를 다음 추첨에서 제외하지 않습니다.** 같은 `j` 가 다시 뽑히면 같은
진폭 상태에서 새 측정 난수로 독립적으로 다시 측정합니다. checkpoint 는 ψ 를
어떻게 만드느냐만 바꾸지 탐색 궤적을 바꾸지 않습니다 — 그래서 같은 시드에서
Normal 과 checkpoint 모드의 `trial_count` · `L_BBHT` · `result_index` 가 같아야
합니다.

## 9. 폐기된 것

아래는 옛 세대의 값입니다. 문서나 `trash_bin/` 에서 마주치면 무시하십시오.

| 항목 | 폐기된 값 | 현행 |
|---|---|---|
| 수치 프로파일 | Q15 / Q2.16 / 18비트 진폭 | Q14 / 소수부 22 / 23비트 |
| 큐비트 runtime 설정 | `n_qubits` 가변 | Q14 고정 + `data_count` 만 runtime |
| 데이터 적재 | AHB `INCR16` 버스트 | AHB SINGLE, single outstanding |
| 열거 | Main IP 밖 상위 계층에서 구현 | Main IP 안. 결과 FIFO 256칸 포함 |
| checkpoint | 1-entry `cache_j` / `cache_valid` | 슬롯 4개 + policy DP |

비트폭과 P32 매핑은 [데이터_고정소수점_메모리_규격.md](데이터_고정소수점_메모리_규격.md),
CSR 맵은 [CSR_레지스터_규격.md](CSR_레지스터_규격.md) 를 따릅니다.
