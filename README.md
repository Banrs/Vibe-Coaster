# Vibe-Coaster

> **Directional, not a spec.** These docs exist so each session doesn't re-ask the basics. Revise freely.

A roller-coaster simulator built on real design math. You describe the ride you want, a solver
generates real geometry from real force math, and you ride it.

Reference point: **Falcon's Flight** — steel, four-across, LSM-launched. It's the floor, not the ceiling.

## Pillars

- **Ride-first.** The POV is the payoff. Row choice should matter.
- **FVD-first.** The force profile is the source of truth; geometry is solved from it.
- **One-shot generation.** You give a sequence (element → height → element → booster) and the whole
  ride is solved in a single pass — forces, energy, terrain and station closure all at once. No
  correction passes, no modifiers bolted on.
- **Terrain is an input, not a feature.** The solver is terrain-aware from the first line. Falcon's
  Flight is a cliff ride; ground is not scenery.
- **Real engineering, extended.** Real force envelopes and structural critique. The near-future part
  is propulsion and restraint — maglev running gear, active suspension, active restraint — expressed
  as vehicle parameters, not special cases.
- **Records are the target.** Taller and faster than anything built. Near-future tech relaxes the
  *engineering* limits; the G-force envelope stays enforced.
- **Pacing is the metric.** Judged on the shape of the whole ride, not peak numbers.

## Non-goals

Park management. Spinning seats, tilting trains, actuated track (disorienting on a flat screen —
the thrill here is speed and scale). Manual spline editing as the primary mode. Photorealism. VR.

## Docs

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — stack, layers, open questions
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — build order

## Building

```
cargo test --workspace
cargo run --release -p vc-ride --bin generate && open out/ride.html
```

That solves the preset ride and opens a POV of it. Current state: **rideable**, through a stand-in
HTML viewer rather than Godot. The generator produces a closed 5.6 km circuit at 321 km/h on maglev
running gear, inside a near-future force envelope. See [`docs/MODEL.md`](docs/MODEL.md) for what
works, what does not, and what needs deciding. Destined for `github.com/Banrs/Vibe-Coaster`.
