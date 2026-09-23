# Current prototype: inspection map

This file describes the prototype before the LuaLaTeX successor is implemented.
It is a navigation aid, not a contract to preserve old geometry.

| Stage | Current location | Behavior |
| --- | --- | --- |
| Public options and styles | `tikzffbd.sty:125` and `tikzffbd.sty:421` | expl3 keys, themes, TikZ styles, automatic width fitting |
| Declarations | `tikzffbd.sty:169` | independent sequences and props; branches/joins become `@c` connector nodes; structures are one-level member lists |
| Measurement | `tikzffbd-layout.code.tex:94` | TikZ boxes measure blocks, annotations, and labels |
| Ranking and wrapping | `tikzffbd-layout.code.tex:133` | repeated edge relaxation, fixed snake map, declaration-order lanes |
| Structure and annotation geometry | `tikzffbd-layout.code.tex:397` | node registry, note search, group rectangles and boundary ports |
| Routing | `tikzffbd-layout.code.tex:572` | bounded obstacle tracks, join trunks, feedback corridors |
| Labels and render | `tikzffbd-layout.code.tex:1062` | labels after routes; final picture may auto-resize |
| Regression harness | `tests/check_layout.py` | geometric validity, with limited visual-quality checks |

The parser flattens FFBD regions before layout. Ranking and row placement are
settled before routing and labels; no complete-scene quality evaluation can
revise them. The router checks obstacles but searches limited tracks and does
not globally optimize crossings or congestion. Note and label placement happen
late, so valid output may still have irregular whitespace.

An explicit `\endrow` also enables automatic column-threshold wrapping with
`wrap=false`; invalid `max-columns` silently becomes five. These are local
defects, while the fixed staged pipeline is the systemic issue.

Keep as concepts: command vocabulary, themes, numbering, true TeX measurement,
declaration-order tie-breaks, explicit feedback, structure boundary ports, and
geometry traces. Replace the old placement/routing passes once the new gates
pass. `HANDOFF.md` is historical prototype context.
