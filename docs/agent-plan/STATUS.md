# Roadmap status

Status values: `ready`, `waiting`, `in progress`, `blocked`, `complete`.
The coordinator changes a task to `ready` after its dependencies have accepted
handoffs. A task is `complete` only with its acceptance evidence in `handoffs/NN.md`.

| Part | State | Depends on | Handoff |
| --- | --- | --- | --- |
| 01 Contracts and fixtures | complete | — | [01.md](handoffs/01.md) |
| 02 Semantic model | complete | 01 | [02.md](handoffs/02.md) |
| 03 TeX bridge and measurement | complete | 01, 02 | [03.md](handoffs/03.md) |
| 04 Constraints and diagnostics | complete | 01, 02 | [04.md](handoffs/04.md) |
| 05 Structural analysis | complete | 02, 04 | [05.md](handoffs/05.md) |
| 06 Serpentine rows and pages | complete | 03, 04, 05 | [06.md](handoffs/06.md) |
| 07 Ordering and coordinates | complete | 06 | [07.md](handoffs/07.md) |
| 08 Routing and ports | ready | 07 | pending |
| 09 Annotations, labels, quality | waiting | 06, 07, 08 | pending |
| 10 TikZ renderer | ready | 01, 03; final integration 09 | pending |
| 11 Integration and release gates | waiting | 01–10 | pending |

The production drawing pass is still the legacy prototype. Parts 01–07 have
established contracts, a semantic Lua builder, the TeX input/measurement
bridge, constraint evaluation, structural analysis, row/page planning, and
measured placement. Parts 08 and 10 are ready for implementation.
