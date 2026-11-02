# DRAM Variant bitstream과 console app — board에 굽는 묶음

## 무엇인가

`hardware_dram/` variant(DRAM 전량 저장 + 32-bit AXI4 bridge)를 RVX platform
`bbht_grover_dram`으로 Arty A7-100T에 구현한 첫 bitstream과, 그 위에 올릴
`bbht_console`입니다. implementation report는
[`../../vivado/vivado_bbht_grover_dram/2026-09-25_dram_axi_build/`](../../vivado/vivado_bbht_grover_dram/2026-09-25_dram_axi_build/evidence.md)
(100 MHz timing closure, WNS +0.005 ns)에 있습니다.

| file | 내용 |
|---|---|
| `arty-100t.bit` | RVX SoC + DDR3 MIG + DRAM Variant accelerator 전체. Vivado 2026.1, build 2026-09-25 |
| `bbht_console.sram.hex` | 2026-09-25 revision의 `bbht_console` **UART revision** SRAM image (42,440 bytes). source는 bram 묶음과 같고 platform header만 다릅니다 |
| `sha256sums.txt` | 위 둘의 hash. bitstream은 implementation 묶음 `bitstream_sha256.txt`와 같습니다 |
| `program_fpga.tcl` | Vivado batch mode 굽기 script (bram 묶음과 같은 것) |
| `ocd/` | JTAG로 app을 SRAM에 올리는 묶음 |

`ocd/`는 [`hardware_bram/configurations/final/bitstream/2026-09-25_console_predicate500/ocd/`](../../../hardware_bram/configurations/final/bitstream/2026-09-25_console_predicate500/evidence.md)
를 복사하고 `arch/` 세 file만 이 platform이 생성한 것으로 바꿨습니다. OpenOCD 설정
(`arty-100t.cfg`)과 app load script(`run_bbht_console.tcl`)는 RVX가 이 platform에 만든 것과
bram 것이 글자까지 같습니다. `use_large_ram_manually` 때문에 `LARGE_RAM_BASEADDR`가
정의되지 않아서 load script는 SRAM 에만 씁니다 — DRAM은 accelerator의 amplitude table 전용입니다.

## console이 BRAM Variant 쪽과 다른 점

source가 같으므로 명령도 같습니다. 다른 것은 셋입니다.

- `ID`가 `STAT platform=bbht_grover_dram`을 냅니다. host 자동 test가 이것을 보고
  Restart mode만 돌립니다
- `SET BURST=1`은 받아들이지만 이 variant에는 checkpoint가 없어 무시됩니다
- `ENUM`은 `config_error`로 거절됩니다 (DRAM Variant는 single search 전용)

## 확인한 것과 아직인 것

| 확인 | 결과 |
|---|---|
| 같은 RTL (`bbht_dram_axi_top`) 의 Predicate500 + AXI model | 2,000/2,000, backpressure에서도 같음 |
| implementation | setup WNS +0.005 ns, hold WHS +0.021 ns. 제약 전부 만족 |
| board build ELF 안의 `script done` 문자열 | 없음 — UART revision |
| **board (2026-10-04)** | Restart mode 2,000이 software reference model과 2,000/2,000. cycle은 SoC RTL simulation과 0.16% 안, AXI model의 1.439× — [`vivado/.../2026-10-04_board_predicate500`](../../vivado/vivado_bbht_grover_dram/2026-10-04_board_predicate500/evidence.md) |

board에서 처음 볼 것으로 꼽았던 둘입니다. 2026-10-04 board 실행에서 둘 다 문제가 없었습니다.

1. **DDR3 보정.** implementation 묶음의 critical warning 표(MIG 온도 입력 · IDELAY 참조 clock)는
   RVX가 붙이는 MIG 쪽입니다. 보정에 실패하면 accelerator의 첫 AXI request가 돌아오지 않아
   `RUN`이 `HOST_TIMEOUT`으로 끝납니다.
2. **checkpoint slot address.** amplitude table은 DDR의 NoC address `0x0`부터 최대 6 MB(number of iterations 값 128개 × 47,104 bytes)를
   씁니다. linker가 DRAM을 쓰지 않으므로 software와 겹치지 않습니다.

## 굽고 올리고 돌리는 법

```bash
# 1. 비트스트림
vivado -mode batch -source program_fpga.tcl

# 2. 앱 (JTAG 어댑터가 붙은 PC. openocd_rvp 는 bram 묶음 설명과 같은 것)
cp /opt/rvx/local_setup/ocd/openocd_rvp ocd/
cp bbht_console.sram.hex ocd/
ocd/ocd_keep.sh &

# 3. 확인과 자동 테스트 (저장소 루트에서)
python3 software/host_fpga_develop/bbht_cli.py --port /dev/ttyUSB1 selftest
python3 software/host_fpga_develop/bbht_predicate500.py --port /dev/ttyUSB1      # NORMAL 2,000 실행
```

3번 자동 test의 결과 Excel은 bram과 같은 형식이고, executed iterations는 expected result의
`actual_iter_dram_session` 열과 맞댑니다
([기술문서 18장](../../../documents/design_references/18_predicate500_automated_test.md)).
