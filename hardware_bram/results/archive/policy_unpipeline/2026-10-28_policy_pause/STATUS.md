# Policy 작업 중단 지점 — 2026-10-28

사용자 request에 따라 실행 중이던 sorted-value 개선 revision의 200T OOC placement · routing까지 완료하고 중단했습니다. 추가 RTL 수정, 새 verification 실행, commit은 시작하지 않았습니다.

## 요청한 1~4단계 진행 상태

| 단계 | 상태 | 남은 작업 |
|---|---|---|
| 1. 현재 policy 변경 마무리 | 진행 중 | 최신 RTL의 전체 regression/SoC verification, full SoC WNS/WHS 통과, 첫 commit |
| 2. Scheduler 설계 고정 | 미착수 | 우선순위/refill/tag/epoch/flush/counter/interface/state도 확정 |
| 3. Scheduler RTL 분리·implementation | 미착수 | module 추가, Accelerator Core 연결, 단독/Common500/SoC verification, 두 번째 commit |
| 4. 200T policy 최적화 | 정식 단계 미착수 | 단계별 stall 계측, memo table/SCAN/bound/overlap 최적화, Checkpoint-Capacity · Lookahead-Shots 확장 시 성능 평가 |

## 완료한 기능 변경과 verification

- WNS용 `actionq/mreq/areq` 및 Build/PREP/evaluation의 latency 전용 단계를 제거했습니다. 동기 memo table 응답 정렬과 full-horizon bound의 algorithm 단계는 유지했습니다.
- timing 단축을 위해 active frame/request/value mirror, rank 기반 root tie-break, generator에서 직접 bound rank-mask 생성, 기존 bound 출력 단계로 ID sort 이동을 구현했습니다. 이 변경들로 policy cycle 추가는 없었습니다.
- sorted-value 직전 revision은 policy search mode 0~6의 a Checkpoint-Capacity of 3, 4-shot Lookahead sample, Checkpoint-Capacity 3 · 4 × Lookahead-Shots 1~8의 20-workload 16 cells, Common500 4 PEs · Triple-Row Build · Quad-Row Build를 통과했습니다.
- Common500: 7,403 decisions, standalone policy 285,140 cycles, 통합 policy 309,000 cycles. Triple-Row Build 총 4,554,476 cycles / stall 26,920; Quad-Row Build 총 4,236,749 / stall 27,522. 결과는 `../2026-10-28_policy_unpipeline_final/summary.csv`입니다.
- sorted-value 직전 revision의 full SoC Questa console: 5분 52초, Errors 0 / Warnings 0. 같은 source의 Verilator 참조와 RUN/STAT/ENUM 모든 field가 일치했습니다. 기존 checker의 mismatch 5건은 과거 final configuration cycle 증거와의 configuration 차이입니다.
- 같은 revision의 200T full SoC bitstream 생성 완료. WNS -0.013 ns / WHS +0.025 ns로 setup은 미통과입니다. LUT 52,138; FF 47,266; BRAM 113.5; DSP 196입니다.

## 방금 완료한 최신 revision

- active checkpoint 값을 오름차순으로 유지하고 PREP predecessor를 우선 선택하도록 변경했습니다.
- policy search mode 0~6의 a Checkpoint-Capacity of 3, 4-shot Lookahead 25-decision sample 전부 expected result 일치, cycle 동일.
- a Checkpoint-Capacity of 3, 3-shot Lookahead, 4 PEs, Triple-Row Build의 20-workload 통합 verification 통과: total 381,657 cycles, policy 21,300 cycles, stall 1,451.
- xc7a200tfbg484-2, 10 ns OOC route: WNS -0.114 ns / WHS +0.068 ns. setup 미통과입니다.
- latest worst path: `univ_val[1][2] -> f_val2[0][0]` (root value 정렬/설치 경로).
- 최신 revision은 전체 Checkpoint-Capacity · Lookahead-Shots regression, Common500, full SoC Questa/implementation을 아직 재실행하지 않았습니다. 이전 revision의 verification 결과를 최신 revision의 결과로 간주하면 안 됩니다.
- `latest_grover_policy.v`, `latest_ooc_*`에 최신 source와 report를 보존했습니다. 원래 실행 directory는 `/tmp/policy_sorted_values_b3`입니다.

## 재개 순서

1. 최신 root value 정렬/설치 경로를 줄이고 10 ns timing을 확인합니다.
2. 최신 RTL로 Checkpoint-Capacity · Lookahead-Shots regression, Common500, full SoC Questa 및 200T implementation을 확정합니다.
3. 검증된 RTL/결과만 첫 commit합니다. 기존 사용자 staged/unstaged 변경은 포함하지 않습니다.
4. 요청한 scheduler 설계·implementation·최적화(2~4단계)로 진행합니다.

현재 작업 관련 신규 commit은 없습니다. 기존 commit HEAD는 `7f4428c`입니다. board benchmark는 수행하지 않았습니다.
