# tikzffbd

`tikzffbd` is an early LaTeX library for producing polished Functional Flow
Block Diagrams without writing low-level TikZ positioning code. It targets
pdfLaTeX and Overleaf first and uses only engine-neutral LaTeX/TikZ features.

## Quick start

Place `tikzffbd.sty` and `tikzffbd-layout.code.tex` beside your document and load it:

```latex
\usepackage{tikzffbd}

\begin{ffbd}[theme=ocean]
  \start{entry}{Request received}
  \function{capture}{Capture input}
  \function{validate}{Validate input}
  \function{store}{Store data}
  \finish{exit}{Request complete}

  \flow{entry}{capture}
  \flow{capture}{validate}
  \flow{validate}{store}
  \flow{store}{exit}
\end{ffbd}
```

Identifiers such as `validate` are internal. Enable `debug=true` to
display them. Functions are numbered automatically; override a number with
`\function[number=2.3]{id}{Text}` or hide it with `number=none`.

## Structured flow commands

```latex
\branch[and]{source}{task-a,task-b,task-c}
\join[and]{task-a,task-b,task-c}{destination}

\branch[or]{check}{yes={Accepted},no={Rejected}}
\join[or]{yes,no}{continue}

\loopflow[condition={Try again},side=above]{later}{earlier}
```

Branches and joins create labeled logical connectors automatically. Branch
destinations can carry edge labels using `id={Label}`.

Group existing functions into a loop, sub-function, or custom structure with:

```latex
\structure[
  type={While loop},
  info={while data is invalid},
  style=shaded,
  inputs={load},
  outputs={validate}
]{retry-cycle}{load,validate}
```

The member list defines the container. `type` appears at its upper-left and
optional `info` (also spelled `condition`) appears at the top center. Styles are
`plain`, `dashed`, and lightly `shaded`. A function can belong to one structure.
Member annotations remain outside their function blocks but are included in the
container bounds.

Flows keep their normal declaration syntax. When a flow crosses a container,
its member endpoint must be listed in `inputs` or `outputs` as appropriate; the
renderer then splits the arrow at a geometry-derived boundary port. Invalid
crossings produce a package error. Structures are route obstacles for unrelated
flows, while internal `\loopflow` feedback stays inside its structure.

External annotations are available as:

```latex
\precondition{function-id}{System is initialized}
\timing{function-id}{Within 5 seconds}
\note{function-id}{Operator may cancel}
\annotation[Risk]{function-id}{Loss of external service}
```

## Appearance and layout

The built-in themes are `ocean` (default), `slate`, `forest`, `plum`,
and `monochrome`:

```latex
\begin{ffbd}[
  theme=forest,
  fill=true,
  font=sans,
  line-weight=thin,
  direction=right,
  wrap=true,
  max-columns=5,
  port-stub=6mm
]
```

Set `fill=false` for transparent blocks, `font=serif` for traditional
document typography, or `line-weight=heavy` for presentations. Use
`direction=down` for a vertical primary flow. Annotations can be placed
`below`, `above`, `left`, or `right`.

The layout engine measures the rendered blocks, logical connectors, annotations,
and condition labels before drawing. AND/OR connectors occupy their own stages,
with the same clear gap to neighboring blocks. Parallel lanes expand to fit tall
text and annotations. `column-sep` (default `36mm`) and `row-sep` (default `20mm`)
are nominal pitches; the engine increases them when the measured content needs
more room and keeps at least `6mm` of clear space between adjacent blocks.
`port-stub` (default `6mm`) sets the minimum straight run where an arrow
leaves or enters a block before its first or final bend.

Declaration order resolves lane ordering. With wrapping enabled, stages snake
after `max-columns`; **logical connectors count as stages**. Wrapped bands have
measured extents and a `10mm` gutter. Use `wrap=false` for one continuous row.
The complex example uses landscape paper with `max-columns=8` to retain readable
text. A final size check scales an over-wide diagram to `\linewidth` unless
`scale-to-fit=false` is selected. Page orientation alone cannot repair collisions.

Arrows use orthogonal routes checked against the measured rectangles of all
blocks and annotations, including transparent ones. Feedback uses an outer
corridor on the requested side. Annotations prefer the requested side and can
move to another clear position; condition labels are placed beside their routes
and checked against **all** arrows and other objects. Blocks stay fixed during
routing. This prevents drawing order or white label backgrounds from concealing
collisions.

Create a reusable organization theme with:

```latex
\ffbdDeclareTheme{corporate}{
  function-fill=blue!10,
  function-draw=blue!65!black,
  and-fill=green!25,
  and-draw=green!55!black,
  or-fill=orange!30,
  or-draw=orange!70!black,
  terminal-fill=blue!18,
  annotation-fill=gray!5,
  ink=black
}
```

## Examples

- `examples/basic.tex`: the five-block straight-line acceptance case.
- `examples/complex.tex`: 15 blocks, three branch operations, AND/OR
  connectors, parallel paths, annotations, and a loop.
- `examples/customization.tex`: a custom palette, vertical direction,
  transparent blocks, serif text, and heavy lines.
- `examples/structures.tex`: shaded and dashed containers, declared boundary
  ports, structure-to-structure flow, internal feedback, and an external bypass.

## Prototype status

Version 0.3 uses a deterministic measured layout and a bounded orthogonal
router, remaining portable to pdfLaTeX without shell escape or external programs.
Declare acyclic forward relationships and represent feedback using `\loopflow`;
forward cycles produce an error. The router searches central and obstacle-edge
corridors, then routes with extra bends. If none is clear it reports an error
instead of drawing through an object. It is not a general maze solver and does
not eliminate arrow-to-arrow crossings or shared branch/join trunks. Dense graphs
may still benefit from a different wrap width or page orientation. Width fitting
can shrink text; automatic page-size selection and pagination are not implemented.

Compile the examples from the project root:

```sh
mkdir -p build
TEXINPUTS=.: pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=build examples/basic.tex
TEXINPUTS=.: pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=build examples/complex.tex
```

For layout regression checks (Python 3 and TeX Live):

```sh
python3 tests/check_layout.py
python3 tests/check_layout.py --lua
```

The checks compile real diagrams and assert that measured objects do not overlap
and that every arrow segment clears every object. Fixtures cover long text,
skipped stages, annotations on all four sides, both directions, wrap boundaries,
transparent blocks, feedback, and the original examples. `layout-debug=true`
emits geometry to the TeX log for diagnosis; it does not change the picture.
