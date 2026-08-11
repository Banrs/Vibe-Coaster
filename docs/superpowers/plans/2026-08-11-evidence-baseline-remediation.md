# Evidence Baseline Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`)
> syntax for tracking.

**Goal:** Correct and simplify the diagnostic evidence baseline introduced at `6d5716e` so it is a
truthful, reproducible prerequisite for the route-configuration foundation, without changing
generated rides.

**Architecture:** `RideFidelity` remains the sole semantic catalog authority, `Verify` composes the
shared physical policy, `RideFidelityArtifacts` validates and publishes one manifest-last canonical
pack, and `_inspect.gd` only orchestrates and prints diagnostics. Work stays in the existing files;
semantic deletion must outweigh new correctness code, and no compatibility layer or cosmetic split
is permitted.

**Tech Stack:** Godot 4.7.1, typed GDScript, GitHub Actions on Ubuntu, authenticated Git and the
GitHub connector for orchestration; `godot/_verify_fidelity_pack.gd` is temporary acceptance-only
GDScript.

## Global Constraints

- Define `$remediationBase = "6d5716e246eb69304becd21d4c17b5aa3e7eb5c2"`; it is the semantic,
  production-numstat, and permanent-workflow comparison base. Start from the clean commit containing
  this plan and separately record that plan checkpoint with `git rev-parse HEAD` before Task 1.
- Do not run a local Godot process. Import, smoke, viewer, RED, GREEN, and full audits run only in
  GitHub Actions because a prior local launch crashed the workstation.
- Preserve every generator value, same-seed route array, smoke threshold, seed, viewer behavior, and
  permanent CI command. Preserve diagnostic formulas except Task 6's removal of the `_stats` radius
  cap; that projection must report exact finite reciprocals or an explicit unbounded value.
- Fidelity `under` and `over` findings remain diagnostic exit 0. Catalog, generation, physical,
  render, reopen, and manifest failures remain operational exit 1.
- Do not promote evidence, invent a POV alignment, alter force or geometry targets, smooth geometry,
  change an authored or generated route radius, add hidden propulsion, or start Plan 2 route types in
  this plan.
- Do not add a schema framework, dependency-injection seam, writer abstraction, registry, fallback,
  alias copy, compatibility shim, or production file split.
- The final diff across touched production `.gd` files must be net-negative. Line packing, moving
  code, deleting independent coverage, and fixture-to-oracle coupling do not count as reduction.
- The mechanical production set is `godot/fidelity_artifacts.gd`, `godot/verify.gd`,
  `godot/smoke.gd`, and `godot/_inspect.gd`. Test files are reviewed separately and never counted as
  production deletion.
- Keep `_run_audit`'s one-build-per-seed callable seam and the fleet order exactly:
  `11, 42, 20260809, 1, 3, 7, 99, 256, 555, 1234, 4096, 31337, 77777, 123456, 20250101`.

## File Responsibility Map

- `godot/fidelity.gd`: unchanged semantic catalog, measurement, reconstruction, and comparison owner.
- `godot/fidelity_artifacts.gd`: simplify in place; report projection, route-bound render jobs,
  camera clipping, verified publication, issue traceability.
- `godot/fidelity_artifact_tests.gd`: artifact-boundary RED/GREEN tests and independent deterministic
  oracles; delete semantic catalog negatives already owned by `fidelity_tests.gd`.
- `godot/verify.gd`: one pure composition of existing physical validators.
- `godot/smoke.gd`: schedule deep versus sweep policy and reuse returned deep analysis.
- `godot/_inspect.gd`: invalidate at run start, apply shared physical policy, orchestrate one build,
  print canonical diagnostics without duplicate renders.
- `README.md`, `CLAUDE.md`, `docs/ISSUES.md`, and
  `docs/superpowers/plans/2026-08-09-evidence-audit-baseline.md`: truthful operator and closeout text.
- `.github/workflows/ci.yml` and `godot/_verify_fidelity_pack.gd`: temporary final-acceptance changes;
  both return to their pre-task state before handoff.

## GitHub-Only TDD Protocol

Each behavior-changing slice uses a test-only RED commit, a reviewed production GREEN commit, and
the unchanged PR workflow unless Task 7 explicitly says otherwise. Task 6 adds one focused
diagnostic-radius RED before deleting duplicate renders; its deletion characterization remains a
recorded static check rather than a source-spelling unit test. After each push, select only the run
whose head SHA equals the local commit; never treat an older green run as evidence.

Push with authenticated Git and prove the remote branch points at the exact commit:

```powershell
$taskSha = (git rev-parse HEAD).Trim()
git push github HEAD:codex/fvd-first-generator
$remoteSha = ((git ls-remote github refs/heads/codex/fvd-first-generator) -split "`t")[0]
if ($remoteSha -ne $taskSha) { throw "Remote branch is not at $taskSha" }
```

Then use these authenticated GitHub connector calls, with no `gh` CLI fallback:

1. Call `github_get_pr_info` with
   `{"repository_full_name":"Banrs/Vibe-Coaster","pr_number":1}` and require an open PR whose base
   is `main`, head is `codex/fvd-first-generator`, and `head_sha` equals `$taskSha`.
2. Record a wall-clock deadline fifteen minutes from the first poll, then call
   `github_fetch_commit_workflow_runs({"repo_full_name":"Banrs/Vibe-Coaster",
   "commit_sha":$taskSha})`. Repeat every five seconds while empty/in-progress, stopping before a
   call when the wall clock reaches that deadline; connector latency never extends the deadline.
   The connector
   request is SHA-filtered; if retries exist, select the `CI` run with the greatest `run_number`.
3. Call `github_fetch_workflow_run_jobs({"repo_full_name":"Banrs/Vibe-Coaster",
   "run_id":run.id})` and select exactly one job
   named `godot`. Call `github_fetch_workflow_job_steps` with that job ID.
4. For RED, require `Import project` to be completed successfully before the intended later step
   fails. Call `github_fetch_workflow_job_logs` for the failed `godot` job and require only the named
   focused assertion or missing API; parser, type-inference, import, timeout, and unrelated smoke
   failures invalidate the RED.
5. For GREEN, require the exact `godot` job to be completed with conclusion `success`; because it is
   the unchanged permanent job, this proves import, `smoke.gd`, and viewer runtime all passed.

Every task then receives a fresh spec review followed by a lean/code-quality review.

---

### Task 1: Make Catalog Validation Single-Owner

**Files:**
- Modify: `godot/fidelity_artifacts.gd:61-655`
- Test: `godot/fidelity_artifact_tests.gd:22-44,455-845`

**Interfaces:**
- Consumes: `RideFidelity.validate_catalog(catalog: Dictionary) -> PackedStringArray`.
- Produces: unchanged `RideFidelityArtifacts.build_report(...) -> Dictionary`; `_catalog_context`
  projects an already-valid catalog and owns no schema-v2 semantics.

- [ ] **Step 1: Make the artifact fixture valid under the real catalog authority.** Add these exact
  records to `_valid_catalog`; retain existing IDs, hashes, prompt records, gap record, and compiled
  anchor unless replaced below:

```gdscript
"selectors": {"selector.loop": {
	"legacy_anchor": {"phase": "act-one", "kind": "loop", "occurrence": 0, "window_role": "whole"},
	"compiled_anchor": {"story_slot_id": "act1.loop", "window_role": "core"},
}},
"transforms": {"observed.identity@1": {
	"kind": "identity", "factor": 1.0,
	"formula": "target_value = observed_value", "approval": "identity; no transform",
}},
```

  Add to `source.raw`: `initial_state: "executable"`, contribution `quantitative force targets`,
  axis `normal_g`, prerequisite `raw artifact and metadata retained`, recording ID `fixture-raw`,
  date `2026-08-09`, context `artifact test fixture`, row `row-02`, device `fixture sensor`, sample
  rate `100.0`, mapping `{"sensor_z":"normal_g"}`, reliability `fixture`, and empty caveats. Remove
  its diagnostic pair and fallback citations because raw acquisition forbids them. Change
  `landmark.point` to window `[1.0, 1.5]`.

  Add to `youtube.unaligned`: observation-only initial state, qualitative-review contribution, empty
  axes, prerequisite `raw sampled telemetry required for targets`, `raw_fetch_unavailable`, URL
  `https://example.invalid/video`, date `2026-08-09`, fixture context, unknown row/device, null sample
  rate, empty axis map, observation-only reliability, processing `metadata only`, caveat
  `sample rate unknown`, the existing metadata/review pairs, diagnostic pair using digest
  `"c".repeat(64)`, and this fallback citation:

```gdscript
{"document": "docs/TELEMETRY.md", "section_id": "fixture", "line_anchor": "fixture",
 "columns_used": ["time"], "source_windows_used": [[3.5, 4.5]]}
```

  Extend `_aligned_observation` with executable state, `source_window_id`, source axis `sensor_z`,
  mapped axis `normal_g`, row `row-02`, duration `0.5` for `landmark.point` else `1.0`, metric
  `normal_peak_positive`, null hold, raw range `[1.0,1.5]`, identity transform, high fixture
  confidence, empty corroboration, and alignment rationale `fixture`. Extend `target.load` with loads
  dimension, the same metric/hold/ranges, and
  `aggregation: {"row":"maximum", "beat":"maximum", "seed":"median"}`.

- [ ] **Step 2: Add the focused RED.** Load `FIDELITY_PATH` in `run`, call this test, redirect the two
  fallback-citation alias mutations to `youtube.unaligned`, and update only projection leaves changed
  by the valid fixture (catalog digest, snapshots, and the point-to-window source time):

```gdscript
static func _test_authoritative_catalog_validation(
	artifacts: Script, fidelity: Script, errors: PackedStringArray
) -> void:
	_expect(errors, fidelity.validate_catalog(_valid_catalog()).is_empty(),
		"artifact fixture is valid under RideFidelity")
	var fixture := _valid_fixture()
	fixture.catalog.transforms = []
	var report := _build(artifacts, fixture)
	_expect(errors, report.get("status") == "invalid-input"
		and "\n".join(report.get("errors", [])).contains("transforms"),
		"artifact reports delegate semantic catalog validation")
```

  In `_test_committed_catalog`, replace the ID-only POV-gap comparison with this association oracle.
  It derives the expected source/landmark relation directly from the authoritative catalog, fixes the
  contractual reason, sorts both sides, and therefore fails if two sources' landmark lists are
  rotated while their gap IDs remain unchanged:

```gdscript
var expected_gaps := []
for source_id in fixture.catalog.sources:
	var source: Dictionary = fixture.catalog.sources[source_id]
	if not str(source_id).begins_with("youtube.") or source.windows.is_empty():
		continue
	var landmark_ids := PackedStringArray()
	for window in source.windows:
		landmark_ids.append(str(window.id))
	landmark_ids.sort()
	expected_gaps.append([
		"%s/alignment-not-present" % source_id,
		str(source_id),
		"alignment-not-present",
		Array(landmark_ids),
	])
expected_gaps.sort_custom(func(a: Array, b: Array): return str(a[0]) < str(b[0]))
var actual_gaps := []
for gap in report.get("pov_map", {}).get("gaps", []):
	var landmark_ids := PackedStringArray()
	for landmark_id in gap.get("source_landmark_ids", []):
		landmark_ids.append(str(landmark_id))
	landmark_ids.sort()
	actual_gaps.append([
		str(gap.get("id", "")),
		str(gap.get("source_id", "")),
		str(gap.get("reason", "")),
		Array(landmark_ids),
	])
actual_gaps.sort_custom(func(a: Array, b: Array): return str(a[0]) < str(b[0]))
_expect(errors, actual_gaps == expected_gaps,
	"committed no-alignment gaps preserve exact source/landmark associations")
```

- [ ] **Step 3: Commit and observe RED on GitHub.** Commit as
  `test: expose duplicate artifact catalog validation`. The valid-fixture assertion must pass; the
  report must wrongly accept `transforms = []`, proving the shadow validator gap.

- [ ] **Step 4: Add exactly one semantic call before projection.** In `build_report`, reject a
  non-Dictionary before the typed call, append the authority's errors, and return the existing sorted
  invalid shape before `_catalog_context`:

```gdscript
if not catalog is Dictionary:
	errors.append("artifact_report: catalog must be a Dictionary")
else:
	for error in _FIDELITY.validate_catalog(catalog):
		errors.append("artifact_report: %s" % error)
if not errors.is_empty():
	return _invalid(errors)
```

  Do not call `validate_catalog_artifacts` here; that remains the inspector's file/digest preflight.

- [ ] **Step 5: Delete shadow semantics and duplicate tests.** Reduce `_catalog_context` and
  `_source_projection` to direct projections from valid dictionaries. Delete `_dictionary_records`,
  `_validated_source_ids`, `_validated_issues`, and catalog schema/type/link/promotion/provenance
  checks. Keep `_required_string` for measurement validation, `_center_row_resolution`, `_source_time`,
  checklist completeness, traceability completeness, canonical JSON safety, and path collisions.
  Delete artifact-suite negative cases for catalog identity/container/source windows/source-ID
  arrays/compiled anchors/alignment shapes/generated anchors/projection leaves/source-target-prompt-
  gap links/issue ranges/aligned link resolution. Keep canonical non-finite, checklist, traceability,
  center-row/window, path collision, alias, successful report, and committed-catalog tests.

- [ ] **Step 6: Verify and commit GREEN.** Require the unchanged GitHub workflow to pass, confirm
  `rg -n '_dictionary_records|_validated_source_ids|_validated_issues' godot/fidelity_artifacts.gd`
  is empty, confirm one `validate_catalog(catalog)` call in the artifact file, and commit as
  `refactor: delegate fidelity catalog validation`.

---

### Task 2A: Preflight Every Render Input and Bind Route Beats

**Files:**
- Modify: `godot/fidelity_artifacts.gd:1109-1296`
- Test: `godot/fidelity_artifact_tests.gd:101-247,1195-1296`

**Interfaces:**
- Preserves `write_pack(output_dir: String, report: Dictionary, routes_by_seed: Dictionary)
  -> PackedStringArray`; no new public type or validator is introduced.

- [ ] **Step 1: Make pack fixtures route-truthful.** Strengthen `_pack_fixture` and `_pack_route`
  so seed, length, duration, kind, native indices, route-derived distance span, and center-row
  windows agree with `RideFidelity.element_bands(route, 0.0)`.

- [ ] **Step 2: Add request, route, and beat-binding RED tables.** Require exact request keys/types,
  known kind, canonical seed/path, no absolute/URI/backslash/parent path, no collisions, finite POV
  time, and nonempty raw beat ID. Use seed 11 to test fewer than three samples, missing/wrong packed
  arrays, unequal counts, non-finite values, non-increasing time/distance, inconsistent seed/length/
  duration, and malformed sections without reaching an assertion. Use seed 42 to mutate, one at a
  time, the route section kind/end index, report beat ID/kind/start/end distance, zero-row distance/
  time window, and POV midpoint. Add two non-composite bands whose distinct phase text slugifies to
  the same phase and whose kind/ordinal therefore produce the same raw beat ID; reject the duplicate
  before inserting either band into a lookup:

```gdscript
var routes := _pack_routes()
routes[42].sections[0].end_index = 39
_expect_contains(errors, Array(artifacts.write_pack(directory, report, routes)),
	"beat", "element rendering binds the report beat to the retained route")
```

- [ ] **Step 3: Commit and observe RED on GitHub.** Commit as
  `test: expose unbound fidelity render inputs`. Accept only the focused preflight/binding failures
  after import; an assertion abort is valid RED evidence only when the log names the intended
  malformed route fixture.

- [ ] **Step 4: Preflight before any ordinary write.** Use private single-purpose helpers, not a
  framework. Validate every request's schema/path and every referenced route's required packed
  channels, equal count at least three, finite frames/scalars, nonnegative speed with zero permitted
  only at the route's initial sample, strictly increasing
  time/distance, positive finite length/duration consistent with endpoints, seed match, terrain
  dictionary, and ordered section bounds. For element/POV routes, call
  `element_bands(route, 0.0)` once, index unique raw IDs, and require report/request ID, kind,
  native bounds, route distance/time window, and POV midpoint parity. Return resolved
  `first`/`last` indices to the existing writer; copied report distances are never render authority.
  Do not call `Verify.validate_structure` here: it is an assertion-bearing >1,000-sample physical
  gate with per-section minimum-speed policy, while this public artifact boundary must reject
  malformed Variants safely and permits the Plan 2 initial zero-speed sample. Mirror only the narrow
  shape facts that the render helpers require.

- [ ] **Step 5: Delete late authority and commit GREEN.** Delete the report-owned `beats` lookup,
  copied-span `_sample_index` authority, and duplicate late request validation. Preserve the current
  publication behavior for Task 2B. Require all request/route mutation tests and permanent CI green,
  then commit as `refactor: preflight fidelity render inputs`.

---

### Task 2B: Invalidate Stale Success Before Work

**Files:**
- Modify: `godot/fidelity_artifacts.gd:106-130,1109-1145`
- Test: `godot/fidelity_artifact_tests.gd:101-247,1195-1296`
- Modify caller: `godot/_inspect.gd:34-62,126-135`

**Interfaces:**
- Produces `RideFidelityArtifacts.invalidate_pack(root: String) -> PackedStringArray`.
- Preserves the public `write_pack` signature and Task 2A's complete preflight.

- [ ] **Step 1: Add stale-success RED cases.** Seed a valid pack, add
  `sentinel.keep`, then require `invalidate_pack` to reject `""` and `"relative/out"`, accept and
  create a `user://` root, accept the same root with a trailing separator without rewriting it,
  remove only `manifest.json`, preserve the sentinel, and be idempotent. Explicitly reject OS
  filesystem volume roots such as `/` and `C:/`. Before invalid-report and Task 2A preflight
  failures, restore a stale manifest and assert it disappears.

- [ ] **Step 2: Commit and observe RED on GitHub.** Commit as
  `test: expose stale fidelity success markers`; expect only missing invalidation and stale-marker
  assertions.

- [ ] **Step 3: Implement early invalidation and caller ordering.** Implement only this public helper:

```gdscript
static func invalidate_pack(root_value: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var root := root_value
	var is_writable_absolute := root.is_absolute_path() or root.begins_with("user://")
	if root.is_empty() or not is_writable_absolute:
		return PackedStringArray(["artifact_write: artifact root must be a nonempty absolute path"])
	var global_root := ProjectSettings.globalize_path(root).replace("\\", "/").simplify_path()
	var is_volume_root := global_root == "/" or (
		global_root.length() >= 2 and global_root[1] == ":"
		and global_root.substr(2).replace("/", "").is_empty()
	)
	if is_volume_root:
		return PackedStringArray(["artifact_write: artifact root cannot be a filesystem volume root"])
	DirAccess.make_dir_recursive_absolute(root)
	if not DirAccess.dir_exists_absolute(root):
		return PackedStringArray(["artifact_write: cannot create artifact root '%s'" % root])
	var manifest := root.path_join("manifest.json")
	if FileAccess.file_exists(manifest) and DirAccess.remove_absolute(manifest) != OK:
		errors.append("artifact_write: cannot remove stale manifest '%s'" % manifest)
	if FileAccess.file_exists(manifest):
		errors.append("artifact_write: stale manifest remains '%s'" % manifest)
	return errors
```

  In the inspector, run root probing, invalidation, and catalog validation in that order before any
  seed build. `write_pack` invokes the same helper before validating its report. Task 7 proves the
  inspector ordering through a real negative process, not a private-source-spelling test.

- [ ] **Step 4: Verify and commit GREEN.** Require all root/API and stale invalid-report/preflight
  cases plus permanent CI green. Commit as `feat: invalidate stale fidelity packs`.

---

### Task 2C: Publish One Reopened, Manifest-Last Pack

**Files:**
- Modify: `godot/fidelity_artifacts.gd:106-130,1109-1296`
- Test: `godot/fidelity_artifact_tests.gd:101-247,1195-1296`

**Interfaces:**
- Preserves Task 2A preflight, Task 2B invalidation, and the public `write_pack` signature.

- [ ] **Step 1: Strengthen publication characterization.** Force an ordinary render-job failure by
  replacing one expected PNG file with a directory, and force final-manifest failure with a nonempty
  directory named `manifest.json`; both return `artifact_write:`, leave no marker file, and preserve
  unrelated sentinels. Keep exact pack-file equality and two-write determinism. Compare checked text
  as raw bytes:

```gdscript
var expected := "{\"utf8\":\"λ\"}\n".to_utf8_buffer()
_expect(errors, artifacts.write_text_checked(path, expected.get_string_from_utf8()).is_empty()
	and FileAccess.get_file_as_bytes(path) == expected,
	"checked text reopens as exact UTF-8 bytes")
```

  These characterize observable safety around an internal simplification; they may already pass.
  Record the pre-refactor green result rather than inventing a production hook to force RED.

- [ ] **Step 2: Sort, stream, and verify deterministic jobs.** After Task 2A preflight, prepare only
  lightweight fixed-text and render specifications; never hold the complete image pack in memory.
  Each internal spec has exact keys `path, artifact_kind, seed, beat_id`; fixed text also carries
  `text_content`. Sort by forward-slash relative path, reject rather than sanitize any bad path, then
  render/write/reopen one spec at a time and release each image. Calculate a channel bundle once; its
  Markdown is projected only after that bundle's canonical legend JSON has reopened.

  Change `write_text_checked` to compare reopened bytes with `content.to_utf8_buffer()`. Reopen
  every job immediately, compare text exactly, decode PNG bytes and verify dimensions, and calculate
  size/SHA from those same bytes. Write and byte-reverify the self-excluding manifest last. On every
  error, call `invalidate_pack(root)` before returning.

- [ ] **Step 3: Delete obsolete bookkeeping and commit.** Delete the second-pass
  `_write`/`_manifest_files` bookkeeping made obsolete by verified jobs. Preserve public image and
  Markdown helpers. Require permanent CI green, no stale marker after every failure class, exact pack
  file equality, and report the slice's production delta as informational. Commit as
  `refactor: publish one checked fidelity pack`.

---

### Task 3: Clip Diagnostic POV Segments in Camera Depth

**Files:**
- Modify: `godot/fidelity_artifacts.gd:991-1067`
- Test: `godot/fidelity_artifact_tests.gd:300-377`

**Interfaces:**
- Produces private `_clip_to_depth(from: Vector3, to: Vector3) -> PackedVector3Array`.
- Preserves 1440×900, vertical FOV 72 degrees, near 0.08 m, far 5000 m, eye offset 0.35 m.

- [ ] **Step 1: Add four direct camera-space RED cases.** Add
  `CONTRACT_POV_FAR_M := 5000.0`, assert the private callable exists, then test wholly before near
  `(0.02,0.04)`, crossing near `(0.04,1.0)`, wholly beyond far `(6000,7000)`, and crossing far
  `(4000,6000)` with varying x/y. Depth is `-z`; empty/outside and clipped endpoint depths must be
  exact within `0.0001`. Keep every existing rendered pixel assertion and add no PNG hash.

- [ ] **Step 2: Commit and observe RED on GitHub.** Commit as
  `test: expose incorrect POV far clipping`; expect only the missing depth helper/far behavior.

- [ ] **Step 3: Replace radius filtering with interval clipping.** `_clip_to_depth` must reject a
  segment wholly below near or wholly above far; interpolate the outside endpoint to near, then far,
  and return endpoints in original order. `_draw_projected` becomes:

```gdscript
var clipped := _clip_to_depth(previous, local)
if not clipped.is_empty():
	var segment := _clipped_to_frame(_projected(clipped[0]), _projected(clipped[1]), bounds)
	if not segment.is_empty():
		_draw_line(image, segment[0], segment[1], color, bounds)
```

  Delete `_clipped_to_near` and `minf(from.length(), to.length()) <= _POV_FAR_M`.

- [ ] **Step 4: Verify and commit GREEN.** Require all four depth cases and existing camera pixels to
  pass remotely. Commit as `fix: clip fidelity POV by camera depth`.

---

### Task 4: Share One Physical-Consistency Policy

**Files:**
- Modify: `godot/verify.gd:394-505`
- Test/Modify: `godot/smoke.gd:94-226,535-607`
- Modify: `godot/_inspect.gd:91-105`
- Test: `godot/fidelity_artifact_tests.gd:48-99`

**Interfaces:**
- Produces `Verify.validate_physical_consistency(route: Dictionary, row_offsets: Array,
  include_loads: bool) -> Dictionary` with exactly `issues` and `analysis` keys.
- Produces private inspector formatter `_physical_issue_errors(catalog_version, seed, issues)` so
  the operational mapping is directly testable without generator or validator injection.
- Keeps the existing `_run_audit(seeds, build_route, measure_route, compare_fleet)` signature and
  builder seam, but changes its implementation to return `operational_errors` and validate before
  measurement or route retention.

- [ ] **Step 1: Add focused policy RED tests inside `_verify_errors`.** Use an all-required-array
  empty route to prove structure failure returns only `route has too few samples`, empty analysis,
  and never reads terrain. For a valid `_mini_route`, attach a flat terrain safely below the track
  and `tunnel_sections = []`; require repeated results equal. Raise the terrain to intersect rail and
  require `terrain intersects track` with empty analysis. On a fresh valid route, fill `normal_g`
  with `20.0`, set `include_loads = true`, and require nonempty analysis plus
  `exceeds raw normal-G limits`.

  Use this exact flat fixture and shift the mini-route positions up 100 m before validation; pass
  `height = 0.0` for the clean/load cases and `height = 200.0` for clearance failure:

```gdscript
func _flat_validation_terrain(height: float) -> Dictionary:
	return {
		"relief": height, "face_height": 0.0, "apron_height": height,
		"edge_normal": Vector2.ZERO, "edge_offset": -1.0,
		"apron_width": 1.0, "face_width": 1.0,
		"wobble_amplitude": 0.0, "wobble_wavelength": 1.0,
		"detail_amplitude": 0.0, "noise_seed": 0,
	}
```

- [ ] **Step 2: Commit and observe RED on GitHub.** Commit as
  `test: define shared route physical validation`; expect the missing method only.

- [ ] **Step 3: Compose existing validators without changing them.** Add:

```gdscript
static func validate_physical_consistency(
	route: Dictionary, row_offsets: Array, include_loads: bool
) -> Dictionary:
	var issues := PackedStringArray()
	validate_structure(route, issues)
	if not issues.is_empty():
		return {"issues": issues, "analysis": {}}
	validate_seams(route, issues)
	validate_clearance(route, route.terrain, route.tunnel_sections, issues)
	validate_self_clearance(route, issues)
	var analysis := {}
	if include_loads:
		analysis = analyze(route, row_offsets)
		validate_loads(analysis, issues)
	return {"issues": issues, "analysis": analysis}
```

- [ ] **Step 4: Add the inspector-orchestration RED fixture.** Replace the fake `{"seed": seed}`
  routes in `_test_one_build_per_seed` with `_audit_route(seed)`, retain the existing fleet/count/order
  assertions, and add `_test_invalid_route_blocks_audit`. This fixture is structurally valid under
  every `Verify` array and frame requirement, contains one section, uses low flat terrain and no
  tunnels, and has exactly 1,001 samples:

```gdscript
static func _audit_terrain(height: float) -> Dictionary:
	return {
		"relief": height, "face_height": 0.0, "apron_height": height,
		"edge_normal": Vector2.ZERO, "edge_offset": -1.0,
		"apron_width": 1.0, "face_width": 1.0,
		"wobble_amplitude": 0.0, "wobble_wavelength": 1.0,
		"detail_amplitude": 0.0, "noise_seed": 0,
	}


static func _audit_vectors(value: Vector3) -> PackedVector3Array:
	var values := PackedVector3Array()
	values.resize(1001)
	values.fill(value)
	return values


static func _audit_floats(value: float) -> PackedFloat32Array:
	var values := PackedFloat32Array()
	values.resize(1001)
	values.fill(value)
	return values


static func _audit_ints(value: int) -> PackedInt32Array:
	var values := PackedInt32Array()
	values.resize(1001)
	values.fill(value)
	return values


static func _audit_route(seed_value: int) -> Dictionary:
	var route: Dictionary = {
		"seed": seed_value, "positions": _audit_vectors(Vector3.ZERO),
		"tangents": _audit_vectors(Vector3.RIGHT), "ups": _audit_vectors(Vector3.UP),
		"rights": _audit_vectors(Vector3.RIGHT.cross(Vector3.UP)),
		"curvatures": _audit_vectors(Vector3.ZERO), "banks": _audit_floats(0.0),
		"speeds": _audit_floats(10.0), "normal_g": _audit_floats(1.0),
		"lateral_g": _audit_floats(0.0), "longitudinal_g": _audit_floats(0.0),
		"roll_rates": _audit_floats(0.0), "distances": _audit_floats(0.0),
		"times": _audit_floats(0.0), "section_indices": _audit_ints(0),
		"lsm_ids": _audit_ints(0),
		"sections": [{
			"name": "Audit straight", "kind": "GRADE", "minimum_speed": 4.0,
			"start_index": 0, "end_index": 1000,
			"start_distance": 0.0, "end_distance": 100.0,
			"start_time": 0.0, "end_time": 10.0,
			"entry_speed": 10.0, "exit_speed": 10.0, "element": {},
		}],
		"terrain": _audit_terrain(0.0), "tunnel_sections": [],
		"length": 100.0, "duration": 10.0,
	}
	for index in 1001:
		route.positions[index] = Vector3(index * 0.1, 100.0, 0.0)
		route.distances[index] = index * 0.1
		route.times[index] = index * 0.01
	return route
```

  Use the real validator through `_run_audit`; do not add a validator callable:

```gdscript
static func _test_invalid_route_blocks_audit(
	runner: Callable, errors: PackedStringArray
) -> void:
	var calls := {"build": {}, "measure": [], "compare": 0}
	var build := func(seed_value: int) -> Dictionary:
		calls.build[seed_value] = int(calls.build.get(seed_value, 0)) + 1
		var route := _audit_route(seed_value)
		if seed_value == 42:
			route.terrain = _audit_terrain(100.0)
		return route
	var measure := func(route: Dictionary) -> Dictionary:
		calls.measure.append(route.seed)
		return {"seed": route.seed}
	var compare := func(measurements: Array) -> Dictionary:
		calls.compare += 1
		return {"fleet": measurements}
	var result: Dictionary = runner.call([11, 42], build, measure, compare)
	var expected_errors := PackedStringArray([
		"physical_consistency: catalog 2026-08-10.evidence-baseline.2 seed 42: " +
		"terrain intersects track near 'Audit straight' at (0, 0): -1.55 m clearance",
	])
	_expect(errors, calls.build == {11: 1, 42: 1},
		"physical failure does not change one-build counts")
	_expect(errors, calls.measure == [11], "the failed seed is not measured")
	_expect(errors, calls.compare == 0 and result.comparison == {},
		"fleet comparison is skipped after an operational error")
	_expect(errors, result.routes_by_seed.size() == 1
		and result.routes_by_seed.has(11) and not result.routes_by_seed.has(42),
		"the failed deep route is not retained")
	_expect(errors, result.generation_counts == {"11": 1, "42": 1},
		"failed validation still records exact generation counts")
	_expect(errors, result.operational_errors == expected_errors,
		"physical-consistency errors retain exact catalog/seed/message formatting")

	var missing_measures := []
	var missing_compares := []
	var missing: Dictionary = runner.call(
		[7],
		func(seed_value: int) -> Dictionary: return {"seed": seed_value},
		func(route: Dictionary) -> Dictionary:
			missing_measures.append(route.seed)
			return {"seed": route.seed},
		func(measurements: Array) -> Dictionary:
			missing_compares.append(measurements)
			return {"fleet": measurements}
	)
	_expect(errors, missing.operational_errors == PackedStringArray([
		"generation: catalog 2026-08-10.evidence-baseline.2 seed 7 produced no route",
	]), "the orchestration boundary owns missing-route failure")
	_expect(errors, missing_measures.is_empty() and missing_compares.is_empty(),
		"a missing route is neither measured nor compared")
```

  Keep `_test_one_build_per_seed`'s existing assertions and make these exact edits: return
  `_audit_route(seed_value)` from its build spy; replace the whole-dictionary `expected_routes`
  assertion with the retained-seed assertion below; and add the empty-error assertion after the
  comparison assertion. This retains the full fleet/count/type/order coverage without duplicating
  the unchanged function in this plan:

```gdscript
_expect(errors, report.get("operational_errors") == PackedStringArray(),
	"the valid audit fleet has no operational errors")
var retained_seeds: Array = report.get("routes_by_seed", {}).keys()
retained_seeds.sort()
var expected_retained := DEEP_REVIEW_SEEDS.duplicate()
expected_retained.sort()
_expect(errors, retained_seeds == expected_retained,
	"only valid deep-review seeds retain their already-built routes")
```

  The end of `_test_audit_fleet` becomes:

```gdscript
_test_one_build_per_seed(Callable(inspect, "_run_audit"), errors)
_test_invalid_route_blocks_audit(Callable(inspect, "_run_audit"), errors)
```

- [ ] **Step 5: Commit and observe the orchestration RED on GitHub.** Commit as
  `test: reject physically invalid audit routes`. Import must pass; the focused failures must show
  that seed 42 was measured/retained, comparison ran, and `operational_errors` is absent. The
  missing-route case must also show measurement/comparison occurred. No parser or unrelated failure
  is an acceptable RED.

- [ ] **Step 6: Delegate smoke and implement validation at the audit boundary.** In deep smoke,
  replace the five direct physical calls with:

```gdscript
var physical: Dictionary = Verify.validate_physical_consistency(
	route, Elements.ROW_OFFSETS, true)
issues.append_array(physical.issues)
var analysis: Dictionary = physical.analysis
```

  In the sweep, replace the four direct physical calls with:

```gdscript
var physical: Dictionary = Verify.validate_physical_consistency(
	route, Elements.ROW_OFFSETS, false)
issues.append_array(physical.issues)
```

  Keep determinism repeats, template probes, length/speed/shape bands, seed scheduling, thresholds,
  and all caller prefixes unchanged. Add the formatter and replace `_run_audit` with:

```gdscript
static func _physical_issue_errors(
	catalog_version: String, seed_value: int, issues: PackedStringArray
) -> PackedStringArray:
	var errors := PackedStringArray()
	for issue in issues:
		errors.append("physical_consistency: catalog %s seed %d: %s" % [
			catalog_version, seed_value, issue,
		])
	return errors


static func _run_audit(
	seeds: Array, build_route: Callable, measure_route: Callable, compare_fleet: Callable
) -> Dictionary:
	var measurements := []
	var routes_by_seed := {}
	var generation_counts := {}
	var operational_errors := PackedStringArray()
	var catalog_version := str(References.CATALOG.get("catalog_version", ""))
	for seed_value in seeds:
		var route: Dictionary = build_route.call(seed_value)
		generation_counts[str(seed_value)] = int(
			generation_counts.get(str(seed_value), 0)) + 1
		if not route.has("positions") or route.positions.is_empty():
			operational_errors.append(
				"generation: catalog %s seed %d produced no route" % [
					catalog_version, seed_value,
				])
			continue
		var physical: Dictionary = Verify.validate_physical_consistency(
			route, Elements.ROW_OFFSETS, seed_value in DEEP_REVIEW_SEEDS)
		var physical_errors := _physical_issue_errors(
			catalog_version, seed_value, physical.issues)
		operational_errors.append_array(physical_errors)
		if not physical_errors.is_empty():
			continue
		measurements.append(measure_route.call(route))
		if seed_value in DEEP_REVIEW_SEEDS:
			routes_by_seed[seed_value] = route
	var comparison := {}
	if operational_errors.is_empty():
		comparison = compare_fleet.call(measurements)
	operational_errors.sort()
	return {
		"fleet": seeds.duplicate(),
		"measurements": measurements,
		"comparison": comparison,
		"routes_by_seed": routes_by_seed,
		"generation_counts": generation_counts,
		"operational_errors": operational_errors,
	}
```

  `_built` becomes only:

```gdscript
func _built(seed_value: int) -> Dictionary:
	return Generator.build(seed_value)
```

  Immediately after `_run_audit` returns in `_audit`, append the returned errors before the existing
  real failure branch:

```gdscript
var audit := _run_audit(AUDIT_SEEDS, build, measure, compare)
for error in audit.operational_errors:
	_operational.append(str(error))
if not _operational.is_empty():
	return _fail()
```

- [ ] **Step 7: Verify semantic parity and commit GREEN.** Require the permanent `godot` job to pass
  through the GitHub connector. Compare representative smoke lines from the preceding green run:
  thresholds, seed labels, and failure message text must be unchanged. Confirm the orchestration test
  reports one build for the clean and failed seeds, measurement only for seed 11, no comparison, no
  retained seed-42 route, and the exact physical error above. Commit as
  `refactor: share route physical validation`.

---

### Task 5: Make All Sixteen Issue Records Exact and Useful

**Files:**
- Modify: `godot/fidelity_artifacts.gd:46-54,293-496,657-697`
- Test: `godot/fidelity_artifact_tests.gd:844-1133`

**Interfaces:**
- Coverage and checklist paths are selected only from the already-built canonical
  `render_requests`; no fabricated POV path is allowed.

- [ ] **Step 1: Replace the fallback oracle with all exact issue text.** In the permanent test, read
  `ProjectSettings.globalize_path("res://../docs/ISSUES.md")`, isolate text strictly between
  `## Ride quality` and `## App`, and join each numbered item with its indented continuation. Reject
  duplicate/missing IDs; use this parsed map as the single expected-title authority rather than
  copying sixteen strings into test code. Assert IDs are exactly `1..16`, every production string
  matches, no value begins `Issue `, and every path is a member of the canonical requests. Define
  path families from the requests: `C` all deep-seed
  channels; `V` all deep-seed top/elevation; `E` available seed-42 element views; `P` authorized POV.
  Assert exact unions:

```text
1  Missing micro elements — e.g. the slow-ish hilltop section Falcon's Flight has; small connective beats are absent.
2  Pacing cheated by near-zero-loss coasting — boring sections hold speed as if friction/drag-free, propping up the elapsed average.
3  G-force envelope still not reached in many parts.
4  Oversmoothing of elements.
5  Poor FVD implementation — the force-authoring quality itself, not just targets.
6  Poor terrain awareness — e.g. ~80 m above the terrain at the ride's highest point, never under 40 m; not actually terrain-hugging.
7  Overlapping supports and poor element shaping, especially inversions.
8  Poor sense of speed.
9  Entry launch should hit significantly higher speed — similar class to the camelback (tunnel) booster.
10 Poor element flow — jerky useless-bank → flat → useless-bank sequences.
11 Overly leisurely in many sections.
12 Too many flats — between the cliff-dive LSM and the camelback, on the return, and the hold extending too far from the cliff edge (so the clifftop is not terrain-hugging).
13 Airtime hills etc. too tame.
14 Elements miss the original near-future scaling requirements — scaling/geometry feels wrong when compared multi-dimensionally (height vs speed vs g vs duration together).
15 Jerky transitions.
16 Many more hard-to-describe "feel" gaps beyond the itemizable ones.
```

```text
1 V+E      2 C        3 C        4 V+E      5 C+V+E    6 C+V
7 V+E      8 C+P      9 C       10 C       11 C+P     12 C+V
13 C      14 V+E     15 C       16 C+V+E+P
```

  Require sorted unique paths, no duplicate, no missing canonical request, and no POV path after
  removing alignment from the fixture. Update JSON/Markdown goldens independently.

- [ ] **Step 2: Commit and observe RED on GitHub.** Commit as
  `test: require exact fidelity issue traceability`; expect missing titles and channel-only links.

- [ ] **Step 3: Project titles and paths from canonical requests.** Replace `_ISSUE_TEXT` with the
  exact sixteen joined strings. Let `_catalog_context` project evidence/state only. After
  `_render_requests`, filter those requests by semantic families and assign paths to checklist rows
  by category: shaping `V+E`; feel `C+V+E+P`; speed perception `C+P`; terrain/clearance `C+V`;
  support overlap `V+E`. Apply the explicit issue-family matrix above; an existing measured state
  does not suppress relevant prompt paths. Sort and deduplicate every list. JSON and Markdown read
  the same coverage object.

- [ ] **Step 4: Verify and commit GREEN.** Require the aligned fixture to include its exact POV path,
  the committed unaligned catalog to contain none, all sixteen text/path cases to pass, and no
  generic title fallback in production. Commit as `feat: trace all ride issues to review artifacts`.

---

### Task 6: Remove Duplicate Renders and Correct Operator Documentation

**Files:**
- Modify: `godot/_inspect.gd:35-66,156-264`
- Test/Modify: `godot/fidelity_artifact_tests.gd:47-99`
- Modify: `README.md:65-125`
- Modify: `CLAUDE.md:55-78`
- Modify: `docs/ISSUES.md:43-96`
- Modify: `docs/superpowers/plans/2026-08-09-evidence-audit-baseline.md` (verified closeout only)

**Interfaces:**
- Preserves console families using the literal prefixes `PHASE `, `ELEM `, and `CHANNEL ` followed
  by deterministic `Artifacts.canonical_json(...)`; records carry unambiguous seed and section/beat/
  channel identity plus every old printed raw metric.
- Makes `_stats(route: Dictionary, a: int, b: int) -> Dictionary` static. Its `r_apex` and `r_valley`
  values are nullable Floats paired with `r_apex_unbounded` and `r_valley_unbounded` Booleans;
  exactly zero curvature is unbounded, otherwise every positive finite value is exactly
  `1.0 / curvature` with no threshold or cap.
- Canonical files remain only under `review/...` plus root report/manifest text.

- [ ] **Step 1: Add the focused diagnostic-radius RED.** Call this from `_test_audit_fleet`; it uses
  only the fields `_stats` reads and proves both the unbounded sentinel and a finite radius above the
  old cap:

```gdscript
static func _test_diagnostic_radii(inspect: Script, errors: PackedStringArray) -> void:
	var stats := Callable(inspect, "_stats")
	if not stats.is_valid():
		errors.append("the inspector exposes no static _stats diagnostic seam")
		return
	var route := {
		"positions": PackedVector3Array([Vector3.ZERO, Vector3.RIGHT]),
		"tangents": PackedVector3Array([Vector3.RIGHT, Vector3.RIGHT]),
		"curvatures": PackedVector3Array([Vector3.ZERO, Vector3.UP * 0.00001]),
		"banks": PackedFloat32Array([0.0, 0.0]),
		"speeds": PackedFloat32Array([10.0, 10.0]),
		"normal_g": PackedFloat32Array([1.0, 1.0]),
		"distances": PackedFloat32Array([0.0, 1.0]),
	}
	var zero: Dictionary = stats.call(route, 0, 0)
	_expect(errors, zero.r_apex == null and zero.r_valley == null
		and zero.r_apex_unbounded == true and zero.r_valley_unbounded == true,
		"zero curvature is explicitly unbounded")
	var finite: Dictionary = stats.call(route, 1, 1)
	_expect(errors, is_equal_approx(float(finite.r_apex), 100000.0)
		and is_equal_approx(float(finite.r_valley), 100000.0)
		and finite.r_apex_unbounded == false and finite.r_valley_unbounded == false,
		"0.00001 inverse metres reports a 100000 m radius without clamping")
	var curvatures: PackedVector3Array = route.curvatures
	curvatures[1] = Vector3.UP * 1.0e-13
	route.curvatures = curvatures
	var tiny: Dictionary = stats.call(route, 1, 1)
	_expect(errors, is_equal_approx(float(tiny.r_apex), 1.0e13)
		and tiny.r_apex_unbounded == false,
		"positive finite curvature remains finite however large its reciprocal")
```

- [ ] **Step 2: Commit and observe RED on GitHub.** Commit the test only as
  `test: reject clamped diagnostic radii`; expect the missing static `_stats` seam, not an import or
  unrelated failure.

- [ ] **Step 3: Delete root rendering and correct radius projection.** First save the nonempty
  matches from the final static `rg` command in the ignored progress ledger and confirm the existing
  pack-file equality test is green. Delete `_save`, root calls to
  `channels_<seed>.png`, seed-42 side images, `top.png`, and `elevation.png`. Delete the inspector's
  duplicate `_element_groups`; make `_stats` static and replace its `1.0 / maxf(curvature, 0.0001)`
  radius floor with the nullable result and explicit unbounded flags below. Do not call `Artifacts.channels`,
  `top_image`, `elevation_image`, or `side_image` from the inspector.

```gdscript
var apex_curvature: float = route.curvatures[apex].length()
var valley_curvature: float = route.curvatures[valley].length()
var apex_unbounded := apex_curvature == 0.0
var valley_unbounded := valley_curvature == 0.0
# Keep the existing statistics and replace only the four radius entries:
"r_apex": null if apex_unbounded else 1.0 / apex_curvature,
"r_valley": null if valley_unbounded else 1.0 / valley_curvature,
"r_apex_unbounded": apex_unbounded,
"r_valley_unbounded": valley_unbounded,
```

  Replace the diagnostic functions with these machine-readable projections. The single
  `Fidelity.element_bands(route, 0.0)` call is the only element grouping operation:

```gdscript
func _print_diagnostics(routes_by_seed: Dictionary) -> void:
	var route: Dictionary = routes_by_seed[42]
	_print_phases(route, 42)
	var bands: Array = Fidelity.element_bands(route, 0.0)
	for band in bands:
		var first := int(band.first)
		var last := int(band.last)
		var stats: Dictionary = _stats(route, first, last)
		print("ELEM " + Artifacts.canonical_json({
			"seed": 42,
			"beat_id": str(band.beat_id),
			"kind": str(band.kind),
			"length_m": float(route.distances[last] - route.distances[first]),
			"entry_speed_mps": float(route.speeds[first]),
			"exit_speed_mps": float(route.speeds[last]),
			"min_pitch_deg": float(stats.min_pitch),
			"max_pitch_deg": float(stats.max_pitch),
			"max_abs_bank_deg": float(stats.max_bank),
			"min_normal_g": float(stats.min_n),
			"max_normal_g": float(stats.max_n),
			"width_m": float(stats.width),
			"height_m": float(stats.height),
			"apex_radius_m": stats.r_apex,
			"apex_radius_unbounded": bool(stats.r_apex_unbounded),
			"valley_radius_m": stats.r_valley,
			"valley_radius_unbounded": bool(stats.r_valley_unbounded),
		}))
	for seed_value in DEEP_REVIEW_SEEDS:
		_print_channels_from_legend(seed_value)


func _print_phases(route: Dictionary, seed_value: int) -> void:
	for section_ordinal in route.sections.size():
		var section: Dictionary = route.sections[section_ordinal]
		var element: Dictionary = section.get("element", {})
		print("PHASE " + Artifacts.canonical_json({
			"seed": seed_value,
			"section_ordinal": section_ordinal,
			"name": str(section.name),
			"kind": str(element.get("kind", section.kind)),
			"length_m": float(section.end_distance - section.start_distance),
			"duration_s": float(section.end_time - section.start_time),
			"entry_speed_mps": float(section.entry_speed),
			"exit_speed_mps": float(section.exit_speed),
		}))


func _print_channels_from_legend(seed_value: int) -> void:
	var relative_path := "review/seed-%d/channels.json" % seed_value
	var legend_path := OUT.path_join(relative_path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(legend_path))
	if not parsed is Dictionary:
		_operational.append(
			"artifact_write: channel legend for seed %d did not reopen" % seed_value)
		return
	var legend: Dictionary = parsed
	for strip in legend.get("strips", []):
		print("CHANNEL " + Artifacts.canonical_json({
			"seed": seed_value,
			"channel_id": str(strip.channel_id),
			"plot_min": float(strip.plot_min),
			"plot_max": float(strip.plot_max),
			"bounded_count": int(strip.bounded_count),
			"unbounded_count": int(strip.unbounded_count),
		}))
```

  Move `_print_diagnostics(audit.routes_by_seed)` to immediately after successful `write_pack`, so
  every `CHANNEL` record is sourced from a checked file rather than in-memory render state. Follow it
  with the exact failure path below; this removes the success marker if a legend cannot be reopened:

```gdscript
_print_diagnostics(audit.routes_by_seed)
if not _operational.is_empty():
	for error in Artifacts.invalidate_pack(OUT):
		_operational.append(str(error))
	return _fail()
```

  `PHASE` preserves exact section name/kind, zero-based ordinal, length, duration, and entry/exit
  speed. `ELEM` preserves length, entry/exit speed, pitch range, maximum absolute bank, normal-G
  range, and width/height. Each apex/valley radius is either an exact finite Float with its unbounded
  flag `false`, or `null` with its unbounded flag `true`. `CHANNEL` preserves plot bounds and bounded/
  unbounded counts from the reopened canonical legend. The checked channel/top/elevation/element/POV
  artifacts continue to preserve the visual shaping, force/angle, geometry, flow, thrill, and speed
  review capability.

- [ ] **Step 4: Update durable documentation to exact current behavior.** State canonical
  `review/...` paths only; all fifteen seeds gate structure/seams/terrain/self-clearance and only
  11/42/20260809 gate loads; text is verified as reopened UTF-8 bytes; PNGs reopen/decode before
  manifest publication; run-start invalidation and manifest-last semantics; route-sampling delegates
  are the only permitted `main.gd` diff; fidelity remains diagnostic; radius-scale and unavailable-
  POV gaps remain. Remove text claiming local/full-audit proof or channel-only issue coverage. Do not
  claim Task 7 evidence before its GitHub run exists.

- [ ] **Step 5: Verify and commit GREEN.** Require the radius test, standard CI, the empty duplicate-
  render search, and the diff check to pass:

```powershell
rg -n 'channels_%d\.png|"%s/top\.png"|"%s/elevation\.png"|Artifacts\.side_image' godot/_inspect.gd
git diff --check
```

  Confirm expected canonical review images remain in artifact tests. Commit as
  `refactor: render canonical fidelity diagnostics once`.

---

### Task 7: Prove Two Complete Audits on GitHub and Restore Permanent CI

**Files:**
- Temporarily modify, then restore: `.github/workflows/ci.yml`
- Temporarily create, then remove: `godot/_verify_fidelity_pack.gd`
- Modify after evidence exists: `docs/superpowers/plans/2026-08-09-evidence-audit-baseline.md`

**Interfaces:**
- Consumes the fixed fleet `11, 42, 20260809, 1, 3, 7, 99, 256, 555, 1234, 4096, 31337,
  77777, 123456, 20250101`, deep seeds `11, 42, 20260809`, catalog version
  `2026-08-10.evidence-baseline.2`, and the eleven channel IDs below.
- Produces one accepted exact-SHA GitHub run and `fidelity-audit` artifact. Leaves the permanent
  workflow byte-identical to `$remediationBase` and no temporary verifier.

- [ ] **Step 1: Write the temporary acceptance verifier first.** Create
  `godot/_verify_fidelity_pack.gd` as a `SceneTree` script using only Godot-native `JSON`,
  `FileAccess`, `DirAccess`, `HashingContext`, and `Image.load_png_from_buffer`. Define these helpers:

```gdscript
func _require(condition: bool, message: String) -> void
func _read_json(path: String) -> Variant
func _read_bytes(path: String) -> PackedByteArray
func _sha256(bytes: PackedByteArray) -> String
func _lf_payload(rows: Array[String]) -> PackedByteArray
func _verify_report(pack_dir: String, report: Dictionary) -> Dictionary
func _verify_manifest(pack_dir: String, manifest_bytes: PackedByteArray,
        report: Dictionary, composition: Dictionary) -> void
func _verify_characterization(pack_dir: String, log_path: String) -> void
func _verify_physical_failure() -> int
```

  Override `_initialize` to accept exactly `pack <pack_dir> <log_path>` or `physical`. Pack
  assertions append deterministic `acceptance: <message>` records; `_initialize` prints them and
  exits 2 when any exist. Otherwise physical mode exits with Step 2's inherited audit status and
  pack mode exits 0.
  `_lf_payload(rows)` returns zero bytes for an empty list; otherwise it is UTF-8
  `"\n".join(rows) + "\n"`.
  Parse the JSON diagnostics and derive these independent canonical LF inventories before hashing:

  - seed-42 `PHASE` rows in section order as
    `section_ordinal<TAB>name<TAB>kind<LF>`: count 53, SHA-256
    `4e078bec257ab7c43b3190d4b2e0e2a186f9a21b7e5e16509b4e3751b27e1c54`;
  - seed-42 `ELEM` rows in beat order as `beat_id<TAB>kind<LF>`: count 51, SHA-256
    `919c50ffae31c7cc52323a6e7ec3e116eb4e3260adf0fb4fce01fb995f8e8871`;
  - sorted element request paths, one path per row: count 15, SHA-256
    `329289c7af125dcb7eae3d83dc71678709a6352d7715473af1357f2ec374266b`;
  - POV gaps sorted by `id`, each row
    `id<TAB>source_id<TAB>reason<TAB>sorted-comma-joined-source_landmark_ids<LF>`: count 8,
    with every reason exactly `alignment-not-present`, SHA-256
    `9e09e172ff3ef0dd10946d7c7485386894f6d82fdee433923429fbcb87cb320a`.

  Verify audit schema `ride-fidelity-audit@1`, catalog schema 2, current catalog version, and valid
  status. Require the 15 seeds in fixed order, each generated once, and 15 measurement summaries
  in that same order. Every summary has a nonempty beat list; every beat has exactly ordered rows
  `row-01` through `row-07` with the modeled offsets. Require empty `findings`, `observed_only`,
  and comparison `evidence_gaps`, and recommendation exactly
  `{"status":"no-eligible-finding"}` with no overall-score member.
  Require source/landmark parity with the catalog, no POV records or requests, and the exact eight
  gap tuples.

  Require 24 path-sorted render requests: three channels, three top views, three elevations, and 15
  seed-42 elements. Require issue records exactly 1..16, non-placeholder exact issue titles, and
  generated paths that are sorted, unique, and members of the render requests. Require the five
  checklist category IDs exactly `shaping`, `feel`, `speed-perception`, `terrain-clearance`, and
  `support-overlap`. Construct the exact 38-file set from the seven fixed text files (`audit.json`,
  `audit.md`, POV-map JSON/Markdown, checklist Markdown, and issue-coverage JSON/Markdown), five
  files per deep seed (channel JSON/Markdown/PNG plus top/elevation PNG), the 15 element PNGs, and
  `manifest.json`. Recursively enumerate the actual pack with `DirAccess`, normalize every relative
  path to forward slashes, sort, and require exact set equality. Require 37 sorted unique manifest
  records, no aliases or extras. Reopen manifest bytes, parse those bytes, reopen every record, verify size and SHA-256,
  fully decode every PNG, and match decoded dimensions; text dimensions must be null.

  Strictly parse and type-check all `PHASE`, `ELEM`, and `CHANNEL` rows before deriving inventories.
  Each ELEM row must match the ordered seed-42 beat identity and retain numeric length, entry/exit
  speed, pitch range, maximum absolute bank, normal-G range, width, and height. Each apex/valley
  radius is either a positive finite number paired with `*_radius_unbounded == false`, or null paired
  with `true`. Require 33 CHANNEL rows:
  deep seeds in order times `speed_kmh`, `normal_g`, `lateral_g`,
  `longitudinal_proper_g`, `pitch_deg`, `roll_rate_dps`, `agl_m`,
  `reconstructed_curvature_inv_m`, `radius_m`, `roll_acceleration_dps2`, `jerk_mps3`;
  numeric bounds and integer bounded/unbounded counts must match each reopened channel legend.

- [ ] **Step 2: Add the real physical-failure probe.** In the temporary verifier, subclass
  `_inspect.gd` and override `_built`, `_measured`, and `_compared` with their exact production
  declarations. Make seed 11 return high terrain. Call inherited `_audit` and assert return 1, all
  15 seeds built exactly once, seed 11 not measured, the other 14 measured once in fleet order,
  and compare never called. A verifier assertion exits 2; otherwise the probe preserves inherited
  status 1. Require captured output to match
  `physical_consistency: catalog .* seed 11: terrain intersects track`.

- [ ] **Step 3: Install the temporary acceptance job.** Append an `audit-characterization` job after
  permanent `godot`; checkout, install Godot 4.7.1, and import before any audit command. Commit only
  workflow plus verifier as `test: require complete fidelity acceptance`, push to PR #1, and select
  only the exact commit SHA. Do not spend a remote run proving that an acceptance-only verifier
  rejects a nonexistent directory; its adversarial catalog and physical process checks run in the
  complete job below.

- [ ] **Step 4: Make one-shot GREEN.** The temporary job must import; move
  `docs/evidence/fidelity/rideforcesdb/4804-diagnostic.json` aside under a restore trap; seed a stale
  manifest; run `_inspect.gd`; require nonzero status, `catalog:` in its log, and absent manifest.
  Restore the moved artifact immediately after those assertions, while retaining the exit trap only
  as fallback cleanup. Run `res://_verify_fidelity_pack.gd -- physical`, requiring status 1 and the exact physical
  substring. Run two audits into
  fresh A/B directories, byte-diff them, extract `^(PHASE|ELEM|CHANNEL)` streams, `cmp` them, then:

```bash
godot --headless --path godot --script res://_verify_fidelity_pack.gd -- \
  pack "$RUNNER_TEMP/a" "$RUNNER_TEMP/a.log"
```

  Upload `fidelity-audit` with A, both audit logs and structured streams, catalog-failure log, and
  physical-probe log using `if-no-files-found: error`. Commit as
  `ci: verify deterministic fidelity audit`; push and accept only its exact-SHA run with permanent
  and temporary jobs each green exactly once.

- [ ] **Step 5: Inspect, restore, and close out.** Download the accepted artifact. Visually inspect
  all three channels, six top/elevation images, and 15 element images; reject blank, corrupt,
  clipped-away, mislabeled, or support-obscured views. Record visual result, accepted run/job/
  artifact/provenance IDs, stale-manifest result, physical result, A/B equality, and root duplicate
  deletion. Revert temporary commits, preserve closeout docs, and prove workflow byte identity and
  verifier absence. Commit `docs: close corrected fidelity baseline`, push by exact SHA, and use the
  GitHub connector to confirm PR #1 at that SHA.

- [ ] **Step 6: Run the static final gate.** Require changed Godot paths exactly
  `godot/_inspect.gd`, `godot/fidelity_artifact_tests.gd`, `godot/fidelity_artifacts.gd`,
  `godot/smoke.gd`, and `godot/verify.gd`. Production numstat across the four production files
  must be net-negative. Report final physical line counts for `fidelity_artifacts.gd`,
  `fidelity.gd`, and `fidelity_tests.gd` against 1296, 2333, and 2218 respectively.
  Require no temporary verifier, unchanged workflow, no root aliases, and fresh correctness,
  documentation, and lean/line-count PASS reviews.

```powershell
git diff --check "$remediationBase..HEAD"
git diff --exit-code $remediationBase -- .github/workflows/ci.yml
if (Test-Path 'godot/_verify_fidelity_pack.gd') { throw 'temporary verifier remains' }
$expected = @('godot/_inspect.gd','godot/fidelity_artifact_tests.gd',
  'godot/fidelity_artifacts.gd','godot/smoke.gd','godot/verify.gd')
$actual = @(git diff --name-only $remediationBase -- 'godot/*.gd' | Sort-Object)
if ((Compare-Object ($expected | Sort-Object) $actual).Count) { throw 'wrong Godot path set' }
$prod = @('godot/_inspect.gd','godot/fidelity_artifacts.gd','godot/smoke.gd','godot/verify.gd')
$add=0; $del=0
foreach ($row in @(git diff --numstat $remediationBase -- $prod)) {
  $p=$row -split "`t"; $add += [int]$p[0]; $del += [int]$p[1]
}
if ($del -le $add) { throw "production is not net-negative: +$add -$del" }
foreach ($pair in @(@('godot/fidelity_artifacts.gd',1296),
  @('godot/fidelity.gd',2333), @('godot/fidelity_tests.gd',2218))) {
  $lines=(Get-Content $pair[0]).Count; "$($pair[0]): $lines (baseline $($pair[1]))"
}
$placeholderPattern = @(('T'+'BD'),('TO'+'DO'),('implement'+' later'),('fill in'+' details')) -join '|'
$placeholderMatches = @(rg -n $placeholderPattern docs/superpowers/plans/2026-08-11-evidence-baseline-remediation.md)
if ($placeholderMatches.Count) { throw "plan placeholders remain: $($placeholderMatches -join '; ')" }
$fences = @(rg -n '^\`\`\`' docs/superpowers/plans/2026-08-11-evidence-baseline-remediation.md)
if ($fences.Count % 2) { throw "unbalanced plan code fences: $($fences.Count)" }
```

  The placeholder scan must have no matches and the fence scan an even count.

- [ ] **Step 7: Run final permanent CI and hand off.** Push final `HEAD`, select only its exact-SHA
  permanent run, require `godot` green, and record final SHA/run/job IDs in the ignored ledger and
  a durable PR #1 comment. Handoff to Plan 2. Defer Graphify full rebuild, local build, and cleanup
  until the whole-branch gate after Plan 2 unless work stops here.

## Completion Boundary

Completion of this plan proves only that the evidence baseline is truthful, deterministic, and safe
to use. It does not declare the ride faithful and does not change ride behavior. Once Tasks 1,
2A–2C, and 3–7 plus their reviews pass, continue with Task 1 of
`docs/superpowers/plans/2026-08-09-route-config-foundation.md` under a fresh
`superpowers:subagent-driven-development` cycle.
