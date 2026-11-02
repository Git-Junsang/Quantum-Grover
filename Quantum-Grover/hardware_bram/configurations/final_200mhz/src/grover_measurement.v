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

//==============================================================================
// grover_born_square32_p -- grover_born_square32 for 200 MHz
//
// Same exact squares and the same exact reduction widths
// (46 -> 47 -> 48 -> 49 -> 50 -> 51 bits, unsigned, adjacent pairs), so
// out_row_sum is bit-identical.  Register boundaries:
//
//   in -> [amp0] -> square -> [m1] -> [sq1] -> L1 [] L2 [] L3 [] L4 [] L5 []
//
// amp0 / m1 / sq1 are the DSP48E1 A/B, M and P registers of the two-DSP
// 23x23 multiplier.  The data flops have no clock enable; in_valid only
// travels down the valid pipe.
//
// The lane squares for the selected-row reread are taken from sq1 with their
// own valid (sq_valid) instead of being delayed to line up with the row sum;
// the reread does not use the row sum, and the five-level delay line would
// have cost 7,360 flops.
//==============================================================================
module grover_born_square32_p (
    input  wire                                  clk,
    input  wire                                  rstn,
    input  wire                                  in_valid,
    input  wire [`GP_ROW_W-1:0]                  in_row,
    input  wire [`GP_P*`GP_AMP_W-1:0]            in_amp,
    output wire                                  sq_valid,
    output wire [`GP_P*`GP_SQUARE_W-1:0]         out_sq,
    output wire                                  out_valid,
    output wire [`GP_ROW_W-1:0]                  out_row,
    output wire [`GP_ROW_SUM_W-1:0]              out_row_sum
);
    localparam integer P   = `GP_P;
    localparam integer AW  = `GP_AMP_W;
    localparam integer SQW = `GP_SQUARE_W;
    localparam integer RSW = `GP_ROW_SUM_W;

    // Valid / row tag: amp0, m1, sq1, L1, L2, L3, L4, L5 = 8 stages.
    reg [7:0] v;
    reg [`GP_ROW_W-1:0] row [0:7];
    integer s;
    always @(posedge clk) begin
        if (!rstn) v <= 8'd0;
        else       v <= {v[6:0], in_valid};
    end
    always @(posedge clk) begin
        row[0] <= in_row;
        for (s = 1; s < 8; s = s + 1) row[s] <= row[s-1];
    end

    reg [P*AW-1:0]  amp0;
    reg [P*SQW-1:0] m1;
    reg [P*SQW-1:0] sq1;
    reg [SQW:0]   l1 [0:15];
    reg [SQW+1:0] l2 [0:7];
    reg [SQW+2:0] l3 [0:3];
    reg [SQW+3:0] l4 [0:1];
    reg [SQW+4:0] l5;

    integer k;
    reg signed [AW-1:0]  amp_k;
    reg signed [SQW-1:0] prod_k;
    always @(posedge clk) begin
        amp0 <= in_amp;
        for (k = 0; k < P; k = k + 1) begin
            amp_k  = $signed(amp0[k*AW +: AW]);
            prod_k = amp_k * amp_k;
            m1[k*SQW +: SQW] <= prod_k;
        end
        sq1 <= m1;
        for (k = 0; k < 16; k = k + 1)
            l1[k] <= {1'b0, sq1[(2*k)*SQW +: SQW]} + {1'b0, sq1[(2*k+1)*SQW +: SQW]};
        for (k = 0; k < 8; k = k + 1) l2[k] <= {1'b0, l1[2*k]} + {1'b0, l1[2*k+1]};
        for (k = 0; k < 4; k = k + 1) l3[k] <= {1'b0, l2[2*k]} + {1'b0, l2[2*k+1]};
        for (k = 0; k < 2; k = k + 1) l4[k] <= {1'b0, l3[2*k]} + {1'b0, l3[2*k+1]};
        l5 <= {1'b0, l4[0]} + {1'b0, l4[1]};
    end

    assign sq_valid    = v[2];
    assign out_sq      = sq1;
    assign out_valid   = v[7];
    assign out_row     = row[7];
    assign out_row_sum = l5;
endmodule

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
    reg [TW-1:0] w_minus1_r;
    integer k_i;
    integer map_i;

    // 200 MHz: stage A is split over two edges and runs every cycle.
    //   edge 1: w_minus1_r = (W > 1) ? W-1 : 0        (60-bit decrement)
    //   edge 2: k_bits     = bit_length(w_minus1_r)    (priority encoder)
    // total_weight is fixed from S_CHECK_W until the measurement ends and
    // k_bits is first used on the S_RND_MAP edge, three edges after
    // S_CHECK_W, so the value seen there is the same k as before.  For
    // W <= 1, bit_length(0) = 0 as before.  load_weight is no longer used.
    always @* begin
        k_comb = 6'd0;
        for (k_i = 0; k_i < TW; k_i = k_i + 1) begin
            if (w_minus1_r[k_i])
                k_comb = k_i + 1;
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
            w_minus1_r <= {TW{1'b0}};
            k_bits     <= 6'd0;
            candidate  <= {TW{1'b0}};
        end else begin
            w_minus1_r <= (total_weight > {{(TW-1){1'b0}},1'b1}) ?
                          (total_weight - {{(TW-1){1'b0}},1'b1}) : {TW{1'b0}};
            k_bits     <= k_comb;

            if (map_candidate)
                candidate <= candidate_comb;
        end
    end

    wire _unused_load_weight = load_weight;

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

//==============================================================================
// grover_sub60_cs -- {borrow, a - b} for 60-bit unsigned a, b (carry-select)
//
// Same result as {1'b0,a} - {1'b0,b}: borrow = (b > a), diff = (a - b) mod
// 2^60.  The low 30 bits and both possible high halves (borrow-in 0 and 1)
// are computed side by side and the low borrow picks one, so the longest
// carry chain is 31 bits instead of 61.
//
// The two high candidates are written as two different additions
// ({1'b0,A} + {1'b1,~B} with and without +1, the +1 carried in through an
// extra LSB) so synthesis cannot derive one from the other by a second
// chain (it did for "x - 1"), and keep stops it from merging them.
//==============================================================================
module grover_sub60_cs (
    input  wire [59:0] a,
    input  wire [59:0] b,
    output wire [59:0] diff,
    output wire        borrow
);
    wire [30:0] lo = {1'b0, a[29:0]} - {1'b0, b[29:0]};
    // {1'b0,A} - {1'b0,B} - cin = {1'b0,A} + {1'b1,~B} + (1 - cin)  (mod 2^31)
    (* keep = "true" *) wire [31:0] hi0_x = {1'b0, a[59:30], 1'b1} + {1'b1, ~b[59:30], 1'b1};
    (* keep = "true" *) wire [30:0] hi1   = {1'b0, a[59:30]} + {1'b1, ~b[59:30]};
    wire [30:0] hi0 = hi0_x[31:1];
    wire [30:0] hi = lo[30] ? hi1 : hi0;
    assign diff   = {hi[29:0], lo[29:0]};
    assign borrow = hi[30];
endmodule

//==============================================================================
// grover_add60_cs -- (a + b) mod 2^60, carry-select (low 30 bits and both
// possible high halves side by side).  Same sum as a + b.
//==============================================================================
module grover_add60_cs (
    input  wire [59:0] a,
    input  wire [59:0] b,
    output wire [59:0] sum
);
    wire [30:0] lo = {1'b0, a[29:0]} + {1'b0, b[29:0]};
    // a + b + 1 as its own addition: the +1 enters through an extra LSB.
    (* keep = "true" *) wire [29:0] hi0   = a[59:30] + b[59:30];
    (* keep = "true" *) wire [30:0] hi1_x = {a[59:30], 1'b1} + {b[59:30], 1'b1};
    wire [29:0] hi1 = hi1_x[30:1];
    assign sum = {lo[30] ? hi1 : hi0, lo[29:0]};
endmodule

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

    // Read-only amp_mem port (selected-row reread).
    input  wire [`GP_P*`GP_AMP_W-1:0]            amp_rdata,
    output reg  [`GP_ROW_W-1:0]                  amp_rd_row,
    output reg                                   amp_rd_en,

    // E4 M1 BUILD-only quad-read interface.  The sampler requests one
    // four-row checkpoint quad every two clocks and consumes it as two
    // consecutive two-row square transactions.
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

    output reg  [`GP_TOTAL_WEIGHT_W-1:0]         total_weight,
    output reg  [`GP_TOTAL_WEIGHT_W-1:0]         threshold,
    output reg  [`GP_ROW_W-1:0]                  selected_row
);
    //--------------------------------------------------------------------------
    // 200 MHz sampler (final_200mhz).
    //
    // Same measurement as the 100 MHz E4 M1/M2 sampler, value for value:
    //   BUILD     two rows/cycle, exact 32-lane squares, row_weight[512],
    //             W, and the 16 exact group CDF endpoints (M2)
    //   W=0/W=1   unchanged special cases (W=1: r=0, no draw)
    //   W>1       two LFSR_MEAS draws hi->lo, low-k rejection, retries
    //   SELECT    FIRST group endpoint > r, then FIRST row in that group
    //             whose cumulative weight > r, then FIRST lane in that row
    //             whose cumulative square > local_r
    //   candidate = {row, lane}
    //
    // What changed is only how the work is cut into cycles:
    //   - the checkpoint memory answers in 4 cycles (AMP_READ_LATENCY=4);
    //     amp_quad_valid arrives 2 cycles after the request and is delayed
    //     the last two cycles here through a register tree, one copy per
    //     four lanes of each square engine's input mux
    //   - square32 has one register per tree level (grover_born_square32_p)
    //   - BUILD adds the two row sums in one stage and the running total in
    //     the next (was one three-input 62-bit add)
    //   - the scans keep rem = r - cumulative instead of cumulative:
    //         cumulative + w > r   <=>   w > r - cumulative   (= w > rem)
    //     and w > rem is the borrow of rem - w, so one subtraction gives both
    //     the decision and the next rem; local_r = r - cumulative_before_row
    //     is rem itself
    //   - the rejection test (candidate < W) is registered in its own state
    //     before S_RND_CHECK uses it (one extra cycle per draw pair)
    //   - the group scan reads the next endpoint into a register before it
    //     compares (one extra cycle per measurement)
    //   - the lane scan rotates the 32 captured squares instead of a 32:1 mux
    //
    // Only the E4 M1+M2 configuration with a 4-cycle checkpoint read exists in
    // this model; any other parameter set stops elaboration below.
    //--------------------------------------------------------------------------
    generate
        if (!((AMP_READ_LATENCY == 4) && (E4_DUAL_BUILD != 0) && (E4_HIER_SELECT != 0)))
        begin : g_unsupported
            grover_born_sampler_200mhz_supports_only_e4_m1_m2_latency4 u_unsupported ();
        end
    endgenerate

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
        S_GROUP_SCAN = 5'd13,
        S_RND_CMP    = 5'd14,
        S_BUILD_FIN  = 5'd15;

    reg [4:0] st;

    // One-hot copies of two states whose decode would otherwise drive the
    // 736-bit square-input mux and the 1,472-bit lane shifter directly.
    // build_sel is copied once more per four lanes below (it changes only at
    // the ends of BUILD, long before and after the reread uses the mux).
    reg build_sel;                            // st == S_BUILD
    (* max_fanout = 64 *) reg lane_wait_sel;  // st == S_LANE_WAIT

    //-------------------------------------------------------------------------
    // Selected-row reread alignment (4-cycle checkpoint read).
    //-------------------------------------------------------------------------
    reg               amp_req_valid_d, amp_req_valid_d2, amp_req_valid_d3, amp_req_valid_d4;
    reg [`GP_ROW_W-1:0] amp_req_row_d, amp_req_row_d2, amp_req_row_d3, amp_req_row_d4;

    //-------------------------------------------------------------------------
    // E4 quad stream scheduler.  Requests are issued every other BUILD cycle.
    // The four returned rows are consumed as {0,1} then buffered {2,3}.
    //-------------------------------------------------------------------------
    reg [7:0] e4_quad_issue_count;
    reg [7:0] e4_quad_resp_count;
    reg       e4_quad_req_gap;
    reg       e4_hold_valid;
    reg [P*`GP_AMP_W-1:0] e4_hold_amp2;
    reg [P*`GP_AMP_W-1:0] e4_hold_amp3;
    reg [`GP_ROW_W-1:0] e4_hold_row2;
    reg [`GP_ROW_W-1:0] e4_hold_row3;

    assign amp_quad_rd_en = (st == S_BUILD) &&
                            (e4_quad_issue_count < 8'd128) &&
                            !e4_quad_req_gap;
    assign amp_quad_rd_index = e4_quad_issue_count[6:0];

    wire [`GP_ROW_W-1:0] e4_resp_base_row = {e4_quad_resp_count[6:0], 2'b00};

    // Quad tag: amp_quad_valid is 2 cycles after the request; qv4 marks the
    // cycle the quad data is on amp_quad* (control copy).
    reg qv3, qv4;
    always @(posedge clk) begin
        if (!rstn) begin qv3 <= 1'b0; qv4 <= 1'b0; end
        else begin qv3 <= amp_quad_valid; qv4 <= qv3; end
    end
    wire quad_now = qv4;

    wire e4_build_pair_valid = (st == S_BUILD) && (quad_now || e4_hold_valid);

    wire [`GP_ROW_W-1:0] e4_pair_row0 = quad_now ?
        e4_resp_base_row : e4_hold_row2;
    wire [`GP_ROW_W-1:0] e4_pair_row1 = quad_now ?
        (e4_resp_base_row + {{(`GP_ROW_W-1){1'b0}},1'b1}) : e4_hold_row3;

    // Square-input muxes, built per four lanes with local copies of the
    // selects:  pair select = the quad tag (two-level copy, same timing as
    // qv4); engine-0 source = build_sel (two-level copy).
    localparam integer AWD = `GP_AMP_W;
    wire [P*AWD-1:0] e4_pair_amp1;
    wire [P*AWD-1:0] sq0_in_amp;
    (* dont_touch = "true" *) reg qv3_h [0:3];   // level 1: engine x half
    (* dont_touch = "true" *) reg bs_h  [0:1];   // level 1: engine-0 halves
    integer hh;
    always @(posedge clk) begin
        for (hh = 0; hh < 4; hh = hh + 1) qv3_h[hh] <= amp_quad_valid;
        for (hh = 0; hh < 2; hh = hh + 1) bs_h[hh]  <= build_sel;
    end
    genvar lg;
    generate for (lg = 0; lg < P/4; lg = lg + 1) begin : g_inmux
        localparam integer LO = lg*4*AWD;
        localparam integer HI = lg / (P/8);       // which half
        (* dont_touch = "true" *) reg qv4_e0, qv4_e1, bs_g;
        always @(posedge clk) begin
            qv4_e0 <= qv3_h[HI];
            qv4_e1 <= qv3_h[2+HI];
            bs_g   <= bs_h[HI];
        end
        wire [4*AWD-1:0] pair0 = qv4_e0 ? amp_quad0[LO +: 4*AWD] : e4_hold_amp2[LO +: 4*AWD];
        assign e4_pair_amp1[LO +: 4*AWD] =
                                 qv4_e1 ? amp_quad1[LO +: 4*AWD] : e4_hold_amp3[LO +: 4*AWD];
        assign sq0_in_amp[LO +: 4*AWD] = bs_g ? pair0 : amp_rdata[LO +: 4*AWD];
    end endgenerate

    // Square engine 0 serves BUILD (even row of each pair) and the reread.
    wire sq0_in_valid = build_sel ? e4_build_pair_valid : amp_req_valid_d4;
    wire [`GP_ROW_W-1:0] sq0_in_row = build_sel ? e4_pair_row0 : amp_req_row_d4;

    wire                 sq0_valid, sq1_valid, sq0_sq_valid;
    wire [`GP_ROW_W-1:0] sq0_row, sq1_row;
    wire [P*SQW-1:0]     sq0_lane;
    wire [RSW-1:0]       sq0_row_sum, sq1_row_sum;

    grover_born_square32_p u_square32 (
        .clk(clk), .rstn(rstn),
        .in_valid(sq0_in_valid), .in_row(sq0_in_row), .in_amp(sq0_in_amp),
        .sq_valid(sq0_sq_valid), .out_sq(sq0_lane),
        .out_valid(sq0_valid), .out_row(sq0_row), .out_row_sum(sq0_row_sum)
    );

    wire                 sq1_sq_valid_unused;
    wire [P*SQW-1:0]     sq1_lane_unused;
    grover_born_square32_p u_square32_b (
        .clk(clk), .rstn(rstn),
        .in_valid(e4_build_pair_valid), .in_row(e4_pair_row1), .in_amp(e4_pair_amp1),
        .sq_valid(sq1_sq_valid_unused), .out_sq(sq1_lane_unused),
        .out_valid(sq1_valid), .out_row(sq1_row), .out_row_sum(sq1_row_sum)
    );

    //-------------------------------------------------------------------------
    // Row-weight memory (two writes/cycle during BUILD, one read/cycle).
    //-------------------------------------------------------------------------
    wire                         rw_rd_en;
    wire [`GP_ROW_W-1:0]         rw_rd_row;
    wire [RSW-1:0]               rw_rd_weight;

    wire rw_wr0_en = (st == S_BUILD) && sq0_valid;
    wire rw_wr1_en = (st == S_BUILD) && sq1_valid;

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

    //-------------------------------------------------------------------------
    // Rejection mapper.  k_bits now settles two edges after total_weight;
    // it is first used on the S_RND_MAP edge, three edges after S_CHECK_W.
    //-------------------------------------------------------------------------
    reg [31:0] rnd_hi;
    reg [31:0] rnd_lo;
    wire [63:0] rnd64 = {rnd_hi, rnd_lo};

    wire [5:0]    reject_k_bits;
    wire [TW-1:0] reject_candidate;
    wire          reject_accept;
    wire          reject_direct_one;
    wire          reject_zero_weight;

    wire reject_map_candidate = (st == S_RND_MAP);
    reg  reject_accept_r;

    grover_born_reject64 u_reject64 (
        .clk           (clk),
        .rstn          (rstn),
        .load_weight   (1'b1),
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
    // BUILD total W: pair sum register, then the running total.
    //-------------------------------------------------------------------------
    reg [TW-1:0]        build_total;
    reg                 psum_valid;
    reg [`GP_ROW_W-1:0] psum_row;
    reg [RSW:0]         psum;
    wire [TW-1:0] build_total_next;
    grover_add60_cs u_badd(.a(build_total), .b({{(TW-RSW-1){1'b0}}, psum}), .sum(build_total_next));

    //-------------------------------------------------------------------------
    // E4 M2 group endpoints: group_cdf[g] = sum(row_weight[0 .. 32*(g+1)-1]).
    //-------------------------------------------------------------------------
    reg [TW-1:0] group_cdf [0:15];
    reg          gcdf_we;
    reg [3:0]    gcdf_idx;
    reg [4:0]    group_issue;      // next endpoint to read, 16 = done
    reg          gq_valid;
    reg [3:0]    gq_index;
    reg [TW-1:0] gq_cdf;
    reg [TW-1:0] rem_cand;         // r - (endpoint of the last group passed)

    // group_take = gq_cdf > r, i.e. the borrow of r - gq_cdf.  200 MHz: the
    // subtraction result is registered (gc_*) before the scan decides, so the
    // scan is read -> subtract -> decide, one group per cycle as before.
    wire [TW-1:0] group_diff_c;
    wire          group_take_c;
    grover_sub60_cs u_gsub(.a(threshold), .b(gq_cdf), .diff(group_diff_c), .borrow(group_take_c));
    reg           gc_valid;
    reg  [3:0]    gc_index;
    reg  [TW-1:0] group_diff;
    reg           group_take;
    wire [`GP_ROW_W:0] group_base_count = {1'b0, gc_index, 5'b00000};

    //-------------------------------------------------------------------------
    // Row scan inside the selected group.
    //-------------------------------------------------------------------------
    reg [`GP_ROW_W:0]   row_issue_count;
    reg [`GP_ROW_W:0]   row_scan_limit;
    reg                 rw_valid_d;
    reg [`GP_ROW_W-1:0] rw_row_d;
    reg                 rw_pipe_valid;
    reg [`GP_ROW_W-1:0] rw_row_pipe;
    reg [RSW-1:0]       rw_weight_pipe;
    reg [TW-1:0]        rem;           // r - cumulative before rw_row_pipe;
                                       // after the row scan it is local_r

    // 200 MHz: the row-weight read request is registered before the BRAM
    // (rw_req_*); the row tag pipeline below is one stage longer to match.
    wire                rw_issue     = (st == S_ROW_SCAN) && (row_issue_count < row_scan_limit);
    wire [`GP_ROW_W-1:0] rw_issue_row = row_issue_count[`GP_ROW_W-1:0];
    reg                 rw_req_v;
    reg [`GP_ROW_W-1:0] rw_req_row;
    assign rw_rd_en  = rw_req_v;
    assign rw_rd_row = rw_req_row;

    wire [TW-1:0] rw_weight_ext = {{(TW-RSW){1'b0}}, rw_weight_pipe};
    wire [TW-1:0] row_diff;
    wire          row_take;                // weight > rem
    grover_sub60_cs u_rsub(.a(rem), .b(rw_weight_ext), .diff(row_diff), .borrow(row_take));

    //-------------------------------------------------------------------------
    // Lane scan inside the selected row.
    //-------------------------------------------------------------------------
    reg [P*SQW-1:0]    lane_sh;
    reg [`GP_LOGP-1:0] lane_index;
    reg [TW-1:0]       lane_rem;       // local_r - cumulative before this lane

    wire [TW-1:0] lane_sq_ext = {{(TW-SQW){1'b0}}, lane_sh[SQW-1:0]};
    wire [TW-1:0] lane_diff;
    wire          lane_take;               // square > lane_rem
    grover_sub60_cs u_lsub(.a(lane_rem), .b(lane_sq_ext), .diff(lane_diff), .borrow(lane_take));

    // Rotate rather than shift: lane_index is 5 bits and wraps, so after
    // lane 31 the 100 MHz scan would look at lane 0 again; rotating keeps
    // that (unreachable) case identical too.
    always @(posedge clk) begin
        if (lane_wait_sel) lane_sh <= sq0_lane;
        else               lane_sh <= {lane_sh[SQW-1:0], lane_sh[P*SQW-1:SQW]};
    end

    //-------------------------------------------------------------------------
    // amp_mem single-row request
    //-------------------------------------------------------------------------
    always @* begin
        amp_rd_en  = (st == S_LANE_REQ);
        amp_rd_row = selected_row;
    end

    assign busy = (st != S_IDLE);

    //-------------------------------------------------------------------------
    // Controller
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rstn) begin
            st                <= S_IDLE;
            build_sel         <= 1'b0;
            lane_wait_sel     <= 1'b0;
            done              <= 1'b0;
            zero_weight_error <= 1'b0;
            candidate         <= {`GP_INDEX_W{1'b0}};
            total_weight      <= {TW{1'b0}};
            threshold         <= {TW{1'b0}};
            selected_row      <= {`GP_ROW_W{1'b0}};

            amp_req_valid_d   <= 1'b0;
            amp_req_valid_d2  <= 1'b0;
            amp_req_valid_d3  <= 1'b0;
            amp_req_valid_d4  <= 1'b0;
            amp_req_row_d     <= {`GP_ROW_W{1'b0}};
            amp_req_row_d2    <= {`GP_ROW_W{1'b0}};
            amp_req_row_d3    <= {`GP_ROW_W{1'b0}};
            amp_req_row_d4    <= {`GP_ROW_W{1'b0}};
            reject_accept_r   <= 1'b0;
            build_total       <= {TW{1'b0}};
            psum_valid        <= 1'b0;
            psum_row          <= {`GP_ROW_W{1'b0}};
            psum              <= {(RSW+1){1'b0}};

            e4_quad_issue_count <= 8'd0;
            e4_quad_resp_count  <= 8'd0;
            e4_quad_req_gap     <= 1'b0;
            e4_hold_valid       <= 1'b0;
            e4_hold_row2        <= {`GP_ROW_W{1'b0}};
            e4_hold_row3        <= {`GP_ROW_W{1'b0}};

            rnd_hi            <= 32'd0;
            rnd_lo            <= 32'd0;

            group_issue       <= 5'd0;
            gq_valid          <= 1'b0;
            gc_valid          <= 1'b0;
            gcdf_we           <= 1'b0;
            gcdf_idx          <= 4'd0;
            gq_index          <= 4'd0;
            rem_cand          <= {TW{1'b0}};
            row_issue_count   <= {(`GP_ROW_W+1){1'b0}};
            row_scan_limit    <= `GP_ROWS;
            rw_valid_d        <= 1'b0;
            rw_req_v          <= 1'b0;
            rw_req_row        <= {`GP_ROW_W{1'b0}};
            rw_row_d          <= {`GP_ROW_W{1'b0}};
            rw_pipe_valid     <= 1'b0;
            rw_row_pipe       <= {`GP_ROW_W{1'b0}};
            rem               <= {TW{1'b0}};

            lane_index        <= {`GP_LOGP{1'b0}};
            lane_rem          <= {TW{1'b0}};
        end else begin
            done              <= 1'b0;
            zero_weight_error <= 1'b0;

            // Selected-row reread alignment.
            amp_req_valid_d  <= amp_rd_en;
            amp_req_valid_d2 <= amp_req_valid_d;
            amp_req_valid_d3 <= amp_req_valid_d2;
            amp_req_valid_d4 <= amp_req_valid_d3;
            if (amp_rd_en)        amp_req_row_d  <= amp_rd_row;
            if (amp_req_valid_d)  amp_req_row_d2 <= amp_req_row_d;
            if (amp_req_valid_d2) amp_req_row_d3 <= amp_req_row_d2;
            if (amp_req_valid_d3) amp_req_row_d4 <= amp_req_row_d3;

            // Row-weight read pipeline: request reg -> BRAM -> timing register.
            rw_req_v   <= rw_issue;
            if (rw_issue)
                rw_req_row <= rw_issue_row;
            rw_valid_d <= rw_rd_en;
            if (rw_rd_en)
                rw_row_d <= rw_rd_row;
            rw_pipe_valid <= rw_valid_d;
            if (rw_valid_d) begin
                rw_row_pipe    <= rw_row_d;
                rw_weight_pipe <= rw_rd_weight;
            end

            // Group endpoint write, one cycle after the add that ends a group.
            gcdf_we  <= (st == S_BUILD) && psum_valid && (psum_row[4:0] == 5'd31);
            gcdf_idx <= psum_row[`GP_ROW_W-1:5];
            if (gcdf_we)
                group_cdf[gcdf_idx] <= build_total;

            // BUILD pair sum.  Both square engines see the same pair, so
            // their row sums are valid on the same cycle.
            psum_valid <= (st == S_BUILD) && sq0_valid && sq1_valid;
            psum_row   <= sq1_row;
            psum       <= {1'b0, sq0_row_sum} + {1'b0, sq1_row_sum};

            // Group endpoint prefetch.
            gq_valid <= (st == S_GROUP_SCAN) && (group_issue < 5'd16);
            gq_index <= group_issue[3:0];
            gq_cdf   <= group_cdf[group_issue[3:0]];
            gc_valid   <= (st == S_GROUP_SCAN) && gq_valid;
            gc_index   <= gq_index;
            group_diff <= group_diff_c;
            group_take <= group_take_c;
            if ((st == S_GROUP_SCAN) && (group_issue < 5'd16))
                group_issue <= group_issue + 1'b1;

            // E4 M1 quad request cadence and 4-row -> 2-row serialization.
            if (st == S_BUILD) begin
                if (amp_quad_rd_en) begin
                    e4_quad_issue_count <= e4_quad_issue_count + 1'b1;
                    e4_quad_req_gap <= 1'b1;
                end else begin
                    e4_quad_req_gap <= 1'b0;
                end

                if (quad_now) begin
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

            // Rows {2,3} of the quad are used on the cycle after the quad
            // arrives; capturing every cycle (no enable) keeps exactly that
            // copy for that cycle and frees 1,472 flops from one CE net.
            e4_hold_amp2 <= amp_quad2;
            e4_hold_amp3 <= amp_quad3;

            // Rejection test registered for S_RND_CHECK.
            reject_accept_r <= reject_accept;

            case (st)
                S_IDLE: begin
                    amp_req_valid_d  <= 1'b0;
                    amp_req_valid_d2 <= 1'b0;
                    amp_req_valid_d3 <= 1'b0;
                    amp_req_valid_d4 <= 1'b0;
                    rw_valid_d       <= 1'b0;
                    rw_req_v         <= 1'b0;
                    rw_pipe_valid    <= 1'b0;
                    if (start) begin
                        candidate            <= {`GP_INDEX_W{1'b0}};
                        total_weight         <= {TW{1'b0}};
                        threshold            <= {TW{1'b0}};
                        selected_row         <= {`GP_ROW_W{1'b0}};
                        build_total          <= {TW{1'b0}};
                        e4_quad_issue_count  <= 8'd0;
                        e4_quad_resp_count   <= 8'd0;
                        e4_quad_req_gap      <= 1'b0;
                        e4_hold_valid        <= 1'b0;
                        row_scan_limit       <= `GP_ROWS;
                        build_sel            <= 1'b1;
                        st                   <= S_BUILD;
                    end
                end

                // BUILD: two exact row sums per cycle.  When the odd row of a
                // pair is the last row of a 32-row group, the updated total is
                // exactly that group's CDF endpoint.
                // 200 MHz: the group endpoint and W are copied from the
                // build_total register one cycle after the add (gcdf_* below,
                // S_BUILD_FIN), not from the adder output.
                S_BUILD: begin
                    if (psum_valid) begin
                        build_total <= build_total_next;
                        if (psum_row == (`GP_ROWS-1)) begin
                            e4_hold_valid <= 1'b0;
                            build_sel     <= 1'b0;
                            st            <= S_BUILD_FIN;
                        end
                    end
                end

                S_BUILD_FIN: begin
                    total_weight <= build_total;
                    st           <= S_CHECK_W;
                end

                S_CHECK_W: begin
                    amp_req_valid_d <= 1'b0;
                    if (reject_zero_weight) begin
                        st <= S_ZERO;
                    end else if (reject_direct_one) begin
                        // Direct W=1 case: no LFSR draw, r = 0.
                        threshold   <= {TW{1'b0}};
                        rem_cand    <= {TW{1'b0}};
                        group_issue <= 5'd0;
                        st          <= S_GROUP_SCAN;
                    end else begin
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
                    st <= S_RND_CMP;
                end

                // reject_accept_r <= (candidate < W) on this edge.
                S_RND_CMP: begin
                    st <= S_RND_CHECK;
                end

                S_RND_CHECK: begin
                    if (reject_accept_r) begin
                        threshold   <= reject_candidate;
                        rem_cand    <= reject_candidate;
                        group_issue <= 5'd0;
                        st          <= S_GROUP_SCAN;
                    end else begin
                        // Rejection consumes no draw here; the next attempt
                        // starts with a completely fresh HI->LO pair.
                        st <= S_RND_HI;
                    end
                end

                // E4 M2: FIRST group endpoint > r.  gq_* is the endpoint read
                // on the previous cycle; rem_cand = r - endpoint of the group
                // before it (r for group 0).
                S_GROUP_SCAN: begin
                    if (gc_valid) begin
                        if (group_take) begin
                            row_issue_count <= group_base_count;
                            row_scan_limit  <= group_base_count + 10'd32;
                            rem             <= rem_cand;
                            rw_valid_d      <= 1'b0;
                            rw_req_v        <= 1'b0;
                            rw_pipe_valid   <= 1'b0;
                            st              <= S_ROW_SCAN;
                        end else begin
                            rem_cand <= group_diff;
                            if (gc_index == 4'd15) begin
                                // Mathematically unreachable for valid r < W.
                                // Same deterministic fallback to the last group.
                                row_issue_count <= 10'd480;
                                row_scan_limit  <= 10'd512;
                                rem             <= rem_cand;
                                rw_valid_d      <= 1'b0;
                            rw_req_v        <= 1'b0;
                                rw_pipe_valid   <= 1'b0;
                                st              <= S_ROW_SCAN;
                            end
                        end
                    end
                end

                // FIRST row with cumulative > r, i.e. weight > rem.
                S_ROW_SCAN: begin
                    if (rw_issue)
                        row_issue_count <= row_issue_count + 1'b1;

                    if (rw_pipe_valid) begin
                        if (row_take) begin
                            // rem is left as is: it is local_r now.
                            selected_row    <= rw_row_pipe;
                            rw_valid_d      <= 1'b0;
                            rw_req_v        <= 1'b0;
                            rw_pipe_valid   <= 1'b0;
                            st              <= S_LANE_REQ;
                        end else begin
                            rem <= row_diff;
                        end
                    end
                end

                // One selected amp row is reread through square engine 0.
                S_LANE_REQ: begin
                    lane_wait_sel <= 1'b1;
                    st <= S_LANE_WAIT;
                end

                // lane_sh follows sq0_lane while waiting; the cycle the reread
                // squares are valid is the cycle it keeps them.
                S_LANE_WAIT: begin
                    if (sq0_sq_valid) begin
                        lane_wait_sel <= 1'b0;
                        lane_index    <= {`GP_LOGP{1'b0}};
                        lane_rem      <= rem;
                        st            <= S_LANE_SCAN;
                    end
                end

                // FIRST lane with cumulative > local_r, i.e. square > lane_rem.
                S_LANE_SCAN: begin
                    if (lane_take) begin
                        candidate <= {selected_row, lane_index};
                        st <= S_FIN;
                    end else begin
                        lane_rem   <= lane_diff;
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

    wire _unused_reject_k = ^reject_k_bits;
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
    // 200 MHz: the E4 data memory passes the verify index through a two-level
    // request tree and the BRAM word through a two-stage lane select, so the
    // value for an index presented on edge 0 is first valid after edge 4 (the
    // found-mask bit after edge 3).  S_WAIT1..S_WAIT4 hold candidate_r (the
    // address) stable over those extra edges.  S_EVAL is split in two: the
    // predicate is registered (S_EVAL) and committed (S_COMMIT), with the run
    // configuration copied into local registers first.
    localparam [3:0] S_IDLE    = 4'd0;
    localparam [3:0] S_CAPTURE = 4'd1;
    localparam [3:0] S_EVAL    = 4'd2;
    localparam [3:0] S_WAIT1   = 4'd3;
    localparam [3:0] S_WAIT2   = 4'd4;
    localparam [3:0] S_WAIT3   = 4'd5;
    localparam [3:0] S_WAIT4   = 4'd6;
    localparam [3:0] S_COMMIT  = 4'd7;

    reg [3:0] st;
    reg [`GP_INDEX_W-1:0] candidate_r;
    reg signed [`GP_DATA_W-1:0] data_verify_value_r;
    reg found_mask_verify_found_r;

    // Present the incoming candidate immediately so data_mem/found_mask launch
    // their synchronous verify reads on the same edge that start is accepted.
    // candidate_r then holds that address stable through CAPTURE and EVAL.
    assign data_verify_index = (st == S_IDLE && start) ? candidate : candidate_r;
    assign busy = (st != S_IDLE);

    // Local copies of the run configuration (fixed during a run; see the
    // E4 datapath header) so the verify predicate starts from nearby flops.
    reg [1:0]                    mode_l;
    reg signed [`GP_DATA_W-1:0]  thr_a_l, thr_b_l;
    reg [`GP_DATA_COUNT_W-1:0]   count_l;
    reg                          enum_l;
    always @(posedge clk) begin
        mode_l  <= predicate_mode;
        thr_a_l <= threshold_a;
        thr_b_l <= threshold_b;
        count_l <= data_count;
        enum_l  <= (enum_enable === 1'b1);
    end

    wire pred_hit;
    reg  hit_r;
    grover_predicate u_verify_predicate (
        .mode        (mode_l),
        .value       (data_verify_value_r),
        .threshold_a (thr_a_l),
        .threshold_b (thr_b_l),
        .index       (candidate_r),
        .data_count  (count_l),
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
                        st          <= S_WAIT1;
                    end
                end

                S_WAIT1: st <= S_WAIT2;
                S_WAIT2: st <= S_WAIT3;
                S_WAIT3: st <= S_WAIT4;
                S_WAIT4: st <= S_CAPTURE;

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
                    hit_r <= pred_hit && (!enum_l || !found_mask_verify_found_r);
                    st    <= S_COMMIT;
                end

                S_COMMIT: begin
                    hit  <= hit_r;
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
