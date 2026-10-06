# 13장. CSR 레지스터와 실행 모드

> [← 12장 Main IP 포트 계약](12_Main_IP_포트_계약.md) · [문서 지도](00_문서_지도.md) · [14장 호스트 인터페이스와 UART 프로토콜 →](14_호스트_인터페이스와_UART_프로토콜.md)

> 이 장은 `software/contract/gen_csr.py` 가 CSR 정본 [`bbht_grover_csr.json`](../../software/contract/bbht_grover_csr.json) 에서 생성합니다.
> 손으로 고치면 다음 생성에서 덮어써집니다. 값은 JSON 을, 문장은 `gen_csr.py` 의
> `gen_doc()` 를 고친 뒤 `python3 software/contract/gen_csr.py` 를 돌리십시오.
>
> 출처: PJK `팀원_Handoff_SW_통신_v0.9.8` §1.4 / §1.5. 정본 버전 0.9.8 (2026-09-01)

---

호스트 펌웨어가 가속기를 부리는 창구는 APB 레지스터 38개입니다. CSR 계약은 v0.9.8 이후
바뀌지 않았고, 보드에 구운 두 통신 계층 판의 오프셋 표도 전부 일치합니다. 레지스터가
Main IP 포트와 어떻게 이어지는지는 [12장](12_Main_IP_포트_계약.md), 호스트 명령이 어느
레지스터를 두드리는지는 [14장](14_호스트_인터페이스와_UART_프로토콜.md)에 있습니다.

---

## 13.1 CSR 접근 규격

| 항목 | 값 |
|---|---|
| base address 매크로 | `I_GROVER_CSR_SLAVE_BASEADDR` |
| 현재 생성값 | `0xE2020000` (이 환경 `make syn` 실측) |
| 메모리맵 크기 | `0x1000` |
| 레지스터 간격 | 4바이트 |
| 데이터 폭 | 32비트 |
| 버스 | APB3 슬레이브. `pready` 상수 1, 대기 상태 없음 |

정렬되지 않은 접근과 미할당 주소는 `pslverr` 로 떨어집니다.

C 코드에서는 숫자를 박지 말고 생성된 매크로를 씁니다. 플랫폼 XML 이 바뀌면 주소가
옮겨가고, 박아 둔 숫자는 조용히 엉뚱한 곳을 두드립니다.

---

## 13.2 탐색 공간과 클럭

| 항목 | 값 |
|---|---|
| 유효 큐비트 | Q = 14 |
| 탐색 공간 | N = 16,384 |
| 데이터 워드 | 16비트 signed |
| 결과 인덱스 | 14비트 |
| 결과 FIFO | 14비트 × 256칸 |
| 가속기 클럭 | 100 MHz. `CYCLE_COUNT` 의 기준이라 `us = cycles / 100` |
| SoC 클럭 | 50 MHz. UART 보율의 기준 |
| 시스템 SRAM | `0xE0000000` ~ `0xE001FFFF` |

---

## 13.3 레지스터 접근 유형

| 표기 | 뜻 |
|---|---|
| `RW` | 설정. 저장되고 값이 IP 로 상시 나갑니다 |
| `W1P` | 명령. 저장 공간이 없고 쓰면 1사이클 펄스만 나갑니다. 읽으면 0. 쓰는 데이터는 무시되고 쓰는 행위 자체가 명령입니다 |
| `RO` | 상태. IP 가 내보내는 와이어를 읽기 응답에 실어 보냅니다 |
| `RPOP` | 읽기 완료가 곧 pop. 부작용이 있는 유일한 읽기입니다 |

`RPOP` 은 `FIFO_DATA` 하나뿐입니다. 인덱스 0 이 정상 결과일 수 있으므로 값 0 을 비었다는
뜻으로 읽으면 안 되고, `FIFO_COUNT` 나 `STATUS.fifo_empty` 로 확인합니다.

---

## 13.4 레지스터 맵

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

`L_BBHT` 는 체크포인트 사용 여부와 관계없이 유지되는 알고리즘 지표이고, `ACTUAL_ITER` 는
체크포인트가 줄이는 실제 연산량입니다. 둘을 구분해야 합니다([15장](15_동작_과정과_사이클_구성.md)).
`0x064` 부터의 정책 텔레메트리로 [11장](11_체크포인트와_정책_엔진.md)의 정책 엔진을 밖에서
관찰할 수 있습니다. `POLICY_MAX_LATENCY` 가 3,352 로 튀면 리셋 뒤 memo 청소가 일어난
실행입니다.

### 비트 필드가 있는 레지스터

`COMMAND` (`0x000`)

| 비트 | 이름 | 뜻 |
|:-:|---|---|
| `0` | `search_start` | external search start |

`CONTROL` (`0x004`)

| 비트 | 이름 | 뜻 |
|:-:|---|---|
| `0` | `auto_shot` | 1: BBHT 가 requested j 자동 생성 |
| `1` | `burst_enable` | 1: checkpoint 재사용 사용 (K·H 는 RTL 빌드 상수. 현 freeze 는 K3/H3) |
| `3:2` | `predicate_mode` | 00 LT / 01 GT / 10 EQ / 11 RANGE |

`ENUM_CFG` (`0x03C`)

| 비트 | 이름 | 뜻 |
|:-:|---|---|
| `0` | `enum_enable` | 0: Single, 1: Enumeration |
| `7:4` | `fail_repeat_limit` | complete-BBHT failure 반복 한계. 유효 1~15, 0 은 config error |

`DMA_COMMAND` (`0x05C`)

| 비트 | 이름 | 뜻 |
|:-:|---|---|
| `0` | `dma_start` | DMA session start |

---

## 13.5 `STATUS` (`0x024`)

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

자주 보게 되는 값입니다.

| 값 | 뜻 |
|---|---|
| `0x080c` | 완료 + 결과 유효 + FIFO 빔. 정상 Single |
| `0x0404` | 완료 + 열거 종료, FIFO 에 결과 남음. 아직 뽑아야 함 |
| `0x0c04` | 완료 + 열거 종료 + FIFO 빔. 다 뽑았음 |
| `0x0844` | 완료 + 예산 도달 + FIFO 빔. 못 찾고 끝남 |

`done_sticky` 를 지우는 것은 `COMMAND` 쓰기뿐입니다. `STATUS` 를 읽거나 설정을 바꿔도
지워지지 않습니다. `search_busy` 는 따로 나오지 않고 `busy & ~load_busy` 로 유도합니다.

---

## 13.6 `DMA_STATUS` (`0x060`)

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

`0x00000080` 이면 완료만 선 정상 상태입니다. 검사 시점과 이유는
[7장 7.3절](07_통신_계층.md#73-loader-의-사전-검사)에 있습니다.

---

## 13.7 술어와 실행 모드

| 값 | 이름 | 조건 |
|--:|---|---|
| 0 | `LT` | data < A |
| 1 | `GT` | data > A |
| 2 | `EQ` | data == A |
| 3 | `RANGE` | A < data < B (열린구간) |

`RANGE` 는 열린구간입니다. 경계값 자체는 정답이 아닙니다.

실행 모드는 별도 레지스터가 아니라 세 비트의 조합입니다.

| 이름 | `auto_shot` | `burst_enable` | `enum_enable` | 설명 |
|---|:-:|:-:|:-:|---|
| `MANUAL_SINGLE` | 0 | 0 | 0 | J_TARGET 을 펌웨어가 지정 |
| `NORMAL_SINGLE` | 1 | 0 | 0 | 표준 BBHT |
| `CKPT_SINGLE` | 1 | 1 | 0 | checkpoint 모드 (K·H·E·M 은 RTL 빌드에 컴파일됨. 현 정본은 K3/H3-E4-M2) |
| `NORMAL_ENUM` | 1 | 0 | 1 | 표준 BBHT 열거 |
| `CKPT_ENUM` | 1 | 1 | 1 | checkpoint 열거 (K·H·E·M 은 RTL 빌드에 컴파일됨. 현 정본은 K3/H3-E4-M2) |

`checkpoint_auto_enable = burst_enable && auto_shot` 이므로 수동 모드(`auto_shot=0`)에서는
체크포인트가 걸리지 않습니다([7장 7.1절](07_통신_계층.md#71-wrapper-의-제어-로직)).
체크포인트 없는 판과 DRAM 갈래는 `burst_enable` 을 무시하고 NORMAL 로 돕니다.

### 모드 이름에 K · H 를 넣지 않는 이유

실행 모드 이름은 2026-09-10 에 `K4H8_*` 에서 `CKPT_*` 로 바꿨습니다. K · H · E · M 은 전부
RTL 빌드에 컴파일되는 값이라 이름에 값을 넣으면 빌드가 바뀔 때마다 이름이 틀려집니다. 실제로
K4/H8 에서 K4/H4 를 거쳐 지금은 K3/H3 입니다.

`bbht_paper_bench` 의 `CONTROL_K4H8_EQ` · `MODE_K4H8` 은 그대로 두었습니다. 그 파일은 보드
ELF 를 낸 소스와 sha256 이 같아야 합니다. 소프트웨어 기준모델은 CSR 모드 이름 대신 정책
이름으로 부릅니다([4장 4.2절](04_소프트웨어_기준모델과_정답_벡터.md#42-세-계층의-기준-모델)).

---

## 13.8 생성 파이프라인

정본 JSON 하나에서 넷을 생성합니다. 생성물은 손으로 고치지 않습니다.

| 생성물 | 쓰는 곳 |
|---|---|
| `software/contract/generated/bbht_grover_csr.vh` | RTL (`bbht_grover_mmio.v` 등 네 곳) |
| `software/contract/generated/bbht_grover_regs.h` | 펌웨어 C |
| `software/contract/generated/bbht_grover_csr.py` | 호스트 CLI |
| `documents/design_references/13_CSR_레지스터와_실행_모드.md` | 이 장 |

같은 숫자를 들고 있으면서 생성 대상이 아닌 곳이 둘 더 있습니다.

| 곳 | 생성 대상이 아닌 이유 |
|---|---|
| `software/models/common/final_hardware_contract.py` | CSR 과 다른 축인 정책 이름을 같이 담습니다 |
| `hardware_bram/firmware/bbht_paper_bench/src/main.c` | 보드 ELF 소스라 한 글자도 못 고칩니다 |

`gen_csr.py --check` 가 그 둘을 읽기만 하고 정본과 대조합니다(main.c 는 이름을 줄여 쓴
것이 있어 오프셋 기준으로 봅니다). 셋째 검사는 방향이 반대로, 생성 헤더를 우회해 RTL 안에
CSR 값을 다시 박는 것을 막습니다.

```bash
python3 software/contract/gen_csr.py          # 갱신
python3 software/contract/gen_csr.py --check  # 갱신 없이 확인만 (CI 용)
```

체크포인트 판 `sim/Makefile` 은 모든 타깃에서 `--check` 를, 체크포인트 없는 판은 생성을 먼저
돌리므로 생성 헤더를 손으로 고쳐 놓고 회귀만 통과시키는 일이 생기지 않습니다(DRAM 갈래는 생성
헤더를 include 만 합니다). CSR 정의가 옛 펌웨어 헤더(8바이트 간격
제안안) · 옛 설계안 mmio · proof app 마다의 복사본 세 곳에 따로 있다가 어긋난 적이 있어서 이
구조를 만들었습니다.
