#!/usr/bin/env python3
"""
포트 계약 검사기.

port_contract.tsv (PJK 인수인계 §3.3/§3.4 에서 뽑은 것) 와 실제 Verilog 를
대조합니다. 이름·방향·폭·signed 가 하나라도 어긋나면 종료코드 1 입니다.

hardware_bram 의 통신 계층은 src/ 한 벌입니다 (2026-09-13 에 src_comm 을
src 로 합쳤습니다). 코어 자리에 무엇을 끼우느냐로 갈래가 둘입니다.

    real   통신 계층 (hardware_bram/src) + 어댑터. 어댑터가 계약 이름
           bbht_grover_core 와 리셋 이름 rstnn 로 맞춰 줍니다.
    stub   같은 통신 계층에 자리 채우개를 끼운 것. 통신 계층만 볼 때 씁니다.

보드에 구운 정본 wrapper 는 어댑터 없이 bbht_grover_main_ip 를 직접 물었고,
그것을 대조하던 final 갈래는 태그 board-k3h3-e4-m2 에 남아 있습니다.

hardware_dram 갈래도 같은 계약을 지켜야 합니다. 그쪽 Main IP 는 우리가 쓴
초안이지만 wrapper 19 + core 61 신호는 통신 계층과 맞물리는 부분이라 바뀌면
안 됩니다. dram 갈래는 hardware_dram 의 wrapper 와 어댑터를 봅니다.

    python3 check_ports.py [stub|real|dram]
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")

CONTRACT = os.path.join(HERE, "port_contract.tsv")

MODE = sys.argv[1] if len(sys.argv) > 1 else "stub"

# 갈래마다 wrapper 한 벌, 그 wrapper 가 무는 코어 한 벌입니다.
#   wrapper  §3.3 을 대조할 파일
#   core     §3.4 를 대조할 파일
#   module   그 파일 안의 모듈 이름
#   inst     wrapper 안에서 코어를 무는 인스턴스 이름
#   rst      코어가 쓰는 리셋 이름 (계약 표에는 clk/리셋이 없습니다).
#            wrapper 는 RVX 가 주는 rstnn 으로 어느 갈래나 같습니다
BRANCHES = {
    # 통신 계층 + 어댑터. 어댑터가 계약 이름과 rstnn 로 맞춰 줍니다.
    "real":  dict(wrapper=("hardware_bram", "src", "bbht_rvx_wrapper.v"),
                  core=("hardware_bram", "src", "bbht_grover_core_adapter.v"),
                  module="bbht_grover_core", inst="u_core", rst="rstnn"),
    # 같은 통신 계층에 자리 채우개를 끼운 것.
    "stub":  dict(wrapper=("hardware_bram", "src", "bbht_rvx_wrapper.v"),
                  core=("hardware_bram", "testbench", "bbht_grover_core_stub.v"),
                  module="bbht_grover_core", inst="u_core", rst="rstnn"),
    # DRAM 전량저장 갈래. 감싸는 Main IP 는 다르지만 계약 61신호는 같습니다.
    "dram":  dict(wrapper=("hardware_dram", "src", "bbht_rvx_wrapper.v"),
                  core=("hardware_dram", "src", "bbht_grover_core_adapter.v"),
                  module="bbht_grover_core", inst="u_core", rst="rstnn"),
}

if MODE not in BRANCHES:
    sys.exit("갈래는 %s 중 하나입니다 (받은 값: %s)"
             % ("|".join(BRANCHES), MODE))

BRANCH = BRANCHES[MODE]
WRAPPER = os.path.join(ROOT, *BRANCH["wrapper"])
CORE = os.path.join(ROOT, *BRANCH["core"])
PARAMS = (os.path.join(ROOT, *BRANCH["params"])
          if "params" in BRANCH else None)


def load_defines(path):
    """grover_param.vh 의 `define 을 {이름: 식} 으로. 폭 계산에만 씁니다.

    정본 Main IP 는 포트 폭을 `GP_INDEX_W-1 처럼 매크로로 씁니다. 어댑터
    갈래는 숫자를 그대로 적으므로 이 표가 필요 없습니다.
    """
    if not path:
        return {}
    out = {}
    for line in io.open(path, encoding="utf-8"):
        m = re.match(r"\s*`define\s+(GP_\w+)\s+(.+?)\s*(?://.*)?$", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


DEFINES = load_defines(PARAMS)


def resolve_width(expr):
    """`GP_J_W-1 같은 상한 식을 숫자 폭으로. 못 풀면 원문 그대로 돌려줍니다."""
    text = expr
    for _ in range(8):
        if "`" not in text:
            break
        text = re.sub(r"`(GP_\w+)",
                      lambda m: "(%s)" % DEFINES.get(m.group(1), "`" + m.group(1)),
                      text)
    if "`" in text or not re.fullmatch(r"[\d\s()+\-*/<>]+", text):
        return None
    try:
        return int(eval(text, {"__builtins__": {}})) + 1
    except Exception:
        return None

# 계약에 없지만 있어야 하는 것. 인수인계 표는 clk 과 리셋을 적지 않습니다.
WRAPPER_IMPLICIT = {"clk", "rstnn"}
CORE_IMPLICIT = {"clk", BRANCH["rst"]}


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
            if hi.isdigit():
                width = str(int(hi) + 1)
            else:
                resolved = resolve_width(hi)
                width = str(resolved) if resolved is not None else hi
        else:
            width = "1"
        ports[mm.group(5)] = ("IN" if mm.group(1) == "input" else "OUT",
                              width, bool(mm.group(2)))
    return ports


def inst_ports(path, instname):
    """.port(sig) 인스턴스 연결 포트 이름."""
    src = re.sub(r"//[^\n]*", "", io.open(path, encoding="utf-8").read())
    m = re.search(r"\b" + instname + r"\s*\((.*?)\n\s*\);", src, re.S)
    if not m:
        sys.exit("인스턴스를 못 찾았습니다: %s in %s" % (instname, path))
    return set(re.findall(r"\.\s*([A-Za-z_]\w*)\s*\(", m.group(1)))


def compare(title, expect, actual, implicit, connected=None):
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

    extra = set(actual) - {p for _, p, _, _, _ in expect} - implicit
    for p in sorted(extra):
        print("  FAIL %-28s 계약에 없는 포트" % p)
        bad += 1

    missing_implicit = implicit - set(actual)
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
                   c["wrapper"], module_ports(WRAPPER, "bbht_rvx_wrapper"),
                   WRAPPER_IMPLICIT)

    bad += compare("§3.4  Main IP generic interface (선언 + wrapper 연결)",
                   c["core"], module_ports(CORE, BRANCH["module"]),
                   CORE_IMPLICIT,
                   connected=inst_ports(WRAPPER, BRANCH["inst"]))

    print()
    if bad:
        print("포트 계약 불일치 %d 건" % bad)
        return 1
    print("포트 계약 일치 (wrapper %d + core %d)" % (len(c["wrapper"]), len(c["core"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
