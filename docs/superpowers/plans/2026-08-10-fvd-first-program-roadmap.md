# FVD-First Generator Program Roadmap

> **Status: superseded as a program index (2026-08-15).** The material vertical slice this
> roadmap pointed at has landed on `main`; live truth is root `CLAUDE.md` (architecture and
> generator contract) and `docs/ISSUES.md` (measured gaps and open issues), not this file.
> Kept as design history. Its original "Current state (verified 2026-08-12)" section
> contained claims that were already or have since become false and was corrected below on
> 2026-08-15 rather than left to mislead a future agent.

## Current state (corrected 2026-08-15; originally "verified 2026-08-12")

The user stopped further evidence-baseline remediation because it did not materially change
the ride. `2026-08-12-material-generator-vertical-slice.md` Tasks 1–3 have since been
executed and landed on `main`; its Task 4 (the version-1 configuration surface) was not
executed at that time, so `build_config` did not exist when this roadmap listed it as a
shared contract below.

Corrections to the original section's claims:

- The `out/baselines/legacy-audit-2a891d2` artifact lives under gitignored `out/` and does
  not survive a fresh clone; treat it as unavailable unless locally rebuilt.
- The "all gates green" list named only three suites; the CI manifest
  (`.github/focused-tests.txt`) now runs nine focused suites plus `res://smoke.gd`.
- The smoke measurement "12/12 seeds build and place clean, 7.6–10.2 km" does not describe
  the landed generator: all fifteen seeds build at ~8.13 km (see `docs/ISSUES.md`, gap A).
- The "incidental" note about `RideGenerator._approach_run` at `godot/generator.gd:2588` no
  longer corresponds to anything: neither `_approach_run` nor `_approach_heading` exists,
  and `generator.gd` is ~470 lines.

## Authority

- Product/design authority: `../specs/2026-08-09-fvd-first-configurable-generator-design.md`.
- Repository contract: root `CLAUDE.md`, except where that approved redesign explicitly replaces
  the documented legacy architecture or poor ride behavior.
- Diagnostic requirements: the user-approved Remote-Main Ride Fidelity Audit and issues 1–16 in
  `docs/ISSUES.md`.
- Remote `Banrs/Vibe-Coaster` `main` is the upstream baseline. Resolve it again before starting a
  new implementation workspace; use fast-forward only.
- The earlier `2026-08-09-ride-fidelity-audit.md` is superseded by the evidence-baseline plan below.

## Execution order

Execute `2026-08-12-material-generator-vertical-slice.md` in order. The earlier route foundation,
kernel, recipes, and runtime-cutover plans remain design history but are superseded as executable
plans: do not build their temporary adapter, ten-class scaffold, dormant candidate, or delayed
legacy deletion. The material plan retains their useful tests and contracts while moving the first
complete public cutover to its second acceptance boundary.

## Shared contracts

- `ride_program.gd` owns the sole configuration/story/recipe catalog and preset ID; no parallel
  catalog exists. (Landed preset ID: `material-v1`; the design's `future-hybrid@1` was the
  pre-implementation name and never shipped.)
- `CanonicalData` remains the sole canonical JSON/SHA-256 implementation.
- `motion.gd` stores controls as typed Float64 coefficient data and produces one packed native
  trajectory plus dynamics-derived dense output. No per-step Dictionary/RefCounted allocation or
  alternate geometry path exists.
- The validated packed route Dictionary is the stable public consumer boundary. It owns the
  trajectory data/handle and exact gesture-role sample/time/distance windows; internal typed structs
  may serve the hot loop but do not create a second public route type.
- `RideGenerator.build(seed) -> Dictionary`. (`build_config(file_config, cli_overrides)`
  was listed here as an existing contract before it was built — it is the material plan's
  Task 4, unexecuted when this roadmap was current.)
- Program compilation performs the accepted route's only full-resolution integration, then
  revalidates capture/handoff/endpoint invariants on that same trajectory without retry or
  reintegration.

## Non-negotiable gates

- Every production behavior begins with a focused failing test and observed expected failure.
- Every task ends green: focused suite, Godot import, existing smoke; no knowingly broken commit.
- Same seed/config is deterministic; exactly 15 canonical audit seeds, generated once per run.
- Exactly three propulsion zones; no hidden drive, lifts, route retries, geometry repairs, seed
  branches, smoothing, fitted replacement path, radius clamp, or tolerance inflation.
- Evidence states remain explicit. Unavailable RideForcesDB raw exports stay
  `raw_fetch_unavailable`; POVs, simulations, and unknown-row traces cannot silently define force
  gates. Only approved per-axis transforms scale force values; durations are retained.
- Fidelity remains diagnostic until a separately reviewed finding is promoted. Safety, malformed
  data, generation, and artifact writes remain hard failures.
- Final acceptance requires byte-identical repeated JSON/Markdown, complete review artifacts,
  fresh import/smoke, a source/POV review, independent code review, and one final Graphify hygiene
  pass. Graphify is not used during ordinary implementation.
