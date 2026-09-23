# FFBD successor architecture: agent entry point

This directory is the approved plan for replacing the current prototype with
an in-compile LuaLaTeX layout engine. It is planning material; the current
`tikzffbd.sty` still implements the old engine until the tasks are executed.

Start with [WORKFLOW.md](WORKFLOW.md). The decisions are in
[ARCHITECTURE.md](ARCHITECTURE.md), the shared data/API definitions in
[CONTRACTS.md](CONTRACTS.md), and visual gates in [QUALITY.md](QUALITY.md).
[STATUS.md](STATUS.md) identifies the next ready part. Each numbered card under
`tasks/` is a bounded assignment for one fresh coding agent. Completed agents
write a matching file under `handoffs/`.

The task dependency graph is:

```text
01 contracts and fixtures
  -> 02 semantic model
       -> 03 TeX bridge and measurement ----\
       -> 04 constraints and diagnostics ---+-> 05 structural analysis
                                            -> 06 serpentine rows and pages
                                            -> 07 ordering and coordinates
                                            -> 08 routing and ports
                                            -> 09 annotations, labels, quality
  -> 10 TikZ renderer (may start after 01, against mock Scenes;
                       final integration needs 03 and 09)
  -> 11 integration and release gates (needs 01-10)
```

Part 03 and part 04 may proceed independently after part 02. Part 10 may be
developed in an isolated worktree while layout work proceeds. The default
workflow is one agent and one part at a time.

The expected implementation location is `tikzffbd.sty` plus colocated
`tikzffbd-*.lua` modules, with tests under `tests/`. Keeping the Lua files beside
the style file makes local and Overleaf distribution straightforward. A task may
choose different module filenames while preserving the contracts.

The old [project handoff](../../HANDOFF.md) and [README](../../README.md) describe
the current prototype. They are historical input, not instructions to preserve
its layout internals or pdfLaTeX compatibility.
