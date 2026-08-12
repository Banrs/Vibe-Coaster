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
const LANDMARK_BANDS := {
	"launch_exit": {"height_m": Vector2(-5.0, 5.0), "speed_mps": Vector2(85.0, 98.0),
		"maximum_abs_tangent_y": 0.05},
	"act_one_exit": {"height_m": Vector2(-40.0, 40.0), "speed_mps": Vector2(40.0, 70.0),
		"maximum_abs_tangent_y": 0.18},
	"lsm2_exit": {"height_m": Vector2(-20.0, 20.0), "speed_mps": Vector2(57.0, 64.0),
		"maximum_abs_tangent_y": 0.12},
	"cliff_crest": {"height_m": Vector2(150.0, 175.0), "speed_mps": Vector2(5.0, 22.0),
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
	_test_station_local_program_compiles()
	_test_malformed_capture_is_structured()
	_test_impossible_capture_is_bounded_without_fallback()
	_test_nonfinite_capture_margin_is_rejected()
	_test_impossible_long_return_is_bounded_without_fallback()
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
	_expect(_conditioning_matches_accepted_point(compiled.get("return_plan", {}), "variables"),
		"return conditioning is tied to the accepted variable vector")
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


func _test_impossible_long_return_is_bounded_without_fallback() -> void:
	var layout := _layout()
	layout.reserved_corridor.minimum_length_m = 10000000.0
	var compiled := _compile(layout)
	_expect(not compiled.get("ok", true), "an impossible long return is rejected")
	var failure: Dictionary = compiled.get("failure", {})
	_expect(failure.get("stage", "") == "return",
		"an impossible long return fails at the structured return stage")
	var evaluations := int(failure.get("evaluation_count", -1))
	_expect(evaluations >= 1 and evaluations <= 42,
		"an impossible long return reports all attempted evaluations within budget")
	_expect(not compiled.has("spans") and not failure.has("route")
		and not failure.has("candidate") and not _contains_fallback_or_repair_field(compiled),
		"an impossible long return exposes no candidate, fallback, or repair")


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
		"reserved_corridor": {"minimum_length_m": 1686.3294193226},
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
		and _plan_evidence_is_within_tolerance(plan) \
		and evaluations >= 1 and evaluations <= 42 \
		and plan.get("max_unique_evaluations", -1) == 42 \
		and plan.get("positive_drive_allowed", true) == false


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
	for field in ["residuals", "fine_residuals"]:
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
		if not _inside(height_m, band.height_m) or not _inside(float(speed), band.speed_mps) \
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
		and rim_heading >= deg_to_rad(15.0) and rim_cross_track >= 3.0 \
		and rim_maximum_bank >= deg_to_rad(20.0) \
		and _reported_near(evidence, "rim_exit_bank_rad", rim_exit_bank, 0.00001) \
		and _reported_near(evidence, "rim_exit_pitch_rad", rim_exit_pitch, 0.00001) \
		and _reported_near(evidence, "rim_exit_up_dot", rim_exit_up_dot, 0.00001) \
		and rim_exit_bank <= deg_to_rad(2.0) \
		and absf(rim_exit_pitch) <= deg_to_rad(3.0) and rim_exit_up_dot >= 0.99


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
