# 12장. Accelerator Core port 계약

> [← 11장 checkpoint와 Policy Engine](11_checkpoint_and_policy_engine.md) · [index](index.md) · [13장 CSR register와 execution mode →](13_csr_registers_and_execution_modes.md)

---

8~11장이 Accelerator Core 안에서 무엇이 어떻게 도는지를 다뤘다면, 이 장은 밖으로 드러나는 계약만
다룹니다. port의 이름 · 폭 · 방향과, 그 port로 주고받는 transaction의 순서입니다.

---

## 12.1 적용 범위

기준은 board에서 검증된 final configuration의 Accelerator Core이고 실물 RTL은
[`hardware_bram/src/`](../../hardware_bram/src/)에 있습니다. 2026-09-13에
Six-Stage Ablation 공통 source revision으로 올려서 Board-Verified Build에 Measurement Microarchitecture parameter(`BUILD_ROWS_PER_CYCLE` 기본 2,
`USE_TWO_LEVEL_SELECT` 기본 1)만 더해졌고, 기본값이면 동작이 같습니다. bitstream과 byte 동일한 revision은 tag
`board-verified-build-2026-09-07` 에 있습니다.

- synthesis profile: 14 qubits / 32 lanes / signed 16-bit data / signed 23-bit amplitude(22 fraction bits)
- 실제 top module: `bbht_grover_main_ip`
- `bbht_rvx_wrapper` 는 계약 이름 `bbht_grover_core` 를 물고, adapter가 이름 · reset
  (`rstn` → `rstnn`) 차이를 흡수합니다. 61 ports는 1:1로 같습니다
- `bbht_bram_top` 은 이 module을 adapter 없이 직접 뭅니다

---

## 12.2 근거와 계약 file

| 항목 | 값 |
|---|---|
| 계약 원본 | 인수인계 docx `LPSoC_BBHT_Grover_팀원_Handoff_SW_통신_v0.9.8반영_2026-09-01.docx`. 내용을 이 장과 7 · 13 · 14장으로 옮긴 뒤 지웠고, commit `495eed0` 까지의 git 기록에 있습니다 |
| docx SHA-256 | `46a5d17805e52caecff4cebbfd1240f9ae7976a54e06b81d2bc391455ba748da` |
| machine-readable 계약 | [`spec/port_contract.tsv`](../../spec/port_contract.tsv) (docx §3.3 wrapper 19개 · §3.4 Accelerator Core 61개를 뽑아 굳힌 것. 추출기 `extract_contract.py` 도 docx와 함께 지웠습니다) |
| 실물 RTL | `hardware_bram/src/` |
| software reference model | `software/reference_model_develop/models/rtl_reference_model/` ([4장](04_software_reference_model_and_test_vectors.md)) |

`check_ports.py` 가 tsv와 RTL을 대조합니다(`make -C hardware_bram/sim ports ports-real`,
DRAM Variant는 `check_ports.py dram`, No-Checkpoint Baseline은 `check_ports.py no_checkpoint_baseline`). 네 가지
모두 wrapper 19 + core 61로 일치합니다. 아래 표는 그 tsv를 사람이 읽으라고 옮긴 것이고, 표와
실물이 어긋나면 실물 RTL을 따르고 표를 고칩니다. 우선순위는 실물 RTL → 이 장 → software
reference model입니다.

---

## 12.3 확정 synthesis parameter

`grover_param.vh` 와 adapter · 최상단이 넘기는 parameter에서 직접 뽑은 값입니다.

| 항목 | 값 |
|---|---:|
| number of qubits `GP_Q` / `INDEX_W` | 14 |
| number of states `GP_N` | 16,384 |
| number of lanes `GP_P` | 32 |
| number of rows `GP_ROWS` | 512 |
| `DATA_W` | signed 16 |
| `FRAC_BITS` | 22 |
| `AMP_W` | signed 23 |
| `DATA_COUNT_W` | 15 |
| `J_W` | 7 |
| sampling range 최대 `GP_M_MAX` | 128 |
| BBHT budget | 576 |
| 기본 `shot_cap` | 100 |
| Result FIFO 깊이 | 256 |
| Checkpoint-Capacity `CHECKPOINT_CAPACITY` | 3 |
| Lookahead-Shots `LOOKAHEAD_SHOTS` | 3 |
| number of PEs `NUMBER_OF_PES` | 4 |
| Measurement Microarchitecture `BUILD_ROWS_PER_CYCLE` · `USE_TWO_LEVEL_SELECT` | 2 · 1 |
| enumeration 기본 `fail_repeat_limit` | 3 |

Checkpoint-Capacity · Lookahead-Shots · number of PEs · Measurement Microarchitecture는 `grover_param.vh` 가 아니라 instance에 넘기는 parameter입니다(adapter 기본값,
`bbht_bram_top` 의 instance). CSR execution mode 이름은 `CHECKPOINT_SINGLE` · `CHECKPOINT_ENUMERATION` 이고, 값이 build마다
달라지므로 이름에 Checkpoint-Capacity · Lookahead-Shots 값을 박지 않습니다. parameter 여덟 개의 뜻은
[8장 8.2절](08_accelerator_core_top_and_bbht_control.md#82-compile-parameter-8개)에 있습니다.

---

## 12.4 입력 port

`clk` 과 `rstn` 은 계약표에 없습니다. 실물이 `posedge clk` 에서 `!rstn` 을 보는 synchronous reset이고,
adapter가 RVX 쪽 이름과 맞춰 줍니다.

### search · mode

| port | 폭 | 형식 | 의미 | 사용 규칙 |
|---|---:|---|---|---|
| `start` | 1 | pulse | search 시작 request | search · load가 모두 idle 일 때만 수락 |
| `auto_shot` | 1 | unsigned | 1: BBHT 자율, 0: manual `j_target` | busy 중 변경 금지 |
| `j_target` | 7 | unsigned | Manual mode의 number of iterations `0..127` | `auto_shot=0` 에서 사용 |
| `burst_enable` | 1 | unsigned | checkpoint 재사용 | busy 중 변경 금지 |
| `enum_enable` | 1 | unsigned | 1: enumeration, 0: single search | busy 중 변경 금지 |
| `fail_repeat_limit` | 4 | unsigned | enumeration에서 연속 실패 허용 횟수 `1..15` | busy 중 변경 금지 |

### checkpoint

| port | 폭 | 의미 |
|---|---:|---|
| `checkpoint_auto_enable` | 1 | 내부 policy가 checkpoint slot을 관리 (production 설정) |
| `checkpoint_manual_enable` | 1 | 바깥에서 계획을 밀어 넣는 시험용 경로 |
| `policy_valid` | 1 | manual 계획 유효 |
| `policy_source_j` | 7 | 어느 checkpoint에서 출발할지 |
| `policy_next_count` | 3 | 이번 전진 뒤 채울 checkpoint slot의 개수 |
| `policy_next_j_flat` | 28 | 그 checkpoint slot들의 number of iterations (7-bit × 4. 폭은 4 checkpoint slots 분량이고 a Checkpoint-Capacity of 3에서는 3개까지 씀) |

wrapper는 `checkpoint_auto_enable = burst_enable && auto_shot` 로 유도하고 manual 쪽 입력은
전부 0으로 묶습니다([7장 7.1절](07_bus_interface.md#71-wrapper의-제어-logic)).

### oracle과 random number

| port | 폭 | 형식 | 의미 |
|---|---:|---|---|
| `predicate_mode` | 2 | unsigned | predicate 선택 |
| `threshold_a` | 16 | signed | predicate threshold A |
| `threshold_b` | 16 | signed | RANGE threshold B |
| `data_count` | 15 | unsigned | 유효 data 개수 `1..16384` |
| `shot_cap` | 16 | unsigned | shot cap (돌릴 수 있는 shot의 최대 개수). 0이면 `config_error` |
| `seed_j` | 32 | unsigned | Iteration-Count LFSR seed. accepted `start` 에서 reload |
| `seed_meas` | 32 | unsigned | Measurement PRNG seed. accepted `start` 에서 reload |

seed가 0이면 내부 fallback seed를 씁니다. 두 stream은 독립이고, 같은 seed 쌍이면 전체 실행이
재현됩니다.

모든 비교는 signed16이고 RANGE는 open interval입니다.

| `predicate_mode` | predicate |
|---|---|
| `2'b00` | `data < threshold_a` |
| `2'b01` | `data > threshold_a` |
| `2'b10` | `data == threshold_a` |
| `2'b11` | `threshold_a < data < threshold_b` |

`threshold_a >= threshold_b` 인 RANGE는 config error가 아닙니다. solution이 없는 predicate로 정상
동작합니다(console의 `SET` 은 이것을 미리 거절합니다. [14장](14_host_interface_and_uart_protocol.md)).

### loader

| port | 폭 | 형식 | 의미 |
|---|---:|---|---|
| `load_start` | 1 | pulse | loader session 시작 |
| `data_wr_en` | 1 | enable | signed16 한 개 쓰기 |
| `data_wr_addr` | 14 | unsigned | 전역 index |
| `data_wr_data` | 16 | signed | 입력 data |
| `load_done` | 1 | pulse | load 종료 및 개수 검사 |

---

## 12.5 출력 port

### 실행과 결과

| port | 폭 | 종류 | 의미 | 유지 규칙 |
|---|---:|---|---|---|
| `load_busy` | 1 | level | loader session 진행 중 | `load_done` 처리까지 |
| `busy` | 1 | level | search 또는 load 진행 중 | 전체 transaction 동안 |
| `done` | 1 | pulse | search 종료 event | 정확히 1 clock |
| `result_valid` | 1 | sticky | 성공 결과가 존재 | 다음 accepted `start` 까지 |
| `result_index` | 14 | unsigned | 성공한 index | `result_valid=1` 에서만 유효 |

`search_busy` 는 따로 나오지 않습니다. 계약이 `busy = search_busy | load_busy` 로 정의하므로
wrapper가 `busy & ~load_busy` 로 유도합니다.

### Result FIFO와 enumeration

| port | 폭 | 종류 | 의미 |
|---|---:|---|---|
| `res_pop` | 1 (IN) | pulse | entry 하나 꺼내기 |
| `res_dout` | 14 | data | FIFO head |
| `res_empty` | 1 | level | 비었음 |
| `res_count` | 9 | counter | 남은 개수 `0..256` |
| `enum_done` | 1 | level | enumeration 종료 |
| `found_count` | 15 | counter | 찾은 개수 |
| `consecutive_fail_count` | 4 | counter | 연속 실패 |
| `max_fifo_occupancy` | 9 | counter | FIFO 최대 점유 |
| `fifo_stall_cycles` | 32 | counter | FIFO full로 멈춘 cycle |

Result FIFO가 256 entries이므로 solution이 그보다 많으면 full stall이 납니다. enumeration에서는 `enum_done` 만 기다리지
말고 `busy` 인 동안에도 계속 뽑아야 하고, `fifo_stall_cycles` 가 0이 아니면 software가 늦게
뽑았다는 뜻입니다.

### status bit (전부 sticky)

| port | 의미 | 해제 시점 |
|---|---|---|
| `config_error` | 설정 또는 load된 dataset 불일치 | 다음 accepted `start` |
| `shot_limit` | `shot_cap` 도달 | 다음 accepted `start` |
| `budget_limit` | BBHT budget(576) 도달 | 다음 accepted `start` |
| `amp_overflow` | amplitude saturation 발생. 진단용이고 결과 무효가 아님 | 다음 accepted `start` |
| `zero_weight_error` | total weight가 0 | 다음 accepted `start` |
| `load_error` | loader 개수 검사 실패 | 다음 accepted `load_start` |

### counter

| port | 폭 | 의미 |
|---|---:|---|
| `shot_count` | 32 | 실행한 shot의 개수 |
| `requested_iterations` | 32 | requested iterations 누적. algorithm 비용 |
| `executed_iterations` | 32 | checkpoint 적용 후 실제 계산량. emulation 비용 |
| `cycle_count` | 32 | accepted start부터 종료까지 (`clk_accel` 100 MHz) |

`requested_iterations` 와 `executed_iterations` 를 섞지 않습니다. checkpoint는 뒤엣것만 줄이고
앞엣것은 그대로 둡니다. paired comparison이 이 성질 위에 서 있습니다.

### policy · plan telemetry

| port | 폭 | 의미 |
|---|---:|---|
| `policy_cycles_total` | 32 | policy가 돈 총 cycle |
| `policy_stall_cycles` | 32 | 그중 search를 실제로 멈춰 세운 cycle |
| `policy_actions_eval` | 32 | 평가한 action의 개수 |
| `policy_memo_hit` · `policy_memo_miss` | 32 | DP memo table hit · miss |
| `policy_max_latency` | 32 | 결정 하나의 최대 latency |
| `plan_queue_level` · `plan_queue_highwater` | 3 | Plan Queue 현재 · 최고 점유 |
| `plan_queue_empty_demand` | 32 | 계획이 없어 기다린 횟수 |
| `plan_queue_hit_count` | 32 | Plan Queue hit |
| `plan_queue_miss_count` | 32 | Plan Queue miss (speculative planning 계획과 실제 request가 어긋난 횟수) |
| `policy_cold_solve_count` · `policy_spec_solve_count` | 32 | 즉시 풀이 · speculative planning 풀이 |

`plan_queue_miss_count == 0` 은 sign-off 조건입니다. 0이 아니면 policy가 예측한 다음 request가
실제와 달랐다는 직접 증거입니다. `policy_stall_cycles` 는 policy Lookahead-Shots를 고를 때의 판단 근거였고,
그 실험은 [실험 07](../reports/07_lookahead_shots_reduction.md)에 있습니다.

---

## 12.6 search transaction

```text
wrapper:          설정값 고정
                -> busy=0, load_busy=0 확인
                -> start 를 1 clock 동안 발생
Accelerator Core: accepted_start
                -> 두 LFSR seed reload
                -> search state/counter clear
                -> busy=1
                -> Grover iteration / measurement / solution check 수행
                -> 종료
                -> busy=0, done=1 clock
                -> sticky 결과/status와 counter 유지
```

필수 규칙입니다.

1. `start` 는 `busy=0 && load_busy=0` 일 때만 발생시킵니다.
2. busy 중의 `start` 는 무시됩니다.
3. 설정 입력은 shadow register가 아니라 live input 이므로 busy 중에 바꾸면 안 됩니다.
4. polling하는 wrapper는 `done` pulse를 `done_sticky` 로 바꿔 잡아야 합니다.
5. `result_index` 는 반드시 `result_valid` 와 함께 읽습니다.

`start` 뒤 다음 중 하나라도 어긋나면 `config_error=1` 로 끝납니다.

- 성공한 loader session으로 `data_valid=1` 이어야 함
- `1 <= data_count <= 16384`
- 현재 `data_count == loaded_count`
- `shot_cap != 0`

Manual mode의 1 shot에서 measurement 후보가 non-solution이면 `done=1`, `result_valid=0` 이지만 오류 · limit bit는 서지
않습니다. 정상적인 실패입니다.

---

## 12.7 Loader transaction

```text
data_count 설정
-> load_start 1 clock
-> load_busy=1 확인
-> address 0..data_count-1 을 한 번씩 순차 쓰기
-> 마지막 쓰기와 같은 clock 또는 그 뒤에 load_done 1 clock
-> load_busy=0
-> load_error=0 확인
-> search start 허용
```

RTL이 보장하는 것입니다.

- `addr >= expected_count` 쓰기는 무시하고 개수에도 넣지 않습니다.
- 마지막 유효 쓰기와 같은 clock의 `load_done` 도 그 쓰기를 포함해 검사합니다.
- 유효 쓰기 개수가 부족하면 `load_error=1`, `data_valid=0` 입니다.
- load 성공 뒤 `data_count` 가 바뀌면 `data_valid` 와 checkpoint가 무효화됩니다.

RTL loader는 서로 다른 address를 모두 썼는지 검사하지 않습니다. 같은 address를 여러 번 써도 쓰기
개수가 올라가므로, wrapper는 각 address를 정확히 한 번씩 생성해야 합니다. 권장 assertion입니다.

```text
data_wr_en -> load_busy
data_wr_en -> data_wr_addr < latched_data_count
accepted writes 의 address = 0,1,2,...,data_count-1
load_done -> accepted_write_count == data_count
```

---

## 12.8 checkpoint 계약

amplitude state를 checkpoint slot 3개(`CHECKPOINT_CAPACITY = 3`)에 두고, policy가 request마다 두 가지를 정합니다. memory는
4 checkpoint slots 분량(row phase 4 banks interleave, RAMB36 44개)이고 a Checkpoint-Capacity of 3은 그중 3개를 씁니다.

1. 어느 checkpoint slot에서 출발할 것인가 (`source_j`)
2. 이번 전진이 끝난 뒤 checkpoint slot을 무엇으로 채울 것인가

```text
이번 request의 executed iterations = number of iterations - source_j        (source_j <= number of iterations)
출발할 checkpoint slot이 없으면 uniform superposition에서 시작하므로 executed iterations = number of iterations
```

경로 중간 state를 checkpoint slot에 남기는 것은 공짜입니다. `source_j` 에서 요청한 number of iterations까지 전진하는 동안 그
state가 실제로 datapath를 지나가기 때문입니다.

아래 표의 request는 이번에 요청한 number of iterations입니다.

| mode / 조건 | 처리 | executed iterations |
|---|---|---:|
| Restart mode | uniform superposition Init 후 request만큼 | request |
| Checkpoint mode, 쓸 checkpoint slot 없음 | Init 후 request만큼 | request |
| Checkpoint mode, request > `source_j` | 그 checkpoint slot에서 이어 계산 | request − `source_j` |
| Checkpoint mode, request == `source_j` | 그대로 다시 measurement | 0 |

무효화 조건은 accepted `load_start`, `predicate_mode` 변경, `threshold_a/b` 변경, `data_count`
변경입니다. enumeration에서 새 solution을 찾아 `found_mask` 가 바뀔 때도 무효화됩니다. `seed`,
`shot_cap`, `auto_shot`, `j_target`, `burst_enable` 만 바꾸는 것은 amplitude의 의미를 바꾸지 않으므로
무효화하지 않습니다.

실패한 number of iterations를 다음 sampling에서 빼지 않습니다. 같은 값이 다시 뽑히면 같은 amplitude state에서 새
random number로 독립적으로 다시 measurement합니다. checkpoint는 amplitude를 어떻게 만드느냐만 바꾸지 BBHT trajectory를
바꾸지 않으므로, 같은 seed에서 Restart mode와 Checkpoint mode의 `shot_count` · `requested_iterations` ·
`result_index` 가 같아야 합니다. 안쪽에서 checkpoint slot을 어떻게 고르는지는
[11장](11_checkpoint_and_policy_engine.md)에 있습니다.
