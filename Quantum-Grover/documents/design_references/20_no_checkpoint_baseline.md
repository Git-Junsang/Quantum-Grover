# 20장. No-Checkpoint Baseline

> [← 19장 synthesis · implementation · bitstream](19_synthesis_implementation_bitstream.md) · [index](index.md) · [21장 DRAM Variant →](21_dram_variant.md)

---

BRAM Variant의 final configuration은 4 PEs 위에 checkpoint(a Checkpoint-Capacity of 3, 3-shot Lookahead)와 measurement 최적화(Dual-Row Build · Two-Level Select)를 얹은
configuration입니다. 이 revision은 그중 **4 PEs만 남기고 나머지 최적화를 모두 끈 것**입니다.
같은 board · 같은 SoC · 같은 PE 위에서 최적화를 켰을 때와 껐을 때의 속도를 맞대려는
baseline이고, 새 algorithm이 아닙니다.

이 revision은 2026-09-25 에 따로 만든 directory tree였고, 2026-10-06 부터는 BRAM Variant의 한 configuration
`hardware_bram/configurations/no_checkpoint_baseline/` 입니다.

---

## 20.1 final configuration과 다른 점

10 configurations 사이의 자리는 [5장 5.2절](05_hardware_architecture_overview.md#hardware-directory-tree와-bram-configuration)에
있습니다. final configuration(`final`)과는 compile parameter만 다릅니다.

| parameter | final configuration | No-Checkpoint Baseline |
|---|:-:|:-:|
| `CHECKPOINT_ENABLE` | 1 | **0** |
| `CHECKPOINT_CAPACITY` · `LOOKAHEAD_SHOTS` | 3 · 3 | (쓰이지 않음) |
| `NUMBER_OF_PES` | 4 | 4 |
| `BUILD_ROWS_PER_CYCLE` · `USE_TWO_LEVEL_SELECT` | 2 · 1 | **1 · 0** |

---

## 20.2 source를 어떻게 나눴나

이 revision은 source를 거의 갖지 않습니다. 다른 configuration처럼 Bus Interface · Accelerator Core · user region · firmware는
`hardware_bram/` 공용 것을 **그대로** 쓰고, 이 revision에만 있는 RTL 은 adapter 하나입니다.

| file | 역할 |
|---|---|
| `src/bbht_grover_core_adapter.v` | final configuration adapter와 port · wiring이 같고 다른 것은 둘. parameter 기본값(위 표), 그리고 `burst_enable` 을 Accelerator Core에 0 으로 넘기는 것 |
| `sim/Makefile` · `sim/equiv_check.py` | regression · Predicate500 · 기준 대조 (20.4절) |
| `rvx/bbht_grover_no_checkpoint_baseline.xml` · `rvx/install_to_platform.sh` | RVX platform. SoC 구성은 `bbht_grover_final` 과 같음. 설치는 공용 설치기가 함 |

Accelerator Core를 복사하지 않은 이유는 두 revision이 **같은 RTL 을 parameter만 달리 compile한 것**이어야
비교가 공정하기 때문입니다. 복사본을 두면 한쪽만 고쳐지는 순간 비교가 깨집니다. Stage 1
(`capacity0_pes1_singlerow_linear`)도 같은 adapter에서 4 PEs를 1 PE로 바꾼 것입니다.

`burst_enable` 을 막는 이유: `CHECKPOINT_ENABLE=0` 인 Accelerator Core에 `burst_enable=1` 을 주면
`grover_bbht` 의 옛 Single-Slot Checkpoint(v0.8 burst)가 살아납니다. 그것도 amplitude를
재활용하는 최적화라 이 revision의 취지와 맞지 않고, 4 PEs 위에서는 검증한 적도 없습니다. 그래서
`SET BURST=1` 을 보내도 Restart mode로 돕니다. DRAM Variant가 BURST 를 무시하는 것과 같은 약속이고,
host 자동 test는 `ID` 의 `platform=bbht_grover_no_checkpoint_baseline` 를 보고 Restart mode만 돌립니다.

---

## 20.3 Accelerator Core에서 바꾼 것 — 4 PEs를 checkpoint에서 떼어 냄

전에는 4 PEs와 Dual-Row Build · Two-Level Select가 `CHECKPOINT_ENABLE=1` 일 때만 생겼습니다. checkpoint를 끄면
1 PE로 돌아가 버려서, "checkpoint만 뺀" revision을 만들 수 없었습니다.

`hardware_bram/src/bbht_grover_main_ip.v` 에서 세 곳을 고쳤습니다.

| 자리 | 전 | 후 |
|---|---|---|
| 4 PEs generate 조건 | `NUMBER_OF_PES == 4 && CHECKPOINT_ENABLE != 0` | `NUMBER_OF_PES == 4` |
| measurement module `AMP_READ_LATENCY` | `CHECKPOINT_ENABLE ? 2 : 1` | `(CHECKPOINT_ENABLE \|\| NUMBER_OF_PES == 4) ? 2 : 1` |
| `E4_DUAL_BUILD` · `E4_HIER_SELECT` | 4 PEs · checkpoint · Measurement Microarchitecture switch | 4 PEs · Measurement Microarchitecture switch |

이렇게 해도 되는 근거는 이미 RTL 안에 있었습니다. final configuration에서 Restart mode를 돌리면
`ckpt_exec_mode=0` 이라 4 PEs amplitude memory의 읽기 · 쓰기 · measurement의 checkpoint slot이 모두 0 으로 묶이고,
Checkpoint Planner · Checkpoint Executor · Policy Engine은 쉬고 있습니다. checkpoint를 끈 revision은 그 쉬는 hardware를
generate 로 뺀 것일 뿐, 도는 경로는 같습니다. `CHECKPOINT_ENABLE=1` 에서는 세 식 모두
전과 같은 값이 되므로 final configuration은 바뀌지 않습니다(20.4절에서 확인).

2 PEs는 여전히 checkpoint가 있어야 생깁니다. 이 revision에 필요하지 않아서 건드리지 않았습니다.

---

## 20.4 verification

| 단계 | 결과 | 근거 |
|---|---|---|
| port 계약 | wrapper 19 + core 61 일치 (`check_ports.py no_checkpoint_baseline`) | `make -C hardware_bram/configurations/no_checkpoint_baseline/sim ports` |
| Bus Interface 계약 T1~T10 (실물 core) | 오류 0. T10 의 burst request가 Restart mode와 같은 121,427 cycles, policy counter 0 | `make -C hardware_bram/configurations/no_checkpoint_baseline/sim real` |
| Predicate500 대 software reference model | Restart mode 2,000/2,000, 여섯 축 전부 | [`hardware_bram/configurations/no_checkpoint_baseline/results/2026-09-25_predicate500_rtl/`](../../hardware_bram/configurations/no_checkpoint_baseline/results/2026-09-25_predicate500_rtl/evidence.md) |
| checkpoint만 뺐는가 | final configuration RTL을 Single-Row Build · Linear Select로 build한 Restart mode(지금의 Stage 4 configuration `capacity3_lookahead3_pes4_singlerow_linear`, `predicate500-ref`)와 **cycle · STATUS 까지 8 열 2,000/2,000** | 같은 묶음 `equiv.txt` |
| final configuration이 안 바뀌었는가 | `ports lint regress real top` 통과, Predicate500 4,000 rows가 2026-09-25 결과와 전 열 같음 | [`hardware_bram/configurations/final/results/2026-09-25_predicate500_rtl/`](../../hardware_bram/configurations/final/results/2026-09-25_predicate500_rtl/evidence.md) 와 대조 |
| SoC RTL simulation | console 16실행이 software reference model과 16/16, dataset hash 8/8, cycle도 verilator 와 16/16 같음 | [`hardware_bram/configurations/no_checkpoint_baseline/results/2026-09-25_soc_rtl_predicate500/`](../../hardware_bram/configurations/no_checkpoint_baseline/results/2026-09-25_soc_rtl_predicate500/evidence.md) |
| implementation | 100 MHz WNS +0.193 ns | [`vivado/.../2026-09-25_nocheckpoint_build/`](../../hardware_bram/configurations/no_checkpoint_baseline/vivado/vivado_bbht_grover_nocheckpoint/2026-09-25_nocheckpoint_build/evidence.md) |
| board (2026-10-04) | Restart mode 2,000/2,000, RTL testbench와 cycle까지 2,000/2,000 | [`vivado/.../2026-10-04_board_predicate500/`](../../hardware_bram/configurations/no_checkpoint_baseline/vivado/vivado_bbht_grover_nocheckpoint/2026-10-04_board_predicate500/evidence.md) |

한 번 헛디딘 것을 적어 둡니다. 처음 `make real` 은 이 revision의 adapter를
`../src/bbht_grover_core_adapter.v` 로 넘겼는데, verilator 는 relative path file을 `-I`
directory 기준으로 먼저 찾아서 **final configuration adapter**를 집어 왔습니다. T10 에 policy
counter가 찍혀서 알아챘고, 지금은 adapter를 `/tmp` 로 복사해 absolute path로 넘기고 parameter
값을 grep 으로 확인합니다. Predicate500 build는 처음부터 build directory에 복사해 썼으므로
영향이 없었습니다.

---

## 20.5 최적화 유무에 따른 속도 (RTL cycle)

같은 2,000 workloads, 같은 harness, accelerator 100 MHz cycle입니다.

| configuration | 네 predicate sum | 이 revision 대비 |
|---|---:|---:|
| No-Checkpoint Baseline (4 PEs) | 61,109,590 | 1.000× |
| final configuration, Restart mode (4 PEs, Dual-Row Build · Two-Level Select) | 46,886,677 | 1.303× |
| final configuration, Checkpoint mode | 21,093,126 | **2.897×** |

measurement 최적화 Dual-Row Build · Two-Level Select가 약 1.3×, checkpoint가 그 위에 약 2.2×를 벌어 합쳐서 약 2.9×입니다.
1 solution에서 3.04×, 256 solutions에서 2.46×로, 희소할수록 checkpoint 몫이 큽니다. predicate별 · number of solutions별
표는 [결과 묶음](../../hardware_bram/configurations/no_checkpoint_baseline/results/2026-09-25_predicate500_rtl/evidence.md)에
있습니다.

이것은 **RTL cycle 축**입니다. Six-Stage Ablation(EQ 한 predicate, a Checkpoint-Capacity of 4와 4-shot Lookahead를 거친 ablation study)과는
단계가 달라 speedup을 섞으면 안 됩니다.

같은 비교를 2026-10-04 에 board wall-clock time으로 했습니다. 두 bitstream을 같은 board에 차례로
굽고 `bbht_predicate500.py` 로 같은 2,000 workloads를 돌렸습니다.

| configuration | wall-clock time sum | 이 revision 대비 wall-clock time | 이 revision 대비 board cycle |
|---|---:|---:|---:|
| No-Checkpoint Baseline (4 PEs) | 621,210 µs | 1.000× | 1.000× |
| final configuration, Restart mode (4 PEs, Dual-Row Build · Two-Level Select) | 478,975 µs | 1.297× | 1.303× |
| final configuration, Checkpoint mode | 221,032 µs | **2.810×** | 2.897× |

board cycle speedup은 위 RTL 표와 같습니다. wall-clock time speedup이 조금 작은 것은 실행마다 붙는 고정
4~7 µs 때문입니다. number of solutions별로는 1 solution에서 3.00×, 256 solutions에서 2.25×입니다
([실험 16](../reports/16_three_revisions_board_predicate500.md)).

SoC RTL simulation(실제 RISC-V 가 console을 돌림)은 DRAM Variant와 같은 16실행(네 predicate × 64 · 256 solutions ×
2 seeds × Restart mode)으로 돌려 16/16 맞았고, cycle도 verilator 와 16/16 같습니다. 결과는
[`hardware_bram/configurations/no_checkpoint_baseline/results/2026-09-25_soc_rtl_predicate500/`](../../hardware_bram/configurations/no_checkpoint_baseline/results/2026-09-25_soc_rtl_predicate500/evidence.md)
에 있습니다.

---

## 20.6 resource

| 항목 (전체 SoC) | No-Checkpoint Baseline | final configuration (2026-09-16) |
|---|---:|---:|
| WNS | +0.193 ns | +0.196 ns |
| LUT / FF | 38,133 / 38,634 | 45,116 / 45,210 |
| BRAM tile / DSP | 111 / 68 | 116 / 132 |

DSP 64 개 차이는 전부 measurement block입니다(Dual-Row Build가 cycle당 두 row의 Born-rule square를 계산하므로 multiplier가 두
배). BRAM 은 policy memo table 만큼만 줄었습니다. 4 PEs amplitude memory는 checkpoint slot 0 만 쓰지만, 736-bit row를
담는 RAMB36 은 폭으로 개수가 정해져 깊이를 줄여도 BRAM tile이 줄지 않습니다.

---

## 20.7 돌리는 법

```bash
# simulation (저장소 루트)
make -C hardware_bram/configurations/no_checkpoint_baseline/sim                     # ports + lint + real
make -C hardware_bram/configurations/no_checkpoint_baseline/sim predicate500 predicate500-ref equiv

# RVX platform과 bitstream
source /opt/rvx/rvx_setup.sh
mkdir -p $RVX_MINI_HOME/platform/bbht_grover_no_checkpoint_baseline
cp $RVX_MINI_HOME/platform/tip_hello/Makefile $RVX_MINI_HOME/platform/bbht_grover_no_checkpoint_baseline/
hardware_bram/configurations/no_checkpoint_baseline/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_no_checkpoint_baseline
make syn && make imp_fpga TARGET_IMP_CLASS=arty-100t
cd imp_arty-100t_<날짜> && make imp && make bbht_console     # 7분쯤

# board (굽기와 app 올리기는 bitstream 묶음 설명대로)
python3 software/host_fpga_develop/bbht_predicate500.py --port /dev/ttyUSB1   # Restart mode 2,000 실행
```

RVX `user/` 뼈대를 빠진 것만 채우는 이유는 [17장 17.1절](17_board_operation.md#171-platform-설치와-생성)에 있습니다.
