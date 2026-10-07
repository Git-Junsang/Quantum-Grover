# K4/H4-E1 — Arty A7-100T 구현 (WNS +0.186 ns)

## 무엇인가

`hardware_bram_K4H4_E1` 을 RVX 플랫폼 `bbht_grover_k4h4_e1` 로 Arty A7-100T(`xc7a100tcsg324-1`)에 구현한 리포트입니다. 공용 `hardware_bram/src/` 에 이 모델 어댑터의 파라미터만 넣었고, SoC 구성과 흐름은 최종 모델 재빌드(2026-09-16)와 같습니다. **보드에 굽지 않았습니다.** 논문의 "100T 자원 · 타이밍" 근거로 쓰려고 낸 빌드입니다.

## 확정 수치

| 항목 | 값 |
|---|---:|
| 셋업 WNS / TNS | **+0.186 ns** / 0.000 |
| 홀드 WHS / THS | +0.014 ns / 0.000 |
| Vivado 판정 | All user specified timing constraints are met |
| LUT | 25,273 / 63,400 |
| FF | 30,549 / 126,800 |
| BRAM 타일 | 98 / 135 |
| DSP | 68 / 240 |
| Main IP (`u_main_ip`) LUT / FF / RAMB36 / RAMB18 / DSP | 13,624 / 13,610 / 50 / 32 / 64 |
| 전력 (추정, 활동률 없음) | 0.436 W |

Available 은 리포트의 값입니다.

## 인용할 때

- 자원 · 타이밍은 이 리포트에서 인용합니다. 다만 Main IP 만의 자원을 논문 표에 쓸 때는 `u_main_ip` 행을 쓰고, SoC 전체와 섞지 마십시오.
- 전력은 시뮬 활동률 없이 낸 추정(Vivado 신뢰도 Medium)이라 구성 사이 전력 차이로 인용하지 마십시오.
- 여섯 모델을 맞댄 표는 [2026-10-07_impl_6models](../../../../../results/2026-10-07_impl_6models/evidence.md) 에 있습니다.
- 같은 모델의 RTL 사이클은 [2026-10-07_bench500_6models](../../../../../results/2026-10-07_bench500_6models/evidence.md) 에 있습니다.

## 파일

| 파일 | 내용 |
|---|---|
| `route_util.rpt` · `route_util_hier.rpt` | 배선 뒤 자원 (전체 · 계층) |
| `route_timing_summary.rpt` | 배선 뒤 타이밍 |
| `route_power.rpt` | 전력 추정 |
| `build_info.txt` | 빌드 조건 |
| `bitstream_sha256.txt` | 비트스트림 해시 |
| `source_sha256.txt` | 플랫폼에 들어간 RTL 의 해시 |
| `summary.csv` | 위 수치 한 줄 |
