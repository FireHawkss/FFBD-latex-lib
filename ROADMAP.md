# Successor implementation roadmap

The current package is the pdfLaTeX-compatible prototype described in
`README.md`. The agreed successor requires LuaLaTeX and keeps the user's
workflow to ordinary `.tex` compilation.

To begin the sequential fresh-agent workflow, read
[docs/agent-plan/WORKFLOW.md](docs/agent-plan/WORKFLOW.md), then assign the first
ready card in [STATUS.md](docs/agent-plan/STATUS.md). The complete decisions,
interfaces, quality gates, task cards, and handoff template are indexed by
[docs/agent-plan/README.md](docs/agent-plan/README.md).

The [prototype inspection map](docs/agent-plan/CURRENT_IMPLEMENTATION.md)
identifies old code entry points and known fragility. It is background for
implementation agents, not a requirement to preserve the old architecture.
