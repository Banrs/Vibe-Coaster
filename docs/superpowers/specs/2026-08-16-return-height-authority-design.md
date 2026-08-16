# Return height authority: the height-a peak as the eighth solved control (2026-08-16)

The stage `docs/ISSUES.md` named as the current spend, executed and landed. The return's
height-beat peak g stops being a fixed per-seed constant and becomes the eighth control of the
bounded return solve, seeded from the planner's certified draw. Everything below is measured;
where a measurement contradicts an in-flight claim, the measurement is recorded and wins.

## 1. Derivation: why a solved control, and why these bounds

All seven prior return controls are durations and bank angles. None of them can move the
capture-gate height without moving everything else through it — the honest-drag refusal
(`2026-08-15-honest-drag-derivation.md` §7.2) and issue 24's floor-pinned swap exhaustions both
measured the solve short of exactly that degree of freedom. The height beats are authored at
fixed peak g, so each beat's rise scales with `v²` and the solve has no way to hold a beat's
rise when the arrival speed moves.

The control is `height_a_peak_g`, appended to `RETURN_SCALAR_IDS`; height-b's peak follows
proportionally (×0.831) exactly as before, so one control moves both beats coherently and the
one measured pathological corner (strong height-a with weak height-b) stays unreachable.

Bounds **[3.4, 4.6]**:

- Floor 3.4 sits 0.25 g under the certified draw band's floor (3.65), so the solve can unload
  the beat slightly below any drawn value without leaving the beat's authored character.
- Ceiling 4.6 is where height-b's proportional peak reaches 3.82 — still under height-a's own
  3.65–3.95 draw band — so no solved point can make the second beat harder than the first
  beat's authored range.
- Measured on the landed fleet (§3): no accepted canonical point touches either bound; the
  ceiling is exercised only by diagnostic probes (§5), where the solve pins 4.6 chasing height
  it cannot otherwise buy. The envelope never binds: 4.6 g normal is far inside the +8.0 Gz
  duration-stretched limit for these hold durations.

## 2. Ownership resolution: the draw proposes, the solve disposes

The planner's certified `return-height-a`/`peak_g` draw (3.65–3.95, named stream, certified at
both extremes by `ride_planner_tests.gd`) **initialises** the eighth control; the solve owns
closure from there inside the control's own bounds. The committed seven-entry `RETURN_SEED` is
completed deterministically in `_solve_return` from the build's own targets, so no randomness
enters the solve and the fixed fixtures still reproduce the drawn recipe exactly (`_return_spans`
falls back to the drawn target when handed a seven-vector).

Measured consequence on the canonical fleet: every solved peak lands **inside the certified
draw band** — 3.725 (seed 1) to 3.941 (seed 555) — displaced −0.023 to +0.057 from its own
draw, never on a bound. The draw still owns the per-seed variety (solved peaks track draws
nearly 1:1); the solve owns the last few hundredths that close the gate. The certification
contract is untouched: both extremes still build (gated in `ride_planner_tests.gd`), and
overrides still reach the solve as its start.

## 3. Canonical outcome at today's drag: re-certification, declared

Adding a Jacobian column changes every solve trajectory, so bit-identity was measured, not
assumed: all fifteen published route hashes move. **This is a declared re-certification,
15/15**, measured before/after on the same tree (seven-control HEAD vs this commit):

| | seven controls (2026-08-15) | eight controls (this commit) |
|---|---|---|
| fleet builds | 15/15 | 15/15 |
| route length | 8142.63–8196.11 m | 8138.10–8187.32 m |
| length spread | 53.47 m | 49.22 m |
| duration spread | 0.408 s | 0.515 s |
| top speed | 94.63–94.76 m/s | 94.63–94.76 m/s (record band 93.9–95.6 holds) |
| return evaluations | 18–26 | 20–29 |
| capture-entry speed | 79.39–79.99 m/s | 79.47–79.98 m/s (band 70–80) |
| brake peak | 3.006–3.075 g | 3.015–3.075 g (cap 3.6) |
| closest length-ceiling approach (accepted) | ≥ 3.57 m | ≥ 12.43 m |

Every gate that pins the contract re-certifies on the new bytes: record band, entry-launch
band, diversity floors (spreads 49.22 m / 0.515 s against floors 5 m / 0.1 s), loads on the
deep seeds, structure/seams/clearance on all fifteen, same-seed-twice bit-identity. Quoted
canonical numbers in code comments were updated in this commit (`smoke.gd` fleet spread,
`ride_return_solve.gd` budget and aim-margin notes).

## 4. MAX_RETURN_EVALUATIONS: 80 → 88, derived then measured

Same derivation the seven-control cap carried, at n = 8: `BoundedSolver.solve` costs
`1 + K*(n+1) + R` unique evaluations; K ≤ 8 accepted iterations and R ≤ 8 rejections gives
`1 + 8*9 + 8 = 81`, and 88 carries the same seven-evaluation slack over the formula that
73 → 80 carried. Measured on the enlarged space: the canonical fleet spends 20–29 unique
evaluations — inside the unchanged 60 % allowance (52) that `ride_program_tests.gd` gates on
five seeds and `smoke.gd` on all fifteen — and the compiled swap diagnostics converge in 38–70.

## 5. The honest-drag fleet test: REFUSED, and what the residual names

This is the first fleet test of §7.2's wall — everything before it was seed 11 only. Probe
conditions (scratchpad only, nothing committed): `AERO_PER_M 0.00021` plus the §7.1 constants
(launch plateau 1.094 s, LSM2 0.59711 g with the reshaped pull-up 3.22746/0.82272/0.58484,
`PREFIX_SEED[0..1]` 7.7012/3.8044, LSM3 core 1.933 s, camelback `fall_s` 3.20), production
scalar bounds, run through the production compile seam on seeds 11, 42, 20260809.

**In-flight claim, inherited:** with the peak pinned the probe hits a −86.6 m height wall on
seed 11, and with the peak freed the same solve converges to zero. **Reproduction failed under
every disclosed condition tried**, and the claim is therefore recorded as unestablished — the
probe that produced it died with the prior session and its exact configuration is unknown:

- Shipped 70–80 m/s capture band, freed control, draw-seeded: budget-exhausts at 88 and at
  320; stalls at 960 (seed 11: height −92.3 m, cross 99.4 m, entry speed 0.29 m/s under the
  70 floor, peak pinned at the 3.4 **floor** — the solve trades height away chasing speed).
- §7.2's disclosed (40, 90) band, freed, draw-seeded at 959 evaluations plus 24 random starts
  × 319 coarse evaluations per seed: **zero convergences on any seed**. Best stall points
  (unscaled: forward / cross / height): seed 11 −79.1 / 137.5 / **−13.1 m**; seed 42
  −52.0 / 235.3 / −26.4 m; seed 20260809 −79.8 / 196.0 / −43.7 m.
- Same conditions, peak pinned (seven-control HEAD solve), seed 11: best stall
  −20.7 / 192.5 / **−50.6 m**.

**What survives of the paired proof:** freeing the control cuts seed 11's best height miss
about fourfold (−50.6 → −13.1 m) while the entry-speed residual closes — height authority is
real and it is the height member's missing DOF. **What refuses:** no vector closes the pose.
The residual that never yields at honest drag is now the *horizontal* capture placement —
cross-track 137–235 m and station-forward 52–80 m at every best point — with the height couple
riding on it. That is §7.4's other candidate by name: the prefix needs a handoff-pose residual;
a return-side control cannot un-move a handoff displaced 426 m/23.7°. Honest drag therefore
stays refused (`AERO_PER_M` stays 0.000075) and issue 2 stays blocked behind prefix handoff
work, not behind further return controls.

Brake peak and capture-entry acceptance numbers at honest drag were never reached: no probe
passed the return, so no brake solve ran. Recorded as such rather than extrapolated.

## 6. The act-one swap re-measure at today's drag: floor-pinning clears

Issue 24's optional-member swap, re-run through the production compile on the four gated seeds
with the eighth control:

| seed | before (2026-08-15) | after (this commit) |
|---|---|---|
| 11 | converged, 34 evals | converged, 70 evals, recovery 0.448 s off floor, peak 3.678 |
| 42 | **budget-exhausted 79/80, recovery floor-pinned** | **converged, 50 evals**, recovery 0.386 s off floor, peak 3.696 |
| 20260809 | **budget-exhausted 79/80, recovery floor-pinned** | **converged, 38 evals**, recovery 0.293 s off floor, peak 3.704 |
| 4096 | converged, 42 evals | converged, 38 evals, recovery 0.384 s off floor, peak 3.700 |

The floor-pinned exhaustion mode — the half of issue 24's wall this control was a named
candidate for — **clears on exactly the seeds that exhibited it**. Two honest costs recorded:
the converged swap returns graze the route-length ceiling (0.45–1.19 m inside the true 8200 m,
past the 8199 m aim edge within the solver's 2.5 m convergence slack), so the compiled-swap
gate now asserts convergence, the cleared floor and strict true-band interiority instead of an
aim margin the solve no longer buys; and the full swapped build still refuses at the route
contract — `outward-dive` 497.4–497.5 m against 350–490 on **every** seed, `return-turn-b`
570.5–573.2 m on three of four — so the cross/yaw prefix mode stands and **issue 24 stays
open**, its remaining wall now purely upstream of the camelback handoff.

## 7. Before/after of the landed change

- `godot/ride_return_solve.gd`: `height_a_peak_g` appended to `RETURN_SCALAR_IDS` with bounds
  [3.4, 4.6]; `_solve_return` completes the seven-entry `RETURN_SEED` with the build's own
  certified draw; `_return_spans` reads `v[7]` when present and falls back to the drawn target
  for seven-vectors; `MAX_RETURN_EVALUATIONS` 80 → 88 (§4).
- `godot/ride_program_tests.gd`: the budget gate asserts the derived 88.
- `godot/generator_material_tests.gd`: the compiled-swap gate re-founded on the re-measure
  (§6); history comments carry the dated measurements.
- `godot/smoke.gd`: fleet-spread comment re-measured (§3); floors unchanged.
- Docs: this spec; `docs/ISSUES.md` issues 2 and 24 annotated, header rewritten;
  `2026-08-15-honest-drag-derivation.md` §4 unverified-link discharged, §7.2 "production"
  label footnoted and the fifth run's seed stated.

Nothing else moved: `motion.gd` untouched, randomness stays in the planner streams, no
candidate loops, `AERO_PER_M` stays 0.000075.

---

## 8. The composition: two role-band residuals, and the act-one swap builds (2026-08-16)

This section is the ship-once home of the composition stage that followed §7. It is the story of
two pieces that each refused alone and close together, so it lives here — with §6, the piece that
landed — rather than being split across two specs. §11 of
`2026-08-15-prefix-closure-solve-design.md` carries a forward pointer to it and keeps its own
measurements unretracted; nothing there is contradicted, only out-reached.

### 8.1 What each half was, and why neither was enough

- **The prefix half** (§11, built and refused on 2026-08-16): a fifth closure residual `dive_arc_m`,
  the built arc of the `outward-dive` role read over exactly the window
  `route_contract.gd:_validate_role_lengths` measures, aimed at the declared 350–490 m role band
  inset by a margin. Refused there because at the 5 m and 3 m insets it tried, the swap went from
  planning 4/4 to refusing 4/4 or building 2/4 — and the two seeds that did reach the route contract
  were then refused on `return-turn-b`. §11's reading was that the metres it returned were re-spent
  by the return.
- **The return half** (new here): `turn_b_length_band_m`, the eighth return residual — the built arc
  of `return-turn-b` against the plan's declared 430–570 m band, inset 3 m. §11's own diagnosis names
  it exactly: the return spends the returned metres on a role nothing was watching. A residual is
  how the solve watches it.

Neither is a new control. Both are new *observations* of quantities the route contract already
judged after the fact, moved to where a solve can still act on them.

### 8.2 Both residuals are inert on canonical, and the fleet is unchanged

Measured on the fifteen preset seeds, before and after, on the same tree:

- `outward-dive` builds 475.604–476.544 m against 350–490 → ≥ 13.456 m of ceiling headroom, so a
  2 m inset is never reached and `_band_residual` is exactly 0.0.
- `return-turn-b` builds 39–83 m inside 430–570 on every seed, so a 3 m inset is never reached and
  that residual is exactly 0.0 too.
- A residual row that is identically zero contributes a zero Jacobian row, adding exactly 0.0 to
  `JᵀJ` and `Jᵀr`, and adds nothing to the max-abs convergence test. **The fleet geometry is
  bit-identical, 15/15**: every published channel — positions, tangents, ups, rights, banks, speeds,
  distances, times, curvatures, normal/lateral/longitudinal g, roll rates, drive, span and gesture
  indices, terrain, bounds, length, duration — hashes the same before and after. Prefix closure
  evaluation counts are unchanged (1 or 6 per seed), and so are the accepted control vectors.
- What does move is the *published record of the solve*: `terrain_story_plan.planning.closure` now
  names five residuals instead of four and carries the fifth's margins and observation, so the whole
  route dictionary's SHA-256 changes while the ride it describes does not. That is a record gaining
  a row, not a ride moving; it is stated here rather than buried, and no canonical re-baseline is
  declared.

### 8.3 The deciding measurement: the act-one optional swap, end to end, four gated seeds

Production path throughout (`RidePlanner.resolve` → `Terrain.generate` → `_plan` → `compile` →
`Motion.integrate` → `RouteContract.build` → validators). Both residuals live, dive inset 2 m,
turn-b inset 3 m, `MAX_PREFIX_EVALUATIONS` 105:

| seed | closure | return | `outward-dive` (350–490) | `return-turn-b` (430–570) | route | verdict |
|---|---|---|---|---|---|---|
| 11 | converged, 40 evals, 11 iters | converged, 65/88 | **487.96** | **567.30** | 8161.45 m, 157.04 s | **builds** |
| 42 | converged, 29 evals, 8 iters | converged, 60/88 | **488.00** | **567.71** | 8175.81 m, 157.43 s | **builds** |
| 20260809 | converged, 46 evals, 13 iters | converged, 38/88 | **487.98** | **567.69** | 8178.46 m, 157.52 s | **builds** |
| 4096 | converged, 99 evals, 30 iters | converged, 29/88 | **488.02** | **529.93** | 8134.68 m, 157.14 s | **builds** |

Every other declared role band is interior on every seed as well — `tunnel-lsm3` 184.7–184.9 m
(150–220), `camelback` 1111.9–1113.0 m (900–1180), `return-turn-a` 537.0–559.6 m (420–620),
`return-height-a` 303.8–321.7 m (290–480), `return-height-b` 568.3–571.5 m (450–590),
`terminal-capture-brakes` 229.75 m (200–240) — and the route contract and validators are clean.
**The act-one optional swap builds end to end for the first time, 4/4.** `generator_material_tests.gd`
now gates seed 4096's swap on the build rather than on the refusal, and keeps the refusal history in
comments.

### 8.4 The two constants the measurement chose, and how

- **Dive inset 2.0 m.** Bounded below by the solver's own convergence slack on that channel
  (0.02 × the 5.0 residual scale = 0.1 m) — above it, an accepted closure is *structurally* inside
  the declared band, not merely measurably inside. Bounded above by the fleet's 13.456 m of headroom,
  under which canonical stays inert. Inside that window the value is chosen by what builds: at 3 m
  the closure delivers 486.97–487.02 m and seeds 42 and 20260809 build while 11 and 4096 refuse with
  their dive at **487.13–487.16 m** — 2.8 m inside the band they are being refused for, and
  0.06–0.16 m outside an aim ceiling that is itself an inset. At 2 m all four build at
  487.96–488.02 m, still 20× the slack clear of 490.
- **Turn-b inset 3.0 m**, scale 125.0 (the route-length residual's scale, the same units and the same
  hundreds-of-metres magnitude). Here the inset *exceeds* the channel's convergence slack
  (0.02 × 125.0 = 2.5 m), so unlike `RETURN_LENGTH_AIM_MARGIN_M` the interiority an accepted point
  carries is structural rather than only measured — and it is still an order of magnitude inside the
  39 m of canonical headroom. Coarse/fine tolerance 0.075 m, matching the length residual's.
- **`MAX_PREFIX_EVALUATIONS` 52 → 105.** The cap bound: at 52 seeds 11 and 4096 budget-exhausted at
  51. The four-residual solve was square; the five-residual one is over-determined and its accepted
  point sits on a band corner where two residuals are active at once, so LM shrinks its trust region
  approaching it. Measured: 8/11/13/30 accepted iterations, 29/40/46/99 unique evaluations. The
  recorded formula `1 + K(n+1) + R` at K ≤ 16, R ≤ 16 gives 97; the measured worst is 99, because
  near the corner most Jacobian probes are cache hits and the formula's probe term stops being tight.
  105 carries the measured worst with the same ~6 % slack the 49 → 52 step carried. **The CI cost is
  ≈ zero**: before the raise the four swap closures burned the full 51-evaluation budget and refused
  (204 evaluations, no ride); after it they converge in 214 and four rides come out.
  `MAX_RETURN_EVALUATIONS` was **not** re-derived — it does not bind; the swap returns converge in
  29–65 of 88, comfortably inside.
- One honest cost: `PREFIX_EVALUATION_ALLOWANCE` (0.6) sets an absolute canonical bar of 63 rather
  than 31. That bar was never tight — the fifteen canonical closures spend 1 or 6 evaluations — so it
  went from 5× loose to 10× loose. It bounds the solve; it has never pinned it. The refused-story
  gate in `generator_material_tests.gd` now holds those stories to the cap itself rather than to 60 %
  of it, because a non-canonical story is not obliged to be as cheap as a canonical one.

### 8.5 What this does and does not close

- **Does:** the swap's two route-contract refusals (`outward-dive`, `return-turn-b`), and §11's
  conclusion that the dive-arc residual "does not land". §11's measurements all stand; its reach did
  not. It tested the prefix residual alone, and alone it is exactly as it measured itself to be.
- **Does not:** issue 24. The optional-member swap is one of thirty-six grammar-legal act-one orders;
  the other thirty-three are still refused at the *preflight*, upstream of the closure, where the
  head-domain problem §5's correction names still stands. Certifying an act-one permutation draw
  needs the whole legal set to build, not one member of it.
- **Does not:** issue 22. The dive still commits with the approach the closure chooses, and the
  pre-commit approach length on the canonical path is untouched (the residual is inert there).
- **Unchanged and still refused:** the handoff-pose residual framing. Neither probe lane supports it.
  The prefix's terrain-neutral authority is 7–74× short of the displacement it would have to absorb,
  and the swap has no station-frame miss to correct in the first place — its return reaches the
  capture gate cleanly (endpoint |cross| ≤ 0.006 m, |height| ≤ 0.033 m, |yaw| ≤ 0.005°), which is why
  its refusals were role-length refusals and not pose refusals. Honest drag's walls are a cross-track
  *shape* miss of 226–355 m plus height, not a pose the prefix can hand over differently; the one
  measured height lever found there is `cam_fall_s` (+22.45 m terrain-neutral height for −0.372 s),
  recorded for a future honest-drag stage and spent by nothing here.

### 8.6 What landed

- `godot/ride_prefix_solve.gd`: fifth residual `dive_arc_m` (scale 5.0, coarse/fine tolerance
  0.05 m), observed over the route contract's own role window; `MAX_PREFIX_EVALUATIONS` 52 → 105.
- `godot/generator.gd`: `DIVE_ARC_AIM_MARGIN_M := 2.0`; `_closure_target` takes the `outward-dive`
  role's declared band and publishes the inset aim.
- `godot/ride_return_solve.gd`: eighth residual `turn_b_length_band_m`
  (`RETURN_TURN_B_AIM_MARGIN_M := 3.0`, scale 125.0, tolerance 0.075 m), a `_role_arc_m` helper that
  reads a role's arc over the contract's own window, and `turn_b_length_m` in the return observation.
- `godot/ride_program.gd`: the layout carries the plan's declared `return-turn-b` band; a plan that
  declares none leaves the residual inert.
- `godot/generator_material_tests.gd`: the swap gate is now an end-to-end build gate; history kept.
- `godot/ride_program_tests.gd`, `godot/smoke.gd`: residual-count assumptions read the constant.

`motion.gd` untouched, no candidate loops, randomness still only in the planner streams and terrain.
