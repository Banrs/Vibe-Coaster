extends SceneTree

const Motion := preload("res://motion.gd")
const RideProgram := preload("res://ride_program.gd")
const RETURN_TOPOLOGY_IDS := [
	"raceway/bank-in-a",
	"raceway/arc-a",
	"raceway/bank-out-a",
	"raceway/hill-a-rise",
	"raceway/hill-a-release",
	"raceway/bank-in-b",
	"raceway/arc-b",
	"raceway/bank-out-b",
	"raceway/hill-b-rise",
	"raceway/hill-b-release",
	"raceway/roll-settle",
]
const LANDMARK_BANDS := {
	"act_one_exit": {"height_m": Vector2(-40.0, 40.0), "speed_mps": Vector2(40.0, 70.0),
		"maximum_abs_tangent_y": 0.18},
	"cliff_crest": {"height_m": Vector2(150.0, 175.0), "speed_mps": Vector2(2.0, 22.0),
		"maximum_abs_tangent_y": 0.22},
	"dive_exit": {"height_m": Vector2(-20.0, 20.0), "speed_mps": Vector2(45.0, 75.0),
		"maximum_abs_tangent_y": 0.22},
	"lsm3_exit": {"height_m": Vector2(-20.0, 20.0), "speed_mps": Vector2(65.0, 75.0),
		"maximum_abs_tangent_y": 0.16},
	"camelback_apex": {"height_m": Vector2(155.0, 170.0), "speed_mps": Vector2(15.0, 45.0),
		"maximum_abs_tangent_y": 0.12},
	"return_entry": {"height_m": Vector2(-20.0, 20.0), "speed_mps": Vector2(45.0, 70.0),
		"maximum_abs_tangent_y": 0.18},
}

var _errors := PackedStringArray()


func _initialize() -> void:
	_test_station_local_program_compiles()
	_test_malformed_capture_is_structured()
	_test_impossible_capture_is_bounded_without_fallback()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _test_station_local_program_compiles() -> void:
	var compiled := _compile(_layout())
	_expect(_landmark_report_is_physical(compiled, _layout()),
		"the compiler publishes physical upstream landmarks with positive return energy")
	if not _expect(compiled.get("ok", false),
			"the explicit station-local return fixture compiles: %s" % str(compiled.get("errors", []))):
		return
	_expect(not compiled.get("spans", []).is_empty(), "the compiled program contains motion spans")
	_expect(compiled.get("capture_plan", {}).get("unique_evaluations", 41) <= 40,
		"the accepted capture stays within its public evaluation budget")
	_expect(_return_topology_ids(compiled) == RETURN_TOPOLOGY_IDS,
		"the global return has the fixed reviewed topology in order")
	_expect(_return_and_terminal_drive_is_nonpositive(compiled),
		"every global-return, capture, brake, and station drive profile is nonpositive")
	_expect(_return_plan_is_bounded(compiled),
		"the solved global-return plan publishes residual evidence within 42 evaluations")
	_expect(_capture_plan_is_bounded(compiled),
		"the solved station capture publishes evidence within 40 coarse evaluations")
	_expect(_terminal_contract_is_fixed(compiled, _layout()),
		"the compiled endpoint contract fixes the requested station frame and terminal speed")
	_expect(not _contains_fallback_or_repair_field(compiled),
		"the compiled program contains no fallback or repair field")
	var repeated := _compile(_layout())
	_expect(var_to_bytes(compiled) == var_to_bytes(repeated),
		"the same public compile request produces a byte-identical deterministic result")
	var brake: Dictionary = compiled.get("brake_plan", {})
	_expect(brake.get("positive_drive_allowed", true) == false,
		"the brake plan forbids positive drive")
	_expect(_brake_spans_have_no_positive_drive(compiled),
		"the authored capture and brake spans contain no positive drive")
	_expect(absf(float(brake.get("terminal_creep_speed_mps", -1.0)) - 1.0) <= 0.000001,
		"the brake plan declares the one metre-per-second terminal target")
	var terminal: Dictionary = compiled.get("spans", [])[-1]
	_expect(terminal.get("mode", "") == "station", "the compiled program ends in station mode")
	_expect(_structural_terminal(terminal), "the compiled program ends on structural controls")


func _test_malformed_capture_is_structured() -> void:
	var layout := _layout()
	layout["capture_seed"] = [0.0, 0.0, 0.0, 0.0]
	var compiled := _compile(layout)
	_expect_capture_failure(compiled, 0, 0, "a malformed capture seed fails before evaluation")


func _test_impossible_capture_is_bounded_without_fallback() -> void:
	var layout := _layout()
	layout["capture_half_width_m"] = -1.0
	var compiled := _compile(layout)
	_expect_capture_failure(compiled, 1, 40,
		"an impossible negative-width capture corridor fails within the evaluation budget")


func _compile(layout: Dictionary) -> Dictionary:
	return RideProgram.compile(42, {}, {}, layout, {
		"position_m": layout.station_position_m,
		"tangent": layout.station_tangent,
		"rider_up": layout.station_up,
		"speed_mps": 6.0,
		"distance_m": 0.0,
		"time_s": 0.0,
	})


func _layout() -> Dictionary:
	return {
		"station_position_m": Vector3.ZERO,
		"station_tangent": Vector3.RIGHT,
		"station_up": Vector3.UP,
	}


func _expect_capture_failure(
	compiled: Dictionary, minimum_evaluations: int, maximum_evaluations: int, message: String
) -> void:
	_expect(not compiled.get("ok", true), message)
	var failure: Dictionary = compiled.get("failure", {})
	_expect(failure.get("stage", "") == "capture", "%s at the capture stage" % message)
	_expect(not str(failure.get("reason", "")).is_empty() and not compiled.get("errors", []).is_empty(),
		"%s with both machine-readable stage data and public errors" % message)
	var count := int(failure.get("evaluation_count", -1))
	_expect(count >= minimum_evaluations and count <= maximum_evaluations,
		"%s with a bounded nonnegative evaluation count" % message)
	_expect(not compiled.has("spans") and not failure.has("route") and not failure.has("candidate"),
		"%s without exposing or accepting a fallback candidate" % message)


func _structural_terminal(span: Dictionary) -> bool:
	for key in ["normal_g", "lateral_g", "drive_g", "roll_rate_rad_s"]:
		var expected := 1.0 if key == "normal_g" else 0.0
		if Motion.profile_sample(span.get(key, {}), 1.0).distance_to(
				Vector3(expected, 0.0, 0.0)) > 0.000001:
			return false
	return true


func _brake_spans_have_no_positive_drive(compiled: Dictionary) -> bool:
	var gestures: Array = compiled.get("gesture_spans", [])
	if gestures.is_empty() or gestures[-1].get("story_slot_id", "") != "brakes-station-capture":
		return false
	var spans: Array = compiled.get("spans", [])
	for span_index in range(int(gestures[-1].first_span), int(gestures[-1].last_span) + 1):
		for u in [0.0, 0.25, 0.5, 0.75, 1.0]:
			if Motion.profile_sample(spans[span_index].drive_g, u).x > 0.000001:
				return false
	return true


func _return_topology_ids(compiled: Dictionary) -> Array:
	var ids := []
	for span in compiled.get("spans", []):
		var span_id := str(span.get("span_id", ""))
		if span_id.begins_with("raceway/"):
			ids.append(span_id)
	return ids


func _return_and_terminal_drive_is_nonpositive(compiled: Dictionary) -> bool:
	var spans: Array = compiled.get("spans", [])
	var first_return := -1
	for index in spans.size():
		if spans[index].get("span_id", "") == RETURN_TOPOLOGY_IDS[0]:
			first_return = index
			break
	if first_return < 0:
		return false
	for index in range(first_return, spans.size()):
		if not _profile_is_nonpositive(spans[index].get("drive_g", {})):
			return false
	return true


func _profile_is_nonpositive(profile: Dictionary) -> bool:
	match profile.get("kind", ""):
		"constant":
			return float(profile.get("value", INF)) <= 0.0
		"quintic":
			return maxf(float(profile.get("from", INF)), float(profile.get("to", INF))) <= 0.0
		"compact_pulse":
			return float(profile.get("amplitude", INF)) <= 0.0
	return false


func _return_plan_is_bounded(compiled: Dictionary) -> bool:
	var plan: Dictionary = compiled.get("return_plan", {})
	var evaluations := int(plan.get("unique_evaluations", -1))
	return plan.get("status", "") == "solved" \
		and plan.get("variables") is Array and not plan.variables.is_empty() \
		and plan.get("residuals") is Array and not plan.residuals.is_empty() \
		and plan.get("fine_residuals") is Array and not plan.fine_residuals.is_empty() \
		and plan.get("margins") is Dictionary and not plan.margins.is_empty() \
		and evaluations >= 1 and evaluations <= 42 \
		and plan.get("max_unique_evaluations", -1) == 42 \
		and plan.get("positive_drive_allowed", true) == false


func _capture_plan_is_bounded(compiled: Dictionary) -> bool:
	var plan: Dictionary = compiled.get("capture_plan", {})
	var evaluations := int(plan.get("unique_evaluations", -1))
	return evaluations >= 1 and evaluations <= 40 \
		and plan.get("max_unique_coarse_evaluations", -1) == 40


func _landmark_report_is_physical(compiled: Dictionary, layout: Dictionary) -> bool:
	var report: Variant = compiled.get("landmark_report")
	if not report is Dictionary:
		return false
	var station_position: Vector3 = layout.station_position_m
	var station_up: Vector3 = layout.station_up.normalized()
	for landmark_id in LANDMARK_BANDS:
		var state: Variant = report.get(landmark_id)
		if not state is Dictionary:
			return false
		var position: Variant = state.get("position_m")
		var tangent: Variant = state.get("tangent")
		var speed: Variant = state.get("speed_mps")
		if not position is Vector3 or not position.is_finite() \
				or not tangent is Vector3 or not tangent.is_finite() \
				or tangent.length_squared() < 0.99 or not _finite_number(speed):
			return false
		var band: Dictionary = LANDMARK_BANDS[landmark_id]
		var height_m: float = (position - station_position).dot(station_up)
		if not _inside(height_m, band.height_m) or not _inside(float(speed), band.speed_mps) \
				or absf(tangent.normalized().dot(station_up)) > band.maximum_abs_tangent_y:
			return false
	var return_entry: Dictionary = report.return_entry
	var reported_headroom: Variant = return_entry.get("energy_headroom_j_per_kg")
	if not _finite_number(reported_headroom) or float(reported_headroom) <= 0.0:
		return false
	var relative_height: float = (return_entry.position_m - station_position).dot(station_up)
	var expected_headroom: float = (
		0.5 * float(return_entry.speed_mps) ** 2 + Motion.G0 * relative_height - 0.5
	)
	return absf(float(reported_headroom) - expected_headroom) <= 0.001


func _inside(value: float, band: Vector2) -> bool:
	return value >= band.x and value <= band.y


func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


func _terminal_contract_is_fixed(compiled: Dictionary, layout: Dictionary) -> bool:
	var contract: Dictionary = compiled.get("terminal_contract", {})
	return contract.get("station_position_m") == layout.station_position_m \
		and contract.get("station_tangent") == layout.station_tangent \
		and contract.get("station_up") == layout.station_up \
		and absf(float(contract.get("terminal_speed_mps", -1.0)) - 1.0) <= 0.000001 \
		and _positive_finite(contract.get("position_tolerance_m")) \
		and _positive_finite(contract.get("angle_tolerance_rad")) \
		and _positive_finite(contract.get("speed_tolerance_mps"))


func _positive_finite(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value)) and float(value) > 0.0


func _contains_fallback_or_repair_field(value: Variant) -> bool:
	if value is Dictionary:
		for key in value:
			var field := str(key).to_lower()
			if field.contains("fallback") or field.contains("repair"):
				return true
			if _contains_fallback_or_repair_field(value[key]):
				return true
	elif value is Array:
		for item in value:
			if _contains_fallback_or_repair_field(item):
				return true
	return false


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_errors.append(message)
	return condition
