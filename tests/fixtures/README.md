# Successor fixture catalogue

Run `python3 tests/run_contracts.py` from the repository root. It uses only the
Python standard library and checks the version 1 schemas, mock Scenes, and
fixture catalogue. This is a development command; end users still compile
diagrams with ordinary LuaLaTeX.

`manifest.json` records current example sources and planned successor cases.
`status=source` means the legacy `.tex` exists as a semantic input; it is not
a geometry baseline. `status=planned` means the case is specified here and
needs a `.tex` input when its responsible implementation part arrives.
`visual_review.reference`, `rating`, and `notes` start at `null` because no
successor layout has been rendered or rated yet. The `standard` check profile
names the checks every solved fixture must eventually run. A fixture's
`semantic` object gives expected relationships or diagnostics, never expected
coordinates.

The two valid mock traces are inputs for part 10's renderer and part 09's
checker. The invalid trace deliberately combines a nonpositive scale, a
fractional sp dimension, a nonorthogonal route, and a nonzero hard violation.
Mock geometry is illustrative, not a prototype coordinate regression target.
