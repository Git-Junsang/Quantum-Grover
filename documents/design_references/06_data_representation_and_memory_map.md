# 6장. data 표현과 memory map

> [← 5장 hardware architecture 개요](05_hardware_architecture_overview.md) · [index](index.md) · [7장 Bus Interface →](07_bus_interface.md)

---

이 장은 입력 data, amplitude, datapath bit width, memory 배치의 source of truth입니다. board에서 검증된 RTL
(`hardware_bram/src/` 의 Accelerator Core)과 bit-exact reference model
(`software/reference_model_develop/models/rtl_reference_model/`)이 같은 규격을 쓰고, 표의 값은
[`grover_param.vh`](../../hardware_bram/src/grover_param.vh)에서 직접 뽑았습니다.

| 항목 | 값 |
|---|---:|
| number of states | 16,384 |
| number of lanes | 32 |
| number of rows | 512 |
| 입력 | signed16 |
| 저장 amplitude | signed 23 bits, raw / `2^22` |
| uniform amplitude raw | 32,768 |
| mean round-half-to-even | nearest, ties-to-even |
| amplitude 범위 | `[-4194303, 4194303]` |
| measurement | integer square + Measurement PRNG rejection sampling + row/lane prefix sum |

---

## 6.1 입력 data

signed 16-bit two's complement입니다.

| 실제 값 | 16-bit HEX |
|---:|---|
| 0 | `0000` |
| 1 | `0001` |
| 32767 | `7FFF` |
| -1 | `FFFF` |
| -32768 | `8000` |

reference model vector file은 전역 index 순서로 한 줄에 네 자리 HEX 하나를 씁니다.

```text
0003
FFF8
0000
7FFF
```

`index >= data_count` 인 칸은 memory에 어떤 값이 남아 있어도 oracle과 후보 verification에서 항상
non-solution입니다. data 개수를 16,384보다 작게 줄 수 있고, 그때 남은 자리의 값이 결과에 영향을
주지 않습니다. padding 자리에 predicate를 만족하는 값을 일부러 넣은 campaign에서도 padding index가
결과로 나온 경우는 0이었습니다([실험 01](../reports/01_reference_model_campaign.md)).

---

## 6.2 32 lanes bank/row mapping

전역 index `i` 를 32 lanes × 512 rows에 이렇게 펼칩니다.

```
bank = i mod 32       =  index[4:0]
row  = i / 32         =  index[13:5]
```

| index | bank | row |
|---:|---:|---:|
| 0 | 0 | 0 |
| 31 | 31 | 0 |
| 32 | 0 | 1 |
| 63 | 31 | 1 |
| 16383 | 31 | 511 |

한 row에서 lane과 bank는 1:1입니다. packed row bus에서 lane `b` 는
`row_bus[b*WIDTH +: WIDTH]` 이고, lane 0이 최하위 bit slice입니다.

한 row를 읽으면 원소 32개를 동시에 가져오고, 512 rows를 읽으면 전체 state를 한 번 훑습니다. 뒤
장에서 쓰는 512 rows 단위가 여기서 나옵니다.

---

## 6.3 amplitude 형식

저장 amplitude는 signed 23 bits, 22 fraction bits이고 real value는 `raw / 2^22` 입니다. "Q1.22 계열" 이라고
부르지만 Q format 표기 관례가 갈릴 수 있으므로 "signed 23 bits, fractional 22" 라는 정의를 우선합니다.

| 값 | raw | 23-bit code (6자리 HEX) |
|---|---:|---|
| 14 qubits uniform amplitude `1/128` | 32768 | `008000` |
| `1/64` | 65536 | `010000` |
| 사용하는 maximum | 4194303 | `3FFFFF` |
| 사용하는 minimum | -4194303 | `400001` |
| 제외한 two's complement minimum | -4194304 | `400000` |

symmetric saturation을 위해 `-4194304` 는 쓰지 않습니다. 양끝이 대칭이어야 diffusion operator의 sign 처리가 한쪽으로
치우치지 않습니다. saturation이 일어나면 `amp_overflow` 가 sticky로 섭니다.

14 qubits의 uniform amplitude는 정확히 표현됩니다. `1/sqrt(16384) = 1/128` 이고 `2^22 / 128 = 32768` 이라
round-half-to-even error 없이 시작합니다. 이 폭(22 fraction bits)을 고른 근거 실험은
[실험 02](../reports/02_amplitude_precision.md)에 있습니다.

---

## 6.4 datapath bit width

| 값 | 폭 | signed | 역할 |
|---|---:|---|---|
| 입력 data | 16 | signed | predicate 입력 |
| 저장 amplitude | 23 | signed | state vector |
| 32 lanes partial sum | 28 | signed | row amplitude sum |
| 전역 accumulator | 39 | signed | 16,384 amplitudes의 sum |
| `two_mean` | 25 | signed | round-half-to-even한 `2*mean` |
| diffusion operator 중간값 | 25 | signed | `two_mean - oracle_amp` |
| amplitude square | 46 | unsigned | `raw^2` |
| row weight | 51 | unsigned | square 32개 sum |
| total weight | 60 | unsigned | 전체 row weight의 sum |
| index | 14 | unsigned | 0..16383 |
| data 개수 | 15 | unsigned | 1..16384 |
| number of iterations | 7 | unsigned | 0..127 |

한 항목의 폭이 바뀌면 그것을 쓰는 하위 연산과 memory 형식을 같이 봐야 합니다. number of iterations가 7 bits인
것이 [8장](08_accelerator_core_top_and_bbht_control.md)의 Iteration-Count LFSR 7-step jump과 직접 이어집니다.

---

## 6.5 한 번의 Grover iteration

```text
Pass 1
  amplitude + data row 읽기
  -> padding gate + signed predicate
  -> solution amplitude sign 반전
  -> oracle 결과를 amplitude memory에 씀
  -> 32-lane sum과 전역 accumulation

Mean
  전역 sum -> round-half-to-even 한 two_mean

Pass 2
  oracle 결과 row 읽기
  -> two_mean - oracle_amp
  -> symmetric saturation
  -> 다음 amplitude를 amplitude memory에 씀
```

oracle은 `i < DATA_COUNT` 이고 predicate가 참인 칸만 sign을 뒤집습니다.

```
oracle_amp[i] = -amp[i]   if (i < DATA_COUNT) and predicate(data[i])
              =  amp[i]   otherwise
```

mean을 round한 뒤 두 배하지 않습니다. 전체 sum에서 `2*mean` 을 한 번만 round-half-to-even으로
맞춥니다. 14 qubits 에서는 signed 전역 sum을 13 bits 오른쪽 shift하고 nearest-even을 적용합니다.

```
two_mean = roundEven( sum(oracle_amp) / 2^(number of qubits - 1) )        14 qubits 이면 13-bit shift
next_amp[i] = clip( two_mean - oracle_amp[i], -4194303, 4194303 )
```

한 번이라도 saturation이 나면 `amp_overflow` 가 다음 accepted start까지 유지됩니다. 진단용이고
종료 사유가 아닙니다.

---

## 6.6 pipeline과 memory 접근

```text
Init / Pass 2
t   : row 발행
t+1 : BRAM 응답 / datapath
t+2 : amplitude memory 쓰기

Pass 1
t   : amplitude/data row 발행
t+1 : BRAM 응답, predicate metadata register
t+2 : padding + oracle, amplitude row register
t+3 : amplitude memory 쓰기, adder tree 전반
t+4 : adder tree 후반, 전역 accumulator
```

Pass 1 뒤에는 마지막 partial sum을 받기 위한 drain state가 있습니다. `cycle_count` 는 이 pipeline을
포함한 regression 관측값이고, pipeline이 바뀌어도 고정되는 외부 port 계약은 아닙니다. pipeline
register를 둔 이유는 [9장 9.3절](09_iteration_datapath_and_number_of_pes.md#93-100-mhz-timing을-위한-pipeline-register)에
있습니다.

---

## 6.7 memory 구조

### 논리 구성

| memory | 논리 구성 | raw 용량 | 용도 |
|---|---|---:|---|
| `data_mem` | 32 banks × 512 × 16-bit | 32 KiB | oracle 입력과 solution check |
| amplitude · checkpoint | state 한 벌 = 512 rows × 32 lanes × 23 bits, checkpoint slot 4벌 | 46 KiB × 4 | state vector와 되돌아갈 지점 |
| row weight | 512 × 51-bit | 약 3.2 KiB | Born-rule sampling의 row prefix sum |

4 PEs configuration에는 따로 떨어진 작업용 amplitude memory가 없습니다. 계산은 checkpoint slot 안에서 제자리(in-place)로
하거나, 한 iteration만 다른 checkpoint slot으로 건너 씁니다(bridge). segment 규약은
[11장](11_checkpoint_and_policy_engine.md)에 있습니다.

measurement는 amplitude memory를 읽기 전용으로 쓰므로 measurement 직전 state가 그대로 남습니다. checkpoint slot은 그 state를
되돌아갈 지점으로 남겨 두는 것이고, 관리 규칙은 [12장 12.8절](12_accelerator_core_port_contract.md#128-checkpoint-계약)에
있습니다.

### 물리 BRAM 배치

위 표는 논리 bit 수이고, 실제 개수는 commit된 implementation report(`route_util_hier.rpt`)로 확인합니다.

| 무엇 | 개수 |
|---|---|
| amplitude state 한 벌 | row 736-bit = 10 × 69-bit + 1 × 46-bit → RAMB36 11개 |
| checkpoint slot 4벌 | row phase 4 banks(각 512 × 736 bits)에 담아 RAMB36 44개 |
| policy memo table | RAMB36 4 |
| Found Mask | RAMB36 2 |
| row weight | RAMB36 2 |
| `data_mem` | RAMB18 64 |
| Accelerator Core 합계 | RAMB36 52 + RAMB18 64 = 84 BRAM tiles |
| full SoC | 116 BRAM tiles |

state 한 벌은 16,384 × 23 = 376,832 bits이고 RAMB36 하나가 36,864 bits라 이론 lower bound가 10.22개,
즉 최소 11개입니다. implementation이 그 lower bound를 달성했습니다([실험 06](../reports/06_checkpoint_memory_packing.md)).

checkpoint slot은 Checkpoint-Capacity와 관계없이 4벌입니다. 그래서 Checkpoint-Capacity를 4에서 3으로 바꿔도 BRAM이 줄지 않았습니다(resource
ablation study 83.0 → 83.0 tiles). 성능 개선은 저장 공간이 아니라 policy 결정 비용에서 나왔습니다
([1장 1.4절](01_project_overview.md#14-final-configuration)).

---

## 6.8 system SRAM과 load

dataset은 CSR로 넣지 않고 system SRAM에 두었다가 accelerator가 끌어갑니다.

| 항목 | 값 |
|---|---|
| SRAM 범위 | `0xE0000000` ~ `0xE001FFFF` (128 KiB) |
| packing | `word[15:0] = data[2k]`, `word[31:16] = data[2k+1]` (little-endian) |
| 전송 | 32-bit AHB SINGLE, single outstanding |
| 비용 | data word당 3 cycles (address 1 + data 1 + 쓰기 1) |
| 14 qubits 전체 | 16,384개 = 8,192 data words → 24,576 cycles, 100 MHz에서 약 246 µs |

`DATA_COUNT` 가 홀수이면 마지막 상위 halfword를 loader가 쓰지 않습니다. 전달하더라도
`addr >= data_count` 라서 Accelerator Core 쪽 loader가 무시합니다.

Accelerator Core loader는 address 중복을 검출하지 않습니다. 같은 address를 여러 번 써도 쓰기 개수가
올라가므로, adapter는 `0..data_count-1` 을 정확히 한 번씩 생성해야 합니다
([12장 12.7절](12_accelerator_core_port_contract.md#127-loader-transaction)).

---

## 6.9 test vector와 비교 순서

기준 vector는 `software/reference_model_data/2026-09-02_requested_j_vectors/requested_j_bit_exact_256_cases.zip`
입니다(file 구성은 [4장 4.5절](04_software_reference_model_and_test_vectors.md#45-rtl-test-vector)). 어긋날 때는
이 순서로 첫 불일치 단계를 찾습니다.

```text
loader data
-> initial amplitude
-> after oracle
-> partial / global sum
-> two_mean
-> after diffusion operator
-> Born-rule sampling total weight / random number
-> selected row / lane / index
-> verification
-> REQUESTED_ITERATIONS / executed iterations / cycle count
```

최종 index만 맞는 것으로 bit-exact PASS를 선언하지 않습니다. BBHT가 후보를 solution check로 스스로
확인하므로 amplitude가 깨져도 답은 맞을 수 있습니다. 첫 불일치 단계에서 loader, predicate, round-half-to-even, saturation,
Iteration-Count LFSR, Measurement PRNG, prefix sum 문제를 가릅니다. `bit-exact` 는 허용 error 안에서 비슷하다는 뜻이 아니라 RTL의
fixed-point bit string이 reference model의 값과 정확히 같다는 뜻입니다. Float64 비교는 수치 품질 verification에,
Q1.22 비교는 RTL implementation verification에 씁니다.
