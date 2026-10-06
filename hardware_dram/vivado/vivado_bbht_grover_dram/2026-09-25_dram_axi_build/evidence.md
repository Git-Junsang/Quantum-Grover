# DRAM 갈래 첫 비트스트림 — 100 MHz 타이밍 클로즈 (WNS +0.005 ns)

## 무엇인가

`hardware_dram/` 갈래를 RVX 플랫폼 `bbht_grover_dram` 으로 Arty A7-100T 에 구현한
빌드의 리포트입니다. 가속기는 DRAM 갈래 Main IP + 통신 계층 + 32비트 AXI4 브리지이고,
진폭표는 RVX 의 `slow_dram`(MIG DDR3)에 둡니다. 설계는
[기술문서 22장](../../../../documents/design_references/22_DRAM_갈래.md),
구운 실물은 [`../../../bitstream/2026-09-25_dram_axi/`](../../../bitstream/2026-09-25_dram_axi/evidence.md) 에 있습니다.

같은 날 세 번 구현했고 이 폴더의 리포트는 **세 번째(최종)** 입니다. 앞의 둘은 아래
"경위" 에 있습니다.

## 확정 수치

| 항목 | 값 |
|---|---|
| 셋업 WNS / TNS | **+0.005 ns** / 0.000 |
| 홀드 WHS / THS | +0.021 ns / 0.000 |
| 펄스 폭 WPWS | +0.109 ns |
| Vivado 판정 | All user specified timing constraints are met |
| LUT / FF | 27,379 (43.18%) / 34,162 (26.94%) |
| BRAM 타일 / DSP | 81 (60.00%) / 74 (30.83%) |
| Slice | 13,151 (82.97%) |
| 전력 (추정) | 1.030 W |

클럭별 셋업 WNS:

| 클럭 | 주기 | WNS | 무엇이 도는가 |
|---|---:|---:|---|
| `clk_pll_i` | 6.667 ns (150 MHz) | +0.005 | MIG ui_clk. **RVX 가 DRAM 을 넣으면 NoC 를 이 클럭으로 돌립니다** |
| `sys_clk_pin` | 10 ns (100 MHz) | +0.431 | `clk_accel` = 가속기 전체 |
| `clk_50000000` | 20 ns (50 MHz) | +5.308 | ORCA 코어 · 주변장치 |

가속기(`i_bbht`, `bbht_dram_axi_top`)는 LUT 10,094 · FF 10,531 · RAMB36 1 · RAMB18 96 ·
DSP 70 이고, 그중 브리지가 LUT 292 · FF 1,744 · DSP 4 입니다. FF 가 많은 것은 행 버퍼 두
벌(쓰기 736비트 · 읽기 736비트) 때문입니다.

**여유가 5 ps 로 얇습니다.** 최악 경로는 우리 RTL 이 아니라 150 MHz 로 도는 RVX NoC
안이고, 가속기 클럭은 0.431 ns 남습니다. 제약은 모든 코너에서 만족하지만 RTL 을 조금만
바꿔도 배치가 달라지니, 다시 구현하면 이 표부터 확인하십시오.

## 경위 — 세 번의 구현

| 차수 | 브리지 | 배치·배선 | WNS | 결과 |
|---|---|---|---:|---|
| 1 | 256 beat 버스트, W 쪽에서 버스트 길이를 곧바로 계산 | RVX 기본 | −2.097 (89곳) | 타이밍 실패 |
| 2 | 256 beat, W 쪽 길이 계산을 한 사이클 늦춤 | `pnr_manually.tcl` | +0.068 | 타이밍은 맞음. **SoC RTL 시뮬에서 첫 탐색이 멈춤** |
| 3 | **16 beat, AW/AR 넷까지, W 는 awlen 큐** | `pnr_manually.tcl` | **+0.005** | 이 폴더 |

**1차의 위반 둘** (`first_try_timing_summary.rpt`)은 서로 무관했습니다.

| 클럭 | WNS | 위반 | 원인 | 조치 |
|---|---:|---:|---|---|
| `sys_clk_pin` | −2.097 | 10곳 | 브리지가 쓰기 세션을 시작하는 사이클에 `(len+1)×23` 곱셈 → 4 KiB 경계 비교 → `w_left` 를 한 번에 계산 | RTL. 3차에서 W 쪽 길이 계산을 아예 없앰(AW 가 수락될 때 awlen 을 큐에 넣고 W 는 그것을 씀) |
| `clk_pll_i` | −0.659 | 79곳 | RVX NoC 의 시스템 SRAM 인터페이스(`i_snim_i_system_sram`) 안 13단 경로. 지연의 70% 가 배선 | 배치·배선. `pnr_manually.tcl` |

두 번째는 우리 RTL 이 아닙니다. RVX 는 DRAM 을 넣으면 `clk_noc` 를 MIG 의 ui_clk 로
바꾸는데, 이 보드의 MIG 설정(`mig_b.prj`, 2:1)에서 그 클럭이 150 MHz 입니다. bram
플랫폼은 NoC 가 50 MHz 라 이 문제가 없습니다. RVX 가 `user/fpga/<보드>/pnr_manually.tcl`
을 읽어 기본 배치·배선을 대신하게 해 두었으므로 그 자리를 썼습니다.

**2차가 SoC 에서 멈춘 이유**는 타이밍이 아니라 NoC 의 동작입니다. RVX micro NoC 는 16 beat
넘는 쓰기를 DDR 쪽에서 16 beat 조각으로 쪼개고 **조각마다 B 응답을 마스터에게 돌려줬습니다**
(AW 46개에 B 736개). AW 하나에 B 하나를 세던 브리지는 대기 중 B 수가 음수로 넘어가
읽기를 시작하지 못했습니다. AXI 모델은 AXI 규칙대로 B 를 하나만 주므로 verilator 에서는
드러나지 않았습니다. 3차 브리지는 버스트를 16 beat 이하로 자르고, AXI 모델은 16 beat 를
넘는 버스트를 오류로 셉니다. 경위와 파형 대신 찍은 핸드셰이크 수는
[기술문서 22장 22.5절](../../../../documents/design_references/22_DRAM_갈래.md#225-브리지-grover_dram_axi_bridgev)에 있습니다.

3차 단계별 셋업 WNS (`[BBHT_PNR]` 로그):

| 단계 | WNS |
|---|---:|
| `opt_design -directive Explore` | −3.043 |
| `place_design -directive ExtraTimingOpt` | −0.573 |
| `phys_opt_design -directive AggressiveExplore` | +0.001 |
| `route_design -directive Explore` | **+0.005** (양수라 배선 뒤 최적화는 건너뜀) |

## 3차 브리지는 시뮬로 다시 확인했습니다

- verilator: `make -C hardware_dram/sim`(회귀)과 `make -C hardware_dram/sim predicate500`
  (AXI 모델 기본 지연 · 백프레셔 두 벌)이 여섯 축 2,000/2,000, 16 beat 초과 버스트 0,
  AXI 오류 0 ([`results/2026-09-25_predicate500_axi/`](../../../results/2026-09-25_predicate500_axi/evidence.md))
- SoC RTL 시뮬: 실제 NoC 와 DDR 모델 위에서 브리지의 AW 와 B 가 1:1(8,096 : 8,096),
  AR 과 rlast 가 1:1 이고 탐색이 끝남 (디버그 스크립트)

`source_sha256.txt` 의 설치본은 저장소 `hardware_dram/src/` 와 파일마다 같습니다.

## RVX 가 "알 수 없음" 으로 분류한 critical warning

`vivado_imp.critical.unknown.log` 41건은 전부 RVX 가 붙이는 MIG 와 PLL 쪽입니다. 우리
RTL 에서 나온 것은 없습니다. 보드에서 DRAM 이 이상하면 먼저 볼 곳이라 적어 둡니다.

| 경고 | 수 | 내용 |
|---|---:|---|
| Synth 8-4442 `device_temp_i` 미연결 | 12 | MIG 설정이 XADC 를 끈 채(`XADC_En Disabled`) 온도 보정을 켜 두었고, RVX 의 `slow_dram_body.vh` 가 온도 입력을 잇지 않음 |
| Opt 31-430 `device_temp_sync_r1_reg` 입력 없음 | 12 | 위와 같은 원인 |
| Timing 38-469 IDELAYCTRL REFCLK 300 MHz 대 IDELAYE2 200 MHz | 16 | MIG 참조 클럭 설정 불일치 |
| Synth 8-4442 PLL `reset` 미연결 | 1 | RVX 클럭 PLL |

온도 보정은 장시간 동작 중 읽기 위상 드리프트를 보상하는 기능이라 짧은 시험에는 영향이
작을 것으로 봅니다. IDELAY 불일치는 MIG 가 보정(calibration)을 통과하는지로 드러납니다.
둘 다 **보드에서 확인할 항목**입니다.

## 인용할 때

- 이 빌드는 **보드에서 돌리지 않았습니다.** 타이밍 클로즈까지가 근거입니다.
- bram 통신 계층 재빌드([`2026-09-16_comm_layer_rebuild`](../../../../hardware_bram/models/hardware_bram_K3H3_E4_M2/vivado/vivado_bbht_grover_fpga/2026-09-16_comm_layer_rebuild/), WNS +0.196 ns,
  LUT 45,116 · DSP 132)와 자원을 맞대면 DRAM 갈래가 LUT 를 덜 씁니다.
  체크포인트 · 정책 엔진 · 연산기 네 벌이 없기 때문이고, 대신 RTL 사이클로 약 11배
  느립니다. 한쪽 축만 인용하지 마십시오.

## 파일

| 파일 | 내용 |
|---|---|
| `route_timing_summary.rpt` · `route_timing_max.rpt` | 최종(3차) 타이밍 |
| `route_util.rpt` · `route_util_hier.rpt` | 자원 |
| `route_power.rpt` | 전력 추정 |
| `first_try_timing_summary.rpt` | 1차 (RVX 기본 흐름, 위반 89곳) |
| `summary.csv` | 한 줄 요약 (bram 묶음과 같은 열) |
| `build_info.txt` | 빌드 조건 · 클럭 · 배치·배선 순서 · 세 번의 구현 |
| `source_sha256.txt` | 플랫폼에 설치된 RTL · 헤더 · `pnr_manually.tcl` 의 sha256 |
| `bitstream_sha256.txt` | 비트스트림 sha256 |
