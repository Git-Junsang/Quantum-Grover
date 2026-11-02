# 2026-09-17 board console benchmark — Bus Interface rebuild revision 첫 굽기

## 결론

2026-09-16에 우리 Bus Interface revision으로 다시 낸 bitstream을 Arty A7-100T에 처음 구웠고,
host가 UART로 명령을 보내 `bbht_console`을 몰았습니다. **selftest 7/7 일치,
RUN·STAT·ENUM 결과 줄 26개가 SoC RTL simulation transcript
([`2026-09-16_soc_rtl_console/transcript.txt`](../../../results/2026-09-16_soc_rtl_console/transcript.txt))
와 26/26 글자 그대로 같습니다.** simulation에서 한 번도 돌지 않았던 "PC → board" 수신 경로
(`read_line()`의 UART revision, `bbht_cli.py`의 serial transport)가 여기서 처음 확인됐습니다.

## 무엇을 구웠나

| 항목 | 값 |
|---|---|
| bitstream sha256 | `1b67a070…52adc61` — [`2026-09-16_comm_layer_rebuild/bitstream_sha256.txt`](../2026-09-16_comm_layer_rebuild/bitstream_sha256.txt)와 같음 |
| app | `bbht_console.sram.hex` (UART revision, sha256 `51e1684c…2e7cf3`), Olimex ARM-USB-TINY-H JTAG로 SRAM load |
| host | Windows 11, `bbht_cli.py --port COM6` (115200 8N1), openocd_rvp는 WSL2 Ubuntu 26.04 + usbipd |
| 순서 | 굽기 → app load → `selftest` → [`board_test.txt`](board_test.txt). 굽고 나서 첫 RUN |

## 결과 (원본 [`board_run.log`](board_run.log) · [`selftest.txt`](selftest.txt))

| 줄 | idx | trials | l | iters | cyc |
|---|--:|--:|--:|--:|--:|
| RUN Restart mode (`BURST=0`) | 8685 | 21 | 119 | 119 | 41,310 |
| RUN Checkpoint mode 첫째 | 8685 | 21 | 119 | 38 | 20,935 |
| RUN Checkpoint mode 둘째 | 8685 | 21 | 119 | 38 | 17,847 |
| ENUM | 8685 → 2852 → 507 → 4724 | | | | 280,494 |

Policy Engine 통계(`policy_cyc` `memo_hit` `max_latency` 등)까지 simulation과 같습니다.
Checkpoint mode 두 줄의 cycle이 다른 것(3,088 차이)은 실행 이력 차이이고(reset 뒤 첫 search만
memo table 청소를 치름), 두 값 모두 simulation과 같습니다.

**`us=`는 wall-clock time이 아닙니다.** firmware가 `bbht_cycles_to_us(cycle_count)`로
cycle에서 환산한 값(100 MHz 기준)이라 simulation과 같게 나옵니다. 이 묶음으로 wall-clock time을
인용하지 마십시오.

## board에서 새로 발견해 고친 것

1. **COM port를 열 때 DTR/RTS가 켜지면 SoC가 reset됩니다.** app이 JTAG로 올린 SRAM
   image뿐이라, 기본 설정으로 port를 열면 그 뒤로 echo조차 오지 않고
   (`ERR HOST_TIMEOUT`) app을 다시 load해야 돌아옵니다. 한 handle로 열어 둔 채로는
   OpenOCD 종료 뒤에도 계속 응답하고, 닫았다 다시 열면 멈추는 것으로 좁혔습니다.
   DTR/RTS를 내린 채 열면 여러 번 열고 닫아도 응답합니다.
   `software/host_fpga_develop/bbht_cli.py`의 `SerialTransport`가 열기 전에 둘을 내리도록 고쳤습니다.
2. Windows에서 `--script` · `--log` file을 cp949로 열어 한글 주석에서 죽던 것을
   UTF-8로 고쳤습니다.

## 남은 것

- wall-clock time benchmark: console은 cycle 환산값만 내므로, 필요하면 board timer를 읽도록 firmware를 바꿔야 합니다.
- board RESET 버튼이나 port 재열기 뒤에는 app을 다시 load해야 합니다(SPI flash boot 미적용).
