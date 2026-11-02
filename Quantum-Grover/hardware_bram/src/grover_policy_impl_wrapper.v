`timescale 1ns/1ps
`include "grover_param.vh"

// Low-I/O implementation wrapper for normal Vivado place/route.
// Keeps the wide policy interface inside the FPGA so top-level I/O count stays small.
// Use hierarchical utilization on u_dut/u_policy to inspect the policy itself.
module grover_policy_impl_wrapper (
    input  wire clk,
    input  wire rstn,
    output wire activity,
    output wire done_out,
    output wire error_out,
    output wire checksum_out
);
    reg [31:0] stim_lfsr;
    reg [7:0]  start_div;
    reg        start;
    reg [3:0]  slot_valid;
    reg [4*`GP_J_W-1:0] slot_j_flat;
    reg [9*`GP_J_W-1:0] j_window_flat;

    wire busy;
    wire done;
    wire policy_error;
    wire [`GP_J_W-1:0] source_j;
    wire [2:0] next_count;
    wire [4*`GP_J_W-1:0] next_j_flat;
    wire [10:0] root_cost;
    wire [2:0] root_segment_count;
    wire [31:0] policy_cycles_last;
    wire [31:0] policy_actions_last;
    wire [31:0] policy_memo_hit_last;
    wire [31:0] policy_memo_miss_last;
    wire [31:0] policy_cycles_total;
    wire [31:0] policy_actions_total;
    wire [31:0] policy_max_latency;
    wire [7:0] policy_epoch;

    reg checksum_r;

    always @(posedge clk) begin
        if (!rstn) begin
            stim_lfsr    <= 32'h1ACE_B00C;
            start_div    <= 8'd0;
            start        <= 1'b0;
            slot_valid   <= 4'b1111;
            slot_j_flat  <= {`GP_J_W*4{1'b0}};
            j_window_flat<= {`GP_J_W*9{1'b0}};
            checksum_r   <= 1'b0;
        end else begin
            stim_lfsr <= {stim_lfsr[30:0], stim_lfsr[31] ^ stim_lfsr[21] ^ stim_lfsr[1] ^ stim_lfsr[0]};
            start_div <= start_div + 1'b1;
            start     <= (start_div == 8'h00) && !busy;

            // Dynamic internal stimulus prevents constant-folding of the policy interface.
            slot_valid <= {slot_valid[2:0], stim_lfsr[0]};
            slot_j_flat <= {slot_j_flat[4*`GP_J_W-2:0], stim_lfsr[1]};
            j_window_flat <= {j_window_flat[9*`GP_J_W-2:0], stim_lfsr[2]};

            checksum_r <= checksum_r ^ done ^ policy_error ^ ^source_j ^ ^next_count ^
                          ^next_j_flat ^ ^root_cost ^ ^root_segment_count ^
                          ^policy_cycles_last ^ ^policy_actions_last ^
                          ^policy_memo_hit_last ^ ^policy_memo_miss_last ^
                          ^policy_cycles_total ^ ^policy_actions_total ^
                          ^policy_max_latency ^ ^policy_epoch;
        end
    end

    (* DONT_TOUCH = "yes" *)
    grover_policy_ooc_top u_dut (
        .clk(clk),
        .rstn(rstn),
        .start(start),
        .slot_valid(slot_valid),
        .slot_j_flat(slot_j_flat),
        .j_window_flat(j_window_flat),
        .busy(busy),
        .done(done),
        .policy_error(policy_error),
        .source_j(source_j),
        .next_count(next_count),
        .next_j_flat(next_j_flat),
        .root_cost(root_cost),
        .root_segment_count(root_segment_count),
        .policy_cycles_last(policy_cycles_last),
        .policy_actions_last(policy_actions_last),
        .policy_memo_hit_last(policy_memo_hit_last),
        .policy_memo_miss_last(policy_memo_miss_last),
        .policy_cycles_total(policy_cycles_total),
        .policy_actions_total(policy_actions_total),
        .policy_max_latency(policy_max_latency),
        .policy_epoch(policy_epoch)
    );

    assign activity     = busy;
    assign done_out     = done;
    assign error_out    = policy_error;
    assign checksum_out = checksum_r;
endmodule
