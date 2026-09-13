//==============================================================================
// grover_param.vh
// LPSoC BBHT/Grover Main IP v0.6 -- single source of truth
//
// Baseline contract:
//   Q14 / P32 / signed DATA16 / Q1.22 amplitude (23-bit signed)
//
// Source alignment priority:
//   1) LPSoC Main IP final design v0.6
//   2) SW Golden RTL-profile / bit-exact contract
//   3) Quantum-Grover GitHub RTL implementation style
//
// IMPORTANT:
//   Q/F changes require regeneration/review of INIT_AMP, BBHT_BUDGET and
//   the Q14-specific 28-entry m_bound ROM values below.
//==============================================================================
`ifndef GROVER_PARAM_VH
`define GROVER_PARAM_VH

//------------------------------------------------------------------------------
// 1. Architectural baseline
//------------------------------------------------------------------------------
`define GP_Q                  14
`define GP_INDEX_W            `GP_Q
`define GP_N                  (1 << `GP_Q)          // 16384 basis states

`define GP_P                  32
`define GP_LOGP               5
`define GP_ROW_W              (`GP_Q - `GP_LOGP)   // 9
`define GP_ROWS               (1 << `GP_ROW_W)     // 512

`define GP_DATA_W             16
`define GP_DATA_COUNT_W       (`GP_Q + 1)           // 15, represents 1..N

//------------------------------------------------------------------------------
// 2. Fixed-point amplitude contract
//    Stored amplitude format: signed Q1.22-like code, AMP_W = F + 1.
//    Legal symmetric saturation range excludes the most-negative 2's-comp code.
//------------------------------------------------------------------------------
`define GP_FRAC_BITS          22
`define GP_AMP_W              (`GP_FRAC_BITS + 1)  // 23
`define GP_PARTIAL_SUM_W      (`GP_AMP_W + `GP_LOGP) // 28, 32-lane amplitude sum
`define GP_ACC_W              (`GP_AMP_W + `GP_Q + 2) // 39
`define GP_TWO_MEAN_W         25
`define GP_DIFF_W             25

`define GP_SQUARE_W           (2 * `GP_AMP_W)      // 46
`define GP_ROW_SUM_W          (`GP_SQUARE_W + `GP_LOGP) // 51
`define GP_TOTAL_WEIGHT_W     (`GP_SQUARE_W + `GP_Q)    // 60

// Q14/F22 uniform state: (2^22)/sqrt(2^14) = 2^15 = 32768 exactly.
`define GP_INIT_AMP_RAW       23'sd32768

// Symmetric saturation bounds for AMP_W=23.
`define GP_AMP_MAX            23'sd4194303
`define GP_AMP_MIN           -23'sd4194303

// Read -> compute/register -> writeback baseline pipeline latency.
`define GP_PIPE_LAT           2

//------------------------------------------------------------------------------
// 3. Predicate encoding
//    Strict signed comparisons. RANGE is open interval A < data < B.
//------------------------------------------------------------------------------
`define GP_MODE_LT            2'b00
`define GP_MODE_GT            2'b01
`define GP_MODE_EQ            2'b10
`define GP_MODE_RANGE         2'b11

//------------------------------------------------------------------------------
// 4. BBHT contract (Q14 baseline)
//------------------------------------------------------------------------------
`define GP_M0                 8'd1
`define GP_M_MAX              8'd128
`define GP_J_W                7          // j = 0..127

`define GP_RROM_DEPTH         28
`define GP_RROM_IDX_W         5
`define GP_RROM_LAST_IDX      5'd27

// SW Golden: m <- min((6/5)*m, sqrt(N)), m_bound = ceil(m)
// Q14 handoff sequence.  Entry 27 is 128 and the round index clamps there.
`define GP_MBOUND_00          8'd1
`define GP_MBOUND_01          8'd2
`define GP_MBOUND_02          8'd2
`define GP_MBOUND_03          8'd2
`define GP_MBOUND_04          8'd3
`define GP_MBOUND_05          8'd3
`define GP_MBOUND_06          8'd3
`define GP_MBOUND_07          8'd4
`define GP_MBOUND_08          8'd5
`define GP_MBOUND_09          8'd6
`define GP_MBOUND_10          8'd7
`define GP_MBOUND_11          8'd8
`define GP_MBOUND_12          8'd9
`define GP_MBOUND_13          8'd11
`define GP_MBOUND_14          8'd13
`define GP_MBOUND_15          8'd16
`define GP_MBOUND_16          8'd19
`define GP_MBOUND_17          8'd23
`define GP_MBOUND_18          8'd27
`define GP_MBOUND_19          8'd32
`define GP_MBOUND_20          8'd39
`define GP_MBOUND_21          8'd47
`define GP_MBOUND_22          8'd56
`define GP_MBOUND_23          8'd67
`define GP_MBOUND_24          8'd80
`define GP_MBOUND_25          8'd96
`define GP_MBOUND_26          8'd115
`define GP_MBOUND_27          8'd128

// Primary BBHT compute-cost guard, Q14 baseline: 4.5*sqrt(16384)=576.
`define GP_BBHT_BUDGET        32'd576

// Runtime shot_cap is a 16-bit Main-IP input. 100 is the baseline SW setting.
`define GP_SHOT_CAP_W         16
`define GP_SHOT_CAP_DEFAULT   16'd100

//------------------------------------------------------------------------------
// 5. Random/LFSR contract
//------------------------------------------------------------------------------
`define GP_LFSR_W             32
`define GP_FALLBACK_J         32'hACE1_2345
`define GP_FALLBACK_MEAS      32'hBEEF_C0DE

// Feedback polynomial implementation rule:
//   fb = state[31] ^ state[21] ^ state[1] ^ state[0]
//   next = {state[30:0], fb}
// LFSR state advances only on its own draw event.

//------------------------------------------------------------------------------
// 6. Common counter widths
//------------------------------------------------------------------------------
`define GP_COUNTER_W          32

//------------------------------------------------------------------------------
// 7. Enumeration v0.3 contract
//------------------------------------------------------------------------------
`define GP_ENUM_FAIL_W        4
`define GP_ENUM_FAIL_DEFAULT  4'd3
`define GP_FOUND_COUNT_W      `GP_DATA_COUNT_W

// Initial result-stream queue depth.  This remains a parameterized implementation
// knob; the top-level visible count width is sized for the baseline depth 256.
`define GP_RESULT_FIFO_DEPTH  256
`define GP_RESULT_FIFO_CNT_W  9

`endif
