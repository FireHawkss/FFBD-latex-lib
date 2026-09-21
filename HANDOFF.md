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

The prototype is version `0.1.0` and lives in `tikzffbd.sty`.

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
- `\loopflow[condition={<text>},side=above|below]{<source>}{<target>}`
- `\precondition{<id>}{<text>}`
- `\timing{<id>}{<text>}`
- `\note{<id>}{<text>}`
- `\annotation[<type>]{<id>}{<text>}`
- `\ffbdDeclareTheme{<name>}{<theme keys>}`

Branch targets can carry conditions directly:

```latex
\branch[or]{check}{accepted={Valid},rework={Invalid}}
```

Function numbering is automatic. Use `number=2.3` to override it or
`number=none` to suppress it.

## Layout architecture

The package uses a deterministic layered layout that remains portable to
pdfLaTeX:

1. Forward relationships from `\flow`, `\branch`, and `\join` form an acyclic
   ranking graph.
2. Repeated longest-path relaxation assigns each function a logical stage.
3. Functions at the same stage are placed in centered parallel lanes.
4. Declaration order resolves ordering within a stage.
5. Explicit loop edges are excluded from rank calculation and routed around
   the finished graph.
6. With wrapping enabled, stages snake after `max-columns`.
7. The finished TikZ picture is measured and optionally scaled to
   `\linewidth`.

This is intentionally not a general graph-layout solver. TikZ graph-drawing's
stronger algorithms generally depend on LuaTeX, while pdfLaTeX/Overleaf was a
primary requirement. The API is declarative enough that a LuaLaTeX layout
backend could be added later without changing diagram source.

## Repository map

- `tikzffbd.sty` -- package and layout implementation.
- `README.md` -- user-facing quick start, API, themes, and options.
- `examples/basic.tex` -- five-block straight-line acceptance example.
- `examples/complex.tex` -- 15-block landscape acceptance example with three
  branches, AND/OR connectors, parallel paths, annotations, and a loop.
- `examples/customization.tex` -- custom theme, vertical flow, transparent
  blocks, serif type, heavy lines, and side annotations.
- `.gitignore` -- ignores build artifacts.
- `build/` -- locally generated PDFs and logs; intentionally ignored.

## Verification already performed

All three examples compile successfully with the installed pdfLaTeX/TeX Live
2023 toolchain:

```sh
mkdir -p build
TEXINPUTS=.: pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=build examples/basic.tex
TEXINPUTS=.: pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=build examples/complex.tex
TEXINPUTS=.: pdflatex -interaction=nonstopmode -halt-on-error \
  -output-directory=build examples/customization.tex
```

The logs were scanned for LaTeX/package warnings and overfull/underfull boxes;
none were present. `git diff --check` passes.

The basic example also compiles successfully with LuaLaTeX. XeLaTeX was not
installed in the development environment and has not been tested.

Generated review files currently exist at:

- `build/basic.pdf`
- `build/complex.pdf`
- `build/customization.pdf`

## Known limitations and engineering debt

1. Structured wrapping is still an MVP. A wrap boundary that falls directly
   inside a dense split/join group can produce less attractive routing. The
   complex acceptance example therefore uses a landscape page and
   `wrap=false` for readability.
2. Connectors currently use direct line segments rather than a complete
   obstacle-avoiding orthogonal router. Dense diagrams can have crossings or
   crowded condition labels.
3. Scaling guarantees width fit, but there is no automatic choice between
   portrait, landscape, wrapping, and font-size preservation. Height only
   produces a warning when it exceeds 80 percent of `\textheight`.
4. The ranking algorithm expects forward edges to be acyclic. Feedback must be
   expressed with `\loopflow`; this requirement is documented but not yet
   validated with a dedicated cycle diagnostic.
5. Error handling exists for duplicate, missing, and malformed identifiers,
   but there is no comprehensive negative-test suite.
6. There is not yet a `.dtx`/`.ins` package structure, generated manual,
   semantic versioning policy, license file, or CTAN metadata.
7. Visual snapshots are inspected manually; there is no regression/image test
   harness.

## Recommended next work

Before expanding features, ask the owner to review the three generated PDFs
and collect feedback on block proportions, typography, palette, connector
shapes, arrow routing, numbering, and annotation presentation.

Suggested technical order after visual feedback:

1. Improve split/join routing with orthogonal buses and explicit forward-axis
   awareness, including wrap transitions.
2. Make wrapping group-aware so a split, its parallel stage, and its join stay
   in the same row when feasible.
3. Add targeted TeX fixtures for every public option, invalid input, multiple
   diagrams per document, and combinations of annotations.
4. Test recent TeX Live versions on pdfLaTeX, LuaLaTeX, XeLaTeX, and Overleaf.
5. Add a small visual gallery comparing all built-in palettes.
6. Once the API stabilizes, convert to a documented package structure and add
   release/license metadata suitable for public distribution.

## Working-tree state

At handoff time the implementation is present but uncommitted. `README.md` is
modified and `.gitignore`, `HANDOFF.md`, `tikzffbd.sty`, and `examples/` are
new files. Do not discard these changes. Build outputs are ignored.

