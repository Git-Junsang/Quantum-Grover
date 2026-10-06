# Predicate500 콘솔판 — 같은 비트스트림에 새 `bbht_console` 을 얹은 묶음

## 무엇인가

보드에서 네 술어 × 500 워크로드 자동 테스트(`software/host/bbht_predicate500.py`)를
돌릴 때 굽고 올릴 파일 묶음입니다. **비트스트림은 새로 내지 않았습니다.** 하드웨어는
2026-09-17 에 보드에서 확인한 것 그대로이고, 바뀐 것은 SRAM 에 올리는 콘솔 앱뿐입니다.

| 파일 | 내용 |
|---|---|
| `arty-100t.bit` | [`../2026-09-17_comm_layer_rebuild/`](../2026-09-17_comm_layer_rebuild/evidence.md) 의 것과 **바이트 동일** (sha256 `1b67a070…`) |
| `bbht_console.sram.hex` | 2026-09-25 판 `bbht_console` **UART 판** SRAM 이미지 (42,440 바이트) |
| `sha256sums.txt` | 위 둘의 해시 |
| `program_fpga.tcl` | Vivado 배치 모드 굽기 스크립트. 같은 폴더의 `arty-100t.bit` 를 씁니다 |
| `ocd/` | JTAG 로 앱을 SRAM 에 올리는 묶음. 2026-09-17 묶음의 `ocd/` 와 파일 전부 같습니다 |

## 콘솔 앱에서 바뀐 것

자세한 명령 형식은 [기술문서 14장](../../../../../documents/design_references/14_호스트_인터페이스와_UART_프로토콜.md)
에 있습니다.

- `GEN PRED= A= B=` — 네 술어 데이터셋을 보드 안에서 만듭니다. 생성 규칙은 SW 생성기
  `software/models/common/benchmark_dataset.py` 의 `generate_predicate_image` 를 C 로 옮긴
  `firmware/bbht_console/src/bbht_dataset_gen.h` 입니다. 호스트가 16,384 워드를 UART 로
  보내지 않아도 되고, 둘이 같은지는 `SUM` 의 FNV-1a 해시로 매번 확인합니다
- `SUM` — 데이터셋 해시 · 정답 수 · 술어 · 적재 여부
- `RUN` 응답에 `wall_us=` — 드라이버 `bbht_search_single_timed()` 가 COMMAND 쓰기부터
  DONE 확인까지 RVX 실시간 타이머로 잰 값. `us=` 는 여전히 사이클 환산값입니다
- `ID` 에 `STAT platform= fw=` 한 줄 — 러너가 bram / dram 갈래를 여기서 알아봅니다
- 새 오류 토큰 `BAD_THRESHOLD` · `TARGET_GUARD`

## 확인한 것

| 확인 | 결과 |
|---|---|
| 보드 빌드(`TARGET_IMP_CLASS=arty-100t`) ELF 안의 `script done` 문자열 | 없음 — UART 판 |
| 같은 ELF 안의 `wall_us=` · `TARGET_GUARD` · `2026-09-25` | 있음 — 새 판 |
| C 생성기 대 SW 생성기 (`make -C hardware_bram/sim console-gen`, 호스트 gcc) | 20/20 해시 일치 (네 술어 × M 다섯) |
| 같은 소스의 RTL 시뮬판을 SoC RTL 시뮬에서 러너 스크립트로 | 16/16 PASS, 데이터셋 해시 4/4 — [`2026-09-25_soc_rtl_predicate500`](../../results/2026-09-25_soc_rtl_predicate500/evidence.md) |
| **보드 (2026-10-04)** | 네 술어 × 500 × 두 모드 4,000 실행이 SW 기준모델과 4,000/4,000. EQ 체크포인트 500 은 보드 정본 M2 와 궤적 500/500, 실경과 합 55,963 대 55,798 us — [`vivado/.../2026-10-04_board_predicate500`](../../vivado/vivado_bbht_grover_fpga/2026-10-04_board_predicate500/evidence.md) |

## 굽고 올리고 돌리는 법

```bash
# 1. 비트스트림
vivado -mode batch -source program_fpga.tcl

# 2. 앱 (JTAG 어댑터가 붙은 PC. openocd_rvp 는 2026-09-17 묶음 설명과 같은 것)
cp /opt/rvx/local_setup/ocd/openocd_rvp ocd/
cp bbht_console.sram.hex ocd/
ocd/ocd_keep.sh &

# 3. 자동 테스트 (저장소 루트에서. 2,000 데이터셋-시드 쌍 x Normal·체크포인트)
python3 software/host/bbht_predicate500.py --port /dev/ttyUSB1
```

3번의 옵션과 결과 엑셀 형식은
[기술문서 19장](../../../../../documents/design_references/19_Predicate500_자동_테스트.md)
에 있습니다.
