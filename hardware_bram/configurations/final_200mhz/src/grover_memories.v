//==============================================================================
// grover_memories.v -- BBHT/Grover Main IP v0.6 consolidated RTL
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
// BBHT/Grover Main IP v0.6
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
// BBHT/Grover Main IP v0.6
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

//==============================================================================
// E2 intra-iteration memory extensions (2026-09-06)
// Reuse each bank's second BRAM port for the odd logical row while the Grover
// pair engine is active. Loader/verify/maintenance retain the frozen behavior
// whenever pair_rd_en=0.
//==============================================================================
module grover_data_mem_e2 (
    input  wire                              clk,
    input  wire [7:0]                        pair_rd_index,
    input  wire                              pair_rd_en,
    output wire [`GP_P*`GP_DATA_W-1:0]       pair_even_data,
    output wire [`GP_P*`GP_DATA_W-1:0]       pair_odd_data,
    input  wire [`GP_INDEX_W-1:0]            wr_index,
    input  wire                              wr_en,
    input  wire signed [`GP_DATA_W-1:0]      wr_data,
    input  wire [`GP_INDEX_W-1:0]            verify_index,
    output wire signed [`GP_DATA_W-1:0]      verify_data
);
    localparam integer P=`GP_P;
    localparam integer DATA_W=`GP_DATA_W;
    localparam integer LOGP=`GP_LOGP;
    localparam integer ROW_W=`GP_ROW_W;
    localparam integer ROWS=`GP_ROWS;

    wire [ROW_W-1:0] even_row = {pair_rd_index,1'b0};
    wire [ROW_W-1:0] odd_row  = {pair_rd_index,1'b1};
    wire [LOGP-1:0] wr_bank = wr_index[LOGP-1:0];
    wire [ROW_W-1:0] wr_row = wr_index[`GP_INDEX_W-1:LOGP];
    wire [LOGP-1:0] verify_bank = verify_index[LOGP-1:0];
    wire [ROW_W-1:0] verify_row = verify_index[`GP_INDEX_W-1:LOGP];
    wire [ROW_W-1:0] port_b_row = pair_rd_en ? odd_row : (wr_en ? wr_row : verify_row);
    wire [DATA_W-1:0] port_b_rdata [0:P-1];
    reg [LOGP-1:0] verify_bank_d;

    genvar b;
    generate for (b=0;b<P;b=b+1) begin: g_bank
        (* ram_style = "block" *) reg [DATA_W-1:0] mem [0:ROWS-1];
        reg [DATA_W-1:0] rd_a_q;
        reg [DATA_W-1:0] rd_b_q;
        wire bank_wr_en = (!pair_rd_en) && wr_en && (wr_bank==b[LOGP-1:0]);
        always @(posedge clk) begin
            if (pair_rd_en) rd_a_q <= mem[even_row];
        end
        always @(posedge clk) begin
            if (bank_wr_en) mem[port_b_row] <= wr_data;
            rd_b_q <= mem[port_b_row];
        end
        assign pair_even_data[b*DATA_W +: DATA_W] = rd_a_q;
        assign pair_odd_data [b*DATA_W +: DATA_W] = rd_b_q;
        assign port_b_rdata[b] = rd_b_q;
    end endgenerate

    always @(posedge clk) begin
        if (!pair_rd_en) verify_bank_d <= verify_bank;
    end
    assign verify_data = $signed(port_b_rdata[verify_bank_d]);
endmodule

module grover_found_mask_mem_e2 (
    input  wire                              clk,
    input  wire                              rstn,
    input  wire [7:0]                        pair_rd_index,
    input  wire                              pair_rd_en,
    output wire [`GP_P-1:0]                 pair_even_mask,
    output wire [`GP_P-1:0]                 pair_odd_mask,
    input  wire [`GP_INDEX_W-1:0]           verify_index,
    output wire                              verify_found,
    input  wire                              clear_start,
    input  wire                              set_start,
    input  wire [`GP_INDEX_W-1:0]           set_index,
    output wire                              maint_busy,
    output reg                               clear_done,
    output reg                               set_done
);
    localparam integer ROW_W=`GP_ROW_W;
    localparam integer LOGP=`GP_LOGP;
    localparam integer P=`GP_P;
    localparam [2:0] M_IDLE=3'd0,M_CLEAR=3'd1,M_SET_READ=3'd2,M_SET_WRITE=3'd3;
    (* ram_style = "block" *) reg [P-1:0] mem [0:`GP_ROWS-1];
    reg [P-1:0] even_q, port_b_q;
    reg [2:0] maint_st;
    reg [ROW_W-1:0] clear_row,set_row_r;
    reg [LOGP-1:0] set_lane_r,verify_lane_q;

    wire [ROW_W-1:0] even_row={pair_rd_index,1'b0};
    wire [ROW_W-1:0] odd_row ={pair_rd_index,1'b1};
    wire [ROW_W-1:0] verify_row=verify_index[`GP_INDEX_W-1:LOGP];
    wire [LOGP-1:0] verify_lane=verify_index[LOGP-1:0];
    wire b_clear=(maint_st==M_CLEAR);
    wire b_set_read=(maint_st==M_SET_READ);
    wire b_set_write=(maint_st==M_SET_WRITE);
    wire pair_b_active=pair_rd_en&&(maint_st==M_IDLE);
    wire [ROW_W-1:0] b_row = b_clear ? clear_row :
                             (b_set_read||b_set_write) ? set_row_r :
                             pair_b_active ? odd_row : verify_row;
    wire b_we=b_clear||b_set_write;
    wire [P-1:0] set_onehot=({{(P-1){1'b0}},1'b1} << set_lane_r);
    wire [P-1:0] b_wdata=b_clear ? {P{1'b0}} : (port_b_q|set_onehot);

    always @(posedge clk) begin
        if (pair_rd_en) even_q <= mem[even_row];
    end
    always @(posedge clk) begin
        if (b_we) mem[b_row] <= b_wdata;
        port_b_q <= mem[b_row];
        if ((maint_st==M_IDLE)&&!pair_rd_en) verify_lane_q <= verify_lane;
    end
    assign pair_even_mask=even_q;
    assign pair_odd_mask=port_b_q;
    assign verify_found=port_b_q[verify_lane_q];
    assign maint_busy=(maint_st!=M_IDLE);

    always @(posedge clk) begin
        if(!rstn) begin
            maint_st<=M_IDLE; clear_row<=0; set_row_r<=0; set_lane_r<=0;
            clear_done<=0; set_done<=0;
        end else begin
            clear_done<=0; set_done<=0;
            case(maint_st)
                M_IDLE: begin
                    if(clear_start) begin clear_row<=0; maint_st<=M_CLEAR; end
                    else if(set_start) begin set_row_r<=set_index[`GP_INDEX_W-1:LOGP]; set_lane_r<=set_index[LOGP-1:0]; maint_st<=M_SET_READ; end
                end
                M_CLEAR: begin
                    if(clear_row==(`GP_ROWS-1)) begin clear_done<=1; maint_st<=M_IDLE; end
                    else clear_row<=clear_row+1'b1;
                end
                M_SET_READ: maint_st<=M_SET_WRITE;
                M_SET_WRITE: begin set_done<=1; maint_st<=M_IDLE; end
                default: maint_st<=M_IDLE;
            endcase
        end
    end
endmodule

//==============================================================================
// E4 intra-iteration memory extensions (2026-09-06)
// Four consecutive rows per issue. Two row[1]-selected physical banks are used;
// each bank consumes both RAM ports for the two row[0] values.
//==============================================================================
module grover_data_mem_e4 (
    input  wire                              clk,
    input  wire [6:0]                        quad_rd_index,
    input  wire                              quad_rd_en,
    output wire [`GP_P*`GP_DATA_W-1:0]       quad_data0,
    output wire [`GP_P*`GP_DATA_W-1:0]       quad_data1,
    output wire [`GP_P*`GP_DATA_W-1:0]       quad_data2,
    output wire [`GP_P*`GP_DATA_W-1:0]       quad_data3,
    input  wire [`GP_INDEX_W-1:0]            wr_index,
    input  wire                              wr_en,
    input  wire signed [`GP_DATA_W-1:0]      wr_data,
    input  wire [`GP_INDEX_W-1:0]            verify_index,
    output wire signed [`GP_DATA_W-1:0]      verify_data
);
    localparam integer P=`GP_P;
    localparam integer DATA_W=`GP_DATA_W;
    localparam integer LOGP=`GP_LOGP;
    localparam integer ROW_W=`GP_ROW_W;

    wire [LOGP-1:0] wr_lane=wr_index[LOGP-1:0];
    wire [ROW_W-1:0] wr_grow=wr_index[`GP_INDEX_W-1:LOGP];
    wire wr_bank_sel=wr_grow[1];
    wire [7:0] wr_lrow={wr_grow[ROW_W-1:2],wr_grow[0]};

    wire [LOGP-1:0] verify_lane=verify_index[LOGP-1:0];
    wire [ROW_W-1:0] verify_grow=verify_index[`GP_INDEX_W-1:LOGP];
    wire verify_bank_sel=verify_grow[1];
    wire [7:0] verify_lrow={verify_grow[ROW_W-1:2],verify_grow[0]};

    // 200 MHz: two-level request tree.  Level A is one register set per
    // group of four lane banks, level B one per lane bank, both dont_touch so
    // synthesis keeps the copies.  Requests reach the RAMB18 pins two edges
    // after they are presented:
    //   quad read : request edge -> A -> B -> BRAM -> quad_data* (3 cycles)
    //               (+1 in grover_e4_oracle_align_quad = 4, like the
    //               checkpoint memory)
    //   load write: two edges later; nothing reads during a load
    //   verify    : index -> A -> B -> BRAM -> group select reg -> final
    //               select reg -> verify_data, valid 5 cycles after the index
    //               (grover_verify waits for it)
    localparam integer NG = P/4;
    (* dont_touch = "true" *) reg       a_rd_en     [0:NG-1];
    (* dont_touch = "true" *) reg [6:0] a_rd_index  [0:NG-1];
    (* dont_touch = "true" *) reg       a_wr_en     [0:NG-1];
    (* dont_touch = "true" *) reg [LOGP-1:0] a_wr_lane [0:NG-1];
    (* dont_touch = "true" *) reg       a_wr_bank   [0:NG-1];
    (* dont_touch = "true" *) reg [7:0] a_wr_lrow   [0:NG-1];
    (* dont_touch = "true" *) reg [7:0] a_verify_lrow [0:NG-1];
    reg [DATA_W-1:0] a_wr_data [0:NG-1];
    integer ga;
    always @(posedge clk) begin
        for (ga = 0; ga < NG; ga = ga + 1) begin
            a_rd_en[ga]       <= quad_rd_en;
            a_rd_index[ga]    <= quad_rd_index;
            a_wr_en[ga]       <= (!quad_rd_en) && wr_en;
            a_wr_lane[ga]     <= wr_lane;
            a_wr_bank[ga]     <= wr_bank_sel;
            a_wr_lrow[ga]     <= wr_lrow;
            a_verify_lrow[ga] <= verify_lrow;
            a_wr_data[ga]     <= wr_data;
        end
    end

    // Verify select pipeline: lane/bank of the verify index, delayed to the
    // edge where each select stage uses it.
    (* dont_touch = "true" *) reg [LOGP-1:0] v_lane_d1, v_lane_d2, v_lane_d3, v_lane_d4;
    (* dont_touch = "true" *) reg            v_bank_d1, v_bank_d2;
    always @(posedge clk) begin
        v_lane_d1 <= verify_lane;  v_bank_d1 <= verify_bank_sel;
        v_lane_d2 <= v_lane_d1;    v_bank_d2 <= v_bank_d1;
        v_lane_d3 <= v_lane_d2;
        v_lane_d4 <= v_lane_d3;
    end

    wire [DATA_W-1:0] group_sel [0:NG-1];

    genvar b, g;
    generate for (g=0; g<NG; g=g+1) begin: g_grp
        wire [DATA_W-1:0] gq0 [0:3];
        wire [DATA_W-1:0] gq1 [0:3];
        for (b=4*g; b<4*g+4; b=b+1) begin: g_e4_bank
            (* ram_style = "block" *) reg [DATA_W-1:0] mem0 [0:255];
            (* ram_style = "block" *) reg [DATA_W-1:0] mem1 [0:255];
            reg [DATA_W-1:0] q0a,q0b,q1a,q1b;
            // Level B: one register set per RAMB18 (mem0 / mem1 can be
            // placed apart, so they do not share request flops).
            (* dont_touch = "true" *) reg       rd_en_0, rd_en_1;
            (* dont_touch = "true" *) reg [6:0] rd_index_0, rd_index_1;
            (* dont_touch = "true" *) reg       wr0_r, wr1_r;
            (* dont_touch = "true" *) reg [7:0] wr_lrow_0, wr_lrow_1, verify_lrow_0, verify_lrow_1;
            reg [DATA_W-1:0] wr_data_0, wr_data_1;
            wire wr_this = a_wr_en[g] && (a_wr_lane[g] == b[LOGP-1:0]);
            always @(posedge clk) begin
                rd_en_0       <= a_rd_en[g];        rd_en_1       <= a_rd_en[g];
                rd_index_0    <= a_rd_index[g];     rd_index_1    <= a_rd_index[g];
                wr0_r         <= wr_this && !a_wr_bank[g];
                wr1_r         <= wr_this &&  a_wr_bank[g];
                wr_lrow_0     <= a_wr_lrow[g];      wr_lrow_1     <= a_wr_lrow[g];
                verify_lrow_0 <= a_verify_lrow[g];  verify_lrow_1 <= a_verify_lrow[g];
                wr_data_0     <= a_wr_data[g];      wr_data_1     <= a_wr_data[g];
            end
            wire [7:0] baddr0=rd_en_0?{rd_index_0,1'b1}:(wr0_r?wr_lrow_0:verify_lrow_0);
            wire [7:0] baddr1=rd_en_1?{rd_index_1,1'b1}:(wr1_r?wr_lrow_1:verify_lrow_1);
            wire [7:0] aaddr0=rd_en_0?{rd_index_0,1'b0}:verify_lrow_0;
            wire [7:0] aaddr1=rd_en_1?{rd_index_1,1'b0}:verify_lrow_1;

            always @(posedge clk) begin
                if (rd_en_0) q0a<=mem0[aaddr0];
                if (wr0_r) mem0[baddr0]<=wr_data_0;
                q0b<=mem0[baddr0];
            end
            always @(posedge clk) begin
                if (rd_en_1) q1a<=mem1[aaddr1];
                if (wr1_r) mem1[baddr1]<=wr_data_1;
                q1b<=mem1[baddr1];
            end
            assign quad_data0[b*DATA_W +: DATA_W]=q0a;
            assign quad_data1[b*DATA_W +: DATA_W]=q0b;
            assign quad_data2[b*DATA_W +: DATA_W]=q1a;
            assign quad_data3[b*DATA_W +: DATA_W]=q1b;
            assign gq0[b-4*g]=q0b;
            assign gq1[b-4*g]=q1b;
        end
        // Group stage of the verify select: one of the group's 8 words.
        // The select is copied per group (its own d3 flops).
        (* dont_touch = "true" *) reg [1:0] g_lane_d3;
        (* dont_touch = "true" *) reg       g_bank_d3;
        always @(posedge clk) begin
            g_lane_d3 <= v_lane_d2[1:0];
            g_bank_d3 <= v_bank_d2;
        end
        reg [DATA_W-1:0] gsel_r;
        always @(posedge clk)
            gsel_r <= g_bank_d3 ? gq1[g_lane_d3] : gq0[g_lane_d3];
        assign group_sel[g] = gsel_r;
    end endgenerate

    // Final stage of the verify select: one of the 8 groups.
    reg [DATA_W-1:0] verify_r;
    always @(posedge clk) verify_r <= group_sel[v_lane_d4[LOGP-1:2]];
    assign verify_data=$signed(verify_r);
endmodule

module grover_found_mask_mem_e4 (
    input  wire                              clk,
    input  wire                              rstn,
    input  wire [6:0]                        quad_rd_index,
    input  wire                              quad_rd_en,
    output wire [`GP_P-1:0]                 quad_mask0,
    output wire [`GP_P-1:0]                 quad_mask1,
    output wire [`GP_P-1:0]                 quad_mask2,
    output wire [`GP_P-1:0]                 quad_mask3,
    input  wire [`GP_INDEX_W-1:0]           verify_index,
    output wire                              verify_found,
    input  wire                              clear_start,
    input  wire                              set_start,
    input  wire [`GP_INDEX_W-1:0]           set_index,
    output wire                              maint_busy,
    output reg                               clear_done,
    output reg                               set_done
);
    localparam integer ROW_W=`GP_ROW_W;
    localparam integer LOGP=`GP_LOGP;
    localparam integer P=`GP_P;
    localparam [2:0] M_IDLE=3'd0,M_CLEAR=3'd1,M_SET_READ=3'd2,M_SET_WRITE=3'd3;

    (* ram_style = "block" *) reg [P-1:0] mem0 [0:255];
    (* ram_style = "block" *) reg [P-1:0] mem1 [0:255];
    reg [P-1:0] q0a,q0b,q1a,q1b;
    reg [2:0] maint_st;
    reg [7:0] clear_addr;
    reg set_bank_r;
    reg [7:0] set_addr_r;
    reg [LOGP-1:0] set_lane_r;

    wire [ROW_W-1:0] verify_grow=verify_index[`GP_INDEX_W-1:LOGP];
    wire verify_bank=verify_grow[1];
    wire [7:0] verify_addr={verify_grow[ROW_W-1:2],verify_grow[0]};
    wire [LOGP-1:0] verify_lane=verify_index[LOGP-1:0];

    // 200 MHz: quad read and verify requests pass two registers before the
    // BRAM address muxes, matching grover_data_mem_e4's two-level tree (quad
    // masks arrive on the same edge as the quad data).  Maintenance keeps its
    // own registered addresses and its read-modify-write timing is unchanged.
    // The verify bit is registered after the lane select and is valid four
    // cycles after the index; grover_verify samples later than that.
    reg       rd_en_a, rd_en_r;
    reg [6:0] rd_index_a, rd_index_r;
    reg [7:0] verify_addr_a, verify_addr_r;
    reg       verify_found_r;
    always @(posedge clk) begin
        rd_en_a       <= quad_rd_en;    rd_en_r       <= rd_en_a;
        rd_index_a    <= quad_rd_index; rd_index_r    <= rd_index_a;
        verify_addr_a <= verify_addr;   verify_addr_r <= verify_addr_a;
    end
    wire [7:0] qaddr0={rd_index_r,1'b0};
    wire [7:0] qaddr1={rd_index_r,1'b1};

    wire b_clear=(maint_st==M_CLEAR);
    wire b_set_read=(maint_st==M_SET_READ);
    wire b_set_write=(maint_st==M_SET_WRITE);
    wire [P-1:0] set_onehot=({{(P-1){1'b0}},1'b1}<<set_lane_r);

    // Port A is dedicated to the first row of each E4 bank during compute.
    always @(posedge clk) begin
        if(rd_en_r) begin q0a<=mem0[qaddr0]; q1a<=mem1[qaddr0]; end
    end

    // Port B handles second E4 rows or maintenance/verify outside compute.
    wire [7:0] baddr0=b_clear?clear_addr:
                       ((b_set_read||b_set_write)&&!set_bank_r)?set_addr_r:
                       rd_en_r?qaddr1:verify_addr_r;
    wire [7:0] baddr1=b_clear?clear_addr:
                       ((b_set_read||b_set_write)&& set_bank_r)?set_addr_r:
                       rd_en_r?qaddr1:verify_addr_r;
    wire we0=b_clear||(b_set_write&&!set_bank_r);
    wire we1=b_clear||(b_set_write&& set_bank_r);
    wire [P-1:0] wd0=b_clear?{P{1'b0}}:(q0b|set_onehot);
    wire [P-1:0] wd1=b_clear?{P{1'b0}}:(q1b|set_onehot);

    reg verify_bank_d1, verify_bank_d2, verify_bank_d3;
    reg [LOGP-1:0] verify_lane_d1, verify_lane_d2, verify_lane_d3;
    always @(posedge clk) begin
        if(we0) mem0[baddr0]<=wd0;
        if(we1) mem1[baddr1]<=wd1;
        q0b<=mem0[baddr0]; q1b<=mem1[baddr1];
        verify_bank_d1<=verify_bank;    verify_lane_d1<=verify_lane;
        verify_bank_d2<=verify_bank_d1; verify_lane_d2<=verify_lane_d1;
        verify_bank_d3<=verify_bank_d2; verify_lane_d3<=verify_lane_d2;
        verify_found_r<=verify_bank_d3?q1b[verify_lane_d3]:q0b[verify_lane_d3];
    end

    assign quad_mask0=q0a; assign quad_mask1=q0b;
    assign quad_mask2=q1a; assign quad_mask3=q1b;
    assign verify_found=verify_found_r;
    assign maint_busy=(maint_st!=M_IDLE);

    wire [ROW_W-1:0] set_grow=set_index[`GP_INDEX_W-1:LOGP];
    always @(posedge clk) begin
        if(!rstn) begin
            maint_st<=M_IDLE; clear_addr<=0; set_bank_r<=0; set_addr_r<=0; set_lane_r<=0;
            clear_done<=0; set_done<=0;
        end else begin
            clear_done<=0; set_done<=0;
            case(maint_st)
                M_IDLE: begin
                    if(clear_start) begin clear_addr<=0; maint_st<=M_CLEAR; end
                    else if(set_start) begin
                        set_bank_r<=set_grow[1];
                        set_addr_r<={set_grow[ROW_W-1:2],set_grow[0]};
                        set_lane_r<=set_index[LOGP-1:0];
                        maint_st<=M_SET_READ;
                    end
                end
                M_CLEAR: begin
                    if(clear_addr==8'hff) begin clear_done<=1; maint_st<=M_IDLE; end
                    else clear_addr<=clear_addr+1'b1;
                end
                M_SET_READ: maint_st<=M_SET_WRITE;
                M_SET_WRITE: begin set_done<=1; maint_st<=M_IDLE; end
                default: maint_st<=M_IDLE;
            endcase
        end
    end
endmodule
