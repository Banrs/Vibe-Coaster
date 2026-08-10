extends SceneTree

const CANONICAL_PATH := "res://canonical_data.gd"
const ARTIFACTS_PATH := "res://fidelity_artifacts.gd"
const REFERENCES_PATH := "res://fidelity_references.gd"
const LEGACY_BASE_COMMIT := "3fa14885bef2daf3a7d9c0e544424cb6a296fd99"


func _initialize() -> void:
	var errors := run()
	for error in errors:
		printerr(error)
	quit(0 if errors.is_empty() else 1)


static func run() -> PackedStringArray:
	var errors := PackedStringArray()
	if not ResourceLoader.exists(CANONICAL_PATH):
		errors.append("CanonicalData is missing")
	if not ResourceLoader.exists(ARTIFACTS_PATH):
		errors.append("RideFidelityArtifacts is missing")
	if not errors.is_empty():
		return errors
	var canonical_data: Script = load(CANONICAL_PATH)
	var artifacts: Script = load(ARTIFACTS_PATH)
	var references: Script = load(REFERENCES_PATH)
	_test_canonical_data(canonical_data, artifacts, errors)
	_test_successful_report(artifacts, errors)
	_test_invalid_inputs(artifacts, errors)
	_test_committed_catalog(artifacts, references, errors)
	_test_element_render_request_filter(artifacts, errors)
	_test_center_row_alignment_selectors(artifacts, errors)
	return errors


static func _test_canonical_data(
	canonical_data: Script, artifacts: Script, errors: PackedStringArray
) -> void:
	var report := {
		"schema_version": "ride-fidelity-audit@1",
		"findings": [{"target_id": "z"}, {"target_id": "a"}],
		"fleet": [11, 42, 20260809, 1],
		"legal": {"null": null, "bool": true},
	}
	var reordered := {
		"legal": {"bool": true, "null": null},
		"fleet": [11, 42, 20260809, 1],
		"findings": [{"target_id": "z"}, {"target_id": "a"}],
		"schema_version": "ride-fidelity-audit@1",
	}
	var json_a: String = canonical_data.canonical_json(report)
	_expect(errors, json_a == canonical_data.canonical_json(reordered),
		"dictionary insertion order does not affect canonical JSON")
	_expect(errors, artifacts.canonical_json(report) == json_a,
		"artifact serialization delegates to CanonicalData")
	_expect(errors, json_a.contains('"fleet":[11,42,20260809,1]'),
		"canonical JSON preserves semantic array order")
	_expect(errors, json_a.contains('"legal":{"bool":true,"null":null}'),
		"recursive canonicalization accepts and orders null and booleans")
	_expect(errors, json_a.ends_with("\n") and not json_a.ends_with("\n\n"),
		"canonical JSON has exactly one final LF")
	_expect(errors, canonical_data.canonical_json({"bad": INF}) == "",
		"non-finite floats are rejected")
	_expect(errors, canonical_data.canonical_json({7: "bad"}) == "",
		"non-String dictionary keys are rejected")
	_expect(errors, canonical_data.canonical_json(Vector3.ZERO) == "",
		"unsupported Variant types are rejected")
	_expect(errors, canonical_data.sha256_text("abc") ==
		"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
		"SHA-256 hashes the exact supplied UTF-8 text")


static func _test_successful_report(artifacts: Script, errors: PackedStringArray) -> void:
	var actual: Dictionary = _build(artifacts, _valid_fixture())
	_expect(errors, actual == _expected_report(),
		"valid inputs produce the complete pure report contract")
	_expect(errors, artifacts.markdown(actual) == EXPECTED_MARKDOWN,
		"Markdown is the normative literal projection")

	var fixture := _valid_fixture()
	var before := fixture.duplicate(true)
	var report_a: Dictionary = _build(artifacts, fixture)
	var report_b: Dictionary = _build(artifacts, _reverse_dictionaries(fixture))
	_expect(errors, fixture == before, "report construction does not mutate public inputs")
	_expect(errors, report_a == report_b,
		"input dictionary insertion order does not affect report values")

	var source_fixture := _valid_fixture()
	var source_report: Dictionary = _build(artifacts, source_fixture)
	source_fixture.comparison.findings[0].metric = "changed"
	source_fixture.seed_measurements[1].dimensions.width = 99.0
	source_fixture.seed_measurements[1].beats[0].kind = "changed"
	source_fixture.catalog.sources["source.raw"].fallback_citations[0].section_id = "changed"
	source_fixture.catalog.sources["source.raw"].windows[1].window_s[0] = 9.0
	source_fixture.catalog.observations[0].alignment.generated_anchor.semantic_selector_id = "changed"
	source_fixture.generation_counts["42"] = 2
	_expect(errors, source_report == _expected_report(), "caller nested mutations do not change the completed report")
	var report_fixture := _valid_fixture()
	var mutable_report: Dictionary = _build(artifacts, report_fixture)
	mutable_report.findings[0].metric = "changed"
	mutable_report.measurement_summaries[1].dimensions.width = 99.0
	mutable_report.measurement_summaries[1].beats[0].kind = "changed"
	mutable_report.evidence_snapshot[0].fallback_citations[0].section_id = "changed"
	mutable_report.pov_map.source_landmarks[1].source_time.window_s[0] = 9.0
	_expect(errors, mutable_report.pov_map.records[1].source_time.window_s[0] == 2.0, "source times are independent")
	mutable_report.pov_map.records[0].generated_anchor.semantic_selector_id = "changed"
	_expect(errors, report_fixture == _valid_fixture(), "completed-report nested mutations do not change caller inputs")


static func _test_invalid_inputs(artifacts: Script, errors: PackedStringArray) -> void:
	var cases := [
		["measurement schema missing", "schema_version",
			func(value: Dictionary): value.seed_measurements[0].erase("schema_version")],
		["measurement schema type", "schema_version",
			func(value: Dictionary): value.seed_measurements[0].schema_version = "2"],
		["measurement schema is supported", "schema_version",
			func(value: Dictionary): value.seed_measurements[0].schema_version = 3],
		["measurement seed is required", "measurement seed",
			func(value: Dictionary): value.seed_measurements[0].erase("seed")],
		["measurement length is required", "measurement",
			func(value: Dictionary): value.seed_measurements[0].erase("length")],
		["measurement length is numeric", "measurement",
			func(value: Dictionary): value.seed_measurements[0].length = "111"],
		["measurement duration is required", "measurement",
			func(value: Dictionary): value.seed_measurements[0].erase("duration")],
		["measurement duration is numeric", "measurement",
			func(value: Dictionary): value.seed_measurements[0].duration = "11"],
		["measurement duration is finite", "measurement",
			func(value: Dictionary): value.seed_measurements[0].duration = NAN],
		["measurement dimensions missing", "measurement",
			func(value: Dictionary): value.seed_measurements[0].erase("dimensions")],
		["measurement dimensions type", "measurement",
			func(value: Dictionary): value.seed_measurements[0].dimensions = []],
		["measurement beats are required", "measurement",
			func(value: Dictionary): value.seed_measurements[0].erase("beats")],
		["measurement beats have Array type", "measurement",
			func(value: Dictionary): value.seed_measurements[0].beats = {}],
		["measurement reconstruction is required", "reconstruction",
			func(value: Dictionary): value.seed_measurements[0].erase("reconstruction")],
		["measurement reconstruction has Dictionary type", "reconstruction",
			func(value: Dictionary): value.seed_measurements[0].reconstruction = []],
		["force missing", "force",
			func(value: Dictionary): value.seed_measurements[0].reconstruction.erase("force_error_peak_g")],
		["force type", "force",
			func(value: Dictionary): value.seed_measurements[0].reconstruction.force_error_peak_g = "0.01"],
		["force finite", "force",
			func(value: Dictionary): value.seed_measurements[0].reconstruction.force_error_peak_g = NAN],
		["seams missing", "seam",
			func(value: Dictionary): value.seed_measurements[0].reconstruction.erase("seam_indices")],
		["measurement seams type", "seam",
			func(value: Dictionary): value.seed_measurements[0].reconstruction.seam_indices = {}],
		["base commit must be lowercase 40-hex", "legacy_base_commit",
			func(value: Dictionary): value.legacy_base_commit = "ABC"],
		["comparison has the exact Task 6 algebra", "comparison",
			func(value: Dictionary): value.comparison[7] = true],
		["Task 6 members cannot be missing", "comparison",
			func(value: Dictionary): value.comparison.erase("findings")],
		["Task 6 members have contracted types", "comparison",
			func(value: Dictionary): value.comparison.observed_only = {}],
		["comparison projections must be JSON-safe", "comparison",
			func(value: Dictionary): value.comparison.findings[0].metric = INF],
		["measurement summaries must be finite", "measurement",
			func(value: Dictionary): value.seed_measurements[0].length = INF],
		["measurement seeds are unique", "duplicate measurement seed",
			func(value: Dictionary): value.seed_measurements[3].seed = 11],
		["measurement seeds must be integers", "measurement seed",
			func(value: Dictionary): value.seed_measurements[0].seed = 11.0],
		["measurement seeds match fleet", "measurement seeds",
			func(value: Dictionary): value.seed_measurements[3].seed = 7],
		["required seed 11 cannot be replaced consistently", "deep seed",
			func(value: Dictionary): _replace_seed(value, 11, 7)],
		["required seed 42 cannot be replaced consistently", "deep seed",
			func(value: Dictionary): _replace_seed(value, 42, 7)],
		["deep seed 20260809 is mandatory", "deep seed",
			func(value: Dictionary): value.comparison.fleet[2] = 7],
		["counter keys are Strings", "generation_counts",
			func(value: Dictionary): value.generation_counts = {11: 1, "42": 1, "20260809": 1, "1": 1}],
		["counter keys cannot be missing", "generation_counts",
			func(value: Dictionary): value.generation_counts.erase("11")],
		["counter key set rejects extras", "generation_counts",
			func(value: Dictionary): value.generation_counts["extra"] = 1],
		["counter values have integer type", "generation_counts",
			func(value: Dictionary): value.generation_counts["42"] = 1.0],
		["every seed was generated exactly once", "generation_counts",
			func(value: Dictionary): value.generation_counts["42"] = 2],
		["catalog identity fields are guarded", "catalog",
			func(value: Dictionary): value.catalog.schema_version = "2"],
		["catalog canonicalization rejects unconsumed NAN", "canonical",
			func(value: Dictionary): value.catalog["unconsumed"] = NAN],
		["catalog record containers are guarded", "catalog",
			func(value: Dictionary): value.catalog.observations = {}],
		["source windows are guarded", "source",
			func(value: Dictionary): value.catalog.sources["source.raw"].windows[0] = {}],
		["source-ID arrays are guarded", "source",
			func(value: Dictionary): value.catalog.review_prompts[0].source_ids = PackedStringArray(["source.raw"])],
		["compiled anchor guard", "anchor",
			func(value: Dictionary): value.catalog.selectors["selector.loop"].compiled_anchor = {}],
		["alignments are guarded", "alignment",
			func(value: Dictionary): value.catalog.observations[0].alignment = null],
		["generated anchor selector matches observation selector", "generated_anchor",
			func(value: Dictionary): value.catalog.observations[0].alignment.generated_anchor.semantic_selector_id = "wrong"],
		["generated anchor has exact members", "generated_anchor",
			func(value: Dictionary): value.catalog.observations[0].alignment.generated_anchor["extra"] = true],
		["measurement beats are guarded", "beat",
			func(value: Dictionary): value.seed_measurements[1].beats[0] = []],
		["measurement beat IDs are unique per seed", "duplicate measurement beat",
			func(value: Dictionary): value.seed_measurements[1].beats.append(
				{"beat_id": "act-one/00/loop", "kind": "brake_run"})],
		["projected beat render paths conflict",
			"artifact_report: render request path has conflicting payload: review/seed-42/elements/act-one__00__loop.png",
			func(value: Dictionary): _append_copy(value.seed_measurements[1].beats, 0, {"beat_id": "act-one__00__loop"})],
		["measurement rows are guarded", "row",
			func(value: Dictionary): value.seed_measurements[1].beats[0].rows[0] = []],
		["generated POV row windows reject equal endpoints", "measurement row window",
			func(value: Dictionary): value.seed_measurements[1].beats[0].rows[0].window_end_s = 10.1],
		["generated POV row windows reject reversed endpoints", "measurement row window",
			func(value: Dictionary): value.seed_measurements[1].beats[0].rows[0].window_start_s = 12.0],
		["generated POV row windows stay within measurement duration", "measurement row window",
			func(value: Dictionary): value.seed_measurements[1].beats[0].rows[0].window_end_s = 12.1],
		["required projection leaf guard", "state",
			func(value: Dictionary): value.catalog.sources["source.raw"].erase("state")],
		["observation source links resolve", "observation",
			func(value: Dictionary): value.catalog.observations[0].source_id = "missing"],
		["target observation links resolve", "target",
			func(value: Dictionary): value.catalog.targets[0].observation_id = "missing"],
		["prompt source links resolve", "prompt",
			func(value: Dictionary): value.catalog.review_prompts[0].source_ids = ["missing"]],
		["gap source links resolve", "gap",
			func(value: Dictionary): value.catalog.evidence_gaps[0].source_ids = ["missing"]],
		["all five checklist categories are present", "checklist category",
			func(value: Dictionary): value.catalog.review_prompts.pop_back()],
		["catalog issue IDs stay in 1 through 16", "issue",
			func(value: Dictionary): value.catalog.review_prompts[0].issues = [17]],
		["every issue has at least one traceability link", "issue 7",
			func(value: Dictionary): value.catalog.evidence_gaps[0].issues.erase(7)],
		["aligned landmarks resolve", "source_landmark_id",
			func(value: Dictionary): value.catalog.observations[0].alignment.source_landmark_id = "missing"],
		["aligned selectors resolve", "semantic_selector_id",
			func(value: Dictionary): value.catalog.observations[0].semantic_selector_id = "missing"],
		["center-row POV resolution requires a zero-offset row", "row",
			func(value: Dictionary): value.seed_measurements[1].beats[0].rows[0].offset = 2.0],
		["center-row POV resolution rejects distinct ambiguous rows", "row",
			func(value: Dictionary): _append_copy(value.seed_measurements[1].beats[0].rows, 0, {"row_id": "row-center-2"})],
		["center-row POV resolution rejects identical ambiguous rows", "row",
			func(value: Dictionary): _append_copy(value.seed_measurements[1].beats[0].rows, 0, {})],
	]
	_expect_invalid_cases(artifacts, errors, cases)
	var multiple := _valid_fixture()
	multiple.legacy_base_commit = "BAD"
	multiple.generation_counts["42"] = 2
	var result: Dictionary = _build(artifacts, multiple)
	var sorted_errors: Array = result.get("errors", []).duplicate()
	sorted_errors.sort()
	_expect(errors, result.keys().size() == 2 and result.status == "invalid-input",
		"invalid reports return only status and errors")
	_expect(errors, result.errors == sorted_errors and result.errors.size() >= 2,
		"all invalid-input diagnostics are stable and sorted")


static func _test_committed_catalog(
	artifacts: Script, references: Script, errors: PackedStringArray
) -> void:
	var fixture := _valid_fixture()
	fixture.catalog = references.CATALOG
	fixture.comparison = {
		"fleet": [11, 42, 20260809, 1], "findings": [], "observed_only": [],
		"evidence_gaps": [], "recommendation": {"status": "no-eligible-finding"},
	}
	var report: Dictionary = _build(artifacts, fixture)
	var expected_gap_ids := []
	for source_id in fixture.catalog.sources:
		if str(source_id).begins_with("youtube.") and not fixture.catalog.sources[source_id].windows.is_empty():
			expected_gap_ids.append("%s/alignment-not-present" % source_id)
	expected_gap_ids.sort()
	var actual_gap_ids: Array = report.get("pov_map", {}).get("gaps", []).map(
		func(gap: Dictionary): return gap.get("id"))
	_expect(errors, actual_gap_ids == expected_gap_ids,
		"committed source-level no-alignment gaps are complete and sorted")
	_expect(errors, report.get("pov_map", {}).get("records", []).is_empty(),
		"committed unaligned catalog produces no POV mappings")
	_expect(errors, report.get("render_requests", []).filter(
		func(request: Dictionary): return request.get("artifact_kind") == "pov").is_empty(),
		"committed unaligned catalog produces no POV PNG requests")


static func _test_element_render_request_filter(artifacts: Script, errors: PackedStringArray) -> void:
	var fixture := _valid_fixture()
	for kind in ["hill", "immelmann", "cutback", "twisted_drop", "dive", "wave_turn", "overbank", "turn", "brake_run"]:
		_append_copy(fixture.seed_measurements[1].beats, 0, {
			"beat_id": "beat-%s" % kind, "kind": kind, "story_slot_id": "act1.%s" % kind,
		})
	var actual := []
	for request in _build(artifacts, fixture).get("render_requests", []):
		if request.get("artifact_kind") == "element":
			actual.append(request.get("beat_id"))
	_expect(errors, actual == ["act-one/00/loop", "beat-cutback", "beat-dive", "beat-hill",
		"beat-immelmann", "beat-overbank", "beat-turn", "beat-twisted_drop", "beat-wave_turn"],
		"only the exact nine retained side-view beat kinds produce element render requests")


static func _test_center_row_alignment_selectors(artifacts: Script, errors: PackedStringArray) -> void:
	for selector in [{"row_id": "row-edge"}, {"position": "front"}, {"offset": 2.0}, null]:
		var fixture := _valid_fixture()
		fixture.seed_measurements[1].beats[0].rows.append({
			"row_id": "row-edge", "position": "front", "offset": 2.0,
			"window_start_s": 8.0, "window_end_s": 9.0,
		})
		fixture.catalog.observations[0].alignment.generated_row_selector = selector
		if selector == null:
			fixture.catalog.observations[0].alignment.row_compatibility = "row-independent"
		var records: Array = _build(artifacts, fixture).get("pov_map", {}).get("records", [])
		_expect(errors, records.size() == 2 and records[0].generated_window_s == [10.1, 11.9]
			and records[0].generated_time_s == 11.0,
			"every valid evidence row selector resolves the unique zero-offset POV center row")


static func _expect_invalid_cases(
	artifacts: Script, errors: PackedStringArray, cases: Array
) -> void:
	for case in cases:
		var fixture := _valid_fixture()
		var mutate: Callable = case[2]
		mutate.call(fixture)
		var result: Dictionary = _build(artifacts, fixture)
		_expect(errors, result.get("status") == "invalid-input", case[0])
		_expect_contains(errors, result.get("errors", []), case[1], case[0])


static func _build(artifacts: Script, fixture: Dictionary) -> Dictionary:
	return artifacts.build_report(
		fixture.seed_measurements, fixture.comparison, fixture.catalog,
		fixture.legacy_base_commit, fixture.generation_counts
	)


static func _replace_seed(value: Dictionary, old_seed: int, new_seed: int) -> void:
	value.seed_measurements[value.comparison.fleet.find(old_seed)].seed = new_seed
	value.comparison.fleet[value.comparison.fleet.find(old_seed)] = new_seed
	value.generation_counts[str(new_seed)] = value.generation_counts[str(old_seed)]
	value.generation_counts.erase(str(old_seed))


static func _append_copy(values: Array, index: int, overrides: Dictionary) -> void:
	var copy: Dictionary = values[index].duplicate(true)
	copy.merge(overrides, true)
	values.append(copy)

static func _valid_fixture() -> Dictionary:
	var measurements := []
	for seed in [11, 42, 20260809, 1]:
		measurements.append({
			"schema_version": 2,
			"seed": seed,
			"length": float(seed % 100 + 100),
			"duration": float(seed % 10 + 10),
			"dimensions": {"width": 40.0, "height": 30.0},
			"beats": [],
			"reconstruction": {
				"force_error_peak_g": 0.01,
				"seam_indices": PackedInt32Array([2, 5]),
				"unsupported": Vector3.ONE,
			},
		})
	measurements[1].beats = [{
		"beat_id": "act-one/00/loop", "story_slot_id": "act1.loop",
		"window_role": "core", "kind": "loop", "window_s": [10.0, 12.0],
		"rows": [{
			"row_id": "row-02", "position": "intermediate",
			"offset": 0.0, "window_start_s": 10.1, "window_end_s": 11.9,
		}],
	}]
	return {
		"legacy_base_commit": LEGACY_BASE_COMMIT,
		"seed_measurements": measurements,
		"generation_counts": {"11": 1, "42": 1, "20260809": 1, "1": 1},
		"comparison": {
			"fleet": [11, 42, 20260809, 1],
			"findings": [{"target_id": "target.load", "metric": "normal_peak_positive"}],
			"observed_only": [{"observation_id": "obs.point", "seed": 42, "value": 1.5}],
			"evidence_gaps": [{"target_id": "target.load", "seed": 1, "reason": "row-not-found"}],
			"recommendation": {"status": "recommended", "target_id": "target.load"},
		},
		"catalog": _valid_catalog(),
	}


static func _valid_catalog() -> Dictionary:
	return {
		"schema_version": 2, "catalog_version": "test",
		"selectors": {"selector.loop": {
			"compiled_anchor": {"story_slot_id": "act1.loop", "window_role": "core"},
		}},
		"sources": {
			"source.raw": {
				"state": "executable", "acquisition": "raw",
				"artifact_path": "evidence/raw.json", "artifact_sha256": "a".repeat(64),
				"diagnostic_path": "evidence/raw-diagnostic.json", "diagnostic_sha256": "f".repeat(64),
				"metadata_artifact_path": "evidence/raw-metadata.json", "metadata_artifact_sha256": "9".repeat(64),
				"review_path": "evidence/raw-review.json", "review_sha256": "b".repeat(64),
				"fallback_citations": [{
					"document": "docs/TELEMETRY.md", "section_id": "fixture",
					"source_windows_used": [[1.25, 3.0]],
				}],
				"url": "https://example.invalid/raw", "processing": ["excluded"],
				"windows": [
					{"id": "landmark.point", "time_s": 1.25},
					{"id": "landmark.window", "window_s": [2.0, 3.0]},
				],
			},
			"youtube.unaligned": {
				"state": "observation_only",
				"metadata_diagnostic_path": "evidence/video-diagnostic.json",
				"metadata_diagnostic_sha256": "d".repeat(64),
				"review_path": "evidence/video-review.json",
				"review_sha256": "e".repeat(64),
				"video_id": "video", "windows": [{"id": "video.crest", "time_s": 4.0}],
			},
		},
		"observations": [
			_aligned_observation("obs.point", "landmark.point"),
			_aligned_observation("obs.window", "landmark.window"),
		],
		"targets": [{
			"id": "target.load", "observation_id": "obs.window",
			"semantic_selector_id": "selector.loop", "issues": [1, 9],
		}],
		"review_prompts": [
			_prompt("prompt.shaping", "shaping", [2, 14]),
			_prompt("prompt.feel", "feel", [3, 15]),
			_prompt("prompt.speed", "speed perception", [4, 9]),
			_prompt("prompt.terrain", "terrain/clearance", [5, 12]),
			_prompt("prompt.support", "support overlap", [6, 16]),
		],
		"evidence_gaps": [{
			"id": "gap.unmeasured", "description": "No executable evidence.",
			"source_ids": ["youtube.unaligned"], "issues": [7, 8, 9, 10, 11, 12, 13, 15],
		}],
	}


static func _aligned_observation(observation_id: String, landmark_id: String) -> Dictionary:
	return {
		"id": observation_id, "source_id": "source.raw",
		"semantic_selector_id": "selector.loop",
		"alignment": {
			"source_landmark_id": landmark_id,
			"generated_anchor": {"semantic_selector_id": "selector.loop"},
			"method": "fixture alignment", "uncertainty_s": 0.1,
			"row_compatibility": "same-row",
			"generated_row_selector": {"row_id": "row-02"},
		},
	}


static func _prompt(prompt_id: String, category: String, issues: Array) -> Dictionary:
	return {
		"id": prompt_id, "category": category, "prompt": "Review %s." % category,
		"source_ids": ["source.raw"], "issues": issues,
	}


static func _expected_report() -> Dictionary:
	var issue_records := []
	for issue_id in range(1, 17):
		issue_records.append(_expected_issue(issue_id))
	return {
		"schema_version": "ride-fidelity-audit@1",
		"legacy_base_commit": "3fa14885bef2daf3a7d9c0e544424cb6a296fd99",
		"catalog": {
			"schema_version": 2, "catalog_version": "test",
			"canonical_sha256": "fd2fb5d8ae1cd756bc501f32ac9951479c13b7c1d7e915be9974fb1a5c06a285", "validation_status": "valid",
		},
		"fleet": [11, 42, 20260809, 1],
		"generation_counts": {"11": 1, "42": 1, "20260809": 1, "1": 1},
		"measurement_summaries": [
			_measurement_summary(11, 111.0, 11.0, []),
			_measurement_summary(42, 142.0, 12.0, [{
				"beat_id": "act-one/00/loop", "story_slot_id": "act1.loop",
				"window_role": "core", "kind": "loop", "window_s": [10.0, 12.0],
				"rows": [{
					"row_id": "row-02", "position": "intermediate",
					"offset": 0.0, "window_start_s": 10.1, "window_end_s": 11.9,
				}],
			}]),
			_measurement_summary(20260809, 109.0, 19.0, []),
			_measurement_summary(1, 101.0, 11.0, []),
		],
		"findings": [{"target_id": "target.load", "metric": "normal_peak_positive"}],
		"observed_only": [{"observation_id": "obs.point", "seed": 42, "value": 1.5}],
		"evidence_gaps": [{"target_id": "target.load", "seed": 1, "reason": "row-not-found"}],
		"recommendation": {"status": "recommended", "target_id": "target.load"},
		"evidence_snapshot": [
			{
				"source_id": "source.raw", "state": "executable", "acquisition": "raw",
				"artifact_path": "evidence/raw.json", "artifact_sha256": "a".repeat(64),
				"diagnostic_path": "evidence/raw-diagnostic.json", "diagnostic_sha256": "f".repeat(64),
				"metadata_artifact_path": "evidence/raw-metadata.json",
				"metadata_artifact_sha256": "9".repeat(64),
				"review_path": "evidence/raw-review.json", "review_sha256": "b".repeat(64),
				"fallback_citations": [{
					"document": "docs/TELEMETRY.md", "section_id": "fixture",
					"source_windows_used": [[1.25, 3.0]],
				}],
			},
			{
				"source_id": "youtube.unaligned", "state": "observation_only",
				"metadata_diagnostic_path": "evidence/video-diagnostic.json",
				"metadata_diagnostic_sha256": "d".repeat(64),
				"review_path": "evidence/video-review.json",
				"review_sha256": "e".repeat(64),
			},
		],
		"pov_map": _expected_pov_map(),
		"checklist": _expected_checklist(),
		"issue_coverage": {
			"schema_version": "fidelity-issue-coverage@1", "records": issue_records,
		},
		"render_requests": _expected_render_requests(),
	}


static func _measurement_summary(
	seed: int, length: float, duration: float, beats: Array
) -> Dictionary:
	return {
		"schema_version": 2, "seed": seed, "length": length, "duration": duration,
		"dimensions": {"width": 40.0, "height": 30.0}, "beats": beats,
		"force_error_peak_g": 0.01, "reconstruction_seam_count": 2,
	}


static func _expected_pov_map() -> Dictionary:
	var records := []
	for spec in [["obs.point", "landmark.point", {"kind": "point", "time_s": 1.25}],
		["obs.window", "landmark.window", {"kind": "window", "window_s": [2.0, 3.0]}]]:
		records.append({
			"source_id": "source.raw", "source_landmark_id": spec[1],
			"source_time": spec[2], "observation_id": spec[0],
			"semantic_selector_id": "selector.loop", "alignment_method": "fixture alignment",
			"uncertainty_s": 0.1, "row_compatibility": "same-row",
			"generated_seed": 42, "generated_anchor": {"semantic_selector_id": "selector.loop"},
			"generated_beat_id": "act-one/00/loop", "generated_window_s": [10.1, 11.9],
			"generated_time_s": 11.0,
			"generated_pov_path": "review/seed-42/pov/act-one__00__loop.png",
		})
	return {
		"schema_version": "fidelity-pov-map@1",
		"source_landmarks": [
			{"source_id": "source.raw", "landmark_id": "landmark.point", "source_time": {"kind": "point", "time_s": 1.25}},
			{
				"source_id": "source.raw", "landmark_id": "landmark.window",
				"source_time": {"kind": "window", "window_s": [2.0, 3.0]},
			},
			{"source_id": "youtube.unaligned", "landmark_id": "video.crest", "source_time": {"kind": "point", "time_s": 4.0}},
		],
		"records": records,
		"gaps": [{
			"id": "youtube.unaligned/alignment-not-present", "source_id": "youtube.unaligned",
			"reason": "alignment-not-present", "source_landmark_ids": ["video.crest"],
		}],
	}


static func _expected_checklist() -> Array:
	var sections := []
	for spec in [
		["shaping", "Shaping", "prompt.shaping", "shaping"],
		["feel", "Feel", "prompt.feel", "feel"],
		["speed-perception", "Speed perception", "prompt.speed", "speed perception"],
		["terrain-clearance", "Terrain / clearance", "prompt.terrain", "terrain/clearance"],
		["support-overlap", "Support overlap", "prompt.support", "support overlap"],
	]:
		sections.append({
			"id": spec[0], "title": spec[1],
			"prompts": [{
				"id": spec[2], "prompt": "Review %s." % spec[3],
				"evidence_ids": ["source.raw"],
				"generated_artifact_paths": ["review/seed-42/channels.png"],
			}],
		})
	return sections


static func _expected_issue(issue_id: int) -> Dictionary:
	var state := "evidence-gap"
	var measurements := []
	var targets := []
	var evidence := ["gap.unmeasured"]
	var artifacts := []
	if issue_id in [1, 9]:
		state = "measured"
		measurements = ["seed-42"]
		targets = ["target.load"]
		evidence = ["obs.window", "source.raw"]
		artifacts = ["review/seed-42/channels.png"]
	elif issue_id in [2, 3, 4, 5, 6, 12, 14, 15, 16]:
		state = "review-prompt"
		evidence = [PROMPT_FOR_ISSUE[issue_id], "source.raw"]
		artifacts = ["review/seed-42/channels.png"]
	return {
		"issue_id": issue_id, "issue_text": ISSUE_TEXT.get(issue_id, "Issue %d" % issue_id),
		"linked_measurement_ids": measurements, "linked_target_ids": targets,
		"linked_evidence_ids": evidence, "generated_artifact_paths": artifacts, "state": state,
	}


const ISSUE_TEXT := {
	9: "Entry-launch speed", 12: "Flats",
	14: "Multidimensional scaling", 15: "Transition jerk",
}

const PROMPT_FOR_ISSUE := {
	2: "prompt.shaping", 14: "prompt.shaping",
	3: "prompt.feel", 15: "prompt.feel",
	4: "prompt.speed", 9: "prompt.speed",
	5: "prompt.terrain", 12: "prompt.terrain",
	6: "prompt.support", 16: "prompt.support",
}

static func _expected_render_requests() -> Array:
	var requests := []
	for seed in [11, 42, 20260809]:
		for kind in ["channels", "elevation", "top"]:
			requests.append({
				"path": "review/seed-%d/%s.png" % [seed, kind],
				"seed": seed, "artifact_kind": kind,
			})
	requests.append({
		"path": "review/seed-42/elements/act-one__00__loop.png", "seed": 42,
		"artifact_kind": "element", "beat_id": "act-one/00/loop",
	})
	requests.append({
		"path": "review/seed-42/pov/act-one__00__loop.png", "seed": 42,
		"artifact_kind": "pov", "beat_id": "act-one/00/loop",
		"generated_time_s": 11.0,
	})
	requests.sort_custom(func(a: Dictionary, b: Dictionary): return a.path < b.path)
	return requests


const EXPECTED_MARKDOWN := """# Ride fidelity audit

## Identity
Schema: ride-fidelity-audit@1
Legacy base: 3fa14885bef2daf3a7d9c0e544424cb6a296fd99
Catalog: test (schema 2, valid)

## Fleet
11, 42, 20260809, 1

## Measurements
| seed | length | duration | force error | seams |
| ---: | ---: | ---: | ---: | ---: |
| 11 | 111.000000 | 11.000000 | 0.010000 | 2 |
| 42 | 142.000000 | 12.000000 | 0.010000 | 2 |
| 20260809 | 109.000000 | 19.000000 | 0.010000 | 2 |
| 1 | 101.000000 | 11.000000 | 0.010000 | 2 |

## Findings
| target | metric |
| --- | --- |
| target.load | normal_peak_positive |

## Observed only
| observation | seed | value |
| --- | ---: | ---: |
| obs.point | 42 | 1.500000 |

## Evidence gaps
| target | seed | reason |
| --- | ---: | --- |
| target.load | 1 | row-not-found |

## Recommendation
recommended: target.load

## Evidence snapshot
| source | state | acquisition |
| --- | --- | --- |
| source.raw | executable | raw |
| youtube.unaligned | observation_only |  |

## POV map
| source | landmark | observation | generated beat | source time |
| --- | --- | --- | --- | --- |
| source.raw | landmark.point | obs.point | act-one/00/loop | point 1.250000 |
| source.raw | landmark.window | obs.window | act-one/00/loop | window 2.000000–3.000000 |
Gap: youtube.unaligned — alignment-not-present (video.crest)

## Checklist
### Shaping
- prompt.shaping: Review shaping. [source.raw] -> review/seed-42/channels.png
### Feel
- prompt.feel: Review feel. [source.raw] -> review/seed-42/channels.png
### Speed perception
- prompt.speed: Review speed perception. [source.raw] -> review/seed-42/channels.png
### Terrain / clearance
- prompt.terrain: Review terrain/clearance. [source.raw] -> review/seed-42/channels.png
### Support overlap
- prompt.support: Review support overlap. [source.raw] -> review/seed-42/channels.png

## Issue coverage
| issue | text | state | targets | evidence | artifacts |
| ---: | --- | --- | --- | --- | --- |
| 1 | Issue 1 | measured | target.load | obs.window, source.raw | review/seed-42/channels.png |
| 2 | Issue 2 | review-prompt |  | prompt.shaping, source.raw | review/seed-42/channels.png |
| 3 | Issue 3 | review-prompt |  | prompt.feel, source.raw | review/seed-42/channels.png |
| 4 | Issue 4 | review-prompt |  | prompt.speed, source.raw | review/seed-42/channels.png |
| 5 | Issue 5 | review-prompt |  | prompt.terrain, source.raw | review/seed-42/channels.png |
| 6 | Issue 6 | review-prompt |  | prompt.support, source.raw | review/seed-42/channels.png |
| 7 | Issue 7 | evidence-gap |  | gap.unmeasured |  |
| 8 | Issue 8 | evidence-gap |  | gap.unmeasured |  |
| 9 | Entry-launch speed | measured | target.load | obs.window, source.raw | review/seed-42/channels.png |
| 10 | Issue 10 | evidence-gap |  | gap.unmeasured |  |
| 11 | Issue 11 | evidence-gap |  | gap.unmeasured |  |
| 12 | Flats | review-prompt |  | prompt.terrain, source.raw | review/seed-42/channels.png |
| 13 | Issue 13 | evidence-gap |  | gap.unmeasured |  |
| 14 | Multidimensional scaling | review-prompt |  | prompt.shaping, source.raw | review/seed-42/channels.png |
| 15 | Transition jerk | review-prompt |  | prompt.feel, source.raw | review/seed-42/channels.png |
| 16 | Issue 16 | review-prompt |  | prompt.support, source.raw | review/seed-42/channels.png |

## Render requests
| path | kind | seed | beat |
| --- | --- | ---: | --- |
| review/seed-11/channels.png | channels | 11 |  |
| review/seed-11/elevation.png | elevation | 11 |  |
| review/seed-11/top.png | top | 11 |  |
| review/seed-20260809/channels.png | channels | 20260809 |  |
| review/seed-20260809/elevation.png | elevation | 20260809 |  |
| review/seed-20260809/top.png | top | 20260809 |  |
| review/seed-42/channels.png | channels | 42 |  |
| review/seed-42/elements/act-one__00__loop.png | element | 42 | act-one/00/loop |
| review/seed-42/elevation.png | elevation | 42 |  |
| review/seed-42/pov/act-one__00__loop.png | pov | 42 | act-one/00/loop |
| review/seed-42/top.png | top | 42 |  |
"""


static func _reverse_dictionaries(value: Variant) -> Variant:
	if value is Dictionary:
		var output := {}
		var keys: Array = value.keys()
		keys.reverse()
		for key in keys:
			output[key] = _reverse_dictionaries(value[key])
		return output
	if value is Array:
		var output := []
		for item in value:
			output.append(_reverse_dictionaries(item))
		return output
	return value


static func _expect(errors: PackedStringArray, condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


static func _expect_contains(
	errors: PackedStringArray, values: Array, needle: String, message: String
) -> void:
	for value in values:
		if str(value).contains(needle):
			return
	errors.append("%s: %s" % [message, str(values)])
