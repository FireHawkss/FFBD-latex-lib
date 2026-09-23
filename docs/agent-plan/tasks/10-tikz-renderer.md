# 10 — TikZ renderer and uniform explicit scale

## Scope

Render a `Scene` through TikZ, retrieve TeX-held labels, apply themes, and
uniformly scale each complete page picture by the explicit FFBD `scale` value.

## Out of scope

No geometry, port, route, row, or page-break decisions. Do not restore automatic
`scale-to-fit` behavior.

## Dependencies

Accepted handoffs 01 and 03 for contract and text registry. The module may be
built against mock Scenes before part 09; final integration depends on 09.

## Interfaces/contracts

`render(Scene, text_registry, styles) -> TeX material`. Coordinates convert
from integer `sp` only at rendering. One `PageScene` becomes one TeX-placeable
TikZ picture. Draw order follows the Scene and preserves annotation/flow
legibility. A page's final box is scaled as a whole.

## Files/components affected

Rendering portions of `tikzffbd.sty`, optional small Lua emission module,
renderer tests and mock Scene fixtures. Remove the old automatic resize path
only when the new renderer owns output.

## Implementation steps

1. Draw nodes, group borders, ports/continuations, routed paths, labels, and
   notes from supplied geometry without remeasuring or moving them.
2. Reuse theme/numbering concepts and fetch exact TeX label tokens by ID.
3. Box each page picture and apply explicit uniform scale to the full box.
4. Hand separate pictures to normal TeX page flow; emit page-continuation text.

## Tests and acceptance criteria

Mock and solved Scene coordinates match geometry traces. Scale 0.9 changes
text, boxes, lines, annotations, and spacing by the same factor. Multipage
pages render in order with linked continuations. No width-dependent shrinking
occurs. Local and Overleaf compilation use only LuaLaTeX.

## Context required by the agent

Contracts, handoffs 01 and 03, current themes/styles, and explicit-scale rule.

## Handoff result

`handoffs/10.md` describes renderer API, text lookup, draw order, scale tests,
and the mock/solved Scene fixtures it accepts.
