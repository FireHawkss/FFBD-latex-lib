# Roadmap status

Status values: `ready`, `waiting`, `in progress`, `blocked`, `complete`.
The coordinator changes a task to `ready` after its dependencies have accepted
handoffs. A task is `complete` only with its acceptance evidence in `handoffs/NN.md`.

| Part | State | Depends on | Handoff |
| --- | --- | --- | --- |
| 01 Contracts and fixtures | ready | — | pending |
| 02 Semantic model | waiting | 01 | pending |
| 03 TeX bridge and measurement | waiting | 01, 02 | pending |
| 04 Constraints and diagnostics | waiting | 01, 02 | pending |
| 05 Structural analysis | waiting | 02, 04 | pending |
| 06 Serpentine rows and pages | waiting | 03, 04, 05 | pending |
| 07 Ordering and coordinates | waiting | 06 | pending |
| 08 Routing and ports | waiting | 07 | pending |
| 09 Annotations, labels, quality | waiting | 06, 07, 08 | pending |
| 10 TikZ renderer | waiting | 01, 03; final integration 09 | pending |
| 11 Integration and release gates | waiting | 01–10 | pending |

The current code is the legacy prototype. No implementation task has started.
