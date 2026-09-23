# 02 — Semantic FFBD model

## Scope

Implement the Lua builder and sealed `Spec` for functions, terminals, typed
AND/OR splits and joins, forward and feedback flows, structures, and
annotations. Validate semantic declarations and retain user order.

## Out of scope

No TeX measurement, rank assignment, coordinates, routing, or rendering. Do not
infer split/join pairing here; that belongs to part 05.

## Dependencies

Accepted handoff 01.

## Interfaces/contracts

`model.new()`, typed `model:add_*()` operations, and `model:seal() -> Spec |
Diagnostic[]`, conforming to `CONTRACTS.md`. Text values are references to
TeX-held tokens. Separate forward and feedback flows. All IDs and declaration
indices are deterministic.

## Files/components affected

New colocated `tikzffbd-model.lua` (or documented equivalent) and Lua unit
tests. Existing `.sty` may remain untouched until part 03.

## Implementation steps

1. Create typed records and ID generation, including internal connector IDs.
2. Preserve branch arm order, conditional labels, join input order, and group
   member/port lists.
3. Validate IDs, endpoints, duplicate declarations, member uniqueness, port
   membership, connector kinds, and forbidden forward cycles.
4. Seal the model against mutation and expose stable inspection/traces.

## Tests and acceptance criteria

Test 2-, 3-, and 4-arm AND/OR cases, nested-looking branches, joins, loops,
structures, annotations, declaration-order stability, duplicate/unknown IDs,
and forward-cycle diagnostics. Repeat-run serialized Specs must match.

## Context required by the agent

Contract definitions, handoff 01, and command meanings in `tikzffbd.sty`.

## Handoff result

`handoffs/02.md` gives the exact builder API, generated ID convention, tests,
and any semantic ambiguities deliberately left for part 05.
