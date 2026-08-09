# Vibe-Coaster

A seed-based, one-shot roller-coaster generator in pure GDScript (Godot 4.7). Every seed is a
complete, rideable, physically validated ride: a near-future (~2041) hybrid of Intamin's
Falcon's Flight and B&M's Tormenta: Rampaging Run, on a seeded desert escarpment of ~300 m
relief. Same seed, same ride — bit for bit.

This is an engineering-sim concept, not a survey reconstruction or a certified design.
Physics, generation, and validation are the product; the visuals are a deliberately generic
inspection layer (placeholder train, simple track and pillars).

## What a seed contains

- Records chased honestly: ~340 km/h via a downhill tunnel launch, a ~250 m camelback
  (structure above its valley), a ~90° cliff dive down ~0.8× the escarpment relief, a
  75–95 m Immelmann (tallest-inversion class), a helical-leg vertical loop, a cutback,
  9–10.5 km of track.
- Falcon's Flight's skeleton in five cohesive gestures — twisted side-drop into one flowing
  low act, a boosted-then-coasting decelerating cliff climb, one crest hold with an
  outward-banked rim turn, a monotonic 90° dive into the tunnel launch and camelback, and a
  single sweeping return arc home — with Tormenta's inversion act grafted where its physics
  belongs (act one, at 42–50 m/s). No lifts: a ~4 g air-powered entry launch plus two short
  ~2 g LSM boosters (one of them the record launch), every climb an unpowered coast.
- Exactly three boost zones, no mid-course brake, one continuous energy arc after the tunnel
  launch, and one deliberate slow beat (the crest hold).
- A ~2041 human-load envelope: duration-stretched ASTM F2291 curves at +8.0/−3.0 Gz ·
  ±4.7 Gy · +8.0/−6.0 Gx · 25 g/s onset · 120°/s roll (anti-G-suit and restraint-tech
  credits — design fiction grounded in `docs/RESEARCH.md` §5).

Every seed passes: frame orthonormality and C4 seam continuity, terrain and self clearance,
per-row (7 rows) filtered envelope usage on the duration curves, push-pull, the 0.2 s
reversal rule, pairwise combined-axis ellipses, onset and roll-rate limits, element-shape
expectations (camelback structure, inversion heights, dive steepness), and determinism.

## Run

```sh
godot --path godot
```

- `N`: generate a new seed (the HUD shows the current one)
- `C`: POV → chase → overview → fly camera; `1`–`7`: choose a row
- `Space`: pause · `R`: restart · `[` / `]`: playback speed
- Fly camera: right mouse + mouse look, `WASD`, `Q/E`, Shift

## Verify

```sh
godot --headless --path godot --editor --quit
godot --headless --path godot --script res://smoke.gd
```

The smoke gate self-tests the verification toolkit against synthetic signals, probes every
element template against its closure contract, and builds multiple seeds twice — identical
output, all checks green, on CI's ubuntu baseline as the performance floor.

Design history: `docs/PLAN.md` (the executed rewrite plan), `docs/RESEARCH.md` (fact-checks,
POV analysis, envelope grounding), `docs/REFERENCE.md` (retired checkpoint rationale).
