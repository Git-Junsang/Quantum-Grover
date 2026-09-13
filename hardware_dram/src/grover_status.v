//==============================================================================
// grover_status.v -- LPSoC BBHT/Grover Main IP v0.3 status/counters
//
// Run-level status block shared by Single Search and Enumeration.  Internal
// BBHT segments may terminate many times during one Enumeration, so shot/budget
// limit events are accepted independently from the final run terminal pulse.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_status_counters (
    input  wire                         clk,
    input  wire                         rstn,

    // External run transaction boundary.
    input  wire                         accepted_start,
    input  wire                         terminal_done,

    // Final run terminal reason, aligned with terminal_done.
    input  wire                         term_success,
    input  wire                         term_config_error,
    input  wire                         term_shot_limit,
    input  wire                         term_budget_limit,
    input  wire                         term_zero_weight_error,
    input  wire [`GP_INDEX_W-1:0]       success_index,

    // Per-BBHT complete-failure diagnostics.  Enumeration may see many of
    // these before its final run termination.
    input  wire                         shot_limit_event,
    input  wire                         budget_limit_event,

    input  wire                         amp_sat_event,

    // Algorithmic run-global counters supplied by top-level control.
    input  wire [31:0]                  algorithm_trial_count,
    input  wire [31:0]                  algorithm_L_BBHT,

    // Physical Grover work.
    input  wire                         iter_done,
    input  wire [15:0]                  iter_count_completed,

    output reg                          done,
    output reg                          result_valid,
    output reg  [`GP_INDEX_W-1:0]       result_index,
    output reg                          config_error,
    output reg                          shot_limit,
    output reg                          budget_limit,
    output reg                          amp_overflow,
    output reg                          zero_weight_error,

    output reg  [31:0]                  trial_count,
    output reg  [31:0]                  L_BBHT,
    output reg  [31:0]                  actual_grover_iterations,
    output reg  [31:0]                  cycle_count
);
    reg search_active;

    always @(posedge clk) begin
        if (!rstn) begin
            search_active            <= 1'b0;
            done                     <= 1'b0;
            result_valid             <= 1'b0;
            result_index             <= {`GP_INDEX_W{1'b0}};
            config_error             <= 1'b0;
            shot_limit               <= 1'b0;
            budget_limit             <= 1'b0;
            amp_overflow             <= 1'b0;
            zero_weight_error        <= 1'b0;
            trial_count              <= 32'd0;
            L_BBHT                   <= 32'd0;
            actual_grover_iterations <= 32'd0;
            cycle_count              <= 32'd0;
        end else begin
            done <= 1'b0;

            if (accepted_start) begin
                search_active            <= 1'b1;
                result_valid             <= 1'b0;
                result_index             <= {`GP_INDEX_W{1'b0}};
                config_error             <= 1'b0;
                shot_limit               <= 1'b0;
                budget_limit             <= 1'b0;
                amp_overflow             <= 1'b0;
                zero_weight_error        <= 1'b0;
                trial_count              <= 32'd0;
                L_BBHT                   <= 32'd0;
                actual_grover_iterations <= 32'd0;
                cycle_count              <= 32'd0;
            end else if (search_active) begin
                trial_count <= algorithm_trial_count;
                L_BBHT      <= algorithm_L_BBHT;
                cycle_count <= cycle_count + 32'd1;

                if (iter_done)
                    actual_grover_iterations <= actual_grover_iterations
                                                + {16'd0, iter_count_completed};

                if (amp_sat_event)
                    amp_overflow <= 1'b1;

                if (shot_limit_event)
                    shot_limit <= 1'b1;
                if (budget_limit_event)
                    budget_limit <= 1'b1;

                if (terminal_done) begin
                    search_active <= 1'b0;
                    done          <= 1'b1;
                    trial_count   <= algorithm_trial_count;
                    L_BBHT        <= algorithm_L_BBHT;

                    if (term_success) begin
                        result_valid <= 1'b1;
                        result_index <= success_index;
                    end else if (term_zero_weight_error) begin
                        zero_weight_error <= 1'b1;
                    end else if (term_config_error) begin
                        config_error <= 1'b1;
                    end else begin
                        // For Single Search these are terminal causes; for
                        // Enumeration the sticky bits are normally set earlier
                        // by the per-BBHT event inputs.
                        if (term_shot_limit)
                            shot_limit <= 1'b1;
                        if (term_budget_limit)
                            budget_limit <= 1'b1;
                    end
                end
            end
        end
    end
endmodule
