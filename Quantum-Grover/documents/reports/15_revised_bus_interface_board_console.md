# 실험 15. Bus Interface revision board console

> [← 실험 14 Common500 software · FPGA 비교](14_common500_software_fpga_comparison.md) · [index](index.md) · [실험 16 세 revision의 board Predicate500 →](16_three_revisions_board_predicate500.md)

---

| 확인한 것 | 근거의 축 |
|---|---|
| Bus Interface revision이 실물 board에서 SoC simulation과 같은 결과를 내는가. 성능 인용에는 쓰지 않음 | board console 한 session (workload 하나) |

2026-09-16에 Bus Interface를 교체해 생성한 bitstream을 Arty A7-100T에 기록하고, host
PC에서 UART를 통해 `bbht_console`을 제어했습니다.

| 항목 | 값 |
|---|---|
| bitstream | sha256 `1b67a070…52adc61` |
| app | `bbht_console.sram.hex` (UART 입력 build, sha256 `51e1684c…2e7cf3`) |
| load | Olimex ARM-USB-TINY-H JTAG로 SRAM에 |
| host | Windows 11, `bbht_cli.py --port COM6` (115200 8N1) |
| workload | 4 solutions, seed 0 (SoC simulation과 같은 것) |

## 결과

selftest 7/7, RUN · STAT · ENUM 결과 줄 26개가 SoC simulation transcript와 글자 그대로
일치합니다.

| run | idx | trials | l | iters | cyc |
|---|--:|--:|--:|--:|--:|
| Restart mode (`BURST=0`) | 8685 | 21 | 119 | 119 | 41,310 |
| Checkpoint mode 첫째 | 8685 | 21 | 119 | 38 | 20,935 |
| Checkpoint mode 둘째 | 8685 | 21 | 119 | 38 | 17,847 |
| `ENUM` | 8685 → 2852 → 507 → 4724 | | | | 280,494 |

Policy Engine 통계(`policy_cyc` · `memo_hit` · `max_latency` 등)까지 simulation과 같습니다.

근거는 [board_console](../../hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-17_board_console/evidence.md),
실물과 굽기·load 묶음은
[bitstream/2026-09-17_comm_layer_rebuild](../../hardware_bram/configurations/final/bitstream/2026-09-17_comm_layer_rebuild/evidence.md)
입니다.

## 처음 verification된 경로

host → board 수신 경로입니다. `read_line()`의 UART 구현과 `bbht_cli.py`의 serial
transport는 SoC simulation에서 한 번도 돌지 않았습니다(script mode는 명령을 compile-time
array에서 읽습니다). 이 층에서만 나올 수 있는 문제가 실제로 하나 있었습니다.

- COM port를 열 때 DTR/RTS가 켜지면 SoC가 reset됩니다. app이 JTAG로 올린 SRAM
  image뿐이라, 기본 설정으로 port를 열면 그 뒤로 echo조차 오지 않고(`ERR HOST_TIMEOUT`)
  app을 다시 load해야 돌아옵니다. 한 handle로 열어 둔 채로는 OpenOCD 종료 뒤에도 계속
  응답하고, 닫았다 다시 열면 멈추는 것으로 좁혔습니다. `SerialTransport`가 열기 전에
  둘을 내리도록 고쳤습니다.
- Windows에서 `--script` · `--log` file을 cp949로 열어 한글 주석에서 죽던 것을 UTF-8로
  고쳤습니다.
