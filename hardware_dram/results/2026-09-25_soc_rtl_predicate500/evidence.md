# SoC RTL 시뮬 — DRAM 갈래가 실제 NoC 와 DDR 모델 위에서 네 술어 16/16

## 무엇인가

RVX 플랫폼 `bbht_grover_dram` 전체를 Questa 로 RTL 시뮬한 결과입니다. 여기에는 ORCA
RISC-V 코어, micro NoC, APB/AHB NI, MIG `slow_dram` 의 시뮬 DDR 모델, 통신 계층, DRAM 갈래
Main IP, 32비트 AXI4 브리지가 모두 들어 있습니다. 그 위에서 2026-09-25 판
`bbht_console` 을 스크립트 모드로 돌렸습니다. 흐름은 bram 쪽
[`2026-09-25_soc_rtl_predicate500`](../../../hardware_bram/models/hardware_bram_K3H3_E4_M2/results/2026-09-25_soc_rtl_predicate500/evidence.md)
과 같습니다.

```
bbht_predicate500.py --emit-script  ->  script_predicate500_dram.h
    -> SoC RTL 시뮬 (bbht_console 스크립트 모드)  ->  transcript.txt
    -> bbht_predicate500.py --port replay:transcript.txt  ->  replay.csv / replay.xlsx
```

verilator 의 AXI 메모리 모델([`2026-09-25_predicate500_axi`](../2026-09-25_predicate500_axi/evidence.md))은
AXI 규칙대로만 움직이는 이상적인 상대였습니다. 여기서는 RVX 가 실제로 만든 NoC 와 DDR
컨트롤러 경로가 상대입니다.

첫 시도에서는 가속기가 멈췄습니다. NoC 가 16 beat 보다 긴 쓰기를 쪼개고 조각마다 B 를
돌려준 것이 원인이었습니다. 이 묶음은 브리지를 16 beat 버스트로 고친 뒤의 결과입니다.
경위는 [기술문서 22장 22.5절](../../../documents/design_references/22_DRAM_갈래.md#225-브리지-grover_dram_axi_bridgev)에 있습니다.

## 워크로드

네 술어 × M = 64 · 256 × 시드 0·1 × Normal 로 **16 실행**입니다. 이 갈래에는 체크포인트가
없습니다. 그래서 러너가 `ID` 의 `platform=bbht_grover_dram` 을 보고 Normal 만 돌립니다. 시드와 임계값은
[`hardware_bram/models/hardware_bram_K3H3_E4_M2/results/2026-09-25_predicate500_rtl`](../../../hardware_bram/models/hardware_bram_K3H3_E4_M2/results/2026-09-25_predicate500_rtl/evidence.md)
과 같습니다. 시뮬 DDR 모델은 2 MiB 라 `j` 43 까지만 담을 수 있습니다. 그래서 궤적이 그
안에 드는 M 두 값을 골랐습니다. 16 실행에 45분 36초 걸렸습니다.

## 확정 수치

| 검사 | 결과 |
|---|---|
| `SUM` 의 FNV-1a 대 SW 생성기 (`predicate500_datasets.csv`) | 8/8 |
| `SUM` 의 정답 수 | 8/8 이 M 과 같음 |
| `result_index` · `trial_count` · `L_BBHT` · `actual_iter` 대 SW 기준모델 | 16/16 |
| 찾은 값이 술어를 만족 | 16/16 |
| `ERR` · `MISS` · `HOST_TIMEOUT` | 0 |
| Questa | `QUIT` 까지 가서 정상 종료, Errors 0 · Warnings 0 |

물리 반복은 기댓값의 `actual_iter_dram_session` 열과 맞댔습니다. DRAM 진폭표는 다음
시드로 넘어가도 남아 있습니다. 그래서 같은 데이터셋 안에서는 앞 시드가 채운 `j` 를 다시
씁니다.

| 데이터셋 | FNV-1a |
|---|---|
| LT M=64 / 256 | `0x8e060871` / `0xa569173a` |
| GT M=64 / 256 | `0x29a01211` / `0x13d60bf9` |
| EQ M=64 / 256 | `0xefb2e98e` / `0xdca4f97c` |
| RANGE M=64 / 256 | `0x4f2d645d` / `0x0d48036a` |

## 사이클은 verilator 와 다릅니다 (궤적은 같습니다)

같은 16 워크로드를 verilator AXI 모델 하네스(`per_workload_stall0.csv`)와 맞대 보았습니다.
`result_index` 와 `actual_iter` 는 16/16 같습니다. 사이클은 16건 중 15건이 1.35~1.42배입니다.
나머지 한 건(GT M=256 시드 1)은 물리 반복이 0 이라 DRAM 을 건드리지 않고, 사이클도 2,505 로
같습니다.

| 술어 | SoC 사이클 합 | verilator 사이클 합 | 배수 |
|---|---:|---:|---:|
| LT | 476,696 | 340,993 | 1.398 |
| GT | 244,611 | 176,369 | 1.387 |
| EQ | 341,470 | 244,601 | 1.396 |
| RANGE | 378,834 | 269,819 | 1.404 |

차이는 전부 메모리 지연에서 옵니다. AXI 모델은 고정 지연을 씁니다. SoC 에서는 요청이
150 MHz NoC 를 건너 MIG 시뮬 모델까지 갔다 옵니다. 이 값은 시뮬 DDR 모델 기준이라 보드의
DDR3 지연과도 다를 수 있습니다. **성능 인용처가 아니며**, 궤적 대조의 근거로만 씁니다.

## 빌드 확인

| 확인 | 결과 |
|---|---|
| `sim_rtl/rvx_app_build.log` 의 `BBHT_CONSOLE_SCRIPT` | 76번 (스크립트 모드로 빌드됨) |
| 스크립트 | `hardware_bram/firmware/bbht_console/src/script_predicate500_dram.h` |
| 앱 빌드 폴더 | 시뮬 전에 `app/bbht_console/rtl.debug` 를 지움. 스크립트가 컴파일 매크로로 들어가 make 가 바뀐 것을 모르기 때문 |

## 재현

```bash
source /opt/rvx/rvx_setup.sh
hardware_dram/rvx/install_to_platform.sh
rm -rf $RVX_MINI_HOME/platform/bbht_grover_dram/app/bbht_console/rtl.debug
cd $RVX_MINI_HOME/platform/bbht_grover_dram/sim_rtl
BBHT_SCRIPT=script_predicate500_dram.h make bbht_console.sim          # 46분쯤
python3 software/host/bbht_predicate500.py --port replay:qtsim.log --targets 64,256 --seeds 2
```

이번에는 세션과 떼어 `setsid nohup` 으로 돌렸습니다. 시뮬이 길어서, 그렇게 하지 않으면
터미널이 닫힐 때 같이 죽습니다.

## 파일

| 파일 | 내용 |
|---|---|
| `transcript.txt` | Questa 로그에서 콘솔 부분(`[RVX/START]` 부터 종료까지)만 떼어 `# ` 접두를 벗긴 것. 이것만으로도 재생됩니다 |
| `replay.csv` | 러너가 재생으로 채점한 16행 (보드 실행과 같은 열) |
| `replay.xlsx` | 같은 내용의 엑셀 (요약 · M별 요약 · 실행별 · 데이터셋 · 환경) |
