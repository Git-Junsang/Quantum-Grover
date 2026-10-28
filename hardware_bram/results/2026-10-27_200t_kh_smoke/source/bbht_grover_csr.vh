//=====================================================================
// bbht_grover_csr.vh -- BBHT/Grover CSR 주소와 비트 정의 (RTL 쪽)
//
// 이 파일은 gen_csr.py 가 bbht_grover_csr.json 에서 생성했습니다. 직접 고치지 마십시오.
//
// 정본 버전 0.9.8 (2026-09-01)
//
// 주소는 워드 인덱스가 아니라 바이트 오프셋입니다. mmio 는 paddr 의
// 하위 비트에서 워드 인덱스를 뽑아 쓰므로 CSR_IDX_ 쪽을 씁니다.
//=====================================================================
`ifndef BBHT_GROVER_CSR_VH
`define BBHT_GROVER_CSR_VH

`define BBHT_CSR_STRIDE     4
`define BBHT_CSR_IDX_BITS   6
`define BBHT_CSR_NUM_REG    38

// 탐색 공간
`define BBHT_Q_BITS         14
`define BBHT_N_ENTRIES      16384
`define BBHT_DATA_W         16
`define BBHT_RESULT_W       14
`define BBHT_FIFO_CNT_W     9

// 워드 인덱스 (paddr[7:2])
`define CSR_IDX_COMMAND                    6'd0     // 0x000 W1P
`define CSR_IDX_CONTROL                    6'd1     // 0x004 RW
`define CSR_IDX_J_TARGET                   6'd2     // 0x008 RW
`define CSR_IDX_THRESHOLD_A                6'd3     // 0x00C RW
`define CSR_IDX_THRESHOLD_B                6'd4     // 0x010 RW
`define CSR_IDX_DATA_COUNT                 6'd5     // 0x014 RW
`define CSR_IDX_SHOT_CAP                   6'd6     // 0x018 RW
`define CSR_IDX_SEED_J                     6'd7     // 0x01C RW
`define CSR_IDX_SEED_MEAS                  6'd8     // 0x020 RW
`define CSR_IDX_STATUS                     6'd9     // 0x024 RO
`define CSR_IDX_RESULT_INDEX               6'd10    // 0x028 RO
`define CSR_IDX_TRIAL_COUNT                6'd11    // 0x02C RO
`define CSR_IDX_L_BBHT                     6'd12    // 0x030 RO
`define CSR_IDX_ACTUAL_ITER                6'd13    // 0x034 RO
`define CSR_IDX_CYCLE_COUNT                6'd14    // 0x038 RO
`define CSR_IDX_ENUM_CFG                   6'd15    // 0x03C RW
`define CSR_IDX_FIFO_DATA                  6'd16    // 0x040 RPOP
`define CSR_IDX_FIFO_COUNT                 6'd17    // 0x044 RO
`define CSR_IDX_FOUND_COUNT                6'd18    // 0x048 RO
`define CSR_IDX_CONSEC_FAIL                6'd19    // 0x04C RO
`define CSR_IDX_MAX_FIFO_OCC               6'd20    // 0x050 RO
`define CSR_IDX_FIFO_STALL                 6'd21    // 0x054 RO
`define CSR_IDX_DATA_ADDR                  6'd22    // 0x058 RW
`define CSR_IDX_DMA_COMMAND                6'd23    // 0x05C W1P
`define CSR_IDX_DMA_STATUS                 6'd24    // 0x060 RO
`define CSR_IDX_POLICY_CYCLES_TOTAL        6'd25    // 0x064 RO
`define CSR_IDX_POLICY_STALL_CYCLES        6'd26    // 0x068 RO
`define CSR_IDX_POLICY_ACTIONS_EVAL        6'd27    // 0x06C RO
`define CSR_IDX_POLICY_MEMO_HIT            6'd28    // 0x070 RO
`define CSR_IDX_POLICY_MEMO_MISS           6'd29    // 0x074 RO
`define CSR_IDX_POLICY_MAX_LATENCY         6'd30    // 0x078 RO
`define CSR_IDX_PLAN_FIFO_LEVEL            6'd31    // 0x07C RO
`define CSR_IDX_PLAN_FIFO_HIGHWATER        6'd32    // 0x080 RO
`define CSR_IDX_PLAN_FIFO_EMPTY_DEMAND     6'd33    // 0x084 RO
`define CSR_IDX_PLAN_FIFO_HIT_COUNT        6'd34    // 0x088 RO
`define CSR_IDX_PLAN_FIFO_MISMATCH_COUNT   6'd35    // 0x08C RO
`define CSR_IDX_POLICY_COLD_SOLVE_COUNT    6'd36    // 0x090 RO
`define CSR_IDX_POLICY_SPEC_SOLVE_COUNT    6'd37    // 0x094 RO

// STATUS 비트 위치
`define BBHT_ST_BUSY                 0
`define BBHT_ST_LOAD_BUSY            1
`define BBHT_ST_DONE_STICKY          2
`define BBHT_ST_RESULT_VALID         3
`define BBHT_ST_CONFIG_ERROR         4
`define BBHT_ST_SHOT_LIMIT           5
`define BBHT_ST_BUDGET_LIMIT         6
`define BBHT_ST_AMP_OVERFLOW         7
`define BBHT_ST_ZERO_WEIGHT_ERROR    8
`define BBHT_ST_LOAD_ERROR           9
`define BBHT_ST_ENUM_DONE            10
`define BBHT_ST_FIFO_EMPTY           11

// DMA_STATUS 비트 위치
`define BBHT_DMA_DMA_BUSY            0
`define BBHT_DMA_DMA_ERROR           1
`define BBHT_DMA_ALIGN_ERROR         2
`define BBHT_DMA_COUNT_ERROR         3
`define BBHT_DMA_RESP_ERROR          4
`define BBHT_DMA_BUSY_ERROR          5
`define BBHT_DMA_RANGE_ERROR         6
`define BBHT_DMA_DMA_DONE_STICKY     7

// 술어
`define BBHT_PRED_LT       2'd0
`define BBHT_PRED_GT       2'd1
`define BBHT_PRED_EQ       2'd2
`define BBHT_PRED_RANGE    2'd3

`endif
