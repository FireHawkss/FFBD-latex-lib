# Agent instructions for tikzffbd

The current package is a pdfLaTeX-compatible prototype. The approved successor
architecture and agent workflow are in [docs/agent-plan/README.md](docs/agent-plan/README.md).

When assigned a numbered implementation part:

1. Read `docs/agent-plan/ARCHITECTURE.md`, `CONTRACTS.md`, the assigned task card,
   and the handoffs listed as dependencies. Read `QUALITY.md` for visual work.
2. Implement only that part. Treat `CONTRACTS.md` as the shared interface. If a
   contract must change, document the reason and update affected task cards before
   building against the changed contract.
3. Keep the end-user workflow to ordinary LuaLaTeX compilation, locally and on
   Overleaf. Development tests may use scripts; the published package may not
   require an external layout executable, shell escape, or preprocessing.
4. Run the task card's acceptance checks. Record results and known limitations in
   `docs/agent-plan/handoffs/NN.md` using `HANDOFF_TEMPLATE.md`.
5. Update `docs/agent-plan/STATUS.md` when the part is complete. Do not mark a
   part complete if its acceptance criteria have not been met.

Do not use the old `HANDOFF.md` as the target architecture; it documents the
prototype and its history. Do not silently shrink diagrams to fit a page.
