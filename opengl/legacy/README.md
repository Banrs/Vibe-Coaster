# Legacy V1 generator — restored live target

These files are the later **July 9–10 V1 procedural-track generator**. This is the active V1
repair target and is compiled directly by `opengl/src/main.cpp`.

- `coaster_track.cpp` — the repaired V1 streaming generator (the `Track` type).
- `coaster_elements_ext.cpp` — V1 element builders included by `coaster_track.cpp`.
- `audit_diagnostics.cpp` — V1-only audit/census diagnostics.

This is not `legacy/v1-original-nocap`, and it is not the V2 or rewrite generator. The live
headless checks are `--v1issues`, `--audit`, `--census`, and the deterministic export test.
