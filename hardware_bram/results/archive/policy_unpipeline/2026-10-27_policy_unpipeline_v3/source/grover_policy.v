//==============================================================================
// grover_policy.v
// BBHT/Grover checkpoint policy RTL -- Phase 5 policy/speculation bundle
// Date: 2026-08-30
// 2026-09-06: parameterized K/H for E4 K3/H3 experiment; K4/H4 defaults preserved.
// 2026-10-27: remove the policy timing-only BUILD/PREP/evaluation registers.
// Keep the synchronous memo read alignment and the full-horizon bound stages,
// which carry architectural transactions rather than delaying control for WNS.
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
// Future-only policy memo.
//
// The production K3/H3 configuration can only create universe IDs 0..6 and
// child sets of size at most three.  With the frozen rank_state() encoding its
// largest reachable rank is therefore 126.  COMPACT_K3H3 stores the three
// 127-rank stages in one 512x18 block RAM instead of keeping the legacy four
// 2,048x18 banks.  Other K/H configurations retain the proven legacy layout.
//------------------------------------------------------------------------------
module grover_ckpt_policy_memo #(
    parameter COMPACT_K3H3 = 1'b0,
    // The legacy rank stride is 1,093.  H=8 therefore needs 8,744 words,
    // which is larger than four 2,048-word banks.  Keep the proven four-bank
    // layout for smaller horizons and elaborate the fifth bank only when the
    // caller's address range actually needs it.
    parameter FIVE_BANKS = 1'b0
) (
    input  wire         clk,

    input  wire         rd_en,
    input  wire [13:0]  rd_addr,
    output wire [17:0]  rd_data,

    input  wire         wr_en,
    input  wire [13:0]  wr_addr,
    input  wire [17:0]  wr_data,

    input  wire         clear_en,
    input  wire [13:0]  clear_addr
);
    wire [13:0] eff_wr_addr = clear_en ? clear_addr : wr_addr;
    wire [17:0] eff_wr_data = clear_en ? 18'd0 : wr_data;
    wire        eff_wr_en   = clear_en | wr_en;

`ifndef SYNTHESIS
    // The compact RAM deliberately drops address bits [13:9].  Fail loudly in
    // simulation if a later rank/layout change violates the proven 0..380
    // live range instead of silently aliasing an out-of-range entry.
    always @(posedge clk) begin
        if ((COMPACT_K3H3 != 0) && rd_en && (rd_addr > 14'd380))
            $error("compact policy memo read address out of range: %0d", rd_addr);
        if ((COMPACT_K3H3 != 0) && eff_wr_en && (eff_wr_addr > 14'd380))
            $error("compact policy memo write address out of range: %0d", eff_wr_addr);
    end
`endif

    generate
        if (COMPACT_K3H3 != 0) begin : g_compact_k3h3
            // Three stages x 127 address slots = 381 live words.  A power-of-two
            // physical depth keeps inference simple; addresses 381..511 are
            // unreachable and therefore do not need clearing.
            (* ram_style = "block" *) reg [17:0] mem [0:511];
            reg [17:0] q;

            always @(posedge clk) begin
                if (rd_en)
                    q <= mem[rd_addr[8:0]];
                if (eff_wr_en)
                    mem[eff_wr_addr[8:0]] <= eff_wr_data;
            end

            assign rd_data = q;
        end else if (FIVE_BANKS != 0) begin : g_legacy5
            (* ram_style = "block" *) reg [17:0] mem0 [0:2047];
            (* ram_style = "block" *) reg [17:0] mem1 [0:2047];
            (* ram_style = "block" *) reg [17:0] mem2 [0:2047];
            (* ram_style = "block" *) reg [17:0] mem3 [0:2047];
            (* ram_style = "block" *) reg [17:0] mem4 [0:2047];

            reg [17:0] q0, q1, q2, q3, q4;
            reg [2:0]  rd_bank_q;
            reg [17:0] rd_data_mux;
            wire [2:0]  rd_bank = rd_addr[13:11];
            wire [2:0]  wr_bank = eff_wr_addr[13:11];
            wire [10:0] rd_row  = rd_addr[10:0];
            wire [10:0] wr_row  = eff_wr_addr[10:0];

            always @(posedge clk) begin
                if (rd_en) begin
                    rd_bank_q <= rd_bank;
                    q0 <= mem0[rd_row];
                    q1 <= mem1[rd_row];
                    q2 <= mem2[rd_row];
                    q3 <= mem3[rd_row];
                    q4 <= mem4[rd_row];
                end
                if (eff_wr_en) begin
                    case (wr_bank)
                        3'd0: mem0[wr_row] <= eff_wr_data;
                        3'd1: mem1[wr_row] <= eff_wr_data;
                        3'd2: mem2[wr_row] <= eff_wr_data;
                        3'd3: mem3[wr_row] <= eff_wr_data;
                        3'd4: mem4[wr_row] <= eff_wr_data;
                        default: mem4[wr_row] <= eff_wr_data;
                    endcase
                end
            end

            always @* begin
                case (rd_bank_q)
                    3'd0: rd_data_mux = q0;
                    3'd1: rd_data_mux = q1;
                    3'd2: rd_data_mux = q2;
                    3'd3: rd_data_mux = q3;
                    3'd4: rd_data_mux = q4;
                    default: rd_data_mux = q4;
                endcase
            end

            assign rd_data = rd_data_mux;
        end else begin : g_legacy4
            // Four explicit 2,048x18 banks preserve the frozen K4/H4 layout.
            // Reading every bank keeps address decode away from the RAMB36 EN
            // path; the registered bank tag selects the returned word.
            (* ram_style = "block" *) reg [17:0] mem0 [0:2047];
            (* ram_style = "block" *) reg [17:0] mem1 [0:2047];
            (* ram_style = "block" *) reg [17:0] mem2 [0:2047];
            (* ram_style = "block" *) reg [17:0] mem3 [0:2047];

            reg [17:0] q0, q1, q2, q3;
            reg [2:0]  rd_bank_q;
            reg [17:0] rd_data_mux;
            wire [2:0]  rd_bank = rd_addr[13:11];
            wire [2:0]  wr_bank = eff_wr_addr[13:11];
            wire [10:0] rd_row  = rd_addr[10:0];
            wire [10:0] wr_row  = eff_wr_addr[10:0];

            always @(posedge clk) begin
                if (rd_en) begin
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
                    3'd0: rd_data_mux = q0;
                    3'd1: rd_data_mux = q1;
                    3'd2: rd_data_mux = q2;
                    3'd3: rd_data_mux = q3;
                    default: rd_data_mux = q3;
                endcase
            end

            assign rd_data = rd_data_mux;
        end
    endgenerate
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
    parameter integer ACTION_LIMIT = 0,
    // Method 1: exact one-step branch-and-bound.  A memo miss descends only
    // when the current action can still beat the frame incumbent.  This does
    // not change the restricted-B action set, objective, or root tie-break.
    // Disabled by default until the stronger seed-first/deeper-bound version
    // removes the H8 repeated-miss regression measured by method-1 study.
    //
    // EXACT_PRUNE=5 is that stronger version: seed-first exact DFS with the
    // full-horizon capacity-relaxed lower bound (experiment 24).  Every frame
    // first scans all legal children through a registered H-stage bound
    // pipeline, evaluates the child with the smallest bound exactly, and then
    // walks the canonical action order pruning every child whose bound cannot
    // beat the incumbent.  Only the search order and the set of evaluated
    // children change; action space, objective and root tie-break do not.
    parameter integer EXACT_PRUNE  = 0,
    // Default parameters preserve the frozen K4/H4 behavior.  The E4/K3H3
    // branch overrides these to CKPT_K=3, H_FUTURE=3.
    parameter integer CKPT_K       = 4,
    parameter integer H_FUTURE     = 4
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
    localparam integer WINDOW_LEN  = H_FUTURE + 1; // current + future requests
    localparam integer U_MAX       = CKPT_K + WINDOW_LEN;
    localparam COMPACT_K3H3 = (CKPT_K == 3) && (H_FUTURE == 3);
    // K3/H3 only visits count<=3 and IDs<7, so rank 126 is its exact maximum.
    // Other parameter sets retain the legacy 1,093-rank stride unchanged.
    localparam integer STATE_RANKS = COMPACT_K3H3 ? 127 : 1093;
    localparam integer MEM_ENTRIES = H_FUTURE * STATE_RANKS;
    localparam [10:0] INF_COST     = 11'h7FF;

    // Seed-first full-bound search (EXACT_PRUNE=5).  UB is the number of
    // distinct values a solve can hold (K checkpoints + H+1 requests); the
    // bound pipeline works on UB-bit masks indexed by sorted-value rank.
    localparam SEED_MODE = (EXACT_PRUNE == 5) || (EXACT_PRUNE == 6);
    // EXACT_PRUNE=6 adds one shortcut on top of mode 5: when the current
    // request has a single legal action, that action is the decision and the
    // subtree below it is not searched.  source_j / next_count / next_j_flat
    // are unchanged.  root_cost then reports the relaxed lower bound
    // (immediate + bound) instead of the exact DP cost; root_cost and
    // root_segment_count are latched by the Main IP but never read.
    localparam ROOT_FORCED = (EXACT_PRUNE == 6);
    localparam integer UB = U_MAX;
    // Per-frame search phase.  SCAN feeds every legal child through the bound
    // pipeline only to find the seed; SEED evaluates that one child exactly;
    // CANON is the canonical action walk with bound pruning.
    localparam [1:0] PH_SCAN  = 2'd0,
                     PH_SEED  = 2'd1,
                     PH_CANON = 2'd2;

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
            if (COMPACT_K3H3) begin
                case (stage)
                    3'd0: base = 14'd0;
                    3'd1: base = 14'd127;
                    default: base = 14'd254;
                endcase
            end else begin
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
            end
            memo_addr_of = base + rank;
        end
    endfunction

    // Rank-space mask helpers for the seed-first bound pipeline.  Bit p of a
    // rank mask stands for the p-th smallest value of the solve universe.
    function [UB-1:0] rank_onehot;
        input [3:0] r;
        integer p;
        begin
            rank_onehot = {UB{1'b0}};
            for (p=0; p<UB; p=p+1)
                if (r == p) rank_onehot[p] = 1'b1;
        end
    endfunction

    // Ranks whose value is <= the value of rank r.
    function [UB-1:0] rank_le;
        input [3:0] r;
        integer p;
        begin
            rank_le = {UB{1'b0}};
            for (p=0; p<UB; p=p+1)
                if (p <= r) rank_le[p] = 1'b1;
        end
    endfunction

    // Ranks whose value is strictly below the value of rank r.
    function [UB-1:0] rank_lt;
        input [3:0] r;
        integer p;
        begin
            rank_lt = {UB{1'b0}};
            for (p=0; p<UB; p=p+1)
                if (p < r) rank_lt[p] = 1'b1;
        end
    endfunction

    // suffix_or[p] = OR of m[p..UB-1].  Bits where it is 0 lie strictly above
    // the highest set bit of m.
    function [UB-1:0] suffix_or;
        input [UB-1:0] m;
        integer p;
        reg acc;
        begin
            acc = 1'b0;
            for (p=UB-1; p>=0; p=p-1) begin
                acc = acc | m[p];
                suffix_or[p] = acc;
            end
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

    reg       build_sel_valid;
    reg [6:0] build_sel_value;

    reg       raw_found;
    reg [3:0] raw_found_id;
    reg       req_pool_found;
    reg [3:0] raw_resolved_id;
    integer bi;
    wire build_commit_abort = build_sel_valid &&
                              (((build_idx < 4) && raw_found) ||
                               (!raw_found && (univ_count >= U_MAX)));

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
        end else if (build_idx < (4 + WINDOW_LEN)) begin
            build_sel_valid = 1'b1;
            case (build_idx-4)
                0: build_sel_value = in_window_flat[0*`GP_J_W +: `GP_J_W];
                1: build_sel_value = in_window_flat[1*`GP_J_W +: `GP_J_W];
                2: build_sel_value = in_window_flat[2*`GP_J_W +: `GP_J_W];
                3: build_sel_value = in_window_flat[3*`GP_J_W +: `GP_J_W];
                4: build_sel_value = in_window_flat[4*`GP_J_W +: `GP_J_W];
                5: build_sel_value = in_window_flat[5*`GP_J_W +: `GP_J_W];
                6: build_sel_value = in_window_flat[6*`GP_J_W +: `GP_J_W];
                7: build_sel_value = in_window_flat[7*`GP_J_W +: `GP_J_W];
                default: build_sel_value = in_window_flat[8*`GP_J_W +: `GP_J_W];
            endcase
        end
    end

    // Resolve and commit one setup value in ST_BUILD. BUILD is outside the
    // action loop, so a separate timing-only capture/resolve pipeline only
    // added solve latency.
    always @* begin
        raw_found = 1'b0;
        raw_found_id = 4'd0;
        for (bi=0; bi<13; bi=bi+1) begin
            if ((bi < univ_count) && (univ_val[bi] == build_sel_value) && !raw_found) begin
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
    // Sorted-value rank of every universe entry (EXACT_PRUNE=5 only).
    //
    //   rk_pos[id]    rank of universe entry id (number of smaller values)
    //   rk_sval[rank] universe value at that rank
    //
    // Both are maintained incrementally while BUILD inserts entries, reusing
    // the existing capture -> resolve -> commit split: RESOLVE compares the
    // captured value with every committed entry and registers the result,
    // COMMIT then shifts ranks/values by one where the new value is smaller.
    // No extra BUILD cycle is added.  Universe values are unique, so the
    // ordering is strict and ranks are a permutation of 0..univ_count-1.
    // -------------------------------------------------------------------------
    reg [3:0]  rk_pos  [0:12];
    reg [6:0]  rk_sval [0:12];
    reg [12:0] build_lt;
    reg [3:0]  build_newpos;
    integer rk_i;

    always @* begin
        build_lt = 13'd0;
        build_newpos = 4'd0;
        for (rk_i=0; rk_i<13; rk_i=rk_i+1) begin
            if ((rk_i < univ_count) && (univ_val[rk_i] < build_sel_value)) begin
                build_lt[rk_i] = 1'b1;
                build_newpos = build_newpos + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // DFS stack. sp=0 is the non-memoized current-request root.
    // req_idx 1..H_FUTURE are memoized future stages 0..H_FUTURE-1.
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

    // PREP consumes the selected architectural frame directly. The former
    // LOAD/PRED/PACK registers existed only to split the combinational cone.
    wire [3:0] prep_req_idx = f_req_idx[sp];
    wire [2:0] prep_count = f_count[sp];
    wire [3:0] prep_id0 = f_id0[sp];
    wire [3:0] prep_id1 = f_id1[sp];
    wire [3:0] prep_id2 = f_id2[sp];
    wire [3:0] prep_id3 = f_id3[sp];

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

    reg [8:0] prep_elig_mask;
    reg [3:0] prep_extra_count;
    reg [35:0] prep_extra_ids;
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
    // EXACT_PRUNE=5: 1 = SCAN packet (bound only, never evaluated).
    reg        actionq_kind;

    // EXACT_PRUNE=5 frame phase.  f_phase[] survives recursion like the other
    // f_* frame arrays; a_phase mirrors the active frame for the hot path.
    reg [1:0]  f_phase [0:8];
    reg [1:0]  a_phase;
    // Seed found by the SCAN of the active frame.  A SCAN never descends, so
    // one copy suffices; it is consumed before the frame can recurse.
    reg        scan_valid;
    reg [10:0] scan_total;
    reg [2:0]  scan_cnt;
    reg [15:0] scan_ids;
    // scan_issued/scan_multi: the SCAN has issued one / more than one child.
    // A single-child frame needs no canonical walk after its seed.
    reg        scan_issued;
    reg        scan_multi;
    reg        f_multi [0:8];
    // Cycles left before the canonical walk may start behind the seed.
    reg [2:0]  seed_gap;

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
    reg [6:0]  areq_next_j, areq_next2_j;
    reg        areq_has_next2;
    reg [1:0]  areq_pre_dsize;
    reg [8:0]  areq_pre_dmask;
    reg [2:0]  areq_pre_rsize;
    reg [8:0]  areq_pre_rmask;
    reg        areq_pre_gen_valid;

    // EXACT_PRUNE=5 direct evaluation.  When the child's remaining window is a
    // single request, the relaxed bound equals the exact child cost, so the
    // packet rides the memo pipeline as a forced hit carrying that cost.
    reg        mreq_direct, areq_direct, mresp_direct;
    reg [9:0]  mreq_lb, areq_lb, mresp_lb;

    reg        mresp_valid;
    reg [6:0]  a_pipe_next_j, a_pipe_next2_j;
    reg        a_pipe_has_next2;
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

    // PREP predecessor/keep logic reads the selected DFS frame directly.
    always @* begin
        prep_jid = req_id[prep_req_idx];
        prep_j   = req_val[prep_req_idx];

        // Read each checkpoint value once, qualify in parallel, then take max
        // with a balanced tree.  Invalid / above-request candidates become 0.
        prep_val0 = univ_val[prep_id0];
        prep_val1 = univ_val[prep_id1];
        prep_val2 = univ_val[prep_id2];
        prep_val3 = univ_val[prep_id3];

        if ((prep_count > 0) && (prep_val0 <= prep_j)) prep_cand0 = prep_val0;
        else                                             prep_cand0 = 7'd0;
        if ((prep_count > 1) && (prep_val1 <= prep_j)) prep_cand1 = prep_val1;
        else                                             prep_cand1 = 7'd0;
        if ((prep_count > 2) && (prep_val2 <= prep_j)) prep_cand2 = prep_val2;
        else                                             prep_cand2 = 7'd0;
        if ((prep_count > 3) && (prep_val3 <= prep_j)) prep_cand3 = prep_val3;
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
        if ((prep_count > 0) && (prep_id0 != prep_jid)) begin
            prep_keep_ids[0*4 +: 4] = prep_id0; prep_keep_count = prep_keep_count + 1'b1;
        end
        if ((prep_count > 1) && (prep_id1 != prep_jid)) begin
            case (prep_keep_count)
                0: prep_keep_ids[0*4 +: 4] = prep_id1;
                1: prep_keep_ids[1*4 +: 4] = prep_id1;
                2: prep_keep_ids[2*4 +: 4] = prep_id1;
                default: prep_keep_ids[3*4 +: 4] = prep_id1;
            endcase
            prep_keep_count = prep_keep_count + 1'b1;
        end
        if ((prep_count > 2) && (prep_id2 != prep_jid)) begin
            case (prep_keep_count)
                0: prep_keep_ids[0*4 +: 4] = prep_id2;
                1: prep_keep_ids[1*4 +: 4] = prep_id2;
                2: prep_keep_ids[2*4 +: 4] = prep_id2;
                default: prep_keep_ids[3*4 +: 4] = prep_id2;
            endcase
            prep_keep_count = prep_keep_count + 1'b1;
        end
        if ((prep_count > 3) && (prep_id3 != prep_jid)) begin
            case (prep_keep_count)
                0: prep_keep_ids[0*4 +: 4] = prep_id3;
                1: prep_keep_ids[1*4 +: 4] = prep_id3;
                2: prep_keep_ids[2*4 +: 4] = prep_id3;
                default: prep_keep_ids[3*4 +: 4] = prep_id3;
            endcase
            prep_keep_count = prep_keep_count + 1'b1;
        end
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
            if ((prep_count > 0) && (prep_id0 == prep_pid)) prep_pool_in_state = 1'b1;
            if ((prep_count > 1) && (prep_id1 == prep_pid)) prep_pool_in_state = 1'b1;
            if ((prep_count > 2) && (prep_id2 == prep_pid)) prep_pool_in_state = 1'b1;
            if ((prep_count > 3) && (prep_id3 == prep_pid)) prep_pool_in_state = 1'b1;
            if ((pi < req_pool_count) && !prep_pool_in_state &&
                (req_pool_val[pi] > 7'd0) &&
                (req_pool_val[pi] < prep_j) &&
                ((prep_count <= 0) || (prep_val0 > prep_j) || (req_pool_val[pi] > prep_val0)) &&
                ((prep_count <= 1) || (prep_val1 > prep_j) || (req_pool_val[pi] > prep_val1)) &&
                ((prep_count <= 2) || (prep_val2 > prep_j) || (req_pool_val[pi] > prep_val2)) &&
                ((prep_count <= 3) || (prep_val3 > prep_j) || (req_pool_val[pi] > prep_val3)))
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
            if (prep_elig_mask[pi]) begin
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
    reg [3:0] sort_raw0, sort_raw1, sort_raw2, sort_raw3;
    integer ai;
    integer tc;

    // Select, compact and canonically sort the current action directly.
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
            if (top_dmask[ai] && (tc < CKPT_K)) begin
                sel_id = a_ctx_extra_ids[ai*4 +: 4];
                tmp_id[tc] = sel_id;
                tc = tc + 1;
            end
        end
        for (ai=0; ai<4; ai=ai+1) begin
            if (top_rmask9[ai] && (tc < CKPT_K)) begin
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

    // Fixed-depth 4-input sorting network from the current action.
    always @* begin
        if (SEED_MODE) begin
            action_child_count = action_raw_child_count;
            sort_raw0 = action_raw0; sort_raw1 = action_raw1;
            sort_raw2 = action_raw2; sort_raw3 = action_raw3;
            action_imm_cost = a_ctx_imm;
        end else begin
            action_child_count = actionq_child_count;
            sort_raw0 = actionq_raw0; sort_raw1 = actionq_raw1;
            sort_raw2 = actionq_raw2; sort_raw3 = actionq_raw3;
            action_imm_cost = actionq_imm;
        end

        if (sort_raw0 <= sort_raw1) begin sid10=sort_raw0; sid11=sort_raw1; end
        else begin sid10=sort_raw1; sid11=sort_raw0; end
        if (sort_raw2 <= sort_raw3) begin sid12=sort_raw2; sid13=sort_raw3; end
        else begin sid12=sort_raw3; sid13=sort_raw2; end

        if (sid10 <= sid12) begin sid20=sid10; sid22=sid12; end
        else begin sid20=sid12; sid22=sid10; end
        if (sid11 <= sid13) begin sid21=sid11; sid23=sid13; end
        else begin sid21=sid13; sid23=sid11; end

        action_id0 = sid20;
        action_id3 = sid23;
        if (sid21 <= sid22) begin action_id1=sid21; action_id2=sid22; end
        else begin action_id1=sid22; action_id2=sid21; end

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

    // Exact one-step lower bound for a memo-miss child.  Any completion of the
    // child must first serve the next request, so
    //
    //   next_j - max(child checkpoints <= next_j)
    //
    // is a mandatory tail cost.  Ignoring all later requests only relaxes the
    // problem and is therefore safe for branch-and-bound pruning.
    reg [6:0] prune_cand0, prune_cand1, prune_cand2, prune_cand3;
    reg [6:0] prune_max01, prune_max23, prune_pred;
    reg [6:0] prune_tail_lb;
    reg [6:0] prune2_pred, prune2_value;
    reg [6:0] prune2_tail_lb;
    reg [10:0] prune_total_lb, prune2_total_lb, prune_active_lb;
    integer prune_i;
    always @* begin
        if ((a_pipe_child_count > 0) && (eval_raw_v0 <= a_pipe_next_j))
            prune_cand0 = eval_raw_v0;
        else
            prune_cand0 = 7'd0;
        if ((a_pipe_child_count > 1) && (eval_raw_v1 <= a_pipe_next_j))
            prune_cand1 = eval_raw_v1;
        else
            prune_cand1 = 7'd0;
        if ((a_pipe_child_count > 2) && (eval_raw_v2 <= a_pipe_next_j))
            prune_cand2 = eval_raw_v2;
        else
            prune_cand2 = 7'd0;
        if ((a_pipe_child_count > 3) && (eval_raw_v3 <= a_pipe_next_j))
            prune_cand3 = eval_raw_v3;
        else
            prune_cand3 = 7'd0;

        if (prune_cand0 >= prune_cand1) prune_max01 = prune_cand0;
        else                             prune_max01 = prune_cand1;
        if (prune_cand2 >= prune_cand3) prune_max23 = prune_cand2;
        else                             prune_max23 = prune_cand3;
        if (prune_max01 >= prune_max23) prune_pred = prune_max01;
        else                             prune_pred = prune_max23;

        prune_tail_lb = a_pipe_next_j - prune_pred;
        prune_total_lb = {4'd0,a_pipe_imm} + {4'd0,prune_tail_lb};

        // Two-step relaxation: after serving next_j, keep the whole child set
        // and materialize every request-pool value that restricted-B could
        // deposit on that path.  This is a superset of every capacity-K child,
        // hence the second immediate distance remains an admissible bound.
        prune2_pred = 7'd0;
        if ((a_pipe_child_count > 0) && (eval_raw_v0 <= a_pipe_next2_j) &&
            (eval_raw_v0 > prune2_pred))
            prune2_pred = eval_raw_v0;
        if ((a_pipe_child_count > 1) && (eval_raw_v1 <= a_pipe_next2_j) &&
            (eval_raw_v1 > prune2_pred))
            prune2_pred = eval_raw_v1;
        if ((a_pipe_child_count > 2) && (eval_raw_v2 <= a_pipe_next2_j) &&
            (eval_raw_v2 > prune2_pred))
            prune2_pred = eval_raw_v2;
        if ((a_pipe_child_count > 3) && (eval_raw_v3 <= a_pipe_next2_j) &&
            (eval_raw_v3 > prune2_pred))
            prune2_pred = eval_raw_v3;
        if ((a_pipe_next_j <= a_pipe_next2_j) &&
            (a_pipe_next_j > prune2_pred))
            prune2_pred = a_pipe_next_j;
        for (prune_i=0; prune_i<9; prune_i=prune_i+1) begin
            prune2_value = req_pool_val[prune_i];
            if ((prune_i < req_pool_count) &&
                (prune2_value > prune_pred) &&
                (prune2_value < a_pipe_next_j) &&
                (prune2_value <= a_pipe_next2_j) &&
                (prune2_value > prune2_pred))
                prune2_pred = prune2_value;
        end
        prune2_tail_lb = a_pipe_next2_j - prune2_pred;
        if (a_pipe_has_next2)
            prune2_total_lb = prune_total_lb + {4'd0,prune2_tail_lb};
        else
            prune2_total_lb = prune_total_lb;
        if ((EXACT_PRUNE == 2) || (EXACT_PRUNE == 4))
            prune_active_lb = prune2_total_lb;
        else
            prune_active_lb = prune_total_lb;
    end

    // Early-bound copy for the actionq boundary.  Raw child IDs are sufficient
    // because predecessor maxima do not depend on canonical tuple order.  Modes
    // 3/4 prune here, before a memo request exists, avoiding the repeated-miss
    // and speculative-pipeline flush cost of the experimental late modes 1/2.
    reg [6:0] early_v0, early_v1, early_v2, early_v3;
    reg [6:0] early_next_j, early_next2_j;
    reg       early_has_next2;
    reg [6:0] early_cand0, early_cand1, early_cand2, early_cand3;
    reg [6:0] early_max01, early_max23, early_pred;
    reg [6:0] early_tail_lb;
    reg [6:0] early2_cand0, early2_cand1, early2_cand2, early2_cand3;
    reg [6:0] early2_max01, early2_max23, early2_child_max;
    reg [6:0] early2_pool_cand [0:8];
    reg [6:0] early2_pool01, early2_pool23, early2_pool45, early2_pool67;
    reg [6:0] early2_pool03, early2_pool47, early2_pool07, early2_pool08;
    reg [6:0] early2_base_pred, early2_pred, early2_tail_lb;
    reg [10:0] early_total_lb, early2_total_lb, early_active_lb;
    integer early_i;
    always @* begin
        early_v0 = (actionq_child_count > 0) ? univ_val[actionq_raw0] : 7'h7F;
        early_v1 = (actionq_child_count > 1) ? univ_val[actionq_raw1] : 7'h7F;
        early_v2 = (actionq_child_count > 2) ? univ_val[actionq_raw2] : 7'h7F;
        early_v3 = (actionq_child_count > 3) ? univ_val[actionq_raw3] : 7'h7F;
        early_next_j = req_val[{1'b0,actionq_stage} + 4'd1];
        early_has_next2 = (({1'b0,actionq_stage} + 4'd2) <= H_FUTURE);
        if (early_has_next2)
            early_next2_j = req_val[{1'b0,actionq_stage} + 4'd2];
        else
            early_next2_j = 7'd0;

        if ((actionq_child_count > 0) && (early_v0 <= early_next_j))
            early_cand0 = early_v0;
        else
            early_cand0 = 7'd0;
        if ((actionq_child_count > 1) && (early_v1 <= early_next_j))
            early_cand1 = early_v1;
        else
            early_cand1 = 7'd0;
        if ((actionq_child_count > 2) && (early_v2 <= early_next_j))
            early_cand2 = early_v2;
        else
            early_cand2 = 7'd0;
        if ((actionq_child_count > 3) && (early_v3 <= early_next_j))
            early_cand3 = early_v3;
        else
            early_cand3 = 7'd0;
        if (early_cand0 >= early_cand1) early_max01 = early_cand0;
        else                             early_max01 = early_cand1;
        if (early_cand2 >= early_cand3) early_max23 = early_cand2;
        else                             early_max23 = early_cand3;
        if (early_max01 >= early_max23) early_pred = early_max01;
        else                             early_pred = early_max23;
        early_tail_lb = early_next_j - early_pred;
        early_total_lb = {4'd0,actionq_imm} + {4'd0,early_tail_lb};

        if ((actionq_child_count > 0) && (early_v0 <= early_next2_j))
            early2_cand0 = early_v0;
        else early2_cand0 = 7'd0;
        if ((actionq_child_count > 1) && (early_v1 <= early_next2_j))
            early2_cand1 = early_v1;
        else early2_cand1 = 7'd0;
        if ((actionq_child_count > 2) && (early_v2 <= early_next2_j))
            early2_cand2 = early_v2;
        else early2_cand2 = 7'd0;
        if ((actionq_child_count > 3) && (early_v3 <= early_next2_j))
            early2_cand3 = early_v3;
        else early2_cand3 = 7'd0;
        if (early2_cand0 >= early2_cand1) early2_max01 = early2_cand0;
        else                               early2_max01 = early2_cand1;
        if (early2_cand2 >= early2_cand3) early2_max23 = early2_cand2;
        else                               early2_max23 = early2_cand3;
        if (early2_max01 >= early2_max23) early2_child_max = early2_max01;
        else                               early2_child_max = early2_max23;
        if ((early_next_j <= early_next2_j) &&
            (early_next_j > early2_child_max))
            early2_base_pred = early_next_j;
        else
            early2_base_pred = early2_child_max;

        for (early_i=0; early_i<9; early_i=early_i+1) begin
            if ((early_i < req_pool_count) &&
                (req_pool_val[early_i] > early_pred) &&
                (req_pool_val[early_i] < early_next_j) &&
                (req_pool_val[early_i] <= early_next2_j))
                early2_pool_cand[early_i] = req_pool_val[early_i];
            else
                early2_pool_cand[early_i] = 7'd0;
        end
        if (early2_pool_cand[0] >= early2_pool_cand[1]) early2_pool01 = early2_pool_cand[0];
        else early2_pool01 = early2_pool_cand[1];
        if (early2_pool_cand[2] >= early2_pool_cand[3]) early2_pool23 = early2_pool_cand[2];
        else early2_pool23 = early2_pool_cand[3];
        if (early2_pool_cand[4] >= early2_pool_cand[5]) early2_pool45 = early2_pool_cand[4];
        else early2_pool45 = early2_pool_cand[5];
        if (early2_pool_cand[6] >= early2_pool_cand[7]) early2_pool67 = early2_pool_cand[6];
        else early2_pool67 = early2_pool_cand[7];
        if (early2_pool01 >= early2_pool23) early2_pool03 = early2_pool01;
        else early2_pool03 = early2_pool23;
        if (early2_pool45 >= early2_pool67) early2_pool47 = early2_pool45;
        else early2_pool47 = early2_pool67;
        if (early2_pool03 >= early2_pool47) early2_pool07 = early2_pool03;
        else early2_pool07 = early2_pool47;
        if (early2_pool07 >= early2_pool_cand[8]) early2_pool08 = early2_pool07;
        else early2_pool08 = early2_pool_cand[8];
        if (early2_base_pred >= early2_pool08) early2_pred = early2_base_pred;
        else early2_pred = early2_pool08;
        early2_tail_lb = early_next2_j - early2_pred;
        if (early_has_next2)
            early2_total_lb = early_total_lb + {4'd0,early2_tail_lb};
        else
            early2_total_lb = early_total_lb;
        if (EXACT_PRUNE == 4)
            early_active_lb = early2_total_lb;
        else
            early_active_lb = early_total_lb;
    end

    // Root value sorting and tie-break are combinational with evaluation.
    reg [6:0] qval10,qval11,qval12,qval13;
    reg [6:0] qval20,qval21,qval22,qval23;
    reg [6:0] qsort_v0,qsort_v1,qsort_v2,qsort_v3;
    reg [2:0] eval_seg;
    always @* begin
        if (eval_raw_v0 <= eval_raw_v1) begin qval10=eval_raw_v0; qval11=eval_raw_v1; end
        else begin qval10=eval_raw_v1; qval11=eval_raw_v0; end
        if (eval_raw_v2 <= eval_raw_v3) begin qval12=eval_raw_v2; qval13=eval_raw_v3; end
        else begin qval12=eval_raw_v3; qval13=eval_raw_v2; end
        if (qval10 <= qval12) begin qval20=qval10; qval22=qval12; end
        else begin qval20=qval12; qval22=qval10; end
        if (qval11 <= qval13) begin qval21=qval11; qval23=qval13; end
        else begin qval21=qval13; qval23=qval11; end
        qsort_v0 = qval20;
        qsort_v3 = qval23;
        if (qval21 <= qval22) begin qsort_v1=qval21; qsort_v2=qval22; end
        else begin qsort_v1=qval22; qsort_v2=qval21; end
        eval_seg = 3'd1;
        if ((a_pipe_child_count > 0) && (qsort_v0 > a_pipe_pred) && (qsort_v0 < a_pipe_j))
            eval_seg = eval_seg + 1'b1;
        if ((a_pipe_child_count > 1) && (qsort_v1 > a_pipe_pred) && (qsort_v1 < a_pipe_j))
            eval_seg = eval_seg + 1'b1;
        if ((a_pipe_child_count > 2) && (qsort_v2 > a_pipe_pred) && (qsort_v2 < a_pipe_j))
            eval_seg = eval_seg + 1'b1;
        if ((a_pipe_child_count > 3) && (qsort_v3 > a_pipe_pred) && (qsort_v3 < a_pipe_j))
            eval_seg = eval_seg + 1'b1;
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
        ST_ROOT_DRAIN  = 4'd10;
    reg [3:0] fsm_state;

    // -------------------------------------------------------------------------
    // Memo keeps one response-alignment register because the BRAM read is
    // synchronous. In seed-first mode, the bound output drives the address
    // directly; the former action/sort/address timing stages are bypassed.
    // -------------------------------------------------------------------------
    wire top_terminal = (a_req_idx >= H_FUTURE);
    wire [17:0] memo_rd_data;
    wire memo_pipe_hit = mresp_valid &&
                         ((memo_rd_data[17:10] == policy_epoch) ||
                          (SEED_MODE && mresp_direct));
    // Child cost of a memo-pipeline hit.  Outside EXACT_PRUNE=5 this is the
    // unchanged BRAM cost field.
    wire [10:0] memo_child_cost = (SEED_MODE && mresp_direct) ?
                                  {1'b0,mresp_lb} : {1'b0,memo_rd_data[9:0]};

    wire can_issue_memo_action = busy && (fsm_state == ST_RUN) && !top_terminal &&
                                 a_gen_valid && (!mresp_valid || memo_pipe_hit);

    wire seed_memo_issue;
    wire [13:0] seed_memo_addr;
    wire memo_rd_en = SEED_MODE ? seed_memo_issue : areq_valid;
    wire [13:0] memo_rd_addr = SEED_MODE ? seed_memo_addr : areq_addr;
    reg memo_wr_en;
    reg [13:0] memo_wr_addr;
    reg [17:0] memo_wr_data;
    reg memo_clear_en;
    reg [13:0] memo_clear_addr;

    grover_ckpt_policy_memo #(
        .COMPACT_K3H3(COMPACT_K3H3),
        .FIVE_BANKS(MEM_ENTRIES > 8192)
    ) u_policy_memo (
        .clk(clk),
        .rd_en(memo_rd_en), .rd_addr(memo_rd_addr), .rd_data(memo_rd_data),
        .wr_en(memo_wr_en), .wr_addr(memo_wr_addr), .wr_data(memo_wr_data),
        .clear_en(memo_clear_en), .clear_addr(memo_clear_addr)
    );

    // -------------------------------------------------------------------------
    // EXACT_PRUNE=5: full-horizon admissible lower bound.
    //
    // Software definition (sim/policy_search_method1.py relaxed_lower_bound):
    // remove the K capacity limit, keep every checkpoint forever, and on each
    // remaining request r
    //     source = max(0, checkpoints <= r);  cost += r - source;
    //     add r and every request-pool value v with source < v < r.
    // The relaxed checkpoint set is a superset of every capacity-K
    // realization, so the cost can never exceed the true optimum.
    //
    // Hardware form.  All values live in the solve universe, so a checkpoint
    // set is a UB-bit mask in sorted-rank order.  With rank order every value
    // comparison above becomes a fixed bit range:
    //     q      = mask & (ranks <= rank(r))         candidates for source
    //     source = highest set bit of q              (0 if q is empty)
    //     above  = ranks strictly above that bit     (~suffix_or(q))
    //     mask'  = mask | {rank(r)} | (above & ranks < rank(r) & pool & v>0)
    // Each request is one registered stage, so no stage contains a value
    // comparator or a max tree.  The source value lookup and the cost add
    // run one stage later from the registered one-hot source; only the next
    // mask depends on the previous mask.
    //
    // Stages are indexed by absolute request number t=1..H and are active
    // when t > a_req_idx (the frame's head request).  The pipeline only ever
    // holds packets of the active frame: it is flushed on every memo miss and
    // whenever the FSM leaves ST_RUN, i.e. exactly when the frame changes.
    // -------------------------------------------------------------------------

    // Per-solve tables.  They depend only on BUILD results, are free-running
    // registers, and settle two cycles after the last BUILD commit, i.e.
    // before the root frame reaches ST_RUN.
    reg [3:0]    rk_req [0:8];
    reg [UB-1:0] bt_le  [0:8];
    reg [UB-1:0] bt_dep [0:8];
    reg [UB-1:0] bt_roh [0:8];
    reg [UB-1:0] rk_pool_c;
    reg [UB-1:0] rk_nz_c;
    integer rt_i;

    always @* begin
        // Request pool = requests 0..H (deduplicated automatically by rank).
        rk_pool_c = {UB{1'b0}};
        for (rt_i=0; rt_i<9; rt_i=rt_i+1)
            if (rt_i < WINDOW_LEN)
                rk_pool_c = rk_pool_c | rank_onehot(rk_req[rt_i]);
        // v > 0: only rank 0 can hold the value 0.
        rk_nz_c = {UB{1'b1}};
        if (rk_sval[0] == 7'd0)
            rk_nz_c[0] = 1'b0;
    end

    always @(posedge clk) begin
        for (rt_i=0; rt_i<9; rt_i=rt_i+1) begin
            rk_req[rt_i] <= rk_pos[req_id[rt_i]];
            bt_le[rt_i]  <= rank_le(rk_req[rt_i]);
            bt_roh[rt_i] <= rank_onehot(rk_req[rt_i]);
            bt_dep[rt_i] <= rank_lt(rk_req[rt_i]) & rk_pool_c & rk_nz_c;
        end
    end

    // Bound pipeline registers.  Index 0 is the entry stage (child set only);
    // index t holds the state after request t's mask update.
    //   bp_oh[t]   one-hot rank of request t's source (0 if inactive/empty)
    //   bp_act[t]  request t was active for this packet's frame
    //   bp_tail[t] cost of requests 1..t-1 (one stage behind the mask)
    reg [H_FUTURE:0] bp_v;
    reg              bp_kind [0:H_FUTURE];
    reg [2:0]        bp_cnt  [0:H_FUTURE];
    reg [15:0]       bp_ids  [0:H_FUTURE];
    reg [23:0]       bp_pre  [0:H_FUTURE];  // {gen_valid,rmask,rsize,dmask,dsize}
    reg [UB-1:0]     bp_mask [0:H_FUTURE];
    reg [UB-1:0]     bp_oh   [0:H_FUTURE];
    reg              bp_act  [0:H_FUTURE];
    reg [10:0]       bp_tail [0:H_FUTURE];

    // Pipeline output, consumed by ST_RUN on the following cycle.
    //   bo_tail  : relaxed lower bound of the child's remaining window
    //   bo_total : bo_tail + the frame's immediate cost (compared with best)
    reg              bo_v;
    reg              bo_kind;
    reg [2:0]        bo_cnt;
    reg [15:0]       bo_ids;
    reg [23:0]       bo_pre;
    reg [10:0]       bo_tail;
    reg [10:0]       bo_total;

    // A memo miss in ST_RUN discards every younger packet.  Leaving ST_RUN
    // also clears the pipeline because the next ST_RUN belongs to a new frame.
    wire bp_flush = (fsm_state != ST_RUN) ||
                    (mresp_valid && !memo_pipe_hit);
    wire bound_capture = busy && (fsm_state == ST_RUN) && !top_terminal &&
                         a_gen_valid &&
                         ((a_phase == PH_SCAN) || (a_phase == PH_CANON));
    wire bp_busy  = bo_v || (|bp_v);

    // The packet at the output is the frame's last SCAN packet: the generator
    // is exhausted and nothing younger is in flight.  scan_fin_* is the seed
    // including that packet, so the SCAN can end in this same cycle.
    wire scan_last = bo_v && bo_kind && !a_gen_valid && !(|bp_v);
    wire scan_take = !scan_valid || (bo_total < scan_total);
    wire [10:0] scan_fin_total = scan_take ? bo_total : scan_total;
    wire [2:0]  scan_fin_cnt   = scan_take ? bo_cnt   : scan_cnt;
    wire [15:0] scan_fin_ids   = scan_take ? bo_ids   : scan_ids;
    wire scan_exact_finish = (sp != 0) && ({1'b0,a_req_idx} == (H_FUTURE-1));
    wire bo_pruned = bo_v && !bo_kind &&
                     (((sp != 0) && f_best_valid[sp] &&
                       (bo_total >= f_best_cost[sp])) ||
                      ((sp == 0) && root_best_valid &&
                       (bo_total > root_best_cost)));
    wire seed_issue_from_scan = scan_last && !scan_exact_finish;
    wire seed_issue_from_bound = bo_v && !bo_kind && !bo_pruned;
    assign seed_memo_issue = SEED_MODE &&
                             (seed_issue_from_scan || seed_issue_from_bound);
    wire [2:0] seed_issue_count = seed_issue_from_scan ? scan_fin_cnt : bo_cnt;
    wire [15:0] seed_issue_ids = seed_issue_from_scan ? scan_fin_ids : bo_ids;
    assign seed_memo_addr = memo_addr_of(a_req_idx[2:0],
        rank_state(seed_issue_count, seed_issue_ids[3:0], seed_issue_ids[7:4],
                   seed_issue_ids[11:8], seed_issue_ids[15:12]));

    // Source value of a one-hot rank (one-hot AND/OR mux).
    function [6:0] rank_value;
        input [UB-1:0] oh;
        integer p;
        begin
            rank_value = 7'd0;
            for (p=0; p<UB; p=p+1)
                rank_value = rank_value | ({7{oh[p]}} & rk_sval[p]);
        end
    endfunction

    reg [UB-1:0] bn_mask0;
    reg [UB-1:0] bn_q, bn_pre, bn_oh, bn_new;
    reg [10:0]   bn_step;
    reg [10:0]   bn_tail_out;
    reg          bn_active;
    reg          bn_in_kind, bn_in_act;
    reg [2:0]    bn_in_cnt;
    reg [15:0]   bn_in_ids;
    reg [23:0]   bn_in_pre;
    reg [UB-1:0] bn_in_mask, bn_in_oh;
    reg [10:0]   bn_in_tail;
    integer      bs;

    always @* begin
        // Entry stage: canonical child IDs -> rank mask.
        bn_mask0 = {UB{1'b0}};
        if (action_child_count > 0) bn_mask0 = bn_mask0 | rank_onehot(rk_pos[action_id0]);
        if (action_child_count > 1) bn_mask0 = bn_mask0 | rank_onehot(rk_pos[action_id1]);
        if (action_child_count > 2) bn_mask0 = bn_mask0 | rank_onehot(rk_pos[action_id2]);
        if (action_child_count > 3) bn_mask0 = bn_mask0 | rank_onehot(rk_pos[action_id3]);

        // Last request's cost, folded into the output register.
        if (bp_act[H_FUTURE])
            bn_tail_out = bp_tail[H_FUTURE] +
                          {4'd0, req_val[H_FUTURE] - rank_value(bp_oh[H_FUTURE])};
        else
            bn_tail_out = bp_tail[H_FUTURE];
    end

    // Variable-depth entry.  A frame whose head is request a_req_idx only has
    // requests a_req_idx+1..H left, so its packets enter directly at stage
    // a_req_idx+1 and skip the inactive front stages.  The bound latency is
    // then (H-a_req_idx)+2 cycles instead of H+2.  The selection is a fixed
    // 2:1 mux per stage driven by the frame register a_req_idx, which only
    // changes while the pipeline is empty.
    reg [H_FUTURE:0] bp_enter;   // bp_enter[t]: stage t takes the entry stage
    integer be;
    always @* begin
        bp_enter = {(H_FUTURE+1){1'b0}};
        for (be=1; be<=H_FUTURE; be=be+1)
            bp_enter[be] = (be == ({1'b0,a_req_idx} + 5'd1));
    end

    always @(posedge clk) begin
        if (!rstn || bp_flush || !SEED_MODE) begin
            bp_v <= {(H_FUTURE+1){1'b0}};
            bo_v <= 1'b0;
        end else begin
            bp_v[0] <= bound_capture;
            // Stages at or below the frame head are skipped: they must not
            // pick up the entry packet, or it would be duplicated.
            for (be=1; be<=H_FUTURE; be=be+1)
                bp_v[be] <= (be > a_req_idx) &&
                            (bp_enter[be] ? bp_v[0] : bp_v[be-1]);
            bo_v <= bp_v[H_FUTURE];
        end

        // Data registers carry no reset; validity is tracked by bp_v/bo_v.
        bp_kind[0] <= (a_phase == PH_SCAN);
        bp_cnt[0]  <= action_child_count;
        bp_ids[0]  <= {action_id3, action_id2, action_id1, action_id0};
        bp_pre[0]  <= {a_gen_valid, a_rmask, a_rsize, a_dmask, a_dsize};
        bp_mask[0] <= bn_mask0;
        bp_oh[0]   <= {UB{1'b0}};
        bp_act[0]  <= 1'b0;
        bp_tail[0] <= 11'd0;

        for (bs=1; bs<=H_FUTURE; bs=bs+1) begin
            // Stage input: the entry stage for the frame's first live request,
            // otherwise the previous stage.  The entry stage has no pending
            // request cost (bp_act[0]=0, bp_tail[0]=0).
            bn_active = (bs > a_req_idx);
            bn_in_kind = bp_enter[bs] ? bp_kind[0] : bp_kind[bs-1];
            bn_in_cnt  = bp_enter[bs] ? bp_cnt[0]  : bp_cnt[bs-1];
            bn_in_ids  = bp_enter[bs] ? bp_ids[0]  : bp_ids[bs-1];
            bn_in_pre  = bp_enter[bs] ? bp_pre[0]  : bp_pre[bs-1];
            bn_in_mask = bp_enter[bs] ? bp_mask[0] : bp_mask[bs-1];
            bn_in_oh   = bp_enter[bs] ? {UB{1'b0}} : bp_oh[bs-1];
            bn_in_act  = bp_enter[bs] ? 1'b0       : bp_act[bs-1];
            bn_in_tail = bp_enter[bs] ? 11'd0      : bp_tail[bs-1];

            bn_q   = bn_in_mask & bt_le[bs];
            bn_pre = suffix_or(bn_q);
            bn_oh  = bn_q & ~(bn_pre >> 1);
            bn_new = bn_in_mask | bt_roh[bs] | (~bn_pre & bt_dep[bs]);

            bp_kind[bs] <= bn_in_kind;
            bp_cnt[bs]  <= bn_in_cnt;
            bp_ids[bs]  <= bn_in_ids;
            bp_pre[bs]  <= bn_in_pre;
            bp_mask[bs] <= bn_active ? bn_new : bn_in_mask;
            bp_oh[bs]   <= bn_active ? bn_oh : {UB{1'b0}};
            bp_act[bs]  <= bn_active;

            // Cost of request bs-1, from the previous stage's registered source.
            if (bn_in_act)
                bn_step = {4'd0, req_val[bs-1] - rank_value(bn_in_oh)};
            else
                bn_step = 11'd0;
            bp_tail[bs] <= bn_in_tail + bn_step;
        end

        bo_kind  <= bp_kind[H_FUTURE];
        bo_cnt   <= bp_cnt[H_FUTURE];
        bo_ids   <= bp_ids[H_FUTURE];
        bo_pre   <= bp_pre[H_FUTURE];
        bo_tail  <= bn_tail_out;
        bo_total <= bn_tail_out + {4'd0, a_ctx_imm};
    end

    // -------------------------------------------------------------------------
    // Control / counters.
    // -------------------------------------------------------------------------
    reg [31:0] cyc_ctr;
    reg [31:0] act_ctr;
    reg [31:0] hit_ctr;
    reg [31:0] miss_ctr;
    reg [31:0] prune_ctr;
    reg [10:0] return_cost;
    reg [13:0] clear_ctr;
    reg memo_needs_clear;

    reg root_best_valid;
    reg [10:0] root_best_cost;
    reg [2:0] root_best_seg;
    reg [2:0] root_best_count;
    reg [6:0] root_best_v0,root_best_v1,root_best_v2,root_best_v3;

    // Non-root frames minimize cost only, so equality cannot improve them.
    // At the root, equality may still win through segment/tuple tie-breaks;
    // prune there only on a strictly worse cost bound.
    wire exact_prune_miss = ((EXACT_PRUNE == 1) || (EXACT_PRUNE == 2)) &&
                            mresp_valid &&
                            !memo_pipe_hit &&
                            (((sp != 0) && f_best_valid[sp] &&
                              (prune_active_lb >= f_best_cost[sp])) ||
                             ((sp == 0) && root_best_valid &&
                              (prune_active_lb > root_best_cost)));
    wire exact_prune_actionq = ((EXACT_PRUNE == 3) || (EXACT_PRUNE == 4)) &&
                               actionq_valid &&
                               (((sp != 0) && f_best_valid[sp] &&
                                 (early_active_lb >= f_best_cost[sp])) ||
                                ((sp == 0) && root_best_valid &&
                                 (early_active_lb > root_best_cost)));
    wire exact_prune_actionq_commit = exact_prune_actionq &&
                                      (!mresp_valid || memo_pipe_hit);

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
            end else if ((a_dsize < (CKPT_K-1)) && ((a_dsize + 1'b1) <= extra_count)) begin
                ndsize = a_dsize + 1'b1;
                if (keep_count < ((CKPT_K-1) - ndsize)) nrsize = keep_count;
                else nrsize = (CKPT_K-1) - ndsize;
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

    // A memo miss normally restores this saved pre-action generator state only
    // after returning from the child.  Exact pruning skips that descent, so
    // restore the same packet and advance it once here.  This preserves the
    // precise canonical action order despite younger speculative requests in
    // the pipeline.
    task restore_generator_after_prune;
        input [1:0] pre_dsize;
        input [8:0] pre_dmask;
        input [2:0] pre_rsize;
        input [8:0] pre_rmask;
        reg [1:0] ndsize;
        reg [2:0] nrsize;
        reg [8:0] nmask;
        begin
            a_dsize <= pre_dsize;
            a_dmask <= pre_dmask;
            a_rsize <= pre_rsize;
            a_rmask <= pre_rmask;
            f_dsize[sp] <= pre_dsize;
            f_dmask[sp] <= pre_dmask;
            f_rsize[sp] <= pre_rsize;
            f_rmask[sp] <= pre_rmask;
            a_gen_valid <= 1'b1;
            f_gen_valid[sp] <= 1'b1;

            if (comb_has_next9(pre_rmask, keep_count, pre_rsize)) begin
                nmask = next_comb9(pre_rmask, keep_count, pre_rsize);
                a_rmask <= nmask;
                f_rmask[sp] <= nmask;
            end else if (comb_has_next9(pre_dmask, extra_count, pre_dsize)) begin
                nmask = next_comb9(pre_dmask, extra_count, pre_dsize);
                a_dmask <= nmask;
                f_dmask[sp] <= nmask;
                a_rmask <= first_comb9(pre_rsize);
                f_rmask[sp] <= first_comb9(pre_rsize);
            end else if ((pre_dsize < (CKPT_K-1)) &&
                         ((pre_dsize + 1'b1) <= extra_count)) begin
                ndsize = pre_dsize + 1'b1;
                if (keep_count < ((CKPT_K-1) - ndsize)) nrsize = keep_count;
                else nrsize = (CKPT_K-1) - ndsize;
                a_dsize <= ndsize;
                f_dsize[sp] <= ndsize;
                a_dmask <= first_comb9(ndsize);
                f_dmask[sp] <= first_comb9(ndsize);
                a_rsize <= nrsize;
                f_rsize[sp] <= nrsize;
                a_rmask <= first_comb9(nrsize);
                f_rmask[sp] <= first_comb9(nrsize);
            end else begin
                a_gen_valid <= 1'b0;
                f_gen_valid[sp] <= 1'b0;
            end
        end
    endtask

    task eval_pending;
        input [10:0] child_cost11;
        reg [10:0] fast_total;
        reg root_better;
        begin
            fast_total = {4'd0,a_pipe_imm} + child_cost11;
            if (sp == 0) begin
                root_better = !root_best_valid || (fast_total < root_best_cost) ||
                    ((fast_total == root_best_cost) &&
                     ((eval_seg < root_best_seg) ||
                      ((eval_seg == root_best_seg) &&
                       lex_less4(a_pipe_child_count,qsort_v0,qsort_v1,qsort_v2,qsort_v3,
                                 root_best_count,root_best_v0,root_best_v1,
                                 root_best_v2,root_best_v3))));
                if (root_better) begin
                    root_best_valid <= 1'b1;
                    root_best_cost <= fast_total;
                    root_best_seg <= eval_seg;
                    root_best_count <= a_pipe_child_count;
                    root_best_v0 <= qsort_v0;
                    root_best_v1 <= qsort_v1;
                    root_best_v2 <= qsort_v2;
                    root_best_v3 <= qsort_v3;
                end
            end else begin
                if (!f_best_valid[sp] || (fast_total < f_best_cost[sp])) begin
                    f_best_valid[sp] <= 1'b1;
                    f_best_cost[sp] <= fast_total;
                end
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
            actionq_kind          <= SEED_MODE && (a_phase == PH_SCAN);
            advance_generator;
        end
    endtask

    // EXACT_PRUNE=5: re-arm the active frame's generator at its first
    // canonical action, exactly as ST_PREP does on frame entry.
    task reset_generator_to_first;
        reg [2:0] rs;
        begin
            if (a_ctx_keep_count < (CKPT_K-1)) rs = a_ctx_keep_count;
            else                               rs = CKPT_K-1;
            a_dsize <= 2'd0;  f_dsize[sp] <= 2'd0;
            a_dmask <= 9'd0;  f_dmask[sp] <= 9'd0;
            a_rsize <= rs;    f_rsize[sp] <= rs;
            a_rmask <= first_comb9(rs);
            f_rmask[sp] <= first_comb9(rs);
            a_gen_valid <= 1'b1;
            f_gen_valid[sp] <= 1'b1;
        end
    endtask

    // EXACT_PRUNE=5: issue the SCAN seed as a normal evaluation packet.  Its
    // saved generator state is "exhausted" so that a memo-miss descent of
    // the seed returns without advancing the canonical walk; the walk is
    // re-armed from the first action once the seed result is known.
    task inject_seed_to_actionq;
        input [2:0]  seed_cnt;
        input [15:0] seed_ids;
        begin
            actionq_valid         <= 1'b1;
            actionq_kind          <= 1'b0;
            actionq_stage         <= a_req_idx[2:0];
            actionq_child_count   <= seed_cnt;
            actionq_raw0          <= seed_ids[ 3: 0];
            actionq_raw1          <= seed_ids[ 7: 4];
            actionq_raw2          <= seed_ids[11: 8];
            actionq_raw3          <= seed_ids[15:12];
            actionq_imm           <= a_ctx_imm;
            actionq_pred          <= a_ctx_pred;
            actionq_j             <= a_ctx_j;
            actionq_pre_dsize     <= 2'd0;
            actionq_pre_dmask     <= 9'd0;
            actionq_pre_rsize     <= 3'd0;
            actionq_pre_rmask     <= 9'd0;
            actionq_pre_gen_valid <= 1'b0;
        end
    endtask

    // EXACT_PRUNE=5/6: forward the bound-pipeline output packet to the memo
    // pipeline.  Frame-invariant fields come from the active-frame mirror,
    // valid because the bound pipeline never outlives its frame.  A child
    // whose window is a single request (frame head = H-1) takes the direct
    // path: its relaxed bound is its exact cost.  force_direct is used only
    // by the EXACT_PRUNE=6 forced-root shortcut.
    task route_bout_to_mreq;
        input force_direct;
        begin
            mreq_valid         <= 1'b1;
            mreq_stage         <= a_req_idx[2:0];
            mreq_child_count   <= bo_cnt;
            mreq_raw0          <= bo_ids[ 3: 0];
            mreq_raw1          <= bo_ids[ 7: 4];
            mreq_raw2          <= bo_ids[11: 8];
            mreq_raw3          <= bo_ids[15:12];
            mreq_imm           <= a_ctx_imm;
            mreq_pred          <= a_ctx_pred;
            mreq_j             <= a_ctx_j;
            mreq_pre_dsize     <= bo_pre[1:0];
            mreq_pre_dmask     <= bo_pre[10:2];
            mreq_pre_rsize     <= bo_pre[13:11];
            mreq_pre_rmask     <= bo_pre[22:14];
            mreq_pre_gen_valid <= bo_pre[23];
            mreq_direct        <= force_direct ||
                                  ({1'b0,a_req_idx} == (H_FUTURE-1));
            mreq_lb            <= bo_tail[9:0];
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
            root_init_count <= 3'd0;
            root_init_id0<=4'd0; root_init_id1<=4'd0; root_init_id2<=4'd0; root_init_id3<=4'd0;
            sp <= 4'd0;
            a_req_idx<=4'd0; a_ctx_j<=7'd0; a_ctx_jid<=4'd0; a_ctx_pred<=7'd0; a_ctx_imm<=7'd0;
            a_ctx_extra_count<=4'd0; a_ctx_extra_ids<=36'd0; a_ctx_keep_count<=3'd0; a_ctx_keep_ids<=16'd0;
            a_dsize<=2'd0; a_dmask<=9'd0; a_rsize<=3'd0; a_rmask<=9'd0; a_gen_valid<=1'b0;
            actionq_valid<=1'b0; actionq_stage<=3'd0; actionq_child_count<=3'd0;
            actionq_raw0<=4'd0; actionq_raw1<=4'd0; actionq_raw2<=4'd0; actionq_raw3<=4'd0;
            actionq_imm<=7'd0; actionq_pred<=7'd0; actionq_j<=7'd0;
            actionq_pre_dsize<=2'd0; actionq_pre_dmask<=9'd0;
            actionq_pre_rsize<=3'd0; actionq_pre_rmask<=9'd0; actionq_pre_gen_valid<=1'b0;
            actionq_kind<=1'b0; a_phase<=PH_SCAN;
            scan_valid<=1'b0; scan_total<=INF_COST; scan_cnt<=3'd0; scan_ids<=16'd0;
            scan_issued<=1'b0; scan_multi<=1'b0; seed_gap<=3'd0;
            mreq_direct<=1'b0; areq_direct<=1'b0; mresp_direct<=1'b0;
            mreq_lb<=10'd0; areq_lb<=10'd0; mresp_lb<=10'd0;
            a_pipe_child_count<=3'd0; a_pipe_cid0<=4'd0; a_pipe_cid1<=4'd0; a_pipe_cid2<=4'd0; a_pipe_cid3<=4'd0;
            a_pipe_imm<=7'd0; a_pipe_pred<=7'd0; a_pipe_j<=7'd0;
            a_pipe_next_j<=7'd0; a_pipe_next2_j<=7'd0; a_pipe_has_next2<=1'b0;
            mreq_valid<=1'b0; mreq_stage<=3'd0; mreq_child_count<=3'd0;
            mreq_raw0<=4'd0; mreq_raw1<=4'd0; mreq_raw2<=4'd0; mreq_raw3<=4'd0;
            mreq_imm<=7'd0; mreq_pred<=7'd0; mreq_j<=7'd0;
            mreq_pre_dsize<=2'd0; mreq_pre_dmask<=9'd0; mreq_pre_rsize<=3'd0; mreq_pre_rmask<=9'd0; mreq_pre_gen_valid<=1'b0;
            areq_valid<=1'b0; areq_addr<=14'd0; areq_child_count<=3'd0;
            areq_id0<=4'd0; areq_id1<=4'd0; areq_id2<=4'd0; areq_id3<=4'd0;
            areq_imm<=7'd0; areq_pred<=7'd0; areq_j<=7'd0;
            areq_next_j<=7'd0; areq_next2_j<=7'd0; areq_has_next2<=1'b0;
            areq_pre_dsize<=2'd0; areq_pre_dmask<=9'd0; areq_pre_rsize<=3'd0; areq_pre_rmask<=9'd0; areq_pre_gen_valid<=1'b0;
            mresp_valid<=1'b0; mresp_pre_dsize<=2'd0; mresp_pre_dmask<=9'd0;
            mresp_pre_rsize<=3'd0; mresp_pre_rmask<=9'd0; mresp_pre_gen_valid<=1'b0;
            fsm_state <= ST_IDLE;
            cyc_ctr <= 32'd0; act_ctr<=32'd0; hit_ctr<=32'd0; miss_ctr<=32'd0; prune_ctr<=32'd0;
            return_cost <= 11'd0;
            clear_ctr <= 14'd0;
            memo_needs_clear <= 1'b1;
            memo_wr_en <= 1'b0; memo_wr_addr<=14'd0; memo_wr_data<=18'd0;
            memo_clear_en<=1'b0; memo_clear_addr<=14'd0;
            root_best_valid<=1'b0; root_best_cost<=INF_COST; root_best_seg<=3'd0; root_best_count<=3'd0;
            root_best_v0<=7'd0; root_best_v1<=7'd0; root_best_v2<=7'd0; root_best_v3<=7'd0;
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
                f_phase[si]<=PH_SCAN;
                f_multi[si]<=1'b0;
            end
            for (si=0; si<13; si=si+1) begin
                univ_val[si] <= 7'd0;
                rk_pos[si] <= 4'd0;
                rk_sval[si] <= 7'd0;
            end
        end else begin
            done <= 1'b0;
            memo_wr_en <= 1'b0;
            memo_clear_en <= 1'b0;

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
                        cyc_ctr<=32'd0; act_ctr<=32'd0; hit_ctr<=32'd0; miss_ctr<=32'd0; prune_ctr<=32'd0;
                        actionq_valid<=1'b0; mreq_valid<=1'b0; areq_valid<=1'b0; mresp_valid<=1'b0;
                        univ_count<=4'd0; req_pool_count<=4'd0; build_idx<=5'd0; root_init_count<=3'd0;
                        root_init_id0<=4'd0; root_init_id1<=4'd0; root_init_id2<=4'd0; root_init_id3<=4'd0;
                        root_best_valid<=1'b0; root_best_cost<=INF_COST; root_best_seg<=3'd0; root_best_count<=3'd0;
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
                    if (build_sel_valid) begin
                        if (build_idx >= 4)
                            req_val[build_idx-4] <= build_sel_value;
                        if ((build_idx < 4) && raw_found) begin
                            // duplicate physical checkpoint j violates metadata invariant
                            policy_error <= 1'b1;
                            fsm_state <= ST_ABORT;
                        end else begin
                            if (!raw_found) begin
                                if (univ_count >= U_MAX) begin
                                    policy_error <= 1'b1;
                                    fsm_state <= ST_ABORT;
                                end else begin
                                    univ_val[univ_count] <= build_sel_value;
                                    if (SEED_MODE) begin
                                        // Sorted insertion: entries with a larger
                                        // value move up one rank, and rank values
                                        // above the insertion point shift up.
                                        rk_pos[univ_count] <= build_newpos;
                                        for (si=0; si<13; si=si+1)
                                            if ((si < univ_count) && !build_lt[si])
                                                rk_pos[si] <= rk_pos[si] + 1'b1;
                                        for (si=1; si<13; si=si+1)
                                            if ((si > build_newpos) && (si <= univ_count))
                                                rk_sval[si] <= rk_sval[si-1];
                                        rk_sval[build_newpos] <= build_sel_value;
                                    end
                                    if (build_idx < 4) begin
                                        case (root_init_count)
                                            0: root_init_id0 <= univ_count;
                                            1: root_init_id1 <= univ_count;
                                            2: root_init_id2 <= univ_count;
                                            default: root_init_id3 <= univ_count;
                                        endcase
                                        root_init_count <= root_init_count + 1'b1;
                                    end else begin
                                        req_id[build_idx-4] <= univ_count;
                                    end
                                    univ_count <= univ_count + 1'b1;
                                end
                            end else begin
                                if (build_idx < 4) begin
                                    case (root_init_count)
                                        0: root_init_id0 <= raw_found_id;
                                        1: root_init_id1 <= raw_found_id;
                                        2: root_init_id2 <= raw_found_id;
                                        default: root_init_id3 <= raw_found_id;
                                    endcase
                                    root_init_count <= root_init_count + 1'b1;
                                end else begin
                                    req_id[build_idx-4] <= raw_found_id;
                                end
                            end
                        end
                    end

                    // Build a deduplicated request-only pool once per solve.
                    if (build_sel_valid && (build_idx >= 4) && !req_pool_found) begin
                        req_pool_id[req_pool_count] <= raw_resolved_id;
                        req_pool_val[req_pool_count] <= build_sel_value;
                        req_pool_count <= req_pool_count + 1'b1;
                    end

                    if ((build_idx == (4 + WINDOW_LEN - 1)) && !build_commit_abort) begin
                        sp <= 4'd0;
                        f_req_idx[0] <= 4'd0;
                        f_count[0] <= root_init_count;
                        f_id0[0] <= root_init_id0; f_id1[0] <= root_init_id1;
                        f_id2[0] <= root_init_id2; f_id3[0] <= root_init_id3;
                        f_dsize[0]<=2'd0; f_dord[0]<=7'd0; f_rord[0]<=4'd0; f_gen_valid[0]<=1'b1;
                        f_best_valid[0]<=1'b0; f_best_cost[0]<=INF_COST; f_pipe_valid[0]<=1'b0;
                        fsm_state <= ST_ROOT_INIT;
                    end else if (!build_commit_abort) begin
                        build_idx <= build_idx + 1'b1;
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
                    fsm_state <= ST_PREP;
                end

                ST_PREP: begin
                    actionq_valid <= 1'b0;
                    mreq_valid <= 1'b0;
                    areq_valid <= 1'b0;
                    mresp_valid <= 1'b0;
                    if (sp == 0)
                        source_j <= prep_pred;
                    f_ctx_j[sp] <= prep_j;
                    f_ctx_jid[sp] <= prep_jid;
                    f_ctx_pred[sp] <= prep_pred;
                    f_ctx_imm[sp] <= prep_j - prep_pred;
                    f_ctx_extra_count[sp] <= prep_extra_count;
                    f_ctx_extra_ids[sp] <= prep_extra_ids;
                    f_ctx_keep_count[sp] <= prep_keep_count;
                    f_ctx_keep_ids[sp] <= prep_keep_ids;

                    a_req_idx <= prep_req_idx;
                    a_ctx_j <= prep_j; a_ctx_jid <= prep_jid;
                    a_ctx_pred <= prep_pred; a_ctx_imm <= prep_j - prep_pred;
                    a_ctx_extra_count <= prep_extra_count; a_ctx_extra_ids <= prep_extra_ids;
                    a_ctx_keep_count <= prep_keep_count; a_ctx_keep_ids <= prep_keep_ids;
                    a_dsize <= 2'd0; a_dmask <= 9'd0;
                    f_dsize[sp] <= 2'd0;
                    f_dmask[sp] <= 9'd0;
                    if (prep_keep_count < (CKPT_K-1)) begin
                        f_rsize[sp] <= prep_keep_count;
                        a_rsize <= prep_keep_count;
                    end else begin
                        f_rsize[sp] <= (CKPT_K-1);
                        a_rsize <= (CKPT_K-1);
                    end
                    if (prep_keep_count < (CKPT_K-1)) begin
                        f_rmask[sp] <= first_comb9(prep_keep_count);
                        a_rmask <= first_comb9(prep_keep_count);
                    end else begin
                        f_rmask[sp] <= first_comb9(CKPT_K-1);
                        a_rmask <= first_comb9(CKPT_K-1);
                    end
                    f_gen_valid[sp] <= 1'b1;
                    a_gen_valid <= 1'b1;
                    // EXACT_PRUNE=5: every new frame starts with its SCAN.
                    a_phase <= PH_SCAN;
                    f_phase[sp] <= PH_SCAN;
                    scan_valid <= 1'b0;
                    scan_total <= INF_COST;
                    scan_issued <= 1'b0;
                    scan_multi <= 1'b0;
                    fsm_state <= ST_RUN;
                end

                ST_RUN: begin
                    if ((ACTION_LIMIT != 0) &&
                        ((act_ctr + prune_ctr) >= ACTION_LIMIT)) begin
                        policy_error <= 1'b1;
                        actionq_valid <= 1'b0;
                        mreq_valid <= 1'b0;
                        areq_valid <= 1'b0;
                        mresp_valid <= 1'b0;
                        fsm_state <= ST_ABORT;
                    end else if (top_terminal) begin
                        actionq_valid <= 1'b0;
                        mreq_valid <= 1'b0;
                        areq_valid <= 1'b0;
                        mresp_valid <= 1'b0;
                        if (a_gen_valid) begin
                            eval_total = {4'd0,a_ctx_imm};
                            if ((sp != 0) &&
                                (!f_best_valid[sp] || (eval_total < f_best_cost[sp]))) begin
                                f_best_valid[sp] <= 1'b1;
                                f_best_cost[sp] <= eval_total;
                            end
                            advance_generator;
                            act_ctr <= act_ctr + 1'b1;
                        end else begin
                            fsm_state <= ST_FINISH;
                        end
                    end else begin
                        if (SEED_MODE) begin
                            // The bound output drives the synchronous memo BRAM
                            // directly. mresp_* is the single alignment record
                            // consumed with that BRAM response next cycle.
                            actionq_valid <= 1'b0;
                            mreq_valid <= 1'b0;
                            areq_valid <= 1'b0;
                            mresp_valid <= seed_memo_issue;
                            if (seed_memo_issue) begin
                                a_pipe_child_count <= seed_issue_count;
                                a_pipe_cid0 <= seed_issue_ids[3:0];
                                a_pipe_cid1 <= seed_issue_ids[7:4];
                                a_pipe_cid2 <= seed_issue_ids[11:8];
                                a_pipe_cid3 <= seed_issue_ids[15:12];
                                a_pipe_imm <= a_ctx_imm;
                                a_pipe_pred <= a_ctx_pred;
                                a_pipe_j <= a_ctx_j;
                                mresp_pre_dsize <= seed_issue_from_scan ? 2'd0 : bo_pre[1:0];
                                mresp_pre_dmask <= seed_issue_from_scan ? 9'd0 : bo_pre[10:2];
                                mresp_pre_rsize <= seed_issue_from_scan ? 3'd0 : bo_pre[13:11];
                                mresp_pre_rmask <= seed_issue_from_scan ? 9'd0 : bo_pre[22:14];
                                mresp_pre_gen_valid <= seed_issue_from_scan ? 1'b0 : bo_pre[23];
                                mresp_direct <= (seed_issue_from_scan && !scan_multi &&
                                                 ROOT_FORCED && (sp == 0)) ||
                                                ({1'b0,a_req_idx} == (H_FUTURE-1));
                                mresp_lb <= seed_issue_from_scan ?
                                    (scan_fin_total - {4'd0,a_ctx_imm}) : bo_tail[9:0];
                            end
                        end else begin
                            mresp_valid <= areq_valid;
                            areq_valid <= mreq_valid;
                            mreq_valid <= actionq_valid && !exact_prune_actionq;
                            actionq_valid <= 1'b0;
                        end

                        if (exact_prune_actionq_commit)
                            prune_ctr <= prune_ctr + 1'b1;

                        if (areq_valid) begin
                            a_pipe_child_count <= areq_child_count;
                            a_pipe_cid0 <= areq_id0; a_pipe_cid1 <= areq_id1;
                            a_pipe_cid2 <= areq_id2; a_pipe_cid3 <= areq_id3;
                            a_pipe_imm <= areq_imm;
                            a_pipe_pred <= areq_pred;
                            a_pipe_j <= areq_j;
                            a_pipe_next_j <= areq_next_j;
                            a_pipe_next2_j <= areq_next2_j;
                            a_pipe_has_next2 <= areq_has_next2;
                            mresp_pre_dsize <= areq_pre_dsize;
                            mresp_pre_dmask <= areq_pre_dmask;
                            mresp_pre_rsize <= areq_pre_rsize;
                            mresp_pre_rmask <= areq_pre_rmask;
                            mresp_pre_gen_valid <= areq_pre_gen_valid;
                            mresp_direct <= areq_direct;
                            mresp_lb <= areq_lb;
                        end

                        if (mreq_valid) begin
                            areq_addr <= mreq_addr;
                            areq_child_count <= mreq_child_count;
                            areq_id0 <= mreq_id0; areq_id1 <= mreq_id1;
                            areq_id2 <= mreq_id2; areq_id3 <= mreq_id3;
                            areq_imm <= mreq_imm;
                            areq_pred <= mreq_pred;
                            areq_j <= mreq_j;
                            areq_next_j <= req_val[{1'b0,mreq_stage} + 4'd1];
                            areq_has_next2 <= (({1'b0,mreq_stage} + 4'd2) <= H_FUTURE);
                            if (({1'b0,mreq_stage} + 4'd2) <= H_FUTURE)
                                areq_next2_j <= req_val[{1'b0,mreq_stage} + 4'd2];
                            else
                                areq_next2_j <= 7'd0;
                            areq_pre_dsize <= mreq_pre_dsize;
                            areq_pre_dmask <= mreq_pre_dmask;
                            areq_pre_rsize <= mreq_pre_rsize;
                            areq_pre_rmask <= mreq_pre_rmask;
                            areq_pre_gen_valid <= mreq_pre_gen_valid;
                            areq_direct <= mreq_direct;
                            areq_lb <= mreq_lb;
                        end

                        if (actionq_valid && !SEED_MODE) begin
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

                        // EXACT_PRUNE=5/6 search control.  Deliberately placed
                        // before, not inside, the memo hit/miss branch below: none
                        // of these enables may depend on the memo BRAM output
                        // (post-route timing, Arty 100T).  When a memo miss
                        // happens in the same cycle, the miss branch's later
                        // nonblocking writes (actionq_valid, mreq_valid,
                        // f_*[sp] generator restore) override these, which
                        // reproduces the in-branch behavior exactly.  SCAN never
                        // overlaps memo traffic, so its writes cannot conflict.
                        if (SEED_MODE) begin
                            // ---- bound-pipeline output ----
                            // Evaluation packets: prune or forward to the memo
                            // pipeline.  SCAN packets update the running seed;
                            // the last SCAN packet is consumed by the phase
                            // control below in the same cycle.
                            if (bo_v && !bo_kind) begin
                                if (((sp != 0) && f_best_valid[sp] &&
                                     (bo_total >= f_best_cost[sp])) ||
                                    ((sp == 0) && root_best_valid &&
                                     (bo_total > root_best_cost))) begin
                                    // The child's exact value is at least
                                    // bo_total, so it cannot strictly beat the
                                    // incumbent.  The root keeps equal-cost
                                    // children for the segment/tuple tie-break.
                                    // A stale (not yet reduced) incumbent is
                                    // only larger, which prunes less: still exact.
                                    // Not counted when an older packet misses in
                                    // this cycle: this one is then flushed and
                                    // regenerated after the child returns.
                                    if (!(mresp_valid && !memo_pipe_hit))
                                        prune_ctr <= prune_ctr + 1'b1;
                                end
                            end else if (bo_v && !scan_last) begin
                                // SCAN: keep the first child with the
                                // smallest bound as the seed.
                                if (!scan_valid || (bo_total < scan_total)) begin
                                    scan_valid <= 1'b1;
                                    scan_total <= bo_total;
                                    scan_cnt   <= bo_cnt;
                                    scan_ids   <= bo_ids;
                                end
                            end

                            // ---- frame phase control ----
                            case (a_phase)
                                PH_SCAN: begin
                                    if (a_gen_valid) begin
                                        advance_generator;
                                        scan_issued <= 1'b1;
                                        if (scan_issued)
                                            scan_multi <= 1'b1;
                                    end else if (scan_last) begin
                                        // The last SCAN packet is at the output
                                        // now; scan_fin_* already includes it.
                                        if ((sp != 0) && ({1'b0,a_req_idx} == (H_FUTURE-1))) begin
                                            // Every child of this frame has a
                                            // one-request window, so the bounds
                                            // are exact and the SCAN minimum is
                                            // the frame value.  Skip SEED/CANON.
                                            f_best_valid[sp] <= 1'b1;
                                            f_best_cost[sp]  <= scan_fin_total;
                                            fsm_state <= ST_FINISH;
                                        end else begin
                                            // The selected SCAN result starts a
                                            // memo read on this edge. Wait for
                                            // that exact seed before the walk.
                                            a_phase <= PH_SEED;
                                            f_phase[sp] <= PH_SEED;
                                            f_multi[sp] <= scan_multi;
                                        end
                                    end
                                end
                                PH_SEED: begin
                                    // Memo hit or child return advances phase.
                                end
                                default: begin
                                    if (a_gen_valid) begin
                                        advance_generator;
                                    end else if (!bp_busy && !mreq_valid && !areq_valid &&
                                                 !mresp_valid) begin
                                        if (sp == 0) fsm_state <= ST_ROOT_DRAIN;
                                        else         fsm_state <= ST_FINISH;
                                    end
                                end
                            endcase
                        end

                        if (exact_prune_miss) begin
                            // The one-step admissible bound proves that this
                            // memo-miss child cannot improve the incumbent.
                            // Count the examined action/miss, discard younger
                            // speculative requests, and resume immediately at
                            // the following canonical action.
                            miss_ctr <= miss_ctr + 1'b1;
                            act_ctr <= act_ctr + 1'b1;
                            actionq_valid <= 1'b0;
                            mreq_valid <= 1'b0;
                            areq_valid <= 1'b0;
                            mresp_valid <= 1'b0;
                            restore_generator_after_prune(
                                mresp_pre_dsize, mresp_pre_dmask,
                                mresp_pre_rsize, mresp_pre_rmask
                            );
                        end else if (mresp_valid && !memo_pipe_hit) begin
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

                                // The child frame is visible through sp on the
                                // next cycle, so PREP reads it directly.
                                fsm_state <= ST_PREP;
                            end
                        end else begin
                            if (mresp_valid && memo_pipe_hit) begin
                                hit_ctr <= hit_ctr + 1'b1;
                                act_ctr <= act_ctr + 1'b1;
                                eval_pending(memo_child_cost);
                                if (SEED_MODE && (a_phase == PH_SEED)) begin
                                    if (f_multi[sp])
                                        reset_generator_to_first;
                                    else begin
                                        a_gen_valid <= 1'b0;
                                        f_gen_valid[sp] <= 1'b0;
                                    end
                                    a_phase <= PH_CANON;
                                    f_phase[sp] <= PH_CANON;
                                end
                            end

                            if (!SEED_MODE) begin
                                if (can_issue_memo_action) begin
                                    capture_current_action_to_actionq;
                                end else if (!a_gen_valid && !actionq_valid && !mreq_valid && !areq_valid && !mresp_valid &&
                                             !mresp_valid) begin
                                    if (sp == 0) fsm_state <= ST_ROOT_DRAIN;
                                    else         fsm_state <= ST_FINISH;
                                end
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
                    a_phase <= f_phase[sp];
                    fsm_state <= ST_RETURN_EVAL;
                end

                ST_RETURN_EVAL: begin
                    // The parent was restored to the missed action's pre-state.
                    // Commit that action exactly once after the child returns.
                    eval_pending(return_cost);
                    f_pipe_valid[sp] <= 1'b0;
                    // EXACT_PRUNE=5: only the injected seed carries an exhausted
                    // saved generator (canonical packets are captured while the
                    // generator is valid).  A returning seed therefore restarts
                    // the canonical walk from its first action -- any younger
                    // canonical packets were flushed by the seed's miss.
                    if (SEED_MODE && !a_gen_valid) begin
                        if (f_multi[sp])
                            reset_generator_to_first;
                        a_phase <= PH_CANON;
                        f_phase[sp] <= PH_CANON;
                    end else begin
                        advance_generator;
                    end
                    actionq_valid <= 1'b0;
                    mreq_valid <= 1'b0;
                    areq_valid <= 1'b0;
                    mresp_valid <= 1'b0;
                    fsm_state <= ST_RUN;
                end

                ST_ROOT_DRAIN: begin
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
                            policy_actions_last <= act_ctr + prune_ctr;
                            policy_memo_hit_last <= hit_ctr;
                            policy_memo_miss_last <= miss_ctr;
                            policy_cycles_total <= policy_cycles_total + cyc_ctr + 1'b1;
                            policy_actions_total <= policy_actions_total + act_ctr + prune_ctr;
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
                    busy <= 1'b0;
                    done <= 1'b1;
                    policy_cycles_last <= cyc_ctr + 1'b1;
                    policy_actions_last <= act_ctr + prune_ctr;
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
module grover_shadow_j #(
    // Seven draws preserves the legacy latency.  Speculating one request ahead
    // needs H+1 draws, hence H8 needs nine (not eight) future requests.
    parameter integer FUTURE_COUNT = 7,
    parameter integer OUTPUT_COUNT = (FUTURE_COUNT > 8) ? FUTURE_COUNT : 8
) (
    input  wire                         clk,
    input  wire                         rstn,
    input  wire                         start,
    input  wire [31:0]                  post_j_state,
    input  wire [`GP_RROM_IDX_W-1:0]   round_after_current,
    input  wire [31:0]                  L_after_current,
    input  wire [`GP_SHOT_CAP_W-1:0]   trial_after_current,

    output reg                          busy,
    output reg                          done,
    output reg  [OUTPUT_COUNT*`GP_J_W-1:0] future_j_flat,
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
            busy<=1'b0; done<=1'b0; future_j_flat<={(OUTPUT_COUNT*`GP_J_W){1'b0}};
            s<=32'd0; r<=0; L<=0; trial<=0; out_idx<=0;
            shadow_state_final<=0; round_final<=0; L_final<=0; trial_final<=0;
            candidate_draws<=0;
        end else begin
            done<=1'b0;
            if (start && !busy) begin
                busy<=1'b1;
                future_j_flat<={(OUTPUT_COUNT*`GP_J_W){1'b0}};
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
                        if (out_idx == (FUTURE_COUNT-1)) begin
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
