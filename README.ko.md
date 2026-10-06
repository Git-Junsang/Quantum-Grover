# 다중 술어 Grover 탐색 가속기

온칩 메모리에 담긴 데이터 배열에서 `<`, `>`, `=`, 범위(`a < x < b`) 네 가지 술어를
만족하는 인덱스를 Grover 알고리즘으로 찾는 FPGA 에뮬레이터 가속기입니다.
호스트 PC 가 UART 로 술어와 임계값을 보내면 RVX SoC 안의 커스텀 IP 가 계산해
결과 인덱스를 돌려줍니다.

- 보드: Arty A7-100T (`xc7a100tcsg324-1`)
- 정합성 기준: **K3/H3-E4-M2** (2026-09-07 빌드, 2026-09-08 실측). 보드에서 검증된 쪽이 정본입니다.

---

## 1. 지금 어디까지 왔는가

| 무엇                                                     | 상태                                                          |
| -------------------------------------------------------- | ------------------------------------------------------------- |
| Main IP 알고리즘 (Q14 / P32 / DATA16)                    | K3/H3-E4-M2. 보드 sign-off 완료                               |
| 통신 계층 (CSR · DMA · FIFO · 드라이버 · UART 콘솔) | 우리 통신 계층 판을 보드에서 확인. 2026-09-17 명령 왕복, 2026-10-04 네 술어 × 500 × 두 모드 4,000 실행이 기준모델과 4,000/4,000 (실경과 시간 포함) |
| 100 MHz 구현                                             | 타이밍 클로즈 (WNS +0.126 ns). 리포트는`hardware_bram/models/hardware_bram_K3H3_E4_M2/vivado/` |
| **Main IP RTL 소스**                               | `hardware_bram/src/` 에 최신판 한 벌. 비트스트림과 sha256 동일한 판은 태그 `board-k3h3-e4-m2` (그 시점 폴더 이름은 `hardware_bram/`) |
| 성능 근거                                                | 보드 실경과 시간 **7.626x**, RTL 사이클 **6.1401x**, ORCA 1코어 대비 **116,426x** |
| 소프트웨어 기준모델                                      | NumPy · Qiskit Aer · Q1.22 bit-exact · K3/H3 정책 모델. 보드와 같은 500 워크로드에서 탐색 궤적과 물리 반복이 500/500 일치 |

배선 정합성은 [포트 대조기](software/contract/check_ports.py)가 인수인계 문서의 포트 표
(wrapper 19 + core 61)와 RTL 을 맞춰 보며 지킵니다. `stub` · `real` · `dram` 세 갈래
모두 일치합니다.

---

## 2. 확정 수치

CSR 의 정본은 [`software/contract/bbht_grover_csr.json`](software/contract/bbht_grover_csr.json)
하나이고, `gen_csr.py` 가 거기서 Verilog · C · Python 헤더와
기술문서 [13장](documents/design_references/13_CSR_레지스터와_실행_모드.md)을 만듭니다.
같은 숫자를 들고 있으면서 생성 대상이 아닌 두 곳(소프트웨어 기준모델, 보드 벤치 앱)은
`--check` 가 읽어서 대조합니다.

| 항목        | 값                                                                                            |
| ----------- | --------------------------------------------------------------------------------------------- |
| 큐비트      | Q = 14 (N = 16,384)                                                                           |
| 데이터 워드 | 16비트 signed                                                                                 |
| 진폭        | Q1.22 계열 23비트                                                                             |
| 병렬도      | P = 32 레인                                                                                   |
| 술어        | `LT` · `GT` · `EQ` · `RANGE`                                                       |
| 실행 모드   | `MANUAL_SINGLE` · `NORMAL_SINGLE` · `CKPT_SINGLE` · `NORMAL_ENUM` · `CKPT_ENUM` (K·H 는 CSR 이 아니라 빌드 상수) |
| CSR         | APB 슬레이브, base`0xE2020000`, 4바이트 간격, 32비트, 38개                                  |
| 데이터 적재 | AHB 마스터 SINGLE, single outstanding. SRAM`0xE0000000`~`0xE001FFFF`                      |
| 결과 FIFO   | 깊이 256                                                                                      |
| 클럭        | 가속기 100 MHz / 시스템 50 MHz                                                                |
| 최종 구성   | **K3/H3-E4-M2** — 체크포인트 3벌 · 정책 지평 3 · 반복 내 연산기 4벌 · 측정 최적화 2단        |

### 성능 — 축을 섞지 마십시오

| 축 | 값 | 근거 |
|---|---|---|
| 보드 실경과 시간 | Normal 425,502 us → **55,798 us** (7.626x) | `hardware_bram/models/hardware_bram_K3H3_E4_M2/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/` |
| RTL 사이클 (6단계) | Normal 42,308,335 → **6,890,470** (6.1401x) | `hardware_bram/results/2026-09-08_publication_6stage/` |
| 소프트웨어 대비 | ORCA 1코어 대비 **116,426x** | `hardware_bram/models/hardware_bram_K3H3_E4_M2/vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/` |

셋 다 같은 500 워크로드(M = 1/4/16/64/256 × 시드 100)입니다. 궤적은 보드와 RTL 이
500/500 일치하지만 사이클 값 자체는 다르므로, 두 축을 섞어 배수를 만들면 안 됩니다.

---

## 3. 두 갈래와 BRAM 모델들

반복 실패 시 진폭 배열을 어떻게 재활용하느냐에서 구현이 둘로 나뉩니다.
**아직 어느 쪽도 확정이 아니고, 나중에 하나를 고릅니다.** 하드웨어 트리는
`hardware_bram/` 과 `hardware_dram/` 둘입니다. 2026-10-06 에 옛
`hardware_bram_checkpoint/` · `hardware_bram_nocheckpoint/` 를 `hardware_bram/` 하나로
모으고, 체크포인트 · 연산기 구성마다 모델 폴더를 나눴습니다. 태그(`board-k3h3-e4-m2` 등)
안에서는 폴더 이름이 그때 이름인 `hardware_bram/` 그대로입니다.

### `hardware_bram/` — BRAM 갈래 공용 소스 + 모델 열 개

BRAM 만 씁니다. 실패한 샷의 진폭을 버리지 않고 체크포인트에서 차이만큼만 이어 돌리고
(K·H), 물리 Grover 반복 한 번 안에서 P=32 연산기 여러 벌이 512행을 나눠 처리합니다(E).
보드 정본이 이 갈래입니다.

Main IP 는 체크포인트 수 K · 정책 지평 H · 연산기 벌 수 E · 측정 최적화 M1/M2 가 전부
컴파일 파라미터입니다. 그래서 모든 모델이 **같은 RTL 을 파라미터만 달리 컴파일**합니다.
통신 계층 · Main IP · 테스트벤치 · 펌웨어 · 시뮬 · 합성은 `hardware_bram/` 바로 아래에
한 벌만 두고, 모델마다 다른 것 -- 파라미터 기본값을 정하는 어댑터 하나, RVX 플랫폼 정의,
그 모델의 구현 리포트 · 보드 실측 · 비트스트림 -- 만 `hardware_bram/models/hardware_bram_<모델>/`
에 둡니다. 모델은 지금까지 실험한 조합 열 개입니다.

| 모델 | K/H | E | M | 어디서 나왔나 | 실물 |
|---|---|---|---|---|---|
| `K3H3_E4_M2` | 3/3 | 4 | M2 | **최종 구성** (6단계 ablation 마지막 단계) | 보드 실측 정본 (2026-09-08) |
| `K3H3_E4_M1` | 3/3 | 4 | M1 | 6단계 ablation 다섯째 단계 | RTL 시뮬만 |
| `K3H3_E4` | 3/3 | 4 | - | 6단계 ablation 넷째 단계 | RTL 시뮬만 |
| `K4H4_E4` | 4/4 | 4 | - | 6단계 ablation 셋째 단계 | RTL 시뮬만 |
| `K4H4_E1` | 4/4 | 1 | - | 6단계 ablation 둘째 단계, K/H 단독 실험 대조군 | 옛 RTL 보드 실측 (2026-09-04) |
| `K3H4_E1` | 3/4 | 1 | - | K/H 단독 실험 | RTL 시뮬만 |
| `K3H3_E1` | 3/3 | 1 | - | K/H 단독 실험 | RTL 시뮬만 |
| `K4H8_E1` | 4/8 | 1 | - | 첫 체크포인트 보드 실측 | 옛 RTL 보드 실측 (2026-09-01) |
| `nocheckpoint` | 없음 | 4 | - | 비교 기준 판 Normal-E4 (아래) | 보드 실측 (2026-10-04) |
| `Normal_E1` | 없음 | 1 | - | 6단계 ablation 첫 단계와 같은 구성 | 없음 |

6단계 ablation 과 K/H 단독 실험의 수치는 태그 안 standalone top 으로 잰 것이고, 모델
어댑터는 그 top 들이 넘기던 파라미터를 그대로 옮긴 것입니다. `Normal_E1` 단계는 그 캠페인에서
`K4H4_E1` 빌드를 런타임 NORMAL 로 돌려 쟀고, 체크포인트 하드웨어를 뺀 빌드는 이 모델이
처음입니다. `K4H8_E1` · `K4H4_E1` 의 보드 비트스트림은 단일 연산기 시절의 옛 RTL 로 만든
것이라, 현행 Main IP 에 이 어댑터를 문 것과 바이트가 같지 않습니다. 열 모델 모두 포트 계약 ·
lint · 실물 코어 통신 계약 T1~T9 를 통과합니다 (`make -C hardware_bram/sim ports-models
lint-models`, `make -C hardware_bram/sim real MODEL=<모델>`).

### `hardware_dram/` — DRAM 전량 저장 + BRAM 큐

`j` 별 진폭을 DRAM 에 모두 저장해 둡니다. 난수 생성기가 뽑은 `j` 는 BRAM 의 큐에도
같이 올려 둡니다. 정답 후보를 찍고 검증해서 틀렸으면 큐에서 그 `j` 의 진폭을 지우고,
DRAM 에서 다음 `j` 의 진폭을 가져와 큐에 올립니다. 어떤 `j` 든 버스트 한 번이면
닿으므로 체크포인트 개수 K 도, 앞을 내다보는 정책 H 도 필요하지 않습니다.

호스트 통신 경로(APB CSR · AHB 적재)를 묶은 최상단 `src/bbht_dram_top.v` 에,
2026-09-25 부터 **DRAM burst 포트를 32비트 AXI4 로 바꾸는 브리지**
(`src/grover_dram_axi_bridge.v`)를 붙여 RVX 플랫폼 `bbht_grover_dram` 의 DDR3
(`slow_dram`)에 잇습니다. 네 술어 × 500 워크로드가 AXI 메모리 모델 위에서 SW 기준모델과
2,000/2,000 맞았습니다. 실제 NoC 와 DDR 모델이 들어간 SoC RTL 시뮬에서도 콘솔 16실행이
16/16 맞았고, 2026-10-04 에 보드(DDR3 실물)에서도 2,000/2,000 맞았습니다. 같은 보드에서
체크포인트 판보다 실경과 시간으로 약 15.6배 느립니다
([기술문서 22장](documents/design_references/22_DRAM_갈래.md)).
회귀는 동작 수준 DRAM 모델 위에서 합니다 (`make -C hardware_dram/sim`,
최상단은 `top` 타깃). 같은 자극을
`hardware_bram` 의 Main IP(K3/H3-E4-M2)에도 걸어 탐색 궤적이 일치하는지 보는 대조는 `make -C hardware_dram/sim equiv`
입니다. 지금은 단일탐색만 되고 열거는 `config_error` 로 거절합니다.

### `hardware_bram/models/hardware_bram_nocheckpoint/` — 체크포인트 없는 비교 기준 판

연산기 네 벌(E4)만 켜고 체크포인트 · 정책 엔진 · 측정 최적화 M1/M2 를 끈 Normal-E4 입니다.
같은 보드 · 같은 SoC 에서 최적화 유무에 따른 속도를 맞대려고 만들었습니다. 다른 모델처럼
Main IP · 통신 계층 · 펌웨어는 `hardware_bram/` 공용 것을 그대로 쓰고, 이 판의 RTL 은
파라미터 기본값과 burst 처리만 다른 어댑터 하나입니다.

Normal 2,000 실행이 SW 기준모델과 맞습니다. `K3H3_E4` 모델(체크포인트 판에서 M1/M2 만 끈 것)을
Normal 로 돌린 것과는 **사이클까지** 2,000/2,000 같습니다. RTL 사이클로는 K3/H3-E4-M2 가 이 판보다
2.897배 빠릅니다. 2026-10-04 에 보드에서 Normal 2,000 이 기준모델과 맞았고, 같은 보드에서
체크포인트 판이 실경과 시간으로 **2.810배** 빠릅니다
([기술문서 21장](documents/design_references/21_체크포인트_없는_BRAM_판.md)).

`hardware_bram/` 과 `hardware_dram/` 은 `src` · `testbench` · `sim` · `rvx` · `firmware` 로
같은 모양을 하고, bram 쪽은 모델마다 다른 `vivado` · `bitstream` 과 모델 전용 `results` 가
`models/` 아래로 내려가 있습니다. 소프트웨어 기준모델과 검증 벡터와 비교 실험은 두 트리가
`software/` 에서 공유합니다.

---

## 4. 디렉터리 구조

```
documents/
  design_references/    기술문서. 번호 장 24개, 입구는 00_문서_지도.md
    diagrams/           그 장들이 참조하는 그림 (유일한 하위 폴더)
  study_references/     학습용 해설서 0~18장 + 부록 A
  papers/               원문 논문 PDF (papers_ko/ 에 한국어 해설본)
  check_docs.py         문서 정합성 검사기
  *.pptx                최종 Main IP 발표 자료 (읽기 전용)

hardware_bram/          갈래 1 — BRAM 전용. 아래는 모든 모델이 같이 쓰는 것
  src/                  RTL 한 벌 (통신 계층 + 최상단 + Main IP). 어댑터는 모델 폴더에.
                        보드에 구운 판은 태그 board-k3h3-e4-m2
  testbench/            테스트벤치. verilator C++ 하네스 포함
  sim/                  Makefile · 러너 · 보고 스크립트. MODEL=<모델> 로 어댑터를 고름
  synth/                Vivado 배치 스크립트. Main IP 자원 합성
  results/              모델 사이 비교 근거 (6단계 ablation · 자원 5구성 · K/H 단독)
  rvx/                  공용 RVX 설치기 install_model.sh · user region 템플릿
  firmware/             드라이버 · 콘솔 앱 · 벤치 앱 · ORCA 기준선
  models/               모델 열 개. 폴더 이름은 hardware_bram_<모델>
    hardware_bram_K3H3_E4_M2/   최종 구성 (보드 정본)
      src/              어댑터 하나 (K·H·E·M 기본값)
      rvx/              RVX 플랫폼 bbht_grover_upgrade 정의와 설치 스크립트
      results/          이 구성의 시뮬 근거 묶음 (YYYY-MM-DD_<주제>/)
      vivado/           Vivado 프로젝트 vivado_bbht_grover_fpga (리포트 · 보드 실측)
      bitstream/        보드에 구운 비트스트림 묶음
    hardware_bram_nocheckpoint/ 비교 기준 Normal-E4. src rvx sim results vivado bitstream
    hardware_bram_K4H8_E1/      src rvx + vivado/ 에 옛 RTL 보드 실측 (2026-09-01)
    hardware_bram_K4H4_E1/      src rvx + vivado/ 에 옛 RTL 보드 실측 (2026-09-04)
    hardware_bram_{Normal_E1,K3H4_E1,K3H3_E1,K4H4_E4,K3H3_E4,K3H3_E4_M1}/
                        src rvx 만 (비트스트림을 낸 적 없음)

hardware_dram/          갈래 2 — DRAM 전량 저장 + BRAM 큐
                        (RTL + 최상단 + AXI4 브리지 + RVX 설치. 2026-10-04 보드 실측)
                        모델 폴더 없이 한 벌이고, 하위 구조는 hardware_bram 에 vivado ·
                        bitstream 을 더한 모양입니다 (synth 만 없음)

software/               두 트리가 공유
  models/               NumPy · Qiskit · Q1.22 bit-exact · 체크포인트 정책 기준모델
  experiments/          Common500 비교 실험 (보드와 같은 500 워크로드)
  rtl_vectors/          RTL 정답 벡터 (requested-j 256케이스 · 열거 두 방식)
                          tools/dump_bench_workload.py -- bench250/500 자극 생성
  results/              Common500 최종 결과 · 표 · 그래프 · 검증 보고서
  contract/             하드웨어-소프트웨어 계약 두 벌과 대조기
                          CSR 정본 JSON · gen_csr.py · generated/
                          port_contract.tsv · check_ports.py
  host/bbht_cli.py      호스트 PC CLI (실 UART · mock · 시뮬 트랜스크립트 재생)
  host/bbht_predicate500.py  네 술어 x 500 워크로드 보드 자동 테스트 -> 엑셀
  requirements.txt      Common500 재실행용 파이썬 패키지

trash_bin/              구 스펙 문서와 대용량 산출물 보관. git 추적 안 함
```

---

## 5. 빠르게 돌려 보기

```bash
# 통신 계층 회귀 / 통신 계층 + 어댑터 + Main IP / 250쌍 궤적 벤치
make -C hardware_bram/sim ports lint regress driver
make -C hardware_bram/sim real
make -C hardware_bram/sim bench250

# 네 술어 x 500 워크로드: RTL 벤치 세 트리, 그리고 보드 자동 테스트
make -C hardware_bram/sim predicate500
make -C hardware_bram/models/hardware_bram_nocheckpoint/sim predicate500 predicate500-ref equiv
make -C hardware_dram/sim predicate500
python3 software/host/bbht_predicate500.py --port /dev/ttyUSB1

# 소프트웨어 기준모델 Common500 비교 (가상환경에 software/requirements.txt 를 설치한 뒤)
bash software/experiments/common500_benchmark/run_full_benchmark.sh

# RVX 플랫폼에 설치 (위 파일이 있을 때)
source /opt/rvx/rvx_setup.sh
hardware_bram/models/hardware_bram_K3H3_E4_M2/rvx/install_to_platform.sh

# 문서를 고쳤으면
python3 documents/check_docs.py
```

보드에서는 콘솔 앱(`hardware_bram/firmware/bbht_console/`)을 올리고 시리얼 터미널로
명령을 칩니다. 순서는 기술문서 [17장](documents/design_references/17_보드_운용.md)에
있습니다.

---

## 6. 더 읽을 것

| 무엇이 궁금한가            | 어디를 보는가                                                                                                     |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| 전체를 장별로 (24장) | [00_문서_지도.md](documents/design_references/00_문서_지도.md) |
| 호스트에서 어떻게 부리는가 | [17장 보드 운용](documents/design_references/17_보드_운용.md) |
| CSR 레지스터 하나하나 | [13장 CSR 레지스터와 실행 모드](documents/design_references/13_CSR_레지스터와_실행_모드.md) |
| Main IP 포트 | [12장 Main IP 포트 계약](documents/design_references/12_Main_IP_포트_계약.md) |
| 고정소수점과 메모리 배치 | [6장 데이터 표현과 메모리 맵](documents/design_references/06_데이터_표현과_메모리_맵.md) |
| UART 명령 | [14장 호스트 인터페이스와 UART 프로토콜](documents/design_references/14_호스트_인터페이스와_UART_프로토콜.md) |
| 소프트웨어 기준모델과 비교 실험 | [4장 소프트웨어 기준모델과 정답 벡터](documents/design_references/04_소프트웨어_기준모델과_정답_벡터.md) |
| 설계를 왜 이렇게 정했나 | [23장 설계 근거 실험](documents/design_references/23_설계_근거_실험.md) |
| Grover 알고리즘 자체       | [study_references/](documents/study_references/README.md) 0~18장                                                   |

영문 요약은 [README.md](README.md) 에 있습니다.
