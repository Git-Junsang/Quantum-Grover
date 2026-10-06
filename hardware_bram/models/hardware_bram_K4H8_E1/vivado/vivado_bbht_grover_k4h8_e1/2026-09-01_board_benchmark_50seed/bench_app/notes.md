# bbht_paper_bench — 50 seed simple version

원래 10-seed benchmark app의 폴더/실행 구조를 그대로 유지하면서:
- seed 수만 50개로 변경
- target 수는 1 / 4 / 16 / 64 / 256 유지
- 매 RUN 원시 로그는 숨기고 10 seed마다 progress + target별 summary만 출력
- `amp_overflow`는 terminal error가 아닌 sticky diagnostic으로 취급하여 DONE까지 기다림

실행:
```bash
cd ~/rvx_summer26/platform/bbht_grover/imp_arty-100t_2026-08-31
make bbht_paper_bench.run
```

RTL/bitstream 변경 없음.
