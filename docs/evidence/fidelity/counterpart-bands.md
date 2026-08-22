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

## Where the numbers live

**The numbers are shipped once, in code.** For any role `X` below, its counterpart citation,
telemetry anchors, per-axis measured values, stretch factor, hold durations and thresholds are
`RideFidelityCounterparts.BANDS["X"]` in `godot/fidelity_counterparts.gd`; the stretched **design
target is derived, never stored** — `RideFidelityCounterparts.bands()` fills it as
measured × stretch rounded to 0.01 g, so document and code can never drift apart. This file keeps
the derivation rule, the source caveats and the human argument for each role; it deliberately no
longer restates a single band value.

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
- Every stretched value is inside the ~2041 envelope (+8.0/−3.0 Gz · ±4.7 Gy · +8.0/−6.0 Gx).
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

**Notes.** Falcon's wall turn is the **steepest bank of that ride** (89–90° at t 115–116.5) and is
the direct geometric analogue for an overbanked arc, but it is a *low*-g overbank at 2.1–2.95 g.
I305 is the opposite: the sustained banked turn is that ride's signature and holds **3.5–4.8 g for
1.4–4.1 s**, accounting for 11 of the 12.3 s it spends above 3.5 g (lines 117–122). The design's
teardrop sits between them; both bands are given rather than averaged. I305 turn #3 is noted in the
source as the outlier — **the load rises through the whole 4.1 s hold rather than decaying**
(line 120), which is a shape target, not a magnitude one. I305 precision is ±0.15 g.

---

# 4. `opener-release` — release hill out of the teardrop

**Notes.** Amplitude and duration trade against each other in the measured set: the deepest hill
(−0.73 g) is the *shortest* below zero (0.52 s), and the longest (1.30 s) is the shallowest
(−0.57 g). Hills 3 and 4 are taken at **75–86°** and **66–88°** bank while unloaded (lines 113, 117)
— steeply banked airtime, which is the release-hill character the design wants, not a flat pop.
Falcon's whole-ride ejector time is only **0.38 s** (line 92), so this ride class is
floater/flojector-dominant; the ejector references live under `act-one-airtime` below.

---

# 5. `act-one-immelmann` — giant Immelmann, 100–110 m

**Context row not carried in code:** the climb into Immelmann #1 reads 0.47–1.43 g over ~4 s
(TELEMETRY.md line 397, preceding row). It is context only — no target, no band.

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

**Open discrepancy (2026-08-23).** For the Source 2 "on the face" row (+0.17 g front / −0.05 g
back), the deleted table applied ×1.5 to the back-run figure and printed −0.08 g, while
`BANDS["outward-dive"]` declares that axis `gz_level` with stretch `NONE`, i.e. an unstretched
target. Both readings agree the value is ≈0 and that the event is an *unloading*, not a negative-g
event (line 925), so nothing downstream turns on it — but the two halves disagree on the rule and
the code, not this file, is the one that is read. Recorded here rather than silently reconciled.

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

**Notes.** **This is the worst-supported magnitude in the whole table and it is deliberately not
adopted** (that axis carries an explicit `target: null` in code). The 4804 tunnel-launch peak of
+2.53 g sits at t=99.52, i.e. **inside the ±5–10 g raw shock burst at t ≈ 99.3–100.3 s**, and the
source flags it as suspect on its own terms (lines 76,
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

**Notes.** ⚠ **The pull-up rows sit inside the t ≈ 99–100 s artefact burst** and every row labelled
`SUSPECT WINDOW` in code carries that flag (lines 74–79). The vertical peak is the least affected of
them — Source 2 measures +3.23/+3.65 g for the same ride, i.e. the same order — but the lateral and
longitudinal pull-up figures are the ones the document identifies as smeared by the wrist shock, and
the document's onset maxima (V +14.5, L −14.6, G +22.1/−26.0 g/s) all fall inside this burst and are
to be read as **upper bounds, not clean measurements** (lines 171–176). The **crest is the strong
part**: 2.78 s is the **longest negative-g hold of the whole ride** (line 167) and ≈6.8 s of
continuous ≤0.2 g is the longest unloaded stretch (line 128), and none of that is inside the burst.
Source 2 corroborates the crest independently (−0.13 g at the apex, line 886) and reports greyout at
the camelback base (line 904), consistent with a genuine high-g pull-up. The two giant-top-hat class
exemplars are included because they are the only other measured elements of comparable scale.

---

# 16. `return-turn-a` — first overbanked return turn

**Notes.** Clean row: outside the artefact burst, on the same ride, in the same structural position
(a banked turn on the unpowered return run). The 2.88 s ≥2 g hold is the **second-longest ≥2 g run
in the recording** (line 163). Note the shape — only 0.10 s above 3 g against 2.88 s above 2 g —
i.e. a long flat-topped ~2.5 g plateau with a brief tip, not a spike. That is the return-turn
character to reproduce; the peak alone would misrepresent it. Single wrist recording, Row 7 L seat;
Source 2's independent readings on the return run (+2.68 g at video t=315, +0.08 g unloaded at
t=320, lines 887–888) are consistent in magnitude.

---

# 17. `return-height-a` — first return height / airtime beat

**Notes.** **Thin evidence, carried as a caveat rather than a gap.** Falcon's return-run float never
goes negative at all (0.22–0.79 g) — it is a floater beat, not an airtime hill, so it grounds the
*placement and duration* of a late-course height but not a negative-g target. The I305 rows supply
the only measured late-course airtime of the right character, and that source notes the pattern
directly: the late hills are **shallow-and-short, −0.4 to −0.5 g for 0.4–1.3 s**
(TELEMETRY-I305.md lines 124–129) — deliberately less than the mid-course hills. A design that makes
the return heights *stronger* than the mid-course airtime would contradict both sources.

---

# 18. `return-turn-b` — second overbanked return turn

**Notes.** The signature of the second return turn is **length, not amplitude**: ~8 s continuously
between 1.7 and 2.5 g, reaching 89° of bank at its middle (line 134), with the ≥2 g portion being
2.76 s of that — the **third-longest ≥2 g run of the ride** (line 163). Three separate return turns
are given because the design places two turns plus a terminal sequence and the measured ride shows
this whole family living in a consistent 2.3–2.5 g band. The −1.52 g longitudinal inside the long
turn is a real retard (the ride is bleeding energy on the return), not a brake application; the
brake references are in row 20.

---

# 19. `return-height-b` — second return height / airtime beat

**Notes.** Same caveat as `return-height-a`, and weaker: Falcon's second return float barely crosses
zero (−0.16 g) and is the shallowest airtime beat on the record. Both measured sources agree the
*last* airtime beat before the brakes is the smallest one of the ride — I305's final pop is −0.45 g
for 0.78 s and its hill #17 is −0.40 g for 0.38 s. A design that lands the last height beat between
−0.2 and −0.6 g for well under a second is inside both sources; anything deeper is unsupported by
measurement, though not by itself wrong.

---

# 20. `terminal-capture-brakes` — brakes and station capture

**Notes.** **The cross-recording Tormenta pair is the trustworthy number here** — −0.94 vs −1.06 g
with hold durations agreeing to 0.02 s (0.82 vs 0.80 s), from two independent devices in two
different seats. 4804's −1.89 g is the ride's longitudinal minimum and, unlike the tunnel launch, is
**not** inside the t≈99–100 s artefact burst, so it is defensible as a real value — but Source 2 puts
the same ride's maximum deceleration at −1.34/−0.93 g (line 917), so the stretched target derived
from −1.89 g should be read as an upper bound rather than a design centre. A brake bite of ≈−1.6 to
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
4804 artefact burst, contradicted by Source 2 at +0.9 g), and the `SUSPECT WINDOW` lateral /
longitudinal pull-up figures under `camelback`.

Machine-readable form — and the only place the values live: `godot/fidelity_counterparts.gd`
(`RideFidelityCounterparts.BANDS`, targets filled by `RideFidelityCounterparts.bands()`). It is
standalone data — nothing preloads it, and it is not part of any gate.
