# Qiskit·NumPy 서버 벤치마크 업로드본

## 구성

이 폴더는 v0.9.8 Q14 Grover/BBHT의 NumPy 기준 모델과 Qiskit Aer 비교를
서버에서 실행하기 위함. 

| 파일 | 역할 |
| --- | --- |
| `qiskit_three_way_benchmark.py` | requested-j NumPy·Qiskit 정답성과 시간 비교 |
| `qiskit_bbht_benchmark.py` | BBHT 전체 다중 attempt를 여러 seed로 비교 |
| `merge_fpga_benchmark.py` | 추후 FPGA cycle을 3자 결과에 결합 |
| `qiskit_grover.py` | Qiskit Aer Grover 상태벡터 코어 |
| `qiskit_bbht.py` | v0.9.8 BBHT 제어 흐름 |
| `grover_core_float.py` | NumPy Float64 기준 코어 |
| `rtl_v098_*.py`, `rtl_v07g.py` | 동결된 v0.9.8 규격·데이터·난수·제어 의미 |
| `config.py`, `models.py`, `trace.py` | NumPy 코어 공통 의존 파일 |
| `requirements-qiskit.txt` | Python 패키지 요구사항 |
| `실험_및_시간구간_가이드.md` | 비교 범위와 결과 해석 |
| `run_server_campaign.sh` | 공식 두 캠페인 순차 실행 |

## 1. 압축 해제 후 확인

```

Qiskit을 불러오지 못할 때만 별도 가상환경에 설치한다.

```bash
python3 -m venv .venv-qiskit
.venv-qiskit/bin/python -m pip install -r requirements-qiskit.txt
export PYTHON=.venv-qiskit/bin/python
```

## 2. 빠른 사전 검사

```bash
${PYTHON:-python3} qiskit_three_way_benchmark.py \
  --preset SMOKE --threads 1 --repeats 1 --warmups 0 \
  --output verification_results/smoke
```

`verification_results/smoke/timing_summary.csv`가 생성되면 실행 환경이 정상이다.

## 3. 공식 서버 캠페인

두 실험은 CPU 자원 간섭을 막기 위해 순차 실행한다.

```bash
nohup bash run_server_campaign.sh > server_campaign.out 2>&1 &
echo $! > server_campaign.pid
```

진행 확인:

```bash
tail -f server_campaign.out
```

완료 확인:

```bash
ps -p $(cat server_campaign.pid)
```

## 4. 결과

| 폴더 | 주요 파일 |
| --- | --- |
| `verification_results/qiskit_three_way_server_1thread` | `raw_timings.csv`, `timing_summary.csv`, FPGA 입력·빈 결과표 |
| `verification_results/qiskit_bbht_server_50seed` | `bbht_raw.csv`, `bbht_attempts.csv`, `bbht_summary.csv`, FPGA 빈 결과표 |

requested-j는 상태벡터와 성공확률의 정확한 일치를 검증한다. BBHT는 여러 seed의
최종 성공률, attempt 수, `L_BBHT`, 실행시간 분포를 검증한다. 두 결과는 목적이
다르므로 하나의 평균으로 합치지 않는다.

## 5. 서버 기록

최종 결과와 함께 다음 명령의 출력도 보관한다.

```bash
python3 --version
lscpu
free -h
uname -a
```

서버 CPU 코어 수, Python·NumPy·Qiskit·Aer 버전, thread 수가 없으면 다른
시스템의 측정값과 공정하게 비교할 수 없다.
