//==============================================================================
// grover_measurement.v -- BBHT/Grover Main IP + E4 Measurement M2
//
// File-level consolidation is preserved; module hierarchy is unchanged.
// v0.7f retains the v0.7e Born-square DSP-input and 32-lane square
// reduction tree for routed 100-MHz timing closure. Exact Born arithmetic,
// rejection/CDF semantics, lane ordering, and PRNG order are preserved.
// Consolidated from: grover_born_square32.v, grover_born_reject64.v, grover_born_sampler.v, grover_verify.v, grover_measure_verify.v
//==============================================================================


//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_born_square32.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_born_square32.v -- BBHT/Grover Main IP v0.7e
//
// 32-lane exact Born-square pipeline with routed-timing closure.
//
// Routed v0.7d timing showed two independent critical paths inside this block:
//   (1) amp_mem BRAM -> 23x23 DSP square -> sq1/PREG
//       ~10.4 ns data path
//   (2) sq1/PREG -> full 32-lane reduction tree -> row_sum register
//       ~11.2 ns data path, design WNS ~ -1.199 ns
//
// v0.7e adds TWO latency-only timing boundaries:
//   Stage A : amp_mem data -> amp0 input REG
//   Stage B : amp0 -> 23x23 DSP square -> sq1 REG/PREG
//   Stage C : reduction 32->16->8 -> part2 REG
//   Stage D : reduction 8->4->2->1 -> row_sum REG
//
// The reduction tree uses only the exact mathematically-required width at each
// level (47/48/49/50/51 bits). No truncation, rounding, normalization, lane
// reordering, or probability change is introduced.
//
// out_sq/out_row/out_valid are delayed with the same transaction so the external
// sampler contract stays unchanged. Throughput remains one row per clock after
// pipeline fill. The sampler FSM does NOT need a fixed-cycle edit because it
// already waits on sq_valid for both BUILD completion and selected-row reread.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_born_square32 (
    input  wire                                  clk,
    input  wire                                  rstn,
    input  wire                                  in_valid,
    input  wire [`GP_ROW_W-1:0]                  in_row,
    input  wire [`GP_P*`GP_AMP_W-1:0]            in_amp,
    output wire                                  out_valid,
    output wire [`GP_ROW_W-1:0]                  out_row,
    output wire [`GP_P*`GP_SQUARE_W-1:0]         out_sq,
    output wire [`GP_ROW_SUM_W-1:0]              out_row_sum
);
    localparam integer P   = `GP_P;          // 32
    localparam integer AW  = `GP_AMP_W;      // 23
    localparam integer SQW = `GP_SQUARE_W;   // 46
    localparam integer RSW = `GP_ROW_SUM_W;  // 51

    // Exact reduction widths:
    //   32 leaves x 46b
    //   32->16 : 47b
    //   16-> 8 : 48b   <-- timing cut/register here
    //    8-> 4 : 49b
    //    4-> 2 : 50b
    //    2-> 1 : 51b
    localparam integer L1W = SQW + 1;
    localparam integer L2W = SQW + 2;
    localparam integer L3W = SQW + 3;
    localparam integer L4W = SQW + 4;
    localparam integer L5W = SQW + 5;

    // Pipeline valid/tag chain.
    reg v0, v1, v2, v3;
    reg [`GP_ROW_W-1:0] row0, row1, row2, row3;

    // Stage A: explicit registered DSP input transaction.
    // Vivado may legally absorb these lane registers into DSP48E1 AREG/BREG;
    // that is desirable and still preserves this clock boundary.
    reg [P*AW-1:0] amp0;

    // Stage B: exact per-lane squares. Vivado previously mapped this registered
    // result into DSP48E1 PREG, which is also desirable.
    reg [P*SQW-1:0] sq1;

    // Delay all lane squares so out_sq remains aligned with the final row sum.
    reg [P*SQW-1:0] sq2;
    reg [P*SQW-1:0] sq3;

    // Stage C timing cut: 8 exact partial sums after two reduction levels.
    reg [8*L2W-1:0] part2_reg;

    // Stage D output row sum.
    reg [RSW-1:0] row_sum3;

    // ------------------------------------------------------------------------
    // Front half of reduction tree: 32 -> 16 -> 8
    // ------------------------------------------------------------------------
    wire [16*L1W-1:0] level1_bus;
    wire [ 8*L2W-1:0] level2_bus;

    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g_red_l1
            wire [SQW-1:0] a;
            wire [SQW-1:0] b;
            assign a = sq1[(2*i  )*SQW +: SQW];
            assign b = sq1[(2*i+1)*SQW +: SQW];
            assign level1_bus[i*L1W +: L1W] =
                {1'b0, a} + {1'b0, b};
        end

        for (i = 0; i < 8; i = i + 1) begin : g_red_l2
            wire [L1W-1:0] a;
            wire [L1W-1:0] b;
            assign a = level1_bus[(2*i  )*L1W +: L1W];
            assign b = level1_bus[(2*i+1)*L1W +: L1W];
            assign level2_bus[i*L2W +: L2W] =
                {1'b0, a} + {1'b0, b};
        end
    endgenerate

    // ------------------------------------------------------------------------
    // Back half of reduction tree: 8 -> 4 -> 2 -> 1
    // ------------------------------------------------------------------------
    wire [4*L3W-1:0] level3_bus;
    wire [2*L4W-1:0] level4_bus;
    wire [  L5W-1:0] level5_sum;

    generate
        for (i = 0; i < 4; i = i + 1) begin : g_red_l3
            wire [L2W-1:0] a;
            wire [L2W-1:0] b;
            assign a = part2_reg[(2*i  )*L2W +: L2W];
            assign b = part2_reg[(2*i+1)*L2W +: L2W];
            assign level3_bus[i*L3W +: L3W] =
                {1'b0, a} + {1'b0, b};
        end

        for (i = 0; i < 2; i = i + 1) begin : g_red_l4
            wire [L3W-1:0] a;
            wire [L3W-1:0] b;
            assign a = level3_bus[(2*i  )*L3W +: L3W];
            assign b = level3_bus[(2*i+1)*L3W +: L3W];
            assign level4_bus[i*L4W +: L4W] =
                {1'b0, a} + {1'b0, b};
        end
    endgenerate

    assign level5_sum =
        {1'b0, level4_bus[0*L4W +: L4W]} +
        {1'b0, level4_bus[1*L4W +: L4W]};

    integer k;
    reg signed [AW-1:0]  amp_k;
    reg signed [SQW-1:0] prod_k;

    always @(posedge clk) begin
        if (!rstn) begin
            v0        <= 1'b0;
            v1        <= 1'b0;
            v2        <= 1'b0;
            v3        <= 1'b0;
            row0      <= {`GP_ROW_W{1'b0}};
            row1      <= {`GP_ROW_W{1'b0}};
            row2      <= {`GP_ROW_W{1'b0}};
            row3      <= {`GP_ROW_W{1'b0}};
            amp0      <= {(P*AW){1'b0}};
            sq1       <= {(P*SQW){1'b0}};
            sq2       <= {(P*SQW){1'b0}};
            sq3       <= {(P*SQW){1'b0}};
            part2_reg <= {(8*L2W){1'b0}};
            row_sum3  <= {RSW{1'b0}};
        end else begin
            // Stage A: register BRAM output transaction before the DSPs.
            v0 <= in_valid;
            if (in_valid) begin
                row0 <= in_row;
                amp0 <= in_amp;
            end

            // Stage B: 32 exact 23x23 squares, registered at DSP output/PREG.
            v1 <= v0;
            if (v0) begin
                row1 <= row0;
                for (k = 0; k < P; k = k + 1) begin
                    amp_k  = $signed(amp0[k*AW +: AW]);
                    prod_k = amp_k * amp_k;
                    sq1[k*SQW +: SQW] <= prod_k;
                end
            end

            // Stage C: first two reduction levels, then explicit timing cut.
            v2 <= v1;
            if (v1) begin
                row2      <= row1;
                sq2       <= sq1;
                part2_reg <= level2_bus;
            end

            // Stage D: remaining three reduction levels and aligned lane output.
            v3 <= v2;
            if (v2) begin
                row3     <= row2;
                sq3      <= sq2;
                row_sum3 <= level5_sum;
            end
        end
    end

    assign out_valid   = v3;
    assign out_row     = row3;
    assign out_sq      = sq3;
    assign out_row_sum = row_sum3;
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_born_square32.v
//------------------------------------------------------------------------------
// END preserved module source: grover_born_square32.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_born_reject64.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_born_reject64.v -- v0.7 registered Born rejection mapper
//
// Purpose
//   This block is the actual timing-closed rejection datapath used by
//   grover_born_sampler.  It is no longer a disconnected reference-only module.
//
// Exact algorithmic contract
//   W = 0 : zero_weight=1
//   W = 1 : direct_one=1, threshold is handled by caller as r=0 with NO draw
//   W > 1 : k = bit_length(W-1)
//           candidate = low-k bits of rnd64
//           accept iff candidate < W
//
// Timing-closure structure
//   load_weight edge:
//       total_weight -> (W-1) -> bit_length -> k_bits REG
//
//   map_candidate edge:
//       registered k_bits + rnd64 -> exact low-k selector -> candidate REG
//
//   following cycle:
//       registered candidate < stable total_weight -> accept
//
// This replaces the pre-v0.7 arithmetic dynamic mask
//     (64'h1 << k) - 1
// with the bit-exact low-k selector.  It is a 100-MHz timing retime only;
// random mapping, rejection distribution, and SW-Golden-visible values do not
// change.  The sampler controls exactly when the two register boundaries fire.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_born_reject64 (
    input  wire                                  clk,
    input  wire                                  rstn,

    // Pulse in the sampler's S_CHECK_W cycle. W is stable for all retries.
    input  wire                                  load_weight,

    // Pulse after the sampler has collected one complete HI->LO rnd64 pair.
    input  wire                                  map_candidate,

    input  wire [`GP_TOTAL_WEIGHT_W-1:0]         total_weight,
    input  wire [63:0]                           rnd64,

    output reg  [5:0]                            k_bits,
    output reg  [`GP_TOTAL_WEIGHT_W-1:0]         candidate,
    output wire                                  accept,
    output wire                                  direct_one,
    output wire                                  zero_weight
);
    localparam integer TW = `GP_TOTAL_WEIGHT_W;

    reg [5:0]    k_comb;
    reg [TW-1:0] candidate_comb;
    reg [TW-1:0] w_minus1;
    integer k_i;
    integer map_i;

    // Stage A: k = bit_length(W-1). Captured only on load_weight.
    always @* begin
        k_comb   = 6'd0;
        w_minus1 = {TW{1'b0}};

        if (total_weight > {{(TW-1){1'b0}},1'b1}) begin
            w_minus1 = total_weight - {{(TW-1){1'b0}},1'b1};
            for (k_i = 0; k_i < TW; k_i = k_i + 1) begin
                if (w_minus1[k_i])
                    k_comb = k_i + 1;
            end
        end
    end

    // Stage B: exact low-k selection. No arithmetic dynamic-mask carry chain.
    always @* begin
        candidate_comb = {TW{1'b0}};
        for (map_i = 0; map_i < TW; map_i = map_i + 1) begin
            if (map_i < k_bits)
                candidate_comb[map_i] = rnd64[map_i];
        end
    end

    always @(posedge clk) begin
        if (!rstn) begin
            k_bits   <= 6'd0;
            candidate <= {TW{1'b0}};
        end else begin
            if (load_weight)
                k_bits <= k_comb;

            if (map_candidate)
                candidate <= candidate_comb;
        end
    end

    assign zero_weight = (total_weight == {TW{1'b0}});
    assign direct_one  = (total_weight == {{(TW-1){1'b0}},1'b1});

    // W=1 is architecturally accepted without a random draw by the caller.
    // Keeping direct_one in accept preserves the standalone module contract.
    assign accept = direct_one ||
                    ((total_weight > {{(TW-1){1'b0}},1'b1}) &&
                     (candidate < total_weight));
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_born_reject64.v
//------------------------------------------------------------------------------

//==============================================================================
// grover_row_weight_mem_m1_2w -- E4 measurement M1 helper
//
// Two writes/cycle for consecutive even/odd rows, one sequential read/cycle for
// the unchanged baseline ROW_SCAN.  The 512x51 logical array is banked by row
// parity into 2x(256x51).  Exact row-weight contents and scan semantics are
// unchanged; only BUILD write bandwidth is doubled.
//==============================================================================
module grover_row_weight_mem_m1_2w (
    input  wire                          clk,
    input  wire                          rd_en,
    input  wire [`GP_ROW_W-1:0]          rd_row,
    output wire [`GP_ROW_SUM_W-1:0]      rd_weight,

    input  wire                          wr0_en,
    input  wire [`GP_ROW_W-1:0]          wr0_row,
    input  wire [`GP_ROW_SUM_W-1:0]      wr0_weight,
    input  wire                          wr1_en,
    input  wire [`GP_ROW_W-1:0]          wr1_row,
    input  wire [`GP_ROW_SUM_W-1:0]      wr1_weight
);
    localparam integer RSW = `GP_ROW_SUM_W;
    localparam integer BW  = `GP_ROW_W - 1;

    (* ram_style = "block" *) reg [RSW-1:0] mem_even [0:(`GP_ROWS/2)-1];
    (* ram_style = "block" *) reg [RSW-1:0] mem_odd  [0:(`GP_ROWS/2)-1];

    reg [RSW-1:0] rd_even_q;
    reg [RSW-1:0] rd_odd_q;
    reg           rd_bank_d;

    wire wr_even_en = (wr0_en && !wr0_row[0]) || (wr1_en && !wr1_row[0]);
    wire wr_odd_en  = (wr0_en &&  wr0_row[0]) || (wr1_en &&  wr1_row[0]);

    wire [BW-1:0] wr_even_addr = (wr0_en && !wr0_row[0]) ?
                                      wr0_row[`GP_ROW_W-1:1] :
                                      wr1_row[`GP_ROW_W-1:1];
    wire [BW-1:0] wr_odd_addr  = (wr0_en &&  wr0_row[0]) ?
                                      wr0_row[`GP_ROW_W-1:1] :
                                      wr1_row[`GP_ROW_W-1:1];

    wire [RSW-1:0] wr_even_data = (wr0_en && !wr0_row[0]) ?
                                      wr0_weight : wr1_weight;
    wire [RSW-1:0] wr_odd_data  = (wr0_en &&  wr0_row[0]) ?
                                      wr0_weight : wr1_weight;

    always @(posedge clk) begin
        if (rd_en) begin
            rd_even_q <= mem_even[rd_row[`GP_ROW_W-1:1]];
            rd_odd_q  <= mem_odd [rd_row[`GP_ROW_W-1:1]];
            rd_bank_d <= rd_row[0];
        end

        if (wr_even_en)
            mem_even[wr_even_addr] <= wr_even_data;
        if (wr_odd_en)
            mem_odd[wr_odd_addr] <= wr_odd_data;
    end

    assign rd_weight = rd_bank_d ? rd_odd_q : rd_even_q;
endmodule

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_born_sampler.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_born_sampler.v -- Row->Lane Born + E4 M1/M2 hierarchical measurement
//
// Baseline flow:
//   1) Scan all 512 amplitude rows read-only.
//      32x |amp|^2 -> row_sum -> row_weight[512], total W.
//   2) W=0 : terminal zero_weight_error.
//      W=1 : threshold r=0 directly, no random draw.
//      W>1 : consume two LFSR_MEAS draws (hi->lo), apply dynamic-width
//            rejection; reject consumes a new complete pair.
//   3) E4 M2 hierarchical scan: BUILD also records the exact global CDF at
//      each 32-row group boundary (16 groups total). Measurement first finds
//      the FIRST group endpoint > r, then scans only that group in the existing
//      row_weight memory. Legacy mode keeps the full 512-row scan.
//      local_r = r - cumulative_before_selected_row.
//   4) Read only the selected amplitude row, square its 32 lanes, and choose
//      the FIRST lane cumulative sum > local_r.
//   5) candidate = {selected_row, selected_lane}.
//
// This block never writes amp_mem.  The external integration must connect the
// read port only and keep amp_mem write enable low during measurement.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_born_sampler #(
    parameter integer AMP_READ_LATENCY = 1,
    parameter integer E4_DUAL_BUILD    = 0,
    parameter integer E4_HIER_SELECT   = 0
) (
    input  wire                                  clk,
    input  wire                                  rstn,
    input  wire                                  start,

    // Measurement PRNG stream. rnd is the CURRENT 32-bit LFSR_MEAS state.
    // rnd_draw advances that stream exactly once.
    input  wire [31:0]                           rnd,
    output wire                                  rnd_draw,

    // Read-only amp_mem port.
    input  wire [`GP_P*`GP_AMP_W-1:0]            amp_rdata,
    output reg  [`GP_ROW_W-1:0]                  amp_rd_row,
    output reg                                   amp_rd_en,

    // E4 M1 BUILD-only quad-read interface.  In E4_DUAL_BUILD mode the
    // sampler requests one four-row checkpoint quad every two clocks and
    // consumes it as two consecutive two-row square transactions.
    input  wire [`GP_P*`GP_AMP_W-1:0]            amp_quad0,
    input  wire [`GP_P*`GP_AMP_W-1:0]            amp_quad1,
    input  wire [`GP_P*`GP_AMP_W-1:0]            amp_quad2,
    input  wire [`GP_P*`GP_AMP_W-1:0]            amp_quad3,
    input  wire                                  amp_quad_valid,
    output wire [6:0]                            amp_quad_rd_index,
    output wire                                  amp_quad_rd_en,

    output wire                                  busy,
    output reg                                   done,
    output reg                                   zero_weight_error,
    output reg  [`GP_INDEX_W-1:0]                candidate,

    // Debug/verification visibility. These are internal-contract values, not
    // required Main-IP external ports.
    output reg  [`GP_TOTAL_WEIGHT_W-1:0]         total_weight,
    output reg  [`GP_TOTAL_WEIGHT_W-1:0]         threshold,
    output reg  [`GP_ROW_W-1:0]                  selected_row
);
    localparam integer P    = `GP_P;
    localparam integer SQW  = `GP_SQUARE_W;
    localparam integer RSW  = `GP_ROW_SUM_W;
    localparam integer TW   = `GP_TOTAL_WEIGHT_W;

    localparam [4:0]
        S_IDLE       = 5'd0,
        S_BUILD      = 5'd1,
        S_CHECK_W    = 5'd2,
        S_RND_HI     = 5'd3,
        S_RND_LO     = 5'd4,
        S_RND_MAP    = 5'd5,
        S_RND_CHECK  = 5'd6,
        S_ROW_SCAN   = 5'd7,
        S_LANE_REQ   = 5'd8,
        S_LANE_WAIT  = 5'd9,
        S_LANE_SCAN  = 5'd10,
        S_FIN        = 5'd11,
        S_ZERO       = 5'd12,
        S_GROUP_SCAN = 5'd13;

    reg [4:0] st;

    //-------------------------------------------------------------------------
    // amp_mem request -> synchronous read alignment
    //-------------------------------------------------------------------------
    reg [`GP_ROW_W:0] amp_issue_count;
    reg               amp_req_valid_d;
    reg [`GP_ROW_W-1:0] amp_req_row_d;
    reg               amp_req_valid_d2;
    reg [`GP_ROW_W-1:0] amp_req_row_d2;

    // Baseline grover_amp_mem returns one cycle after request.  The packed
    // checkpoint memory adds a registered source-select stage and therefore
    // returns two cycles after request.  Keep legacy latency as the default.
    wire amp_sq_in_valid = (AMP_READ_LATENCY == 2) ? amp_req_valid_d2
                                                   : amp_req_valid_d;
    wire [`GP_ROW_W-1:0] amp_sq_in_row = (AMP_READ_LATENCY == 2) ? amp_req_row_d2
                                                                 : amp_req_row_d;

    // Shared square datapath.  Legacy mode is unchanged.  E4 M1 uses two
    // identical square32 engines during BUILD and reuses engine0 only for the
    // selected-row lane reread.
    wire                          sq0_valid;
    wire [`GP_ROW_W-1:0]          sq0_row;
    wire [P*SQW-1:0]              sq0_lane;
    wire [RSW-1:0]                sq0_row_sum;

    wire                          sq1_valid;
    wire [`GP_ROW_W-1:0]          sq1_row;
    wire [P*SQW-1:0]              sq1_lane;
    wire [RSW-1:0]                sq1_row_sum;

    // E4 quad stream scheduler.  Requests are issued every other BUILD cycle.
    // The four returned rows are consumed as {0,1} then buffered {2,3}.
    reg [7:0] e4_quad_issue_count;
    reg [7:0] e4_quad_resp_count;
    reg       e4_quad_req_gap;
    reg       e4_hold_valid;
    reg [P*`GP_AMP_W-1:0] e4_hold_amp2;
    reg [P*`GP_AMP_W-1:0] e4_hold_amp3;
    reg [`GP_ROW_W-1:0] e4_hold_row2;
    reg [`GP_ROW_W-1:0] e4_hold_row3;

    assign amp_quad_rd_en = (E4_DUAL_BUILD != 0) &&
                            (st == S_BUILD) &&
                            (e4_quad_issue_count < 8'd128) &&
                            !e4_quad_req_gap;
    assign amp_quad_rd_index = e4_quad_issue_count[6:0];

    wire [`GP_ROW_W-1:0] e4_resp_base_row =
        {e4_quad_resp_count[6:0], 2'b00};

    wire e4_build_pair_valid = (E4_DUAL_BUILD != 0) &&
                               (st == S_BUILD) &&
                               (amp_quad_valid || e4_hold_valid);

    wire [`GP_ROW_W-1:0] e4_pair_row0 = amp_quad_valid ?
        e4_resp_base_row : e4_hold_row2;
    wire [`GP_ROW_W-1:0] e4_pair_row1 = amp_quad_valid ?
        (e4_resp_base_row + {{(`GP_ROW_W-1){1'b0}},1'b1}) : e4_hold_row3;
    wire [P*`GP_AMP_W-1:0] e4_pair_amp0 = amp_quad_valid ?
        amp_quad0 : e4_hold_amp2;
    wire [P*`GP_AMP_W-1:0] e4_pair_amp1 = amp_quad_valid ?
        amp_quad1 : e4_hold_amp3;

    // Legacy/single selected-row alignment remains exact.
    wire lane_sq_in_valid = (AMP_READ_LATENCY == 2) ? amp_req_valid_d2
                                                    : amp_req_valid_d;
    wire [`GP_ROW_W-1:0] lane_sq_in_row = (AMP_READ_LATENCY == 2) ?
                                           amp_req_row_d2 : amp_req_row_d;

    wire sq0_in_valid = (E4_DUAL_BUILD != 0 && st == S_BUILD) ?
                         e4_build_pair_valid : lane_sq_in_valid;
    wire [`GP_ROW_W-1:0] sq0_in_row =
        (E4_DUAL_BUILD != 0 && st == S_BUILD) ? e4_pair_row0 : lane_sq_in_row;
    wire [P*`GP_AMP_W-1:0] sq0_in_amp =
        (E4_DUAL_BUILD != 0 && st == S_BUILD) ? e4_pair_amp0 : amp_rdata;

    wire sq1_in_valid = (E4_DUAL_BUILD != 0) &&
                        (st == S_BUILD) && e4_build_pair_valid;

    grover_born_square32 u_square32 (
        .clk         (clk),
        .rstn        (rstn),
        .in_valid    (sq0_in_valid),
        .in_row      (sq0_in_row),
        .in_amp      (sq0_in_amp),
        .out_valid   (sq0_valid),
        .out_row     (sq0_row),
        .out_sq      (sq0_lane),
        .out_row_sum (sq0_row_sum)
    );

    generate
        if (E4_DUAL_BUILD != 0) begin : g_m1_square1
            grover_born_square32 u_square32_b (
                .clk         (clk),
                .rstn        (rstn),
                .in_valid    (sq1_in_valid),
                .in_row      (e4_pair_row1),
                .in_amp      (e4_pair_amp1),
                .out_valid   (sq1_valid),
                .out_row     (sq1_row),
                .out_sq      (sq1_lane),
                .out_row_sum (sq1_row_sum)
            );
        end else begin : g_no_m1_square1
            assign sq1_valid   = 1'b0;
            assign sq1_row     = {`GP_ROW_W{1'b0}};
            assign sq1_lane    = {(P*SQW){1'b0}};
            assign sq1_row_sum = {RSW{1'b0}};
        end
    endgenerate

    // Backward-compatible aliases used by the unchanged selected-lane path.
    wire                          sq_valid   = sq0_valid;
    wire [`GP_ROW_W-1:0]          sq_row     = sq0_row;
    wire [P*SQW-1:0]              sq_lane    = sq0_lane;
    wire [RSW-1:0]                sq_row_sum = sq0_row_sum;

    //-------------------------------------------------------------------------
    // Row-weight memory
    //-------------------------------------------------------------------------
    wire                         rw_rd_en;
    wire [`GP_ROW_W-1:0]         rw_rd_row;
    wire [RSW-1:0]               rw_rd_weight;

    wire rw_wr0_en = (st == S_BUILD) && sq0_valid;
    wire rw_wr1_en = (st == S_BUILD) && sq1_valid;

    generate
        if (E4_DUAL_BUILD != 0) begin : g_m1_row_weight
            grover_row_weight_mem_m1_2w u_row_weight_mem (
                .clk       (clk),
                .rd_en     (rw_rd_en),
                .rd_row    (rw_rd_row),
                .rd_weight (rw_rd_weight),
                .wr0_en    (rw_wr0_en),
                .wr0_row   (sq0_row),
                .wr0_weight(sq0_row_sum),
                .wr1_en    (rw_wr1_en),
                .wr1_row   (sq1_row),
                .wr1_weight(sq1_row_sum)
            );
        end else begin : g_legacy_row_weight
            grover_row_weight_mem u_row_weight_mem (
                .clk       (clk),
                .rd_en     (rw_rd_en),
                .rd_row    (rw_rd_row),
                .rd_weight (rw_rd_weight),
                .wr_en     (rw_wr0_en),
                .wr_row    (sq0_row),
                .wr_weight (sq0_row_sum)
            );
        end
    endgenerate

    //-------------------------------------------------------------------------
    // v0.7 timing-closed dynamic-width threshold rejection
    //-------------------------------------------------------------------------
    // The registered rejection datapath is intentionally a real child module,
    // not duplicated inline logic. This keeps the synthesized/RTL hierarchy
    // faithful to the functional architecture:
    //
    //   grover_born_sampler
    //     `-- grover_born_reject64
    //
    // Sampler FSM timing is unchanged from v0.7c:
    //   S_CHECK_W   : reject block latches k = bit_length(W-1)
    //   S_RND_HI/LO : consume exactly two LFSR_MEAS draws, hi then lo
    //   S_RND_MAP   : reject block latches the exact low-k candidate
    //   S_RND_CHECK : consume registered candidate/accept result
    //
    // This is a hierarchy cleanup only. It preserves the already-verified
    // v0.7c latency, PRNG draw order, W=0/W=1 special cases, and bit-exact
    // rejection mapping while keeping both timing register boundaries inside
    // the named rejection module.
    reg [31:0] rnd_hi;
    reg [31:0] rnd_lo;
    wire [63:0] rnd64 = {rnd_hi, rnd_lo};

    wire [5:0]    reject_k_bits;
    wire [TW-1:0] reject_candidate;
    wire          reject_accept;
    wire          reject_direct_one;
    wire          reject_zero_weight;

    wire reject_load_weight  = (st == S_CHECK_W) &&
                               (total_weight > {{(TW-1){1'b0}},1'b1});
    wire reject_map_candidate = (st == S_RND_MAP);

    grover_born_reject64 u_reject64 (
        .clk           (clk),
        .rstn          (rstn),
        .load_weight   (reject_load_weight),
        .map_candidate (reject_map_candidate),
        .total_weight  (total_weight),
        .rnd64         (rnd64),
        .k_bits        (reject_k_bits),
        .candidate     (reject_candidate),
        .accept        (reject_accept),
        .direct_one    (reject_direct_one),
        .zero_weight   (reject_zero_weight)
    );

    assign rnd_draw = (st == S_RND_HI) || (st == S_RND_LO);

    //-------------------------------------------------------------------------
    // Build total W
    //-------------------------------------------------------------------------
    reg [TW-1:0] build_total;
    wire [TW-1:0] sq0_row_sum_ext = {{(TW-RSW){1'b0}}, sq0_row_sum};
    wire [TW-1:0] sq1_row_sum_ext = {{(TW-RSW){1'b0}}, sq1_row_sum};
    wire [TW+1:0] build_total_pair_ext = {2'b00, build_total} +
                                         {2'b00, sq0_row_sum_ext} +
                                         {2'b00, sq1_row_sum_ext};
    wire [TW:0] build_total_next_ext = {1'b0, build_total} +
                                        {1'b0, sq0_row_sum_ext};

    //-------------------------------------------------------------------------
    // E4 M2 hierarchical row selection metadata.
    //
    // 512 rows are divided into 16 groups of 32 consecutive rows.  During the
    // existing two-row BUILD, capture the exact GLOBAL CDF value at the end of
    // each group.  No extra squaring and no extra BUILD cycle are introduced.
    //
    // group_cdf[g] = sum(row_weight[0 .. 32*(g+1)-1])
    //
    // Group selection therefore needs only the strict comparison
    //     group_cdf[g] > threshold
    // and preserves the baseline FIRST cumulative > r rule bit-exactly.
    //-------------------------------------------------------------------------
    reg [TW-1:0] group_cdf [0:15];
    reg [3:0]    group_scan_index;
    reg [TW-1:0] group_prev_cdf;
    reg [`GP_ROW_W:0] row_scan_limit;

    wire [TW-1:0] group_cdf_cur = group_cdf[group_scan_index];
    wire group_take = (group_cdf_cur > threshold);
    wire [`GP_ROW_W:0] group_base_count =
        {1'b0, group_scan_index, 5'b00000};
    wire [`GP_ROW_W:0] group_end_count =
        group_base_count + 10'd32;

    //-------------------------------------------------------------------------
    // Row CDF scan -- v0.7 100-MHz timing-closure retiming.
    //
    // Post-Born-rejection synthesis left a smaller critical path:
    //   row_weight BRAM -> cumulative add -> strict threshold compare
    //                   -> row_take / FSM control
    // with about -0.243 ns worst setup slack in the unplaced synthesis report.
    //
    // Add one explicit register immediately after the synchronous row_weight
    // BRAM response.  Data, row tag, and valid move together:
    //   BRAM -> [rw_weight_pipe/rw_row_pipe/rw_pipe_valid]
    //        -> cumulative add -> (cumulative > threshold) -> FSM
    //
    // This changes latency only.  Row->Lane CDF ordering, the strict FIRST
    // cumulative > r boundary, selected row, and local threshold are bit-exact.
    //-------------------------------------------------------------------------
    reg [`GP_ROW_W:0] row_issue_count;
    reg                 rw_valid_d;
    reg [`GP_ROW_W-1:0] rw_row_d;

    reg                 rw_pipe_valid;
    reg [`GP_ROW_W-1:0] rw_row_pipe;
    reg [RSW-1:0]       rw_weight_pipe;

    reg [TW-1:0]      row_cumulative;
    reg [TW-1:0]      local_threshold;

    assign rw_rd_en  = (st == S_ROW_SCAN) &&
                       (row_issue_count < row_scan_limit);
    assign rw_rd_row = row_issue_count[`GP_ROW_W-1:0];

    wire [TW-1:0] rw_weight_ext = {{(TW-RSW){1'b0}}, rw_weight_pipe};
    wire [TW:0] row_next_ext = {1'b0, row_cumulative} +
                                {1'b0, rw_weight_ext};
    wire row_take = (row_next_ext > {1'b0, threshold});

    //-------------------------------------------------------------------------
    // Selected-row lane CDF
    //-------------------------------------------------------------------------
    reg [P*SQW-1:0] lane_sq_hold;
    reg [`GP_LOGP-1:0] lane_index;
    reg [TW-1:0] lane_cumulative;

    wire [SQW-1:0] lane_sq_cur = lane_sq_hold[lane_index*SQW +: SQW];
    wire [TW-1:0] lane_sq_ext = {{(TW-SQW){1'b0}}, lane_sq_cur};
    wire [TW:0] lane_next_ext = {1'b0, lane_cumulative} +
                                 {1'b0, lane_sq_ext};
    wire lane_take = (lane_next_ext > {1'b0, local_threshold});

    //-------------------------------------------------------------------------
    // amp_mem request mux
    //-------------------------------------------------------------------------
    always @* begin
        amp_rd_en  = 1'b0;
        amp_rd_row = {`GP_ROW_W{1'b0}};

        if ((E4_DUAL_BUILD == 0) &&
            (st == S_BUILD) && (amp_issue_count < `GP_ROWS)) begin
            amp_rd_en  = 1'b1;
            amp_rd_row = amp_issue_count[`GP_ROW_W-1:0];
        end else if (st == S_LANE_REQ) begin
            amp_rd_en  = 1'b1;
            amp_rd_row = selected_row;
        end
    end

    assign busy = (st != S_IDLE);

    //-------------------------------------------------------------------------
    // Controller
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rstn) begin
            st                <= S_IDLE;
            done              <= 1'b0;
            zero_weight_error <= 1'b0;
            candidate         <= {`GP_INDEX_W{1'b0}};
            total_weight      <= {TW{1'b0}};
            threshold         <= {TW{1'b0}};
            selected_row      <= {`GP_ROW_W{1'b0}};

            amp_issue_count   <= {(`GP_ROW_W+1){1'b0}};
            amp_req_valid_d   <= 1'b0;
            amp_req_row_d     <= {`GP_ROW_W{1'b0}};
            amp_req_valid_d2  <= 1'b0;
            amp_req_row_d2    <= {`GP_ROW_W{1'b0}};
            build_total       <= {TW{1'b0}};

            e4_quad_issue_count <= 8'd0;
            e4_quad_resp_count  <= 8'd0;
            e4_quad_req_gap     <= 1'b0;
            e4_hold_valid       <= 1'b0;
            e4_hold_amp2        <= {(P*`GP_AMP_W){1'b0}};
            e4_hold_amp3        <= {(P*`GP_AMP_W){1'b0}};
            e4_hold_row2        <= {`GP_ROW_W{1'b0}};
            e4_hold_row3        <= {`GP_ROW_W{1'b0}};

            rnd_hi               <= 32'd0;
            rnd_lo               <= 32'd0;

            row_issue_count   <= {(`GP_ROW_W+1){1'b0}};
            row_scan_limit    <= `GP_ROWS;
            group_scan_index  <= 4'd0;
            group_prev_cdf    <= {TW{1'b0}};
            rw_valid_d        <= 1'b0;
            rw_row_d          <= {`GP_ROW_W{1'b0}};
            rw_pipe_valid     <= 1'b0;
            rw_row_pipe       <= {`GP_ROW_W{1'b0}};
            rw_weight_pipe    <= {RSW{1'b0}};
            row_cumulative    <= {TW{1'b0}};
            local_threshold   <= {TW{1'b0}};

            lane_sq_hold      <= {(P*SQW){1'b0}};
            lane_index        <= {`GP_LOGP{1'b0}};
            lane_cumulative   <= {TW{1'b0}};
        end else begin
            done              <= 1'b0;
            zero_weight_error <= 1'b0;

            // Align amp_mem synchronous read data to the square-pipeline input.
            amp_req_valid_d <= amp_rd_en;
            if (amp_rd_en)
                amp_req_row_d <= amp_rd_row;

            amp_req_valid_d2 <= amp_req_valid_d;
            if (amp_req_valid_d)
                amp_req_row_d2 <= amp_req_row_d;

            // First alignment stage: row_weight synchronous BRAM response.
            rw_valid_d <= rw_rd_en;
            if (rw_rd_en)
                rw_row_d <= rw_rd_row;

            // v0.7 second alignment stage: timing register after BRAM Q.
            // Data + row tag + valid are always captured as one transaction.
            rw_pipe_valid <= rw_valid_d;
            if (rw_valid_d) begin
                rw_row_pipe    <= rw_row_d;
                rw_weight_pipe <= rw_rd_weight;
            end

            // E4 M1 quad request cadence and 4-row -> 2-row serialization.
            if ((E4_DUAL_BUILD != 0) && (st == S_BUILD)) begin
                if (amp_quad_rd_en) begin
                    e4_quad_issue_count <= e4_quad_issue_count + 1'b1;
                    e4_quad_req_gap <= 1'b1;
                end else begin
                    e4_quad_req_gap <= 1'b0;
                end

                if (amp_quad_valid) begin
                    e4_hold_amp2 <= amp_quad2;
                    e4_hold_amp3 <= amp_quad3;
                    e4_hold_row2 <= e4_resp_base_row + {{(`GP_ROW_W-2){1'b0}},2'd2};
                    e4_hold_row3 <= e4_resp_base_row + {{(`GP_ROW_W-2){1'b0}},2'd3};
                    e4_hold_valid <= 1'b1;
                    e4_quad_resp_count <= e4_quad_resp_count + 1'b1;
                end else if (e4_hold_valid) begin
                    e4_hold_valid <= 1'b0;
                end
            end else begin
                e4_quad_req_gap <= 1'b0;
                e4_hold_valid   <= 1'b0;
            end

            case (st)
                S_IDLE: begin
                    amp_req_valid_d  <= 1'b0;
                    amp_req_valid_d2 <= 1'b0;
                    rw_valid_d      <= 1'b0;
                    rw_pipe_valid   <= 1'b0;
                    if (start) begin
                        candidate       <= {`GP_INDEX_W{1'b0}};
                        total_weight    <= {TW{1'b0}};
                        threshold       <= {TW{1'b0}};
                        selected_row    <= {`GP_ROW_W{1'b0}};
                        amp_issue_count      <= {(`GP_ROW_W+1){1'b0}};
                        build_total          <= {TW{1'b0}};
                        e4_quad_issue_count  <= 8'd0;
                        e4_quad_resp_count   <= 8'd0;
                        e4_quad_req_gap      <= 1'b0;
                        e4_hold_valid        <= 1'b0;
                        group_scan_index     <= 4'd0;
                        group_prev_cdf       <= {TW{1'b0}};
                        row_scan_limit       <= `GP_ROWS;
                        st                   <= S_BUILD;
                    end
                end

                // BUILD. Legacy mode preserves one row/cycle. E4 M1 consumes
                // two exact row sums/cycle from the two square32 pipelines.
                S_BUILD: begin
                    if (E4_DUAL_BUILD == 0) begin
                        if (amp_rd_en)
                            amp_issue_count <= amp_issue_count + 1'b1;

                        if (sq0_valid) begin
                            build_total <= build_total_next_ext[TW-1:0];
                            if (sq0_row == (`GP_ROWS-1)) begin
                                total_weight <= build_total_next_ext[TW-1:0];
                                st <= S_CHECK_W;
                            end
                        end
                    end else begin
                        if (sq0_valid && sq1_valid) begin
                            build_total <= build_total_pair_ext[TW-1:0];

                            // Every pair is consecutive.  When the odd row is
                            // the last row of a 32-row group, the updated global
                            // BUILD total is exactly that group's CDF endpoint.
                            if ((E4_HIER_SELECT != 0) &&
                                (sq1_row[4:0] == 5'd31))
                                group_cdf[sq1_row[`GP_ROW_W-1:5]] <=
                                    build_total_pair_ext[TW-1:0];

                            if (sq1_row == (`GP_ROWS-1)) begin
                                total_weight <= build_total_pair_ext[TW-1:0];
                                e4_hold_valid <= 1'b0;
                                st <= S_CHECK_W;
                            end
                        end
                    end
                end

                S_CHECK_W: begin
                    amp_req_valid_d <= 1'b0;
                    if (total_weight == {TW{1'b0}}) begin
                        st <= S_ZERO;
                    end else if (total_weight == {{(TW-1){1'b0}},1'b1}) begin
                        // Direct W=1 case: no LFSR draw.
                        threshold       <= {TW{1'b0}};
                        row_issue_count <= {(`GP_ROW_W+1){1'b0}};
                        row_cumulative  <= {TW{1'b0}};
                        rw_valid_d      <= 1'b0;
                        rw_pipe_valid   <= 1'b0;
                        if ((E4_DUAL_BUILD != 0) &&
                            (E4_HIER_SELECT != 0)) begin
                            group_scan_index <= 4'd0;
                            group_prev_cdf   <= {TW{1'b0}};
                            st               <= S_GROUP_SCAN;
                        end else begin
                            row_scan_limit <= `GP_ROWS;
                            st             <= S_ROW_SCAN;
                        end
                    end else begin
                        // u_reject64 captures k on this S_CHECK_W edge.
                        st <= S_RND_HI;
                    end
                end

                // Each threshold attempt consumes exactly two draws, hi then lo.
                S_RND_HI: begin
                    rnd_hi <= rnd;
                    st <= S_RND_LO;
                end

                S_RND_LO: begin
                    rnd_lo <= rnd;
                    st <= S_RND_MAP;
                end

                // u_reject64 captures the exact low-k candidate on this edge.
                S_RND_MAP: begin
                    st <= S_RND_CHECK;
                end

                S_RND_CHECK: begin
                    if (reject_accept) begin
                        threshold       <= reject_candidate;
                        row_issue_count <= {(`GP_ROW_W+1){1'b0}};
                        row_cumulative  <= {TW{1'b0}};
                        rw_valid_d      <= 1'b0;
                        rw_pipe_valid   <= 1'b0;
                        if ((E4_DUAL_BUILD != 0) &&
                            (E4_HIER_SELECT != 0)) begin
                            group_scan_index <= 4'd0;
                            group_prev_cdf   <= {TW{1'b0}};
                            st               <= S_GROUP_SCAN;
                        end else begin
                            row_scan_limit <= `GP_ROWS;
                            st             <= S_ROW_SCAN;
                        end
                    end else begin
                        // Rejection consumes no draw here; the next attempt
                        // starts with a completely fresh HI->LO pair.
                        st <= S_RND_HI;
                    end
                end

                // E4 M2: first select one of 16 x 32-row groups from
                // the exact global CDF endpoints captured during BUILD.
                // This is only a decomposition of the same strict CDF search.
                S_GROUP_SCAN: begin
                    if (group_take) begin
                        row_issue_count <= group_base_count;
                        row_scan_limit  <= group_end_count;
                        row_cumulative  <= group_prev_cdf;
                        rw_valid_d      <= 1'b0;
                        rw_pipe_valid   <= 1'b0;
                        st              <= S_ROW_SCAN;
                    end else begin
                        group_prev_cdf <= group_cdf_cur;
                        if (group_scan_index == 4'd15) begin
                            // Mathematically unreachable for valid threshold < W.
                            // Keep a deterministic safe fallback to the last group.
                            row_issue_count <= 10'd480;
                            row_scan_limit  <= 10'd512;
                            row_cumulative  <= group_prev_cdf;
                            rw_valid_d      <= 1'b0;
                            rw_pipe_valid   <= 1'b0;
                            st              <= S_ROW_SCAN;
                        end else begin
                            group_scan_index <= group_scan_index + 1'b1;
                        end
                    end
                end

                // Strict boundary rule: select FIRST cumulative > threshold.
                // In E4 M2 the requests are limited to the selected 32-row group;
                // row_cumulative starts at the exact CDF before that group.
                // Legacy mode still scans all 512 rows from cumulative zero.
                S_ROW_SCAN: begin
                    if (rw_rd_en)
                        row_issue_count <= row_issue_count + 1'b1;

                    if (rw_pipe_valid) begin
                        if (row_take) begin
                            selected_row    <= rw_row_pipe;
                            local_threshold <= threshold - row_cumulative;

                            // Stop/flush outstanding row-scan metadata. BRAM may
                            // have a later request physically in flight, but it
                            // is ignored after state leaves S_ROW_SCAN.
                            rw_valid_d      <= 1'b0;
                            rw_pipe_valid   <= 1'b0;
                            st              <= S_LANE_REQ;
                        end else begin
                            row_cumulative <= row_next_ext[TW-1:0];
                        end
                    end
                end

                // One selected amp row is reread; the same 32-square pipeline is
                // reused, so there is no second full-state square pass.
                S_LANE_REQ: begin
                    st <= S_LANE_WAIT;
                end

                S_LANE_WAIT: begin
                    if (sq_valid) begin
                        lane_sq_hold    <= sq_lane;
                        lane_index      <= {`GP_LOGP{1'b0}};
                        lane_cumulative <= {TW{1'b0}};
                        st              <= S_LANE_SCAN;
                    end
                end

                // Strict boundary rule again inside the selected row.
                S_LANE_SCAN: begin
                    if (lane_take) begin
                        candidate <= {selected_row, lane_index};
                        st <= S_FIN;
                    end else begin
                        lane_cumulative <= lane_next_ext[TW-1:0];
                        lane_index <= lane_index + 1'b1;
                    end
                end

                S_FIN: begin
                    done <= 1'b1;
                    st <= S_IDLE;
                end

                S_ZERO: begin
                    zero_weight_error <= 1'b1;
                    done <= 1'b1;
                    st <= S_IDLE;
                end

                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_born_sampler.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_verify.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_verify.v -- BBHT/Grover Main IP v0.6, Step 7
//
// Classical verification of one Born-measured candidate.
//   candidate -> data_mem Port-B synchronous read -> SAME predicate as Oracle
//
// v0.6 contract:
//   target(i) = (i < data_count) && predicate(data[i])
//   LT/GT/RANGE are signed comparisons, RANGE is open (A < x < B).
//   A candidate in padding (i >= data_count) must always fail verification.
//
// Timing with grover_data_mem Port B after T5:
//   start edge   : candidate address is presented and captured
//   capture edge : returned data + found-mask bit are registered
//   next edge    : registered data is evaluated, done pulses with hit valid
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_verify (
    input  wire                                  clk,
    input  wire                                  rstn,
    input  wire                                  start,
    input  wire [`GP_INDEX_W-1:0]                candidate,

    input  wire [1:0]                            predicate_mode,
    input  wire signed [`GP_DATA_W-1:0]          threshold_a,
    input  wire signed [`GP_DATA_W-1:0]          threshold_b,
    input  wire [`GP_DATA_COUNT_W-1:0]           data_count,
    input  wire                                  enum_enable,
    input  wire                                  found_mask_verify_found,

    // Connect directly to grover_data_mem.verify_index / verify_data.
    output wire [`GP_INDEX_W-1:0]                data_verify_index,
    input  wire signed [`GP_DATA_W-1:0]          data_verify_value,

    output wire                                  busy,
    output reg                                   done,
    output reg                                   hit
);
    // T5 timing cut for the standalone post-route Verify bottleneck.
    //
    // Baseline critical path:
    //   data_mem Port-B BRAM Q -> predicate compare -> hit_reg/D
    //
    // Add one explicit capture boundary immediately after the synchronous
    // dataset/mask reads.  The candidate address is still launched on the
    // accepted start edge; S_CAPTURE stores the returned data and aligned
    // found-mask bit; S_EVAL performs the unchanged predicate and commit.
    // This adds exactly one grover_verify busy cycle per verification request
    // while preserving predicate semantics, candidate ordering, and PRNG use.
    localparam [1:0] S_IDLE    = 2'd0;
    localparam [1:0] S_CAPTURE = 2'd1;
    localparam [1:0] S_EVAL    = 2'd2;

    reg [1:0] st;
    reg [`GP_INDEX_W-1:0] candidate_r;
    reg signed [`GP_DATA_W-1:0] data_verify_value_r;
    reg found_mask_verify_found_r;

    // Present the incoming candidate immediately so data_mem/found_mask launch
    // their synchronous verify reads on the same edge that start is accepted.
    // candidate_r then holds that address stable through CAPTURE and EVAL.
    assign data_verify_index = (st == S_IDLE && start) ? candidate : candidate_r;
    assign busy = (st != S_IDLE);

    wire pred_hit;
    grover_predicate u_verify_predicate (
        .mode        (predicate_mode),
        .value       (data_verify_value_r),
        .threshold_a (threshold_a),
        .threshold_b (threshold_b),
        .index       (candidate_r),
        .data_count  (data_count),
        .hit         (pred_hit)
    );

    always @(posedge clk) begin
        if (!rstn) begin
            st                         <= S_IDLE;
            candidate_r                <= {`GP_INDEX_W{1'b0}};
            data_verify_value_r        <= {`GP_DATA_W{1'b0}};
            found_mask_verify_found_r  <= 1'b0;
            done                       <= 1'b0;
            hit                        <= 1'b0;
        end else begin
            done <= 1'b0;

            case (st)
                S_IDLE: begin
                    if (start) begin
                        candidate_r <= candidate;
                        hit         <= 1'b0;
                        st          <= S_CAPTURE;
                    end
                end

                S_CAPTURE: begin
                    // data_verify_value and found_mask_verify_found now
                    // correspond to candidate_r.  Capture both on the same
                    // edge so the subsequent predicate/mask decision is aligned.
                    data_verify_value_r       <= data_verify_value;
                    found_mask_verify_found_r <= found_mask_verify_found;
                    st                        <= S_EVAL;
                end

                S_EVAL: begin
                    // Exact verification rule is unchanged.  In Single mode
                    // the registered found-mask bit is intentionally ignored.
                    hit  <= pred_hit &&
                            (!(enum_enable === 1'b1) || !found_mask_verify_found_r);
                    done <= 1'b1;
                    st   <= S_IDLE;
                end

                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_verify.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_measure_verify.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_measure_verify.v -- BBHT/Grover Main IP v0.6, Step 7
//
// Integration boundary:
//   psi_j -> Row->Lane Born sampler -> candidate -> data_mem Port B -> verify
//
// This block intentionally does NOT contain BBHT shot policy, cache policy,
// loader control, status-stickiness, or result/limit termination policy.
// Those remain later v0.6 integration steps.
//
// Cache invariant:
//   Measurement is read-only on amp_mem.  This block has no amplitude write
//   outputs. amp_write_forbid stays high for the complete measurement+verify
//   transaction so the upper-level memory mux can force amp_mem.wr_en=0.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_measure_verify #(
    parameter integer AMP_READ_LATENCY = 1,
    parameter integer E4_DUAL_BUILD    = 0,
    parameter integer E4_HIER_SELECT   = 0
) (
    input  wire                                  clk,
    input  wire                                  rstn,
    input  wire                                  start,

    // Oracle/verification contract.
    input  wire [1:0]                            predicate_mode,
    input  wire signed [`GP_DATA_W-1:0]          threshold_a,
    input  wire signed [`GP_DATA_W-1:0]          threshold_b,
    input  wire [`GP_DATA_COUNT_W-1:0]           data_count,
    input  wire                                  enum_enable,
    input  wire                                  found_mask_verify_found,

    // Measurement PRNG stream. rnd is current LFSR_MEAS state.
    input  wire [31:0]                           rnd,
    output wire                                  rnd_draw,

    // Read-only amplitude-memory port used by the Born engine.
    input  wire [`GP_P*`GP_AMP_W-1:0]            amp_rdata,
    output wire [`GP_ROW_W-1:0]                  amp_rd_row,
    output wire                                  amp_rd_en,

    input  wire [`GP_P*`GP_AMP_W-1:0]            amp_quad0,
    input  wire [`GP_P*`GP_AMP_W-1:0]            amp_quad1,
    input  wire [`GP_P*`GP_AMP_W-1:0]            amp_quad2,
    input  wire [`GP_P*`GP_AMP_W-1:0]            amp_quad3,
    input  wire                                  amp_quad_valid,
    output wire [6:0]                            amp_quad_rd_index,
    output wire                                  amp_quad_rd_en,

    // data_mem Port-B verification interface.
    output wire [`GP_INDEX_W-1:0]                data_verify_index,
    input  wire signed [`GP_DATA_W-1:0]          data_verify_value,

    output wire                                  busy,
    output reg                                   done,
    output reg                                   verify_hit,
    output reg                                   zero_weight_error,
    output reg  [`GP_INDEX_W-1:0]                candidate,

    // Must be used by the upper-level amp_mem write mux.
    output wire                                  amp_write_forbid,

    // Debug / Golden-comparison visibility.
    output wire [`GP_TOTAL_WEIGHT_W-1:0]         total_weight,
    output wire [`GP_TOTAL_WEIGHT_W-1:0]         measurement_threshold,
    output wire [`GP_ROW_W-1:0]                  selected_row
);
    localparam [2:0]
        S_IDLE      = 3'd0,
        S_MEAS      = 3'd1,
        S_VFY_REQ   = 3'd2,
        S_VFY_WAIT  = 3'd3;

    reg [2:0] st;
    reg born_start;
    reg vfy_start;

    wire born_busy;
    wire born_done;
    wire born_zero_weight_error;
    wire [`GP_INDEX_W-1:0] born_candidate;

    wire vfy_busy;
    wire vfy_done;
    wire vfy_hit;

    assign busy = (st != S_IDLE);
    assign amp_write_forbid = busy;

    grover_born_sampler #(
        .AMP_READ_LATENCY(AMP_READ_LATENCY),
        .E4_DUAL_BUILD   (E4_DUAL_BUILD),
        .E4_HIER_SELECT  (E4_HIER_SELECT)
    ) u_born (
        .clk               (clk),
        .rstn              (rstn),
        .start             (born_start),
        .rnd               (rnd),
        .rnd_draw          (rnd_draw),
        .amp_rdata         (amp_rdata),
        .amp_rd_row        (amp_rd_row),
        .amp_rd_en         (amp_rd_en),
        .amp_quad0         (amp_quad0),
        .amp_quad1         (amp_quad1),
        .amp_quad2         (amp_quad2),
        .amp_quad3         (amp_quad3),
        .amp_quad_valid    (amp_quad_valid),
        .amp_quad_rd_index (amp_quad_rd_index),
        .amp_quad_rd_en    (amp_quad_rd_en),
        .busy              (born_busy),
        .done              (born_done),
        .zero_weight_error (born_zero_weight_error),
        .candidate         (born_candidate),
        .total_weight      (total_weight),
        .threshold         (measurement_threshold),
        .selected_row      (selected_row)
    );

    grover_verify u_verify (
        .clk               (clk),
        .rstn              (rstn),
        .start             (vfy_start),
        .candidate         (candidate),
        .predicate_mode    (predicate_mode),
        .threshold_a       (threshold_a),
        .threshold_b       (threshold_b),
        .data_count        (data_count),
        .enum_enable       (enum_enable),
        .found_mask_verify_found(found_mask_verify_found),
        .data_verify_index (data_verify_index),
        .data_verify_value (data_verify_value),
        .busy              (vfy_busy),
        .done              (vfy_done),
        .hit               (vfy_hit)
    );

    always @(posedge clk) begin
        if (!rstn) begin
            st                <= S_IDLE;
            born_start        <= 1'b0;
            vfy_start         <= 1'b0;
            done              <= 1'b0;
            verify_hit        <= 1'b0;
            zero_weight_error <= 1'b0;
            candidate         <= {`GP_INDEX_W{1'b0}};
        end else begin
            born_start <= 1'b0;
            vfy_start  <= 1'b0;
            done       <= 1'b0;

            case (st)
                S_IDLE: begin
                    if (start) begin
                        // Per-transaction result fields are cleared on the
                        // accepted request. Later Step-10 logic may make the
                        // externally visible error/status bits sticky.
                        verify_hit        <= 1'b0;
                        zero_weight_error <= 1'b0;
                        candidate         <= {`GP_INDEX_W{1'b0}};
                        born_start        <= 1'b1;
                        st                <= S_MEAS;
                    end
                end

                S_MEAS: begin
                    if (born_done) begin
                        if (born_zero_weight_error) begin
                            zero_weight_error <= 1'b1;
                            done              <= 1'b1;
                            st                <= S_IDLE;
                        end else begin
                            candidate <= born_candidate;
                            st        <= S_VFY_REQ;
                        end
                    end
                end

                // Separate request state keeps candidate stable for a complete
                // cycle before grover_verify launches data_mem Port-B read.
                S_VFY_REQ: begin
                    vfy_start <= 1'b1;
                    st        <= S_VFY_WAIT;
                end

                S_VFY_WAIT: begin
                    if (vfy_done) begin
                        verify_hit <= vfy_hit;
                        done       <= 1'b1;
                        st         <= S_IDLE;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_measure_verify.v
//------------------------------------------------------------------------------
