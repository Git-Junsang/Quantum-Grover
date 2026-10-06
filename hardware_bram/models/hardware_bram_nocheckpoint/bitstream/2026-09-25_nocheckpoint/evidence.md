# 체크포인트 없는 판 비트스트림과 콘솔 앱 — 보드에 굽는 묶음

## 무엇인가

`hardware_bram_nocheckpoint`(연산기 네 벌 E4 만 켜고 체크포인트 · 정책 엔진 · 측정
최적화 M1/M2 를 끈 Normal-E4)를 RVX 플랫폼 `bbht_grover_nocheckpoint` 로 Arty A7-100T 에
구현한 비트스트림과, 그 위에 올릴 `bbht_console` 입니다. 최적화 유무에 따른 속도를
체크포인트 판(K3/H3-E4-M2)과 같은 보드에서 맞대려고 만들었습니다. 구현 리포트는
[`../../vivado/vivado_bbht_grover_nocheckpoint/2026-09-25_nocheckpoint_build/`](../../vivado/vivado_bbht_grover_nocheckpoint/2026-09-25_nocheckpoint_build/evidence.md)
(100 MHz 타이밍 클로즈, WNS +0.193 ns)에 있습니다.

| 파일 | 내용 |
|---|---|
| `arty-100t.bit` | RVX SoC + Normal-E4 가속기. Vivado 2026.1, 빌드 2026-09-25 |
| `bbht_console.sram.hex` | 2026-09-25 판 `bbht_console` **UART 판** SRAM 이미지. 소스는 체크포인트 판 묶음과 같고 플랫폼 헤더만 다릅니다 |
| `sha256sums.txt` | 위 둘의 해시. 비트스트림은 구현 묶음 `bitstream_sha256.txt` 와 같습니다 |
| `program_fpga.tcl` | Vivado 배치 모드 굽기 스크립트 (체크포인트 판 묶음과 같은 것) |
| `ocd/` | JTAG 로 앱을 SRAM 에 올리는 묶음 |

`ocd/` 는 [`hardware_bram/models/hardware_bram_K3H3_E4_M2/bitstream/2026-09-25_console_predicate500/ocd/`](../../../hardware_bram_K3H3_E4_M2/bitstream/2026-09-25_console_predicate500/evidence.md)
를 복사하고 `arch/` 세 파일만 이 플랫폼이 생성한 것으로 바꿨습니다. 그중 실제로 달라진
줄은 `hw_info.tcl` 의 `PLATFORM_NAME` 하나입니다(SoC 구성이 같으므로 메모리 맵도 같습니다).
`arty-100t.cfg` 와 `run_bbht_console.tcl` 은 RVX 가 이 플랫폼에 만든 것과 글자까지 같습니다.

## 콘솔이 체크포인트 판과 다른 점

소스가 같으므로 명령도 같습니다. 다른 것은 둘입니다.

- `ID` 가 `STAT platform=bbht_grover_nocheckpoint` 를 냅니다. 호스트 자동 테스트가 이것을
  보고 Normal 만 돌립니다 (2,000 실행)
- `SET BURST=1` 은 받아들이지만 어댑터가 Main IP 에 넘기지 않아 Normal 로 돕니다.
  DRAM 갈래와 같은 약속입니다

## 확인한 것과 아직인 것

| 확인 | 결과 |
|---|---|
| 같은 구성의 Predicate500 (verilator) | Normal 2,000/2,000 이 SW 기준모델과 일치. 체크포인트 판을 M1=M2=0 으로 빌드한 Normal 과 사이클까지 2,000/2,000 같음 ([`results/2026-09-25_predicate500_rtl/`](../../results/2026-09-25_predicate500_rtl/evidence.md)) |
| 구현 | 셋업 WNS +0.193 ns, 홀드 WHS +0.012 ns. 제약 전부 만족. RVX 가 "알 수 없음" 으로 분류한 critical warning 0 건 |
| 보드 빌드 ELF 안의 `script done` 문자열 | 없음 — UART 판 |
| **보드 (2026-10-04)** | NORMAL 2,000 이 SW 기준모델과 2,000/2,000, RTL 벤치와 사이클까지 2,000/2,000. 같은 보드에서 체크포인트 판이 실경과 시간으로 2.810배 빠름 — [`vivado/.../2026-10-04_board_predicate500`](../../vivado/vivado_bbht_grover_nocheckpoint/2026-10-04_board_predicate500/evidence.md) |

## 굽고 올리고 돌리는 법

```bash
# 1. 비트스트림
vivado -mode batch -source program_fpga.tcl

# 2. 앱 (JTAG 어댑터가 붙은 PC. openocd_rvp 는 체크포인트 판 묶음 설명과 같은 것)
cp /opt/rvx/local_setup/ocd/openocd_rvp ocd/
cp bbht_console.sram.hex ocd/
ocd/ocd_keep.sh &

# 3. 확인과 자동 테스트 (저장소 루트에서)
python3 software/host/bbht_cli.py --port /dev/ttyUSB1 selftest
python3 software/host/bbht_predicate500.py --port /dev/ttyUSB1      # Normal 2,000 실행
```

3번 자동 테스트의 결과 엑셀은 다른 두 판과 같은 형식이고, 물리 반복은 기댓값의
`actual_iter_normal` 열과 맞댑니다
([기술문서 19장](../../../../../documents/design_references/19_Predicate500_자동_테스트.md)).
체크포인트 판 결과 엑셀의 `wall_us` 와 나란히 놓으면 보드 실경과 시간으로 본 최적화
효과가 됩니다.
