`timescale 1ns/1ps
module tb_plan_queue_parameterized;
    localparam integer S=10,CW=4;
    reg clk=0;always #5 clk=~clk;
    reg rstn=0,flush=0,push=0,pop=0,demand=0;
    reg [7:0] push_oracle_epoch=0;
    reg [6:0] push_expected_j=0,push_source_j=0;
    reg [CW-1:0] push_input_s_count=0,push_next_count=0,push_segment_count=0;
    reg [S*7-1:0] push_input_s_flat=0,push_next_flat=0;
    reg [10:0] push_root_cost=0;
    wire empty,full;
    wire [2:0] level,highwater;
    wire [31:0] empty_on_demand_count;
    wire [7:0] head_oracle_epoch;
    wire [6:0] head_expected_j,head_source_j;
    wire [CW-1:0] head_input_s_count,head_next_count,head_segment_count;
    wire [S*7-1:0] head_input_s_flat,head_next_flat;
    wire [10:0] head_root_cost;
    grover_ckpt_plan_queue #(.SLOTS(S),.COUNT_W(CW)) dut(.*);
    task automatic payload(input integer id);
        begin
            push_oracle_epoch=8'(251+id);push_expected_j=7'(120+id);push_source_j=7'(87+id);
            push_input_s_count=10;push_next_count=10;push_segment_count=10;push_root_cost=11'(1900+id);
            for(integer n=0;n<S;n=n+1) begin
                push_input_s_flat[n*7+:7]=7'(n+id*10);push_next_flat[n*7+:7]=7'(127-n-id);
            end
        end
    endtask
    task automatic check(input integer id);
        begin
            payload(id);
            if(head_oracle_epoch!==push_oracle_epoch || head_expected_j!==push_expected_j ||
               head_source_j!==push_source_j || head_input_s_count!==push_input_s_count ||
               head_next_count!==push_next_count || head_segment_count!==push_segment_count ||
               head_root_cost!==push_root_cost || head_input_s_flat!==push_input_s_flat || head_next_flat!==push_next_flat)
                $fatal(1,"wide FIFO packet truncated id%0d",id);
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rstn=1;
        demand=1;@(negedge clk);demand=0;
        if(empty_on_demand_count!=1)$fatal(1,"empty demand counter");
        for(integer id=0;id<4;id=id+1) begin payload(id);push=1;@(negedge clk);end
        push=0;if(!full || highwater!=4)$fatal(1,"full queue not exercised");
        payload(9);push=1;@(negedge clk);push=0;
        if(level!=4)$fatal(1,"overflow accepted");
        for(integer id=0;id<4;id=id+1) begin check(id);pop=1;@(negedge clk);end
        pop=0;if(!empty)$fatal(1,"queue failed to drain");
        payload(3);push=1;@(negedge clk);push=0;check(3);
        flush=1;push=1;pop=1;payload(7);@(negedge clk);flush=0;push=0;pop=0;
        if(!empty)$fatal(1,"flush did not override enqueue/dequeue");
        payload(6);push=1;@(negedge clk);push=0;check(6);
        payload(7);push=1;pop=1;@(negedge clk);push=0;pop=0;check(7);
        $display("SUMMARY wide_queue slots=10 count_width=4 full_flush_simultaneous=passed errors=0");$finish;
    end
endmodule
