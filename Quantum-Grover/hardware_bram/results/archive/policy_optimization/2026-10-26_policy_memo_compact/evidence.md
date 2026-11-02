# a Checkpoint-Capacity of 3 and 3-shot Lookahead policy memo table 압축 근거

## 변경 대상

- `hardware_bram/src/grover_policy.v`
- `hardware_bram/configurations/final_200mhz/src/grover_policy.v`

a Checkpoint-Capacity of 3 and 3-shot Lookahead에 한해 `STATE_RANKS=127`, `MEM_ENTRIES=381`을 사용합니다. 최대 live address는
`2 × 127 + 126 = 380`입니다. 다른 Checkpoint-Capacity · Lookahead-Shots configuration은 `STATE_RANKS=1093`을 유지합니다.

## verification 명령

```sh
make -C hardware_bram/sim lint-real lint-configurations
make -C hardware_bram/sim real
make -C hardware_bram/configurations/final_200mhz/sim lint
make -C hardware_bram/configurations/final_200mhz/sim real
make -C hardware_bram/configurations/final_200mhz/sim QUICK=10 predicate500 predicate500-ref equiv
```

## 결과

공용 `real`과 200 MHz `real`은 T1~T10, driver D1~D11을 모두 통과했고 오류는 0이었습니다.
T10의 Checkpoint mode 실행(`T10 K4`)의 주요 policy counter는 다음과 같습니다.

| source | 전체 cycle | policy cycle | policy stall | action | hit | miss | cold | spec |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 공용 100 MHz | 40,274 | 6,748 | 1,081 | 1,030 | 225 | 348 | 1 | 27 |
| 200 MHz overlay | 44,080 | 11,089 | 2,768 | 1,030 | 225 | 348 | 1 | 27 |

첫 memo table 청소는 3,279에서 381로 줄어 두 source 모두 이전 배치보다 정확히 2,898 cycles
짧아졌습니다. policy 결과와 action/hit/miss counter는 유지됐습니다.

`QUICK=10`은 LT·GT·EQ·RANGE, number of solutions 다섯 값, Restart mode · Checkpoint mode 두 mode를 합쳐 400건을
실행했습니다. 두 source 모두 software reference model 대조를 통과했고, 공용과 200 MHz 사이에서 cycle을
제외한 전 열이 400/400 일치했습니다.

| mode | 공용 cycle sum | 200 MHz cycle sum | 200 MHz / 공용 cycle | 200 MHz / 공용 시간 |
|---|---:|---:|---:|---:|
| Restart mode | 4,700,643 | 4,934,719 | 1.0498 | 0.5249 |
| Checkpoint mode | 2,036,186 | 2,246,989 | 1.1035 | 0.5518 |

## synthesis 제한

`hardware_bram/synth/run_main_ip.sh`로 OOC synthesis를 시도했으나 실행 환경에서 유효한 Vivado
license를 얻지 못해 시작 단계에서 중단됐습니다. 따라서 RTL의 512×18 compact array가 실제
몇 개 RAMB로 배치되는지는 새 synthesis report가 생길 때까지 확정값으로 인용하지 않습니다.
