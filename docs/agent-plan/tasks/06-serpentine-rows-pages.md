# 06 — Serpentine row and semantic page planning

## Scope

Generate a bounded set of row and page plans from regions, measurements,
constraints, and available frame size. Wrapped rows alternate direction.

## Out of scope

Do not finalize node coordinates, route individual flows, render pages, or
silently adjust scale. Avoid a fixed rank-count-only wrap rule.

## Dependencies

Accepted handoffs 03, 04, and 05.

## Interfaces/contracts

`plan(Regions, Metrics, Constraint[], Frame) -> Plan[] | Diagnostic[]`.
Each `Plan` explicitly lists page, row, row direction, ordered regions/nodes,
hard and preferred breaks, and linked continuation markers. Row 1 goes in the
primary direction; every wrap reverses it. Each new page resets to the primary
direction and uses clear continuation markers.

## Files/components affected

New `tikzffbd-planner.lua`; planner fixtures, trace output, and tests.

## Implementation steps

1. Compute minimum region footprints from actual `Metrics`, including a
   conservative annotation and routing allowance.
2. Generate feasible structural row-break candidates respecting hard columns,
   exact `\endrow`, and keep-together rules.
3. Rank cuts by branch/join integrity, flow clarity, and consistent row use.
4. If multipage is enabled, choose semantic page cuts; split an oversized
   region only with paired continuation objects.
5. Bound candidate count and record why candidates were pruned.

## Tests and acceptance criteria

Verify alternating right/left rows and analogous downward bands; exact and
soft row breaks; hard/soft max columns; branches kept together when feasible;
semantic multipage cuts; an oversized region continued clearly; graceful
planning for >50 blocks. When multipage is off, over-wide cases produce
recommendations without implicit scaling.

## Context required by the agent

Contracts and handoffs 03-05. User intent is serpentine wrapping, including
port direction reversal on each wrapped row.

## Handoff result

`handoffs/06.md` records the candidate budget, plan ranking, continuation
contract, and fixtures for downstream placement.
