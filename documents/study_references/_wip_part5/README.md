# `_wip_part5/` — 논문 1차 검증 노트

## 이 폴더는 무엇인가

`facts/04.md` ~ `facts/09.md` 는 해설서 Part 5~8을 쓰기 위해 **논문 여섯 편을 원문과 한 줄씩 대조하며 뽑아낸 사실 노트**입니다(총 37만 자). 해설서 본문이 아니라 **본문의 근거**입니다.

| 파일 | 논문 |
|---|---|
| `facts/04.md` | Choi & W. Lee, *Developing a Grover's quantum algorithm emulator on standalone FPGAs*, AIMS Math. 9(11), 2024 |
| `facts/05.md` | Choi 외, *Precision-aware fixed-point emulation of Grover's algorithm*, Quantum Inf. Process. 25:214, 2026 |
| `facts/06.md` | Choi 외, *Standalone FPGA-Based QAOA Emulator*, arXiv:2502.11316, 2025 |
| `facts/07.md` | El-Araby 외, *Towards Complete and Scalable Emulation of Quantum Algorithms on HPRC*, IEEE TC 72(8), 2023 |
| `facts/08.md` | Byrnes, Forster, Tessler, *Generalized Grover's Algorithm for Multiple Phase Inversion States*, PRL 120:060501, 2018 |
| `facts/09.md` | Habibie 외, *Quantum Minimum Searching Algorithms for AUD in Wireless IoT*, IEEE IoT J. 11(12), 2024 |

## 왜 남겨 두는가

[15.6절 「인용 시 주의 — 논문의 오류와 모호점」](../15_논문지도와_설계결정표.md#156-인용-시-주의--논문의-오류와-모호점)의 정오표가 전부 이 노트에서 나왔습니다. 04번 의사코드의 오타, 매직넘버 LSB 어긋남, 06번 첨자 뒤바뀜, 09번 부호 규약과 `Algorithm 2` 의 `m` 갱신 누락 — 그대로 옮기면 회로가 동작하지 않는 것들입니다. 정오표를 다시 확인하거나 새 논문을 추가할 때 여기서 출발하십시오.

12장이 05번 `f_min` 공식의 전제를 따져 "우리 조건에서는 쓸 수 없다"고 결론 내린 근거도 `facts/05.md` 에 있습니다.

## 폐기된 것

이 폴더에 있던 `PLAN.md`(11~15장 집필 계획서)와 `HANDOFF.md`(인계 문서)는 **2026-08-15에 삭제했습니다.** 2026-07-17에 쓰인 문서라 비트폭·저장 위치·SoC 형태가 미정인 상태를 기준선으로 삼고 있었고, 목차도 11~15장 다섯 개 장 전제였습니다. 지금 구조(11~18장, Part 5~8)와 정면으로 충돌해 그대로 두면 다음 작업자가 폐기된 계획을 실행하게 됩니다.

그 문서들이 세운 원칙 중 하나만 계승할 값이 있어 여기 옮겨 둡니다.

> **study_references가 주교재다.** `papers_ko/` 는 단순 번역본으로 취급하고, 실제 학습은 해설서를 기준으로 한다. 따라서 **새 장은 자체 완결**이어야 하며, 논문 해설본을 읽어야만 이해되는 서술을 남기지 않는다.

현행 확정 스펙의 단일 출처는 [15.4절](../15_논문지도와_설계결정표.md#154-우리-프로젝트의-좌표--확정-설계-결정표)입니다.
