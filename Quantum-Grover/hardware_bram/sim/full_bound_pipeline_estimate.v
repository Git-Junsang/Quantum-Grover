// Resource-estimation microkernel only; this is not wired into production RTL.
// It implements the capacity-relaxed full-horizon lower bound at one candidate
// per clock, with one registered request step per pipeline stage.
module full_bound_stage_estimate #(
    parameter integer U = 14
) (
    input  wire                 clk,
    input  wire                 valid_i,
    input  wire [U-1:0]         original_mask_i,
    input  wire [U-1:0]         relaxed_mask_i,
    input  wire [10:0]          cost_i,
    input  wire [U*7-1:0]       universe_flat,
    input  wire [U-1:0]         pool_mask,
    input  wire [6:0]           request_i,
    output reg                  valid_o,
    output reg  [U-1:0]         original_mask_o,
    output reg  [U-1:0]         relaxed_mask_o,
    output reg  [10:0]          cost_o
);
    integer p;
    reg [6:0] source_c;
    reg [6:0] value_c;
    reg [U-1:0] next_mask_c;

    always @* begin
        source_c = 7'd0;
        for (p = 0; p < U; p = p + 1) begin
            value_c = universe_flat[p*7 +: 7];
            if (relaxed_mask_i[p] && (value_c <= request_i) &&
                (value_c > source_c))
                source_c = value_c;
        end

        next_mask_c = relaxed_mask_i;
        for (p = 0; p < U; p = p + 1) begin
            value_c = universe_flat[p*7 +: 7];
            if ((value_c == request_i) ||
                (pool_mask[p] && (source_c < value_c) &&
                 (value_c < request_i)))
                next_mask_c[p] = 1'b1;
        end
    end

    always @(posedge clk) begin
        valid_o         <= valid_i;
        original_mask_o <= original_mask_i;
        relaxed_mask_o  <= next_mask_c;
        cost_o          <= cost_i + request_i - source_c;
    end
endmodule

module full_bound_pipeline_estimate #(
    parameter integer K = 5,
    parameter integer H = 8,
    parameter integer U = K + H + 1
) (
    input  wire                 clk,
    input  wire                 valid_i,
    input  wire [U-1:0]         candidate_mask_i,
    input  wire [U*7-1:0]       universe_flat,
    input  wire [U-1:0]         pool_mask,
    input  wire [H*7-1:0]       request_flat,
    output wire                 valid_o,
    output wire [U-1:0]         candidate_mask_o,
    output wire [10:0]          bound_o
);
    wire [U-1:0] original_pipe [0:H];
    wire [U-1:0] relaxed_pipe [0:H];
    wire [10:0] cost_pipe [0:H];
    wire valid_pipe [0:H];

    assign original_pipe[0] = candidate_mask_i;
    assign relaxed_pipe[0]  = candidate_mask_i;
    assign cost_pipe[0]     = 11'd0;
    assign valid_pipe[0]    = valid_i;

    genvar g;
    generate
        for (g = 0; g < H; g = g + 1) begin : g_stage
            full_bound_stage_estimate #(.U(U)) u_stage (
                .clk(clk),
                .valid_i(valid_pipe[g]),
                .original_mask_i(original_pipe[g]),
                .relaxed_mask_i(relaxed_pipe[g]),
                .cost_i(cost_pipe[g]),
                .universe_flat(universe_flat),
                .pool_mask(pool_mask),
                .request_i(request_flat[g*7 +: 7]),
                .valid_o(valid_pipe[g+1]),
                .original_mask_o(original_pipe[g+1]),
                .relaxed_mask_o(relaxed_pipe[g+1]),
                .cost_o(cost_pipe[g+1])
            );
        end
    endgenerate

    assign valid_o          = valid_pipe[H];
    assign candidate_mask_o = original_pipe[H];
    assign bound_o          = cost_pipe[H];
endmodule
