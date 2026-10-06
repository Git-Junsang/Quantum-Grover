# 21장. 체크포인트 없는 BRAM 판

> [← 20장 합성 · 구현 · 비트스트림](20_합성_구현_비트스트림.md) · [문서 지도](00_문서_지도.md) · [22장 DRAM 갈래 →](22_DRAM_갈래.md)

---

BRAM 갈래는 연산기 네 벌(E4) 위에 체크포인트(K3/H3)와 측정 최적화(M1/M2)를 얹은
구성입니다. 이 판은 그중 **연산기 네 벌만 남기고 나머지 최적화를 모두 끈 것**입니다.
같은 보드 · 같은 SoC · 같은 연산기 위에서 최적화를 켰을 때와 껐을 때의 속도를 맞대려는
비교 기준이고, 새 알고리즘이 아닙니다.

이 판은 2026-09-25 에 따로 만든 트리였고, 2026-10-06 부터는 BRAM 갈래의 한 모델
`hardware_bram/models/hardware_bram_nocheckpoint/` 입니다.

---

## 21.1 체크포인트 판과 다른 점

모델 열 개 사이의 자리는 [5장 5.2절](05_하드웨어_아키텍처_개요.md#하드웨어-트리와-bram-모델)에
있습니다. 체크포인트 판(최종 구성 `K3H3_E4_M2`)과는 컴파일 파라미터만 다릅니다.

| 파라미터 | 체크포인트 판 | 체크포인트 없는 판 |
|---|:-:|:-:|
| `CHECKPOINT_ENABLE` | 1 | **0** |
| `CKPT_K` · `POLICY_H_FUTURE` | 3 · 3 | (쓰이지 않음) |
| `INTRA_ENGINES` | 4 | 4 |
| `MEAS_M1_ENABLE` · `MEAS_M2_ENABLE` | 1 · 1 | **0 · 0** |

---

## 21.2 소스를 어떻게 나눴나

이 판은 소스를 거의 갖지 않습니다. 다른 모델처럼 통신 계층 · Main IP · user region · 펌웨어는
`hardware_bram/` 공용 것을 **그대로** 쓰고, 이 판에만 있는 RTL 은 어댑터 하나입니다.

| 파일 | 역할 |
|---|---|
| `src/bbht_grover_core_adapter.v` | 체크포인트 판 어댑터와 포트 · 결선이 같고 다른 것은 둘. 파라미터 기본값(위 표), 그리고 `burst_enable` 을 Main IP 에 0 으로 넘기는 것 |
| `sim/Makefile` · `sim/equiv_check.py` | 회귀 · Predicate500 · 기준 대조 (21.4절) |
| `rvx/bbht_grover_nocheckpoint.xml` · `rvx/install_to_platform.sh` | RVX 플랫폼. SoC 구성은 `bbht_grover_upgrade` 와 같음. 설치는 공용 설치기가 함 |

Main IP 를 복사하지 않은 이유는 두 판이 **같은 RTL 을 파라미터만 달리 컴파일한 것**이어야
비교가 공정하기 때문입니다. 복사본을 두면 한쪽만 고쳐지는 순간 비교가 깨집니다. `Normal_E1`
모델도 같은 어댑터에서 연산기 수만 1 로 바꾼 것입니다.

`burst_enable` 을 막는 이유: `CHECKPOINT_ENABLE=0` 인 Main IP 에 `burst_enable=1` 을 주면
`grover_bbht` 의 옛 "한 벌 캐시 이어 돌리기"(v0.8 burst)가 살아납니다. 그것도 진폭을
재활용하는 최적화라 이 판의 취지와 맞지 않고, E4 위에서는 검증한 적도 없습니다. 그래서
`SET BURST=1` 을 보내도 NORMAL 로 돕니다. DRAM 갈래가 BURST 를 무시하는 것과 같은 약속이고,
호스트 자동 테스트는 `ID` 의 `platform=bbht_grover_nocheckpoint` 를 보고 NORMAL 만 돌립니다.

---

## 21.3 Main IP 에서 바꾼 것 — E4 를 체크포인트에서 떼어 냄

전에는 E4 연산기와 M1/M2 가 `CHECKPOINT_ENABLE=1` 일 때만 생겼습니다. 체크포인트를 끄면
연산기가 한 벌(E1)로 돌아가 버려서, "체크포인트만 뺀" 판을 만들 수 없었습니다.

`hardware_bram/src/bbht_grover_main_ip.v` 에서 세 곳을 고쳤습니다.

| 자리 | 전 | 후 |
|---|---|---|
| E4 generate 조건 | `INTRA_ENGINES == 4 && CHECKPOINT_ENABLE != 0` | `INTRA_ENGINES == 4` |
| 측정 모듈 `AMP_READ_LATENCY` | `CHECKPOINT_ENABLE ? 2 : 1` | `(CHECKPOINT_ENABLE \|\| INTRA_ENGINES == 4) ? 2 : 1` |
| `E4_DUAL_BUILD` · `E4_HIER_SELECT` | E4 · 체크포인트 · M 스위치 | E4 · M 스위치 |

이렇게 해도 되는 근거는 이미 RTL 안에 있었습니다. 체크포인트 판에서 NORMAL 을 돌리면
`ckpt_exec_mode=0` 이라 E4 진폭 메모리의 읽기 · 쓰기 · 측정 슬롯이 모두 0 으로 묶이고,
Planner · Executor · 정책 엔진은 쉬고 있습니다. 체크포인트를 끈 판은 그 쉬는 하드웨어를
generate 로 뺀 것일 뿐, 도는 경로는 같습니다. `CHECKPOINT_ENABLE=1` 에서는 세 식 모두
전과 같은 값이 되므로 체크포인트 판은 바뀌지 않습니다(21.4절에서 확인).

E2 는 여전히 체크포인트가 있어야 생깁니다. 이 판에 필요하지 않아서 건드리지 않았습니다.

---

## 21.4 검증

| 단계 | 결과 | 근거 |
|---|---|---|
| 포트 계약 | wrapper 19 + core 61 일치 (`check_ports.py nocheckpoint`) | `make -C hardware_bram/models/hardware_bram_nocheckpoint/sim ports` |
| 통신 계약 T1~T10 (실물 코어) | 오류 0. T10 의 burst 요청이 NORMAL 과 같은 121,427 사이클, 정책 카운터 0 | `make -C hardware_bram/models/hardware_bram_nocheckpoint/sim real` |
| Predicate500 대 SW 기준모델 | NORMAL 2,000/2,000, 여섯 축 전부 | [`hardware_bram/models/hardware_bram_nocheckpoint/results/2026-09-25_predicate500_rtl/`](../../hardware_bram/models/hardware_bram_nocheckpoint/results/2026-09-25_predicate500_rtl/evidence.md) |
| 체크포인트만 뺐는가 | 체크포인트 판을 M1=M2=0 으로 빌드한 NORMAL(지금의 `K3H3_E4` 모델, `predicate500-ref`)과 **사이클 · STATUS 까지 8 열 2,000/2,000** | 같은 묶음 `equiv.txt` |
| 체크포인트 판이 안 바뀌었는가 | `ports lint regress real top` 통과, Predicate500 4,000 행이 2026-09-25 결과와 전 열 같음 | [`hardware_bram/models/hardware_bram_K3H3_E4_M2/results/2026-09-25_predicate500_rtl/`](../../hardware_bram/models/hardware_bram_K3H3_E4_M2/results/2026-09-25_predicate500_rtl/evidence.md) 와 대조 |
| SoC RTL 시뮬 | 콘솔 16실행이 SW 기준모델과 16/16, 데이터셋 해시 8/8, 사이클도 verilator 와 16/16 같음 | [`hardware_bram/models/hardware_bram_nocheckpoint/results/2026-09-25_soc_rtl_predicate500/`](../../hardware_bram/models/hardware_bram_nocheckpoint/results/2026-09-25_soc_rtl_predicate500/evidence.md) |
| 구현 | 100 MHz WNS +0.193 ns | [`vivado/.../2026-09-25_nocheckpoint_build/`](../../hardware_bram/models/hardware_bram_nocheckpoint/vivado/vivado_bbht_grover_nocheckpoint/2026-09-25_nocheckpoint_build/evidence.md) |
| 보드 (2026-10-04) | NORMAL 2,000/2,000, RTL 벤치와 사이클까지 2,000/2,000 | [`vivado/.../2026-10-04_board_predicate500/`](../../hardware_bram/models/hardware_bram_nocheckpoint/vivado/vivado_bbht_grover_nocheckpoint/2026-10-04_board_predicate500/evidence.md) |

한 번 헛디딘 것을 적어 둡니다. 처음 `make real` 은 이 판의 어댑터를
`../src/bbht_grover_core_adapter.v` 로 넘겼는데, verilator 는 상대경로 파일을 `-I`
디렉터리 기준으로 먼저 찾아서 **체크포인트 판 어댑터**를 집어 왔습니다. T10 에 정책
카운터가 찍혀서 알아챘고, 지금은 어댑터를 `/tmp` 로 복사해 절대경로로 넘기고 파라미터
값을 grep 으로 확인합니다. Predicate500 빌드는 처음부터 빌드 폴더에 복사해 썼으므로
영향이 없었습니다.

---

## 21.5 최적화 유무에 따른 속도 (RTL 사이클)

같은 2,000 워크로드, 같은 하네스, 가속기 100 MHz 사이클입니다.

| 구성 | 네 술어 합 | 이 판 대비 |
|---|---:|---:|
| 체크포인트 없는 판 (E4) | 61,109,590 | 1.000x |
| 체크포인트 판 NORMAL (E4-M2) | 46,886,677 | 1.303x |
| 체크포인트 판 체크포인트 (K3/H3-E4-M2) | 21,093,126 | **2.897x** |

측정 최적화 M1/M2 가 약 1.3배, 체크포인트가 그 위에 약 2.2배를 벌어 합쳐서 약 2.9배입니다.
M = 1 에서 3.04배, M = 256 에서 2.46배로, 희소할수록 체크포인트 몫이 큽니다. 술어별 · M별
표는 [결과 묶음](../../hardware_bram/models/hardware_bram_nocheckpoint/results/2026-09-25_predicate500_rtl/evidence.md)에
있습니다.

이것은 **RTL 사이클 축**입니다. 6단계 ablation(EQ 한 술어, K4/H4 를 거친 사다리)과는
단계가 달라 배수를 섞으면 안 됩니다.

같은 비교를 2026-10-04 에 보드 실경과 시간으로 했습니다. 두 비트스트림을 같은 보드에 차례로
굽고 `bbht_predicate500.py` 로 같은 2,000 워크로드를 돌렸습니다.

| 구성 | 실경과 합 | 이 판 대비 실경과 | 이 판 대비 보드 사이클 |
|---|---:|---:|---:|
| 체크포인트 없는 판 (E4) | 621,210 us | 1.000x | 1.000x |
| 체크포인트 판 NORMAL (E4-M2) | 478,975 us | 1.297x | 1.303x |
| 체크포인트 판 체크포인트 (K3/H3-E4-M2) | 221,032 us | **2.810x** | 2.897x |

보드 사이클 배수는 위 RTL 표와 같습니다. 실경과 배수가 조금 작은 것은 실행마다 붙는 고정
4~7 us 때문입니다. M 별로는 M = 1 에서 3.00배, M = 256 에서 2.25배입니다
([18장 18.4절](18_보드_확인과_실측.md#184-2026-10-04-세-판의-predicate500)).

SoC RTL 시뮬(실제 RISC-V 가 콘솔을 돌림)은 DRAM 갈래와 같은 16실행(네 술어 × M 64·256 ×
시드 2 × NORMAL)으로 돌려 16/16 맞았고, 사이클도 verilator 와 16/16 같습니다. 결과는
[`hardware_bram/models/hardware_bram_nocheckpoint/results/2026-09-25_soc_rtl_predicate500/`](../../hardware_bram/models/hardware_bram_nocheckpoint/results/2026-09-25_soc_rtl_predicate500/evidence.md)
에 있습니다.

---

## 21.6 자원

| 항목 (전체 SoC) | 체크포인트 없는 판 | 체크포인트 판 (2026-09-16) |
|---|---:|---:|
| WNS | +0.193 ns | +0.196 ns |
| LUT / FF | 38,133 / 38,634 | 45,116 / 45,210 |
| BRAM 타일 / DSP | 111 / 68 | 116 / 132 |

DSP 64 개 차이는 전부 측정 블록입니다(M1 이 Born 제곱을 사이클당 두 행 하므로 곱셈기가 두
배). BRAM 은 정책 memo 만큼만 줄었습니다. E4 진폭 메모리는 슬롯 0 만 쓰지만, 736비트 행을
담는 RAMB36 은 폭으로 개수가 정해져 깊이를 줄여도 타일이 줄지 않습니다.

---

## 21.7 돌리는 법

```bash
# 시뮬 (저장소 루트)
make -C hardware_bram/models/hardware_bram_nocheckpoint/sim                     # ports + lint + real
make -C hardware_bram/models/hardware_bram_nocheckpoint/sim predicate500 predicate500-ref equiv

# RVX 플랫폼과 비트스트림
source /opt/rvx/rvx_setup.sh
mkdir -p $RVX_MINI_HOME/platform/bbht_grover_nocheckpoint
cp $RVX_MINI_HOME/platform/tip_hello/Makefile $RVX_MINI_HOME/platform/bbht_grover_nocheckpoint/
hardware_bram/models/hardware_bram_nocheckpoint/rvx/install_to_platform.sh
cd $RVX_MINI_HOME/platform/bbht_grover_nocheckpoint
make syn && make imp_fpga TARGET_IMP_CLASS=arty-100t
cd imp_arty-100t_<날짜> && make imp && make bbht_console     # 7분쯤

# 보드 (굽기와 앱 올리기는 bitstream 묶음 설명대로)
python3 software/host/bbht_predicate500.py --port /dev/ttyUSB1   # NORMAL 2,000 실행
```

RVX `user/` 뼈대를 빠진 것만 채우는 이유는 [17장 17.1절](17_보드_운용.md#171-플랫폼-설치와-생성)에 있습니다.
