//==============================================================================
// grover_loader.v -- LPSoC BBHT/Grover Main IP v0.6 consolidated RTL
//
// File-level consolidation only: verified module boundaries and logic are
// preserved. No new wrapper hierarchy is introduced by this merge.
// Consolidated from: grover_loader_ctrl.v
//==============================================================================


//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_loader_ctrl.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_loader_ctrl.v -- LPSoC BBHT/Grover Main IP v0.6, Step 8
//
// Generic Main-IP dataset loader control/validation.
//
// v0.6 contract
//   accepted_load_start = load_start && !search_busy && !load_busy
//   - accepted start latches data_count as expected_count
//   - data_valid=0, load_error=0, write_count=0 at accepted start
//   - only in-range writes (addr < expected_count) are forwarded/count
//   - write_count saturates at expected_count
//   - load_done is honored only while load_busy
//   - same-cycle final valid write + load_done is included via next_count
//   - insufficient count => sticky load_error=1, data_valid=0
//   - successful validation => data_valid=1
//   - changing data_count after a valid load invalidates data_valid/cache
//
// This is deliberately NOT an AHB/AXI/DMA engine.  Bus-level hresp/load_err
// propagation remains an E2E integration item in v0.6.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_loader_ctrl (
    input  wire                              clk,
    input  wire                              rstn,

    // Main-IP load request and search/load interlock.
    input  wire                              load_start,
    input  wire                              search_busy,
    input  wire [`GP_DATA_COUNT_W-1:0]       data_count,

    // Generic one-item loader stream from outside the Main IP.
    input  wire                              data_wr_en,
    input  wire [`GP_INDEX_W-1:0]            data_wr_addr,
    input  wire signed [`GP_DATA_W-1:0]       data_wr_data,
    input  wire                              load_done,

    // Validated data_mem Port-B write stream.
    output wire                              mem_wr_en,
    output wire [`GP_INDEX_W-1:0]            mem_wr_addr,
    output wire signed [`GP_DATA_W-1:0]       mem_wr_data,

    // Load/session state.
    output reg                               load_busy,
    output reg                               data_valid,
    output reg                               load_error,

    // Integration hooks.
    output wire                              accepted_load_start,
    output wire                              cache_invalidate,

    // Debug / Golden-trace observability.
    output reg  [`GP_DATA_COUNT_W-1:0]       expected_count,
    output reg  [`GP_DATA_COUNT_W-1:0]       write_count,
    output reg  [`GP_DATA_COUNT_W-1:0]       loaded_count
);
    localparam integer N = `GP_N;

    wire expected_count_valid;
    wire addr_in_range;
    wire valid_write;
    wire [`GP_DATA_COUNT_W-1:0] write_count_next;
    wire data_count_mismatch;
    wire load_success_now;

    assign accepted_load_start = load_start && !search_busy && !load_busy;

    // A loaded dataset is semantically tied to the data_count used for that
    // successful load.  Any later change requires a new dataset load.
    assign data_count_mismatch = data_valid && (data_count != loaded_count);

    // Dataset/cache semantics change immediately on either event.
    assign cache_invalidate = accepted_load_start || data_count_mismatch;

    assign expected_count_valid = (expected_count != {`GP_DATA_COUNT_W{1'b0}}) &&
                                  (expected_count <= N);

    // Zero-extend the physical 14-bit address before comparing with the
    // 15-bit count.  For expected_count==16384, every 14-bit address is valid.
    assign addr_in_range = ({1'b0, data_wr_addr} < expected_count);

    assign valid_write = load_busy && expected_count_valid &&
                         data_wr_en && addr_in_range;

    // Lower-bound validation only: duplicate addresses still count.  Saturate
    // exactly at expected_count so extra accepted writes cannot overflow.
    assign write_count_next = (valid_write && (write_count < expected_count))
                            ? (write_count + {{(`GP_DATA_COUNT_W-1){1'b0}}, 1'b1})
                            : write_count;

    // Requiring the live count to still match the session latch prevents a
    // one-cycle data_valid window if software changes data_count during load.
    assign load_success_now = expected_count_valid &&
                              (write_count_next >= expected_count) &&
                              (data_count == expected_count);

    assign mem_wr_en   = valid_write;
    assign mem_wr_addr = data_wr_addr;
    assign mem_wr_data = data_wr_data;

    always @(posedge clk) begin
        if (!rstn) begin
            load_busy      <= 1'b0;
            data_valid     <= 1'b0;
            load_error     <= 1'b0;
            expected_count <= {`GP_DATA_COUNT_W{1'b0}};
            write_count    <= {`GP_DATA_COUNT_W{1'b0}};
            loaded_count   <= {`GP_DATA_COUNT_W{1'b0}};
        end else begin
            // A successfully loaded dataset becomes invalid as soon as the
            // externally visible data_count no longer describes it.
            if (data_count_mismatch)
                data_valid <= 1'b0;

            // Busy/search interlock: requests not accepted here cause no state
            // clear, no count relatch, and no cache invalidation.
            if (accepted_load_start) begin
                load_busy      <= 1'b1;
                data_valid     <= 1'b0;
                load_error     <= 1'b0;
                expected_count <= data_count;
                write_count    <= {`GP_DATA_COUNT_W{1'b0}};
            end else if (load_busy) begin
                write_count <= write_count_next;

                // load_done outside load_busy is intentionally ignored.
                if (load_done) begin
                    load_busy <= 1'b0;
                    if (load_success_now) begin
                        data_valid   <= 1'b1;
                        load_error   <= 1'b0;
                        loaded_count <= expected_count;
                    end else begin
                        data_valid <= 1'b0;
                        load_error <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_loader_ctrl.v
//------------------------------------------------------------------------------
