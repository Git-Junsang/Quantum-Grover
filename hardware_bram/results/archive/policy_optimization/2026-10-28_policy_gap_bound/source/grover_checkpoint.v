//==============================================================================
// grover_checkpoint.v -- checkpoint metadata, planner, and pipelined autonomous planner
// BBHT/Grover checkpoint RTL -- Phase 1~2, integration-safe revision
// Date: 2026-08-29
//
// Implemented in this file
//   1) grover_amp_mem_packed
//      - exact external 736-bit row interface of the Q14/P32/F22 baseline
//      - internal 10 x (512 x 69b) + 1 x (512 x 46b)
//      - no array reset, simple dual-port style
//   2) grover_ckpt_mem
//      - CKPT_K = 3 or 4 full-state slots
//      - 11 packed-word-local source-select/register groups after BRAM outputs
//      - two-cycle read response from request edge (BRAM + mux register)
//   3) grover_ckpt_meta
//      - CKPT_K valid/j metadata, invalidate/clear/commit
//      - canonical sorted logical checkpoint set S
//   4) grover_ckpt_planner
//      - logical {source_j, sorted S'} -> deterministic physical slot plan
//      - closest predecessor, endpoint mandatory, exact hit, psi0 anchor
//      - K3 max 2 / K4 max 3 B-mode intermediates
//   5) grover_ckpt_executor
//      - parameter-independent boundary sequencer for K3/K4
//      - INIT, in-place run, 1-iteration out-of-place bridge
//      - metadata clear/commit only at safe boundaries
//   6) grover_ckpt_segment_router
//      - bridge contract: PASS1 src->dst, PASS2 dst->dst
//
// Deliberately NOT implemented yet
//   - modified/retimed grover_ctrl_fsm integration for the extra read-mux stage
//   - Shadow-J window
//   - Rolling-H DP policy engine (LOOKAHEAD_H design point intentionally not frozen here)
//   - speculative plan FIFO / BBHT top-level integration
//
// IMPORTANT
//   CKPT_K is constrained to 3 or 4. Physical slot IDs remain 2 bits.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

//------------------------------------------------------------------------------
// One packed amplitude state.
//
// External contract is intentionally identical to the existing grover_amp_mem:
//   rd_amp / wr_amp = 32 * 23 = 736 bits.
// Internal mapping verified separately in Vivado 2022.1:
//   mem0..mem9 : 512 x 69 bits (3 lanes each)
//   mem10      : 512 x 46 bits (2 lanes)
// -> 11 RAMB36E1/state on xc7a100tcsg324-1.
//------------------------------------------------------------------------------
module grover_amp_mem_packed (
    input  wire                              clk,
    input  wire [`GP_ROW_W-1:0]              rd_row,
    input  wire                              rd_en,
    output wire [`GP_P*`GP_AMP_W-1:0]        rd_amp,
    input  wire [`GP_ROW_W-1:0]              wr_row,
    input  wire                              wr_en,
    input  wire [`GP_P*`GP_AMP_W-1:0]        wr_amp
);
    // v1.1 is intentionally frozen to the current Q14/P32/F22 baseline.
    // These widths make any accidental parameter drift obvious at integration.
    localparam integer AMP_ROW_BITS = `GP_P * `GP_AMP_W; // 736

    (* ram_style = "block" *) reg [68:0] mem0  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem1  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem2  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem3  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem4  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem5  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem6  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem7  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem8  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem9  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [45:0] mem10 [0:`GP_ROWS-1];

    reg [68:0] q0;
    reg [68:0] q1;
    reg [68:0] q2;
    reg [68:0] q3;
    reg [68:0] q4;
    reg [68:0] q5;
    reg [68:0] q6;
    reg [68:0] q7;
    reg [68:0] q8;
    reg [68:0] q9;
    reg [45:0] q10;

    // Independent synchronous read port.
    always @(posedge clk) begin
        if (rd_en) begin
            q0  <= mem0 [rd_row];
            q1  <= mem1 [rd_row];
            q2  <= mem2 [rd_row];
            q3  <= mem3 [rd_row];
            q4  <= mem4 [rd_row];
            q5  <= mem5 [rd_row];
            q6  <= mem6 [rd_row];
            q7  <= mem7 [rd_row];
            q8  <= mem8 [rd_row];
            q9  <= mem9 [rd_row];
            q10 <= mem10[rd_row];
        end
    end

    // Independent synchronous write port. No array reset.
    always @(posedge clk) begin
        if (wr_en) begin
            mem0 [wr_row] <= wr_amp[68:0];
            mem1 [wr_row] <= wr_amp[137:69];
            mem2 [wr_row] <= wr_amp[206:138];
            mem3 [wr_row] <= wr_amp[275:207];
            mem4 [wr_row] <= wr_amp[344:276];
            mem5 [wr_row] <= wr_amp[413:345];
            mem6 [wr_row] <= wr_amp[482:414];
            mem7 [wr_row] <= wr_amp[551:483];
            mem8 [wr_row] <= wr_amp[620:552];
            mem9 [wr_row] <= wr_amp[689:621];
            mem10[wr_row] <= wr_amp[735:690];
        end
    end

    assign rd_amp[68:0]    = q0;
    assign rd_amp[137:69]  = q1;
    assign rd_amp[206:138] = q2;
    assign rd_amp[275:207] = q3;
    assign rd_amp[344:276] = q4;
    assign rd_amp[413:345] = q5;
    assign rd_amp[482:414] = q6;
    assign rd_amp[551:483] = q7;
    assign rd_amp[620:552] = q8;
    assign rd_amp[689:621] = q9;
    assign rd_amp[735:690] = q10;

    // Synthesis-time intent guard (not a hardware assertion).
    // AMP_ROW_BITS is referenced so lint does not treat it as dead metadata.
    wire _unused_width_guard = (AMP_ROW_BITS == 736);
endmodule

//------------------------------------------------------------------------------
// CKPT_K full-state storage with packed-word-local registered source muxes.
//
// Physical-intent note:
//   The logical row is 736 bits, but the implementation is deliberately expressed
//   as 10 x 69-bit + 1 x 46-bit mux/register groups. This preserves the same
//   boundaries as the 11 packed RAMB36 banks so place/route is free to keep each
//   source-select cone local to its corresponding BRAM group.
//
// Read latency:
//   request sampled at edge t
//   packed BRAM q updates after edge t
//   selected row is captured into rd_amp at edge t+1
// Therefore rd_valid pulses one cycle after BRAM q becomes valid, i.e. the
// checkpoint wrapper adds one explicit stage beyond the baseline amp BRAM.
// The later grover_ctrl_fsm integration MUST retime row/data/write alignment.
//------------------------------------------------------------------------------
module grover_ckpt_mem #(
    parameter integer CKPT_K = 4
) (
    input  wire                              clk,

    input  wire [1:0]                        rd_slot,
    input  wire [`GP_ROW_W-1:0]              rd_row,
    input  wire                              rd_en,
    output reg  [`GP_P*`GP_AMP_W-1:0]        rd_amp,
    output reg                               rd_valid,

    input  wire [1:0]                        wr_slot,
    input  wire [`GP_ROW_W-1:0]              wr_row,
    input  wire                              wr_en,
    input  wire [`GP_P*`GP_AMP_W-1:0]        wr_amp
);
    localparam integer AMP_ROW_BITS = `GP_P * `GP_AMP_W;

    wire [AMP_ROW_BITS-1:0] q0;
    wire [AMP_ROW_BITS-1:0] q1;
    wire [AMP_ROW_BITS-1:0] q2;
    wire [AMP_ROW_BITS-1:0] q3;

    wire we0 = wr_en && (wr_slot == 2'd0);
    wire we1 = wr_en && (wr_slot == 2'd1);
    wire we2 = wr_en && (wr_slot == 2'd2);
    wire we3 = wr_en && (wr_slot == 2'd3) && (CKPT_K == 4);

    // All active slots receive the same read row. This is the exact structure
    // used by the K3/K4 736-bit mux OOC micro-synthesis.
    grover_amp_mem_packed u_slot0 (
        .clk(clk), .rd_row(rd_row), .rd_en(rd_en), .rd_amp(q0),
        .wr_row(wr_row), .wr_en(we0), .wr_amp(wr_amp)
    );
    grover_amp_mem_packed u_slot1 (
        .clk(clk), .rd_row(rd_row), .rd_en(rd_en), .rd_amp(q1),
        .wr_row(wr_row), .wr_en(we1), .wr_amp(wr_amp)
    );
    grover_amp_mem_packed u_slot2 (
        .clk(clk), .rd_row(rd_row), .rd_en(rd_en), .rd_amp(q2),
        .wr_row(wr_row), .wr_en(we2), .wr_amp(wr_amp)
    );

    generate
        if (CKPT_K == 4) begin : g_k4_slot
            grover_amp_mem_packed u_slot3 (
                .clk(clk), .rd_row(rd_row), .rd_en(rd_en), .rd_amp(q3),
                .wr_row(wr_row), .wr_en(we3), .wr_amp(wr_amp)
            );
        end else begin : g_k3_no_slot
            assign q3 = {AMP_ROW_BITS{1'b0}};
        end
    endgenerate

    reg [1:0] rd_slot_d;
    reg       rd_valid_d;

    // Keep the source-select/register stage aligned with the packed BRAM words
    // instead of describing one monolithic 736-bit mux. Functionally this is
    // identical, but it gives physical implementation 11 independent local cones.
    reg [68:0] sel_g0, sel_g1, sel_g2, sel_g3, sel_g4;
    reg [68:0] sel_g5, sel_g6, sel_g7, sel_g8, sel_g9;
    reg [45:0] sel_g10;

    reg [68:0] rd_g0, rd_g1, rd_g2, rd_g3, rd_g4;
    reg [68:0] rd_g5, rd_g6, rd_g7, rd_g8, rd_g9;
    reg [45:0] rd_g10;

    always @* begin
        sel_g0  = 69'd0; sel_g1  = 69'd0; sel_g2  = 69'd0;
        sel_g3  = 69'd0; sel_g4  = 69'd0; sel_g5  = 69'd0;
        sel_g6  = 69'd0; sel_g7  = 69'd0; sel_g8  = 69'd0;
        sel_g9  = 69'd0; sel_g10 = 46'd0;

        case (rd_slot_d)
            2'd0: begin
                sel_g0=q0[68:0];    sel_g1=q0[137:69];  sel_g2=q0[206:138];
                sel_g3=q0[275:207]; sel_g4=q0[344:276]; sel_g5=q0[413:345];
                sel_g6=q0[482:414]; sel_g7=q0[551:483]; sel_g8=q0[620:552];
                sel_g9=q0[689:621]; sel_g10=q0[735:690];
            end
            2'd1: begin
                sel_g0=q1[68:0];    sel_g1=q1[137:69];  sel_g2=q1[206:138];
                sel_g3=q1[275:207]; sel_g4=q1[344:276]; sel_g5=q1[413:345];
                sel_g6=q1[482:414]; sel_g7=q1[551:483]; sel_g8=q1[620:552];
                sel_g9=q1[689:621]; sel_g10=q1[735:690];
            end
            2'd2: begin
                sel_g0=q2[68:0];    sel_g1=q2[137:69];  sel_g2=q2[206:138];
                sel_g3=q2[275:207]; sel_g4=q2[344:276]; sel_g5=q2[413:345];
                sel_g6=q2[482:414]; sel_g7=q2[551:483]; sel_g8=q2[620:552];
                sel_g9=q2[689:621]; sel_g10=q2[735:690];
            end
            2'd3: begin
                if (CKPT_K == 4) begin
                    sel_g0=q3[68:0];    sel_g1=q3[137:69];  sel_g2=q3[206:138];
                    sel_g3=q3[275:207]; sel_g4=q3[344:276]; sel_g5=q3[413:345];
                    sel_g6=q3[482:414]; sel_g7=q3[551:483]; sel_g8=q3[620:552];
                    sel_g9=q3[689:621]; sel_g10=q3[735:690];
                end
            end
            default: begin end
        endcase
    end

    always @(posedge clk) begin
        if (rd_en)
            rd_slot_d <= rd_slot;
        rd_valid_d <= rd_en;

        if (rd_valid_d) begin
            rd_g0  <= sel_g0;  rd_g1  <= sel_g1;  rd_g2  <= sel_g2;
            rd_g3  <= sel_g3;  rd_g4  <= sel_g4;  rd_g5  <= sel_g5;
            rd_g6  <= sel_g6;  rd_g7  <= sel_g7;  rd_g8  <= sel_g8;
            rd_g9  <= sel_g9;  rd_g10 <= sel_g10;
        end
        rd_valid <= rd_valid_d;
    end

    always @* begin
        rd_amp = {AMP_ROW_BITS{1'b0}};
        rd_amp[68:0]    = rd_g0;
        rd_amp[137:69]  = rd_g1;
        rd_amp[206:138] = rd_g2;
        rd_amp[275:207] = rd_g3;
        rd_amp[344:276] = rd_g4;
        rd_amp[413:345] = rd_g5;
        rd_amp[482:414] = rd_g6;
        rd_amp[551:483] = rd_g7;
        rd_amp[620:552] = rd_g8;
        rd_amp[689:621] = rd_g9;
        rd_amp[735:690] = rd_g10;
    end
endmodule

//------------------------------------------------------------------------------
// CKPT_K checkpoint metadata.
// Physical slots never move. Canonical S is produced only for policy input.
// Ports are fixed to four slots so CKPT_K=3 and 4 share one Main-IP seam.
//------------------------------------------------------------------------------
module grover_ckpt_meta #(
    parameter integer CKPT_K = 4
) (
    input  wire                         clk,
    input  wire                         rstn,

    input  wire                         invalidate_all,
    input  wire                         clear_en,
    input  wire [3:0]                   clear_mask,
    input  wire                         commit_en,
    input  wire [1:0]                   commit_slot,
    input  wire [`GP_J_W-1:0]           commit_j,

    output reg  [3:0]                   slot_valid,
    output reg  [4*`GP_J_W-1:0]         slot_j_flat,

    output reg  [2:0]                   sorted_count,
    output reg  [4*`GP_J_W-1:0]         sorted_j_flat
);
    localparam [3:0] ACTIVE_MASK = (CKPT_K == 4) ? 4'b1111 : 4'b0111;

    reg [3:0] valid_next;
    reg [7:0] s0, s1, s2, s3, tmp;

    always @* begin
        valid_next = slot_valid & ACTIVE_MASK;
        if (invalidate_all) begin
            valid_next = 4'b0000;
        end else begin
            if (clear_en)
                valid_next = valid_next & ~(clear_mask & ACTIVE_MASK);
            if (commit_en && (commit_slot < CKPT_K))
                valid_next[commit_slot] = 1'b1;
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            slot_valid  <= 4'b0000;
            slot_j_flat <= {(4*`GP_J_W){1'b0}};
        end else begin
            slot_valid <= valid_next;
            if (commit_en && (commit_slot < CKPT_K)) begin
                case (commit_slot)
                    2'd0: slot_j_flat[0*`GP_J_W +: `GP_J_W] <= commit_j;
                    2'd1: slot_j_flat[1*`GP_J_W +: `GP_J_W] <= commit_j;
                    2'd2: slot_j_flat[2*`GP_J_W +: `GP_J_W] <= commit_j;
                    2'd3: slot_j_flat[3*`GP_J_W +: `GP_J_W] <= commit_j;
                    default: begin end
                endcase
            end
        end
    end

    // Four-input sorting network. 8'hFF is outside legal 7-bit j range.
    always @* begin
        s0 = slot_valid[0] ? {1'b0, slot_j_flat[0*`GP_J_W +: `GP_J_W]} : 8'hFF;
        s1 = slot_valid[1] ? {1'b0, slot_j_flat[1*`GP_J_W +: `GP_J_W]} : 8'hFF;
        s2 = slot_valid[2] ? {1'b0, slot_j_flat[2*`GP_J_W +: `GP_J_W]} : 8'hFF;
        s3 = ((CKPT_K == 4) && slot_valid[3]) ?
             {1'b0, slot_j_flat[3*`GP_J_W +: `GP_J_W]} : 8'hFF;

        if (s0 > s1) begin tmp=s0; s0=s1; s1=tmp; end
        if (s2 > s3) begin tmp=s2; s2=s3; s3=tmp; end
        if (s0 > s2) begin tmp=s0; s0=s2; s2=tmp; end
        if (s1 > s3) begin tmp=s1; s1=s3; s3=tmp; end
        if (s1 > s2) begin tmp=s1; s1=s2; s2=tmp; end

        sorted_count = {2'b00,slot_valid[0]} + {2'b00,slot_valid[1]} +
                       {2'b00,slot_valid[2]} +
                       ((CKPT_K == 4) ? {2'b00,slot_valid[3]} : 3'd0);

        sorted_j_flat = {(4*`GP_J_W){1'b0}};
        if (s0 != 8'hFF) sorted_j_flat[0*`GP_J_W +: `GP_J_W] = s0[`GP_J_W-1:0];
        if (s1 != 8'hFF) sorted_j_flat[1*`GP_J_W +: `GP_J_W] = s1[`GP_J_W-1:0];
        if (s2 != 8'hFF) sorted_j_flat[2*`GP_J_W +: `GP_J_W] = s2[`GP_J_W-1:0];
        if (s3 != 8'hFF) sorted_j_flat[3*`GP_J_W +: `GP_J_W] = s3[`GP_J_W-1:0];
    end
endmodule

//------------------------------------------------------------------------------
// Logical S' -> physical plan compiler.
//
// Policy input is slot-agnostic and canonical:
//   policy_source_j + policy_next_count + sorted policy_next_j_flat.
// Planner output is a sequence of newly materialized forward-path boundaries.
// The last boundary is always endpoint j_req. Previous boundaries are B-mode
// intermediates. Old checkpoints retained in S' are locked by retain_mask.
//------------------------------------------------------------------------------
module grover_ckpt_planner #(
    parameter integer CKPT_K = 4
) (
    input  wire                         policy_valid,

    input  wire [3:0]                   slot_valid,
    input  wire [4*`GP_J_W-1:0]         slot_j_flat,

    input  wire [`GP_J_W-1:0]           j_req,
    input  wire [`GP_J_W-1:0]           policy_source_j,
    input  wire [2:0]                   policy_next_count,
    input  wire [4*`GP_J_W-1:0]         policy_next_j_flat,

    output reg                          plan_valid,
    output reg                          plan_error,
    output reg                          exact_hit,

    output reg                          source_is_anchor,
    output reg                          source_materialized,
    output reg                          source_retain,
    output reg  [1:0]                   source_slot,

    output reg  [3:0]                   retain_mask,
    output reg  [3:0]                   clear_mask,

    output reg  [2:0]                   boundary_count,
    output reg  [4*`GP_J_W-1:0]         boundary_j_flat,
    output reg  [7:0]                   boundary_slot_flat,
    output reg  [1:0]                   endpoint_slot
);
    localparam [3:0] ACTIVE_MASK = (CKPT_K == 4) ? 4'b1111 : 4'b0111;
    localparam [2:0] K_COUNT     = CKPT_K;

    reg [`GP_J_W-1:0] sj [0:3];
    reg [`GP_J_W-1:0] nj [0:3];
    reg [`GP_J_W-1:0] bj [0:3];
    reg [1:0]          bs [0:3];

    reg [3:0] old_in_next;
    reg [3:0] next_is_old;
    reg [3:0] avail;

    reg [`GP_J_W-1:0] pred_j;
    reg pred_found;
    reg [1:0] pred_slot;
    reg [1:0] exact_slot;
    reg exact_found;

    reg endpoint_present;
    reg canonical_ok;
    reg exact_same_set;
    reg legal_next;
    reg alloc_ok;
    reg [2:0] current_count;
    reg [2:0] new_count;

    integer i;
    integer j;
    integer n;

    function [1:0] lowest_slot4;
        input [3:0] mask;
        begin
            if      (mask[0]) lowest_slot4 = 2'd0;
            else if (mask[1]) lowest_slot4 = 2'd1;
            else if (mask[2]) lowest_slot4 = 2'd2;
            else              lowest_slot4 = 2'd3;
        end
    endfunction

    always @* begin
        // Unpack inputs.
        for (i=0; i<4; i=i+1) begin
            sj[i] = slot_j_flat[i*`GP_J_W +: `GP_J_W];
            nj[i] = policy_next_j_flat[i*`GP_J_W +: `GP_J_W];
            bj[i] = {`GP_J_W{1'b0}};
            bs[i] = 2'd0;
        end

        plan_valid          = 1'b0;
        plan_error          = 1'b0;
        exact_hit           = 1'b0;
        source_is_anchor    = 1'b0;
        source_materialized = 1'b0;
        source_retain       = 1'b0;
        source_slot         = 2'd0;
        retain_mask         = 4'b0000;
        clear_mask          = 4'b0000;
        boundary_count      = 3'd0;
        boundary_j_flat     = {(4*`GP_J_W){1'b0}};
        boundary_slot_flat  = 8'd0;
        endpoint_slot       = 2'd0;

        old_in_next    = 4'b0000;
        next_is_old    = 4'b0000;
        avail          = 4'b0000;
        pred_j         = {`GP_J_W{1'b0}};
        pred_found     = 1'b0;
        pred_slot      = 2'd0;
        exact_slot     = 2'd0;
        exact_found    = 1'b0;
        endpoint_present = 1'b0;
        canonical_ok   = 1'b1;
        exact_same_set = 1'b1;
        legal_next     = 1'b1;
        alloc_ok       = 1'b1;
        current_count  = 3'd0;
        new_count      = 3'd0;

        // Count active physical checkpoints and locate exact endpoint/source.
        for (i=0; i<4; i=i+1) begin
            if ((i < CKPT_K) && slot_valid[i]) begin
                current_count = current_count + 1'b1;
                if (sj[i] == j_req) begin
                    exact_found = 1'b1;
                    exact_slot  = i[1:0];
                end
                if ((sj[i] <= j_req) && (!pred_found || (sj[i] > pred_j))) begin
                    pred_found = 1'b1;
                    pred_j     = sj[i];
                    pred_slot  = i[1:0];
                end
            end
        end

        // Validate policy S' shape and build old<->next membership maps.
        if ((policy_next_count == 0) || (policy_next_count > K_COUNT))
            canonical_ok = 1'b0;

        for (i=0; i<4; i=i+1) begin
            if (i < policy_next_count) begin
                if (nj[i] == j_req)
                    endpoint_present = 1'b1;
                if ((i > 0) && !(nj[i-1] < nj[i]))
                    canonical_ok = 1'b0;

                for (j=0; j<4; j=j+1) begin
                    if ((j < CKPT_K) && slot_valid[j] && (nj[i] == sj[j])) begin
                        next_is_old[i] = 1'b1;
                        old_in_next[j] = 1'b1;
                    end
                end
            end
        end

        retain_mask = old_in_next & ACTIVE_MASK;
        clear_mask  = (slot_valid & ACTIVE_MASK) & ~retain_mask;

        // Closest-predecessor contract. Logical psi0 is available when no
        // materialized predecessor exists; a materialized psi0 is preferred.
        if (pred_found) begin
            if (policy_source_j != pred_j)
                plan_error = 1'b1;
            source_materialized = 1'b1;
            source_slot = pred_slot;
        end else begin
            if (policy_source_j != {`GP_J_W{1'b0}})
                plan_error = 1'b1;
            source_is_anchor = 1'b1;
        end

        if (source_materialized)
            source_retain = retain_mask[source_slot];

        exact_hit = exact_found;

        if (!policy_valid)
            plan_error = 1'b1;
        if (!canonical_ok || !endpoint_present)
            plan_error = 1'b1;

        // Exact-hit contract: DSE's only legal no-movement action is S'=S.
        if (exact_found) begin
            if (policy_source_j != j_req)
                exact_same_set = 1'b0;
            if (policy_next_count != current_count)
                exact_same_set = 1'b0;
            for (i=0; i<4; i=i+1) begin
                if ((i < CKPT_K) && slot_valid[i] && !old_in_next[i])
                    exact_same_set = 1'b0;
                if ((i < policy_next_count) && !next_is_old[i])
                    exact_same_set = 1'b0;
            end

            if (!exact_same_set)
                plan_error = 1'b1;

            retain_mask   = slot_valid & ACTIVE_MASK;
            clear_mask    = 4'b0000;
            boundary_count= 3'd0;
            endpoint_slot = exact_slot;
        end else begin
            // Validate every newly-created state and collect boundaries in the
            // already-canonical next-state order. A new psi0 is legal only when
            // the endpoint itself is j=0; otherwise intermediates are a<t<j.
            n = 0;
            for (i=0; i<4; i=i+1) begin
                if (i < policy_next_count) begin
                    if (!next_is_old[i]) begin
                        if ((j_req == 0) && (policy_source_j == 0) && (nj[i] == 0)) begin
                            // legal materialization of psi0 endpoint
                        end else if (!((nj[i] > policy_source_j) && (nj[i] <= j_req))) begin
                            legal_next = 1'b0;
                        end
                        if (n < 4) begin
                            bj[n] = nj[i];
                            n = n + 1;
                        end else begin
                            legal_next = 1'b0;
                        end
                    end
                end
            end
            new_count = n[2:0];
            boundary_count = new_count;

            if (!legal_next || (new_count == 0) || (new_count > K_COUNT))
                plan_error = 1'b1;

            // Physical free/victim pool. Retained slots are never touched.
            avail = ACTIVE_MASK & ~retain_mask;

            for (i=0; i<4; i=i+1) begin
                if (i < new_count) begin
                    if ((i == 0) && source_materialized && !source_retain) begin
                        // v1.1 capacity invariant relies on reusing a destructive
                        // source slot as the first work slot.
                        bs[i] = source_slot;
                        if (!avail[source_slot])
                            alloc_ok = 1'b0;
                        avail[source_slot] = 1'b0;
                    end else begin
                        if (avail == 4'b0000) begin
                            alloc_ok = 1'b0;
                            bs[i] = 2'd0;
                        end else begin
                            bs[i] = lowest_slot4(avail);
                            avail[bs[i]] = 1'b0;
                        end
                    end

                    if (bj[i] == j_req)
                        endpoint_slot = bs[i];
                end
            end

            if (!alloc_ok)
                plan_error = 1'b1;

            for (i=0; i<4; i=i+1) begin
                boundary_j_flat[i*`GP_J_W +: `GP_J_W] = bj[i];
                boundary_slot_flat[i*2 +: 2] = bs[i];
            end
        end

        if (!plan_error)
            plan_valid = 1'b1;
    end
endmodule


//------------------------------------------------------------------------------
// Production autonomous pipelined planner.
//
// Fixed one-cycle internal pipeline:
//   capture edge:
//     - snapshot policy / checkpoint metadata
//     - compute canonical membership maps
//     - compute exact hit
//     - compute closest predecessor with a balanced 4-way tree
//   following cycle:
//     - derive source/retain semantics
//     - validate exact-hit or B-mode boundary set
//     - allocate physical checkpoint slots
//
// The output packet is combinational from Stage-1 registers and is captured by
// the Main-IP auto_plan_pipe register on the following edge.  Therefore the
// original long metadata -> predecessor -> allocation -> plan-packet path is
// split across two clock periods without changing planner semantics.
//
// This module is used only when CKPT_MANUAL_ENABLE=0.  The original
// grover_ckpt_planner remains the authoritative Phase-4B manual path.
//------------------------------------------------------------------------------
module grover_ckpt_planner_pipe #(
    parameter integer CKPT_K = 4
) (
    input  wire                         clk,
    input  wire                         rstn,
    input  wire                         capture,

    input  wire                         policy_valid,
    input  wire [3:0]                   slot_valid,
    input  wire [4*`GP_J_W-1:0]         slot_j_flat,
    input  wire [`GP_J_W-1:0]           j_req,
    input  wire [`GP_J_W-1:0]           policy_source_j,
    input  wire [2:0]                   policy_next_count,
    input  wire [4*`GP_J_W-1:0]         policy_next_j_flat,

    output reg                          plan_valid,
    output reg                          plan_error,
    output reg                          exact_hit,

    output reg                          source_is_anchor,
    output reg                          source_materialized,
    output reg                          source_retain,
    output reg  [1:0]                   source_slot,

    output reg  [3:0]                   retain_mask,
    output reg  [3:0]                   clear_mask,

    output reg  [2:0]                   boundary_count,
    output reg  [4*`GP_J_W-1:0]         boundary_j_flat,
    output reg  [7:0]                   boundary_slot_flat,
    output reg  [1:0]                   endpoint_slot
);
    localparam [3:0] ACTIVE_MASK = (CKPT_K == 4) ? 4'b1111 : 4'b0111;
    localparam [2:0] K_COUNT     = CKPT_K;

    // ---------------------------
    // Stage-1 combinational work.
    // ---------------------------
    wire [`GP_J_W-1:0] in_sj0 = slot_j_flat[0*`GP_J_W +: `GP_J_W];
    wire [`GP_J_W-1:0] in_sj1 = slot_j_flat[1*`GP_J_W +: `GP_J_W];
    wire [`GP_J_W-1:0] in_sj2 = slot_j_flat[2*`GP_J_W +: `GP_J_W];
    wire [`GP_J_W-1:0] in_sj3 = slot_j_flat[3*`GP_J_W +: `GP_J_W];

    wire [`GP_J_W-1:0] in_nj0 = policy_next_j_flat[0*`GP_J_W +: `GP_J_W];
    wire [`GP_J_W-1:0] in_nj1 = policy_next_j_flat[1*`GP_J_W +: `GP_J_W];
    wire [`GP_J_W-1:0] in_nj2 = policy_next_j_flat[2*`GP_J_W +: `GP_J_W];
    wire [`GP_J_W-1:0] in_nj3 = policy_next_j_flat[3*`GP_J_W +: `GP_J_W];

    wire a0 = (CKPT_K > 0) && slot_valid[0];
    wire a1 = (CKPT_K > 1) && slot_valid[1];
    wire a2 = (CKPT_K > 2) && slot_valid[2];
    wire a3 = (CKPT_K > 3) && slot_valid[3];

    wire e0 = a0 && (in_sj0 <= j_req);
    wire e1 = a1 && (in_sj1 <= j_req);
    wire e2 = a2 && (in_sj2 <= j_req);
    wire e3 = a3 && (in_sj3 <= j_req);

    // Balanced pairwise max tree for closest predecessor.
    wire p01_found = e0 | e1;
    wire p23_found = e2 | e3;

    wire p01_take1 = e1 && (!e0 || (in_sj1 > in_sj0));
    wire p23_take3 = e3 && (!e2 || (in_sj3 > in_sj2));

    wire [`GP_J_W-1:0] p01_j = p01_take1 ? in_sj1 : in_sj0;
    wire [`GP_J_W-1:0] p23_j = p23_take3 ? in_sj3 : in_sj2;
    wire [1:0] p01_slot = p01_take1 ? 2'd1 : 2'd0;
    wire [1:0] p23_slot = p23_take3 ? 2'd3 : 2'd2;

    wire pred_take23 = p23_found && (!p01_found || (p23_j > p01_j));
    wire s1_pred_found_d = p01_found | p23_found;
    wire [`GP_J_W-1:0] s1_pred_j_d =
        pred_take23 ? p23_j : p01_j;
    wire [1:0] s1_pred_slot_d =
        pred_take23 ? p23_slot : p01_slot;

    wire x0 = a0 && (in_sj0 == j_req);
    wire x1 = a1 && (in_sj1 == j_req);
    wire x2 = a2 && (in_sj2 == j_req);
    wire x3 = a3 && (in_sj3 == j_req);

    // Metadata is canonical, so duplicates should not exist; preserve the
    // original loop's effective "last matching slot wins" behavior anyway.
    wire s1_exact_found_d = x0 | x1 | x2 | x3;
    wire [1:0] s1_exact_slot_d =
        x3 ? 2'd3 :
        x2 ? 2'd2 :
        x1 ? 2'd1 : 2'd0;

    wire n0_active = (policy_next_count > 0);
    wire n1_active = (policy_next_count > 1);
    wire n2_active = (policy_next_count > 2);
    wire n3_active = (policy_next_count > 3);

    wire next0_old = n0_active &&
        ((a0 && (in_nj0 == in_sj0)) || (a1 && (in_nj0 == in_sj1)) ||
         (a2 && (in_nj0 == in_sj2)) || (a3 && (in_nj0 == in_sj3)));
    wire next1_old = n1_active &&
        ((a0 && (in_nj1 == in_sj0)) || (a1 && (in_nj1 == in_sj1)) ||
         (a2 && (in_nj1 == in_sj2)) || (a3 && (in_nj1 == in_sj3)));
    wire next2_old = n2_active &&
        ((a0 && (in_nj2 == in_sj0)) || (a1 && (in_nj2 == in_sj1)) ||
         (a2 && (in_nj2 == in_sj2)) || (a3 && (in_nj2 == in_sj3)));
    wire next3_old = n3_active &&
        ((a0 && (in_nj3 == in_sj0)) || (a1 && (in_nj3 == in_sj1)) ||
         (a2 && (in_nj3 == in_sj2)) || (a3 && (in_nj3 == in_sj3)));

    wire old0_next = a0 &&
        ((n0_active && (in_sj0 == in_nj0)) || (n1_active && (in_sj0 == in_nj1)) ||
         (n2_active && (in_sj0 == in_nj2)) || (n3_active && (in_sj0 == in_nj3)));
    wire old1_next = a1 &&
        ((n0_active && (in_sj1 == in_nj0)) || (n1_active && (in_sj1 == in_nj1)) ||
         (n2_active && (in_sj1 == in_nj2)) || (n3_active && (in_sj1 == in_nj3)));
    wire old2_next = a2 &&
        ((n0_active && (in_sj2 == in_nj0)) || (n1_active && (in_sj2 == in_nj1)) ||
         (n2_active && (in_sj2 == in_nj2)) || (n3_active && (in_sj2 == in_nj3)));
    wire old3_next = a3 &&
        ((n0_active && (in_sj3 == in_nj0)) || (n1_active && (in_sj3 == in_nj1)) ||
         (n2_active && (in_sj3 == in_nj2)) || (n3_active && (in_sj3 == in_nj3)));

    wire [3:0] s1_next_is_old_d = {next3_old, next2_old, next1_old, next0_old};
    wire [3:0] s1_old_in_next_d = {old3_next, old2_next, old1_next, old0_next};
    wire [3:0] s1_retain_mask_d = s1_old_in_next_d & ACTIVE_MASK;
    wire [3:0] s1_clear_mask_d =
        (slot_valid & ACTIVE_MASK) & ~s1_retain_mask_d;

    wire s1_endpoint_present_d =
        (n0_active && (in_nj0 == j_req)) ||
        (n1_active && (in_nj1 == j_req)) ||
        (n2_active && (in_nj2 == j_req)) ||
        (n3_active && (in_nj3 == j_req));

    wire s1_canonical_ok_d =
        (policy_next_count != 0) &&
        (policy_next_count <= K_COUNT) &&
        (!n1_active || (in_nj0 < in_nj1)) &&
        (!n2_active || (in_nj1 < in_nj2)) &&
        (!n3_active || (in_nj2 < in_nj3));

    wire [2:0] s1_current_count_d =
        {2'b00,a0} + {2'b00,a1} + {2'b00,a2} + {2'b00,a3};

    // ----------------
    // Stage-1 registers
    // ----------------
    reg                         s1_policy_valid;
    reg [3:0]                   s1_slot_valid;
    reg [`GP_J_W-1:0]           s1_j_req;
    reg [`GP_J_W-1:0]           s1_policy_source_j;
    reg [2:0]                   s1_policy_next_count;
    reg [4*`GP_J_W-1:0]         s1_policy_next_j_flat;

    reg                         s1_pred_found;
    reg [`GP_J_W-1:0]           s1_pred_j;
    reg [1:0]                   s1_pred_slot;
    reg                         s1_exact_found;
    reg [1:0]                   s1_exact_slot;
    reg [3:0]                   s1_next_is_old;
    reg [3:0]                   s1_old_in_next;
    reg [3:0]                   s1_retain_mask;
    reg [3:0]                   s1_clear_mask;
    reg                         s1_endpoint_present;
    reg                         s1_canonical_ok;
    reg [2:0]                   s1_current_count;

    always @(posedge clk) begin
        if (!rstn) begin
            s1_policy_valid       <= 1'b0;
            s1_slot_valid         <= 4'b0000;
            s1_j_req              <= {`GP_J_W{1'b0}};
            s1_policy_source_j    <= {`GP_J_W{1'b0}};
            s1_policy_next_count  <= 3'd0;
            s1_policy_next_j_flat <= {(4*`GP_J_W){1'b0}};

            s1_pred_found         <= 1'b0;
            s1_pred_j             <= {`GP_J_W{1'b0}};
            s1_pred_slot          <= 2'd0;
            s1_exact_found        <= 1'b0;
            s1_exact_slot         <= 2'd0;
            s1_next_is_old        <= 4'b0000;
            s1_old_in_next        <= 4'b0000;
            s1_retain_mask        <= 4'b0000;
            s1_clear_mask         <= 4'b0000;
            s1_endpoint_present   <= 1'b0;
            s1_canonical_ok       <= 1'b0;
            s1_current_count      <= 3'd0;
        end else if (capture) begin
            s1_policy_valid       <= policy_valid;
            s1_slot_valid         <= slot_valid;
            s1_j_req              <= j_req;
            s1_policy_source_j    <= policy_source_j;
            s1_policy_next_count  <= policy_next_count;
            s1_policy_next_j_flat <= policy_next_j_flat;

            s1_pred_found         <= s1_pred_found_d;
            s1_pred_j             <= s1_pred_j_d;
            s1_pred_slot          <= s1_pred_slot_d;
            s1_exact_found        <= s1_exact_found_d;
            s1_exact_slot         <= s1_exact_slot_d;
            s1_next_is_old        <= s1_next_is_old_d;
            s1_old_in_next        <= s1_old_in_next_d;
            s1_retain_mask        <= s1_retain_mask_d;
            s1_clear_mask         <= s1_clear_mask_d;
            s1_endpoint_present   <= s1_endpoint_present_d;
            s1_canonical_ok       <= s1_canonical_ok_d;
            s1_current_count      <= s1_current_count_d;
        end
    end

    // ---------------------------
    // Stage-2 planner computation.
    // ---------------------------
    reg [`GP_J_W-1:0] nj [0:3];
    reg [`GP_J_W-1:0] bj [0:3];
    reg [1:0]          bs [0:3];

    reg [3:0] avail;
    reg exact_same_set;
    reg legal_next;
    reg alloc_ok;
    reg [2:0] new_count;
    integer i;
    integer n;

    function [1:0] lowest_slot4;
        input [3:0] mask;
        begin
            if      (mask[0]) lowest_slot4 = 2'd0;
            else if (mask[1]) lowest_slot4 = 2'd1;
            else if (mask[2]) lowest_slot4 = 2'd2;
            else              lowest_slot4 = 2'd3;
        end
    endfunction

    always @* begin
        for (i=0; i<4; i=i+1) begin
            nj[i] = s1_policy_next_j_flat[i*`GP_J_W +: `GP_J_W];
            bj[i] = {`GP_J_W{1'b0}};
            bs[i] = 2'd0;
        end

        plan_valid          = 1'b0;
        plan_error          = 1'b0;
        exact_hit           = s1_exact_found;
        source_is_anchor    = 1'b0;
        source_materialized = 1'b0;
        source_retain       = 1'b0;
        source_slot         = 2'd0;
        retain_mask         = s1_retain_mask;
        clear_mask          = s1_clear_mask;
        boundary_count      = 3'd0;
        boundary_j_flat     = {(4*`GP_J_W){1'b0}};
        boundary_slot_flat  = 8'd0;
        endpoint_slot       = 2'd0;

        avail          = 4'b0000;
        exact_same_set = 1'b1;
        legal_next     = 1'b1;
        alloc_ok       = 1'b1;
        new_count      = 3'd0;

        // Closest-predecessor contract.
        if (s1_pred_found) begin
            if (s1_policy_source_j != s1_pred_j)
                plan_error = 1'b1;
            source_materialized = 1'b1;
            source_slot = s1_pred_slot;
        end else begin
            if (s1_policy_source_j != {`GP_J_W{1'b0}})
                plan_error = 1'b1;
            source_is_anchor = 1'b1;
        end

        if (source_materialized)
            source_retain = s1_retain_mask[source_slot];

        if (!s1_policy_valid)
            plan_error = 1'b1;
        if (!s1_canonical_ok || !s1_endpoint_present)
            plan_error = 1'b1;

        // Exact-hit contract: S' must equal S.
        if (s1_exact_found) begin
            if (s1_policy_source_j != s1_j_req)
                exact_same_set = 1'b0;
            if (s1_policy_next_count != s1_current_count)
                exact_same_set = 1'b0;

            for (i=0; i<4; i=i+1) begin
                if ((i < CKPT_K) && s1_slot_valid[i] && !s1_old_in_next[i])
                    exact_same_set = 1'b0;
                if ((i < s1_policy_next_count) && !s1_next_is_old[i])
                    exact_same_set = 1'b0;
            end

            if (!exact_same_set)
                plan_error = 1'b1;

            retain_mask    = s1_slot_valid & ACTIVE_MASK;
            clear_mask     = 4'b0000;
            boundary_count = 3'd0;
            endpoint_slot  = s1_exact_slot;
        end else begin
            // Collect newly-created boundaries in canonical S' order.
            n = 0;
            for (i=0; i<4; i=i+1) begin
                if (i < s1_policy_next_count) begin
                    if (!s1_next_is_old[i]) begin
                        if ((s1_j_req == 0) &&
                            (s1_policy_source_j == 0) &&
                            (nj[i] == 0)) begin
                            // legal psi0 endpoint materialization
                        end else if (!((nj[i] > s1_policy_source_j) &&
                                       (nj[i] <= s1_j_req))) begin
                            legal_next = 1'b0;
                        end

                        if (n < 4) begin
                            bj[n] = nj[i];
                            n = n + 1;
                        end else begin
                            legal_next = 1'b0;
                        end
                    end
                end
            end

            new_count = n[2:0];
            boundary_count = new_count;

            if (!legal_next || (new_count == 0) || (new_count > K_COUNT))
                plan_error = 1'b1;

            avail = ACTIVE_MASK & ~s1_retain_mask;

            for (i=0; i<4; i=i+1) begin
                if (i < new_count) begin
                    if ((i == 0) && source_materialized && !source_retain) begin
                        bs[i] = source_slot;
                        if (!avail[source_slot])
                            alloc_ok = 1'b0;
                        avail[source_slot] = 1'b0;
                    end else begin
                        if (avail == 4'b0000) begin
                            alloc_ok = 1'b0;
                            bs[i] = 2'd0;
                        end else begin
                            bs[i] = lowest_slot4(avail);
                            avail[bs[i]] = 1'b0;
                        end
                    end

                    if (bj[i] == s1_j_req)
                        endpoint_slot = bs[i];
                end
            end

            if (!alloc_ok)
                plan_error = 1'b1;

            for (i=0; i<4; i=i+1) begin
                boundary_j_flat[i*`GP_J_W +: `GP_J_W] = bj[i];
                boundary_slot_flat[i*2 +: 2] = bs[i];
            end
        end

        if (!plan_error)
            plan_valid = 1'b1;
    end
endmodule

//------------------------------------------------------------------------------
// Parameterized execution sequencer.
//
// Planner provides newly materialized boundaries in forward order. The last
// boundary is endpoint. Each completed non-endpoint boundary is committed as a
// B-mode intermediate and therefore forces the next forward iteration to be a
// 1-iteration out-of-place bridge into the next boundary slot.
//------------------------------------------------------------------------------
module grover_ckpt_executor (
    input  wire                         clk,
    input  wire                         rstn,

    input  wire                         start,
    input  wire                         invalidate,

    input  wire                         plan_valid,
    input  wire                         plan_exact_hit,
    input  wire                         plan_source_is_anchor,
    input  wire                         plan_source_materialized,
    input  wire                         plan_source_retain,
    input  wire [1:0]                   plan_source_slot,
    input  wire [`GP_J_W-1:0]           plan_source_j,
    input  wire [`GP_J_W-1:0]           plan_j_req,
    input  wire [3:0]                   plan_clear_mask,
    input  wire [2:0]                   plan_boundary_count,
    input  wire [4*`GP_J_W-1:0]         plan_boundary_j_flat,
    input  wire [7:0]                   plan_boundary_slot_flat,
    input  wire [1:0]                   plan_endpoint_slot,

    // Inner one-segment Grover engine request.
    output reg                          iter_start,
    output reg                          iter_do_init,
    output reg  [15:0]                  iter_count,
    output reg  [1:0]                   iter_src_slot,
    output reg  [1:0]                   iter_dst_slot,
    output reg                          iter_bridge,
    input  wire                         iter_busy,
    input  wire                         iter_done,

    // Metadata operations.
    output reg                          meta_clear_en,
    output reg  [3:0]                   meta_clear_mask,
    output reg                          meta_commit_en,
    output reg  [1:0]                   meta_commit_slot,
    output reg  [`GP_J_W-1:0]           meta_commit_j,

    output reg                          busy,
    output reg                          done,
    output reg                          aborted,
    output reg  [1:0]                   endpoint_slot,

    // Debug/counters for later Main-IP integration.
    output reg  [31:0]                  physical_iter_issued,
    output reg  [15:0]                  bridge_count,
    output reg  [15:0]                  intermediate_commit_count
);
    localparam [2:0] E_IDLE         = 3'd0;
    localparam [2:0] E_WAIT_INPLACE = 3'd1;
    localparam [2:0] E_WAIT_BRIDGE  = 3'd2;

    reg [2:0] st;
    reg abort_pending;

    reg [2:0] boundary_count_q;
    reg [4*`GP_J_W-1:0] boundary_j_q;
    reg [7:0] boundary_slot_q;
    reg [2:0] boundary_idx;
    reg [15:0] bridge_remaining;

    reg [`GP_J_W-1:0] current_boundary_j;
    reg [1:0] current_boundary_slot;

    reg [15:0] delta16;
    reg [`GP_J_W-1:0] target_j;
    reg [1:0] target_slot;

    function [`GP_J_W-1:0] bj_at;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: bj_at = boundary_j_q[0*`GP_J_W +: `GP_J_W];
                3'd1: bj_at = boundary_j_q[1*`GP_J_W +: `GP_J_W];
                3'd2: bj_at = boundary_j_q[2*`GP_J_W +: `GP_J_W];
                3'd3: bj_at = boundary_j_q[3*`GP_J_W +: `GP_J_W];
                default: bj_at = {`GP_J_W{1'b0}};
            endcase
        end
    endfunction

    function [1:0] bs_at;
        input [2:0] idx;
        begin
            case (idx)
                3'd0: bs_at = boundary_slot_q[1:0];
                3'd1: bs_at = boundary_slot_q[3:2];
                3'd2: bs_at = boundary_slot_q[5:4];
                3'd3: bs_at = boundary_slot_q[7:6];
                default: bs_at = 2'd0;
            endcase
        end
    endfunction

    // iter_busy is intentionally accepted as an interface guard for the later
    // real controller; this sequencer launches a request only after iter_done.
    wire _unused_iter_busy = iter_busy;

    always @(posedge clk) begin
        if (!rstn) begin
            st                         <= E_IDLE;
            abort_pending              <= 1'b0;
            boundary_count_q           <= 3'd0;
            boundary_j_q               <= {(4*`GP_J_W){1'b0}};
            boundary_slot_q            <= 8'd0;
            boundary_idx               <= 3'd0;
            bridge_remaining           <= 16'd0;
            current_boundary_j         <= {`GP_J_W{1'b0}};
            current_boundary_slot      <= 2'd0;
            iter_start                 <= 1'b0;
            iter_do_init               <= 1'b0;
            iter_count                 <= 16'd0;
            iter_src_slot              <= 2'd0;
            iter_dst_slot              <= 2'd0;
            iter_bridge                <= 1'b0;
            meta_clear_en              <= 1'b0;
            meta_clear_mask            <= 4'b0000;
            meta_commit_en             <= 1'b0;
            meta_commit_slot           <= 2'd0;
            meta_commit_j              <= {`GP_J_W{1'b0}};
            busy                       <= 1'b0;
            done                       <= 1'b0;
            aborted                    <= 1'b0;
            endpoint_slot              <= 2'd0;
            physical_iter_issued       <= 32'd0;
            bridge_count               <= 16'd0;
            intermediate_commit_count  <= 16'd0;
        end else begin
            iter_start      <= 1'b0;
            meta_clear_en   <= 1'b0;
            meta_commit_en  <= 1'b0;
            done            <= 1'b0;

            if (invalidate && busy)
                abort_pending <= 1'b1;

            case (st)
                E_IDLE: begin
                    busy <= 1'b0;
                    abort_pending <= 1'b0;
                    if (start) begin
                        physical_iter_issued      <= 32'd0;
                        bridge_count              <= 16'd0;
                        intermediate_commit_count <= 16'd0;
                        aborted                   <= 1'b0;

                        if (!plan_valid) begin
                            done    <= 1'b1;
                            aborted <= 1'b1;
                        end else if (plan_exact_hit) begin
                            endpoint_slot <= plan_endpoint_slot;
                            done <= 1'b1;
                        end else begin
                            busy              <= 1'b1;
                            endpoint_slot     <= plan_endpoint_slot;
                            boundary_count_q  <= plan_boundary_count;
                            boundary_j_q      <= plan_boundary_j_flat;
                            boundary_slot_q   <= plan_boundary_slot_flat;
                            boundary_idx      <= 3'd0;

                            meta_clear_en   <= 1'b1;
                            meta_clear_mask <= plan_clear_mask;

                            target_j    = plan_boundary_j_flat[0*`GP_J_W +: `GP_J_W];
                            target_slot = plan_boundary_slot_flat[1:0];

                            if (plan_source_is_anchor) begin
                                // INIT creates psi0 and the same controller call
                                // continues in-place for target_j iterations.
                                iter_do_init  <= 1'b1;
                                iter_count    <= {{(16-`GP_J_W){1'b0}}, target_j};
                                iter_src_slot <= target_slot;
                                iter_dst_slot <= target_slot;
                                iter_bridge   <= 1'b0;
                                iter_start    <= 1'b1;
                                physical_iter_issued <= {{(32-`GP_J_W){1'b0}}, target_j};
                                st <= E_WAIT_INPLACE;
                            end else if (plan_source_materialized) begin
                                delta16 = {{(16-`GP_J_W){1'b0}}, target_j} -
                                          {{(16-`GP_J_W){1'b0}}, plan_source_j};

                                if (delta16 == 16'd0) begin
                                    busy    <= 1'b0;
                                    done    <= 1'b1;
                                    aborted <= 1'b1;
                                end else if (plan_source_retain) begin
                                    // Preserve source: first iteration bridges.
                                    iter_do_init  <= 1'b0;
                                    iter_count    <= 16'd1;
                                    iter_src_slot <= plan_source_slot;
                                    iter_dst_slot <= target_slot;
                                    iter_bridge   <= 1'b1;
                                    iter_start    <= 1'b1;
                                    bridge_remaining <= delta16 - 1'b1;
                                    physical_iter_issued <= 32'd1;
                                    bridge_count <= 16'd1;
                                    st <= E_WAIT_BRIDGE;
                                end else begin
                                    // Destructive source uses its own slot as
                                    // planner-selected first work slot.
                                    iter_do_init  <= 1'b0;
                                    iter_count    <= delta16;
                                    iter_src_slot <= plan_source_slot;
                                    iter_dst_slot <= target_slot;
                                    iter_bridge   <= 1'b0;
                                    iter_start    <= 1'b1;
                                    physical_iter_issued <= delta16;
                                    st <= E_WAIT_INPLACE;
                                end
                            end else begin
                                busy    <= 1'b0;
                                done    <= 1'b1;
                                aborted <= 1'b1;
                            end
                        end
                    end
                end

                E_WAIT_BRIDGE: begin
                    if (iter_done) begin
                        if (abort_pending || invalidate) begin
                            busy    <= 1'b0;
                            done    <= 1'b1;
                            aborted <= 1'b1;
                            st      <= E_IDLE;
                        end else if (bridge_remaining != 16'd0) begin
                            // Finish target boundary in-place in bridge dst.
                            iter_do_init  <= 1'b0;
                            iter_count    <= bridge_remaining;
                            iter_src_slot <= bs_at(boundary_idx);
                            iter_dst_slot <= bs_at(boundary_idx);
                            iter_bridge   <= 1'b0;
                            iter_start    <= 1'b1;
                            physical_iter_issued <= physical_iter_issued + bridge_remaining;
                            st <= E_WAIT_INPLACE;
                        end else begin
                            // Bridge itself landed exactly on the boundary.
                            current_boundary_j    <= bj_at(boundary_idx);
                            current_boundary_slot <= bs_at(boundary_idx);
                            meta_commit_en        <= 1'b1;
                            meta_commit_slot      <= bs_at(boundary_idx);
                            meta_commit_j         <= bj_at(boundary_idx);

                            if ((boundary_idx + 1'b1) < boundary_count_q) begin
                                intermediate_commit_count <= intermediate_commit_count + 1'b1;
                                target_j    = bj_at(boundary_idx + 1'b1);
                                target_slot = bs_at(boundary_idx + 1'b1);
                                delta16 = {{(16-`GP_J_W){1'b0}}, target_j} -
                                          {{(16-`GP_J_W){1'b0}}, bj_at(boundary_idx)};

                                boundary_idx <= boundary_idx + 1'b1;
                                iter_do_init  <= 1'b0;
                                iter_count    <= 16'd1;
                                iter_src_slot <= bs_at(boundary_idx);
                                iter_dst_slot <= target_slot;
                                iter_bridge   <= 1'b1;
                                iter_start    <= 1'b1;
                                bridge_remaining <= delta16 - 1'b1;
                                physical_iter_issued <= physical_iter_issued + 1'b1;
                                bridge_count <= bridge_count + 1'b1;
                                st <= E_WAIT_BRIDGE;
                            end else begin
                                endpoint_slot <= bs_at(boundary_idx);
                                busy <= 1'b0;
                                done <= 1'b1;
                                st   <= E_IDLE;
                            end
                        end
                    end
                end

                E_WAIT_INPLACE: begin
                    if (iter_done) begin
                        if (abort_pending || invalidate) begin
                            busy    <= 1'b0;
                            done    <= 1'b1;
                            aborted <= 1'b1;
                            st      <= E_IDLE;
                        end else begin
                            current_boundary_j    <= bj_at(boundary_idx);
                            current_boundary_slot <= bs_at(boundary_idx);
                            meta_commit_en        <= 1'b1;
                            meta_commit_slot      <= bs_at(boundary_idx);
                            meta_commit_j         <= bj_at(boundary_idx);

                            if ((boundary_idx + 1'b1) < boundary_count_q) begin
                                intermediate_commit_count <= intermediate_commit_count + 1'b1;
                                target_j    = bj_at(boundary_idx + 1'b1);
                                target_slot = bs_at(boundary_idx + 1'b1);
                                delta16 = {{(16-`GP_J_W){1'b0}}, target_j} -
                                          {{(16-`GP_J_W){1'b0}}, bj_at(boundary_idx)};

                                boundary_idx <= boundary_idx + 1'b1;
                                iter_do_init  <= 1'b0;
                                iter_count    <= 16'd1;
                                iter_src_slot <= bs_at(boundary_idx);
                                iter_dst_slot <= target_slot;
                                iter_bridge   <= 1'b1;
                                iter_start    <= 1'b1;
                                bridge_remaining <= delta16 - 1'b1;
                                physical_iter_issued <= physical_iter_issued + 1'b1;
                                bridge_count <= bridge_count + 1'b1;
                                st <= E_WAIT_BRIDGE;
                            end else begin
                                endpoint_slot <= bs_at(boundary_idx);
                                busy <= 1'b0;
                                done <= 1'b1;
                                st   <= E_IDLE;
                            end
                        end
                    end
                end

                default: begin
                    st      <= E_IDLE;
                    busy    <= 1'b0;
                    done    <= 1'b1;
                    aborted <= 1'b1;
                end
            endcase
        end
    end
endmodule

//------------------------------------------------------------------------------
// Segment-level physical routing contract for later grover_ctrl_fsm adapter.
// bridge=1 means only PASS1 reads the preserved src; PASS2 must consume the
// Oracle state already written into dst by PASS1.
//------------------------------------------------------------------------------
module grover_ckpt_segment_router (
    input  wire                         pass1_active,
    input  wire                         bridge,
    input  wire [1:0]                   src_slot,
    input  wire [1:0]                   dst_slot,
    output wire [1:0]                   amp_rd_slot,
    output wire [1:0]                   amp_wr_slot
);
    assign amp_rd_slot = (bridge && pass1_active) ? src_slot : dst_slot;
    assign amp_wr_slot = dst_slot;
endmodule

//==============================================================================
// E2 intra-iteration checkpoint physical memory extensions (2026-09-06)
//==============================================================================
module grover_amp_mem_packed_tdp_e2 (
    input  wire                              clk,

    input  wire                              a_en,
    input  wire                              a_we,
    input  wire [`GP_ROW_W-1:0]              a_row,
    input  wire [`GP_P*`GP_AMP_W-1:0]        a_wdata,
    output wire [`GP_P*`GP_AMP_W-1:0]        a_rdata,

    input  wire                              b_en,
    input  wire                              b_we,
    input  wire [`GP_ROW_W-1:0]              b_row,
    input  wire [`GP_P*`GP_AMP_W-1:0]        b_wdata,
    output wire [`GP_P*`GP_AMP_W-1:0]        b_rdata
);
    (* ram_style = "block" *) reg [68:0] mem0  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem1  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem2  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem3  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem4  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem5  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem6  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem7  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem8  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [68:0] mem9  [0:`GP_ROWS-1];
    (* ram_style = "block" *) reg [45:0] mem10 [0:`GP_ROWS-1];

    reg [68:0] aq0,aq1,aq2,aq3,aq4,aq5,aq6,aq7,aq8,aq9;
    reg [45:0] aq10;
    reg [68:0] bq0,bq1,bq2,bq3,bq4,bq5,bq6,bq7,bq8,bq9;
    reg [45:0] bq10;

    always @(posedge clk) begin
        if (a_en) begin
            if (a_we) begin
                mem0[a_row]  <= a_wdata[68:0];
                mem1[a_row]  <= a_wdata[137:69];
                mem2[a_row]  <= a_wdata[206:138];
                mem3[a_row]  <= a_wdata[275:207];
                mem4[a_row]  <= a_wdata[344:276];
                mem5[a_row]  <= a_wdata[413:345];
                mem6[a_row]  <= a_wdata[482:414];
                mem7[a_row]  <= a_wdata[551:483];
                mem8[a_row]  <= a_wdata[620:552];
                mem9[a_row]  <= a_wdata[689:621];
                mem10[a_row] <= a_wdata[735:690];
            end
            aq0<=mem0[a_row]; aq1<=mem1[a_row]; aq2<=mem2[a_row];
            aq3<=mem3[a_row]; aq4<=mem4[a_row]; aq5<=mem5[a_row];
            aq6<=mem6[a_row]; aq7<=mem7[a_row]; aq8<=mem8[a_row];
            aq9<=mem9[a_row]; aq10<=mem10[a_row];
        end
    end

    always @(posedge clk) begin
        if (b_en) begin
            if (b_we) begin
                mem0[b_row]  <= b_wdata[68:0];
                mem1[b_row]  <= b_wdata[137:69];
                mem2[b_row]  <= b_wdata[206:138];
                mem3[b_row]  <= b_wdata[275:207];
                mem4[b_row]  <= b_wdata[344:276];
                mem5[b_row]  <= b_wdata[413:345];
                mem6[b_row]  <= b_wdata[482:414];
                mem7[b_row]  <= b_wdata[551:483];
                mem8[b_row]  <= b_wdata[620:552];
                mem9[b_row]  <= b_wdata[689:621];
                mem10[b_row] <= b_wdata[735:690];
            end
            bq0<=mem0[b_row]; bq1<=mem1[b_row]; bq2<=mem2[b_row];
            bq3<=mem3[b_row]; bq4<=mem4[b_row]; bq5<=mem5[b_row];
            bq6<=mem6[b_row]; bq7<=mem7[b_row]; bq8<=mem8[b_row];
            bq9<=mem9[b_row]; bq10<=mem10[b_row];
        end
    end

    assign a_rdata[68:0]=aq0; assign a_rdata[137:69]=aq1;
    assign a_rdata[206:138]=aq2; assign a_rdata[275:207]=aq3;
    assign a_rdata[344:276]=aq4; assign a_rdata[413:345]=aq5;
    assign a_rdata[482:414]=aq6; assign a_rdata[551:483]=aq7;
    assign a_rdata[620:552]=aq8; assign a_rdata[689:621]=aq9;
    assign a_rdata[735:690]=aq10;

    assign b_rdata[68:0]=bq0; assign b_rdata[137:69]=bq1;
    assign b_rdata[206:138]=bq2; assign b_rdata[275:207]=bq3;
    assign b_rdata[344:276]=bq4; assign b_rdata[413:345]=bq5;
    assign b_rdata[482:414]=bq6; assign b_rdata[551:483]=bq7;
    assign b_rdata[620:552]=bq8; assign b_rdata[689:621]=bq9;
    assign b_rdata[735:690]=bq10;
endmodule

//------------------------------------------------------------------------------
// Four K4 checkpoint slots with pair access for E2 and legacy single-row read
// for Born measurement / debug scanning.
// Pair read keeps the frozen checkpoint wrapper's extra registered slot mux,
// so request->pair_valid latency is two clocks.
//------------------------------------------------------------------------------
module grover_ckpt_mem_tdp_e2 #(
    parameter integer CKPT_K = 4
) (
    input wire clk,

    input wire [1:0] pair_rd_slot,
    input wire [7:0] pair_rd_index,
    input wire pair_rd_en,
    output reg [`GP_P*`GP_AMP_W-1:0] pair_rd_even,
    output reg [`GP_P*`GP_AMP_W-1:0] pair_rd_odd,
    output reg pair_rd_valid,

    input wire [1:0] pair_wr_slot,
    input wire [7:0] pair_wr_index,
    input wire pair_wr_en,
    input wire [`GP_P*`GP_AMP_W-1:0] pair_wr_even,
    input wire [`GP_P*`GP_AMP_W-1:0] pair_wr_odd,

    input wire [1:0] single_rd_slot,
    input wire [`GP_ROW_W-1:0] single_rd_row,
    input wire single_rd_en,
    output reg [`GP_P*`GP_AMP_W-1:0] single_rd_amp,
    output reg single_rd_valid
);
    localparam integer W=`GP_P*`GP_AMP_W;
    wire [`GP_ROW_W-1:0] even_row={pair_rd_index,1'b0};
    wire [`GP_ROW_W-1:0] odd_row ={pair_rd_index,1'b1};
    wire [`GP_ROW_W-1:0] weven_row={pair_wr_index,1'b0};
    wire [`GP_ROW_W-1:0] wodd_row ={pair_wr_index,1'b1};

    wire [W-1:0] qa0,qb0,qa1,qb1,qa2,qb2,qa3,qb3;

    wire wr0=pair_wr_en&&(pair_wr_slot==2'd0);
    wire wr1=pair_wr_en&&(pair_wr_slot==2'd1);
    wire wr2=pair_wr_en&&(pair_wr_slot==2'd2);
    wire wr3=pair_wr_en&&(pair_wr_slot==2'd3)&&(CKPT_K==4);

    // Single-read mode is mutually exclusive with E2 pair compute by contract.
    wire use_single=single_rd_en;
    wire [`GP_ROW_W-1:0] a_read_row=use_single?single_rd_row:even_row;
    wire a_read_en=use_single|pair_rd_en;
    wire b_read_en=(!use_single)&pair_rd_en;

`define E2_SLOT(INST, WRSEL, QA, QB) \
    grover_amp_mem_packed_tdp_e2 INST ( \
      .clk(clk), \
      .a_en(a_read_en | WRSEL), .a_we(WRSEL), \
      .a_row(WRSEL ? weven_row : a_read_row), .a_wdata(pair_wr_even), .a_rdata(QA), \
      .b_en(b_read_en | WRSEL), .b_we(WRSEL), \
      .b_row(WRSEL ? wodd_row : odd_row), .b_wdata(pair_wr_odd), .b_rdata(QB) );

    `E2_SLOT(u_s0,wr0,qa0,qb0)
    `E2_SLOT(u_s1,wr1,qa1,qb1)
    `E2_SLOT(u_s2,wr2,qa2,qb2)
    generate if (CKPT_K==4) begin: g_s3
        `E2_SLOT(u_s3,wr3,qa3,qb3)
    end else begin: g_no_s3
        assign qa3={W{1'b0}}; assign qb3={W{1'b0}};
    end endgenerate
`undef E2_SLOT

    reg [1:0] pair_slot_d;
    reg pair_v_d;
    reg [1:0] single_slot_d;
    reg single_v_d;

    wire [W-1:0] pair_sel_a=(pair_slot_d==0)?qa0:(pair_slot_d==1)?qa1:(pair_slot_d==2)?qa2:qa3;
    wire [W-1:0] pair_sel_b=(pair_slot_d==0)?qb0:(pair_slot_d==1)?qb1:(pair_slot_d==2)?qb2:qb3;
    wire [W-1:0] single_sel=(single_slot_d==0)?qa0:(single_slot_d==1)?qa1:(single_slot_d==2)?qa2:qa3;

    always @(posedge clk) begin
        if (pair_rd_en) pair_slot_d<=pair_rd_slot;
        pair_v_d<=pair_rd_en;
        if (pair_v_d) begin pair_rd_even<=pair_sel_a; pair_rd_odd<=pair_sel_b; end
        pair_rd_valid<=pair_v_d;

        if (single_rd_en) single_slot_d<=single_rd_slot;
        single_v_d<=single_rd_en;
        if (single_v_d) single_rd_amp<=single_sel;
        single_rd_valid<=single_v_d;
    end
endmodule

//------------------------------------------------------------------------------
// One extra full-state Oracle scratch.  Pair-only true-dual-port access.
// PASS1 writes two rows/cycle; PASS2 reads two rows/cycle.
//------------------------------------------------------------------------------
module grover_e2_oracle_scratch_tdp (
    input wire clk,
    input wire [7:0] pair_rd_index,
    input wire pair_rd_en,
    output wire [`GP_P*`GP_AMP_W-1:0] pair_rd_even,
    output wire [`GP_P*`GP_AMP_W-1:0] pair_rd_odd,
    input wire [7:0] pair_wr_index,
    input wire pair_wr_en,
    input wire [`GP_P*`GP_AMP_W-1:0] pair_wr_even,
    input wire [`GP_P*`GP_AMP_W-1:0] pair_wr_odd
);
    grover_amp_mem_packed_tdp_e2 u_mem(
      .clk(clk),
      .a_en(pair_rd_en|pair_wr_en), .a_we(pair_wr_en),
      .a_row(pair_wr_en?{pair_wr_index,1'b0}:{pair_rd_index,1'b0}),
      .a_wdata(pair_wr_even), .a_rdata(pair_rd_even),
      .b_en(pair_rd_en|pair_wr_en), .b_we(pair_wr_en),
      .b_row(pair_wr_en?{pair_wr_index,1'b1}:{pair_rd_index,1'b1}),
      .b_wdata(pair_wr_odd), .b_rdata(pair_rd_odd));
endmodule

//==============================================================================
// Active E4 intra-iteration checkpoint storage (2026-09-06)
//
// Four consecutive logical rows are processed per issue.  The active design
// uses four interleaved row-phase banks; legacy split-half/banked E4 variants
// and the old full-state E4 Oracle scratch have been removed.
//==============================================================================
//==============================================================================
// BRAM-efficient E4 checkpoint storage (2026-09-06)
//
// Key idea:
//   Do NOT build four independent wide memories inside every checkpoint slot.
//   That leaves each BRAM only 1/4 full and causes severe RAMB18/RAMB36
//   over-utilization.  Instead, transpose {slot,row_mod4} into the address/bank
//   organization:
//
//     phase bank 0 stores logical rows 4*q+0 for all four K4 slots
//     phase bank 1 stores logical rows 4*q+1 for all four K4 slots
//     phase bank 2 stores logical rows 4*q+2 for all four K4 slots
//     phase bank 3 stores logical rows 4*q+3 for all four K4 slots
//
//   address = {slot[1:0], quad_index[6:0]} => exactly 512 deep.
//
// Each phase bank is therefore the already-proven 512x736 packed SDP memory
// (11 RAMB36E1), so all K4 checkpoints together remain 4*11 = 44 BRAM36
// instead of exploding to ~176+ BRAM36-equivalent resources.
//
// PASS1/PASS2 may read four rows/cycle while simultaneously writing the
// previous quad through the independent write port of each phase bank.
//==============================================================================
module grover_ckpt_mem_interleaved_e4 #(
    parameter integer CKPT_K = 4
) (
    input  wire                              clk,

    input  wire [1:0]                        quad_rd_slot,
    input  wire [6:0]                        quad_rd_index,
    input  wire                              quad_rd_en,
    output reg  [`GP_P*`GP_AMP_W-1:0]        quad_rd0,
    output reg  [`GP_P*`GP_AMP_W-1:0]        quad_rd1,
    output reg  [`GP_P*`GP_AMP_W-1:0]        quad_rd2,
    output reg  [`GP_P*`GP_AMP_W-1:0]        quad_rd3,
    output reg                               quad_rd_valid,

    input  wire [1:0]                        quad_wr_slot,
    input  wire [6:0]                        quad_wr_index,
    input  wire                              quad_wr_en,
    input  wire [`GP_P*`GP_AMP_W-1:0]        quad_wr0,
    input  wire [`GP_P*`GP_AMP_W-1:0]        quad_wr1,
    input  wire [`GP_P*`GP_AMP_W-1:0]        quad_wr2,
    input  wire [`GP_P*`GP_AMP_W-1:0]        quad_wr3,

    input  wire [1:0]                        single_rd_slot,
    input  wire [`GP_ROW_W-1:0]              single_rd_row,
    input  wire                              single_rd_en,
    output reg  [`GP_P*`GP_AMP_W-1:0]        single_rd_amp,
    output reg                               single_rd_valid
);
    localparam integer W = `GP_P * `GP_AMP_W;

    // Keep the 2-bit physical slot address space so the same interleaved
    // organization supports CKPT_K <= 4 (current E4 experiments use K=3,
    // while the frozen publication baseline uses K=4).
    wire [`GP_ROW_W-1:0] quad_raddr = {quad_rd_slot, quad_rd_index};
    wire [`GP_ROW_W-1:0] quad_waddr = {quad_wr_slot, quad_wr_index};
    wire [`GP_ROW_W-1:0] single_raddr = {single_rd_slot, single_rd_row[`GP_ROW_W-1:2]};

    wire use_single = single_rd_en;
    wire rd_en = quad_rd_en | single_rd_en;
    wire [`GP_ROW_W-1:0] rd_addr = use_single ? single_raddr : quad_raddr;

    wire [W-1:0] p0_q, p1_q, p2_q, p3_q;

    // Four row-phase banks.  Each is exactly 512x736 and therefore preserves
    // the original efficient 11-RAMB36 packed mapping.
    grover_amp_mem_packed u_phase0 (
        .clk(clk), .rd_row(rd_addr), .rd_en(rd_en), .rd_amp(p0_q),
        .wr_row(quad_waddr), .wr_en(quad_wr_en), .wr_amp(quad_wr0)
    );
    grover_amp_mem_packed u_phase1 (
        .clk(clk), .rd_row(rd_addr), .rd_en(rd_en), .rd_amp(p1_q),
        .wr_row(quad_waddr), .wr_en(quad_wr_en), .wr_amp(quad_wr1)
    );
    grover_amp_mem_packed u_phase2 (
        .clk(clk), .rd_row(rd_addr), .rd_en(rd_en), .rd_amp(p2_q),
        .wr_row(quad_waddr), .wr_en(quad_wr_en), .wr_amp(quad_wr2)
    );
    grover_amp_mem_packed u_phase3 (
        .clk(clk), .rd_row(rd_addr), .rd_en(rd_en), .rd_amp(p3_q),
        .wr_row(quad_waddr), .wr_en(quad_wr_en), .wr_amp(quad_wr3)
    );

    reg quad_v_d;
    reg single_v_d;
    reg [1:0] single_phase_d;

    always @(posedge clk) begin
        quad_v_d <= quad_rd_en;
        single_v_d <= single_rd_en;
        if (single_rd_en)
            single_phase_d <= single_rd_row[1:0];

        // Explicit output register preserves the legacy checkpoint read
        // contract: request edge -> packed BRAM -> wrapper register = 2 cycles.
        if (quad_v_d) begin
            quad_rd0 <= p0_q;
            quad_rd1 <= p1_q;
            quad_rd2 <= p2_q;
            quad_rd3 <= p3_q;
        end
        quad_rd_valid <= quad_v_d;

        if (single_v_d) begin
            case (single_phase_d)
                2'd0: single_rd_amp <= p0_q;
                2'd1: single_rd_amp <= p1_q;
                2'd2: single_rd_amp <= p2_q;
                default: single_rd_amp <= p3_q;
            endcase
        end
        single_rd_valid <= single_v_d;
    end

    wire _unused_ckpt_k_guard = (CKPT_K == 4);
endmodule
