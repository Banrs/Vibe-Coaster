# FVD-First Generator Program Roadmap

> **Status:** approved design decomposition. Execute with
> `superpowers:subagent-driven-development`, test-first, one implementation task at a time.

## Current state (verified 2026-08-12)

The deterministic legacy audit is built and its last complete GitHub artifact is preserved beneath
ignored `out/baselines/legacy-audit-2a891d2`. The user stopped further evidence-baseline remediation
because it did not materially change the ride.

**Next action: `2026-08-12-material-generator-vertical-slice.md`, Task 1.** Its accompanying execution
addendum, `../specs/2026-08-12-material-generator-vertical-slice-design.md`, preserves the approved
product and physics contracts but supersedes the adapter-first, dormant-candidate execution order.

All gates verified green at `a2445a8` with `out/tools/godot-4.7.1/Godot_v4.7.1-stable_win64_console.exe`:
editor import, `res://smoke.gd` (~248 s local; 12/12 seeds build and place clean, 7.6–10.2 km),
`res://fidelity_tests.gd`, and `res://fidelity_artifact_tests.gd` all exit 0.

Incidental, not acted on: `RideGenerator._approach_run` (`godot/generator.gd:2588`) has no callers
anywhere in the repository — leftover from an earlier launch-corridor solve, while its sibling
`_approach_heading` is still live.

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
  catalog exists.
- `CanonicalData` remains the sole canonical JSON/SHA-256 implementation.
- `motion.gd` stores controls as typed Float64 coefficient data and produces one packed native
  trajectory plus dynamics-derived dense output. No per-step Dictionary/RefCounted allocation or
  alternate geometry path exists.
- The validated packed route Dictionary is the stable public consumer boundary. It owns the
  trajectory data/handle and exact gesture-role sample/time/distance windows; internal typed structs
  may serve the hot loop but do not create a second public route type.
- `RideGenerator.build(seed) -> Dictionary` and
  `build_config(file_config, cli_overrides) -> {ok, route, resolved_config, plan, errors}`.
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
