# Geometry and Ride References

This project currently contains **no copied third-party source code**. The sources below are design references and factual anchors. Any future code import must be reviewed against its license before it is added.

## Geometry approach

Track geometry should have one source of truth: generate and validate each complete element, sample it adaptively by arc length, compute a rotation-minimizing frame, and publish one immutable track snapshot for physics, rendering, supports, and audits. Terrain may influence element placement or rejection, but must not deform already-authored element samples.

Element geometry uses one uniform linear scale `lambda` for height, plan dimensions, radius, and arc length, constrained to `1.0 <= lambda <= 1.5`. At twice the real coaster's entry speed, curvature acceleration scales as:

```text
a_game / a_real = 4 / lambda
```

For an upright vertical-force approximation:

```text
G_game ~= 1 + (4 / lambda) * (G_real - 1)
```

Production validation must use full vector proper acceleration rather than this scalar approximation. If an element cannot meet its speed, force, and dimensional constraints with one scale in the allowed range, it is ineligible at that entry speed; individual axes or joints must not be patched independently.

## Launch reference

Fuji-Q Highland's official Do-Dodonpa description reports `0-180 km/h` in `1.56 s`. Its mean acceleration is therefore `32.051 m/s^2` (`3.27 g`). The game's requested `1.5x` reference acceleration is:

```text
a = 48.077 m/s^2 = 4.90 g
d = (v_target^2 - v_entry^2) / (2a)
```

Representative distances to a `360 km/h` target are:

| Entry speed | Powered distance |
| --- | ---: |
| 0 km/h | 104.0 m |
| 180 km/h | 78.0 m |
| 240 km/h | 57.8 m |
| 300 km/h | 31.8 m |
| 320 km/h | 21.8 m |

A launch section's stated length is its actual powered distance. Any neutral lead-in or lead-out is a separate transition, and propulsion ends before a pitch or curvature transition.

Source: [Fuji-Q Highland, Do-Dodonpa description](https://staging.fujiq.jp/media/h5f6de000001ogfc.html).

## Official ride anchors

- [Intamin: Falcon's Flight](https://www.intamin.com/project/falcons-flight/) — `195 m` overall height, `250 km/h`, `4,325 m` track; a `55 m` first twisted drop, a `150 km/h` cliff launch, and a final `250 km/h` launch into a `165 m` camelback. Intamin describes deliberately drawn-out curves, gentle banking, and transitions balancing intense and quieter moments. Scaling the `165 m` camelback by `1.5x` gives `247.5 m`, within the project's `250 m` element/drop cap.
- [Intamin: Formula Rossa](https://www.intamin.com/company/about-us/) and [Ferrari World: Formula Rossa](https://www.ferrariworldabudhabi.com/en/rides/formula-rossa) — `240 km/h` from rest in `4.5 s`, `52 m` height, and `4.8 g`. The launch averages `14.815 m/s^2` (`1.51 g`) and approximately `150 m` under constant acceleration.
- [Six Flags: Tormenta Rampaging Run](https://www.sixflags.com/overtexas/attractions/tormenta-rampaging-run?pubDate=20260314) — `309 ft` (`94.18 m`) overall, `285 ft` (`86.87 m`) drop at `95 degrees`, `87 mph` (`140 km/h`), `218 ft` (`66.45 m`) Immelmann, `179 ft` (`54.56 m`) loop, and `4,199 ft` (`1,279.86 m`) track. At `1.5x`, the corresponding caps are `141.27 m`, `130.30 m`, `99.67 m`, and `81.84 m`. The official source does not state an inversion count, so it is not used to infer inversion frequency.

## Corkscrew reference

- [Arrow Development, US3889605A](https://patents.google.com/patent/US3889605A/en) defines a corkscrew as a cylindrical helix around a substantially horizontal axis, with smooth entry and exit transitions. Its helix pitch is measured from the plane perpendicular to that axis; the patent describes a range above `40 degrees` and approximately `70 degrees` at the upper end. V1 uses `60 degrees`.
- [I.E. Park, Roller Coaster catalogue](https://www.iepark.com/wp-content/uploads/2019/pdf/ROLLER-COASTER.pdf) lists the corkscrew axis at `9.6 m` and track/station elevation at `3.0 m`. Their difference gives a documented clean-room radius inference of `6.6 m`; it is not copied geometry.

With radius `R`, handedness `h` (`-1` or `+1`), incoming forward `F`, neutral up `U`, side `S = U x F`, and phase `theta`, V1 authors the centreline and inward rider frame from the same function:

```text
P(q)   = O + F L q + h S R sin(theta) + U R (1 - cos(theta))
Nin(q) = U cos(theta) - h S sin(theta)
```

At the bottom, `Nin = U`; at either side it points toward the helix axis; at the top it points downward. This ties roll handedness to centreline handedness and prevents an outward-banked corkscrew. Radius, axial advance, maximum excursion, and rail length all use the same `lambda` in the project's `1.0..1.5` range. The reference rail length is approximately `94.31 m`, and the axis-line excursion is `2R = 13.2 m`; their `1.5x` caps are approximately `141.46 m` and `19.8 m`.

[MACK Rides' Voltron Nevera release](https://mack.group/en/press-media/press-releases/2023-08-11/voltron-nevera-powered-by-rimac) is a macro-layout reminder that a corkscrew can be a complete final set-piece rather than a decorative roll that automatically feeds a helix. It is not used as a dimensional source.

## Open-source and academic references

### OpenFVD / FVD++

[OpenFVD](https://github.com/altlenny/openFVD) and its [archived revival](https://github.com/H27CK/openFVD) are conceptual references for force-vector design, heartline geometry, authored force and roll profiles, and speed/energy integration. They are licensed under GPL-3.0. No OpenFVD code is copied or linked here: importing it would introduce GPL distribution obligations and would be inappropriate without an explicit project-wide licensing decision.

### Clothoids / G2lib

[Bertolazzi and Frego's Clothoids library](https://github.com/ebertolazzi/Clothoids) provides C++ implementations of G1/G2 clothoid fitting and curvature-continuous planar transitions. Its [license](https://github.com/ebertolazzi/Clothoids/blob/master/license.txt) is BSD-2-Clause-style. Clothoid mathematics and the cited papers may guide a clean-room implementation. If library code is ever vendored, its copyright, conditions, and disclaimer must be retained in source and binary distribution materials.

Clothoids are useful transition primitives, not a complete speed- and gravity-aware 3D coaster generator. Hills, loops, and inversions still require force-aware geometry and validation.

### Rotation-minimizing frames

The preferred frame reference is Wang, Juttler, Zheng, and Liu, *Computation of Rotation Minimizing Frames*, ACM Transactions on Graphics 27(1), 2008: [author-hosted paper](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/12/Computation-of-rotation-minimizing-frames.pdf). A clean-room implementation of the paper's double-reflection method avoids Frenet-frame flips at inflections and near-zero curvature. Authored bank/roll is applied after constructing the rotation-minimizing frame.

### TinySpline

[TinySpline](https://github.com/msteinbeck/tinyspline) is MIT-licensed and includes spline evaluation, arc-length tools, derivatives, and rotation-minimizing frames. It is not currently imported. If used later, its MIT copyright and permission notice must be retained. General B-spline smoothing must not be applied after element generation because positional smoothness alone does not guarantee physical curvature continuity and may introduce overshoot, flat zones, or force spikes.

## Attribution policy

- Independently implemented equations and published algorithms are documented here with their primary references.
- No code may be copied from GPL projects unless the project deliberately accepts the resulting GPL obligations.
- Any permissively licensed code that is imported must retain its complete required notice and be recorded here.
- Manufacturer and park specifications are factual design anchors, not source-code dependencies.
