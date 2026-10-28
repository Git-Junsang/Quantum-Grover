# 200T parameter 자동화 기준점

날짜: 2026-10-27 (한국). 축: policy 단독 RTL, 통합 RTL cycle, accelerator OOC.
board benchmark와 전체 RVX SoC implementation은 포함하지 않습니다.

구상·RTL 변경·사용법·지원 범위는
[실험 27](../../../documents/reports/27_200t_parameter_automation.md)에 있습니다.

## 재현 입력

- [manifest.json](manifest.json): 전체 설정, 원본 source SHA-256, 생성 cell 목록
- [source](source): 실제 compile한 RTL·driver·harness·synthesis Tcl 사본
- [dse_200t.json](../../sim/dse_200t.json): 기본 설정 (a Checkpoint-Capacity of 3, 3-shot Lookahead, 4 PEs, Two-Level Select, Triple-Row Build · Quad-Row Build, policy search mode 6, Common500)
- 부품 `xc7a200tfbg484-2`, accelerator clock 10 ns. 100T resource 제한 없음
- Verilator 5.020 / Icarus Verilog, 원격 OOC는 Vivado 2026.1

## RTL verification

`python3 hardware_bram/sim/test_dse.py` 통과. Single-Row · Dual-Row · Triple-Row · Quad-Row Build 경로의 total weight · Measurement PRNG 소비 · random number ·
candidate가 여섯 amplitude 분포에서 일치합니다. 0, total weight 1, uniform amplitude, group 경계와 마지막 row, maximum
amplitude, 비균일 분포를 포함합니다. Quad-Row Build의 measurement는 각 사례에서 Triple-Row Build보다 43 cycles 짧았습니다.
Iteration-Count Predictor는 생성 개수 7·8·9 각각 80문맥, 합계 240문맥에서 독립 7-step jump 기준과 일치합니다.
shot/BBHT budget 재시작과 rejection sampling을 포함합니다. 지원하지 않는 설정도 build 전에 거부합니다.

`make -C hardware_bram/sim regress-real CONFIGURATION=capacity3_lookahead3_pes4_triplerow_twolevel_seedfirst_singleexit`는 오류 0건으로 통과했습니다.
`python3 spec/gen_csr.py --check`도 일치했습니다.
통합 regression 원문은 [regress_real.log](validation/regress_real.log)에 있습니다.
문서 검사에는 작업 시작 때와 동일하게 기존 오류 62건·경고 6건이 남아 있습니다
([docs_check.log](validation/docs_check.log)). 이동된 논문 경로와 기존 memo table 절 anchor 등이
원인이며, 이번에 추가한 report·근거 link에서 새 오류는 나오지 않았습니다.

### 전체 Common500

기존 Triple-Row Build 경로는 500/500 workload에서 외부 trace의 result/trial/L_BBHT 및 해당 Checkpoint-Capacity · Lookahead-Shots의
exact replay executed iterations와 일치했습니다. 전체 4,566,996 cycles, executed iterations 9,582,
policy stall 39,440으로 기존 policy search mode 6(Seed-First Branch and Bound with Single-Action Exit) 기준점을 그대로 재현했습니다.
원자료는 [Triple-Row Build sim.json](k3h3_e4_b3_p6/sim.json), [Triple-Row Build bench.csv](k3h3_e4_b3_p6/bench.csv)입니다.
policy 단독도 7,403/7,403 결정이 일치했으며 525,037 cycles입니다
([policy.json](k3h3_e4_b3_p6/policy.json)).

Quad-Row Build 경로도 **500/500 workload**의 논리 결과와 exact replay executed iterations가 일치했습니다.
모든 실행의 Plan Queue miss는 0입니다. 같은 configuration · policy search mode 6에서 Build만 바꾼 비교입니다.

| Build | 전체 RTL cycle | executed iterations | 노출 policy stall |
|---|---:|---:|---:|
| Triple-Row Build | 4,566,996 | 9,582 | 39,440 |
| Quad-Row Build | 4,250,089 | 9,582 | 40,862 |

전체 cycle이 6.94 % 줄었습니다. 기준 clock에서의 이론적 throughput 비는 1.075×이며,
board wall-clock time benchmark는 아닙니다. 실행이 짧아져 policy stall은 조금 늘었습니다.
원자료는 [Quad-Row Build sim.json](k3h3_e4_b4_p6/sim.json),
[Quad-Row Build bench.csv](k3h3_e4_b4_p6/bench.csv), [summary.csv](summary.csv)입니다.
동일 source/hash로 다시 호출할 때는 verification 완료 단계를 건너뛰고 report를 재생성했습니다.

## synthesis·routing의 범위

최상위는 실제 APB/AHB Bus Interface와 생성 adapter를 포함한 `bbht_rvx_wrapper`입니다.
Accelerator Core와 Bus Interface를 합친 accelerator OOC이며 ORCA·NoC·system SRAM 등 전체 SoC가 아닙니다.
내부 clock 경로만 제약합니다. 따라서 OOC 통과를 full SoC나 board 통과로 인용하지 않습니다.

Quad-Row Build 경로의 200T routing은 **WNS +0.272 ns / WHS +0.068 ns**, routing 오류 0으로 통과했습니다.
routing 후 resource는 LUT 37,625 / FF 29,622 / BRAM tile 82.5 / DSP 256입니다.
근거는 [routing timing](k3h3_e4_b4_p6/route/timing.rpt),
[routing status](k3h3_e4_b4_p6/route/route_status.rpt),
[routing resource](k3h3_e4_b4_p6/route/util.rpt), [slack.csv](k3h3_e4_b4_p6/route/slack.csv)입니다.
원격 compile 16 sources의 hash도 저장소의 실험 사본과 전부 일치했습니다
([remote_source_sha256.txt](remote_source_sha256.txt)).
baseline인 Triple-Row Build 경로도 같은 부품·clock·흐름에서 OOC timing을 통과했습니다.

| Build | routing LUT | FF | BRAM tile | DSP | WNS ns | WHS ns |
|---|---:|---:|---:|---:|---:|---:|
| Triple-Row Build | 40,961 | 30,995 | 81.5 | 192 | +0.605 | +0.068 |
| Quad-Row Build | 37,625 | 29,622 | 82.5 | 256 | +0.272 | +0.068 |

Triple-Row Build 경로 원자료는 [routing resource](k3h3_e4_b3_p6/route/util.rpt),
[routing timing](k3h3_e4_b3_p6/route/timing.rpt),
[routing status](k3h3_e4_b3_p6/route/route_status.rpt)입니다. Quad-Row Build 경로는 DSP를 64개 더 쓰지만
4→3 residual 변환 경로를 사용하지 않아 이 build에서는 LUT·FF가 줄었습니다.
두 경로 모두 routing 오류 0입니다. 단일 seed·기본 placement 흐름의 결과이며 full SoC resource는 아닙니다.

이 routing에서 최악 setup 경로는 policy가 아니라 `run_predicate_mode`에서 4 PEs configuration의 PE
`pred0_pipe`로 가는 제어 fanout입니다. 내부 clock 미제약 endpoint는 0이며, OOC 입력
82개·출력 65개에는 I/O delay를 주지 않았습니다. 따라서 현재 report는 내부 경로의
통과만 증명합니다. policy pipeline 단계를 합칠지는 별도의 latency·timing 실험으로
판단해야 합니다.

원격 작업 directory는 `sdsl-fpga:~/sdsl_fpga_runs/2026-10-27_200t_dse`입니다.
첫 Tcl 실행에서 Vivado 2026.1이 `read_verilog -include_dirs`를 거부했습니다.
include 경로를 `synth_design`에 전달하도록 고쳤고, 완료된 synthesis 결과는 없었습니다.
simulation에 사용한 RTL은 바뀌지 않았습니다. 구·신 hash와 수정 이유는
[tooling_corrections.json](tooling_corrections.json), 실패한 Tcl은
[source/dse_ooc_read_option_failed.tcl](source/dse_ooc_read_option_failed.tcl)에 보존했습니다.

## 별도 Checkpoint-Capacity · Lookahead-Shots 확인

8-shot Lookahead와 a Checkpoint-Capacity of 4의 통합 설정 확인은 [별도 묶음](../2026-10-27_200t_kh_smoke/evidence.md)에서
실행합니다. 짧은 앞부분 확인이며 Common500 전체 heatmap으로 인용하지 않습니다.
