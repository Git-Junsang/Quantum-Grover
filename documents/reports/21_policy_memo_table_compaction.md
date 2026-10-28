# 실험 21. a Checkpoint-Capacity of 3 and 3-shot Lookahead policy memo table 압축

> [← 실험 20](20_200mhz_implementation.md) · [실험 보고서 index](index.md)

## 목적

Policy Engine의 reset 직후 및 epoch 순환 initialization이 3,279 cycles을 차지하던 원인을 확인하고,
a Checkpoint-Capacity of 3 and 3-shot Lookahead에서 실제 도달하는 state만 저장해 initialization latency와 BRAM 요구량을 줄였습니다.

## 변경

a Checkpoint-Capacity of 3 and 3-shot Lookahead의 universe ID는 0..6, state set 크기는 최대 3이므로 동결된 combination rank의 maximum은
126입니다. 단계 보폭을 1,093에서 127로 줄여 세 단계의 live entry를 3,279개에서 381개로
줄였습니다. 공용 100 MHz source와 별도 200 MHz overlay에 같은 변경을 적용했고, 다른 Checkpoint-Capacity · Lookahead-Shots
configuration은 기존 배치를 유지했습니다.

## 결과

- memo table 청소 길이: 3,279 → 381 cycles, 시작 또는 epoch 순환당 2,898 cycles 감소
- 공용 RTL `real`: T1~T10 및 driver D1~D11 통과, 오류 0
- 200 MHz overlay `real`: T1~T10 및 driver D1~D11 통과, 오류 0
- 모든 BRAM configuration lint 통과
- 네 predicate quick 교차 regression 400건에서 공용/200 MHz 모두 software 기준 통과, cycle 외 전 열 400/400 일치
- Vivado OOC synthesis는 유효한 license를 얻지 못해 resource 수를 새로 확정하지 못함

명령과 주요 counter는
[`2026-10-26_policy_memo_compact/evidence.md`](../../hardware_bram/results/2026-10-26_policy_memo_compact/evidence.md)에
기록했습니다.

## 해석

이번 변경은 initialization과 epoch 순환의 고정 latency를 제거하는 저위험 수정입니다. 공용 100 MHz
Policy Engine의 memo table hit 발행률은 이미 1 action/cycle입니다. 200 MHz overlay에는 5 ns timing을
위해 combination generator 갱신을 두 단계로 나눈 별도 1 action/2 cycles 제한이 남아 있습니다. 이를 없애려면
연속 non-root 결과의 best-cost forwarding과 implementation timing을 함께 검증해야 하므로 이번 변경에
섞지 않았습니다.
