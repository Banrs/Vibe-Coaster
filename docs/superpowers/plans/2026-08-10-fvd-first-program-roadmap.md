# FVD-First Generator Program Roadmap

> **Status:** approved design decomposition. Execute with
> `superpowers:subagent-driven-development`, test-first, one implementation task at a time.

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

1. `2026-08-09-evidence-audit-baseline.md`
   - Execute against the untouched legacy route dictionary.
   - Establish corrected measurement semantics, reviewed source records, deterministic reports,
     visual artifacts, and a one-build-per-seed baseline before behavior changes.
2. `2026-08-09-route-config-foundation.md`
   - Introduce the final immutable Route/Trajectory boundary through one temporary adapter.
   - Migrate all consumers atomically and add deterministic configuration/planning.
3. `2026-08-09-time-domain-motion-kernel.md`
   - Add the approved time-domain FVD law, packed dense sampler, analytic boundary jets, bounded
     solver, and station-capture validation behind tests; legacy behavior remains authoritative.
4. `2026-08-09-default-ride-recipes.md`
   - Compile the complete approved story into one MotionProgram and one candidate RideRoute.
   - Keep the legacy runtime public until the candidate fleet passes every prerequisite gate.
5. `2026-08-09-runtime-cutover-and-polish.md`
   - Cut over the only runtime path, delete legacy FVD/grade/closure/repair execution, rerun the
     same audit, and accept at most three shared evidence-backed refinements.
   - Preserve element geometry profiles plus force/angle/speed/AGL/curvature/radius/jerk outputs.

The audit implementation comes first because it is the pre-change oracle. Its final typed-route
migration and post-change run still occur at the design's fidelity gate; this is one tool and one
catalog, not two audit systems. Stable semantic selectors carry explicit legacy-beat and
compiled-story-slot anchors so target identity survives the migration without an implicit remap.

## Shared contracts

- `RideCatalog` is the only configuration/story/recipe catalog:
  `PRESET_ID == "future-hybrid@1"`, `data`, `validate`, `content_hash`.
- `CanonicalData` is the only canonical JSON/SHA-256 implementation.
- `MotionTrajectory.create(channels, dense_sampler)` copies a closed set of singular SI packed
  channels, including authored `drive_g` and total proper `longitudinal_g`. One immutable packed
  sampler owns all dense interpolation and interval estimates; hot consumers reuse a typed
  `MotionSample`, and no per-step RefCounted objects, mutable append API, or alternate geometry
  path exists.
- `MotionSpan` stores each authored control as its own Float64 coefficient channel. `MotionProgram`
  derives stable role-level span windows, and `RideRoute` projects them to exact native/time/distance
  windows without widening unresolved selectors.
- `RideGenerator.build(seed) -> RideRoute` and
  `build_config(file_config, cli_overrides) -> {ok, route, resolved_config, plan, errors}`.
- `RideCompiler.compile(plan, kernel_config) -> {ok, route, program, report, error}` performs the
  accepted candidate's only full-resolution integration, then revalidates capture/handoff/endpoint
  invariants on that same trajectory without retry or reintegration.

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
