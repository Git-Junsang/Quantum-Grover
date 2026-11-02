# 18장. Predicate500 자동 test

> [← 17장 board 운용](17_board_operation.md) · [index](index.md) · [19장 synthesis · implementation · bitstream →](19_synthesis_implementation_bitstream.md)

---

board를 연결해 두고 명령 하나로 LT · GT · EQ · RANGE 각각 500 workloads를 돌려 software reference model과
맞대고 Excel로 남기는 program입니다. host program은
[`software/host_fpga_develop/bbht_predicate500.py`](../../software/host_fpga_develop/bbht_predicate500.py), board app은
`bbht_console`(2026-09-25 revision), expected result는 `software/reference_model_develop/predicate500/` 입니다.
세 bitstream 모두에서 돕니다.

---

## 18.1 왜 필요한가

board 500 runs(2026-09-08)와 software Common500 은 모두 "12345 와 같은가" 한 predicate를 500 workloads에
걸었습니다. LT · GT · RANGE 는 RTL regression에서 몇 건만 돌았습니다. 설계는 네 predicate를 같은
comparator(`grover_predicate`)로 oracle · solution check · enumeration에 똑같이 쓰지만, 그것을 같은 규모로
확인한 근거가 없었습니다.

Predicate500 은 Common500 과 같은 모양(number of solutions 1/4/16/64/256 × 공식 seed 100쌍)을 네 predicate에
각각 겁니다. 2,000 workloads이고, EQ 500개는 Common500 과 dataset · seed가 byte 단위로
같습니다.

---

## 18.2 workload

| predicate | threshold | solution 값 범위 | 위치 seed |
|---|---|---|---|
| LT | A = −16384 | [−32768, −16385] | `0x17A02026` |
| GT | A = 16383 | [16384, 32767] | `0x67A02026` |
| EQ | A = 12345 | 12345 | `0xA17E2026` (공식) |
| RANGE | A = −4096, B = 4096 | [−4095, 4095] (open interval) | `0x3A4E2026` |

dataset은 16,384칸 전부 유효(`DATA_COUNT = 16384`)이고 배경 seed는 공식 benchmark와 같은
`0x5EED1234` 입니다. 만드는 규칙은 둘입니다.

- 배경: xorshift32 로 16-bit 값을 차례로 뽑되, predicate를 만족하는 값은 non-solution 쪽으로 접어 넣습니다.
  LT 이면 `A` 이상으로, GT 이면 `A` 이하로, RANGE 이면 `B` 이상으로 옮기므로 배경에는 solution이
  하나도 없습니다.
- solution: 위치 seed로 칸을 뽑아(이미 solution인 칸은 건너뜀) 정한 number of solutions만큼 심습니다. 값은 EQ 이면 `A`, 나머지는
  따로 도는 xorshift32 로 solution 값 범위 안에 흩뿌립니다. 그래서 LT 의 solution은 −32768 부터 −16385 까지
  여러 값에 걸쳐 있고 comparator의 양 끝 근처가 같이 시험됩니다.

number of solutions가 커질 때 앞의 solution이 그대로 남습니다(1 ⊂ 4 ⊂ 16 ⊂ 64 ⊂ 256). 공식 benchmark와 같은 성질입니다.

규칙의 source of truth는 `benchmark_dataset.py` 의 `generate_predicate_image` 이고, board firmware의 `GEN PRED=`
가 같은 integer 연산을 합니다([14장 14.3절](14_host_interface_and_uart_protocol.md#143-명령)). 그래서
dataset 32 KB 를 UART 로 보내지 않습니다. board가 `GEN` 으로 직접 만들고, host는 `SUM` 이
돌려주는 FNV-1a hash와 number of solutions만 expected result와 맞댑니다.

---

## 18.3 expected result

```bash
python3 software/reference_model_develop/predicate500/run_predicate500_golden.py   # 30초쯤
```

Q1.22 bit-exact reference model이 2,000 workloads를 셋 mode로 돌려 `expected/` 에 두 file을 씁니다
([4장 4.4절](04_software_reference_model_and_test_vectors.md#44-predicate500-expected-result)). 저장소에 commit해
두었으므로 host 에는 numpy 가 필요 없습니다.

| file | 내용 |
|---|---|
| `predicate500_expected.csv` | workload 2,000 rows. `result_index` `result_value` `trial_count` `L_BBHT` 와 executed iterations 열 넷 |
| `predicate500_datasets.csv` | 20 datasets. board에 보낼 `GEN` 명령, FNV-1a, sha256 |

| executed iterations 열 | 무엇과 맞대나 |
|---|---|
| `actual_iter_normal` | final configuration의 Restart mode, No-Checkpoint Baseline (`L_BBHT` 와 같음) |
| `actual_iter_k3h3` | final configuration의 Checkpoint mode |
| `actual_iter_dram_all_j` | search마다 DRAM 표를 비운 DRAM Variant (참고용) |
| `actual_iter_dram_session` | dataset 하나를 load한 뒤 seed를 차례로 돌며 DRAM 표를 이어 쓴 DRAM Variant. board · RTL 은 이 열과 맞아야 함 |

DRAM 표는 load나 predicate 변경 때만 버려지므로 DRAM Variant는 session 열과 맞대야 합니다. EQ 500 rows는
board 500-run benchmark(Restart mode, final configuration)와 `result_index` · `trial_count` · `L_BBHT` · executed iterations가 모두
500/500 같습니다. expected result가 Board-Verified Build와 같은 계산을 한다는 확인입니다.

---

## 18.4 board에 올리기 전에 확인한 것

세 revision의 RTL 과 SoC RTL simulation(실제 RISC-V 가 console을 돌림)에서 전부 expected result와 맞았습니다. 표는
[16장 16.9절](16_verification_framework.md#169-네-predicate와-다른-두-revision)에 있습니다. final configuration RTL testbench의
EQ 1,000 실행은 기존 bench500 근거(board final configuration과 cycle까지 500/500)와 cycle까지 1,000/1,000
같아서, 새 harness도 믿을 만하다는 것을 함께 확인했습니다.

board 실행은 2026-10-04 에 세 revision 모두 마쳤고, 8,000 실행이 전부 expected result와 맞았습니다. 결과와
revision 사이 비교는 [실험 16](../reports/16_three_revisions_board_predicate500.md)에 있습니다.

---

## 18.5 board에서 돌리는 법

bitstream과 console app은 [17장](17_board_operation.md) 절차대로 올립니다. console은 2026-09-25 revision이어야
합니다. `GEN PRED` · `SUM` · `wall_us` · `ID` 의 `platform=` 이 이 revision에서 생겼고, 옛 revision이면
program이 첫 `ID` 에서 알려 주고 멈춥니다. host 에는 `pip install pyserial openpyxl` 이
필요합니다.

```bash
python3 software/host_fpga_develop/bbht_predicate500.py --port /dev/ttyUSB1        # Linux / WSL
python3 software/host_fpga_develop/bbht_predicate500.py --port COM4                # Windows
```

program이 하는 일은 이 순서입니다.

1. `ID` 로 platform과 console revision을 확인합니다. `bbht_grover_final` 면 Restart mode와 Checkpoint mode를 같은 seed로
   짝지어 4,000 실행, `bbht_grover_no_checkpoint_baseline` 과 `bbht_grover_dram` 이면 Restart mode만 2,000
   실행입니다. executed iterations는 No-Checkpoint Baseline이 `actual_iter_normal`, DRAM Variant가
   `actual_iter_dram_session` 열과 맞댑니다.
2. predicate × number of solutions 마다 `GEN PRED=...` → `SUM` 으로 FNV 와 number of solutions 확인 → `LOAD` → `SET`
3. seed 100쌍마다 `SET BURST=.. SEEDJ=.. SEEDM=..` → `RUN`, 결과를 expected result와 맞댐
4. 실행마다 CSV 에 한 줄씩 바로 쓰고, 끝나면 Excel file을 만들고 terminal에 요약과 판정을 찍음

| 인자 | 뜻 |
|---|---|
| `--predicates EQ` | predicate 일부만 (`LT,GT` 처럼 쉼표) |
| `--targets 1,4` · `--seeds 10` | number of solutions나 seed 일부만 (시험용) |
| `--modes normal` | final configuration에서도 Restart mode만 |
| `--out 경로.xlsx` | 결과 file. 안 주면 현재 directory에 `predicate500_<platform>_<시각>.xlsx` |
| `--resume` | `--out` 의 CSV 가 있으면 끝난 dataset은 건너뜀 |
| `--log 파일` | 주고받은 줄 전부 기록 |
| `--timeout 60` | 명령 하나의 응답 대기 상한(초) |

걸리는 시간은 UART 왕복이 대부분입니다. 실행 하나가 명령 둘(SET, RUN)이고 응답이 짧아서
4,000 실행이면 수 분 정도로 예상합니다. board에서 잰 값은 아직 없습니다.

---

## 18.6 Excel 결과

| sheet | 내용 |
|---|---|
| `요약` | predicate × mode마다 실행 수, 축별 일치 수, 전부 일치 수, executed iterations · cycle · wall_us sum. final configuration이면 Restart mode 대비 Checkpoint mode의 speedup |
| `M별 요약` | 같은 것을 number of solutions별로 |
| `실행별` | 실행 한 줄씩. board 값, expected result, 축별 일치 여부. 어긋난 줄은 빨간 바탕 |
| `데이터셋` | 20 datasets의 GEN 명령, expected result FNV, board FNV, number of solutions |
| `환경` | 시각, port, platform, console revision, expected result file sha256, 명령줄, ID 응답 원문 |

판정 `all_match` 는 `result_index` · `trial_count` · `L_BBHT` · `actual_iter` 가 expected result와 같고 결과
값이 predicate를 만족할 때 1입니다. `cycle_count` 와 `wall_us` 는 reference model에 없는 축이라 맞대지 않고
기록만 합니다.

- `cycle_count`: accelerator 100 MHz cycle
- `wall_us`: board 실시간 clock(1 MHz)으로 `COMMAND` 직전부터 DONE 을 본 순간까지. Board-Verified Build의
  500-run board benchmark와 같은 시간 범위
- `cycle_us`: firmware가 `cycle_count` 를 100 으로 나눈 환산값. wall-clock time이 아님

이 결과는 새 workload(predicate 넷)의 board benchmark이지 성능 세 축의 source of truth를 대신하지 않습니다. 성능은
계속 [1장 1.5절](01_project_overview.md#15-성능-지표와-인용-기준)의 근거에서 인용합니다. final
configuration과 No-Checkpoint Baseline을 같은 board에서 돌려 `wall_us` 를 맞대면 최적화 유무의 wall-clock time
비교가 됩니다([20장](20_no_checkpoint_baseline.md)).

---

## 18.7 board 없이 시험하기

| port | 무엇 |
|---|---|
| `--port mock` | expected result로 답하는 흉내 board. cycle과 wall_us 는 지어냅니다. Excel 첫 줄에 "MOCK" 이 찍힙니다. `--mock-platform bbht_grover_dram` · `bbht_grover_no_checkpoint_baseline` 으로 다른 두 revision 흉내 |
| `--port replay:<트랜스크립트>` | SoC RTL simulation이 낸 console 출력을 되먹임. 실제 firmware 응답을 같은 parser로 읽음 |
| `--emit-script <헤더>` | 보낼 명령 순서만 뽑아 SoC simulation용 script header로 씀 |

SoC RTL simulation으로 실제 CPU 위에서 확인하는 순서입니다. script header 두 개
(`script_predicate500.h` · `script_predicate500_dram.h`)는 이미 app directory에 있습니다. No-Checkpoint
Baseline도 Restart mode만 돌므로 DRAM script와 명령이 한 줄도 다르지 않아 그것을 그대로 씁니다.

```bash
# 1. 명령 순서를 script로 (checkpoint 판: 네 predicate x M=256 x seed 2 x 두 mode)
python3 software/host_fpga_develop/bbht_predicate500.py --port mock --targets 256 --seeds 2 \
    --emit-script hardware_bram/firmware/bbht_console/src/script_predicate500.h
# 2. 설치하고 SoC simulation (환경변수 BBHT_SCRIPT 로 script 선택)
hardware_bram/configurations/final/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_final/sim_rtl
BBHT_SCRIPT=script_predicate500.h make bbht_console.sim
# 3. 트랜스크립트를 host 프로그램에 되먹여 엑셀까지
python3 software/host_fpga_develop/bbht_predicate500.py --port replay:qtsim.log --targets 256 --seeds 2
```

DRAM Variant는 RTL simulation의 DDR model이 2 MiB 라 number of iterations가 43 을 넘는 checkpoint slot을 둘 수 없습니다. 그래서
64 · 256 solutions만 씁니다. script만 바꿔 다시 돌릴 때는 app build directory를 지워야 합니다
([2장 2.3절](02_development_environment_and_toolchain.md#23-rvx-platform)).

---

## 18.8 문제 해결

| 증상 | 원인과 조치 |
|---|---|
| `ID 응답에 platform= 이 없습니다` | 옛 console app입니다. 2026-09-25 revision의 `bbht_console.sram.hex` 를 다시 올립니다 |
| `보드 데이터셋이 기준모델과 다릅니다` | board의 `GEN` 과 expected result 규칙이 어긋났습니다. firmware와 `benchmark_dataset.py` revision을 확인하고 `make -C hardware_bram/sim console-gen` 을 돌려 봅니다 |
| 어느 시점부터 `ERR HOST_TIMEOUT` | board가 reset됐거나 app이 사라졌습니다. app을 다시 올리고 `--resume` 으로 이어 갑니다 |
| DRAM Variant에서 `actual_iter` 만 어긋남 | dataset 도중에 다시 시작한 경우입니다. DRAM 표가 비어 executed iterations가 달라집니다. `--resume` 은 반쯤 된 dataset을 처음부터 다시 돌리므로 그대로 쓰면 됩니다 |
| Excel file이 안 생김 | `pip install openpyxl`. CSV 는 그대로 남아 있습니다 |

---

## 18.9 file 지도

| file | 역할 |
|---|---|
| `software/host_fpga_develop/bbht_predicate500.py` | host 자동 test |
| `software/host_fpga_develop/bbht_cli.py` | transport와 응답 parser (같이 씀) |
| `software/reference_model_develop/predicate500/run_predicate500_golden.py` | expected result 생성 |
| `software/reference_model_develop/models/common/benchmark_dataset.py` | dataset 규칙 source of truth (`generate_predicate_image`, `fnv1a32_s16`) |
| `hardware_bram/firmware/bbht_console/src/bbht_dataset_gen.h` | 같은 규칙의 firmware implementation |
| `software/reference_model_develop/tb_stimulus/dump_predicate500_workload.py` | RTL testbench stimulus |
| `hardware_bram/testbench/tb_predicate500.cpp` · `sim/predicate500_report.py` | final configuration RTL testbench와 대조기. No-Checkpoint Baseline도 같은 harness를 `PRED500_MODES=normal` 로 쓰고, 대조기는 `--branch no_checkpoint_baseline` · `--branch dram` 도 봄 |
| `hardware_bram/configurations/no_checkpoint_baseline/sim/equiv_check.py` | No-Checkpoint Baseline과, final configuration RTL을 Single-Row Build · Linear Select로 돌린 Restart mode의 8열 대조 |
| `hardware_dram/testbench/tb_dram_predicate500.cpp` | DRAM Variant RTL testbench |
