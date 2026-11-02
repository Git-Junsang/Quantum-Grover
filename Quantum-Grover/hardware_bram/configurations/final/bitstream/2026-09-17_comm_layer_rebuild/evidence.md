# Bus Interface rebuild revision의 bitstream과 console app — board에 구운 실물

## 무엇인가

2026-09-16에 **우리 Bus Interface revision**(wrapper · mmio · loader · adapter)으로 다시 낸
bitstream과, 그것을 Arty A7-100T에 굽고 `bbht_console`을 올릴 때 실제로 쓴 file
묶음입니다. 2026-09-17에 이것으로 board를 몰았고, benchmark는
[`../../vivado/vivado_bbht_grover_fpga/2026-09-17_board_console/`](../../vivado/vivado_bbht_grover_fpga/2026-09-17_board_console/evidence.md)
에 있습니다.

Board-Verified Build(`2026-09-08_k3h3_e4_m2`)와 다른 점은 둘입니다 — Bus Interface가 우리 revision이고,
user region이 accelerator clock을 `clk_accel` 대신 `gclk_accel`(생성 RTL에서
`assign gclk_accel = clk_accel;` 인 순수 별칭)로 뭅니다. Accelerator Core는 같습니다.

| file | 내용 |
|---|---|
| `arty-100t.bit` | RVX SoC + accelerator 전체 bitstream. Vivado 2026.1, build 2026-09-16 |
| `bbht_console.sram.hex` | board에 올린 `bbht_console` **UART revision** SRAM image (40,232 bytes) |
| `sha256sums.txt` | 위 둘의 hash |
| `program_fpga.tcl` | Vivado batch mode 굽기 script |
| `ocd/` | JTAG로 app을 SRAM에 올리는 묶음 (아래) |

두 hash 모두 implementation 묶음
[`2026-09-16_comm_layer_rebuild/bitstream_sha256.txt`](../../vivado/vivado_bbht_grover_fpga/2026-09-16_comm_layer_rebuild/bitstream_sha256.txt)
및 board benchmark 묶음 `evidence.md`가 적어 둔 값과 같습니다.

## 이 bitstream이 낸 것

- implementation report — [`2026-09-16_comm_layer_rebuild/`](../../vivado/vivado_bbht_grover_fpga/2026-09-16_comm_layer_rebuild/)
  (WNS +0.196 ns. Board-Verified Build는 +0.126 ns, BRAM·DSP 동일, LUT 168 적음)
- board console benchmark — [`2026-09-17_board_console/`](../../vivado/vivado_bbht_grover_fpga/2026-09-17_board_console/evidence.md)
  (selftest 7/7, RUN·STAT·ENUM이 SoC RTL simulation transcript와 글자 그대로 일치)

**이 묶음으로 성능을 인용하지 마십시오.** console은 workload 하나(4 solutions, seed 0)만 돌렸고
`us=`는 cycle 환산값입니다. 성능 세 축의 source of truth는 `CLAUDE.md` 2절에 있습니다.

## `ocd/` — app을 SRAM에 올리는 묶음

RVX가 `imp` directory에 내주는 OCD 환경은 `/opt/rvx` 절대경로를 읽어서 다른 PC에서 못
씁니다. 그래서 필요한 tcl을 이 directory 안 상대경로로 모아 두었습니다. `arch/` 셋은
platform `bbht_grover_upgrade`가 생성한 것이고, `rvx_env/` 14개는 RVX devkit의
공용 function입니다. `set_ocd_env.tcl`이 그 둘을 상대경로로 읽도록 우리가 다시 썼습니다.

| file | 역할 |
|---|---|
| `arty-100t.cfg` | OpenOCD 설정. Olimex ARM-USB-TINY-H, 10 MHz, JTAG tap `rvp.noc` 0xc47f80a1 |
| `run_bbht_console.tcl` | platform reset → `bbht_console.sram.hex`를 SRAM에 write → `set_all_ready` |
| `set_ocd_env.tcl` | `arch/` · `rvx_env/`를 상대경로로 읽는 우리 revision |
| `load_app.sh` | 올리고 빠져나옴 |
| `ocd_keep.sh` | 올린 뒤 OpenOCD를 **붙여 둔 채 유지**. 빠져나오면 adapter가 platform을 reset해 SRAM의 app이 날아갑니다 |

`openocd_rvp` 실행 file(12 MB)은 두지 않았습니다.
`/opt/rvx/local_setup/ocd/openocd_rvp`와 sha256이
`da54bfd871d7f7eb00b2726727f75bb85c7ab6defaaa0365b127fb5fe765c53e`로 같으니 그것을
이 directory에 복사해 쓰십시오.

## 굽고 올리는 법

```bash
# 1. 비트스트림 (Vivado, 헤드리스 가능)
vivado -mode batch -source program_fpga.tcl

# 2. 앱 (JTAG 어댑터가 붙어 있는 PC 에서. Windows 면 usbipd 로 WSL 에 넘긴 뒤)
cp /opt/rvx/local_setup/ocd/openocd_rvp ocd/
cp bbht_console.sram.hex ocd/
ocd/ocd_keep.sh &          # 붙여 둔 채 유지. load_app.sh 는 올리고 빠져나옵니다

# 3. 호스트에서 명령 (COM 포트 번호는 환경에 맞게)
python3 software/host_fpga_develop/bbht_cli.py --port /dev/ttyUSB1 selftest
```

board RESET 버튼을 누르거나 OpenOCD를 놓으면 app이 날아가므로 2번부터 다시 합니다
(SPI flash boot는 아직 안 넣었습니다).
