# Open issues — user review, 2026-08-09

Daniel's ride-through/review findings after the fidelity campaign. This is the starting
point for the next round of work, not a spec: investigate openly, measure, and expect to
discover problems beyond what is listed. `docs/TELEMETRY.md` holds measured ground truth;
root `CLAUDE.md` holds the contract.

## Next session — start here (2026-08-15, end of session)

Verified on Godot 4.7.1: the import gate, the twelve focused suites in
`.github/focused-tests.txt`, and `smoke.gd` are all green, and all fifteen seeds build and
place clean. Gaps **A** (stage 1) and **B**, which opened this section at the start of the
session, are closed and gated:

**B — the record launch is real.** The tunnel LSM3 booster runs at 1.33 g and the built ride
tops out at 340.40 km/h (94.55 m/s) on all fifteen seeds, gated in smoke at 93.9–95.6 m/s. The
entry launch peaks at 3.9 g (gated 3.7–4.1) with exit speed conserved. The measured cost of
closing the record inside 8.2 km without a mid-course brake was the passive capture-entry band,
widened 70–77 → 70–80 m/s, and the brake bound, raised 3.0 → 3.6 g (measured peak 3.05; the
envelope allows 4.286 over that hold). Derivation:
`docs/superpowers/specs/2026-08-15-record-launch-derivation.md`.

**A stage 1 — the seed varies the ride.** `godot/ride_planner.gd` holds named decision streams
(FNV-1a over stream name plus seed, so streams are independent), the story grammar as data, and
the certified per-seed target draws: return turn-a `transfer_bank_bias` 6.5–8.5°, height-a
`peak_g` 3.65–3.95, and unload scales 0.95–1.05. Measured fleet spread is 8138.7–8180.6 m
(41.9 m) and 0.31 s of duration, with the records pinned on every seed; smoke now has diversity
floors so the fleet cannot silently collapse back to one ride. A latent bug surfaced and was
fixed on the way: the terminal-approach corridor was never clearance-sampled, so seed 123456's
brakes sat 1.82 m under the 2.0 m floor; the approach is now held to station clearance.

### The recommended next work: the prefix closure solve (issue 24)

Stage 2 of gap A — act-one permutation and per-seed draws in the opener and act one — was
**refused by measurement**, three independent times, and all three refusals hit the same wall.
The prefix (station through the cliff dive) has no closure solve of its own: its terminal
geometry is chaotic in its own force parameters, so nothing upstream of the dive can be varied
without knocking the dive off its placement feasibility edge.

The evidence trail, all measured this session:

1. **Act-one permutation refused.** A ±0.005 change in a single force value moves the dive
   chord by ~115 m. 12 of 24 candidate permutations fail the capability preflight outright, and
   the best survivors fail the return solve on 12 of 15 seeds.
2. **Opener roll tranche refused** (issue 20 work). Any bank-timing change in the opener tips
   dive placement off its feasibility edge on *every* seed, so the opener's roll stepping could
   not be fixed with the return and clifftop tranches.
3. **Opener/act-one target draws refused.** Same mechanism: the draws are legal in capability
   terms and still leave the prefix unable to land the dive.

So the recommendation is explicit: build a bounded closure solve for the prefix, the way the
return already has one, so the dive's placement becomes a solved residual instead of a
hand-calibrated coincidence. That unblocks issue 20's last tranche, stage 2 of gap A, and issue
22's dive-commit placement, and it is issue 24's real fix — authoring in the rider's frame is
reproducing the force trace without producing a coherent swept shape, and the prefix is where
that costs the most.

Issue 24 remains the strongest candidate for the single root cause behind 20, 23 and much of
15. If one thing is picked up next, pick the prefix closure solve.

**Progress, 2026-08-15 (stages 1–3 landed):** the prefix closure solve is in production.
`_plan` runs preflight → terrain-derived closure target → one bounded four-control solve →
closed-form placement; the grid search is deleted; the accepted controls thread into
`compile()` and are verified off the built spans. Fleet-wide gated margins at the stage-3
baseline (worst seed): dive-entry edge +6.13 m, apron fraction +0.062, summit AGL +2.90 m,
record exit +0.79 m/s — stage 5a later moved the entry aim to the rim end for issue 22, so
the current margins live in that entry (dive-entry +4.30 m with the low side binding) —
with the solve converging in 1–6 of 31 allowed evaluations on all fifteen seeds. One honest
narrowing recorded: the entry aim band sits inside a band already inset 3 m, so
terrain the old grid search would have placed can now refuse with a structured error — the
refusal paths are unreached on the fleet, not unreachable in principle; stage 4's
refusal-derived tests exercise them.

**Stage 4 measured (2026-08-15): the solve did half its job, and the other half now has a
name.** Tail-domain changes are absorbed — the act-one loop at −0.005 g places inside all
four margins on 15/15 seeds, and the act-one optional-member swap places 15/15 (both were
flat refusals before the solve). But no perturbed or permuted story builds end to end:
opener (head-domain) changes refuse at the terrain preflight before the solve is reached
(±0.005 g swings the native chord 245–408 m against a ~270 m terrain span — the four
controls all live downstream of act one), and every story that does place then fails in the
seven-control return solve, whose hand-tuned fixed seed does not re-converge for a moved
handoff (budget-exhausted at 79/80 with residuals nearly closed; the record-exit residual
pins the speed, the geometric handoff still moves). The two named follow-ons: a
deterministic per-story derivation of the return seed (a seed derivation, never a retry
loop), and a measured decision on head accommodation for opener draws. The planning-half
victories are gated in `generator_material_tests.gd` (four seeds × {swap, loop −0.005};
~12.7 s locally where the parallel runner hides it, ~25 s on ubuntu's serial CI). Spec
correction recorded in the design's §5. A review then caught the gated swap helper as a
no-op; the corrected helper was re-measured across the full grammar — the counts all
survived, now actually proven, and the complete table exists: of the **36** grammar-legal
act-one orders (not 24 as earlier prose said), exactly three place at all — canonical,
the optional-member swap `cutback loop wave airtime` (15/15), and the airtime-dropped
order (9/15, seeds named in the test comment); the other 33 refuse at the same preflight.

**Story-energy accommodation refused by measurement (2026-08-15).** The proposed prefix-side
follow-on — re-target the closure's fourth residual from `record_exit_speed_mps` to
`dive_entry_speed_mps` so the solve can see the pre-dive energy state — was measured before it
was written, per its own design §9.1, and the measurement refuted it. The swapped story arrives
at the rim **+2.43…+2.46 m/s** hotter carrying only **+7.7…+20.2 J/kg** (the design derived
≈ +3 m/s and ≈ 63 J/kg from arc length), and the +21 m of dive arc is **not** an energy surplus:
at *equal* dive-entry speed the swapped dive still runs +21.7 m longer, and its arc never reaches
490 m anywhere in `climb_core_s`'s 6–12 s bound (minimum ≈ 494.5 m; ≈ 497.1 m anywhere the summit
rise stays in its aim band, i.e. at the entry speed it already has — lowering the entry speed
*lengthens* the arc). The re-target was then implemented and run rather than argued about:
canonical stays bit-identical on all fifteen seeds, and the swap goes from planning 4/4 to
**refusing 4/4 at the prefix closure**, because pulling the dive entry down pushes the record exit
to 96.8–97.2 m/s — inside the summit-rise aim band the swapped record exit spans 94.31–97.94 m/s,
so the design's "pinning `v_entry` at a pinned entry height *is* pinning the record" is false. The
change was therefore **not landed**; the measurement lives in that design's new §10. The only
control that shortens the dive without moving its entry state is `dive_approach_s` (497.1 → 487.6 m
at 0.40 s, entry speed unchanged), which is issue 22's knob.

**Return-seed derivation refused by measurement (2026-08-16), and the order it implied is void.**
The follow-on this section named — "the deterministic per-story return-seed derivation first, then a
dive-arc residual absorbed by `dive_approach_s`" — was measured before more of it was written, and
both halves of its premise failed. (1) The refusal it existed to fix **does not reproduce**: all
fifteen seeds × `dive_approach_s` ∈ {0.80, 0.85, 0.90} converge from the unchanged fixed
`RETURN_SEED` (45/45, worst 68 evaluations), so the fixed seed already follows that moved handoff and
issue 22's second half is unblocked without it. (2) On the act-one swap — the class the design's §4
named — **no seed of any form reaches the target**: re-seeded with an oracle (seed 11's exact
converged vector at the same approach, and the swap's handoff deviation is seed-independent to 0.1 m
fleet-wide), seeds 42 and 20260809 still budget-exhaust at 79/80 at every approach value, every
refusal pinning `height_a_recovery_duration_s` at its 0.35 s floor. The wall is a box constraint, not
a basin. The linear warm start was built and run anyway: it changes no outcome and moves the worst
scaled residual 0.269 → 0.183 on seed 42 but 0.041 → **0.200** on 20260809 — worse on one of the two
cases it was for — so no code landed. The measured sensitivity matrix is recorded at §8.3 of the
design so the work is not lost. Honest order now: **not** the certified
`height_a_recovery_duration_s` floor relaxation — that trim (0.35 → ~0.30) was already measured and
refused, recorded at the bound in `ride_return_solve.gd:28-34`: at a 0.30 floor seed 20260809's
swapped return converges, and its accepted point runs `return-height-a` to 277.6 m against that
role's declared 290–480 m band, so the role band binds below the floor and the certifiable floor is
*above* today's value, never below it. The remaining wall the same measurement named is prefix-side
role length: under the swap `outward-dive` runs 497.4–497.5 m against its 350–490 m band on **every**
seed while the closure accepts `PREFIX_SEED` unchanged, so those 21 m are prefix geometry, "not a
control choice or a return seed". ~~Spend there — the dive-arc residual, `dive_approach_s` returning
route metres~~ — **that spend was taken and refused by its own measurement (2026-08-16); see the next
entry. The role overrun is real, but it is a symptom of the handoff, not the wall, and the metres it
would return are not what the swap is short of.**

**Dive-arc residual refused by measurement (2026-08-16), and the "prefix-side role length" reading
with it.** Third refusal in a row, and like the other two it was built and run rather than argued
about. Corrections first: **canonical does not overrun its dive band.** It builds `outward-dive` at
**475.604–476.544 m** on all fifteen seeds (475.640–476.721 m across every closure observation the
fleet makes), inside the declared 350–490 m band with 13.456 m of headroom, so there was never a
canonical re-baseline to declare. 497.4–497.5 m is the swap's number alone.
Measured per span (seed 11, production integration), the role's length is a **rim-speed budget, not a
cliff-geometry one**: 63% of it is the 4.64 s pull-out run at 49–70 m/s, both stories fall the same
cliff to **5.4 cm** (−247.48 m against −247.42 m, both inside the declared −250…−240 m), and what the
swap's **+2.431 m/s** of rim entry buys is length — all eight spans lengthen, **21.467 m** in total.
That is a **two-point secant of ≈ 8.83 m per m/s** between these two stories (every difference between
them included), not a per-span law: the commit block grows +15.5% against the pull-out's +1.7%. Read
through it the 13.456 m of headroom is ≈ +1.5 m/s of rim speed, and the swap's 497.43–497.46 m is
**7.43–7.46 m past 490 m ≈ 0.84 m/s** too hot (computed on one side of the comparison throughout; the
earlier 0.91 subtracted seed 77777's headroom from seed 11's rim delta).
The residual itself: aim band = the declared role band inset by a margin, four controls and
`MAX_PREFIX_EVALUATIONS := 52` untouched. **Canonical is bit-identical 15/15** (every observation
strictly interior, `_band_residual` exactly 0.0 there, coarse/fine agreement 0.0014 m) and **the swap
refuses 4/4 at the prefix closure**, where today it plans 4/4. Its only absorber returns ≈ 15.8 m of
*net* arc per second of `dive_approach_s`, so the swap needs 0.79 s of that control's 0.60 s of range
to clear a 490 − 5 m *aim* ceiling (the bare 490 m ceiling needs 0.47 s, inside range — the figure is
margin-dependent) — and at a margin small enough to be reachable (3 m), seeds 42 and 20260809 *do*
close the dive at 487.0 m and **still budget-exhaust their return at 79/80** (that run recorded the
exhaustion and the delivered dive length only; the residual breakdown at 79/80 was not captured).
Worse, every metre the approach returns is
re-spent at a loss: pinning the approach at 0.80 s buys seed 11 3.164 m of dive arc and costs
**+46.810 m of `return-turn-b`** and −22.595 m of `return-height-a` (through its 290 m floor); at
0.60 s seed 11's return stops converging; at 0.40 s the plan refuses because the accepted closure flips
the yaw solution. **Length is relieved and the wall remains** — the stronger and better-supported
reading than "length was never binding": the short-approach refusals carry a length residual of exactly
0.0 while the geometric residuals blow up; the converged swap cases sit at 8198.76–8198.80 m, which is
0.20–0.24 m inside the 8199.0 m aim ceiling (`RETURN_LENGTH_AIM_MARGIN_M` = 1.0) and so pressed against
the constraint, not slack under it; and the un-retracted 2.1 m / 5.1 m length overruns those two
exhausting seeds carry (`generator_material_tests.gd:193-195`; 4.9–8.1 m against 8200 m in §1 of the
story-energy design) are more than covered by the ≈ 10.4 m the 3 m-margin run gives back — and they
exhaust at 79/80 anyway.
Widening the band instead is refused too — even past 497.5 m the swap still fails `return-turn-b`
(571.2 / 572.6 m against 430–570) on the two seeds whose returns converge, and 42 / 20260809 never
reach the route contract. **What the evidence names instead:** the swap's wall is the *geometric*
camelback handoff (pulled back 32–66 m, +12–13 m higher, 3.5–5.1° in yaw), and all four closure
controls are durations downstream of act one, so they cannot pin six DOF. The honest spends are
head-domain accommodation (a control upstream of act one — measure the head re-integration cost first)
or a prefix residual on the handoff pose, which needs more than four controls. Neither is a residual on
the dive. Full derivation, the pinned-approach matrix and the built-and-run result:
`docs/superpowers/specs/2026-08-15-prefix-closure-solve-design.md` §11; the refusal is also recorded at
the band's own home in `generator.gd`'s `outward-dive` role.

**Cross-suite build reuse refused by measurement (2026-08-16); the battery's cost is its
schedule, not its builds.** The battery makes 62 full `RideGenerator.build()` calls per run and
35 are preset builds a shared pre-built fleet could serve, so sharing them looks free. It is not:
the reusable builds are not on the critical path. `tools/gates.sh` dispatches in `JOB_LIST` order,
so `smoke.gd` goes last and ends the run; reorder longest-first and the path becomes
`ride_planner_tests` at 140 s, 16 of whose 17 builds are `build_with_decisions` at certified-range
extremes that no preset fleet can serve. Measured: today 183.6 s, longest-first dispatch alone
**145.2 s and 13/13 green**, reuse in today's order 167.9 s (−8.5%), reuse *plus* that reorder
160.5 s — **slower than the free reorder**, because the 20.0 s fleet pre-build prologue costs more
than the 4.9 s reuse takes off the critical path. The full measurement, the per-suite build census
and the scheduler model live in `tools/gates.sh`'s header. Neither lever reaches ~2 min:
`ride_planner_tests`' 16 extreme builds are the wall, and the reorder is measured and available.

### Decisions — 2026-08-15 review session

Recorded user decisions from the full-codebase review (they resolve the "decide deliberately"
items above):

- **Gap A is a bug, not intent: seeds must genuinely vary the ride** — terrain placement,
  track, element geometry, and element order. Variety is to be built as the approved
  FVD-first planner vision (named decision streams, story grammar, per-slot recipe/target
  resolution), not as a simplified RNG sprinkle that would be thrown away. Order variation is
  limited to grammar cells (act-one pool permutes and may drop one optional member; return
  composition varies; the spine stays ordered; `sequence.order` stays reserved).
- **Records are fixed identity; everything else draws.** Camelback ~250 m, the record launch,
  and the 100–110 m Immelmann stay in tight bands; non-record geometry draws per seed within
  conservative certified capability ranges grounded in the FF/TRR telemetry counterparts.
- **Gap B resolves toward the contract, derivation first.** The launch/record numbers are
  re-derived from real engineering (Do-Dodonpa ≈3.3 g reference; near-future LSM credit)
  before code is retuned; the derived numbers become both the code and the prose, gated in
  smoke. Note the honest baseline: the built entry launch (3.2 g) matches the real
  Do-Dodonpa reference; CLAUDE.md's "~4 g" was the unsupported side of that disagreement.
- **The version-1 config surface (material plan Task 4) is in scope** and is to be built on
  the planner decision layer (`build_config`, key registry, overlay algebra).
- **No document is beyond skepticism** — authority: user decisions → physical derivation +
  verified evidence → vision docs → code. Doc cleanup is banner-plus-falsehood-fixes;
  history stays intact.
- **Return-solve budget flag — discharged 2026-08-15:** the budget was re-derived from the
  measured evaluation formula and tightened 220 → `MAX_RETURN_EVALUATIONS := 80` (now in
  `godot/ride_return_solve.gd`), gated at ≤60% usage on all fifteen seeds in smoke.
- **Capture-entry band widened 70–77 → 70–80 m/s** — accepted as the measured cost of closing
  the ~340 km/h record inside the 8.2 km route band with no mid-course brake. The brake bound
  moved 3.0 → 3.6 g for the same reason. Both are recorded in `CLAUDE.md`'s contract, with the
  derivation in `docs/superpowers/specs/2026-08-15-record-launch-derivation.md`. The derived
  entry launch landed at a 3.9 g peak, which supersedes the 3.2 g baseline noted above.
- **Reference imagery is local-only.** Photographic and video reference media is never
  committed. `tools/fetch-reference-media.sh` builds a local manifest, `REF_MEDIA_MANIFEST`
  points the inspection run at it, and an absent manifest is reported as a declared gap rather
  than worked around. (Full POV downloads are bot-blocked from this environment; the thumbnail
  fallback produced five real overlays, and full frames can be supplied locally.)
- **Code budget.** Write the minimum code that solves the problem; ship each piece of data once,
  in code or in a document but never both; the read-only diagnostic layer must not outgrow the
  generator it measures; if two hundred lines could be fifty, rewrite them. This session's
  deflation pass removed 664 lines with byte-identical behavior. Standing rule, in `CLAUDE.md`.
- **Config v1 landed with an honest registry.** `godot/ride_config.gd` and
  `RideGenerator.build_config()` implement the overlay algebra, canonical hash, and resolution
  report, but only `preset`, `seed`, and `slot.intensity` on the two return heights are
  registered — the keys whose full range is certified by `ride_planner_tests.gd`. Every other
  candidate key carries its measured refusal reason in `RideConfig.UNREGISTERED`. Do not widen
  the registry ahead of the measurement that certifies it.
- Housekeeping: the `.superpowers/` working directory referenced by commit `b464a7b`'s
  message is not in the repository and does not survive a fresh clone. `godot/fidelity_overlay.gd`
  and its suite landed via commits `bff59ef`/`d2bda61`/`1999ca0` without a planning document;
  their contract is described in README and the material design's diagnostics section.

Carry-over from the same review: role `targets`, `phases` and `recipe_id` are published in the
accepted route but still unenforced (see *Known limitations of the baseline itself* below).
Only `length_m` and the three terrain intents are proven against the built ride, by
`_validate_role_lengths` in `godot/route_contract.gd` — that function is the working model for
enforcing the rest. None of the sixteen ride-quality issues below is closed.

## Ride quality

1. Missing micro elements — e.g. the slow-ish hilltop section Falcon's Flight has; small
   connective beats are absent.
2. Pacing cheated by near-zero-loss coasting — boring sections hold speed as if
   friction/drag-free, propping up the elapsed average.
   **Mechanism derived, 2026-08-15.** The integrator's resistance is
   `0.08 + 0.000075·v²` m/s² (`ride_program.gd` `ROLLING_MPS2`/`AERO_PER_M`). Rolling at
   0.08 m/s² (c_rr ≈ 0.008) is defensible with near-future bogie credit, but the aero term is
   3–5× under real physics: a ~12 t open train at Cd·A ≈ 4.5–7 m² in desert air
   (ρ ≈ 1.1–1.225 kg/m³) gives 0.00021–0.00036 per metre, not 0.000075. At return speeds
   (~75 m/s) the built ride sheds ~0.05 m of head per metre where honest drag sheds ~0.17.
   Fixing it re-opens the whole energy chain — launch exit speeds, act-one entry bands, LSM
   drives, camelback crest, and the record closure (where more honest drag actually *eases*
   the measured ~21.8 m surplus-head problem) — so it must land as one re-derivation with the
   prefix closure solve available (issue 24), not as a constant tweak.
3. G-force envelope still not reached in many parts.
   **Measured against the counterpart bands, 2026-08-15** (offline geometry pack, deep
   seeds; diagnostic labels, not verdicts): the inversion act runs *under* its grounded
   targets — cutback peak 4.12 g vs the 5.15–5.6 band, Immelmann peak 5.23 g vs 5.79–5.91
   (misses of 0.05–0.18 normalized) — while the loop entry lobe sits slightly over. Roughly
   30 of ~94 counterpart windows read `under` per deep seed. The under-shoots are in exactly
   the roles whose targets are still hardcoded literals; they become drawable/re-targetable
   when the prefix closure solve (24) unblocks act-one retuning.
4. Oversmoothing of elements.
5. Poor FVD implementation — the force-authoring quality itself, not just targets.
6. Poor terrain awareness — e.g. ~80 m above the terrain at the ride's highest point, never
   under 40 m; not actually terrain-hugging.
7. Overlapping supports and poor element shaping, especially inversions.
8. Poor sense of speed.
9. Entry launch should hit significantly higher speed — similar class to the camelback
   (tunnel) booster.
10. Poor element flow — jerky useless-bank → flat → useless-bank sequences.
11. Overly leisurely in many sections.
12. Too many flats — between the cliff-dive LSM and the camelback, on the return, and the
    hold extending too far from the cliff edge (so the clifftop is not terrain-hugging).
    **Measured, 2026-08-15:** ~35.5 s of flat dwell per ~158 s ride on every deep seed;
    12.5 s is the station itself (legitimately flat), leaving ~23 s (~15% of the ride)
    of in-ride flats spread across the beats — the per-beat table is in the offline
    audit's pacing metrics.
13. Airtime hills etc. too tame.
    **Quantified, 2026-08-15:** the act-one airtime chain measures −0.325 g against grounded
    counterpart targets of −1.1 (Falcon deepest mid-course hill), −1.35/−1.73 (I305 ejector
    hills) and −1.13 (longest float) — the built hills deliver a quarter to a fifth of the
    counterpart ejector force, the largest normalized misses in the whole comparison. The
    return heights author −0.45 g × the certified 0.95–1.05 unload draw, similarly tame.
    Blocked on 24 for act one; the return-side deepening needs its draw range re-certified
    wider (the envelope allows far more: −3.0 Gz stretched).
14. Elements miss the original near-future scaling requirements — scaling/geometry feels
    wrong when compared multi-dimensionally (height vs speed vs g vs duration together).
15. Jerky transitions.
16. Many more hard-to-describe "feel" gaps beyond the itemizable ones.

### Second review pass — 2026-08-15

Daniel's findings after riding the merged material-generator build. Numbered from 20 to keep
1–16 stable, because those IDs are wired into the catalog and the audit (see the coverage note
below); these seven are **not** covered by the audit's traceability record.

20. Roll sections cheat the g and jerk budget. The roll is delivered as abrupt
    roll → flat → roll → flat steps rather than a coherent continuous roll, which keeps the
    filtered channels inside the envelope while the actual motion is incoherent. Closely
    related to 15 and 10, but the specific mechanism is the stepping, and it is a way of
    passing `validate_loads` without earning it — treat any fix that keeps the stepping and
    only reshapes the filtered trace as a cheat.
    **Partially fixed, 2026-08-15, measured.** Two tranches now roll continuously. Return
    roles: turn-a peak roll rate 108 → 69°/s, its acceleration break 662 → 258°/s², banked-flat
    share 0.47 → 0.38 (the height roles came out similar). Clifftop roles: slow-crest
    acceleration 901 → 515°/s², rim peak roll 115 → 75°/s, seam breaks 134 → 47 and
    176 → 62°/s². Top speed drifted 94.555 → 94.745 m/s (in band) and the route sits at
    ~8181 m. **Remaining:** the opener tranche was refused by measurement — any bank-timing
    change there tips dive placement off its feasibility edge on all seeds — so the worst seam
    break, 899.7°/s² at drop/unbank-out, stands until the prefix closure solve (24) lands.
21. Height above terrain is not watched and drifts upward. There is a terrain-clearance floor
    but no ceiling and no control of slow upward drift, so the track wanders away from the
    ground over long stretches. Sharpens 6 with a concrete mechanism: the drift is unwatched,
    not merely mis-tuned.
    **Measured, 2026-08-15 (deep seeds 11/42/20260809).** Only 20–27% of samples sit within
    20 m of the ground and 30–34% within 40 m; the longest contiguous stretch above 40 m AGL
    is 2.8–3.2 km, running from the climb through the camelback into the return. Vertical AGL
    beside the near-vertical cliff face legitimately inflates the climb/dive rows, but the
    return is unambiguous drift on the plain: return-turn-b median AGL 101–127 m and
    return-height-b median 146–175 m — the return's airtime structures ride 100+ m above the
    ground they should skim. Act one never comes under ~38 m (per-role minima 51–66 m on
    cutback/loop/airtime/wave), and the `tunnel-lsm3` role runs at 16–52 m AGL, so the
    "tunnel" record launch is not in a tunnel. Fix split: the opener/act-one floor is prefix
    territory, blocked on the closure solve (24); the return-side profile is emergent from
    force authoring — the seven-control solve constrains route length, entry speed, and the
    capture corridor, and nothing in it references the ground beneath the path — so terrain
    awareness there means a residual or authored-height reference against local ground.
22. The cliff dive starts too far out from the cliff edge. The dive should commit at the rim;
    it currently begins well back from it, which also costs the vertigo the beat exists for.
    Interacts with 12's "hold extending too far from the cliff edge" and with the placement
    bands in `generator.gd` (`DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M`, `DIVE_EXIT_APRON_BAND`).
    **Open, with new evidence (2026-08-15):** dive placement is sitting on a feasibility edge —
    a ±0.005 change in one upstream force value moves the dive chord ~115 m — so the approach
    length cannot be shortened by retuning the prefix. It needs the prefix closure solve (24).
    **Half fixed, 2026-08-15 (stage 5a, measured):** with the closure solve landed, the dive
    entry now commits at 16.3–19.6 m behind the rim fleet-wide (was 27.1–33.9 m), aimed at
    the rim end of the clearance band with all margin floors intact (low side now binds at
    +4.30 m) and per-seed variety preserved. The other half — shortening the 64.1 m / 3.68 s
    banked pre-commit approach — **is no longer blocked, corrected by re-measurement
    2026-08-16.** The earlier record (the approach shortening "breaks the return solve on
    15/15 seeds, with a non-monotone basin where 0.85 passes and 0.80 and 0.90 refuse single
    seeds") does not reproduce on today's code: all fifteen preset seeds × `dive_approach_s`
    ∈ {0.80, 0.85, 0.90} — 45 return solves through the production compile seam — converge
    from the unchanged fixed `RETURN_SEED`, worst 68 evaluations (seed 7 at 0.80, the only one
    over the 60% = 48 gate); the per-case distribution and the probe that ruled out
    `RETURN_LENGTH_AIM_MARGIN_M` as the mechanism are in §8.1 of
    `docs/superpowers/specs/2026-08-15-return-seed-derivation-design.md`. So the shortening is
    a prefix-side stage that can be taken on its own evidence: what remains to prove is the
    dive's *geometry* at a shorter approach, not the return's ability to follow it. A gate
    still holds the closure from ever lengthening the approach (fleet 0.996–1.000 s).
    **What remains, priced 2026-08-16.** The shortening was not taken this session, and the
    dive-arc work that would have taken it was refused (see *Next session*). What that stage
    measured about this half, on the canonical path, still stands and is now quantified:
    the approach span itself builds **17.625 m of arc per second** at the canonical rim speed
    (seed 11: the 1.00 s span is 17.625 m of the role's 475.960 m) — that is the *raw span* rate,
    not what the role gives back: the **net** rate, after the commit geometry re-settles around a
    shorter span, is **15.82 m per second** (§11.3 of the prefix-closure design, measured on the
    swapped story — the canonical net rate was not measured). And the whole
    commit block — bank-in, approach, bank-out, commit — is 3.684 s and 64.111 m with just
    +0.258 m of net rise, so it is exactly the flat banked run issue 22 objects to. Shortening
    it on canonical is a **re-baseline**, not a feasibility question: the return follows
    (45/45 at 0.80–0.90, §8.1 of the return-seed design) and the dive band has 13.456 m of
    headroom that a shorter approach only widens. What is still unproven is the one thing the
    issue is about — the dive's *geometry* at a shorter approach: whether the commit still
    reaches the face before the vertical entry begins, and whether `dive_edge_span_m` stays
    inside its aim band without the closure walking the entry back off the rim it was just
    aimed at (at 0.40 s on the swapped story the accepted closure flipped the yaw solution
    outright, which is the failure mode to watch for). Measure that before spending the margin.
23. Too many elements are geometrically distorted — e.g. the camelback carries a sideways tilt
    it should not have. The elements hit their force targets while their shapes are visibly
    wrong. Extends 7 beyond inversions and supports to the marquee elements.
    **Open, now quantified (2026-08-15)** by `godot/geometry_metrics.gd`: the camelback leans
    24.46° off vertical on the rise, 16.28° at the exit, and 10.05° at the crest, against
    ≤1.9° on the airtime hills. The likely mechanism is the 42.5° of heading turn taken during
    the climb. 18 of the 20 roles are grounded against a measured counterpart band
    (`godot/fidelity_counterparts.gd`, derived in
    `docs/evidence/fidelity/counterpart-bands.md`); the wave turn and the outward rim turn are
    declared evidence gaps.
24. The FVD++ implementation gets the g's but not the geometry, especially in the connecting
    transitions. This is the root cause behind 20, 23 and much of 15: authoring in the rider's
    frame is reproducing the force trace without producing a coherent swept shape, and the
    transitions between elements are where the discrepancy shows most. The deepest of the seven
    — 20, 23 and 25 are plausibly symptoms of it. **Now the recommended next work**, with a
    named first step: the prefix closure solve. See *Next session — start here* for the three
    measured refusals that converge on it.
    **Still open, and its remaining half now has a measured name (2026-08-16).** The closure
    solve landed and absorbs tail-domain changes; act-one *permutation* draw certification is
    still blocked and this entry does not close. Three candidate unblocks have now been built
    and refused on their own measurements — the return-seed derivation, the story-energy
    re-target, and the dive-arc residual — and all three failed the same way: they moved a
    scalar the swap is not actually short of. Measured before/after for the act-one optional
    swap, unchanged across all three attempts: it **plans 15/15** and **builds 0/15**; on the
    four gated seeds the returns of 11 and 4096 converge (34 and 42 evaluations) and are then
    refused by the route contract on `outward-dive` 497.4 / 497.5 m and `return-turn-b` 572.6 /
    571.2 m, while 42 and 20260809 budget-exhaust their return at 79/80 with
    `height_a_recovery_duration_s` pinned at its floor. The invariant behind all of it: the
    swapped act one hands the camelback a handoff pulled back 32–66 m, +12–13 m higher and
    3.5–5.1° in yaw, and the four closure controls are all durations *downstream* of act one,
    so they cannot pin six DOF. The next attempt has to add degrees of freedom upstream of the
    handoff — head-domain accommodation or a handoff-pose residual with more than four controls
    — not re-aim an existing one.
25. Still no sense of speed, possibly because of the height off the ground (see 21). Restates 8
    with a candidate cause worth testing directly: measure whether AGL, not velocity, is what
    is missing.
    **Hypothesis confirmed by measurement, 2026-08-15.** In the fastest decile of samples
    (≥80.6–80.9 m/s) the ride is never within 20 m of the ground — the ≤20 m share is 0.000 on
    all three deep seeds, with minimum 37 m and median 49–58 m AGL. The ride is fastest exactly
    where it is farthest from anything that could convey speed; AGL, not velocity, is the
    missing ingredient. The fix is 21's fix.
26. The clifftop section is just a slow bank, not the twisty, windy suspense the real coaster
    has there. The declared roles `clifftop-slow-crest` (35–80 m) and `clifftop-outward-rim`
    (65–120 m) may simply be too short to contain that character at all — check whether this is
    a shaping bug or an under-declared story beat before treating it as either.
    **Answered by measurement, 2026-08-15: under-declared story beat.** Falcon's Flight's
    clifftop is two beats, not one — 21.0 s of upper-cliff turns (four distinct banked
    gestures, bank maxima 79°/52°/52°/67°, three unbank troughs, four corroborating Gz
    valleys at 1.6–2.1 g) and then the 12.3 s crest crawl; ours is 7–11 s with one bank
    build. Heading is not the gap (integrated 206–412° vs our declared 160–195°); rhythm
    and length are. Design: one new role `clifftop-rim-weave` (190–280 m, three alternating
    sweeps, counterpart bands unstretched) inserted ahead of the crawl so the rim→dive
    handoff (22) is untouched; no fifth solve control needed — the weave sits inside the
    solve tail and its energy cost is bounded by the existing residuals. Spec:
    `docs/superpowers/specs/2026-08-15-clifftop-character-design.md`. Lands after issue
    24's stages (stage-5 territory).

## App

17. Loading time.
    **Addressed and review-approved, 2026-08-15 (viewer):** generation and analysis run on a
    worker thread; the ride already on screen keeps playing under a "Generating seed N…"
    HUD line until the new route validates, then the world swaps atomically — a rejected
    route keeps the old ride and shows a persistent ROUTE INVALID banner. Closing the window
    mid-build says "Finishing generation…" and quits when the build lands instead of
    freezing silently. Raw generation time itself is unchanged (issue 19's measurement).
    Awaiting Daniel's verdict.
18. Camera/HUD issues.
    **Scoped by Daniel, first pass landed 2026-08-15, code review found real defects — fix
    in flight.** First pass: POV look-ahead (0.47–1.5 s depending on speed, 8–45 m clamp),
    speed shake, nonlinear FOV ramp; HUD dropped envelope-usage %, bank°, roll°/s and
    elapsed-average, humanized lateral/longitudinal as L/R and accel/brake, added progress
    (clock + km), current → next element, and peak-so-far stats. The opus review then
    measured two real defects — the shake frequencies (23.7–45 Hz) aliased at 60 fps Nyquist
    into up to 7.9 cm of per-frame jitter, and the threaded loader (17) left the CI viewer
    step running 0 of 120 live frames — and the fix round landed and was re-review-approved
    the same day: shake re-tuned to 8.2–11.6 Hz on a wall-clock phase in the camera's own
    basis, measuring 4.41 mm of eye travel per 60 fps frame at top speed; FOV expressed as
    106.5–123.8° horizontal under KEEP_WIDTH (74–93° vertical at 16:9, ultrawide cannot
    widen it); so-far stats track peak and minimum Gz, seed from the first live sample, and
    reset on restart, wrap, new seed, and both row-change paths; the route's own top speed
    shows alongside the so-far value. The camera/HUD logic is now two pure statics swept by
    smoke every run (camera ≤6.3° off tangent vs a 40° bound, look 84.5° clear of the up
    axis vs 30°, per-frame shake ≤8 mm bound at 1.8× measured, element names never empty
    and in exact story order), and CI's viewer step counts live ride frames and exits 1 on
    a rejected route — proven able to fail before the injection was removed. Awaiting
    Daniel's ride-through verdict on the feel.
19. Generation/CI speed — the time-domain return, capture, and brake solves have bounded
    coarse/fine/production evaluations, but the full fleet gate can still be slow. Measure current
    GitHub Actions timings before changing evaluation caps, caching imports, or splitting jobs.
    **Measured, 2026-08-15:** the latest green main run totals 6.1 min — setup + import 19 s,
    focused manifest 2 m 51 s (nine suites at the time; twelve now, projected +30–60 s), smoke
    2 m 48 s, viewer 9 s. At that size, evaluation-cap changes, import caching, or job splitting
    are complexity the measurement does not justify; re-measure only if the manifest keeps
    growing. Note CI triggers on push-to-main and pull requests only, so feature branches
    without a PR run no CI — the local gate sequence is the branch's verification.

## Code health — 2026-08-15 hygiene review

Production is 8,959 SLOC across 17 files; tests are 7,252 across 9. By subsystem: fidelity
4,080 · generator 3,544 · viewer 483 · verify 448 · harness 404. The read-only diagnostic layer
is the largest thing in the repository — larger than the generator it measures — which is worth
knowing before anyone reads `CLAUDE.md`'s "physics, generation, and validation are the product"
as a description of where the code is.

A **full** generator refactor is not recommended: it is green, deterministic, freshly landed,
and none of issues 20–26 is caused by its file layout. The return solve is also basin-sensitive
(act-one force changes perturb it), so gratuitous motion risks a hand-calibrated result for no
functional gain. Two bounded targets are worth doing, ideally as part of the issue 24 work
rather than before it:

- **Duplicated numerics — resolved 2026-08-15.** The capture and brake Newton steps now take
  their linear solve and conditioning from `BoundedSolver.linear_solve` (one Gauss path);
  `_finite_difference_jacobian` deliberately stays private in `godot/ride_return_solve.gd` —
  measured and review-confirmed: adopting `BoundedSolver.solve` wholesale would change the
  iterate path and break bit-identity.
- **The five-concern decomposition — done 2026-08-15** (commit `2d3b9b9`): `ride_program.gd`
  split at the solve seams into `ride_prefix_solve.gd` and `ride_return_solve.gd`,
  byte-identical routes SHA-verified. The former deferral said do it when issue 24 forces
  changes there, not speculatively — issue 24's stages fired that trigger.

Not adjusted, deliberately: the flat `godot/` layout (19 production files, prefix-grouped by
name — a directory move would rewrite ~40 preload paths, the `.uid` files, `main.tscn`, the CI
manifest and every doc reference for modest gain), and the name `_inspect.gd`, whose leading
underscore reads as private though it is a documented user-facing command (54 references, most
in historical plans).

## Audit coverage for issues 1–16

**The range in this heading is a code contract, not prose.** `1..16` is hardcoded in
`godot/fidelity.gd` (`_validate_issues` rejects any issue id outside it), in
`godot/fidelity_artifacts.gd` (`range(1, 17)` builds the coverage records), and in two focused
suites. Issues 17–19 and 20–26 therefore have no coverage record and cannot be referenced from
a catalog target, review prompt, or evidence gap. Extending the audit to the 2026-08-15
findings is a code change in those four places plus `_ISSUE_TEXT`, not a documentation edit —
do it deliberately, or leave 20–26 tracked here only and say so.

The offline fidelity baseline (see README) emits a deterministic traceability record for every
issue in that range: `review/issue-coverage.json` and `review/issue-coverage.md` under
`INSPECT_OUT`, with `review/checklist.md` holding the review prompts and `audit.md` holding the
evidence snapshot, POV map, and gap list. Each record links the issue to the evidence IDs,
review prompts, and generated artifacts that bear on it.

**No issue here is closed by an audit result.** As of the 2026-08-11 baseline, every one of the
sixteen is in state `review-prompt` or `evidence-gap`: catalog
`2026-08-10.evidence-baseline.2` holds no `executable` source and empty `selectors`,
`observations` and `targets`, so the run legitimately produces zero findings and the
recommendation `no-eligible-finding`. That is the contracted output for an empty eligible set —
it records that nothing was eligible to compare against, not that the ride is right. A
diagnostic number, a green run, or an unlinked artifact is never sufficient to mark a
ride-quality issue solved; only measurement against reviewed evidence, or an explicit user
decision, closes one.

### Promoting a finding to a hard gate

A finding becomes an enforced gate only through a new Superpowers design cycle that establishes,
in writing and in code:

1. Reviewed **executable** evidence — a committed source artifact or content digest, retrieval
   date, exact window, axis mapping, row/seat, transform ID, confidence rationale, and the
   required corroborating links. Corroborative, observation-only, and review-pending sources
   cannot define a band.
2. An explicit **threshold and scope**: which metric, which axis and polarity, which selector
   and window role, which seeds, and what counts as a miss.
3. A **focused failing test** that fails before the change and passes after, plus a decision on
   whether the check joins the smoke gate or stays diagnostic.
4. Proof that the promoted gate **cannot be satisfied by cheating**: it must not reward geometry
   smoothing, a fitted or clamped radius, a viewer-only path, or hidden drive. Generated
   positions stay raw integrator output; any filtering must be the labelled human-tolerance
   filter or a catalogued evidence comparison.

Optional local `RFDB_4804_CSV` / `RFDB_6383_CSV` overlays are diagnostic-only. They do not
modify the committed catalog, create catalog selectors, observations or targets, create
fleet-comparison findings, promote a source to `executable`, or satisfy the evidence requirement
above.

## Known limitations of the baseline itself

- Plan role `targets`, `phases`, and `recipe_id` (e.g. the Immelmann's declared
  `vertical_excursion_m`) are published in the accepted route's `terrain_story_plan` but no
  code measures or enforces them — only `length_m` and the three terrain intents are proven
  against the built ride. Confirmed by the 2026-08-15 pre-push review; enforcing them the way
  `_validate_role_lengths` enforces lengths is deliberate next-cycle scope (the planned
  Immelmann re-scale exercises exactly those fields).

- The radius strip in the channel sheets is degenerate. Near-straight track yields enormous
  finite radii, so the linear plot range runs to ~5.4e8 m (seed 42), ~7.7e8 m (seed 11) and
  ~8.0e8 m (seed 20260809), collapsing all small-radius detail onto the baseline. The sidecar
  legend declares the non-finite (`unbounded`) counts honestly, but the strip is not usefully
  readable as drawn. Lives in `godot/fidelity_artifacts.gd`.
- Issue coverage links only `review/seed-42/channels.png` as the generated artifact for every
  issue, and only issues 9, 12, 14 and 15 carry their real titles — the rest render as
  "Issue N". The top, elevation, and element side views are written and hashed but never linked
  from the coverage record, so the support-overlap and element-shaping prompts point at a
  channel sheet rather than the views they ask for.
- The POV map is entirely gaps because no source landmark has a committed alignment. Supplying
  either optional RFDB export still renders diagnostic seed-42 midpoint POVs for supported
  side-view beats;
  those frames neither resolve nor promote an alignment.

## Where the POV and force-diagram links already live

They are committed — nothing needs re-researching. All twelve catalogued sources are in
`docs/evidence/fidelity/source-manifest.json` (retrieved 2026-08-10), each with its URL,
`current_state`, permitted axes, promotion prerequisites, and the SHA-256 of its metadata
artifact. Per-source records sit alongside it in `docs/evidence/fidelity/rideforcesdb/` and
`docs/evidence/fidelity/youtube/`, and `godot/fidelity_references.gd` carries the same URLs as
inert provenance strings. There is no network client anywhere in `godot/` — these are records,
not fetches.

- **Force diagrams (RideForcesDB)** — Falcon's Flight `?id=4804`; Tormenta `?id=6369` and
  `?id=6383`. All three are `corroborative`; 4804 is flagged unreliable and cannot promote
  alone. `docs/evidence/fidelity/catalog-review.md` records that raw acquisition was blocked.
  Local CSV exports for the diagnostic overlay are hash-pinned in
  `rfdb-local-overlay-manifest.json` and supplied via `RFDB_4804_CSV` / `RFDB_6383_CSV`.
- **POV video (YouTube)** — nine sources: Falcon's Flight forward `cUURkqyn4Zs`, backward
  `J54WKu2nU6o`, `poco8rOnW18`, `sdXGD9kMR7s`, CGI `NFVNGgwZk3c`; Tormenta forward
  `AHjk2R4da_I`; CoasterTalk continuous `0UaOSBGSx20` and edited `seNRpi4wP-s`; I305 overlay
  `wX7uHKj-Ujc`. Two are `corroborative`, three `observation_only`, four `review_pending`
  (the manifest's overall tally is 5 corroborative / 4 review_pending / 3 observation_only,
  with the three RideForcesDB sources making up the other corroboratives).
  No frames, audio, or copyrighted content are committed — metadata and timestamps only.

**None is `executable`**, which is exactly why the audit emits `no-eligible-finding`. Grounding
any issue above in measurement means promoting a source through
`docs/evidence/fidelity/catalog-review.md` and the four-part bar in *Promoting a finding to a
hard gate* — the links being present is not the same as the evidence being usable.

27. Dense-output kinematic defect metric is tautological. Motion.gd's `max_kinematic_defect_mps`
    compares `_dense_velocity(...)` against `sample.tangent * sample.speed_mps`, but `_dense_sample`
    defines tangent and speed as `velocity.normalized()` and `velocity.length()` from the same
    `_dense_velocity` call, so the metric measures `v.distance_to(v.normalized() * v.length())`
    — Float32 round-trip noise, measured constant 5.7220459e-06 on all three deep seeds
    (11/42/20260809) to every printed digit. Consequence: `motion_tests.gd`'s defect gate
    ("dense output measures its actual dr/dt minus returned vT defect", threshold 1e-5, around
    lines 436-438) cannot fail. The honest fix is comparing against the independently interpolated
    speed/tangent channels — but that changes published bits (the metric feeds nothing else;
    verify which before claiming), so it needs its own measured stage; **not fixed deliberately**,
    to preserve the bit-identity contract. Evidence source: the 0b36657 task review (2026-08-16).

## Recommended approach

Compare the ride element by element against real high-thrill coasters — not just the two
named references. Use RideForcesDB (raw per-recording traces are decodable; multiple
recordings of one ride can be cross-checked) and similar sources, plus POV video extraction
and analysis, to ground every element class in measured reality and in how the real thing
*feels*. Discovery is the point: ride it, trace it, and chase whatever looks or feels wrong,
whether or not it is on this list.
