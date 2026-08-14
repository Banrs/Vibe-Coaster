extends SceneTree

const CANONICAL_PATH := "res://canonical_data.gd"
const ARTIFACTS_PATH := "res://fidelity_artifacts.gd"
const REFERENCES_PATH := "res://fidelity_references.gd"
const SAMPLING_PATH := "res://route_sampling.gd"
const VIEWER_PATH := "res://main.gd"
const FIDELITY_PATH := "res://fidelity.gd"
const INSPECT_PATH := "res://_inspect.gd"
const LEGACY_BASE_COMMIT := "3fa14885bef2daf3a7d9c0e544424cb6a296fd99"
const AUDIT_SEEDS := [11, 42, 20260809, 1, 3, 7, 99, 256, 555, 1234, 4096, 31337, 77777, 123456, 20250101]
const DEEP_REVIEW_SEEDS := [11, 42, 20260809]


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
	var fidelity: Script = load(FIDELITY_PATH)
	var references: Script = load(REFERENCES_PATH)
	_test_canonical_data(canonical_data, artifacts, errors)
	_test_authoritative_catalog_validation(artifacts, fidelity, errors)
	_test_successful_report(artifacts, errors)
	_test_invalid_inputs(artifacts, errors)
	_test_committed_catalog(artifacts, references, errors)
	_test_catalog_evidence_gaps_are_published(artifacts, references, errors)
	_test_element_render_request_filter(artifacts, errors)
	_test_center_row_alignment_selectors(artifacts, errors)
	_test_compiled_anchor_identity(artifacts, errors)
	_test_route_sampling(errors)
	_test_pov_camera(artifacts, errors)
	_test_checked_writes(artifacts, errors)
	_test_default_off_preserves_report_and_pack(artifacts, errors)
	_test_opt_in_generated_midpoint_pov_requests(artifacts, errors)
	_test_write_pack_overlay_additions_and_valid_gaps(artifacts, errors)
	_test_overlay_independent_plot_domains(artifacts, errors)
	_test_overlay_pack_redaction_and_determinism(artifacts, errors)
	_test_overlay_writer_rejects_malformed_explicit_projection(artifacts, errors)
	_test_inspector_overlay_boundary(errors)
	_test_inspector_diagnostics_are_read_only(artifacts, errors)
	_test_write_pack(artifacts, errors)
	_test_audit_fleet(errors)
	return errors


## Characterization gate for the compatibility ABI: an unaligned retained element must not
## silently acquire a POV when callers use the original five-/three-argument path.
static func _test_default_off_preserves_report_and_pack(
	artifacts: Script, errors: PackedStringArray
) -> void:
	var fixture := _pack_fixture()
	fixture.seed_measurements[1].beats.append_array([{
		"beat_id": "act-one/01/hill", "story_slot_id": "act1.hill",
		"window_role": "core", "kind": "hill", "window_s": [4.0, 6.0],
		"start_distance": 50.0, "end_distance": 100.0,
		"rows": [{"row_id": "row-02", "position": "intermediate", "offset": 0.0,
			"window_start_s": 4.0, "window_end_s": 6.0}],
	}])
	var inspect: Script = load(INSPECT_PATH)
	var report_seam := Callable(inspect, "_artifact_report")
	var writer_seam := Callable(inspect, "_write_artifact_pack")
	_expect(errors, report_seam.is_valid() and writer_seam.is_valid(),
		"the inspector exposes its off-versus-opt-in artifact seam")
	if not report_seam.is_valid() or not writer_seam.is_valid(): return
	var audit := {"measurements": fixture.seed_measurements, "comparison": fixture.comparison,
		"generation_counts": fixture.generation_counts, "routes_by_seed": _pack_routes()}
	var report: Dictionary = report_seam.call(
		audit, fixture.catalog, fixture.legacy_base_commit, {})
	var direct: Dictionary = _build(artifacts, fixture)
	_expect(errors, artifacts.canonical_json(report) == artifacts.canonical_json(direct)
		and artifacts.markdown(report) == artifacts.markdown(direct),
		"the inspector's both-empty RFDB path is the exact legacy report call")
	var element_paths := PackedStringArray()
	var pov_paths := PackedStringArray()
	for request: Dictionary in report.get("render_requests", []):
		if request.artifact_kind == "element": element_paths.append(request.path)
		if request.artifact_kind == "pov": pov_paths.append(request.path)
	_expect(errors, element_paths == PackedStringArray([
		"review/seed-42/elements/act-one__00__loop.png",
		"review/seed-42/elements/act-one__01__hill.png",
	]), "default report retains both element requests")
	_expect(errors, pov_paths == PackedStringArray([
		"review/seed-42/pov/act-one__00__loop.png",
	]), "default report adds no midpoint POV for an unaligned retained element")
	var first := "user://artifact-off-first"
	var second := "user://artifact-off-second"
	_reset_directory(first)
	_reset_directory(second)
	_expect(errors, writer_seam.call(first, report, _pack_routes(), {}).is_empty(),
		"default pack writes the frozen compatibility fixture")
	_expect(errors, writer_seam.call(second, report, _pack_routes(), {}).is_empty(),
		"default pack repeats the frozen compatibility fixture")
	var expected_files := PackedStringArray(EXPECTED_PACK_FILES)
	expected_files.append("review/seed-42/elements/act-one__01__hill.png")
	expected_files.sort()
	_expect(errors, _relative_files(first) == expected_files,
		"default pack preserves the complete legacy set plus its requested element")
	_expect(errors, _relative_files(second) == expected_files,
		"repeated default pack preserves the complete file list")
	for path in expected_files:
		_expect(errors, FileAccess.get_file_as_bytes("%s/%s" % [first, path])
			== FileAccess.get_file_as_bytes("%s/%s" % [second, path]),
			"default artifact '%s' repeats byte-identically" % path)


static func _test_opt_in_generated_midpoint_pov_requests(
	artifacts: Script, errors: PackedStringArray
) -> void:
	var fixture := _pack_fixture()
	fixture.seed_measurements[1].beats.append_array([{
		"beat_id": "act-one/01/hill", "story_slot_id": "act1.hill", "window_role": "core",
		"kind": "hill", "window_s": [4.0, 6.0], "start_distance": 50.0, "end_distance": 100.0,
		"rows": [{"row_id": "row-04", "position": "middle", "offset": 6.45,
			"window_start_s": 4.0, "window_end_s": 6.0}],
	}, {
		"beat_id": "act-one/02/brakes", "story_slot_id": "act1.brakes", "window_role": "core",
		"kind": "brake_run", "window_s": [6.0, 8.0], "rows": [{"offset": 0.0,
			"window_start_s": 6.0, "window_end_s": 8.0}],
	}])
	var report: Dictionary = artifacts.build_report(fixture.seed_measurements, fixture.comparison,
		fixture.catalog, fixture.legacy_base_commit, fixture.generation_counts, true)
	var hill_povs: Array = report.get("render_requests", []).filter(func(request: Dictionary):
		return request.get("path") == "review/seed-42/pov/act-one__01__hill.png")
	_expect(errors, hill_povs.size() == 1 and hill_povs[0].generated_time_s == 5.0
		and hill_povs[0].row_id == "row-04" and hill_povs[0].row_offset_m == 6.45,
		"opt-in adds exactly one row-04 midpoint POV for an unaligned retained element")
	_expect(errors, report.render_requests.filter(func(request: Dictionary):
		return str(request.get("path", "")).contains("brakes")).is_empty(),
		"opt-in adds no request for a non-side-view beat")
	_expect(errors, report.render_requests.filter(func(request: Dictionary):
		return request.get("path") == "review/seed-42/pov/act-one__00__loop.png").size() == 1,
		"an aligned midpoint request deduplicates byte-for-byte")
	var missing_center := fixture.duplicate(true)
	missing_center.seed_measurements[1].beats[1].rows = []
	var missing_result: Dictionary = artifacts.build_report(missing_center.seed_measurements,
		missing_center.comparison, missing_center.catalog, missing_center.legacy_base_commit,
		missing_center.generation_counts, true)
	_expect_contains(errors, missing_result.get("errors", []),
		"midpoint POV requires exactly one row-04",
		"opt-in rejects a retained element with no row-04")
	var duplicate_center := fixture.duplicate(true)
	duplicate_center.seed_measurements[1].beats[1].rows.append(
		duplicate_center.seed_measurements[1].beats[1].rows[0].duplicate(true))
	var duplicate_result: Dictionary = artifacts.build_report(duplicate_center.seed_measurements,
		duplicate_center.comparison, duplicate_center.catalog, duplicate_center.legacy_base_commit,
		duplicate_center.generation_counts, true)
	_expect_contains(errors, duplicate_result.get("errors", []),
		"midpoint POV requires exactly one row-04",
		"opt-in rejects a retained element with multiple row-04 records")
	_append_copy(fixture.seed_measurements[1].beats, 0, {
		"beat_id": "act-one__00__loop", "story_slot_id": "act1.conflict"})
	var conflict: Dictionary = artifacts.build_report(fixture.seed_measurements, fixture.comparison,
		fixture.catalog, fixture.legacy_base_commit, fixture.generation_counts, true)
	_expect_contains(errors, conflict.get("errors", []), "conflicting payload",
		"an aligned POV that conflicts with the midpoint invalidates the report")


static func _test_write_pack_overlay_additions_and_valid_gaps(
	artifacts: Script, errors: PackedStringArray
) -> void:
	for gap_kind in ["complete", "source", "generated"]:
		var overlays := _overlay_fixture(4)
		if gap_kind == "source": _make_source_gap(overlays.comparisons[0])
		if gap_kind == "generated": _make_generated_gap(overlays.comparisons[0])
		var first := "user://overlay-pack-%s-a" % gap_kind
		var second := "user://overlay-pack-%s-b" % gap_kind
		_reset_directory(first); _reset_directory(second)
		var report := _build(artifacts, _pack_fixture())
		var failures: Array = Array(artifacts.write_pack(first, report, _pack_routes(), overlays))
		_expect(errors, failures.is_empty(), "%s overlay gap writes successfully: %s" % [gap_kind, failures])
		_expect(errors, artifacts.write_pack(second, report, _pack_routes(), overlays).is_empty(),
			"%s overlay gap repeats successfully" % gap_kind)
		var additions := PackedStringArray(["review/overlays/index.json", "review/overlays/index.md"])
		for index in 4: additions.append("review/overlays/test-%d.png" % index)
		var expected := PackedStringArray(EXPECTED_PACK_FILES)
		expected.append_array(additions); expected.sort()
		_expect(errors, _relative_files(first) == expected, "%s adds only the six overlay artifacts" % gap_kind)
		for path in expected:
			_expect(errors, FileAccess.get_file_as_bytes("%s/%s" % [first, path])
				== FileAccess.get_file_as_bytes("%s/%s" % [second, path]),
				"%s artifact '%s' repeats byte-identically" % [gap_kind, path])
		var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/manifest.json" % first))
		var paths: Array = manifest.files.map(func(file: Dictionary): return file.path)
		var sorted := paths.duplicate(); sorted.sort()
		_expect(errors, paths == sorted, "overlay manifest paths are sorted")
		for file: Dictionary in manifest.files:
			if str(file.path).begins_with("review/overlays/") and file.path.ends_with(".png"):
				_expect(errors, file.artifact_kind == "telemetry-overlay" and file.width > 0 and file.height > 0,
					"overlay PNGs reopen and carry telemetry-overlay records")
		if gap_kind == "generated":
			var emitted: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
				"%s/review/overlays/index.json" % first))
			_expect(errors, emitted.comparisons[0].generated.window_s == null
				and emitted.comparisons[0].generated.duration_s == null,
				"generated gaps serialize no invented window or duration")
		var markdown := FileAccess.get_file_as_string("%s/review/overlays/index.md" % first)
		_expect(errors, markdown.contains("| comparison | source | generated | artifact |")
			and markdown.contains("test-0") and markdown.contains("source-local-seconds")
			and markdown.contains("generated-route-seconds")
			and not markdown.contains('"samples"') and not markdown.contains('"time_s"'),
			"overlay Markdown is a concise ordered review projection without per-sample JSON")


static func _test_overlay_independent_plot_domains(artifacts: Script, errors: PackedStringArray) -> void:
	var comparison: Dictionary = _overlay_fixture(1).comparisons[0]
	comparison.source.window_s = [20.0, 30.0]; comparison.source.duration_s = 10.0
	comparison.generated.window_s = [200.0, 260.0]; comparison.generated.duration_s = 60.0
	for lane: Dictionary in comparison.lanes:
		if lane.role in ["source_observed_smoothed", "approved_scaled_target"]:
			lane.samples[0].time_s = 20.0; lane.samples[1].time_s = 29.999
		elif lane.role == "generated_raw":
			lane.samples[0].time_s = 200.0; lane.samples[1].time_s = 259.999
	comparison.markers = [{"id": "entry", "time_s": 20.0, "uncertainty_s": 0.1},
		{"id": "apex", "time_s": 25.0, "uncertainty_s": 0.1},
		{"id": "exit", "time_s": 30.0, "uncertainty_s": 0.1}]
	var image: Image = artifacts._overlay_image(comparison)
	_expect(errors, image.get_size() == Vector2i(1200, 900), "overlay renderer has the fixed contracted frame")
	# Cyan source and magenta generated endpoints must independently reach x=50 and x=1149.
	_expect(errors, _column_has_color(image, 51, Color(0.55, 0.95, 1.0), 0, 900)
		and _column_has_color(image, 1148, Color(0.55, 0.95, 1.0), 0, 900),
		"source traces reach their source-native panel bounds")
	_expect(errors, _column_has_color(image, 50, Color(0.95, 0.55, 0.95), 0, 900)
		and _column_has_color(image, 1149, Color(0.95, 0.55, 0.95), 0, 900),
		"generated traces reach their generated-native panel bounds")
	var marker_only_source := _column_has_color(image, 600, Color(0.75, 0.62, 0.25), 20, 130)
	for lower in [160, 460, 760]:
		marker_only_source = marker_only_source and not _column_has_color(
			image, 600, Color(0.75, 0.62, 0.25), lower, lower + 110)
	_expect(errors, marker_only_source,
		"source semantic markers are never projected into generated panels")


static func _test_overlay_pack_redaction_and_determinism(
	artifacts: Script, errors: PackedStringArray
) -> void:
	var local_path := "C:/Users/fixture/secret-rfdb.csv"
	var inspect: Script = load(INSPECT_PATH); var captured := {}
	var overlays: Dictionary = Callable(inspect, "_build_overlays").call(
		'{"fixture":true}'.to_utf8_buffer(), {"rfdb-4804": local_path}, {}, {}, {},
		func(_manifest, _bytes, local_files, _measurement, _route, _transforms):
			captured.local_files = local_files
			return _overlay_fixture(4))
	_expect(errors, captured.get("local_files") == {"rfdb-4804": local_path},
		"the redaction fixture injects a recognizable absolute local path at the core boundary")
	var reversed: Dictionary = _reverse_dictionaries(overlays)
	var first := "user://overlay-redaction-a"; var second := "user://overlay-redaction-b"
	_reset_directory(first); _reset_directory(second)
	var report := _build(artifacts, _pack_fixture())
	artifacts.write_pack(first, report, _pack_routes(), overlays)
	artifacts.write_pack(second, report, _pack_routes(), reversed)
	_expect(errors, _relative_files(first) == _relative_files(second), "dictionary order does not change files")
	for path in _relative_files(first):
		var left := FileAccess.get_file_as_bytes("%s/%s" % [first, path])
		var right := FileAccess.get_file_as_bytes("%s/%s" % [second, path])
		_expect(errors, left == right, "dictionary order does not change '%s'" % path)
		if path.ends_with(".json") or path.ends_with(".md"):
			var text := left.get_string_from_utf8()
			_expect(errors, not text.contains(local_path) and not text.contains("timestamp")
				and not text.contains("created_at"), "artifacts contain no local path or timestamp fields")


static func _test_overlay_writer_rejects_malformed_explicit_projection(
	artifacts: Script, errors: PackedStringArray
) -> void:
	var cases := [
		func(v): v.schema_version = "wrong", func(v): v.status = "invalid-input",
		func(v): v.comparisons[0].comparison_id = "../bad", func(v): v.comparisons.append(v.comparisons[0].duplicate(true)),
		func(v): v.comparisons[0].artifact_path = "review/overlays/wrong.png",
		func(v): v.comparisons[0].source.window_s = [1.0], func(v): v.comparisons[0].generated.duration_s = 99.0,
		func(v): v.comparisons[0].lanes.pop_back(), func(v): v.comparisons[0].lanes[1].role = "generated_raw",
		func(v): v.comparisons[0].lanes[1].clock = "generated", func(v): v.comparisons[0].lanes[1].samples = {},
		func(v): v.comparisons[0].lanes[1].samples[0] = [], func(v): v.comparisons[0].lanes[1].samples[0].time_s = INF,
		func(v): v.comparisons[0].lanes[1].samples[0].time_s = 99.0,
		func(v): v.comparisons[0].lanes[1].samples[1].time_s = 1.0,
		func(v): v.comparisons[0].lanes[1].samples[0].normal_g = NAN,
		func(v): v.comparisons[0].lanes[1].samples[0].eligible = 1,
		func(v): v.comparisons[0].markers[0].uncertainty_s = 0.0,
		func(v): v.gaps = ["bad"],
	]
	for index in cases.size():
		var overlays := _overlay_fixture(1); cases[index].call(overlays)
		var directory := "user://overlay-invalid-%d" % index; _reset_directory(directory)
		var failures: Array = Array(artifacts.write_pack(directory,
			_build(artifacts, _pack_fixture()), _pack_routes(), overlays))
		var sorted := failures.duplicate(); sorted.sort()
		_expect(errors, not failures.is_empty() and failures == sorted
			and failures.all(func(value): return str(value).begins_with("artifact_write: overlay")),
			"malformed overlay case %d returns sorted artifact_write errors" % index)
		_expect(errors, not FileAccess.file_exists("%s/manifest.json" % directory)
			and not DirAccess.dir_exists_absolute("%s/review/overlays" % directory),
			"malformed overlay case %d writes no overlay or manifest" % index)


static func _test_inspector_overlay_boundary(errors: PackedStringArray) -> void:
	var inspect: Script = load(INSPECT_PATH)
	var local_files_seam := Callable(inspect, "_local_rfdb_files")
	var seam := Callable(inspect, "_build_overlays")
	_expect(errors, local_files_seam.is_valid() and seam.is_valid(),
		"the inspector exposes a static overlay boundary")
	if not local_files_seam.is_valid() or not seam.is_valid(): return
	var captured := {}
	var builder := func(manifest, bytes, local_files, measurement, route, transforms):
		captured.merge({"manifest": manifest, "bytes": bytes, "local_files": local_files,
			"measurement": measurement, "route": route, "transforms": transforms})
		return _overlay_fixture(1)
	var env := {"RFDB_4804_CSV": "a.csv", "RFDB_6383_CSV": "", "IGNORED": "secret.csv"}
	var bytes := '{"schema_version":"fixture"}'.to_utf8_buffer()
	var measurement := {"identity": "retained-measurement"}; var route := {"identity": "retained-route"}
	var local_files: Dictionary = local_files_seam.call(func(name): return env.get(name, ""))
	var result: Dictionary = seam.call(bytes, local_files, measurement,
		route, {"t": 1}, builder)
	_expect(errors, result.status == "ok" and captured.local_files == {"rfdb-4804": "a.csv"},
		"only the two named nonempty RFDB variables enter the transient local map")
	_expect(errors, is_same(captured.measurement, measurement) and is_same(captured.route, route),
		"the overlay seam receives retained seed-42 values")
	var empty_files: Dictionary = local_files_seam.call(func(_name): return "")
	_expect(errors, empty_files.is_empty(),
		"both absent RFDB variables select the inspector's legacy off path")
	var malformed: Dictionary = seam.call("{".to_utf8_buffer(), {"rfdb-4804": "bad.csv"}, measurement,
		route, {}, builder)
	_expect(errors, malformed.status == "invalid-input", "malformed committed manifest is operational")
	var diagnostic := func(_m, _b, _l, _me, _r, _t):
		var value := _overlay_fixture(1); _make_source_gap(value.comparisons[0]); return value
	var missing: Dictionary = seam.call(bytes, {"rfdb-4804": "missing.csv"}, measurement,
		route, {}, diagnostic)
	_expect(errors, missing.status == "ok" and missing.comparisons[0].source.status == "source_trace_unavailable",
		"missing or hash-invalid optional CSV remains diagnostic")


static func _test_inspector_diagnostics_are_read_only(
	artifacts: Script, errors: PackedStringArray
) -> void:
	var directory := "user://diagnostic-read-only"; _reset_directory(directory)
	var report := _build(artifacts, _pack_fixture())
	artifacts.write_pack(directory, report, _pack_routes())
	var before := _file_bytes(directory)
	var inspect: Script = load(INSPECT_PATH)
	var project := Callable(inspect, "_diagnostic_lines")
	_expect(errors, project.is_valid(), "the inspector exposes a read-only diagnostic projection")
	if not project.is_valid(): return
	var lines: Variant = project.call(report, directory)
	_expect(errors, lines is PackedStringArray and not lines.is_empty(), "checked report and legends project diagnostics")
	_expect(errors, before == _file_bytes(directory), "diagnostic projection does not change artifact bytes")
	for path in _relative_files(directory):
		_expect(errors, not (not path.contains("/") and path.ends_with(".png")),
			"diagnostics create no root-level PNG")


## The audit orchestration seam, exercised with spies only: no generator, no catalog, no files.
static func _test_audit_fleet(errors: PackedStringArray) -> void:
	if not ResourceLoader.exists(INSPECT_PATH):
		errors.append("the inspector is missing")
		return
	var inspect: Script = load(INSPECT_PATH)
	var fidelity: Script = load(FIDELITY_PATH)
	_expect(errors, inspect.get_script_constant_map().get("AUDIT_SEEDS") == AUDIT_SEEDS,
		"the inspector pins the canonical fifteen-seed fleet in its documented order")
	_expect(errors, fidelity.get_script_constant_map().get("CANONICAL_FLEET") == AUDIT_SEEDS,
		"the audited fleet is the fleet the comparison calls canonical")
	_test_one_build_per_seed(Callable(inspect, "_run_audit"), errors)


static func _test_one_build_per_seed(runner: Callable, errors: PackedStringArray) -> void:
	if not runner.is_valid():
		errors.append("the inspector exposes no static _run_audit orchestration seam")
		return
	var calls := {}
	var build := func(seed_value: int) -> Dictionary:
		calls[seed_value] = int(calls.get(seed_value, 0)) + 1
		return {"seed": seed_value}
	var measure_calls := {"count": 0}
	var measure := func(route: Dictionary) -> Dictionary:
		measure_calls.count += 1
		return {"seed": route.seed}
	var compare := func(measurements: Array) -> Dictionary: return {"fleet": measurements.map(func(item): return item.seed)}
	var report: Dictionary = runner.call(AUDIT_SEEDS, build, measure, compare)
	_expect(errors, report.get("fleet") == AUDIT_SEEDS, "report preserves canonical fleet")
	for seed_value in AUDIT_SEEDS:
		_expect(errors, calls.get(seed_value, 0) == 1, "seed %d is generated once" % seed_value)
	_expect(errors, calls.size() == AUDIT_SEEDS.size(), "the audit generates nothing outside the fleet")
	var expected_measurements := AUDIT_SEEDS.map(func(seed_value: int): return {"seed": seed_value})
	_expect(errors, report.get("measurements") == expected_measurements,
		"every seed is measured once, in fleet order")
	_expect(errors, report.get("comparison") == {"fleet": AUDIT_SEEDS},
		"the fleet comparison sees exactly the ordered measurements")
	var expected_routes := {}
	for seed_value in DEEP_REVIEW_SEEDS:
		expected_routes[seed_value] = {"seed": seed_value}
	_expect(errors, report.get("routes_by_seed") == expected_routes,
		"only the deep-review seeds retain their already-built route")
	var expected_counts := {}
	for seed_value in AUDIT_SEEDS:
		expected_counts[str(seed_value)] = 1
	var counts: Variant = report.get("generation_counts")
	_expect(errors, counts is Dictionary and counts == expected_counts,
		"generation counts are the fleet under String keys, each generated once")
	if not counts is Dictionary:
		return
	var counted: Dictionary = counts
	for key in counted:
		_expect(errors, typeof(key) == TYPE_STRING, "generation-count key '%s' is a String" % str(key))
		_expect(errors, typeof(counted[key]) == TYPE_INT,
			"generation-count value for '%s' is an integer" % str(key))
	var inspect: Script = load(INSPECT_PATH); var captured := {}
	var retained_measurement: Dictionary = report.measurements[1]
	var retained_route: Dictionary = report.routes_by_seed[42]
	Callable(inspect, "_build_overlays").call('{"fixture":true}'.to_utf8_buffer(),
		{}, retained_measurement, retained_route, {},
		func(_m, _b, _l, measurement, route, _t):
			captured.measurement = measurement; captured.route = route
			return {"status": "ok"})
	_expect(errors, is_same(captured.get("measurement"), retained_measurement)
		and is_same(captured.get("route"), retained_route),
		"the overlay seam receives the exact retained seed-42 measurement and route identities")
	_expect(errors, measure_calls.count == AUDIT_SEEDS.size()
		and calls.values().all(func(count): return count == 1),
		"the overlay seam invokes neither generation nor measurement callbacks")


## One deterministic pack: the contracted output set, its reopened manifest, and the checked
## sidecars that make each rendered PNG readable without a font.
static func _test_write_pack(artifacts: Script, errors: PackedStringArray) -> void:
	var directory := "user://artifact-pack"
	_reset_directory(directory)
	var report: Dictionary = _build(artifacts, _pack_fixture())
	var failures: Array = Array(artifacts.write_pack(directory, report, _pack_routes()))
	_expect(errors, failures.is_empty(), "a valid pack writes cleanly: %s" % str(failures))
	_expect(errors, _relative_files(directory) == PackedStringArray(EXPECTED_PACK_FILES),
		"the pack writes exactly the contracted output set")
	_expect_pack_text(artifacts, directory, report, errors)
	_expect_pack_manifest(directory, errors)

	var repeat := "user://artifact-pack-repeat"
	_reset_directory(repeat)
	artifacts.write_pack(repeat, report, _pack_routes())
	_expect(errors, FileAccess.get_file_as_bytes("%s/manifest.json" % directory)
		== FileAccess.get_file_as_bytes("%s/manifest.json" % repeat),
		"identical input writes a byte-identical pack")

	var route := _pack_route(42)
	_expect(errors, artifacts.side_image(route, 0, 40).get_size() == Vector2i(1100, 700)
		and artifacts.top_image(route).get_size() == Vector2i(1100, 700)
		and artifacts.elevation_image(route).get_size() == Vector2i(1100, 700),
		"the inspector's side, top, and elevation renders survive the move")
	var rendered: Dictionary = artifacts.channels(route)
	_expect(errors, rendered.strips.size() == 11
		and rendered.image.get_size() == Vector2i(1400, 1650),
		"the channel render survives the move and carries all eleven strips")
	var separator: Color = rendered.image.get_pixel(349, 4)
	_expect(errors, absf(separator.r - 0.30) < 0.01 and absf(separator.g - 0.27) < 0.01 \
		and absf(separator.b - 0.20) < 0.01,
		"channel separators retain an interior native role boundary")
	_expect_pack_failures(artifacts, errors)


static func _expect_pack_text(
	artifacts: Script, directory: String, report: Dictionary, errors: PackedStringArray
) -> void:
	for case in [
		["audit.json", artifacts.canonical_json(report)],
		["audit.md", artifacts.markdown(report)],
		["review/pov-map.json", artifacts.canonical_json(report.pov_map)],
		["review/issue-coverage.json", artifacts.canonical_json(report.issue_coverage)],
		["review/pov-map.md", _expected_standalone("POV map", "Checklist")],
		["review/checklist.md", _expected_standalone("Checklist", "Issue coverage")],
		["review/issue-coverage.md", _expected_standalone("Issue coverage", "Render requests")],
		["review/seed-11/channels.md", EXPECTED_CHANNELS_MARKDOWN],
	]:
		_expect(errors, FileAccess.get_file_as_string("%s/%s" % [directory, case[0]]) == case[1],
			"%s is the contracted projection" % case[0])
	_expect(errors, FileAccess.get_file_as_string("%s/review/seed-11/channels.json" % directory)
		== artifacts.canonical_json(_expected_legend(11)),
		"the channel legend binds eleven ordered strips to its reopened image")


static func _expect_pack_manifest(directory: String, errors: PackedStringArray) -> void:
	var text := FileAccess.get_file_as_string("%s/manifest.json" % directory)
	var manifest: Variant = JSON.parse_string(text)
	if not manifest is Dictionary:
		errors.append("manifest.json does not reopen as JSON")
		return
	_expect(errors, manifest.keys() == ["files", "generation_counts", "schema_version"],
		"the manifest has exactly the three contracted top-level keys")
	_expect(errors, manifest.schema_version == "fidelity-artifact-manifest@1",
		"the manifest declares its schema")
	_expect(errors, text.contains('"generation_counts":{"1":1,"11":1,"20260809":1,"42":1}'),
		"the manifest copies the report's integer generation counts unchanged")
	var by_path := {}
	var paths := []
	for file in manifest.files:
		paths.append(file.path)
		by_path[file.path] = file
	var expected_paths := EXPECTED_PACK_FILES.duplicate()
	expected_paths.erase("manifest.json")
	_expect(errors, paths == expected_paths,
		"the manifest lists every artifact except itself, sorted by path")
	var audit: Dictionary = by_path.get("audit.json", {})
	_expect(errors, audit.keys() == ["artifact_kind", "beat_id", "byte_size", "height", "kind",
		"path", "seed", "sha256", "width"], "file records carry exactly the contracted keys")
	_expect(errors, audit.get("kind") == "json" and audit.get("artifact_kind") == "audit"
		and audit.get("seed") == null and audit.get("beat_id") == null
		and audit.get("width") == null and audit.get("height") == null,
		"inapplicable manifest members are explicit nulls")
	_expect(errors, audit.get("sha256") == FileAccess.get_sha256("%s/audit.json" % directory)
		and audit.get("byte_size") == FileAccess.get_file_as_bytes(
			"%s/audit.json" % directory).size(),
		"manifest sizes and hashes come from the reopened bytes")
	for case in [
		["review/seed-11/channels.png", "channels", 11, null, 1400, 1650],
		["review/seed-11/channels.json", "channels", 11, null, null, null],
		["review/seed-11/top.png", "top", 11, null, 1100, 700],
		["review/seed-20260809/elevation.png", "elevation", 20260809, null, 1100, 700],
		["review/seed-42/elements/act-one__00__loop.png", "element", 42, "act-one/00/loop", 1100, 700],
		["review/seed-42/pov/act-one__00__loop.png", "pov", 42, "act-one/00/loop", 1440, 900],
		["review/checklist.md", "checklist", null, null, null, null],
	]:
		var record: Dictionary = by_path.get(case[0], {})
		_expect(errors, record.get("artifact_kind") == case[1] and record.get("seed") == case[2]
			and record.get("beat_id") == case[3] and record.get("width") == case[4]
			and record.get("height") == case[5],
			"%s is described by its own render, not by its request" % case[0])


static func _expect_pack_failures(artifacts: Script, errors: PackedStringArray) -> void:
	var directory := "user://artifact-pack-invalid"
	_reset_directory(directory)
	var mismatched: Dictionary = _build(artifacts, _pack_fixture())
	for request in mismatched.render_requests:
		if request.artifact_kind == "element":
			request.path = "review/seed-42/elements/act-one-00-loop.png"
	_expect_contains(errors, Array(artifacts.write_pack(directory, mismatched, _pack_routes())),
		"artifact_write", "a mismatched render path is an operational failure")
	_expect(errors, not FileAccess.file_exists("%s/manifest.json" % directory),
		"a failed pack never claims a manifest")
	var report: Dictionary = _build(artifacts, _pack_fixture())
	var incomplete := _pack_routes()
	incomplete.erase(20260809)
	_expect_contains(errors, Array(artifacts.write_pack(directory, report, incomplete)),
		"artifact_write", "a missing generated route is an operational failure")
	_expect_contains(errors,
		Array(artifacts.write_pack(directory, {"status": "invalid-input"}, _pack_routes())),
		"artifact_write", "an invalid report never writes a pack")


## Writes are operational: an unopenable destination is an error, and a landed file is reopened.
static func _test_checked_writes(artifacts: Script, errors: PackedStringArray) -> void:
	var unopenable := "Z:/path-that-does-not-exist/audit.json"
	var failures: Array = Array(artifacts.write_text_checked(unopenable, "{}\n"))
	_expect(errors, not failures.is_empty(), "failed report write is operationally visible")
	_expect_contains(errors, failures, "artifact_write", "write failure has a distinct category")
	var image := Image.create(4, 3, false, Image.FORMAT_RGB8)
	_expect_contains(errors,
		Array(artifacts.save_png_checked(image, "Z:/path-that-does-not-exist/frame.png")),
		"artifact_write", "failed PNG write is operationally visible")
	var directory := "user://artifact-tests"
	DirAccess.make_dir_recursive_absolute(directory)
	_expect(errors, artifacts.write_text_checked("%s/audit.json" % directory, "{\"a\":1}\n").is_empty(),
		"a verified text write reports no error")
	_expect(errors, FileAccess.get_file_as_string("%s/audit.json" % directory) == "{\"a\":1}\n",
		"checked text writes land byte-exact")
	_expect(errors, artifacts.save_png_checked(image, "%s/frame.png" % directory).is_empty(),
		"a verified PNG write reports no error")
	var reopened := Image.new()
	_expect(errors, reopened.load_png_from_buffer(
		FileAccess.get_file_as_bytes("%s/frame.png" % directory)) == OK
		and reopened.get_size() == Vector2i(4, 3),
		"checked PNG writes reopen at their rendered size")


## The viewer's interpolation is the POV contract: extraction must not move a single sample.
static func _test_route_sampling(errors: PackedStringArray) -> void:
	if not ResourceLoader.exists(SAMPLING_PATH):
		errors.append("RouteSampling is missing")
		return
	var sampling: Script = load(SAMPLING_PATH)
	var viewer: Script = load(VIEWER_PATH)
	var route := _sampling_route()
	_expect(errors, sampling.lower_index(route.distances, -5.0) == 0,
		"lower index clamps below the first knot")
	_expect(errors, sampling.lower_index(route.distances, 10.0) == 1,
		"lower index takes the span starting at an exact knot")
	_expect(errors, sampling.lower_index(route.distances, 25.0) == 1,
		"lower index clamps to the final span")
	_expect(errors, is_equal_approx(sampling.distance_at_time(route, 0.25), 2.5),
		"distance interpolates linearly between sample times")
	_expect(errors, is_equal_approx(sampling.distance_at_time(route, 2.25), 2.5),
		"time wraps by ride duration")
	var pose: Transform3D = sampling.pose_at_distance(route, 5.0)
	_expect(errors, pose.origin.is_equal_approx(Vector3(5.0, 0.0, 0.0)),
		"pose origin lerps between knot positions")
	var diagonal := sqrt(0.5)
	_expect(errors, (-pose.basis.z).is_equal_approx(Vector3(diagonal, 0.0, -diagonal))
		and pose.basis.y.is_equal_approx(Vector3.UP),
		"pose orientation slerps halfway through the quarter-turn between knots")
	_expect(errors, sampling.pose_at_distance(route, 25.0) == pose, "distance wraps by ride length")
	for distance in [0.0, 3.75, 10.0, 14.5, 19.9, 41.0]:
		_expect(errors, viewer.pose_at_distance(route, distance)
			== sampling.pose_at_distance(route, distance),
			"viewer pose sampling delegates without change at %f" % distance)
		_expect(errors, viewer.distance_at_time(route, distance * 0.1)
			== sampling.distance_at_time(route, distance * 0.1),
			"viewer time-to-distance delegates without change at %f" % distance)
		_expect(errors, viewer._lower_index(route.distances, distance)
			== sampling.lower_index(route.distances, distance),
			"viewer lower index delegates without change at %f" % distance)


## Three knots turning a right angle about the vertical: enough to expose lerp-versus-slerp.
static func _sampling_route() -> Dictionary:
	return {
		"length": 20.0, "duration": 2.0,
		"distances": PackedFloat32Array([0.0, 10.0, 20.0]),
		"times": PackedFloat32Array([0.0, 1.0, 2.0]),
		"positions": PackedVector3Array([
			Vector3.ZERO, Vector3(10.0, 0.0, 0.0), Vector3(10.0, 0.0, -10.0),
		]),
		"tangents": PackedVector3Array([Vector3.RIGHT, Vector3.FORWARD, Vector3.LEFT]),
		"ups": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]),
		"rights": PackedVector3Array([Vector3.BACK, Vector3.RIGHT, Vector3.FORWARD]),
	}


## The approved POV camera, restated from the plan rather than read back from the renderer: a
## 1440x900 frame, a 72 degree vertical FOV, a 0.08 m near plane, a 5000 m far plane, and an eye
## 0.35 m over the row-04 pose, with none of the viewer's speed-dependent widening.
const CONTRACT_POV_SIZE := Vector2i(1440, 900)
const CONTRACT_POV_FOV_DEG := 72.0
const CONTRACT_POV_NEAR_M := 0.08
const CONTRACT_POV_EYE_UP_M := 0.35
const POV_GROUND_COLOR := Color(0.45, 0.36, 0.26)
const POV_TRACE_COLOR := Color(0.55, 0.95, 1.0)


## Pin the projection itself, not the constants that spell it: known world geometry is projected
## from the contract above and matched against the pixel it has to light, so an intrinsic that
## drifts moves a rendered feature off its contracted pixel and turns this red.
static func _test_pov_camera(artifacts: Script, errors: PackedStringArray) -> void:
	# The pack fixture is a straight 200 m loop along +X at y = 30 over flat ground, so row-04 at
	# 10 s puts the eye 6.45 m behind the 100 m front position, with the 40 m ground
	# grid steps away from x = 80; the far x = 400 grid line is 306.45 m ahead.
	var image: Image = artifacts.pov_image(_pack_route(11), 10.0, 6.45)
	_expect(errors, image.get_size() == CONTRACT_POV_SIZE,
		"the POV render is the contracted %s frame, not %s" % [CONTRACT_POV_SIZE, image.get_size()])
	if image.get_size() != CONTRACT_POV_SIZE:
		return
	var knot := _pov_pixel(320.0, -(30.0 + CONTRACT_POV_EYE_UP_M), 306.45)
	var ground_row := _pov_top_row_in_column(image, POV_GROUND_COLOR, 1200)
	_expect(errors, ground_row == roundi(knot.y),
		"the ground 306.45 m ahead lands where the %.1f degree vertical FOV puts it: row %d, not %d"
			% [CONTRACT_POV_FOV_DEG, roundi(knot.y), ground_row])
	_expect(errors, _pov_is(image, roundi(knot.x), roundi(knot.y), POV_GROUND_COLOR),
		"the grid knot 320 m right of that line lights its contracted pixel (%d, %d)"
			% [roundi(knot.x), roundi(knot.y)])

	# The rails ride 1.05 m under the pose, so the eye offset alone sets how steeply they fall
	# away from the vanishing point: 0.95 m right of and 1.40 m under the eye, 4 m ahead.
	var rail_under_eye := 1.05 + CONTRACT_POV_EYE_UP_M
	var rail := _pov_pixel(0.95, -rail_under_eye, 4.0)
	var rail_columns := _pov_columns(image, POV_TRACE_COLOR, roundi(rail.y), CONTRACT_POV_SIZE.x / 2)
	var rail_columns_are_projected := rail_columns.has(roundi(rail.x))
	for column in rail_columns:
		rail_columns_are_projected = rail_columns_are_projected \
			and absi(column - roundi(rail.x)) <= 1
	_expect(errors, rail_columns_are_projected,
		"the eye rides %.2f m over the pose: the right rail 4 m ahead stays within one raster pixel of row %d, column %d, not %s"
			% [CONTRACT_POV_EYE_UP_M, roundi(rail.y), roundi(rail.x), str(rail_columns)])

	# The rail is carried past the last sample in front of the eye — 2 m ahead — to the near
	# plane, so it leaves through the bottom edge instead of stopping at that sample.
	var bottom := float(CONTRACT_POV_SIZE.y - 1)
	var last_sample := _pov_pixel(0.95, -rail_under_eye, 2.0)
	var at_near := _pov_pixel(0.95, -rail_under_eye, CONTRACT_POV_NEAR_M)
	var exit_column := roundi(last_sample.lerp(
		at_near, (bottom - last_sample.y) / (at_near.y - last_sample.y)).x)
	var edge_column := _pov_last_column(image, POV_TRACE_COLOR, CONTRACT_POV_SIZE.y - 1)
	_expect(errors, edge_column == exit_column,
		"the rail runs on to the %.2f m near plane and leaves the bottom edge at column %d, not %d"
			% [CONTRACT_POV_NEAR_M, exit_column, edge_column])

	# Track behind the eye is clipped there, not smeared back in mirrored above the horizon: the
	# highest rail pixels are the far knots 98 m ahead, the last samples before the loop wraps.
	var far_left := _pov_pixel(-0.95, -rail_under_eye, 98.0)
	var far_right := _pov_pixel(0.95, -rail_under_eye, 98.0)
	var top_row := _pov_top_row(image, POV_TRACE_COLOR)
	_expect(errors, absi(top_row - roundi(far_right.y)) <= 1,
		"no rail is drawn more than one raster pixel above the far knot 98 m ahead on row %d, but row %d carries one"
			% [roundi(far_right.y), top_row])
	var top_columns := _pov_columns(image, POV_TRACE_COLOR, roundi(far_right.y), 0)
	_expect(errors, top_columns == PackedInt32Array([roundi(far_left.x), roundi(far_right.x)]),
		"that far pair sits at the contracted columns %d and %d, not %s"
			% [roundi(far_left.x), roundi(far_right.x), str(top_columns)])


## The contracted pinhole: a point `right_m` right of, `above_eye_m` over, and `depth_m` in front
## of the eye, in frame pixels.
static func _pov_pixel(right_m: float, above_eye_m: float, depth_m: float) -> Vector2:
	var half_height := depth_m * tan(deg_to_rad(CONTRACT_POV_FOV_DEG) * 0.5)
	var half_width := half_height * CONTRACT_POV_SIZE.x / CONTRACT_POV_SIZE.y
	return Vector2(
		(0.5 + 0.5 * right_m / half_width) * CONTRACT_POV_SIZE.x,
		(0.5 - 0.5 * above_eye_m / half_height) * CONTRACT_POV_SIZE.y
	)


## Rendered colours are quantized to eight bits per channel, so pixels match by nearness.
static func _pov_is(image: Image, column: int, row: int, color: Color) -> bool:
	var pixel := image.get_pixel(column, row)
	return (absf(pixel.r - color.r) <= 0.01 and absf(pixel.g - color.g) <= 0.01
		and absf(pixel.b - color.b) <= 0.01)


static func _pov_top_row_in_column(image: Image, color: Color, column: int) -> int:
	for row in image.get_height():
		if _pov_is(image, column, row, color):
			return row
	return -1


static func _pov_top_row(image: Image, color: Color) -> int:
	for row in image.get_height():
		for column in image.get_width():
			if _pov_is(image, column, row, color):
				return row
	return -1


static func _pov_last_column(image: Image, color: Color, row: int) -> int:
	for step in image.get_width():
		var column := image.get_width() - 1 - step
		if _pov_is(image, column, row, color):
			return column
	return -1


static func _pov_columns(
	image: Image, color: Color, row: int, from_column: int
) -> PackedInt32Array:
	var columns := PackedInt32Array()
	for column in range(from_column, image.get_width()):
		if _pov_is(image, column, row, color):
			columns.append(column)
	return columns


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
	var before: Dictionary = fixture.duplicate(true)
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
	source_fixture.catalog.sources["youtube.unaligned"].fallback_citations[0].section_id = "changed"
	source_fixture.catalog.sources["source.raw"].windows[1].window_s[0] = 9.0
	source_fixture.catalog.observations[0].alignment.generated_anchor.semantic_selector_id = "changed"
	source_fixture.generation_counts["42"] = 2
	_expect(errors, source_report == _expected_report(), "caller nested mutations do not change the completed report")
	var report_fixture := _valid_fixture()
	var mutable_report: Dictionary = _build(artifacts, report_fixture)
	mutable_report.findings[0].metric = "changed"
	mutable_report.measurement_summaries[1].dimensions.width = 99.0
	mutable_report.measurement_summaries[1].beats[0].kind = "changed"
	mutable_report.evidence_snapshot[1].fallback_citations[0].section_id = "changed"
	mutable_report.pov_map.source_landmarks[1].source_time.window_s[0] = 9.0
	_expect(errors, mutable_report.pov_map.records[1].source_time.window_s[0] == 2.0, "source times are independent")
	mutable_report.pov_map.records[0].generated_anchor.semantic_selector_id = "changed"
	_expect(errors, report_fixture == _valid_fixture(), "completed-report nested mutations do not change caller inputs")


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
		["catalog canonicalization rejects unconsumed NAN", "canonical",
			func(value: Dictionary): value.catalog["unconsumed"] = NAN],
		["measurement beats are guarded", "beat",
			func(value: Dictionary): value.seed_measurements[1].beats[0] = []],
		["measurement beat IDs are unique per seed", "duplicate measurement beat",
			func(value: Dictionary): value.seed_measurements[1].beats.append(
				{"beat_id": "act-one/00/loop", "story_slot_id": "act1.brakes",
					"window_role": "core", "kind": "brake_run"})],
		["schema-2 beats require story identity", "story_slot_id",
			func(value: Dictionary): value.seed_measurements[1].beats[0].erase("story_slot_id")],
		["schema-2 beats require role identity", "window_role",
			func(value: Dictionary): value.seed_measurements[1].beats[0].erase("window_role")],
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
		["all five checklist categories are present", "checklist category",
			func(value: Dictionary): value.catalog.review_prompts.pop_back()],
		["every issue has at least one traceability link", "issue 7",
			func(value: Dictionary): value.catalog.evidence_gaps[0].issues.erase(7)],
		["midpoint POV resolution requires row-04 at offset 6.45", "row",
			func(value: Dictionary): value.seed_measurements[1].beats[0].rows[0].offset = 2.0],
		["row-04 POV resolution rejects distinct ambiguous rows", "row",
			func(value: Dictionary): _append_copy(value.seed_measurements[1].beats[0].rows, 0,
				{"window_start_s": 10.2})],
		["row-04 POV resolution rejects identical ambiguous rows", "row",
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
	var retained := _valid_fixture()
	retained.legacy_base_commit = "BAD"
	retained.seed_measurements[1].beats[0].rows[0].offset = 2.0
	var retained_result: Dictionary = _build(artifacts, retained)
	_expect_contains(errors, retained_result.get("errors", []), "legacy_base_commit",
		"combined invalid input retains the base diagnostic")
	_expect_contains(errors, retained_result.get("errors", []), "exactly one row-04",
		"non-catalog errors preserve retained artifact diagnostics")


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
	_expect(errors, report.get("pov_map", {}).get("records", []).is_empty(),
		"committed unaligned catalog produces no POV mappings")
	_expect(errors, report.get("render_requests", []).filter(
		func(request: Dictionary): return request.get("artifact_kind") == "pov").is_empty(),
		"committed unaligned catalog produces no POV PNG requests")


## A catalogued evidence gap is the audit's most load-bearing negative claim. The comparison gap
## list is empty by contract while no source is executable, so a report that publishes only that
## list reads to a reviewer as "no gap" while the catalog declares five.
static func _test_catalog_evidence_gaps_are_published(
	artifacts: Script, references: Script, errors: PackedStringArray
) -> void:
	var fixture := _valid_fixture()
	fixture.catalog = references.CATALOG
	fixture.comparison = {
		"fleet": [11, 42, 20260809, 1], "findings": [], "observed_only": [],
		"evidence_gaps": [], "recommendation": {"status": "no-eligible-finding"},
	}
	var report: Dictionary = _build(artifacts, fixture)
	var declared: Array = fixture.catalog.evidence_gaps
	_expect(errors, not declared.is_empty(), "the committed catalog declares evidence gaps")
	var expected := []
	for gap in declared:
		expected.append({
			"id": gap.id, "description": gap.description,
			"source_ids": gap.source_ids.duplicate(), "issues": gap.issues.duplicate(),
		})
	expected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.id) < str(b.id))
	_expect(errors, report.get("catalog_evidence_gaps", []) == expected,
		"the catalog's declared evidence gaps are published in the report, sorted by id")
	var markdown: String = artifacts.markdown(report)
	var records: Array = report.get("issue_coverage", {}).get("records", [])
	for gap in declared:
		_expect(errors, markdown.contains(str(gap.id)) and markdown.contains(str(gap.description)),
			"declared gap %s reaches the Markdown projection" % gap.id)
		for issue_id in gap.issues:
			var record: Dictionary = records[int(issue_id) - 1]
			_expect(errors, str(gap.id) in record.linked_evidence_ids,
				"issue %d links its declaring gap %s" % [int(issue_id), gap.id])


static func _test_element_render_request_filter(artifacts: Script, errors: PackedStringArray) -> void:
	var fixture := _valid_fixture()
	for kind in ["hill", "immelmann", "cutback", "twisted_drop", "dive", "wave_turn",
		"overbank", "turn", "rise", "crest", "fall", "commit", "vertical-entry",
		"pullout", "exit", "slow-crest", "brake_run"]:
		_append_copy(fixture.seed_measurements[1].beats, 0, {
			"beat_id": "beat-%s" % kind, "kind": kind, "story_slot_id": "act1.%s" % kind,
		})
	var actual := []
	for request in _build(artifacts, fixture).get("render_requests", []):
		if request.get("artifact_kind") == "element":
			actual.append(request.get("beat_id"))
	_expect(errors, actual == ["act-one/00/loop", "beat-commit", "beat-crest", "beat-cutback",
		"beat-dive", "beat-exit", "beat-fall", "beat-hill", "beat-immelmann",
		"beat-overbank", "beat-pullout", "beat-rise", "beat-slow-crest", "beat-turn", "beat-twisted_drop",
		"beat-vertical-entry", "beat-wave_turn"],
		"all physical element and marquee phase kinds produce side-view requests")


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
			and records[0].generated_time_s == 11.0 and records[0].row_id == "row-04"
			and records[0].row_offset_m == 6.45,
			"every valid evidence row selector resolves the unique row-04 POV midpoint")


static func _test_compiled_anchor_identity(artifacts: Script, errors: PackedStringArray) -> void:
	var rows := [{"row_id": "row-04", "offset": 6.45,
		"window_start_s": 8.0, "window_end_s": 9.0}]
	var measurement := {"duration": 20.0, "beats": [{
		"beat_id": "act-one/giant-inversion/00-immelmann", "story_slot_id": "act-one",
		"window_role": "giant-inversion", "kind": "immelmann", "occurrence": 0,
		"window_id": "act-one/giant-inversion/00-immelmann", "rows": rows,
	}, {
		"beat_id": "act-one/giant-inversion/01-loop", "story_slot_id": "act-one",
		"window_role": "giant-inversion", "kind": "loop", "occurrence": 1,
		"window_id": "act-one/giant-inversion/01-loop", "rows": rows,
	}]}
	var resolution_errors: Array[String] = []
	var resolution: Dictionary = artifacts._center_row_resolution(measurement, {
		"story_slot_id": "act-one", "window_role": "giant-inversion", "kind": "loop",
		"occurrence": 1, "window_id": "act-one/giant-inversion/01-loop",
	}, resolution_errors)
	_expect(errors, resolution_errors.is_empty()
		and resolution.get("beat_id") == "act-one/giant-inversion/01-loop",
		"artifact POV resolution honors the complete stable compiled identity")


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
			"row_id": "row-04", "position": "middle",
			"offset": 6.45, "window_start_s": 10.1, "window_end_s": 11.9,
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
			"legacy_anchor": {"phase": "act-one", "kind": "loop", "occurrence": 0, "window_role": "whole"},
			"compiled_anchor": {"story_slot_id": "act1.loop", "window_role": "core"},
		}},
		"transforms": {"observed.identity@1": {
			"kind": "identity", "factor": 1.0,
			"formula": "target_value = observed_value", "approval": "identity; no transform",
		}},
		"sources": {
			"source.raw": {
				"initial_state": "executable", "state": "executable",
				"permitted_contributions": ["quantitative force targets"],
				"permitted_axes": ["normal_g"],
				"promotion_prerequisites": ["raw artifact and metadata retained"],
				"acquisition": "raw", "url": "https://example.invalid/raw",
				"recording_id": "fixture-raw", "retrieved_on": "2026-08-09",
				"retrieval_context": "artifact test fixture",
				"artifact_path": "evidence/raw.json", "artifact_sha256": "a".repeat(64),
				"metadata_artifact_path": "evidence/raw-metadata.json", "metadata_artifact_sha256": "9".repeat(64),
				"review_path": "evidence/raw-review.json", "review_sha256": "b".repeat(64),
				"row_seat": "row-02", "device": "fixture sensor", "sample_rate_hz": 100.0,
				"axis_mapping": {"sensor_z": "normal_g"}, "reliability": "fixture",
				"processing": ["excluded"], "caveats": [],
				"windows": [
					{"id": "landmark.point", "window_s": [1.0, 1.5]},
					{"id": "landmark.window", "window_s": [2.0, 3.0]},
				],
			},
			"youtube.unaligned": {
				"initial_state": "observation_only", "state": "observation_only",
				"permitted_contributions": ["qualitative review"], "permitted_axes": [],
				"promotion_prerequisites": ["raw sampled telemetry required for targets"],
				"acquisition": "raw_fetch_unavailable", "url": "https://example.invalid/video",
				"video_id": "video", "retrieved_on": "2026-08-09",
				"retrieval_context": "artifact test fixture",
				"diagnostic_path": "evidence/video-fetch-diagnostic.json",
				"diagnostic_sha256": "c".repeat(64),
				"metadata_diagnostic_path": "evidence/video-diagnostic.json",
				"metadata_diagnostic_sha256": "d".repeat(64),
				"review_path": "evidence/video-review.json",
				"review_sha256": "e".repeat(64),
				"fallback_citations": [{
					"document": "docs/TELEMETRY.md", "section_id": "fixture", "line_anchor": "fixture",
					"columns_used": ["time"], "source_windows_used": [[3.5, 4.5]],
				}],
				"row_seat": "unknown", "device": "unknown", "sample_rate_hz": null,
				"axis_mapping": {}, "reliability": "observation only",
				"processing": ["metadata only"], "caveats": ["sample rate unknown"],
				"windows": [{"id": "video.crest", "time_s": 4.0}],
			},
		},
		"observations": [
			_aligned_observation("obs.point", "landmark.point"),
			_aligned_observation("obs.window", "landmark.window"),
		],
		"targets": [{
			"id": "target.load", "observation_id": "obs.window",
			"semantic_selector_id": "selector.loop", "dimension": "loads",
			"metric": "normal_peak_positive", "hold_seconds": null,
			"raw_range": [1.0, 1.5], "target_range": [1.0, 1.5], "issues": [1, 9],
			"aggregation": {"row": "maximum", "beat": "maximum", "seed": "median"},
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
		"id": observation_id, "state": "executable", "source_id": "source.raw",
		"source_window_id": landmark_id, "source_axis": "sensor_z", "mapped_axis": "normal_g",
		"row_seat": "row-02", "duration_s": 0.5 if landmark_id == "landmark.point" else 1.0,
		"metric": "normal_peak_positive", "hold_seconds": null, "raw_range": [1.0, 1.5],
		"transform_id": "observed.identity@1", "confidence": "high",
		"confidence_rationale": "fixture", "corroborating_observation_ids": [],
		"semantic_selector_id": "selector.loop",
		"alignment": {
			"source_landmark_id": landmark_id,
			"generated_anchor": {"semantic_selector_id": "selector.loop"},
			"method": "fixture alignment", "uncertainty_s": 0.1,
			"row_compatibility": "same-row",
			"generated_row_selector": {"row_id": "row-02"},
			"rationale": "fixture",
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
			"canonical_sha256": "2fc1b0c7df31bf9a6fff87cee24ff5e0dce85b02bcd2508110c87ab43f124d8b", "validation_status": "valid",
		},
		"fleet": [11, 42, 20260809, 1],
		"generation_counts": {"11": 1, "42": 1, "20260809": 1, "1": 1},
		"measurement_summaries": [
			_measurement_summary(11, 111.0, 11.0, []),
			_measurement_summary(42, 142.0, 12.0, [{
				"beat_id": "act-one/00/loop", "story_slot_id": "act1.loop",
				"window_role": "core", "kind": "loop", "window_s": [10.0, 12.0],
				"rows": [{
					"row_id": "row-04", "position": "middle",
					"offset": 6.45, "window_start_s": 10.1, "window_end_s": 11.9,
				}],
			}]),
			_measurement_summary(20260809, 109.0, 19.0, []),
			_measurement_summary(1, 101.0, 11.0, []),
		],
		"findings": [{"target_id": "target.load", "metric": "normal_peak_positive"}],
		"observed_only": [{"observation_id": "obs.point", "seed": 42, "value": 1.5}],
		"evidence_gaps": [{"target_id": "target.load", "seed": 1, "reason": "row-not-found"}],
		"catalog_evidence_gaps": [{
			"id": "gap.unmeasured", "description": "No executable evidence.",
			"source_ids": ["youtube.unaligned"], "issues": [7, 8, 9, 10, 11, 12, 13, 15],
		}],
		"recommendation": {"status": "recommended", "target_id": "target.load"},
		"evidence_snapshot": [
			{
				"source_id": "source.raw", "state": "executable", "acquisition": "raw",
				"artifact_path": "evidence/raw.json", "artifact_sha256": "a".repeat(64),
				"metadata_artifact_path": "evidence/raw-metadata.json",
				"metadata_artifact_sha256": "9".repeat(64),
				"review_path": "evidence/raw-review.json", "review_sha256": "b".repeat(64),
			},
			{
				"source_id": "youtube.unaligned", "state": "observation_only",
				"acquisition": "raw_fetch_unavailable",
				"diagnostic_path": "evidence/video-fetch-diagnostic.json",
				"diagnostic_sha256": "c".repeat(64),
				"metadata_diagnostic_path": "evidence/video-diagnostic.json",
				"metadata_diagnostic_sha256": "d".repeat(64),
				"review_path": "evidence/video-review.json",
				"review_sha256": "e".repeat(64),
				"fallback_citations": [{
					"document": "docs/TELEMETRY.md", "section_id": "fixture", "line_anchor": "fixture",
					"columns_used": ["time"], "source_windows_used": [[3.5, 4.5]],
				}],
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
	for spec in [["obs.point", "landmark.point", {"kind": "window", "window_s": [1.0, 1.5]}],
		["obs.window", "landmark.window", {"kind": "window", "window_s": [2.0, 3.0]}]]:
		records.append({
			"source_id": "source.raw", "source_landmark_id": spec[1],
			"source_time": spec[2], "observation_id": spec[0],
			"semantic_selector_id": "selector.loop", "alignment_method": "fixture alignment",
			"uncertainty_s": 0.1, "row_compatibility": "same-row",
			"generated_seed": 42, "generated_anchor": {"semantic_selector_id": "selector.loop"},
			"generated_beat_id": "act-one/00/loop", "generated_window_s": [10.1, 11.9],
			"generated_time_s": 11.0, "row_id": "row-04", "row_offset_m": 6.45,
			"generated_pov_path": "review/seed-42/pov/act-one__00__loop.png",
		})
	return {
		"schema_version": "fidelity-pov-map@1",
		"source_landmarks": [
			{
				"source_id": "source.raw", "landmark_id": "landmark.point",
				"source_time": {"kind": "window", "window_s": [1.0, 1.5]},
			},
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
	## The fixture gap declares these issues; the declaration survives whatever else covers them.
	if state != "evidence-gap" and issue_id in [7, 8, 9, 10, 11, 12, 13, 15]:
		evidence = (evidence + ["gap.unmeasured"])
		evidence.sort()
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
		"generated_time_s": 11.0, "row_id": "row-04", "row_offset_m": 6.45,
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

## Catalog evidence gaps
| gap | issues | sources | description |
| --- | --- | --- | --- |
| gap.unmeasured | 7, 8, 9, 10, 11, 12, 13, 15 | youtube.unaligned | No executable evidence. |

## Recommendation
recommended: target.load

## Evidence snapshot
| source | state | acquisition |
| --- | --- | --- |
| source.raw | executable | raw |
| youtube.unaligned | observation_only | raw_fetch_unavailable |

## POV map
| source | landmark | observation | generated beat | source time |
| --- | --- | --- | --- | --- |
| source.raw | landmark.point | obs.point | act-one/00/loop | window 1.000000–1.500000 |
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
| 9 | Entry-launch speed | measured | target.load | gap.unmeasured, obs.window, source.raw | review/seed-42/channels.png |
| 10 | Issue 10 | evidence-gap |  | gap.unmeasured |  |
| 11 | Issue 11 | evidence-gap |  | gap.unmeasured |  |
| 12 | Flats | review-prompt |  | gap.unmeasured, prompt.terrain, source.raw | review/seed-42/channels.png |
| 13 | Issue 13 | evidence-gap |  | gap.unmeasured |  |
| 14 | Multidimensional scaling | review-prompt |  | prompt.shaping, source.raw | review/seed-42/channels.png |
| 15 | Transition jerk | review-prompt |  | gap.unmeasured, prompt.feel, source.raw | review/seed-42/channels.png |
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


const EXPECTED_PACK_FILES := [
	"audit.json", "audit.md", "manifest.json",
	"review/checklist.md", "review/issue-coverage.json", "review/issue-coverage.md",
	"review/pov-map.json", "review/pov-map.md",
	"review/seed-11/channels.json", "review/seed-11/channels.md", "review/seed-11/channels.png",
	"review/seed-11/elevation.png", "review/seed-11/top.png",
	"review/seed-20260809/channels.json", "review/seed-20260809/channels.md",
	"review/seed-20260809/channels.png", "review/seed-20260809/elevation.png",
	"review/seed-20260809/top.png",
	"review/seed-42/channels.json", "review/seed-42/channels.md", "review/seed-42/channels.png",
	"review/seed-42/elements/act-one__00__loop.png", "review/seed-42/elevation.png",
	"review/seed-42/pov/act-one__00__loop.png", "review/seed-42/top.png",
]

## Eleven constant channels over level, straight, unbanked track: every plot rule is predictable.
const EXPECTED_CHANNEL_SPECS := [
	["speed_kmh", "Speed", "km/h", 36.0],
	["normal_g", "Normal proper acceleration", "g", 1.0],
	["lateral_g", "Lateral proper acceleration", "g", 0.0],
	["longitudinal_proper_g", "Longitudinal proper acceleration", "g", 0.0],
	["pitch_deg", "Pitch", "deg", 0.0],
	["roll_rate_dps", "Roll rate", "deg/s", 0.0],
	["agl_m", "Height above ground", "m", 30.0],
	["reconstructed_curvature_inv_m", "Reconstructed curvature", "1/m", 0.0],
	["radius_m", "Radius", "m", null],
	["roll_acceleration_dps2", "Roll acceleration", "deg/s^2", 0.0],
	["jerk_mps3", "Inertial jerk magnitude", "m/s^3", 0.0],
]

const EXPECTED_CHANNELS_MARKDOWN := """# Channel legend — seed 11

Image: review/seed-11/channels.png (1400x1650)

| index | channel | label | unit | plot min | plot max | bounded | unbounded | series | color |
| ---: | --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- |
| 0 | speed_kmh | Speed | km/h | 36.000000 | 36.001000 | 41 | 0 | raw_generated | 0.550000, 0.950000, 1.000000, 1.000000 |
| 1 | normal_g | Normal proper acceleration | g | 1.000000 | 1.001000 | 41 | 0 | raw_generated | 0.550000, 0.950000, 1.000000, 1.000000 |
| 2 | lateral_g | Lateral proper acceleration | g | 0.000000 | 0.001000 | 41 | 0 | raw_generated | 0.550000, 0.950000, 1.000000, 1.000000 |
| 3 | longitudinal_proper_g | Longitudinal proper acceleration | g | 0.000000 | 0.001000 | 41 | 0 | raw_generated | 0.550000, 0.950000, 1.000000, 1.000000 |
| 4 | pitch_deg | Pitch | deg | 0.000000 | 0.001000 | 41 | 0 | raw_generated | 0.550000, 0.950000, 1.000000, 1.000000 |
| 5 | roll_rate_dps | Roll rate | deg/s | 0.000000 | 0.001000 | 41 | 0 | raw_generated | 0.550000, 0.950000, 1.000000, 1.000000 |
| 6 | agl_m | Height above ground | m | 30.000000 | 30.001000 | 41 | 0 | raw_generated | 0.550000, 0.950000, 1.000000, 1.000000 |
| 7 | reconstructed_curvature_inv_m | Reconstructed curvature | 1/m | 0.000000 | 0.001000 | 41 | 0 | raw_generated | 0.550000, 0.950000, 1.000000, 1.000000 |
| 8 | radius_m | Radius | m | 0.000000 | 1.000000 | 0 | 41 | raw_generated | 0.550000, 0.950000, 1.000000, 1.000000 |
| 9 | roll_acceleration_dps2 | Roll acceleration | deg/s^2 | 0.000000 | 0.001000 | 41 | 0 | raw_generated | 0.550000, 0.950000, 1.000000, 1.000000 |
| 10 | jerk_mps3 | Inertial jerk magnitude | m/s^3 | 0.000000 | 0.001000 | 41 | 0 | raw_generated | 0.550000, 0.950000, 1.000000, 1.000000 |
"""


static func _expected_legend(seed_value: int) -> Dictionary:
	var strips := []
	for index in EXPECTED_CHANNEL_SPECS.size():
		var spec: Array = EXPECTED_CHANNEL_SPECS[index]
		var constant: Variant = spec[3]
		var unbounded: bool = constant == null
		strips.append({
			"index": index, "channel_id": spec[0], "label": spec[1], "unit": spec[2],
			"plot_min": 0.0 if unbounded else float(constant),
			"plot_max": 1.0 if unbounded else float(constant) + 0.001,
			"bounded_count": 0 if unbounded else 41, "unbounded_count": 41 if unbounded else 0,
			"series": [{"role": "raw_generated", "color_rgba": [0.55, 0.95, 1.0, 1.0]}],
		})
	return {
		"schema_version": "fidelity-channel-legend@1",
		"image_path": "review/seed-%d/channels.png" % seed_value, "seed": seed_value,
		"width": 1400, "height": 1650, "strips": strips,
	}


## The standalone review files are the same body the aggregate audit prints, under their own title.
static func _expected_standalone(title: String, next_title: String) -> String:
	var body: String = EXPECTED_MARKDOWN.split("## %s\n" % title)[1].split(
		"\n\n## %s" % next_title)[0]
	return "# %s\n\n%s\n" % [title, body]


static func _pack_fixture() -> Dictionary:
	var fixture := _valid_fixture()
	fixture.seed_measurements[1].beats[0].merge({"start_distance": 0.0, "end_distance": 200.0})
	return fixture


static func _pack_routes() -> Dictionary:
	var routes := {}
	for seed_value in [11, 42, 20260809]:
		routes[seed_value] = _pack_route(seed_value)
	return routes


static func _pack_route(seed_value: int) -> Dictionary:
	var route := {
		"seed": seed_value, "length": 200.0, "duration": 20.0,
		"positions": PackedVector3Array(), "tangents": PackedVector3Array(),
		"ups": PackedVector3Array(), "rights": PackedVector3Array(),
		"curvatures": PackedVector3Array(), "banks": PackedFloat32Array(),
		"speeds": PackedFloat32Array(), "normal_g": PackedFloat32Array(),
		"lateral_g": PackedFloat32Array(), "longitudinal_g": PackedFloat32Array(),
		"roll_rates": PackedFloat32Array(), "distances": PackedFloat32Array(),
		"times": PackedFloat32Array(), "span_indices": PackedInt32Array(),
		"terrain": {
			"relief": 1.0, "face_height": 0.0, "apron_height": 0.0,
			"edge_normal": Vector2(0.0, -1.0), "edge_offset": 0.0, "apron_width": 1.0,
			"face_width": 1.0, "wobble_amplitude": 0.0, "wobble_wavelength": 1.0,
			"detail_amplitude": 0.0, "noise_seed": 0,
		},
		"gesture_windows": [{
			"story_slot_id": "act-one", "display_name": "Act One",
			"first": 0, "last": 19, "start_time_s": 0.0, "end_time_s": 9.5,
			"start_distance_m": 0.0, "end_distance_m": 95.0,
			"role_windows": [{
				"id": "giant-inversion", "display_name": "Loop", "diagnostic_kind": "loop",
				"window_id": "act-one/giant-inversion/00-loop", "first": 0, "last": 9,
				"start_time_s": 0.0, "end_time_s": 4.5,
			}, {
				"id": "handoff", "display_name": "Handoff", "diagnostic_kind": "",
				"window_id": "act-one/handoff/00", "first": 10, "last": 19,
				"start_time_s": 5.0, "end_time_s": 9.5,
			}],
		}, {
			"story_slot_id": "brakes-station-capture", "display_name": "Brakes Station Capture",
			"diagnostic_kind": "dive",
			"window_id": "brakes-station-capture/whole/00-dive",
			"first": 20, "last": 40, "start_time_s": 10.0, "end_time_s": 20.0,
			"start_distance_m": 100.0, "end_distance_m": 200.0,
			"role_windows": [{
				"id": "brakes", "display_name": "Brakes", "diagnostic_kind": "",
				"window_id": "brakes-station-capture/brakes/00-brake_run", "first": 20, "last": 40,
				"start_time_s": 10.0, "end_time_s": 20.0,
			}],
		}],
	}
	for index in 41:
		route.positions.append(Vector3(index * 5.0, 30.0, 0.0))
		route.tangents.append(Vector3.RIGHT)
		route.ups.append(Vector3.UP)
		route.rights.append(Vector3.BACK)
		route.curvatures.append(Vector3.ZERO)
		route.banks.append(0.0)
		route.speeds.append(10.0)
		route.normal_g.append(1.0)
		route.lateral_g.append(0.0)
		route.longitudinal_g.append(0.0)
		route.roll_rates.append(0.0)
		route.distances.append(index * 5.0)
		route.times.append(index * 0.5)
		route.span_indices.append(0 if index < 20 else 1)
	return route


static func _overlay_fixture(count: int) -> Dictionary:
	var comparisons := []
	for index in count:
		var id := "test-%d" % index
		var source_samples := [
			{"time_s": 0.0, "normal_g": -1.0, "lateral_g": 0.5,
				"longitudinal_g": -0.25, "eligible": true},
			{"time_s": 0.9, "normal_g": 2.0, "lateral_g": -0.5,
				"longitudinal_g": 0.25, "eligible": true},
		]
		var target_samples: Array = source_samples.duplicate(true)
		target_samples[1].longitudinal_g = null
		var generated_samples := [
			{"time_s": 10.0, "normal_g": -0.5, "lateral_g": 0.25,
				"longitudinal_g": -0.1, "eligible": true},
			{"time_s": 10.9, "normal_g": 1.5, "lateral_g": -0.25,
				"longitudinal_g": 0.1, "eligible": true},
		]
		comparisons.append({
			"comparison_id": id, "alignment_status": "semantic_only",
			"evidence_class": "local-diagnostic", "source_id": "rfdb-4804",
			"source": {"status": "available", "clock": "source-local-seconds",
				"window_s": [0.0, 1.0], "duration_s": 1.0, "sample_count": 2},
			"generated": {"status": "available", "clock": "generated-route-seconds",
				"seed": 42, "beat_id": "act-one/00/loop", "story_slot_id": "act1.loop",
				"window_role": "core", "window_s": [10.0, 11.0],
				"duration_s": 1.0, "sample_count": 2},
			"lanes": [
				{"role": "source_observed_raw", "status": "evidence_gap", "samples": []},
				{"role": "source_observed_smoothed", "status": "available", "clock": "source",
					"samples": source_samples},
				{"role": "approved_scaled_target", "status": "available", "clock": "source",
					"samples": target_samples},
				{"role": "generated_raw", "status": "available", "clock": "generated",
					"samples": generated_samples},
			],
			"markers": [{"id": "entry", "time_s": 0.0, "uncertainty_s": 0.1},
				{"id": "apex", "time_s": 0.5, "uncertainty_s": 0.1},
				{"id": "exit", "time_s": 1.0, "uncertainty_s": 0.1}],
			"caveats": ["semantic markers only"],
			"artifact_path": "review/overlays/%s.png" % id,
		})
	return {"schema_version": "fidelity-semantic-overlays@1", "manifest_sha256": "a".repeat(64),
		"recordings": [], "comparisons": comparisons, "gaps": [], "errors": [], "status": "ok"}


static func _make_source_gap(comparison: Dictionary) -> void:
	comparison.source.status = "source_trace_unavailable"; comparison.source.sample_count = 0
	for lane: Dictionary in comparison.lanes:
		if lane.role in ["source_observed_smoothed", "approved_scaled_target"]:
			lane.status = "source_trace_unavailable"; lane.samples = []


static func _make_generated_gap(comparison: Dictionary) -> void:
	comparison.generated.status = "generated_window_unavailable"
	comparison.generated.window_s = null; comparison.generated.duration_s = null
	comparison.generated.sample_count = 0
	for lane: Dictionary in comparison.lanes:
		if lane.role == "generated_raw": lane.status = "generated_window_unavailable"; lane.samples = []


static func _column_has_color(
	image: Image, x: int, color: Color, first_y: int, last_y: int
) -> bool:
	for y in range(first_y, last_y):
		var pixel := image.get_pixel(x, y)
		if absf(pixel.r - color.r) < 0.01 and absf(pixel.g - color.g) < 0.01 \
			and absf(pixel.b - color.b) < 0.01: return true
	return false


static func _file_bytes(directory: String) -> Dictionary:
	var output := {}
	for path in _relative_files(directory):
		output[path] = FileAccess.get_file_as_bytes("%s/%s" % [directory, path])
	return output


static func _relative_files(directory: String, prefix: String = "") -> PackedStringArray:
	var output := PackedStringArray()
	for name in DirAccess.get_files_at(directory):
		output.append(prefix + name)
	for name in DirAccess.get_directories_at(directory):
		output.append_array(_relative_files("%s/%s" % [directory, name], "%s%s/" % [prefix, name]))
	output.sort()
	return output


static func _reset_directory(directory: String) -> void:
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
		return
	for name in DirAccess.get_directories_at(directory):
		_reset_directory("%s/%s" % [directory, name])
	for name in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute("%s/%s" % [directory, name])
	DirAccess.remove_absolute(directory)
	DirAccess.make_dir_recursive_absolute(directory)


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
