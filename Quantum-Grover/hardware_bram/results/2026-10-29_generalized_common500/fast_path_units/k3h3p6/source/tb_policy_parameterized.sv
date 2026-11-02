`timescale 1ns/1ps
module tb_policy_parameterized #(
    parameter integer K=3,H=3,MODE=6,FORCE_GENERIC=1,LANES=4,MEMO_ADDR_W=5,FAST_PATHS=1
);
    localparam integer CW=$clog2(K+1);
    reg clk=0; always #5 clk=~clk;
    reg rstn=0,start=0;
    reg [K-1:0] slot_valid=0;
    reg [K*7-1:0] slot_j_flat=0;
    reg [(H+1)*7-1:0] j_window_flat=0;
    wire busy,done,policy_error;
    wire [6:0] source_j;
    wire [CW-1:0] next_count,root_segment_count;
    wire [K*7-1:0] next_j_flat;
    wire [10:0] root_cost;
    wire [31:0] policy_cycles_last,policy_actions_last,policy_memo_hit_last,policy_memo_miss_last;
    grover_ckpt_policy_parameterized #(.CHECKPOINT_CAPACITY(K),.LOOKAHEAD_SHOTS(H),
        .EXACT_PRUNE(MODE),.FORCE_GENERIC(FORCE_GENERIC),.SCAN_LANES(LANES),
        .MEMO_ADDR_W(MEMO_ADDR_W),.EPOCH_W(2),.FAST_PATHS(FAST_PATHS)) dut (.*);
    string trace_path;
    integer fd,rc,es,ec,ev,eg,rows=0,elapsed,actual_cycles,total_cycles=0;
    reg [K*7-1:0] expected_tuple;
    initial begin
        if(!$value$plusargs("TRACE=%s",trace_path)) $fatal(1,"TRACE required");
        fd=$fopen(trace_path,"r"); if(!fd) $fatal(1,"trace missing");
        repeat(4) @(negedge clk);
        rstn=1;
        repeat(20000) @(negedge clk);
        while(busy) @(negedge clk);
        while(!$feof(fd)) begin
            rc=$fscanf(fd,"%h %h %h %d %d %h %d %d\n",slot_valid,slot_j_flat,
                j_window_flat,es,ec,expected_tuple,ev,eg);
            if(rc!=8) $fatal(1,"invalid vector row %0d",rows);
            if(rows>0 && rows%11==0) begin
                rstn=0;repeat(2) @(negedge clk);rstn=1;
                repeat(20000) @(negedge clk);while(busy) @(negedge clk);
            end
            start=1;@(negedge clk);start=0;elapsed=0;
            // The solver owns a snapshot after accepting start.
            slot_valid=0;slot_j_flat=0;j_window_flat=0;
            while(!done && elapsed<2000000) begin @(negedge clk);elapsed=elapsed+1;end
            if(!done || policy_error || source_j!==7'(es) || next_count!==CW'(ec) ||
                next_j_flat!==expected_tuple || root_cost!==11'(ev) || root_segment_count!==CW'(eg))
                $fatal(1,"row=%0d source=%0d/%0d count=%0d/%0d tuple=%h/%h cost=%0d/%0d seg=%0d/%0d elapsed=%0d",rows,
                    source_j,es,next_count,ec,next_j_flat,expected_tuple,root_cost,ev,root_segment_count,eg,elapsed);
            if(policy_cycles_last!==32'(elapsed))
                $fatal(1,"cycle counter differs from clock edges: %0d/%0d",policy_cycles_last,elapsed);
            $display("RESULT row=%0d cycles=%0d actions=%0d hits=%0d misses=%0d",rows,
                policy_cycles_last,policy_actions_last,policy_memo_hit_last,policy_memo_miss_last);
            total_cycles=total_cycles+policy_cycles_last;rows=rows+1;
            @(negedge clk);
        end
        $display("SUMMARY parameterized capacity=%0d lookahead=%0d cases=%0d errors=0 total_cycles=%0d",K,H,rows,total_cycles);
        $finish;
    end
endmodule
