# 12장. CSR 레지스터와 실행 모드

> [← 11장 체크포인트와 정책 엔진](11_체크포인트와_정책_엔진.md) · [13장 호스트 인터페이스와 UART 프로토콜 →](13_호스트_인터페이스와_UART_프로토콜.md)

---

CSR 정의의 정본은 [`bbht_grover_csr.json`](../../software/contract/bbht_grover_csr.json)입니다.
사람이 읽을 수 있는
[CSR_레지스터_규격.md](../design_references/CSR_레지스터_규격.md)도 이 JSON에서 생성됩니다.
이 장에서는 레지스터 구조와 접근 규칙을 설명합니다.

---

## 12.1 CSR 접근 규격

| 항목 | 값 |
|---|---|
| base 매크로 | `I_GROVER_CSR_SLAVE_BASEADDR` |
| 현재 생성값 | `0xE2020000` |
| 메모리맵 크기 | `0x1000` |
| 레지스터 간격 | 4바이트 |
| 데이터 폭 | 32비트 |
| 버스 | APB3 슬레이브. `pready` 상수 1, 대기 상태 없음 |

정렬되지 않은 접근과 미할당 주소는 `pslverr`로 떨어집니다.

C 코드에서는 고정 주소 대신 생성된 매크로를 사용해야 합니다. 플랫폼 XML이 바뀌면 CSR
주소도 바뀔 수 있으며, 고정 주소는 잘못된 메모리 영역에 접근할 위험이 있습니다.

---

## 12.2 레지스터 접근 유형

| 표기 | 뜻 |
|---|---|
| `RW` | 설정. 저장되고 값이 IP로 상시 나갑니다 |
| `W1P` | 명령. 저장 공간이 없고 쓰면 1사이클 펄스만. 읽으면 0. 쓰는 데이터는 무시되고 쓰는 행위 자체가 명령입니다 |
| `RO` | 상태. IP가 내보내는 와이어를 읽기 응답에 실어 보냅니다 |
| `RPOP` | 읽기 완료가 곧 pop. 부작용이 있는 유일한 읽기입니다 |

`RPOP`은 `FIFO_DATA`에만 사용합니다. 값 0도 정상 결과일 수 있으므로(인덱스 0), FIFO의
빈 상태는 `FIFO_COUNT`나 `STATUS.fifo_empty`로 확인해야 합니다.

---

## 12.3 레지스터 맵 38개

### 설정과 명령

| 오프셋 | 이름 | 접근 | 폭 | 뜻 |
|--:|---|:-:|--:|---|
| `0x000` | `COMMAND` | W1P | 1 | 탐색 시작 |
| `0x004` | `CONTROL` | RW | 4 | 동작 모드 (12.4절) |
| `0x008` | `J_TARGET` | RW | 7 | 수동 `j` (0~127). `auto_shot=1`이면 무시 |
| `0x00C` | `THRESHOLD_A` | RW | 16 | 임계값 A. RANGE에서는 하한 |
| `0x010` | `THRESHOLD_B` | RW | 16 | RANGE 상한 (열린구간) |
| `0x014` | `DATA_COUNT` | RW | 15 | 유효 데이터 개수 1~16384 |
| `0x018` | `SHOT_CAP` | RW | 16 | BBHT 샷 상한. 기본 100 |
| `0x01C` | `SEED_J` | RW | 32 | `j` 선택 PRNG 시드 |
| `0x020` | `SEED_MEAS` | RW | 32 | 측정 PRNG 시드. `SEED_J`와 독립 |
| `0x03C` | `ENUM_CFG` | RW | 8 | 열거 설정 (12.4절) |
| `0x058` | `DATA_ADDR` | RW | 32 | SRAM 원본 주소. 4바이트 정렬 필수 |
| `0x05C` | `DMA_COMMAND` | W1P | 1 | DMA 적재 시작 |

### 결과와 상태

| 오프셋 | 이름 | 접근 | 뜻 |
|--:|---|:-:|---|
| `0x024` | `STATUS` | RO | 실행 상태 12비트 (12.5절) |
| `0x028` | `RESULT_INDEX` | RO | 단일 모드 결과. `STATUS.result_valid`가 1일 때만 의미 |
| `0x02C` | `TRIAL_COUNT` | RO | 논리 시도 수 |
| `0x030` | `L_BBHT` | RO | 요청 `j`의 합. 체크포인트로 줄지 않습니다 |
| `0x034` | `ACTUAL_ITER` | RO | 실제 돌린 물리 반복 수. 체크포인트가 줄이는 대상 |
| `0x038` | `CYCLE_COUNT` | RO | 소비 사이클. 100 MHz 기준이므로 `us = cycles/100` |
| `0x040` | `FIFO_DATA` | RPOP | 결과 FIFO head |
| `0x044` | `FIFO_COUNT` | RO | 현재 occupancy |
| `0x048` | `FOUND_COUNT` | RO | unique 타겟 누적 |
| `0x04C` | `CONSEC_FAIL` | RO | BBHT 완전 실패 연속 횟수 |
| `0x050` | `MAX_FIFO_OCC` | RO | 최대 occupancy |
| `0x054` | `FIFO_STALL` | RO | FIFO full로 멈춘 사이클 |
| `0x060` | `DMA_STATUS` | RO | DMA 상태 8비트 (12.6절) |

`L_BBHT`는 체크포인트 사용 여부와 관계없이 유지되는 알고리즘 지표이고,
`ACTUAL_ITER`는 체크포인트가 줄이는 실제 연산량입니다. 두 값을 구분해야 합니다
([14장](14_동작_과정과_사이클_구성.md)).

### 정책 텔레메트리

| 오프셋 | 이름 | 뜻 |
|--:|---|---|
| `0x064` | `POLICY_CYCLES_TOTAL` | 정책 총 사이클 |
| `0x068` | `POLICY_STALL_CYCLES` | 정책 때문에 데이터패스가 기다린 사이클 |
| `0x06C` | `POLICY_ACTIONS_EVAL` | 평가한 action 수 |
| `0x070` · `0x074` | `POLICY_MEMO_HIT` · `_MISS` | memo 적중·실패 |
| `0x078` | `POLICY_MAX_LATENCY` | 정책 최대 지연 |
| `0x07C` · `0x080` | `PLAN_FIFO_LEVEL` · `_HIGHWATER` | plan FIFO 수위 |
| `0x084` | `PLAN_FIFO_EMPTY_DEMAND` | 필요할 때 비어 있던 횟수 |
| `0x088` | `PLAN_FIFO_HIT_COUNT` | 선행 계획 적중 |
| `0x08C` | `PLAN_FIFO_MISMATCH_COUNT` | 정상 기대값 0 |
| `0x090` · `0x094` | `POLICY_COLD_SOLVE_COUNT` · `_SPEC_SOLVE_COUNT` | cold · speculative 풀이 횟수 |

이 19개 레지스터로 [11장](11_체크포인트와_정책_엔진.md)의 정책 엔진 상태를 외부에서
관찰할 수 있습니다. `POLICY_MAX_LATENCY`가 3,352이면 memo 초기화가 발생한 경우입니다.

---

## 12.4 비트 필드

`CONTROL` (`0x004`)

| 비트 | 이름 | 뜻 |
|:-:|---|---|
| 0 | `auto_shot` | 1: BBHT가 `j`를 자동 생성 |
| 1 | `burst_enable` | 1: 체크포인트 재사용 |
| 3:2 | `predicate_mode` | 00 `LT` / 01 `GT` / 10 `EQ` / 11 `RANGE` |

`ENUM_CFG` (`0x03C`)

| 비트 | 이름 | 뜻 |
|:-:|---|---|
| 0 | `enum_enable` | 0 단일, 1 열거 |
| 7:4 | `fail_repeat_limit` | 완전 실패 반복 한계. 유효 1~15, 0은 config error |

---

## 12.5 `STATUS` (`0x024`)

| 비트 | 이름 | 뜻 |
|--:|---|---|
| 0 | `busy` | search/main busy |
| 1 | `load_busy` | loader busy |
| 2 | `done_sticky` | 탐색 완료 sticky. `COMMAND` 쓰기로 클리어 |
| 3 | `result_valid` | 단일 결과 유효 |
| 4 | `config_error` | 설정 오류 sticky |
| 5 | `shot_limit` | 샷 상한 도달 sticky |
| 6 | `budget_limit` | 논리 예산 도달 sticky |
| 7 | `amp_overflow` | 진폭 포화 sticky. 진단용이며 종료 사유가 아님 |
| 8 | `zero_weight_error` | Born 전체 가중치 0 sticky |
| 9 | `load_error` | loader 검증 오류 sticky |
| 10 | `enum_done` | 열거 종료 sticky |
| 11 | `fifo_empty` | 결과 FIFO 비어 있음 |

`search_busy`는 따로 나오지 않습니다. 계약이 `busy = search_busy | load_busy`이므로
`busy & ~load_busy`로 유도합니다([5장 5.5절](05_하드웨어_아키텍처_개요.md)).

---

## 12.6 `DMA_STATUS` (`0x060`)

| 비트 | 이름 | 뜻 |
|--:|---|---|
| 0 | `dma_busy` | 진행 중 |
| 1 | `dma_error` | 아래 오류들의 OR |
| 2 | `align_error` | `DATA_ADDR` 4바이트 정렬 위반 |
| 3 | `count_error` | `DATA_COUNT` 범위 위반 |
| 4 | `resp_error` | AHB 응답 오류 |
| 5 | `busy_error` | Main IP busy 라서 거절 |
| 6 | `range_error` | SRAM 범위 밖 |
| 7 | `dma_done_sticky` | 완료 sticky |

검사 시점과 이유는 [7장 7.3절](07_통신_계층.md).

---

## 12.7 다섯 실행 모드

모드는 별도 레지스터가 아니라 세 비트의 조합입니다.

| 이름 | `auto_shot` | `burst_enable` | `enum_enable` | 설명 |
|---|:-:|:-:|:-:|---|
| `MANUAL_SINGLE` | 0 | 0 | 0 | `J_TARGET`을 펌웨어가 지정 |
| `NORMAL_SINGLE` | 1 | 0 | 0 | 표준 BBHT |
| `CKPT_SINGLE` | 1 | 1 | 0 | 체크포인트 모드 |
| `NORMAL_ENUM` | 1 | 0 | 1 | 표준 BBHT 열거 |
| `CKPT_ENUM` | 1 | 1 | 1 | 체크포인트 열거 |

`checkpoint_auto_enable = burst_enable && auto_shot`이므로 수동 모드에서는 체크포인트가
걸리지 않습니다([7장 7.1절](07_통신_계층.md)).

### 실행 모드 이름에서 K·H를 제외한 이유

실행 모드 이름은 2026-09-10에 `K4H8_*`에서 `CKPT_*`로 바꿨습니다. K·H·E·M은 전부
RTL 빌드에 컴파일되는 값이라 CSR 모드 이름에 값을 포함하면 빌드가 바뀔 때마다 이름이
틀려지기 때문입니다: 실제로 K4/H8에서 K4/H4를 거쳐 지금은 K3/H3입니다.

`bbht_paper_bench`의 `CONTROL_K4H8_EQ` · `MODE_K4H8`은 그대로 두었습니다. 그 파일은
보드 ELF를 낸 소스와 sha256이 같아야 하기 때문입니다.

소프트웨어 기준모델은 CSR 모드 이름 대신 정책 이름으로 부릅니다
([4장 4.1절](04_소프트웨어_기준모델과_정답_벡터.md)).

---

## 12.8 생성 파이프라인

`gen_csr.py`는 정본 JSON에서 다음 네 파일을 생성합니다. 생성된 파일은 직접 수정하지
않습니다.

| 생성물 | 쓰는 곳 |
|---|---|
| `generated/bbht_grover_csr.vh` | RTL (`bbht_grover_mmio.v` 등 네 곳) |
| `generated/bbht_grover_regs.h` | 펌웨어 C |
| `generated/bbht_grover_csr.py` | 호스트 CLI |
| `CSR_레지스터_규격.md` | 사람이 읽는 판 |

같은 숫자를 들고 있으면서 생성 대상이 아닌 곳이 둘 더 있습니다.

| 곳 | 왜 생성 대상이 아닌가 |
|---|---|
| `software/models/common/final_hardware_contract.py` | CSR과 다른 축인 정책 이름을 같이 담습니다 |
| `firmware/bbht_paper_bench/src/main.c` | 보드 ELF 소스라 못 고칩니다 |

`gen_csr.py --check`가 그 둘을 읽어서 정본과 대조합니다. 셋째 검사는 방향이 반대로,
RTL 안에 CSR 값을 다시 박아 두는 것을 막습니다.

```bash
python3 software/contract/gen_csr.py          # 갱신
python3 software/contract/gen_csr.py --check  # 확인만 (CI 용)
```

`hardware_bram/sim/Makefile`의 모든 타깃이 이것을 먼저 돌리므로, 생성 헤더를 손으로
고쳐 놓고 회귀만 통과시키는 일이 생기지 않습니다.
