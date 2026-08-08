# Falcon's Flight reference decisions

> **RETIRED-CHECKPOINT DOCUMENT (Step 0, 2026-08-08): kept only for the rationale behind the
> load-verification toolkit that survives the rewrite. Its route targets, source interpretation,
> and its envelope table (+7.0/−2.5 Gz · ±4.0 Gy · ±7.0 Gx · 15 g/s · 110°/s) are the OLD
> checkpoint's — do not confuse with the rewrite envelope (+8.0/−3.0 Gz · ±4.7 Gy ·
> +8.0/−6.0 Gx · ~25 g/s · ~120°/s, see `docs/PLAN.md` and `docs/RESEARCH.md` §5).**

Falcon Flightline borrows Falcon's Flight's macro sequence and visual language, then scales the
experience into a frontier concept. It does not claim survey-grade coordinates, an exact replica,
or a buildable engineering design.

## Source interpretation

Intamin describes a 40 km/h LSM lift, a 55 m twisted first drop, lower-course hills, a 150 km/h
powered cliff climb, an outward-banked rim turn, summit turns and holding brake, a cliff dive into a
tunnel, a third launch to 250 km/h, a 165 m camelback, and elongated high-speed return track. The
published ride has zero inversions.

- [Intamin project description](https://www.intamin.com/project/falcons-flight/)
- [RCDB 21315](https://rcdb.com/21315.htm)
- [Six Flags Qiddiya City ride page](https://www.sixflagsqiddiyacity.com/en/rides/falcons-flight)
- [Supplied CGI and third-person geometry reference](https://www.youtube.com/watch?v=NFVNGgwZk3c)

“Twisted drop” does not mean a barrel roll or corkscrew. The supplied video shows the first lift
handing into a banked, heading-changing side-dive that loses height and then unwinds into the first
valley. The model keeps it non-inverting and separate from the later main cliff dive. Likewise, the
rim moment is an outward bank—not an overbank or helix.

## Frontier translation

The checkpoint targets 5.4–5.6 km, a 319–321 km/h peak, 158–165 seconds including the cliff hold,
and at least 120 km/h averaged over the full elapsed ride. Signature geometry is approximately
1.25× the applicable record: about a 198 m main drop and a 206–210 m camelback. Smaller elements follow the scale of their real counterpart at the
corresponding speed; holding force constant requires radius to grow with speed squared.

Three LSM zones retain the reference pacing: station/lift, powered cliff climb, and downhill tunnel
launch. The grade-authored holding brake physically decelerates into a low-speed cliff crawl and
release; it and the final brakes are infrastructure, not thrill geometry.

## Mixed geometry model

Most of the route is force-vector designed. Authored proper vertical and lateral loads and bank,
together with the physically integrated shared train speed, produce the curvature vector:

```text
curvature = (proper acceleration + gravity across the track) / speed²
```

That applies to drops, hills, pullouts, and high-speed banked turns. Station, lift, LSM, and brake
sections instead author a smooth grade while propulsion or braking changes the energy state. The
model therefore follows the physical distinction between rider-load-led track and infrastructure
whose grade or speed duty is primary.

The energy state uses mean tangential gravity across all seven rows, not a point-mass front car.
Each row's load then uses that shared train speed with its own local tangent, curvature, and rider
frame.

Quintic interpolation makes force continuous through its second derivative, yielding C4 position
geometry. Septic grade transitions flatten the first three endpoint derivatives, while bank is
gated smoothly without changing the centerline continuity. The station return is an explicit
degree-nine curve with matched endpoint derivatives through fourth order; it is validated as a
short route section, not concealed as a global correction.

## Human-load verification

The project uses this concept envelope:

| Quantity | Frontier limit |
| --- | ---: |
| Vertical proper acceleration | +7.0 g / −2.5 g |
| Lateral proper acceleration | ±4.0 g |
| Longitudinal proper acceleration | ±7.0 g |
| Resultant onset rate | 15 g/s |
| Roll rate | 110°/s |

Validation resamples loads at 100 Hz, applies a four-pole 5 Hz Butterworth filter, checks every
duration window against per-axis limits, and checks the instantaneous combined-axis ellipse. The route must approach
the vertical, combined-axis, onset, and roll-rate frontiers intentionally while remaining within
every limit; merely staying well below the design capability is a failure.

These checks are informed by ASTM F2291-style measurement practice but are not a certification
claim. Restraints, seats, suspension, train coupler dynamics, structures, fatigue, evacuation, and
terrain geotechnics remain out of scope. The Godot checkpoint provides seven rider rows and a live
human-viewable POV so geometry, pacing, clearance, and row-dependent loads can be inspected.
