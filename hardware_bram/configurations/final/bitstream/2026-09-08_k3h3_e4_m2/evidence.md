# final configuration의 Board-Verified Build bitstream과 firmware

## 무엇인가

500 workloads board benchmark와 ORCA baseline을 낸 실물 묶음입니다. platform 이름은
`bbht_grover_upgrade`(지금 `bbht_grover_final`), board는 Arty A7-100T (`xc7a100tcsg324-1`), accelerator clock
100 MHz, Vivado 2024.2, build 2026-09-07 입니다.

| file | 내용 |
|---|---|
| `arty-100t.bit` | RVX SoC + accelerator 전체 bitstream |
| `bbht_paper_bench.elf` | 실시간 benchmark app. number of solutions 5가지 × 100 seeds를 Restart mode · Checkpoint mode 짝으로 돌립니다 |
| `orca_sw_baseline.elf` | accelerator를 안 쓰는 ORCA 1 core baseline app |
| `sha256sums.txt` | 위 셋의 hash |

세 hash 모두 재현 package의 원본 manifest와 일치합니다.

## 이 bitstream이 낸 것

- implementation report — `../../vivado/vivado_bbht_grover_fpga/reports/`
  (WNS +0.126 ns, TNS 0, WHS +0.016 ns, LUT 45,284 / FF 45,223 / Slice 15,214 / BRAM 116 / DSP 132)
- board benchmark 500 runs — `../../vivado/vivado_bbht_grover_fpga/2026-09-08_k3h3_e4_m2_board_500run/`
- ORCA baseline 500 runs — `../../vivado/vivado_bbht_grover_fpga/2026-09-08_orca_1core_baseline/`

## source와의 대응

`../../vivado/vivado_bbht_grover_fpga/meta/source_sha256.txt` 가 이 bitstream에
들어간 RTL 의 sha256 을 적고 있고, tag `board-verified-build-2026-09-07` 의 `hardware_bram/src/`
17 files와 **byte 동일**합니다. main 의 `src/` 는 그 뒤 revision 한 벌로 정리했습니다. firmware source는 `hardware_bram/firmware/bbht_paper_bench/` 와
`hardware_bram/firmware/orca_sw_baseline/` 입니다.

## 굽는 법

```bash
source /opt/rvx/rvx_setup.sh
hardware_bram/configurations/final/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_final && make syn && make arty-100t
```

이미 구워진 위 `.bit` 를 그대로 쓰려면 RVX 의 다운로드 경로에 넣으십시오.
bitstream만 바꾸고 app을 다시 올리려면 `.elf` 두 개를 씁니다.
