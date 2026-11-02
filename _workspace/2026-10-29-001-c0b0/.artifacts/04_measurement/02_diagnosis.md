# 윤문 진단

## 장르·레지스터
- 학부생용 quantum algorithm·FPGA 해설서(report), 친근한 합쇼체 중심이며 독자에게 말을 거는 해요체가 일부 섞인 기존 학습서 말투입니다. 격식을 올리거나 설명을 학술 논문체로 바꾸지 않습니다.
- 제목·절 번호·목록·표·수식·code·link·기존 콜아웃 및 이모지 형식은 보존합니다. 한국어 서술만 국소적으로 다듬습니다.
- 영어 용어·영어 토큰은 번역, 교체, 삭제, 추가하지 않습니다. SSOT는 documents/design_references/22_appendix_glossary_and_retired_specs.md §22.2와 기존 glossary입니다.
- 사실·수치·조건·부정·인과·추측/당위·인용을 보존합니다. 원문의 기술 주장을 새 해설이나 사실 교정으로 확장하지 않습니다.

## 정량 앵커
- 11,798자, risk_band low, route_hint standard. A-19 double_particle_count=2, A-18 relative_clause_nesting=5. conclusion_pivot_count=1(따라서), ending_comma_rate=0.47. A-8·A-9·A-7은 0으로 확정 패턴이 아닙니다.
## 지배 패턴과 겨냥 순서
1. D-14·D-5: “emulator에서는 유혹이 하나 생깁니다”, “quantum algorithm의 약속이 여기서 소리 없이 사라집니다”, “자연이 이 sampling을 공짜로 해 주지만”, “checkpoint의 뿌리”, “회로를 스스로 묶어 두려는” 등이 설명을 의인화하거나 비유로 돌립니다. 작용과 결과를 직접 적는 방향이 적합합니다. 학습용 동전·계단 비유 자체는 무조건 제거하지 않습니다.
2. D-8·I-2: “measurement의 가장 중요한 성질:”, “규칙을 지키려면 규칙대로 뽑아야 합니다” 등 설명 앞의 예고·자명한 반복이 있습니다. 뒤의 실제 설명에 자연스럽게 잇는 후보입니다.
3. A-18: 4.2·4.3·4.4절에서 amplitude 동률→argmax의 반복 출력, sampling→계층 구조, 실패 shot→checkpoint의 인과를 긴 문장에 몰아넣습니다. 조건을 보존하며 한국어 절 연결을 정돈할 수 있습니다.
4. C-8·J-2: argmax와 sampling, 물리 장치와 emulator를 반복 대구·가상 따옴표로 구별합니다. 기술적 대립은 보존하되 “확률이니 sample이니”, “그럴듯한 약속” 같은 과장된 어감을 줄이는 후보입니다.
5. A-19·C-11: 이중 조사와 “~이고,” “~이므로,” 등 연결어미 뒤 쉼표를 본문에서 확인합니다. 제목에 포함된 ‘circuit에서의’는 제목 보존 조건 때문에 고치지 않습니다.
