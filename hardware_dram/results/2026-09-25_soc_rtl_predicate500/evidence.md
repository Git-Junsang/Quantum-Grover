# SoC RTL simulation — DRAM Variant가 실제 NoC 와 DDR model 위에서 네 predicate 16/16

## 무엇인가

RVX platform `bbht_grover_dram` 전체를 Questa 로 RTL simulation한 결과입니다. 여기에는 ORCA
RISC-V core, micro NoC, APB/AHB NI, MIG `slow_dram` 의 simulation DDR model, Bus Interface, DRAM Variant
Accelerator Core, 32-bit AXI4 bridge가 모두 들어 있습니다. 그 위에서 2026-09-25 revision
`bbht_console` 을 script mode로 돌렸습니다. 흐름은 BRAM Variant 쪽
[`2026-09-25_soc_rtl_predicate500`](../../../hardware_bram/configurations/final/results/2026-09-25_soc_rtl_predicate500/evidence.md)
과 같습니다.

```
bbht_predicate500.py --emit-script  ->  script_predicate500_dram.h
    -> SoC RTL simulation (bbht_console script mode)  ->  transcript.txt
    -> bbht_predicate500.py --port replay:transcript.txt  ->  replay.csv / replay.xlsx
```

verilator 의 AXI memory model([`2026-09-25_predicate500_axi`](../2026-09-25_predicate500_axi/evidence.md))은
AXI 규칙대로만 움직이는 이상적인 상대였습니다. 여기서는 RVX 가 실제로 만든 NoC 와 DDR
controller 경로가 상대입니다.

첫 시도에서는 accelerator가 멈췄습니다. NoC 가 16 beat 보다 긴 쓰기를 쪼개고 조각마다 B 를
돌려준 것이 원인이었습니다. 이 묶음은 bridge를 16 beat burst로 고친 뒤의 결과입니다.
경위는 [기술문서 21장 21.5절](../../../documents/design_references/21_dram_variant.md#215-bridge-grover_dram_axi_bridgev)에 있습니다.

## workload

네 predicate × 64 · 256 solutions × seed 0·1 × Restart mode로 **16 실행**입니다. 이 variant에는 checkpoint가
없습니다. 그래서 runner가 `ID` 의 `platform=bbht_grover_dram` 을 보고 Restart mode만 돌립니다. seed와 threshold는
[`hardware_bram/configurations/final/results/2026-09-25_predicate500_rtl`](../../../hardware_bram/configurations/final/results/2026-09-25_predicate500_rtl/evidence.md)
과 같습니다. simulation DDR model은 2 MiB 라 43 iterations까지만 담을 수 있습니다. 그래서 BBHT trajectory가 그
안에 드는 두 값(64 · 256 solutions)을 골랐습니다. 16 실행에 45분 36초 걸렸습니다.

## 확정 수치

| 검사 | 결과 |
|---|---|
| `SUM` 의 FNV-1a 대 software 생성기 (`predicate500_datasets.csv`) | 8/8 |
| `SUM` 의 number of solutions | 8/8 이 dataset에 심은 값과 같음 |
| `result_index` · `trial_count` · `L_BBHT` · `actual_iter` 대 software reference model | 16/16 |
| 찾은 값이 predicate를 만족 | 16/16 |
| `ERR` · `MISS` · `HOST_TIMEOUT` | 0 |
| Questa | `QUIT` 까지 가서 정상 종료, Errors 0 · Warnings 0 |

executed iterations는 expected result의 `actual_iter_dram_session` 열과 맞댔습니다. DRAM amplitude table은 다음
seed로 넘어가도 남아 있습니다. 그래서 같은 dataset 안에서는 앞 seed가 채운 iteration별 amplitude를 다시
씁니다.

| dataset | FNV-1a |
|---|---|
| LT 64 solutions / 256 | `0x8e060871` / `0xa569173a` |
| GT 64 solutions / 256 | `0x29a01211` / `0x13d60bf9` |
| EQ 64 solutions / 256 | `0xefb2e98e` / `0xdca4f97c` |
| RANGE 64 solutions / 256 | `0x4f2d645d` / `0x0d48036a` |

## cycle은 verilator 와 다릅니다 (BBHT trajectory는 같습니다)

같은 16 workloads를 verilator AXI model harness(`per_workload_stall0.csv`)와 맞대 보았습니다.
`result_index` 와 `actual_iter` 는 16/16 같습니다. cycle은 16건 중 15건이 1.35~1.42×입니다.
나머지 한 건(GT 256 solutions seed 1)은 executed iterations가 0 이라 DRAM 을 건드리지 않고, cycle도 2,505 로
같습니다.

| predicate | SoC cycle sum | verilator cycle sum | SoC / verilator |
|---|---:|---:|---:|
| LT | 476,696 | 340,993 | 1.398 |
| GT | 244,611 | 176,369 | 1.387 |
| EQ | 341,470 | 244,601 | 1.396 |
| RANGE | 378,834 | 269,819 | 1.404 |

차이는 전부 memory latency에서 옵니다. AXI model은 고정 latency를 씁니다. SoC 에서는 request가
150 MHz NoC 를 건너 MIG simulation model까지 갔다 옵니다. 이 값은 simulation DDR model 기준이라 board의
DDR3 latency와도 다를 수 있습니다. **성능 인용처가 아니며**, BBHT trajectory 대조의 근거로만 씁니다.

## build 확인

| 확인 | 결과 |
|---|---|
| `sim_rtl/rvx_app_build.log` 의 `BBHT_CONSOLE_SCRIPT` | 76번 (script mode로 build됨) |
| script | `hardware_bram/firmware/bbht_console/src/script_predicate500_dram.h` |
| app build directory | simulation 전에 `app/bbht_console/rtl.debug` 를 지움. script가 compile macro로 들어가 make 가 바뀐 것을 모르기 때문 |

## 재현

```bash
source /opt/rvx/rvx_setup.sh
hardware_dram/rvx/install_to_platform.sh
rm -rf $RVX_MINI_HOME/platform/bbht_grover_dram/app/bbht_console/rtl.debug
cd $RVX_MINI_HOME/platform/bbht_grover_dram/sim_rtl
BBHT_SCRIPT=script_predicate500_dram.h make bbht_console.sim          # 46분쯤
python3 software/host_fpga_develop/bbht_predicate500.py --port replay:qtsim.log --targets 64,256 --seeds 2
```

이번에는 session과 떼어 `setsid nohup` 으로 돌렸습니다. simulation이 길어서, 그렇게 하지 않으면
terminal이 닫힐 때 같이 죽습니다.

## file

| file | 내용 |
|---|---|
| `transcript.txt` | Questa log에서 console 부분(`[RVX/START]` 부터 종료까지)만 떼어 `# ` 접두를 벗긴 것. 이것만으로도 재생됩니다 |
| `replay.csv` | runner가 재생으로 채점한 16 rows (board 실행과 같은 열) |
| `replay.xlsx` | 같은 내용의 Excel (요약 · number of solutions별 요약 · 실행별 · dataset · 환경) |
