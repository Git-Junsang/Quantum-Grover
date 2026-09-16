/*
 * bbht_console -- 호스트에서 UART 로 BBHT/Grover 를 직접 몰기 위한 셸
 *
 * 기존 proof app 들은 술어와 임계값과 시드가 C 코드에 박혀 있어서, 조건을
 * 하나 바꾸려면 앱을 다시 빌드하고 다시 내려받아야 했습니다. 이 앱은 그
 * 값들을 UART 명령으로 받습니다. 비트스트림도 앱도 그대로 두고 호스트에서
 * 조건만 바꿔 가며 돌릴 수 있습니다.
 *
 * 프로토콜 정본은 documents/design_references/UART_명령_프로토콜.md 입니다. 요약하면,
 *   - 명령은 한 줄. 개행으로 끝납니다
 *   - 응답은 데이터 줄이 먼저 나오고, 마지막이 반드시 OK 또는 ERR 입니다
 *   - 호스트는 그 마지막 줄을 보고 다음 명령을 보냅니다
 *
 * 흐름 제어가 없는 8N1 원시 스트림이므로 "응답을 받은 뒤에 다음 명령" 이
 * 규약입니다. 이것을 어기면 폴링 루프 동안 RX FIFO 가 넘칩니다.
 */
#include "platform_info.h"
#include "ervp_printf.h"
#include "ervp_uart.h"
#include "bbht_grover_driver.h"

#define UART_IDX      UART_INDEX_FOR_UART_PRINTF
#define LINE_MAX      160
#define WORDS_MAX     (BBHT_N_ENTRIES / 2)      /* 8192 워드 = 32 KiB */
#define ENUM_OUT_MAX  512

/* 데이터셋 버퍼. System SRAM 에 잡히고 이 주소를 그대로 DMA 원본으로
 * 넘깁니다. 4바이트 정렬이 필수입니다. */
static unsigned int dataset[WORDS_MAX] __attribute__((aligned(4)));

static unsigned short enum_out[ENUM_OUT_MAX];

static bbht_config_t  cfg;
static bbht_result_t  res;

static unsigned int dataset_count = 0u;   /* 지금 버퍼에 든 항목 수 */
static unsigned int dataset_ready = 0u;   /* DMA 로 적재까지 끝났는가 */

/*====================================================================
 * 문자열 도우미. 표준 라이브러리를 끌어오지 않습니다.
 *==================================================================*/
static int str_eq(const char *a, const char *b)
{
    while (*a && *b) { if (*a != *b) return 0; a++; b++; }
    return *a == *b;
}

static int is_space(char c) { return c == ' ' || c == '\t'; }

static char upper(char c) { return (c >= 'a' && c <= 'z') ? (char)(c - 32) : c; }

/* 10진수 기본, 0x 접두사는 16진수, 앞의 - 는 음수.
 * 실패하면 0 을 반환하고 *ok 를 0 으로 만듭니다. */
static int parse_num(const char *s, int *ok)
{
    int neg = 0;
    long v = 0;
    int digits = 0;

    *ok = 0;
    if (*s == '-') { neg = 1; s++; }
    else if (*s == '+') { s++; }

    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X')) {
        s += 2;
        while (*s) {
            char c = upper(*s);
            int d;
            if (c >= '0' && c <= '9')      d = c - '0';
            else if (c >= 'A' && c <= 'F') d = c - 'A' + 10;
            else return 0;
            v = v * 16 + d;
            digits++; s++;
        }
    } else {
        while (*s) {
            if (*s < '0' || *s > '9') return 0;
            v = v * 10 + (*s - '0');
            digits++; s++;
        }
    }

    if (!digits) return 0;
    *ok = 1;
    return neg ? (int)(-v) : (int)v;
}

/*====================================================================
 * UART 한 줄 읽기
 *
 * 사람이 직접 칠 수 있어야 하므로 에코를 넣고 백스페이스를 받습니다.
 * CR 과 LF 를 둘 다 줄 끝으로 봅니다 -- 터미널마다 다릅니다.
 *==================================================================*/
#ifdef BBHT_CONSOLE_SCRIPT
/*
 * 스크립트 모드 -- RTL 시뮬 전용입니다. 보드 빌드에는 들어가지 않습니다.
 *
 * RVX 의 시뮬 printf 모듈(ncsim_printf.v)은 uart_tx 를 1 로 묶어 둡니다.
 * 보낼 쪽이 없으니 read_line() 의 rx_data_ready 폴링이 영원히 안 풀리고,
 * 그래서 SoC RTL 시뮬에서 콘솔 앱이 첫 명령도 못 받고 멈춥니다.
 *
 * 그것을 피하려고 명령을 컴파일 시점에 박아 넣습니다. UART 경로 코드는
 * 그대로 두었습니다 -- 이 매크로를 정의하지 않으면 보드 빌드는 한 바이트도
 * 달라지지 않습니다.
 *
 * 명령 목록은 -DBBHT_CONSOLE_SCRIPT_LINES='"A","B",...' 로 넘기거나,
 * 안 넘기면 아래 기본 순서를 씁니다. 마지막 QUIT 이 시뮬을 끝냅니다.
 */
#ifndef BBHT_CONSOLE_SCRIPT_LINES
#define BBHT_CONSOLE_SCRIPT_LINES                                             \
    "ID",                                                                     \
    "GEN COUNT=16384 TARGETS=4 VAL=12345 SEED=1",                             \
    "LOAD",                                                                   \
    "SET MODE=EQ A=12345 AUTO=1 BURST=0 SEEDJ=0x7B1DCDAF SEEDM=0x24370DF2",   \
    "RUN",                                                                    \
    "STAT",                                                                   \
    "SET BURST=1",                                                            \
    "RUN",                                                                    \
    "STAT",                                                                   \
    "QUIT"
#endif

static const char *const script_lines[] = { BBHT_CONSOLE_SCRIPT_LINES };
static int script_pos = 0;

/* 한 줄씩 돌려줍니다. 다 쓰면 QUIT 을 계속 냅니다. */
static void read_line(char *buf, int max)
{
    const char *s;
    int n = 0;

    s = (script_pos < (int)(sizeof(script_lines) / sizeof(script_lines[0])))
        ? script_lines[script_pos++]
        : "QUIT";

    while (s[n] && n < max - 1) { buf[n] = s[n]; n++; }
    buf[n] = '\0';

    /* 호스트가 보낸 것처럼 보이게 에코합니다 -- 트랜스크립트를 그대로
       bbht_cli.py --port replay 로 먹일 수 있게 하려는 것입니다. */
    printf("> %s\n", buf);
}
#else
static void read_line(char *buf, int max)
{
    int n = 0;

    for (;;) {
        char c;

        while (!uart_check_rx_data_ready(UART_IDX)) { }
        c = uart_read_rx_buffer(UART_IDX);

        if (c == '\r' || c == '\n') {
            uart_putc(UART_IDX, '\r');
            uart_putc(UART_IDX, '\n');
            buf[n] = '\0';
            return;
        }

        if (c == 8 || c == 127) {              /* BS / DEL */
            if (n > 0) {
                n--;
                uart_putc(UART_IDX, 8);
                uart_putc(UART_IDX, ' ');
                uart_putc(UART_IDX, 8);
            }
            continue;
        }

        if (c >= 32 && c < 127 && n < max - 1) {
            buf[n++] = c;
            uart_putc(UART_IDX, c);            /* 에코 */
        }
    }
}
#endif  /* BBHT_CONSOLE_SCRIPT */

/* 공백으로 자른 토큰을 최대 max 개까지. 원본을 제자리에서 자릅니다. */
static int split(char *line, char *tok[], int max)
{
    int n = 0;
    char *p = line;

    while (*p && n < max) {
        while (is_space(*p)) p++;
        if (!*p) break;
        tok[n++] = p;
        while (*p && !is_space(*p)) { *p = upper(*p); p++; }
        if (*p) *p++ = '\0';
    }
    return n;
}

/* "KEY=VAL" 을 둘로 가릅니다. '=' 가 없으면 0 을 반환합니다. */
static int split_kv(char *tok, char **key, char **val)
{
    char *p = tok;

    while (*p && *p != '=') p++;
    if (*p != '=') return 0;
    *p = '\0';
    *key = tok;
    *val = p + 1;
    return 1;
}

/*====================================================================
 * 데이터셋 생성
 *
 * PJK 벤치마크 하니스와 같은 xorshift32 입니다. 같은 시드면 같은 배열이
 * 나오므로, 보드에서 얻은 결과를 골든 모델과 대조할 수 있습니다.
 *==================================================================*/
static unsigned int xorshift32(unsigned int *state)
{
    unsigned int x = *state;

    if (x == 0u) x = 0x6D2B79F5u;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    return x;
}

static void gen_dataset(unsigned int count, unsigned int bg_seed,
                        unsigned int pos_seed, unsigned int targets, int value)
{
    unsigned int state = bg_seed;
    unsigned int i, placed = 0u, guard = 0u;

    /* 배경. 목표값과 같아지면 한 비트를 뒤집어 피합니다 -- 그래야 심은
     * 개수가 곧 정답 개수가 됩니다. */
    for (i = 0u; i < count; i++) {
        unsigned int v = xorshift32(&state) & 0xFFFFu;
        if (v == ((unsigned int)value & 0xFFFFu)) v ^= 1u;
        bbht_pack16(dataset, i, (int)v);
    }

    /* 목표를 심습니다. 겹치면 다시 뽑습니다. */
    state = pos_seed;
    while (placed < targets && guard < 100000u) {
        unsigned int idx = xorshift32(&state) % count;
        guard++;
        if (bbht_unpack16(dataset, idx) == (int)(short)value) continue;
        bbht_pack16(dataset, idx, value);
        placed++;
    }

    dataset_count = count;
    dataset_ready = 0u;
}

/*====================================================================
 * 명령 처리
 *==================================================================*/
static const char *pred_name(unsigned int p)
{
    switch (p) {
    case BBHT_PRED_LT:    return "LT";
    case BBHT_PRED_GT:    return "GT";
    case BBHT_PRED_EQ:    return "EQ";
    case BBHT_PRED_RANGE: return "RANGE";
    default:              return "?";
    }
}

static void cmd_help(void)
{
    printf("# ID                          펌웨어/하드웨어 식별\n");
    printf("# SET K=V ...                 MODE A B COUNT CAP SEEDJ SEEDM AUTO BURST J FAILLIM\n");
    printf("# SHOW                        현재 설정\n");
    printf("# GEN COUNT=n SEED=x POS=x TARGETS=n VAL=v   데이터셋 생성\n");
    printf("# POKE IDX=i VAL=v            한 칸 수정 (뒤에 LOAD 필요)\n");
    printf("# PEEK IDX=i                  한 칸 읽기 (보드 버퍼)\n");
    printf("# LOAD                        버퍼를 DMA 로 적재\n");
    printf("# RUN                         단일 탐색\n");
    printf("# ENUM                        열거\n");
    printf("# STAT                        마지막 실행 카운터/텔레메트리\n");
    printf("# REG                         CSR 덤프\n");
    printf("OK\n");
}

static void cmd_id(void)
{
    printf("STAT name=bbht_console csr_ver=%s\n", "0.9.8");
    printf("STAT csr_base=0x%08x q_bits=%d n_entries=%u fifo_depth=%u\n",
           (unsigned int)BBHT_CSR_BASE, BBHT_Q_BITS,
           BBHT_N_ENTRIES, BBHT_FIFO_DEPTH);
    printf("STAT accel_clk_hz=%u sram_base=0x%08x sram_last=0x%08x\n",
           BBHT_ACCEL_CLK_HZ, BBHT_SRAM_BASE, BBHT_SRAM_LAST);
    printf("STAT dataset_addr=0x%08x dataset_count=%u loaded=%u\n",
           (unsigned int)(unsigned long)dataset, dataset_count, dataset_ready);
    printf("OK\n");
}

static void cmd_show(void)
{
    printf("CFG mode=%s a=%d b=%d count=%u cap=%u\n",
           pred_name(cfg.predicate), cfg.threshold_a, cfg.threshold_b,
           cfg.data_count, cfg.shot_cap);
    printf("CFG auto=%u burst=%u j=%u faillim=%u seedj=0x%08x seedm=0x%08x\n",
           cfg.auto_shot, cfg.burst_enable, cfg.j_target, cfg.fail_limit,
           cfg.seed_j, cfg.seed_meas);
    printf("OK\n");
}

/* SET 의 키 하나를 처리합니다. 모르는 키면 0 을 반환합니다. */
static int apply_kv(const char *k, const char *v)
{
    int ok, n;

    if (str_eq(k, "MODE")) {
        if      (str_eq(v, "LT"))    cfg.predicate = BBHT_PRED_LT;
        else if (str_eq(v, "GT"))    cfg.predicate = BBHT_PRED_GT;
        else if (str_eq(v, "EQ"))    cfg.predicate = BBHT_PRED_EQ;
        else if (str_eq(v, "RANGE")) cfg.predicate = BBHT_PRED_RANGE;
        else return 0;
        return 1;
    }

    n = parse_num(v, &ok);
    if (!ok) return 0;

    if      (str_eq(k, "A"))       cfg.threshold_a  = n;
    else if (str_eq(k, "B"))       cfg.threshold_b  = n;
    else if (str_eq(k, "COUNT"))   cfg.data_count   = (unsigned int)n;
    else if (str_eq(k, "CAP"))     cfg.shot_cap     = (unsigned int)n;
    else if (str_eq(k, "SEEDJ"))   cfg.seed_j       = (unsigned int)n;
    else if (str_eq(k, "SEEDM"))   cfg.seed_meas    = (unsigned int)n;
    else if (str_eq(k, "AUTO"))    cfg.auto_shot    = n ? 1u : 0u;
    else if (str_eq(k, "BURST"))   cfg.burst_enable = n ? 1u : 0u;
    else if (str_eq(k, "J"))       cfg.j_target     = (unsigned int)n;
    else if (str_eq(k, "FAILLIM")) cfg.fail_limit   = (unsigned int)n;
    else return 0;

    return 1;
}

static void report_run(bbht_status_t rc)
{
    if (rc == BBHT_OK) {
        int val = (res.result_index < dataset_count)
                ? bbht_unpack16(dataset, res.result_index) : 0;
        printf("HIT idx=%u val=%d trials=%u l=%u iters=%u cyc=%u us=%u\n",
               res.result_index, val, res.trial_count, res.l_bbht,
               res.actual_iter, res.cycle_count,
               bbht_cycles_to_us(res.cycle_count));
        if (res.amp_overflow) printf("# amp_overflow (진단용, 결과는 유효)\n");
        printf("OK\n");
        return;
    }

    if (rc == BBHT_ERR_NOT_FOUND) {
        const char *why = (res.status & BBHT_ST_SHOT_LIMIT)   ? "SHOT_CAP"
                        : (res.status & BBHT_ST_BUDGET_LIMIT) ? "BUDGET"
                        : "NONE";
        printf("MISS reason=%s trials=%u cyc=%u us=%u\n",
               why, res.trial_count, res.cycle_count,
               bbht_cycles_to_us(res.cycle_count));
        printf("OK\n");
        return;
    }

    printf("ERR %s status=0x%08x\n", bbht_status_str(rc), res.status);
}

/*====================================================================*/
int main(void)
{
    char  line[LINE_MAX];
    char *tok[16];
    int   ntok, i;

    uart_init();

    bbht_config_init(&cfg);

    printf("\n");
    printf("# bbht_console -- HELP 를 치면 명령 목록이 나옵니다\n");

    if (bbht_probe() != BBHT_OK)
        printf("# 경고: CSR 응답이 이상합니다. 비트스트림과 base address 를 확인하십시오\n");

    printf("OK\n");

    for (;;) {
        read_line(line, LINE_MAX);
        ntok = split(line, tok, 16);

        if (ntok == 0) { printf("OK\n"); continue; }

        /*------------------------------------------------------------*/
#ifdef BBHT_CONSOLE_SCRIPT
        if (str_eq(tok[0], "QUIT")) {
            /* 시뮬을 끝냅니다. 보드 빌드에는 이 분기가 없습니다. */
            printf("OK\n");
            printf("# script done\n");
            return 0;
        }
#endif

        if (str_eq(tok[0], "HELP")) {
            cmd_help();

        } else if (str_eq(tok[0], "ID")) {
            cmd_id();

        } else if (str_eq(tok[0], "SHOW")) {
            cmd_show();

        /*------------------------------------------------------------*/
        } else if (str_eq(tok[0], "SET")) {
            int bad = 0;
            for (i = 1; i < ntok; i++) {
                char *k, *v;
                if (!split_kv(tok[i], &k, &v) || !apply_kv(k, v)) { bad = 1; break; }
            }
            if (bad) printf("ERR BAD_KV\n");
            else if (cfg.predicate == BBHT_PRED_RANGE &&
                     cfg.threshold_b <= cfg.threshold_a)
                printf("ERR RANGE_NEEDS_B_GT_A\n");
            else printf("OK\n");

        /*------------------------------------------------------------*/
        } else if (str_eq(tok[0], "GEN")) {
            unsigned int count = BBHT_N_ENTRIES, seed = 0x5EED1234u;
            unsigned int pos = 0xA17E2026u, targets = 1u;
            int value = 12345, bad = 0;

            for (i = 1; i < ntok; i++) {
                char *k, *v; int ok, n;
                if (!split_kv(tok[i], &k, &v)) { bad = 1; break; }
                n = parse_num(v, &ok);
                if (!ok) { bad = 1; break; }
                if      (str_eq(k, "COUNT"))   count   = (unsigned int)n;
                else if (str_eq(k, "SEED"))    seed    = (unsigned int)n;
                else if (str_eq(k, "POS"))     pos     = (unsigned int)n;
                else if (str_eq(k, "TARGETS")) targets = (unsigned int)n;
                else if (str_eq(k, "VAL"))     value   = n;
                else { bad = 1; break; }
            }

            if (bad)                              printf("ERR BAD_KV\n");
            else if (count == 0u || count > BBHT_N_ENTRIES)
                                                  printf("ERR BAD_COUNT\n");
            else if (targets > count)             printf("ERR TOO_MANY_TARGETS\n");
            else {
                gen_dataset(count, seed, pos, targets, value);
                cfg.data_count = count;
                printf("OK count=%u targets=%u val=%d\n", count, targets, value);
            }

        /*------------------------------------------------------------*/
        } else if (str_eq(tok[0], "POKE")) {
            unsigned int idx = 0u; int value = 0, bad = 0, got = 0;
            for (i = 1; i < ntok; i++) {
                char *k, *v; int ok, n;
                if (!split_kv(tok[i], &k, &v)) { bad = 1; break; }
                n = parse_num(v, &ok);
                if (!ok) { bad = 1; break; }
                if      (str_eq(k, "IDX")) { idx = (unsigned int)n; got |= 1; }
                else if (str_eq(k, "VAL")) { value = n;             got |= 2; }
                else { bad = 1; break; }
            }
            if (bad || got != 3)              printf("ERR BAD_KV\n");
            else if (idx >= BBHT_N_ENTRIES)   printf("ERR BAD_INDEX\n");
            else {
                bbht_pack16(dataset, idx, value);
                if (idx + 1u > dataset_count) dataset_count = idx + 1u;
                dataset_ready = 0u;
                printf("OK idx=%u val=%d\n", idx, value);
            }

        /*------------------------------------------------------------*/
        } else if (str_eq(tok[0], "PEEK")) {
            unsigned int idx = 0u; int bad = 0, got = 0;
            for (i = 1; i < ntok; i++) {
                char *k, *v; int ok, n;
                if (!split_kv(tok[i], &k, &v)) { bad = 1; break; }
                n = parse_num(v, &ok);
                if (!ok) { bad = 1; break; }
                if (str_eq(k, "IDX")) { idx = (unsigned int)n; got = 1; }
                else { bad = 1; break; }
            }
            if (bad || !got)                printf("ERR BAD_KV\n");
            else if (idx >= BBHT_N_ENTRIES) printf("ERR BAD_INDEX\n");
            else printf("STAT idx=%u val=%d\nOK\n", idx, bbht_unpack16(dataset, idx));

        /*------------------------------------------------------------*/
        } else if (str_eq(tok[0], "LOAD")) {
            bbht_status_t rc;
            if (dataset_count == 0u) { printf("ERR NO_DATASET\n"); continue; }
            rc = bbht_dma_load(dataset, dataset_count);
            if (rc == BBHT_OK) {
                dataset_ready = 1u;
                printf("OK loaded=%u addr=0x%08x\n",
                       dataset_count, (unsigned int)(unsigned long)dataset);
            } else {
                printf("ERR %s dma_status=0x%08x\n",
                       bbht_status_str(rc), bbht_rd(BBHT_DMA_STATUS));
            }

        /*------------------------------------------------------------*/
        } else if (str_eq(tok[0], "RUN")) {
            bbht_config_t local = cfg;
            if (!dataset_ready) { printf("ERR NOT_LOADED\n"); continue; }
            local.enum_enable = 0u;
            report_run(bbht_search_single(&local, &res));

        /*------------------------------------------------------------*/
        } else if (str_eq(tok[0], "ENUM")) {
            unsigned int n = 0u, k;
            bbht_status_t rc;
            if (!dataset_ready) { printf("ERR NOT_LOADED\n"); continue; }

            rc = bbht_search_enum(&cfg, enum_out, ENUM_OUT_MAX, &n, &res);
            if (rc != BBHT_OK && rc != BBHT_ERR_NOT_FOUND) {
                printf("ERR %s status=0x%08x\n", bbht_status_str(rc), res.status);
                continue;
            }
            for (k = 0u; k < n; k++)
                printf("FOUND idx=%u val=%d\n",
                       enum_out[k], bbht_unpack16(dataset, enum_out[k]));
            printf("END count=%u found=%u cyc=%u us=%u%s\n",
                   n, res.found_count, res.cycle_count,
                   bbht_cycles_to_us(res.cycle_count),
                   (n >= ENUM_OUT_MAX) ? " truncated=1" : "");
            printf("OK\n");

        /*------------------------------------------------------------*/
        } else if (str_eq(tok[0], "STAT")) {
            bbht_read_result(&res);
            printf("STAT status=0x%08x valid=%u idx=%u\n",
                   res.status, res.result_valid, res.result_index);
            printf("STAT trials=%u l_bbht=%u actual_iter=%u cyc=%u us=%u\n",
                   res.trial_count, res.l_bbht, res.actual_iter,
                   res.cycle_count, bbht_cycles_to_us(res.cycle_count));
            printf("STAT found=%u consec_fail=%u max_fifo=%u fifo_stall=%u\n",
                   res.found_count, res.consec_fail,
                   res.max_fifo_occ, res.fifo_stall);
            printf("STAT policy_cyc=%u stall=%u actions=%u memo_hit=%u memo_miss=%u\n",
                   res.policy_cycles, res.policy_stall, res.policy_actions,
                   res.policy_memo_hit, res.policy_memo_miss);
            printf("STAT plan_level=%u high=%u empty=%u hit=%u mismatch=%u\n",
                   res.plan_level, res.plan_highwater, res.plan_empty_demand,
                   res.plan_hit, res.plan_mismatch);
            printf("STAT cold_solve=%u spec_solve=%u max_latency=%u\n",
                   res.cold_solve, res.spec_solve, res.policy_max_latency);
            printf("OK\n");

        /*------------------------------------------------------------*/
        } else if (str_eq(tok[0], "REG")) {
            unsigned int off;
            for (off = 0u; off <= BBHT_POLICY_SPEC_SOLVE_COUNT; off += 4u) {
                /* FIFO_DATA 는 읽으면 pop 되므로 덤프에서 뺍니다. */
                if (off == BBHT_FIFO_DATA) {
                    printf("REG 0x%03x = (skip: read-to-pop)\n", off);
                    continue;
                }
                printf("REG 0x%03x = 0x%08x\n", off, bbht_rd(off));
            }
            printf("OK\n");

        /*------------------------------------------------------------*/
        } else {
            printf("ERR UNKNOWN_CMD\n");
        }
    }

    return 0;
}
