`timescale 1ns/1ps
`include "grover_param.vh"

module bbht_rvx_wrapper (
    input  wire        clk,
    input  wire        rstnn,

    // ============================================================
    // RVX APB slave
    // ============================================================
    input  wire        psel,
    input  wire        penable,
    input  wire        pwrite,
    input  wire [31:0] paddr,
    input  wire [31:0] pwdata,

    output wire        pready,
    output wire [31:0] prdata,
    output wire        pslverr,

    // ============================================================
    // RVX AHB master
    // ============================================================
    input  wire        shready,

    output wire [31:0] shaddr,
    output wire [2:0]  shburst,
    output wire        shmasterlock,
    output wire [3:0]  shprot,
    output wire [2:0]  shsize,
    output wire [1:0]  shtrans,
    output wire        shwrite,
    output wire [31:0] shwdata,

    input  wire [31:0] shrdata,
    input  wire        shresp
);

    // ============================================================
    // MMIO -> Main IP configuration
    // ============================================================
    wire                         cmd_start;

    wire                         cfg_auto_shot;
    wire [`GP_J_W-1:0]          cfg_j_target;
    wire                         cfg_burst_enable;
    wire [1:0]                   cfg_predicate_mode;

    wire signed [`GP_DATA_W-1:0] cfg_threshold_a;
    wire signed [`GP_DATA_W-1:0] cfg_threshold_b;

    wire [`GP_DATA_COUNT_W-1:0]  cfg_data_count;
    wire [`GP_SHOT_CAP_W-1:0]    cfg_shot_cap;

    wire [31:0]                  cfg_seed_j;
    wire [31:0]                  cfg_seed_meas;

    // Enumeration
    wire                         cfg_enum_enable;
    wire [`GP_ENUM_FAIL_W-1:0]   cfg_fail_repeat_limit;

    // Result FIFO
    wire                         cmd_res_pop;

    // ============================================================
    // MMIO -> AHB DMA configuration
    // ============================================================
    wire [31:0]                  cfg_data_addr;
    wire                         cmd_dma_start;

    // ============================================================
    // AHB loader -> Main IP loader
    // ============================================================
    wire                         mip_load_start;
    wire                         mip_data_wr_en;
    wire [`GP_INDEX_W-1:0]       mip_data_wr_addr;
    wire signed [`GP_DATA_W-1:0] mip_data_wr_data;
    wire                         mip_load_done;

    // ============================================================
    // Main IP -> MMIO status
    // ============================================================
    wire                         st_busy;
    wire                         st_load_busy;
    wire                         st_done;
    wire                         st_result_valid;
    wire [`GP_INDEX_W-1:0]       st_result_index;

    // Enumeration status
    wire                         st_enum_done;
    wire [`GP_FOUND_COUNT_W-1:0] st_found_count;
    wire [`GP_ENUM_FAIL_W-1:0]   st_consecutive_fail_count;

    wire [`GP_RESULT_FIFO_CNT_W-1:0]
                                 st_max_fifo_occupancy;

    wire [31:0]                  st_fifo_stall_cycles;

    // Result FIFO
    wire [`GP_INDEX_W-1:0]       st_res_dout;
    wire                         st_res_empty;

    wire [`GP_RESULT_FIFO_CNT_W-1:0]
                                 st_res_count;

    // Error/status
    wire                         st_config_error;
    wire                         st_shot_limit;
    wire                         st_budget_limit;
    wire                         st_amp_overflow;
    wire                         st_zero_weight_error;
    wire                         st_load_error;

    // Performance counters
    wire [31:0]                  st_trial_count;
    wire [31:0]                  st_L_BBHT;
    wire [31:0]                  st_actual_grover_iterations;
    wire [31:0]                  st_cycle_count;

    // K3/H3 policy observability
    wire [31:0]                  st_policy_cycles_total;
    wire [31:0]                  st_policy_stall_cycles;
    wire [31:0]                  st_policy_actions_eval;
    wire [31:0]                  st_policy_memo_hit;
    wire [31:0]                  st_policy_memo_miss;
    wire [31:0]                  st_policy_max_latency;

    wire [2:0]                   st_plan_fifo_level;
    wire [2:0]                   st_plan_fifo_highwater;
    wire [31:0]                  st_plan_fifo_empty_demand;
    wire [31:0]                  st_plan_fifo_hit_count;
    wire [31:0]                  st_plan_fifo_mismatch_count;
    wire [31:0]                  st_policy_cold_solve_count;
    wire [31:0]                  st_policy_spec_solve_count;

    // ============================================================
    // AHB DMA -> MMIO status
    // ============================================================
    wire                         st_dma_busy;
    wire                         st_dma_error;
    wire [4:0]                   st_dma_error_bits;

    // ============================================================
    // APB CSR block
    // ============================================================
    bbht_grover_mmio
    u_mmio (
        .clk(clk),
        .rstnn(rstnn),

        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .paddr(paddr),
        .pwdata(pwdata),

        .pready(pready),
        .prdata(prdata),
        .pslverr(pslverr),

        // Search command/config
        .cmd_start(cmd_start),

        .cfg_auto_shot(cfg_auto_shot),
        .cfg_j_target(cfg_j_target),
        .cfg_burst_enable(cfg_burst_enable),
        .cfg_predicate_mode(cfg_predicate_mode),

        .cfg_threshold_a(cfg_threshold_a),
        .cfg_threshold_b(cfg_threshold_b),

        .cfg_data_count(cfg_data_count),
        .cfg_shot_cap(cfg_shot_cap),

        .cfg_seed_j(cfg_seed_j),
        .cfg_seed_meas(cfg_seed_meas),

        // Enumeration
        .cfg_enum_enable(cfg_enum_enable),
        .cfg_fail_repeat_limit(cfg_fail_repeat_limit),

        // Result FIFO
        .cmd_res_pop(cmd_res_pop),

        // DMA
        .cfg_data_addr(cfg_data_addr),
        .cmd_dma_start(cmd_dma_start),

        // Main IP status
        .st_busy(st_busy),
        .st_load_busy(st_load_busy),
        .st_done_pulse(st_done),
        .st_result_valid(st_result_valid),
        .st_result_index(st_result_index),

        // Enumeration status
        .st_enum_done(st_enum_done),
        .st_found_count(st_found_count),
        .st_consecutive_fail_count(
            st_consecutive_fail_count
        ),
        .st_max_fifo_occupancy(
            st_max_fifo_occupancy
        ),
        .st_fifo_stall_cycles(
            st_fifo_stall_cycles
        ),

        // Result FIFO status/data
        .st_res_dout(st_res_dout),
        .st_res_empty(st_res_empty),
        .st_res_count(st_res_count),

        // Main IP errors
        .st_config_error(st_config_error),
        .st_shot_limit(st_shot_limit),
        .st_budget_limit(st_budget_limit),
        .st_amp_overflow(st_amp_overflow),
        .st_zero_weight_error(st_zero_weight_error),
        .st_load_error(st_load_error),

        // Counters
        .st_trial_count(st_trial_count),
        .st_L_BBHT(st_L_BBHT),
        .st_actual_grover_iterations(
            st_actual_grover_iterations
        ),
        .st_cycle_count(st_cycle_count),

        // K3/H3 policy observability
        .st_policy_cycles_total(st_policy_cycles_total),
        .st_policy_stall_cycles(st_policy_stall_cycles),
        .st_policy_actions_eval(st_policy_actions_eval),
        .st_policy_memo_hit(st_policy_memo_hit),
        .st_policy_memo_miss(st_policy_memo_miss),
        .st_policy_max_latency(st_policy_max_latency),

        .st_plan_fifo_level(st_plan_fifo_level),
        .st_plan_fifo_highwater(st_plan_fifo_highwater),
        .st_plan_fifo_empty_demand(st_plan_fifo_empty_demand),
        .st_plan_fifo_hit_count(st_plan_fifo_hit_count),
        .st_plan_fifo_mismatch_count(st_plan_fifo_mismatch_count),
        .st_policy_cold_solve_count(st_policy_cold_solve_count),
        .st_policy_spec_solve_count(st_policy_spec_solve_count),

        // DMA status
	.st_dma_busy(st_dma_busy),
	.st_dma_error(st_dma_error),
	.st_dma_error_bits(st_dma_error_bits),
	.st_dma_done_pulse(mip_load_done)
    );

    // ============================================================
    // RVX AHB -> Main IP dataset loader
    // ============================================================
    bbht_ahb_loader
    u_ahb_loader (
        .clk(clk),
        .rstnn(rstnn),

        // CSR
        .src_addr(cfg_data_addr),
        .data_count(cfg_data_count),
        .dma_start(cmd_dma_start),

        .dma_busy(st_dma_busy),
        .dma_error(st_dma_error),
        .dma_error_bits(st_dma_error_bits),

        // Main IP loader
        .load_start(mip_load_start),
        .data_wr_en(mip_data_wr_en),
        .data_wr_addr(mip_data_wr_addr),
        .data_wr_data(mip_data_wr_data),
        .load_done(mip_load_done),

        .load_busy(st_load_busy),

        // Main IP busy = search_busy | load_busy
        .main_busy(st_busy),

        // RVX AHB
        .shready(shready),

        .shaddr(shaddr),
        .shburst(shburst),
        .shmasterlock(shmasterlock),
        .shprot(shprot),
        .shsize(shsize),
        .shtrans(shtrans),
        .shwrite(shwrite),
        .shwdata(shwdata),

        .shrdata(shrdata),
        .shresp(shresp)
    );

    // ============================================================
    // BBHT / Grover Main IP
    // ============================================================
    bbht_grover_main_ip #(
        .CHECKPOINT_ENABLE(1),
        .CKPT_K(3),
        .POLICY_H_FUTURE(3),
        .CKPT_MANUAL_ENABLE(0),
        .AUTO_SPEC_ENABLE(1),
        .INTRA_ENGINES(4),
        .MEAS_M1_ENABLE(1),
        .MEAS_M2_ENABLE(1)
    )
    u_main_ip (
        .clk(clk),
        .rstn(rstnn),

        // Search
        .start(cmd_start),
        .auto_shot(cfg_auto_shot),
        .j_target(cfg_j_target),
        .burst_enable(cfg_burst_enable),

        // Enumeration
        .enum_enable(cfg_enum_enable),
        .fail_repeat_limit(cfg_fail_repeat_limit),

        // Production autonomous K3/H3-E4-M2
        // Manual verification-only checkpoint policy is compile-time removed.
        .checkpoint_manual_enable(1'b0),
        .policy_valid(1'b0),
        .policy_source_j({`GP_J_W{1'b0}}),
        .policy_next_count(3'd0),
        .policy_next_j_flat({(4*`GP_J_W){1'b0}}),
        .checkpoint_auto_enable(cfg_burst_enable && cfg_auto_shot),

        // Predicate
        .predicate_mode(cfg_predicate_mode),
        .threshold_a(cfg_threshold_a),
        .threshold_b(cfg_threshold_b),
        .data_count(cfg_data_count),

        // BBHT / PRNG
        .shot_cap(cfg_shot_cap),
        .seed_j(cfg_seed_j),
        .seed_meas(cfg_seed_meas),

        // Dataset loader
        .load_start(mip_load_start),
        .data_wr_en(mip_data_wr_en),
        .data_wr_addr(mip_data_wr_addr),
        .data_wr_data(mip_data_wr_data),
        .load_done(mip_load_done),
        .load_busy(st_load_busy),

        // Result FIFO
        .res_pop(cmd_res_pop),
        .res_dout(st_res_dout),
        .res_empty(st_res_empty),
        .res_count(st_res_count),

        // Execution/result
        .busy(st_busy),
        .done(st_done),
        .result_valid(st_result_valid),
        .result_index(st_result_index),

        // Enumeration status
        .enum_done(st_enum_done),
        .found_count(st_found_count),
        .consecutive_fail_count(
            st_consecutive_fail_count
        ),
        .max_fifo_occupancy(
            st_max_fifo_occupancy
        ),
        .fifo_stall_cycles(
            st_fifo_stall_cycles
        ),

        // Errors
        .config_error(st_config_error),
        .shot_limit(st_shot_limit),
        .budget_limit(st_budget_limit),
        .amp_overflow(st_amp_overflow),
        .zero_weight_error(st_zero_weight_error),
        .load_error(st_load_error),

        // Counters
        .trial_count(st_trial_count),
        .L_BBHT(st_L_BBHT),
        .actual_grover_iterations(
            st_actual_grover_iterations
        ),
        .cycle_count(st_cycle_count),

        // Phase-6 policy observability
        .policy_cycles_total(st_policy_cycles_total),
        .policy_stall_cycles(st_policy_stall_cycles),
        .policy_actions_eval(st_policy_actions_eval),
        .policy_memo_hit(st_policy_memo_hit),
        .policy_memo_miss(st_policy_memo_miss),
        .policy_max_latency(st_policy_max_latency),

        // Phase-6 speculative-plan observability
        .plan_fifo_level(st_plan_fifo_level),
        .plan_fifo_highwater(st_plan_fifo_highwater),
        .plan_fifo_empty_demand(st_plan_fifo_empty_demand),
        .plan_fifo_hit_count(st_plan_fifo_hit_count),
        .plan_fifo_mismatch_count(st_plan_fifo_mismatch_count),
        .policy_cold_solve_count(st_policy_cold_solve_count),
        .policy_spec_solve_count(st_policy_spec_solve_count)
    );


endmodule
