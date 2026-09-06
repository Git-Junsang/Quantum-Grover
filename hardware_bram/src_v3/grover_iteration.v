//==============================================================================
// grover_iteration.v -- LPSoC BBHT/Grover Main IP v0.7g consolidated RTL
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
// grover_iter_datapath.v -- LPSoC BBHT/Grover Main IP v0.7 timing closure
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
    output reg                                       sat_event,

    // v3 PASS2 융합용. row_out_valid 와 정확히 같은 사이클에 뜨며, 그 행이
    // PASS2 결과(= 새 psi_j)임을 알립니다. 측정용 row_weight 를 이 행에서
    // 바로 만들기 위한 것입니다.
    output reg                                       row_out_is_pass2
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
            row_out_is_pass2 <= 1'b0;
            row_out_index    <= {ROW_W{1'b0}};
            two_mean         <= {`GP_TWO_MEAN_W{1'b0}};
            sat_event        <= 1'b0;
            lane_sat_pipe    <= {P{1'b0}};
            sat_pipe_valid   <= 1'b0;
            pass1_sum_valid  <= 1'b0;
        end else begin
            row_out_valid    <= 1'b0;
            row_out_is_pass2 <= 1'b0;

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
                amp_row_out      <= diffusion_row;
                row_out_index    <= row_index;
                row_out_valid    <= 1'b1;
                row_out_is_pass2 <= 1'b1;
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
// grover_ctrl_fsm.v -- LPSoC BBHT/Grover Main IP v0.7f timing-aligned controller
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
