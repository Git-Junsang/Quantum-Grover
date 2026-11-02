# Stage 4 — AX7A200B bitstream (100T 예산)

원격 board AX7A200B(`xc7a200tfbg484-2`)에 2026-10-08에 실제로 구워 500 runs를 잰 bitstream과 app입니다.
implementation 조건과 report는 [`../../vivado/vivado_bbht_grover_k3h3_e4/2026-10-07_ax7a200b_budget100t/`](../../vivado/vivado_bbht_grover_k3h3_e4/2026-10-07_ax7a200b_budget100t/evidence.md),
benchmark는 [`../../vivado/vivado_bbht_grover_k3h3_e4/2026-10-08_ax7a200b_board_500run/`](../../vivado/vivado_bbht_grover_k3h3_e4/2026-10-08_ax7a200b_board_500run/evidence.md) 입니다.

**Arty 100T에는 구울 수 없습니다** (부품이 다름). 100T용 실물은 이 configuration directory의 다른 `bitstream/` 묶음이나
`vivado/.../2026-10-07_arty100t_build/` 를 보십시오.

## file

| file | 내용 |
|---|---|
| `ax7a200b.bit` | bitstream |
| `bbht_paper_bench.sram.hex` | 500 runs 실시간 benchmark app (이 benchmark에 쓴 것) |
| `bbht_console.sram.hex` | UART 명령 shell |
| `sha256sums.txt` | 위 file들의 hash |
| `ocd/` | app load용 OpenOCD 묶음. 상대경로라 원격 host에 그대로 복사해 씁니다 |

`ocd/` 의 `arch/` 는 이 configuration의 platform이 생성한 memory map이라 다른 configuration과 섞어 쓰지 마십시오. `openocd_rvp`
실행 file(12 MB)은 저장소에 두지 않습니다. `/opt/rvx/local_setup/ocd/openocd_rvp` 를 `ocd/` 에 복사합니다.

## 다시 재는 법

```bash
hardware_bram/sim/board_run.sh capacity3_lookahead3_pes4_singlerow_linear              # 굽기 · 적재 · 캡처 · bench500 대조
.claude/skills/fpga-flash/scripts/sdsl_fpga.sh restore --pcie   # 끝나면 반드시
```
