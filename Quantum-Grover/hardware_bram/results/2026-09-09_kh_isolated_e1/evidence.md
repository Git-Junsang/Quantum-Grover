# Checkpoint-Capacity · Lookahead-Shots 단독 실험 — 1 PE, Single-Row Build · Linear Select (250 workloads)

## 무엇인가

Six-Stage Ablation에서 Checkpoint-Capacity와 Lookahead-Shots만 떼어 낸 보조 실험입니다.
PE는 한 벌(1 PE), Measurement Microarchitecture 최적화는 둘 다 끈 채(Single-Row Build · Linear Select)로 세 조합을 비교합니다.
같은 공통소스, 같은 TB, 1/4/16/64/256 solutions × 50 seeds = **250 workloads**,
configuration 3벌이니 750회 simulation입니다.

Checkpoint-Capacity와 Lookahead-Shots를 같이 줄일 때 정말로 이득인지, 아니면 둘 중 하나만 줄여도 되는지를
가르는 것이 목적입니다.

## 확정 수치

| configuration | 총 cycle | a Checkpoint-Capacity of 4 and 4-shot Lookahead 대비 |
|---|---:|---:|
| Stage 2 (대조군) | 8,836,298 | 1.000000× |
| a Checkpoint-Capacity of 3, 4-shot Lookahead and 1 PE | 8,818,101 | 1.002064× |
| a Checkpoint-Capacity of 3, 3-shot Lookahead and 1 PE | 8,596,609 | 1.027882× |

- a Checkpoint-Capacity of 3 and 3-shot Lookahead 대 a Checkpoint-Capacity of 3 and 4-shot Lookahead는 1.025765×
- verification: a Checkpoint-Capacity of 3 실행 500/500 PASS, 논리 불일치 0

읽는 법은 이렇습니다. **Checkpoint-Capacity를 4에서 3으로 줄이는 것만으로는 거의
차이가 없습니다 (0.21%).** 이득의 대부분은 Lookahead-Shots를 4에서 3으로 줄일 때
나옵니다 (2.58%). 즉 비싼 쪽은 저장 공간이 아니라 결정 비용입니다.

이 결론은 2026-09-04 묶음이 a Checkpoint-Capacity of 4 and 8-shot Lookahead 대 a Checkpoint-Capacity of 4 and 4-shot Lookahead에서 관찰한 것과 방향이 같습니다 —
Lookahead-Shots를 깊게 잡으면 Grover iteration은 조금 덜 쓰지만 policy stall이 그보다 크게
늘어납니다.

## 이 숫자를 쓸 때의 경계

- **cycle 축**입니다. board wall-clock time이 아닙니다.
- 1 PE, Single-Row Build · Linear Select 조건입니다. Six-Stage Ablation의 Stage 4 칸과는 조건이
  달라서 직접 맞대면 안 됩니다.
- 250 workloads(50 seeds)라 500 workloads campaign과 총합을 비교할 수 없습니다.
- TB 표시 문자열에 `k4h4`가 hard-coded로 남아 있습니다. 실제 instance
  parameter는 top file이 정하며 따로 감사됐다고 원 기록에 적혀 있습니다.
- 재현 source(top 3벌 · runner)는 tag `board-k3h3-e4-m2`에 있습니다. 거기서
  `make -C hardware_bram/sim kh`로 750회를 돌려 `summary.csv`와 맞댑니다.

## file

| file | 내용 |
|---|---|
| `summary.csv` | 세 configuration의 총 cycle과 상대비 |
| `workloads.csv` | 250 workloads 목록 (number of solutions × 50 seeds) |
