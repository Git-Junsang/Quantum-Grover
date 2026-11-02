//==============================================================================
// grover_dram_amp_store.v -- hardware_dram branch, per-iteration full-history
// amplitude store/restore engine.
//
// This is the module that replaces grover_checkpoint.v's K3/K4 planner and
// executor. It does not decide WHICH j to visit -- that is grover_dram_shot_
// fsm.v's job, driven by the unmodified grover_bbht_random draw stream. This
// module only knows how to do two things against the abstract DRAM burst
// port defined below:
//
//   STORE   : read back a caller-supplied amp_mem-shaped buffer (512 rows of
//             736 bits, 1-cycle synchronous read latency, same contract as
//             grover_amp_mem) and stream it out as one burst tagged with
//             iteration index store_j. Used once after every completed
//             Grover iteration while the search is growing -- this is the
//             literal RTL form of "이터레이션이 끝날 때마다 진폭값을 DRAM에
//             저장".
//   RESTORE : burst-read the slot for iteration restore_j back in, and
//             stream it into a caller-supplied amp_mem-shaped write port.
//             Used whenever a drawn candidate j is behind the current growth
//             frontier, replacing checkpoint replay with one direct fetch.
//
// Store and restore are independent sub-FSMs; grover_dram_shot_fsm.v is
// responsible for never running both at once against the same physical
// buffer (they don't share a buffer here -- STORE reads the grow buffer,
// RESTORE writes the fetch buffer -- but the abstract DRAM port itself is
// single-ported, so the two bursts are still serialized by the caller).
//
// Abstract DRAM burst port
//   One beat = one packed 736-bit amplitude row (`GD_ROW_BYTES = 92 bytes).
//   A burst is always exactly `GD_BURST_LEN (=GP_ROWS=512) beats, i.e. one
//   full iteration slot. This is deliberately NOT AXI4 and NOT MIG native UI
//   -- physical DRAM binding is still undecided (CLAUDE.md section 3). A
//   future bridge sits between dram_wr_*/dram_rd_* and whatever the real
//   controller interface turns out to be; it only needs to width-convert and
//   pack/unpack this row-granular stream, not change anything upstream.
//==============================================================================
`timescale 1ns/1ps
`include "grover_dram_param.vh"

module grover_dram_amp_store (
    input  wire                              clk,
    input  wire                              rstn,

    //--------------------------------------------------------------------
    // STORE: snapshot the current grow buffer to DRAM as iteration store_j.
    //--------------------------------------------------------------------
    input  wire                              store_start,
    input  wire [`GP_J_W-1:0]                store_j,
    output wire                              store_busy,
    output reg                               store_done,

    // Drive into the grow buffer's read port (grover_amp_mem contract).
    output wire [`GP_ROW_W-1:0]              store_rd_row,
    output wire                              store_rd_en,
    input  wire [`GP_P*`GP_AMP_W-1:0]        store_rd_data,

    //--------------------------------------------------------------------
    // RESTORE: fetch iteration restore_j from DRAM into the fetch buffer.
    //--------------------------------------------------------------------
    input  wire                              restore_start,
    input  wire [`GP_J_W-1:0]                restore_j,
    output wire                              restore_busy,
    output reg                               restore_done,

    // Drive into the fetch buffer's write port (grover_amp_mem contract).
    output wire [`GP_ROW_W-1:0]              restore_wr_row,
    output wire                              restore_wr_en,
    output wire [`GP_P*`GP_AMP_W-1:0]        restore_wr_data,

    //--------------------------------------------------------------------
    // Abstract DRAM write burst (store side).
    //--------------------------------------------------------------------
    output reg                               dram_wr_req,
    output reg  [`GD_ADDR_W-1:0]             dram_wr_addr,
    output wire [`GD_BURST_LEN_W-1:0]        dram_wr_len,
    output wire                              dram_wr_valid,
    output wire [`GP_P*`GP_AMP_W-1:0]        dram_wr_data,
    output wire                              dram_wr_last,
    input  wire                              dram_wr_ready,

    //--------------------------------------------------------------------
    // Abstract DRAM read burst (restore side).
    //--------------------------------------------------------------------
    output reg                               dram_rd_req,
    output reg  [`GD_ADDR_W-1:0]             dram_rd_addr,
    output wire [`GD_BURST_LEN_W-1:0]        dram_rd_len,
    input  wire                              dram_rd_valid,
    input  wire [`GP_P*`GP_AMP_W-1:0]        dram_rd_data,
    output wire                              dram_rd_ready,
    input  wire                              dram_rd_last
);
    localparam integer ROWS  = `GP_ROWS;
    localparam integer ROW_W = `GP_ROW_W;
    localparam [ROW_W-1:0] ROW_LAST = ROWS - 1;

    assign dram_wr_len = {{(`GD_BURST_LEN_W-ROW_W){1'b0}}, ROW_LAST};
    assign dram_rd_len = {{(`GD_BURST_LEN_W-ROW_W){1'b0}}, ROW_LAST};

    //==========================================================================
    // STORE sub-FSM -- one row per cycle.
    //
    // The earlier draft walked S_REQ -> S_SEND(valid rises) -> S_SEND(transfer)
    // per row, which cost three cycles for every one of the 512 beats. Measured
    // on tb_dram_core C1 that was 1546 cycles per slot: a full Grover iteration
    // is about 1550 cycles, so snapshotting an iteration cost as much as
    // computing one. That is an implementation artifact, not something the
    // full-history scheme requires, so this version streams the burst.
    //
    // The pipeline is two deep and needs no skid buffer, because grover_amp_mem
    // is the buffer: its rd_q only changes on rd_en, so withholding rd_en holds
    // the beat in flight indefinitely.
    //
    //   issue      assert rd_en for ss_rd_ptr. Data lands in rd_q next cycle.
    //   ss_valid_q rd_q currently holds a beat that has not been accepted.
    //   ss_row_q   which row that beat is (only needed for dram_wr_last).
    //
    // The one rule that makes it correct: issue only when rd_q may legally be
    // overwritten next cycle, i.e. when it is empty or its beat is being
    // accepted this very cycle (ss_can_issue). Under backpressure that stops
    // the reads, the amp_mem output freezes, and the held beat is retried
    // unchanged -- same guarantee the three-cycle version got by sitting still.
    //
    // Steady state with dram_wr_ready high is one beat per cycle, so a slot is
    // 512 beats + 2 cycles of pipeline fill instead of 1536.
    //==========================================================================
    localparam [0:0] SS_IDLE = 1'd0, SS_RUN = 1'd1;

    reg              ss_st;
    reg [ROW_W-1:0]  ss_rd_ptr;    // next row to request from amp_mem
    reg [ROW_W-1:0]  ss_row_q;     // row currently sitting in amp_mem's rd_q
    reg              ss_valid_q;   // that beat has not been accepted yet
    reg              ss_rd_done;   // all 512 read requests have been issued

    // This cycle's beat is being accepted.
    wire ss_beat_go   = ss_valid_q && dram_wr_ready;
    // rd_q may be overwritten on the next edge.
    wire ss_can_issue = !ss_valid_q || dram_wr_ready;
    wire ss_issue     = (ss_st == SS_RUN) && !ss_rd_done && ss_can_issue;

    assign store_busy   = (ss_st != SS_IDLE);
    assign store_rd_row = ss_rd_ptr;
    assign store_rd_en  = ss_issue;

    assign dram_wr_data  = store_rd_data;
    assign dram_wr_valid = ss_valid_q;
    assign dram_wr_last  = ss_valid_q && (ss_row_q == ROW_LAST);

    always @(posedge clk) begin
        if (!rstn) begin
            ss_st        <= SS_IDLE;
            ss_rd_ptr    <= {ROW_W{1'b0}};
            ss_row_q     <= {ROW_W{1'b0}};
            ss_valid_q   <= 1'b0;
            ss_rd_done   <= 1'b0;
            store_done   <= 1'b0;
            dram_wr_req  <= 1'b0;
            dram_wr_addr <= {`GD_ADDR_W{1'b0}};
        end else begin
            store_done  <= 1'b0;
            dram_wr_req <= 1'b0;

            case (ss_st)
                SS_IDLE: begin
                    ss_valid_q <= 1'b0;
                    if (store_start) begin
                        ss_rd_ptr    <= {ROW_W{1'b0}};
                        ss_row_q     <= {ROW_W{1'b0}};
                        ss_rd_done   <= 1'b0;
                        dram_wr_req  <= 1'b1;
                        dram_wr_addr <= `GD_AMP_BASE +
                            ({{(`GD_ADDR_W-`GP_J_W){1'b0}}, store_j} * `GD_ITER_STRIDE);
                        ss_st        <= SS_RUN;
                    end
                end

                SS_RUN: begin
                    if (ss_issue) begin
                        ss_row_q <= ss_rd_ptr;
                        if (ss_rd_ptr == ROW_LAST)
                            ss_rd_done <= 1'b1;
                        else
                            ss_rd_ptr <= ss_rd_ptr + 1'b1;
                    end

                    // Next cycle holds a beat if one was just requested, or if
                    // the current one is still waiting for ready. The two are
                    // mutually exclusive by ss_can_issue.
                    ss_valid_q <= ss_issue || (ss_valid_q && !dram_wr_ready);

                    if (ss_beat_go && (ss_row_q == ROW_LAST)) begin
                        ss_valid_q <= 1'b0;
                        store_done <= 1'b1;
                        ss_st      <= SS_IDLE;
                    end
                end

                default: ss_st <= SS_IDLE;
            endcase
        end
    end

    //==========================================================================
    // RESTORE sub-FSM.
    //
    //   S_IDLE -> pulse dram_rd_req, always-ready streaming write into the
    //   fetch buffer as beats arrive. dram_rd_last from the (future) bridge
    //   is cross-checked against the local row counter as a sanity guard
    //   only; the local counter is authoritative for restore_wr_row.
    //==========================================================================
    localparam [0:0] RS_IDLE = 1'd0, RS_RUN = 1'd1;

    reg               rs_st;
    reg [ROW_W-1:0]   rs_row;

    assign restore_busy    = (rs_st != RS_IDLE);
    assign dram_rd_ready   = (rs_st == RS_RUN);
    assign restore_wr_en   = (rs_st == RS_RUN) && dram_rd_valid;
    assign restore_wr_row  = rs_row;
    assign restore_wr_data = dram_rd_data;

    always @(posedge clk) begin
        if (!rstn) begin
            rs_st          <= RS_IDLE;
            rs_row         <= {ROW_W{1'b0}};
            restore_done   <= 1'b0;
            dram_rd_req    <= 1'b0;
            dram_rd_addr   <= {`GD_ADDR_W{1'b0}};
        end else begin
            restore_done <= 1'b0;
            dram_rd_req  <= 1'b0;

            case (rs_st)
                RS_IDLE: begin
                    if (restore_start) begin
                        rs_row       <= {ROW_W{1'b0}};
                        dram_rd_req  <= 1'b1;
                        dram_rd_addr <= `GD_AMP_BASE +
                            ({{(`GD_ADDR_W-`GP_J_W){1'b0}}, restore_j} * `GD_ITER_STRIDE);
                        rs_st        <= RS_RUN;
                    end
                end

                RS_RUN: begin
                    if (dram_rd_valid) begin
                        if (rs_row == ROW_LAST) begin
                            restore_done <= 1'b1;
                            rs_st        <= RS_IDLE;
                        end else begin
                            rs_row <= rs_row + 1'b1;
                        end
                    end
                end

                default: rs_st <= RS_IDLE;
            endcase
        end
    end

    // dram_rd_last is reserved for a future bridge-side sanity cross-check
    // (see RESTORE header comment) and is not consumed by this draft's local
    // row counter.
    wire _unused_dram_rd_last = dram_rd_last;

endmodule
