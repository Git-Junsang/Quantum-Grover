`timescale 1ns/1ps
`include "grover_param.vh"

// Python-generated independent jump7/rejection/context-restart vectors.
// Includes H8's ninth future request, needed by the speculative H8 root.
module tb_shadow_horizon #(
    parameter integer FUTURE_COUNT=9
);
    reg clk=0;
    always #5 clk=~clk;
    reg rstn=0, start=0;
    reg [31:0] post_state;
    reg [4:0] round_in;
    reg [31:0] l_in;
    reg [15:0] trial_in;
    wire busy, done;
    wire [62:0] futures;
    wire [31:0] state_out, l_out;
    wire [4:0] round_out;
    wire [15:0] trial_out, draws;
    grover_shadow_j #(.FUTURE_COUNT(FUTURE_COUNT),.OUTPUT_COUNT(9)) dut (
        .clk(clk),.rstn(rstn),.start(start),.post_j_state(post_state),
        .round_after_current(round_in),.L_after_current(l_in),.trial_after_current(trial_in),
        .busy(busy),.done(done),.future_j_flat(futures),.shadow_state_final(state_out),
        .round_final(round_out),.L_final(l_out),.trial_final(trial_out),.candidate_draws(draws)
    );
    reg [1023:0] path;
    reg [62:0] exp_futures;
    reg [31:0] exp_state, exp_l;
    integer exp_round, exp_trial, exp_draws;
    integer fd, n, rows=0, guard;
    initial begin
        if (!$value$plusargs("VECTORS=%s",path)) $fatal(1,"missing vectors");
        fd=$fopen(path,"r");
        if (!fd) $fatal(1,"cannot open vectors");
        repeat(4) @(negedge clk);
        rstn=1;
        while (!$feof(fd)) begin
            n=$fscanf(fd,"%h %d %d %d %h %h %d %d %d %d\n",
                      post_state,round_in,l_in,trial_in,exp_futures,exp_state,
                      exp_round,exp_l,exp_trial,exp_draws);
            if (n!=10) $fatal(1,"bad vector");
            start=1;
            @(negedge clk);
            start=0;
            guard=0;
            while (!done) begin
                @(negedge clk);
                guard=guard+1;
                if (guard>1000) $fatal(1,"shadow timeout");
            end
            if (futures!==exp_futures || state_out!==exp_state ||
                round_out!=exp_round || l_out!=exp_l || trial_out!=exp_trial || draws!=exp_draws)
                $fatal(1,"shadow mismatch row=%0d count=%0d",rows,FUTURE_COUNT);
            rows=rows+1;
            @(negedge clk);
        end
        $display("PASS shadow future_count=%0d contexts=%0d",FUTURE_COUNT,rows);
        $finish;
    end
endmodule
