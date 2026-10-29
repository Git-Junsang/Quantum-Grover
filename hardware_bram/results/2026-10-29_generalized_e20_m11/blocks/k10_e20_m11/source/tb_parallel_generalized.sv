`timescale 1ns/1ps
`include "grover_param.vh"
module tb_parallel_generalized #(
    parameter integer K=3,E=4,M=2
);
    localparam integer RP=(E>M)?E:M,SW=(K<2)?1:$clog2(K),W=32*23;
    reg clk=0;always #5 clk=~clk;
    reg rstn=0;
    reg [SW-1:0] rd_slot=0,wr_slot=0;
    reg [RP-1:0] rd_en=0;
    reg [RP*9-1:0] rd_rows=0;
    wire [RP*W-1:0] rd_data;
    wire [RP-1:0] rd_valid;
    reg [E-1:0] wr_en=0;
    reg [E*9-1:0] wr_rows=0;
    reg [E*W-1:0] wr_data=0;
    grover_ckpt_mem_parallel #(.CHECKPOINT_CAPACITY(K),.READ_PORTS(RP),.WRITE_PORTS(E)) u_mem(.*);
    integer extreme=0,plusarg_result,saturation_events=0;
    function automatic integer sample(input integer slot,row,lane);
        begin
            if(extreme) sample=(lane%4==0) ? -4194303 : 4194303;
            else sample=((slot*997+row*31+lane*17)%200001)-100000;
        end
    endfunction
    reg [1:0] op=0,predicate_mode=0;
    reg [E-1:0] row_valid=0;
    reg [E*9-1:0] row_indices=0;
    reg acc_clear=0;
    reg [E*W-1:0] amp_in=0;
    reg [E*32*16-1:0] data_in=0;
    reg [E*32-1:0] found_mask_in=0;
    reg signed [15:0] threshold_a=-3,threshold_b=17;
    reg [14:0] data_count=16355;
    reg enum_enable=1;
    wire [E*W-1:0] amp_out;
    wire [E-1:0] row_out_valid;
    wire [E*9-1:0] row_out_indices;
    wire signed [38:0] global_sum;
    wire signed [24:0] two_mean;
    wire sum_commit,sat_event;
    grover_iter_datapath_parallel #(.INTRA_ENGINES(E)) u_iteration (
        .clk(clk),.rstn(rstn),.op(op),.row_valid(row_valid),.row_indices(row_indices),.acc_clear(acc_clear),
        .amp_in(amp_in),.data_in(data_in),.found_mask_in(found_mask_in),.predicate_mode(predicate_mode),
        .threshold_a(threshold_a),.threshold_b(threshold_b),.data_count(data_count),.enum_enable(enum_enable),
        .amp_out(amp_out),.row_out_valid(row_out_valid),.row_out_indices(row_out_indices),
        .global_sum(global_sum),.two_mean(two_mean),.sum_commit(sum_commit),.sat_event(sat_event));
    reg [M-1:0] in_valid=0;
    reg [M*9-1:0] in_rows=0;
    reg [M*W-1:0] in_amp=0;
    wire [M-1:0] out_valid;
    wire [M*9-1:0] out_rows;
    wire [M*32*46-1:0] out_sq;
    wire [M*51-1:0] out_row_sum;
    grover_born_square_parallel #(.SQUARE_ENGINES(M)) u_squares(.*);
    integer memory_rows=0,square_rows=0,pass1_rows=0,diffusion_rows=0,init_rows=0;
    integer phase=0,slots_to_test,slot,row,base,p,l,actual,data,expected,hit,oracle_amp;
    reg signed [63:0] total,partial,square,expected_mean;
    // Check every returned amplitude and square independently of engine/bank.
    always @(negedge clk) if(rstn) begin
        if(sat_event) saturation_events=saturation_events+1;
        for(integer p=0;p<E;p=p+1) if(row_out_valid[p]) begin
            for(integer l=0;l<32;l=l+1) begin
                row=row_out_indices[p*9+:9];actual=$signed(amp_out[(p*32+l)*23+:23]);
                data=((row*32+l)%47)-23;
                case(predicate_mode)
                    0:hit=data<threshold_a;
                    1:hit=data>threshold_a;
                    2:hit=data==threshold_a;
                    3:hit=threshold_a<data && data<threshold_b;
                endcase
                hit=hit && (row*32+l<data_count) && !((row*32+l)%19==0);
                oracle_amp=hit ? -sample(K-1,row,l) : sample(K-1,row,l);
                if(phase==1) expected=32768;
                else if(phase==2) expected=oracle_amp;
                else begin
                    expected=expected_mean-oracle_amp;
                    if(expected>4194303) expected=4194303;
                    if(expected< -4194303) expected= -4194303;
                end
                if(actual!==expected) $fatal(1,"arithmetic E%0d row%0d lane%0d phase%0d got%0d expected%0d",E,row,l,phase,actual,expected);
            end
            if(phase==1)init_rows=init_rows+1;
            else if(phase==2)pass1_rows=pass1_rows+1;
            else diffusion_rows=diffusion_rows+1;
        end
        for(integer p=0;p<M;p=p+1) if(out_valid[p]) begin
            partial=0;
            for(integer l=0;l<32;l=l+1) begin
                square=sample(K-1,out_rows[p*9+:9],l);
                square=square*square;
                if(out_sq[(p*32+l)*46+:46]!==46'(square)) $fatal(1,"squarer mismatch");
                partial=partial+square;
            end
            if(out_row_sum[p*51+:51]!==51'(partial)) $fatal(1,"square reduction mismatch");
            square_rows=square_rows+1;
        end
    end
    task automatic drive_rows(input integer operation);
        begin
            op=operation;
            for(integer b=0;b<512;b=b+E) begin
                @(posedge clk);#1;
                row_valid=0;
                for(integer p=0;p<E;p=p+1) if(b+p<512) begin
                    row_valid[p]=1;row_indices[p*9+:9]=b+p;
                    for(integer l=0;l<32;l=l+1) begin
                        data_in[(p*32+l)*16+:16]=16'((((b+p)*32+l)%47)-23);
                        found_mask_in[p*32+l]=(((b+p)*32+l)%19==0);
                        if(operation==3) begin
                            data=(((b+p)*32+l)%47)-23;
                            case(predicate_mode)
                                0:hit=data<threshold_a;
                                1:hit=data>threshold_a;
                                2:hit=data==threshold_a;
                                3:hit=threshold_a<data && data<threshold_b;
                            endcase
                            hit=hit && ((b+p)*32+l<data_count) && !found_mask_in[p*32+l];
                            amp_in[(p*32+l)*23+:23]=23'(hit ? -sample(K-1,b+p,l):sample(K-1,b+p,l));
                        end else amp_in[(p*32+l)*23+:23]=23'(sample(K-1,b+p,l));
                    end
                end
            end
            @(posedge clk);#1;row_valid=0;
            repeat(10) @(posedge clk);#1;
        end
    endtask
    initial begin
        plusarg_result=$value$plusargs("EXTREME=%d",extreme);
        repeat(3) @(posedge clk);#1;rstn=1;
        // Fill and check all physical slots, including slot 9 and rows 510/511.
        for(integer s=0;s<K;s=s+1) begin
            for(integer b=0;b<512;b=b+E) begin
                @(negedge clk);wr_slot=s;wr_en=0;
                for(integer p=0;p<E;p=p+1) if(b+p<512) begin
                    wr_en[p]=1;wr_rows[p*9+:9]=b+p;
                    for(integer l=0;l<32;l=l+1) wr_data[(p*32+l)*23+:23]=23'(sample(s,b+p,l));
                end
            end
            @(negedge clk);wr_en=0;
        end
        for(integer s=0;s<K;s=s+1) begin
            for(integer b=0;b<512;b=b+RP) begin
                @(negedge clk);rd_slot=s;rd_en=0;
                for(integer p=0;p<RP;p=p+1) if(b+p<512) begin rd_en[p]=1;rd_rows[p*9+:9]=b+p;end
                @(posedge clk);#1;
                if(rd_valid!==rd_en) $fatal(1,"memory response valid mismatch");
                for(integer p=0;p<RP;p=p+1) if(rd_valid[p]) begin
                    for(integer l=0;l<32;l=l+1)
                        if($signed(rd_data[(p*32+l)*23+:23])!==sample(s,b+p,l)) $fatal(1,"bank address alias s%0d row%0d lane%0d",s,b+p,l);
                    memory_rows=memory_rows+1;
                end
            end
        end
        @(negedge clk);rd_en=0;
        for(integer b=0;b<512;b=b+M) begin
            @(posedge clk);#1;in_valid=0;
            for(integer p=0;p<M;p=p+1) if(b+p<512) begin
                in_valid[p]=1;in_rows[p*9+:9]=b+p;
                for(integer l=0;l<32;l=l+1) in_amp[(p*32+l)*23+:23]=23'(sample(K-1,b+p,l));
            end
        end
        @(posedge clk);#1;in_valid=0;repeat(10) @(posedge clk);#1;
        phase=1;drive_rows(0);
        for(integer mode=0;mode<4;mode=mode+1) begin
            predicate_mode=mode;phase=2;total=0;
            for(integer r=0;r<512;r=r+1) for(integer l=0;l<32;l=l+1) begin
                data=((r*32+l)%47)-23;
                case(mode)
                    0:hit=data<threshold_a;1:hit=data>threshold_a;2:hit=data==threshold_a;
                    3:hit=threshold_a<data && data<threshold_b;
                endcase
                hit=hit && r*32+l<data_count && !((r*32+l)%19==0);
                total=total+(hit ? -sample(K-1,r,l):sample(K-1,r,l));
            end
            op=1;acc_clear=1;@(posedge clk);#1;acc_clear=0;
            drive_rows(1);
            if(global_sum!==39'(total)) $fatal(1,"global reduction mismatch E%0d got%0d expected%0d",E,global_sum,total);
            expected_mean=total>>>13;
            if((total & 8191)>4096 || ((total &8191)==4096 && expected_mean[0]))expected_mean=expected_mean+1;
            op=2;@(posedge clk);#1;
            if(two_mean!==25'(expected_mean)) $fatal(1,"mean mismatch");
            phase=3;drive_rows(3);
        end
        if(memory_rows!=K*512 || square_rows!=512 || init_rows!=512 || pass1_rows!=2048 || diffusion_rows!=2048)
            $fatal(1,"incomplete row coverage");
        if(extreme && saturation_events==0) $fatal(1,"saturation not exercised");
        $display("SUMMARY parallel capacity=%0d iteration_engines=%0d square_engines=%0d memory_rows=%0d square_rows=%0d pass1_rows=%0d diffusion_rows=%0d errors=0",K,E,M,memory_rows,square_rows,pass1_rows,diffusion_rows);
        $finish;
    end
endmodule
