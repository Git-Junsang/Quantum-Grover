//==============================================================================
// grover_arithmetic.v -- BBHT/Grover Main IP v0.7f consolidated RTL
//
// File-level consolidation/module hierarchy is preserved. v0.7f keeps the
// Candidate-B adder-tree timing cut and adds a resource-oriented predicate
// option: PASS1 can bypass the duplicated per-lane full-width padding
// comparator because padding is generated once per row in the iteration
// datapath. GT/RANGE signed-subtraction logic is intentionally unchanged.
// Consolidated from: grover_predicate.v, grover_adder_tree.v, grover_sum_accum.v, grover_two_mean_calc.v, grover_oracle_flip.v, grover_diffusion_sat.v
//==============================================================================


//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_predicate.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_predicate.v -- BBHT/Grover Main IP v0.6
//
// Combinational predicate + padding gate.
//   target(index) = (index < data_count) && predicate(data[index])
//
// Predicate contract:
//   LT    : value <  threshold_a
//   GT    : value >  threshold_a
//   EQ    : value == threshold_a
//   RANGE : threshold_a < value < threshold_b   (open interval)
//
// DATA is signed 16-bit.  RANGE with A >= B naturally produces no hits and is
// NOT a config_error.  Padding always wins: index >= data_count => hit=0.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_predicate #(
    // USE_PADDING=1 preserves the original v0.6 standalone contract:
    //     hit = (index < data_count) && predicate(value)
    //
    // USE_PADDING=0 is used only by the 32 PASS1 lane predicates in v0.7f.
    // There, one shared row-level padding mask is applied later, so synthesizing
    // 32 copies of the full INDEX_W/DATA_COUNT_W comparison is unnecessary.
    parameter integer USE_PADDING = 1
) (
    input  wire [1:0]                           mode,
    input  wire signed [`GP_DATA_W-1:0]         value,
    input  wire signed [`GP_DATA_W-1:0]         threshold_a,
    input  wire signed [`GP_DATA_W-1:0]         threshold_b,
    input  wire [`GP_INDEX_W-1:0]               index,
    input  wire [`GP_DATA_COUNT_W-1:0]          data_count,
    output wire                                  hit
);
    localparam W = `GP_DATA_W;

    // Keep the original W+1 signed-subtraction implementation exactly.
    // In particular, v0.7f does NOT replace the GT/RANGE subtractors.
    wire signed [W:0] v_ext  = {value[W-1],       value};
    wire signed [W:0] a_ext  = {threshold_a[W-1], threshold_a};
    wire signed [W:0] b_ext  = {threshold_b[W-1], threshold_b};

    wire signed [W:0] v_minus_a = v_ext - a_ext;
    wire signed [W:0] a_minus_v = a_ext - v_ext;
    wire signed [W:0] v_minus_b = v_ext - b_ext;

    wire pred_lt    = v_minus_a[W];                  // value < A
    wire pred_gt    = a_minus_v[W];                  // A < value
    wire pred_eq    = (value == threshold_a);
    wire pred_range = a_minus_v[W] & v_minus_b[W];  // A < value < B

    reg pred;
    always @* begin
        case (mode)
            `GP_MODE_LT:    pred = pred_lt;
            `GP_MODE_GT:    pred = pred_gt;
            `GP_MODE_EQ:    pred = pred_eq;
            `GP_MODE_RANGE: pred = pred_range;
            default:        pred = 1'b0;
        endcase
    end

    generate
        if (USE_PADDING != 0) begin : g_with_padding
            wire [`GP_DATA_COUNT_W-1:0] index_ext =
                {{(`GP_DATA_COUNT_W-`GP_INDEX_W){1'b0}}, index};
            wire in_valid_data = (index_ext < data_count);
            assign hit = in_valid_data & pred;
        end else begin : g_without_padding
            // Shared padding is applied in grover_iter_datapath.
            // Because this is a generate-time constant branch, Vivado can
            // remove the unused per-lane index/data_count comparator entirely.
            assign hit = pred;
        end
    endgenerate
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_predicate.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_adder_tree.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_adder_tree.v -- 32-lane balanced signed amplitude adder tree, v0.7
//
// Input:  P=32 signed AMP_W=23 Oracle amplitudes, lane 0 at LSB slice.
// Output: AMP_W+log2(P)=28-bit exact row partial sum.
// Pairing order remains exactly the GitHub/SW-Golden contract:
//   stage1 (0,1)(2,3)... ; then adjacent pairs through stage5.
//
// v0.7 100-MHz timing-closure retiming (Candidate B):
//   stage1 -> stage2 -> stage3 -> [4 x PSW REG] -> stage4 -> stage5
//
// The register is inserted only between original tree stages 3 and 4.  No
// addend order, width, rounding, or saturation rule changes; therefore the
// arithmetic result is bit-exact to the original five-level tree.  This cuts
// the synthesized amp_row_out->tree->global-accumulator critical path while
// keeping the frozen P=32 pairing order intact.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_adder_tree (
    input  wire                                      clk,
    input  wire                                      rstn,
    input  wire                                      en,
    input  wire [`GP_P*`GP_AMP_W-1:0]               din,
    output wire signed [`GP_PARTIAL_SUM_W-1:0]       partial,
    output reg                                       valid_out
);
    localparam P   = `GP_P;
    localparam AW  = `GP_AMP_W;
    localparam PSW = `GP_PARTIAL_SUM_W;
    localparam CUT = 3;               // Candidate-B boundary: after stage 3.
    localparam CUT_N = P >> CUT;      // P=32 -> 4 registered partials.

    // Pre-cut tree: leaves + original stages 1..3.  Every node is kept at PSW,
    // exactly as in the v0.6/GitHub tree, so no intermediate overflow occurs.
    wire signed [PSW-1:0] pre_node [0:(CUT+1)*P-1];

    genvar s, i;
    generate
        for (i = 0; i < P; i = i + 1) begin : g_leaf
            wire signed [AW-1:0] leaf;
            assign leaf = din[i*AW +: AW];
            assign pre_node[i] = {{(PSW-AW){leaf[AW-1]}}, leaf};
        end
        for (s = 1; s <= CUT; s = s + 1) begin : g_pre_stage
            for (i = 0; i < (P >> s); i = i + 1) begin : g_node
                assign pre_node[s*P+i] = pre_node[(s-1)*P+2*i] +
                                         pre_node[(s-1)*P+2*i+1];
            end
        end
    endgenerate

    // Timing boundary: stage-3 produces four PSW-wide values for P=32.
    reg signed [PSW-1:0] cut_reg [0:CUT_N-1];
    integer r;
    always @(posedge clk) begin
        if (!rstn) begin
            valid_out <= 1'b0;
            for (r = 0; r < CUT_N; r = r + 1)
                cut_reg[r] <= {PSW{1'b0}};
        end else begin
            valid_out <= en;
            if (en) begin
                for (r = 0; r < CUT_N; r = r + 1)
                    cut_reg[r] <= pre_node[CUT*P+r];
            end
        end
    end

    // Post-cut original stages 4 and 5.  P=32 baseline => 4 -> 2 -> 1.
    wire signed [PSW-1:0] stage4_0 = cut_reg[0] + cut_reg[1];
    wire signed [PSW-1:0] stage4_1 = cut_reg[2] + cut_reg[3];
    assign partial = stage4_0 + stage4_1;
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_adder_tree.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_sum_accum.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_sum_accum.v -- global Oracle-amplitude sum accumulator, v0.6
//
// Accumulates one exact 32-lane partial sum per valid row during PASS1.
// clear has priority over en.  ACC_W=39 follows the frozen v0.6 contract.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_sum_accum (
    input  wire                                      clk,
    input  wire                                      rstn,
    input  wire                                      clear,
    input  wire                                      en,
    input  wire signed [`GP_PARTIAL_SUM_W-1:0]       partial,
    output reg  signed [`GP_ACC_W-1:0]               total
);
    wire signed [`GP_ACC_W-1:0] partial_ext =
        {{(`GP_ACC_W-`GP_PARTIAL_SUM_W){partial[`GP_PARTIAL_SUM_W-1]}}, partial};

    always @(posedge clk) begin
        if (!rstn)
            total <= {`GP_ACC_W{1'b0}};
        else if (clear)
            total <= {`GP_ACC_W{1'b0}};
        else if (en)
            total <= total + partial_ext;
    end
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_sum_accum.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_two_mean_calc.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_two_mean_calc.v -- 2*mean with nearest-even rounding, v0.6
//
// For compile-time Q:
//   2*mean = total / 2^(Q-1)
//
// total is an integer fixed-point code sum.  The single right-shift is rounded
// to nearest, ties-to-even.  Do NOT implement as two separately rounded shifts.
// Output width is the frozen signed TWO_MEAN_W=25.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_two_mean_calc (
    input  wire signed [`GP_ACC_W-1:0]         total,
    output wire signed [`GP_TWO_MEAN_W-1:0]    two_mean
);
    localparam K = `GP_Q - 1;

    wire signed [`GP_ACC_W-1:0] q = total >>> K;
    wire [`GP_ACC_W-1:0] total_u = total;

    wire round_bit = (K == 0) ? 1'b0 : total_u[K-1];

    wire [`GP_ACC_W-1:0] low_mask =
        (K <= 1) ? {`GP_ACC_W{1'b0}} :
        (({{(`GP_ACC_W-1){1'b0}},1'b1} << (K-1)) -
         {{(`GP_ACC_W-1){1'b0}},1'b1});

    wire sticky = |(total_u & low_mask);
    wire increment = round_bit & (sticky | q[0]);

    wire signed [`GP_ACC_W-1:0] rounded =
        q + {{(`GP_ACC_W-1){1'b0}}, increment};

    assign two_mean = rounded[`GP_TWO_MEAN_W-1:0];
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_two_mean_calc.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_oracle_flip.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_oracle_flip.v -- conditional Oracle phase inversion, v0.6
//
// Symmetric amplitude range excludes the most-negative two's-complement code,
// therefore sign inversion is exact for every legal stored amplitude.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_oracle_flip (
    input  wire signed [`GP_AMP_W-1:0] amp_in,
    input  wire                         hit,
    output wire signed [`GP_AMP_W-1:0] amp_out
);
    wire [`GP_AMP_W-1:0] flipped =
        (amp_in ^ {`GP_AMP_W{hit}}) + {{(`GP_AMP_W-1){1'b0}}, hit};

    assign amp_out = $signed(flipped);
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_oracle_flip.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_diffusion_sat.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_diffusion_sat.v -- diffusion subtract + symmetric saturation, v0.6
//
//   diff = two_mean - oracle_amp
//
// Both operands are evaluated in the frozen DIFF_W=25 signed path, then the
// result is saturated to the legal symmetric AMP_W=23 range:
//   [ -4194303, +4194303 ] for F22 baseline.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_diffusion_sat (
    input  wire signed [`GP_TWO_MEAN_W-1:0] two_mean,
    input  wire signed [`GP_AMP_W-1:0]      oracle_amp,
    output wire signed [`GP_AMP_W-1:0]      amp_out,
    output wire                              sat
);
    wire signed [`GP_DIFF_W-1:0] tm_ext =
        {{(`GP_DIFF_W-`GP_TWO_MEAN_W){two_mean[`GP_TWO_MEAN_W-1]}}, two_mean};
    wire signed [`GP_DIFF_W-1:0] amp_ext =
        {{(`GP_DIFF_W-`GP_AMP_W){oracle_amp[`GP_AMP_W-1]}}, oracle_amp};

    wire signed [`GP_DIFF_W-1:0] diff = tm_ext - amp_ext;

    wire signed [`GP_DIFF_W-1:0] sat_hi =
        {{(`GP_DIFF_W-`GP_AMP_W){1'b0}}, `GP_AMP_MAX};
    wire signed [`GP_DIFF_W-1:0] sat_lo =
        {{(`GP_DIFF_W-`GP_AMP_W){1'b1}}, `GP_AMP_MIN};

    wire over_hi = (diff > sat_hi);
    wire over_lo = (diff < sat_lo);

    assign amp_out = over_hi ? `GP_AMP_MAX :
                     over_lo ? `GP_AMP_MIN : diff[`GP_AMP_W-1:0];
    assign sat = over_hi | over_lo;
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_diffusion_sat.v
//------------------------------------------------------------------------------
