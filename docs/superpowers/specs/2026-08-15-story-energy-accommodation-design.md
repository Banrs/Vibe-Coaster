# Story Energy Accommodation — Design

> **REFUSED BY ITS OWN §9.1 MEASUREMENT (2026-08-15). Do not implement §3.** The deciding
> measurement this design demanded before any code was run, and it refuted the mechanism rather
> than sizing it. The re-target was then implemented and run anyway, to measure rather than argue,
> and it makes the blocked stories *worse*: all four seeds now refuse at the prefix closure where
> today all four plan. The measurement, the numbers it replaces, and what the swap actually needs
> are in §10 below; §§2–5 are kept verbatim as the refuted reasoning, not as guidance.

**Status:** proposed direction (2026-08-15). The prefix-side follow-on named by `2026-08-15-prefix-closure-solve-design.md` §5 and
disclaimed by `2026-08-15-return-seed-derivation-design.md` §5 ("role-length overruns on a reordered act one is a prefix-geometry
cycle, not this one"). **Authority:** user decisions → physical derivation + verified evidence → vision docs → code. Nothing here
overrides `CLAUDE.md`'s contract, the envelope, the 7800–8200 m route band or the record bands. Numbers are *measured* (with
citation) or *derived* (with the measurement that replaces them, §9).

## 1. The measured problem

`godot/generator_material_tests.gd:188-211` and `docs/ISSUES.md` (issue 24, stage 4): under the act-one optional swap the closure
**accepts `PREFIX_SEED` unchanged on every seed**, the whole prefix is seed-independent to three decimals, and `outward-dive` runs
**497.43–497.46 m against its declared 350–490 m band** (canonically 475.6–476.5). Downstream `return-turn-b` runs 571–574 m against
430–570, and seeds 42 / 20260809 need **4.9–8.1 m more route than 8200 m allows**. The return provably cannot create those metres
(`ride_return_solve.gd:28-68`: the recovery floor is certified from *above*, the length aim margin is headroom, not slack). Seeds
11 and 4096 close their returns and still refuse on the dive band. The solve never compensates because **no residual observes the
pre-dive energy state.**

## 2. The physics: how hot, and why residual 4 is blind to it

The model is frictionless — normal forces do no work, drive is an authored acceleration — so the prefix tail is exactly an energy
ledger. **The dive's arc is an energy readout.** Its spans are fixed durations, so `Δarc = ∫Δv dt` with `Δv = ΔE/v`. Integrating
`dt/v` over the dive's ≈ 11.7 s of authored spans gives ≈ 0.33 s²/m, so the measured **+21 m of arc is ΔE ≈ 63 J/kg** — ≈ 6.4 m of
head, **≈ +3 m/s at a ~20 m/s dive entry**. *Derived from the recorded length; §9.1 replaces it.*

**Residual 4 sees that same 63 J/kg as ≈ 0.67 m/s**, because `ΔV = ΔE/v` and the tunnel exit runs at ≈ 94.5 m/s.
`RECORD_EXIT_SPEED_BAND_MPS` is 93.9–95.6 and `_inner_band` keeps `AIM_BAND_INTERIOR_FRACTION = 0.4`: an aim band **0.68 m/s wide**,
inside which `_band_residual` is exactly flat. In energy that flat region is 0.68 × 94.5 ≈ **64 J/kg** — the size of the miss, and
the measured record-exit margins on placed stories (+0.51…+0.83 m/s inside band) are exactly a surplus sliding across a flat region
without touching an edge. LSM3 does not mask it by adding energy: its drive is an acceleration, so it adds a **fixed** `∫a dt =
(0.15 + 1.633337 + 0.15) × 1.33 g = 25.22 m/s` whatever the entry. What masks it is speed — the same band width is **4.7× coarser in
energy** at 95 m/s than at 20 m/s. Residual 1 misses it too: `dive_edge_span_m` is the *outward projection*, aimed within
`DIVE_SPAN_AIM_HALF_WIDTH_M = 6 m` of the terrain's chord, while 21 m of arc distributes across three axes and a rotating frame.
Projection and arc are only loosely coupled; that is the hole.

## 3. Mechanism: re-target residual 4 to the dive entry — the system stays 4×4

**Chosen: re-target, not a fifth control.** Replace `record_exit_speed_mps` with `dive_entry_speed_mps` —
`trajectory.speed_mps[first]` at the sample `RidePrefixSolve._prefix_observation` already locates for `summit_rise_m`. No new
control, no new integration. The record stays pinned **by derivation, not by hope**: residual 3 pins the dive-entry height,
placement pins the exit onto the apron floor, energy is conserved through the dive, and LSM3 adds a fixed 25.22 m/s, so `v_record =
sqrt(v_entry² + 2g·Δh_dive) + 25.22`. Pinning `v_entry` at a pinned entry height *is* pinning the record — more tightly than today,
since the same band width buys 4.7× more energy resolution. Record exit stays observed and becomes a **strict acceptance
inequality** against 93.9–95.6 (fleet-gated ≥ 0.4 m/s margin, closure design §6), reported in the closure plan; it stops being a
*driven* residual, and smoke's record gate stays the authority.

**Why not 5×5.** A fifth control (closure design §9 named `climb/powered-settle`, 0.98 s) plus a fifth residual re-derives the
budget by the same formula `1 + K(n+1) + R` at n = 5, K ≤ 8, R ≤ 8 → 57 → `MAX_PREFIX_EVALUATIONS := 60`, and one more Jacobian
column per iteration (+20% evaluations). Budget is not the objection — the landed 4×4 converges in **1–6 of 31 allowed evaluations**
on all fifteen seeds. **Conditioning is**: `climb_core_s` and `climb/powered-settle` are adjacent spans on the same drive at nearly
the same speed, so their columns are near-parallel and the 5×5 would be worse conditioned than the 4×4 it replaces. Build it only if
§9.2 measures the 4×4's conditioning degrading past the return's measured 6.2e5–2.5e6.

## 4. The absorber and its authority

`climb_core_s` (`climb/powered-core`, seed 8.78838861 s, bounds 6.0–12.0) is the natural absorber: the LSM2 assist length, setting
crest energy directly, downstream of act one (so the head still integrates once per solve), moving no authored force. Its authority
is `dE/dt = a_drive · v = 0.29367873763844 g × v_core = 2.880 v_core` J/kg per second. **A hotter story shortens the core, a colder
one lengthens it** — symmetric, both inside the bounds. The limit is not the control bound but `climb-lsm2`'s four declared claims:
length 520–680 m, `exit_speed_mps` 14–24, `height_delta_m` 200–225, `drive_distance_fraction` 0.65–0.80. One second of core costs ≈
`v_core` metres of role length and `2.880 v_core` J/kg, so **if `v_core` is in the 40–60 m/s class, 63 J/kg is ≈ 0.4 s and ≈ 20 m**
— an order of magnitude inside a 160 m-wide band, with the height and exit-speed claims re-closed by `climb_pull_over_s` against
residual 3 — what a coupled 4×4 is for. Derived, not measured: **§9.2 measures `v_core`, the canonical climb-lsm2 length inside
520–680, and all four claim margins under the swap.** If height or exit-speed binds before length, the absorber becomes the pair
(`climb_core_s`, `climb_pull_over_s`) — a re-weighting, not a different design.

## 5. Role-band ruling: hold both bands, absorb upstream

1. **The extra arc buys nothing.** The dive's authored force profile is unchanged under the swap; only its speed is higher. Its
   counterpart claims in `docs/evidence/fidelity/counterpart-bands.md` §13 are *force and hold-duration* claims (Gz− −0.52 g × 1.5 →
   −0.78 g over 1.14 s; pullout 2.99–5.02 g over 1.58–3.0 s), untouched by arc length either way. **No counterpart evidence speaks
   to dive arc length at all**, so none licenses widening: widening on "it came out longer" is a band moved to fit a number.
2. **The ceiling binds first, and it is a user contract number.** 7800–8200 m is fixed, the return cannot create metres, and 42 /
   20260809 are 4.9–8.1 m short. Widening 490 → 500 relocates the refusal to the route ceiling without curing it. Absorbing the 63
   J/kg instead **returns the whole +21 m to the route budget** — 2.6–4.3× the shortfall — which is also the expected mechanism for
   `return-turn-b`'s 571–574 m: the return gets its metres back and re-closes inside 430–570.
3. **Symmetry.** A colder legal story would run the dive under 350 m and the ruling reverses: lengthen the core, do not drop the
   floor. A band that moves per story is not a claim.

**Ruling: both bands hold; the energy is the thing to fix.** If measurement later shows the swap inside every role band and still
over 8200 m, that is a *different* finding — the story is longer than the route band — reported as such, never hidden by a band.

## 6. Canonical bit-identity

The local idiom: `RETURN_LENGTH_AIM_MARGIN_M`'s "aim margin inside the flat region, sized from the fleet's own measured headroom"
(`ride_return_solve.gd:47-67`). The `dive_entry_speed_mps` aim band is derived so that **every canonical observation on the fleet —
seed, Jacobian probe, rejected trial and accepted point, at both step sizes — lies strictly inside it**, where `_band_residual`
returns exactly `0.0` as the record residual does today. The solver then sees a bit-identical residual vector and accepts
`PREFIX_SEED` on exactly the seeds it accepts it on today: an IEEE-754 identity, not an approximation, gated as the fifteen-seed
route SHA-256 set unchanged. The prefix being seed-independent to three decimals, the canonical spread is expected ≪ 0.1 m/s against
a ≈ 3 m/s swap delta, so such a band exists with room to spare — **confirmed by §9.1; if the spread is not small, the band is
derived from the measured spread rather than assumed.**

## 7. Certification

**Acceptance:** the swap **builds end to end** on 42 and 20260809 (the measured blockers), inside every role band, ≥ 1 m interior to
7800–8200 and ≥ 0.4 m/s interior to 93.9–95.6; ideally it still plans 15/15 and compiles on 11 / 4096. A seed that refuses is
reported with its binding claim, not accommodated. **Unchanged gates:** all twelve focused suites and every `smoke.gd` gate
(structure, seams, clearance, loads, record and entry-launch bands, diversity floors, same-seed bit identity), the ≤ 60%
`MAX_PREFIX_EVALUATIONS` gate, and the closure design's four fleet margins. **New gates:** (a) fifteen-seed route SHA-256 unchanged;
(b) fleet record-exit acceptance margin ≥ 0.4 m/s; (c) the swap compiles end to end on 42 and 20260809; (d) `climb-lsm2`'s four
claim margins reported per seed. **CI cost:** zero on the canonical fleet — one array read per observation, no extra integration,
unchanged evaluation counts (§6). The new cost is the end-to-end swap builds, ≈ 9 s local / ≈ 18 s ubuntu-serial each
(`generator_material_tests.gd:213-218`); budget it by **replacing** the return-only swap compile on seed 4096 with full builds on 42
and 20260809 — net ≈ +9 s local, ≈ +18 s serial CI.

## 8. Implementation sketch (TDD, one bounded stage, four tasks)

1. **Measure first (§9.1–9.2), in the test comment.** No production change; guessing these numbers is what this design forbids.
2. **Re-target residual 4.** Failing test first: the closure plan reports `dive_entry_speed_mps` with its `_closure_target` band
   derived from Task 1's spread, and the fifteen-seed route SHA-256 set is unchanged. Record exit becomes a reported acceptance
   inequality; `PREFIX_RESIDUAL_IDS`, `_SCALES` (propose 0.2 → 0.5, replaced by Task 1's number) and `_FINE_TOLERANCES` move
   together.
3. **The swap builds end to end.** Failing test first: §7's acceptance on 42 and 20260809. A seed that still refuses reports its
   binding claim — never a widened band.
4. **Report.** Conditioning, evaluations and all five margins printed per seed in smoke; the §7 compile-seed swap landed. A moved
   committed hash is a failure, not a re-baseline.

## 9. What is not measured, and exactly how

1. **The deciding measurement.** Build 11 / 42 / 20260809 / 4096 twice — canonical and `_act_one_optional_swap()` — recording at the
   `cliff-dive` gesture's first sample **speed, height and specific energy `0.5v² + g·h`**; plus the canonical fleet spread of that
   speed across all fifteen seeds and every solver evaluation at both step sizes. Replaces §2's derived numbers and sizes §6's aim
   band. Everything else here is conditional on it.
2. **The absorber's authority.** Same runs: `climb/powered-core` mean speed, `climb-lsm2` role length and its three target margins,
   and the 4×4's conditioning under the swap. Decides §4 and §3's 5×5 question.
3. **Colder stories are unmeasured.** The airtime-dropped order (places 9/15) is the available probe; its dive arc against 350–490
   tests §5's symmetry claim. Not in this stage's acceptance — record it while the harness is open.
4. **Head-domain stories stay out of scope.** Opener ±0.005 g refuses at the terrain preflight (chord 245–408 m against a ~270 m
   terrain span). No residual re-targeting reaches that; head accommodation is its own cycle.

## 10. The §9.1 measurement, and what it refuses (2026-08-15, this dev box, Godot 4.7.1)

### 10.1 The deciding measurement

At the `cliff-dive` gesture's first sample, on the accepted closure's production integration, canonical vs `_act_one_optional_swap()`:

| seed | variant | dive-entry speed | entry rise | `0.5v² + g·h` | record exit |
| --- | --- | --- | --- | --- | --- |
| 11 | canonical | 18.568518 | 285.2679 | 2969.918 | 94.661518 |
| 42 | canonical | 18.572704 | 286.5425 | 2982.494 | 94.709589 |
| 20260809 | canonical | 18.541916 | 286.3479 | 2980.015 | 94.730196 |
| 4096 | canonical | 18.566672 | 285.3389 | 2970.579 | 94.666000 |
| all four | swap | 21.003114 | 282.4188 | 2990.148 | 94.685675 |

The swapped prefix is identical on all four seeds to six decimals, confirming §1. **Δ(dive-entry speed) = +2.430…+2.461 m/s**
against §2's derived ≈ +3 m/s (over by ~1.23×), **ΔE = +7.7…+20.2 J/kg** against §2's derived ≈ 63 J/kg (over by 3.1–8.2×), and
the swap arrives **2.85–4.12 m lower**, so most of what it gains it gains as speed, not head.

**§6's aim band exists with room to spare, as predicted.** Every canonical observation on the fifteen preset seeds — seed, Jacobian
probe, rejected trial and accepted point — runs **18.530671–18.605595 m/s** across the 65 coarse evaluations and 18.531436–18.587656
across the 15 production ones; the worst coarse/fine gap is **0.000840 m/s**. A ±0.10 m/s band `[18.43, 18.71]` holds all of them
strictly interior, where `_band_residual` is exactly `0.0`.

### 10.2 What it refuses

1. **§2's mechanism.** The +21 m of dive arc is not an energy surplus the climb can absorb. Measured at *equal* dive-entry speed
   (18.93 m/s, `climb_core_s` = 6.0), the canonical dive runs 476.5 m and the swapped one 498.2 m — still +21.7 m. The arc against
   `climb_core_s` is U-shaped with its minimum at the authored seed (canonical 476.2 m at 8.788 s, 487.7 m at 6.0 s, 502.6 m at
   12.0 s; swap 497.1 m at 8.788 s, 498.2 m at 6.0 s, 539.9 m at 12.0 s). **The swap's dive arc never reaches 490 m anywhere in
   `climb_core_s`'s 6–12 s bound** — its minimum is ≈ 494.5 m at 8.0 s — and over the whole (`climb_core_s`, `climb_pull_over_s`)
   grid that keeps `summit_rise_m` inside its aim band the minimum is 497.1 m, at exactly the 21.00 m/s the story already has.
   Lowering the entry speed *lengthens* the arc (505.0 m at 19.77 m/s). §4's absorber has the wrong sign for the job.
2. **§3's record derivation.** "Pinning `v_entry` at a pinned entry height *is* pinning the record" is false as measured: inside the
   summit-rise aim band the swapped story's record exit runs **94.31–97.94 m/s** while the dive-entry speed moves only
   19.77–22.04 m/s. Speed and height at one sample do not determine the tunnel exit, so demoting the record to an inequality
   removes a pin nothing else replaces.
3. **§5's ruling survives, its arithmetic does not.** Both role bands still hold — but "absorbing the 63 J/kg returns the whole
   +21 m to the route budget" is void, because there is no 63 J/kg and no setting of the four controls returns the metres.

### 10.3 The re-target, implemented and run

Residual 4 → `dive_entry_speed_mps` (aim band `[18.43, 18.71]`, scale 0.5, `PREFIX_OBSERVATION_IDS` five long, record exit demoted
to a strict acceptance inequality against 94.30–95.20 m/s), 4×4 kept, `MAX_PREFIX_EVALUATIONS` untouched:

- **Canonical is bit-identical**, exactly as §6 argued: every accepted control vector, every evaluation count (1–6 of 31) and every
  built length unchanged (11: 8175.954 m, 42: 8142.633 m, 20260809: 8172.663 m, 4096: 8165.445 m).
- **The swap refuses on all four seeds, at the prefix closure** — strictly worse than today, where all four plan:

| seed | solver | residuals | why it refused |
| --- | --- | --- | --- |
| 11 | converged, 51 evals | −0.0152, 0.0, −0.0179, 0.0024 | record exit 97.18 m/s, +1.98 over the accepted band |
| 42 | budget_exhausted 51/51 | −0.3151, 0.0, −0.0268, 0.7094 | dive entry +0.355 m/s over its ceiling, record +1.56 over |
| 20260809 | budget_exhausted 51/51 | −0.0484, 0.0, −0.0237, 0.1944 | dive entry +0.097 m/s over its ceiling, record +1.87 over |
| 4096 | converged, 33 evals | 0.0, 0.0, −0.0100, 0.0153 | record exit 97.03 m/s, +1.83 over the accepted band |

For the record, the same four seeds' end-to-end blockers **without** the re-target: seeds 11 and 4096 reach the route contract and
are refused on `outward-dive` 497.4 / 497.5 m (band 350–490) and `return-turn-b` 572.6 / 571.2 m (band 430–570); seeds 42 and
20260809 never reach it, their seven-control return solve budget-exhausting at 79 of 80.

### 10.4 What the swap actually needs

The only control that moves the dive's arc without moving its entry state is `dive_approach_s`, the one control inside the dive
itself: the swap's arc falls 497.1 → 490.8 → 487.6 m at 1.00 / 0.60 / 0.40 s, with the dive-entry speed unchanged to four decimals
(`∂v_entry/∂dive_approach_s` is exactly zero — the approach is downstream of the entry sample). So the accommodation is a **dive-arc
residual**, not a dive-entry-speed one — and it lands on issue 22's knob, whose shortening was already refused by measurement
because it moves the camelback handoff ~10 m and the fixed-seed return solve does not re-converge. That makes the honest order:
**the deterministic per-story return-seed derivation first**, then a dive-arc residual with `dive_approach_s` as its absorber. Until
the return can re-converge for a moved handoff, no prefix-side residual can buy the swap a build.
