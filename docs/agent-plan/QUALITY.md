# Quality and release evidence

## Automated invariants

For every fixture, check: valid FFBD graph and connector meaning; stable output
for repeated runs; hard constraint satisfaction; no functional-block overlap;
no flow through functional-block interiors; correct structure ports and
containment; orthogonal routes with no immediate port reversal; no unreadable
or overlapping note/label text; page bounds when multipage is enabled; and
uniform explicit scale. Include both rightward and downward primary directions.

For feasible diagrams, record a lexicographic quality vector:

```text
(semantic_or_hard_violations,
 severe_crossings_and_wrong_way_routes,
 ordinary_crossings_and_congestion,
 grouping_and_alignment_deviation,
 spacing_variance_and_whitespace_imbalance,
 bends_and_edge_length,
 note_and_label_displacement)
```

The first element must be zero. Later elements are compared only after earlier
ones; tiny compactness gains cannot excuse a hard conflict or an unreadable
route. The exact normalization and thresholds belong to part 01 fixtures and
part 09 calibration, with changes documented in handoffs.

## Visual fixture catalogue

Start from `examples/basic.tex`, `complex.tex`, `structures.tex`,
`customization.tex`, and `1st-real-world-use.tex`. Add fixtures for: an 8-block
chain; 15- and 30-block branches with unequal arm lengths; 30-50 blocks with
several joins and feedback loops; dense conditions and long annotations; a
structure across a serpentine wrap; hard/soft column limits; hard/soft row
breaks; eight annotation positions; explicit scale; and >50 blocks with and
without multipage. Fixtures should include adversarial cases where a geometric
pass produces visibly irregular gaps or long displaced labels.

For each fixture, store semantic expectations, automated geometry checks, a
rendered PDF or image reference, and a short human visual rating. The rating
asks whether flow direction, branch grouping, spacing rhythm, crossings,
labels, notes, and page continuations are understandable without manual edits.
Track the under-10 / 10-30 / 30-50 readiness proportions as measured results;
do not assert them from algorithm design alone.

Part 01's inventory is `tests/fixtures/manifest.json`. Each entry has a stable
fixture ID, source path or `null` while a successor `.tex` case is pending,
semantic expectations, one visual-review prompt, a geometry check profile,
and `visual_review` fields for a rendered reference, rating, and notes. A
`null` visual result means **not reviewed**; the legacy PDF is not an expected
geometry reference. `standard` names the invariant checks listed above.
Later implementation parts add the planned `.tex` sources and populate the
reference/rating fields with measured results. Readiness rates and quality
thresholds remain unmeasured until those runs; part 09 calibrates score
normalization and thresholds from visual evidence.

## Performance and environment

Benchmark cold and repeat LuaLaTeX compilation on representative 10, 30, 50,
and larger-block fixtures. Record engine/TeX Live version, elapsed time, memory,
candidate count, router work, and whether the search budget was reached. Use a
fixed deterministic budget and provide a valid best solution or useful
diagnostic. Verify an uploaded project on Overleaf with the `.tex`, `.sty`, and
colocated `.lua` files and LuaLaTeX selected. No additional user command is
allowed.

Development tests may run Python, `texlua`, image comparison, and ordinary
LaTeX compilers. This restriction applies to the user's diagram workflow, not
to the project's test workflow.
