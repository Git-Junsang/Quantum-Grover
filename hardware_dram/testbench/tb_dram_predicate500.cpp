//=====================================================================
// tb_dram_predicate500.cpp -- DRAM 갈래 Predicate500 (네 술어 x 500 워크로드)
//
// hardware_bram/testbench/tb_predicate500.cpp 의 DRAM 짝입니다. 자극 목록,
// 시드, 실행 순서, 드라이버 호출, CSV 형식이 같고 다른 것은 셋입니다.
//
//   1. 최상단이 tb_dram_axi_sys (bbht_dram_axi_top + axi4_mem_model) 입니다.
//      보드에 들어가는 RTL(통신 계층 + DRAM Main IP + AXI 브리지)을 그대로
//      실제 드라이버로 두드리고, AXI 뒤쪽만 모델입니다
//   2. 모드는 NORMAL 하나입니다. 이 갈래에는 체크포인트가 없고 burst_enable
//      은 계약 호환용으로 무시됩니다. 물리 반복은 기준모델의 DRAM_ALL_J 열과
//      맞댑니다 (predicate500_report.py --branch dram)
//   3. 끝에 AXI 모델의 심판 결과(프로토콜 위반, 안 쓴 워드 읽기)와 브리지의
//      axi_error 를 찍고, 하나라도 있으면 errors 에 더합니다
//=====================================================================
#include "Vtb_dram_axi_sys.h"
#include "verilated.h"

#include <sys/mman.h>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>

extern "C" {
#include "bbht_grover_driver.h"
}

static Vtb_dram_axi_sys *top;
static vluint64_t main_time = 0;

// AHB 슬레이브 상태: 주소 위상을 한 사이클 미뤄 데이터 위상으로 넘깁니다.
static bool     ahb_pending = false, ahb_next_pending = false;
static uint32_t ahb_addr = 0,        ahb_next_addr = 0;

static void half_low(void)
{
    top->clk = 0;
    top->eval();

    top->shready = 1;
    top->shresp  = 0;
    top->shrdata = ahb_pending
                 ? *reinterpret_cast<uint32_t *>(static_cast<uintptr_t>(ahb_addr))
                 : 0;
    top->eval();

    ahb_next_pending = (top->shtrans == 2);
    ahb_next_addr    = top->shaddr;
}

static void half_high(void)
{
    top->clk = 1;
    top->eval();
    ahb_pending = ahb_next_pending;
    ahb_addr    = ahb_next_addr;
    main_time++;
}

static void tick(void) { half_low(); half_high(); }

// APB 마스터. pready 가 상수 1 이라 access 위상이 한 사이클입니다.
extern "C" void bbht_host_wr(unsigned int off, unsigned int val)
{
    top->psel = 1; top->penable = 0; top->pwrite = 1;
    top->paddr = off; top->pwdata = val;
    tick();
    top->penable = 1;
    tick();
    top->psel = 0; top->penable = 0; top->pwrite = 0;
}

extern "C" unsigned int bbht_host_rd(unsigned int off)
{
    unsigned int d;

    top->psel = 1; top->penable = 0; top->pwrite = 0;
    top->paddr = off;
    tick();
    top->penable = 1;
    half_low();
    d = top->prdata;              // FIFO_DATA 는 완료 posedge 에서 pop 됩니다
    half_high();
    top->psel = 0; top->penable = 0;
    return d;
}

//=====================================================================
#define NDATA  16384
#define NSEED  100
#define NWL    32

struct SeedPair { unsigned int j, meas; };
struct Workload { char pred[8]; unsigned int code; int a, b, m; char path[512]; };

static short    g_data[NDATA];
static SeedPair g_seeds[NSEED];
static Workload g_wl[NWL];
static int      g_nseed = 0, g_nwl = 0;

static int load_seeds(void)
{
    char path[512];
    snprintf(path, sizeof(path), "%s/seeds.txt", getenv("WL_DIR"));
    FILE *f = fopen(path, "r");
    if (!f) { printf("FAIL: %s 를 못 엽니다\n", path); return -1; }
    while (g_nseed < NSEED &&
           fscanf(f, "%u %u", &g_seeds[g_nseed].j, &g_seeds[g_nseed].meas) == 2)
        g_nseed++;
    fclose(f);
    return (g_nseed > 0) ? 0 : -1;
}

static int load_list(void)
{
    const char *list = getenv("WL_LIST");
    if (!list) { printf("FAIL: WL_LIST 가 없습니다\n"); return -1; }
    FILE *f = fopen(list, "r");
    if (!f) { printf("FAIL: %s 를 못 엽니다\n", list); return -1; }
    while (g_nwl < NWL) {
        Workload &w = g_wl[g_nwl];
        if (fscanf(f, "%7s %u %d %d %d %511s",
                   w.pred, &w.code, &w.a, &w.b, &w.m, w.path) != 6)
            break;
        g_nwl++;
    }
    fclose(f);
    return (g_nwl > 0) ? 0 : -1;
}

static int load_data(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f) { printf("FAIL: %s 를 못 엽니다\n", path); return -1; }
    size_t n = fread(g_data, sizeof(short), NDATA, f);
    fclose(f);
    if (n != NDATA) { printf("FAIL: %s 크기 이상 (%zu)\n", path, n); return -1; }
    return 0;
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    top = new Vtb_dram_axi_sys;

    void *sram = mmap(reinterpret_cast<void *>(0xE0000000UL), 0x20000,
                      PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
    if (sram != reinterpret_cast<void *>(0xE0000000UL)) {
        printf("FAIL: 0xE0000000 에 mmap 실패\n"); return 1;
    }
    unsigned int *words = static_cast<unsigned int *>(sram);
    memset(words, 0, 0x20000);

    if (load_seeds() != 0 || load_list() != 0) return 1;

    top->rstnn = 0;
    top->psel = 0; top->penable = 0; top->pwrite = 0;
    top->paddr = 0; top->pwdata = 0;
    top->shready = 1; top->shrdata = 0; top->shresp = 0;
    for (int i = 0; i < 8; i++) tick();
    top->rstnn = 1;
    for (int i = 0; i < 8; i++) tick();

    if (bbht_probe() != BBHT_OK) { printf("FAIL: probe\n"); return 1; }

    printf("predicate,m,seed_idx,mode,rc,result_index,result_value,trial,l_bbht,"
           "iter,cycles,status\n");

    int errors = 0;
    for (int wi = 0; wi < g_nwl; wi++) {
        const Workload &w = g_wl[wi];
        if (load_data(w.path) != 0) return 1;
        memcpy(words, g_data, sizeof(g_data));
        if (bbht_dma_load(words, NDATA) != BBHT_OK) {
            printf("FAIL: dma_load %s M=%d\n", w.pred, w.m); return 1;
        }
        for (int s = 0; s < g_nseed; s++) {
            for (int mode = 0; mode < 1; mode++) {
                bbht_config_t cfg; bbht_result_t res;
                bbht_config_init(&cfg);
                cfg.predicate    = w.code;
                cfg.threshold_a  = w.a;
                cfg.threshold_b  = w.b;
                cfg.data_count   = NDATA;
                cfg.shot_cap     = 100;
                cfg.seed_j       = g_seeds[s].j;
                cfg.seed_meas    = g_seeds[s].meas;
                cfg.auto_shot    = 1;
                cfg.burst_enable = 0;         /* 이 갈래는 무시합니다 */
                cfg.enum_enable  = 0;
                bbht_status_t rc = bbht_search_single(&cfg, &res);
                if (rc != BBHT_OK && rc != BBHT_ERR_NOT_FOUND) errors++;
                int found = (rc == BBHT_OK);
                printf("%s,%d,%d,%s,%s,%d,%d,%u,%u,%u,%u,0x%08x\n",
                       w.pred, w.m, s, mode ? "ckpt" : "normal",
                       bbht_status_str(rc),
                       found ? (int)res.result_index : -1,
                       found ? (int)g_data[res.result_index] : 0,
                       res.trial_count, res.l_bbht, res.actual_iter,
                       res.cycle_count, res.status);
                fflush(stdout);
            }
        }
        fprintf(stderr, "%s M=%d 완료\n", w.pred, w.m);
    }
    if (top->mem_err_count != 0 || top->axi_error) {
        printf("FAIL: AXI 모델 오류 %u 건, 브리지 axi_error=%u\n",
               (unsigned)top->mem_err_count, (unsigned)top->axi_error);
        errors++;
    }
    printf("# AXI wr_bursts=%u rd_bursts=%u mem_err=%u axi_error=%u frontier_j=%u\n",
           (unsigned)top->mem_wr_bursts, (unsigned)top->mem_rd_bursts,
           (unsigned)top->mem_err_count, (unsigned)top->axi_error,
           (unsigned)top->frontier_j);
    printf("# DONE errors=%d\n", errors);
    return 0;
}
