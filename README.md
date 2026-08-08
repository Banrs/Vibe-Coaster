# Falcon Flightline

A deterministic, rideable Godot checkpoint inspired by the scale and pacing of Intamin's
Falcon's Flight. The project opens directly into a moving seven-row train; route generation,
analysis, rendering, and rider cameras are all native GDScript.

This is a frontier concept, not a survey reconstruction or a certified ride design. Its acceptance
contract is:

- 5.4–5.6 km of track, centred on 5.5 km
- 319–321 km/h top speed, 158–165 seconds elapsed, and at least 120 km/h elapsed average speed
- signature geometry near 1.25× current records: about a 198 m main drop and 206 m camelback
- three visible LSM zones, zero inversions, no helix, an outward-banked rim turn, and a distinct
  non-inverting opening side-drop
- a deliberately used frontier force envelope of +7.0/−2.5 vertical g, ±4.0 lateral g,
  ±7.0 longitudinal g, 15 g/s onset, and 110°/s roll rate

Thrill track—including high-speed banked turns—is force-vector designed. Geometry-driven sections
are reserved for the station, lifts, launches, brakes, and the explicit station return. Smooth force
and bank profiles plus the degree-nine return preserve C4 position continuity without hiding a
late correction. See [the reference decisions](docs/REFERENCE.md) for the source interpretation and
model boundary.

The current validated build is 5.577 km in 163.8 seconds, peaks at 320.1 km/h, and averages
122.6 km/h including the physical low-speed cliff holding-brake crawl. Its 198 m main drop and
210.5 m camelback use train-averaged energy, and all seven rows remain inside the filtered frontier
envelope while deliberately approaching its vertical, combined-axis, onset, and roll-rate limits.

## Run

Godot 4.7 or newer:

```sh
godot --path godot
```

Controls:

- `C`: POV → chase → overview → fly camera
- `1`–`7`: choose a row
- `Space`: pause
- `R`: restart
- `[` / `]`: playback speed
- Fly camera: right mouse + mouse look, `WASD`, `Q/E`, Shift

## Verify

```sh
godot --headless --path godot --editor --quit
godot --headless --path godot --script res://smoke.gd
```

The smoke test builds the model twice to prove deterministic output, runs the model's geometry,
continuity, pacing, and human-load validation, then constructs the rail and terrain meshes.

The force limits are a concept-design envelope informed by amusement-ride practice, not a claim of
ASTM certification. Restraints, seats, suspension, structures, evacuation, and detailed vehicle
dynamics are intentionally not modelled yet.
