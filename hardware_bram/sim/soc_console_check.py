#!/usr/bin/env python3
"""
soc_console_check.py -- SoC RTL 시뮬에서 돈 bbht_console 트랜스크립트 검사기

RVX 플랫폼 전체를 Questa 로 돌리면 bbht_console 이 스크립트 모드로 명령을 받고
응답을 UART 로 냅니다. 이 스크립트는 그 출력을 호스트 CLI(software/host/bbht_cli.py)
의 재생 트랜스포트에 그대로 먹이고, 파싱한 숫자를 기준과 맞댑니다.

  make -C hardware_bram/sim console-seq          # 기준 CSV (30초쯤)
  python3 hardware_bram/sim/soc_console_check.py \\
      $RVX_MINI_HOME/platform/bbht_grover_upgrade/sim_rtl/qtsim.log \\
      --ref /tmp/sjs_console_seq/console_seq.csv \\
      --transcript transcript.txt --out crosscheck.txt

무엇을 보나

  1. 명령 순서. 호스트가 보낸 명령과 펌웨어가 에코한 명령이 한 줄도 어긋나지 않는가.
     보낼 명령은 main.c 의 BBHT_CONSOLE_SCRIPT_LINES 에서 읽습니다 -- 스크립트를
     고치면 이 검사도 따라갑니다.
  2. 종결자. 일부러 넣은 두 줄(적재 전 RUN, 틀린 SET MODE)만 ERR 이고 나머지는 OK.
  3. ID 가 보고한 상수가 CSR 정본과 같은가 (bbht_cli.py selftest).
  4. 워크로드. POKE 한 칸이 dataset_target_M.bin 의 12345 자리와 같고, SEEDJ/SEEDM 이
     보드 로스터의 몇 번 시드인지. 둘 다 스크립트에서 알아냅니다.
  5. 같은 순서의 verilator 기준(--ref, testbench/tb_console_seq.cpp). RUN · STAT ·
     ENUM 의 숫자 전부가 한 칸도 다르지 않아야 합니다. 사이클까지 맞대는 곳은
     여기뿐입니다.
  6. 이미 있는 근거와의 대조. 체크포인트 사이클은 실행 이력에 달려 있어서 기준마다
     맞댈 수 있는 축이 다릅니다.
       - NORMAL 은 정책 엔진을 안 써서 이력과 무관합니다. bench500 · SoC paper_bench
         행과 사이클까지 맞댑니다.
       - 리셋 뒤 첫 체크포인트 탐색은 6단계 캠페인(워크로드마다 새로 시작)과
         사이클까지 맞댑니다. 연달아 도는 bench500 과의 차이는 전부 policy_stall
         이어야 합니다 (정책 memo 를 지우는 3,279 사이클).
       - 그다음 체크포인트 탐색은 직전 탐색이 달라서 사이클이 어느 근거와도 같을
         이유가 없습니다. 논리 4축(result_index · trial_count · L_BBHT ·
         actual_iter)을 보드 M2 · bench500 · SoC paper_bench 와 맞대고, bench500 과의
         사이클 차이가 policy_stall 차이와 같은지만 봅니다.
  7. ENUM 이 낸 인덱스가 전부 심은 목표 자리인가.

종료 코드는 어긋난 항목 수입니다 (0 이면 통과).
"""

import argparse
import csv
import io
import os
import re
import struct
import sys
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
HW = os.path.normpath(os.path.join(HERE, os.pardir))          # hardware_bram
ROOT = os.path.normpath(os.path.join(HW, os.pardir))          # 저장소 루트

sys.path.insert(0, os.path.join(ROOT, "software", "host"))
import bbht_cli                                                 # noqa: E402

MAIN_C = os.path.join(HW, "firmware", "bbht_console", "src", "main.c")
DATASETS = os.path.join(ROOT, "software", "experiments", "common500_benchmark",
                        "inputs", "datasets")
BENCH500 = os.path.join(HW, "results", "2026-09-10_bench500_final_core",
                        "per_workload.csv")
BOARD_M2 = os.path.join(HW, "vivado", "vivado_bbht_grover_fpga",
                        "2026-09-08_k3h3_e4_m2_board_500run", "per_run_m2.csv")
SOC_BENCH = os.path.join(HW, "results", "2026-09-16_soc_rtl_paper_bench",
                         "per_run.csv")
STAGE6 = os.path.join(HW, "results", "2026-09-08_publication_6stage",
                      "observations.csv")

VALUE = 12345          # 보드 워크로드의 목표값 (tb_bench500.cpp 와 같음)

# 콘솔 출력 키 -> 기준 CSV 열 (tb_console_seq.cpp 가 같은 이름을 씁니다)
HIT_KEYS = [("result_index", "idx"), ("trial_count", "trials"), ("L_BBHT", "l"),
            ("actual_iter", "iters"), ("cycle_count", "cyc")]
STAT_KEYS = ["idx", "trials", "l_bbht", "actual_iter", "cyc", "policy_cyc", "stall",
             "actions", "memo_hit", "memo_miss", "cold_solve", "spec_solve",
             "mismatch", "max_latency", "empty"]


# ---------------------------------------------------------------------
def script_lines():
    """main.c 의 기본 스크립트를 순서대로."""
    with open(MAIN_C, encoding="utf-8") as f:
        src = f.read()
    m = re.search(r"#define\s+BBHT_CONSOLE_SCRIPT_LINES\s*\\\n((?:.*\\\n)*.*\n)", src)
    if not m:
        sys.exit("main.c 에서 BBHT_CONSOLE_SCRIPT_LINES 를 못 찾았습니다")
    return re.findall(r'"([^"]*)"', m.group(1))


def extract_transcript(path):
    """qtsim.log 면 콘솔 출력 부분만 떼어 Questa 의 '# ' 머리말을 벗깁니다.
    이미 떼어 둔 트랜스크립트면 그대로 돌려줍니다.

    콘솔 자신의 주석 줄('# script done')도 Questa 로그에서는 '#' 하나로 보여서
    머리말과 구별되지 않습니다. 그래서 응답은 종결자와 태그(HIT STAT ...)로만
    읽고 나머지 줄은 보지 않습니다."""
    with open(path, encoding="utf-8", errors="replace") as f:
        lines = [l.rstrip("\r\n") for l in f]
    start = next((i for i, l in enumerate(lines) if "[RVX/START]" in l), None)
    if start is None:
        return lines
    out = []
    for l in lines[start + 1:]:
        # 코어가 끝났다는 RVX 표시부터는 콘솔 출력이 아닙니다.
        if "[PROC_STATUS]" in l or l.startswith("# ** Note: $finish"):
            break
        out.append(l[2:] if l.startswith("# ") else l.lstrip("#"))
    return out


def terminator(lines):
    """응답에서 마지막 OK/ERR 줄. 뒤에 붙는 주석 줄은 건너뜁니다."""
    for l in reversed(lines):
        if l.split(None, 1)[:1] in (["OK"], ["ERR"]):
            return l
    return lines[-1] if lines else "(무응답)"


def kv_of(lines, tag):
    d = {}
    for l in lines:
        if l.split(None, 1)[:1] == [tag]:
            d.update(bbht_cli.parse_kv_line(l)[1])
    return d


def csv_rows(path):
    with open(path, newline="") as f:
        return [row for row in csv.DictReader(f)
                if not next(iter(row.values()), "").startswith("#")]


def num(v):
    return int(v) if v not in (None, "") else None


# ---------------------------------------------------------------------
class Report:
    def __init__(self):
        self.lines, self.bad = [], 0

    def say(self, s=""):
        self.lines.append(s)

    def check(self, name, got, want):
        ok = got == want
        self.bad += 0 if ok else 1
        self.say("  %s %-38s %-14s %s" % ("일치" if ok else "다름", name, got,
                                           "" if ok else "(기대 %s)" % want))

    def axes(self, title, got, want, pairs):
        """pairs = [(표시 이름, got 키, want 키), ...]."""
        n = sum(1 for _, g, w in pairs if got.get(g) == num(want.get(w)))
        self.say("%s  %d/%d" % (title, n, len(pairs)))
        for label, g, w in pairs:
            self.check(label, got.get(g), num(want.get(w)))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("log", help="sim_rtl/qtsim.log 또는 떼어 둔 트랜스크립트")
    ap.add_argument("--ref", required=True,
                    help="make console-seq 가 낸 기준 CSV (tb_console_seq.cpp)")
    ap.add_argument("--transcript", help="떼어 낸 트랜스크립트를 저장할 곳")
    ap.add_argument("--out", help="보고서를 저장할 곳")
    args = ap.parse_args()

    r = Report()
    text = extract_transcript(args.log)
    tpath = args.transcript or os.path.join(os.path.dirname(os.path.abspath(args.log)),
                                             "console_transcript.txt")
    with open(tpath, "w", encoding="utf-8") as f:
        f.write("\n".join(text) + "\n")

    cmds = script_lines()
    board = bbht_cli.Board(bbht_cli.ReplayTransport(tpath))

    # selftest 가 ID 를 스스로 보내므로 그 응답을 가로채 둡니다.
    last = {}
    orig_cmd = board.cmd

    def capture(line):
        last["lines"] = orig_cmd(line)
        return last["lines"]
    board.cmd = capture

    # 1~2. 명령을 스크립트 순서대로 보내고 응답을 모읍니다 ------------------
    r.say("=== 명령 %d 줄 재생 (bbht_cli.py ReplayTransport) ===" % len(cmds))
    replies, loaded, burst = [], False, None
    runs = []                  # [{"burst": b, "hit": {...}, "stat": {...}}, ...] 실행 순서
    selftest_out, selftest_bad = None, 0
    for i, c in enumerate(cmds):
        if i == 0 and c.upper() == "ID":
            buf = io.StringIO()
            with redirect_stdout(buf):
                selftest_bad = bbht_cli.selftest(board)
            selftest_out = buf.getvalue()
            lines = last["lines"]
        else:
            lines = board.cmd(c)
        replies.append(lines)
        term = terminator(lines)
        head = c.upper().split()[0]

        # 일부러 ERR 을 기대하는 두 경우
        expect_err = (head == "RUN" and not loaded) or \
                     (head == "SET" and re.search(r"MODE=(?!(LT|GT|EQ|RANGE)\b)", c.upper()))
        want = "ERR" if expect_err else "OK"
        got = term.split()[0] if term else ""
        ok = got == want and "REPLAY_" not in term
        r.bad += 0 if ok else 1
        r.say("  %s %-60s %s" % ("일치" if ok else "다름", "> " + c, term))

        if head == "LOAD" and got == "OK":
            loaded = True
        if head == "SET":
            m = re.search(r"BURST=(\d+)", c.upper())
            if m:
                burst = int(m.group(1))
        if head == "RUN" and got == "OK":
            runs.append({"burst": burst, "hit": kv_of(lines, "HIT"), "stat": {}})
        if head == "STAT" and runs:
            runs[-1]["stat"] = kv_of(lines, "STAT")

    # 3. ID 상수 ----------------------------------------------------------
    r.say()
    r.say("=== ID 응답 대 CSR 정본 (bbht_cli.py selftest) ===")
    if selftest_out is None:
        r.bad += 1
        r.say("  스크립트 첫 명령이 ID 가 아니라 대조하지 못했습니다")
    else:
        for l in selftest_out.rstrip().splitlines():
            r.say("  " + l)
        r.bad += selftest_bad

    # 4. 워크로드 식별 ----------------------------------------------------
    r.say()
    r.say("=== 워크로드 ===")
    pokes = sorted(int(re.search(r"IDX=(\d+)", c.upper()).group(1))
                   for c in cmds if c.upper().startswith("POKE"))
    M = len(pokes)
    with open(os.path.join(DATASETS, "dataset_target_%d.bin" % M), "rb") as f:
        data = struct.unpack("<16384h", f.read())
    targets = [i for i, v in enumerate(data) if v == VALUE]
    r.check("POKE 자리 = dataset_target_%d.bin 의 %d 자리" % (M, VALUE), pokes, targets)

    set_all = " ".join(c.upper() for c in cmds if c.upper().startswith("SET"))
    seed_j = int(re.search(r"SEEDJ=(0X[0-9A-F]+)", set_all).group(1), 16)
    seed_m = int(re.search(r"SEEDM=(0X[0-9A-F]+)", set_all).group(1), 16)
    board_row = next((row for row in csv_rows(BOARD_M2)
                      if int(row["target_count"]) == M
                      and int(row["seed_j"], 16) == seed_j
                      and int(row["seed_meas"], 16) == seed_m), None)
    if board_row is None:
        sys.exit("보드 로스터에서 M=%d seed_j=0x%08X seed_meas=0x%08X 를 못 찾았습니다"
                 % (M, seed_j, seed_m))
    sidx = int(board_row["seed_index"])
    r.say("  M = %d, 시드 %d (seed_j 0x%08X, seed_meas 0x%08X)" % (M, sidx, seed_j, seed_m))

    peek = kv_of(replies[next(i for i, c in enumerate(cmds)
                              if c.upper().startswith("PEEK"))], "STAT")
    r.check("PEEK 이 돌려준 값", peek.get("val"), VALUE)
    load = bbht_cli.parse_kv_line(terminator(replies[cmds.index("LOAD")]))[1]
    r.check("LOAD 적재 항목 수", load.get("loaded"), 16384)

    # 5~6. 숫자 대조 ------------------------------------------------------
    ref = {row["step"]: row for row in csv_rows(args.ref)}
    b500 = {row["mode"]: row for row in csv_rows(BENCH500)
            if int(row["m"]) == M and int(row["seed_idx"]) == sidx}
    stage = next(row for row in csv_rows(STAGE6)
                 if int(row["target_count"]) == M and int(row["seed_index"]) == sidx
                 and row["stage"] == "K3/H3-E4-M2")
    soc_rows = csv_rows(SOC_BENCH) if os.path.exists(SOC_BENCH) else []

    five_b500 = list(zip([n for n, _ in HIT_KEYS], [k for _, k in HIT_KEYS],
                         ["result_index", "trial", "l_bbht", "iter", "cycles"]))
    five_run = list(zip([n for n, _ in HIT_KEYS], [k for _, k in HIT_KEYS],
                        ["result_index", "trial_count", "l_bbht", "actual_iter",
                         "cycle_count"]))
    five_stage = list(zip([n for n, _ in HIT_KEYS], [k for _, k in HIT_KEYS],
                          ["result_index", "trial_count", "L_BBHT", "actual_iter",
                           "cycles"]))
    policy_b500 = [("policy_cycles", "policy_cyc", "policy_cycles"),
                   ("policy_stall", "stall", "policy_stall"),
                   ("policy_actions", "actions", "policy_actions"),
                   ("cold_solve", "cold_solve", "cold"),
                   ("spec_solve", "spec_solve", "spec"),
                   ("plan_mismatch", "mismatch", "mismatch")]

    n_ckpt = 0
    for k, run in enumerate(runs):
        b, hit, st = run["burst"], run["hit"], run["stat"]
        if b == 1:
            n_ckpt += 1
        title = ("BURST=0 NORMAL" if b == 0 else
                 "BURST=1 K3/H3-E4-M2, 리셋 뒤 %d 번째 체크포인트 탐색" % n_ckpt)
        r.say()
        r.say("=== RUN %d: %s ===" % (k + 1, title))
        if not hit:
            r.bad += 1
            r.say("  HIT 이 없습니다")
            continue

        # 5. 같은 순서의 verilator 기준 -- 전부 같아야 합니다
        want = ref.get("run%d" % (k + 1))
        if want is None:
            r.bad += 1
            r.say("  기준 CSV 에 run%d 이 없습니다" % (k + 1))
        else:
            r.check("기준과 BURST 같음", b, num(want["burst"]))
            r.axes("HIT 대 같은 순서 verilator (tb_console_seq)", hit, want,
                   [(n, key, col) for (n, key), col in
                    zip(HIT_KEYS, ["idx", "trials", "l_bbht", "actual_iter", "cyc"])])
            r.axes("STAT 대 같은 순서 verilator", st, want, [(s, s, s) for s in STAT_KEYS])

        # 6. 이미 있는 근거
        mode_name = "normal" if b == 0 else "k4"
        soc = next((row for row in soc_rows
                    if int(row["target_count"]) == M and int(row["seed_index"]) == sidx
                    and int(row["mode"]) == b), None)
        if b == 0:
            r.axes("HIT 대 bench500 normal 행 (이력 무관)", hit, b500["normal"], five_b500)
            r.axes("STAT 대 bench500 normal 행", st, b500["normal"], policy_b500)
            if soc:
                r.axes("HIT 대 SoC paper_bench mode0 행", hit, soc, five_run)
            continue

        d_cyc = hit["cyc"] - int(b500["k4"]["cycles"])
        d_stall = st.get("stall", 0) - int(b500["k4"]["policy_stall"])
        if n_ckpt == 1:
            r.axes("HIT 대 6단계 캠페인 K3/H3-E4-M2 (워크로드마다 새로 시작)",
                   hit, stage, five_stage)
        else:
            logic = five_b500[:4]
            r.axes("논리 4축 대 bench500 k4 행", hit, b500["k4"], logic)
            r.axes("논리 4축 대 보드 M2 실측 행", hit, board_row, five_run[:4])
            if soc:
                r.axes("논리 4축 대 SoC paper_bench mode1 행", hit, soc, five_run[:4])
        r.say("  bench500 k4 (연달아 실행) 대비 cycle %+d, policy_stall %+d"
              % (d_cyc, d_stall))
        r.check("cycle 차이 = policy_stall 차이", d_cyc, d_stall)

    # 7. ENUM -------------------------------------------------------------
    r.say()
    r.say("=== ENUM ===")
    ei = next((i for i, c in enumerate(cmds) if c.upper() == "ENUM"), None)
    if ei is not None:
        found = [bbht_cli.parse_kv_line(l)[1] for l in replies[ei]
                 if l.startswith("FOUND")]
        end = kv_of(replies[ei], "END")
        order = [f["idx"] for f in found]
        r.say("  FOUND %s" % order)
        r.check("FOUND 가 전부 심은 자리", all(i in targets for i in order), True)
        r.check("FOUND 값이 전부 %d" % VALUE, all(f["val"] == VALUE for f in found), True)
        r.check("FOUND 에 중복 없음", len(set(order)) == len(order), True)
        r.check("END count = FOUND 줄 수", end.get("count"), len(found))
        r.check("END found = FOUND 줄 수", end.get("found"), len(found))
        want = ref.get("enum")
        if want is None:
            r.bad += 1
            r.say("  기준 CSV 에 enum 이 없습니다")
        else:
            r.check("FOUND 순서 = 같은 순서 verilator", order,
                    [int(x) for x in want["enum_idx"].split()])
            r.check("END cyc = 같은 순서 verilator", end.get("cyc"), num(want["cyc"]))

    r.say()
    r.say("어긋남 %d 건" % r.bad)
    text_out = "\n".join(r.lines) + "\n"
    sys.stdout.write(text_out)
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(text_out)
    return r.bad


if __name__ == "__main__":
    sys.exit(min(main(), 255))
