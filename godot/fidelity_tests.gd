extends SceneTree

const FIDELITY_PATH := "res://fidelity.gd"


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
	_test_held_values(fidelity, errors)
	_test_composite_grouping(fidelity, errors)
	_test_catalog_validation(fidelity, errors)
	return errors


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
				"selector": {"kind": "hill"},
				"dimension": "loads",
				"metric": "normal_held_negative",
				"hold_seconds": 0.8,
				"row": "all",
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
