# 2장. 개발 환경과 toolchain

> [← 1장 project 개요](01_project_overview.md) · [index](index.md) · [3장 Grover와 BBHT algorithm →](03_grover_and_bbht_algorithm.md)

---

이 장은 저장소를 build하고 simulation을 돌리고 implementation하는 데 쓰는 도구와 그 사용법을 다룹니다.
각 명령이 무엇을 확인하는지는 [16장](16_verification_framework.md), board에 굽고 부리는 절차는
[17장](17_board_operation.md)에 있습니다.

---

## 2.1 도구의 역할과 version

도구는 역할이 셋으로 갈립니다.

| 도구 | 역할 |
|---|---|
| RVX | platform 생성부터 SoC RTL simulation, synthesis·implementation·bitstream까지 전 과정 |
| Verilator | 저장소 regression 전용. SoC 없이 wrapper와 Accelerator Core만 빠르게 돌립니다 |
| Qiskit · NumPy | RTL 밖에서 도는 reference. 결과가 맞는지 대조하는 데만 씁니다 |

이 환경에서 직접 확인한 version입니다 (RVX·Verilator 2026-08-21, Vivado 2026-08-22,
Qiskit 2026-09-03, regression 2026-09-09).

| 도구 | version | 쓰는 자리 |
|---|---|---|
| `verilator` | 5.020 | hardware directory tree의 `sim/` regression 전체 |
| `vsim` (Questa) | 2022.1_2 | RVX `make sim_rtl` (SoC 전체) |
| `vivado` | 2026.1 (node-locked) | `xc7a100tcsg324-1` synthesis·implementation·bitstream |
| RISC-V GCC | RVX 동봉 | ORCA core용 firmware |
| RVX | `/opt/rvx` local 전체 설치 | platform 생성·simulation·implementation. 원격 접속 불필요 |
| `iverilog` / `vvp` | 12.0 | 설치만 되어 있고 저장소에서 쓰는 곳이 없습니다 |
| qiskit / qiskit-aer | 2.5.2 / 0.17.2 | reference model 대조 ([4장](04_software_reference_model_and_test_vectors.md)) |

Board-Verified Build bitstream(2026-09-07)은 Vivado 2024.2로 구웠습니다. 지금 환경은 2026.1이라 두
build의 bitstream hash를 비교할 수 없습니다([19장](19_synthesis_implementation_bitstream.md)).

### 환경 제약

- headless입니다. `gtkwave`, Vivado GUI, RVX `make view` 는 설치 여부와 무관하게 띄울 수
  없습니다. Vivado는 `-mode batch` 또는 `-mode tcl` 로만 돌리고, waveform은 file로 남겨
  내려받아 봅니다.
- 저장소 경로에 공백이 있습니다 (`중앙대학교 학부인턴`). GNU Make가 공백 있는 directory에서
  Verilator 생성 Makefile을 돌리지 못하므로 `sim/Makefile` 이 `--Mdir /tmp/...` 로 build
  directory를 뺍니다. 이 설정은 유지해야 합니다.

---

## 2.2 저장소 regression: Verilator

`hardware_*/testbench/` 에는 testbench source만 있고 Makefile이 없습니다. entry point는
`hardware_bram/sim/Makefile` · `hardware_dram/sim/Makefile`, 그리고 configuration 전용 regression이 있는
`no_checkpoint_baseline` configuration의 `sim/Makefile` 이고, Verilator를 직접 부를 일은 새 testbench를 세울 때뿐입니다.

```bash
# BRAM Variant (hardware_bram). adapter가 들어가는 target은 CONFIGURATION=<configuration>, 기본값 final
make -C hardware_bram/sim ports lint regress driver   # Bus Interface + 자리 채우개 (몇 초)
make -C hardware_bram/sim real [CONFIGURATION=capacity4_lookahead4_pes4_singlerow_linear]        # Bus Interface + configuration adapter + Accelerator Core (몇 분)
make -C hardware_bram/sim ports-configurations lint-configurations    # configuration adapter 전부 (몇 분)
make -C hardware_bram/sim top                         # 최상단 bbht_bram_top (1분 30초쯤)
make -C hardware_bram/sim bench250                    # 250쌍 BBHT trajectory testbench (20분쯤)
make -C hardware_bram/sim predicate500 console-gen    # 네 predicate x 500 (수 분)

# checkpoint 없는 판 (no_checkpoint_baseline configuration 전용 regression)
make -C hardware_bram/configurations/no_checkpoint_baseline/sim                           # ports + lint + real
make -C hardware_bram/configurations/no_checkpoint_baseline/sim predicate500 predicate500-ref equiv

# DRAM Variant (hardware_dram)
make -C hardware_dram/sim                                        # ports lint store prep core top (1분 30초쯤)
make -C hardware_dram/sim equiv                                  # checkpoint 판과 BBHT trajectory 대조 (40초 더)
make -C hardware_dram/sim predicate500 [AXI_STALL=1]             # AXI memory configuration 위 2,000 실행
```

모든 directory tree가 CSR 생성 header(`spec/generated/`)를 씁니다. RTL 네 곳과 testbench 세
곳이 `bbht_grover_csr.vh` 를, `bbht_grover_driver.h` 가 `bbht_grover_regs.h` 를 include 하므로
header가 없으면 아무것도 돌지 않습니다. checkpoint revision은 모든 target이 `csr:`(`gen_csr.py --check`)를,
No-Checkpoint Baseline은 `csr:`(생성)를 선행 조건으로 먼저 돌립니다. 생성 pipeline은
[13장](13_csr_registers_and_execution_modes.md)에 있습니다.

Six-Stage Ablation과 Checkpoint-Capacity · Lookahead-Shots 단독 실험은 standalone top 틀을 쓰므로 main에 없습니다. tag에서
worktree를 따로 꺼내 돌립니다. tag 안의 directory 이름은 옛 이름 `hardware_bram/` 그대로입니다.

```bash
git worktree add /tmp/board board-verified-build-2026-09-07
make -C /tmp/board/hardware_bram/sim anchor      # publication · kh 도 같은 자리
```

### Verilator를 직접 부를 때

새 testbench를 세울 때의 형태입니다.

```bash
verilator --cc -Wno-fatal --Mdir /tmp/mytb -Isrc src/bbht_rvx_wrapper.v \
          --exe tb.cpp --build -j 4 -o sim_tb
/tmp/mytb/sim_tb
```

option 두 개가 빠지면 안 됩니다.

- `-Isrc`: header(`bbht_grover_csr.vh`, `grover_param.vh`)를 찾는 include 경로이자 하위 module
  search 경로입니다. module 이름과 file 이름이 같아서 이 하나로 해결되고 `*.v` 를 나열할 필요가
  없습니다.
- `-Wno-fatal`: 없으면 경고 몇 건으로 `%Error: Exiting due to N warning(s)` 가 나며 build가
  죽습니다.

`-Wno-fatal` 로 경고를 묻으면 선언 누락이 조용히 1-bit로 잘립니다. Two-Track Execution 실험에서
16-bit signal이 그렇게 잘려 한나절을 쓴 적이 있으니, 새 signal 연결을 넣은 뒤에는 경고 목록을 한 번
읽으십시오.

상대경로 file이 `-I` directory 기준으로 먼저 찾아진다는 점도 주의합니다. No-Checkpoint Baseline의
`sim/Makefile` 이 자기 adapter를 `/tmp` 로 복사해 절대경로로 넘기는 이유가 이것입니다
([20장](20_no_checkpoint_baseline.md)).

testbench C++는 clock을 직접 toggle하고 매번 `eval()` 을 부릅니다. 입력 port를 전부
initialize해야 하고(안 하면 X로 시작합니다), `shready` 는 1로 두어야 AHB가 멈추지 않습니다.
reset은 `rstnn` 입니다(실물 Accelerator Core 쪽 `rstn` 과의 차이는 adapter가 흡수합니다).

```cpp
#include "Vbbht_rvx_wrapper.h"
#include "verilated.h"
#include <cstdio>

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vbbht_rvx_wrapper* dut = new Vbbht_rvx_wrapper;

    dut->clk = 0; dut->rstnn = 0;
    dut->psel = 0; dut->penable = 0; dut->pwrite = 0;    // APB
    dut->paddr = 0; dut->pwdata = 0;
    dut->shready = 1; dut->shresp = 0; dut->shrdata = 0; // AHB master가 받는 쪽

    for (int i = 0; i < 8; i++) { dut->clk = !dut->clk; dut->eval(); }
    dut->rstnn = 1;

    for (int c = 0; c < 1000; c++) {
        dut->clk = 0; dut->eval();
        dut->clk = 1; dut->eval();
    }
    printf("prdata=%08x\n", (unsigned)dut->prdata);
    delete dut;
    return 0;
}
```

waveform이 필요하면 `--trace` 를 붙여 build하고, `VerilatedVcdC` 를 열어 매 `eval()` 뒤에
`dump()` 합니다. 만든 VCD는 내려받아 local에서 엽니다.

```cpp
#include "verilated_vcd_c.h"

Verilated::traceEverOn(true);
VerilatedVcdC* tfp = new VerilatedVcdC;
dut->trace(tfp, 99);
tfp->open("wave.vcd");
// loop 안에서 eval() 뒤에
tfp->dump(main_time++);
// 끝나고
tfp->close();
```

---

## 2.3 RVX platform

RVX는 `/opt/rvx` 에 전부 설치되어 있습니다. 새 terminal마다 한 번 환경을 잡습니다.

```bash
source /opt/rvx/rvx_setup.sh
```

따를 예제는 `platform/tip_quantized_cnn/` 입니다. accelerator를 `user/rtl` · `user/api` 에 두는
구조가 우리와 같습니다.

### platform 셋

BRAM configuration마다, 그리고 DRAM Variant에 RVX platform이 하나씩 있고, 각자의
`rvx/install_to_platform.sh` 가 자기 platform에 설치합니다. BRAM configuration의 설치 script는 공용 installer
[`hardware_bram/rvx/install_model.sh`](../../hardware_bram/rvx/install_model.sh) 를 부릅니다. configuration별
platform 이름은 [5장 5.2절](05_hardware_architecture_overview.md#hardware-directory-tree와-bram-configuration) 표에 있습니다.

| directory tree | platform | platform 정의 |
|---|---|---|
| `hardware_bram/` 의 `final` | `bbht_grover_final` | [`bbht_grover_final.xml`](../../hardware_bram/configurations/final/rvx/bbht_grover_final.xml) (accelerator 100 MHz) |
| `hardware_bram/` 의 다른 configuration 아홉 | `bbht_grover_<모델 소문자>` · `bbht_grover_no_checkpoint_baseline` | SoC 구성은 upgrade와 같음 |
| `hardware_dram/` | `bbht_grover_dram` | `include_slow_dram` · `use_large_ram_manually` 추가 ([21장](21_dram_variant.md)) |

```bash
hardware_bram/configurations/final/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_final
make syn        # XML 로부터 RTL · system software 생성
make sim_rtl    # Questa simulation 작업방 생성
make imp_fpga TARGET_IMP_CLASS=arty-100t && cd imp_arty-100t_<날짜> && make imp && make bbht_console
```

설치 script가 옮기는 것과 platform directory를 처음 만드는 절차는 [17장 17.1절](17_board_operation.md#171-platform-설치와-생성)에
있습니다. `hardware_bram/rvx/bbht_grover_user_region.vh.generated` 는 RVX `make syn` 이 뽑은 빈 template이고,
RVX가 IP를 바꿨을 때 우리 user region과 대조하는 용도입니다. synthesis에는
`src/bbht_grover_user_region.vh` 를 씁니다.

### 새 platform을 처음부터 만들 때

```bash
cd $RVX_MINI_HOME/platform
make copy_platform BEFORE=tip_quantized_cnn AFTER=grover_soc   # accelerator IP 예제 복제
cd grover_soc && vim grover_soc.xml                             # IP instance와 parameter
make syn
cd app && make new APP_NAME=grover && cd ..                     # app 뼈대
make sim_rtl && (cd sim_rtl && make grover.sim)                 # RTL simulation
make arty-100t && cd imp_arty-100t_<날짜> && make imp           # synthesis·implementation
```

### 명령은 어디서 치느냐로 갈립니다

| 위치 | 명령 | 하는 일 |
|---|---|---|
| `platform/` | `make new PLATFORM_NAME=<이름>` · `make copy_platform BEFORE=.. AFTER=..` | 새 platform · 복제 |
| `<platform>/` | `make syn` | XML → RTL · system software 생성 |
| `<platform>/` | `make sim_rtl` · `make arty-100t` | simulation 작업방 · implementation 작업방 생성 |
| `<platform>/` | `make fpga_list` · `make clean` | board 목록 · 산출물 정리 |
| `<platform>/app/` | `make new APP_NAME=<앱>` | 새 app |
| `sim_rtl/` | `make <앱>.sim` | build + RTL compile + simulation |
| `sim_rtl/` | `make <앱>.resim` · `make <앱>.all` | app만 다시 · 전부 처음부터 |
| `sim_rtl/` | `make <앱>.debug` · `make <앱>.debug_init` | waveform 남기며 · boot 순간부터 waveform |
| `sim_rtl/` | `make compile_test` · `compile_test_all` · `compile_check` | RTL 문법만 · 하나씩(빠진 include 찾기) · 실패한 것만 |
| `imp_*/` | `make project` · `make imp` · `make reimp` · `make check_imp` | project · bitstream · 다시 · report 확인 |
| `imp_*/` | `make program` · `make program_flash` | board에 굽기 · SPI flash에 굽기 |
| `imp_*/` | `make printf` · `make <앱>.run` | UART console · build 후 board에서 실행 |

접미사 없는 `make <앱>` 은 `sim_rtl/` 에서는 `.sim` 과 같고, `imp_*/` 에서는 build만 합니다.
`make download` 라는 target은 없습니다. build mode는 기본 `debug` 이고
`make <앱>.sim BUILD_MODE=release` 처럼 바꿉니다(`debug` · `release` · `profile`).

`make fpga_list` 에는 `arty-100t` 를 포함해 여덟 board가 나옵니다. RVX CLI manual은 두 board만
적고 있지만 설치본을 믿으십시오. 우리 board는 `arty-100t` 입니다.

### SoC simulation 결과 읽기

`make <앱>.sim` 이 끝나면 log 끝에 이렇게 나옵니다.

```
# [RVX/START] SIM@RTL
# Hello World!
# [PROC_STATUS]  1 cores have finished @  426794000 ns
# Errors: 0, Warnings: 0
```

`[RVX/START]` 이후가 app의 `main()` 입니다. 이 줄 앞에서 멈췄다면 app이 아니라 platform·boot
문제입니다. `main()` 이 return 하면 simulation이 끝납니다.

### SoC simulation에서 console app을 돌리는 법

`bbht_console` 의 UART build는 SoC simulation에서 `read_line()` 에 멈춥니다. RVX의 `ncsim_printf.v` 가
`uart_tx` 를 1로 묶어 두어 명령을 보낼 쪽이 없기 때문입니다. 그래서
[`rvx_each.mh`](../../hardware_bram/firmware/bbht_console/rvx_each.mh) 가 RTL simulation build
(`TARGET_IMP_CLASS=rtl`)에만 `-DBBHT_CONSOLE_SCRIPT` 를 넣고, console은 명령을 compile 시점
array에서 읽습니다. board build ELF는 byte 단위로 그대로입니다. script는
`BBHT_SCRIPT=<헤더>` 로 고릅니다.

```bash
(cd $RVX_MINI_HOME/platform/bbht_grover_final/sim_rtl && make bbht_console.sim)   # 3분쯤
grep -c BBHT_CONSOLE_SCRIPT $RVX_MINI_HOME/platform/bbht_grover_final/sim_rtl/rvx_app_build.log
```

두 가지를 지킵니다.

- 이 정의를 명령줄의 `DEFINE_CFLAGS` 로 넘기지 마십시오. `make bbht_console.sim` 이 simulation 직전에
  app을 다시 build하면서 빠지고, UART build가 첫 명령을 기다리며 멈춥니다. 위 grep이 0이면
  script mode가 아닙니다. 이 증상을 한동안 "원인 미확인 멈춤" 으로 잘못 기록했고, 진단
  순서는 [soc_rtl_console evidence](../../hardware_bram/configurations/final/results/2026-09-16_soc_rtl_console/evidence.md)
  에 남겼습니다.
- script만 바꿔 다시 돌릴 때는 app build directory(`app/bbht_console/rtl.debug`)를 지우십시오.
  `BBHT_SCRIPT` 는 compile macro라 make가 바뀐 것을 모르고 앞서 build한 object를 씁니다.
  `rvx_app_build.log` 에 고른 script file 이름이 찍혔는지 확인합니다.

응답 검사 절차는 [16장 16.5절](16_verification_framework.md#165-3층-soc-전체-rtl-simulation)에 있습니다.

---

## 2.4 Vivado

RVX의 `make project` · `make imp` 가 안에서 부르는 것이 Vivado입니다. 따로 준비할 것 없이
`vivado` 로 바로 부릅니다.

| 항목 | 값 |
|---|---|
| version | `vivado v2026.1` (`/usr/local/bin/vivado` wrapper가 `/tools/Xilinx/2026.1/Vivado/bin/vivado` 를 부름) |
| license | 노드락 `/opt/xilinx-lic/Xilinx.lic`. `XILINXD_LICENSE_FILE` 은 `/etc/profile.d/eda-tools.sh` 에서 잡힘 |
| license 기능 | `Vivado_Synthesis` · `Vivado_Implementation` · `Vivado_Simulation` · `Vivado_Basic_Package` |
| 만료 | 2027-08-21 |
| part | Artix-7 설치됨. `xc7a100tcsg324-1` 사용 가능 (2026-08-28 `synth_design` benchmark) |

license는 이 container `eth0` 의 MAC(`bc2411359cb8`)에 묶여 있습니다. container를 새로 만들어
MAC이 바뀌면 AMD license portal에서 새 host ID로 다시 발급받아 `/opt/xilinx-lic/` 에
넣어야 합니다. host ID는 `cat /sys/class/net/eth0/address` 로 확인합니다.

### IP 하나만 synthesis해 resource를 잴 때

```bash
cat > run.tcl <<'EOF'
read_verilog [glob ../src/*.v]
synth_design -top bbht_rvx_wrapper -part xc7a100tcsg324-1 -include_dirs {../src}
opt_design
place_design
route_design
report_utilization -file util.rpt
report_timing_summary -file timing.rpt
EOF

vivado -mode batch -nojournal -nolog -source run.tcl
```

`src/` 를 통째로 읽으면 `grover_policy_ooc_top.v` 와 `grover_policy_impl_wrapper.v` 때문에
최상위 후보가 셋이 됩니다. `-top` 을 줬으니 synthesis는 되지만, 최상위를 하나로 두려면 두 file을
빼십시오. pin constraint 없이 `write_bitstream` 까지 가면 placement되지 않은 IO 때문에 DRC에서 멈추므로, resource만
볼 때는 `route_design` 까지면 충분합니다.

Accelerator Core만 final configuration parameter로 재는 것은 script로 있습니다.

```bash
hardware_bram/synth/run_main_ip.sh      # 2분쯤
```

결과를 [resource ablation study 묶음](../../hardware_bram/results/2026-09-08_resource_ablation_5config/evidence.md)
의 기대값과 나란히 보여 줍니다([19장 19.3절](19_synthesis_implementation_bitstream.md#193-accelerator-core-resource-다시-재기)).

---

## 2.5 software reference model과 host 도구

### Qiskit 설치 현황

CT 200 · CT 205 두 container에 같은 version이 올라가 있습니다.

| qiskit | aer | numpy | scipy | matplotlib |
|---|---|---|---|---|
| 2.5.2 | 0.17.2 | 2.4.6 | 1.18.0 | 3.11.1 |

virtual environment 없이 `/usr/local/lib/python3.12/dist-packages` 에 넣었으므로 어디서든 `python3` 로
바로 부릅니다. system Python이 PEP 668로 잠겨 있어 container를 새로 만들면 flag를 붙여
되살립니다. numpy · scipy는 dependency로 딸려 옵니다.

```bash
pip3 install --break-system-packages qiskit==2.5.2 qiskit-aer==0.17.2 matplotlib==3.11.1
python3 -c "import qiskit, qiskit_aer; print(qiskit.__version__, qiskit_aer.__version__)"
```

`qiskit_algorithms` 는 깔려 있지 않습니다. `from qiskit_algorithms import Grover` 로 시작하는
예제는 돌지 않으니 `grover_operator` 로 직접 조립합니다([4장 4.6절](04_software_reference_model_and_test_vectors.md#46-qiskit과-numpy로-대조하기)).
matplotlib 기본 backend가 `agg` 라 그림은 창 대신 `filename=` 으로 저장합니다.

### Common500 재실행

Common500은 Python virtual environment에 [`software/reference_model_develop/common500/requirements.txt`](../../software/reference_model_develop/common500/requirements.txt)를
설치한 뒤 돌립니다. NumPy · Qiskit까지 전부 돌리면 수 시간이고, 끊겨도 같은 명령이 이어서
돕니다. 절차는 [실험 14](../reports/14_common500_software_fpga_comparison.md).

```bash
bash software/reference_model_develop/common500/run_full_benchmark.sh
python3 software/reference_model_develop/predicate500/run_predicate500_golden.py   # 30초쯤
```

### host CLI

board가 없어도 두 가지 대체 transport로 돌릴 수 있습니다.

```bash
python3 software/host_fpga_develop/bbht_cli.py --port mock selftest             # Python model. 수치 인용 금지
python3 software/host_fpga_develop/bbht_cli.py --port replay:<트랜스크립트> -c ID -c RUN
```

`replay:` 는 SoC simulation transcript를 실제 parser에 그대로 먹입니다. transport 셋의 차이는
[14장 14.6절](14_host_interface_and_uart_protocol.md#146-host-cli-의-세-transport).

---

## 2.6 정합성 검사

관련 file을 고친 뒤에는 다음 검사를 돌려 오류가 없는지 확인합니다.

```bash
python3 spec/gen_csr.py --check              # CSR source of truth 대조 (갱신 없이)
make -C hardware_bram/sim ports ports-real     # port 계약 대조
python3 documents/check_docs.py                           # 문서 정합성 (오류 0건이어야 함)
```

diagram을 고쳤으면 render도 같이 합니다.

```bash
python3 documents/design_references/render_diagrams.py
python3 documents/study_references/render_diagrams.py
```

각 검사가 잡는 것과 못 잡는 것은 [16장 16.8절](16_verification_framework.md#168-자동-정합성-검사)에 있습니다.

---

## 2.7 증상별 대처

| 증상 | 대처 |
|---|---|
| Vivado `valid license was not found` | `echo $XILINXD_LICENSE_FILE` 가 `/opt/xilinx-lic` 인지, host ID(MAC)가 바뀌지 않았는지 (2.4절) |
| Vivado GUI · `make view` · `gtkwave` 가 안 뜸 | headless. `-mode batch` 로 돌리고 `vsim.wlf` · VCD는 내려받아 local에서 엶 |
| RVX 명령이 variable을 못 찾음 | `source /opt/rvx/rvx_setup.sh` |
| `vsim` 의 `ADDR_NO_RANDOMIZE failed` 경고 | 무시해도 됩니다 |
| SoC simulation에서 console이 첫 명령을 기다리며 멈춤 | script mode가 build에 안 들어갔습니다 (2.3절) |
| Verilator가 경고만 있는데 종료 code 1 | `-Wno-fatal` |
| Verilator `Cannot find include file: grover_param.vh` | `-I` 로 `src` 를 안 넣었습니다 |
| Verilator 산출물이 옛 revision이라 이상함 | `make -C hardware_bram/sim clean` (build directory는 `/tmp`) |
| pip가 `externally-managed-environment` 로 거부 | `--break-system-packages` (2.5절) |
| `ModuleNotFoundError: qiskit_algorithms` | 안 깔려 있습니다. `grover_operator` 로 직접 조립 |
| `DeprecationWarning: Diagonal` · `PhaseOracle` | `DiagonalGate` · `PhaseOracleGate` 로 ([4장 4.6절](04_software_reference_model_and_test_vectors.md#46-qiskit과-numpy로-대조하기)) |
