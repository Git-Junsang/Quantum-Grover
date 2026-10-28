# Board-Verified Build core 500 workloads RTL testbench — board benchmark와 cycle까지 500/500 일치

## 무엇인가

`hardware_bram/src/` 의 Board-Verified Build core(final configuration)를 `make -C hardware_bram/sim bench500`
으로 500 workloads(1/4/16/64/256 solutions × 100 seeds)에 걸어 돌린 결과입니다. Bus Interface도
Board-Verified Build 그대로이고, 자극은 실제 driver(`bbht_grover_driver.c`)를 그대로 compile해 넣습니다.

`2026-09-10_bench250_final_core` 와 같은 방식인데 seed roster가 100쌍입니다.
seed roster는 board 500 runs·Six-Stage Ablation campaign이 쓴 것과 같고, 앞 50쌍이
250쌍 testbench의 roster와 같습니다 (dump 도구가 매번 확인합니다).

500개를 **한 process에서 reset 없이 연달아** 돕니다. board app
(`firmware/bbht_paper_bench/src/main.c`) 이 number of solutions 바깥 loop · seed 안쪽 loop ·
seed마다 Restart mode 다음 Checkpoint mode 순서로 500개를 한 번에 도는데, 그 순서를 그대로
맞춘 것입니다. 이것이 250쌍 testbench와의 유일한 실질 차이이고, 아래 4절이 그 차이가
무엇을 낳는지입니다.

## 확정 수치

| 항목 | mode0 | mode1 (final configuration) |
|---|---:|---:|
| executed iterations | 31,424 | 9,582 (-69.51%) |
| cycle | 11,785,382 | 5,328,877 (-54.78%) |
| policy stall | — | 172,066 (Checkpoint mode cycle의 3.23%) |
| 총 shot | 7,403 | 7,403 |
| Plan Queue miss | — | 0 |

BBHT trajectory 불변식 **500/500 일치** — 같은 seed에서 mode0 과 mode1 이 `trial_count` 와
`L_BBHT` 를 같게 냅니다.

## 500 workloads 두 근거와의 대조

셋 다 workload가 같습니다. BBHT trajectory 열 넷(`result_index` · `trial_count` · `L_BBHT` · `actual_iter`)은 셋이 전부 같습니다.

| 대조 상대 | result_index | trial_count | L_BBHT | actual_iter | cycle_count |
|---|---:|---:|---:|---:|---:|
| final configuration board benchmark (`vivado/.../2026-09-08_k3h3_e4_m2_board_500run/per_run_m2.csv`) | 500/500 | 500/500 | 500/500 | 500/500 | **500/500** |
| Six-Stage Ablation final configuration (`results/2026-09-08_publication_6stage/observations.csv`) | 500/500 | 500/500 | 500/500 | 500/500 | 6/500 |

**board와 cycle이 workload 하나까지 전부 같습니다.** 합계도 5,328,877 대
5,328,877 로 error 0 입니다.

| number of solutions | 이 testbench | board final configuration | Six-Stage Ablation final configuration |
|---:|---:|---:|---:|
| 1 | 2,232,584 | 2,232,584 | 2,534,469 |
| 4 | 1,323,661 | 1,323,661 | 1,636,791 |
| 16 | 892,367 | 892,367 | 1,199,262 |
| 64 | 543,909 | 543,909 | 858,971 |
| 256 | 336,356 | 336,356 | 660,977 |
| **전체** | **5,328,877** | **5,328,877** | 6,890,470 |

Six-Stage Ablation campaign 쪽이 큰 것은 algorithm 차이가 아닙니다. workload별로 빼 보면
**473/500 이 정확히 +3,279 cycles**이고 6건이 0, 나머지 21건만 제각각입니다.
누적이 아니라 run당 붙는 고정 항입니다.

| number of solutions | +3,279 인 건수 | 0 인 건수 |
|---:|---:|---:|
| 1 | 91/100 | 3 |
| 4 | 94/100 | 0 |
| 16 | 93/100 | 0 |
| 64 | 96/100 | 2 |
| 256 | 99/100 | 1 |

256 solutions에서 비율 차이가 -49% 로 커 보이는 것도 이 고정 항 때문입니다. 256 solutions는
workload 한 건이 3,364 cycles 남짓이라 3,279 가 상대적으로 크게 보일 뿐입니다.

## 250쌍 testbench와의 관계 — 실행 길이가 cycle을 바꿉니다

앞 50 seeds의 250 workloads를 `2026-09-10_bench250_final_core` 와 맞대면 BBHT trajectory 열 넷은
250/250 이고 **cycle만 230/250** 입니다. 어긋난 20건은
`(4,4) (4,9) (4,17) (4,31) (4,36) (4,45) (4,49) (16,1) (16,10) (16,16) (16,25)
(16,32) (16,43) (64,13) (64,16) (64,37) (64,40) (256,6) (256,11) (256,42)` 이고,
이것은 250쌍 testbench가 board와 어긋났던 20건과 **정확히 같은 집합**입니다.

즉 250개만 돌면 그 20건이 board와 다르게 나오고, 500개를 board와 같은 순서로
연달아 돌면 500건 전부가 board와 같아집니다. 250쌍 testbench가 세워 두었던
"board는 500 workloads를 연달아 돌아 checkpoint 준비 비용을 앞에서 한 번만
낸다" 는 가설이 이것으로 확인됐습니다. 해당 20건은 연달아 도는 길이에 따라
준비 비용을 내느냐 마느냐가 갈리는 workload입니다.

이 확인은 250쌍 testbench의 대조 상대에도 적용됩니다 — 250쌍 testbench의 cycle
230/250 은 harness 결함이 아니라 실행 길이가 짧아서 생긴 것입니다.

## 이 숫자를 쓸 때의 경계

**mode0 cycle을 board `per_run_normal.csv` 나 Six-Stage Ablation Stage 1과 맞대지
마십시오.** 저 둘은 `NUMBER_OF_PES=1` 별도 build의 mode0(각각 42,300,932 ·
42,308,335 cycles)이고, 이 testbench의 mode0 은 Board-Verified Build `src/` 곧 4 PEs build의 mode0
입니다. 그래서 이 표의 같은 build 안 speedup 2.2116× 는 Six-Stage Ablation campaign의 6.1401×
와 다른 것을 재는 값이며, **성능 주장으로 쓸 수 없습니다.** Six-Stage Ablation speedup을
인용할 자리는 `results/2026-09-08_publication_6stage/` 입니다.

**cycle이 500/500 같다고 해서 board wall-clock time을 대신하지는 않습니다.** board
쪽 인용은 여전히 `elapsed_us` 축(`2026-09-08_k3h3_e4_m2_board_500run/`,
Restart mode 대비 7.626×)에서 하십시오. 이 testbench가 보탠 것은 Board-Verified Build RTL 이 board에서
돌 때의 cycle을 simulation으로 정확히 재현한다는 사실이지, 두 축을 섞어도 된다는
뜻이 아닙니다.

**reference model과는 여전히 일치하지 않습니다.** reference model은 Measurement PRNG의 random number 확장과
Checkpoint Planner가 가정이라 BBHT trajectory 재현기가 아닙니다.

## 재현

```bash
make -C hardware_bram/sim bench500              # Bus Interface + adapter + Accelerator Core
```

이 묶음을 낸 2026-09-10 에는 Bus Interface가 두 벌이라 같은 testbench를 Board-Verified Build
Bus Interface로도(`make bench500`), 우리 Bus Interface로도(`make bench500 CORE=real`)
돌렸습니다. 2026-09-13 부터 main 에는 우리 Bus Interface 한 벌뿐이라 위 명령이 뒤쪽
조합이고, 앞쪽 조합은 tag `board-verified-build-2026-09-07` 에서 돕니다.

이 환경(verilator 5.020)에서 40분쯤 걸립니다.

## file

| file | 내용 |
|---|---|
| `per_workload.csv` | 500 workloads × 2 modes 원본 (결과·BBHT trajectory·cycle·policy 계측) |
| `report.txt` | `sim/bench500_report.py` 출력 |
