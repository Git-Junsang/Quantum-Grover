# 19장. Predicate500 자동 테스트

> [← 18장 보드 확인과 실측](18_보드_확인과_실측.md) · [문서 지도](00_문서_지도.md) · [20장 합성 · 구현 · 비트스트림 →](20_합성_구현_비트스트림.md)

---

보드를 연결해 두고 명령 하나로 LT · GT · EQ · RANGE 각각 500 워크로드를 돌려 SW 기준모델과
맞대고 엑셀로 남기는 프로그램입니다. 호스트 프로그램은
[`software/host/bbht_predicate500.py`](../../software/host/bbht_predicate500.py), 보드 앱은
`bbht_console`(2026-09-25 판), 기댓값은 `software/experiments/predicate500_benchmark/` 입니다.
세 비트스트림 모두에서 돕니다.

---

## 19.1 왜 필요한가

보드 500런(2026-09-08)과 SW Common500 은 모두 "12345 와 같은가" 한 술어를 500 워크로드에
걸었습니다. LT · GT · RANGE 는 RTL 회귀에서 몇 건만 돌았습니다. 설계는 네 술어를 같은
비교기(`grover_predicate`)로 오라클 · 측정 검증 · 열거에 똑같이 쓰지만, 그것을 같은 규모로
확인한 근거가 없었습니다.

Predicate500 은 Common500 과 같은 모양(정답 수 M = 1/4/16/64/256 × 공식 시드 100쌍)을 네 술어에
각각 겁니다. 2,000 워크로드이고, EQ 500개는 Common500 과 데이터셋 · 시드가 바이트 단위로
같습니다.

---

## 19.2 워크로드

| 술어 | 임계값 | 정답 값 구간 | 위치 시드 |
|---|---|---|---|
| LT | A = −16384 | [−32768, −16385] | `0x17A02026` |
| GT | A = 16383 | [16384, 32767] | `0x67A02026` |
| EQ | A = 12345 | 12345 | `0xA17E2026` (공식) |
| RANGE | A = −4096, B = 4096 | [−4095, 4095] (열린구간) | `0x3A4E2026` |

데이터셋은 16,384칸 전부 유효(`DATA_COUNT = 16384`)이고 배경 시드는 공식 벤치와 같은
`0x5EED1234` 입니다. 만드는 규칙은 둘입니다.

- 배경: xorshift32 로 16비트 값을 차례로 뽑되, 술어를 만족하는 값은 비정답 쪽으로 접어 넣습니다.
  LT 이면 `A` 이상으로, GT 이면 `A` 이하로, RANGE 이면 `B` 이상으로 옮기므로 배경에는 정답이
  하나도 없습니다.
- 목표: 위치 시드로 칸을 뽑아(이미 목표인 칸은 건너뜀) M 개를 심습니다. 값은 EQ 이면 `A`, 나머지는
  따로 도는 xorshift32 로 정답 구간 안에 흩뿌립니다. 그래서 LT 의 정답은 −32768 부터 −16385 까지
  여러 값에 걸쳐 있고 비교기의 양 끝 근처가 같이 시험됩니다.

M 이 커질 때 앞의 목표가 그대로 남습니다(1 ⊂ 4 ⊂ 16 ⊂ 64 ⊂ 256). 공식 벤치와 같은 성질입니다.

규칙의 정본은 `benchmark_dataset.py` 의 `generate_predicate_image` 이고, 보드 펌웨어의 `GEN PRED=`
가 같은 정수 연산을 합니다([14장 14.3절](14_호스트_인터페이스와_UART_프로토콜.md#143-명령)). 그래서
데이터셋 32 KB 를 UART 로 보내지 않습니다. 보드가 `GEN` 으로 직접 만들고, 호스트는 `SUM` 이
돌려주는 FNV-1a 해시와 정답 수만 기댓값과 맞댑니다.

---

## 19.3 기댓값

```bash
python3 software/experiments/predicate500_benchmark/run_predicate500_golden.py   # 30초쯤
```

Q1.22 bit-exact 기준모델이 2,000 워크로드를 셋 모드로 돌려 `expected/` 에 두 파일을 씁니다
([4장 4.4절](04_소프트웨어_기준모델과_정답_벡터.md#44-predicate500-기댓값)). 저장소에 커밋해
두었으므로 호스트 PC 에는 numpy 가 필요 없습니다.

| 파일 | 내용 |
|---|---|
| `predicate500_expected.csv` | 워크로드 2,000행. `result_index` `result_value` `trial_count` `L_BBHT` 와 물리 반복 넷 |
| `predicate500_datasets.csv` | 데이터셋 20개. 보드에 보낼 `GEN` 명령, FNV-1a, sha256 |

| 물리 반복 열 | 무엇과 맞대나 |
|---|---|
| `actual_iter_normal` | 체크포인트 판 NORMAL, 체크포인트 없는 판 (`L_BBHT` 와 같음) |
| `actual_iter_k3h3` | 체크포인트 판 CKPT (K3/H3-E4-M2) |
| `actual_iter_dram_all_j` | 탐색마다 DRAM 표를 비운 DRAM 갈래 (참고용) |
| `actual_iter_dram_session` | 데이터셋 하나를 적재한 뒤 시드를 차례로 돌며 DRAM 표를 이어 쓴 DRAM 갈래. 보드 · RTL 은 이 열과 맞아야 함 |

DRAM 표는 적재나 술어 변경 때만 버려지므로 DRAM 갈래는 세션 열과 맞대야 합니다. EQ 500행은
보드 500런 실측(Normal, M2)과 `result_index` · `trial_count` · `L_BBHT` · 물리 반복이 모두
500/500 같습니다. 기댓값이 보드 정본과 같은 계산을 한다는 확인입니다.

---

## 19.4 보드에 올리기 전에 확인한 것

세 판의 RTL 과 SoC RTL 시뮬(실제 RISC-V 가 콘솔을 돌림)에서 전부 기댓값과 맞았습니다. 표는
[16장 16.9절](16_검증_체계.md#169-네-술어와-다른-두-판)에 있습니다. 체크포인트 판 RTL 벤치의
EQ 1,000 실행은 기존 bench500 근거(보드 M2 와 사이클까지 500/500)와 사이클까지 1,000/1,000
같아서, 새 하네스도 믿을 만하다는 것을 함께 확인했습니다.

보드 실행은 2026-10-04 에 세 판 모두 마쳤고, 8,000 실행이 전부 기댓값과 맞았습니다. 결과와
판 사이 비교는 [18장 18.4절](18_보드_확인과_실측.md#184-2026-10-04-세-판의-predicate500)에 있습니다.

---

## 19.5 보드에서 돌리는 법

비트스트림과 콘솔 앱은 [17장](17_보드_운용.md) 절차대로 올립니다. 콘솔은 2026-09-25 판이어야
합니다. `GEN PRED` · `SUM` · `wall_us` · `ID` 의 `platform=` 이 이 판에서 생겼고, 옛 판이면
프로그램이 첫 `ID` 에서 알려 주고 멈춥니다. 호스트 PC 에는 `pip install pyserial openpyxl` 이
필요합니다.

```bash
python3 software/host/bbht_predicate500.py --port /dev/ttyUSB1        # Linux / WSL
python3 software/host/bbht_predicate500.py --port COM4                # Windows
```

프로그램이 하는 일은 이 순서입니다.

1. `ID` 로 플랫폼과 콘솔 판을 확인합니다. `bbht_grover_upgrade` 면 NORMAL 과 CKPT 를 같은 시드로
   짝지어 4,000 실행, `bbht_grover_nocheckpoint` 와 `bbht_grover_dram` 이면 NORMAL 만 2,000
   실행입니다. 물리 반복은 체크포인트 없는 판이 `actual_iter_normal`, DRAM 갈래가
   `actual_iter_dram_session` 열과 맞댑니다.
2. 술어 × M 마다 `GEN PRED=...` → `SUM` 으로 FNV 와 정답 수 확인 → `LOAD` → `SET`
3. 시드 100쌍마다 `SET BURST=.. SEEDJ=.. SEEDM=..` → `RUN`, 결과를 기댓값과 맞댐
4. 실행마다 CSV 에 한 줄씩 바로 쓰고, 끝나면 엑셀을 만들고 터미널에 요약과 판정을 찍음

| 인자 | 뜻 |
|---|---|
| `--predicates EQ` | 술어 일부만 (`LT,GT` 처럼 쉼표) |
| `--targets 1,4` · `--seeds 10` | M 이나 시드 일부만 (시험용) |
| `--modes normal` | 체크포인트 판에서도 NORMAL 만 |
| `--out 경로.xlsx` | 결과 파일. 안 주면 현재 폴더에 `predicate500_<platform>_<시각>.xlsx` |
| `--resume` | `--out` 의 CSV 가 있으면 끝난 데이터셋은 건너뜀 |
| `--log 파일` | 주고받은 줄 전부 기록 |
| `--timeout 60` | 명령 하나의 응답 대기 상한(초) |

걸리는 시간은 UART 왕복이 대부분입니다. 실행 하나가 명령 둘(SET, RUN)이고 응답이 짧아서
4,000 실행이면 수 분 정도로 예상합니다. 보드에서 잰 값은 아직 없습니다.

---

## 19.6 엑셀 결과

| 시트 | 내용 |
|---|---|
| `요약` | 술어 × 모드마다 실행 수, 축별 일치 수, 전부 일치 수, 물리 반복 · 사이클 · wall_us 합. 체크포인트 판이면 NORMAL/CKPT 배수 |
| `M별 요약` | 같은 것을 M 별로 |
| `실행별` | 실행 한 줄씩. 보드 값, 기댓값, 축별 일치 여부. 어긋난 줄은 빨간 바탕 |
| `데이터셋` | 20개 데이터셋의 GEN 명령, 기댓값 FNV, 보드 FNV, 정답 수 |
| `환경` | 시각, 포트, 플랫폼, 콘솔 판, 기댓값 파일 sha256, 명령줄, ID 응답 원문 |

판정 `all_match` 는 `result_index` · `trial_count` · `L_BBHT` · `actual_iter` 가 기댓값과 같고 결과
값이 술어를 만족할 때 1입니다. `cycle_count` 와 `wall_us` 는 기준모델에 없는 축이라 맞대지 않고
기록만 합니다.

- `cycle_count`: 가속기 100 MHz 사이클
- `wall_us`: 보드 실시간 클럭(1 MHz)으로 `COMMAND` 직전부터 DONE 을 본 순간까지. 보드 500런
  정본과 같은 구간
- `cycle_us`: 펌웨어가 `cycle_count` 를 100 으로 나눈 환산값. 실경과 시간이 아님

이 결과는 새 워크로드(술어 넷)의 보드 실측이지 성능 세 축의 정본을 대신하지 않습니다. 성능은
계속 [1장 1.5절](01_프로젝트_개요.md#15-성능-지표와-인용-기준)의 근거에서 인용합니다. 체크포인트
판과 체크포인트 없는 판을 같은 보드에서 돌려 `wall_us` 를 맞대면 최적화 유무의 실경과 시간
비교가 됩니다([21장](21_체크포인트_없는_BRAM_판.md)).

---

## 19.7 보드 없이 시험하기

| 포트 | 무엇 |
|---|---|
| `--port mock` | 기댓값으로 답하는 흉내 보드. 사이클과 wall_us 는 지어냅니다. 엑셀 첫 줄에 "MOCK" 이 찍힙니다. `--mock-platform bbht_grover_dram` · `bbht_grover_nocheckpoint` 로 다른 두 판 흉내 |
| `--port replay:<트랜스크립트>` | SoC RTL 시뮬이 낸 콘솔 출력을 되먹임. 실제 펌웨어 응답을 같은 파서로 읽음 |
| `--emit-script <헤더>` | 보낼 명령 순서만 뽑아 SoC 시뮬용 스크립트 헤더로 씀 |

SoC RTL 시뮬로 실제 CPU 위에서 확인하는 순서입니다. 스크립트 헤더 두 개
(`script_predicate500.h` · `script_predicate500_dram.h`)는 이미 앱 폴더에 있습니다. 체크포인트
없는 판도 NORMAL 만 돌므로 DRAM 스크립트와 명령이 한 줄도 다르지 않아 그것을 그대로 씁니다.

```bash
# 1. 명령 순서를 스크립트로 (체크포인트 판: 네 술어 x M=256 x 시드 2 x 두 모드)
python3 software/host/bbht_predicate500.py --port mock --targets 256 --seeds 2 \
    --emit-script hardware_bram/firmware/bbht_console/src/script_predicate500.h
# 2. 설치하고 SoC 시뮬 (환경변수 BBHT_SCRIPT 로 스크립트 선택)
hardware_bram/models/hardware_bram_K3H3_E4_M2/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_upgrade/sim_rtl
BBHT_SCRIPT=script_predicate500.h make bbht_console.sim
# 3. 트랜스크립트를 호스트 프로그램에 되먹여 엑셀까지
python3 software/host/bbht_predicate500.py --port replay:qtsim.log --targets 256 --seeds 2
```

DRAM 갈래는 RTL 시뮬의 DDR 모델이 2 MiB 라 슬롯 `j` 가 43 을 넘으면 안 됩니다. 그래서 M = 64 와
256 만 씁니다. 스크립트만 바꿔 다시 돌릴 때는 앱 빌드 폴더를 지워야 합니다
([2장 2.3절](02_개발_환경과_툴체인.md#23-rvx-플랫폼)).

---

## 19.8 문제 해결

| 증상 | 원인과 조치 |
|---|---|
| `ID 응답에 platform= 이 없습니다` | 옛 콘솔 앱입니다. 2026-09-25 판 `bbht_console.sram.hex` 를 다시 올립니다 |
| `보드 데이터셋이 기준모델과 다릅니다` | 보드의 `GEN` 과 기댓값 규칙이 어긋났습니다. 펌웨어와 `benchmark_dataset.py` 판을 확인하고 `make -C hardware_bram/sim console-gen` 을 돌려 봅니다 |
| 어느 시점부터 `ERR HOST_TIMEOUT` | 보드가 리셋됐거나 앱이 사라졌습니다. 앱을 다시 올리고 `--resume` 으로 이어 갑니다 |
| DRAM 갈래에서 `actual_iter` 만 어긋남 | 데이터셋 도중에 다시 시작한 경우입니다. DRAM 표가 비어 물리 반복이 달라집니다. `--resume` 은 반쯤 된 데이터셋을 처음부터 다시 돌리므로 그대로 쓰면 됩니다 |
| 엑셀이 안 생김 | `pip install openpyxl`. CSV 는 그대로 남아 있습니다 |

---

## 19.9 파일 지도

| 파일 | 역할 |
|---|---|
| `software/host/bbht_predicate500.py` | 호스트 자동 테스트 |
| `software/host/bbht_cli.py` | 트랜스포트와 응답 파서 (같이 씀) |
| `software/experiments/predicate500_benchmark/run_predicate500_golden.py` | 기댓값 생성 |
| `software/models/common/benchmark_dataset.py` | 데이터셋 규칙 정본 (`generate_predicate_image`, `fnv1a32_s16`) |
| `hardware_bram/firmware/bbht_console/src/bbht_dataset_gen.h` | 같은 규칙의 펌웨어 판 |
| `software/rtl_vectors/tools/dump_predicate500_workload.py` | RTL 벤치 자극 |
| `hardware_bram/testbench/tb_predicate500.cpp` · `sim/predicate500_report.py` | 체크포인트 판 RTL 벤치와 대조기. 체크포인트 없는 판도 같은 하네스를 `PRED500_MODES=normal` 로 쓰고, 대조기는 `--branch nocheckpoint` · `--branch dram` 도 봄 |
| `hardware_bram/models/hardware_bram_nocheckpoint/sim/equiv_check.py` | 체크포인트 없는 판과 체크포인트 판(M1=M2=0) Normal 의 8열 대조 |
| `hardware_dram/testbench/tb_dram_predicate500.cpp` | DRAM 갈래 RTL 벤치 |
