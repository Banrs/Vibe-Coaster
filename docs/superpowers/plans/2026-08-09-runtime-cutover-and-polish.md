# Runtime Cutover and Polish Implementation Plan

> **Superseded — design history, not an executable plan.** Superseded by
> `2026-08-12-material-generator-vertical-slice.md` and its execution addendum
> `../specs/2026-08-12-material-generator-vertical-slice-design.md`, which landed on `main` on
> 2026-08-15. Do not execute the steps below: the cutover and the deletion of `elements.gd` are
> already done, and its `RideVerify.ROW_OFFSETS_M` step landed as `RouteContract.ROW_OFFSETS`
> instead. Read this for rationale.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the tested configuration/planner/compiler/time-domain-kernel pipeline the only runtime generator, remove the legacy geometry system, refine the default fleet from committed evidence, and preserve verified viewer, audit, and guided-authoring workflows.

**Architecture:** `RideGenerator` becomes a thin façade over `RideConfig -> RidePlanner -> RideCompiler`; `RideCompiler` alone compiles `MotionProgram`, runs the accepted `MotionKernel` integration, and returns `RideRoute`. Consumers remain on `RideRoute`/`MotionTrajectory`; `RideFidelityArtifacts` drives bounded review. The temporary adapter and legacy execution are deleted in the same cutover.

**Tech Stack:** Godot 4.7.1, typed GDScript, JSON-compatible configuration, existing headless tests, `RideFidelityArtifacts`, PowerShell command examples with `GODOT_BIN` override, and Graphify only in the final hygiene task.

## Global Constraints

- Begin only after `2026-08-09-route-config-foundation.md`, `2026-08-09-time-domain-motion-kernel.md`, `2026-08-09-default-ride-recipes.md`, and `2026-08-09-evidence-audit-baseline.md` pass their acceptance gates.
- Consume these exact public types: `MotionSpan`, `MotionKernel`, `MotionTrajectory`, `RideRoute`, `RideConfig`, `CompiledRidePlan`, `RidePlanner`, shared `RideCatalog`, `RideCompiler`, and `RideFidelityArtifacts`. Do not add parallel trajectory, catalog, plan, or compiler types.
- Consume these exact catalog/compiler contracts: `RideCatalog.data() -> Dictionary`, `RideCatalog.validate() -> PackedStringArray`, `RideCatalog.content_hash() -> String`, `RideCatalog.PRESET_ID == "future-hybrid@1"`, and `RideCompiler.compile(plan: CompiledRidePlan, kernel_config: MotionKernel.Config = MotionKernel.production_config()) -> Dictionary` returning `{ok, route: RideRoute, program: MotionProgram, report, error}`.
- Consume `MotionProgram.create(spans: Array, gesture_windows: Array[Dictionary], metadata: Dictionary) -> MotionProgram`, `spans() -> Array`, `role_span_windows() -> Array[Dictionary]`, and `validation_errors() -> PackedStringArray`; do not reconstruct a second program in `RideGenerator`.
- Preserve `RideGenerator.build(seed_value: int) -> RideRoute`. Add `RideGenerator.build_config(file_config: Dictionary, cli_overrides: Array[Dictionary] = []) -> Dictionary` returning `{ok, route, resolved_config, plan, errors}`.
- Exactly one full-resolution integration is permitted for an accepted route. No RNG, route search, retry, geometry repair, smoothing, or fitted replacement path may occur after planning.
- Legacy geometry is not a compatibility target. Retain safety, physics, deterministic-input, work-counter, audit, viewer, and command contracts.
- Refinement may change shared recipe/catalog values and preset choices only. Never add seed branches, seed patches, force/clearance tolerance inflation, hidden propulsion, target relaxation, or post-generation correction.
- Retain per-gesture profiles, whole-route top/elevation, and force/angle/speed/AGL overlays, including longitudinal proper-g, curvature, radius, roll acceleration, and jerk.
- Normal runtime and CI remain offline. Graphify is forbidden until Task 7.

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

---

### Task 1: Make the new pipeline authoritative in `RideGenerator`

**Files:**
- Create: `godot/runtime_cutover_tests.gd`
- Modify: `godot/generator.gd`
- Modify: `godot/smoke.gd`

**Interfaces:**
- Consumes: `RideConfig.resolve`, `RidePlanner.compile`, `RideCompiler.compile`, and the exact shared contracts above.
- Produces: `RideGenerator.build(seed_value: int) -> RideRoute` and `RideGenerator.build_config(file_config: Dictionary, cli_overrides: Array[Dictionary] = []) -> Dictionary`.

- [ ] **Step 1: Add a failing equivalence and provenance test.**

```gdscript
static func _test_default_build_path(errors: PackedStringArray) -> void:
	var direct: RideRoute = RideGenerator.build(42)
	var configured := RideGenerator.build_config({
		"ride_config_version": 1, "preset": RideCatalog.PRESET_ID, "seed": 42,
	})
	_expect(errors, configured.ok, "default config builds")
	_expect(errors, direct.fingerprints.normalized_config_hash == configured.route.fingerprints.normalized_config_hash, "seed shorthand uses normalized config")
	_expect(errors, direct.trajectory.position_m == configured.route.trajectory.position_m, "seed shorthand and config entry point share one pipeline")
	_expect(errors, configured.route.fingerprints.recipe_catalog_hash == RideCatalog.content_hash(), "route records exact recipe catalog")
	_expect(errors, configured.route.solver_counters.full_resolution_integrations == 1, "accepted route integrates once")
	var measured := RideFidelity.measure_route(direct, RideVerify.ROW_OFFSETS_M)
	var compared := RideFidelity.compare_fleet([measured], RideFidelityReferences.CATALOG)
	for gap in compared.evidence_gaps:
		_expect(errors, gap.get("reason", "") != "selector_unresolved", "compiled route resolves semantic selector %s" % gap.get("semantic_selector_id", "<missing>"))
	var gesture := _gesture_by_story_slot(direct, "act1.giant_inversion")
	var core := direct.role_window(gesture.gesture_id, "core")
	_expect(errors, not core.is_empty(), "compiled core role resolves explicitly")
	_expect(errors, core.start_native_sample > gesture.start_native_sample, "compiled core excludes entry")
	_expect(errors, core.end_native_sample < gesture.end_native_sample, "compiled core excludes exit")
```

This is the catalog migration gate: the same target IDs and catalog hash used for the legacy baseline remain unchanged, while every applicable executable selector resolves through its compiled anchor. Compiled anchors resolve their declared role against native sample/time/distance subwindows, so `core` cannot include an entry or exit shoulder. A legacy-only or compiled-only selector must declare the other branch inapplicable explicitly; no code falls back from one anchor branch or role to another.

- [ ] **Step 2: Add a failing structured-error test.**

```gdscript
static func _test_build_config_error(errors: PackedStringArray) -> void:
	var result := RideGenerator.build_config({"ride_config_version": 1, "preset": RideCatalog.PRESET_ID, "seed": 42, "sequence": {"order": []}})
	_expect(errors, not result.ok and result.route == null, "invalid config returns no partial route")
	_expect(errors, result.errors[0].stage == "configuration", "configuration failure keeps its stage")
```

- [ ] **Step 3: Run the focused test and confirm `build_config` is absent.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://runtime_cutover_tests.gd'
```

- [ ] **Step 4: Replace the public generator body with the exact façade.**

```gdscript
static func build(seed_value: int) -> RideRoute:
	var result := build_config({"ride_config_version": 1, "preset": RideCatalog.PRESET_ID, "seed": seed_value})
	if not result.ok:
		push_error("generation failed for seed %d: %s" % [seed_value, str(result.errors)])
		return null
	return result.route

static func build_config(file_config: Dictionary, cli_overrides: Array[Dictionary] = []) -> Dictionary:
	var resolved := RideConfig.resolve(file_config, cli_overrides)
	if not resolved.ok:
		return {"ok": false, "route": null, "resolved_config": null, "plan": null, "errors": resolved.errors}
	var planned := RidePlanner.compile(resolved.value)
	if not planned.ok:
		return {"ok": false, "route": null, "resolved_config": resolved, "plan": null, "errors": planned.errors}
	var compiled := RideCompiler.compile(planned.plan)
	if not compiled.ok:
		return {"ok": false, "route": null, "resolved_config": resolved, "plan": planned.plan, "errors": [compiled.error]}
	return {"ok": true, "route": compiled.route, "resolved_config": resolved, "plan": planned.plan, "errors": []}
```

- [ ] **Step 5: Add the focused suite to `smoke.gd`, run all prerequisite suites, and commit.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://runtime_cutover_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://motion_kernel_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://default_ride_recipe_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git add godot/generator.gd godot/runtime_cutover_tests.gd godot/smoke.gd
git commit -m "feat: cut generator over to motion compiler"
```

---

### Task 2: Delete the legacy geometry and repair runtime

**Files:**
- Delete: `godot/legacy_route_adapter.gd`
- Delete: `godot/elements.gd`
- Delete matching `.uid` files if present.
- Modify: `godot/generator.gd`
- Modify: `godot/smoke.gd`
- Modify: `godot/verify.gd`
- Modify: `godot/main.gd`
- Modify: `godot/fidelity.gd`
- Modify: `godot/fidelity_artifacts.gd`
- Modify: `godot/fidelity_tests.gd`
- Modify: `godot/fidelity_artifact_tests.gd`
- Modify: `godot/_inspect.gd`
- Modify: `godot/runtime_cutover_tests.gd`

**Interfaces:**
- Preserves: only the two Task 1 `RideGenerator` entry points.
- Removes: `_build_legacy`, legacy `REGISTRY`, sequential legacy `_plan`, `FVD`/`GRADE`/`CLOSURE`, `_level`, `_align`, `append_closure`, connector/Bezier repair, and raw-route fixtures.

- [ ] **Step 1: Add a failing source-boundary test.**

```gdscript
static func _test_no_legacy_runtime(errors: PackedStringArray) -> void:
	for path in ["res://generator.gd", "res://smoke.gd", "res://fidelity.gd", "res://fidelity_artifacts.gd", "res://verify.gd", "res://main.gd", "res://_inspect.gd"]:
		var source := FileAccess.get_file_as_string(ProjectSettings.globalize_path(path))
		for forbidden in ["LegacyRouteAdapter", "_build_legacy", "append_closure", "_level(", "_align(", "\"GRADE\"", "\"CLOSURE\""]:
			_expect(errors, not source.contains(forbidden), "%s retains %s" % [path, forbidden])
```

- [ ] **Step 2: Move train-row offsets to the verifier contract before deleting `elements.gd`.**

Add `RideVerify.ROW_OFFSETS_M` with the exact seven existing metre offsets; replace `RideElements.ROW_OFFSETS` imports in `main.gd`, `verify.gd`, `smoke.gd`, `fidelity.gd`, `fidelity_artifacts.gd`, `_inspect.gd`, and every focused/runtime fixture with it. Run an exhaustive `rg` assertion and import before deleting the old file.

- [ ] **Step 3: Delete legacy generator methods and element/template probes.**

Keep `generator.gd` as the Task 1 façade. Remove `elements.gd` probes; retain route, kernel, compiler, safety, load, determinism, and arbitrary-seed tests. Convert remaining fidelity fixtures to `RideRoute`.

- [ ] **Step 4: Delete the adapter and legacy element files, then prove no runtime reference remains.**

```powershell
rg -n 'LegacyRouteAdapter|_build_legacy|RideElements|"(FVD|GRADE|CLOSURE)"|append_closure|_level\(|_align\(' godot -g '*.gd'
```

Expected: no matches under `godot/`.

- [ ] **Step 5: Run the complete gate and commit deletion.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://runtime_cutover_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git add -A godot
git commit -m "refactor: remove legacy geometry runtime"
```

---

### Task 3: Characterize authoritative consumers and work shape

**Files:**
- Modify: `godot/runtime_cutover_tests.gd`
- Modify only on failure: `godot/main.gd`, `godot/verify.gd`, `godot/fidelity.gd`, `godot/_inspect.gd`, `godot/smoke.gd`

**Interfaces:**
- Consumes: `RideRoute`/`MotionTrajectory` only.
- Verifies: viewer, verifier, audit, and artifact writer share the same generated route and do not reintegrate or fit geometry.

- [ ] **Step 1: Add a fifteen-seed work-counter test.**

```gdscript
const AUDIT_SEEDS := [11, 42, 20260809, 1, 3, 7, 99, 256, 555, 1234, 4096, 31337, 77777, 123456, 20250101]

static func _test_authoritative_fleet(errors: PackedStringArray) -> void:
	for seed_value in AUDIT_SEEDS:
		var route: RideRoute = RideGenerator.build(seed_value)
		_expect(errors, route != null, "seed %d builds" % seed_value)
		_expect(errors, route.solver_counters.full_resolution_integrations == 1, "seed %d integrates once" % seed_value)
		_expect(errors, route.solver_counters.get("post_generation_repairs", 0) == 0, "seed %d has no repair" % seed_value)
```

- [ ] **Step 2: Add consumer characterization for seed 42.**

Build once, pass the same object to `RideVerify.analyze`, `RideFidelity.measure_route`, `Main.build_rail_mesh`, and `Main.build_terrain_mesh`; assert validation passes, meshes contain one surface, gesture IDs agree, and native-channel hashes are unchanged after every consumer.

- [ ] **Step 3: Run viewer and audit commands without compatibility wrappers.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://runtime_cutover_tests.gd'
$env:INSPECT_OUT = Join-Path (Get-Location) 'out\cutover-characterization'
& $portableGodot --headless --path '.\godot' --script 'res://_inspect.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
```

- [ ] **Step 4: Fix only typed-contract or duplicate-work failures, rerun, and commit.**

```powershell
git add godot/runtime_cutover_tests.gd godot/main.gd godot/verify.gd godot/fidelity.gd godot/_inspect.gd godot/smoke.gd
git commit -m "test: characterize authoritative ride consumers"
```

---

### Task 4: Run bounded evidence-driven fleet refinement

**Files:**
- Modify when justified: `godot/ride_catalog.gd` and the owning recipe data files named by `RideCatalog.data()`.
- Modify: `godot/runtime_cutover_tests.gd`
- Do not modify: `godot/verify.gd`, safety limits, evidence target bands/transforms, kernel tolerances, solver budgets, or seed handling.

**Interfaces:**
- Consumes: `RideFidelity.compare_fleet`, `RideFidelityArtifacts.build_report`, and the exact fifteen-seed artifact pack.
- Produces: evidence-backed shared catalog/recipe values and an updated `RideCatalog.content_hash()`.

- [ ] **Step 1: Generate the pre-refinement pack twice and compare deterministic reports.**

```powershell
$env:INSPECT_OUT = Join-Path (Get-Location) 'out\cutover-before-a'
& $portableGodot --headless --path '.\godot' --script 'res://_inspect.gd'
$env:INSPECT_OUT = Join-Path (Get-Location) 'out\cutover-before-b'
& $portableGodot --headless --path '.\godot' --script 'res://_inspect.gd'
Compare-Object (Get-Content 'out\cutover-before-a\audit.json') (Get-Content 'out\cutover-before-b\audit.json')
Compare-Object (Get-Content 'out\cutover-before-a\audit.md') (Get-Content 'out\cutover-before-b\audit.md')
```

Expected: no comparison output.

- [ ] **Step 2: Select exactly one eligible finding per iteration.**

Read `comparison.recommendation` from `audit.json`. Proceed only for a medium/high-confidence executable target missed by at least eight seeds. Trace it to one owning recipe/catalog field and record source IDs/current value in catalog provenance. If it says `no-eligible-finding`, make no change.

- [ ] **Step 3: Add a fleet test for the selected evidence target before changing its value.**

The test must build all fifteen seeds, measure the exact target selector/row/hold window through `RideFidelity`, and assert the target's documented transformed band and minimum eight-seed prevalence. It must not mention individual seed values in implementation logic.

- [ ] **Step 4: Change the single owning catalog/recipe value and rerun all gates.**

Accept only if normalized median miss decreases, all seeds pass safety/physics, no within-band dimension becomes a new eligible miss, and counters remain bounded. Repeat Steps 2–4 for at most three accepted changes.

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://runtime_cutover_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git diff --exit-code -- godot/verify.gd godot/motion_kernel.gd godot/bounded_solver.gd
rg -n 'seed(_value)?\s*(==|!=|<|>)|match\s+seed' godot/ride_catalog.gd godot/ride_compiler.gd godot/recipes -g '*.gd'
```

Expected: protected-file diff and seed-patch search emit nothing.

- [ ] **Step 5: Generate the accepted pack and commit each accepted shared refinement separately.**

```powershell
$env:INSPECT_OUT = Join-Path (Get-Location) 'out\cutover-after'
& $portableGodot --headless --path '.\godot' --script 'res://_inspect.gd'
git add godot/ride_catalog.gd godot/recipes godot/runtime_cutover_tests.gd
git commit -m "tune: refine default ride from fleet evidence"
```

Skip the commit if no eligible finding exists.

---

### Task 5: Preserve diagnostics and prove curvature/smoothing integrity

**Files:**
- Modify: `godot/fidelity_artifact_tests.gd`
- Modify: `godot/runtime_cutover_tests.gd`
- Modify only on failure: `godot/fidelity.gd`, `godot/fidelity_artifacts.gd`, `godot/_inspect.gd`

**Interfaces:**
- Consumes: `RideFidelity.reconstruct_channels(route)`, `RideFidelityArtifacts.write_pack`, and the authoritative `MotionTrajectory` dense sampling API.
- Verifies: raw generated positions remain the sole geometry used by physics, verification, viewer, fidelity, and artifacts.

- [ ] **Step 1: Add native-endpoint and force-reconstruction tests.**

```gdscript
static func _test_trajectory_integrity(errors: PackedStringArray) -> void:
	var route: RideRoute = RideGenerator.build(42)
	var sample := MotionSample.new()
	for i in route.trajectory.time_s.size():
		route.trajectory.sample_time_into(route.trajectory.time_s[i], sample)
		_expect(errors, sample.position_m.distance_to(route.trajectory.position_m[i]) <= 1e-5, "dense output meets native sample %d" % i)
	var reconstructed := RideFidelity.reconstruct_channels(route)
	_expect(errors, reconstructed.force_error_peak_g <= 0.02, "authored and reconstructed proper force agree")
	_expect(errors, not reconstructed.has("filtered_positions") and not reconstructed.has("smoothed_positions"), "integrity path creates no replacement geometry")
```

- [ ] **Step 2: Assert the complete diagnostic manifest.**

Require `top.png`, `elevation.png`, `channels.png`, and every stable gesture profile. Require speed, three proper-g axes, pitch, roll rate, AGL, curvature, radius, roll acceleration, and jerk; raw and source-filtered channels need distinct legend IDs.

- [ ] **Step 3: Run artifact tests and inspect the seed-42 review set.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_artifact_tests.gd'
$env:INSPECT_OUT = Join-Path (Get-Location) 'out\cutover-integrity'
& $portableGodot --headless --path '.\godot' --script 'res://_inspect.gd'
Get-ChildItem 'out\cutover-integrity\review\seed-42' -Recurse -File | Select-Object FullName,Length
```

Inspect top/elevation, whole-route channels, giant inversion, cliff dive, camelback, and return-raceway profiles. Reject clipped plots, missing legends, empty PNGs, unreported curvature discontinuity, or a visual path differing from `MotionTrajectory.position_m`.

- [ ] **Step 4: Search for forbidden smoothing/fitted geometry paths, run smoke, and commit.**

```powershell
rg -n 'smooth(ed|ing)?_positions|filtered_positions|fit(ted)?_path|radius_clamp|viewer_path|physics_path' godot -g '*.gd'
& $portableGodot --headless --path '.\godot' --script 'res://runtime_cutover_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git add godot/fidelity_artifact_tests.gd godot/runtime_cutover_tests.gd godot/fidelity.gd godot/fidelity_artifacts.gd godot/_inspect.gd
git commit -m "test: verify ride diagnostic integrity"
```

Expected search matches only negative assertions or explicitly labelled evidence-filtered force channels, never generated positions.

---

### Task 6: Add the guided configuration command and final documentation

**Files:**
- Create: `godot/generate.gd`
- Create: `godot/configs/future-hybrid-example.json`
- Create: `godot/generate_tests.gd`
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `docs/ISSUES.md`
- Modify: `godot/smoke.gd`

**Interfaces:**
- Consumes: `RideGenerator.build_config` and `RideFidelityArtifacts.canonical_json`/`write_text_checked`.
- Command example: `& $portableGodot --headless --path '.\godot' --script 'res://generate.gd' -- --config 'res://configs/future-hybrid-example.json' --override '{"seed":99}' --out 'user://guided-99'`.
- Produces: `<directory>/generation.json` containing normalized-config hash, preset, seed, ordered gesture decisions, resolution report, route summary, fingerprints, and solver counters.

- [ ] **Step 1: Add parser and end-to-end command tests.**

```gdscript
static func _test_guided_command(errors: PackedStringArray) -> void:
	var parsed := Generate.parse_args(["--config", "res://configs/future-hybrid-example.json", "--override", "{\"seed\":99}", "--out", "user://guided-test"])
	_expect(errors, parsed.ok and parsed.cli_overrides[0].seed == 99, "guided override remains a RideConfig layer")
	var result := Generate.run(parsed)
	_expect(errors, result.is_empty(), "guided generation succeeds")
	var report := JSON.parse_string(FileAccess.get_file_as_string("user://guided-test/generation.json"))
	_expect(errors, report.seed == 99 and report.solver_counters.full_resolution_integrations == 1, "guided report records authoritative build")
```

- [ ] **Step 2: Implement strict argument parsing.**

Accept one `--config`, zero or more `--override` JSON objects in argument order, and one `--out`. Reject missing values, duplicate config/output flags, non-object JSON, unknown flags, and failed writes with non-zero exit; pass parsed dictionaries directly to `RideGenerator.build_config`.

- [ ] **Step 3: Add the exact example config.**

```json
{
  "ride_config_version": 1,
  "preset": "future-hybrid@1",
  "seed": 42,
  "sequence": {"pinned": {}},
  "constraints": {"required": [], "preferred": []}
}
```

- [ ] **Step 4: Document preset, guided command, overlay order, outputs, failures, and review command.**

Document preset → file → ordered overrides and that all guided input uses `RideConfig`. Update `docs/ISSUES.md` with the post-cutover issue-coverage artifact, leaving unresolved items open and recording any promoted gate's evidence/threshold/test provenance. Include:

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://generate.gd' -- --config 'res://configs/future-hybrid-example.json' --override '{"seed":99}' --out 'user://guided-99'
$env:INSPECT_OUT = Join-Path (Get-Location) 'out\fidelity'
& $portableGodot --headless --path '.\godot' --script 'res://_inspect.gd'
```

- [ ] **Step 5: Run tests, smoke, and commit.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://generate_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git add godot/generate.gd godot/configs/future-hybrid-example.json godot/generate_tests.gd godot/smoke.gd README.md CLAUDE.md docs/ISSUES.md
git commit -m "feat: document guided ride generation"
```

---

### Task 7: Independent review loops and Graphify-assisted hygiene

**Files:**
- Review: all runtime, catalog, recipe, fidelity, test, and documentation changes.
- Modify only when a finding is reproduced: the owning file and its focused test.

**Interfaces:**
- Verifies: approved design gates 5–6, no legacy/bypass paths, no duplicate ownership, and no dead cutover code.

- [ ] **Step 1: Run a fresh complete acceptance pass.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://runtime_cutover_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://motion_kernel_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://default_ride_recipe_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_artifact_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://generate_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
```

- [ ] **Step 2: Request an independent lightweight specification review.**

Use `superpowers:requesting-code-review` with a fresh reviewer: “Compare the diff against design sections 1, 3–4, 9–14 and the four prerequisite plans. Report reproducible gaps in routing, deletion, evidence, diagnostics, smoothing integrity, counters, guided config, or commands.” Reproduce findings and test accepted issues.

- [ ] **Step 3: Request a second independent lightweight code-quality review.**

Use a different fresh reviewer with: “Find duplicate pipeline/catalog/trajectory ownership, hidden retries or repairs, seed logic, mutable-plan leaks, unchecked writes, dead legacy code, and needless abstractions. Cite files and lines.” Reject stylistic churn; fix only verified defects.

- [ ] **Step 4: Only now run Graphify over the final code.**

```powershell
python -m graphify extract . --code-only --force --no-cluster
python -m graphify query "After the runtime cutover, what executable paths bypass RideGenerator.build_config, RidePlanner, RideCompiler, MotionKernel, MotionTrajectory, RideRoute, RideCatalog, or RideFidelityArtifacts; what legacy FVD, GRADE, CLOSURE, repair, duplicate sampling, duplicate catalog, dead API, or orphaned test paths remain?" --budget 2500 --graph '.\graphify-out\graph.json'
```

For every reported path, confirm it with `rg` and direct file inspection. Add a failing test before removing a real bypass or orphan; ignore documentation/history-only references.

- [ ] **Step 5: Rerun the complete acceptance pass after review fixes.**

Repeat the eight commands from Step 1. Regenerate `out\cutover-after`, inspect the same seed-42 artifact set, and confirm the fifteen-seed `audit.json`/`audit.md` remain deterministic.

- [ ] **Step 6: Inspect final scope and commit verified review fixes.**

```powershell
git status --short
git diff --check
git diff --stat
rg -n 'LegacyRouteAdapter|_build_legacy|RideElements|"(FVD|GRADE|CLOSURE)"|append_closure|_level\(|_align\(' godot -g '*.gd'
git add godot README.md CLAUDE.md docs/ISSUES.md
git commit -m "refactor: complete runtime cutover review"
```

Expected: no whitespace errors, no legacy matches, and only scoped files changed. Skip the commit when review produces no changes.
