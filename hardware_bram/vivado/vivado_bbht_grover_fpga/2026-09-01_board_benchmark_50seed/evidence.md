# LPSoC BBHT/Grover — 2026-09-01 actual-board paired benchmark evidence

## Test contract
- Board/system: Arty A7-100T, frozen RVX 100 MHz final bitstream
- Search space: Q14, N=16,384
- Dataset: signed 16-bit deterministic random background
- Predicate: EQ(12345)
- Background seed: `0x5EED1234`
- Target-position seed: `0xA17E2026`
- Target counts: 1 / 4 / 16 / 64 / 256 (nested target sets)
- Paired random seeds: 50 `(seed_j, seed_meas)` pairs per target condition
- Comparison: Normal BBHT -> true K4/H8 using the same paired seeds
- RTL/bitstream change: none; SW benchmark harness only

## Headline result
- 5 target profiles × 50 seed pairs = **250 paired runs**
- Pair consistency: **250/250 PASS**
- Search success: Normal **250/250**, K4/H8 **250/250**
- Plan mismatch: **0**
- Aggregate physical Grover iterations: **14,883 -> 4,134 (-72.22%)**
- Aggregate cycles: **20,229,755 -> 13,824,806 (-31.66%)**

## Files
- `bench_app/`: exact test app package used for the final 50-seed run. It was
  shipped as `bench_app.zip` and extracted in place on 2026-09-13; the archive's
  hash in `sha256sums.txt` is kept as the record of the original. Two changes from
  the archive: its `README.md` is now `notes.md` (the repository allows README files
  only at the root), and the `tools/__pycache__/` bytecode was dropped. Every other
  file is byte-identical to the archive member.
- `terminal_full.txt`: exact final 50-seed terminal output
- `result.txt`: concise aggregate result
- `summary.csv`: target-level summary
- `sha256sums.txt`: checksums of the files above

The v0.9.8 communication-contract handoff document that accompanied this bundle now
lives in `software/contract/`, next to the extractor that reads it. The two K4/H8-era
summary documents were retired to `trash_bin/PJK_handoff/`.

> Renamed on 2026-09-03 to follow the repository naming rule. The measurement files
> (`result.txt`, `summary.csv`, `terminal_full.txt`, `bench_app.zip`) are byte-identical
> to the originals — their checksums are unchanged. Only this description file was edited.

## Limitation
The final simple-output run intentionally suppressed individual `RUN` lines. Therefore the package proves aggregate target-level board performance and paired correctness, but does not preserve seed-by-seed cycle distributions. If a paper needs p50/p95/CDF or per-seed paired significance, run the same harness in verbose/raw mode and archive those lines separately.
