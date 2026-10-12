/*
 * bbht_k3h3.c : model 2, the K3/H3 restricted-B rolling checkpoint policy.
 *
 * Line-by-line port of the C++ model B (cpp/include/checkpoint_policy.hpp), itself a
 * port of the team reference model (checkpoint_bbht_model.py: _deposit_options,
 * _next_states, _window_cost, _select_policy_action, V098CheckpointReference.execute).
 * The policy only decides which states are kept and where a request resumes; it never
 * changes the requested j, so results, trial counts and L equal the Normal policy.
 *
 * Memory: at most 3 checkpoints plus the work state, like the RTL (4 slots).
 * - The work state is int32 (64 KB). As in the RTL, where the current state lives in
 *   its checkpoint slot, the checkpoint at the last request stays in the work buffer
 *   ("resident") and is packed only when the work buffer is needed for another state.
 * - Other checkpoints are packed to 24 bits per amplitude (4 amplitudes in 3 words,
 *   48 KB; |a| < 2^22 fits). With one checkpoint resident, at most 2 are packed.
 * - The uniform state (j = 0) is recomputed instead of stored.
 * - Each checkpoint keeps the CDF of its state (512 row sums, 4 KB), so a state
 *   measured again is not re-weighed: 3 x 4 KB.
 * Total 64 + 2 x 48 + 3 x 4 = 172 KB.
 *
 * Order per attempt (bbht_search.c): exact hit -> measure the kept state, nothing
 * else; miss -> future-j prediction, policy decision, state movement, iterations.
 */
#include "bbht_q14.h"

#if BBHT_ENABLE_K3H3

#define CAPACITY 3
#define HORIZON 3
#define MAXPOS 4          /* positions per state (CAPACITY, +1 spare) */
#define MAXOPT 32         /* candidate states per decision (<= 21 for K3) */
#define POOLMAX (1 + HORIZON)

typedef struct { uint8_t n; uint8_t v[MAXPOS]; } pos_t;   /* sorted ascending, values 0..128 */

/* ---------------------------------------------------------------- positions */
static int pos_has(const pos_t *p, int x)
{
    int i;
    for (i = 0; i < p->n; ++i)
        if (p->v[i] == x)
            return 1;
    return 0;
}

static void pos_sort(pos_t *p)
{
    int i, j;
    for (i = 1; i < p->n; ++i) {
        uint8_t x = p->v[i];
        for (j = i - 1; j >= 0 && p->v[j] > x; --j)
            p->v[j + 1] = p->v[j];
        p->v[j + 1] = x;
    }
}

/* std::vector<int> operator<: lexicographic, a proper prefix is smaller. */
static int pos_cmp(const pos_t *a, const pos_t *b)
{
    int i, n = a->n < b->n ? a->n : b->n;
    for (i = 0; i < n; ++i)
        if (a->v[i] != b->v[i])
            return a->v[i] < b->v[i] ? -1 : 1;
    return a->n < b->n ? -1 : (a->n > b->n ? 1 : 0);
}

static int closest_source(const pos_t *held, int request)
{
    int i, s = 0;
    for (i = 0; i < held->n; ++i)
        if (held->v[i] <= request && held->v[i] > s)
            s = held->v[i];
    return s;
}

/* All size-k combinations of items[0..n) in itertools order, appended to out. */
static void combinations(const uint8_t *items, int n, int k, pos_t *out, int *nout, int max)
{
    int idx[MAXPOS], i, j;
    if (k > n || k <= 0)
        return;
    for (i = 0; i < k; ++i)
        idx[i] = i;
    for (;;) {
        if (*nout < max) {
            pos_t *c = &out[(*nout)++];
            c->n = (uint8_t)k;
            for (i = 0; i < k; ++i)
                c->v[i] = items[idx[i]];
        }
        i = k - 1;
        while (i >= 0 && idx[i] == n - k + i)
            --i;
        if (i < 0)
            return;
        ++idx[i];
        for (j = i + 1; j < k; ++j)
            idx[j] = idx[j - 1] + 1;
    }
}

/* ------------------------------------------------------------------- solver */
typedef struct {
    int pool[POOLMAX];
    int npool;
    const int *window;
    int nwindow;
} ctx_t;

static void deposit_options(int source, int request, const ctx_t *cx, const pos_t *held,
                            pos_t *out, int *nout)
{
    uint8_t in_path[POOLMAX];
    int n_in = 0, i, size;
    pos_t combos[MAXOPT];
    for (i = 0; i < cx->npool; ++i) {
        int v = cx->pool[i], dup = 0, k;
        if (!(source < v && v < request) || pos_has(held, v))
            continue;
        for (k = 0; k < n_in; ++k)
            if (in_path[k] == v)
                dup = 1;
        if (!dup)
            in_path[n_in++] = (uint8_t)v;
    }
    {   /* sort in_path */
        pos_t t;
        t.n = (uint8_t)n_in;
        for (i = 0; i < n_in; ++i)
            t.v[i] = in_path[i];
        pos_sort(&t);
        for (i = 0; i < n_in; ++i)
            in_path[i] = t.v[i];
    }
    *nout = 0;
    out[0].n = 1;
    out[0].v[0] = (uint8_t)request;
    *nout = 1;
    for (size = 1; size < CAPACITY; ++size) {
        int nc = 0;
        if (size > n_in)
            break;
        combinations(in_path, n_in, size, combos, &nc, MAXOPT);
        for (i = 0; i < nc && *nout < MAXOPT; ++i) {
            pos_t *o = &out[(*nout)++];
            *o = combos[i];
            o->v[o->n++] = (uint8_t)request;      /* request > every in-path value: stays sorted */
        }
    }
}

static int pos_cmp_qsort(const pos_t *a, const pos_t *b) { return pos_cmp(a, b); }

static void next_states(const pos_t *held, int source, int request, const ctx_t *cx,
                        pos_t *out, int *nout)
{
    pos_t deposits[MAXOPT], keeps[MAXOPT];
    uint8_t keep_pool[MAXPOS];
    int nkeep = 0, nd = 0, i, j, k;

    for (i = 0; i < held->n; ++i)
        if (held->v[i] != request)
            keep_pool[nkeep++] = held->v[i];
    deposit_options(source, request, cx, held, deposits, &nd);
    *nout = 0;
    for (i = 0; i < nd; ++i) {
        const pos_t *d = &deposits[i];
        int room = CAPACITY - d->n;
        if (room <= 0) {
            if (*nout < MAXOPT)
                out[(*nout)++] = *d;
        } else if (nkeep <= room) {
            pos_t s = *d;
            for (k = 0; k < nkeep; ++k)
                s.v[s.n++] = keep_pool[k];
            pos_sort(&s);
            if (*nout < MAXOPT)
                out[(*nout)++] = s;
        } else {
            int nk = 0;
            combinations(keep_pool, nkeep, room, keeps, &nk, MAXOPT);
            for (j = 0; j < nk; ++j) {
                pos_t s = keeps[j];
                for (k = 0; k < d->n; ++k)
                    s.v[s.n++] = d->v[k];
                pos_sort(&s);
                if (*nout < MAXOPT)
                    out[(*nout)++] = s;
            }
        }
    }
    /* sort + unique (insertion sort: at most ~21 entries) */
    for (i = 1; i < *nout; ++i) {
        pos_t x = out[i];
        for (j = i - 1; j >= 0 && pos_cmp_qsort(&out[j], &x) > 0; --j)
            out[j + 1] = out[j];
        out[j + 1] = x;
    }
    for (i = 0, k = 0; i < *nout; ++i)
        if (k == 0 || pos_cmp(&out[k - 1], &out[i]) != 0)
            out[k++] = out[i];
    *nout = k;
}

/* Memo of window_cost within one decision (window and pool are fixed there).
 * Key: offset(2b) | n(2b) | 3 positions x 8b. The C++ model keys the same values. */
#define MEMO_SIZE 512u
static uint32_t g_memo_key[MEMO_SIZE];
static int32_t g_memo_val[MEMO_SIZE];
#define MEMO_EMPTY 0xFFFFFFFFu

static uint32_t memo_key(const pos_t *h, int offset)
{
    uint32_t key = ((uint32_t)offset << 30) | ((uint32_t)h->n << 28);
    int i;
    for (i = 0; i < h->n && i < 3; ++i)
        key |= (uint32_t)h->v[i] << (8 * i);
    return key;
}

static int32_t window_cost(const pos_t *held, int offset, const ctx_t *cx)
{
    pos_t states[MAXOPT];
    int n, i, request, source;
    int32_t best = 0x7FFFFFFF, immediate;
    uint32_t key, slot;

    if (offset >= cx->nwindow)
        return 0;
    key = memo_key(held, offset);
    slot = (key * 2654435761u) >> 23;               /* 9-bit hash */
    while (g_memo_key[slot] != MEMO_EMPTY) {
        if (g_memo_key[slot] == key)
            return g_memo_val[slot];
        slot = (slot + 1) & (MEMO_SIZE - 1);
    }
    request = cx->window[offset];
    source = closest_source(held, request);
    immediate = request - source;
    next_states(held, source, request, cx, states, &n);
    for (i = 0; i < n; ++i) {
        int32_t c = immediate + window_cost(&states[i], offset + 1, cx);
        if (c < best)
            best = c;
    }
    /* re-probe: the recursion may have filled slots */
    slot = (key * 2654435761u) >> 23;
    while (g_memo_key[slot] != MEMO_EMPTY)
        slot = (slot + 1) & (MEMO_SIZE - 1);
    g_memo_key[slot] = key;
    g_memo_val[slot] = best;
    return best;
}

/* _select_policy_action: source and the next checkpoint positions. */
static int select_action(const pos_t *held, int request, const int *future, int nfuture, pos_t *chosen)
{
    ctx_t cx;
    pos_t states[MAXOPT], best_state = {0, {0, 0, 0, 0}};
    int n, i, source, immediate, have = 0, best_segments = 0;
    int32_t best_cost = 0;
    uint32_t m;

    cx.npool = 0;
    cx.pool[cx.npool++] = request;
    for (i = 0; i < nfuture; ++i) {
        int k, dup = 0;
        for (k = 0; k < cx.npool; ++k)
            if (cx.pool[k] == future[i])
                dup = 1;
        if (!dup && cx.npool < POOLMAX)
            cx.pool[cx.npool++] = future[i];
    }
    cx.window = future;
    cx.nwindow = nfuture;
    for (m = 0; m < MEMO_SIZE; ++m)
        g_memo_key[m] = MEMO_EMPTY;

    source = closest_source(held, request);
    immediate = request - source;
    *chosen = *held;
    next_states(held, source, request, &cx, states, &n);
    for (i = 0; i < n; ++i) {
        int32_t tail = window_cost(&states[i], 0, &cx);
        int segments = 1, k, better;
        int32_t cost = immediate + tail;
        for (k = 0; k < states[i].n; ++k)
            if (source < states[i].v[k] && states[i].v[k] < request)
                ++segments;
        /* root tie-break (grover_policy.v): total cost, segments, sorted state */
        better = !have || cost < best_cost ||
                 (cost == best_cost && (segments < best_segments ||
                                        (segments == best_segments && pos_cmp(&states[i], &best_state) < 0)));
        if (better) {
            have = 1;
            best_cost = cost;
            best_segments = segments;
            best_state = states[i];
            *chosen = states[i];
        }
    }
    return source;
}

/* ------------------------------------------------------------- checkpoints */
#define NBUF 2
#define PACKED_WORDS (Q14_N / 4u * 3u)   /* 12288 words = 48 KB */
static uint32_t g_slot_mem[NBUF][PACKED_WORDS];
static int g_buf_used[NBUF];

enum { SLOT_UNIFORM = 0, SLOT_PACKED = 1, SLOT_RESIDENT = 2 };

typedef struct {
    int used;
    int pos;
    int kind;         /* SLOT_* */
    int buf;          /* packed buffer index (SLOT_PACKED) */
    int cdf_valid;    /* g_slot_cdf[slot] holds this state's CDF */
    int64_t osum;
} slot_t;

static slot_t g_slots[CAPACITY];
static bbht_cdf_t g_slot_cdf[CAPACITY];
static slot_t *g_view;   /* the slot to measure (the requested state) */

#ifdef BBHT_K3H3_STATS   /* host verification only: which paths ran */
unsigned long bbht_k3h3_stats[10];
#define STAT(i) (++bbht_k3h3_stats[i])
#else
#define STAT(i) ((void)0)
#endif

static int32_t sx24(uint32_t x) { return (int32_t)((x ^ 0x800000u) & 0xFFFFFFu) - 0x800000; }

static void pack4(const int32_t *a, uint32_t *w)
{
    uint32_t a0 = (uint32_t)a[0] & 0xFFFFFFu, a1 = (uint32_t)a[1] & 0xFFFFFFu;
    uint32_t a2 = (uint32_t)a[2] & 0xFFFFFFu, a3 = (uint32_t)a[3] & 0xFFFFFFu;
    w[0] = a0 | (a1 << 24);
    w[1] = (a1 >> 8) | (a2 << 16);
    w[2] = (a2 >> 16) | (a3 << 8);
}

static void unpack4(const uint32_t *w, int32_t *a)
{
    a[0] = sx24(w[0]);
    a[1] = sx24((w[0] >> 24) | (w[1] << 8));
    a[2] = sx24((w[1] >> 16) | (w[2] << 16));
    a[3] = sx24(w[2] >> 8);
}

static void pack_state(const int32_t *a, uint32_t *w)
{
    uint32_t i;
    for (i = 0; i < Q14_N; i += 4, w += 3)
        pack4(a + i, w);
}

static void unpack_state(const uint32_t *w, int32_t *a)
{
    uint32_t i;
    for (i = 0; i < Q14_N; i += 4, w += 3)
        unpack4(w, a + i);
}

/* work <-> packed buffer in one pass (no third buffer needed). */
static void swap_state(int32_t *a, uint32_t *w)
{
    uint32_t i;
    for (i = 0; i < Q14_N; i += 4, w += 3) {
        int32_t from_buf[4];
        unpack4(w, from_buf);
        pack4(a + i, w);
        a[i] = from_buf[0];
        a[i + 1] = from_buf[1];
        a[i + 2] = from_buf[2];
        a[i + 3] = from_buf[3];
    }
}

static const int32_t *row_from_packed(const void *src, uint32_t row, int32_t *tmp)
{
    const uint32_t *w = (const uint32_t *)src + row * (Q14_P / 4u * 3u);
    uint32_t l;
    for (l = 0; l < Q14_P; l += 4, w += 3)
        unpack4(w, tmp + l);
    return tmp;
}

void bbht_k3h3_invalidate(void)
{
    int i;
    for (i = 0; i < CAPACITY; ++i)
        g_slots[i].used = 0;
    for (i = 0; i < NBUF; ++i)
        g_buf_used[i] = 0;
    g_view = 0;
}

void bbht_k3h3_view(bbht_row_fetch_t *fetch, const void **src)
{
    if (!g_view || g_view->kind == SLOT_RESIDENT) {
        *fetch = bbht_row_from_array;
        *src = bbht_work;
    } else if (g_view->kind == SLOT_PACKED) {
        *fetch = row_from_packed;
        *src = g_slot_mem[g_view->buf];
    } else {
        *fetch = bbht_row_uniform;
        *src = 0;
    }
}

/* CDF of the state to measure: computed the first time the state is measured,
 * then reused while the checkpoint is kept (its amplitudes do not change). */
const bbht_cdf_t *bbht_k3h3_cdf(void)
{
    bbht_cdf_t *c = &g_slot_cdf[g_view - g_slots];
    if (!g_view->cdf_valid) {
        STAT(8);
        if (g_view->kind == SLOT_UNIFORM) {
            bbht_cdf_prepare_uniform(c);
        } else {
            bbht_row_fetch_t fetch;
            const void *src;
            bbht_k3h3_view(&fetch, &src);
            bbht_cdf_prepare_rows(fetch, src, c);
        }
        g_view->cdf_valid = 1;
    } else {
        STAT(9);
    }
    return c;
}

static slot_t *find_slot(int pos)
{
    int i;
    for (i = 0; i < CAPACITY; ++i)
        if (g_slots[i].used && g_slots[i].pos == pos)
            return &g_slots[i];
    return 0;
}

static slot_t *find_resident(void)
{
    int i;
    for (i = 0; i < CAPACITY; ++i)
        if (g_slots[i].used && g_slots[i].kind == SLOT_RESIDENT)
            return &g_slots[i];
    return 0;
}

static slot_t *add_slot(int pos, int kind)
{
    int i;
    for (i = 0; i < CAPACITY; ++i)
        if (!g_slots[i].used) {
            g_slots[i].used = 1;
            g_slots[i].pos = pos;
            g_slots[i].kind = kind;
            g_slots[i].buf = -1;
            g_slots[i].cdf_valid = 0;
            return &g_slots[i];
        }
    return 0;   /* cannot happen: next positions never exceed CAPACITY */
}

static int alloc_buf(int avoid)
{
    int i;
    for (i = 0; i < NBUF; ++i)
        if (!g_buf_used[i] && i != avoid) {
            g_buf_used[i] = 1;
            return i;
        }
    return -1;   /* cannot happen: at most 2 checkpoints are packed at any time */
}

/* Resident checkpoint -> its own packed buffer (the work buffer is about to change). */
static void evict_resident(slot_t *r, int avoid)
{
    r->buf = alloc_buf(avoid);
    pack_state(bbht_work, g_slot_mem[r->buf]);
    r->kind = SLOT_PACKED;
}

int bbht_k3h3_lookup(int requested)
{
    g_view = find_slot(requested);
    if (g_view)
        STAT(g_view->kind);                    /* 0 uniform, 1 packed, 2 resident */
    return g_view != 0;
}

int bbht_k3h3_execute(int requested, const int *future, int nfuture, int32_t *work, int64_t *work_osum,
                      const bbht_oracle_t *o, int *source_out, uint32_t *saturations)
{
    pos_t before, next;
    int i, source, cursor, src_kind = SLOT_UNIFORM, src_buf = -1;
    int64_t src_osum = 0;
    slot_t *s, *res;

    before.n = 0;
    for (i = 0; i < CAPACITY; ++i)
        if (g_slots[i].used)
            before.v[before.n++] = (uint8_t)g_slots[i].pos;
    pos_sort(&before);
    if (nfuture > HORIZON)
        nfuture = HORIZON;
    source = select_action(&before, requested, future, nfuture, &next);

    s = find_slot(source);                     /* where the iterations start */
    if (s) {
        src_kind = s->kind;
        src_buf = s->buf;
        src_osum = s->osum;
    }
    for (i = 0; i < CAPACITY; ++i)             /* drop checkpoints the policy does not keep */
        if (g_slots[i].used && !pos_has(&next, g_slots[i].pos)) {
            if (g_slots[i].kind == SLOT_PACKED)
                g_buf_used[g_slots[i].buf] = 0;   /* contents stay valid until reused */
            g_slots[i].used = 0;
        }

    res = find_resident();                     /* kept checkpoint still in the work buffer */
    if (src_kind == SLOT_RESIDENT) {
        if (res) {                             /* source itself is kept: keep a copy */
            STAT(3);
            evict_resident(res, -1);
        }
        *work_osum = src_osum;                 /* work already holds the source */
    } else if (src_kind == SLOT_PACKED) {
        if (res && !g_buf_used[src_buf]) {     /* source dropped: swap it with the resident */
            STAT(4);
            g_buf_used[src_buf] = 1;
            swap_state(work, g_slot_mem[src_buf]);
            res->kind = SLOT_PACKED;
            res->buf = src_buf;
        } else {
            if (res) {
                STAT(5);
                evict_resident(res, src_buf);
            }
            unpack_state(g_slot_mem[src_buf], work);
        }
        *work_osum = src_osum;
    } else if (requested > 0) {               /* from the uniform state */
        if (res) {
            STAT(6);
            evict_resident(res, -1);
        }
        bbht_state_reset(work, work_osum, o);
    }                                          /* requested == 0: the work buffer is not needed */

    if (pos_has(&next, 0) && !find_slot(0))
        add_slot(0, SLOT_UNIFORM);             /* uniform state: recomputed, not stored */

    cursor = source;
    for (i = 0; i < next.n; ++i) {
        int b = next.v[i], k;
        if (find_slot(b) || !(source < b && b <= requested))
            continue;
        for (k = cursor; k < b; ++k)
            bbht_core_opt_iterate(work, work_osum, o, saturations);
        if (b == requested) {
            s = add_slot(b, SLOT_RESIDENT);    /* stays in the work buffer */
        } else {
            STAT(7);
            s = add_slot(b, SLOT_PACKED);
            s->buf = alloc_buf(-1);
            pack_state(work, g_slot_mem[s->buf]);
        }
        s->osum = *work_osum;
        cursor = b;
    }
    g_view = find_slot(requested);             /* always kept: the request is always deposited */
    *source_out = source;
    return requested - source;
}

#endif
