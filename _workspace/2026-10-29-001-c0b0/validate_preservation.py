from pathlib import Path
from collections import Counter
import re, json, sys

def body(text):
    return re.sub(r'\n*<!--\s*HUMANIZE-SUMMARY\b.*', '', text, flags=re.S).rstrip()+'\n'

def features(text):
    return {
      'English tokens':Counter(re.findall(r"[A-Za-z]+(?:[-_’'][A-Za-z0-9]+)*", text)),
      'English phrases':Counter(re.findall(r"[A-Za-z]+(?:[-_’'][A-Za-z0-9]+)*(?:[ \t]+[A-Za-z]+(?:[-_’'][A-Za-z0-9]+)*)+", text)),
      'numbers':Counter(re.findall(r'\d+(?:[.,]\d+)*',text)),
      'formulas':re.findall(r'\$\$[\s\S]*?\$\$|(?<![$\\])\$(?!\$)[^\n$]*?(?<!\\)\$(?!\$)',text),
      'code fences':re.findall(r'^```[^\n]*\n.*?^```[^\n]*$',text,re.M|re.S),
      'inline code':re.findall(r'(?<!`)`[^`\n]+`(?!`)',text),
      'headings':re.findall(r'^#{1,6} .+$',text,re.M),
      'link targets':re.findall(r'\]\(([^)]+)\)',text),
      'callout symbols':Counter(re.findall(r'[💡🔍❓⚠🔑✏]',text)),
    }

def validate(rd):
    rd=Path(rd); a=body((rd/'01_input.txt').read_text()); b=body((rd/'final.md').read_text())
    af,bf=features(a),features(b); issues={}
    for key in af:
      if af[key]!=bf[key]:
        if isinstance(af[key],Counter):
          issues[key]={'removed':dict(af[key]-bf[key]),'added':dict(bf[key]-af[key])}
        else: issues[key]={'before_count':len(af[key]),'after_count':len(bf[key])}
    return issues

if __name__=='__main__':
    arg=Path(sys.argv[1]); data=json.loads(arg.read_text()) if arg.suffix=='.json' else None
    entries=(data.get('files') or sum(data['groups'],[])) if data else [{'run_dir':str(arg)}]
    failures={Path(e['source']).name if 'source' in e else Path(e['run_dir']).name:validate(e['run_dir']) for e in entries if (Path(e['run_dir'])/'final.md').exists()}
    failures={k:v for k,v in failures.items() if v}
    print(json.dumps(failures,ensure_ascii=False,indent=2));sys.exit(bool(failures))
