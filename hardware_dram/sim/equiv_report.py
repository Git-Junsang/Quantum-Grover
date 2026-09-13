#!/usr/bin/env python3
"""
tb_dram_core 로그 대조기.

같은 자극을 세 벌에 걸어 얻은 로그를 맞댑니다.

    dram      hardware_dram (DRAM 전량저장)
    bram      hardware_bram Normal (매 실행 처음부터 재계산)
    ckpt      hardware_bram checkpoint_auto (정본 K3/H3-E4-M2)

두 부류로 나눠서 봅니다.

  반드시 같아야 하는 것 -- 탐색 궤적
      valid / idx / trials / lbbht / cfgerr / shotlim / budlim
      진폭이 한 비트라도 어긋나면 측정 결과가 달라지고, 그러면 몇 번째
      시도에서 맞췄는지(trials)와 뽑은 j 의 합(lbbht)이 즉시 갈라집니다.
      그래서 이 일곱 개가 세 벌에서 같다는 것이 "hardware_dram 이 보드에서
      검증된 v0.9.8 과 같은 계산을 한다" 의 근거입니다.
      result_index 만 봐서는 안 됩니다. BBHT 가 후보를 술어로 자가 검증
      하므로 진폭이 깨져도 답 자체는 맞게 나옵니다.

  달라야 정상인 것 -- 비용
      iters (Grover 반복 수) 와 cyc (사이클). 이 차이가 곧 갈래의 이득이고,
      아래 표가 그걸 정리합니다.

    python3 equiv_report.py dram.log bram.log [ckpt.log]

같은 대조를 최상단 회귀(tb_bbht_dram_top)에도 씁니다. 그때는 두 로그가 둘 다
dram 갈래라 이름을 바꿔 줘야 표가 헷갈리지 않습니다.

    python3 equiv_report.py --names dram,top core_dram.log top.log

첫 이름이 비용 비교의 기준입니다. 이름 개수는 로그 개수와 같아야 합니다.
"""
import io
import re
import sys

CASE_RE = re.compile(
    r"^CASE (?P<label>.*?) "
    r"valid=(?P<valid>\d+) idx=(?P<idx>\d+) trials=(?P<trials>\d+) "
    r"lbbht=(?P<lbbht>\d+) cfgerr=(?P<cfgerr>\d+) shotlim=(?P<shotlim>\d+) "
    r"budlim=(?P<budlim>\d+) \| iters=(?P<iters>\d+) cyc=(?P<cyc>\d+)\s*$"
)

# 갈래마다 같아야 하는 항목.
TRAJ_KEYS = ["valid", "idx", "trials", "lbbht", "cfgerr", "shotlim", "budlim"]


def parse(path):
    """CASE 줄을 label 순서대로 뽑습니다."""
    order, rows = [], {}
    for line in io.open(path, encoding="utf-8", errors="replace"):
        m = CASE_RE.match(line.rstrip("\n"))
        if not m:
            continue
        label = m.group("label").strip()
        rows[label] = {k: int(m.group(k)) for k in m.groupdict() if k != "label"}
        order.append(label)
    if not rows:
        sys.exit("CASE 줄이 하나도 없습니다: %s" % path)
    return order, rows


def main():
    args = sys.argv[1:]
    names = None
    if args and args[0] == "--names":
        if len(args) < 2:
            sys.exit(__doc__)
        names = args[1].split(",")
        args = args[2:]
    if len(args) < 2:
        sys.exit(__doc__)
    if names is None:
        names = ["dram", "bram", "ckpt"][: len(args)]
    if len(names) != len(args):
        sys.exit("--names 개수(%d)와 로그 개수(%d)가 다릅니다" % (len(names), len(args)))

    logs = [parse(p) for p in args]
    base_order, base = logs[0]

    print("=" * 78)
    print("궤적 대조 -- %s 가 같은 답을 같은 경로로 내는가" % " / ".join(names))
    print("=" * 78)

    errors = 0
    common = []
    for label in base_order:
        present = [i for i, (_, rows) in enumerate(logs) if label in rows]
        if len(present) < len(logs):
            missing = ", ".join(names[i] for i in range(len(logs)) if i not in present)
            print("  --   %-28s (%s 에는 없는 케이스, 대조 제외)" % (label, missing))
            continue
        common.append(label)

        bad = []
        for key in TRAJ_KEYS:
            vals = [rows[label][key] for _, rows in logs]
            if len(set(vals)) != 1:
                bad.append("%s=%s" % (key, "/".join(str(v) for v in vals)))
        if bad:
            errors += 1
            print("  FAIL %-28s 갈라짐: %s" % (label, "  ".join(bad)))
        else:
            r = base[label]
            print("  ok   %-28s valid=%d idx=%-6d trials=%-3d L_BBHT=%d"
                  % (label, r["valid"], r["idx"], r["trials"], r["lbbht"]))

    print()
    print("=" * 78)
    print("비용 대조 -- 갈라져야 정상인 항목")
    print("=" * 78)
    head = "%-28s" % "케이스"
    for n in names:
        head += " %10s" % ("반복/" + n)
    for n in names:
        head += " %10s" % ("사이클/" + n)
    print(head)
    print("-" * len(head))

    totals = {n: {"iters": 0, "cyc": 0} for n in names}
    for label in common:
        row = "%-28s" % label
        for i, n in enumerate(names):
            v = logs[i][1][label]["iters"]
            totals[n]["iters"] += v
            row += " %10d" % v
        for i, n in enumerate(names):
            v = logs[i][1][label]["cyc"]
            totals[n]["cyc"] += v
            row += " %10d" % v
        print(row)

    print("-" * len(head))
    row = "%-28s" % "합계"
    for n in names:
        row += " %10d" % totals[n]["iters"]
    for n in names:
        row += " %10d" % totals[n]["cyc"]
    print(row)

    # dram 을 기준으로 나머지와의 차이를 백분율로. 기준이 0 이면 생략합니다.
    if len(names) > 1:
        print()
        for n in names[1:]:
            for field, unit in (("iters", "Grover 반복"), ("cyc", "사이클")):
                ref = totals[n][field]
                got = totals[names[0]][field]
                if ref == 0:
                    continue
                pct = (got - ref) * 100.0 / ref
                print("  %s 합계: %s %d vs %s %d  (%+.2f%%)"
                      % (unit, names[0], got, n, ref, pct))

    print()
    print("  주의: 위 사이클 수는 dram_burst_model 의 파라미터 지연으로 잰 값입니다.")
    print("        기본값(WR_LAT=4 RD_LAT=12 BEAT_GAP=0)은 실물 DDR3L + MIG 보다")
    print("        낙관적입니다. 물리 바인딩이 정해지기 전까지 이 사이클 수는")
    print("        상한이 아니라 하한으로만 읽어야 합니다. 반복 수(iters)는")
    print("        DRAM 지연과 무관하므로 그대로 인용해도 됩니다.")

    print()
    if errors:
        print("결과: 궤적이 갈라진 케이스 %d 건 -- FAIL" % errors)
        return 1
    print("결과: 대조한 %d 케이스 전부 궤적 일치 -- PASS" % len(common))
    return 0


if __name__ == "__main__":
    sys.exit(main())
