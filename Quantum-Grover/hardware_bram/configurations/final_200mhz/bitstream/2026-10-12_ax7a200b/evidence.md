# final configuration (200 MHz) — AX7A200B bitstream (100T 예산)

원격 board AX7A200B(`xc7a200tfbg484-2`)에 2026-10-12 · 13에 실제로 구워 Predicate500과 500 runs를 잰 bitstream과 app입니다.
implementation 조건과 report는 [`../../vivado/vivado_bbht_grover_200mhz/2026-10-12_ax7a200b_budget100t/`](../../vivado/vivado_bbht_grover_200mhz/2026-10-12_ax7a200b_budget100t/evidence.md),
benchmark는 [`../../vivado/vivado_bbht_grover_200mhz/2026-10-12_ax7a200b_board_predicate500/`](../../vivado/vivado_bbht_grover_200mhz/2026-10-12_ax7a200b_board_predicate500/evidence.md) 와
[`../../vivado/vivado_bbht_grover_200mhz/2026-10-13_ax7a200b_board_500run/`](../../vivado/vivado_bbht_grover_200mhz/2026-10-13_ax7a200b_board_500run/evidence.md) 입니다.

**Arty 100T에는 구울 수 없습니다** (부품이 다름). 이 revision은 Arty 100T로 구현한 적이 없습니다.

## file

| file | 내용 |
|---|---|
| `ax7a200b.bit` | bitstream (`clk_accel` 200 MHz, system 50 MHz) |
| `bbht_console.sram.hex` | UART 명령 shell (Predicate500에 쓴 app) |
| `bbht_paper_bench.sram.hex` | 500 runs 실시간 benchmark app (500 runs에 쓴 것). 100 MHz revision과 byte가 같습니다 |
| `sha256sums.txt` | 위 file들의 hash |
| `ocd/` | app load용 OpenOCD 묶음. 상대경로라 원격 host에 그대로 복사해 씁니다 |

`ocd/` 의 `arch/` 는 이 platform이 생성한 memory map이라 다른 configuration과 섞어 쓰지 마십시오. `openocd_rvp`
실행 file(12 MB)은 저장소에 두지 않습니다. `/opt/rvx/local_setup/ocd/openocd_rvp` 를 `ocd/` 에 복사합니다.

## 다시 재는 법

```bash
hardware_bram/sim/board_run.sh final_200mhz predicate500 3600   # 굽기 · 적재 · 네 술어 측정
hardware_bram/sim/board_run.sh final_200mhz                      # 500런 (RTL 대조는 board_vs_bench500.py 가 이 모델을 몰라 따로 함)
.claude/skills/fpga-flash/scripts/sdsl_fpga.sh restore --pcie         # 끝나면 반드시
```

`board_run.sh` 는 platform의 `.fpga_syn_rvx_last` 가 가리키는 implementation directory의 `imp_result/*.ax7a200b.bit` 를 굽습니다.
이 build는 원격 server에서 구현했으므로, 이 묶음의 `ax7a200b.bit` 를 그 자리에 두고 implementation directory 경로를
`.fpga_syn_rvx_last` 에 적은 뒤 돌렸습니다.
