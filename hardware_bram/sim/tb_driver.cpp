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
int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    top = new Vbbht_rvx_wrapper;

    printf("=== tb_driver : 드라이버 + RTL 회귀 ===\n");

    // 실제 System SRAM 과 같은 주소에 버퍼를 잡습니다. 여기가 안 잡히면
    // 드라이버의 범위 검사를 진짜로 돌릴 수 없으므로 그냥 멈춥니다.
    void *sram = mmap(reinterpret_cast<void *>(0xE0000000UL), 0x20000,
                      PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
    if (sram != reinterpret_cast<void *>(0xE0000000UL)) {
        printf("FAIL: 0xE0000000 에 mmap 실패\n");
        return 1;
    }
    unsigned int *words = static_cast<unsigned int *>(sram);
    memset(words, 0, 0x20000);

    // 리셋
    top->rstnn = 0;
    top->psel = 0; top->penable = 0; top->pwrite = 0;
    top->paddr = 0; top->pwdata = 0;
    top->shready = 1; top->shrdata = 0; top->shresp = 0;
    for (int i = 0; i < 8; i++) tick();
    top->rstnn = 1;
    for (int i = 0; i < 8; i++) tick();

    //-----------------------------------------------------------------
    printf("[D1] CSR probe\n");
    chk_rc("bbht_probe", bbht_probe(), BBHT_OK);

    //-----------------------------------------------------------------
    printf("[D2] pack16 / unpack16 (부호 확장 포함)\n");
    bbht_pack16(words, 0,  1234);
    bbht_pack16(words, 1, -5678);
    bbht_pack16(words, 2, -1);
    bbht_pack16(words, 3,  32767);
    chk("unpack16[0]", bbht_unpack16(words, 0),  1234);
    chk("unpack16[1]", bbht_unpack16(words, 1), -5678);
    chk("unpack16[2]", bbht_unpack16(words, 2), -1);
    chk("unpack16[3]", bbht_unpack16(words, 3),  32767);

    //-----------------------------------------------------------------
    printf("[D3] DMA 인자 검증 (하드웨어에 가기 전에 걸러야 함)\n");
    chk_rc("count=0",   bbht_dma_load(words, 0), BBHT_ERR_ARG);
    chk_rc("count>N",   bbht_dma_load(words, BBHT_N_ENTRIES + 1), BBHT_ERR_ARG);
    chk_rc("정렬 위반", bbht_dma_load(
               reinterpret_cast<unsigned int *>(
                   reinterpret_cast<uintptr_t>(words) + 2), 64), BBHT_ERR_ARG);
    chk_rc("범위 밖",   bbht_dma_load(
               reinterpret_cast<unsigned int *>(0xF0000000UL), 64), BBHT_ERR_ARG);

    //-----------------------------------------------------------------
    // 데이터셋: data[i] = i, 목표값 777 을 인덱스 100, 250, 999 에 심습니다.
    //-----------------------------------------------------------------
    const unsigned int NDATA = 1024;
    for (unsigned int i = 0; i < NDATA; i++)
        bbht_pack16(words, i, static_cast<int>(i));
    bbht_pack16(words, 100, 777);
    bbht_pack16(words, 250, 777);
    bbht_pack16(words, 999, 777);
    // data[777] 자체가 777 이라 정답이 넷이 됩니다. 값을 바꿔 셋으로 맞춥니다.
    bbht_pack16(words, 777, -777);

    printf("[D4] DMA 적재\n");
    chk_rc("bbht_dma_load", bbht_dma_load(words, NDATA), BBHT_OK);

    //-----------------------------------------------------------------
    printf("[D5] Single 탐색\n");
    bbht_config_t cfg;
    bbht_result_t res;

    bbht_config_init(&cfg);
    cfg.predicate   = BBHT_PRED_EQ;
    cfg.threshold_a = 777;
    cfg.data_count  = NDATA;

    chk_rc("bbht_search_single", bbht_search_single(&cfg, &res), BBHT_OK);
    // 정답이 셋이므로 어느 것이 나오는지는 Born 측정이 정합니다. 스텁은
    // 선형 스캔이라 늘 100 을 냈지만 실물은 셋 중 하나입니다. 집합만 봅니다.
    if (res.result_index == 100 || res.result_index == 250 || res.result_index == 999)
        printf("  ok   result_index in {100,250,999}  %u\n", res.result_index);
    else {
        printf("  FAIL result_index : got %u, {100,250,999} 밖\n", res.result_index);
        errors++;
    }
    chk("result_valid", res.result_valid, 1);
    if (res.cycle_count == 0) { printf("  FAIL cycle_count 가 0\n"); errors++; }
    else printf("  ok   cycle_count = %u (%u us)\n",
                res.cycle_count, bbht_cycles_to_us(res.cycle_count));

    //-----------------------------------------------------------------
    printf("[D6] 음수 임계값 -- 부호를 흘리면 여기서 걸립니다\n");
    cfg.threshold_a = -777;
    chk_rc("EQ(-777)", bbht_search_single(&cfg, &res), BBHT_OK);
    chk("result_index", res.result_index, 777);

    //-----------------------------------------------------------------
    printf("[D7] 해가 없을 때\n");
    cfg.threshold_a = 30000;
    chk_rc("EQ(30000)", bbht_search_single(&cfg, &res), BBHT_ERR_NOT_FOUND);
    chk("result_valid", res.result_valid, 0);

    //-----------------------------------------------------------------
    printf("[D8] 열거 -- FIFO drain\n");
    unsigned short out[64];
    unsigned int   n = 0;

    cfg.predicate   = BBHT_PRED_EQ;
    cfg.threshold_a = 777;
    cfg.fail_limit  = 4;
    chk_rc("bbht_search_enum", bbht_search_enum(&cfg, out, 64, &n, &res), BBHT_OK);
    chk("열거 개수", n, 3);
    if (n == 3) {
        // 순서는 발견 순서라 오름차순이 아닙니다. 집합만 확인합니다.
        int seen100 = 0, seen250 = 0, seen999 = 0, other = 0;
        for (unsigned int k = 0; k < n; k++) {
            if      (out[k] == 100) seen100 = 1;
            else if (out[k] == 250) seen250 = 1;
            else if (out[k] == 999) seen999 = 1;
            else                    other   = 1;
        }
        if (seen100 && seen250 && seen999 && !other)
            printf("  ok   열거 집합 {100,250,999} (순서 무관)\n");
        else {
            printf("  FAIL 열거 집합이 {100,250,999} 이 아님: %u %u %u\n",
                   out[0], out[1], out[2]);
            errors++;
        }
    }
    chk("FOUND_COUNT", res.found_count, 3);

    //-----------------------------------------------------------------
    printf("[D9] 열거 설정 오류 -- fail_limit 0\n");
    cfg.fail_limit = 0;
    chk_rc("fail_limit=0", bbht_search_enum(&cfg, out, 64, &n, &res), BBHT_ERR_ARG);
    cfg.fail_limit = 4;

    //-----------------------------------------------------------------
    printf("[D10] RANGE 술어\n");
    cfg.predicate   = BBHT_PRED_RANGE;
    cfg.threshold_a = 499;
    cfg.threshold_b = 501;              // 열린구간이므로 500 하나
    chk_rc("RANGE(499,501)", bbht_search_single(&cfg, &res), BBHT_OK);
    chk("result_index", res.result_index, 500);

    //-----------------------------------------------------------------
    printf("[D11] 사이클 -> 시간 환산\n");
    chk("100 사이클 = 1 us", bbht_cycles_to_us(100), 1);
    chk("1,000,000 사이클 = 10,000 us", bbht_cycles_to_us(1000000), 10000);

    //-----------------------------------------------------------------
    for (int i = 0; i < 10; i++) tick();
    printf("=== 결과: 오류 %d 건 (%llu 사이클) ===\n",
           errors, static_cast<unsigned long long>(main_time));
    printf("%s\n", errors == 0 ? "PASS" : "FAIL");

    top->final();
    delete top;
    return errors == 0 ? 0 : 1;
}
