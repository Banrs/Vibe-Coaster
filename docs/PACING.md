# Pacing and intensity distribution — research notes

> **Status: research input. Nothing here is decided.** Gathered for roadmap step 9 (pacing score) and
> step 10 (Falcon's Flight validation). Every factual claim carries a URL. Anything derived here
> rather than read off a source is prefixed **INFERRED** — those are arithmetic on the cited figures,
> not published values.
>
> **Before implementing any of this: review it, and ask.** These notes were assembled in one research
> pass under a search budget that ran out (see §11), and one confidently-worded conclusion has already
> been withdrawn on review as a category error (§2). Treat the derivations as arguments to be checked,
> not as results to be coded. In particular, decide *with the human* — do not decide alone —
>
> - whether the pacing score integrates g-seconds, and over what window and axis set;
> - whether §1's envelope is complete enough to gate on, given the ASTM tables could not be obtained;
> - how §4's `G_total / duration` should be normalised, since the Σ|dθ| figures there are guesses;
> - whether any of this belongs in the model at all, or only in the analysis surfaced to the user.
>
> Open questions are collected in §12.

## 1. Absolute limits

| Limit | Value | Source |
|---|---|---|
| ASTM F24 max acceleration | 6 G, duration < 0.8 s | [coaster101](https://www.coaster101.com/2025/04/28/flip-flap-railway/) |
| Max onset rate (jerk) | 15 g/s | [physicsworld](https://physicsworld.com/a/twists-turns-thrills-and-spills-the-physics-of-rollercoasters/) |
| Min decay rate | 0.8 g/s — caps how long an exposure may last | same |
| Envelope shape | magnitude-vs-duration: rise ramp, duration-capped plateau per g level, fall ramp | same |
| Human +Gz | ~5 g LOC threshold, untrained | [wiki G-force](https://en.wikipedia.org/wiki/G-force) |
| Human −Gz | −2 to −3 g | same |

Observed fleet ceiling sits at the *human* limit, not the ASTM one: 5.0 g Skyrush, 4.5 g Expedition
GeForce, 4.3 g Nitro, 5.9 g Shock Wave (highest listed operational), 4.7 ± 0.2 g mean across four
Thorpe Park rides
([Skyrush](https://en.wikipedia.org/wiki/Skyrush), [G-force](https://en.wikipedia.org/wiki/G-force),
[PMC5285407](https://pmc.ncbi.nlm.nih.gov/articles/PMC5285407/)).
The negative floor is exactly −2 g (El Toro, Skyrush) — again the human limit, not a structural one.

**Duration, not magnitude, is the binding constraint.** Do-Dodonpa's launch was 3.3 g — *below*
Skyrush's 5.0 g — but held for 1.56 s, roughly twice the 0.8 s cap, in the eyeballs-back axis. 18
injuries, 9 fractures, permanent closure
([wiki](https://en.wikipedia.org/wiki/Do-Dodonpa)). Peak g is the wrong scalar to limit on.

## 2. Per-element geometric scaling

From `n_c = v² / (r·g₀)`, holding a target load fixed gives **r ∝ v²** — element size scales with the
square of speed. INFERRED throughout this table:

| Target | Formula | @70 mph | @95 mph (Fury) | @155 mph (Falcon's Flight) |
|---|---|---|---|---|
| +4.0 g valley | r = v²/(3g₀) | 33 m / 109 ft | 61 m / 201 ft | 163 m / 535 ft |
| −1.0 g crest (ejector) | r = v²/(2g₀) | 50 m / 164 ft | 92 m / 302 ft | 245 m / 803 ft |
| −0.3 g crest (floater) | r = v²/(1.3g₀) | 77 m / 252 ft | 141 m / 463 ft | 377 m / 1236 ft |

- INFERRED: at 155 mph nothing smaller than ~163 m of radius delivers 4 g, so small elements are
  geometrically unavailable and the layout has to be launches separated by long transits rather than
  a hill train. Directly relevant to step 10.
  > **Editorial note, added on review.** This bullet originally observed that the 163 m figure is
  > "almost exactly" Falcon's Flight's 534 ft camelback and concluded its intensity distribution is
  > *forced, not chosen*. That comparison is a category error — 163 m is a **radius** here and a
  > **height** there — and the numerical match is a coincidence carrying no evidence. The size-floor
  > claim above survives on its own; the "forced not chosen" conclusion does not, and is withdrawn.
- INFERRED, converse, and **unverified**: Skyrush reaches 5.0 g and −2.0 g in 63 s at 75 mph, which
  is consistent with radii near the minimum the envelope allows — but no Skyrush radius is published,
  so this is a hypothesis that fits, not a measurement. Reading its flat, no-build profile as "held
  at the geometric limit end to end" is the same shape of leap the withdrawn note above made. Check
  it against the model before relying on it.

## 3. The anti-cheat invariant — g-seconds are radius-independent

For a constant-speed arc sweeping Δθ: time in element `t = rΔθ/v`, load `n_c = v²/(r·g₀)`, so

```
∫ n_c dt  =  v·Δθ / g₀          ← radius cancels
```

INFERRED, and the key result for the pacing score: tightening `r` raises peak g and shortens dwell
time in *exact* inverse proportion. Peak-g and duration slide along a hyperbola; the area under the
g-vs-time curve for that element is fixed by speed and swept angle alone.

**Reducing smoothing cannot add force content — it only relocates it up the magnitude axis and into
the ASTM duration-cap violation region.** Any scoring function built on peak g is gameable by
tightening; one built on g-seconds is not.

- Cheat-proof per-element metric: `g·s = v·Δθ / g₀`. INFERRED examples — 180° turnaround @70 mph =
  10.0 g·s; @40 mph = 5.7 g·s; 60°-sweep airtime crest @70 mph = 3.3 g·s; full vertical loop at
  avg 25 m/s = 16.0 g·s.
- Cheat-proof per-track metric: `G_total = (1/g₀) ∫ v·|dθ|` — the line integral of speed against
  turning. Raised only by going faster or turning more, never by tightening.

## 4. Does the metric track how coasters actually flow?

INFERRED, with rough Σ|dθ| estimates — the angles are mine, not published:

| Ride | Σ|dθ| est. | avg v | G_total | ÷ duration | Matches critique? |
|---|---|---|---|---|---|---|
| El Toro | ~25 rad (9 airtime moments ×120° + 2 turnarounds) | 20 m/s | ~51 g·s | 102 s → 0.50 g | yes — "never lets up" |
| Millennium Force | ~15.7 rad (3 hills + 3 overbanks + helix) | 30 m/s | ~48 g·s | 140 s → 0.34 g | yes |

The useful result: `G_total` ranks the two rides as near-equal, but **`G_total / duration` separates
them the way reviewers do.** Millennium Force delivers almost the same total force content as El Toro
spread over 37% more time. The "giant blue powered coaster" complaint is a *density* deficit, not a
force deficit. Pacing quality reads as force density, and the archetypes in §5 are the shape of that
density over time.

**Middle-50% (IQR) vertical g is the right robust statistic** — duration-weighted and therefore
radius-invariant, unlike p99/max. INFERRED anchors: Steel Vengeance is 27.2 s airtime in 150 s =
18.1% of the ride below 0 g, so its p18 is already ≤ 0 and its middle 50% plausibly spans ~0.3–2.0 g;
Millennium Force with 1–2 airtime moments plausibly sits ~0.9–1.3 g, statistically near-static for
most of its run
([Steel Vengeance](https://en.wikipedia.org/wiki/Steel_Vengeance),
[Voyage 24.3 s / 165 s = 14.7%](https://holidayworld.com/rides/the-voyage/)).

## 5. Smoothing floor — the constraint that must not be relaxed

INFERRED from the 15 g/s cap: minimum transition time `t ≥ Δn/15`, minimum easement arc length
`L ≥ v·Δn/15`.

| Transition | Speed | t_min | L_min |
|---|---|---|---|
| 1 g → 4 g | 70 mph | 0.20 s | 6.3 m / 21 ft |
| 1 g → 4 g | 155 mph | 0.20 s | 13.9 m / 46 ft |
| −1 g → +4 g (Δn = 5) | 155 mph | 0.33 s | 23.1 m / 76 ft |

The clothoid / Euler spiral has curvature linear in arc length, so `dn/dt` is constant — it is the
minimum-length easement satisfying a jerk cap. **Any transition shorter than `L_min` is the geometry
cheat.** Stengel's clothoid loop and heartlining are the historical instantiations
([Stengel](https://en.wikipedia.org/wiki/Werner_Stengel)); the 1895 Flip Flap Railway's *circular*
12.5 ft-radius loop is the counterexample, ~6–8 g by recalculation
([coaster101](https://www.coaster101.com/2025/04/28/flip-flap-railway/)).

The 0.8 g/s minimum decay is a pacing mandate inside the standard itself: a high-g state must be
exited, so sustained plateaus are illegal and oscillation is structurally required. INFERRED:
4 g → 1 g at the minimum rate occupies ≥ 3.75 s, which is why real traces oscillate rather than
plateau — Helix runs 3.5 g → −1 g → 4 g → −1 g → 4 g
([physicsworld](https://physicsworld.com/a/twists-turns-thrills-and-spills-the-physics-of-rollercoasters/)).

## 6. Where peaks occur — real traces

| Ride | Peak +g | Peak −g | Peak speed |
|---|---|---|---|
| Helix (real accelerometer trace) | 3.5 g first-drop bottom; ~4 g launch; >4 g valley; 4 g again later | −1 g airtime hill between the two 4 g valleys | after launch ([physicsworld](https://physicsworld.com/a/twists-turns-thrills-and-spills-the-physics-of-rollercoasters/)) |
| Skyrush | 5.0 g bottom of 212 ft/85° drop (~15% in) | −2.0 g on airtime hill #2 | first drop, 75 mph ([wiki](https://en.wikipedia.org/wiki/Skyrush), [PSU](https://sites.psu.edu/rollercoastersusa/2019/03/12/skyrush-ride-the-edge/)) |
| Expedition GeForce | 4.5 g first drop | 7 weightless periods | 74.6 mph first drop ([wiki](https://en.wikipedia.org/wiki/Expedition_GeForce)) |
| Nitro | 4.3 g first drop | floater only, 7 camelbacks | 80 mph first drop ([wiki](https://en.wikipedia.org/wiki/Nitro_(Six_Flags_Great_Adventure))) |
| El Toro | not published | −2 g on Rolling Thunder hill, ~70% through | 70 mph first drop ([wiki](https://en.wikipedia.org/wiki/El_Toro_(Six_Flags_Great_Adventure))) |
| Intimidator 305 | greyout/blackout in 270° turn straight off drop (~15%) | strongest ejector = 150 ft hill ~30% | 90 mph first drop ([wiki](https://en.wikipedia.org/wiki/Intimidator_305)) |
| Do-Dodonpa | 3.3 g for 1.56 s at launch | — | end of launch ([wiki](https://en.wikipedia.org/wiki/Do-Dodonpa)) |

Near-universal rule: **peak +g and peak speed both land at the first valley** — confirmed for Magnum,
Millennium Force, Steel Vengeance, Voyage, Boulder Dash, Nitro, Skyrush, Fury 325, I305. Peak −g is
the value that migrates late in the layout.

### Modern exceptions where peak speed is not the first drop

- **Falcon's Flight** (Intamin, opened 31 Dec 2025, 3:35): L1 → 24 mph → twisted 180 ft drop plus
  airtime hills → **L2 → 99.4 mph** up the Tuwaiq cliffs → turns and an outer-banked turn → **brake
  section** → 90° drop into tunnel → **L3 → 155 mph top speed** → 534 ft camelback → hills → brakes
  ([wiki](https://en.wikipedia.org/wiki/Falcon%27s_Flight),
  [coaster101](https://www.coaster101.com/2023/11/14/intamin-reveals-falcons-flight-details/)).
  INFERRED: top speed sits at element 7 of 10, ~65–70% through — an escalating three-act profile with
  a deliberate deceleration beat immediately before the biggest launch.
- **Tormenta: Rampaging Run** (B&M giga dive, Six Flags Over Texas, 2026; 309 ft, 285 ft @95°,
  87 mph, 4,199 ft, 5 inversions): lift → dive drop → 218 ft Immelmann (tallest inversion anywhere) →
  179 ft vertical loop (tallest) → mid-course brake → vertical drop → smaller Immelmann → cutback.
  Front-loaded; ~60 s drop-to-brake, "each element blends seamlessly into the next"
  ([review](https://www.coaster101.com/2026/07/10/tormenta-review-grabbing-the-bull-by-the-horns-at-six-flags-over-texas/),
  [specs](https://www.coaster101.com/2025/09/25/tormenta-dive-coaster/)).
- **VelociCoaster**: 70 mph after the *second* launch, ~55% through
  ([wiki](https://en.wikipedia.org/wiki/Jurassic_World_VelociCoaster)).

## 7. Distribution archetypes

- **Front-loaded / decaying** — Millennium Force ("after the first drop there isn't much in the way
  of airtime… just mild floater air",
  [CF](https://coasterforce.com/forums/threads/do-you-think-millennium-force-has-a-good-layout.18740/));
  Nitro ("airtime… isn't as memorable or was non-existent",
  [coastercritic](https://coastercritic.com/2007/06/06/nitro-six-flags-great-adventure-coaster/));
  I305 ("the first half of the ride is exhilarating, but really nothing all that amazing",
  [coastercritic](https://coastercritic.com/2010/08/31/intimidator-305-kings-dominion-roller-coaster-reviews/));
  Tormenta.
- **Escalating / back-loaded** — Magnum ("the trip back to the station is stuffed with ejector air",
  [coastercritic](https://coastercritic.com/2006/06/02/magnum-xl-200-cedar-point-coaster/)); El Toro
  ("just gets crazier and crazier",
  [inc](http://www.incrediblecoasters.com/Top10WoodenCoasters.html)); Iron Gwazi ("actually seems to
  be getting faster as it goes on"; finale double-down among "the strongest airtime on the ride",
  [coaster101](https://www.coaster101.com/2022/02/11/iron-gwazi-our-review-and-reactions/));
  Boulder Dash; Falcon's Flight.
- **Oscillating, with an engineered rest beat** — Voyage's mid-course brake as a false ending, return
  leg "even more insane than the ride out"
  ([coasterguy](https://coasterguy.wordpress.com/2013/06/08/the-voyage-at-holiday-world-review/));
  Phoenix's tunnel "cuts off your senses just long enough to reset expectations"
  ([thrillzing](https://thrillzing.com/roller-coasters/phoenix-knoebels/)); **Taron act 2 "a bit
  smoother… so you can prepare for part two", closing bunny hops braked deliberately for pacing**
  ([coasterkings](https://thecoasterkings.com/opening-event-klugheim-taron-and-raik/)); Maverick
  ([wiki](https://en.wikipedia.org/wiki/Maverick_(roller_coaster))); Smiler halts fully at halfway,
  7 inversions per act
  ([coaster101](https://www.coaster101.com/2021/06/28/beyond-the-track-smiler-at-alton-towers-in-depth-analysis/)).
- **Flat-topped** — Skyrush "starts impossibly fast and stays that fast throughout"
  ([wiki](https://en.wikipedia.org/wiki/Skyrush)); Steel Vengeance "didn't have… 'lull zones'"
  ([coaster101](https://www.coaster101.com/2018/04/30/steel-vengeance-review/)); Fury 325 and Iron
  Gwazi have **no mid-course brake at all**
  ([wiki](https://en.wikipedia.org/wiki/Fury_325), [wiki](https://en.wikipedia.org/wiki/Iron_Gwazi)).

## 8. Peak counts — how many discrete intensity events

VelociCoaster 12 airtime moments + 4 inversions + 2 launches (~2:00) · Iron Gwazi "a dozen airtime
moments" (1:50) · El Toro 9 zero-g opportunities (1:42) · Steel Vengeance 4 inversions + 6 finale
hills + 2 pre-lift hops ≈ 15+ (2:30) · Magnum 3 big hills + 7 airtime hills (2:00) · Maverick 8 hills
+ 3 inversions + 2 launches (2:30) · Expedition GeForce 7 (1:15) · Nitro 7 camelbacks (2:20) ·
Boulder Dash 8 major hills (2:30) · Phoenix 8 (2:00) · Skyrush 5 hills + 4 turns (1:03) ·
Millennium Force only ~1–2 real airtime moments in 2:20 (outlier low).

INFERRED: modal count is **7–12 discrete peaks in a 1:40–2:30 ride ⇒ one notable event every
~9–15 s**. Falcon's Flight at 3:35 is the only ride long enough to require three acts.

## 9. Pacing as a stated design variable

- Jeff Havlik, PGAV Destinations: "We don't want to do full-out scream experiences, where you're
  disoriented the entire time. **We look at it more like creating a symphony, with rises, falls, and
  crescendos.**" ([matador](https://matadornetwork.com/read/roller-coaster-design-process/))
- Spacing as the deciding variable: Talon's "pacing… is ten fold better than say Batman… where you
  feel like you were tossed in a dryer and put on tumble with one quick inversion after the other"
  ([coastercritic](https://coastercritic.com/2019/01/05/review-talon-dorney-park/)); the same argument
  praising Iron Gwazi's "sheer size and *spacing* of the layout"
  ([coaster101](https://www.coaster101.com/2022/02/11/iron-gwazi-our-review-and-reactions/)).
- Relentlessness costs re-rides: I305 "I wasn't able to do more than a few back-to-back rides";
  Fury "better for re-rides as it's a bit *less intense all-around*"
  ([coastercritic](https://coastercritic.com/2015/07/25/fury-325-vs-intimidator-305-roller-coaster-showdowns/)).
- Pacing retuned as post-opening engineering: I305 trims added 2010, then the first turn rebuilt at
  larger radius and trims removed ([wiki](https://en.wikipedia.org/wiki/Intimidator_305)); Maverick's
  heartline roll cut pre-opening for "excessive force"
  ([wiki](https://en.wikipedia.org/wiki/Maverick_(roller_coaster))).

## 10. Fraction of ride outside 1 g — the only hard numbers

- Steel Vengeance: 27.2 s airtime in 2:30 ([wiki](https://en.wikipedia.org/wiki/Steel_Vengeance)) →
  INFERRED 18.1% of duration below 0 g.
- The Voyage: 24.3 s in 2:45 ([Holiday World](https://holidayworld.com/rides/the-voyage/)) →
  INFERRED 14.7%.
- INFERRED: a conventional hyper (7 camelbacks × ~1–1.5 s) lands nearer 5–8%.

## 11. What could not be sourced

- Full ASTM F2291 per-axis acceleration/duration tables. Only the F24 6 G / 0.8 s figure is
  reachable; astm.org and the standard itself are paywalled and no accessible reproduction of the
  axis-by-axis envelope was found. **The §1 envelope should be treated as partial.**
- EN 13814 numeric tables.
- Percent-time-above-+2 g for any coaster — no such publication appears to exist.
- Published g-force figures for Magnum, Steel Vengeance, Voyage, Phoenix, Boulder Dash, Maverick,
  Iron Gwazi, Fury 325, Tormenta, Falcon's Flight.
- Measured radii for any named element, so **every radius in §2 is a derived requirement, not a
  reported value.**
- Per-element g breakdowns from any manufacturer.
- Stengel's own g-vs-time diagrams — only the clothoid/heartlining philosophy is online.
- Pendrill's 2013 loop-geometry paper (IOP paywalled; the Gothenburg PDF mirror is image-only and
  not text-extractable), and Pendrill & Eager 2020, same problem.
- Falcon's Flight rider-experience reporting — Scott Schaffer's CoasterForce POV exists but the host
  is unreachable.
- Mitch Hawker poll methodology — ushsho.com has been repurposed, coasterfanatics.com redirects, and
  archive.org was blocked.

Retrieval blockers during this session: WebSearch budget exhausted at 200/200;
coasterforce.com, coasterpedia.net, grokipedia.com, researchgate.net and reddit all returned 403;
arborsci returned 503.

## 12. Open questions — resolve with the human before writing code

Ordered roughly by how much downstream design they decide.

1. **Does the pacing score belong in the model, or only in the analysis?** Step 9 is "analysis
   surfaced", which suggests read-only measurement. But a score the solver optimises against is a
   different thing entirely, and would touch step 6. Not answered here.
2. **What does the g-seconds integral run over?** §3 derives the invariant for a single
   constant-speed arc. A whole track is neither constant-speed nor a single arc. Whether to integrate
   `|n − 1|`, signed `n`, per-axis components, or a magnitude, and whether to weight negative
   differently from positive, are all unanswered — and the answer changes what the score rewards.
3. **Is §1's envelope safe to gate on?** The ASTM per-axis duration tables could not be obtained. The
   6 G / 0.8 s figure is a single secondary-source number. If the project already implements a
   duration-scaled envelope, reconcile the two rather than replacing one with the other.
4. **How is force density normalised?** §4's `G_total / duration` separates El Toro from Millennium
   Force convincingly, but on Σ|dθ| values that are my estimates from element counts, not measured
   turning. The metric may not survive real numbers. Re-derive from the model's own geometry first.
5. **Should the archetypes in §7 be a target or an output?** They are descriptive categories drawn
   from enthusiast writing. Whether a designer picks "escalating" and the solver honours it, or
   whether the shape simply falls out and gets reported, is a real fork and is not decided.
6. **Does anything here conflict with `MODEL.md`?** Elements are force-profile templates there. The
   §2 radius floors are a *consequence* of a force profile plus a speed, so they may already be
   implied by the existing model — in which case §2 is a cross-check, not a new constraint. Verify
   before adding anything.

Two cautions carried forward from how these notes were made. The withdrawn claim in §2 was
confidently worded and wrong for a full draft before review caught it, so treat fluency here as no
evidence of correctness. And §11 is long: the gaps are not incidental, several are load-bearing, and
a fresh session with a working search budget should consider re-running the retrieval before building
on the thinner sections.
