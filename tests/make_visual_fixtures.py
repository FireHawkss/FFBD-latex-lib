"""Regenerate the development catalogue's ordinary LuaLaTeX sources."""
import json
from pathlib import Path
from run_contracts import source_inventory
ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / 'tests/fixtures/visual'
DEST.mkdir(exist_ok=True)

def document(body, options='', geometry='a4paper,landscape,margin=16mm'):
    return '\n'.join([r'\documentclass{article}', r'\usepackage['+geometry+r']{geometry}',
        r'\usepackage{tikzffbd}', r'\pagestyle{empty}', r'\begin{document}',
        r'\begin{ffbd}['+options+']', *body, r'\end{ffbd}', r'\end{document}', ''])

def nodes(count):
    return [rf'\start{{n1}}{{Begin}}'] + [rf'\function{{n{i}}}{{Step {i-1}}}' for i in range(2,count)] + [rf'\finish{{n{count}}}{{Complete}}']
def flows(start,end):
    return [rf'\flow{{n{i}}}{{n{i+1}}}' for i in range(start,end)]
def chain(count): return nodes(count)+flows(1,count)
def branches(count,logics,feedback=False):
    body=nodes(count);remaining=list(range(2,count));entry=1
    for i,logic in enumerate(logics):
        groups_left=len(logics)-i
        take=(len(remaining)-groups_left+1)//groups_left if groups_left>1 else len(remaining)
        arms=remaining[:take];remaining=remaining[take:]
        # Unequal arms: a short two-node arm and a longer arm.
        cut=max(1,len(arms)//3);left,right=arms[:cut],arms[cut:]
        exit_node=remaining.pop(0) if remaining else count
        body.append(rf'\branch[{logic}]{{n{entry}}}{{n{left[0]},n{right[0]}}}')
        body+=flows(left[0],left[-1])+flows(right[0],right[-1])
        body.append(rf'\join[{logic}]{{n{left[-1]},n{right[-1]}}}{{n{exit_node}}}')
        if feedback: body.append(rf'\loopflow[condition={{Retry {i+1}}}]{{n{right[-1]}}}{{n{right[0]}}}')
        entry=exit_node
    return body

cases={
 'chain-8':(chain(8),'max-columns=5'),
 'branches-15-unequal':(branches(15,['and']),'max-columns=7,multipage=true'),
 'branches-30-unequal':(branches(30,['or','and']),'direction=down,max-columns=8,multipage=true'),
 'joins-feedback-42':(branches(42,['and','or','or'],True),'max-columns=8,multipage=true'),
 'columns-soft':(chain(8),'max-columns=5,max-columns-strength=soft'),
 'large-64-single':(chain(64),'max-columns=5'),
 'large-64-multipage':(chain(64),'max-columns=5,multipage=true'),
 'irregular-gap-adversary':(chain(24)+[r'\loopflow[condition={Inspect again}]{n19}{n4}'],'max-columns=5,multipage=true'),
 'displaced-label-adversary':(nodes(16)+[rf'\flow[condition={{Condition {i}}}]{{n{i}}}{{n{i+1}}}' for i in range(1,16)],'direction=down,max-columns=5,multipage=true'),
}
b=branches(12,['or'],True)
for i in range(3,8): b.append(rf'\note{{n{i}}}{{A long annotation about the required checks before this operation may proceed.}}')
# Put conditions on the two declared branch arms.
b=[s.replace(r'{n2,n5}',r'{n2={Accepted},n5={Review needed}}') for s in b]
cases['dense-text-conditions']=(b,'max-columns=6,multipage=true')
b=chain(14)
b.append(r'\structure[type={Processing region},info={Steps 3 through 10},inputs={n4},outputs={n11}]{region}{n4,n5,n6,n7,n8,n9,n10,n11}')
cases['group-across-wrap']=(b,'max-columns=5,multipage=true')
b=nodes(12)
for i in range(1,12):
    b.append(rf'\flow{{n{i}}}{{n{i+1}}}')
    if i==3: b.append(r'\endrow')
    if i==7: b.append(r'\endrow[soft]')
cases['rowbreak-hard-soft']=(b,'max-columns=5')
for name,(body,opts) in cases.items(): (DEST/(name+'.tex')).write_text(document(body,opts))
# Independent diagrams isolate each hard note position without imposing an
# unrelated route conflict. All eight positions still use the real renderer.
positions=['top-left','top-center','top-right','left','right','bottom-left','bottom-center','bottom-right']
body=[]
for i,pos in enumerate(positions):
    body += [r'\begin{ffbd}',rf'\function{{n{i+1}}}{{{pos}}}',rf'\annotation[type=Note,position={pos}]{{n{i+1}}}{{Explicit position}}',r'\end{ffbd}']
s=document([], '')
s=s.replace('\\begin{ffbd}[]\n\\end{ffbd}', '\n'.join(body))
(DEST/'annotations-eight.tex').write_text(s)
body=[]
for scale in [.9,1,1.2]:
    body += [rf'\begin{{ffbd}}[scale={scale}]',*chain(8),r'\end{ffbd}']
s=document([], '').replace('\\begin{ffbd}[]\n\\end{ffbd}','\n'.join(body))
(DEST/'scale-explicit.tex').write_text(s)
(DEST/'columns-hard-conflict.tex').write_text(document(nodes(8)+flows(1,4)+[r'\endrow']+flows(4,8),'max-columns=2','paperwidth=35mm,paperheight=200mm,margin=10mm'))
manifest=ROOT/'tests/fixtures/manifest.json'
m=json.loads(manifest.read_text())
for f in m['fixtures']:
    if f['source'] is None:
        f['source']='tests/fixtures/visual/'+f['id']+'.tex';f['status']='source'
    if f['id']=='columns-hard-conflict':
        f['semantic']={'expected_diagnostic':'no-feasible-rows','competing_constraints':['max-columns','endrow','measured-width']}
        f['visual_prompt']='Does the measured-width diagnostic name the affected nodes and retained hard column/row constraints?'
    if f['source'].startswith('tests/fixtures/visual/'):
        actual=source_inventory(ROOT/f['source'])
        f['source_blocks']=actual['start']+actual['function']+actual['finish']
        f['semantic'].update(starts=actual['start'],finishes=actual['finish'],
            forward_flows=actual['flow']+actual['branch_arms']+actual['join_arms'],
            feedback_flows=actual['loopflow'],structures=actual['structure'],
            annotations=sum(actual[k] for k in ['annotation','note','precondition','timing']),
            split_logics=actual['branch_logics'],join_logics=actual['join_logics'])
manifest.write_text(json.dumps(m,indent=2)+'\n')
