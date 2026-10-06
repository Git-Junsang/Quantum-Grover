//=====================================================================
// tb_predicate500.cpp -- 네 술어 x 500 워크로드 벤치 (Predicate500)
//
// tb_bench500.cpp 는 EQ 술어 하나만 돕니다. 보드 500런과 Common500 이 EQ 뿐이라
// 그랬는데, 그러면 LT / GT / RANGE 비교기와 그 경로의 타이밍 컷이 실측 규모로
// 한 번도 검증되지 않습니다. 이 하네스는 같은 M 다섯 개 x 공식 시드 100쌍을
// 술어마다 따로 돌려 SW 기준모델의 기댓값과 맞댑니다.
//
//   자극   software/rtl_vectors/tools/dump_predicate500_workload.py 가 떨군
//          WL_DIR/workloads_<P>.txt 목록 (환경변수 WL_LIST 로 파일 하나를 지정)
//          한 줄 = "<P> <술어코드> <A> <B> <M> <bin 경로>"
//   기댓값 software/experiments/predicate500_benchmark/expected/
//          predicate500_expected.csv (predicate500_report.py 가 대조)
//
// 실행 순서는 보드 앱과 같습니다. 데이터셋 하나를 적재하고, 시드마다 Normal 다음
// 체크포인트를 같은 시드로 돌립니다. 목록 하나를 한 프로세스에서 연달아 돌기
// 때문에 체크포인트 준비 비용(리셋 뒤 첫 탐색의 memo 청소)은 목록마다 한 번만
// 냅니다. 술어별로 프로세스를 나눠 병렬로 돌려도 논리 궤적과 물리 반복은
// 이력과 무관하므로 대조에는 영향이 없습니다.
//
// 환경변수 PRED500_MODES 로 돌릴 모드를 고릅니다. "normal" 이면 Normal 만,
// 안 주거나 "both" 면 Normal 과 체크포인트 둘 다입니다. 체크포인트 없는 판
// (hardware_bram_nocheckpoint) 은 BURST 를 무시하므로 Normal 만 돌립니다.
//
// CSR 접근은 tb_bench500.cpp 와 같은 BBHT_HOST_TEST 갈래이고, 데이터셋 버퍼는
// 0xE0000000 에 mmap 해 실제 System SRAM 주소를 씁니다.
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
    top = new Vbbht_rvx_wrapper;

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

    // 모드 수: 2 = Normal + 체크포인트, 1 = Normal 만 (PRED500_MODES=normal)
    const char *modes_env = getenv("PRED500_MODES");
    int nmode = 2;
    if (modes_env && strcmp(modes_env, "normal") == 0) nmode = 1;
    else if (modes_env && strcmp(modes_env, "both") != 0 && modes_env[0]) {
        printf("FAIL: PRED500_MODES=%s (normal 또는 both)\n", modes_env); return 1;
    }

    int errors = 0;
    for (int wi = 0; wi < g_nwl; wi++) {
        const Workload &w = g_wl[wi];
        if (load_data(w.path) != 0) return 1;
        memcpy(words, g_data, sizeof(g_data));
        if (bbht_dma_load(words, NDATA) != BBHT_OK) {
            printf("FAIL: dma_load %s M=%d\n", w.pred, w.m); return 1;
        }
        for (int s = 0; s < g_nseed; s++) {
            for (int mode = 0; mode < nmode; mode++) {
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
                cfg.burst_enable = mode;      /* 0 = NORMAL, 1 = CKPT (K3/H3-E4-M2) */
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
    printf("# DONE errors=%d\n", errors);
    return 0;
}
