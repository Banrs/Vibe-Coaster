extends SceneTree

const FIDELITY_PATH := "res://fidelity.gd"
const REFERENCES_PATH := "res://fidelity_references.gd"
const GENERATOR_PATH := "res://generator.gd"
const LEGACY_BASE_COMMIT := "3fa14885bef2daf3a7d9c0e544424cb6a296fd99"


func _initialize() -> void:
	var errors := run()
	for error in errors:
		printerr(error)
	quit(0 if errors.is_empty() else 1)


static func run() -> PackedStringArray:
	var errors := PackedStringArray()
	if not ResourceLoader.exists(FIDELITY_PATH):
		errors.append("RideFidelity is missing")
		return errors
	var fidelity: Script = load(FIDELITY_PATH)
	_test_legacy_input_boundary(errors)
	_test_held_values(fidelity, errors)
	_test_composite_grouping(fidelity, errors)
	_test_legacy_characterization(fidelity, errors)
	_test_catalog_validation(fidelity, errors)
	_test_route_measurements(fidelity, errors)
	_test_reference_catalog(fidelity, errors)
	return errors


static func _test_legacy_input_boundary(errors: PackedStringArray) -> void:
	if not ResourceLoader.exists(GENERATOR_PATH):
		errors.append("RideGenerator is missing")
		return
	var generator: Script = load(GENERATOR_PATH)
	var route: Variant = generator.build(42)
	_expect(errors, route is Dictionary, "legacy generator build returns a Dictionary")
	if not route is Dictionary:
		return
	_expect(errors, LEGACY_BASE_COMMIT == "3fa14885bef2daf3a7d9c0e544424cb6a296fd99", "legacy report contract pins the pre-foundation commit")
	for key in ["positions", "tangents", "ups", "rights", "curvatures"]:
		_expect(errors, route.get(key) is PackedVector3Array, "legacy generator keeps packed vector channel %s" % key)
	for key in [
		"banks", "speeds", "normal_g", "lateral_g", "longitudinal_g", "roll_rates",
		"distances", "times",
	]:
		_expect(errors, route.get(key) is PackedFloat32Array, "legacy generator keeps packed float channel %s" % key)
	for key in ["section_indices", "lsm_ids"]:
		_expect(errors, route.get(key) is PackedInt32Array, "legacy generator keeps packed integer channel %s" % key)
	_expect(errors, route.get("sections") is Array, "legacy generator keeps sections")
	for script_path in [FIDELITY_PATH, "res://_inspect.gd", "res://fidelity_tests.gd"]:
		var dependencies := ResourceLoader.get_dependencies(script_path)
		for forbidden_path in ["res://ride_route.gd", "res://motion_trajectory.gd", "res://legacy_route_adapter.gd"]:
			_expect(errors, not dependencies.has(forbidden_path), "%s does not import %s" % [script_path, forbidden_path])


static func _test_held_values(fidelity: Script, errors: PackedStringArray) -> void:
	var positive := PackedFloat32Array([1.0, 2.0, 2.0, 2.0, 1.0])
	var negative := PackedFloat32Array([0.0, -1.0, -1.0, -1.0, 0.0])
	_expect_close(errors, fidelity.held(positive, 1.0, 0.02), 2.0, "three samples hold +2 g")
	_expect_close(errors, fidelity.held(negative, -1.0, 0.02), -1.0, "three samples hold -1 g")
	_expect(errors, is_inf(fidelity.held(positive, 1.0, 0.05)), "a hold longer than the series returns infinity")


static func _test_composite_grouping(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _grouping_route()
	var bands: Array = fidelity.element_bands(route)
	_expect(errors, bands.size() == 3, "two sections sharing one element form one beat")
	if bands.size() != 3:
		return
	_expect(errors, bands[0].kind == "hill", "the composite beat keeps its element kind")
	_expect(errors, bands[0].beat_id == "act-one/00/hill", "the composite beat gets a stable ID")
	_expect(errors, bands[0].first == 0 and bands[0].last == 18, "the composite beat spans both sections")
	_expect(errors, bands[1].kind == "Transfer", "a grade section is a distinct named beat")
	_expect(errors, bands[2].beat_id == "act-one/02/turn", "later beats advance the phase ordinal")


static func _test_legacy_characterization(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _legacy_characterization_route()
	var before := route.duplicate(true)
	var bands: Array = fidelity.element_bands(route, 2.0)
	if bands.is_empty():
		errors.append("legacy characterization produces element bands")
		return
	_expect(errors, bands[0].beat_id == "act-one/00/hill", "legacy adapter keeps its stable beat ID")
	_expect_close(errors, bands[0].window_start_distance, 2.0, "rear row enters after its offset")
	fidelity.measure_route(route, [0.0, 2.0])
	_expect(errors, route == before, "fidelity measurement is read-only")


static func _test_catalog_validation(fidelity: Script, errors: PackedStringArray) -> void:
	var catalog := _valid_catalog()
	_expect(errors, fidelity.validate_catalog(catalog).is_empty(), "a complete catalog validates")

	var duplicate: Dictionary = catalog.duplicate(true)
	duplicate.targets.append(duplicate.targets[0].duplicate(true))
	_expect_contains(errors, fidelity.validate_catalog(duplicate), "duplicate target id", "duplicate target IDs are rejected")

	var invalid_range: Dictionary = catalog.duplicate(true)
	invalid_range.targets[0].target_range = [2.0, 1.0]
	_expect_contains(errors, fidelity.validate_catalog(invalid_range), "invalid target_range", "descending target ranges are rejected")

	var missing_source: Dictionary = catalog.duplicate(true)
	missing_source.targets[0].source_ids = ["missing"]
	_expect_contains(errors, fidelity.validate_catalog(missing_source), "unknown source", "unknown source IDs are rejected")

	var unsupported_metric: Dictionary = catalog.duplicate(true)
	unsupported_metric.targets[0].metric = "magic"
	_expect_contains(errors, fidelity.validate_catalog(unsupported_metric), "unsupported metric", "unsupported metrics are rejected")


static func _test_route_measurements(fidelity: Script, errors: PackedStringArray) -> void:
	if not _script_has_method(fidelity, "measure_route"):
		errors.append("RideFidelity.measure_route is missing")
		return
	var measured: Dictionary = fidelity.measure_route(_measurement_route(), [0.0, 2.0])
	_expect(errors, measured.get("beats", []).size() == 3, "measurement retains composite, grade, and closure beats")
	if measured.get("beats", []).is_empty():
		return
	var beat: Dictionary = measured.beats[0]
	_expect(errors, beat.rows.size() == 2, "every requested train row is measured")
	if beat.rows.size() == 2:
		_expect_close(errors, beat.rows[1].window_start_distance, 2.0, "rear-row window starts when that row reaches the beat")
		_expect_close(errors, beat.rows[1].window_end_distance, 22.0, "rear-row window ends when that row leaves the beat")
		_expect_close(errors, beat.rows[1].loads.normal_peak_positive, 1.0, "constant synthetic normal load remains one g")
		_expect_close(errors, beat.rows[1].loads.lateral_peak_absolute, 0.0, "constant synthetic lateral load remains zero")
	_expect_close(errors, beat.geometry.length, 20.0, "beat geometry reports track length")
	_expect_close(errors, beat.geometry.height, 10.0, "beat geometry reports vertical scale")
	_expect_close(errors, beat.geometry.width, 20.0, "beat geometry reports plan displacement")
	_expect_close(errors, beat.pacing.duration, 2.0, "beat pacing reports elapsed duration")
	_expect_close(errors, beat.pacing.speed_loss, 0.0, "constant speed has no energy loss")
	_expect_close(errors, beat.terrain.agl_median, 5.0, "terrain scorecard reports median AGL")
	_expect_close(errors, beat.flow.transition_force_swing, 0.0, "constant-force seam has no transition swing")
	for dimension in ["loads", "geometry", "pacing", "terrain", "flow"]:
		_expect(errors, measured.dimensions.has(dimension), "route aggregate includes %s" % dimension)


static func _test_reference_catalog(fidelity: Script, errors: PackedStringArray) -> void:
	if not ResourceLoader.exists(REFERENCES_PATH):
		errors.append("RideFidelityReferences is missing")
		return
	var references: Script = load(REFERENCES_PATH)
	var catalog: Dictionary = references.CATALOG
	for error in fidelity.validate_catalog(catalog):
		errors.append("reference catalog: %s" % error)
	var covered := {}
	for collection in [catalog.get("targets", []), catalog.get("review_prompts", []), catalog.get("evidence_gaps", [])]:
		for record in collection:
			for issue in record.get("issues", []):
				covered[int(issue)] = true
	for issue in range(1, 17):
		_expect(errors, covered.has(issue), "reference catalog covers issue %d" % issue)


static func _grouping_route() -> Dictionary:
	var shared := {"kind": "hill", "rise": 12.0}
	var other := {"kind": "turn", "heading_change_deg": 30.0}
	var count := 31
	var times := PackedFloat32Array()
	var distances := PackedFloat32Array()
	var normal := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	var longitudinal := PackedFloat32Array()
	for i in count:
		times.append(i * 0.01)
		distances.append(float(i))
		normal.append(1.0)
		lateral.append(0.0)
		longitudinal.append(0.0)
	return {
		"times": times,
		"distances": distances,
		"normal_g": normal,
		"lateral_g": lateral,
		"longitudinal_g": longitudinal,
		"sections": [
			{"kind": "FVD", "name": "hill-a", "element": shared, "phase": "act one", "start_index": 0, "end_index": 9},
			{"kind": "FVD", "name": "hill-b", "element": shared, "phase": "act one", "start_index": 9, "end_index": 18},
			{"kind": "GRADE", "name": "Transfer", "element": {}, "phase": "act one", "start_index": 18, "end_index": 24},
			{"kind": "FVD", "name": "turn", "element": other, "phase": "act one", "start_index": 24, "end_index": 30},
		],
	}


static func _measurement_route(shared_element_identity: bool = true) -> Dictionary:
	var shared := {"kind": "hill", "rise": 10.0}
	var second_element: Dictionary = shared if shared_element_identity else shared.duplicate(true)
	var positions := PackedVector3Array()
	var tangents := PackedVector3Array()
	var ups := PackedVector3Array()
	var rights := PackedVector3Array()
	var curvatures := PackedVector3Array()
	var banks := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var normal := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	var longitudinal := PackedFloat32Array()
	var roll_rates := PackedFloat32Array()
	var distances := PackedFloat32Array()
	var times := PackedFloat32Array()
	for i in 41:
		var height := float(mini(i, 20 - i)) if i <= 20 else 0.0
		positions.append(Vector3(i, height, 0.0))
		tangents.append(Vector3.RIGHT)
		ups.append(Vector3.UP)
		rights.append(Vector3.FORWARD)
		curvatures.append(Vector3.ZERO)
		banks.append(0.0)
		speeds.append(10.0)
		normal.append(1.0)
		lateral.append(0.0)
		longitudinal.append(0.0)
		roll_rates.append(0.0)
		distances.append(float(i))
		times.append(i * 0.1)
	return {
		"seed": 7,
		"length": 40.0,
		"duration": 4.0,
		"positions": positions,
		"tangents": tangents,
		"ups": ups,
		"rights": rights,
		"curvatures": curvatures,
		"banks": banks,
		"speeds": speeds,
		"normal_g": normal,
		"lateral_g": lateral,
		"longitudinal_g": longitudinal,
		"roll_rates": roll_rates,
		"distances": distances,
		"times": times,
		"sections": [
			{"kind": "FVD", "name": "hill-a", "element": shared, "phase": "act one", "start_index": 0, "end_index": 10},
			{"kind": "FVD", "name": "hill-b", "element": second_element, "phase": "act one", "start_index": 10, "end_index": 20},
			{"kind": "GRADE", "name": "Transfer", "element": {}, "phase": "act one", "start_index": 20, "end_index": 30},
			{"kind": "CLOSURE", "name": "Closure", "element": {}, "phase": "run home", "start_index": 30, "end_index": 40},
		],
	}


static func _legacy_characterization_route() -> Dictionary:
	var route := _measurement_route(false)
	route["sections"][0]["element"] = route.sections[1].element
	route["sections"][0]["phase"] = "act one"
	route["sections"][1]["phase"] = "act one"
	return route


static func _valid_catalog() -> Dictionary:
	return {
		"schema_version": 1,
		"catalog_version": "test",
		"sources": {
			"source": {
				"document": "docs/TELEMETRY.md",
				"section": "test",
				"confidence": "high",
				"caveats": [],
			},
		},
		"targets": [
			{
				"id": "loads.hill.negative",
				"source_ids": ["source"],
				"confidence": "high",
				"caveats": [],
				"selector": {"kind": "hill"},
				"dimension": "loads",
				"metric": "normal_held_negative",
				"hold_seconds": 0.8,
				"recording_row": "unknown",
				"raw_range": [-1.0, -0.5],
				"transform": {"kind": "scale", "factor": 1.5},
				"target_range": [-1.5, -0.75],
				"issues": [13],
			},
		],
		"review_prompts": [],
		"evidence_gaps": [],
	}


static func _expect(errors: PackedStringArray, condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


static func _expect_close(errors: PackedStringArray, actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		errors.append("%s: got %s, expected %s" % [message, actual, expected])


static func _expect_contains(errors: PackedStringArray, values: PackedStringArray, needle: String, message: String) -> void:
	for value in values:
		if value.contains(needle):
			return
	errors.append("%s: %s" % [message, str(values)])


static func _script_has_method(script: Script, method_name: String) -> bool:
	for method in script.get_script_method_list():
		if method.name == method_name:
			return true
	return false
