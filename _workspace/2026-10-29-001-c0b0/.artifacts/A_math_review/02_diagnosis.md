# 윤문 진단

## 장르·레지스터
- 학부생용 quantum algorithm·FPGA 해설서(report), 친근한 합쇼체 중심이며 독자에게 말을 거는 해요체가 일부 섞인 기존 학습서 말투입니다. 격식을 올리거나 설명을 학술 논문체로 바꾸지 않습니다.
- 제목·절 번호·목록·표·수식·code·link·기존 콜아웃 및 이모지 형식은 보존합니다. 한국어 서술만 국소적으로 다듬습니다.
- 영어 용어·영어 토큰은 번역, 교체, 삭제, 추가하지 않습니다. SSOT는 documents/design_references/22_appendix_glossary_and_retired_specs.md §22.2와 기존 glossary입니다.
- 사실·수치·조건·부정·인과·추측/당위·인용을 보존합니다. 원문의 기술 주장을 새 해설이나 사실 교정으로 확장하지 않습니다.

## 정량 앵커
- 12,360자, risk_band low, route_hint light. A-18 relative_clause_nesting=1. A-7·A-8·A-9·A-19=0. ending_comma_rate=0.55이나 모든 쉼표를 오류로 취급하지 않고 연결어미 직후인지 확인합니다.
## 지배 패턴과 겨냥 순서
1. D-14·D-5: “두 가지 배경 지식에 기댑니다”, “linear algebra 위에서 돌아가고”, “계산의 핵심 동력”, “회로 전체가 이 성질 위에 서 있습니다”, “값은 틀리지만 sign과 크기 순서는 살아남고” 등 비유가 연산 설명과 섞입니다. 학습에 도움 되는 complex plane·막대 비유는 유지하고 어색한 추상 비유만 검토합니다.
2. A-18·C-11: A.1의 Grover real-number 조건과 설계 제외 이유, A.3의 matrix 순서 설명, A.5의 Q format·rounding 설명에서 조건절을 겹칩니다. 모든 수식과 영어 표기를 보존하며 절 연결을 자연스럽게 다듬을 후보입니다.
3. D-8·I-2: “그 integer를 어떻게 읽기로 약속했는지가 아래 다섯 가지”, “그 어긋남의 정체가 바로 이 전제”처럼 명사화된 예고·결산이 있습니다. 설명을 직접 이어 쓰는 후보입니다.
4. C-8·J-2: 실제 정의를 가상 따옴표나 ‘A가 아니라 B’로 강조하는 경우가 있습니다. 수학적 구분에 필요한 대조를 남기고 영어 용어를 바꾸지 않습니다.
## 특별 보존
- Euler's formula, conjugate transpose, half-up, round-half-to-even, two's complement, prefix sum, Monte Carlo 등 모든 영어 원어 및 약어·수식·표를 유지합니다. 약간 긴 수학 유도와 필요한 반복은 문체 문제로 간주하지 않습니다.
