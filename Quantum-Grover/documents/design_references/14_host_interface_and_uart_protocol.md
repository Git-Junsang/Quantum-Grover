# 14장. host interface와 UART protocol

> [← 13장 CSR register와 execution mode](13_csr_registers_and_execution_modes.md) · [index](index.md) · [15장 동작 과정과 cycle 구성 →](15_operation_sequence_and_cycle_breakdown.md)

---

이 장은 host 와 board 사이의 명령 규약의 source of truth입니다. board 쪽 implementation은
[`bbht_console/src/main.c`](../../hardware_bram/firmware/bbht_console/src/main.c),
host 쪽은 serial terminal이나 이 규약을 따르는 script면 되고, 저장소의 host CLI 는
[`software/host_fpga_develop/bbht_cli.py`](../../software/host_fpga_develop/bbht_cli.py)입니다. 같은 console source가 세
bitstream에 올라갑니다. board에 연결해 실제로 부리는 절차는 [17장](17_board_operation.md)에 있습니다.

---

## 14.1 ASCII line protocol을 고른 이유

이 경로로 오가는 것은 몇십 byte짜리 명령과 결과뿐입니다. binary frame이 빠르긴 하지만
여기서는 속도가 문제가 아니고, ASCII 로 얻는 것이 큽니다.

- serial terminal만으로 board를 부릴 수 있습니다.
- transcript가 그대로 실험 기록이자 regression 입력이 됩니다. SoC simulation transcript를 host CLI
  의 replay transport에 그대로 먹여 parsing할 수 있습니다([16장](16_verification_framework.md)).
- parsing이 어긋났는지 값이 틀렸는지가 눈으로 구분됩니다. bring-up 단계에서 이 차이가 며칠을
  좌우합니다.

data array는 이 길로 보내지 않습니다. 14-qubit dataset은 32 KB 이고 115200 8N1(byte당
10 bits)로 보내면 약 3초로, search 한 번보다 훨씬 깁니다. 그래서 data는 board 위 `GEN` 으로
만들거나 AHB DMA 로 넣고, UART 에는 명령과 결과만 흘립니다.

---

## 14.2 link 규약

| 항목 | 값 |
|---|---|
| baud rate | 115200 (SoC 50 MHz 에서 분주) |
| framing | 8N1 |
| flow control | 없음 |
| line ending | 보내는 쪽 `\n` 또는 `\r\n`, 받는 쪽 `\r\n` |
| encoding | ASCII |

응답을 다 받은 뒤에 다음 명령을 보냅니다. flow control이 없는 raw stream이라, board가 polling
loop에 들어가 있는 동안 명령을 밀어 넣으면 RX FIFO 가 넘칩니다. host script는 이것을
강제해야 합니다.

응답 한 덩어리는 반드시 `OK` 또는 `ERR` 로 끝납니다. data 줄이 먼저 나오고 마지막 줄이
종결자입니다.

console은 받은 글자를 그대로 되비춥니다(echo). 사람이 칠 때 필요한 것이고, script는 명령을
보내기 전에 입력 buffer를 비우면 영향이 없습니다. backspace(`BS` / `DEL`)를 받습니다.

---

## 14.3 명령

| 명령 | 뜻 |
|---|---|
| `HELP` | 명령 목록 |
| `ID` | firmware · hardware 식별. CSR base, number of states, clock, dataset state, platform |
| `SET K=V ...` | 설정 변경 |
| `SHOW` | 현재 설정 |
| `GEN ...` | board 위에서 dataset 생성 (`PRED=` 를 주면 predicate별) |
| `SUM` | board buffer의 FNV-1a hash와 지금 predicate의 number of solutions |
| `POKE IDX=i VAL=v` | 한 칸 수정 |
| `PEEK IDX=i` | 한 칸 읽기 (board buffer) |
| `LOAD` | buffer를 DMA 로 IP 에 load |
| `RUN` | single search |
| `ENUM` | enumeration |
| `STAT` | 마지막 실행의 counter와 telemetry |
| `REG` | CSR 전체 dump |

명령과 키 이름은 대소문자를 가리지 않습니다(내부에서 대문자로 바꿉니다). 숫자는 10진수가
기본이고 `0x` 접두사면 16진수, 앞의 `-` 는 음수입니다. 이 shell 덕분에 predicate나 조건을 바꾸려고
bitstream이나 ELF 를 다시 만들 필요가 없습니다.

### `SET` 의 키와 CSR 대응

| 키 | 값 | CSR |
|---|---|---|
| `MODE` | `LT` `GT` `EQ` `RANGE` | `CONTROL[3:2]` |
| `A` | signed 16-bit threshold | `THRESHOLD_A` |
| `B` | signed 16-bit 상한 (`RANGE` 전용) | `THRESHOLD_B` |
| `COUNT` | 유효 data 개수 1~16384 | `DATA_COUNT` |
| `CAP` | shot cap | `SHOT_CAP` |
| `SEEDJ` | Iteration-Count LFSR seed | `SEED_J` |
| `SEEDM` | Measurement PRNG seed | `SEED_MEAS` |
| `AUTO` | 0 number of iterations 수동 지정, 1 BBHT 자율 | `CONTROL[0]` |
| `BURST` | 0 Restart mode, 1 checkpoint 재사용 | `CONTROL[1]` |
| `J` | 수동 지정 number of iterations (0~127) | `J_TARGET` |
| `FAILLIM` | enumeration 에서 BBHT 전체 실패를 허용하는 횟수 1~15 | `ENUM_CFG[7:4]` |

threshold는 sign이 있습니다. `SET A=-777` 이 됩니다. sign을 흘리면 `LT` predicate의 절반이 조용히
죽습니다. `RANGE` 는 open interval이고 `B > A` 여야 합니다. 아니면 `ERR RANGE_NEEDS_B_GT_A`.

### `GEN` 의 키

| 키 | 기본값 | 뜻 |
|---|---|---|
| `COUNT` | 16384 | 만들 항목 수 |
| `SEED` | `0x5EED1234` | 배경 xorshift32 seed |
| `POS` | `0xA17E2026` (`PRED` 를 주면 predicate별 값) | solution 위치 seed |
| `TARGETS` | 1 | 심을 number of solutions |
| `VAL` | 12345 | solution 값 (`PRED` 없는 옛 형식, 곧 EQ) |
| `PRED` | 없음 | `LT` `GT` `EQ` `RANGE`. 주면 그 predicate로 정확히 `TARGETS` 개가 solution인 array를 만듦 |
| `A` / `B` | predicate별 값 | threshold. `RANGE` 는 `B` 까지 |

기본값은 board benchmark와 같은 seed입니다. 같은 seed면 같은 array가 나오므로 그 결과와 대조할
수 있습니다. 배경을 만들 때 solution 값과 같아지는 자리는 한 bit를 뒤집어 피하므로 `TARGETS` 로
심은 개수가 곧 number of solutions가 됩니다.

`PRED` 를 주면 두 가지가 달라집니다. 배경 값 가운데 predicate를 만족하는 것을 non-solution 쪽으로 접어
넣고(LT 이면 `A` 이상, GT 이면 `A` 이하, RANGE 이면 `B` 이상), solution 값은 solution 값 범위 안에서 따로
도는 xorshift32 로 흩뿌립니다. 그리고 `SET MODE/A/B/COUNT` 도 만든 predicate로 맞춰 둡니다. `A` ·
`B` · `POS` 를 안 주면 Predicate500 의 값을 씁니다.

| `PRED` | `A` | `B` | `POS` | solution 값 범위 |
|---|---|---|---|---|
| `LT` | −16384 | — | `0x17A02026` | [−32768, −16385] |
| `GT` | 16383 | — | `0x67A02026` | [16384, 32767] |
| `EQ` | 12345 | — | `0xA17E2026` | 12345 |
| `RANGE` | −4096 | 4096 | `0x3A4E2026` | [−4095, 4095] |

규칙의 source of truth는 `software/reference_model_develop/models/common/benchmark_dataset.py` 의 `generate_predicate_image` 이고,
firmware의 `bbht_console/src/bbht_dataset_gen.h` 가 같은 integer 연산을 합니다. 같은 인자면 byte
단위로 같은 array가 나옵니다(`make -C hardware_bram/sim console-gen` 이 20 datasets로 확인). `PRED=EQ` 는 옛 형식과 규칙이 같습니다.

`GEN` 이나 `POKE` 뒤에는 반드시 `LOAD` 를 해야 합니다. 안 하면 `ERR NOT_LOADED` 가 납니다.
board buffer만 바뀌고 IP 안의 array는 그대로이기 때문입니다.

### `SUM`

```
> SUM
STAT count=16384 fnv=0x44bb67d0 hits=4 pred=EQ a=12345 b=0 loaded=1
OK
```

`fnv` 는 buffer 앞 `count` 칸을 16-bit little-endian byte로 늘어놓은 FNV-1a 32 이고, `hits` 는
지금 `SET` 된 predicate로 센 number of solutions입니다. host는 32 KB 를 받아 오지 않고도 board가 만든 array가
reference model이 쓴 array와 같은지 이 두 값으로 확인합니다. ORCA 에서 몇백 ms 걸립니다.

---

## 14.4 응답

### 종결자

| 줄 | 뜻 |
|---|---|
| `OK` | 성공. 뒤에 `key=value` 가 붙을 수 있습니다 |
| `ERR <token>` | 실패. token이 이유입니다 |

### data 줄

| tag | 언제 | 예 |
|---|---|---|
| `HIT` | `RUN` 이 solution을 찾음 | `HIT idx=507 val=12345 trials=25 l=308 iters=70 cyc=30913 us=309 wall_us=314` |
| `MISS` | `RUN` 이 못 찾음 | `MISS reason=SHOT_CAP trials=100 l=... iters=... cyc=1200000 us=12000 wall_us=...` |
| `FOUND` | `ENUM` 이 solution 하나를 뱉음 | `FOUND idx=507 val=12345` |
| `END` | `ENUM` 종료 요약 | `END count=4 found=4 cyc=280494 us=2804` |
| `STAT` | `ID` · `PEEK` · `STAT` · `SUM` | `STAT trials=25 l_bbht=308 actual_iter=70 cyc=30913 us=309` |
| `CFG` | `SHOW` | `CFG mode=EQ a=12345 b=0 count=16384 cap=100` |
| `REG` | `REG` | `REG 0x024 = 0x0000080c` |
| `#` | 주석 · 경고 | `# amp_overflow (진단용, 결과는 유효)` |

`#` 로 시작하는 줄은 사람을 위한 것이고 parser가 무시해도 됩니다.

| field | 뜻 |
|---|---|
| `idx` | 찾은 index |
| `val` | 그 자리의 data 값 (board가 자기 buffer에서 읽어 붙임) |
| `trials` | number of shots |
| `l` | `REQUESTED_ITERATIONS` = requested iterations, 곧 shot마다 뽑은 number of iterations의 sum. algorithm 지표 |
| `iters` | `EXECUTED_ITERATIONS` = executed iterations. checkpoint가 줄이는 대상 |
| `cyc` | `CYCLE_COUNT`, `clk_accel`(100 MHz) 기준 |
| `us` | firmware가 `cyc` 를 100 으로 나눈 환산값. wall-clock time이 아님 |
| `wall_us` | board 실시간 clock(1 MHz tick)으로 `COMMAND` 를 쓰기 직전부터 polling이 DONE 을 본 순간까지 잰 wall-clock time |

`us` 와 `wall_us` 는 다릅니다. `us` 는 cycle 환산값이라 simulation과 board에서 같은 값이
나옵니다. `wall_us` 가 재는 시간 범위는 Board-Verified Build의 500-run board benchmark(`bbht_paper_bench`)와 같고, 2026-09-25 revision의
console부터 나옵니다. `MISS` 에도 같은 날부터 `l` 과 `iters` 가 붙습니다.

`ID` 는 2026-09-25 revision부터 `STAT platform=<RVX platform 이름> fw=<console revision>` 한 줄을 더 냅니다.
`bbht_grover_final` 면 final configuration, `bbht_grover_no_checkpoint_baseline` 면 No-Checkpoint Baseline,
`bbht_grover_dram` 이면 DRAM Variant bitstream이고, host 자동 test가 이것으로 돌릴 mode를
정합니다.

### `ERR` token

| token | 뜻 |
|---|---|
| `UNKNOWN_CMD` | 모르는 명령 |
| `BAD_KV` | `KEY=VALUE` 형식이 아니거나 모르는 키, parsing 실패 |
| `BAD_COUNT` | `COUNT` 가 1~16384 밖 |
| `BAD_INDEX` | index가 number of states(16,384) 이상 |
| `TOO_MANY_TARGETS` | `TARGETS > COUNT` |
| `RANGE_NEEDS_B_GT_A` | `RANGE` 인데 `B <= A` |
| `BAD_THRESHOLD` | `GEN` 의 solution 값 범위가 비었음 (`LT A=-32768`, `GT A=32767`, `RANGE` 에서 `B-A<2`, 16-bit 밖) |
| `TARGET_GUARD` | `GEN` 이 solution을 다 못 심음. 뒤에 `placed=n` |
| `NO_DATASET` | `LOAD` 인데 buffer가 비었음 |
| `NOT_LOADED` | `RUN` / `ENUM` 인데 아직 load 안 함 |
| `TIMEOUT` | polling 상한 초과 |
| `DMA_ERROR` | DMA 오류. 뒤에 `dma_status=0x..` |
| `STATUS_ERROR` | STATUS 에 치명 오류 bit. 뒤에 `status=0x..` |
| `BAD_ARG` | driver 인자 verification 실패 |
| `BUSY` | start 수락 조건 불충족 ([5장 5.6절](05_hardware_architecture_overview.md#56-시작-명령-수락-조건)) |
| `HOST_TIMEOUT` | board가 아니라 host 쪽 도구가 붙이는 token. board가 응답하지 않음 |

`MISS reason` 은 셋입니다.

| 값 | 뜻 |
|---|---|
| `SHOT_CAP` | shot cap 도달 |
| `BUDGET` | BBHT budget 도달 |
| `NONE` | 정상 종료했는데 solution이 없음 |

---

## 14.5 한 번 돌리는 전형적인 순서

```
> ID
STAT name=bbht_console csr_ver=0.9.8
STAT platform=bbht_grover_final fw=2026-09-25
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

두 `HIT` 줄의 수치는 같은 조건(같은 dataset seed · 같은 search seed)으로 2026-09-08 board benchmark
app이 낸 benchmark 값(solution이 1개인 첫 workload, Restart mode와 final configuration)을 옮긴 것이라 `wall_us` 는 뺐습니다.
console app 자체가 board에서 낸 응답은 [실험 15](../reports/15_revised_bus_interface_board_console.md)에 있습니다.

마지막 두 `RUN` 이 이 project의 주장을 그대로 보여 줍니다. `idx` 와 `l` 은 같고 `iters` 와
`cyc` 만 줄었습니다. 답이 같고 algorithm이 oracle에 던진 질의 수도 같은데 emulation 시간만
줄어든 것입니다. 셋 중 하나라도 어긋나면 개선이 아니라 bug입니다. 둘을 합쳐 "Grover iteration을
줄였다" 고 쓰면 틀린 말이 됩니다. 줄어든 것은 emulation 비용이지 oracle 질의 횟수가 아닙니다.

predicate별로 돌리려면 `GEN PRED=LT TARGETS=16` 처럼 `PRED` 를 줍니다. `SET MODE/A/B` 가 같이
맞춰지므로 곧바로 `LOAD` 와 `RUN` 을 하면 됩니다. 네 predicate × 500 workloads를 통째로 돌리는 것은
[18장](18_predicate500_automated_test.md)입니다.

---

## 14.6 host CLI 의 세 transport

`bbht_cli.py` 가 같은 protocol을 세 상대와 말합니다.

| `--port` | 상대 | 쓰임 |
|---|---|---|
| `/dev/ttyUSB1` · `COM6` | 실제 board | benchmark |
| `mock` | console 문법을 흉내 내는 Python model | 문법 연습 · 동작 확인. 수치 인용 금지 |
| `replay:<파일>` | RTL simulation이 낸 transcript | 실제 firmware 응답을 같은 parser로 verification |

```bash
python3 software/host_fpga_develop/bbht_cli.py --port /dev/ttyUSB1 --script exp.txt --log run.log
python3 software/host_fpga_develop/bbht_cli.py --port /dev/ttyUSB1 selftest
python3 software/host_fpga_develop/bbht_cli.py --port replay:<트랜스크립트> -c ID -c RUN
```

`selftest` 는 board가 `ID` 로 보고하는 constant 일곱 개를 CSR source of truth에서 생성한 값과 맞댑니다.
어긋나면 board에 구운 것과 저장소의 source of truth가 다르다는 뜻이니 굽기 전에 원인을 찾습니다.

`replay:` 는 transcript에 명령 echo(`> CMD`)가 있으면 그 경계로 응답을 자르고, 보낸 명령이
echo와 다르면 `ERR REPLAY_MISMATCH` 를 돌려줍니다. replay이므로 transcript에 있는 명령을 같은
순서로 보내야 합니다.

CLI 를 안 쓰고 직접 짤 때는 이 규약대로 한 줄 보내고 `OK` / `ERR` 을 받을 때까지 기다리는
loop이면 됩니다. Python이면 `software/reference_model_develop/common500/requirements.txt` 에 있는 `pyserial` 을 씁니다.

---

## 14.7 host가 지켜야 할 것

- 응답 대기: `OK` / `ERR` 를 받기 전에 다음 명령을 보내지 않습니다.
- timeout: `RUN` 은 최악의 경우 shot cap까지 돕니다. host timeout는 `SHOT_CAP` 과 짝을
  이뤄야 하고 임의로 고르는 값이 아닙니다.
- log와 결과가 같은 UART 를 씁니다. parser는 `#` 줄과 모르는 tag를 건너뛰어야 나중에 진단
  줄이 늘어도 깨지지 않습니다.
- clock을 hardcode하지 않습니다. `ID` 의 `accel_clk_hz` 로 cycle을 시간으로 바꾸거나 board가
  준 `us` field를 씁니다.
- port를 열 때 DTR/RTS 를 내립니다. 켜진 채 열면 SoC 가 reset되어 SRAM 에 올린 app이 사라집니다
  ([17장 17.8절](17_board_operation.md#178-잘-안-될-때)).

## 14.8 protocol을 늘릴 때

새 명령이나 새 field를 더하는 것은 안전합니다. parser가 모르는 tag를 건너뛰기 때문입니다.
바꾸면 안 되는 것은 셋입니다.

1. 응답 덩어리가 `OK` / `ERR` 로 끝난다는 규칙
2. 이미 있는 `key=` 이름의 뜻 (`l` 과 `iters` 를 뒤바꾸는 것 같은)
3. `ERR` token 이름

바꿔야 한다면 `ID` 의 `csr_ver` 를 올리고 host script가 그것을 보고 갈라지게 합니다.
