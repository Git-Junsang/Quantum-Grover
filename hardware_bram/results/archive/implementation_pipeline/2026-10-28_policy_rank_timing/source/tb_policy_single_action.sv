`timescale 1ns/1ps
`include "grover_param.vh"

// Directed regression for the mode-6 forced-root fast path. The mode-0 solver
// supplies an independent exhaustive policy result. Single-action cases must
// return on the first BUILD edge, with no universe setup, bound capture
// or memo read. Multi-action cases must keep the normal exact-search path.
module tb_policy_single_action;
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rstn = 1'b0;
    reg start = 1'b0;
    reg [3:0] slot_valid = 4'd0;
    reg [27:0] slot_j_flat = 28'd0;
    reg [62:0] j_window_flat = 63'd0;

    wire fast_busy, fast_done, fast_error;
    wire ref_busy, ref_done, ref_error;
    wire [6:0] fast_source, ref_source;
    wire [2:0] fast_count, ref_count, fast_segments, ref_segments;
    wire [27:0] fast_next, ref_next;
    wire [10:0] fast_cost, ref_cost;
    wire [31:0] fast_cycles, ref_cycles, fast_hits, fast_misses;
    wire [7:0] fast_epoch, ref_epoch;

    grover_ckpt_policy_rolling #(.CHECKPOINT_CAPACITY(3), .LOOKAHEAD_SHOTS(3), .EXACT_PRUNE(6)) fast (
        .clk(clk), .rstn(rstn), .start(start),
        .slot_valid(slot_valid), .slot_j_flat(slot_j_flat), .j_window_flat(j_window_flat),
        .busy(fast_busy), .done(fast_done), .policy_error(fast_error),
        .source_j(fast_source), .next_count(fast_count), .next_j_flat(fast_next),
        .root_cost(fast_cost), .root_segment_count(fast_segments),
        .policy_cycles_last(fast_cycles), .policy_memo_hit_last(fast_hits),
        .policy_memo_miss_last(fast_misses), .policy_epoch(fast_epoch)
    );
    grover_ckpt_policy_rolling #(.CHECKPOINT_CAPACITY(3), .LOOKAHEAD_SHOTS(3), .EXACT_PRUNE(0)) reference (
        .clk(clk), .rstn(rstn), .start(start),
        .slot_valid(slot_valid), .slot_j_flat(slot_j_flat), .j_window_flat(j_window_flat),
        .busy(ref_busy), .done(ref_done), .policy_error(ref_error),
        .source_j(ref_source), .next_count(ref_count), .next_j_flat(ref_next),
        .root_cost(ref_cost), .root_segment_count(ref_segments),
        .policy_cycles_last(ref_cycles), .policy_epoch(ref_epoch)
    );

    integer cases = 0;
    integer errors = 0;
    integer clear_cycles = 0;
    integer bound_issues = 0;
    integer memo_reads = 0;
    integer fast_decisions = 0;
    integer clear_events = 0;
    integer i;
    reg seen_fast, seen_ref;

    always @(posedge clk) begin
        if (rstn && start && !fast_busy) begin
            clear_cycles = 0;
            bound_issues = 0;
            memo_reads = 0;
            fast_decisions = 0;
        end else if (rstn && fast_busy) begin
            if (fast.fsm_state == fast.ST_CLEAR) clear_cycles = clear_cycles + 1;
            if (fast.bound_capture && !fast.bp_flush) bound_issues = bound_issues + 1;
            if (fast.memo_rd_en) memo_reads = memo_reads + 1;
            if (((fast.fsm_state == fast.ST_BUILD) && fast.build_idx == 0 && fast.early_root_single) ||
                ((fast.fsm_state == fast.ST_RUN) && fast.root_single_action))
                fast_decisions = fast_decisions + 1;
        end
    end

    task run_case;
        input [3:0] valid;
        input [27:0] slots;
        input [6:0] j0, j1, j2, j3;
        input expect_fast;
        integer timeout;
        begin
            @(negedge clk);
            slot_valid = valid;
            slot_j_flat = slots;
            j_window_flat = {35'd0, j3, j2, j1, j0};
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            seen_fast = 1'b0; seen_ref = 1'b0;
            timeout = 0;
            while (!(seen_fast && seen_ref) && timeout < 100000) begin
                @(negedge clk);
                if (fast_done) seen_fast = 1'b1;
                if (ref_done) seen_ref = 1'b1;
                timeout = timeout + 1;
            end
            cases = cases + 1;
            if (!(seen_fast && seen_ref)) $fatal(1, "case %0d timeout", cases);
            if (fast_error || ref_error || fast_source !== ref_source ||
                fast_count !== ref_count || fast_next !== ref_next ||
                fast_segments !== ref_segments || fast_epoch !== ref_epoch) begin
                $display("ERROR case=%0d decision fast=%0d/%0d/%h ref=%0d/%0d/%h",
                         cases, fast_source, fast_count, fast_next, ref_source, ref_count, ref_next);
                errors = errors + 1;
            end
            if (clear_cycles != 0) begin
                clear_events = clear_events + 1;
                if (clear_cycles != 381) $fatal(1, "unexpected clear length %0d", clear_cycles);
            end
            if (expect_fast) begin
                // One input-snapshot decision edge; no universe BUILD.
                if ((fast_cycles != clear_cycles + 1) || bound_issues != 0 ||
                    memo_reads != 0 || fast_decisions != 1 || fast_hits != 0 || fast_misses != 0 ||
                    fast_cost != (j0 - fast_source) || fast_cost > ref_cost) begin
                    $display("ERROR case=%0d fast-path cycles=%0d clear=%0d bound=%0d memo=%0d take=%0d cost=%0d",
                             cases, fast_cycles, clear_cycles, bound_issues, memo_reads,
                             fast_decisions, fast_cost);
                    errors = errors + 1;
                end
            end else if (fast_decisions != 0 || bound_issues == 0 || fast_cost !== ref_cost) begin
                $display("ERROR case=%0d multi-action incorrectly shortened", cases);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (5) @(negedge clk);
        rstn = 1'b1;
        // Empty set and a current endpoint of zero.
        run_case(4'b0000, 28'd0, 0, 1, 2, 3, 1'b1);
        // Endpoint already held; retain every old checkpoint.
        run_case(4'b0111, {7'd0,7'd9,7'd5,7'd2}, 5, 5, 5, 9, 1'b1);
        // Insert a new endpoint into an available slot.
        run_case(4'b0011, {14'd0,7'd9,7'd2}, 5, 9, 5, 2, 1'b1);
        // Full set without the endpoint has multiple retention choices.
        run_case(4'b0111, {7'd0,7'd11,7'd7,7'd2}, 5, 7, 11, 2, 1'b0);
        // An eligible intermediate deposit also creates multiple choices.
        run_case(4'b0001, {21'd0,7'd2}, 8, 4, 8, 2, 1'b0);
        // Maximum endpoint and valid checkpoint zero.
        run_case(4'b0011, {14'd0,7'd126,7'd0}, 127, 126, 127, 0, 1'b1);
        // Noncontiguous physical slots in non-value order.
        run_case(4'b1011, {7'd5,7'd0,7'd2,7'd9}, 9, 9, 5, 2, 1'b1);
        // Fast decisions must not break memo epoch wrap or soft reset clear.
        for (i=0; i<260; i=i+1)
            run_case(4'b0000, 28'd0, 0, 0, 0, 0, 1'b1);
        if (clear_events != 2) $fatal(1, "expected initial+wrap clear, got %0d", clear_events);
        @(negedge clk); rstn = 1'b0;
        repeat (3) @(negedge clk);
        rstn = 1'b1;
        run_case(4'b0000, 28'd0, 0, 1, 2, 3, 1'b1);
        if (clear_events != 3) $fatal(1, "soft reset did not clear memo");
        $display("SUMMARY single_action cases=%0d errors=%0d clears=%0d", cases, errors, clear_events);
        if (errors != 0) $fatal(1, "single-action regression failed");
        $finish;
    end
endmodule
