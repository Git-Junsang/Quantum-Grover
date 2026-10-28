# 기존 final configuration에 최신 policy search mode 6 적용 — 2026-10-28

상태: **2026-10-28 사용자 request로 조회. simulation 통과, 200T setup timing 미통과로 중단.**

## 조회 결과

기존 final configuration에서도 Common500 통합 policy는 **80,719 cycles**, policy stall은 **16,363 cycles**,
전체 checkpoint 실행은 **5,150,965 cycles**, executed iterations는 9,582회입니다. 500 workloads reference model verification과
전체 SoC console 90항목이 통과했고 Questa Errors 0 / Warnings 0입니다.

bitstream은 생성됐지만 WNS **-26.252 ns**로 setup 미통과이며 WHS는 +0.028 ns입니다.
최악 경로는 policy의 rk_pos_reg에서 a_pipe_r1_reg까지이고, data delay 36.231 ns·logic 48단계입니다.
timing 판정 단계에서 종료했으므로 이번 작업은 board에 program하지 않았습니다.
`pipeline_state.json`, `implementation_result.log`와 아래 implementation report가 근거입니다.

implementation report: `/opt/rvx/platform/bbht_grover_k3h3_e4_m2_policy6_20261028/imp_ax7a200b_2026-10-28/imp_result/route_timing_summary.rpt`

조회 시 frozen platform 입력 28개는 manifest와 모두 일치했습니다. workspace의 공용 RTL을
수정해도 이 platform·snapshot을 덮어쓰지 않으면 기존 실행 입력에는 반영되지 않습니다.
기존 Triple-Row Build background 실행의 결과는 이번에도 조회하지 않았습니다.

기존 final configuration의 Dual-Row Build와 Two-Level Select(16 groups × 32 rows)를 유지하고 최신 policy RTL을 적용합니다.
앞서 잰 Triple-Row Build와 다른 configuration입니다. 이 configuration의 수치는 `k3h3_e4_b2_p6/sim.json`이며,
이번 final configuration 실행도 policy cycle 합계가 80,719로 같지만 stall·전체 실행은 다릅니다.

## 동결한 입력

| 항목 | 설정 |
|---|---|
| Checkpoint-Capacity · Lookahead-Shots · number of PEs | 3 · 3 · 4 |
| 기존 final configuration의 Measurement Microarchitecture | Dual-Row Build · Two-Level Select (16 × 32) |
| policy | policy search mode 6, Scan 4개, CANON 4개 |
| FPGA | xc7a200tfbg484-2, 200T 전체 resource |
| accelerator/system clock | 100/50 MHz |
| workload | Common500, Restart mode · Checkpoint mode 각 500개 |
| platform | bbht_grover_k3h3_e4_m2_policy6_20261028 |

`config.json`, `manifest.json`, `pipeline_inputs.json`, `source/`와 생성 adapter가 입력 source of truth입니다.
명시적인 `MEAS_BUILD_ROWS=2`가 legacy 기본값보다 우선하므로 실제 Measurement Unit은 Dual-Row Build입니다.
공용 policy SHA는 `5aa95f551cc74e0b5ff5454df775fc13bf241ed0557bc792fa348ba347818b3d`,
Accelerator Core SHA는 `d949759b1dc3ae85b4d1b4f336f00f3636c1e94c8c47bee0737eb42f8b306712`입니다.

공용 RTL은 이번 작업에서 수정하지 않았습니다. platform에 설치한 RTL·adapter·header·driver·app
입력을 hash로 고정했으므로 이후 workspace에서 다른 RTL을 개발해도 이 실행에는 반영되지 않습니다.
Board-Verified Build의 `firmware/bbht_paper_bench` source도 수정하지 않고 설치한 사본을 build합니다.

## 자동 진행과 판정

`pipeline_worker.py`를 session에서 분리해 실행했습니다. 제출 PID와 log는 `background_pid.json`,
진행 상태는 `pipeline_state.json`, 단계별 기록은 `pipeline.log`와 각 log에 남습니다.

1. frozen RTL로 policy 단독·통합 Common500을 실행하고 reference model 결과 · executed iterations를 검증합니다.
2. 같은 source의 Verilator console reference와 전체 RVX SoC Questa console을 실행합니다.
   historical checker와 별도로 `verify_soc.py`가 현재 source의 RUN·STAT·ENUM 90항목을 비교합니다.
3. local Vivado가 비어 있을 때 200T implementation을 시작합니다. 한 번에 Vivado 하나, threads=2입니다.
4. bitstream 부품과 WNS/WHS를 검사합니다. 실패하면 board에 올리지 않고 해당 단계에서 멈춥니다.
5. 통과하면 변경하지 않은 paper_bench app을 build하고, 원격 JTAG·UART·Olimex를 다시 확인합니다.
6. board에서 Restart mode · Checkpoint mode 1,000 rows를 재서 새 RTL Common500과 결과·iteration·cycle을 엄격히 비교합니다.
7. 성공·실패 모두에서 board에 굽기를 시도했다면 flash 설계를 다시 load합니다.

진행을 기다리고 판정하는 것은 이 background process입니다. assistant의 반복 polling이나
후속 model 호출이 필요하지 않습니다. 실패 시 자동으로 RTL을 고치거나 재구현하지 않으며,
`failed_stage`와 오류를 남깁니다. commit은 이 process에서 수행하지 않습니다.

## board 접근과 도구 확인

제출 전에 read-only check로 SSH, Olimex와 CP2102N serial 장치, FT232H JTAG 및 xc7a200t를
확인했습니다. UART는 당시 `/dev/ttyUSB0`, Olimex serial은 `/dev/ttyUSB2`였습니다. 실제 실행 시
고정 번호 대신 CP2102N by-id 경로를 다시 찾습니다. 이 단계에서는 board를 다시 program하지 않았습니다.

board runner에 별도 platform·같은 source benchmark CSV·자동 복구 선택을 추가했습니다.
OpenOCD 종료는 해당 실행의 PID와 작업 directory를 확인한 뒤에만 수행합니다.
기존 checker가 빈 capture를 통과시키지 않도록 전체 workload·중복·누락 검사도 추가했고,
strict cycle 비교의 실패 code를 runner가 보존하도록 했습니다.

`tool_checks.json`에 완전한 과거 board 원자료의 논리 비교 통과, 빈/누락/중복 capture 실패,
OpenOCD의 다른 작업 directory PID 보호와 자기 process 종료 검사 결과를 기록했습니다.
Bash·sh 문법과 Python compile 검사도 통과했습니다. 이는 새 board benchmark 통과를 뜻하지 않습니다.

## 범위

새 configuration은 simulation 통과·PPA setup 미통과이며 board benchmark는 수행하지 않았습니다.
기존 Triple-Row Build background implementation의 결과는 조회하지 않았습니다.
Checkpoint-Capacity · Lookahead-Shots 1~10 일반화와 전체 조합 실행은 하지 않았습니다.
새 configuration부터 이름의 `M`은 Measurement Unit squarer의 병렬 개수를 뜻하며, 옛 이름 `K3H3_E4_M2`의 `M`(Measurement Microarchitecture 단계)과 구분합니다.
