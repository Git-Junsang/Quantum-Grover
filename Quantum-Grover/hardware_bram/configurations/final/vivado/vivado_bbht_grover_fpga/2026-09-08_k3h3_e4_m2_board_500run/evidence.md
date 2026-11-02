# final configuration board benchmark — 500 workloads

## 무엇인가

**final configuration**을 Arty A7-100T 에 올려 500 workloads를 돌린 benchmark입니다.
같은 workload를 Restart mode와 Stage 2(a Checkpoint-Capacity of 4 · 4-shot Lookahead)로도 돌려서 세 구성을 한 표에 놓았습니다.
재현 package `BBHT_Grover_Reproduction_Package_v1.0_20260909` 의
`09_REFERENCE_RESULTS/board_reference/` 에서 가져왔습니다.

workload는 **1/4/16/64/256 solutions × 100 seeds = 500** 이고, seed roster는
Six-Stage Ablation campaign과 같습니다. 앞선 2026-09-01·2026-09-04 묶음의 250쌍
(50 seeds)과는 roster가 다르므로 총합을 직접 맞대면 안 됩니다.

## 확정 수치 — wall-clock time

| number of solutions | Restart mode (mode0) | Stage 2 (mode1) | final configuration (mode1) | final configuration / Restart mode | final configuration / Stage 2 |
|---:|---:|---:|---:|---:|---:|
| 1 | 209,754 µs | 72,598 µs | 22,818 µs | 9.192× | 3.182× |
| 4 | 106,615 | 40,806 | 13,748 | 7.755× | 2.968× |
| 16 | 61,934 | 26,272 | 9,432 | 6.566× | 2.785× |
| 64 | 30,990 | 15,620 | 5,942 | 5.215× | 2.629× |
| 256 | 16,209 | 9,601 | 3,858 | 4.201× | 2.489× |
| **전체** | **425,502** | **164,897** | **55,798** | **7.626×** | **2.955×** |

- median 525.0 / 235.5 / **87.5** µs, p95 2,810 / 929 / **285** µs
- solution이 희소할수록 이득이 큽니다 (1 solution에서 9.19×, 256 solutions에서 4.20×)
- 논리 동치: `crosscheck.txt` — Stage 2 500 rows 대 final configuration 500 rows, semantic mismatch 0

## cycle 축과 wall-clock time 축을 섞지 마십시오

이 묶음은 **board wall-clock time** 근거입니다. Six-Stage Ablation
(`results/2026-09-08_publication_6stage/`) 은 **RTL cycle** 근거이고, 둘은 다른
축입니다. 재현 package의 metric guardrail 이 명시적으로 요구하는 구분입니다.

두 축을 실제로 맞대 보면 이렇습니다. 500 workloads 전부에서 `result_index`,
`trial_count`, `L_BBHT` 가 **500/500 일치**합니다 — BBHT trajectory는 같습니다.
그런데 `cycle_count` 는 다릅니다.

| | board sum | RTL sum | workload별 차이 |
|---|---:|---:|---|
| Restart mode | 42,300,932 | 42,308,335 | RTL 이 1~31 cycles 더 큼 |
| final configuration | 5,328,877 | 6,890,470 | 473/500 이 정확히 3,279 cycles, 6건이 0 |

Restart mode 쪽 한 자리 수 차이는 계측 구간이 조금 다른 정도로 보입니다. final configuration 쪽
3,279 cycles는 거의 모든 workload에 똑같이 붙는 고정 항이고, 첫 workload
(1 solution, seed 0) 에서만 0 입니다 — board는 연속 실행이라 이 비용을 처음 한 번만
내고 RTL 은 매 실행 내는 것으로 보이지만, **원인을 확인하지는 않았습니다.**
그러니 board cycle과 RTL cycle로 speedup을 만들지 마십시오. board에서는
wall-clock time을, RTL 에서는 cycle을 인용하십시오.

## file

| file | 내용 |
|---|---|
| `summary.csv` | 세 구성 × number of solutions별 집계 (sum·mean·median·p95·minimum·maximum) |
| `per_run_m2.csv` | final configuration 500 runs 원본 (seed·결과·BBHT trajectory·timer) |
| `per_run_normal.csv` | Restart mode(mode0) 500 runs 원본 |
| `per_run_k4h4.csv` | Stage 2(mode1) 500 runs 원본 |
| `speedup_k4h4.csv` | Stage 2 대 Restart mode, number of solutions별 speedup |
| `crosscheck.txt` | Stage 2 대 final configuration 논리 동치 확인 |

`per_run_*.csv` 의 `elapsed_us` 는 RVX 실시간 timer이고 계측 구간은 search
호출뿐입니다 — solution 설정과 `printf` 는 빠져 있습니다.

## implementation

이 benchmark를 낸 bitstream과 implementation report는 같은 project directory 안에 있습니다.

- `../reports/` — routing report (WNS +0.126 ns, TNS 0, LUT 45,284 / FF 45,223 / BRAM 116 / DSP 132)
- `../meta/build_info.txt` — platform `bbht_grover_upgrade`, Vivado 2024.2, 2026-09-07 build
- `../meta/source_sha256.txt` — 그 build에 들어간 RTL 의 sha256. `hardware_bram/src/` 와 byte 동일합니다
- `../../../bitstream/2026-09-08_k3h3_e4_m2/` — bitstream과 firmware ELF
