# CLAUDE.md

## 0. 프로젝트

**주제 (2026-07-28 확정)**: `<`, `>`, `=`, 범위(`a < x < b`) 네 가지 술어를 지원하는 **다중 타겟 Grover 탐색 에뮬레이터 가속기**. 온칩 BRAM에 담긴 데이터 배열 `value[i]` 중 술어를 만족하는 인덱스를 찾아, 하나를 반환하거나 반복 호출로 전부 열거합니다.

**최종 형태**: 호스트 PC가 UART로 술어와 임계값을 보내면, RVX SoC 안의 커스텀 IP가 계산해 결과 인덱스를 돌려줍니다. 특수 IP만 직접 설계하고 나머지 주변 회로(CPU·버스·UART·SRAM)는 RVX가 생성합니다.

**핵심 기여**: 검증에 실패한 샷의 진폭 배열을 버리지 않고 **차이만큼만 이어 돌리는 재개 캐시**. 추가 BRAM 0개로 약 35%를 절감하며(n=15·M=1·몬테카를로 20,000회. M이 커지면 완만히 낮아져 M=256에서 29%), 결과는 새로 초기화해서 돌린 것과 비트 단위로 동일합니다.

**사용자**: 양자 알고리즘을 처음 접한 학부생. FPGA 사용 경험은 있으나 **설정·RTL 관련은 자세히 답할 것.**

## 1. 작업 규칙

- 대화는 **한국어 존댓말**로. (내부 추론은 영어로 해도 무방)
- 코드 주석은 **자세히** 달되 이모지 사용 등 AI티를 내지 말 것.
  - 단, `documents/study_references/` 해설서 본문의 💡🔍❓⚠️🔑✏️ 표기는 **문서 고유의 기존 관습**이므로 유지합니다. 이모지 금지는 코드 주석에 대한 규칙입니다.
  - 해설서에 **새 콜아웃 박스를 만들지 마십시오.** 보충 설명은 흐르는 산문으로 기존 문단에 녹입니다.
- 수식은 채팅에 쓰지 말 것 (터미널에서 LaTeX가 보이지 않습니다). `.md` 파일에 쓰고 링크만 주십시오.
- GitHub push 허용. 단 **커밋 메시지·PR에 Claude/Anthropic을 명시하지 말 것** (`Co-Authored-By`, "Generated with" 류 일절 금지).

## 2. 저장소 구조

| 경로 | 성격 |
|---|---|
| `hardware/src/` | RTL 본체 (Verilog). 파라미터 헤더 `grover_param.vh` 포함 |
| `hardware/testbench/` | 테스트벤치. iverilog 회귀의 진입점 |
| `hardware/sim/` | verilator 하네스 |
| `software/` | 골든 모델(Python), RVX 플랫폼·앱·드라이버, 호스트 CLI, 벤치마크 |
| `documents/study_references/` | **주교재.** 0~18장 해설서 + 부록 A. 대상은 사람(학부생) |
| `documents/design/개발계획.md` | **현행 정본.** 개발 순서·Phase별 Task·합격 기준 (2026-08-15) |
| `documents/design/블록도.md` · `반복횟수_결정.md` | 2026-07 결정 기록. **구 스펙이 남아 있어 머리의 경고 블록을 먼저 읽을 것** |
| `documents/check_docs.py` | 문서 정합성 검사기. 문서를 고친 뒤 **반드시 돌릴 것** (6절) |
| `documents/presentation/` | 발표자료. 이름 규칙 `YYYY-MM-DD_<종류>_<주제>` |
| `documents/papers/` | 원문 논문·강의자료 PDF. **읽기 전용 참고자료** |
| `documents/papers_ko/` | 논문 6편의 한국어 해설본. 원문 대조용 **보조** 자료 |

`hardware/`·`software/` 는 아직 비어 있습니다. 이전에 있던 `project1/`(학습용 RTL 스케치)은 **삭제되었습니다** — 해설서에서 인용하지 마십시오.

## 3. 확정 설계 — 숫자의 단일 출처

**모든 수치의 정본은 [해설서 15.4절](documents/study_references/15_논문지도와_설계결정표.md#154-우리-프로젝트의-좌표--확정-설계-결정표)입니다.** 아래는 자주 쓰는 값의 요약이며, 어긋나면 15.4가 이깁니다.

| 항목 | 값 |
|---|---|
| 보드 | Arty-S7-50 (`xc7s50csga324-1`). BRAM36 75개 / DSP 120개. **실물은 아직 없음 — 나중에 생길 예정** |
| 목표 큐비트 | n = 15 (N = 32,768) |
| 진폭 | 실수 전용 고정소수점 **18비트 Q2.16**, round-half-to-even, 포화, 재정규화 없음 |
| 데이터 워드 | 16비트 signed |
| 병렬도 | P = 32 레인. 인덱스 하위 5비트로 뱅크 선택 |
| 반복 1회 | 2패스 = 2N/P = **2,048 사이클** |
| 메모리 | amp 16 + data 16 + mask 1 = **BRAM36 33개**, SoC 포함 ~48/75 |
| 곱셈기 | 확산·오라클·INIT 경로 **0개**. 측정 경로만 제곱기 32개(DSP 32/120) |
| 측정 | **Born 확률 샘플링** 2단 병렬. argmax가 **아님** |
| 반복 횟수 | **BBHT** 기본(M을 모른다고 가정). 평균 24.5샷 (n=15·M=1·몬테카를로 20,000회) |
| SoC | RVX `rvc_orca` RV32 + **APB 슬레이브(CSR) + AHB 마스터(DMA)**. 호스트는 UART |
| 샷 루프 | **두 모드 공존.** BBHT 자율 모드(하드웨어 바깥 FSM)가 최종 형태, 펌웨어 구동 모드(앱이 절대값 `j_target` 기록)는 캐시 검증·M-known 비교·골든 대조용으로 영구 유지. 개발 순서 **Phase 5a(펌웨어) → 5b(하드웨어)**. `j_cur`·`cache_valid` 는 어느 쪽이든 하드웨어 소유 |

**폐기된 값 — 옛 문서에서 보이면 무시하십시오**: XC7S100, n=16 목표, Q1.17, argmax 측정, 직렬 CDF 측정, AXI4-Lite CSR, AXI-Stream `data_loader`, MicroBlaze, "검증 실패 시 초기화부터 통째로 다시".

**아직 미정 — 9개** (억지로 채우지 말 것). 정본은 [16.9절](documents/study_references/16_반복제어와_재개캐시.md#169-아직-정하지-않은-것)(4개)과 [17.8절](documents/study_references/17_RVX_SoC_통합.md#178-아직-정하지-않은-것)(5개)입니다.

1. (16.9) M=0 종료 조건 — BBHT 상한 도달로 선언할지, 고전 스캔 1패스로 확정할지
2. (16.9) `j ~ U[0,m)` 의 균등성 — LFSR 마스킹은 균등하지 않음. 기각 샘플링 등 규약 필요
3. (16.9) 난수 소비 규약 — LFSR 다항식·시드·샷당 추출 횟수·범위 매핑. 어긋나면 bit-exact가 영원히 안 맞음
4. (16.9) `m ← min(1.2m, √N)` 의 하드웨어 산술
5. (17.8) **CSR 맵 전체가 초안** — RVX mmio 생성기 입력 XML 스키마부터 확인 필요
6. (17.8) 열거 결과 반환 경로 — `result_fifo` 를 둘지, 호스트가 M번 호출할지
7. (17.8) `M_max` 값 (예시 256, 확정 아님)
8. (17.8) RVX SoC의 실제 자원 점유 — Phase 0의 `make imp_fpga` 리포트로 실측
9. (17.8) **클럭이 정말 100 MHz인가** — RVX 기본 생성물은 `SYSTEM_CLK_HZ = 50,000,000`. 100 MHz는 요구해야 얻는 값

## 4. 명령어

### 시뮬레이션 (로컬)

```bash
make -C hardware/testbench regress        # iverilog + vvp 회귀
```

**이 환경의 툴체인**: `iverilog`, `vvp`, `verilator`, `gtkwave` 사용 가능. **`vivado`·`vsim`·`riscv-gcc` 는 없습니다.**

### RVX (원격 빌드)

```bash
source /home/coder/rvx_lec_hw/rvx_setup.sh
cd $RVX_MINI_HOME/platform/<플랫폼>
make syn && make sim_rtl                  # 원격 ModelSim
make imp_fpga TARGET_IMP_CLASS=arty-50    # 원격 Vivado
```

RVX Mini(씬 클라이언트) 판이라 생성·시뮬·합성이 전부 **원격 서버(`cau01.rvx.coreicc.net`)** 에서 돕니다. 로컬 폴백이 없으므로 접속이 막히면 RTL 시뮬과 합성이 통째로 멈춥니다. 참고할 예제는 `platform/lec_apb/`(APB 슬레이브 최소 구성)와 `platform/lec_ahb/`(AHB 마스터 + APB 슬레이브 가속기 — **우리가 따를 패턴**)입니다.

### 해설서 다이어그램

```bash
cd documents/study_references
python3 render_diagrams.py           # src/*.mmd → diagrams/*.svg
python3 render_diagrams.py --force   # 캐시 무시 재렌더
```

## 5. 해설서 작성 규칙

- 본문은 다이어그램을 `<img src="diagrams/<name>.svg">` 로 참조합니다. **mermaid fence를 본문에 직접 쓰지 않습니다** — 어느 뷰어에서든 보이게 하려는 의도입니다.
- mermaid 소스는 `diagrams/src/*.mmd` 에 보존됩니다. mermaid로 표현이 안 되는 그림(진폭 막대그래프, 기하학적 회전, 타임라인, 예산 막대)은 **손으로 작성한 SVG를 `diagrams/` 에 직접** 둡니다 — 대응하는 `.mmd` 가 없으며 `render_diagrams.py` 가 건드리지 않습니다.
- 각 장은 개념이 앞에서 뒤로 단조롭게 쌓이도록 배치되어 있습니다. 장 시작부의 "이 장을 읽기 위한 준비" 링크와 장 간 상호 링크를 깨뜨리지 마세요. **파일명과 장 번호는 동결**입니다(13·14장은 제목만 바뀌었고 파일명은 그대로).
- 수식은 LaTeX(`$...$`, `$$...$$`), 상태는 켓(`$|\psi\rangle$`) 표기.
- 실측 수치에는 **조건을 병기**하십시오 — "평균 24.5샷(n=15·M=1·몬테카를로 20,000회)" 식으로. 조건 없이 인용하면 나중에 어긋납니다.
- **고전 선형 스캔과 속도를 비교하지 않습니다.** √N 이득은 실기 양자의 이야기이고 에뮬레이션은 O(N·√(N/M))이라 고전 스캔보다 느립니다. 비교 대상은 Qiskit AerSimulator / NumPy 상태벡터 시뮬레이터입니다.

## 6. 문서 정합성 — 무엇을 고치면 무엇을 확인해야 하는가

문서가 서로를 촘촘히 참조하고 있어서, 한 곳을 고치면 다른 곳이 조용히 어긋납니다.
**문서를 건드린 뒤에는 반드시 검사기를 돌리십시오.**

```bash
python3 documents/check_docs.py        # 오류 0건이어야 합니다 (종료 코드 0)
python3 documents/check_docs.py -v     # 통계까지
```

검사기가 잡는 것: 죽은 링크 · 없는 절 앵커 · 없는 그림 · 고아 그림 · 렌더 안 된 `.mmd` ·
되살아난 폐기 스펙 · 확정 수치와 다른 값 · 장 구조(요약 절·준비 링크) · 본문 mermaid fence.

### 6.1 정본은 하나뿐입니다

| 무엇 | 정본 | 나머지 문서의 역할 |
|---|---|---|
| 설계 수치 전부 | **[15.4절 확정 설계 결정표](documents/study_references/15_논문지도와_설계결정표.md#154-우리-프로젝트의-좌표--확정-설계-결정표)** | 값을 적되 15.4를 정본으로 표시 |
| 플랫폼·자원 예산 | [15.5절](documents/study_references/15_논문지도와_설계결정표.md#155-확정-플랫폼과-자원-예산) | 〃 |
| 미정 항목 | [16.9절](documents/study_references/16_반복제어와_재개캐시.md#169-아직-정하지-않은-것) · [17.8절](documents/study_references/17_RVX_SoC_통합.md#178-아직-정하지-않은-것) | 〃 |
| 개발 순서·검증 기준 | [개발계획.md](documents/design/개발계획.md) | — |

`documents/design/블록도.md` 와 `반복횟수_결정.md` 는 **2026-07 시점 기록**입니다. 본문에 낡은
수치(NB=16, Q1.17, AXI, BRAM36 32개)가 남아 있는 것이 정상이고, 머리의 경고 블록이 독자를 15.4로
보냅니다. **이 두 문서의 본문 수치를 현행으로 고치지 마십시오** — 결정 이력이 사라집니다.

### 6.2 고친 곳별 확인 목록

| 무엇을 고쳤나 | 반드시 같이 확인할 곳 |
|---|---|
| **설계 수치 하나라도** (비트폭·자원·사이클·샷 수·절감률) | 15.4 · 15.5 → `CLAUDE.md` 3절 → 저장소 `README.md` 2·3절 → 해당 장 본문 → `documents/presentation/README.md` 의 "현행 대비" 표 |
| **절 제목** | 그 장으로 들어오는 모든 링크. 앵커가 바뀝니다 — `check_docs.py` 가 잡습니다 |
| **절 번호(절 추가·삭제)** | 뒤따르는 모든 절 번호가 밀립니다. 다른 장이 `#4.7` 로 걸어 둔 링크가 조용히 딴 절을 가리키게 됩니다. **실제로 4장에 절을 추가했을 때 7장·14장 링크가 이렇게 깨졌습니다** |
| **장 제목** | `study_references/README.md` 목차 · `10.9절` 다음 단계 · 저장소 `README.md` 7절 표 |
| **파일명** | **동결입니다.** 13·14장은 제목만 바뀌었고 파일명은 그대로 둔 이유가 이것입니다(13장으로 25곳, 15장으로 12곳, 3장으로 41곳이 들어옵니다) |
| **다이어그램** | `.mmd` 를 고쳤으면 `python3 documents/study_references/render_diagrams.py` · 손 SVG 를 고쳤으면 그대로 · 그림을 없앴으면 `<img>` 참조도 |
| **디렉터리 구조** | `CLAUDE.md` 2절 · 저장소 `README.md` 4절 · `개발계획.md` §5 트리 |
| **미정 항목이 결정됨** | 16.9 또는 17.8 에서 빼고 → 15.4 에 넣고 → `CLAUDE.md` 3절 "아직 미정" 에서 빼기 |
| **발표자료 추가** | `documents/presentation/README.md` 색인 표 · 이름 규칙 `YYYY-MM-DD_<종류>_<주제>` |

### 6.3 검사기가 못 잡는 것 — 사람이 봐야 합니다

기계는 링크가 **존재하는지**만 압니다. 다음은 직접 읽어 확인하십시오.

- **인용한 주장이 대상 절에 실제로 있는가.** 예: 14.3절이 "9.4절에서 두 막대가 나란히 **자란다**"고
  썼는데 9.4절의 $N=4$·$M=2$ 는 확률이 제자리인 퇴화 사례였습니다. 앵커는 멀쩡했고 내용만 틀렸습니다.
- **선수 개념 역전.** 뒤 장에서 정의되는 용어를 앞 장이 설명 없이 쓰는 것. 12장이 뱅크·2단 측정을
  앞질러 쓰지 않는지, 0장이 `data_mem`·`mask_mem` 을 정의 없이 쓰지 않는지.
- **폐기된 주장이 표현만 바꿔 살아 있는 곳.** "가장 큰 진폭을 고르면 된다"(= argmax),
  "정답 인덱스의 진폭을 뒤집는다"(= 오라클이 정답을 안다), "재시도할 때 처음부터 다시"(= 캐시 부정).
- **실측 수치의 조건 누락.** "평균 24.5샷"은 n=15·M=1·몬테카를로 20,000회 조건입니다.
  조건 없이 인용하면 n=16 수치(26.5샷)와 뒤섞입니다.
- **새 콜아웃 박스.** 💡🔍❓⚠️🔑✏️ 는 기존 것만 보존하고 **새로 만들지 않습니다.**
  개편 전 원본과 개수를 대조하십시오.

### 6.4 개편 이력

2026-08-15 에 해설서를 전면 개편했습니다. 그 전 원본은 git 이전 커밋에 있습니다.
주요 변경: 측정 argmax → **Born 2단 병렬** / Q1.17 → **Q2.16** / 최솟값 탐색 주제 → **확장으로 강등** /
16·17·18장 신설(재개 캐시 · RVX SoC · 골든 모델 검증) / Part 5~8 재편 / `project1/` 인용 전면 제거.

---

# 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
