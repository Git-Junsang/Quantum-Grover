# 13장. CSR register와 execution mode

> [← 12장 Accelerator Core port 계약](12_accelerator_core_port_contract.md) · [index](index.md) · [14장 host interface와 UART protocol →](14_host_interface_and_uart_protocol.md)

> 이 장은 `spec/gen_csr.py` 가 CSR source of truth [`bbht_grover_csr.json`](../../spec/bbht_grover_csr.json) 에서 생성합니다.
> 손으로 고치면 다음 생성에서 덮어써집니다. 값은 JSON 을, 문장은 `gen_csr.py` 의
> `gen_doc()` 를 고친 뒤 `python3 spec/gen_csr.py` 를 돌리십시오.
>
> 출처: PJK `팀원_Handoff_SW_통신_v0.9.8` §1.4 / §1.5. source of truth version 0.9.8 (2026-09-01)

---

host firmware가 accelerator를 부리는 창구는 APB register 38개입니다. CSR 계약은 v0.9.8 이후
바뀌지 않았고, board에 구운 두 Bus Interface revision의 offset 표도 전부 일치합니다. register가
Accelerator Core port와 어떻게 이어지는지는 [12장](12_accelerator_core_port_contract.md), host 명령이 어느
register를 두드리는지는 [14장](14_host_interface_and_uart_protocol.md)에 있습니다.

---

## 13.1 CSR 접근 규격

| 항목 | 값 |
|---|---|
| base address macro | `I_GROVER_CSR_SLAVE_BASEADDR` |
| 현재 생성값 | `0xE2020000` (이 환경 `make syn` 생성물에서 확인) |
| memory map 크기 | `0x1000` |
| register 간격 | 4 bytes |
| data word width | 32 bits |
| bus | APB3 slave. `pready` constant 1, wait state 없음 |

정렬되지 않은 접근과 미할당 address는 `pslverr` 로 떨어집니다.

C code에서는 숫자를 박지 말고 생성된 macro를 씁니다. platform XML 이 바뀌면 address가
옮겨가고, 박아 둔 숫자는 조용히 엉뚱한 곳을 두드립니다.

---

## 13.2 search 공간과 clock

| 항목 | 값 |
|---|---|
| number of qubits | 14 qubits |
| number of states | 16,384 states |
| data word | 16-bit signed |
| 결과 index | 14 bits |
| Result FIFO | 14 bits × 256 entries |
| accelerator clock | 100 MHz. `CYCLE_COUNT` 의 기준이라 `us = cycles / 100` |
| SoC clock | 50 MHz. UART 보율의 기준 |
| system SRAM | `0xE0000000` ~ `0xE001FFFF` |

---

## 13.3 register 접근 유형

| 표기 | 뜻 |
|---|---|
| `RW` | 설정. 저장되고 값이 IP 로 상시 나갑니다 |
| `W1P` | 명령. 저장 공간이 없고 쓰면 1 cycle pulse만 나갑니다. 읽으면 0. 쓰는 data는 무시되고 쓰는 행위 자체가 명령입니다 |
| `RO` | status. IP가 내보내는 wire를 읽기 응답에 실어 보냅니다 |
| `RPOP` | 읽기 완료가 곧 pop. 부작용이 있는 유일한 읽기입니다 |

`RPOP` 은 `FIFO_DATA` 하나뿐입니다. index 0 이 정상 결과일 수 있으므로 값 0 을 비었다는
뜻으로 읽으면 안 되고, `FIFO_COUNT` 나 `STATUS.fifo_empty` 로 확인합니다.

---

## 13.4 register map

| offset | 이름 | 접근 | 폭 | 뜻 |
|--:|---|:-:|--:|---|
| `0x000` | `COMMAND` | W1P | 1 | search 시작. 쓰는 행위 자체가 명령이고 저장 공간이 없습니다 |
| `0x004` | `CONTROL` | RW | 4 | 동작 mode |
| `0x008` | `J_TARGET` | RW | 7 | Manual mode의 requested iterations (0~127). auto_shot=1이면 무시됩니다 |
| `0x00C` | `THRESHOLD_A` | RW | 16 | threshold A. RANGE 에서는 lower bound |
| `0x010` | `THRESHOLD_B` | RW | 16 | threshold B. RANGE 상한 (A < data < B, 열린구간) |
| `0x014` | `DATA_COUNT` | RW | 15 | 유효 data 개수 1~16384. 그 이후 index는 non-solution |
| `0x018` | `SHOT_CAP` | RW | 16 | BBHT shot cap. 기본 100 |
| `0x01C` | `SEED_J` | RW | 32 | Iteration-Count LFSR seed |
| `0x020` | `SEED_MEAS` | RW | 32 | Measurement PRNG seed. SEED_J 와 독립 |
| `0x024` | `STATUS` | RO | 12 | 실행 state. bit 정의는 status_bits 참조 |
| `0x028` | `RESULT_INDEX` | RO | 14 | Single mode 결과 index. STATUS.result_valid 가 1 일 때만 의미가 있습니다 |
| `0x02C` | `SHOT_COUNT` | RO | 32 | run 전체의 shot 수 |
| `0x030` | `REQUESTED_ITERATIONS` | RO | 32 | requested iterations의 sum - algorithm 지표. checkpoint로 줄지 않습니다 |
| `0x034` | `EXECUTED_ITERATIONS` | RO | 32 | executed iterations - checkpoint가 줄이는 대상 |
| `0x038` | `CYCLE_COUNT` | RO | 32 | run 소비 cycle. clk_accel(100 MHz) 기준이므로 µs = cycles/100 |
| `0x03C` | `ENUM_CFG` | RW | 8 | enumeration mode 설정 |
| `0x040` | `FIFO_DATA` | RPOP | 14 | Result FIFO head. 읽기 완료 자체가 pop 입니다. 별도 POP register는 없습니다 |
| `0x044` | `FIFO_COUNT` | RO | 9 | 현재 FIFO occupancy |
| `0x048` | `FOUND_COUNT` | RO | 15 | unique solution 누적 |
| `0x04C` | `CONSEC_FAIL` | RO | 4 | complete BBHT failure 연속 횟수 |
| `0x050` | `MAX_FIFO_OCC` | RO | 9 | run 중 최대 occupancy |
| `0x054` | `FIFO_STALL` | RO | 32 | FIFO full 로 멈춘 cycle |
| `0x058` | `DATA_ADDR` | RW | 32 | System SRAM 원본 address. 4-byte 정렬 필수 |
| `0x05C` | `DMA_COMMAND` | W1P | 1 | DMA load 시작 |
| `0x060` | `DMA_STATUS` | RO | 8 | DMA state. bit 정의는 dma_status_bits 참조 |
| `0x064` | `POLICY_CYCLES_TOTAL` | RO | 32 | policy 총 cycle |
| `0x068` | `POLICY_STALL_CYCLES` | RO | 32 | policy stall |
| `0x06C` | `POLICY_ACTIONS_EVAL` | RO | 32 | 평가한 action 수 |
| `0x070` | `POLICY_MEMO_HIT` | RO | 32 | memo hit |
| `0x074` | `POLICY_MEMO_MISS` | RO | 32 | memo miss |
| `0x078` | `POLICY_MAX_LATENCY` | RO | 32 | policy 최대 latency |
| `0x07C` | `PLAN_QUEUE_LEVEL` | RO | 3 | 현재 Plan Queue 레벨 |
| `0x080` | `PLAN_QUEUE_HIGHWATER` | RO | 3 | Plan Queue 최고 수위 |
| `0x084` | `PLAN_QUEUE_EMPTY_DEMAND` | RO | 32 | demand 시 empty 횟수 |
| `0x088` | `PLAN_QUEUE_HIT_COUNT` | RO | 32 | speculative plan hit |
| `0x08C` | `PLAN_QUEUE_MISS_COUNT` | RO | 32 | 정상 기대값 0 |
| `0x090` | `POLICY_COLD_SOLVE_COUNT` | RO | 32 | cold solve 횟수 |
| `0x094` | `POLICY_SPEC_SOLVE_COUNT` | RO | 32 | speculative solve |

`REQUESTED_ITERATIONS` 는 checkpoint 사용 여부와 관계없이 유지되는 algorithm 지표이고, `EXECUTED_ITERATIONS` 는
checkpoint가 줄이는 실제 연산량입니다. 둘을 구분해야 합니다([15장](15_operation_sequence_and_cycle_breakdown.md)).
`0x064` 부터의 policy telemetry로 [11장](11_checkpoint_and_policy_engine.md)의 Policy Engine을 밖에서
관찰할 수 있습니다. `POLICY_MAX_LATENCY` 가 3,352 로 튀면 reset 뒤 memo table 청소가 일어난
실행입니다.

### bit field가 있는 register

`COMMAND` (`0x000`)

| bit | 이름 | 뜻 |
|:-:|---|---|
| `0` | `search_start` | external search start |

`CONTROL` (`0x004`)

| bit | 이름 | 뜻 |
|:-:|---|---|
| `0` | `auto_shot` | 1: BBHT가 requested iterations를 자동 생성 |
| `1` | `burst_enable` | 1: checkpoint 재사용 사용 (Checkpoint-Capacity · Lookahead-Shots는 RTL build constant. 현 freeze는 a Checkpoint-Capacity of 3 and 3-shot Lookahead) |
| `3:2` | `predicate_mode` | 00 LT / 01 GT / 10 EQ / 11 RANGE |

`ENUM_CFG` (`0x03C`)

| bit | 이름 | 뜻 |
|:-:|---|---|
| `0` | `enum_enable` | 0: Single, 1: Enumeration |
| `7:4` | `fail_repeat_limit` | complete-BBHT failure 연속 횟수 한계. 유효 1~15, 0 은 config error |

`DMA_COMMAND` (`0x05C`)

| bit | 이름 | 뜻 |
|:-:|---|---|
| `0` | `dma_start` | DMA session start |

---

## 13.5 `STATUS` (`0x024`)

| bit | 이름 | 뜻 |
|--:|---|---|
| 0 | `busy` | search/main busy |
| 1 | `load_busy` | Main IP loader busy |
| 2 | `done_sticky` | search 완료 sticky. COMMAND 쓰기로 클리어 |
| 3 | `result_valid` | Single result 유효 |
| 4 | `config_error` | 설정 오류 sticky |
| 5 | `shot_limit` | shot cap 도달 sticky |
| 6 | `budget_limit` | BBHT budget 도달 sticky |
| 7 | `amp_overflow` | amplitude saturation sticky. 진단용이며 종료 사유가 아님 |
| 8 | `zero_weight_error` | Born-rule sampling total weight 오류 sticky |
| 9 | `load_error` | DMA Engine 검사 오류 sticky |
| 10 | `enum_done` | Enumeration 종료 sticky |
| 11 | `fifo_empty` | Result FIFO 비어 있음 |

자주 보게 되는 값입니다.

| 값 | 뜻 |
|---|---|
| `0x080c` | 완료 + 결과 유효 + FIFO 빔. 정상 Single |
| `0x0404` | 완료 + enumeration 종료, FIFO 에 결과 남음. 아직 뽑아야 함 |
| `0x0c04` | 완료 + enumeration 종료 + FIFO 빔. 다 뽑았음 |
| `0x0844` | 완료 + 예산 도달 + FIFO 빔. 못 찾고 끝남 |

`done_sticky` 를 지우는 것은 `COMMAND` 쓰기뿐입니다. `STATUS` 를 읽거나 설정을 바꿔도
지워지지 않습니다. `search_busy` 는 따로 나오지 않고 `busy & ~load_busy` 로 유도합니다.

---

## 13.6 `DMA_STATUS` (`0x060`)

| bit | 이름 | 뜻 |
|--:|---|---|
| 0 | `dma_busy` | DMA 진행 중 |
| 1 | `dma_error` | 아래 오류들의 OR |
| 2 | `align_error` | DATA_ADDR 4-byte 정렬 위반 |
| 3 | `count_error` | DATA_COUNT 범위 위반 |
| 4 | `resp_error` | AHB 응답 오류 |
| 5 | `busy_error` | Accelerator Core busy 라서 DMA 거절 |
| 6 | `range_error` | System SRAM 범위 밖 |
| 7 | `dma_done_sticky` | DMA 완료 sticky |

`0x00000080` 이면 완료만 선 정상 state입니다. 검사 시점과 이유는
[7장 7.3절](07_bus_interface.md#73-dma-engine의-사전-검사)에 있습니다.

---

## 13.7 predicate와 execution mode

| 값 | 이름 | 조건 |
|--:|---|---|
| 0 | `LT` | data < A |
| 1 | `GT` | data > A |
| 2 | `EQ` | data == A |
| 3 | `RANGE` | A < data < B (열린구간) |

`RANGE` 는 열린구간입니다. 경계값 자체는 solution이 아닙니다.

execution mode는 별도 register가 아니라 세 bit의 조합입니다.

| 이름 | `auto_shot` | `burst_enable` | `enum_enable` | 설명 |
|---|:-:|:-:|:-:|---|
| `MANUAL_SINGLE` | 0 | 0 | 0 | J_TARGET을 firmware가 지정 |
| `RESTART_SINGLE` | 1 | 0 | 0 | Restart mode. 표준 BBHT |
| `CHECKPOINT_SINGLE` | 1 | 1 | 0 | Checkpoint mode (Checkpoint-Capacity · Lookahead-Shots · number of PEs · Measurement Microarchitecture는 RTL build에 컴파일됨. 현 Board-Verified Build는 final configuration) |
| `RESTART_ENUMERATION` | 1 | 0 | 1 | Restart mode enumeration |
| `CHECKPOINT_ENUMERATION` | 1 | 1 | 1 | Checkpoint mode enumeration (Checkpoint-Capacity · Lookahead-Shots · number of PEs · Measurement Microarchitecture는 RTL build에 컴파일됨. 현 Board-Verified Build는 final configuration) |

`checkpoint_auto_enable = burst_enable && auto_shot` 이므로 Manual mode(`auto_shot=0`)에서는
checkpoint가 걸리지 않습니다([7장 7.1절](07_bus_interface.md#71-wrapper의-제어-logic)).
No-Checkpoint Baseline과 DRAM Variant는 `burst_enable` 을 무시하고 Restart mode로 돕니다.

### mode 이름에 Checkpoint-Capacity · Lookahead-Shots 값을 넣지 않는 이유

execution mode 이름은 2026-09-10 에 `K4H8_*` 에서 `CKPT_*` 로, 2026-10-28 에 `CHECKPOINT_*` 로 바꿨습니다. Checkpoint-Capacity · Lookahead-Shots · number of PEs ·
Measurement Microarchitecture는 전부
RTL build에 컴파일되는 값이라 이름에 값을 넣으면 build가 바뀔 때마다 이름이 틀려집니다. 실제로
a Checkpoint-Capacity of 4 and 8-shot Lookahead에서 a Checkpoint-Capacity of 4 and 4-shot Lookahead를 거쳐 지금은 a Checkpoint-Capacity of 3 and 3-shot Lookahead입니다.

`bbht_paper_bench` 의 `CONTROL_K4H8_EQ` · `MODE_K4H8` 은 그대로 두었습니다. 그 file은 board
ELF 를 낸 source와 sha256 이 같아야 합니다. software reference model은 CSR mode 이름 대신 policy
이름으로 부릅니다([4장 4.2절](04_software_reference_model_and_test_vectors.md#42-세-layer의-reference-model)).

---

## 13.8 생성 pipeline

source of truth JSON 하나에서 넷을 생성합니다. 생성물은 손으로 고치지 않습니다.

| 생성물 | 쓰는 곳 |
|---|---|
| `spec/generated/bbht_grover_csr.vh` | RTL (`bbht_grover_mmio.v` 등 네 곳) |
| `spec/generated/bbht_grover_regs.h` | firmware C |
| `spec/generated/bbht_grover_csr.py` | host CLI |
| `documents/design_references/13_csr_registers_and_execution_modes.md` | 이 장 |

같은 숫자를 들고 있으면서 생성 대상이 아닌 곳이 둘 더 있습니다.

| 곳 | 생성 대상이 아닌 이유 |
|---|---|
| `software/reference_model_develop/models/common/final_hardware_contract.py` | CSR 과 다른 축인 policy 이름을 같이 담습니다 |
| `hardware_bram/firmware/bbht_paper_bench/src/main.c` | board ELF source라 한 글자도 못 고칩니다 |

`gen_csr.py --check` 가 그 둘을 읽기만 하고 source of truth와 대조합니다(main.c 는 이름을 줄여 쓴
것이 있어 offset 기준으로 봅니다). 셋째 검사는 방향이 반대로, 생성 header를 우회해 RTL 안에
CSR 값을 다시 박는 것을 막습니다.

```bash
python3 spec/gen_csr.py          # 갱신
python3 spec/gen_csr.py --check  # 갱신 없이 확인만 (CI 용)
```

checkpoint가 있는 revision의 `sim/Makefile`은 모든 target에서 `--check`를, No-Checkpoint Baseline은 생성을 먼저
돌리므로 생성 header를 손으로 고쳐 놓고 regression만 통과시키는 일이 생기지 않습니다(DRAM Variant는 생성
header를 include 만 합니다). CSR 정의가 옛 firmware header(8-byte 간격
제안안) · 옛 설계안 mmio · proof app 마다의 복사본 세 곳에 따로 있다가 어긋난 적이 있어서 이
구조를 만들었습니다.
