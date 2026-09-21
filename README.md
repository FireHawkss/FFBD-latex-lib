# tikzffbd

`tikzffbd` is an early LaTeX library for producing polished Functional Flow
Block Diagrams without writing low-level TikZ positioning code. It targets
pdfLaTeX and Overleaf first and uses only engine-neutral LaTeX/TikZ features.

## Quick start

Place `tikzffbd.sty` beside your document and load it:

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
  max-columns=5
]
```

Set `fill=false` for transparent blocks, `font=serif` for traditional
document typography, or `line-weight=heavy` for presentations. Use
`direction=down` for a vertical primary flow. Annotations can be placed
`below`, `above`, `left`, or `right`.

The layout engine derives stages from the declared connections. Functions at
the same stage are centered in parallel lanes; declaration order resolves
lane ordering. With wrapping enabled, stages snake after `max-columns`.
Disable this with `wrap=false`. A final size check scales an over-wide
diagram to the current `\linewidth` unless `scale-to-fit=false` is selected.

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

## Prototype status

Version 0.1 uses a predictable layered layout rather than a general graph
solver. Declare acyclic forward relationships naturally and represent
feedback using `\loopflow`; this keeps the source portable to pdfLaTeX.
Very dense graphs may still need adjustments to `max-columns`, spacing,
orientation, or a landscape page.

Compile the examples from the project root:

```sh
mkdir -p build
TEXINPUTS=.: pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=build examples/basic.tex
TEXINPUTS=.: pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=build examples/complex.tex
```
