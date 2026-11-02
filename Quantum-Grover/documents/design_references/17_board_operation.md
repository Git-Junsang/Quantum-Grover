# 17장. board 운용

> [← 16장 verification 체계](16_verification_framework.md) · [index](index.md) · [18장 Predicate500 자동 test →](18_predicate500_automated_test.md)

---

이 장은 bitstream을 만들고 Arty A7-100T 에 구워, host 에서 accelerator를 부리는 절차입니다.
명령 문법은 [14장](14_host_interface_and_uart_protocol.md), board에서 실제로 잰 결과와 그
인용 경계는 [실험 보고서 index 「board benchmark 묶음」](../reports/index.md#board-benchmark-묶음)에 있습니다. 예시는 final configuration(`bbht_grover_final`)
기준이고, 다른 두 revision은 platform 이름과 bitstream 묶음만 다릅니다.

---

## 17.1 platform 설치와 생성

### 설치 script가 옮기는 것

```bash
source /opt/rvx/rvx_setup.sh
hardware_bram/configurations/final/rvx/install_to_platform.sh     # $RVX_MINI_HOME/platform/bbht_grover_final
```

| 저장소 | platform |
|---|---|
| `hardware_bram/configurations/final/rvx/bbht_grover_final.xml` | `<플랫폼이름>.xml` (`<name>` 을 directory 이름에 맞춰 넣음) |
| `hardware_bram/src/` Accelerator Core 10개 + `grover_param.vh` | `user/rtl/src/` · `include/` |
| `hardware_bram/src/` Bus Interface 3개 + configuration의 `src/bbht_grover_core_adapter.v` | `user/rtl/src/` |
| `hardware_bram/src/bbht_grover_user_region.vh` | `user/rtl/include/<플랫폼이름>_user_region.vh` |
| `spec/generated/bbht_grover_csr.vh` | `user/rtl/include/` |
| `hardware_bram/firmware/bbht_grover_driver.{c,h}` · `generated/bbht_grover_regs.h` | `user/api/` |
| `firmware/bbht_console/` · `bbht_paper_bench/` · `orca_sw_baseline/` | `app/`. 다른 configuration은 `bbht_console` 하나 |
| (script가 만듦) | `user/env/set_rtl_syn_env.tcl`. `user/rtl` 을 synthesis 경로에 등록 |
| RVX 뼈대 `$RVX_DEVKIT/env/user/` 중 없는 것 | `user/env/` · `user/sim/include/` |

일은 전부 공용 설치기 [`hardware_bram/rvx/install_model.sh`](../../hardware_bram/rvx/install_model.sh) 가
하고, configuration의 `install_to_platform.sh` 는 configuration directory와 app 목록만 넘깁니다. 다른 configuration은 그 configuration의
script를 부르면 되고, 설치기는 어떤 Checkpoint-Capacity · Lookahead-Shots · number of PEs · Measurement Microarchitecture가 들어갔는지 adapter 기본값을 찍어 줍니다.
설치할 때마다 `user/rtl/` 과 app directory를 비우고 다시 채우므로 앞서 설치한 다른 configuration의 흔적이
남지 않습니다. RVX 뼈대를 빠진 것만 채우는 이유는 RVX 가 `make syn` 때 `user/` 가 **없을 때만**
뼈대를 복사하기 때문입니다. 설치기가 `user/` 를 먼저 만들면 그 복사가 건너뛰어져 SoC simulation
compile이 user region header를 못 찾습니다(2026-09-25 첫 simulation이 이것으로 실패했습니다).

script는 첫 줄에서 `gen_csr.py` 를 불러 생성 header 둘을 직접 만들므로, 저장소를 새로 받아도
따로 준비할 것이 없습니다. synthesis 대상만 골라 옮깁니다. `grover_policy_ooc_top.v` ·
`grover_policy_impl_wrapper.v` 는 OOC 전용이고, `bbht_bram_top.v` 는 wrapper 와 같은 자리에 들어가는
다른 최상단이라 빠집니다.

### platform directory를 처음 만들 때

script는 platform directory를 만들지 않습니다. 없으면 안내만 하고 끝나므로 RVX 골격부터 만듭니다.

```bash
cd $RVX_MINI_HOME/platform
make copy_platform BEFORE=bbht_grover AFTER=bbht_grover_final
```

복제본에는 다른 platform의 RTL 이 이름만 바뀐 채 들어 있습니다(`rename.py` 가 file 이름과 내용의
`bbht_grover` 를 전부 치환합니다). 특히 `bbht_grover_core_stub.v` 는 우리 adapter와 module 이름이
겹쳐 elaboration 을 깨뜨리므로, 설치 전에 `user/rtl/{src,include}` · `user/api` ·
`user/template` 을 비우고 `app/bbht_console` 을 지웁니다.

No-Checkpoint Baseline은 `tip_hello` 의 Makefile 만 복사한 빈 directory에서 시작하고, 그 설치 script가
RVX `user/` 뼈대 중 빠진 것을 채웁니다. RVX 는 `make syn` 때 `user/` 가 없을 때만 뼈대를
복사하는데, 설치 script가 `user/` 를 먼저 만들면 그게 건너뛰어져 SoC simulation이 user region header를
못 찾기 때문입니다([20장 20.7절](20_no_checkpoint_baseline.md#207-돌리는-법)).

### 생성과 확인할 값

```bash
cd $RVX_MINI_HOME/platform/bbht_grover_final
make syn
grep -E "I_GROVER_CSR_SLAVE_BASEADDR|I_SYSTEM_SRAM" arch/ssw/src/memorymap_info.h
grep SYSTEM_CLK_HZ arch/ssw/src/hw_info.h
```

| 무엇 | 값 (2026-09-02 benchmark) |
|---|---|
| `I_GROVER_CSR_SLAVE_BASEADDR` | `0xE2020000` (size `0x1000`) |
| `I_SYSTEM_SRAM` | `0xE0000000` ~ `0xE001FFFF` (128 KiB) |
| `SYSTEM_CLK_HZ` | 50 MHz (SoC 쪽) |
| `clk_accel` | 100 MHz (accelerator clock domain, PLL0) |

clock이 둘이라는 점이 자주 헷갈립니다. RISC-V core와 UART 는 50 MHz, accelerator와 CSR · DMA Engine 은
100 MHz 에서 돕니다. `CYCLE_COUNT` 는 뒤엣것 기준이라 시간 = cycle / 100 µs 이고, 50으로 나누면
두 배 틀립니다.

---

## 17.2 bitstream 만들기

```bash
cd $RVX_MINI_HOME/platform/bbht_grover_final
make imp_fpga TARGET_IMP_CLASS=arty-100t      # make arty-100t 와 같음
cd imp_arty-100t_<날짜>
make imp                                      # 나오는 것: imp_result/bbht_grover_fpga.arty-100t.bit
make bbht_console                             # board용 console hex
```

Bus Interface를 고친 뒤에는 implementation report를 다시 뽑아 commit된 기준과 비교합니다. 특히
`route_timing_summary.rpt` 의 WNS 입니다. 기준 수치와 report 위치는
[19장](19_synthesis_implementation_bitstream.md)에 있습니다.

board에 구운 것은 directory tree마다 `bitstream/<날짜>_<주제>/` 묶음으로 남겨 두었습니다. 묶음마다
bitstream · console hex · 굽기 script(`program_fpga.tcl`) · load 묶음(`ocd/`) · hash가 같이
있습니다.

| 묶음 | 내용 |
|---|---|
| [`hardware_bram/configurations/final/bitstream/2026-09-08_k3h3_e4_m2/`](../../hardware_bram/configurations/final/bitstream/2026-09-08_k3h3_e4_m2/evidence.md) | Board-Verified Build bitstream + `bbht_paper_bench.elf` + `orca_sw_baseline.elf` |
| [`hardware_bram/configurations/final/bitstream/2026-09-17_comm_layer_rebuild/`](../../hardware_bram/configurations/final/bitstream/2026-09-17_comm_layer_rebuild/evidence.md) | Bus Interface를 교체한 revision + 2026-09-17 console |
| [`hardware_bram/configurations/final/bitstream/2026-09-25_console_predicate500/`](../../hardware_bram/configurations/final/bitstream/2026-09-25_console_predicate500/evidence.md) | 같은 bitstream + 2026-09-25 revision의 console(`GEN PRED` · `SUM` · `wall_us`) |
| [`hardware_bram/configurations/no_checkpoint_baseline/bitstream/2026-09-25_nocheckpoint/`](../../hardware_bram/configurations/no_checkpoint_baseline/bitstream/2026-09-25_nocheckpoint/evidence.md) | No-Checkpoint Baseline. 2026-10-04 board에서 Predicate500 2,000/2,000 |
| [`hardware_dram/bitstream/2026-09-25_dram_axi/`](../../hardware_dram/bitstream/2026-09-25_dram_axi/evidence.md) | DRAM Variant. 2026-10-04 board에서 Predicate500 2,000/2,000 |

---

## 17.3 board 연결과 UART

Arty A7-100T 의 micro USB 하나가 JTAG 과 UART 를 겸합니다(FT2232). 꽂으면 host에 serial
port가 둘 잡힙니다.

```bash
ls -l /dev/serial/by-id/          # 안정적인 이름
dmesg | tail -20                  # 방금 잡힌 ttyUSB 번호
sudo usermod -aG dialout $USER    # 권한이 없으면. 로그아웃 후 다시 로그인
```

보통 `/dev/ttyUSB0` 이 JTAG channel, `/dev/ttyUSB1` 이 UART channel입니다. 둘 중 뒤 번호가 UART 이고,
앞 번호에 terminal을 붙이면 아무것도 안 나옵니다. Windows 에서는 `COM` 번호로 잡힙니다.

| 항목 | 값 |
|---|---|
| baud rate | 115200 |
| data · parity · stop bit | 8 · 없음 · 1 |
| flow control | 없음 |

baud rate는 RVX 의 `ervp_uart.c` 기본값(`UART_BAUD_RATE 115200`)이고 `UART_CLK_HZ` 50 MHz 에서
분주됩니다. `SYSTEM_CLK_HZ` 를 바꾸면 분주비가 같이 바뀌므로 clock을 건드린 뒤에는 다시
확인합니다. 안 맞으면 깨진 글자만 나옵니다.

UART RX 는 표준 pin map 그대로 양방향입니다. `imp_class_info/arty-100t/pinmap/uart_printf.xdc` 가
`printf_rx` 를 A9 pin(`uart_txd_in`)에 배정하고, RVX SSW 에 `uart_check_rx_data_ready()` ·
`uart_read_rx_buffer()` API 가 있습니다.

---

## 17.4 굽고 app 올리기

### bitstream

```bash
cd hardware_bram/configurations/final/bitstream/2026-09-25_console_predicate500
vivado -mode batch -source program_fpga.tcl        # 헤드리스 가능
```

RVX imp directory에서는 `make program`(board에 굽기) · `make program_flash`(SPI flash에 굽기, 전원을
내려도 남음)로도 굽습니다.

### app

app은 JTAG 로 SRAM 에 올립니다. JTAG adapter(Olimex ARM-USB-TINY-H)가 붙은 PC 에서 합니다.
Windows 면 `usbipd` 로 WSL 에 넘긴 뒤입니다.

```bash
cp /opt/rvx/local_setup/ocd/openocd_rvp ocd/
cp bbht_console.sram.hex ocd/
ocd/ocd_keep.sh &          # 올린 뒤 OpenOCD 를 붙여 둔 채 유지
```

`ocd/` 는 RVX 가 imp directory에 내주는 OCD 환경이 `/opt/rvx` absolute path를 읽어 다른 PC 에서 못 쓰기
때문에, 필요한 tcl 을 relative path로 모아 둔 묶음입니다.

| file | 역할 |
|---|---|
| `arty-100t.cfg` | OpenOCD 설정. Olimex ARM-USB-TINY-H, 10 MHz, JTAG tap `rvp.noc` |
| `run_bbht_console.tcl` | platform reset → SRAM 에 write → `set_all_ready` |
| `set_ocd_env.tcl` | `arch/` · `rvx_env/` 를 relative path로 읽도록 고친 revision |
| `load_app.sh` | 올리고 빠져나옴 |
| `ocd_keep.sh` | 올린 뒤 OpenOCD 를 붙여 둔 채 유지 |

OpenOCD 를 종료하면 adapter 분리 과정에서 platform이 reset되어 SRAM 의 app이 사라집니다. SPI flash
boot 기능은 아직 없으므로 board RESET button을 눌러도 app을 다시 올려야 합니다. `openocd_rvp` 실행
file(12 MB)은 저장소에 두지 않았습니다. `/opt/rvx/local_setup/ocd/` 사본과 sha256 이 같습니다.

RVX imp directory에서 build와 실행을 한 번에 하려면 `make <앱>.run` 입니다.

---

## 17.5 두 가지 app

| | proof app (`bbht_paper_bench` 등) | console app (`bbht_console`) |
|---|---|---|
| 설정이 있는 곳 | C code 안 (`#define`) | UART 명령 |
| 조건을 바꾸려면 | app rebuild → reload | 명령 한 줄 |
| 만든 사람 | PJK | SJS |
| 쓰는 자리 | regression baseline, board 500-run benchmark | 실험, bring-up, 조건 sweep, 자동 test |

두 app 모두 bitstream과 Accelerator Core는 건드리지 않고 app만 바꿔 끼웁니다.

proof app 을 지우지 마십시오. PJK 가 board에서 통과시킨 다섯 scenario(APB / DMA / Single /
Enumeration / checkpoint)가 regression baseline이고, Bus Interface를 고칠 때마다 그 다섯을 다시 통과해야
baseline 교체를 논의할 수 있습니다. app 이름에 남은 `K4H8` 은 그 시절 이름이고 가리키는 것은
checkpoint 경로입니다.

```bash
cd $RVX_MINI_HOME/platform/bbht_grover_final/imp_arty-100t_<날짜>
make bbht_single.run
```

```
BBHT SINGLE SEARCH E2E TEST START
dataset addr = 0xe000597c
DMA_STATUS = 0x00000080
DMA LOAD PASS
SEARCH CONFIGURED
SEARCH START issued
STATUS = 0x0000080c
RESULT_INDEX = 120
SHOT_COUNT  = 1
REQUESTED_ITERATIONS       = 1
EXECUTED_ITERATIONS  = 1
CYCLE_COUNT  = 2126
BBHT SINGLE SEARCH E2E TEST PASS
```

`STATUS = 0x0000080c` 는 bit2 `done_sticky`, bit3 `result_valid`, bit11 `fifo_empty` 입니다.
정상 완료 · 결과 유효 · FIFO 빔입니다([13장 13.5절](13_csr_registers_and_execution_modes.md#135-status-0x024)).
board 500 runs는 `make bbht_paper_bench.run` 으로 돌린 것입니다.

---

## 17.6 console로 부리기

terminal을 붙이면(`screen /dev/ttyUSB1 115200` 또는 `minicom -D /dev/ttyUSB1 -b 115200`) 이렇게
나옵니다.

```
# bbht_console -- HELP 를 치면 명령 목록이 나옵니다
OK
```

한 번 돌려 보는 순서입니다. 응답과 field의 뜻은 [14장 14.5절](14_host_interface_and_uart_protocol.md#145-한-번-돌리는-전형적인-순서)에 있습니다.

```
ID
GEN COUNT=16384 TARGETS=1 VAL=12345
LOAD
SET MODE=EQ A=12345 AUTO=1 BURST=0 SEEDJ=0x7b1dcdaf SEEDM=0x24370df2
RUN
SET BURST=1
RUN
STAT
```

여러 명령을 한 번에 돌리거나 log를 남길 때는 host CLI 를 씁니다.

```bash
python3 software/host_fpga_develop/bbht_cli.py --port /dev/ttyUSB1 selftest
python3 software/host_fpga_develop/bbht_cli.py --port /dev/ttyUSB1 --script exp.txt --log run.log
```

네 predicate × 500 workloads를 통째로 돌려 Excel로 남기는 것은 `bbht_predicate500.py` 입니다
([18장](18_predicate500_automated_test.md)).

paired comparison에서 두 mode의 결과가 하나라도 다르면 그 결과를 쓰지 않습니다. 같은 seed에서 Restart mode와
Checkpoint mode가 다른 답을 냈다는 것은 checkpoint implementation이나 Bus Interface가 의미를 바꿨다는 signal입니다.

---

## 17.7 CSR 을 직접 두드릴 때 지킬 규약

RTL 과 driver가 이미 강제하지만, 직접 CSR 을 두드릴 때는 사람이 지켜야 합니다.

1. `COMMAND` 를 쓰기 전에 `STATUS` 를 확인합니다. start queue가 없어서 조건이 안 맞으면 pulse가 조용히
   버려집니다. 시작한 줄 알고 polling하면 직전 실행의 `done` 을 보고 낡은 결과를 읽습니다.
2. 완료 판정은 `done_sticky` 로 합니다. 그것을 지우는 것은 `COMMAND` 쓰기뿐입니다.
3. 결과는 `busy` 가 내려간 뒤에 읽습니다. 결과와 counter는 APB transaction 여러 번에 나눠 읽히므로,
   그 사이 새 실행이 시작되면 서로 다른 시점의 값이 섞입니다.
4. load 중에는 시작하지 않습니다. 절반만 채워진 array 위에서 oracle을 돌리면 경고 없이 그럴듯한
   non-solution이 나옵니다.
5. `FIFO_DATA` 는 읽는 것 자체가 pop 입니다. index 0 이 정상 결과일 수 있으므로 비었는지는
   `STATUS.fifo_empty` 나 `FIFO_COUNT` 로 봅니다. enumeration에서는 실행 중에도 계속 뽑아야 합니다.

C code에서 base address 를 숫자로 박지 않습니다. `bbht_grover_regs.h` 가
`I_GROVER_CSR_SLAVE_BASEADDR` 를 쓰도록 되어 있습니다.

---

## 17.8 잘 안 될 때

| 증상 | 먼저 볼 것 |
|---|---|
| terminal에 아무것도 안 나옴 | port를 잘못 골랐습니다. 뒤 번호(`/dev/ttyUSB1`) 쪽입니다 |
| 깨진 글자만 나옴 | baud rate 불일치. `SYSTEM_CLK_HZ` 를 바꿨는지 확인합니다 |
| `# 경고: CSR 응답이 이상합니다` | bitstream이 안 올라갔거나 base address 가 다릅니다. `make syn` 뒤 `memorymap_info.h` 를 다시 봅니다 |
| `ERR NOT_LOADED` | `LOAD` 를 안 했습니다. `GEN` 이나 `POKE` 뒤에는 반드시 `LOAD` |
| `ERR DMA_ERROR` | `REG` 로 `0x060`(`DMA_STATUS`)을 봅니다 ([13장 13.6절](13_csr_registers_and_execution_modes.md#136-dma_status-0x060)) |
| `ERR TIMEOUT` | search가 console의 polling 상한을 넘었습니다. `SET CAP=...` 을 조정합니다 |
| `MISS reason=SHOT_CAP` | 정상 동작입니다. solution이 없거나 shot cap에 걸린 것입니다 |
| host script가 응답을 못 받음 | search가 길면 대기 시간을 `SHOT_CAP` 에 맞춰 늘립니다 |
| 명령을 연달아 보냈더니 깨짐 | flow control이 없습니다. 응답을 받은 뒤 다음 명령이 규약입니다 |
| port를 다시 열었더니 echo조차 안 옴 (`ERR HOST_TIMEOUT`) | port를 열 때 DTR/RTS 가 켜지면 SoC 가 reset됩니다. app이 JTAG 로 올린 SRAM image뿐이라 다시 올려야 합니다. `bbht_cli.py` 는 2026-09-17 부터 열기 전에 둘을 내립니다. 다른 terminal을 쓴다면 같은 설정을 확인합니다 |
| Windows 에서 `--script` · `--log` 가 한글에서 죽음 | cp949 로 열던 것을 UTF-8 로 고쳤습니다. 옛 사본을 쓰고 있지 않은지 봅니다 |
| host 자동 test가 `platform=` 이 없다고 멈춤 | 옛 console입니다. 2026-09-25 revision의 `bbht_console.sram.hex` 를 올립니다 |

---

## 17.9 원격 200T board (AX7A200B)

2026-10-08 부터 configuration 사이 board benchmark는 원격 host `sdsl-fpga` 에 꽂힌 AX7A200B(`xc7a200tfbg484-2`)에서
합니다. 100 MHz accelerator · 50 MHz system clock이 Arty 와 같아 cycle과 wall-clock time이 같은 축으로 나옵니다.
Arty 100T 용 bitstream은 부품이 달라 구울 수 없으므로 200T 용으로 다시 구현합니다.

| 장치 | 원격에서 보이는 이름 | 쓰임 |
|---|---|---|
| FT232H (board JTAG) | Vivado hw_server | bitstream 굽기 |
| Olimex ARM-USB-TINY-H | `15ba:002a` (serial 쪽은 `/dev/ttyUSB1`) | `pjtag` pin(J11 3~7)으로 app load |
| CP2102N | `/dev/serial/by-id/*CP2102N*` (`/dev/ttyUSB2`) | UART 115200 8N1 |

원격 계정이 `dialout` group에 없어 serial은 sudo 로 엽니다. 흐름은 넷입니다.

```bash
hardware_bram/configurations/<configuration>/rvx/install_to_platform.sh     # 17.1절
/fpga-syn-rvx <platform> 100T 예산, 앱 bbht_paper_bench                     # 200T implementation (100T resource 예산)
hardware_bram/sim/board_run.sh <configuration> [앱]                                # 굽기 · load · 캡처 · bench500 대조
.claude/skills/fpga-flash/scripts/sdsl_fpga.sh restore --pcie            # 끝나면 반드시
```

`board_run.sh` 는 17.4절의 OCD 묶음을 configuration마다 만들어(memory map `arch/` 는 그 configuration의 platform에서) 원격으로
보내고, UART capture(`uart_capture.py`)를 먼저 띄운 뒤 OpenOCD 로 app을 올려 끝 표시 줄까지 기다립니다.
paper_bench 면 `board_vs_bench500.py` 로 그 configuration의 bench500 과 workload마다 맞댑니다. board는 line ending을
`\n\r` 로 보내므로 줄 머리의 `\r` 을 떼야 끝 표시를 알아봅니다.

board flash에는 다른 사람의 PCIe 설계(`10ee:7022`)가 들어 있습니다. benchmark를 마치면 `restore --pcie` 로
되돌리고, 오래 점유하는 benchmark(ORCA baseline 등)는 미리 일정을 맞춥니다. 굽은 실물은 각 configuration의
`bitstream/2026-10-08_ax7a200b/` 에 OCD 묶음과 함께 있습니다.

`restore` 는 **flash에 든 설계**를 다시 올립니다. benchmark 전에 누군가 JTAG 로 다른 설계를 올려 두었다면 그
설계로는 돌아가지 않습니다. 2026-10-11 에는 benchmark 전 BAR 두 개(user · config)이던 장치가 복구 뒤 BAR 하나
(config)로 잡혔습니다. 굽기 전에 `sdsl_fpga.sh check` 의 PCIe 줄과 원격 `dmesg` 의 xdma BAR 줄을 남겨 두고,
다르면 그 설계의 주인에게 알립니다.

ORCA software baseline처럼 몇 시간 걸리는 app은 `software/orca_grover_develop/tools/board_run.sh` 로 잽니다. 순서는
`board_run.sh` 와 같고, 원격 쪽을 session에서 떼어 놓아 ssh 가 끊겨도 capture가 계속됩니다. 쓰는 법은
[실험 19 「다시 재는 법」](../reports/19_orca_server_software_baseline.md#다시-재는-법)에 있습니다.

