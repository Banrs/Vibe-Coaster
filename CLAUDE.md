# Vibe-Coaster — start here

This repository is a seed-based one-shot coaster generator in pure GDScript: a near-future
(~2041) hybrid of Falcon's Flight and Tormenta: Rampaging Run. Physics, generation, and
validation are the product; visuals are a deliberately generic inspection layer.

> **Current generator checkpoint:**
> The approved FVD-first redesign and material-generator vertical slice now back the public
> `RideGenerator.build()` path. `docs/superpowers/specs/2026-08-09-fvd-first-configurable-generator-design.md`
> and `docs/superpowers/specs/2026-08-12-material-generator-vertical-slice-design.md` remain the
> design rationale; the architecture and generator contract below describe the landed runtime.
> `docs/superpowers/specs/2026-08-12-material-generator-vertical-slice-design.md` is the approved
> execution addendum and `docs/superpowers/plans/2026-08-12-material-generator-vertical-slice.md` is
> the executed plan. They supersede the adapter-first/dormant-candidate order in the older route,
> kernel, recipe, and cutover plans.
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

Performance verdicts come from GitHub Actions (ubuntu ≈ 2× slower than a dev Mac), not from
local timings.

## Architecture (keep this split)

- `godot/terrain.gd` — seeded analytic heightfield: plain + one escarpment (gentle apron ~20%
  of relief, near-vertical face ~80%). Pure function of its params dict.
- `godot/generator.gd` — the `material-v1` facade: seed → accepted terrain-relative plan →
  compiled program → one accepted production integration → published route. The seeded RNG is
  consumed by `Terrain.generate()` and then `_plan()`; the plan contains twenty ordered roles and
  a 7.8–8.2 km route band.
- `godot/ride_program.gd` — native force/time-domain recipes and bounded return, capture, and
  brake solves. `godot/motion.gd` is the sole accepted rider-frame integrator;
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
- `godot/smoke.gd` — headless gate: toolkit self-tests, both focused
  fidelity suites, and multi-seed generator validation (same seed twice bit-identical). Be
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
  POVs; these do not change the committed catalog or resolve the POV map. Operational failures
  (catalog, generation, physical consistency, artifact writes) exit 1; fidelity misses are
  diagnostic and exit 0. See README for the command and the full output contract.

Diagnostic results are evidence to read, not verdicts. A `no-eligible-finding` recommendation
means no catalogued evidence was eligible, not that the ride is right; a green audit never
licenses closing a ride-quality issue. Filtering is allowed only for the human-tolerance
verifier or an explicitly catalogued evidence comparison, and must be labelled — generated
positions stay raw for physics, verification, and generated-channel measurement.

## Generator contract

- Same seed → bit-identical ride. The seeded RNG is used only by terrain generation and `_plan()`;
  no `Dictionary` iteration-order dependence or post-hoc geometry patching.
- Envelope (~2041, anti-G-suit credit; duration-stretched ASTM F2291 curves, never flat
  tables): +8.0/−3.0 Gz · ±4.7 Gy · +8.0/−6.0 Gx · 25 g/s onset · 120°/s roll. The limit at
  duration t is `stretch × F2291_limit(t)` per axis — see `verify.gd` constants.
- Material story, twenty ordered roles with seeded terrain-relative placement:
  station → ~4 g air-launch + unpowered coast over the opener crest → twisted non-inverting
  side-drop into act one, ONE flowing arc at honest inversion speed (giant Immelmann
  100–110 m: the tallest-inversion chase; helical-leg loop; cutback at the Immelmann exit;
  hills + wave turn, all chained exit-to-entry) → LSM2 boost at the cliff base (~290 km/h)
  + unpowered decelerating coast up the escarpment → crest crawl/hold (the ride's one
  deliberate slow beat) + compact clifftop suspense (reference-scale only, outward-banked
  rim turn) → 90° cliff dive (~0.8× relief, monotonic, no lip pause) → tunnel LSM boost to
  ~340 km/h (the record launch) → record camelback (~250 m structure above its
  valley) → force-authored return with two overbanked turns and two height/airtime beats →
  brakes → explicit C4 station closure.
- Propulsion = exactly three short boosters, no lifts, no powered climbs (user decision):
  a Do-Dodonpa-like non-LSM air/hydraulic entry launch at ~4 g out of the station, then two
  LSM boosters at ~2 g class (fastest-current-LSM × near-future credit), each shorter than
  Falcon's booster sections. Boosters need not be flat — like Falcon's, a launch may extend
  into a climb or run a varying gradient. No mid-course brake: one
  continuous energy arc after the tunnel booster. No standalone connector turns, no sub-30 m stub
  sections, no flat grades between elements; elapsed average speed is reported, never
  targeted — pacing is organic. Length 7.8–8.2 km. The unpowered return is authored in normal-g
  and bank/roll functions; a bounded seven-control solve targets the derived capture-entry
  corridor, the 7.8–8.2 km route band, and the 70–77 m/s passive entry-speed band with
  coarse/fine agreement, then the capture solve closes the
  station frame. Records live in the marquee elements; suspense/clifftop elements never scale toward
  records; no element class between ~110 m and the ~250 m marquee pair (the gap is the
  authentic pattern).
- Physics limits discovered by measurement, respected by design: giant inversions need
  42–50 m/s entries (hence act one); the cutback requires entry pitch ≤ ~22°; a planar
  loop self-intersects (hence the helical lateral with sign reversed at the top).

Do not restore the removed Rust optimizer, native extension, HTML viewer, hardcoded
`ride_model.gd` route, runtime correction passes, or the old flat per-duration limit tables.
Do not add restraint/seat/suspension/structural models until requested. History and rationale:
`docs/PLAN.md` (executed), `docs/RESEARCH.md` (Step-0 findings), `docs/REFERENCE.md` (retired
checkpoint rationale). Measured real-ride telemetry (the fidelity ground truth — per-element
g/duration tables for Falcon's Flight, Tormenta, and class exemplars): `docs/TELEMETRY.md`
and `docs/TELEMETRY-I305.md`. Fidelity targets = measured counterpart × per-axis envelope
stretch on values (Gz+ ×1.333, Gz− ×1.5, Gy ×1.567, Gx− ×1.71), measured hold durations kept.
