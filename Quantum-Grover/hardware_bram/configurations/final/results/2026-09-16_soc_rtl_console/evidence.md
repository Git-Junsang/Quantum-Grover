# SoC RTL simulation — `bbht_console` 명령 왕복과 host CLI 재생

## 무엇인가

RVX platform `bbht_grover_final` 전체(ORCA RISC-V core · micro NoC · APB/AHB NI ·
우리 Bus Interface · Accelerator Core)를 Questa로 RTL simulation을 돌리면서 `bbht_console` 을 script mode로
돌린 결과입니다. 명령 21줄의 응답을 host CLI `software/host_fpga_develop/bbht_cli.py` 의 재생
transport에 그대로 먹여 parse하고, parse한 숫자를 기준과 대조했습니다.

같은 날의 [`2026-09-16_soc_rtl_paper_bench`](../2026-09-16_soc_rtl_paper_bench/evidence.md)
가 "SoC에서 CPU가 Bus Interface를 구동한다"를 보였다면, 이 묶음은 **명령 parser → driver
→ CSR/DMA → Accelerator Core → UART 응답 → host parser**의 왕복을 보입니다.

## 앞선 기록의 정정 — "OK 직후에 멈춘다"는 시험 절차의 잘못이었습니다

paper_bench 묶음에는 `bbht_console` 이 SoC simulation에서 시작 banner `OK` 직후에 멈추고 원인을
못 찾았다고 적혀 있었습니다. **원인은 firmware도 RVX도 RTL도 아니고 제 시험 절차였습니다.**

- script mode는 `-DBBHT_CONSOLE_SCRIPT` 로 켭니다. 이것을 app directory에서
  `make rtl DEFINE_CFLAGS=...` 로 넘겨 build했습니다.
- 그런데 `sim_rtl` 의 `make bbht_console.sim` 은 simulation 직전에 app을 **스스로 다시
  build**합니다(`rtl.debug`). 그때는 명령줄 값이 없으니 simulation에 실린 것은 UART revision이었고,
  UART revision은 설계대로 `read_line()` 에서 RX 입력을 기다렸습니다. RVX simulation printf module
  `ncsim_printf.v` 는 `uart_tx` 를 1로 묶어 둬서 입력이 오지 않습니다.
- 당시 `sim_rtl/rvx_app_build.log` 에 `BBHT_CONSOLE_SCRIPT` 가 **0번** 나옵니다.
  loop 안에 넣은 표시 printf가 안 나온 것, `uart_init()` 을 빼도 똑같이 멈춘 것도 둘 다
  `#ifdef BBHT_CONSOLE_SCRIPT` 안에 넣은 변경이라 애초에 build에 없었기 때문입니다.

고친 방법은 RVX가 정한 app별 설정 file입니다.
[`firmware/bbht_console/rvx_each.mh`](../../../../firmware/bbht_console/rvx_each.mh) 에
`TARGET_IMP_CLASS=rtl` 일 때만 이 정의를 넣었습니다. app을 누가 언제 다시 build하든
RTL simulation build에는 들어가고 board build에는 안 들어갑니다.

| 확인 | 결과 |
|---|---|
| `make bbht_console.sim` 이 다시 build한 log의 `BBHT_CONSOLE_SCRIPT` | 0번 → 75번 |
| RTL simulation ELF 안의 `script done` 문자열 | 있음 |
| board build(`make arty-100t`) log의 `BBHT_CONSOLE_SCRIPT` | 0번 |
| board build ELF sha256, 이번 수정 전 `main.c` 대 후 | 둘 다 `535ba8cf…` — byte 동일 |
| simulation | 2분 55초 만에 `QUIT` 까지 가서 정상 종료 |

## 확정 수치

`crosscheck.txt` 의 요약입니다. **어긋남 0건.**

| 검사 | 결과 |
|---|---|
| 명령 21줄의 echo 순서 = host가 보낸 순서 | 21/21 |
| 종결자 (일부러 넣은 `ERR` 2줄 포함) | 21/21 |
| `ID` 응답 7값 대 CSR source of truth (`bbht_cli.py selftest`) | 7/7 |
| `POKE` 네 칸 = `dataset_target_4.bin` 의 12345 자리 `507 2852 4724 8685` | 일치 |
| `RUN`/`STAT` 3회 대 같은 순서 verilator (HIT 5 + STAT 15) | 60/60 |
| `ENUM` 대 같은 순서 verilator (FOUND 순서 · END cyc 280,494) | 일치 |

workload는 board 500 runs의 **4 solutions, seed 0**입니다. console은 `GEN TARGETS=0` 으로 12345가
없는 배경을 만들고 `POKE` 네 줄로 같은 자리에 solution을 심습니다. EQ predicate는 12345인
칸만 보므로 oracle 표시가 board dataset과 같고, board dataset을 그대로 쓴 verilator
기준과 모든 값이 같게 나왔습니다.

| RUN | 기준 | result_index | trial | L_BBHT | actual_iter | cycle_count |
|---|---|---:|---:|---:|---:|---:|
| 1. Restart mode | bench500 · SoC paper_bench | 8685 = | 21 = | 119 = | 119 = | 41,310 = |
| 2. Checkpoint mode, reset 뒤 첫 번째 | Six-Stage Ablation campaign의 final configuration | 8685 = | 21 = | 119 = | 38 = | 20,935 = |
| 3. Checkpoint mode, 두 번째 | board의 final configuration · bench500 · SoC paper_bench | 8685 = | 21 = | 119 = | 38 = | 17,847 (board 17,656) |

## checkpoint cycle은 실행 이력에 달려 있습니다

RUN 2와 RUN 3은 설정 · data · seed가 전부 같고 사이에 reset만 없습니다. BBHT trajectory는 같은데
cycle이 20,935와 17,847로 다릅니다. 차이는 전부 `policy_stall` 입니다.

**reset 뒤 첫 checkpoint search의 +3,279 cycles — 원인 확인.**
`grover_policy.v` 는 memo table BRAM이 reset으로 지워지지 않아서, reset 뒤 첫 시작과 epoch가
한 바퀴 돌 때 `ST_CLEAR` state에서 memo table을 한 칸씩 지웁니다. 길이가
`MEM_ENTRIES = LOOKAHEAD_SHOTS × STATE_RANKS = 3 × 1,093 = 3,279` cycles입니다. RUN 2는
연달아 도는 bench500의 같은 row보다 cycle · policy_cycles · policy_stall이 **셋 다
정확히 +3,279** 이고, `max_latency` 가 3,352로 튀어 있습니다.

그래서 board 500 runs 묶음이 "원인을 확인하지 않았다"고 적어 둔 **Six-Stage Ablation campaign과 board final configuration의
473/500이 정확히 3,279 cycles 차이**는 이 memo table 청소로 설명됩니다. Six-Stage Ablation campaign은
workload마다 새로 시작해서 매번 청소를 치르고, board app과 bench500은 500개를 연달아
돌아 첫 workload에서 한 번만 치릅니다. 이 묶음에서 직접 확인한 것은 한 workload이고,
473건 전부를 이 방식으로 다시 돌려 보지는 않았습니다. 나머지 21건이 제각각인 이유
(epoch 한 바퀴마다 붙는 청소가 어느 workload에 떨어지느냐로 보이지만)도 확인하지
않았습니다.

**그다음 search의 +191 cycles.** RUN 3은 bench500의 같은 row보다 policy_stall이 191,
policy_actions가 87 많습니다. 직전 search가 RUN 2(같은 workload)인 console과 1 solution, seed 99
인 bench500이 달라서 Policy Engine이 남긴 state가 다르기 때문입니다. **무엇이 남는지는
확인하지 않았습니다.** 다만 이것이 Bus Interface나 firmware 탓이 아니라는 것은 확인했습니다
— 같은 RTL을 console과 같은 순서로 두드린 verilator harness
(`testbench/tb_console_seq.cpp`)가 RUN 3의 17,847과 STAT 15값을 전부 똑같이 냅니다.

결론적으로 **board에서 console로 돌린 checkpoint cycle은 board 500 runs 표와 같게 나올 이유가
없습니다.** 논리 4축은 같아야 하고, cycle은 직전에 무엇을 돌렸는지와 함께 보아야 합니다.

## 확인하지 않은 것

- **물리 UART.** simulation printf module이 115200 baud로 받아 해독했지만 FTDI · baud rate error ·
  pin map은 board에서만 봅니다.
- **host → board 방향 byte.** script mode는 명령을 compile 시점 array에서 읽습니다.
  UART RX · echo · backspace 처리 code(`read_line()` 의 UART revision)는 simulation에서 돌지
  않았습니다. `bbht_cli.py` 의 `SerialTransport` 도 마찬가지입니다.
- **workload 하나.** 4 solutions, seed 0만 돌렸습니다. 나머지 workload의 SoC 경로 근거는
  paper_bench 묶음(261쌍)입니다.
- **`amp_overflow` 줄, `REG` · `HELP` 명령.** script에 넣지 않았습니다.

## file

| file | 내용 |
|---|---|
| `transcript.txt` | `qtsim.log` 에서 떼어 Questa 머리말을 벗긴 console 출력. `bbht_cli.py --port replay:` 에 그대로 먹일 수 있습니다 |
| `crosscheck.txt` | `soc_console_check.py` 출력 원문 |
| `verilator_seq.csv` | `make console-seq` 출력. console과 같은 순서의 기준값 |

## 재현

```bash
source /opt/rvx/rvx_setup.sh
hardware_bram/configurations/final/rvx/install_to_platform.sh              # rvx_each.mh 까지 옮깁니다
cd $RVX_MINI_HOME/platform/bbht_grover_final        # make syn · make sim_rtl 은 한 번만
cd sim_rtl && make bbht_console.sim                   # 3분쯤
grep -c BBHT_CONSOLE_SCRIPT rvx_app_build.log         # 0 이면 스크립트 모드가 아닙니다

cd <저장소>
make -C hardware_bram/sim console-seq                 # 30초쯤
python3 hardware_bram/sim/soc_console_check.py \
    $RVX_MINI_HOME/platform/bbht_grover_final/sim_rtl/qtsim.log \
    --ref /tmp/sjs_console_seq/console_seq.csv --transcript transcript.txt
```
