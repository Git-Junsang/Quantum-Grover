#!/usr/bin/env python3
"""
bbht_cli.py -- 호스트 PC 에서 BBHT/Grover 보드를 조작하는 CLI

보드의 bbht_console 앱과 UART 로 이야기합니다. 프로토콜 정본은
documents/design_references/UART_명령_프로토콜.md 입니다.

  대화형   python3 bbht_cli.py --port /dev/ttyUSB1
  일괄     python3 bbht_cli.py --port /dev/ttyUSB1 -c "GEN TARGETS=4" -c LOAD -c RUN
  스크립트 python3 bbht_cli.py --port /dev/ttyUSB1 --script exp.txt
  벤치마크 python3 bbht_cli.py --port /dev/ttyUSB1 bench --seeds 50 --targets 1,4,16,64,256

RTL 시뮬 트랜스크립트가 있으면 --port replay:<파일> 로 같은 파서에 먹일 수
있습니다. 보드 없이 호스트 파서를 진짜 펌웨어 응답으로 검증하는 길입니다.

보드가 없을 때는 --port mock 을 쓰십시오. 콘솔 앱과 같은 문법을 흉내 내는
파이썬 모델이 붙어서, 실험 스크립트와 파서를 미리 짜고 시험할 수 있습니다.
숫자는 진짜가 아니므로 결과를 인용하면 안 됩니다.
"""

import argparse
import csv
import os
import sys
import time

# CSR 정본에서 생성한 파이썬 상수. 옛 판은 `__file__.rsplit("/", 2)[0]` 로 경로를
# 잡았는데, 절대경로로 부르면 저장소 바깥을 가리켜 항상 ImportError 로 떨어졌습니다.
# 어떻게 불러도 같은 자리를 보도록 os.path 로 고쳤습니다.
_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.normpath(os.path.join(_HERE, os.pardir, os.pardir))
sys.path.insert(0, os.path.join(_REPO, "software", "contract", "generated"))

try:
    import bbht_grover_csr as CSR
except ImportError:                                     # 생성 전이면 없이도 돕니다
    CSR = None


# =====================================================================
# 트랜스포트
# =====================================================================
class SerialTransport:
    """실제 UART. 응답을 다 받은 뒤에 다음 명령을 보냅니다 -- 흐름 제어가
    없는 8N1 원시 스트림이라 밀어 넣으면 RX FIFO 가 넘칩니다."""

    def __init__(self, port, baud, timeout):
        try:
            import serial
        except ImportError:
            sys.exit("pyserial 이 필요합니다:  pip install pyserial\n"
                     "보드 없이 시험만 하려면 --port mock 을 쓰십시오.")
        # 포트를 열 때 DTR/RTS 가 켜지면 Arty 쪽에서 SoC 가 리셋되어 JTAG 로
        # 올려 둔 앱이 사라집니다 (2026-09-17 보드에서 확인: 열고 닫기만 해도
        # 다음 명령에 응답이 없음). 열기 전에 둘 다 내려 두어야 합니다.
        self.ser = serial.Serial()
        self.ser.port = port
        self.ser.baudrate = baud
        self.ser.timeout = 0.2
        self.ser.dtr = False
        self.ser.rts = False
        self.ser.open()
        self.timeout = timeout
        self.buf = ""

    def send(self, line):
        self.ser.reset_input_buffer()
        self.ser.write((line + "\n").encode("ascii", "replace"))
        self.ser.flush()

    def read_lines(self):
        """OK 또는 ERR 로 끝나는 응답 한 덩어리를 모아 돌려줍니다."""
        out, deadline = [], time.time() + self.timeout
        while time.time() < deadline:
            chunk = self.ser.read(256).decode("ascii", "replace")
            if not chunk:
                continue
            self.buf += chunk
            while "\n" in self.buf:
                line, self.buf = self.buf.split("\n", 1)
                line = line.strip("\r").strip()
                if not line:
                    continue
                out.append(line)
                if line.startswith("OK") or line.startswith("ERR"):
                    return out
        out.append("ERR HOST_TIMEOUT")
        return out

    def close(self):
        self.ser.close()


class MockTransport:
    """보드가 없을 때 쓰는 모델. 콘솔 앱의 문법과 응답 모양만 흉내 냅니다.

    탐색은 그로버가 아니라 선형 스캔이고 사이클 수도 지어낸 값입니다.
    문법과 파서를 시험하는 용도이지 성능을 재는 용도가 아닙니다."""

    N = 16384

    def __init__(self):
        self.data = [0] * self.N
        self.count = 0
        self.loaded = False
        self.cfg = dict(MODE="EQ", A=0, B=0, COUNT=self.N, CAP=100,
                        SEEDJ=1, SEEDM=1, AUTO=1, BURST=0, J=0, FAILLIM=4)
        self.last = dict(trials=0, l=0, iters=0, cyc=0, found=0)
        self.out = ["# bbht_console (mock)", "OK"]

    # ------------------------------------------------------------------
    @staticmethod
    def _num(s):
        s = s.strip()
        neg = s.startswith("-")
        if neg:
            s = s[1:]
        v = int(s, 16) if s.lower().startswith("0x") else int(s)
        return -v if neg else v

    def _xorshift(self, x):
        if x == 0:
            x = 0x6D2B79F5
        x ^= (x << 13) & 0xFFFFFFFF
        x ^= x >> 17
        x ^= (x << 5) & 0xFFFFFFFF
        return x & 0xFFFFFFFF

    def _match(self, v):
        m, a, b = self.cfg["MODE"], self.cfg["A"], self.cfg["B"]
        if m == "LT":
            return v < a
        if m == "GT":
            return v > a
        if m == "EQ":
            return v == a
        return a < v < b

    # ------------------------------------------------------------------
    def send(self, line):
        tok = line.upper().split()
        self.out = []
        if not tok:
            self.out = ["OK"]
            return
        cmd, rest = tok[0], tok[1:]

        try:
            kv = dict(t.split("=", 1) for t in rest if "=" in t)
        except ValueError:
            self.out = ["ERR BAD_KV"]
            return

        if cmd == "HELP":
            self.out = ["# mock: HELP ID SET SHOW GEN POKE PEEK LOAD RUN ENUM STAT", "OK"]

        elif cmd == "ID":
            self.out = ["STAT name=bbht_console csr_ver=0.9.8 (mock)",
                        "STAT csr_base=0xe2020000 q_bits=14 n_entries=16384 fifo_depth=256",
                        "STAT accel_clk_hz=100000000 sram_base=0xe0000000 sram_last=0xe001ffff",
                        "STAT dataset_addr=0x00000000 dataset_count=%d loaded=%d"
                        % (self.count, int(self.loaded)),
                        "OK"]

        elif cmd == "SET":
            for k, v in kv.items():
                if k == "MODE":
                    if v not in ("LT", "GT", "EQ", "RANGE"):
                        self.out = ["ERR BAD_KV"]
                        return
                    self.cfg[k] = v
                elif k in self.cfg:
                    self.cfg[k] = self._num(v)
                else:
                    self.out = ["ERR BAD_KV"]
                    return
            if self.cfg["MODE"] == "RANGE" and self.cfg["B"] <= self.cfg["A"]:
                self.out = ["ERR RANGE_NEEDS_B_GT_A"]
                return
            self.out = ["OK"]

        elif cmd == "SHOW":
            c = self.cfg
            self.out = ["CFG mode=%s a=%d b=%d count=%d cap=%d"
                        % (c["MODE"], c["A"], c["B"], c["COUNT"], c["CAP"]),
                        "CFG auto=%d burst=%d j=%d faillim=%d seedj=0x%08x seedm=0x%08x"
                        % (c["AUTO"], c["BURST"], c["J"], c["FAILLIM"],
                           c["SEEDJ"], c["SEEDM"]),
                        "OK"]

        elif cmd == "GEN":
            count = self._num(kv.get("COUNT", str(self.N)))
            seed = self._num(kv.get("SEED", "0x5EED1234"))
            pos = self._num(kv.get("POS", "0xA17E2026"))
            targets = self._num(kv.get("TARGETS", "1"))
            val = self._num(kv.get("VAL", "12345"))
            if not (0 < count <= self.N) or targets > count:
                self.out = ["ERR BAD_COUNT"]
                return
            st = seed
            for i in range(count):
                st = self._xorshift(st)
                v = st & 0xFFFF
                if v == (val & 0xFFFF):
                    v ^= 1
                self.data[i] = v - 0x10000 if v >= 0x8000 else v
            st, placed, guard = pos, 0, 0
            while placed < targets and guard < 100000:
                st = self._xorshift(st)
                idx = st % count
                guard += 1
                if self.data[idx] == val:
                    continue
                self.data[idx] = val
                placed += 1
            self.count, self.loaded = count, False
            self.cfg["COUNT"] = count
            self.out = ["OK count=%d targets=%d val=%d" % (count, targets, val)]

        elif cmd == "POKE":
            idx, val = self._num(kv["IDX"]), self._num(kv["VAL"])
            self.data[idx] = val
            self.count = max(self.count, idx + 1)
            self.loaded = False
            self.out = ["OK idx=%d val=%d" % (idx, val)]

        elif cmd == "PEEK":
            idx = self._num(kv["IDX"])
            self.out = ["STAT idx=%d val=%d" % (idx, self.data[idx]), "OK"]

        elif cmd == "LOAD":
            if self.count == 0:
                self.out = ["ERR NO_DATASET"]
                return
            self.loaded = True
            self.out = ["OK loaded=%d addr=0x00000000" % self.count]

        elif cmd in ("RUN", "ENUM"):
            if not self.loaded:
                self.out = ["ERR NOT_LOADED"]
                return
            hits = [i for i in range(self.cfg["COUNT"]) if self._match(self.data[i])]
            # 지어낸 숫자입니다. 실물의 성질 두 가지만 지킵니다.
            #   L_BBHT(Sum requested j)는 checkpoint 와 무관하게 같습니다
            #   물리 반복(actual_iter)만 체크포인트 경로에서 줄어듭니다
            # 짝맞춤 판정이 이 성질 위에 서 있으므로, 모델이 이걸 어기면
            # 실험 스크립트를 시험할 때 항상 불일치가 납니다.
            l_bbht = 120
            iters = 40 if not self.cfg["BURST"] else 12
            cyc = 2100 * iters + 100000
            self.last = dict(trials=len(hits) or 1, l=l_bbht,
                             iters=iters, cyc=cyc, found=len(hits))
            if cmd == "RUN":
                if hits:
                    self.out = ["HIT idx=%d val=%d trials=%d l=%d iters=%d cyc=%d us=%d"
                                % (hits[0], self.data[hits[0]], self.last["trials"],
                                   self.last["l"], iters, cyc, cyc // 100), "OK"]
                else:
                    self.out = ["MISS reason=SHOT_CAP trials=%d cyc=%d us=%d"
                                % (self.cfg["CAP"], cyc, cyc // 100), "OK"]
            else:
                self.out = ["FOUND idx=%d val=%d" % (i, self.data[i]) for i in hits]
                self.out.append("END count=%d found=%d cyc=%d us=%d"
                                % (len(hits), len(hits), cyc, cyc // 100))
                self.out.append("OK")

        elif cmd == "STAT":
            m = self.last
            self.out = ["STAT status=0x0000080c valid=1 idx=0",
                        "STAT trials=%d l_bbht=%d actual_iter=%d cyc=%d us=%d"
                        % (m["trials"], m["l"], m["iters"], m["cyc"], m["cyc"] // 100),
                        "STAT found=%d consec_fail=0 max_fifo=0 fifo_stall=0" % m["found"],
                        "OK"]

        elif cmd == "REG":
            self.out = ["REG 0x%03x = 0x00000000" % o for o in range(0, 0x98, 4)] + ["OK"]

        else:
            self.out = ["ERR UNKNOWN_CMD"]

    def read_lines(self):
        return self.out

    def close(self):
        pass


# =====================================================================
# 응답 파싱
# =====================================================================
class ReplayTransport:
    """RTL 시뮬이 뱉은 콘솔 트랜스크립트를 그대로 되짚습니다.

    보드가 없을 때 mock 만 쓰면 파이썬 모델의 숫자를 파싱하는 것이라 증명력이
    없습니다. 이쪽은 Questa 에서 `bbht_console` 을 돌려 나온 진짜 출력을 같은
    Board / parse_kv_line 경로로 먹입니다. 즉 호스트 파서가 실제 펌웨어 응답을
    정확히 해석하는지를 봅니다.

    자르는 법은 트랜스크립트에 명령 에코(`> CMD`)가 있느냐로 갈립니다.

    - 에코가 있으면(스크립트 모드 `bbht_console` 이 내는 형태) 에코 줄을 경계로
      자릅니다. 첫 에코 앞의 시작 배너와 그 `OK` 는 어느 명령의 응답도 아니라서
      버립니다. 그리고 호스트가 보낸 명령과 펌웨어가 받았다고 에코한 명령을
      대조해서, 다르면 `ERR REPLAY_MISMATCH` 를 돌려줍니다 -- 순서가 한 칸만
      밀려도 그 뒤 숫자가 전부 엉뚱한 명령의 것이 되기 때문입니다.
    - 에코가 없으면 응답 덩어리를 `OK` / `ERR` 종결자로 잘라서 보낸 순서대로
      하나씩 돌려줍니다. 콘솔 앱이 한 명령에 정확히 하나의 종결자를 내는
      규약(UART_명령_프로토콜.md §2)을 그대로 쓴 것입니다. 이때는 배너가 없는
      트랜스크립트여야 합니다.
    """

    def __init__(self, path):
        self.blocks = self._split(path)
        self.i = 0
        self.pending = []

    @staticmethod
    def _norm(cmd):
        # 콘솔의 split() 이 토큰을 대문자로 바꾸고 공백을 하나로 봅니다.
        return " ".join(cmd.upper().split())

    @staticmethod
    def _split(path):
        """[(에코한 명령 또는 None, 응답 줄 목록), ...]"""
        with open(path, encoding="utf-8", errors="replace") as f:
            lines = [raw.rstrip("\r\n") for raw in f]

        if any(l.startswith("> ") for l in lines):
            blocks, cur = [], None
            for line in lines:
                if line.startswith("> "):
                    cur = (line[2:].strip(), [])
                    blocks.append(cur)
                    continue
                stripped = line.strip()
                if cur is None or not stripped:           # 배너, 빈 줄
                    continue
                cur[1].append(stripped)
            return blocks

        blocks, cur = [], []
        for line in lines:
            stripped = line.strip()
            if not stripped:
                continue
            cur.append(stripped)
            # 종결자는 첫 낱말이 OK / ERR 인 줄입니다. OK 는 인자를 달고
            # 오는 경우가 많아서("OK count=16384 targets=4") 줄 전체를
            # 맞대면 안 됩니다.
            head = stripped.split(None, 1)[0]
            if head in ("OK", "ERR"):
                blocks.append((None, cur))
                cur = []
        if cur:                                          # 종결자 없이 끝난 꼬리
            blocks.append((None, cur))
        return blocks

    def send(self, line):
        if self.i >= len(self.blocks):
            self.pending = ["ERR REPLAY_EXHAUSTED"]
            return
        echoed, resp = self.blocks[self.i]
        self.i += 1
        if echoed is not None and self._norm(echoed) != self._norm(line):
            self.pending = ["ERR REPLAY_MISMATCH sent=%r transcript=%r"
                            % (line, echoed)]
            return
        self.pending = resp

    def read_lines(self):
        out, self.pending = self.pending, []
        return out

    def close(self):
        pass


def parse_kv_line(line):
    """'HIT idx=12 val=7 cyc=100' -> ('HIT', {'idx':12,'val':7,'cyc':100})"""
    parts = line.split()
    tag = parts[0]
    d = {}
    for p in parts[1:]:
        if "=" not in p:
            continue
        k, v = p.split("=", 1)
        try:
            d[k] = int(v, 16) if v.lower().startswith("0x") else int(v)
        except ValueError:
            d[k] = v
    return tag, d


class Board:
    def __init__(self, transport, echo=False):
        self.t = transport
        self.echo = echo

    def cmd(self, line):
        """명령 하나를 보내고 응답 줄 목록을 돌려줍니다."""
        self.t.send(line)
        lines = self.t.read_lines()
        if self.echo:
            print("> " + line)
            for l in lines:
                print("  " + l)
        return lines

    def cmd_ok(self, line):
        lines = self.cmd(line)
        if not lines or not lines[-1].startswith("OK"):
            raise RuntimeError("명령 실패: %s -> %s" % (line, lines[-1] if lines else "(무응답)"))
        return lines

    def run(self):
        """RUN 한 번. 찾으면 dict, 못 찾으면 None."""
        for line in self.cmd_ok("RUN"):
            if line.startswith("HIT"):
                return parse_kv_line(line)[1]
            if line.startswith("MISS"):
                return None
        return None

    def enumerate(self):
        """ENUM 한 번. (인덱스 목록, END 필드) 를 돌려줍니다."""
        idxs, end = [], {}
        for line in self.cmd_ok("ENUM"):
            if line.startswith("FOUND"):
                idxs.append(parse_kv_line(line)[1]["idx"])
            elif line.startswith("END"):
                end = parse_kv_line(line)[1]
        return idxs, end

    def stat(self):
        d = {}
        for line in self.cmd_ok("STAT"):
            if line.startswith("STAT"):
                d.update(parse_kv_line(line)[1])
        return d


# =====================================================================
# 벤치마크 -- Normal vs 체크포인트 짝 비교
# =====================================================================
def selftest(board):
    """보드가 보고하는 상수가 CSR 정본과 같은지 봅니다.

    `ID` 응답에는 펌웨어가 컴파일 시점에 들고 있던 값이 실려 옵니다. 그것이
    `software/contract/bbht_grover_csr.json` 에서 생성한 상수와 다르면, 보드에
    구운 것과 저장소 정본이 어긋났다는 뜻입니다 -- 굽기 전에 잡아야 하는
    어긋남입니다.

    반환값은 어긋난 항목 수입니다 (0 이면 통과).
    """
    if CSR is None:
        print("CSR 상수를 못 읽었습니다. software/contract/gen_csr.py 를 돌리십시오.")
        return 1

    want = {
        "csr_base":     CSR.BASE,
        "q_bits":       CSR.Q_BITS,
        "n_entries":    CSR.N_ENTRIES,
        "accel_clk_hz": CSR.ACCEL_CLK_HZ,
        "sram_base":    CSR.SRAM_BASE,
        "sram_last":    CSR.SRAM_LAST,
    }

    got = {}
    for line in board.cmd("ID"):
        tag, kv = parse_kv_line(line)
        if tag == "STAT":
            got.update(kv)

    bad = 0
    print("%-14s %-14s %-14s" % ("항목", "보드", "정본"))
    for key in sorted(want):
        if key not in got:
            print("  없음 %-12s %-14s %-14s" % (key, "(응답에 없음)", _fmt(want[key])))
            bad += 1
            continue
        ok = got[key] == want[key]
        print("  %s %-12s %-14s %-14s"
              % ("일치" if ok else "다름", key, _fmt(got[key]), _fmt(want[key])))
        if not ok:
            bad += 1

    # fifo_depth 는 JSON 의 search_space 에 있고 생성 상수에는 REG 만 나옵니다.
    # 보드가 보고하면 깊이 256 이라는 계약만 확인합니다.
    if "fifo_depth" in got:
        ok = got["fifo_depth"] == 256
        print("  %s %-12s %-14s %-14s" % ("일치" if ok else "다름",
                                          "fifo_depth", got["fifo_depth"], 256))
        if not ok:
            bad += 1

    print("")
    print("selftest: %d 항목 중 %d 어긋남" % (len(want) + ("fifo_depth" in got), bad))
    return bad


def _fmt(v):
    if isinstance(v, int) and v > 0xFFFF:
        return "0x%08X" % v
    return str(v)


def bench(board, seeds, targets, value, count, out_path):
    """같은 (seed_j, seed_meas) 짝으로 Normal 과 체크포인트 경로를 각각 돌립니다.

    PJK 의 2026-09-01 보드 벤치마크와 같은 모양입니다. 짝맞춤이 핵심이고,
    두 모드가 같은 결과를 내면서 물리 반복만 줄어야 정상입니다."""
    rows = []
    for tcount in targets:
        board.cmd_ok("GEN COUNT=%d TARGETS=%d VAL=%d" % (count, tcount, value))
        board.cmd_ok("LOAD")
        board.cmd_ok("SET MODE=EQ A=%d AUTO=1" % value)

        agg = dict(n=0, ok=0, mism=0,
                   iter_n=0, iter_k=0, cyc_n=0, cyc_k=0)

        for s in range(seeds):
            sj, sm = 0x1000_0001 + s * 0x9E37_79B9, 0x2000_0001 + s * 0x85EB_CA6B
            sj &= 0xFFFFFFFF
            sm &= 0xFFFFFFFF

            res = {}
            for mode, burst in (("normal", 0), ("ckpt", 1)):
                board.cmd_ok("SET BURST=%d SEEDJ=0x%08X SEEDM=0x%08X" % (burst, sj, sm))
                res[mode] = board.run()

            agg["n"] += 1
            n, k = res["normal"], res["ckpt"]
            if n is None or k is None:
                continue
            agg["ok"] += 1
            if n["idx"] != k["idx"] or n.get("l") != k.get("l"):
                agg["mism"] += 1
            agg["iter_n"] += n.get("iters", 0)
            agg["iter_k"] += k.get("iters", 0)
            agg["cyc_n"] += n.get("cyc", 0)
            agg["cyc_k"] += k.get("cyc", 0)

        di = (1 - agg["iter_k"] / agg["iter_n"]) * 100 if agg["iter_n"] else 0.0
        dc = (1 - agg["cyc_k"] / agg["cyc_n"]) * 100 if agg["cyc_n"] else 0.0

        rows.append(dict(targets=tcount, seeds=agg["n"], success=agg["ok"],
                         mismatch=agg["mism"],
                         iter_normal=agg["iter_n"], iter_ckpt=agg["iter_k"],
                         iter_delta_pct=round(di, 2),
                         cyc_normal=agg["cyc_n"], cyc_ckpt=agg["cyc_k"],
                         cyc_delta_pct=round(dc, 2)))
        print("targets=%-4d seeds=%d success=%d mismatch=%d  iter %d->%d (%.2f%%)  "
              "cyc %d->%d (%.2f%%)"
              % (tcount, agg["n"], agg["ok"], agg["mism"],
                 agg["iter_n"], agg["iter_k"], di,
                 agg["cyc_n"], agg["cyc_k"], dc))

    if out_path:
        with open(out_path, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        print("CSV 기록: %s" % out_path)
    return rows


# =====================================================================
def interactive(board):
    print("명령을 입력하십시오. HELP 로 목록, quit 로 종료.")
    while True:
        try:
            line = input("bbht> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            return
        if line.lower() in ("quit", "exit", "q"):
            return
        if not line:
            continue
        for l in board.cmd(line):
            print(l)


def main():
    ap = argparse.ArgumentParser(description="BBHT/Grover 호스트 CLI")
    ap.add_argument("--port", required=True,
                    help="시리얼 장치 (예 /dev/ttyUSB1, COM3). 'mock' 이면 파이썬 모델, "
                         "'replay:<파일>' 이면 RTL 시뮬 트랜스크립트 재생")
    ap.add_argument("--baud", type=int, default=115200)
    ap.add_argument("--timeout", type=float, default=30.0,
                    help="응답 대기 상한(초). 탐색이 길면 키우십시오")
    ap.add_argument("-c", "--cmd", action="append", default=[],
                    help="명령 하나. 여러 번 쓸 수 있습니다")
    ap.add_argument("--script", help="명령 파일. # 은 주석")
    ap.add_argument("--log", help="주고받은 줄 전부를 기록할 파일")

    sub = ap.add_subparsers(dest="sub")
    b = sub.add_parser("bench", help="Normal vs 체크포인트 짝 비교")
    b.add_argument("--seeds", type=int, default=10)
    b.add_argument("--targets", default="1,4,16,64,256")
    b.add_argument("--value", type=int, default=12345)
    b.add_argument("--count", type=int, default=16384)
    b.add_argument("--csv", default=None)
    sub.add_parser("selftest",
                   help="보드가 보고하는 상수를 CSR 정본과 대조")

    args = ap.parse_args()

    if args.port == "mock":
        transport = MockTransport()
    elif args.port.startswith("replay:"):
        transport = ReplayTransport(args.port.split(":", 1)[1])
    else:
        transport = SerialTransport(args.port, args.baud, args.timeout)
    board = Board(transport, echo=bool(args.cmd or args.script))

    logf = open(args.log, "w", encoding="utf-8") if args.log else None
    if logf:
        orig = board.cmd

        def logged(line):
            out = orig(line)
            logf.write("> %s\n" % line)
            for l in out:
                logf.write("%s\n" % l)
            logf.flush()
            return out
        board.cmd = logged

    try:
        # 보드가 살아 있는지 먼저 확인합니다. 여기서 막히면 배선이나
        # 보율이 문제이지 그 뒤 명령이 문제가 아닙니다.
        #
        # 재생 모드에는 보드가 없습니다. 게다가 여기서 한 번 보내면 트랜스크립트
        # 블록을 하나 먹어서 그 뒤가 전부 한 칸씩 밀립니다. 그래서 건너뜁니다.
        if not isinstance(transport, ReplayTransport):
            board.cmd("ID")

        if args.sub == "selftest":
            return selftest(board)
        elif args.sub == "bench":
            targets = [int(x) for x in args.targets.split(",")]
            bench(board, args.seeds, targets, args.value, args.count, args.csv)
        elif args.script:
            # Windows 기본 인코딩(cp949)으로 읽으면 한글 주석에서 깨집니다
            with open(args.script, encoding="utf-8") as f:
                for raw in f:
                    line = raw.split("#", 1)[0].strip()
                    if line:
                        board.cmd_ok(line)
        elif args.cmd:
            for line in args.cmd:
                board.cmd_ok(line)
        else:
            interactive(board)
    finally:
        if logf:
            logf.close()
        transport.close()


if __name__ == "__main__":
    sys.exit(main() or 0)
