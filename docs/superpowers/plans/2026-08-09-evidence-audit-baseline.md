# Evidence Audit Baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce a skeptical, fully offline, deterministic fidelity baseline over the approved fifteen legacy-generator seeds before any ride-behavior change, backed by re-adjudicated committed evidence and checked JSON, Markdown, POV, and PNG artifacts.

**Architecture:** Execute this plan first, against the untouched legacy `Dictionary` returned by the current `RideGenerator.build(seed)`, before typed-route adaptation, motion-kernel authority, recipes, or behavior changes. `RideFidelityReferences` points to reviewed committed metadata/landmarks/hashes under `docs/evidence/fidelity/`; acquisition is an authoring workflow, while audit/CI remain offline. `RideFidelity` is read-only, `CanonicalData` supplies the one canonical JSON/hash implementation, `RideFidelityArtifacts` owns reports/checked writes, and `_inspect.gd` remains the diagnostic command.

**Tech Stack:** Godot 4.7.1, typed GDScript, built-in `JSON`, `FileAccess`, `DirAccess`, `Image`, and `HashingContext`; PowerShell 7-compatible verification commands; committed JSON/Markdown evidence records.

## Global Constraints

- Authority order is explicit user decisions, reproducible physical derivation and verified external evidence, creative ride vision, then current code/generated behavior.
- This baseline is executed and committed before the route/config foundation: it consumes untouched legacy route dictionaries, imports no `RideRoute`, `MotionTrajectory`, or `LegacyRouteAdapter`, and records the legacy base commit in `audit.json`.
- The fixed fleet order is exactly `[11, 42, 20260809, 1, 3, 7, 99, 256, 555, 1234, 4096, 31337, 77777, 123456, 20250101]`; preserve this order in reports. Sort stable identifiers inside findings, never the fleet.
- Source acquisition may use the visible in-app Browser or ignored local `yt-dlp`/`ffmpeg` work files. Commit no copyrighted video/frame/audio, cookies, tokens, or session data—only reviewed metadata, timestamped landmarks, source/alignment decisions, and hashes. Normal audit/smoke/CI are offline.
- Every YouTube video ID and RideForcesDB recording ID is a separate source record. Never merge URLs, runs, rows, devices, or timelines.
- Evidence targets reference a stable `semantic_selector_id`, never a route-specific beat ID. Each selector record declares both a legacy anchor (`phase`, `kind`, occurrence rule, and `window_role`) and a compiled anchor (`story_slot_id` plus `window_role`), or explicitly declares one representation inapplicable. Legacy v1 anchors use only the honest `whole` role; compiled anchors may select a validated role such as `core`. This single catalog must resolve both pre-change legacy measurements and post-cutover story-slot measurements; an unresolved applicable branch or role is an evidence gap, never a fallback.
- Evidence states are exactly `review_pending`, `observation_only`, `corroborative`, and `executable`; only `executable` observations may define comparison bands.
- A source or observation becomes `executable` only with a committed source artifact or content digest, retrieval date, exact window, axis mapping, row/seat, transform ID, confidence rationale, and required corroborating links.
- Unknown device/sample-rate video contributes timestamped landmarks, visible values, phase order, geometry, flow, and review prompts only. Never fabricate a dense trace.
- Approved fictional force transforms scale force values only, never source duration, geometry, or time. Positive/negative vertical, lateral, and negative longitudinal remain separate axes; there is no inferred positive-longitudinal multiplier.
- Preserve physical seconds even when emitting phase-normalized overlays; normalization must not conceal a duration miss. Keep row effects separate.
- Audit dimensions remain separate: loads, geometry/scale, pacing/energy, terrain/AGL, and flow/transitions. Findings are `within`, `under`, `over`, `observed-only`, or `evidence-gap`; there is no overall fidelity score.
- Preserve the diagnostic capability to emit per-element side/profile images, whole-route top/elevation images, and whole-ride force, speed, pitch, roll, and AGL channels. Extend it with longitudinal proper acceleration, curvature, radius, roll acceleration, and jerk.
- Generated positions are direct integrator output. No smoothing, fitted replacement curve, radius clamp, or viewer-only path may feed physics, verification, or generated-channel measurement.
- Filtering is permitted only for the existing human-tolerance verifier or a catalogued evidence comparison and must be explicitly labelled. Raw generated channels remain available.
- The audit generates each seed exactly once per run. Fidelity misses are diagnostic; malformed catalog data, generation failure, physical inconsistency, or failed artifact writes are operational failures.
- Do not modify `godot/generator.gd`, `godot/elements.gd`, `godot/main.gd`, `godot/terrain.gd`, or the safety thresholds/filtering in `godot/verify.gd` in this plan.
- Required stable commands remain the editor import and `res://smoke.gd` invocations below, always through the controlled portable binary and isolated application state.

Before any command block in a PowerShell session, run this preamble. In a linked worktree, the fallback resolves the portable binary from the shared repository rather than `PATH`; application state remains beneath the active worktree's ignored `out/`:

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

## File and Interface Map

- Create `docs/evidence/fidelity/source-manifest.json`: stable source IDs, exact URLs/recording IDs, retrieval metadata, state, and artifact digests.
- Create `docs/evidence/fidelity/catalog-review.md`: concise adjudication log explaining promotion, downgrade, rejection, and unresolved mappings.
- Create `docs/evidence/fidelity/youtube/*.json`: one reviewed metadata/landmark record per YouTube ID; no copied video and no invented sample series.
- Create `docs/evidence/fidelity/rideforcesdb/*.json`: reviewed retrieval/alignment records and raw response only when a genuine session-backed fetch validates; otherwise cite the committed telemetry tables and record the fetch gap.
- Create `godot/canonical_data.gd`: narrow recursive canonical JSON plus SHA-256 utility shared by config/catalog/report code.
- Create `godot/route_sampling.gd`: pure route time/distance/pose interpolation shared by the viewer and deterministic POV artifacts.
- Modify `godot/fidelity_references.gd`: JSON-compatible executable `CATALOG`, immutable transforms, source/observation records, targets, review prompts, and evidence gaps.
- Modify `godot/fidelity.gd`: catalog validation, beat/row measurement, exact held values, time-weighted metrics, transition windows, reconstruction, fleet comparison, and deterministic recommendation.
- Modify `godot/fidelity_tests.gd`: pure synthetic tests for all semantics and catalog rules.
- Create `godot/fidelity_artifacts.gd`: deterministic report/Markdown, checked writes, and diagnostic render helpers; canonical JSON delegates to `CanonicalData`.
- Create `godot/fidelity_artifact_tests.gd`: synthetic serialization, manifest, write-failure, render, and one-build-per-seed tests.
- Modify `godot/main.gd`: retain its static sampling APIs as thin delegates to `RouteSampling`, with no viewer behavior change.
- Modify `godot/_inspect.gd`: thin offline runner over the fixed fleet; retains existing console/PNG diagnostics and emits the complete baseline pack.
- Modify `godot/smoke.gd`: keep delegating shared grouping/held primitives and run both focused test suites; do not change existing ride target constants or generator gate behavior.
- Modify `README.md` and `CLAUDE.md`: document the offline baseline command, output contract, evidence-authoring separation, and operational-versus-diagnostic exit semantics.

Stable public interfaces for this plan:

```gdscript
RideFidelity.validate_catalog(catalog: Dictionary) -> PackedStringArray
RideFidelity.validate_catalog_artifacts(catalog: Dictionary) -> PackedStringArray
RideFidelity.held(values: PackedFloat32Array, polarity: float, seconds: float) -> float
RideFidelity.element_bands(route: Dictionary, row_offset: float = 0.0) -> Array
RideFidelity.measure_route(route: Dictionary, row_offsets: Array) -> Dictionary
RideFidelity.compare_fleet(seed_measurements: Array, catalog: Dictionary) -> Dictionary
CanonicalData.canonical_json(value: Variant) -> String
CanonicalData.sha256_text(value: String) -> String
RideFidelityArtifacts.build_report(seed_measurements: Array, comparison: Dictionary, catalog: Dictionary, legacy_base_commit: String, generation_counts: Dictionary) -> Dictionary
RideFidelityArtifacts.canonical_json(value: Variant) -> String # delegate only
RideFidelityArtifacts.markdown(report: Dictionary) -> String
RideFidelityArtifacts.write_pack(output_dir: String, report: Dictionary, routes_by_seed: Dictionary) -> PackedStringArray
RouteSampling.lower_index(values: PackedFloat32Array, value: float) -> int
RouteSampling.distance_at_time(route: Dictionary, time_s: float) -> float
RouteSampling.pose_at_distance(route: Dictionary, distance_m: float) -> Transform3D
```

---

### Task 1: Characterize the existing diagnostic contract

**Files:**
- Modify: `godot/fidelity_tests.gd`

**Interfaces:**
- Consumes: current `RideFidelity.held`, `RideFidelity.element_bands`, `RideFidelity.measure_route`, current inspector artifact names.
- Produces: characterization fixtures that distinguish preserved capability from corrected semantics.

- [ ] **Step 0: Pin and prove the untouched legacy input boundary**

Run `git rev-parse HEAD` and retain the exact hash as `legacy_base_commit` in the report contract. Add a focused assertion that `RideGenerator.build(42) is Dictionary`, contains current packed arrays/sections, and that `fidelity.gd`, `_inspect.gd`, and this test import none of `RideRoute`, `MotionTrajectory`, or `LegacyRouteAdapter`. If the foundation has already changed that boundary, execute this plan from a worktree at the pinned pre-foundation commit rather than adapting the audit forward.

- [ ] **Step 1: Add a synthetic legacy route helper with shared-element identity and all required diagnostic channels**

```gdscript
static func _legacy_characterization_route() -> Dictionary:
	var route := _measurement_route()
	route["sections"][0]["element"] = route.sections[1].element
	route["sections"][0]["phase"] = "act one"
	route["sections"][1]["phase"] = "act one"
	return route
```

- [ ] **Step 2: Add characterization assertions for grouping, stable current beat IDs, row-window intent, and read-only measurement**

```gdscript
static func _test_legacy_characterization(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _legacy_characterization_route()
	var before := route.duplicate(true)
	var bands: Array = fidelity.element_bands(route, 2.0)
	_expect(errors, bands[0].beat_id == "act-one/00/hill", "legacy adapter keeps its stable beat ID")
	_expect_close(errors, bands[0].window_start_distance, 2.0, "rear row enters after its offset")
	fidelity.measure_route(route, [0.0, 2.0])
	_expect(errors, route == before, "fidelity measurement is read-only")
```

- [ ] **Step 3: Run the focused suite with the repository-portable Godot binary**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
```

Expected: the existing fidelity characterizations pass. Artifact tests are introduced immediately before artifact implementation in Task 7, so no committed task leaves a focused suite red.

- [ ] **Step 4: Commit the characterization boundary**

```powershell
git add godot/fidelity_tests.gd
git commit -m "test: characterize fidelity diagnostics"
```

### Task 2: Research and commit distinct evidence records

**Files:**
- Create: `docs/evidence/fidelity/source-manifest.json`
- Create: `docs/evidence/fidelity/catalog-review.md`
- Create: `docs/evidence/fidelity/youtube/*.json`
- Create: `docs/evidence/fidelity/rideforcesdb/*.json`

**Interfaces:**
- Consumes: approved evidence rules and the repository claims in `docs/TELEMETRY.md`, `docs/TELEMETRY-I305.md`, and `docs/RESEARCH.md`.
- Produces: immutable offline artifacts referenced by `RideFidelityReferences.CATALOG`.

- [ ] **Step 1: Create the evidence directories and record the exact source inventory in `source-manifest.json`**

```powershell
New-Item -ItemType Directory -Force 'docs/evidence/fidelity/youtube' | Out-Null
New-Item -ItemType Directory -Force 'docs/evidence/fidelity/rideforcesdb' | Out-Null
```

The manifest must contain separate source IDs for all of these URLs/recordings, even when two sources cover the same ride:

```text
youtube.falcon.forward.cUURkqyn4Zs       https://www.youtube.com/watch?v=cUURkqyn4Zs
youtube.falcon.backward.J54WKu2nU6o      https://www.youtube.com/watch?v=J54WKu2nU6o
youtube.falcon.sdXGD9kMR7s               https://www.youtube.com/watch?v=sdXGD9kMR7s
youtube.falcon.poco8rOnW18               https://www.youtube.com/watch?v=poco8rOnW18
youtube.coastertalk.continuous.0Ua       https://www.youtube.com/watch?v=0UaOSBGSx20
youtube.coastertalk.edited.seNR          https://www.youtube.com/watch?v=seNRpi4wP-s
youtube.tormenta.forward.AHjk            https://www.youtube.com/watch?v=AHjk2R4da_I
youtube.i305.overlay.wX7                  https://www.youtube.com/watch?v=wX7uHKj-Ujc
youtube.falcon.cgi.NFV                    https://www.youtube.com/watch?v=NFVNGgwZk3c
rideforcesdb.falcon.4804                  https://rideforcesdb.com/getRec?id=4804
rideforcesdb.tormenta.6383                https://rideforcesdb.com/getRec?id=6383
rideforcesdb.tormenta.6369                https://rideforcesdb.com/getRec?id=6369
```

`source-manifest.json` has `schema_version: "fidelity-source-manifest@1"` and one record per source ID. Each record fixes `initial_state`, `permitted_contributions`, `permitted_axes`, and `promotion_prerequisites`; no later code infers them from the URL:

| Source ID | Initial state | Permitted contribution |
|---|---|---|
| `youtube.falcon.forward.cUURkqyn4Zs` | `observation_only` | order, geometry, timing landmarks, feel prompts |
| `youtube.falcon.backward.J54WKu2nU6o` | `observation_only` | order, geometry, speed perception, feel prompts |
| `youtube.falcon.sdXGD9kMR7s` | `observation_only` | order, geometry, timing landmarks, feel prompts |
| `youtube.falcon.poco8rOnW18` | `corroborative` | model-to-model geometry/order only |
| `youtube.coastertalk.continuous.0Ua` | `corroborative` | displayed-channel landmarks; axes remain unknown until reviewed |
| `youtube.coastertalk.edited.seNR` | `review_pending` | edited visual landmarks only; no absolute ride timeline |
| `youtube.tormenta.forward.AHjk` | `observation_only` | order, geometry, timing landmarks, feel prompts |
| `youtube.i305.overlay.wX7` | `corroborative` | vertical/normal-g windows only |
| `youtube.falcon.cgi.NFV` | `corroborative` | model-to-model geometry/order only |
| `rideforcesdb.falcon.4804` | `corroborative` | reviewed force windows with row/device caveats |
| `rideforcesdb.tormenta.6383` | `corroborative` | reviewed force windows with row/device caveats |
| `rideforcesdb.tormenta.6369` | `corroborative` | cross-recording support only; pocket/sliding caveat |

State semantics are executable rules: `review_pending` means identified/acquired but not sufficiently reviewed; `observation_only` permits only its manifest-listed observations and prompts but no band; `corroborative` may support another aligned source but cannot define a band alone; `executable` requires artifact/digest, exact window, axis/row mapping, transform, confidence rationale, and required corroboration. Promotion cannot expand a source beyond `permitted_contributions` or `permitted_axes` without a reviewed manifest version change.

Review these four visual timelines independently and retain only source-local point landmarks:
`J54WKu2nU6o` real backwards POV (`observation_only`), `sdXGD9kMR7s` real front-row POV
(`observation_only`), `0UaOSBGSx20` continuous CoasterTalk Source landmarks (`corroborative`,
unknown row/device/sample rate preserved), and `poco8rOnW18` NoLimits2 simulation
(`corroborative` model-to-model only, never measured truth). No source-to-generated alignment or
aligned observation is approved in this baseline; keep the alignment arrays empty. Never merge
their URLs, timeline origins, landmarks, or clocks. The table fixes every other source's state and
limits. If identity, row, device, or timing cannot be established, retain `review_pending`; only a
future qualifying observation may become `executable` through a separately reviewed promotion.

- [ ] **Step 2: Capture reproducible YouTube metadata artifacts without downloading video**

```powershell
$ids = @('cUURkqyn4Zs','J54WKu2nU6o','sdXGD9kMR7s','poco8rOnW18','0UaOSBGSx20','seNRpi4wP-s','AHjk2R4da_I','wX7uHKj-Ujc','NFVNGgwZk3c')
foreach ($id in $ids) {
  curl.exe -L --fail --silent --show-error --max-time 30 "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$id&format=json" -o "docs/evidence/fidelity/youtube/$id-oembed.json"
}
```

Expected: nine distinct JSON files; a failed or unavailable URL stops the task and leaves that record `review_pending` with the retrieval failure recorded, never copied from another source.

- [ ] **Step 3: Review video through the visible in-app Browser or ignored local extraction**

Preferred: invoke `browser:control-in-app-browser`, navigate the exact URL, keep the pane visible, seek precisely, and use canvas-painted contact sheets per `docs/RESEARCH.md` §7. If Browser inspection is unavailable, use ignored local work only:

```powershell
New-Item -ItemType Directory -Force 'out/evidence-work/video','out/evidence-work/frames' | Out-Null
$timelineIds = @('J54WKu2nU6o','sdXGD9kMR7s','0UaOSBGSx20','poco8rOnW18')
foreach ($id in $timelineIds) {
  yt-dlp --no-playlist -f "bv*+ba/b" --merge-output-format mp4 -o "out/evidence-work/video/%(id)s.%(ext)s" "https://www.youtube.com/watch?v=$id"
}
ffmpeg -hide_banner -loglevel error -ss 00:01:54.500 -i 'out/evidence-work/video/sdXGD9kMR7s.mp4' -frames:v 1 'out/evidence-work/frames/sdXGD9kMR7s-114.5.png'
```

Use `ffprobe` for duration/stream metadata and repeat `ffmpeg -ss` only at reviewed landmarks. Commit no downloaded media, frames, audio, thumbnails, cookies, or sessions. Commit one `<video-id>-review.json` per URL containing metadata, exact timestamps/windows, landmark descriptions, local source SHA-256 when available, and state; a hash does not make a video trace executable. This baseline approves no source-to-generated mapping. Any future mapping must carry a reviewed structured `alignment` object with `source_landmark_id`, `generated_anchor.semantic_selector_id`, `method`, `uncertainty_s`, `row_compatibility`, and `rationale`. Edited or discontinuous timelines could use only landmark-to-landmark methods, never invented absolute ride time. Missing fields yield an evidence gap, never an inferred mapping.

- [ ] **Step 4: Establish a RideForcesDB session, then attempt genuine raw acquisition**

```powershell
$recordings = @('4804','6383','6369')
foreach ($recording in $recordings) {
  $cookie = "out/evidence-work/rfdb-$recording.cookies"
  curl.exe -L --fail --silent --show-error --max-time 30 -c $cookie -o NUL "https://rideforcesdb.com/?id=$recording&axes=yzxac"
  curl.exe -L --fail --silent --show-error --max-time 30 -b $cookie "https://rideforcesdb.com/getRec?id=$recording" -o "out/evidence-work/rfdb-$recording-getRec"
  curl.exe -L --fail --silent --show-error --max-time 30 -b $cookie "https://rideforcesdb.com/download?id=$recording&ftype=csv" -o "out/evidence-work/rfdb-$recording.csv"
}
```

Validate status, content type, non-login/non-HTML body, parseability, recording ID, columns, sample count, and monotone time before copying a genuine payload to `docs/evidence/fidelity/rideforcesdb/<id>-raw.{json,csv}`. Never commit cookies. Acquisition is a validated `acquisition` tagged union: `raw` requires repository-relative `artifact_path` and `artifact_sha256` and forbids `diagnostic_path`, `diagnostic_sha256`, and `fallback_citations`; `raw_fetch_unavailable` forbids `artifact_path`/`artifact_sha256`, requires repository-relative `diagnostic_path`/`diagnostic_sha256`, and requires non-empty `fallback_citations`, each with `document`, stable table/section ID, row or line anchor, columns used, and source windows used. If both endpoints remain unavailable, commit only retrieval diagnostics, cite the already committed windows/tables in `docs/TELEMETRY.md`, and keep the justified evidence state. Never fabricate or reconstruct a raw payload from prose tables.

- [ ] **Step 5: Verify raw artifact hashes and record the exact lowercase SHA-256 values in the manifest**

```powershell
Get-ChildItem 'docs/evidence/fidelity' -Recurse -File |
  Where-Object Name -Match '(oembed|raw).*\.(json|csv)$' |
  Sort-Object FullName |
  ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
    '{0}  {1}' -f $hash, $_.FullName
  }
```

Copy each exact digest into its matching manifest record; do not use a date, path, or digest from a neighboring source.

- [ ] **Step 6: Create separate reviewed alignment records for RideForcesDB 4804, 6383, and 6369**

Each record must include `acquisition` (`raw` or `raw_fetch_unavailable`), exactly the matching artifact pair or diagnostic-plus-structured-fallback branch defined above, raw axis names when actually acquired, mapped rider axes, row/seat, device, native sample rate, processing chain, excluded intervals, named element order, exact source-second windows, alignment evidence, confidence rationale, and corroborating source IDs. Keep 4804 corroborative because RideForcesDB flags the wrist recording unreliable. Record 6383 as row 2. Record 6369 separately with its back/right-pocket, pocket-carried/sliding-device caveat; it cannot silently stand in for 6383 or measured rider-frame truth. Only a derived observation corroborated across 6383, 6369, and the Tormenta POV may become executable. When raw acquisition is unavailable, retain `raw_fetch_unavailable`; validator tests must reject missing fallback anchors, simultaneous acquisition branches, or a raw digest without a genuine raw artifact.

- [ ] **Step 7: Write `catalog-review.md` as a decision log**

Record these mandatory adjudications:

- the continuous `0UaOSBGSx20` and edited `seNRpi4wP-s` videos remain distinct;
- `J54WKu2nU6o`, `sdXGD9kMR7s`, `0UaOSBGSx20`, and `poco8rOnW18` retain independent timeline origins and source-local point landmarks; no source-to-generated alignment or aligned observation is approved, so their alignment arrays remain empty;
- `poco8rOnW18` is NoLimits2 simulation and remains corroborative model-to-model evidence only;
- no unknown-rate video becomes a dense trace;
- 4804 does not independently define executable bands;
- 6383 remains row 2; 6369 retains its back/right-pocket, pocket-carried/sliding-device caveat; a telemetry-table fallback is labelled `raw_fetch_unavailable` rather than raw;
- the old `terrain.act_one_hugging_share = [0.8, 1.0]` is an evidence gap because the source is qualitative;
- the old I305 `transition_force_swing = [3.5, 4.7]` is removed unless an exact non-coincident source window proves that metric;
- the old Do-Dodonpa `1.1` positive-longitudinal scale is removed because no approved Gx+ fictional multiplier exists;
- CGI remains model-to-model visual evidence and yields no measured-truth target where real POV disagrees.

- [ ] **Step 8: Confirm normal test commands run with network disabled after artifacts exist**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
```

Expected: this command reads repository files only. Inert provenance URLs exist only in
`fidelity_references.gd`; no test or runtime code constructs a network client or dereferences a
catalog URL.

- [ ] **Step 9: Commit the reviewed evidence artifacts separately from executable catalog code**

```powershell
git add docs/evidence/fidelity
git commit -m "docs: commit reviewed ride evidence"
```

### Task 3: Replace the catalog schema and re-adjudicate executable targets

**Files:**
- Modify: `godot/fidelity_references.gd`
- Modify: `godot/fidelity.gd`
- Modify: `godot/fidelity_tests.gd`

**Interfaces:**
- Consumes: committed evidence artifacts from Task 2.
- Produces: `RideFidelityReferences.CATALOG` schema version 2 and strict `RideFidelity.validate_catalog`.

- [ ] **Step 1: Add a complete valid schema-v2 catalog fixture**

```gdscript
static func _valid_catalog_v2() -> Dictionary:
	return {
		"schema_version": 2,
		"catalog_version": "2026-08-09.baseline.1",
		"selectors": {
			"semantic.act1.loop.core": {
				"legacy_anchor": {"phase":"act one", "kind":"loop", "occurrence":0, "window_role":"whole"},
				"compiled_anchor": {"story_slot_id":"act1.loop", "window_role":"core"},
			},
		},
		"sources": {
			"rideforcesdb.tormenta.6383": {
				"state": "corroborative",
				"acquisition": "raw",
				"url": "https://rideforcesdb.com/getRec?id=6383",
				"recording_id": "6383",
				"retrieved_on": "2026-08-10",
				"retrieval_context": "RideForcesDB getRec response",
				"artifact_path": "docs/evidence/fidelity/rideforcesdb/6383-raw.json",
				"artifact_sha256": "d".repeat(64),
				"row_seat": "row 2",
				"device": "consumer IMU; exact device unverified",
				"sample_rate_hz": 50.0,
				"axis_mapping": {"vertical": "normal_g", "lateral": "lateral_g", "longitudinal": "longitudinal_g"},
				"reliability": "requires element-order and cross-recording corroboration",
				"processing": ["raw committed response", "source-window selection only"],
				"caveats": ["no independently validated angle channel"],
			},
		},
		"transforms": {
			"fictional.gz-positive.1_3333333333@2026-08-09": {
				"axis": "normal_g", "polarity": "positive", "factor": 1.3333333333,
				"formula": "target_force_g = observed_force_g * 1.3333333333",
				"approval": "explicit user decision 2026-08-09",
			},
		},
		"observations": [], "targets": [], "review_prompts": [], "evidence_gaps": [],
	}
```

- [ ] **Step 2: Add failing validator cases for state, provenance, digest, row, axis, duration, and transform rules**

```gdscript
static func _test_catalog_v2_validation(fidelity: Script, errors: PackedStringArray) -> void:
	var catalog := _valid_catalog_v2()
	_expect(errors, fidelity.validate_catalog(catalog).is_empty(), "complete schema-v2 catalog validates")
	var bad_state := catalog.duplicate(true)
	bad_state.sources["rideforcesdb.tormenta.6383"].state = "trusted"
	_expect_contains(errors, fidelity.validate_catalog(bad_state), "invalid state", "unknown evidence state is rejected")
	var bad_hash := catalog.duplicate(true)
	bad_hash.sources["rideforcesdb.tormenta.6383"].artifact_sha256 = "abc"
	_expect_contains(errors, fidelity.validate_catalog(bad_hash), "artifact_sha256", "non-SHA-256 digest is rejected")
	var bad_union := catalog.duplicate(true)
	bad_union.sources["rideforcesdb.tormenta.6383"].acquisition = "raw_fetch_unavailable"
	_expect_contains(errors, fidelity.validate_catalog(bad_union), "acquisition", "acquisition branches cannot be mixed")
	var bad_selector := catalog.duplicate(true)
	bad_selector.selectors["semantic.act1.loop.core"].erase("compiled_anchor")
	_expect_contains(errors, fidelity.validate_catalog(bad_selector), "compiled_anchor", "applicable selectors require a compiled anchor")
	var bad_transform := catalog.duplicate(true)
	bad_transform.transforms["fictional.gz-positive.1_3333333333@2026-08-09"].axis = "duration_s"
	_expect_contains(errors, fidelity.validate_catalog(bad_transform), "force axis", "transforms cannot scale time")
```

- [ ] **Step 3: Add failing promotion tests**

```gdscript
static func _test_executable_promotion(fidelity: Script, errors: PackedStringArray) -> void:
	var catalog := _valid_catalog_v2()
	catalog.observations.append({
		"id": "tormenta.loop.gz-positive.6383",
		"state": "executable", "source_ids": ["rideforcesdb.tormenta.6383"],
		"source_window_s": [22.94, 27.58], "source_axis": "vertical",
		"mapped_axis": "normal_g", "row_seat": "row 2", "duration_s": 4.64,
		"raw_range": [2.52, 3.84], "transform_id": "fictional.gz-positive.1_3333333333@2026-08-09",
		"confidence": "medium", "confidence_rationale": "exact trace window",
		"corroborating_source_ids": [], "semantic_selector_id": "semantic.act1.loop.core",
		"alignment": {"source_landmark_id":"tormenta.loop.entry", "generated_anchor":{"semantic_selector_id":"semantic.act1.loop.core"}, "method":"element-order-plus-force-shape", "uncertainty_s":0.2, "row_compatibility":"explicit-row-transform", "rationale":"matched entry/exit shoulders"},
	})
	_expect_contains(errors, fidelity.validate_catalog(catalog), "requires corroboration", "corroborative source cannot promote alone")
```

- [ ] **Step 4: Run the focused test and verify schema-v1 code fails**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
```

Expected: failures mention schema version 2, evidence state, digest, and executable promotion.

- [ ] **Step 5: Implement the schema-v2 validator with exact allowed sets**

```gdscript
const EVIDENCE_STATES := ["review_pending", "observation_only", "corroborative", "executable"]
const FORCE_AXES := ["normal_g", "lateral_g", "longitudinal_g"]
const FINDING_STATES := ["within", "under", "over", "observed-only", "evidence-gap"]

static func _valid_sha256(value: Variant) -> bool:
	var text := str(value)
	if text.length() != 64:
		return false
	for character in text:
		if character not in "0123456789abcdef":
			return false
	return true
```

Validate unique IDs across every collection, exact source and semantic-selector references, both selector-anchor branches and their allowed fields, required non-empty `window_role`, legacy role exactly `whole`, source-manifest initial state/permitted contributions/permitted axes, the exact mutually exclusive `acquisition` union and its artifact-or-diagnostic digest pair, retrieval date/context, row/device/sample-rate/axis mapping/reliability/processing/caveats/windows, transform axis/polarity/factor/formula/approval, observation promotion, target-to-executable-observation linkage, and separate raw/target ranges. Reject absolute paths, `res://`/URI paths, and parent traversal. Resolve a validated artifact or diagnostic path for reading with `ProjectSettings.globalize_path("res://../" + repository_path)` in one catalog helper. Every mapped observation requires the complete `alignment` object and compatible source permissions; validate its `generated_anchor.semantic_selector_id`, nonnegative uncertainty, explicit row compatibility, and method. `sample_rate_hz` may be `null` only when the state is not `executable` and the caveat explicitly records it as unknown.

Implement `validate_catalog_artifacts` by selecting exactly the path/hash pair allowed by each source's acquisition branch, globalizing the repository-relative path, hashing its bytes with `HashingContext.HASH_SHA256`, and comparing the lowercase hex digest. Missing files, unreadable files, branch mismatches, and digest mismatches are catalog operational errors. The method performs no network access.

- [ ] **Step 6: Replace `RideFidelityReferences.CATALOG` with the re-adjudicated schema-v2 catalog**

Use the exact source IDs from Task 2. Add one stable `selectors` record per generated element family used by an observation/target, with both legacy and compiled anchors as defined globally. Each observation and target references only `semantic_selector_id`; `compare_fleet` resolves that selector against measurement metadata using the legacy branch before cutover and the compiled branch afterward, clips the selected measurement to the exact role-level native/time/distance window, never rewrites target IDs, and emits an evidence gap when an applicable branch or role does not resolve. Whole-gesture beat aggregation remains unchanged and is not silently substituted for a compiled `core`. Encode the approved value transforms as five unambiguous signed records: Gz+ ×1.3333333333, Gz− ×1.5, Gy+ ×1.5666666667, Gy− ×1.5666666667, and Gx− ×1.7142857143. Transform application preserves the observation sign and only scales magnitude for the declared polarity. Represent identity as `observed.identity@1`; do not create a Gx+ scale transform or a time/geometry transform. Add tests rejecting wrong-polarity application, any Gx+ record, and any transform outside the three force axes. Make qualitative AGL, connective micro-element, coasting-drag, support geometry, and insufficiently aligned transition claims evidence gaps or review prompts rather than numeric targets.

- [ ] **Step 7: Run the focused tests until the committed catalog validates offline**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
```

Expected: exit 0 and no network access.

- [ ] **Step 8: Commit schema and catalog together**

```powershell
git add godot/fidelity_references.gd godot/fidelity.gd godot/fidelity_tests.gd
git commit -m "feat: re-adjudicate fidelity evidence catalog"
```

### Task 4: Correct held, row, pacing, and transition semantics

**Files:**
- Modify: `godot/fidelity.gd`
- Modify: `godot/fidelity_tests.gd`

**Interfaces:**
- Consumes: legacy route dictionaries and schema-v2 observation durations.
- Produces: corrected `held`, `element_bands`, and `measure_route` with physical-time semantics.

- [ ] **Step 1: Add an exact-duration held-value regression**

```gdscript
static func _test_exact_duration_hold(fidelity: Script, errors: PackedStringArray) -> void:
	var exact := PackedFloat32Array()
	exact.resize(81)
	exact.fill(-0.75)
	_expect_close(errors, fidelity.held(exact, -1.0, 0.8), -0.75, "81 samples contain exactly 0.8 seconds at 100 Hz")
	_expect(errors, fidelity.held(exact, -1.0, 0.804) == -INF, "81 samples do not contain a non-grid 0.804-second hold")
	var non_grid := PackedFloat32Array(exact)
	non_grid.append(-0.75)
	_expect_close(errors, fidelity.held(non_grid, -1.0, 0.804), -0.75, "82 samples contain the ceiling interval count for 0.804 seconds")
```

- [ ] **Step 2: Add a moving non-grid seam regression for production measurement.** Build a monotone moving route whose selected beat begins between native 100 Hz timestamps and whose force plateau covers the requested `0.804 s` only after deterministic time interpolation. Assert `measure_route`, not merely direct `held`, samples the selected row/window on a fresh exact 100 Hz grid anchored at its physical start, returns the expected held value, excludes the preceding gesture, and is invariant to extra irregular native samples. Keep the fixture reusable so the later route migration runs the same assertion through `MotionTrajectory.sample_time_into`.

- [ ] **Step 3: Add an irregular-time pacing route and time-weighted expectations**

```gdscript
static func _test_time_weighted_pacing(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _irregular_pacing_route()
	var measured: Dictionary = fidelity.measure_route(route, [0.0])
	_expect_close(errors, measured.beats[0].pacing.dead_zone_share, 0.2 / 1.3, "dead-zone share is weighted by elapsed seconds")
	_expect_close(errors, measured.beats[0].pacing.speed_share_200, 1.1 / 1.3, "speed share is weighted by elapsed seconds")
```

Add `_irregular_pacing_route()` as a complete five-sample route: build fresh five-entry arrays for positions, tangents, ups, rights, curvatures, banks, speeds, three proper-g axes, roll rates, distances, and times; use the exact values in the former inline fixture and one section spanning indices `0..4`. Do not mutate the forty-one-sample `_measurement_route`, because mismatched channel lengths would invalidate the test.

- [ ] **Step 4: Add row-boundary tests at the beginning and end of the closed route**

```gdscript
static func _test_row_windows(fidelity: Script, errors: PackedStringArray) -> void:
	var bands: Array = fidelity.element_bands(_measurement_route(), 2.0)
	_expect_close(errors, bands[0].window_start_distance, 2.0, "rear row begins when it reaches the beat start")
	_expect_close(errors, bands[0].window_end_distance, 22.0, "rear row ends when it reaches the beat end")
	_expect(errors, bands[-1].window_end_distance <= 40.0, "terminal row window is explicitly clipped, not wrapped into an unrelated beat")
```

- [ ] **Step 5: Add a meaningful non-coincident transition-window test**

```gdscript
static func _test_transition_windows(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _transition_route() # helper returns 3.0 seconds at 100 Hz with a seam at 1.5 s
	var measured: Dictionary = fidelity.measure_route(route, [0.0])
	var flow: Dictionary = measured.beats[0].flow
	_expect_close(errors, flow.transition_before_s[0], 1.0, "before window starts 0.5 seconds before seam")
	_expect_close(errors, flow.transition_before_s[1], 1.5, "before window ends at seam")
	_expect_close(errors, flow.transition_after_s[0], 1.5, "after window starts at seam")
	_expect_close(errors, flow.transition_after_s[1], 2.0, "after window ends 0.5 seconds after seam")
	_expect(errors, flow.transition_force_swing > 1.9, "transition compares window extrema, not coincident seam samples")
```

- [ ] **Step 6: Run tests and confirm all five semantics fail against the partial audit code**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
```

- [ ] **Step 7: Correct exact held-window bounds**

```gdscript
static func held(values: PackedFloat32Array, polarity: float, seconds: float) -> float:
	var window := ceili(seconds * Verify.SAMPLE_HZ - 1e-9) + 1
	if window > values.size():
		return -INF
	return Verify._held_curve(values, polarity)[window] * polarity
```

Require finite `seconds > 0.0`, use `<= values.size()` in `_hold_values`, and keep the existing signed-polarity convention. The small epsilon protects exact grid-aligned durations from floating representation; ceiling semantics prevents a non-grid request from accepting a shorter interval. `-INF` remains an internal compatibility sentinel only: `measure_route` converts it to an unavailable metric with reason `insufficient_duration`, omits a numeric value, and `compare_fleet` emits an evidence gap where applicable. No non-finite sentinel enters canonical JSON.

- [ ] **Step 8: Resample every held-force measurement to an exact physical 100 Hz grid.** Before any production call to `held`, derive the selected beat/role and row-shifted physical time bounds, then sample that single force axis at `window_start_s + n / Verify.SAMPLE_HZ` while the timestamp is within the window. Use `MotionTrajectory.sample_time_into` after route migration and deterministic timestamp interpolation for the untouched legacy baseline. Never pass native per-span arrays directly to `held`, concatenate samples across role boundaries, or infer duration from native sample count. Preserve the public `held` primitive and its legacy smoke parity; the resampler is a private measurement detail.

- [ ] **Step 9: Replace sample counts with interval-duration accumulation**

For each interval `i..i+1`, add `dt = times[i + 1] - times[i]` to the metric when the left sample satisfies its predicate, then divide by total positive duration. Keep physical durations in seconds and emit sample counts only as diagnostics.

- [ ] **Step 10: Implement explicit row-window clipping and transition windows**

Add `TRANSITION_WINDOW_SECONDS := 0.5`. Emit `transition_before_s`, `transition_after_s`, maximum force swing between the two window extrema, bank handoff, roll-rate handoff, and `transition_seconds := 1.0` when both full windows exist. Emit an `evidence-gap` measurement reason when route boundaries cannot supply both windows; never silently fall back to coincident seam samples.

- [ ] **Step 11: Run focused tests and smoke**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
```

Expected: all corrected semantics pass; legacy generator behavior and existing smoke bands remain unchanged.

- [ ] **Step 12: Commit corrected measurement semantics**

```powershell
git add godot/fidelity.gd godot/fidelity_tests.gd
git commit -m "fix: measure fidelity in physical time"
```

### Task 5: Add independent force, curvature, and smoothing-integrity reconstruction

**Files:**
- Modify: `godot/fidelity.gd`
- Modify: `godot/fidelity_tests.gd`

**Interfaces:**
- Consumes: route `positions`, `times`, `distances`, `speeds`, `tangents`, `ups`, `rights`, `curvatures`, three proper-g arrays, and `roll_rates`.
- Produces: `reconstruct_channels(route: Dictionary) -> Dictionary`, included in `measure_route`.

- [ ] **Step 1: Add straight, unbounded-radius, and raw-integrity regressions**

```gdscript
static func _test_straight_reconstruction(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _analytic_straight_route(20.0, 2.0, 100.0)
	var before := route.duplicate(true)
	var channels: Dictionary = fidelity.reconstruct_channels(route)
	var repeated: Dictionary = fidelity.reconstruct_channels(route)
	_expect_close(errors, _max_abs(channels.curvature), 0.0, "straight route has zero geometric curvature")
	_expect_close(errors, _array_peak(channels.reconstructed_normal_g), 1.0, "level straight reconstructs one normal g")
	_expect_close(errors, _max_abs(channels.reconstructed_longitudinal_g), 0.0, "constant speed reconstructs zero longitudinal proper g")
	for index in route.positions.size():
		_expect(errors, channels.radius_m[index] == null and channels.radius_unbounded[index], "straight radius is JSON-safe and unbounded")
	_expect(errors, route == before and channels == repeated, "raw reconstruction is read-only and deterministic")
	_expect(errors, not channels.has("comparison_channels"), "raw reconstruction does not invent source filtering")
```

- [ ] **Step 2: Add independent and unclamped circle regressions**

```gdscript
static func _test_constant_radius_reconstruction(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _analytic_circle_route(25.0, 50.0, 4.0, 100.0)
	route.curvatures.fill(Vector3.ZERO)
	var channels: Dictionary = fidelity.reconstruct_channels(route)
	_expect_close_tol(errors, _median_finite(channels.radius_m), 50.0, 0.75, "circle reconstructs geometric radius")
	_expect_close_tol(errors, _median_packed(channels.curvature), 0.02, 0.0003, "circle reconstructs curvature")
	_expect_close(errors, _max_abs_vector(channels.authored_curvature_vector), 0.0, "incorrect authored curvature is preserved separately")
	_expect_close_tol(errors, _median_vector_length(channels.geometric_authored_curvature_error_vector), 0.02, 0.0003, "geometric/authored mismatch is exposed")
```

Also reconstruct a `20,000 m` radius circle and require a finite median near `20,000 m`, never the legacy `10,000 m` clamp and never `radius_unbounded=true`.

- [ ] **Step 3: Add exact force-error and nonuniform derivative regressions**

```gdscript
static func _test_force_integrity_mismatch(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _analytic_circle_route(25.0, 50.0, 4.0, 100.0)
	route.lateral_g.fill(0.0)
	var channels: Dictionary = fidelity.reconstruct_channels(route)
	var expected_lateral := 25.0 * 25.0 / 50.0 / 9.80665
	_expect_close_tol(errors, _median_packed(channels.normal_force_error_g), 0.0, 0.002, "normal force error keeps its axis")
	_expect_close_tol(errors, _median_packed(channels.lateral_force_error_g), expected_lateral, 0.002, "lateral error is reconstructed minus authored")
	_expect_close_tol(errors, channels.force_error_peak_g, expected_lateral, 0.002, "aggregate is the largest absolute axis error")
```

Add an irregular grid at times `[0.0, 0.07, 0.21, 0.5, 0.9, 1.4]` with `x(t)=5t+t²`; every reconstructed acceleration must be `(2,0,0) m/s²` within `0.001`, with jerk below `0.001`. Assert `measure_route` contains exactly one route-level `reconstruction` key.

- [ ] **Step 4: Add a boundary curvature-vector derivative test**

Construct continuous horizontal and vertical `50 m` radius arcs meeting with a common tangent. The second half uses `right=Vector3.LEFT` and `up=vertical_inward`, preserving an orthonormal rider frame. Assert raw/reconstructed curvature-vector and scalar derivatives, authored curvature derivatives, `50 deg/s²` roll acceleration, one stable seam marker, and no `comparison_channels`. Require `authored_curvature_vector_ds[seam].length() > 0.05` while the maximum absolute authored scalar-curvature derivative remains below `0.0001`; this prevents a hidden smoothing pass from erasing a direction jump whose magnitude is unchanged.

- [ ] **Step 5: Commit and push the test-only RED checkpoint**

```powershell
git add docs/superpowers/plans/2026-08-09-evidence-audit-baseline.md godot/fidelity_tests.gd
git commit -m "test: specify raw fidelity reconstruction"
git push
```

Expected: pull-request CI fails because `RideFidelity.reconstruct_channels` is missing; import must still parse. Record the run ID and failing output in the task report before writing production code.

- [ ] **Step 6: Implement reconstruction from generated samples**

Reconstruct geometry independently from raw positions: normalize the nonuniform-distance derivative of position, differentiate that tangent against distance, and reject any residual tangential component. Preserve `route.curvatures` only as a separately labelled authored channel. Emit geometric-versus-authored and force-derived-versus-authored curvature-vector errors so copied or force-fitted curvature cannot pass as an independent geometry measurement.

Reconstruct inertial acceleration directly as the nonuniform-time second derivative of position, subtract gravity, and project proper acceleration into the raw rider frame. Emit per-axis reconstructed-minus-authored force errors; `force_error_peak_g` is the maximum absolute axis error across all samples. Derive the authored-force curvature vector from gravity plus the three authored proper-force axes, reject its tangential component, and divide by validated positive `speed²` without an epsilon denominator repair.

Every derivative uses the original strictly increasing coordinate array and the derivative of the unique local three-point quadratic: centered at interior samples and one-sided at endpoints. Obtain second derivatives directly from that quadratic rather than differentiating a first-derivative array. Apply the same rule to raw curvature-vector/scalar derivatives, roll acceleration, and acceleration-to-jerk differentiation. Preserve sorted unique nonzero section-start seam indices and compact raw seam windows.

Use `CURVATURE_ZERO_EPS := 1e-9`. Straight samples serialize radius as `null` with `radius_unbounded=true`; never emit infinity, clamp radius, or substitute a large finite value. `reconstruct_channels` is raw-only: it must not mutate, filter, fit, smooth, repair, or duplicate `route.positions`. Include one route-level reconstruction in `measure_route`, never one copy per beat.

- [ ] **Step 7: Keep evidence filtering outside raw reconstruction**

`reconstruct_channels(route)` has no catalog input and emits no `comparison_channels`. Later comparison/artifact code may reuse `Verify.filter` only when an observation explicitly names the existing 100 Hz, 5 Hz human-tolerance chain. Such output is labelled `source_filtered` with a stable filter ID and never replaces or feeds positions, frames, curvature, radius, derivatives, acceleration, jerk, or generated raw channels.

- [ ] **Step 8: Commit production and require the GREEN CI gate**

```powershell
git add godot/fidelity.gd
git commit -m "feat: reconstruct route fidelity channels"
git push
```

Expected: the same pull-request CI import, smoke, and viewer job passes. Record its run ID and pristine result in the task report, then self-review the complete two-commit task diff.

### Task 6: Implement deterministic fleet comparison and recommendation

**Files:**
- Modify: `godot/fidelity.gd`
- Modify: `godot/fidelity_tests.gd`

**Interfaces:**
- Consumes: `measure_route` results and schema-v2 catalog.
- Produces: `compare_fleet(seed_measurements, catalog) -> Dictionary`.

- [ ] **Step 1: Extend the catalog contract with only the execution policy comparison needs**

Add mandatory target field `aggregation := {row, beat, seed}`. `row` and `beat` allow
`minimum`, `maximum`, `median`, or `time_weighted_mean`; `seed` allows `minimum`, `maximum`, or
`median`. Reject `sum` and `time_weighted_sum`: they change the metric's units and therefore cannot
be classified against the existing target band. Add mandatory
`observation.alignment.generated_row_selector`, either `null` or exactly one of
`{"row_id": String}`, `{"position": "front"|"intermediate"|"rear"}`, or a finite
`{"offset": float}`. `row-independent` requires `null`; `same-row` and
`explicit-row-transform` require an exact selector. Source `row_seat` remains provenance text and is
never parsed. A held-metric observation/target must use a duration exactly present in
`HOLD_SECONDS`; non-grid durations remain supported by the public `held()` primitive but cannot be
looked up from the fixed measurement dictionary under a rounded alias. Update the strict schema-v2
validation tests before adding comparison tests.

- [ ] **Step 2: Add table-driven classification and normalization tests**

```gdscript
static func _test_target_classification(fidelity: Script, errors: PackedStringArray) -> void:
	for case in [
		{"value": 0.5, "band": [1.0, 2.0], "expected": "under"},
		{"value": 1.5, "band": [1.0, 2.0], "expected": "within"},
		{"value": 2.5, "band": [1.0, 2.0], "expected": "over"},
	]:
		_expect(errors, fidelity.classify_value(case.value, case.band) == case.expected, "classification %s" % case.expected)
```

- [ ] **Step 3: Add exact selector, row, and reduction tests**

Representation is selected only from `measure_route.schema_version`: schema 1 uses `legacy`; schema
2 uses `compiled`; mixed representations reject the comparison. For legacy, `occurrence` is the
zero-based occurrence in measurement order among exact `(phase, kind)` matches, never the stored
phase-wide ordinal. For compiled, match exact non-empty `story_slot_id` plus `window_role`; a
compiled miss never falls back to legacy. Multiple compiled matches are reduced by the declared
beat reducer.

Resolve rows before beats. `row-independent` selects all rows; other compatibility modes require
exactly one matching row. Match IDs and positions exactly and offsets within `0.000001`. A numeric
base sample carries value, beat ID, row ID, and support duration. For held metrics support duration
is the requested `hold_seconds`; for other metrics it is the row's physical `window_seconds`.
Resolution is all-or-nothing across the selected row/beat set: any missing or explicitly unavailable
selected metric makes that target/seed an evidence gap, so a favorable surviving subset is never
reduced. Any non-finite numeric value or duration in fields consumed by comparison is malformed
input and rejects the whole comparison as `measurement-invalid`; it is never recast as an evidence gap. Row-reduced retained duration is the
maximum contributing duration because rows are simultaneous views; beat-reduced duration is their sum. `time_weighted_mean` is
`sum(value * seconds) / sum(seconds)` in stable order.

Table-test every reducer, unequal durations, exact and missing rows, ambiguous rows, legacy
occurrence, compiled roles, no compiled-to-legacy fallback, unavailable held values, and stable
retained-duration arithmetic.

- [ ] **Step 4: Add catalog-driven observed-only and target evidence-gap cases**

Keep result kinds separate. `findings` contains only target comparisons with at least one available
seed. `observed_only` contains successfully resolved numeric samples for catalog observations not
referenced by a target; do not enumerate measurement metrics that have no catalog provenance.
`evidence_gaps` contains at most one record per `(target_id, seed)`, at the first failed stage, with
one of `anchor-not-found`, `row-not-found`, `row-ambiguous`, `metric-not-found`, or
`metric-unavailable`. A target's seed results plus gaps cover the fleet exactly once.

- [ ] **Step 5: Add fleet validation, aggregation, and deterministic ranking tests**

```gdscript
static func _test_recommendation_ranking(fidelity: Script, errors: PackedStringArray) -> void:
	var fleet := _comparison_fleet([11,42,20260809,1,3,7,99,256,555,1234,4096,31337,77777,123456,20250101])
	var comparison: Dictionary = fidelity.compare_fleet(fleet, _comparison_catalog())
	_expect(errors, comparison.fleet == [11,42,20260809,1,3,7,99,256,555,1234,4096,31337,77777,123456,20250101], "canonical fleet order is preserved")
	_expect(errors, comparison.recommendation.target_id == "loads.hill.ejector", "normalized median miss wins deterministic ranking")
	var reversed := fleet.duplicate(true)
	reversed.reverse()
	var reordered: Dictionary = fidelity.compare_fleet(reversed, _comparison_catalog())
	_expect(errors, comparison.findings == reordered.findings, "finding order is independent of input map order")
```

The fleet must contain each canonical seed exactly once. Preserve input order only at top-level
`fleet`; sort all nested seed results numerically. Duplicate, missing, extra, non-integer, malformed,
or mixed-schema inputs reject the whole comparison without partial findings, using exactly
`{"status":"invalid-input","reason":...}` where reason is `catalog-invalid`, `fleet-invalid`,
`measurement-invalid`, or `mixed-representation` in that validation precedence. Beat IDs must be
unique within one seed measurement; row IDs must be unique only within their containing beat and
normally repeat across different beats.

- [ ] **Step 6: Add the eligibility boundary and explicit no-result tests**

`affected_count` counts only `under` and `over`; gaps and `within` remain in the fifteen-seed
prevalence denominator. Recommendation severity is the median normalized miss of affected seeds,
not the separately reported target-declared fleet reduction. Require medium/high confidence and at
least eight affected seeds. Seven misses are ineligible; eight are eligible; low confidence is
always ineligible. An empty eligible set emits exactly `{"status":"no-eligible-finding"}`.

- [ ] **Step 7: Run tests remotely and verify comparison APIs fail**

```powershell
git push
gh run watch --exit-status
```

Do not launch local Godot on this machine. Record the failing GitHub Actions run and confirm the
failure is caused by the absent comparison contract, not a fixture or parser defect.

- [ ] **Step 8: Implement the minimum comparison pipeline**

```gdscript
static func normalized_miss(value: float, target_range: Array) -> float:
	var distance := 0.0
	if value < float(target_range[0]):
		distance = float(target_range[0]) - value
	elif value > float(target_range[1]):
		distance = value - float(target_range[1])
	var denominator := maxf(0.1, maxf(absf(float(target_range[0])), maxf(absf(float(target_range[1])), float(target_range[1]) - float(target_range[0]))))
	return distance / denominator
```

Implement three small private stages: resolve selector/rows, reduce declared values/durations, and
build one target finding. Pre-index catalog records once; do not add a generic scoring or query
framework. Classification is numeric and inclusive at both endpoints. Reduce rows, then beats, then
the available seed values for the reported `fleet_value`/`fleet_status`. Ranking remains independent
of that fleet reducer.

- [ ] **Step 9: Emit the exact deterministic result algebra without an overall score**

Return `{fleet, findings, observed_only, evidence_gaps, recommendation}`. Every finding contains
target/observation IDs; sorted unique primary and corroborating source IDs/caveats; transform and
semantic-selector IDs; dimension/metric/hold duration; resolved branch, anchor, row compatibility,
and row selector; declared aggregation; raw/target bands; seed-sorted results with values, statuses,
misses, retained seconds, beat IDs, and row IDs; fleet value/status; total retained seconds; affected,
available, and gap counts; prevalence; normalized median miss; and observation confidence.

Sort findings by target ID, observed-only records by `(observation_id, seed, beat_id, row_id)`, gaps
by `(target_id, seed)`, and nested identifiers lexicographically. Rank eligible findings by normalized
median miss descending, prevalence descending, confidence high before medium, then target ID
ascending. Emit either a compact `recommended` projection or exact no-result object. Recursively
forbid `score`, `total_score`, and any weighted cross-dimension scalar.

- [ ] **Step 10: Push GREEN and verify focused tests and smoke in GitHub Actions**

```powershell
git push
gh run watch --exit-status
```

Confirm import, focused fidelity tests through smoke, the unchanged seed sweep, and viewer all pass.

- [ ] **Step 11: Commit the comparison engine**

```powershell
git add godot/fidelity.gd godot/fidelity_tests.gd
git commit -m "feat: compare deterministic fidelity fleet"
```

### Required checkpoint after Task 6: consolidate before adding evidence or artifacts

The Task 6 review exposed avoidable repetition in the shared fidelity core and tests. Before adding
any tracked POV data or Task 7 code, perform one behavior-preserving deletion pass under
`AGENTS.md`: unify the duplicate time/distance interpolation path, replace repeated catalog and fleet
fixtures with readable data-driven cases, remove guards that only tested APIs already made
mandatory by earlier RED commits, narrow only metrics already rejected by `_metric_axis`, and keep smoke
delegation thin. Do not shorten files by packing assertions onto long lines, splitting files, weakening
tests, or changing seeds, tolerances, physics, smoothing, radii, selectors, schemas, or gates.

- [ ] Modify exactly `godot/fidelity.gd`, `godot/fidelity_tests.gd`, and `godot/smoke.gd`. At code
  baseline `eb8b639e6e394d85877784a691703b6c4d14e03e` they contain 2,361 + 2,079 + 991 =
  5,431 physical lines, counted with `[IO.File]::ReadAllLines((Resolve-Path $file)).Count`.
  Require a final total no greater than 5,331; 5,266–5,311 is the reviewed safe target, not a quota
  that permits obscurity.
- [ ] Keep `DIMENSIONS` unchanged. Shallow-copy only the two catalog arrays used solely for sorting;
  all returned defensive fields and every per-seed fleet template remain deeply isolated.
- [ ] Keep multi-error, precedence, artifact-I/O, and positive validation controls explicit. Every
  data-driven single-mutation case retains a readable name, fresh deep-copied catalog, exact
  mutation, and expected diagnostic substring.
- [ ] Remove API guards only by making every required API call unconditional. Add one nested
  per-seed fixture-isolation assertion and one assertion that comparison neither reorders the catalog
  nor exposes returned fields that can mutate it.
- [ ] Refresh Graphify first and use only source-backed dependency paths; retain the recorded warning
  that no compare-to-artifact edge exists until Task 7.
- [ ] Treat GitHub Actions run 39 (`31389177890`) as the green before-state, then run the same import,
  focused suite, unchanged smoke/seed sweep, and viewer workflow remotely after the refactor.
- [ ] Obtain an independent scoped review confirming semantic parity, readable tests, and no hidden
  ride-behavior or threshold change.
- [ ] Commit only the three files above as `refactor: consolidate fidelity measurement scaffolding`
  before starting the POV RED commit.

### Required checkpoint between Tasks 6 and 7: commit the reviewed live POV landmarks

This is a separate TDD slice because it shares `fidelity_tests.gd` with Task 6. Modify only the four
YouTube `*-review.json` files for `J54WKu2nU6o`, `sdXGD9kMR7s`, `poco8rOnW18`, and
`0UaOSBGSx20`; `docs/evidence/fidelity/source-manifest.json`;
`docs/evidence/fidelity/catalog-review.md`; `godot/fidelity_references.gd`; and
`godot/fidelity_tests.gd`. Preserve every source state and permission ceiling, empty permitted axes
and mappings, null sample rates, empty alignments/selectors/observations/targets, independent source
clocks, and the absence of any duration scaling or generated mapping. Do not change runtime,
generator, viewer, verifier, or CI behavior.

- [ ] **Step 1: Commit and push focused RED regressions before changing evidence data**

Require exact ordered landmark IDs and source-local `time_s` values in each review file and its
catalog-window mirror:

```text
J54: j54.station_dispatch=0.07, j54.park_straight=29.99, j54.park_bank=59.07,
     j54.rocky_descent=89.18, j54.elevated_crest=120.71, j54.steep_segment=139.36,
     j54.park_return=159.43, j54.support_passage=179.50, j54.station_return=219.65
sdX: sdx.station_dispatch=0.07, sdx.park_straight=28.93, sdx.park_bank=58.81,
     sdx.rock_face_pitch=88.87, sdx.cliff_edge=118.94, sdx.elevated_crest=138.86,
     sdx.low_terrain_turn=158.97, sdx.park_run=178.88, sdx.station_return=218.91
poco: poco.opening=0.10, poco.park_element=43.63, poco.desert_curve=88.56,
      poco.elevated_arch=133.76, poco.supported_grade=148.74, poco.low_return=163.71,
      poco.virtual_pov_start=170.69, poco.steep_ascent=178.69, poco.rocky_ascent=223.89,
      poco.modeled_hill=268.82, poco.park_return=314.02
0Ua: 0ua.station_dispatch=0.06, 0ua.park_straight=25.25, 0ua.park_hill_turn=49.171226,
     0ua.cliff_approach=74.18, 0ua.high_terrain_turn=100.45, 0ua.cliff_descent=124.37,
     0ua.fast_park_return=149.39, 0ua.compact_park_descent=174.40,
     0ua.station_return=204.44
```

Also require exact durations/publish dates `(240.881, 2026-01-05)`,
`(239.061, 2026-01-01)`, `(328.521, 2023-06-04)`, and `(213.541, 2026-04-14)` in that
source order; the reviewed built/rear-facing, built/front-row-view, NoLimits2-precreation/mixed, and
built/leading-view classifications with conservative obstruction/mount caveats; and exact
non-promotion invariants. Tests must fail on the stale committed catalog. File SHA-256 values are
integrity checks recomputed from final bytes; correctness comes from direct assertions over the
exact structured review fixture below, never from a manifest/file self-match alone.

Use these exact landmark descriptions in the same order as the ID/time lists above:

```text
J54: Covered station corridor with track centered in the rear-facing view. |
     Open-air straight beside park buildings and walkways. |
     Strongly banked park turn among illuminated supports. |
     Banked descending turn through dark rocky terrain. |
     Large elevated crest silhouetted against the night sky. |
     Extremely steep track segment; travel direction is ambiguous in the rear-facing still. |
     Banked return toward the illuminated park. |
     Tilted passage through dense supports and park structures. |
     Brake/return track entering the station area.
sdX: Dark station dispatch corridor with the leading car nose visible. |
     Straight beside park buildings approaching a tall inclined section; editorial length card visible. |
     Banked compact park element among dense supports. |
     Steeply pitched track beside a rock face. |
     High cliff-edge view over the park and track below. |
     Elevated crest with strong sun glare. |
     Low banked terrain turn past supports and buildings. |
     Elevated park run through a hill-and-turn section. |
     Brake/return track inside the blue-lit station.
poco: Black opening frame. |
      Third-person train view in a compact modeled park element. |
      Third-person banked curve over modeled desert terrain. |
      Third-person profile of a large elevated arch. |
      Third-person train on a long highly supported grade. |
      Third-person low return track through the modeled park. |
      First sampled virtual POV frame toward a tall inclined element. |
      Virtual POV on a very steep ascent. |
      Virtual POV ascending through modeled rocky terrain. |
      Virtual POV approaching a large triangular-supported hill. |
      Virtual POV in a banked compact modeled park return.
0Ua: Station attendant dispatch. |
     Straight away from the station toward a tall inclined section. |
     Compact park hill and turn. |
     Long approach toward the cliff and terrain section. |
     Lower-speed banked turn on the high desert terrain. |
     Steep cliff descent toward a tunnel. |
     Fast park return with large hills visible. |
     Compact descent between park buildings. |
     Brake/return run approaching the station.
```

The exact `view` objects are:

```json
{"content_kind":"built-ride","direction":"rear-facing","position_claim":"centered rear-facing view; exact row undisclosed","mount":"unknown","obstructions":["lower-right watermark","night exposure","motion blur","rapid camera roll"],"certainty":"high for ride identity and orientation; medium for element shaping from sparse night frames"}
{"content_kind":"built-ride","direction":"forward","position_claim":"front-row view per title over the leading car nose; exact mount undisclosed","mount":"unknown","obstructions":["leading car nose","curved windshield or bar","lower-right watermark","sun glare","lens or dust spots"],"certainty":"high for ride identity and stated front-row orientation; medium for exact element interpretation"}
{"content_kind":"nolimits2-precreation","direction":"mixed","position_claim":"mixed third-person and virtual POV; not an as-built camera","mount":"not-applicable","obstructions":["synthetic low-detail terrain and scenery","lower-right watermark"],"certainty":"high for precreation status; low for as-built correspondence"}
{"content_kind":"built-ride","direction":"forward","position_claim":"leading-view appearance consistent with front row; exact row undisclosed","mount":"unknown","obstructions":["leading car nose and curved bar","edge gauges and bottom graph","lower-left seat model","right-side readouts","central watermark","sun glare"],"certainty":"high for synchronized overlay presence; medium for physical accuracy because of uploader limitations"}
```

Every `provenance.live_review` object has exact keys `reviewed_on`, `method`, `time_basis`,
`retained_frame_or_video`, and `correction_review`. Their common values are `2026-08-10`,
`visible live YouTube player, media-element currentTime readback, and expanded description; sparse manual sampling only`,
`source-local media-element seconds`, and `false`; correction status is `pass` only for 0Ua and
`not-applicable` for the other three. Keep the existing parent `provenance.video_downloaded: false`.

- [ ] **Step 2: Transcribe only the reviewed sparse evidence and prompts**

Keep schema `fidelity-youtube-review@1`. Add the reviewed metadata, source-local live-review
provenance, view classification, and exact point landmarks. Every landmark is exactly
`{id, time_s, description, provenance, rendered_readouts}` with provenance
`live-player-currentTime-readback`. Commit numeric readouts only for these three sign-reviewed
uploader labels, without a mapped rider axis:

```json
{"label":"Long.","display_value":-0.30,"unit":"g","qualifier":"approximate-unmapped-uploader-display","adjacent_range":[]}
{"label":"Long.","display_value":-0.19,"unit":"g","qualifier":"approximate-unmapped-uploader-display","adjacent_range":[]}
{"label":"Long.","display_value":-0.58,"unit":"g","qualifier":"approximate-unmapped-uploader-display","adjacent_range":[-0.58,-0.57]}
```

They belong respectively to `0ua.park_hill_turn`, `0ua.fast_park_return`, and
`0ua.compact_park_descent`. Record the uploader sensor/edit/sampling caveats; do not commit the
unre-reviewed adjacent `Vert.` or `Lat.` values. Update the four review SHA-256 values in the
manifest and catalog, bump the catalog version once, mirror the point windows, replace stale
"metadata only" claims, and update the adjudication log.

Add exactly two unscored prompts: `review.coastertalk_overlay_spot_checks`, category `ride feel`,
sources `[youtube.coastertalk.continuous.0Ua]`, issues `[3,10,13,15,16]`; and
`review.terrain_clearance`, category `terrain/clearance`, sources
`[youtube.coastertalk.continuous.0Ua,youtube.falcon.backward.J54WKu2nU6o,youtube.falcon.sdXGD9kMR7s]`,
issues `[6,8,12]`. Their prose must explicitly forbid treating the spot checks as a calibrated trace
or band and forbid proportional alignment of independent video clocks or inference of an AGL band.

Replace the existing prompt/gap prose with these exact strings:

```text
review.ride_feel: Compare generated act ordering and connective flow against source-local POV landmarks only; do not transfer timestamps or proportionally scale independent video clocks.
review.speed_perception: Compare generated speed perception against source-local terrain, support, and park-reference landmarks only; do not infer speed from a global POV duration ratio.
gap.force_bands: Sparse rendered video points lack raw sampling, device/row calibration, rider-axis mapping, full source-to-generated alignment, and corroboration; no multiplier or duration ratio closes those gaps.
```

Other catalog prose may reuse the exact provenance/view/description strings above but must add no
new fact. It is not a byte-exact test surface. The RED fixture pins structured fields, ordered
landmarks, the exact prompt/gap strings above, and non-promotion invariants; artifact validation
separately recomputes each manifest SHA-256 from the checked-in review bytes.

- [ ] **Step 3: Push GREEN and verify through GitHub Actions**

Catalog and artifact validation must pass; all four exact landmark sets, three negative readouts,
metadata/classifications/hashes, and empty executable collections must pass. Import, existing smoke
and seed sweep, and viewer must remain green. Never run local Godot.

- [ ] **Step 4: Commit the evidence refresh**

```powershell
git add docs/evidence/fidelity/youtube/J54WKu2nU6o-review.json `
  docs/evidence/fidelity/youtube/sdXGD9kMR7s-review.json `
  docs/evidence/fidelity/youtube/poco8rOnW18-review.json `
  docs/evidence/fidelity/youtube/0UaOSBGSx20-review.json `
  docs/evidence/fidelity/source-manifest.json docs/evidence/fidelity/catalog-review.md `
  godot/fidelity_references.gd godot/fidelity_tests.gd
git commit -m "docs: record reviewed POV landmarks"
```

### Task 7: Build deterministic reports and checked diagnostic artifacts

**Files:**
- Create: `godot/canonical_data.gd`
- Create: `godot/route_sampling.gd`
- Create: `godot/fidelity_artifacts.gd`
- Create: `godot/fidelity_artifact_tests.gd`
- Modify: `godot/_inspect.gd`
- Modify: `godot/main.gd`
- Modify: `godot/smoke.gd`

**Interfaces:**
- Consumes: measured legacy route dictionaries, comparison, schema-v2 catalog, pinned `legacy_base_commit`, externally observed `generation_counts`, existing inspector rendering behavior.
- Produces: one narrow `CanonicalData` serializer/hash utility, `ride-fidelity-audit@1`, `fidelity-artifact-manifest@1`, `fidelity-pov-map@1`, and `fidelity-issue-coverage@1` reports, plus the checked audit/POV/PNG pack under `INSPECT_OUT`.

`build_report` never infers generation work from measurements. Its fifth argument is the counter
dictionary collected by Task 8's build spy. It must have only `String` keys, with a key set exactly
equal to the report fleet mapped through `str(seed)`, and every value must have integer type and
value `1`. Reject rather than coerce non-string keys, missing or extra keys, and non-integer `1`
values. Synthetic Task 7 fixtures supply that exact shape; Task 8 passes
`_run_audit(...).generation_counts` unchanged. A successful report retains an isolated exact copy
as top-level JSON-only operational provenance. Task 7B copies that field unchanged into the
manifest; neither stage reconstructs counters from the fleet or measurements.

Execute Task 7 as three sequential reviewed TDD slices. Task 7A owns canonical serialization and
complete pure report construction, including POV mappings/gaps, checklist, issue coverage, render
requests, deterministic text, and permanent artifact-suite registration during RED. Task 7B owns
CPU rendering, beat/span resolution, checked text/PNG pack writes, and manifest-last assembly from
reopened bytes. Task 7C owns inspector delegation and retains the final smoke registration unchanged.
This is the sole sequencing exception. These slices must not introduce renderer injection or partial
report/manifest contracts merely to manufacture an intermediate GREEN state.

Task 7A's pure report contract is exact:

- `generation_counts` is the isolated exact copy of the validated fifth argument. It has one
  String key per fleet seed and integer value `1`; it is present in canonical JSON but does not add
  a Markdown section.
- Every measurement's `beat_id` values are unique. A resolved POV center-row window is finite and
  satisfies `0 <= start < end <= measurement.duration`; both its POV-map record and render request
  carry `generated_time_s = start + (end - start) * 0.5`. Identical path/payload intents deduplicate,
  while a conflicting same-path payload is invalid.
- Comparison keys are proven String/exact without sorting unvalidated Variants. Each projected
  generated anchor is constructed as exactly `{"semantic_selector_id": <matching selector ID>}`;
  source-landmark and POV-record time dictionaries are independently owned.
- Each `measurement_summaries` entry has exact top-level keys `{schema_version, seed, length,
  duration, dimensions, beats, force_error_peak_g, reconstruction_seam_count}`.
  `force_error_peak_g` copies `measurement.reconstruction.force_error_peak_g`;
  `reconstruction_seam_count` is `measurement.reconstruction.seam_indices.size()`. Omit the
  `reconstruction` key and every other reconstruction member.
- `evidence_snapshot` contains one record for every `catalog.sources` entry, sorted by `source_id`.
  Each record contains `source_id`, `state`, optional `acquisition` only when present in the catalog,
  every present path/hash pair from `artifact`, `diagnostic`, `metadata_artifact`,
  `metadata_diagnostic`, and `review`, and `fallback_citations` only when present. It contains no
  URL, windows, axes, processing, caveats, or invented acquisition value.
- Exact equality with the successful fixture's ordered issue IDs 1-16 proves that constructed output
  has no missing or duplicate record. Public-input negative fixtures cover an out-of-range catalog
  issue ID and an issue whose union of linked IDs and generated paths is empty. Do not expose a
  coverage validator or add test-only injection solely to manufacture malformed output records.
- The literal expected Markdown in the valid RED fixture is normative. Its section order is
  Identity, Fleet, Measurements, Findings, Observed only, Evidence gaps, Recommendation, Evidence
  snapshot, POV map, Checklist, Issue coverage, Render requests; rows follow the already-contracted
  array orders.
- Task 7A physical-line review thresholds are 55 soft / 80 absolute for `canonical_data.gd`, a
  reviewed structural landing forecast of 735-750 / 750 absolute for `fidelity_artifacts.gd`, 766
  absolute for the focused regression suite after final review fixes, and exactly two
  added `smoke.gd` lines.
  These are stops, not quotas; never pack lines, couple expected values to fixtures, weaken
  mutations, or add generic schema machinery to meet them. Further test growth requires structural
  deletion or an explicit reviewed contract amendment.

- [ ] **Step 1: Create the SceneTree runner and add canonical JSON/Markdown ordering tests**

The runner checks `ResourceLoader.exists` for `res://canonical_data.gd` and `res://fidelity_artifacts.gd`, reports the missing production scripts, and returns before loading them. Once present, it loads both scripts, calls every focused test, prints errors in stable order, and exits nonzero on failure.

```gdscript
static func _test_canonical_reports(canonical_data: Script, artifacts: Script, errors: PackedStringArray) -> void:
	var report := {"schema_version":"ride-fidelity-audit@1", "catalog":{"schema_version":2,"catalog_version":"test","canonical_sha256":"a".repeat(64)}, "findings":[{"target_id":"z"},{"target_id":"a"}], "fleet":[11,42,20260809,1], "evidence_snapshot":[]}
	var reordered := {"evidence_snapshot":[], "fleet":[11,42,20260809,1], "findings":[{"target_id":"z"},{"target_id":"a"}], "catalog":{"canonical_sha256":"a".repeat(64),"catalog_version":"test","schema_version":2}, "schema_version":"ride-fidelity-audit@1"}
	var json_a: String = canonical_data.canonical_json(report)
	var json_b: String = canonical_data.canonical_json(reordered)
	_expect(errors, json_a == json_b, "dictionary insertion order does not affect canonical JSON")
	_expect(errors, artifacts.canonical_json(report) == json_a, "artifact serialization delegates to CanonicalData")
	_expect(errors, json_a.contains('"fleet":[11,42,20260809,1]'), "canonical fleet order is preserved")
	_expect(errors, not json_a.contains(Time.get_datetime_string_from_system()), "report contains no runtime timestamp")
```

- [ ] **Step 2: Add checked-write failure tests**

```gdscript
static func _test_checked_write_failure(artifacts: Script, errors: PackedStringArray) -> void:
	var failures: PackedStringArray = artifacts.write_text_checked("Z:/path-that-does-not-exist/audit.json", "{}\n")
	_expect(errors, not failures.is_empty(), "failed report write is operationally visible")
	_expect_contains(errors, failures, "artifact_write", "write failure has a distinct category")
```

- [x] **Step 3: Add a manifest and preserved-output test**

Require these stable outputs:

```text
audit.json
audit.md
manifest.json
review/pov-map.json
review/pov-map.md
review/checklist.md
review/issue-coverage.json
review/issue-coverage.md
review/seed-11/channels.png
review/seed-11/channels.json
review/seed-11/channels.md
review/seed-11/top.png
review/seed-11/elevation.png
review/seed-42/channels.png
review/seed-42/channels.json
review/seed-42/channels.md
review/seed-42/top.png
review/seed-42/elevation.png
review/seed-20260809/channels.png
review/seed-20260809/channels.json
review/seed-20260809/channels.md
review/seed-20260809/top.png
review/seed-20260809/elevation.png
review/seed-42/elements/<stable-beat-id>.png
review/seed-42/pov/<stable-beat-id>.png
```

Keep each logical `beat_id` unchanged in JSON. For element and POV filename stems only, replace
every `/` with `__`; the generated beat grammar cannot contain underscores, so this projection is
reversible. Task 7A emits the projected request path, and Task 7B recomputes and validates it rather
than repairing a mismatched request.

`audit.json` records the exact pinned `legacy_base_commit`, audit schema, catalog schema/version/canonical
SHA-256, catalog validation result, and a sorted `evidence_snapshot`. Every referenced source snapshot
records source ID, state, acquisition only when present, every present repository-relative
artifact/diagnostic/review path and SHA-256 pair, and exact structured fallback citations only when
present; it never claims an unavailable raw artifact. The manifest has exact top-level keys
`{schema_version, generation_counts, files}` and copies `report.generation_counts` unchanged; it
never infers generation work from fleet or route data. Every file record has exact keys
`{path, kind, artifact_kind, byte_size, sha256, seed, beat_id, width, height}`. `kind` is one of
`json`, `markdown`, or `png`; `artifact_kind` is one of `audit`, `pov-map`, `checklist`,
`issue-coverage`, `channels`, `top`, `elevation`, `element`, or `pov`. Use explicit `null` for
inapplicable seed/beat/dimensions. Sort records by forward-slash relative path; populate size/hash
and PNG dimensions from reopened bytes. Write `manifest.json` last and exclude it from `files` to
avoid recursive self-hashing. Tests assert the old side/top/elevation/channel capability still exists.

- [ ] **Step 4: Permanently register the artifact suite and confirm GitHub RED**

Preload `FidelityArtifactTests` in `smoke.gd` and append `FidelityArtifactTests.run()` immediately
after `FidelityTests.run()`. Keep both lines through Task 7C. The guarded runner must report both
missing production scripts before attempting to load either one.

```sh
godot --headless --path godot --script res://smoke.gd
```

Expected GitHub RED diagnostics, in order: `CanonicalData is missing`, then
`RideFidelityArtifacts is missing`. Do not add a workflow step or run local Godot.

- [ ] **Step 5: Create or reuse the narrow `CanonicalData` utility and delegate all report serialization to it**

```gdscript
class_name CanonicalData
extends RefCounted

static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var output := {}
		var keys := value.keys()
		keys.sort()
		for key in keys:
			output[key] = _canonical(value[key])
		return output
	if value is Array:
		var output := []
		for item in value:
			output.append(_canonical(item))
		return output
	return value

static func canonical_json(value: Variant) -> String:
	return JSON.stringify(_canonical(value), "", false, true) + "\n"

static func sha256_text(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()
```

Canonicalization sorts dictionary keys only. Arrays already carrying semantic order—including `fleet`—must remain in their supplied order. Findings are sorted before report construction by their stable contract. `RideFidelityArtifacts.canonical_json(value)` is only `return CanonicalData.canonical_json(value)`; it must not carry a second `_canonical` implementation. Later foundation/config/catalog/report code reuses this same utility instead of introducing another canonical JSON encoder.
Before serialization, recursively reject non-finite numeric values. `null` is legal only where the report schema explicitly declares absence, including `radius_m[i] == null` paired with `radius_unbounded[i] == true`; it is never a stand-in for malformed arithmetic.

- [x] **Step 6: Implement checked text and PNG writes**

```gdscript
static func write_text_checked(path: String, content: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("artifact_write: cannot open '%s': %s" % [path, error_string(FileAccess.get_open_error())])
		return errors
	file.store_string(content)
	file.close()
	var verify := FileAccess.get_file_as_string(path)
	if verify != content:
		errors.append("artifact_write: byte verification failed for '%s'" % path)
	return errors

static func save_png_checked(image: Image, path: String) -> PackedStringArray:
	var error := image.save_png(path)
	return PackedStringArray() if error == OK and FileAccess.file_exists(path) and FileAccess.get_file_as_bytes(path).size() > 0 else PackedStringArray(["artifact_write: PNG failed '%s' (%s)" % [path, error_string(error)]])
```

- [x] **Step 7: Move existing render logic behind `RideFidelityArtifacts` without deleting capability**

Keep side/profile, top, elevation, and the existing speed/normal/lateral/pitch/roll-rate/AGL strips.
Add longitudinal proper-g, reconstructed curvature, radius, roll-acceleration, and jerk strips. Keep
the PNG traces font-free. Task 7B computes each image and its `fidelity-channel-legend@1` record from
one shared channel descriptor, then writes stable adjacent `channels.json` and `channels.md`
sidecars. Each legend binds image path, seed, dimensions, and eleven ordered strips with stable ID,
index, label, unit, finite plotted min/max, bounded/unbounded counts, and exactly one
`raw_generated` series with the existing `[0.55,0.95,1.0,1.0]` RGBA trace color;
`source_filtered` is absent in this baseline. Include the checked
sidecars in the manifest. Do not add an embedded glyph table, font rasterizer, text-layout helper,
or label asset, and do not duplicate channel calculations across Tasks 7A/7B. Use stable beat-ID
filenames rather than sample indices.

The canonical legend has exact keys/types
`{schema_version:String,image_path:String,seed:int,width:int,height:int,strips:Array}` with
`schema_version: "fidelity-channel-legend@1"`, an audit-root-relative forward-slash image path,
`width: 1400`, and `height: 1650`. Each strip has exact keys/types
`{index:int,channel_id:String,label:String,unit:String,plot_min:float,plot_max:float,bounded_count:int,unbounded_count:int,series:Array}`.
Finite values define the bounded count and exact min/max; a constant finite channel uses
`plot_max = plot_min + 0.001`; an all-unbounded channel uses `[0.0,1.0]` and a nonzero unbounded
count. The sole series is exactly
`{"role":"raw_generated","color_rgba":[0.55,0.95,1.0,1.0]}`. Strip order is:

```text
0 | speed_kmh | Speed | km/h
1 | normal_g | Normal proper acceleration | g
2 | lateral_g | Lateral proper acceleration | g
3 | longitudinal_proper_g | Longitudinal proper acceleration | g
4 | pitch_deg | Pitch | deg
5 | roll_rate_dps | Roll rate | deg/s
6 | agl_m | Height above ground | m
7 | reconstructed_curvature_inv_m | Reconstructed curvature | 1/m
8 | radius_m | Radius | m
9 | roll_acceleration_dps2 | Roll acceleration | deg/s^2
10 | jerk_mps3 | Inertial jerk magnitude | m/s^3
```

The jerk strip is the unfiltered Euclidean length of each vector in
`reconstruction.jerk_mps3`; it is non-negative and does not invent a privileged rider-frame axis.

`channels.md` is a pure projection of the reopened canonical JSON: fixed title
`# Channel legend — seed <seed>`, an image line with path and `<width>x<height>`, then one
fixed-column table row per strip in array order containing every strip field and the series
role/RGBA. Format floats with six digits after the decimal point. A synthetic eleven-strip golden
JSON fixture and exact Markdown string pin keys, order, relative path, numeric formatting,
all-unbounded radius behavior, and the absence of `source_filtered`.

- [x] **Step 8: Add synchronized POV mappings and generated POV frames**

`pov-map.json` carries `schema_version: "fidelity-pov-map@1"`. Successful records come only from
validated observation `alignment` objects and link source ID, source landmark, alignment
method/uncertainty/row compatibility, observation and selector IDs, generated seed, generated
anchor/stable beat ID/window, arithmetic-midpoint `generated_time_s`, and relative generated-POV
PNG. Source time is a tagged union that
preserves exactly one catalog form: `{"kind":"point","time_s":...}` or
`{"kind":"window","window_s":[...]}`; never turn a point into an invented interval or rescale a
source window. Every generated window satisfies finite
`0 <= start < end <= measurement.duration`; Task 7B consumes the recorded midpoint without
reinterpreting the window. Every YouTube source with declared landmarks but no aligned observation emits one
source-level `alignment-not-present` gap, carrying no invented observation, selector, generated
timestamp, or PNG request. Observation-driven gaps remain distinct. Sort landmarks and gaps by
stable IDs. `pov-map.md` presents the same data.

Extract the viewer's exact lower-index, time-to-distance, and quaternion-slerped pose interpolation
into pure `RouteSampling`; keep `main.gd`'s existing static methods as thin delegates and pin parity
before/after. `RideFidelityArtifacts` depends on the neutral utility, never on `main.gd`, and does not
substitute the force verifier's intentionally different private field interpolation. Render the
recorded midpoint with a fixed neutral perspective camera: `1440x900`, vertical FOV `72` degrees,
near `0.08 m`, far `5000 m`, center-row route basis, and eye position
`pose.origin + pose.basis.y * 0.35`. Do not apply the viewer's speed-dependent FOV widening. Render
the generic track/terrain inspection layer only; do not embed source-video frames.

- [x] **Step 9: Add the unscored review checklist and complete issue 1–16 traceability**

Write exactly five ordered checklist sections for shaping, feel, speed perception,
terrain/clearance, and support overlap. Every prompt is catalog-owned: map catalog category
`terrain/clearance` to checklist ID `terrain-clearance` just as the other four reviewed categories
map to their checklist IDs; do not invent a fixed implementation prompt. Each category must receive
at least one catalog prompt, and each prompt links evidence IDs and generated artifacts but carries
no numeric score. Emit one ordered issue-coverage record for every integer ID 1 through 16, with
issue text, linked measurement/target/evidence IDs, generated artifact paths, and exactly one
top-level state of `measured`, `review-prompt`, or `evidence-gap`. A record may link many findings,
but each issue ID appears once and none may be omitted. Pin exact successful issue IDs 1-16, and add
failing public-input tests for an out-of-range catalog issue ID and an issue whose linked-ID/path
union is empty, including direct fixtures for entry-launch speed (9), flats (12), multidimensional
scaling (14), and transition jerk (15).

Keep `markdown(report)` and `write_pack(...)` as the only public text/pack APIs. Private shared body
appenders project POV map, checklist, and issue coverage for both aggregate `audit.md` and their
standalone Markdown files; the pack writer never revisits catalog/comparison inputs or adds separate
public formatter methods.

- [x] **Step 10: Retain the pre-registered artifact suite and run the focused and smoke gates**

Task 7C adds inspector delegation only. It must not re-register or otherwise alter the smoke harness;
the unchanged smoke command continues to execute both focused suites before generator checks.

```sh
godot --headless --path godot --script res://smoke.gd
```

Verify this command through GitHub Actions only; do not launch local Godot.

- [x] **Step 11: Commit report and artifact support**

```powershell
git add godot/canonical_data.gd godot/fidelity_artifacts.gd godot/fidelity_artifact_tests.gd godot/_inspect.gd godot/smoke.gd
git commit -m "feat: write checked fidelity review artifacts"
```

### Task 8: Run the exact fifteen-seed baseline once per seed

**Files:**
- Modify: `godot/_inspect.gd`
- Modify: `godot/fidelity_artifact_tests.gd`

**Interfaces:**
- Consumes: `RideGenerator.build`, `RideElements.ROW_OFFSETS`, validated catalog, `measure_route`, `compare_fleet`, and `RideFidelityArtifacts`.
- Produces: complete deterministic baseline pack and generation work counters.

- [ ] **Step 1: Add the canonical fleet constant and one-build spy test**

```gdscript
const AUDIT_SEEDS := [11, 42, 20260809, 1, 3, 7, 99, 256, 555, 1234, 4096, 31337, 77777, 123456, 20250101]

static func _test_one_build_per_seed(runner: Callable, errors: PackedStringArray) -> void:
	var calls := {}
	var build := func(seed_value: int) -> Dictionary:
		calls[seed_value] = int(calls.get(seed_value, 0)) + 1
		return {"seed": seed_value}
	var measure := func(route: Dictionary) -> Dictionary: return {"seed": route.seed}
	var compare := func(measurements: Array) -> Dictionary: return {"fleet": measurements.map(func(item): return item.seed)}
	var report: Dictionary = runner.call(AUDIT_SEEDS, build, measure, compare)
	_expect(errors, report.fleet == AUDIT_SEEDS, "report preserves canonical fleet")
	for seed_value in AUDIT_SEEDS:
		_expect(errors, calls.get(seed_value, 0) == 1, "seed %d is generated once" % seed_value)
```

The spy also asserts that the returned `generation_counts` has exactly the fleet mapped to String
keys and that every value is integer `1`.

- [ ] **Step 2: Implement `_run_audit(seeds, build_route, measure_route, compare_fleet)` as injectable orchestration**

```gdscript
static func _run_audit(seeds: Array, build_route: Callable, measure_route: Callable, compare_fleet: Callable) -> Dictionary:
	var measurements := []
	var routes_by_seed := {}
	var generation_counts := {}
	for seed_value in seeds:
		var route: Dictionary = build_route.call(seed_value)
		generation_counts[str(seed_value)] = int(generation_counts.get(str(seed_value), 0)) + 1
		measurements.append(measure_route.call(route))
		if seed_value in [11, 42, 20260809]:
			routes_by_seed[seed_value] = route
	var comparison: Dictionary = compare_fleet.call(measurements)
	return {"fleet": seeds.duplicate(), "measurements": measurements, "comparison": comparison, "routes_by_seed": routes_by_seed, "generation_counts": generation_counts}
```

Production calls `_run_audit(AUDIT_SEEDS, RideGenerator.build, func(route): return RideFidelity.measure_route(route, RideElements.ROW_OFFSETS), func(measurements): return RideFidelity.compare_fleet(measurements, RideFidelityReferences.CATALOG))`.

Pass the returned `audit.generation_counts` once to `build_report(...)`, then call
`write_pack(output_dir, report, audit.routes_by_seed)`. The pack writer consumes only the validated
copy retained in `report.generation_counts`.

Do not build deep-review seeds a second time; retain those three already-built route dictionaries only until artifact writing completes.

- [ ] **Step 3: Make operational errors fail and fidelity misses remain diagnostic**

Before generation, validate the catalog and artifact root. During generation, record distinct `generation`, `physical_consistency`, and `artifact_write` errors with catalog version and seed. A comparison result containing `under` or `over` findings still exits 0 when all operational work succeeds.

- [ ] **Step 4: Run the focused one-build test**

```powershell
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_artifact_tests.gd'
```

- [ ] **Step 5: Run two clean full audits**

```powershell
$workspace = (Resolve-Path '.').Path
$env:INSPECT_OUT = Join-Path $workspace 'out\fidelity-baseline-a'
& $portableGodot --headless --path '.\godot' --script 'res://_inspect.gd'
if ($LASTEXITCODE -ne 0) { throw "baseline A failed: $LASTEXITCODE" }
$env:INSPECT_OUT = Join-Path $workspace 'out\fidelity-baseline-b'
& $portableGodot --headless --path '.\godot' --script 'res://_inspect.gd'
if ($LASTEXITCODE -ne 0) { throw "baseline B failed: $LASTEXITCODE" }
```

- [ ] **Step 6: Compare deterministic text artifacts byte for byte**

```powershell
$textArtifacts = @(
  'audit.json','audit.md','manifest.json','review\pov-map.json','review\pov-map.md',
  'review\checklist.md','review\issue-coverage.json','review\issue-coverage.md',
  'review\seed-11\channels.json','review\seed-11\channels.md',
  'review\seed-42\channels.json','review\seed-42\channels.md',
  'review\seed-20260809\channels.json','review\seed-20260809\channels.md'
)
foreach ($relative in $textArtifacts) {
  $a = [IO.File]::ReadAllBytes((Join-Path 'out\fidelity-baseline-a' $relative))
  $b = [IO.File]::ReadAllBytes((Join-Path 'out\fidelity-baseline-b' $relative))
  if ($a.Length -ne $b.Length -or [Convert]::ToHexString($a) -cne [Convert]::ToHexString($b)) {
    throw "non-deterministic artifact: $relative"
  }
}
```

- [ ] **Step 7: Verify the artifact manifest and generated images**

```powershell
$manifest = Get-Content -Raw 'out\fidelity-baseline-a\manifest.json' | ConvertFrom-Json
$expectedCountKeys = @(
  '11','42','20260809','1','3','7','99','256','555','1234',
  '4096','31337','77777','123456','20250101'
) | Sort-Object
$actualCountKeys = @($manifest.generation_counts.PSObject.Properties.Name | Sort-Object)
if (Compare-Object $expectedCountKeys $actualCountKeys) { throw 'generation-count seed set is incomplete' }
if (($manifest.generation_counts.PSObject.Properties | Where-Object Value -ne 1).Count -ne 0) { throw 'a seed was generated more than once' }
if (($manifest.files | Where-Object { -not (Test-Path -LiteralPath (Join-Path 'out\fidelity-baseline-a' $_.path)) }).Count -ne 0) { throw 'manifest references a missing artifact' }
if ($manifest.schema_version -ne 'fidelity-artifact-manifest@1') { throw 'unexpected manifest schema' }
if (($manifest.files | Where-Object kind -eq 'png').Count -lt 12) { throw 'review PNG pack is incomplete' }
```

- [ ] **Step 8: Inspect fresh seed-11, seed-42, and seed-20260809 channel/top/elevation images, seed-42 profiles, and generated POV frames**

Check that every image is non-empty, legible when paired with its canonical sidecar legend, contains
the one declared raw-generated trace, and has no clipped trace or blank viewport. Review
`pov-map.md` against each linked generated frame and source timestamp. Record post-run human
observations in `out/fidelity-baseline-a/manual-inspection.md`, explicitly outside the deterministic
manifest/text comparison; generated `audit.md` remains canonical and contains prompts/results only.
Do not convert subjective checks into scores.

- [ ] **Step 9: Run required import, focused tests, and smoke from clean portable app-data directories**

```powershell
& $portableGodot --headless --path '.\godot' --editor --quit
if ($LASTEXITCODE -ne 0) { throw "Godot import failed: $LASTEXITCODE" }
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
if ($LASTEXITCODE -ne 0) { throw "fidelity tests failed: $LASTEXITCODE" }
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_artifact_tests.gd'
if ($LASTEXITCODE -ne 0) { throw "artifact tests failed: $LASTEXITCODE" }
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
if ($LASTEXITCODE -ne 0) { throw "smoke failed: $LASTEXITCODE" }
```

- [ ] **Step 10: Commit the completed runner**

```powershell
git add godot/_inspect.gd godot/fidelity_artifact_tests.gd
git commit -m "feat: audit fixed fifteen-seed baseline"
```

### Task 9: Document and adversarially review the baseline gate

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `docs/ISSUES.md`
- Review: all files changed by Tasks 1–8 and ignored artifacts under `out/fidelity-baseline-a/`.

**Interfaces:**
- Consumes: verified audit command and output contract.
- Produces: durable operator instructions and a final evidence-backed baseline ready before generator behavior changes.

Treat source and test line-count growth as a first-class review concern. Against exact authoritative
baseline `1b612990edbf52a1ce0f7e4e9149192376b7efad`, report numstat for every changed `.gd` file and
flag any production file above 1,000 physical lines or test file above 1,500. Each flagged file needs
a reviewer-recorded keep/simplify decision; any actionable simplify decision blocks completion until
implemented and reverified. File splitting and line minification do not count as reduction.

- [ ] **Step 1: Add the exact offline audit command and output contract to `README.md`**

Document the portable command from Task 8, `INSPECT_OUT`, the fixed fleet order, JSON/Markdown/manifest and review-pack paths, offline behavior, and the rule that fidelity misses do not fail while malformed evidence/generation/physics/write failures do.

- [ ] **Step 2: Update `CLAUDE.md` architecture notes without claiming the legacy ride is correct**

State that `_inspect.gd` preserves the existing diagnostic images and now adds reconstructed longitudinal/curvature/radius/roll-acceleration/jerk channels, evidence-linked review prompts, explicit POV mapping gaps, and checked writes. Keep the approved force-informed hybrid design authoritative: FVD is preferred where it gives superior rider-dynamics control, not forced onto layout, terrain, closure, or exact-geometry work better solved by another physically coherent method.

- [ ] **Step 3: Update open-issues audit and promotion guidance**

For issues 1–16, link the deterministic `review/issue-coverage.json`/Markdown artifacts without
marking a ride-quality issue solved from a diagnostic result alone. Document that a finding becomes
a future hard gate only through a new Superpowers design cycle with reviewed executable evidence,
an explicit threshold and scope, a focused failing test, and proof that the promoted gate does not
reward geometry smoothing, radius manipulation, or hidden drive.

- [ ] **Step 4: Scan for forbidden live-network runtime dependencies and overall scores**

```powershell
$networkCodeHits = rg -n 'HTTPRequest|HTTPClient|WebSocketPeer|WebSocketMultiplayerPeer|StreamPeerTCP' godot --glob '*.gd'
if ($networkCodeHits) { throw "runtime network dependency found:`n$networkCodeHits" }
$urlCodeHits = rg -n 'https?://' godot --glob '*.gd' --glob '!fidelity_references.gd'
if ($urlCodeHits) { throw "URL outside the provenance catalog found:`n$urlCodeHits" }
$scoreHits = rg -n 'overall[_ -]?score|total[_ -]?score' godot docs/evidence/fidelity
if ($scoreHits) { throw "forbidden overall fidelity score found:`n$scoreHits" }
```

URLs are allowed only in `fidelity_references.gd` as inert provenance strings. The class scan rejects executable network clients independently of literal provenance.

- [ ] **Step 5: Inspect the final diff for behavior changes**

```powershell
git diff --stat 1b612990edbf52a1ce0f7e4e9149192376b7efad..HEAD
git diff 1b612990edbf52a1ce0f7e4e9149192376b7efad..HEAD -- godot/generator.gd godot/elements.gd godot/main.gd godot/terrain.gd godot/verify.gd
```

Expected: the second command is empty. If it is not, revert the out-of-scope behavior change and rerun Task 8 verification.

- [ ] **Step 6: Adversarially review evidence and math**

Check every executable observation against its committed artifact, exact window, row, axis, processing, transform, confidence, and corroboration. Recompute at least one held value, one time-weighted share, one row shift, one transition window, one curvature/radius case, and one normalized miss independently. Confirm stable IDs and finding order, canonical fleet order, one build per seed, checked writes, and no smoothed geometry path.

- [ ] **Step 7: Run the final fresh verification commands**

```powershell
& $portableGodot --headless --path '.\godot' --editor --quit
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://fidelity_artifact_tests.gd'
& $portableGodot --headless --path '.\godot' --script 'res://smoke.gd'
```

- [ ] **Step 8: Commit operator documentation**

```powershell
git add README.md CLAUDE.md docs/ISSUES.md
git commit -m "docs: document offline fidelity baseline"
```

- [ ] **Step 9: Record the final handoff condition**

The next ride-behavior plan may start only when: catalog validation passes offline; the exact fleet is generated once; two audits have byte-identical JSON, Markdown, and manifests; all manifest files exist and hash correctly; fresh POV/PNG artifacts were visually inspected; import, focused tests, and smoke pass; and the diff contains no generator, elements, viewer, terrain, or verifier behavior change.
