`timescale 1ns/1ps
`include "grover_param.vh"

// Parameter-width policy interface for simulation development. The production
// configurations retain the existing optimized backend. Wider configurations
// use the generic exact backend below; its latency must be reported separately
// until it has the same datapath schedule and Main-IP integration as production.
module grover_ckpt_policy_parameterized #(
    parameter integer CHECKPOINT_CAPACITY=3,
    parameter integer LOOKAHEAD_SHOTS=3,
    parameter integer EXACT_PRUNE=6,
    parameter integer FORCE_GENERIC=0,
    parameter integer SCAN_LANES=4,
    parameter integer MEMO_ADDR_W=12,
    parameter integer EPOCH_W=16,
    parameter integer COUNT_W=$clog2(CHECKPOINT_CAPACITY+1),
    parameter integer FAST_PATHS=1
) (
    input wire clk, rstn, start,
    input wire [CHECKPOINT_CAPACITY-1:0] slot_valid,
    input wire [CHECKPOINT_CAPACITY*`GP_J_W-1:0] slot_j_flat,
    input wire [(LOOKAHEAD_SHOTS+1)*`GP_J_W-1:0] j_window_flat,
    output wire busy,done,policy_error,
    output wire [`GP_J_W-1:0] source_j,
    output wire [COUNT_W-1:0] next_count,
    output wire [CHECKPOINT_CAPACITY*`GP_J_W-1:0] next_j_flat,
    output wire [10:0] root_cost,
    output wire [COUNT_W-1:0] root_segment_count,
    output wire [31:0] policy_cycles_last,policy_actions_last,
    output wire [31:0] policy_memo_hit_last,policy_memo_miss_last
);
    initial begin
        if (CHECKPOINT_CAPACITY<1 || CHECKPOINT_CAPACITY>10 ||
            LOOKAHEAD_SHOTS<1 || LOOKAHEAD_SHOTS>10)
            $fatal(1,"parameterized policy requires capacity/lookahead in 1..10");
        if (EXACT_PRUNE!=5 && EXACT_PRUNE!=6)
            $fatal(1,"parameterized policy supports exact search modes 5 and 6");
        if (SCAN_LANES!=1 && SCAN_LANES!=2 && SCAN_LANES!=4)
            $fatal(1,"SCAN_LANES must be 1, 2 or 4");
        if (COUNT_W<$clog2(CHECKPOINT_CAPACITY+1))
            $fatal(1,"COUNT_W cannot represent the checkpoint capacity");
    end
    generate
        if (FORCE_GENERIC==0 && (CHECKPOINT_CAPACITY==3 || CHECKPOINT_CAPACITY==4) &&
            LOOKAHEAD_SHOTS<=8) begin : g_production
            wire [27:0] output_tuple;
            wire [2:0] output_count,output_segments;
            grover_ckpt_policy_rolling #(
                .CHECKPOINT_CAPACITY(CHECKPOINT_CAPACITY),.LOOKAHEAD_SHOTS(LOOKAHEAD_SHOTS),
                .EXACT_PRUNE(EXACT_PRUNE),.CANON_LANES(SCAN_LANES),.SCAN_LANES(SCAN_LANES)
            ) u_policy (
                .clk(clk),.rstn(rstn),.start(start),
                .slot_valid({{(4-CHECKPOINT_CAPACITY){1'b0}},slot_valid}),
                .slot_j_flat({{((4-CHECKPOINT_CAPACITY)*`GP_J_W){1'b0}},slot_j_flat}),
                .j_window_flat({{((8-LOOKAHEAD_SHOTS)*`GP_J_W){1'b0}},j_window_flat}),
                .busy(busy),.done(done),.policy_error(policy_error),.source_j(source_j),
                .next_count(output_count),.next_j_flat(output_tuple),.root_cost(root_cost),
                .root_segment_count(output_segments),.policy_cycles_last(policy_cycles_last),
                .policy_actions_last(policy_actions_last),.policy_memo_hit_last(policy_memo_hit_last),
                .policy_memo_miss_last(policy_memo_miss_last),.policy_cycles_total(),
                .policy_actions_total(),.policy_max_latency(),.policy_epoch()
            );
            assign next_j_flat=output_tuple[CHECKPOINT_CAPACITY*`GP_J_W-1:0];
            assign next_count=output_count[COUNT_W-1:0];
            assign root_segment_count=output_segments[COUNT_W-1:0];
        end else begin : g_general
            grover_ckpt_policy_generic #(
                .K(CHECKPOINT_CAPACITY),.H(LOOKAHEAD_SHOTS),.MODE(EXACT_PRUNE),
                .LANES(SCAN_LANES),.MEMO_ADDR_W(MEMO_ADDR_W),.EPOCH_W(EPOCH_W),.CW(COUNT_W),
                .FAST_PATHS(FAST_PATHS)
            ) u_policy (.*);
        end
    endgenerate
endmodule

// Exact restricted-B solver with parameter-sized sets, stack, and memo tags.
// A set is a mask of sorted universe values, avoiding four-slot tuple limits.
// Four independent candidates can enter the existing three-stage relaxed gap
// bound each clock. SCAN caches those bounds, chooses the minimum optimistic
// key, evaluates that seed exactly, and replays only surviving candidates.
// Memo collisions replace entries after full tag comparison, never alias costs.
// This is an experimental RTL backend, not a software latency estimate.
module grover_ckpt_policy_generic #(
    parameter integer K=3,H=3,MODE=6,LANES=4,MEMO_ADDR_W=12,EPOCH_W=16,CW=$clog2(K+1),FAST_PATHS=1
) (
    input wire clk,rstn,start,
    input wire [K-1:0] slot_valid,
    input wire [K*`GP_J_W-1:0] slot_j_flat,
    input wire [(H+1)*`GP_J_W-1:0] j_window_flat,
    output reg busy,done,policy_error,
    output reg [`GP_J_W-1:0] source_j,
    output reg [CW-1:0] next_count,
    output reg [K*`GP_J_W-1:0] next_j_flat,
    output reg [10:0] root_cost,
    output reg [CW-1:0] root_segment_count,
    output reg [31:0] policy_cycles_last,policy_actions_last,
    output reg [31:0] policy_memo_hit_last,policy_memo_miss_last
);
    localparam integer U=K+H+1, CB=(K>H+1)?K:H+1;
    localparam integer IW=1+2*CB+2*CW, WORD_W=U+CW+11;
    localparam integer MEM_SIZE=1<<MEMO_ADDR_W;
    localparam [10:0] INF=11'h7ff;
    function automatic integer combinations(input integer n,k);
        integer i; begin
            combinations=1;
            for(i=1;i<=k;i=i+1) combinations=combinations*(n-i+1)/i;
        end
    endfunction
    function automatic integer cache_bound(input integer n,k);
        integer i; begin
            cache_bound=0;
            for(i=0;i<=k;i=i+1) cache_bound=cache_bound+combinations(n,i);
        end
    endfunction
    localparam integer CACHE_N=cache_bound(U-1,K-1);
    localparam integer CACHE_W=$clog2(CACHE_N+1);
    localparam [3:0] IDLE=0,CLEAR=1,BUILD=2,MAP=3,PREP=4,SCAN=5,
        PROBE=6,RESPONSE=7,EVALUATE=8,REPLAY=9,FINISH=10,RETURN=11,CACHE_READ=12,ROOT_FAST=13;
    reg [3:0] state;
    reg [K-1:0] held_valid;
    reg [K*7-1:0] held_flat;
    reg [(H+1)*7-1:0] request_flat;
    reg [6:0] universe[0:U-1];
    integer universe_count,build_index,sp;
    reg [U-1:0] request_bit[0:H];
    reg [6:0] requests[0:H];
    reg [U-1:0] pool_mask;
    reg [U-1:0] frame_mask[0:H];
    reg [6:0] frame_imm[0:H],frame_pred[0:H];
    reg [10:0] frame_best[0:H],frame_seed_bound[0:H];
    reg [U-1:0] frame_best_mask[0:H],frame_pending_mask[0:H];
    reg [CW-1:0] frame_best_seg[0:H],frame_pending_seg[0:H];
    reg frame_seed[0:H];
    integer frame_count[0:H],frame_next[0:H],frame_seed_index[0:H];
    reg [WORD_W-1:0] cache[0:(H+1)*CACHE_N-1];
    reg [EPOCH_W-1:0] epoch;
    reg clear_resume,clear_fast;
    integer clear_index;
    reg [EPOCH_W-1:0] memo_epoch[0:MEM_SIZE-1];
    reg [U-1:0] memo_mask[0:MEM_SIZE-1];
    reg [3:0] memo_depth[0:MEM_SIZE-1];
    reg [10:0] memo_cost[0:MEM_SIZE-1];
    reg memo_hit_q;
    reg [10:0] memo_cost_q,return_cost,evaluated_cost;
    reg [31:0] cycles,actions,hits,misses;
    reg [U-1:0] extra_mask,keep_mask,endpoint;
    integer extra_count,keep_count;
    reg [IW-1:0] iterator;

    // Decide a unique root action directly from the input packet. Building a
    // sorted universe, mapping every future value and launching lower bounds
    // cannot change that action. Mode 6 deliberately reports immediate cost
    // for this established Single-Action Exit contract. The raw physical slot
    // order is arbitrary, so construct the same ascending canonical tuple.
    reg [6:0] input_pred,input_request,input_value;
    reg input_extra,input_held,input_unique;
    reg [K*7-1:0] input_next;
    integer input_keeps,input_rank,input_count;
    always @* begin
        input_request=j_window_flat[0+:7];input_pred=0;
        input_extra=0;input_held=0;input_value=0;input_keeps=0;
        input_rank=0;input_count=0;input_next=0;input_unique=0;
        for(integer s=0;s<K;s=s+1) if(slot_valid[s]) begin
            if(slot_j_flat[7*s+:7]<=input_request && slot_j_flat[7*s+:7]>input_pred)
                input_pred=slot_j_flat[7*s+:7];
            if(slot_j_flat[7*s+:7]!=input_request) input_keeps=input_keeps+1;
        end
        for(integer h=0;h<=H;h=h+1) begin
            input_value=j_window_flat[7*h+:7];input_held=0;
            for(integer s=0;s<K;s=s+1)
                if(slot_valid[s] && slot_j_flat[7*s+:7]==input_value) input_held=1;
            if(input_pred<input_value && input_value<input_request && !input_held) input_extra=1;
        end
        input_unique=(MODE==6) && (K==1 || (!input_extra && input_keeps<K));
        if(K==1) begin input_next[0+:7]=input_request;input_count=1;end
        else begin
            input_rank=0;
            for(integer s=0;s<K;s=s+1)
                if(slot_valid[s] && slot_j_flat[7*s+:7]<input_request) input_rank=input_rank+1;
            if(input_rank<K) input_next[7*input_rank+:7]=input_request;
            for(integer s=0;s<K;s=s+1) if(slot_valid[s] && slot_j_flat[7*s+:7]!=input_request) begin
                input_rank=(input_request<slot_j_flat[7*s+:7])?1:0;
                for(integer t=0;t<K;t=t+1)
                    if(slot_valid[t] && slot_j_flat[7*t+:7]!=input_request &&
                        slot_j_flat[7*t+:7]<slot_j_flat[7*s+:7]) input_rank=input_rank+1;
                if(input_rank<K) input_next[7*input_rank+:7]=slot_j_flat[7*s+:7];
            end
            input_count=input_keeps+1;
        end
    end

    function automatic [CB-1:0] first_comb(input integer size);
        begin first_comb=(1<<size)-1; end
    endfunction
    function automatic has_next(input [CB-1:0] mask,input integer n,size);
        begin has_next=(size>0) && mask<(((1<<size)-1)<<(n-size)); end
    endfunction
    function automatic [CB-1:0] next_comb(input [CB-1:0] mask);
        reg [CB:0] low,raised;
        begin
            low={1'b0,mask}&(-{1'b0,mask}); raised={1'b0,mask}+low;
            next_comb=low!=0 ? raised|(((raised^{1'b0,mask})>>2)/low) : 0;
        end
    endfunction
    function automatic [IW-1:0] successor(input [IW-1:0] it,input integer ne,nk);
        reg valid;
        reg [CB-1:0] dm,rm;
        reg [CW-1:0] ds,rs;
        integer room;
        begin
            {valid,rm,rs,dm,ds}=it;
            if(valid) begin
                if(has_next(rm,nk,rs)) rm=next_comb(rm);
                else if(has_next(dm,ne,ds)) begin dm=next_comb(dm); rm=first_comb(rs); end
                else if(ds<K-1 && ds<ne) begin
                    ds=ds+1'b1; room=K-1-ds; rs=(nk<room)?nk:room;
                    dm=first_comb(ds); rm=first_comb(rs);
                end else valid=0;
            end
            successor={valid,rm,rs,dm,ds};
        end
    endfunction
    function automatic [U-1:0] child_of(input [IW-1:0] it,
        input [U-1:0] extras,keeps,end_bit);
        reg valid;
        reg [CB-1:0] dm,rm;
        reg [CW-1:0] ds,rs;
        integer i,di,ri;
        begin
            {valid,rm,rs,dm,ds}=it; child_of=end_bit; di=0;ri=0;
            for(i=0;i<U;i=i+1) begin
                if(extras[i]) begin child_of[i]=dm[di];di=di+1;end
                if(keeps[i]) begin child_of[i]=rm[ri];ri=ri+1;end
            end
        end
    endfunction
    function automatic [8*K-1:0] tuple_key(input [U-1:0] mask);
        integer i,n;
        begin
            tuple_key=0;n=0;
            for(i=0;i<U;i=i+1) if(mask[i] && n<K) begin
                // Add one so zero padding sorts before any proper extension.
                tuple_key[8*(K-1-n)+:8]={1'b0,universe[i]}+8'd1;n=n+1;
            end
        end
    endfunction
    function automatic better(input [10:0] cost,input [CW-1:0] seg,
        input [U-1:0] mask,input [10:0] incumbent,input [CW-1:0] best_seg,
        input [U-1:0] best_mask,input root);
        begin better=cost<incumbent || (root && cost==incumbent &&
            (seg<best_seg || (seg==best_seg && tuple_key(mask)<tuple_key(best_mask)))); end
    endfunction
    function automatic [MEMO_ADDR_W-1:0] hash_key(input [U-1:0] mask,input integer depth);
        integer i;
        begin
            hash_key=depth;
            for(i=0;i<U;i=i+1) hash_key[i%MEMO_ADDR_W]=hash_key[i%MEMO_ADDR_W]^mask[i];
        end
    endfunction
    initial begin
        if(EPOCH_W<2 || EPOCH_W>16) $fatal(1,"EPOCH_W must be 2..16");
        if(MEMO_ADDR_W<1 || MEMO_ADDR_W>20) $fatal(1,"MEMO_ADDR_W must be 1..20");
    end
    // One registered memo response, with the full state/depth/solve epoch tag.
    // Clear is serial and measured when required; ordinary solves advance epoch.
    always @(posedge clk) begin
        if(state==PROBE && busy) begin
            memo_hit_q <= memo_epoch[hash_key(frame_pending_mask[sp],sp+1)]==epoch &&
                memo_mask[hash_key(frame_pending_mask[sp],sp+1)]==frame_pending_mask[sp] &&
                memo_depth[hash_key(frame_pending_mask[sp],sp+1)]==sp+1;
            memo_cost_q <= memo_cost[hash_key(frame_pending_mask[sp],sp+1)];
        end
        if(!rstn) begin
            // Actual clearing is performed by CLEAR after reset is released.
        end else if(state==CLEAR) memo_epoch[clear_index]<=0;
        else if(state==FINISH && sp!=0 && busy) begin
            memo_epoch[hash_key(frame_mask[sp],sp)]<=epoch;
            memo_mask[hash_key(frame_mask[sp],sp)]<=frame_mask[sp];
            memo_depth[hash_key(frame_mask[sp],sp)]<=sp;
            memo_cost[hash_key(frame_mask[sp],sp)]<=frame_best[sp];
        end
    end

    reg [U-1:0] prep_extra,prep_keep,prep_future,prep_endpoint;
    reg [6:0] prep_pred,prep_request,suffix_request,suffix_pred;
    integer prep_ne,prep_nk,i,j,n,found,position;
    always @* begin
        prep_extra=0;prep_keep=0;prep_future=0;prep_endpoint=0;
        prep_pred=0;prep_request=requests[sp];prep_ne=0;prep_nk=0;
        for(i=0;i<U;i=i+1) if(i<universe_count && frame_mask[sp][i] &&
            universe[i]<=prep_request && universe[i]>prep_pred) prep_pred=universe[i];
        for(i=0;i<U;i=i+1) if(i<universe_count) begin
            prep_endpoint[i]=(universe[i]==prep_request);
            prep_keep[i]=frame_mask[sp][i] && universe[i]!=prep_request;
            prep_extra[i]=pool_mask[i] && !frame_mask[sp][i] &&
                prep_pred<universe[i] && universe[i]<prep_request;
            if(prep_keep[i]) prep_nk=prep_nk+1;
            if(prep_extra[i]) prep_ne=prep_ne+1;
        end
        for(i=0;i<=H;i=i+1) if(i>sp) prep_future=prep_future|request_bit[i];
        // A non-root two-request suffix needs only its cost. With capacity
        // at least two, the endpoint can coexist with any one eligible old
        // checkpoint or deposited intermediate. The greatest attainable
        // predecessor of the last request therefore gives its exact cost.
        suffix_request=requests[(sp<H)?sp+1:H];
        suffix_pred=(prep_request<=suffix_request)?prep_request:7'd0;
        for(i=0;i<U;i=i+1) if(i<universe_count && universe[i]<=suffix_request &&
            universe[i]>suffix_pred && (frame_mask[sp][i] || prep_extra[i])) suffix_pred=universe[i];
    end
    wire [IW-1:0] lane_it[0:LANES] /* verilator split_var */;
    wire [U-1:0] lane_child[0:LANES-1];
    wire [10:0] lane_bound_raw[0:LANES-1];
    reg [10:0] lane_bound[0:LANES-1];
    reg [LANES-1:0] valid0,valid1,valid2;
    wire [7*U-1:0] values_flat;
    wire [U-1:0] scan_future=prep_future;
    reg [U-1:0] mask0[0:LANES-1],mask1[0:LANES-1],mask2[0:LANES-1];
    reg [CW-1:0] seg0[0:LANES-1],seg1[0:LANES-1],seg2[0:LANES-1];
    assign lane_it[0]=iterator;
    genvar g;
    generate
        for(g=0;g<U;g=g+1) begin : g_values
            assign values_flat[7*g+:7]=universe[g];
        end
        for(g=0;g<LANES;g=g+1) begin : g_lane
            wire [IW-1:0] current_iterator,next_iterator;
            if(g==0) assign current_iterator=iterator;
            else assign current_iterator=g_lane[g-1].next_iterator;
            assign next_iterator=successor(current_iterator,extra_count,keep_count);
            assign lane_it[g+1]=next_iterator;
            assign lane_child[g]=child_of(current_iterator,extra_mask,keep_mask,endpoint);
            grover_ckpt_gap_bound #(.UB(U)) u_bound (
                .clk(clk),.child_mask(lane_child[g]),.future_mask(scan_future),
                .values_flat(values_flat),.cost(lane_bound_raw[g])
            );
            always @(posedge clk) begin
                lane_bound[g]<=lane_bound_raw[g];
                mask0[g]<=lane_child[g]; mask1[g]<=mask0[g]; mask2[g]<=mask1[g];
                seg0[g]<=current_iterator[CW-1:0]+1'b1;
                seg1[g]<=seg0[g];seg2[g]<=seg1[g];
            end
        end
    endgenerate
    always @(posedge clk) begin
        if(!rstn || state!=SCAN) begin valid0<=0;valid1<=0;valid2<=0;end
        else begin
            for(integer l=0;l<LANES;l=l+1) valid0[l]<=lane_it[l][IW-1];
            valid1<=valid0;valid2<=valid1;
        end
    end
    reg scan_found;
    reg [10:0] scan_min;
    reg [CW-1:0] scan_seg;
    reg [U-1:0] scan_mask;
    integer scan_index,scan_written;
    always @* begin
        scan_found=frame_count[sp]!=0;
        scan_min=frame_seed_bound[sp];scan_seg=frame_pending_seg[sp];
        scan_mask=frame_pending_mask[sp];scan_index=frame_seed_index[sp];scan_written=0;
        for(integer l=0;l<LANES;l=l+1) if(valid2[l]) begin
            if(!scan_found || better(lane_bound[l]+frame_imm[sp],seg2[l],mask2[l],
                scan_min,scan_seg,scan_mask,sp==0)) begin
                scan_found=1;scan_min=lane_bound[l]+frame_imm[sp];
                scan_seg=seg2[l];scan_mask=mask2[l];scan_index=frame_count[sp]+scan_written;
            end
            scan_written=scan_written+1;
        end
    end
    reg replay_found;
    reg [WORD_W-1:0] replay_word,walk_word;
    reg [WORD_W-1:0] replay_words[0:LANES-1];
    always @(posedge clk) if(state==CACHE_READ)
        for(integer l=0;l<LANES;l=l+1)
            if(frame_next[sp]+l<frame_count[sp])
                replay_words[l]<=cache[sp*CACHE_N+frame_next[sp]+l];
            else replay_words[l]<=0;
    integer replay_next;
    always @* begin
        replay_found=0;replay_word=0;walk_word=0;replay_next=frame_next[sp];
        for(integer l=0;l<LANES;l=l+1) if(!replay_found && replay_next<frame_count[sp]) begin
            walk_word=replay_words[l];
            if(replay_next!=frame_seed_index[sp] &&
                better(walk_word[10:0]+frame_imm[sp],walk_word[11+:CW],
                    walk_word[11+CW+:U],frame_best[sp],frame_best_seg[sp],frame_best_mask[sp],sp==0)) begin
                replay_found=1;replay_word=walk_word;
            end
            replay_next=replay_next+1;
        end
    end
    reg [U-1:0] mapped_initial,mapped_pool;
    reg [U-1:0] mapped_request[0:H];
    always @* begin
        mapped_initial=0;mapped_pool=0;
        for(integer h=0;h<=H;h=h+1) begin
            mapped_request[h]=0;
            for(integer v=0;v<U;v=v+1)
                if(v<universe_count && universe[v]==request_flat[7*h+:7])
                    mapped_request[h][v]=1;
            mapped_pool=mapped_pool|mapped_request[h];
        end
        for(integer v=0;v<U;v=v+1)
            for(integer s=0;s<K;s=s+1)
                if(held_valid[s] && v<universe_count && universe[v]==held_flat[7*s+:7])
                    mapped_initial[v]=1;
    end
    reg [6:0] build_value;
    reg build_use;
    always @* begin
        build_value=0;build_use=0;
        if(build_index<K) begin
            build_value=held_flat[7*build_index+:7];build_use=held_valid[build_index];
        end else if(build_index<U) begin
            build_value=request_flat[7*(build_index-K)+:7];build_use=1;
        end
    end
    // All search progress is clocked. The generic backend has no DPI/software
    // solve call and never translates an algorithmic work count into cycles.
    always @(posedge clk) begin
        if(!rstn) begin
            state<=CLEAR;clear_index<=0;epoch<=0;clear_resume<=0;clear_fast<=0;busy<=1;done<=0;policy_error<=0;
            source_j<=0;next_count<=0;next_j_flat<=0;root_cost<=0;root_segment_count<=0;
            policy_cycles_last<=0;policy_actions_last<=0;policy_memo_hit_last<=0;policy_memo_miss_last<=0;
            cycles<=0;actions<=0;hits<=0;misses<=0;sp<=0;universe_count<=0;
            build_index<=0;iterator<=0;pool_mask<=0;extra_mask<=0;keep_mask<=0;endpoint<=0;
            extra_count<=0;keep_count<=0;return_cost<=0;evaluated_cost<=0;
            for(integer d=0;d<=H;d=d+1) begin
                frame_mask[d]<=0;frame_imm[d]<=0;frame_pred[d]<=0;frame_best[d]<=INF;
                frame_seed_bound[d]<=INF;frame_best_mask[d]<=0;frame_pending_mask[d]<=0;
                frame_best_seg[d]<=0;frame_pending_seg[d]<=0;frame_seed[d]<=0;
                frame_count[d]<=0;frame_next[d]<=0;frame_seed_index[d]<=0;
                requests[d]<=0;request_bit[d]<=0;
            end
            for(integer v=0;v<U;v=v+1) universe[v]<=0;
        end else begin
            done<=0;
            if(busy) cycles<=cycles+1;
            case(state)
                CLEAR: begin
                    if(clear_index==MEM_SIZE-1) begin
                        clear_index<=0;epoch<=1;clear_resume<=0;
                        if(clear_resume) state<=clear_fast?ROOT_FAST:BUILD;
                        else begin state<=IDLE;busy<=0;end
                    end
                    else clear_index<=clear_index+1;
                end
                IDLE: if(start) begin
                    held_valid<=slot_valid;held_flat<=slot_j_flat;request_flat<=j_window_flat;
                    busy<=1;policy_error<=0;cycles<=0;actions<=0;hits<=0;misses<=0;
                    universe_count<=0;build_index<=0;pool_mask<=0;sp<=0;
                    frame_mask[0]<=0;state<=BUILD;
                    clear_fast<=FAST_PATHS && input_unique;
                    if(FAST_PATHS && input_unique) begin
                        source_j<=input_pred;next_j_flat<=input_next;next_count<=CW'(input_count);
                        root_cost<=11'(input_request-input_pred);root_segment_count<=CW'(1);
                        state<=ROOT_FAST;
                    end
                    if(epoch=={EPOCH_W{1'b1}}) begin
                        // A start at wrap is accepted and retained while tags clear.
                        state<=CLEAR;epoch<=0;clear_resume<=1;
                    end else epoch<=epoch+1;
                end
                ROOT_FAST: begin
                    policy_cycles_last<=cycles+1;policy_actions_last<=1;
                    policy_memo_hit_last<=0;policy_memo_miss_last<=0;
                    busy<=0;done<=1;state<=IDLE;
                end
                BUILD: begin
                    if(build_use) begin
                        found=0;position=universe_count;
                        for(integer v=0;v<U;v=v+1) if(v<universe_count) begin
                            if(universe[v]==build_value) found=1;
                            if(universe[v]>build_value && position==universe_count) position=v;
                        end
                        if(!found) begin
                            for(integer v=U-1;v>0;v=v-1)
                                if(v>position && v<=universe_count) universe[v]<=universe[v-1];
                            universe[position]<=build_value;universe_count<=universe_count+1;
                        end
                    end
                    if(build_index==U-1) state<=MAP;
                    else build_index<=build_index+1;
                end
                MAP: begin
                    frame_mask[0]<=mapped_initial;pool_mask<=mapped_pool;
                    for(integer h=0;h<=H;h=h+1) begin
                        request_bit[h]<=mapped_request[h];requests[h]<=request_flat[7*h+:7];
                    end
                    state<=PREP;
                end
                PREP: begin
                    frame_imm[sp]<=prep_request-prep_pred;frame_pred[sp]<=prep_pred;
                    frame_best[sp]<=INF;frame_best_seg[sp]<=0;frame_best_mask[sp]<=0;
                    frame_seed_bound[sp]<=INF;frame_pending_seg[sp]<=0;frame_pending_mask[sp]<=0;
                    frame_count[sp]<=0;frame_next[sp]<=0;frame_seed_index[sp]<=0;frame_seed[sp]<=1;
                    if(sp==0) source_j<=prep_pred;
                    if(sp==H) begin frame_best[sp]<=prep_request-prep_pred;state<=FINISH;end
                    else if(FAST_PATHS && sp!=0 && sp==H-1 && K>=2) begin
                        frame_best[sp]<=11'(prep_request-prep_pred)+11'(suffix_request-suffix_pred);
                        actions<=actions+1;state<=FINISH;
                    end else if(sp==0 && MODE==6 && (K==1 || (prep_ne==0 && prep_nk<=K-1))) begin
                        frame_best[sp]<=prep_request-prep_pred;frame_best_mask[sp]<=(K==1) ? prep_endpoint : prep_keep|prep_endpoint;
                        frame_best_seg[sp]<=1;actions<=actions+1;state<=FINISH;
                    end else if(FAST_PATHS && (K==1 || (prep_ne==0 && prep_nk<K))) begin
                        // The tail still needs an exact value, but a unique
                        // child needs neither candidate SCAN nor a bound.
                        frame_pending_mask[sp]<=(K==1)?prep_endpoint:prep_keep|prep_endpoint;
                        frame_pending_seg[sp]<=CW'(1);frame_count[sp]<=1;frame_seed[sp]<=0;
                        actions<=actions+1;state<=PROBE;
                    end else begin
                        extra_mask<=prep_extra;keep_mask<=prep_keep;endpoint<=prep_endpoint;
                        extra_count<=prep_ne;keep_count<=prep_nk;
                        n=(prep_nk<K-1)?prep_nk:K-1;
                        iterator<={1'b1,first_comb(n),CW'(n),{CB{1'b0}},{CW{1'b0}}};
                        state<=SCAN;
                    end
                end
                SCAN: begin
                    iterator<=lane_it[LANES];
                    if(|valid2) begin
                        n=0;
                        for(integer l=0;l<LANES;l=l+1) if(valid2[l]) begin
                            if(frame_count[sp]+n>=CACHE_N) $fatal(1,"generic candidate cache overflow");
                            cache[sp*CACHE_N+frame_count[sp]+n]<={mask2[l],seg2[l],lane_bound[l]};n=n+1;
                        end
                        actions<=actions+n;frame_count[sp]<=frame_count[sp]+n;
                        frame_seed_bound[sp]<=scan_min;frame_pending_seg[sp]<=scan_seg;
                        frame_pending_mask[sp]<=scan_mask;frame_seed_index[sp]<=scan_index;
                    end
                    if(|valid2 && !iterator[IW-1] && !(|valid0) && !(|valid1)) begin
                        if(FAST_PATHS && sp==H-1) begin
                            // Only one request follows: its relaxed gap bound
                            // is already exact, including root tie-breaking.
                            frame_best[sp]<=scan_min;frame_best_mask[sp]<=scan_mask;
                            frame_best_seg[sp]<=scan_seg;state<=FINISH;
                        end else state<=PROBE;
                    end
                end
                PROBE: state<=RESPONSE;
                RESPONSE: begin
                    if(memo_hit_q) begin
                        hits<=hits+1;evaluated_cost<=frame_imm[sp]+memo_cost_q;state<=EVALUATE;
                    end else begin
                        misses<=misses+1;frame_mask[sp+1]<=frame_pending_mask[sp];sp<=sp+1;state<=PREP;
                    end
                end
                RETURN: begin evaluated_cost<=frame_imm[sp]+return_cost;state<=EVALUATE;end
                EVALUATE: begin
                    if(better(evaluated_cost,frame_pending_seg[sp],frame_pending_mask[sp],
                        frame_best[sp],frame_best_seg[sp],frame_best_mask[sp],sp==0)) begin
                        frame_best[sp]<=evaluated_cost;frame_best_mask[sp]<=frame_pending_mask[sp];
                        frame_best_seg[sp]<=frame_pending_seg[sp];
                    end
                    if((FAST_PATHS && frame_count[sp]==1) ||
                        (frame_seed[sp] && evaluated_cost==frame_seed_bound[sp])) state<=FINISH;
                    else begin frame_seed[sp]<=0;state<=CACHE_READ;end
                end
                CACHE_READ: state<=REPLAY;
                REPLAY: begin
                    frame_next[sp]<=replay_next;
                    if(replay_found) begin
                        frame_pending_mask[sp]<=replay_word[11+CW+:U];
                        frame_pending_seg[sp]<=replay_word[11+:CW];state<=PROBE;
                    end else if(replay_next>=frame_count[sp]) state<=FINISH;
                    else state<=CACHE_READ;
                end
                FINISH: begin
                    if(sp!=0) begin return_cost<=frame_best[sp];sp<=sp-1;state<=RETURN;end
                    else begin
                        n=0;next_j_flat<=0;
                        for(integer v=0;v<U;v=v+1) if(frame_best_mask[0][v]) begin
                            if(n>=K) $fatal(1,"generic tuple exceeds capacity");
                            next_j_flat[7*n+:7]<=universe[v];n=n+1;
                        end
                        next_count<=n;root_cost<=frame_best[0];root_segment_count<=frame_best_seg[0];
                        policy_cycles_last<=cycles+1;policy_actions_last<=actions;
                        policy_memo_hit_last<=hits;policy_memo_miss_last<=misses;
                        busy<=0;done<=1;state<=IDLE;
                    end
                end
                default: begin policy_error<=1;busy<=0;done<=1;state<=IDLE;end
            endcase
        end
    end
endmodule
