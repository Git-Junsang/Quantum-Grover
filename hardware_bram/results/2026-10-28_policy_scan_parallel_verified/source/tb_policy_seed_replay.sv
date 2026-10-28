`timescale 1ns/1ps
`include "grover_param.vh"

// Compare seed-first exact search with the independent exhaustive mode. The
// observer remembers the selected seed tuple, not the DUT's generator key, so
// it detects both a wrong skip and a seed that still reaches canonical output.
// Recursive misses exercise restoration of the parent frame's remembered seed.
module tb_policy_seed_replay #(
    parameter integer CKPT_K = 3,
    parameter integer H_FUTURE = 3,
    parameter integer RANDOM_CASES = 320,
    parameter integer REQUIRE_COVERAGE = 1,
    parameter integer EXACT_PRUNE = 5,
    parameter integer CANON_LANES = 4,
    parameter integer SCAN_LANES = CANON_LANES
);
    reg clk = 1'b0;
    always #5 clk = ~clk;
    reg rstn = 1'b0;
    reg start = 1'b0;
    reg [3:0] slot_valid = 4'd0;
    reg [27:0] slot_j_flat = 28'd0;
    reg [62:0] j_window_flat = 63'd0;

    wire busy, done, policy_error, ref_busy, ref_done, ref_error;
    wire [6:0] source_j, ref_source;
    wire [2:0] next_count, ref_count, segments, ref_segments;
    wire [27:0] next_j_flat, ref_next;
    wire [10:0] root_cost, ref_cost;
    wire [7:0] epoch, ref_epoch;

    grover_ckpt_policy_rolling #(.CKPT_K(CKPT_K), .H_FUTURE(H_FUTURE),
        .EXACT_PRUNE(EXACT_PRUNE), .CANON_LANES(CANON_LANES), .SCAN_LANES(SCAN_LANES)) dut (
        .clk(clk), .rstn(rstn), .start(start),
        .slot_valid(slot_valid), .slot_j_flat(slot_j_flat), .j_window_flat(j_window_flat),
        .busy(busy), .done(done), .policy_error(policy_error),
        .source_j(source_j), .next_count(next_count), .next_j_flat(next_j_flat),
        .root_cost(root_cost), .root_segment_count(segments), .policy_epoch(epoch)
    );
    grover_ckpt_policy_rolling #(.CKPT_K(CKPT_K), .H_FUTURE(H_FUTURE), .EXACT_PRUNE(0)) reference (
        .clk(clk), .rstn(rstn), .start(start),
        .slot_valid(slot_valid), .slot_j_flat(slot_j_flat), .j_window_flat(j_window_flat),
        .busy(ref_busy), .done(ref_done), .policy_error(ref_error),
        .source_j(ref_source), .next_count(ref_count), .next_j_flat(ref_next),
        .root_cost(ref_cost), .root_segment_count(ref_segments), .policy_epoch(ref_epoch)
    );

    reg [15:0] observed_seed_ids [0:8];
    reg [2:0] observed_seed_count [0:8];
    reg [2:0] observed_seed_segments [0:8];
    reg observed_seed_valid [0:8];
    integer cases = 0;
    integer errors = 0;
    integer skips = 0;
    integer nested_skips = 0;
    integer seed_hits = 0;
    integer seed_misses = 0;
    integer canonical_misses = 0;
    integer root_equal_bounds = 0;
    integer skip_during_miss = 0;
    integer max_universe = 0;
    integer checked_bounds = 0;
    integer checked_cached_bounds = 0;
    integer max_pruned_batch = 0;
    integer max_scan_count = 0;
    integer root_certificates=0, inner_certificates=0, exact_suffixes=0;
    integer overlapped_reads=0, scan_lane, pick;
    reg [127:0] scan_held;
    reg [31:0] bound_packet;
    integer lane;
    integer cached_index;
    reg [31:0] cached_packet;
    reg case_forced = 1'b0;
    integer depth;
    integer ci, si, wi, count, value, previous;
    reg duplicate;
    reg [31:0] rng = 32'h385f1a93;
    reg [27:0] generated_slots;
    reg [3:0] generated_valid;
    reg [62:0] generated_window;
    integer bound_expected [0:2][0:SCAN_LANES-1];

    function integer sequential_held_cost;
        input [127:0] initial_held;
        reg [127:0] held,pool;
        integer p,q,request_value,source_value;
        begin
            held=initial_held; pool=0; sequential_held_cost=0;
            for (q=0; q<=H_FUTURE; q=q+1) pool[dut.req_val[q]]=1'b1;
            for (q=dut.a_req_idx+1; q<=H_FUTURE; q=q+1) begin
                request_value=dut.req_val[q]; source_value=0;
                for (p=0; p<=request_value; p=p+1) if (held[p]) source_value=p;
                sequential_held_cost=sequential_held_cost+request_value-source_value;
                held[request_value]=1'b1;
                for (p=source_value+1; p<request_value; p=p+1) if (pool[p]) held[p]=1'b1;
            end
        end
    endfunction

    function integer sequential_tail_cost;
        input [2:0] child_count;
        input [15:0] child_ids;
        reg [127:0] held, pool;
        integer p, q, request_value, source_value;
        begin
            held = 128'd0; pool = 128'd0;
            if (child_count > 0) held[dut.univ_val[child_ids[3:0]]] = 1'b1;
            if (child_count > 1) held[dut.univ_val[child_ids[7:4]]] = 1'b1;
            if (child_count > 2) held[dut.univ_val[child_ids[11:8]]] = 1'b1;
            if (child_count > 3) held[dut.univ_val[child_ids[15:12]]] = 1'b1;
            for (q=0; q<=H_FUTURE; q=q+1) pool[dut.req_val[q]] = 1'b1;
            sequential_tail_cost = 0;
            for (q=dut.a_req_idx+1; q<=H_FUTURE; q=q+1) begin
                request_value = dut.req_val[q]; source_value = 0;
                for (p=0; p<=request_value; p=p+1)
                    if (held[p]) source_value = p;
                sequential_tail_cost = sequential_tail_cost + request_value-source_value;
                held[request_value] = 1'b1;
                for (p=source_value+1; p<request_value; p=p+1)
                    if (pool[p]) held[p] = 1'b1;
            end
        end
    endfunction

    function [31:0] random_word;
        input [31:0] state;
        reg [31:0] x;
        begin
            x = state ^ (state << 13);
            x = x ^ (x >> 17);
            random_word = x ^ (x << 5);
        end
    endfunction

    always @(posedge clk) begin
        if (rstn && start && !busy) case_forced = 1'b0;
        if (rstn && busy) begin
            if (dut.cache_write_en && dut.a_cache_count+dut.scan_output_count>max_scan_count)
                max_scan_count=dut.a_cache_count+dut.scan_output_count;
            if (dut.fsm_state==dut.ST_PREP && dut.prep_two_left) exact_suffixes=exact_suffixes+1;
            if (dut.cache_read_en && dut.cache_walk_fire) overlapped_reads=overlapped_reads+1;
            if ((dut.fsm_state==dut.ST_RETURN_EVAL && dut.a_phase==dut.PH_SEED && dut.seed_return_optimal) ||
                (dut.fsm_state==dut.ST_RUN && dut.a_phase==dut.PH_SEED && dut.mresp_valid &&
                 dut.memo_pipe_hit && dut.seed_hit_optimal)) begin
                if (dut.sp==0) root_certificates=root_certificates+1;
                else inner_certificates=inner_certificates+1;
            end
            if (dut.fsm_state==dut.ST_BUILD && dut.build_idx==0 && dut.early_root_single)
                case_forced=1'b1;
            if (dut.univ_count > max_universe) max_universe = dut.univ_count;
            for (scan_lane=0; scan_lane<SCAN_LANES; scan_lane=scan_lane+1) begin
                bound_packet=dut.scan_packets[32*scan_lane +: 32];
                if (dut.bo_mask[scan_lane] && !dut.bp_flush) begin
                    checked_bounds=checked_bounds+1;
                    if (bound_packet[10:0] !== bound_expected[2][scan_lane])
                        $fatal(1,"bound mismatch case=%0d depth=%0d lane=%0d got=%0d expected=%0d",
                               cases+1,dut.sp,scan_lane,bound_packet[10:0],bound_expected[2][scan_lane]);
                end
                bound_expected[2][scan_lane]=bound_expected[1][scan_lane];
                bound_expected[1][scan_lane]=bound_expected[0][scan_lane];
                if (dut.scan_issue_mask[scan_lane]) begin
                    scan_held=0;
                    scan_held[dut.univ_val[dut.a_ctx_jid]]=1'b1;
                    for (pick=0; pick<9; pick=pick+1)
                        if (dut.scan_iterator[scan_lane][2+pick])
                            scan_held[dut.univ_val[dut.a_ctx_extra_ids[4*pick +: 4]]]=1'b1;
                    for (pick=0; pick<4; pick=pick+1)
                        if (dut.scan_iterator[scan_lane][14+pick])
                            scan_held[dut.univ_val[dut.a_ctx_keep_ids[4*pick +: 4]]]=1'b1;
                    bound_expected[0][scan_lane]=sequential_held_cost(scan_held);
                end
            end
            depth = dut.sp;
            if (dut.fsm_state == dut.ST_PREP)
                observed_seed_valid[depth] = 1'b0;
            if (dut.seed_issue_from_scan && dut.fsm_state == dut.ST_RUN) begin
                observed_seed_ids[depth] = dut.seed_issue_ids;
                observed_seed_count[depth] = dut.seed_issue_count;
                observed_seed_segments[depth] = dut.seed_issue_seg;
                observed_seed_valid[depth] = 1'b1;
            end
            if (dut.fsm_state==dut.ST_RUN && dut.a_phase==dut.PH_CANON && dut.bound_capture)
                $fatal(1,"canonical replay recomputed a bound");
            if (dut.cache_walk_fire) begin
                if (dut.cache_pruned_count>max_pruned_batch) max_pruned_batch=dut.cache_pruned_count;
                for (lane=0; lane<CANON_LANES; lane=lane+1) begin
                    cached_packet=dut.cache_rd_data[32*lane +: 32];
                    cached_index=dut.cache_group_base+lane;
                    if (cached_index>=dut.a_cache_next && cached_index<dut.a_cache_count) begin
                        checked_cached_bounds=checked_cached_bounds+1;
                        if (cached_packet[10:0] !== sequential_tail_cost(cached_packet[31:29],cached_packet[28:13]))
                            $fatal(1,"cached bound mismatch case=%0d depth=%0d index=%0d",cases+1,depth,cached_index);
                        if (depth==0 && dut.root_best_valid &&
                            cached_packet[10:0]+dut.a_ctx_imm==dut.root_best_cost)
                            root_equal_bounds=root_equal_bounds+1;
                    end
                    if (dut.cache_seed_mask[lane]) begin
                        skips=skips+1;
                        if (depth!=0) nested_skips=nested_skips+1;
                        if (!observed_seed_valid[depth] ||
                            cached_packet[31:29] !== observed_seed_count[depth] ||
                            cached_packet[28:13] !== observed_seed_ids[depth] ||
                            ({1'b0,cached_packet[12:11]}+1'b1) !== observed_seed_segments[depth])
                            $fatal(1,"wrong cached seed skip case=%0d depth=%0d",cases+1,depth);
                    end
                end
            end
            if (dut.seed_issue_from_bound && observed_seed_valid[depth] &&
                dut.seed_issue_ids==observed_seed_ids[depth] &&
                dut.seed_issue_count==observed_seed_count[depth] &&
                dut.seed_issue_seg==observed_seed_segments[depth]) begin
                $fatal(1,"seed was sent to memo a second time");
            end
            if (dut.fsm_state == dut.ST_RUN && dut.mresp_valid) begin
                if (dut.a_phase == dut.PH_SEED) begin
                    if (dut.memo_pipe_hit) seed_hits = seed_hits + 1;
                    else seed_misses = seed_misses + 1;
                end else if (!dut.memo_pipe_hit)
                    canonical_misses = canonical_misses + 1;
            end
        end
    end

    task run_case;
        input [3:0] valid;
        input [27:0] slots;
        input [62:0] window_values;
        integer timeout;
        reg seen_dut, seen_ref;
        begin
            @(negedge clk);
            slot_valid = valid; slot_j_flat = slots; j_window_flat = window_values;
            start = 1'b1;
            @(negedge clk); start = 1'b0;
            seen_dut = 1'b0; seen_ref = 1'b0; timeout = 0;
            while (!(seen_dut && seen_ref) && timeout < 1000000) begin
                @(negedge clk);
                if (done) seen_dut = 1'b1;
                if (ref_done) seen_ref = 1'b1;
                timeout = timeout + 1;
            end
            cases = cases + 1;
            if (!(seen_dut && seen_ref)) $fatal(1, "timeout case=%0d", cases);
            if (policy_error || ref_error || source_j !== ref_source ||
                next_count !== ref_count || next_j_flat !== ref_next ||
                segments !== ref_segments || (!case_forced && root_cost !== ref_cost) ||
                (case_forced && (root_cost>ref_cost || root_cost!=(window_values[6:0]-source_j))) ||
                epoch !== ref_epoch) begin
                $display("ERROR case=%0d source=%0d/%0d next=%h/%h cost=%0d/%0d seg=%0d/%0d",
                         cases, source_j, ref_source, next_j_flat, ref_next,
                         root_cost, ref_cost, segments, ref_segments);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        for (si=0; si<9; si=si+1) observed_seed_valid[si] = 1'b0;
        repeat (5) @(negedge clk);
        rstn = 1'b1;
        run_case(4'b0111, {7'd0,7'd11,7'd7,7'd2}, {35'd0,7'd2,7'd11,7'd7,7'd5});
        run_case(4'b0101, {7'd0,7'd9,7'd0,7'd2}, {35'd0,7'd2,7'd8,7'd4,7'd8});
        run_case(4'b1011, {7'd0,7'd0,7'd126,7'd127}, {35'd0,7'd0,7'd127,7'd126,7'd127});
        if (CKPT_K == 4 && H_FUTURE == 8)
            run_case(4'b1111, {7'd19,7'd13,7'd7,7'd2},
                     {7'd54,7'd48,7'd42,7'd36,7'd30,7'd24,7'd18,7'd12,7'd5});
        if (CKPT_K == 4 && H_FUTURE == 8)
            // Eight optional deposits plus four retainable old checkpoints:
            // 220 root actions exercise all banks and many cache groups.
            run_case(4'b1111, {7'd120,7'd100,7'd95,7'd91},
                     {7'd63,7'd45,7'd31,7'd19,7'd11,7'd7,7'd3,7'd1,7'd90});
        // Generate legal, unsorted physical slots independently of action
        // generation. Repeated future requests force cost and tuple ties.
        for (ci=0; ci<RANDOM_CASES; ci=ci+1) begin
            rng = random_word(rng); count = rng % (CKPT_K+1);
            generated_valid = 4'd0; generated_slots = 28'd0;
            for (si=0; si<count; si=si+1) begin
                duplicate = 1'b1;
                while (duplicate) begin
                    rng = random_word(rng); value = rng % 128;
                    duplicate = 1'b0;
                    for (previous=0; previous<si; previous=previous+1)
                        if (generated_slots[7*previous +: 7] == value)
                            duplicate = 1'b1;
                end
                generated_valid[si] = 1'b1;
                generated_slots[7*si +: 7] = value[6:0];
            end
            if ((ci % 2) == 0) begin
                generated_valid = {generated_valid[0],generated_valid[3:1]};
                generated_slots = {generated_slots[6:0],generated_slots[27:7]};
            end
            generated_window = 63'd0;
            for (wi=0; wi<=H_FUTURE; wi=wi+1) begin
                rng = random_word(rng);
                generated_window[7*wi +: 7] = ((ci % 5) == 0) ? 7'd7 : rng[6:0];
            end
            run_case(generated_valid, generated_slots, generated_window);
        end
        if (REQUIRE_COVERAGE && (root_certificates==0 || seed_misses==0 ||
            (H_FUTURE>=3 && (inner_certificates==0 || exact_suffixes==0))))
            $fatal(1,"missing root/internal certificate or exact suffix coverage");
        if (CKPT_K == 4 && H_FUTURE == 8 && max_universe != 13)
            $fatal(1, "largest-universe integration case was not exercised");
        if (CKPT_K == 4 && H_FUTURE == 8 && max_scan_count<220)
            $fatal(1,"large SCAN cache address/bank case was not exercised");
        $display("SUMMARY seed_replay cases=%0d errors=%0d skips=%0d nested=%0d seed_hits=%0d seed_misses=%0d canonical_misses=%0d root_equal_bounds=%0d skip_during_miss=%0d max_universe=%0d checked_bounds=%0d cached_bounds=%0d max_pruned_batch=%0d max_scan_count=%0d",
                 cases, errors, skips, nested_skips, seed_hits, seed_misses,
                 canonical_misses, root_equal_bounds, skip_during_miss, max_universe, checked_bounds,
                 checked_cached_bounds,max_pruned_batch,max_scan_count);
        $display("CERTIFICATES root=%0d inner=%0d suffix=%0d overlapped_reads=%0d scan_lanes=%0d",
                 root_certificates,inner_certificates,exact_suffixes,overlapped_reads,SCAN_LANES);
        if (errors != 0) $fatal(1, "seed replay regression failed");
        $finish;
    end
endmodule
