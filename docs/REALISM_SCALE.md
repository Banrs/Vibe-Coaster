# Realism scaling & element research — how to size and shape MINECOASTER's elements

Status: authoritative, alongside `SHAPES.md` (geometric contract) and `TERRAIN_CONTRACT.md`
(terrain rules). This doc covers the *other* half of V2: how big elements are, how fast they're
taken, how long they last, and what real-world engineering their shapes must match. Read this
before assigning any numeric target (radius, height, speed, duration, g-force) to an element.

**Read `opengl/COASTER_REWRITE.md`'s "Start here" section first if you haven't.** This doc
assumes you're implementing V2 primitives and need to know what number to plug into each one.

## Why this file exists (read this before trusting any number below)

A prior pass on this project got burned twice: it anchored top speed to Kingda Ka (a 2005
coaster, **demolished February 28, 2025** — do not use it as a live reference for anything), and
it once read an element's "height" as relative to local terrain instead of the element's own
raw vertical extent. Both mistakes came from *not verifying against current sources* and *not
stating which quantity a number referred to*. Every figure in this doc is either (a) sourced with
a citation and a confidence flag, or (b) explicitly marked as this project's own derived/estimated
target, never blended together silently. Do the same when you extend this doc: if you can't find
a real citation, say so and mark it as a design estimate — don't present a guess as a fact.

**"Height" and every other size figure below is the element's own raw dimension along its own
axis** (e.g., a drop's height is the vertical descent it produces, a loop's height is its own
vertical diameter) — **never** terrain-relative, never `(track_y_at_point - terrain_y_at_point)`.
Confirm this explicitly in code review if you see height/size logic that reads terrain height as
an input to sizing anything other than clearance validation.

## Core philosophy

MINECOASTER is **arcadey but grounded in real coaster engineering** — a voxel game (Minecraft-style
blocky world) with a modern shader-quality look (dynamic lighting, atmospheric fog/sky, PBR-ish
materials — think "shader Minecraft," not flat/vanilla Minecraft) layered over track and ride
physics that a real coaster engineer's reasoning would recognize, even though the scale and g-forces
exceed anything ASTM would permit. Every element is sized and paced from a **real, currently-verified
world-record (WR) anchor** for that element type, then scaled by the rules below — never invented
from scratch, never guessed from the element's name alone.

**The target is grander than Falcon's Flight**, the current fastest/tallest real coaster (see
below) — this game's default scale sits *above* today's tallest/fastest real ride, not at parity
with it.

**Note: this doc's scope is the track generator's element sizing/pacing.** The rendering/shader
layer (fog, sky, lighting — `render_fx.cpp`, `environment.cpp`, the GLSL shaders) is a **separate**
rewrite target to hit the "shader Minecraft" look, at a full-to-partial rewrite depending on the
subsystem. The recent split of `main.cpp` into `game_state.cpp`/`environment.cpp`/`voxel_render.cpp`/
etc. was a **mechanical reorganization only** — it preserves V1 rendering behavior byte-for-byte
and does **not** represent a finished or authoritative shader implementation. Don't treat those
files' current contents as a target to preserve; they're a starting point to rewrite from.

## Sizing rule: size is *derived* from entry speed, not an independent free parameter

This is the central mechanic, and it replaces the earlier "taper size by element-size-class"
idea floated earlier in this project's history (small elements get more headroom, big elements
capped lower) — **that idea is superseded.** The final rule is simpler and physics-driven:

1. At generation time, the element's **live entry speed** determines its size, by targeting a
   consistent **sustained-g feel** (see the g-force section below) — slower entries produce a
   smaller instance of that element, faster entries produce a larger one. Size is never rolled
   independently of speed.
2. The **built size** (whatever the primary WR dimension is for that element — radius for loops/
   turns/helix, height for drops/hills/top-hats) must land in **1.0x–1.5x of the element's real
   WR anchor**, with headroom for the implementer's judgment to go slightly higher when a specific
   element calls for it. Never below 1.0x — this game's grandest elements always meet or exceed
   the tallest/biggest real example, consistent with "grander than Falcon's Flight."
3. The **entry-speed multiplier** (relative to that element's real-world entry speed) ranges
   roughly **0.75x–1.5x**, and can go slightly higher case-by-case. This is the primary knob;
   size is derived from it, then clamped to the 1.0–1.5x WR size band in rule 2.

### The size-vs-speed exponent — and why it can't be the classic v²/g formula

V1 used (see `opengl/src/coaster_track.cpp`'s `recCapMul`/`invRAt`) a classic constant-g radius
formula: `r = v² / ((n−1)·g·mul)` — radius scales with the **square** of entry speed to hold a
*constant* g-force regardless of speed. **Do not reuse this relationship in V2.** Here's the
problem, worked through: transit time through a element scales roughly as `t ≈ (path length)/v`.
If radius (and therefore path length) scales as `v²`, transit time scales as `t ∝ v² / v = v` —
i.e., a 2x-faster element would take roughly **2x as long** to ride through under the classic
formula. That directly contradicts the target below (similar or *slightly shorter* transit time
at higher speed), and it also means g-force (`g = v²/r`) stays flat regardless of speed, which
contradicts "g-forces proportional to the speed/size increase" (g should feel *more* intense at
higher speed/size, not identical).

**Target instead: radius should scale closer to *linearly* with entry speed (`r ∝ v^a` with `a`
around 0.9–1.0, slightly under 1.0 to trim transit time a little rather than hold it exactly
flat).** Worked through: with `r ∝ v^a`, transit time `t ∝ r/v ∝ v^(a−1)` — at `a≈0.95`, transit
time shrinks slightly as speed rises (matches "similar, or ever so slightly less" run time). And
g-force `g = v²/r ∝ v^(2−a)` — at `a≈0.95`, g grows slightly *faster* than linearly with speed,
which matches "g-forces proportional to the speed/size increases" without the size actively racing
away into transit-time bloat. **This exponent is this project's own derivation, not a sourced
real-world constant** — no published source ties coaster radius to entry speed by a power law
(confirmed absent in the research below). Treat `a` as a tunable starting point (~0.9–1.0) to
verify empirically against the transit-time target once V2's audit/continuity harness exists, not
as a fixed law.

**Illustrative example the user gave (explicitly not literal, don't hardcode these numbers):** a
100 km/h real loop taking ~3s should map to a ~200 km/h game loop taking roughly ~2.25–2.5s, not
~6s (naive doubling) and not ~3s flat (naive "same size, just faster"). Use the derivation above,
not this specific example, to compute actual targets per element.

### The real physics of curve shape vs. g-force (peer-reviewed, use this for within-element curve design)

The `v^a` exponent above governs how an element's *overall* size scales with entry speed — a
coarse, whole-element parameter. Separately, real peer-reviewed physics answers the finer-grained
question of how the track's curve shape *within* an element should relate to g-force at each point,
and this project should use it rather than inventing curve shapes. Three papers, all peer-reviewed
and directly on-topic (not adjacent-field):

- **Müller, "Roller coasters without differential equations," *European Journal of Physics* 31
  (2010) 835.** Derives a general force formula for *any* track shape `y = f(x)`:
  `F_C = [2|f''(x)| / (1+f'(x)²)^1.5] · (E_tot − m·g·f(x)) + sign(f''(x))/√(1+f'(x)²) · m·g`.
  For a parabolic hill `y = −c·x²`, this reduces at the crest to `F_C(top) = 4c·E_tot − mg`. The
  key result: a hill shaped as the **exact free-fall parabola** for the car's crest speed
  (`c = g/(2v₀²)`) gives `F_C = 0` everywhere — true sustained 0g. **Shape the crest curve
  *tighter* than that matching parabola** (smaller radius of curvature than free-fall would trace)
  **to get negative g ("airtime")** — this is confirmed against real accelerometer data on a dive
  coaster's first drop by Pendrill & Eager (2020, below), who found measured negative g traces
  directly to "the shape of the track being a more narrow parabola than would correspond to an
  object leaving the top of the track in pure free fall."
- **Pendrill & Eager, "Velocity, acceleration, jerk, snap and vibration," *Physics Education* 55
  (2020) 065012.** Confirms the above against real ride telemetry; also the source for this
  project's jerk/transition-smoothness reasoning (see `SHAPES.md`).
- **Nordmark & Essén, "The comfortable roller coaster – on the shape of tracks with constant
  normal force," *European Journal of Physics* 31 (2010) 1307.** Solves the harder problem this
  project actually needs for zero-g stalls and any "hold a target g over an extended arc" element:
  what track shape gives a **constant-magnitude normal force over a whole arc**, not just an
  instant. Answer: the required curve is related to the **Kepler orbit problem** — trajectories in
  velocity space are conic sections (ellipse/parabola/hyperbola depending on the target g-to-gravity
  ratio), **not a simple polynomial of any fixed order**. The ordinary free-fall parabola is just
  the zero-g limiting case of this family. **Do not assume a zero-g stall's crest is a quartic** —
  no source (including this one) confirms that; if a closed-form curve is wanted for the stall's
  extended-hold arc, derive it from this paper's conic-section construction, or numerically match
  a spline to a constant-g target instead of assuming a fixed polynomial order.
- **Pendrill, "Rollercoaster loop shapes," *Physics Education* 40 (2005) 517.** Gives the working
  recipe for constant-g loop segments: `1/r = (1/h)(h₀/r₀ + (cosθ₀ − cosθ)/2)` relates local radius
  to height and track angle for a segment held at constant centripetal g — this is the real-world
  basis for "loops are composites of clothoid + constant-g arcs," not a single closed-form curve
  either.

Net guidance: **don't hand-pick a polynomial degree for any crest/arc shape.** Use Müller's general
force formula to evaluate any candidate curve's g-force profile directly, and Nordmark & Essén's
construction (or a numerically-fit spline against it) when a target is "hold constant g over an
arc" rather than "pass through one crest point." This is a stronger, more precise tool than the
degree-5 (`quinticC2`) crest formula V1 used for top hats (see `SHAPES.md`) — worth re-deriving
V1's crest shapes against these formulas rather than carrying the old polynomial forward unverified.

### Target speeds

- **Top speed**: ~375 km/h = 1.5x Falcon's Flight's 250 km/h (sourced below).
- **Average speed** (ride-cycle average, not top speed): ~225 km/h flat target — not a multiplier
  of anything, a direct design target.

### Process requirement: ask before locking in per-element targets

When you build the WR-anchor table (per element or per element family), **surface the researched
data to the user and ask what target size/multiplier they want for that element or family**
before hardcoding it — don't unilaterally pick a number within the 1.0–1.5x band and move on,
especially for elements where the research below found no solid real-world anchor (turn radius,
corkscrew roll rate — see gaps below). The user may want specific elements pushed toward the top
or bottom of the range for pacing/variety reasons that aren't derivable from research alone.

## g-force scaling

Real coasters publish sparse, inconsistent g-force *records* (see per-element notes below —
several elements have **no sourced peak/sustained-g figure at all**). Where a real figure exists,
target roughly proportional scaling with the size/speed multiplier applied (a 1.25x element should
feel roughly 1.25x-ish more intense, modulated by the `v^(2−a)` relationship above) — but don't
force a number where none exists; note it as a design estimate. Separately from the *target*
number, the *mechanism* for hitting any g target at a given point is not a gap — use Müller
(2010)'s general force formula above to compute exactly what g a candidate curve produces, rather
than tuning by feel. **Never manage g by braking** (carried forward from the prior REALISM.md's
hard rule, still correct) — g is a geometry output, not a speed input.

## Element occurrence & density

- Falcon's Flight and Formula Rossa — this project's two primary real-world anchors — both have
  **zero inversions**. This game should have **a few, not zero and not many** — noticeably fewer
  than a dedicated inversion coaster, but present, unlike its real anchors. Don't treat "zero
  inversions" as the target; the old REALISM.md's "2–4 inversions/lap" range is a reasonable
  starting point to re-validate against the new size/speed rules, not a fixed carry-over.
- Element density (elements per lap/minute) should be **similar to real coasters, adjusted slightly
  lower** to account for elements being physically bigger (bigger elements eat more track length
  and time per instance, so fewer fit in the same ride duration at similar pacing quality).
- Historical note requiring reconfirmation, not silent inheritance: a past decision (recorded in
  git history, `REALISM.md` as of commit `782e56d^`) removed banana roll, heartline roll, and
  overbanked turn (WINGOVER) from generation per a past "roll overload" complaint. Re-confirm with
  the user whether that still holds under the new V2 element roster rather than assuming it does —
  everything is being rewritten, so old exclusions aren't automatically still wanted.

## Per-element research

Every entry below is from live 2026 web research (not training-data recall) specifically to avoid
repeating the Kingda-Ka-class mistake. Confidence is stated per fact; where research found **no**
real data, that's stated explicitly as a gap, with a recommendation for how to proceed (derive
from physics, or ask the user) rather than inventing a number.

### Primary speed/launch anchors

**Falcon's Flight** (Six Flags Qiddiya City, Saudi Arabia; Intamin LSM launch; opened December 31,
2025 — current, not historical): top speed **250 km/h (155 mph)**, confirmed current record.
Height figures have a real, sourced ambiguity worth preserving rather than flattening: Intamin's
own marketing cites **195 m** as the ride's headline "height," while RCDB/Wikipedia describe
**163 m** as the structure height and 195 m as the total *elevation change* — the extra ~32 m comes
from the natural Tuwaiq escarpment the ride launches down into, not steel structure. Use **163 m**
for "structure height" and **195 m** for "total elevation drop" as two distinct quantities, not
interchangeably. The ride features an LSM climb to the cliff, an **outward-banked summit turn**
(confirmed by multiple sources, but **no numeric bank angle is published anywhere** — flag as a
gap if a specific angle is needed), then a near-vertical dive down the natural cliff face.
Sources: [Wikipedia](https://en.wikipedia.org/wiki/Falcons_Flight), [Six Flags Qiddiya City official](https://sixflagsqiddiyacity.com/en/explore/rides/falcons-flight), [Intamin project page](https://www.intamin.com/project/falcons-flight/).

**Formula Rossa** (Ferrari World Abu Dhabi; Intamin hydraulic-accumulator launch, not flywheel;
opened 2010, record re-verified January 2026): top speed **240 km/h (149.1 mph)** reached in
**4.9 s**. **Correction to a figure the old REALISM.md conflated**: the commonly-cited **4.8g is
the peak g-force found *anywhere* on the ride, not the launch g** — launch g is **1.7g**. Formula
Rossa reclaimed a narrower "fastest launch acceleration" sub-record in Jan 2026, but Falcon's
Flight remains the fastest coaster overall. Sources: [Wikipedia](https://en.wikipedia.org/wiki/Formula_Rossa), [Guinness World Records, Jan 2026](https://www.guinnessworldrecords.com/news/2026/4/formula-rossa-achieves-highest-ever-rollercoaster-launch-speed-to-extend-record-legacy).

### Vertical loop

Current record height/diameter ~52 m (multiple coasters tied; a larger claimed record —
Tormenta Rampaging Run's ~179 ft loop — is **unverified as actually opened**, flag as unconfirmed
if cited). Real loops are **not circular** — they're a **clothoid/teardrop shape** (this design
choice traces to Werner Stengel's 1976 work, the origin of the modern coaster loop), with radius
tightest at the top and wider at the bottom. This is a deliberate g-force-management shape: a
true circular loop would produce dangerously high g at the bottom (where speed is highest) to
match a survivable g at the top (where speed is lowest); varying the radius continuously keeps g
within a bounded range throughout. **Confidence: high** (physics-education literature, corroborated
across multiple engineering-adjacent sources). No sourced numeric transit-time-vs-height relationship
was found — derive one from the v^a scaling above, or measure empirically once implemented.

### Immelmann / dive loop / pretzel loop

These are geometrically distinct, half-loop-derived inversions. **Correction to an assumption in
this project's own history**: "pretzel loop" is specifically a **B&M flying-coaster element**
(seen on Tatsu), not an RMC element — don't conflate it with RMC's dive-loop-family shapes when
citing a real anchor. Immelmann = climb + half-loop + half-twist to exit inverted-then-upright
(named for the WWI aerial maneuver); dive loop = the reverse, entering inverted-ish and diving out.
No further dimensional/kinematic detail beyond what's cited for the vertical loop above was found
with strong sourcing in this pass — treat radius/transit-time targets for these as derived from
the loop's scaling relationship until a dedicated research pass finds better anchors.

### Corkscrew / barrel roll

**Genuine data gap, not a search failure**: real-world corkscrew **radius records and roll rate
(dθ/dt, degrees/second) are not published anywhere** — not by manufacturers, not by RCDB, not in
academic literature. The only figure surfaced was a weakly-sourced derived estimate of
**~97.5°/s average** for a *helix* (not a corkscrew specifically) on Goliath, treat as a rough
upper-bound reference only, not a corkscrew fact. **Recommendation: this is exactly the kind of
element to bring to the user directly** (per the "ask before locking in" rule above) rather than
inventing a number — propose a roll-rate range grounded in rider-comfort reasoning (see the
clothoid/transition section below for the general jerk-management principle) and confirm it.

### Helix

No solid real-world radius record was found. Rotation/duration reference: Goliath's helix is
cited (weakly) at ~585° total rotation, ~4.5g sustained, ~6s duration — treat these as directional,
not firmly sourced facts (this specific figure traces to the same weak derivation as the corkscrew
roll-rate estimate above, re-verify before hardcoding). No source describes whether real helix
bank angle is held constant or varied through the turn — assume constant-bank as the simpler,
defensible default absent contrary evidence, and flag this as an assumption in code comments if
you implement it.

### Turn (banked) / S-curve / overbanked turns

Strong, specific, well-sourced *angle* data exists for several real coasters' overbanked turns —
but **turn radius is a total gap**: no official or enthusiast source (including RCDB) publishes a
radius figure for any of the coasters below. Angle data:

| Coaster | Overbank angle(s) | Notes |
|---|---|---|
| Millennium Force | 122° (tallest of 3, 169 ft) | Cited as a world record *at 2000 opening*; unconfirmed whether still standing as of 2026 |
| Fury 325 | 91° ("horseshoe turn", 157 ft) | |
| Iron Rattler | 110°, 95°, 98°, 93° (four distinct turns) | |
| Maverick | 92° | |
| Twisted Colossus | 90° ("High Five", both parallel tracks) | Exactly 90°, not technically overbanked |
| Goliath (SFGA) | unspecified angle, 125 ft | |

**Important cautionary data point**: **Intimidator 305 / Pantherian**'s original 270° turn
following its 300 ft first drop produced **sustained g over 5g**, causing rider grey-outs/
blackouts at its 2010 opening. The park's fix was **not** to add brakes or cut speed permanently —
it was to **physically reprofile the turn with a wider radius** in the off-season, after which
trims were removed and full speed restored. This is a direct, real precedent for "manage g via
geometry, not braking" (the hard rule carried from the prior REALISM.md) — and a cautionary
example of what happens when turn radius doesn't scale with speed. Source: [Pantherian — Wikipedia](https://en.wikipedia.org/wiki/Pantherian).

Standard banking-angle physics (adjacent field, well-established, not coaster-specific but
directly applicable): `tan(θ) = v² / (r·g)` relates bank angle, radius, and speed for a
zero-lateral-force banked turn — use this as the baseline relationship, then apply the size/speed
scaling rules above to pick `r` from target entry speed.

### Transition curves — how banking/pitch actually evolves through an element

This directly answers the "how does pitch/roll evolve" requirement, and is **confirmed by a real
coaster-specific engineering patent**, not just adjacent-field theory: **US Patent 4,693,183A**
(Pötzsch, 1987) explicitly describes coaster track using **clothoid (Euler spiral) transitions** —
radius of curvature inversely proportional to arc length (`r = A/s`) — to smoothly reduce radius
from a straight section into a curved one, explicitly to keep the vehicle "free of transverse
force" during the transition. This is corroborated by peer-reviewed sources: Eager et al.,
*Physics Education* (2020) confirms modern coasters use "clothoids and space curves" specifically
to bound **jerk** (rate of change of acceleration) during transitions, contrasting with older
coasters' abrupt constant-radius-to-constant-radius joins. A generalizable formal constraint (from
an adjacent railway-transition-curve patent, US7,027,966B2): a well-behaved transition requires
the **second derivative of bank/roll angle to be zero at both ends of the transition** — i.e., no
sudden kink in how fast the roll rate itself is changing, not just the roll angle. **No official
manufacturer (B&M/Intamin/RMC) publishes a numeric jerk limit or roll-rate-of-change standard** —
this is a real gap; SHAPES.md's own C2-continuity requirement (position/tangent/curvature agree
at joins) is this project's answer to the same problem and should be treated as the operative
standard, not a further real-world number search.

### Camelback / airtime hill

| Coaster | Height | Notes |
|---|---|---|
| El Toro | 112/100/82 ft hills, 176 ft first drop @ 76° | |
| Steel Vengeance | 116 ft outward-banked hill (205 ft overall height) | **27.2s total airtime across the whole ride** — current record, but this is a whole-ride aggregate, not per-hill |
| Goliath (SFGA) | 165 ft structure + 15 ft below-grade tunnel = **180 ft total drop** | Clean, well-documented example of drop exceeding structure height via an excavated section — a good real-world precedent for this project's own "raw element height, not terrain-relative" convention, since here the *extra* height is a deliberate design choice (dig a trench), not a measurement bug |
| Millennium Force | 182 ft parabolic hill, crosses a lagoon | Reference datum (water surface vs ground) is ambiguous in every source checked |
| Iron Gwazi | 206 ft, 91° beyond-vertical drop | |

**No source gives per-hill transit time or a reliable numeric negative-g figure** for any specific
hill on any of these — g-force claims found (e.g. El Toro "-2g") trace to a single uncited
Wikipedia line or enthusiast forum post, not an instrumented reading. Treat hill airtime-g targets
as this project's own design estimate, informed by the qualitative "floater" (gentle, sustained)
vs "ejector" (violent, sharp) distinction, not a sourced number. **The shape mechanism is not a
gap, though** — real, peer-reviewed physics (Müller 2010, confirmed against measured accelerometer
data by Pendrill & Eager 2020, both cited above) establishes that a crest gives **negative g
("airtime") exactly when it's curved tighter than the free-fall parabola matching the car's crest
speed** — a hill shaped as the exact free-fall parabola gives true 0g, not negative g. Use this
directly: pick a target negative-g value, compute the free-fall-matching parabola for the entry
speed, then curve the crest tighter by whatever margin the target g requires (via Müller's
`F_C(top) = 4c·E_tot − mg` relation). "Floater" (gentle) vs "ejector" (sharp) is a matter of degree
on this same continuum — floater = crest curved only slightly tighter than free-fall, ejector =
noticeably tighter — not a fundamentally different construction.

### Top hat

Kingda Ka (once the tallest top-hat tower at 456 ft) is **confirmed demolished February 28,
2025** — cite it only as a historical/dead reference, never as a current anchor (this is the exact
mistake this project needs to stop making). Top Thrill 2's tower uses a 90° vertical ascent with
a twist near the crest, not a simple constant-angle face. Falcon's Flight's climb (see above) is
this project's primary current top-hat/summit anchor at 163 m structure height.

### Zero-g stall

**Correction to a premise this project's history may have implicitly carried**: a zero-g stall is
**fully an inversion** (rider goes upside-down), not a non-inverting airtime element — confirmed
across RCDB, Wikipedia's roller-coaster-element taxonomy, and industry glossaries. The real
distinction from a "zero-g roll": a **roll** twists a continuous 360° through a hill crest
(B&M signature, e.g. Alpengeist, Montu) with no pause — weightlessness is a brief passing moment.
A **stall** (RMC signature) twists 180° to fully inverted, **pauses/holds** inverted through a
straight-or-gently-curved section, then twists the remaining 180° back upright — the pause is what
extends "hang time." Sourced hang-time figures are sparse and low-confidence: Pantheon ~2s
(a reviewer's estimate, not instrumented), VelociCoaster and ArieForce One both have marketing
claims ("100 ft long," "largest in America") with **no measured seconds figure**. **No instrumented
peak-g figure exists anywhere for either a zero-g roll or a zero-g stall** on any real coaster —
do not cite a specific g number as fact for this element. **On shape**: a common assumption that a
stall's crest/hold arc is a quartic (degree-4 polynomial) curve is **not confirmed by any source**
found in this research, including a targeted search for RMC engineering patents. The rigorous
peer-reviewed answer for "hold a near-constant g over an extended arc" (Nordmark & Essén 2010,
cited above) is that the correct curve family is derived from the **Kepler orbit problem** —
conic-section trajectories in velocity space, not a fixed-degree polynomial. If V1's stall/hold
logic uses a quartic, treat that as an unverified inherited assumption to re-derive against
Nordmark & Essén rather than carry forward as-is.

### Cliff dive

This project's existing natural-escarpment cliff-dive concept (see `SHAPES.md`) is directly modeled
on Falcon's Flight's real mechanic (LSM climb to a natural cliff edge, outward-banked summit turn,
near-vertical dive down the cliff face) — see the Falcon's Flight entry above for the sourced
detail. No other real coaster does this at comparable scale, so Falcon's Flight is the sole
real-world anchor for this element; everything else here is this project's own design extrapolation
(already governed by `TERRAIN_CONTRACT.md`'s escarpment-scan rules).

## Summary of genuine research gaps (don't fabricate numbers for these)

- Corkscrew/barrel-roll radius and roll rate (dθ/dt) — not published anywhere.
- Turn/S-curve radius for any named real coaster — angle data exists, radius does not.
- Per-hill airtime transit time (seconds) — only whole-ride totals are published.
- Numeric jerk limits or roll-rate-of-change standards from any manufacturer.
- Instrumented peak-g for zero-g rolls/stalls, corkscrews, or helices.
- Helix and corkscrew dimensional records generally (weak, low-confidence derived figures only).

For all of these: either derive a target from the physics relationships in this doc (banking
formula, C2-continuity/clothoid transition requirement, the size-vs-speed exponent), or bring it
to the user as an open design choice — don't present an invented number as if it were sourced.

## File-organization convention (applies to this rewrite generally)

Keep new files at a level a single LLM context can hold and navigate without excessive
searching — group related concerns into one file rather than fragmenting into many tiny files.
The V2 module split in `opengl/COASTER_REWRITE.md` (7 files under `opengl/src/track/`) and the
recent `main.cpp` host-code split (7 files: `game_state.cpp`, `environment.cpp`,
`voxel_render.cpp`, `spline.cpp`, `coaster_car.cpp`, `presentation.cpp`, `audit_diagnostics.cpp`)
are both calibrated to this — don't split further without a concrete reason (a file that's
genuinely become too large to hold in context, not just "this could be two files").
