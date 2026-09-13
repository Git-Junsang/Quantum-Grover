`timescale 1ns/1ps

module bbht_ahb_loader #(
    parameter [31:0] SRC_BASE = 32'hE000_0000,
    parameter [31:0] SRC_LAST = 32'hE001_FFFF
) (
    input  wire               clk,
    input  wire               rstnn,

    input  wire [31:0]        src_addr,
    input  wire [14:0]        data_count,
    input  wire               dma_start,
    output wire               dma_busy,
    output wire               dma_error,
    output wire [4:0]         dma_error_bits,

    output wire               load_start,
    output wire               data_wr_en,
    output wire [13:0]        data_wr_addr,
    output wire signed [15:0] data_wr_data,
    output wire               load_done,
    input  wire               load_busy,
    input  wire               main_busy,

    input  wire               shready,
    output wire [31:0]        shaddr,
    output wire [2:0]         shburst,
    output wire               shmasterlock,
    output wire [3:0]         shprot,
    output wire [2:0]         shsize,
    output wire [1:0]         shtrans,
    output wire               shwrite,
    output wire [31:0]        shwdata,
    input  wire [31:0]        shrdata,
    input  wire               shresp
);

    localparam [1:0] TRANS_IDLE   = 2'b00;
    localparam [1:0] TRANS_NONSEQ = 2'b10;
    localparam [2:0] SIZE_4BYTE   = 3'b010;
    localparam [2:0] BURST_SINGLE = 3'b000;

    localparam [14:0] COUNT_MAX = 15'd16384;

    localparam [2:0] S_IDLE      = 3'd0,
                     S_WAIT_BUSY = 3'd1,
                     S_ADDR      = 3'd2,
                     S_DATA      = 3'd3,
                     S_WLO       = 3'd4,
                     S_WHI       = 3'd5,
                     S_FIN       = 3'd6;

    reg [2:0]  st;
    reg [31:0] addr_q;
    reg [14:0] n_q;
    reg [14:0] cnt_q;
    reg [31:0] rdata_q;

    reg        ld_start_q;
    reg        ld_done_q;
    reg        wr_en_q;
    reg [13:0] wr_addr_q;
    reg signed [15:0] wr_data_q;

    reg        e_align;
    reg        e_count;
    reg        e_resp;
    reg        e_busy;
    reg        e_range;

    wire [14:0] cnt_next = cnt_q + 15'd1;
    wire        is_last  = (cnt_next == n_q);

    wire align_bad = (src_addr[1:0] != 2'b00);

    wire count_bad =
        (data_count == 15'd0) ||
        (data_count > COUNT_MAX);

    wire [15:0] word_count =
        ({1'b0, data_count} + 16'd1) >> 1;

    wire [32:0] first_byte = {1'b0, src_addr};
    wire [32:0] span_byte  = {15'd0, word_count, 2'b00};
    wire [32:0] last_byte  =
        first_byte + span_byte - 33'd1;

    wire range_bad =
        (~count_bad) &&
        (
            (first_byte < {1'b0, SRC_BASE}) ||
            (last_byte  > {1'b0, SRC_LAST})
        );

    wire req_bad =
        align_bad |
        count_bad |
        range_bad;

    wire loader_idle =
        (st == S_IDLE) &&
        (~ld_done_q);

    assign shwrite      = 1'b0;
    assign shwdata      = 32'd0;
    assign shsize       = SIZE_4BYTE;
    assign shburst      = BURST_SINGLE;
    assign shmasterlock = 1'b0;
    assign shprot       = 4'b0011;
    assign shaddr       = addr_q;

    assign shtrans =
        (st == S_ADDR)
        ? TRANS_NONSEQ
        : TRANS_IDLE;

    assign dma_busy = ~loader_idle;

    assign dma_error_bits = {
        e_range,
        e_busy,
        e_resp,
        e_count,
        e_align
    };

    assign dma_error = |dma_error_bits;

    assign load_start   = ld_start_q;
    assign load_done    = ld_done_q;
    assign data_wr_en   = wr_en_q;
    assign data_wr_addr = wr_addr_q;
    assign data_wr_data = wr_data_q;

    always @(posedge clk) begin
        if (!rstnn) begin
            st         <= S_IDLE;
            addr_q     <= 32'd0;
            n_q        <= 15'd0;
            cnt_q      <= 15'd0;
            rdata_q    <= 32'd0;

            ld_start_q <= 1'b0;
            ld_done_q  <= 1'b0;

            wr_en_q    <= 1'b0;
            wr_addr_q  <= 14'd0;
            wr_data_q  <= 16'sd0;

            e_align    <= 1'b0;
            e_count    <= 1'b0;
            e_resp     <= 1'b0;
            e_busy     <= 1'b0;
            e_range    <= 1'b0;
        end
        else begin
            ld_start_q <= 1'b0;
            ld_done_q  <= 1'b0;
            wr_en_q    <= 1'b0;

            if (dma_start) begin
                if ((~loader_idle) || main_busy) begin
                    e_busy <= 1'b1;
                end
                else if (req_bad) begin
                    if (align_bad)
                        e_align <= 1'b1;

                    if (count_bad)
                        e_count <= 1'b1;

                    if (range_bad)
                        e_range <= 1'b1;
                end
                else begin
                    e_align    <= 1'b0;
                    e_count    <= 1'b0;
                    e_resp     <= 1'b0;
                    e_busy     <= 1'b0;
                    e_range    <= 1'b0;

                    addr_q     <= src_addr;
                    n_q        <= data_count;
                    cnt_q      <= 15'd0;

                    ld_start_q <= 1'b1;
                    st         <= S_WAIT_BUSY;
                end
            end

            case (st)

                S_IDLE: begin
                end

                S_WAIT_BUSY: begin
                    if (load_busy)
                        st <= S_ADDR;
                end

                S_ADDR: begin
                    if (shready)
                        st <= S_DATA;
                end

                S_DATA: begin
                    if (shready) begin
                        if (shresp) begin
                            e_resp    <= 1'b1;
                            ld_done_q <= 1'b1;
                            st        <= S_IDLE;
                        end
                        else begin
                            rdata_q <= shrdata;
                            st      <= S_WLO;
                        end
                    end
                end

                S_WLO: begin
                    wr_en_q   <= 1'b1;
                    wr_addr_q <= cnt_q[13:0];
                    wr_data_q <= rdata_q[15:0];

                    cnt_q     <= cnt_next;
                    addr_q    <= addr_q + 32'd4;

                    st <= is_last
                        ? S_FIN
                        : S_WHI;
                end

                S_WHI: begin
                    wr_en_q   <= 1'b1;
                    wr_addr_q <= cnt_q[13:0];
                    wr_data_q <= rdata_q[31:16];

                    cnt_q <= cnt_next;

                    st <= is_last
                        ? S_FIN
                        : S_ADDR;
                end

                S_FIN: begin
                    ld_done_q <= 1'b1;
                    st        <= S_IDLE;
                end

                default: begin
                    st <= S_IDLE;
                end

            endcase
        end
    end

endmodule
