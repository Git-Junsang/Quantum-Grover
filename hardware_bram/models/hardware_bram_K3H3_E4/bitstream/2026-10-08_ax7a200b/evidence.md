# K3/H3-E4 — AX7A200B 비트스트림 (100T 예산)

원격 보드 AX7A200B(`xc7a200tfbg484-2`)에 2026-10-08 에 실제로 구워 500런을 잰 비트스트림과 앱입니다.
구현 조건과 리포트는 [`../../vivado/vivado_bbht_grover_k3h3_e4/2026-10-07_ax7a200b_budget100t/`](../../vivado/vivado_bbht_grover_k3h3_e4/2026-10-07_ax7a200b_budget100t/evidence.md),
측정은 [`../../vivado/vivado_bbht_grover_k3h3_e4/2026-10-08_ax7a200b_board_500run/`](../../vivado/vivado_bbht_grover_k3h3_e4/2026-10-08_ax7a200b_board_500run/evidence.md) 입니다.

**Arty 100T 에는 구울 수 없습니다** (부품이 다름). 100T 용 실물은 이 모델 폴더의 다른 `bitstream/` 묶음이나
`vivado/.../2026-10-07_arty100t_build/` 를 보십시오.

## 파일

| 파일 | 내용 |
|---|---|
| `ax7a200b.bit` | 비트스트림 |
| `bbht_paper_bench.sram.hex` | 500런 실시간 벤치 (측정에 쓴 앱) |
| `bbht_console.sram.hex` | UART 명령 셸 |
| `sha256sums.txt` | 위 파일들의 해시 |
| `ocd/` | 앱 적재용 OpenOCD 묶음. 상대경로라 원격 호스트에 그대로 복사해 씁니다 |

`ocd/` 의 `arch/` 는 이 모델 플랫폼이 생성한 메모리맵이라 다른 모델과 섞어 쓰지 마십시오. `openocd_rvp`
실행 파일(12 MB)은 저장소에 두지 않습니다. `/opt/rvx/local_setup/ocd/openocd_rvp` 를 `ocd/` 에 복사합니다.

## 다시 재는 법

```bash
hardware_bram/sim/board_run.sh K3H3_E4              # 굽기 · 적재 · 캡처 · bench500 대조
.claude/skills/fpga-flash/scripts/sdsl_fpga.sh restore --pcie   # 끝나면 반드시
```
