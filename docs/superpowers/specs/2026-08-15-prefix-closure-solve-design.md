# Prefix Closure Solve — Design

**Status:** proposed direction (2026-08-15). Issue 24's named first step, and the root-cause fix behind
the three measured refusals in `docs/ISSUES.md` (*The recommended next work*): act-one permutation, the
opener roll tranche of issue 20, and the opener/act-one target draws. All three failed for one reason —
the story prefix has no closure solve of its own, so its terminal geometry must be hit by coincidence.

**Authority:** user decisions → physical derivation + verified evidence → vision docs → code. Nothing
here overrides `CLAUDE.md`'s generator contract, the envelope, or the record bands. Timings were
measured on this dev box (Godot 4.7.1, scratchpad copy of `godot/`); ubuntu CI runs ≈ 2× slower, and
performance verdicts still come from CI.

## 1. What is rigid today

`RideProgram.terrain_story_capability` (`godot/ride_program.gd:93`) integrates the whole prefix once,
in the station-local frame, at `PRODUCTION_STEP_S`, and publishes a *fixed* footprint: the dive-entry
pose, the dive/tunnel exit offsets, the sampled dive and station/opener corridors. Every span in
`_add_story_prefix` (`:310`) is a hardcoded duration over an authored force profile, so that footprint
is a pure function of the force literals.

`RideGenerator._plan` (`godot/generator.gd:113`) then does terrain-relative arithmetic on that fixed
footprint: it picks the yaw solution (`outward_local`, `:194-211`), derives the feasible dive-entry
edge band (`:244-251`), draws a point in it on `STREAM_PLACEMENT` (`:258`), and hands the whole thing
to `_solve_dive_placement` (`:331`). That grid search is the only adaptive element in the prefix, and
it adapts in one degree of freedom: it slides the station along `inward` in 0.25 m
`TERRAIN_PLACEMENT_STEP_M` steps and takes the first candidate whose required station height leaves
the summit inside `SUMMIT_TRACK_AGL_BAND_M` (15.01–24.95 m). A rigid translation cannot change a
chord, a rise, or an entry speed, so *all* prefix variation must be absorbed by ~10 m of summit slack
and a few tens of metres of edge band — against a measured **+114.8 m of dive chord per +0.005 of one
lateral-g literal** (`godot/ride_planner.gd:63-82`). The ride's most expressive section is frozen by a
search that can only move it, never reshape it.

The return already solved the analogous problem. `_solve_return` (`godot/ride_program.gd:901`) runs one
`BoundedSolver.solve` over `RETURN_SCALAR_IDS`, targets `RETURN_RESIDUAL_IDS` — a mixture of exact
station-frame equalities and `_band_residual` (`:1052`) band targets — checks coarse/fine agreement and
inequality margins, and fails structurally. This design gives the prefix the same treatment.

## 2. Where the solve sits

Three stages, in order, with no nesting and no candidate loop.

**P — preflight (unchanged shape, unchanged cost).** `_plan` calls `terrain_story_capability(side,
story)` exactly as it does today, with the drawn story and the *seed* control values. Its footprint is
used only to choose the yaw frame (`outward_local`, `tangent`, `right`) and to prove the terrain can
host a dive at all. It is a preflight, not a candidate.

**S — the closure solve (new).** `_plan` derives a **closure target** — closed-form terrain arithmetic,
no integration — and calls `RideProgram.terrain_story_capability(side, story, closure_target)`. With a
target present, the capability runs one `BoundedSolver.solve` over four flex-span durations, then
re-publishes the same footprint dictionary from the accepted solution; the published contract at
`ride_program.gd:156-171` is unchanged in *shape*.
**Correction (2026-08-15, Stage-2 review, measured):** "no downstream consumer moves" was wrong —
`compile()` builds the production route from the authored span durations, so the accepted control
vector MUST thread from the solved capability into `compile()` (via the plan), or the ride would be
built from `PREFIX_SEED` while placement uses the solved footprint. Stage 3 carries that threading,
plus the constant one-step offset between the residual's terminal tunnel sample and the published
pre-seam `[-2]` sample that placement actually consumes.

**F — placement (shrinks).** `_solve_dive_placement` keeps its clearance scans and loses its search
(§3).

The target is computable before the solve because it is built only from terrain-and-frame quantities
already present in `_plan`: `shelf_edge_m`, `apron_width_m`, `DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M`,
`DIVE_EXIT_APRON_BAND`, `TUNNEL_EXIT_PLAIN_OVERSHOOT_M`, `SUMMIT_TRACK_AGL_BAND_M`, the record band,
and the preflight `outward_local` axis (`terrain_dive_span_m`, `generator.gd:172`, is already
terrain-only and becomes the chord target's spine). The generator stays the terrain-relative planner
and `RideProgram` stays terrain-agnostic: what crosses the boundary is a small dictionary of
station-local bands plus the projection axis.

### Controls (four, all durations, all downstream of act one)

| id | span | authored today | why it is safe to solve |
| --- | --- | --- | --- |
| `climb_core_s` | `climb/powered-core` (`ride_program.gd:349`) | 8.78838861 s | LSM2 assist length: sets crest energy. Bounded by the `climb-lsm2` role's 520–680 m length, 14–24 m/s exit and 0.65–0.80 `drive_distance_fraction`. |
| `climb_pull_over_s` | `climb/pull-over` (`:353`) | 3.20659393 s | Trades summit rise against forward run at fixed authored endpoints (0.874 → 0.722 g). No force value moves. |
| `crest_hold_s` | `rim/slow-crest-core` (`:380`) | derived from 3.5816 s | A flat hold at the drawn crest normal. Changes no force, changes where the rim sits over the edge. |
| `dive_approach_s` | `dive/face-approach` (`:418`) | 1.00 s | How far the car runs banked at 25° before committing — the issue 22 knob. |

Every control is a **duration**; no g value, roll rate, drive level or pulse shape becomes one.
Rider-feel-critical forces stay authored — the solve buys closure with time, not with the force trace.
Bounds are declared per control and certified at both extremes on the fleet, the way
`ride_planner_tests.gd` certifies draw ranges.

### Residuals (four; a square system, like the return's 7×7)

1. `dive_edge_span_m` — the dive's outward run projected on `outward_local`, banded so the apron can
   host it and the exit lands inside `DIVE_EXIT_APRON_BAND`.
2. `tunnel_edge_span_m` — dive-exit → tunnel-exit, banded to clear `TUNNEL_EXIT_PLAIN_OVERSHOOT_M` and
   keep `tunnel-lsm3` inside its 150–220 m role band.
3. `summit_rise_m` — the prefix's rise above the plateau, banded to the interior of
   `SUMMIT_TRACK_AGL_BAND_M`: precisely what today's grid search hunts for and reports as
   `lowest_required_summit_agl_m` when it fails (`generator.gd:412-417`).
4. `record_exit_speed_mps` — tunnel-exit speed, banded to the interior of the gated 93.9–95.6 m/s
   record band. This pins the record *and* freezes the camelback handoff, which is what the return
   solve's fixed `RETURN_SEED` basin depends on: the permutation refusal was measured as a 2.5–4.4 m/s
   hotter dive handoff breaking the return on 12 of 15 seeds (`ride_planner.gd:41-48`).

All four are `_band_residual` targets against an **inner aim band** (the middle ~40% of each feasible
band), so a converged solve sits interior by construction and the margin is measured, not hoped for.
Heading is deliberately not a residual: four controls cannot fix six DOF, and the yaw construction
(`generator.gd:218`) already absorbs the residual heading exactly as it does today.

## 3. Interaction with `_solve_dive_placement`

Placement does not shrink to a coarse seed and the solve does not chase a placement-chosen corridor.
The order is preflight → target → solve → closed-form placement, so neither ever runs inside the other.

`_solve_dive_placement` keeps everything that is an *evaluation* — the dive-corridor clearance scan,
the station/opener lower-spine scan, the reserved terminal-approach scan (`generator.gd:391-401`) — and
loses everything that is a *search*: the `candidates` array, the `steps`/`lerp` grid, the
`sort_custom`, the `continue` on an out-of-band summit, and `TERRAIN_PLACEMENT_STEP_M`
(`:342-351`, `:404-405`). Given the solved footprint, the station shift follows from the solved entry
edge and the station height follows from the clearance maximum; the summit AGL is then *checked*
against `SUMMIT_TRACK_AGL_BAND_M` and a miss is a structured error, not a retry. The `placement_u`
draw survives at the same stream position — it now picks the aim point inside the inner band instead
of a hope inside the outer one, so no other stream moves. After the solve, `outward_local` is
recomputed from the accepted footprint and asserted identical to the preflight choice; a disagreement
is a structured error (`stage: "prefix-closure"`), never a second pass.

## 4. Budget and determinism

`BoundedSolver.solve` (`godot/bounded_solver.gd:3`) costs `1 + K·(n+1) + R` evaluations: one seed
evaluation, then per accepted iteration `n` cached Jacobian probes plus one trial, plus one evaluation
per rejected trial (the probes are cache hits on rejection, `:107-110`). Measured on the landed return
solve (n = 7, seeds 42/11/20260809/1/123456): **18–35 unique evaluations of the 220 cap, 2–5 LM
iterations, conditioning 6.2e5–2.5e6, `converged` on every seed**. The 220 is therefore ≈ 6× the
measured worst case, which is the underived budget `docs/ISSUES.md` flags.

Derived cap for n = 4: allow `K ≤ 8` (1.6× the return's measured worst from a hand-tuned seed) and
`R ≤ 8` (at most one rejection per iteration in the observed history):
`1 + 8·5 + 8 = 49` → **`MAX_PREFIX_EVALUATIONS := 52`**, with a fleet gate that no seed exceeds 60% of
it. The same formula re-derives the return at `1 + 8·8 + 8 = 73` → tighten `MAX_RETURN_EVALUATIONS`
220 → **80** in the same change, discharging the standing flag.

CI cost, measured: the prefix is 99.47 s of ride time over 70 spans — station+opener+act one is
59.75 s (spans 0–46), climb→tunnel is 39.72 s (spans 47–69). Integrating the whole prefix costs
509 / 200 / 100 ms at 0.01 / 0.025 / 0.05 s steps; integrating **only the tail** costs
200 / 79 / **41.7** ms. Because every control lies in the tail, the head is integrated once per build
and reused, and the solve runs at `COARSE_STEP_S` = 0.05: a typical solve (K = 3, R = 2 → 18
evaluations) costs ≈ 0.75 s and the derived cap costs ≤ 2.2 s, plus one production re-integration of
the tail (0.20 s). Against a measured build of 5.7–8.2 s per seed (compile 4.1–6.5 s), that is
**≈ +11% typical, ≤ +27% worst** — bounded, printed per seed in smoke, and gated against the cap.

Determinism: no RNG in the solve; controls seed from a committed `PREFIX_SEED`; the residual is a pure
function of (story, target); same seed → bit-identical ride stays a smoke gate. The solve is accepted
only when the coarse solution reproduces at `PRODUCTION_STEP_S` within declared per-residual tolerances
(the `_solve_return` coarse/fine idiom, `ride_program.gd:944-949`). Failure is a structured error
carrying stage, accepted values, residuals, margins and draw provenance — never a retry or a widened
band at runtime.

## 5. What it unblocks, in order — and what it does not do

1. **Issue 22** (dive commits at the rim): aim `dive_edge_span_m` and `dive_approach_s` at the low end
   of `DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M`. First, because it needs no new draws.
2. **Issue 20, opener tranche**: opener bank timing can move again, so the 899.7°/s² seam break at
   `drop/unbank-out` gets the continuous-roll treatment the return and clifftop tranches already got.
3. **Gap A stage 2, draws**: opener/act-one target draws re-certified over a *measured* range instead
   of the ~0.3%-wide one recorded in `ride_planner.gd`.
4. **Gap A stage 2, permutation**: act-one order draws on `STREAM_STORY_ACT_ONE`; residual 4 absorbs
   the 2.5–4.4 m/s handoff shift that broke the return on 12 of 15 seeds.
5. **Issue 23**: partially — the climb gains a degree of freedom it lacks today, but the camelback's
   24.46° lean needs its own geometry residual. This design does **not** claim to close 23.

**Correction (2026-08-15, Stage-4 full-matrix measurement).** Items 2–4 above were optimistic:
- Item 4 is **half true as measured**: residual 4 pins the record exit *speed* on every placed
  story (+0.51…+0.83 m/s inside band), but the *geometric* handoff (position/heading at the
  camelback) still moves, and the seven-control return solve does not re-converge from its
  hand-tuned fixed `RETURN_SEED` (budget_exhausted at 79/80 evaluations with residuals
  0.01–0.5 on the deep seeds). Full builds of every perturbed/permuted story fail there or on
  role-length overruns. The named unblock is a **deterministic per-story derivation of the
  return seed** (a function of the drawn story and the solved handoff — a seed derivation,
  never a candidate loop); that is its own design cycle.
  *Forward pointer (2026-08-16): that cycle ran and **refused** the derivation on its own §8
  measurement (`2026-08-15-return-seed-derivation-design.md`) — the wall is a box constraint no
  seed reaches. The dive-arc / role-length work it named next was then built and run, and
  **refused too** (§11 below): the prefix can return the metres, and the swap is not short of
  metres. The live spend is **head-domain accommodation** (a control upstream of act one) or a
  prefix residual on the **camelback handoff pose** itself — never a residual on the dive.*
- Items 2–3 are **domain-split**: the four controls are all downstream of act one, so the solve
  absorbs tail-domain changes (act-one loop −0.005 places 15/15; the optional-member swap
  places 15/15) but head-domain changes (opener literals) refuse at the terrain preflight
  before the solve is reached — a ±0.005 lateral-g change swings the native chord 245–408 m
  against a ~270 m terrain span. Opener draws therefore certify only over a narrow measured
  range, or need head accommodation (a head control means paying head re-integration per
  evaluation — measure before choosing). Issue 20's opener roll tranche is a *timing* change,
  smaller than ±0.005 g of force: measure it against the landed margins before assuming
  either way.
- Item 1 stands unchanged (tail-domain), and is the correct first spend of the margin.

Deliberately out of scope: no geometry patching or post-hoc position edits; no smoothing; no
position-space authoring (controls are span durations in the time/force domain); no force value, roll
rate or drive level as a control; no runtime candidate loops; no change to the return's controls,
bounds or seed beyond the budget constant; no restraint/structural model; and no ride-quality issue
closed on a green run alone.

## 6. Certification plan

Existing gates that must stay green, unchanged: `terrain_story_material_tests.gd` (zone crossing and
monotonic dive, 240–250 m dive drop, rim hugging, tunnel corridor, plan contract `:218-262`),
`generator_material_tests.gd` (role lengths, terrain intents, record bands), `ride_program_tests.gd`
(`_test_terrain_story_capability_is_finite_and_handed`, the return contract and its rigid-frame
equivariance), `geometry_metrics_tests.gd`, and `smoke.gd` (15-seed structure, seams, clearance; loads
on the three deep seeds; record bands; diversity floors; same-seed bit identity).

New focused tests:

- **Convergence and budget** (`ride_program_tests.gd`): the solve converges from `PREFIX_SEED` on all
  fifteen seeds within `MAX_PREFIX_EVALUATIONS`, and no seed exceeds 60% of it.
- **Coarse/fine agreement**: every residual reproduces at `PRODUCTION_STEP_S` within its tolerance.
- **Hand invariance**: both hands solve to identical control vectors (durations and hand-symmetric
  scalars), so the 0.05 m mirror assertion is met by construction; add a 1e-9 control-vector equality.
- **Structural failure**: an infeasible target returns `stage == "prefix-closure"` with residuals,
  margins and provenance — no relaxation, no retry.
- **No search left**: a source assertion that `_solve_dive_placement` carries no candidate list, the
  idiom already at `terrain_story_material_tests.gd:261`.

Measured criteria for "the prefix has margin now" — the analogue of the return's post-widening
margins, all on the fifteen-seed fleet:

- dive-entry edge ≥ 3 m inside both ends of `DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M`;
- summit AGL ≥ 1.5 m inside both ends of `SUMMIT_TRACK_AGL_BAND_M`;
- dive-exit apron fraction ≥ 0.05 inside `DIVE_EXIT_APRON_BAND`;
- record exit speed ≥ 0.4 m/s inside 93.9–95.6 m/s;
- and the decisive one — **re-run the three refusals as tests**: ±0.005 on `drop_lateral_g` and on
  `loop_positive_g` still builds and places on all fifteen seeds inside those margins, and at least
  two act-one permutations build clean. Until that test passes, the solve has not done its job.

## 7. Code budget

`CLAUDE.md`'s standing rule: write the minimum code that solves the problem; if two hundred lines could
be fifty, rewrite them. Original target: ≈ 90–110 new lines in `ride_program.gd` plus ≈ 25 in
`generator.gd`, netted against deleting the placement grid search (≈ 25 lines) and the three private
numeric helpers (≈ 90 lines) by moving capture/brake onto `BoundedSolver`.
**Correction (2026-08-15, measured by Stages 1–2):** the helper deletion is partly void — Stage 1
proved (and its reviewer confirmed) that the capture/brake solves cannot adopt `BoundedSolver.solve`
without changing the iterate path and breaking bit-identity; only `_linear_solve` and
`_matrix_conditioning` were deletable (−43 net in Stage 1). And the ≈ 90–110 estimate never priced
the program/observation split that §4's head-once/tail-only re-integration requires; Stage 2 landed
at +187 net with two deflation passes already done. Revised expectation: **Stage 3 deletes the grid
search and recovers the ~15–25 lines the Stage-2 review named; the honest net for the whole solve is
≈ +150–190 production lines**, justified by the structure §4 demands, not the original ≤ +40.

## 8. Risks and mitigations

- **Basin sensitivity** (the return's own history). Mitigation: a committed `PREFIX_SEED`; band
  residuals with an inner aim band so the accepted point is interior; bounds certified at both extremes
  on the fleet; structured failure rather than runtime widening. Residual 4 additionally *stabilises*
  the return by freezing the camelback handoff.
- **CI time** — one more coarse solve per build, bounded above by tail-only integration at a 0.05 s
  step and a 52-evaluation cap: ≤ 2.2 s worst, ≈ 0.75 s typical per seed here. Smoke prints per-seed
  evaluations and the fleet total; a regression past the cap fails rather than silently costing time.
- **The knife-edge equivariance test** (`ride_program_tests.gd:203-207`, 0.05 m mirror tolerance).
  Mitigated structurally, not by widening tolerance: all controls are durations, so one solve serves
  both hands and the mirror stays exact.
- **One-time re-baseline.** The solve moves every seed's ride, so committed baselines (fidelity artifact
  hashes, geometry metrics, quoted numbers) shift once — land it as a single re-baseline commit, the
  treatment the decision-streams change already got.
- **Terrain that cannot host any prefix.** The existing feasibility precondition (`generator.gd:252`)
  stays *ahead* of the solve, so such a seed is rejected before an evaluation is spent.

## 9. Open questions (not measured this cycle)

- Whether four controls suffice on the steepest-relief seeds, or a fifth (a climb-settle shoulder) is
  needed. Decide from measured conditioning on the fleet in Task 2, not by guessing.
- The inner-aim-band fractions; 40% is a proposal, to be replaced by Task 3's measured margins.
- Whether `crest_hold_s` can move without breaking the clifftop's declared 160° heading floor and 3 m
  centreline variation (`ride_program.gd:366-369`). If not, promote the climb-settle shoulder instead.

## 10. Staged implementation plan (TDD, each stage independently green)

1. **Budget derivation and numerics consolidation.** Failing test first: assert the return solve's
   accepted evaluations stay ≤ 60% of a tightened `MAX_RETURN_EVALUATIONS := 80` on all fifteen seeds;
   move the capture and brake solves onto `BoundedSolver` and delete the three private numeric helpers.
   No behaviour change beyond the constant. Fleet green, net line count down.
2. **The solve, targeting today's geometry.** Failing test first: `terrain_story_capability` with a
   closure target converges from `PREFIX_SEED` inside `MAX_PREFIX_EVALUATIONS` with coarse/fine
   agreement and identical control vectors on both hands. Target the *current* footprint's own bands,
   so the built ride is unchanged to within the fine tolerance and every existing gate proves the
   plumbing.
3. **Placement shrinks; margins become gates.** Failing test first: the four fleet-wide margin criteria
   of §6, plus the no-search source assertion. Replace the grid search with the closed-form placement,
   re-baseline records and artifact hashes in one commit.
4. **The refusals become tests.** Failing test first: ±0.005 on `drop_lateral_g` and `loop_positive_g`
   builds and places on all fifteen seeds; two act-one permutations build clean. This is the acceptance
   evidence for issue 24's first step.
5. **Spend the margin.** Issue 22 first (aim the dive at the rim), then issue 20's opener tranche, then
   the opener/act-one draw ranges re-certified into `RidePlanner.TARGET_DRAWS` with their measured
   widths and the act-one order draw on `STREAM_STORY_ACT_ONE`.

## 11. The dive-arc residual — derived, built, run, and **refused** (2026-08-16, Godot 4.7.1)

The spend §8.5 of `2026-08-15-return-seed-derivation-design.md` named: add the built dive arc as a fifth
closure residual so `dive_approach_s` returns route metres, and the act-one optional swap gets the length
it needs. Every number below was measured on the production path
(`RidePlanner.resolve` → `Terrain.generate` → `_plan` → `compile` → `Motion.integrate` →
`RouteContract.build`), never estimated; the residual was then **built and run** rather than argued about,
on a scratchpad copy of `godot/`. **Verdict: the residual does not land.** It is inert on canonical (all
fifteen rides bit-identical) and it can only refuse the swap earlier than today. The wall it was aimed at
is not the one that is there.

### 11.1 The commissioning premise was wrong on its face

The brief for this stage said the *canonical* fleet builds `outward-dive` at 497.4–497.5 m, overrunning
its declared 350–490 m role band, and that fixing it would be a declared re-baseline. Measured on all
fifteen preset seeds, canonical builds the role at **475.604–476.544 m** — inside the band, with
**13.456 m of ceiling headroom** on the worst seed (77777). Across all fifty closure evaluations the whole
fleet makes (seed, Jacobian probe, rejected trial, accepted point) the residual observes the arc between
**475.640 m and 476.721 m**, so the closest any canonical closure observation comes to 490 m is
**13.279 m**. The two ranges are measured on different integrations — 475.604–476.544 m is the *built*
role length the route contract reports on the production integration, 475.640–476.721 m is what the
*closure* observed across its own evaluations — so they do not nest (475.640 > 475.604) and the earlier
reading of the second range as containing the first was wrong. Which of step, window or accepted-vector
re-integration accounts for the 0.036 m at the low end was not captured by this run; both bounds stand as
measured, and both are ≥ 13.2 m clear of the ceiling. There is no canonical overrun, no
band falsehood on the production path, and **no re-baseline to declare**. 497.4–497.5 m is the *swap's*
number, exactly as `generator_material_tests.gd` and §10 of the story-energy design already recorded it.

### 11.2 What the role's length actually is — the derivation

Per-span, seed 11, production integration, canonical against the act-one optional swap (metres, m/s):

| block (spans) | s | canonical arc / drop | swap arc / drop |
| --- | --- | --- | --- |
| commit — outward-bank, face-approach, outward-release, commit | 3.684 | 64.111 / +0.258 | 74.038 / −0.005 |
| fall — vertical-entry, core | 3.404 | 112.248 / −108.397 | 118.578 / −111.628 |
| pull-out — pullout, pullout-release | 4.640 | 299.602 / −139.338 | 304.811 / −135.791 |
| **role total** | **11.728** | **475.960 / −247.477** | **497.427 / −247.423** |

Two facts fall out, and they decide the stage:

1. **Both stories fall the same cliff, to 5.4 cm.** The role's drop is −247.48 m canonical and −247.42 m
   swapped, both inside the declared `height_delta_m` band of −250…−240 m and inside the story's
   0.85–0.93 × relief. The 21.5 m the swap adds is **not** cliff geometry, and no terrain quantity moves.
2. **The role's length is a rim-speed budget, not a cliff-geometry one.** 63% of it (299.6 m of 476.0 m)
   is the 4.64 s pull-out block run at 49–70 m/s; the whole role is authored time × speed. The swap
   arrives at the rim at **20.996 m/s against canonical's 18.565 m/s** (+2.431 m/s) and the role runs
   **21.467 m longer** for it. Every one of the eight spans lengthens — +2.0, +2.7, +2.2, +3.0, +4.5,
   +1.8, +2.4, +2.9 m, no span carrying the miss alone — but *not* proportionally, and the table above
   says so itself: the commit block grows **+15.5%** while the pull-out block grows **+1.7%** (a
   proportional +13.1% rim scaling would have added ≈ 62 m, not 21.5). The two stories also differ in
   more than rim speed — their block drops differ by 3.2 m (fall) and 3.5 m (pull-out), netting to the
   5.4 cm of fact 1. So **8.83 m of role length per m/s of rim speed** is a **two-point secant between
   these two stories** — 21.467 m / 2.431 m/s, every difference between them included — not a per-span
   law and not a derivative anyone measured. What is solid is the direction and the size: a hotter rim
   entry buys a longer role, at ≈ 9 m per m/s over the one interval measured.

So the declared 490 m ceiling, read through that secant, *estimates* the fastest rim entry the story may
have: canonical's 13.456 m of headroom is ≈ **+1.5 m/s of rim speed**. The swap builds 497.43–497.46 m,
i.e. **7.43–7.46 m past the ceiling ≈ 0.84 m/s** of rim speed past what the band permits. (The earlier
"0.91 m/s" mixed sides of the comparison — seed 77777's headroom against seed 11's rim delta; computed on
one side throughout it is 0.84.) **The band is not the falsehood and neither is the arc. Both are honest
reports of what they measure.**

### 11.3 What `dive_approach_s` can actually return

The approach span returns arc at the local rim speed: on seed 11 the 1.00 s span itself builds 17.625 m of
arc canonically and 20.334 m swapped. The *net* rate, after the commit geometry re-settles around the
shorter span, is lower and is what matters — measured on the swap, the role runs **497.427 m at 1.00 s and
494.263 m at 0.80 s**, i.e. **15.82 m of arc per second of approach** (§10.4 of the story-energy design
measured the same slope further down the range: 497.1 → 490.8 → 487.6 m at 1.00 / 0.60 / 0.40 s, the
control's own floor). To put the swap under the bare 490 m ceiling needs 0.47 s of the control's 0.60 s of
range; to put it under a 490 − 5 m aim ceiling needs **0.79 s**, i.e. an approach of 0.21 s — **outside the
control's own 0.40 s floor**. The residual's absorber is 0.19 s short of the job before anything downstream
is even consulted, and the four controls together cannot make it up: the solve's own 204 evaluations
across the four swap seeds never observe an arc below **485.548 m** anywhere in the control box.

### 11.4 And every metre it does return is re-spent, at a loss

`dive_approach_s` pinned, act-one optional swap, four seeds, full build through the route contract:

| approach s | seed 11 | seed 42 | seed 20260809 | seed 4096 |
| --- | --- | --- | --- | --- |
| 1.00 (authored) | return converges (34 evals); dive **497.427**, turn-b **572.590**, height-a 308.4; route **refused** on dive + turn-b | return **budget_exhausted** 79/80 | return **budget_exhausted** 79/80 | converges (42); dive **497.457**, turn-b **571.228**, height-a 290.06; route **refused** on dive + turn-b |
| 0.80 | converges (42); dive **494.263**, turn-b **619.400**, height-a **285.820**; route refused on *three* roles | budget_exhausted | budget_exhausted | budget_exhausted |
| 0.60 | **budget_exhausted** | budget_exhausted | budget_exhausted | budget_exhausted |
| 0.40 | plan **refused**: the accepted closure changes the yaw solution | budget_exhausted | — | — |

Read the seed-11 row: 0.20 s of approach buys **3.164 m** of dive arc and costs **+46.810 m of
`return-turn-b`** and **−22.595 m of `return-height-a`**, taking height-a through its own 290 m floor — the
return's answer to the moved camelback handoff costs an order of magnitude more geometry than the metres
returned. Another 0.20 s stops the return converging at all; another 0.20 s after that flips the yaw
branch and the plan refuses before the solve is reached. What binds is geometry, not length — but the
claim has to be scoped to what was measured, because "length was never binding" over-generalises. On the
**short-approach refusals** the length residual is exactly **0.0** while the geometric residuals blow up;
that much is direct. The converged cases prove less than they look: at 8198.76–8198.80 m they sit
**0.20–0.24 m inside the 8199.0 m aim ceiling** (`RETURN_LENGTH_AIM_MARGIN_M` = 1.0), i.e. pressed
against the constraint, not slack under it. And the length overruns on record are un-retracted — the two
budget-exhausting seeds carry length residuals of **2.1 m and 5.1 m past the ceiling**
(`generator_material_tests.gd:193-195`; §1 of the story-energy design prices the same shortfall at
4.9–8.1 m against 8200 m).

The honest statement is the **stronger** one, and it comes from §11.5's 3 m-margin run: there the dive
gave back ≈ **10.4 m** (497.43 → 487.02), more than either of those overruns, and seeds 42 and 20260809
**still budget-exhausted at 79/80**. Length was *relieved* and the wall remained. §8.5's "no seed creates
metres" was right; its conclusion that the prefix could create them was not — **the prefix can, and the return spends
them re-closing a handoff that moved because they were created.**

### 11.5 Built and run

Fifth residual `dive_arc_m`, observed as `distance_m[last+1] − distance_m[first]` over the `cliff-dive`
gesture (the same window `route_contract.gd:_validate_role_lengths` measures), scale 5.0, aim band = the
declared role band inset by a margin, `PREFIX_CONTROL_*`, `MAX_PREFIX_EVALUATIONS` and the other four
residuals untouched:

- **Canonical is bit-identical, 15/15**, at a 5 m margin (aim band 355–485 m): every accepted control
  vector, every role length, every route total and every return evaluation count matches the unmodified
  build byte for byte. The mechanism is the one `RETURN_LENGTH_AIM_MARGIN_M` uses — every canonical
  observation is strictly interior, `_band_residual` is exactly `0.0` there, and a zero Jacobian row adds
  exactly `0.0` to `JᵀJ` and `Jᵀr`. Coarse/fine agreement on the new channel is **0.0014 m** (a 0.05 m
  tolerance would have been ample), so nothing about the plumbing is marginal.
- **The swap refuses 4/4 at the prefix closure** at that margin, where today it plans 4/4 and compiles
  2/4 — strictly worse in kind, the same outcome the story-energy re-target produced.
- At a **3 m** margin (aim ceiling 487 m — below which the swap's own arc floor of 485.5 m cannot reach),
  the closure converges on seeds 42 and 20260809, delivering the dive at **487.02 / 487.01 m** with
  `dive_approach_s` at 0.401 / 0.410 — and **both then budget-exhaust their return at 79/80 anyway**,
  while seeds 11 and 4096 still refuse at the closure. Delivering the dive inside its band does not buy
  the swap a build, and the ≈ 10.4 m it delivers covers the 2.1 / 5.1 m length overruns those two seeds
  carry (§11.4) without changing the outcome. **Residual breakdown not captured:** this run recorded the
  exhaustion and the delivered dive length only, so *which* residuals were still unsatisfied at 79/80
  here is unmeasured. (The approach-sweep exhaustions in §8.2 of the return-seed design all pinned
  `height_a_recovery_duration_s` at its 0.35 s floor, but that sweep ran without this residual and is not
  this run's breakdown.)

Under §7's standing rule — buys nothing measurable → it does not land — no code lands. The refusal is
recorded at the band's ship-once home in `generator.gd`, next to the `outward-dive` role.

### 11.6 What this refuses, and what it names

- **Refused:** the dive-arc residual, and with it the whole "the swap's wall is prefix-side role length"
  reading in §8.5 of the return-seed design, in §10.4 of the story-energy design, and in `docs/ISSUES.md`.
  All three are corrected in the same commit.
- **Refused with them:** re-deriving the 350–490 m band. Even with the dive band widened past 497.5 m the
  swap still fails `return-turn-b` (571.2 / 572.6 m against 430–570) on the two seeds whose returns
  converge, and seeds 42 / 20260809 never reach the route contract at all. Widening buys two seeds a build
  and neither of the two the acceptance named — and it would be fitting a declared band to one story.
- **What the evidence names instead.** The swap's wall is the *geometric* camelback handoff — pulled back
  32–66 m, +12–13 m higher, 3.5–5.1° in yaw — and the four closure controls are all durations downstream of
  act one, so they cannot pin six DOF (§2 said as much about heading and it generalises). Every honest
  next spend is on that: either **head-domain accommodation** (a control upstream of act one, paying head
  re-integration per evaluation — measure that cost before choosing, §5's correction), or a **prefix
  residual on the handoff pose itself** rather than on the dive's own span, which needs more controls than
  four. Neither is a residual on the dive.
- **Untouched and still true:** `MAX_PREFIX_EVALUATIONS := 52` (no change was needed or made), the four
  landed residuals, the fleet margins, and issue 22's rim aim.

**Forward pointer (2026-08-16, later the same day).** Everything §11 measured stands. Its *reach*
did not: the residual was tested alone, and alone it behaves exactly as measured here. Composed with
an eighth return residual on `return-turn-b` interiority — the role §11.4 itself identified as where
the returned metres were being re-spent — and at a 2 m inset instead of 3 m, both residuals land and
the act-one optional swap builds end to end on all four gated seeds while the canonical fleet stays
bit-identical. The record lives at §8 of
`docs/superpowers/specs/2026-08-16-return-height-authority-design.md`. §11.6's "refused" verdict on
the dive-arc residual is superseded there; §11.6's refusal of a *re-derived* 350–490 m band, and its
statement that the swap's remaining wall is not a residual on the dive alone, both stand.
