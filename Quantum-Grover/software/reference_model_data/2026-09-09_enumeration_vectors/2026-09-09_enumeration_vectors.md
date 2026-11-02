# 2026-09-09 enumeration test vector

enumeration에서 이미 찾은 solution을 빼는 두 방식(`software_reload/` · `projected_mask_mem/`)을 같은 다섯 case로 돌려, enumeration round마다
Found Mask와 결과를 적은 reference model의 expected result입니다. 두 방식이 모든 쌍에서 같은 결과를 낸 것이
[실험 04](../../../documents/reports/04_enumeration_method_comparison.md)의 근거입니다. 원본 생성일이 남아 있지 않아 directory 날짜는
저장소 반입일입니다.

지금 이 test vector를 읽는 code는 없습니다. `q16_eq_m2` 는 폐기된 16 qubits 확장의 기록이라 verification 근거로 쓰지 않습니다. file 구성은
[기술문서 4장 4.5절](../../../documents/design_references/04_software_reference_model_and_test_vectors.md#45-rtl-test-vector)에 있습니다.
