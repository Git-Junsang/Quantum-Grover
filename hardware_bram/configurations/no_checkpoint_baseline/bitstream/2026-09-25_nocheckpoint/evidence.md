# No-Checkpoint Baseline bitstream과 console app — board에 굽는 묶음

## 무엇인가

`no_checkpoint_baseline`(4 PEs만 켜고 checkpoint · Policy Engine · Measurement Unit
최적화(Dual-Row Build · Two-Level Select)를 끈 No-Checkpoint Baseline)를 그때의 RVX platform `bbht_grover_nocheckpoint` 로 Arty A7-100T에
구현한 bitstream과, 그 위에 올릴 `bbht_console` 입니다. 최적화 유무에 따른 속도를
checkpoint revision(final configuration)과 같은 board에서 맞대려고 만들었습니다. implementation report는
[`../../vivado/vivado_bbht_grover_nocheckpoint/2026-09-25_nocheckpoint_build/`](../../vivado/vivado_bbht_grover_nocheckpoint/2026-09-25_nocheckpoint_build/evidence.md)
(100 MHz timing closure, WNS +0.193 ns)에 있습니다.

| file | 내용 |
|---|---|
| `arty-100t.bit` | RVX SoC + No-Checkpoint Baseline accelerator. Vivado 2026.1, build 2026-09-25 |
| `bbht_console.sram.hex` | 2026-09-25 revision `bbht_console` **UART revision** SRAM image. source는 checkpoint revision 묶음과 같고 platform header만 다릅니다 |
| `sha256sums.txt` | 위 둘의 hash. bitstream은 implementation 묶음 `bitstream_sha256.txt` 와 같습니다 |
| `program_fpga.tcl` | Vivado batch mode 굽기 script (checkpoint revision 묶음과 같은 것) |
| `ocd/` | JTAG로 app을 SRAM에 올리는 묶음 |

`ocd/` 는 [`hardware_bram/configurations/final/bitstream/2026-09-25_console_predicate500/ocd/`](../../../final/bitstream/2026-09-25_console_predicate500/evidence.md)
를 복사하고 `arch/` 세 file만 이 platform이 생성한 것으로 바꿨습니다. 그중 실제로 달라진
줄은 `hw_info.tcl` 의 `PLATFORM_NAME` 하나입니다(SoC 구성이 같으므로 memory map도 같습니다).
`arty-100t.cfg` 와 `run_bbht_console.tcl` 은 RVX가 이 platform에 만든 것과 글자까지 같습니다.

## console이 checkpoint revision과 다른 점

source가 같으므로 명령도 같습니다. 다른 것은 둘입니다.

- `ID` 가 `STAT platform=bbht_grover_nocheckpoint` 를 냅니다. host 자동 test가 이것을
  보고 Restart mode만 돌립니다 (2,000 실행)
- `SET BURST=1` 은 받아들이지만 adapter가 Accelerator Core에 넘기지 않아 Restart mode로 돕니다.
  DRAM Variant와 같은 약속입니다

## 확인한 것과 아직인 것

| 확인 | 결과 |
|---|---|
| 같은 configuration의 Predicate500 (verilator) | Restart mode 2,000/2,000이 software reference model과 일치. checkpoint revision을 Single-Row Build · Linear Select로 build한 Restart mode와 cycle까지 2,000/2,000 같음 ([`results/2026-09-25_predicate500_rtl/`](../../results/2026-09-25_predicate500_rtl/evidence.md)) |
| implementation | setup WNS +0.193 ns, hold WHS +0.012 ns. 제약 전부 만족. RVX가 "알 수 없음"으로 분류한 critical warning 0건 |
| board build ELF 안의 `script done` 문자열 | 없음 — UART revision |
| **board (2026-10-04)** | Restart mode 2,000 실행이 software reference model과 2,000/2,000, RTL testbench와 cycle까지 2,000/2,000. 같은 board에서 checkpoint revision이 wall-clock time으로 2.810× 빠름 — [`vivado/.../2026-10-04_board_predicate500`](../../vivado/vivado_bbht_grover_nocheckpoint/2026-10-04_board_predicate500/evidence.md) |

## 굽고 올리고 돌리는 법

```bash
# 1. 비트스트림
vivado -mode batch -source program_fpga.tcl

# 2. 앱 (JTAG 어댑터가 붙은 PC. openocd_rvp 는 체크포인트 판 묶음 설명과 같은 것)
cp /opt/rvx/local_setup/ocd/openocd_rvp ocd/
cp bbht_console.sram.hex ocd/
ocd/ocd_keep.sh &

# 3. 확인과 자동 테스트 (저장소 루트에서)
python3 software/host_fpga_develop/bbht_cli.py --port /dev/ttyUSB1 selftest
python3 software/host_fpga_develop/bbht_predicate500.py --port /dev/ttyUSB1      # Normal 2,000 실행
```

3번 자동 test의 결과 Excel은 다른 두 revision과 같은 형식이고, executed iterations는 expected result의
`actual_iter_normal` 열과 맞댑니다
([기술문서 18장](../../../../../documents/design_references/18_predicate500_automated_test.md)).
checkpoint revision 결과 Excel의 `wall_us` 와 나란히 놓으면 board wall-clock time으로 본 최적화
효과가 됩니다.
