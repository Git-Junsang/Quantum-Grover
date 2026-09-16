# 우리 통신 계층 판으로 다시 구현 — 비트스트림 생성과 타이밍 검증

## 무엇인가

main 의 [`hardware_bram/src/`](../../../src/) 를 RVX 플랫폼 `bbht_grover_upgrade` 에
설치해 Arty A7-100T 용 비트스트림까지 낸 것입니다. **보드에는 굽지 않았습니다** —
이 머신에 보드가 없습니다(`/dev/ttyUSB*` 없음, Digilent JTAG `15ba:002a` 없음).

2026-09-07 보드 빌드 이후 처음으로 전체 SoC 를 다시 구현한 것이고, 그 사이에 두 가지가
바뀌었습니다.

- **통신 계층이 우리 판으로 교체**됐습니다. wrapper · mmio · loader 세 파일이 태그
  `board-k3h3-e4-m2` 의 것과 전면 교체 수준으로 다르고(716 / 871 / 452줄), Main IP 를
  직접 물지 않고 어댑터(`bbht_grover_core_adapter.v`)를 한 겹 거칩니다.
- **user region 이 가속기 클럭을 `gclk_accel` 로** 뭅니다. 보드 정본은 `clk_accel`
  이었습니다.

`CLAUDE.md` 2절이 "다시 굽기 전에 이 둘을 먼저 보십시오" 라고 적어 둔 그 둘입니다.

## 확정 수치

| 항목 | 2026-09-07 보드 빌드 | **이 빌드** | 차이 |
|---|---:|---:|---|
| Vivado | 2024.2 | **2026.1** | 툴 판이 다름 |
| WNS (100 MHz) | +0.126 ns | **+0.196 ns** | 여유 +0.070 |
| TNS / failing endpoints | 0 / 0 | **0 / 0** | 같음 |
| WHS / THS | +0.016 / 0 | **+0.017 / 0** | 같음 |
| Slice LUT | 45,284 | **45,116** | -168 |
| Slice Register | 45,223 | **45,210** | -13 |
| Block RAM tile | 116 (135 중 85.9%) | **116** | 같음 |
| DSP48E1 | 132 (240 중 55.0%) | **132** | 같음 |
| Slice | 15,214 | **14,971** | -243 |

`sys_clk_pin`(가속기 100 MHz) 도메인 엔드포인트 74,623개 전부 통과. Inter Clock Table
은 비어 있습니다 — 도메인을 건너는 경로가 없다는 뜻이고, CDC 는 RVX 의
`*_ASYNCH` NI 모듈이 담당한다는 설계와 맞습니다. `check_timing` 은 no_clock 0 ·
unconstrained 0 · loops 0 입니다.

**어댑터 한 겹은 비용이 없습니다.** 계층 리포트에서 `u_core`(어댑터) 32,180 LUT 와
그 안의 `u_main_ip` 32,180 LUT 가 같습니다 — 배선만 하는 껍데기라 논리가 남지 않습니다.
통신 계층까지 합친 `i_bbht` 가 32,477 LUT 이고, 보드의
`i_bbht_rvx_wrapper` 32,610 LUT 보다 오히려 133 적습니다.

## 그래서 무엇이 확인됐나

보드에서 한 번도 확인하지 않았던 두 차이가 **구현 단계까지는** 문제를 일으키지
않았습니다.

- 통신 계층 교체 — 타이밍이 나빠지지 않았고(오히려 +0.070 ns 여유), 자원도 줄었습니다.
- `gclk_accel` — 생성 RTL `arch/rtl/src/bbht_grover_upgrade_rtl.v:1455` 가
  `assign gclk_accel = clk_accel;` 입니다. 게이팅도 BUFG 도 없는 순수 별칭이라
  전기적으로 같은 네트입니다.

## 인용할 때 주의

**이 빌드의 비트스트림 해시를 2026-09-07 것과 비교하지 마십시오.** Vivado 2024.2 대
2026.1 이라 절대 재현되지 않습니다. 같은 이유로 **위 자원·타이밍 수치도 "보드 빌드가
재현됐다"는 근거가 아닙니다** — 배치·라우팅 알고리즘이 다릅니다. 읽을 수 있는 것은
"통신 계층을 바꾸고도 같은 칩에 같은 여유로 들어간다" 까지입니다.

성능 수치(사이클 · 실경과 시간)는 여기서 인용하지 마십시오. 이 묶음에는 실행 결과가
없습니다. `CLAUDE.md` 2절의 세 축을 쓰십시오.

## 곁가지 — 펌웨어 ELF 는 바이트 단위로 재현됐습니다

같은 플랫폼에서 앱 셋을 빌드했더니 둘이 보드에 구운 것과 sha256 이 같았습니다.

| ELF | 보드 (2026-09-07) | 이 빌드 |
|---|---|---|
| `bbht_paper_bench.elf` | `f01c49a7…` | `f01c49a7…` |
| `orca_sw_baseline.elf` | `ff186860…` | `ff186860…` |

비트스트림과 달리 ELF 는 재현됐습니다 — RISC-V 툴체인 · RVX SSW · 메모리맵 ·
소스가 2026-09-07 빌드 머신(`/home/kyu/rvx_summer26`)과 같다는 뜻입니다.
`bbht_console` 은 보드 묶음(`bitstream/2026-09-08_k3h3_e4_m2/`)에 ELF 가 없어 대조할 것이
없습니다. 이 앱의 보드 빌드 ELF 는 시뮬 전용 스크립트 모드를 넣기 전후로 바이트 동일합니다
([`results/2026-09-16_soc_rtl_console/`](../../../results/2026-09-16_soc_rtl_console/evidence.md)).

## 파일

| 파일 | 내용 |
|---|---|
| `summary.csv` | 위 표의 기계가독 판 |
| `build_info.txt` | 툴 판 · 타깃 · 작업방 · 합성 최상단 |
| `source_sha256.txt` | 설치된 RTL **17개 전부**의 해시 (`user/rtl/{src,include}`) |
| `bitstream_sha256.txt` | 비트스트림 해시 |
| `route_timing_summary.rpt` · `route_util.rpt` · `route_util_hier.rpt` · `route_power.rpt` | Vivado 원본 리포트 |

`meta/` 와 `reports/` 는 건드리지 않았습니다 — 그쪽은 2026-09-07 보드 빌드의 기록이고
다시 만들 수 없습니다. 다만 그 `meta/source_sha256.txt` 는 RTL 7개만 담은 부분
기록이라는 점을 적어 둡니다. 보드 정본 17개 전부의 해시는
[`results/2026-09-09_repro_package_v1.0/sha256_final_rtl.txt`](../../../results/2026-09-09_repro_package_v1.0/sha256_final_rtl.txt)
에 있습니다.

## 재현

```bash
source /opt/rvx/rvx_setup.sh
cd $RVX_MINI_HOME/platform
make copy_platform BEFORE=bbht_grover AFTER=bbht_grover_upgrade
# 복제본에는 다른 플랫폼 RTL 이 이름만 바뀐 채로 들어 있습니다. 특히
# bbht_grover_core_stub.v 는 우리 어댑터와 모듈 이름이 겹쳐 elaboration 을 깨뜨립니다.
cd bbht_grover_upgrade
rm -rf user/rtl/src/* user/rtl/include/* user/api/* user/template/* app/bbht_console

cd <저장소>
hardware_bram/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_upgrade
make syn                                  # 오류 0건
make arty-100t
cd imp_arty-100t_* && make imp            # 11분쯤
```
