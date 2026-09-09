`timescale 1ns/1ps
`include "grover_param.vh"

// OOC/resource wrapper for the K4/H6 exact Rolling policy.
// All functional inputs/outputs are kept as top-level ports so synthesis cannot
// constant-fold the policy away.  Main-IP integration is intentionally absent.
module grover_policy_ooc_top (
    input  wire                         clk,
    input  wire                         rstn,
    input  wire                         start,
    input  wire [3:0]                   slot_valid,
    input  wire [4*`GP_J_W-1:0]         slot_j_flat,
    input  wire [9*`GP_J_W-1:0]         j_window_flat,
    output wire                         busy,
    output wire                         done,
    output wire                         policy_error,
    output wire [`GP_J_W-1:0]           source_j,
    output wire [2:0]                   next_count,
    output wire [4*`GP_J_W-1:0]         next_j_flat,
    output wire [10:0]                  root_cost,
    output wire [2:0]                   root_segment_count,
    output wire [31:0]                  policy_cycles_last,
    output wire [31:0]                  policy_actions_last,
    output wire [31:0]                  policy_memo_hit_last,
    output wire [31:0]                  policy_memo_miss_last,
    output wire [31:0]                  policy_cycles_total,
    output wire [31:0]                  policy_actions_total,
    output wire [31:0]                  policy_max_latency,
    output wire [7:0]                   policy_epoch
);
    (* keep_hierarchy = "yes" *)
    grover_ckpt_policy_rolling #(.ACTION_LIMIT(0)) u_policy (
        .clk(clk), .rstn(rstn), .start(start),
        .slot_valid(slot_valid), .slot_j_flat(slot_j_flat), .j_window_flat(j_window_flat),
        .busy(busy), .done(done), .policy_error(policy_error),
        .source_j(source_j), .next_count(next_count), .next_j_flat(next_j_flat),
        .root_cost(root_cost), .root_segment_count(root_segment_count),
        .policy_cycles_last(policy_cycles_last), .policy_actions_last(policy_actions_last),
        .policy_memo_hit_last(policy_memo_hit_last), .policy_memo_miss_last(policy_memo_miss_last),
        .policy_cycles_total(policy_cycles_total), .policy_actions_total(policy_actions_total),
        .policy_max_latency(policy_max_latency), .policy_epoch(policy_epoch)
    );
endmodule
