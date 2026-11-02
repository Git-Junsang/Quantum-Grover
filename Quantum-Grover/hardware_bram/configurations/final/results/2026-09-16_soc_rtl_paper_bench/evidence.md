# SoC RTL simulation — 실제 RISC-V core가 우리 Bus Interface를 구동해 board cycle을 재현

## 무엇인가

RVX platform `bbht_grover_final`(당시 `bbht_grover_upgrade`) 전체(ORCA RISC-V core · micro NoC · APB/AHB NI ·
우리 Bus Interface · Accelerator Core)를 Questa 로 RTL simulation하고, 그 위에서 **board에 구운 것과
sha256 이 같은** `bbht_paper_bench.elf`(`f01c49a7…`)를 돌린 결과입니다.

앞선 verification은 전부 Bus Interface를 **testbench가 직접** 두드렸습니다 — verilator 의
`tb_bbht_rvx` · `tb_bbht_bram_top` · `tb_driver` · `bench250` · `bench500` 모두 그렇습니다.
이 묶음은 처음으로 **실제 CPU 가 NoC 를 거쳐** 두드린 것입니다. 우리 Bus Interface는
board에서 한 번도 돈 적이 없어서, 굽기 전에 이 접점을 보는 것이 목적이었습니다.

## 확정 수치

simulation은 3,000초 제한에 걸려 49분 45초 동안 261쌍을 돌았습니다
(1 · 4 solutions는 100 seeds 전부, 16 solutions는 61 seeds). 마지막 줄은 SIGTERM 에 잘려 버렸습니다.

**bench500 (verilator, 같은 Board-Verified Build core) 대비 — 5축 전부 일치**

| mode | result_index | trial_count | L_BBHT | actual_iter | cycle_count | cycle sum |
|---|---:|---:|---:|---:|---:|---:|
| mode0 Restart mode | 262/262 | 262/262 | 262/262 | 262/262 | **262/262** | 9,718,996 = 9,718,996 |
| mode1 final configuration | 261/261 | 261/261 | 261/261 | 261/261 | **261/261** | 4,089,796 = 4,089,796 |

**board 500 runs benchmark 대비 — mode1 은 cycle까지 일치**

| mode | BBHT trajectory 4축 | cycle_count | cycle sum |
|---|---:|---:|---:|
| mode1 final configuration | 261/261 전부 | **261/261** | 4,089,796 = 4,089,796 (+0.00%) |
| mode0 Restart mode | 262/262 전부 | 0/262 | 아래 설명 |

| number of solutions | runs | cycle 일치 (mode1 대 board final configuration) | cycle sum |
|---:|---:|---:|---:|
| 1 | 100 | 100/100 | 2,232,584 |
| 4 | 100 | 100/100 | 1,323,661 |
| 16 | 61 | 61/61 | 533,551 |

1 · 4 solutions의 cycle sum은 `results/2026-09-10_bench500_final_core/report.txt` 의
number of solutions별 표와 자릿수까지 같습니다. app 자신의 짝 검사도 `pair_fail=0 mismatch=0` 으로
끝났습니다.

**mode0 cycle이 board와 안 맞는 것은 결함이 아닙니다.** board의
`per_run_normal.csv` 는 같은 bitstream의 mode0 이 아니라 **Stage 1 configuration**에서 나온
것입니다 — 그 500 runs 합계 42,300,932 가 Six-Stage Ablation 의 Stage 1 RTL 합계
42,308,335 와 workload당 1~31 cycles 차이로 맞습니다
(`vivado/.../2026-09-08_k3h3_e4_m2_board_500run/evidence.md`). 여기 mode0 은
4 PEs에 checkpoint만 끈 것이라, 같은 configuration인 bench500 mode0과 262/262 로 맞는 것이
정상입니다.

## 그래서 무엇이 확인됐나

`CLAUDE.md` 2절이 "board에서 아직 확인하지 않았다" 고 적은 두 차이 중 **Bus Interface
교체**를, board 없이 확인할 수 있는 가장 가까운 곳에서 확인했습니다.

- 실제 CPU 가 RVX NoC 의 APB NI 를 거쳐 CSR 을 쓰고, AHB NI 를 거쳐 dataset을 load하고,
  결과를 읽어 오는 **전 경로**가 돕니다.
- 그 경로로 얻은 cycle이 testbench로 직접 두드린 값과 **한 cycle도 다르지 않습니다.**
  `CYCLE_COUNT` 는 Accelerator Core가 accelerator clock으로 세는 값이라, 이것이 같다는 것은 Bus Interface가
  search의 시작과 끝을 testbench와 똑같은 시점에 잡는다는 뜻입니다.
- 그리고 그 값이 **final configuration board benchmark와도** 같습니다.

`gclk_accel` 은 이 simulation에서도 `arch/rtl/src/bbht_grover_upgrade_rtl.v:1455` 의
`assign gclk_accel = clk_accel;` 로 순수 별칭입니다.

## 확인하지 않은 것

- **물리 UART.** simulation printf module(`ncsim_printf.v`)이 UART 를 115200 baud 로 받아 해독하므로
  framing은 simulation 안에서 돌았습니다. 그러나 FTDI · baud rate error · pin map은 board에서만 봅니다.
- **wall-clock time 축.** `timer_lo` 열은 simulation의 가상 시간이라 board `elapsed_us` 와 맞대면
  안 됩니다. 성능 인용은 `CLAUDE.md` 2절의 세 축을 쓰십시오.
- **16 solutions의 나머지 39 seeds와 64 · 256 solutions.** 시간 제한에 걸렸습니다. 같은 configuration의 verilator
  bench500 이 500/500 으로 통과했으므로 공백은 좁지만, SoC 경로로는 돌지 않았습니다.
- **`bbht_console` 명령 왕복.** 같은 날 따로 돌렸습니다 —
  [`2026-09-16_soc_rtl_console`](../2026-09-16_soc_rtl_console/evidence.md).

## 곁가지 — `bbht_console` 이 멈췄던 것은 시험 절차의 잘못이었습니다

처음에 이 절에는 "`bbht_console` 을 script mode로 돌리면 시작 banner `OK` 직후에 멈추고
원인을 찾지 못했다" 고 적었습니다. **틀린 기록입니다.** script mode 정의를 명령줄로만
넘겼는데 `make bbht_console.sim` 이 simulation 직전에 app을 다시 build하면서 그 정의가 빠졌고,
simulation에 실린 UART revision이 설계대로 입력을 기다린 것이었습니다(당시 build log에
`BBHT_CONSOLE_SCRIPT` 0번). `uart_init()` 가설 시험도 같은 이유로 실제로는 돌지 않았습니다.

app directory의 `rvx_each.mh` 로 RTL simulation build에만 정의를 넣도록 고친 뒤 console은 명령 21줄을
끝까지 돌았고, 결과는
[`2026-09-16_soc_rtl_console`](../2026-09-16_soc_rtl_console/evidence.md) 에 있습니다.

## file

| file | 내용 |
|---|---|
| `per_run.csv` | simulation이 UART 로 낸 `HW_REALTIME_CSV` 523 rows. 열 이름은 board `per_run_*.csv` 와 같고 `elapsed_us` 열만 없습니다 |
| `crosscheck.txt` | 위 표의 원문. `per_run.csv` 만으로 계산했습니다 |

## 재현

```bash
source /opt/rvx/rvx_setup.sh
# platform 준비는 vivado/vivado_bbht_grover_fpga/2026-09-16_comm_layer_rebuild/evidence.md 의 재현 절
cd $RVX_MINI_HOME/platform/bbht_grover_final
make sim_rtl
cd app/bbht_paper_bench && make rtl        # ELF sha256 이 f01c49a7… 인지 확인
cd ../../sim_rtl && make bbht_paper_bench.sim   # 500쌍 전부는 3시간 남짓
```
