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

Or in the Godot client (`brew install --cask godot`, once):

```
cargo build -p vc-godot --release
godot --path godot
```

Press Generate — the solve runs in-engine, a minute or two — then it rides
itself. `C` toggles between the seat and a fly camera (right mouse looks,
WASD moves, Shift is fast). The ride is bit-identical to the CLI's: both call
`solve::solve_two_rounds`.

## What the generator produced

| | this ride | Falcon's Flight | margin |
|---|---|---|---|
| tallest hill, rider-felt rise | **247 m** | 163 m | 1.52× |
| tallest drop, rider-felt | **206 m** | 158 m | 1.30× |
| top speed | **386 km/h** | 250 km/h | 1.54× |
| average speed | **205 km/h** | ~71 km/h | 2.9× |
| peak positive g | **7.3** | ~5.9 (Shock Wave) | 1.24× |
| peak airtime g | **−2.5** | −2 typical | 1.25× |
| track length | 6,861 m | 4,250 m | 1.61× |
| duration | 120 s | ~215 s | — |

Every record target is beaten. Station closure came in at **18.7 m over 6.9 km
with 11.4° of heading error**. Three limits are still broken, all small; see
"what did not work".

## Why a record figure is not a target

A table of records cannot be demanded of one ride, because each record was set
at its own speed with its own felt g. For a force-specified element every length
scales as `v²/g₀` times a dimensionless shape factor, so **size, speed and
intensity determine one another** — pick any two and the third follows.

The trap that falls out of this: scaling an element up at a fixed speed grows
every radius with it and leaves the element *weaker* than the record it beats.
An earlier version of this ride was big because it was weak — 3.3 g inside a 7 g
envelope.

So the three are controlled by three different mechanisms, none over-specified:

- **geometry** — pinned per element as rider-felt rise or drop, at 1.25× the
  record's geometric figure
- **intensity** — authored into the force channels, with `g_scale` floored at
  1.0 so the solve may firm an element up but never soften it
- **speed** — an outcome of the drops and four propulsion sections

Not every record is chased. Overbanked turns, inversions and airtime *duration*
are left alone: a layout whose every element is maximal has no shape.

## Two demands per element

The load-bearing change this round. Each element has two free parameters that
matter and now carries two demands to match:

- **trim → the pitch it hands on.** Nearly always zero: give the track back the
  way you found it.
- **length → how big it is.** A rise, a drop, or a net turn.

Neither can be authored by eye, and the reason is `v²`. The pitch an element
sweeps is roughly `(n̄ − 1)·g₀·L / v²`, so a thousand metres at one g of
departure turns **69° at 90 m/s and 351° at 40 m/s** — the same authored element
is a gentle hill where the train is fast and a spiral where it is slow.

A seeder solves both with damped Newton steps, using the exact derivatives the
dual numbers already provide. Then: solve, re-seed, solve. Closure needs
kilometres of correction, and finding them moves the lengths far enough that the
pitches and sizes need re-establishing at the speeds the new layout actually
runs at.

This is what made the pins bind. The previous checkpoint asked the global solve
to discover the height *and* close the circuit from an arbitrary guess, and it
delivered 59 m against a pinned 150.

## Bugs this round, all found by disbelieving a number

- **A symmetric force profile cannot dive.** Its second half undoes its first,
  so the cliff dive finished pointing 82° *up*. Dives are now one-sided; the
  pull-out is the next element's job, as in a real layout.
- **Positive bank turns right, not left.** `frame.rs` documented the opposite.
  The seeder pushed a turnaround the wrong way until it spiralled through
  2,819°. Now verified by a test rather than asserted in a comment.
- **A dive that stops at 0.15 g steps the force at the seam** — unbounded jerk,
  177 g/s. Every channel now meets its neighbours at 1 g.
- **The trim was eating the intensity.** `level_trim()` tries to make every
  element altitude-neutral; for a 6.8 g pull-out it asked for −2.3 g and
  delivered 4.2. A valley *cannot* be altitude-neutral. Trim seeds are capped.
- **A stalled train explodes the geometry.** Curvature is force over speed
  squared, so a brake run that reaches a standstill spirals — and the solve,
  differentiating through it, finds a landscape full of those. Straights now
  have a free trim so they can level themselves, and the speed floor is high
  enough that an unhealthy ride degrades instead of exploding.
- **The cliff was too short.** A 198 m rider-felt drop plus its pull-out needs
  ~260 m of fall; 200 m of escarpment put the track 45 m underground.

## What did not work

**Three limits were reported broken**, all by small margins: jerk at 19.7 g/s
against 15, peak positive g at 7.29 against 7.0 over a 0.2 s window, and ground
clearance at 3.91 m against 4.0. Two corrections found on review, 2026-08-07:

- **The jerk did not trace to the brake run.** Measured from the exported ride,
  the 19.7 g/s peak sits on the ejector-hop (79.5 m/s, length solved to 177 m)
  with the pullout second at 18.6; the brake run is nowhere near. The mechanism
  is that channel transitions are authored as fractions of element length, so
  jerk scales as Δg·v over transition-fraction times length — and nothing
  couples length to jerk strongly enough to beat closure. The brake run *does*
  still stall against the speed floor; that is a separate wart, not the jerk.
- **The 19.7 was an instantaneous peak compared against a windowed limit.**
  F2291 defines onset rate as a straight-line slope across a ~0.1 s window on a
  5 Hz low-passed signal, never a per-step derivative (see `PACING.md` §1). A
  quintic profile's peak reads 1.875× its windowed slope, so 19.7 instantaneous
  is ≈10.5 g/s as the standard measures it — inside the 15 g/s proving limit.
  The analysis now measures jerk the way the limit is defined.

**The solve remains basin-sensitive**, and this round produced two more
data points for the table:

| change | closure gap |
|---|---|
| per-element pitch and size seeding | 419 m |
| free trim on straights, higher speed floor | **18.7 m** |
| brake run: free exit speed, longer bounds | 439 m |
| reverted | **18.7 m** |
| arc key widths allocated ∝ Δg crossed (2026-08-07) | 18.4 m but 51° heading |
| windowed jerk as the solver's check | 513 m |
| multiple shooting, 3 seams, defect weight ×5, wide boxes | defects never closed; forward ride ~1.2 km |
| dual jerk: design enforced, proving advisory | **18.7 m** restored |
| minimax split alone, old 14-element layout | 28.1 m, 21.4° — basin held, design jerk passed |
| FF-shaped 19-element roster + geometric grades + closer | ~1.3 km — seeder does not bind pins on grade/overbank/roll elements yet |

The brake-run change was a reasonable-looking tweak that made closure twenty
times worse, and it was reverted rather than tuned around.

**Multiple shooting was attempted 2026-08-07 and is wired but not enabled.**
The evaluator integrates from arbitrary seam states (`eval::evaluate_split`),
seams are seeded from a forward pass, and defect residuals exist — all
test-exercised. Enabled, the solve settles on stitched optima whose defects
sit near thirty residual units and never close, across defect weights, seam
boxes and 150-iteration budgets; the forward ride meanwhile loses the basin
entirely. Even a *passing* extra residual reshapes the path — adding the
proving-window jerk check as a solver penalty was alone enough to lose 18.7 m,
which is why it is advisory. Next hypotheses, untried: eliminate seam
variables by Gauss-Newton on the defect block (exploiting the arrow sparsity
this dense LM ignores), or a homotopy that starts shooting from the converged
single-shooting answer rather than from the seed.

A second lesson of the same shape: the arc-key reallocation (each swing's
width proportional to the g it crosses — the minimax split, cutting the
authored jerk peak from 19.7 to 14.2 g/s at fixed length) is the right
transition shape, verified by direct evaluation. It is not in the preset
because it moves every seeded trim and the solve then lands 51° of heading
error away. It waits on a solver that can follow it.

**Falcon's Flight's own camelback shows the nonlinearity.** Worked from its
published geometry, 69.4 m/s at the cliff valley climbing 163 m puts its crest
at ~40 m/s — a ~610 m radius at the bottom and ~206 m at the top. The hill
*tightens* as it climbs. No linear scale factor could have been written down.

## Decisions that need your ruling

**1. The envelope is a near-future one, and it is a position, not a reading.**
+7 g / −2.5 g against ASTM's +6 / −2, arguing that current limits are set by
restraint hardware rather than physiology. The jerk figure is now sourced
verbatim: Rohde p.40 gives 15 g/s as "the max. allowable value when proving the
design", with 5–10 g/s in the design phase. Roll rate has *no* standard at all —
Rohde §7.6.2, "rotational accelerations are not mentioned and not measured" — so
the 110 deg/s here sits above openFVD's own red band of 80, deliberately.

**2. The solve's objective is still "stay closest to the ride as described."**
A light residual pulls each parameter back towards its spec value. Provisional.

**3. Falcon's Flight is two-across in seven rows, not four.** The README says
four. Its headline 195 m is elevation change; structure height is 163 m and the
drop 158 m.

**4. Per-element speed and g conditions for the records are not published.**
Researched and confirmed absent — RCDB and manufacturer sheets give height,
speed and angle only, and no manufacturer publishes track radii. The conditions
in this file are therefore *derived* from published geometry with the simulator,
not sourced. Fan-forum estimates were deliberately not used.

## Deviations from the roadmap, deliberate

- **The viewer is HTML, not Godot.** The roadmap sanctions a stand-in.
  `brew install --cask godot` when you want the real thing.
- **One crate, `vc-ride`, not three.** `model`, `eval`, `solve` are modules.
- **Multibody is rigid-coupler.** Elastic couplers and snatch loads are not
  modelled.
- **Forces are on the heartline only**, so the buildability cusp check
  (`1 + h·κ ≤ 0`) is missing.
- **No pacing score.** Average speed is now a solve target, which is the part of
  pacing that could be defined without guessing.
