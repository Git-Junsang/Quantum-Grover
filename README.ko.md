# 다중 술어 Grover 탐색 가속기

온칩 메모리에 담긴 데이터 배열에서 `<`, `>`, `=`, 범위(`a < x < b`) 네 가지 술어를
만족하는 인덱스를 Grover 알고리즘으로 찾는 FPGA 에뮬레이터 가속기입니다.
호스트 PC 가 UART 로 술어와 임계값을 보내면 RVX SoC 안의 커스텀 IP 가 계산해
결과 인덱스를 돌려줍니다.

- 보드: Arty A7-100T (`xc7a100tcsg324-1`)
- 정합성 기준: **v0.9.8** (2026-09-01). 보드에서 검증된 쪽이 정본입니다.

---

## 1. 지금 어디까지 왔는가

| 무엇                                                     | 상태                                                          |
| -------------------------------------------------------- | ------------------------------------------------------------- |
| Main IP 알고리즘 (Q14 / P32 / DATA16)                    | v0.9.8 freeze. 보드 sign-off 완료                             |
| 통신 계층 (CSR · DMA · FIFO · 드라이버 · 호스트 CLI) | 회귀 통과. 실보드 E2E 는 미완                                 |
| 100 MHz 구현                                             | 타이밍 클로즈. 리포트는`hardware_bram/vivado/`              |
| **Main IP RTL 소스**                               | `hardware_bram/src_v2/` 에 있습니다 (K4/H4 freeze). 어댑터로 통신 계층에 붙습니다 |

Main IP 소스가 freeze 대상이라 배선 정합성은 사람 눈이 아니라
[포트 계약 대조](software/contract/check_ports.py)가 지킵니다. 인수인계 문서의
포트 표(wrapper 19 + core 61)를 `port_contract.tsv` 로 굳혀 두고 회귀가 매번 RTL 과 맞춰 봅니다.

---

## 2. 확정 수치

모든 숫자의 단일 출처는 [`software/csr/bbht_grover_csr.json`](software/csr/bbht_grover_csr.json) 입니다.
C 헤더 · Verilog 헤더 · Python 헤더 · 규격 문서가 전부 여기서 생성됩니다.

| 항목        | 값                                                                                            |
| ----------- | --------------------------------------------------------------------------------------------- |
| 큐비트      | Q = 14 (N = 16,384)                                                                           |
| 데이터 워드 | 16비트 signed                                                                                 |
| 진폭        | Q1.22 계열 23비트                                                                             |
| 병렬도      | P = 32 레인                                                                                   |
| 술어        | `LT` · `GT` · `EQ` · `RANGE`                                                       |
| 실행 모드   | `MANUAL_SINGLE` · `NORMAL_SINGLE` · `K4H8_SINGLE` · `NORMAL_ENUM` · `K4H8_ENUM` |
| CSR         | APB 슬레이브, base`0xE2020000`, 4바이트 간격, 32비트, 38개                                  |
| 데이터 적재 | AHB 마스터 SINGLE, single outstanding. SRAM`0xE0000000`~`0xE001FFFF`                      |
| 결과 FIFO   | 깊이 256                                                                                      |
| 클럭        | 가속기 100 MHz / 시스템 50 MHz                                                                |

---

## 3. 두 갈래로 갈라져 있습니다

반복 실패 시 진폭 배열을 어떻게 재활용하느냐에서 구현이 둘로 나뉩니다.
**아직 어느 쪽도 확정이 아니고, 나중에 하나를 고릅니다.**

### `hardware_bram/` — 체크포인트 + 연산기 두 벌

기존 방식입니다. BRAM 만 씁니다. 실패한 샷의 진폭을 버리지 않고 체크포인트에서
차이만큼만 이어 돌립니다(K4/H4 정책). 연산기를 두 벌 두어 처리량을 벌충합니다.
v0.9.8 실물이 이 갈래이고, 지금 저장소에 있는 코드는 전부 여기 속합니다.

### `hardware_dram/` — DRAM 전량 저장 + BRAM 큐

`j` 별 진폭을 DRAM 에 모두 저장해 둡니다. 난수 생성기가 뽑은 `j` 는 BRAM 의 큐에도
같이 올려 둡니다. 정답 후보를 찍고 검증해서 틀렸으면 큐에서 그 `j` 의 진폭을 지우고,
DRAM 에서 다음 `j` 의 진폭을 가져와 큐에 올립니다. 어떤 `j` 든 버스트 한 번이면
닿으므로 체크포인트 개수 K 도, 앞을 내다보는 정책 H 도 필요하지 않습니다.

**RTL 초안과 회귀가 있고, 물리 DRAM 바인딩(MIG/AXI)과 통신 계층은 아직 없습니다.**
검증은 동작 수준 DRAM 모델 위에서 합니다 (`make -C hardware_dram/sim`). 같은 자극을
`hardware_bram` 에도 걸어 탐색 궤적이 일치하는지 보는 대조는 `make -C hardware_dram/sim equiv`
입니다. 지금은 단일탐색만 되고 열거는 `config_error` 로 거절합니다.

두 트리는 `src` · `testbench` · `sim` · `rvx` · `vivado` · `firmware` 로 같은 모양을 하고,
CSR 정본과 골든 모델과 검증 벡터는 `software/` 에서 공유합니다.

---

## 4. 디렉터리 구조

```
documents/
  design_references/    설계 문서. CSR 규격 · 포트 규격 · 호스트 조작법 · 분석 보고서
    diagrams/           그 문서들이 참조하는 그림 (유일한 하위 폴더)
  study_references/     학습용 해설서 0~18장 + 부록 A
  papers/               원문 논문 PDF (papers_ko/ 에 한국어 해설본)
  check_docs.py         문서 정합성 검사기

hardware_bram/          갈래 1 — 체크포인트 + 연산기 두 벌, BRAM 전용
  src/                  RTL
  testbench/            Verilog 테스트벤치
  sim/                  비 Verilog 하네스 · 빌드 스크립트 · 로그
  rvx/                  RVX 플랫폼 정의와 설치 스크립트
  vivado/               Vivado 프로젝트 폴더. 이름은 소문자 vivado_<프로젝트이름>
  firmware/             드라이버와 콘솔 앱

hardware_dram/          갈래 2 — DRAM 전량 저장 + BRAM 큐
                        (RTL 초안 + 회귀. 물리 DRAM 바인딩과 통신 계층은 아직)

software/
  csr/                  CSR 정본 JSON 과 헤더 생성기       ← 두 갈래가 공유
  contract/             포트 계약과 자동 대조기            ← 두 갈래가 공유
  golden/               골든 모델 (Python)
  bin/                  검증 벡터와 데이터 파일
  bbht_cli.py           호스트 CLI

trash_bin/              구 스펙 문서와 대용량 산출물 보관. git 추적 안 함
```

---

## 5. 빠르게 돌려 보기

```bash
# 통신 계층 회귀 (몇 초). ports 가 포트 계약 대조입니다
make -C hardware_bram/sim ports lint regress driver

# 실물 코어로 같은 넷. 보드와 같은 250쌍 workload 는 bench250
make -C hardware_bram/sim real
make -C hardware_bram/sim bench250

# 호스트 CLI 를 보드 없이
python3 software/bbht_cli.py --port mock \
    -c "GEN COUNT=4096 TARGETS=3 VAL=777" -c LOAD -c "SET MODE=EQ A=777" -c RUN

# RVX 플랫폼에 설치
source /opt/rvx/rvx_setup.sh
hardware_bram/rvx/install_to_platform.sh

# 문서를 고쳤으면
python3 documents/check_docs.py
```

CSR 정본을 고쳤다면 `python3 software/csr/gen_csr.py` 로 헤더를 다시 만드십시오.
회귀가 `--check` 를 먼저 돌리므로 생성물만 손으로 고쳐 놓고 통과시킬 수 없습니다.

---

## 6. 더 읽을 것

| 무엇이 궁금한가            | 어디를 보는가                                                                                                     |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| 호스트에서 어떻게 부리는가 | [design_references/호스트_조작_방법.md](documents/design_references/호스트_조작_방법.md)                           |
| CSR 레지스터 하나하나      | [design_references/CSR_레지스터_규격.md](documents/design_references/CSR_레지스터_규격.md)                         |
| Main IP 포트               | [design_references/Main_IP_포트_규격.md](documents/design_references/Main_IP_포트_규격.md)                         |
| 고정소수점과 메모리 배치   | [design_references/데이터_고정소수점_메모리_규격.md](documents/design_references/데이터_고정소수점_메모리_규격.md) |
| UART 명령                  | [design_references/UART_명령_프로토콜.md](documents/design_references/UART_명령_프로토콜.md)                       |
| Grover 알고리즘 자체       | [study_references/](documents/study_references/README.md) 0~18장                                                   |

영문 요약은 [README.md](README.md) 에 있습니다.
