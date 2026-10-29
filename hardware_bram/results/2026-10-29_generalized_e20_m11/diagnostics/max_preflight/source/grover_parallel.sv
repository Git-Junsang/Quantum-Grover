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
            READ_PORTS<1 || READ_PORTS>`GP_MAX_INTRA_ENGINES ||
            WRITE_PORTS<1 || WRITE_PORTS>`GP_MAX_INTRA_ENGINES)
            $fatal(1,"parallel memory requires capacity 1..10 and ports 1..20");
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

// Expanded measurement frontend. Arithmetic precision and the ordered Born
// sampling procedure are the same as the legacy sampler: exact row weights,
// 16 global group CDFs, a scan within one 32-row group, then a 32-lane scan.
// Only BUILD bandwidth is parameterized. This simulation-first implementation
// deliberately retains every row weight; resource-specific packing is a later
// step once a feasible checkpoint/lookahead/engine configuration is selected.
module grover_born_sampler_parallel #(
    parameter integer SQUARE_ENGINES=5
) (
    input wire clk,rstn,start,
    input wire [31:0] rnd,
    output wire rnd_draw,
    output reg [SQUARE_ENGINES-1:0] rd_en,
    output reg [SQUARE_ENGINES*`GP_ROW_W-1:0] rd_rows,
    input wire [SQUARE_ENGINES*`GP_P*`GP_AMP_W-1:0] amp_data,
    input wire [SQUARE_ENGINES-1:0] amp_valid,
    output wire busy,
    output reg done,zero_weight_error,
    output reg [`GP_INDEX_W-1:0] candidate,
    output reg [`GP_TOTAL_WEIGHT_W-1:0] total_weight,threshold,
    output reg [`GP_ROW_W-1:0] selected_row
);
    localparam integer M=SQUARE_ENGINES,TW=`GP_TOTAL_WEIGHT_W,RSW=`GP_ROW_SUM_W;
    localparam integer SQW=`GP_SQUARE_W,ROWS=`GP_ROWS,BANK_ROWS=(ROWS+M-1)/M;
    localparam [3:0] IDLE=0,BUILD=1,CHECK_WEIGHT=2,RND_HI=3,RND_LO=4,
        RND_MAP=5,RND_CHECK=6,GROUP_SCAN=7,ROW_SCAN=8,LANE_REQ=9,
        LANE_WAIT=10,LANE_SCAN=11,FINISH=12,ZERO_WEIGHT=13;
    reg [3:0] state;
    reg [9:0] issued,row_issue,row_limit;
    reg [M*9-1:0] tags1,tags2;
    wire [M-1:0] square_in_valid=amp_valid & {M{state==BUILD || state==LANE_WAIT}};
    wire [M-1:0] square_valid;
    wire [M*9-1:0] square_rows;
    wire [M*32*SQW-1:0] squares;
    wire [M*RSW-1:0] row_sums;
    grover_born_square_parallel #(.SQUARE_ENGINES(M)) u_squares (
        .clk(clk),.rstn(rstn),.in_valid(square_in_valid),.in_rows(tags2),.in_amp(amp_data),
        .out_valid(square_valid),.out_rows(square_rows),.out_sq(squares),.out_row_sum(row_sums)
    );
    initial if(M<1 || M>`GP_MAX_SQUARE_ENGINES)
        $fatal(1,"parallel sampler requires 1..11 square engines");
    assign busy=(state!=IDLE);
    assign rnd_draw=(state==RND_HI || state==RND_LO);

    // Requests and response tags retain the physical kernel's two-cycle read
    // contract. The final incomplete batch is masked before memory access.
    always @* begin
        rd_en=0;rd_rows=0;
        for(integer p=0;p<M;p=p+1) begin
            if(state==BUILD && integer'(issued)+p<ROWS) begin
                rd_en[p]=1;rd_rows[p*9+:9]=9'(integer'(issued)+p);
            end
        end
        if(state==LANE_REQ) begin rd_en[0]=1;rd_rows[0+:9]=selected_row;end
    end
    always @(posedge clk) begin
        if(!rstn) begin tags1<=0;tags2<=0;end
        else begin tags1<=rd_rows;tags2<=tags1;end
    end

    reg [TW-1:0] build_total;
    wire [TW-1:0] prefix[0:M] /* verilator split_var */;
    assign prefix[0]=build_total;
    genvar p;
    generate for(p=0;p<M;p=p+1) begin : g_prefix
        assign prefix[p+1]=prefix[p]+(square_valid[p] ?
            {{(TW-RSW){1'b0}},row_sums[p*RSW+:RSW]} : {TW{1'b0}});
    end endgenerate
    reg [TW-1:0] group_cdf[0:15];
    reg [3:0] group_index;
    reg [TW-1:0] group_previous,row_cumulative,local_threshold;

    // Lane p owns BUILD rows with row modulo M equal to p. Each bank therefore
    // has one write port even for odd M. All banks provide synchronous reads;
    // the delayed bank selector and row tag identify the single scan response.
    wire row_read=(state==ROW_SCAN && row_issue<row_limit);
    wire [M*RSW-1:0] bank_weights;
    reg [$clog2(M+1)-1:0] read_bank;
    reg [8:0] read_row;
    reg read_valid;
    generate for(p=0;p<M;p=p+1) begin : g_row_weight
        (* ram_style="block" *) reg [RSW-1:0] mem[0:BANK_ROWS-1];
        reg [RSW-1:0] q;
        always @(posedge clk) begin
            if(state==BUILD && square_valid[p])
                mem[integer'(square_rows[p*9+:9])/M]<=row_sums[p*RSW+:RSW];
            if(row_read) q<=mem[integer'(row_issue)/M];
        end
        assign bank_weights[p*RSW+:RSW]=q;
    end endgenerate
    always @(posedge clk) begin
        if(!rstn) begin read_bank<=0;read_row<=0;read_valid<=0;end
        else begin
            read_valid<=row_read;
            if(row_read) begin
                read_bank<=$clog2(M+1)'(integer'(row_issue)%M);
                read_row<=row_issue[8:0];
            end
        end
    end
    wire [RSW-1:0] scan_weight=bank_weights[integer'(read_bank)*RSW+:RSW];
    wire [TW:0] row_next={1'b0,row_cumulative}+{{(TW+1-RSW){1'b0}},scan_weight};
    reg [32*SQW-1:0] lane_squares;
    reg [4:0] lane_index;
    reg [TW-1:0] lane_cumulative;
    wire [SQW-1:0] lane_weight=lane_squares[integer'(lane_index)*SQW+:SQW];
    wire [TW:0] lane_next={1'b0,lane_cumulative}+{{(TW+1-SQW){1'b0}},lane_weight};

    // Reuse the established registered rejection mapper and its HI then LO
    // draw protocol. Rejections consume a fresh pair; weights zero and one
    // consume no random draw. BUILD width cannot alter the PRNG trajectory.
    reg [31:0] random_hi,random_lo;
    wire [5:0] reject_bits;
    wire [TW-1:0] reject_candidate;
    wire reject_accept,reject_one,reject_zero;
    grover_born_reject64 u_reject (
        .clk(clk),.rstn(rstn),.load_weight(state==CHECK_WEIGHT && total_weight>1),
        .map_candidate(state==RND_MAP),.total_weight(total_weight),.rnd64({random_hi,random_lo}),
        .k_bits(reject_bits),.candidate(reject_candidate),.accept(reject_accept),
        .direct_one(reject_one),.zero_weight(reject_zero)
    );

    always @(posedge clk) begin
        if(!rstn) begin
            state<=IDLE;issued<=0;row_issue<=0;row_limit<=0;done<=0;zero_weight_error<=0;
            candidate<=0;total_weight<=0;threshold<=0;selected_row<=0;build_total<=0;
            group_index<=0;group_previous<=0;row_cumulative<=0;local_threshold<=0;
            random_hi<=0;random_lo<=0;lane_squares<=0;lane_index<=0;lane_cumulative<=0;
        end else begin
            done<=0;
            case(state)
                IDLE: if(start) begin
                    issued<=0;build_total<=0;zero_weight_error<=0;candidate<=0;
                    total_weight<=0;threshold<=0;selected_row<=0;state<=BUILD;
                end
                BUILD: begin
                    if(|rd_en) issued<=issued+10'(M);
                    if(|square_valid) build_total<=prefix[M];
                    for(integer s=0;s<M;s=s+1) if(square_valid[s]) begin
                        // A 32-row boundary may occur on any square lane.
                        if(square_rows[s*9+:5]==5'd31)
                            group_cdf[square_rows[s*9+5+:4]]<=prefix[s+1];
                        if(square_rows[s*9+:9]==9'd511) begin
                            total_weight<=prefix[M];state<=CHECK_WEIGHT;
                        end
                    end
                end
                CHECK_WEIGHT: begin
                    if(total_weight==0) state<=ZERO_WEIGHT;
                    else if(total_weight==1) begin
                        threshold<=0;group_index<=0;group_previous<=0;state<=GROUP_SCAN;
                    end else state<=RND_HI;
                end
                RND_HI: begin random_hi<=rnd;state<=RND_LO;end
                RND_LO: begin random_lo<=rnd;state<=RND_MAP;end
                RND_MAP: state<=RND_CHECK;
                RND_CHECK: begin
                    if(reject_accept) begin
                        threshold<=reject_candidate;group_index<=0;group_previous<=0;state<=GROUP_SCAN;
                    end else state<=RND_HI;
                end
                GROUP_SCAN: begin
                    if(group_cdf[group_index]>threshold) begin
                        row_issue<={1'b0,group_index,5'b0};
                        row_limit<={1'b0,group_index,5'b0}+10'd32;
                        row_cumulative<=group_previous;state<=ROW_SCAN;
                    end else begin group_previous<=group_cdf[group_index];group_index<=group_index+1'b1;end
                end
                ROW_SCAN: begin
                    if(row_read) row_issue<=row_issue+1'b1;
                    if(read_valid) begin
                        if(row_next>{1'b0,threshold}) begin
                            selected_row<=read_row;local_threshold<=threshold-row_cumulative;state<=LANE_REQ;
                        end else row_cumulative<=row_next[TW-1:0];
                    end
                end
                LANE_REQ: state<=LANE_WAIT;
                LANE_WAIT: if(square_valid[0]) begin
                    lane_squares<=squares[0+:32*SQW];lane_index<=0;lane_cumulative<=0;state<=LANE_SCAN;
                end
                LANE_SCAN: begin
                    if(lane_next>{1'b0,local_threshold}) begin
                        candidate<={selected_row,lane_index};state<=FINISH;
                    end else begin lane_cumulative<=lane_next[TW-1:0];lane_index<=lane_index+1'b1;end
                end
                FINISH: begin done<=1;state<=IDLE;end
                ZERO_WEIGHT: begin zero_weight_error<=1;done<=1;state<=IDLE;end
                default: state<=IDLE;
            endcase
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk) if(rstn) begin
        for(integer s=0;s<M;s=s+1)
            if(state==BUILD && square_valid[s] && integer'(square_rows[s*9+:9])%M!=s)
                $fatal(1,"measurement response row does not belong to its square bank");
        if(state==GROUP_SCAN && group_index==15 && group_cdf[15]<=threshold)
            $fatal(1,"measurement group CDF does not cover threshold");
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
    initial if(SQUARE_ENGINES<1 || SQUARE_ENGINES>`GP_MAX_SQUARE_ENGINES)
        $fatal(1,"SQUARE_ENGINES must be 1..11");
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
    initial if(E<1 || E>`GP_MAX_INTRA_ENGINES) $fatal(1,"INTRA_ENGINES must be 1..20");
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

// The controller counts issued groups, completed writes and completed sums
// independently. It never advances to MEAN until both PASS1 drains complete.
// Explicit row masks prevent a partial final group from touching row zero.
module grover_ctrl_fsm_parallel #(
    parameter integer INTRA_ENGINES=4
) (
    input wire clk,rstn,iter_start,iter_do_init,
    input wire [15:0] iter_count,
    input wire dp_out_valid,dp_sum_commit,
    output wire iter_busy,
    output reg iter_done,
    output wire [3:0] state,
    output wire [INTRA_ENGINES-1:0] memory_read,
    output wire [INTRA_ENGINES*`GP_ROW_W-1:0] memory_rows,
    output wire [1:0] dp_op,
    output wire [INTRA_ENGINES-1:0] dp_valid,
    output wire [INTRA_ENGINES*`GP_ROW_W-1:0] dp_rows,
    output wire acc_clear,
    output reg pass_tick
);
    localparam integer E=INTRA_ENGINES,GROUPS=(`GP_ROWS+E-1)/E;
    localparam [3:0] IDLE=0,INIT=1,PASS1=2,MEAN=3,PASS2=4;
    reg [3:0] st;
    integer issued,completed,summed;
    reg [15:0] remaining;
    reg writes_done,sums_done;
    wire issue=(st==INIT || st==PASS1 || st==PASS2) && issued<GROUPS;
    wire [E-1:0] issue_mask;
    wire [E*9-1:0] issue_rows;
    reg [E-1:0] valid1,valid2;
    reg [E*9-1:0] rows1,rows2;
    reg [1:0] operation1,operation2;
    wire [1:0] operation=(st==INIT)?0:(st==PASS1)?1:3;
    genvar e;
    generate for(e=0;e<E;e=e+1) begin : g_row
        assign issue_mask[e]=issue && issued*E+e<`GP_ROWS;
        assign issue_rows[e*9+:9]=9'(issued*E+e);
    end endgenerate
    assign memory_read=(st==PASS1 || st==PASS2)?issue_mask:0;
    assign memory_rows=issue_rows;
    assign dp_valid=(st==INIT)?issue_mask:((st==PASS1 || st==PASS2)?valid2:0);
    assign dp_rows=(st==INIT)?issue_rows:rows2;
    assign dp_op=(st==MEAN)?2:(st==INIT)?0:operation2;
    assign acc_clear=(st==PASS1 && issue && issued==0);
    assign state=st;
    assign iter_busy=(st!=IDLE);
    wire last_write=dp_out_valid && completed==GROUPS-1;
    wire last_sum=dp_sum_commit && summed==GROUPS-1;
    always @(posedge clk) begin
        if(!rstn) begin
            st<=IDLE;issued<=0;completed<=0;summed<=0;remaining<=0;
            writes_done<=0;sums_done<=0;valid1<=0;valid2<=0;rows1<=0;rows2<=0;
            operation1<=0;operation2<=0;iter_done<=0;pass_tick<=0;
        end else begin
            iter_done<=0;pass_tick<=0;
            valid1<=issue_mask;valid2<=valid1;rows1<=issue_rows;rows2<=rows1;
            operation1<=operation;operation2<=operation1;
            if(issue) issued<=issued+1;
            if(dp_out_valid) completed<=completed+1;
            if(dp_sum_commit) summed<=summed+1;
            case(st)
                IDLE: begin
                    issued<=0;completed<=0;summed<=0;writes_done<=0;sums_done<=0;
                    if(iter_start) begin
                        remaining<=iter_count;
                        if(iter_do_init) st<=INIT;
                        else if(iter_count!=0) st<=PASS1;
                        else iter_done<=1;
                    end
                end
                INIT: if(last_write) begin
                    issued<=0;completed<=0;summed<=0;
                    if(remaining!=0) st<=PASS1;
                    else begin st<=IDLE;iter_done<=1;end
                end
                PASS1: begin
                    if(last_write) writes_done<=1;
                    if(last_sum) sums_done<=1;
                    if((writes_done || last_write) && (sums_done || last_sum)) begin
                        issued<=0;completed<=0;summed<=0;writes_done<=0;sums_done<=0;
                        pass_tick<=1;st<=MEAN;
                    end
                end
                MEAN: begin issued<=0;completed<=0;summed<=0;st<=PASS2;end
                PASS2: if(last_write) begin
                    issued<=0;completed<=0;summed<=0;pass_tick<=1;
                    if(remaining==1) begin remaining<=0;st<=IDLE;iter_done<=1;end
                    else begin remaining<=remaining-1'b1;st<=PASS1;end
                end
                default: begin st<=IDLE;iter_done<=1;end
            endcase
        end
    end
endmodule

// Main-IP-facing physical kernel. Dataset/found-mask replicas provide genuine
// synchronous Oracle reads for arbitrary E. This first simulation-oriented
// implementation favors parameter correctness over minimum BRAM replication.
// Amplitude storage is banked across rows and slots; all read clients retain
// the existing two-cycle checkpoint-memory contract.
module grover_inner_parallel #(
    parameter integer CHECKPOINT_CAPACITY=3,INTRA_ENGINES=4,
    parameter integer SQUARE_ENGINES=2,
    parameter integer SLOT_W=(CHECKPOINT_CAPACITY<2)?1:$clog2(CHECKPOINT_CAPACITY)
) (
    input wire clk,rstn,iter_start,iter_do_init,
    input wire [15:0] iter_count,
    input wire [SLOT_W-1:0] src_slot,dst_slot,
    input wire bridge,
    output wire iter_busy,iter_done,
    output wire [3:0] state,
    output wire pass_tick,
    output wire signed [`GP_ACC_W-1:0] global_sum,
    output wire signed [`GP_TWO_MEAN_W-1:0] two_mean,
    output wire sat_event,
    input wire [1:0] predicate_mode,
    input wire signed [`GP_DATA_W-1:0] threshold_a,threshold_b,
    input wire [`GP_DATA_COUNT_W-1:0] data_count,
    input wire enum_enable,
    input wire [`GP_INDEX_W-1:0] data_wr_index,
    input wire data_wr_en,
    input wire signed [`GP_DATA_W-1:0] data_wr_value,
    input wire [`GP_INDEX_W-1:0] verify_index,
    output wire signed [`GP_DATA_W-1:0] verify_value,
    output wire verify_found,
    input wire mask_clear_start,mask_set_start,
    input wire [`GP_INDEX_W-1:0] mask_set_index,
    output wire mask_maint_busy,mask_clear_done,mask_set_done,
    input wire meas_busy,
    input wire [SLOT_W-1:0] meas_slot,
    input wire meas_single_en,
    input wire [8:0] meas_single_row,
    output wire [`GP_P*`GP_AMP_W-1:0] meas_single_data,
    output wire meas_single_valid,
    input wire meas_quad_en,
    input wire [6:0] meas_quad_index,
    output wire [`GP_P*`GP_AMP_W-1:0] meas_quad0,meas_quad1,meas_quad2,meas_quad3,
    output wire meas_quad_valid,
    // The expanded sampler uses one independently tagged row per square
    // engine. Legacy one/four-row clients retain their existing interface.
    input wire [SQUARE_ENGINES-1:0] meas_parallel_en,
    input wire [SQUARE_ENGINES*`GP_ROW_W-1:0] meas_parallel_rows,
    output wire [SQUARE_ENGINES*`GP_P*`GP_AMP_W-1:0] meas_parallel_data,
    output wire [SQUARE_ENGINES-1:0] meas_parallel_valid,
    input wire amp_write_forbid
);
    localparam integer E=INTRA_ENGINES,M=SQUARE_ENGINES;
    localparam integer CLIENT_ROWS=(M>4)?M:4,RP=(E>CLIENT_ROWS)?E:CLIENT_ROWS;
    localparam integer W=`GP_P*`GP_AMP_W,DW=`GP_P*`GP_DATA_W;
    wire [E-1:0] read_mask,dp_valid,out_valid;
    wire [E*9-1:0] read_rows,dp_rows,out_rows;
    wire [1:0] dp_op;
    wire acc_clear,sum_commit;
    wire [E*W-1:0] out_data;
    grover_ctrl_fsm_parallel #(.INTRA_ENGINES(E)) u_control (
        .clk(clk),.rstn(rstn),.iter_start(iter_start),.iter_do_init(iter_do_init),.iter_count(iter_count),
        .dp_out_valid(|out_valid),.dp_sum_commit(sum_commit),.iter_busy(iter_busy),.iter_done(iter_done),
        .state(state),.memory_read(read_mask),.memory_rows(read_rows),.dp_op(dp_op),
        .dp_valid(dp_valid),.dp_rows(dp_rows),.acc_clear(acc_clear),.pass_tick(pass_tick)
    );
    reg [RP-1:0] amp_read;
    reg [RP*9-1:0] amp_rows;
    wire [SLOT_W-1:0] read_slot=meas_busy?meas_slot:((bridge && state==2)?src_slot:dst_slot);
    wire [RP*W-1:0] amp_raw;
    wire [RP-1:0] amp_raw_valid;
    reg [RP*W-1:0] amp_aligned;
    reg [RP-1:0] amp_aligned_valid;
    reg quad_request1,quad_request2,single_request1,single_request2;
    reg [M-1:0] parallel_request1,parallel_request2;
    always @* begin
        amp_read=0;amp_rows=0;
        if(meas_busy) begin
            if(M>4) begin
                amp_read[M-1:0]=meas_parallel_en;
                amp_rows[M*9-1:0]=meas_parallel_rows;
            end else if(meas_single_en) begin amp_read[0]=1;amp_rows[0+:9]=meas_single_row;end
            else if(meas_quad_en) begin
                for(integer r=0;r<4;r=r+1) begin amp_read[r]=1;amp_rows[9*r+:9]={meas_quad_index,2'(r)};end
            end
        end else begin amp_read[E-1:0]=read_mask;amp_rows[E*9-1:0]=read_rows;end
    end
    wire [E-1:0] amp_write=((state==1 || state==2 || state==4) && !amp_write_forbid)?out_valid:0;
    grover_ckpt_mem_parallel #(.CHECKPOINT_CAPACITY(CHECKPOINT_CAPACITY),.READ_PORTS(RP),.WRITE_PORTS(E),.SLOT_W(SLOT_W)) u_amplitudes (
        .clk(clk),.rstn(rstn),.rd_slot(read_slot),.wr_slot(dst_slot),.rd_en(amp_read),.rd_rows(amp_rows),
        .rd_data(amp_raw),.rd_valid(amp_raw_valid),.wr_en(amp_write),.wr_rows(out_rows),.wr_data(out_data)
    );
    always @(posedge clk) begin
        if(!rstn) begin
            amp_aligned<=0;amp_aligned_valid<=0;quad_request1<=0;quad_request2<=0;single_request1<=0;single_request2<=0;
            parallel_request1<=0;parallel_request2<=0;
        end else begin
            amp_aligned<=amp_raw;amp_aligned_valid<=amp_raw_valid;
            quad_request1<=meas_busy && meas_quad_en && !meas_single_en;quad_request2<=quad_request1;
            single_request1<=meas_busy && meas_single_en;single_request2<=single_request1;
            parallel_request1<=meas_busy?meas_parallel_en:0;
            parallel_request2<=parallel_request1;
        end
    end
    assign meas_single_data=amp_aligned[0+:W];
    assign meas_single_valid=single_request2 && amp_aligned_valid[0];
    assign {meas_quad3,meas_quad2,meas_quad1,meas_quad0}=amp_aligned[4*W-1:0];
    assign meas_quad_valid=quad_request2 && (&amp_aligned_valid[3:0]);
    assign meas_parallel_data=amp_aligned[M*W-1:0];
    assign meas_parallel_valid=parallel_request2 & amp_aligned_valid[M-1:0];
    wire [E*DW-1:0] data_aligned;
    wire [E*`GP_P-1:0] masks_aligned;
    wire [E-1:0] mask_busy,mask_clear,mask_set;
    genvar engine;
    generate for(engine=0;engine<E;engine=engine+1) begin : g_oracle_memory
        wire [DW-1:0] data_raw;
        wire [`GP_P-1:0] mask_raw;
        wire signed [`GP_DATA_W-1:0] verify_data_copy;
        wire verify_found_copy;
        reg [DW-1:0] data_q;
        reg [`GP_P-1:0] mask_q;
        grover_data_mem u_data (
            .clk(clk),.rd_row(read_rows[engine*9+:9]),.rd_en(read_mask[engine] && state==2),.rd_data(data_raw),
            .wr_index(data_wr_index),.wr_en(data_wr_en),.wr_data(data_wr_value),
            .verify_index(verify_index),.verify_data(verify_data_copy)
        );
        grover_found_mask_mem u_mask (
            .clk(clk),.rstn(rstn),.oracle_rd_row(read_rows[engine*9+:9]),.oracle_rd_en(read_mask[engine] && state==2),
            .oracle_mask_row(mask_raw),.verify_index(verify_index),.verify_found(verify_found_copy),
            .clear_start(mask_clear_start),.set_start(mask_set_start),.set_index(mask_set_index),
            .maint_busy(mask_busy[engine]),.clear_done(mask_clear[engine]),.set_done(mask_set[engine])
        );
        always @(posedge clk) begin
            if(!rstn) begin data_q<=0;mask_q<=0;end
            else begin data_q<=data_raw;mask_q<=mask_raw;end
        end
        assign data_aligned[engine*DW+:DW]=data_q;
        assign masks_aligned[engine*`GP_P+:`GP_P]=mask_q;
        if(engine==0) begin : g_verify
            assign verify_value=verify_data_copy;assign verify_found=verify_found_copy;
        end
    end endgenerate
    assign mask_maint_busy=|mask_busy;
    assign mask_clear_done=&mask_clear;
    assign mask_set_done=&mask_set;
    grover_iter_datapath_parallel #(.INTRA_ENGINES(E)) u_datapath (
        .clk(clk),.rstn(rstn),.op(dp_op),.row_valid(dp_valid),.row_indices(dp_rows),.acc_clear(acc_clear),
        .amp_in(amp_aligned[E*W-1:0]),.data_in(data_aligned),.found_mask_in(masks_aligned),
        .predicate_mode(predicate_mode),.threshold_a(threshold_a),.threshold_b(threshold_b),
        .data_count(data_count),.enum_enable(enum_enable),.amp_out(out_data),.row_out_valid(out_valid),
        .row_out_indices(out_rows),.global_sum(global_sum),.two_mean(two_mean),.sum_commit(sum_commit),.sat_event(sat_event)
    );
`ifndef SYNTHESIS
    always @(posedge clk) if(rstn) begin
        if(iter_start && bridge && iter_count!=1) $fatal(1,"a bridge request must execute exactly one iteration");
        if(meas_busy && iter_busy) $fatal(1,"measurement/iteration amplitude ownership conflict");
        if((|amp_write) && meas_busy) $fatal(1,"amplitude write during measurement");
    end
`endif
endmodule
