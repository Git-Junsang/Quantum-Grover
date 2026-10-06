# DRAM 갈래 비트스트림과 콘솔 앱 — 보드에 굽는 묶음

## 무엇인가

`hardware_dram/` 갈래(DRAM 전량 저장 + 32비트 AXI4 브리지)를 RVX 플랫폼
`bbht_grover_dram` 으로 Arty A7-100T 에 구현한 첫 비트스트림과, 그 위에 올릴
`bbht_console` 입니다. 구현 리포트는
[`../../vivado/vivado_bbht_grover_dram/2026-09-25_dram_axi_build/`](../../vivado/vivado_bbht_grover_dram/2026-09-25_dram_axi_build/evidence.md)
(100 MHz 타이밍 클로즈, WNS +0.005 ns) 에 있습니다.

| 파일 | 내용 |
|---|---|
| `arty-100t.bit` | RVX SoC + DDR3 MIG + DRAM 갈래 가속기 전체. Vivado 2026.1, 빌드 2026-09-25 |
| `bbht_console.sram.hex` | 2026-09-25 판 `bbht_console` **UART 판** SRAM 이미지 (42,440 바이트). 소스는 bram 묶음과 같고 플랫폼 헤더만 다릅니다 |
| `sha256sums.txt` | 위 둘의 해시. 비트스트림은 구현 묶음 `bitstream_sha256.txt` 와 같습니다 |
| `program_fpga.tcl` | Vivado 배치 모드 굽기 스크립트 (bram 묶음과 같은 것) |
| `ocd/` | JTAG 로 앱을 SRAM 에 올리는 묶음 |

`ocd/` 는 [`hardware_bram/models/hardware_bram_K3H3_E4_M2/bitstream/2026-09-25_console_predicate500/ocd/`](../../../hardware_bram/models/hardware_bram_K3H3_E4_M2/bitstream/2026-09-25_console_predicate500/evidence.md)
를 복사하고 `arch/` 세 파일만 이 플랫폼이 생성한 것으로 바꿨습니다. OpenOCD 설정
(`arty-100t.cfg`)과 앱 적재 스크립트(`run_bbht_console.tcl`)는 RVX 가 이 플랫폼에 만든 것과
bram 것이 글자까지 같습니다. `use_large_ram_manually` 때문에 `LARGE_RAM_BASEADDR` 가
정의되지 않아서 적재 스크립트는 SRAM 에만 씁니다 — DRAM 은 가속기의 진폭표 전용입니다.

## 콘솔이 bram 판과 다른 점

소스가 같으므로 명령도 같습니다. 다른 것은 셋입니다.

- `ID` 가 `STAT platform=bbht_grover_dram` 을 냅니다. 호스트 자동 테스트가 이것을 보고
  NORMAL 만 돌립니다
- `SET BURST=1` 은 받아들이지만 이 갈래에는 체크포인트가 없어 무시됩니다
- `ENUM` 은 `config_error` 로 거절됩니다 (DRAM 갈래는 단일 탐색 전용)

## 확인한 것과 아직인 것

| 확인 | 결과 |
|---|---|
| 같은 RTL (`bbht_dram_axi_top`) 의 Predicate500 + AXI 모델 | 2,000/2,000, 백프레셔에서도 같음 |
| 구현 | 셋업 WNS +0.005 ns, 홀드 WHS +0.021 ns. 제약 전부 만족 |
| 보드 빌드 ELF 안의 `script done` 문자열 | 없음 — UART 판 |
| **보드 (2026-10-04)** | NORMAL 2,000 이 SW 기준모델과 2,000/2,000. 사이클은 SoC RTL 시뮬과 0.16% 안, AXI 모델의 1.439배 — [`vivado/.../2026-10-04_board_predicate500`](../../vivado/vivado_bbht_grover_dram/2026-10-04_board_predicate500/evidence.md) |

보드에서 처음 볼 것으로 꼽았던 둘입니다. 2026-10-04 보드 실행에서 둘 다 문제가 없었습니다.

1. **DDR3 보정.** 구현 묶음의 critical warning 표(MIG 온도 입력 · IDELAY 참조 클럭)는
   RVX 가 붙이는 MIG 쪽입니다. 보정에 실패하면 가속기의 첫 AXI 요청이 돌아오지 않아
   `RUN` 이 `HOST_TIMEOUT` 으로 끝납니다.
2. **슬롯 주소.** 진폭표는 DDR 의 NoC 주소 `0x0` 부터 최대 6 MB(`j` 128개 × 47,104바이트)를
   씁니다. 링커가 DRAM 을 쓰지 않으므로 소프트웨어와 겹치지 않습니다.

## 굽고 올리고 돌리는 법

```bash
# 1. 비트스트림
vivado -mode batch -source program_fpga.tcl

# 2. 앱 (JTAG 어댑터가 붙은 PC. openocd_rvp 는 bram 묶음 설명과 같은 것)
cp /opt/rvx/local_setup/ocd/openocd_rvp ocd/
cp bbht_console.sram.hex ocd/
ocd/ocd_keep.sh &

# 3. 확인과 자동 테스트 (저장소 루트에서)
python3 software/host/bbht_cli.py --port /dev/ttyUSB1 selftest
python3 software/host/bbht_predicate500.py --port /dev/ttyUSB1      # NORMAL 2,000 실행
```

3번 자동 테스트의 결과 엑셀은 bram 과 같은 형식이고, 물리 반복은 기댓값의
`actual_iter_dram_session` 열과 맞댑니다
([기술문서 19장](../../../documents/design_references/19_Predicate500_자동_테스트.md)).
