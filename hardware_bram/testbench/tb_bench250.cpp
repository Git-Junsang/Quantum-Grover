//=====================================================================
// tb_driver.cpp -- 드라이버와 RTL 을 같이 돌리는 회귀
//
// tb_bbht_rvx.v 가 RTL 만 보는 데 비해, 이쪽은 실제 펌웨어가 쓸
// bbht_grover_driver.c 를 그대로 컴파일해 verilator 모델에 붙입니다.
// 그래서 여기서 잡히는 것은 "드라이버와 RTL 이 같은 계약을 보고 있는가"
// 입니다 -- 오프셋 하나가 어긋나거나, 폴링 순서가 틀리거나, 열거에서
// FIFO 를 흘리는 부류.
//
// CSR 접근은 BBHT_HOST_TEST 갈래로 bbht_host_rd/wr 에 연결됩니다.
// 데이터셋 버퍼는 0xE0000000 에 mmap 해서 실제 System SRAM 과 같은 주소를
// 씁니다. 그래야 드라이버의 범위 검사와 loader 의 범위 검사가 둘 다 진짜로
// 돌아갑니다.
//=====================================================================
#include "Vbbht_rvx_wrapper.h"
#include "verilated.h"

#include <sys/mman.h>
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>

extern "C" {
#include "bbht_grover_driver.h"
}

static Vbbht_rvx_wrapper *top;
static vluint64_t main_time = 0;

// AHB 슬레이브 상태: 주소 위상을 한 사이클 미뤄 데이터 위상으로 넘깁니다.
static bool     ahb_pending = false, ahb_next_pending = false;
static uint32_t ahb_addr = 0,        ahb_next_addr = 0;

static int errors = 0;

//---------------------------------------------------------------------
static void half_low(void)
{
    top->clk = 0;
    top->eval();

    // 데이터 위상: 직전 사이클에 잡아 둔 주소의 워드를 냅니다.
    top->shready = 1;
    top->shresp  = 0;
    top->shrdata = ahb_pending
                 ? *reinterpret_cast<uint32_t *>(static_cast<uintptr_t>(ahb_addr))
                 : 0;
    top->eval();

    // 이번 사이클의 주소 위상 (NONSEQ = 2'b10) 을 잡습니다.
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

//---------------------------------------------------------------------
// APB 마스터. pready 가 상수 1 이라 access 위상이 한 사이클입니다.
//---------------------------------------------------------------------
extern "C" void bbht_host_wr(unsigned int off, unsigned int val)
{
    top->psel = 1; top->penable = 0; top->pwrite = 1;
    top->paddr = off; top->pwdata = val;
    tick();                       // setup 위상
    top->penable = 1;
    tick();                       // access 위상. 이 posedge 에서 완료
    top->psel = 0; top->penable = 0; top->pwrite = 0;
}

extern "C" unsigned int bbht_host_rd(unsigned int off)
{
    unsigned int d;

    top->psel = 1; top->penable = 0; top->pwrite = 0;
    top->paddr = off;
    tick();                       // setup 위상
    top->penable = 1;
    half_low();                   // access 위상. 조합 출력이 확정됨
    d = top->prdata;             // 완료 posedge 이전에 샘플링해야 합니다.
                                  // FIFO_DATA 는 그 posedge 에서 pop 됩니다.
    half_high();
    top->psel = 0; top->penable = 0;
    return d;
}

//---------------------------------------------------------------------
static void chk(const char *name, long got, long exp)
{
    if (got != exp) {
        printf("  FAIL %-34s got %ld, expected %ld\n", name, got, exp);
        errors++;
    } else {
        printf("  ok   %-34s %ld\n", name, got);
    }
}

static void chk_rc(const char *name, bbht_status_t got, bbht_status_t exp)
{
    if (got != exp) {
        printf("  FAIL %-34s got %s, expected %s\n",
               name, bbht_status_str(got), bbht_status_str(exp));
        errors++;
    } else {
        printf("  ok   %-34s %s\n", name, bbht_status_str(got));
    }
}

//---------------------------------------------------------------------

//=====================================================================
// 250쌍 벤치 -- 보드 실측(2026-09-04 K4/H4)과 같은 워크로드를 RTL 로 재현
//
//   데이터셋 : build_official_board_benchmark_dataset(M), M in {1,4,16,64,256}
//   시드     : seed_roster_50.json 그대로 50쌍
//   각 쌍마다 Normal(burst_enable=0) 과 K4(burst_enable=1) 를 같은 시드로
//   돌려 paired 비교를 만듭니다. 보드 벤치가 쓴 방식과 같습니다.
//=====================================================================
#define NDATA 16384

struct SeedPair { unsigned int j, meas; };

static short g_data[NDATA];
static SeedPair g_seeds[50];
static int g_nseed = 0;

static int load_data(int M)
{
    char path[256];
    snprintf(path, sizeof(path), "%s/data_m%d.bin", getenv("WL_DIR"), M);
    FILE *f = fopen(path, "rb");
    if (!f) { printf("FAIL: %s 를 못 엽니다\n", path); return -1; }
    size_t n = fread(g_data, sizeof(short), NDATA, f);
    fclose(f);
    if (n != NDATA) { printf("FAIL: %s 크기 이상 (%zu)\n", path, n); return -1; }
    return 0;
}

static int load_seeds(void)
{
    char path[256];
    snprintf(path, sizeof(path), "%s/seeds.txt", getenv("WL_DIR"));
    FILE *f = fopen(path, "r");
    if (!f) { printf("FAIL: seeds.txt 를 못 엽니다\n"); return -1; }
    while (g_nseed < 50 &&
           fscanf(f, "%u %u", &g_seeds[g_nseed].j, &g_seeds[g_nseed].meas) == 2)
        g_nseed++;
    fclose(f);
    return (g_nseed == 50) ? 0 : -1;
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    top = new Vbbht_rvx_wrapper;

    void *sram = mmap(reinterpret_cast<void *>(0xE0000000UL), 0x20000,
                      PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
    if (sram != reinterpret_cast<void *>(0xE0000000UL)) {
        printf("FAIL: 0xE0000000 에 mmap 실패\n"); return 1;
    }
    unsigned int *words = static_cast<unsigned int *>(sram);
    memset(words, 0, 0x20000);

    if (load_seeds() != 0) return 1;

    top->rstnn = 0;
    top->psel = 0; top->penable = 0; top->pwrite = 0;
    top->paddr = 0; top->pwdata = 0;
    top->shready = 1; top->shrdata = 0; top->shresp = 0;
    for (int i = 0; i < 8; i++) tick();
    top->rstnn = 1;
    for (int i = 0; i < 8; i++) tick();

    if (bbht_probe() != BBHT_OK) { printf("FAIL: probe\n"); return 1; }

    printf("m,seed_idx,mode,result_index,trial,l_bbht,iter,cycles,"
           "policy_cycles,policy_stall,policy_actions,cold,spec,mismatch\n");

    const int Ms[5] = {1, 4, 16, 64, 256};
    for (int mi = 0; mi < 5; mi++) {
        int M = Ms[mi];
        if (load_data(M) != 0) return 1;
        memcpy(words, g_data, sizeof(g_data));
        if (bbht_dma_load(words, NDATA) != BBHT_OK) {
            printf("FAIL: dma_load M=%d\n", M); return 1;
        }
        for (int s = 0; s < g_nseed; s++) {
            for (int mode = 0; mode < 2; mode++) {
                bbht_config_t cfg; bbht_result_t res;
                bbht_config_init(&cfg);
                cfg.predicate    = BBHT_PRED_EQ;
                cfg.threshold_a  = 12345;
                cfg.data_count   = NDATA;
                cfg.shot_cap     = 100;
                cfg.seed_j       = g_seeds[s].j;
                cfg.seed_meas    = g_seeds[s].meas;
                cfg.auto_shot    = 1;
                cfg.burst_enable = mode;      /* 0=Normal, 1=K4 */
                cfg.enum_enable  = 0;
                cfg.fail_limit   = 4;
                bbht_status_t rc = bbht_search_single(&cfg, &res);
                printf("%d,%d,%s,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u\n",
                       M, s, mode ? "k4" : "normal",
                       (rc == BBHT_OK) ? res.result_index : 0xFFFFFFFFu,
                       res.trial_count, res.l_bbht, res.actual_iter,
                       res.cycle_count, res.policy_cycles, res.policy_stall,
                       res.policy_actions, res.cold_solve, res.spec_solve,
                       res.plan_mismatch);
                fflush(stdout);
            }
        }
        fprintf(stderr, "M=%d 완료\n", M);
    }
    printf("# DONE errors=%d\n", errors);
    return 0;
}
