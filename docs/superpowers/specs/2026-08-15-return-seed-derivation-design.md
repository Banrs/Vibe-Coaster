# Return Seed Derivation — Design

**Status:** proposed direction (2026-08-15). The stage-4 unblock named in §5 of
`2026-08-15-prefix-closure-solve-design.md` — "a deterministic per-story derivation of the return seed … a seed
derivation, never a candidate loop". **Authority:** user decisions → physical derivation + verified evidence → vision
docs → code. Every number below was measured this session (Godot 4.7.1, scratchpad copy of `godot/`, the production
path `_plan` → `_add_story_prefix` → `_add_camelback` → `RideReturnSolve._solve_return`), never estimated; ubuntu CI
is ≈ 2× slower and verdicts still come from CI.

**Headline — it corrects this design's commissioning premise.** The stage-4 record's "budget-exhausts at 79/80 …
nearly converged" reads as a basin miss. At a 5× budget it is not: the solve **stalls**, and both starts a seed
derivation can offer stall at the same class of point. The seed is not the wall; §4 names what is.

## 1. What moves in the handoff

`compile()` (`ride_program.gd:164-169`) integrates prefix + camelback and hands `_last_state()` to `_solve_return`.
Six components enter the residual — station-frame forward/cross/height, yaw, speed, arc length (via
`route_length_band_m`); roll enters as `initial_bank_rad`, re-authoring the return's own spans. Seeds 42 / 20260809 /
11 / 4096:

| | forward m | cross m | height m | yaw rad | speed m/s | arc m |
| --- | --- | --- | --- | --- | --- | --- |
| canonical spread (4 seeds) | 35.83…45.09 | ±820.76…823.18 | 40.46…40.67 | ∓2.2593…2.2668 | 86.912…86.950 | 5955.07…5957.36 |
| **swap** Δ vs own canonical | −31.9…−66.1 | 11.2…21.8 | **+12.37…+13.17** | 0.062…0.089 (3.5–5.1°) | −1.08…−1.16 | +3.1…+5.4 |
| **loop −0.005** Δ | −339.5…−385.2 | 118.6…146.1 | +11.7…+13.2 | 0.284…0.324 (16–19°) | −1.04…−1.15 | +40.5…+42.7 |

The closure solve's residual 4 pins the *tunnel-exit* speed (+0.51…+0.83 m/s inside band), yet the camelback hands over
**1.1 m/s slower** on every perturbed story. The fixed `RETURN_SEED` absorbs the canonical 9.3 m of forward spread; the
swap asks 32–66 m plus a 12–13 m rise, the loop 340–385 m.

## 2. Why the fixed seed's basin is not the wall — measured

`_solve_return` from `RETURN_SEED`, production bounds, at today's `MAX_RETURN_EVALUATIONS := 80` and again at 400
(scratchpad constant only):

| case | @80 | @400 | max scaled residual @400 |
| --- | --- | --- | --- |
| swap, seed 42 | `budget_exhausted` 79 | **`stalled` 271** | 0.480 (height 2.40 m) |
| swap, seed 20260809 | `budget_exhausted` 79 | **`stalled` 365** | 0.039 (route length 4.9 m) |
| swap, seeds 11 / 4096 | `converged` 34 / 42 | — | — |
| loop −0.005, all four | `budget_exhausted` 79 | `budget_exhausted` 399 | 26–55 (station miss 62–277 m) |

`stalled` is the trust radius collapsing below 1e-8 (`bounded_solver.gd:101`), not a budget end: 321 extra evaluations
bought 0.014 (seed 42) and 0.025 (20260809) of scaled residual and converged nothing, both stalls pinning
`height_a_recovery_duration_s` at its 0.35 s floor (`RETURN_SCALAR_BOUNDS[2]`). **Budget verdict:
`MAX_RETURN_EVALUATIONS := 80` holds and this design earns no change to it** — 5× converged no extra case, so the
constant is not what refuses and its derivation (`ride_return_solve.gd:13-16`) stands. One unrelated flag: seed 4096's
swap converges in **42** against the 60% gate at 48, the tightest observed headroom, to watch if §4 lands.

**Form (b) is refuted by measurement, not argument.** Seeding the perturbed solve with the *same seed's* canonical
accepted vector — the brief's coarse-continuation form — was run on every case: seed 42 stalls at 280 with residual
1.011, **worse** than cold; 20260809 stalls at 373 with 0.037, indistinguishable; seed 11 converges in 26 vs 34 (a
saving, no capability); seed 4096 *regresses* from a cold convergence to a point rejected on its margin
(`route_length_high_m = −5.9e−6`). None unblocked — a continuation paid for on every non-canonical build that buys
nothing is not a design. **Form (c), a per-story-class seed table, is rejected**: it cannot cover the space (36
grammar-legal orders × 15 seeds × *continuous* draws — any table is a lookup with holes), and it is hand-tuning at
scale, the practice the closure solves exist to delete.

## 3. The chosen form — (a), an analytic warm start — and how it stays bit-identical

Only (a) is a *function* of the handoff, costs zero solver evaluations, and reduces to an identity on the canonical
story, so it is the form to build **if one is built at all** — but §2 demotes it from "the unblock" to "a budget
optimisation", and §4 spends first.

	seed_i = clamp( RETURN_SEED_i + Σ_j S_ij · Δh_j , RETURN_SCALAR_BOUNDS_i )

`Δh` is §1's six-vector measured **against the canonical story's handoff on the same seed**; `S` is a committed 7×6
sensitivity matrix derived once, offline, by finite differences over the fleet and published in the solve report. No
RNG, no iteration, no branch on a measured value — a pure function of (story, handoff), so same seed → same seed
vector. A non-canonical story integrates the canonical prefix once for its `Δh` reference (100 ms at `COARSE_STEP_S`)
against a 5.7–8.2 s build.

Bit identity is algebraic, not a special case: the argument is the story's *deviation* from canonical. Production
draws no sequence and no act-one target today, so for every seed and both hands the drawn story **is** canonical, the
same seed integrates the same prefix, and `Δh ≡ 0` exactly — every component, not approximately. `RETURN_SEED + S·0 =
RETURN_SEED` bit-identically in IEEE-754, so `_solve_return` starts from the same vector and accepts the same point.
Because that is an identity and not a hope, the canonical path short-circuits before the reference integration is
spent — the story descriptor (sequence + resolved targets) is compared to the canonical one, and on equality the
derivation returns `RETURN_SEED` unevaluated, so canonical builds pay nothing. Gated as the decision-streams change
was: the fifteen-seed route SHA-256 set unchanged.

## 4. What the evidence says the unblock actually is

A probe with `RETURN_SCALAR_BOUNDS` widened across the board (scratchpad only, to ask *what is binding*, never a proposal):

- **seed 20260809, swap: converges in 42 evaluations** — then is rejected by the inequality margin
  `route_length_high_m = −0.0021 m`: the accepted point sits **2.1 mm past the 8200 m ceiling**. One production bound
  was active — `height_a_recovery_duration_s` wants 0.3115 s against its 0.35 s floor.
- **seed 4096, swap** shows the same signature under *production* bounds (`route_length_high_m = −5.9e−6`).
- **seed 42, swap** stalls needing 8.6 m more than 8200 m allows — length-short, not seed-short.
- **loop −0.005** still misses by 62–192 m with every bound relaxed: beyond the return solve's reach by two orders of
  magnitude. It is the *prefix's* handoff geometry that must be constrained, not the seed.

The swap class is **length-saturated**, and the mechanism is that `_band_residual` returns 0 anywhere inside the band:
the solve has no gradient telling it to stay interior, converges onto the 8200 m boundary, and is rejected by a strict
`> 0` margin. Three measured spends, in order, none a seed: (1) an **inner aim band** on `route_length_band_m` (and
`entry_speed_band_mps`), the treatment the prefix closure design gave its own four residuals, so a converged return
sits interior by construction; (2) a **certified relaxation of the `height_a_recovery_duration_s` floor** (0.35 →
~0.30), proven at both extremes on the fleet as `ride_planner_tests.gd` certifies a draw range; (3) **length
accounting** for the swap's +3.1…+5.4 m of arc and 32–66 m of pulled-back handoff — seed 42 is 8.6 m short, and no
seed creates metres.

## 5. Certification

The four stage-4 refusals are three different failures, so name them precisely:

- **swap on 42 / 20260809 / 4096** — full build end to end (not the planning-half gate already in
  `generator_material_tests.gd`). These are the cases §4 targets.
- **swap on seed 11** — its return solve already **converges** (34 cold, 26 warm); it fails on role lengths (dive
  497.4 m against 350–490; turn-b 574.5 m against 430–570). **This design does not address role-length overruns** and
  must not be credited with them.
- **loop −0.005, all four seeds** — explicitly **out of scope**, measured unreachable in §4; it belongs to a
  geometric handoff residual on the prefix side, its own cycle.

Gates that stay green, unchanged: `smoke.gd` (fifteen-seed structure, seams, clearance; loads on 11/42/20260809; record
and entry-launch bands; diversity floors; same-seed bit identity), `ride_program_tests.gd` (return contract, rigid-frame
equivariance, ≤60% budget gate), and the generator-material, ride-planner, ride-config, terrain-story and
geometry-metrics suites; plus one new gate, the fifteen-seed route SHA-256 set unchanged by §3. CI cost: zero on the
canonical fleet; §4's aim band may move accepted points and evaluation counts, so print them per seed in smoke.

## 6. Implementation sketch (TDD, ≤4 bounded stages)

1. **Inner aim band on the return's length residual.** Failing test first: every accepted return on the fleet reports
   `route_length_high_m`/`_low_m` ≥ a declared interior margin (proposal 2 m, replaced by the stage's measured value),
   and seed 4096's converged-but-rejected swap point is not produced.
2. **Certify the `height_a_recovery_duration_s` floor.** Failing test first: a fleet build with that control pinned at
   each end of the proposed range is accepted, as draw ranges are certified; then move it. No other bound moves.
3. **Swap builds end to end.** Failing test first: seeds 42 / 20260809 / 4096 build a complete route with the act-one
   swap, inside every gate. If it fails, seed 42's 8.6 m shortfall (§4) is the finding — never widen the band to hide it.
4. **The seed derivation itself (§3), only if §7 says it pays.** Failing test first: fifteen-seed route SHA-256
   identical with the derivation in place, then swap-case evaluation counts drop measurably against stage 3's numbers.

## 7. The one measurement that decides whether §3 is built at all

(a)-vs-(b) is closed — (b) is refuted in §2. What remains open is whether form (a) earns its code: **after stages 1–3
land, re-run the swap story on all fifteen seeds and record, per seed, `solver_status`, `unique_evaluations`, and the
accepted control vector.** If every seed converges with the worst count under 48, form (a) buys nothing measurable and
stage 4 is dropped — the honest outcome, given §2 showed the seed moves stall points but not capability. If any seed
exceeds 48 or stalls, derive `S` (§3) from those vectors against §1's handoff deltas: the runs are their own
finite-difference data, so recording the vectors in stage 3 makes this measurement free.
