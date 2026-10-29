//=====================================================================
// tb_console_seq.cpp -- SoC 시뮬 bbht_console 스크립트와 같은 순서의 verilator 짝
//
// bbht_console 을 RVX SoC 전체 RTL 시뮬로 돌리면 사이클 수가 보드 500런의 같은
// 워크로드 행과 다르게 나옵니다. 탐색 궤적은 같은데 사이클만 다릅니다. 체크포인트
// 탐색의 사이클이 **그 전에 무엇을 돌았느냐**에 달려 있기 때문입니다.
//
//   - 리셋 뒤 첫 체크포인트 탐색은 정책 엔진이 memo BRAM 을 한 번 지웁니다
//     (grover_policy.v ST_CLEAR). 길이는 H_FUTURE x STATE_RANKS = 3 x 1093
//     = 3,279 사이클이고 전부 policy_stall 로 잡힙니다.
//   - 그 뒤의 탐색도 직전 탐색이 남긴 정책 엔진 상태에 따라 stall 이 달라집니다.
//
// 보드 앱과 bench500 은 M=1 시드 0 부터 Normal/체크포인트를 번갈아 연달아 돌고,
// 콘솔 스크립트는 리셋 직후 Normal -> 체크포인트 -> 체크포인트 순서입니다.
// 이력이 다르니 사이클을 맞댈 기준이 따로 있어야 합니다. 이 하네스가 그
// 기준입니다 -- 같은 통신 계층 · 어댑터 · Main IP 를 실제 드라이버로, 콘솔
// 스크립트와 **같은 순서로** 두드립니다.
//
// 순서는 firmware/bbht_console/src/main.c 의 BBHT_CONSOLE_SCRIPT_LINES 기본값을
// 그대로 옮긴 것입니다. 그쪽을 고치면 여기도 고치십시오.
//
//   리셋 -> DMA 적재(M=4) -> RUN BURST=0 -> RUN BURST=1 -> RUN BURST=1 -> ENUM
//   시드는 공식 로스터 0번, 술어 EQ 12345, 나머지는 bbht_config_init() 기본값
//
// 데이터셋은 콘솔과 다릅니다. 콘솔은 GEN 배경에 POKE 로 12345 네 칸을 심고,
// 여기는 보드 데이터셋 dataset_target_4.bin 을 그대로 씁니다. EQ 술어는 12345
// 인 칸만 보므로 둘은 오라클 표시가 칸마다 같습니다 -- 결과가 같으면 그것까지
// 확인되는 셈입니다.
//
// 출력은 CSV 한 벌이고 hardware_bram/sim/soc_console_check.py --ref 가 읽습니다.
//
// 아래 APB/AHB 모형과 워크로드 적재는 tb_bench500.cpp 와 같습니다.
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

//=====================================================================
// 워크로드 적재
//=====================================================================
#define NDATA  16384
#define NSEED  100

struct SeedPair { unsigned int j, meas; };

static short g_data[NDATA];
static SeedPair g_seeds[NSEED];
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
    while (g_nseed < NSEED &&
           fscanf(f, "%u %u", &g_seeds[g_nseed].j, &g_seeds[g_nseed].meas) == 2)
        g_nseed++;
    fclose(f);
    if (g_nseed != NSEED) {
        printf("FAIL: 시드가 %d쌍입니다. %d쌍이어야 합니다 "
               "(dump_bench_workload.py --seeds 100 으로 떨궜는지 보십시오)\n",
               g_nseed, NSEED);
        return -1;
    }
    return 0;
}

//---------------------------------------------------------------------
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

    printf("step,burst,rc,idx,trials,l_bbht,actual_iter,cyc,policy_cyc,stall,"
           "actions,memo_hit,memo_miss,cold_solve,spec_solve,mismatch,"
           "max_latency,empty,enum_idx\n");

    if (load_data(4) != 0) return 1;
    memcpy(words, g_data, sizeof(g_data));
    if (bbht_dma_load(words, NDATA) != BBHT_OK) {
        printf("FAIL: dma_load M=4\n"); return 1;
    }

    // 콘솔의 SET MODE=EQ A=12345 AUTO=1 BURST=0 SEEDJ=.. SEEDM=.. 과 같은 설정
    bbht_config_t cfg; bbht_result_t res;
    bbht_config_init(&cfg);
    cfg.predicate    = BBHT_PRED_EQ;
    cfg.threshold_a  = 12345;
    cfg.data_count   = NDATA;
    cfg.seed_j       = g_seeds[0].j;
    cfg.seed_meas    = g_seeds[0].meas;
    cfg.auto_shot    = 1;

    const unsigned int bursts[3] = {0u, 1u, 1u};
    for (int k = 0; k < 3; k++) {
        cfg.burst_enable = bursts[k];
        bbht_config_t local = cfg;        // 콘솔 RUN 과 같이 열거는 끕니다
        local.enum_enable = 0u;
        bbht_status_t rc = bbht_search_single(&local, &res);
        bbht_read_result(&res);           // 콘솔 STAT 과 같은 읽기
        printf("run%d,%u,%d,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,%u,\n",
               k + 1, bursts[k], (int)rc,
               res.result_index, res.trial_count, res.l_bbht, res.actual_iter,
               res.cycle_count, res.policy_cycles, res.policy_stall,
               res.policy_actions, res.policy_memo_hit, res.policy_memo_miss,
               res.cold_solve, res.spec_solve, res.plan_mismatch,
               res.policy_max_latency, res.plan_empty_demand);
    }

    // 콘솔 ENUM 은 마지막 SET 설정(BURST=1) 그대로 bbht_search_enum 을 부릅니다.
    unsigned short out[512];
    unsigned int n = 0u;
    bbht_status_t rc = bbht_search_enum(&cfg, out, 512u, &n, &res);
    printf("enum,%u,%d,,,,,%u,,,,,,,,,,,", cfg.burst_enable, (int)rc, res.cycle_count);
    for (unsigned int i = 0; i < n; i++) printf("%s%u", i ? " " : "", out[i]);
    printf("\n");
    printf("# DONE found=%u\n", res.found_count);
    return 0;
}
