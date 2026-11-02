from pathlib import Path
import json,sys,subprocess,re,shutil
root=Path(__file__).resolve().parent
m=json.loads((root/'manifest.json').read_text()); skill=Path(m['skill_root'])
group=int(sys.argv[1]); phase=sys.argv[2] if len(sys.argv)>2 else 'initial'
for e in m['groups'][group-1]:
 rd=Path(e['run_dir'])
 if e['route']=='heavy' and phase=='initial':
  r=subprocess.run(['python3',str(skill/'scripts/reassemble_chunks.py'),'--run-dir',str(rd),'--strict'],capture_output=True,text=True)
  if r.returncode:raise RuntimeError(r.stdout+r.stderr)
  shutil.copyfile(rd/'03_reassembled.md',rd/'final.md')
 r=subprocess.run(['python3',str(skill/'scripts/verify_gates.py'),'--before',str(rd/'01_input.txt'),'--after',str(rd/'final.md'),'--genre','report','--json'],capture_output=True,text=True)
 (rd/f'gate_{phase}.log').write_text(r.stdout+r.stderr)
 match=re.search(r'^\{',r.stdout,re.M)
 if not match:raise RuntimeError(r.stdout+r.stderr)
 report=json.loads(r.stdout[match.start():]);(rd/f'gate_{phase}.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
 print(rd.name,r.returncode,report['change_rate']['rate'],[x['code'] for x in report['golden']])
 if r.returncode>=2:raise RuntimeError('gate failed: '+str(rd))
