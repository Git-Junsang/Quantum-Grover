# 2026-09-02 요청 j 비트 정확 벡터

골든 모델(Q1.22 비트 정확 상태벡터)이 데이터 · 술어 · `j` 를 받아 반복을 마친 뒤의 진폭과 결과를 비트 단위로 적은
256케이스입니다(`requested_j_bit_exact_256_cases.zip`, 방향성 28 · 앵커 1 · 무작위 227). 범위는 수동 코어 산술이고,
자동 BBHT 의 난수 · 정책 · 사이클은 빠져 있습니다.

지금은 C++ 구현 검증(`software/pc_grover_develop/tools/verify_cpp_rtl_vectors.py`)이 읽습니다. 케이스 안의 파일 구성은
[기술문서 4장 4.5절](../../../documents/design_references/04_소프트웨어_기준모델과_정답_벡터.md#45-rtl-정답-벡터)에 있습니다.
