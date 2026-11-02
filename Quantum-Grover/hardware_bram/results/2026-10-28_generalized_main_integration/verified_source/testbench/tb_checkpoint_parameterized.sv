`timescale 1ns/1ps
`include "grover_param.vh"
// Real Metadata -> pipelined Planner -> Executor integration. A delayed
// segment model remembers physical checkpoint positions independently of
// metadata validity, so clearing a destructive source does not erase its data.
module tb_checkpoint_parameterized #(parameter integer K=5);
    localparam integer S=(K>4)?K:4,CW=(K>4)?$clog2(K+1):3,SW=(K>4)?$clog2(K):2;
    reg clk=0;always #5 clk=~clk;
    reg rstn=0,invalidate_all=0,capture=0,policy_valid=0,start=0,preload=0;
    reg [SW-1:0] preload_slot=0;
    reg [6:0] preload_j=0;
    reg preload_commit=0;
    wire [S-1:0] slot_valid;
    wire [S*7-1:0] slot_j_flat,sorted_j_flat;
    wire [CW-1:0] sorted_count;
    reg [6:0] j_req=0,policy_source_j=0,accepted_source=0,accepted_request=0;
    reg [CW-1:0] policy_next_count=0;
    reg [S*7-1:0] policy_next_j_flat=0;
    wire plan_valid,plan_error,exact_hit,source_is_anchor,source_materialized,source_retain;
    wire [SW-1:0] source_slot,endpoint_slot;
    wire [S-1:0] retain_mask,clear_mask;
    wire [CW-1:0] boundary_count;
    wire [S*7-1:0] boundary_j_flat;
    wire [S*SW-1:0] boundary_slot_flat;
    wire iter_start,iter_do_init,iter_bridge,meta_clear_en,meta_commit_en,busy,done,aborted;
    wire [15:0] iter_count;
    wire [SW-1:0] iter_src_slot,iter_dst_slot,meta_commit_slot,exec_endpoint_slot;
    wire [S-1:0] meta_clear_mask;
    wire [6:0] meta_commit_j;
    wire [31:0] physical_iter_issued;
    wire [15:0] bridge_count,intermediate_commit_count;
    reg iter_busy=0,iter_done=0;
    integer delay_count=0;
    reg [SW-1:0] pending_slot;
    integer physical_j[0:S-1];
    integer pending_j;
    reg [S-1:0] physical_valid=0,locked_mask=0;
    integer locked_j[0:S-1];
    grover_ckpt_meta #(.CHECKPOINT_CAPACITY(K)) u_meta (
        .clk(clk),.rstn(rstn),.invalidate_all(invalidate_all),
        .clear_en(!preload && meta_clear_en),.clear_mask(meta_clear_mask),
        .commit_en(preload?preload_commit:meta_commit_en),
        .commit_slot(preload?preload_slot:meta_commit_slot),.commit_j(preload?preload_j:meta_commit_j),
        .slot_valid(slot_valid),.slot_j_flat(slot_j_flat),.sorted_count(sorted_count),.sorted_j_flat(sorted_j_flat)
    );
    grover_ckpt_planner_generic_pipe #(.CHECKPOINT_CAPACITY(K)) u_planner(.*);
    grover_ckpt_executor #(.CHECKPOINT_CAPACITY(K)) u_executor (
        .clk(clk),.rstn(rstn),.start(start),.invalidate(invalidate_all),
        .plan_valid(plan_valid),.plan_exact_hit(exact_hit),.plan_source_is_anchor(source_is_anchor),
        .plan_source_materialized(source_materialized),.plan_source_retain(source_retain),.plan_source_slot(source_slot),
        .plan_source_j(accepted_source),.plan_j_req(accepted_request),.plan_clear_mask(clear_mask),
        .plan_boundary_count(boundary_count),.plan_boundary_j_flat(boundary_j_flat),
        .plan_boundary_slot_flat(boundary_slot_flat),.plan_endpoint_slot(endpoint_slot),
        .iter_start(iter_start),.iter_do_init(iter_do_init),.iter_count(iter_count),
        .iter_src_slot(iter_src_slot),.iter_dst_slot(iter_dst_slot),.iter_bridge(iter_bridge),.iter_busy(iter_busy),.iter_done(iter_done),
        .meta_clear_en(meta_clear_en),.meta_clear_mask(meta_clear_mask),.meta_commit_en(meta_commit_en),
        .meta_commit_slot(meta_commit_slot),.meta_commit_j(meta_commit_j),.busy(busy),.done(done),.aborted(aborted),
        .endpoint_slot(exec_endpoint_slot),.physical_iter_issued(physical_iter_issued),.bridge_count(bridge_count),
        .intermediate_commit_count(intermediate_commit_count)
    );
    integer segments=0,bridges=0,commits=0;
    always @(posedge clk) begin
        iter_done<=0;
        if(!rstn) begin iter_busy<=0;delay_count<=0;physical_valid<=0;end
        else if(preload) begin
            if(preload_commit) begin physical_j[preload_slot]<=preload_j;physical_valid[preload_slot]<=1;end
        end else begin
            if(iter_start) begin
                if(iter_busy) $fatal(1,"overlapping physical segments");
                if(!iter_do_init && !physical_valid[iter_src_slot]) $fatal(1,"missing physical predecessor");
                if(iter_src_slot>=K || iter_dst_slot>=K) $fatal(1,"slot address out of range");
                if(locked_mask[iter_dst_slot] && !exact_hit) $fatal(1,"retained checkpoint overwritten");
                pending_j=(iter_do_init?0:physical_j[iter_src_slot])+iter_count;
                pending_slot=iter_dst_slot;iter_busy<=1;delay_count<=3;segments=segments+1;
                if(iter_bridge) begin
                    if(iter_count!=1 || iter_src_slot==iter_dst_slot) $fatal(1,"invalid bridge");
                    bridges=bridges+1;
                end
            end else if(iter_busy) begin
                if(delay_count==1) begin
                    physical_j[pending_slot]<=pending_j;physical_valid[pending_slot]<=1;
                    iter_busy<=0;iter_done<=1;delay_count<=0;
                end else delay_count<=delay_count-1;
            end
            if(meta_commit_en) begin
                if(!physical_valid[meta_commit_slot] || physical_j[meta_commit_slot]!=meta_commit_j)
                    $fatal(1,"metadata committed before physical boundary");
                commits=commits+1;
            end
        end
    end
    string trace_path;
    integer fd,rc,es,ec,ev,eg,rows=0,elapsed;
    reg [K-1:0] input_valid;
    reg [K*7-1:0] input_flat,expected_tuple;
    reg [4*7-1:0] window;
    initial begin
        if(!$value$plusargs("TRACE=%s",trace_path)) $fatal(1,"TRACE required");
        fd=$fopen(trace_path,"r");if(!fd)$fatal(1,"trace missing");
        repeat(4) @(negedge clk);rstn=1;
        while(!$feof(fd)) begin
            rc=$fscanf(fd,"%h %h %h %d %d %h %d %d\n",input_valid,input_flat,window,es,ec,expected_tuple,ev,eg);
            if(rc!=8)$fatal(1,"invalid trace row");
            preload=1;invalidate_all=1;@(negedge clk);invalidate_all=0;
            for(integer p=0;p<K;p=p+1) begin
                preload_slot=p;preload_j=input_flat[7*p+:7];preload_commit=input_valid[p];@(negedge clk);
            end
            preload_commit=0;preload=0;
            j_req=window[6:0];policy_source_j=es;policy_next_count=ec;policy_next_j_flat=expected_tuple;
            accepted_source=es;accepted_request=window[6:0];policy_valid=1;capture=1;
            @(negedge clk);capture=0;
            if(plan_error || !plan_valid)$fatal(1,"legal policy rejected row%0d",rows);
            locked_mask=retain_mask;
            for(integer p=0;p<K;p=p+1) locked_j[p]=physical_j[p];
            // Changing policy inputs after capture must not change the packet.
            policy_source_j=0;policy_next_count=0;policy_next_j_flat=0;policy_valid=0;
            start=1;@(negedge clk);start=0;elapsed=0;
            while(!done && elapsed<1000)begin @(negedge clk);elapsed=elapsed+1;end
            if(!done || aborted)$fatal(1,"execution failed row%0d",rows);
            repeat(2)@(negedge clk);
            if(sorted_count!=ec || sorted_j_flat[K*7-1:0]!==expected_tuple)
                $fatal(1,"metadata final tuple mismatch row%0d",rows);
            if(physical_iter_issued!=accepted_request-accepted_source)
                $fatal(1,"physical cost mismatch row%0d",rows);
            if(physical_j[exec_endpoint_slot]!=accepted_request)$fatal(1,"wrong endpoint state");
            for(integer p=0;p<K;p=p+1) if(locked_mask[p] && physical_j[p]!=locked_j[p])
                $fatal(1,"preserved source changed");
            rows=rows+1;
        end
        // Invalid policy packets must complete as aborted without issuing work.
        j_req=127;accepted_request=127;accepted_source=0;policy_source_j=0;
        policy_next_count=0;policy_next_j_flat=0;policy_valid=1;capture=1;
        @(negedge clk);capture=0;
        if(plan_valid || !plan_error)$fatal(1,"invalid packet accepted");
        start=1;@(negedge clk);start=0;
        if(!done || !aborted || iter_start)$fatal(1,"invalid packet reached physical engine");
        repeat(2)@(negedge clk);
        // Flush during real outstanding work: allow the current segment to
        // drain, discard its metadata commit, and acknowledge an abort.
        preload=1;invalidate_all=1;@(negedge clk);invalidate_all=0;preload=0;
        locked_mask=0;j_req=6;accepted_request=6;accepted_source=0;policy_source_j=0;
        policy_next_count=1;policy_next_j_flat=6;policy_valid=1;capture=1;
        @(negedge clk);capture=0;
        if(!plan_valid || plan_error)$fatal(1,"abort setup rejected");
        start=1;@(negedge clk);start=0;
        while(!iter_busy)@(negedge clk);
        invalidate_all=1;@(negedge clk);invalidate_all=0;elapsed=0;
        while(!done && elapsed<100)begin @(negedge clk);elapsed=elapsed+1;end
        if(!done || !aborted || slot_valid!=0)$fatal(1,"in-flight invalidate failed");
        $display("SUMMARY checkpoint capacity=%0d cases=%0d segments=%0d bridges=%0d commits=%0d errors=0",K,rows,segments,bridges,commits);
        $finish;
    end
endmodule
