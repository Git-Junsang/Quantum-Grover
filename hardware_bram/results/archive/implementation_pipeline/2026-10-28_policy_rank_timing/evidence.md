# Policy value-rank key 전달과 분리된 200T 재구현

사용자 요청으로 기존 두 구현의 결과를 한 번 조회했습니다. 기존 Dual-Row Build는 setup 미통과,
Triple-Row Build도 setup 미통과입니다. 이 묶음은 그 결과에 따라 수정한 새 source이며,
기존 bitstream이나 일반화 개발 source와 구분합니다. 기존 수치는 각 platform의 route report가 근거입니다.

## 변경과 기능 검사

기존 최악 경로는 rk_pos에서 후보 선택과 반복 rank lookup/sort를 지나 pending rank까지 이어졌습니다.
SCAN 각 lane에서 value-rank key를 기존 세 data 단계에 맞춰 계산·전달하고, lane reduction과
최종 선택이 그 key를 같이 선택하도록 고쳤습니다. canonical replay는 등록된 cache packet에서 한 번 변환합니다.
제어 대기 상태나 timing-only action queue는 추가하지 않았습니다.

`before/grover_policy.v`가 수정 전, `source/grover_policy.v`가 제출한 수정본입니다.
`unit_results.json`의 15 variants, 2,232 cases가 exhaustive reference와 일치했습니다.
이 검사는 setup timing 통과를 뜻하지 않습니다.

## 백그라운드 제출

platform: `bbht_grover_k3h3_e4_m2_rankfix_20261028`.
기존 Dual-Row Build · Two-Level Select, policy mode 6, accelerator 100 MHz / system 50 MHz,
200T 전체 자원을 유지합니다. `background_pid.json`에 제출 정보가 있습니다.

worker는 단독 회귀·Common500·전체 SoC를 검사한 다음 Vivado 하나, threads=2로 실행합니다.
같은 RTL에 대해 Explore, ExtraTimingOpt, AltSpreadLogic_high 계열의 세 전략을 순차 시도합니다.
각 시도의 report를 `implementation_attempt_*`에 보존하고 WNS/WHS가 모두 통과하면 중단합니다.
모두 실패하면 실패를 기록하고 종료합니다. clock 완화나 false path 추가는 하지 않습니다.
통과할 경우 같은 source의 board Common500 비교와 flash 설계 복구까지 이어집니다.

설치된 Vivado command manual로 directive를 확인하고 두 번째 시도의 opt_design 값을
ExploreWithRemap으로 정정했습니다. 재제출 worker는 지원되는 directive를 직접 사용하므로
최초 제출을 위해 추가했던 임시 Tcl 호환 hook은 제거했습니다.

`pipeline_inputs.json`의 RTL·app 입력 28개는 일반화 개발에서 덮어쓰지 않습니다. 추가 구현 제어 파일도
hash로 기록했습니다. 일반화 모듈은 이 snapshot이나 platform에 설치하지 않았습니다.

사용자 지시에 따라 제출 뒤 assistant가 배치배선 완료 여부를 반복 조회하지 않았습니다.
따라서 이 문서는 새 구현의 timing 통과나 board 검증 완료를 선언하지 않습니다. 이후 요청 시
`pipeline_state.json` 및 해당 시도의 report로 판정해야 합니다. commit도 수행하지 않았습니다.

## 사용자 요청 조회와 재제출

추가 조회에서 최초 worker가 console reference compile 오류로 중단된 것을 확인했습니다.
따라서 최초 제출은 Vivado implementation에 도달하지 못했고 세 전략 재시도도 수행하지 않았습니다.
`recovery_1/pipeline_state.json`, `pipeline.log`, `console_build.log`에 당시 기록을 보존했습니다.

원인은 복사한 console observer가 이전 driver struct의 trial_count/l_bbht/actual_iter 필드명을
사용한 것입니다. RTL·driver·firmware를 바꾸지 않고 별도의 observer 사본만 현재 필드명
shot_count/requested_iterations/executed_iterations에 맞췄습니다. 차이는
`recovery_1/observer.patch`에 있습니다. 참조 모델을 foreground에서 compile·실행하여 통과했고
`recovery_1/console_preflight.json`에 입력·출력 hash를 기록한 뒤 재제출했습니다.

수정 RTL의 Common500은 500 workloads 검증 통과, policy 80,719 cycles,
policy stall 16,363 cycles, checkpoint 전체 5,150,965 cycles로 기존 기능 결과를 유지했습니다.
`k3h3_e4_b2_p6/sim.json`이 근거입니다. 완료한 2,232개 unit test도 source hash를 대조한 뒤 재사용합니다.

재제출 정보는 `background_pid.json`입니다. 전체 SoC → implementation 최대 세 전략 →
timing 통과 시 board 검증으로 이어집니다. 재제출 후 implementation 진행·완료 여부를 다시 조회하지 않았습니다.

## 2026-10-29 요청 조회: 합성 중 종료와 serial synthesis 재제출

위 문단은 당시 제출 기록입니다. 이후 사용자의 별도 조회 요청으로 세 시도의 종료를 확인했습니다.
전체 SoC는 [soc_equivalence.json](soc_equivalence.json)의 90 checks, errors / warnings 0으로 통과했습니다.
각 `implementation_attempt_1` / `implementation_attempt_2` / `implementation_attempt_3`의
`vivado.log`에는 synthesis 중 주 Vivado가 `Killed`로 종료된 기록이 있습니다.
`result.log`는 모두 bitstream 없음이며 route timing report도 생성되지 않았습니다.
따라서 세 시도를 setup timing 실패로 분류하지 않습니다. board 단계도 시작되지 않았습니다.
RVX 외부 make가 exit 0을 반환했어도 별도 bitstream / timing gate가 실패를 잡았습니다.

code-server service의 메모리 한도는 10 GiB이고 실행 환경의 OOM kill counter가 존재합니다.
개별 Vivado PID의 kernel OOM event를 확보하지는 않았으므로 `Killed`의 직접 원인은 확정하지 않습니다.
local Vivado parameter 조회에서 `general.maxThreads=1`일 때도 `synth.maxThreads` 기본값이 7인 것을
확인했습니다. 둘 다 1로 설정하는 Tcl은 local tool에서 정상 수락됨을 확인했습니다.

[retry_low_memory_20261029.py](retry_low_memory_20261029.py)를 별도 worker로 제출했습니다.
기존 입력 28개와 보호 firmware hash를 다시 대조하고 완료한 동일 source의 Common500 / SoC 검사를
재사용합니다. 일반 / 합성 스레드를 각각 1로 제한하는 `syn_manually.tcl`과 기존 Explore 계열 PNR
전략을 사용합니다. RTL · app · clock constraints를 수정하지 않고 새 일반화 RTL도 설치하지 않습니다.

제출 PID와 worker hash는 [retry_low_memory_background_pid.json](retry_low_memory_background_pid.json),
추가 구현 제어 입력은 `recovery_low_memory_20261029/inputs.json`에 기록합니다.
worker는 기존 Vivado lock을 잡고 구현 하나만 수행하며 bitstream 및 WNS / WHS gate를 통과한 경우에만
이미 승인된 board 비교 / flash 설계 복구로 이어집니다. 실패하면 기록하고 종료합니다.
재제출 후 assistant가 완료 여부를 조회하지 않았으므로 이 문서는 재시도 성공을 선언하지 않습니다.

## 4차 실행 결과 (2026-10-29 조회)

4차 실행은 2026-10-29 04:32 (Asia/Seoul)에 `failed`로 끝났습니다. synthesis와 placement · routing은 끝까지
진행되어 bitstream이 생성되었으나 WNS **-14.718 ns** / WHS +0.056 ns로 setup timing gate를 통과하지 못했고,
board 비교는 시작하지 않았습니다. 판정 값은 `implementation_attempt_4_low_memory/`의 `result.log` ·
`route_timing_summary.rpt`, 종료 상태는 `recovery_low_memory_20261029/pipeline_state.json`과
`retry_low_memory_20261029.log`에 있습니다. 이 결과를 받아 RTL을 다시 고치거나 재구현하지 않았습니다.
