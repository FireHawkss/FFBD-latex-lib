# 05 — Structural FFBD analysis

## Scope

Derive ordered sequence, parallel, and group regions from the forward graph;
attach feedback relationships; preserve generic fallback subgraphs.

## Out of scope

Do not change the `Spec`, invent missing AND/OR semantics, choose row/page
breaks, or assign positions.

## Dependencies

Accepted handoffs 02 and 04; part 01 contracts remain authoritative.

## Interfaces/contracts

`analyze(Spec) -> Regions` with ordered children, entry/exit IDs, member IDs,
keep-together eligibility, and ambiguity records. Use only forward flows for
the DAG; feedback attaches to its source/target regions. Preserve structures
as meaningful regions, not just future rectangles.

## Files/components affected

New `tikzffbd-analysis.lua` and structural fixtures/tests.

## Implementation steps

1. Build adjacency and reachability for forward flows.
2. Identify sequence chains and unambiguous split/join regions using graph
   structure such as dominance/post-dominance.
3. Nest or group recognized regions without losing member or arm order.
4. Record unresolved graph portions as general layered subgraphs with reasons.

## Tests and acceptance criteria

Recognize simple, multi-arm, and nested parallel regions; keep asymmetric arm
lengths correctly ordered; attach loop feedback; preserve boundary-port group
meaning. Ambiguous joins use fallback without a fabricated pairing. Results
are deterministic across declaration orders that are semantically equivalent
except for stated tie-breaks.

## Context required by the agent

Contracts, handoffs 02 and 04, and fixture IDs from handoff 01.

## Handoff result

`handoffs/05.md` describes region invariants, known ambiguous patterns, and
the fallback output consumed by part 06.
