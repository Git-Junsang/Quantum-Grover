`timescale 1ns/1ps
`include "grover_param.vh"

// Parameter-sized checkpoint amplitude store. Consecutive iteration rows and
// consecutive measurement rows each occupy different banks, even for a count
// that is not a power of two. Padding at the end of the 512-row state consumes
// no logical rows. A slot uses ceil(512/BANKS) addresses in every bank; this is
// essential to prevent the last partial group from aliasing the next slot.
module grover_ckpt_mem_parallel #(
    parameter integer CHECKPOINT_CAPACITY=3,
    parameter integer READ_PORTS=4,WRITE_PORTS=4,
    parameter integer WORD_W=`GP_P*`GP_AMP_W,
    parameter integer SLOT_W=(CHECKPOINT_CAPACITY<2)?1:$clog2(CHECKPOINT_CAPACITY)
) (
    input wire clk,rstn,
    input wire [SLOT_W-1:0] rd_slot,wr_slot,
    input wire [READ_PORTS-1:0] rd_en,
    input wire [READ_PORTS*`GP_ROW_W-1:0] rd_rows,
    output wire [READ_PORTS*WORD_W-1:0] rd_data,
    output reg [READ_PORTS-1:0] rd_valid,
    input wire [WRITE_PORTS-1:0] wr_en,
    input wire [WRITE_PORTS*`GP_ROW_W-1:0] wr_rows,
    input wire [WRITE_PORTS*WORD_W-1:0] wr_data
);
    localparam integer BANKS=(READ_PORTS>WRITE_PORTS)?READ_PORTS:WRITE_PORTS;
    localparam integer BANK_ROWS=(`GP_ROWS+BANKS-1)/BANKS;
    localparam integer BW=(BANKS<2)?1:$clog2(BANKS);
    wire [WORD_W-1:0] bank_q[0:BANKS-1];
    reg [BW-1:0] read_bank[0:READ_PORTS-1];
    initial begin
        if(CHECKPOINT_CAPACITY<1 || CHECKPOINT_CAPACITY>10 ||
            READ_PORTS<1 || READ_PORTS>16 || WRITE_PORTS<1 || WRITE_PORTS>16)
            $fatal(1,"parallel memory requires capacity 1..10 and ports 1..16");
        if(SLOT_W<((CHECKPOINT_CAPACITY<2)?1:$clog2(CHECKPOINT_CAPACITY)))
            $fatal(1,"slot address cannot represent capacity");
    end
    genvar bank,port;
    generate
        for(bank=0;bank<BANKS;bank=bank+1) begin : g_bank
            (* ram_style="block" *) reg [WORD_W-1:0] mem[0:CHECKPOINT_CAPACITY*BANK_ROWS-1];
            reg [WORD_W-1:0] q;
            always @(posedge clk) begin
                for(integer p=0;p<READ_PORTS;p=p+1)
                    if(rd_en[p] && rd_slot<CHECKPOINT_CAPACITY &&
                       rd_rows[p*`GP_ROW_W+:`GP_ROW_W]%BANKS==bank)
                        q<=mem[rd_slot*BANK_ROWS+rd_rows[p*`GP_ROW_W+:`GP_ROW_W]/BANKS];
                for(integer p=0;p<WRITE_PORTS;p=p+1)
                    if(wr_en[p] && wr_slot<CHECKPOINT_CAPACITY &&
                       wr_rows[p*`GP_ROW_W+:`GP_ROW_W]%BANKS==bank)
                        mem[wr_slot*BANK_ROWS+wr_rows[p*`GP_ROW_W+:`GP_ROW_W]/BANKS]
                            <=wr_data[p*WORD_W+:WORD_W];
            end
            assign bank_q[bank]=q;
        end
        for(port=0;port<READ_PORTS;port=port+1) begin : g_port
            assign rd_data[port*WORD_W+:WORD_W]=bank_q[read_bank[port]];
            always @(posedge clk) if(rd_en[port])
                read_bank[port]<=rd_rows[port*`GP_ROW_W+:`GP_ROW_W]%BANKS;
        end
    endgenerate
    always @(posedge clk) begin
        if(!rstn) rd_valid<=0;
        else rd_valid<=rd_en;
    end
`ifndef SYNTHESIS
    always @(posedge clk) if(rstn) begin
        if((|rd_en && rd_slot>=CHECKPOINT_CAPACITY) || (|wr_en && wr_slot>=CHECKPOINT_CAPACITY))
            $fatal(1,"parallel memory slot out of range");
        for(integer a=0;a<READ_PORTS;a=a+1)
            for(integer b=a+1;b<READ_PORTS;b=b+1)
                if(rd_en[a] && rd_en[b] &&
                    rd_rows[a*`GP_ROW_W+:`GP_ROW_W]%BANKS==rd_rows[b*`GP_ROW_W+:`GP_ROW_W]%BANKS)
                    $fatal(1,"parallel memory read bank conflict");
        for(integer a=0;a<WRITE_PORTS;a=a+1)
            for(integer b=a+1;b<WRITE_PORTS;b=b+1)
                if(wr_en[a] && wr_en[b] &&
                    wr_rows[a*`GP_ROW_W+:`GP_ROW_W]%BANKS==wr_rows[b*`GP_ROW_W+:`GP_ROW_W]%BANKS)
                    $fatal(1,"parallel memory write bank conflict");
    end
`endif
endmodule

// The measurement parallelism is the number of complete 32-lane row squarers.
// Each instance retains the existing square/reduction pipeline and row tag.
// This port is independent of iteration parallelism: memory arbitration will
// select measurement requests while the measurement engine owns the state.
module grover_born_square_parallel #(
    parameter integer SQUARE_ENGINES=2
) (
    input wire clk,rstn,
    input wire [SQUARE_ENGINES-1:0] in_valid,
    input wire [SQUARE_ENGINES*`GP_ROW_W-1:0] in_rows,
    input wire [SQUARE_ENGINES*`GP_P*`GP_AMP_W-1:0] in_amp,
    output wire [SQUARE_ENGINES-1:0] out_valid,
    output wire [SQUARE_ENGINES*`GP_ROW_W-1:0] out_rows,
    output wire [SQUARE_ENGINES*`GP_P*`GP_SQUARE_W-1:0] out_sq,
    output wire [SQUARE_ENGINES*`GP_ROW_SUM_W-1:0] out_row_sum
);
    initial if(SQUARE_ENGINES<1 || SQUARE_ENGINES>4)
        $fatal(1,"SQUARE_ENGINES must be 1..4");
    genvar g;
    generate for(g=0;g<SQUARE_ENGINES;g=g+1) begin : g_square
        grover_born_square32 u_square (
            .clk(clk),.rstn(rstn),.in_valid(in_valid[g]),
            .in_row(in_rows[g*`GP_ROW_W+:`GP_ROW_W]),
            .in_amp(in_amp[g*`GP_P*`GP_AMP_W+:`GP_P*`GP_AMP_W]),
            .out_valid(out_valid[g]),.out_row(out_rows[g*`GP_ROW_W+:`GP_ROW_W]),
            .out_sq(out_sq[g*`GP_P*`GP_SQUARE_W+:`GP_P*`GP_SQUARE_W]),
            .out_row_sum(out_row_sum[g*`GP_ROW_SUM_W+:`GP_ROW_SUM_W])
        );
    end endgenerate
endmodule

// Iteration arithmetic with one independent 32-lane datapath per engine.
// Row indices are explicit rather than {group,phase}, allowing every count
// from 1 to 16. The last group can mask unused rows without wrapping to row 0.
// All engines contribute to one signed global sum and one rounded two_mean.
module grover_iter_datapath_parallel #(
    parameter integer INTRA_ENGINES=4
) (
    input wire clk,rstn,
    input wire [1:0] op,
    input wire [INTRA_ENGINES-1:0] row_valid,
    input wire [INTRA_ENGINES*`GP_ROW_W-1:0] row_indices,
    input wire acc_clear,
    input wire [INTRA_ENGINES*`GP_P*`GP_AMP_W-1:0] amp_in,
    input wire [INTRA_ENGINES*`GP_P*`GP_DATA_W-1:0] data_in,
    input wire [INTRA_ENGINES*`GP_P-1:0] found_mask_in,
    input wire [1:0] predicate_mode,
    input wire signed [`GP_DATA_W-1:0] threshold_a,threshold_b,
    input wire [`GP_DATA_COUNT_W-1:0] data_count,
    input wire enum_enable,
    output wire [INTRA_ENGINES*`GP_P*`GP_AMP_W-1:0] amp_out,
    output wire [INTRA_ENGINES-1:0] row_out_valid,
    output wire [INTRA_ENGINES*`GP_ROW_W-1:0] row_out_indices,
    output wire signed [`GP_ACC_W-1:0] global_sum,
    output reg signed [`GP_TWO_MEAN_W-1:0] two_mean,
    output wire sum_commit,sat_event
);
    localparam integer E=INTRA_ENGINES,P=`GP_P,AW=`GP_AMP_W,DW=`GP_DATA_W;
    localparam integer LEAVES=1<<$clog2(E);
    localparam [1:0] INIT=0,PASS1=1,MEAN=2,PASS2=3;
    wire signed [`GP_ACC_W-1:0] totals[0:E-1];
    wire signed [`GP_ACC_W-1:0] sum_tree[1:2*LEAVES-1] /* verilator split_var */;
    wire [E-1:0] committed,saturated;
    wire signed [`GP_TWO_MEAN_W-1:0] mean_comb;
    grover_two_mean_calc u_mean(.total(global_sum),.two_mean(mean_comb));
    always @(posedge clk) begin
        if(!rstn) two_mean<=0;
        else if(op==MEAN) two_mean<=mean_comb;
    end
    initial if(E<1 || E>16) $fatal(1,"INTRA_ENGINES must be 1..16");
    assign global_sum=sum_tree[1];
    assign sum_commit=|committed;
    assign sat_event=|saturated;
    genvar engine,lane,node;
    generate
        for(engine=0;engine<E;engine=engine+1) begin : g_engine
            wire [P-1:0] hits,sat;
            reg [P-1:0] hit_q;
            reg [P*AW-1:0] amp_q,oracle_q,out_q;
            wire [P*AW-1:0] oracle_amp,diffusion_amp;
            reg [8:0] row_q,oracle_row_q,out_row;
            reg pass1_q,oracle_valid_q,out_valid,sat_q;
            wire signed [`GP_PARTIAL_SUM_W-1:0] partial;
            wire partial_valid;
            for(lane=0;lane<P;lane=lane+1) begin : g_lane
                wire raw_hit;
                grover_predicate u_predicate (
                    .mode(predicate_mode),.value(data_in[(engine*P+lane)*DW+:DW]),
                    .threshold_a(threshold_a),.threshold_b(threshold_b),
                    .index({row_indices[engine*9+:9],5'(lane)}),.data_count(data_count),.hit(raw_hit)
                );
                assign hits[lane]=raw_hit && !(enum_enable && found_mask_in[engine*P+lane]);
                grover_oracle_flip u_oracle (
                    .amp_in(amp_q[lane*AW+:AW]),.hit(hit_q[lane]),.amp_out(oracle_amp[lane*AW+:AW])
                );
                grover_diffusion_sat u_diffusion (
                    .two_mean(two_mean),.oracle_amp(amp_in[(engine*P+lane)*AW+:AW]),
                    .amp_out(diffusion_amp[lane*AW+:AW]),.sat(sat[lane])
                );
            end
            grover_adder_tree u_partial (.clk(clk),.rstn(rstn),.en(oracle_valid_q),
                .din(oracle_q),.partial(partial),.valid_out(partial_valid));
            grover_sum_accum u_accum (.clk(clk),.rstn(rstn),.clear(acc_clear),
                .en(partial_valid),.partial(partial),.total(totals[engine]));
            assign committed[engine]=partial_valid;
            assign saturated[engine]=sat_q;
            assign amp_out[engine*P*AW+:P*AW]=out_q;
            assign row_out_valid[engine]=out_valid;
            assign row_out_indices[engine*9+:9]=out_row;
            always @(posedge clk) begin
                if(!rstn) begin
                    hit_q<=0;amp_q<=0;oracle_q<=0;out_q<=0;row_q<=0;oracle_row_q<=0;out_row<=0;
                    pass1_q<=0;oracle_valid_q<=0;out_valid<=0;sat_q<=0;
                end else begin
                    pass1_q<=row_valid[engine] && op==PASS1;
                    hit_q<=hits;amp_q<=amp_in[engine*P*AW+:P*AW];row_q<=row_indices[engine*9+:9];
                    oracle_valid_q<=pass1_q;oracle_q<=oracle_amp;oracle_row_q<=row_q;
                    out_valid<=0;sat_q<=row_valid[engine] && op==PASS2 && |sat;
                    if(oracle_valid_q) begin out_q<=oracle_q;out_row<=oracle_row_q;out_valid<=1;end
                    else if(row_valid[engine] && op==INIT) begin
                        for(integer l=0;l<P;l=l+1) out_q[l*AW+:AW]<=`GP_INIT_AMP_RAW;
                        out_row<=row_indices[engine*9+:9];out_valid<=1;
                    end else if(row_valid[engine] && op==PASS2) begin
                        out_q<=diffusion_amp;out_row<=row_indices[engine*9+:9];out_valid<=1;
                    end
                end
            end
        end
        for(engine=0;engine<LEAVES;engine=engine+1) begin : g_sum_leaf
            if(engine<E) assign sum_tree[LEAVES+engine]=totals[engine];
            else assign sum_tree[LEAVES+engine]=0;
        end
        for(node=1;node<LEAVES;node=node+1) begin : g_sum_node
            assign sum_tree[node]=sum_tree[2*node]+sum_tree[2*node+1];
        end
    endgenerate
endmodule
