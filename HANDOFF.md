# tikzffbd project handoff

## Mission

Build an easy-to-use LaTeX library for polished Functional Flow Block Diagrams
(FFBDs) used in systems engineering. Users should describe functions and
relationships declaratively without writing low-level TikZ positioning code.

The initial audience is the owner's engineering team. The project may later
become a public/CTAN package. Ease of use and visual quality take priority over
arbitrary manual control.

## Agreed requirements

- Package name: `tikzffbd`.
- Primary targets: pdfLaTeX and Overleaf. Other popular engines are desirable.
- Function declarations use short internal identifiers:

  ```latex
  \function{validate}{Validate input}
  ```

- Identifiers remain hidden unless `debug=true` is enabled.
- Functions are numbered automatically, with optional manual overrides.
- Layout should be as automatic as practical.
- Declaration order should provide a predictable layout tie-breaker.
- Required constructs:
  - ordinary function blocks;
  - directed flows;
  - start and finish terminals;
  - AND and OR splits and joins;
  - parallel paths with more than two branches;
  - loops through an explicit `\loopflow` command;
  - entry/exit nodes;
  - preconditions, timing information, notes, and generic annotations;
  - optional edge/branch conditions.
- Logical connectors are visibly labeled `AND` or `OR` and use distinct colors.
- Annotations sit outside their associated function blocks.
- Default styling:
  - filled, slightly rounded blocks;
  - clean sans-serif text;
  - thin technical lines;
  - restrained professional colors.
- Environment options provide transparent blocks, serif text, heavier lines,
  direction, annotation placement, and layout spacing.
- Built-in palettes: `ocean`, `slate`, `forest`, `plum`, and `monochrome`.
- Users can define organization-wide themes through `\ffbdDeclareTheme`.
- Wrapping is enabled by default but can be disabled.
- Oversized diagrams are scaled to `\linewidth` by default.
- Acceptance examples:
  - easiest: five blocks in one straight left-to-right sequence;
  - hardest: 15 blocks with a loop, three branching operations, AND/OR logic,
    and parallel paths.

## Current implementation

The prototype is version `0.4.0`; its public API lives in `tikzffbd.sty`
and the measured layout engine in `tikzffbd-layout.code.tex`.

The public short commands are installed locally inside an `ffbd` environment,
which avoids polluting the rest of a document with generic names such as
`\function`, `\flow`, and `\note`.

Example:

```latex
\begin{ffbd}[theme=ocean]
  \start{entry}{Request received}
  \function{capture}{Capture input}
  \function{validate}{Validate input}
  \finish{exit}{Request complete}

  \flow{entry}{capture}
  \flow{capture}{validate}
  \flow{validate}{exit}
\end{ffbd}
```

Implemented public commands:

- `\function[<options>]{<id>}{<label>}`
- `\start[<options>]{<id>}{<label>}`
- `\finish[<options>]{<id>}{<label>}`
- `\flow[condition={<text>}]{<source>}{<target>}`
- `\branch[and|or]{<source>}{<target-list>}`
- `\join[and|or]{<source-list>}{<target>}`
- `\endrow`
- `\loopflow[condition={<text>},side=above|below]{<source>}{<target>}`
- `\structure[<options>]{<id>}{<member-list>}`
- `\precondition{<id>}{<text>}`
- `\timing{<id>}{<text>}`
- `\note{<id>}{<text>}`
- `\annotation[<type>]{<id>}{<text>}`
- `\ffbdDeclareTheme{<name>}{<theme keys>}`

`\structure` creates a one-level container around existing functions. It
supports custom type/info text, plain/dashed/shaded styles, declared input and
output members, automatic boundary ports, and context-aware routing.

Branch targets can carry conditions directly:

```latex
\branch[or]{check}{accepted={Valid},rework={Invalid}}
```

Function numbering is automatic. Use `number=2.3` to override it or
`number=none` to suppress it.

## General structures and loop containers

Version 0.3 implements rounded containers for loops, decomposed functions, and
custom structures. Members and their annotations determine the measured bounds;
the header reserves extra top space. `type` is drawn at upper-left, optional
`info`/`condition` at top center, and `style` accepts `plain`, `dashed`, or the
lightly filled `shaded` default.

`inputs` and `outputs` declare which members can participate in external flows.
Normal `\flow` declarations are split automatically at geometry-derived boundary
ports. Invalid crossings raise a package error. Unrelated containers participate
in obstacle routing, while internal routes exclude their own container. Internal
`\loopflow` feedback uses a corridor inside the shared structure. Membership is
one level: a function can belong to at most one structure, and finished structure
rectangles must not overlap.

The acceptance specimen is `examples/structures.tex`. Debug geometry uses
separate `FFBD STRUCT` and `FFBD PORT` records. Regression checks cover member and
annotation containment, ports on borders, minimum real-block stubs, unrelated
structure avoidance, internal-loop containment, horizontal and vertical layouts,
and undeclared crossing diagnostics.

## Layout architecture

The package uses a measured, deterministic layout portable to pdfLaTeX:

1. Functions and generated logical connectors participate in longest-path ranking.
   Connector stages reserve real space. Feedback edges do not affect rank.
2. The same TikZ styles measure and draw block, connector, annotation, and label
   rectangles. Stage widths and lane pitches grow to accommodate those bounds.
3. Declaration order determines lane ordering. Wrapping snakes after
   `max-columns`, counting connector stages. `\endrow` adds an explicit stage
   boundary. Occupied band extents determine wrap offsets with a common gutter.
4. Blocks are fixed before annotations and arrows are placed. Annotations can
   move to another side if their requested position is occupied.
5. A rectangle registry drives orthogonal routing: central corridors, obstacle
   boundaries, then routes with additional bends. Feedback uses outer corridors.
   An unrouteable edge produces an error, rather than a colliding fallback line.
6. Labels are placed after all routes, checking both objects and arrow segments.
7. The result is optionally scaled to the available width. Height diagnostics
   use the final scaled size.

Implementation is split between the public API/styles in `tikzffbd.sty` and
`tikzffbd-layout.code.tex`. Distribute both files together.

## Repository map

- `tikzffbd.sty` -- public API, graph declarations, and styles.
- `tikzffbd-layout.code.tex` -- measurement, layout, obstacle registry, routing.
- `tests/check_layout.py` -- compilation and geometric collision regressions.
- `README.md` -- user-facing quick start, API, themes, and options.
- `examples/basic.tex` -- five-block straight-line acceptance example.
- `examples/complex.tex` -- 15-block landscape acceptance example with three
  branches, AND/OR connectors, parallel paths, annotations, and a loop.
- `examples/customization.tex` -- custom theme, vertical flow, transparent
  blocks, serif type, heavy lines, and side annotations.
- `.gitignore` -- ignores build artifacts.
- `build/` -- tracked review PDFs plus ignored scratch builds and logs.

## Verification already performed

All four examples compile successfully with the installed pdfLaTeX/TeX Live
2023 toolchain:

```sh
mkdir -p build
TEXINPUTS=.: pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=build examples/basic.tex
TEXINPUTS=.: pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=build examples/complex.tex
TEXINPUTS=.: pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=build examples/customization.tex
TEXINPUTS=.: pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=build examples/structures.tex
```

The complete `python3 tests/check_layout.py --lua` suite passes without
geometry or typesetting warnings, and `git diff --check` passes. The suite runs
all examples with pdfLaTeX and the complex specimen with LuaLaTeX. XeLaTeX is
not installed in the development environment and has not been tested. Scratch
PDFs and logs are written below `build/tests/` and remain ignored.

## Layout revision after visual review

The original complex specimen was already landscape; compiling unchanged portrait
and landscape versions confirmed that page orientation did not remove overlaps.
Baseline PDFs and the original style are retained locally under `build/before/`.
The revised complex example uses landscape and `max-columns=8` for a readable,
two-row drawing. The original basic diagram retains its nominal 36mm pitch.

## Known limitations and engineering debt

- The bounded corridor router is not a general maze solver. A failed route raises
  a package error with spacing guidance. Arrow-to-arrow crossings and shared
  branch/join trunks are possible; boxes and text remain obstacles.
- Width fitting can reduce font sizes. Automatic orientation selection, pagination,
  and group-aware wrap selection are not implemented.
- Annotation placement is a side preference, not an absolute position constraint.
- Visual review still complements the geometry regression suite. Engine checks
  cover pdfLaTeX and LuaLaTeX; XeLaTeX and Overleaf have not been exercised here.
- A `.dtx`/`.ins` distribution, license, and CTAN packaging remain future work.

The structure implementation and its acceptance example now pass the pdfLaTeX
geometry suite in both horizontal and vertical directions. The complete
`python3 tests/check_layout.py --lua` run should remain the final release check.

Version 0.4 also preserves one-in/one-out branch lanes through intermediate
functions, provides `\endrow` for explicit snake-row boundaries, and assigns
normal-flow input/output ports from the direction of each row so a block never
reuses its input side for an output. Focused geometry regressions cover all three.
