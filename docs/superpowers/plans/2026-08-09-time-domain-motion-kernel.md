# Time-Domain Motion Kernel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an independently tested, deterministic 100 Hz FVD kernel with immutable C2 profiles, one C2 resistance law, foundation-owned authoritative trajectories, analytic boundary jets, strict station-only low-speed motion, and a bounded five-variable station-capture prototype without changing generated rides.

**Architecture:** This Gate-3 plan depends on the Route/Configuration Foundation plan: it consumes `MotionTrajectory.create(channels, dense_sampler)` and contributes one packed `MotionDenseSampler` implementing the foundation's nested `DenseSampler` contract. `MotionKernel` integrates immutable `MotionSpan` controls into pre-sized typed buffers, then creates one sampler and one immutable foundation `MotionTrajectory`; `BoundedSolver` is a narrow normalized-coordinate root solver, and `StationCapture` alone owns manifold semantics and evaluation budgets. `RideGenerator` continues producing the characterized legacy `RideRoute` until the later default-recipe and cutover plans.

**Tech Stack:** Godot 4.7.1, typed GDScript, `RefCounted`, foundation `MotionTrajectory`/`RideRoute`, packed arrays, headless SceneTree tests, GitHub Actions Ubuntu.

## Global Constraints

- Execute `2026-08-09-route-config-foundation.md` first. Do not recreate or add mutable append methods to `godot/motion_trajectory.gd`.
- Before Task 1, require the foundation trajectory tests to prove that empty/missing dense coverage is rejected (or natively sampled by an explicit segment implementation) and that unequal packed-channel counts return structured validation errors before any per-sample indexing. If either upstream test is absent or red, stop and repair the foundation plan/implementation in its own scope; do not patch around it here.
- Consume the foundation's exact singular SI fields: `time_s`, `distance_m`, `position_m`, `tangent`, `rider_up`, `speed_mps`, `normal_g`, `lateral_g`, `drive_g`, total proper `longitudinal_g`, and `roll_rate_rad_s`.
- Time is the sole integration domain. `MotionKernel.production_config().dt_s == 0.01` exactly.
- Preserve the approved law: `a_perp = g - dot(g,T)T + g0(normal_g U + lateral_g R)`, `dr/dt=vT`, `ds/dt=v`, `dv/dt=dot(g,T)+g0 drive_g-drag`, `dT/dt=a_perp/v`, and emitted `longitudinal_g=drive_g-drag/g0`.
- `MIN_MOVING_SPEED == 2.0 m/s`. Below it only straight station launch/creep/brake mode is legal; transverse inertial acceleration cancels, roll rate is zero, and tangent/frame remain fixed. Station/moving handoffs occur at native step/span boundaries at the threshold. Consecutive station spans and a final positive-speed station transfer are legal; zero speed is legal only at the initial instant, never over an interval. Validate every RK intermediate before division and every accepted state, including the program endpoint.
- Profiles and resistance are analytically C2. Moving boundary jets use analytic chain rule; finite differences only corroborate convergence.
- RK full/half differences and coarse/fine capture differences are numerical estimates, never proofs or conservative bounds. Results may be `screened` or `validated_100hz`, never `certified`.
- Hot integration uses pre-sized packed buffers and reusable typed scratch records. No `Dictionary`, callable, state, derivative, sampler, or per-step object allocation occurs inside the step loop.
- Every RK intermediate and accepted state is normalized/reorthogonalized before derivative evaluation. GDScript scalar `float`, `PackedFloat64Array` time/distance/speed/control-coefficient buffers, and solver coordinates are Float64; only `Vector3` geometry uses standard-build engine precision. Tests use scalar endpoint tolerances appropriate to Float64 and vector-geometry tolerances appropriate to engine precision; never claim an all-Float64 geometry state.
- Station solving uses exactly five nonzero-width bounded variables and at most 40 coarse trajectory evaluations including its fine-step estimate evaluation.
- Keep `elements.gd`, `generator.gd`, `verify.gd`, `main.gd`, and current generated behavior unchanged. Every task ends with import, focused tests, existing smoke, and a green commit.

Set one controlled Godot command per PowerShell session. In a linked worktree, the fallback resolves the portable binary from the shared repository rather than `PATH`; application state remains isolated beneath the active worktree's ignored `out/`:

```powershell
$taskRoot = (Resolve-Path '.').Path
$sharedRepoRoot = Split-Path ((git rev-parse --path-format=absolute --git-common-dir).Trim()) -Parent
$portableGodot = if ($env:GODOT_BIN) { (Resolve-Path -LiteralPath $env:GODOT_BIN).Path } else { (Resolve-Path -LiteralPath (Join-Path $sharedRepoRoot 'out\tools\godot-4.7.1\Godot_v4.7.1-stable_win64_console.exe')).Path }
$godotAppData = Join-Path $taskRoot 'out\godot-appdata'
$godotLocalAppData = Join-Path $taskRoot 'out\godot-localappdata'
$null = New-Item -ItemType Directory -Force -Path $godotAppData, $godotLocalAppData
$env:APPDATA = $godotAppData
$env:LOCALAPPDATA = $godotLocalAppData
```

## Files and Dependency Contract

**Create:**

- `godot/motion_span.gd` — immutable-by-interface quintic physical-control span.
- `godot/motion_resistance.gd` — sole C2 rolling/aerodynamic loss law.
- `godot/motion_dense_sampler.gd` — one packed convergence-tested dense approximation implementing `MotionTrajectory.DenseSampler`.
- `godot/motion_kernel.gd` — reusable typed scratch state, RK4/step-doubling integration, trajectory construction, low-speed rules, analytic boundary jets.
- `godot/bounded_solver.gd` — deterministic normalized box-constrained trust-region root solver.
- `godot/station_capture.gd` — station-local manifold residuals, solve budget, screening, full-resolution validation.
- `godot/motion_kernel_tests.gd`, `godot/bounded_solver_tests.gd`, `godot/station_capture_tests.gd`.

**Modify:** `godot/smoke.gd` only to register the three focused suites.

**Consume unchanged:**

```gdscript
MotionTrajectory.create(channels: Dictionary, dense_sampler: MotionTrajectory.DenseSampler = null) -> MotionTrajectory
MotionTrajectory.sample_time(query_time_s: float) -> MotionSample
MotionTrajectory.sample_time_into(query_time_s: float, out: MotionSample) -> void
MotionTrajectory.sample_distance(query_distance_m: float) -> MotionSample
MotionTrajectory.sample_distance_into(query_distance_m: float, out: MotionSample) -> void
```

**Produce for downstream default-recipe/cutover plans:**

```gdscript
MotionSpan.control(normal_g: float, lateral_g: float, drive_g: float, roll_rate_rad_s: float) -> MotionSpan.Control
MotionSpan.quintic(gesture_id: String, duration_s: float, value0: MotionSpan.Control, d1_0: MotionSpan.Control, d2_0: MotionSpan.Control, value1: MotionSpan.Control, d1_1: MotionSpan.Control, d2_1: MotionSpan.Control, station_mode: bool = false, metadata: Dictionary = {}) -> MotionSpan
MotionSpan.evaluate_into(local_time_s: float, derivative_order: int, out: MotionSpan.Control) -> void
MotionSpan.value_at(local_time_s: float) -> MotionSpan.Control # convenience allocation only
MotionSpan.derivative_at(local_time_s: float, order: int) -> MotionSpan.Control # convenience allocation only
MotionSpan.validate_sequence(spans: Array, tolerance: float = 2e-5) -> PackedStringArray
MotionResistance.legacy_baseline() -> MotionResistance.Config
MotionResistance.acceleration_mps2(speed_mps: float, config: MotionResistance.Config) -> float
MotionResistance.speed_derivatives(speed_mps: float, config: MotionResistance.Config) -> Vector3 # acceleration, d/dv, d2/dv2
MotionKernel.production_config() -> MotionKernel.Config
MotionKernel.initial_state(position_m: Vector3, tangent: Vector3, rider_up: Vector3, speed_mps: float) -> MotionKernel.State
MotionKernel.integrate(spans: Array, initial: MotionKernel.State, resistance: MotionResistance.Config, config: MotionKernel.Config) -> Dictionary
MotionKernel.boundary_jet(state: MotionKernel.State, span: MotionSpan, local_time_s: float, resistance: MotionResistance.Config, config: MotionKernel.Config) -> Dictionary
BoundedSolver.solve(residual: Callable, lower: PackedFloat64Array, upper: PackedFloat64Array, initial: PackedFloat64Array, max_evaluations: int) -> Dictionary
StationCapture.solve(entry: MotionKernel.State, span_factory: Callable, lower: PackedFloat64Array, upper: PackedFloat64Array, initial: PackedFloat64Array, manifold: Dictionary, resistance: MotionResistance.Config, kernel_config: MotionKernel.Config, context: Dictionary, max_trajectory_evaluations: int = 40) -> Dictionary
StationCapture.validate_at_100hz(solution: Dictionary, entry: MotionKernel.State, resistance: MotionResistance.Config, context: Dictionary) -> Dictionary
StationCapture.validate_accepted_trajectory(trajectory: MotionTrajectory, spans: Array, capture_record: Dictionary, resistance: MotionResistance.Config, kernel_config: MotionKernel.Config) -> Dictionary
```

`MotionKernel.integrate` returns `{ok, trajectory: MotionTrajectory, end_state, work}` or `{ok=false, error}`. It calls `MotionTrajectory.create` once and never exposes construction buffers.

---

### Task 1: Immutable C2 Motion Spans and Sole C2 Resistance

**Files:** Create `godot/motion_span.gd`, `godot/motion_resistance.gd`, `godot/motion_kernel_tests.gd`.

**Interfaces:** Produces `MotionSpan` and `MotionResistance` signatures above. `MotionSpan.Control` is a reusable typed scratch record with named scalar Float64 fields `normal_g`, `lateral_g`, `drive_g`, and `roll_rate_rad_s`; total proper `longitudinal_g` is derived by the kernel and is not an authored profile.

- [ ] **Step 1: Write failing endpoint, mutation-isolation, and resistance tests.**

```gdscript
var span := MotionSpan.quintic("test", 2.0, v0, d10, d20, v1, d11, d21, false, {"slot":"act1"})
var actual := MotionSpan.control(0.0, 0.0, 0.0, 0.0)
span.evaluate_into(0.0, 0, actual)
_expect_control(errors, actual, v0, 1e-12, "start value")
span.evaluate_into(2.0, 2, actual)
_expect_control(errors, actual, d21, 1e-10, "end d2")
var exposed := span.metadata()
exposed.slot = "mutated"
_expect(errors, span.metadata().slot == "act1", "metadata is defensively copied")
var loss := MotionResistance.legacy_baseline()
_expect_close(errors, MotionResistance.acceleration_mps2(0.0, loss), 0.0, 1e-12, "rest loss")
var left := MotionResistance.speed_derivatives(loss.transition_speed_mps - 1e-7, loss)
var right := MotionResistance.speed_derivatives(loss.transition_speed_mps + 1e-7, loss)
_expect_v3(errors, left, right, 1e-4, "C2 resistance transition")
```

- [ ] **Step 2: Run `& $portableGodot --headless --path '.\godot' --script 'res://motion_kernel_tests.gd'`; expect missing scripts.**

- [ ] **Step 3: Implement immutable span getters and closed-form quintic coefficients.** Copy all input controls at construction. Store only private `_gesture_id`, `_duration_s`, `_station_mode`, `_metadata`, and four six-entry `PackedFloat64Array` coefficient channels (`_normal_g_coefficients`, `_lateral_g_coefficients`, `_drive_g_coefficients`, `_roll_rate_coefficients`); expose getter methods/properties with no setters and return `_metadata.duplicate(true)`. A private scalar helper computes the six coefficients below independently for each channel; never pack authored controls into `Vector4`.

```gdscript
var a0: float = value0
var a1: float = d1_0 * duration_s
var a2: float = 0.5 * d2_0 * duration_s * duration_s
var c0: float = value1 - a0 - a1 - a2
var c1: float = d1_1 * duration_s - a1 - 2.0 * a2
var c2: float = d2_1 * duration_s * duration_s - 2.0 * a2
return PackedFloat64Array([a0, a1, a2, 10.0*c0-4.0*c1+0.5*c2, -15.0*c0+7.0*c1-c2, 6.0*c0-3.0*c1+0.5*c2])
```

- [ ] **Step 4: Implement allocation-free `evaluate_into`, allocating convenience getters, and exact C2 sequence validation.** Evaluate all four scalar channels into caller-owned `MotionSpan.Control`; reject invalid duration/nonfinite jets during construction; `validate_sequence` names gesture IDs, scalar channel, and derivative order.

- [ ] **Step 5: Implement the resistance formula and analytic speed derivatives.**

```gdscript
static func acceleration_mps2(v: float, c: Config) -> float:
	var u := clampf(v / c.transition_speed_mps, 0.0, 1.0)
	var smooth5 := u*u*u*(10.0 + u*(-15.0 + 6.0*u))
	return c.aero_per_m*v*v + c.rolling_mps2*smooth5
```

Use `aero_per_m=0.000064`, `rolling_mps2=0.0015*9.80665`, and `transition_speed_mps=0.5`; label them legacy-derived design assumptions. Test value, first derivative, and second derivative at both transition endpoints plus monotonic unpowered loss.

- [ ] **Step 6: Run focused, import, and smoke commands; commit green.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://motion_kernel_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git add godot/motion_span.gd godot/motion_resistance.gd godot/motion_kernel_tests.gd
git commit -m "feat: add immutable C2 motion controls"
```

---

### Task 2: Typed FVD Dynamics and Strict Low-Speed Mode

**Files:** Create `godot/motion_kernel.gd`; modify `godot/motion_kernel_tests.gd`.

**Interfaces:** Produces `MotionKernel.Config`, `State`, reusable `Derivative`, `production_config`, `initial_state`, and private `_derivative_into`.

- [ ] **Step 1: Add failing station-mode and gravity-once tests.** At level rest, `(1,0,0.5,0)` is legal only in station mode; nonzero roll or normal `0.9` fails. At a supported `-20°` pitched straight with zero resistance and `drive_g == 0`, assert `dv/dt == gravity.dot(tangent)`, emitted `longitudinal_g == 0`, and `dT/dt == 0`. With nonzero resistance, assert emitted `longitudinal_g == drive_g - drag/g0`.

- [ ] **Step 2: Run the focused script; expect `motion_kernel.gd` missing.**

- [ ] **Step 3: Implement reusable typed records.** `State` owns position, tangent, rider-up, speed, time, distance. `Derivative` owns their time derivatives. Add `copy_into`, `advance_into`, and `combine_into`; each writes an existing object. `advance_into` and `combine_into` normalize tangent and project/normalize rider-up before any derivative call.

```gdscript
static func _orthonormalize(state: State) -> void:
	state.tangent = state.tangent.normalized()
	state.rider_up = (state.rider_up - state.tangent * state.rider_up.dot(state.tangent)).normalized()
```

- [ ] **Step 4: Implement the approved equations without dictionaries or hidden energy.**

```gdscript
static func _derivative_into(out: Derivative, state: State, control: MotionSpan.Control, station_mode: bool, loss: MotionResistance.Config, config: Config, work: Work) -> bool:
	var right := state.tangent.cross(state.rider_up).normalized()
	var across := config.gravity - state.tangent * config.gravity.dot(state.tangent) + config.g0*(control.normal_g*state.rider_up + control.lateral_g*right)
	if station_mode:
		if state.speed_mps > MIN_MOVING_SPEED + config.speed_tolerance_mps or absf(control.roll_rate_rad_s) > config.control_tolerance or across.length() > config.station_transverse_tolerance_mps2:
			return false
	elif state.speed_mps < MIN_MOVING_SPEED - config.speed_tolerance_mps:
		return false
	out.position_dt = state.speed_mps * state.tangent
	out.distance_dt = state.speed_mps
	out.speed_dt = config.gravity.dot(state.tangent) + config.g0*control.drive_g - MotionResistance.acceleration_mps2(state.speed_mps, loss)
	out.tangent_dt = Vector3.ZERO if station_mode else across/state.speed_mps
	out.up_dt = Vector3.ZERO if station_mode else -state.tangent*out.tangent_dt.dot(state.rider_up) + control.roll_rate_rad_s*right
	work.derivative_evaluations += 1
	return true
```

- [ ] **Step 5: Validate every stage and each station-law handoff.** Use `station_transverse_tolerance_mps2=1e-5`, `control_tolerance=2e-6`, and scalar `speed_tolerance_mps=1e-6`. `_rk4_into` stops on a false derivative result and records the failing stage in reusable `Work`; construct the structured error only after leaving the hot loop. Require every station span duration to be an integer multiple of `dt_s` and every station RK stage to remain at or below the threshold with zero transverse acceleration/roll. A station-to-moving or moving-to-station boundary must meet `2.0 m/s` within speed tolerance and have a structural zero curvature jet; station-to-station boundaries retain continuous speed/control jets. A final station span may end below the threshold only at the plan's declared positive `station_terminal_speed_mps`. Permit zero speed only for the initial sample and reject any accepted interval whose distance increment is not positive. Reject every nonstation stage below the threshold before `across / speed`, including projected midpoint stages and the final endpoint.

- [ ] **Step 6: Run focused/import/smoke and commit green.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://motion_kernel_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git add godot/motion_kernel.gd godot/motion_kernel_tests.gd
git commit -m "feat: define time-domain FVD dynamics"
```

---

### Task 3: Packed Dense Approximation and 100 Hz Integration

**Files:** Create `godot/motion_dense_sampler.gd`; modify `godot/motion_kernel.gd`, `godot/motion_kernel_tests.gd`. Do not modify `motion_trajectory.gd`.

**Interfaces:** `MotionDenseSampler extends MotionTrajectory.DenseSampler`; `MotionKernel.integrate` creates the foundation trajectory using singular channels.

- [ ] **Step 1: Add failing analytic tests.** Cover supported straight, constant-acceleration station launch, zero-gravity constant-curvature inversion, physically banked horizontal turn, and pitched gravity/no-double-counting. Add `dt=0.02/0.01/0.005` convergence checks; describe them as convergence evidence.

- [ ] **Step 2: Add failing dense-contract tests.** Reuse one `MotionSample` for all hot-path calls. At every native time, dense and native position/frame/speed/G/drive channels match. At mid-step, assert returned authored controls equal `owning_span.value_at(local_time)`, total `longitudinal_g == drive_g - drag(sample.speed_mps)/g0`, and no endpoint control interpolation occurs. Numerically differentiate dense position and require convergence toward dense `speed_mps*tangent` as `dt` halves; do not require an identity that independent cubic interpolation cannot guarantee.

- [ ] **Step 3: Implement one `MotionDenseSampler` from packed Hermite approximation data.** Its factory copies the completed primitive channel arrays, immutable spans, packed span-start times, resistance scalars, `g0`, and three packed numerical-estimate arrays—never `MotionKernel.State`. `sample_time_into` binary-searches the native interval, evaluates position, tangent, rider-up, speed, and distance from the same interval parameter, and orthonormalizes the frame. It evaluates the owning immutable span for exact authored controls and writes the caller-owned sample:

```gdscript
_span.evaluate_into(_span_local_start_s + query_time_s - start_time_s, 0, _control_scratch)
out.time_s = query_time_s
out.distance_m = state.distance_m
out.position_m = state.position_m
out.tangent = state.tangent
out.rider_up = state.rider_up
out.speed_mps = state.speed_mps
out.normal_g = _control_scratch.normal_g
out.lateral_g = _control_scratch.lateral_g
out.drive_g = _control_scratch.drive_g
out.longitudinal_g = _control_scratch.drive_g - MotionResistance.acceleration_mps2(state.speed_mps, _loss) / _g0
out.roll_rate_rad_s = _control_scratch.roll_rate_rad_s
out.span_index = span_index
```

`sample_distance_into` binary-searches the distance interval, bisects the same monotone `distance_m(t)`, and delegates to the common interval evaluator. `interval_count()` is `native_count - 1`; `interval_error_estimate(i)` returns the three estimates plus `{kind="rk4_full_vs_two_half", is_formal_bound=false}`. The sampler has no public mutator and creates no object when the caller supplies a reusable `MotionSample`; the foundation convenience method honestly allocates one result.

- [ ] **Step 4: Preallocate the entire integration workspace.** Sum `ceil(duration/dt)` before entering the loop; resize every required native channel and interval-estimate packed buffer; allocate one accepted state, full/half states, RK stage states, derivatives, one reusable `MotionSpan.Control`, and `Work`. No allocation occurs inside the loop. Construct the single `MotionDenseSampler` only after the packed buffers are complete; it owns one reusable control scratch for its non-concurrent sampling contract.

- [ ] **Step 5: Implement projected-stage RK4 plus full/two-half estimates.** `_rk4_into` writes supplied scratch objects; all stage states are reorthogonalized and speed/station-validated before `_derivative_into`. Propagate a false derivative result without evaluating later stages or dividing by speed. Accept the two-half result, retain full-versus-half position/frame/speed differences as empirical estimates, and count every successful `_derivative_into` call at the call site through `Work`—including dense endpoint derivatives.

- [ ] **Step 6: Fill singular SI channels and create one immutable trajectory.** Keep scalar time, distance, speed, authored controls, resistance, and solver arithmetic in GDScript Float64 and use the standard engine vector representation only for position/frame geometry; apply the documented precision-aware tolerances. Call exactly:

```gdscript
var trajectory := MotionTrajectory.create({"time_s":time_s, "distance_m":distance_m, "position_m":position_m,
	"position_dt_mps":position_dt_mps, "tangent":tangent, "tangent_dt_per_s":tangent_dt_per_s,
	"rider_up":rider_up, "rider_up_dt_per_s":rider_up_dt_per_s, "speed_mps":speed_mps,
	"speed_dt_mps2":speed_dt_mps2, "normal_g":normal_g, "lateral_g":lateral_g,
	"longitudinal_g":longitudinal_g, "drive_g":drive_g, "roll_rate_rad_s":roll_rate_rad_s,
	"span_index":span_index}, dense_sampler)
```

Return `work.native_steps`, actual `derivative_evaluations`, and `full_resolution_integrations = 1` only for a successful `dt_s==0.01` call.

- [ ] **Step 7: Run focused/import/smoke and commit green.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://motion_kernel_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git add godot/motion_dense_sampler.gd godot/motion_kernel.gd godot/motion_kernel_tests.gd
git commit -m "feat: integrate authoritative dense trajectories"
```

---

### Task 4: Analytic Arc-Length Boundary Jets

**Files:** Modify `godot/motion_kernel.gd`, `godot/motion_kernel_tests.gd`.

**Interfaces:** Completes `MotionKernel.boundary_jet` without sampling or finite differences.

- [ ] **Step 1: Add failing matched-seam tests.** Two quintics sharing value/d1/d2 must produce equal curvature, `curvature_ds`, `curvature_d2s`, proper-G/rate, roll rate/acceleration, speed, and tangential acceleration from the same state. A level `(1,0,*,0)` threshold shoulder with zero transverse jets must yield structural zero curvature jet.

- [ ] **Step 2: Run focused tests; expect missing boundary fields.**

- [ ] **Step 3: Implement analytic frame/acceleration derivatives.** Use `Tdot=A/v`, `Udot=-T(Tdot·U)+omega R`, `Rdot=-T(Tdot·R)-omega U`, and exact control d1/d2 from `MotionSpan`; use analytic resistance speed derivatives for `vdot/vddot` and for total `longitudinal_g = drive_g - drag/g0` plus its boundary rates.

- [ ] **Step 4: Apply exact time-to-arc chain rules.**

```gdscript
var curvature := acceleration/(v*v)
var curvature_dt := acceleration_dt/(v*v) - 2.0*acceleration*vdot/(v*v*v)
var curvature_d2t := acceleration_d2t/(v*v) - 4.0*acceleration_dt*vdot/(v*v*v) - 2.0*acceleration*vddot/(v*v*v) + 6.0*acceleration*vdot*vdot/pow(v,4)
var curvature_ds := curvature_dt/v
var curvature_d2s := curvature_d2t/(v*v) - curvature_dt*vdot/(v*v*v)
```

Reject requests below `MIN_MOVING_SPEED`. Return explicit `hypotheses_met`; do not claim C4 when control sequence/resistance/frame hypotheses are absent.

- [ ] **Step 5: Add symmetric sampled convergence toward the analytic jet.** Halve `dt` twice and require decreasing error; test wording says “boundary-jet convergence,” not “proof.”

- [ ] **Step 6: Run focused/import/smoke and commit green.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://motion_kernel_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git add godot/motion_kernel.gd godot/motion_kernel_tests.gd
git commit -m "feat: derive analytic motion boundary jets"
```

---

### Task 5: Deterministic Normalized Box Solver

**Files:** Create `godot/bounded_solver.gd`, `godot/bounded_solver_tests.gd`.

**Interfaces:** Produces `BoundedSolver.solve` exactly as declared; no geometry, station, RNG, or general optimizer features.

- [ ] **Step 1: Write failing five-dimensional linear-root, impossible-root, repeat-determinism, zero-width, and 40-evaluation tests.**

- [ ] **Step 2: Run `& $portableGodot --headless --path '.\godot' --script 'res://bounded_solver_tests.gd'`; expect missing solver.**

- [ ] **Step 3: Validate finite bounds and strictly positive widths.** Convert physical input to normalized `z=(x-lower)/(upper-lower)` and reject any width `<=0`; every residual call converts `z` back to physical `x`.

- [ ] **Step 4: Implement the trust-region Jacobian and step entirely in normalized coordinates.** Use deterministic one-sided differences inside `[0,1]`, damped `JᵀJ`, stable partial-pivot Gaussian elimination, and lexically fixed dimension order. Apply the solved step directly to `z`; never multiply an already physical step by box width.

```gdscript
var z_candidate := PackedFloat64Array(z)
for i in n:
	z_candidate[i] = clampf(z[i] + normalized_step[i], 0.0, 1.0)
var x_candidate := _to_physical(z_candidate, lower, upper)
var candidate_r: PackedFloat64Array = residual.call(x_candidate)
```

- [ ] **Step 5: Report `{ok,status,x,residuals,evaluations,iterations}` and stop before any call that would exceed budget.** Singular Jacobians shrink radius; they do not fabricate a direction.

- [ ] **Step 6: Run solver/import/smoke and commit green.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://bounded_solver_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git add godot/bounded_solver.gd godot/bounded_solver_tests.gd
git commit -m "feat: add normalized bounded root solver"
```

---

### Task 6: Five-Variable Station Capture and Honest Margins

**Files:** Create `godot/station_capture.gd`, `godot/station_capture_tests.gd`.

**Interfaces:** Produces the exact `StationCapture` signatures above; consumes `BoundedSolver` and coarse `MotionKernel` only.

- [ ] **Step 1: Add failing station-local residual tests.** Manifold contains `origin`, unit `tangent`, unit `rider_up`, along interval, height, brake-speed band, and five tolerances. Residuals are cross-track, height, station-local yaw, pitch, and terminal roll.

- [ ] **Step 2: Implement station-local attitude without resetting the actual frame.**

```gdscript
var target_t := manifold.tangent.normalized()
var target_u := (manifold.rider_up - target_t*manifold.rider_up.dot(target_t)).normalized()
var target_r := target_t.cross(target_u).normalized()
var yaw := atan2(state.tangent.dot(target_r), state.tangent.dot(target_t))
var pitch := asin(clampf(state.tangent.dot(target_u), -1.0, 1.0))
var aligned_up := Quaternion(state.tangent, target_t) * state.rider_up
var roll := atan2(target_t.dot(target_u.cross(aligned_up)), target_u.dot(aligned_up))
```

Because `state.rider_up` is the integrated incoming frame, this roll includes parallel-transport holonomy plus authored roll; no level-up rebuild occurs.

- [ ] **Step 3: Add a real-kernel synthetic return factory with exactly five variables:** lateral amplitude/skew, normal amplitude/skew, and signed roll-pulse area. Its terminal shoulder is C2 and structurally zero-curvature. Generate a known reachable manifold from a fixed parameter vector, then solve from the box midpoint.

- [ ] **Step 4: Implement bounded coarse screening with an exact budget.** Cache physical parameter vectors deterministically. Give `BoundedSolver` at most 39 trajectory calls; reuse its final cached coarse evaluation and spend at most one additional `dt/2` call. Report coarse/fine absolute residual differences as `error_estimates`, `estimate_kind="coarse_vs_half_step_difference"`, and `is_certified=false`.

- [ ] **Step 5: Enforce all capture invariants during screening.** Require `abs(normalized residual)+estimate < 1`, along-track inside interval, speed inside band, and analytic terminal curvature/value/d1/d2 jets structurally zero. Impossible box/manifold combinations return context, variables, bounds, residuals, invariants, and counters without repair or retry.

- [ ] **Step 6: Implement both full-resolution validation paths with one shared invariant evaluator.** `validate_at_100hz` remains a focused diagnostic that performs exactly one `dt=0.01` integration. `validate_accepted_trajectory` performs no integration: it reads the compiler-recorded native capture/brake/station boundaries from an already accepted trajectory and the corresponding spans. Both call one private evaluator that recomputes all five residuals, along interval, brake-entry speed band, accepted endpoint speed, analytic terminal zero-curvature value/d1/d2 jet, moving/station handoff at `MIN_MOVING_SPEED`, and the fixed terminal endpoint. Any miss returns `integrator_correctness_failure`; neither path calls solve again, retries, repairs, or claims certification.

- [ ] **Step 7: Test impossible, insufficient-margin, deterministic-budget, and full-resolution invariant drift cases.** Exercise each shared invariant through both validation paths. Assert `validate_accepted_trajectory` performs zero integration and rejects missing/non-native boundary records. Default-recipe solving uses `solve` only; after the later compiler performs the accepted whole-program 100 Hz integration once, it must call `validate_accepted_trajectory` exactly once.

- [ ] **Step 8: Run capture/solver/import/smoke and commit green.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://bounded_solver_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://station_capture_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git add godot/station_capture.gd godot/station_capture_tests.gd
git commit -m "feat: screen bounded station capture"
```

---

### Task 7: Register Gates and Verify Cross-Plan Contracts

**Files:** Modify `godot/smoke.gd` only.

**Interfaces:** Consumes `MotionKernelTests.run`, `BoundedSolverTests.run`, and `StationCaptureTests.run`; changes no runtime route/generator API.

- [ ] **Step 1: Preload the three suites and append their `run()` errors before legacy generator checks.**

- [ ] **Step 2: Run every focused suite twice.** Require identical status/order/counters; floating arrays use test tolerances rather than cross-platform byte identity.

- [ ] **Step 3: Run required repository gates.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://motion_kernel_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://bounded_solver_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://station_capture_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
```

- [ ] **Step 4: Verify ownership and hot-loop constraints.** `motion_trajectory.gd` has no diff; kernel calls `MotionTrajectory.create` once; no kernel step function returns/creates `Dictionary`; accepted moving states are checked after stepping; counters equal actual derivative calls.

- [ ] **Step 5: Verify downstream signatures.** Confirm default recipes still consume `MotionSpan.control/quintic/evaluate_into/validate_sequence`, `MotionKernel.integrate/production_config`, `MotionResistance.acceleration_mps2`, `BoundedSolver.solve`, the nine required `StationCapture.solve` arguments plus optional budget, `StationCapture.validate_accepted_trajectory`, and immutable `MotionTrajectory.create`. Confirm runtime cutover consumes foundation `position_m` rather than introducing `positions`; do not add an alias here.

- [ ] **Step 6: Inspect scope and commit green.**

```sh
git diff --check
git diff --exit-code HEAD -- godot/elements.gd godot/generator.gd godot/verify.gd godot/main.gd godot/motion_trajectory.gd
git add godot/smoke.gd
git commit -m "test: gate the time-domain motion kernel"
```

## Claim Boundary

This plan analytically establishes quintic endpoint jets, C2 resistance, and boundary-chain-rule identities under explicit hypotheses. It convergence-tests integration, dense output, and capture behavior. Full/half differences remain empirical estimates, so station results are never formally certified. The legacy generator remains unchanged; the default-recipe plan may build candidate `RideRoute` objects behind tests, and only the runtime-cutover plan may make this kernel authoritative and delete legacy execution.
