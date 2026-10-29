`timescale 1ns/1ps
`include "grover_param.vh"

// Standalone latency/bit-exact harness for the compile-time K/H policy grid.
//
// Trace rows are written by sim/kh_sweep.py:
//   reset_slots, j[0]..j[8], expected_source, expected_count,
//   expected_next[0]..expected_next[3]
//
// reset_slots clears only the logical checkpoint set.  It deliberately does
// not reset the policy memo/epoch, matching consecutive searches in bench500.
module tb_policy_kh_sweep #(
    parameter integer CKPT_K = 3,
    parameter integer H_FUTURE = 3,
    parameter integer EXACT_PRUNE = 0
);
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rstn = 1'b0;
    reg start = 1'b0;
    reg [3:0] slot_valid = 4'b0;
    reg [4*`GP_J_W-1:0] slot_j_flat = 0;
    reg [9*`GP_J_W-1:0] j_window_flat = 0;

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

    grover_ckpt_policy_rolling #(
        .CKPT_K(CKPT_K),
        .H_FUTURE(H_FUTURE),
        .EXACT_PRUNE(EXACT_PRUNE),
        .ACTION_LIMIT(0)
    ) dut (
        .clk(clk), .rstn(rstn), .start(start),
        .slot_valid(slot_valid), .slot_j_flat(slot_j_flat),
        .j_window_flat(j_window_flat),
        .busy(busy), .done(done), .policy_error(policy_error),
        .source_j(source_j), .next_count(next_count),
        .next_j_flat(next_j_flat), .root_cost(root_cost),
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

    integer trace_fd;
    integer scan_count;
    integer reset_slots_i;
    integer j0, j1, j2, j3, j4, j5, j6, j7, j8;
    integer exp_source, exp_count, exp0, exp1, exp2, exp3;
    integer row_count = 0;
    integer error_count = 0;
    integer total_cycles = 0;
    integer total_actions = 0;
    integer max_cycles = 0;
    integer trace_timeout;
    reg [1023:0] trace_path;

    task load_window;
        begin
            j_window_flat = 0;
            j_window_flat[0*`GP_J_W +: `GP_J_W] = j0;
            j_window_flat[1*`GP_J_W +: `GP_J_W] = j1;
            j_window_flat[2*`GP_J_W +: `GP_J_W] = j2;
            j_window_flat[3*`GP_J_W +: `GP_J_W] = j3;
            j_window_flat[4*`GP_J_W +: `GP_J_W] = j4;
            j_window_flat[5*`GP_J_W +: `GP_J_W] = j5;
            j_window_flat[6*`GP_J_W +: `GP_J_W] = j6;
            j_window_flat[7*`GP_J_W +: `GP_J_W] = j7;
            j_window_flat[8*`GP_J_W +: `GP_J_W] = j8;
        end
    endtask

    task check_result;
        integer i;
        integer got;
        integer expected;
        begin
            if (policy_error) begin
                $display("ERROR,row=%0d,policy_error", row_count);
                error_count = error_count + 1;
            end
            if (source_j !== exp_source[`GP_J_W-1:0]) begin
                $display("ERROR,row=%0d,source,got=%0d,expected=%0d",
                         row_count, source_j, exp_source);
                error_count = error_count + 1;
            end
            if (next_count !== exp_count[2:0]) begin
                $display("ERROR,row=%0d,count,got=%0d,expected=%0d",
                         row_count, next_count, exp_count);
                error_count = error_count + 1;
            end
            for (i = 0; i < 4; i = i + 1) begin
                got = next_j_flat[i*`GP_J_W +: `GP_J_W];
                case (i)
                    0: expected = exp0;
                    1: expected = exp1;
                    2: expected = exp2;
                    default: expected = exp3;
                endcase
                if ((i < exp_count) && (got != expected)) begin
                    $display("ERROR,row=%0d,next%0d,got=%0d,expected=%0d",
                             row_count, i, got, expected);
                    error_count = error_count + 1;
                end
            end
        end
    endtask

    task accept_next_set;
        integer i;
        begin
            slot_valid = 4'b0;
            slot_j_flat = 0;
            for (i = 0; i < 4; i = i + 1) begin
                if (i < next_count) begin
                    slot_valid[i] = 1'b1;
                    slot_j_flat[i*`GP_J_W +: `GP_J_W] =
                        next_j_flat[i*`GP_J_W +: `GP_J_W];
                end
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("TRACE=%s", trace_path)) begin
            $display("FAIL: +TRACE=<path> is required");
            $finish(2);
        end
        trace_fd = $fopen(trace_path, "r");
        if (trace_fd == 0) begin
            $display("FAIL: cannot open trace %0s", trace_path);
            $finish(2);
        end

        repeat (5) @(posedge clk);
        rstn <= 1'b1;
        repeat (3) @(posedge clk);

        while (!$feof(trace_fd)) begin
            scan_count = $fscanf(
                trace_fd,
                "%d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
                reset_slots_i,
                j0, j1, j2, j3, j4, j5, j6, j7, j8,
                exp_source, exp_count, exp0, exp1, exp2, exp3
            );
            if (scan_count == 16) begin
                if (reset_slots_i != 0) begin
                    slot_valid = 4'b0;
                    slot_j_flat = 0;
                end
                load_window();
                @(posedge clk);
                while (busy) @(posedge clk);
                start <= 1'b1;
                @(posedge clk);
                start <= 1'b0;

                trace_timeout = 0;
                while (!done && trace_timeout < 2000000) begin
                    @(posedge clk);
                    trace_timeout = trace_timeout + 1;
                end
                if (!done) begin
                    $display("FAIL: timeout row=%0d", row_count);
                    $finish(3);
                end
                #1;
                check_result();
                accept_next_set();
                total_cycles = total_cycles + policy_cycles_last;
                total_actions = total_actions + policy_actions_last;
                if (policy_cycles_last > max_cycles)
                    max_cycles = policy_cycles_last;
                row_count = row_count + 1;
            end else if (scan_count != -1) begin
                $display("FAIL: malformed trace row after %0d rows (fields=%0d)",
                         row_count, scan_count);
                $finish(4);
            end
        end

        $fclose(trace_fd);
        $display("SUMMARY,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                 CKPT_K, H_FUTURE, row_count, total_cycles,
                 total_actions, max_cycles, error_count);
        $finish(error_count == 0 ? 0 : 2);
    end
endmodule
