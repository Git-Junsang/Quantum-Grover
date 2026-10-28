# DRAM Variant 첫 bitstream — 100 MHz timing closure (WNS +0.005 ns)

## 무엇인가

DRAM Variant(`hardware_dram/`)를 RVX platform `bbht_grover_dram` 으로 Arty A7-100T 에 구현한
build의 report입니다. accelerator는 DRAM Variant Accelerator Core + Bus Interface + 32-bit AXI4 bridge이고,
amplitude table은 RVX 의 `slow_dram`(MIG DDR3)에 둡니다. 설계는
[기술문서 21장](../../../../documents/design_references/21_dram_variant.md),
구운 실물은 [`../../../bitstream/2026-09-25_dram_axi/`](../../../bitstream/2026-09-25_dram_axi/evidence.md) 에 있습니다.

같은 날 세 번 구현했고 이 directory의 report는 **세 번째(최종)** 입니다. 앞의 둘은 아래
"경위" 에 있습니다.

## 확정 수치

| 항목 | 값 |
|---|---|
| setup WNS / TNS | **+0.005 ns** / 0.000 |
| hold WHS / THS | +0.021 ns / 0.000 |
| pulse 폭 WPWS | +0.109 ns |
| Vivado 판정 | All user specified timing constraints are met |
| LUT / FF | 27,379 (43.18%) / 34,162 (26.94%) |
| BRAM tile / DSP | 81 (60.00%) / 74 (30.83%) |
| Slice | 13,151 (82.97%) |
| 전력 (추정) | 1.030 W |

clock별 setup WNS:

| clock | 주기 | WNS | 무엇이 도는가 |
|---|---:|---:|---|
| `clk_pll_i` | 6.667 ns (150 MHz) | +0.005 | MIG ui_clk. **RVX 가 DRAM 을 넣으면 NoC 를 이 clock으로 돌립니다** |
| `sys_clk_pin` | 10 ns (100 MHz) | +0.431 | `clk_accel` = accelerator 전체 |
| `clk_50000000` | 20 ns (50 MHz) | +5.308 | ORCA core · peripheral |

accelerator(`i_bbht`, `bbht_dram_axi_top`)는 LUT 10,094 · FF 10,531 · RAMB36 1 · RAMB18 96 ·
DSP 70 이고, 그중 bridge가 LUT 292 · FF 1,744 · DSP 4 입니다. FF 가 많은 것은 row buffer 두
벌(쓰기 736-bit · 읽기 736-bit) 때문입니다.

**여유가 5 ps 로 얇습니다.** 최악 경로는 우리 RTL 이 아니라 150 MHz 로 도는 RVX NoC
안이고, accelerator clock은 0.431 ns 남습니다. 제약은 모든 corner에서 만족하지만 RTL 을 조금만
바꿔도 placement가 달라지니, 다시 구현하면 이 표부터 확인하십시오.

## 경위 — 세 번의 implementation

| 차수 | bridge | placement · routing | WNS | 결과 |
|---|---|---|---:|---|
| 1 | 256 beat burst, W 쪽에서 burst 길이를 곧바로 계산 | RVX 기본 | −2.097 (89곳) | timing 실패 |
| 2 | 256 beat, W 쪽 길이 계산을 한 cycle 늦춤 | `pnr_manually.tcl` | +0.068 | timing은 맞음. **SoC RTL simulation에서 첫 search가 멈춤** |
| 3 | **16 beat, AW/AR 넷까지, W 는 awlen queue** | `pnr_manually.tcl` | **+0.005** | 이 directory |

**1차의 위반 둘** (`first_try_timing_summary.rpt`)은 서로 무관했습니다.

| clock | WNS | 위반 | 원인 | 조치 |
|---|---:|---:|---|---|
| `sys_clk_pin` | −2.097 | 10곳 | bridge가 쓰기 session을 시작하는 cycle에 `(len+1)×23` multiplication → 4 KiB 경계 비교 → `w_left` 를 한 번에 계산 | RTL. 3차에서 W 쪽 길이 계산을 아예 없앰(AW 가 수락될 때 awlen 을 queue에 넣고 W 는 그것을 씀) |
| `clk_pll_i` | −0.659 | 79곳 | RVX NoC 의 system SRAM interface(`i_snim_i_system_sram`) 안 13단 경로. latency의 70% 가 routing | placement · routing. `pnr_manually.tcl` |

두 번째는 우리 RTL 이 아닙니다. RVX 는 DRAM 을 넣으면 `clk_noc` 를 MIG 의 ui_clk 로
바꾸는데, 이 board의 MIG 설정(`mig_b.prj`, 2:1)에서 그 clock이 150 MHz 입니다. BRAM Variant
platform은 NoC 가 50 MHz 라 이 문제가 없습니다. RVX 가 `user/fpga/<board>/pnr_manually.tcl`
을 읽어 기본 placement · routing을 대신하게 해 두었으므로 그 자리를 썼습니다.

**2차가 SoC 에서 멈춘 이유**는 timing이 아니라 NoC 의 동작입니다. RVX micro NoC 는 16 beat
넘는 쓰기를 DDR 쪽에서 16 beat 조각으로 쪼개고 **조각마다 B 응답을 master에게 돌려줬습니다**
(AW 46개에 B 736개). AW 하나에 B 하나를 세던 bridge는 대기 중 B 수가 음수로 넘어가
읽기를 시작하지 못했습니다. AXI model은 AXI 규칙대로 B 를 하나만 주므로 verilator 에서는
드러나지 않았습니다. 3차 bridge는 burst를 16 beat 이하로 자르고, AXI model은 16 beat 를
넘는 burst를 오류로 셉니다. 경위와 waveform 대신 찍은 handshake 수는
[기술문서 21장 21.5절](../../../../documents/design_references/21_dram_variant.md#215-bridge-grover_dram_axi_bridgev)에 있습니다.

3차 단계별 setup WNS (`[BBHT_PNR]` log):

| 단계 | WNS |
|---|---:|
| `opt_design -directive Explore` | −3.043 |
| `place_design -directive ExtraTimingOpt` | −0.573 |
| `phys_opt_design -directive AggressiveExplore` | +0.001 |
| `route_design -directive Explore` | **+0.005** (양수라 routing 뒤 최적화는 건너뜀) |

## 3차 bridge는 simulation으로 다시 확인했습니다

- verilator: `make -C hardware_dram/sim`(regression)과 `make -C hardware_dram/sim predicate500`
  (AXI model 기본 latency · backpressure 두 벌)이 여섯 축 2,000/2,000, 16 beat 초과 burst 0,
  AXI 오류 0 ([`results/2026-09-25_predicate500_axi/`](../../../results/2026-09-25_predicate500_axi/evidence.md))
- SoC RTL simulation: 실제 NoC 와 DDR model 위에서 bridge의 AW 와 B 가 1:1(8,096 : 8,096),
  AR 과 rlast 가 1:1 이고 search가 끝남 (debug script)

`source_sha256.txt` 의 설치본은 저장소 `hardware_dram/src/` 와 file마다 같습니다.

## RVX 가 "알 수 없음" 으로 분류한 critical warning

`vivado_imp.critical.unknown.log` 41건은 전부 RVX 가 붙이는 MIG 와 PLL 쪽입니다. 우리
RTL 에서 나온 것은 없습니다. board에서 DRAM 이 이상하면 먼저 볼 곳이라 적어 둡니다.

| 경고 | 수 | 내용 |
|---|---:|---|
| Synth 8-4442 `device_temp_i` 미연결 | 12 | MIG 설정이 XADC 를 끈 채(`XADC_En Disabled`) 온도 보정을 켜 두었고, RVX 의 `slow_dram_body.vh` 가 온도 입력을 잇지 않음 |
| Opt 31-430 `device_temp_sync_r1_reg` 입력 없음 | 12 | 위와 같은 원인 |
| Timing 38-469 IDELAYCTRL REFCLK 300 MHz 대 IDELAYE2 200 MHz | 16 | MIG 참조 clock 설정 불일치 |
| Synth 8-4442 PLL `reset` 미연결 | 1 | RVX clock PLL |

온도 보정은 장시간 동작 중 읽기 phase drift를 보상하는 기능이라 짧은 시험에는 영향이
작을 것으로 봅니다. IDELAY 불일치는 MIG 가 calibration을 통과하는지로 드러납니다.
둘 다 **board에서 확인할 항목**입니다.

## 인용할 때

- 이 build는 **board에서 돌리지 않았습니다.** timing closure까지가 근거입니다.
- BRAM Variant의 Bus Interface rebuild([`2026-09-16_comm_layer_rebuild`](../../../../hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-16_comm_layer_rebuild/), WNS +0.196 ns,
  LUT 45,116 · DSP 132)와 resource를 맞대면 DRAM Variant가 LUT 를 덜 씁니다.
  checkpoint · Policy Engine · 4 PEs가 없기 때문이고, 대신 RTL cycle로 약 11×
  느립니다. 한쪽 축만 인용하지 마십시오.

## file

| file | 내용 |
|---|---|
| `route_timing_summary.rpt` · `route_timing_max.rpt` | 최종(3차) timing |
| `route_util.rpt` · `route_util_hier.rpt` | resource |
| `route_power.rpt` | 전력 추정 |
| `first_try_timing_summary.rpt` | 1차 (RVX 기본 흐름, 위반 89곳) |
| `summary.csv` | 한 줄 요약 (BRAM Variant 묶음과 같은 열) |
| `build_info.txt` | build 조건 · clock · placement · routing 순서 · 세 번의 implementation |
| `source_sha256.txt` | platform에 설치된 RTL · header · `pnr_manually.tcl` 의 sha256 |
| `bitstream_sha256.txt` | bitstream sha256 |
