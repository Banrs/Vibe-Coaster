extends SceneTree

# Deliberately RED production gate for docs/ISSUES.md VC-016 (geometry-truth plan, Task 4).
# It is not in .github/focused-tests.txt: the planar recipe solves as an element but the return
# cannot re-close behind it within its existing authority (see the VC-016 status note), and the
# plan forbids closing it by adding solver authority. Run by hand until the rewrite lands:
#   godot --headless --path godot --script res://camelback_geometry_tests.gd
# Re-add it to the manifest in the same change that turns it green.

const RideGenerator := preload("res://generator.gd")
const RideProgram := preload("res://ride_program.gd")

const MAX_VERTICAL_PLANE_TILT_DEG := 3.0
const MAX_OUT_OF_PLANE_RATIO := 0.02
const MAX_HEADING_DRIFT_DEG := 5.0
const MAX_BOUNDARY_BANK_DEG := 3.0

var _errors := PackedStringArray()


func _initialize() -> void:
	_test_seed_42_camelback_is_a_reviewed_planar_element()
	_test_camelback_recipe_contains_no_semantic_micro_hold()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _test_seed_42_camelback_is_a_reviewed_planar_element() -> void:
	var route := RideGenerator.build(42)
	if not _expect(route.get("ok", false),
			"seed 42 builds before camelback geometry is inspected: %s"
			% str(route.get("errors", []))):
		return
	var record_value: Variant = route.get("element_contracts", {}).get("camelback")
	if not _expect(record_value is Dictionary,
			"accepted route publishes the camelback's whole-element record"):
		return
	var record: Dictionary = record_value
	var measurement: Dictionary = record.get("measurement", {})
	print("camelback geometry baseline: ", JSON.stringify({
		"status": record.get("status"),
		"vertical_plane_tilt_deg": measurement.get("vertical_plane_tilt_deg"),
		"out_of_plane_ratio": measurement.get("out_of_plane_ratio"),
		"heading_drift_deg": measurement.get("heading_drift_deg"),
		"entry_pitch_deg": measurement.get("entry_pitch_deg"),
		"exit_pitch_deg": measurement.get("exit_pitch_deg"),
		"entry_bank_deg": measurement.get("entry_bank_deg"),
		"exit_bank_deg": measurement.get("exit_bank_deg"),
	}))
	_expect(record.get("status") == "adopted",
		"camelback geometry is an adopted production contract, not an unreviewed diagnostic")
	var violations_value: Variant = record.get("violations")
	_expect(violations_value is PackedStringArray and violations_value.is_empty(),
		"accepted camelback carries no contract violations: %s" % str(violations_value))
	_expect(_finite_at_most(measurement, "vertical_plane_tilt_deg",
			MAX_VERTICAL_PLANE_TILT_DEG),
		"camelback vertical-plane tilt is <= %.1f degrees; got %s"
		% [MAX_VERTICAL_PLANE_TILT_DEG, str(measurement.get("vertical_plane_tilt_deg"))])
	_expect(_finite_at_most(measurement, "out_of_plane_ratio",
			MAX_OUT_OF_PLANE_RATIO),
		"camelback out-of-plane RMS ratio is <= %.3f; got %s"
		% [MAX_OUT_OF_PLANE_RATIO, str(measurement.get("out_of_plane_ratio"))])
	_expect(_finite_at_most(measurement, "heading_drift_deg",
			MAX_HEADING_DRIFT_DEG),
		"camelback heading drift is <= %.1f degrees; got %s"
		% [MAX_HEADING_DRIFT_DEG, str(measurement.get("heading_drift_deg"))])
	_expect(_finite_abs_at_most(measurement, "entry_bank_deg", MAX_BOUNDARY_BANK_DEG),
		"camelback enters near neutral bank; got %s degrees"
		% str(measurement.get("entry_bank_deg")))
	_expect(_finite_abs_at_most(measurement, "exit_bank_deg", MAX_BOUNDARY_BANK_DEG),
		"camelback exits near neutral bank; got %s degrees"
		% str(measurement.get("exit_bank_deg")))


func _test_camelback_recipe_contains_no_semantic_micro_hold() -> void:
	var spans: Array = []
	var metadata: Array = []
	var propulsion := PackedInt32Array()
	RideProgram._add_camelback(spans, metadata, propulsion)
	var ids := []
	for span_value in spans:
		if span_value is Dictionary:
			ids.append(str(span_value.get("span_id", "")))
	_expect(not ids.has("camelback/pullout-hold"),
		"camelback has no 0.01 s semantic pullout hold: %s" % str(ids))
	for span_value in spans:
		if not span_value is Dictionary:
			continue
		var span: Dictionary = span_value
		_expect(float(span.get("duration_s", 0.0)) >= 0.30,
			"camelback semantic span '%s' is at least 0.30 s; got %.6f s"
			% [str(span.get("span_id", "")), float(span.get("duration_s", 0.0))])


func _finite_at_most(measurement: Dictionary, key: String, maximum: float) -> bool:
	var value: Variant = measurement.get(key)
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) <= maximum


func _finite_abs_at_most(measurement: Dictionary, key: String, maximum: float) -> bool:
	var value: Variant = measurement.get(key)
	return (value is int or value is float) and is_finite(float(value)) \
		and absf(float(value)) <= maximum


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_errors.append(message)
	return condition
