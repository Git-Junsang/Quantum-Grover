# DRAM Variant 대 BRAM Board-Verified Build — 500 workloads 대조

## 무엇인가

두 variant를 같은 표본에서 맞댄 결과입니다. `make -C hardware_dram/sim bench500`이
같은 testbench(`tb_dram_bench500.v`)를 DRAM Variant core와 `hardware_bram/src/`의
Board-Verified Build core(final configuration)에 각각 물려 500 workloads를 돌립니다.

- workload: 1/4/16/64/256 solutions × 100 seeds = **500**. board 500 runs · Six-Stage
  Ablation이 쓴 것과 같은 roster입니다
- variant 셋: `dram` / `bram normal`(mode0) / `bram ckpt`(final configuration)
- 설정: `predicate=EQ`, `threshold_a=12345`, `data_count=16384`, `auto_shot=1`,
  `shot_cap=100`, `enum_enable=0`
- Bus Interface는 끼지 않습니다. DRAM Variant에 아직 없으므로 두 variant 모두 Accelerator Core
  port를 직접 흔듭니다

250쌍 testbench(50 seeds)를 500으로 올린 이유는 source of truth 근거와 표본을 맞추기
위해서입니다. 250쌍 roster로는 board 500 runs · Six-Stage Ablation campaign과 총합을 맞댈 수 없습니다.

## 이 cycle은 board와 같은 축입니다

Bus Interface 없이 잰 값인데도, bram core를 물린 쪽이 두 source of truth 근거와 cycle까지
같습니다.

| 대조 상대 | 일치 |
|---|---:|
| `hardware_bram/configurations/final/results/2026-09-10_bench500_final_core/` (driver harness) | Restart mode 500/500, Checkpoint mode 500/500 |
| `hardware_bram/configurations/final/vivado/.../2026-09-08_k3h3_e4_m2_board_500run/per_run_m2.csv` | 500/500 |

`CSR_CYCLE_COUNT`의 계측 구간이 search 자체라 Bus Interface가 끼든 안 끼든 바뀌지
않기 때문입니다. 그래서 아래 `dram` 대 `bram ckpt` 비교는 board benchmark와 같은 cycle 축
위에 있습니다.

## 정합성 — 세 variant가 같은 계산을 합니다

`trial_count` · `L_BBHT` · `result_index`가 **500/500 × 3 variants 전부 일치**하고
`config_error` 0 건입니다. DRAM Variant가 amplitude를 DRAM에서 복원해도
Board-Verified Build와 같은 답·같은 BBHT trajectory를 낸다는 근거입니다.

## 비용 — Board-Verified Build가 이깁니다

DRAM latency를 세 가지로 줘서 재었습니다. 어느 쪽이든 결론이 같습니다.

| DRAM latency | `dram` cycle | `bram ckpt` | 차이 | 승/무/패 (dram 기준) |
|---|---:|---:|---:|---|
| `fast` (WR 0 / RD 1) | 9,332,398 | 5,328,877 | **+75.13%** | 13 / 0 / 487 |
| `model` (WR 4 / RD 12, TB 기본) | 9,380,081 | 5,328,877 | **+76.02%** | 13 / 0 / 487 |
| `slow` (WR 9 / RD 31 + backpressure) | 11,893,069 | 5,328,877 | **+123.18%** | 1 / 0 / 499 |

number of solutions별로 보면 희소할수록 dram이 그나마 붙습니다 (`model` 기준).

| number of solutions | `bram ckpt` | `dram` | speedup |
|---:|---:|---:|---:|
| 1 | 2,232,584 | 3,000,246 | 1.34× |
| 4 | 1,323,661 | 2,368,906 | 1.79× |
| 16 | 892,367 | 1,882,407 | 2.11× |
| 64 | 543,909 | 1,281,787 | 2.36× |
| 256 | 336,356 | 846,735 | 2.52× |
| **전체** | **5,328,877** | **9,380,081** | **1.76×** |

mode0(Restart mode)과 맞대면 `model` latency에서 cycle -20.41%, `slow`에서 +0.91%로
거의 비깁니다. 즉 DRAM Variant는 checkpoint 없는 Restart mode와 비슷한 자리에 있고
Board-Verified Build의 Checkpoint mode에는 못 미칩니다.

## 왜 지는가 — latency 탓이 아닙니다

DRAM Variant는 executed iterations를 압도적으로 줄입니다.

| | `dram` | `bram ckpt` | |
|---|---:|---:|---|
| executed iterations | 245 | 9,582 | dram이 **39.11×** 적음 |
| iteration당 cycle | 38,091 | 556 | dram이 **68.5×** 비쌈 |

iteration을 39× 줄이고도 iteration 하나가 68× 비싸서 총합에서 집니다. 그리고 latency를
거의 0(`fast`)으로 줘도 +75.13% 라 **latency가 원인이 아닙니다.** enumeration round마다
512 rows를 DRAM checkpoint slot에 넣고 빼는 고정 비용이 원인이고, 이것은 MIG를 아무리 빠른
것으로 바꿔도 남습니다. 물리 binding을 붙이기 전에 이 고정 비용부터 줄일
방법(enumeration round 간 prefetch, buffer B 활용)을 봐야 한다는 뜻입니다.

## 경계

- **dram cycle은 동작 수준 DRAM model 위의 값입니다.** 물리 MIG/AXI binding은
  아직 없습니다. 인용할 때 어느 latency로 쟀는지 반드시 같이 적으십시오
- **buffer B를 쓰는 enumeration round 간 prefetch가 아직 없습니다.** 그 implementation이 붙으면
  iteration당 비용이 달라질 수 있으므로, 이 표는 현재 RTL 초안의 값입니다
- single search 전용입니다. `enum_enable=1`은 `config_error`로 거절합니다
- bram 쪽 mode0 cycle을 Six-Stage Ablation의 Stage 1과 맞대지 마십시오.
  저쪽은 `NUMBER_OF_PES=1` 별도 build입니다

## 재현

```bash
make -C hardware_dram/sim bench500              # TB 기본 지연
make -C hardware_dram/sim bench500 DLAT=fast    # 지연 0 에 가까운 상한
make -C hardware_dram/sim bench500 DLAT=slow    # 백프레셔까지 있는 하한
```

한 벌에 10분쯤 걸립니다 (dram 1분 + bram 8분 + report).

## file

| file | 내용 |
|---|---|
| `dram_fast.csv` · `dram_model.csv` · `dram_slow.csv` | DRAM Variant 500 workloads, latency 세 벌 |
| `bram.csv` | Board-Verified Build core 500 workloads × 2 modes (`normal` / `ckpt`) |
| `report.txt` | `sim/bench500_report.py` 출력 세 벌 |
