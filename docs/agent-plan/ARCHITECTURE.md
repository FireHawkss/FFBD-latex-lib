# Finalized architectural decisions

## Product boundary

Users declare FFBD meaning, preferences, and high-level constraints using the
existing command vocabulary where its meaning is clear. The library determines
coordinates, bends, ports, and route tracks. Backward compatibility with the
prototype's internals and pdfLaTeX is not a requirement.

LuaLaTeX is required. Lua runs during normal `.tex` compilation. TeX owns and
measures arbitrary LaTeX text; Lua owns semantics, structural analysis,
constraints, layout, routing, and quality evaluation; TikZ renders a solved
scene. The package must work locally and on Overleaf with no external layout
program, preprocessing, shell escape, or user-managed intermediate file.

## Reading order and size

Wrapped rows are **serpentine**: rightward first row, leftward second row, then
alternating. `direction=down` uses the analogous alternating vertical bands.
Direction is an input to placement, port selection, and routing. The planner
chooses row breaks from FFBD structure and quality, not a fixed rank count alone.
An explicit `\endrow` is an exact break by default; a soft form may be added.

`max-columns=5` is a hard limit by default. `max-columns-strength=soft` expresses
the same value as a preference. The constraint system should generalize this
strength pattern. When hard constraints conflict, emit a useful diagnostic.

There is no block-count ceiling. Target readiness over representative fixtures:
under 10 blocks effectively 100%; 10-30 about 95%; 30-50 about 85%; larger
diagrams supported with graceful quality/runtime degradation and recommendations.
These are empirical visual-review targets, not hard-coded block thresholds.

Multipage is an FFBD-level opt-in. Break at semantic region boundaries where
possible. A region too large for a page may split with labeled continuation
markers. Each page is a separate TikZ picture; the first row on each page starts
in the primary direction. With multipage off, recommend landscape, multipage,
soft-column adjustment, or explicit scale when appropriate.

`scale` is FFBD-level, explicit, and uniform: text, blocks, paths, notes, line
widths, and spacing scale together. Do not infer or silently adjust it to fit.
Render an unscaled solved picture in a box and apply the user's scale to that
complete box, separately but consistently on every page.

## Pipeline

```text
commands -> typed Spec -> semantic validation and regions -> TeX Metrics
         -> constraints -> bounded row/page candidates -> node ordering
         -> coordinate assignment <-> route/annotation/label evaluation
         -> scored Scene -> TikZ
```

The layout/route feedback is bounded and deterministic. A route conflict may
cause a new structural candidate or global gutter allocation. Rendering does
not choose geometry. The solution may use heuristics; it need not solve a global
mathematical optimum.

Preserve function, terminal, AND/OR split and join, forward flow, feedback,
annotation, and structural-group meanings. Identify split/join regions where
unambiguous. An ambiguous graph stays representable and uses a general layered
fallback; the engine must not invent semantic relationships.

## Hard rules and visual priorities

Hard: correct FFBD relationships, explicit hard constraints, readable text,
nonoverlapping functional blocks, flows outside functional-block interiors,
valid group ports/containment, and page bounds when multipage is enabled.
Strong: minimize avoidable crossings and confusing backward routes; preserve
branch and group clarity. Weaker: regular global spacing, alignment, short
routes, few bends, balanced whitespace, and nearby readable labels. Use a
lexicographic quality vector after hard feasibility. Local gap changes require
a higher-priority reason and should be penalized for irregularity.

Annotations are flexible objects with eight positions: top-left, top-center,
top-right, left, right, bottom-left, bottom-center, bottom-right. Automatic
placement evaluates them with routing. An explicitly selected position is hard
unless the user marks it soft. Flows preferably avoid annotations; unavoidable
annotation/flow conflicts trigger candidate reconsideration before failure.

## Legacy ideas to retain

Keep the approachable command names, numbering, themes, actual TeX measurement,
deterministic declaration-order tie-breaking, explicit feedback flows, structure
boundary ports, geometry traces, and collision regression fixtures. Replace the
rank-to-snake fixed-lane placement, late uncoordinated labels, bounded track
router, and automatic `scale-to-fit` behavior.
