//==============================================================================
// grover_iteration.v -- BBHT/Grover Main IP v0.7g consolidated RTL
//
// File-level consolidation is preserved; module hierarchy is unchanged.
// v0.7 adds PASS1 timing-closure pipeline boundaries and one S_P1DRN cycle.
// Algorithmic arithmetic/results are unchanged; busy latency increases only.
// Consolidated from: grover_iter_datapath.v, grover_ctrl_fsm.v
//==============================================================================


//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_iter_datapath.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_iter_datapath.v -- BBHT/Grover Main IP v0.7 timing closure
//
// Grover one-iteration arithmetic datapath only.
// No BBHT, cache, Born measurement, loader control, or iteration FSM is included.
// Step 5 will provide the BRAM/FSM timing around this block.
//
// Operation contract
//   OP_INIT  : output one uniform-amplitude row (raw 32768 for Q14/F22)
//   OP_PASS1 : predicate/padding -> Oracle sign flip -> row sum -> global sum
//   OP_MEAN  : latch 2*mean = round-even(global_sum / 2^(Q-1))
//   OP_PASS2 : diff = two_mean - stored Oracle amplitude -> symmetric saturation
//
// v0.7 PASS1 timing-closure pipeline boundary
//   100 MHz timing analysis on xc7a100tcsg324-1 showed the dominant setup path
//   traversing:
//
//     data_mem BRAM -> predicate -> Oracle -> 32-lane adder tree
//                   -> global sum accumulator
//
//   with approximately -6.574 ns worst setup slack before this change.
//
//   The existing amp_row_out writeback register is therefore reused as a
//   pipeline boundary. PASS1 now operates as:
//
//     Stage A : BRAM -> predicate -> Oracle -> amp_row_out REG
//     Stage B : amp_row_out REG -> adder tree -> global accumulator REG
//
//   amp_row_out is NOT a second state/cache copy. The same registered Oracle
//   row fans out to both:
//     (1) amp_mem writeback, and
//     (2) the PASS1 row-sum path.
//
//   Functional arithmetic is unchanged. v0.7 Candidate-B adder retiming adds
//   one more PASS1 sum-pipeline cycle after amp_row_out: original adder stages
//   1..3 are followed by a register, then stages 4..5 and the accumulator.
//   The controller therefore inserts one explicit PASS1 drain cycle after the
//   final amp_mem write before entering S_MEAN.
//
// acc_clear must be asserted before the first valid PASS1 row reaches this
// datapath. It has priority over accumulation, matching grover_sum_accum.v.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_iter_datapath (
    input  wire                                      clk,
    input  wire                                      rstn,

    // Controller-facing operation control.
    input  wire [1:0]                                op,
    input  wire                                      row_valid,
    input  wire [`GP_ROW_W-1:0]                      row_index,
    input  wire                                      acc_clear,

    // Row data returned from amp_mem/data_mem and aligned to row_index.
    input  wire [`GP_P*`GP_AMP_W-1:0]                amp_row_in,
    input  wire [`GP_P*`GP_DATA_W-1:0]               data_row_in,
    // Enumeration found-mask row, synchronous-aligned with data_row_in.
    input  wire [`GP_P-1:0]                           found_mask_row_in,

    // Oracle configuration.
    input  wire [1:0]                                predicate_mode,
    input  wire signed [`GP_DATA_W-1:0]              threshold_a,
    input  wire signed [`GP_DATA_W-1:0]              threshold_b,
    input  wire [`GP_DATA_COUNT_W-1:0]               data_count,
    input  wire                                      enum_enable,

    // Registered row result for amp_mem writeback.
    output reg  [`GP_P*`GP_AMP_W-1:0]                amp_row_out,
    output reg                                       row_out_valid,
    output reg  [`GP_ROW_W-1:0]                      row_out_index,

    // Debug/Golden-trace observability.
    output wire signed [`GP_PARTIAL_SUM_W-1:0]        row_partial_sum,
    output wire signed [`GP_ACC_W-1:0]                global_sum,
    output reg  signed [`GP_TWO_MEAN_W-1:0]           two_mean,

    // One-cycle indication aligned with row_out_valid for a PASS2 row.
    output reg                                       sat_event
);
    localparam [1:0] OP_INIT  = 2'd0;
    localparam [1:0] OP_PASS1 = 2'd1;
    localparam [1:0] OP_MEAN  = 2'd2;
    localparam [1:0] OP_PASS2 = 2'd3;

    localparam integer P       = `GP_P;
    localparam integer AMP_W   = `GP_AMP_W;
    localparam integer DATA_W  = `GP_DATA_W;
    localparam integer LOGP    = `GP_LOGP;
    localparam integer ROW_W   = `GP_ROW_W;
    localparam integer COUNT_W = `GP_DATA_COUNT_W;

    //==========================================================================
    // v0.7f PASS1 predicate/padding timing + resource optimization
    //
    // Routed v0.7d implementation exposed a remaining path:
    //
    //   data_mem BRAM -> predicate/padding -> Oracle -> amp_row_out
    //
    // v0.7f makes one deliberate timing cut AFTER the data predicate result,
    // while leaving the predicate arithmetic itself unchanged:
    //
    //   Stage A:
    //     data_mem -> LT/GT/EQ/RANGE predicate -> pred/amp/row/count REG
    //
    //   Stage B:
    //     shared row-level padding mask -> Oracle -> amp_row_out REG
    //
    // The amplitude row/tag/count are pipelined with the predicate result, so a
    // streamed row can never be combined with the following row's metadata.
    //
    // Padding resource optimization for P=32:
    //   full_rows = data_count >> 5
    //   tail      = data_count[4:0]
    //
    //   row < full_rows : all 32 lanes valid
    //   row = full_rows : lane < tail only
    //   row > full_rows : all lanes padding
    //
    // This is exactly equivalent to basis_index < data_count, including
    // data_count multiples of 32 and data_count=16384. It removes 32 duplicated
    // full-width padding comparisons from PASS1. The standalone predicate used
    // by measurement verification still keeps its original padding comparator.
    //==========================================================================

    wire [P-1:0] pass1_pred_raw;
    reg  [P-1:0] pass1_pred_pipe;

    reg  [P*AMP_W-1:0] pass1_amp_pipe;
    reg  [P-1:0]       pass1_mask_pipe;
    reg  [ROW_W-1:0]   pass1_row_pipe;
    reg  [COUNT_W-1:0] pass1_count_pipe;
    reg                 pass1_pred_valid;

    wire [ROW_W:0] pass1_full_rows =
        pass1_count_pipe[COUNT_W-1:LOGP];
    wire [LOGP-1:0] pass1_tail =
        pass1_count_pipe[LOGP-1:0];
    wire [ROW_W:0] pass1_row_ext = {1'b0, pass1_row_pipe};

    wire pass1_row_before_full = (pass1_row_ext < pass1_full_rows);
    wire pass1_row_is_tail     = (pass1_row_ext == pass1_full_rows);

    wire [P-1:0] pass1_padding_mask;
    wire enum_active = (enum_enable === 1'b1);
    wire [P-1:0] pass1_not_found_mask =
        enum_active ? ~pass1_mask_pipe : {P{1'b1}};
    wire [P-1:0] pass1_lane_hit =
        pass1_pred_pipe & pass1_padding_mask & pass1_not_found_mask;

    wire [P*AMP_W-1:0] oracle_row;
    wire [P*AMP_W-1:0] diffusion_row;
    wire [P-1:0]       lane_sat;

    //==========================================================================
    // v0.7g PASS2 saturation-status timing retime
    //
    // Routed v0.7f timing left one failing setup path ending at sat_event:
    //   amp_mem BRAM -> diffusion saturation detect -> 32-lane OR -> sat_event
    //
    // The amplitude datapath itself remains unchanged. Only the diagnostic
    // saturation sideband is retimed by one clock:
    //   diffusion lane_sat[31:0] -> lane_sat_pipe REG -> OR -> sat_event REG
    //
    // This removes the cross-lane OR reduction from the BRAM/diffusion clock
    // path. sat_event is therefore exactly one clock later than the PASS2 row
    // that generated it. amp_overflow is sticky at top level, and measurement
    // follows PASS2, so this latency-only status change does not alter Grover
    // arithmetic, memory writeback, controller sequencing, or search result.
    //==========================================================================
    reg [P-1:0] lane_sat_pipe;
    reg         sat_pipe_valid;

    genvar b;
    generate
        for (b = 0; b < P; b = b + 1) begin : g_lane
            wire signed [DATA_W-1:0] data_lane;
            wire signed [AMP_W-1:0]  amp_lane;
            wire signed [AMP_W-1:0]  pass1_amp_lane;
            wire signed [AMP_W-1:0]  oracle_lane;
            wire signed [AMP_W-1:0]  diff_lane;
            wire                     lane_tail_valid;

            localparam [LOGP-1:0] LANE_INDEX = b;

            assign data_lane      = $signed(data_row_in[b*DATA_W +: DATA_W]);
            assign amp_lane       = $signed(amp_row_in[b*AMP_W +: AMP_W]);
            assign pass1_amp_lane = $signed(pass1_amp_pipe[b*AMP_W +: AMP_W]);

            // Predicate arithmetic only.  Padding is shared once per row below.
            grover_predicate #(
                .USE_PADDING (0)
            ) u_predicate (
                .mode        (predicate_mode),
                .value       (data_lane),
                .threshold_a (threshold_a),
                .threshold_b (threshold_b),
                .index       ({`GP_INDEX_W{1'b0}}),
                .data_count  ({`GP_DATA_COUNT_W{1'b0}}),
                .hit         (pass1_pred_raw[b])
            );

            // Small tail comparison only (5 bits for P=32), replacing the old
            // 15-bit basis-index/data_count comparison replicated per lane.
            assign lane_tail_valid = (LANE_INDEX < pass1_tail);
            assign pass1_padding_mask[b] =
                pass1_row_before_full |
                (pass1_row_is_tail & lane_tail_valid);

            grover_oracle_flip u_oracle (
                .amp_in  (pass1_amp_lane),
                .hit     (pass1_lane_hit[b]),
                .amp_out (oracle_lane)
            );

            // PASS2 consumes the Oracle amplitude already stored by PASS1.
            grover_diffusion_sat u_diffusion (
                .two_mean  (two_mean),
                .oracle_amp(amp_lane),
                .amp_out   (diff_lane),
                .sat       (lane_sat[b])
            );

            assign oracle_row[b*AMP_W +: AMP_W]    = oracle_lane;
            assign diffusion_row[b*AMP_W +: AMP_W] = diff_lane;
        end
    endgenerate

    //==========================================================================
    // Existing v0.7 Candidate-B PASS1 sum pipeline
    //==========================================================================
    reg  pass1_sum_valid;
    wire row_partial_valid;

    grover_adder_tree u_adder_tree (
        .clk       (clk),
        .rstn      (rstn),
        .en        (pass1_sum_valid),
        .din       (amp_row_out),
        .partial   (row_partial_sum),
        .valid_out (row_partial_valid)
    );

    grover_sum_accum u_sum_accum (
        .clk     (clk),
        .rstn    (rstn),
        .clear   (acc_clear),
        .en      (row_partial_valid),
        .partial (row_partial_sum),
        .total   (global_sum)
    );

    wire signed [`GP_TWO_MEAN_W-1:0] two_mean_comb;
    grover_two_mean_calc u_two_mean_calc (
        .total    (global_sum),
        .two_mean (two_mean_comb)
    );

    integer k;
    always @(posedge clk) begin
        if (!rstn) begin
            pass1_pred_pipe  <= {P{1'b0}};
            pass1_amp_pipe   <= {(P*AMP_W){1'b0}};
            pass1_mask_pipe  <= {P{1'b0}};
            pass1_row_pipe   <= {ROW_W{1'b0}};
            pass1_count_pipe <= {COUNT_W{1'b0}};
            pass1_pred_valid <= 1'b0;

            amp_row_out      <= {(P*AMP_W){1'b0}};
            row_out_valid    <= 1'b0;
            row_out_index    <= {ROW_W{1'b0}};
            two_mean         <= {`GP_TWO_MEAN_W{1'b0}};
            sat_event        <= 1'b0;
            lane_sat_pipe    <= {P{1'b0}};
            sat_pipe_valid   <= 1'b0;
            pass1_sum_valid  <= 1'b0;
        end else begin
            row_out_valid <= 1'b0;

            // v0.7g status-sideband pipeline. Nonblocking assignment means
            // sat_event observes the PREVIOUS cycle's lane_sat_pipe/valid,
            // giving exactly +1 clock latency versus the corresponding PASS2
            // amplitude row. A bubble naturally emits sat_event=0.
            sat_event      <= sat_pipe_valid ? |lane_sat_pipe : 1'b0;
            sat_pipe_valid <= row_valid && (op == OP_PASS2);
            if (row_valid && (op == OP_PASS2))
                lane_sat_pipe <= lane_sat;

            // Stage A transaction register.
            pass1_pred_valid <= row_valid && (op == OP_PASS1);
            if (row_valid && (op == OP_PASS1)) begin
                pass1_pred_pipe  <= pass1_pred_raw;
                pass1_amp_pipe   <= amp_row_in;
                pass1_mask_pipe  <= found_mask_row_in;
                pass1_row_pipe   <= row_index;
                pass1_count_pipe <= data_count;
            end

            // amp_row_out is created from the previous Stage-A PASS1
            // transaction.  Tag the same registered Oracle row for the existing
            // Candidate-B adder tree on the following clock.
            pass1_sum_valid <= pass1_pred_valid;

            // MEAN is intentionally a register boundary.
            if (op == OP_MEAN)
                two_mean <= two_mean_comb;

            // PASS1 now has priority only when a valid Stage-A transaction is
            // present.  INIT/PASS2 retain their original latency.
            if (pass1_pred_valid) begin
                amp_row_out   <= oracle_row;
                row_out_index <= pass1_row_pipe;
                row_out_valid <= 1'b1;
            end else if (row_valid && (op == OP_INIT)) begin
                for (k = 0; k < P; k = k + 1)
                    amp_row_out[k*AMP_W +: AMP_W] <= `GP_INIT_AMP_RAW;
                row_out_index <= row_index;
                row_out_valid <= 1'b1;
            end else if (row_valid && (op == OP_PASS2)) begin
                amp_row_out   <= diffusion_row;
                row_out_index <= row_index;
                row_out_valid <= 1'b1;
                // lane_sat is captured by lane_sat_pipe above. sat_event is
                // intentionally emitted one clock later.
            end
        end
    end

endmodule

//------------------------------------------------------------------------------
// END preserved module source: grover_iter_datapath.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_ctrl_fsm.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_ctrl_fsm.v -- BBHT/Grover Main IP v0.7f timing-aligned controller
//
// Inner Grover controller only.
//   S_IDLE -> S_INIT(optional) ->
//   (S_PASS1 -> S_P1DRN -> S_MEAN -> S_PASS2) x iter_count -> S_IDLE
//
// Fixed baseline: Q14 / P32 -> 512 rows.
//
// Phase-specific memory/writeback contract after v0.7f:
//   INIT:
//     edge t   issue row
//     edge t+1 datapath creates uniform row
//     edge t+2 amp_mem write
//
//   PASS1:
//     edge t   request amp_mem/data_mem row
//     edge t+1 BRAM response -> predicate result/amp/tag/count REG
//     edge t+2 shared padding + Oracle -> amp_row_out REG
//     edge t+3 amp_mem write + Candidate-B adder stages 1..3 REG
//     edge t+4 adder stages 4..5 -> global accumulator
//
//   PASS2:
//     edge t   request amp_mem row
//     edge t+1 diffusion -> amp_row_out REG
//     edge t+2 amp_mem write
//
// S_P1DRN remains exactly one cycle: the final PASS1 amp_mem write occurs at
// t+3 and the final registered tree partial is accumulated at t+4 while the
// controller is in S_P1DRN.  No additional drain state is needed.
//
// INIT uses the same two-stage row-valid/write-address pipeline, but does not
// read either BRAM.  The Step-4 datapath supplies GP_INIT_AMP_RAW for OP_INIT.
//
// This block deliberately contains no BBHT, cache, measurement, loader, or
// status policy.  Those are later integration steps in the v0.6 plan.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_ctrl_fsm (
    input  wire                         clk,
    input  wire                         rstn,

    // Upper-level request. iter_start is accepted only while idle.
    input  wire                         iter_start,
    input  wire                         iter_do_init,
    input  wire [15:0]                  iter_count,

    output wire                         iter_busy,
    output reg                          iter_done,
    output wire [3:0]                   state,

    // Synchronous BRAM read request side.
    output wire [`GP_ROW_W-1:0]         amp_rd_row,
    output wire                         amp_rd_en,
    output wire [`GP_ROW_W-1:0]         data_rd_row,
    output wire                         data_rd_en,

    // Step-4 datapath input alignment, valid one cycle after row issue.
    output wire [1:0]                   dp_op,
    output wire                         dp_row_valid,
    output wire [`GP_ROW_W-1:0]         dp_row_index,
    output wire                         acc_clear,

    // amp_mem write slot aligned to Step-4 registered row output.
    // Connect amp_wr_data to grover_iter_datapath.amp_row_out.
    output wire                         amp_wr_en,
    output wire [`GP_ROW_W-1:0]         amp_wr_row,

    // Debug / later counter hook: one pulse at completion of PASS1 or PASS2.
    output reg                          pass_tick
);
    // State encoding kept compatible with the GitHub reference controller.
    localparam [3:0] S_IDLE  = 4'd0;
    localparam [3:0] S_INIT  = 4'd1;
    localparam [3:0] S_PASS1 = 4'd2;
    localparam [3:0] S_MEAN  = 4'd3;
    localparam [3:0] S_PASS2 = 4'd4;
    localparam [3:0] S_P1DRN = 4'd5; // v0.7 Candidate-B PASS1 sum drain

    // Step-4 datapath operation encoding.
    localparam [1:0] OP_INIT  = 2'd0;
    localparam [1:0] OP_PASS1 = 2'd1;
    localparam [1:0] OP_MEAN  = 2'd2;
    localparam [1:0] OP_PASS2 = 2'd3;

    localparam integer ROWS = `GP_ROWS;

    reg [3:0] st;
    reg [`GP_ROW_W:0] issue_count; // 0..ROWS, one guard bit for 512
    reg [15:0] iterations_left;

    // Row request metadata pipeline.
    reg                         issue_v_d1;
    reg                         issue_v_d2;
    reg                         issue_v_d3;
    reg [`GP_ROW_W-1:0]         issue_row_d1;
    reg [`GP_ROW_W-1:0]         issue_row_d2;
    reg [`GP_ROW_W-1:0]         issue_row_d3;
    reg [1:0]                   issue_op_d1;
    reg [1:0]                   issue_op_d2;
    reg [1:0]                   issue_op_d3;

    wire state_issues_rows;
    wire issue_valid;
    wire [`GP_ROW_W-1:0] issue_row;
    wire [1:0] issue_op;

    assign state_issues_rows = (st == S_INIT) || (st == S_PASS1) ||
                               (st == S_PASS2);
    assign issue_valid = state_issues_rows && (issue_count < ROWS);
    assign issue_row   = issue_count[`GP_ROW_W-1:0];

    assign issue_op = (st == S_INIT ) ? OP_INIT  :
                      (st == S_PASS1) ? OP_PASS1 :
                      (st == S_PASS2) ? OP_PASS2 : OP_MEAN;

    // Phase-specific final write slots.
    wire final_write_slot_init;
    wire final_write_slot_pass1;
    wire final_write_slot_pass2;

    assign final_write_slot_init =
        (issue_count == ROWS) && !issue_v_d1 && issue_v_d2 &&
        (issue_op_d2 == OP_INIT);

    // PASS1 writeback is one cycle later in v0.7f because predicate output is
    // registered before shared padding + Oracle.
    assign final_write_slot_pass1 =
        (issue_count == ROWS) && !issue_v_d1 && !issue_v_d2 && issue_v_d3 &&
        (issue_op_d3 == OP_PASS1);

    assign final_write_slot_pass2 =
        (issue_count == ROWS) && !issue_v_d1 && issue_v_d2 &&
        (issue_op_d2 == OP_PASS2);

    // BRAM reads are needed only by actual Grover passes.
    assign amp_rd_row  = issue_row;
    assign data_rd_row = issue_row;
    assign amp_rd_en   = issue_valid && ((st == S_PASS1) || (st == S_PASS2));
    assign data_rd_en  = issue_valid &&  (st == S_PASS1);

    // t+1 metadata aligned to the synchronous BRAM response.
    assign dp_row_valid = issue_v_d1;
    assign dp_row_index = issue_row_d1;

    // MEAN is a state-level one-cycle operation with no row_valid.  Otherwise
    // the delayed row operation is presented to the Step-4 datapath.
    assign dp_op = (st == S_MEAN) ? OP_MEAN : issue_op_d1;

    // Clear the global PASS1 accumulator one full cycle before row 0 is
    // consumed by the datapath.  clear therefore cannot suppress row-0 add.
    assign acc_clear = (st == S_PASS1) && issue_valid &&
                       (issue_count == {(`GP_ROW_W+1){1'b0}});

    // INIT/PASS2 write at t+2. PASS1 writes at t+3.
    // Operation tags travel with metadata so a residual d3 transaction from a
    // previous PASS2 can never be mistaken for a PASS1 write after a state
    // transition.
    wire write_v_d2 = issue_v_d2 && (issue_op_d2 != OP_PASS1);
    wire write_v_d3 = issue_v_d3 && (issue_op_d3 == OP_PASS1);

    assign amp_wr_en  = write_v_d2 | write_v_d3;
    assign amp_wr_row = write_v_d3 ? issue_row_d3 : issue_row_d2;

    assign iter_busy = (st != S_IDLE);
    assign state     = st;

    always @(posedge clk) begin
        if (!rstn) begin
            st              <= S_IDLE;
            issue_count     <= {(`GP_ROW_W+1){1'b0}};
            iterations_left <= 16'd0;
            issue_v_d1      <= 1'b0;
            issue_v_d2      <= 1'b0;
            issue_v_d3      <= 1'b0;
            issue_row_d1    <= {`GP_ROW_W{1'b0}};
            issue_row_d2    <= {`GP_ROW_W{1'b0}};
            issue_row_d3    <= {`GP_ROW_W{1'b0}};
            issue_op_d1     <= OP_INIT;
            issue_op_d2     <= OP_INIT;
            issue_op_d3     <= OP_INIT;
            iter_done       <= 1'b0;
            pass_tick       <= 1'b0;
        end else begin
            iter_done <= 1'b0;
            pass_tick <= 1'b0;

            // Pipeline always advances. In non-issuing states issue_valid=0,
            // so it naturally drains without a separate drain state.
            issue_v_d1   <= issue_valid;
            issue_v_d2   <= issue_v_d1;
            issue_v_d3   <= issue_v_d2;
            issue_row_d1 <= issue_row;
            issue_row_d2 <= issue_row_d1;
            issue_row_d3 <= issue_row_d2;
            issue_op_d1  <= issue_op;
            issue_op_d2  <= issue_op_d1;
            issue_op_d3  <= issue_op_d2;

            case (st)
                S_IDLE: begin
                    issue_count <= {(`GP_ROW_W+1){1'b0}};

                    if (iter_start) begin
                        iterations_left <= iter_count;

                        if (iter_do_init) begin
                            st <= S_INIT;
                        end else if (iter_count != 16'd0) begin
                            st <= S_PASS1;
                        end else begin
                            // Legitimate zero-delta request: no state update.
                            iter_done <= 1'b1;
                        end
                    end
                end

                S_INIT: begin
                    if (issue_valid)
                        issue_count <= issue_count + 1'b1;

                    if (final_write_slot_init) begin
                        issue_count <= {(`GP_ROW_W+1){1'b0}};
                        if (iterations_left != 16'd0) begin
                            st <= S_PASS1;
                        end else begin
                            st        <= S_IDLE;
                            iter_done <= 1'b1;
                        end
                    end
                end

                S_PASS1: begin
                    if (issue_valid)
                        issue_count <= issue_count + 1'b1;

                    if (final_write_slot_pass1) begin
                        issue_count <= {(`GP_ROW_W+1){1'b0}};

                        // v0.7f PASS1 final t+3 write slot:
                        // Raise pass_tick while the controller is IN S_P1DRN,
                        // not after leaving it.  The pulse is registered on the
                        // S_PASS1->S_P1DRN transition and therefore remains high
                        // throughout the one-cycle drain state.  A synchronous
                        // observer samples pass_tick=1 on the drain edge, which
                        // is the same edge that consumes the final registered
                        // adder-tree partial into global_sum.
                        //
                        // This changes only debug/counter pulse alignment; the
                        // Grover datapath arithmetic and state sequencing are
                        // unchanged.
                        pass_tick   <= 1'b1;
                        st          <= S_P1DRN;
                    end
                end

                // One-cycle PASS1 timing drain.  pass_tick is already high
                // during this state because it was registered on entry from
                // S_PASS1.  On the drain edge the final row_partial_valid /
                // row_partial_sum pair is consumed by the global accumulator;
                // the default pass_tick<=0 above then clears the pulse as the
                // controller advances to S_MEAN.
                S_P1DRN: begin
                    issue_count <= {(`GP_ROW_W+1){1'b0}};
                    st          <= S_MEAN;
                end

                S_MEAN: begin
                    // Step-4 latches round-even two_mean on this cycle.
                    issue_count <= {(`GP_ROW_W+1){1'b0}};
                    st          <= S_PASS2;
                end

                S_PASS2: begin
                    if (issue_valid)
                        issue_count <= issue_count + 1'b1;

                    if (final_write_slot_pass2) begin
                        issue_count <= {(`GP_ROW_W+1){1'b0}};
                        pass_tick   <= 1'b1;

                        if (iterations_left == 16'd1) begin
                            iterations_left <= 16'd0;
                            st              <= S_IDLE;
                            iter_done       <= 1'b1;
                        end else begin
                            iterations_left <= iterations_left - 1'b1;
                            st              <= S_PASS1;
                        end
                    end
                end

                default: begin
                    st          <= S_IDLE;
                    issue_count <= {(`GP_ROW_W+1){1'b0}};
                end
            endcase
        end
    end

endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_ctrl_fsm.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN Phase-3A checkpoint integration modules
//------------------------------------------------------------------------------
//==============================================================================
// grover_ckpt_oracle_align
//
// grover_ckpt_mem adds one explicit registered source-select stage beyond the
// baseline one-cycle amp BRAM. data_mem and found_mask_mem remain one-cycle
// memories. This adapter delays their PASS1 row response by exactly one cycle so
// that amp/data/mask are sampled by grover_iter_datapath on the same transaction.
//
// req_en is the original synchronous data/found-mask read request. req_en_d
// identifies the raw one-cycle memory response that is safe to capture here.
// aligned_valid is intended to match grover_ctrl_fsm_ckpt.dp_row_valid for
// PASS1 rows and is exported for TB/assertion observability.
//==============================================================================
module grover_ckpt_oracle_align (
    input  wire                                      clk,
    input  wire                                      rstn,
    input  wire                                      req_en,
    input  wire [`GP_P*`GP_DATA_W-1:0]              data_row_raw,
    input  wire [`GP_P-1:0]                         found_mask_row_raw,
    output reg  [`GP_P*`GP_DATA_W-1:0]              data_row_aligned,
    output reg  [`GP_P-1:0]                         found_mask_row_aligned,
    output reg                                       aligned_valid
);
    reg req_en_d;

    always @(posedge clk) begin
        if (!rstn) begin
            req_en_d               <= 1'b0;
            aligned_valid          <= 1'b0;
            data_row_aligned       <= {(`GP_P*`GP_DATA_W){1'b0}};
            found_mask_row_aligned <= {`GP_P{1'b0}};
        end else begin
            req_en_d      <= req_en;
            aligned_valid <= req_en_d;

            // At this edge, one-cycle synchronous data/mask memories expose
            // the row requested on the previous edge. Capture that response
            // into the extra alignment register used by checkpoint mode.
            if (req_en_d) begin
                data_row_aligned       <= data_row_raw;
                found_mask_row_aligned <= found_mask_row_raw;
            end
        end
    end
endmodule

//==============================================================================
// grover_ctrl_fsm_ckpt -- Phase-3A checkpoint-memory timing variant
//
// IMPORTANT:
//   * The verified legacy grover_ctrl_fsm above is intentionally untouched.
//   * This controller exists only for grover_ckpt_mem, whose amplitude read path
//     is one clock deeper than grover_amp_mem (BRAM + registered source mux).
//   * GP_PIPE_LAT remains unchanged. The extra latency is a memory-interface
//     alignment issue, not a change to the arithmetic pipeline contract.
//
// Phase timing relative to a row request edge t:
//   INIT (no amp/data read):
//     t+1 datapath INIT transaction, t+2 checkpoint write
//   PASS1:
//     t+1 packed BRAM/data response
//     t+2 checkpoint source-mux response + aligned data/mask transaction
//     t+3 Oracle row register
//     t+4 checkpoint write + adder-tree cut register
//     t+5 final row accumulates during S_P1DRN
//   PASS2:
//     t+1 packed BRAM response
//     t+2 checkpoint source-mux response -> diffusion row register
//     t+3 checkpoint write
//
// The one-cycle S_P1DRN remains sufficient because PASS1 write and adder-tree
// cut still occur on the same edge; only both are shifted one clock later.
//==============================================================================
module grover_ctrl_fsm_ckpt (
    input  wire                         clk,
    input  wire                         rstn,

    input  wire                         iter_start,
    input  wire                         iter_do_init,
    input  wire [15:0]                  iter_count,

    output wire                         iter_busy,
    output reg                          iter_done,
    output wire [3:0]                   state,

    output wire [`GP_ROW_W-1:0]         amp_rd_row,
    output wire                         amp_rd_en,
    output wire [`GP_ROW_W-1:0]         data_rd_row,
    output wire                         data_rd_en,

    output wire [1:0]                   dp_op,
    output wire                         dp_row_valid,
    output wire [`GP_ROW_W-1:0]         dp_row_index,
    output wire                         acc_clear,

    output wire                         amp_wr_en,
    output wire [`GP_ROW_W-1:0]         amp_wr_row,

    output reg                          pass_tick
);
    localparam [3:0] S_IDLE  = 4'd0;
    localparam [3:0] S_INIT  = 4'd1;
    localparam [3:0] S_PASS1 = 4'd2;
    localparam [3:0] S_MEAN  = 4'd3;
    localparam [3:0] S_PASS2 = 4'd4;
    localparam [3:0] S_P1DRN = 4'd5;

    localparam [1:0] OP_INIT  = 2'd0;
    localparam [1:0] OP_PASS1 = 2'd1;
    localparam [1:0] OP_MEAN  = 2'd2;
    localparam [1:0] OP_PASS2 = 2'd3;

    localparam integer ROWS = `GP_ROWS;

    reg [3:0] st;
    reg [`GP_ROW_W:0] issue_count;
    reg [15:0] iterations_left;

    // Four metadata stages are required because checkpoint PASS1 writeback is
    // t+4 from issue. INIT still consumes only d1/d2; PASS2 consumes d2/d3.
    reg                         issue_v_d1;
    reg                         issue_v_d2;
    reg                         issue_v_d3;
    reg                         issue_v_d4;
    reg [`GP_ROW_W-1:0]         issue_row_d1;
    reg [`GP_ROW_W-1:0]         issue_row_d2;
    reg [`GP_ROW_W-1:0]         issue_row_d3;
    reg [`GP_ROW_W-1:0]         issue_row_d4;
    reg [1:0]                   issue_op_d1;
    reg [1:0]                   issue_op_d2;
    reg [1:0]                   issue_op_d3;
    reg [1:0]                   issue_op_d4;

    wire state_issues_rows;
    wire issue_valid;
    wire [`GP_ROW_W-1:0] issue_row;
    wire [1:0] issue_op;

    assign state_issues_rows = (st == S_INIT) || (st == S_PASS1) ||
                               (st == S_PASS2);
    assign issue_valid = state_issues_rows && (issue_count < ROWS);
    assign issue_row   = issue_count[`GP_ROW_W-1:0];

    assign issue_op = (st == S_INIT ) ? OP_INIT  :
                      (st == S_PASS1) ? OP_PASS1 :
                      (st == S_PASS2) ? OP_PASS2 : OP_MEAN;

    // Completion is tied to the actual checkpoint write slot, not merely to the
    // final read request. This prevents state transitions from outrunning the
    // deeper checkpoint read path.
    wire final_write_slot_init =
        (issue_count == ROWS) && !issue_v_d1 && issue_v_d2 &&
        (issue_op_d2 == OP_INIT);

    wire final_write_slot_pass1 =
        (issue_count == ROWS) && !issue_v_d1 && !issue_v_d2 &&
        !issue_v_d3 && issue_v_d4 && (issue_op_d4 == OP_PASS1);

    wire final_write_slot_pass2 =
        (issue_count == ROWS) && !issue_v_d1 && !issue_v_d2 &&
        issue_v_d3 && (issue_op_d3 == OP_PASS2);

    assign amp_rd_row  = issue_row;
    assign data_rd_row = issue_row;
    assign amp_rd_en   = issue_valid && ((st == S_PASS1) || (st == S_PASS2));
    assign data_rd_en  = issue_valid &&  (st == S_PASS1);

    // INIT does not read amp_mem and therefore keeps legacy d1 alignment.
    // PASS1/PASS2 consume the two-cycle checkpoint response and use d2.
    wire dp_init_valid = issue_v_d1 && (issue_op_d1 == OP_INIT);
    wire dp_pass_valid = issue_v_d2 &&
                         ((issue_op_d2 == OP_PASS1) ||
                          (issue_op_d2 == OP_PASS2));

    assign dp_row_valid = dp_init_valid | dp_pass_valid;
    assign dp_row_index = dp_init_valid ? issue_row_d1 : issue_row_d2;
    assign dp_op = (st == S_MEAN) ? OP_MEAN :
                   dp_init_valid   ? OP_INIT : issue_op_d2;

    // Earlier-than-necessary clear is intentional and safe. It occurs on the
    // row-0 request edge, before any delayed PASS1 partial can reach the accum.
    assign acc_clear = (st == S_PASS1) && issue_valid &&
                       (issue_count == {(`GP_ROW_W+1){1'b0}});

    // INIT: t+2, PASS2: t+3, PASS1: t+4.
    wire write_v_d2 = issue_v_d2 && (issue_op_d2 == OP_INIT);
    wire write_v_d3 = issue_v_d3 && (issue_op_d3 == OP_PASS2);
    wire write_v_d4 = issue_v_d4 && (issue_op_d4 == OP_PASS1);

    assign amp_wr_en  = write_v_d2 | write_v_d3 | write_v_d4;
    assign amp_wr_row = write_v_d4 ? issue_row_d4 :
                        write_v_d3 ? issue_row_d3 : issue_row_d2;

    assign iter_busy = (st != S_IDLE);
    assign state     = st;

    always @(posedge clk) begin
        if (!rstn) begin
            st              <= S_IDLE;
            issue_count     <= {(`GP_ROW_W+1){1'b0}};
            iterations_left <= 16'd0;
            issue_v_d1      <= 1'b0;
            issue_v_d2      <= 1'b0;
            issue_v_d3      <= 1'b0;
            issue_v_d4      <= 1'b0;
            issue_row_d1    <= {`GP_ROW_W{1'b0}};
            issue_row_d2    <= {`GP_ROW_W{1'b0}};
            issue_row_d3    <= {`GP_ROW_W{1'b0}};
            issue_row_d4    <= {`GP_ROW_W{1'b0}};
            issue_op_d1     <= OP_INIT;
            issue_op_d2     <= OP_INIT;
            issue_op_d3     <= OP_INIT;
            issue_op_d4     <= OP_INIT;
            iter_done       <= 1'b0;
            pass_tick       <= 1'b0;
        end else begin
            iter_done <= 1'b0;
            pass_tick <= 1'b0;

            issue_v_d1   <= issue_valid;
            issue_v_d2   <= issue_v_d1;
            issue_v_d3   <= issue_v_d2;
            issue_v_d4   <= issue_v_d3;
            issue_row_d1 <= issue_row;
            issue_row_d2 <= issue_row_d1;
            issue_row_d3 <= issue_row_d2;
            issue_row_d4 <= issue_row_d3;
            issue_op_d1  <= issue_op;
            issue_op_d2  <= issue_op_d1;
            issue_op_d3  <= issue_op_d2;
            issue_op_d4  <= issue_op_d3;

            case (st)
                S_IDLE: begin
                    issue_count <= {(`GP_ROW_W+1){1'b0}};
                    if (iter_start) begin
                        iterations_left <= iter_count;
                        if (iter_do_init)
                            st <= S_INIT;
                        else if (iter_count != 16'd0)
                            st <= S_PASS1;
                        else
                            iter_done <= 1'b1;
                    end
                end

                S_INIT: begin
                    if (issue_valid)
                        issue_count <= issue_count + 1'b1;

                    if (final_write_slot_init) begin
                        issue_count <= {(`GP_ROW_W+1){1'b0}};
                        if (iterations_left != 16'd0)
                            st <= S_PASS1;
                        else begin
                            st        <= S_IDLE;
                            iter_done <= 1'b1;
                        end
                    end
                end

                S_PASS1: begin
                    if (issue_valid)
                        issue_count <= issue_count + 1'b1;

                    if (final_write_slot_pass1) begin
                        issue_count <= {(`GP_ROW_W+1){1'b0}};
                        pass_tick   <= 1'b1;
                        st          <= S_P1DRN;
                    end
                end

                S_P1DRN: begin
                    issue_count <= {(`GP_ROW_W+1){1'b0}};
                    st          <= S_MEAN;
                end

                S_MEAN: begin
                    issue_count <= {(`GP_ROW_W+1){1'b0}};
                    st          <= S_PASS2;
                end

                S_PASS2: begin
                    if (issue_valid)
                        issue_count <= issue_count + 1'b1;

                    if (final_write_slot_pass2) begin
                        issue_count <= {(`GP_ROW_W+1){1'b0}};
                        pass_tick   <= 1'b1;

                        if (iterations_left == 16'd1) begin
                            iterations_left <= 16'd0;
                            st              <= S_IDLE;
                            iter_done       <= 1'b1;
                        end else begin
                            iterations_left <= iterations_left - 1'b1;
                            st              <= S_PASS1;
                        end
                    end
                end

                default: begin
                    st          <= S_IDLE;
                    issue_count <= {(`GP_ROW_W+1){1'b0}};
                end
            endcase
        end
    end
endmodule
//------------------------------------------------------------------------------
// END Phase-3A checkpoint integration modules
//------------------------------------------------------------------------------

//==============================================================================
// E2 intra-iteration datapath/controller extensions (2026-09-06)
//==============================================================================
module grover_iter_datapath_e2 (
    input  wire                                      clk,
    input  wire                                      rstn,

    input  wire [1:0]                                op,
    input  wire                                      pair_valid,
    input  wire [7:0]                                pair_index,
    input  wire                                      acc_clear,

    input  wire [`GP_P*`GP_AMP_W-1:0]                amp_even_in,
    input  wire [`GP_P*`GP_AMP_W-1:0]                amp_odd_in,
    input  wire [`GP_P*`GP_DATA_W-1:0]               data_even_in,
    input  wire [`GP_P*`GP_DATA_W-1:0]               data_odd_in,
    input  wire [`GP_P-1:0]                          mask_even_in,
    input  wire [`GP_P-1:0]                          mask_odd_in,

    input  wire [1:0]                                predicate_mode,
    input  wire signed [`GP_DATA_W-1:0]              threshold_a,
    input  wire signed [`GP_DATA_W-1:0]              threshold_b,
    input  wire [`GP_DATA_COUNT_W-1:0]               data_count,
    input  wire                                      enum_enable,

    output reg  [`GP_P*`GP_AMP_W-1:0]                amp_even_out,
    output reg  [`GP_P*`GP_AMP_W-1:0]                amp_odd_out,
    output reg                                       pair_out_valid,
    output reg  [7:0]                                pair_out_index,

    output wire signed [`GP_ACC_W-1:0]                global_sum,
    output reg  signed [`GP_TWO_MEAN_W-1:0]           two_mean,
    output wire                                      sum_commit,
    output reg                                       sat_event
);
    localparam [1:0] OP_INIT  = 2'd0;
    localparam [1:0] OP_PASS1 = 2'd1;
    localparam [1:0] OP_MEAN  = 2'd2;
    localparam [1:0] OP_PASS2 = 2'd3;

    localparam integer P       = `GP_P;
    localparam integer AMP_W   = `GP_AMP_W;
    localparam integer DATA_W  = `GP_DATA_W;
    localparam integer LOGP    = `GP_LOGP;
    localparam integer ROW_W   = `GP_ROW_W;
    localparam integer COUNT_W = `GP_DATA_COUNT_W;

    // Stage-A PASS1 registers for both logical rows.
    wire [P-1:0] pred_even_raw;
    wire [P-1:0] pred_odd_raw;

    reg  [P-1:0] pred_even_pipe;
    reg  [P-1:0] pred_odd_pipe;
    reg  [P*AMP_W-1:0] amp_even_pipe;
    reg  [P*AMP_W-1:0] amp_odd_pipe;
    reg  [P-1:0] mask_even_pipe;
    reg  [P-1:0] mask_odd_pipe;
    reg  [ROW_W-1:0] row_even_pipe;
    reg  [ROW_W-1:0] row_odd_pipe;
    reg  [COUNT_W-1:0] count_pipe;
    reg  [7:0] pair_index_pipe;
    reg  pass1_valid_pipe;

    wire [ROW_W-1:0] row_even_now = {pair_index, 1'b0};
    wire [ROW_W-1:0] row_odd_now  = {pair_index, 1'b1};

    wire [ROW_W:0] full_rows = count_pipe[COUNT_W-1:LOGP];
    wire [LOGP-1:0] tail = count_pipe[LOGP-1:0];

    wire [ROW_W:0] row_even_ext = {1'b0, row_even_pipe};
    wire [ROW_W:0] row_odd_ext  = {1'b0, row_odd_pipe};

    wire row_even_before_full = (row_even_ext < full_rows);
    wire row_odd_before_full  = (row_odd_ext  < full_rows);
    wire row_even_is_tail = (row_even_ext == full_rows);
    wire row_odd_is_tail  = (row_odd_ext  == full_rows);

    wire [P-1:0] pad_even;
    wire [P-1:0] pad_odd;
    wire enum_active = (enum_enable === 1'b1);
    wire [P-1:0] not_found_even = enum_active ? ~mask_even_pipe : {P{1'b1}};
    wire [P-1:0] not_found_odd  = enum_active ? ~mask_odd_pipe  : {P{1'b1}};
    wire [P-1:0] hit_even = pred_even_pipe & pad_even & not_found_even;
    wire [P-1:0] hit_odd  = pred_odd_pipe  & pad_odd  & not_found_odd;

    wire [P*AMP_W-1:0] oracle_even;
    wire [P*AMP_W-1:0] oracle_odd;
    wire [P*AMP_W-1:0] diff_even;
    wire [P*AMP_W-1:0] diff_odd;
    wire [P-1:0] sat_even;
    wire [P-1:0] sat_odd;

    genvar b;
    generate
        for (b = 0; b < P; b = b + 1) begin : g_e2_lane
            localparam [LOGP-1:0] LANE_INDEX = b;

            wire signed [DATA_W-1:0] data_even_lane =
                $signed(data_even_in[b*DATA_W +: DATA_W]);
            wire signed [DATA_W-1:0] data_odd_lane =
                $signed(data_odd_in[b*DATA_W +: DATA_W]);

            wire signed [AMP_W-1:0] amp_even_lane =
                $signed(amp_even_in[b*AMP_W +: AMP_W]);
            wire signed [AMP_W-1:0] amp_odd_lane =
                $signed(amp_odd_in[b*AMP_W +: AMP_W]);

            wire signed [AMP_W-1:0] pass_even_lane =
                $signed(amp_even_pipe[b*AMP_W +: AMP_W]);
            wire signed [AMP_W-1:0] pass_odd_lane =
                $signed(amp_odd_pipe[b*AMP_W +: AMP_W]);

            wire signed [AMP_W-1:0] oracle_even_lane;
            wire signed [AMP_W-1:0] oracle_odd_lane;
            wire signed [AMP_W-1:0] diff_even_lane;
            wire signed [AMP_W-1:0] diff_odd_lane;

            grover_predicate #(.USE_PADDING(0)) u_pred_even (
                .mode(predicate_mode), .value(data_even_lane),
                .threshold_a(threshold_a), .threshold_b(threshold_b),
                .index({`GP_INDEX_W{1'b0}}),
                .data_count({`GP_DATA_COUNT_W{1'b0}}),
                .hit(pred_even_raw[b])
            );

            grover_predicate #(.USE_PADDING(0)) u_pred_odd (
                .mode(predicate_mode), .value(data_odd_lane),
                .threshold_a(threshold_a), .threshold_b(threshold_b),
                .index({`GP_INDEX_W{1'b0}}),
                .data_count({`GP_DATA_COUNT_W{1'b0}}),
                .hit(pred_odd_raw[b])
            );

            assign pad_even[b] = row_even_before_full |
                                 (row_even_is_tail & (LANE_INDEX < tail));
            assign pad_odd[b]  = row_odd_before_full |
                                 (row_odd_is_tail & (LANE_INDEX < tail));

            grover_oracle_flip u_oracle_even (
                .amp_in(pass_even_lane), .hit(hit_even[b]),
                .amp_out(oracle_even_lane)
            );
            grover_oracle_flip u_oracle_odd (
                .amp_in(pass_odd_lane), .hit(hit_odd[b]),
                .amp_out(oracle_odd_lane)
            );

            grover_diffusion_sat u_diff_even (
                .two_mean(two_mean), .oracle_amp(amp_even_lane),
                .amp_out(diff_even_lane), .sat(sat_even[b])
            );
            grover_diffusion_sat u_diff_odd (
                .two_mean(two_mean), .oracle_amp(amp_odd_lane),
                .amp_out(diff_odd_lane), .sat(sat_odd[b])
            );

            assign oracle_even[b*AMP_W +: AMP_W] = oracle_even_lane;
            assign oracle_odd [b*AMP_W +: AMP_W] = oracle_odd_lane;
            assign diff_even  [b*AMP_W +: AMP_W] = diff_even_lane;
            assign diff_odd   [b*AMP_W +: AMP_W] = diff_odd_lane;
        end
    endgenerate

    // Two row-sum trees execute in parallel.
    wire signed [`GP_PARTIAL_SUM_W-1:0] partial_even;
    wire signed [`GP_PARTIAL_SUM_W-1:0] partial_odd;
    wire partial_even_valid;
    wire partial_odd_valid;

    grover_adder_tree u_sumtree_even (
        .clk(clk), .rstn(rstn), .en(pass1_valid_pipe),
        .din(oracle_even), .partial(partial_even),
        .valid_out(partial_even_valid)
    );
    grover_adder_tree u_sumtree_odd (
        .clk(clk), .rstn(rstn), .en(pass1_valid_pipe),
        .din(oracle_odd), .partial(partial_odd),
        .valid_out(partial_odd_valid)
    );

    wire partial_pair_valid = partial_even_valid & partial_odd_valid;

    // Separate half-state accumulators avoid a new 64-lane reduction critical
    // path. Integer addition is exact; they are combined only at MEAN.
    wire signed [`GP_ACC_W-1:0] total_even;
    wire signed [`GP_ACC_W-1:0] total_odd;

    grover_sum_accum u_acc_even (
        .clk(clk), .rstn(rstn), .clear(acc_clear),
        .en(partial_pair_valid), .partial(partial_even), .total(total_even)
    );
    grover_sum_accum u_acc_odd (
        .clk(clk), .rstn(rstn), .clear(acc_clear),
        .en(partial_pair_valid), .partial(partial_odd), .total(total_odd)
    );

    wire signed [`GP_ACC_W:0] total_pair_ext =
        {{1{total_even[`GP_ACC_W-1]}}, total_even} +
        {{1{total_odd [`GP_ACC_W-1]}}, total_odd};
    assign global_sum = total_pair_ext[`GP_ACC_W-1:0];
    assign sum_commit = partial_pair_valid;

    wire signed [`GP_TWO_MEAN_W-1:0] two_mean_comb;
    grover_two_mean_calc u_two_mean (
        .total(global_sum), .two_mean(two_mean_comb)
    );

    reg [P-1:0] sat_even_pipe;
    reg [P-1:0] sat_odd_pipe;
    reg sat_pipe_valid;

    integer k;
    always @(posedge clk) begin
        if (!rstn) begin
            pred_even_pipe <= {P{1'b0}};
            pred_odd_pipe  <= {P{1'b0}};
            amp_even_pipe  <= {(P*AMP_W){1'b0}};
            amp_odd_pipe   <= {(P*AMP_W){1'b0}};
            mask_even_pipe <= {P{1'b0}};
            mask_odd_pipe  <= {P{1'b0}};
            row_even_pipe  <= {ROW_W{1'b0}};
            row_odd_pipe   <= {ROW_W{1'b0}};
            count_pipe     <= {COUNT_W{1'b0}};
            pair_index_pipe<= 8'd0;
            pass1_valid_pipe <= 1'b0;

            amp_even_out   <= {(P*AMP_W){1'b0}};
            amp_odd_out    <= {(P*AMP_W){1'b0}};
            pair_out_valid <= 1'b0;
            pair_out_index <= 8'd0;
            two_mean       <= {`GP_TWO_MEAN_W{1'b0}};

            sat_even_pipe  <= {P{1'b0}};
            sat_odd_pipe   <= {P{1'b0}};
            sat_pipe_valid <= 1'b0;
            sat_event      <= 1'b0;
        end else begin
            pair_out_valid <= 1'b0;

            sat_event      <= sat_pipe_valid ? (|sat_even_pipe | |sat_odd_pipe) : 1'b0;
            sat_pipe_valid <= pair_valid && (op == OP_PASS2);
            if (pair_valid && (op == OP_PASS2)) begin
                sat_even_pipe <= sat_even;
                sat_odd_pipe  <= sat_odd;
            end

            // PASS1 predicate/amp transaction register.
            pass1_valid_pipe <= pair_valid && (op == OP_PASS1);
            if (pair_valid && (op == OP_PASS1)) begin
                pred_even_pipe  <= pred_even_raw;
                pred_odd_pipe   <= pred_odd_raw;
                amp_even_pipe   <= amp_even_in;
                amp_odd_pipe    <= amp_odd_in;
                mask_even_pipe  <= mask_even_in;
                mask_odd_pipe   <= mask_odd_in;
                row_even_pipe   <= row_even_now;
                row_odd_pipe    <= row_odd_now;
                count_pipe      <= data_count;
                pair_index_pipe <= pair_index;
            end

            if (op == OP_MEAN)
                two_mean <= two_mean_comb;

            // Stage-B PASS1 output.
            if (pass1_valid_pipe) begin
                amp_even_out   <= oracle_even;
                amp_odd_out    <= oracle_odd;
                pair_out_index <= pair_index_pipe;
                pair_out_valid <= 1'b1;
            end else if (pair_valid && (op == OP_INIT)) begin
                for (k = 0; k < P; k = k + 1) begin
                    amp_even_out[k*AMP_W +: AMP_W] <= `GP_INIT_AMP_RAW;
                    amp_odd_out [k*AMP_W +: AMP_W] <= `GP_INIT_AMP_RAW;
                end
                pair_out_index <= pair_index;
                pair_out_valid <= 1'b1;
            end else if (pair_valid && (op == OP_PASS2)) begin
                amp_even_out   <= diff_even;
                amp_odd_out    <= diff_odd;
                pair_out_index <= pair_index;
                pair_out_valid <= 1'b1;
            end
        end
    end
endmodule

//------------------------------------------------------------------------------
// Event-counted E2 controller.  256 pair requests cover all 512 logical rows.
// Dataset/mask rows are expected to return with the same 1-cycle latency as the
// active scratch pair read.
//------------------------------------------------------------------------------
module grover_e2_oracle_align_pair (
    input wire clk,input wire rstn,input wire req_en,
    input wire [`GP_P*`GP_DATA_W-1:0] data_even_raw,
    input wire [`GP_P*`GP_DATA_W-1:0] data_odd_raw,
    input wire [`GP_P-1:0] mask_even_raw,
    input wire [`GP_P-1:0] mask_odd_raw,
    output reg [`GP_P*`GP_DATA_W-1:0] data_even_aligned,
    output reg [`GP_P*`GP_DATA_W-1:0] data_odd_aligned,
    output reg [`GP_P-1:0] mask_even_aligned,
    output reg [`GP_P-1:0] mask_odd_aligned,
    output reg aligned_valid
);
    reg req_d;
    always @(posedge clk) begin
      if(!rstn) begin req_d<=0; aligned_valid<=0; data_even_aligned<=0; data_odd_aligned<=0; mask_even_aligned<=0; mask_odd_aligned<=0; end
      else begin
        req_d<=req_en; aligned_valid<=req_d;
        if(req_d) begin data_even_aligned<=data_even_raw; data_odd_aligned<=data_odd_raw; mask_even_aligned<=mask_even_raw; mask_odd_aligned<=mask_odd_raw; end
      end
    end
endmodule

//------------------------------------------------------------------------------
// E2 checkpoint-aware event-counted controller.
// PASS1 checkpoint read latency = 2 cycles; PASS2 scratch read latency = 1.
//------------------------------------------------------------------------------
module grover_ctrl_fsm_ckpt_e2 (
    input wire clk,input wire rstn,
    input wire iter_start,input wire iter_do_init,input wire [15:0] iter_count,
    input wire dp_pair_out_valid,input wire dp_sum_commit,
    output wire iter_busy,output reg iter_done,output wire [3:0] state,
    output wire [7:0] pair_index,output wire ckpt_pair_rd_en,
    output wire scratch_pair_rd_en,output wire data_pair_rd_en,
    output wire [1:0] dp_op,output wire dp_pair_valid,output wire [7:0] dp_pair_index,
    output wire acc_clear,output reg pass_tick
);
    localparam [3:0] S_IDLE=0,S_INIT=1,S_PASS1=2,S_MEAN=3,S_PASS2=4;
    localparam [1:0] OP_INIT=0,OP_PASS1=1,OP_MEAN=2,OP_PASS2=3;
    localparam integer PAIRS=256;
    reg [3:0] st;
    reg [8:0] issue_count,out_count,sum_count;
    reg [15:0] iterations_left;
    reg pass1_out_done,pass1_sum_done;
    reg issue_v_d1,issue_v_d2;
    reg [7:0] pair_d1,pair_d2;
    reg [1:0] op_d1,op_d2;

    wire state_issues=(st==S_INIT)||(st==S_PASS1)||(st==S_PASS2);
    wire issue_valid=state_issues&&(issue_count<PAIRS);
    wire [7:0] ipair=issue_count[7:0];
    wire [1:0] iop=(st==S_INIT)?OP_INIT:(st==S_PASS1)?OP_PASS1:OP_PASS2;
    assign pair_index=ipair;
    assign ckpt_pair_rd_en=issue_valid&&(st==S_PASS1);
    assign scratch_pair_rd_en=issue_valid&&(st==S_PASS2);
    assign data_pair_rd_en=issue_valid&&(st==S_PASS1);
    assign dp_pair_valid=(st==S_INIT)?issue_valid:(st==S_PASS1)?issue_v_d2:(st==S_PASS2)?issue_v_d1:1'b0;
    assign dp_pair_index=(st==S_INIT)?ipair:(st==S_PASS1)?pair_d2:pair_d1;
    assign dp_op=(st==S_MEAN)?OP_MEAN:(st==S_INIT)?OP_INIT:(st==S_PASS1)?op_d2:op_d1;
    assign acc_clear=(st==S_PASS1)&&issue_valid&&(issue_count==0);
    assign iter_busy=(st!=S_IDLE); assign state=st;
    wire last_out=dp_pair_out_valid&&(out_count==PAIRS-1);
    wire last_sum=dp_sum_commit&&(sum_count==PAIRS-1);

    always @(posedge clk) begin
      if(!rstn) begin st<=S_IDLE;issue_count<=0;out_count<=0;sum_count<=0;iterations_left<=0;pass1_out_done<=0;pass1_sum_done<=0;issue_v_d1<=0;issue_v_d2<=0;pair_d1<=0;pair_d2<=0;op_d1<=OP_INIT;op_d2<=OP_INIT;iter_done<=0;pass_tick<=0; end
      else begin
        iter_done<=0;pass_tick<=0;
        issue_v_d1<=issue_valid; issue_v_d2<=issue_v_d1;
        if(issue_valid) begin pair_d1<=ipair;op_d1<=iop;issue_count<=issue_count+1'b1; end
        pair_d2<=pair_d1; op_d2<=op_d1;
        if(dp_pair_out_valid) out_count<=out_count+1'b1;
        if(dp_sum_commit) sum_count<=sum_count+1'b1;
        case(st)
          S_IDLE: begin issue_count<=0;out_count<=0;sum_count<=0;pass1_out_done<=0;pass1_sum_done<=0;
            if(iter_start) begin iterations_left<=iter_count; if(iter_do_init) st<=S_INIT; else if(iter_count!=0) st<=S_PASS1; else iter_done<=1; end end
          S_INIT: if(last_out) begin issue_count<=0;out_count<=0;sum_count<=0; if(iterations_left!=0) st<=S_PASS1; else begin st<=S_IDLE;iter_done<=1;end end
          S_PASS1: begin if(last_out)pass1_out_done<=1;if(last_sum)pass1_sum_done<=1;
            if((pass1_out_done||last_out)&&(pass1_sum_done||last_sum)) begin issue_count<=0;out_count<=0;sum_count<=0;pass1_out_done<=0;pass1_sum_done<=0;pass_tick<=1;st<=S_MEAN;end end
          S_MEAN: begin issue_count<=0;out_count<=0;sum_count<=0;st<=S_PASS2;end
          S_PASS2: if(last_out) begin issue_count<=0;out_count<=0;sum_count<=0;pass_tick<=1;
            if(iterations_left==1) begin iterations_left<=0;st<=S_IDLE;iter_done<=1;end else begin iterations_left<=iterations_left-1'b1;st<=S_PASS1;end end
          default: st<=S_IDLE;
        endcase
      end
    end
endmodule

//------------------------------------------------------------------------------
// Physical kernel seam matching the K4 checkpoint executor's src/dst/bridge
// contract. Dataset/mask pair rows are external in this integration gate.
//------------------------------------------------------------------------------

//==============================================================================
// E4 intra-iteration datapath/controller extensions (2026-09-06)
//==============================================================================
//
// 200 MHz version (final_200mhz).
//
// The E4 datapath below keeps the arithmetic of the 100 MHz module bit for
// bit (same predicate, Oracle flip, 32-lane tree order, accumulator width,
// round-even 2*mean and symmetric saturation) and only moves register
// boundaries.  Timeline for one quad issued by the controller on cycle 0:
//
//   0      controller issues the quad (checkpoint + data memory requests)
//   0->4   memories: two request registers, BRAM, output register
//   2      controller's issue tag (valid/op/quad) reaches this module
//   3      tag copied once per 4-lane group, 4  once per lane
//   4      S1 captures predicate / padding / mask / amplitude
//   5      S2: hit = pred & pad & not-found;  sub = (PASS1 ? 0 : 2*mean) - amp
//   6      S3: INIT constant / PASS1 Oracle (hit ? -amp : amp) / PASS2
//          saturated 2*mean - amp  -> amp*_out
//   7      quad_out_valid (memory write request); the PASS1 tree reads amp*_out
//   7..12  PASS1 only: five tree levels, then the 39-bit accumulator
//
// PASS1 Oracle: grover_oracle_flip computes (amp ^ {hit}) + hit, i.e. -amp
// when hit; S2 forms 0 - amp in the same 25-bit subtractor PASS2 uses for
// 2*mean - amp, and S3 keeps its low 23 bits -- the identical value.
//
// At 5 ns one register cannot reach all 128 lanes: each lane sits next to
// its RAMB18/RAMB36, all over the die.  Lane b of the four quads shares data
// bank b, so the four quad-lanes of one lane index end up together; the
// broadcast trees are organised that way.  Values that change every cycle
// (valid/op/quad) ride the tag delay line, which is now one copy per 4-lane
// group (cycle 3) and one per lane (cycle 4) -- no extra latency.  Values
// fixed during a run (predicate mode, thresholds, data_count, enum_enable;
// run_* registers change only on an accepted start, many cycles before the
// first PASS1) and 2*mean (fixed for the whole PASS2, set several cycles
// before the first PASS2 lane needs it) get the same two-level copy tree.
//==============================================================================
module grover_iter_datapath_e4 (
    input  wire                                      clk,
    input  wire                                      rstn,
    input  wire [1:0]                                op,          // issue tag, 2 cycles after issue
    input  wire                                      quad_valid,  // "
    input  wire [6:0]                                quad_index,  // "
    input  wire                                      acc_clear,
    input  wire [`GP_P*`GP_AMP_W-1:0]                amp0_in,
    input  wire [`GP_P*`GP_AMP_W-1:0]                amp1_in,
    input  wire [`GP_P*`GP_AMP_W-1:0]                amp2_in,
    input  wire [`GP_P*`GP_AMP_W-1:0]                amp3_in,
    input  wire [`GP_P*`GP_DATA_W-1:0]               data0_in,
    input  wire [`GP_P*`GP_DATA_W-1:0]               data1_in,
    input  wire [`GP_P*`GP_DATA_W-1:0]               data2_in,
    input  wire [`GP_P*`GP_DATA_W-1:0]               data3_in,
    input  wire [`GP_P-1:0]                          mask0_in,
    input  wire [`GP_P-1:0]                          mask1_in,
    input  wire [`GP_P-1:0]                          mask2_in,
    input  wire [`GP_P-1:0]                          mask3_in,
    input  wire [1:0]                                predicate_mode,
    input  wire signed [`GP_DATA_W-1:0]              threshold_a,
    input  wire signed [`GP_DATA_W-1:0]              threshold_b,
    input  wire [`GP_DATA_COUNT_W-1:0]               data_count,
    input  wire                                      enum_enable,
    output wire [`GP_P*`GP_AMP_W-1:0]                amp0_out,
    output wire [`GP_P*`GP_AMP_W-1:0]                amp1_out,
    output wire [`GP_P*`GP_AMP_W-1:0]                amp2_out,
    output wire [`GP_P*`GP_AMP_W-1:0]                amp3_out,
    output reg                                       quad_out_valid,
    output reg  [6:0]                                quad_out_index,
    output wire signed [`GP_ACC_W-1:0]                global_sum,
    output wire signed [`GP_TWO_MEAN_W-1:0]           two_mean,
    output wire                                      sum_commit,
    output reg                                       sat_event
);
    localparam [1:0] OP_INIT=2'd0,OP_PASS1=2'd1,OP_MEAN=2'd2,OP_PASS2=2'd3;
    localparam integer P=`GP_P, AMP_W=`GP_AMP_W, DATA_W=`GP_DATA_W;
    localparam integer LOGP=`GP_LOGP, ROW_W=`GP_ROW_W, COUNT_W=`GP_DATA_COUNT_W;
    localparam integer DW=`GP_DIFF_W, TMW=`GP_TWO_MEAN_W;
    localparam integer NLG=8, GLN=P/NLG;    // eight groups of four lane indices

    wire [P*AMP_W-1:0]  amp_in  [0:3];
    wire [P*DATA_W-1:0] data_in [0:3];
    wire [P-1:0]        mask_in [0:3];
    assign amp_in[0]=amp0_in;   assign amp_in[1]=amp1_in;
    assign amp_in[2]=amp2_in;   assign amp_in[3]=amp3_in;
    assign data_in[0]=data0_in; assign data_in[1]=data1_in;
    assign data_in[2]=data2_in; assign data_in[3]=data3_in;
    assign mask_in[0]=mask0_in; assign mask_in[1]=mask1_in;
    assign mask_in[2]=mask2_in; assign mask_in[3]=mask3_in;

    //--------------------------------------------------------------------------
    // Reference tag pipeline: drives quad_out_*, the tree enables and MEAN.
    // It runs alongside the per-lane copies with the same timing.
    //--------------------------------------------------------------------------
    reg       rv3, rv4;
    reg [1:0] rop3, rop4;
    reg [6:0] ridx3, ridx4, ridx1, ridx2;
    reg       rv1_init, rv1_p1, rv1_p2, rv2_init, rv2_p1, rv2_p2, rvo_p1;
    reg       mean_d3, mean_d4, acc_clear_r;

    always @(posedge clk) begin
        if (!rstn) begin
            rv3<=0; rv4<=0; rop3<=0; rop4<=0;
            rv1_init<=0; rv1_p1<=0; rv1_p2<=0; rv2_init<=0; rv2_p1<=0; rv2_p2<=0; rvo_p1<=0;
            quad_out_valid<=0; mean_d3<=0; mean_d4<=0; acc_clear_r<=0;
        end else begin
            rv3 <= quad_valid; rop3 <= op;
            rv4 <= rv3;        rop4 <= rop3;
            rv1_init <= rv4 && (rop4==OP_INIT);
            rv1_p1   <= rv4 && (rop4==OP_PASS1);
            rv1_p2   <= rv4 && (rop4==OP_PASS2);
            rv2_init <= rv1_init; rv2_p1 <= rv1_p1; rv2_p2 <= rv1_p2;
            quad_out_valid <= rv2_init || rv2_p1 || rv2_p2;
            rvo_p1   <= rv2_p1;               // amp*_out holds PASS1 Oracle data
            mean_d3 <= (op==OP_MEAN);
            mean_d4 <= mean_d3;
            acc_clear_r <= acc_clear;
        end
    end
    always @(posedge clk) begin
        ridx3 <= quad_index; ridx4 <= ridx3;
        ridx1 <= ridx4; ridx2 <= ridx1;
        quad_out_index <= ridx2;
    end

    //--------------------------------------------------------------------------
    // 2*mean: free-running pipeline from the four accumulators.  tot_r is
    // final by the time the delayed MEAN pulse (mean_d4) captures it.
    //--------------------------------------------------------------------------
    wire signed [`GP_ACC_W-1:0] total0,total1,total2,total3;
    reg  signed [`GP_ACC_W+1:0] s01_r, s23_r, tot_r;
    always @(posedge clk) begin
        s01_r <= {{2{total0[`GP_ACC_W-1]}},total0} + {{2{total1[`GP_ACC_W-1]}},total1};
        s23_r <= {{2{total2[`GP_ACC_W-1]}},total2} + {{2{total3[`GP_ACC_W-1]}},total3};
        tot_r <= s01_r + s23_r;
    end
    assign global_sum = tot_r[`GP_ACC_W-1:0];
    wire signed [TMW-1:0] two_mean_comb;
    grover_two_mean_calc u_mean(.total(global_sum),.two_mean(two_mean_comb));
    reg signed [TMW-1:0] two_mean_r;
    always @(posedge clk) begin
        if (!rstn)        two_mean_r <= 0;
        else if (mean_d4) two_mean_r <= two_mean_comb;
    end
    assign two_mean = two_mean_r;

    //--------------------------------------------------------------------------
    // Lane engines: group g (lane indices 4g..4g+3) -> lane b -> quad q.
    //--------------------------------------------------------------------------
    wire [P*AMP_W-1:0] out_s3 [0:3];
    wire [NLG-1:0]     sat_grp;

    genvar g, b, q;
    generate for (g=0; g<NLG; g=g+1) begin: g_lg
        // Level-1 copies (one per 4-lane group), cycle 3.
        (* dont_touch = "true" *) reg       gv;
        (* dont_touch = "true" *) reg [1:0] gop;
        (* dont_touch = "true" *) reg [6:0] gidx;
        (* dont_touch = "true" *) reg [1:0]               mode_g;
        (* dont_touch = "true" *) reg signed [DATA_W-1:0] thr_a_g, thr_b_g;
        (* dont_touch = "true" *) reg [COUNT_W-1:0]       count_g;
        (* dont_touch = "true" *) reg                     enum_g;
        (* dont_touch = "true" *) reg signed [TMW-1:0]    tm_g;
        always @(posedge clk) begin
            if (!rstn) gv <= 1'b0;
            else       gv <= quad_valid;
            gop     <= op;
            gidx    <= quad_index;
            mode_g  <= predicate_mode;
            thr_a_g <= threshold_a;
            thr_b_g <= threshold_b;
            count_g <= data_count;
            enum_g  <= (enum_enable===1'b1);
            if (!rstn)        tm_g <= 0;
            else if (mean_d4) tm_g <= two_mean_comb;
        end
        // Row padding for the four rows {gidx, q}: full_rows/tail come from
        // data_count exactly as before.  Registered with the lane copies.
        wire [ROW_W:0]  full_rows_g = count_g[COUNT_W-1:LOGP];
        wire [3:0] rb_g, rt_g;
        for (q=0; q<4; q=q+1) begin: g_rowpad
            localparam [1:0] QI = q;
            wire [ROW_W:0] row_ext = {1'b0, gidx, QI};
            assign rb_g[q] = (row_ext <  full_rows_g);
            assign rt_g[q] = (row_ext == full_rows_g);
        end

        wire [GLN-1:0] sat_lanes;

        for (b=g*GLN; b<(g+1)*GLN; b=b+1) begin: g_ln
            localparam [LOGP-1:0] LANE_INDEX=b;
            // Level-2 copies (one per lane index, shared by its four
            // quad-lanes), cycle 4.
            (* dont_touch = "true" *) reg       lv;
            (* dont_touch = "true" *) reg [1:0] lop;
            (* dont_touch = "true" *) reg [3:0] rb_l, rt_l;
            (* dont_touch = "true" *) reg [LOGP-1:0]          tail_l;
            (* dont_touch = "true" *) reg [1:0]               mode_l;
            (* dont_touch = "true" *) reg signed [DATA_W-1:0] thr_a_l, thr_b_l;
            (* dont_touch = "true" *) reg                     enum_l;
            (* dont_touch = "true" *) reg signed [TMW-1:0]    tm_l;
            always @(posedge clk) begin
                if (!rstn) lv <= 1'b0;
                else       lv <= gv;
                lop     <= gop;
                rb_l    <= rb_g;
                rt_l    <= rt_g;
                tail_l  <= count_g[LOGP-1:0];
                mode_l  <= mode_g;
                thr_a_l <= thr_a_g;
                thr_b_l <= thr_b_g;
                enum_l  <= enum_g;
                tm_l    <= tm_g;
            end
            wire lane_in_tail = (LANE_INDEX < tail_l);
            wire signed [DW-1:0] tm_ext = {{(DW-TMW){tm_l[TMW-1]}}, tm_l};

            wire [3:0] sat_q;
            for (q=0; q<4; q=q+1) begin: g_q
                // Per quad-lane stage controls (local to the lane's flops).
                reg v1_init, v1_p1, v1_p2, v2_init, v2_p1, v2_p2;
                always @(posedge clk) begin
                    if (!rstn) begin
                        v1_init<=0; v1_p1<=0; v1_p2<=0; v2_init<=0; v2_p1<=0; v2_p2<=0;
                    end else begin
                        v1_init <= lv && (lop==OP_INIT);
                        v1_p1   <= lv && (lop==OP_PASS1);
                        v1_p2   <= lv && (lop==OP_PASS2);
                        v2_init <= v1_init; v2_p1 <= v1_p1; v2_p2 <= v1_p2;
                    end
                end

                wire signed [DATA_W-1:0] d = $signed(data_in[q][b*DATA_W +: DATA_W]);
                wire pred_raw;
                grover_predicate #(.USE_PADDING(0)) u_p(.mode(mode_l),.value(d),
                    .threshold_a(thr_a_l),.threshold_b(thr_b_l),
                    .index({`GP_INDEX_W{1'b0}}),.data_count({`GP_DATA_COUNT_W{1'b0}}),
                    .hit(pred_raw));

                // S1 (no clock enable).
                reg pred_s1, pad_s1, nf_s1;
                reg signed [AMP_W-1:0] amp_s1;
                always @(posedge clk) begin
                    pred_s1 <= pred_raw;
                    pad_s1  <= rb_l[q] | (rt_l[q] && lane_in_tail);
                    nf_s1   <= enum_l ? ~mask_in[q][b] : 1'b1;
                    amp_s1  <= $signed(amp_in[q][b*AMP_W +: AMP_W]);
                end

                // S2: hit, and one 25-bit subtractor for both passes.
                wire signed [DW-1:0] a_ext = {{(DW-AMP_W){amp_s1[AMP_W-1]}}, amp_s1};
                reg hit_s2;
                reg signed [AMP_W-1:0] amp_s2;
                reg signed [DW-1:0] sub_s2;
                always @(posedge clk) begin
                    hit_s2 <= pred_s1 & pad_s1 & nf_s1;
                    amp_s2 <= amp_s1;
                    sub_s2 <= (v1_p1 ? {DW{1'b0}} : tm_ext) - a_ext;
                end

                // S3: saturate PASS2, select the output source.
                wire signed [AMP_W-1:0] x;
                wire sat;
                grover_amp_sat25 u_s(.diff(sub_s2),.amp_out(x),.sat(sat));
                reg [AMP_W-1:0] out_r;
                reg sat_r;
                always @(posedge clk) begin
                    out_r <= v2_init ? `GP_INIT_AMP_RAW :
                             v2_p1   ? (hit_s2 ? sub_s2[AMP_W-1:0] : amp_s2) : x;
                    sat_r <= v2_p2 & sat;
                end
                assign out_s3[q][b*AMP_W +: AMP_W] = out_r;
                assign sat_q[q] = sat_r;
            end
            assign sat_lanes[b-g*GLN] = |sat_q;
        end

        reg sat_any;
        always @(posedge clk) sat_any <= |sat_lanes;
        assign sat_grp[g] = sat_any;
    end endgenerate

    assign amp0_out = out_s3[0]; assign amp1_out = out_s3[1];
    assign amp2_out = out_s3[2]; assign amp3_out = out_s3[3];

    always @(posedge clk) begin
        if (!rstn) sat_event <= 1'b0;
        else       sat_event <= |sat_grp;
    end

    //--------------------------------------------------------------------------
    // PASS1 sums: the tree reads the registered output (the Oracle amplitudes
    // in a PASS1 cycle); its output is a register, so the accumulator add
    // starts from flops too.
    //--------------------------------------------------------------------------
    wire signed [`GP_PARTIAL_SUM_W-1:0] partial0,partial1,partial2,partial3;
    wire pv0,pv1,pv2,pv3;
    grover_adder_tree_p5 u_sum0(.clk(clk),.rstn(rstn),.en(rvo_p1),.din(out_s3[0]),.partial(partial0),.valid_out(pv0));
    grover_adder_tree_p5 u_sum1(.clk(clk),.rstn(rstn),.en(rvo_p1),.din(out_s3[1]),.partial(partial1),.valid_out(pv1));
    grover_adder_tree_p5 u_sum2(.clk(clk),.rstn(rstn),.en(rvo_p1),.din(out_s3[2]),.partial(partial2),.valid_out(pv2));
    grover_adder_tree_p5 u_sum3(.clk(clk),.rstn(rstn),.en(rvo_p1),.din(out_s3[3]),.partial(partial3),.valid_out(pv3));
    wire pvalid=pv0&pv1&pv2&pv3;

    grover_sum_accum u_a0(.clk(clk),.rstn(rstn),.clear(acc_clear_r),.en(pvalid),.partial(partial0),.total(total0));
    grover_sum_accum u_a1(.clk(clk),.rstn(rstn),.clear(acc_clear_r),.en(pvalid),.partial(partial1),.total(total1));
    grover_sum_accum u_a2(.clk(clk),.rstn(rstn),.clear(acc_clear_r),.en(pvalid),.partial(partial2),.total(total2));
    grover_sum_accum u_a3(.clk(clk),.rstn(rstn),.clear(acc_clear_r),.en(pvalid),.partial(partial3),.total(total3));
    assign sum_commit=pvalid;
endmodule

// Data/mask aligner.  The E4 data and found-mask memories answer three
// cycles after the request (two request registers + BRAM) and this register
// makes it four, the same as the checkpoint memory.  The data/mask flops
// capture every cycle (the old req_d clock enable fanned out to 2,176
// flops); aligned_valid still marks the cycle that belongs to a request.
module grover_e4_oracle_align_quad (
    input wire clk,input wire rstn,input wire req_en,
    input wire [`GP_P*`GP_DATA_W-1:0] data0_raw,input wire [`GP_P*`GP_DATA_W-1:0] data1_raw,
    input wire [`GP_P*`GP_DATA_W-1:0] data2_raw,input wire [`GP_P*`GP_DATA_W-1:0] data3_raw,
    input wire [`GP_P-1:0] mask0_raw,input wire [`GP_P-1:0] mask1_raw,
    input wire [`GP_P-1:0] mask2_raw,input wire [`GP_P-1:0] mask3_raw,
    output reg [`GP_P*`GP_DATA_W-1:0] data0_aligned,output reg [`GP_P*`GP_DATA_W-1:0] data1_aligned,
    output reg [`GP_P*`GP_DATA_W-1:0] data2_aligned,output reg [`GP_P*`GP_DATA_W-1:0] data3_aligned,
    output reg [`GP_P-1:0] mask0_aligned,output reg [`GP_P-1:0] mask1_aligned,
    output reg [`GP_P-1:0] mask2_aligned,output reg [`GP_P-1:0] mask3_aligned,
    output reg aligned_valid
);
    reg req_d1, req_d2, req_d3;
    always @(posedge clk) begin
        if(!rstn) begin
            req_d1<=0;req_d2<=0;req_d3<=0;aligned_valid<=0;
        end else begin
            req_d1<=req_en;req_d2<=req_d1;req_d3<=req_d2;aligned_valid<=req_d3;
        end
    end
    always @(posedge clk) begin
        data0_aligned<=data0_raw;data1_aligned<=data1_raw;data2_aligned<=data2_raw;data3_aligned<=data3_raw;
        mask0_aligned<=mask0_raw;mask1_aligned<=mask1_raw;mask2_aligned<=mask2_raw;mask3_aligned<=mask3_raw;
    end
endmodule

// E4 controller.  Changes against the 100 MHz controller:
//   - The datapath tag (dp_quad_valid/dp_op/dp_quad_index) now leaves here
//     two cycles after issue for every op, INIT included; the datapath
//     copies it twice more and starts S1 four cycles after issue, matching
//     the 4-cycle memories.
//   - MEAN lasts three cycles; dp_op is OP_MEAN on the last one.  The
//     datapath delays that pulse by two more cycles before it captures
//     2*mean.
// Issue order, quad counts, iteration counting and the PASS1 exit rule (both
// the last output and the last sum seen) are unchanged.
module grover_ctrl_fsm_ckpt_e4 (
    input wire clk,input wire rstn,
    input wire iter_start,input wire iter_do_init,input wire [15:0] iter_count,
    input wire dp_quad_out_valid,input wire dp_sum_commit,
    output wire iter_busy,output reg iter_done,output wire [3:0] state,
    output wire [6:0] quad_index,output wire ckpt_quad_rd_en,
    output wire scratch_quad_rd_en,output wire data_quad_rd_en,
    output wire [1:0] dp_op,output wire dp_quad_valid,output wire [6:0] dp_quad_index,
    output wire acc_clear,output reg pass_tick
);
    localparam [3:0] S_IDLE=0,S_INIT=1,S_PASS1=2,S_MEAN=3,S_PASS2=4;
    localparam [1:0] OP_INIT=0,OP_PASS1=1,OP_MEAN=2,OP_PASS2=3;
    localparam integer QUADS=128;
    reg [3:0] st;
    reg [7:0] issue_count,out_count,sum_count;
    reg [15:0] iterations_left;
    reg pass1_out_done,pass1_sum_done;
    reg issue_v_d1,issue_v_d2;
    reg [6:0] quad_d1,quad_d2;
    reg [1:0] op_d1,op_d2;
    reg [1:0] mean_cnt;

    wire state_issues=(st==S_INIT)||(st==S_PASS1)||(st==S_PASS2);
    wire issue_valid=state_issues&&(issue_count<QUADS);
    wire [6:0] iquad=issue_count[6:0];
    wire [1:0] iop=(st==S_INIT)?OP_INIT:(st==S_PASS1)?OP_PASS1:OP_PASS2;
    assign quad_index=iquad;
    assign ckpt_quad_rd_en=issue_valid&&((st==S_PASS1)||(st==S_PASS2));
    assign scratch_quad_rd_en=1'b0;
    assign data_quad_rd_en=issue_valid&&(st==S_PASS1);
    // op_d2 only ever holds INIT/PASS1/PASS2, so OP_MEAN is unambiguous.
    assign dp_quad_valid=issue_v_d2;
    assign dp_quad_index=quad_d2;
    assign dp_op=((st==S_MEAN)&&(mean_cnt==2'd2))?OP_MEAN:op_d2;
    assign acc_clear=(st==S_PASS1)&&issue_valid&&(issue_count==0);
    assign iter_busy=(st!=S_IDLE);assign state=st;
    wire last_out=dp_quad_out_valid&&(out_count==QUADS-1);
    wire last_sum=dp_sum_commit&&(sum_count==QUADS-1);

    always @(posedge clk) begin
        if(!rstn) begin
            st<=S_IDLE;issue_count<=0;out_count<=0;sum_count<=0;iterations_left<=0;
            pass1_out_done<=0;pass1_sum_done<=0;issue_v_d1<=0;issue_v_d2<=0;
            quad_d1<=0;quad_d2<=0;op_d1<=OP_INIT;op_d2<=OP_INIT;
            iter_done<=0;pass_tick<=0;mean_cnt<=0;
        end else begin
            iter_done<=0;pass_tick<=0;
            issue_v_d1<=issue_valid;issue_v_d2<=issue_v_d1;
            if(issue_valid) begin quad_d1<=iquad;op_d1<=iop;issue_count<=issue_count+1'b1;end
            quad_d2<=quad_d1;op_d2<=op_d1;
            if(dp_quad_out_valid) out_count<=out_count+1'b1;
            if(dp_sum_commit) sum_count<=sum_count+1'b1;
            case(st)
                S_IDLE: begin issue_count<=0;out_count<=0;sum_count<=0;pass1_out_done<=0;pass1_sum_done<=0;
                    if(iter_start) begin iterations_left<=iter_count;if(iter_do_init)st<=S_INIT;else if(iter_count!=0)st<=S_PASS1;else iter_done<=1;end end
                S_INIT: if(last_out) begin issue_count<=0;out_count<=0;sum_count<=0;
                    if(iterations_left!=0)st<=S_PASS1;else begin st<=S_IDLE;iter_done<=1;end end
                S_PASS1: begin if(last_out)pass1_out_done<=1;if(last_sum)pass1_sum_done<=1;
                    if((pass1_out_done||last_out)&&(pass1_sum_done||last_sum)) begin
                        issue_count<=0;out_count<=0;sum_count<=0;pass1_out_done<=0;pass1_sum_done<=0;pass_tick<=1;
                        mean_cnt<=0;st<=S_MEAN;end end
                S_MEAN: begin issue_count<=0;out_count<=0;sum_count<=0;
                    if(mean_cnt==2'd2) st<=S_PASS2; else mean_cnt<=mean_cnt+1'b1; end
                S_PASS2: if(last_out) begin issue_count<=0;out_count<=0;sum_count<=0;pass_tick<=1;
                    if(iterations_left==1) begin iterations_left<=0;st<=S_IDLE;iter_done<=1;end
                    else begin iterations_left<=iterations_left-1'b1;st<=S_PASS1;end end
                default: st<=S_IDLE;
            endcase
        end
    end
endmodule
