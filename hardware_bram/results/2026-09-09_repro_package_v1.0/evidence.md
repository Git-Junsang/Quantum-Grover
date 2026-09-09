# 재현 패키지 v1.0 — 반입 출처

## 무엇인가

이 저장소의 2026-09-09 갱신분이 어디서 왔는지 적어 둔 폴더입니다.
출처는 `BBHT_Grover_Reproduction_Package_v1.0_20260909` 한 벌이고,
`hardware_bram/SERVER-20260909T134037Z-1-001.zip` 로 받았습니다.

## 무엇을 가져왔고 무엇을 안 가져왔는가

가져온 것:

| 반입 위치 | 패키지 안 위치 |
|---|---|
| `hardware_bram/src/` | `02_FINAL_RTL/{src,include}` — 최종 K3/H3-E4-M2 RVX 소스 17개 |
| `hardware_bram/rvx/bbht_grover_upgrade.xml` | `02_FINAL_RTL/bbht_grover_upgrade.xml` |
| `hardware_bram/vivado/.../reports` · `meta` | `09_REFERENCE_RESULTS/full_rvx/` |
| `hardware_bram/vivado/.../2026-09-08_k3h3_e4_m2_board_500run/` | `09_REFERENCE_RESULTS/board_reference/` |
| `hardware_bram/vivado/.../2026-09-08_orca_1core_baseline/` | `09_REFERENCE_RESULTS/orca_reference/` |
| `hardware_bram/results/2026-09-08_publication_6stage/` | `09_REFERENCE_RESULTS/publication/` · `04_PUBLICATION_6STAGE/expected/` |
| `hardware_bram/results/2026-09-09_kh_isolated_e1/` | `05_KH_ISOLATED/expected/` |
| `hardware_bram/results/2026-09-08_resource_ablation_5config/` | `09_REFERENCE_RESULTS/resource/` |
| `hardware_bram/synth/` | `06_RESOURCE_SYNTHESIS/` |
| `hardware_bram/firmware/bbht_paper_bench/` | `08_RVX_INTEGRATION/hw_realtime_firmware/source/` |
| `hardware_bram/firmware/orca_sw_baseline/` | `08_RVX_INTEGRATION/orca_sw_baseline/` |
| `hardware_bram/bitstream/2026-09-08_k3h3_e4_m2/` | `09_REFERENCE_RESULTS/full_rvx/` · 두 펌웨어 ELF |

일부러 안 가져온 것:

- `04_PUBLICATION_6STAGE/{src,tops,tb,scripts}` · `05_KH_ISOLATED/{tops,scripts}` —
  ablation 재현 소스. 결과와 기대값만 근거로 두기로 했습니다
- `07_STANDALONE_FPGA/` — RVX 없이 UART-APB 로 도는 독립 갈래. 이 저장소는
  RVX 통합판만 유지합니다
- `08_RVX_INTEGRATION/docs/` — **구 스펙 문서입니다.** 17장 해설서의 옛 판본이라
  `arty-50` · `xc7s50csga324-1` 로 적혀 있습니다. 저장소의
  `documents/study_references/17_RVX_SoC_통합.md` 가 최신입니다
- `11_OPTIONAL_CHECKPOINT_DSE/` — 옛 DSE 하네스와 18 MB 원본 CSV
- `BBHT_Grover_Reproduction_Package_v1.0_20260909.tar.gz` — 패키지 자체 아카이브

## 정합성 확인

`hardware_bram/src/` 17개 파일의 sha256 이 `sha256_final_rtl.txt` 및
`../../vivado/vivado_bbht_grover_fpga/meta/source_sha256.txt` 와 **전부 일치**합니다.
즉 저장소의 RTL 은 2026-09-07 비트스트림에 들어간 것과 바이트 동일합니다.

## 파일

| 파일 | 내용 |
|---|---|
| `package_info.txt` | 패키지 정보 (최종 구조 K3/H3-E4-M2, 논문 기준선 K4/H4-E1) |
| `expected_results.md` | 여섯 재현 수준의 기대값 원문 |
| `metric_guardrails.md` | 지표를 섞지 않기 위한 네 가지 규칙 원문 |
| `sha256_final_rtl.txt` | 최종 RVX 소스 sha256 |
| `sha256_publication_src.txt` | ablation 공통소스 sha256 |
