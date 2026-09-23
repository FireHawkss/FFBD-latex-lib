# 07 — Crossing reduction and coordinate assignment

## Scope

Order nodes within layers and assign measured rectangles with structurally
regular columns, branch lanes, groups, and row gaps.

## Out of scope

No final pathfinding, label placement, pagination policy, or rendering. Do not
shrink arbitrary local gaps merely to meet width.

## Dependencies

Accepted handoff 06 and its dependencies.

## Interfaces/contracts

`place(Plan, Spec, Metrics, Constraint[]) -> Geometry | conflict`.
`Geometry` includes node and provisional group rectangles, row axes,
reserved route channels, candidate port sides, and spacing statistics. It
uses integer `sp` and preserves each row's direction sign.

## Files/components affected

New `tikzffbd-placement.lua`; crossing/alignment fixtures and geometry tests.

## Implementation steps

1. Layer each planned row or region; represent long edges across intermediate
   layers without changing the semantic `Spec`.
2. Use deterministic median/barycenter sweeps and limited local swaps to reduce
   crossings while respecting branch order and hard constraints.
3. Place rectangles using measured sizes and shared spacing variables; align
   related blocks and equivalent branch lanes.
4. Reserve global gutters for joins, feedback, annotations, and wraps.
5. Return a conflict signal when a plan cannot meet hard dimensions.

## Tests and acceptance criteria

No functional-block overlap; no hard plan violation; simple chains straight;
related blocks aligned; branch spacing consistent; serpentine rows have correct
port-side candidates; repeated runs match. Compare crossing counts and spacing
variance on fixtures before accepting a change.

## Context required by the agent

Contracts, handoff 06, structural region semantics from 05, and `QUALITY.md`.

## Handoff result

`handoffs/07.md` identifies placement API, spacing variables and invariants,
quality traces, and any geometry conflicts the planner must handle.
