# Route and Configuration Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Define the final immutable `MotionTrajectory`/`RideRoute` consumer contract, migrate the legacy generator through one explicitly temporary adapter without changing its geometry, and implement deterministic version-1 configuration normalization and planning.

**Architecture:** `MotionTrajectory` is an immutable factory-built container of packed native SI channels plus one immutable packed dense sampler; the sampler owns its interpolation data and never refers back to `MotionTrajectory` or `MotionKernel`. `MotionSample` is the one typed mutable scratch record used by allocation-free hot-path sampling, while convenience sampling allocates exactly one result. `RideRoute` is the final object returned by `RideGenerator.build`, and all consumers migrate to it in the same green commit as `LegacyRouteAdapter`. Shared `RideCatalog` owns the versioned configuration grammar, story slots, recipe compatibility, and public-key registry; `RideConfig` canonicalizes overlays and `RidePlanner` emits immutable `CompiledRidePlan` data without controlling legacy geometry.

**Tech Stack:** Godot 4.7.1, typed GDScript, packed arrays, `JSON`, `HashingContext`, and `RandomNumberGenerator`; no third-party dependencies or network access.

## Global Constraints

- `docs/superpowers/specs/2026-08-09-fvd-first-configurable-generator-design.md` is authoritative. Current legacy shape, timing, and smoke target bands are characterization only.
- Consume the same names used by the other plans: `MotionSpan`, `MotionKernel`, `MotionTrajectory`, `RideRoute`, `RideCatalog`, `RideConfig`, `CompiledRidePlan`, `RidePlanner`, `MotionProgram`, `RideCompiler`, and `RideFidelityArtifacts`. Do not add parallel catalog, trajectory, plan, or route types.
- `RideGenerator.build(seed_value: int) -> RideRoute` is the final seed entry point. This plan does not add a wrapper return type or expose a selectable geometry system.
- `LegacyRouteAdapter` is temporary and may be imported only by `generator.gd` and focused adapter tests. Delete it at the runtime-cutover gate after `RideCompiler` emits `RideRoute` directly.
- The adapter must preserve legacy native positions, times, distances, speeds, frames, controls, section attribution, and geometry exactly; it converts degrees to radians once at ingestion.
- No consumer may read the raw route dictionary, `route.plan`, `FVD`/`GRADE`/`CLOSURE`, or adapter internals after the atomic migration.
- `MotionTrajectory` has no mutable append API and no dependency on `MotionKernel.State` or `MotionKernel.Derivative`. The kernel later supplies one immutable packed Hermite sampler through the same factory.
- Version 1 accepts only catalogued keys; it rejects explicit `null`, unknown fields/slots/recipes, incompatible pins, grammar contradictions, and `sequence.order`.
- Required constraints are planning-time equalities. State-dependent duration, speed, and height requests remain preferred and unresolved until `RideCompiler` owns them.
- Planner randomness uses stable named streams and never consumes or perturbs the legacy terrain/generator RNG.
- Never commit a knowingly red import or smoke gate. The adapter, generator return change, verifier, viewer, smoke, fidelity, inspector, and fixtures migrate atomically in Task 2.

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

## Fixed public interfaces

```gdscript
# motion_sample.gd
class_name MotionSample
extends RefCounted
# Mutable scratch fields: time_s, distance_m, position_m, tangent, rider_up, speed_mps,
# normal_g, lateral_g, longitudinal_g, drive_g, roll_rate_rad_s, and span_index.

# motion_trajectory.gd
class_name MotionTrajectory
extends RefCounted

class DenseSampler extends RefCounted:
	func interval_count() -> int
	func sample_time_into(query_time_s: float, out: MotionSample) -> void
	func sample_distance_into(query_distance_m: float, out: MotionSample) -> void
	func interval_error_estimate(interval_index: int) -> Dictionary

static func create(
	channels: Dictionary,
	dense_sampler: DenseSampler = null
) -> MotionTrajectory
func sample_time(query_time_s: float) -> MotionSample
func sample_time_into(query_time_s: float, out: MotionSample) -> void
func sample_distance(query_distance_m: float) -> MotionSample
func sample_distance_into(query_distance_m: float, out: MotionSample) -> void
func interval_error_estimate(interval_index: int) -> Dictionary
func validation_errors() -> PackedStringArray

# ride_route.gd
RideRoute.create(seed_value: int, trajectory: MotionTrajectory, gesture_windows: Array[Dictionary], terrain: Dictionary, fingerprints: Dictionary, resolution_report: Array[Dictionary], solver_counters: Dictionary, verification_inputs: Dictionary) -> RideRoute
RideRoute.validation_errors() -> PackedStringArray
RideRoute.gesture_at_sample(sample_index: int) -> Dictionary
RideRoute.role_window(gesture_id: String, role: String) -> Dictionary

# ride_catalog.gd
RideCatalog.PRESET_ID == "future-hybrid@1"
RideCatalog.STORY_SLOT_ORDER
RideCatalog.STORY_SLOTS
RideCatalog.RECIPES
RideCatalog.data() -> Dictionary
RideCatalog.validate() -> PackedStringArray
RideCatalog.content_hash() -> String

# ride_config.gd / ride_planner.gd
RideConfig.resolve(file_config: Dictionary = {}, cli_overrides: Array[Dictionary] = []) -> Dictionary
CanonicalData.canonical_json(value: Variant) -> String
CanonicalData.sha256_text(value: String) -> String
RidePlanner.compile(resolved_config: Dictionary) -> Dictionary
```

`channels` has one closed schema: `time_s`, `distance_m`, `position_m`, `position_dt_mps`, `tangent`, `tangent_dt_per_s`, `rider_up`, `rider_up_dt_per_s`, `speed_mps`, `speed_dt_mps2`, `normal_g`, `lateral_g`, `longitudinal_g`, `drive_g`, `roll_rate_rad_s`, and `span_index`. `drive_g` is the authored propulsion/brake command; `longitudinal_g` is total proper acceleration after resistance and is the channel compared with accelerometer evidence. Time and distance are strictly increasing after the initial sample; speed may be zero only at that initial instant, so stationary station dwell is intentionally outside the trajectory and distance sampling has no plateau ambiguity. Every native channel is exposed read-only under that singular name; packed-array getters return copy-on-write values and there are no setters. A dense sample writes the corresponding physical state, authored controls, and total longitudinal telemetry into a caller-owned `MotionSample`. The convenience methods allocate one `MotionSample`; hot consumers reuse one record with the `*_into` methods. One immutable packed `DenseSampler` owns all interval interpolation/error-estimate data; the trajectory never allocates one object per integration step.

---

### Task 1: Immutable `MotionTrajectory` and final `RideRoute`

**Files:**
- Create: `godot/motion_sample.gd`
- Create: `godot/motion_trajectory.gd`
- Create: `godot/ride_route.gd`
- Create: `godot/route_contract_tests.gd`

**Interfaces:** Produces the fixed trajectory and route interfaces above. It does not import `motion_kernel.gd`.

- [ ] **Step 1: Add a failing factory/immutability test.**

```gdscript
static func _test_factory(errors: PackedStringArray) -> void:
	var trajectory := _two_sample_trajectory()
	_expect(errors, trajectory.time_s == PackedFloat64Array([0.0, 1.0]), "factory retains native SI time")
	var positions := trajectory.position_m
	positions[0] = Vector3(99.0, 0.0, 0.0)
	_expect(errors, trajectory.position_m[0] == Vector3.ZERO, "packed channel mutation cannot alter trajectory")
	_expect(errors, trajectory.validation_errors().is_empty(), "valid trajectory validates")
```

`_two_sample_trajectory()` calls the exact dictionary factory with two entries in every required channel, including separate finite `drive_g` and total `longitudinal_g`, and one immutable test-local `DenseSampler` reporting one interval; no mutable trajectory field assignment occurs after `create`. Test both the allocating convenience call and reuse of one `MotionSample` through `sample_time_into`.

- [ ] **Step 2: Add failing structural cases.**

Assert: missing/unknown keys and one mismatched channel produce structured errors without indexing; two native samples with no sampler or a sampler reporting anything other than one interval fail; zero/one native sample permits no sampler; non-monotone time/distance and non-orthonormal frames fail.

- [ ] **Step 3: Run the focused suite and confirm missing scripts.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://route_contract_tests.gd'
```

- [ ] **Step 4: Implement immutable storage and factory copies.**

Use private packed fields matching the closed schema plus one `_dense_sampler`. `create` rejects missing/unknown keys and wrong packed-array types, copies every channel, and retains only an immutable-by-interface sampler that copied its own construction inputs. Singular read-only properties return packed values. Do not add `append_native`, `append_error_estimate`, per-step sampler objects, or a `MotionKernel` preload.

- [ ] **Step 5: Implement validation with an early count return.**

```gdscript
func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var native_count := _time_s.size()
	for channel in [_distance_m, _position_m, _position_dt_mps, _tangent, _tangent_dt_per_s, _rider_up, _rider_up_dt_per_s, _speed_mps, _speed_dt_mps2, _normal_g, _lateral_g, _longitudinal_g, _drive_g, _roll_rate_rad_s, _span_index]:
		if channel.size() != native_count:
			errors.append("trajectory native channel count differs")
	if not errors.is_empty():
		return errors
	var expected_intervals := maxi(0, native_count - 1)
	if expected_intervals == 0 and _dense_sampler != null:
		errors.append("trajectory dense sampler is unexpected")
	elif expected_intervals > 0 and (_dense_sampler == null or _dense_sampler.interval_count() != expected_intervals):
		errors.append("trajectory dense sampler interval count differs")
	if native_count == 0:
		return errors
	for i in native_count:
		if i > 0 and (_time_s[i] <= _time_s[i - 1] or _distance_m[i] <= _distance_m[i - 1]):
			errors.append("trajectory native coordinates are non-monotone at %d" % i)
		if _speed_mps[i] < 0.0 or (i > 0 and _speed_mps[i] <= 0.0):
			errors.append("trajectory speed is nonpositive after its initial instant at %d" % i)
		if not _position_m[i].is_finite() or absf(_tangent[i].length_squared() - 1.0) > 0.002 or absf(_rider_up[i].length_squared() - 1.0) > 0.002 or absf(_tangent[i].dot(_rider_up[i])) > 0.002:
			errors.append("trajectory frame is invalid at %d" % i)
	return errors
```

- [ ] **Step 6: Implement packed dense sampling and endpoint behavior.**

For one native sample, `sample_time_into`/`sample_distance_into` write that native sample. Otherwise they clamp and delegate to the single sampler, which binary-searches packed interval end bounds. The convenience methods create one `MotionSample`, delegate, and return it. `interval_error_estimate(i)` delegates to the sampler and rejects indices outside `0..native_count-2`.

- [ ] **Step 7: Implement `RideRoute` as immutable-by-copy final consumer data.**

Derive `length_m`, `duration_s`, and `bounds_m` from the trajectory. Validate trajectory, unique/ordered gesture IDs and whole-gesture windows, required fingerprints, resolution/counter dictionaries, sample-to-gesture indices, curvature samples, minimum-speed samples, propulsion IDs, boundaries, and tunnel gesture indices. Each gesture window also owns ordered `role_windows`; every role window carries a stable `role` plus inclusive native sample bounds and physical time/distance bounds, remains inside its whole gesture, and exactly covers it when concatenated. Adjacent roles may share only their single native seam sample and identical physical endpoint; their open interiors never overlap. `role_window` resolves only an exact `(gesture_id, role)` pair and returns empty on absence; it never falls back to the whole gesture. `RideRoute` does not expose the raw dictionary or legacy plan.

- [ ] **Step 8: Run import/smoke unchanged and commit.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://route_contract_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git add godot/motion_sample.gd godot/motion_trajectory.gd godot/ride_route.gd godot/route_contract_tests.gd
git commit -m "feat: define immutable ride route contract"
```

---

### Task 2: Atomic legacy adapter and consumer migration

**Files:**
- Create: `godot/legacy_route_adapter.gd`
- Modify: `godot/generator.gd`, `godot/verify.gd`, `godot/main.gd`, `godot/smoke.gd`, `godot/fidelity.gd`, `godot/fidelity_tests.gd`, `godot/fidelity_artifacts.gd`, `godot/fidelity_artifact_tests.gd`, `godot/_inspect.gd`, `godot/route_contract_tests.gd`

**Interfaces:** Produces `LegacyRouteAdapter.adapt(raw: Dictionary) -> RideRoute`; changes `RideGenerator.build(seed_value: int) -> RideRoute`; migrates every consumer before one commit.

- [ ] **Step 1: Add adapter characterization tests without changing the public generator yet.**

Call the current raw generator helper and `LegacyRouteAdapter.adapt`; assert exact equality for native position/time/distance/speed/frame/control values, section-to-gesture attribution, seed, terrain, and totals. Assert same seed twice gives identical adapted trajectory channels and stable gesture IDs.

- [ ] **Step 2: Implement one usable self-contained temporary packed sampler.**

```gdscript
class LegacyLinearDenseSampler extends MotionTrajectory.DenseSampler:
	var _channels: Dictionary

	func _init(channels: Dictionary) -> void:
		_channels = _copy_packed_channels(channels)

	func sample_time_into(query_time_s: float, out: MotionSample) -> void:
		var interval := _interval_for(_channels.time_s, query_time_s)
		_sample_interval_into(interval, inverse_lerp(_channels.time_s[interval], _channels.time_s[interval + 1], query_time_s), out)

	func sample_distance_into(query_distance_m: float, out: MotionSample) -> void:
		var interval := _interval_for(_channels.distance_m, query_distance_m)
		_sample_interval_into(interval, inverse_lerp(_channels.distance_m[interval], _channels.distance_m[interval + 1], query_distance_m), out)
```

The one sampler copies all legacy packed channels, binary-searches time/distance, and linearly interpolates position, derivatives, speed, authored controls, and total longitudinal telemetry; it normalizes tangent, orthogonalizes `rider_up`, and writes the exact `MotionSample` fields. It reports `native_count - 1` intervals and unavailable numerical-error estimates. It does not require a constructed trajectory and has no circular reference or sampling allocation when the caller reuses its output record.

- [ ] **Step 3: Build immutable native channels and one sampler.**

Convert current float arrays to the factory's exact packed types, derive position/tangent/up/speed time derivatives by deterministic one-sided/centered differences, preserve all three legacy total proper-G axes exactly, reconstruct finite `drive_g` from the legacy section's explicit propulsion/brake law, convert roll degrees/s to radians/s once, use legacy section index as temporary `span_index`, and create one sampler only when `native_count > 1`. A focused test re-evaluates representative unpowered, launch, and brake samples from the original formulas so the extra command channel is provenance, not an invented force. Preserve current curvature and section-only data under `RideRoute.verification_inputs`.

- [ ] **Step 4: Map legacy sections to deterministic gesture windows.**

Merge consecutive sections sharing the same non-empty element metadata; give windows `legacy/<three-digit-ordinal>/<kind>` gesture IDs, `legacy.unassigned` story slot, `legacy/<kind>` recipe ID, and native sample/time/distance bounds. Give each legacy gesture exactly one nested role window named `whole` with identical bounds; legacy data does not invent entry/core/exit phases. Map every sample, boundary, propulsion zone, and tunnel section to these windows. Mark fingerprints `legacy-generator@1`, `legacy-elements@1`, and `legacy-sequential-rng@1` so the adapter cannot be mistaken for the future compiler.

- [ ] **Step 5: Move the existing generator body unchanged to `_build_legacy` and return the final route.**

```gdscript
static func build(seed_value: int) -> RideRoute:
	return LegacyRouteAdapter.adapt(_build_legacy(seed_value))
```

The old body moves byte-for-byte into `_build_legacy(seed_value: int) -> Dictionary`; do not change constants, draw order, branches, sections, or repairs.

- [ ] **Step 6: Migrate verifier and viewer in the same worktree before running smoke.**

Verifier consumes `route.trajectory`, its three proper-g fields and `roll_rate_rad_s`, dense sampling, and `verification_inputs`; it no longer accepts separate terrain/tunnel arguments. Convert the 120°/s limit to radians. Viewer meshes use `position_m`, `tangent`, and `rider_up`, derive right/bank from the frame, use `length_m`/`duration_s`/`bounds_m`, gesture windows, and propulsion/tunnel verification data; HUD converts radians to degrees only for display.

- [ ] **Step 7: Migrate smoke, fidelity, fixtures, and inspector before committing.**

Generated-route smoke retains determinism, safety, physics, loads, arbitrary seeds, and three propulsion zones but stops reading `route.plan` or freezing legacy shape bands. Raw `elements.gd` template probes remain raw internal tests. Fidelity and artifact fixtures construct `MotionTrajectory`/`RideRoute` directly; fidelity, artifact rendering, and inspector group whole-gesture reports by `gesture_id`, resolve catalog selectors through the route's exact nested `role_windows`, and read singular trajectory channels. Re-run the evidence plan's moving non-grid 100 Hz resampling fixture through the dense-sampler path. `RideFidelityArtifacts` remains the sole artifact owner, with no raw-dictionary overload.

- [ ] **Step 8: Prove all consumers use the final contract and run the complete gate.**

```powershell
rg -n 'LegacyRouteAdapter|route\.plan|route\.(positions|tangents|ups|rights|curvatures|banks|speeds|times|distances|sections|section_indices|lsm_ids|tunnel_sections)' godot/main.gd godot/verify.gd godot/smoke.gd godot/fidelity.gd godot/fidelity_artifacts.gd godot/_inspect.gd
& $portableGodot --headless --path '.\godot' --script 'res://route_contract_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_artifact_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
```

Expected: search emits nothing and every command exits 0. Do not commit any subset of Steps 5–7.

- [ ] **Step 9: Commit the atomic green migration.**

```powershell
git add godot/legacy_route_adapter.gd godot/generator.gd godot/verify.gd godot/main.gd godot/smoke.gd godot/fidelity.gd godot/fidelity_tests.gd godot/fidelity_artifacts.gd godot/fidelity_artifact_tests.gd godot/_inspect.gd godot/route_contract_tests.gd
git commit -m "refactor: migrate runtime consumers to ride route"
```

---

### Task 3: Shared `RideCatalog` and canonical base configuration

**Files:**
- Create: `godot/ride_catalog.gd`
- Create: `godot/ride_config.gd`
- Create: `godot/ride_config_tests.gd`

**Interfaces:** Produces the fixed `RideCatalog` and `RideConfig` interfaces. `2026-08-09-default-ride-recipes.md` later fills the same catalog's physical recipe data.

- [ ] **Step 1: Add failing catalog ownership tests.**

Assert `PRESET_ID`, version 1, exact ordered story-slot IDs, recipe compatibility, optional-slot declarations, and the closed public-key registry exist in `RideCatalog.data`; returned data mutation cannot alter a second read; `validate()` is empty; `content_hash()` is 64 lowercase hex characters and stable.

- [ ] **Step 2: Define one catalog record.**

Declare `STORY_SLOT_ORDER`, `STORY_SLOTS`, and `RECIPES` as the single source-of-truth records. In this gate `RECIPES` contains only stable IDs and compatibility/capability skeletons; the default-recipe plan fills their physical records in the same member. `RideCatalog.data()` deep-copies and assembles `preset`, `story_slot_order`, `story_slots`, `recipes`, `recipe_compatibility`, and `key_registry`. The registry records value type, unit, legal scope, legal operator, domain, owner, and feasibility phase for `slot.recipe`, `slot.enabled`, `ride.duration_s`, `ride.peak_speed_mps`, `slot.structure_height_m`, `slot.intensity`, and `slot.airtime_character`. Do not create `RideConfigCatalog`; do not add physical profiles, force keys, or solver bounds in this gate.

- [ ] **Step 3: Implement immutable catalog reads and canonical hash.**

```gdscript
class_name RideCatalog
extends RefCounted
const PRESET_ID := "future-hybrid@1"
const PRESET := {} # populated with the version-1 preset record in this task
const STORY_SLOT_ORDER := []
const STORY_SLOTS := {}
const RECIPES := {}
const RECIPE_COMPATIBILITY := {}
const KEY_REGISTRY := {}

static func data() -> Dictionary:
	return {"preset":PRESET.duplicate(true), "story_slot_order":STORY_SLOT_ORDER.duplicate(),
		"story_slots":STORY_SLOTS.duplicate(true), "recipes":RECIPES.duplicate(true),
		"recipe_compatibility":RECIPE_COMPATIBILITY.duplicate(true), "key_registry":KEY_REGISTRY.duplicate(true)}

static func content_hash() -> String:
	return CanonicalData.sha256_text(CanonicalData.canonical_json(data()))
```

`RideCatalog` and `RideConfig` both consume the already-created `CanonicalData`; neither reimplements sorted-key JSON or SHA-256. `RideConfig.resolve` may preload `RideCatalog` without a cycle because `RideCatalog` does not depend on `RideConfig`.

- [ ] **Step 4: Add failing canonical base tests.**

Resolve reordered `{ride_config_version:1,preset:"future-hybrid@1",seed:42}` dictionaries and require identical canonical bytes/hash. Reject explicit null recursively, unknown top-level/sequence fields, unknown preset, invalid version, non-integer seed, and `sequence.order`.

- [ ] **Step 5: Delegate canonical bytes/hash and implement base resolution.**

Use `CanonicalData.canonical_json` and `CanonicalData.sha256_text` directly; do not add another `_canonical`, JSON serializer, or hashing helper. Base resolution discovers the highest-precedence preset, loads `RideCatalog.data().preset`, validates every layer, and returns `{ok, value, canonical_json, hash, errors}`.

- [ ] **Step 6: Run tests/import/smoke and commit.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://ride_config_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git add godot/ride_catalog.gd godot/ride_config.gd godot/ride_config_tests.gd
git commit -m "feat: add shared ride configuration catalog"
```

---

### Task 4: Overlay algebra, provenance, and conflicts

**Files:**
- Modify: `godot/ride_config.gd`
- Modify: `godot/ride_config_tests.gd`

**Interfaces:** Extends `RideConfig.resolve` with preset → file → ordered CLI overlay semantics and structured errors.

- [ ] **Step 1: Add table-driven overlay tests.**

Require omitted inheritance; scalar replacement; pin replacement by story-slot ID; last CLI layer wins; every scalar/pin/constraint retains `source_layer`, `source_rank`, and `source_position`; normalized pins sort by story-slot ID.

- [ ] **Step 2: Add constraint conflict tests.**

Reject duplicate IDs inside one layer; same-ID replacement that changes scope/key; two effective IDs for one `(scope,key)`; incompatible pins; disabling required slots; wrong type/domain/operator/scope; missing/negative tolerance. Required records canonicalize by `(scope,key,id)`. Preferred records sort highest source rank first, then original list position, then ID.

- [ ] **Step 3: Implement merge without reset or fallback.**

Validate each layer before merging. Merge stable IDs only after identity checks, then scan effective records for ambiguous `(scope,key)`. Return all structured errors with stage, code, config version, preset, seed, story slot, recipe/constraint ID, invariant, bounds/residuals, and message; return no partial normalized value on failure.

- [ ] **Step 4: Prove semantic determinism.**

Resolve the same layers twice and in dictionaries with reversed insertion order; require byte-identical canonical output. Also prove CLI argument order intentionally changes provenance/hash when precedence changes.

- [ ] **Step 5: Run green gates and commit.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://ride_config_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git add godot/ride_config.gd godot/ride_config_tests.gd
git commit -m "feat: implement ride config overlay algebra"
```

---

### Task 5: Immutable deterministic `CompiledRidePlan` and `RidePlanner`

**Files:**
- Create: `godot/compiled_ride_plan.gd`
- Create: `godot/ride_planner.gd`
- Create: `godot/ride_planner_tests.gd`

**Interfaces:** Produces `CompiledRidePlan.create(data: Dictionary) -> CompiledRidePlan`, defensive `to_dictionary`, `slot_decisions`, `resolution_report`, `canonical_json`, and `RidePlanner.compile(resolved_config) -> {ok, plan, errors}`.

- [ ] **Step 1: Add deterministic/immutability tests.**

Compile seed 42 twice and require byte-identical plans, ordered slot decisions, exact preset/config/catalog hashes, and defensive copies. Toggle an optional slot and require unrelated decisions unchanged. Pin a compatible recipe and require exact selection; incompatible pins and pin/required conflicts return planning errors with no partial plan.

- [ ] **Step 2: Implement stable named streams.**

Derive a positive 56-bit RNG seed from SHA-256 of `seed|ride-planner-streams@1|story-slot-id|decision-name`. Create one `RandomNumberGenerator` per named decision. Never pass RNG into `CompiledRidePlan`, compiler metadata, or legacy generation.

- [ ] **Step 3: Resolve required constraints before preferences.**

Apply pins and `slot.recipe`/`slot.enabled` required equalities against `RideCatalog` compatibility. Emit decisions `{story_slot_id,enabled,recipe_id,source,decision_stream}` in catalog story order. Planning-owned enum preferences are achieved only when the selected recipe's declared catalog choices contain the target; compilation-owned duration/speed/height preferences remain `unresolved` with no `achieved` field and reason `gesture compiler is outside the route/config foundation gate`.

- [ ] **Step 4: Persist exact foundation provenance.**

Plan data includes normalized-config hash, preset ID, seed, slot decisions, constraints, resolution report, decision provenance, `RideCatalog.content_hash()`, evidence-catalog hash sentinel `not-available:foundation-gate`, planner/compiler/kernel/decision-stream versions, and zero generation work counters. It contains no raw FVD keys or hand-authored geometry.

- [ ] **Step 5: Run twice, then import/smoke and commit.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://ride_planner_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://ride_planner_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
git add godot/compiled_ride_plan.gd godot/ride_planner.gd godot/ride_planner_tests.gd
git commit -m "feat: add deterministic ride planner"
```

---

### Task 6: Foundation acceptance and explicit adapter deletion gate

**Files:**
- Review: all Task 1–5 files and the four downstream plan contracts.
- Modify only if a reproduced failure requires it: the owning file and focused test.

- [ ] **Step 1: Run every foundation and retained consumer gate fresh.**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://route_contract_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://ride_config_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://ride_planner_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
```

- [ ] **Step 2: Confirm cross-plan type ownership.**

Search all plan documents and code: only `motion_trajectory.gd` defines `MotionTrajectory`; only `ride_route.gd` defines `RideRoute`; only `ride_catalog.gd` defines `RideCatalog`; no `RideConfigCatalog`, mutable trajectory append API, per-step dense object, or `MotionKernel` reference exists in `motion_trajectory.gd`. `2026-08-09-time-domain-motion-kernel.md` supplies one packed Hermite sampler through `MotionTrajectory.create`; `2026-08-09-default-ride-recipes.md` extends `RideCatalog.data` physical recipe records and makes `RideCompiler` emit `RideRoute`; the evidence and runtime plans consume the same route/catalog.

- [ ] **Step 3: Confirm adapter isolation.**

```powershell
rg -n 'LegacyRouteAdapter|_build_legacy' godot
```

Expected: only `legacy_route_adapter.gd`, `generator.gd`, and focused characterization tests. No consumer imports it.

- [ ] **Step 4: Record the deletion gate in review notes.**

The runtime-cutover plan deletes `legacy_route_adapter.gd`, `_build_legacy`, the adapter linear sampler/fingerprints, and legacy `FVD`/`GRADE`/`CLOSURE`/repair execution only after: the kernel supplies the authoritative packed Hermite sampler through the fixed factory; complete recipes compile the default plan; `RideCompiler.compile` returns a passing `RideRoute`; viewer/verifier/smoke/fidelity/inspector pass unchanged; exactly one full-resolution integration is recorded; and no runtime switch selects legacy geometry.

- [ ] **Step 5: Inspect final diff and commit review fixes only when needed.**

```powershell
git diff --check
git status --short
git diff --stat
```

If review fixes changed files, rerun Step 1 and commit only those verified fixes with `git commit -m "test: verify route config foundation"`. Do not create an empty commit.
