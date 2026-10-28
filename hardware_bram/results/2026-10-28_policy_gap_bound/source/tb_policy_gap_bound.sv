`timescale 1ns/1ps

// The oracle executes the original request-by-request unlimited-checkpoint
// algorithm. It does not use the gap formula. Small universes exhaust all
// pairs of child/future sets; the largest current universe streams random
// packets. Ascending and descending request order exercise order independence.
module gap_bound_cases #(
    parameter integer UB = 7,
    parameter integer EXHAUSTIVE = 1
) (output reg complete = 1'b0);
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg [UB-1:0] children = 0, future = 0;
    reg [7*UB-1:0] values_flat = 0;
    wire [10:0] cost;
    reg valid = 1'b0;
    reg valid0 = 1'b0, valid1 = 1'b0;
    integer expect0 = 0, expect1 = 0;
    integer checked = 0;
    integer variant, ci, fi, rank, iteration;
    reg [31:0] rng = 32'h5e916743;

    grover_ckpt_gap_bound #(.UB(UB)) dut (
        .clk(clk), .child_mask(children), .future_mask(future),
        .values_flat(values_flat), .cost(cost)
    );

    function integer sequential_cost;
        input [UB-1:0] initial_held, requests;
        input reverse_order;
        reg [UB-1:0] held;
        integer step, request_rank, source_rank, p, request_value, source_value;
        begin
            held = initial_held;
            sequential_cost = 0;
            for (step=0; step<UB; step=step+1) begin
                request_rank = reverse_order ? UB-1-step : step;
                if (requests[request_rank]) begin
                    source_rank = -1; source_value = 0;
                    for (p=0; p<UB; p=p+1)
                        if (held[p] && p<=request_rank) begin
                            source_rank = p;
                            source_value = values_flat[7*p +: 7];
                        end
                    request_value = values_flat[7*request_rank +: 7];
                    sequential_cost = sequential_cost + request_value - source_value;
                    held[request_rank] = 1'b1;
                    for (p=0; p<UB; p=p+1)
                        if (requests[p] && p>source_rank && p<request_rank &&
                            values_flat[7*p +: 7]>0)
                            held[p] = 1'b1;
                end
            end
        end
    endfunction

    function [31:0] random_word;
        input [31:0] state;
        reg [31:0] x;
        begin
            x = state ^ (state << 13); x = x ^ (x >> 17);
            random_word = x ^ (x << 5);
        end
    endfunction

    always @(posedge clk) begin
        valid1 = valid0; valid0 = valid;
        expect1 = expect0;
        if (valid) expect0 = sequential_cost(children, future, variant != 0);
        #1;
        if (valid1) begin
            if (cost !== expect1[10:0])
                $fatal(1, "gap bound UB=%0d case=%0d got=%0d expected=%0d", UB, checked, cost, expect1);
            checked = checked + 1;
        end
    end

    initial begin
        for (variant=0; variant<2; variant=variant+1) begin
            @(negedge clk);
            // Strictly ascending ranks include 127 in both variants and 0
            // only in the first. The implicit source 0 must work in both.
            for (rank=0; rank<UB; rank=rank+1)
                values_flat[7*rank +: 7] = variant*3 + rank*(127-variant*3)/(UB-1);
            // Hold the same one-hot choices across a rank-table change. This
            // catches value lookups that omit values_flat from their explicit
            // function inputs and can retain a previous solve's value in an
            // event-driven simulator.
            repeat (3) begin
                @(negedge clk); valid = 1'b1;
                children = {UB{1'b0}}; children[UB-1] = 1'b1;
                future = {UB{1'b0}}; future[UB-2] = 1'b1;
            end
            if (EXHAUSTIVE) begin
                for (ci=0; ci<(1<<UB); ci=ci+1)
                    for (fi=0; fi<(1<<UB); fi=fi+1) begin
                        @(negedge clk); valid = 1'b1;
                        children = ci[UB-1:0]; future = fi[UB-1:0];
                    end
            end else begin
                for (iteration=0; iteration<6000; iteration=iteration+1) begin
                    @(negedge clk); valid = 1'b1;
                    rng = random_word(rng); children = rng[UB-1:0];
                    rng = random_word(rng); future = rng[UB-1:0];
                end
            end
            @(negedge clk); children = {UB{1'b0}}; children[UB-1] = 1'b1;
            future = {UB{1'b0}}; future[UB-2] = 1'b1;
            repeat (3) @(negedge clk);
            valid = 1'b0;
            repeat (3) @(negedge clk);
        end
        $display("SUMMARY gap_bound UB=%0d cases=%0d errors=0", UB, checked);
        complete = 1'b1;
    end
endmodule

module tb_policy_gap_bound;
    wire small_done, large_done;
    gap_bound_cases #(.UB(7), .EXHAUSTIVE(1)) u_small (.complete(small_done));
    gap_bound_cases #(.UB(13), .EXHAUSTIVE(0)) u_large (.complete(large_done));
    initial begin
        wait (small_done && large_done);
        $finish;
    end
endmodule
