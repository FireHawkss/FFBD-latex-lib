#!/usr/bin/env python3
"""Compile real diagrams and check their emitted geometry, not source patterns."""
import itertools
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build' / 'tests'
BUILD.mkdir(parents=True, exist_ok=True)
ENV = dict(os.environ, TEXINPUTS=f'{ROOT}:', max_print_line='1000')


def intersects(a, b, tolerance=0.05):
    return (max(a[0], a[2]) > b[0] + tolerance
            and min(a[0], a[2]) < b[2] - tolerance
            and max(a[1], a[3]) > b[1] + tolerance
            and min(a[1], a[3]) < b[3] - tolerance)


def segment_length(segment):
    return abs(segment[2] - segment[0]) + abs(segment[3] - segment[1])


def check(name, source, engine='pdflatex', extended=False):
    source = source.replace(r'\begin{ffbd}[', r'\begin{ffbd}[layout-debug=true,')
    source = source.replace(r'\begin{ffbd}' + '\n', r'\begin{ffbd}[layout-debug=true]' + '\n')
    tex = BUILD / f'{name}.tex'
    tex.write_text(source)
    result = subprocess.run([engine, '-interaction=nonstopmode', '-halt-on-error',
                             f'-output-directory={BUILD}', str(tex)],
                            cwd=ROOT, env=ENV, text=True, stdout=subprocess.PIPE)
    (BUILD / f'{name}.stdout').write_text(result.stdout)
    assert result.returncode == 0, f'{name}: compilation failed (see {name}.stdout)'
    assert not re.search(r'Missing character|Overfull|Underfull', result.stdout), f'{name}: typesetting warning'
    diagrams = result.stdout.split('FFBD BEGIN')[1:]
    assert diagrams, f'{name}: missing geometry'
    all_boxes, all_segments, all_structures, all_ports = [], [], [], []
    for diagram in diagrams:
        boxes, segments, structures, ports = [], [], [], []
        for line in diagram.split('FFBD END')[0].splitlines():
            parts = line.split()
            if parts[:2] == ['FFBD', 'BOX']:
                boxes.append((parts[2], tuple(map(float, parts[3:]))))
            if parts[:2] == ['FFBD', 'SEG']:
                segments.append((parts[2:4], tuple(map(float, parts[4:]))))
            if parts[:2] == ['FFBD', 'STRUCT']:
                structures.append((parts[2], tuple(map(float, parts[3:]))))
            if parts[:2] == ['FFBD', 'PORT']:
                ports.append((tuple(parts[2:6]), tuple(map(float, parts[6:]))))
        assert boxes and segments, f'{name}: missing geometry'
        for (an, a), (bn, b) in itertools.combinations(boxes, 2):
            assert not intersects(a, b), f'{name}: boxes {an} and {bn} overlap'
        for ends, segment in segments:
            x1, y1, x2, y2 = segment
            assert abs(x1-x2) < .05 or abs(y1-y2) < .05, f'{name}: non-orthogonal segment'
            for bn, box in boxes:
                # Endpoints touch their blocks, but must never enter their interiors.
                assert not intersects(segment, box), f'{name}: {ends} crosses {bn}: {segment}, {box}'
        all_boxes.extend(boxes)
        all_segments.extend(segments)
        all_structures.extend(structures)
        all_ports.extend(ports)
    print(f'{name}: {len(all_boxes)} objects, {len(all_segments)} segments; no collisions', flush=True)
    if extended:
        return all_boxes, all_segments, all_structures, all_ports
    return all_boxes, all_segments


def document(body, options=''):
    return (r'\documentclass{article}\usepackage[paperwidth=500mm,paperheight=500mm,margin=10mm]{geometry}'
            r'\usepackage{tikzffbd}\pagestyle{empty}\begin{document}' '\n'
            r'\begin{ffbd}[' + options + ']\n' + body + '\n'
            r'\end{ffbd}\end{document}')


def check_structures(name, source):
    boxes, segments, structures, ports = check(name, source, extended=True)
    bounds = dict(boxes)
    containers = dict(structures)
    assert set(containers) == {'retry-cycle', 'refinement'}, f'{name}: missing structures'
    membership = {
        'load': 'retry-cycle', 'validate': 'retry-cycle',
        'refine': 'refinement', 'approve': 'refinement',
    }
    for member, structure in membership.items():
        box, outer = bounds[member], containers[structure]
        assert (outer[0] < box[0] and outer[1] < box[1]
                and outer[2] > box[2] and outer[3] > box[3]), (
                    f'{name}: {member} is not inside {structure}')
    annotation, outer = bounds['annotation-validate'], containers['retry-cycle']
    assert (outer[0] < annotation[0] and outer[1] < annotation[1]
            and outer[2] > annotation[2] and outer[3] > annotation[3]), (
                f'{name}: member annotation is not inside retry-cycle')

    port_structures = {}
    roles = []
    for (port, structure, member, role), point in ports:
        outer = containers[structure]
        x, y = point
        on_vertical = (abs(x - outer[0]) < .05 or abs(x - outer[2]) < .05)
        on_horizontal = (abs(y - outer[1]) < .05 or abs(y - outer[3]) < .05)
        assert (on_vertical or on_horizontal), f'{name}: {port} is not on {structure}'
        assert outer[0] - .05 <= x <= outer[2] + .05
        assert outer[1] - .05 <= y <= outer[3] + .05
        port_structures[port] = structure
        roles.append((structure, member, role))
    assert sorted(roles) == sorted([
        ('retry-cycle', 'load', 'input'),
        ('retry-cycle', 'validate', 'output'),
        ('refinement', 'refine', 'input'),
        ('refinement', 'approve', 'output'),
    ]), f'{name}: incorrect boundary ports'

    # Every structure is an obstacle except for its own internal/crossing route.
    for ends, segment in segments:
        allowed = {membership[end] for end in ends if end in membership}
        allowed.update(port_structures[end] for end in ends if end in port_structures)
        for structure, outer in containers.items():
            if structure not in allowed:
                assert not intersects(segment, outer), (
                    f'{name}: {ends} crosses unrelated {structure}')

    loop = [segment for ends, segment in segments if ends == ['validate', 'load']]
    assert loop, f'{name}: missing internal feedback route'
    outer = containers['retry-cycle']
    for segment in loop:
        for x, y in ((segment[0], segment[1]), (segment[2], segment[3])):
            assert outer[0] - .05 <= x <= outer[2] + .05
            assert outer[1] - .05 <= y <= outer[3] + .05

    minimum_stub = 6 * 72.27 / 25.4
    for member, at_start in (('validate', True), ('approve', True),
                             ('load', False), ('refine', False)):
        candidates = [(ends, segment) for ends, segment in segments
                      if (ends[0] == member if at_start else ends[1] == member)
                      and ('@p' in ends[1] if at_start else '@p' in ends[0])]
        assert candidates, f'{name}: missing split segment at {member}'
        endpoint_segment = candidates[0][1] if at_start else candidates[-1][1]
        assert segment_length(endpoint_segment) >= minimum_stub - .05, (
            f'{name}: short block stub at {member}')


def main():
    for name in ('basic', 'complex', 'customization'):
        boxes, segments = check(name, (ROOT / f'examples/{name}.tex').read_text())
        if name == 'basic':
            blocks = [b for node, b in boxes if not node.startswith('annotation-')]
            centers = [((b[0]+b[2])/2, (b[1]+b[3])/2) for b in blocks]
            for (x1, y1), (x2, y2) in zip(centers, centers[1:]):
                assert abs(x2-x1-36*72.27/25.4) < .02, 'basic pitch changed'
                assert abs(y2-y1) < .02, 'basic row is not straight'
        if name == 'complex':
            bounds = dict(boxes)
            minimum_stub = 6 * 72.27 / 25.4
            for target in ('safety', 'resources', 'schedule'):
                route = [segment for ends, segment in segments
                         if ends == ['@c3', target]]
                assert route, f'complex: missing wrapped split route to {target}'
                assert abs(route[0][0] - bounds['@c3'][2]) < .05
                assert segment_length(route[0]) >= minimum_stub - .05
                assert route[0][2] > route[0][0], (
                    'complex: wrapped split must leave the AND connector on its right')
                assert abs(route[-1][2] - bounds[target][2]) < .05
                assert segment_length(route[-1]) >= minimum_stub - .05
                assert route[-1][0] > route[-1][2], (
                    f'complex: wrapped split must enter {target} on its right')
            feedback = [segment for ends, segment in segments
                        if ends == ['rework', 'execute']]
            assert segment_length(feedback[0]) >= minimum_stub - .05
            assert segment_length(feedback[-1]) >= minimum_stub - .05
    specimen = (ROOT / 'examples/complex.tex').read_text()
    check('complex-unwrapped', specimen.replace('wrap=true', 'wrap=false'))
    check('complex-portrait', specimen.replace('landscape,margin', 'margin'))
    # A forward edge must detour around intervening blocks and labels.
    chain = r'''
\start{s}{Start}
\function{a}{A much longer function description that occupies several lines}
\function{b}{Middle task}
\function{c}{Last task}
\finish{t}{Finish}
\flow{s}{a}\flow{a}{b}\flow{b}{c}\flow{c}{t}
\flow[condition={Skip intermediate operations when authorized}]{s}{t}
\note{b}{An external annotation with several lines of text}
\timing{b}{Within the allocated response window}
\loopflow[condition={Repeat},side=above]{c}{a}
\loopflow[condition={Retry},side=below]{c}{a}
'''
    for direction in ('right', 'down'):
        for side in ('above', 'below', 'left', 'right'):
            check(f'obstacles-{direction}-{side}', document(chain,
                  f'wrap=false,direction={direction},annotations={side},fill=false'))
    parallel = r'''
\start{s}{Start}
\function{a}{First lane with a very long description that must expand the block}
\function{b}{Second lane}
\function{c}{Third lane}
\function{d}{Continue}
\finish{t}{Finish}
\branch[or]{s}{a={First choice},b={Second choice},c={Third choice}}
\join[and]{a,b,c}{d}\flow{d}{t}
\note{a}{First annotation spans several lines and needs its own space}
\note{b}{Second annotation}\note{c}{Third annotation}
'''
    for direction in ('right', 'down'):
        for columns in (2, 3, 5):
            check(f'parallel-{direction}-{columns}', document(parallel,
                  f'direction={direction},max-columns={columns},row-sep=12mm,column-sep=28mm'))
    check('parallel-custom-stub', document(parallel,
          'direction=right,max-columns=5,port-stub=9mm'))
    # Reused node IDs and different layout options must not leak between pictures.
    first = document(r'\start{s}{Start}\function{a}{Work}\finish{t}{End}'
                     r'\flow{s}{a}\flow{a}{t}', 'direction=down,annotations=right')
    second = (ROOT / 'examples/basic.tex').read_text().split(r'\begin{document}')[1]
    check('multiple-diagrams', first.replace(r'\end{document}', r'\newpage' + second))
    structure_source = (ROOT / 'examples/structures.tex').read_text()
    check_structures('structures', structure_source)
    vertical_structure_source = structure_source.replace(
        r'\usepackage[landscape,margin=16mm]{geometry}',
        r'\usepackage[paperwidth=500mm,paperheight=500mm,margin=10mm]{geometry}')
    check_structures('structures-down',
                     vertical_structure_source.replace(
                         'wrap=false,', 'wrap=false,direction=down,'))

    invalid_crossing = document(r'''
\start{outside}{Outside}
\function{inside}{Inside}
\flow{outside}{inside}
\structure[type={Protected},outputs={inside}]{protected}{inside}
''', 'wrap=false')
    invalid = BUILD / 'structure-invalid-port.tex'
    invalid.write_text(invalid_crossing)
    result = subprocess.run(['pdflatex', '-interaction=nonstopmode', '-halt-on-error',
                             f'-output-directory={BUILD}', str(invalid)],
                            cwd=ROOT, env=ENV, text=True, stdout=subprocess.PIPE)
    assert result.returncode != 0 and 'crosses structure' in result.stdout
    print('structure-invalid-port: clear undeclared-port diagnostic', flush=True)

    cycle = BUILD / 'cycle.tex'
    cycle.write_text(document(r'\function{a}{A}\function{b}{B}\flow{a}{b}\flow{b}{a}'))
    result = subprocess.run(['pdflatex', '-interaction=nonstopmode', '-halt-on-error',
                             f'-output-directory={BUILD}', str(cycle)],
                            cwd=ROOT, env=ENV, text=True, stdout=subprocess.PIPE)
    assert result.returncode != 0 and 'Forward flows contain a cycle' in result.stdout
    print('cycle: clear diagnostic instead of runaway layout', flush=True)
    if '--lua' in sys.argv:
        check('complex-lua', (ROOT / 'examples/complex.tex').read_text(), 'lualatex')


if __name__ == '__main__':
    main()
