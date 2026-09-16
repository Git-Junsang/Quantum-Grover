# SoC RTL 시뮬 — `bbht_console` 명령 왕복과 호스트 CLI 재생

## 무엇인가

RVX 플랫폼 `bbht_grover_upgrade` 전체(ORCA RISC-V 코어 · micro NoC · APB/AHB NI ·
우리 통신 계층 · Main IP)를 Questa 로 RTL 시뮬하면서 `bbht_console` 을 스크립트 모드로
돌린 결과입니다. 명령 21줄의 응답을 호스트 CLI `software/host/bbht_cli.py` 의 재생
트랜스포트에 그대로 먹여 파싱하고, 파싱한 숫자를 기준과 대조했습니다.

같은 날의 [`2026-09-16_soc_rtl_paper_bench`](../2026-09-16_soc_rtl_paper_bench/evidence.md)
가 "SoC 에서 CPU 가 통신 계층을 구동한다" 를 보였다면, 이 묶음은 **명령 파서 → 드라이버
→ CSR/DMA → Main IP → UART 응답 → 호스트 파서** 의 왕복을 보입니다.

## 앞선 기록의 정정 — "OK 직후에 멈춘다" 는 시험 절차의 잘못이었습니다

paper_bench 묶음에는 `bbht_console` 이 SoC 시뮬에서 시작 배너 `OK` 직후에 멈추고 원인을
못 찾았다고 적혀 있었습니다. **원인은 펌웨어도 RVX 도 RTL 도 아니고 제 시험 절차였습니다.**

- 스크립트 모드는 `-DBBHT_CONSOLE_SCRIPT` 로 켭니다. 이것을 앱 폴더에서
  `make rtl DEFINE_CFLAGS=...` 로 넘겨 빌드했습니다.
- 그런데 `sim_rtl` 의 `make bbht_console.sim` 은 시뮬 직전에 앱을 **스스로 다시
  빌드**합니다(`rtl.debug`). 그때는 명령줄 값이 없으니 시뮬에 실린 것은 UART 판이었고,
  UART 판은 설계대로 `read_line()` 에서 RX 입력을 기다렸습니다. RVX 시뮬 printf 모듈
  `ncsim_printf.v` 는 `uart_tx` 를 1 로 묶어 둬서 입력이 오지 않습니다.
- 당시 `sim_rtl/rvx_app_build.log` 에 `BBHT_CONSOLE_SCRIPT` 가 **0번** 나옵니다.
  루프 안에 넣은 표시 printf 가 안 나온 것, `uart_init()` 을 빼도 똑같이 멈춘 것도 둘 다
  `#ifdef BBHT_CONSOLE_SCRIPT` 안에 넣은 변경이라 애초에 빌드에 없었기 때문입니다.

고친 방법은 RVX 가 정한 앱별 설정 파일입니다.
[`firmware/bbht_console/rvx_each.mh`](../../firmware/bbht_console/rvx_each.mh) 에
`TARGET_IMP_CLASS=rtl` 일 때만 이 정의를 넣었습니다. 앱을 누가 언제 다시 빌드하든
RTL 시뮬 빌드에는 들어가고 보드 빌드에는 안 들어갑니다.

| 확인 | 결과 |
|---|---|
| `make bbht_console.sim` 이 다시 빌드한 로그의 `BBHT_CONSOLE_SCRIPT` | 0번 → 75번 |
| RTL 시뮬 ELF 안의 `script done` 문자열 | 있음 |
| 보드 빌드(`make arty-100t`) 로그의 `BBHT_CONSOLE_SCRIPT` | 0번 |
| 보드 빌드 ELF sha256, 이번 수정 전 `main.c` 대 후 | 둘 다 `535ba8cf…` — 바이트 동일 |
| 시뮬 | 2분 55초 만에 `QUIT` 까지 가서 정상 종료 |

## 확정 수치

`crosscheck.txt` 의 요약입니다. **어긋남 0건.**

| 검사 | 결과 |
|---|---|
| 명령 21줄의 에코 순서 = 호스트가 보낸 순서 | 21/21 |
| 종결자 (일부러 넣은 `ERR` 2줄 포함) | 21/21 |
| `ID` 응답 7값 대 CSR 정본 (`bbht_cli.py selftest`) | 7/7 |
| `POKE` 네 칸 = `dataset_target_4.bin` 의 12345 자리 `507 2852 4724 8685` | 일치 |
| `RUN`/`STAT` 3회 대 같은 순서 verilator (HIT 5 + STAT 15) | 60/60 |
| `ENUM` 대 같은 순서 verilator (FOUND 순서 · END cyc 280,494) | 일치 |

워크로드는 보드 500런의 **M = 4, 시드 0** 입니다. 콘솔은 `GEN TARGETS=0` 으로 12345 가
없는 배경을 만들고 `POKE` 네 줄로 같은 자리에 목표를 심습니다. EQ 술어는 12345 인
칸만 보므로 오라클 표시가 보드 데이터셋과 같고, 보드 데이터셋을 그대로 쓴 verilator
기준과 모든 값이 같게 나왔습니다.

| RUN | 기준 | result_index | trial | L_BBHT | actual_iter | cycle_count |
|---|---|---:|---:|---:|---:|---:|
| 1. NORMAL | bench500 · SoC paper_bench | 8685 = | 21 = | 119 = | 119 = | 41,310 = |
| 2. 체크포인트, 리셋 뒤 첫 번째 | 6단계 캠페인 K3/H3-E4-M2 | 8685 = | 21 = | 119 = | 38 = | 20,935 = |
| 3. 체크포인트, 두 번째 | 보드 M2 · bench500 · SoC paper_bench | 8685 = | 21 = | 119 = | 38 = | 17,847 (보드 17,656) |

## 체크포인트 사이클은 실행 이력에 달려 있습니다

RUN 2 와 RUN 3 은 설정 · 데이터 · 시드가 전부 같고 사이에 리셋만 없습니다. 궤적은 같은데
사이클이 20,935 와 17,847 로 다릅니다. 차이는 전부 `policy_stall` 입니다.

**리셋 뒤 첫 체크포인트 탐색의 +3,279 사이클 — 원인 확인.**
`grover_policy.v` 는 memo BRAM 이 리셋으로 지워지지 않아서, 리셋 뒤 첫 시작과 epoch 가
한 바퀴 돌 때 `ST_CLEAR` 상태에서 memo 를 한 칸씩 지웁니다. 길이가
`MEM_ENTRIES = H_FUTURE × STATE_RANKS = 3 × 1,093 = 3,279` 사이클입니다. RUN 2 는
연달아 도는 bench500 의 같은 행보다 cycle · policy_cycles · policy_stall 이 **셋 다
정확히 +3,279** 이고, `max_latency` 가 3,352 로 튀어 있습니다.

그래서 보드 500런 묶음이 "원인을 확인하지 않았다" 고 적어 둔 **6단계 캠페인과 보드의
M2 473/500 이 정확히 3,279 사이클 차이** 는 이 memo 청소로 설명됩니다. 6단계 캠페인은
워크로드마다 새로 시작해서 매번 청소를 치르고, 보드 앱과 bench500 은 500개를 연달아
돌아 첫 워크로드에서 한 번만 치릅니다. 이 묶음에서 직접 확인한 것은 한 워크로드이고,
473건 전부를 이 방식으로 다시 돌려 보지는 않았습니다. 나머지 21건이 제각각인 이유
(epoch 한 바퀴마다 붙는 청소가 어느 워크로드에 떨어지느냐로 보이지만)도 확인하지
않았습니다.

**그다음 탐색의 +191 사이클.** RUN 3 은 bench500 의 같은 행보다 policy_stall 이 191,
policy_actions 가 87 많습니다. 직전 탐색이 RUN 2(같은 워크로드)인 콘솔과 M = 1 시드 99
인 bench500 이 달라서 정책 엔진이 남긴 상태가 다르기 때문입니다. **무엇이 남는지는
확인하지 않았습니다.** 다만 이것이 통신 계층이나 펌웨어 탓이 아니라는 것은 확인했습니다
— 같은 RTL 을 콘솔과 같은 순서로 두드린 verilator 하네스
(`testbench/tb_console_seq.cpp`)가 RUN 3 의 17,847 과 STAT 15값을 전부 똑같이 냅니다.

결론적으로 **보드에서 콘솔로 돌린 체크포인트 사이클은 보드 500런 표와 같게 나올 이유가
없습니다.** 논리 4축은 같아야 하고, 사이클은 직전에 무엇을 돌렸는지와 함께 보아야 합니다.

## 확인하지 않은 것

- **물리 UART.** 시뮬 printf 모듈이 115200 baud 로 받아 해독했지만 FTDI · 보율 오차 ·
  핀맵은 보드에서만 봅니다.
- **호스트 → 보드 방향 바이트.** 스크립트 모드는 명령을 컴파일 시점 배열에서 읽습니다.
  UART RX · 에코 · 백스페이스 처리 코드(`read_line()` 의 UART 판)는 시뮬에서 돌지
  않았습니다. `bbht_cli.py` 의 `SerialTransport` 도 마찬가지입니다.
- **워크로드 하나.** M = 4 시드 0 만 돌렸습니다. 나머지 워크로드의 SoC 경로 근거는
  paper_bench 묶음(261쌍)입니다.
- **`amp_overflow` 줄, `REG` · `HELP` 명령.** 스크립트에 넣지 않았습니다.

## 파일

| 파일 | 내용 |
|---|---|
| `transcript.txt` | `qtsim.log` 에서 떼어 Questa 머리말을 벗긴 콘솔 출력. `bbht_cli.py --port replay:` 에 그대로 먹일 수 있습니다 |
| `crosscheck.txt` | `soc_console_check.py` 출력 원문 |
| `verilator_seq.csv` | `make console-seq` 출력. 콘솔과 같은 순서의 기준값 |

## 재현

```bash
source /opt/rvx/rvx_setup.sh
hardware_bram/rvx/install_to_platform.sh              # rvx_each.mh 까지 옮깁니다
cd $RVX_MINI_HOME/platform/bbht_grover_upgrade        # make syn · make sim_rtl 은 한 번만
cd sim_rtl && make bbht_console.sim                   # 3분쯤
grep -c BBHT_CONSOLE_SCRIPT rvx_app_build.log         # 0 이면 스크립트 모드가 아닙니다

cd <저장소>
make -C hardware_bram/sim console-seq                 # 30초쯤
python3 hardware_bram/sim/soc_console_check.py \
    $RVX_MINI_HOME/platform/bbht_grover_upgrade/sim_rtl/qtsim.log \
    --ref /tmp/sjs_console_seq/console_seq.csv --transcript transcript.txt
```
