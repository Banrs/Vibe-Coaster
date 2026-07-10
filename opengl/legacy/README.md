# Legacy V1 generator — archived, do not touch

These files are the **V1 procedural-track generator**, retired when the V2 generator
(`opengl/src/track/`) went live in the OpenGL host (migration step 7, 2026-07-10). They are kept
here **byte-identical to their original state, purely for reference/tracking**. They are **not
compiled** — the unity build (`opengl/src/main.cpp`) no longer `#include`s them.

- `coaster_track.cpp` — the V1 streaming state-machine generator (the `Track` type).
- `coaster_elements_ext.cpp` — V1 element builders (was `#include`d by `coaster_track.cpp`).
- `audit_diagnostics.cpp` — V1-only audit/census diagnostics.

**Rules:** do not modify these, do not re-include them in the build, and do not consult them as a
reference for V2 work — V2 was a ground-up rewrite precisely because V1 is untrustworthy spaghetti
(see `opengl/COASTER_REWRITE.md`). Their only purpose here is historical: to compare against, or to
recover a V1 behavior/name if ever genuinely needed. The live headless correctness check that
replaced V1's `--census`/`--audit` modes is `./opengl/minecoaster --v2audit N`.
