# 재현 패키지 v1.0 — 반입 출처

## 무엇인가

이 저장소의 2026-09-09 갱신분과 2026-09-13 반입분이 어디서 왔는지 적어 둔
폴더입니다. 출처는 `BBHT_Grover_Reproduction_Package_v1.0_20260909` 한 벌이고,
`hardware_bram/SERVER-20260909T134037Z-1-001.zip` 로 받았습니다.

2026-09-09 에는 정본 RTL 과 결과만 들이고 재현 소스는 패키지에 남겨 두었습니다.
2026-09-13 에 zip 을 풀어 나머지를 `hardware_bram/` 의 역할별 폴더로 옮기고 zip 은
지웠습니다. zip 안에 든 `BBHT_Grover_Reproduction_Package_v1.0_20260909.tar.gz` 는
zip 의 나머지 파일 202개와 바이트까지 같은 사본이라 따로 풀지 않고 버렸습니다.

## 어디로 갔는가

| 패키지 안 위치 | 저장소 위치 |
|---|---|
| `02_FINAL_RTL/{src,include}` | `hardware_bram/src/` — 최종 K3/H3-E4-M2 RVX 소스 17개 |
| `02_FINAL_RTL/bbht_grover_upgrade.xml` | `hardware_bram/rvx/bbht_grover_upgrade.xml` |
| `03_COMMON_SIM/rtl_support/` · `04_PUBLICATION_6STAGE/{src,include,tops}/` · `05_KH_ISOLATED/tops/` | `hardware_bram/src_ablation/` |
| `07_STANDALONE_FPGA/constraints/` | `hardware_bram/src_ablation/` — 5구성 자원 합성의 공통 XDC 로만 씁니다 |
| `04_PUBLICATION_6STAGE/tb/` | `hardware_bram/testbench/tb_publication_plusargs.v` |
| `04_PUBLICATION_6STAGE/scripts/` · `05_KH_ISOLATED/scripts/` | `hardware_bram/sim/run_publication.py` · `publication_report.py` · `run_kh.py` |
| `03_COMMON_SIM/datasets/` · `04_PUBLICATION_6STAGE/expected/` · `09_REFERENCE_RESULTS/publication/` | `hardware_bram/results/2026-09-08_publication_6stage/` |
| `05_KH_ISOLATED/expected/` | `hardware_bram/results/2026-09-09_kh_isolated_e1/` |
| `06_RESOURCE_SYNTHESIS/` | `hardware_bram/synth/run_resource.sh` · `resource_synth.tcl` · `parse_resource.py` |
| `06_RESOURCE_SYNTHESIS/expected/` · `09_REFERENCE_RESULTS/resource/` | `hardware_bram/results/2026-09-08_resource_ablation_5config/` |
| `08_RVX_INTEGRATION/hw_realtime_firmware/source/` | `hardware_bram/firmware/bbht_paper_bench/` |
| `08_RVX_INTEGRATION/orca_sw_baseline/` | `hardware_bram/firmware/orca_sw_baseline/` |
| `09_REFERENCE_RESULTS/full_rvx/` · 두 펌웨어 ELF | `hardware_bram/vivado/vivado_bbht_grover_fpga/{reports,meta}/` · `hardware_bram/bitstream/2026-09-08_k3h3_e4_m2/` |
| `09_REFERENCE_RESULTS/board_reference/` | `hardware_bram/vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/` |
| `09_REFERENCE_RESULTS/orca_reference/` | `hardware_bram/vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/` |
| `00_START_HERE/master_reference/*.docx` | `documents/` |
| `00_START_HERE/` · `99_MANIFEST/` 일부 | 이 폴더 (아래 파일 표) |

파일 이름은 저장소 규칙(소문자 snake_case, 폴더가 말해 주는 것은 되풀이하지 않음)에
맞춰 바꾼 것이 있습니다. 내용은 바꾸지 않았고, 경로를 저장소 배치로 고친 러너와
합성 스크립트만 예외입니다 (판정 논리와 기대값은 원본 그대로).

## 저장소에 넣지 않은 것

저장소 어디에도 바이트 동일본이 없는데 들이지 않은 파일이 81개 있습니다.
`trash_bin/SERVER_repro_package_v1.0/` 에 패키지 배치 그대로 두었습니다
(git 추적 안 함).

- `07_STANDALONE_FPGA/` (XDC 제외) — RVX 없이 UART-APB 브리지와 온칩 데이터셋
  생성기로 도는 standalone 판입니다. 2026-09-13 에 한 번 들였다가 최종판에 필요
  없다고 보고 다시 뺐습니다. PC 에서 임의 데이터를 올릴 수 없고(데이터는 온칩
  생성기의 고정 벤치 배열뿐), CSR 접근마다 UART 를 왕복해서 시스템 속도도 RVX
  판보다 느립니다. Main IP 코드는 정본과 같습니다(주석만 다름). 뺄 때 RTL 15개의
  sha256 이 `sha256_standalone_rtl.txt` 와 전부 맞는 것을 확인했습니다
- `08_RVX_INTEGRATION/docs/` — **구 스펙 문서입니다.** 17장 해설서의 옛 판본이라
  `arty-50` · `xc7s50csga324-1` 로 적혀 있습니다. 저장소의
  `documents/study_references/17_RVX_SoC_통합.md` 가 최신입니다
- `02_FINAL_RTL/Makefile` · `08_RVX_INTEGRATION/platform/Makefile` — RVX 표준
  플랫폼 Makefile 입니다. `/opt/rvx/platform/tip_quantized_cnn/Makefile` 과 바이트
  동일하고 ETRI 저작권 표기가 붙어 있습니다
- 패키지 배치를 전제로 한 안내와 러너 — 폴더마다 있던 `README*`,
  `10_REPRO_RUNNER/`, `01_ENVIRONMENT/`, `08_RVX_INTEGRATION/prepare_new_platform.sh`.
  러너 역할은 `hardware_bram/sim/Makefile` 의 `anchor` · `publication` · `kh` 와
  `hardware_bram/synth/run_resource.sh`, `hardware_bram/rvx/install_to_platform.sh` 가
  이어받았습니다
- `*/scripts/original/` — 원 캠페인 서버 경로가 박힌 옛 스크립트. 패키지 스스로
  이식판을 따로 만들어 둔 것들입니다
- `06_RESOURCE_SYNTHESIS/` 의 portable 스크립트 — `hardware_bram/synth/` 에 같은
  논리에 주석을 붙인 판이 이미 있습니다
- `11_OPTIONAL_CHECKPOINT_DSE/` — 옛 체크포인트 DSE 하네스와 18 MB 원본 CSV.
  패키지가 "공식 tie-break 캠페인을 이것만으로 정확히 재현한다고 주장하지 말라"
  고 적어 둔 자료입니다 (`missing.md` 참고)
- 펌웨어 옛 판 `main.c.before_real_clock`, ORCA 빌드 로그와 MANIFEST,
  `90_EXTERNAL_DEPENDENCIES/`, `99_MANIFEST/FILE_INDEX.csv`

`90_EXTERNAL_DEPENDENCIES/LICENSE_NOTES.md` 는 이 패키지가 재현 서버용이며 공개
배포 전에 라이선스와 소유권을 다시 감사하라고 적고 있습니다. GitHub 에 올리기
전에 한 번 보십시오.

## 정합성 확인

2026-09-13 반입 뒤 매니페스트를 저장소 경로로 옮겨 대조했고 **전부 일치**합니다.

```bash
cd hardware_bram
R=results/2026-09-09_repro_package_v1.0
sed -e 's#02_FINAL_RTL/bbht_grover_upgrade.xml#rvx/bbht_grover_upgrade.xml#' \
    -e 's#02_FINAL_RTL/[a-z]*/#src/#' $R/sha256_final_rtl.txt | sha256sum -c
sed -e 's#04_PUBLICATION_6STAGE/tb/#testbench/#' \
    -e 's#04_PUBLICATION_6STAGE/[a-z]*/#src_ablation/#' $R/sha256_publication_src.txt | sha256sum -c
```

`hardware_bram/src/` 17개는 `../../vivado/vivado_bbht_grover_fpga/meta/source_sha256.txt`
와도 일치합니다. 즉 저장소의 정본 RTL 은 2026-09-07 비트스트림에 들어간 것과
바이트 동일합니다.

## 파일

| 파일 | 내용 |
|---|---|
| `package_info.txt` | 패키지 정보 (최종 구조 K3/H3-E4-M2, 논문 기준선 K4/H4-E1) |
| `expected_results.md` | 여섯 재현 수준의 기대값 원문 |
| `metric_guardrails.md` | 지표를 섞지 않기 위한 네 가지 규칙 원문 |
| `reproduction_levels.md` | 재현 수준 R0~R6 표 원문. 명령은 패키지 러너 이름입니다 |
| `not_bundled.md` · `missing.md` | 패키지가 일부러 뺀 것과 나중에 채울 것의 원문 |
| `sha256_final_rtl.txt` | 최종 RVX 소스 sha256 |
| `sha256_publication_src.txt` | ablation 공통소스 · top · TB sha256 |
| `sha256_standalone_rtl.txt` | standalone RTL sha256 (파일은 trash_bin 쪽) |
| `sha256_all.txt` | 패키지 전체 파일 sha256 (경로는 패키지 배치 기준) |
| `internal_verify.txt` | 패키지를 만들 때의 자체 감사 기록 원문 |
