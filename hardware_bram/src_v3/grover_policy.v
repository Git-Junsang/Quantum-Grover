//==============================================================================
// grover_policy.v
// LPSoC BBHT/Grover checkpoint policy RTL -- Phase 5 policy/speculation bundle
// Date: 2026-08-30
// Split mask-driven action compaction from canonical sorting;
//             evaluate Shadow-J restart from registered context before draw.
//
// Functional scope of this file
//   1) grover_ckpt_policy_memo
//      - five explicit 2,048 x 18-bit synchronous block-RAM memo banks (5 RAMB36 target)
//      - future-only memo semantic: 8 future stages, 10-bit cost + 8-bit epoch
//   2) grover_ckpt_policy_rolling
//      - LEGACY MODULE NAME RETAINED for existing RVX/OOC wrappers
//      - exact restricted-B Rolling H=7 policy for CKPT_K=4
//      - current request + 7 deterministic future requests (8 request window)
//      - closest-predecessor source only
//      - endpoint mandatory, request-pool intermediates only
//      - old checkpoints retained maximally subject to K=4 capacity
//      - corrected root tie-break:
//          (total DP physical cost, segment_count, canonical sorted S')
//      - top-down DFS with memo and a one-action/cycle hit pipeline
//      - active-frame + active-pending mirrors remove variable-index stack muxes
//      - staged PREP filter/pack pipeline with cached request values
//      - action select, rank/address, and BRAM access are separated by registered boundaries
//      - fixed-depth 4-way sorting networks on registered request/value paths
//      - registered memo-address stage removes combinadic rank/address logic from RAMB36 pins
//      - non-root memo-return cost is registered before best-cost add/compare (hwfix18)
//      - eligibility predicates are factored from the predecessor max-tree
//      - qualified predecessor candidates are registered before the max-tree
//      - raw-value, sorted-value and root-candidate pipelines isolate universe
//        lookup / sorting / segment count / tie-break across separate cycles
//      - ACTION_LIMIT=0 means exact/unlimited baseline
//   3) grover_shadow_j
//      - bit-exact failure-continuation future-J generator for jump7 J stream
//      - never mutates the real BBHT J state; operates on an input state copy
//   4) grover_ckpt_plan_fifo
//      - small plan FIFO with tags/debug counters for later autonomous integration
//
// IMPORTANT SEMANTIC FREEZE FOR PHASE 5
//   Memo is FUTURE-ONLY, not root-inclusive.
//     memo V_i(S), i=0..7  <=>  future request j_{i+1}..j_8
//   Maximum memo cost = 8 * 127 = 1016, therefore 10 cost bits are sufficient.
//   Root adds the current immediate cost and is reported on 11 bits.
//   The saved bit is reassigned to epoch: {epoch[7:0], cost[9:0]} = 18 bits.
//
// This file deliberately does NOT modify Main-IP RTL yet.  Phase 4B remains the
// integration anchor while this policy/speculation bundle is verified standalone.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

//------------------------------------------------------------------------------
// 8-stage x 1093-rank future-only memo = 8744 logical entries.
// A padded 10,240x18 synchronous simple-dual-port array maps naturally to five
// RAMB36 memories (2,048x18 each) while only logical addresses 0..8743 are used.
//------------------------------------------------------------------------------
module grover_ckpt_policy_memo (
    input  wire         clk,

    input  wire         rd_en,
    input  wire [13:0]  rd_addr,
    output reg  [17:0]  rd_data,

    input  wire         wr_en,
    input  wire [13:0]  wr_addr,
    input  wire [17:0]  wr_data,

    input  wire         clear_en,
    input  wire [13:0]  clear_addr
);
    // Five explicit 2,048x18 banks avoid non-power-of-two depth rounding.
    // Architectural addresses 0..8743 occupy banks 0..4.
    (* ram_style = "block" *) reg [17:0] mem0 [0:2047];
    (* ram_style = "block" *) reg [17:0] mem1 [0:2047];
    (* ram_style = "block" *) reg [17:0] mem2 [0:2047];
    (* ram_style = "block" *) reg [17:0] mem3 [0:2047];

    reg [17:0] q0, q1, q2, q3;
    reg [2:0]  rd_bank_q;

    wire [13:0] eff_wr_addr = clear_en ? clear_addr : wr_addr;
    wire [17:0] eff_wr_data = clear_en ? 18'd0 : wr_data;
    wire        eff_wr_en   = clear_en | wr_en;
    wire [2:0]  rd_bank     = rd_addr[13:11];
    wire [2:0]  wr_bank     = eff_wr_addr[13:11];
    wire [10:0] rd_row      = rd_addr[10:0];
    wire [10:0] wr_row      = eff_wr_addr[10:0];

    always @(posedge clk) begin
        if (rd_en) begin
            // Read all banks at the selected row and register the bank tag.
            // This removes address-dependent bank decode from the RAMB36 EN path.
            rd_bank_q <= rd_bank;
            q0 <= mem0[rd_row];
            q1 <= mem1[rd_row];
            q2 <= mem2[rd_row];
            q3 <= mem3[rd_row];
        end
        if (eff_wr_en) begin
            case (wr_bank)
                3'd0: mem0[wr_row] <= eff_wr_data;
                3'd1: mem1[wr_row] <= eff_wr_data;
                3'd2: mem2[wr_row] <= eff_wr_data;
                3'd3: mem3[wr_row] <= eff_wr_data;
                default: mem3[wr_row] <= eff_wr_data;
            endcase
        end
    end

    always @* begin
        case (rd_bank_q)
            3'd0: rd_data = q0;
            3'd1: rd_data = q1;
            3'd2: rd_data = q2;
            3'd3: rd_data = q3;
            default: rd_data = q3;
        endcase
    end
endmodule

//------------------------------------------------------------------------------
// Exact K4 / restricted-B / Rolling H7 policy (legacy module name retained).
//
// Inputs:
//   slot_valid/slot_j_flat : current physical metadata; slot numbers do not
//                            enter the logical DP state.
//   j_window_flat          : physical interface remains 9 x 7-bit for compatibility.
//                            H4 consumes slices 0..4 only: current + 4 future.
//                            Slices 5..8 are ignored by policy semantics.
//                            little-slice order: [i*7 +: 7].
//
// Outputs are logical only.  grover_ckpt_planner remains responsible for
// deterministic physical slot allocation.
//------------------------------------------------------------------------------
module grover_ckpt_policy_rolling #(
    parameter integer ACTION_LIMIT = 0
) (
    input  wire                         clk,
    input  wire                         rstn,
    input  wire                         start,

    input  wire [3:0]                   slot_valid,
    input  wire [4*`GP_J_W-1:0]         slot_j_flat,
    input  wire [9*`GP_J_W-1:0]         j_window_flat,

    output reg                          busy,
    output reg                          done,
    output reg                          policy_error,

    output reg  [`GP_J_W-1:0]           source_j,
    output reg  [2:0]                   next_count,
    output reg  [4*`GP_J_W-1:0]         next_j_flat,
    output reg  [10:0]                  root_cost,
    output reg  [2:0]                   root_segment_count,

    output reg  [31:0]                  policy_cycles_last,
    output reg  [31:0]                  policy_actions_last,
    output reg  [31:0]                  policy_memo_hit_last,
    output reg  [31:0]                  policy_memo_miss_last,
    output reg  [31:0]                  policy_cycles_total,
    output reg  [31:0]                  policy_actions_total,
    output reg  [31:0]                  policy_max_latency,
    output reg  [7:0]                   policy_epoch
);
    localparam integer H_FUTURE    = 4;
    localparam integer WINDOW_LEN  = 5;
    localparam integer U_MAX       = 9;    // K4 + 5 requests (current + 4 future)
    localparam integer STATE_RANKS = 1093; // legacy-compatible memo physical sizing
    localparam integer MEM_ENTRIES = 4372; // 4 future stages x 1093 ranks
    localparam [10:0] INF_COST     = 11'h7FF;

    // K4/H6 conversion note: j_window_flat keeps the legacy 9-slice bus so the
    // RVX integration ports do not change.  All H6 semantic loops/build logic
    // stop at slice 7; slice 8 must not influence source/action selection.

    // -------------------------------------------------------------------------
    // Small constant-combination helpers.
    // -------------------------------------------------------------------------
    function [10:0] choose13;
        input [3:0] n;
        input [2:0] k;
        begin
            choose13 = 11'd0;
            if (k == 0)
                choose13 = 11'd1;
            else begin
                case ({n,k})
                    {4'd1,3'd1}: choose13=11'd1;
                    {4'd2,3'd1}: choose13=11'd2;
                    {4'd2,3'd2}: choose13=11'd1;
                    {4'd3,3'd1}: choose13=11'd3;
                    {4'd3,3'd2}: choose13=11'd3;
                    {4'd3,3'd3}: choose13=11'd1;
                    {4'd4,3'd1}: choose13=11'd4;
                    {4'd4,3'd2}: choose13=11'd6;
                    {4'd4,3'd3}: choose13=11'd4;
                    {4'd4,3'd4}: choose13=11'd1;
                    {4'd5,3'd1}: choose13=11'd5;
                    {4'd5,3'd2}: choose13=11'd10;
                    {4'd5,3'd3}: choose13=11'd10;
                    {4'd5,3'd4}: choose13=11'd5;
                    {4'd6,3'd1}: choose13=11'd6;
                    {4'd6,3'd2}: choose13=11'd15;
                    {4'd6,3'd3}: choose13=11'd20;
                    {4'd6,3'd4}: choose13=11'd15;
                    {4'd7,3'd1}: choose13=11'd7;
                    {4'd7,3'd2}: choose13=11'd21;
                    {4'd7,3'd3}: choose13=11'd35;
                    {4'd7,3'd4}: choose13=11'd35;
                    {4'd8,3'd1}: choose13=11'd8;
                    {4'd8,3'd2}: choose13=11'd28;
                    {4'd8,3'd3}: choose13=11'd56;
                    {4'd8,3'd4}: choose13=11'd70;
                    {4'd9,3'd1}: choose13=11'd9;
                    {4'd9,3'd2}: choose13=11'd36;
                    {4'd9,3'd3}: choose13=11'd84;
                    {4'd9,3'd4}: choose13=11'd126;
                    {4'd10,3'd1}: choose13=11'd10;
                    {4'd10,3'd2}: choose13=11'd45;
                    {4'd10,3'd3}: choose13=11'd120;
                    {4'd10,3'd4}: choose13=11'd210;
                    {4'd11,3'd1}: choose13=11'd11;
                    {4'd11,3'd2}: choose13=11'd55;
                    {4'd11,3'd3}: choose13=11'd165;
                    {4'd11,3'd4}: choose13=11'd330;
                    {4'd12,3'd1}: choose13=11'd12;
                    {4'd12,3'd2}: choose13=11'd66;
                    {4'd12,3'd3}: choose13=11'd220;
                    {4'd12,3'd4}: choose13=11'd495;
                    {4'd13,3'd1}: choose13=11'd13;
                    {4'd13,3'd2}: choose13=11'd78;
                    {4'd13,3'd3}: choose13=11'd286;
                    {4'd13,3'd4}: choose13=11'd715;
                    default: choose13=11'd0;
                endcase
            end
        end
    endfunction

    function [8:0] comb_mask9;
        input [3:0] n;
        input [1:0] k;
        input [6:0] ord;
        integer p;
        integer rem;
        integer need;
        integer c;
        reg [8:0] m;
        begin
            m = 9'd0;
            rem = ord;
            need = k;
            for (p=0; p<9; p=p+1) begin
                if ((p < n) && (need > 0)) begin
                    c = choose13(n-p-1, need-1);
                    if (rem < c) begin
                        m[p] = 1'b1;
                        need = need - 1;
                    end else begin
                        rem = rem - c;
                    end
                end
            end
            comb_mask9 = m;
        end
    endfunction

    function [8:0] first_comb9;
        input [2:0] k;
        begin
            case (k)
                3'd0: first_comb9 = 9'b000000000;
                3'd1: first_comb9 = 9'b000000001;
                3'd2: first_comb9 = 9'b000000011;
                default: first_comb9 = 9'b000000111;
            endcase
        end
    endfunction

    function comb_has_next9;
        input [8:0] mask;
        input [3:0] n;
        input [2:0] k;
        integer q;
        integer seen;
        integer p0,p1,p2;
        begin
            p0=0; p1=0; p2=0; seen=0;
            for (q=0; q<9; q=q+1) begin
                if (mask[q]) begin
                    if (seen==0) p0=q;
                    else if (seen==1) p1=q;
                    else if (seen==2) p2=q;
                    seen=seen+1;
                end
            end
            case (k)
                3'd0: comb_has_next9 = 1'b0;
                3'd1: comb_has_next9 = (p0 + 1 < n);
                3'd2: comb_has_next9 = ((p1 + 1 < n) || (p0 + 2 < n));
                default: comb_has_next9 = ((p2 + 1 < n) || (p1 + 2 < n) || (p0 + 3 < n));
            endcase
        end
    endfunction

    function [8:0] next_comb9;
        input [8:0] mask;
        input [3:0] n;
        input [2:0] k;
        integer q;
        integer seen;
        integer p0,p1,p2;
        reg [8:0] m;
        begin
            p0=0; p1=0; p2=0; seen=0;
            for (q=0; q<9; q=q+1) begin
                if (mask[q]) begin
                    if (seen==0) p0=q;
                    else if (seen==1) p1=q;
                    else if (seen==2) p2=q;
                    seen=seen+1;
                end
            end
            m = mask;
            case (k)
                3'd1: begin
                    m = 9'd0;
                    if (p0 + 1 < n) m[p0+1] = 1'b1;
                end
                3'd2: begin
                    m = 9'd0;
                    if (p1 + 1 < n) begin
                        m[p0] = 1'b1;
                        m[p1+1] = 1'b1;
                    end else begin
                        m[p0+1] = 1'b1;
                        m[p0+2] = 1'b1;
                    end
                end
                3'd3: begin
                    m = 9'd0;
                    if (p2 + 1 < n) begin
                        m[p0] = 1'b1; m[p1] = 1'b1; m[p2+1] = 1'b1;
                    end else if (p1 + 2 < n) begin
                        m[p0] = 1'b1; m[p1+1] = 1'b1; m[p1+2] = 1'b1;
                    end else begin
                        m[p0+1] = 1'b1; m[p0+2] = 1'b1; m[p0+3] = 1'b1;
                    end
                end
                default: m = 9'd0;
            endcase
            next_comb9 = m;
        end
    endfunction

    // Specialized combinadic tables used only by the hot memo-rank path.
    // Keeping k constant removes the generic {n,k} decoder from this path.
    function [10:0] comb_c2;
        input [3:0] n;
        begin
            case (n)
                4'd2: comb_c2=11'd1;   4'd3: comb_c2=11'd3;
                4'd4: comb_c2=11'd6;   4'd5: comb_c2=11'd10;
                4'd6: comb_c2=11'd15;  4'd7: comb_c2=11'd21;
                4'd8: comb_c2=11'd28;  4'd9: comb_c2=11'd36;
                4'd10: comb_c2=11'd45; 4'd11: comb_c2=11'd55;
                4'd12: comb_c2=11'd66; 4'd13: comb_c2=11'd78;
                default: comb_c2=11'd0;
            endcase
        end
    endfunction

    function [10:0] comb_c3;
        input [3:0] n;
        begin
            case (n)
                4'd3: comb_c3=11'd1;    4'd4: comb_c3=11'd4;
                4'd5: comb_c3=11'd10;   4'd6: comb_c3=11'd20;
                4'd7: comb_c3=11'd35;   4'd8: comb_c3=11'd56;
                4'd9: comb_c3=11'd84;   4'd10: comb_c3=11'd120;
                4'd11: comb_c3=11'd165; 4'd12: comb_c3=11'd220;
                4'd13: comb_c3=11'd286;
                default: comb_c3=11'd0;
            endcase
        end
    endfunction

    function [10:0] comb_c4;
        input [3:0] n;
        begin
            case (n)
                4'd4: comb_c4=11'd1;    4'd5: comb_c4=11'd5;
                4'd6: comb_c4=11'd15;   4'd7: comb_c4=11'd35;
                4'd8: comb_c4=11'd70;   4'd9: comb_c4=11'd126;
                4'd10: comb_c4=11'd210; 4'd11: comb_c4=11'd330;
                4'd12: comb_c4=11'd495; 4'd13: comb_c4=11'd715;
                default: comb_c4=11'd0;
            endcase
        end
    endfunction

    function [10:0] rank_state;
        input [2:0] cnt;
        input [3:0] i0;
        input [3:0] i1;
        input [3:0] i2;
        input [3:0] i3;
        reg [10:0] s01;
        reg [10:0] s23;
        begin
            case (cnt)
                3'd0: rank_state = 11'd0;
                3'd1: rank_state = 11'd1 + {7'd0,i0};
                3'd2: rank_state = 11'd14 + {7'd0,i0} + comb_c2(i1);
                3'd3: begin
                    s01 = 11'd92 + {7'd0,i0};
                    s23 = comb_c2(i1) + comb_c3(i2);
                    rank_state = s01 + s23;
                end
                default: begin
                    s01 = 11'd378 + {7'd0,i0} + comb_c2(i1);
                    s23 = comb_c3(i2) + comb_c4(i3);
                    rank_state = s01 + s23;
                end
            endcase
        end
    endfunction

    function [13:0] memo_addr_of;
        input [2:0] stage;
        input [10:0] rank;
        reg [13:0] base;
        begin
            case (stage)
                3'd0: base = 14'd0;
                3'd1: base = 14'd1093;
                3'd2: base = 14'd2186;
                3'd3: base = 14'd3279;
                3'd4: base = 14'd4372;
                3'd5: base = 14'd5465;
                3'd6: base = 14'd6558;
                default: base = 14'd7651;
            endcase
            memo_addr_of = base + rank;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Latched solve input, per-solve local universe, request-local IDs.
    // The request-only pool is deduplicated once during ST_BUILD.  That removes
    // the old 9x9 dedup/range scan from every action issue and is the main
    // timing-oriented refactor in this revision.
    // -------------------------------------------------------------------------
    reg [3:0] in_slot_valid;
    reg [4*`GP_J_W-1:0] in_slot_j_flat;
    reg [9*`GP_J_W-1:0] in_window_flat;

    reg [6:0] univ_val [0:12];
    reg [3:0] univ_count;
    reg [3:0] req_id [0:8];
    reg [6:0] req_val [0:8];
    reg [3:0] req_pool_id [0:8];
    reg [6:0] req_pool_val [0:8];
    reg [3:0] req_pool_count;

    reg [4:0] build_idx;
    reg [2:0] root_init_count;
    reg [3:0] root_init_id0, root_init_id1, root_init_id2, root_init_id3;

    // BUILD is deliberately split into capture -> resolve -> commit.  BUILD is
    // solve setup, not the hot DP action loop, so the extra setup cycles are a
    // small throughput cost but remove the long build_idx/input-mux/dedup/write
    // enable path from the 100-MHz critical set.
    reg       build_sel_valid;
    reg [6:0] build_sel_value;
    reg       build_raw_valid_q;
    reg [6:0] build_raw_value_q;
    reg [4:0] build_raw_idx_q;

    reg       raw_found;
    reg [3:0] raw_found_id;
    reg       req_pool_found;
    reg [3:0] raw_resolved_id;
    reg       build_found_q;
    reg [3:0] build_found_id_q;
    reg       build_req_pool_found_q;
    reg [3:0] build_resolved_id_q;
    integer bi;
    wire build_commit_abort = build_raw_valid_q &&
                              (((build_raw_idx_q < 4) && build_found_q) ||
                               (!build_found_q && (univ_count >= U_MAX)));

    // Stage 1 input selection.  Only the selected value is registered here.
    always @* begin
        build_sel_valid = 1'b0;
        build_sel_value = 7'd0;
        if (build_idx < 4) begin
            build_sel_valid = in_slot_valid[build_idx];
            case (build_idx)
                0: build_sel_value = in_slot_j_flat[0*`GP_J_W +: `GP_J_W];
                1: build_sel_value = in_slot_j_flat[1*`GP_J_W +: `GP_J_W];
                2: build_sel_value = in_slot_j_flat[2*`GP_J_W +: `GP_J_W];
                default: build_sel_value = in_slot_j_flat[3*`GP_J_W +: `GP_J_W];
            endcase
        end else if (build_idx < 9) begin
            build_sel_valid = 1'b1;
            case (build_idx-4)
                0: build_sel_value = in_window_flat[0*`GP_J_W +: `GP_J_W];
                1: build_sel_value = in_window_flat[1*`GP_J_W +: `GP_J_W];
                2: build_sel_value = in_window_flat[2*`GP_J_W +: `GP_J_W];
                3: build_sel_value = in_window_flat[3*`GP_J_W +: `GP_J_W];
                4: build_sel_value = in_window_flat[4*`GP_J_W +: `GP_J_W];
                5: build_sel_value = in_window_flat[5*`GP_J_W +: `GP_J_W];
                6: build_sel_value = in_window_flat[6*`GP_J_W +: `GP_J_W];
                default: build_sel_value = in_window_flat[7*`GP_J_W +: `GP_J_W];
            endcase
        end
    end

    // Stage 2 resolve against the already-committed universe/request pool.
    // No build_idx or wide input mux is on this path.
    always @* begin
        raw_found = 1'b0;
        raw_found_id = 4'd0;
        for (bi=0; bi<13; bi=bi+1) begin
            if ((bi < univ_count) && (univ_val[bi] == build_raw_value_q) && !raw_found) begin
                raw_found = 1'b1;
                raw_found_id = bi[3:0];
            end
        end

        raw_resolved_id = raw_found ? raw_found_id : univ_count;
        req_pool_found = 1'b0;
        for (bi=0; bi<9; bi=bi+1) begin
            if ((bi < req_pool_count) && (req_pool_id[bi] == raw_resolved_id))
                req_pool_found = 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // DFS stack. sp=0 is the non-memoized current-request root.
    // req_idx 1..4 are memoized future stages 0..3.
    // -------------------------------------------------------------------------
    reg [3:0] sp;
    reg [3:0] f_req_idx [0:8];
    reg [2:0] f_count   [0:8];
    reg [3:0] f_id0     [0:8];
    reg [3:0] f_id1     [0:8];
    reg [3:0] f_id2     [0:8];
    reg [3:0] f_id3     [0:8];

    reg [1:0] f_dsize   [0:8];
    reg [6:0] f_dord    [0:8];
    reg [3:0] f_rord    [0:8]; // legacy/debug ordinal storage, not on action datapath
    reg [8:0] f_dmask   [0:8];
    reg [8:0] f_rmask   [0:8];
    reg [2:0] f_rsize   [0:8];
    reg       f_gen_valid [0:8];

    reg       f_best_valid [0:8];
    reg [10:0] f_best_cost [0:8];

    // One pending synchronous memo lookup per frame.
    reg       f_pipe_valid [0:8];
    reg [2:0] f_pipe_child_count [0:8];
    reg [3:0] f_pipe_cid0 [0:8];
    reg [3:0] f_pipe_cid1 [0:8];
    reg [3:0] f_pipe_cid2 [0:8];
    reg [3:0] f_pipe_cid3 [0:8];
    reg [6:0] f_pipe_imm  [0:8];
    reg [2:0] f_pipe_seg  [0:8];
    reg [6:0] f_pipe_pred [0:8];
    reg [6:0] f_pipe_j    [0:8];
    reg [2:0] f_pipe_val_count [0:8];
    reg [6:0] f_pipe_v0 [0:8];
    reg [6:0] f_pipe_v1 [0:8];
    reg [6:0] f_pipe_v2 [0:8];
    reg [6:0] f_pipe_v3 [0:8];

    // -------------------------------------------------------------------------
    // Per-frame PREP context.  Expensive predecessor/range/state filtering is
    // paid once when entering a frame, not on every legal action.
    // -------------------------------------------------------------------------
    reg [6:0]  f_ctx_j [0:8];
    reg [3:0]  f_ctx_jid [0:8];
    reg [6:0]  f_ctx_pred [0:8];
    reg [6:0]  f_ctx_imm [0:8];
    reg [3:0]  f_ctx_extra_count [0:8];
    reg [35:0] f_ctx_extra_ids [0:8];   // 9 x 4-bit
    reg [2:0]  f_ctx_keep_count [0:8];
    reg [15:0] f_ctx_keep_ids [0:8];    // 4 x 4-bit

    // PREP timing pipeline.
    //   ST_PREP_LOAD: snapshot the selected DFS frame (breaks sp->array mux path)
    //   ST_PREP_PRED: compute/latch request, qualified predecessor candidates, keep set
    //   ST_PREP_PACK: select/latch predecessor from registered candidates
    //   ST_PREP:      filter/pack restricted-B extras and install active context
    reg [3:0] prep_req_idx_q;
    reg [2:0] prep_count_q;
    reg [3:0] prep_id0_q, prep_id1_q, prep_id2_q, prep_id3_q;

    reg [6:0] prep_j;
    reg [3:0] prep_jid;
    reg [6:0] prep_pred;
    reg [6:0] prep_imm;
    reg [2:0] prep_keep_count;
    reg [15:0] prep_keep_ids;

    // Parallel predecessor tree.  Each checkpoint value is qualified
    // independently and the maximum is selected with a balanced 2-level tree.
    // This removes the previous four-deep compare/update chain from PREP.
    reg [6:0] prep_val0, prep_val1, prep_val2, prep_val3;
    reg [6:0] prep_cand0, prep_cand1, prep_cand2, prep_cand3;
    reg [6:0] prep_max01, prep_max23;

    // Timing cut: qualified predecessor candidates are captured before the
    // max-tree.  This adds one PREP cycle but preserves the exact predecessor
    // semantics while removing id/value qualification from the max-tree path.
    reg [6:0] prep_cand0_q, prep_cand1_q, prep_cand2_q, prep_cand3_q;
    reg [6:0] prep_qmax01, prep_qmax23, prep_pred_from_q;

    reg [6:0] prep_j_q;
    reg [3:0] prep_jid_q;
    reg [6:0] prep_pred_q;
    reg [6:0] prep_imm_q;
    reg [2:0] prep_keep_count_q;
    reg [15:0] prep_keep_ids_q;

    // PREP filter/pack timing pipeline.  The expensive work is deliberately
    // split into register-bounded stages rather than relying on place/route to
    // rescue a long priority/packing cone.
    reg [8:0] prep_elig_mask;
    reg [8:0] prep_elig_mask_q;
    reg [3:0] prep_extra_count;
    reg [35:0] prep_extra_ids;
    reg [3:0] prep_extra_count_q;
    reg [35:0] prep_extra_ids_q;
    reg prep_pool_in_state;
    reg [3:0] prep_pid;
    integer pi;

    // Hot-path active-frame mirror.  The DFS arrays remain the architectural
    // recursion stack, but action generation never variable-indexes them.
    // This removes the sp->9-way-array mux from the one-action/cycle path.
    reg [3:0]  a_req_idx;
    reg [6:0]  a_ctx_j;
    reg [3:0]  a_ctx_jid;
    reg [6:0]  a_ctx_pred;
    reg [6:0]  a_ctx_imm;
    reg [3:0]  a_ctx_extra_count;
    reg [35:0] a_ctx_extra_ids;
    reg [2:0]  a_ctx_keep_count;
    reg [15:0] a_ctx_keep_ids;
    reg [1:0]  a_dsize;
    reg [8:0]  a_dmask;
    reg [2:0]  a_rsize;
    reg [8:0]  a_rmask;
    reg        a_gen_valid;

    // Registered raw action-selection packet.
    //
    // The mask-driven restricted-B selector/compactor is intentionally
    // separated from the canonical 4-way ID sort by this register boundary:
    //
    //   a_dmask/a_rmask -> raw child IDs -> [actionq] -> canonical sort -> mreq
    //
    // This preserves one-action/cycle steady-state issue.  The packet also
    // carries the exact pre-action generator state so any older memo miss can
    // still flush younger speculative requests and restore the committed
    // action's parent generator bit-exactly.
    reg        actionq_valid;
    reg [2:0]  actionq_stage;
    reg [2:0]  actionq_child_count;
    reg [3:0]  actionq_raw0, actionq_raw1, actionq_raw2, actionq_raw3;
    reg [6:0]  actionq_imm, actionq_pred, actionq_j;
    reg [1:0]  actionq_pre_dsize;
    reg [8:0]  actionq_pre_dmask;
    reg [2:0]  actionq_pre_rsize;
    reg [8:0]  actionq_pre_rmask;
    reg        actionq_pre_gen_valid;

    // Active pending-action mirror.  f_pipe_* remains the architectural copy
    // that survives recursion, but the evaluation datapath never variable-
    // indexes that 9-frame array.  On a memo miss return, ST_RETURN restores
    // this mirror and ST_RETURN_EVAL consumes it one cycle later.
    reg [2:0] a_pipe_child_count;
    reg [3:0] a_pipe_cid0, a_pipe_cid1, a_pipe_cid2, a_pipe_cid3;
    reg [6:0] a_pipe_imm;
    reg [6:0] a_pipe_pred;
    reg [6:0] a_pipe_j;

    // Registered memo-request boundary. Canonical sorting ends at
    // these FFs; combinadic rank/stage-base address generation starts here.
    // Younger speculative requests are discarded on an older memo miss.
    reg        mreq_valid;
    reg [2:0]  mreq_stage;
    reg [2:0]  mreq_child_count;
    reg [3:0]  mreq_raw0, mreq_raw1, mreq_raw2, mreq_raw3;
    reg [6:0]  mreq_imm, mreq_pred, mreq_j;
    reg [1:0]  mreq_pre_dsize;
    reg [8:0]  mreq_pre_dmask;
    reg [2:0]  mreq_pre_rsize;
    reg [8:0]  mreq_pre_rmask;
    reg        mreq_pre_gen_valid;

    // Registered address/BRAM-request stage.  Sorting + combinadic rank +
    // stage-base addition terminate at these FFs instead of at RAMB36 pins.
    // The pipeline remains one-request-per-cycle; a miss flushes all younger
    // speculative stages and restores the missed action's saved generator state.
    reg        areq_valid;
    reg [13:0] areq_addr;
    reg [2:0]  areq_child_count;
    reg [3:0]  areq_id0, areq_id1, areq_id2, areq_id3;
    reg [6:0]  areq_imm, areq_pred, areq_j;
    reg [1:0]  areq_pre_dsize;
    reg [8:0]  areq_pre_dmask;
    reg [2:0]  areq_pre_rsize;
    reg [8:0]  areq_pre_rmask;
    reg        areq_pre_gen_valid;

    reg        mresp_valid;
    reg [1:0]  mresp_pre_dsize;
    reg [8:0]  mresp_pre_dmask;
    reg [2:0]  mresp_pre_rsize;
    reg [8:0]  mresp_pre_rmask;
    reg        mresp_pre_gen_valid;

    reg [3:0] mreq_s10,mreq_s11,mreq_s12,mreq_s13;
    reg [3:0] mreq_s20,mreq_s21,mreq_s22,mreq_s23;
    reg [3:0] mreq_id0,mreq_id1,mreq_id2,mreq_id3;
    reg [10:0] mreq_rank;
    reg [13:0] mreq_addr;
    always @* begin
        // hwfix15: mreq_raw* are already canonicalized at capture time.
        // Keep this stage to combinadic rank + stage-base address only.
        mreq_id0 = mreq_raw0;
        mreq_id1 = mreq_raw1;
        mreq_id2 = mreq_raw2;
        mreq_id3 = mreq_raw3;
        mreq_rank = rank_state(mreq_child_count,mreq_id0,mreq_id1,mreq_id2,mreq_id3);
        mreq_addr = memo_addr_of(mreq_stage,mreq_rank);
    end

    // PREP predecessor/keep stage uses only the registered frame snapshot.
    // req_val[] is cached during BUILD, avoiding req_id -> univ_val cascades for
    // the current request value.
    always @* begin
        prep_jid = req_id[prep_req_idx_q];
        prep_j   = req_val[prep_req_idx_q];

        // Read each checkpoint value once, qualify in parallel, then take max
        // with a balanced tree.  Invalid / above-request candidates become 0.
        prep_val0 = univ_val[prep_id0_q];
        prep_val1 = univ_val[prep_id1_q];
        prep_val2 = univ_val[prep_id2_q];
        prep_val3 = univ_val[prep_id3_q];

        if ((prep_count_q > 0) && (prep_val0 <= prep_j)) prep_cand0 = prep_val0;
        else                                             prep_cand0 = 7'd0;
        if ((prep_count_q > 1) && (prep_val1 <= prep_j)) prep_cand1 = prep_val1;
        else                                             prep_cand1 = 7'd0;
        if ((prep_count_q > 2) && (prep_val2 <= prep_j)) prep_cand2 = prep_val2;
        else                                             prep_cand2 = 7'd0;
        if ((prep_count_q > 3) && (prep_val3 <= prep_j)) prep_cand3 = prep_val3;
        else                                             prep_cand3 = 7'd0;

        if (prep_cand0 >= prep_cand1) prep_max01 = prep_cand0;
        else                           prep_max01 = prep_cand1;
        if (prep_cand2 >= prep_cand3) prep_max23 = prep_cand2;
        else                           prep_max23 = prep_cand3;
        if (prep_max01 >= prep_max23) prep_pred = prep_max01;
        else                           prep_pred = prep_max23;

        prep_imm = prep_j - prep_pred;

        prep_keep_count = 3'd0;
        prep_keep_ids = 16'd0;
        if ((prep_count_q > 0) && (prep_id0_q != prep_jid)) begin
            prep_keep_ids[0*4 +: 4] = prep_id0_q; prep_keep_count = prep_keep_count + 1'b1;
        end
        if ((prep_count_q > 1) && (prep_id1_q != prep_jid)) begin
            case (prep_keep_count)
                0: prep_keep_ids[0*4 +: 4] = prep_id1_q;
                1: prep_keep_ids[1*4 +: 4] = prep_id1_q;
                2: prep_keep_ids[2*4 +: 4] = prep_id1_q;
                default: prep_keep_ids[3*4 +: 4] = prep_id1_q;
            endcase
            prep_keep_count = prep_keep_count + 1'b1;
        end
        if ((prep_count_q > 2) && (prep_id2_q != prep_jid)) begin
            case (prep_keep_count)
                0: prep_keep_ids[0*4 +: 4] = prep_id2_q;
                1: prep_keep_ids[1*4 +: 4] = prep_id2_q;
                2: prep_keep_ids[2*4 +: 4] = prep_id2_q;
                default: prep_keep_ids[3*4 +: 4] = prep_id2_q;
            endcase
            prep_keep_count = prep_keep_count + 1'b1;
        end
        if ((prep_count_q > 3) && (prep_id3_q != prep_jid)) begin
            case (prep_keep_count)
                0: prep_keep_ids[0*4 +: 4] = prep_id3_q;
                1: prep_keep_ids[1*4 +: 4] = prep_id3_q;
                2: prep_keep_ids[2*4 +: 4] = prep_id3_q;
                default: prep_keep_ids[3*4 +: 4] = prep_id3_q;
            endcase
            prep_keep_count = prep_keep_count + 1'b1;
        end
    end

    // Registered-candidate predecessor max-tree.  ST_PREP_PRED captures the
    // four qualified candidates; ST_PREP_PACK evaluates only this short tree.
    always @* begin
        if (prep_cand0_q >= prep_cand1_q) prep_qmax01 = prep_cand0_q;
        else                               prep_qmax01 = prep_cand1_q;
        if (prep_cand2_q >= prep_cand3_q) prep_qmax23 = prep_cand2_q;
        else                               prep_qmax23 = prep_cand3_q;
        if (prep_qmax01 >= prep_qmax23) prep_pred_from_q = prep_qmax01;
        else                             prep_pred_from_q = prep_qmax23;
    end

    // PREP filter stage: nine range/membership tests in parallel.
    //
    // Timing factoring: do NOT feed the balanced predecessor max-tree back into
    // every restricted-B eligibility comparator.  For a pool value x<j,
    //     x > max(valid checkpoint values <= j)
    // is exactly equivalent to x being greater than each individually valid
    // predecessor candidate.  The implicit psi0 predecessor (j=0) is kept as
    // an explicit x>0 guard.  The four checkpoint comparisons can therefore run in
    // parallel with the max-tree used only for source_j / immediate cost.
    // This removes the previous id->value->max-tree->eligibility serial path
    // without adding an FSM cycle.
    always @* begin
        prep_elig_mask = 9'd0;
        for (pi=0; pi<9; pi=pi+1) begin
            prep_pid = req_pool_id[pi];
            prep_pool_in_state = 1'b0;
            if ((prep_count_q > 0) && (prep_id0_q == prep_pid)) prep_pool_in_state = 1'b1;
            if ((prep_count_q > 1) && (prep_id1_q == prep_pid)) prep_pool_in_state = 1'b1;
            if ((prep_count_q > 2) && (prep_id2_q == prep_pid)) prep_pool_in_state = 1'b1;
            if ((prep_count_q > 3) && (prep_id3_q == prep_pid)) prep_pool_in_state = 1'b1;
            if ((pi < req_pool_count) && !prep_pool_in_state &&
                (req_pool_val[pi] > 7'd0) &&
                (req_pool_val[pi] < prep_j) &&
                ((prep_count_q <= 0) || (prep_val0 > prep_j) || (req_pool_val[pi] > prep_val0)) &&
                ((prep_count_q <= 1) || (prep_val1 > prep_j) || (req_pool_val[pi] > prep_val1)) &&
                ((prep_count_q <= 2) || (prep_val2 > prep_j) || (req_pool_val[pi] > prep_val2)) &&
                ((prep_count_q <= 3) || (prep_val3 > prep_j) || (req_pool_val[pi] > prep_val3)))
                prep_elig_mask[pi] = 1'b1;
        end
    end

    // PREP pack stage: only compaction remains.  The dynamic part-select used
    // by the earlier implementation is replaced by fixed-slice case writes,
    // which synthesizes to a shallower network on Artix-7.
    always @* begin
        prep_extra_count = 4'd0;
        prep_extra_ids = 36'd0;
        for (pi=0; pi<9; pi=pi+1) begin
            if (prep_elig_mask_q[pi]) begin
                case (prep_extra_count)
                    4'd0: prep_extra_ids[ 3: 0] = req_pool_id[pi];
                    4'd1: prep_extra_ids[ 7: 4] = req_pool_id[pi];
                    4'd2: prep_extra_ids[11: 8] = req_pool_id[pi];
                    4'd3: prep_extra_ids[15:12] = req_pool_id[pi];
                    4'd4: prep_extra_ids[19:16] = req_pool_id[pi];
                    4'd5: prep_extra_ids[23:20] = req_pool_id[pi];
                    4'd6: prep_extra_ids[27:24] = req_pool_id[pi];
                    4'd7: prep_extra_ids[31:28] = req_pool_id[pi];
                    default: prep_extra_ids[35:32] = req_pool_id[pi];
                endcase
                prep_extra_count = prep_extra_count + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Current legal action from the active-frame mirror.
    //
    // Split mask -> compaction -> canonical-sort path:
    //   Egen : active masks -> raw child-ID packet (registered actionq)
    //   Esort: actionq raw IDs -> fixed-depth canonical 4-way sort -> mreq
    //
    // Both stages accept one action per cycle.  Only latency increases by one
    // cycle; requested-j, candidate/action set, DP cost, tie-break and memo
    // semantics are unchanged.
    // -------------------------------------------------------------------------
    reg [6:0] top_j;
    reg [3:0] top_jid;
    reg [6:0] top_pred;
    reg [3:0] extra_count;
    reg [2:0] keep_count;
    reg [1:0] top_dsize;
    reg [2:0] top_rsize;
    reg [8:0] top_dmask;
    reg [8:0] top_rmask9;

    reg [2:0] action_raw_child_count;
    reg [3:0] action_raw0, action_raw1, action_raw2, action_raw3;

    reg [2:0] action_child_count;
    reg [3:0] action_id0, action_id1, action_id2, action_id3;
    reg [6:0] action_imm_cost;

    reg [3:0] tmp_id [0:3];
    reg [3:0] sel_id;
    reg [3:0] sid10,sid11,sid12,sid13;
    reg [3:0] sid20,sid21,sid22,sid23;
    integer ai;
    integer tc;

    // Egen: mask-driven selection/compaction only.  Canonical sorting is
    // deliberately deferred until after actionq_* registers.
    always @* begin
        top_j = a_ctx_j;
        top_jid = a_ctx_jid;
        top_pred = a_ctx_pred;
        extra_count = a_ctx_extra_count;
        keep_count = a_ctx_keep_count;
        top_dsize = a_dsize;
        top_rsize = a_rsize;
        top_dmask = a_dmask;
        top_rmask9 = a_rmask;

        for (ai=0; ai<4; ai=ai+1)
            tmp_id[ai] = 4'hF;
        tc = 1;
        tmp_id[0] = top_jid;
        for (ai=0; ai<9; ai=ai+1) begin
            if (top_dmask[ai] && (tc < 4)) begin
                sel_id = a_ctx_extra_ids[ai*4 +: 4];
                tmp_id[tc] = sel_id;
                tc = tc + 1;
            end
        end
        for (ai=0; ai<4; ai=ai+1) begin
            if (top_rmask9[ai] && (tc < 4)) begin
                sel_id = a_ctx_keep_ids[ai*4 +: 4];
                tmp_id[tc] = sel_id;
                tc = tc + 1;
            end
        end

        action_raw_child_count = tc[2:0];
        action_raw0 = tmp_id[0];
        action_raw1 = tmp_id[1];
        action_raw2 = tmp_id[2];
        action_raw3 = tmp_id[3];
    end

    // Esort: fixed-depth 4-input sorting network from registered actionq data.
    always @* begin
        action_child_count = actionq_child_count;

        if (actionq_raw0 <= actionq_raw1) begin sid10=actionq_raw0; sid11=actionq_raw1; end
        else begin sid10=actionq_raw1; sid11=actionq_raw0; end
        if (actionq_raw2 <= actionq_raw3) begin sid12=actionq_raw2; sid13=actionq_raw3; end
        else begin sid12=actionq_raw3; sid13=actionq_raw2; end

        if (sid10 <= sid12) begin sid20=sid10; sid22=sid12; end
        else begin sid20=sid12; sid22=sid10; end
        if (sid11 <= sid13) begin sid21=sid11; sid23=sid13; end
        else begin sid21=sid13; sid23=sid11; end

        action_id0 = sid20;
        action_id3 = sid23;
        if (sid21 <= sid22) begin action_id1=sid21; action_id2=sid22; end
        else begin action_id1=sid22; action_id2=sid21; end

        action_imm_cost = actionq_imm;
    end

    // Pending-action evaluation pipeline.
    // hwfix9: deep metadata evaluation is root-only; future frames use a fast
    // cost-only path because their DP objective has no segment/tuple tie-break.
    //
    // Stage E0: registered child IDs -> universe-value lookup only.
    // Stage E1: registered raw values -> fixed-depth 4-way value sort.
    // Stage E2: registered sorted values -> segment count / best reduction.
    //
    // This is intentionally deeper than the earlier direct a_pipe_cid* ->
    // root_cand_* path.  Each stage accepts one action per cycle, so steady
    // memo-hit throughput is preserved while the 100-MHz critical cone is cut.
    reg [6:0] eval_raw_v0, eval_raw_v1, eval_raw_v2, eval_raw_v3;
    always @* begin
        eval_raw_v0 = (a_pipe_child_count > 0) ? univ_val[a_pipe_cid0] : 7'h7F;
        eval_raw_v1 = (a_pipe_child_count > 1) ? univ_val[a_pipe_cid1] : 7'h7F;
        eval_raw_v2 = (a_pipe_child_count > 2) ? univ_val[a_pipe_cid2] : 7'h7F;
        eval_raw_v3 = (a_pipe_child_count > 3) ? univ_val[a_pipe_cid3] : 7'h7F;
    end

    reg        pvalq_valid;
    reg [3:0]  pvalq_sp;
    reg [10:0] pvalq_total_cost;
    reg [2:0]  pvalq_count;
    reg [6:0]  pvalq_v0, pvalq_v1, pvalq_v2, pvalq_v3;
    reg [6:0]  pvalq_pred;
    reg [6:0]  pvalq_j;

    // Non-root memo-hit cost pipeline.  Register the BRAM-returned child cost
    // before the add/compare against f_best_cost.  This adds one evaluation
    // cycle but keeps one result accepted per cycle and removes the direct
    // RAMB36 -> add -> compare -> f_best_cost critical path.
    reg        fvalq_valid;
    reg [3:0]  fvalq_sp;
    reg [6:0]  fvalq_imm;
    reg [10:0] fvalq_child_cost;
    wire [10:0] fvalq_total = {4'd0,fvalq_imm} + fvalq_child_cost;

    reg [6:0] qval10,qval11,qval12,qval13;
    reg [6:0] qval20,qval21,qval22,qval23;
    reg [6:0] qsort_v0,qsort_v1,qsort_v2,qsort_v3;
    always @* begin
        if (pvalq_v0 <= pvalq_v1) begin qval10=pvalq_v0; qval11=pvalq_v1; end
        else begin qval10=pvalq_v1; qval11=pvalq_v0; end
        if (pvalq_v2 <= pvalq_v3) begin qval12=pvalq_v2; qval13=pvalq_v3; end
        else begin qval12=pvalq_v3; qval13=pvalq_v2; end
        if (qval10 <= qval12) begin qval20=qval10; qval22=qval12; end
        else begin qval20=qval12; qval22=qval10; end
        if (qval11 <= qval13) begin qval21=qval11; qval23=qval13; end
        else begin qval21=qval13; qval23=qval11; end
        qsort_v0 = qval20;
        qsort_v3 = qval23;
        if (qval21 <= qval22) begin qsort_v1=qval21; qsort_v2=qval22; end
        else begin qsort_v1=qval22; qsort_v2=qval21; end
    end

    reg        pmeta_valid;
    reg [3:0]  pmeta_sp;
    reg [10:0] pmeta_total_cost;
    reg [2:0]  pmeta_count;
    reg [6:0]  pmeta_v0, pmeta_v1, pmeta_v2, pmeta_v3;
    reg [6:0]  pmeta_pred;
    reg [6:0]  pmeta_j;
    reg [2:0]  pmeta_seg;
    always @* begin
        pmeta_seg = 3'd1;
        if ((pmeta_count > 0) && (pmeta_v0 > pmeta_pred) && (pmeta_v0 < pmeta_j))
            pmeta_seg = pmeta_seg + 1'b1;
        if ((pmeta_count > 1) && (pmeta_v1 > pmeta_pred) && (pmeta_v1 < pmeta_j))
            pmeta_seg = pmeta_seg + 1'b1;
        if ((pmeta_count > 2) && (pmeta_v2 > pmeta_pred) && (pmeta_v2 < pmeta_j))
            pmeta_seg = pmeta_seg + 1'b1;
        if ((pmeta_count > 3) && (pmeta_v3 > pmeta_pred) && (pmeta_v3 < pmeta_j))
            pmeta_seg = pmeta_seg + 1'b1;
    end

    // Root lexicographic compare helper.
    function lex_less4;
        input [2:0] ac;
        input [6:0] a0,a1,a2,a3;
        input [2:0] bc;
        input [6:0] b0,b1,b2,b3;
        begin
            // Verilog implementation of tuple(sorted(S')) ordering.  If one
            // tuple is a strict prefix of the other, the shorter tuple is
            // lexicographically smaller (Python tuple semantics used by SW).
            if ((ac == 0) || (bc == 0)) begin
                lex_less4 = (ac < bc);
            end else if (a0 != b0) begin
                lex_less4 = (a0 < b0);
            end else if ((ac == 1) || (bc == 1)) begin
                lex_less4 = (ac < bc);
            end else if (a1 != b1) begin
                lex_less4 = (a1 < b1);
            end else if ((ac == 2) || (bc == 2)) begin
                lex_less4 = (ac < bc);
            end else if (a2 != b2) begin
                lex_less4 = (a2 < b2);
            end else if ((ac == 3) || (bc == 3)) begin
                lex_less4 = (ac < bc);
            end else if (a3 != b3) begin
                lex_less4 = (a3 < b3);
            end else begin
                lex_less4 = 1'b0;
            end
        end
    endfunction

    // -------------------------------------------------------------------------
    // Control-state encoding is declared before memo-read combinational gating.
    // -------------------------------------------------------------------------
    localparam [3:0]
        ST_IDLE      = 4'd0,
        ST_CLEAR     = 4'd1,
        ST_BUILD     = 4'd2,
        ST_ROOT_INIT = 4'd3,
        ST_RUN       = 4'd4,
        ST_RETURN    = 4'd5,
        ST_FINISH    = 4'd6,
        ST_ABORT       = 4'd7,
        ST_PREP        = 4'd8,
        ST_RETURN_EVAL = 4'd9,
        ST_ROOT_DRAIN  = 4'd10,
        ST_PREP_LOAD   = 4'd11,
        ST_PREP_PRED   = 4'd12,
        ST_BUILD_COMMIT = 4'd13,
        ST_PREP_PACK   = 4'd14,
        ST_BUILD_RESOLVE = 4'd15;
    reg [3:0] fsm_state;

    // -------------------------------------------------------------------------
    // Memo interface.  Address generation starts from registered mreq_* fields,
    // breaking the old a_dmask -> sort -> rank -> BRAM path.
    // -------------------------------------------------------------------------
    wire top_terminal = (a_req_idx >= 4);
    wire [17:0] memo_rd_data;
    wire memo_pipe_hit = mresp_valid && (memo_rd_data[17:10] == policy_epoch);

    wire can_issue_memo_action = busy && (fsm_state == ST_RUN) && !top_terminal &&
                                 a_gen_valid && (!mresp_valid || memo_pipe_hit);

    wire memo_rd_en = areq_valid;
    wire [13:0] memo_rd_addr = areq_addr;
    reg memo_wr_en;
    reg [13:0] memo_wr_addr;
    reg [17:0] memo_wr_data;
    reg memo_clear_en;
    reg [13:0] memo_clear_addr;

    grover_ckpt_policy_memo u_policy_memo (
        .clk(clk),
        .rd_en(memo_rd_en), .rd_addr(memo_rd_addr), .rd_data(memo_rd_data),
        .wr_en(memo_wr_en), .wr_addr(memo_wr_addr), .wr_data(memo_wr_data),
        .clear_en(memo_clear_en), .clear_addr(memo_clear_addr)
    );

    // -------------------------------------------------------------------------
    // Control / counters.
    // -------------------------------------------------------------------------
    reg [31:0] cyc_ctr;
    reg [31:0] act_ctr;
    reg [31:0] hit_ctr;
    reg [31:0] miss_ctr;
    reg [10:0] return_cost;
    reg [13:0] clear_ctr;
    reg memo_needs_clear;

    reg root_best_valid;
    reg [10:0] root_best_cost;
    reg [2:0] root_best_seg;
    reg [2:0] root_best_count;
    reg [6:0] root_best_v0,root_best_v1,root_best_v2,root_best_v3;

    // One-deep root candidate reduction pipeline.  A candidate is captured from
    // the memo-return datapath, then compared with the running best on the next
    // cycle.  Capture and reduction may overlap, preserving one-action/cycle
    // root memo-hit throughput while cutting the former 20+ ns combined path.
    reg        root_cand_valid;
    reg [10:0] root_cand_cost;
    reg [2:0]  root_cand_seg;
    reg [2:0]  root_cand_count;
    reg [6:0]  root_cand_v0,root_cand_v1,root_cand_v2,root_cand_v3;
    reg        root_cand_better;

    integer si;
    reg [10:0] eval_total;

    // Advance the top frame's legal-action iterator after issuing one action.
    // Masks are state, not recomputed from ordinals on the action critical path.
    task advance_generator;
        reg [1:0] ndsize;
        reg [2:0] nrsize;
        reg [8:0] nmask;
        begin
            if (comb_has_next9(a_rmask, keep_count, a_rsize)) begin
                nmask = next_comb9(a_rmask, keep_count, a_rsize);
                a_rmask <= nmask;
                f_rmask[sp] <= nmask;
            end else if (comb_has_next9(a_dmask, extra_count, a_dsize)) begin
                nmask = next_comb9(a_dmask, extra_count, a_dsize);
                a_dmask <= nmask;
                f_dmask[sp] <= nmask;
                a_rmask <= first_comb9(a_rsize);
                f_rmask[sp] <= first_comb9(a_rsize);
            end else if ((a_dsize < 3) && ((a_dsize + 1'b1) <= extra_count)) begin
                ndsize = a_dsize + 1'b1;
                if (keep_count < (3 - ndsize)) nrsize = keep_count;
                else nrsize = 3 - ndsize;
                a_dsize <= ndsize; f_dsize[sp] <= ndsize;
                a_dmask <= first_comb9(ndsize); f_dmask[sp] <= first_comb9(ndsize);
                a_rsize <= nrsize; f_rsize[sp] <= nrsize;
                a_rmask <= first_comb9(nrsize); f_rmask[sp] <= first_comb9(nrsize);
            end else begin
                a_gen_valid <= 1'b0;
                f_gen_valid[sp] <= 1'b0;
            end
        end
    endtask

    task eval_pending;
        input [10:0] child_cost11;
        reg [10:0] fast_total;
        begin
            fast_total = {4'd0,a_pipe_imm} + child_cost11;
            if (sp == 0) begin
                // Only the root needs segment count + lexicographic S' metadata.
                // Keep the deep E0/E1/E2 pipeline there for 100-MHz closure.
                pvalq_valid      <= 1'b1;
                pvalq_sp         <= 4'd0;
                pvalq_total_cost <= fast_total;
                pvalq_count      <= a_pipe_child_count;
                pvalq_v0         <= eval_raw_v0;
                pvalq_v1         <= eval_raw_v1;
                pvalq_v2         <= eval_raw_v2;
                pvalq_v3         <= eval_raw_v3;
                pvalq_pred       <= a_pipe_pred;
                pvalq_j          <= a_pipe_j;
            end else begin
                // Future DP frames minimize physical cost only.  Capture the
                // memo-returned child cost here and perform add/compare from
                // registers on the next cycle.  Store sp explicitly because a
                // following memo miss may descend to a child before this result
                // is reduced.
                fvalq_valid      <= 1'b1;
                fvalq_sp         <= sp;
                fvalq_imm        <= a_pipe_imm;
                fvalq_child_cost <= child_cost11;
            end
        end
    endtask

    task capture_current_action_to_actionq;
        begin
            // Egen capture: preserve the exact unsorted legal action
            // and its pre-action generator state, then advance the architectural
            // generator state at the registered boundary.
            actionq_valid         <= 1'b1;
            actionq_stage         <= a_req_idx[2:0];
            actionq_child_count   <= action_raw_child_count;
            actionq_raw0          <= action_raw0;
            actionq_raw1          <= action_raw1;
            actionq_raw2          <= action_raw2;
            actionq_raw3          <= action_raw3;
            actionq_imm           <= a_ctx_imm;
            actionq_pred          <= a_ctx_pred;
            actionq_j             <= a_ctx_j;
            actionq_pre_dsize     <= a_dsize;
            actionq_pre_dmask     <= a_dmask;
            actionq_pre_rsize     <= a_rsize;
            actionq_pre_rmask     <= a_rmask;
            actionq_pre_gen_valid <= a_gen_valid;
            advance_generator;
        end
    endtask

    // Main sequential engine.
    always @(posedge clk) begin
        if (!rstn) begin
            busy <= 1'b0;
            done <= 1'b0;
            policy_error <= 1'b0;
            source_j <= 7'd0;
            next_count <= 3'd0;
            next_j_flat <= 28'd0;
            root_cost <= 11'd0;
            root_segment_count <= 3'd0;
            policy_cycles_last <= 32'd0;
            policy_actions_last <= 32'd0;
            policy_memo_hit_last <= 32'd0;
            policy_memo_miss_last <= 32'd0;
            policy_cycles_total <= 32'd0;
            policy_actions_total <= 32'd0;
            policy_max_latency <= 32'd0;
            policy_epoch <= 8'd0;
            in_slot_valid <= 4'd0;
            in_slot_j_flat <= 28'd0;
            in_window_flat <= 63'd0;
            univ_count <= 4'd0;
            req_pool_count <= 4'd0;
            build_idx <= 5'd0;
            build_raw_valid_q <= 1'b0;
            build_raw_value_q <= 7'd0;
            build_raw_idx_q <= 5'd0;
            build_found_q <= 1'b0;
            build_found_id_q <= 4'd0;
            build_req_pool_found_q <= 1'b0;
            build_resolved_id_q <= 4'd0;
            root_init_count <= 3'd0;
            root_init_id0<=4'd0; root_init_id1<=4'd0; root_init_id2<=4'd0; root_init_id3<=4'd0;
            sp <= 4'd0;
            prep_req_idx_q<=4'd0; prep_count_q<=3'd0;
            prep_id0_q<=4'd0; prep_id1_q<=4'd0; prep_id2_q<=4'd0; prep_id3_q<=4'd0;
            prep_j_q<=7'd0; prep_jid_q<=4'd0; prep_pred_q<=7'd0; prep_imm_q<=7'd0;
            prep_cand0_q<=7'd0; prep_cand1_q<=7'd0; prep_cand2_q<=7'd0; prep_cand3_q<=7'd0;
            prep_keep_count_q<=3'd0; prep_keep_ids_q<=16'd0;
            prep_elig_mask_q<=9'd0; prep_extra_count_q<=4'd0; prep_extra_ids_q<=36'd0;
            a_req_idx<=4'd0; a_ctx_j<=7'd0; a_ctx_jid<=4'd0; a_ctx_pred<=7'd0; a_ctx_imm<=7'd0;
            a_ctx_extra_count<=4'd0; a_ctx_extra_ids<=36'd0; a_ctx_keep_count<=3'd0; a_ctx_keep_ids<=16'd0;
            a_dsize<=2'd0; a_dmask<=9'd0; a_rsize<=3'd0; a_rmask<=9'd0; a_gen_valid<=1'b0;
            actionq_valid<=1'b0; actionq_stage<=3'd0; actionq_child_count<=3'd0;
            actionq_raw0<=4'd0; actionq_raw1<=4'd0; actionq_raw2<=4'd0; actionq_raw3<=4'd0;
            actionq_imm<=7'd0; actionq_pred<=7'd0; actionq_j<=7'd0;
            actionq_pre_dsize<=2'd0; actionq_pre_dmask<=9'd0;
            actionq_pre_rsize<=3'd0; actionq_pre_rmask<=9'd0; actionq_pre_gen_valid<=1'b0;
            a_pipe_child_count<=3'd0; a_pipe_cid0<=4'd0; a_pipe_cid1<=4'd0; a_pipe_cid2<=4'd0; a_pipe_cid3<=4'd0;
            a_pipe_imm<=7'd0; a_pipe_pred<=7'd0; a_pipe_j<=7'd0;
            mreq_valid<=1'b0; mreq_stage<=3'd0; mreq_child_count<=3'd0;
            mreq_raw0<=4'd0; mreq_raw1<=4'd0; mreq_raw2<=4'd0; mreq_raw3<=4'd0;
            mreq_imm<=7'd0; mreq_pred<=7'd0; mreq_j<=7'd0;
            mreq_pre_dsize<=2'd0; mreq_pre_dmask<=9'd0; mreq_pre_rsize<=3'd0; mreq_pre_rmask<=9'd0; mreq_pre_gen_valid<=1'b0;
            areq_valid<=1'b0; areq_addr<=14'd0; areq_child_count<=3'd0;
            areq_id0<=4'd0; areq_id1<=4'd0; areq_id2<=4'd0; areq_id3<=4'd0;
            areq_imm<=7'd0; areq_pred<=7'd0; areq_j<=7'd0;
            areq_pre_dsize<=2'd0; areq_pre_dmask<=9'd0; areq_pre_rsize<=3'd0; areq_pre_rmask<=9'd0; areq_pre_gen_valid<=1'b0;
            mresp_valid<=1'b0; mresp_pre_dsize<=2'd0; mresp_pre_dmask<=9'd0;
            mresp_pre_rsize<=3'd0; mresp_pre_rmask<=9'd0; mresp_pre_gen_valid<=1'b0;
            fsm_state <= ST_IDLE;
            cyc_ctr <= 32'd0; act_ctr<=32'd0; hit_ctr<=32'd0; miss_ctr<=32'd0;
            return_cost <= 11'd0;
            clear_ctr <= 14'd0;
            memo_needs_clear <= 1'b1;
            memo_wr_en <= 1'b0; memo_wr_addr<=14'd0; memo_wr_data<=18'd0;
            memo_clear_en<=1'b0; memo_clear_addr<=14'd0;
            root_best_valid<=1'b0; root_best_cost<=INF_COST; root_best_seg<=3'd0; root_best_count<=3'd0;
            root_best_v0<=7'd0; root_best_v1<=7'd0; root_best_v2<=7'd0; root_best_v3<=7'd0;
            root_cand_valid<=1'b0; root_cand_cost<=INF_COST; root_cand_seg<=3'd0; root_cand_count<=3'd0;
            root_cand_v0<=7'd0; root_cand_v1<=7'd0; root_cand_v2<=7'd0; root_cand_v3<=7'd0;
            pvalq_valid<=1'b0; pvalq_sp<=4'd0; pvalq_total_cost<=11'd0; pvalq_count<=3'd0;
            pvalq_v0<=7'd0; pvalq_v1<=7'd0; pvalq_v2<=7'd0; pvalq_v3<=7'd0; pvalq_pred<=7'd0; pvalq_j<=7'd0;
            fvalq_valid<=1'b0; fvalq_sp<=4'd0; fvalq_imm<=7'd0; fvalq_child_cost<=11'd0;
            pmeta_valid<=1'b0; pmeta_sp<=4'd0; pmeta_total_cost<=11'd0; pmeta_count<=3'd0;
            pmeta_v0<=7'd0; pmeta_v1<=7'd0; pmeta_v2<=7'd0; pmeta_v3<=7'd0; pmeta_pred<=7'd0; pmeta_j<=7'd0;
            for (si=0; si<9; si=si+1) begin
                req_id[si] <= 4'd0;
                req_val[si] <= 7'd0;
                req_pool_id[si] <= 4'd0;
                req_pool_val[si] <= 7'd0;
                f_req_idx[si] <= 4'd0;
                f_count[si] <= 3'd0;
                f_id0[si]<=4'd0; f_id1[si]<=4'd0; f_id2[si]<=4'd0; f_id3[si]<=4'd0;
                f_dsize[si]<=2'd0; f_dord[si]<=7'd0; f_rord[si]<=4'd0;
                f_dmask[si]<=9'd0; f_rmask[si]<=9'd0; f_rsize[si]<=3'd0; f_gen_valid[si]<=1'b0;
                f_best_valid[si]<=1'b0; f_best_cost[si]<=INF_COST;
                f_pipe_valid[si]<=1'b0;
                f_pipe_child_count[si]<=3'd0;
                f_pipe_cid0[si]<=4'd0; f_pipe_cid1[si]<=4'd0; f_pipe_cid2[si]<=4'd0; f_pipe_cid3[si]<=4'd0;
                f_pipe_imm[si]<=7'd0; f_pipe_seg[si]<=3'd0; f_pipe_pred[si]<=7'd0; f_pipe_j[si]<=7'd0; f_pipe_val_count[si]<=3'd0;
                f_pipe_v0[si]<=7'd0; f_pipe_v1[si]<=7'd0; f_pipe_v2[si]<=7'd0; f_pipe_v3[si]<=7'd0;
                f_ctx_j[si]<=7'd0; f_ctx_jid[si]<=4'd0; f_ctx_pred[si]<=7'd0; f_ctx_imm[si]<=7'd0;
                f_ctx_extra_count[si]<=4'd0; f_ctx_extra_ids[si]<=36'd0;
                f_ctx_keep_count[si]<=3'd0; f_ctx_keep_ids[si]<=16'd0;
            end
            for (si=0; si<13; si=si+1)
                univ_val[si] <= 7'd0;
        end else begin
            done <= 1'b0;
            memo_wr_en <= 1'b0;
            memo_clear_en <= 1'b0;

            // Drain one registered root candidate every cycle.  eval_pending may
            // capture the next candidate later in this same always block; the
            // final nonblocking assignment to root_cand_valid therefore keeps
            // the pipeline full on consecutive root memo hits.
            root_cand_better = 1'b0;
            if (root_cand_valid) begin
                if (!root_best_valid)
                    root_cand_better = 1'b1;
                else if (root_cand_cost < root_best_cost)
                    root_cand_better = 1'b1;
                else if ((root_cand_cost == root_best_cost) && (root_cand_seg < root_best_seg))
                    root_cand_better = 1'b1;
                else if ((root_cand_cost == root_best_cost) && (root_cand_seg == root_best_seg) &&
                         lex_less4(root_cand_count,root_cand_v0,root_cand_v1,root_cand_v2,root_cand_v3,
                                   root_best_count,root_best_v0,root_best_v1,root_best_v2,root_best_v3))
                    root_cand_better = 1'b1;

                if (root_cand_better) begin
                    root_best_valid <= 1'b1;
                    root_best_cost  <= root_cand_cost;
                    root_best_seg   <= root_cand_seg;
                    root_best_count <= root_cand_count;
                    root_best_v0    <= root_cand_v0;
                    root_best_v1    <= root_cand_v1;
                    root_best_v2    <= root_cand_v2;
                    root_best_v3    <= root_cand_v3;
                end
            end
            root_cand_valid <= 1'b0;

            // E2: consume one sorted-value record every cycle.
            pmeta_valid <= pvalq_valid;
            if (pvalq_valid) begin
                pmeta_sp         <= pvalq_sp;
                pmeta_total_cost <= pvalq_total_cost;
                pmeta_count      <= pvalq_count;
                pmeta_v0         <= qsort_v0;
                pmeta_v1         <= qsort_v1;
                pmeta_v2         <= qsort_v2;
                pmeta_v3         <= qsort_v3;
                pmeta_pred       <= pvalq_pred;
                pmeta_j          <= pvalq_j;
            end

            // E0 input slot is consumed every cycle; eval_pending() later in
            // this same always block may refill it for the next cycle.
            pvalq_valid <= 1'b0;

            // Non-root memo result reduction.  The BRAM output was captured in
            // fvalq_* on the previous cycle, so this cone starts at FFs rather
            // than at RAMB36 output pins.  The slot may be refilled later in
            // this same always block by eval_pending(), sustaining 1/cycle.
            if (fvalq_valid) begin
                if (!f_best_valid[fvalq_sp] || (fvalq_total < f_best_cost[fvalq_sp])) begin
                    f_best_valid[fvalq_sp] <= 1'b1;
                    f_best_cost[fvalq_sp]  <= fvalq_total;
                end
            end
            fvalq_valid <= 1'b0;

            // E3 reduction from registered sorted values.
            if (pmeta_valid) begin
                if (pmeta_sp == 0) begin
                    root_cand_valid <= 1'b1;
                    root_cand_cost  <= pmeta_total_cost;
                    root_cand_seg   <= pmeta_seg;
                    root_cand_count <= pmeta_count;
                    root_cand_v0    <= pmeta_v0;
                    root_cand_v1    <= pmeta_v1;
                    root_cand_v2    <= pmeta_v2;
                    root_cand_v3    <= pmeta_v3;
                end else if (!f_best_valid[pmeta_sp] ||
                             (pmeta_total_cost < f_best_cost[pmeta_sp])) begin
                    f_best_valid[pmeta_sp] <= 1'b1;
                    f_best_cost[pmeta_sp]  <= pmeta_total_cost;
                end
            end

            if (busy)
                cyc_ctr <= cyc_ctr + 1'b1;

            case (fsm_state)
                ST_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        policy_error <= 1'b0;
                        in_slot_valid <= slot_valid;
                        in_slot_j_flat <= slot_j_flat;
                        in_window_flat <= j_window_flat;
                        cyc_ctr<=32'd0; act_ctr<=32'd0; hit_ctr<=32'd0; miss_ctr<=32'd0;
                        actionq_valid<=1'b0; mreq_valid<=1'b0; areq_valid<=1'b0; mresp_valid<=1'b0; pvalq_valid<=1'b0; pmeta_valid<=1'b0; fvalq_valid<=1'b0;
                        univ_count<=4'd0; req_pool_count<=4'd0; build_idx<=5'd0; root_init_count<=3'd0;
                        build_raw_valid_q<=1'b0; build_raw_value_q<=7'd0; build_raw_idx_q<=5'd0;
                        build_found_q<=1'b0; build_found_id_q<=4'd0; build_req_pool_found_q<=1'b0; build_resolved_id_q<=4'd0;
                        root_init_id0<=4'd0; root_init_id1<=4'd0; root_init_id2<=4'd0; root_init_id3<=4'd0;
                        root_best_valid<=1'b0; root_best_cost<=INF_COST; root_best_seg<=3'd0; root_best_count<=3'd0;
                        root_cand_valid<=1'b0;
                        next_count<=3'd0; next_j_flat<=28'd0; root_cost<=11'd0; root_segment_count<=3'd0;
                        for (si=0; si<9; si=si+1) begin
                            f_pipe_valid[si]<=1'b0;
                            f_best_valid[si]<=1'b0;
                            f_gen_valid[si]<=1'b0;
                        end

                        if (memo_needs_clear || (policy_epoch == 8'hFF)) begin
                            // BRAM contents are not reset by rstn.  Clear once
                            // after reset as well as on epoch wrap, preventing
                            // stale-tag false hits after a soft reset.
                            policy_epoch <= 8'd1;
                            clear_ctr <= 14'd0;
                            memo_needs_clear <= 1'b0;
                            fsm_state <= ST_CLEAR;
                        end else begin
                            policy_epoch <= policy_epoch + 1'b1;
                            fsm_state <= ST_BUILD;
                        end
                    end
                end

                ST_CLEAR: begin
                    // Correctness-first memo clear: once after reset and then
                    // once per epoch wrap. Later PPA work may background/overlap
                    // this clear, but baseline semantics remain exact.
                    memo_clear_en <= 1'b1;
                    memo_clear_addr <= clear_ctr;
                    if (clear_ctr == MEM_ENTRIES-1) begin
                        clear_ctr <= 14'd0;
                        fsm_state <= ST_BUILD;
                    end else begin
                        clear_ctr <= clear_ctr + 1'b1;
                    end
                end

                ST_BUILD: begin
                    // Stage 1: capture one physical-checkpoint/window value.
                    build_raw_valid_q <= build_sel_valid;
                    build_raw_value_q <= build_sel_value;
                    build_raw_idx_q <= build_idx;
                    fsm_state <= ST_BUILD_RESOLVE;
                end

                ST_BUILD_RESOLVE: begin
                    // Stage 2: register universe lookup and request-pool dedup.
                    // The previous item was fully committed before this state,
                    // preserving exactly the original sequential BUILD semantics.
                    build_found_q <= raw_found;
                    build_found_id_q <= raw_found_id;
                    build_resolved_id_q <= raw_resolved_id;
                    build_req_pool_found_q <= req_pool_found;
                    fsm_state <= ST_BUILD_COMMIT;
                end

                ST_BUILD_COMMIT: begin
                    // Stage 3: commit the captured BUILD item.  This state name
                    // was unused in the balanced PREP implementation and is
                    // repurposed only for BUILD commit; PREP semantics are unchanged.
                    if (build_raw_valid_q) begin
                        if (build_raw_idx_q >= 4)
                            req_val[build_raw_idx_q-4] <= build_raw_value_q;
                        if ((build_raw_idx_q < 4) && build_found_q) begin
                            // duplicate physical checkpoint j violates metadata invariant
                            policy_error <= 1'b1;
                            fsm_state <= ST_ABORT;
                        end else begin
                            if (!build_found_q) begin
                                if (univ_count >= U_MAX) begin
                                    policy_error <= 1'b1;
                                    fsm_state <= ST_ABORT;
                                end else begin
                                    univ_val[univ_count] <= build_raw_value_q;
                                    if (build_raw_idx_q < 4) begin
                                        case (root_init_count)
                                            0: root_init_id0 <= univ_count;
                                            1: root_init_id1 <= univ_count;
                                            2: root_init_id2 <= univ_count;
                                            default: root_init_id3 <= univ_count;
                                        endcase
                                        root_init_count <= root_init_count + 1'b1;
                                    end else begin
                                        req_id[build_raw_idx_q-4] <= univ_count;
                                    end
                                    univ_count <= univ_count + 1'b1;
                                end
                            end else begin
                                if (build_raw_idx_q < 4) begin
                                    case (root_init_count)
                                        0: root_init_id0 <= build_found_id_q;
                                        1: root_init_id1 <= build_found_id_q;
                                        2: root_init_id2 <= build_found_id_q;
                                        default: root_init_id3 <= build_found_id_q;
                                    endcase
                                    root_init_count <= root_init_count + 1'b1;
                                end else begin
                                    req_id[build_raw_idx_q-4] <= build_found_id_q;
                                end
                            end
                        end
                    end

                    // Build a deduplicated request-only pool once per solve.
                    if (build_raw_valid_q && (build_raw_idx_q >= 4) && !build_req_pool_found_q) begin
                        req_pool_id[req_pool_count] <= build_resolved_id_q;
                        req_pool_val[req_pool_count] <= build_raw_value_q;
                        req_pool_count <= req_pool_count + 1'b1;
                    end

                    if ((build_raw_idx_q == 8) && !build_commit_abort) begin
                        sp <= 4'd0;
                        f_req_idx[0] <= 4'd0;
                        f_count[0] <= root_init_count;
                        f_id0[0] <= root_init_id0; f_id1[0] <= root_init_id1;
                        f_id2[0] <= root_init_id2; f_id3[0] <= root_init_id3;
                        f_dsize[0]<=2'd0; f_dord[0]<=7'd0; f_rord[0]<=4'd0; f_gen_valid[0]<=1'b1;
                        f_best_valid[0]<=1'b0; f_best_cost[0]<=INF_COST; f_pipe_valid[0]<=1'b0;
                        fsm_state <= ST_ROOT_INIT;
                    end else if (!build_commit_abort) begin
                        build_idx <= build_raw_idx_q + 1'b1;
                        fsm_state <= ST_BUILD;
                    end
                end

                ST_ROOT_INIT: begin
                    // One settling cycle after the last universe insertion.
                    // Re-copy the root state/count because the final build-cycle
                    // nonblocking updates are now visible.
                    f_count[0] <= root_init_count;
                    f_id0[0] <= root_init_id0; f_id1[0] <= root_init_id1;
                    f_id2[0] <= root_init_id2; f_id3[0] <= root_init_id3;
                    // source_j is latched in ST_PREP, after the final root-state
                    // nonblocking updates from ST_ROOT_INIT are visible to prep_pred.
                    f_dsize[0]<=2'd0; f_dord[0]<=7'd0; f_rord[0]<=4'd0; f_gen_valid[0]<=1'b1;
                    f_pipe_valid[0]<=1'b0;
                    fsm_state <= ST_PREP_LOAD;
                end

                ST_PREP_LOAD: begin
                    actionq_valid <= 1'b0;
                    mreq_valid <= 1'b0;
                    areq_valid <= 1'b0;
                    mresp_valid <= 1'b0;
                    // Timing cut #1: snapshot only the selected recursive frame.
                    // The next PREP stages do not read f_*[sp] combinationally.
                    prep_req_idx_q <= f_req_idx[sp];
                    prep_count_q   <= f_count[sp];
                    prep_id0_q     <= f_id0[sp];
                    prep_id1_q     <= f_id1[sp];
                    prep_id2_q     <= f_id2[sp];
                    prep_id3_q     <= f_id3[sp];
                    fsm_state <= ST_PREP_PRED;
                end

                ST_PREP_PRED: begin
                    // Timing cut #2: qualify checkpoint values and capture them
                    // before the predecessor max-tree.  Eligibility/keep remain
                    // parallel and are captured in the same stage.
                    prep_j_q <= prep_j;
                    prep_jid_q <= prep_jid;
                    prep_cand0_q <= prep_cand0;
                    prep_cand1_q <= prep_cand1;
                    prep_cand2_q <= prep_cand2;
                    prep_cand3_q <= prep_cand3;
                    prep_keep_count_q <= prep_keep_count;
                    prep_keep_ids_q <= prep_keep_ids;
                    prep_elig_mask_q <= prep_elig_mask;
                    fsm_state <= ST_PREP_PACK;
                end

                ST_PREP_PACK: begin
                    // Only the balanced 4->2->1 max-tree remains in this cycle.
                    // The selected predecessor is consumed by ST_PREP.
                    prep_pred_q <= prep_pred_from_q;
                    fsm_state <= ST_PREP;
                end

                ST_PREP: begin
                    // Install the fully registered frame-invariant context.
                    if (sp == 0)
                        source_j <= prep_pred_q;
                    f_ctx_j[sp] <= prep_j_q;
                    f_ctx_jid[sp] <= prep_jid_q;
                    f_ctx_pred[sp] <= prep_pred_q;
                    // j and predecessor were registered in ST_PREP_PRED, so
                    // the immediate-distance subtract now occupies this already
                    // existing stage rather than extending the predecessor tree.
                    f_ctx_imm[sp] <= prep_j_q - prep_pred_q;
                    f_ctx_extra_count[sp] <= prep_extra_count;
                    f_ctx_extra_ids[sp] <= prep_extra_ids;
                    f_ctx_keep_count[sp] <= prep_keep_count_q;
                    f_ctx_keep_ids[sp] <= prep_keep_ids_q;

                    a_req_idx <= prep_req_idx_q;
                    a_ctx_j <= prep_j_q; a_ctx_jid <= prep_jid_q;
                    a_ctx_pred <= prep_pred_q; a_ctx_imm <= prep_j_q - prep_pred_q;
                    a_ctx_extra_count <= prep_extra_count; a_ctx_extra_ids <= prep_extra_ids;
                    a_ctx_keep_count <= prep_keep_count_q; a_ctx_keep_ids <= prep_keep_ids_q;
                    a_dsize <= 2'd0; a_dmask <= 9'd0;
                    f_dsize[sp] <= 2'd0;
                    f_dmask[sp] <= 9'd0;
                    if (prep_keep_count_q < 3) begin
                        f_rsize[sp] <= prep_keep_count_q;
                        a_rsize <= prep_keep_count_q;
                    end else begin
                        f_rsize[sp] <= 3;
                        a_rsize <= 3;
                    end
                    if (prep_keep_count_q < 3) begin
                        f_rmask[sp] <= first_comb9(prep_keep_count_q);
                        a_rmask <= first_comb9(prep_keep_count_q);
                    end else begin
                        f_rmask[sp] <= first_comb9(3);
                        a_rmask <= first_comb9(3);
                    end
                    f_gen_valid[sp] <= 1'b1;
                    a_gen_valid <= 1'b1;
                    fsm_state <= ST_RUN;
                end

                ST_RUN: begin
                    if ((ACTION_LIMIT != 0) && (act_ctr >= ACTION_LIMIT)) begin
                        policy_error <= 1'b1;
                        actionq_valid <= 1'b0;
                        mreq_valid <= 1'b0;
                        areq_valid <= 1'b0;
                        mresp_valid <= 1'b0;
                        pvalq_valid <= 1'b0;
                        pmeta_valid <= 1'b0;
                        fvalq_valid <= 1'b0;
                        fsm_state <= ST_ABORT;
                    end else if (top_terminal) begin
                        actionq_valid <= 1'b0;
                        mreq_valid <= 1'b0;
                        areq_valid <= 1'b0;
                        mresp_valid <= 1'b0;
                        if (a_gen_valid) begin
                            f_pipe_imm[sp] <= a_ctx_imm;
                            eval_total = {4'd0,a_ctx_imm};
                            if (sp == 0) begin
                                // root can never be terminal for the configured H6 window
                            end else if (!f_best_valid[sp] || (eval_total < f_best_cost[sp])) begin
                                f_best_valid[sp] <= 1'b1;
                                f_best_cost[sp] <= eval_total;
                            end
                            advance_generator;
                            act_ctr <= act_ctr + 1'b1;
                        end else begin
                            fsm_state <= ST_FINISH;
                        end
                    end else begin
                        // Four registered boundaries on the hot memo path:
                        //   mask select/compact -> actionq(raw IDs)
                        //   canonical ID sort   -> mreq(sorted IDs)
                        //   rank/address        -> areq(registered address)
                        //   RAMB36 read         -> mresp(data)
                        // All stages accept one action per cycle.
                        mresp_valid <= areq_valid;
                        areq_valid <= mreq_valid;
                        mreq_valid <= actionq_valid;
                        actionq_valid <= 1'b0;

                        if (areq_valid) begin
                            a_pipe_child_count <= areq_child_count;
                            a_pipe_cid0 <= areq_id0; a_pipe_cid1 <= areq_id1;
                            a_pipe_cid2 <= areq_id2; a_pipe_cid3 <= areq_id3;
                            a_pipe_imm <= areq_imm;
                            a_pipe_pred <= areq_pred;
                            a_pipe_j <= areq_j;
                            mresp_pre_dsize <= areq_pre_dsize;
                            mresp_pre_dmask <= areq_pre_dmask;
                            mresp_pre_rsize <= areq_pre_rsize;
                            mresp_pre_rmask <= areq_pre_rmask;
                            mresp_pre_gen_valid <= areq_pre_gen_valid;
                        end

                        if (mreq_valid) begin
                            areq_addr <= mreq_addr;
                            areq_child_count <= mreq_child_count;
                            areq_id0 <= mreq_id0; areq_id1 <= mreq_id1;
                            areq_id2 <= mreq_id2; areq_id3 <= mreq_id3;
                            areq_imm <= mreq_imm;
                            areq_pred <= mreq_pred;
                            areq_j <= mreq_j;
                            areq_pre_dsize <= mreq_pre_dsize;
                            areq_pre_dmask <= mreq_pre_dmask;
                            areq_pre_rsize <= mreq_pre_rsize;
                            areq_pre_rmask <= mreq_pre_rmask;
                            areq_pre_gen_valid <= mreq_pre_gen_valid;
                        end

                        if (actionq_valid) begin
                            // Esort capture.  The fixed-depth canonical sort
                            // starts only from actionq_* FFs, so a_dmask is no
                            // longer in the mreq_raw* timing cone.
                            mreq_stage         <= actionq_stage;
                            mreq_child_count   <= action_child_count;
                            mreq_raw0          <= action_id0;
                            mreq_raw1          <= action_id1;
                            mreq_raw2          <= action_id2;
                            mreq_raw3          <= action_id3;
                            mreq_imm           <= actionq_imm;
                            mreq_pred          <= actionq_pred;
                            mreq_j             <= actionq_j;
                            mreq_pre_dsize     <= actionq_pre_dsize;
                            mreq_pre_dmask     <= actionq_pre_dmask;
                            mreq_pre_rsize     <= actionq_pre_rsize;
                            mreq_pre_rmask     <= actionq_pre_rmask;
                            mreq_pre_gen_valid <= actionq_pre_gen_valid;
                        end

                        if (mresp_valid && !memo_pipe_hit) begin
                            // Memo miss commits this action.  Drop all younger
                            // speculative pipeline requests and restore the parent
                            // generator to this action's pre-state.
                            miss_ctr <= miss_ctr + 1'b1;
                            act_ctr <= act_ctr + 1'b1;
                            actionq_valid <= 1'b0;
                            mreq_valid <= 1'b0;
                            areq_valid <= 1'b0;
                            mresp_valid <= 1'b0;
                            if (sp >= 8) begin
                                policy_error <= 1'b1;
                                fsm_state <= ST_ABORT;
                            end else begin
                                f_pipe_valid[sp] <= 1'b1;
                                f_pipe_child_count[sp] <= a_pipe_child_count;
                                f_pipe_cid0[sp] <= a_pipe_cid0; f_pipe_cid1[sp] <= a_pipe_cid1;
                                f_pipe_cid2[sp] <= a_pipe_cid2; f_pipe_cid3[sp] <= a_pipe_cid3;
                                f_pipe_imm[sp] <= a_pipe_imm;
                                f_pipe_pred[sp] <= a_pipe_pred;
                                f_pipe_j[sp] <= a_pipe_j;
                                f_dsize[sp] <= mresp_pre_dsize;
                                f_dmask[sp] <= mresp_pre_dmask;
                                f_rsize[sp] <= mresp_pre_rsize;
                                f_rmask[sp] <= mresp_pre_rmask;
                                f_gen_valid[sp] <= mresp_pre_gen_valid;

                                sp <= sp + 1'b1;
                                f_req_idx[sp+1] <= f_req_idx[sp] + 1'b1;
                                f_count[sp+1] <= a_pipe_child_count;
                                f_id0[sp+1] <= a_pipe_cid0; f_id1[sp+1] <= a_pipe_cid1;
                                f_id2[sp+1] <= a_pipe_cid2; f_id3[sp+1] <= a_pipe_cid3;
                                f_dsize[sp+1]<=2'd0; f_dord[sp+1]<=7'd0; f_rord[sp+1]<=4'd0;
                                f_gen_valid[sp+1]<=1'b1;
                                f_best_valid[sp+1]<=1'b0; f_best_cost[sp+1]<=INF_COST;
                                f_pipe_valid[sp+1]<=1'b0;

                                // Hot miss path: the child state is already in
                                // registered a_pipe_* metadata.  Seed PREP from
                                // it directly instead of writing f_*[sp+1] and
                                // spending another cycle reading it back through
                                // ST_PREP_LOAD.  Root/init still use PREP_LOAD.
                                prep_req_idx_q <= f_req_idx[sp] + 1'b1;
                                prep_count_q   <= a_pipe_child_count;
                                prep_id0_q     <= a_pipe_cid0;
                                prep_id1_q     <= a_pipe_cid1;
                                prep_id2_q     <= a_pipe_cid2;
                                prep_id3_q     <= a_pipe_cid3;
                                fsm_state <= ST_PREP_PRED;
                            end
                        end else begin
                            if (mresp_valid && memo_pipe_hit) begin
                                hit_ctr <= hit_ctr + 1'b1;
                                act_ctr <= act_ctr + 1'b1;
                                eval_pending({1'b0,memo_rd_data[9:0]});
                            end

                            if (can_issue_memo_action) begin
                                capture_current_action_to_actionq;
                            end else if (!a_gen_valid && !actionq_valid && !mreq_valid && !areq_valid && !mresp_valid &&
                                         !pvalq_valid && !pmeta_valid && !fvalq_valid) begin
                                if (sp == 0) fsm_state <= ST_ROOT_DRAIN;
                                else         fsm_state <= ST_FINISH;
                            end
                        end
                    end
                end

                ST_RETURN: begin
                    // A memo miss child has just been solved. Restore the hot
                    // parent-frame mirror and its preserved pending action.
                    // Evaluation occurs in ST_RETURN_EVAL after these NBAs are
                    // visible, removing the sp-indexed pending mux from timing.
                    a_req_idx <= f_req_idx[sp];
                    a_ctx_j <= f_ctx_j[sp]; a_ctx_jid <= f_ctx_jid[sp];
                    a_ctx_pred <= f_ctx_pred[sp]; a_ctx_imm <= f_ctx_imm[sp];
                    a_ctx_extra_count <= f_ctx_extra_count[sp]; a_ctx_extra_ids <= f_ctx_extra_ids[sp];
                    a_ctx_keep_count <= f_ctx_keep_count[sp]; a_ctx_keep_ids <= f_ctx_keep_ids[sp];
                    a_dsize <= f_dsize[sp]; a_dmask <= f_dmask[sp];
                    a_rsize <= f_rsize[sp]; a_rmask <= f_rmask[sp];
                    a_gen_valid <= f_gen_valid[sp];
                    a_pipe_child_count <= f_pipe_child_count[sp];
                    a_pipe_cid0 <= f_pipe_cid0[sp]; a_pipe_cid1 <= f_pipe_cid1[sp];
                    a_pipe_cid2 <= f_pipe_cid2[sp]; a_pipe_cid3 <= f_pipe_cid3[sp];
                    a_pipe_imm <= f_pipe_imm[sp];
                    a_pipe_pred <= f_pipe_pred[sp];
                    a_pipe_j <= f_pipe_j[sp];
                    fsm_state <= ST_RETURN_EVAL;
                end

                ST_RETURN_EVAL: begin
                    // The parent was restored to the missed action's pre-state.
                    // Commit that action exactly once after the child returns.
                    eval_pending(return_cost);
                    f_pipe_valid[sp] <= 1'b0;
                    advance_generator;
                    actionq_valid <= 1'b0;
                    mreq_valid <= 1'b0;
                    areq_valid <= 1'b0;
                    mresp_valid <= 1'b0;
                    fsm_state <= ST_RUN;
                end

                ST_ROOT_DRAIN: begin
                    // Drain E0/E1/E2 plus the final root-candidate reducer.
                    if (!pvalq_valid && !pmeta_valid && !root_cand_valid && !fvalq_valid)
                        fsm_state <= ST_FINISH;
                end

                ST_FINISH: begin
                    if (sp == 0) begin
                        if (!root_best_valid) begin
                            policy_error <= 1'b1;
                            fsm_state <= ST_ABORT;
                        end else begin
                            root_cost <= root_best_cost;
                            root_segment_count <= root_best_seg;
                            next_count <= root_best_count;
                            next_j_flat <= 28'd0;
                            if (root_best_count > 0) next_j_flat[0*`GP_J_W +: `GP_J_W] <= root_best_v0;
                            if (root_best_count > 1) next_j_flat[1*`GP_J_W +: `GP_J_W] <= root_best_v1;
                            if (root_best_count > 2) next_j_flat[2*`GP_J_W +: `GP_J_W] <= root_best_v2;
                            if (root_best_count > 3) next_j_flat[3*`GP_J_W +: `GP_J_W] <= root_best_v3;

                            busy <= 1'b0;
                            done <= 1'b1;
                            policy_cycles_last <= cyc_ctr + 1'b1;
                            policy_actions_last <= act_ctr;
                            policy_memo_hit_last <= hit_ctr;
                            policy_memo_miss_last <= miss_ctr;
                            policy_cycles_total <= policy_cycles_total + cyc_ctr + 1'b1;
                            policy_actions_total <= policy_actions_total + act_ctr;
                            if ((cyc_ctr + 1'b1) > policy_max_latency)
                                policy_max_latency <= cyc_ctr + 1'b1;
                            fsm_state <= ST_IDLE;
                        end
                    end else begin
                        if (!f_best_valid[sp]) begin
                            policy_error <= 1'b1;
                            fsm_state <= ST_ABORT;
                        end else begin
                            // Future-only memo write: stage=req_idx-1.
                            memo_wr_en <= 1'b1;
                            memo_wr_addr <= memo_addr_of(f_req_idx[sp]-1'b1,
                                rank_state(f_count[sp],f_id0[sp],f_id1[sp],f_id2[sp],f_id3[sp]));
                            memo_wr_data <= {policy_epoch,f_best_cost[sp][9:0]};
                            return_cost <= f_best_cost[sp];
                            sp <= sp - 1'b1;
                            fsm_state <= ST_RETURN;
                        end
                    end
                end

                ST_ABORT: begin
                    actionq_valid <= 1'b0;
                    mreq_valid <= 1'b0;
                    areq_valid <= 1'b0;
                    mresp_valid <= 1'b0;
                    fvalq_valid <= 1'b0;
                    busy <= 1'b0;
                    done <= 1'b1;
                    policy_cycles_last <= cyc_ctr + 1'b1;
                    policy_actions_last <= act_ctr;
                    policy_memo_hit_last <= hit_ctr;
                    policy_memo_miss_last <= miss_ctr;
                    fsm_state <= ST_IDLE;
                end

                default: begin
                    policy_error <= 1'b1;
                    fsm_state <= ST_ABORT;
                end
            endcase
        end
    end
endmodule

//------------------------------------------------------------------------------
// Shadow-J failure-continuation generator.
//
// Input state is the REAL J-LFSR state *after* the current j draw has fully
// consumed its accepted/rejected candidates. The module works only on a copy.
// round_after_current/L_after_current/trial_after_current describe the logical
// BBHT state after accounting the current requested j.
//
// For each future failure-continuation request:
//   if current BBHT instance is complete => round/L/trial reset, J stream kept
//   draw candidate from PRE-DRAW copied state
//   jump copied state by 7 ordinary steps for every candidate, reject included
//------------------------------------------------------------------------------
// A completed BBHT context is recognized from registered
// r/L/trial at the beginning of the next busy cycle.  That cycle is a no-draw
// context-reset bubble: the copied J RNG state is not advanced.  This keeps the
// This removes candidate-to-restart combinational feedback while preserving sequence semantics.
module grover_shadow_j (
    input  wire                         clk,
    input  wire                         rstn,
    input  wire                         start,
    input  wire [31:0]                  post_j_state,
    input  wire [`GP_RROM_IDX_W-1:0]   round_after_current,
    input  wire [31:0]                  L_after_current,
    input  wire [`GP_SHOT_CAP_W-1:0]   trial_after_current,

    output reg                          busy,
    output reg                          done,
    output reg  [8*`GP_J_W-1:0]        future_j_flat,
    output reg  [31:0]                  shadow_state_final,
    output reg  [`GP_RROM_IDX_W-1:0]   round_final,
    output reg  [31:0]                  L_final,
    output reg  [`GP_SHOT_CAP_W-1:0]   trial_final,
    output reg  [15:0]                  candidate_draws
);
    function [31:0] lfsr_step1;
        input [31:0] s;
        reg fb;
        begin
            fb = s[31] ^ s[21] ^ s[1] ^ s[0];
            lfsr_step1 = {s[30:0],fb};
        end
    endfunction
    function [31:0] lfsr_jump7;
        input [31:0] s;
        integer i;
        reg [31:0] t;
        begin
            t=s;
            for (i=0;i<7;i=i+1) t=lfsr_step1(t);
            lfsr_jump7=t;
        end
    endfunction
    function [7:0] mbound_of;
        input [`GP_RROM_IDX_W-1:0] r;
        begin
            case (r)
                5'd0:mbound_of=`GP_MBOUND_00;
                5'd1:mbound_of=`GP_MBOUND_01; 5'd2:mbound_of=`GP_MBOUND_02;
                5'd3:mbound_of=`GP_MBOUND_03; 5'd4:mbound_of=`GP_MBOUND_04;
                5'd5:mbound_of=`GP_MBOUND_05; 5'd6:mbound_of=`GP_MBOUND_06;
                5'd7:mbound_of=`GP_MBOUND_07; 5'd8:mbound_of=`GP_MBOUND_08;
                5'd9:mbound_of=`GP_MBOUND_09; 5'd10:mbound_of=`GP_MBOUND_10;
                5'd11:mbound_of=`GP_MBOUND_11; 5'd12:mbound_of=`GP_MBOUND_12;
                5'd13:mbound_of=`GP_MBOUND_13; 5'd14:mbound_of=`GP_MBOUND_14;
                5'd15:mbound_of=`GP_MBOUND_15; 5'd16:mbound_of=`GP_MBOUND_16;
                5'd17:mbound_of=`GP_MBOUND_17; 5'd18:mbound_of=`GP_MBOUND_18;
                5'd19:mbound_of=`GP_MBOUND_19; 5'd20:mbound_of=`GP_MBOUND_20;
                5'd21:mbound_of=`GP_MBOUND_21; 5'd22:mbound_of=`GP_MBOUND_22;
                5'd23:mbound_of=`GP_MBOUND_23; 5'd24:mbound_of=`GP_MBOUND_24;
                5'd25:mbound_of=`GP_MBOUND_25; 5'd26:mbound_of=`GP_MBOUND_26;
                default:mbound_of=`GP_MBOUND_27;
            endcase
        end
    endfunction
    function [7:0] mask_for_m;
        input [7:0] m;
        reg [7:0] x;
        begin
            if (m<=1) mask_for_m=8'd0;
            else begin
                x=m-1'b1;
                if (x[7]) mask_for_m=8'hFF;
                else if (x[6]) mask_for_m=8'h7F;
                else if (x[5]) mask_for_m=8'h3F;
                else if (x[4]) mask_for_m=8'h1F;
                else if (x[3]) mask_for_m=8'h0F;
                else if (x[2]) mask_for_m=8'h07;
                else if (x[1]) mask_for_m=8'h03;
                else mask_for_m=8'h01;
            end
        end
    endfunction

    reg [31:0] s;
    reg [`GP_RROM_IDX_W-1:0] r;
    reg [31:0] L;
    reg [`GP_SHOT_CAP_W-1:0] trial;
    reg [3:0] out_idx;

    // Registered restart boundary:
    // Restart is detected from the already-registered BBHT context at the
    // beginning of the next busy cycle.  A boundary-crossing accepted draw
    // therefore commits r/L/trial first; the following cycle is a no-draw
    // context-reset bubble.  RNG state s is untouched in that bubble.
    //
    // This preserves the intended sequence while removing the
    // candidate -> L_after_accept -> restart_pending.D path.
    wire context_restart_now =
        (trial >= `GP_SHOT_CAP_DEFAULT) ||
        ((32'd1 + L) >= `GP_BBHT_BUDGET);

    reg [7:0] mb;
    reg [7:0] cand8;
    reg accept;
    reg [31:0] s_next;
    reg [`GP_RROM_IDX_W-1:0] r_after_accept;
    reg [31:0] L_after_accept;
    reg [`GP_SHOT_CAP_W-1:0] trial_after_accept;

    always @* begin
        mb=mbound_of(r);
        cand8=s[7:0] & mask_for_m(mb);
        accept=(mb!=0) && (cand8<mb);
        s_next=lfsr_jump7(s);

        if (r >= `GP_RROM_LAST_IDX)
            r_after_accept = `GP_RROM_LAST_IDX;
        else
            r_after_accept = r + 1'b1;

        L_after_accept = L + cand8;
        trial_after_accept = trial + 1'b1;
    end

    always @(posedge clk) begin
        if (!rstn) begin
            busy<=1'b0; done<=1'b0; future_j_flat<={(8*`GP_J_W){1'b0}};
            s<=32'd0; r<=0; L<=0; trial<=0; out_idx<=0;
            shadow_state_final<=0; round_final<=0; L_final<=0; trial_final<=0;
            candidate_draws<=0;
        end else begin
            done<=1'b0;
            if (start && !busy) begin
                busy<=1'b1;
                future_j_flat<={(8*`GP_J_W){1'b0}};
                s<=post_j_state;
                r<=round_after_current;
                L<=L_after_current;
                trial<=trial_after_current;
                out_idx<=0;
                candidate_draws<=0;
            end else if (busy) begin
                if (context_restart_now) begin
                    // Dedicated no-draw context-reset bubble.
                    // Keep s and candidate_draws unchanged so the next cycle
                    // sees the identical pre-draw RNG state under (r,L,trial)=0.
                    r<= {`GP_RROM_IDX_W{1'b0}};
                    L<= 32'd0;
                    trial<= {`GP_SHOT_CAP_W{1'b0}};
                end else begin
                    // Every candidate, accepted or rejected, consumes jump7.
                    s<=s_next;
                    candidate_draws<=candidate_draws+1'b1;
                    if (accept) begin
                        future_j_flat[out_idx*`GP_J_W +: `GP_J_W] <= cand8[`GP_J_W-1:0];
                        r <= r_after_accept;
                        L <= L_after_accept;
                        trial <= trial_after_accept;
                        if (out_idx == 6) begin
                            busy<=1'b0;
                            done<=1'b1;
                            shadow_state_final<=s_next;
                            round_final<=r_after_accept;
                            L_final<=L_after_accept;
                            trial_final<=trial_after_accept;
                        end else begin
                            out_idx<=out_idx+1'b1;
                        end
                    end
                end
            end
        end
    end

endmodule

//------------------------------------------------------------------------------
// Plan FIFO.  The entry is intentionally policy/logical, not physical-slot.
// Packed layout (LSB first):
//   oracle_epoch[7:0], expected_j[6:0], input_S_count[2:0], input_S_flat[27:0],
//   source_j[6:0], next_count[2:0], next_flat[27:0], root_cost[10:0], segment[2:0]
//------------------------------------------------------------------------------
module grover_ckpt_plan_fifo #(
    parameter integer DEPTH = 4,
    parameter integer PTR_W = 2
) (
    input  wire                         clk,
    input  wire                         rstn,
    input  wire                         flush,

    input  wire                         push,
    input  wire [7:0]                   push_oracle_epoch,
    input  wire [`GP_J_W-1:0]           push_expected_j,
    input  wire [2:0]                   push_input_s_count,
    input  wire [4*`GP_J_W-1:0]         push_input_s_flat,
    input  wire [`GP_J_W-1:0]           push_source_j,
    input  wire [2:0]                   push_next_count,
    input  wire [4*`GP_J_W-1:0]         push_next_flat,
    input  wire [10:0]                  push_root_cost,
    input  wire [2:0]                   push_segment_count,

    input  wire                         pop,
    input  wire                         demand,

    output wire                         empty,
    output wire                         full,
    output reg  [PTR_W:0]               level,
    output reg  [PTR_W:0]               highwater,
    output reg  [31:0]                  empty_on_demand_count,

    output wire [7:0]                   head_oracle_epoch,
    output wire [`GP_J_W-1:0]           head_expected_j,
    output wire [2:0]                   head_input_s_count,
    output wire [4*`GP_J_W-1:0]         head_input_s_flat,
    output wire [`GP_J_W-1:0]           head_source_j,
    output wire [2:0]                   head_next_count,
    output wire [4*`GP_J_W-1:0]         head_next_flat,
    output wire [10:0]                  head_root_cost,
    output wire [2:0]                   head_segment_count
);
    localparam integer ENTRY_W = 98;
    reg [ENTRY_W-1:0] mem [0:DEPTH-1];
    reg [PTR_W-1:0] wptr, rptr;
    wire [ENTRY_W-1:0] push_entry = {
        push_segment_count,
        push_root_cost,
        push_next_flat,
        push_next_count,
        push_source_j,
        push_input_s_flat,
        push_input_s_count,
        push_expected_j,
        push_oracle_epoch
    };
    wire [ENTRY_W-1:0] head = mem[rptr];

    assign empty = (level == 0);
    assign full  = (level == DEPTH);

    assign head_oracle_epoch  = head[7:0];
    assign head_expected_j    = head[14:8];
    assign head_input_s_count = head[17:15];
    assign head_input_s_flat  = head[45:18];
    assign head_source_j      = head[52:46];
    assign head_next_count    = head[55:53];
    assign head_next_flat     = head[83:56];
    assign head_root_cost     = head[94:84];
    assign head_segment_count = head[97:95];

    always @(posedge clk) begin
        if (!rstn) begin
            wptr<=0; rptr<=0; level<=0; highwater<=0;
            empty_on_demand_count<=0;
        end else if (flush) begin
            // Flush invalidates queued speculative plans, but observability
            // counters remain cumulative across Oracle epochs.
            wptr<=0; rptr<=0; level<=0;
        end else begin
            if (demand && empty)
                empty_on_demand_count <= empty_on_demand_count + 1'b1;

            case ({push && !full, pop && !empty})
                2'b10: begin
                    mem[wptr] <= push_entry;
                    wptr <= (wptr == DEPTH-1) ? {PTR_W{1'b0}} : wptr + 1'b1;
                    level <= level + 1'b1;
                    if ((level + 1'b1) > highwater)
                        highwater <= level + 1'b1;
                end
                2'b01: begin
                    rptr <= (rptr == DEPTH-1) ? {PTR_W{1'b0}} : rptr + 1'b1;
                    level <= level - 1'b1;
                end
                2'b11: begin
                    mem[wptr] <= push_entry;
                    wptr <= (wptr == DEPTH-1) ? {PTR_W{1'b0}} : wptr + 1'b1;
                    rptr <= (rptr == DEPTH-1) ? {PTR_W{1'b0}} : rptr + 1'b1;
                end
                default: begin end
            endcase
        end
    end
endmodule
