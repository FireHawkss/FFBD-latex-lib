# 01 — Contracts and fixture foundation

## Scope

Turn `../CONTRACTS.md` and `../QUALITY.md` into executable schema checks,
fixture metadata, and a test runner skeleton. Capture the prototype examples as
semantic reference cases while allowing their geometry to change.

## Out of scope

Do not implement the Lua solver, alter public commands, or freeze prototype
coordinates as expected output.

## Dependencies

None. This is the foundation for all other parts.

## Interfaces/contracts

Own version 1 of `Spec`, `Metrics`, `Constraint`, `Regions`, `Plan`, `Geometry`,
`Routes`, `Scene`, and `Diagnostic`. Define exact ID namespace rules and
serialization for test traces. Later parts may extend fields additively.

## Files/components affected

`docs/agent-plan/CONTRACTS.md`, `QUALITY.md`, test fixture manifests under
`tests/`, and a small test runner. Do not change the production layout engine.

## Implementation steps

1. Define validators for type, required fields, integer-sp dimensions, stable
   IDs, finite geometry, and per-environment isolation.
2. Inventory and name the examples plus new cases listed in `QUALITY.md`.
3. Specify semantic expected outputs and visual review prompts per fixture.
4. Provide mock valid and invalid `Scene` objects for renderer and checker work.

## Tests and acceptance criteria

Schema tests reject malformed objects and accept the mock Scenes. Fixture
metadata covers simple, dense, wrapped, structured, annotated, multipage,
invalid-constraint, and >50-block cases. A fresh agent can run the checks from
one documented command. Geometry is not locked to the old implementation.

## Context required by the agent

`ARCHITECTURE.md`, `CONTRACTS.md`, `QUALITY.md`, and current example files.
The old `HANDOFF.md` is only historical context.

## Handoff result

`handoffs/01.md` records validator APIs, fixture IDs, the test command, and
accepted schema decisions. Mark part 01 complete in `STATUS.md`.
