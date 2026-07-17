# V1 Coaster

These files are the later **July 9–10 V1 procedural-track generator**. This is the active V1
target and is compiled directly by `src/main.cpp`.

- `src/` — game, rendering, simulation, and audit host code.
- `v1/coaster_track.cpp` — the repaired V1 streaming generator.
- `v1/audit_diagnostics.cpp` — V1 audit and census diagnostics.
- `MINECOASTER.command` — build and launch the game on macOS.

The no-cap snapshot, rewrite, captures, generated builds, and obsolete V2 sources are not
part of this package. Headless checks include `--v1issues`, `--jointaudit`, `--audit`,
`--census`, `--launchaudit`, `--forceaudit`, `--terrainaudit`, and deterministic export.
