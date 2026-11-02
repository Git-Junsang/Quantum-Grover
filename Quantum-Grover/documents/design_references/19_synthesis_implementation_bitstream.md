# 19장. synthesis · implementation · bitstream

> [← 18장 Predicate500 자동 test](18_predicate500_automated_test.md) · [index](index.md) · [20장 No-Checkpoint Baseline →](20_no_checkpoint_baseline.md)

---

## 19.1 implementation 결과 비교

| 항목 | 2026-09-07 (Board-Verified Build) | 2026-09-16 (Bus Interface 교체 revision) |
|---|---:|---:|
| Vivado | 2024.2 | 2026.1 |
| WNS (100 MHz) | +0.126 ns | +0.196 ns |
| TNS / failing endpoints | 0 / 0 | 0 / 0 |
| Slice LUT | 45,284 | 45,116 |
| Block RAM tile | 116 | 116 |
| DSP48E1 | 132 | 132 |

accelerator clock domain endpoint 74,623개가 모두 통과했고 Inter Clock Table도 비어 있습니다.
이는 clock domain 간 경로가 없으며 [5장 5.3절](05_hardware_architecture_overview.md)의 CDC 소유권
설계가 유지되었음을 보여 줍니다.

adapter는 wiring만 수행하므로 별도의 logic resource를 사용하지 않습니다. hierarchy report에서도
adapter와 내부 Accelerator Core의 LUT 수가 동일합니다.

### 결과의 해석 범위

이 결과는 Bus Interface를 교체한 설계도 같은 chip에서 유사한 timing 여유로 구현됨을 보여
줍니다. LUT는 168개 줄었고 BRAM과 DSP 사용량은 같습니다.

다음 내용은 이 표만으로 판단할 수 없습니다.

- 두 bitstream의 hash 비교. Vivado version이 다릅니다. 원리상 불가능합니다.
- "board build가 재현됐다". 같은 도구로 같은 결과가 나온 것이 아닙니다.
- 성능. 이 묶음에는 실행 결과가 없습니다. 성능은 [1장 1.5절](01_project_overview.md).

근거는 [comm_layer_rebuild](../../hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-16_comm_layer_rebuild/evidence.md)
입니다.

---

## 19.2 resource ablation study 다섯 configuration

다섯 configuration을 같은 조건(Vivado 2024.2, `xc7a100tcsg324-1`, 공통 source · 공통 XDC,
synthesis까지)으로 재고 Accelerator Core hierarchy만 떼어 낸 값입니다.

| configuration | LUT | FF | BRAM tile | DSP |
|---|---:|---:|---:|---:|
| Stage 1 / Stage 2 | 13,804 | 13,611 | 66.0 | 64 |
| Stage 3 | 30,294 | 25,822 | 83.0 | 64 |
| Stage 4 | 29,959 | 25,655 | 83.0 | 64 |
| Stage 5 | 33,547 | 28,195 | 84.0 | 128 |
| final configuration | 33,730 | 28,258 | 84.0 | 128 |

주요 변화는 다음과 같습니다.

- 1 PE에서 4 PEs로 바꾸면 LUT 사용량이 2.2×가 되고 cycle은 38.71% 감소합니다
  ([9장](09_iteration_datapath_and_number_of_pes.md)).
- a Checkpoint-Capacity of 4와 4-shot Lookahead에서 a Checkpoint-Capacity of 3과 3-shot Lookahead로 바꾸면 resource 사용량과 cycle이 모두 감소합니다. BRAM 사용량이
  같은 이유는 checkpoint slot이 Checkpoint-Capacity와 관계없이 4개이기 때문입니다
  ([6장 6.7절](06_data_representation_and_memory_map.md#67-memory-구조)).
- Dual-Row Build에서는 measurement Build를 cycle당 두 row로 처리하기 위해 DSP 사용량이 두 배가 됩니다.
  Two-Level Select는 LUT 183개만 추가로 사용합니다([10장](10_measurement_unit_and_microarchitecture.md)).

근거는 [resource_ablation_5config](../../hardware_bram/results/2026-09-08_resource_ablation_5config/evidence.md)
입니다. 논문에 인용할 값은 이 표 쪽입니다.

---

## 19.3 Accelerator Core resource 다시 재기

저장소의 `src/`를 최종 parameter로 OOC synthesis하면 됩니다.

```bash
hardware_bram/synth/run_main_ip.sh      # Vivado, 2분쯤
```

결과는 BRAM과 DSP가 정확히 맞고 FF가 0.2% 안에 듭니다. LUT은 +2.9% 인데 synthesis
조건 차이입니다.

다섯 configuration을 한꺼번에 재는 `run_resource.sh`는 standalone top 틀이 필요해서 tag
`board-verified-build-2026-09-07`에 있습니다([2장 2.2절](02_development_environment_and_toolchain.md)).

`grover_policy_ooc_top.v` · `grover_policy_impl_wrapper.v`는 Policy Engine만 따로 OOC
synthesis해 timing을 확인하는 용도이며 전체 설계 synthesis source에서는 제외합니다.

---

## 19.4 implementation report 위치

| 경로 | 내용 |
|---|---|
| [`vivado/vivado_bbht_grover_fpga/reports/`](../../hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/) | 최종 implementation `route_{util,util_hier,timing_summary,timing_max,power}.rpt` |
| `vivado/vivado_bbht_grover_fpga/meta/` | build 정보 · source sha256 · bitstream sha256 |
| `vivado/vivado_bbht_grover_fpga/2026-09-16_comm_layer_rebuild/` | Bus Interface 교체 revision의 implementation report |

`meta/source_sha256.txt`는 부분 기록입니다. Board-Verified Build의 RTL 17개 가운데 7개만 적혀
있으므로, 그것만 보고 "전부 대조했다" 고 하면 안 됩니다. 17개 전부는
[`sha256_final_rtl.txt`](../../hardware_bram/configurations/final/results/2026-09-09_repro_package_v1.0/evidence.md)
에 있고 tag `board-verified-build-2026-09-07`와 17/17 일치합니다.

---

## 19.5 bitstream 묶음과 다른 두 revision

board에 구운 것은 directory tree마다 `bitstream/<날짜>_<주제>/` 에 날짜별로 있고, 묶음 목록과 굽는 절차는
[17장 17.2절](17_board_operation.md#172-bitstream-만들기) · [17.4절](17_board_operation.md#174-굽고-app-올리기)에
있습니다. RVX 흐름으로 처음부터 만들려면 이렇습니다.

```bash
source /opt/rvx/rvx_setup.sh
hardware_bram/configurations/final/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_final && make syn && make imp_fpga TARGET_IMP_CLASS=arty-100t
```

다른 두 revision의 implementation 결과(timing · resource)는 [20장 20.6절](20_no_checkpoint_baseline.md#206-resource)과
[21장 21.8절](21_dram_variant.md#218-synthesis와-implementation)에 있습니다.
