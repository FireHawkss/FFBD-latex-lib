# 04 — Constraints and diagnostics

## Scope

Normalize layout options into `Constraint` records, enforce hard feasibility,
score soft preferences, and produce useful conflict diagnostics.

## Out of scope

Do not choose rows, coordinates, routes, or annotation positions. Do not add
independent ad-hoc exception rules for each option.

## Dependencies

Accepted handoffs 01 and 02. Coordinate input option integration with part 03.

## Interfaces/contracts

`constraints.normalize(Spec, Frame) -> Constraint[] | Diagnostic[]` and
`constraints.check(candidate) -> violations`, as in `CONTRACTS.md`. Each
diagnostic names sources and affected IDs. Candidate checks support partial
plans as well as completed Scenes.

## Files/components affected

New `tikzffbd-constraints.lua` and diagnostic module or equivalent; constraint
unit tests; documentation of supported strengths.

## Implementation steps

1. Define one strength and precedence mechanism for max columns, row breaks,
   group keeping, annotation positions, page fit, and future options.
2. Make default max columns and plain `\endrow` hard; soft variants contribute
   strong preference costs.
3. Check invalid values and conflicts before search when possible.
4. Define stable diagnostic codes with concrete suggested adjustments.

## Tests and acceptance criteria

Hard five-column limit is never exceeded; a soft five-column preference may
be exceeded with a recorded cost. Conflicting hard keep-together, page, row,
or annotation constraints identify both causes. No invalid value silently
changes to a default. Same inputs yield identical diagnostics.

## Context required by the agent

Contracts, handoffs 01-02, and the accepted public-option syntax from part 03
when available.

## Handoff result

`handoffs/04.md` records the evaluator API, diagnostic codes, and examples of
hard conflict and soft override.
