# Predicate500 console revision — 같은 bitstream에 새 `bbht_console` 을 얹은 묶음

## 무엇인가

board에서 네 predicate × 500 workloads 자동 test(`software/host_fpga_develop/bbht_predicate500.py`)를
돌릴 때 굽고 올릴 file 묶음입니다. **bitstream은 새로 내지 않았습니다.** hardware는
2026-09-17에 board에서 확인한 것 그대로이고, 바뀐 것은 SRAM에 올리는 console app뿐입니다.

| file | 내용 |
|---|---|
| `arty-100t.bit` | [`../2026-09-17_comm_layer_rebuild/`](../2026-09-17_comm_layer_rebuild/evidence.md) 의 것과 **byte 동일** (sha256 `1b67a070…`) |
| `bbht_console.sram.hex` | 2026-09-25 revision `bbht_console` **UART revision** SRAM image (42,440 bytes) |
| `sha256sums.txt` | 위 둘의 hash |
| `program_fpga.tcl` | Vivado batch mode 굽기 script. 같은 directory의 `arty-100t.bit` 를 씁니다 |
| `ocd/` | JTAG로 app을 SRAM에 올리는 묶음. 2026-09-17 묶음의 `ocd/` 와 file 전부 같습니다 |

## console app에서 바뀐 것

자세한 명령 형식은 [기술문서 14장](../../../../../documents/design_references/14_host_interface_and_uart_protocol.md)
에 있습니다.

- `GEN PRED= A= B=` — 네 predicate dataset을 board 안에서 만듭니다. 생성 규칙은 software 생성기
  `software/reference_model_develop/models/common/benchmark_dataset.py` 의 `generate_predicate_image` 를 C로 옮긴
  `firmware/bbht_console/src/bbht_dataset_gen.h` 입니다. host가 16,384 data words를 UART로
  보내지 않아도 되고, 둘이 같은지는 `SUM` 의 FNV-1a hash로 매번 확인합니다
- `SUM` — dataset hash · number of solutions · predicate · load 여부
- `RUN` 응답에 `wall_us=` — driver `bbht_search_single_timed()` 가 COMMAND 쓰기부터
  DONE 확인까지 RVX 실시간 timer로 잰 값. `us=` 는 여전히 cycle 환산값입니다
- `ID` 에 `STAT platform= fw=` 한 줄 — runner가 bram / dram variant를 여기서 알아봅니다
- 새 오류 token `BAD_THRESHOLD` · `TARGET_GUARD`

## 확인한 것

| 확인 | 결과 |
|---|---|
| board build(`TARGET_IMP_CLASS=arty-100t`) ELF 안의 `script done` 문자열 | 없음 — UART revision |
| 같은 ELF 안의 `wall_us=` · `TARGET_GUARD` · `2026-09-25` | 있음 — 새 revision |
| C 생성기 대 software 생성기 (`make -C hardware_bram/sim console-gen`, host gcc) | 20/20 hashes 일치 (네 predicate × 다섯 가지 number of solutions) |
| 같은 source의 RTL simulation revision을 SoC RTL simulation에서 runner script로 | 16/16 PASS, dataset hash 4/4 — [`2026-09-25_soc_rtl_predicate500`](../../results/2026-09-25_soc_rtl_predicate500/evidence.md) |
| **board (2026-10-04)** | 네 predicate × 500 × 두 mode 4,000 실행이 software reference model과 4,000/4,000. EQ Checkpoint mode 500 runs는 Board-Verified Build와 BBHT trajectory 500/500, wall-clock time sum 55,963 대 55,798 µs — [`vivado/.../2026-10-04_board_predicate500`](../../vivado/vivado_bbht_grover_fpga/2026-10-04_board_predicate500/evidence.md) |

## 굽고 올리고 돌리는 법

```bash
# 1. 비트스트림
vivado -mode batch -source program_fpga.tcl

# 2. 앱 (JTAG 어댑터가 붙은 PC. openocd_rvp 는 2026-09-17 묶음 설명과 같은 것)
cp /opt/rvx/local_setup/ocd/openocd_rvp ocd/
cp bbht_console.sram.hex ocd/
ocd/ocd_keep.sh &

# 3. 자동 테스트 (저장소 루트에서. 2,000 데이터셋-시드 쌍 x Normal·체크포인트)
python3 software/host_fpga_develop/bbht_predicate500.py --port /dev/ttyUSB1
```

3번의 option과 결과 Excel 형식은
[기술문서 18장](../../../../../documents/design_references/18_predicate500_automated_test.md)
에 있습니다.
