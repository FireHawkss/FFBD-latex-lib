# Shared implementation contracts, version 1

Part 01 owns the first executable definitions of these contracts. Later parts
may refine fields without changing their meaning. A breaking change requires an
updated contract, affected task cards, and a recorded handoff before dependent
work continues.

## Executable version 1 trace contract

`tests/contract_schema.py` is the development-time structural validator for
the named phase objects below. Its public API is `validate(kind, value) ->
list[str]`, `validate_trace(trace) -> list[str]`, and `canonical_trace(trace) ->
str`. An empty error list means the object satisfies the version 1 structural
schema. It does **not** certify graph semantics or visual feasibility; later
phase tests and the checks in `QUALITY.md` cover those. Additive fields are
accepted, so later parts may record more detail without invalidating traces.

For test traces, serialize one environment at a time as UTF-8 JSON:

```json
{"contract_version":1,"environment_id":"fixture-1","objects":{"Scene":{}}}
```

The `objects` map uses the exact contract names `Spec`, `Metrics`, `Frame`,
`Constraint`, `Diagnostic`, `Regions`, `Plan`, `Geometry`, `Routes`, and `Scene`.
Only present phases are serialized; an incomplete trace may contain just one
phase. Each top-level phase object except standalone `Constraint` and
`Diagnostic` carries the same nonempty `environment_id` as the envelope.
This prevents accidental mixing of sealed environments. `canonical_trace`
rejects invalid input and emits one line of JSON with sorted keys, compact
separators, UTF-8 characters intact, and a final newline. Arrays retain
semantic/declaration order. JSON `NaN` and infinities are forbidden.

User-owned function/terminal node, structure, and annotation IDs use
`[A-Za-z][A-Za-z0-9._-]*`; `@` is reserved. Generated IDs use
`@<namespace>/<segment>[/<segment>...]`, with nonempty segments from
`[A-Za-z0-9._-]+`. Version 1 namespaces are `flow`, `branch`, `join`, `port`,
`continuation`, `region`, `text`, and `constraint`. A generated ID is assigned
from deterministic command expansion order, not coordinates or page numbers;
it remains stable through replanning. `index` is the source command's positive
declaration index. Different collections, and multiple flows expanded from one
branch/join command, may share it. Within nodes, structures, and annotations,
declaration indices are unique. The generated ID disambiguates repeated
indices. The environment ID scopes all IDs, so the same user ID can appear in
separate environments. `text_ref` is an internal `@text/...` ID; no raw TeX
tokens enter JSON traces.
Split and join nodes are generated connectors with `@branch/...` and
`@join/...` IDs respectively. The same connector ID appears in its branch or
join record and may key a node rectangle. Flow IDs use `@flow/...`.

All serialized `*_sp` coordinates and dimensions are JSON integers (Python
`bool` is rejected as an integer). Dimensions are positive where the schema
requires visible width/height; coordinate origins may be negative. Scales and
quality costs are finite JSON numbers. `Scene.quality.vector` has seven
nonnegative components in the order in `QUALITY.md`, with component zero equal
to zero for a valid Scene. It also records `search_budget`,
`candidates_evaluated`, and `budget_exhausted`. `PageScene` uses ID-keyed
`node_rects`, `structure_rects`, and `flow_paths`, plus ordered arrays of
`annotations`, `edge_labels`, and `continuation_markers`. A rectangle is
`{x_sp,y_sp,width_sp,height_sp}`. A path has `source_port_id`,
`target_port_id`, and at least two ordered, nonzero orthogonal point segments.
Annotations record `id`, `owner_id`, `position`, `rect`, `type_ref`, and
`body_ref`; labels record `flow_id`, `text_ref`, and `rect`. Continuation markers
record `id`, `counterpart_id`, `semantic_flow_id`, `rect`, and `text_ref`; the
counterpart must be reciprocal, on another page, and name the same flow.
These details make renderer mocks independently consumable. The tests include
single-page and multipage examples under `tests/fixtures/scenes/`.

## Units, identity, and ownership

- All layout dimensions and coordinates crossing a phase boundary are finite
  integer TeX scaled points (`sp`). Lua may use floating-point calculations
  internally, then round deterministically at the boundary. Pixel and `pt`
  values are renderer-only conversions.
- Every semantic object has a stable string ID and declaration index. Internal
  IDs for connectors, continuation markers, and ports use separate namespaces.
  Repeated compilation of the same document must produce the same IDs and
  geometry. IDs shown in diagnostics refer to user IDs where possible.
- TeX owns raw label tokens. Lua receives `text_ref` IDs, measured dimensions,
  and plain metadata; it never evaluates or rewrites arbitrary LaTeX content.
  The renderer retrieves the original tokens by `text_ref`.
- Each FFBD environment is isolated. A sealed `Spec`, `Metrics`, and `Scene`
  from one environment cannot leak into another.

## Spec

`Spec` is the validated, immutable semantic input. Fields may be implemented as
Lua tables with named keys:

```text
Spec {
  nodes[]: {id, index, kind=function|start|finish|split|join,
            logic=and|or (split/join only), text_ref?, number?}
  flows[]: {id, index, source, target, kind=forward|feedback,
            condition_ref?, preferred_feedback_side?}
  branches[]: {connector_id, source_id, arm_flow_ids_in_user_order[]}
  joins[]: {connector_id, arm_flow_ids_in_user_order[], target_id}
  structures[]: {id, index, member_ids[], type_ref?, info_ref?, style,
                 input_member_ids[], output_member_ids[]}
  annotations[]: {id, index, owner_id, type_ref, body_ref,
                  preferred_position?, position_strength?}
  constraints[]: Constraint
  options: {direction, theme, scale, multipage, ...}
}
```

The branch and join records preserve command intent. They do not imply that a
particular split matches a particular join. Forward flows form the DAG used for
layering; feedback flows are retained separately. A structure refers to semantic
members rather than an early drawing rectangle. The model records source command
information for diagnostics.

## Metrics and Frame

```text
Metrics { by_text_ref: {width_sp, height_sp, depth_sp?},
          by_node_id: {width_sp, height_sp},
          by_annotation_id: {width_sp, height_sp},
          by_structure_id: {header_width_sp, header_height_sp, info_width_sp?},
          style_clearances: {...} }
Frame {page_width_sp, page_height_sp, content_width_sp,
       content_height_sp, direction, scale}
```

Metrics reflect the final TeX styles and actual label tokens. `scale` is a
positive finite user value, default 1. Geometry is computed unscaled; usable
physical content dimensions are divided by `scale` for feasibility. No phase
may silently change it.

## Constraints and diagnostics

```text
Constraint {id, kind, target_ids[], value, strength=hard|strong|weak,
            source={command, option?, declaration_index}}
Diagnostic {code, severity=error|warning|info, object_ids[],
            constraint_ids[], message, suggested_actions[]}
```

Hard constraints are feasibility tests. Strong and weak preferences contribute
to the quality vector. `max-columns` defaults to hard. An ordinary `\endrow`
is hard. Explicit annotation position defaults to hard; global annotation side
is a preference. Invalid values fail at input validation. A hard conflict names
the competing constraints and region rather than choosing one silently.

Minimum hard geometry: function/terminal/connector rectangles do not overlap;
forward or feedback paths do not enter functional-block interiors; text boxes
remain readable and do not overlap functional blocks; structure membership and
declared boundary ports are honored; all semantic flows remain connected.
Annotation and edge-label clearance is a high-priority candidate objective;
if no valid readable placement is found, emit a diagnostic. Do not silently
place text over another object.

## Regions, plans, geometry, and routes

```text
Regions {root, regions_by_id, fallback_subgraphs[], ambiguities[]}
Region {id, kind=sequence|parallel|group|generic, entry_id?, exit_id?,
        ordered_children[], member_ids[], can_keep_together}
Plan {pages[]: {rows[]: {index, direction_sign, ordered_region_ids[],
                         ordered_node_ids[], forced_break_ids[]},
                  continuation_ids[]}, estimated_costs}
Geometry {node_rects_by_id, group_rects_by_id, row_axes[],
          reserved_channels[], provisional_ports[], spacing_stats}
Routes {paths_by_flow_id, ports_by_id, shared_trunks[], crossings[],
        congestion[], costs, conflicts[]}
```

`direction_sign` alternates at every wrap. Rightward primary direction starts
with `+1`; downward primary direction uses the analogous sign convention. A
new page starts in its primary direction. Plans must preserve flow semantics and
hard row/page constraints. Geometry rectangles are axis-aligned and include
visible stroke where relevant. An obstacle grid derives from final rectangles
plus clearance; it is not encoded as ad-hoc route commands in `Spec`.

The phase entry points are:

```text
model.new(), model:add_*(), model:seal() -> Spec | Diagnostic[]
constraints.normalize(Spec, Frame) -> Constraint[] | Diagnostic[]
analyze(Spec) -> Regions
plan(Regions, Metrics, Constraint[], Frame) -> Plan[] | Diagnostic[]
place(Plan, Spec, Metrics, Constraint[]) -> Geometry | conflict
route(Geometry, Spec, occupied_annotations) -> Routes | conflict
solve(Spec, Metrics, Frame) -> Scene | Diagnostic[]
render(Scene, text_registry, styles) -> TeX material
```

Each phase must have deterministic fixture tests before integration. The
solver's search budget is explicit and reported when exhausted. A valid best
candidate may be returned with a quality warning; an invalid candidate cannot.

## Scene and rendering

```text
Scene {pages[]: PageScene, quality, diagnostics, scale}
PageScene {node_rects, structure_rects, annotations, flow_paths,
           edge_labels, continuation_markers, bounding_rect}
```

Every flow path contains its ordered orthogonal points and port IDs. Every
annotation records one of the eight allowed positions. A continuation marker
has a stable semantic link to its counterpart on another page. TikZ consumes
these placements exactly. It may select colors, fonts, strokes, and draw order,
but cannot move objects or alter routes. A complete page picture is uniformly
scaled by the user-selected value after drawing.

## Public option evolution

Maintain current command forms. Add FFBD-level `scale=<positive number>` and
`multipage=true|false`. Add `max-columns-strength=hard|soft` (`hard` default);
the input layer maps `soft` to a strong preference. Allow `\endrow[soft]`, with
the existing no-option form hard. Add annotation `position=<eight choices>`
and `position-strength=hard|soft` where its command accepts options. Existing
`annotations=above|below|left|right` remains a global preference. Part 03 may
choose a backward-compatible optional-key syntax for `\annotation` and record
it in its handoff; it must not change the three mandatory arguments.

Future high-level controls, such as keep-together groups, use the same
`Constraint` strength mechanism. Avoid exposing coordinates or bend points.
