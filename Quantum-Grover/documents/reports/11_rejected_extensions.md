# 실험 11. 채택하지 않은 확장과 variant

> [← 실험 10 Two-Track Execution과 Pass 2–Build Fusion: 채택하지 않은 두 시도](10_two_track_execution_and_pass2_build_fusion.md) · [index](index.md) · [실험 12 Board-Verified Build 500 workloads →](12_board_verified_build_500_runs.md)

---

| 정한 것 | 근거의 축 |
|---|---|
| 15 qubits · 16 qubits · 64 lanes 확장과 그 밖의 variant를 채택하지 않음 | 추정 · 감사 |

## 규모 확장

| 후보 | state vector 크기 | rows / pass | 2-pass Grover iteration lower bound |
|---|---:|---:|---:|
| 14 qubits · 32 lanes · 22 fraction bits | 46 KiB | 512 | 1,024 cycles |
| 15 qubits · 32 lanes · 22 fraction bits | 92 KiB | 1,024 | 2,048 cycles |
| 16 qubits · 32 lanes · 22 fraction bits | 184 KiB | 2,048 | 4,096 cycles |
| 14 qubits · 64 lanes · 22 fraction bits | 46 KiB | 256 | 512 cycles |

FSM · BRAM latency · pipeline 비용을 뺀 이상적 lower bound입니다. 15 qubits · 16 qubits는 precision([실험 02](02_amplitude_precision.md))와 BRAM
budget에서, 64 lanes는 resource에서 폐기하고 14 qubits · 32 lanes로 굳혔습니다. 실제로 cycle을 줄인 것은 규모 확장이
아니라 Grover iteration 안의 병렬화(4 PEs)와 Measurement Unit(Dual-Row Build · Two-Level Select)였습니다.

## 독립 FPGA variant

RVX 없이 UART-APB bridge와 on-chip dataset generator로 도는 standalone 구성이 있었습니다. 4 PEs · Dual-Row Build · Two-Level Select를
처음 실험한 틀이지만, 임의 data를 올릴 수 없고 UART 왕복 때문에 system 속도도 RVX 통합 revision보다 느려
final configuration에 쓰지 않았습니다. 이 저장소는 RVX 통합 revision만 유지하고, Six-Stage Ablation과 Checkpoint-Capacity · Lookahead-Shots 단독 실험의
재현은 tag `board-verified-build-2026-09-07`에서 합니다([2장 2.2절](../design_references/02_development_environment_and_toolchain.md#22-저장소-regression-verilator)).

## 2026-08 interface 감사에서 남은 규칙

CSR · base address · enumeration 경계가 정해지기 전(2026-08-22), 당시 GitHub revision(15 qubits · Q2.16 · runtime에 바꾸는
number of qubits)과 전달 RTL(v0.7g) · reference model을 맞대 미결을 목록으로 만들었습니다. 미결은 v0.9.8에서
전부 닫혔고, 그 감사가 짚은 것 가운데 지금도 지키는 규칙은 이렇습니다.

| 발견 | 지금의 규칙 |
|---|---|
| DMA Engine이 서로 다른 address가 아니라 쓰기 개수만 셈 | wrapper가 `0..DATA_COUNT-1`을 정확히 한 번씩 생성 ([12장 12.7절](../design_references/12_accelerator_core_port_contract.md#127-loader-transaction)) |
| 홀수 `DATA_COUNT`의 마지막 halfword | DMA Engine이 쓰지 않음. 써도 Accelerator Core가 무시 |
| `done`은 1-clock pulse, 결과와 state는 sticky | mmio의 `done_sticky`. 지우는 것은 `COMMAND` 쓰기뿐 |
| "실패 후 collapse state" 라는 표현 | checkpoint는 measurement 직전 state ψ_j. measurement는 amplitude를 읽기만 함 |
| GitHub revision과 전달 RTL의 amplitude constant 혼용 위험 | SoC 구조만 참고하고 산술 · bit width는 14 qubits · 22 fraction bits 기준 |
