# K3/H3-E4-M2 최종 비트스트림과 펌웨어

## 무엇인가

500 워크로드 보드 실측과 ORCA 기준선을 낸 실물 묶음입니다. 플랫폼 이름은
`bbht_grover_upgrade`, 보드는 Arty A7-100T (`xc7a100tcsg324-1`), 가속기 클럭
100 MHz, Vivado 2024.2, 빌드 2026-09-07 입니다.

| 파일 | 내용 |
|---|---|
| `arty-100t.bit` | RVX SoC + 가속기 전체 비트스트림 |
| `bbht_paper_bench.elf` | 실시간 벤치 앱. 5타겟 × 시드 100 을 Normal/최적화 짝으로 돌립니다 |
| `orca_sw_baseline.elf` | 가속기를 안 쓰는 ORCA 1코어 기준선 앱 |
| `sha256sums.txt` | 위 셋의 해시 |

세 해시 모두 재현 패키지의 원본 매니페스트와 일치합니다.

## 이 비트스트림이 낸 것

- 구현 리포트 — `../../vivado/vivado_bbht_grover_fpga/reports/`
  (WNS +0.126 ns, TNS 0, WHS +0.016 ns, LUT 45,284 / FF 45,223 / Slice 15,214 / BRAM 116 / DSP 132)
- 보드 실측 500런 — `../../vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/`
- ORCA 기준선 500런 — `../../vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/`

## 소스와의 대응

`../../vivado/vivado_bbht_grover_fpga/meta/source_sha256.txt` 가 이 비트스트림에
들어간 RTL 의 sha256 을 적고 있고, `hardware_bram/src/` 의 17개 파일과 **바이트
동일**합니다. 펌웨어 소스는 `hardware_bram/firmware/bbht_paper_bench/` 와
`hardware_bram/firmware/orca_sw_baseline/` 입니다.

## 굽는 법

```bash
source /opt/rvx/rvx_setup.sh
hardware_bram/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_upgrade && make syn && make arty-100t
```

이미 구워진 위 `.bit` 를 그대로 쓰려면 RVX 의 다운로드 경로에 넣으십시오.
비트스트림만 바꾸고 앱을 다시 올리려면 `.elf` 두 개를 씁니다.
