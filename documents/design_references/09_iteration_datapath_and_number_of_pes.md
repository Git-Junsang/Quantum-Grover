# 9장. Iteration Datapath와 4 PEs

> [← 8장 Accelerator Core 최상위와 BBHT 제어](08_accelerator_core_top_and_bbht_control.md) · [index](index.md) · [10장 Measurement Unit과 Dual-Row Build · Two-Level Select →](10_measurement_unit_and_microarchitecture.md)

---

number of iterations가 정해지면 Grover iteration을 그 횟수만큼 실행합니다. 이 장에서는 한 번의 iteration을 처리하는
datapath를 설명합니다. algorithm 수준의 설명은
[3장 3.2절](03_grover_and_bbht_algorithm.md)에 있습니다.

---

## 9.1 실행 state

`grover_ctrl_fsm_ckpt_e4`의 state는 다섯이고, iteration 한 번은 뒤의 셋을 씁니다.

| state | 무엇을 |
|---|---|
| `S_INIT` | amplitude 전체를 uniform amplitude raw 32768로 채움 |
| `S_PASS1` | data에 predicate를 걸어 oracle sign을 뒤집고, 동시에 32 lanes sum을 누적 |
| `S_MEAN` | 누적된 전체 sum에서 `2×mean`을 round-half-to-even으로 확정 |
| `S_PASS2` | 각 amplitude를 `2×mean − amplitude`로 바꾸고 symmetric saturation |

`S_INIT`은 search를 시작하거나 사용할 checkpoint가 없을 때만 실행됩니다.

oracle과 diffusion operator가 한 번의 pass에 하나씩 들어가서, iteration 한 번이 state 전체를 두 번
지납니다. oracle만 훑고 diffusion operator만 다시 훑는 구조가 아니라, Pass 1이 oracle과 sum 누적을
같이 하고 Pass 2가 diffusion operator를 합니다.

### 단일 state memory 사용

Pass 1에서 oracle 결과를 amplitude memory에 쓰면서 그 같은 register 출력을 adder tree로도
보냅니다. state 한 벌을 더 두고 한쪽은 쓰고 한쪽은 읽는 것이 아니라, 같은 register 출력이 두
곳으로 갈라지는 것입니다. BRAM을 아끼는 가장 큰 요령입니다.

---

## 9.2 산술 조각

[`grover_arithmetic.v`](../../hardware_bram/src/grover_arithmetic.v) 안의 module들입니다.

| module | 하는 일 |
|---|---|
| `grover_predicate` | 16-bit signed 비교 네 가지 |
| `grover_oracle_flip` | predicate가 참이면 amplitude sign 반전 |
| `grover_adder_tree` | 32 lanes amplitude를 한 값으로 |
| `grover_sum_accum` | 512 rows partial sum을 전역 accumulator(39 bits)로 |
| `grover_two_mean_calc` | 전체 sum에서 `2×mean`을 round-half-to-even |
| `grover_diffusion_sat` | `2×mean − amplitude`와 symmetric saturation |

### predicate는 runtime 값입니다

`grover_predicate`의 판정은 combinational `case` 문 한 덩어리입니다.

```verilog
case (mode)
    `GP_MODE_LT:    pred = pred_lt;
    `GP_MODE_GT:    pred = pred_gt;
    `GP_MODE_EQ:    pred = pred_eq;
    `GP_MODE_RANGE: pred = pred_range;
    default:        pred = 1'b0;
endcase
```

네 가지가 전부 circuit으로 깔려 있습니다. `generate`로 잘라 내지 않으므로, bitstream
하나로 네 predicate를 전부 쓸 수 있습니다. 값은 `CONTROL` register bit [3:2]에서 와서
mmio → adapter → Accelerator Core → Measurement Unit까지 그대로 흐릅니다([13장](13_csr_registers_and_execution_modes.md)).

같은 Predicate Unit을 measurement 뒤 solution check에서도 씁니다([10장](10_measurement_unit_and_microarchitecture.md)).
oracle과 solution check가 다른 Predicate Unit을 쓰면 둘이 어긋날 수 있어서 하나로 묶었습니다.

### saturation은 대칭입니다

23-bit two's complement에서 가장 음수인 code(`-4194304`)를 쓰지 않고 `±4,194,303`으로
자릅니다([6장 6.3절](06_data_representation_and_memory_map.md)). saturation이 일어나면 `amp_overflow`가
sticky로 섭니다: 진단용이고 종료 사유가 아닙니다.

---

## 9.3 100 MHz timing을 위한 pipeline register

Pass 1의 `BRAM → predicate → oracle → 32-lane adder tree → accumulator` 경로가 placement·routing 뒤 약
-6.574 ns로 가장 나빴습니다. 두 곳을 잘랐습니다.

1. oracle 출력 register를 pipeline register로 씀
2. adder tree 5단을 3단 + register + 2단으로 가름

그 대가로 Pass 1 마지막 쓰기 뒤 drain 한 cycle이 `S_MEAN` 진입 전에 들어갑니다.
산술 결과는 바뀌지 않고 latency만 늡니다: pipeline register는 값을 바꾸지 않으므로
software reference model과의 bit-exact 대조가 그대로 섭니다.

---

## 9.4 4 PEs의 4 rows 병렬 처리

`NUMBER_OF_PES=4` 일 때 512 rows는 128 row groups로 묶이고, 한 row group은 4 rows입니다. Pass 1과
Pass 2는 각각 128번만 발행하면 됩니다.

```
1 PE  : Pass 1 512 rows + Pass 2 512 rows             →  iteration 한 번에 1,024번 발행
4 PEs : Pass 1 128 row groups + Pass 2 128 row groups →  iteration 한 번에   256번 발행
```

### BBHT trajectory의 보존

4 PEs는 Grover iteration 한 번 안을 쪼갤 뿐이고 BBHT의 request 순서(어떤 number of iterations를 몇 번째로 뽑는가)는
손대지 않습니다. 그래서 `shot_count` · `requested_iterations` · `executed_iterations`가 1 PE와
완전히 같고, 줄어드는 것은 cycle뿐입니다.

BBHT trajectory가 바뀌면 software reference model과의 500/500 대조를 통과할 수 없습니다. regression test는
4 PEs 최적화가 논리 동작을 바꾸지 않았는지 자동으로 확인합니다
([16장](16_verification_framework.md)).

2026-09-06에 시도했던 Two-Track Execution은 반대로 request 순서를 두 track으로 갈랐고, 분할 비용
+50% 와 checkpoint slot 소유권 문제로 탈락했습니다. benchmark와 4 PEs를 고른 근거(1 PE cycle 분해)는
[실험 08](../reports/08_one_pe_profiling_and_four_pes.md)과
[실험 10](../reports/10_two_track_execution_and_pass2_build_fusion.md)에 있습니다.

### BRAM 절감 방식

Pass 1의 oracle 결과를 별도 scratch memory에 두지 않고 목적지 checkpoint slot에 바로
씁니다. Pass 2는 그 checkpoint slot을 다시 읽어 diffusion operator 결과로 덮습니다. segment 실행 규약
(`PASS1: src→dst`, `PASS2: dst→dst`)이 원래 그렇게 되어 있어서 전체 state 한 벌을 더 둘
필요가 없습니다([11장](11_checkpoint_and_policy_engine.md)).

### measurement와 port를 나눠 씁니다

measurement 중에는 Grover iteration이 돌지 않으므로, measurement도 같은 4 rows 동시 읽기 port를 빌려 씁니다.
읽기 응답에 tag를 달아 두어서 남아 있던 checkpoint 응답이 measurement의 첫 row로
오인되지 않습니다.

---

## 9.5 4 PEs의 resource 비용

| configuration | LUT | FF | BRAM tile | DSP |
|---|---:|---:|---:|---:|
| Stage 2 | 13,804 | 13,611 | 66.0 | 64 |
| Stage 3 | 30,294 | 25,822 | 83.0 | 64 |

LUT 사용량은 2.2×로 늘었고 cycle은 38.71% 감소했습니다
([15장](15_operation_sequence_and_cycle_breakdown.md)). DSP 사용량은 증가하지 않습니다. 이 경로에
multiplier가 없기 때문입니다. diffusion operator는 `2×mean − amplitude`라 shift와 subtraction이고, oracle은 sign
반전입니다. DSP가 두 배가 되는 것은 Measurement Unit의 Dual-Row Build 단계입니다([10장](10_measurement_unit_and_microarchitecture.md)).
