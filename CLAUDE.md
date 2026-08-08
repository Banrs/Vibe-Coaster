# Falcon Flightline — start here

This repository is a lean Godot riding checkpoint, not a general coaster optimizer.

Run both checks before and after route changes:

```sh
godot --headless --path godot --editor --quit
godot --headless --path godot --script res://smoke.gd
```

## Architecture

- `godot/ride_model.gd` owns route sections, integration, frames, force analysis, and validation.
- `godot/main.gd` owns meshes, scenery, cameras, train playback, and the rider UI.
- `godot/smoke.gd` proves deterministic generation and exercises both layers headlessly.

Keep this split. Prefer direct values and profiles over new abstractions. Do not restore the removed
Rust optimizer, native extension, HTML viewer, or runtime correction passes.

## Route contract

- Target 5.4–5.6 km, 319–321 km/h top speed, 158–165 seconds including the physical cliff crawl, and at
  least 120 km/h elapsed average speed.
- Use FVD for hills, drops, transitions, and banked turns. Use authored grade only for the station,
  lifts, LSM launches, brakes, and the explicit C4 station return.
- The opening twisted drop is a non-inverting banked side-dive. The later main cliff dive is a
  separate, nearly straight element feeding downhill LSM 3.
- The rim turn banks outward. There are no inversions or helices, and exactly three contiguous LSM
  zones.
- Scale signature geometry to roughly 1.25× the relevant record: about 198 m for the main drop and
  206 m for the camelback. Scale smaller counterparts by operating speed; at equal force, radius is
  proportional to speed squared.
- Exercise, but do not exceed, the duration-aware frontier envelope: +7.0/−2.5 vertical g,
  ±4.0 lateral g, ±7.0 longitudinal g, 15 g/s onset, and 110°/s roll rate.
- Preserve C4 position continuity at kernels and seams. The station return must remain explicit,
  cusp-free, and at most 8% of route length.
- Keep all seven row viewpoints rideable and report the selected row's loads.

Do not add a restraint, seat, suspension, or structural model until that work is requested. This is
a human-viewable concept checkpoint, not a certification calculation.
