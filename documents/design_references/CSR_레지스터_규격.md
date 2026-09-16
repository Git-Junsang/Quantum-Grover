# CSR 레지스터 규격

> **이 파일은 `software/contract/gen_csr.py` 가 `bbht_grover_csr.json` 에서 생성합니다.**
> 손으로 고치지 마십시오 — 다음 생성에서 덮어써집니다.
> 값을 바꾸려면 JSON 을 고치고 `python3 gen_csr.py` 를 돌리십시오.
>
> 출처: PJK `팀원_Handoff_SW_통신_v0.9.8` §1.4 / §1.5. 정본 버전 0.9.8 (2026-09-01)

---

## 1. 접근 방법

| 항목 | 값 |
|---|---|
| base address 매크로 | `I_GROVER_CSR_SLAVE_BASEADDR` |
| 현재 생성값 | `0xE2020000` (이 환경 `make syn` 실측) |
| 메모리맵 크기 | `0x1000` |
| 레지스터 간격 | 4 바이트 |
| 데이터 폭 | 32 비트 |
| 버스 | APB3 슬레이브. `pready` 상수 1, 대기 상태 없음 |

정렬되지 않은 접근과 미할당 주소는 `pslverr` 로 떨어집니다.

**C 코드는 숫자를 박지 말고 매크로를 쓰십시오.** 플랫폼 XML 이 바뀌면
주소가 옮겨가고, 박아 둔 숫자는 조용히 엉뚱한 곳을 두드립니다.

## 2. 탐색 공간

| 항목 | 값 |
|---|---|
| 유효 큐비트 | Q = 14 |
| 탐색 공간 | N = 16,384 |
| 데이터 워드 | 16 비트 signed |
| 결과 인덱스 | 14 비트 |
| Result FIFO | 14 비트 x 256 칸 |
| 가속기 클럭 | 100 MHz -- `CYCLE_COUNT` 의 기준 |
| SoC 클럭 | 50 MHz -- UART 보율의 기준 |
| System SRAM | `0xE0000000` ~ `0xE001FFFF` |

## 3. 접근 성격

| 표기 | 뜻 |
|---|---|
| `RW` | 설정. 여기 저장되고 값이 IP 로 상시 나갑니다 |
| `W1P` | 명령. 저장 공간이 없고 쓰면 1사이클 펄스만 나갑니다. **읽으면 0**. 쓰는 데이터는 무시되고 쓰는 행위 자체가 명령입니다 |
| `RO` | 상태. IP 가 내보내는 와이어를 읽기 응답에 실어 보냅니다 |
| `RPOP` | **읽기 완료가 곧 pop**. 부작용이 있는 유일한 읽기입니다 |

## 4. 레지스터 맵

| 오프셋 | 이름 | 접근 | 폭 | 뜻 |
|--:|---|:-:|--:|---|
| `0x000` | `COMMAND` | W1P | 1 | 탐색 시작. 쓰는 행위 자체가 명령이고 저장 공간이 없습니다 |
| `0x004` | `CONTROL` | RW | 4 | 동작 모드 |
| `0x008` | `J_TARGET` | RW | 7 | manual requested j (0~127). auto_shot=1 이면 무시됩니다 |
| `0x00C` | `THRESHOLD_A` | RW | 16 | 임계값 A. RANGE 에서는 하한 |
| `0x010` | `THRESHOLD_B` | RW | 16 | 임계값 B. RANGE 상한 (A < data < B, 열린구간) |
| `0x014` | `DATA_COUNT` | RW | 15 | 유효 데이터 개수 1~16384. 그 이후 인덱스는 non-target |
| `0x018` | `SHOT_CAP` | RW | 16 | BBHT shot 상한. 기본 100 |
| `0x01C` | `SEED_J` | RW | 32 | requested-j PRNG 시드 |
| `0x020` | `SEED_MEAS` | RW | 32 | 측정 PRNG 시드. SEED_J 와 독립 |
| `0x024` | `STATUS` | RO | 12 | 실행 상태. bit 정의는 status_bits 참조 |
| `0x028` | `RESULT_INDEX` | RO | 14 | Single 모드 결과 인덱스. STATUS.result_valid 가 1 일 때만 의미가 있습니다 |
| `0x02C` | `TRIAL_COUNT` | RO | 32 | run 전체의 logical trial 수 |
| `0x030` | `L_BBHT` | RO | 32 | Sum of requested j - 알고리즘 지표. checkpoint 로 줄지 않습니다 |
| `0x034` | `ACTUAL_ITER` | RO | 32 | 실제로 돌린 물리 Grover 반복 수 - checkpoint 가 줄이는 대상 |
| `0x038` | `CYCLE_COUNT` | RO | 32 | run 소비 사이클. clk_accel(100 MHz) 기준이므로 us = cycles/100 |
| `0x03C` | `ENUM_CFG` | RW | 8 | 열거 모드 설정 |
| `0x040` | `FIFO_DATA` | RPOP | 14 | Result FIFO head. 읽기 완료 자체가 pop 입니다. 별도 POP 레지스터는 없습니다 |
| `0x044` | `FIFO_COUNT` | RO | 9 | 현재 FIFO occupancy |
| `0x048` | `FOUND_COUNT` | RO | 15 | unique target 누적 |
| `0x04C` | `CONSEC_FAIL` | RO | 4 | complete BBHT failure 연속 횟수 |
| `0x050` | `MAX_FIFO_OCC` | RO | 9 | run 중 최대 occupancy |
| `0x054` | `FIFO_STALL` | RO | 32 | FIFO full 로 멈춘 사이클 |
| `0x058` | `DATA_ADDR` | RW | 32 | System SRAM 원본 주소. 4바이트 정렬 필수 |
| `0x05C` | `DMA_COMMAND` | W1P | 1 | DMA 적재 시작 |
| `0x060` | `DMA_STATUS` | RO | 8 | DMA 상태. bit 정의는 dma_status_bits 참조 |
| `0x064` | `POLICY_CYCLES_TOTAL` | RO | 32 | policy 총 사이클 |
| `0x068` | `POLICY_STALL_CYCLES` | RO | 32 | policy stall |
| `0x06C` | `POLICY_ACTIONS_EVAL` | RO | 32 | 평가한 action 수 |
| `0x070` | `POLICY_MEMO_HIT` | RO | 32 | memo hit |
| `0x074` | `POLICY_MEMO_MISS` | RO | 32 | memo miss |
| `0x078` | `POLICY_MAX_LATENCY` | RO | 32 | policy 최대 지연 |
| `0x07C` | `PLAN_FIFO_LEVEL` | RO | 3 | 현재 plan FIFO 레벨 |
| `0x080` | `PLAN_FIFO_HIGHWATER` | RO | 3 | plan FIFO 최고 수위 |
| `0x084` | `PLAN_FIFO_EMPTY_DEMAND` | RO | 32 | demand 시 empty 횟수 |
| `0x088` | `PLAN_FIFO_HIT_COUNT` | RO | 32 | speculative plan hit |
| `0x08C` | `PLAN_FIFO_MISMATCH_COUNT` | RO | 32 | 정상 기대값 0 |
| `0x090` | `POLICY_COLD_SOLVE_COUNT` | RO | 32 | cold solve 횟수 |
| `0x094` | `POLICY_SPEC_SOLVE_COUNT` | RO | 32 | speculative solve |

### 4.1 비트 필드가 있는 레지스터

**`COMMAND`** (`0x000`)

| 비트 | 이름 | 뜻 |
|:-:|---|---|
| `0` | `search_start` | external search start |

**`CONTROL`** (`0x004`)

| 비트 | 이름 | 뜻 |
|:-:|---|---|
| `0` | `auto_shot` | 1: BBHT 가 requested j 자동 생성 |
| `1` | `burst_enable` | 1: checkpoint 재사용 사용 (K·H 는 RTL 빌드 상수. 현 freeze 는 K3/H3) |
| `3:2` | `predicate_mode` | 00 LT / 01 GT / 10 EQ / 11 RANGE |

**`ENUM_CFG`** (`0x03C`)

| 비트 | 이름 | 뜻 |
|:-:|---|---|
| `0` | `enum_enable` | 0: Single, 1: Enumeration |
| `7:4` | `fail_repeat_limit` | complete-BBHT failure 반복 한계. 유효 1~15, 0 은 config error |

**`DMA_COMMAND`** (`0x05C`)

| 비트 | 이름 | 뜻 |
|:-:|---|---|
| `0` | `dma_start` | DMA session start |

## 5. STATUS (`0x024`)

| 비트 | 이름 | 뜻 |
|--:|---|---|
| 0 | `busy` | search/main busy |
| 1 | `load_busy` | Main IP loader busy |
| 2 | `done_sticky` | search 완료 sticky. COMMAND 쓰기로 클리어 |
| 3 | `result_valid` | Single result 유효 |
| 4 | `config_error` | 설정 오류 sticky |
| 5 | `shot_limit` | shot cap 도달 sticky |
| 6 | `budget_limit` | BBHT logical budget 도달 sticky |
| 7 | `amp_overflow` | 진폭 포화 sticky. 진단용이며 종료 사유가 아님 |
| 8 | `zero_weight_error` | Born total-weight 오류 sticky |
| 9 | `load_error` | loader 검증 오류 sticky |
| 10 | `enum_done` | Enumeration 종료 sticky |
| 11 | `fifo_empty` | Result FIFO 비어 있음 |

## 6. DMA_STATUS (`0x060`)

| 비트 | 이름 | 뜻 |
|--:|---|---|
| 0 | `dma_busy` | DMA 진행 중 |
| 1 | `dma_error` | 아래 오류들의 OR |
| 2 | `align_error` | DATA_ADDR 4바이트 정렬 위반 |
| 3 | `count_error` | DATA_COUNT 범위 위반 |
| 4 | `resp_error` | AHB 응답 오류 |
| 5 | `busy_error` | Main IP busy 라서 DMA 거절 |
| 6 | `range_error` | System SRAM 범위 밖 |
| 7 | `dma_done_sticky` | DMA 완료 sticky |

## 7. 술어

| 값 | 이름 | 조건 |
|--:|---|---|
| 0 | `LT` | data < A |
| 1 | `GT` | data > A |
| 2 | `EQ` | data == A |
| 3 | `RANGE` | A < data < B (열린구간) |

`RANGE` 는 **열린구간**입니다. 경계값 자체는 정답이 아닙니다.

## 8. 권장 운용 모드

| 용도 | `auto_shot` | `burst_enable` | `enum_enable` | 설명 |
|---|:-:|:-:|:-:|---|
| MANUAL_SINGLE | 0 | 0 | 0 | J_TARGET 을 펌웨어가 지정 |
| NORMAL_SINGLE | 1 | 0 | 0 | 표준 BBHT |
| CKPT_SINGLE | 1 | 1 | 0 | checkpoint 모드 (K·H·E·M 은 RTL 빌드에 컴파일됨. 현 정본은 K3/H3-E4-M2) |
| NORMAL_ENUM | 1 | 0 | 1 | 표준 BBHT 열거 |
| CKPT_ENUM | 1 | 1 | 1 | checkpoint 열거 (K·H·E·M 은 RTL 빌드에 컴파일됨. 현 정본은 K3/H3-E4-M2) |

`checkpoint_auto_enable = burst_enable && auto_shot` 입니다. `auto_shot=0`
(manual) 에서는 checkpoint 가 걸리지 않습니다.

## 9. 생성물

이 정본에서 같이 나오는 것들입니다. 손으로 고치면 다음 생성에서 사라집니다.

| 파일 | 쓰는 곳 |
|---|---|
| `software/contract/generated/bbht_grover_regs.h` | 펌웨어 C |
| `software/contract/generated/bbht_grover_csr.vh` | RTL (`bbht_grover_mmio.v` 등) |
| `software/contract/generated/bbht_grover_csr.py` | 호스트 CLI |
| `documents/design_references/CSR_레지스터_규격.md` | 이 문서 |

`python3 gen_csr.py --check` 는 갱신 없이 최신인지만 확인합니다.
`hardware_bram/sim/Makefile` 의 모든 타깃이 이것을 먼저 돌리므로, 생성 헤더를
손으로 고쳐 놓고 회귀만 통과시키는 일이 생기지 않습니다.
