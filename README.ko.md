# 다중 술어 Grover 탐색 가속기

[English](README.md) | **한국어**

온칩 데이터 배열에서 `<`, `>`, `=`, `a < x < b` 네 가지 술어를 판정하며 15큐비트 Grover 탐색을 에뮬레이션하는 FPGA SoC. 단일 Spartan-7에 올립니다.

중앙대학교 학부 인턴 프로젝트 · 2026

* * *

## 1. 배경

Grover 알고리즘은 정렬되지 않은 `N`개 항목에서 술어를 만족하는 항목을 `O(√N)` 질의에 찾습니다. 이 이득은 **실제 양자 하드웨어**의 것입니다. 상태벡터를 고전 회로로 펼쳐 흉내 내면 반복마다 `N`개 진폭을 전부 훑어야 하므로 `O(N·√(N/M))`이 되고, 고전 선형 스캔보다 오히려 느립니다.

그래서 이 가속기의 값어치는 속도가 아닙니다. **양자 알고리즘의 동작을 결정적이고 재현 가능하게 재현·검증하는 전용 엔진**이라는 데 있습니다. 비교 대상도 고전 스캔이 아니라 소프트웨어 상태벡터 시뮬레이터(Qiskit AerSimulator, NumPy)입니다.

기존 Grover FPGA 에뮬레이터는 대부분 정답 인덱스를 파라미터로 못 박거나 정답이 하나라고 가정합니다. 이 프로젝트는 두 가정을 모두 버립니다. 오라클이 인덱스가 아니라 **데이터 값**을 비교해 판정하고, 정답이 여럿일 때도 중복 없이 전부 열거합니다.

* * *

## 2. 시스템 개요

| 구성 요소 | 역할 |
|---|---|
| 호스트 PC | UART로 술어·임계값 전송, 결과 인덱스 수신 |
| RVX SoC (`rvc_orca` RV32) | 술어·임계값 정책, UART 파싱, 열거 라운드 종료 판단, 데이터 준비. 펌웨어 구동 모드에서는 매 샷 절대값 `j_target` 기록 |
| **Grover IP** (직접 설계) | 진폭 초기화 · 오라클 · 확산 · Born 측정 · 고전 검증 · 재개 캐시 판정. 자율 모드에서는 BBHT 샷 루프까지 |
| APB 슬레이브 | 제어·상태 레지스터 |
| AHB 마스터 | 탐색 데이터 배열 DMA 적재 |

샷 루프는 **두 모드가 공존**합니다. **BBHT 자율 모드**에서는 하드웨어의 바깥 FSM이 `m`을 갱신하고 LFSR로 `j_target`을 뽑고 캐시 유효성을 판정하며, 펌웨어가 보는 것은 설정 → `start` → 폴링 → 결과 읽기 네 줄뿐입니다. **펌웨어 구동 모드**에서는 앱이 매 샷 절대값 `j_target`을 씁니다. 어느 쪽이든 `j_cur`과 `cache_valid`는 하드웨어가 소유하므로 캐시 상태가 두 곳에 존재하는 일이 없습니다.

| 항목 | 값 |
|---|---|
| 대상 FPGA | Arty-S7-50 (`xc7s50csga324-1`) |
| 목표 큐비트 | n = 15 (N = 32,768) |
| 진폭 표현 | 실수 전용 고정소수점, 18비트 Q2.16, round-half-to-even, 포화 |
| 데이터 워드 | 16비트 signed |
| 병렬도 | P = 32 레인 (인덱스 하위 5비트로 뱅크 선택) |
| 반복 1회 | 2패스 = 2N/P = 2,048 사이클 |
| 목표 클럭 | 100 MHz (RVX 기본 생성물은 `SYSTEM_CLK_HZ = 50 MHz` — Phase 0에서 확인) |
| 탐색 1회 | 약 3.7 ms (n=15, M=1, 캐시 적용) |

* * *

## 3. 알고리즘과 하드웨어 아키텍처

### 3.1 알고리즘 — 술어 오라클을 쓰는 BBHT

정답 개수 `M`은 술어·임계값·데이터에 의존하므로 사전에 알 수 없습니다. 양자 위상 추정으로 세는 정공법은 복소수를 강제해 실수 전용 데이터패스를 무너뜨리므로, 대신 **BBHT**를 씁니다.

```
m ← 1,  λ ← 6/5
반복:
    j ~ U[0, m)                      # 균등 추출
    Grover 반복을 j회                # 재개 캐시가 여기서 개입
    Born 샘플링으로 측정
    고전 검증 — data_mem 한 칸을 다시 읽어 술어 재확인
    실패하면  m ← min(1.2·m, √N)
```

`m`이 1부터 완만히 커지므로 초반 샷은 거의 다 실패합니다. n=15·M=1에서 평균 **24.5샷**입니다(몬테카를로 20,000회).

**재개 캐시 — 핵심 기여.** 진폭 배열에 쓰는 것은 초기화·오라클·확산 셋뿐입니다. Born 측정은 배열을 **읽기만** 하고 고전 검증은 데이터 한 칸만 봅니다. 따라서 샷이 실패해도 `j_prev`회 반복한 상태가 그대로 남습니다.

```
if (!cache_valid || force_init || j_target < j_cur)   초기화 후 j_target회 전진
else                                                   (j_target − j_cur)회만 이어서 전진
```

재개 경로는 새로 초기화해서 `j`회 돌린 것과 **문자 그대로 같은 연산열**이라 결과가 비트 단위로 동일합니다. **추가 BRAM은 0개** — `j_cur`과 `cache_valid` 레지스터뿐입니다. 측정 병렬화와 합치면 약 **35 %**를 절감합니다(n=15·M=1·몬테카를로 20,000회. M=256에서는 29 %로 낮아집니다).

| 술어 | `mode` | 판정 |
|---|:-:|---|
| `value < thr_a` | 0 | `value − thr_a` 의 MSB |
| `value > thr_a` | 1 | 피연산자를 바꾼 같은 MSB |
| `value == thr_a` | 2 | XOR-NOR |
| `thr_a < value < thr_b` | 3 | 두 비교의 AND |

비교기 IP를 쓰지 않습니다. 감산기 하나의 부호비트가 곧 답입니다. 열거 모드에서는 `!found[i]`를 AND로 걸어 이미 보고한 해를 제외합니다.

### 3.2 하드웨어 아키텍처 — RTL

확산이 배열 전체의 평균을 필요로 하므로 오라클과 한 패스에 묶을 수 없어, 한 반복이 두 패스로 나뉩니다.

| 상태 | 사이클 | 하는 일 |
|---|--:|---|
| `S_INIT` | 1,024 | 전 칸에 `INIT_AMP`(n=15에서 362) 기입 |
| `S_PASS1` | 1,024 | 술어 판정 → 부호 반전 → 되쓰기, 같은 사이클에 누산 |
| `S_MEAN` | 1 | 누산기를 `n−1`칸 산술 우시프트 → `two_mean` |
| `S_PASS2` | 1,024 | 각 칸을 `two_mean − amp` 로 갱신 |

**확산에 곱셈기가 없습니다.** 확산이 필요로 하는 값은 2×평균이므로 누산기를 `n−1`칸 **한 번에** 밉니다 — `>>> n` 후 `<<< 1`은 최하위 비트를 버리고 반올림 지점을 두 곳으로 만들기 때문에 쓰지 않습니다. 나머지는 뺄셈입니다. 이 설계에서 DSP를 쓰는 곳은 측정 경로의 제곱기 32개뿐입니다.

**측정은 argmax가 아니라 Born 샘플링입니다.** 오라클과 확산이 정답 집합을 완전히 대칭으로 다루므로 `M`개 정답의 진폭이 매 반복 **정확히 같아집니다.** 최대 진폭을 고르는 회로는 영원히 같은 인덱스만 반환해 열거가 불가능합니다. 2단 병렬 샘플러는 32,768 대신 2,080 사이클에 끝납니다.

| 자원 | 구성 | BRAM36 | DSP |
|---|---|--:|--:|
| `amp_mem` | 32뱅크 × 1024 × 18b | 16 | 0 |
| `data_mem` | 32뱅크 × 1024 × 16b | 16 | 0 |
| `mask_mem` | 1024 × 32b | 1 | 0 |
| 연산 레인 × 32 | 비교기·부호반전·확산 | 0 | **0** |
| `born_sampler` | 제곱기 32개 | 0 | 32 |
| **IP 합계** | | **33 / 75** | **32 / 120** |

* * *

## 4. 디렉터리 구조

```
├── hardware/
│   ├── src/                   # RTL (Verilog) + grover_param.vh
│   ├── testbench/             # 테스트벤치, iverilog 회귀의 진입점
│   └── sim/                   # verilator 하네스
├── software/
│   ├── golden/                # float64 참조, 비트정확 고정소수점 모델, 검증 벡터
│   ├── soc/                   # RVX 플랫폼, RISC-V 앱, 드라이버
│   ├── host/                  # grover_cli.py (UART 클라이언트)
│   ├── bench/                 # 벤치마크 스윕
│   └── tools/                 # deploy.sh
└── documents/
    ├── study_references/      # 주교재 — 0~18장 + 부록 A
    ├── design/                # 개발계획.md (현행) + 2026-07 기록 (머리의 경고 참조)
    ├── presentation/          # 발표자료, 이름 규칙 YYYY-MM-DD_<종류>_<주제>
    ├── papers/                # 원문 논문 (읽기 전용)
    ├── papers_ko/             # 논문 한국어 해설본 (보조)
    └── check_docs.py          # 문서 정합성 검사기
```

`hardware/src/` 와 `hardware/testbench/` 에 RTL 21개 모듈과 iverilog 회귀가 들어 있습니다. `hardware/sim/` 와 `software/` 는 아직 비어 있습니다. 아래 개발 현황 참조.

* * *

## 5. 시작하기

### 5.1 골든 모델 (Python)

```bash
cd software/golden
python3 run_all.py            # float64 참조 → 비트정확 고정소수점 모델 → RTL 검증 벡터
```

### 5.2 RTL 시뮬레이션 (로컬)

```bash
make -C hardware/testbench regress     # iverilog + vvp, 골든 벡터와 비트 단위 대조
```

로컬에서 쓸 수 있는 것은 `iverilog`, `vvp`, `verilator`, `gtkwave` 입니다.

### 5.3 SoC 통합·합성 (RVX 원격)

```bash
source /home/coder/rvx_lec_hw/rvx_setup.sh
cd $RVX_MINI_HOME/platform/grover_soc
make syn && make sim_rtl                       # 원격 ModelSim
make imp_fpga TARGET_IMP_CLASS=arty-50         # 원격 Vivado → 비트스트림
```

RVX Mini(씬 클라이언트) 판이라 생성·시뮬·합성이 전부 원격 서버에서 돕니다. `vivado`·`vsim`·`riscv-gcc` 는 로컬에 **없습니다.**

### 5.4 문서 검사

```bash
python3 documents/check_docs.py        # 오류 0건이어야 합니다
```

### 5.5 보드 실행 (호스트 PC UART 클라이언트)

```bash
python3 software/host/grover_cli.py --mode 2 --thr 42     # value == 42 인 인덱스
```

* * *

## 6. 개발 현황

**현재 — 문서화 완료. RTL 1차 작성 완료(로컬 iverilog 회귀 통과). Phase 0(툴체인 확보) 착수 전.**

실물 보드는 아직 없습니다. Phase 6까지의 합격 기준은 원격 ModelSim 시뮬레이션과 Vivado 구현 리포트이며, 보드 실행은 입수 후 Phase 7에서 합니다. Task 전문과 합격 기준은 [개발계획.md](documents/design/개발계획.md)에 있습니다.

**Phase 0 — 툴체인 확보와 저장소 뼈대**
- [ ] `software/{golden,soc,host,bench,tools}` 생성
- [ ] `lec_ahb`(AHB 마스터 + APB 슬레이브 — 우리가 따를 패턴)에서 RVX 플랫폼 복제
- [ ] 저장소와 RVX 워크스페이스 연결 방식 확정 (심볼릭 링크, 안 되면 tar 배포)
- [ ] 가상 플랫폼에서 hello world, 이어서 원격 RTL 시뮬에서도
- [ ] `make imp_fpga TARGET_IMP_CLASS=arty-50` → utilization 리포트를 자원 기준선으로 확보
- [ ] UART **수신** 경로(`uart_getc`) 확인 — 호스트 명령 통로
- [ ] 빈 `grover_top` 스텁을 `iverilog -g2012`로 컴파일

**Phase 1 — 골든 모델과 수치 스펙 확정** *(가장 중요)*
- [ ] `grover_float.py` — float64 참조: 술어 4종, BBHT 루프, Born 샘플링
- [ ] `grover_fixed.py` — RTL과 1:1 대응하는 비트정확 고정소수점 모델
- [ ] 비트폭 스윕: f = 8~24 × n ∈ {10,12,14,15} × M ∈ {1,4,64} → 성공률 곡선
- [ ] Q포맷 스윕: {Q1.17, Q2.16} × {half-up, half-even} → 포화 횟수
- [ ] 캐시 스윕: naive 대 전진전용 재개, 직렬 대 병렬 측정
- [ ] n = 8, 10, 12용 RTL 검증 벡터 생성
- [ ] NumPy / Qiskit AerSimulator 기준선 측정
- [ ] M = 0 종료 규칙 확정

**Phase 2 — SoC 껍데기: 더미 IP로 end-to-end 경로 뚫기**
- [ ] RVX mmio 생성기로 CSR 레지스터 파일 생성
- [ ] `grover_soc_user_region.vh` 에 APB 슬레이브 결선
- [ ] RVX 래퍼 — `grover_top.v` 는 `ervp_*.vh` 를 include하지 않아 iverilog 단독 시뮬이 유지되게
- [ ] 더미 `grover_top`: `start` 후 K사이클 뒤 `done`
- [ ] 드라이버 `grover_api.{c,h}` 와 앱 `grover_search/src/main.c` (ASCII 라인 프로토콜)
- [ ] 호스트 `grover_cli.py`

**Phase 3 — 데이터패스 코어 (P = 1, n ≤ 12), 골든 대비 비트정확**
- [ ] `grover_param.vh` — NB, DW, QF, W, P, ACCW, INIT_AMP
- [ ] `grover_predicate.v` — 감산기 하나를 공유하는 술어 4종
- [ ] `grover_lane.v` — 부호 반전 + 확산 (`two_mean − amp`, 포화)
- [ ] `grover_two_mean_calc.v` — `n−1`칸 한 번 시프트 + round-half-to-even
- [ ] `grover_adder_tree.v`, `grover_sum_accum.v`, `grover_ctrl_fsm.v`
- [ ] `grover_amp_mem.v`, `grover_data_mem.v`, `grover_data_gen.v`(xorshift), `grover_verify.v`

**Phase 4 — 병렬화 P = 32 와 측정**
- [ ] 인덱스 하위 `log₂P` 비트 뱅킹
- [ ] 32입력 5단 가산 트리
- [ ] `grover_born_sampler.v` — 2단 병렬 샘플러, 제곱기 32개, 기각 샘플링
- [ ] `grover_lfsr.v`, `grover_iter_rom.v`(30항), `cycle_cnt`·`passes_run` 카운터

**Phase 5 — 재개 캐시와 BBHT 샷 루프** *(본 요구사항)*
- [ ] 5a: 펌웨어 구동 모드 — 앱이 매 샷 절대값 `j_target` 기록
- [ ] 5a: `grover_cache_ctrl.v` 와 술어·임계값·마스크 write 시 하드웨어 자동 무효화
- [ ] 5a: 비트 동일성 증명 — 재개 경로와 새 초기화 경로의 진폭 배열 전수 비교
- [ ] 5b: `grover_shot_fsm.v` — `m` 레지스터·LFSR 추첨·`S_VERIFY` 를 갖춘 바깥 FSM
- [ ] 5b: `ctrl.auto_shot` 한 비트로 두 모드 선택

**Phase 6 — AHB 마스터 데이터 적재와 열거 모드**
- [ ] `grover_ahb_master.v` — `lec_simd.v` 를 본뜬 버스트 마스터
- [ ] `grover_mask_mem.v`, `grover_result_fifo.v`
- [ ] `M_max` 와 `TOO_MANY` 를 갖춘 열거 라운드 루프

**Phase 7 — 구현·평가·문서**
- [ ] 스테이징 구현: n=12/P=8 → n=12/P=32 → **n=15/P=32** @ arty-50
- [ ] 100 MHz 타이밍 클로징
- [ ] 벤치마크: 캐시 on/off, 직렬 대 병렬 측정, BBHT 대 M-known, NumPy/Qiskit 대비
- [ ] n=16 @ arty-100t 구현 리포트
- [ ] 보드 입수 후 실기 브링업

**미정 항목** (9개. 출처는 [16.9절](documents/study_references/16_반복제어와_재개캐시.md#169-아직-정하지-않은-것)과 [17.8절](documents/study_references/17_RVX_SoC_통합.md#178-아직-정하지-않은-것)): M = 0 종료 조건 · `j ~ U[0,m)` 의 균등성(LFSR 마스킹은 균등하지 않음) · 난수 소비 규약 · `m ← min(1.2m, √N)` 의 하드웨어 산술 · CSR 맵이 초안 · 열거 결과 반환 경로 · `M_max` 값 · RVX SoC의 실제 자원 점유 · 100 MHz 달성 가능 여부.

* * *

## 7. 부속 자료

### 문서

**[해설서 (documents/study_references/)](documents/study_references/README.md)** — 양자컴퓨팅 기초부터 이 가속기의 설계 결정까지 0~18장. 양자 알고리즘을 처음 접하는 독자를 대상으로 합니다.

| 파트 | 장 | 내용 |
|---|---|---|
| 이론 | 0~10 | 큐비트 · 게이트 · 측정 · 얽힘 · 오라클 · Grover |
| 뼈대 | 11~12 | 메모리 지도와 자원 예산 · 고정소수점 Q2.16 |
| 데이터패스 | 13~14 | 오라클과 확산 · Born 측정과 열거 |
| 설계 좌표 | 15 | 논문 지도 · **확정 설계 결정표(모든 수치의 단일 출처)** |
| 샷 바깥 | 16~18 | BBHT와 재개 캐시 · RVX SoC 통합 · 골든 모델 검증 |

### 설계 노트

[개발계획.md](documents/design/개발계획.md)(2026-08-15)가 개발 순서와 합격 기준의 현행 정본입니다. `블록도.md` 와 `반복횟수_결정.md` 는 2026-07 기록이라 머리에 현행 스펙을 가리키는 경고가 붙어 있습니다. 발표자료는 [documents/presentation/](documents/presentation/README.md)에 있습니다.

* * *

## 8. 참고문헌

- Grover, L. K. (1996). *A fast quantum mechanical algorithm for database search.* STOC.
- Boyer, M., Brassard, G., Høyer, P., Tapp, A. (1998). *Tight bounds on quantum searching.* Fortschritte der Physik 46(4-5). — BBHT 스케줄의 원전
- Choi, S., Lee, W. (2024). *Developing a Grover's quantum algorithm emulator on standalone FPGAs.* AIMS Mathematics 9(11).
- Choi, S. 외 (2026). *Precision-aware fixed-point emulation of Grover's algorithm.* Quantum Information Processing 25:214.
- Byrnes, T., Forster, G., Tessler, L. (2018). *Generalized Grover's algorithm for multiple phase inversion states.* PRL 120:060501.
- El-Araby, E. 외 (2023). *Towards complete and scalable emulation of quantum algorithms on high-performance reconfigurable computers.* IEEE Trans. Computers 72(8).
- Han, K. 외. *RVX (RISC-V eXpress)* — ETRI SoC Design Research Group.

전체 목록과 인용 시 주의할 오류·모호점은 [15장](documents/study_references/15_논문지도와_설계결정표.md)에 정리되어 있습니다.
