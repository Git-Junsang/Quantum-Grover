# Candidate cache physical-resource collection

기존에 진행 중인 최신 banked-cache RTL의 OOC synthesis에서 candidate cache와 memo의
primitive를 따로 수집합니다. 전체 SoC fitting 경계나 새로운 resource model은 만들지 않습니다.

대상은 고정 iteration PEs / square engines에서 Checkpoint-Capacity · Lookahead-Shots를
늘리는 세 구성입니다: `k5h7e4m4`, `k6h8e4m4`, `k7h8e4m4`.
원래 합성 대기열이 실행하는 작업을 재사용하며 이 수집기는 Vivado를 실행하지 않습니다.
같은 대기열의 다른 완료 구성에서도 cache별 report가 생성되면 기준 자료로 보존합니다.

[`policy_cache_report.tcl`](../../../synth/policy_cache_report.tcl)은 synthesis가 끝나고 design이
열려 있을 때 memory 이름에 해당하는 primitive를 기록합니다. native `report_ram_utilization`이
지원되면 전체 memory 상세 report도 보존합니다. 집계 오류가 원래 synthesis 작업을 실패시키지 않게 합니다.

[`collect_policy_cache.py`](../../../sim/collect_policy_cache.py)는 이 report와 manifest를 복사하고
candidate cache의 RAMB36 · RAMB18 수, distributed RAM primitive와 이름으로 확인되는 LUT · FF를
memo와 구분합니다. 이름으로 분류한 LUT · FF는 공유되거나 재명명된 cache 제어 회로 전체를
완전히 분리한 값이 아닙니다. distributed RAM primitive 수를 LUT 개수로 읽지 않습니다.
cache에 해당하는 primitive가 확인되지 않으면 0으로 확정하지 않고 미분류로 기록합니다.

source hash가 다른 solver 결과는 같은 implementation의 K/H scaling 결과로 합치지 않습니다.
기존 K3H3 전체 solver 계층 report만으로 candidate cache 단독 사용량을 확정하지 않습니다.

## 확인 주기

사용자 지시대로 결과 확인 주기는 1,800초입니다. 준비 시점에 한 번 확인한 뒤 다음 확인부터
30분 간격으로만 읽습니다. 세 대상의 결과를 확보하면 종료하고, 합성 runner가 종료했는데
결과가 없으면 그 상태를 기록하고 종료합니다. 중복 합성이나 자동 재시도는 수행하지 않습니다.

실행 상태는 [watcher.json](watcher.json), 마지막 확인 결과는 [status.json](status.json)입니다.
실측값을 확보하면 이 directory에 `measured_cache.csv`와 구성별 원 report가 생성됩니다.
