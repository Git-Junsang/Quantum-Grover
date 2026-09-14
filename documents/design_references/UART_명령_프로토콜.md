# UART 명령 프로토콜

> 담당: 통신·명령·시스템 (SJS) · 2026-09-02 작성 · 2026-09-09 갱신
> 보드 쪽 구현 `hardware_bram/firmware/bbht_console/src/main.c`.
> 호스트 쪽은 시리얼 터미널이나 이 규약을 따르는 스크립트면 됩니다. 호스트 CLI
> `software/bbht_cli.py` 는 2026-09-13 저장소에서 빠졌습니다 (커밋 `7d5455c` 에 있음).

---

## 1. 왜 ASCII 라인인가

이 경로로 오가는 것은 몇십 바이트짜리 명령과 결과뿐입니다. 바이너리 프레임이
빠르긴 하지만 여기서는 속도가 문제가 아니고, ASCII 로 얻는 것이 큽니다 —
터미널을 열어 손으로 쳐 볼 수 있고, 로그가 그대로 사람이 읽는 실험 기록이
되며, 무엇보다 **파싱이 어긋났는지 값이 틀렸는지가 눈으로 구분됩니다.**
브링업 단계에서 이 차이가 며칠을 좌우합니다.

**데이터 배열은 이 길로 안 갑니다.** Q14 데이터셋은 32 KB 이고 115200 8N1
(바이트당 10비트)로 보내면 약 3초입니다. 탐색 한 번이 그보다 훨씬 짧으므로,
배열을 넣는 데 탐색의 수백 배를 쓰게 됩니다. 그래서 데이터는 보드 위
`GEN` 으로 만들거나 AHB DMA 로 넣고, UART 에는 명령과 결과만 흘립니다.

---

## 2. 링크 규약

| 항목 | 값 |
|---|---|
| 보율 | 115200 |
| 프레이밍 | 8N1 |
| 흐름 제어 | **없음** |
| 줄 끝 | 보내는 쪽은 `\n` 또는 `\r\n`, 받는 쪽은 `\r\n` |
| 인코딩 | ASCII |

**응답을 다 받은 뒤에 다음 명령을 보냅니다.** 흐름 제어가 없는 원시
스트림이라, 보드가 폴링 루프에 들어가 있는 동안 명령을 밀어 넣으면
RX FIFO 가 넘칩니다. 호스트 스크립트를 짤 때 이것을 강제하십시오.

**응답 한 덩어리는 반드시 `OK` 또는 `ERR` 로 끝납니다.** 데이터 줄이
먼저 나오고 마지막 줄이 종결자입니다. 호스트는 그 줄을 보고 다음으로
넘어갑니다.

콘솔은 받은 글자를 그대로 되비춥니다(에코). 사람이 칠 때 필요한 것이고,
스크립트는 명령을 보내기 전에 입력 버퍼를 비우면 영향이 없습니다.
백스페이스(`BS` / `DEL`)를 받습니다.

---

## 3. 명령

| 명령 | 뜻 |
|---|---|
| `HELP` | 명령 목록 |
| `ID` | 펌웨어·하드웨어 식별. CSR base, N, 클럭, 데이터셋 상태 |
| `SET K=V ...` | 설정 변경 |
| `SHOW` | 현재 설정 |
| `GEN ...` | 보드 위에서 데이터셋 생성 |
| `POKE IDX=i VAL=v` | 한 칸 수정 |
| `PEEK IDX=i` | 한 칸 읽기 (보드 버퍼) |
| `LOAD` | 버퍼를 DMA 로 IP 에 적재 |
| `RUN` | 단일 탐색 |
| `ENUM` | 열거 |
| `STAT` | 마지막 실행의 카운터와 텔레메트리 |
| `REG` | CSR 전체 덤프 |

명령과 키 이름은 대소문자를 가리지 않습니다(내부에서 대문자로 바꿉니다).
숫자는 10진수 기본, `0x` 접두사면 16진수, 앞의 `-` 는 음수입니다.

### 3.1 `SET` 의 키

| 키 | 값 | CSR |
|---|---|---|
| `MODE` | `LT` `GT` `EQ` `RANGE` | `CONTROL[3:2]` |
| `A` | signed 16비트 임계값 | `THRESHOLD_A` |
| `B` | signed 16비트 상한 (`RANGE` 전용) | `THRESHOLD_B` |
| `COUNT` | 유효 데이터 개수 1~16384 | `DATA_COUNT` |
| `CAP` | shot 상한 | `SHOT_CAP` |
| `SEEDJ` | requested-j PRNG 시드 | `SEED_J` |
| `SEEDM` | 측정 PRNG 시드 | `SEED_MEAS` |
| `AUTO` | 0 = manual j, 1 = BBHT 자율 | `CONTROL[0]` |
| `BURST` | 0 = Normal, 1 = checkpoint 재사용 | `CONTROL[1]` |
| `J` | manual requested j (0~127) | `J_TARGET` |
| `FAILLIM` | 열거 실패 반복 한계 1~15 | `ENUM_CFG[7:4]` |

임계값은 **부호가 있습니다.** `SET A=-777` 이 됩니다. 부호를 흘리면
`LT` 술어의 절반이 조용히 죽습니다.

`RANGE` 는 열린구간이고 `B > A` 여야 합니다. 아니면 `ERR RANGE_NEEDS_B_GT_A`.

### 3.2 `GEN` 의 키

| 키 | 기본값 | 뜻 |
|---|---|---|
| `COUNT` | 16384 | 만들 항목 수 |
| `SEED` | `0x5EED1234` | 배경 xorshift32 시드 |
| `POS` | `0xA17E2026` | 목표 위치 시드 |
| `TARGETS` | 1 | 심을 목표 개수 |
| `VAL` | 12345 | 목표값 |

기본값은 보드 벤치마크(2026-09-01 · 2026-09-04)와 같은 시드입니다. 같은 시드면
같은 배열이 나오므로 그 결과와 대조할 수 있습니다 — 성능 인용의 정본은
K3/H3-E4-M2 인 2026-09-08 묶음입니다.

배경을 만들 때 목표값과 같아지는 자리는 한 비트를 뒤집어 피합니다. 그래야
`TARGETS` 로 심은 개수가 곧 정답 개수가 됩니다.

**`GEN` 이나 `POKE` 뒤에는 반드시 `LOAD` 를 해야 합니다.** 안 하면
`ERR NOT_LOADED` 가 납니다 — 보드 버퍼만 바뀌고 IP 안의 배열은 그대로이기
때문입니다.

---

## 4. 응답

### 4.1 종결자

| 줄 | 뜻 |
|---|---|
| `OK` | 성공. 뒤에 `key=value` 가 붙을 수 있습니다 |
| `ERR <토큰>` | 실패. 토큰이 이유입니다 |

### 4.2 데이터 줄

| 태그 | 언제 | 예 |
|---|---|---|
| `HIT` | `RUN` 이 해를 찾음 | `HIT idx=507 val=12345 trials=25 l=308 iters=70 cyc=30913 us=309` |
| `MISS` | `RUN` 이 못 찾음 | `MISS reason=SHOT_CAP trials=100 cyc=1200000 us=12000` |
| `FOUND` | `ENUM` 이 해 하나를 뱉음 | `FOUND idx=507 val=777` |
| `END` | `ENUM` 종료 요약 | `END count=3 found=3 cyc=89000 us=890` |
| `STAT` | `ID`, `PEEK`, `STAT` | `STAT trials=25 l_bbht=308 actual_iter=70 cyc=30913 us=309` |
| `CFG` | `SHOW` | `CFG mode=EQ a=12345 b=0 count=16384 cap=100` |
| `REG` | `REG` | `REG 0x024 = 0x0000080c` |
| `#` | 주석·경고 | `# amp_overflow (진단용, 결과는 유효)` |

`#` 로 시작하는 줄은 사람을 위한 것이고 파서가 무시해도 됩니다.

### 4.3 `ERR` 토큰

| 토큰 | 뜻 |
|---|---|
| `UNKNOWN_CMD` | 모르는 명령 |
| `BAD_KV` | `KEY=VALUE` 형식이 아니거나 모르는 키, 파싱 실패 |
| `BAD_COUNT` | `COUNT` 가 1~16384 밖 |
| `BAD_INDEX` | 인덱스가 N 이상 |
| `TOO_MANY_TARGETS` | `TARGETS > COUNT` |
| `RANGE_NEEDS_B_GT_A` | `RANGE` 인데 `B <= A` |
| `NO_DATASET` | `LOAD` 인데 버퍼가 비었음 |
| `NOT_LOADED` | `RUN`/`ENUM` 인데 아직 적재 안 함 |
| `TIMEOUT` | 폴링 상한 초과 |
| `DMA_ERROR` | DMA 오류. 뒤에 `dma_status=0x..` 가 붙습니다 |
| `STATUS_ERROR` | STATUS 에 치명 오류 비트. 뒤에 `status=0x..` |
| `BAD_ARG` | 드라이버 인자 검증 실패 |
| `BUSY` | 시작 조건 불충족 |
| `HOST_TIMEOUT` | **보드가 아니라 호스트 쪽 도구가 붙이는 토큰** (옛 CLI 관례). 보드가 응답 안 함 |

### 4.4 `MISS reason`

| 값 | 뜻 |
|---|---|
| `SHOT_CAP` | shot 상한 도달 |
| `BUDGET` | logical budget 도달 |
| `NONE` | 정상 종료했는데 해가 없음 |

---

## 5. 한 번 돌리는 전형적인 순서

```
> ID
STAT name=bbht_console csr_ver=0.9.8
STAT csr_base=0xe2020000 q_bits=14 n_entries=16384 fifo_depth=256
STAT accel_clk_hz=100000000 sram_base=0xe0000000 sram_last=0xe001ffff
STAT dataset_addr=0xe0000abc dataset_count=0 loaded=0
OK

> GEN COUNT=16384 TARGETS=1 VAL=12345
OK count=16384 targets=1 val=12345

> LOAD
OK loaded=16384 addr=0xe0000abc

> SET MODE=EQ A=12345 AUTO=1 BURST=0 SEEDJ=0x7b1dcdaf SEEDM=0x24370df2
OK

> RUN
HIT idx=507 val=12345 trials=25 l=308 iters=308 cyc=351394 us=3513
OK

> SET BURST=1
OK

> RUN
HIT idx=507 val=12345 trials=25 l=308 iters=70 cyc=30913 us=309
OK
```

두 `HIT` 줄의 수치는 같은 조건(같은 데이터셋 시드 · 같은 탐색 시드)으로 2026-09-08 보드
벤치 앱이 낸 실측값(M = 1 첫 워크로드, Normal 과 K3/H3-E4-M2)을 옮긴 것입니다. 콘솔 앱
자체는 아직 보드에서 돌려 보지 않았습니다.

마지막 두 `RUN` 이 이 프로젝트의 주장을 그대로 보여 줍니다. **`idx` 와 `l` 은
같고 `iters` 와 `cyc` 만 줄었습니다.** 답이 같고 알고리즘이 오라클에 던진
질의 수도 같은데 에뮬레이션 시간만 줄어든 것입니다. 셋 중 하나라도
어긋나면 그건 개선이 아니라 버그입니다.

---

## 6. 호스트가 지켜야 할 것

**응답 대기.** `OK`/`ERR` 를 받기 전에 다음 명령을 보내지 마십시오.

**타임아웃.** `RUN` 은 최악의 경우 shot 상한까지 돕니다. 호스트 타임아웃은
`SHOT_CAP` 과 짝을 이뤄야 하고, 임의로 고르는 값이 아닙니다. 옛 CLI 는 기본
30초였습니다.

**로그와 결과가 같은 UART 를 씁니다.** 콘솔은 `#` 로 시작하는 줄에만
사람용 메시지를 냅니다. 파서는 그 줄을 무시하고, 알 수 없는 태그도
건너뛰어야 합니다 — 나중에 진단 줄이 늘어도 안 깨지게.

**클럭을 하드코딩하지 마십시오.** `ID` 응답의 `accel_clk_hz` 를 읽어
사이클을 시간으로 바꾸십시오. 보드 쪽 `us` 필드를 그냥 쓰는 것이 제일 안전합니다.

---

## 7. 프로토콜을 늘릴 때

새 명령이나 새 필드를 더하는 것은 안전합니다 — 파서가 모르는 태그를
건너뛰기 때문입니다. **바꾸면 안 되는 것**은 셋입니다.

1. 응답 덩어리가 `OK`/`ERR` 로 끝난다는 규칙
2. 이미 있는 `key=` 이름의 뜻 (`l` 과 `iters` 를 뒤바꾸는 것 같은)
3. `ERR` 토큰 이름

바꿔야 한다면 `ID` 의 `csr_ver` 를 올리고 호스트 스크립트가 그것을 보고
갈라지게 하십시오.
