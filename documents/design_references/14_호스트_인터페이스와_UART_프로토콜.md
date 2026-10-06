# 14장. 호스트 인터페이스와 UART 프로토콜

> [← 13장 CSR 레지스터와 실행 모드](13_CSR_레지스터와_실행_모드.md) · [문서 지도](00_문서_지도.md) · [15장 동작 과정과 사이클 구성 →](15_동작_과정과_사이클_구성.md)

---

이 장은 호스트 PC 와 보드 사이의 명령 규약의 정본입니다. 보드 쪽 구현은
[`bbht_console/src/main.c`](../../hardware_bram/firmware/bbht_console/src/main.c),
호스트 쪽은 시리얼 터미널이나 이 규약을 따르는 스크립트면 되고, 저장소의 호스트 CLI 는
[`software/host/bbht_cli.py`](../../software/host/bbht_cli.py)입니다. 같은 콘솔 소스가 세
비트스트림에 올라갑니다. 보드에 연결해 실제로 부리는 절차는 [17장](17_보드_운용.md)에 있습니다.

---

## 14.1 ASCII 라인 프로토콜을 고른 이유

이 경로로 오가는 것은 몇십 바이트짜리 명령과 결과뿐입니다. 바이너리 프레임이 빠르긴 하지만
여기서는 속도가 문제가 아니고, ASCII 로 얻는 것이 큽니다.

- 시리얼 터미널만으로 보드를 부릴 수 있습니다.
- 트랜스크립트가 그대로 실험 기록이자 회귀 입력이 됩니다. SoC 시뮬 트랜스크립트를 호스트 CLI
  의 재생 트랜스포트에 그대로 먹여 파싱할 수 있습니다([16장](16_검증_체계.md)).
- 파싱이 어긋났는지 값이 틀렸는지가 눈으로 구분됩니다. 브링업 단계에서 이 차이가 며칠을
  좌우합니다.

데이터 배열은 이 길로 보내지 않습니다. Q14 데이터셋은 32 KB 이고 115200 8N1(바이트당
10비트)로 보내면 약 3초로, 탐색 한 번보다 훨씬 깁니다. 그래서 데이터는 보드 위 `GEN` 으로
만들거나 AHB DMA 로 넣고, UART 에는 명령과 결과만 흘립니다.

---

## 14.2 링크 규약

| 항목 | 값 |
|---|---|
| 보율 | 115200 (SoC 50 MHz 에서 분주) |
| 프레이밍 | 8N1 |
| 흐름 제어 | 없음 |
| 줄 끝 | 보내는 쪽 `\n` 또는 `\r\n`, 받는 쪽 `\r\n` |
| 인코딩 | ASCII |

응답을 다 받은 뒤에 다음 명령을 보냅니다. 흐름 제어가 없는 원시 스트림이라, 보드가 폴링
루프에 들어가 있는 동안 명령을 밀어 넣으면 RX FIFO 가 넘칩니다. 호스트 스크립트는 이것을
강제해야 합니다.

응답 한 덩어리는 반드시 `OK` 또는 `ERR` 로 끝납니다. 데이터 줄이 먼저 나오고 마지막 줄이
종결자입니다.

콘솔은 받은 글자를 그대로 되비춥니다(에코). 사람이 칠 때 필요한 것이고, 스크립트는 명령을
보내기 전에 입력 버퍼를 비우면 영향이 없습니다. 백스페이스(`BS` / `DEL`)를 받습니다.

---

## 14.3 명령

| 명령 | 뜻 |
|---|---|
| `HELP` | 명령 목록 |
| `ID` | 펌웨어 · 하드웨어 식별. CSR base, N, 클럭, 데이터셋 상태, 플랫폼 |
| `SET K=V ...` | 설정 변경 |
| `SHOW` | 현재 설정 |
| `GEN ...` | 보드 위에서 데이터셋 생성 (`PRED=` 를 주면 술어별) |
| `SUM` | 보드 버퍼의 FNV-1a 해시와 지금 술어의 정답 수 |
| `POKE IDX=i VAL=v` | 한 칸 수정 |
| `PEEK IDX=i` | 한 칸 읽기 (보드 버퍼) |
| `LOAD` | 버퍼를 DMA 로 IP 에 적재 |
| `RUN` | 단일 탐색 |
| `ENUM` | 열거 |
| `STAT` | 마지막 실행의 카운터와 텔레메트리 |
| `REG` | CSR 전체 덤프 |

명령과 키 이름은 대소문자를 가리지 않습니다(내부에서 대문자로 바꿉니다). 숫자는 10진수가
기본이고 `0x` 접두사면 16진수, 앞의 `-` 는 음수입니다. 이 셸 덕분에 술어나 조건을 바꾸려고
비트스트림이나 ELF 를 다시 만들 필요가 없습니다.

### `SET` 의 키와 CSR 대응

| 키 | 값 | CSR |
|---|---|---|
| `MODE` | `LT` `GT` `EQ` `RANGE` | `CONTROL[3:2]` |
| `A` | signed 16비트 임계값 | `THRESHOLD_A` |
| `B` | signed 16비트 상한 (`RANGE` 전용) | `THRESHOLD_B` |
| `COUNT` | 유효 데이터 개수 1~16384 | `DATA_COUNT` |
| `CAP` | 샷 상한 | `SHOT_CAP` |
| `SEEDJ` | requested-j PRNG 시드 | `SEED_J` |
| `SEEDM` | 측정 PRNG 시드 | `SEED_MEAS` |
| `AUTO` | 0 수동 `j`, 1 BBHT 자율 | `CONTROL[0]` |
| `BURST` | 0 Normal, 1 체크포인트 재사용 | `CONTROL[1]` |
| `J` | 수동 `j` (0~127) | `J_TARGET` |
| `FAILLIM` | 열거 실패 반복 한계 1~15 | `ENUM_CFG[7:4]` |

임계값은 부호가 있습니다. `SET A=-777` 이 됩니다. 부호를 흘리면 `LT` 술어의 절반이 조용히
죽습니다. `RANGE` 는 열린구간이고 `B > A` 여야 합니다. 아니면 `ERR RANGE_NEEDS_B_GT_A`.

### `GEN` 의 키

| 키 | 기본값 | 뜻 |
|---|---|---|
| `COUNT` | 16384 | 만들 항목 수 |
| `SEED` | `0x5EED1234` | 배경 xorshift32 시드 |
| `POS` | `0xA17E2026` (`PRED` 를 주면 술어별 값) | 목표 위치 시드 |
| `TARGETS` | 1 | 심을 목표 개수 |
| `VAL` | 12345 | 목표값 (`PRED` 없는 옛 형식, 곧 EQ) |
| `PRED` | 없음 | `LT` `GT` `EQ` `RANGE`. 주면 그 술어로 정확히 `TARGETS` 개가 정답인 배열을 만듦 |
| `A` / `B` | 술어별 값 | 임계값. `RANGE` 는 `B` 까지 |

기본값은 보드 벤치마크와 같은 시드입니다. 같은 시드면 같은 배열이 나오므로 그 결과와 대조할
수 있습니다. 배경을 만들 때 목표값과 같아지는 자리는 한 비트를 뒤집어 피하므로 `TARGETS` 로
심은 개수가 곧 정답 개수가 됩니다.

`PRED` 를 주면 두 가지가 달라집니다. 배경 값 가운데 술어를 만족하는 것을 비정답 쪽으로 접어
넣고(LT 이면 `A` 이상, GT 이면 `A` 이하, RANGE 이면 `B` 이상), 목표 값은 정답 구간 안에서 따로
도는 xorshift32 로 흩뿌립니다. 그리고 `SET MODE/A/B/COUNT` 도 만든 술어로 맞춰 둡니다. `A` ·
`B` · `POS` 를 안 주면 Predicate500 의 값을 씁니다.

| `PRED` | `A` | `B` | `POS` | 정답 값 구간 |
|---|---|---|---|---|
| `LT` | −16384 | — | `0x17A02026` | [−32768, −16385] |
| `GT` | 16383 | — | `0x67A02026` | [16384, 32767] |
| `EQ` | 12345 | — | `0xA17E2026` | 12345 |
| `RANGE` | −4096 | 4096 | `0x3A4E2026` | [−4095, 4095] |

규칙의 정본은 `software/models/common/benchmark_dataset.py` 의 `generate_predicate_image` 이고,
펌웨어의 `bbht_console/src/bbht_dataset_gen.h` 가 같은 정수 연산을 합니다. 같은 인자면 바이트
단위로 같은 배열이 나옵니다(`make -C hardware_bram/sim console-gen` 이 20개
데이터셋으로 확인). `PRED=EQ` 는 옛 형식과 규칙이 같습니다.

`GEN` 이나 `POKE` 뒤에는 반드시 `LOAD` 를 해야 합니다. 안 하면 `ERR NOT_LOADED` 가 납니다.
보드 버퍼만 바뀌고 IP 안의 배열은 그대로이기 때문입니다.

### `SUM`

```
> SUM
STAT count=16384 fnv=0x44bb67d0 hits=4 pred=EQ a=12345 b=0 loaded=1
OK
```

`fnv` 는 버퍼 앞 `count` 칸을 16비트 little-endian 바이트로 늘어놓은 FNV-1a 32 이고, `hits` 는
지금 `SET` 된 술어로 센 정답 수입니다. 호스트는 32 KB 를 받아 오지 않고도 보드가 만든 배열이
기준모델이 쓴 배열과 같은지 이 두 값으로 확인합니다. ORCA 에서 몇백 ms 걸립니다.

---

## 14.4 응답

### 종결자

| 줄 | 뜻 |
|---|---|
| `OK` | 성공. 뒤에 `key=value` 가 붙을 수 있습니다 |
| `ERR <토큰>` | 실패. 토큰이 이유입니다 |

### 데이터 줄

| 태그 | 언제 | 예 |
|---|---|---|
| `HIT` | `RUN` 이 해를 찾음 | `HIT idx=507 val=12345 trials=25 l=308 iters=70 cyc=30913 us=309 wall_us=314` |
| `MISS` | `RUN` 이 못 찾음 | `MISS reason=SHOT_CAP trials=100 l=... iters=... cyc=1200000 us=12000 wall_us=...` |
| `FOUND` | `ENUM` 이 해 하나를 뱉음 | `FOUND idx=507 val=12345` |
| `END` | `ENUM` 종료 요약 | `END count=4 found=4 cyc=280494 us=2804` |
| `STAT` | `ID` · `PEEK` · `STAT` · `SUM` | `STAT trials=25 l_bbht=308 actual_iter=70 cyc=30913 us=309` |
| `CFG` | `SHOW` | `CFG mode=EQ a=12345 b=0 count=16384 cap=100` |
| `REG` | `REG` | `REG 0x024 = 0x0000080c` |
| `#` | 주석 · 경고 | `# amp_overflow (진단용, 결과는 유효)` |

`#` 로 시작하는 줄은 사람을 위한 것이고 파서가 무시해도 됩니다.

| 필드 | 뜻 |
|---|---|
| `idx` | 찾은 인덱스 |
| `val` | 그 자리의 데이터 값 (보드가 자기 버퍼에서 읽어 붙임) |
| `trials` | 논리 시도 수 |
| `l` | `L_BBHT` = Σ requested j. 알고리즘 지표 |
| `iters` | `ACTUAL_ITER` = 물리 Grover 반복. 체크포인트가 줄이는 대상 |
| `cyc` | `CYCLE_COUNT`, `clk_accel`(100 MHz) 기준 |
| `us` | 펌웨어가 `cyc` 를 100 으로 나눈 환산값. 실경과 시간이 아님 |
| `wall_us` | 보드 실시간 클럭(1 MHz 틱)으로 `COMMAND` 를 쓰기 직전부터 폴링이 DONE 을 본 순간까지 잰 실경과 시간 |

`us` 와 `wall_us` 는 다릅니다. `us` 는 사이클 환산값이라 시뮬레이션과 보드에서 같은 값이
나옵니다. `wall_us` 가 재는 구간은 보드 500런 정본(`bbht_paper_bench`)과 같고, 2026-09-25 판
콘솔부터 나옵니다. `MISS` 에도 같은 날부터 `l` 과 `iters` 가 붙습니다.

`ID` 는 2026-09-25 판부터 `STAT platform=<RVX 플랫폼 이름> fw=<콘솔 판>` 한 줄을 더 냅니다.
`bbht_grover_upgrade` 면 체크포인트 판, `bbht_grover_nocheckpoint` 면 체크포인트 없는 판,
`bbht_grover_dram` 이면 DRAM 갈래 비트스트림이고, 호스트 자동 테스트가 이것으로 돌릴 모드를
정합니다.

### `ERR` 토큰

| 토큰 | 뜻 |
|---|---|
| `UNKNOWN_CMD` | 모르는 명령 |
| `BAD_KV` | `KEY=VALUE` 형식이 아니거나 모르는 키, 파싱 실패 |
| `BAD_COUNT` | `COUNT` 가 1~16384 밖 |
| `BAD_INDEX` | 인덱스가 N 이상 |
| `TOO_MANY_TARGETS` | `TARGETS > COUNT` |
| `RANGE_NEEDS_B_GT_A` | `RANGE` 인데 `B <= A` |
| `BAD_THRESHOLD` | `GEN` 의 목표 구간이 비었음 (`LT A=-32768`, `GT A=32767`, `RANGE` 에서 `B-A<2`, 16비트 밖) |
| `TARGET_GUARD` | `GEN` 이 목표를 다 못 심음. 뒤에 `placed=n` |
| `NO_DATASET` | `LOAD` 인데 버퍼가 비었음 |
| `NOT_LOADED` | `RUN` / `ENUM` 인데 아직 적재 안 함 |
| `TIMEOUT` | 폴링 상한 초과 |
| `DMA_ERROR` | DMA 오류. 뒤에 `dma_status=0x..` |
| `STATUS_ERROR` | STATUS 에 치명 오류 비트. 뒤에 `status=0x..` |
| `BAD_ARG` | 드라이버 인자 검증 실패 |
| `BUSY` | start 수락 조건 불충족 ([5장 5.6절](05_하드웨어_아키텍처_개요.md#56-시작-명령-수락-조건)) |
| `HOST_TIMEOUT` | 보드가 아니라 호스트 쪽 도구가 붙이는 토큰. 보드가 응답하지 않음 |

`MISS reason` 은 셋입니다.

| 값 | 뜻 |
|---|---|
| `SHOT_CAP` | 샷 상한 도달 |
| `BUDGET` | 논리 예산 도달 |
| `NONE` | 정상 종료했는데 해가 없음 |

---

## 14.5 한 번 돌리는 전형적인 순서

```
> ID
STAT name=bbht_console csr_ver=0.9.8
STAT platform=bbht_grover_upgrade fw=2026-09-25
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

두 `HIT` 줄의 수치는 같은 조건(같은 데이터셋 시드 · 같은 탐색 시드)으로 2026-09-08 보드 벤치
앱이 낸 실측값(M = 1 첫 워크로드, Normal 과 K3/H3-E4-M2)을 옮긴 것이라 `wall_us` 는 뺐습니다.
콘솔 앱 자체가 보드에서 낸 응답은 [18장 18.3절](18_보드_확인과_실측.md)에 있습니다.

마지막 두 `RUN` 이 이 프로젝트의 주장을 그대로 보여 줍니다. `idx` 와 `l` 은 같고 `iters` 와
`cyc` 만 줄었습니다. 답이 같고 알고리즘이 오라클에 던진 질의 수도 같은데 에뮬레이션 시간만
줄어든 것입니다. 셋 중 하나라도 어긋나면 개선이 아니라 버그입니다. 둘을 합쳐 "그로버 반복을
줄였다" 고 쓰면 틀린 말이 됩니다. 줄어든 것은 에뮬레이션 비용이지 오라클 질의 횟수가 아닙니다.

술어별로 돌리려면 `GEN PRED=LT TARGETS=16` 처럼 `PRED` 를 줍니다. `SET MODE/A/B` 가 같이
맞춰지므로 곧바로 `LOAD` 와 `RUN` 을 하면 됩니다. 네 술어 × 500 워크로드를 통째로 돌리는 것은
[19장](19_Predicate500_자동_테스트.md)입니다.

---

## 14.6 호스트 CLI 의 세 트랜스포트

`bbht_cli.py` 가 같은 프로토콜을 세 상대와 말합니다.

| `--port` | 상대 | 쓰임 |
|---|---|---|
| `/dev/ttyUSB1` · `COM6` | 실제 보드 | 실측 |
| `mock` | 콘솔 문법을 흉내 내는 파이썬 모델 | 문법 연습 · 동작 확인. 수치 인용 금지 |
| `replay:<파일>` | RTL 시뮬이 낸 트랜스크립트 | 실제 펌웨어 응답을 같은 파서로 검증 |

```bash
python3 software/host/bbht_cli.py --port /dev/ttyUSB1 --script exp.txt --log run.log
python3 software/host/bbht_cli.py --port /dev/ttyUSB1 selftest
python3 software/host/bbht_cli.py --port replay:<트랜스크립트> -c ID -c RUN
```

`selftest` 는 보드가 `ID` 로 보고하는 상수 일곱 개를 CSR 정본에서 생성한 값과 맞댑니다.
어긋나면 보드에 구운 것과 저장소 정본이 다르다는 뜻이니 굽기 전에 원인을 찾습니다.

`replay:` 는 트랜스크립트에 명령 에코(`> CMD`)가 있으면 그 경계로 응답을 자르고, 보낸 명령이
에코와 다르면 `ERR REPLAY_MISMATCH` 를 돌려줍니다. 재생이므로 트랜스크립트에 있는 명령을 같은
순서로 보내야 합니다.

CLI 를 안 쓰고 직접 짤 때는 이 규약대로 한 줄 보내고 `OK` / `ERR` 을 받을 때까지 기다리는
루프면 됩니다. 파이썬이면 `software/requirements.txt` 에 있는 `pyserial` 을 씁니다.

---

## 14.7 호스트가 지켜야 할 것

- 응답 대기: `OK` / `ERR` 를 받기 전에 다음 명령을 보내지 않습니다.
- 타임아웃: `RUN` 은 최악의 경우 샷 상한까지 돕니다. 호스트 타임아웃은 `SHOT_CAP` 과 짝을
  이뤄야 하고 임의로 고르는 값이 아닙니다.
- 로그와 결과가 같은 UART 를 씁니다. 파서는 `#` 줄과 모르는 태그를 건너뛰어야 나중에 진단
  줄이 늘어도 깨지지 않습니다.
- 클럭을 하드코딩하지 않습니다. `ID` 의 `accel_clk_hz` 로 사이클을 시간으로 바꾸거나 보드가
  준 `us` 필드를 씁니다.
- 포트를 열 때 DTR/RTS 를 내립니다. 켜진 채 열면 SoC 가 리셋되어 SRAM 에 올린 앱이 사라집니다
  ([17장 17.8절](17_보드_운용.md#178-잘-안-될-때)).

## 14.8 프로토콜을 늘릴 때

새 명령이나 새 필드를 더하는 것은 안전합니다. 파서가 모르는 태그를 건너뛰기 때문입니다.
바꾸면 안 되는 것은 셋입니다.

1. 응답 덩어리가 `OK` / `ERR` 로 끝난다는 규칙
2. 이미 있는 `key=` 이름의 뜻 (`l` 과 `iters` 를 뒤바꾸는 것 같은)
3. `ERR` 토큰 이름

바꿔야 한다면 `ID` 의 `csr_ver` 를 올리고 호스트 스크립트가 그것을 보고 갈라지게 합니다.
