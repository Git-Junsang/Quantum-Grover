//==============================================================================
// grover_dram_random.v -- hardware_dram branch, reused from hardware_bram v0.6
//
// Byte-identical copy of the PRNG/ROM helper modules from
// hardware_bram/src_v2/grover_bbht.v (grover_lfsr32_jump7,
// grover_meas_prng64_adapter, grover_j_reject, grover_iter_rom,
// grover_bbht_random). None of these have any coupling to checkpoint storage
// or amplitude memory -- they only produce the BBHT candidate index j_req
// from the J-LFSR stream and the m_bound ROM. hardware_dram reuses them
// unmodified; only the shot-level controller that consumes j_req changes
// (see grover_dram_shot_fsm.v), because this branch resolves a candidate j by
// DRAM restore/extend instead of grover_cache_ctrl's single-slot checkpoint.
//
// grover_cache_ctrl and grover_bbht_shot_fsm from the original file are
// intentionally NOT copied here; grover_dram_shot_fsm.v replaces both.
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
