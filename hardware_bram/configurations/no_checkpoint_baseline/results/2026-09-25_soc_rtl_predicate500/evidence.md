# SoC RTL simulation — No-Checkpoint Baseline에서 console 16실행, cycle까지 verilator 와 16/16

## 무엇인가

RVX platform `bbht_grover_no_checkpoint_baseline`(당시 `bbht_grover_nocheckpoint`) 전체를 Questa 로 RTL simulation하면서 2026-09-25 revision
`bbht_console` 을 script mode로 돌린 결과입니다. platform에는 ORCA RISC-V core, micro NoC,
APB/AHB NI, Bus Interface, No-Checkpoint Baseline Accelerator Core가 들어 있습니다. 흐름은 final configuration의
[`2026-09-25_soc_rtl_predicate500`](../../../final/results/2026-09-25_soc_rtl_predicate500/evidence.md)
과 같습니다. board에서 host runner가 COM port로 할 일을 SoC 위에서 한 바퀴 돈 것입니다.

```
bbht_predicate500.py 가 뽑은 명령 (script_predicate500_dram.h 와 같은 66줄)
    -> SoC RTL simulation (bbht_console script mode)  ->  transcript.txt
    -> bbht_predicate500.py --port replay:transcript.txt  ->  replay.csv / replay.xlsx
```

## workload

네 predicate × 64 · 256 solutions × seed 0·1 × Restart mode로 **16 실행**입니다. 이 configuration은 Restart mode만 도는 것이
DRAM Variant와 같습니다. 그래서 명령 순서가 한 줄도 다르지 않아 DRAM script를 그대로 썼고,
두 SoC 결과를 같은 workload로 나란히 볼 수 있습니다. 16 실행에 38분 15초 걸렸습니다.

## 확정 수치

| 검사 | 결과 |
|---|---|
| `ID` 의 platform | `platform=bbht_grover_nocheckpoint` (runner가 No-Checkpoint Baseline으로 알아보고 Restart mode만 계획) |
| `SUM` 의 FNV-1a 대 software 생성기 | 8/8 (값은 [DRAM SoC 묶음](../../../../../hardware_dram/results/2026-09-25_soc_rtl_predicate500/evidence.md) 표와 같음) |
| `result_index` · `trial_count` · `L_BBHT` · `actual_iter` 대 software reference model | 16/16 (`actual_iter` 는 `actual_iter_normal` 열) |
| 찾은 값이 predicate를 만족 | 16/16 |
| `ERR` · `MISS` | 0 |
| **cycle 대 verilator** [`2026-09-25_predicate500_rtl/per_workload.csv`](../2026-09-25_predicate500_rtl/per_workload.csv) | **16/16 같음** |
| Questa | `QUIT` 까지 가서 정상 종료, Errors 0 · Warnings 0 |

final configuration SoC simulation에서는 reset 뒤 첫 checkpoint search가 memo table 청소 3,279 cycles만큼
verilator 와 달랐습니다. 이 configuration에는 Policy Engine이 없어서 그런 이력 의존이 없고, cycle이 전부
같습니다.

| predicate | cycle sum (4 실행) | `us=` sum | `wall_us` sum |
|---|---:|---:|---:|
| LT | 48,370 | 481 | 503 |
| GT | 29,671 | 294 | 318 |
| EQ | 37,632 | 374 | 398 |
| RANGE | 44,572 | 443 | 465 |

`wall_us` 는 실행마다 `us=` 보다 5~7 µs 큽니다. CPU 가 COMMAND 를 쓰고 DONE 을 polling해
보기까지 NoC 를 오가는 값으로, final configuration SoC simulation과 같은 크기입니다. **simulation이므로 성능
인용처가 아닙니다.**

## build 확인

| 확인 | 결과 |
|---|---|
| `sim_rtl/rvx_app_build.log` 의 `BBHT_CONSOLE_SCRIPT` | 76번 (script mode로 build됨) |
| script | `hardware_bram/firmware/bbht_console/src/script_predicate500_dram.h` |
| 첫 시도 | `make sim_rtl` 뒤 compile이 user region header를 못 찾아 실패. RVX `user/` 뼈대(`set_sim_env.mh`)가 빠진 탓이었고, 설치 script가 채우게 고친 뒤 다시 돌린 것이 이 묶음입니다 |

## 재현

```bash
source /opt/rvx/rvx_setup.sh
hardware_bram/configurations/no_checkpoint_baseline/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_no_checkpoint_baseline && make sim_rtl
rm -rf app/bbht_console/rtl.debug
cd sim_rtl && BBHT_SCRIPT=script_predicate500_dram.h make bbht_console.sim     # 40분쯤
python3 software/host_fpga_develop/bbht_predicate500.py --port replay:qtsim.log --targets 64,256 --seeds 2
```

## file

| file | 내용 |
|---|---|
| `transcript.txt` | Questa log에서 console 부분(`[RVX/START]` 부터 종료까지)만 떼어 `# ` 접두를 벗긴 것. 이것만으로도 재생됩니다 |
| `replay.csv` | runner가 재생으로 채점한 16 rows (board 실행과 같은 열) |
| `replay.xlsx` | 같은 내용의 Excel (요약 · number of solutions별 요약 · 실행별 · dataset · 환경) |
