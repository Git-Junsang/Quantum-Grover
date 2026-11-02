# SoC RTL simulation — board console이 네 predicate dataset을 스스로 만들고 host runner가 채점

## 무엇인가

RVX platform `bbht_grover_final` 전체(ORCA RISC-V core · micro NoC · APB/AHB NI ·
Bus Interface · final configuration Accelerator Core)를 Questa로 RTL simulation하면서, 2026-09-25 revision의
`bbht_console`을 script mode로 돌린 결과입니다. script는 board 자동 test
`software/host_fpga_develop/bbht_predicate500.py`가 board에 보낼 명령을 **그 runner가 직접 뽑은 것**
(`--emit-script`)이고, transcript는 같은 runner의 재생 transport로 다시 먹여 채점했습니다.

```
bbht_predicate500.py --emit-script  ->  script_predicate500.h (명령 50줄)
    -> SoC RTL 시뮬 (bbht_console 스크립트 모드)  ->  transcript.txt
    -> bbht_predicate500.py --port replay:transcript.txt  ->  replay.csv / replay.xlsx
```

board에서 runner가 COM port로 할 일을 한 글자도 바꾸지 않고 SoC 위에서 한 바퀴 돈 것입니다.
이번 revision에서 새로 생긴 경로 셋이 여기서 처음 실제 CPU 위에서 돌았습니다.

- `GEN PRED= A= B=` — firmware가 네 predicate dataset을 board 안에서 만듦
  (`firmware/bbht_console/src/bbht_dataset_gen.h`)
- `SUM` — 만든 dataset의 FNV-1a hash와 number of solutions를 보고
- `RUN` 응답의 `wall_us=` — `bbht_search_single_timed()`가 COMMAND 쓰기부터 DONE 확인까지 잰 값

## workload

네 predicate × 256 solutions × seed 0·1 × Restart mode · Checkpoint mode = **16 실행**. seed와 threshold는
[`2026-09-25_predicate500_rtl`](../2026-09-25_predicate500_rtl/evidence.md)과 같습니다.
256 solutions 하나만 고른 것은 SoC simulation이 느려서입니다(16 실행에 21분 44초).

## 확정 수치

| 검사 | 결과 |
|---|---|
| `SUM`의 FNV-1a 대 software 생성기 (`predicate500_datasets.csv`) | 4/4 (LT `0xa569173a` · GT `0x13d60bf9` · EQ `0xdca4f97c` · RANGE `0x0d48036a`) |
| `SUM`의 number of solutions | 4/4가 256 |
| `result_index` · `trial_count` · `L_BBHT` · `actual_iter` 대 software reference model | 16/16 |
| 찾은 값이 predicate를 만족 | 16/16 |
| `ERR` · `MISS` | 0 |
| cycle 대 Verilator [`2026-09-25_predicate500_rtl/per_workload.csv`](../2026-09-25_predicate500_rtl/per_workload.csv) | 15/16 같음. 나머지 1건은 +3,279 |

cycle이 다른 한 건은 **LT seed 0의 Checkpoint mode**입니다(SoC 6,095 대 Verilator 2,816).
script에서 reset 뒤 처음 도는 Checkpoint mode search라, Policy Engine이 memo table BRAM을 지우는
3,279 cycles(`LOOKAHEAD_SHOTS × STATE_RANKS = 3 × 1,093`)를 치른 것입니다.
Verilator harness는 같은 process 안에서 1 solution부터 돌아와 256 solutions에 닿을 때는 이미
치른 뒤입니다. 원인은 [`2026-09-16_soc_rtl_console`](../2026-09-16_soc_rtl_console/evidence.md)
에서 확인한 것과 같습니다.

| predicate | Restart mode cycle (seed 0 + 1) | Checkpoint mode cycle (seed 0 + 1) |
|---|---:|---:|
| LT | 9,880 | 10,288 (Verilator 7,009 + 3,279) |
| GT | 3,384 | 2,807 |
| EQ | 8,475 | 5,976 |
| RANGE | 7,220 | 5,373 |

## `wall_us`에 대해

SoC simulation의 `wall_us`는 RVX 실시간 timer를 simulation 시간으로 읽은 값이라, board에서 잴
wall-clock time과 같은 뜻입니다. 이 simulation에서는 cycle 환산값 `us=`보다 5~7 µs 큽니다.
COMMAND를 쓰고 DONE을 polling해 보기까지 CPU가 50 MHz NoC를 오가는 값입니다.
**simulation이므로 성능 인용처가 아닙니다.** board에서 runner를 돌리면 같은 열이 benchmark로 채워집니다.

## build 확인

| 확인 | 결과 |
|---|---|
| `sim_rtl/rvx_app_build.log`의 `BBHT_CONSOLE_SCRIPT` | 76번 (script mode로 build됨) |
| script | `firmware/bbht_console/src/script_predicate500.h` (`BBHT_SCRIPT=`로 선택) |
| simulation | `QUIT`까지 가서 정상 종료, Questa Errors 0 · Warnings 0 |

## 재현

```bash
source /opt/rvx/rvx_setup.sh
hardware_bram/configurations/final/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_final/sim_rtl
BBHT_SCRIPT=script_predicate500.h make bbht_console.sim          # 22분쯤
python3 software/host_fpga_develop/bbht_predicate500.py --port replay:qtsim.log --targets 256 --seeds 2
```

## file

| file | 내용 |
|---|---|
| `transcript.txt` | Questa log에서 console 부분(`[RVX/START]`부터 종료까지)만 떼어 `# ` 접두를 벗긴 것. 이것만으로도 재생됩니다 |
| `replay.csv` | runner가 재생으로 채점한 16 rows (board 실행과 같은 열) |
| `replay.xlsx` | 같은 내용의 Excel (sheet `요약` · `M별 요약` · `실행별` · `데이터셋` · `환경`) |
