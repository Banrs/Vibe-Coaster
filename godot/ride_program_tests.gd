extends SceneTree

const Motion := preload("res://motion.gd")
const RideProgram := preload("res://ride_program.gd")
const RETURN_TOPOLOGY_IDS := [
	"raceway/turn-a-entry",
	"raceway/turn-a-core",
	"raceway/turn-a-exit-pullup",
	"raceway/airtime-unload",
	"raceway/airtime-recovery",
	"raceway/turn-b-entry",
	"raceway/turn-b-core",
	"raceway/turn-b-exit",
]
const CAPTURE_MARGIN_IDS := [
	"coefficient_margin",
	"corridor_cross_m",
	"corridor_forward_high_m",
	"corridor_forward_low_m",
	"corridor_height_m",
	"lateral_force_g",
	"normal_force_g",
	"remaining_along_track_m",
	"roll_rate_rad_s",
	"speed_floor_margin_mps",
	"speed_floor_mps",
]
const CAPTURE_HALF_WIDTH_M := 150.0
const CAPTURE_HALF_HEIGHT_M := 75.0
const CAPTURE_RESIDUAL_LIMITS := [0.05, 0.05, 0.00001, 0.00001, 0.00001]
const LANDMARK_BANDS := {
	"launch_exit": {"height_m": Vector2(-5.0, 5.0), "speed_mps": Vector2(75.0, 78.0),
		"maximum_abs_tangent_y": 0.05},
	"act_one_exit": {"height_m": Vector2(-40.0, 40.0), "speed_mps": Vector2(40.0, 70.0),
		"maximum_abs_tangent_y": 0.18},
	"lsm2_exit": {"height_m": Vector2(-20.0, 20.0), "speed_mps": Vector2(57.0, 64.0),
		"maximum_abs_tangent_y": 0.12},
	"cliff_crest": {"height_m": null, "speed_mps": Vector2(5.0, 22.0),
		"maximum_abs_tangent_y": 0.22},
	"dive_exit": {"height_m": Vector2(-20.0, 20.0), "speed_mps": Vector2(55.0, 70.0),
		"maximum_abs_tangent_y": 0.22},
	"lsm3_exit": {"height_m": Vector2(-20.0, 20.0), "speed_mps": Vector2(90.0, 98.0),
		"maximum_abs_tangent_y": 0.16},
	"camelback_apex": {"height_m": Vector2(240.0, 260.0), "speed_mps": Vector2(50.0, 68.0),
		"maximum_abs_tangent_y": 0.12},
	"return_entry": {"height_m": Vector2(-20.0, 20.0), "speed_mps": Vector2(78.0, 92.0),
		"maximum_abs_tangent_y": 0.18},
}

var _errors := PackedStringArray()


func _initialize() -> void:
	_test_capture_accepts_varied_station_frames()
	_test_sustained_brake_closes_without_padding()
	_test_station_local_program_compiles()
	_test_malformed_capture_is_structured()
	_test_impossible_capture_is_bounded_without_fallback()
	_test_nonfinite_capture_margin_is_rejected()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _test_sustained_brake_closes_without_padding() -> void:
	var station := Vector3(174.262812, 0.0, 0.0)
	var start := {
		"position_m": Vector3.ZERO,
		"tangent": Vector3.RIGHT,
		"rider_up": Vector3.UP,
		"speed_mps": 69.0,
		"distance_m": 0.0,
		"time_s": 0.0,
	}
	var layout := {
		"station_position_m": station,
		"station_tangent": Vector3.RIGHT,
		"station_up": Vector3.UP,
	}
	var solved: Dictionary = RideProgram._solve_brakes(
		start, layout, RideProgram._settings(0.05))
	if not _expect(solved.get("ok", false),
			"the reviewed 4.4 s final brake closes without a padding coast: %s" % str(solved)):
		return
	var spans: Array = solved.get("spans", [])
	var ids := []
	var active_duration_s := 0.0
	for span: Dictionary in spans:
		ids.append(span.get("span_id", ""))
		if str(span.get("span_id", "")).begins_with("brakes/"):
			active_duration_s += float(span.get("duration_s", 0.0))
	_expect(ids == ["brakes/engage", "brakes/hold", "brakes/release", "station/creep"],
		"the terminal program contains only the sustained brake and station creep")
	_expect(RideProgram._validate_control_seams(spans).is_empty(),
		"the sustained brake and station handoff match C2 control jets")
	_expect(absf(active_duration_s - 4.4) <= 0.000001,
		"the active final brake retains the observed 4.4 second duration")
	var route := Motion.integrate(start, spans, RideProgram._settings(0.01))
	if not _expect(route.get("ok", false),
			"the sustained brake fixture integrates through the central motion kernel"):
		return
	var handoff := Motion.sample_time(route, 4.4)
	_expect(absf(float(handoff.get("speed_mps", -1.0)) - 2.0) <= 0.0001,
		"the moving brake reaches exactly 2 m/s at its native station handoff")
	_expect(route.position_m[-1].distance_to(station) <= 0.05,
		"the authored terminal spans consume their physical station distance")
	_expect(absf(float(route.speed_mps[-1]) - 1.0) <= 0.001,
		"the station creep reaches the preset terminal speed")


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
	_expect(_compiled_return_ids(compiled) == RETURN_TOPOLOGY_IDS,
		"the compiled raceway retains the reviewed eight-span authored topology")
	_expect(_return_and_terminal_drive_is_nonpositive(compiled),
		"every global-return, capture, brake, and station drive profile is nonpositive")
	_expect(_return_is_passive_and_material(compiled, _layout()),
		"the authored raceway is at least 1.1 km and monotonically loses mechanical energy")
	_expect(not compiled.has("return_plan"),
		"the fixed raceway publishes no Newton return plan or evaluation metadata")
	_expect(_capture_plan_is_bounded(compiled),
		"the solved station capture publishes evidence within 40 coarse evaluations")
	_expect(_conditioning_matches_accepted_point(
		compiled.get("capture_plan", {}), "coefficients"),
		"capture conditioning is tied to the accepted coefficient vector")
	_expect(_capture_margin_contract_is_complete(compiled),
		"accepted capture evidence validates every required finite nonnegative margin")
	_expect(_capture_corridor_is_longitudinally_bounded(compiled, _layout()),
		"capture samples and margins stay between the reserved approach start and station")
	_expect(_terminal_contract_is_fixed(compiled, _layout()),
		"the integrated endpoint satisfies the requested station frame and terminal speed")
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


func _test_capture_accepts_varied_station_frames() -> void:
	var fixtures := [
		_capture_fixture("rotated", Vector3(120.0, 15.0, -80.0),
			Vector3(0.8, 0.0, 0.6), 62.0, 350.0, 8.0, -4.0, 2.0, 1.0, 8.0),
		_capture_fixture("rotated-mirrored-holonomy", Vector3(-260.0, 31.0, 190.0),
			Vector3(-0.6, 0.0, 0.8), 70.0, 380.0, -8.0, 4.0, -2.0, -1.0, -12.0),
	]
	var settings: Dictionary = RideProgram._settings(0.05)
	for fixture: Dictionary in fixtures:
		var solved: Dictionary = RideProgram._solve_capture(
			fixture.state, fixture.layout, settings)
		if not _expect(solved.get("ok", false),
				"capture accepts the %s fixture: %s" % [fixture.id, str(solved)]):
			continue
		_expect(int(solved.get("unique_evaluations", 41)) <= 40,
			"capture solves within 40 evaluations for %s" % fixture.id)
		_expect(maxf(absf(float(solved.coefficients[0])),
			absf(float(solved.coefficients[1]))) > 0.75,
			"the short %s capture exercises restored lateral authority" % fixture.id)
		for step_and_field in [[0.05, "residuals"], [0.025, "fine_residuals"], [0.01, ""]]:
			var measured := _integrated_capture_residuals(
				fixture, solved.coefficients, float(step_and_field[0]))
			var field := str(step_and_field[1])
			_expect(measured.get("ok", false) and _residuals_are_within(
					measured.get("residuals", []), CAPTURE_RESIDUAL_LIMITS),
				"accepted %s capture independently satisfies five axes at %.3f s: %s"
				% [fixture.id, step_and_field[0], str(measured)])
			if not field.is_empty():
				_expect(_residual_vectors_near(
					solved.get(field, []), measured.get("residuals", []), 0.0000001),
					"reported %s match independently derived %s geometry"
					% [field, fixture.id])


func _capture_fixture(
	id: String, station: Vector3, forward: Vector3, speed_mps: float, along_m: float,
	cross_m: float, height_m: float, yaw_deg: float, pitch_deg: float, roll_deg: float
) -> Dictionary:
	forward = forward.normalized()
	var up := Vector3.UP
	var right := forward.cross(up).normalized()
	var horizontal := forward.rotated(up, deg_to_rad(yaw_deg))
	var tangent := (horizontal * cos(deg_to_rad(pitch_deg))
		+ up * sin(deg_to_rad(pitch_deg))).normalized()
	var rider_up := (up - tangent * up.dot(tangent)).normalized().rotated(
		tangent, deg_to_rad(roll_deg))
	return {"id": id, "layout": {
		"station_position_m": station, "station_tangent": forward, "station_up": up,
		"reserved_corridor": {"minimum_length_m": 450.0},
		"capture_half_width_m": CAPTURE_HALF_WIDTH_M,
		"capture_half_height_m": CAPTURE_HALF_HEIGHT_M,
	}, "state": {
		"position_m": station - forward * along_m + right * cross_m + up * height_m,
		"tangent": tangent, "rider_up": rider_up, "speed_mps": speed_mps,
		"distance_m": 3100.0, "time_s": 42.0,
	}}


func _residuals_are_within(residuals: Variant, limits: Array) -> bool:
	if not residuals is Array or residuals.size() != limits.size():
		return false
	for index in limits.size():
		if not _finite_number(residuals[index]) \
				or absf(float(residuals[index])) > float(limits[index]):
			return false
	return true


func _integrated_capture_residuals(
	fixture: Dictionary, coefficients: Array, step_s: float
) -> Dictionary:
	var route: Dictionary = Motion.integrate(fixture.state,
		RideProgram._capture_spans(coefficients), RideProgram._settings(step_s))
	if not route.get("ok", false):
		return {"ok": false, "errors": route.get("errors", [])}
	var terminal := Motion.sample_time(route, float(route.time_s[-1]))
	return {"ok": true, "residuals": _independent_capture_residuals(
		terminal, fixture.layout)}


func _independent_capture_residuals(state: Dictionary, layout: Dictionary) -> Array:
	var forward: Vector3 = layout.station_tangent.normalized()
	var up: Vector3 = layout.station_up.normalized()
	var right: Vector3 = forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	var delta: Vector3 = state.position_m - layout.station_position_m
	var tangent: Vector3 = state.tangent.normalized()
	var rider_up: Vector3 = state.rider_up
	var horizontal_length: float = sqrt(
		tangent.dot(forward) ** 2 + tangent.dot(right) ** 2)
	var reference_up: Vector3 = (up - tangent * up.dot(tangent)).normalized()
	var actual_up: Vector3 = (
		rider_up - tangent * rider_up.dot(tangent)).normalized()
	return [
		delta.dot(right),
		delta.dot(up),
		atan2(tangent.dot(right), tangent.dot(forward)),
		atan2(tangent.dot(up), horizontal_length),
		atan2(actual_up.dot(tangent.cross(reference_up)), actual_up.dot(reference_up)),
	]


func _residual_vectors_near(actual: Variant, expected: Variant, tolerance: float) -> bool:
	if not actual is Array or not expected is Array or actual.size() != expected.size():
		return false
	for index in actual.size():
		if not _finite_number(actual[index]) or not _finite_number(expected[index]) \
				or absf(float(actual[index]) - float(expected[index])) > tolerance:
			return false
	return true


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
		"an impossible negative-width capture corridor fails within the evaluation budget", true)


func _test_nonfinite_capture_margin_is_rejected() -> void:
	var layout := _layout()
	layout["capture_half_width_m"] = NAN
	var compiled := _compile(layout)
	_expect_capture_failure(compiled, 1, 40,
		"a nonfinite capture margin is rejected before a plan can be accepted", true)


func _compile(layout: Dictionary) -> Dictionary:
	return RideProgram.compile(42, {}, layout, {
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
		"reserved_corridor": {"minimum_length_m": 450.0},
		"capture_half_width_m": CAPTURE_HALF_WIDTH_M,
		"capture_half_height_m": CAPTURE_HALF_HEIGHT_M,
	}


func _expect_capture_failure(
	compiled: Dictionary, minimum_evaluations: int, maximum_evaluations: int, message: String,
	require_conditioning: bool = false
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
	if require_conditioning:
		_expect(_valid_conditioning(failure.get("conditioning")),
			"%s with conditioning from the evaluated point" % message)


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


func _compiled_return_ids(compiled: Dictionary) -> Array:
	var spans: Array = compiled.get("spans", [])
	var first := -1
	for index in spans.size():
		if spans[index].get("span_id", "") == RETURN_TOPOLOGY_IDS[0]:
			first = index
			break
	if first < 0 or first + RETURN_TOPOLOGY_IDS.size() >= spans.size() \
			or spans[first + RETURN_TOPOLOGY_IDS.size()].get("span_id", "") != "capture/early":
		return []
	var result := []
	for offset in RETURN_TOPOLOGY_IDS.size():
		var span: Dictionary = spans[first + offset]
		result.append(span.get("span_id", ""))
	return result


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


func _return_is_passive_and_material(compiled: Dictionary, layout: Dictionary) -> bool:
	var spans: Array = compiled.get("spans", [])
	var first := -1
	for index in spans.size():
		if spans[index].get("span_id", "") == RETURN_TOPOLOGY_IDS[0]:
			first = index
			break
	if first < 0:
		return false
	var last := first + RETURN_TOPOLOGY_IDS.size() - 1
	var trajectory := _integrated_trajectory(compiled, layout)
	if not trajectory.get("ok", false):
		return false
	var bounds := _owned_span_bounds(trajectory.span_index, first, last)
	if bounds.x < 0 or bounds.y <= bounds.x \
			or float(trajectory.distance_m[bounds.y] - trajectory.distance_m[bounds.x]) < 1100.0:
		return false
	var up: Vector3 = layout.station_up.normalized()
	var previous: float = 0.5 * float(trajectory.speed_mps[bounds.x]) ** 2 + Motion.G0 * (
		trajectory.position_m[bounds.x] - layout.station_position_m).dot(up)
	for sample_index in range(bounds.x + 1, bounds.y + 1):
		var energy: float = 0.5 * float(trajectory.speed_mps[sample_index]) ** 2 + Motion.G0 * (
			trajectory.position_m[sample_index] - layout.station_position_m).dot(up)
		if energy - previous > 0.01:
			return false
		previous = energy
	return true


func _owned_span_bounds(
	owners: PackedInt32Array, first_span: int, last_span: int
) -> Vector2i:
	var result := Vector2i(-1, -1)
	for sample_index in owners.size():
		var owner := int(owners[sample_index])
		if owner >= first_span and owner <= last_span:
			if result.x < 0:
				result.x = sample_index
			result.y = sample_index
		elif result.x >= 0 and owner > last_span:
			break
	return result


func _linear_held_at_or_below(
	times: PackedFloat64Array, values: PackedFloat64Array, bounds: Vector2i, threshold: float
) -> float:
	var result := 0.0
	for index in range(bounds.x + 1, bounds.y + 1):
		var before: float = values[index - 1]
		var after: float = values[index]
		var duration: float = times[index] - times[index - 1]
		if before <= threshold and after <= threshold:
			result += duration
		elif (before <= threshold) != (after <= threshold):
			var crossing := clampf((threshold - before) / (after - before), 0.0, 1.0)
			result += duration * (crossing if before <= threshold else 1.0 - crossing)
	return result


func _capture_plan_is_bounded(compiled: Dictionary) -> bool:
	var plan: Dictionary = compiled.get("capture_plan", {})
	var evaluations := int(plan.get("unique_evaluations", -1))
	return evaluations >= 1 and evaluations <= 40 \
		and plan.get("max_unique_coarse_evaluations", -1) == 40 \
		and _plan_evidence_is_within_tolerance(plan)


func _plan_evidence_is_within_tolerance(plan: Dictionary) -> bool:
	var ids: Variant = plan.get("residual_ids")
	var tolerances: Variant = plan.get("residual_tolerances")
	var margins: Variant = plan.get("margins")
	if not ids is Array or ids.is_empty() or not tolerances is Array \
			or tolerances.size() != ids.size() or not margins is Dictionary \
			or margins.is_empty():
		return false
	for tolerance in tolerances:
		if not _positive_finite(tolerance):
			return false
	for field in ["residuals", "fine_residuals", "production_residuals"]:
		var residuals: Variant = plan.get(field)
		if not residuals is Array or residuals.size() != ids.size():
			return false
		for index in residuals.size():
			if not _finite_number(residuals[index]) \
					or absf(float(residuals[index])) > float(tolerances[index]):
				return false
	for margin in margins.values():
		if not _finite_number(margin) or float(margin) < 0.0:
			return false
	return true


func _conditioning_matches_accepted_point(plan: Dictionary, vector_field: String) -> bool:
	var vector: Variant = plan.get(vector_field)
	var conditioning: Variant = plan.get("conditioning")
	return vector is Array and conditioning is Dictionary \
		and conditioning.get("ok", false) and _valid_conditioning(conditioning) \
		and conditioning.get("evaluated_vector") == vector


func _valid_conditioning(value: Variant) -> bool:
	return value is Dictionary \
		and _finite_number(value.get("minimum_pivot")) \
		and float(value.minimum_pivot) >= 0.0 \
		and _finite_number(value.get("pivot_ratio")) \
		and float(value.pivot_ratio) >= 0.0


func _capture_margin_contract_is_complete(compiled: Dictionary) -> bool:
	var margins: Variant = compiled.get("capture_plan", {}).get("margins")
	if not margins is Dictionary:
		return false
	var actual_ids: Array = margins.keys()
	actual_ids.sort()
	var expected_ids := CAPTURE_MARGIN_IDS.duplicate()
	expected_ids.sort()
	if actual_ids != expected_ids:
		return false
	for margin in margins.values():
		if not _finite_number(margin) or float(margin) < 0.0:
			return false
	return true


func _capture_corridor_is_longitudinally_bounded(
	compiled: Dictionary, layout: Dictionary
) -> bool:
	var trajectory := _integrated_trajectory(compiled, layout)
	if not trajectory.get("ok", false):
		return false
	var capture_span_indices := []
	for span_index in compiled.get("spans", []).size():
		if str(compiled.spans[span_index].get("span_id", "")).begins_with("capture/"):
			capture_span_indices.append(span_index)
	if capture_span_indices.is_empty():
		return false
	var forward: Vector3 = layout.station_tangent.normalized()
	var approach_start: Vector3 = layout.station_position_m - forward * float(
		layout.reserved_corridor.minimum_length_m)
	var sample_count := 0
	for sample_index in trajectory.position_m.size():
		if not capture_span_indices.has(int(trajectory.span_index[sample_index])):
			continue
		sample_count += 1
		var position: Vector3 = trajectory.position_m[sample_index]
		if (position - approach_start).dot(forward) < 0.0 \
				or (layout.station_position_m - position).dot(forward) < 0.0:
			return false
	var margins: Dictionary = compiled.get("capture_plan", {}).get("margins", {})
	return sample_count > 0 \
		and _finite_number(margins.get("corridor_forward_low_m")) \
		and float(margins.corridor_forward_low_m) >= 0.0 \
		and _finite_number(margins.get("corridor_forward_high_m")) \
		and float(margins.corridor_forward_high_m) >= 0.0


func _landmark_report_is_physical(compiled: Dictionary, layout: Dictionary) -> bool:
	var report: Variant = compiled.get("landmark_report")
	var trajectory := _integrated_trajectory(compiled, layout)
	if not report is Dictionary or not trajectory.get("ok", false):
		return false
	var station_position: Vector3 = layout.station_position_m
	var station_up: Vector3 = layout.station_up.normalized()
	for landmark_id in LANDMARK_BANDS:
		var state: Variant = report.get(landmark_id)
		if not state is Dictionary:
			return false
		var time_s: Variant = state.get("time_s")
		var position: Variant = state.get("position_m")
		var tangent: Variant = state.get("tangent")
		var rider_up: Variant = state.get("rider_up")
		var speed: Variant = state.get("speed_mps")
		if not _finite_number(time_s) or not position is Vector3 or not position.is_finite() \
				or not tangent is Vector3 or not tangent.is_finite() \
				or not rider_up is Vector3 or not rider_up.is_finite() \
				or tangent.length_squared() < 0.99 or rider_up.length_squared() < 0.99 \
				or not _finite_number(speed):
			return false
		var sampled := Motion.sample_time(trajectory, float(time_s))
		if sampled.is_empty() or absf(float(sampled.time_s) - float(time_s)) > 0.000000001 \
				or position.distance_to(sampled.position_m) > 0.001 \
				or tangent.distance_to(sampled.tangent) > 0.00001 \
				or rider_up.distance_to(sampled.rider_up) > 0.00001 \
				or absf(float(speed) - float(sampled.speed_mps)) > 0.001:
			return false
		var band: Dictionary = LANDMARK_BANDS[landmark_id]
		var height_m: float = (position - station_position).dot(station_up)
		if (band.height_m != null and not _inside(height_m, band.height_m)) \
				or not _inside(float(speed), band.speed_mps) \
				or absf(tangent.normalized().dot(station_up)) > band.maximum_abs_tangent_y:
			return false
	var return_entry: Dictionary = report.return_entry
	var reported_headroom: Variant = return_entry.get("energy_headroom_j_per_kg")
	if not _finite_number(reported_headroom) or float(reported_headroom) <= 0.0:
		return false
	if not _shape_evidence_matches_trajectory(compiled, report, trajectory):
		return false
	var relative_height: float = (return_entry.position_m - station_position).dot(station_up)
	var expected_headroom: float = (
		0.5 * float(return_entry.speed_mps) ** 2 + Motion.G0 * relative_height - 0.5
	)
	return absf(float(reported_headroom) - expected_headroom) <= 0.001


func _shape_evidence_matches_trajectory(
	compiled: Dictionary, report: Dictionary, trajectory: Dictionary
) -> bool:
	var shape: Variant = report.get("shape_evidence")
	var climb := _compiled_gesture(compiled, "escarpment-climb")
	var cliff := _compiled_gesture(compiled, "clifftop-suspense")
	var rim := _compiled_role(cliff, "outward-rim")
	var slow_crest := _compiled_role(cliff, "slow-crest")
	if not shape is Dictionary or climb.is_empty() or cliff.is_empty() \
			or rim.is_empty() or slow_crest.is_empty():
		return false
	var evidence: Dictionary = shape
	var climb_entry := _trajectory_span_bounds(trajectory,
		int(climb.first_span), int(climb.first_span)).x
	var crest_bounds := _trajectory_span_bounds(trajectory,
		int(climb.first_span), int(cliff.last_span))
	var slow_bounds := _trajectory_span_bounds(trajectory,
		int(slow_crest.first_span), int(slow_crest.last_span))
	var rim_bounds := _trajectory_span_bounds(trajectory,
		int(rim.first_span), int(rim.last_span))
	var crest_apex := _maximum_trajectory_height(trajectory, crest_bounds)
	var held_s := _held_at_or_below(
		trajectory.time_s, trajectory.speed_mps, slow_bounds, 22.0)
	var cliff_prominence := float(trajectory.position_m[crest_apex].y) \
		- float(trajectory.position_m[climb_entry].y)
	var rim_heading := _trajectory_heading_change(trajectory.tangent, rim_bounds)
	var rim_cross_track := _trajectory_cross_track(
		trajectory.position_m, trajectory.tangent, rim_bounds)
	var rim_maximum_bank := _trajectory_maximum_bank(
		trajectory.tangent, trajectory.rider_up, rim_bounds)
	var negative_rim_bank := PackedFloat64Array()
	negative_rim_bank.resize(trajectory.time_s.size())
	var rim_maximum_lateral_g := 0.0
	for index in range(rim_bounds.x, rim_bounds.y + 1):
		negative_rim_bank[index] = -_trajectory_bank(
			trajectory.tangent[index], trajectory.rider_up[index])
		rim_maximum_lateral_g = maxf(
			rim_maximum_lateral_g, absf(float(trajectory.lateral_g[index])))
	var rim_held_bank_s := _linear_held_at_or_below(
		trajectory.time_s, negative_rim_bank, rim_bounds, -deg_to_rad(40.0))
	var rim_duration_s: float = trajectory.time_s[rim_bounds.y] \
		- trajectory.time_s[rim_bounds.x]
	var rim_distance_m: float = trajectory.distance_m[rim_bounds.y] \
		- trajectory.distance_m[rim_bounds.x]
	var rim_exit: int = rim_bounds.y
	var rim_exit_bank := _trajectory_bank(
		trajectory.tangent[rim_exit], trajectory.rider_up[rim_exit])
	var rim_exit_pitch := asin(clampf(trajectory.tangent[rim_exit].y, -1.0, 1.0))
	var rim_exit_up_dot: float = trajectory.rider_up[rim_exit].dot(Vector3.UP)
	return _reported_near(evidence, "crest_held_at_or_below_22_mps_s", held_s, 0.051) \
		and held_s >= 2.7 \
		and _reported_near(evidence, "cliff_prominence_m", cliff_prominence, 0.001) \
		and cliff_prominence >= 150.0 and cliff_prominence <= 175.0 \
		and _reported_near(evidence, "rim_heading_change_rad", rim_heading, 0.00001) \
		and _reported_near(evidence, "rim_cross_track_m", rim_cross_track, 0.001) \
		and _reported_near(evidence, "rim_maximum_bank_rad", rim_maximum_bank, 0.00001) \
		and rim_heading >= deg_to_rad(110.0) and rim_heading <= deg_to_rad(170.0) \
		and rim_held_bank_s >= 1.0 and rim_maximum_lateral_g <= 0.050001 \
		and rim_duration_s >= 3.5 and rim_duration_s <= 6.0 \
		and rim_distance_m >= 40.0 and rim_distance_m <= 160.0 \
		and _reported_near(evidence, "rim_exit_bank_rad", rim_exit_bank, 0.00001) \
		and _reported_near(evidence, "rim_exit_pitch_rad", rim_exit_pitch, 0.00001) \
		and _reported_near(evidence, "rim_exit_up_dot", rim_exit_up_dot, 0.00001) \
		and rim_exit_bank <= deg_to_rad(2.0) \
		and absf(rim_exit_pitch) <= deg_to_rad(0.5) and rim_exit_up_dot >= 0.99


func _compiled_gesture(compiled: Dictionary, story_id: String) -> Dictionary:
	for gesture in compiled.get("gesture_spans", []):
		if gesture.get("story_slot_id", "") == story_id:
			return gesture
	return {}


func _compiled_role(gesture: Dictionary, role_id: String) -> Dictionary:
	for role in gesture.get("role_windows", []):
		if role.get("id", "") == role_id:
			return role
	return {}


func _trajectory_span_bounds(
	trajectory: Dictionary, first_span: int, last_span: int
) -> Vector2i:
	var owners: PackedInt32Array = trajectory.span_index
	var first := 0
	while first < owners.size() - 1 and owners[first] < first_span:
		first += 1
	var last := first
	while last < owners.size() - 1 and owners[last] <= last_span:
		last += 1
	return Vector2i(first, last)


func _maximum_trajectory_height(trajectory: Dictionary, bounds: Vector2i) -> int:
	var result := bounds.x
	for index in range(bounds.x + 1, bounds.y + 1):
		if trajectory.position_m[index].y > trajectory.position_m[result].y:
			result = index
	return result


func _held_at_or_below(
	times: PackedFloat64Array, values: PackedFloat64Array, bounds: Vector2i, threshold: float
) -> float:
	var result := 0.0
	for index in range(bounds.x + 1, bounds.y + 1):
		if 0.5 * (values[index - 1] + values[index]) <= threshold:
			result += times[index] - times[index - 1]
	return result


func _trajectory_heading_change(tangents: PackedVector3Array, bounds: Vector2i) -> float:
	var first := Vector2(tangents[bounds.x].x, tangents[bounds.x].z).normalized()
	var last := Vector2(tangents[bounds.y].x, tangents[bounds.y].z).normalized()
	return acos(clampf(first.dot(last), -1.0, 1.0))


func _trajectory_cross_track(
	positions: PackedVector3Array, tangents: PackedVector3Array, bounds: Vector2i
) -> float:
	var forward := Vector2(tangents[bounds.x].x, tangents[bounds.x].z).normalized()
	var right := Vector2(-forward.y, forward.x)
	var delta := Vector2(positions[bounds.y].x - positions[bounds.x].x,
		positions[bounds.y].z - positions[bounds.x].z)
	return absf(delta.dot(right))


func _trajectory_maximum_bank(
	tangents: PackedVector3Array, rider_ups: PackedVector3Array, bounds: Vector2i
) -> float:
	var result := 0.0
	for index in range(bounds.x, bounds.y + 1):
		result = maxf(result, _trajectory_bank(tangents[index], rider_ups[index]))
	return result


func _trajectory_bank(tangent: Vector3, rider_up: Vector3) -> float:
	var level_up := Vector3.UP - tangent * tangent.y
	if level_up.length_squared() <= 0.000001:
		return INF
	return acos(clampf(rider_up.dot(level_up.normalized()), -1.0, 1.0))


func _reported_near(
	report: Dictionary, key: String, expected: float, tolerance: float
) -> bool:
	var actual: Variant = report.get(key)
	return _finite_number(actual) and absf(float(actual) - expected) <= tolerance


func _inside(value: float, band: Vector2) -> bool:
	return value >= band.x and value <= band.y


func _finite_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))


func _terminal_contract_is_fixed(compiled: Dictionary, layout: Dictionary) -> bool:
	var contract: Dictionary = compiled.get("terminal_contract", {})
	if not (contract.get("station_position_m") is Vector3) \
			or not (contract.get("station_tangent") is Vector3) \
			or not (contract.get("station_up") is Vector3) \
			or contract.get("station_position_m") != layout.station_position_m \
			or contract.get("station_tangent") != layout.station_tangent \
			or contract.get("station_up") != layout.station_up \
			or absf(float(contract.get("terminal_speed_mps", -1.0)) - 1.0) > 0.000001 \
			or not _positive_finite(contract.get("position_tolerance_m")) \
			or not _positive_finite(contract.get("angle_tolerance_rad")) \
			or not _positive_finite(contract.get("speed_tolerance_mps")):
		return false
	var trajectory := _integrated_trajectory(compiled, layout)
	if not trajectory.get("ok", false):
		return false
	var actual := Motion.sample_time(trajectory, float(trajectory.time_s[-1]))
	return actual.position_m.distance_to(contract.station_position_m) \
			<= float(contract.position_tolerance_m) \
		and _angle_between(actual.tangent, contract.station_tangent) \
			<= float(contract.angle_tolerance_rad) \
		and _angle_between(actual.rider_up, contract.station_up) \
			<= float(contract.angle_tolerance_rad) \
		and absf(float(actual.speed_mps) - float(contract.terminal_speed_mps)) \
			<= float(contract.speed_tolerance_mps)


func _integrated_trajectory(compiled: Dictionary, layout: Dictionary) -> Dictionary:
	var spans: Variant = compiled.get("spans")
	var settings: Variant = compiled.get("settings")
	if not spans is Array or spans.is_empty() or not settings is Dictionary:
		return {}
	return Motion.integrate({
		"position_m": layout.station_position_m,
		"tangent": layout.station_tangent,
		"rider_up": layout.station_up,
		"speed_mps": 6.0,
		"distance_m": 0.0,
		"time_s": 0.0,
	}, spans, settings)


func _angle_between(a: Vector3, b: Vector3) -> float:
	if not a.is_finite() or not b.is_finite() \
			or a.length_squared() <= 0.0 or b.length_squared() <= 0.0:
		return INF
	return acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0))


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
