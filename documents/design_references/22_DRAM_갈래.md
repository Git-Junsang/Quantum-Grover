# 22장. DRAM 갈래

> [← 21장 체크포인트 없는 BRAM 판](21_체크포인트_없는_BRAM_판.md) · [문서 지도](00_문서_지도.md) · [23장 설계 근거 실험 →](23_설계_근거_실험.md)

---

반복 실패 뒤 진폭을 어떻게 재활용하느냐에서 구현이 갈립니다. 체크포인트 판(1~20장)은 슬롯
세 개와 정책 엔진으로 되돌아갈 지점을 고르고, 이 장의 DRAM 갈래는 모든 `j` 의 진폭을 DRAM 에
저장해 고를 것 자체를 없앱니다. 두 갈래 모두 보드 실측까지 마쳤고(2026-10-04), 어느 쪽을 최종으로 할지는
아직 정하지 않았습니다.

---

## 22.1 방식

`j` 별 진폭을 DRAM 에 전부 저장하고, 난수 생성기가 뽑은 `j` 는 BRAM 큐에도 올립니다. 정답
후보를 검증해 틀리면 큐에서 그 `j` 를 지우고 DRAM 에서 다음 `j` 의 진폭을 큐에 올립니다.

체크포인트 K 도 정책 H 도 쓰지 않습니다. 모든 `j` 가 버스트 한 번 거리에 있어서 계획할 것이
없기 때문입니다. [11장](11_체크포인트와_정책_엔진.md)의 DP 와 memo 가 통째로 사라지는 대신 DRAM
대역폭이 비용이 됩니다.

| 항목 | 상태 |
|---|---|
| RTL · 32비트 AXI4 브리지 · RVX 설치 | 있음 (2026-09-25) |
| 비트스트림 | 100 MHz 로 냄. 2026-10-04 보드에서 Predicate500 2,000/2,000 |
| 탐색 | 단일 탐색 전용. `enum_enable=1` 은 `config_error` 로 거절 |
| 없는 것 | 열거, 버퍼 B 를 쓰는 라운드 간 프리페치 |

---

## 22.2 파일 구성

Main IP 가 다른 갈래라 `hardware_dram/src/` 의 내용은 체크포인트 판과 다릅니다. Main IP 초안
(`grover_*` · `lpsoc_*`)과 통신 계층(`bbht_*`)을 한 폴더에 두고, 통신 계층의 mmio · loader 는
체크포인트 판과 바이트 동일합니다. 재사용 8개(`grover_param.vh` · `arithmetic` · `memories` ·
`iteration` · `measurement` · `loader` · `status` · `dram_random`)에 아래가 붙습니다.
체크포인트(`grover_checkpoint.v`)와 정책 엔진(`grover_policy.v`)은 일부러 가져오지 않았습니다.

| 파일 | 역할 |
|---|---|
| `src/grover_dram_amp_store.v` | 반복마다 512행을 DRAM 슬롯에 store / 필요할 때 restore |
| `src/grover_dram_prep_seq.v` | 버퍼 A 준비 시퀀서. 체크포인트 K/H 를 대신하는 자리 |
| `src/grover_dram_shot_fsm.v` | 바깥 BBHT 라운드 제어 |
| `src/grover_dram_queue.v` | 버퍼 A/B 두 벌과 역할별 포트 멀티플렉서 |
| `src/grover_dram_param.vh` | 슬롯 주소맵. 92바이트/행 × 512행 = 47,104바이트/슬롯 |
| [`src/bbht_dram_top.v`](../../hardware_dram/src/bbht_dram_top.v) | mmio + AHB 적재기 + Main IP 를 직접 물고 DRAM burst 포트를 밖으로 냄 |
| [`src/grover_dram_axi_bridge.v`](../../hardware_dram/src/grover_dram_axi_bridge.v) | 그 포트(한 beat = 736비트 행)를 32비트 AXI4 마스터로 바꿈 (22.5절) |
| [`src/bbht_dram_axi_top.v`](../../hardware_dram/src/bbht_dram_axi_top.v) | `bbht_dram_top` + 브리지. RVX user region 이 무는 모듈 (22.6절) |
| `src/bbht_rvx_wrapper.v` · `bbht_grover_core_adapter.v` | 포트 계약 대조용 판. DRAM 을 안쪽에 묶어 두어 복원이 필요한 탐색에서 멈춤 |
| `testbench/dram_burst_model.v` | 동작 수준 DRAM 모델. 지연 · 백프레셔가 전부 파라미터 |
| `testbench/axi4_mem_model.v` · `tb_dram_axi_sys.v` · `tb_dram_predicate500.cpp` | AXI 메모리 모델(프로토콜 심판 겸)과 그 위의 Predicate500 하네스 |
| `testbench/tb_dram_amp_store.v` · `tb_dram_prep_seq.v` · `tb_dram_core.v` · `tb_bbht_dram_top.v` | store/restore A1~A5, prep P1~P8, Main IP 통합 C1~C8, 최상단 H1~H14 |
| `sim/Makefile` · `sim/equiv_report.py` | `ports lint store prep core top equiv predicate500`. 최상위가 여럿이라 파일을 하나씩 나열합니다(glob 금지) |
| `rvx/bbht_grover_dram.xml` · `install_to_platform.sh` · `pnr_manually.tcl` | RVX 플랫폼 정의 · 설치 · 배치배선 순서 (22.8절) |

`make -C hardware_dram/sim equiv` 가 같은 자극을 체크포인트 판에도 걸어 탐색 궤적이 일치하는지
대조합니다. 대조 상대는 2026-09-09 부터 K3/H3-E4-M2 입니다(그전에는 K4/H4).

---

## 22.3 전체 모양

```
ORCA --NoC--> APB   i_grover_csr  ---+
ORCA <-NoC--  AHB   i_grover_dma  ---+-- bbht_dram_axi_top (clk_accel 100 MHz)
                                     |     bbht_dram_top      통신 계층 + DRAM Main IP
                                     |     grover_dram_axi_bridge   736b 행 <-> 32b 워드
DDR3L <-MIG-- NoC <-- AXI4 i_grover_dram --+
```

| RVX 인터페이스 | 라이브러리 | 역할 | bram 갈래와 |
|---|---|---|---|
| `i_grover_csr` | `user_slaveif_apb_clkout` | CSR 38개, base `0xE2020000` | 같음 |
| `i_grover_dma` | `user_masterif_ahb_clkout` | 데이터셋 적재 (SRAM → 가속기) | 같음 |
| `i_grover_dram` | `user_masterif_axi4_clkout` | 진폭표 쓰기·읽기 (가속기 ↔ DDR3) | **새로 더함** |

CSR · 펌웨어 · 호스트 프로그램은 bram 갈래와 같은 것을 씁니다. 콘솔은 `ID` 응답의
`platform=bbht_grover_dram` 으로 자기가 어느 갈래인지 알리고, 호스트 자동 테스트
([19장](19_Predicate500_자동_테스트.md))가 그걸 보고 NORMAL 만 돌립니다. 이 갈래는
체크포인트가 없어 `burst_enable` 을 무시합니다.

---

## 22.4 왜 32비트 AXI4 인가

RVX 가 Arty A7-100T 에 주는 DRAM 은 `slow_dram` 하나입니다. MIG DDR3 컨트롤러
(`xilinx_ddr3_ctrl_axi32`)를 **32비트 AXI** 로 NoC 에 붙이고, NoC 주소 `0x0` 에 1 GiB 창을
엽니다. `fast_dram` 은 이 보드용 설정이 RVX 에 없습니다
(`rvx_install/mini_git/imp_class_info/arty-100t/include/`).

그래서 가속기 쪽 포트도 32비트 AXI4 마스터로 맞췄습니다. 한 행이 736비트라 행 하나가
워드 23개가 되고, 이것이 이 갈래의 가장 큰 비용입니다(22.7절).

플랫폼 정의 [`hardware_dram/rvx/bbht_grover_dram.xml`](../../hardware_dram/rvx/bbht_grover_dram.xml)
은 bram 의 것에 두 가지를 더했습니다.

- `include_slow_dram = True` — DDR3 를 넣습니다
- `use_large_ram_manually = True` — DRAM 을 넣으면 RVX 링커가 코드와 데이터를 DRAM 에
  둡니다. 그러면 콘솔의 데이터셋 버퍼가 DRAM 에 잡혀 SRAM 만 받는 AHB 적재기가
  `range_error` 로 거절하고, 진폭표와 주소가 겹칠 수도 있습니다. 이 키로 DRAM 은
  "손으로만 쓰는" 영역이 되고 링커는 SRAM 만 씁니다. DRAM 은 진폭표 전용입니다

---

## 22.5 브리지 `grover_dram_axi_bridge.v`

Main IP 의 추상 포트(`dram_wr_*` / `dram_rd_*`, 한 beat = 한 행 736비트)를 AXI4 로 바꿉니다.
Main IP 쪽 계약은 `grover_dram_amp_store.v` 그대로라 Main IP 를 고치지 않았습니다.

### 22.5.1 주소 — 주소 맵을 한 글자도 안 바꿈

| 단위 | 값 |
|---|---|
| 한 행 | 736비트 = 워드 23개 = 92바이트 (`GD_ROW_BYTES`) |
| 한 슬롯 (`j` 하나) | 512행 = 11,776 워드 = 47,104바이트 (`GD_ITER_STRIDE`) |
| 슬롯 `j` 의 시작 | `GD_AMP_BASE + j × 47,104` |

736 이 32 의 배수라 행이 워드 경계에서 딱 끊깁니다. 행 `k` 의 워드 `w` 는
`슬롯 시작 + (k × 23 + w) × 4` 이고, 워드 0 이 행의 `[31:0]` 입니다.
`j` 는 최대 127(`m` 상한 √N = 128)이라 진폭표 전체가 6 MB 이고, 보드 DDR3 256 MB 에
여유 있게 들어갑니다.

### 22.5.2 버스트 — 16 beat

- INCR, 4바이트(`awsize = 2`), **최대 16 beat**(`MAX_BEATS`, 64 B). 4 KiB 경계는 넘지 않게
  자릅니다(AXI 규칙).
- 47,104 = 736 × 64 라 한 슬롯은 정확히 16 beat 버스트 736개입니다.
- ID 는 0 하나. 같은 ID 의 R 은 순서대로 오므로 재정렬이 없습니다.

**왜 AXI4 최대인 256 beat 가 아닌가.** 처음에는 256 beat 로 짰고 AXI 모델 위 verilator
2,000 실행이 전부 맞았습니다. 그런데 실제 RVX SoC(micro NoC 4.5 + DDR 모델) RTL 시뮬에서
첫 탐색이 끝나지 않고 콘솔이 `ERR TIMEOUT status=0x801`(BUSY · FIFO 빔)을 냈습니다.
Questa 에서 브리지와 DDR 쪽 AXI 핸드셰이크를 세어 보니 이랬습니다.

| 관측점 | 256 beat 판 | 16 beat 판 (최종) |
|---|---|---|
| 브리지가 낸 AW | 46 (awlen 255) | 8,096 (awlen 15) |
| 브리지가 받은 B | **736** | 8,096 |
| DDR 쪽 AW 의 awlen | 전부 15 | 전부 15 |
| 브리지의 대기 B 수 `b_pending` | 64,846 (= −690, 언더플로) | 0 |
| 첫 탐색 | AR 을 한 번도 못 냄 | 끝남 |

NoC 가 256 beat 쓰기를 DDR 쪽에서 16 beat 조각으로 쪼개고, **조각마다 B 응답을 마스터에게
돌려줍니다.** AXI 규칙은 AW 하나에 B 하나라서 브리지는 AW 수만큼 B 를 기다리다가 대기 수가
음수로 넘어갔고, "쓰기가 다 닿은 뒤에만 읽는다"(22.5.4)는 조건이 영영 서지 않았습니다.
16 beat 이하로 보내면 NoC 가 쪼개지 않으므로 AW 와 B 가 1:1 로 돌아옵니다. 읽기의 `rlast`
도 AR 하나에 하나입니다.

AXI 모델(`axi4_mem_model`)은 규칙대로 B 를 하나만 주므로 이 차이를 볼 수 없습니다. 그래서
모델이 **16 beat 넘는 버스트를 오류로 세게** 했습니다(`MAX_BEATS`). verilator 에서도 같은
제약이 지켜집니다.

### 22.5.3 쓰기 (store)

- AW 는 W 보다 최대 네 버스트(`AW_AHEAD`) 앞서 냅니다. W 는 **자기 AW 가 이미 수락된
  버스트만** 보냅니다. AW 전에 W 를 보내는 것도 AXI 에서 합법이지만 인터커넥트에 따라
  막힐 수 있어 피했습니다.
- AW 가 수락될 때 그 `awlen` 을 깊이 4 큐(`lenq`)에 넣고, W 는 큐 머리와 beat 카운터를
  맞대 `wlast` 를 냅니다. 큐가 비어 있지 않다는 것이 곧 "AW 가 이미 수락됐다" 는 조건입니다.
  W 쪽에서 버스트 길이를 다시 계산하지 않으므로 긴 조합 경로도, 버스트 사이 빈 사이클도
  없습니다(22.8.1).
- 행 하나를 받아 시프트 레지스터로 23워드를 풀어 보내는 동안 `dram_wr_ready` 를 내립니다.
  행마다 한 사이클이 비지만(23/24), `wready` 에서 Main IP 의 진폭 메모리 읽기까지 이어지는
  조합 경로가 생기지 않습니다.
- Main IP 는 마지막 행을 넘기는 순간 저장이 끝났다고 보는데, 브리지는 그 행의 워드를
  아직 보내는 중일 수 있습니다. 그 사이 다음 저장 요청 펄스가 오면 래치(`w_req_q`)에
  붙들어 두었다가 앞 세션이 끝나는 대로 시작합니다.

### 22.5.4 읽기 (restore)

- AR 을 최대 네 개(`RD_OUTSTANDING`) 띄워 NoC 왕복 지연을 가립니다. 버스트가 16 beat 로
  짧아져 둘로는 R 사이가 비었습니다. 넷이면 사이클이 256 beat 판과 한 사이클도 다르지
  않습니다(22.7절 근거 묶음).
- R 워드 23개를 모아 한 행이 되면 `dram_rd_valid` 를 올립니다. Main IP 가 받지 않으면
  행을 붙들고 `rready` 를 내립니다.
- **쓰기 직후 같은 슬롯 읽기.** AXI 는 채널 사이 순서를 보장하지 않습니다. 그래서 앞선
  쓰기의 B 응답이 전부 돌아오고(`b_pending == 0`) 쓰기 세션이 끝나기 전에는 AR 을 내지
  않습니다. 읽기 요청 펄스는 래치하므로 잃지 않습니다.

### 22.5.5 오류

`bresp` / `rresp` 가 OKAY 가 아니면 `axi_error` 를 세웁니다(리셋까지 유지). CSR 은 두
갈래 공통 정본이라 새 비트를 만들지 않았고, 최상단의 관측 출력(`dram_axi_error`)으로만
냅니다.

---

## 22.6 최상단과 user region

[`bbht_dram_axi_top.v`](../../hardware_dram/src/bbht_dram_axi_top.v) 는 `bbht_dram_top` 에 브리지를
물린 한 겹입니다. 포트가 RVX 인터페이스 셋과 한 줄씩 대응하고, user region
([`bbht_grover_user_region.vh`](../../hardware_dram/src/bbht_grover_user_region.vh))은 이 모듈 하나만
뭅니다. 시뮬 하네스도 같은 모듈에 AXI 메모리 모델을 붙이므로 **보드에 들어가는 RTL 과
시뮬로 검증한 RTL 이 같습니다.**

- 세 인터페이스가 모두 `*_clkout` 이라 클럭은 유저가 넣습니다. 셋 다 `gclk_accel`
  (bram 갈래와 같은 이유 — 생성 RTL 에서 `clk_accel` 의 순수 별칭)
- NoC 쪽 클럭 도메인 건너기는 RVX 가 만들어 줍니다
- user region 머리말은 RVX `make syn` 이 뽑은 빈 템플릿과 같습니다

설치는 [`hardware_dram/rvx/install_to_platform.sh`](../../hardware_dram/rvx/install_to_platform.sh)
입니다. RTL 17개(DRAM Main IP 12 + 통신 계층 mmio · 적재기 2 + `bbht_dram_top` + 브리지 + 최상단)를 파일 이름으로 하나씩
옮깁니다. `src/` 에 최상위 후보가 셋(`bbht_dram_top` · `bbht_dram_axi_top` · 계약판
`bbht_rvx_wrapper`)이라 glob 을 쓰지 않습니다. 펌웨어(드라이버와 `bbht_console`)는
`hardware_bram/firmware/` 의 것을 그대로 옮깁니다.

---

## 22.7 검증

| 단계 | 결과 | 근거 |
|---|---|---|
| 회귀 (`make -C hardware_dram/sim`) | 추상 포트 위 store · prep · core · top 전부 통과 | — |
| Predicate500 + AXI 모델 | 네 술어 × 500 워크로드가 SW 기준모델과 여섯 축 2,000/2,000. AXI 모델 기본 지연과 백프레셔 두 벌 모두. 프로토콜 위반 0, 한 번도 안 쓴 워드 읽기 0 | [`hardware_dram/results/2026-09-25_predicate500_axi/`](../../hardware_dram/results/2026-09-25_predicate500_axi/evidence.md) |
| SoC RTL 시뮬 (실제 CPU · NoC · DDR 모델) | 콘솔 스크립트 16실행(네 술어 × M 64·256 × 시드 2)이 SW 기준모델과 16/16, 보드가 만든 데이터셋 해시 8/8. 궤적은 verilator 와 같고 사이클은 NoC·DDR 모델 지연 때문에 약 1.4배 | [`hardware_dram/results/2026-09-25_soc_rtl_predicate500/`](../../hardware_dram/results/2026-09-25_soc_rtl_predicate500/evidence.md) |
| 보드 (2026-10-04, DDR3 실물) | 네 술어 × 500 이 SW 기준모델과 2,000/2,000. 사이클은 SoC RTL 시뮬과 0.16% 안, AXI 모델의 1.439배. 같은 워크로드를 다시 돌리면 사이클이 최대 0.033% 흔들림 | [`hardware_dram/vivado/.../2026-10-04_board_predicate500/`](../../hardware_dram/vivado/vivado_bbht_grover_dram/2026-10-04_board_predicate500/evidence.md) |

AXI 메모리 모델([`testbench/axi4_mem_model.v`](../../hardware_dram/testbench/axi4_mem_model.v))은
심판 역할도 합니다. 크기 · INCR · 4 KiB 경계 · 16 beat 상한 · 주소 범위 · `wlast` 위치를 매 버스트
검사하고, 한 번도 쓰지 않은 워드를 읽으면 오류로 셉니다(쓰기-읽기 순서가 깨지면 여기서
잡힙니다). `AXI_STALL=1` 이면 `awready` · `wready` · `arready` · `rvalid` 에 LFSR 로 불규칙한
빈틈을 넣습니다.

**DRAM 표는 시드가 바뀌어도 남습니다.** 데이터셋 적재나 술어 변경 때만 버려집니다. 그래서
보드·RTL 의 물리 반복은 탐색마다 표를 비우는 기준모델 열(`actual_iter_dram_all_j`)이 아니라
같은 순서로 표를 이어 쓰는 열(`actual_iter_dram_session`)과 맞아야 합니다.

### 22.7.1 사이클 — 32비트 AXI 의 값

한 슬롯을 옮기는 데 최소 11,776 사이클이 듭니다. 같은 워크로드에서 추상 포트(한 사이클
한 행) 모델보다 약 6.4배, bram 체크포인트보다 약 11배 느립니다(숫자는 위 근거 묶음).
보드에서는 NoC 와 MIG 를 거쳐 AXI 모델의 1.439배가 되었고, 같은 보드에서 실경과 시간으로
bram 체크포인트 판의 15.65배, 체크포인트 없는 판의 5.57배입니다(2026-10-04). **이 갈래가 bram 정본을 이기려면
DRAM 쪽 폭부터 넓혀야 합니다** — 이 보드에서는 RVX 가 주는 DRAM 이 32비트 하나라서,
넓히려면 MIG 를 직접 붙이는(RVX `slow_dram` 을 쓰지 않는) 길을 따로 가야 합니다.

---

## 22.8 합성과 구현

```bash
source /opt/rvx/rvx_setup.sh
hardware_dram/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_dram
make syn                                   # 플랫폼 생성 (처음 한 번)
cd imp_arty-100t_<날짜> && make reimp        # 합성 · 구현 · 비트스트림 (10분쯤)
make bbht_console                          # 보드용 콘솔 hex
```

결과는 **100 MHz 타이밍 클로즈, 셋업 WNS +0.005 ns · 홀드 WHS +0.021 ns** 입니다
([구현 묶음](../../hardware_dram/vivado/vivado_bbht_grover_dram/2026-09-25_dram_axi_build/evidence.md),
[굽는 묶음](../../hardware_dram/bitstream/2026-09-25_dram_axi/evidence.md)). 최악 경로는 150 MHz
로 도는 RVX NoC 안이고, 가속기 클럭(100 MHz)은 +0.431 ns 남습니다. 같은 날 세 번 구현했습니다.

| 차수 | 브리지 | 배치·배선 | WNS | 결과 |
|---|---|---|---:|---|
| 1 | 256 beat, W 쪽에서 버스트 길이를 곧바로 계산 | RVX 기본 | −2.097 | 타이밍 실패 (6.1 · 6.2) |
| 2 | 256 beat, W 쪽 길이 계산을 한 사이클 늦춤 | `pnr_manually.tcl` | +0.068 | 타이밍은 맞았지만 SoC 시뮬에서 멈춤 (22.5.2) |
| 3 | 16 beat, AW/AR 넷까지, W 는 awlen 큐 | `pnr_manually.tcl` | **+0.005** | 최종 |

### 22.8.1 브리지의 버스트 길이 계산 (우리 RTL)

첫 구현에서 가속기 클럭 쪽 최악 경로 10개가 전부 브리지의 `w_left` 였습니다(−2.097 ns).
쓰기 세션을 시작하는 사이클에 요청 래치 선택 → `(len+1) × 23` 곱셈 → 4 KiB 경계까지 남은
워드와 비교 → `w_left` 가 한꺼번에 걸렸습니다. `wlast` 직후 다음 버스트 길이를 구하는
자리도 덧셈 두 번과 비교가 이어졌습니다.

2차에서는 두 자리를 한 사이클 늦춰 이미 레지스터에 든 값으로 계산했습니다. 타이밍은
풀렸지만 그 사이클에 `wvalid` 를 내려야 해서 버스트마다 1사이클이 비었고, 16 beat 로 바꾸면
슬롯당 736사이클(쓰기 처리량 약 6%)이 됩니다. 그래서 3차에서는 W 쪽 계산을 아예 없앴습니다.
AW 쪽은 원래 레지스터 값으로 길이를 계산하므로, AW 가 수락될 때 그 `awlen` 을 큐에 넣고 W 는
큐 머리를 beat 카운터와 맞대기만 합니다(22.5.3). 가속기 클럭의 WNS 는 +0.431 ns 가 됐고 빈
사이클도 없습니다.

### 22.8.2 NoC 가 150 MHz 로 돈다 (RVX)

나머지 79곳(−0.659 ns)은 RVX 가 만든 NoC 안, 시스템 SRAM 인터페이스의 13단 경로였습니다.
RVX 는 DRAM 을 넣으면 생성 RTL 에서 `assign clk_noc = clk_dram_if;` 로 NoC 를 MIG 의
ui_clk 에 옮깁니다. 이 보드의 MIG 설정(`mig_b.prj`, PHY 2:1)에서 그 클럭이 150 MHz 이고,
bram 플랫폼(NoC 50 MHz)에는 없던 제약입니다.

RVX 코드를 고치지 않고 푸는 자리가 있습니다. 구현 스크립트(`__implement.tcl`)는
`${PLATFORM_DIR}/user/fpga/${FPGA_NAME}/pnr_manually.tcl` 이 있으면 기본
`opt_design; place_design; route_design` 대신 그것을 씁니다. 저장소의
[`hardware_dram/rvx/pnr_manually.tcl`](../../hardware_dram/rvx/pnr_manually.tcl) 을 설치
스크립트가 그 자리에 둡니다.

| 단계 | 지시어 | 셋업 WNS |
|---|---|---:|
| 논리 최적화 | `opt_design -directive Explore` | −3.043 |
| 배치 | `place_design -directive ExtraTimingOpt` | −0.573 |
| 배치 뒤 최적화 | `phys_opt_design -directive AggressiveExplore` | +0.001 |
| 배선 | `route_design -directive Explore` | **+0.005** |
| 배선 뒤 최적화 (음수일 때만) | `phys_opt_design -directive AggressiveExplore` | 건너뜀 |

(3차 빌드의 값입니다. 2차는 배선 뒤 −0.083 에서 이 단계로 +0.068 까지 올라갔습니다.)

여유가 얇습니다. RTL 을 바꿔 다시 구현하면 이 표부터 다시 보십시오. 더 여유를 원하면
MIG 를 PHY 4:1(ui_clk 약 83 MHz)로 바꾸는 길이 있습니다. RVX 에 그 설정(`mig_a.prj`)이 같이
들어 있지만 입력 클럭이 166.666 MHz 라 RVX 가 주는 150 MHz 와 맞지 않고, RVX 설치본의 보드
정의까지 고쳐야 해서 이번에는 하지 않았습니다.

### 22.8.3 자원

| 항목 | 전체 | 가속기 (`bbht_dram_axi_top`) | 그중 브리지 |
|---|---:|---:|---:|
| LUT | 27,379 | 10,094 | 292 |
| FF | 34,162 | 10,531 | 1,744 |
| BRAM (RAMB36 / RAMB18) | 81 타일 | 1 / 96 | 0 |
| DSP | 74 | 70 | 4 |

---

## 22.9 한계와 남은 일

- **열거(`enum_enable=1`)는 여전히 `config_error` 입니다.** 단일 탐색만 됩니다.
- 버퍼 B 를 쓰는 라운드 간 프리페치는 없습니다.
- RTL 시뮬의 DDR 모델은 2 MiB(`SIM_LARGE_RAM_SIZE`)로 고정이고 spec 으로 못 바꿉니다.
  슬롯 `j` 가 43 을 넘는 탐색은 SoC 시뮬에서 돌리지 마십시오. SoC 시뮬 스크립트
  (`script_predicate500_dram.h`)가 M = 64 와 256 만 쓰는 이유입니다.
- 보드에서는 Predicate500 만 돌렸습니다(2026-10-04). 사이클이 실행마다 조금씩 흔들리므로 사이클을 인용할 때는 그 폭을 같이 적습니다.
