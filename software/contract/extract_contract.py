#!/usr/bin/env python3
"""
PJK 인수인계 docx 에서 포트 계약표를 뽑아 port_contract.tsv 로 굳힙니다.

docx 는 이 폴더에 같이 있고 바이너리라 diff 가 안 보입니다. 그래서 계약을
텍스트로 뽑아 저장소에 커밋해 두고, check_ports.py 가 그것과 RTL 을
대조합니다. 인수인계가 갱신되면 이 스크립트를 다시 돌려 tsv 를 갱신하고
diff 로 무엇이 바뀌었는지 봅니다.

    python3 extract_contract.py [docx경로]
"""
import hashlib
import io
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DOCX = os.path.join(
    HERE, "LPSoC_BBHT_Grover_팀원_Handoff_SW_통신_v0.9.8반영_2026-09-01.docx")
OUT = os.path.join(HERE, "port_contract.tsv")


def docx_text(path):
    xml = zipfile.ZipFile(path).read("word/document.xml").decode("utf-8")
    xml = xml.replace("</w:p>", "\n").replace("</w:tr>", "\n")
    xml = re.sub(r"</w:tc>", " | ", xml)
    xml = re.sub(r"<w:tab[^>]*/>", "\t", xml)
    xml = re.sub(r"<w:br[^>]*/>", "\n", xml)
    import html
    return html.unescape(re.sub(r"<[^>]+>", "", xml)).splitlines()


def section(lines, start_pat, end_pat):
    s = e = None
    for i, l in enumerate(lines):
        if s is None and re.search(start_pat, l):
            s = i
        elif s is not None and re.search(end_pat, l):
            e = i
            break
    if s is None or e is None:
        sys.exit("계약 절을 못 찾았습니다: %s" % start_pat)
    return lines[s:e]


def rows(lines):
    """한 행이 여러 줄에 걸쳐 있습니다. ' | ' 로 시작하지 않는 줄이 새 행."""
    out, cur = [], None
    for l in lines:
        if l.startswith(" | "):
            if cur is not None:
                cur.append(l[3:].strip())
        else:
            if cur:
                out.append(cur)
            cur = [l.strip()]
    if cur:
        out.append(cur)
    return [r for r in out if len(r) >= 4]


def main():
    docx = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DOCX
    if not os.path.exists(docx):
        sys.exit("docx 가 없습니다: %s" % docx)

    sha = hashlib.sha256(open(docx, "rb").read()).hexdigest()
    lines = docx_text(docx)

    recs = []
    for r in rows(section(lines, r"^3\.3 bbht_rvx_wrapper", r"^3\.4 Main IP generic")):
        if r[0] == "Bus" or r[2] not in ("IN", "OUT"):
            continue
        recs.append(("wrapper", r[0], r[1], r[2], r[3], "signed" if "signed" in r[3] else ""))

    for r in rows(section(lines, r"^3\.4 Main IP generic", r"^3\.5 AHB loader")):
        if r[0] == "Group" or r[2] not in ("IN", "OUT"):
            continue
        w = r[3].split()[0]
        recs.append(("core", r[0], r[1], r[2], w, "signed" if "signed" in r[3] else ""))

    with io.open(OUT, "w", encoding="utf-8") as f:
        f.write("# BBHT/Grover 포트 계약 -- 기계 생성물. 손으로 고치지 마십시오.\n")
        f.write("# 출처: %s\n" % os.path.basename(docx))
        f.write("#   §3.3 bbht_rvx_wrapper 외부 APB/AHB 포트 계약\n")
        f.write("#   §3.4 Main IP generic interface\n")
        f.write("# docx sha256: %s\n" % sha)
        f.write("# scope\tgroup\tport\tdir\twidth\tsigned\n")
        for r in recs:
            f.write("\t".join(r) + "\n")

    n_w = sum(1 for r in recs if r[0] == "wrapper")
    n_c = sum(1 for r in recs if r[0] == "core")
    print("%s 생성: wrapper %d 개, core %d 개" % (os.path.basename(OUT), n_w, n_c))


if __name__ == "__main__":
    main()
