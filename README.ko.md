# 다중 predicate Grover search accelerator

온칩 memory에 담긴 data array에서 `<`, `>`, `=`, 범위(`a < x < b`) 네 가지 predicate를
만족하는 index를 Grover algorithm으로 찾는 FPGA emulator accelerator입니다.
host 가 UART 로 predicate와 threshold를 보내면 RVX SoC 안의 accelerator 가 계산해
결과 index를 돌려줍니다.

- board: Arty A7-100T (`xc7a100tcsg324-1`)
- 정합성 기준: **final configuration** (2026-09-07 build, 2026-09-08 benchmark). board에서 검증된 쪽이 Board-Verified Build입니다.

---

## 1. 지금 어디까지 왔는가

| 무엇                                                     | state                                                          |
| -------------------------------------------------------- | ------------------------------------------------------------- |
| Accelerator Core algorithm (14 qubits / 32 lanes / DATA16)                    | final configuration. board sign-off 완료                               |
| Bus Interface (CSR · DMA · FIFO · driver · UART console) | 우리 Bus Interface revision을 board에서 확인. 2026-09-17 명령 왕복, 2026-10-04 네 predicate × 500 × 두 mode 4,000 실행이 reference model과 4,000/4,000 (wall-clock time 포함) |
| 100 MHz implementation                                             | timing 클로즈 (WNS +0.126 ns). report는`hardware_bram/configurations/final/vivado/` |
| **Accelerator Core RTL source**                               | `hardware_bram/src/` 에 revision 한 벌. bitstream과 sha256이 같은 revision은 tag `board-verified-build-2026-09-07` (그 시점 directory 이름은 `hardware_bram/`) |
| 성능 근거                                                | board wall-clock time **7.626×**, RTL cycle **6.1401×**, ORCA 1 core 대비 **116,426×** |
| software reference model                                      | NumPy · Qiskit Aer · Q1.22 bit-exact · a Checkpoint-Capacity of 3 and 3-shot Lookahead policy configuration. board와 같은 500 workloads에서 search BBHT trajectory와 executed iterations가 500/500 일치 |

routing 정합성은 [port 대조기](spec/check_ports.py)가 인수인계 문서의 port 표
(wrapper 19 + core 61)와 RTL 을 맞춰 보며 지킵니다. `stub` · `real` · `dram` 세 variant
모두 일치합니다.

---

## 2. 확정 수치

CSR 의 source of truth는 [`spec/bbht_grover_csr.json`](spec/bbht_grover_csr.json)
하나이고, `gen_csr.py` 가 거기서 Verilog · C · Python header와
기술문서 [13장](documents/design_references/13_csr_registers_and_execution_modes.md)을 만듭니다.
같은 숫자를 들고 있으면서 생성 대상이 아닌 두 곳(software reference model, board testbench app)은
`--check` 가 읽어서 대조합니다.

| 항목        | 값                                                                                            |
| ----------- | --------------------------------------------------------------------------------------------- |
| qubit      | 14 qubits (16,384 states)                                                                           |
| data word | 16-bit signed                                                                                 |
| amplitude        | Q1.22 계열 23 bits                                                                             |
| 병렬도      | 32 lanes                                                                                   |
| predicate        | `LT` · `GT` · `EQ` · `RANGE`                                                       |
| execution mode   | `MANUAL_SINGLE` · `RESTART_SINGLE` · `CHECKPOINT_SINGLE` · `RESTART_ENUMERATION` · `CHECKPOINT_ENUMERATION` (Checkpoint-Capacity · Lookahead-Shots는 CSR이 아니라 build constant) |
| CSR         | APB slave, base`0xE2020000`, 4-byte 간격, 32 bits, 38개                                  |
| data load | AHB master SINGLE, single outstanding. SRAM`0xE0000000`~`0xE001FFFF`                      |
| Result FIFO   | 깊이 256                                                                                      |
| clock        | accelerator 100 MHz / system 50 MHz                                                                |
| 최종 구성   | **final configuration** — checkpoint 3벌 · policy Lookahead-Shots 3 · iteration 내 PE 4벌 · measurement 최적화 2단        |

### 성능 — 축을 섞지 마십시오

| 축 | 값 | 근거 |
|---|---|---|
| board wall-clock time | Restart mode 425,502 µs → **55,798 µs** (7.626×) | `hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/` |
| RTL cycle (6단계) | Restart mode 42,308,335 → **6,890,470** (6.1401×) | `hardware_bram/results/2026-09-08_publication_6stage/` |
| software 대비 | ORCA 1 core 대비 **116,426×** | `hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/` |

셋 다 같은 500 workloads(1 solution/4/16/64/256 × seed 100)입니다. BBHT trajectory는 board와 RTL 이
500/500 일치하지만 cycle 값 자체는 다르므로, 두 축을 섞어 speedup을 만들면 안 됩니다.

2026-10-11 에는 새 software baseline(`software/orca_grover_develop/`)을 200T board의 ORCA 와 server x86 core 하나에서 네 predicate
2,000개로 재어 같은 board의 FPGA 와 같은 mode끼리 맞댔습니다. ORCA 는 FPGA 보다 wall-clock time으로 15,889~19,861×
느리지만, server 한 core는 FPGA 의 1.15~1.34× 시간에 끝납니다. 위 표와는 board · workload · baseline이 달라 섞지
않습니다([실험 19](documents/reports/19_orca_server_software_baseline.md)).

---

## 3. 두 variant와 BRAM configuration들

iteration 실패 시 amplitude array를 어떻게 재활용하느냐에서 implementation이 둘로 나뉩니다.
**아직 어느 쪽도 확정이 아니고, 나중에 하나를 고릅니다.** hardware directory tree는
`hardware_bram/` 과 `hardware_dram/` 둘입니다. 2026-10-06 에 옛
`hardware_bram_checkpoint/` · `no_checkpoint_baseline/` 을 `hardware_bram/` 하나로
모으고, checkpoint · PE 구성마다 configuration directory를 나눴습니다. tag(`board-verified-build-2026-09-07` 등)
안에서는 directory 이름이 그때 이름인 `hardware_bram/` 그대로입니다.

### `hardware_bram/` — BRAM Variant 공용 source + configuration 열 개

BRAM 만 씁니다. 실패한 shot의 amplitude를 버리지 않고 checkpoint에서 차이만큼만 이어 돌리고
(Checkpoint-Capacity · Lookahead-Shots), Grover iteration 한 번 안에서는 32-lane PE 여러 개가 512 rows를 나눠 처리합니다(number of PEs).
Board-Verified Build가 이 variant입니다.

Accelerator Core는 Checkpoint-Capacity · Lookahead-Shots · number of PEs · Measurement Microarchitecture(Dual-Row Build, Two-Level Select)가 전부
compile parameter입니다. 그래서 모든 configuration이 **같은 RTL 을 parameter만 달리 compile**합니다.
Bus Interface · Accelerator Core · testbench · firmware · simulation · synthesis는 `hardware_bram/` 바로 아래에
한 벌만 두고, configuration마다 다른 것 -- parameter 기본값을 정하는 adapter 하나, RVX platform 정의,
그 configuration의 implementation report · board benchmark · bitstream -- 만 `hardware_bram/configurations/<configuration>/`
에 둡니다. configuration은 지금까지 실험한 조합 열 개입니다.

| configuration | Checkpoint-Capacity / Lookahead-Shots | number of PEs | Measurement Microarchitecture | 어디서 나왔나 | 실물 |
|---|---|---|---|---|---|
| `final` | 3/3 | 4 | Dual-Row Build · Two-Level Select | **최종 구성** (Six-Stage Ablation 마지막 단계) | board benchmark Board-Verified Build (2026-09-08), 200T bitstream (2026-10-07), 200T board 500 runs (2026-10-08) |
| `capacity3_lookahead3_pes4_dualrow_linear` | 3/3 | 4 | Dual-Row Build · Linear Select | Six-Stage Ablation 다섯째 단계 | RTL simulation · 100T implementation · 200T bitstream (2026-10-07), 200T board 500 runs (2026-10-08) |
| `capacity3_lookahead3_pes4_singlerow_linear` | 3/3 | 4 | Single-Row Build · Linear Select | Six-Stage Ablation 넷째 단계 | RTL simulation · 100T implementation · 200T bitstream (2026-10-07), 200T board 500 runs (2026-10-08) |
| `capacity4_lookahead4_pes4_singlerow_linear` | 4/4 | 4 | Single-Row Build · Linear Select | Six-Stage Ablation 셋째 단계 | RTL simulation · 100T implementation · 200T bitstream (2026-10-07), 200T board 500 runs (2026-10-08) |
| `capacity4_lookahead4_pes1_singlerow_linear` | 4/4 | 1 | Single-Row Build · Linear Select | Six-Stage Ablation 둘째 단계, Checkpoint-Capacity · Lookahead-Shots 단독 실험 대조군 | 옛 RTL board benchmark (2026-09-04), 현행 RTL RTL simulation · 100T implementation · 200T bitstream (2026-10-07), 200T board 500 runs (2026-10-08) |
| `capacity3_lookahead4_pes1_singlerow_linear` | 3/4 | 1 | Single-Row Build · Linear Select | Checkpoint-Capacity · Lookahead-Shots 단독 실험 | RTL simulation만 |
| `capacity3_lookahead3_pes1_singlerow_linear` | 3/3 | 1 | Single-Row Build · Linear Select | Checkpoint-Capacity · Lookahead-Shots 단독 실험 | RTL simulation · 100T implementation · 200T bitstream (2026-10-07), 200T board 500 runs (2026-10-08) |
| `capacity4_lookahead8_pes1_singlerow_linear` | 4/8 | 1 | Single-Row Build · Linear Select | 첫 checkpoint board benchmark | 옛 RTL board benchmark (2026-09-01) |
| `no_checkpoint_baseline` | 없음 | 4 | Single-Row Build · Linear Select | No-Checkpoint Baseline (아래) | board benchmark (2026-10-04) |
| `capacity0_pes1_singlerow_linear` | 없음 | 1 | Single-Row Build · Linear Select | Six-Stage Ablation 첫 단계와 같은 구성 | 100T implementation (2026-10-08) |
| `final_200mhz` | 3/3 | 4 | Dual-Row Build · Two-Level Select | 최종 구성을 accelerator clock 200 MHz 로 (RTL 을 따로 가짐, 아래) | RTL simulation · 200T bitstream · 200T board 네 predicate (2026-10-12) · 500 runs (2026-10-13) |

Six-Stage Ablation 과 Checkpoint-Capacity · Lookahead-Shots 단독 실험의 수치는 tag 안 standalone top 으로 잰 것이고, configuration
adapter는 그 top 들이 넘기던 parameter를 그대로 옮긴 것입니다. `capacity0_pes1_singlerow_linear` 단계는 그 campaign에서
`capacity4_lookahead4_pes1_singlerow_linear` build를 runtime Restart mode로 돌려 쟀고, checkpoint hardware를 뺀 build는 이 configuration이
처음입니다. `capacity4_lookahead8_pes1_singlerow_linear` · `capacity4_lookahead4_pes1_singlerow_linear` 의 board bitstream은 단일 PE 시절의 옛 RTL 로 만든
것이라, 현행 Accelerator Core에 이 adapter를 문 것과 byte가 같지 않습니다. 열 configuration 모두 port 계약 ·
lint · 실물 core 통신 계약 T1~T9 를 통과합니다 (`make -C hardware_bram/sim ports-configurations
lint-configurations`, `make -C hardware_bram/sim real CONFIGURATION=<configuration>`).

`final_200mhz` 는 이 규칙의 예외입니다. 200 MHz 에 맞추려고 pipeline register를 더한 Accelerator Core RTL 을
configuration directory에 따로 둡니다. BBHT trajectory는 `final` 과 같고 RTL cycle은 Restart mode +5.0 %, checkpoint +10.1 %
늘었습니다. 원격 200T board에서 네 predicate 4,000 실행이 reference model과 맞았고, 같은 board의 100 MHz revision보다 wall-clock time
시간이 Restart mode 1.869×, checkpoint 1.751× 빠릅니다([실험 20](documents/reports/20_200mhz_implementation.md)).

### `hardware_dram/` — DRAM 전량 저장 + BRAM queue

`j` 별 amplitude를 DRAM 에 모두 저장해 둡니다. random number 생성기가 뽑은 `j` 는 BRAM 의 queue에도
같이 올려 둡니다. solution 후보를 찍고 검증해서 틀렸으면 queue에서 그 `j` 의 amplitude를 지우고,
DRAM 에서 다음 `j` 의 amplitude를 가져와 queue에 올립니다. 어떤 `j` 든 burst 한 번이면
닿으므로 Checkpoint-Capacity도 Lookahead-Shots도 필요하지 않습니다.

host 통신 경로(APB CSR · AHB load)를 묶은 최상단 `src/bbht_dram_top.v` 에,
2026-09-25 부터 **DRAM burst port를 32-bit AXI4 로 바꾸는 bridge**
(`src/grover_dram_axi_bridge.v`)를 붙여 RVX platform `bbht_grover_dram` 의 DDR3
(`slow_dram`)에 잇습니다. 네 predicate × 500 workloads가 AXI memory configuration 위에서 software reference model과
2,000/2,000 맞았습니다. 실제 NoC 와 DDR model이 들어간 SoC RTL simulation에서도 console 16실행이
16/16 맞았고, 2026-10-04 에 board(DDR3 실물)에서도 2,000/2,000 맞았습니다. 같은 board에서
checkpoint 판보다 wall-clock time으로 약 15.6× 느립니다
([기술문서 21장](documents/design_references/21_dram_variant.md)).
regression은 동작 수준 DRAM configuration 위에서 합니다 (`make -C hardware_dram/sim`,
최상단은 `top` target). 같은 자극을
`hardware_bram` 의 Accelerator Core(final configuration)에도 걸어 search BBHT trajectory가 일치하는지 보는 대조는 `make -C hardware_dram/sim equiv`
입니다. 지금은 단일탐색만 되고 enumeration은 `config_error` 로 거절합니다.

### `hardware_bram/configurations/no_checkpoint_baseline/` — No-Checkpoint Baseline

PE 네 벌(4 PEs)만 켜고 checkpoint · Policy Engine · measurement 최적화 Dual-Row Build/Two-Level Select를 끈 No-Checkpoint Baseline입니다.
같은 board · 같은 SoC 에서 최적화 유무에 따른 속도를 맞대려고 만들었습니다. 다른 configuration처럼
Accelerator Core · Bus Interface · firmware는 `hardware_bram/` 공용 것을 그대로 쓰고, 이 revision의 RTL 은
parameter 기본값과 burst 처리만 다른 adapter 하나입니다.

Restart mode 2,000 실행이 software reference model과 맞습니다. `capacity3_lookahead3_pes4_singlerow_linear` configuration(checkpoint 판에서 Dual-Row Build/Two-Level Select만 끈 것)을
Restart mode로 돌린 것과는 **cycle까지** 2,000/2,000 같습니다. RTL cycle로는 final configuration이 이 revision보다
2.897× 빠릅니다. 2026-10-04 에 board에서 Restart mode 2,000 이 reference model과 맞았고, 같은 board에서
checkpoint build가 wall-clock time으로 **2.810×** 빠릅니다
([기술문서 20장](documents/design_references/20_no_checkpoint_baseline.md)).

`hardware_bram/` 과 `hardware_dram/` 은 `src` · `testbench` · `sim` · `rvx` · `firmware` 로
같은 모양을 하고, bram 쪽은 configuration마다 다른 `vivado` · `bitstream` 과 configuration 전용 `results` 가
`models/` 아래로 내려가 있습니다. software reference model과 verification vector와 비교 실험은 두 directory tree가
`software/` 에서 공유합니다.

---

## 4. directory 구조

```
documents/
  study_references/     공부용 해설서. 입구는 index.md, 1~18장 + 부록 A
    papers/             원문 논문 PDF (papers_ko/ 에 한국어 해설본), 우리 논문 목차 paper_outline.md
  design_references/    확정된 설계. 번호 장 22개, 입구는 index.md
    diagrams/           기술문서 · 실험 보고서가 참조하는 그림 (유일한 하위 directory)
  reports/              설계를 정하거나 확인한 실험. <번호>_<실험명>.md, 입구는 index.md
  check_docs.py         문서 정합성 검사기

hardware_bram/          BRAM Variant — BRAM 전용. 아래는 모든 configuration이 같이 쓰는 것
  src/                  RTL 한 벌 (Bus Interface + 최상단 + Accelerator Core). adapter는 configuration directory에.
                        board에 구운 revision은 tag board-verified-build-2026-09-07
  testbench/            testbench. verilator C++ harness 포함
  sim/                  Makefile · runner · report script. CONFIGURATION=<configuration> 로 adapter를 고름
  synth/                Vivado batch script. Accelerator Core resource synthesis
  results/              configuration 사이 비교 근거 (Six-Stage Ablation · resource 5구성 · Checkpoint-Capacity · Lookahead-Shots 단독 실험)
  rvx/                  공용 RVX 설치기 install_model.sh · user region template
  firmware/             driver · console app · benchmark app · ORCA baseline
  models/               configuration 열 개와 200 MHz revision. directory 이름은 hardware_bram_<configuration>
    final/   최종 구성 (Board-Verified Build)
      src/              adapter 하나 (구성 네 축의 기본값)
      rvx/              RVX platform bbht_grover_final 정의와 설치 script
      results/          이 구성의 simulation evidence bundle (YYYY-MM-DD_<주제>/)
      vivado/           Vivado project vivado_bbht_grover_fpga (report · board benchmark)
      bitstream/        board에 구운 bitstream 묶음
    no_checkpoint_baseline/ No-Checkpoint Baseline. src rvx sim results vivado bitstream
    final_200mhz/ 최종 구성의 200 MHz revision. src 에 adapter와 Accelerator Core RTL 10개,
                        rvx sim results vivado bitstream
    capacity4_lookahead8_pes1_singlerow_linear/      src rvx + vivado/ 에 옛 RTL board benchmark (2026-09-01)
    capacity4_lookahead4_pes1_singlerow_linear/      src rvx + vivado/ 에 옛 RTL board benchmark (2026-09-04)
    hardware_bram_{capacity0_pes1_singlerow_linear,capacity3_lookahead4_pes1_singlerow_linear,capacity3_lookahead3_pes1_singlerow_linear,capacity4_lookahead4_pes4_singlerow_linear,capacity3_lookahead3_pes4_singlerow_linear,capacity3_lookahead3_pes4_dualrow_linear}/
                        src rvx 만 (bitstream을 낸 적 없음)

hardware_dram/          DRAM Variant — DRAM 전량 저장 + BRAM queue
                        (RTL + 최상단 + AXI4 bridge + RVX 설치. 2026-10-04 board benchmark)
                        configuration directory 없이 한 벌이고, 하위 구조는 hardware_bram 에 vivado ·
                        bitstream 을 더한 모양입니다 (synth 만 없음)

spec/                   register · port 규격. RTL · firmware · host가 함께 씀
                          CSR 원본 JSON · gen_csr.py · generated/ · port_contract.tsv · check_ports.py

software/               분류 / 하위 directory / 내용물. data · 결과 directory 이름은 날짜_내용, 대표 문서는 같은 이름 .md
  reference_model_develop/       reference model (models/) · RTL testbench 자극 생성기 (tb_stimulus/) · Common500 비교 · Predicate500 expected result 생성기
  reference_model_data/          reference model이 낸 결과와 비교 결과: requested iterations vector · enumeration vector · Common500 결과 · Predicate500 expected result
  testbench_data/       testbench · 실험이 읽는 입력: Common500 dataset · seed roster, Predicate500 dataset
  pc_grover_develop/    PC 용 Grover implementation (C++ · NumPy · Qiskit). 실험 17
  pc_grover_result/       그 benchmark 결과
  orca_grover_develop/  accelerator 없는 C 세 model, ORCA 와 server x86 공용. 실험 19
  orca_grover_result/     그 benchmark 결과
  host_fpga_develop/    PC 에서 board를 부리는 도구
                          bbht_cli.py (실 UART · mock · 재생) · bbht_predicate500.py (네 predicate 자동 test)

trash_bin/              구 스펙 문서와 대용량 산출물 보관. git 추적 안 함
```

---

## 5. 빠르게 돌려 보기

```bash
# Bus Interface regression / Bus Interface + adapter + Accelerator Core / 250쌍 BBHT trajectory testbench
make -C hardware_bram/sim ports lint regress driver
make -C hardware_bram/sim real
make -C hardware_bram/sim bench250

# 네 predicate x 500 workloads: RTL testbench 세 directory tree, 그리고 board 자동 test
make -C hardware_bram/sim predicate500
make -C hardware_bram/configurations/no_checkpoint_baseline/sim predicate500 predicate500-ref equiv
make -C hardware_dram/sim predicate500
python3 software/host_fpga_develop/bbht_predicate500.py --port /dev/ttyUSB1

# software reference model Common500 비교 (가상환경에 software/reference_model_develop/common500/requirements.txt 를 설치한 뒤)
bash software/reference_model_develop/common500/run_full_benchmark.sh

# RVX platform에 설치 (위 file이 있을 때)
source /opt/rvx/rvx_setup.sh
hardware_bram/configurations/final/rvx/install_to_platform.sh

# 문서를 고쳤으면
python3 documents/check_docs.py
```

board에서는 console app(`hardware_bram/firmware/bbht_console/`)을 올리고 serial terminal로
명령을 칩니다. 순서는 기술문서 [17장](documents/design_references/17_board_operation.md)에
있습니다.

---

## 6. 더 읽을 것

| 무엇이 궁금한가            | 어디를 보는가                                                                                                     |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| 전체를 장별로 (22장) | [index.md](documents/design_references/index.md) |
| host에서 어떻게 부리는가 | [17장 board 운용](documents/design_references/17_board_operation.md) |
| CSR register 하나하나 | [13장 CSR register와 execution mode](documents/design_references/13_csr_registers_and_execution_modes.md) |
| Accelerator Core port | [12장 Accelerator Core port 계약](documents/design_references/12_accelerator_core_port_contract.md) |
| fixed-point와 memory 배치 | [6장 data 표현과 memory map](documents/design_references/06_data_representation_and_memory_map.md) |
| UART 명령 | [14장 host interface와 UART protocol](documents/design_references/14_host_interface_and_uart_protocol.md) |
| software reference model과 비교 실험 | [4장 software reference model과 test vector](documents/design_references/04_software_reference_model_and_test_vectors.md) |
| 설계를 왜 이렇게 정했나 · benchmark와 baseline 비교 | [실험 보고서 index](documents/reports/index.md) |
| Grover algorithm 자체       | [study_references/](documents/study_references/index.md) index · 1~18장                                                   |

영문 요약은 [README.md](README.md) 에 있습니다.
