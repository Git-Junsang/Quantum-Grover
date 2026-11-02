# 윤문 진단

## 장르·레지스터
- 학부생용 quantum algorithm·FPGA 해설서(report), 친근한 합쇼체 중심이며 독자에게 말을 거는 해요체가 일부 섞인 기존 학습서 말투입니다. 격식을 올리거나 설명을 학술 논문체로 바꾸지 않습니다.
- 제목·절 번호·목록·표·수식·code·link·기존 콜아웃 및 이모지 형식은 보존합니다. 한국어 서술만 국소적으로 다듬습니다.
- 영어 용어·영어 토큰은 번역, 교체, 삭제, 추가하지 않습니다. SSOT는 documents/design_references/22_appendix_glossary_and_retired_specs.md §22.2와 기존 glossary입니다.
- 사실·수치·조건·부정·인과·추측/당위·인용을 보존합니다. 원문의 기술 주장을 새 해설이나 사실 교정으로 확장하지 않습니다.

## 정량 앵커
- 21,908자, risk_band low, route_hint heavy(길이 기준). A-18 relative_clause_nesting=5. pronoun_density=0.001(A-16 후보는 실제 선행사 확인 필요). conclusion_pivot_count=2, lexical_diversity=0.55(z=-2.04)는 전문용어·코드 반복에 크게 좌우됩니다. ending_comma_rate=0.56은 C-11 후보를 실제로 확인할 보조 근거입니다.
## 지배 패턴과 겨냥 순서
1. D-14·D-5: “Q1.22 fixed-point로 못 박았습니다”, “이 장이 심으려는 감각”, “우아함의 정체”, “0 multipliers는 … 거짓말”, “쓰레기 값이 solution 행세”, “허무할 만큼 간단”, “조용히 무력화”, “Q1.22의 천장”, “multiplier·divider를 물어옵니다” 등 감정·의인화·과장이 본문에 반복됩니다. 구조와 연산을 가리키는 한국어 설명으로 다듬는 것을 우선합니다.
2. D-8·I-2: “이 절이 이 project의 주제 그 자체”, “이제 … 약속을 정확한 문장으로 닫습니다”, “그 지점을 못 박아 둡니다” 등 독립 예고가 많습니다. 실제 datapath 설명을 바로 잇는 후보입니다.
3. A-18·C-11: 13.2의 논문 constant 오차 설명, 13.5의 shift·rounding 설명, 13.7의 accumulation 순서 조건이 긴 연결절로 이어집니다. 수치·수식·code는 건드리지 않고 한국어 절 연결과 쉼표를 정돈합니다.
4. C-8·J-2: ‘경로별 0 multiplier’와 ‘Measurement Unit의 128 DSP’를 여러 차례 같은 대구·가상 인용으로 반복합니다. 기술적으로 필요한 경로 구분과 모든 영어 표기는 보존하고 평가성 표현만 검토합니다.
5. F-1·D-2: “완전히”, “정확히”, “한 개도” 중 mathematical equality나 하드웨어 수량을 표시하는 것은 유지합니다. “기분 좋은 이득”, “역설의 가장 선명한 사례” 같은 감상만 완화할 후보입니다.
