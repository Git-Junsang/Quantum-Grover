# Triple-Row Build: WNS margin recovery

Date: 2026-10-27

Starting point:

- Source and initial timing-clean implementation: commit `09367b6`.
- Pre-experiment implementation evidence: commit `1e32e08`.
- Starting WNS: `+0.106 ns` at 200 MHz.
- Requested minimum WNS: `+0.150 ns`.

The strategy sweep changes placement and routing only. RTL, policy selection,
measurement behavior, and cycle counts are unchanged.

## Strategy results

| Place directive | Route directive | Final WNS (ns) | Target met | Route errors |
|---|---|---:|---|---:|
| Explore | AggressiveExplore | +0.082 | No | 0 |
| ExtraPostPlacementOpt | AggressiveExplore | +0.123 | No | 0 |
| ExtraNetDelay_high | AggressiveExplore | **+0.182** | **Yes** | 0 |

`ExtraNetDelay_high` improved WNS by `0.076 ns` over the `+0.106 ns`
starting point and exceeded the requested margin by `0.032 ns`.

## Winning implementation

Target: Arty A7-100T, 200 MHz (`5.000 ns`).

| Metric | Result |
|---|---:|
| WNS | +0.182 ns |
| TNS | 0.000 ns |
| Setup failing endpoints | 0 |
| WHS | +0.016 ns |
| THS | 0.000 ns |
| Hold failing endpoints | 0 |
| Route errors | 0 |
| Slice LUTs | 50950 / 63400 (80.36%) |
| Slice registers | 47027 / 126800 (37.09%) |
| Slices | 15490 / 15850 (97.73%) |
| BRAM tiles | 113.5 / 135 (84.07%) |
| DSPs | 196 / 240 (81.67%) |

All user timing constraints are met. Relative to the starting implementation,
the winning physical strategy uses 262 more LUTs, 3 more registers, and 49 more
slices; BRAM and DSP usage are unchanged.

## Bitstream

- File size: `3,826,007` bytes.
- SHA-256: `fcc50c6326d1a408df176c47a7ac8ff26173afd8979ae2313901db227fcc1688`.
- The binary bitstream and routed DCP remain on the synthesis host as generated
  build products. Their reports, result metadata, and bitstream checksum are
  committed here.

## Evidence map

- `extra_net_delay_high/route_timing_summary.rpt`: winning setup/hold report.
- `extra_net_delay_high/route_util.rpt`: winning resource report.
- `extra_net_delay_high/route_status.rpt`: winning routing-integrity report.
- `extra_net_delay_high/result.txt`: directives, WNS, and target status.
- `explore/` and `extra_post_placement_opt/`: comparison result and route status.
- `strategy_summary.csv`: machine-readable comparison.

The reproducible Vivado flow is in
`hardware_bram/synth/implementation_strategy_sweep.tcl`.
