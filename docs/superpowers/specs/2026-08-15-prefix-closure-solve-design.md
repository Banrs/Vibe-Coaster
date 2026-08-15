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
