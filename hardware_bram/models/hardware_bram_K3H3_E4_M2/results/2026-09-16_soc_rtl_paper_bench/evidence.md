# SoC RTL 시뮬 — 실제 RISC-V 코어가 우리 통신 계층을 구동해 보드 사이클을 재현

## 무엇인가

RVX 플랫폼 `bbht_grover_upgrade` 전체(ORCA RISC-V 코어 · micro NoC · APB/AHB NI ·
우리 통신 계층 · Main IP)를 Questa 로 RTL 시뮬하고, 그 위에서 **보드에 구운 것과
sha256 이 같은** `bbht_paper_bench.elf`(`f01c49a7…`)를 돌린 결과입니다.

앞선 검증은 전부 통신 계층을 **테스트벤치가 직접** 두드렸습니다 — verilator 의
`tb_bbht_rvx` · `tb_bbht_bram_top` · `tb_driver` · `bench250` · `bench500` 모두 그렇습니다.
이 묶음은 처음으로 **실제 CPU 가 NoC 를 거쳐** 두드린 것입니다. 우리 통신 계층은
보드에서 한 번도 돈 적이 없어서, 굽기 전에 이 접점을 보는 것이 목적이었습니다.

## 확정 수치

시뮬은 3,000초 제한에 걸려 49분 45초 동안 261쌍을 돌았습니다
(M = 1 과 4 는 100시드 전부, M = 16 은 61시드). 마지막 줄은 SIGTERM 에 잘려 버렸습니다.

**bench500 (verilator, 같은 정본 코어) 대비 — 5축 전부 일치**

| 모드 | result_index | trial_count | L_BBHT | actual_iter | cycle_count | 사이클 합 |
|---|---:|---:|---:|---:|---:|---:|
| mode0 NORMAL | 262/262 | 262/262 | 262/262 | 262/262 | **262/262** | 9,718,996 = 9,718,996 |
| mode1 K3/H3-E4-M2 | 261/261 | 261/261 | 261/261 | 261/261 | **261/261** | 4,089,796 = 4,089,796 |

**보드 500런 실측 대비 — mode1 은 사이클까지 일치**

| 모드 | 논리 4축 | cycle_count | 사이클 합 |
|---|---:|---:|---:|
| mode1 K3/H3-E4-M2 | 261/261 전부 | **261/261** | 4,089,796 = 4,089,796 (+0.00%) |
| mode0 NORMAL | 262/262 전부 | 0/262 | 아래 설명 |

| M | n | 사이클 일치 (mode1 대 보드 M2) | 합 |
|---:|---:|---:|---:|
| 1 | 100 | 100/100 | 2,232,584 |
| 4 | 100 | 100/100 | 1,323,661 |
| 16 | 61 | 61/61 | 533,551 |

M = 1 과 M = 4 의 합은 `results/2026-09-10_bench500_final_core/report.txt` 의
타겟수별 표와 자릿수까지 같습니다. 앱 자신의 짝 검사도 `pair_fail=0 mismatch=0` 으로
끝났습니다.

**mode0 사이클이 보드와 안 맞는 것은 결함이 아닙니다.** 보드의
`per_run_normal.csv` 는 같은 비트스트림의 mode0 이 아니라 **Normal-E1 구성**에서 나온
것입니다 — 그 500런 합계 42,300,932 가 6단계 ablation 의 Normal-E1 RTL 합계
42,308,335 와 워크로드당 1~31 사이클 차이로 맞습니다
(`vivado/.../2026-09-08_k3h3_e4_m2_board_500run/evidence.md`). 여기 mode0 은 연산기
네 벌(E4)에 체크포인트만 끈 것이라, 같은 구성인 bench500 normal 과 262/262 로 맞는 것이
정상입니다.

## 그래서 무엇이 확인됐나

`CLAUDE.md` 2절이 "보드에서 아직 확인하지 않았다" 고 적은 두 차이 중 **통신 계층
교체**를, 보드 없이 확인할 수 있는 가장 가까운 곳에서 확인했습니다.

- 실제 CPU 가 RVX NoC 의 APB NI 를 거쳐 CSR 을 쓰고, AHB NI 를 거쳐 데이터셋을 적재하고,
  결과를 읽어 오는 **전 경로**가 돕니다.
- 그 경로로 얻은 사이클이 테스트벤치로 직접 두드린 값과 **한 사이클도 다르지 않습니다.**
  `CYCLE_COUNT` 는 Main IP 가 가속기 클럭으로 세는 값이라, 이것이 같다는 것은 통신 계층이
  탐색의 시작과 끝을 테스트벤치와 똑같은 시점에 잡는다는 뜻입니다.
- 그리고 그 값이 **보드 실측 M2 와도** 같습니다.

`gclk_accel` 은 이 시뮬에서도 `arch/rtl/src/bbht_grover_upgrade_rtl.v:1455` 의
`assign gclk_accel = clk_accel;` 로 순수 별칭입니다.

## 확인하지 않은 것

- **물리 UART.** 시뮬 printf 모듈(`ncsim_printf.v`)이 UART 를 115200 baud 로 받아 해독하므로
  프레이밍은 시뮬 안에서 돌았습니다. 그러나 FTDI · 보율 오차 · 핀맵은 보드에서만 봅니다.
- **실경과 시간 축.** `timer_lo` 열은 시뮬의 가상 시간이라 보드 `elapsed_us` 와 맞대면
  안 됩니다. 성능 인용은 `CLAUDE.md` 2절의 세 축을 쓰십시오.
- **M = 16 나머지 39시드와 M = 64 · 256.** 시간 제한에 걸렸습니다. 같은 구성의 verilator
  bench500 이 500/500 으로 통과했으므로 공백은 좁지만, SoC 경로로는 돌지 않았습니다.
- **`bbht_console` 명령 왕복.** 같은 날 따로 돌렸습니다 —
  [`2026-09-16_soc_rtl_console`](../2026-09-16_soc_rtl_console/evidence.md).

## 곁가지 — `bbht_console` 이 멈췄던 것은 시험 절차의 잘못이었습니다

처음에 이 절에는 "`bbht_console` 을 스크립트 모드로 돌리면 시작 배너 `OK` 직후에 멈추고
원인을 찾지 못했다" 고 적었습니다. **틀린 기록입니다.** 스크립트 모드 정의를 명령줄로만
넘겼는데 `make bbht_console.sim` 이 시뮬 직전에 앱을 다시 빌드하면서 그 정의가 빠졌고,
시뮬에 실린 UART 판이 설계대로 입력을 기다린 것이었습니다(당시 빌드 로그에
`BBHT_CONSOLE_SCRIPT` 0번). `uart_init()` 가설 시험도 같은 이유로 실제로는 돌지 않았습니다.

앱 폴더의 `rvx_each.mh` 로 RTL 시뮬 빌드에만 정의를 넣도록 고친 뒤 콘솔은 명령 21줄을
끝까지 돌았고, 결과는
[`2026-09-16_soc_rtl_console`](../2026-09-16_soc_rtl_console/evidence.md) 에 있습니다.

## 파일

| 파일 | 내용 |
|---|---|
| `per_run.csv` | 시뮬이 UART 로 낸 `HW_REALTIME_CSV` 523행. 열 이름은 보드 `per_run_*.csv` 와 같고 `elapsed_us` 열만 없습니다 |
| `crosscheck.txt` | 위 표의 원문. `per_run.csv` 만으로 계산했습니다 |

## 재현

```bash
source /opt/rvx/rvx_setup.sh
# 플랫폼 준비는 vivado/vivado_bbht_grover_fpga/2026-09-16_comm_layer_rebuild/evidence.md 의 재현 절
cd $RVX_MINI_HOME/platform/bbht_grover_upgrade
make sim_rtl
cd app/bbht_paper_bench && make rtl        # ELF sha256 이 f01c49a7… 인지 확인
cd ../../sim_rtl && make bbht_paper_bench.sim   # 500쌍 전부는 3시간 남짓
```
