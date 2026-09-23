# 11 — Integration and release gates

## Scope

Integrate all phases into the public package, migrate examples and docs, run
functional and visual regressions, and verify practical compilation locally
and on Overleaf.

## Out of scope

Do not reopen accepted architectural choices for convenience. A contract
change needs an explicit recorded reason and affected task-card updates.

## Dependencies

Accepted handoffs 01-10.

## Interfaces/contracts

End users load `tikzffbd`, select LuaLaTeX, write `ffbd` commands, and compile
the `.tex` document normally. The runtime returns either a rendered `Scene` or
specific diagnostics. No shell escape, external graph engine, preprocessing,
or manually generated data file is required.

## Files/components affected

`tikzffbd.sty`, all new Lua modules, `tests/`, `examples/`, `README.md`, and
distribution instructions. Retire obsolete layout code only after equivalent
features pass the new gates.

## Implementation steps

1. Connect bridge, model, constraints, analysis, planner, placement, router,
   solver, and renderer; remove staging adapters.
2. Migrate all current examples and add new large/multipage/scaled examples.
3. Run semantic, constraint, geometry, deterministic, and diagnostic suites.
4. Render and review the fixture catalogue; record visual ratings and fix
   concrete deficiencies within the accepted contracts.
5. Benchmark 10, 30, 50, and >50 blocks, including cold/repeat runs and budget
   exhaustion behavior.
6. Verify a project with only `.tex`, `.sty`, and colocated `.lua` files on
   Overleaf with LuaLaTeX selected. Update installation and option docs.

## Tests and acceptance criteria

All hard invariants and documented options pass; representative readiness is
measured against the <10, 10-30, and 30-50 targets; >50 remains supported with
graceful diagnostics/recommendations; deterministic results and practical
compilation times are recorded; Overleaf needs only normal compilation.
Known limitations are explicit and reproducible.

## Context required by the agent

`ARCHITECTURE.md`, `CONTRACTS.md`, `QUALITY.md`, and handoffs 01-10. No full
conversation or prototype development history is required.

## Handoff result

`handoffs/11.md` is the release report: changed files, test and visual
evidence, timing/memory measurements, Overleaf result, known limits, and
recommended version/release notes. Mark the roadmap complete only if all
acceptance criteria hold.
