//==============================================================================
// grover_memories.v -- LPSoC BBHT/Grover Main IP v0.6 consolidated RTL
//
// File-level consolidation only: verified module boundaries and logic are
// preserved. No new wrapper hierarchy is introduced by this merge.
// Consolidated from: grover_data_mem.v, grover_amp_mem.v, grover_row_weight_mem.v
//==============================================================================


//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_data_mem.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_data_mem.v
// LPSoC BBHT/Grover Main IP v0.6
//
// Dataset memory contract
//   - 32 banks x 512 rows x signed 16-bit
//   - global index mapping: bank=index[4:0], row=index[13:5]
//   - Port A: 32-lane synchronous parallel read for Oracle datapath
//   - Port B: one-item dataset load write OR one-item candidate verify read
//
// Port-B load/verify mutual exclusion is enforced by the upper-level controller.
// This memory intentionally has no reset so Vivado can infer block RAM.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_data_mem (
    input  wire                              clk,

    // Port A: one row -> 32 signed DATA_W lanes, synchronous 1-cycle read
    input  wire [`GP_ROW_W-1:0]              rd_row,
    input  wire                              rd_en,
    output wire [`GP_P*`GP_DATA_W-1:0]       rd_data,

    // Port B load write: exactly one global dataset item per accepted write
    input  wire [`GP_INDEX_W-1:0]            wr_index,
    input  wire                              wr_en,
    input  wire signed [`GP_DATA_W-1:0]       wr_data,

    // Port B candidate verify read: synchronous 1-cycle read
    input  wire [`GP_INDEX_W-1:0]            verify_index,
    output wire signed [`GP_DATA_W-1:0]       verify_data
);
    localparam integer P       = `GP_P;
    localparam integer DATA_W  = `GP_DATA_W;
    localparam integer LOGP    = `GP_LOGP;
    localparam integer ROW_W   = `GP_ROW_W;
    localparam integer ROWS    = `GP_ROWS;

    wire [LOGP-1:0] wr_bank;
    wire [ROW_W-1:0] wr_row;
    wire [LOGP-1:0] verify_bank;
    wire [ROW_W-1:0] verify_row;

    assign wr_bank     = wr_index[LOGP-1:0];
    assign wr_row      = wr_index[`GP_INDEX_W-1:LOGP];
    assign verify_bank = verify_index[LOGP-1:0];
    assign verify_row  = verify_index[`GP_INDEX_W-1:LOGP];

    // Port B is shared. During a write, its read value is don't-care because
    // candidate verification is not active. Otherwise it addresses verify_index.
    wire [ROW_W-1:0] port_b_row;
    assign port_b_row = wr_en ? wr_row : verify_row;

    wire [DATA_W-1:0] port_b_rdata [0:P-1];
    reg  [LOGP-1:0]   verify_bank_d;

    genvar b;
    generate
        for (b = 0; b < P; b = b + 1) begin : g_bank
            (* ram_style = "block" *) reg [DATA_W-1:0] mem [0:ROWS-1];
            reg [DATA_W-1:0] rd_a_q;
            reg [DATA_W-1:0] rd_b_q;
            wire bank_wr_en;

            assign bank_wr_en = wr_en && (wr_bank == b[LOGP-1:0]);

            // Port A: Oracle row read.
            always @(posedge clk) begin
                if (rd_en)
                    rd_a_q <= mem[rd_row];
            end

            // Port B: load-write / verify-read shared port.
            // Read-during-write data is intentionally unspecified and unused.
            always @(posedge clk) begin
                if (bank_wr_en)
                    mem[port_b_row] <= wr_data;
                rd_b_q <= mem[port_b_row];
            end

            assign rd_data[b*DATA_W +: DATA_W] = rd_a_q;
            assign port_b_rdata[b] = rd_b_q;
        end
    endgenerate

    // Delay the bank selector by the same one cycle as the BRAM Port-B read.
    always @(posedge clk)
        verify_bank_d <= verify_bank;

    assign verify_data = $signed(port_b_rdata[verify_bank_d]);

endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_data_mem.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_amp_mem.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_amp_mem.v
// LPSoC BBHT/Grover Main IP v0.6
//
// Amplitude state memory contract
//   - single current state (no ping-pong STATE_A/STATE_B)
//   - 32 banks x 512 rows x signed 23-bit (Q1.22 encoded amplitude)
//   - lane <-> bank is 1:1
//   - simple dual-port: independent synchronous read row and write row
//   - in-place Grover update: delayed row writeback may overlap later reads
//   - Born measurement is read-only; upper-level logic must keep wr_en=0
//
// This memory intentionally has no reset so Vivado can infer block RAM.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_amp_mem (
    input  wire                              clk,

    // Read port: one row -> 32 amplitude lanes, synchronous 1-cycle read
    input  wire [`GP_ROW_W-1:0]              rd_row,
    input  wire                              rd_en,
    output wire [`GP_P*`GP_AMP_W-1:0]        rd_amp,

    // Write port: all 32 lanes of one row written together
    input  wire [`GP_ROW_W-1:0]              wr_row,
    input  wire                              wr_en,
    input  wire [`GP_P*`GP_AMP_W-1:0]        wr_amp
);
    localparam integer P      = `GP_P;
    localparam integer AMP_W  = `GP_AMP_W;
    localparam integer ROWS   = `GP_ROWS;

    genvar b;
    generate
        for (b = 0; b < P; b = b + 1) begin : g_bank
            (* ram_style = "block" *) reg [AMP_W-1:0] mem [0:ROWS-1];
            reg [AMP_W-1:0] rd_q;

            // Independent synchronous read and write ports. No array reset.
            always @(posedge clk) begin
                if (rd_en)
                    rd_q <= mem[rd_row];
            end

            always @(posedge clk) begin
                if (wr_en)
                    mem[wr_row] <= wr_amp[b*AMP_W +: AMP_W];
            end

            assign rd_amp[b*AMP_W +: AMP_W] = rd_q;
        end
    endgenerate

endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_amp_mem.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_row_weight_mem.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_row_weight_mem.v -- Row->Lane Born row-weight storage, v0.6
//
// 512 rows x ROW_SUM_W=51 bits for Q14/P32/F22.
// The memory has one synchronous read port and one synchronous write port.
// No reset is applied to the array so Vivado can infer block RAM.
//
// A fresh Born measurement overwrites all 512 entries before any row-CDF read,
// therefore stale power-up contents are never consumed by the baseline path.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_row_weight_mem (
    input  wire                          clk,
    input  wire                          rd_en,
    input  wire [`GP_ROW_W-1:0]          rd_row,
    output wire [`GP_ROW_SUM_W-1:0]      rd_weight,
    input  wire                          wr_en,
    input  wire [`GP_ROW_W-1:0]          wr_row,
    input  wire [`GP_ROW_SUM_W-1:0]      wr_weight
);
    (* ram_style = "block" *) reg [`GP_ROW_SUM_W-1:0] mem [0:`GP_ROWS-1];
    reg [`GP_ROW_SUM_W-1:0] rd_q;

    always @(posedge clk) begin
        if (rd_en)
            rd_q <= mem[rd_row];
    end

    always @(posedge clk) begin
        if (wr_en)
            mem[wr_row] <= wr_weight;
    end

    assign rd_weight = rd_q;
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_row_weight_mem.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// Enumeration v0.3: found-mask memory
//------------------------------------------------------------------------------
// 16384 bits = 512 rows x 32 bits for Q14/P32.
// Port A is the Oracle row-read port. Port B is shared by verify reads,
// sequential clear, and read-modify-write bit set after a new target is found.
// The array intentionally has no reset so Vivado may infer BRAM.
//------------------------------------------------------------------------------
module grover_found_mask_mem (
    input  wire                              clk,
    input  wire                              rstn,

    // Port A: Oracle row read, synchronous one-cycle response.
    input  wire [`GP_ROW_W-1:0]              oracle_rd_row,
    input  wire                              oracle_rd_en,
    output wire [`GP_P-1:0]                  oracle_mask_row,

    // Port B: verify read.  verify_found is aligned to a synchronous read of
    // verify_index while the maintenance FSM is idle.
    input  wire [`GP_INDEX_W-1:0]            verify_index,
    output wire                              verify_found,

    // Maintenance requests are accepted only while maint_busy=0.
    input  wire                              clear_start,
    input  wire                              set_start,
    input  wire [`GP_INDEX_W-1:0]            set_index,
    output wire                              maint_busy,
    output reg                               clear_done,
    output reg                               set_done
);
    localparam integer ROW_W = `GP_ROW_W;
    localparam integer LOGP  = `GP_LOGP;
    localparam integer P     = `GP_P;

    localparam [2:0]
        M_IDLE      = 3'd0,
        M_CLEAR     = 3'd1,
        M_SET_READ  = 3'd2,
        M_SET_WRITE = 3'd3;

    (* ram_style = "block" *) reg [P-1:0] mem [0:`GP_ROWS-1];

    reg [P-1:0] oracle_q;
    reg [P-1:0] port_b_q;
    reg [2:0] maint_st;
    reg [ROW_W-1:0] clear_row;
    reg [ROW_W-1:0] set_row_r;
    reg [LOGP-1:0] set_lane_r;
    reg [LOGP-1:0] verify_lane_q;

    wire [ROW_W-1:0] verify_row = verify_index[`GP_INDEX_W-1:LOGP];
    wire [LOGP-1:0]  verify_lane = verify_index[LOGP-1:0];

    wire b_clear = (maint_st == M_CLEAR);
    wire b_set_read = (maint_st == M_SET_READ);
    wire b_set_write = (maint_st == M_SET_WRITE);

    wire [ROW_W-1:0] b_row = b_clear ? clear_row :
                             (b_set_read || b_set_write) ? set_row_r :
                             verify_row;
    wire b_we = b_clear || b_set_write;
    wire [P-1:0] set_onehot = ({{(P-1){1'b0}},1'b1} << set_lane_r);
    wire [P-1:0] b_wdata = b_clear ? {P{1'b0}} : (port_b_q | set_onehot);

    // Port A: Oracle row read.
    always @(posedge clk) begin
        if (oracle_rd_en)
            oracle_q <= mem[oracle_rd_row];
    end

    // Port B: read/write. Read-during-write value is not consumed.
    always @(posedge clk) begin
        if (b_we)
            mem[b_row] <= b_wdata;
        port_b_q <= mem[b_row];

        // Only the idle verify path updates the lane tag associated with the
        // synchronous Port-B read.
        if (maint_st == M_IDLE)
            verify_lane_q <= verify_lane;
    end

    assign oracle_mask_row = oracle_q;
    assign verify_found = port_b_q[verify_lane_q];
    assign maint_busy = (maint_st != M_IDLE);

    always @(posedge clk) begin
        if (!rstn) begin
            maint_st  <= M_IDLE;
            clear_row <= {ROW_W{1'b0}};
            set_row_r <= {ROW_W{1'b0}};
            set_lane_r <= {LOGP{1'b0}};
            clear_done <= 1'b0;
            set_done   <= 1'b0;
        end else begin
            clear_done <= 1'b0;
            set_done   <= 1'b0;

            case (maint_st)
                M_IDLE: begin
                    if (clear_start) begin
                        clear_row <= {ROW_W{1'b0}};
                        maint_st  <= M_CLEAR;
                    end else if (set_start) begin
                        set_row_r  <= set_index[`GP_INDEX_W-1:LOGP];
                        set_lane_r <= set_index[LOGP-1:0];
                        maint_st   <= M_SET_READ;
                    end
                end

                M_CLEAR: begin
                    if (clear_row == (`GP_ROWS-1)) begin
                        clear_done <= 1'b1;
                        maint_st   <= M_IDLE;
                    end else begin
                        clear_row <= clear_row + {{(ROW_W-1){1'b0}},1'b1};
                    end
                end

                M_SET_READ: begin
                    // port_b_q captures the old row on this edge.
                    maint_st <= M_SET_WRITE;
                end

                M_SET_WRITE: begin
                    // The bit-set row is committed on this edge.
                    set_done <= 1'b1;
                    maint_st <= M_IDLE;
                end

                default: maint_st <= M_IDLE;
            endcase
        end
    end
endmodule

//------------------------------------------------------------------------------
// Enumeration v0.3: result FIFO
//------------------------------------------------------------------------------
// Stores discovered target indices.  Full is backpressure, not termination.
// The memory is intentionally not forced to BRAM/LUTRAM; final inference is
// selected after RVX-integrated resource/timing measurements.
//------------------------------------------------------------------------------
module grover_result_fifo #(
    parameter integer DEPTH = `GP_RESULT_FIFO_DEPTH,
    parameter integer CNT_W = `GP_RESULT_FIFO_CNT_W
) (
    input  wire                              clk,
    input  wire                              rstn,
    input  wire                              clear,

    input  wire                              push,
    input  wire [`GP_INDEX_W-1:0]            push_data,
    output wire                              push_accept,

    input  wire                              pop,
    output wire [`GP_INDEX_W-1:0]            dout,
    output wire                              pop_accept,

    output wire                              empty,
    output wire                              full,
    output wire [CNT_W-1:0]                  count
);
    localparam integer PTR_W = (DEPTH <= 2) ? 1 : $clog2(DEPTH);
    localparam [CNT_W-1:0] DEPTH_COUNT = DEPTH;

    reg [`GP_INDEX_W-1:0] mem [0:DEPTH-1];
    reg [PTR_W-1:0] wptr;
    reg [PTR_W-1:0] rptr;
    reg [CNT_W-1:0] count_r;

    assign empty = (count_r == {CNT_W{1'b0}});
    assign full  = (count_r == DEPTH_COUNT);
    assign count = count_r;

    // FWFT-style head visibility.  For the initial 256x14 queue Vivado may
    // choose LUTRAM/register implementation; no ram_style is forced here.
    assign dout = mem[rptr];

    assign push_accept = push && !full;
    assign pop_accept  = pop  && !empty;

    always @(posedge clk) begin
        if (!rstn || clear) begin
            wptr    <= {PTR_W{1'b0}};
            rptr    <= {PTR_W{1'b0}};
            count_r <= {CNT_W{1'b0}};
        end else begin
            if (push_accept) begin
                mem[wptr] <= push_data;
                wptr <= wptr + {{(PTR_W-1){1'b0}},1'b1};
            end

            if (pop_accept)
                rptr <= rptr + {{(PTR_W-1){1'b0}},1'b1};

            case ({push_accept, pop_accept})
                2'b10: count_r <= count_r + {{(CNT_W-1){1'b0}},1'b1};
                2'b01: count_r <= count_r - {{(CNT_W-1){1'b0}},1'b1};
                default: ;
            endcase
        end
    end
endmodule
