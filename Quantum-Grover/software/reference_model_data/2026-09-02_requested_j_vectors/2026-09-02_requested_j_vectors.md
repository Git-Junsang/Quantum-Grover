# 2026-09-02 number of iterations 지정 bit-exact test vector

reference model(Q1.22 bit-exact state vector)이 data · predicate · number of iterations를 받아 Grover iteration을 마친 뒤의 amplitude와 결과를 bit 단위로 적은
256 cases입니다(`requested_j_bit_exact_256_cases.zip`, 방향성 28 · anchor 1 · 무작위 227). 범위는 Manual mode의 core 산술이고,
자동 BBHT의 random number · policy · cycle은 빠져 있습니다.

지금은 C++ implementation verification(`software/pc_grover_develop/tools/verify_cpp_rtl_vectors.py`)이 읽습니다. case 안의 file 구성은
[기술문서 4장 4.5절](../../../documents/design_references/04_software_reference_model_and_test_vectors.md#45-rtl-test-vector)에 있습니다.
