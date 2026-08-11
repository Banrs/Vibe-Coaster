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
	_test_element_render_request_filter(artifacts, errors)
	_test_center_row_alignment_selectors(artifacts, errors)
	_test_route_sampling(errors)
	_test_pov_camera(artifacts, errors)
	_test_checked_writes(artifacts, errors)
	_test_write_pack(artifacts, errors)
	_test_audit_fleet(errors)
	return errors


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
	var measure := func(route: Dictionary) -> Dictionary: return {"seed": route.seed}
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
## 0.35 m over the centre-row pose, with none of the viewer's speed-dependent widening.
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
	# The pack fixture is a straight 200 m loop along +X at y = 30 over flat ground, so 10 s in
	# the eye sits at (100, 30.35, 0), looks down +X with +Z to its right, and the 40 m ground
	# grid steps away from x = 80 — the far grid line is 300 m ahead.
	var image: Image = artifacts.pov_image(_pack_route(11), 10.0)
	_expect(errors, image.get_size() == CONTRACT_POV_SIZE,
		"the POV render is the contracted %s frame, not %s" % [CONTRACT_POV_SIZE, image.get_size()])
	if image.get_size() != CONTRACT_POV_SIZE:
		return
	var knot := _pov_pixel(320.0, -(30.0 + CONTRACT_POV_EYE_UP_M), 300.0)
	var ground_row := _pov_top_row_in_column(image, POV_GROUND_COLOR, 1200)
	_expect(errors, ground_row == roundi(knot.y),
		"the ground 300 m ahead lands where the %.1f degree vertical FOV puts it: row %d, not %d"
			% [CONTRACT_POV_FOV_DEG, roundi(knot.y), ground_row])
	_expect(errors, _pov_is(image, roundi(knot.x), roundi(knot.y), POV_GROUND_COLOR),
		"the grid knot 320 m right of that line lights its contracted pixel (%d, %d)"
			% [roundi(knot.x), roundi(knot.y)])

	# The rails ride 1.05 m under the pose, so the eye offset alone sets how steeply they fall
	# away from the vanishing point: 0.95 m right of and 1.40 m under the eye, 4 m ahead.
	var rail_under_eye := 1.05 + CONTRACT_POV_EYE_UP_M
	var rail := _pov_pixel(0.95, -rail_under_eye, 4.0)
	var rail_columns := _pov_columns(image, POV_TRACE_COLOR, roundi(rail.y), CONTRACT_POV_SIZE.x / 2)
	_expect(errors, rail_columns == PackedInt32Array([roundi(rail.x)]),
		"the eye rides %.2f m over the pose: the right rail 4 m ahead holds row %d at column %d, not %s"
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
	_expect(errors, top_row == roundi(far_right.y),
		"no rail is drawn above the far knot 98 m ahead on row %d, but row %d carries one"
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
		["all five checklist categories are present", "checklist category",
			func(value: Dictionary): value.catalog.review_prompts.pop_back()],
		["every issue has at least one traceability link", "issue 7",
			func(value: Dictionary): value.catalog.evidence_gaps[0].issues.erase(7)],
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
			"generated_time_s": 11.0,
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
		"times": PackedFloat32Array(),
		"terrain": {
			"relief": 1.0, "face_height": 0.0, "apron_height": 0.0,
			"edge_normal": Vector2(0.0, -1.0), "edge_offset": 0.0, "apron_width": 1.0,
			"face_width": 1.0, "wobble_amplitude": 0.0, "wobble_wavelength": 1.0,
			"detail_amplitude": 0.0, "noise_seed": 0,
		},
		"sections": [{
			"kind": "FVD", "name": "loop", "element": {"kind": "loop"}, "phase": "act one",
			"start_index": 0, "end_index": 40, "start_time": 0.0,
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
	return route


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
