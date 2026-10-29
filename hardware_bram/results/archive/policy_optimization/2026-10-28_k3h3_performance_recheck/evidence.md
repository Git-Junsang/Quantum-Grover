# a Checkpoint-Capacity of 3 · 3-shot Lookahead 전체 실행 성능 재확인 — 2026-10-28

같은 configuration(a Checkpoint-Capacity of 3 · 3-shot Lookahead · 4 PEs · Triple-Row Build · policy search mode 6)의 Common500을 다시 simulation하고 결과를 검증했습니다.
policy 계산량은 크게 감소했지만, 직전 revision 대비 전체 실행 cycle 개선은 0.005129%입니다.
Checkpoint-Capacity 1~10 × Lookahead-Shots 1~10 구조 확장과 100 cells 실행은 이 결과를 평가한 뒤 결정하는 다음 단계로 남겼습니다.

## 재실행과 정확성

`inputs.json`에 원본 source manifest, native Verilator model binary hash와 실행 환경을 기록했습니다.
원본 manifest의 모든 source·입력 hash가 현재 workspace와 일치함을 확인한 뒤 이미 compile된
같은 RTL model을 사용해 Common500을 새로 실행했습니다. RTL을 다시 compile한 작업은 아닙니다.

- 500 workloads, Restart mode/Checkpoint mode 결과 1,000 rows.
- `dse.validate_bench`로 reference model의 request BBHT trajectory, 결과, shot, requested iterations, workload별 executed iterations를 검증.
- 새 `bench.csv`는 직전 최종 benchmark file과 byte-identical입니다. 재실행은 `run.log`, `sim.log`, `sim.json`입니다.
- 두 baseline과 결과 · shot · requested/executed iterations · mismatch가 전부 같으며 Restart mode row의 모든 field가 같습니다.
- executed iterations는 모든 비교 revision에서 9,582 iterations로 동일합니다.

검증한 policy SHA는 `5aa95f551cc74e0b5ff5454df775fc13bf241ed0557bc792fa348ba347818b3d`,
Accelerator Core SHA는 `d949759b1dc3ae85b4d1b4f336f00f3636c1e94c8c47bee0737eb42f8b306712`입니다.

## Common500 통합 accelerator RTL cycle

| 지표 | Build·cache 개선 전 | 직전 검증 revision | 이번 재실행 |
|---|---:|---:|---:|
| 전체 policy cycles | 239,873 | 161,272 | 80,719 |
| 실제 policy stall | 22,298 | 17,715 | 17,483 |
| 전체 Checkpoint mode 실행 cycles | 4,549,854 | 4,523,062 | 4,522,830 |

세 revision은 a Checkpoint-Capacity of 3 · 3-shot Lookahead · 4 PEs · Triple-Row Build · Two-Level Select, policy search mode 6, Common500과 executed iterations 규칙이 같습니다.
원자료는 [Build·cache 개선 전](../2026-10-28_policy_gap_bound_final/k3h3_e4_b3_p6/sim.json),
[직전 검증 revision](../2026-10-28_policy_parallel_paths_verified/k3h3_e4_b3_p6/sim.json),
이번 `sim.json`입니다. `compare.py`가 불변 field를 검증하고 `comparison.csv`·`comparison.json`을 만듭니다.

직전 revision 대비 policy 계산량은 80,553 cycles, 49.9485% 감소했습니다. stall은 232 cycles,
1.3096% 감소했고 전체 실행도 정확히 같은 232 cycles, 0.005129% 감소했습니다.
Build·cache 개선 전부터 누적하면 policy 계산 66.3493%, stall 21.5939%, 전체 실행 0.5940% 감소입니다.

## 의미와 다음 판단

현재 a Checkpoint-Capacity of 3 · 3-shot Lookahead에서 solver는 실제 계산 중 다음 계획을 미리 구합니다. 계산량 감소 대부분이 이미
겹쳐 있던 시간에서 발생하므로 전체 실행 시간의 같은 비율 감소를 뜻하지 않습니다. 최신 실행에서
실제 policy stall은 전체 Checkpoint mode 실행의 약 0.3866%입니다.

policy 계산 throughput과 향후 더 큰 Checkpoint-Capacity · Lookahead-Shots와 더 많은 PEs · 더 빠른 Build를 위한 여유 확보에는 개선이 있습니다.
그러나 현재 a Checkpoint-Capacity of 3 · 3-shot Lookahead의 직접적인 전체 실행 가속만으로 평가하면 직전 revision 대비 이득은 작습니다.
이 결과만으로 Checkpoint-Capacity 1~10 × Lookahead-Shots 1~10 확장의 실제 stall 개선이나 성능을 확정하지 않습니다.

큰 Checkpoint-Capacity · Lookahead-Shots sweep을 준비하던 a Checkpoint-Capacity of 3 · 8-shot Lookahead pilot은 사용자의 범위 변경에 따라 완료 전에 중단했습니다.
그 실행에서 cycle 값을 추정하지 않았습니다. RTL 구조 변경이나 100 cells 실행은 하지 않았습니다.

## verification 범위와 남겨 둔 implementation

이번 4백만대 cycle은 driver를 연결한 **통합 accelerator RTL** Common500 결과입니다.
전체 RVX SoC console의 elapsed simulation time과 같은 지표가 아닙니다. 같은 최종 RTL의
전체 RVX SoC는 [기존 verification 묶음](../2026-10-28_policy_scan_parallel_verified/evidence.md)에서
Questa Errors 0 / Warnings 0 및 RUN·STAT·ENUM 90항목 일치로 검증했습니다. 이번에는 재실행하지 않았습니다.

기존 200T placement and routing background 작업은 그대로 두었고 이번 작업에서 상태·결과를 조회하지 않았습니다.
RTL도 변경하지 않았으며 commit하지 않았습니다. board benchmark는 수행하지 않았습니다.

## 재현

원본 snapshot은 `../2026-10-28_policy_scan_parallel_verified/source/`, 원본 config는 그 directory의
`config.json`입니다. 해당 config로 `dse.py --stages policy,sim,report`를 새 출력 directory에서
실행하면 다시 compile하고 잴 수 있습니다. 이번에 사용한 native binary 경로·hash·환경은
`inputs.json`에 보존했습니다. `compare.py`는 같은 두 기준 revision과 다시 대조합니다.

문서 검사에는 기존 오류 62건·경고 6건이 남아 있습니다. 이번 문서 추가 전후 새 진단은 없습니다.
