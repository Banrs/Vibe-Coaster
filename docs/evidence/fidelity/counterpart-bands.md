# Per-element counterpart bands — design grounding

**Created 2026-08-15.** Derived entirely from the committed telemetry documents
`docs/TELEMETRY.md` and `docs/TELEMETRY-I305.md`. No network access, no new measurement.

## What this is

A per-element-class lookup from the generator's twenty material roles
(`RideProgram.MATERIAL_ROLE_IDS`) to the measured real-ride element that grounds it, with the
measured values, the stretched design target, and the caveats that travel with each number.

## What this is not

This is **design grounding data**, not evidence promotion. It does **not** promote any source in
`godot/fidelity_references.gd` from `corroborative` / `observation-only` / `review-pending` to
`executable`, it creates **no catalog `targets` and no `selectors`**, and it is not wired into
`fidelity.gd`, `verify.gd`, or `smoke.gd`. Nothing here is a gate, and a generated ride that misses
one of these bands is not thereby failing. The catalog `2026-08-10.evidence-baseline.2` still has
empty `selectors`, `observations` and `targets`; that is unchanged by this file.

## Derivation rule (repo rule, root `CLAUDE.md`, final paragraph)

> Fidelity targets = measured counterpart × per-axis envelope stretch on **values**, measured hold
> **durations kept**.

| Axis | Multiplier | Applies to |
|---|---|---|
| Gz+ (normal, into seat) | **×1.333** | positive vertical peaks and held plateau values |
| Gz− (normal, negative / airtime) | **×1.5** | negative vertical minima and held negative values |
| Gy (lateral) | **×1.567** | lateral peaks, either sign |
| Gx− (longitudinal, braking / retard) | **×1.71** | deceleration magnitudes |
| Gx+ (longitudinal, accelerating) | **— none —** | **no Gx+ multiplier exists; none may be inferred** |

Additional rules applied throughout:

- **Durations are copied verbatim.** A measured `≥3 g for 2.70 s` becomes a target held at the
  stretched value for **2.70 s**, unchanged.
- **Thresholds are reported as measured.** Where telemetry states a hold against a threshold
  (`≥2 g`, `≤ −0.5 g`), the threshold is quoted at its measured value. A stretched threshold
  (e.g. 3 g → 4.00 g at ×1.333) is a convenience for reading the target, never a measured number,
  and is labelled as such where given.
- **Geometry is never scaled.** Heights, radii, lengths and bank angles here are context only.
- **1 g baselines are not stretched.** A level ~1.00 g cruise is the gravity baseline, not a load
  excursion; multiplying it would be a category error.
- **Cross-recording values.** Where TELEMETRY gives two recordings, both are reported; the target
  band is taken from the pair, and the note says which quantity the two recordings actually agree
  on (usually duration, not peak).
- Every stretched value below is inside the ~2041 envelope (+8.0/−3.0 Gz · ±4.7 Gy · +8.0/−6.0 Gx).
  The envelope is the ceiling, not the target.

## Standing source caveats

- **Falcon's Flight, RFDB 4804** is **flagged unreliable by RideForcesDB** (TELEMETRY.md lines
  67–70), is the **only** recording of that ride (line 71), and is a **wrist-worn Apple Watch,
  Row 7 L seat** (line 61). The raw ±5–10 g extremes cluster at t ≈ 99.3–100.3 s and are shock /
  limb artefacts (lines 74–76). Any value drawn from t ≈ 99–100 s carries that flag.
- **Source 2** (CoasterTalk Insta360 camera-IMU, front + back runs) independently measures the same
  ride and **disagrees materially on longitudinal** — peak +0.87/+0.91 g against 4804's +2.53 g
  (lines 912–916, 931–943). Where the two disagree, both are reported and the longitudinal target
  is taken from Source 2.
- **Tormenta 6369 / 6383** carry **no gravity/angle channel**, so inversion state is inferred from
  RCDB element order matched to trace shape (lines 373–376). 6369 is a pocket-carried phone the
  author flags for sliding; 6383 is an iPhone, Row 2 Seat 8. Element **durations and magnitudes**
  are comparable across them; absolute `t` is not.
- **Intimidator 305** values are read off a video overlay to **±0.15 g / ±0.15 s**, and the
  g-data and imagery come from different sources, so element↔time attribution is the uploader's
  sync (TELEMETRY-I305.md lines 22–32). Element labels are good-confidence, not certified.
- Row/seat position alone moves the peak by up to **0.7 g** on the same element (TELEMETRY.md
  line 395). Peaks are seat-dependent; durations are much less so.

---

# 1. `station-launch` — air/hydraulic entry launch (~4 g class)

| Field | Value |
|---|---|
| Counterpart (propulsion) | Do-Dodonpa, S&S compressed-air launch — RFDB 4721 (TELEMETRY.md lines 742–751) |
| Counterpart (layout) | Falcon's Flight LSM launch 1, t 2.0–6.0 s (TELEMETRY.md line 104) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gx+ launch (Do-Dodonpa) | **+3.17 g** peak, `G ≥0.6 g` sustained t=2.0→3.9 (line 745) | **none** | **+3.17 g** (unstretched) | **1.90 s** | ≥0.6 g |
| Gx+ launch, cross-recording | **+3.17 … +3.77 g** across all 5 recordings (lines 746–747, 793) | none | **+3.17 … +3.77 g** | — | — |
| Gx+ launch (Falcon opener) | +0.55 … **+0.96 g** peak @ t≈2.x (line 104) | none | +0.96 g | — | — |
| Gz+ pull-up out of launch | **+1.98 g** @ t≈5 (line 104) | ×1.333 | **+2.64 g** | — | — |
| Gz coast over opener crest | 0.82–1.04, mean **0.93 g**; Gx +0.10…+0.55 sustained (line 105) | none (≈1 g cruise) | 0.93 g | **~7.5 s** | — |

**Notes.** The ~4 g entry launch is the one place the repo deliberately exceeds every measured
launch; Do-Dodonpa at +3.17…+3.77 g is the highest launch longitudinal in the whole database and
is the honest ceiling of measurement — the design's ~4 g is a near-future extrapolation past it,
not a stretched measurement. **No Gx+ multiplier is defined and none is inferred here.**
Do-Dodonpa also shows what that launch class does *not* produce: essentially no airtime (flojector
and ejector 0.00 s in all five recordings, line 748–749). Falcon's own opener launch is a much
milder +0.96 g and is corroborated by Source 2's narration "peak acceleration of 0.9 G" (line 900);
it grounds the *shape* (short kick then a sustained boost into a climb, line 901), not the
magnitude. The opener coast (line 105) reads V≈cos21°, G≈sin21° ⇒ a near-constant-speed 20° grade,
which is the unpowered-coast signature the design calls for.

---

# 2. `opener-twisted-drop` — twisted non-inverting side-drop

| Field | Value |
|---|---|
| Counterpart | Falcon's Flight, **first drop — twisted side-drop**, t 16.30–17.38 s (TELEMETRY.md line 107), pullout t 17.88–19.84 (line 108) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gz− drop | min **−0.99 g** | ×1.5 | **−1.49 g** | **1.10 s** below 0 g; **0.80 s** at threshold | ≤ −0.5 g |
| Gy peak (one side) | **+1.64 g** @ 16.94–17.16 | ×1.567 | **+2.57 g** | — | — |
| Gy reversal (other side) | **−1.35 g** @ 17.36–17.54 | ×1.567 | **−2.12 g** | full reversal in **0.50 s** | — |
| Gz+ pullout peak | **+3.35 g** (range 2.00–3.35) | ×1.333 | **+4.47 g** | **1.98 s** ≥2 g; **0.34 s** ≥3 g | 2 g / 3 g measured |
| Gx during drop | −0.76 … +1.09 | ×1.71 on the negative | −1.30 g (retard side) | — | — |

**Notes.** This is the **strongest airtime and strongest lateral of the whole Falcon recording**
(line 107) and the **longest ejector-class hold: 0.80 s at ≤ −0.5 g** (line 168) — the reference
for the design's twisted side-drop. Angle sweeps 30°→84°, i.e. the drop is taken nearly on the side,
which is exactly the lateral reversal signature. **Caveat:** Source 2 measures Falcon's whole-ride
lateral envelope at only **−0.79 … +0.66 g** (lines 895, 919, 938) — less than half the 4804
figure. Both sources agree the ride is *laterally quiet everywhere else*; the disagreement is
concentrated on this element. Treat +1.64/−1.35 as an upper reading from a wrist device that may
be smearing energy between axes (line 44), and the 0.50 s reversal **time** as the more robust
quantity. Minimum vertical is the one thing the two sources agree on closely (−0.96 to −1.15 g,
line 941).

---

# 3. `opener-teardrop` — overbanked teardrop arc

| Field | Value |
|---|---|
| Counterpart | Falcon's Flight, **near-90° banked wall turn**, t 113.0–119.0 s (TELEMETRY.md line 130) |
| Class exemplar | Intimidator 305 sustained banked turns (TELEMETRY-I305.md lines 46, 51, 55, 117–122) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gz+ held (Falcon) | 2.10–**2.95 g** | ×1.333 | **+3.93 g** peak | **2.58 s** @116.12–118.68 | ≥2 g |
| Gy (Falcon) | −0.80 … **+0.97 g** | ×1.567 | **−1.25 / +1.52 g** | — | — |
| Gx (Falcon) | −1.04 … +0.89 | ×1.71 on negative | −1.78 g | — | — |
| Gz+ held (I305 turn #3) | **+4.80 g** peak, never below 3.7 g inside it | ×1.333 | **+6.40 g** | **4.10 s** ≥3.5 g | ≥3.5 g |
| Gz+ held (I305 turns #6/#8/#12) | 4.30 / 4.30 / **4.25 g** | ×1.333 | 5.73 / 5.73 / **5.67 g** | **1.4 / 3.1 / 2.4 s** ≥3.5 g | ≥3.5 g |

**Notes.** Falcon's wall turn is the **steepest bank of that ride** (89–90° at t 115–116.5) and is
the direct geometric analogue for an overbanked arc, but it is a *low*-g overbank at 2.1–2.95 g.
I305 is the opposite: the sustained banked turn is that ride's signature and holds **3.5–4.8 g for
1.4–4.1 s**, accounting for 11 of the 12.3 s it spends above 3.5 g (lines 117–122). The design's
teardrop sits between them; both bands are given rather than averaged. I305 turn #3 is noted in the
source as the outlier — **the load rises through the whole 4.1 s hold rather than decaying**
(line 120), which is a shape target, not a magnitude one. I305 precision is ±0.15 g.

---

# 4. `opener-release` — release hill out of the teardrop

| Field | Value |
|---|---|
| Counterpart | Falcon's Flight airtime hills 1/3/4, t 20.68–21.72 / 30.10–31.38 / 39.88–40.38 (TELEMETRY.md lines 109, 113, 117) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gz− hill 4 (deepest) | min **−0.73 g** | ×1.5 | **−1.10 g** | **0.52 s** below 0 g; **0.22 s** at threshold | ≤ −0.5 g |
| Gz− hill 1 | min **−0.58 g** | ×1.5 | **−0.87 g** | **1.06 s** below 0 g | 0 g |
| Gz− hill 3 | min **−0.57 g** | ×1.5 | **−0.86 g** | **1.30 s** below 0 g | 0 g |
| Gz+ following valley (valley 6) | 2.01–**2.84 g** | ×1.333 | **+3.79 g** | **1.36 s** ≥2 g | ≥2 g |

**Notes.** Amplitude and duration trade against each other in the measured set: the deepest hill
(−0.73 g) is the *shortest* below zero (0.52 s), and the longest (1.30 s) is the shallowest
(−0.57 g). Hills 3 and 4 are taken at **75–86°** and **66–88°** bank while unloaded (lines 113, 117)
— steeply banked airtime, which is the release-hill character the design wants, not a flat pop.
Falcon's whole-ride ejector time is only **0.38 s** (line 92), so this ride class is
floater/flojector-dominant; the ejector references live under `act-one-airtime` below.

---

# 5. `act-one-immelmann` — giant Immelmann, 100–110 m

| Field | Value |
|---|---|
| Counterpart | Tormenta: Rampaging Run, **Immelmann #1 (218 ft)** — 6383 t 17.60–21.16, 6369 t 18.04–21.58 (TELEMETRY.md line 397) |
| Secondary | Tormenta **Immelmann #2** (line 403) |

| Axis | Measured (6383 / 6369) | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gz+ peak, Immelmann #1 | **+4.34 / +4.43 g** | ×1.333 | **+5.79 … +5.91 g** | — | — |
| Gz+ held ≥3 g, Immelmann #1 | 3.00 g floor | ×1.333 | **≥4.00 g** (stretched threshold, derived) | **2.70 / 2.52 s** | ≥3 g measured |
| Gz+ held ≥2 g, Immelmann #1 | 2.00 g floor | ×1.333 | ≥2.67 g (derived) | **3.58 / 3.56 s** | ≥2 g measured |
| Gz+ peak, Immelmann #2 | **+4.14 / +4.22 g** | ×1.333 | **+5.52 … +5.63 g** | **1.24 / 1.14 s** ≥3 g; **2.24 / 1.90 s** ≥2 g | ≥3 g / ≥2 g |
| Gz entry (climb to it) | 0.47–1.43 over ~4 s (line 397, preceding row) | — | context only | — | — |

**Notes.** Immelmann #1 is called out in the source as the **strongest cross-recording agreement of
the whole ride** — peak within 0.09 g (4.34 vs 4.43) and the ≥2 g duration within 0.02 s
(3.58 vs 3.56 s). The target band is therefore taken from the pair directly rather than from a
single seat. The ≥3 g hold spread (2.70 vs 2.52 s) is the seat-position effect. Both recordings lack
an angle channel, so inversion state is inferred from RCDB order (lines 373–376); the element
*identity* is high-confidence because RCDB names the sequence authoritatively (lines 356–358).
Tormenta reaches these numbers at 140 km/h on a 94 m dive coaster — the design's Immelmann is a
100–110 m element taken at the 42–50 m/s entry the repo discovered by measurement, so the g band
transfers but the geometry does not.

---

# 6. `act-one-cutback`

| Field | Value |
|---|---|
| Counterpart | Tormenta, **Cutback** — 6383 t 54.50–56.24, 6369 t 56.34–58.02 (TELEMETRY.md line 404) |

| Axis | Measured (6383 / 6369) | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gz+ peak | **+4.20 / +3.86 g** | ×1.333 | **+5.15 … +5.60 g** | — | — |
| Gz+ held ≥3 g | 3.00 g floor | ×1.333 | ≥4.00 g (derived) | **0.96 / 0.98 s** | ≥3 g measured |
| Gz+ held ≥2 g | 2.00 g floor | ×1.333 | ≥2.67 g (derived) | **1.76 / 1.70 s** | ≥2 g measured |

**Notes.** The **agreement here is in the durations, not the peak**: ≥3 g holds match to 0.02 s
(0.96 vs 0.98) and ≥2 g to 0.06 s, while the peaks differ by 0.34 g. The duration figures are
therefore the load-bearing numbers and the peak is given as a band. This is the **shortest of
Tormenta's big elements** (line 404) — a cutback is a brief high-g snap, and the design must not
let it grow into an Immelmann-length hold. Element assignment is by RCDB order (Immelmann before
Cutback), noted in the source as an assignment rather than a direct observation (line 403).
The repo's own measured constraint — cutback entry pitch ≤ ~22° — is a geometry finding and is not
stretched.

---

# 7. `act-one-loop` — helical-leg loop

| Field | Value |
|---|---|
| Counterpart | Tormenta, **Loop (179 ft)** — 6383 t 22.94–27.58, 6369 t 23.50–28.52 (TELEMETRY.md line 398) |
| Contrast exemplar | Full Throttle, world's tallest loop, RFDB 5070 (TELEMETRY.md lines 679–681, 695–696) |

| Axis | Measured (6383 / 6369) | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gz+ entry lobe peak | **+3.84 / +3.86 g** | ×1.333 | **+5.12 … +5.15 g** | **1.22 s** ≥3 g (entry lobe) | ≥3 g |
| Gz+ **apex dip** (local minimum) | **≈+2.50 g**, 6383 t=25 min **+2.52 g** | ×1.333 | **+3.33 … +3.36 g** | — | apex is the local *minimum* |
| Gz+ exit lobe peak | **+3.74 g** | ×1.333 | **+4.99 g** | **1.26 s** ≥3 g (exit lobe) | ≥3 g |
| Gz+ held ≥2 g, whole loop | 2.00 g floor | ×1.333 | ≥2.67 g (derived) | **4.66 / 5.04 s** | ≥2 g measured |
| *Contrast:* Full Throttle apex | **−0.40 … −0.67 g**, inverted | ×1.5 | −0.60 … **−1.01 g** | **2.62 s** below 0 g; 1.22 s ≤ −0.5 g | ≤ −0.5 g |

**Notes.** The **twin-lobe signature is the point**: entry 3.84 g → apex dip ≈2.5 g → exit 3.74 g,
with the **loop apex as a local minimum that is never unloaded** (line 398). Peak agreement between
the two recordings is 0.02 g — the tightest pair in the whole document. Full Throttle is included
as the *opposite* case, and only as contrast: it is a launched loop whose apex genuinely unloads to
−0.67 g for 2.62 s, with a confirmed angle channel reaching 166.9° (line 670). The design's loop is
a **helical lateral with the sign reversed at the top** (a planar loop self-intersects at these
speeds — a repo measurement finding), so it is closer to Tormenta's loaded-apex family than to Full
Throttle's; both bands are recorded so the choice stays explicit rather than assumed.

---

# 8. `act-one-airtime` — airtime hills

| Field | Value |
|---|---|
| Counterpart | Intimidator 305 ejector hills #1/#2/#3 (TELEMETRY-I305.md lines 48, 50, 56, 124–129) |
| Secondary | Falcon's Flight airtime hills + sustained float (TELEMETRY.md lines 109–119, esp. 115) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gz− I305 hill #1 (deepest) | min **−1.15 g** | ×1.5 | **−1.73 g** | **2.40 s** below 0 g; ~1.5 s below −0.7 g | 0 g / −0.7 g |
| Gz− I305 hill #2 | min **−0.90 g** | ×1.5 | **−1.35 g** | **1.33 s** below 0 g | 0 g |
| Gz− I305 hill #3 (longest float) | min **−0.75 g** | ×1.5 | **−1.13 g** | **2.30 s** below 0 g; **2.60 s** below 0.5 g | 0 g / 0.5 g |
| Gz− Falcon deepest hill | min **−0.73 g** | ×1.5 | **−1.10 g** | 0.52 s below 0; 0.22 s ≤ −0.5 g | ≤ −0.5 g |
| Gz Falcon sustained float | 0.05–0.44, mean ≈**0.05 g** @ t=35 | none (near-0, not negative) | ≈0.05 g | **~1.0 s** continuously ≤0.22 g | ≤0.22 g |
| Gz+ Falcon valleys between hills | 2.00–**2.68 g** typical, up to 2.84 | ×1.333 | **+3.57 … +3.79 g** | **1.30–1.42 s** ≥2 g | ≥2 g |

**Notes.** Two different airtime characters are on record and the design should choose knowingly.
I305 is the **ejector** reference: six genuine sub-zero hills, four of which hold below −0.35 g for
over a second, and the first two hold below −0.7 g for ~1.5 s each (lines 124–129) — sustained
negative, not a spike. Falcon is the **floater** reference: 23.00 s total airtime but only 0.38 s of
ejector across the whole ride (line 92). The I305 caveat matters here: values are read from a video
overlay at ±0.15 g, and the ±0.2 g visible noise means the quoted minima are local means of the
noise band, not spikes (TELEMETRY-I305.md lines 22–30). The transition rate is a separate finding:
I305's sharpest unloading is **+3.8 → −0.9 g in 0.80 s (5.9 g/s)** and nothing in that recording
exceeds ~7 g/s (lines 132–141) — well under the design's 25 g/s onset ceiling, so onset here is a
character reference, not a limit.

---

# 9. `act-one-wave` — wave turn — **EVIDENCE GAP**

**No measured counterpart exists in the committed telemetry.** No source in `docs/TELEMETRY.md` or
`docs/TELEMETRY-I305.md` records a wave turn — a laterally-banked twin-peak airtime element — as an
identified element. The candidates all fail for a stated reason:

- Falcon's "upper-cliff turns/hills", t 56.0–77.0 (line 122), is an unresolved multi-element block
  in the source's own assignment, not a named wave turn; its lateral peak −1.13 g is held only
  2×0.22 s and cannot be attributed to a single element.
- Tormenta's post-loop turn (line 399) carries the ride's lateral maximum (+1.09 / +1.15 g) but is
  a plain banked turn of ~2 s at 1.18–1.97 g, with no airtime component at all (that ride has
  **zero ejector airtime in both recordings**, line 387).
- I305's "final low twisted turn" (TELEMETRY-I305.md line 61) has no lateral channel — the overlay
  carries a single signed vertical trace only (lines 12–14).

**No number is assigned.** For bounding only, and explicitly *not* as a target: the highest
attributable lateral anywhere in the primary sources is Falcon's first-drop +1.64 g (line 107,
itself contested by Source 2) and Tormenta's +1.15 g (line 399). Closing this gap needs a recording
of an actual wave turn with a lateral channel.

---

# 10. `climb-lsm2` — LSM booster at the cliff base + decelerating coast

| Field | Value |
|---|---|
| Counterpart (boost) | Falcon's Flight **LSM launch 2**, t 44.5–48.5 s (TELEMETRY.md line 120) |
| Counterpart (climb) | Falcon's Flight **escarpment climb**, t 48.5–56.0 s (TELEMETRY.md line 121) |
| Class band | LSM launch longitudinal across the database (TELEMETRY.md line 816); Pantheon multi-LSM (lines 735–737) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gx+ boost peak (4804) | +0.53 … **+1.78 g** @48.0–48.4 | **none** | **+1.78 g** (unstretched) | **0.30 s + 0.40 s** at threshold | ≥0.8 g |
| Gx+ boost, LSM class band | **+0.75 … +1.57 g** across all DB LSM rides | none | **+0.75 … +1.57 g** | — | — |
| Gx+ boost, Pantheon LSM | every boost **0.9–1.3 g** | none | +0.9 … +1.3 g | **0.3–1.5 s** each | ≥0.6 g |
| Gz+ pull-up into the climb | **+2.96 g** @47.64–48.02 | ×1.333 | **+3.95 g** | — | — |
| Gz on the climb | 0.57–**2.13 g**, sustained ~30° grade | ×1.333 on the peak | **+2.84 g** | **7.5 s** climb | — |
| Gx on the climb | −0.34 … +0.96 | ×1.71 on negative | −0.58 g | — | — |

**Notes.** **No Gx+ multiplier — the boost target is the measured value.** The 4804 figure of
+1.78 g is *not* inside the t≈99–100 s artefact burst, so it is less suspect than the tunnel launch
below, but Source 2 still puts the whole ride's longitudinal maximum at **+0.87/+0.91 g** (lines
912–916), which would make even +1.78 g high. The class band (0.75–1.57 g for LSM, against
1.37–2.73 g hydraulic and 3.17–3.77 g compressed air, line 816) is the more defensible design
reference. Pantheon is the closest structural analogue to a three-booster layout and shows every
boost is **0.3–1.5 s long** (line 737) — the design's "shorter than Falcon's booster sections"
constraint has direct measured support. The escarpment climb reference confirms a booster may run
into a sustained grade rather than staying flat (line 121), which the design relies on.

---

# 11. `clifftop-slow-crest` — crest crawl / hold

| Field | Value |
|---|---|
| Counterpart | Falcon's Flight **clifftop crest crawl / slow beat**, t 78.0–90.3 s (TELEMETRY.md line 123; summarised line 169) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gz level hold | **0.98–1.00 g** | **none** (gravity baseline) | **0.98–1.00 g** | **≈12 s** (12+ s at 0.98–1.00) | — |
| Gy | **≈0.00 g** (±0.15) | ×1.567 on the bound | ≤ ±0.24 g | full 12 s | — |
| Gx− deceleration | 0 → **−0.95 g** @82–83; −0.28…−0.43 @88–90 | ×1.71 | **−1.62 g**; −0.48…−0.74 g | — | — |
| Angle | **1–15°** | — | geometry, not scaled | — | — |

**Notes.** This is the single most directly transferable row in the document: the design's "one
deliberate slow beat" has an exact measured counterpart in the same ride's clifftop section, and
the source names it as **the ride's one slow section** and the **longest ~1 g level hold (≈12 s)**
of the whole recording (lines 123, 169). The 1.00 g value is explicitly **not** stretched — it is
the gravity baseline of a level, laterally dead, gently decelerating crawl, and multiplying it would
invent a load that is not there. Only the deceleration is a real Gx− excursion and it is the only
stretched number here. Note the contrast with I305, which has **no dwell at 1 g anywhere between
lift crest and brakes** (TELEMETRY-I305.md lines 95–99) — the slow beat is a Falcon trait, not a
universal one, and is a deliberate design choice.

---

# 12. `clifftop-outward-rim` — outward-banked rim turn — **EVIDENCE GAP**

**No measured counterpart exists.** Not one element in either telemetry document is identified as
**outward-banked** (banked away from the turn centre, so lateral load pushes the rider outward).
Every banked element on record is inward-banked, and the sign convention itself blocks inference:
lateral positive is "one side (recording-dependent)" (TELEMETRY.md line 14), so an outward bank
cannot be distinguished from an inward one in any of these traces without a gravity/angle channel
plus a known turn direction — a combination no source here provides.

Additionally, Falcon's clifftop section, which is where the design places this element, is measured
as **laterally dead: ≈0.00 g ±0.15 over the full 12 s** (line 123). There is no rim turn in the
measured trace at all; the design's compact clifftop suspense element is an invention of the
material story, correctly held to reference scale only.

**No number is assigned.** Closing this gap needs a recording of an outward-banked turn with an
angle channel and a documented turn direction.

---

# 13. `outward-dive` — 90° cliff dive

| Field | Value |
|---|---|
| Counterpart (same ride) | Falcon's Flight **cliff-dive entry / free-fall** t 90.5–92.7, **pullout** t 93.0–96.0 (TELEMETRY.md lines 124–125); Source 2 direct dive readings (lines 882–883, 923–925) |
| Class exemplar (90°) | Yukon Striker, B&M 90° dive (TELEMETRY.md lines 764–773) |
| Class exemplar (95°) | Tormenta 95° drop + pullout (TELEMETRY.md lines 394–395) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gz− dive entry (4804) | min **−0.52 g** | ×1.5 | **−0.78 g** | **1.14 s** below 0 g @91.56–92.68 | 0 g |
| Combined vector minimum | **0.043 g** @91.36 — near-total free-fall | — | not a per-axis target | instantaneous | — |
| Gz on the face (Source 2) | **+0.17 g** front / **−0.05 g** back | −0.05 ×1.5 = −0.08 | ≈0 g — an **unloading** event | — | — |
| Gx− on the face (Source 2, front) | **−0.82 g** nose-down | ×1.71 | **−1.40 g** | — | — |
| Gz− Yukon Striker 90° drop | min **−0.24 g** only | ×1.5 | **−0.36 g** | **1.10 s** below 0 g | 0 g |
| Gz− Tormenta 95° drop | min **−0.52 / −0.66 g** | ×1.5 | **−0.78 … −0.99 g** | **1.80 / 1.88 s** below 0 g; 6369 ≤−0.5 g for 0.18+0.22 s | 0 g / ≤ −0.5 g |
| Gz+ pullout (4804) | 2.04–**2.99 g** | ×1.333 | **+3.99 g** | **1.58 s** ≥2 g @93.74–95.30 | ≥2 g |
| Gz+ pullout (Yukon Striker) | peak **+3.91 g** | ×1.333 | **+5.21 g** | **3.00 s** ≥3 g (t 12.3–15.3) | ≥3 g |
| Gz+ pullout (Tormenta) | **+4.33 / +5.02 g** | ×1.333 | **+5.77 … +6.69 g** | **2.80 / 2.82 s** ≥3 g; **3.74 / 3.62 s** ≥2 g; 0.36/0.50 s ≥4 g | ≥3 g / ≥2 g / ≥4 g |
| Gx− holding brake before drop (Yukon) | **−0.60 … −0.81 g** | ×1.71 | **−1.03 … −1.39 g** | **4.10 s** (t 4.8–8.8) | — |

**Notes.** The most important measured finding here is negative: **a 90° dive drop produces no
meaningful airtime.** Yukon Striker unloads only to −0.24 g (line 770), Source 2 measures Falcon's
cliff dive at ≈0 g and states explicitly that "it is an unloading event, not a negative-g event"
(line 925), and even Tormenta's beyond-vertical 95° drop bottoms at −0.52/−0.66 g. The design's
"monotonic, no lip pause" dive is consistent with all three. The **violence is in the pullout, not
the drop**: Tormenta's ≥3 g hold of 2.80/2.82 s agrees across recordings to 0.02 s while its peak
differs by 0.7 g on seat position (line 395) — so the *duration* is the transferable number.
Yukon Striker's 4.1 s holding brake at −0.60…−0.81 g is included as the measured precedent for a
controlled crest hold before a vertical face; the design has no holding brake (no mid-course brake
is permitted), so it is context only. The 4804 dive rows are outside the t≈99–100 s artefact burst.

---

# 14. `tunnel-lsm3` — tunnel LSM booster (the record launch)

| Field | Value |
|---|---|
| Counterpart | Falcon's Flight **LSM launch 3 (tunnel)**, t 96.5–99.7 s (TELEMETRY.md line 126) |
| Corroboration | Source 2 longitudinal (lines 912–916); LSM class band (line 816); Pantheon boosts (lines 735–737) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gx+ boost (4804) ⚠ | **+1.02 … +2.53 g** in 4 bursts | **none** | ⚠ **not adopted — suspect** | **0.32 / 0.32 / 0.30 / 0.36 s** | — |
| Gx+ boost (Source 2, corroborated) | **+0.87 / +0.91 g** whole-ride maximum | none | **+0.87 … +0.91 g** | — | — |
| Gx+ boost, LSM class band | **+0.75 … +1.57 g** | none | **+0.75 … +1.57 g** | 0.3–1.5 s per boost (Pantheon) | ≥0.6 g |
| Gz+ through the boost | 0.47–**1.67 g** rising | ×1.333 | **+2.23 g** | — | — |

**Notes.** **This is the worst-supported magnitude in the whole table and it is deliberately not
adopted.** The 4804 tunnel-launch peak of +2.53 g sits at t=99.52, i.e. **inside the ±5–10 g raw
shock burst at t ≈ 99.3–100.3 s**, and the source flags it as suspect on its own terms (lines 76,
79, 126). Source 2 independently measures the same ride's longitudinal maximum at +0.87/+0.91 g,
corroborated by on-screen narration "I measured a peak acceleration of 0.9 G" (lines 900, 912–916),
and the document's own conclusion is: *"Treat ~0.9 g as the ride's real launch longitudinal
magnitude"* (line 916). The design target therefore comes from the class band, not from 4804.
**No Gx+ multiplier is defined and none is inferred.** The **burst structure** — four bursts of
0.30–0.36 s — is the one thing worth carrying from 4804, because burst timing is a shape and is not
distorted by an amplitude artefact in the way the magnitude is; it matches Pantheon's measured
0.3–1.5 s boost lengths.

---

# 15. `camelback` — record camelback (~250 m above its valley)

| Field | Value |
|---|---|
| Counterpart | Falcon's Flight **record camelback**: pull-up t 99.02–102.32, crest t 102.90–109.66, exit pullout t 110.24–112.54 (TELEMETRY.md lines 127–129); summarised lines 166–167 |
| Corroboration | Source 2 camelback apex and narration (lines 886, 903–904) |
| Class exemplars | Top Thrill 2 top-hat (lines 626–629); Red Force top-hat (lines 650–654) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gz+ pull-up peak ⚠ | **+3.894 g** @99.82 (range 2.14–3.89) | ×1.333 | **+5.19 g** | **3.32 s** ≥2 g; **1.10 s** ≥3 g @101.12–102.20 | ≥2 g / ≥3 g |
| Gz+ pull-up (Source 2) | **+3.23 g** back / **+3.65 g** front | ×1.333 | **+4.31 … +4.87 g** | — | — |
| Gz− crest, first pass | min **−0.87 g** | ×1.5 | **−1.31 g** | **1.60 s** below 0 g | 0 g |
| Gz− crest, second pass | min **−0.61 g** | ×1.5 | **−0.92 g** | **2.78 s** below 0 g @106.90–109.66 | 0 g |
| Gz crest, continuous unloaded | ≤ **0.2 g** essentially continuous | none (near-0) | ≤0.2 g | **≈6.8 s** (102.9→109.7) | ≤0.2 g |
| Gz crest (Source 2 apex) | **−0.13 g**; narration "about 0.5 G at the top" | ×1.5 | −0.20 g | — | — |
| Gy pull-up ⚠ | −1.16 … +1.03 g | ×1.567 | **−1.82 / +1.61 g** | — | — |
| Gx pull-up ⚠ | −1.70 … +1.81 g | ×1.71 on negative | **−2.91 g** | — | — |
| Gz+ exit pullout | 2.16–**3.44 g** | ×1.333 | **+4.59 g** | **2.32 s** ≥2 g; 0.38+0.22+0.18+0.26 s ≥3 g | ≥2 g / ≥3 g |
| *Class:* TT2 top-hat crest | min **−1.08 g** | ×1.5 | −1.62 g | **2.94 s** below 0 g; 1.42 s ≤ −0.5 g | 0 g / ≤ −0.5 g |
| *Class:* Red Force descent airtime | min **−0.88 g** | ×1.5 | −1.32 g | **1.82 s** below 0 g; 1.04 s ≤ −0.5 g | 0 g / ≤ −0.5 g |

**Notes.** ⚠ **The pull-up rows sit inside the t ≈ 99–100 s artefact burst** and every value marked
⚠ above carries that flag (lines 74–79). The vertical peak is the least affected of them — Source 2
measures +3.23/+3.65 g for the same ride, i.e. the same order — but the lateral and longitudinal
pull-up figures are the ones the document identifies as smeared by the wrist shock, and the
document's onset maxima (V +14.5, L −14.6, G +22.1/−26.0 g/s) all fall inside this burst and are to
be read as **upper bounds, not clean measurements** (lines 171–176). The **crest is the strong
part**: 2.78 s is the **longest negative-g hold of the whole ride** (line 167) and ≈6.8 s of
continuous ≤0.2 g is the longest unloaded stretch (line 128), and none of that is inside the burst.
Source 2 corroborates the crest independently (−0.13 g at the apex, line 886) and reports greyout at
the camelback base (line 904), consistent with a genuine high-g pull-up. The two giant-top-hat class
exemplars are included because they are the only other measured elements of comparable scale.

---

# 16. `return-turn-a` — first overbanked return turn

| Field | Value |
|---|---|
| Counterpart | Falcon's Flight **return-run turn A**, t 124.16–127.02 s (TELEMETRY.md line 132) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gz+ peak | 2.02–**3.14 g** | ×1.333 | **+4.19 g** | **2.88 s** ≥2 g; **0.10 s** ≥3 g | ≥2 g / ≥3 g |
| Gy | −0.56 … **+0.99 g** | ×1.567 | **−0.88 / +1.55 g** | — | — |
| Gx− | **−0.91 g** … +0.52 | ×1.71 | **−1.56 g** | — | — |
| Angle | 15–64° | — | geometry, not scaled | — | — |

**Notes.** Clean row: outside the artefact burst, on the same ride, in the same structural position
(a banked turn on the unpowered return run). The 2.88 s ≥2 g hold is the **second-longest ≥2 g run
in the recording** (line 163). Note the shape — only 0.10 s above 3 g against 2.88 s above 2 g —
i.e. a long flat-topped ~2.5 g plateau with a brief tip, not a spike. That is the return-turn
character to reproduce; the peak alone would misrepresent it. Single wrist recording, Row 7 L seat;
Source 2's independent readings on the return run (+2.68 g at video t=315, +0.08 g unloaded at
t=320, lines 887–888) are consistent in magnitude.

---

# 17. `return-height-a` — first return height / airtime beat

| Field | Value |
|---|---|
| Counterpart | Falcon's Flight **return-run float**, t 119.0–123.0 s (TELEMETRY.md line 131) |
| Class corroboration | I305 late-course ejector hills #15/#17/#19 (TELEMETRY-I305.md lines 58, 60, 62) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gz float (Falcon) | **0.22–0.79 g** | none (positive, near-0 floater) | 0.22–0.79 g | **~4 s** float band | ≤0.79 g |
| Gy (Falcon) | −0.46 … +0.43 | ×1.567 | −0.72 / +0.67 g | — | — |
| Gx (Falcon) | −0.61 … +0.55 | ×1.71 on negative | −1.04 g | — | — |
| Gz− I305 hill #15 | min **−0.50 g** | ×1.5 | **−0.75 g** | **1.25 s** below 0 g | 0 g |
| Gz− I305 hill #19 (last pop) | min **−0.45 g** | ×1.5 | **−0.68 g** | **0.78 s** below 0 g | 0 g |

**Notes.** **Thin evidence, carried as a caveat rather than a gap.** Falcon's return-run float never
goes negative at all (0.22–0.79 g) — it is a floater beat, not an airtime hill, so it grounds the
*placement and duration* of a late-course height but not a negative-g target. The I305 rows supply
the only measured late-course airtime of the right character, and that source notes the pattern
directly: the late hills are **shallow-and-short, −0.4 to −0.5 g for 0.4–1.3 s**
(TELEMETRY-I305.md lines 124–129) — deliberately less than the mid-course hills. A design that makes
the return heights *stronger* than the mid-course airtime would contradict both sources.

---

# 18. `return-turn-b` — second overbanked return turn

| Field | Value |
|---|---|
| Counterpart | Falcon's Flight **long sustained banked turn**, t 132.0–139.4 s (TELEMETRY.md line 134) |
| Secondary | Falcon's Flight **return-run turn B** t 128.0–131.0 (line 133); **turn C** t 142.36–144.34 (line 136) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gz+ held (long turn) | 1.69–**2.46 g** | ×1.333 | **+3.28 g** | **2.76 s** ≥2 g @136.64–139.38; ~8 s continuously 1.7–2.5 g | ≥2 g |
| Gx− (long turn) | **−1.52 g** … +0.21 | ×1.71 | **−2.60 g** | — | — |
| Gy (long turn) | −0.63 … +0.35 | ×1.567 | −0.99 / +0.55 g | — | — |
| Angle (long turn) | 16–**89°** @135 | — | geometry, not scaled | — | — |
| Gz+ (turn B) | 1.54–**2.39 g** | ×1.333 | **+3.19 g** | — | — |
| Gy (turn B) | **−0.95** … +0.48 | ×1.567 | **−1.49 / +0.75 g** | — | — |
| Gz+ (turn C) | 2.03–**2.31 g** | ×1.333 | **+3.08 g** | **1.74 s** ≥2 g | ≥2 g |

**Notes.** The signature of the second return turn is **length, not amplitude**: ~8 s continuously
between 1.7 and 2.5 g, reaching 89° of bank at its middle (line 134), with the ≥2 g portion being
2.76 s of that — the **third-longest ≥2 g run of the ride** (line 163). Three separate return turns
are given because the design places two turns plus a terminal sequence and the measured ride shows
this whole family living in a consistent 2.3–2.5 g band. The −1.52 g longitudinal inside the long
turn is a real retard (the ride is bleeding energy on the return), not a brake application; the
brake references are in row 20.

---

# 19. `return-height-b` — second return height / airtime beat

| Field | Value |
|---|---|
| Counterpart | Falcon's Flight **float**, t 140.0–142.0 s (TELEMETRY.md line 135) |
| Class corroboration | I305 ejector hill #17 (TELEMETRY-I305.md line 60) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gz− (Falcon) | min **−0.16 g** (range −0.16…+1.12) | ×1.5 | **−0.24 g** | ~2 s float window | 0 g |
| Gy (Falcon) | −0.37 … +0.23 | ×1.567 | −0.58 / +0.36 g | — | — |
| Gx (Falcon) | −0.60 … +0.53 | ×1.71 on negative | −1.03 g | — | — |
| Gz− I305 hill #17 | min **−0.40 g** | ×1.5 | **−0.60 g** | **0.38 s** below 0 g | 0 g |

**Notes.** Same caveat as `return-height-a`, and weaker: Falcon's second return float barely crosses
zero (−0.16 g) and is the shallowest airtime beat on the record. Both measured sources agree the
*last* airtime beat before the brakes is the smallest one of the ride — I305's final pop is −0.45 g
for 0.78 s and its hill #17 is −0.40 g for 0.38 s. A design that lands the last height beat between
−0.2 and −0.6 g for well under a second is inside both sources; anything deeper is unsupported by
measurement, though not by itself wrong.

---

# 20. `terminal-capture-brakes` — brakes and station capture

| Field | Value |
|---|---|
| Counterpart (bite) | Falcon's Flight **trim / brake bite**, t 145.58–145.88 (TELEMETRY.md line 137) |
| Counterpart (run) | Falcon's Flight **final brake run**, t 151.6–156.0 (line 139); station t 156.0–158.0 (line 140) |
| Cross-recording | Tormenta brake bite (line 405) and brake run (line 406) |
| Corroboration | Source 2 maximum deceleration (line 917) |

| Axis | Measured | Stretch | Target | Hold | Threshold |
|---|---|---|---|---|---|
| Gx− bite (4804) | **−1.89 g** (ride's longitudinal minimum) | ×1.71 | **−3.23 g** | **0.32 s** at threshold | ≤ −1 g |
| Gx− bite (Source 2) | **−1.34 g** front / **−0.93 g** back | ×1.71 | **−1.59 … −2.29 g** | — | — |
| Gx− bite (Tormenta, cross-rec) | **−0.94 / −1.06 g** | ×1.71 | **−1.61 … −1.81 g** | **0.82 / 0.80 s** | — |
| Gx− final brake run (4804) | **−0.25 … −1.06 g** sustained | ×1.71 | **−0.43 … −1.81 g** | **4.40 s** (151.6–156.0) | — |
| Gz− on the brake run (4804) | 0.90–**1.09 g** (≈1.00) | none (gravity baseline) | ≈1.00 g | 4.40 s | — |
| Gx− brake run (Tormenta) | **−0.3 … −0.7 g** repeating | ×1.71 | **−0.51 … −1.20 g** | **~22 s** | — |
| Gz station (4804) | 0.64–1.01 g | none | ≈1.00 g | 2 s | — |

**Notes.** **The cross-recording Tormenta pair is the trustworthy number here** — −0.94 vs −1.06 g
with hold durations agreeing to 0.02 s (0.82 vs 0.80 s), from two independent devices in two
different seats. 4804's −1.89 g is the ride's longitudinal minimum and, unlike the tunnel launch, is
**not** inside the t≈99–100 s artefact burst, so it is defensible as a real value — but Source 2 puts
the same ride's maximum deceleration at −1.34/−0.93 g (line 917), so the −1.89 g stretched target of
−3.23 g should be read as an upper bound rather than a design centre. A brake bite of ≈−1.6 to
−1.8 g stretched, held under a second, then a sustained run at −0.4 to −1.2 g, is supported by both
rides. The station rows confirm the obvious: **capture is a 1 g level state**, not stretched.

---

## Coverage summary

**18 of 20 element classes have a measured counterpart.**

**2 evidence gaps, no number assigned:**

| Element class | Reason |
|---|---|
| `act-one-wave` | No wave turn (laterally-banked twin-peak airtime element) is identified in any committed source; the nearest candidates are an unresolved multi-element block, a plain banked turn with no airtime, or an element with no lateral channel at all. |
| `clifftop-outward-rim` | No outward-banked turn exists on record, and the lateral sign convention plus the absence of turn-direction metadata makes outward vs inward undecidable in these traces. Falcon's clifftop section is measured laterally dead (≈0.00 ±0.15 g over 12 s). |

**Weakly-supported but not gaps** (caveat carried in-row): `return-height-a` and `return-height-b`
— Falcon's return floats never go meaningfully negative, so the negative-g character comes from
I305's late-course hills as class corroboration rather than from a same-ride counterpart.

**Magnitudes explicitly not adopted despite being measured:** `tunnel-lsm3` Gx+ (+2.53 g, inside the
4804 artefact burst, contradicted by Source 2 at +0.9 g), and the ⚠-marked lateral/longitudinal
pull-up figures under `camelback`.

Machine-readable form of this same table: `godot/fidelity_counterparts.gd`
(`RideFidelityCounterparts.bands()`). It is standalone data — nothing preloads it, and it is not
part of any gate.
