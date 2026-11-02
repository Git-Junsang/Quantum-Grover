//==============================================================================
// grover_dram_queue.v -- hardware_dram branch, 2-deep candidate amplitude
// buffer ("BRAM 큐" in CLAUDE.md section 3).
//
// Physically this is two independent grover_amp_mem instances (buf A, buf B).
// Logically each buffer is bound, at any moment, to exactly one of four
// external engines via its role_* select:
//
//   role_grow    -- grover_ctrl_fsm/grover_iter_datapath are actively running
//                    a Grover iteration in place on this buffer.
//   role_store   -- grover_dram_amp_store is streaming this buffer's just-
//                    completed contents out to DRAM (read-only access).
//   role_restore -- grover_dram_amp_store is streaming a DRAM slot back into
//                    this buffer for a candidate that is behind the growth
//                    frontier (write-only access).
//   role_measure -- grover_measure_verify is Born-sampling this buffer.
//
// This module is pure storage + port muxing, analogous in spirit to
// grover_ckpt_mem in hardware_bram but far simpler: there is no source-select
// register stage here because a buffer's role never changes mid-request, so
// read latency stays exactly 1 cycle (matches grover_amp_mem / the
// AMP_READ_LATENCY=1 default the shared grover_measure_verify already
// assumes -- no retiming needed on that side).
//
// grover_dram_shot_fsm.v owns all role-select sequencing. The invariant it
// must uphold: at most one of {a_role_grow, b_role_grow} is set at a time
// (ditto per role, across the two buffers), and a buffer's role does not
// change while a request against it is in flight. This module does not
// itself check that invariant.
//==============================================================================
`timescale 1ns/1ps
`include "grover_dram_param.vh"

module grover_dram_queue (
    input  wire                              clk,

    // Buffer A / B role selects. One-hot per buffer (or all-zero = idle).
    input  wire                              a_role_grow,
    input  wire                              a_role_store,
    input  wire                              a_role_restore,
    input  wire                              a_role_measure,

    input  wire                              b_role_grow,
    input  wire                              b_role_store,
    input  wire                              b_role_restore,
    input  wire                              b_role_measure,

    // Shared growth port (grover_ctrl_fsm INIT/PASS1/PASS2 row traffic).
    // Targets whichever buffer currently has role_grow set.
    input  wire [`GP_ROW_W-1:0]              grow_rd_row,
    input  wire                              grow_rd_en,
    output wire [`GP_P*`GP_AMP_W-1:0]        grow_rd_amp,
    input  wire [`GP_ROW_W-1:0]              grow_wr_row,
    input  wire                              grow_wr_en,
    input  wire [`GP_P*`GP_AMP_W-1:0]        grow_wr_amp,

    // Shared store-sweep read port (grover_dram_amp_store STORE side).
    input  wire [`GP_ROW_W-1:0]              store_rd_row,
    input  wire                              store_rd_en,
    output wire [`GP_P*`GP_AMP_W-1:0]        store_rd_amp,

    // Shared restore write port (grover_dram_amp_store RESTORE side).
    input  wire [`GP_ROW_W-1:0]              restore_wr_row,
    input  wire                              restore_wr_en,
    input  wire [`GP_P*`GP_AMP_W-1:0]        restore_wr_amp,

    // Shared measurement read port (grover_measure_verify Born sampler).
    input  wire [`GP_ROW_W-1:0]              meas_rd_row,
    input  wire                              meas_rd_en,
    output wire [`GP_P*`GP_AMP_W-1:0]        meas_rd_amp
);
    wire [`GP_ROW_W-1:0]       a_rd_row, b_rd_row;
    wire                        a_rd_en,  b_rd_en;
    wire [`GP_P*`GP_AMP_W-1:0] a_rd_amp, b_rd_amp;
    wire [`GP_ROW_W-1:0]       a_wr_row, b_wr_row;
    wire                        a_wr_en,  b_wr_en;
    wire [`GP_P*`GP_AMP_W-1:0] a_wr_amp, b_wr_amp;

    // Read-port source select: grow > store > measure priority is arbitrary
    // since exactly one role is active at a time by the caller's invariant;
    // the priority only matters if that invariant is ever violated, in which
    // case grow wins so an in-flight iteration is never starved.
    assign a_rd_row = a_role_grow  ? grow_rd_row  :
                       a_role_store ? store_rd_row :
                                       meas_rd_row;
    assign a_rd_en  = (a_role_grow  & grow_rd_en) |
                       (a_role_store & store_rd_en) |
                       (a_role_measure & meas_rd_en);

    assign b_rd_row = b_role_grow  ? grow_rd_row  :
                       b_role_store ? store_rd_row :
                                       meas_rd_row;
    assign b_rd_en  = (b_role_grow  & grow_rd_en) |
                       (b_role_store & store_rd_en) |
                       (b_role_measure & meas_rd_en);

    // Write-port source select: only grow and restore ever write.
    assign a_wr_row = a_role_grow ? grow_wr_row : restore_wr_row;
    assign a_wr_en  = (a_role_grow    & grow_wr_en) |
                       (a_role_restore & restore_wr_en);
    assign a_wr_amp = a_role_grow ? grow_wr_amp : restore_wr_amp;

    assign b_wr_row = b_role_grow ? grow_wr_row : restore_wr_row;
    assign b_wr_en  = (b_role_grow    & grow_wr_en) |
                       (b_role_restore & restore_wr_en);
    assign b_wr_amp = b_role_grow ? grow_wr_amp : restore_wr_amp;

    grover_amp_mem u_buf_a (
        .clk    (clk),
        .rd_row (a_rd_row), .rd_en (a_rd_en), .rd_amp (a_rd_amp),
        .wr_row (a_wr_row), .wr_en (a_wr_en), .wr_amp (a_wr_amp)
    );

    grover_amp_mem u_buf_b (
        .clk    (clk),
        .rd_row (b_rd_row), .rd_en (b_rd_en), .rd_amp (b_rd_amp),
        .wr_row (b_wr_row), .wr_en (b_wr_en), .wr_amp (b_wr_amp)
    );

    // Shared output buses: whichever buffer currently holds that role drives
    // the corresponding external bus. When neither buffer holds a role
    // (e.g. no measurement in flight), the bus reads buffer A's output as a
    // harmless don't-care -- the consuming engine's own busy/valid signal
    // gates whether that data is used.
    assign grow_rd_amp  = a_role_grow    ? a_rd_amp : b_rd_amp;
    assign store_rd_amp = a_role_store   ? a_rd_amp : b_rd_amp;
    assign meas_rd_amp  = a_role_measure ? a_rd_amp : b_rd_amp;

endmodule
