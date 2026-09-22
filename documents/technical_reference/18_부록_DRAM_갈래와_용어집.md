# 18장. 부록: DRAM 갈래와 용어집

> [← 17장 합성 · 구현 · 비트스트림](17_합성_구현_비트스트림.md) · [문서 지도](00_문서_지도.md)

---

## 18.1 BRAM과 DRAM 구현의 개발 상태

반복 실패 뒤 진폭을 재사용하는 방식에 따라 BRAM과 DRAM 두 구현을 개발하고 있습니다.
최종 방식은 물리 DRAM 구현과 성능 검증을 마친 뒤 선택할 예정입니다.

| 갈래 | 방식 | 상태 |
|---|---|---|
| [`hardware_bram/`](../../hardware_bram/) | 체크포인트(K3)로 차이만큼만 이어 돌리고, 반복 한 번에 연산기 네 벌(E4)이 협력. BRAM만 씁니다 | 보드 실물이 이쪽. 1~17장 전체 |
| [`hardware_dram/`](../../hardware_dram/) | `j` 별 진폭을 DRAM에 전량 저장. 체크포인트 K도 정책 H도 쓰지 않습니다 | RTL 초안 + 동작 수준 모델 위 회귀 |

### DRAM 구현 방식

`j` 별 진폭을 DRAM에 전부 저장하고, 난수 생성기가 뽑은 `j`는 BRAM 큐에도 올립니다.
정답 후보를 검증해 틀리면 큐에서 그 `j`를 지우고 DRAM에서 다음 `j` 진폭을 큐에
올립니다.

체크포인트도 정책도 없습니다: 모든 `j`가 버스트 한 번 거리에 있어서 계획할 것이
없기 때문입니다. [11장](11_체크포인트와_정책_엔진.md)에서 본 DP와 memo가 통째로
사라지는 대신, DRAM 대역폭이 비용이 됩니다.

### 구조

두 트리는 하위 구조가 같습니다(`src/` `testbench/` `sim/` `results/` `firmware/` `rvx/`
`vivado/`). BRAM에만 있는 폴더는 DRAM에 아직 없는 역할인 `synth/`와 `bitstream/`
둘입니다.

재사용 8개(`grover_param.vh` · `arithmetic` · `memories` · `iteration` · `measurement` ·
`loader` · `status` · `dram_random`)에 신규 5개가 붙습니다.

| 파일 | 역할 |
|---|---|
| `grover_dram_amp_store.v` | 반복마다 512행을 DRAM 슬롯에 store / 필요할 때 restore |
| `grover_dram_prep_seq.v` | 버퍼 A 준비 시퀀서. 체크포인트 K/H를 대신하는 자리 |
| `grover_dram_shot_fsm.v` | 외곽 BBHT 라운드 제어 |
| `grover_dram_queue.v` | 버퍼 A/B 두 벌과 역할별 포트 멀티플렉서 |
| `grover_dram_param.vh` | 슬롯 주소맵. 92바이트/행 × 512행 = 47,104바이트/슬롯 |
| [`bbht_dram_top.v`](../../hardware_dram/src/bbht_dram_top.v) | 이 갈래의 최상단. DRAM burst 포트를 밖으로 냄 |

통신 계층(`bbht_*`)은 `hardware_bram/src/`와 mmio · loader가 바이트 동일합니다.
같은 폴더의 `bbht_rvx_wrapper.v` + 어댑터는 포트 계약 대조용 판이라 DRAM을 안쪽에
묶어 두었고, 복원이 필요한 탐색에서 멈춥니다.

단일 탐색 전용이고 `enum_enable=1`은 `config_error`로 거절합니다.

### 검증

동작 수준 DRAM 모델(`testbench/dram_burst_model.v`, 지연·백프레셔가 전부 파라미터) 위에서
합니다.

```bash
make -C hardware_dram/sim          # ports lint store prep core top
make -C hardware_dram/sim equiv    # BRAM 정본과 궤적 대조 (40초 더)
```

`equiv`가 같은 자극을 `hardware_bram` 정본에도 걸어 탐색 궤적이 일치하는지 대조합니다.
대조 상대는 2026-09-09부터 K3/H3-E4-M2입니다(그전에는 K4/H4 였습니다).

최상위 모듈이 두 개이므로 `sim/Makefile`은 소스 파일을 명시적으로 나열합니다. glob을
사용하면 두 최상위 모듈이 동시에 포함될 수 있습니다.

### 미구현 항목

물리 DRAM 바인딩(MIG native UI 든 AXI4 든), 열거, 버퍼 B를 쓰는 라운드 간 프리페치,
RVX 설치 스크립트, Vivado 프로젝트.

---

## 18.2 폐기된 규격

다음 값은 이전 설계에서 사용했으나 현재 규격에는 적용되지 않습니다. `trash_bin/`의
문서는 모두 이전 규격을 기준으로 하므로 현행 설계의 근거로 사용하지 않습니다.

- 큐비트 수를 n = 15 나 n = 16으로 적은 것은 폐기됐습니다. 현행은 Q = 14입니다.
- 진폭 형식을 Q2.16이나 Q1.17로 적은 것은 폐기됐습니다. 현행은 signed 23비트, 소수부 22입니다.
- CSR 간격 8바이트는 폐기됐습니다. 현행은 4바이트입니다.
- INCR16 버스트 적재는 폐기됐습니다. 현행은 AHB SINGLE, single outstanding입니다.
- 진폭이 가장 큰 칸을 고르는 측정은 폐기됐습니다. 현행은 Born 규칙 정수 CDF입니다.
- 버스를 AXI4-Lite 나 AXI-Stream으로 적은 것은 폐기됐습니다. 현행은 APB 슬레이브 + AHB 마스터이고, RVX에 AXI-Stream 심이 없습니다.
- SoC를 MicroBlaze로 적은 것은 폐기됐습니다. 현행은 RVX rvc_orca입니다.
- 목표 칩을 XC7S100이나 Arty S7-50으로 적은 것은 폐기됐습니다. 현행은 Arty A7-100T (`xc7a100tcsg324-1`)입니다.

문서 검사기가 이 값들의 부활을 자동으로 잡습니다
([15장 15.8절](15_검증_체계.md)).

### 중간 단계였던 것

K4/H4 · K4/H8은 이제 중간 단계입니다. 2026-09-01(K4/H8) · 2026-09-04(K4/H4) 보드
실측 묶음은 그 시점 근거로 남겨 두었지만, 최종 성능을 인용할 자리가 아닙니다. 두
묶음은 250쌍(시드 50)이라 500 워크로드 캠페인과 총합을 맞댈 수도 없습니다.

---

## 18.3 용어와 약어

| 용어 | 뜻 |
|---|---|
| BBHT | Boyer–Brassard–Høyer–Tapp. 정답 수를 모를 때의 Grover 탐색 ([3장](03_Grover와_BBHT_알고리즘.md)) |
| 샷 (shot) | BBHT의 한 번의 시도. `j`를 뽑아 돌리고 측정해 검증하는 한 덩어리 |
| `j` | 한 샷에서 돌릴 Grover 반복 횟수. `[0, m)` 균등 |
| `m` | `j`를 뽑는 범위. 실패할 때마다 28엔트리 ROM을 따라 커집니다 |
| `L_BBHT` | 논리 반복 누적. 뽑힌 `j`의 합. 체크포인트로 줄지 않습니다 |
| 물리 반복 | 실제로 돌린 반복 수(`ACTUAL_ITER`). 체크포인트가 줄이는 대상 |
| 오라클 | 술어를 만족하는 칸의 진폭 부호를 뒤집는 단계. 정답 인덱스를 모릅니다 |
| 확산 | 평균 중심 반사. `2×평균 − 진폭` |
| Born 측정 | 진폭 제곱에 비례하는 확률로 인덱스를 뽑는 것 |
| 술어 | `LT` `GT` `EQ` `RANGE` 네 조건. 전부 strict |
| K | 체크포인트 슬롯 수. 확정 3 |
| H | 정책이 내다보는 미래 요청 수. 확정 3 |
| E | 물리 반복 한 번에 협력하는 연산기 수. 확정 4 |
| M | 측정 경로 최적화 단계. 확정 2 |
| M (워크로드) | 데이터셋에 심은 타겟 개수. 1/4/16/64/256 |
| quad | E4가 한 번에 처리하는 4행 묶음 |
| memo | 정책 DP의 부분 결과 저장소. 3,279엔트리 |
| Shadow-J | 실제 LFSR의 복사본으로 미래 `j`를 예측하는 장치 |
| plan FIFO | 선행 계획을 담아 두는 큐 |
| found_mask | 열거에서 이미 찾은 인덱스를 표시하는 비트맵 |
| RVX | 이 프로젝트가 쓰는 SoC 플랫폼 생성 환경 (`/opt/rvx`) |
| ORCA | RVX의 RV32 코어. 순수 소프트웨어 기준선의 주체 |
| user region | RVX SoC 안에 우리 IP가 들어가는 자리 |
| W1P | 쓰면 1사이클 펄스만 나가는 CSR 성격 |
| RPOP | 읽기 완료가 곧 pop 인 CSR 성격. `FIFO_DATA` 하나뿐 |
| OOC | Out-Of-Context 합성. 모듈 하나만 떼어 재는 방식 |
| WNS | Worst Negative Slack. 타이밍 여유 |
