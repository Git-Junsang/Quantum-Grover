# Triple-Row Build: pre-AggressiveExplore evidence

Date: 2026-10-27

Source commit: `09367b6` (`M3 3-row measurement path and timing cleanup`)

This directory records the synthesis/implementation evidence captured before the
post-route `AggressiveExplore` experiment.  The raw Vivado reports are committed
alongside this summary; generated bitstreams remain on the synthesis host because
they are large binary build products.

## Functional and cycle verification

- RTL lint/regression: PASS.
- Common500: 500/500 workloads PASS in Restart mode and Checkpoint mode.
- The Common500 CSVs before and after the Measurement Unit CE cleanup are byte-identical.
- Predicate500: LT, GT, EQ, and RANGE each PASS 500/500 in Restart mode and Checkpoint mode.
- Triple-Row Build Common500 totals: Restart mode `11,156,127` cycles, Checkpoint mode `4,680,014` cycles,
  `9,582` executed iterations, `152,458` policy-stall cycles, and zero mismatches.
- Corresponding Dual-Row Build · Two-Level Select (Exhaustive DFS) Checkpoint mode total: `5,255,084` cycles.
- Triple-Row Build saves `575,070` cycles (`10.94%`) relative to Dual-Row Build · Two-Level Select (Exhaustive DFS).

## Full-system implementation steps

Target: Arty A7-100T, 200 MHz (`5.000 ns`).

| Step | Policy search mode | WNS (ns) | TNS (ns) | Failing endpoints | LUT | FF | Slices | BRAM tiles | DSP | Route errors |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Initial Triple-Row Build | 4 | -20.291 | -113497.875 | 31610 | 52080 | 47184 | 15395 (97.13%) | 113.5 | 196 | 0 |
| Exhaustive DFS baseline | 0 | +0.028 | 0 | 0 | 50821 | 47024 | 15602 (98.44%) | 113.5 | 196 | 0 |
| Measurement Unit CE cleanup | 0 | +0.106 | 0 | 0 | 50688 | 47024 | 15441 (97.42%) | 113.5 | 196 | 0 |

The CE cleanup removed the 394-fanout Measurement Unit payload clock-enable path.
The resulting worst path is in the Policy Engine `pvalq` four-way sorting logic.  The
final pre-experiment build meets timing with 106 ps setup margin and 21 ps hold
margin.

## OOC Dual-Row Build to Triple-Row Build resource delta

| Configuration | LUT | FF | BRAM tiles | DSP |
|---|---:|---:|---:|---:|
| Dual-Row Build · Two-Level Select, Exhaustive DFS | 34672 | 28183 | 80.5 | 128 |
| Triple-Row Build · Two-Level Select, Exhaustive DFS, CE cleanup | 39929 | 30007 | 81.5 | 192 |
| Delta | +5257 | +1824 | +1.0 | +64 |

## Bitstream identity

| Step | Bytes | SHA-256 |
|---|---:|---|
| Initial Triple-Row Build, Two-Request Bound Pruning | 3826007 | `e391f3451d0e3458b2b30795d164d1824269fa25830941b00dd8de9c4b1b96fe` |
| Exhaustive DFS baseline | 3826007 | `84976c1cd47f76df9cfae747f5c213b1d4f5c8eb24f5b21224202b07aa31403c` |
| CE cleanup, Exhaustive DFS | 3826007 | `3a52d962ac99678fcbf3caf05e7fe9fc0d7db7be978948d003b231d9086a8572` |

## Raw report map

- `prune4/`: initial Triple-Row Build route timing, utilization, and route-status reports.
- `prune0_wns0028/`: Exhaustive DFS baseline route reports.
- `cefix_wns0106/`: final pre-AggressiveExplore route reports.
- `ooc/`: Dual-Row Build and Triple-Row Build out-of-context utilization reports.

The later post-route `AggressiveExplore` run is intentionally not included in
these pre-experiment figures.  It preserved WNS at `+0.106 ns` and did not meet
the requested `+0.150 ns` target.
