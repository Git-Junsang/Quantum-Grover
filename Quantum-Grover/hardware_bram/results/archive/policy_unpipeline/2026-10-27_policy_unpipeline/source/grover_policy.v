//==============================================================================
// grover_policy.v
// BBHT/Grover checkpoint policy RTL -- Phase 5 policy/speculation bundle
// Date: 2026-08-30
// 2026-09-06: parameterized K/H for E4 K3/H3 experiment; K4/H4 defaults preserved.
// 2026-10-27: remove policy timing-only pipeline boundaries; retain DFS/memo state.
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
    // 0: exhaustive; 1/3: one-step bound; 2/4: two-step bound;
    // 5: seed-first full-horizon bound; 6: also skip a forced root subtree.
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

    localparam SEED_MODE = (EXACT_PRUNE == 5) || (EXACT_PRUNE == 6);
    // Mode 6 preserves the existing sole-root shortcut: root_cost reports
    // its admissible bound; selected checkpoints remain exact.
    localparam ROOT_FORCED = (EXACT_PRUNE == 6);
    localparam [1:0] PH_SCAN=0, PH_SEED=1, PH_CANON=2;

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

    // Only solve state, the DFS stack and synchronous memo-read metadata are
    // registered. BUILD lookup, frame preparation, action sorting, the relaxed
    // bound and root tie-break are combinational; none has a timing-only stage.
    reg [3:0] in_slot_valid;
    reg [27:0] in_slot_j_flat;
    reg [62:0] in_window_flat;
    reg [6:0] univ_val [0:12];
    reg [3:0] univ_count;
    reg [3:0] req_id [0:8];
    reg [6:0] req_val [0:8];
    reg [3:0] req_pool_id [0:8];
    reg [6:0] req_pool_val [0:8];
    reg [3:0] req_pool_count;
    reg [4:0] build_idx;
    reg [2:0] root_init_count;
    reg [15:0] root_init_ids;
    reg [3:0] sp;
    reg [3:0] f_req_idx [0:8];
    reg [2:0] f_count [0:8];
    reg [15:0] f_ids [0:8];
    reg [6:0] f_j [0:8], f_pred [0:8], f_imm [0:8];
    reg [3:0] f_extra_count [0:8];
    reg [35:0] f_extra_ids [0:8];
    reg [2:0] f_keep_count [0:8];
    reg [15:0] f_keep_ids [0:8];
    reg [1:0] f_dsize [0:8];
    reg [8:0] f_dmask [0:8], f_rmask [0:8];
    reg [2:0] f_rsize [0:8];
    reg f_gen_valid [0:8], f_best_valid [0:8];
    reg [10:0] f_best_cost [0:8];
    reg [1:0] f_phase [0:8];
    // A pending child survives a memo miss/recursive descent. These fields
    // are transaction state, not a sort/rank/evaluation pipeline.
    reg [2:0] f_pending_count [0:8];
    reg [15:0] f_pending_ids [0:8];
    reg f_pending_seed [0:8];
    reg scan_valid, scan_multi;
    reg [10:0] scan_total;
    reg [2:0] scan_count;
    reg [15:0] scan_ids;
    reg [2:0] root_best_seg, root_best_count;
    reg [27:0] root_best_values;
    reg [10:0] return_cost;
    reg [31:0] cyc_ctr, act_ctr, hit_ctr, miss_ctr;
    reg [13:0] clear_ctr;
    reg memo_needs_clear;
    localparam [3:0] ST_IDLE=0, ST_CLEAR=1, ST_BUILD=2, ST_ROOT_INIT=3,
        ST_PREP=4, ST_RUN=5, ST_MEMO=6, ST_RETURN=7, ST_FINISH=8, ST_ABORT=9;
    reg [3:0] fsm_state;

    reg build_valid, build_found, pool_found;
    reg [6:0] build_value;
    reg [3:0] build_id;
    integer bi;
    always @* begin
        build_valid = (build_idx < 4) ? in_slot_valid[build_idx] : 1'b1;
        build_value = (build_idx < 4) ?
            in_slot_j_flat[build_idx*7 +: 7] : in_window_flat[(build_idx-4)*7 +: 7];
        build_found = 1'b0;
        build_id = univ_count;
        for (bi=0; bi<13; bi=bi+1)
            if ((bi < univ_count) && (univ_val[bi] == build_value)) begin
                build_found = 1'b1;
                build_id = bi[3:0];
            end
        pool_found = 1'b0;
        for (bi=0; bi<9; bi=bi+1)
            if ((bi < req_pool_count) && (req_pool_id[bi] == build_id))
                pool_found = 1'b1;
    end

    // Prepare a complete frame directly from its architectural stack entry.
    // Keep the original request-pool insertion order and canonical action walk.
    reg [6:0] prep_j, prep_pred, prep_v;
    reg [3:0] prep_jid, prep_extra_count, prep_id;
    reg [2:0] prep_keep_count;
    reg [15:0] prep_keep_ids;
    reg [35:0] prep_extra_ids;
    reg prep_member;
    integer pi, pj;
    always @* begin
        prep_j = req_val[f_req_idx[sp]];
        prep_jid = req_id[f_req_idx[sp]];
        prep_pred = 7'd0;
        prep_v = 7'd0;
        prep_id = 4'd0;
        prep_keep_count = 0;
        prep_keep_ids = 0;
        prep_extra_count = 0;
        prep_extra_ids = 0;
        prep_member = 0;
        for (pi=0; pi<4; pi=pi+1) begin
            prep_v = univ_val[f_ids[sp][pi*4 +: 4]];
            if (pi < f_count[sp]) begin
                if ((prep_v <= prep_j) && (prep_v > prep_pred)) prep_pred = prep_v;
                if (f_ids[sp][pi*4 +: 4] != prep_jid) begin
                    prep_keep_ids[prep_keep_count*4 +: 4] = f_ids[sp][pi*4 +: 4];
                    prep_keep_count = prep_keep_count + 1'b1;
                end
            end
        end
        for (pi=0; pi<9; pi=pi+1) begin
            prep_id = req_pool_id[pi];
            prep_member = 0;
            for (pj=0; pj<4; pj=pj+1)
                if ((pj < f_count[sp]) && (f_ids[sp][pj*4 +: 4] == prep_id))
                    prep_member = 1;
            if ((pi < req_pool_count) && !prep_member &&
                (req_pool_val[pi] > prep_pred) && (req_pool_val[pi] < prep_j)) begin
                prep_extra_ids[prep_extra_count*4 +: 4] = prep_id;
                prep_extra_count = prep_extra_count + 1'b1;
            end
        end
    end

    function [15:0] sort_ids;
        input [15:0] ids;
        reg [3:0] values [0:3];
        reg [3:0] swap;
        integer i,j;
        begin
            for (i=0; i<4; i=i+1) values[i] = ids[i*4 +: 4];
            for (i=0; i<4; i=i+1)
                for (j=i+1; j<4; j=j+1)
                    if (values[j] < values[i]) begin
                        swap=values[i]; values[i]=values[j]; values[j]=swap;
                    end
            for (i=0; i<4; i=i+1) sort_ids[i*4 +: 4] = values[i];
        end
    endfunction

    reg [15:0] action_raw_ids, action_ids;
    reg [2:0] action_count;
    integer ai, ac;
    always @* begin
        action_raw_ids = 16'hffff;
        action_raw_ids[3:0] = req_id[f_req_idx[sp]];
        ac = 1;
        for (ai=0; ai<9; ai=ai+1)
            if (f_dmask[sp][ai] && (ac < CKPT_K)) begin
                action_raw_ids[ac*4 +: 4] = f_extra_ids[sp][ai*4 +: 4];
                ac = ac + 1;
            end
        for (ai=0; ai<4; ai=ai+1)
            if (f_rmask[sp][ai] && (ac < CKPT_K)) begin
                action_raw_ids[ac*4 +: 4] = f_keep_ids[sp][ai*4 +: 4];
                ac = ac + 1;
            end
        action_count = ac[2:0];
        action_ids = sort_ids(action_raw_ids);
    end

    // Capacity-relaxed admissible bound. All future request steps are evaluated
    // in one combinational cone. The held mask uses universe IDs, so sorted-rank
    // capture registers and the H-stage bound packet pipeline are unnecessary.
    function [10:0] lower_bound;
        input [2:0] count;
        input [15:0] ids;
        input [3:0] head;
        input integer depth;
        reg [12:0] held;
        reg [6:0] pred;
        integer i,t;
        begin
            held = 0;
            for (i=0; i<4; i=i+1)
                if (i < count) held[ids[i*4 +: 4]] = 1'b1;
            lower_bound = 0;
            for (t=1; t<=H_FUTURE; t=t+1)
                if ((t > head) && (t <= (head + depth))) begin
                    pred = 0;
                    for (i=0; i<13; i=i+1)
                        if ((i < univ_count) && held[i] &&
                            (univ_val[i] <= req_val[t]) && (univ_val[i] > pred))
                            pred = univ_val[i];
                    lower_bound = lower_bound + {4'd0,req_val[t] - pred};
                    held[req_id[t]] = 1'b1;
                    for (i=0; i<9; i=i+1)
                        if ((i < req_pool_count) && (req_pool_val[i] > pred) &&
                            (req_pool_val[i] < req_val[t])) held[req_pool_id[i]] = 1'b1;
                end
        end
    endfunction

    wire [10:0] action_tail = lower_bound(action_count, action_ids, f_req_idx[sp],
        SEED_MODE ? H_FUTURE : (((EXACT_PRUNE == 2) || (EXACT_PRUNE == 4)) ? 2 : 1));
    wire [10:0] action_total = {4'd0,f_imm[sp]} + action_tail;
    wire action_pruned = (EXACT_PRUNE != 0) && f_best_valid[sp] &&
        ((sp == 0) ? (action_total > f_best_cost[sp]) : (action_total >= f_best_cost[sp]));
    wire seed_issue = SEED_MODE && (f_phase[sp] == PH_SEED);
    wire [2:0] issue_count = seed_issue ? scan_count : action_count;
    wire [15:0] issue_ids = seed_issue ? scan_ids : action_ids;
    wire forced_root = seed_issue && ROOT_FORCED && (sp == 0) && !scan_multi;
    wire action_limit = (ACTION_LIMIT != 0) && (act_ctr >= ACTION_LIMIT);
    wire memo_rd_en = busy && (fsm_state == ST_RUN) && !action_limit &&
        (seed_issue ? !forced_root : (f_gen_valid[sp] &&
            !(SEED_MODE && (f_phase[sp] == PH_SCAN)) && !action_pruned));
    wire [13:0] memo_rd_addr = memo_addr_of(f_req_idx[sp][2:0],
        rank_state(issue_count,issue_ids[3:0],issue_ids[7:4],issue_ids[11:8],issue_ids[15:12]));
    wire [17:0] memo_rd_data;
    reg memo_wr_en, memo_clear_en;
    reg [13:0] memo_wr_addr, memo_clear_addr;
    reg [17:0] memo_wr_data;
    grover_ckpt_policy_memo #(.COMPACT_K3H3(COMPACT_K3H3), .FIVE_BANKS(MEM_ENTRIES > 8192))
        u_policy_memo (.clk(clk), .rd_en(memo_rd_en), .rd_addr(memo_rd_addr),
        .rd_data(memo_rd_data), .wr_en(memo_wr_en), .wr_addr(memo_wr_addr),
        .wr_data(memo_wr_data), .clear_en(memo_clear_en), .clear_addr(memo_clear_addr));

    task reset_generator;
        begin
            f_dsize[sp] <= 0;
            f_dmask[sp] <= 0;
            f_rsize[sp] <= (f_keep_count[sp] < CKPT_K-1) ? f_keep_count[sp] : CKPT_K-1;
            f_rmask[sp] <= first_comb9((f_keep_count[sp] < CKPT_K-1) ? f_keep_count[sp] : CKPT_K-1);
            f_gen_valid[sp] <= 1;
        end
    endtask

    task advance_generator;
        reg [1:0] nd;
        reg [2:0] nr;
        begin
            if (comb_has_next9(f_rmask[sp], {1'b0,f_keep_count[sp]}, f_rsize[sp]))
                f_rmask[sp] <= next_comb9(f_rmask[sp], {1'b0,f_keep_count[sp]}, f_rsize[sp]);
            else if (comb_has_next9(f_dmask[sp], f_extra_count[sp], {1'b0,f_dsize[sp]})) begin
                f_dmask[sp] <= next_comb9(f_dmask[sp], f_extra_count[sp], {1'b0,f_dsize[sp]});
                f_rmask[sp] <= first_comb9(f_rsize[sp]);
            end else if ((f_dsize[sp] < CKPT_K-1) && ((f_dsize[sp]+1'b1) <= f_extra_count[sp])) begin
                nd = f_dsize[sp]+1'b1;
                nr = (f_keep_count[sp] < CKPT_K-1-nd) ? f_keep_count[sp] : CKPT_K-1-nd;
                f_dsize[sp] <= nd;
                f_dmask[sp] <= first_comb9({1'b0,nd});
                f_rsize[sp] <= nr;
                f_rmask[sp] <= first_comb9(nr);
            end else f_gen_valid[sp] <= 0;
        end
    endtask

    // Evaluate against the current incumbent on the same edge as a memo hit or
    // child return. Root metadata is sorted by VALUE, not by universe ID; these
    // orders differ whenever physical checkpoints were inserted out of order.
    task evaluate;
        input [10:0] child_cost;
        input [2:0] count;
        input [15:0] ids;
        reg [10:0] total;
        reg [6:0] values [0:3];
        reg [6:0] swap;
        reg [2:0] segments;
        reg better;
        integer i,j;
        begin
            total = {4'd0,f_imm[sp]} + child_cost;
            for (i=0; i<4; i=i+1)
                values[i] = (i < count) ? univ_val[ids[i*4 +: 4]] : 7'h7f;
            for (i=0; i<4; i=i+1)
                for (j=i+1; j<4; j=j+1)
                    if (values[j] < values[i]) begin
                        swap=values[i]; values[i]=values[j]; values[j]=swap;
                    end
            segments = 1;
            for (i=0; i<4; i=i+1)
                if ((i < count) && (values[i] > f_pred[sp]) && (values[i] < f_j[sp]))
                    segments = segments + 1'b1;
            better = !f_best_valid[sp] || (total < f_best_cost[sp]);
            if ((sp == 0) && f_best_valid[sp] && (total == f_best_cost[sp]))
                better = (segments < root_best_seg) || ((segments == root_best_seg) &&
                    lex_less4(count,values[0],values[1],values[2],values[3],root_best_count,
                        root_best_values[6:0],root_best_values[13:7],root_best_values[20:14],root_best_values[27:21]));
            if (better) begin
                f_best_valid[sp] <= 1;
                f_best_cost[sp] <= total;
                if (sp == 0) begin
                    root_best_seg <= segments;
                    root_best_count <= count;
                    root_best_values <= {values[3],values[2],values[1],values[0]};
                end
            end
        end
    endtask

    task complete_action;
        begin
            if (f_pending_seed[sp]) begin
                f_phase[sp] <= PH_CANON;
                // A single child needs no second canonical evaluation.
                if (f_gen_valid[sp]) reset_generator;
            end else advance_generator;
            fsm_state <= ST_RUN;
        end
    endtask

    integer si;
    always @(posedge clk) begin
        if (!rstn) begin
            busy<=0; done<=0; policy_error<=0; source_j<=0; next_count<=0; next_j_flat<=0;
            root_cost<=0; root_segment_count<=0; policy_cycles_last<=0; policy_actions_last<=0;
            policy_memo_hit_last<=0; policy_memo_miss_last<=0; policy_cycles_total<=0;
            policy_actions_total<=0; policy_max_latency<=0; policy_epoch<=0;
            in_slot_valid<=0; in_slot_j_flat<=0; in_window_flat<=0;
            univ_count<=0; req_pool_count<=0; build_idx<=0; root_init_count<=0; root_init_ids<=0;
            sp<=0; scan_valid<=0; scan_multi<=0; scan_total<=INF_COST; scan_count<=0; scan_ids<=0;
            root_best_seg<=0; root_best_count<=0; root_best_values<=0; return_cost<=0;
            cyc_ctr<=0; act_ctr<=0; hit_ctr<=0; miss_ctr<=0; clear_ctr<=0; memo_needs_clear<=1;
            memo_wr_en<=0; memo_wr_addr<=0; memo_wr_data<=0; memo_clear_en<=0; memo_clear_addr<=0;
            fsm_state<=ST_IDLE;
            for (si=0; si<13; si=si+1) univ_val[si]<=0;
            for (si=0; si<9; si=si+1) begin
                req_id[si]<=0; req_val[si]<=0; req_pool_id[si]<=0; req_pool_val[si]<=0;
                f_req_idx[si]<=0; f_count[si]<=0; f_ids[si]<=0;
                f_j[si]<=0; f_pred[si]<=0; f_imm[si]<=0; f_extra_count[si]<=0; f_extra_ids[si]<=0;
                f_keep_count[si]<=0; f_keep_ids[si]<=0; f_dsize[si]<=0; f_dmask[si]<=0;
                f_rsize[si]<=0; f_rmask[si]<=0; f_gen_valid[si]<=0;
                f_best_valid[si]<=0; f_best_cost[si]<=INF_COST; f_phase[si]<=PH_SCAN;
                f_pending_count[si]<=0; f_pending_ids[si]<=0; f_pending_seed[si]<=0;
            end
        end else begin
            done<=0; memo_wr_en<=0; memo_clear_en<=0;
            if (busy) cyc_ctr<=cyc_ctr+1'b1;
            case (fsm_state)
                ST_IDLE: if (start) begin
                    busy<=1; policy_error<=0;
                    in_slot_valid<=slot_valid; in_slot_j_flat<=slot_j_flat; in_window_flat<=j_window_flat;
                    cyc_ctr<=0; act_ctr<=0; hit_ctr<=0; miss_ctr<=0;
                    univ_count<=0; req_pool_count<=0; build_idx<=0; root_init_count<=0; root_init_ids<=0;
                    next_count<=0; next_j_flat<=0; root_cost<=0; root_segment_count<=0;
                    if (memo_needs_clear || (policy_epoch == 8'hff)) begin
                        policy_epoch<=1; clear_ctr<=0; memo_needs_clear<=0; fsm_state<=ST_CLEAR;
                    end else begin
                        policy_epoch<=policy_epoch+1'b1; fsm_state<=ST_BUILD;
                    end
                end
                ST_CLEAR: begin
                    memo_clear_en<=1; memo_clear_addr<=clear_ctr;
                    if (clear_ctr == MEM_ENTRIES-1) fsm_state<=ST_BUILD;
                    else clear_ctr<=clear_ctr+1'b1;
                end
                ST_BUILD: begin
                    if (build_valid && (((build_idx < 4) && build_found) ||
                        (!build_found && (univ_count >= U_MAX)) ||
                        ((build_idx < 4) && (root_init_count >= CKPT_K)))) begin
                        policy_error<=1; fsm_state<=ST_ABORT;
                    end else begin
                        if (build_valid) begin
                            if (!build_found) begin
                                univ_val[univ_count]<=build_value; univ_count<=univ_count+1'b1;
                            end
                            if (build_idx < 4) begin
                                root_init_ids[root_init_count*4 +: 4]<=build_id;
                                root_init_count<=root_init_count+1'b1;
                            end else begin
                                req_id[build_idx-4]<=build_id; req_val[build_idx-4]<=build_value;
                                if (!pool_found) begin
                                    req_pool_id[req_pool_count]<=build_id;
                                    req_pool_val[req_pool_count]<=build_value;
                                    req_pool_count<=req_pool_count+1'b1;
                                end
                            end
                        end
                        if (build_idx == 4+WINDOW_LEN-1) fsm_state<=ST_ROOT_INIT;
                        else build_idx<=build_idx+1'b1;
                    end
                end
                ST_ROOT_INIT: begin
                    sp<=0; f_req_idx[0]<=0; f_count[0]<=root_init_count;
                    f_ids[0]<=sort_ids(root_init_ids | (16'hffff << (root_init_count*4)));
                    fsm_state<=ST_PREP;
                end
                ST_PREP: begin
                    f_j[sp]<=prep_j; f_pred[sp]<=prep_pred; f_imm[sp]<=prep_j-prep_pred;
                    f_extra_count[sp]<=prep_extra_count; f_extra_ids[sp]<=prep_extra_ids;
                    f_keep_count[sp]<=prep_keep_count; f_keep_ids[sp]<=prep_keep_ids;
                    f_dsize[sp]<=0; f_dmask[sp]<=0;
                    f_rsize[sp]<=(prep_keep_count < CKPT_K-1) ? prep_keep_count : CKPT_K-1;
                    f_rmask[sp]<=first_comb9((prep_keep_count < CKPT_K-1) ? prep_keep_count : CKPT_K-1);
                    f_gen_valid[sp]<=1; f_best_valid[sp]<=0; f_best_cost[sp]<=INF_COST;
                    f_phase[sp]<=PH_SCAN; scan_valid<=0; scan_multi<=0; scan_total<=INF_COST;
                    if (sp == 0) source_j<=prep_pred;
                    if (f_req_idx[sp] >= H_FUTURE) begin
                        f_best_valid[sp]<=1; f_best_cost[sp]<={4'd0,prep_j-prep_pred};
                        act_ctr<=act_ctr+1'b1; fsm_state<=ST_FINISH;
                    end else fsm_state<=ST_RUN;
                end
                ST_RUN: begin
                    if (action_limit) begin
                        policy_error<=1; fsm_state<=ST_ABORT;
                    end else if (SEED_MODE && (f_phase[sp] == PH_SCAN)) begin
                        if (f_gen_valid[sp]) begin
                            if (!scan_valid || (action_total < scan_total)) begin
                                scan_total<=action_total; scan_count<=action_count; scan_ids<=action_ids;
                            end
                            scan_multi<=scan_valid; scan_valid<=1;
                            advance_generator;
                        end else if ((sp != 0) && (f_req_idx[sp] == H_FUTURE-1)) begin
                            f_best_valid[sp]<=1; f_best_cost[sp]<=scan_total; fsm_state<=ST_FINISH;
                        end else begin
                            f_phase[sp]<=PH_SEED;
                            // Remember whether a canonical walk is needed across
                            // descent; the global scan record can then be reused.
                            f_gen_valid[sp]<=scan_multi;
                        end
                    end else if (forced_root) begin
                        evaluate(scan_total-{4'd0,f_imm[sp]},scan_count,scan_ids);
                        act_ctr<=act_ctr+1'b1; f_gen_valid[sp]<=0;
                        f_phase[sp]<=PH_CANON; fsm_state<=ST_FINISH;
                    end else if (seed_issue || f_gen_valid[sp]) begin
                        act_ctr<=act_ctr+1'b1;
                        if (!seed_issue && action_pruned) advance_generator;
                        else begin
                            f_pending_count[sp]<=issue_count; f_pending_ids[sp]<=issue_ids;
                            f_pending_seed[sp]<=seed_issue; fsm_state<=ST_MEMO;
                        end
                    end else fsm_state<=ST_FINISH;
                end
                ST_MEMO: begin
                    // The preceding ST_RUN edge read the BRAM and captured its
                    // child metadata. No address/result timing registers intervene.
                    if (memo_rd_data[17:10] == policy_epoch) begin
                        hit_ctr<=hit_ctr+1'b1;
                        evaluate({1'b0,memo_rd_data[9:0]},f_pending_count[sp],f_pending_ids[sp]);
                        complete_action;
                    end else begin
                        miss_ctr<=miss_ctr+1'b1;
                        if (sp >= 8) begin policy_error<=1; fsm_state<=ST_ABORT; end
                        else begin
                            f_req_idx[sp+1]<=f_req_idx[sp]+1'b1;
                            f_count[sp+1]<=f_pending_count[sp]; f_ids[sp+1]<=f_pending_ids[sp];
                            sp<=sp+1'b1; fsm_state<=ST_PREP;
                        end
                    end
                end
                ST_RETURN: begin
                    evaluate(return_cost,f_pending_count[sp],f_pending_ids[sp]);
                    complete_action;
                end
                ST_FINISH: begin
                    if (!f_best_valid[sp]) begin policy_error<=1; fsm_state<=ST_ABORT; end
                    else if (sp != 0) begin
                        memo_wr_en<=1;
                        memo_wr_addr<=memo_addr_of(f_req_idx[sp]-1'b1,
                            rank_state(f_count[sp],f_ids[sp][3:0],f_ids[sp][7:4],f_ids[sp][11:8],f_ids[sp][15:12]));
                        memo_wr_data<={policy_epoch,f_best_cost[sp][9:0]};
                        return_cost<=f_best_cost[sp]; sp<=sp-1'b1; fsm_state<=ST_RETURN;
                    end else begin
                        root_cost<=f_best_cost[0]; root_segment_count<=root_best_seg; next_count<=root_best_count;
                        for (si=0; si<4; si=si+1)
                            next_j_flat[si*7 +: 7]<=(si < root_best_count) ? root_best_values[si*7 +: 7] : 7'd0;
                        busy<=0; done<=1; fsm_state<=ST_IDLE;
                        policy_cycles_last<=cyc_ctr+1'b1; policy_actions_last<=act_ctr;
                        policy_memo_hit_last<=hit_ctr; policy_memo_miss_last<=miss_ctr;
                        policy_cycles_total<=policy_cycles_total+cyc_ctr+1'b1;
                        policy_actions_total<=policy_actions_total+act_ctr;
                        if (cyc_ctr+1'b1 > policy_max_latency) policy_max_latency<=cyc_ctr+1'b1;
                    end
                end
                ST_ABORT: begin
                    busy<=0; done<=1; fsm_state<=ST_IDLE;
                    policy_cycles_last<=cyc_ctr+1'b1; policy_actions_last<=act_ctr;
                    policy_memo_hit_last<=hit_ctr; policy_memo_miss_last<=miss_ctr;
                    policy_cycles_total<=policy_cycles_total+cyc_ctr+1'b1;
                    policy_actions_total<=policy_actions_total+act_ctr;
                    if (cyc_ctr+1'b1 > policy_max_latency) policy_max_latency<=cyc_ctr+1'b1;
                end
                default: begin policy_error<=1; fsm_state<=ST_ABORT; end
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
