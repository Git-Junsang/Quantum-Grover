/*
 * 서버 빌드용 대체 헤더. main.c 는 bbht_search() 앞뒤에서 get_real_clock_tick() 을 한 번씩 불러
 * 그 차이를 timer_hi/timer_lo 로 찍습니다. 보드에서는 1 us 틱 카운터입니다.
 *
 * 서버에서는 같은 실행 안에서 두 값을 같이 잽니다.
 *   반환값  CLOCK_MONOTONIC_RAW 의 us (보드 timer 와 같은 단위, SW_RUN 의 timer_hi/lo 로 찍힘)
 *   부수    이 스레드의 사용자 공간 코어 사이클(perf_event, PERF_COUNT_HW_CPU_CYCLES).
 *           호출 두 번(시작 · 끝)마다 차이를 모아 두었다가 프로그램이 끝날 때
 *           HOST_CYCLES,<순번>,<사이클> 줄로 찍습니다. 순번은 SW_RUN 줄 순서와 같습니다.
 * 시간용 · 사이클용을 따로 빌드하면 main.c 크기 차이로 함수 배치가 바뀌어 같은 계산이 ±20% 다르게
 * 걸리는 것을 확인해서(2026-10-11) 한 빌드로 합쳤습니다.
 */
#ifndef HOST_ERVP_REAL_CLOCK_H
#define HOST_ERVP_REAL_CLOCK_H
#include <linux/perf_event.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#define HOST_MAX_PAIRS 4096
static int host_cyc_fd = -1;
static uint64_t host_cyc_start;
static uint64_t host_cyc_delta[HOST_MAX_PAIRS];
static unsigned host_calls;

static void host_print_cycles(void)
{
    unsigned i;
    for (i = 0; i < host_calls / 2 && i < HOST_MAX_PAIRS; ++i)
        printf("HOST_CYCLES,%u,%llu\n", i, (unsigned long long)host_cyc_delta[i]);
}

static inline uint64_t host_read_cycles(void)
{
    uint64_t v = 0;
    if (read(host_cyc_fd, &v, sizeof v) != (ssize_t)sizeof v) {
        perror("read cycles");
        exit(2);
    }
    return v;
}

static inline uint64_t get_real_clock_tick(void)
{
    struct timespec t;
    uint64_t c;
    if (host_cyc_fd < 0) {
        struct perf_event_attr a;
        memset(&a, 0, sizeof a);
        a.type = PERF_TYPE_HARDWARE;
        a.size = sizeof a;
        a.config = PERF_COUNT_HW_CPU_CYCLES;
        a.exclude_kernel = 1;   /* 보드 쪽도 앱 코드만 셉니다 (커널 없음) */
        a.exclude_hv = 1;
        host_cyc_fd = (int)syscall(__NR_perf_event_open, &a, 0, -1, -1, 0);
        if (host_cyc_fd < 0) {
            perror("perf_event_open");
            exit(2);
        }
        atexit(host_print_cycles);
    }
    /* 시작 호출은 시간을 먼저, 끝 호출은 사이클을 먼저 읽어 두 구간이 서로의 읽기 비용을 덜 품게 합니다. */
    if ((host_calls & 1u) == 0) {
        clock_gettime(CLOCK_MONOTONIC_RAW, &t);
        host_cyc_start = host_read_cycles();
    } else {
        c = host_read_cycles();
        clock_gettime(CLOCK_MONOTONIC_RAW, &t);
        if (host_calls / 2 < HOST_MAX_PAIRS)
            host_cyc_delta[host_calls / 2] = c - host_cyc_start;
    }
    ++host_calls;
    return (uint64_t)t.tv_sec * 1000000u + (uint64_t)t.tv_nsec / 1000u;
}
#endif
