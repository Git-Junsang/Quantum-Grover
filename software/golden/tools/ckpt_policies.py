import numpy as np, itertools

def build(m, K):
    states = list(itertools.combinations_with_replacement(range(m), K))
    idx = {s:i for i,s in enumerate(states)}
    S=len(states)
    cost=np.empty((S,m,K),dtype=np.float64); nxt=np.empty((S,m,K),dtype=np.int64)
    for si,s in enumerate(states):
        for j in range(m):
            for a in range(K):
                c=s[a]; cost[si,j,a]=(j-c) if c<=j else j
                t=list(s); t[a]=j; nxt[si,j,a]=idx[tuple(sorted(t))]
    return states, cost, nxt

def avg_cost(m, act, cost, nxt, iters=4000):
    """결정적 정책의 평균비용 = 정상분포 x 상태별 기대비용."""
    S=cost.shape[0]
    c=np.take_along_axis(cost, act[:,:,None],axis=2)[:,:,0]   # (S,m)
    n=np.take_along_axis(nxt , act[:,:,None],axis=2)[:,:,0]
    flat=n.ravel()
    v=np.full(S,1.0/S)
    for _ in range(iters):
        w=np.repeat(v/m, m)
        nv=np.bincount(flat, weights=w, minlength=S)
        if np.abs(nv-v).max()<1e-14: v=nv; break
        v=nv
    return float((v*c.mean(axis=1)).sum())

def optimal(m, K, cost, nxt, iters=6000):
    S=cost.shape[0]; h=np.zeros(S); g=0.0
    for _ in range(iters):
        newh=(cost+h[nxt]).min(axis=2).mean(axis=1); g=newh[0]; newh=newh-g
        if np.abs(newh-h).max()<1e-11: h=newh; break
        h=newh
    return g, (cost+h[nxt]).argmin(axis=2)

m=32; base=(m-1)/2
print(f"m={m},  캐시 없음 = {base:.3f}\n")
print(f"{'K':>2} {'최적':>8} {'절감':>7} | {'근접+최저리셋':>13} {'절감':>7} | {'근접+최고리셋':>13} {'절감':>7}")
for K in (1,2,3,4):
    states, cost, nxt = build(m,K); S=len(states)
    gA=np.empty((S,m),dtype=np.int64); gB=np.empty((S,m),dtype=np.int64)
    for si,s in enumerate(states):
        for j in range(m):
            cands=[a for a in range(K) if s[a]<=j]
            if cands:
                a=max(cands,key=lambda a:s[a]); gA[si,j]=a; gB[si,j]=a
            else:
                gA[si,j]=0; gB[si,j]=K-1
    vA=avg_cost(m,gA,cost,nxt); vB=avg_cost(m,gB,cost,nxt)
    opt,pol=optimal(m,K,cost,nxt)
    f=lambda x:100*(1-x/base)
    print(f"{K:>2} {opt:>8.3f} {f(opt):>6.1f}% | {vA:>13.3f} {f(vA):>6.1f}% | {vB:>13.3f} {f(vB):>6.1f}%")
