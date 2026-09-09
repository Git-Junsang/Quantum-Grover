"""
K개 destructive checkpoint 문제의 정확 최적해 (평균비용 MDP).

모델
  상태 S_0..S_{m-1} 이 직선 위에 있고 전진만 가능. S_c -> S_j 비용 = j-c (j>=c).
  슬롯 K개. 각 슬롯은 어떤 S_c 를 담는다. S_0 은 언제나 공짜로 얻을 수 있다(재초기화).
  요청 j ~ U{0..m-1} 이 오면 슬롯 하나를 골라 S_j 까지 전진시킨다.
    - 고른 슬롯이 c <= j 면 비용 j-c
    - 고른 슬롯이 c >  j 면 0 으로 되돌린 뒤 전진하므로 비용 j + init_cost
  전진한 슬롯은 S_j 가 된다 (destructive).
  목표: 요청당 평균 비용 최소화.

풀이: 상태 = 슬롯 위치의 정렬된 K-튜플. 상대값 반복(relative value iteration).
"""
import itertools, sys
import numpy as np


def solve(m, K, init_cost=0.0, tol=1e-10, max_iter=20000):
    states = list(itertools.combinations_with_replacement(range(m), K))
    idx = {s: i for i, s in enumerate(states)}
    S = len(states)

    cost = np.empty((S, m, K), dtype=np.float32)
    nxt = np.empty((S, m, K), dtype=np.int32)
    for si, s in enumerate(states):
        for j in range(m):
            for a in range(K):
                c = s[a]
                cost[si, j, a] = (j - c) if c <= j else (j + init_cost)
                t = list(s)
                t[a] = j
                nxt[si, j, a] = idx[tuple(sorted(t))]

    h = np.zeros(S, dtype=np.float64)
    g = 0.0
    for _ in range(max_iter):
        q = cost + h[nxt]                 # (S, m, K)
        newh = q.min(axis=2).mean(axis=1)  # 요청 j 에 대한 기댓값
        g = newh[0]
        newh = newh - g
        if np.max(np.abs(newh - h)) < tol:
            h = newh
            break
        h = newh

    # 최적 정책과, 비교용 greedy(항상 pred(j) 사용) 정책의 평균비용
    q = cost + h[nxt]
    policy = q.argmin(axis=2)

    # greedy 정책 평가: c <= j 중 가장 큰 것, 없으면 가장 작은 슬롯을 리셋
    gact = np.empty((S, m), dtype=np.int32)
    for si, s in enumerate(states):
        for j in range(m):
            cands = [a for a in range(K) if s[a] <= j]
            gact[si, j] = max(cands, key=lambda a: s[a]) if cands else 0
    gcost = np.take_along_axis(cost, gact[:, :, None], axis=2)[:, :, 0]
    gnxt = np.take_along_axis(nxt, gact[:, :, None], axis=2)[:, :, 0]
    hg = np.zeros(S)
    gg = 0.0
    for _ in range(max_iter):
        newh = (gcost + hg[gnxt]).mean(axis=1)
        gg = newh[0]
        newh = newh - gg
        if np.max(np.abs(newh - hg)) < tol:
            hg = newh
            break
        hg = newh
    return g, gg, S, policy, states


if __name__ == "__main__":
    m = int(sys.argv[1]) if len(sys.argv) > 1 else 32
    base = (m - 1) / 2.0
    print(f"m = {m},  캐시 없음(매번 S_0 부터) = {base:.4f}")
    print(f"{'K':>2} {'상태수':>8} {'최적':>9} {'greedy':>9} {'최적 절감':>9} {'greedy 절감':>11} {'정적하한 m/(2(K+1))':>20}")
    for K in range(1, 5):
        g, gg, S, pol, st = solve(m, K)
        lb = m / (2.0 * (K + 1))
        print(f"{K:>2} {S:>8} {g:>9.4f} {gg:>9.4f} "
              f"{100*(1-g/base):>8.1f}% {100*(1-gg/base):>10.1f}% {lb:>20.4f}")
