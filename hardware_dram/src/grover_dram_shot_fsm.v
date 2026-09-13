//==============================================================================
// grover_dram_shot_fsm.v -- hardware_dram branch, outer BBHT shot controller.
//
// Structurally this is grover_bbht_shot_fsm.v (hardware_bram) with the
// cache-checkpoint step (grover_cache_ctrl + direct grover_ctrl_fsm call)
// replaced by one call into grover_dram_prep_seq.v. Everything about the
// BBHT algorithm itself -- random j draw via the m_bound ROM/LFSR, shot_cap
// and BBHT-budget termination, success/config/zero-weight priority -- is
// unchanged from the reference so this branch stays bit-exact against the
// same golden model as hardware_bram for a single-target search.
//
// v1 scope: single-target search only (MANUAL_SINGLE / NORMAL_SINGLE).
// Enumeration (multi-target, found-mask, result-stream) is not wired here;
// see lpsoc_bbht_grover_main_ip.v's top comment for why that is deferred.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_dram_shot_fsm (
    input  wire                         clk,
    input  wire                         rstn,

    input  wire                         start,
    input  wire                         config_ok,
    input  wire                         auto_shot,
    input  wire [`GP_J_W-1:0]          j_target,
    input  wire [`GP_SHOT_CAP_W-1:0]   shot_cap,
    input  wire [31:0]                  seed_j,
    input  wire                         seed_reload,

    // grover_dram_prep_seq.v interface.
    output reg                          prep_start,
    output wire [`GP_J_W-1:0]          prep_target_j,
    input  wire                         prep_done,

    // grover_measure_verify interface.
    output reg                          meas_start,
    input  wire                         meas_done,
    input  wire                         meas_verify_hit,
    input  wire                         meas_zero_weight_error,
    input  wire [`GP_INDEX_W-1:0]       meas_candidate,

    output reg                          busy,
    output reg                          done,

    output reg                          term_success,
    output reg                          term_config_error,
    output reg                          term_shot_limit,
    output reg                          term_budget_limit,
    output reg                          term_zero_weight_error,
    output reg  [`GP_INDEX_W-1:0]       success_index,

    output reg  [`GP_RROM_IDX_W-1:0]   round_idx,
    output wire [7:0]                   current_m_bound,
    output reg  [`GP_J_W-1:0]          current_j,
    output reg  [31:0]                  trial_count,
    output reg  [31:0]                  L_BBHT,
    output wire                         j_rnd_draw,
    output wire [31:0]                  j_rnd_state
);
    localparam [3:0]
        S_IDLE       = 4'd0,
        S_CONFIG     = 4'd1,
        S_SHOT_PREP  = 4'd2,
        S_DRAW_WAIT  = 4'd3,
        S_PREP_REQ   = 4'd4,
        S_PREP_WAIT  = 4'd5,
        S_MEAS_REQ   = 4'd6,
        S_MEAS_WAIT  = 4'd7,
        S_LIMIT      = 4'd8,
        S_FIN        = 4'd9;

    localparam [2:0]
        R_NONE        = 3'd0,
        R_SUCCESS     = 3'd1,
        R_CONFIG      = 3'd2,
        R_SHOT_LIMIT  = 3'd3,
        R_BUDGET      = 3'd4,
        R_ZERO_WEIGHT = 3'd5,
        R_MANUAL_FAIL = 3'd6;

    reg [3:0] st;
    reg [2:0] finish_reason;
    reg [`GP_J_W-1:0] j_req_r;
    reg random_request;

    wire random_busy;
    wire random_done;
    wire [`GP_J_W-1:0] random_j;
    wire rom_last;

    wire random_seed_we = seed_reload;

    assign prep_target_j = j_req_r;

    grover_bbht_random u_bbht_random (
        .clk       (clk),
        .rstn      (rstn),
        .seed_we   (random_seed_we),
        .seed      (seed_j),
        .request   (random_request),
        .round_idx (round_idx),
        .busy      (random_busy),
        .done      (random_done),
        .j_req     (random_j),
        .m_bound   (current_m_bound),
        .rnd_draw  (j_rnd_draw),
        .rnd_state (j_rnd_state),
        .rom_last  (rom_last)
    );

    wire shot_hit;
    wire budget_hit;
    assign shot_hit   = (trial_count >= {{(32-`GP_SHOT_CAP_W){1'b0}}, shot_cap});
    assign budget_hit = ((L_BBHT + 32'd1) >= `GP_BBHT_BUDGET);

    always @(posedge clk) begin
        if (!rstn) begin
            st                     <= S_IDLE;
            finish_reason          <= R_NONE;
            j_req_r                <= {`GP_J_W{1'b0}};
            random_request         <= 1'b0;
            prep_start              <= 1'b0;
            meas_start              <= 1'b0;
            busy                    <= 1'b0;
            done                    <= 1'b0;
            term_success            <= 1'b0;
            term_config_error       <= 1'b0;
            term_shot_limit         <= 1'b0;
            term_budget_limit       <= 1'b0;
            term_zero_weight_error  <= 1'b0;
            success_index           <= {`GP_INDEX_W{1'b0}};
            round_idx               <= {`GP_RROM_IDX_W{1'b0}};
            current_j               <= {`GP_J_W{1'b0}};
            trial_count              <= 32'd0;
            L_BBHT                   <= 32'd0;
        end else begin
            random_request          <= 1'b0;
            prep_start               <= 1'b0;
            meas_start               <= 1'b0;
            done                     <= 1'b0;
            term_success             <= 1'b0;
            term_config_error        <= 1'b0;
            term_shot_limit          <= 1'b0;
            term_budget_limit        <= 1'b0;
            term_zero_weight_error   <= 1'b0;

            case (st)
                S_IDLE: begin
                    if (start) begin
                        busy          <= 1'b1;
                        finish_reason <= R_NONE;
                        round_idx     <= {`GP_RROM_IDX_W{1'b0}};
                        current_j     <= {`GP_J_W{1'b0}};
                        trial_count   <= 32'd0;
                        L_BBHT        <= 32'd0;
                        success_index <= {`GP_INDEX_W{1'b0}};
                        st            <= S_CONFIG;
                    end
                end

                S_CONFIG: begin
                    if (!config_ok || (shot_cap == {`GP_SHOT_CAP_W{1'b0}})) begin
                        finish_reason <= R_CONFIG;
                        st            <= S_FIN;
                    end else begin
                        st <= S_SHOT_PREP;
                    end
                end

                S_SHOT_PREP: begin
                    if (auto_shot) begin
                        random_request <= 1'b1;
                        st             <= S_DRAW_WAIT;
                    end else begin
                        j_req_r     <= j_target;
                        current_j   <= j_target;
                        trial_count <= trial_count + 32'd1;
                        L_BBHT      <= L_BBHT + {{(32-`GP_J_W){1'b0}}, j_target};
                        st          <= S_PREP_REQ;
                    end
                end

                S_DRAW_WAIT: begin
                    if (random_done) begin
                        j_req_r     <= random_j;
                        current_j   <= random_j;
                        trial_count <= trial_count + 32'd1;
                        L_BBHT      <= L_BBHT + {{(32-`GP_J_W){1'b0}}, random_j};
                        st          <= S_PREP_REQ;
                    end
                end

                S_PREP_REQ: begin
                    prep_start <= 1'b1;
                    st         <= S_PREP_WAIT;
                end

                S_PREP_WAIT: begin
                    if (prep_done)
                        st <= S_MEAS_REQ;
                end

                S_MEAS_REQ: begin
                    meas_start <= 1'b1;
                    st         <= S_MEAS_WAIT;
                end

                S_MEAS_WAIT: begin
                    if (meas_done) begin
                        if (meas_zero_weight_error) begin
                            finish_reason <= R_ZERO_WEIGHT;
                            st            <= S_FIN;
                        end else if (meas_verify_hit) begin
                            success_index <= meas_candidate;
                            finish_reason <= R_SUCCESS;
                            st            <= S_FIN;
                        end else begin
                            st <= S_LIMIT;
                        end
                    end
                end

                S_LIMIT: begin
                    if (shot_hit) begin
                        finish_reason <= R_SHOT_LIMIT;
                        st            <= S_FIN;
                    end else if (budget_hit) begin
                        finish_reason <= R_BUDGET;
                        st            <= S_FIN;
                    end else if (!auto_shot) begin
                        finish_reason <= R_MANUAL_FAIL;
                        st            <= S_FIN;
                    end else begin
                        if (!rom_last)
                            round_idx <= round_idx + {{(`GP_RROM_IDX_W-1){1'b0}},1'b1};
                        st <= S_SHOT_PREP;
                    end
                end

                S_FIN: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    case (finish_reason)
                        R_SUCCESS:     term_success           <= 1'b1;
                        R_CONFIG:      term_config_error      <= 1'b1;
                        R_SHOT_LIMIT:  term_shot_limit        <= 1'b1;
                        R_BUDGET:      term_budget_limit      <= 1'b1;
                        R_ZERO_WEIGHT: term_zero_weight_error <= 1'b1;
                        default: ;
                    endcase
                    st <= S_IDLE;
                end

                default: begin
                    finish_reason <= R_CONFIG;
                    st            <= S_FIN;
                end
            endcase
        end
    end
endmodule
