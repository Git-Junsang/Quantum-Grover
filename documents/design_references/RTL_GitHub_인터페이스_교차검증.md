# 전달 RTL·GitHub·골든 모델 인터페이스 교차검증

> **2026-08-22 감사 기록이다.** 그때는 CSR 도 base address 도 열거 경계도 정해지지
> 않았고, 이 감사가 그 미결을 목록으로 만들었다. 지금은 v0.9.8 이 보드에서 검증돼
> 전부 닫혔다 — 무엇이 어떻게 닫혔는지는 6절에 있다. **여기 나오는 "미구현"·"미정"
> 을 현재 상태로 읽지 말 것.**
>
> 그래도 남겨 두는 이유는 두 가지다. 하나는 5절의 8-case bit-exact 회귀가 지금도
> 유효한 회귀 기준이라는 것, 다른 하나는 4절이 **어떤 표현이 왜 위험한지**를 적어
> 두었다는 것이다. 4.6절의 "실패 후 붕괴 상태가 아니라 측정 직전 checkpoint" 같은
> 구분은 지금도 그대로 지킨다.

## 1. 감사 목적

이 보고서는 다음 세 문서가 실제 구현과 일치하는지 추적했다.

- `Main_IP_포트_규격.md`
- CSR 주소맵 제안안 (폐기. 지금은 [CSR_레지스터_규격.md](CSR_레지스터_규격.md))
- `데이터_고정소수점_메모리_규격.md`

감사일: 2026-08-22

## 2. 비교한 정본

| 구분 | 식별자 | 사용 범위 |
| --- | --- | --- |
| 최신 전달 RTL | `v0.7g composite`, 2026-08-20 ZIP | Main IP 포트, Q14/F22 산술, loader, cache, BBHT, 측정 |
| 전달 TB | Normal/Burst j=1/4/8/6 8-case | handshake, index, Born W, counter, cycle 관측값 |
| GitHub | commit `7b96551c3d2354dc02121ecdc256972c81bf9e93` | legacy APB/AHB 구조와 실제 legacy CSR offset |
| 골든 모델 | `rtl_v07g.py` | 최신 RTL의 bit-exact 소프트웨어 대응 |

### 전달 파일 무결성

| 파일 | SHA-256 |
| --- | --- |
| 전달 ZIP | `0E085CFF2915F0BB4F269854258E96C2B9A5C320149FB59E2BAA24CB0298E752` |
| `grover_param.vh` | `036E8FE9F8C41908080FC7A8F29A3D4132E7CEEEA2AE754E9AA7C2E095717E35` |
| `lpsoc_bbht_grover_main_ip.v` | `7E8195CAEE809B83F505240CCE7F8A5B8E88FEA1A0C98689CA564290F09AF970` |
| 8-case TB | `91EDFBF07EB2C4CEA96806602BE04AA26E7445C9AF4A2549DEE93EC04198F813` |

## 3. 핵심 교차검증 결과

| 항목 | GitHub | 최신 전달 RTL | 골든 모델 | 판정 |
| --- | --- | --- | --- | --- |
| Qubit | Q15 기본, runtime `n` | Q14 고정 | Q14 exact, Q16 projected | Q14를 현재 정본으로 사용 |
| 병렬도 | P32 | P32 | P32 | 일치 |
| 입력 | signed16 | signed16 | signed16 | 일치 |
| 진폭 | Q2.16/18-bit | F22/23-bit | F22/23-bit | GitHub 수치 사용 금지 |
| predicate encoding | LT/GT/EQ/RANGE | 동일 | 동일 | 일치 |
| RANGE | open interval | open interval | open interval | 일치 |
| padding | legacy runtime 구조 | `index<data_count` gate | 동일 | 최신 기준 일치 |
| loader | AHB/generator | generic direct loader | memory image/load API | adapter 필요 |
| APB CSR | 구현됨 | 없음 | 해당 없음 | 감사 시점 미구현 (지금은 `bbht_grover_mmio`) |
| BBHT `j` | legacy controller | 독립 J-LFSR + ROM | 동일 | 최신 기준 일치 |
| 측정 난수 | legacy 단일 구조 | 독립 Measurement-LFSR | 동일 | 최신 기준 일치 |
| cache | legacy metadata | current `amp_mem` + metadata | 동일 의미 | 일치 |
| 열거 mask/FIFO | 있음 | Main IP에 없음 | RTL profile에 없음 | 감사 시점 미정 (v0.9.8 에서 Main IP 안으로) |

## 4. 발견한 문서 위험과 수정 내용

### 4.1 CSR 확정 여부 혼동

문제: 기존 문서는 권장 Q14 CSR map이 현재 구현된 것처럼 읽힐 수 있었다.

수정:

- GitHub legacy map을 실제 offset 그대로 별도 표로 분리
- v0.7g 권장 map은 **미구현 통합 제안**으로 명시
- firmware 상수를 승인 전에 고정하지 말라는 경고 추가

### 4.2 Q15/Q2.16과 Q14/F22 혼용 위험

문제: GitHub wrapper 수치와 최신 Main IP 수치가 다르다.

수정:

- SoC 구조만 참고하고 산술/폭은 `v0.7g`를 우선하도록 명시
- Q16은 RTL이 아닌 projected profile로 분리

### 4.3 Loader 중복 주소 검출 부재

문제: 최신 loader는 distinct address coverage가 아니라 accepted write count만 센다.

영향: 같은 주소를 반복 write해도 count만 맞으면 load가 성공할 수 있다.

수정:

- wrapper가 `0..DATA_COUNT-1`을 정확히 한 번씩 생성해야 한다고 명시
- 권장 assertion 추가

### 4.4 홀수 DATA_COUNT의 마지막 halfword

문제: GitHub AHB master는 `DATA_WORDS*2`개 halfword를 출력한다.

수정:

- adapter가 마지막 padding halfword를 억제하는 권장안 명시
- 그대로 전달할 경우 Main IP가 `addr>=data_count`로 무시한다는 대안도 분리

### 4.5 done pulse와 polling

확인:

- Main IP `done`은 1클록 pulse
- `result_valid`와 검색 status는 sticky
- wrapper가 polling을 위해 `done_sticky`를 만들어야 함

주의: GitHub legacy MMIO는 START write 자체에서 done sticky를 clear한다. 새 wrapper는 accepted START에서 clear하거나 busy write를 거부해야 한다.

### 4.6 cache 표현

확인:

- 별도 amplitude state copy를 요구하지 않음
- measurement는 `amp_mem` read-only
- `cache_j/cache_valid`가 현재 `amp_mem`의 의미를 표시
- Normal은 항상 INIT
- Burst는 `j_req>=cache_j`일 때 delta만 계산

문서에서 “실패 후 붕괴 상태”가 아니라 **측정 직전 `psi_j` checkpoint**로 표현을 통일했다.

### 4.7 BRAM 개수 표현

확인 가능한 것은 논리 용량이다.

- `data_mem`: 32 KiB
- `amp_mem`: 46 KiB
- row-weight memory: 약 3.2 KiB

정확한 BRAM primitive 개수는 implementation utilization report 없이는 확정하지 않는다.

## 5. bit-exact 회귀 결과

골든 모델이 전달 8-case를 다시 생성한 결과:

| Case | 모드 | j | index | Born W | `L_BBHT` | physical iter | 결과 |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | Normal | 1 | 120 | `2^44` | 1 | 1 | PASS |
| 2 | Burst exact-hit | 1 | 120 | `2^44` | 1 | 0 | PASS |
| 3 | Normal | 4 | 120 | `2^44` | 4 | 4 | PASS |
| 4 | Burst exact-hit | 4 | 120 | `2^44` | 4 | 0 | PASS |
| 5 | Normal | 8 | 480 | `2^44` | 8 | 8 | PASS |
| 6 | Burst exact-hit | 8 | 480 | `2^44` | 8 | 0 | PASS |
| 7 | Normal | 6 | 480 | `2^44` | 6 | 6 | PASS |
| 8 | Burst exact-hit | 6 | 480 | `2^44` | 6 | 0 | PASS |

추가 자동 테스트:

- RTL profile/campaign 관련 30 tests PASS
- Normal/Burst 동일 seed에서 attempt별 `j`, 측정 index, 성공 여부, 최종 결과 일치
- Burst physical iteration 감소 확인
- Oracle 또는 dataset 변경 시 cache 무효화 확인
- SAFE/POISON padding의 target mask와 결과 일치 확인

## 6. 그 뒤 어떻게 확정됐나

감사가 남긴 미결이 v0.9.8 에서 전부 닫혔다.

| 2026-08-22 미결 | 확정된 값 | 근거 |
| --- | --- | --- |
| 최종 CSR offset/field | 4바이트 간격 32비트 38개 | [CSR_레지스터_규격.md](CSR_레지스터_규격.md) |
| base address | `0xE2020000` (size `0x1000`) | RVX `make syn` 생성물 |
| interrupt | 넣지 않음. polling | [CSR_레지스터_규격.md](CSR_레지스터_규격.md) |
| busy 중 write | start 펄스를 조용히 버림. 펌웨어가 `STATUS` 를 먼저 본다 | [블록_인터페이스_다이어그램.md](블록_인터페이스_다이어그램.md) 4절 |
| AHB adapter owner | 통신 계층. `bbht_ahb_loader` (SINGLE, single outstanding) | `hardware_bram/src/` |
| odd DATA_COUNT | 마지막 upper halfword 를 쓰지 않는다 | [데이터_고정소수점_메모리_규격.md](데이터_고정소수점_메모리_규격.md) 12절 |
| generator 유지 | 보드 위 `GEN` 명령으로 남았다 | [UART_명령_프로토콜.md](UART_명령_프로토콜.md) |
| enumeration mask/FIFO | **Main IP 안.** FIFO 256칸 | [Main_IP_포트_규격.md](Main_IP_포트_규격.md) 5.2절 |
| Q16 | **폐기.** Q14 freeze | [전체_내용_보고서.md](전체_내용_보고서.md) 14절 |
| BRAM primitive 수 | 풀 SoC 116 tile, 그중 Main IP 84 tile (K3/H3-E4-M2 구현) | `vivado/vivado_bbht_grover_fpga/reports/route_util.rpt` · `route_util_hier.rpt` |
| clock/CDC | 가속기 100 MHz · SoC 50 MHz. CDC 는 RVX 생성물이 담당 | [블록_인터페이스_다이어그램.md](블록_인터페이스_다이어그램.md) 3절 |

4.3절이 지적한 loader 중복 주소 문제는 지금도 유효하다. RTL loader 는 accepted write
count 만 세므로, wrapper 가 `0..DATA_COUNT-1` 을 정확히 한 번씩 생성해야 한다.

4.5절의 `done` pulse → `done_sticky` 변환도 그대로 살아 있고, 그것을 지우는 것은
`COMMAND` 쓰기뿐이다.
