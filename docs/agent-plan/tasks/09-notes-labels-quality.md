# 09 — Annotation, label, and quality coordination

## Scope

Select annotation positions, place edge labels, evaluate complete diagrams,
and coordinate a bounded retry among row plans, placement, and routing.

## Out of scope

No rendering and no unbounded global optimizer. Do not silently decrease the
user's scale or violate hard constraints for a better score.

## Dependencies

Accepted handoffs 06, 07, and 08.

## Interfaces/contracts

`solve(Spec, Metrics, Frame) -> Scene | Diagnostic[]`. It evaluates hard
feasibility first, then the quality vector in `QUALITY.md`. It may call
`plan`, `place`, and `route` more than once within a stated deterministic
budget. `Scene` records selected positions, paths, quality, warnings, and pages.

## Files/components affected

New `tikzffbd-annotations.lua`, `tikzffbd-quality.lua`, and solver coordinator
(or cohesive equivalents); visual-quality fixtures and checks.

## Implementation steps

1. Evaluate all eight relative note positions, respecting explicit hard/soft
   choices and structure containment.
2. Route with chosen note obstacles; try alternative note/route combinations
   when the first pairing causes congestion.
3. Place flow labels close to their paths with clearance from objects and
   other paths; request a new candidate if none remains readable.
4. Compare complete candidates lexicographically and return the best valid one.
5. Emit specific conflicts and layout recommendations when hard feasibility
   fails or the search budget is exhausted.

## Tests and acceptance criteria

Hard note positions hold or diagnose; soft positions can move. Labels remain
associated with their flows and do not obscure blocks. A candidate with lower
crossing or spacing cost wins according to documented priorities. Fixtures
expose irregular local compression and excessive whitespace. Determinism and
budget behavior are tested at 10, 30, 50, and >50 blocks.

## Context required by the agent

Contracts, handoffs 06-08, `QUALITY.md`, and all hard/soft defaults.

## Handoff result

`handoffs/09.md` records solver budget, score components, unresolved visual
cases, and fully solved Scene fixtures for the renderer.
