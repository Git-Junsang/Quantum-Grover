#!/usr/bin/env python3
"""
포트 계약 검사기.

port_contract.tsv (PJK 인수인계 §3.3/§3.4 에서 뽑은 것) 와 실제 Verilog 를
대조합니다. 이름·방향·폭·signed 가 하나라도 어긋나면 종료코드 1 입니다.

실물 Main IP 는 hardware_bram/src_v2 에 있고 모듈 이름이
lpsoc_bbht_grover_main_ip 입니다. 계약 이름(bbht_grover_core)으로 감싸는
어댑터가 src/bbht_grover_core_adapter.v 라, real 갈래는 그 어댑터를 봅니다.
어댑터가 계약 폭을 그대로 선언하고 있으므로 실물 배선도 이 검사로 지켜집니다.

    python3 check_ports.py [stub|real|v3]
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")

WRAPPER = os.path.join(ROOT, "hardware_bram", "src", "bbht_rvx_wrapper.v")
CONTRACT = os.path.join(HERE, "port_contract.tsv")

# 계약 대조 대상. 둘 다 module bbht_grover_core 를 계약 폭 그대로 선언합니다.
#   stub  통신 계층만 볼 때 쓰는 자리 채우개
#   real  실물 Main IP(lpsoc_bbht_grover_main_ip) 를 감싼 어댑터
CORES = {
    "stub": os.path.join(ROOT, "hardware_bram", "testbench", "bbht_grover_core_stub.v"),
    "real": os.path.join(ROOT, "hardware_bram", "src", "bbht_grover_core_adapter.v"),
    #   v3    PASS2 융합판(src_v3) 을 감싼 어댑터. 몸통은 real 과 같고
    #         헤더만 다르지만, 포트가 61개 그대로인지는 따로 확인해야
    #         합니다. 어댑터를 하나 더 두면 배선이 갈릴 수 있습니다.
    "v3": os.path.join(ROOT, "hardware_bram", "src", "bbht_grover_core_adapter_v3.v"),
}
CORE = CORES[sys.argv[1] if len(sys.argv) > 1 else "stub"]

# 계약에 없지만 있어야 하는 것. 인수인계 표는 clk/rstnn 을 적지 않습니다.
IMPLICIT = {"clk", "rstnn"}


def load_contract():
    out = {"wrapper": [], "core": []}
    for line in io.open(CONTRACT, encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        scope, group, port, d, w, signed = (line.rstrip("\n").split("\t") + [""] * 6)[:6]
        out[scope].append((group, port, d, w, signed == "signed"))
    return out


def module_ports(path, modname):
    """module <name> ... ( ... ); 의 포트 선언 -> {이름: (방향, 폭, signed)}"""
    src = re.sub(r"//[^\n]*", "", io.open(path, encoding="utf-8").read())
    m = re.search(r"\bmodule\s+" + modname + r"\b(.*?);", src, re.S)
    if not m:
        sys.exit("모듈을 못 찾았습니다: %s in %s" % (modname, path))
    ports = {}
    pat = r"\b(input|output)\s+(?:wire|reg)?\s*(signed)?\s*(\[([^\]]+)\])?\s*([A-Za-z_]\w*)"
    for mm in re.finditer(pat, m.group(1)):
        rng = mm.group(4)
        if rng:
            hi = rng.split(":")[0].strip()
            width = str(int(hi) + 1) if hi.isdigit() else hi
        else:
            width = "1"
        ports[mm.group(5)] = ("IN" if mm.group(1) == "input" else "OUT",
                              width, bool(mm.group(2)))
    return ports


def inst_ports(path, instname):
    """.port(sig) 인스턴스 연결 포트 이름."""
    src = re.sub(r"//[^\n]*", "", io.open(path, encoding="utf-8").read())
    m = re.search(r"\b\w+\s+" + instname + r"\s*\((.*?)\n\s*\);", src, re.S)
    if not m:
        sys.exit("인스턴스를 못 찾았습니다: %s in %s" % (instname, path))
    return set(re.findall(r"\.\s*([A-Za-z_]\w*)\s*\(", m.group(1)))


def compare(title, expect, actual, connected=None):
    print("=" * 72)
    print(title)
    print("=" * 72)
    bad = 0
    for group, port, d, w, signed in expect:
        if port not in actual:
            print("  FAIL %-28s 포트 없음" % port)
            bad += 1
            continue
        ad, aw, asigned = actual[port]
        prob = []
        if ad != d:
            prob.append("방향 %s (계약 %s)" % (ad, d))
        if aw != w:
            prob.append("폭 %s (계약 %s)" % (aw, w))
        if signed and not asigned:
            prob.append("signed 누락")
        if connected is not None and port not in connected:
            prob.append("인스턴스 미연결")
        if prob:
            print("  FAIL %-28s %s" % (port, ", ".join(prob)))
            bad += 1

    extra = set(actual) - {p for _, p, _, _, _ in expect} - IMPLICIT
    for p in sorted(extra):
        print("  FAIL %-28s 계약에 없는 포트" % p)
        bad += 1

    missing_implicit = IMPLICIT - set(actual)
    for p in sorted(missing_implicit):
        print("  FAIL %-28s clk/rstnn 누락" % p)
        bad += 1

    if bad == 0:
        print("  OK   %d 개 전부 일치 (이름·방향·폭·signed)" % len(expect))
    return bad


def main():
    c = load_contract()
    bad = 0

    bad += compare("§3.3  bbht_rvx_wrapper 외부 APB/AHB 포트",
                   c["wrapper"], module_ports(WRAPPER, "bbht_rvx_wrapper"))

    bad += compare("§3.4  Main IP generic interface (선언 + wrapper 연결)",
                   c["core"], module_ports(CORE, "bbht_grover_core"),
                   connected=inst_ports(WRAPPER, "u_core"))

    print()
    if bad:
        print("포트 계약 불일치 %d 건" % bad)
        return 1
    print("포트 계약 일치 (wrapper %d + core %d)" % (len(c["wrapper"]), len(c["core"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
