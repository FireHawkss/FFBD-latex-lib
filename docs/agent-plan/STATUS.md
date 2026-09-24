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
| 08 Routing and ports | complete | 07 | [08.md](handoffs/08.md) |
| 09 Annotations, labels, quality | blocked | 06, 07, 08 | [09.md](handoffs/09.md) |
| 10 TikZ renderer | complete | 01, 03; final integration 09 | [10.md](handoffs/10.md) |
| 11 Integration and release gates | blocked | 01–10 | [11.md](handoffs/11.md) |

The production drawing pass now consumes solved Scenes. Part 09 visual acceptance remains blocked, and part 11 is blocked by three failing existing examples, incomplete visual readiness evidence, and an unverified Overleaf upload. See the reproducible diagnostics and release measurements in `handoffs/11.md`.
