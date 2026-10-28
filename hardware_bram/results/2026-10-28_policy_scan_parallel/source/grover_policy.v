//==============================================================================
// grover_policy.v
// BBHT/Grover checkpoint policy RTL -- Phase 5 policy/speculation bundle
// Date: 2026-08-30
// 2026-09-06: parameterized K/H for E4 K3/H3 experiment; K4/H4 defaults preserved.
// 2026-10-27: remove the policy timing-only BUILD/PREP/evaluation registers.
// Keep the synchronous memo read alignment and the full-horizon bound stages,
// which carry architectural transactions rather than delaying control for WNS.
// 2026-10-28: skip solved seeds and evaluate relaxed cost in parallel gaps.
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
//      - top-down DFS with synchronous memo lookup
//      - active-frame + active-pending mirrors remove variable-index stack muxes
//      - combinational BUILD/PREP/action/rank/evaluation control; no WNS-only delay stages
//      - one response-alignment register remains for the synchronous memo BRAM
//      - fixed-depth 4-way sorting networks on action/value paths
//      - eligibility predicates are factored from the predecessor max-tree
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
// Capacity-relaxed cost evaluated by gaps between initial checkpoints.
//
// Within one gap, processing a new largest request deposits every smaller
// request-pool value up to that endpoint. All remaining requests belong to the
// pool. Later requests at or below the endpoint therefore cost zero, while a
// larger endpoint pays only the extension. Costs telescope to max(request)-lo
// in each gap, independently of request order. Requests already held cost zero.
// The implicit checkpoint 0 supplies the first gap's lower endpoint.
//
// Two data stages: capture child/future masks, then find each gap's source and
// largest request in parallel. The caller registers the balanced cost sum with
// the packet metadata. Latency is independent of H; logic size grows with UB.
// values_flat is constant during a solve, and validity/flush belongs to caller.
//------------------------------------------------------------------------------
module grover_ckpt_gap_bound #(
    parameter integer UB = 7
) (
    input wire clk,
    input wire [UB-1:0] child_mask,
    input wire [UB-1:0] future_mask,
    input wire [7*UB-1:0] values_flat,
    output wire [10:0] cost
);
    localparam integer SUM_LEAVES = 1 << $clog2(UB+1);
    reg [UB-1:0] child_q, future_q;
    // Each array element is a separate acyclic adder node. Ask Verilator to
    // track them separately too, avoiding a false whole-array feedback path.
    wire [10:0] sum_tree [1:2*SUM_LEAVES-1] /* verilator split_var */;

    function [UB-1:0] spread_down;
        input [UB-1:0] mask;
        integer shift;
        reg [UB-1:0] bits;
        begin
            bits = mask;
            for (shift=1; shift<UB; shift=shift*2)
                bits = bits | (bits >> shift);
            spread_down = bits;
        end
    endfunction

    function [UB-1:0] highest_onehot;
        input [UB-1:0] mask;
        begin highest_onehot = mask & ~(spread_down(mask) >> 1); end
    endfunction

    function [6:0] value_of;
        input [UB-1:0] onehot;
        input [7*UB-1:0] rank_values;
        integer rank;
        begin
            value_of = 7'd0;
            for (rank=0; rank<UB; rank=rank+1)
                value_of = value_of | ({7{onehot[rank]}} & rank_values[7*rank +: 7]);
        end
    endfunction

    always @(posedge clk) begin
        child_q <= child_mask;
        future_q <= future_mask;
    end

    genvar gap, node;
    generate
        for (gap=0; gap<=UB; gap=gap+1) begin : g_gap
            // A held rank is a gap's exclusive upper boundary. UB is the
            // final open boundary above the largest representable value.
            localparam [UB-1:0] BELOW = {UB{1'b1}} >> (UB-gap);
            wire active;
            if (gap < UB) begin : g_finite
                assign active = child_q[gap];
            end else begin : g_open
                assign active = 1'b1;
            end
            wire [UB-1:0] lower_children = child_q & BELOW;
            wire [UB-1:0] requests = future_q & BELOW & ~spread_down(lower_children);
            reg [UB-1:0] source_oh, request_oh;
            always @(posedge clk) begin
                source_oh <= highest_onehot(lower_children);
                request_oh <= active ? highest_onehot(requests) : {UB{1'b0}};
            end
            assign sum_tree[SUM_LEAVES+gap] = (|request_oh) ?
                ({4'd0,value_of(request_oh,values_flat)} -
                 {4'd0,value_of(source_oh,values_flat)}) : 11'd0;
        end
        for (gap=UB+1; gap<SUM_LEAVES; gap=gap+1) begin : g_pad
            assign sum_tree[SUM_LEAVES+gap] = 11'd0;
        end
        for (node=1; node<SUM_LEAVES; node=node+1) begin : g_sum
            assign sum_tree[node] = sum_tree[2*node] + sum_tree[2*node+1];
        end
    endgenerate
    assign cost = sum_tree[1];
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
// Banked scan-result store. SCAN writes one candidate per clock; canonical
// replay reads a group of LANES candidates together. Frames occupy disjoint
// address ranges, so child recursion never overwrites an unfinished parent.
// One SCAN lane: compact a legal action, evaluate its relaxed bound, and
// preserve its canonical tuple. The three data stages carry useful work;
// independent lanes increase throughput without adding WNS-only delays.
module grover_policy_scan_bound #(
    parameter integer UB=7
) (
    input wire clk,
    input wire [3:0] endpoint,
    input wire [35:0] extras,
    input wire [15:0] retained,
    input wire [23:0] iterator_state,
    input wire [4*UB-1:0] positions,
    input wire [7*UB-1:0] values,
    input wire [UB-1:0] future_mask,
    output reg [31:0] packet
);
    wire [8:0] deposits=iterator_state[10:2];
    wire [8:0] keeps=iterator_state[22:14];
    wire [2:0] count=3'd1+{1'b0,iterator_state[1:0]}+iterator_state[13:11];
    reg [15:0] raw_ids;
    integer item, used;
    always @* begin
        raw_ids=16'hffff;
        raw_ids[3:0]=endpoint;
        used=1;
        for (item=0; item<9; item=item+1)
            if (deposits[item] && used<4) begin
                raw_ids[4*used +: 4]=extras[4*item +: 4];
                used=used+1;
            end
        for (item=0; item<4; item=item+1)
            if (keeps[item] && used<4) begin
                raw_ids[4*used +: 4]=retained[4*item +: 4];
                used=used+1;
            end
    end
    function [UB-1:0] rank_bit;
        input [3:0] id;
        input [4*UB-1:0] pos;
        begin rank_bit={{(UB-1){1'b0}},1'b1} << pos[4*id +: 4]; end
    endfunction
    wire [UB-1:0] mask_tree [1:31] /* verilator split_var */;
    assign mask_tree[16]=rank_bit(endpoint,positions);
    genvar p;
    generate
        for (p=0; p<9; p=p+1) begin : g_extra
            assign mask_tree[17+p]={UB{deposits[p]}} & rank_bit(extras[4*p +: 4],positions);
        end
        for (p=0; p<4; p=p+1) begin : g_keep
            assign mask_tree[26+p]={UB{keeps[p]}} & rank_bit(retained[4*p +: 4],positions);
        end
        for (p=30; p<32; p=p+1) begin : g_pad
            assign mask_tree[p]={UB{1'b0}};
        end
        for (p=1; p<16; p=p+1) begin : g_or
            assign mask_tree[p]=mask_tree[2*p] | mask_tree[2*p+1];
        end
    endgenerate
    wire [10:0] tail_cost;
    grover_ckpt_gap_bound #(.UB(UB)) u_bound (
        .clk(clk),.child_mask(mask_tree[1]),.future_mask(future_mask),
        .values_flat(values),.cost(tail_cost)
    );
    reg [15:0] ids0,ids1;
    reg [2:0] count0,count1;
    reg [1:0] deposits0,deposits1;
    reg [3:0] v0,v1,v2,v3,t;
    always @* begin
        v0=ids1[3:0]; v1=ids1[7:4]; v2=ids1[11:8]; v3=ids1[15:12]; t=0;
        if (v0>v1) begin t=v0; v0=v1; v1=t; end
        if (v2>v3) begin t=v2; v2=v3; v3=t; end
        if (v0>v2) begin t=v0; v0=v2; v2=t; end
        if (v1>v3) begin t=v1; v1=v3; v3=t; end
        if (v1>v2) begin t=v1; v1=v2; v2=t; end
    end
    always @(posedge clk) begin
        ids0<=raw_ids; ids1<=ids0;
        count0<=count; count1<=count0;
        deposits0<=iterator_state[1:0]; deposits1<=deposits0;
        packet<={count1,v3,v2,v1,v0,deposits1,tail_cost};
    end
endmodule

module grover_policy_action_cache #(
    parameter integer LANES = 4,
    parameter integer ADDR_W = 5,
    parameter integer DEPTH = 32
) (
    input wire clk,
    input wire [LANES-1:0] wr_en,
    input wire [ADDR_W-1:0] wr_addr,
    input wire [32*LANES-1:0] wr_data,
    input wire rd_en,
    input wire [ADDR_W-1:0] rd_addr,
    output wire [32*LANES-1:0] rd_data
);
    localparam integer WR_LANE_W = LANES<=1 ? 1 : $clog2(LANES);
    genvar bank;
    generate
        for (bank=0; bank<LANES; bank=bank+1) begin : g_bank
            (* ram_style = "block" *) reg [31:0] mem [0:DEPTH-1];
            reg [31:0] q;
            always @(posedge clk) begin
                if (wr_en[bank]) mem[wr_addr] <= wr_data[32*bank +: 32];
                if (rd_en) q <= mem[rd_addr];
            end
            assign rd_data[32*bank +: 32] = q;
        end
    endgenerate
endmodule

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
    // first scans all legal children through a fixed-depth gap bound
    // pipeline, evaluates the child with the smallest bound exactly, and then
    // walks the canonical action order pruning every child whose bound cannot
    // beat the incumbent.  Only the search order and the set of evaluated
    // children change; action space, objective and root tie-break do not.
    parameter integer EXACT_PRUNE  = 0,
    // Default parameters preserve the frozen K4/H4 behavior.  The E4/K3H3
    // branch overrides these to CKPT_K=3, H_FUTURE=3.
    parameter integer CKPT_K       = 4,
    parameter integer H_FUTURE     = 4,
    // Independent canonical-bound filters per clock. Only the first surviving
    // action uses the single synchronous memo port. 1/2/4 retain exact order.
    parameter integer CANON_LANES  = 4,
    // SCAN candidates per clock. The cache has CANON_LANES banks; a SCAN
    // batch must fit those banks. Limited-action compatibility uses one lane.
    parameter integer SCAN_LANES   = CANON_LANES
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
    // are unchanged. A forced root now returns before SCAN: root_cost reports
    // the immediate cost alone, an admissible lower bound, rather than waiting
    // for the full-horizon relaxed cost. Main IP does not use root_cost to
    // choose or execute a plan. Multi-action roots still report exact DP cost.
    localparam ROOT_FORCED = (EXACT_PRUNE == 6);
    localparam integer UB = U_MAX;
    function integer cache_action_bound;
        input integer n, k;
        integer i, combination, total;
        begin
            combination=1; total=1;
            for (i=1; i<=k; i=i+1) begin
                combination=combination*(n-i+1)/i;
                total=total+combination;
            end
            cache_action_bound=total;
        end
    endfunction
    // Every child contains the endpoint, leaving at most K-1 choices from
    // U-1 other values. This bounds every SCAN, including partially full sets.
    localparam integer CACHE_MAX_ACTIONS = cache_action_bound(U_MAX-1,CKPT_K-1);
    localparam integer CACHE_LANE_BITS = (CANON_LANES<=1) ? 0 : $clog2(CANON_LANES);
    localparam integer CACHE_INDEX_W = ($clog2(CACHE_MAX_ACTIONS+1) > CACHE_LANE_BITS+1) ?
        $clog2(CACHE_MAX_ACTIONS+1) : CACHE_LANE_BITS+1;
    localparam integer CACHE_GROUP_W = CACHE_INDEX_W-CACHE_LANE_BITS;
    localparam integer CACHE_FRAME_W = $clog2(H_FUTURE+1);
    localparam integer CACHE_ADDR_W = CACHE_FRAME_W+CACHE_GROUP_W;
    localparam integer CACHE_GROUPS = 1 << CACHE_GROUP_W;
    localparam integer CACHE_DEPTH = (H_FUTURE+1)*CACHE_GROUPS;
    localparam [2:0] ROOT_CAPACITY = CKPT_K[2:0];
    localparam [CACHE_INDEX_W:0] CACHE_LIMIT_COUNT = CACHE_MAX_ACTIONS[CACHE_INDEX_W:0];
`ifndef SYNTHESIS
    initial if (CANON_LANES != 1 && CANON_LANES != 2 && CANON_LANES != 4)
        $fatal(1,"CANON_LANES must be 1, 2 or 4");
    initial if ((SCAN_LANES!=1 && SCAN_LANES!=2 && SCAN_LANES!=4) || SCAN_LANES>CANON_LANES)
        $fatal(1,"SCAN_LANES must be 1, 2 or 4 and <= CANON_LANES");
`endif
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

    // -------------------------------------------------------------------------
    // Latched solve input, per-solve local universe, request-local IDs.
    // The request-only pool is deduplicated once during ST_BUILD.  That removes
    // the old 9x9 dedup/range scan from every action issue and is the main
    // timing-oriented refactor in this revision.
    // -------------------------------------------------------------------------
    reg [3:0] in_slot_valid;
    reg [4*`GP_J_W-1:0] in_slot_j_flat;
    reg [9*`GP_J_W-1:0] in_window_flat;

    // Detect a forced root directly from the input snapshot. No universe IDs,
    // ranks or memo data are needed when every old checkpoint fits beside the
    // endpoint and no request-pool deposit lies on the source->endpoint path.
    // This reuses the first BUILD edge as the decision edge instead of paying
    // the whole BUILD/ROOT_INIT/PREP path for a unique plan.
    reg [2:0] early_root_count;
    reg early_root_has_endpoint, early_root_duplicate, early_root_extra;
    reg [6:0] early_root_pred;
    reg [6:0] early_root_values [0:3];
    reg [6:0] early_root_pair0, early_root_pair1;
    reg [6:0] early_root_p0, early_root_p1, early_root_p2, early_root_p3;
    reg [6:0] early_root_s0, early_root_s1, early_root_s2, early_root_s3;
    reg [27:0] early_root_flat;
    reg early_pool_held;
    reg [6:0] early_pool_value;
    reg [6:0] early_pred_candidates [0:3];
    integer er_i, er_j;
    wire [6:0] early_root_j = in_window_flat[0 +: `GP_J_W];
    wire [2:0] early_root_next_count = early_root_count + {2'd0,!early_root_has_endpoint};
    wire early_root_single = ROOT_FORCED && !early_root_duplicate &&
                             !early_root_extra &&
                             (early_root_count <= ROOT_CAPACITY) &&
                             (early_root_next_count <= ROOT_CAPACITY);
    always @* begin
        early_root_count = 3'd0;
        early_root_has_endpoint = 1'b0;
        early_root_duplicate = 1'b0;
        for (er_i=0; er_i<4; er_i=er_i+1) begin
            early_root_values[er_i] = 7'h7f;
            early_pred_candidates[er_i] =
                (in_slot_valid[er_i] && in_slot_j_flat[7*er_i +: 7] <= early_root_j) ?
                in_slot_j_flat[7*er_i +: 7] : 7'd0;
            if (in_slot_valid[er_i]) begin
                early_root_values[early_root_count[1:0]] = in_slot_j_flat[7*er_i +: 7];
                early_root_count = early_root_count + 1'b1;
                if (in_slot_j_flat[7*er_i +: 7] == early_root_j)
                    early_root_has_endpoint = 1'b1;
                for (er_j=0; er_j<er_i; er_j=er_j+1)
                    if (in_slot_valid[er_j] &&
                        in_slot_j_flat[7*er_i +: 7] == in_slot_j_flat[7*er_j +: 7])
                        early_root_duplicate = 1'b1;
            end
        end
        early_root_pair0 = early_pred_candidates[0] > early_pred_candidates[1] ?
                           early_pred_candidates[0] : early_pred_candidates[1];
        early_root_pair1 = early_pred_candidates[2] > early_pred_candidates[3] ?
                           early_pred_candidates[2] : early_pred_candidates[3];
        early_root_pred = early_root_pair0 > early_root_pair1 ? early_root_pair0 : early_root_pair1;
        early_root_extra = 1'b0;
        early_pool_held = 1'b0;
        early_pool_value = 7'd0;
        for (er_i=1; er_i<WINDOW_LEN; er_i=er_i+1) begin
            early_pool_value = in_window_flat[7*er_i +: 7];
            early_pool_held = 1'b0;
            for (er_j=0; er_j<4; er_j=er_j+1)
                if (in_slot_valid[er_j] && in_slot_j_flat[7*er_j +: 7] == early_pool_value)
                    early_pool_held = 1'b1;
            if (!early_pool_held && early_pool_value > early_root_pred && early_pool_value < early_root_j)
                early_root_extra = 1'b1;
        end
        if (!early_root_has_endpoint && early_root_count < 4)
            early_root_values[early_root_count[1:0]] = early_root_j;
        if (early_root_values[0] <= early_root_values[1]) begin
            early_root_p0=early_root_values[0]; early_root_p1=early_root_values[1];
        end else begin early_root_p0=early_root_values[1]; early_root_p1=early_root_values[0]; end
        if (early_root_values[2] <= early_root_values[3]) begin
            early_root_p2=early_root_values[2]; early_root_p3=early_root_values[3];
        end else begin early_root_p2=early_root_values[3]; early_root_p3=early_root_values[2]; end
        if (early_root_p0 <= early_root_p2) begin early_root_s0=early_root_p0; early_root_s2=early_root_p2; end
        else begin early_root_s0=early_root_p2; early_root_s2=early_root_p0; end
        if (early_root_p1 <= early_root_p3) begin early_root_s1=early_root_p1; early_root_s3=early_root_p3; end
        else begin early_root_s1=early_root_p3; early_root_s3=early_root_p1; end
    end
    // Keep packing separate from the count/endpoint computation. Otherwise
    // treating the entire always block as one node creates a false feedback
    // dependency through the derived early_root_next_count in Verilator.
    always @* begin
        early_root_flat = 28'd0;
        if (early_root_next_count > 0) early_root_flat[0 +: 7] = early_root_s0;
        if (early_root_next_count > 1) early_root_flat[7 +: 7] = early_root_s1 <= early_root_s2 ? early_root_s1 : early_root_s2;
        if (early_root_next_count > 2) early_root_flat[14 +: 7] = early_root_s1 <= early_root_s2 ? early_root_s2 : early_root_s1;
        if (early_root_next_count > 3) early_root_flat[21 +: 7] = early_root_s3;
    end

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
    reg [6:0] f_val0    [0:8];
    reg [6:0] f_val1    [0:8];
    reg [6:0] f_val2    [0:8];
    reg [6:0] f_val3    [0:8];

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
    reg [3:0] f_pipe_r0 [0:8];
    reg [3:0] f_pipe_r1 [0:8];
    reg [3:0] f_pipe_r2 [0:8];
    reg [3:0] f_pipe_r3 [0:8];

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

    // PREP consumes a hot mirror of the current architectural frame. The
    // mirror is updated at root entry, descent and return, so PREP does not
    // place the 9-frame sp-indexed array mux in front of its combinational
    // predecessor/filter logic.
    reg [3:0] a_req_idx;
    reg [2:0] a_count;
    reg [3:0] a_id0, a_id1, a_id2, a_id3;
    reg [6:0] a_val0, a_val1, a_val2, a_val3;
    wire [3:0] prep_req_idx = a_req_idx;
    wire [2:0] prep_count = a_count;
    wire [3:0] prep_id0 = a_id0;
    wire [3:0] prep_id1 = a_id1;
    wire [3:0] prep_id2 = a_id2;
    wire [3:0] prep_id3 = a_id3;

    reg [6:0] prep_j;
    reg [3:0] prep_jid;
    reg [6:0] prep_pred;
    reg [6:0] prep_imm;
    reg [2:0] prep_keep_count;
    reg [15:0] prep_keep_ids;

    // Active checkpoint values are kept in ascending value order.  PREP can
    // therefore choose the highest value not above j with one qualification
    // layer and a priority mux instead of a three-comparator max tree.
    reg [6:0] prep_val0, prep_val1, prep_val2, prep_val3;

    // Root checkpoints arrive in slot/ID order, so sort their values once when
    // the root hot mirror is installed.  Descendants already carry sorted
    // value ranks in a_pipe_r*.
    reg [6:0] root_raw_v0, root_raw_v1, root_raw_v2, root_raw_v3;
    reg [6:0] root_sv10, root_sv11, root_sv12, root_sv13;
    reg [6:0] root_sv20, root_sv21, root_sv22, root_sv23;
    reg [6:0] root_sort_v0, root_sort_v1, root_sort_v2, root_sort_v3;
    always @* begin
        root_raw_v0 = (root_init_count > 0) ? univ_val[root_init_id0] : 7'h7F;
        root_raw_v1 = (root_init_count > 1) ? univ_val[root_init_id1] : 7'h7F;
        root_raw_v2 = (root_init_count > 2) ? univ_val[root_init_id2] : 7'h7F;
        root_raw_v3 = (root_init_count > 3) ? univ_val[root_init_id3] : 7'h7F;
        if (root_raw_v0 <= root_raw_v1) begin root_sv10=root_raw_v0; root_sv11=root_raw_v1; end
        else begin root_sv10=root_raw_v1; root_sv11=root_raw_v0; end
        if (root_raw_v2 <= root_raw_v3) begin root_sv12=root_raw_v2; root_sv13=root_raw_v3; end
        else begin root_sv12=root_raw_v3; root_sv13=root_raw_v2; end
        if (root_sv10 <= root_sv12) begin root_sv20=root_sv10; root_sv22=root_sv12; end
        else begin root_sv20=root_sv12; root_sv22=root_sv10; end
        if (root_sv11 <= root_sv13) begin root_sv21=root_sv11; root_sv23=root_sv13; end
        else begin root_sv21=root_sv13; root_sv23=root_sv11; end
        root_sort_v0 = root_sv20;
        root_sort_v3 = root_sv23;
        if (root_sv21 <= root_sv22) begin root_sort_v1=root_sv21; root_sort_v2=root_sv22; end
        else begin root_sort_v1=root_sv22; root_sort_v2=root_sv21; end
    end

    reg [8:0] prep_elig_mask;
    reg [3:0] prep_extra_count;
    reg [35:0] prep_extra_ids;
    reg prep_pool_in_state;
    reg [3:0] prep_pid;
    integer pi;

    // Hot-path active-frame mirror.  The DFS arrays remain the architectural
    // recursion stack, but action generation never variable-indexes them.
    // This removes the sp->9-way-array mux from the one-action/cycle path.
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

    // EXACT_PRUNE=5 frame phase.  f_phase[] survives recursion like the other
    // f_* frame arrays; a_phase mirrors the active frame for the hot path.
    reg [1:0]  f_phase [0:8];
    reg [1:0]  a_phase;
    // Seed found by the SCAN of the active frame. A SCAN never descends, so
    // one running-minimum record suffices. Its selected generator position
    // is then saved per frame to avoid canonical replay after recursion.
    reg        scan_valid;
    reg [10:0] scan_total;
    reg [2:0]  scan_cnt;
    reg [15:0] scan_ids;
    reg [2:0]  scan_seg;
    // Cache positions identify complete canonical actions, including segment
    // count. Preserve the selected seed and resume position across recursion.
    reg [CACHE_INDEX_W:0] a_cache_count, a_cache_next, scan_seed_index;
    reg [CACHE_INDEX_W:0] a_seed_index, mresp_cache_next;
    reg [CACHE_INDEX_W:0] f_cache_count [0:8];
    reg [CACHE_INDEX_W:0] f_cache_next [0:8];
    reg [CACHE_INDEX_W:0] f_seed_index [0:8];
    // The global minimum relaxed cost belongs to the frame, not to the hot
    // SCAN accumulator: a recursive child overwrites that accumulator.  If
    // the selected seed attains this value, its exact optimum is certified.
    reg [10:0] a_seed_bound;
    reg [10:0] f_seed_bound [0:8];
    reg [10:0] return_cost;
    // scan_issued/scan_multi: the SCAN has issued one / more than one child.
    // A single-child frame needs no canonical walk after its seed.
    reg        scan_issued;
    reg        scan_multi;
    // Active pending-action mirror.  f_pipe_* remains the architectural copy
    // that survives recursion, but the evaluation datapath never variable-
    // indexes that 9-frame array.  On a memo miss return, ST_RETURN restores
    // this mirror and ST_RETURN_EVAL consumes it one cycle later.
    reg [2:0] a_pipe_child_count;
    reg [3:0] a_pipe_cid0, a_pipe_cid1, a_pipe_cid2, a_pipe_cid3;
    reg [6:0] a_pipe_imm;
    reg [6:0] a_pipe_pred;
    reg [6:0] a_pipe_j;
    reg [2:0] a_pipe_seg;
    reg [3:0] a_pipe_r0, a_pipe_r1, a_pipe_r2, a_pipe_r3;

    // EXACT_PRUNE=5 direct evaluation. When the child's remaining window is a
    // single request, the relaxed bound equals the exact child cost. mresp_*
    // aligns that metadata with the synchronous memo BRAM response.
    reg        mresp_direct;
    reg [9:0]  mresp_lb;

    reg        mresp_valid;
    reg [6:0]  a_pipe_next_j, a_pipe_next2_j;
    reg        a_pipe_has_next2;
    reg [1:0]  mresp_pre_dsize;
    reg [8:0]  mresp_pre_dmask;
    reg [2:0]  mresp_pre_rsize;
    reg [8:0]  mresp_pre_rmask;
    reg        mresp_pre_gen_valid;

    // PREP predecessor/keep logic reads the selected DFS frame directly.
    always @* begin
        // The current request is mirrored when entering/restoring a frame.
        // PREP therefore avoids the a_req_idx -> 9-way req array mux in front
        // of the predecessor max tree and immediate-cost subtractor.
        prep_jid = a_ctx_jid;
        prep_j   = a_ctx_j;

        // Read each checkpoint value once, qualify in parallel, then take max
        // with a balanced tree.  Invalid / above-request candidates become 0.
        prep_val0 = a_val0;
        prep_val1 = a_val1;
        prep_val2 = a_val2;
        prep_val3 = a_val3;

        if ((prep_count > 3) && (prep_val3 <= prep_j))
            prep_pred = prep_val3;
        else if ((prep_count > 2) && (prep_val2 <= prep_j))
            prep_pred = prep_val2;
        else if ((prep_count > 1) && (prep_val1 <= prep_j))
            prep_pred = prep_val1;
        else if ((prep_count > 0) && (prep_val0 <= prep_j))
            prep_pred = prep_val0;
        else
            prep_pred = 7'd0;

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

    // Exact two-request suffix. Only a non-root frame may use this shortcut:
    // its caller needs the optimal cost, not the chosen checkpoint tuple.
    // Every eligible old checkpoint can be retained by the zero-deposit
    // action, and every eligible intermediate can be selected by a one-deposit
    // action (K>=2). Thus each member of this union is attainable individually.
    // With only one subsequent request, the best attainable predecessor alone
    // determines the exact tail cost; enumerating checkpoint sets is redundant.
    wire prep_two_left = SEED_MODE && (ACTION_LIMIT==0) && (sp!=0) &&
                         (a_req_idx==H_FUTURE-1) && (CKPT_K>=2);
    wire [6:0] prep_next_j = req_val[a_req_idx+1'b1];
    wire [6:0] suffix_max [1:31] /* verilator split_var */;
    assign suffix_max[16] = (prep_j<=prep_next_j) ? prep_j : 7'd0;
    assign suffix_max[17] = (prep_count>0 && a_val0<=prep_next_j) ? a_val0 : 7'd0;
    assign suffix_max[18] = (prep_count>1 && a_val1<=prep_next_j) ? a_val1 : 7'd0;
    assign suffix_max[19] = (prep_count>2 && a_val2<=prep_next_j) ? a_val2 : 7'd0;
    assign suffix_max[20] = (prep_count>3 && a_val3<=prep_next_j) ? a_val3 : 7'd0;
    genvar sx;
    generate
        for (sx=0; sx<9; sx=sx+1) begin : g_suffix_pool
            assign suffix_max[21+sx] = (prep_elig_mask[sx] && req_pool_val[sx]<=prep_next_j) ?
                                      req_pool_val[sx] : 7'd0;
        end
        for (sx=30; sx<32; sx=sx+1) begin : g_suffix_pad
            assign suffix_max[sx] = 7'd0;
        end
        for (sx=1; sx<16; sx=sx+1) begin : g_suffix_max
            assign suffix_max[sx] = (suffix_max[2*sx]>=suffix_max[2*sx+1]) ?
                                    suffix_max[2*sx] : suffix_max[2*sx+1];
        end
    endgenerate
    wire [10:0] prep_suffix_cost = {4'd0,prep_imm}+{4'd0,prep_next_j}-{4'd0,suffix_max[1]};

    // -------------------------------------------------------------------------
    // Current legal action from the active-frame mirror.
    //
    // The active masks are compacted and canonically sorted in the issue cycle.
    // The resulting combinadic address drives the synchronous memo directly.
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

    // A root has exactly one restricted-B action when there are no optional
    // deposits and every old checkpoint other than the endpoint fits beside
    // that mandatory endpoint. No SCAN, bound, or memo lookup can change this
    // choice. Test the installed active context, avoiding a second PREP cone.
    wire root_single_action = ROOT_FORCED && (sp == 0) && a_gen_valid &&
                              (a_ctx_extra_count == 0) &&
                              (a_ctx_keep_count <= (CKPT_K-1));
    wire root_single_new_endpoint = (a_count == a_ctx_keep_count);
    wire [2:0] root_single_count = a_count + root_single_new_endpoint;
    reg [6:0] root_single_v0, root_single_v1, root_single_v2, root_single_v3;
    always @* begin
        // a_val* is already sorted. For the forced action retain all old
        // checkpoints and insert the endpoint if it is not present yet.
        root_single_v0 = a_val0; root_single_v1 = a_val1;
        root_single_v2 = a_val2; root_single_v3 = a_val3;
        if (root_single_new_endpoint) begin
            if ((a_count == 0) || (a_ctx_j < a_val0)) begin
                root_single_v0 = a_ctx_j; root_single_v1 = a_val0;
                root_single_v2 = a_val1; root_single_v3 = a_val2;
            end else if ((a_count == 1) || (a_ctx_j < a_val1)) begin
                root_single_v1 = a_ctx_j;
                root_single_v2 = a_val1; root_single_v3 = a_val2;
            end else if ((a_count == 2) || (a_ctx_j < a_val2)) begin
                root_single_v2 = a_ctx_j; root_single_v3 = a_val2;
            end else begin
                root_single_v3 = a_ctx_j;
            end
        end
    end

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
        action_child_count = action_raw_child_count;
        sort_raw0 = action_raw0; sort_raw1 = action_raw1;
        sort_raw2 = action_raw2; sort_raw3 = action_raw3;
        action_imm_cost = a_ctx_imm;

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

    // Combinational pending-child value lookup for the legacy short bounds.
    // The former E0/E1/E2 timing-only evaluation pipeline was removed. Root
    // tie-breaks use sorted ranks carried with the synchronous memo response;
    // non-root frames compare cost only.
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

    // Early bound from the current action. Modes 3/4 prune before issuing a
    // memo read; modes 1/2 keep the legacy late-miss behavior.
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
        early_v0 = (action_raw_child_count > 0) ? univ_val[action_raw0] : 7'h7F;
        early_v1 = (action_raw_child_count > 1) ? univ_val[action_raw1] : 7'h7F;
        early_v2 = (action_raw_child_count > 2) ? univ_val[action_raw2] : 7'h7F;
        early_v3 = (action_raw_child_count > 3) ? univ_val[action_raw3] : 7'h7F;
        early_next_j = req_val[{1'b0,a_req_idx[2:0]} + 4'd1];
        early_has_next2 = (({1'b0,a_req_idx[2:0]} + 4'd2) <= H_FUTURE);
        if (early_has_next2)
            early_next2_j = req_val[{1'b0,a_req_idx[2:0]} + 4'd2];
        else
            early_next2_j = 7'd0;

        if ((action_raw_child_count > 0) && (early_v0 <= early_next_j))
            early_cand0 = early_v0;
        else
            early_cand0 = 7'd0;
        if ((action_raw_child_count > 1) && (early_v1 <= early_next_j))
            early_cand1 = early_v1;
        else
            early_cand1 = 7'd0;
        if ((action_raw_child_count > 2) && (early_v2 <= early_next_j))
            early_cand2 = early_v2;
        else
            early_cand2 = 7'd0;
        if ((action_raw_child_count > 3) && (early_v3 <= early_next_j))
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
        early_total_lb = {4'd0,a_ctx_imm} + {4'd0,early_tail_lb};

        if ((action_raw_child_count > 0) && (early_v0 <= early_next2_j))
            early2_cand0 = early_v0;
        else early2_cand0 = 7'd0;
        if ((action_raw_child_count > 1) && (early_v1 <= early_next2_j))
            early2_cand1 = early_v1;
        else early2_cand1 = 7'd0;
        if ((action_raw_child_count > 2) && (early_v2 <= early_next2_j))
            early2_cand2 = early_v2;
        else early2_cand2 = 7'd0;
        if ((action_raw_child_count > 3) && (early_v3 <= early_next2_j))
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

    // Root lexicographic compare helper.  Inputs are sorted-value ranks, so
    // rank order is identical to the software tuple(value) order.
    function lex_less4;
        input [2:0] ac;
        input [3:0] a0,a1,a2,a3;
        input [2:0] bc;
        input [3:0] b0,b1,b2,b3;
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
    // Convert canonical ID tuples to sorted-value ranks for root tie-breaks.
    // ID order is insertion order and must never substitute for value order.
    function [15:0] tuple_value_ranks;
        input [2:0] count;
        input [15:0] ids;
        input [4*UB-1:0] positions;
        reg [3:0] v0,v1,v2,v3,t;
        begin
            v0=(count>0) ? positions[4*ids[3:0] +: 4] : 4'hf;
            v1=(count>1) ? positions[4*ids[7:4] +: 4] : 4'hf;
            v2=(count>2) ? positions[4*ids[11:8] +: 4] : 4'hf;
            v3=(count>3) ? positions[4*ids[15:12] +: 4] : 4'hf;
            if (v0>v1) begin t=v0; v0=v1; v1=t; end
            if (v2>v3) begin t=v2; v2=v3; v3=t; end
            if (v0>v2) begin t=v0; v0=v2; v2=t; end
            if (v1>v3) begin t=v1; v1=v3; v3=t; end
            if (v1>v2) begin t=v1; v1=v2; v2=t; end
            tuple_value_ranks={v3,v2,v1,v0};
        end
    endfunction

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

    reg root_best_valid;
    reg [10:0] root_best_cost;
    reg [2:0] root_best_seg;
    reg [2:0] root_best_count;
    reg [3:0] root_best_r0,root_best_r1,root_best_r2,root_best_r3;

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
    wire legacy_pruned = ((EXACT_PRUNE == 3) || (EXACT_PRUNE == 4)) &&
                         (((sp != 0) && f_best_valid[sp] &&
                           (early_active_lb >= f_best_cost[sp])) ||
                          ((sp == 0) && root_best_valid &&
                           (early_active_lb > root_best_cost)));
    wire legacy_memo_issue = !SEED_MODE && can_issue_memo_action && !legacy_pruned;
    wire [13:0] legacy_memo_addr = memo_addr_of(a_req_idx[2:0],
        rank_state(action_child_count,action_id0,action_id1,action_id2,action_id3));
    wire memo_rd_en = SEED_MODE ? seed_memo_issue : legacy_memo_issue;
    wire [13:0] memo_rd_addr = SEED_MODE ? seed_memo_addr : legacy_memo_addr;
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
    // grover_ckpt_gap_bound computes this same relaxed cost independently for
    // each initial-checkpoint gap. The full remaining request set is a rank
    // mask; its order and repetitions do not affect the relaxed cost. Two
    // data stages plus the output register replace the former H-stage walk.
    // Packets still belong to one active frame and are flushed on memo miss
    // or whenever the FSM leaves ST_RUN.
    // -------------------------------------------------------------------------

    // Per-solve tables.  They depend only on BUILD results, are free-running
    // registers, and settle two cycles after the last BUILD commit, i.e.
    // before the root frame reaches ST_RUN.
    reg [3:0]    rk_req [0:8];
    reg [UB-1:0] future_ranks [0:8];
    reg [UB-1:0] future_ranks_c [0:8];
    integer rt_i, rt_j;

    always @* begin
        for (rt_i=0; rt_i<9; rt_i=rt_i+1) begin
            future_ranks_c[rt_i] = {UB{1'b0}};
            for (rt_j=0; rt_j<9; rt_j=rt_j+1)
                if ((rt_j > rt_i) && (rt_j < WINDOW_LEN))
                    future_ranks_c[rt_i] = future_ranks_c[rt_i] | rank_onehot(rk_req[rt_j]);
        end
    end

    always @(posedge clk) begin
        for (rt_i=0; rt_i<9; rt_i=rt_i+1) begin
            rk_req[rt_i] <= rk_pos[req_id[rt_i]];
            future_ranks[rt_i] <= future_ranks_c[rt_i];
        end
    end

    localparam integer SCAN_WIDTH=(ACTION_LIMIT==0 && SEED_MODE) ? SCAN_LANES : 1;
    // A small prefix network advances independent lane iterators. It preserves
    // the frozen numeric-mask action order, including deposit-size boundaries.
    // No loop-dependent RTL register is shared between candidate datapaths.
    function [23:0] scan_successor;
        input [23:0] state;
        input [3:0] nextra;
        input [2:0] nkeep;
        reg valid;
        reg [1:0] ds;
        reg [2:0] rs;
        reg [8:0] dm,rm;
        begin
            {valid,rm,rs,dm,ds}=state;
            if (valid) begin
                if (comb_has_next9(rm,nkeep,rs)) rm=next_comb9(rm,nkeep,rs);
                else if (comb_has_next9(dm,nextra,{1'b0,ds})) begin
                    dm=next_comb9(dm,nextra,{1'b0,ds}); rm=first_comb9(rs);
                end else if (ds<CKPT_K-1 && ds+1'b1<=nextra) begin
                    ds=ds+1'b1;
                    rs=(nkeep<CKPT_K-1-ds) ? nkeep : CKPT_K-1-ds;
                    dm=first_comb9({1'b0,ds}); rm=first_comb9(rs);
                end else valid=1'b0;
            end
            scan_successor={valid,rm,rs,dm,ds};
        end
    endfunction
    wire [23:0] scan_iterator [0:SCAN_WIDTH] /* verilator split_var */;
    wire [4*UB-1:0] scan_rank_positions;
    wire [7*UB-1:0] bound_values;
    wire [SCAN_WIDTH-1:0] scan_issue_mask;
    reg [SCAN_WIDTH-1:0] scan_valid0,scan_valid1,scan_valid2;
    wire [SCAN_WIDTH-1:0] bo_mask=scan_valid2;
    wire [1:0] bp_v={|scan_valid1,|scan_valid0};
    wire bo_v=|bo_mask;
    wire bo_kind=1'b1;
    wire bp_flush=(fsm_state!=ST_RUN) || (mresp_valid && !memo_pipe_hit);
    wire bound_capture=busy && fsm_state==ST_RUN && !top_terminal &&
                       a_gen_valid && !root_single_action && a_phase==PH_SCAN;
    wire bp_busy=bo_v || |bp_v;
    wire [32*SCAN_WIDTH-1:0] scan_packets;
    genvar sl;
    generate
        for (sl=0; sl<UB; sl=sl+1) begin : g_scan_positions
            assign scan_rank_positions[4*sl +: 4]=rk_pos[sl];
            assign bound_values[7*sl +: 7]=rk_sval[sl];
        end
        for (sl=0; sl<SCAN_WIDTH; sl=sl+1) begin : g_scan_lane
            wire [23:0] iterator_state,next_iterator;
            if (sl==0) begin : g_first
                assign iterator_state={a_gen_valid,a_rmask,a_rsize,a_dmask,a_dsize};
            end else begin : g_later
                assign iterator_state=g_scan_lane[sl-1].next_iterator;
            end
            assign next_iterator=scan_successor(iterator_state,a_ctx_extra_count,a_ctx_keep_count);
            assign scan_iterator[sl]=iterator_state;
            if (sl==SCAN_WIDTH-1) begin : g_last
                assign scan_iterator[SCAN_WIDTH]=next_iterator;
            end
            assign scan_issue_mask[sl]=bound_capture && iterator_state[23];
            grover_policy_scan_bound #(.UB(UB)) u_lane (
                .clk(clk),.endpoint(a_ctx_jid),.extras(a_ctx_extra_ids),.retained(a_ctx_keep_ids),
                .iterator_state(iterator_state),.positions(scan_rank_positions),
                .values(bound_values),.future_mask(future_ranks[a_req_idx]),
                .packet(scan_packets[32*sl +: 32])
            );
        end
    endgenerate
    always @(posedge clk) begin
        if (!rstn || bp_flush || !SEED_MODE) begin
            scan_valid0<=0; scan_valid1<=0; scan_valid2<=0;
        end else begin
            scan_valid0<=scan_issue_mask;
            scan_valid1<=scan_valid0;
            scan_valid2<=scan_valid1;
        end
    end
    // Balanced lane reduction. The optimistic root key includes segment count
    // and tuple values; equal keys retain the first canonical candidate index.
    function [34:0] scan_minimum;
        input [34:0] left,right;
        input root;
        input [4*UB-1:0] positions;
        reg [31:0] a,b;
        reg [15:0] ar,br;
        reg take_right;
        begin
            a=left[31:0]; b=right[31:0];
            ar=tuple_value_ranks(a[31:29],a[28:13],positions);
            br=tuple_value_ranks(b[31:29],b[28:13],positions);
            take_right=!left[34] || (right[34] &&
                ((b[10:0]<a[10:0]) || (root && b[10:0]==a[10:0] &&
                 ((b[12:11]<a[12:11]) || (b[12:11]==a[12:11] &&
                  lex_less4(b[31:29],br[3:0],br[7:4],br[11:8],br[15:12],
                            a[31:29],ar[3:0],ar[7:4],ar[11:8],ar[15:12]))))));
            scan_minimum=take_right ? right : left;
        end
    endfunction
    wire [34:0] scan_min_tree [1:2*SCAN_WIDTH-1] /* verilator split_var */;
    generate
        for (sl=0; sl<SCAN_WIDTH; sl=sl+1) begin : g_scan_min_leaf
            assign scan_min_tree[SCAN_WIDTH+sl]={bo_mask[sl],sl[1:0],scan_packets[32*sl +: 32]};
        end
        for (sl=1; sl<SCAN_WIDTH; sl=sl+1) begin : g_scan_min_node
            assign scan_min_tree[sl]=scan_minimum(scan_min_tree[2*sl],scan_min_tree[2*sl+1],sp==0,scan_rank_positions);
        end
    endgenerate
    wire [1:0] bo_selected_lane=scan_min_tree[1][33:32];
    wire [31:0] bo_packet=scan_min_tree[1][31:0];
    wire [2:0] bo_cnt=bo_packet[31:29];
    wire [15:0] bo_ids=bo_packet[28:13];
    wire [23:0] bo_pre={22'd0,bo_packet[12:11]};
    wire [10:0] bo_tail=bo_packet[10:0];
    wire [10:0] bo_total=bo_tail+{4'd0,a_ctx_imm};
    reg [2:0] scan_output_count,scan_input_count;
    integer sc;
    always @* begin
        scan_output_count=0; scan_input_count=0;
        for (sc=0; sc<SCAN_WIDTH; sc=sc+1) begin
            scan_output_count=scan_output_count+bo_mask[sc];
            scan_input_count=scan_input_count+scan_issue_mask[sc];
        end
    end
    wire scan_last=bo_v && !a_gen_valid && !(|bp_v);
    wire [15:0] scan_packet_ranks=tuple_value_ranks(bo_cnt,bo_ids,scan_rank_positions);
    wire [15:0] scan_best_ranks=tuple_value_ranks(scan_cnt,scan_ids,scan_rank_positions);
    wire [2:0] scan_packet_seg={1'b0,bo_pre[1:0]}+1'b1;
    wire scan_take=!scan_valid || bo_total<scan_total ||
        ((sp==0) && bo_total==scan_total &&
         ((scan_packet_seg<scan_seg) ||
          (scan_packet_seg==scan_seg && lex_less4(bo_cnt,
            scan_packet_ranks[3:0],scan_packet_ranks[7:4],scan_packet_ranks[11:8],scan_packet_ranks[15:12],
            scan_cnt,scan_best_ranks[3:0],scan_best_ranks[7:4],scan_best_ranks[11:8],scan_best_ranks[15:12]))));
    wire [10:0] scan_fin_total=scan_take ? bo_total : scan_total;
    wire [2:0] scan_fin_cnt=scan_take ? bo_cnt : scan_cnt;
    wire [15:0] scan_fin_ids=scan_take ? bo_ids : scan_ids;
    wire [CACHE_INDEX_W:0] scan_fin_index=scan_take ? a_cache_count+bo_selected_lane : scan_seed_index;
    wire [2:0] scan_fin_seg=scan_take ? scan_packet_seg : scan_seg;
    wire scan_exact_finish=(sp!=0) && ({1'b0,a_req_idx}==H_FUTURE-1);
    wire seed_issue_from_scan=scan_last && !scan_exact_finish;
    // SCAN stores the same canonical packet the bound has just produced.
    // The bounded per-frame count replaces epoch tags/clears for this store:
    // every entry below that count was written by this frame's current SCAN.
    wire cache_write_en = SEED_MODE && busy && (fsm_state == ST_RUN) &&
                          (a_phase == PH_SCAN) && bo_v && bo_kind && !bp_flush;
    reg [CANON_LANES-1:0] cache_wr_enable;
    reg [32*CANON_LANES-1:0] cache_wr_packets;
    integer cw, bank_index;
    always @* begin
        cache_wr_enable=0; cache_wr_packets=0; bank_index=0;
        // SCAN_WIDTH divides CANON_LANES, so an aligned SCAN batch cannot
        // cross a bank-group boundary. The final partial batch ends the SCAN.
        for (cw=0; cw<SCAN_WIDTH; cw=cw+1) begin
            bank_index=(a_cache_count+cw) % CANON_LANES;
            cache_wr_enable[bank_index]=cache_write_en && bo_mask[cw];
            cache_wr_packets[32*bank_index +: 32]=scan_packets[32*cw +: 32];
        end
    end
    wire [CACHE_ADDR_W-1:0] cache_wr_addr =
        {sp[CACHE_FRAME_W-1:0],a_cache_count[CACHE_INDEX_W-1:CACHE_LANE_BITS]};
    wire [32*CANON_LANES-1:0] cache_rd_data;
    reg cache_group_valid;
    reg [CACHE_INDEX_W:0] cache_group_base;
    wire cache_walk_fire = SEED_MODE && busy && (fsm_state == ST_RUN) &&
                           (a_phase == PH_CANON) && cache_group_valid &&
                           (a_cache_next < a_cache_count) &&
                           (!mresp_valid || memo_pipe_hit);
    reg cache_choice_valid;
    reg [31:0] cache_choice;
    reg [CACHE_INDEX_W:0] cache_walk_next;
    reg [CANON_LANES-1:0] cache_prune_mask, cache_seed_mask;
    reg [2:0] cache_pruned_count;
    reg [31:0] cache_lane_data;
    reg [CACHE_INDEX_W:0] cache_lane_index;
    reg [10:0] cache_lane_total;
    integer cl;

    wire seed_hit_optimal = (ACTION_LIMIT==0) &&
        (({4'd0,a_pipe_imm}+memo_child_cost)==a_seed_bound);
    wire seed_return_optimal = (ACTION_LIMIT==0) &&
        (({4'd0,a_pipe_imm}+return_cost)==a_seed_bound);
    wire cache_seed_prefetch = (fsm_state==ST_RUN) && (a_phase==PH_SEED) &&
        mresp_valid && memo_pipe_hit && !seed_hit_optimal && a_cache_count>1;
    wire cache_return_prefetch = (fsm_state==ST_RETURN_EVAL) &&
        (((a_phase==PH_SEED) && !seed_return_optimal && a_cache_count>1) ||
         ((a_phase==PH_CANON) && a_cache_next<a_cache_count));
    wire cache_group_cross = (cache_walk_next >> CACHE_LANE_BITS)!=
                             (cache_group_base >> CACHE_LANE_BITS);
    wire cache_next_prefetch = cache_walk_fire && cache_group_cross &&
                               cache_walk_next<a_cache_count;
    wire [CACHE_INDEX_W:0] cache_read_index =
        (cache_seed_prefetch || (cache_return_prefetch && a_phase==PH_SEED)) ? 0 :
        cache_next_prefetch ? cache_walk_next : a_cache_next;
    wire cache_read_en = SEED_MODE && busy &&
        (cache_seed_prefetch || cache_return_prefetch ||
         ((fsm_state==ST_RUN) && (a_phase==PH_CANON) && !bp_flush &&
          ((!cache_group_valid && a_cache_next<a_cache_count) || cache_next_prefetch)));
    wire [CACHE_ADDR_W-1:0] cache_rd_addr =
        {sp[CACHE_FRAME_W-1:0],cache_read_index[CACHE_INDEX_W-1:CACHE_LANE_BITS]};

    grover_policy_action_cache #(.LANES(CANON_LANES),.ADDR_W(CACHE_ADDR_W),.DEPTH(CACHE_DEPTH)) u_action_cache (
        .clk(clk), .wr_en(cache_wr_enable), .wr_addr(cache_wr_addr),
        .wr_data(cache_wr_packets),
        .rd_en(cache_read_en), .rd_addr(cache_rd_addr), .rd_data(cache_rd_data)
    );

    // Compare independent bounds in parallel and select the earliest survivor.
    // Equality is kept at the root for segment/tuple tie-breaks. Only entries
    // before the survivor are consumed; later entries remain for the next edge.
    always @* begin
        cache_choice_valid=1'b0; cache_choice=32'd0;
        cache_walk_next=a_cache_next;
        cache_prune_mask={CANON_LANES{1'b0}};
        cache_seed_mask={CANON_LANES{1'b0}};
        cache_pruned_count=3'd0;
        cache_lane_data=32'd0; cache_lane_index=0; cache_lane_total=0;
        for (cl=0; cl<CANON_LANES; cl=cl+1) begin
            cache_lane_data=cache_rd_data[32*cl +: 32];
            cache_lane_index=cache_group_base+cl[CACHE_INDEX_W:0];
            cache_lane_total=cache_lane_data[10:0]+{4'd0,a_ctx_imm};
            if (cache_walk_fire && !cache_choice_valid &&
                cache_lane_index>=a_cache_next && cache_lane_index<a_cache_count) begin
                if (cache_lane_index==a_seed_index) begin
                    cache_seed_mask[cl]=1'b1;
                end else if (((sp!=0) && f_best_valid[sp] && cache_lane_total>=f_best_cost[sp]) ||
                             ((sp==0) && root_best_valid && cache_lane_total>root_best_cost)) begin
                    cache_prune_mask[cl]=1'b1;
                    cache_pruned_count=cache_pruned_count+1'b1;
                end else begin
                    cache_choice_valid=1'b1;
                    cache_choice=cache_lane_data;
                end
                cache_walk_next=cache_lane_index+1'b1;
                // Nonzero action budgets retain one-action accounting per
                // clock, including seed skips, just like the serial engine.
                if (ACTION_LIMIT!=0) cache_choice_valid=1'b1;
            end
        end
    end
    // With a work limit, a pruned/seed-only step must not issue a memo read.
    wire cache_has_survivor = cache_choice_valid && (cache_choice[31:29]!=0);
    wire canonical_seed_repeat = |cache_seed_mask;
    always @(posedge clk) begin
        if (!rstn) begin
            cache_group_valid<=1'b0;
            cache_group_base<=0;
        end else if (cache_read_en) begin
            cache_group_valid<=1'b1;
            cache_group_base<=(cache_read_index >> CACHE_LANE_BITS) << CACHE_LANE_BITS;
        end else if (fsm_state!=ST_RUN || a_phase!=PH_CANON || bp_flush) begin
            cache_group_valid<=1'b0;
            cache_group_base<=0;
        end else if (cache_walk_fire &&
                     ((cache_walk_next>=a_cache_count) ||
                      ((cache_walk_next >> CACHE_LANE_BITS)!=(cache_group_base >> CACHE_LANE_BITS)))) begin
            cache_group_valid<=1'b0;
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk) if (cache_write_en && a_cache_count+scan_output_count>CACHE_LIMIT_COUNT)
        $fatal(1,"policy SCAN cache capacity exceeded: %0d",a_cache_count);
`endif

    // Replay goes straight to the synchronous memo port: no repeated bound
    // pipeline, tuple compaction, or generator walk is needed in PH_CANON.
    wire seed_issue_from_bound = cache_walk_fire && cache_has_survivor;
    assign seed_memo_issue = SEED_MODE &&
                             (seed_issue_from_scan || seed_issue_from_bound);
    wire [2:0] seed_issue_count = seed_issue_from_scan ? scan_fin_cnt : cache_choice[31:29];
    wire [15:0] seed_issue_ids = seed_issue_from_scan ? scan_fin_ids : cache_choice[28:13];
    wire [2:0] seed_issue_seg = seed_issue_from_scan ? scan_fin_seg :
        ({1'b0,cache_choice[12:11]} + 1'b1);
    assign seed_memo_addr = memo_addr_of(a_req_idx[2:0],
        rank_state(seed_issue_count, seed_issue_ids[3:0], seed_issue_ids[7:4],
                   seed_issue_ids[11:8], seed_issue_ids[15:12]));

    // Root tie-break metadata is computed once when the synchronous memo read
    // is issued and rides the existing response-alignment record.  Comparing
    // four-bit sorted-value ranks at response time avoids the old
    // child-ID -> universe-value mux -> 7-bit sort -> root CE critical path.
    wire [2:0] issue_child_count = SEED_MODE ? seed_issue_count : action_child_count;
    wire [15:0] issue_child_ids = SEED_MODE ? seed_issue_ids :
        {action_id3, action_id2, action_id1, action_id0};
    reg [3:0] issue_rank0, issue_rank1, issue_rank2, issue_rank3;
    reg [3:0] ir10, ir11, ir12, ir13, ir20, ir21, ir22, ir23;
    always @* begin
        issue_rank0 = (issue_child_count > 0) ? rk_pos[issue_child_ids[3:0]] : 4'hF;
        issue_rank1 = (issue_child_count > 1) ? rk_pos[issue_child_ids[7:4]] : 4'hF;
        issue_rank2 = (issue_child_count > 2) ? rk_pos[issue_child_ids[11:8]] : 4'hF;
        issue_rank3 = (issue_child_count > 3) ? rk_pos[issue_child_ids[15:12]] : 4'hF;
        if (issue_rank0 <= issue_rank1) begin ir10=issue_rank0; ir11=issue_rank1; end
        else begin ir10=issue_rank1; ir11=issue_rank0; end
        if (issue_rank2 <= issue_rank3) begin ir12=issue_rank2; ir13=issue_rank3; end
        else begin ir12=issue_rank3; ir13=issue_rank2; end
        if (ir10 <= ir12) begin ir20=ir10; ir22=ir12; end
        else begin ir20=ir12; ir22=ir10; end
        if (ir11 <= ir13) begin ir21=ir11; ir23=ir13; end
        else begin ir21=ir13; ir23=ir11; end
        issue_rank0 = ir20;
        issue_rank3 = ir23;
        if (ir21 <= ir22) begin issue_rank1=ir21; issue_rank2=ir22; end
        else begin issue_rank1=ir22; issue_rank2=ir21; end
    end


    // -------------------------------------------------------------------------
    // Control / counters.
    // -------------------------------------------------------------------------
    reg [31:0] cyc_ctr;
    reg [31:0] act_ctr;
    reg [31:0] hit_ctr;
    reg [31:0] miss_ctr;
    reg [31:0] prune_ctr;
    reg [13:0] clear_ctr;
    reg memo_needs_clear;

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
    wire legacy_prune_commit = !SEED_MODE && can_issue_memo_action && legacy_pruned;

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
                     ((a_pipe_seg < root_best_seg) ||
                      ((a_pipe_seg == root_best_seg) &&
                       lex_less4(a_pipe_child_count,
                                 a_pipe_r0,a_pipe_r1,a_pipe_r2,a_pipe_r3,
                                 root_best_count,root_best_r0,root_best_r1,
                                 root_best_r2,root_best_r3))));
                if (root_better) begin
                    root_best_valid <= 1'b1;
                    root_best_cost <= fast_total;
                    root_best_seg <= a_pipe_seg;
                    root_best_count <= a_pipe_child_count;
                    root_best_r0 <= a_pipe_r0;
                    root_best_r1 <= a_pipe_r1;
                    root_best_r2 <= a_pipe_r2;
                    root_best_r3 <= a_pipe_r3;
                end
            end else begin
                if (!f_best_valid[sp] || (fast_total < f_best_cost[sp])) begin
                    f_best_valid[sp] <= 1'b1;
                    f_best_cost[sp] <= fast_total;
                end
            end
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
            a_req_idx<=4'd0; a_count<=3'd0;
            a_id0<=4'd0; a_id1<=4'd0; a_id2<=4'd0; a_id3<=4'd0;
            a_val0<=7'd0; a_val1<=7'd0; a_val2<=7'd0; a_val3<=7'd0;
            a_ctx_j<=7'd0; a_ctx_jid<=4'd0; a_ctx_pred<=7'd0; a_ctx_imm<=7'd0;
            a_ctx_extra_count<=4'd0; a_ctx_extra_ids<=36'd0; a_ctx_keep_count<=3'd0; a_ctx_keep_ids<=16'd0;
            a_dsize<=2'd0; a_dmask<=9'd0; a_rsize<=3'd0; a_rmask<=9'd0; a_gen_valid<=1'b0;
            a_phase<=PH_SCAN;
            scan_valid<=1'b0; scan_total<=INF_COST; scan_cnt<=3'd0; scan_ids<=16'd0; scan_seg<=3'd0;
            a_cache_count<=0; a_cache_next<=0; scan_seed_index<=0;
            a_seed_index<=0; mresp_cache_next<=0;
            a_seed_bound<=0;
            scan_issued<=1'b0; scan_multi<=1'b0;
            mresp_direct<=1'b0;
            mresp_lb<=10'd0;
            a_pipe_child_count<=3'd0; a_pipe_cid0<=4'd0; a_pipe_cid1<=4'd0; a_pipe_cid2<=4'd0; a_pipe_cid3<=4'd0;
            a_pipe_imm<=7'd0; a_pipe_pred<=7'd0; a_pipe_j<=7'd0;
            a_pipe_seg<=3'd0; a_pipe_r0<=4'd0; a_pipe_r1<=4'd0; a_pipe_r2<=4'd0; a_pipe_r3<=4'd0;
            a_pipe_next_j<=7'd0; a_pipe_next2_j<=7'd0; a_pipe_has_next2<=1'b0;
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
            root_best_r0<=4'd0; root_best_r1<=4'd0; root_best_r2<=4'd0; root_best_r3<=4'd0;
            for (si=0; si<9; si=si+1) begin
                req_id[si] <= 4'd0;
                req_val[si] <= 7'd0;
                req_pool_id[si] <= 4'd0;
                req_pool_val[si] <= 7'd0;
                f_req_idx[si] <= 4'd0;
                f_count[si] <= 3'd0;
                f_id0[si]<=4'd0; f_id1[si]<=4'd0; f_id2[si]<=4'd0; f_id3[si]<=4'd0;
                f_val0[si]<=7'd0; f_val1[si]<=7'd0; f_val2[si]<=7'd0; f_val3[si]<=7'd0;
                f_dsize[si]<=2'd0; f_dord[si]<=7'd0; f_rord[si]<=4'd0;
                f_dmask[si]<=9'd0; f_rmask[si]<=9'd0; f_rsize[si]<=3'd0; f_gen_valid[si]<=1'b0;
                f_best_valid[si]<=1'b0; f_best_cost[si]<=INF_COST;
                f_pipe_valid[si]<=1'b0;
                f_pipe_child_count[si]<=3'd0;
                f_pipe_cid0[si]<=4'd0; f_pipe_cid1[si]<=4'd0; f_pipe_cid2[si]<=4'd0; f_pipe_cid3[si]<=4'd0;
                f_pipe_imm[si]<=7'd0; f_pipe_seg[si]<=3'd0; f_pipe_pred[si]<=7'd0; f_pipe_j[si]<=7'd0;
                f_pipe_r0[si]<=4'd0; f_pipe_r1[si]<=4'd0; f_pipe_r2[si]<=4'd0; f_pipe_r3[si]<=4'd0;
                f_ctx_j[si]<=7'd0; f_ctx_jid[si]<=4'd0; f_ctx_pred[si]<=7'd0; f_ctx_imm[si]<=7'd0;
                f_ctx_extra_count[si]<=4'd0; f_ctx_extra_ids[si]<=36'd0;
                f_ctx_keep_count[si]<=3'd0; f_ctx_keep_ids[si]<=16'd0;
                f_phase[si]<=PH_SCAN;
                f_cache_count[si]<=0; f_cache_next[si]<=0; f_seed_index[si]<=0;
                f_seed_bound[si]<=0;
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

            if (cache_write_en) begin
                a_cache_count<=a_cache_count+scan_output_count;
                f_cache_count[sp]<=a_cache_count+scan_output_count;
                if (scan_take) scan_seed_index<=a_cache_count+bo_selected_lane;
            end

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
                        mresp_valid<=1'b0;
                        univ_count<=4'd0; req_pool_count<=4'd0; build_idx<=5'd0; root_init_count<=3'd0;
                        root_init_id0<=4'd0; root_init_id1<=4'd0; root_init_id2<=4'd0; root_init_id3<=4'd0;
                        root_best_valid<=1'b0; root_best_cost<=INF_COST; root_best_seg<=3'd0; root_best_count<=3'd0;
                        root_best_r0<=4'd0; root_best_r1<=4'd0; root_best_r2<=4'd0; root_best_r3<=4'd0;
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
                    if ((build_idx == 0) && early_root_single) begin
                        source_j <= early_root_pred;
                        next_count <= early_root_next_count;
                        next_j_flat <= early_root_flat;
                        root_cost <= {4'd0,early_root_j - early_root_pred};
                        root_segment_count <= 3'd1;
                        a_gen_valid <= 1'b0;
                        mresp_valid <= 1'b0;
                        busy <= 1'b0;
                        done <= 1'b1;
                        policy_cycles_last <= cyc_ctr + 1'b1;
                        policy_actions_last <= 32'd1;
                        policy_memo_hit_last <= 32'd0;
                        policy_memo_miss_last <= 32'd0;
                        policy_cycles_total <= policy_cycles_total + cyc_ctr + 1'b1;
                        policy_actions_total <= policy_actions_total + 1'b1;
                        if ((cyc_ctr + 1'b1) > policy_max_latency)
                            policy_max_latency <= cyc_ctr + 1'b1;
                        fsm_state <= ST_IDLE;
                    end else begin
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
                                    // Root result metadata uses sorted ranks in
                                    // every policy mode.  Keep this table warm
                                    // unconditionally; mode 5/6 additionally use
                                    // it for their full-horizon bound network.
                                    rk_pos[univ_count] <= build_newpos;
                                    for (si=0; si<13; si=si+1)
                                        if ((si < univ_count) && !build_lt[si])
                                            rk_pos[si] <= rk_pos[si] + 1'b1;
                                    for (si=1; si<13; si=si+1)
                                        if ((si > build_newpos) && (si <= univ_count))
                                            rk_sval[si] <= rk_sval[si-1];
                                    rk_sval[build_newpos] <= build_sel_value;
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
                end

                ST_ROOT_INIT: begin
                    // One settling cycle after the last universe insertion.
                    // Re-copy the root state/count because the final build-cycle
                    // nonblocking updates are now visible.
                    f_count[0] <= root_init_count;
                    f_id0[0] <= root_init_id0; f_id1[0] <= root_init_id1;
                    f_id2[0] <= root_init_id2; f_id3[0] <= root_init_id3;
                    a_req_idx <= 4'd0;
                    a_count <= root_init_count;
                    a_id0 <= root_init_id0; a_id1 <= root_init_id1;
                    a_id2 <= root_init_id2; a_id3 <= root_init_id3;
                    a_val0 <= root_sort_v0;
                    a_val1 <= root_sort_v1;
                    a_val2 <= root_sort_v2;
                    a_val3 <= root_sort_v3;
                    a_ctx_j <= req_val[0];
                    a_ctx_jid <= req_id[0];
                    f_val0[0] <= root_sort_v0;
                    f_val1[0] <= root_sort_v1;
                    f_val2[0] <= root_sort_v2;
                    f_val3[0] <= root_sort_v3;
                    // source_j is latched in ST_PREP, after the final root-state
                    // nonblocking updates from ST_ROOT_INIT are visible to prep_pred.
                    f_dsize[0]<=2'd0; f_dord[0]<=7'd0; f_rord[0]<=4'd0; f_gen_valid[0]<=1'b1;
                    f_pipe_valid[0]<=1'b0;
                    fsm_state <= ST_PREP;
                end

                ST_PREP: begin
                    mresp_valid <= 1'b0;
                    a_cache_count<=0; a_cache_next<=0; scan_seed_index<=0;
                    f_cache_count[sp]<=0; f_cache_next[sp]<=0;
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
                    scan_seg <= 3'd0;
                    scan_issued <= 1'b0;
                    scan_multi <= 1'b0;
                    fsm_state <= ST_RUN;
                    if (prep_two_left) begin
                        f_best_valid[sp]<=1'b1;
                        f_best_cost[sp]<=prep_suffix_cost;
                        act_ctr<=act_ctr+1'b1;
                        fsm_state<=ST_FINISH;
                    end
                end

                ST_RUN: begin
                    if ((ACTION_LIMIT != 0) &&
                        ((act_ctr + prune_ctr) >= ACTION_LIMIT)) begin
                        policy_error <= 1'b1;
                        mresp_valid <= 1'b0;
                        fsm_state <= ST_ABORT;
                    end else if (root_single_action) begin
                        // The plan is already unique. Return on this edge,
                        // without filling/draining the bound pipeline or
                        // issuing a synchronous memo request. The immediate
                        // cost is explicitly a lower bound in this mode.
                        next_count <= root_single_count;
                        next_j_flat <= 28'd0;
                        if (root_single_count > 0) next_j_flat[0*`GP_J_W +: `GP_J_W] <= root_single_v0;
                        if (root_single_count > 1) next_j_flat[1*`GP_J_W +: `GP_J_W] <= root_single_v1;
                        if (root_single_count > 2) next_j_flat[2*`GP_J_W +: `GP_J_W] <= root_single_v2;
                        if (root_single_count > 3) next_j_flat[3*`GP_J_W +: `GP_J_W] <= root_single_v3;
                        root_cost <= {4'd0,a_ctx_imm};
                        root_segment_count <= 3'd1;
                        a_gen_valid <= 1'b0;
                        mresp_valid <= 1'b0;
                        busy <= 1'b0;
                        done <= 1'b1;
                        policy_cycles_last <= cyc_ctr + 1'b1;
                        policy_actions_last <= act_ctr + prune_ctr + 1'b1;
                        policy_memo_hit_last <= hit_ctr;
                        policy_memo_miss_last <= miss_ctr;
                        policy_cycles_total <= policy_cycles_total + cyc_ctr + 1'b1;
                        policy_actions_total <= policy_actions_total + act_ctr + prune_ctr + 1'b1;
                        if ((cyc_ctr + 1'b1) > policy_max_latency)
                            policy_max_latency <= cyc_ctr + 1'b1;
                        fsm_state <= ST_IDLE;
                    end else if (top_terminal) begin
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
                            mresp_valid <= seed_memo_issue;
                            if (seed_memo_issue) begin
                                a_pipe_child_count <= seed_issue_count;
                                a_pipe_cid0 <= seed_issue_ids[3:0];
                                a_pipe_cid1 <= seed_issue_ids[7:4];
                                a_pipe_cid2 <= seed_issue_ids[11:8];
                                a_pipe_cid3 <= seed_issue_ids[15:12];
                                a_pipe_imm <= a_ctx_imm;
                                a_pipe_seg <= seed_issue_seg;
                                a_pipe_r0 <= issue_rank0; a_pipe_r1 <= issue_rank1;
                                a_pipe_r2 <= issue_rank2; a_pipe_r3 <= issue_rank3;
                                a_pipe_pred <= a_ctx_pred;
                                a_pipe_j <= a_ctx_j;
                                // Canonical replay resumes by cache index;
                                // generator masks no longer need restoring.
                                mresp_pre_dsize <= 2'd0;
                                mresp_pre_dmask <= 9'd0;
                                mresp_pre_rsize <= 3'd0;
                                mresp_pre_rmask <= 9'd0;
                                mresp_pre_gen_valid <= !seed_issue_from_scan;
                                mresp_cache_next <= seed_issue_from_scan ? 0 : cache_walk_next;
                                mresp_direct <= (seed_issue_from_scan && !scan_multi &&
                                                 ROOT_FORCED && (sp == 0)) ||
                                                ({1'b0,a_req_idx} == (H_FUTURE-1));
                                mresp_lb <= seed_issue_from_scan ?
                                    (scan_fin_total - {4'd0,a_ctx_imm}) : cache_choice[9:0];
                            end
                        end else begin
                            mresp_valid <= legacy_memo_issue;
                            if (legacy_memo_issue) begin
                                a_pipe_child_count <= action_child_count;
                                a_pipe_cid0 <= action_id0; a_pipe_cid1 <= action_id1;
                                a_pipe_cid2 <= action_id2; a_pipe_cid3 <= action_id3;
                                a_pipe_imm <= a_ctx_imm;
                                a_pipe_seg <= {1'b0,a_dsize} + 1'b1;
                                a_pipe_r0 <= issue_rank0; a_pipe_r1 <= issue_rank1;
                                a_pipe_r2 <= issue_rank2; a_pipe_r3 <= issue_rank3;
                                a_pipe_pred <= a_ctx_pred;
                                a_pipe_j <= a_ctx_j;
                                a_pipe_next_j <= early_next_j;
                                a_pipe_next2_j <= early_next2_j;
                                a_pipe_has_next2 <= early_has_next2;
                                mresp_pre_dsize <= a_dsize;
                                mresp_pre_dmask <= a_dmask;
                                mresp_pre_rsize <= a_rsize;
                                mresp_pre_rmask <= a_rmask;
                                mresp_pre_gen_valid <= a_gen_valid;
                                mresp_direct <= 1'b0;
                                mresp_lb <= 10'd0;
                            end
                        end

                        if (legacy_prune_commit)
                            prune_ctr <= prune_ctr + 1'b1;

                        // EXACT_PRUNE=5/6 search control.  Deliberately placed
                        // before, not inside, the memo hit/miss branch below.
                        // A memo miss restores the saved generator state after
                        // any same-cycle phase-control update.
                        if (SEED_MODE) begin
                            // ---- bound-pipeline output ----
                            // Only SCAN emits bound packets. CANON prunes
                            // cached bounds without refilling this pipe.
                            if (bo_v && !scan_last) begin
                                // SCAN: keep the first child with the
                                // smallest bound as the seed.
                                if (scan_take) begin
                                    scan_valid <= 1'b1;
                                    scan_total <= bo_total;
                                    scan_cnt   <= bo_cnt;
                                    scan_ids   <= bo_ids;
                                    scan_seg   <= {1'b0,bo_pre[1:0]} + 1'b1;
                                end
                            end

                            // ---- frame phase control ----
                            case (a_phase)
                                PH_SCAN: begin
                                    if (a_gen_valid) begin
                                        {a_gen_valid,a_rmask,a_rsize,a_dmask,a_dsize}<=scan_iterator[SCAN_WIDTH];
                                        {f_gen_valid[sp],f_rmask[sp],f_rsize[sp],f_dmask[sp],f_dsize[sp]}<=scan_iterator[SCAN_WIDTH];
                                        scan_issued <= 1'b1;
                                        if (scan_issued || scan_input_count>1)
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
                                            a_seed_index<=scan_fin_index;
                                            f_seed_index[sp]<=scan_fin_index;
                                            a_seed_bound<=scan_fin_total;
                                            f_seed_bound[sp]<=scan_fin_total;
                                        end
                                    end
                                end
                                PH_SEED: begin
                                    // Memo hit or child return advances phase.
                                end
                                default: begin
                                    if (cache_walk_fire) begin
                                        a_cache_next<=cache_walk_next;
                                        prune_ctr<=prune_ctr+{29'd0,cache_pruned_count};
                                        if (cache_walk_next>=a_cache_count && !cache_has_survivor)
                                            fsm_state<=ST_FINISH;
                                    end else if ((a_cache_next>=a_cache_count) && !mresp_valid && !bp_busy) begin
                                        // All memo/evaluation updates already
                                        // committed; no empty root-drain edge
                                        // is needed for the cache replay path.
                                        fsm_state <= ST_FINISH;
                                    end
                                end
                            endcase
                        end

                        if (exact_prune_miss) begin
                            // The one-step admissible bound proves that this
                            // memo-miss child cannot improve the incumbent.
                            // Count the examined action/miss and resume at the
                            // following canonical action.
                            miss_ctr <= miss_ctr + 1'b1;
                            act_ctr <= act_ctr + 1'b1;
                            mresp_valid <= 1'b0;
                            restore_generator_after_prune(
                                mresp_pre_dsize, mresp_pre_dmask,
                                mresp_pre_rsize, mresp_pre_rmask
                            );
                        end else if (mresp_valid && !memo_pipe_hit) begin
                            // Memo miss commits this action and restores the
                            // parent generator to this action's pre-state.
                            miss_ctr <= miss_ctr + 1'b1;
                            act_ctr <= act_ctr + 1'b1;
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
                                f_pipe_seg[sp] <= a_pipe_seg;
                                f_pipe_r0[sp] <= a_pipe_r0; f_pipe_r1[sp] <= a_pipe_r1;
                                f_pipe_r2[sp] <= a_pipe_r2; f_pipe_r3[sp] <= a_pipe_r3;
                                f_pipe_pred[sp] <= a_pipe_pred;
                                f_pipe_j[sp] <= a_pipe_j;
                                f_dsize[sp] <= mresp_pre_dsize;
                                f_dmask[sp] <= mresp_pre_dmask;
                                f_rsize[sp] <= mresp_pre_rsize;
                                f_rmask[sp] <= mresp_pre_rmask;
                                f_gen_valid[sp] <= mresp_pre_gen_valid;
                                f_cache_next[sp]<=mresp_cache_next;

                                sp <= sp + 1'b1;
                                f_req_idx[sp+1] <= f_req_idx[sp] + 1'b1;
                                f_count[sp+1] <= a_pipe_child_count;
                                f_id0[sp+1] <= a_pipe_cid0; f_id1[sp+1] <= a_pipe_cid1;
                                f_id2[sp+1] <= a_pipe_cid2; f_id3[sp+1] <= a_pipe_cid3;
                                f_val0[sp+1] <= (a_pipe_child_count > 0) ? rk_sval[a_pipe_r0] : 7'h7F;
                                f_val1[sp+1] <= (a_pipe_child_count > 1) ? rk_sval[a_pipe_r1] : 7'h7F;
                                f_val2[sp+1] <= (a_pipe_child_count > 2) ? rk_sval[a_pipe_r2] : 7'h7F;
                                f_val3[sp+1] <= (a_pipe_child_count > 3) ? rk_sval[a_pipe_r3] : 7'h7F;
                                f_dsize[sp+1]<=2'd0; f_dord[sp+1]<=7'd0; f_rord[sp+1]<=4'd0;
                                f_gen_valid[sp+1]<=1'b1;
                                f_best_valid[sp+1]<=1'b0; f_best_cost[sp+1]<=INF_COST;
                                f_pipe_valid[sp+1]<=1'b0;

                                a_req_idx <= a_req_idx + 1'b1;
                                a_count <= a_pipe_child_count;
                                a_id0 <= a_pipe_cid0; a_id1 <= a_pipe_cid1;
                                a_id2 <= a_pipe_cid2; a_id3 <= a_pipe_cid3;
                                a_val0 <= (a_pipe_child_count > 0) ? rk_sval[a_pipe_r0] : 7'h7F;
                                a_val1 <= (a_pipe_child_count > 1) ? rk_sval[a_pipe_r1] : 7'h7F;
                                a_val2 <= (a_pipe_child_count > 2) ? rk_sval[a_pipe_r2] : 7'h7F;
                                a_val3 <= (a_pipe_child_count > 3) ? rk_sval[a_pipe_r3] : 7'h7F;
                                a_ctx_j <= req_val[a_req_idx + 1'b1];
                                a_ctx_jid <= req_id[a_req_idx + 1'b1];

                                // The child frame and its hot mirror are visible
                                // on the next cycle, so PREP avoids a stack mux.
                                fsm_state <= ST_PREP;
                            end
                        end else begin
                            if (mresp_valid && memo_pipe_hit) begin
                                hit_ctr <= hit_ctr + 1'b1;
                                act_ctr <= act_ctr + 1'b1;
                                eval_pending(memo_child_cost);
                                if (SEED_MODE && (a_phase == PH_SEED)) begin
                                    a_gen_valid<=1'b0; f_gen_valid[sp]<=1'b0;
                                    a_cache_next<=(a_cache_count==1) ? a_cache_count : 0;
                                    a_phase <= PH_CANON;
                                    f_phase[sp] <= PH_CANON;
                                    if (seed_hit_optimal) begin
                                        // No candidate has a better optimistic
                                        // key. Account for certified pruning
                                        // without reading each cached entry.
                                        prune_ctr<=prune_ctr+a_cache_count-1'b1;
                                        fsm_state<=ST_FINISH;
                                    end
                                end else if (SEED_MODE && a_cache_next>=a_cache_count && !seed_memo_issue) begin
                                    fsm_state<=ST_FINISH;
                                end
                            end

                            if (!SEED_MODE) begin
                                if (can_issue_memo_action) begin
                                    advance_generator;
                                end else if (!a_gen_valid && !mresp_valid) begin
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
                    a_count <= f_count[sp];
                    a_id0 <= f_id0[sp]; a_id1 <= f_id1[sp];
                    a_id2 <= f_id2[sp]; a_id3 <= f_id3[sp];
                    a_val0 <= f_val0[sp]; a_val1 <= f_val1[sp];
                    a_val2 <= f_val2[sp]; a_val3 <= f_val3[sp];
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
                    a_pipe_seg <= f_pipe_seg[sp];
                    a_pipe_r0 <= f_pipe_r0[sp]; a_pipe_r1 <= f_pipe_r1[sp];
                    a_pipe_r2 <= f_pipe_r2[sp]; a_pipe_r3 <= f_pipe_r3[sp];
                    a_pipe_pred <= f_pipe_pred[sp];
                    a_pipe_j <= f_pipe_j[sp];
                    a_phase <= f_phase[sp];
                    a_cache_count<=f_cache_count[sp];
                    a_cache_next<=f_cache_next[sp];
                    a_seed_index<=f_seed_index[sp];
                    a_seed_bound<=f_seed_bound[sp];
                    fsm_state <= ST_RETURN_EVAL;
                end

                ST_RETURN_EVAL: begin
                    // The parent was restored to the missed action's pre-state.
                    // Commit that action exactly once after the child returns.
                    eval_pending(return_cost);
                    f_pipe_valid[sp] <= 1'b0;
                    // A seed return starts cache replay; other returns resume
                    // immediately after the selected candidate. A one-action
                    // frame is complete already and needs no replay at all.
                    if (SEED_MODE) begin
                        if (a_phase==PH_SEED)
                            a_cache_next<=(a_cache_count==1) ? a_cache_count : 0;
                        a_gen_valid<=1'b0; f_gen_valid[sp]<=1'b0;
                        a_phase <= PH_CANON;
                        f_phase[sp] <= PH_CANON;
                        if (a_phase==PH_SEED && seed_return_optimal) begin
                            prune_ctr<=prune_ctr+a_cache_count-1'b1;
                        end
                    end else begin
                        advance_generator;
                    end
                    mresp_valid <= 1'b0;
                    fsm_state <= ST_RUN;
                    if (SEED_MODE && a_phase==PH_SEED && seed_return_optimal)
                        fsm_state<=ST_FINISH;
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
                            if (root_best_count > 0) next_j_flat[0*`GP_J_W +: `GP_J_W] <= rk_sval[root_best_r0];
                            if (root_best_count > 1) next_j_flat[1*`GP_J_W +: `GP_J_W] <= rk_sval[root_best_r1];
                            if (root_best_count > 2) next_j_flat[2*`GP_J_W +: `GP_J_W] <= rk_sval[root_best_r2];
                            if (root_best_count > 3) next_j_flat[3*`GP_J_W +: `GP_J_W] <= rk_sval[root_best_r3];

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
