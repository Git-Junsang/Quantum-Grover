# SoC RTL 시뮬 — 체크포인트 없는 판에서 콘솔 16실행, 사이클까지 verilator 와 16/16

## 무엇인가

RVX 플랫폼 `bbht_grover_nocheckpoint` 전체를 Questa 로 RTL 시뮬하면서 2026-09-25 판
`bbht_console` 을 스크립트 모드로 돌린 결과입니다. 플랫폼에는 ORCA RISC-V 코어, micro NoC,
APB/AHB NI, 통신 계층, Normal-E4 Main IP 가 들어 있습니다. 흐름은 체크포인트 판
[`2026-09-25_soc_rtl_predicate500`](../../../hardware_bram_K3H3_E4_M2/results/2026-09-25_soc_rtl_predicate500/evidence.md)
과 같습니다. 보드에서 호스트 러너가 COM 포트로 할 일을 SoC 위에서 한 바퀴 돈 것입니다.

```
bbht_predicate500.py 가 뽑은 명령 (script_predicate500_dram.h 와 같은 66줄)
    -> SoC RTL 시뮬 (bbht_console 스크립트 모드)  ->  transcript.txt
    -> bbht_predicate500.py --port replay:transcript.txt  ->  replay.csv / replay.xlsx
```

## 워크로드

네 술어 × M = 64 · 256 × 시드 0·1 × Normal 로 **16 실행**입니다. 이 판은 Normal 만 도는 것이
DRAM 갈래와 같습니다. 그래서 명령 순서가 한 줄도 다르지 않아 DRAM 스크립트를 그대로 썼고,
두 SoC 결과를 같은 워크로드로 나란히 볼 수 있습니다. 16 실행에 38분 15초 걸렸습니다.

## 확정 수치

| 검사 | 결과 |
|---|---|
| `ID` 의 플랫폼 | `platform=bbht_grover_nocheckpoint` (러너가 nocheckpoint 갈래로 알아보고 Normal 만 계획) |
| `SUM` 의 FNV-1a 대 SW 생성기 | 8/8 (값은 [DRAM SoC 묶음](../../../../../hardware_dram/results/2026-09-25_soc_rtl_predicate500/evidence.md) 표와 같음) |
| `result_index` · `trial_count` · `L_BBHT` · `actual_iter` 대 SW 기준모델 | 16/16 (`actual_iter` 는 `actual_iter_normal` 열) |
| 찾은 값이 술어를 만족 | 16/16 |
| `ERR` · `MISS` | 0 |
| **사이클 대 verilator** [`2026-09-25_predicate500_rtl/per_workload.csv`](../2026-09-25_predicate500_rtl/per_workload.csv) | **16/16 같음** |
| Questa | `QUIT` 까지 가서 정상 종료, Errors 0 · Warnings 0 |

체크포인트 판 SoC 시뮬에서는 리셋 뒤 첫 체크포인트 탐색이 memo 청소 3,279 사이클만큼
verilator 와 달랐습니다. 이 판에는 정책 엔진이 없어서 그런 이력 의존이 없고, 사이클이 전부
같습니다.

| 술어 | 사이클 합 (4 실행) | `us=` 합 | `wall_us` 합 |
|---|---:|---:|---:|
| LT | 48,370 | 481 | 503 |
| GT | 29,671 | 294 | 318 |
| EQ | 37,632 | 374 | 398 |
| RANGE | 44,572 | 443 | 465 |

`wall_us` 는 실행마다 `us=` 보다 5~7 us 큽니다. CPU 가 COMMAND 를 쓰고 DONE 을 폴링해
보기까지 NoC 를 오가는 값으로, 체크포인트 판 SoC 시뮬과 같은 크기입니다. **시뮬이므로 성능
인용처가 아닙니다.**

## 빌드 확인

| 확인 | 결과 |
|---|---|
| `sim_rtl/rvx_app_build.log` 의 `BBHT_CONSOLE_SCRIPT` | 76번 (스크립트 모드로 빌드됨) |
| 스크립트 | `hardware_bram/firmware/bbht_console/src/script_predicate500_dram.h` |
| 첫 시도 | `make sim_rtl` 뒤 컴파일이 user region 헤더를 못 찾아 실패. RVX `user/` 뼈대(`set_sim_env.mh`)가 빠진 탓이었고, 설치 스크립트가 채우게 고친 뒤 다시 돌린 것이 이 묶음입니다 |

## 재현

```bash
source /opt/rvx/rvx_setup.sh
hardware_bram/models/hardware_bram_nocheckpoint/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_nocheckpoint && make sim_rtl
rm -rf app/bbht_console/rtl.debug
cd sim_rtl && BBHT_SCRIPT=script_predicate500_dram.h make bbht_console.sim     # 40분쯤
python3 software/host/bbht_predicate500.py --port replay:qtsim.log --targets 64,256 --seeds 2
```

## 파일

| 파일 | 내용 |
|---|---|
| `transcript.txt` | Questa 로그에서 콘솔 부분(`[RVX/START]` 부터 종료까지)만 떼어 `# ` 접두를 벗긴 것. 이것만으로도 재생됩니다 |
| `replay.csv` | 러너가 재생으로 채점한 16행 (보드 실행과 같은 열) |
| `replay.xlsx` | 같은 내용의 엑셀 (요약 · M별 요약 · 실행별 · 데이터셋 · 환경) |
