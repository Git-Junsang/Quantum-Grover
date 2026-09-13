`timescale 1ns/1ps
`include "grover_param.vh"

module bbht_grover_mmio (
    input  wire        clk,
    input  wire        rstnn,

    // ============================================================
    // APB slave
    // ============================================================
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] paddr,
    input  wire [31:0] pwdata,

    output wire        pready,
    output reg  [31:0] prdata,
    output wire        pslverr,

    // ============================================================
    // Main IP command / configuration
    // ============================================================
    output reg                          cmd_start,

    output reg                          cfg_auto_shot,
    output reg [`GP_J_W-1:0]           cfg_j_target,
    output reg                          cfg_burst_enable,
    output reg [1:0]                    cfg_predicate_mode,

    output reg signed [`GP_DATA_W-1:0]  cfg_threshold_a,
    output reg signed [`GP_DATA_W-1:0]  cfg_threshold_b,

    output reg [`GP_DATA_COUNT_W-1:0]   cfg_data_count,
    output reg [`GP_SHOT_CAP_W-1:0]     cfg_shot_cap,

    output reg [31:0]                   cfg_seed_j,
    output reg [31:0]                   cfg_seed_meas,

    // ============================================================
    // Enumeration configuration
    // ============================================================
    output reg                          cfg_enum_enable,
    output reg [`GP_ENUM_FAIL_W-1:0]    cfg_fail_repeat_limit,

    // ============================================================
    // Result FIFO
    // ============================================================
    output wire                         cmd_res_pop,

    // ============================================================
    // AHB DMA configuration / command
    // ============================================================
    output reg [31:0]                   cfg_data_addr,
    output reg                          cmd_dma_start,

    // ============================================================
    // Main IP status / result
    // ============================================================
    input  wire                         st_busy,
    input  wire                         st_load_busy,
    input  wire                         st_done_pulse,
    input  wire                         st_result_valid,
    input  wire [`GP_INDEX_W-1:0]       st_result_index,

    input  wire                         st_enum_done,
    input  wire [`GP_FOUND_COUNT_W-1:0] st_found_count,
    input  wire [`GP_ENUM_FAIL_W-1:0]   st_consecutive_fail_count,

    input  wire [`GP_RESULT_FIFO_CNT_W-1:0]
                                         st_max_fifo_occupancy,

    input  wire [31:0]                  st_fifo_stall_cycles,

    input  wire [`GP_INDEX_W-1:0]       st_res_dout,
    input  wire                         st_res_empty,

    input  wire [`GP_RESULT_FIFO_CNT_W-1:0]
                                         st_res_count,

    input  wire                         st_config_error,
    input  wire                         st_shot_limit,
    input  wire                         st_budget_limit,
    input  wire                         st_amp_overflow,
    input  wire                         st_zero_weight_error,
    input  wire                         st_load_error,

    input  wire [31:0]                  st_trial_count,
    input  wire [31:0]                  st_L_BBHT,
    input  wire [31:0]                  st_actual_grover_iterations,
    input  wire [31:0]                  st_cycle_count,

    // ============================================================
    // K4/H6 policy observability
    // ============================================================
    input  wire [31:0]                  st_policy_cycles_total,
    input  wire [31:0]                  st_policy_stall_cycles,
    input  wire [31:0]                  st_policy_actions_eval,
    input  wire [31:0]                  st_policy_memo_hit,
    input  wire [31:0]                  st_policy_memo_miss,
    input  wire [31:0]                  st_policy_max_latency,

    input  wire [2:0]                   st_plan_fifo_level,
    input  wire [2:0]                   st_plan_fifo_highwater,
    input  wire [31:0]                  st_plan_fifo_empty_demand,
    input  wire [31:0]                  st_plan_fifo_hit_count,
    input  wire [31:0]                  st_plan_fifo_mismatch_count,
    input  wire [31:0]                  st_policy_cold_solve_count,
    input  wire [31:0]                  st_policy_spec_solve_count,

    // ============================================================
    // AHB DMA status
    //
    // dma_error_bits =
    // {range, busy, resp, count, align}
    // ============================================================
    input  wire                         st_dma_busy,
    input  wire                         st_dma_error,
    input  wire [4:0]                   st_dma_error_bits,

    // bbht_ahb_loader -> load_done pulse
    input  wire                         st_dma_done_pulse
);

    // ============================================================
    // CSR map
    // ============================================================
    localparam [11:0]
        R_COMMAND          = 12'h000,
        R_CONTROL          = 12'h004,
        R_J_TARGET         = 12'h008,
        R_THRESHOLD_A      = 12'h00C,
        R_THRESHOLD_B      = 12'h010,
        R_DATA_COUNT       = 12'h014,
        R_SHOT_CAP         = 12'h018,
        R_SEED_J           = 12'h01C,
        R_SEED_MEAS        = 12'h020,

        R_STATUS           = 12'h024,
        R_RESULT_INDEX     = 12'h028,
        R_TRIAL_COUNT      = 12'h02C,
        R_L_BBHT           = 12'h030,
        R_ACTUAL_ITER      = 12'h034,
        R_CYCLE_COUNT      = 12'h038,

        R_ENUM_CFG         = 12'h03C,
        R_FIFO_DATA        = 12'h040,
        R_FIFO_COUNT       = 12'h044,
        R_FOUND_COUNT      = 12'h048,
        R_CONSEC_FAIL      = 12'h04C,
        R_MAX_FIFO_OCC     = 12'h050,
        R_FIFO_STALL       = 12'h054,

        R_DATA_ADDR        = 12'h058,
        R_DMA_COMMAND      = 12'h05C,
        R_DMA_STATUS       = 12'h060,

        R_POLICY_CYCLES     = 12'h064,
        R_POLICY_STALL      = 12'h068,
        R_POLICY_ACTIONS    = 12'h06C,
        R_POLICY_MEMO_HIT   = 12'h070,
        R_POLICY_MEMO_MISS  = 12'h074,
        R_POLICY_MAX_LAT    = 12'h078,

        R_PLAN_FIFO_LEVEL   = 12'h07C,
        R_PLAN_FIFO_HIGH    = 12'h080,
        R_PLAN_FIFO_EMPTY   = 12'h084,
        R_PLAN_FIFO_HIT     = 12'h088,
        R_PLAN_FIFO_MISMATCH= 12'h08C,
        R_POLICY_COLD_SOLVE = 12'h090,
        R_POLICY_SPEC_SOLVE = 12'h094;

    wire [11:0] offset = paddr[11:0];

    wire access = psel && penable;
    wire wr     = access &&  pwrite;
    wire rd     = access && ~pwrite;

    wire aligned = (offset[1:0] == 2'b00);

    wire mapped =
        (offset == R_COMMAND)      ||
        (offset == R_CONTROL)      ||
        (offset == R_J_TARGET)     ||
        (offset == R_THRESHOLD_A)  ||
        (offset == R_THRESHOLD_B)  ||
        (offset == R_DATA_COUNT)   ||
        (offset == R_SHOT_CAP)     ||
        (offset == R_SEED_J)       ||
        (offset == R_SEED_MEAS)    ||
        (offset == R_STATUS)       ||
        (offset == R_RESULT_INDEX) ||
        (offset == R_TRIAL_COUNT)  ||
        (offset == R_L_BBHT)       ||
        (offset == R_ACTUAL_ITER)  ||
        (offset == R_CYCLE_COUNT)  ||
        (offset == R_ENUM_CFG)     ||
        (offset == R_FIFO_DATA)    ||
        (offset == R_FIFO_COUNT)   ||
        (offset == R_FOUND_COUNT)  ||
        (offset == R_CONSEC_FAIL)  ||
        (offset == R_MAX_FIFO_OCC) ||
        (offset == R_FIFO_STALL)   ||
        (offset == R_DATA_ADDR)    ||
        (offset == R_DMA_COMMAND)  ||
        (offset == R_DMA_STATUS)       ||
        (offset == R_POLICY_CYCLES)     ||
        (offset == R_POLICY_STALL)      ||
        (offset == R_POLICY_ACTIONS)    ||
        (offset == R_POLICY_MEMO_HIT)   ||
        (offset == R_POLICY_MEMO_MISS)  ||
        (offset == R_POLICY_MAX_LAT)    ||
        (offset == R_PLAN_FIFO_LEVEL)   ||
        (offset == R_PLAN_FIFO_HIGH)    ||
        (offset == R_PLAN_FIFO_EMPTY)   ||
        (offset == R_PLAN_FIFO_HIT)     ||
        (offset == R_PLAN_FIFO_MISMATCH)||
        (offset == R_POLICY_COLD_SOLVE) ||
        (offset == R_POLICY_SPEC_SOLVE);

    assign pready  = 1'b1;
    assign pslverr = access && (!aligned || !mapped);

    // ============================================================
    // Result FIFO
    //
    // FIFO_DATA read -> one-cycle res_pop
    // ============================================================
    assign cmd_res_pop =
        rd &&
        mapped &&
        (offset == R_FIFO_DATA) &&
        !st_res_empty;

    // ============================================================
    // Sticky status
    // ============================================================
    reg done_sticky;
    reg dma_done_sticky;

    // ============================================================
    // Configuration / command registers
    // ============================================================
    always @(posedge clk or negedge rstnn) begin

        if (!rstnn) begin

            cmd_start             <= 1'b0;
            cmd_dma_start         <= 1'b0;

            cfg_auto_shot         <= 1'b1;
            cfg_j_target          <= {`GP_J_W{1'b0}};
            cfg_burst_enable      <= 1'b0;
            cfg_predicate_mode    <= 2'd0;

            cfg_threshold_a       <= {`GP_DATA_W{1'b0}};
            cfg_threshold_b       <= {`GP_DATA_W{1'b0}};

            cfg_data_count        <= {`GP_DATA_COUNT_W{1'b0}};
            cfg_shot_cap          <= 16'd100;

            cfg_seed_j            <= 32'd0;
            cfg_seed_meas         <= 32'd0;

            cfg_enum_enable       <= 1'b0;
            cfg_fail_repeat_limit <= `GP_ENUM_FAIL_DEFAULT;

            cfg_data_addr         <= 32'd0;

            done_sticky           <= 1'b0;
            dma_done_sticky       <= 1'b0;

        end
        else begin

            // ====================================================
            // Command outputs are one-cycle pulses
            // ====================================================
            cmd_start     <= 1'b0;
            cmd_dma_start <= 1'b0;

            // ====================================================
            // Search START
            // COMMAND bit0
            // ====================================================
            if (wr &&
                (offset == R_COMMAND) &&
                pwdata[0] &&
                !st_busy) begin

                cmd_start   <= 1'b1;
                done_sticky <= 1'b0;

            end
            else if (st_done_pulse) begin

                done_sticky <= 1'b1;

            end

            // ====================================================
            // DMA START
            //
            // st_busy로 여기서 차단하지 않음.
            // bbht_ahb_loader가 main_busy를 검사하고
            // busy_error를 기록함.
            //
            // 새 DMA command가 들어오면
            // 이전 DMA done sticky를 clear.
            // ====================================================
            if (wr &&
                (offset == R_DMA_COMMAND) &&
                pwdata[0]) begin

                cmd_dma_start   <= 1'b1;
                dma_done_sticky <= 1'b0;

            end
            else if (st_dma_done_pulse) begin

                dma_done_sticky <= 1'b1;

            end

            // ====================================================
            // Main IP busy 중 configuration 변경 금지
            // ====================================================
            if (wr && !st_busy) begin

                case (offset)

                    R_CONTROL: begin
                        cfg_auto_shot      <= pwdata[0];
                        cfg_burst_enable   <= pwdata[1];
                        cfg_predicate_mode <= pwdata[3:2];
                    end

                    R_J_TARGET: begin
                        cfg_j_target <=
                            pwdata[`GP_J_W-1:0];
                    end

                    R_THRESHOLD_A: begin
                        cfg_threshold_a <=
                            pwdata[`GP_DATA_W-1:0];
                    end

                    R_THRESHOLD_B: begin
                        cfg_threshold_b <=
                            pwdata[`GP_DATA_W-1:0];
                    end

                    R_DATA_COUNT: begin
                        cfg_data_count <=
                            pwdata[`GP_DATA_COUNT_W-1:0];
                    end

                    R_SHOT_CAP: begin
                        cfg_shot_cap <=
                            pwdata[`GP_SHOT_CAP_W-1:0];
                    end

                    R_SEED_J: begin
                        cfg_seed_j <= pwdata;
                    end

                    R_SEED_MEAS: begin
                        cfg_seed_meas <= pwdata;
                    end

                    R_ENUM_CFG: begin
                        cfg_enum_enable <= pwdata[0];

                        cfg_fail_repeat_limit <=
                            pwdata[
                                4 + `GP_ENUM_FAIL_W - 1
                                :
                                4
                            ];
                    end

                    R_DATA_ADDR: begin
                        cfg_data_addr <= pwdata;
                    end

                    default: begin
                    end

                endcase
            end
        end
    end

    // ============================================================
    // Main IP STATUS
    //
    // bit  0 : busy
    // bit  1 : load_busy
    // bit  2 : done_sticky
    // bit  3 : result_valid
    // bit  4 : config_error
    // bit  5 : shot_limit
    // bit  6 : budget_limit
    // bit  7 : amp_overflow
    // bit  8 : zero_weight_error
    // bit  9 : load_error
    // bit 10 : enum_done
    // bit 11 : result FIFO empty
    // ============================================================
    wire [31:0] status_word = {
        20'd0,
        st_res_empty,
        st_enum_done,
        st_load_error,
        st_zero_weight_error,
        st_amp_overflow,
        st_budget_limit,
        st_shot_limit,
        st_config_error,
        st_result_valid,
        done_sticky,
        st_load_busy,
        st_busy
    };

    // ============================================================
    // DMA STATUS
    //
    // bit 0 : dma_busy
    // bit 1 : dma_error
    // bit 2 : align_error
    // bit 3 : count_error
    // bit 4 : resp_error
    // bit 5 : busy_error
    // bit 6 : range_error
    // bit 7 : dma_done_sticky
    // ============================================================
    wire [31:0] dma_status_word = {
        24'd0,
        dma_done_sticky,
        st_dma_error_bits,
        st_dma_error,
        st_dma_busy
    };

    // ============================================================
    // APB read mux
    // ============================================================
    always @* begin

        case (offset)

            R_COMMAND: begin
                prdata = 32'd0;
            end

            R_CONTROL: begin
                prdata = {
                    28'd0,
                    cfg_predicate_mode,
                    cfg_burst_enable,
                    cfg_auto_shot
                };
            end

            R_J_TARGET: begin
                prdata =
                    {{(32-`GP_J_W){1'b0}},
                     cfg_j_target};
            end

            R_THRESHOLD_A: begin
                prdata =
                    {{(32-`GP_DATA_W){1'b0}},
                     cfg_threshold_a};
            end

            R_THRESHOLD_B: begin
                prdata =
                    {{(32-`GP_DATA_W){1'b0}},
                     cfg_threshold_b};
            end

            R_DATA_COUNT: begin
                prdata =
                    {{(32-`GP_DATA_COUNT_W){1'b0}},
                     cfg_data_count};
            end

            R_SHOT_CAP: begin
                prdata =
                    {{(32-`GP_SHOT_CAP_W){1'b0}},
                     cfg_shot_cap};
            end

            R_SEED_J: begin
                prdata = cfg_seed_j;
            end

            R_SEED_MEAS: begin
                prdata = cfg_seed_meas;
            end

            R_STATUS: begin
                prdata = status_word;
            end

            R_RESULT_INDEX: begin
                prdata =
                    {{(32-`GP_INDEX_W){1'b0}},
                     st_result_index};
            end

            R_TRIAL_COUNT: begin
                prdata = st_trial_count;
            end

            R_L_BBHT: begin
                prdata = st_L_BBHT;
            end

            R_ACTUAL_ITER: begin
                prdata =
                    st_actual_grover_iterations;
            end

            R_CYCLE_COUNT: begin
                prdata = st_cycle_count;
            end

            R_ENUM_CFG: begin
                prdata = {
                    24'd0,
                    cfg_fail_repeat_limit,
                    3'd0,
                    cfg_enum_enable
                };
            end

            R_FIFO_DATA: begin
                prdata =
                    st_res_empty
                    ? 32'd0
                    : {{(32-`GP_INDEX_W){1'b0}},
                       st_res_dout};
            end

            R_FIFO_COUNT: begin
                prdata =
                    {{(32-`GP_RESULT_FIFO_CNT_W){1'b0}},
                     st_res_count};
            end

            R_FOUND_COUNT: begin
                prdata =
                    {{(32-`GP_FOUND_COUNT_W){1'b0}},
                     st_found_count};
            end

            R_CONSEC_FAIL: begin
                prdata =
                    {{(32-`GP_ENUM_FAIL_W){1'b0}},
                     st_consecutive_fail_count};
            end

            R_MAX_FIFO_OCC: begin
                prdata =
                    {{(32-`GP_RESULT_FIFO_CNT_W){1'b0}},
                     st_max_fifo_occupancy};
            end

            R_FIFO_STALL: begin
                prdata = st_fifo_stall_cycles;
            end

            R_DATA_ADDR: begin
                prdata = cfg_data_addr;
            end

            R_DMA_COMMAND: begin
                prdata = 32'd0;
            end

            R_DMA_STATUS: begin
                prdata = dma_status_word;
            end

            R_POLICY_CYCLES: begin
                prdata = st_policy_cycles_total;
            end

            R_POLICY_STALL: begin
                prdata = st_policy_stall_cycles;
            end

            R_POLICY_ACTIONS: begin
                prdata = st_policy_actions_eval;
            end

            R_POLICY_MEMO_HIT: begin
                prdata = st_policy_memo_hit;
            end

            R_POLICY_MEMO_MISS: begin
                prdata = st_policy_memo_miss;
            end

            R_POLICY_MAX_LAT: begin
                prdata = st_policy_max_latency;
            end

            R_PLAN_FIFO_LEVEL: begin
                prdata = {29'd0, st_plan_fifo_level};
            end

            R_PLAN_FIFO_HIGH: begin
                prdata = {29'd0, st_plan_fifo_highwater};
            end

            R_PLAN_FIFO_EMPTY: begin
                prdata = st_plan_fifo_empty_demand;
            end

            R_PLAN_FIFO_HIT: begin
                prdata = st_plan_fifo_hit_count;
            end

            R_PLAN_FIFO_MISMATCH: begin
                prdata = st_plan_fifo_mismatch_count;
            end

            R_POLICY_COLD_SOLVE: begin
                prdata = st_policy_cold_solve_count;
            end

            R_POLICY_SPEC_SOLVE: begin
                prdata = st_policy_spec_solve_count;
            end

            default: begin
                prdata = 32'd0;
            end

        endcase
    end

endmodule
