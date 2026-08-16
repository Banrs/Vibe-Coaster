# Vibe-Coaster — start here

This repository is a seed-based one-shot coaster generator in pure GDScript: a near-future
(~2041) hybrid of Falcon's Flight and Tormenta: Rampaging Run. Physics, generation, and
validation are the product; visuals are a deliberately generic inspection layer.

> **Current generator checkpoint:**
> The approved FVD-first redesign and material-generator vertical slice now back the public
> `RideGenerator.build()` path. Design rationale lives in
> `docs/superpowers/specs/2026-08-09-fvd-first-configurable-generator-design.md`; its approved
> execution addendum is `docs/superpowers/specs/2026-08-12-material-generator-vertical-slice-design.md`,
> executed via `docs/superpowers/plans/2026-08-12-material-generator-vertical-slice.md`
> (Tasks 1–3; Task 4's config surface landed later — see that plan's status banner). The
> architecture and generator contract below describe the landed runtime and win over any spec
> prose they contradict. They supersede the adapter-first/dormant-candidate order in the older
> route, kernel, recipe, and cutover plans. No spec is beyond skepticism: where prose, spec,
> and code disagree, reproducible physical derivation and verified evidence decide, and the
> loser gets corrected.
>
> That design is a force-informed **hybrid**, not an FVD monoculture. FVD is preferred where
> authoring in the rider's frame gives superior rider-dynamics control; it is not to be forced
> onto layout, terrain fitting, closure, or exact-geometry work that another physically coherent
> method solves better. Choosing the other method there is following the design, not deviating.

Run both checks before and after any change:

```sh
godot --headless --path godot --editor --quit
godot --headless --path godot --script res://smoke.gd
```

Smoke alone does not run most of the test suites: CI additionally executes every script in
`.github/focused-tests.txt` (twelve focused suites — motion, bounded-solver, route-contract,
ride-program, generator-material, terrain-story, geometry-metrics, ride-planner, ride-config,
and three fidelity suites). When your change touches one of those areas, run the matching
focused suite(s) locally too:

```sh
godot --headless --path godot --script res://<suite>.gd
```

Performance verdicts come from GitHub Actions (ubuntu ≈ 2× slower than a dev Mac), not from
local timings.

## Architecture (keep this split)

- `godot/terrain.gd` — seeded analytic heightfield: plain + one escarpment (gentle apron
  15–22% of relief, near-vertical face 78–85%, drawn per seed). Pure function of its params
  dict.
- `godot/generator.gd` — the `material-v1` facade: seed → accepted terrain-relative plan →
  compiled program → one accepted production integration → published route. The seeded RNG is
  consumed by `Terrain.generate()` and then `_plan()`; the plan contains twenty ordered roles and
  a 7.8–8.2 km route band.
- `godot/ride_planner.gd` — the decision layer: named decision streams (FNV-1a over the stream
  name plus the seed, so streams are independent), the story grammar as data, and the certified
  per-seed target draws. Randomness lives only here and in terrain generation; every draw range
  is a claim that the whole range builds, certified by `ride_planner_tests.gd` — there are no
  candidate loops downstream.
- `godot/ride_config.gd` — the version-1 configuration surface behind
  `RideGenerator.build_config()`: overlay algebra (rules 1–7), canonical hash, resolution report.
  The registry is deliberately narrow — `preset`, `seed`, and `slot.intensity` on the two return
  heights — and every key that did not clear that bar sits in `UNREGISTERED` with the measurement
  that refused it.
- `godot/ride_program.gd` — native force/time-domain recipes, plan validation, and the public
  `RideProgram` API; its two solve seams live in `godot/ride_prefix_solve.gd` (prefix
  capability + closure solve) and `godot/ride_return_solve.gd` (bounded return, capture, and
  brake solves). `godot/motion.gd` is the sole accepted rider-frame integrator;
  `godot/route_contract.gd` validates and publishes its trajectory.
- `godot/verify.gd` — the load-verification toolkit: 100 Hz resample → 4-pole 5 Hz
  Butterworth → duration-dependent envelope usage (held-curve), plus push-pull, the 0.2 s
  reversal rule, pairwise combined-axis ellipses, onset (least-squares over 100 ms), and the
  structural checks (frames, seams, terrain/self clearance). Parametric — no element names.
- `godot/main.gd` — viewer: meshes, cameras, seven rows, metrics HUD, seed key (N). Its
  static sampling API is a thin delegate to `route_sampling.gd`; behavior is unchanged.
- `godot/route_sampling.gd` — the one route time/distance/pose interpolation, shared by the
  viewer and the deterministic POV artifacts. `godot/canonical_data.gd` — the one canonical
  JSON + SHA-256 implementation, shared by catalog and report code.
- `godot/smoke.gd` — headless gate: toolkit self-tests, two of the three fidelity suites
  (`fidelity_tests.gd`, `fidelity_artifact_tests.gd`; `fidelity_overlay_tests.gd` runs only
  via the CI focused-test manifest), and multi-seed generator validation (same seed twice
  bit-identical). It also gates the record band (top speed 93.9–95.6 m/s), the entry-launch
  peak band (3.7–4.1 g), and fleet diversity (floors on the length and duration spread across
  the accepted fleet, so the fleet cannot become one ride fifteen times). Be
  precise about its coverage: structure, seams, terrain clearance and self-clearance are
  gated on all fifteen seeds, but the load envelope (`validate_loads`) is gated only on the
  three deep seeds 11/42/20260809 — the twelve sweep seeds are deliberately ungated on loads
  for CI time. Widen that only with a measured CI-time budget.
- `godot/fidelity_references.gd` — the committed evidence catalog: sources, transforms,
  selectors, review prompts, evidence gaps. Catalog `2026-08-10.evidence-baseline.2` holds 12
  sources (12 corroborative/observation-only/review-pending, none `executable`), 6 transforms,
  6 review prompts, 5 evidence gaps — and empty `selectors`, `observations` and `targets`, so
  no comparison band exists yet. URLs live here (and in
  `docs/evidence/fidelity/`) as inert provenance strings only; no network client exists.
- `godot/fidelity_counterparts.gd` — the per-role counterpart bands (measured real-ride value ×
  the per-axis envelope stretch); the derivation that produced them is
  `docs/evidence/fidelity/counterpart-bands.md`.
- `godot/geometry_metrics.gd` — geometry measurement, not force measurement: seam roll
  continuity, element planarity and tilt, shape ratios, and the counterpart comparison against
  `fidelity_counterparts.gd`. `godot/geometry_reference.gd` renders overlays against local
  reference imagery named by `REF_MEDIA_MANIFEST`. Both are diagnostic — never gates — and no
  reference media is ever committed.
- `godot/fidelity.gd` — read-only measurement and comparison: catalog validation, beat/row
  bands, exact held values, time-weighted pacing shares, transition windows, raw channel
  reconstruction, fleet comparison, deterministic recommendation. `godot/fidelity_artifacts.gd`
  — deterministic report/Markdown, checked writes, and the render helpers.
- `godot/_inspect.gd` — inspection harness (not a gate) and the offline fidelity-audit runner.
  It keeps every existing diagnostic — per-element stats, phase tables, element side views,
  top/elevation, the stacked ride traces — and adds reconstructed longitudinal proper
  acceleration, curvature, radius, roll acceleration and jerk channels, evidence-linked
  review prompts and issue coverage, an explicit POV map that names its alignment gaps rather
  than inventing a mapping, optional local RideForcesDB diagnostic overlays via
  `RFDB_4804_CSV` / `RFDB_6383_CSV`, and checked writes with a hashed manifest. When either local
  export is supplied it also writes semantic overlay artifacts and diagnostic seed-42 midpoint
  POVs; these do not change the committed catalog or resolve the POV map. It also writes the
  geometry pack — `review/seed-<n>/geometry-metrics.{json,md}` and
  `review/counterpart-comparison.{json,md}` — plus reference overlays when
  `REF_MEDIA_MANIFEST` names a local manifest. Operational failures
  (catalog, generation, physical consistency, artifact writes) exit 1; fidelity misses are
  diagnostic and exit 0. See README for the command and the full output contract.

Diagnostic results are evidence to read, not verdicts. A `no-eligible-finding` recommendation
means no catalogued evidence was eligible, not that the ride is right; a green audit never
licenses closing a ride-quality issue. Filtering is allowed only for the human-tolerance
verifier or an explicitly catalogued evidence comparison, and must be labelled — generated
positions stay raw for physics, verification, and generated-channel measurement.

## Generator contract

- Same seed → bit-identical ride. The seeded RNG is used only by terrain generation and `_plan()`
  — and inside `_plan()` only through `ride_planner.gd`'s named streams; no `Dictionary`
  iteration-order dependence or post-hoc geometry patching.
- Envelope (~2041, anti-G-suit credit; duration-stretched ASTM F2291 curves, never flat
  tables): +8.0/−3.0 Gz · ±4.7 Gy · +8.0/−6.0 Gx · 25 g/s onset · 120°/s roll. The limit at
  duration t is `stretch × F2291_limit(t)` per axis — see `verify.gd` constants.
- Material story, twenty ordered roles with seeded terrain-relative placement, plus per-seed
  target draws made through `ride_planner.gd`'s named decision streams. Today only the
  return-side draw set is certified (turn-a transfer bank bias, height-a peak g, the unload
  scales); act-one permutation and the opener/act-one geometry draws were refused by
  measurement and stay blocked until the prefix closure solve lands — see `docs/ISSUES.md`
  issue 24. The story itself:
  station → 3.9 g-peak air-launch (band-gated) + unpowered coast over the opener crest → three-role opener
  (twisted non-inverting side-drop, overbanked teardrop, rising release) into act one, ONE
  flowing arc at honest inversion speed (giant Immelmann 100–110 m: the tallest-inversion
  chase; cutback at the Immelmann exit; helical-leg loop; hills + wave turn, all chained
  exit-to-entry) → LSM2 boost at the cliff base (the built assist enters at ~175 km/h and
  peaks at ~177 km/h — measured 2026-08-16)
  + unpowered decelerating coast up the escarpment → crest crawl/hold (the ride's one
  deliberate slow beat) + compact clifftop suspense (reference-scale only, outward-banked
  rim turn) → 90° cliff dive (~0.85–0.93× relief, monotonic once committed, no lip pause —
  the pre-commit approach length is open issue 22) → tunnel LSM boost to
  ~340 km/h (the record launch; the built top speed is gated in smoke at 93.9–95.6 m/s) →
  record camelback (~250 m structure above its
  valley, and **symmetric** — the rise and fall profiles mirror each other; pinned by user
  ruling 2026-08-16, so it is never an energy absorber: a chain that does not close is a
  refusal to record, not a licence to grow or reshape this hill) → force-authored return with
  two overbanked turns and two height/airtime beats →
  brakes → explicit C4 station closure.
- Propulsion = exactly three short boosters, no lifts, no powered climbs (user decision):
  a Do-Dodonpa-like non-LSM air/hydraulic entry launch peaking at 3.9 g out of the station
  (gated 3.7–4.1), then two
  LSM boosters (fastest-current-LSM × near-future credit; each booster's authored drive
  follows from its speed target and length — currently ~0.29 g on the cliff-base climb assist
  and 1.33 g in the tunnel, not a flat "~2 g class"), each shorter than
  Falcon's booster sections. Boosters need not be flat — like Falcon's, a launch may extend
  into a climb or run a varying gradient. No mid-course brake: one
  continuous energy arc after the tunnel booster. No standalone connector turns, no sub-30 m stub
  sections, no flat grades between elements (design intent — reviewed, not yet mechanically
  enforced by any validator); elapsed average speed is reported, never
  targeted — pacing is organic. Length 7.8–8.2 km. The unpowered return is authored in normal-g
  and bank/roll functions; a bounded seven-control solve targets the derived capture-entry
  corridor, the 7.8–8.2 km route band, and the 70–80 m/s passive entry-speed band (widened
  from 70–77 on 2026-08-15 — the measured cost of closing the ~340 km/h record inside
  8.2 km without a mid-course brake; see
  `docs/superpowers/specs/2026-08-15-record-launch-derivation.md`. Reverting it to 70–77
  together with the 3.0 g brake bound was built and refused on 2026-08-16: their reason only
  disappears under honest drag, honest drag does not close, and on today's drag the revert
  budget-exhausts the return on all three deep seeds — `docs/ISSUES.md` issue 2 and
  `docs/superpowers/specs/2026-08-15-honest-drag-derivation.md` §7) with
  coarse/fine agreement, then the capture solve closes the
  station frame. Records live in the marquee elements; suspense/clifftop elements never scale toward
  records; no element class between ~110 m and the ~250 m marquee pair (the gap is the
  authentic pattern).
- Physics limits discovered by measurement, respected by design: giant inversions need
  42–50 m/s entries (hence act one); the cutback requires entry pitch ≤ ~22° (measured
  during design; not re-measured or enforced by any current validator); a planar
  loop self-intersects (hence the helical lateral with sign reversed at the top).

Write the minimum code that solves the problem. Ship each piece of data once — in code or in a
document, never both. The read-only diagnostic layer must not outgrow the generator it measures.
If two hundred lines could be fifty, rewrite them; deflation with byte-identical behavior is
always in scope.

Do not restore the removed Rust optimizer, native extension, HTML viewer, hardcoded
`ride_model.gd` route, runtime correction passes, or the old flat per-duration limit tables.
Do not add restraint/seat/suspension/structural models until requested. Live measured gaps,
open ride-quality issues, and next-session guidance: `docs/ISSUES.md`. History and rationale:
`docs/PLAN.md` (executed), `docs/RESEARCH.md` (Step-0 findings), `docs/REFERENCE.md` (retired
checkpoint rationale). Measured real-ride telemetry (the fidelity ground truth — per-element
g/duration tables for Falcon's Flight, Tormenta, and class exemplars): `docs/TELEMETRY.md`
and `docs/TELEMETRY-I305.md`. Fidelity targets = measured counterpart × per-axis envelope
stretch on values (Gz+ ×1.333, Gz− ×1.5, Gy ×1.567, Gx− ×1.71), measured hold durations kept.
