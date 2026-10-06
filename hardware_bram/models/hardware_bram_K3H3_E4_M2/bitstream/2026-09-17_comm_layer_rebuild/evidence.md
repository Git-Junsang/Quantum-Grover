# 통신 계층 재빌드판 비트스트림과 콘솔 앱 — 보드에 구운 실물

## 무엇인가

2026-09-16 에 **우리 통신 계층 판**(wrapper · mmio · loader · 어댑터)으로 다시 낸
비트스트림과, 그것을 Arty A7-100T 에 굽고 `bbht_console` 을 올릴 때 실제로 쓴 파일
묶음입니다. 2026-09-17 에 이것으로 보드를 몰았고, 실측은
[`../../vivado/vivado_bbht_grover_fpga/2026-09-17_board_console/`](../../vivado/vivado_bbht_grover_fpga/2026-09-17_board_console/evidence.md)
에 있습니다.

보드 정본(`2026-09-08_k3h3_e4_m2`)과 다른 점은 둘입니다 — 통신 계층이 우리 판이고,
user region 이 가속기 클럭을 `clk_accel` 대신 `gclk_accel`(생성 RTL 에서
`assign gclk_accel = clk_accel;` 인 순수 별칭)로 뭅니다. Main IP 는 같습니다.

| 파일 | 내용 |
|---|---|
| `arty-100t.bit` | RVX SoC + 가속기 전체 비트스트림. Vivado 2026.1, 빌드 2026-09-16 |
| `bbht_console.sram.hex` | 보드에 올린 `bbht_console` **UART 판** SRAM 이미지 (40,232 바이트) |
| `sha256sums.txt` | 위 둘의 해시 |
| `program_fpga.tcl` | Vivado 배치 모드 굽기 스크립트 |
| `ocd/` | JTAG 로 앱을 SRAM 에 올리는 묶음 (아래) |

두 해시 모두 구현 묶음
[`2026-09-16_comm_layer_rebuild/bitstream_sha256.txt`](../../vivado/vivado_bbht_grover_fpga/2026-09-16_comm_layer_rebuild/bitstream_sha256.txt)
및 보드 실측 묶음 `evidence.md` 가 적어 둔 값과 같습니다.

## 이 비트스트림이 낸 것

- 구현 리포트 — [`2026-09-16_comm_layer_rebuild/`](../../vivado/vivado_bbht_grover_fpga/2026-09-16_comm_layer_rebuild/)
  (WNS +0.196 ns. 보드 정본 빌드는 +0.126 ns, BRAM·DSP 동일, LUT 168 적음)
- 보드 콘솔 실측 — [`2026-09-17_board_console/`](../../vivado/vivado_bbht_grover_fpga/2026-09-17_board_console/evidence.md)
  (selftest 7/7, RUN·STAT·ENUM 이 SoC RTL 시뮬 트랜스크립트와 글자 그대로 일치)

**이 묶음으로 성능을 인용하지 마십시오.** 콘솔은 워크로드 하나(M = 4, 시드 0)만 돌렸고
`us=` 는 사이클 환산값입니다. 성능 세 축의 정본은 `CLAUDE.md` 2절에 있습니다.

## `ocd/` — 앱을 SRAM 에 올리는 묶음

RVX 가 `imp` 폴더에 내주는 OCD 환경은 `/opt/rvx` 절대경로를 읽어서 다른 PC 에서 못
씁니다. 그래서 필요한 tcl 을 이 폴더 안 상대경로로 모아 두었습니다. `arch/` 셋은
플랫폼 `bbht_grover_upgrade` 가 생성한 것이고, `rvx_env/` 14개는 RVX devkit 의
공용 함수입니다. `set_ocd_env.tcl` 이 그 둘을 상대경로로 읽도록 우리가 다시 썼습니다.

| 파일 | 역할 |
|---|---|
| `arty-100t.cfg` | OpenOCD 설정. Olimex ARM-USB-TINY-H, 10 MHz, JTAG tap `rvp.noc` 0xc47f80a1 |
| `run_bbht_console.tcl` | 플랫폼 리셋 → `bbht_console.sram.hex` 를 SRAM 에 write → `set_all_ready` |
| `set_ocd_env.tcl` | `arch/` · `rvx_env/` 를 상대경로로 읽는 우리 판 |
| `load_app.sh` | 올리고 빠져나옴 |
| `ocd_keep.sh` | 올린 뒤 OpenOCD 를 **붙여 둔 채 유지**. 빠져나오면 어댑터가 플랫폼을 리셋해 SRAM 의 앱이 날아갑니다 |

`openocd_rvp` 실행 파일(12 MB)은 두지 않았습니다.
`/opt/rvx/local_setup/ocd/openocd_rvp` 와 sha256 이
`da54bfd871d7f7eb00b2726727f75bb85c7ab6defaaa0365b127fb5fe765c53e` 로 같으니 그것을
이 폴더에 복사해 쓰십시오.

## 굽고 올리는 법

```bash
# 1. 비트스트림 (Vivado, 헤드리스 가능)
vivado -mode batch -source program_fpga.tcl

# 2. 앱 (JTAG 어댑터가 붙어 있는 PC 에서. Windows 면 usbipd 로 WSL 에 넘긴 뒤)
cp /opt/rvx/local_setup/ocd/openocd_rvp ocd/
cp bbht_console.sram.hex ocd/
ocd/ocd_keep.sh &          # 붙여 둔 채 유지. load_app.sh 는 올리고 빠져나옵니다

# 3. 호스트에서 명령 (COM 포트 번호는 환경에 맞게)
python3 software/host/bbht_cli.py --port /dev/ttyUSB1 selftest
```

보드 RESET 버튼을 누르거나 OpenOCD 를 놓으면 앱이 날아가므로 2번부터 다시 합니다
(SPI 플래시 부팅은 아직 안 넣었습니다).
