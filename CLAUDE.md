# Vibe-Coaster — start here

This repository is a seed-based one-shot coaster generator in pure GDScript: a near-future
(~2041) hybrid of Falcon's Flight and Tormenta: Rampaging Run. Physics, generation, and
validation are the product; visuals are a deliberately generic inspection layer.

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
- `godot/elements.gd` — the integrator core (explicit rider frame: transported tangent/up +
  authored roll rate — inversions and vertical track are representable) plus every element
  template (`author_*`): each returns solved FVD sections via 1D secant closures
  (`solve_scalar`), no hidden trims. Group boundary contract: normal 1.0, lateral 0.0,
  roll rate 0.0 at group edges; equal values at internal seams (quintic keys ⇒ C4 position).
- `godot/generator.gd` — seed → ride. ALL randomness is drawn up front in `_plan()` in a
  fixed, unconditional order; assembly reads only the plan and the live integration state.
  Layout works in the terrain's s/a edge frame. `REGISTRY` is the data-driven extension
  point for the future configurable generator.
- `godot/verify.gd` — the load-verification toolkit: 100 Hz resample → 4-pole 5 Hz
  Butterworth → duration-dependent envelope usage (held-curve), plus push-pull, the 0.2 s
  reversal rule, pairwise combined-axis ellipses, onset (least-squares over 100 ms), and the
  structural checks (frames, seams, terrain/self clearance). Parametric — no element names.
- `godot/main.gd` — viewer: meshes, cameras, seven rows, metrics HUD, seed key (N).
- `godot/smoke.gd` — headless gate: toolkit self-tests, template probes, and multi-seed
  generator validation (same seed twice bit-identical; every seed passes every check).

## Generator contract

- Same seed → bit-identical ride. No RNG outside `_plan()`; no `Dictionary` iteration order
  dependence; no post-hoc geometry patching (the one sanctioned correction is the climb-pitch
  retune in the generator).
- Envelope (~2041, anti-G-suit credit; duration-stretched ASTM F2291 curves, never flat
  tables): +8.0/−3.0 Gz · ±4.7 Gy · +8.0/−6.0 Gx · 25 g/s onset · 120°/s roll. The limit at
  duration t is `stretch × F2291_limit(t)` per axis — see `verify.gd` constants.
- Story skeleton (seeded variation inside slots): station → LSM1 lift → twisted non-inverting
  side-drop → act-one inversions at honest speed (giant Immelmann ~75–95 m: the
  tallest-inversion chase; helical-leg loop ~52–68 m; cutback at the Immelmann exit) →
  airtime hills + wave turn → LSM2 launch + decelerating powered climb up the escarpment →
  crest crawl/hold (the ride's one deliberate slow beat) → clifftop suspense (reference-scale
  only, outward-banked rim turn) → 90° cliff dive (~0.8× relief, monotonic, no lip pause) →
  tunnel + downhill LSM3 to ~340 km/h → record camelback (~250 m structure above its valley)
  → return run with corridor-gated beats → brakes → explicit C4 station closure.
- Exactly three contiguous LSM zones. No mid-course brake: one continuous energy arc after
  LSM3. Records live in the marquee elements; suspense/clifftop elements never scale toward
  records; no element class between ~110 m and the ~250 m marquee pair (the gap is the
  authentic pattern).
- Physics limits discovered by measurement, respected by design: giant inversions need
  42–50 m/s entries (hence act one); `author_cutback` requires entry pitch ≤ ~22°; a planar
  loop self-intersects (hence the helical lateral with sign reversed at the top).

Do not restore the removed Rust optimizer, native extension, HTML viewer, hardcoded
`ride_model.gd` route, runtime correction passes, or the old flat per-duration limit tables.
Do not add restraint/seat/suspension/structural models until requested. History and rationale:
`docs/PLAN.md` (executed), `docs/RESEARCH.md` (Step-0 findings), `docs/REFERENCE.md` (retired
checkpoint rationale).
