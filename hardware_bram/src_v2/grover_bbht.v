//==============================================================================
// grover_bbht.v -- LPSoC BBHT/Grover Main IP v0.6 consolidated RTL
//
// File-level consolidation only: verified module boundaries and logic are
// preserved. No new wrapper hierarchy is introduced by this merge.
// Consolidated BBHT support RTL.  PRNG correctness fix replaces the legacy
// grover_lfsr32 instance path with grover_lfsr32_jump7 (J) and
// grover_meas_prng64_adapter (MEAS).
//==============================================================================


//------------------------------------------------------------------------------
// PRNG helper modules (PRNG correctness fix)
//------------------------------------------------------------------------------
`timescale 1ns/1ps
`include "grover_param.vh"

//==============================================================================
// grover_lfsr32_jump7 -- J-stream decorrelation adapter
//
// Keeps the original 32-bit LFSR polynomial and external seed contract, but
// advances the internal LFSR state by seven ordinary LFSR steps per candidate
// draw.  grover_j_reject consumes at most seven low bits (j in 0..127), so
// successive accepted/rejected candidate draws no longer reuse the same
// sliding low-bit window used by the previous draw.
//
// IMPORTANT: rnd is always the PRE-DRAW state, preserving the legacy draw timing contract.
// A draw consumes one candidate and advances the underlying LFSR by 7 steps.
//==============================================================================
module grover_lfsr32_jump7 #(
    parameter [31:0] FALLBACK_SEED = `GP_FALLBACK_J
) (
    input  wire        clk,
    input  wire        rstn,
    input  wire        seed_we,
    input  wire [31:0] seed,
    input  wire        draw,
    output wire [31:0] rnd
);
    reg [31:0] state;

    function [31:0] lfsr_step1;
        input [31:0] s;
        reg feedback;
        begin
            feedback  = s[31] ^ s[21] ^ s[1] ^ s[0];
            lfsr_step1 = {s[30:0], feedback};
        end
    endfunction

    function [31:0] lfsr_step7;
        input [31:0] s;
        integer i;
        reg [31:0] t;
        begin
            t = s;
            for (i = 0; i < 7; i = i + 1)
                t = lfsr_step1(t);
            lfsr_step7 = t;
        end
    endfunction

    always @(posedge clk) begin
        if (!rstn)
            state <= FALLBACK_SEED;
        else if (seed_we)
            state <= (seed == 32'd0) ? FALLBACK_SEED : seed;
        else if (draw)
            state <= lfsr_step7(state);
    end

    assign rnd = state;
endmodule

//==============================================================================
// grover_meas_prng64_adapter -- 64-bit measurement PRNG behind legacy 32-bit
// draw interface.
//
// The existing Born FSM intentionally remains unchanged: it requests two
// 32-bit draws (HI then LO) per 64-bit rejection candidate.  This adapter
// serves both halves from ONE 64-bit PRNG state and advances the 64-bit state
// only after the LO half is consumed.  Therefore a threshold candidate is a
// complete 64-bit PRNG block rather than two adjacent 32-bit LFSR states.
//
// External seed_meas remains 32-bit.  It is deterministically expanded to a
// non-zero 64-bit state, so the RVX/CSR/top-level interface does not change.
//
// PRNG core: Marsaglia xorshift64 (13,7,17), period 2^64-1 for non-zero state.
// It uses only shifts/XORs (no DSP/multiplier) and has three XOR dependency
// stages, avoiding a long 64-step combinational LFSR jump path.
//==============================================================================
module grover_meas_prng64_adapter #(
    parameter [31:0] FALLBACK_SEED = `GP_FALLBACK_MEAS,
    parameter [31:0] SEED_MIX      = 32'h9E37_79B9
) (
    input  wire        clk,
    input  wire        rstn,
    input  wire        seed_we,
    input  wire [31:0] seed,
    input  wire        draw,
    output wire [31:0] rnd
);
    reg [63:0] state;
    reg        half_sel; // 0: HI half, 1: LO half

    function [63:0] expand_seed64;
        input [31:0] s;
        reg [31:0] e;
        begin
            e = (s == 32'd0) ? FALLBACK_SEED : s;
            // SEED_MIX is non-zero, therefore the concatenated state cannot be 0.
            expand_seed64 = {e, (e ^ SEED_MIX)};
        end
    endfunction

    function [63:0] xorshift64_next;
        input [63:0] s;
        reg [63:0] x;
        begin
            x = s;
            x = x ^ (x << 13);
            x = x ^ (x >> 7);
            x = x ^ (x << 17);
            xorshift64_next = x;
        end
    endfunction

    always @(posedge clk) begin
        if (!rstn) begin
            state    <= expand_seed64(FALLBACK_SEED);
            half_sel <= 1'b0;
        end else if (seed_we) begin
            state    <= expand_seed64(seed);
            half_sel <= 1'b0;
        end else if (draw) begin
            if (!half_sel) begin
                // HI consumed. Keep the same 64-bit block for the following LO.
                half_sel <= 1'b1;
            end else begin
                // LO consumed. Advance exactly once to the next independent block.
                state    <= xorshift64_next(state);
                half_sel <= 1'b0;
            end
        end
    end

    assign rnd = half_sel ? state[31:0] : state[63:32];
endmodule
//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_j_reject.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_j_reject.v -- exact-uniform BBHT j candidate mapping, v0.6
//
// Given one 32-bit LFSR draw and m_bound in [1,128]:
//   k         = bit_length(m_bound-1)
//   mask      = 2^k - 1
//   candidate = rnd[k-1:0]
//   accept    = candidate < m_bound
//
// m_bound=1 is the direct case: candidate=0, accept=1.
// A rejection consumes the current draw; the BBHT FSM must request a NEW draw.
// This module itself is purely combinational and does not advance the LFSR.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_j_reject (
    input  wire [31:0]             rnd,
    input  wire [7:0]              m_bound,
    output wire [`GP_J_W-1:0]      candidate,
    output wire                     accept
);
    integer i;
    reg [3:0] k;
    reg [7:0] mask;
    reg [7:0] candidate8;
    wire [7:0] m_minus1 = m_bound - 8'd1;

    always @* begin
        k = 4'd0;
        if (m_bound > 8'd1) begin
            for (i = 0; i < 8; i = i + 1)
                if (m_minus1[i])
                    k = i + 1;
        end

        if (k == 4'd0)
            mask = 8'd0;
        else if (k >= 4'd8)
            mask = 8'hFF;
        else
            mask = (8'h01 << k) - 8'h01;

        candidate8 = rnd[7:0] & mask;
    end

    assign candidate = candidate8[`GP_J_W-1:0];
    assign accept = (m_bound != 8'd0) && (candidate8 < m_bound);
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_j_reject.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_iter_rom.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_iter_rom.v -- LPSoC BBHT/Grover Main IP v0.6, Step 9
//
// Q14 BBHT m_bound ROM generated from the SW Golden rule:
//   m <- min((6/5)*m, sqrt(N)), m_bound = ceil(m)
//
// 28 entries, index 0..27.  Any index above LAST_IDX returns the final
// clamped value 128.  This intentionally differs from the provisional GitHub
// integer recurrence table.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_iter_rom (
    input  wire [`GP_RROM_IDX_W-1:0] round_idx,
    output reg  [7:0]                 m_bound,
    output wire                       last
);
    always @* begin
        case (round_idx)
            5'd0 : m_bound = `GP_MBOUND_00;
            5'd1 : m_bound = `GP_MBOUND_01;
            5'd2 : m_bound = `GP_MBOUND_02;
            5'd3 : m_bound = `GP_MBOUND_03;
            5'd4 : m_bound = `GP_MBOUND_04;
            5'd5 : m_bound = `GP_MBOUND_05;
            5'd6 : m_bound = `GP_MBOUND_06;
            5'd7 : m_bound = `GP_MBOUND_07;
            5'd8 : m_bound = `GP_MBOUND_08;
            5'd9 : m_bound = `GP_MBOUND_09;
            5'd10: m_bound = `GP_MBOUND_10;
            5'd11: m_bound = `GP_MBOUND_11;
            5'd12: m_bound = `GP_MBOUND_12;
            5'd13: m_bound = `GP_MBOUND_13;
            5'd14: m_bound = `GP_MBOUND_14;
            5'd15: m_bound = `GP_MBOUND_15;
            5'd16: m_bound = `GP_MBOUND_16;
            5'd17: m_bound = `GP_MBOUND_17;
            5'd18: m_bound = `GP_MBOUND_18;
            5'd19: m_bound = `GP_MBOUND_19;
            5'd20: m_bound = `GP_MBOUND_20;
            5'd21: m_bound = `GP_MBOUND_21;
            5'd22: m_bound = `GP_MBOUND_22;
            5'd23: m_bound = `GP_MBOUND_23;
            5'd24: m_bound = `GP_MBOUND_24;
            5'd25: m_bound = `GP_MBOUND_25;
            5'd26: m_bound = `GP_MBOUND_26;
            default: m_bound = `GP_MBOUND_27;
        endcase
    end

    assign last = (round_idx >= `GP_RROM_LAST_IDX);
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_iter_rom.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_bbht_random.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_bbht_random.v -- LPSoC BBHT/Grover Main IP v0.6, Step 9
//
// Owns the J-side random stream for autonomous BBHT shots:
//   round_idx -> m_bound ROM -> exact-uniform mask/rejection -> j_req
//
// Random contract:
//   * independent 32-bit LFSR_J
//   * seed reload on accepted search start
//   * zero seed -> GP_FALLBACK_J
//   * one LFSR draw per candidate, including rejected candidates
//   * m_bound=1 still consumes one draw and returns j=0
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_bbht_random (
    input  wire                         clk,
    input  wire                         rstn,

    input  wire                         seed_we,
    input  wire [31:0]                  seed,

    // One-cycle request while idle. round_idx must remain stable until done.
    input  wire                         request,
    input  wire [`GP_RROM_IDX_W-1:0]   round_idx,

    output reg                          busy,
    output reg                          done,
    output reg  [`GP_J_W-1:0]          j_req,
    output wire [7:0]                   m_bound,

    // Debug/Golden trace hooks.
    output wire                         rnd_draw,
    output wire [31:0]                  rnd_state,
    output wire                         rom_last
);
    wire [`GP_J_W-1:0] candidate;
    wire                candidate_ok;

    grover_iter_rom u_rom (
        .round_idx (round_idx),
        .m_bound   (m_bound),
        .last      (rom_last)
    );

    grover_lfsr32_jump7 #(
        .FALLBACK_SEED (`GP_FALLBACK_J)
    ) u_lfsr_j (
        .clk     (clk),
        .rstn    (rstn),
        .seed_we (seed_we),
        .seed    (seed),
        .draw    (rnd_draw),
        .rnd     (rnd_state)
    );

    grover_j_reject u_reject (
        .rnd       (rnd_state),
        .m_bound   (m_bound),
        .candidate (candidate),
        .accept    (candidate_ok)
    );

    // While busy, every cycle is exactly one candidate draw.  The candidate
    // is evaluated from the pre-edge LFSR state; the same edge advances the
    // LFSR whether the candidate is accepted or rejected.
    assign rnd_draw = busy;

    always @(posedge clk) begin
        if (!rstn) begin
            busy  <= 1'b0;
            done  <= 1'b0;
            j_req <= {`GP_J_W{1'b0}};
        end else begin
            done <= 1'b0;

            if (!busy) begin
                if (request)
                    busy <= 1'b1;
            end else begin
                if (candidate_ok) begin
                    j_req <= candidate;
                    busy  <= 1'b0;
                    done  <= 1'b1;
                end
                // candidate rejection intentionally leaves busy asserted.
            end
        end
    end
endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_bbht_random.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_cache_ctrl.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_cache_ctrl.v -- LPSoC BBHT/Grover Main IP v0.6, Step 6
//
// 1-entry resume-cache metadata only.  The amplitude checkpoint itself is the
// current contents of amp_mem; this block stores only cache_valid + cache_j.
//
// v0.6 policy
//   Normal (burst_enable=0): always fresh INIT, execute j_req iterations.
//   Burst  (burst_enable=1):
//     no valid checkpoint       -> fresh INIT, execute j_req
//     j_req > cache_j           -> resume, execute j_req-cache_j
//     j_req = cache_j           -> resume, execute 0
//     j_req < cache_j           -> fresh INIT, execute j_req
//
// The completed Grover sequence is a valid checkpoint regardless of a later
// measurement/verify result.  Dataset/Oracle semantic changes must assert
// cache_invalidate.  Seed/shot-cap/auto-shot/j-target/burst-enable changes do
// not invalidate the amplitude state by themselves.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_cache_ctrl (
    input  wire                         clk,
    input  wire                         rstn,

    // One-cycle pulse when an upper-level shot is launched.
    input  wire                         shot_start,
    input  wire                         burst_enable,
    input  wire [`GP_J_W-1:0]           j_req,

    // Pulse for any change that alters dataset/Oracle semantics.
    // Typical OR: accepted_load_start | predicate_cfg_write |
    //             threshold_cfg_write | data_count_cfg_write.
    input  wire                         cache_invalidate,

    // Completion pulse from grover_ctrl_fsm for this shot's Grover sequence.
    input  wire                         iter_done,

    // Decision sampled by grover_ctrl_fsm together with shot_start.
    output wire                         iter_do_init,
    output wire [15:0]                  iter_count,
    output wire [`GP_J_W-1:0]           delta_j,

    // Internal metadata exposed for integration/debug.
    output reg                          cache_valid,
    output reg  [`GP_J_W-1:0]           cache_j
);
    reg [`GP_J_W-1:0] j_req_latched;
    reg                 run_active;
    reg                 run_stale;

    wire checkpoint_usable;
    assign checkpoint_usable = burst_enable && cache_valid &&
                               !cache_invalidate && (j_req >= cache_j);

    // Normal always forces INIT.  Burst resumes only from a compatible
    // checkpoint at or below the requested absolute Grover iteration count.
    assign iter_do_init = !checkpoint_usable;
    assign delta_j      = iter_do_init ? j_req : (j_req - cache_j);
    assign iter_count   = {{(16-`GP_J_W){1'b0}}, delta_j};

    always @(posedge clk) begin
        if (!rstn) begin
            cache_valid  <= 1'b0;
            cache_j      <= {`GP_J_W{1'b0}};
            j_req_latched<= {`GP_J_W{1'b0}};
            run_active   <= 1'b0;
            run_stale    <= 1'b0;
        end else begin
            // Invalidation of the old checkpoint has priority over metadata
            // validity.  A same-cycle new shot is allowed to build a fresh
            // checkpoint from the new semantics, so it does not mark that new
            // run stale by itself.
            if (cache_invalidate)
                cache_valid <= 1'b0;

            if (shot_start) begin
                j_req_latched <= j_req;
                run_active    <= 1'b1;
                run_stale     <= 1'b0;
            end else if (run_active && cache_invalidate) begin
                // Defensive handling for an illegal/exceptional config change
                // while an iteration sequence is already in flight.
                run_stale <= 1'b1;
            end

            if (iter_done) begin
                run_active <= 1'b0;

                // Do not resurrect a checkpoint if its semantics were changed
                // while it was being produced or on this completion edge.
                if (!run_stale && !cache_invalidate) begin
                    cache_j     <= j_req_latched;
                    cache_valid <= 1'b1;
                end else begin
                    cache_valid <= 1'b0;
                end
                run_stale <= 1'b0;
            end
        end
    end

endmodule
//------------------------------------------------------------------------------
// END preserved module source: grover_cache_ctrl.v
//------------------------------------------------------------------------------

//------------------------------------------------------------------------------
// BEGIN preserved module source: grover_bbht_shot_fsm.v
//------------------------------------------------------------------------------
//==============================================================================
// grover_bbht_shot_fsm.v -- LPSoC BBHT/Grover Main IP v0.6, Step 9
//
// Outer shot controller.  This block sequences already-verified lower blocks:
//   auto/manual j selection -> cache decision -> Grover -> measurement+verify
//   -> success / shot limit / BBHT budget / next shot.
//
// Integration assumptions:
//   * start is an accepted search request (top-level load/search interlock is
//     added at Step 11).  A start while this FSM is busy is ignored.
//   * config_ok represents all execution config/data-valid checks except the
//     local shot_cap!=0 rule, which is also enforced here.
//   * grover_cache_ctrl receives cache_shot_start+j_req and returns the
//     combinational iter_do_init/iter_count decision.
//   * grover_ctrl_fsm receives iter_start/iter_do_init/iter_count.
//   * grover_measure_verify receives meas_start and returns one final
//     meas_done carrying verify_hit/zero_weight_error/candidate.
//
// Counter timing used internally for termination follows v0.6:
//   trial_count += 1 and L_BBHT += requested j when j_req is finalized.
//   budget B = 1 + L_BBHT; terminate after a failed shot when B >= 576.
//
// Terminal priority after a completed shot:
//   success > zero-weight runtime error > shot_limit > budget_limit >
//   manual miss > next autonomous shot.
//==============================================================================
`timescale 1ns/1ps
`include "grover_param.vh"

module grover_bbht_shot_fsm (
    input  wire                         clk,
    input  wire                         rstn,

    input  wire                         start,
    input  wire                         config_ok,
    input  wire                         auto_shot,
    input  wire [`GP_J_W-1:0]          j_target,
    input  wire [`GP_SHOT_CAP_W-1:0]   shot_cap,
    input  wire [31:0]                  seed_j,
    // External-run seed reload.  Internal Enumeration BBHT restarts assert
    // start without seed_reload so the J-LFSR stream continues.
    input  wire                         seed_reload,

    // 1-entry cache-control interface.
    output reg                          cache_shot_start,
    output wire [`GP_J_W-1:0]          j_req,
    input  wire                         cache_iter_do_init,
    input  wire [15:0]                  cache_iter_count,

    // Inner Grover controller interface.
    output reg                          iter_start,
    output reg                          iter_do_init,
    output reg  [15:0]                  iter_count,
    input  wire                         iter_done,

    // Measurement + verify integration interface.
    output reg                          meas_start,
    input  wire                         meas_done,
    input  wire                         meas_verify_hit,
    input  wire                         meas_zero_weight_error,
    input  wire [`GP_INDEX_W-1:0]       meas_candidate,

    output reg                          busy,
    output reg                          done,

    // One-cycle terminal event pulses, aligned with done.
    output reg                          term_success,
    output reg                          term_config_error,
    output reg                          term_shot_limit,
    output reg                          term_budget_limit,
    output reg                          term_zero_weight_error,
    output reg  [`GP_INDEX_W-1:0]       success_index,

    // Step-9 trace/counter visibility.  Step 10 adds the complete externally
    // visible sticky-status/counter contract.
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
        S_CACHE      = 4'd4,
        S_ITER_REQ   = 4'd5,
        S_ITER_WAIT  = 4'd6,
        S_MEAS_REQ   = 4'd7,
        S_MEAS_WAIT  = 4'd8,
        S_LIMIT      = 4'd9,
        S_FIN        = 4'd10;

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

    // Seed reload is separated from BBHT start so Enumeration can restart a
    // fresh BBHT search without replaying the same random stream.
    wire random_seed_we = seed_reload;

    assign j_req = j_req_r;

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
            cache_shot_start       <= 1'b0;
            iter_start             <= 1'b0;
            iter_do_init           <= 1'b0;
            iter_count             <= 16'd0;
            meas_start             <= 1'b0;
            busy                   <= 1'b0;
            done                   <= 1'b0;
            term_success           <= 1'b0;
            term_config_error      <= 1'b0;
            term_shot_limit        <= 1'b0;
            term_budget_limit      <= 1'b0;
            term_zero_weight_error <= 1'b0;
            success_index          <= {`GP_INDEX_W{1'b0}};
            round_idx              <= {`GP_RROM_IDX_W{1'b0}};
            current_j              <= {`GP_J_W{1'b0}};
            trial_count            <= 32'd0;
            L_BBHT                 <= 32'd0;
        end else begin
            // Default pulse outputs.
            random_request         <= 1'b0;
            cache_shot_start       <= 1'b0;
            iter_start             <= 1'b0;
            meas_start             <= 1'b0;
            done                   <= 1'b0;
            term_success           <= 1'b0;
            term_config_error      <= 1'b0;
            term_shot_limit        <= 1'b0;
            term_budget_limit      <= 1'b0;
            term_zero_weight_error <= 1'b0;

            case (st)
                S_IDLE: begin
                    if (start) begin
                        // Search-status/counter clear happens on accepted start,
                        // before config result.  seed reload is combinationally
                        // asserted on this same edge through random_seed_we.
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
                        st          <= S_CACHE;
                    end
                end

                S_DRAW_WAIT: begin
                    if (random_done) begin
                        j_req_r     <= random_j;
                        current_j   <= random_j;
                        trial_count <= trial_count + 32'd1;
                        L_BBHT      <= L_BBHT + {{(32-`GP_J_W){1'b0}}, random_j};
                        st          <= S_CACHE;
                    end
                end

                S_CACHE: begin
                    // cache_iter_* are combinational functions of j_req and
                    // cache metadata from grover_cache_ctrl.
                    cache_shot_start <= 1'b1;
                    iter_do_init     <= cache_iter_do_init;
                    iter_count       <= cache_iter_count;
                    st               <= S_ITER_REQ;
                end

                S_ITER_REQ: begin
                    iter_start <= 1'b1;
                    st         <= S_ITER_WAIT;
                end

                S_ITER_WAIT: begin
                    if (iter_done)
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
                    // Success has already been resolved in S_MEAS_WAIT.
                    // If both limits hit on a failed shot, shot_limit wins.
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
                        // rom_last keeps index clamped at LAST_IDX=27.
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
                        default: ; // manual failed one-shot: no error/limit bit
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
//------------------------------------------------------------------------------
// END preserved module source: grover_bbht_shot_fsm.v
//------------------------------------------------------------------------------
