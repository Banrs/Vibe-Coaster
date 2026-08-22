# Geometric Return Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the globally coupled return/capture solve with order-generic macro geometry and local, distance-domain FVD elements that close the canonical fleet honestly within every existing contract.

**Architecture:** `Motion` gains one physically equivalent arc-length integration path for spatial curvature and twist profiles. A pure return layout solve with five bounded controls allocates length and endpoint frames; local turn/height builders realize one assignment at a time; a neutral capture and one-dimensional spatial brake replace the visible five-axis terminal correction. `RideProgram` orchestrates these owners and deletes `ride_return_solve.gd` in the production cutover.

**Tech Stack:** Godot 4.7.1, typed GDScript, existing RK4/FVD kernel and bounded linear algebra, GitHub Actions, GitHub CLI, PowerShell.

**Spec:** `docs/superpowers/specs/2026-08-22-return-macro-layout-design.md`

## Global Constraints

- Read the spec completely before editing and treat it as authoritative over this plan if wording differs.
- Fable is the primary coordinator in Claude Code. Use Haiku for bounded repository discovery and CI-log extraction, Sonnet for most TDD implementation and routine review, and Opus for FVD mathematics, macro-layout architecture, and final acceptance review.
- Agent routing is advisory, not a repository dependency. The committed code and tests must not mention any model, agent, or execution product.
- Apply all four global `CLAUDE.md` rules on every task: Think Before Coding, Simplicity First, Surgical Changes, and Goal-Driven Execution.
- “Surgical” constrains scope, not legacy-line preservation. Rewrite any affected implementation when the verified result is materially smaller or clearer.
- Use local Godot (`D:\Games\Godot_v4.7.1-stable_win64.exe`, or the `GODOT` environment variable) freely to iterate: run the editor import and any focused suite before pushing. GitHub Actions CI on the PR is the RED/GREEN verdict — a local run is a fast check, never the evidence a step is complete.
- Preserve the untracked `HANDOFF_NEXT_AGENT.md` and unrelated changes in the main checkout.
- Do not alter the existing 7.8–8.2 km route band, role-length bands, force envelopes, convergence tolerances, terrain intent, or existing solver caps to make the rewrite pass.
- The return has no positive drive or midcourse brake. Gravity plus the existing rolling/aerodynamic resistance law owns passive speed.
- `Motion` integration is the sole centreline authority. Macro geometry and element previews are targets; integrated mismatch rejects the candidate.
- No seed-specific branch, warm start, retry, fallback topology, tolerance, or evaluation budget. Seed 4096 is one fleet member.
- Planner order is resolved once on `story.return`. Local failure never changes that order.
- Prefer closed form, bounded water-filling, or one-dimensional solving. The only multi-variable solve added by this plan is the macro geometry solve: five bounded controls against four residuals (spec §7.4).
- Spatial profiles use actual integrated arc length. Time profiles remain for launches and station motion.
- Do not invent an average-G acceptance threshold. The final force summary is evidence only.
- Honest physics is inherited, not validated. The frozen `AERO_PER_M = 7.5e-5` (`CdA ~ 1.73 m^2` for a 12 t train, ~2.8x under-damped against `docs/superpowers/specs/2026-08-15-honest-drag-derivation.md`) is the sole reason the return arrives at 70–80 m/s and needs a ~2.2 g mean brake inside 150 m. This rewrite inherits that terminal condition. No commit message, comment, report, or review may describe a green fleet here as validating that drag constant.
- Commit each RED test separately, then commit its GREEN implementation. The final PR may be squash-merged after review.
- After every push, identify the new CI run from the current branch rather than reusing an older run ID:

```powershell
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
```

- For an expected RED run, inspect only the intended failure and confirm no earlier import failure obscured it:

```powershell
gh run view $run --log-failed
```

---

## File Structure

New test suites use the shared `TestUtil` (`godot/test_util.gd`) assertion helpers and `RouteFixture`
(`godot/route_fixture.gd`) synthetic-route builders, which exist by the time this plan runs. The
test-local constructors written out in the tasks below are the fixtures those helpers do not cover;
keep them local rather than promoting them.

- Modify `godot/motion.gd`: add distance-domain RK4 spans whose curvature and twist remain physically coupled to speed and proper force.
- Modify `godot/motion_tests.gd`: exact-length, curvature, twist, force-projection, seam, and step-halving tests.
- Modify `godot/ride_planner.gd`: legal return permutations and one named-stream order decision.
- Modify `godot/ride_planner_tests.gd`: all 24 permutations, stream independence, determinism, and malformed-order rejection.
- Modify `godot/generator.gd`: publish order-neutral return role geometry/terrain contracts.
- Modify `godot/generator_material_tests.gd`: plan schema and no-rescue assertions.
- Create `godot/ride_return_layout.gd`: terminal gate, bounded length allocation, five-control macro solve, terrain/energy margins, and immutable assignments.
- Create `godot/ride_return_layout_tests.gd`: allocation, all-order synthetic closure, infeasibility, determinism, and zero-feedback tests.
- Create `godot/ride_return_elements.gd`: spatial preview plus concrete overbanked-turn and vertical-height builders.
- Create `godot/ride_return_elements_tests.gd`: preview/integration agreement, speed invariance, counter-lateral band, planarity, C4, and structured local failure.
- Create `godot/ride_terminal.gd`: neutral capture, one-dimensional spatial brake solve, and station creep.
- Create `godot/ride_terminal_tests.gd`: straight-frame capture, exact distance/speed, force limits, budget, and malformed-corridor tests.
- Rewrite `godot/ride_program.gd` at the prefix/return/terminal seam: fixed prefix, one layout call, order-generic local build loop, and terminal build.
- Rewrite return-specific portions of `godot/ride_program_tests.gd`: production orchestration, ownership, no global solve, and fleet-budget fixtures.
- Modify `godot/route_contract.gd`: validate accepted layout/element evidence and direct C4/terminal contracts.
- Modify `godot/route_contract_tests.gd`: malformed evidence and integrated-mismatch rejection.
- Modify `godot/geometry_metrics.gd` and `godot/geometry_audit_tests.gd`: direct integrated `x^(0..4)` seam evidence and return role geometry.
- Modify `godot/fidelity.gd` and `godot/fidelity_tests.gd`: sample/time-weighted normal and resultant-G evidence.
- Modify `godot/fidelity_artifacts.gd` and `godot/fidelity_artifact_tests.gd`: publish force summaries in the audit artifact.
- Modify `.github/focused-tests.txt`: add the three focused return suites and restore `camelback_geometry_tests.gd` when its production path turns green.
- Delete `godot/ride_return_solve.gd` and `godot/ride_return_solve.gd.uid`: remove the global return and five-axis capture implementation after cutover.
- Modify `docs/ISSUES.md`, `CLAUDE.md`, and `README.md` only where they describe the deleted solver or the verified final behavior.

---

### Task 1: Distance-Domain FVD Kernel

**Files:**

- Modify: `godot/motion_tests.gd`
- Modify: `godot/motion.gd`

**Interfaces:**

- Produces: `Motion.spatial_span(span_id: String, length_m: float, pitch_curvature_m_inv: Dictionary, yaw_curvature_m_inv: Dictionary, drive_g: Dictionary, twist_rad: Dictionary, transition_id: String = "") -> Dictionary`
- Produces: spatial-span integration through the existing `Motion.integrate(initial_state, spans, settings) -> Dictionary` API.
- Guarantees: integrated length ends at the declared `length_m`; published `normal_g`, `lateral_g`, `roll_rate_rad_s`, curvature, speed, time, position, and frame all come from the same RK stages.
- Preserves: `Motion.span(...)` and every existing temporal caller unchanged.

- [ ] **Step 1: Add failing spatial-span tests**

Append these calls to `_initialize()` and implement the fixtures in `motion_tests.gd`:

```gdscript
_test_spatial_straight_ends_at_exact_length()
_test_spatial_quarter_circle_matches_curvature()
_test_spatial_twist_uses_actual_distance()
_test_spatial_force_projection_matches_curvature()
_test_spatial_step_halving_converges()
```

The first two fixtures must contain these assertions:

```gdscript
func _test_spatial_straight_ends_at_exact_length() -> void:
	var state := _moving_state(Vector3.ZERO, Vector3.RIGHT, Vector3.UP, 40.0)
	var span := Motion.spatial_span("spatial/straight", 100.0,
		Motion.constant(0.0), Motion.constant(0.0), Motion.constant(0.0),
		Motion.constant(0.0))
	var route := Motion.integrate(state, [span], {"step_s": 0.01,
		"gravity_mps2": Vector3.ZERO, "rolling_mps2": 0.0, "aero_per_m": 0.0})
	_expect(route.get("ok", false), "spatial straight integrates")
	_expect_close(route.distance_m[-1], 100.0, "spatial span ends at its exact length", 0.000001)
	_expect(route.position_m[-1].distance_to(Vector3(100.0, 0.0, 0.0)) <= 0.0001,
		"spatial straight endpoint follows its tangent")

func _test_spatial_quarter_circle_matches_curvature() -> void:
	var radius := 100.0
	var length_m := 0.5 * PI * radius
	var span := Motion.spatial_span("spatial/quarter-circle", length_m,
		Motion.constant(0.0), Motion.constant(1.0 / radius), Motion.constant(0.0),
		Motion.constant(0.0))
	var route := Motion.integrate(_moving_state(Vector3.ZERO, Vector3.RIGHT, Vector3.UP, 40.0),
		[span], {"step_s": 0.005, "gravity_mps2": Vector3.ZERO,
			"rolling_mps2": 0.0, "aero_per_m": 0.0})
	_expect(route.position_m[-1].distance_to(Vector3(radius, 0.0, radius)) <= 0.02,
		"constant spatial curvature makes a quarter circle")
	_expect(route.tangent[-1].distance_to(Vector3.BACK) <= 0.0002,
		"quarter circle turns its tangent by ninety degrees")
```

Add this test-local constructor; reuse the existing `_settings(step_s)` and `_expect*` helpers:

```gdscript
func _moving_state(position: Vector3, tangent: Vector3, up: Vector3, speed_mps: float) -> Dictionary:
	return {"position_m": position, "tangent": tangent.normalized(),
		"rider_up": up.normalized(), "speed_mps": speed_mps,
		"distance_m": 0.0, "time_s": 0.0}
```

Use the production force identity for the projection fixture:

```text
yaw_normal = normalize(t cross world_up)
pitch_normal = normalize(yaw_normal cross t)
kappa = kappa_pitch pitch_normal + kappa_yaw yaw_normal
kappa_u = kappa dot rider_up
kappa_r = kappa dot rider_right
g_perp = g - t (g dot t)
n = (v^2 kappa_u - g_perp dot u) / g0
l = (v^2 kappa_r - g_perp dot r) / g0
omega = v d(phi)/ds
```

- [ ] **Step 2: Commit and push RED**

```powershell
git add godot/motion_tests.gd
git commit -m "test: specify distance-domain FVD spans"
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
gh run view $run --log-failed
```

Expected: import succeeds; `motion_tests.gd` fails because `Motion.spatial_span` is undefined. No production route has changed.

- [ ] **Step 3: Implement the spatial span and distance-domain RK4**

Use the same state, resistance, frame orthonormalization, and rejection rules as the temporal path. Reparameterize the moving equations by arc length for `v > 0`:

```text
dx/ds = t
dt/ds = kappa_pitch pitch_normal + kappa_yaw yaw_normal
du/ds = -t ((dt/ds) dot u) + (d(phi)/ds) r
dv/ds = (g dot t + g0 d - rolling - aero v^2) / v
dtime/ds = 1 / v
```

At each stage derive `yaw_normal = normalize(t cross world_up)` and
`pitch_normal = normalize(yaw_normal cross t)`, then project the resulting world-space curvature
onto rider-up/right for proper-force publication. Reject a spatial span whose tangent is too close to
world vertical for that basis; no return family is allowed to cross that singularity.

At each RK stage, derive proper force and roll rate from that same stage's speed/frame. Use
`h_m = min(remaining_length_m, speed * settings.step_s)` as the maximum spatial step, then RK4 the spatial equations and terminate exactly at the declared length. Reject nonpositive speed at every stage.

The constructor record is immutable and has this exact shape:

```gdscript
{"span_id": span_id, "domain": "distance", "length_m": length_m,
 "pitch_curvature_m_inv": pitch_curvature_m_inv,
 "yaw_curvature_m_inv": yaw_curvature_m_inv,
 "drive_g": drive_g, "twist_rad": twist_rad,
 "transition_id": transition_id}
```

Temporal records gain `"domain": "time"` internally only if that makes dispatch smaller; do not require callers to pass it.

- [ ] **Step 4: Push GREEN and inspect complete CI**

```powershell
git add godot/motion.gd godot/motion_tests.gd
git commit -m "feat: integrate spatial FVD spans by distance"
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
```

Expected: all existing motion/route tests remain green; smoke route hashes and visuals remain unchanged because production uses no spatial span yet.

- [ ] **Step 5: Run the Task 1 review gate**

Have Opus review the equations, RK staging, exact endpoint, frame transport, `v > 0` guards, and proper-force publication. Have Sonnet review for duplicate temporal/spatial integration code. Reject the task if common RK operations can be shared with fewer branches without changing the equations.

Commit review-only corrections as:

```powershell
git add godot/motion.gd godot/motion_tests.gd
git commit -m "refactor: simplify spatial motion integration"
```

---

### Task 2: Order-Generic Return Grammar

**Files:**

- Modify: `godot/ride_planner_tests.gd`
- Modify: `godot/ride_planner.gd`
- Modify: `godot/generator_material_tests.gd`
- Modify: `godot/generator.gd`

**Interfaces:**

- Produces: `RidePlanner.RETURN_ROLES := ["return-turn-a", "return-height-a", "return-turn-b", "return-height-b"]`
- Produces: `RidePlanner.return_order(sequence: Array) -> Array`
- Produces: `RidePlanner.with_return_order(sequence: Array, order: Array) -> Array`
- Guarantees: `is_legal_sequence()` accepts each permutation exactly once and rejects missing/duplicate/non-return roles.
- Defers: consuming `story.return` in production until Task 7, so the old fixed emitter stays green during intermediate tasks.

- [ ] **Step 1: Add failing permutation and stream-isolation tests**

Generate all permutations recursively in the test; do not paste a 24-entry table. Assert:

```gdscript
for order in _permutations(RidePlanner.RETURN_ROLES):
	var sequence := RidePlanner.with_return_order(RidePlanner.canonical_role_ids(), order)
	_expect(RidePlanner.is_legal_sequence(sequence), "return permutation is grammar-legal: %s" % str(order))
	_expect(RidePlanner.return_order(sequence) == order, "return order round-trips")

var duplicated := RidePlanner.RETURN_ROLES.duplicate()
duplicated[3] = duplicated[0]
_expect(not RidePlanner.is_legal_sequence(
	RidePlanner.with_return_order(RidePlanner.canonical_role_ids(), duplicated)),
	"duplicate return role is illegal")
```

Use this exact test helper:

```gdscript
func _permutations(values: Array) -> Array:
	if values.is_empty(): return [[]]
	var result: Array = []
	for index in values.size():
		var rest := values.duplicate()
		var head: Variant = rest.pop_at(index)
		for suffix: Array in _permutations(rest):
			result.append([head] + suffix)
	return result
```

Record all non-return draw bytes before and after an explicit return-order override and assert identity. This proves the named stream cannot perturb terrain, placement, act-one, or target draws.

- [ ] **Step 2: Commit and push RED**

```powershell
git add godot/ride_planner_tests.gd godot/generator_material_tests.gd
git commit -m "test: require order-generic return stories"
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
gh run view $run --log-failed
```

Expected: `ride_planner_tests.gd` fails on missing `RETURN_ROLES`, `return_order`, and `with_return_order`.

- [ ] **Step 3: Implement generic legality without changing production order**

Replace the positional `RETURN_CELL` equality check with a permutation check:

```gdscript
static func return_order(sequence: Array) -> Array:
	var order: Array = []
	for role_id in sequence:
		if RETURN_ROLES.has(role_id): order.append(role_id)
	return order

static func _valid_return_order(order: Array) -> bool:
	if order.size() != RETURN_ROLES.size(): return false
	for role_id in RETURN_ROLES:
		if order.count(role_id) != 1: return false
	return true
```

Keep `_draw_sequence()` canonical in this task. Add order-neutral `geometry` intent to the four generator role records using existing bands and family names only; do not invent new numeric audit bands. The layout derives curvature/elevation feasibility from length, force, terrain, and speed contracts.

- [ ] **Step 4: Push GREEN and review**

```powershell
git add godot/ride_planner.gd godot/ride_planner_tests.gd godot/generator.gd godot/generator_material_tests.gd
git commit -m "feat: make return grammar order-generic"
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
```

Expected: all 24 grammar fixtures pass; production bytes remain unchanged.

- [ ] **Step 5: Apply the four-rule review**

Fable records PASS/FAIL for all four global `CLAUDE.md` rules. In particular, reject a generic permutation framework outside the four return roles and reject any lookup keyed by seed.

---

### Task 3: Pure Macro Return Layout

**Files:**

- Create: `godot/ride_return_layout_tests.gd`
- Create: `godot/ride_return_layout.gd`
- Modify: `.github/focused-tests.txt`

**Interfaces:**

- Produces: `RideReturnLayout.allocate_lengths(nominals: Array, bands: Array, weights: Array, total_m: float) -> Dictionary`
- Produces: `RideReturnLayout.build(start: Dictionary, plan: Dictionary, ordered_roles: Array) -> Dictionary`
- Produces immutable result keys: `ok`, `assignments`, `terminal_gate`, `target_total_length_m`, `length_budget_margin_m`, `terrain_margins`, `energy_margins`, `report`, and `errors`.
- Each assignment has exact keys: `role_id`, `family`, `entry_frame`, `exit_frame`, `target_length_m`, `corridor`, `terrain_intent`, `curvature_sign`, `heading_change_rad`, and `elevation_change_m`.
- `entry_frame`, `exit_frame`, and `terminal_gate` are dictionaries with finite `position_m: Vector3`, unit `tangent: Vector3`, and unit orthogonal `rider_up: Vector3`.
- `curvature_sign`, `heading_change_rad`, `elevation_change_m`, and `target_length_m` are finite floats; turn signs are exactly `-1.0` or `1.0`, while height roles publish `0.0` curvature sign.
- Uses exactly five bounded controls: signed heading change for turn A/B, signed net elevation for height A/B, and the bounded return total length `S_return`. Role controls are addressed by role ID, never list index.
- Publishes the per-turn heading feasibility bound and its margin; a turn whose requested heading exceeds the bound is rejected here, not downstream.

- [ ] **Step 1: Add focused RED tests and manifest entry**

Add `res://ride_return_layout_tests.gd` immediately after `res://motion_tests.gd` in `.github/focused-tests.txt`.

The test entry point must run:

```gdscript
_test_bounded_allocation_hits_exact_sum()
_test_bounded_allocation_rejects_impossible_sum()
_test_terminal_gate_comes_from_station_corridor()
_test_heading_bound_rejects_an_infeasible_turn()
_test_all_return_orders_close_synthetic_frames()
_test_layout_is_byte_deterministic()
_test_local_failure_feedback_cannot_change_layout()
_test_energy_bound_rejects_hidden_drive()
```

Use this exact allocation fixture:

```gdscript
var allocation := Layout.allocate_lengths(
	[480.0, 420.0, 500.0, 520.0],
	[Vector2(420.0, 620.0), Vector2(290.0, 480.0),
	 Vector2(430.0, 570.0), Vector2(450.0, 590.0)],
	[1.0, 1.0, 1.0, 1.0], 2000.0)
_expect(allocation.ok, "bounded allocation is feasible")
_expect(absf(_sum(allocation.lengths) - 2000.0) <= 0.000001,
	"bounded allocation hits the exact return budget")
```

Add the test-local sum helper:

```gdscript
func _sum(values: Array) -> float:
	var total := 0.0
	for value in values: total += float(value)
	return total
```

The zero-feedback test builds once, mutates only an external fake failure record, builds again, and requires `var_to_bytes(first) == var_to_bytes(second)`.

- [ ] **Step 2: Commit and push RED**

```powershell
git add godot/ride_return_layout_tests.gd .github/focused-tests.txt
git commit -m "test: specify macro return layout"
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
gh run view $run --log-failed
```

Expected: import succeeds and the new suite fails because `ride_return_layout.gd` does not exist.

- [ ] **Step 3: Implement bounded water-filling**

Implement the monotone projection exactly:

```text
L_i(lambda) = clamp(N_i + lambda w_i, lower_i, upper_i)
sum L_i(lambda) = total_m
```

Reject non-finite/nonpositive weights and infeasible totals before bisection. Stop when the sum error is at most `1e-6 m`; return the remaining distance as a signed diagnostic, not a relaxed tolerance.

- [ ] **Step 4: Implement the terminal gate and five-control macro solve**

The terminal gate is fixed:

```gdscript
var gate_position: Vector3 = plan.station.position_m \
	- plan.station.tangent.normalized() * float(plan.corridor.approach_length_m)
```

Build a nominal spatial chain in the planner's role order. Turn roles consume signed heading change; height roles consume signed net elevation and zero net heading. Each family uses quintic curvature shoulders with zero first/second spatial derivatives. Solve four residuals in the station frame:

```text
cross-track position
vertical position
forward position
terminal yaw
```

against five bounded controls:

```text
delta_psi_a, delta_psi_b        signed heading change, turn A and turn B
delta_h_a,   delta_h_b          signed net elevation, height A and height B
S_return                        bounded return total length
```

The four role controls alone are rank-deficient against those residuals, which is why `S_return` is a control and not a pre-chosen number: terminal yaw fixes only `psi_a + psi_b`, leaving cross-track and forward both driven by `psi_a` alone, and the two elevations enter only the vertical residual. `S_return` is bounded by the 7.8–8.2 km route band once the prefix is accepted — it is a band, not a fixed number — and each evaluation water-fills the Step 3 allocation to the currently proposed `S_return`, so allocation stays a deterministic function of the control vector rather than a separate stage. Solve with the existing `BoundedSolver` damped bounded least-squares, regularised toward the nominal control vector; the two elevation controls split the vertical residual by their nominal weights so their mutual degeneracy resolves deterministically.

Do not add total length, role length, speed, bank, or local timing residuals; those are allocated facts or separate feasibility margins.

**Gate pitch and roll are not residuals.** They are closed by construction: the height family's exit-frame contract ends at zero pitch and the turn family's ends at zero bank, so whichever role is last hands the gate a level, unbanked frame. Do not add gate pitch/roll residuals to re-derive what the element contracts already guarantee.

Declare the residual scales explicitly so the shared convergence language means one thing:

```text
cross    5 m
vertical 5 m
forward  5 m
yaw      0.02 rad
```

A scaled residual of 0.02 is therefore 0.1 m of position error and 0.0004 rad of yaw error at the gate.

Enforce the per-turn heading feasibility bound before accepting any candidate:

```text
|delta_psi| <= 0.8 L g0 tan(phi_max) / v^2
```

`L` is the allocated role length, `v` the entry speed, and `phi_max` the family bank ceiling; `0.8` is the loaded fraction of the arc once both quintic shoulders are reserved. At the declared role bands and the 70–80 m/s entry band this admits roughly 75–111° for turn A and 77–102° for turn B. A 180° reversal (dogbone) is refused by this bound — it would need 3.3–6.2 g of normal load against a 4.0 g held limit — so do not implement a reversal topology or any special case that reaches one.

The layout evaluation cap follows the repository's own derivation `1 + K(n + 1) + R`. With `n = 5` the Jacobian costs six probes per iteration, so reuse the existing `MAX_RETURN_EVALUATIONS = 88`; introduce no new cap and move no existing one.

The macro energy bound evaluates:

```text
d(v^2 / 2)/ds = g dot t - rolling - aero v^2
```

over conservative tangent/elevation envelopes. It may reject; it may not add drive or modify order.

- [ ] **Step 5: Push GREEN and review every permutation**

```powershell
git add godot/ride_return_layout.gd godot/ride_return_layout_tests.gd
git commit -m "feat: plan return anchors and length budgets"
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
```

Expected: all 24 synthetic orders produce ordered assignments with positive margins; infeasible length/terrain/energy fixtures fail before any element build.

- [ ] **Step 6: Opus architecture gate**

Require a written PASS/FAIL on: exactly five bounded controls (four role controls plus `S_return`) against four residuals, no force-profile/timing/bank controls, no gate pitch or roll residual, no seed/order branches, no retry, no role-band residual, and no second centreline authority. Commit only corrections that reduce or clarify this boundary.

---

### Task 4: Local Spatial Return Elements

**Files:**

- Create: `godot/ride_return_elements_tests.gd`
- Create: `godot/ride_return_elements.gd`
- Modify: `.github/focused-tests.txt`

**Interfaces:**

- Produces: `RideReturnElements.preview(assignment: Dictionary, step_m: float = 1.0) -> Dictionary`
- Produces: `RideReturnElements.build(start: Dictionary, assignment: Dictionary, settings: Dictionary) -> Dictionary`
- Returns exact keys: `ok`, `spans`, `trajectory`, `end_state`, `observation`, `margins`, `evaluation_count`, and `errors`.
- Supports only the two required families: `return_turn` and `return_height`.
- A turn uses allocated length plus signed heading change; a height uses allocated length plus signed elevation change and its existing planner targets.

- [ ] **Step 1: Add RED tests and manifest entry**

Add `res://ride_return_elements_tests.gd` after the layout suite. Test these cases:

```gdscript
_test_turn_preview_matches_integrated_geometry_at_70_and_80_mps()
_test_turn_bank_and_curvature_sign_agree()
_test_turn_lateral_lands_inside_the_counter_lateral_band()
_test_height_is_vertical_plane_at_70_and_80_mps()
_test_height_has_one_pitch_zero_apex_and_monotone_phases()
_test_element_seams_meet_the_c4_contract()
_test_impossible_corridor_returns_one_structured_failure()
```

The speed-invariance assertion compares integrated endpoints after subtracting/rotating by their entry frame:

```gdscript
var slow := Elements.build(_state(70.0), assignment, _settings())
var fast := Elements.build(_state(80.0), assignment, _settings())
_expect(slow.ok and fast.ok, "turn builds across its entry-speed band")
_expect(_local_end(slow).position.distance_to(_local_end(fast).position) <= 0.05,
	"spatial turn identity is speed-invariant")
_expect(_angle(_local_end(slow).tangent, _local_end(fast).tangent) <= 0.0001,
	"spatial turn heading is speed-invariant")
```

Use explicit test helpers so entry-frame normalization is not reimplemented in each fixture:

```gdscript
func _state(speed_mps: float) -> Dictionary:
	return {"position_m": Vector3.ZERO, "tangent": Vector3.RIGHT,
		"rider_up": Vector3.UP, "speed_mps": speed_mps,
		"distance_m": 0.0, "time_s": 0.0}

func _settings() -> Dictionary:
	return {"step_s": 0.01, "gravity_mps2": Vector3.DOWN * Motion.G0,
		"rolling_mps2": RideProgram.ROLLING_MPS2, "aero_per_m": RideProgram.AERO_PER_M}

func _local_end(result: Dictionary) -> Dictionary:
	var end: Dictionary = result.end_state
	return {"position": end.position_m - result.trajectory.position_m[0],
		"tangent": end.tangent}

func _angle(a: Vector3, b: Vector3) -> float:
	return acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0))
```

- [ ] **Step 2: Commit and push RED**

```powershell
git add godot/ride_return_elements_tests.gd .github/focused-tests.txt
git commit -m "test: specify local spatial return elements"
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
gh run view $run --log-failed
```

Expected: the new suite fails because `ride_return_elements.gd` is absent.

- [ ] **Step 3: Implement the overbanked-turn family**

Use one semantic spatial span with a staged **yaw-curvature** profile and zero pitch curvature. Reserve 20% of length for each quintic shoulder and 60% for the core. Quintic shoulder area is one half, so derive peak yaw curvature without a solve:

```text
kappa_peak = heading_change_rad / (0.8 target_length_m)
```

Because yaw curvature is defined against world-up before projection into the rolling rider frame,
twist changes rider loads without tilting the planned centreline out of its horizontal turn plane. Use
the actual integrated speed history to solve only peak twist/bank, and solve it **to the counter-lateral band, not to balance**:

```text
f = v^2 kappa - g_perp
l = (f dot rider_right) / g0
accept when 0.2 <= |l_peak| <= 0.6 and l is signed down the bank (toward the turn centre)
```

`CLAUDE.md` names two overbanked turns on the return, so a laterally neutral turn is a contract failure here, not a success. The band is the measured Falcon counterpart: 77° of bank at `n = 2.39 g`, whose balanced bank would be 65.8°, gives `l = (n cos(phi) - 1) / sin(phi) ~ -0.47 g`. Lateral of the opposite sign — outward, an underbank — is rejected outright.

The twist profile is one continuous quintic-in/hold/quintic-out narrative. It must start/end with zero twist rate and acceleration, so the exit frame is unbanked as the layout's terminal contract assumes. Reject a bank sign that disagrees with signed horizontal curvature; do not flip it to rescue closure.

- [ ] **Step 4: Implement the vertical-height family**

Use one fixed vertical plane through the entry tangent. Solve the minimum local scalar set needed to hit the assignment's endpoint elevation and pitch while satisfying the existing length and target unload values. The apex check is:

```text
theta = 0
d(theta)/ds < 0
dy/ds > 0 before apex
dy/ds < 0 after apex
prominence = y_apex - max(y_entry, y_exit)
```

Use one staged spatial-curvature profile with analytically matched value/first/second derivatives. No internal semantic span, pulse restart, neutral pause, or micro-hold is allowed.

- [ ] **Step 5: Implement seam and corridor evidence at the order each is measurable**

Do not finite-difference positions for the high orders. Published positions are float32 `Vector3`; at the production spacing `h ~ 0.75 m` a fourth-order difference of position produces roughly `3e-3 m^-3` of quantisation noise against a `2.25e-6 m^-3` signal, so an FD-based C4 seam check would measure rounding with a threshold attached.

Split the evidence by order:

- Compare `x^(0..2)` — position, tangent, and world-space curvature vector — **directly** from the integrated route on both sides of the seam. Starting tolerances, to be confirmed by measurement once the fleet is green: position `1e-3 m`, tangent `1e-4` (unit-vector distance), curvature `1e-5 m^-1`.
- Compute `x^(3)` and `x^(4)` **analytically** from each side's commanded curvature jets through the frame ODE: with arc length as the parameter, `x' = t`, `x'' = kappa`, `x''' = kappa'`, `x'''' = kappa''`, where `kappa'` and `kappa''` are world-space derivatives and therefore include the derivatives of the evolving pitch/yaw basis, not only the commanded component slopes. The seam requires the two published analytic jets to agree.
- Keep a finite difference of the higher orders as a **coarse sanity check only**: it may flag an order-of-magnitude disagreement between the analytic jets and the integrated path, and it carries no tight tolerance and no veto.

Publish all margins in the returned result and reject any negative/non-finite value.

- [ ] **Step 6: Push GREEN and run two-stage review**

```powershell
git add godot/ride_return_elements.gd godot/ride_return_elements_tests.gd
git commit -m "feat: build local spatial return elements"
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
```

Expected: preview and integrated geometry agree across 70/80 m/s; force/bank/planarity/C4 tests pass; production remains byte-identical because no caller uses the new builders.

Have Opus review the physics and Sonnet review code size/ownership. Reject lookup curves, post-fit positions, generic family abstractions, or more than the minimum local solve dimensions.

---

### Task 5: Neutral Capture and One-Dimensional Brakes

**Files:**

- Create: `godot/ride_terminal_tests.gd`
- Create: `godot/ride_terminal.gd`
- Modify: `.github/focused-tests.txt`

**Interfaces:**

- Produces: `RideTerminal.build(start: Dictionary, layout: Dictionary, settings: Dictionary) -> Dictionary`
- Returns: `ok`, `spans`, `trajectory`, `report`, `margins`, and `errors`.
- Capture is a zero-curvature, zero-twist, zero-drive spatial span of `corridor.capture_length_m`.
- Brake moving distance is `corridor.brake_length_m - station_creep_distance_m` and is exact by spatial construction.
- Only solved brake control: peak negative `drive_g`; endpoint residual: moving-boundary speed minus `2.0 m/s`, with the stopping shortfall standing in for that residual when the train stops early.
- Brake evaluation cap: 32 unique evaluations.

- [ ] **Step 1: Add RED terminal tests**

Test entry speeds 70, 75, and 80 m/s on axis-aligned and rotated station frames:

```gdscript
for speed in [70.0, 75.0, 80.0]:
	var built := Terminal.build(_capture_start(speed), _layout(), _settings())
	_expect(built.ok, "terminal builds at %.1f m/s" % speed)
	_expect(built.report.capture_steering_controls == 0,
		"capture has no visible steering solve")
	_expect(absf(built.report.moving_boundary_speed_mps - 2.0) <= 0.0001,
		"spatial brake reaches the moving boundary speed")
	_expect(built.report.unique_evaluations <= 32,
		"one-dimensional brake stays inside its cap")
```

Also require exact station pose, no positive drive, peak brake no greater than the existing 3.6 g cap, and structured rejection outside the 70–80 m/s/corridor partition.

Use these test-local constructors; rotate all three frame vectors together for the rotated fixture:

```gdscript
func _capture_start(speed_mps: float) -> Dictionary:
	return {"position_m": Vector3.ZERO, "tangent": Vector3.RIGHT,
		"rider_up": Vector3.UP, "speed_mps": speed_mps,
		"distance_m": 0.0, "time_s": 0.0}

func _layout() -> Dictionary:
	return {"station_position_m": Vector3(230.0, 0.0, 0.0),
		"station_tangent": Vector3.RIGHT, "station_up": Vector3.UP,
		"reserved_corridor": {"minimum_length_m": 230.0,
			"capture_length_m": 80.0, "brake_length_m": 150.0,
			"entry_speed_mps": Vector2(70.0, 80.0)}}

func _settings() -> Dictionary:
	return RideProgram._settings(0.01)
```

- [ ] **Step 2: Commit and push RED**

```powershell
git add godot/ride_terminal_tests.gd .github/focused-tests.txt
git commit -m "test: specify neutral capture and spatial brakes"
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
gh run view $run --log-failed
```

Expected: the terminal suite fails because `ride_terminal.gd` is absent.

- [ ] **Step 3: Implement neutral capture and scalar brake solve**

Build the capture with `Motion.spatial_span(... curvature=0, drive=0, twist=0)`. Build a distance-domain brake drive profile with quintic shoulders and a held negative peak. Since spatial length is exact, solve only:

```text
F(peak_brake_g) = integrated_end_speed_mps - 2.0
```

`F` must be **defined over the whole bracket**, including the upper half where the integration cannot reach the end of the span. Above the operating point the train stops before the span ends — at 3.6 g it stops in about 90 m of the 147 m moving span — and the integrator terminates early. That is not a failure to abort on: return the **stopping shortfall** (the metres of span left unused, expressed as a positive residual) in place of the speed residual. `F` then stays monotone and the bracket stays valid across all of `[0.0, 3.6]`, which is what makes bisection legitimate rather than lucky.

Use monotone bounded bisection on `[0.0, 3.6]`, at most 32 unique evaluations. Append the existing physical 2→1 m/s station creep only after the moving brake reaches its exact boundary.

The operating point sits comfortably inside the bound: shedding 80 m/s over the 147 m moving span needs a mean of 2.19 g, and the shouldered profile peaks at roughly 2.0–2.6 g across the 70–80 m/s entry band against the 3.6 g bound. That is above real magnetic practice — measured eddy-current brake runs sit at 1.0–1.5 g — because this is a held friction/hydraulic deceleration profile, whose retardation does not decay with speed the way an eddy-current brake's does. Say so where the profile is defined; do not describe it as an eddy-current brake.

- [ ] **Step 4: Push GREEN and simplify**

```powershell
git add godot/ride_terminal.gd godot/ride_terminal_tests.gd
git commit -m "feat: close the station with neutral capture and scalar brakes"
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
```

Expected: all terminal fixtures pass without a Jacobian, steering coefficients, padding span, or positive drive. Production remains unchanged until Task 7.

- [ ] **Step 5: Review against VC-008**

With capture coefficients conceptually zero because none exist, require the route to stay inside the pre-capture pose corridor: ±150 m cross, ±75 m height, 8° yaw, 5° pitch, 30° roll. Opus verifies the brake energy math; Sonnet verifies the rewrite is shorter than the capture/brake portion it will delete.

---

### Task 6: Independent Record Release and Planar Camelback

**Files:**

- Modify: `godot/camelback_geometry_tests.gd`
- Modify: `godot/ride_program_tests.gd`
- Modify: `godot/ride_program.gd`
- Modify: `.github/focused-tests.txt`

**Interfaces:**

- Produces fixed, independently accepted record-release and camelback spans before return layout.
- Record release owns its 340–390 m role, 55–65° bank intent, and horizontal-turn planarity.
- Camelback owns its 900–1180 m role, 245–255 m prominence, vertical-plane contract, pitch-zero apex, and its declared `apex_agl_m` band of 140–170 m (the repository contract in `generator.gd`; there is no 155 m terrace figure).
- Camelback rise/fall symmetry is numeric: `|rise arc - fall arc| <= 5 m`.
- Neither prefix role exposes duration, bank, or fall controls to return layout.

- [ ] **Step 1: Restore the existing RED camelback suite to the manifest**

Add `res://camelback_geometry_tests.gd` after `res://element_contract_integration_tests.gd`. Extend it to assert no return-owned parameters are present in the compiled prefix report.

Use the preserved measured recipe at historical object `dfae8e1:.github/apply_planar_camelback.py` only as evidence for the accepted geometry:

```text
length 1178.994 m
prominence 247.430 m
exit height -0.489 m
exit pitch -0.096 deg
apex pitch -0.098 deg
rise/fall arc imbalance 3.666 m
```

Two facts about that recipe matter when the GDScript owner is rewritten. Its 3.666 m imbalance is what
sets the symmetry tolerance at `|rise arc - fall arc| <= 5 m` — the tolerance is measured, not chosen
round. And its 1178.994 m sits about 1 m under the 1180 m band ceiling, so the rewrite has almost no
length headroom on this role: a longer camelback fails the band rather than borrowing from it.

Do not restore or run the Python patch script; rewrite the GDScript owner directly with spatial profiles.

- [ ] **Step 2: Commit and push RED**

```powershell
git add godot/camelback_geometry_tests.gd godot/ride_program_tests.gd .github/focused-tests.txt
git commit -m "test: restore the planar camelback contract"
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
gh run view $run --log-failed
```

Expected: the camelback suite reports the existing plane tilt/heading drift and/or return-owned prefix controls. This RED is expected; Task 7 performs the atomic production cutover, so do not leave the PR at this commit longer than needed.

- [ ] **Step 3: Rewrite both prefix owners with spatial FVD profiles**

Record release uses the same spatial curvature/twist mathematics as a balanced turn but remains a private prefix builder. Camelback uses one vertical-plane staged spatial-curvature span with a pitch-zero descending apex and one continuous pullout/release. Preserve the adopted geometry intent already encoded by `camelback_geometry_tests.gd`; remove the 0.01 s pseudo-hold and every lateral/alternating-roll pulse.

Do not make this intermediate production commit separately. Carry these working-tree changes directly into Task 7's cutover commit so the obsolete return solver never receives the new handoff on a purported GREEN revision.

---

### Task 7: Atomic Production Cutover and Old-Solver Deletion

**Files:**

- Rewrite: `godot/ride_program.gd`
- Rewrite return-specific tests: `godot/ride_program_tests.gd`
- Modify: `godot/route_contract.gd`
- Modify: `godot/route_contract_tests.gd`
- Modify: `godot/geometry_metrics.gd`
- Modify: `godot/geometry_audit_tests.gd`
- Modify: `godot/ride_planner.gd`
- Modify: `godot/generator.gd`
- Modify: `godot/generator_material_tests.gd`
- Delete: `godot/ride_return_solve.gd`
- Delete: `godot/ride_return_solve.gd.uid`

**Interfaces:**

- `RideProgram.compile()` integrates the prefix through camelback once, calls `RideReturnLayout.build()` once, iterates assignments in planner order through `RideReturnElements.build()`, then calls `RideTerminal.build()` once.
- Produces private `RideProgram._append_element(spans: Array, metadata: Array, propulsion: PackedInt32Array, role_id: String, authored: Array) -> void`, which appends each accepted span through `_add_record` and records direct contiguous role ownership.
- Compiled output publishes immutable `return_layout`, per-role `element_results`, `terminal_report`, and direct role span ownership.
- The production planner consumes `story.return` exactly once using deterministic Fisher–Yates over `RETURN_ROLES`.
- No source preload or string reference to `RideReturnSolve`, `RETURN_SCALAR_IDS`, `_solve_return`, `_return_observation`, or capture coefficients remains.

- [ ] **Step 1: Add the failing orchestration and deletion assertions**

Replace old global-solve tests with:

```gdscript
_test_compile_calls_one_layout_and_builds_planner_order()
_test_record_release_and_camelback_are_fixed_before_layout()
_test_local_failure_preserves_layout_and_does_not_retry()
_test_terminal_capture_has_no_steering_controls()
_test_compiled_return_publishes_positive_margins()
_test_source_has_no_global_return_solver_tokens()
```

The source assertion scans production GDScript and rejects:

```gdscript
for token in ["RideReturnSolve", "RETURN_SCALAR_IDS", "_solve_return(",
		"_return_observation(", "capture_seed", "capture.coefficients"]:
	_expect(not source.contains(token), "deleted global return token is absent: %s" % token)
```

- [ ] **Step 2: Commit and push the orchestration RED**

```powershell
git add godot/ride_program_tests.gd godot/route_contract_tests.gd godot/geometry_audit_tests.gd
git commit -m "test: require geometric return orchestration"
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
gh run view $run --log-failed
```

Expected: focused tests fail on the still-present global solver/fixed emitter and on absent compiled layout evidence. Import must succeed.

- [ ] **Step 3: Rewrite the compile seam**

The orchestration must have this shape, with existing metadata/error helpers used directly:

```gdscript
var prefix := Motion.integrate(initial_state, spans, settings)
var layout_result := RideReturnLayout.build(_last_state(prefix), resolved_plan,
	RidePlanner.return_order(story.sequence))
if not layout_result.ok: return _failure(layout_result.errors[0], "return-layout", layout_result)

for assignment: Dictionary in layout_result.assignments:
	var element := RideReturnElements.build(_last_state(prefix), assignment, settings)
	if not element.ok: return _failure(element.errors[0], "return-element", element)
	_append_element(spans, metadata, propulsion, assignment.role_id, element.spans)
	prefix = Motion.integrate(initial_state, spans, settings)

var terminal := RideTerminal.build(_last_state(prefix), _layout_from_plan(resolved_plan), settings)
if not terminal.ok: return _failure(terminal.errors[0], "terminal", terminal)
```

Avoid a thin orchestration wrapper. If repeated full-prefix integration can be replaced by appending already integrated arrays without changing public bytes or validation, use the smaller measured implementation.

- [ ] **Step 4: Consume the return-order stream once**

In `_draw_sequence`, copy `RETURN_ROLES`, perform Fisher–Yates with `rngs[STREAM_STORY_RETURN]`, and append the result. No compile or solve code may receive an RNG.

Add certification assertions that the canonical 15 seeds are deterministic and that explicit return-order overrides do not alter other named streams.

- [ ] **Step 5: Publish and validate direct evidence**

`RouteContract` rejects:

- layout/compiled order disagreement;
- target/integrated role-length disagreement;
- negative/non-finite layout, terrain, energy, or local-element margins;
- direct `x^(0..4)` seam failure;
- return corridor or force-envelope failure;
- non-neutral capture entry; and
- final station mismatch.

Role ownership is recorded while spans are appended. Delete fixed positional `_add_raceway()` family emission and any reconstruction logic made redundant by direct ownership.

- [ ] **Step 6: Delete the old owner and stale tests/comments**

Delete `ride_return_solve.gd` and its UID. Remove old seeds, 12-control arrays/bounds/scales, prefix candidate cache, global residuals, capture Jacobian, obsolete budget comments, and camelback-frame diagnostic output. Do not retain compatibility aliases for private symbols.

- [ ] **Step 7: Commit the atomic GREEN candidate and push CI**

```powershell
git add .github/focused-tests.txt godot/motion.gd godot/motion_tests.gd `
  godot/ride_planner.gd godot/ride_planner_tests.gd godot/generator.gd `
  godot/generator_material_tests.gd godot/ride_return_layout.gd `
  godot/ride_return_layout_tests.gd godot/ride_return_elements.gd `
  godot/ride_return_elements_tests.gd godot/ride_terminal.gd `
  godot/ride_terminal_tests.gd godot/ride_program.gd godot/ride_program_tests.gd `
  godot/route_contract.gd godot/route_contract_tests.gd godot/geometry_metrics.gd `
  godot/geometry_audit_tests.gd godot/camelback_geometry_tests.gd `
  docs/ISSUES.md CLAUDE.md README.md
git add -u -- godot/ride_return_solve.gd godot/ride_return_solve.gd.uid
git commit -m "feat: replace global return solve with geometric FVD layout"
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
```

Expected GREEN requirements:

- import within 30,000 ms;
- every focused suite, including camelback/layout/elements/terminal, passes;
- six-seed fast regression remains inside its existing allowance;
- fifteen-seed smoke fleet passes, including seed 4096 without special handling;
- viewer and visual-audit steps run rather than skip.

If this commit fails macro layout or local element feasibility, fix the owning geometric contract. Do not resurrect a global residual, add a retry, or change a band/cap.

- [ ] **Step 8: Run code-diff and solver-math reviews**

Opus reviews FVD equations, spatial/temporal equivalence, macro controls, local force bands, energy, and terminal braking. Sonnet reviews every changed line against the four global `CLAUDE.md` rules and reports old/new line counts for the affected return/terminal path. Fable rejects the change if complexity merely moved across files.

Commit accepted corrections, push, and require a fresh complete CI run.

---

### Task 8: Force Evidence, Visual Acceptance, and Merge

**Files:**

- Modify: `godot/fidelity_tests.gd`
- Modify: `godot/fidelity.gd`
- Modify: `godot/fidelity_artifact_tests.gd`
- Modify: `godot/fidelity_artifacts.gd`
- Modify: `docs/ISSUES.md`
- Modify: `CLAUDE.md` — including its focused-suite count and enumeration, which still say sixteen
  while the manifest has grown by `ride_return_layout_tests.gd`, `geometry_audit_tests.gd`,
  `ride_terminal_tests.gd`, and (Task 6) `camelback_geometry_tests.gd`. The count is only correct
  once every task has landed, so it is a cutover-time edit, not a per-task one.
- Modify: `README.md` only if its solver description is stale.

**Interfaces:**

- Adds evidence-only load fields under each route measurement:
  - `normal_sample_mean_g`
  - `normal_time_weighted_mean_g`
  - `resultant_sample_mean_g`
  - `resultant_time_weighted_mean_g`
- Defines resultant proper G per sample as `sqrt(normal_g^2 + lateral_g^2 + longitudinal_g^2)`.
- Uses trapezoidal time weighting over native route timestamps.
- Adds no acceptance gate for any mean.

- [ ] **Step 1: Add RED force-summary tests**

Use an irregular-time synthetic route so sample and time means differ:

```gdscript
var times := PackedFloat32Array([0.0, 1.0, 3.0])
var normal := PackedFloat32Array([1.0, 3.0, 1.0])
var lateral := PackedFloat32Array([0.0, 4.0, 0.0])
var longitudinal := PackedFloat32Array([0.0, 0.0, 0.0])
var summary := Fidelity.force_summary(times, normal, lateral, longitudinal)
_expect_close(summary.normal_sample_mean_g, 5.0 / 3.0,
	"sample-weighted normal mean uses native samples")
_expect_close(summary.normal_time_weighted_mean_g, 2.0,
	"time-weighted normal mean uses trapezoidal seconds")
_expect_close(summary.resultant_sample_mean_g, 7.0 / 3.0,
	"resultant mean uses vector magnitude")
```

Artifact tests require the four fields in `audit.json` and verify the report labels them as evidence, not gates.

- [ ] **Step 2: Commit/push RED, then implement and push GREEN**

```powershell
git add godot/fidelity_tests.gd godot/fidelity_artifact_tests.gd
git commit -m "test: specify weighted force evidence"
$sha = git rev-parse HEAD
git push origin HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
gh run view $run --log-failed
```

Expected RED: missing `Fidelity.force_summary` or missing artifact fields.

Implement one linear pass with finite/type/length validation, then:

```powershell
git add godot/fidelity.gd godot/fidelity_tests.gd godot/fidelity_artifacts.gd godot/fidelity_artifact_tests.gd
git commit -m "feat: publish weighted force evidence"
git push origin HEAD
$sha = git rev-parse HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
```

- [ ] **Step 3: Download and inspect the clean artifact**

```powershell
$artifact = Join-Path $env:TEMP "pr14-visual-audit-$run"
New-Item -ItemType Directory -Force -Path $artifact | Out-Null
gh run download $run -n ci-diagnostics -D $artifact
Get-ChildItem -LiteralPath $artifact -Recurse -File | Sort-Object FullName
```

Inspect seeds 42, 11, and 20260809:

- top, elevation, and channel summaries;
- opener, Immelmann, dive, camelback, return, and station element/POV images;
- camelback planarity, its 140–170 m `apex_agl_m` band, and its rise/fall symmetry;
- turn curvature/bank agreement and absence of closure counter-bank;
- transition continuity and lack of neutral pauses/micro-spans;
- clearance, terrain proximity, and high-speed optic-flow cues.

Opus performs the independent visual/physics review; Sonnet checks artifact completeness and compares the four force means with existing envelope and `docs/TELEMETRY.md`. Report comparison only; do not add an average-G gate.

- [ ] **Step 4: Final cleanup and four-rule audit**

Run static checks without Godot:

```powershell
rg -n "RideReturnSolve|RETURN_SCALAR_IDS|_solve_return\(|_return_observation\(|capture_seed|camelback frame|temporary diagnostic" godot docs README.md CLAUDE.md
git diff --check origin/main...HEAD
git status --short
```

Expected: no obsolete solver/temporary tokens; no whitespace errors; only the preserved `HANDOFF_NEXT_AGENT.md` remains untracked.

Fable records explicit PASS/FAIL for:

1. Think Before Coding — assumptions and math trace to the spec.
2. Simplicity First — affected path is materially smaller/clearer with no wrapper abstractions.
3. Surgical Changes — every changed line serves the return, spatial kernel, terminal, evidence, or required docs.
4. Goal-Driven Execution — RED/GREEN CI, fleet, margins, visuals, and force evidence are present.

- [ ] **Step 5: Commit final documentation and push the final CI candidate**

```powershell
git add docs/ISSUES.md CLAUDE.md README.md
git commit -m "docs: record geometric return verification"
git push origin HEAD
$sha = git rev-parse HEAD
$run = gh run list --workflow CI --commit $sha --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $run --exit-status
gh pr checks 14
```

Do not merge unless the latest run is complete and green, visual and force reviews pass, no temporary diagnostics remain, and all four review grades pass.

- [ ] **Step 6: Merge PR #14 and safely fast-forward local main**

```powershell
gh pr merge 14 --merge

$main = 'D:\Coding\ClaudeCode\Vibe-Coaster'
git -C $main status --short -- README.md Run-VibeCoaster.cmd Telemetry
git -C $main stash push -u -m "pre-pr14-main-fast-forward" -- README.md Run-VibeCoaster.cmd Telemetry
git -C $main fetch origin
git -C $main merge --ff-only origin/main
git -C $main stash apply 'stash@{0}'
git -C $main status --short -- README.md Run-VibeCoaster.cmd Telemetry
```

If stash application conflicts, stop, report the exact paths, and retain the stash. Drop it only after the restored user changes are verified byte-for-byte or the user explicitly authorizes removal.

---

## Final Acceptance Checklist

- [ ] Every RED/GREEN claim is backed by a named CI run, not a local Godot run.
- [ ] Spatial FVD math and direct C4 evidence received Opus PASS.
- [ ] All 24 return orders pass pure layout contracts; production order uses only `story.return`.
- [ ] No local failure can alter layout, order, warm start, tolerance, topology, or budget.
- [ ] `ride_return_solve.gd` and its private compatibility surface are deleted.
- [ ] Record release and camelback are independently accepted before return layout.
- [ ] Capture is neutral and the brake solve is one-dimensional.
- [ ] Seed 4096 passes as an ordinary fleet member.
- [ ] Latest CI passes import, focused manifest, smoke fleet, viewer, and visual artifact generation.
- [ ] Every scaled residual is at most 0.02 and every true-band margin is positive.
- [ ] Seeds 42, 11, and 20260809 pass independent visual review.
- [ ] Sample/time-weighted normal/resultant G is reported without a new mean-G gate.
- [ ] Solver-math, code-diff, visual, and four-rule reviews all pass.
- [ ] PR #14 is merged only after all prior checks.
- [ ] Main fast-forward preserves README, launcher, and Telemetry user changes; stash is retained on conflict.
