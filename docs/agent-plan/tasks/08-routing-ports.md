# 08 — Orthogonal routing and ports

## Scope

Route forward, feedback, structure-crossing, and page-continuation flows around
measured obstacles. Assign ports and shared split/join channels.

## Out of scope

Do not alter semantic connections, move nodes directly, finalize annotation
positions, or generate TikZ paths as the primary data structure.

## Dependencies

Accepted handoff 07 and its dependencies.

## Interfaces/contracts

`route(Geometry, Spec, occupied_annotations) -> Routes | conflict`. Each path
is an ordered orthogonal point list with port IDs, shared-trunk ownership,
crossing and congestion costs. A conflict names the obstructed region/corridor
and can be passed back to candidate selection. Structure boundary crossings
must use declared member ports.

## Files/components affected

New `tikzffbd-routing.lua`; port, loop, wrap, structure, and congestion tests.

## Implementation steps

1. Construct a sparse rectilinear visibility graph from object bounds and
   clearances; avoid a dense Cartesian product over all obstacle coordinates.
2. Search with direction-aware costs for length, bends, proximity, crossings,
   and wrong-way travel, honoring row sign and minimum port stubs.
3. Allocate split buses, join trunks, feedback lanes, and structure ports.
4. Route related flows coherently, then perform bounded rip-up/re-route for
   congestion; return a conflict when no valid route exists.

## Tests and acceptance criteria

Every path is orthogonal and connected; no functional-block interior is
crossed; port stubs do not reverse; undeclared structure crossings diagnose;
loops and wraps keep readable direction; route quality metrics are emitted.
Dense fixtures finish within a documented bounded work budget.

## Context required by the agent

Contracts, handoff 07, prior geometry regression fixtures, and the distinction
between forward and feedback semantics.

## Handoff result

`handoffs/08.md` documents routing costs, work budget, conflict reasons, port
contracts, and examples of routed/failed fixtures.
