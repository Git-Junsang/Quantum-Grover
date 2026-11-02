# 우리 Bus Interface revision으로 다시 implementation — bitstream 생성과 timing verification

## 무엇인가

main의 [`hardware_bram/src/`](../../../../../src/)를 RVX platform `bbht_grover_upgrade`에
설치해 Arty A7-100T 용 bitstream까지 낸 것입니다. **board에는 굽지 않았습니다** —
이 machine에 board가 없습니다(`/dev/ttyUSB*` 없음, Digilent JTAG `15ba:002a` 없음).

2026-09-07 board build 이후 처음으로 전체 SoC를 다시 구현한 것이고, 그 사이에 두 가지가
바뀌었습니다.

- **Bus Interface가 우리 revision으로 교체**됐습니다. wrapper · mmio · loader 세 file이 tag
  `board-k3h3-e4-m2`의 것과 전면 교체 수준으로 다르고(716 / 871 / 452줄), Accelerator Core를
  직접 물지 않고 adapter(`bbht_grover_core_adapter.v`)를 한 겹 거칩니다.
- **user region이 accelerator clock을 `gclk_accel` 로** 뭅니다. Board-Verified Build는 `clk_accel`
  이었습니다.

`CLAUDE.md` 2절이 "다시 굽기 전에 이 둘을 먼저 보십시오" 라고 적어 둔 그 둘입니다.

## 확정 수치

| 항목 | 2026-09-07 board build | **이 build** | 차이 |
|---|---:|---:|---|
| Vivado | 2024.2 | **2026.1** | tool version이 다름 |
| WNS (100 MHz) | +0.126 ns | **+0.196 ns** | 여유 +0.070 |
| TNS / failing endpoints | 0 / 0 | **0 / 0** | 같음 |
| WHS / THS | +0.016 / 0 | **+0.017 / 0** | 같음 |
| Slice LUT | 45,284 | **45,116** | -168 |
| Slice Register | 45,223 | **45,210** | -13 |
| Block RAM tile | 116 (135 중 85.9%) | **116** | 같음 |
| DSP48E1 | 132 (240 중 55.0%) | **132** | 같음 |
| Slice | 15,214 | **14,971** | -243 |

`sys_clk_pin`(accelerator 100 MHz) clock domain의 endpoint 74,623개 전부 통과. Inter Clock Table
은 비어 있습니다 — clock domain을 건너는 경로가 없다는 뜻이고, CDC는 RVX의
`*_ASYNCH` NI module이 담당한다는 설계와 맞습니다. `check_timing`은 no_clock 0 ·
unconstrained 0 · loops 0입니다.

**adapter 한 겹은 비용이 없습니다.** hierarchy report에서 `u_core`(adapter) 32,180 LUT와
그 안의 `u_main_ip` 32,180 LUT가 같습니다 — wire만 잇는 껍데기라 논리가 남지 않습니다.
Bus Interface까지 합친 `i_bbht`가 32,477 LUT이고, board의
`i_bbht_rvx_wrapper` 32,610 LUT보다 오히려 133 적습니다.

## 그래서 무엇이 확인됐나

board에서 한 번도 확인하지 않았던 두 차이가 **implementation 단계까지는** 문제를 일으키지
않았습니다.

- Bus Interface 교체 — timing이 나빠지지 않았고(오히려 +0.070 ns 여유), resource도 줄었습니다.
- `gclk_accel` — 생성 RTL `arch/rtl/src/bbht_grover_upgrade_rtl.v:1455`가
  `assign gclk_accel = clk_accel;`입니다. gating도 BUFG도 없는 순수 별칭이라
  전기적으로 같은 net입니다.

## 인용할 때 주의

**이 build의 bitstream hash를 2026-09-07 것과 비교하지 마십시오.** Vivado 2024.2 대
2026.1이라 절대 재현되지 않습니다. 같은 이유로 **위 resource·timing 수치도 "board build가
재현됐다"는 근거가 아닙니다** — placement · routing algorithm이 다릅니다. 읽을 수 있는 것은
"Bus Interface를 바꾸고도 같은 chip에 같은 여유로 들어간다" 까지입니다.

성능 수치(cycle · wall-clock time)는 여기서 인용하지 마십시오. 이 묶음에는 실행 결과가
없습니다. `CLAUDE.md` 2절의 세 축을 쓰십시오.

## 곁가지 — firmware ELF는 byte 단위로 재현됐습니다

같은 platform에서 app 셋을 build했더니 둘이 board에 구운 것과 sha256이 같았습니다.

| ELF | board (2026-09-07) | 이 build |
|---|---|---|
| `bbht_paper_bench.elf` | `f01c49a7…` | `f01c49a7…` |
| `orca_sw_baseline.elf` | `ff186860…` | `ff186860…` |

bitstream과 달리 ELF는 재현됐습니다 — RISC-V toolchain · RVX SSW · memory map ·
source가 2026-09-07 build machine(`/home/kyu/rvx_summer26`)과 같다는 뜻입니다.
`bbht_console`은 board 묶음(`bitstream/2026-09-08_k3h3_e4_m2/`)에 ELF가 없어 대조할 것이
없습니다. 이 app의 board build ELF는 simulation 전용 script mode를 넣기 전후로 byte 동일합니다
([`results/2026-09-16_soc_rtl_console/`](../../../results/2026-09-16_soc_rtl_console/evidence.md)).

## file

| file | 내용 |
|---|---|
| `summary.csv` | 위 표의 machine-readable 형태 |
| `build_info.txt` | tool version · target · 작업방 · synthesis 최상단 |
| `source_sha256.txt` | 설치된 RTL **17개 전부**의 hash (`user/rtl/{src,include}`) |
| `bitstream_sha256.txt` | bitstream hash |
| `route_timing_summary.rpt` · `route_util.rpt` · `route_util_hier.rpt` · `route_power.rpt` | Vivado 원본 report |

`meta/`와 `reports/`는 건드리지 않았습니다 — 그쪽은 2026-09-07 board build의 기록이고
다시 만들 수 없습니다. 다만 그 `meta/source_sha256.txt`는 RTL 7개만 담은 부분
기록이라는 점을 적어 둡니다. Board-Verified Build 17개 전부의 hash는
[`results/2026-09-09_repro_package_v1.0/sha256_final_rtl.txt`](../../../results/2026-09-09_repro_package_v1.0/sha256_final_rtl.txt)
에 있습니다.

## 재현

```bash
source /opt/rvx/rvx_setup.sh
cd $RVX_MINI_HOME/platform
make copy_platform BEFORE=bbht_grover AFTER=bbht_grover_final
# 복제본에는 다른 플랫폼 RTL 이 이름만 바뀐 채로 들어 있습니다. 특히
# bbht_grover_core_stub.v 는 우리 어댑터와 모듈 이름이 겹쳐 elaboration 을 깨뜨립니다.
cd bbht_grover_final
rm -rf user/rtl/src/* user/rtl/include/* user/api/* user/template/* app/bbht_console

cd <저장소>
hardware_bram/configurations/final/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_final
make syn                                  # 오류 0건
make arty-100t
cd imp_arty-100t_* && make imp            # 11분쯤
```
