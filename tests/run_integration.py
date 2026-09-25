"""Compile, trace, check and benchmark the visual catalogue using ordinary LuaLaTeX.

Usage: python3 tests/run_integration.py [fixture-id ...] [--output build/release]
PDFs, JSON traces, logs, timings and report.json are development artifacts.
"""
import argparse
import itertools
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from contract_schema import validate_trace

ROOT=Path(__file__).resolve().parents[1]

def overlap(a,b):
    return (a['x_sp']<b['x_sp']+b['width_sp'] and b['x_sp']<a['x_sp']+a['width_sp']
        and a['y_sp']<b['y_sp']+b['height_sp'] and b['y_sp']<a['y_sp']+a['height_sp'])
def hit(r,a,b):
    x,y,w,h=(r[k] for k in ('x_sp','y_sp','width_sp','height_sp'))
    if a['x_sp']==b['x_sp']:
        return x<a['x_sp']<x+w and max(a['y_sp'],b['y_sp'])>y and min(a['y_sp'],b['y_sp'])<y+h
    return y<a['y_sp']<y+h and max(a['x_sp'],b['x_sp'])>x and min(a['x_sp'],b['x_sp'])<x+w

def invariants(trace):
    errors=validate_trace(trace)
    o=trace['objects'];s=o['Scene'];spec=o['Spec'];frame=o['Frame']
    def check(value,message):
        if not value: errors.append(message)
    check(s['scale']==frame['scale']==spec['options']['scale'],'explicit scale changed')
    nodes={};flow_legs={}
    for pi,page in enumerate(s['pages']):
        for nid,r in page['node_rects'].items():
            check(nid not in nodes,'repeated node '+nid);nodes[nid]=(pi,r)
        objects=list(page['node_rects'].items())
        text=[]
        for key in ('annotations','edge_labels','continuation_markers','structure_texts'):
            for item in page.get(key,[]):
                text.append((item.get('id',item.get('flow_id',key)),item['rect']))
        objects+=text
        for (aid,a),(bid,b) in itertools.combinations(objects,2):
            check(not overlap(a,b),f'overlap {aid} / {bid}')
        for fid,path in page['flow_paths'].items():
            flow_legs.setdefault(fid,[]).append((pi,path))
            for a,b in zip(path['points'],path['points'][1:]):
                for oid,r in objects:
                    # Continuation text meets its own endpoint on a box edge.
                    check(not hit(r,a,b),f'flow {fid} crosses {oid}')
            pts=path['points']
            for a,b,c in zip(pts,pts[1:],pts[2:]):
                dot=(b['x_sp']-a['x_sp'])*(c['x_sp']-b['x_sp'])+(b['y_sp']-a['y_sp'])*(c['y_sp']-b['y_sp'])
                check(dot>=0,f'port reversal {fid}')
        for gid,r in page['structure_rects'].items():
            owner=page.get('structure_owner_by_id',{}).get(gid,gid)
            group=next(g for g in spec['structures'] if g['id']==owner)
            for nid,nr in page['node_rects'].items():
                if nid in group['member_ids']:
                    check(r['x_sp']<=nr['x_sp'] and r['y_sp']<=nr['y_sp'] and nr['x_sp']+nr['width_sp']<=r['x_sp']+r['width_sp'] and nr['y_sp']+nr['height_sp']<=r['y_sp']+r['height_sp'],f'group containment {gid}/{nid}')
                else: check(not overlap(r,nr),f'group intrusion {gid}/{nid}')
        if spec['options']['multipage']:
            b=page['bounding_rect']
            check(b['x_sp']>=0 and b['y_sp']>=0 and (b['x_sp']+b['width_sp'])*s['scale']<=frame['content_width_sp'] and (b['y_sp']+b['height_sp'])*s['scale']<=frame['content_height_sp'],'page bounds')
    check(set(nodes)=={n['id'] for n in spec['nodes']},'node coverage')
    check(set(flow_legs)=={f['id'] for f in spec['flows']},'flow coverage')
    def on_boundary(p,r):
        x,y=p['x_sp'],p['y_sp'];l,t=r['x_sp'],r['y_sp'];right,bottom=l+r['width_sp'],t+r['height_sp']
        return (x in (l,right) and t<=y<=bottom) or (y in (t,bottom) and l<=x<=right)
    for f in spec['flows']:
        legs=flow_legs.get(f['id'],[])
        for endpoint,key in [('source',0),('target',-1)]:
            pi,r=nodes[f[endpoint]]
            legs_here=[path for p,path in legs if p==pi]
            check(bool(legs_here) and on_boundary(legs_here[0]['points'][key],r),f'flow endpoint {f["id"]}/{endpoint}')
        for g in spec['structures']:
            inside_source=f['source'] in g['member_ids'];inside_target=f['target'] in g['member_ids']
            if inside_source != inside_target:
                role='output_member_ids' if inside_source else 'input_member_ids'
                check(f['source' if inside_source else 'target'] in g[role],f'undeclared boundary {f["id"]}')
                check(any(path.get('boundary_port_ids') for _,path in legs),f'missing group port {f["id"]}')
    for page in s['plan']['pages']:
        for i,row in enumerate(page['rows']):
            check(row['direction_sign']==(1 if i%2==0 else -1),'serpentine direction')
            if spec['options'].get('max_columns_strength','hard')=='hard':
                check(len(row['ordered_node_ids'])<=spec['options'].get('max_columns',5),'hard columns')
    for c in spec['constraints']:
        if c['kind']=='row-break' and c['strength']=='hard':
            check(any(row['ordered_node_ids'][-1]==c['target_ids'][0] for page in s['plan']['pages'] for row in page['rows']),'hard row break')
    for note in spec['annotations']:
        if note.get('preferred_position') and note.get('position_strength')!='soft':
            actual=next(n for p in s['pages'] for n in p['annotations'] if n['id']==note['id'])
            check(actual['position']==note['preferred_position'],'hard annotation position')
    return errors

def run(fixture,out):
    ident=fixture['id'];source=(ROOT/fixture['source']).read_text()
    wrapper=out/(ident+'.tex')
    wrapper.write_text(source.replace(r'\begin{document}',r'\begin{document}\directlua{dofile("tests/capture_scene.lua")}'))
    env=dict(os.environ,FFBD_TEST_OUTPUT=str(out))
    runs=[];previous=None;errors=[];traces=[]
    for iteration in range(2):
        for old in out.glob(ident+'-env-*.json'):old.unlink()
        start=time.perf_counter()
        command=['/usr/bin/time','-f','%M','-o',str(out/(ident+'.rss')),'lualatex','-no-shell-escape','-interaction=nonstopmode','-halt-on-error','-output-directory='+str(out),str(wrapper)]
        result=subprocess.run(command,cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=120)
        runs.append({'seconds':round(time.perf_counter()-start,3),'peak_rss_kib':int((out/(ident+'.rss')).read_text().splitlines()[-1])})
        (out/(ident+f'-{iteration}.stdout')).write_text(result.stdout)
        traces=[json.loads(p.read_text()) for p in sorted(out.glob(ident+'-env-*.json'))]
        expected=fixture['semantic'].get('expected_diagnostic')
        if expected:
            if not result.returncode or '['+expected+']' not in result.stdout: errors.append('expected diagnostic '+expected)
        elif result.returncode:
            errors.append('compilation: '+' '.join(re.findall(r'^!.*',result.stdout,re.M)))
        else:
            if not traces: errors.append('missing integrated traces')
            for trace in traces:errors+=invariants(trace)
        canonical=json.dumps(traces,sort_keys=True)
        if previous is not None and canonical!=previous:errors.append('nondeterministic trace')
        previous=canonical
    log=(out/(ident+'.log')).read_text()
    overflow=bool(re.search(r'Overfull \\[hv]box',log))
    if overflow and ident!='large-64-single': errors.append('TeX content overflow')
    scenes=[t['objects']['Scene'] for t in traces]
    return {'id':ident,'source':fixture['source'],'passed':not errors,'errors':sorted(set(errors)),
        'runs':runs,'tex_overflow':overflow,'pages':sum(len(s['pages']) for s in scenes),
        'quality':[s['quality'] for s in scenes],
        'diagnostics':[d for s in scenes for d in s['diagnostics']]}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('ids',nargs='*');parser.add_argument('--output',default='build/release')
    args=parser.parse_args();out=(ROOT/args.output).resolve();out.mkdir(parents=True,exist_ok=True)
    fixtures=json.loads((ROOT/'tests/fixtures/manifest.json').read_text())['fixtures']
    if args.ids: fixtures=[f for f in fixtures if f['id'] in args.ids]
    results=[]
    for f in fixtures:
        r=run(f,out);results.append(r);print(r['id'], 'PASS' if r['passed'] else 'FAIL',r['errors'],flush=True)
    report={'engine':subprocess.check_output(['lualatex','--version'],text=True).splitlines()[0],
        'timing_note':'First/repeat compilation; OS caches not flushed. Peak RSS includes LuaLaTeX.','results':results}
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    return int(any(not r['passed'] for r in results))
if __name__=='__main__':sys.exit(main())
