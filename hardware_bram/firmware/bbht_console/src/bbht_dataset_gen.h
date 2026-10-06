/*
 * bbht_dataset_gen.h -- 보드 위 데이터셋 생성기 (GEN 명령) 와 해시 (SUM 명령)
 *
 * software/models/common/benchmark_dataset.py 의 generate_predicate_image() /
 * fnv1a32_s16() 과 한 쌍입니다. 같은 인자면 바이트 단위로 같은 배열이 나와야
 * 하고, 그래야 호스트가 32 KiB 데이터셋을 UART 로 보내지 않고도 보드 결과를
 * SW 기준모델 기댓값과 맞댈 수 있습니다. 한쪽을 고치면 다른 쪽도 고치십시오.
 * 대조는 `make -C hardware_bram/sim console-gen` 이 이 헤더를 호스트 gcc 로
 * 컴파일해 20개 데이터셋의 FNV-1a 를 기댓값 CSV 와 맞대는 것으로 합니다.
 *
 * RVX 헤더에 기대지 않습니다. 저장은 드라이버의 bbht_pack16 / bbht_unpack16
 * 만 씁니다 (word[k][15:0] = data[2k], [31:16] = data[2k+1]).
 *
 * 규칙 (값은 모두 부호 있는 16비트, mod 는 음이 아닌 나머지)
 *   배경  raw = xorshift32(bg) & 0xFFFF 를 차례로 뽑아
 *         EQ    raw == A(16비트)이면 raw ^= 1
 *         LT    s <  A    이면 s = A + ((s + 32768) mod (32768 - A))   -> [A, 32767]
 *         GT    s >  A    이면 s = -32768 + ((s - A - 1) mod (A + 32769)) -> [-32768, A]
 *         RANGE A < s < B 이면 s = B + ((s - A - 1) mod (32768 - B))      -> [B, 32767]
 *         그래서 배경은 어느 칸도 술어를 만족하지 않습니다.
 *   목표  위치 = xorshift32(pos) mod count, 이미 목표인 칸이면 건너뜀.
 *         값 = EQ 이면 A, 아니면 lo + (xorshift32(val) mod size), val 시드는
 *         pos ^ 0x9E3779B9. 구간은 LT [-32768, A-1] GT [A+1, 32767]
 *         RANGE [A+1, B-1].
 *
 * EQ 는 2026-09-01 부터 쓰던 GEN 과 규칙이 같습니다. 기본 시드
 * (SEED 0x5EED1234, POS 0xA17E2026, A 12345)로 만들면 보드 500런·Common500 의
 * 공식 데이터셋과 같은 바이트가 나옵니다.
 */
#ifndef BBHT_DATASET_GEN_H
#define BBHT_DATASET_GEN_H

#include "bbht_grover_driver.h"

#define BBHT_GEN_VALUE_SEED_MIX  0x9E3779B9u
#define BBHT_GEN_GUARD           100000u

/* 반환 코드 */
#define BBHT_GEN_OK              0
#define BBHT_GEN_BAD_THRESHOLD  -1   /* 목표 구간이 비었거나 16비트 밖 */
#define BBHT_GEN_BAD_COUNT      -2
#define BBHT_GEN_GUARD_HIT      -3   /* 목표를 다 못 심음 (TARGETS 가 너무 큼) */

static unsigned int bbht_gen_xorshift32(unsigned int *state)
{
    unsigned int x = *state;

    if (x == 0u) x = 0x6D2B79F5u;
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    return x;
}

/* RTL grover_predicate 와 같은 부호 있는 비교. */
static int bbht_gen_pred_hit(unsigned int mode, int v, int a, int b)
{
    switch (mode) {
    case BBHT_PRED_LT:    return v < a;
    case BBHT_PRED_GT:    return v > a;
    case BBHT_PRED_EQ:    return v == a;
    case BBHT_PRED_RANGE: return (v > a) && (v < b);
    default:              return 0;
    }
}

/* 목표 구간 [lo, lo + size). 비었으면 0 을 돌려줍니다. */
static int bbht_gen_target_span(unsigned int mode, int a, int b, int *lo, int *size)
{
    if (a < -32768 || a > 32767 || b < -32768 || b > 32767) return 0;
    switch (mode) {
    case BBHT_PRED_LT:
        if (a == -32768) return 0;
        *lo = -32768; *size = a + 32768; return 1;
    case BBHT_PRED_GT:
        if (a == 32767) return 0;
        *lo = a + 1;  *size = 32767 - a; return 1;
    case BBHT_PRED_RANGE:
        if (b - a < 2) return 0;
        *lo = a + 1;  *size = b - a - 1; return 1;
    case BBHT_PRED_EQ:
        *lo = a;      *size = 1;         return 1;
    default:
        return 0;
    }
}

/*
 * words 에 count 칸을 만듭니다. *placed 에 실제로 심은 목표 수를 적습니다.
 */
static int bbht_gen_dataset(unsigned int *words, unsigned int count,
                            unsigned int mode, int a, int b,
                            unsigned int targets,
                            unsigned int bg_seed, unsigned int pos_seed,
                            unsigned int *placed)
{
    unsigned int state, vstate, i, guard = 0u, n = 0u;
    int lo, size;

    *placed = 0u;
    if (!bbht_gen_target_span(mode, a, b, &lo, &size)) return BBHT_GEN_BAD_THRESHOLD;
    if (count == 0u || count > BBHT_N_ENTRIES || targets > count) return BBHT_GEN_BAD_COUNT;

    /* 배경 */
    state = bg_seed;
    for (i = 0u; i < count; i++) {
        unsigned int raw = bbht_gen_xorshift32(&state) & 0xFFFFu;
        int s;

        if (mode == BBHT_PRED_EQ) {
            if (raw == ((unsigned int)a & 0xFFFFu)) raw ^= 1u;
            bbht_pack16(words, i, (int)raw);
            continue;
        }
        s = (raw & 0x8000u) ? (int)raw - 65536 : (int)raw;
        if (mode == BBHT_PRED_LT && s < a)
            s = a + (s + 32768) % (32768 - a);
        else if (mode == BBHT_PRED_GT && s > a)
            s = -32768 + (s - a - 1) % (a + 32769);
        else if (mode == BBHT_PRED_RANGE && s > a && s < b)
            s = b + (s - a - 1) % (32768 - b);
        bbht_pack16(words, i, s);
    }

    /* 목표 */
    state  = pos_seed;
    vstate = pos_seed ^ BBHT_GEN_VALUE_SEED_MIX;
    while (n < targets && guard < BBHT_GEN_GUARD) {
        unsigned int idx = bbht_gen_xorshift32(&state) % count;
        guard++;
        if (bbht_gen_pred_hit(mode, bbht_unpack16(words, idx), a, b)) continue;
        if (mode == BBHT_PRED_EQ) {
            bbht_pack16(words, idx, a);
        } else {
            unsigned int x = bbht_gen_xorshift32(&vstate);
            bbht_pack16(words, idx, lo + (int)(x % (unsigned int)size));
        }
        n++;
    }
    *placed = n;
    return (n == targets) ? BBHT_GEN_OK : BBHT_GEN_GUARD_HIT;
}

/* 16비트 값을 little-endian 바이트로 늘어놓은 FNV-1a 32. */
static unsigned int bbht_gen_fnv1a(const unsigned int *words, unsigned int count)
{
    unsigned int h = 0x811C9DC5u, i;

    for (i = 0u; i < count; i++) {
        unsigned int v = (unsigned int)bbht_unpack16(words, i) & 0xFFFFu;
        h ^= v & 0xFFu;        h *= 0x01000193u;
        h ^= (v >> 8) & 0xFFu; h *= 0x01000193u;
    }
    return h;
}

/* 술어를 만족하는 칸 수 (앞 count 칸). */
static unsigned int bbht_gen_count_hits(const unsigned int *words, unsigned int count,
                                        unsigned int mode, int a, int b)
{
    unsigned int i, n = 0u;

    for (i = 0u; i < count; i++)
        if (bbht_gen_pred_hit(mode, bbht_unpack16(words, i), a, b)) n++;
    return n;
}

#endif /* BBHT_DATASET_GEN_H */
