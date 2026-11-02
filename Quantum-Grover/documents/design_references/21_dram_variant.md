# 21장. DRAM Variant

> [← 20장 No-Checkpoint Baseline](20_no_checkpoint_baseline.md) · [index](index.md) · [22장 부록: 용어집과 폐기된 규격 →](22_appendix_glossary_and_retired_specs.md)

---

shot이 실패한 뒤 amplitude를 어떻게 재활용하느냐에서 implementation이 갈립니다. BRAM Variant(1~19장)는 checkpoint slot
세 개와 Policy Engine으로 되돌아갈 지점을 고르고, 이 장의 DRAM Variant는 모든 number of iterations의 amplitude를 DRAM 에
저장해 고를 것 자체를 없앱니다. 두 variant 모두 board benchmark까지 마쳤고(2026-10-04), 어느 쪽을 최종으로 할지는
아직 정하지 않았습니다.

---

## 21.1 방식

number of iterations별 amplitude를 DRAM 에 전부 저장하고, PRNG가 뽑은 number of iterations는 BRAM queue에도 올립니다. solution
후보를 검증해 틀리면 queue에서 그 항목을 지우고 DRAM 에서 다음 number of iterations의 amplitude를 queue에 올립니다.

Checkpoint-Capacity도 Lookahead-Shots도 쓰지 않습니다. 어느 number of iterations의 amplitude든 burst 한 번 거리에 있어서 계획할 것이
없기 때문입니다. [11장](11_checkpoint_and_policy_engine.md)의 DP 와 memo table이 통째로 사라지는 대신 DRAM
bandwidth가 비용이 됩니다.

| 항목 | status |
|---|---|
| RTL · 32-bit AXI4 bridge · RVX 설치 | 있음 (2026-09-25) |
| bitstream | 100 MHz 로 냄. 2026-10-04 board에서 Predicate500 2,000/2,000 |
| search | single search 전용. `enum_enable=1` 은 `config_error` 로 거절 |
| 없는 것 | enumeration, buffer B 를 쓰는 enumeration round 간 prefetch |

---

## 21.2 file 구성

Accelerator Core가 다른 variant라 `hardware_dram/src/` 의 내용은 BRAM Variant와 다릅니다. Accelerator Core 초안
(`grover_*` · `lpsoc_*`)과 Bus Interface(`bbht_*`)를 한 directory에 두고, Bus Interface의 mmio · DMA Engine 은
BRAM Variant와 byte 동일합니다. 재사용 8개(`grover_param.vh` · `arithmetic` · `memories` ·
`iteration` · `measurement` · `loader` · `status` · `dram_random`)에 아래가 붙습니다.
checkpoint(`grover_checkpoint.v`)와 Policy Engine(`grover_policy.v`)은 일부러 가져오지 않았습니다.

| file | 역할 |
|---|---|
| `src/grover_dram_amp_store.v` | iteration마다 512 rows를 DRAM checkpoint slot에 store / 필요할 때 restore |
| `src/grover_dram_prep_seq.v` | buffer A 준비 sequencer. Checkpoint-Capacity · Lookahead-Shots를 대신하는 자리 |
| `src/grover_dram_shot_fsm.v` | 바깥 BBHT shot loop 제어 |
| `src/grover_dram_queue.v` | buffer A/B 두 벌과 역할별 port mux |
| `src/grover_dram_param.vh` | checkpoint slot address map. 92 bytes/row × 512 rows = 47,104 bytes/checkpoint slot |
| [`src/bbht_dram_top.v`](../../hardware_dram/src/bbht_dram_top.v) | mmio + DMA Engine + Accelerator Core를 직접 물고 DRAM burst port를 밖으로 냄 |
| [`src/grover_dram_axi_bridge.v`](../../hardware_dram/src/grover_dram_axi_bridge.v) | 그 port(한 beat = 736-bit row)를 32-bit AXI4 master로 바꿈 (21.5절) |
| [`src/bbht_dram_axi_top.v`](../../hardware_dram/src/bbht_dram_axi_top.v) | `bbht_dram_top` + bridge. RVX user region 이 무는 module (21.6절) |
| `src/bbht_rvx_wrapper.v` · `bbht_grover_core_adapter.v` | port 계약 대조용 revision. DRAM 을 안쪽에 묶어 두어 복원이 필요한 search에서 멈춤 |
| `testbench/dram_burst_model.v` | behavioral DRAM model. latency · backpressure가 전부 parameter |
| `testbench/axi4_mem_model.v` · `tb_dram_axi_sys.v` · `tb_dram_predicate500.cpp` | AXI memory model(protocol 심판 겸)과 그 위의 Predicate500 harness |
| `testbench/tb_dram_amp_store.v` · `tb_dram_prep_seq.v` · `tb_dram_core.v` · `tb_bbht_dram_top.v` | store/restore A1~A5, prep P1~P8, Accelerator Core 통합 C1~C8, 최상단 H1~H14 |
| `sim/Makefile` · `sim/equiv_report.py` | `ports lint store prep core top equiv predicate500`. 최상위가 여럿이라 file을 하나씩 나열합니다(glob 금지) |
| `rvx/bbht_grover_dram.xml` · `install_to_platform.sh` · `pnr_manually.tcl` | RVX platform 정의 · 설치 · placement and routing 순서 (21.8절) |

`make -C hardware_dram/sim equiv` 가 같은 stimulus를 BRAM Variant에도 걸어 BBHT trajectory가 일치하는지
대조합니다. 대조 상대는 2026-09-09 부터 final configuration입니다(그전에는 a Checkpoint-Capacity of 4와 4-shot Lookahead의 configuration).

---

## 21.3 전체 모양

```
ORCA --NoC--> APB   i_grover_csr  ---+
ORCA <-NoC--  AHB   i_grover_dma  ---+-- bbht_dram_axi_top (clk_accel 100 MHz)
                                     |     bbht_dram_top      Bus Interface + DRAM Variant Accelerator Core
                                     |     grover_dram_axi_bridge   736b row <-> 32b data word
DDR3L <-MIG-- NoC <-- AXI4 i_grover_dram --+
```

| RVX interface | library | 역할 | BRAM Variant와 |
|---|---|---|---|
| `i_grover_csr` | `user_slaveif_apb_clkout` | CSR 38개, base `0xE2020000` | 같음 |
| `i_grover_dma` | `user_masterif_ahb_clkout` | dataset load (SRAM → accelerator) | 같음 |
| `i_grover_dram` | `user_masterif_axi4_clkout` | amplitude table 쓰기·읽기 (accelerator ↔ DDR3) | **새로 더함** |

CSR · firmware · host program은 BRAM Variant와 같은 것을 씁니다. console은 `ID` 응답의
`platform=bbht_grover_dram` 으로 자기가 어느 variant인지 알리고, host 자동 test
([18장](18_predicate500_automated_test.md))가 그걸 보고 Restart mode만 돌립니다. 이 variant는
checkpoint가 없어 `burst_enable` 을 무시합니다.

---

## 21.4 왜 32-bit AXI4 인가

RVX 가 Arty A7-100T 에 주는 DRAM 은 `slow_dram` 하나입니다. MIG DDR3 controller
(`xilinx_ddr3_ctrl_axi32`)를 **32-bit AXI** 로 NoC 에 붙이고, NoC address `0x0` 에 1 GiB address window를
엽니다. `fast_dram` 은 이 board용 설정이 RVX 에 없습니다
(`rvx_install/mini_git/imp_class_info/arty-100t/include/`).

그래서 accelerator 쪽 port도 32-bit AXI4 master로 맞췄습니다. 한 row가 736 bits라 row 하나가
23 data words가 되고, 이것이 이 variant의 가장 큰 비용입니다(21.7절).

platform 정의 [`hardware_dram/rvx/bbht_grover_dram.xml`](../../hardware_dram/rvx/bbht_grover_dram.xml)
은 BRAM Variant의 것에 두 가지를 더했습니다.

- `include_slow_dram = True` — DDR3 를 넣습니다
- `use_large_ram_manually = True` — DRAM 을 넣으면 RVX linker가 code와 data를 DRAM 에
  둡니다. 그러면 console의 dataset buffer가 DRAM 에 잡혀 SRAM 만 받는 DMA Engine이
  `range_error` 로 거절하고, amplitude table과 address가 겹칠 수도 있습니다. 이 키로 DRAM 은
  "손으로만 쓰는" 영역이 되고 linker는 SRAM 만 씁니다. DRAM 은 amplitude table 전용입니다

---

## 21.5 bridge `grover_dram_axi_bridge.v`

Accelerator Core의 추상 port(`dram_wr_*` / `dram_rd_*`, 한 beat = 한 row 736 bits)를 AXI4 로 바꿉니다.
Accelerator Core 쪽 계약은 `grover_dram_amp_store.v` 그대로라 Accelerator Core를 고치지 않았습니다.

### 21.5.1 address — address map을 한 글자도 안 바꿈

| 단위 | 값 |
|---|---|
| 한 row | 736-bit = 23 data words = 92-byte (`GD_ROW_BYTES`) |
| 한 checkpoint slot (number of iterations 하나) | 512 rows = 11,776 data words = 47,104-byte (`GD_ITER_STRIDE`) |
| 한 checkpoint slot의 시작 | `GD_AMP_BASE + number of iterations × 47,104` |

736 이 32 의 multiple이라 row가 data word 경계에서 딱 끊깁니다. data word 하나의 address는
`checkpoint slot 시작 + (row index × 23 + row 안 data word index) × 4` 이고, data word 0 이 row의 `[31:0]` 입니다.
number of iterations는 최대 127(sampling range 상한 = √16,384 = 128)이라 amplitude table 전체가 6 MB 이고, board DDR3 256 MB 에
여유 있게 들어갑니다.

### 21.5.2 burst — 16 beat

- INCR, 4 bytes(`awsize = 2`), **최대 16 beat**(`MAX_BEATS`, 64 B). 4 KiB 경계는 넘지 않게
  자릅니다(AXI 규칙).
- 47,104 = 736 × 64 라 한 checkpoint slot은 정확히 16-beat burst 736개입니다.
- ID 는 0 하나. 같은 ID 의 R 은 순서대로 오므로 재정렬이 없습니다.

**왜 AXI4 최대인 256 beat 가 아닌가.** 처음에는 256 beat 로 짰고 AXI model 위 verilator
2,000 실행이 전부 맞았습니다. 그런데 실제 RVX SoC(micro NoC 4.5 + DDR model) RTL simulation에서
첫 search가 끝나지 않고 console이 `ERR TIMEOUT status=0x801`(BUSY · FIFO 빔)을 냈습니다.
Questa 에서 bridge와 DDR 쪽 AXI handshake를 세어 보니 이랬습니다.

| 관측점 | 256-beat revision | 16-beat revision (최종) |
|---|---|---|
| bridge가 낸 AW | 46 (awlen 255) | 8,096 (awlen 15) |
| bridge가 받은 B | **736** | 8,096 |
| DDR 쪽 AW 의 awlen | 전부 15 | 전부 15 |
| bridge가 기다리는 B 수 `b_pending` | 64,846 (= −690, underflow) | 0 |
| 첫 search | AR 을 한 번도 못 냄 | 끝남 |

NoC 가 256 beat 쓰기를 DDR 쪽에서 16 beat 조각으로 쪼개고, **조각마다 B 응답을 master에게
돌려줍니다.** AXI 규칙은 AW 하나에 B 하나라서 bridge는 AW 수만큼 B 를 기다리다가 대기 수가
음수로 넘어갔고, "쓰기가 다 닿은 뒤에만 읽는다"(21.5.4)는 조건이 영영 서지 않았습니다.
16 beat 이하로 보내면 NoC 가 쪼개지 않으므로 AW 와 B 가 1:1 로 돌아옵니다. 읽기의 `rlast`
도 AR 하나에 하나입니다.

AXI model(`axi4_mem_model`)은 규칙대로 B 를 하나만 주므로 이 차이를 볼 수 없습니다. 그래서
model이 **16 beat 넘는 burst를 오류로 세게** 했습니다(`MAX_BEATS`). verilator 에서도 같은
제약이 지켜집니다.

### 21.5.3 쓰기 (store)

- AW 는 W 보다 최대 네 burst(`AW_AHEAD`) 앞서 냅니다. W 는 **자기 AW 가 이미 수락된
  burst만** 보냅니다. AW 전에 W 를 보내는 것도 AXI 에서 합법이지만 interconnect에 따라
  막힐 수 있어 피했습니다.
- AW 가 수락될 때 그 `awlen` 을 깊이 4의 queue(`lenq`)에 넣고, W 는 queue 머리와 beat counter를
  맞대 `wlast` 를 냅니다. queue가 비어 있지 않다는 것이 곧 "AW 가 이미 수락됐다" 는 조건입니다.
  W 쪽에서 burst 길이를 다시 계산하지 않으므로 긴 combinational path도, burst 사이 빈 cycle도
  없습니다(21.8.1).
- row 하나를 받아 shift register로 23 data words를 풀어 보내는 동안 `dram_wr_ready` 를 내립니다.
  row마다 한 cycle이 비지만(23/24), `wready` 에서 Accelerator Core의 amplitude memory 읽기까지 이어지는
  combinational path가 생기지 않습니다.
- Accelerator Core는 마지막 row를 넘기는 순간 저장이 끝났다고 보는데, bridge는 그 row의 data word를
  아직 보내는 중일 수 있습니다. 그 사이 다음 저장 request pulse가 오면 latch(`w_req_q`)에
  붙들어 두었다가 앞 session이 끝나는 대로 시작합니다.

### 21.5.4 읽기 (restore)

- AR 을 최대 네 개(`RD_OUTSTANDING`) 띄워 NoC 왕복 latency를 가립니다. burst가 16 beat 로
  짧아져 둘로는 R 사이가 비었습니다. 넷이면 cycle이 256-beat revision과 한 cycle도 다르지
  않습니다(21.7절 evidence bundle).
- R 23 data words를 모아 한 row가 되면 `dram_rd_valid` 를 올립니다. Accelerator Core가 받지 않으면
  row를 붙들고 `rready` 를 내립니다.
- **쓰기 직후 같은 checkpoint slot 읽기.** AXI 는 channel 사이 순서를 보장하지 않습니다. 그래서 앞선
  쓰기의 B 응답이 전부 돌아오고(`b_pending == 0`) 쓰기 session이 끝나기 전에는 AR 을 내지
  않습니다. 읽기 request pulse는 latch하므로 잃지 않습니다.

### 21.5.5 오류

`bresp` / `rresp` 가 OKAY 가 아니면 `axi_error` 를 세웁니다(reset까지 유지). CSR 은 두
variant 공통 source of truth라 새 bit를 만들지 않았고, 최상단의 관측 출력(`dram_axi_error`)으로만
냅니다.

---

## 21.6 최상단과 user region

[`bbht_dram_axi_top.v`](../../hardware_dram/src/bbht_dram_axi_top.v) 는 `bbht_dram_top` 에 bridge를
물린 한 겹입니다. port가 RVX interface 셋과 한 줄씩 대응하고, user region
([`bbht_grover_user_region.vh`](../../hardware_dram/src/bbht_grover_user_region.vh))은 이 module 하나만
뭅니다. simulation harness도 같은 module에 AXI memory model을 붙이므로 **board에 들어가는 RTL 과
simulation으로 검증한 RTL 이 같습니다.**

- 세 interface가 모두 `*_clkout` 이라 clock은 user가 넣습니다. 셋 다 `gclk_accel`
  (BRAM Variant와 같은 이유 — 생성 RTL 에서 `clk_accel` 의 순수 별칭)
- NoC 쪽 clock domain 건너기는 RVX 가 만들어 줍니다
- user region 머리말은 RVX `make syn` 이 뽑은 빈 template와 같습니다

설치는 [`hardware_dram/rvx/install_to_platform.sh`](../../hardware_dram/rvx/install_to_platform.sh)
입니다. RTL 17개(DRAM Accelerator Core 12 + Bus Interface mmio · DMA Engine 2 + `bbht_dram_top` + bridge + 최상단)를 file 이름으로 하나씩
옮깁니다. `src/` 에 최상위 후보가 셋(`bbht_dram_top` · `bbht_dram_axi_top` · 계약 대조용 revision
`bbht_rvx_wrapper`)이라 glob 을 쓰지 않습니다. firmware(driver와 `bbht_console`)는
`hardware_bram/firmware/` 의 것을 그대로 옮깁니다.

---

## 21.7 verification

| 단계 | 결과 | 근거 |
|---|---|---|
| regression (`make -C hardware_dram/sim`) | 추상 port 위 store · prep · core · top 전부 통과 | — |
| Predicate500 + AXI model | 네 predicate × 500 workloads가 software reference model과 여섯 축 2,000/2,000. AXI model 기본 latency와 backpressure 두 벌 모두. protocol 위반 0, 한 번도 안 쓴 data word 읽기 0 | [`hardware_dram/results/2026-09-25_predicate500_axi/`](../../hardware_dram/results/2026-09-25_predicate500_axi/evidence.md) |
| SoC RTL simulation (실제 CPU · NoC · DDR model) | console script 16실행(네 predicate × 64 · 256 solutions × 2 seeds)이 software reference model과 16/16, board가 만든 dataset hash 8/8. BBHT trajectory는 verilator 와 같고 cycle은 NoC·DDR model latency 때문에 약 1.4× | [`hardware_dram/results/2026-09-25_soc_rtl_predicate500/`](../../hardware_dram/results/2026-09-25_soc_rtl_predicate500/evidence.md) |
| board (2026-10-04, DDR3 실물) | 네 predicate × 500 이 software reference model과 2,000/2,000. cycle은 SoC RTL simulation과 0.16% 안, AXI model의 1.439×. 같은 workload를 다시 돌리면 cycle이 최대 0.033% 흔들림 | [`hardware_dram/vivado/.../2026-10-04_board_predicate500/`](../../hardware_dram/vivado/vivado_bbht_grover_dram/2026-10-04_board_predicate500/evidence.md) |

AXI memory model([`testbench/axi4_mem_model.v`](../../hardware_dram/testbench/axi4_mem_model.v))은
심판 역할도 합니다. 크기 · INCR · 4 KiB 경계 · 16 beat 상한 · address 범위 · `wlast` 위치를 매 burst
검사하고, 한 번도 쓰지 않은 data word를 읽으면 오류로 셉니다(쓰기-읽기 순서가 깨지면 여기서
잡힙니다). `AXI_STALL=1` 이면 `awready` · `wready` · `arready` · `rvalid` 에 LFSR 로 불규칙한
빈틈을 넣습니다.

**DRAM 표는 seed가 바뀌어도 남습니다.** dataset load나 predicate 변경 때만 버려집니다. 그래서
board·RTL 의 executed iterations는 search마다 표를 비우는 reference model 열(`actual_iter_dram_all_j`)이 아니라
같은 순서로 표를 이어 쓰는 열(`actual_iter_dram_session`)과 맞아야 합니다.

### 21.7.1 cycle — 32-bit AXI 의 값

한 checkpoint slot을 옮기는 데 최소 11,776 cycles이 듭니다. 같은 workload에서 추상 port(한 cycle
한 row) model보다 약 6.4×, BRAM Variant의 Checkpoint mode보다 약 11× 느립니다(숫자는 위 evidence bundle).
board에서는 NoC 와 MIG 를 거쳐 AXI model의 1.439×가 되었고, 같은 board에서 wall-clock time으로
final configuration Checkpoint mode의 15.65×, No-Checkpoint Baseline의 5.57×입니다(2026-10-04). **이 variant가 BRAM Variant의 final configuration을 이기려면
DRAM 쪽 폭부터 넓혀야 합니다** — 이 board에서는 RVX 가 주는 DRAM 이 32-bit 하나라서,
넓히려면 MIG 를 직접 붙이는(RVX `slow_dram` 을 쓰지 않는) 길을 따로 가야 합니다.

---

## 21.8 synthesis와 implementation

```bash
source /opt/rvx/rvx_setup.sh
hardware_dram/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_dram
make syn                                   # platform 생성 (처음 한 번)
cd imp_arty-100t_<날짜> && make reimp        # synthesis · implementation · bitstream (10분쯤)
make bbht_console                          # board용 console hex
```

결과는 **100 MHz timing closure, setup WNS +0.005 ns · hold WHS +0.021 ns** 입니다
([implementation 묶음](../../hardware_dram/vivado/vivado_bbht_grover_dram/2026-09-25_dram_axi_build/evidence.md),
[굽는 묶음](../../hardware_dram/bitstream/2026-09-25_dram_axi/evidence.md)). 최악 경로는 150 MHz
로 도는 RVX NoC 안이고, accelerator clock(100 MHz)은 +0.431 ns 남습니다. 같은 날 세 번 구현했습니다.

| 차수 | bridge | placement · routing | WNS | 결과 |
|---|---|---|---:|---|
| 1 | 256 beat, W 쪽에서 burst 길이를 곧바로 계산 | RVX 기본 | −2.097 | timing 실패 (6.1 · 6.2) |
| 2 | 256 beat, W 쪽 길이 계산을 한 cycle 늦춤 | `pnr_manually.tcl` | +0.068 | timing은 맞았지만 SoC simulation에서 멈춤 (21.5.2) |
| 3 | 16 beat, AW/AR 넷까지, W 는 awlen queue | `pnr_manually.tcl` | **+0.005** | 최종 |

### 21.8.1 bridge의 burst 길이 계산 (우리 RTL)

첫 implementation에서 accelerator clock 쪽 최악 경로 10개가 전부 bridge의 `w_left` 였습니다(−2.097 ns).
쓰기 session을 시작하는 cycle에 request latch 선택 → `(len+1) × 23` multiplication → 4 KiB 경계까지 남은
data word와 비교 → `w_left` 가 한꺼번에 걸렸습니다. `wlast` 직후 다음 burst 길이를 구하는
자리도 addition 두 번과 비교가 이어졌습니다.

2차에서는 두 자리를 한 cycle 늦춰 이미 register에 든 값으로 계산했습니다. timing은
풀렸지만 그 cycle에 `wvalid` 를 내려야 해서 burst마다 1 cycle이 비었고, 16 beat 로 바꾸면
checkpoint slot당 736 cycles(쓰기 throughput 약 6%)가 됩니다. 그래서 3차에서는 W 쪽 계산을 아예 없앴습니다.
AW 쪽은 원래 register 값으로 길이를 계산하므로, AW 가 수락될 때 그 `awlen` 을 queue에 넣고 W 는
queue 머리를 beat counter와 맞대기만 합니다(21.5.3). accelerator clock의 WNS 는 +0.431 ns 가 됐고 빈
cycle도 없습니다.

### 21.8.2 NoC 가 150 MHz 로 돈다 (RVX)

나머지 79곳(−0.659 ns)은 RVX 가 만든 NoC 안, system SRAM interface의 13단 경로였습니다.
RVX 는 DRAM 을 넣으면 생성 RTL 에서 `assign clk_noc = clk_dram_if;` 로 NoC 를 MIG 의
ui_clk 에 옮깁니다. 이 board의 MIG 설정(`mig_b.prj`, PHY 2:1)에서 그 clock이 150 MHz 이고,
BRAM Variant의 platform(NoC 50 MHz)에는 없던 제약입니다.

RVX code를 고치지 않고 푸는 자리가 있습니다. implementation script(`__implement.tcl`)는
`${PLATFORM_DIR}/user/fpga/${FPGA_NAME}/pnr_manually.tcl` 이 있으면 기본
`opt_design; place_design; route_design` 대신 그것을 씁니다. 저장소의
[`hardware_dram/rvx/pnr_manually.tcl`](../../hardware_dram/rvx/pnr_manually.tcl) 을 설치
script가 그 자리에 둡니다.

| 단계 | directive | setup WNS |
|---|---|---:|
| logic 최적화 | `opt_design -directive Explore` | −3.043 |
| placement | `place_design -directive ExtraTimingOpt` | −0.573 |
| placement 뒤 최적화 | `phys_opt_design -directive AggressiveExplore` | +0.001 |
| routing | `route_design -directive Explore` | **+0.005** |
| routing 뒤 최적화 (음수일 때만) | `phys_opt_design -directive AggressiveExplore` | 건너뜀 |

(3차 build의 값입니다. 2차는 routing 뒤 −0.083 에서 이 단계로 +0.068 까지 올라갔습니다.)

여유가 얇습니다. RTL 을 바꿔 다시 구현하면 이 표부터 다시 보십시오. 더 여유를 원하면
MIG 를 PHY 4:1(ui_clk 약 83 MHz)로 바꾸는 길이 있습니다. RVX 에 그 설정(`mig_a.prj`)이 같이
들어 있지만 입력 clock이 166.666 MHz 라 RVX 가 주는 150 MHz 와 맞지 않고, RVX 설치본의 board
정의까지 고쳐야 해서 이번에는 하지 않았습니다.

### 21.8.3 resource

| 항목 | 전체 | accelerator (`bbht_dram_axi_top`) | 그중 bridge |
|---|---:|---:|---:|
| LUT | 27,379 | 10,094 | 292 |
| FF | 34,162 | 10,531 | 1,744 |
| BRAM (RAMB36 / RAMB18) | 81 BRAM tiles | 1 / 96 | 0 |
| DSP | 74 | 70 | 4 |

---

## 21.9 한계와 남은 일

- **enumeration(`enum_enable=1`)는 여전히 `config_error` 입니다.** single search만 됩니다.
- buffer B 를 쓰는 enumeration round 간 prefetch는 없습니다.
- RTL simulation의 DDR model은 2 MiB(`SIM_LARGE_RAM_SIZE`)로 고정이고 spec 으로 못 바꿉니다.
  number of iterations가 43 을 넘는 checkpoint slot이 필요한 search는 SoC simulation에서 돌리지 마십시오. SoC simulation script
  (`script_predicate500_dram.h`)가 64 · 256 solutions만 쓰는 이유입니다.
- board에서는 Predicate500 만 돌렸습니다(2026-10-04). cycle이 실행마다 조금씩 흔들리므로 cycle을 인용할 때는 그 폭을 같이 적습니다.
