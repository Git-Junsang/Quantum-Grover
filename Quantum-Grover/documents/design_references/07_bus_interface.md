# 7장. Bus Interface

> [← 6장 data 표현과 memory map](06_data_representation_and_memory_map.md) · [index](index.md) · [8장 Accelerator Core 최상위와 BBHT 제어 →](08_accelerator_core_top_and_bbht_control.md)

---

Bus Interface는 네 file입니다. RVX가 만든 port를 Accelerator Core에 잇고 CSR 접근과 data load를
처리합니다.

| file | 역할 |
|---|---|
| [`bbht_rvx_wrapper.v`](../../hardware_bram/src/bbht_rvx_wrapper.v) | 셋을 묶는 wiring |
| [`bbht_grover_mmio.v`](../../hardware_bram/src/bbht_grover_mmio.v) | APB slave · CSR 38개 |
| [`bbht_ahb_loader.v`](../../hardware_bram/src/bbht_ahb_loader.v) | AHB master · dataset DMA |
| [`bbht_grover_core_adapter.v`](../../hardware_bram/configurations/final/src/bbht_grover_core_adapter.v) | 계약 이름·reset 차이 흡수 |

DRAM Variant의 mmio · loader는 이 directory의 것과 byte 동일하고, No-Checkpoint Baseline은 이 directory의
Bus Interface를 그대로 씁니다.

---

## 7.1 wrapper의 제어 logic

```
i_grover_csr (APB slave)  → bbht_grover_mmio  → Accelerator Core 설정·status
i_grover_dma (AHB master) ← bbht_ahb_loader   → Accelerator Core loader port
```

대부분은 signal 연결이고, wrapper가 직접 판단하는 것은 셋입니다.

1. start 수락 조건 ([5장 5.6절](05_hardware_architecture_overview.md#56-시작-명령-수락-조건))
2. `checkpoint_auto_enable = burst_enable && auto_shot`
3. manual checkpoint 입력 전부 0 tie-off (production 설정)

두 번째 규칙 때문에 `auto_shot = 0` 인 Manual mode에서는 checkpoint가 걸리지 않습니다. Manual
mode는 firmware가 number of iterations를 지정하는 verification용 경로라, Policy Engine이 끼어들면 무엇을 재는지 알 수 없게
됩니다. 세 번째 규칙은 계획의 출처를 하나로 두려는 것입니다. 자동 경로와 manual 경로를 동시에
열면 policy 통계가 의미를 잃습니다.

clock은 `gclk_accel`(100 MHz) 하나입니다. CDC는 RVX layer가 처리하므로 이 module에는 넣지
않습니다([5장 5.3절](05_hardware_architecture_overview.md#53-clock과-reset-소유권)).

---

## 7.2 mmio의 register 접근

APB slave를 받아 register file로 만듭니다. address map의 source of truth는
[`bbht_grover_csr.json`](../../spec/bbht_grover_csr.json)이고, mmio가 include 하는
`bbht_grover_csr.vh` 가 그 JSON에서 생성됩니다. RTL에는 offset 숫자를 직접 적지 않으며
`gen_csr.py --check` 의 세 번째 검사가 이것을 지킵니다([13장](13_csr_registers_and_execution_modes.md)).

| 성격 | 뜻 |
|---|---|
| `RW` | 설정. 저장되고 값이 출력 wire로 상시 나갑니다 |
| `W1P` | 명령. 저장 공간이 없고 쓰면 1 cycle pulse만 나갑니다. 읽으면 0. 쓰는 data는 무시하고 쓰는 행위 자체가 명령입니다 |
| `RO` | status. 저장하지 않고 core가 내보내는 wire를 읽기 응답에 실어 보냅니다 |
| `RPOP` | `FIFO_DATA` 하나뿐. 읽기 완료 자체가 pop이라 별도 POP register가 없습니다 |

`pready` 는 constant 1이고 wait state가 없습니다. 정렬되지 않은 접근과 미할당 address는 `pslverr` 로
떨어집니다. decode는 `rpaddr[11:0]` 만 보므로 NoC가 전체 address를 주든 offset을 주든 동작합니다.

`done` 은 Accelerator Core에서 1 clock pulse로 나오므로 mmio가 `done_sticky` 로 잡아 둡니다. 이것을
지우는 것은 `COMMAND` 쓰기뿐입니다. `STATUS` 를 읽어도, 설정을 바꿔도 안 지워집니다.

---

## 7.3 DMA Engine의 사전 검사

system SRAM의 signed 16-bit array를 AHB master로 읽어 Accelerator Core의 generic loader port
(`data_wr_en` / `data_wr_addr` / `data_wr_data`)로 넘깁니다. 전송은 32-bit AHB SINGLE read,
single outstanding이고 data word mapping은 little-endian입니다.

```
word[k][15:0]  -> data[2k]
word[k][31:16] -> data[2k+1]
```

`data_count` 가 홀수면 마지막 data word의 상위 16 bits는 쓰지 않습니다. burst로 올리는 것은 DMA가
실제 병목임이 benchmark로 확인된 뒤에 볼 일이고, 지금은 14 qubits 전체 load가 246 µs 인데 search 한 번이 그보다
훨씬 깁니다([6장 6.8절](06_data_representation_and_memory_map.md#68-system-sram과-load)).

### 시작 전 검사 네 가지

하나라도 걸리면 전송을 시작하지 않고 오류 bit만 세웁니다.

| 검사 | 조건 | 오류 bit |
|---|---|---|
| 정렬 | `data_addr[1:0] == 0` | `align_error` |
| 개수 | `1 <= data_count <= 16384` | `count_error` |
| 범위 | `[data_addr, data_addr + 4*words)` 가 SRAM 안 | `range_error` |
| status | Accelerator Core가 busy가 아닐 것 | `busy_error` |

array가 일부만 load된 채로 oracle을 돌리면 경고 없이 그럴듯한 non-solution이 나옵니다. 결과만
보고는 원인을 찾기 어려워서 전송 전에 설정을 검사합니다. 전송 중 AHB 응답 오류는
`resp_error`, 완료는 `dma_done_sticky` 로 나옵니다([13장 13.6절](13_csr_registers_and_execution_modes.md#136-dma_status-0x060)).

---

## 7.4 adapter

계약 이름 `bbht_grover_core` 와 실물 module `bbht_grover_main_ip`, reset 이름(`rstnn` ↔ `rstn`)
사이를 잇는 wrapper입니다. 61 ports는 1:1이고 폭 변환도 logic도 없습니다. Checkpoint-Capacity · Lookahead-Shots · number of PEs ·
Measurement Microarchitecture parameter의 기본값이 여기 있습니다([8장 8.2절](08_accelerator_core_top_and_bbht_control.md#82-compile-parameter-8개)).

signal만 이어 주므로 logic가 생기지 않습니다. 2026-09-16 implementation의 hierarchy report에서 adapter와 그 안의
Accelerator Core가 같은 LUT 수를 갖습니다.

`bbht_bram_top` 은 adapter를 거치지 않고 Accelerator Core에 직접 연결됩니다
([5장 5.2절](05_hardware_architecture_overview.md#52-module-layer와-file-지도)).

---

## 7.5 계약만 보고 쓴 implementation과 실물의 대조

Bus Interface RTL은 인수인계 문서의 계약(§1.4 CSR map, §1.5 bit 정의, §3.3 ports, §3.4 Accelerator Core
interface, §3.5 동작)만 보고 쓴 별도 implementation이었습니다. 실물 Accelerator Core가 들어오면서 해석이 갈릴 수
있던 자리를 이렇게 정리했습니다.

| # | 항목 | 우리 implementation | 실물과 대조한 결과 |
|:-:|---|---|---|
| 1 | `pending_valid` 의 의미 | mmio의 `done_sticky`. 직전 완료가 안 읽혔으면 새 start를 막음 | 계약에 정의가 없어 우리 해석을 유지. T1~T9가 이 의미로 고정 |
| 2 | `done` / `enum_done` 이 pulse인가 level인가 | rising edge로 latch. 어느 쪽이든 같게 동작 | 실물이 1 clock pulse. 그대로 동작 |
| 3 | core module 이름 | 계약 이름 `bbht_grover_core` | 실물은 `bbht_grover_main_ip`. adapter가 흡수 |
| 4 | `search_busy` | 계약에 없어서 `busy & ~load_busy` 로 유도 | 실물도 따로 안 내보냄. 유도 유지 |
| 5 | `clk` / `rstnn` 이름 | 계약표가 적지 않아 RVX 관례를 따름 | 이름·reset 차이도 adapter가 흡수 |
| 6 | AHB session당 cycle | data word당 3 cycles (SINGLE + 16-bit 쓰기 2회) | Board-Verified Build의 Bus Interface와 같은 testbench에서 같은 cycle |
| 7 | `rpaddr` 가 전체 address인가 offset인가 | `rpaddr[11:0]` 만 decode | board end-to-end로 확인 |

board에 구운 Bus Interface는 PJK revision(wrapper가 Accelerator Core를 adapter 없이 직접 물고, mmio가 offset을
localparam으로 적음)이었고 지금 main은 우리 revision입니다. 두 revision의 CSR offset 표는 38개가 전부
일치하고, 옛 revision은 tag `board-verified-build-2026-09-07` 에 있습니다. 두 revision이 같은 board에서 같은 결과를 낸다는
것은 [실험 16](../reports/16_three_revisions_board_predicate500.md)에서 확인합니다.

---

## 7.6 Bus Interface verification

| 묶음 | 대상 | 무엇을 |
|---|---|---|
| T1~T9 | [`tb_bbht_rvx.v`](../../hardware_bram/testbench/tb_bbht_rvx.v) | CSR round trip, W1P pulse, `rpslverr`, DMA 정상/거절, single search 결과, `done_sticky` clear 규칙, enumeration FIFO read-to-pop |
| D1~D11 | [`tb_driver.cpp`](../../hardware_bram/testbench/tb_driver.cpp) | 실제 firmware driver C code를 그대로 compile해 RTL에 붙임. offset 하나나 polling 순서가 틀리면 여기서 잡힘 |
| H1~H15 | [`tb_bbht_bram_top.v`](../../hardware_bram/testbench/tb_bbht_bram_top.v) | 최상단에 APB로 host 순서를 흉내 내고 14 qubits 전체 load, Restart mode/Checkpoint mode BBHT trajectory 비교, enumeration까지 |

`CORE=stub` 이면 Accelerator Core 자리에 선형 scan stub
([`bbht_grover_core_stub.v`](../../hardware_bram/testbench/bbht_grover_core_stub.v))를
넣습니다. 이때 통과는 Bus Interface가 계약을 지킨다는 뜻이지 search가 맞다는 뜻이 아니므로 search
결과를 인용하면 안 됩니다. `CORE=real` 이면 adapter를 거쳐 실물 Accelerator Core를 뭅니다.

두 Bus Interface revision(Board-Verified Build와 현재 revision)이 같은 testbench에서 T1~T9 · D1~D11을 모두 통과했고,
D5 single search cycle이 63,963으로 같았습니다. port 연결 자체는 `check_ports.py` 가 wrapper
19 signals + core 61 signals를 대조합니다([16장 16.2절](16_verification_framework.md#162-0층-port-계약)).

---

## 7.7 남겨 둔 개선안

2026-09-01 인수인계(v0.9.8)가 "필요가 확인될 때만 검토" 로 남긴 Bus Interface 개선안입니다. 지금 revision도 아래 "현재"
열 그대로이고, 어느 것도 시작하지 않았습니다.

| 후보 | 현재 | 검토할 조건 |
|---|---|---|
| AHB burst · stream load | SINGLE 읽기, single outstanding | DMA가 실제 병목으로 benchmark될 때 |
| interrupt | `done` · DMA · FIFO 모두 polling | software 부담이나 응답성이 문제가 될 때 |
| Result FIFO 깊이 · backpressure 조정 | 깊이 256 | 실제 enumeration의 number of solutions · 점유 · 정지 근거가 있을 때 |
| interface pipeline register | 100 MHz timing 통과 | SoC를 키워 fanout · congestion 문제가 생길 때 |

어느 것을 바꾸든 Accelerator Core의 기능 의미를 바꾸지 않는 것이 먼저이고, RTL regression뿐 아니라 100 MHz full SoC implementation과
board 확인까지 다시 통과해야 기준 revision을 바꿉니다. 옛 INCR16 burst 규격은 이 개선안과 별개로 폐기된 값입니다
([22장](22_appendix_glossary_and_retired_specs.md)).
