# 03 — TeX input bridge and measurement

## Scope

Connect the current `ffbd` command vocabulary to the Lua model and produce
accurate TeX `Metrics` for all visible text and objects. Add a clear LuaLaTeX
requirement and the agreed high-level options.

## Out of scope

Do not implement layout, routing, quality scoring, or a new FFBD language.
Keep the existing theme concepts; do not redesign visual style in this part.

## Dependencies

Accepted handoffs 01 and 02.

## Interfaces/contracts

Input produces `Spec`, `Metrics`, and `Frame`. Raw LaTeX tokens stay in a
per-environment text registry keyed by `text_ref`; Lua receives safe IDs and
integer-sp measurements. `scale` remains an explicit positive user value.
Implement public options per `CONTRACTS.md`, including hard `\endrow` and an
optional soft form. Existing `\annotation[Type]{id}{text}` remains accepted.

## Files/components affected

Parser and style/measurement portions of `tikzffbd.sty`; a small bridge Lua
module; input/measurement tests. The old layout file may remain during staging.

## Implementation steps

1. Detect LuaLaTeX and initialize the colocated Lua modules using TeX's file
   lookup; document local and Overleaf distribution.
2. Translate every current command into builder operations without placing it.
3. Store original label tokens and measure boxes with the eventual styles.
4. Add `scale`, `multipage`, strength, and supported annotation-position keys.
5. Ensure two FFBD environments cannot share data or token references.

## Tests and acceptance criteria

Existing examples parse under LuaLaTeX; text with math, macros, punctuation,
and TeX special characters survives exactly; measurements match rendered box
extents within documented tolerance. A pdfLaTeX run reports a concise compiler
requirement. No shell escape or external process is invoked.

## Context required by the agent

Handoffs 01-02, contracts, current `tikzffbd.sty` commands and styles. Later
solver parts will consume the produced `Spec`, `Metrics`, and `Frame`.

## Handoff result

`handoffs/03.md` documents option syntax (especially annotation keys), the
text-registry interface, measurement tolerance, and integration test command.
