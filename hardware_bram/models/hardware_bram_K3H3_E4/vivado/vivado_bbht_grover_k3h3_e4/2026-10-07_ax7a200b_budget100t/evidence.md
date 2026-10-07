# K3/H3-E4 — AX7A200B 구현, 100T 자원 예산 (WNS +0.169 ns)

## 무엇인가

`hardware_bram_K3H3_E4` 을 RVX 플랫폼 `bbht_grover_k3h3_e4` 로 원격 보드 AX7A200B(`xc7a200tfbg484-2`)에 구현한 리포트입니다. `/fpga-syn-rvx --budget-100t` 로 200T 의 site 를 막아 Available 을 100T 와 같게 맞췄습니다. 이 비트스트림이 200T 보드에서 모델 사이 측정을 할 대상입니다.

## 확정 수치

| 항목 | 값 |
|---|---:|
| 셋업 WNS / TNS | **+0.169 ns** / 0.000 |
| 홀드 WHS / THS | +0.031 ns / 0.000 |
| Vivado 판정 | All user specified timing constraints are met |
| LUT | 42,463 / 63,400 |
| FF | 42,614 / 126,800 |
| BRAM 타일 | 115 / 135 |
| DSP | 68 / 240 |
| Main IP (`u_main_ip`) LUT / FF / RAMB36 / RAMB18 / DSP | 28,932 / 25,625 / 51 / 64 / 64 |
| 전력 (추정, 활동률 없음) | 0.529 W |

Available 은 리포트의 값입니다 (200T 에서 100T 예산을 건 결과라 100T 와 같음).

## 인용할 때

- **WNS 는 0 이상인지만 봅니다.** 배치 · 배선이 100T 와 달라 값 자체를 인용하지 않습니다. 타이밍과 자원 인용은 Arty 100T 리포트에서 합니다.
- `fpga_syn_rvx.sh result` 는 이 빌드에서 "타이밍 위반" 으로 exit 1 을 냈지만 오판입니다. 스크립트가 Design Timing Summary 의 값 줄 대신 그 아래 빈 줄을 읽습니다(`grep -A3 … | tail -1`). 위 값은 `route_timing_summary.rpt` 에서 직접 읽은 것입니다.
- `bitstream_sha256.txt` 에 비트스트림과 함께 빌드한 앱 hex 의 sha256 이 있습니다. 보드 측정 결과는 이 해시로 빌드와 묶습니다.
- 여섯 모델을 맞댄 표는 [2026-10-07_impl_6models](../../../../../results/2026-10-07_impl_6models/evidence.md) 에 있습니다.
- 같은 모델의 RTL 사이클은 [2026-10-07_bench500_6models](../../../../../results/2026-10-07_bench500_6models/evidence.md) 에 있습니다.

## 파일

| 파일 | 내용 |
|---|---|
| `route_util.rpt` · `route_util_hier.rpt` | 배선 뒤 자원 (전체 · 계층) |
| `route_timing_summary.rpt` | 배선 뒤 타이밍 |
| `route_power.rpt` | 전력 추정 |
| `build_info.txt` | 빌드 조건 |
| `bitstream_sha256.txt` | 비트스트림 · 앱 hex 해시 |
| `source_sha256.txt` | 플랫폼에 들어간 RTL 의 해시 |
| `summary.csv` | 위 수치 한 줄 |
