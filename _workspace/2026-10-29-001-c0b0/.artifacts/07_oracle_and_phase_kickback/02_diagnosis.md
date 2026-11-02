# 윤문 진단

## 장르·레지스터
- 학부생용 quantum algorithm·FPGA 해설서(report), 친근한 합쇼체 중심이며 독자에게 말을 거는 해요체가 일부 섞인 기존 학습서 말투입니다. 격식을 올리거나 설명을 학술 논문체로 바꾸지 않습니다.
- 제목·절 번호·목록·표·수식·code·link·기존 콜아웃 및 이모지 형식은 보존합니다. 한국어 서술만 국소적으로 다듬습니다.
- 영어 용어·영어 토큰은 번역, 교체, 삭제, 추가하지 않습니다. SSOT는 documents/design_references/22_appendix_glossary_and_retired_specs.md §22.2와 기존 glossary입니다.
- 사실·수치·조건·부정·인과·추측/당위·인용을 보존합니다. 원문의 기술 주장을 새 해설이나 사실 교정으로 확장하지 않습니다.

## 정량 앵커
- 11,133자, risk_band low, route_hint light. A-18 relative_clause_nesting=2. A-7·A-8·A-9·A-19=0. ending_comma_rate=0.38. 정량 카운터 밖의 의미·표현 문제를 아래 실제 구절로 판단합니다.
## 지배 패턴과 겨냥 순서
1. D-14·D-5: “함숫값을 amplitude의 sign으로 바꿔치기하는 마법”, “떠받치는 기둥”, “마법처럼 … 튀어나옵니다”, “곁다리(constant)”, “쌍둥이” 등 비유가 핵심 설명 전반에 중첩됩니다. 영어 technical term은 그대로 두고 한국어 동사·비유만 명료하게 다듬습니다. phase kickback의 이름을 풀이하는 kick back 표기는 영어이므로 보존합니다.
2. D-8·I-2: “핵심은 우리가 …”, “이제 문제는 …”, “가장 중요한 부분입니다” 등 설명 전후의 강조·예고가 겹칩니다. 내부 동작을 모른다는 가정, phase와 measurement probability의 차이는 보존합니다.
3. A-18·C-11: 7.4·7.5절은 solution이 하나인 special case, 일반 predicate oracle, 실습 circuit, 실제 search의 차이를 긴 관계절과 대시로 이어 갑니다. 명제 순서와 조건을 보존하며 긴 한국어 연결을 정돈할 수 있습니다.
4. C-8·J-2: ‘solution을 아는 circuit이 아니다’라는 설명을 가상 인용과 반복 대구로 여러 번 풉니다. 구분은 남기되 “반칙”, “몰래” 같은 감정적 어휘가 추가되지 않도록 합니다.
5. F-1·D-2: “완전히 명확”, “완전히 대칭”, “정확히”, “압도” 중 실제 mathematical equality에 해당하는 정확·대칭은 보존하고, 도입부와 마무리의 평가성 수식만 검토합니다.
