# Successor fixture catalogue

`manifest.json` contains 20 ordinary LuaLaTeX sources and their semantic
expectations. Run `python3 tests/run_contracts.py` for source/schema checks and
`python3 tests/run_integration.py` for two compilations of every case, exact trace
comparison, geometry checks, timing, memory and router-work evidence. Generated
build files go to `build/release/`; these scripts are development tools only.

Saved PDFs are in `references/`, integrated results in `release-report.json`,
and 10/30/50/64-block performance results in `benchmark-report.json`.
`REVIEW.md` links the PDFs and identifies remaining visual concerns. Human
`visual_review.rating` fields remain null until the user's final sign-off.
Separate `agent_visual_review` entries record only the PDFs actually inspected.
Automated pass rates must not be substituted for human readiness proportions.

`python3 tests/make_visual_fixtures.py` regenerates the added source fixtures and
source-count metadata. `source_blocks` counts all declarations in documents with
multiple environments; `blocks` describes the representative diagram size.
The expected diagnostic case has no PDF. The 64-block single-page case deliberately
warns about overflow and preserves scale; use its multipage counterpart for a
readable page-bound result.

The original JSON Scene mocks remain independent renderer/schema fixtures.
