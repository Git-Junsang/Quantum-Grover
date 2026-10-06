# SoC RTL 시뮬 — 보드 콘솔이 네 술어 데이터셋을 스스로 만들고 호스트 러너가 채점

## 무엇인가

RVX 플랫폼 `bbht_grover_upgrade` 전체(ORCA RISC-V 코어 · micro NoC · APB/AHB NI ·
통신 계층 · K3/H3-E4-M2 Main IP)를 Questa 로 RTL 시뮬하면서, 2026-09-25 판
`bbht_console` 을 스크립트 모드로 돌린 결과입니다. 스크립트는 보드 자동 테스트
`software/host/bbht_predicate500.py` 가 보드에 보낼 명령을 **그 러너가 직접 뽑은 것**
(`--emit-script`)이고, 트랜스크립트는 같은 러너의 재생 트랜스포트로 다시 먹여 채점했습니다.

```
bbht_predicate500.py --emit-script  ->  script_predicate500.h (명령 50줄)
    -> SoC RTL 시뮬 (bbht_console 스크립트 모드)  ->  transcript.txt
    -> bbht_predicate500.py --port replay:transcript.txt  ->  replay.csv / replay.xlsx
```

보드에서 러너가 COM 포트로 할 일을 한 글자도 바꾸지 않고 SoC 위에서 한 바퀴 돈 것입니다.
이번 판에서 새로 생긴 경로 셋이 여기서 처음 실제 CPU 위에서 돌았습니다.

- `GEN PRED= A= B=` — 펌웨어가 네 술어 데이터셋을 보드 안에서 만듦
  (`firmware/bbht_console/src/bbht_dataset_gen.h`)
- `SUM` — 만든 데이터셋의 FNV-1a 해시와 정답 수를 보고
- `RUN` 응답의 `wall_us=` — `bbht_search_single_timed()` 가 COMMAND 쓰기부터 DONE 확인까지 잰 값

## 워크로드

네 술어 × M = 256 × 시드 0·1 × Normal·체크포인트 = **16 실행**. 시드와 임계값은
[`2026-09-25_predicate500_rtl`](../2026-09-25_predicate500_rtl/evidence.md) 과 같습니다.
M = 256 하나만 고른 것은 SoC 시뮬이 느려서입니다(16 실행에 21분 44초).

## 확정 수치

| 검사 | 결과 |
|---|---|
| `SUM` 의 FNV-1a 대 SW 생성기 (`predicate500_datasets.csv`) | 4/4 (LT `0xa569173a` · GT `0x13d60bf9` · EQ `0xdca4f97c` · RANGE `0x0d48036a`) |
| `SUM` 의 정답 수 | 4/4 가 256 |
| `result_index` · `trial_count` · `L_BBHT` · `actual_iter` 대 SW 기준모델 | 16/16 |
| 찾은 값이 술어를 만족 | 16/16 |
| `ERR` · `MISS` | 0 |
| 사이클 대 verilator [`2026-09-25_predicate500_rtl/per_workload.csv`](../2026-09-25_predicate500_rtl/per_workload.csv) | 15/16 같음. 나머지 1건은 +3,279 |

사이클이 다른 한 건은 **LT 시드 0 의 체크포인트** 입니다(SoC 6,095 대 verilator 2,816).
스크립트에서 리셋 뒤 처음 도는 체크포인트 탐색이라, 정책 엔진이 memo BRAM 을 지우는
3,279 사이클(`H_FUTURE × STATE_RANKS = 3 × 1,093`)을 치른 것입니다.
verilator 하네스는 같은 프로세스 안에서 M = 1 부터 돌아와 M = 256 에 닿을 때는 이미
치른 뒤입니다. 원인은 [`2026-09-16_soc_rtl_console`](../2026-09-16_soc_rtl_console/evidence.md)
에서 확인한 것과 같습니다.

| 술어 | Normal 사이클 (시드 0 + 1) | 체크포인트 사이클 (시드 0 + 1) |
|---|---:|---:|
| LT | 9,880 | 10,288 (verilator 7,009 + 3,279) |
| GT | 3,384 | 2,807 |
| EQ | 8,475 | 5,976 |
| RANGE | 7,220 | 5,373 |

## `wall_us` 에 대해

SoC 시뮬의 `wall_us` 는 RVX 실시간 타이머를 시뮬 시간으로 읽은 값이라, 보드에서 잴
실경과 시간과 같은 뜻입니다. 이 시뮬에서는 사이클 환산값 `us=` 보다 5~7 us 큽니다.
COMMAND 를 쓰고 DONE 을 폴링해 보기까지 CPU 가 50 MHz NoC 를 오가는 값입니다.
**시뮬이므로 성능 인용처가 아닙니다.** 보드에서 러너를 돌리면 같은 열이 실측으로 채워집니다.

## 빌드 확인

| 확인 | 결과 |
|---|---|
| `sim_rtl/rvx_app_build.log` 의 `BBHT_CONSOLE_SCRIPT` | 76번 (스크립트 모드로 빌드됨) |
| 스크립트 | `firmware/bbht_console/src/script_predicate500.h` (`BBHT_SCRIPT=` 로 선택) |
| 시뮬 | `QUIT` 까지 가서 정상 종료, Questa Errors 0 · Warnings 0 |

## 재현

```bash
source /opt/rvx/rvx_setup.sh
hardware_bram/models/hardware_bram_K3H3_E4_M2/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_upgrade/sim_rtl
BBHT_SCRIPT=script_predicate500.h make bbht_console.sim          # 22분쯤
python3 software/host/bbht_predicate500.py --port replay:qtsim.log --targets 256 --seeds 2
```

## 파일

| 파일 | 내용 |
|---|---|
| `transcript.txt` | Questa 로그에서 콘솔 부분(`[RVX/START]` 부터 종료까지)만 떼어 `# ` 접두를 벗긴 것. 이것만으로도 재생됩니다 |
| `replay.csv` | 러너가 재생으로 채점한 16행 (보드 실행과 같은 열) |
| `replay.xlsx` | 같은 내용의 엑셀 (요약 · M별 요약 · 실행별 · 데이터셋 · 환경) |
