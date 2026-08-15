#!/usr/bin/env python3
"""
check_docs.py — 문서 정합성 검사

문서를 고친 뒤 반드시 이것을 돌립니다. 무엇이 깨졌는지 사람이 눈으로 찾을 수
없는 것들 — 링크, 앵커, 그림 참조, 폐기된 스펙의 부활 — 을 기계적으로 잡습니다.

    python3 documents/check_docs.py          # 검사만
    python3 documents/check_docs.py -v       # 통과 항목까지 전부 출력

종료 코드 0 = 이상 없음, 1 = 오류 있음.

검사 항목
  1. 마크다운 링크가 가리키는 파일이 실재하는가
  2. 링크의 절 앵커가 대상 문서에 실재하는가 (GitHub 슬러그 규칙)
  3. <img> 가 가리키는 그림이 실재하는가
  4. 참조되지 않는 그림(고아)이 있는가
  5. mermaid 소스(.mmd)에 대응하는 .svg 가 있는가
  6. 폐기된 스펙이 되살아났는가 (아래 BANNED 표)
  7. 각 장이 요약 절로 닫히고 준비 링크를 갖는가
  8. 본문에 mermaid fence 를 직접 쓰지 않았는가
"""
import re, os, sys, glob, urllib.parse, collections

DOC = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(DOC)
VERBOSE = '-v' in sys.argv

# ── 폐기된 스펙: 이 패턴이 "허용 파일" 밖에서 나오면 오류 ──────────────────
# 허용되는 문맥은 셋뿐입니다.
#   (a) 기각 논증 — "왜 이것을 버렸는가"를 설명하는 자리
#   (b) 정오표·논문 인용 — 원문이 그렇게 적혀 있다는 사실의 기록
#   (c) 2026-07 구 기록 문서 — 머리에 경고 블록이 붙어 있음
BANNED = [
    # (정규식, 설명, 허용 파일 목록)
    (r'XC7S100',
     '폐기된 목표 FPGA (현행 Arty-S7-50 / xc7s50csga324-1)',
     ['15_논문지도와_설계결정표.md', 'CLAUDE.md', '블록도.md', '반복횟수_결정.md',
      '개발계획.md', 'presentation/README.md']),

    (r'BRAM(36)?\s*(120|66)\s*개|BRAM\s*120\b',
     '폐기된 자원 수치 (XC7S100 기준). 현행 IP 33개 / 보드 75개',
     ['블록도.md', '반복횟수_결정.md', 'presentation/README.md']),

    (r'DSP\s*160|160\s*개.*DSP',
     '폐기된 DSP 수치 (XC7S100 기준). 현행 보드 120개',
     ['블록도.md', '반복횟수_결정.md']),

    (r'AXI4-Lite|AXI-?Stream',
     '폐기된 버스 (현행 APB 슬레이브 + AHB 마스터). RVX 에 AXI-Stream 심이 없음',
     ['17_RVX_SoC_통합.md', '15_논문지도와_설계결정표.md', 'CLAUDE.md',
      '블록도.md', '반복횟수_결정.md', '개발계획.md', 'presentation/README.md']),

    (r'MicroBlaze',
     '폐기된 SoC (현행 RVX rvc_orca)',
     ['15_논문지도와_설계결정표.md', 'CLAUDE.md', '블록도.md',
      'README.md', 'presentation/README.md']),

    (r'DSP가?\s*잡히면',
     '"DSP가 잡히면 잘못 짠 것"은 폐기됨 — 측정 경로는 제곱기 32개를 정상적으로 씁니다',
     []),

    (r'곱셈기(를)?\s*(하나도|전혀|한 개도)\s*(안|쓰지)',
     '"곱셈기 0개"에는 반드시 경로를 붙여야 합니다 (확산·오라클·INIT 경로 한정)',
     ['12_고정소수점과_정밀도.md', '13_오라클_확산_측정_데이터패스.md',
      '01_큐비트와_양자상태.md', '06_양자회로_모델과_범용성.md',
      'README.md', '개발계획.md']),
]

# ── 확정 수치: 문서에 다른 값이 적히면 오류 ────────────────────────────────
CANON = [
    (r'BRAM36\s*(\d+)\s*개', {'1', '2', '16', '32', '33', '75', '135'},
     'BRAM36 개수 (IP 33 / 보드 75 / amp·data 각 16)'),
    (r'평균\s*([\d.]+)\s*샷', {'24.5', '26.5', '20.9', '19.1', '15.5'},
     '평균 샷 수 (n=15·M=1 은 24.5)'),
    (r'INIT_AMP\s*[=은는]?\s*(\d+)', {'362'}, 'INIT_AMP (n=15·Q2.16)'),
]


def links(txt):
    """마크다운 인라인 링크 추출. CommonMark 처럼 균형 잡힌 괄호를 허용한다.
    `[라벨](../papers/5. 추가 수집 (OpenAlex)/)` 같은 경로를 끊지 않기 위함."""
    out = []
    i = 0
    while True:
        i = txt.find('](', i)
        if i < 0:
            break
        j, depth = i + 2, 1
        while j < len(txt) and depth:
            if txt[j] == '(':
                depth += 1
            elif txt[j] == ')':
                depth -= 1
            j += 1
        if depth == 0:
            body = txt[i + 2:j - 1]
            out.append(body.split()[0] if body.strip() else '<EMPTY>')
        i = j
    return out


# 부정·정정 문맥 표지. 이 말이 같은 문장에 있으면 폐기 스펙을 "언급"한 것이지
# "주장"한 것이 아니므로 오류가 아니다.
NEGATION = re.compile(
    r'틀렸|틀린|아니라|아닙니다|아니다|폐기|버린|버렸|기각|예전|옛|이전 판|구 |'
    r'하지 않|없습니다만|더는|이제는|바뀌|대신|~이었|였습니다|안 들어|넘어서|초과|'
    r'못 |불가|오해|착각|함정|주의|하지 마|마십시오|말 것|금지')


def sentence_at(txt, pos):
    """pos 를 포함하는 문장(줄 단위 + 앞뒤 한 줄)을 돌려준다."""
    lo = txt.rfind('\n', 0, pos)
    lo = txt.rfind('\n', 0, lo) if lo > 0 else 0
    hi = txt.find('\n', pos)
    hi = txt.find('\n', hi + 1) if hi > 0 else len(txt)
    return txt[max(lo, 0):hi if hi > 0 else len(txt)]


def slug(h):
    """GitHub 앵커 규칙: 소문자화 → 영숫자·한글·공백·하이픈 외 제거 → 공백 하나당 하이픈 하나."""
    s = h.strip().lower()
    s = re.sub(r'[^\w\s가-힣-]', '', s, flags=re.U)
    return s.replace(' ', '-')


def md_files():
    out = []
    for p in glob.glob(os.path.join(ROOT, '**', '*.md'), recursive=True):
        rel = os.path.relpath(p, ROOT)
        if '/facts/' in rel or rel.startswith('papers_ko') or 'papers_ko/' in rel:
            continue
        out.append(rel)
    return sorted(out)


def main():
    errors, warns, notes = [], [], []
    files = md_files()
    text = {f: open(os.path.join(ROOT, f), encoding='utf-8').read() for f in files}
    anchors = {f: {slug(h) for h in re.findall(r'^#{1,6}\s+(.+)$', text[f], re.M)} for f in files}

    # 1~3. 링크와 그림
    img_used = collections.Counter()
    for f in files:
        base = os.path.dirname(f)
        for tgt in links(text[f]):
            if tgt == '<EMPTY>':
                errors.append(f'[링크] {f}  빈 링크 `[라벨]()` — 대상을 채우거나 평문으로 바꾸십시오')
                continue
            if tgt.startswith(('http', 'mailto', '<')) or '<' in tgt:
                continue
            path, _, frag = tgt.partition('#')
            path = urllib.parse.unquote(path)
            target = os.path.normpath(os.path.join(base, path)) if path else f
            if path and not os.path.exists(os.path.join(ROOT, target)):
                errors.append(f'[링크] {f} → {tgt}  (파일 없음)')
                continue
            if frag and target in anchors:
                if slug(urllib.parse.unquote(frag)) not in anchors[target]:
                    errors.append(f'[앵커] {f} → {tgt}  (절 없음)')
        for src in re.findall(r'<img[^>]+src="([^"]+)"', text[f]):
            if src.startswith(('http', '<')) or '<' in src or '>' in src:
                continue
            p = os.path.normpath(os.path.join(base, urllib.parse.unquote(src)))
            img_used[p] += 1
            if not os.path.exists(os.path.join(ROOT, p)):
                errors.append(f'[그림] {f} → {src}  (파일 없음)')

    # 4. 고아 그림
    for svg in glob.glob(os.path.join(DOC, '**', 'diagrams', '*.svg'), recursive=True):
        rel = os.path.relpath(svg, ROOT)
        if rel not in img_used:
            warns.append(f'[고아] {rel}  (본문 어디서도 참조하지 않음)')

    # 5. mmd ↔ svg
    for mmd in glob.glob(os.path.join(DOC, '**', 'diagrams', 'src', '*.mmd'), recursive=True):
        svg = os.path.join(os.path.dirname(os.path.dirname(mmd)),
                           os.path.basename(mmd)[:-4] + '.svg')
        if not os.path.exists(svg):
            errors.append(f'[렌더] {os.path.relpath(mmd, ROOT)} → svg 없음. '
                          f'render_diagrams.py 를 돌리십시오')

    # 6. 폐기 스펙 부활
    for pat, why, allow in BANNED:
        rx = re.compile(pat)
        for f in files:
            if any(f.endswith(a) for a in allow):
                continue
            for m in rx.finditer(text[f]):
                if NEGATION.search(sentence_at(text[f], m.start())):
                    continue          # "그것은 틀렸다 / 폐기했다" 는 정상적인 언급
                line = text[f][:m.start()].count('\n') + 1
                ctx = text[f].splitlines()[line - 1][:110]
                errors.append(f'[폐기] {f}:{line}  {why}\n         → {ctx.strip()}')

    # 7. 확정 수치
    for pat, allowed, what in CANON:
        for f in files:
            for m in re.finditer(pat, text[f]):
                v = m.group(1)
                if v in allowed:
                    continue
                sent = sentence_at(text[f], m.start())
                if NEGATION.search(sent) or re.search(r'n\s*=\s*1[26]|n=1[26]', sent):
                    continue          # 다른 n 조건과의 비교는 정상
                line = text[f][:m.start()].count('\n') + 1
                warns.append(f'[수치] {f}:{line}  {what} 로 "{v}" — 확인 필요')

    # 8. 장 구조 (해설서 본편만)
    SR = 'documents/study_references'
    REF_ONLY = {'10_용어정리와_치트시트.md', 'A_수학_빠른복습.md', 'README.md',
                '00_양자컴퓨팅_시작하기.md'}
    for f in files:
        if not f.startswith(SR) or '_wip' in f:
            continue
        name = os.path.basename(f)
        if name in REF_ONLY:
            continue
        if not re.search(r'^##.*이 장의 요약', text[f], re.M):
            warns.append(f'[구조] {f}  "이 장의 요약" 절이 없음')
        if '읽기 위한 준비' not in text[f]:
            warns.append(f'[구조] {f}  "이 장을 읽기 위한 준비" 링크가 없음')

    # 9. 본문 mermaid fence
    for f in files:
        if re.search(r'^```mermaid', text[f], re.M):
            errors.append(f'[그림] {f}  본문에 mermaid fence 직접 사용 — '
                          f'diagrams/src/*.mmd 로 옮기고 <img> 로 참조하십시오')

    # ── 보고 ────────────────────────────────────────────────────────────
    print(f'문서 {len(files)}개 검사\n')
    for e in errors:
        print('  오류  ' + e)
    if errors:
        print()
    for w in warns:
        print('  경고  ' + w)
    if warns:
        print()
    if VERBOSE:
        print(f'  링크 대상 {sum(len(a) for a in anchors.values())}개 앵커 확인')
        print(f'  그림 참조 {sum(img_used.values())}회 / {len(img_used)}개 파일')
    print(f'오류 {len(errors)}건, 경고 {len(warns)}건')
    return 1 if errors else 0


if __name__ == '__main__':
    sys.exit(main())
