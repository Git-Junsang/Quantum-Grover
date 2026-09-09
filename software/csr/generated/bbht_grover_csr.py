"""bbht_grover_csr.py -- 호스트 쪽 CSR 상수.

이 파일은 gen_csr.py 가 bbht_grover_csr.json 에서 생성했습니다. 직접 고치지 마십시오.

정본 버전 0.9.8 (2026-09-01)
"""

BASE = 0xE2020000
STRIDE = 4

REG = {
    "COMMAND":                   (0x000, 'W1P'),
    "CONTROL":                   (0x004, 'RW'),
    "J_TARGET":                  (0x008, 'RW'),
    "THRESHOLD_A":               (0x00C, 'RW'),
    "THRESHOLD_B":               (0x010, 'RW'),
    "DATA_COUNT":                (0x014, 'RW'),
    "SHOT_CAP":                  (0x018, 'RW'),
    "SEED_J":                    (0x01C, 'RW'),
    "SEED_MEAS":                 (0x020, 'RW'),
    "STATUS":                    (0x024, 'RO'),
    "RESULT_INDEX":              (0x028, 'RO'),
    "TRIAL_COUNT":               (0x02C, 'RO'),
    "L_BBHT":                    (0x030, 'RO'),
    "ACTUAL_ITER":               (0x034, 'RO'),
    "CYCLE_COUNT":               (0x038, 'RO'),
    "ENUM_CFG":                  (0x03C, 'RW'),
    "FIFO_DATA":                 (0x040, 'RPOP'),
    "FIFO_COUNT":                (0x044, 'RO'),
    "FOUND_COUNT":               (0x048, 'RO'),
    "CONSEC_FAIL":               (0x04C, 'RO'),
    "MAX_FIFO_OCC":              (0x050, 'RO'),
    "FIFO_STALL":                (0x054, 'RO'),
    "DATA_ADDR":                 (0x058, 'RW'),
    "DMA_COMMAND":               (0x05C, 'W1P'),
    "DMA_STATUS":                (0x060, 'RO'),
    "POLICY_CYCLES_TOTAL":       (0x064, 'RO'),
    "POLICY_STALL_CYCLES":       (0x068, 'RO'),
    "POLICY_ACTIONS_EVAL":       (0x06C, 'RO'),
    "POLICY_MEMO_HIT":           (0x070, 'RO'),
    "POLICY_MEMO_MISS":          (0x074, 'RO'),
    "POLICY_MAX_LATENCY":        (0x078, 'RO'),
    "PLAN_FIFO_LEVEL":           (0x07C, 'RO'),
    "PLAN_FIFO_HIGHWATER":       (0x080, 'RO'),
    "PLAN_FIFO_EMPTY_DEMAND":    (0x084, 'RO'),
    "PLAN_FIFO_HIT_COUNT":       (0x088, 'RO'),
    "PLAN_FIFO_MISMATCH_COUNT":  (0x08C, 'RO'),
    "POLICY_COLD_SOLVE_COUNT":   (0x090, 'RO'),
    "POLICY_SPEC_SOLVE_COUNT":   (0x094, 'RO'),
}

STATUS_BITS = [
    ( 0, "busy",              'search/main busy'),
    ( 1, "load_busy",         'Main IP loader busy'),
    ( 2, "done_sticky",       'search 완료 sticky. COMMAND 쓰기로 클리어'),
    ( 3, "result_valid",      'Single result 유효'),
    ( 4, "config_error",      '설정 오류 sticky'),
    ( 5, "shot_limit",        'shot cap 도달 sticky'),
    ( 6, "budget_limit",      'BBHT logical budget 도달 sticky'),
    ( 7, "amp_overflow",      '진폭 포화 sticky. 진단용이며 종료 사유가 아님'),
    ( 8, "zero_weight_error", 'Born total-weight 오류 sticky'),
    ( 9, "load_error",        'loader 검증 오류 sticky'),
    (10, "enum_done",         'Enumeration 종료 sticky'),
    (11, "fifo_empty",        'Result FIFO 비어 있음'),
]

DMA_STATUS_BITS = [
    ( 0, "dma_busy",          'DMA 진행 중'),
    ( 1, "dma_error",         '아래 오류들의 OR'),
    ( 2, "align_error",       'DATA_ADDR 4바이트 정렬 위반'),
    ( 3, "count_error",       'DATA_COUNT 범위 위반'),
    ( 4, "resp_error",        'AHB 응답 오류'),
    ( 5, "busy_error",        'Main IP busy 라서 DMA 거절'),
    ( 6, "range_error",       'System SRAM 범위 밖'),
    ( 7, "dma_done_sticky",   'DMA 완료 sticky'),
]

PREDICATE = {
    "LT":      0,
    "GT":      1,
    "EQ":      2,
    "RANGE":   3,
}

RUN_MODES = {
    "MANUAL_SINGLE":   dict(auto_shot=0, burst_enable=0, enum_enable=0),
    "NORMAL_SINGLE":   dict(auto_shot=1, burst_enable=0, enum_enable=0),
    "K4H8_SINGLE":     dict(auto_shot=1, burst_enable=1, enum_enable=0),
    "NORMAL_ENUM":     dict(auto_shot=1, burst_enable=0, enum_enable=1),
    "K4H8_ENUM":       dict(auto_shot=1, burst_enable=1, enum_enable=1),
}

Q_BITS = 14
N_ENTRIES = 16384
ACCEL_CLK_HZ = 100000000
SRAM_BASE = 0xE0000000
SRAM_LAST = 0xE001FFFF
