# 2026-09-17 보드 콘솔 실측 — 통신 계층 재빌드판 첫 굽기

## 결론

2026-09-16 에 우리 통신 계층 판으로 다시 낸 비트스트림을 Arty A7-100T 에 처음 구웠고,
호스트 PC 가 UART 로 명령을 보내 `bbht_console` 을 몰았습니다. **selftest 7/7 일치,
RUN·STAT·ENUM 결과 줄 26개가 SoC RTL 시뮬 트랜스크립트
([`2026-09-16_soc_rtl_console/transcript.txt`](../../../results/2026-09-16_soc_rtl_console/transcript.txt))
와 26/26 글자 그대로 같습니다.** 시뮬에서 한 번도 돌지 않았던 "PC → 보드" 수신 경로
(`read_line()` 의 UART 판, `bbht_cli.py` 의 시리얼 트랜스포트)가 여기서 처음 확인됐습니다.

## 무엇을 구웠나

| 항목 | 값 |
|---|---|
| 비트스트림 sha256 | `1b67a070…52adc61` — [`2026-09-16_comm_layer_rebuild/bitstream_sha256.txt`](../2026-09-16_comm_layer_rebuild/bitstream_sha256.txt) 와 같음 |
| 앱 | `bbht_console.sram.hex` (UART 판, sha256 `51e1684c…2e7cf3`), Olimex ARM-USB-TINY-H JTAG 로 SRAM 적재 |
| 호스트 | Windows 11, `bbht_cli.py --port COM6` (115200 8N1), openocd_rvp 는 WSL2 Ubuntu 26.04 + usbipd |
| 순서 | 굽기 → 앱 적재 → `selftest` → [`board_test.txt`](board_test.txt). 굽고 나서 첫 RUN |

## 결과 (원본 [`board_run.log`](board_run.log) · [`selftest.txt`](selftest.txt))

| 줄 | idx | trials | l | iters | cyc |
|---|--:|--:|--:|--:|--:|
| RUN Normal (`BURST=0`) | 8685 | 21 | 119 | 119 | 41,310 |
| RUN 체크포인트 첫째 | 8685 | 21 | 119 | 38 | 20,935 |
| RUN 체크포인트 둘째 | 8685 | 21 | 119 | 38 | 17,847 |
| ENUM | 8685 → 2852 → 507 → 4724 | | | | 280,494 |

정책 엔진 통계(`policy_cyc` `memo_hit` `max_latency` 등)까지 시뮬과 같습니다.
체크포인트 두 줄의 사이클이 다른 것(3,088 차이)은 실행 이력 차이이고(리셋 뒤 첫 탐색만
memo 청소를 치름), 두 값 모두 시뮬과 같습니다.

**`us=` 는 실경과 시간이 아닙니다.** 펌웨어가 `bbht_cycles_to_us(cycle_count)` 로
사이클에서 환산한 값(100 MHz 기준)이라 시뮬과 같게 나옵니다. 이 묶음으로 실경과 시간을
인용하지 마십시오.

## 보드에서 새로 발견해 고친 것

1. **COM 포트를 열 때 DTR/RTS 가 켜지면 SoC 가 리셋됩니다.** 앱이 JTAG 로 올린 SRAM
   이미지뿐이라, 기본 설정으로 포트를 열면 그 뒤로 에코조차 오지 않고
   (`ERR HOST_TIMEOUT`) 앱을 다시 적재해야 돌아옵니다. 한 핸들로 열어 둔 채로는
   OpenOCD 종료 뒤에도 계속 응답하고, 닫았다 다시 열면 멈추는 것으로 좁혔습니다.
   DTR/RTS 를 내린 채 열면 여러 번 열고 닫아도 응답합니다.
   `software/host/bbht_cli.py` 의 `SerialTransport` 가 열기 전에 둘을 내리도록 고쳤습니다.
2. Windows 에서 `--script` · `--log` 파일을 cp949 로 열어 한글 주석에서 죽던 것을
   UTF-8 로 고쳤습니다.

## 남은 것

- 실경과 시간 측정: 콘솔은 사이클 환산값만 내므로, 필요하면 보드 타이머를 읽도록 펌웨어를 바꿔야 합니다.
- 보드 RESET 버튼이나 포트 재열기 뒤에는 앱을 다시 적재해야 합니다(SPI 플래시 부팅 미적용).
