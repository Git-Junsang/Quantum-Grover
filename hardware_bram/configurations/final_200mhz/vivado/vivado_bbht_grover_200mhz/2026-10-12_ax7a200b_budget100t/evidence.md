# final configuration 200 MHz revision — AX7A200B implementation, 100T resource 예산 (WNS +0.066 ns)

## 무엇인가

`final_200mhz` 를 RVX platform `bbht_grover_200mhz`(지금 `bbht_grover_final_200mhz`, `clk_accel` 200 MHz)로 원격 board
AX7A200B(`xc7a200tfbg484-2`)에 구현한 report입니다. 200T 의 site 를 막아 Available 을 100T 와 같게 맞춘 점은
100 MHz revision의 [2026-10-07 build](../../../../final/vivado/vivado_bbht_grover_fpga/2026-10-07_ax7a200b_budget100t/evidence.md)와
같고, placement · routing directive만 더 강하게 걸었습니다(`build_info.txt`). Vivado 는 원격 server `sdsl-fpga` 에서 돌렸습니다.

## 확정 수치

| 항목 | 값 |
|---|---:|
| setup WNS / TNS | **+0.066 ns** / 0.000 |
| hold WHS / THS | +0.051 ns / 0.000 |
| Vivado 판정 | All user specified timing constraints are met |
| 200 MHz clock (`clk_200000000`) WNS · endpoints | +0.066 ns · 80,654 |
| 50 MHz system clock WNS | +4.321 ns |
| LUT | 44,573 / 63,400 |
| FF | 66,870 / 126,800 |
| Slice | 15,288 / 15,850 |
| BRAM tile | 116 / 135 |
| DSP | 132 / 240 |
| Accelerator Core (`u_main_ip`) LUT / FF / RAMB36 / RAMB18 / DSP | 32,855 / 49,830 / 52 / 64 / 128 |
| 전력 (추정, 활동률 없음) | 1.43 W |

100 MHz revision build와 견주면 Accelerator Core의 LUT · BRAM · DSP 는 거의 같고 FF 가 28,221 에서 49,830 으로 늘었습니다.
더한 pipeline register와 broadcast register tree 몫입니다. Slice 는 96 % 를 써서 여유가 거의 없습니다.

## 인용할 때

- **WNS 는 0 이상인지만 봅니다.** 여유가 0.066 ns 라 RTL 이나 directive를 바꾸면 다시 깨질 수 있습니다.
- 200T 에 100T 예산을 건 build입니다. Arty 100T 로 구현한 적은 없습니다.
- `bitstream_sha256.txt` 에 bitstream과 app hex hash가 있습니다. `bbht_paper_bench.sram.hex` 는 100 MHz revision과
  byte가 같습니다. `bbht_console.sram.hex` 는 이 platform에서 다시 build한 것이고, cycle → µs 환산
  constant(`BBHT_ACCEL_CLK_HZ`)가 200 MHz 로 들어갔습니다(board console이 `accel_clk_hz=200000000` 을 찍음).

## file

| file | 내용 |
|---|---|
| `route_util.rpt` · `route_util_hier.rpt` | routing 뒤 resource (전체 · hierarchy) |
| `route_timing_summary.rpt` | routing 뒤 timing |
| `route_power.rpt` | 전력 추정 |
| `build_info.txt` | build 조건과 placement · routing 흐름 |
| `bitstream_sha256.txt` | bitstream · app hex hash |
| `source_sha256.txt` | platform에 들어간 RTL · 17 headers의 hash |
| `summary.csv` | 위 수치 한 줄 |
