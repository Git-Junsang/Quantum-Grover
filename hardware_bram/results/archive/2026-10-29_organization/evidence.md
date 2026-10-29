# Results directory organization

기록일: 2026-10-29, Asia/Seoul. directory organization과원자료 preservation 확인입니다.
RTL simulation, synthesis, implementation 또는 board verification을 새로 수행한 기록이 아닙니다.

최상위 실험 묶음 59개 중 중간 개발 결과 28개를 `archive/`의 네 topic directory로 이동했습니다.
대표 evidence와 최신 full Common500, Main IP integration, background pipeline 경로는 유지합니다.
background pipeline의 상태는 조회하지 않았습니다.

## 이동과 보존

- [moves.json](moves.json): 이동 전후 경로와 topic.
- [files_before.json](files_before.json): 이동한 모든 file의 기존 경로, 새 경로, bytes와 SHA-256.
- [preservation.json](preservation.json): 이동 file 전체와 보호한 source · Common500 evidence의 SHA-256 대조.
- [reference_updates.json](reference_updates.json): authored evidence와 report의 경로 갱신 기록.
- [catalog.json](../../catalog.json): 현재 대표 묶음과 archive의 전체 경로 목록.

원자료를 삭제하지 않았습니다. log · CSV · JSON · source snapshot은 내용 그대로 이동했습니다.
과거 실행 경로를 포함한 benchmark 기록은 당시 사실을 보존합니다. authored Markdown의 이동한
경로만 갱신했으며, 해당 세 Markdown의 수정 전 사본은 `backups/`의 `.bak` file에 보관했습니다. 현재 RTL과 보호한 firmware,
최신 full Common500 evidence는 변경하지 않았습니다.

독립 policy / parallel unit test는 이후 실행부터 고유한 `/tmp/` directory에 출력합니다.
과거 결과 묶음에 새 source의 결과를 덮어쓰거나 고정 경로를 다시 만드는 동작을 피합니다.
문서 link와 helper 경로 확인 결과는 [validation.json](validation.json)에 기록합니다.
