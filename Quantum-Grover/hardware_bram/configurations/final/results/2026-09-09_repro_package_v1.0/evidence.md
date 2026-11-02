# 재현 package v1.0 — 반입 출처

## 무엇인가

이 저장소의 2026-09-09 갱신분과 2026-09-13 반입분이 어디서 왔는지 적어 둔
directory입니다. 출처는 `BBHT_Grover_Reproduction_Package_v1.0_20260909` 한 벌이고,
`hardware_bram/SERVER-20260909T134037Z-1-001.zip`로 받았습니다 (당시 directory 이름).

2026-09-09에는 Board-Verified Build RTL과 결과만 들이고 재현 source는 package에 남겨 두었습니다.
2026-09-13에 zip을 풀어 나머지를 당시 `hardware_bram/`의 역할별 directory로 옮기고 zip은
지웠습니다. zip 안에 든 `BBHT_Grover_Reproduction_Package_v1.0_20260909.tar.gz`는
zip의 나머지 202 files와 byte까지 같은 사본이라 따로 풀지 않고 버렸습니다.

같은 날 `hardware_bram/src/`를 최신 revision 한 벌로 정리했습니다. 그래서 반입한 것 중
일부는 main에 없고 tag에만 있습니다.

| tag | 그 시점의 `hardware_bram/` |
|---|---|
| `board-k3h3-e4-m2` | 반입 직후. `src/`가 Board-Verified Build 17개 그대로이고 `src_comm/` · `src_ablation/`과 ablation study runner가 전부 있음 |
| `backup-src_comm` | `src_comm`을 `src/`로 합친 직후 |
| `backup-src_ablation` | ablation study core까지 `src/`로 합친 최신 revision |

## 어디로 갔는가

| package 안 위치 | 저장소 위치 |
|---|---|
| `02_FINAL_RTL/{src,include}` | tag `board-k3h3-e4-m2`의 `hardware_bram/src/` — Board-Verified Build 17개. main의 `src/`에는 그중 Accelerator Core 쪽 11개가 byte 그대로 남았습니다 |
| `02_FINAL_RTL/bbht_grover_upgrade.xml` | `hardware_bram/configurations/final/rvx/bbht_grover_final.xml` |
| `04_PUBLICATION_6STAGE/src/`의 `bbht_grover_main_ip.v` · `grover_measurement.v` | main의 `hardware_bram/src/` — 2026-09-13부터 Accelerator Core가 이 공통 source revision입니다 |
| `03_COMMON_SIM/rtl_support/` · `04_PUBLICATION_6STAGE/{src,include,tops}/` · `05_KH_ISOLATED/tops/` · `07_STANDALONE_FPGA/constraints/` | tag `board-k3h3-e4-m2`의 `hardware_bram/src_ablation/` |
| `04_PUBLICATION_6STAGE/{tb,scripts}/` · `05_KH_ISOLATED/scripts/` | tag `board-k3h3-e4-m2`의 `testbench/tb_publication_plusargs.v` · `sim/run_publication.py` · `publication_report.py` · `run_kh.py` |
| `03_COMMON_SIM/datasets/` · `04_PUBLICATION_6STAGE/expected/` · `09_REFERENCE_RESULTS/publication/` | `hardware_bram/results/2026-09-08_publication_6stage/` |
| `05_KH_ISOLATED/expected/` | `hardware_bram/results/2026-09-09_kh_isolated_e1/` |
| `06_RESOURCE_SYNTHESIS/` | `hardware_bram/synth/parse_resource.py`. `run_resource.sh` · `resource_synth.tcl`은 tag `board-k3h3-e4-m2` |
| `06_RESOURCE_SYNTHESIS/expected/` · `09_REFERENCE_RESULTS/resource/` | `hardware_bram/results/2026-09-08_resource_ablation_5config/` |
| `08_RVX_INTEGRATION/hw_realtime_firmware/source/` | `hardware_bram/firmware/bbht_paper_bench/` |
| `08_RVX_INTEGRATION/orca_sw_baseline/` | `hardware_bram/firmware/orca_sw_baseline/` |
| `09_REFERENCE_RESULTS/full_rvx/` · 두 firmware ELF | `hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/{reports,meta}/` · `hardware_bram/configurations/final/bitstream/2026-09-08_k3h3_e4_m2/` |
| `09_REFERENCE_RESULTS/board_reference/` | `hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/` |
| `09_REFERENCE_RESULTS/orca_reference/` | `hardware_bram/configurations/final/vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/` |
| `00_START_HERE/master_reference/*.docx` | `documents/` |
| `00_START_HERE/` · `99_MANIFEST/` 일부 | 이 directory (아래 file 표) |

file 이름은 저장소 규칙(소문자 snake_case, directory가 말해 주는 것은 되풀이하지 않음)에
맞춰 바꾼 것이 있습니다. 내용은 바꾸지 않았고, 경로를 저장소 배치로 고친 runner와
synthesis script만 예외입니다 (판정 논리와 expected result는 원본 그대로).

## 저장소에 넣지 않은 것

저장소 어디에도 byte 동일본이 없는데 들이지 않은 file이 81개 있습니다.
`trash_bin/SERVER_repro_package_v1.0/`에 package 배치 그대로 두었습니다
(git 추적 안 함).

- `07_STANDALONE_FPGA/` (XDC 제외) — RVX 없이 UART-APB bridge와 on-chip dataset
  생성기로 도는 standalone revision입니다. 2026-09-13에 한 번 들였다가 최종 revision에 필요
  없다고 보고 다시 뺐습니다. PC에서 임의 data를 올릴 수 없고(data는 on-chip
  생성기의 고정 testbench array뿐), CSR 접근마다 UART를 왕복해서 system 속도도 RVX
  revision보다 느립니다. Accelerator Core code는 Board-Verified Build와 같습니다(주석만 다름). 뺄 때 RTL 15개의
  sha256이 `sha256_standalone_rtl.txt`와 전부 맞는 것을 확인했습니다
- `08_RVX_INTEGRATION/docs/` — **구 스펙 문서입니다.** 17장 해설서의 옛 판본이라
  `arty-50` · `xc7s50csga324-1`로 적혀 있습니다. 저장소의
  `documents/study_references/17_rvx_soc_integration.md`가 최신입니다
- `02_FINAL_RTL/Makefile` · `08_RVX_INTEGRATION/platform/Makefile` — RVX 표준
  platform Makefile입니다. `/opt/rvx/platform/tip_quantized_cnn/Makefile`과 byte
  동일하고 ETRI 저작권 표기가 붙어 있습니다
- package 배치를 전제로 한 안내와 runner — directory마다 있던 `README*`,
  `10_REPRO_RUNNER/`, `01_ENVIRONMENT/`, `08_RVX_INTEGRATION/prepare_new_platform.sh`.
  runner 역할은 tag `board-k3h3-e4-m2`의 `hardware_bram/sim/Makefile`
  (`anchor` · `publication` · `kh`)과 `synth/run_resource.sh`, 그리고
  `hardware_bram/configurations/final/rvx/install_to_platform.sh`가 이어받았습니다
- `*/scripts/original/` — 원 campaign server 경로가 박힌 옛 script. package 스스로
  이식한 revision을 따로 만들어 둔 것들입니다
- `06_RESOURCE_SYNTHESIS/`의 portable script — 같은 논리에 주석을 붙인 revision이
  tag `board-k3h3-e4-m2`의 `hardware_bram/synth/`에 있습니다
- `11_OPTIONAL_CHECKPOINT_DSE/` — 옛 checkpoint DSE harness와 18 MB 원본 CSV.
  package가 "공식 tie-break campaign을 이것만으로 정확히 재현한다고 주장하지 말라"
  고 적어 둔 자료입니다 (`missing.md` 참고)
- firmware 옛 revision `main.c.before_real_clock`, ORCA build log와 MANIFEST,
  `90_EXTERNAL_DEPENDENCIES/`, `99_MANIFEST/FILE_INDEX.csv`

`90_EXTERNAL_DEPENDENCIES/LICENSE_NOTES.md`는 이 package가 재현 server용이며 공개
배포 전에 license와 소유권을 다시 감사하라고 적고 있습니다. GitHub에 올리기
전에 한 번 보십시오.

## 정합성 확인

반입 뒤 manifest를 저장소 경로로 옮겨 대조했고 **전부 일치**합니다. Board-Verified Build와
ablation study 공통소스 전체는 tag에서, main의 Accelerator Core는 main에서 봅니다.

```bash
# 태그에서 -- 보드 정본 17개와 ablation 공통소스 23개
git worktree add /tmp/board board-k3h3-e4-m2 && cd /tmp/board/hardware_bram
R=results/2026-09-09_repro_package_v1.0
sed -e 's#02_FINAL_RTL/bbht_grover_upgrade.xml#rvx/bbht_grover_upgrade.xml#' \
    -e 's#02_FINAL_RTL/[a-z]*/#src/#' $R/sha256_final_rtl.txt | sha256sum -c
sed -e 's#04_PUBLICATION_6STAGE/tb/#testbench/#' \
    -e 's#04_PUBLICATION_6STAGE/[a-z]*/#src_ablation/#' $R/sha256_publication_src.txt | sha256sum -c

# main 에서 -- src/ 의 Main IP 13개가 ablation 공통소스와 바이트 동일
cd hardware_bram
grep -E '04_PUBLICATION_6STAGE/(src/(bbht_grover_main_ip|grover_)|include/grover_param)' \
    $R/sha256_publication_src.txt | sed 's#04_PUBLICATION_6STAGE/[a-z]*/#src/#' | sha256sum -c
```

Board-Verified Build 17개는 `../../vivado/vivado_bbht_grover_fpga/meta/source_sha256.txt` 와도
일치합니다. 즉 tag `board-k3h3-e4-m2`의 RTL이 2026-09-07 bitstream에 들어간 것과
byte 동일합니다.

## file

| file | 내용 |
|---|---|
| `package_info.txt` | package 정보 (최종 구조 final configuration, 논문 baseline Stage 2) |
| `expected_results.md` | 여섯 재현 수준의 expected result 원문 |
| `metric_guardrails.md` | 지표를 섞지 않기 위한 네 가지 규칙 원문 |
| `reproduction_levels.md` | 재현 수준 R0~R6 표 원문. 명령은 package runner 이름입니다 |
| `not_bundled.md` · `missing.md` | package가 일부러 뺀 것과 나중에 채울 것의 원문 |
| `sha256_final_rtl.txt` | 최종 RVX source sha256 |
| `sha256_publication_src.txt` | ablation study 공통소스 · top · TB sha256 |
| `sha256_standalone_rtl.txt` | standalone RTL sha256 (file은 trash_bin 쪽) |
| `sha256_all.txt` | package 전체 file sha256 (경로는 package 배치 기준) |
| `internal_verify.txt` | package를 만들 때의 자체 감사 기록 원문 |
