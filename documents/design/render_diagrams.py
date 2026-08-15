#!/usr/bin/env python3
"""
render_diagrams.py — diagrams/src/*.mmd → diagrams/*.svg 렌더
================================================================
이 해설서의 다이어그램은 md 본문에서 `<img src="diagrams/<name>.svg">` 이미지로
참조한다(확장 없이 VSCode·GitHub·어느 뷰어에서든 보이도록). 다이어그램 소스
(mermaid)는 `diagrams/src/<name>.mmd` 에 보존되며, 이 스크립트가 mermaid-cli
(mmdc)로 SVG(기본)/PNG 를 재생성한다.

다이어그램 수정 방법:
  1) diagrams/src/<name>.mmd 편집
  2) python3 render_diagrams.py   →  diagrams/<name>.svg 갱신
  (md 의 이미지 링크는 그대로 두면 된다)

사전 조건:
  - Node.js + mermaid-cli. 전역 설치 시 `mmdc`, 아니면 npx 로 자동 호출.
      sudo npm install -g @mermaid-js/mermaid-cli
  - headless chromium 의존 라이브러리. 누락 시:
      sudo apt-get install -y libxkbcommon0

사용법:
  python3 render_diagrams.py            # src/*.mmd → diagrams/*.svg
  python3 render_diagrams.py --png      # PNG 로 (scale 2x)
  python3 render_diagrams.py --force    # 캐시 무시하고 재렌더
"""
import os, glob, subprocess, hashlib, argparse, shutil, sys

SG   = os.path.dirname(os.path.abspath(__file__))
DIAG = os.path.join(SG, "diagrams")
SRC  = os.path.join(DIAG, "src")
PP   = os.path.join(SG, ".puppeteer.json")


def mmdc_cmd():
    """전역 mmdc 가 있으면 그것을, 없으면 npx 경유."""
    if shutil.which("mmdc"):
        return ["mmdc"]
    return ["npx", "-y", "@mermaid-js/mermaid-cli"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--png",   action="store_true", help="SVG 대신 PNG 출력")
    ap.add_argument("--force", action="store_true", help="캐시 무시 재렌더")
    args = ap.parse_args()

    ext = "png" if args.png else "svg"
    # puppeteer: 컨테이너/root 환경에서 --no-sandbox 필요
    with open(PP, "w") as fh:
        fh.write('{"args":["--no-sandbox","--disable-setuid-sandbox"]}')

    base = mmdc_cmd()
    cache = os.path.join(DIAG, ".cache")
    os.makedirs(cache, exist_ok=True)
    srcs = sorted(glob.glob(os.path.join(SRC, "*.mmd")))
    if not srcs:
        print(f"소스 없음: {SRC}/*.mmd  (먼저 다이어그램을 src 로 추출하세요)")
        sys.exit(1)

    total = rendered = cached = 0
    fail = []
    for mmd in srcs:
        total += 1
        name = os.path.splitext(os.path.basename(mmd))[0] + "." + ext
        out  = os.path.join(DIAG, name)
        code = open(mmd, encoding="utf-8").read()
        sig  = hashlib.sha1(code.encode("utf-8")).hexdigest()[:12]
        sigf = os.path.join(cache, name + ".sig")
        if (not args.force and os.path.exists(out)
                and os.path.exists(sigf)
                and open(sigf).read().strip() == sig):
            cached += 1
            continue
        cmd = base + ["-i", mmd, "-o", out, "-p", PP, "-b", "white"]
        if args.png:
            cmd += ["-s", "2"]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(out):
            fail.append((name, (r.stderr or r.stdout)[-160:]))
            print(f"  FAIL {name}")
        else:
            open(sigf, "w").write(sig)
            rendered += 1
            print(f"  OK   {name}")

    print(f"\n총 {total}개  |  렌더 {rendered}  캐시 {cached}  실패 {len(fail)}")
    print(f"출력: {DIAG}/")
    for n, e in fail:
        print(f"  ✗ {n}: {e}")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
