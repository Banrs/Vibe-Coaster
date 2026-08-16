# Default Ride Recipes Implementation Plan

> **Superseded — design history, not an executable plan.** Superseded by
> `2026-08-12-material-generator-vertical-slice.md` and its execution addendum
> `../specs/2026-08-12-material-generator-vertical-slice-design.md`, which landed on `main` on
> 2026-08-15. Do not execute the steps below: they build the ten-class template scaffold and a
> dormant candidate program alongside the legacy runtime, an order the material slice explicitly
> replaced. Native recipes now live in `godot/ride_program.gd`. Read this for rationale.
> The sixteen-slot / seventeen-recipe vocabulary below (`act1.giant_inversion`,
> `hydraulic_station_launch`, `PRESET_ID == "future-hybrid@1"`, …) was never built and
> corresponds to nothing in the repository; the shipped story is ten beats over twenty
> ordered roles under preset `material-v1`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Compile the complete `future-hybrid@1` story into one evidence-backed, physically integrated candidate `MotionProgram`/`RideRoute` behind focused tests, without cutting the public runtime over from the characterized legacy generator.

**Architecture:** Versioned `RideCatalog` data and planner-resolved physical targets drive one generic `RideCompiler`; recipes contain only proper-force, roll-rate, duration, terrain, propulsion, and terminal intent compiled directly into `MotionSpan`, never position-space geometry. Recipe-local bounded solves and `StationCapture` may use coarse kernel evaluations, then `RideCompiler` integrates the accepted program exactly once at 100 Hz into an immutable `MotionTrajectory`/`RideRoute`. `RideGenerator.build` remains untouched.

**Tech Stack:** Godot 4.7.1, typed GDScript, upstream config/planner, motion kernel/solver, `RideRoute`, and committed evidence catalog.

## Global Constraints

- Scope is Gate 4 only: complete default recipes behind tests; no runtime cutover or legacy deletion.
- Preserve the exact ordered story slots from `RideCatalog.STORY_SLOT_ORDER`: `station.launch`, `opener.side_drop`, `act1.giant_inversion`, `act1.helical_loop`, `act1.cutback`, `act1.airtime`, `act1.wave_turn`, `cliff.lsm_climb`, `clifftop.suspense`, `clifftop.rim_turn`, `cliff.dive`, `tunnel.lsm`, `return.camelback`, `return.release`, `return.raceway`, `station.brakes_return`.
- Preserve recipe IDs already published by `RideCatalog.STORY_SLOTS`: `hydraulic_station_launch`, `twisted_side_drop`, `giant_immelmann`, `helical_leg_loop`, `cutback`, `airtime_hills`, `wave_turn`, `cliff_lsm_climb`, `clifftop_suspense`, `outward_rim_turn`, `cliff_dive`, `tunnel_lsm`, `record_camelback`, `return_airtime_pair`, `return_wave_turn`, `return_raceway`, `station_brakes_return`.
- Exactly three short propulsion zones: station ID 1, cliff-base LSM ID 2, tunnel LSM ID 3. No lift, powered upper climb, mid-course brake, late boost, or hidden correction.
- `MotionResistance` is the sole rolling/aerodynamic loss law. Every unpowered span has zero longitudinal drive; the cliff climb and return must lose energy honestly.
- Time is the sole domain; authored controls are `(normal_g, lateral_g, drive_g, roll_rate_rad_s)` and adjacent spans match value plus two derivatives. Trajectory `longitudinal_g` is the total proper acceleration `drive_g - drag/g0`.
- Recipes may use small declared `BoundedSolver.solve(...)` roots and coarse `MotionKernel.integrate(...)`; each reports variables, bounds, residuals, evaluation count, and failure context. No full-resolution integration occurs inside planning or recipe solving.
- The accepted complete `MotionProgram` receives exactly one `MotionKernel.integrate(...)` call using `MotionKernel.production_config()` (`0.01 s`, 100 Hz). No candidate loop, retry, post-pass, or second full-resolution integration is allowed.
- Ban `GRADE`, `CLOSURE`, `_level`, `_align`, connector sections, short-section dropping, position-space Bézier/spline authoring, point movement, smoothing, frame reset, translation, geometry repair, silent relaxation, seed-specific fixes, and fallback recipes.
- Every gesture owns its shoulders/core/propulsion; grade, height, heading, and pose are outcomes or bounded residuals.
- The return uses the planner-reserved station capture manifold and shared `StationCapture.solve(...)`; along-track capture is free only inside its declared interval. The final brake/transfer is straight FVD control, not a legacy closure.
- `RidePlanner` owns all randomness and terrain/corridor budgets. `RideCompiler` receives no RNG.
- Consume only committed offline `RideFidelityReferences.CATALOG`; persist evidence/recipe hashes. Missing targets remain design assumptions/evidence gaps.

At the start of every task, initialize the portable Godot command:

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

## Upstream Interfaces Consumed Verbatim

- Route/config: the foundation-owned `RideCatalog.data/validate/content_hash`, `RideConfig.resolve`, `RidePlanner.compile`, `CompiledRidePlan.to_dictionary/slot_decisions/resolution_report`, and shared `CanonicalData` serializer/hash utility.
- Motion: `MotionSpan.quintic/validate_sequence`, immutable `MotionTrajectory.create`, `MotionKernel.integrate/production_config`, and `MotionResistance.acceleration_mps2`.
- Solving: `BoundedSolver.solve` and the upstream nine-argument `StationCapture.solve` with `max_trajectory_evaluations = 40`.
- Output/evidence: `RideRoute.create`, `RideFidelity.validate_catalog`, `RideFidelity.measure_route`, and `RideFidelity.compare_fleet`.

The compiler never calls mutable trajectory append APIs. It consumes the kernel's immutable trajectory result, whose construction is owned by `MotionTrajectory.create(...)`.

## Files and New Interfaces

- `motion_program.gd`: immutable spans/windows/metadata; `ride_catalog.gd`: the single versioned config/story/recipe catalog; `ride_planner.gd`: physical targets, terrain/capture budgets, provenance.
- `ride_compiler.gd`: generic interpreter, bounded solves, one integration, `RideRoute`; `default_ride_recipe_tests.gd`: focused Gate 4 suite; `smoke.gd`: suite registration only.

```gdscript
# RideCatalog
const PRESET_ID := "future-hybrid@1"
static func data() -> Dictionary
static func validate() -> PackedStringArray
static func content_hash() -> String
MotionProgram.create(spans: Array, gesture_windows: Array[Dictionary], metadata: Dictionary) -> MotionProgram
MotionProgram.spans() -> Array
MotionProgram.role_span_windows() -> Array[Dictionary]
MotionProgram.validation_errors() -> PackedStringArray
RideCompiler.compile(plan: CompiledRidePlan, kernel_config: MotionKernel.Config = MotionKernel.production_config()) -> Dictionary # {ok, route: RideRoute, program: MotionProgram, report, error}
```

---

### Task 1: Immutable Motion Program Contract

**Files:**
- Create: `godot/motion_program.gd`
- Create: `godot/default_ride_recipe_tests.gd`

**Interfaces:** Produces `MotionProgram` exactly as declared above; consumes `MotionSpan` directly.

- [ ] **Step 1: Create the SceneTree runner and a failing program test.** Build one `MotionSpan.quintic` shoulder and one window `{gesture_id:"test/000", story_slot_id:"act1.giant_inversion", recipe_id:"giant_immelmann", start_span:0, end_span:0}`; assert the exact `MotionProgram.create` call validates and returns one span.

- [ ] **Step 2: Run `& $portableGodot --headless --path '.\godot' --script 'res://default_ride_recipe_tests.gd'`; expect missing `motion_program.gd`.**

- [ ] **Step 3: Implement `MotionProgram` validation and role-level span windows.** Require non-empty ordered spans; `MotionSpan.validate_sequence`; unique immutable `gesture_id` on each gesture window; exact contiguous `start_span..end_span` coverage; story/recipe IDs; required metadata fingerprints/report/counters; and non-negative counters. Every span covered by a window repeats that window's `gesture_id`, carries one stable non-empty `span_role` such as `entry`, `core`, or `exit`, and spans with the same gesture ID and role are contiguous. Derive `role_span_windows()` deterministically in gesture order with `{gesture_id, story_slot_id, role, start_span, end_span}`; reject a role that reappears after another role in the same gesture. Store deep copies; both accessors return duplicates.

- [ ] **Step 4: Add a role-window test.** Build an `entry/core/exit` gesture and assert exactly three ordered role windows, with `core` covering only its own spans. Duplicate/discontiguous role blocks fail validation. This span-level identity is later projected to native sample/time/distance bounds by `RideCompiler`; whole-gesture reporting remains separate.

- [ ] **Step 5: Add a source-level ban test over `motion_program.gd` and future `ride_compiler.gd`.** Reject `GRADE`, `CLOSURE`, `_level`, `_align`, `Bezier`, `Curve3D`, `position_offset`, `translate`, `repair`, `smooth`, `RandomNumberGenerator`, and `randf`.

- [ ] **Step 6: Run the focused suite until green, then commit.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://default_ride_recipe_tests.gd'
git add godot/motion_program.gd godot/default_ride_recipe_tests.gd
git commit -m "feat: define generic motion recipe program"
```

### Task 2: Versioned Recipe Catalog and Planned Physical Targets

**Files:**
- Modify: `godot/ride_catalog.gd`
- Modify: `godot/ride_planner.gd`
- Modify: `godot/compiled_ride_plan.gd`
- Modify: `godot/default_ride_recipe_tests.gd`

**Interfaces:** Consumes the foundation's existing `STORY_SLOT_ORDER`, `STORY_SLOTS`, `RECIPES`, catalog grammar, and evidence catalog verbatim; extends each slot decision with `gesture_id`, `physical_targets`, `terrain_intent`, `terminal_intent`, and provenance. It does not define a second catalog grammar or compatibility/order contract.

- [ ] **Step 1: Add a failing catalog test requiring the exact `PRESET_ID`, all sixteen ordered slots, and seventeen recipes.** Assert `PRESET_ID == "future-hybrid@1"`, `data()` exposes the foundation grammar, `validate()` is empty, and `content_hash() == CanonicalData.sha256_text(CanonicalData.canonical_json(data()))`. Assert each recipe has `version: 1`, compatible slot, `duration_s` capability, `profile_template`, `scale_class`, `terrain_relationship`, `terminal_intent`, `propulsion_zone_id`, `coarse_solve` bounds/budget, and `evidence_target_ids` or explicit `design_assumptions`.

- [ ] **Step 2: Add a failing planner test for stable physical decisions.** Compile seed 42 twice and assert byte-identical `CompiledRidePlan.to_dictionary()`, gesture IDs `future-hybrid@1/<two-digit-index>/<story-slot-id>`, terrain parameters, reserved station capture manifold, selected recipe IDs, target provenance, and zero RNG in compiler inputs.

- [ ] **Step 3: Populate the foundation-owned `RECIPES` without changing its grammar or public IDs.** Use a small fixed vocabulary of templates—`launch`, `drop`, `inversion`, `airtime`, `turn`, `climb`, `dive`, `raceway`, `brake_return`—and catalog data for force/roll/duration/scale/terrain/terminal intent. Declare exactly `const PRESET_ID := "future-hybrid@1"`; implement `data()`, `validate()`, and `content_hash()` only, with `content_hash()` delegating to `CanonicalData.sha256_text(CanonicalData.canonical_json(data()))`. Set propulsion IDs only on `hydraulic_station_launch: 1`, `cliff_lsm_climb: 2`, and `tunnel_lsm: 3`; all other recipes use `0`.

- [ ] **Step 4: Encode these story-specific invariants in catalog data, not compiler branches.** `cliff_lsm_climb` drives only at its base then coasts uphill; `clifftop_suspense` is compact/light; `outward_rim_turn` banks outward; `cliff_dive` commits monotonically; `record_camelback` owns marquee scale; `return_raceway` has zero propulsion and monotonic energy bleed; `station_brakes_return` targets the reserved capture manifold and fixed station endpoint with a positive `station_terminal_speed_mps` below `MIN_MOVING_SPEED`.

- [ ] **Step 5: Extend `RidePlanner.compile` to resolve all physical targets before compilation.** Use existing named decision streams, persist values/capability ranges, emit terrain/corridor/capture budgets, set `evidence_catalog_hash` from `RideFidelityReferences.CATALOG`, and report unresolved preferences honestly.

- [ ] **Step 6: Add impossible planning cases.** Reject out-of-capability structure height, incompatible pinned recipe, missing executable evidence for a field declared evidence-required, propulsion-zone reassignment, and capture reservation outside its preset envelope. Each error includes preset version, seed, story slot, recipe, invariant, and bounds.

- [ ] **Step 7: Run upstream and focused tests, then commit.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://route_contract_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://ride_config_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://ride_planner_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://default_ride_recipe_tests.gd'
git add godot/ride_catalog.gd godot/ride_planner.gd godot/compiled_ride_plan.gd godot/default_ride_recipe_tests.gd
git commit -m "feat: plan future hybrid physical targets"
```

### Task 3: Generic Ride Compiler and Bounded Local Solves

**Files:**
- Create: `godot/ride_compiler.gd`
- Modify: `godot/default_ride_recipe_tests.gd`

**Interfaces:** Produces `RideCompiler.compile(...)` exactly as declared above; consumes only plan decisions, `RideCatalog`, `MotionSpan`, `MotionKernel`, `MotionResistance`, `BoundedSolver`, `StationCapture`, and `RideRoute`.

- [ ] **Step 1: Add a failing table-driven compiler test for every generic profile template.** Each case supplies a synthetic decision and entry state, then asserts non-empty C2 spans, matching gesture metadata, no position fields, terminal state from coarse kernel integration, reported residuals/counters, and deterministic repeat output.

- [ ] **Step 2: Add bounded-solve tests.** A one-variable duration solve must converge within its recipe budget; an impossible target must return `ok=false` with variable, lower/upper bounds, residual, evaluations, seed, slot, and recipe. Assert no evaluation uses `MotionKernel.production_config()` and no retry occurs.

- [ ] **Step 3: Implement a data-driven template dispatch map.** Map exactly `launch`, `drop`, `inversion`, `airtime`, `turn`, `climb`, `dive`, `raceway`, and `brake_return` to the same `_compile_profile` interpreter. Recipe data supplies channel pulses/residuals; unknown IDs are errors, not fallbacks.

- [ ] **Step 4: Implement `_compile_profile`.** Private `_transition`, `_hold`, and `_pulse` helpers call `MotionSpan.quintic` directly with catalogued endpoint jets; use them for entry shoulder, cores/pulses, and exit shoulder. Apply propulsion metadata, integrate only with the declared coarse config, and return terminal state plus counters. Never read or author position control points.

- [ ] **Step 5: Route declared local solves through `BoundedSolver.solve`.** The residual callable changes only catalogued duration/profile parameters, reintegrates that gesture coarsely, and returns normalized terminal-intent residuals. Enforce the per-recipe maximum; cache identical parameter vectors; expose all preferred adjustments in the compile report.

- [ ] **Step 6: Implement `compile` as one ordered pass through `CompiledRidePlan.slot_decisions()`.** Disabled optional `return.release` emits no gesture; all other decisions compile once in story order. Accumulate spans/windows/report/counters, then create `MotionProgram`; stop on the first contextual failure with no partial program or route.

- [ ] **Step 7: Run the focused suite and static ban scan, then commit.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://default_ride_recipe_tests.gd'
rg -n 'GRADE|CLOSURE|_level|_align|Curve3D|Bezier|RandomNumberGenerator|randf|position_offset|geometry_repair' godot/ride_compiler.gd
git add godot/ride_compiler.gd godot/default_ride_recipe_tests.gd
git commit -m "feat: compile data driven ride gestures"
```

### Task 4: Station, Opener, and Cohesive Act-One Recipes

**Files:**
- Modify: `godot/ride_catalog.gd`
- Modify: `godot/default_ride_recipe_tests.gd`

**Interfaces:** Completes recipes for slots `station.launch` through `act1.wave_turn`; compiler remains generic.

- [ ] **Step 1: Add one failing real-kernel test per recipe:** `hydraulic_station_launch`, `twisted_side_drop`, `giant_immelmann`, `helical_leg_loop`, `cutback`, `airtime_hills`, and `wave_turn`. Assert C2 seams, moving-speed legality, finite orthonormal frames, evidence target IDs, intended pitch/roll/force character, terminal intent, and declared solve budget.

- [ ] **Step 2: Add a composite act-one flow test.** Compile the seven slots in order and assert one continuous program with no neutral connector gesture, no sub-minimum span, no useless bank-flat-bank sequence, stable gesture IDs, and boundary-jet continuity from `MotionKernel.boundary_jet`.

- [ ] **Step 3: Add propulsion and launch tests.** Station mode alone may begin below `MotionKernel.MIN_MOVING_SPEED`; the `hydraulic_station_launch` owns propulsion zone 1 and may author positive `drive_g` until it exits at a native step/span boundary through a zero-curvature shoulder. From `twisted_side_drop` through `wave_turn`, every opener/act-one span has propulsion ID 0 and `drive_g == 0`; total `longitudinal_g` there records resistance rather than falsely reading zero.

- [ ] **Step 4: Tune only catalogued physical profile values inside evidence/capability ranges.** The side drop stays non-inverting; giant inversion owns inversion scale; loop has helical lateral sign reversal near its top; cutback combines pitch/roll; airtime and wave turn provide force/release without connector filler. Any target miss returns a compile report, never geometry correction.

- [ ] **Step 5: Run focused tests plus kernel tests.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://motion_kernel_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://default_ride_recipe_tests.gd'
```

- [ ] **Step 6: Commit the independently integrated first act.**

```powershell
git add godot/ride_catalog.gd godot/default_ride_recipe_tests.gd
git commit -m "feat: author default opening ride act"
```

### Task 5: Cliff, Suspense, Dive, Tunnel, and Camelback Recipes

**Files:**
- Modify: `godot/ride_catalog.gd`
- Modify: `godot/default_ride_recipe_tests.gd`

**Interfaces:** Completes `cliff.lsm_climb`, `clifftop.suspense`, `clifftop.rim_turn`, `cliff.dive`, `tunnel.lsm`, and `return.camelback`.

- [ ] **Step 1: Add failing recipe tests for all six slots.** Require source target IDs or explicit design assumptions, C2 shoulders, terrain intent, scale-class separation, bounded evaluations, and no hidden drive.

- [ ] **Step 2: Add the cliff energy test.** Assert propulsion zone 2 is one short base interval; after it ends every climb span has zero longitudinal drive and `end_speed_mps < boost_exit_speed_mps`. The crest supplies the ride's one deliberate slow beat without falling below moving-speed legality.

- [ ] **Step 3: Add shaping tests.** Suspense height remains within its small capability class; rim-turn lateral/roll signs encode outward bank; dive pitch changes monotonically toward vertical with no lip hold; zone 3 is one short tunnel boost; camelback owns marquee structure scale and has no propulsion.

- [ ] **Step 4: Add terrain-relative tests using planner terrain parameters.** Coarse trajectories must satisfy the recipe's declared AGL/corridor residuals with reported bounds; unsupported absolute AGL claims remain evidence gaps. No compiler branch may read world-space control points or patch clearance.

- [ ] **Step 5: Tune only recipe data and rerun focused/kernel/evidence tests.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://default_ride_recipe_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
```

- [ ] **Step 6: Commit the cliff-to-camelback sequence.**

```powershell
git add godot/ride_catalog.gd godot/default_ride_recipe_tests.gd
git commit -m "feat: author default cliff and camelback"
```

### Task 6: Return Raceway and Reserved Station Capture

**Files:**
- Modify: `godot/ride_catalog.gd`
- Modify: `godot/ride_compiler.gd`
- Modify: `godot/default_ride_recipe_tests.gd`

**Interfaces:** Completes `return.release`, `return.raceway`, and `station.brakes_return`; consumes `StationCapture.solve(...)` exactly.

- [ ] **Step 1: Add failing tests for both optional release recipes and the raceway.** Compile `return_airtime_pair` and `return_wave_turn` from pinned configs; assert each owns its shoulders, contains no propulsion, preserves stable IDs, and joins the same raceway contract. Disabled release must omit exactly that slot without shifting other gesture IDs or decision streams.

- [ ] **Step 2: Add an honest return-energy test.** From camelback exit through brake entry, assert propulsion IDs are zero, central resistance is unchanged, total mechanical energy trends downward apart from gravity exchange, and terminal speed lies inside the reserved brake-entry band. No late speed increase may be explained by longitudinal drive.

- [ ] **Step 3: Add station-capture success and impossible tests.** Assert exactly five bounded variables/residuals, along-track capture inside the reserved manifold, contextual residuals/counters, `trajectory_evaluations <= 40`, zero-curvature terminal shoulder, and no call to `StationCapture.validate_at_100hz`. Move one manifold outside capability and require clean failure with no repair or retry.

- [ ] **Step 4: Route only the return-capture pulses through `StationCapture.solve`.** Its `span_factory` ends on the planner's capture manifold with the brake-entry speed band and a structural zero curvature jet. After a successful capture, compile the catalogued straight brake/transfer as an ordinary bounded local profile: the remaining along-track distance determines its finite solve, the moving brake reaches exactly `MIN_MOVING_SPEED`, and the station-mode transfer ends at the positive `station_terminal_speed_mps` at the fixed endpoint. The station/moving boundary is a native step/span boundary. Report the brake solve separately and append neither capture nor brake spans unless both screen successfully; stationary dwell is outside the generated trajectory.

- [ ] **Step 5: Add a source assertion that `ride_compiler.gd` contains one `StationCapture.solve` call and zero `StationCapture.validate_at_100hz`, `CLOSURE`, Bézier, frame reset, translation, or endpoint patch calls.**

- [ ] **Step 6: Run capture, compiler, and kernel suites, then commit.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://station_capture_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://default_ride_recipe_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://motion_kernel_tests.gd'
git add godot/ride_catalog.gd godot/ride_compiler.gd godot/default_ride_recipe_tests.gd
git commit -m "feat: capture default ride at station"
```

### Task 7: Complete Candidate MotionProgram and RideRoute Behind Tests

**Files:**
- Modify: `godot/ride_compiler.gd`
- Modify: `godot/default_ride_recipe_tests.gd`
- Modify: `godot/smoke.gd`

**Interfaces:** Completes `RideCompiler.compile(...)`; must not change `RideGenerator.build(seed_value: int) -> RideRoute`. Runtime cutover will separately add `RideGenerator.build_config(...)`.

- [ ] **Step 1: Add a failing complete-candidate test.** Resolve `future-hybrid@1`, compile its plan/program, and assert sixteen enabled gestures by default, exact story order/recipe IDs, valid `MotionProgram`, valid `RideRoute`, fingerprints, resolution/compile reports, and no legacy section kinds.

- [ ] **Step 2: Add exact work-shape tests.** Spy on integration calls and assert: planning uses zero integrations; every recipe solve reports bounded coarse evaluations; station capture reports at most 40; accepted candidate calls `MotionKernel.integrate` with production config exactly once and `StationCapture.validate_accepted_trajectory` exactly once; route counters report `full_resolution_integrations == 1`; accepted-trajectory validation reports zero integrations; there is no full-route candidate loop or duplicate time/distance kernel.

- [ ] **Step 3: Add exact propulsion and energy assertions.** Read `route.verification_inputs.propulsion_zone_ids`, collapse contiguous runs, and require `[1, 2, 3]`. Assert no ID reappears, no fourth zone exists, unpowered cliff/return spans use zero longitudinal drive, and central resistance produces measured speed/energy loss.

- [ ] **Step 4: Complete `RideCompiler.compile` and validate the accepted capture without reintegration.** Validate plan/catalog, generate terrain from recorded parameters without RNG, compile one program, and call `MotionKernel.integrate(program.spans(), initial_state, resistance, kernel_config)` exactly once. Project every `MotionProgram.role_span_windows()` entry to deterministic native sample, time, and distance bounds and nest those role windows beneath the corresponding whole-gesture route window. Then call `StationCapture.validate_accepted_trajectory` against the recorded native boundaries of that one trajectory. Recompute all five station-local residuals, along-track interval, brake-entry speed band, terminal zero-curvature value/d1/d2 jet, moving/station law handoff at `MIN_MOVING_SPEED`, and the fixed terminal endpoint with catalogued positive creep speed. Any miss returns `integrator_correctness_failure`; do not retry, reintegrate, relax, or append a repair. Only after this check succeeds, construct verification inputs and call `RideRoute.create`. Return exactly `{ok, route, program, report, error}`; never call `RideGenerator`, `LegacyRouteAdapter`, or a repair pass.

- [ ] **Step 5: Add accepted-trajectory capture and role-resolution tests.** Perturb each recorded boundary invariant in turn and require a contextual `integrator_correctness_failure` with `full_resolution_integrations == 1`. Assert an `act1` compiled `core` role window excludes the open interiors of its `entry` and `exit`, every role boundary lands on its recorded span boundary, adjacent roles share exactly that one C2 seam sample/physical endpoint, and exact-duration held measurement over `core` uses `core.end_time_s - core.start_time_s` without concatenating either neighbor.

- [ ] **Step 6: Add a fifteen-seed private candidate test.** Use the evidence plan's canonical fleet order `[11, 42, 20260809, 1, 3, 7, 99, 256, 555, 1234, 4096, 31337, 77777, 123456, 20250101]`; build each once, validate physics/safety and evidence measurements, compare two seed-42 builds for identical topology/IDs/reports/counters, and record numeric tolerances for floating arrays.

- [ ] **Step 7: Register only `DefaultRideRecipeTests.run()` in `smoke.gd`.** Add a source test proving `generator.gd` does not import `ride_compiler.gd` or define `build_config`, and `RideGenerator.build` still returns the characterized legacy-adapted route.

- [ ] **Step 8: Run all focused and stable commands.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://route_contract_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://ride_config_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://ride_planner_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://motion_kernel_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://bounded_solver_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://station_capture_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://default_ride_recipe_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
```

- [ ] **Step 9: Run adversarial source/work-counter checks and inspect the diff.**

```powershell
rg -n 'GRADE|CLOSURE|_level|_align|Curve3D|Bezier|RandomNumberGenerator|randf|repair|smooth|translate' godot/motion_program.gd godot/ride_compiler.gd
rg -n 'ride_compiler|build_config' godot/generator.gd godot/main.gd
git diff -- godot/generator.gd godot/main.gd
```

Expected: both `rg` commands have no hits and the runtime diff is empty. Independently review catalog capability claims, force/roll units, C2 seams, terrain residuals, exactly three propulsion zones, resistance use, solve bounds/counters, station capture, one final integration, failure context, and absence of unnecessary abstractions.

- [ ] **Step 10: Commit the private complete candidate gate.**

```powershell
git add godot/ride_compiler.gd godot/default_ride_recipe_tests.gd godot/smoke.gd
git commit -m "feat: compile complete default ride candidate"
```

## Gate 4 Completion Boundary

Gate 4 requires all seventeen recipes, the sixteen-slot default story, both release variants, reserved station capture, C2 programs, valid routes, evidence provenance, bounded solves, one 100 Hz integration, propulsion runs `[1, 2, 3]`, honest unpowered loss, contextual failures, and green focused/import/smoke commands. `RideGenerator.build` remains legacy; cutover, deletion, and final audit/polish are later gates.
