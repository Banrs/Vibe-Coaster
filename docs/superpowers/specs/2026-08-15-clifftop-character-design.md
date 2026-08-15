# Clifftop Character — Design Note (answers `docs/ISSUES.md` issue 26)

Design only. Nothing lands before the prefix closure solve (Stages 1–4 of `2026-08-15-prefix-closure-solve-design.md`) is green.
Scope: `climb-lsm2` → `outward-dive`.

## 1. Verdict — under-declared story beat, not a shaping bug

Falcon's Flight puts **two** things on the clifftop (TELEMETRY.md lines 122–123):

| window | source's own label | duration | Gz | Gy | bank |
|---|---|---|---|---|---|
| 56.0–77.0 s | **Upper-cliff turns/hills** | **21.0 s** | 0.44–2.10 | −1.13 peak; −0.63…−0.90 sustained | 14–79° |
| 78.0–90.3 s | Crest crawl / slow beat | 12.3 s | 0.98–1.00 (12 s hold) | ≈0.00 ±0.15 | 1–15° |

**The number that decides it:** the 1 Hz appendix (lines 240–262) resolves 56.0–77.0 s into **four** distinct banked gestures —
bank maxima 79° (t 57–58), 52° (t 63), 52° (t 69–70), 67° (t 75–76) — separated by **three** troughs where bank falls to 8–14°
(t 61, 68, 73), corroborated by four independent Gz valleys of 1.6–2.1 g at t 55–57, 63–64, 69–70, 75–77 (line 122). Our whole
clifftop is **7–11 s with one bank build** (`generator_material_tests.gd:274`; `ride_program.gd:568-616`). 33.3 s and four
gestures against 7–11 s and one: a missing role, not a mis-shaped one (issue 20's continuous-roll fix landed inside those two
roles and cannot reach this).

Heading is *not* short. Integrating `ω = g(Gz·sinφ + Gy·cosφ)/v` over 56–77 s gives **412°/275°/206°** at an assumed 20/30/40
m/s, against our declared 160–195° (`:277`). What differs is *rhythm*: the real ride spends that heading in four alternating
sweeps with three unbank troughs, we spend ours in one monotonic sweep. **Length** is the second shortfall — at 20/25/40 m/s the
run is **420/525/840 m** against our `clifftop-suspense` band of 80–190 m (`:188`).

Honesty: recording 4804 is flagged UNRELIABLE and is the only one (lines 62–66); line 122's assignment is the source's own
inference; no speed channel exists, so every length above assumes a speed. Robust part: the *count* — two channels independently
say four. (`docs/ISSUES.md` quotes `clifftop-slow-crest` as 35–70 m; the code says 35–80 m, `generator.gd:516`.)

## 2. Minimal change — one new role ahead of the crawl

`SPINE_TAIL` becomes `climb-lsm2 → clifftop-rim-weave → clifftop-slow-crest → clifftop-outward-rim → outward-dive`, matching the
real order (turns → crawl → dive).

`clifftop-rim-weave`, band **190–280 m**: three alternating banked sweeps at fixed total duration, each `quintic` bank-in / held
arc / `quintic` release on a plateau-pulse roll (the rim's continuous-roll idiom), unbanking to ≤15° between sweeps. Bands from
the measured counterpart, **unstretched**: Gz ≤ **2.10 g** (measured max — the ×1.333 stretch is *declined* for
`counterpart-bands.md` §11's reason: this beat's identity is suspense, not load, and 2.80 g would be act-one class, a record
inside a reference-scale element); |Gy| ≤ **0.75 g** (measured sustained −0.63…−0.90; the −1.13 g peak lasts 2×0.22 s on a
wrist-mounted watch, inside the source's own artefact caveat); unwrapped heading **≥165°**, ≥2 bank-sign reversals, each sweep
held ≥0.8 s at |φ|≥30°; clifftop total (weave + crawl + rim) **18–28 s**, **300–450 m**. Against the five constraints:

1. *Reference-scale-only.* Every number is a measured Falcon value, unstretched. The scale gates then need re-deriving: at 450 m
   the `opener/summit ≥6×` and `camelback/summit ≥4.5×` floors (`:210-211`) become ≈3.0 and ≈2.2 — re-derive both from Falcon,
   where those ratios are ~1.9 and ~1.4.
2. *One slow beat.* New gate: weave minimum speed ≥ crawl minimum **+3 m/s**, and the crawl stays the unique ≥5 s hold within
   ±0.02 g of 1.00 g. The real ride passes by construction.
3. *Narrow plateau.* An alternating weave hugs better than one long sweep: sign-reversing sweeps return to the shelf-parallel
   axis, bounding cross-track walk. Declare it — centreline offset from the shelf-edge tangent ≤ **0.35 × `apron_width_m`**,
   clearance scans unchanged.
4. *Issue 22.* The weave goes **upstream of the crawl**, so nothing moves between the rim turn and the dive; `dive_approach_s`
   keeps aiming at the low end of `DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M`.
5. *Solve tail.* The weave sits between `climb/level` and `rim/slow-crest-in` — **inside the solve tail already**: all four
   prefix residuals (`dive_edge_span_m`, `tunnel_edge_span_m`, `summit_rise_m`, `record_exit_speed_mps`) are measured
   downstream, so every evaluation re-integrates it. Cost is tail length: ~+15 s ≈ +300 coarse samples/eval, ≈+35% on §8's
   budget (2.2 s → ≈3.0 s worst/seed) — Task 4 gates it.

**Fifth control: not needed.** The weave is authored at fixed total duration; its energy cost is paid by `climb_core_s` (control
1, the crest-energy knob) and bounded by residuals 3 and 4 — a control per sweep would break the square 4×4 system. What must
move is *data*: `climb-lsm2`'s `exit_speed_mps` band (14–24 m/s, `generator.gd:511`) re-derived upward to pay for ~15 s of
unpowered weaving. If Task 4 measures conditioning degrading on the longer tail, the fallback is **`weave_total_s` as a fifth
control against a fifth residual (`clifftop_length_m` in band)** — square preserved — *not* the climb-settle shoulder §9 names.

**Solve design §9, third question, answered:** `crest_hold_s` becomes free. Today the 160° heading floor and the 3 m centreline
floor are both charged to a 7–11 s window whose only heading source is the rim sweep — hence `ride_program.gd:575-577` recording
the crest hold as load-bearing for both. Move the heading floor onto the weave (≥165° of its own) and the vertical-variation
floor onto its Gz valleys, and the crawl collapses to what telemetry measures (level 1–15°, laterally dead, heading ≈0), leaving
`crest_hold_s` a pure hold length. The weave *unblocks* control 3.

## 3. Certified draws this enables

Two continuous draws on a new `targets.clifftop-rim-weave` stream; the existing `Vector2` ranges in `RidePlanner.TARGET_DRAWS`
suffice, no new machinery.

- `sweep_bank_rad` ∈ **[35°, 52°]** — held bank of all three sweeps (measured span 14–79°; 35–52° is the interior that keeps
  |Gy| ≤ 0.75 g at clifftop speeds).
- `rhythm_bias` ∈ **[0.85, 1.15]** — ratio of sweep-1 to sweep-3 arc time, sweep-2 derived so **total weave duration is
  invariant**. This is the rim's own trick (`rim_arc_s = 4.016 − 2·shoulder`, `:607`) and it is what makes the draw certifiable:
  the handoff does not move, so neither `PREFIX_SEED`'s basin nor the return's fixed seed is disturbed.

`sweep_count` stays **fixed at 3** — an integer the range machinery cannot express, and varying it moves the handoff; drawable
only once the solve has proven re-convergence from a moved handoff (residual 4 is the mechanism). Certification at both extremes
(`ride_planner_tests.gd`, fifteen seeds each): at 35° the clifftop still clears the ≥165° heading and ≥3 m centreline floors;
at 52° the |Gy| ≤ 0.75 g cap, the ≤120°/s roll limit at fixed shoulder times, §2.2's speed separation and §2.3's cross-track
bound all hold; at both the solve converges at ≤60% of `MAX_PREFIX_EVALUATIONS`.

## 4. Evidence gap — what stays unknown

`clifftop-outward-rim` has **no counterpart band** (`counterpart-bands.md` §12, `fidelity_counterparts.gd:197`): no
outward-banked element exists in either telemetry document, and the sign convention (lateral positive is "one side,
recording-dependent", line 14) makes inward-vs-outward undecidable. The weave inherits that limit — its four gestures are
*counted* from bank magnitude and Gz valleys, which say nothing about which way each turns. `REF_MEDIA_MANIFEST`
(`geometry_reference.gd`; template at `docs/evidence/fidelity/geometry-reference-manifest.template.json`) could close part of
it: **overhead / satellite / drone plan-view stills of the Falcon clifftop between the climb top and the dive** would let the
overlay confirm or refute (a) the sweep count as a plan-view shape, (b) each sweep's radius, (c) how far the track walks off the
shelf-parallel axis — precisely §2.3's bound. Unknown even with imagery: bank sign per sweep, whether the hills sit on the
plateau or on the apron below, and the speed profile — so §1's lengths stay inferred. Unlike the rim, this role ships *with* a
named counterpart (Falcon 56.0–77.0 s): it adds a `counterpart-bands.md` entry rather than a gap.

## 5. Implementation sketch (five tasks, TDD, stage 5+)

1. **Declare the beat.** Failing test first (`_check_clifftop_contract`): ≥3 gestures at |φ|≥30° held ≥0.8 s separated by ≤15°
   troughs, ≥2 bank-sign reversals, clifftop duration 18–28 s — red today. Then add the role to `SPINE_TAIL`, its `_role(...)`
   band, and the three-sweep recipe in the clifftop tranche.
2. **Keep the crawl the one slow beat.** Failing test first: weave minimum speed ≥ crawl minimum +3 m/s and the crawl the unique
   ≥5 s hold within ±0.02 g, fifteen seeds. Then re-derive `climb-lsm2`'s `exit_speed_mps` upward, let `climb_core_s` pay,
   re-baseline in one commit.
3. **Hug the shelf.** Failing test first: centreline offset ≤0.35 × `apron_width_m` and terrain clearance unchanged, fifteen
   seeds. Then bound the sweep geometry and re-derive §2.1's two scale floors from Falcon, with the derivation written into the
   test.
4. **Prove the solve still closes.** Failing test first (`ride_program_tests.gd`): with the weave in the tail the solve
   converges from `PREFIX_SEED` on all fifteen seeds at ≤60% of `MAX_PREFIX_EVALUATIONS`, coarse/fine agreement holds, both
   hands give identical control vectors to 1e-9, per-seed time under the re-measured cap. Only if that cannot go green on four
   controls, add the §2.5 fifth pair.
5. **Draw the rhythm.** Failing test first (`ride_planner_tests.gd`): both extremes of `sweep_bank_rad` and `rhythm_bias` build
   an accepted ride fleet-wide with a measurable clifftop-geometry spread. Then register the draws, move the 160° heading and 3
   m centreline floors onto the weave, and record in the solve design's §9 that `crest_hold_s` is unconstrained.
