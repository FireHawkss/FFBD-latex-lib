# Starting, managing, and finishing agent work

## Start

1. Read [STATUS.md](STATUS.md) and choose the lowest numbered ready task. Start
   only when its dependency handoffs exist. Give a fresh agent this prompt:

   > Implement `docs/agent-plan/tasks/NN-*.md`. Read `AGENTS.md`,
   > `docs/agent-plan/ARCHITECTURE.md`, `CONTRACTS.md`, `QUALITY.md` where relevant,
   > and the dependency handoffs. Follow the card's scope and acceptance criteria.
   > At completion write `docs/agent-plan/handoffs/NN.md` from the template and
   > update `STATUS.md`. Report changed files, tests, and unresolved issues.

2. Use a fresh agent for the next part. Give it the same prompt with the next
   task number; it reads only the listed dependency handoffs, not full history.

## Manage

- One agent owns one task and its affected files. Sequential execution is the
  simplest default. Parts 03/04 or renderer part 10 can run concurrently only
  in separate worktrees, with nonoverlapping edits and explicit integration.
- Review each handoff against its task card before starting dependents. Confirm
  the contract, acceptance results, and changed files. Keep incomplete tasks
  `in progress` or `blocked` in `STATUS.md` with a concrete reason.
- A necessary contract change is proposed in the handoff, applied to
  `CONTRACTS.md` and affected task cards, then accepted before dependent work.
  Do not let separate agents implement incompatible interpretations.
- Development scripts and generated test files are allowed. End users must only
  select LuaLaTeX and compile their `.tex` file normally.

## Finish

Run part 11 after parts 01-10 have accepted handoffs. Review its local and
Overleaf compilation evidence, semantic and geometric tests, visual fixture
ratings, performance at 10/30/50/>50 blocks, diagnostics, and documentation.
Mark the roadmap complete only when part 11 meets its acceptance criteria.
The agent should leave a concise release handoff with any measured limits.
