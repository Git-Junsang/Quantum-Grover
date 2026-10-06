# CLAUDE.md

## 프로젝트

`<`, `>`, `=`, 범위(`a < x < b`) 네 술어를 지원하는 **다중 타겟 Grover 탐색 에뮬레이터
가속기**. 호스트 PC 가 UART 로 술어와 임계값을 보내면 RVX SoC 안의 커스텀 IP 가 계산해
결과 인덱스를 돌려줍니다. 보드는 Arty A7-100T (`xc7a100tcsg324-1`).

**사용자**: 양자 알고리즘을 처음 접한 학부생. FPGA 경험은 있으나 설정·RTL 은 자세히 답할 것.

이 파일은 **규칙과 길잡이만** 담습니다. 설계 · 수치 · 절차의 정본은 기술문서
[`documents/design_references/`](documents/design_references/00_문서_지도.md) 이고, 여기에 같은
내용을 다시 적지 않습니다. 무엇을 찾든 먼저 [문서 지도](documents/design_references/00_문서_지도.md)를 보십시오.

---

## 1. 작업 규칙

- 대화는 **한국어 존댓말**. 내부 추론은 영어 무방.
- 코드 주석은 **자세히** 달되 이모지 등 AI 티를 내지 말 것.
  - 예외: `documents/study_references/` 해설서 본문의 💡🔍❓⚠️🔑✏️ 표기는 문서 고유 관습이라
    **기존 것만 보존**합니다. 새 콜아웃 박스는 만들지 말고 산문으로 녹이십시오.
- 수식은 채팅에 쓰지 말 것 (터미널에 LaTeX 가 안 보입니다). `.md` 에 쓰고 링크만 주십시오.
- GitHub push 허용. 단 **커밋 메시지·PR 에 Claude/Anthropic 을 명시하지 말 것**.
- `vivado/` 폴더(`hardware_dram/vivado/`, `hardware_bram/models/*/vivado/`) 아래에는 **Vivado
  프로젝트 폴더만** 두고, 이름은 소문자 `vivado_<프로젝트이름>` 입니다. 그 안에는 **리포트와
  재현 불가능한 실측만** 남깁니다. 빌드·합성·시뮬 로그처럼 다시 돌리면 나오는 것은 두지
  않습니다. 실측 묶음 폴더는 `YYYY-MM-DD_<주제>`, 그 안의 파일은 소문자 snake_case 로 짧게
  (`result.txt` `summary.csv` `evidence.md`) — 폴더가 이미 말해 주는 프로젝트명·날짜를
  파일명에 되풀이하지 마십시오. `results/` · `bitstream/` 묶음도 같은 이름 규칙입니다.
- README 는 루트의 `README.md` · `README.ko.md` **둘뿐**입니다. 하위 폴더에 README 를
  만들지 말고, 설명이 필요하면 기술문서의 해당 장에 쓰십시오 (새 주제면 장을 더하고
  `00_문서_지도.md` 에 올립니다).
- `.gitignore` 도 루트에 **하나뿐**입니다.
- 측정 기록(`*.txt` `*.csv` `*.log` `*.rpt`)은 그 시점의 사실이라, 폴더를 옮겨도 안의 옛 경로를
  고치지 않습니다. `evidence.md` 와 소스의 경로는 고칩니다.

---

## 2. 정본 — 무엇을 믿고 무엇을 인용하나

- **보드에서 검증된 K3/H3-E4-M2 (2026-09-07 빌드) 가 정본입니다.** 그 빌드의 RTL 17개는 태그
  `board-k3h3-e4-m2` 의 `hardware_bram/src/` 이고 비트스트림과 바이트 동일합니다. 대조는
  `sha256_final_rtl.txt`(17개 전부)로 하십시오. 같은 빌드의 `meta/source_sha256.txt` 는 7개만 적은
  부분 기록이라 그것만 보고 "전부 대조했다" 고 하면 안 됩니다
  ([20장](documents/design_references/20_합성_구현_비트스트림.md)).
- main 의 `hardware_bram/src/` 는 그 뒤의 최신판 한 벌입니다. 보드 정본과의 차이(통신 계층 교체,
  `gclk_accel`, M1/M2 스위치, E4 분리)와 각각을 확인한 근거는
  [1장 1.6절](documents/design_references/01_프로젝트_개요.md#16-보드-검증-이력)과
  [18장](documents/design_references/18_보드_확인과_실측.md)에 있습니다.
- 확정 스펙(Q=14, Q1.22, P=32, CSR 38개 등)은 [1장 1.2절](documents/design_references/01_프로젝트_개요.md#12-확정-스펙).
- **CSR 의 정본은 [`software/contract/bbht_grover_csr.json`](software/contract/bbht_grover_csr.json)
  하나입니다.** `gen_csr.py` 가 Verilog · C · 파이썬 헤더와 기술문서 13장을 만듭니다 — 그 넷은
  손으로 고치지 마십시오(13장 문장은 `gen_csr.py` 의 `gen_doc()` 를 고칩니다). `--check` 가 생성
  대상이 아닌 두 곳(`final_hardware_contract.py`, `bbht_paper_bench/src/main.c`)을 대조하고, RTL 에
  CSR 값을 다시 박는 것을 막습니다.
- **`hardware_bram/firmware/bbht_paper_bench/` 는 한 글자도 고치지 마십시오.** 보드 ELF 를 낸
  소스와 sha256 이 같아야 합니다. 그 안의 옛 이름 `CONTROL_K4H8_EQ` · `MODE_K4H8` 도 그대로 둡니다.
  CSR 모드 이름에 K · H 를 넣지 않는 이유는 [13장 13.7절](documents/design_references/13_CSR_레지스터와_실행_모드.md).

### 성능을 인용할 때

- 세 축 — **RTL 사이클 / 보드 실경과 시간 / ORCA 1코어 대비** — 을 섞지 마십시오. 각 축의 정본
  묶음과 값은 [1장 1.5절](documents/design_references/01_프로젝트_개요.md#15-성능-지표와-인용-기준)
  하나에만 있습니다. 성능 세 축은 언제나 2026-09-07 빌드의 보드 정본에서 인용합니다.
- 보드 사이클과 RTL 사이클로 배수를 만들지 마십시오. 궤적은 같아도 체크포인트 사이클은 직전 실행
  이력에 달려 있습니다(3,279 사이클, [11장 11.5절](documents/design_references/11_체크포인트와_정책_엔진.md#115-memo와-3279-사이클)).
  콘솔 한 번의 사이클을 500런 표와 맞대지 마십시오. 콘솔의 `us=` 는 사이클 환산값이고 실경과
  시간은 `wall_us` 입니다.
- 사이클은 RTL 이나 보드에서 인용합니다. 소프트웨어 기준모델은 궤적까지만 재현하고 사이클은
  일부러 흉내 내지 않습니다([4장](documents/design_references/04_소프트웨어_기준모델과_정답_벡터.md)).
- K4/H4 · K4/H8 보드 묶음(2026-09-01 · 09-04)은 중간 단계이고 250쌍이라 500 워크로드와 총합을
  맞댈 수 없습니다. 2026-10-04 묶음은 같은 보드 위 **판 사이 비교**의 인용처입니다.
- **고전 선형 스캔과 속도를 비교하지 않습니다.** 비교 대상은 ORCA 1코어 순수 SW 기준선 ·
  Qiskit AerSimulator · NumPy 셋입니다. ORCA 대비 배수가 십만 단위인 것은 P=32 병렬과 클럭 2배
  때문이지 알고리즘 우위가 아니라는 단서를 항상 붙이십시오.

**폐기된 값 — 보이면 무시하십시오**: n=15·n=16, Q2.16·Q1.17, 8바이트 CSR 간격, INCR16 버스트,
argmax 측정, AXI4-Lite, MicroBlaze, XC7S100 ([24장](documents/design_references/24_부록_용어집과_폐기된_규격.md)).
`trash_bin/`(git 추적 안 함) 은 전부 이 구 스펙 기준이라 **인용하면 안 됩니다**.

---

## 3. 하드웨어 트리 — 아직 어느 갈래도 확정이 아님

반복 실패 뒤 진폭 재활용 방식으로 갈래가 둘이고, 나중에 하나를 고릅니다. 구조와 모델 목록의
정본은 [5장 5.2절](documents/design_references/05_하드웨어_아키텍처_개요.md#하드웨어-트리와-bram-모델).

- **`hardware_bram/`** — BRAM 갈래. 보드 실물이 이쪽입니다. 공용 소스(`src` `testbench` `sim`
  `synth` `firmware` `rvx` `results`)를 바로 아래에 한 벌 두고, 체크포인트 · 연산기 구성마다
  `models/hardware_bram_<모델>/` 을 둡니다(열 개: `Normal_E1` `K4H8_E1` `K4H4_E1` `K3H4_E1`
  `K3H3_E1` `K4H4_E4` `K3H3_E4` `K3H3_E4_M1` `K3H3_E4_M2` `nocheckpoint`). 모델 폴더에는 그
  모델만의 것 — 어댑터 하나(K·H·E·M 기본값) · `rvx/` · `results/` · `vivado/` · `bitstream/` —
  만 둡니다. 최종 구성은 `K3H3_E4_M2`(RVX 플랫폼 `bbht_grover_upgrade`), 비교 기준 판은
  `nocheckpoint`([21장](documents/design_references/21_체크포인트_없는_BRAM_판.md)).
- **`hardware_dram/`** — 모든 `j` 의 진폭을 DDR3 에 저장하는 갈래. 모델 폴더 없이 한 벌입니다
  ([22장](documents/design_references/22_DRAM_갈래.md)).
- **`software/`** — 두 트리가 공유하는 기준모델 · 검증 벡터 · 계약 · 호스트 도구
  ([4장](documents/design_references/04_소프트웨어_기준모델과_정답_벡터.md)). 한쪽 갈래나 한 모델에만
  해당하는 것을 넣지 마십시오.

지킬 것:

- **Main IP 를 모델 폴더로 복사하지 마십시오.** 모든 모델이 같은 RTL 을 파라미터만 달리 컴파일해야
  모델 사이 비교가 공정합니다. 새 모델은 기존 모델의 `src/` · `rvx/` 를 복사해 어댑터 기본값과
  xml 의 첫 `<name>` 만 바꿉니다. RVX 설치는 공용 `hardware_bram/rvx/install_model.sh` 가 합니다.
- 결과 묶음은 한 모델 것이면 그 모델의 `results/`, 여러 모델을 맞대면 `hardware_bram/results/`.
- 파일을 새로 둘 때 dram 에 같은 역할의 폴더가 있으면 그리로 맞춥니다. 테스트벤치는 C++ 하네스까지
  `testbench/`, 러너와 보고 스크립트는 `sim/` 입니다. `hardware_*/testbench/` 에 Makefile 을 두지
  않습니다.
- `hardware_dram/sim/Makefile` 은 최상위가 둘이라 파일을 하나씩 나열합니다 — glob 으로 모으지
  마십시오. `grover_policy_ooc_top.v` · `grover_policy_impl_wrapper.v` 는 OOC 전용이라 합성 경로에
  넣지 않습니다. `bbht_bram_top` 과 `bbht_rvx_wrapper` 는 둘 중 하나만 합성합니다.
- 태그 안에서는 BRAM 갈래 폴더가 그 시점 배치의 `hardware_bram/` 입니다. 태그 안 경로를 말할 때는
  옛 배치를 그대로 씁니다(태그 표는 5장 5.2절). 6단계 ablation · K/H 단독 실험의 재현 소스도 태그에만
  있습니다.

---

## 4. 명령어

절차 전체와 증상별 대처는 [2장](documents/design_references/02_개발_환경과_툴체인.md),
보드는 [17장](documents/design_references/17_보드_운용.md), 검증 순서는
[16장](documents/design_references/16_검증_체계.md).

```bash
# BRAM 갈래. 어댑터가 들어가는 타깃은 MODEL=<모델> (기본 K3H3_E4_M2)
make -C hardware_bram/sim ports lint regress driver      # 통신 계층 (몇 초)
make -C hardware_bram/sim real [MODEL=K4H4_E4]           # + 모델 어댑터 + Main IP (몇 분)
make -C hardware_bram/sim ports-models lint-models       # 모델 열 개 전부
make -C hardware_bram/sim top                            # 최상단 bbht_bram_top (1분 30초쯤)
make -C hardware_bram/sim bench250                       # 250쌍 궤적 벤치 (20분쯤)
make -C hardware_bram/sim predicate500 console-gen       # 네 술어 x 500
make -C hardware_bram/models/hardware_bram_nocheckpoint/sim [predicate500 predicate500-ref equiv]
hardware_bram/synth/run_main_ip.sh                       # Main IP 자원 (Vivado, 2분쯤)

# DRAM 갈래
make -C hardware_dram/sim && make -C hardware_dram/sim equiv
make -C hardware_dram/sim predicate500 [AXI_STALL=1]

# 계약 · 문서 (문서를 고쳤으면 check_docs 오류 0건이어야 합니다)
python3 software/contract/gen_csr.py [--check]
python3 documents/check_docs.py

# RVX: 모델마다 rvx/install_to_platform.sh 가 자기 플랫폼에 설치
source /opt/rvx/rvx_setup.sh
hardware_bram/models/hardware_bram_K3H3_E4_M2/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_upgrade && make syn && make sim_rtl

# 보드 · 호스트
python3 software/host/bbht_predicate500.py --port /dev/ttyUSB1
python3 software/host/bbht_cli.py --port mock selftest
```

함정 셋 (자세한 이유는 2장):

- 저장소 경로에 공백이 있을 수 있어 `sim/Makefile` 이 verilator 빌드를 `--Mdir /tmp/...` 로
  뺍니다. 건드리지 마십시오.
- RVX SoC 시뮬에서 `bbht_console` 은 `rvx_each.mh` 가 RTL 시뮬 빌드에만 스크립트 모드를 켭니다.
  **명령줄로 `DEFINE_CFLAGS` 를 넘기지 마십시오.** 시뮬 뒤 `sim_rtl/rvx_app_build.log` 에
  `BBHT_CONSOLE_SCRIPT` 가 있는지 보십시오.
- 헤드리스라 `gtkwave` 와 Vivado GUI 는 못 띄웁니다. Vivado 는 `-mode batch` 전용입니다.

---

## 5. 문서를 고쳤을 때 같이 확인할 곳

기술문서 작성 규칙: 한 수치는 한 장에만 적고 다른 장은 링크합니다. 장 머리에
`← 이전 · 문서 지도 · 다음 →` 줄. 본문에 LaTeX · mermaid fence 를 쓰지 않습니다(그림은
`diagrams/` 의 SVG, `design_references/diagrams/` 가 유일한 하위 폴더). 장을 더하거나 번호를 바꾸면
모든 장의 머리 줄과 `00_문서_지도.md` 를 같이 고칩니다. 해설서(`study_references/`)는 **파일명과
장 번호가 동결**입니다. `papers/` 와 `*.pptx` 는 읽기 전용입니다.

`check_docs.py` 는 죽은 링크 · 없는 앵커 · 없는 그림 · 고아 그림 · 렌더 안 된 `.mmd` · 되살아난
폐기 스펙 · 본문 mermaid fence 를 잡습니다. 다음은 **기계가 못 잡으니 사람이** 봅니다.

- 인용한 주장이 대상 절에 실제로 있는가
- 뒤 장에서 정의되는 용어를 앞 장이 설명 없이 쓰지 않는가
- 폐기된 주장이 표현만 바꿔 살아 있지 않은가 ("가장 큰 진폭을 고른다" = argmax,
  "정답 인덱스의 진폭을 뒤집는다" = 오라클이 정답을 안다)
- 실측 수치에 조건이 붙어 있는가

| 무엇을 고쳤나 | 같이 볼 곳 |
|---|---|
| 설계 수치 | CSR 이면 JSON 을 고치고 `gen_csr.py` → 1장 1.2절 → `README*.md` 2절 → 해설서 [15.4절](documents/study_references/15_논문지도와_설계결정표.md#154-우리-프로젝트의-좌표--확정-설계-결정표) |
| 성능·자원 수치 | 어느 축인지부터 → 해당 근거 묶음의 `evidence.md` → 1장 1.5절 → `README*.md` |
| 포트 | 기술문서 12장과 RTL 을 같이. `make -C hardware_bram/sim ports ports-real ports-models` |
| 모델 추가·파라미터 | 5장 5.2절 모델 표 → `README*.md` 3절 |
| 절 제목·절 번호 | 그 장으로 들어오는 모든 링크. 앵커가 밀립니다 |
| 디렉터리 구조 | 이 파일 3절 · `README.md`/`README.ko.md` 4절 · 기술문서 5장 5.2절과 17장 |
| 다이어그램 | `.mmd` 를 고쳤으면 `render_diagrams.py` 실행 |
