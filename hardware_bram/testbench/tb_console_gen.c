/*
 * tb_console_gen.c -- 콘솔 펌웨어의 GEN 생성기가 SW 생성기와 같은 배열을 내는가
 *
 * bbht_console 의 GEN PRED=... 은 firmware/bbht_console/src/bbht_dataset_gen.h
 * 를 씁니다. 그 헤더를 호스트 gcc 로 그대로 컴파일해서, Predicate500 기댓값
 * (software/experiments/predicate500_benchmark/expected/predicate500_datasets.csv)
 * 의 20개 데이터셋을 만들고 FNV-1a 와 정답 수를 맞댑니다. 보드나 SoC 시뮬
 * 없이 "보드가 만든 배열 = 기준모델이 쓴 배열" 을 확인하는 첫 관문입니다.
 * 보드에서는 호스트 프로그램이 SUM 명령으로 같은 비교를 한 번 더 합니다.
 *
 *   make -C hardware_bram/sim console-gen
 */
#include <stdio.h>
#include <string.h>

#include "bbht_grover_driver.h"
#include "bbht_dataset_gen.h"

/* 드라이버를 BBHT_HOST_TEST 로 컴파일하면 CSR 접근이 이 둘로 옵니다.
 * 생성기는 CSR 을 안 건드리므로 비워 둡니다. */
void bbht_host_wr(unsigned int off, unsigned int val) { (void)off; (void)val; }
unsigned int bbht_host_rd(unsigned int off) { (void)off; return 0u; }

static unsigned int words[BBHT_N_ENTRIES / 2];

static int pred_code(const char *s, unsigned int *mode)
{
    if (!strcmp(s, "LT"))    { *mode = BBHT_PRED_LT;    return 1; }
    if (!strcmp(s, "GT"))    { *mode = BBHT_PRED_GT;    return 1; }
    if (!strcmp(s, "EQ"))    { *mode = BBHT_PRED_EQ;    return 1; }
    if (!strcmp(s, "RANGE")) { *mode = BBHT_PRED_RANGE; return 1; }
    return 0;
}

int main(int argc, char **argv)
{
    char line[1024];
    int n = 0, bad = 0;
    FILE *f;

    if (argc != 2) { fprintf(stderr, "usage: %s predicate500_datasets.csv\n", argv[0]); return 2; }
    f = fopen(argv[1], "r");
    if (!f) { printf("FAIL: %s 를 못 엽니다\n", argv[1]); return 1; }
    if (!fgets(line, sizeof(line), f)) { printf("FAIL: 빈 파일\n"); return 1; }

    while (fgets(line, sizeof(line), f)) {
        char pred[8];
        int a, b;
        unsigned int m, bg, pos, want_fnv, got_fnv, hits, placed, mode;
        int rc;

        if (sscanf(line, "%7[^,],%d,%d,%u,0x%x,0x%x,%*[^,],0x%x",
                   pred, &a, &b, &m, &bg, &pos, &want_fnv) != 7) continue;
        if (!pred_code(pred, &mode)) { printf("FAIL: 술어 %s\n", pred); bad++; continue; }

        memset(words, 0, sizeof(words));
        rc = bbht_gen_dataset(words, BBHT_N_ENTRIES, mode, a, b, m, bg, pos, &placed);
        got_fnv = bbht_gen_fnv1a(words, BBHT_N_ENTRIES);
        hits = bbht_gen_count_hits(words, BBHT_N_ENTRIES, mode, a, b);
        n++;

        if (rc != BBHT_GEN_OK || got_fnv != want_fnv || hits != m || placed != m) {
            printf("  FAIL %-5s M=%-3u fnv 0x%08x (기댓값 0x%08x) hits=%u placed=%u rc=%d\n",
                   pred, m, got_fnv, want_fnv, hits, placed, rc);
            bad++;
        } else {
            printf("  ok   %-5s M=%-3u fnv 0x%08x hits=%u\n", pred, m, got_fnv, hits);
        }
    }
    fclose(f);

    if (n != 20) { printf("FAIL: 데이터셋이 %d 개입니다. 20 개여야 합니다\n", n); bad++; }
    printf("%s  (펌웨어 GEN 대 SW 생성기, %d 개 중 %d 개 어긋남)\n", bad ? "FAIL" : "PASS", n, bad);
    return bad ? 1 : 0;
}
