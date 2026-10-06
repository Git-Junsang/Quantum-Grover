# 체크포인트 없는 판 비트스트림 — 100 MHz 타이밍 클로즈 (WNS +0.193 ns)

## 무엇인가

`hardware_bram_nocheckpoint` 를 RVX 플랫폼 `bbht_grover_nocheckpoint` 로 Arty A7-100T 에
구현한 빌드의 리포트입니다. 구성은 연산기 네 벌(E4)만 켜고 체크포인트 · 정책 엔진 ·
측정 최적화 M1/M2 를 끈 Normal-E4 입니다. SoC 구성과 배치·배선 흐름은 체크포인트 판
재빌드([`2026-09-16_comm_layer_rebuild`](../../../../hardware_bram_K3H3_E4_M2/vivado/vivado_bbht_grover_fpga/2026-09-16_comm_layer_rebuild/))
와 같게 두고 어댑터 파라미터만 바꿨습니다. 구운 실물은
[`../../../bitstream/2026-09-25_nocheckpoint/`](../../../bitstream/2026-09-25_nocheckpoint/evidence.md)
에 있습니다.

## 확정 수치

| 항목 | 이 판 (Normal-E4) | 체크포인트 판 (K3/H3-E4-M2, 2026-09-16) |
|---|---:|---:|
| 셋업 WNS / TNS | **+0.193 ns** / 0.000 | +0.196 ns / 0.000 |
| 홀드 WHS / THS | +0.012 ns / 0.000 | +0.017 ns / 0.000 |
| Vivado 판정 | All user specified timing constraints are met | 같음 |
| LUT / FF | 38,133 / 38,634 | 45,116 / 45,210 |
| BRAM 타일 / DSP | 111 / 68 | 116 / 132 |
| Slice | 14,342 (90.49%) | 14,971 |
| 전력 (추정) | 0.624 W | 0.568 W |

클럭별 셋업 WNS: `sys_clk_pin`(가속기 100 MHz) +0.193, `clk_50000000`(코어·주변장치
50 MHz) +5.374.

Main IP(`u_main_ip`)만 보면:

| 항목 | 이 판 | 체크포인트 판 | 차이의 출처 |
|---|---:|---:|---|
| LUT | 24,846 | 32,180 | 정책 엔진(3,077) · Planner/Executor/메타 · 측정 M1/M2 |
| FF | 21,650 | 28,221 | 정책 엔진(2,921) · 측정 행 버퍼 |
| RAMB36 / RAMB18 | 47 / 64 | 52 / 64 | 정책 memo(4) 와 측정(1) |
| DSP | 64 | 128 | **전부 측정 블록**. M1 은 Born 제곱을 사이클당 두 행 하므로 곱셈기가 두 배 |

E4 진폭 메모리(`g_intra_e4.u_amp_mem`)는 두 판 모두 RAMB36 44 개입니다. 이 판은 슬롯 0
하나만 쓰지만, 736비트 행을 담는 RAMB36 은 폭으로 개수가 정해져 깊이를 줄여도
타일이 줄지 않습니다.

전력은 두 판 모두 시뮬 활동률 없이 낸 추정(Vivado 신뢰도 Medium)입니다. 이 판이 더 높게
나왔지만 구성의 전력 차이로 인용하지 마십시오.

## 인용할 때

- 이 빌드는 **보드에서 돌리지 않았습니다.** 타이밍 클로즈까지가 근거입니다.
- 속도 비교(체크포인트 · M1/M2 유무)는 RTL 사이클로
  [`results/2026-09-25_predicate500_rtl/`](../../../results/2026-09-25_predicate500_rtl/evidence.md)
  에 있습니다. 보드 실경과 시간 비교는 두 비트스트림을 같은 보드에서
  `bbht_predicate500.py` 로 돌린 뒤에 합니다.

## 파일

| 파일 | 내용 |
|---|---|
| `route_timing_summary.rpt` · `route_timing_max.rpt` | 타이밍 |
| `route_util.rpt` · `route_util_hier.rpt` | 자원 |
| `route_power.rpt` | 전력 추정 |
| `summary.csv` | 한 줄 요약 (체크포인트 판 묶음과 같은 열) |
| `build_info.txt` | 빌드 조건 · 클럭 · 순서 |
| `source_sha256.txt` | 플랫폼에 설치된 RTL 17개의 sha256. 저장소 원본과 17/17 같음 |
| `bitstream_sha256.txt` | 비트스트림 sha256 |
