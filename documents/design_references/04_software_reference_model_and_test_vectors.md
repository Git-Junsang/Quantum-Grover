# 4장. software reference model과 test vector

> [← 3장 Grover와 BBHT algorithm](03_grover_and_bbht_algorithm.md) · [index](index.md) · [5장 hardware architecture 개요 →](05_hardware_architecture_overview.md)

---

RTL을 검증하려면 implementation과 독립된 기준값이 필요합니다. [`software/`](../../software/)가 그
기준값을 만들고, 두 hardware directory tree(BRAM Variant의 configuration들 · DRAM Variant)가 함께
씁니다. 한쪽 directory tree에만 필요한 code는 그 directory tree 안에 둡니다.

---

## 4.1 기준 구성과 directory

| 항목 | 값 |
|---|---|
| search space | 14 qubits, 16,384 states |
| parallelism | 32 lanes |
| 입력 | signed 16-bit |
| amplitude | signed Q1.22, 23-bit |
| oracle | `EQ` · `LT` · `GT` · `RANGE` |
| BBHT | 초기 sampling range 1, growth factor 6/5, sampling range 최대 128, BBHT budget 576 |
| 최종 checkpoint | a Checkpoint-Capacity of 3 and 3-shot Lookahead (비교용 이전 policy a Checkpoint-Capacity of 4 and 4-shot Lookahead) |
| FPGA 구성 | final configuration, accelerator 100 MHz |

값은 [`final_hardware_contract.py`](../../software/reference_model_develop/models/common/final_hardware_contract.py)
에 있고 CSR 쪽 기록인 [13장](13_csr_registers_and_execution_modes.md)과 같습니다.

```text
spec/                           register · port 규격 (RTL · firmware · host 공용)
software/
├── reference_model_develop/             reference model과 그 도구
│   ├── models/
│   │   ├── common/             공통 설정 · 결과 data type · dataset · BBHT 규약
│   │   └── rtl_reference_model/  Q1.22 bit-exact 와 checkpoint policy model
│   ├── tb_stimulus/            RTL testbench stimulus 생성기 (hardware Makefile 이 부름)
│   ├── common500/              Common500 비교 실험 script
│   └── predicate500/           Predicate500 expected result 생성기
├── reference_model_data/                reference model이 낸 test vector와 비교 결과
│   ├── 2026-09-02_requested_j_vectors/   requested iterations bit-exact 256 cases
│   ├── 2026-09-09_enumeration_vectors/   enumeration 두 방식 x 5 cases
│   ├── 2026-09-11_common500/             Common500 비교 결과 · 2026-09-11_common500.md
│   └── 2026-09-25_predicate500/          Predicate500 expected result CSV 두 개
├── testbench_data/             testbench · 실험이 읽는 입력
│   ├── 2026-09-08_common500/             Board-Verified Build dataset 5개 · seed roster 100쌍
│   └── 2026-10-05_predicate500/          Predicate500 dataset 20개
├── pc_grover_develop/          PC 용 Grover implementation (C++ · NumPy · Qiskit, 팀 원본 team_models/)
├── pc_grover_result/           그 benchmark 결과 (2026-10-05_server · 2026-10-05_devvm)
├── orca_grover_develop/        accelerator 없는 C 세 model (ORCA · x86 공용)
├── orca_grover_result/         그 benchmark 결과 (2026-10-11_predicate500)
└── host_fpga_develop/          host CLI 와 board 자동 test
```

data · 결과 directory 이름은 `YYYY-MM-DD_<내용>` 이고, directory마다 대표 문서가 directory와 같은 이름의 `.md` 로 있습니다.

---

## 4.2 세 layer의 reference model

| layer | 위치 | 무엇을 확인하나 |
|---|---|---|
| Float64 state vector | [`pc_grover_develop/team_models/numpy_model/`](../../software/pc_grover_develop/team_models/numpy_model/) | algorithm이 맞는지. fixed-point 영향이 없는 기준 |
| Qiskit Aer | [`pc_grover_develop/team_models/qiskit_model/`](../../software/pc_grover_develop/team_models/qiskit_model/) | 같은 circuit을 독립 implementation으로 확인 |
| Q1.22 bit-exact | [`reference_model_develop/models/rtl_reference_model/`](../../software/reference_model_develop/models/rtl_reference_model/) | RTL과 같은 수가 나오는지 |

| file | 역할 |
|---|---|
| `reference_model_develop/models/common/final_hardware_contract.py` | 14 qubits · 32 lanes · Q1.22, CSR offset(`CSR_OFFSETS`)과 입력 범위, execution mode(`RUN_MODES`), checkpoint constant |
| `reference_model_develop/models/common/benchmark_dataset.py` | number of solutions별 공식 dataset 생성·verification, oracle solution mask, predicate별 dataset 규칙 `generate_predicate_image` |
| `reference_model_develop/models/common/bbht_control_semantics.py` | BBHT sampling range 경계, BBHT budget, shot · FIFO 의미 검사 |
| `reference_model_develop/models/common/model_config.py` · `result_records.py` · `trace_recorder.py` | 실험 설정 · 결과 data type · oracle 전후와 diffusion operator 후 state 기록 |
| `pc_grover_develop/team_models/numpy_model/numpy_grover_backend.py` | Float64 oracle · diffusion operator state vector 계산 |
| `pc_grover_develop/team_models/qiskit_model/qiskit_grover_backend.py` | Qiskit Aer로 requested iterations circuit 준비·실행 |
| `pc_grover_develop/team_models/qiskit_model/bbht_qiskit_runner.py` | 같은 Iteration-Count LFSR · measurement 규칙으로 NumPy/Qiskit BBHT 수행 |
| `reference_model_develop/models/rtl_reference_model/fixed_point_statevector.py` | RTL Q1.22 산술, LFSR, measurement의 bit-exact 기준 |
| `reference_model_develop/models/rtl_reference_model/checkpoint_bbht_model.py` | BBHT · enumeration 실행 기준. Restart mode · a Checkpoint-Capacity of 4 and 4-shot Lookahead · a Checkpoint-Capacity of 3 and 3-shot Lookahead · `DRAM_ALL_J` policy |

### RTL reference model이 재현하는 범위

| 재현함 | 재현 안 함 |
|---|---|
| Q1.22 산술 (saturation · round-half-to-even 포함) | `cycle_count` |
| Iteration-Count LFSR과 7-step jump timing | policy 풀이 latency |
| Measurement PRNG(xorshift64)와 integer prefix sum | Plan Queue stall |
| a Checkpoint-Capacity of 3 and 3-shot Lookahead policy의 결정 규칙 | 4 PEs · Two-Level Select의 cycle 효과 |
| executed iterations (`executed_iterations`) | |

오른쪽은 hardware timing이라 일부러 빼 두었습니다. policy latency와 pipeline stall까지 흉내 내면
RTL과 독립된 verification이라는 의미가 약해집니다. cycle은 RTL simulation이나 board에서 인용합니다.

reference model은 CSR mode 이름(`CHECKPOINT_SINGLE` 등) 대신 policy 이름으로 부릅니다. `RUN_MODES` 에
`K3H3_*` · `K3H3_E4_M2_*` · `K4H4_*` · `K4H8_*` 가 있고 `CKPT_*` 는 없습니다.
`checkpoint_bbht_model.py` 는 `mode="K4H8"` 을 옛 a Checkpoint-Capacity of 4 and 4-shot Lookahead policy로, `"final"` 를 a Checkpoint-Capacity of 3 and 3-shot Lookahead로
옮겨 받습니다. 이름이 갈라진 이유는 [1장 1.4절](01_project_overview.md#14-final-configuration)에 있습니다.

`DRAM_ALL_J` 도 policy model로 들어 있습니다. DRAM Variant([21장](21_dram_variant.md))의 발상을
algorithm 수준에서 비교하려는 것이고 DRAM 전송 latency는 modeling하지 않았습니다.

### enumeration을 reference model로 돌리는 법

`enum_enable=True` 면 `run_configured()` 가 enumeration으로 가고, `burst_enable=True` 면 a Checkpoint-Capacity of 3 and 3-shot Lookahead checkpoint
policy를 씁니다.

```python
import sys
for sub in ("common", "rtl_reference_model"):
    sys.path.insert(0, f"software/reference_model_develop/models/{sub}")

from benchmark_dataset import build_controlled_v098_dataset
from checkpoint_bbht_model import V098AutomaticCore

dataset = build_controlled_v098_dataset(
    predicate_mode="EQ", data_count=16384, target_count=4,
    enum_enable=True, burst_enable=True, fail_repeat_limit=3)
result = V098AutomaticCore(dataset, dataset.config).run_configured(max_results=256)
```

---

## 4.3 Common500 비교 실험

board와 같은 500 workloads를 software backend 다섯(NumPy · Qiskit Aer · fixed-point Restart mode · a Checkpoint-Capacity of 4 and 4-shot Lookahead · a Checkpoint-Capacity of 3 and 3-shot Lookahead)과
board benchmark 셋에 걸어 맞댄 실험입니다. 실행 방법 · 정합성 · 결과 file은
[실험 14](../reports/14_common500_software_fpga_comparison.md)에 있습니다.

---

## 4.4 Predicate500 expected result

Common500은 EQ 하나입니다. 같은 모양(number of solutions 다섯 값 × 공식 seed 100쌍)을 LT · GT · EQ · RANGE에 각각
건 2,000 workloads의 expected result를 `software/reference_model_develop/predicate500/` 의 생성기가
`software/reference_model_data/2026-09-25_predicate500/` 에 만듭니다. EQ 500개는
Common500과 dataset·seed가 byte 단위로 같고, expected result가 board 500 runs benchmark와 네 축 모두
500/500 같습니다.

```bash
python3 software/reference_model_develop/predicate500/run_predicate500_golden.py   # 30초쯤
```

- Q1.22 bit-exact model(`V098AutomaticCore`)이 Restart mode · a Checkpoint-Capacity of 3 and 3-shot Lookahead · DRAM_ALL_J 셋 mode로 돌리고,
  BBHT trajectory가 셋 mode에서 같은지 생성기가 스스로 확인합니다.
- DRAM의 executed iterations는 열이 하나 더 있습니다(`actual_iter_dram_session`). DRAM 표가 load 사이에
  살아 있어서 한 dataset에서 seed를 차례로 돌면 앞 seed가 채운 checkpoint slot을 뒤 seed가 씁니다. 이것을
  재현하려고 `run_single` 에 `checkpoint=` argument를 더했습니다.
- 결과는 `expected/predicate500_expected.csv`(2,000 rows)와 `predicate500_datasets.csv`(20개)이고,
  board 자동 test와 RTL testbench가 이 둘을 읽습니다([18장](18_predicate500_automated_test.md)).

---

## 4.5 RTL test vector

reference model이 미리 계산해 둔 bit 단위 expected result입니다. requested iterations vector는
[`software/reference_model_data/2026-09-02_requested_j_vectors/`](../../software/reference_model_data/2026-09-02_requested_j_vectors/),
enumeration vector는 [`software/reference_model_data/2026-09-09_enumeration_vectors/`](../../software/reference_model_data/2026-09-09_enumeration_vectors/)
에 있습니다. 지금 이 저장소의 RTL testbench는 두 vector를 직접 읽지 않습니다. requested iterations vector는 C++ implementation verification
(`software/pc_grover_develop/tools/verify_cpp_rtl_vectors.py`)이 쓰고, enumeration vector는 읽는 code 없이 기준 기록으로
남아 있습니다. RTL testbench가 실제로 쓰는 stimulus는 아래 「testbench workload 생성기」가 만듭니다.

### requested iterations bit-exact 256 cases

`requested_j_bit_exact_256_cases.zip`: directed 28개(`dir_*`), anchor
1개(`anchor_*`), random 227개(`rnd_*`). case마다 directory 하나입니다.

| file | 내용 |
|---|---|
| `config.json` | predicate · threshold · `DATA_COUNT` · `j_target` 과 profile(14 qubits · 32 lanes · 22 fraction bits · 23-bit amplitude) |
| `data_signed16.hex` · `data_ahb_words.hex` · `data_memory_image.hex` | 같은 dataset의 세 표현 (index 순 · AHB data word · 32 lanes memory image) |
| `target_mask_p32.hex` | oracle solution mask |
| `initial_amp.hex` | 초기 Q1.22 amplitude |
| `iter_###_after_oracle.hex` · `iter_###_row_partial_sum.hex` · `iter_###_after_diffusion.hex` | iteration별 중간값 (FULL trace 56 cases만) |
| `expected_final_amp.hex` · `expected_core.json` | 최종 amplitude와 결과 · executed iterations · saturation 횟수 · amplitude hash |

verification 범위는 Manual mode의 core 산술로 한정됩니다. `expected_core.json` 의 `scope` 가
`MANUAL_CORE_BIT_EXACT` 이고, 자동 BBHT의 Iteration-Count LFSR random number · Measurement PRNG random number · policy telemetry · `cycle_count`
는 이 vector의 주장에서 빠져 있습니다(`excluded_from_claim`). 그쪽은 Common500이 맡습니다.
단계별 비교 순서는 [6장 6.9절](06_data_representation_and_memory_map.md#69-test-vector와-비교-순서)에 있습니다.

### enumeration 두 방식

| directory | 뜻 |
|---|---|
| `software_reload/` | 찾은 값을 non-solution으로 바꾸고 dataset을 다시 load |
| `projected_mask_mem/` | hardware Found Mask 방식 (최종 RTL이 채택) |

두 방식에 같은 다섯 case(`q14_eq_m1` · `q14_range_m4_pad50` · `q14_gt_m8_pad75` · `q14_lt_m0` ·
`q16_eq_m2`)가 있고, case마다 다음을 비교합니다.

| file | 뜻 |
|---|---|
| `data.hex` | signed16 dataset |
| `config.json` | number of qubits, predicate, threshold, `DATA_COUNT`, seed, backend |
| `expected_result.json` | 결과 목록, shot, number of iterations, 종료 사유 |
| `round_*_mask_before.hex` · `round_*_mask_after.hex` | enumeration round 전후 Found Mask. data word는 `row = index>>5`, `bit = index&31` |

`q16_eq_m2` 는 폐기된 16 qubits 확장의 기록이므로 14 qubits board implementation의 verification 근거로 쓰지 않습니다.

### testbench workload 생성기

| 생성기 | 자극 |
|---|---|
| [`dump_bench_workload.py`](../../software/reference_model_develop/tb_stimulus/dump_bench_workload.py) | `bench250` · `bench500` (`--seeds 50|100`) |
| `dump_predicate500_workload.py` | Predicate500 RTL testbench. dataset hash를 expected result와 대조 |

두 생성기는 `software/reference_model_develop/tb_stimulus/` 에 있고 hardware Makefile이 부릅니다.
`dump_bench_workload.py` 는 dataset을 다시 계산하지 않고 `software/testbench_data/2026-09-08_common500/` 에서
복사하며, 돌 때마다 hash · roster · 부분집합 관계(250이 500의 부분집합)를 스스로 검사합니다.
board testbench가 쓴 dataset 다섯 개는 `software/testbench_data/2026-09-08_common500/datasets/` 와
`hardware_bram/firmware/bbht_paper_bench/tools/reference_dataset/` 에 sha256이 같은
채로 있고, seed roster 100쌍도 같은 directory의 `official_board_seed_roster.h` 와
`hardware_bram/results/2026-09-08_publication_6stage/seeds.csv` 에 같은 값으로 있어서
numpy 없이 복사만 합니다.

---

## 4.6 Qiskit과 NumPy로 대조하기

Qiskit은 build 사슬에 들어가지 않습니다. 새 reference model을 넣거나 결과가 이상할 때 손으로
대조하는 reference입니다. 비교 대상은 AerSimulator와 NumPy state vector 둘이고, 고전 선형 scan과는
속도를 견주지 않습니다.

### oracle은 data에서 만듭니다

IP가 하는 일은 memory에 실린 16-bit data 전체에 predicate를 적용해 predicate에 맞는 칸을 표시하는
것입니다. Qiskit에서 이것에 대응하는 것은 diagonal entry가 ±1 인 diagonal gate 하나입니다.

```python
import numpy as np
from qiskit import QuantumCircuit
from qiskit.circuit.library import DiagonalGate, grover_operator

Q = 14
N = 1 << Q
rng = np.random.default_rng(0)
data = rng.integers(-32768, 32768, size=N).astype(np.int16)   # 16-bit signed

marked = np.flatnonzero(data > 32000)      # GT predicate. LT/EQ/RANGE 도 이 줄만 바뀝니다
diag = np.ones(N)
diag[marked] = -1                          # predicate를 통과한 자리만 phase 반전

oracle = QuantumCircuit(Q)
oracle.append(DiagonalGate(diag.tolist()), range(Q))
G = grover_operator(oracle)                # oracle + diffusion operator를 묶은 iteration 한 번
```

`marked` 를 미리 계산한다고 oracle이 답을 아는 것은 아닙니다. predicate를 data 전체에 적용한
결과이고 hardware도 매 iteration 같은 일을 합니다. solution index를 손으로 적어 넣는 식으로 바꾸면
verification이 성립하지 않습니다.

### solution이 몇 개인지 알 때와 모를 때

```python
from qiskit import transpile
from qiskit_aer import AerSimulator

M = len(marked)
r = int(np.floor(np.pi / 4 * np.sqrt(N / M)))    # M 을 알 때의 최적 iteration

qc = QuantumCircuit(Q)
qc.h(range(Q))
for _ in range(r):
    qc.compose(G, inplace=True)
qc.measure_all()
sim = AerSimulator(method="statevector")
counts = sim.run(transpile(qc, sim), shots=1024).result().get_counts()
```

위 data에서는 221 solutions가 나오고, 최적값은 6 iterations입니다. predicate를 만족하는 index가 나올 이론 probability가
0.9967이고, transpile 0.11초 · 실행 0.02초입니다. Aer가 diagonal gate를 분해하지 않아 circuit
depth는 26입니다.

solution이 몇 개인지 모를 때가 실제 장비가 푸는 문제입니다. sampling range를 growth factor 6/5로 늘려 가며 찍고, 나온
index를 predicate로 다시 검사해(solution check) 틀리면 다시 돌립니다.

```python
cache = {}
def measure_once(j, seed):
    if j not in cache:                     # 같은 j 는 circuit을 재활용
        c = QuantumCircuit(Q)
        c.h(range(Q))
        for _ in range(j):
            c.compose(G, inplace=True)
        c.measure_all()
        cache[j] = transpile(c, sim)
    bits = list(sim.run(cache[j], shots=1, seed_simulator=seed).result().get_counts())[0]
    return int(bits, 2)

m, lam, seed = 1.0, 6 / 5, 0
while True:
    j = int(rng.integers(0, int(m) + 1))
    seed += 1
    idx = measure_once(j, seed)
    if data[idx] > 32000:                  # 검산은 고전적으로. 판정의 근거는 여기
        break
    m = min(lam * m, np.sqrt(N))
```

`seed_simulator` 를 shot마다 바꿔야 합니다. 고정하면 같은 number of iterations에서 같은 index만 나와 loop가
끝나지 않습니다. 이 data에서 seed를 바꿔 20번 돌리면 requested iterations 누적의 median이 5, maximum이
41이었습니다. mean은 최적값 6과 비슷한데 꼬리가 길고, 이 편차가 checkpoint로 줄이려는
대상입니다([11장](11_checkpoint_and_policy_engine.md)).

### 세 경로 중 무엇을 쓸 것인가

14 qubits, 6 iterations에서 잰 값입니다.

| 경로 | 시간 | 언제 |
|---|---|---|
| `qiskit.quantum_info.Statevector(qc)` | 16~25초 | 쓰지 않음. Python에서 gate를 하나씩 곱함 |
| `AerSimulator` + `save_statevector()` | 0.1초 안팎 | 보고서에 실을 기준값 |
| NumPy array 직접 | 0.1 ms | 수천 번 돌리는 campaign |

```python
qc = QuantumCircuit(Q)
qc.h(range(Q))
for _ in range(r):
    qc.compose(G, inplace=True)
qc.save_statevector()                      # qiskit_aer 를 import 하면 생기는 메서드
sv = sim.run(transpile(qc, sim)).result().get_statevector()

psi = np.full(N, 1 / np.sqrt(N))           # 같은 것을 NumPy 로
for _ in range(r):
    psi *= diag                            # oracle
    psi = 2 * psi.mean() - psi             # diffusion operator: mean 기준 반사
```

셋의 결과는 amplitude 기준 `1e-13` 안에서 일치합니다. 새 reference model을 넣을 때 이 세 값을 함께
찍으면 틀린 것이 새 model인지 reference인지 바로 갈립니다.

### 이름이 바뀐 API

Qiskit 2.x가 class를 gate 형태로 옮기는 중이라 인터넷 예제 상당수가 경고를 냅니다. 3.0에서
실제로 사라지므로 새 이름을 씁니다. 경고를 놓치지 않으려면
`python3 -W error::DeprecationWarning your_script.py` 로 돌립니다.

| 옛 이름 | 쓸 것 | 비고 |
|---|---|---|
| `Diagonal` | `DiagonalGate` | 2.1부터 deprecated |
| `PhaseOracle` | `PhaseOracleGate` | 2.2부터 deprecated |

14 qubits에 iteration까지 펼친 circuit은 text로 그리기에 너무 넓으니 `G` 한 벌이나 qubit 서너 개짜리
축소판만 `qc.draw("mpl", filename="circ.png")` 로 그립니다.

---

## 4.7 hardware-software 계약

[`spec/`](../../spec/)에 계약 두 벌과 그 대조기가 있습니다.

| 계약 | file | 자세한 곳 |
|---|---|---|
| CSR | source of truth `bbht_grover_csr.json`, 생성기 `gen_csr.py` → `generated/` (Verilog · C · Python header)와 [13장](13_csr_registers_and_execution_modes.md) | [13장 13.8절](13_csr_registers_and_execution_modes.md#138-생성-pipeline) |
| port | `port_contract.tsv` · `check_ports.py` | [12장](12_accelerator_core_port_contract.md), [16장 16.2절](16_verification_framework.md#162-0층-port-계약) |

2026-10-12에 이 directory를 `software/contract/` 에서 저장소 root `spec/` 으로 올렸습니다. 두 hardware directory tree의
RTL, firmware, host 도구가 함께 쓰는 규격이라 software 아래에 둘 이유가 없어서입니다. 같은 날 `software/` 는
`golden/` · `pc_grover/` · `orca_grover/` · `host_fpga/` 네 분류로 다시 나눴습니다(4.1절의 directory tree).
