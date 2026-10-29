`timescale 1ns/1ps
`include "grover_param.vh"

// Compare every BUILD bandwidth against the established single-row Born
// sampler.  Use independent synchronous amplitude responses and identical RNG
// streams; compare total W, rejection threshold, draw count and chosen index.
// Cases exercise zero weight, W=1, group boundaries, the final partial M3
// packet, saturation-sized amplitudes and repeated starts without reset.
module tb_measure_build_rows;
    reg clk=0;
    always #5 clk=~clk;
    reg rstn=0, start=0;
    integer pattern=0;
    localparam integer CONFIGS=11;
    wire [CONFIGS-1:0] done;
    reg [CONFIGS-1:0] finished=0;
    wire [59:0] weight[0:CONFIGS-1], threshold[0:CONFIGS-1];
    wire [13:0] candidate[0:CONFIGS-1];
    wire [CONFIGS-1:0] zero_error;
    integer draws[0:CONFIGS-1];
    integer latency[0:CONFIGS-1];
    integer ticks=0;

    function automatic [31:0] next_rng(input [31:0] s);
        next_rng={s[30:0],s[31]^s[21]^s[1]^s[0]};
    endfunction
    function automatic signed [22:0] amplitude(input integer row, lane);
        integer index, mixed;
        begin
            index=row*32+lane;
            mixed=(index*7919+17) % 100003;
            case (pattern)
                0: amplitude=0;
                1: amplitude=(index==16383) ? 1 : 0;
                2: amplitude=32768;
                3: amplitude=((row==31)||(row==32)||(row==63)||
                              (row==64)||(row==510)||(row==511)) ? mixed-50001 : 0;
                4: amplitude=(index%3==0) ? 23'sd4194303 : -23'sd4194303;
                default: amplitude=mixed-50001;
            endcase
        end
    endfunction
    function automatic [32*23-1:0] row_data(input integer row);
        integer lane;
        begin
            for (lane=0;lane<32;lane=lane+1)
                row_data[lane*23 +: 23]=amplitude(row,lane);
        end
    endfunction

    genvar g;
    generate for (g=0;g<CONFIGS;g=g+1) begin : sampler
        wire rd_en, quad_en, rnd_draw;
        wire [8:0] rd_row;
        wire [6:0] quad_index;
        reg [735:0] single_data=0;
        reg [735:0] quad_data[0:3];
        reg single_d=0, quad_d=0, quad_valid=0;
        reg [8:0] row_d=0;
        reg [6:0] index_d=0;
        reg [31:0] rng=32'hBEEF_C0DE;
        integer i;
        always @(posedge clk) begin
            single_d<=rd_en;
            quad_d<=quad_en;
            if (rd_en) row_d<=rd_row;
            if (quad_en) index_d<=quad_index;
            if (single_d) single_data<=row_data(row_d);
            quad_valid<=quad_d;
            if (quad_d)
                for (i=0;i<4;i=i+1) quad_data[i]<=row_data(index_d*4+i);
            if (!rstn) begin
                rng<=32'hBEEF_C0DE;
                draws[g]<=0;
            end else if (rnd_draw) begin
                rng<=next_rng(rng);
                draws[g]<=draws[g]+1;
            end
            if (done[g]) begin
                finished[g]<=1;
                latency[g]<=ticks;
            end else if (start) finished[g]<=0;
        end
        if(g<4) begin : legacy
        grover_born_sampler #(
            .AMP_READ_LATENCY(2), .E4_DUAL_BUILD(g>=1),
            .E4_TRIPLE_BUILD(g==2), .E4_QUAD_BUILD(g==3),
            .E4_HIER_SELECT(g>=1)
        ) dut (
            .clk(clk), .rstn(rstn), .start(start), .rnd(rng), .rnd_draw(rnd_draw),
            .amp_rdata(single_data), .amp_rd_row(rd_row), .amp_rd_en(rd_en),
            .amp_quad0(quad_data[0]), .amp_quad1(quad_data[1]),
            .amp_quad2(quad_data[2]), .amp_quad3(quad_data[3]),
            .amp_quad_valid(quad_valid), .amp_quad_rd_index(quad_index),
            .amp_quad_rd_en(quad_en), .busy(), .done(done[g]),
            .zero_weight_error(zero_error[g]), .candidate(candidate[g]),
            .total_weight(weight[g]), .threshold(threshold[g]), .selected_row()
        );
        end else begin : expanded
            localparam integer M=g+1;
            wire [M-1:0] enables;
            wire [M*9-1:0] rows;
            reg [M-1:0] enables1=0,enables2=0;
            reg [M*736-1:0] data1=0,data2=0;
            always @(posedge clk) begin
                enables1<=enables;enables2<=enables1;
                for(integer lane=0;lane<M;lane=lane+1)
                    if(enables[lane]) data1[lane*736+:736]<=row_data(rows[lane*9+:9]);
                data2<=data1;
            end
            // The legacy response path above remains idle for this client.
            assign rd_en=0;assign rd_row=0;assign quad_en=0;assign quad_index=0;
            grover_born_sampler_parallel #(.SQUARE_ENGINES(M)) dut (
                .clk(clk),.rstn(rstn),.start(start),.rnd(rng),.rnd_draw(rnd_draw),
                .rd_en(enables),.rd_rows(rows),.amp_data(data2),.amp_valid(enables2),
                .busy(),.done(done[g]),.zero_weight_error(zero_error[g]),
                .candidate(candidate[g]),.total_weight(weight[g]),.threshold(threshold[g]),.selected_row()
            );
        end
    end endgenerate

    integer p, s;
    initial begin
        repeat(4) @(negedge clk);
        rstn=1;
        for (p=0;p<6;p=p+1) begin
            pattern=p;
            ticks=0;
            start=1;
            @(negedge clk);
            start=0;
            while (finished!={CONFIGS{1'b1}}) begin
                @(negedge clk);
                ticks=ticks+1;
                if (ticks>5000) $fatal(1,"sampler timeout pattern=%0d",p);
            end
            for (s=1;s<CONFIGS;s=s+1)
                if (weight[s]!==weight[0] || zero_error[s]!==zero_error[0] ||
                    draws[s]!=draws[0] ||
                    (p!=0 && (threshold[s]!==threshold[0] || candidate[s]!==candidate[0])))
                    $fatal(1,"Born mismatch pattern=%0d rows=%0d W=%0d/%0d idx=%0d/%0d",p,s+1,
                           weight[s],weight[0],candidate[s],candidate[0]);
            if (latency[3]>=latency[2]) $fatal(1,"M4 did not reduce latency");
            $display("PASS pattern=%0d W=%0d candidate=%0d latencies=%0d,%0d,%0d,%0d",
                     p,weight[0],candidate[0],latency[0],latency[1],latency[2],latency[3]);
            repeat(4) @(negedge clk);
        end
        $display("PASS BUILD_ROWS=1..11 bit-exact Born equivalence cases=66 errors=0");
        $finish;
    end
endmodule
