# CLAUDE.md

## project

`<`, `>`, `=`, 범위(`a < x < b`) 네 predicate를 지원하는 **multi-solution Grover search emulator
accelerator**. host 가 UART 로 predicate와 threshold를 보내면 RVX SoC 안의 accelerator 가 계산해
결과 index를 돌려줍니다. board는 Arty A7-100T (`xc7a100tcsg324-1`).

**사용자**: quantum algorithm을 처음 접한 학부생. FPGA 경험은 있으나 설정·RTL 은 자세히 답할 것.

이 file은 **규칙과 길잡이만** 담습니다. 설계 · 수치 · 절차의 source of truth는 기술문서
[`documents/design_references/`](documents/design_references/index.md) 이고, 여기에 같은
내용을 다시 적지 않습니다. 무엇을 찾든 먼저 [기술문서 index](documents/design_references/index.md)를 보십시오.

`documents/` 의 문서는 세 directory로 나눕니다. 같은 내용을 두 곳에 쓰지 말고 한 곳에 쓴 뒤 링크하십시오.

| directory | 무엇 | 입구 |
|---|---|---|
| `study_references/` | 공부용 해설서 | [해설서 index](documents/study_references/index.md) |
| `design_references/` | 확정된 설계와 그 source of truth 수치 | [기술문서 index](documents/design_references/index.md) |
| `reports/` | 설계를 정하거나 확인하려고 돌린 실험. 파일명 `<번호>_<실험명>.md`, 번호는 01 부터 | [실험 보고서 index](documents/reports/index.md) |

실험 보고서는 원자료를 옮겨 적지 않고 evidence bundle(`evidence.md`)을 링크합니다. 설계 문서가 "왜 이렇게
정했나" 를 말할 때는 실험 보고서로 링크합니다. 논문 뼈대는 `documents/study_references/papers/paper_outline.md` 입니다.

---

## 1. 작업 규칙

- 대화는 **한국어 존댓말**. 내부 추론은 영어 무방.
- 문서의 용어는 [22장 22.2절](documents/design_references/22_appendix_glossary_and_retired_specs.md#222-용어)을 따릅니다. 용어는 영어로 쓰고
  한 개념에 하나만 씁니다. project 약자(K · H · E · M 등)와 양을 대신하는 기호는 본문 · 표 · 그림 · 수식 어디에도 쓰지
  않습니다. code identifier · directory 이름 · benchmark 기록 · 이미 낸 tag는 그 시점의 이름 그대로 둡니다.
- code 주석은 **자세히** 달되 이모지 등 AI 티를 내지 말 것.
  - 예외: `documents/study_references/` 해설서 본문의 💡🔍❓⚠️🔑✏️ 표기는 문서 고유 관습이라
    **기존 것만 보존**합니다. 새 콜아웃 박스는 만들지 말고 산문으로 녹이십시오.
- 수식은 채팅에 쓰지 말 것 (terminal에 LaTeX 가 안 보입니다). `.md` 에 쓰고 link만 주십시오.
- GitHub push 허용. 단 **commit 메시지·PR 에 Claude/Anthropic 을 명시하지 말 것**.
- `vivado/` directory(`hardware_dram/vivado/`, `hardware_bram/configurations/*/vivado/`) 아래에는 **Vivado
  project directory만** 두고, 이름은 소문자 `vivado_<프로젝트이름>` 입니다. 그 안에는 **report와
  재현 불가능한 benchmark만** 남깁니다. build·synthesis·simulation log처럼 다시 돌리면 나오는 것은 두지
  않습니다. benchmark 묶음 directory는 `YYYY-MM-DD_<주제>`, 그 안의 file은 소문자 snake_case 로 짧게
  (`result.txt` `summary.csv` `evidence.md`) — directory가 이미 말해 주는 프로젝트명·날짜를
  파일명에 되풀이하지 마십시오. `results/` · `bitstream/` 묶음도 같은 이름 규칙입니다.
- README 는 루트의 `README.md` · `README.ko.md` **둘뿐**입니다. 하위 directory에 README 를
  만들지 말고, 설명이 필요하면 기술문서의 해당 장에 쓰십시오 (새 주제면 장을 더하고
  `index.md` 에 올립니다). 실험 도구의 쓰는 법 · 결과는 그 실험 보고서에 씁니다.
- `.gitignore` 도 루트에 **하나뿐**입니다.
- benchmark 기록(`*.txt` `*.csv` `*.log` `*.rpt`)은 그 시점의 사실이라, directory를 옮겨도 안의 옛 경로를
  고치지 않습니다. `evidence.md` 와 source의 경로는 고칩니다.

---

## 2. source of truth — 무엇을 믿고 무엇을 인용하나

- **board에서 검증된 final configuration (2026-09-07 build) 가 Board-Verified Build입니다.** 그 build의 RTL 17개는 tag
  `board-verified-build-2026-09-07` 의 `hardware_bram/src/` 이고 bitstream과 byte 동일합니다. 대조는
  `sha256_final_rtl.txt`(17개 전부)로 하십시오. 같은 build의 `meta/source_sha256.txt` 는 7개만 적은
  부분 기록이라 그것만 보고 "전부 대조했다" 고 하면 안 됩니다
  ([19장](documents/design_references/19_synthesis_implementation_bitstream.md)).
- main 의 `hardware_bram/src/` 는 그 뒤의 revision 한 벌입니다. Board-Verified Build와의 차이(Bus Interface 교체,
  `gclk_accel`, Dual-Row Build/Two-Level Select switch, 4 PEs 분리)와 각각을 확인한 근거는
  [1장 1.6절](documents/design_references/01_project_overview.md#16-board-verification-이력)과
  [실험 보고서 index 「board benchmark 묶음」](documents/reports/index.md#board-benchmark-묶음)에 있습니다.
- 확정 스펙(14 qubits, Q1.22, 32 lanes, CSR 38개 등)은 [1장 1.2절](documents/design_references/01_project_overview.md#12-확정-spec).
- **CSR 의 source of truth는 [`spec/bbht_grover_csr.json`](spec/bbht_grover_csr.json)
  하나입니다.** `gen_csr.py` 가 Verilog · C · Python header와 기술문서 13장을 만듭니다 — 그 넷은
  손으로 고치지 마십시오(13장 문장은 `gen_csr.py` 의 `gen_doc()` 를 고칩니다). `--check` 가 생성
  대상이 아닌 두 곳(`final_hardware_contract.py`, `bbht_paper_bench/src/main.c`)을 대조하고, RTL 에
  CSR 값을 다시 박는 것을 막습니다.
- **`hardware_bram/firmware/bbht_paper_bench/` 는 한 글자도 고치지 마십시오.** board ELF 를 낸
  source와 sha256 이 같아야 합니다. 그 안의 옛 이름 `CONTROL_K4H8_EQ` · `MODE_K4H8` 도 그대로 둡니다.
  CSR mode 이름에 Checkpoint-Capacity · Lookahead-Shots 값을 넣지 않는 이유는 [13장 13.7절](documents/design_references/13_csr_registers_and_execution_modes.md).

### 성능을 인용할 때

- 세 축 — **RTL cycle / board wall-clock time / ORCA 1 core 대비** — 을 섞지 마십시오. 각 축의 Board-Verified Build
  묶음과 값은 [1장 1.5절](documents/design_references/01_project_overview.md#15-성능-지표와-인용-기준)
  하나에만 있습니다. 성능 세 축은 언제나 2026-09-07 build의 Board-Verified Build에서 인용합니다.
- board cycle과 RTL cycle로 speedup을 만들지 마십시오. BBHT trajectory는 같아도 checkpoint cycle은 직전 실행
  이력에 달려 있습니다. Board-Verified Build는 3,279 cycles, 최신 main a Checkpoint-Capacity of 3 and 3-shot Lookahead는 381 cycles의 memo table 청소를 사용합니다
  ([11장 11.5절](documents/design_references/11_checkpoint_and_policy_engine.md#115-memo-table-initialization-3279--381-cycles)).
  console 한 번의 cycle을 500 runs 표와 맞대지 마십시오. console의 `us=` 는 cycle 환산값이고 wall-clock time
  시간은 `wall_us` 입니다.
- cycle은 RTL 이나 board에서 인용합니다. software reference model은 BBHT trajectory까지만 재현하고 cycle은
  일부러 흉내 내지 않습니다([4장](documents/design_references/04_software_reference_model_and_test_vectors.md)).
- a Checkpoint-Capacity of 4 and 4-shot Lookahead · a Checkpoint-Capacity of 4 and 8-shot Lookahead board 묶음(2026-09-01 · 09-04)은 중간 단계이고 250쌍이라 500 workloads와 총합을
  맞댈 수 없습니다. 2026-10-04 묶음은 같은 board 위 **revision 사이 비교**의 인용처입니다.
- **고전 선형 scan과 속도를 비교하지 않습니다.** 비교 대상은 ORCA 1 core 순수 software baseline ·
  Qiskit AerSimulator · NumPy 셋입니다. ORCA 대비 speedup이 십만 단위인 것은 32 lanes 병렬과 clock 2×
  때문이지 algorithm 우위가 아니라는 단서를 항상 붙이십시오.
- 새 software baseline(`software/orca_grover_develop/`, 200T board ORCA · server x86, 네 predicate 2,000개, 2026-10-11)은
  [실험 19](documents/reports/19_orca_server_software_baseline.md)이 인용처이고 위 세 축과 섞지 않습니다.
  **server 한 core가 FPGA 와 비슷한 시간에 끝난다**는 결과가 있으니 가속 효과를 말할 때 같이 밝히십시오.
  ORCA ① naive 의 전체 시간은 추정값입니다.

**폐기된 값 — 보이면 무시하십시오**: 15 qubits·16 qubits, Q2.16·Q1.17, 8-byte CSR 간격, INCR16 burst,
argmax measurement, AXI4-Lite, MicroBlaze, XC7S100 ([22장](documents/design_references/22_appendix_glossary_and_retired_specs.md)).
`trash_bin/`(git 추적 안 함) 은 전부 이 구 스펙 기준이라 **인용하면 안 됩니다**.

---

## 3. hardware directory tree — 아직 어느 variant도 확정이 아님

iteration 실패 뒤 amplitude 재활용 방식으로 variant가 둘이고, 나중에 하나를 고릅니다. 구조와 configuration 목록의
source of truth는 [5장 5.2절](documents/design_references/05_hardware_architecture_overview.md#hardware-directory-tree와-bram-configuration).

- **`hardware_bram/`** — BRAM Variant. board 실물이 이쪽입니다. 공용 source(`src` `testbench` `sim`
  `synth` `firmware` `rvx` `results`)를 바로 아래에 한 벌 두고, checkpoint · PE 구성마다
  `configurations/<configuration>/` 을 둡니다(열세 개. 이름은 Checkpoint-Capacity · Lookahead-Shots · number of PEs ·
  Measurement Microarchitecture 값을 단어로 적은 것이고 예외는 `final` · `final_200mhz` · `no_checkpoint_baseline` 셋. 목록과
  옛 이름 대응은 [22장 22.2절](documents/design_references/22_appendix_glossary_and_retired_specs.md#222-용어)). configuration directory에는 그
  configuration만의 것 — adapter 하나(Checkpoint-Capacity · Lookahead-Shots · number of PEs · Measurement Microarchitecture 기본값) · `rvx/` · `results/` · `vivado/` · `bitstream/` —
  만 둡니다. 최종 구성은 `final`(RVX platform `bbht_grover_final`), No-Checkpoint Baseline은
  `no_checkpoint_baseline`([20장](documents/design_references/20_no_checkpoint_baseline.md)). 여기에 `final`을
  `clk_accel` 200 MHz 로 맞춘 `final_200mhz`(platform `bbht_grover_final_200mhz`)가 하나 더 있습니다
  ([실험 20](documents/reports/20_200mhz_implementation.md)).
- **`hardware_dram/`** — 모든 `j` 의 amplitude를 DDR3 에 저장하는 variant. configuration directory 없이 한 벌입니다
  ([21장](documents/design_references/21_dram_variant.md)).
- **`spec/`** — register · port 규격(CSR 원본 JSON · `gen_csr.py` · 생성 header · port 표 · 검사기). 두 hardware
  directory tree의 RTL, firmware, host 도구가 함께 쓰므로 어느 directory tree에도 넣지 않고 루트에 둡니다.
- **`software/`** — 두 directory tree가 공유하는 software
  ([4장](documents/design_references/04_software_reference_model_and_test_vectors.md)). 한쪽 variant나 한 configuration에만
  해당하는 것을 넣지 마십시오. 분류는 여덟이고 번호 접두사를 붙이지 않습니다: `reference_model_develop/`(reference model ·
  RTL testbench 자극 생성기 · 비교 실험 · expected result 생성기), `reference_model_data/`(reference model이 낸 solution과 비교 결과),
  `testbench_data/`(testbench · 실험이 읽는 입력), `pc_grover_develop/` · `pc_grover_result/`(C++ · NumPy ·
  Qiskit 과 그 결과), `orca_grover_develop/` · `orca_grover_result/`(accelerator 없는 C, ORCA · x86 공용, 과 그 결과),
  `host_fpga_develop/`(PC 에서 board를 부리는 도구). `_data` · `_result` 안의 묶음은 `YYYY-MM-DD_<내용>` 이고 대표
  문서는 directory와 같은 이름의 `.md` 입니다. 사본을 두지 말고 원본 위치를 읽게 하십시오. `software/orca_grover_develop/` 은 accelerator 없는 software baseline C 세 model과 그 ORCA board ·
  server benchmark 도구입니다([실험 19](documents/reports/19_orca_server_software_baseline.md)). 세 app directory의
  `src/` 는 측정한 source와 sha256 이 같아야 하니 고치지 마십시오(hash는 결과 묶음의 `sha256.txt`).

지킬 것:

- **Accelerator Core를 configuration directory로 복사하지 마십시오.** 모든 configuration이 같은 RTL 을 parameter만 달리 컴파일해야
  configuration 사이 비교가 공정합니다. 예외는 사용자 지시로 만든 `final_200mhz` 하나입니다. register
  경계를 더한 RTL 10개를 configuration `src/` 에 두고 configuration `sim/` · `rvx/` 가 공용 source 위에 덮어씁니다
  ([5장 5.2절](documents/design_references/05_hardware_architecture_overview.md#hardware-directory-tree와-bram-configuration)). 새 configuration은 기존 configuration의 `src/` · `rvx/` 를 복사해 adapter 기본값과
  xml 의 첫 `<name>` 만 바꿉니다. RVX 설치는 공용 `hardware_bram/rvx/install_model.sh` 가 합니다.
- 결과 묶음은 한 configuration 것이면 그 configuration의 `results/`, 여러 configuration을 맞대면 `hardware_bram/results/`.
- file을 새로 둘 때 dram 에 같은 역할의 directory가 있으면 그리로 맞춥니다. testbench는 C++ harness까지
  `testbench/`, 러너와 보고 script는 `sim/` 입니다. `hardware_*/testbench/` 에 Makefile 을 두지
  않습니다.
- `hardware_dram/sim/Makefile` 은 최상위가 둘이라 file을 하나씩 나열합니다 — glob 으로 모으지
  마십시오. `grover_policy_ooc_top.v` · `grover_policy_impl_wrapper.v` 는 OOC 전용이라 synthesis 경로에
  넣지 않습니다. `bbht_bram_top` 과 `bbht_rvx_wrapper` 는 둘 중 하나만 합성합니다.
- tag 안에서는 BRAM Variant directory가 그 시점 배치의 `hardware_bram/` 입니다. tag 안 경로를 말할 때는
  옛 배치를 그대로 씁니다(tag 표는 5장 5.2절). Six-Stage Ablation · Checkpoint-Capacity · Lookahead-Shots 단독 실험의 재현 source도 tag에만
  있습니다.

---

## 4. 명령어

절차 전체와 증상별 대처는 [2장](documents/design_references/02_development_environment_and_toolchain.md),
board는 [17장](documents/design_references/17_board_operation.md), verification 순서는
[16장](documents/design_references/16_verification_framework.md).

```bash
# BRAM Variant. adapter가 들어가는 target은 CONFIGURATION=<configuration> (기본 `final`)
make -C hardware_bram/sim ports lint regress driver      # Bus Interface (몇 초)
make -C hardware_bram/sim real [CONFIGURATION=capacity4_lookahead4_pes4_singlerow_linear]           # + configuration adapter + Accelerator Core (몇 분)
make -C hardware_bram/sim ports-configurations lint-configurations       # configuration adapter 전부
make -C hardware_bram/sim top                            # 최상단 bbht_bram_top (1분 30초쯤)
make -C hardware_bram/sim bench250                       # 250쌍 BBHT trajectory testbench (20분쯤)
make -C hardware_bram/sim predicate500 console-gen       # 네 predicate × 500
make -C hardware_bram/configurations/no_checkpoint_baseline/sim [predicate500 predicate500-ref equiv]
make -C hardware_bram/configurations/final_200mhz/sim [predicate500 predicate500-ref equiv real driver]
hardware_bram/synth/run_main_ip.sh                       # Accelerator Core resource (Vivado, 2분쯤)

# DRAM Variant
make -C hardware_dram/sim && make -C hardware_dram/sim equiv
make -C hardware_dram/sim predicate500 [AXI_STALL=1]

# 계약 · 문서 (문서를 고쳤으면 check_docs 오류 0건이어야 합니다)
python3 spec/gen_csr.py [--check]
python3 documents/check_docs.py

# RVX: configuration마다 rvx/install_to_platform.sh 가 자기 platform에 설치
source /opt/rvx/rvx_setup.sh
hardware_bram/configurations/final/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_final && make syn && make sim_rtl

# board · host
python3 software/host_fpga_develop/bbht_predicate500.py --port /dev/ttyUSB1
python3 software/host_fpga_develop/bbht_cli.py --port mock selftest
```

함정 셋 (자세한 이유는 2장):

- 저장소 경로에 공백이 있을 수 있어 `sim/Makefile` 이 verilator build를 `--Mdir /tmp/...` 로
  뺍니다. 건드리지 마십시오.
- RVX SoC simulation에서 `bbht_console` 은 `rvx_each.mh` 가 RTL simulation build에만 script mode를 켭니다.
  **명령줄로 `DEFINE_CFLAGS` 를 넘기지 마십시오.** simulation 뒤 `sim_rtl/rvx_app_build.log` 에
  `BBHT_CONSOLE_SCRIPT` 가 있는지 보십시오.
- 헤드리스라 `gtkwave` 와 Vivado GUI 는 못 띄웁니다. Vivado 는 `-mode batch` 전용입니다.

---

## 5. 문서를 고쳤을 때 같이 확인할 곳

기술문서 작성 규칙: 한 수치는 한 장에만 적고 다른 장은 링크합니다. 장 머리에
`← 이전 · index · 다음 →` 줄. 본문에 LaTeX · mermaid fence 를 쓰지 않습니다(그림은
`diagrams/` 의 SVG, `design_references/diagrams/` 가 유일한 하위 directory). 장을 더하거나 번호를 바꾸면
모든 장의 머리 줄과 `index.md` 를 같이 고칩니다. 세 directory 모두 입구는 번호 없는 `index.md` 이고 번호 붙은
file은 01 부터입니다. 파일 이름은 번호 + 영어 snake_case 입니다. 해설서(`study_references/`)는 **장 번호가 동결**입니다(옛 0장은 `index.md`). `study_references/papers/` 의 원문 · 해설본은 읽기 전용입니다(`paper_outline.md` 는
우리 논문 뼈대라 고칩니다). 실험 보고서(`reports/`)도 같은 규칙이고, 머리 줄은
`← 이전 실험 · index · 다음 실험 →`, 맨 앞에 정한 것(확인한 것)과 근거의 축을 적는 표를 둡니다.

`check_docs.py` 는 죽은 link · 없는 앵커 · 없는 그림 · 고아 그림 · 렌더 안 된 `.mmd` · 되살아난
폐기 스펙 · 본문 mermaid fence 를 잡습니다. 다음은 **기계가 못 잡으니 사람이** 봅니다.

- 인용한 주장이 대상 절에 실제로 있는가
- 뒤 장에서 정의되는 용어를 앞 장이 설명 없이 쓰지 않는가
- 폐기된 주장이 표현만 바꿔 살아 있지 않은가 ("가장 큰 amplitude를 고른다" = argmax,
  "solution index의 amplitude를 뒤집는다" = oracle이 solution을 안다)
- benchmark 수치에 조건이 붙어 있는가

| 무엇을 고쳤나 | 같이 볼 곳 |
|---|---|
| 설계 수치 | CSR 이면 JSON 을 고치고 `gen_csr.py` → 1장 1.2절 → `README*.md` 2절 → 해설서 [15.4절](documents/study_references/15_paper_map_and_design_decisions.md#154-우리-project의-좌표--확정-설계-결정표) |
| 성능·resource 수치 | 어느 축인지부터 → 해당 evidence bundle의 `evidence.md` → 1장 1.5절 → `README*.md` |
| port | 기술문서 12장과 RTL 을 같이. `make -C hardware_bram/sim ports ports-real ports-configurations` |
| configuration 추가·parameter | 5장 5.2절 configuration 표 → `README*.md` 3절 |
| 절 제목·절 번호 | 그 장으로 들어오는 모든 link. 앵커가 밀립니다 |
| 실험 추가 | `reports/` 에 다음 번호로 `<번호>_<실험명>.md` → `index.md` 목록 → 앞뒤 실험의 머리 줄 → 그 실험으로 정한 설계 장에서 link |
| directory 구조 | 이 file 3절 · `README.md`/`README.ko.md` 4절 · 기술문서 5장 5.2절과 17장 |
| diagram | `.mmd` 를 고쳤으면 `render_diagrams.py` 실행 |
