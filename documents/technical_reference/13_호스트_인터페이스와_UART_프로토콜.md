# 13장. 호스트 인터페이스와 UART 프로토콜

> [← 12장 CSR 레지스터와 실행 모드](12_CSR_레지스터와_실행_모드.md) · [14장 동작 과정과 사이클 구성 →](14_동작_과정과_사이클_구성.md)

---

명령 문법은 [UART_명령_프로토콜.md](../design_references/UART_명령_프로토콜.md), 실제 운용
절차는 [호스트_조작_방법.md](../design_references/호스트_조작_방법.md)를 기준으로 합니다.
이 장에서는 프로토콜의 구조와 설계 의도를 설명합니다.

---

## 13.1 ASCII 라인 프로토콜을 선택한 이유

바이너리 프레임이 아니라 사람이 읽고 칠 수 있는 한 줄입니다.

- 시리얼 터미널만으로 보드를 제어할 수 있습니다.
- 트랜스크립트가 그대로 로그이자 회귀 입력이 됩니다: SoC 시뮬 트랜스크립트를 호스트
  CLI의 재생 트랜스포트에 그대로 입력해 파싱할 수 있습니다
  ([15장](15_검증_체계.md))
- 파싱 버그가 눈에 보입니다

---

## 13.2 링크 규약

| 항목 | 값 |
|---|---|
| 보율 | 115200 (SoC 50 MHz 기준) |
| 프레이밍 | 8N1 |
| 흐름 제어 | 없음 |
| 줄 끝 | 보내는 쪽 `\n` 또는 `\r\n`, 받는 쪽 `\r\n` |
| 인코딩 | ASCII |

응답을 다 받은 뒤에 다음 명령을 보냅니다. 흐름 제어가 없는 원시 스트림이라, 보드가
폴링 루프에 들어가 있는 동안 명령을 밀어 넣으면 RX FIFO가 넘칩니다. 호스트 스크립트를
짤 때 이것을 강제해야 합니다.

응답 한 덩어리는 반드시 `OK` 또는 `ERR`로 끝납니다. 데이터 줄이 먼저 나오고 마지막
줄이 종결자입니다. 호스트는 그 줄을 보고 다음으로 넘어갑니다.

콘솔은 받은 글자를 그대로 되비춥니다(에코). 사람이 칠 때 필요한 것이고, 스크립트는 명령을
보내기 전에 입력 버퍼를 비우면 영향이 없습니다. 백스페이스(`BS` / `DEL`)를 받습니다.

---

## 13.3 명령

| 명령 | 뜻 |
|---|---|
| `HELP` | 명령 목록 |
| `ID` | 펌웨어·하드웨어 식별. CSR base, N, 클럭, 데이터셋 상태 |
| `SET K=V ...` | 설정 변경 |
| `SHOW` | 현재 설정 |
| `GEN ...` | 보드 위에서 데이터셋 생성 |
| `POKE IDX=i VAL=v` | 한 칸 수정 |
| `PEEK IDX=i` | 한 칸 읽기 (보드 버퍼) |
| `LOAD` | 버퍼를 DMA로 IP에 적재 |
| `RUN` | 단일 탐색 |
| `ENUM` | 열거 |
| `STAT` | 마지막 실행의 카운터와 텔레메트리 |
| `REG` | CSR 전체 덤프 |

명령과 키 이름은 대소문자를 가리지 않습니다. 숫자는 10진수 기본, `0x` 접두사면 16진수,
앞의 `-`는 음수입니다.

이 셸을 사용하면 재빌드 없이 검색 조건을 바꿀 수 있습니다. 술어를 바꾸기 위해
비트스트림이나 ELF를 다시 만들 필요가 없습니다.

### `SET`의 키와 CSR 대응

| 키 | 값 | CSR |
|---|---|---|
| `MODE` | `LT` `GT` `EQ` `RANGE` | `CONTROL[3:2]` |
| `A` | signed 16비트 임계값 | `THRESHOLD_A` |
| `B` | signed 16비트 상한 (`RANGE` 전용) | `THRESHOLD_B` |
| `COUNT` | 유효 데이터 개수 1~16384 | `DATA_COUNT` |
| `CAP` | 샷 상한 | `SHOT_CAP` |
| `SEEDJ` · `SEEDM` | 두 PRNG 시드 | `SEED_J` · `SEED_MEAS` |
| `AUTO` | 0 수동 `j`, 1 BBHT 자율 | `CONTROL[0]` |
| `BURST` | 0 Normal, 1 체크포인트 | `CONTROL[1]` |
| `J` | 수동 `j` (0~127) | `J_TARGET` |
| `FAILLIM` | 열거 실패 반복 한계 1~15 | `ENUM_CFG[7:4]` |

임계값은 signed 값이므로 `SET A=-777`과 같이 음수를 지정할 수 있습니다. 부호 처리를
누락하면 `LT`와 같은 술어가 음수 영역에서 잘못 동작합니다.

`RANGE`는 열린구간이고 `B > A` 여야 합니다. 아니면 `ERR RANGE_NEEDS_B_GT_A`.

### `GEN`을 이용한 데이터셋 생성

| 키 | 기본값 | 뜻 |
|---|---|---|
| `COUNT` | 16384 | 만들 항목 수 |
| `SEED` | `0x5EED1234` | 배경 xorshift32 시드 |
| `POS` | `0xA17E2026` | 목표 위치 시드 |
| `TARGETS` | 1 | 심을 목표 개수 |
| `VAL` | 12345 | 목표값 |

배경을 만들 때 목표값과 같아지는 자리는 한 비트를 뒤집어 피합니다. 그래야 `TARGETS`로
심은 개수가 곧 정답 개수가 됩니다.

`GEN`이나 `POKE` 뒤에는 반드시 `LOAD`를 해야 합니다. 안 하면 `ERR NOT_LOADED`가
납니다: 보드 버퍼만 바뀌고 IP 안의 배열은 그대로이기 때문입니다.

---

## 13.4 응답

### 데이터 줄

| 태그 | 언제 | 예 |
|---|---|---|
| `HIT` | `RUN`이 해를 찾음 | `HIT idx=8685 val=12345 trials=21 l=119 iters=119 cyc=41310 us=413` |
| `MISS` | `RUN`이 못 찾음 | `MISS reason=SHOT_CAP trials=100 cyc=1200000 us=12000` |
| `FOUND` | `ENUM`이 해 하나를 뱉음 | `FOUND idx=507 val=12345` |
| `END` | `ENUM` 종료 요약 | `END count=4 found=4 cyc=280494 us=2804` |
| `STAT` | `ID` · `PEEK` · `STAT` | `STAT trials=21 l_bbht=119 actual_iter=38 cyc=17847 us=178` |
| `CFG` | `SHOW` | `CFG mode=EQ a=12345 b=0 count=16384 cap=100` |
| `REG` | `REG` | `REG 0x024 = 0x0000080c` |
| `#` | 주석·경고 | `# amp_overflow (진단용, 결과는 유효)` |

`#`로 시작하는 줄은 사람을 위한 것이고 파서가 무시해도 됩니다.

### `us=`는 실경과 시간이 아닙니다

펌웨어가 `bbht_cycles_to_us(cycle_count)`로 사이클에서 환산한 값(100 MHz 기준)입니다.
따라서 시뮬레이션과 보드에서 같은 값이 나옵니다. 실경과 시간은 이 값이 아니라
[1장 1.5절](01_프로젝트_개요.md)의 성능 측정 결과를 사용합니다.

### 주요 `ERR` 토큰

| 토큰 | 뜻 |
|---|---|
| `UNKNOWN_CMD` · `BAD_KV` | 명령·키 파싱 실패 |
| `BAD_COUNT` · `BAD_INDEX` · `TOO_MANY_TARGETS` | 인자 범위 |
| `RANGE_NEEDS_B_GT_A` | `RANGE`인데 `B <= A` |
| `NO_DATASET` · `NOT_LOADED` | 버퍼가 비었거나 적재 안 함 |
| `DMA_ERROR` | 뒤에 `dma_status=0x..`가 붙습니다 |
| `STATUS_ERROR` | 뒤에 `status=0x..` |
| `BUSY` | start 수락 조건 불충족 ([5장 5.5절](05_하드웨어_아키텍처_개요.md)) |
| `TIMEOUT` | 폴링 상한 초과 |
| `HOST_TIMEOUT` | 보드가 아니라 호스트 쪽 도구가 붙이는 토큰. 보드가 응답하지 않음 |

`MISS reason`은 `SHOT_CAP` · `BUDGET` · `NONE` 셋입니다.

---

## 13.5 전형적인 순서

```
ID                                          식별과 selftest
GEN COUNT=16384 TARGETS=0 VAL=12345 SEED=1  배경 만들기
POKE IDX=507 VAL=12345                      목표 심기
...
LOAD                                        DMA 적재
SET MODE=EQ A=12345 AUTO=1 BURST=0          조건 설정
SHOW                                        확인
RUN                                         단일 탐색
STAT                                        카운터 읽기
SET BURST=1                                 체크포인트로 전환
RUN
ENUM                                        전부 찾기
```

---

## 13.6 호스트 CLI의 세 트랜스포트

[`software/host/bbht_cli.py`](../../software/host/bbht_cli.py)가 같은 프로토콜을 세 가지
방식으로 말합니다.

| `--port` | 상대 | 쓰임 |
|---|---|---|
| `/dev/ttyUSB1` · `COM6` | 실제 보드 | 실측 |
| `mock` | 파이썬 모델 | 동작 확인. 수치 인용 금지 |
| `replay:<파일>` | RTL 시뮬 트랜스크립트 | 시뮬 응답을 같은 파서로 검증 |

`replay:`는 SoC 시뮬레이션 트랜스크립트를 실제 호스트 파서에 그대로 입력합니다. 이를 통해
응답 내용뿐 아니라 호스트가 해당 응답을 해석하는 과정까지 확인합니다
([15장 3층](15_검증_체계.md)).

`selftest`는 보드가 `ID`로 보고하는 상수 7개를 CSR 정본과 대조합니다.

```bash
python3 software/host/bbht_cli.py --port mock selftest
python3 software/host/bbht_cli.py --port replay:<트랜스크립트> -c ID -c RUN
```

### 보드에서 확인된 문제

| 증상 | 원인과 조치 |
|---|---|
| 포트를 열면 그 뒤로 에코조차 안 옴 | COM 포트 열 때 DTR/RTS가 SoC를 리셋합니다. 앱이 SRAM이미지뿐이라 다시 적재해야 합니다. `SerialTransport`가 열기 전에 둘을 내리도록 고쳤습니다 |
| Windows에서 스크립트·로그 파일이 한글 주석에서 죽음 | cp949로 열던 것을 UTF-8로 고쳤습니다 |

자세한 것은 [16장](16_보드_확인과_실측.md).
