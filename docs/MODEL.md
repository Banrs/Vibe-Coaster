# The ride model — review checkpoint

> Roadmap steps 3–6 and 8, as a vertical slice through one preset. Read this
> before the code.

## Ride it

```
cargo run --release -p vc-ride --bin generate
open out/ride.html
```

Pick a row from the dropdown — row 8 is the back, which is where the snap is.
`chase cam` pulls the camera out behind the train.

## What the generator produced

| | this ride | Falcon's Flight |
|---|---|---|
| track length | **5,596 m** | 4,250 m |
| top speed | **321 km/h** | 250 km/h |
| duration | 245 s | ~215 s |
| running gear | maglev | urethane wheels |
| envelope | +7 / −2.5 g | +6 / −2 g |

Station closure came in at **1.8 m over 5.6 km, with 0.6° of heading error**,
and every comfort and clearance limit is met. One constraint is not: the
pinned apex. See "what did not work".

## How an element works

Every element is the same object. Force Vector Design says a ride is specified,
at each point, by the vertical g the rider feels, the lateral g they feel, and
the bank angle — exactly three numbers, which is exactly the three components
of the track frame's rotation rate. Two would leave the roll undetermined; four
would over-specify it. Geometry is then solved from those three:

```
kappa = (n·g₀·up + l·g₀·right + g − (g·t)t) / v²
```

A top hat and an airtime hill differ only in the numbers in those three curves.
Nothing in the crate branches on an element's name.

Four scalars per element are free for the solve:

- **length** — buys height and heading
- **g_scale** — multiplies the *departure* from level, so scaling never bends
  straight track
- **trim** — a constant added to the vertical force, which is what decides
  whether an element climbs, holds or descends
- **roll_scale** — turns only; a bank multiplier on a hill is a Jacobian column
  that does nothing

Plus an optional **exit speed** wherever infrastructure drives the train, and an
optional **pinned apex**, which is the human's one geometric demand.

## Decisions that need your ruling

**1. The envelope is now a near-future one, and it is fiction.** `frontier_limits()`
allows +7 g / −2.5 g against ASTM's +6 / −2, on the argument that current limits
are set by restraint hardware rather than physiology: a lap bar cannot hold a
slumping rider, and a passive seat cannot support a head at 7 g. Active
restraint and a reclined contoured seat change those premises. The reference
points are aviation and centrifuge, not amusement rides. `astm_limits()` is kept
alongside it for step 10 validation. **Is +7 / −2.5 the number you want, and is
the reasoning the one you want on record?**

**2. The solve's objective is "stay closest to the ride as described."** Closure
plus pins is about a dozen equations against 25 free parameters, so the feasible
set is a manifold and something must pick a point on it. A light residual pulls
each parameter back towards its spec value. That keeps the spec a steering wheel.
The alternative is maximising pacing — which would make the pacing score
load-bearing at step 6 rather than a step-9 readout. **Provisional; your call.**

**3. Falcon's Flight is two-across in seven rows, not four.** The README says
four-across. Its headline "195 m" is elevation change, not structure height —
that is 163 m, with a 158 m drop. The preset uses the researched figures.

**4. Force envelope numbers come from a reproduction, not the standard.** Both
EN 13814 and ASTM F2291 are paywalled and were not read. The tables come from
Rohde's VDV paper, whose author sits on the ASTM F24 g-force task group and
which reprints F2291's own figures; ramp breakpoints were read off graphs, so
±0.5 s. Two known gaps make the tables *permissive*: the standards measure at
the seat through a 5 Hz low-pass where this reads an idealised point, and
combined-axis loading is judged by an ellipsoid criterion that per-axis checks
cannot express.

## What did not work

**The pinned apex is missed, badly.** 59 m against a pinned 150 m. Everything
else converges; this does not. It is the one place the generator fails to
deliver what the human asked for, which makes it the most important open item —
the pin is the primary input.

The cause is not obviously a bug. The element has the length and trim authority
to climb 150 m on paper, but the solve settles elsewhere. Two suspects: the
apex residual is fighting the closure residuals through the same parameters,
and the solve is basin-sensitive.

**The solve is basin-sensitive, and residual weights behave like
hyperparameters.** Three tuning attempts made it *worse*, each time by a lot:

| change | closure gap | cost |
|---|---|---|
| baseline | 13 m | 3.6e3 |
| widen trim and roll bounds | 339 m | — |
| raise apex weight 1 → 4 | 367 m | 1.4e6 |
| add backtracking line search | **1.8 m** | 4.5e3 |

Only the line search helped, and it helped enormously — the solve had been
stalling the moment any parameter touched a bound. But "widen the bounds and
get a worse answer" is exactly the failure mode the architecture doc warned
about, and it means the current result is not robust. Multiple shooting is
still the recommended structural fix.

**The forces are conservative.** Peak vertical g came out at 3.3 against a 7 g
envelope. The ride breaks records on height, speed and length but not on
intensity — the solver softens `g_scale` to buy closure. If the point is to
push human limits, the templates need to demand more and the intensity needs
protecting from being traded away.

## Deviations from the roadmap, deliberate

- **The viewer is HTML, not Godot.** Godot is not installed and could not be
  reviewed while you were asleep; the roadmap already sanctions "a throwaway
  centreline viewer" as the cheap fix. It renders real solved geometry with
  real per-row forces. Godot remains the plan for step 7 — `brew install --cask
  godot` when you want it.
- **One crate, `vc-ride`, not three.** `model`, `eval`, `solve` are modules.
  Splitting later is mechanical; three crates now was ceremony.
- **Multibody is rigid-coupler.** Cars sit at fixed arclength offsets and the
  longitudinal acceleration is the mass-weighted mean of gravity over every
  row. That is the real effect — the lead cars pull the back over a crest — but
  elastic couplers, and therefore snatch loads, are not modelled.
- **Forces are on the heartline only.** Rail offset is carried as a vehicle
  parameter but not yet used, so the buildability cusp check
  (`1 + h·κ ≤ 0`) is missing.
- **No pacing score.** It is the least-defined thing in the architecture and
  building it uninstructed seemed worse than leaving the gap.

## Things the research changed

- **Curvature divides by v².** A ride specified purely by force is singular at
  a standstill, so the station has a real dispatch speed and drive tyres that
  hold it.
- **Gravity must be subtracted in the instantaneous frame.** Treating force and
  curvature as a pointwise algebraic map gets the bank silently wrong
  everywhere.
- **Infrastructure force has to ramp.** Switching propulsion on at an element
  seam is a step in force, and a step in force is unbounded jerk. That artefact
  alone was dominating the solve's cost and starving closure.
- **A constant trim steps at element seams too** — same problem, same fix. The
  trim is windowed to zero at both ends.
