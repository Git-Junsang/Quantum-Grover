# CLAUDE.md

## 프로젝트

`<`, `>`, `=`, 범위(`a < x < b`) 네 술어를 지원하는 **다중 타겟 Grover 탐색 에뮬레이터
가속기**. 호스트 PC 가 UART 로 술어와 임계값을 보내면 RVX SoC 안의 커스텀 IP 가 계산해
결과 인덱스를 돌려줍니다. 보드는 Arty A7-100T (`xc7a100tcsg324-1`).

**사용자**: 양자 알고리즘을 처음 접한 학부생. FPGA 경험은 있으나 설정·RTL 은 자세히 답할 것.

---

## 1. 작업 규칙

- 대화는 **한국어 존댓말**. 내부 추론은 영어 무방.
- 코드 주석은 **자세히** 달되 이모지 등 AI 티를 내지 말 것.
  - 예외: `documents/study_references/` 해설서 본문의 💡🔍❓⚠️🔑✏️ 표기는 문서 고유 관습이라
    **기존 것만 보존**합니다. 새 콜아웃 박스는 만들지 말고 산문으로 녹이십시오.
- 수식은 채팅에 쓰지 말 것 (터미널에 LaTeX 가 안 보입니다). `.md` 에 쓰고 링크만 주십시오.
- GitHub push 허용. 단 **커밋 메시지·PR 에 Claude/Anthropic 을 명시하지 말 것**.
- `hardware_*/vivado/` 아래에는 **Vivado 프로젝트 폴더만** 두고, 이름은 소문자 `vivado_<프로젝트이름>` 입니다.
  그 안에는 **리포트와 재현 불가능한 실측만** 남깁니다. 빌드·합성·시뮬 로그처럼 다시 돌리면
  나오는 것은 두지 않습니다. 실측 묶음 폴더는 `YYYY-MM-DD_<주제>`, 그 안의 파일은
  소문자 snake_case 로 짧게 (`result.txt` `summary.csv` `evidence.md`) — 폴더가 이미
  말해 주는 프로젝트명·날짜를 파일명에 되풀이하지 마십시오.
- README 는 루트의 `README.md` · `README.ko.md` **둘뿐**입니다. 하위 폴더에 README 를
  만들지 말고, 설명이 필요하면 `documents/design_references/` 에 별도 문서를 만드십시오.
- `.gitignore` 도 루트에 **하나뿐**입니다.

---

## 2. 정합성 기준 — 무엇이 정본인가

**보드에서 검증된 K3/H3-E4-M2 (2026-09-07 빌드) 가 정본입니다.** RTL 은
[`hardware_bram/src/`](hardware_bram/src/) 열일곱 파일이고, 그 sha256 이
비트스트림에 들어간 것과 바이트 동일합니다
([`meta/source_sha256.txt`](hardware_bram/vivado/vivado_bbht_grover_fpga/meta/source_sha256.txt)).
CSR 의 모든 숫자는 [`software/csr/bbht_grover_csr.json`](software/csr/bbht_grover_csr.json)
하나에서 나옵니다 (C·Verilog·Python 헤더와 CSR 규격 문서가 전부 생성물).

| 항목 | 값 |
|---|---|
| 큐비트 | Q = 14 (N = 16,384) |
| 데이터 워드 | 16비트 signed / 진폭 23비트 Q1.22 계열 / P = 32 레인 |
| 술어 | `LT` `GT` `EQ` `RANGE` |
| 실행 모드 | `MANUAL_SINGLE` `NORMAL_SINGLE` `CKPT_SINGLE` `NORMAL_ENUM` `CKPT_ENUM` |
| CSR | APB, base `0xE2020000`, **4바이트 간격**, 32비트, 38개 |
| 데이터 적재 | AHB 마스터 **SINGLE**, single outstanding. SRAM `0xE0000000`~`0xE001FFFF` |
| 결과 FIFO | 깊이 256 |
| 클럭 | 가속기 100 MHz / 시스템 50 MHz |
| 최종 구성 | **K3/H3-E4-M2** — 체크포인트 3벌 · 정책 지평 3 · 연산기 4벌 · 측정 최적화 2단 |

실행 모드 이름은 2026-09-10 에 `K4H8_*` 에서 `CKPT_*` 로 바꿨습니다. K·H·E·M 은
전부 RTL 빌드에 컴파일되는 값이라 CSR 모드 이름에 값을 박아 두면 빌드가 바뀔
때마다 이름이 틀려집니다 — 실제로 K4/H8 에서 K4/H4 를 거쳐 지금은 K3/H3 입니다.
골든 모델은 옛 이름(`K4H8_SINGLE` `K4H8_ENUM`, 그리고 `mode="K4H8"`)도 계속
받습니다 (`RUN_MODE_ALIASES` · `_MODE_ALIASES`). 다만 `bbht_paper_bench` 의
`CONTROL_K4H8_EQ` · `MODE_K4H8` 은 **그대로 두었습니다** — 그 파일은 보드 ELF 를
낸 소스와 sha256 이 같아야 합니다.

### 성능을 인용할 때 — 두 축을 섞지 마십시오

| 축 | 정본 | 값 |
|---|---|---|
| RTL 사이클 | [`results/2026-09-08_publication_6stage/`](hardware_bram/results/2026-09-08_publication_6stage/) | Normal 42,308,335 → M2 6,890,470 사이클, **6.1401x** |
| 보드 실경과 시간 | [`vivado/.../2026-09-08_k3h3_e4_m2_board_500run/`](hardware_bram/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/) | Normal 425,502 us → M2 55,798 us, **7.626x** |
| 소프트웨어 대비 | [`vivado/.../2026-09-08_orca_1core_baseline/`](hardware_bram/vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/) | ORCA 1코어 대비 **116,426x** (실경과 시간) |

세 근거는 같은 500 워크로드(M = 1/4/16/64/256 × 시드 100)를 씁니다. 궤적
(`result_index`·`trial_count`·`L_BBHT`)은 보드와 RTL 이 500/500 일치하지만
**사이클 값 자체는 다릅니다** — M2 는 473/500 이 정확히 3,279 사이클 차이납니다.
그러니 보드 사이클과 RTL 사이클로 배수를 만들지 마십시오.

우리 `bench250` 하네스는 드라이버로 연속 실행해서 보드에 더 가깝습니다 —
같은 250 워크로드에서 논리 축 250/250, 사이클도 230/250 이 정확히 같습니다
([`results/2026-09-10_bench250_final_core/`](hardware_bram/results/2026-09-10_bench250_final_core/)).

**골든 모델은 궤적 재현기가 아닙니다.** 측정 난수 확장과 체크포인트 플래너가
가정(`MEASUREMENT_ASSUMPTION` · `CHECKPOINT_ASSUMPTION`)이라 같은 250 워크로드에서
답은 250/250 유효하지만 `trial_count` 는 36/250 만 맞습니다. 오라클·고정소수점·
FIFO·종료 조건을 보는 **의미 참조**로만 쓰십시오.

6단계는 `Normal-E1 → K4/H4-E1 → K4/H4-E4 → K3/H3-E4 → K3/H3-E4-M1 → K3/H3-E4-M2`
이고, 단계별 기여는 -56.63% / -38.71% / -7.66% / -18.15% / -18.94% 입니다.
자원은 [`results/2026-09-08_resource_ablation_5config/`](hardware_bram/results/2026-09-08_resource_ablation_5config/)
에 다섯 구성이 같은 조건으로 있습니다 (Main IP LUT 13,804 → 33,730, DSP 64 → 128).

**폐기된 값 — 보이면 무시하십시오**: n=15·n=16, Q2.16·Q1.17, 8바이트 CSR 간격,
INCR16 버스트, argmax 측정, AXI4-Lite, MicroBlaze, XC7S100.
`trash_bin/` 안의 문서는 전부 이 구 스펙 기준이라 인용하면 안 됩니다.

**K4/H4·K4/H8 은 이제 중간 단계입니다.** 2026-09-01(K4/H8)·2026-09-04(K4/H4)
보드 실측 묶음은 그 시점 근거로 남겨 두었지만, 최종 성능을 인용할 자리가
아닙니다. 두 묶음은 250쌍(시드 50)이라 500 워크로드 캠페인과 총합을 맞댈 수도
없습니다.

**`hardware_bram/src/` 는 freeze 대상이라 고치지 마십시오.** 통신 계층은 두 벌이고
(정본 `src/` · 우리 것 `src_comm/`), 회귀가 셋 다 돌려 T1~T9·D1~D11 을 확인합니다.
배선 정합성은 `check_ports.py` 가 wrapper 19 + core 61 신호를 네 갈래
(`stub`/`real`/`final`/`dram`)로 매번 대조해서 지킵니다.

---

## 3. 두 갈래 — 아직 어느 쪽도 확정이 아님

반복 실패 시 진폭을 어떻게 재활용하느냐에서 구현이 둘로 갈립니다. 나중에 하나를 고릅니다.

- **`hardware_bram/`** — 체크포인트(K3)로 차이만큼만 이어 돌리고, 반복 한 번에 연산기
  **네 벌**(E4)이 협력합니다. **BRAM 만** 씁니다. 보드 실물이 이 갈래이고 현재 코드는
  전부 여기 있습니다.
- **`hardware_dram/`** — `j` 별 진폭을 DRAM 에 전량 저장하고, 난수 생성기가 뽑은 `j` 는
  BRAM 큐에도 올립니다. 정답 후보를 검증해 틀리면 큐에서 그 `j` 를 지우고 DRAM 에서
  다음 `j` 진폭을 큐에 올립니다. 체크포인트 K 도 정책 H 도 쓰지 않습니다 — 모든 `j` 가
  버스트 한 번 거리에 있어서 계획할 것이 없습니다. **RTL 초안과 회귀, 호스트 통신 경로를
  묶은 최상단(`src/bbht_dram_top.v`)까지 있고, 물리 DRAM 바인딩(MIG/AXI)과 RVX 설치는
  아직 없습니다.** 최상단은 DRAM burst 포트를 밖으로 냅니다. 같은 폴더의
  `bbht_rvx_wrapper.v` + 어댑터는 포트 계약 대조용 판이라 DRAM 을 안쪽에서 묶어 두었고,
  복원이 필요한 탐색에서 멈춥니다. 검증은 동작 수준 DRAM 모델
  (`testbench/dram_burst_model.v`) 위에서 하며, `make -C hardware_dram/sim equiv` 가
  같은 자극을 `hardware_bram` 정본에도 걸어 탐색 궤적이 일치하는지 대조합니다.
  대조 상대는 2026-09-09 부터 K3/H3-E4-M2 입니다 (그전에는 K4/H4 였습니다).
  단일탐색 전용이고 `enum_enable=1` 은 `config_error` 로 거절합니다.

두 트리는 하위 구조가 같습니다(`src/` `testbench/` `sim/` `results/` `firmware/` `rvx/` `vivado/`).
bram 에만 있는 폴더는 둘 중 하나입니다 — 모듈 이름이 정본 `src/` 와 겹쳐서 나눈 RTL
(`src_comm/` `src_ablation/`), 아니면 dram 에 아직 없는 역할(`synth/` `bitstream/`). 4절.
CSR 정본·골든 모델·검증 벡터는 `software/` 에서 공유합니다.
한쪽 갈래에만 해당하는 것을 `software/` 에 넣지 마십시오.

---

## 4. 디렉터리와 파일의 역할

### `documents/`

| 경로 | 역할 |
|---|---|
| `design_references/` | **설계 문서.** 해설서와 같은 기술문서체로 씁니다 |
| `design_references/CSR_레지스터_규격.md` | `gen_csr.py` **생성물.** 손으로 고치지 마십시오 |
| `design_references/호스트_조작_방법.md` | 호스트에서 부리는 법. 통신 계층의 주 문서 |
| `design_references/UART_명령_프로토콜.md` · `블록_인터페이스_다이어그램.md` | 통신 계약 |
| `design_references/Main_IP_포트_규격.md` · `데이터_고정소수점_메모리_규격.md` | Main IP 계약 |
| `design_references/다중결과탐색_*.md` · `단일검색_*.md` · `RTL_GitHub_*.md` · `전체_내용_보고서.md` | 골든 모델 분석 보고서 |
| `design_references/K3H3_E4_M2_정본_반입.md` | 정본이 K4/H4 에서 바뀐 경위와 세 성능 축 |
| `design_references/PASS2_융합과_다중엔진_탐색_실측.md` | 우리가 시도한 측정 융합·다중 엔진과, 정본이 같은 병목을 어떻게 다르게 푸는지 |
| `design_references/diagrams/` | **design_references 의 유일한 하위 폴더.** 손그림 SVG · `campaign_*.png` · `src/*.mmd` |
| `design_references/render_diagrams.py` | `diagrams/src/*.mmd` → `diagrams/*.svg` |
| `study_references/` | 학습용 해설서 0~18장 + 부록 A. **파일명과 장 번호는 동결** |
| `papers/` | 원문 논문 PDF. 읽기 전용 |
| `papers/papers_ko/` | 논문 한국어 해설본. 원문 대조용 보조 자료 |
| `check_docs.py` | 문서 정합성 검사기. **문서를 고친 뒤 반드시 돌릴 것** |
| `Main_IP_Final_20260910.pptx` · `LPSoC_BBHT_Grover_최종집약본_v1.0.4_2026-09-09.docx` | 발표 자료와 프로젝트 최종 집약본 원본. 읽기 전용. 집약본은 K4/H8 부터의 이력을 그대로 담고 있어 옛 수치가 섞여 있으니 인용은 2절 정본에서 하십시오 |

### `hardware_bram/` (와 같은 구조의 `hardware_dram/`)

아래 표는 두 갈래가 공유하는 모양에 `hardware_bram/` 에만 있는 폴더를 더한 것입니다.
`hardware_dram/` 에만 있는 것은 그다음 표에 따로 적었습니다. 파일을 새로 둘 때는
dram 에 같은 역할의 폴더가 있으면 그리로 보내십시오 (테스트벤치는 C++ 하네스까지
`testbench/`, 러너와 보고 스크립트는 `sim/`).

| 경로 | 역할 |
|---|---|
| `src/` | **보드 정본 RTL 17개 (freeze).** wrapper·mmio·loader·Main IP 10개·헤더 2개 |
| `src/bbht_rvx_wrapper.v` | RVX user region 최상위. 어댑터 없이 Main IP 를 K3/H3-E4 로 뭅니다 |
| `src/bbht_grover_main_ip.v` | Main IP 최상위. K·H·E·M 이 전부 컴파일 파라미터입니다 |
| `src/grover_policy_ooc_top.v` · `grover_policy_impl_wrapper.v` | policy OOC 합성 전용. **합성 경로에 넣지 마십시오** |
| `src_comm/` | 우리가 쓴 통신 계층. CSR 정본에서 생성한 헤더를 include 합니다 |
| `src_comm/bbht_grover_core_adapter.v` | 계약 이름 `bbht_grover_core` 로 정본 Main IP 를 감싸는 어댑터 |
| `src_comm/bbht_grover_user_region.vh` | 우리 갈래가 RVX 에 넘기는 user region 선언 |
| `src_comm/bbht_bram_top.v` | 최상단. 우리 mmio·loader 에 정본 Main IP 를 어댑터 없이 직접 뭄. 포트는 `bbht_rvx_wrapper` 와 같고 `hardware_dram/src/bbht_dram_top.v` 와 짝 |
| `src_ablation/` | 6단계 ablation · K/H 단독 실험의 공통소스 28개. 정본에 `MEAS_M1/M2` 스위치를 더한 판(정본과 다른 것은 `bbht_grover_main_ip.v` `bbht_rvx_wrapper.v` `grover_measurement.v` 셋) + 구성별 standalone top 8벌 + UART 브리지·데이터셋 생성기 + 공통 XDC. 캠페인 입력이라 **고치지 마십시오** |
| `testbench/tb_bbht_rvx.v` | 통신 계층 계약 T1~T9. 두 갈래에 같은 TB 를 물립니다 |
| `testbench/bbht_grover_core_stub.v` | Main IP 자리 채우개. 포트 계약 대조 대상 |
| `testbench/ahb_sram_model.v` | AHB 슬레이브 모델 |
| `testbench/tb_bbht_bram_top.v` | 최상단 H1~H15. APB 로 호스트 순서를 흉내 내고 Q14 전체 적재, NORMAL/CKPT 짝 궤적 비교, 열거까지 |
| `testbench/tb_publication_plusargs.v` | ablation 캠페인 TB (iverilog, `+TC` `+SEED_*` 플러스인자). 표시 문자열의 `k4h4` 는 하드코딩 잔재 |
| `sim/Makefile` | 회귀 진입점. verilator: `ports lint regress driver` · `real` · `final` · `top` · `bench250` · `bench500` / iverilog: `anchor` · `publication` · `kh` |
| `testbench/tb_driver.cpp` · `sim/run_driver_test.sh` | 드라이버 + RTL 공동 시뮬 D1~D11 (`CORE=stub\|real\|final`) |
| `testbench/tb_bench250.cpp` · `sim/bench250_report.py` | 250쌍 워크로드 시뮬. 궤적 불변식 + 보드 M2 실측과 워크로드별 대조 (`bench500` 도 같은 짝) |
| `sim/run_publication.py` · `publication_report.py` · `run_kh.py` | 재현 패키지 러너 이식판. 6단계 2,500회 · K/H 750회를 돌려 `results/` 기대값과 정확 대조 |
| `synth/` | Vivado 배치 스크립트. `run_main_ip.sh` 정본 OOC · `run_resource.sh` 5구성 ablation |
| `results/` | **시뮬 캠페인 근거 묶음** (`YYYY-MM-DD_<주제>/`). 재현 소스 없이 결과만 |
| `bitstream/` | 보드에 구운 비트스트림 묶음 (`YYYY-MM-DD_<주제>`) |
| `rvx/bbht_grover_upgrade.xml` | RVX 플랫폼 정의 (clk_accel 100 MHz) |
| `rvx/install_to_platform.sh` | 저장소 → RVX 플랫폼 설치. `LAYER=final\|comm` 으로 통신 계층을 고릅니다 |
| `vivado/vivado_<프로젝트이름>/` | **Vivado 프로젝트 한 벌.** 폴더 이름 규칙은 소문자 `vivado_` 접두 |
| `vivado/vivado_bbht_grover_fpga/reports/` | 최종 구현 `route_{util,util_hier,timing_summary,timing_max,power}.rpt` |
| `vivado/vivado_bbht_grover_fpga/meta/` | 그 구현의 빌드 정보·소스 sha256·비트스트림 sha256 |
| `vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/` | **보드 실측 정본.** 500 워크로드, Normal 대비 7.626x |
| `vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/` | 같은 보드 ORCA 1코어 순수 SW 기준선 |
| `vivado/vivado_bbht_grover_fpga/2026-09-01_*` · `2026-09-04_*` | 중간 단계(K4/H8·K4/H4) 보드 실측. 최종 인용처가 아닙니다 |
| `firmware/bbht_grover_driver.{c,h}` | 재사용 드라이버 |
| `firmware/bbht_console/` | UART 명령 셸. 재빌드 없이 조건을 바꿉니다 |
| `firmware/bbht_paper_bench/` | 실시간 벤치 앱. 보드 실측 500런을 낸 것 |
| `firmware/orca_sw_baseline/` | 가속기를 안 쓰는 ORCA 1코어 기준선 앱 |

### `hardware_dram/` 에만 있는 것

Main IP 자체가 다른 갈래라 이쪽 `src/` 의 내용은 `hardware_bram/src/` 와 다릅니다.
`hardware_bram` 은 `src/`(freeze 정본)와 `src_comm/`(우리 통신 계층)으로 나뉘지만, 이쪽은
freeze 대상이 없어서 **`src/` 한 폴더**에 Main IP 초안(`grover_*` · `lpsoc_*`)과 통신 계층
(`bbht_*`, `hardware_bram/src_comm/` 과 mmio·loader 바이트 동일)을 같이 둡니다
(2026-09-11 에 옛 `src_v2/` 를 `src/` 로 합쳤습니다). 최상위가 둘이라 `sim/Makefile` 은
파일을 하나씩 나열합니다 — glob 으로 모으지 마십시오. 재사용 8개
(`grover_param.vh` `arithmetic` `memories` `iteration` `measurement` `loader` `status`
`dram_random`) 에 아래 신규 5개가 붙습니다. 체크포인트(`grover_checkpoint.v`)와 정책
엔진(`grover_policy.v`)은 **일부러 안 가져왔습니다** — 모든 `j` 가 버스트 한 번 거리라
계획할 것이 없습니다.

| 경로 | 역할 |
|---|---|
| `src/grover_dram_amp_store.v` | 반복마다 512행을 DRAM 슬롯에 store / 필요할 때 restore |
| `src/grover_dram_prep_seq.v` | 버퍼 A 준비 시퀀서. **체크포인트 K/H 를 대신하는 자리** |
| `src/grover_dram_shot_fsm.v` | 외곽 BBHT 라운드 제어 |
| `src/grover_dram_queue.v` | 버퍼 A/B 두 벌과 역할별 포트 뮤스 |
| `src/grover_dram_param.vh` | 슬롯 주소맵. 92바이트/행 × 512행 = 47,104바이트/슬롯 |
| `src/bbht_dram_top.v` | **이 갈래의 최상단.** mmio + AHB 적재기 + Main IP 를 직접 물고 DRAM burst 포트를 밖으로 냄 |
| `src/bbht_rvx_wrapper.v` · `bbht_grover_core_adapter.v` | 포트 계약판. `check_ports.py dram` 대조용이고 DRAM 이 묶여 있어 실제로는 못 씀 |
| `testbench/dram_burst_model.v` | 동작 수준 DRAM 모델. 지연·백프레셔가 전부 파라미터 |
| `testbench/tb_dram_amp_store.v` | store/restore 왕복 A1~A5 |
| `testbench/tb_dram_prep_seq.v` | prep 시퀀서 P1~P8. 연산기 자리에 스텁을 넣습니다 |
| `testbench/tb_dram_core.v` | Main IP 통합 C1~C8. `GD_DRAM_BRANCH` 를 빼면 `hardware_bram` 에도 물립니다 |
| `testbench/tb_bbht_dram_top.v` | 최상단 H1~H14. APB 로 호스트 순서를 흉내 내고, C1~C7 은 `tb_dram_core` 와 궤적 대조 |
| `sim/Makefile` | `ports lint store prep core top equiv`. `top` 은 기본 지연과 백프레셔 두 벌 |
| `sim/equiv_report.py` | 세 갈래(dram / bram Normal / bram 체크포인트) 로그 대조기. `--names` 로 최상단 대조에도 씀 |

**아직 없는 것**: 물리 DRAM 바인딩(MIG native UI 든 AXI4 든), 열거,
버퍼 B 를 쓰는 라운드 간 프리페치, RVX 설치 스크립트, Vivado 프로젝트.

### `software/` — 두 갈래가 공유

| 경로 | 역할 |
|---|---|
| `csr/bbht_grover_csr.json` | **모든 숫자의 출처** |
| `csr/gen_csr.py` | → C·Verilog·Python 헤더 + CSR 규격 문서. `--check` 로 검증 |
| `csr/generated/` | 생성물. 손으로 고치면 회귀가 잡습니다 |
| `contract/*.docx` | **인수인계 통신 계약 원본.** 포트 계약의 출처 |
| `contract/port_contract.tsv` | 포트 계약 (인수인계 §3.3 wrapper 19 + §3.4 core 61) |
| `contract/extract_contract.py` | 옆의 docx → tsv. 재현 가능 (docx sha256 을 헤더에 남깁니다) |
| `contract/check_ports.py` | tsv ↔ RTL 자동 대조 |
| `golden/rtl_v098_*.py` · `rtl_v07g.py` | 골든 모델 |
| `golden/tools/` | 벡터 생성기 · 캠페인 분석 · 체크포인트 K 최적화 모델 |
| `bin/` | 검증 벡터와 데이터 파일 (hex · json) |
| `bbht_cli.py` | 호스트 CLI. `--port mock` 이면 보드 없이 됩니다 |

### `trash_bin/` — git 추적 안 함

구 스펙 문서와 대용량 산출물 보관소입니다. **여기서 인용하지 마십시오.**
`documents_design/` 구 설계 문서 11편 · `KJE/` 구 펌웨어와 71M 분석 결과 ·
`PJK/` 비트스트림과 136M 아카이브 · `PJK_handoff/` K4/H8 시절 인수인계 요약본 2편 ·
`SJS/` 구 README · `presentation/` 세미나·스펙결정 발표자료 · `old_tools/` 폐기된 Vivado 스텁 ·
`SERVER_repro_package_v1.0/` 재현 패키지 zip 에서 저장소에 들이지 않은 81개 (standalone 판 전체, 구 17장 판본, 옛 스크립트, DSE 원본 18 MB 등).

---

## 5. 명령어

```bash
# 통신 계층 회귀 (몇 초)
make -C hardware_bram/sim ports lint regress driver

# 정본 통째 / 우리 통신 계층 + 정본 코어 (각각 몇 분)
make -C hardware_bram/sim final
make -C hardware_bram/sim real

# 최상단 bbht_bram_top 회귀 (1분 30초쯤)
make -C hardware_bram/sim top

# 250쌍 궤적 벤치 (20분쯤). CORE=real 이면 우리 통신 계층으로
make -C hardware_bram/sim bench250

# 6단계 ablation · K/H 단독 실험 재현 (iverilog). anchor 는 5회뿐이라 금방,
# publication 은 2,500회, kh 는 750회. JOBS=N 으로 병렬도
make -C hardware_bram/sim anchor
make -C hardware_bram/sim publication
make -C hardware_bram/sim kh

# 최종 Main IP 자원 재기 (Vivado, 2분쯤)
hardware_bram/synth/run_main_ip.sh

# 5구성 자원 ablation (Vivado)
hardware_bram/synth/run_resource.sh

# DRAM 갈래 회귀 (1분 30초쯤, 최상단 bbht_dram_top 의 top 까지). equiv 는
# hardware_bram 정본과 궤적 대조까지 (40초 더)
make -C hardware_dram/sim
make -C hardware_dram/sim equiv

# CSR 정본을 고쳤으면
python3 software/csr/gen_csr.py

# 문서를 고쳤으면 (오류 0건이어야 합니다)
python3 documents/check_docs.py

# 해설서 다이어그램
python3 documents/study_references/render_diagrams.py

# RVX
source /opt/rvx/rvx_setup.sh
hardware_bram/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_upgrade && make syn && make sim_rtl
```

**이 환경의 툴체인** (2026-09-09 실측): `verilator` 5.020, `vsim`(Questa 2022.1_2),
`vivado` 2026.1(노드락 라이선스, `xc7a100tcsg324-1` 합성·구현·비트스트림 가능), RISC-V GCC,
`iverilog`/`vvp` 12.0. 회귀는 **전부 verilator** 로 돌아갑니다 — `hardware_*/testbench/` 에는
테스트벤치 소스만 있고 Makefile 이 없으며, `sim/Makefile` 이 그것들을 물어 갑니다.
**헤드리스라 `gtkwave` 와 Vivado GUI 는 설치돼 있어도 못 띄웁니다** — `-mode batch` 전용.
RVX 는 `/opt/rvx` 에 로컬 전체 설치되어 있어 원격 접속이 필요 없습니다.
따를 예제는 `platform/tip_quantized_cnn/`(커스텀 IP + `user/rtl`·`user/api`).

경로에 공백("중앙대학교 학부인턴")이 있어서 verilator 생성 Makefile 을 제자리에서 못 돌립니다.
`sim/Makefile` 이 `--Mdir /tmp/...` 로 빼는 이유가 이것이니 건드리지 마십시오.

---

## 6. 문서를 고쳤을 때 같이 확인할 곳

`check_docs.py` 는 죽은 링크 · 없는 앵커 · 없는 그림 · 고아 그림 · 렌더 안 된 `.mmd` ·
되살아난 폐기 스펙 · 본문 mermaid fence 를 잡습니다. 다음은 **기계가 못 잡으니 사람이** 봅니다.

- 인용한 주장이 대상 절에 실제로 있는가
- 뒤 장에서 정의되는 용어를 앞 장이 설명 없이 쓰지 않는가
- 폐기된 주장이 표현만 바꿔 살아 있지 않은가 ("가장 큰 진폭을 고른다" = argmax,
  "정답 인덱스의 진폭을 뒤집는다" = 오라클이 정답을 안다)
- 실측 수치에 조건이 붙어 있는가

| 무엇을 고쳤나 | 같이 볼 곳 |
|---|---|
| 설계 수치 | `software/csr/bbht_grover_csr.json` → `gen_csr.py` 재실행 → `CLAUDE.md` 2절 → `README*.md` 2절 |
| 성능·자원 수치 | 어느 축인지부터 (RTL 사이클 / 보드 실경과 시간 / 소프트웨어 대비) → 해당 근거 묶음의 `evidence.md` → `CLAUDE.md` 2절 → `README*.md` |
| 포트 | 인수인계 docx → `extract_contract.py` 재실행 → `make -C hardware_bram/sim ports` (네 갈래 전부) |
| 절 제목·절 번호 | 그 장으로 들어오는 모든 링크. 앵커가 밀립니다 |
| 해설서 파일명 | **동결입니다.** 13·14장이 제목만 바뀌고 파일명을 둔 이유가 이것입니다 |
| 디렉터리 구조 | `CLAUDE.md` 4절 · `README.md`/`README.ko.md` 4절 |
| 다이어그램 | `.mmd` 를 고쳤으면 `render_diagrams.py` 실행 |

해설서 본문은 다이어그램을 `<img src="diagrams/<name>.svg">` 로 참조합니다.
**본문에 mermaid fence 를 직접 쓰지 않습니다** — 어느 뷰어에서든 보이게 하려는 의도입니다.
mermaid 로 안 되는 그림(진폭 막대, 기하 회전, 타임라인)은 손으로 쓴 SVG 를 `diagrams/` 에 직접 둡니다.

**고전 선형 스캔과 속도를 비교하지 않습니다.** 에뮬레이션은 고전 스캔보다 느립니다.
비교 대상은 셋입니다 — 같은 보드 위의 ORCA 1코어 순수 소프트웨어 기준선(가장 정당한
대조군. 같은 칩·같은 워크로드·같은 시드), Qiskit AerSimulator, NumPy 상태벡터
시뮬레이터. ORCA 대비 배수가 십만 단위인 것은 P=32 병렬과 클럭 2배 때문이지
알고리즘 우위가 아니라는 단서를 항상 붙이십시오.
