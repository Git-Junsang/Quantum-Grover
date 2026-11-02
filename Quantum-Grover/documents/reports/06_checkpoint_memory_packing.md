# 실험 06. checkpoint memory packing

> [← 실험 05 checkpoint policy algorithm 선정](05_checkpoint_policy_selection.md) · [index](index.md) · [실험 07 Lookahead-Shots를 줄인 이유: 8 → 6 → 4 → 3 shots →](07_lookahead_shots_reduction.md)

---

| 정한 것 | 근거의 축 |
|---|---|
| checkpoint slot당 RAMB36 11개 packing, future-only memo table | synthesis · OOC |

state vector 한 벌은 16,384 × 23 = 376,832 bits이고 RAMB36E1 하나가 36,864 bits라 이론 lower bound는 10.22개,
즉 11개입니다. implementation은 그 lower bound를 달성했습니다.

```
row 736 bits = 10 × 69 bits + 1 × 46 bits     (lane 0~29 를 세 개씩 묶어 69-bit 열 개, lane 30~31 을 46 bits)
state vector 한 벌 = RAMB36E1 11개
a Checkpoint-Capacity of 3 = 33개, a Checkpoint-Capacity of 4 = 44개
```

512 rows 전체와 sign · 경계 · 무작위 패턴, 독립 읽기/쓰기, 덮어쓰기를 32 × 23 기준 implementation과 비교한
bit-exact testbench가 통과했습니다. 이 결과로 "state vector 한 벌에 BRAM 16개" 라던 이전 추정을 버렸습니다.
checkpoint slot 읽기 mux(3:1 · 4:1)는 OOC에서 둘 다 RAMB36 → LUT6 1단 → 출력 register 경로로 100 MHz를
+6.579 ns 여유로 닫았습니다.

policy memo table은 root action을 매번 직접 평가하고 미래 단계만 저장하는 future-only 방식으로 굳혔습니다.
entry는 10-bit 비용 + 8-bit epoch = 18 bits이고, epoch가 다른 entry는 hit로 보지 않습니다.
a Checkpoint-Capacity of 4 and 8-shot Lookahead에서 8 × 1,093 = 8,744 entries가 RAMB36 5개로 구현됐고, Lookahead-Shots를 줄이며 number of banks도 줄었습니다.
지금의 a Checkpoint-Capacity of 3 and 3-shot Lookahead는 `STATE_RANKS = 1,093` stride를 그대로 두고 3 × 1,093 = 3,279 entries를 씁니다. reset
뒤 이 memo table을 한 칸씩 지우는 길이가 3,279 cycles이고, board와 RTL campaign의 cycle 차이가 여기서
나옵니다([11장 11.5절](../design_references/11_checkpoint_and_policy_engine.md#115-memo-table-initialization-3279--381-cycles)).

4 PEs에서는 네 bank가 state vector 네 벌의 복제가 아니라, state vector 하나를 row index mod 4로 나눈 bandwidth 구조입니다.
checkpoint slot이 Checkpoint-Capacity와 무관하게 4벌이라 Checkpoint-Capacity를 4에서 3으로 줄여도 BRAM이 줄지 않습니다([6장 6.7절](../design_references/06_data_representation_and_memory_map.md#67-memory-구조)).
