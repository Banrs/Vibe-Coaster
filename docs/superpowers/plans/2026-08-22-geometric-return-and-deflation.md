# Geometric Return Rewrite + Whole-Codebase Deflation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development — fresh
> implementer subagent per task, task review (spec + quality) after each, broad final review.
> Steps use `- [ ]`. Routing is 10-80-10: the coordinator (fable) orchestrates and reviews; opus/sonnet implement;
> fable implements only the very hardest pieces.

**Goal:** Replace the globally coupled return/capture solve with order-generic macro geometry and
local distance-domain FVD elements (priority), and deflate the whole codebase under the global
CLAUDE.md simplicity rules wherever a shorter rewrite is a meaningful improvement.

**Architecture:** Rebase onto `main` (the `codex/geometry-audit` branch is CI-red thrash with no
spatial span; ~450 lines are reusable and get ported by function). Byte-identical deflation lands
first so the rewrite's new suites use the shared test harness. The rewrite then executes the
already-detailed `docs/superpowers/plans/2026-08-22-geometric-return-rewrite.md` (8 tasks) with
the amendments below. Judgement-level deflation (value-changing, doc de-dup) lands after cutover.

**Tech Stack:** Godot 4.7.1 GDScript, headless focused-test scripts, GitHub Actions, `gh`.

## Context (why)

- Newest plan = worktree `.worktrees/geometry-audit/docs/superpowers/plans/2026-08-22-geometric-return-rewrite.md`
  (spec `docs/superpowers/specs/2026-08-22-return-macro-layout-design.md`, PR #14). It supersedes
  main's `2026-08-17-geometry-truth-vertical-slice.md` (Tasks 1–3 landed; Task 4 planar camelback
  blocked only by return closure — VC-016; Task 5 half done).
- Branch CI fails deterministically: seed 4096 act-one swap return solve → `budget_exhausted`
  219/220 evals, 12 controls — the coupling the spec deletes.
- Branch `motion.gd` has **no** spatial span; `geometry_metrics.gd` +177 is
  `transition_audit()/role_audit()`, not x^(0..4); `ride_return_solve.gd` +435 is deleted wholesale.
- Diagnostic layer 6,727 lines ≈ generator 7,388 (CLAUDE.md parity limit); tests 10,468 with
  ~750 duplicated harness/fixture lines; ~250 md lines of data shipped twice. Core ≈105 safe lines.
- Local Godot: `D:\Games\Godot_v4.7.1-stable_win64.exe` (`GODOT` env var; not on PATH).

## User decisions (2026-08-22)

- Rewrite is the **priority**; whole-codebase deflation is in scope (all phases).
- Base on `main` + cherry-pick by function. **Drop the 155 m return terrace** entirely.
- **One PR** from `feat/geometric-return`; deflation as its own early commits.

## Global Constraints

- Same seed + resolved config → bit-identical route. Phase A/0 oracle: 15-seed published-channel
  SHA-256 baseline captured in Task 0.
- Do not alter the 7.8–8.2 km band, role-length bands, force envelopes, convergence tolerances,
  terrain intent, solver caps, or the 70–80 m/s entry band to make anything pass.
- No seed-specific branch, warm start, retry, fallback topology, or evaluation budget.
- `Motion` integration is the sole centreline authority. No positive drive or midcourse brake in
  the return. Camelback stays symmetric, planar, never an energy absorber.
- Layout adds exactly four semantic controls; brake solve is one-dimensional; capture is neutral.
- Ship each piece of data once; the diagnostic layer must not outgrow the generator.
- Never reorder float arithmetic in a "byte-identical" task; a verifier diff-reviews each one.
- Pinned bytes that must not move: `fidelity_artifact_tests.gd:804,480,1308`,
  `fidelity_overlay_tests.gd:217-228`, `ride_config_tests.gd:19`.
- Tests are written and observed RED before production code changes. Commit RED, then GREEN.
- Local Godot for iteration; GitHub Actions is the verdict. After each push:
  `$sha=git rev-parse HEAD; gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'`
  then `gh run watch $run --exit-status`.
- Leave the user's uncommitted `README.md`, `Run-VibeCoaster.cmd`, `Telemetry/` changes alone.
- Committed code/tests never mention models, agents, or execution products.

Local commands (PowerShell):
```powershell
$env:GODOT='D:\Games\Godot_v4.7.1-stable_win64.exe'
& $env:GODOT --headless --path godot --editor --quit
& $env:GODOT --headless --path godot --script res://smoke.gd
& $env:GODOT --headless --path godot --script res://<suite>.gd
```

---

## Task 0: Rebase onto main and freeze the oracle (fable coordinates; sonnet mechanics)

**Files:** branch `feat/geometric-return` from `main`; port by function from `codex/geometry-audit`.

**Port (exact list):**
- `godot/geometry_metrics.gd`: `transition_audit()`, `role_audit()`, `_agl_distribution()`,
  `_range()`, `_profile_value()`, `_profile_has_motion()`, consts `TRANSITION_ZERO_TOLERANCE`,
  `SEMANTIC_SPAN_MIN_S`, `record-release-turn` in `MATERIAL_ROLE_BY_WINDOW`.
- `godot/geometry_audit_tests.gd` whole file + `res://geometry_audit_tests.gd` manifest line.
- `godot/route_contract.gd`: the `role_bounds`/`measured_route`/`geometry_audit` block in
  `build()` — **without** `_return_terrace_proof()`.
- `godot/generator.gd`: `geometry` intent dicts on `camelback` and `record-release-turn`; the bug
  fix in `build_with_decisions()` passing `compiled.plan` to `RouteContract.build()`.
- `godot/ride_planner.gd`: `"record-release-turn"` appended to `SPINE_TAIL`.
- `godot/motion.gd`: only `transition_id: String = ""` on `span()` and its record field.
- Docs: `docs/superpowers/specs/2026-08-22-return-macro-layout-design.md`,
  `docs/superpowers/plans/2026-08-22-geometric-return-rewrite.md`,
  `docs/superpowers/plans/2026-08-20-full-ride-geometry-audit.md`.
- **Not ported:** anything terrace (`_stamp_return_terrace`, `RETURN_TERRACE_*`,
  `_return_terrace_*`, `terrain.gd` terrace helpers, `require_return_terrace`), bounded_solver
  secant polish, every `ride_return_solve.gd` change, `_set_return_prefix_parameters()`,
  `_apply_record_release_parameters()`, `_apply_camelback_fall_duration()`, the removal of the
  `transfer_bank_bias_rad` draw.

- [ ] Step 1: `git checkout -b feat/geometric-return main`
- [ ] Step 2: Port the list above (read each function from the worktree; paste verbatim).
- [ ] Step 3: Local import + `geometry_audit_tests.gd` + smoke → GREEN. Push; CI GREEN = baseline.
- [ ] Step 4: Capture oracle: for the 15 canonical seeds write
  `scratchpad/baseline-hashes.json` = `{seed: canonical_sha256(route published channels)}` using
  `canonical_data.gd` through a throwaway headless script (not committed).
- [ ] Step 5: Commit `chore: rebase geometry audit onto main without the return terrace`.

---

## Phase A — Byte-identical deflation (Workflow: parallel worktrees, one implementer each)

Every task: (1) touched suites + smoke locally GREEN; (2) `baseline-hashes.json` identical;
(3) sonnet verifier reviews the diff for any arithmetic reordering or dict-key-order change;
(4) one commit `refactor: …`. Ordering: A1 first (others build on `test_util.gd`), then the rest
in parallel. Nothing here touches `ride_return_solve.gd` (deleted by Task 7).

### Task A1 (haiku): shared test harness
- Create `godot/test_util.gd` (`class_name TestUtil extends RefCounted`): `errors: PackedStringArray`,
  `expect(ok, msg)`, `expect_close(a, b, msg, tol=1e-6)`, `expect_vector(a, b, msg, tol)`,
  `expect_range(v, lo, hi, msg)`, `expect_min`, `expect_max`, `contains(list, item)`,
  `finish(tree: SceneTree)` (print errors, `quit(1)` else `quit(0)`).
- Migrate all 17 `*_tests.gd` + `camelback_geometry_tests.gd` (`_errors`, `_expect*`, `_initialize` tail).
- Expected −250–330 lines. Verify: full focused manifest locally GREEN.

### Task A2 (sonnet): shared synthetic-route fixture
- Create `godot/route_fixture.gd` builder (`points()`, `roles()`, `channel(name, values)`,
  `build() -> Dictionary`) filling all 13 packed arrays + key set once.
- Replace builders at `fidelity_tests.gd:1351-1720`, `fidelity_artifact_tests.gd:1666-1738`,
  `geometry_metrics_tests.gd:381-525`, `fidelity_overlay_tests.gd:337-350`,
  `route_contract_tests.gd:178-378`, `element_contract_tests.gd:74-133`,
  `dense_output_tests.gd:41-66`, `route_sampling_tests.gd:71-90`. Expected −300–400.

### Task A3 (sonnet): de-duplicate landmark data in tests
- `fidelity_tests.gd:595-816` `_test_reviewed_live_pov_landmarks` → read committed
  `docs/evidence/fidelity/youtube/*-review.json` as `_test_manifest_parity` (`:817-855`) does;
  keep only the asserted invariants (three Long. readouts, six prompt IDs, empty
  selectors/observations/targets). Expected −150–170.

### Task A4 (haiku): fold per-file helpers
- `_role(route, story, role)`/`_window(route, story)` from `generator_material_tests.gd:1054-1101`,
  `terrain_story_material_tests.gd:334-348`, `geometry_metrics_tests.gd:399-407`,
  `ride_planner_tests.gd:226-231` → `RouteContract` (owner of `role_windows`); ranges → `TestUtil`. −60.

### Task A5 (haiku): diagnostic mechanical
- `fidelity_artifacts.gd:566-574` `_matches_compiled_anchor` → call `_FIDELITY` (−9).
- `_inspect.gd:201-223` `_write_geometry_file` → `Artifacts.write_recorded(...)` public (−20).
- `fidelity.gd:610-616` `element_bands` (zero production callers) + its 3 tests → delete (−32).

### Task A6 (sonnet): measurement helper merge
- `geometry_metrics.gd:1088-1123` `_maximum/_minimum/_absolute_peak/_pitch_deg` → one pair in
  `fidelity.gd` with explicit `empty_value` arg; verify each GM call site's empty/normalize case (−25).
- `geometry_metrics.gd:888-913` markdown cell helpers → shared with `fidelity_artifacts.gd:782-795`
  on GM's side only (artifact markdown is byte-pinned) (−20).

### Task A7 (sonnet): prefix-closure margin table once
- `smoke.gd:315-352` ↔ `generator_material_tests.gd:387-402` → `RideGenerator.prefix_closure_margins(planning, terrain, fine) -> Array` of `[label, margin, band, required]`; callers format/assert (−25).

### Task A8 (haiku): constants once
- `generator.gd:21-27` ↔ `route_contract.gd:13-18` (`DIVE_EXIT_APRON_BAND`,
  `DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M`, `TUNNEL_EXIT_PLAIN_OVERSHOOT_M`,
  `LOWER_SPINE_SURFACE_OFFSET_M`; `1.79` in `terrain_story_material_tests.gd:7`) → owner
  `RouteContract`. Never merge `SUMMIT_AGL_BAND_M` with `SUMMIT_TRACK_AGL_BAND_M` (−5).

### Task A9 (sonnet): generator/contract loops
- `generator.gd:279-289,368-383,384-397,670-682` → `_world_offset(tangent, right, v)` and
  `_lower_spine(...)`, preserving `tangent*x + UP*y + right*z` term order verbatim (−18).
- `route_contract.gd:619-644,688-695` chained `minf` → fold array in identical order (−16).

### Task A10 (haiku): small mechanical
- `ride_program.gd:962-970` `_add` builds span then calls `_add_record` (−6).
- `main.gd:362-431` `_multimesh_from(mesh, transforms) -> MultiMesh` (−10).
- Double default+`is_empty()` guards `ride_program.gd:538,978,994`, `generator.gd:706` (−4).
- Inline `element_contract.gd:264 _bank_at` (−3); drop `ride_program.gd:12 COMPACT_PULSE_AREA`
  re-export, caller uses `Motion.COMPACT_PULSE_AREA` (−2).
- Move the misplaced comment `smoke.gd:26-40` to `generator.gd` next to the constants it describes.

### Task A11 (sonnet): coarse/fine agreement once
- `ride_prefix_solve.gd:238-248` loop → `RideProgram._observations_agree(a, b, tolerances) -> bool`
  (the return copy dies with Task 7). Never unify the two report dicts (hashed) (−7).

**Explicit non-targets:** `motion.gd:326-372` unrolled RK4; `profile_sample`/`_profile_value`
Float32 narrowing (`motion.gd:152` pins it); the three typed binary searches; `_window_id`
duplication (the duplicate is the check); test-only `Motion.bank_balance`/`sample_*`;
`fidelity.gd:65-604 compare_fleet` (designed dormancy, not dead).

---

## Phase B — Geometric return rewrite (Tasks 1–8 of the 2026-08-22 plan)

Execute `docs/superpowers/plans/2026-08-22-geometric-return-rewrite.md` as written — its tasks
already carry RED tests, interfaces, equations, and commit steps — with these amendments:

1. Verification: local Godot for iteration, CI for RED/GREEN record (replaces "no local Godot").
2. New suites use `TestUtil` / `RouteFixture` from Phase A.
3. No terrace: Task 6/7 must not reference `RETURN_TERRACE_*` or a 155 m AGL relationship;
   the camelback contract is planarity + pitch-zero apex + 245–255 m prominence only.
4. Model routing — T1 spatial kernel: **opus** (fable math review, sonnet dup-code review);
   T2 grammar: **sonnet**; T3 layout: **opus** (fable architecture gate); T4 elements: **opus**
   (fable physics review); T5 terminal: **sonnet** (opus energy review); T6+T7 atomic cutover:
   **opus** (fable review gate; fable implements only if opus fails it), single agent, sole writer of `ride_program.gd` during it; T8 evidence: **sonnet**
   impl, **opus** visual/physics review of seeds 42/11/20260809.
5. Parallelism: T1 ∥ T2 ∥ T3 (worktrees); T4, T5 after T1; T6/T7 after all; T8 last.
6. Before T1 starts, a real-world basis check (Task B0) cross-examines every numeric the spec
   and plan rely on against docs/TELEMETRY*.md, counterpart bands, verify.gd and real coaster
   references; discrepancies are fixed in the spec before implementation.
7. Temporal-path bytes must stay identical through T1 (oracle = `baseline-hashes.json`).
8. GREEN = import, 20 focused suites incl. `camelback_geometry_tests.gd` restored to the manifest,
   15-seed smoke incl. seed 4096 unspecial, viewer frame/runtime, visual audit pack; every scaled
   residual ≤ 0.02, every margin positive.

---

## Phase C — Judgement deflation (after cutover)

### Task C1 (opus): counterpart bands once
- `docs/evidence/fidelity/counterpart-bands.md:72-~560` duplicates `fidelity_counterparts.gd BANDS`
  and hardcodes the code-derived `target`. Keep derivation rule, caveats, per-role prose; drop
  numeric table bodies; point at `RideFidelityCounterparts.BANDS` (−~250 md).

### Task C2 (opus, fable review): one filtered-window slicer
- `fidelity.gd:1006-1104` (`_bands_for_row`+`_sample_filtered_window`) and
  `geometry_metrics.gd:507-578` (`material_role_bands`+`_time_at_distance`) → one
  `Fidelity.filtered_window(route, first, last, row_offset)`. Changes `geometry-metrics.json` /
  `counterpart-comparison.json` values (not pinned) — record before/after in the PR (−60–80).

### Task C3 (opus): fleet/seed/commit literals once
- `fidelity.gd:17`, `_inspect.gd:32-35`, `fidelity_artifacts.gd:44`,
  `fidelity_artifact_tests.gd:10-12,1305,1491`, `fidelity_tests.gd:6` → single owner in
  `fidelity.gd`; delete the now-vacuous agreement pin `fidelity_artifact_tests.gd:369-371` (−10).

### Task C4 (opus): generate expected render requests
- `fidelity_artifact_tests.gd:1299-1637`: `_expected_render_requests` → loop over
  `EXPECTED_PACK_FILES`; all expected bytes stay exact (−60–80).

### Task C5 (sonnet): docs truth
- `docs/ISSUES.md`: VC-016/VC-029/VC-038/issue 24 status; `CLAUDE.md`: three new owners
  (`ride_return_layout.gd`, `ride_return_elements.gd`, `ride_terminal.gd`), deleted
  `ride_return_solve.gd`, 20 focused suites, "eight controls" prose; `README.md` solver description.

---

## Task D: Land
- [ ] Final broad review (superpowers final reviewer): four-rule audit with old/new line counts for
  the return/terminal path and the repo total, recorded in the PR body.
- [ ] `rg -n "RideReturnSolve|RETURN_SCALAR_IDS|_solve_return\(|_return_observation\(|capture_seed|RETURN_TERRACE" godot docs README.md CLAUDE.md` → empty.
- [ ] Open PR from `feat/geometric-return`; close PR #14 as superseded; after merge remove the
  `geometry-audit` worktree and branch.

## Execution protocol (first actions after approval)
1. Write the consolidated design note to `docs/superpowers/specs/2026-08-22-rebase-and-deflation-design.md`
   (decisions above: rebase-on-main, terrace dropped, deflation catalog) and this plan to
   `docs/superpowers/plans/2026-08-22-geometric-return-and-deflation.md`; commit.
2. Run Task 0 inline (coordinator), then Phase A as a Workflow (parallel worktree implementers +
   verifier), then Phase B per the routing above, then Phase C, then Task D.
3. Coordinator context stays orchestration-only: implementers get self-contained prompts with the
   exact task text, reviewers return PASS/FAIL + findings, and file contents never round-trip
   through the coordinator.
