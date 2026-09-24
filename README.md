# tikzffbd

`tikzffbd` turns FFBD commands into measured, routed TikZ diagrams during ordinary LuaLaTeX compilation. Version 0.5.0 is an integration preview; see [release status](docs/agent-plan/handoffs/11.md) for reproducible cases that still block a full release.

## Install and compile

Copy `tikzffbd.sty`, `tikzffbd-bridge.code.tex`, `tikzffbd-renderer.code.tex`, `tikzffbd-layout.code.tex`, and all `tikzffbd-*.lua` files beside your `.tex` document. Select **LuaLaTeX** locally or in Overleaf, then compile normally. No shell escape, graph executable, preprocessing, or generated data file is needed. The layout TeX file currently supplies shared measurement and command helpers.

```latex
\documentclass{article}
\usepackage{tikzffbd}
\begin{document}
\begin{ffbd}[theme=ocean,max-columns=5]
  \start{entry}{Request received}
  \function{work}{Process request}
  \finish{exit}{Request complete}
  \flow{entry}{work}
  \flow{work}{exit}
\end{ffbd}
\end{document}
```

Functions are numbered automatically. Use `\function[number=2.3]{id}{Text}` to override a number or `number=none` to hide it. IDs begin with a letter and may contain letters, digits, periods, underscores, and hyphens.

## Commands

Inside `ffbd`, the short forms `\start`, `\finish`, `\function`, `\flow`, `\branch`, `\join`, `\loopflow`, `\endrow`, `\structure`, `\precondition`, `\timing`, `\note`, and `\annotation` are available. The corresponding `\ffbd...` forms also work.

```latex
\flow[condition={Ready}]{first}{second}
\branch[or]{decision}{yes={Accepted},no={Rejected}}
\join[or]{yes,no}{next}
\loopflow[condition={Retry},side=above]{later}{earlier}
\endrow                 % exact row break after the preceding flow
\endrow[soft]           % row preference
\annotation[type=Risk,position=top-left,position-strength=soft]
  {second}{Check external service}
```

An explicit annotation position is hard unless `position-strength=soft` is set. The eight positions are `top-left`, `top-center`, `top-right`, `left`, `right`, `bottom-left`, `bottom-center`, and `bottom-right`. `\annotation[Risk]{id}{body}` remains valid. `\precondition`, `\timing`, and `\note` take an owner ID and body.

Structures group existing functions. Declare boundary members with `inputs` and `outputs`:

```latex
\structure[type={While loop},info={until valid},style=shaded,
  inputs={load},outputs={check}]{cycle}{load,check}
```

## Options

| Option | Values and meaning |
| --- | --- |
| `theme` | `ocean` (default), `slate`, `forest`, `plum`, `monochrome`, or a theme declared with `\ffbdDeclareTheme` |
| `direction` | `right` (default) or `down`; wrapped bands alternate direction |
| `max-columns` | Positive integer, default `5`; hard by default |
| `max-columns-strength` | `hard` (default) or `soft` |
| `multipage` | `false` (default) or `true`; each solved page is a separate TikZ picture |
| `scale` | Positive number, default `1`; uniformly scales the complete picture on each page |
| `annotations` | Preferred side: `above`, `below`, `left`, or `right` |
| `fill`, `font`, `line-weight` | `true/false`; `sans/serif`; `thin/heavy` |

The solver does not shrink a diagram automatically. When a hard layout cannot be met, compilation reports a diagnostic code and message. `scale-to-fit`, `wrap`, `block-width`, `column-sep`, `row-sep`, `port-stub`, and `layout-debug` remain accepted by the compatibility input layer, but do not currently control the solved layout; avoid relying on them in new documents.

The `examples/` directory contains basic, customized, structural, large, scaled, and multipage documents. The release handoff records which currently compile and which need further solver work. For a local smoke test:

```sh
lualatex -no-shell-escape -interaction=nonstopmode -halt-on-error examples/basic.tex
```
