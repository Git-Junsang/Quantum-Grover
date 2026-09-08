//==============================================================================
// grover_dram_param.vh -- hardware_dram branch, DRAM full-history amplitude
// table address map. Extends grover_param.vh; does not redefine anything in
// it.
//
// Design intent (see CLAUDE.md section 3, hardware_dram branch)
//   hardware_bram keeps only CKPT_K=3/4 materialized amplitude states and
//   replays grover_checkpoint.v's planner/executor to reach an arbitrary j.
//   hardware_dram instead snapshots the FULL 512-row/736-bit amplitude table
//   to DRAM after every completed Grover iteration, so any j in [1, GP_M_MAX]
//   is reached by exactly one DRAM burst read -- no replay, no policy engine.
//
// Table layout
//   One row  = GP_P * GP_AMP_W = 736 bits = 92 bytes (byte-aligned exactly).
//   One slot = GP_ROWS rows    = 512 * 92 = 47104 bytes (one full iteration).
//   Slot 0 is never written (j=0 is the uniform INIT state and is always
//   regenerated locally via OP_INIT; storing it would only waste capacity).
//   Slots 1..127 are written once each, the first time the search grows past
//   that iteration count, and are read back on every later candidate draw
//   that lands on an already-grown j. 127 and not GP_M_MAX: GP_J_W is 7, so
//   store_j/restore_j cannot express anything above 127. GP_M_MAX = 128 is
//   the m_bound ceiling (the exclusive upper bound the LFSR draws j below),
//   not a reachable j. Slot 128 is therefore allocated but never touched;
//   the extra 46 KiB is not worth an off-by-one in the address map.
//
//   table_bytes = (GP_M_MAX + 1) * DRAM_ITER_STRIDE = 129 * 47104
//               = 6,076,416 bytes (~5.8 MiB). Trivially fits any DDR3L module
//   on the Arty A7-100T; capacity was never the constraint for this branch.
//
// Physical binding is NOT decided yet (see CLAUDE.md section 3: "hardware_dram
// 현재 빈 뼈대"). GP_DRAM_ADDR_W / GP_DRAM_AMP_BASE are placeholders for a
// generic byte-addressed window; grover_dram_amp_store.v's abstract burst
// port (dram_wr_*/dram_rd_*) is the seam where a future MIG native-UI or
// AXI4 bridge attaches. Nothing downstream of that seam assumes AXI or MIG.
//==============================================================================
`ifndef GROVER_DRAM_PARAM_VH
`define GROVER_DRAM_PARAM_VH

`include "grover_param.vh"

// Abstract DRAM port geometry. One beat = one packed amplitude row.
`define GD_ADDR_W             32
`define GD_ROW_BYTES          (`GP_P * `GP_AMP_W / 8)      // 92
`define GD_BURST_LEN          `GP_ROWS                      // 512 beats/slot
`define GD_BURST_LEN_W         10                            // holds 0..511

// Per-search-session DRAM window. Placeholder base; rebind when the MIG/AXI
// bridge is designed. Must be `GD_ROW_BYTES-aligned (it is, trivially, since
// it is 0) and must leave room for (GP_M_MAX+1) * GD_ITER_STRIDE bytes.
`define GD_AMP_BASE           32'h0000_0000
`define GD_ITER_STRIDE        (`GD_ROW_BYTES * `GP_ROWS)    // 47104 bytes/slot

`endif
