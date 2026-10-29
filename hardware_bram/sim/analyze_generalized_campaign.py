#!/usr/bin/env python3
"""Summarize measured totals, budget failures and passive solver bottlenecks."""
import argparse
import csv
import json
import os
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]

def analyze(out):
    rows=list(csv.DictReader((out/'summary.csv').open()))
    fields=('k','h','e','m','workloads','cycles','iter','policy_cycles','policy_stall',
            'policy_actions','solver_jobs','max_solver_cycles')
    converted=[{**row,**{key:int(row[key]) for key in fields}} for row in rows]
    progress=json.loads((out/'progress.json').read_text())
    phase_rows=[]
    for row in converted:
        record=json.loads((ROOT/row['evidence']/'integration.json').read_text())
        phase=record['policy_replay']['phase_cycles']
        if len(phase)!=32:raise ValueError('missing clock-checked phase profile')
        groups={'setup':sum(phase[i] for i in (2,3,4)),
                'candidate_scan_replay':sum(phase[i] for i in (5,9,12)),
                'memo_evaluate_finish_return':sum(phase[i] for i in (6,7,8,10,11)),
                'unique_root':phase[13],'memo_clear':phase[1]}
        groups['other']=sum(phase)-sum(groups.values())
        phase_rows.append({'k':row['k'],'h':row['h'],'all_completed_job_clocks':sum(phase),
                           'reported_run_policy_clocks':row['policy_cycles'],**groups})
    budget=300000
    excessive=[row for row in converted if row['policy_cycles']>budget]
    pareto=[row for row in converted if not any(
        other['cycles']<=row['cycles'] and other['policy_cycles']<=row['policy_cycles'] and
        (other['cycles']<row['cycles'] or other['policy_cycles']<row['policy_cycles']) for other in converted)]
    result={'completed':len(converted),'requested':progress['cells'],
        'complete':len(converted)==progress['cells'] and not progress['failed'],
        'target_policy_cycles':budget,'within_target':len(converted)-len(excessive),
        'exceeded_target':excessive,'best_total_cycles':min(converted,key=lambda row:row['cycles']) if converted else None,
        'best_within_policy_target':min((row for row in converted if row['policy_cycles']<=budget),key=lambda row:row['cycles'],default=None),
        'worst_policy_cycles':max(converted,key=lambda row:row['policy_cycles']) if converted else None,
        'total_policy_cycle_pareto':pareto,
        'pareto_limit':'This two-metric set does not include resource usage or physical timing.',
        'phase_scope':'All completed solver transactions; run CSR accounting can exclude cancelled/out-of-run results.',
        'phase_rows':phase_rows,'errors':progress['failed']}
    (out/'analysis.json').write_text(json.dumps(result,indent=2)+'\n')
    with (out/'phase_summary.csv').open('w') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(phase_rows[0]) if phase_rows else ['k','h'])
        writer.writeheader();writer.writerows(phase_rows)
    if converted:
        os.environ.setdefault('MPLCONFIGDIR','/tmp/bbht-general-analysis-matplotlib')
        import matplotlib
        matplotlib.use('Agg')
        import matplotlib.pyplot as plt
        worst=sorted(converted,key=lambda row:row['policy_cycles'],reverse=True)[:5]
        selected=[next(p for p in phase_rows if (p['k'],p['h'])==(r['k'],r['h'])) for r in worst]
        labels=[f"capacity={r['k']}, lookahead={r['h']}" for r in worst]
        fig,ax=plt.subplots(figsize=(11,5.8),constrained_layout=True);left=[0.]*len(selected)
        for key,title in [('setup','Build / map / prepare'),('candidate_scan_replay','Scan / cache / replay'),
                          ('memo_evaluate_finish_return','Memo / evaluate / finish / return'),
                          ('unique_root','Unique root'),('memo_clear','Memo clear'),('other','Other')]:
            values=[r[key]/1000 for r in selected]
            ax.barh(labels,values,left=left,label=title)
            left=[a+b for a,b in zip(left,values)]
        ax.set_xlabel('Actual completed solver clocks (thousands)')
        ax.set_title('Slowest measured policy configurations: phase breakdown')
        ax.legend(loc='upper left',bbox_to_anchor=(1.0,1.0));fig.savefig(out/'policy_bottlenecks.png',dpi=180)
        plt.close(fig)
        # Retain enough digits to distinguish neighbouring optimum candidates;
        # the full-range colour scale is dominated by the single-slot cases.
        import numpy as np
        from matplotlib.patches import Rectangle
        plan=json.loads((out/'manifest.json').read_text())['plan'];ks=plan['capacities'];hs=plan['lookahead_shots']
        fig,axes=plt.subplots(1,3,figsize=(18,5.8),constrained_layout=True)
        for ax,field,title,scale,precision in zip(axes,['policy_cycles','policy_stall','cycles'],
                ['Policy cycles (thousands)','Exposed policy stall (thousands)','Total accelerator cycles (millions)'],
                [1000,1000,1000000],[1,1,3]):
            values=np.full((len(ks),len(hs)),np.nan)
            for row in converted:values[ks.index(row['k']),hs.index(row['h'])]=row[field]/scale
            image=ax.imshow(np.ma.masked_invalid(values),origin='lower',aspect='auto',cmap='YlOrRd')
            ax.set_xticks(range(len(hs)),hs);ax.set_yticks(range(len(ks)),ks)
            ax.set_xlabel('Lookahead-Shots');ax.set_ylabel('Checkpoint-Capacity');ax.set_title(title)
            for row in converted:
                x=hs.index(row['h']);y=ks.index(row['k'])
                ax.text(x,y,f'{row[field]/scale:.{precision}f}',ha='center',va='center',fontsize=8)
                if field=='policy_cycles' and row[field]>budget:
                    ax.add_patch(Rectangle((x-.48,y-.48),.96,.96,fill=False,edgecolor='black',linewidth=2))
                if field=='cycles' and row is result['best_total_cycles']:
                    ax.add_patch(Rectangle((x-.48,y-.48),.96,.96,fill=False,edgecolor='#008d39',linewidth=3))
            fig.colorbar(image,ax=ax,shrink=.75)
        fig.suptitle(f"Actual Main-IP RTL; {len(converted)}/{progress['cells']} cells, {plan['workloads']} workloads each; iteration engines={plan['iteration_engines']}, square engines={plan['square_engines']}")
        fig.savefig(out/'kh_heatmap_detail.png',dpi=180);fig.savefig(out/'kh_heatmap_detail.svg');plt.close(fig)
    print(json.dumps({'completed':result['completed'],'complete':result['complete'],
        'within_target':result['within_target'],'exceeded':[(r['k'],r['h'],r['policy_cycles']) for r in excessive],
        'best':result['best_total_cycles']}),flush=True)
    return result

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();analyze(args.out.resolve())
