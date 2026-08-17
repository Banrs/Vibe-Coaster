extends SceneTree

const RideGenerator := preload("res://generator.gd")

var _errors := PackedStringArray()


func _initialize() -> void:
	_test_every_material_role_publishes_an_explicit_contract_record()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _test_every_material_role_publishes_an_explicit_contract_record() -> void:
	var route := RideGenerator.build(42)
	if not _expect(route.get("ok", false),
			"seed 42 builds before element-contract publication is inspected: %s"
			% str(route.get("errors", []))):
		return
	var plan: Dictionary = route.get("terrain_story_plan", {}).get("plan", {})
	var expected_ids := []
	for role_value in plan.get("roles", []):
		if role_value is Dictionary:
			expected_ids.append(str(role_value.get("id", "")))
	var records_value: Variant = route.get("element_contracts")
	if not _expect(records_value is Dictionary,
			"accepted route publishes an element_contracts dictionary"):
		return
	var records: Dictionary = records_value
	var actual_ids: Array = records.keys()
	actual_ids.sort()
	var sorted_expected := expected_ids.duplicate()
	sorted_expected.sort()
	_expect(actual_ids == sorted_expected,
		"element-contract records exactly cover the plan's material roles; expected %s, got %s"
		% [str(sorted_expected), str(actual_ids)])
	for role_id in expected_ids:
		var record_value: Variant = records.get(role_id)
		if not _expect(record_value is Dictionary,
				"material role '%s' owns one contract record" % role_id):
			continue
		var record: Dictionary = record_value
		_expect(record.get("status") == "unadopted",
			"role '%s' is explicitly unadopted until a reviewed intent lands" % role_id)
		_expect(str(record.get("reason", "")).length() > 0,
			"unadopted role '%s' publishes why it is not a production geometry gate" % role_id)
		_expect(record.get("intent", {}) is Dictionary and record.get("intent", {}).is_empty(),
			"unadopted role '%s' cannot carry a hidden geometry intent" % role_id)
		var measurement_value: Variant = record.get("measurement")
		_expect(measurement_value is Dictionary
			and measurement_value.get("status") == "measured",
			"role '%s' still publishes an honest whole-element measurement" % role_id)
		var violations_value: Variant = record.get("violations")
		_expect(violations_value is PackedStringArray and violations_value.is_empty(),
			"unadopted role '%s' publishes no pretend pass/fail violations" % role_id)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_errors.append(message)
	return condition
