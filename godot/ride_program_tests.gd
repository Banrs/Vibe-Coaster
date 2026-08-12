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
const RETURN_CAPTURE_SPEED_MPS := Vector2(48.0, 82.0)
const CAPTURE_HALF_WIDTH_M := 150.0
const CAPTURE_HALF_HEIGHT_M := 75.0
const CAPTURE_LATERAL_LIMIT_G := 0.55
const CAPTURE_NORMAL_DELTA_LIMIT_G := 0.45
const CAPTURE_ROLL_REACH_RAD := 1.2
const CAPTURE_PULSE_AREA_S := 2.0 * 3.5 * (100.0 / 231.0)
const CAPTURE_RESIDUAL_LIMITS := [0.05, 0.05, 0.00001, 0.00001, 0.00001]
const LANDMARK_BANDS := {
	"launch_exit": {"height_m": Vector2(-5.0, 5.0), "speed_mps": Vector2(75.0, 78.0),
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
	var return_indices := _return_span_indices(compiled)
	_expect(_return_topology_is_contiguous(compiled, return_indices),
		"the exact 11-span raceway is consecutive and immediately precedes capture")
	_expect(_return_and_terminal_drive_is_nonpositive(compiled),
		"every global-return, capture, brake, and station drive profile is nonpositive")
	var return_evidence := _return_evidence(compiled, _layout(), return_indices)
	_expect(_return_energy_is_monotonic(return_evidence),
		"the raceway monotonically loses specific energy: %s" % str(return_evidence))
	_expect(_return_has_two_material_turns(return_evidence),
		"the raceway contains two coordinated material turns: %s" % str(return_evidence))
	_expect(_return_has_two_material_hills(return_evidence),
		"the raceway contains two material airtime hills: %s" % str(return_evidence))
	_expect(_return_extent_is_material(return_evidence),
		"the raceway remains a fast 1.1-3.0 km return without a dominant turn: %s"
		% str(return_evidence))
	_expect(_inside(float(return_evidence.get("capture_speed_mps", -INF)),
		RETURN_CAPTURE_SPEED_MPS),
		"the raceway enters capture at 48-82 m/s: %s" % str(return_evidence))
	_expect(_capture_entry_is_inside_basin(return_evidence),
		"the raceway enters inside the explicit capture basin: %s" % str(return_evidence))
	_expect(_capture_entry_frame_is_reachable(return_evidence),
		"the raceway entrance frame is within capture authority: %s" % str(return_evidence))
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
			Vector3(0.8, 0.0, 0.6), 62.0, 650.0, 8.0, -4.0, 2.0, 1.0, 8.0),
		_capture_fixture("rotated-mirrored-holonomy", Vector3(-260.0, 31.0, 190.0),
			Vector3(-0.6, 0.0, 0.8), 70.0, 700.0, -8.0, 4.0, -2.0, -1.0, -12.0),
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
		"reserved_corridor": {"minimum_length_m": 1686.3294193226},
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


func _return_span_indices(compiled: Dictionary) -> Dictionary:
	var result := {}
	for index in compiled.get("spans", []).size():
		var id := str(compiled.spans[index].get("span_id", ""))
		if not id.begins_with("raceway/"):
			continue
		if not RETURN_TOPOLOGY_IDS.has(id) or result.has(id):
			return {}
		result[id] = index
	return result if result.size() == RETURN_TOPOLOGY_IDS.size() else {}


func _return_topology_is_contiguous(compiled: Dictionary, indices: Dictionary) -> bool:
	if indices.size() != RETURN_TOPOLOGY_IDS.size():
		return false
	var first := int(indices.get(RETURN_TOPOLOGY_IDS[0], -1))
	for offset in RETURN_TOPOLOGY_IDS.size():
		if int(indices.get(RETURN_TOPOLOGY_IDS[offset], -1)) != first + offset:
			return false
	var spans: Array = compiled.get("spans", [])
	return first >= 0 and first + RETURN_TOPOLOGY_IDS.size() < spans.size() \
		and spans[first + RETURN_TOPOLOGY_IDS.size()].get("span_id", "") == "capture/early"


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


func _return_evidence(
	compiled: Dictionary, layout: Dictionary, indices: Dictionary
) -> Dictionary:
	var trajectory := _integrated_trajectory(compiled, layout)
	if not trajectory.get("ok", false) or indices.size() != RETURN_TOPOLOGY_IDS.size():
		return {}
	var first_return := int(indices["raceway/bank-in-a"])
	var first_capture := int(indices["raceway/roll-settle"]) + 1
	var start_sample := _owned_span_bounds(
		trajectory.span_index, first_return, first_return).x
	var capture_sample := _owned_span_bounds(
		trajectory.span_index, first_capture, first_capture).x
	if start_sample < 0 or capture_sample <= start_sample:
		return {}
	var up: Vector3 = layout.station_up.normalized()
	var forward: Vector3 = layout.station_tangent.normalized()
	var right: Vector3 = forward.cross(up).normalized()
	var position: Vector3 = trajectory.position_m[capture_sample]
	var tangent: Vector3 = trajectory.tangent[capture_sample]
	var rider_up: Vector3 = trajectory.rider_up[capture_sample]
	var delta: Vector3 = position - layout.station_position_m
	var reference_up: Vector3 = up - tangent * up.dot(tangent)
	var actual_up: Vector3 = rider_up - tangent * rider_up.dot(tangent)
	var roll := INF
	if reference_up.length_squared() > 0.000001 and actual_up.length_squared() > 0.000001:
		reference_up = reference_up.normalized()
		actual_up = actual_up.normalized()
		roll = atan2(tangent.dot(reference_up.cross(actual_up)), reference_up.dot(actual_up))
	var first_energy: float = _specific_energy(trajectory, start_sample, layout)
	var previous_energy: float = first_energy
	var maximum_energy_rise := 0.0
	var minimum_speed: float = trajectory.speed_mps[start_sample]
	for sample_index in range(start_sample + 1, capture_sample + 1):
		var energy: float = _specific_energy(trajectory, sample_index, layout)
		maximum_energy_rise = maxf(maximum_energy_rise, energy - previous_energy)
		previous_energy = energy
		minimum_speed = minf(minimum_speed, float(trajectory.speed_mps[sample_index]))
	var speed: float = trajectory.speed_mps[capture_sample]
	return {
		"maximum_energy_rise_j_per_kg": maximum_energy_rise,
		"energy_loss_j_per_kg": first_energy - previous_energy,
		"length_m": float(trajectory.distance_m[capture_sample])
			- float(trajectory.distance_m[start_sample]),
		"duration_s": float(trajectory.time_s[capture_sample])
			- float(trajectory.time_s[start_sample]),
		"minimum_speed_mps": minimum_speed,
		"turns": [
			_return_turn_evidence(trajectory, int(indices["raceway/bank-in-a"]),
				int(indices["raceway/bank-out-a"]), up),
			_return_turn_evidence(trajectory, int(indices["raceway/bank-in-b"]),
				int(indices["raceway/bank-out-b"]), up),
		],
		"hills": [
			_return_hill_evidence(trajectory, int(indices["raceway/hill-a-rise"]),
				int(indices["raceway/hill-a-release"]), up),
			_return_hill_evidence(trajectory, int(indices["raceway/hill-b-rise"]),
				int(indices["raceway/hill-b-release"]), up),
		],
		"capture_speed_mps": speed,
		"capture_entry_margins_m": {
			"cross": float(layout.capture_half_width_m) - absf(delta.dot(right)),
			"height": float(layout.capture_half_height_m) - absf(delta.dot(up)),
			"forward_low": float(layout.reserved_corridor.minimum_length_m)
				+ delta.dot(forward),
			"forward_high": -delta.dot(forward),
		},
		"capture_yaw_rad": atan2(tangent.dot(right), tangent.dot(forward)),
		"capture_pitch_rad": asin(clampf(tangent.dot(up), -1.0, 1.0)),
		"capture_roll_rad": roll,
		"capture_yaw_reach_rad": Motion.G0 * CAPTURE_LATERAL_LIMIT_G
			* CAPTURE_PULSE_AREA_S / speed,
		"capture_pitch_reach_rad": Motion.G0 * CAPTURE_NORMAL_DELTA_LIMIT_G
			* CAPTURE_PULSE_AREA_S / speed,
	}


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


func _specific_energy(trajectory: Dictionary, sample_index: int, layout: Dictionary) -> float:
	return 0.5 * float(trajectory.speed_mps[sample_index]) ** 2 + Motion.G0 * (
		trajectory.position_m[sample_index] - layout.station_position_m
	).dot(layout.station_up.normalized())


func _return_turn_evidence(
	trajectory: Dictionary, first_span: int, last_span: int, up: Vector3
) -> Dictionary:
	var bounds := _owned_span_bounds(trajectory.span_index, first_span, last_span)
	if bounds.x < 0 or bounds.y <= bounds.x:
		return {}
	var maximum_lateral := 0.0
	var maximum_bank := 0.0
	var signed_heading := 0.0
	var previous: Vector3 = trajectory.tangent[bounds.x]
	previous -= up * previous.dot(up)
	if previous.length_squared() <= 0.000001:
		return {}
	previous = previous.normalized()
	for sample_index in range(bounds.x, bounds.y + 1):
		var horizontal: Vector3 = trajectory.tangent[sample_index]
		horizontal -= up * horizontal.dot(up)
		if horizontal.length_squared() <= 0.000001:
			return {}
		horizontal = horizontal.normalized()
		if sample_index > bounds.x:
			signed_heading += atan2(up.dot(previous.cross(horizontal)), previous.dot(horizontal))
		previous = horizontal
		maximum_lateral = maxf(maximum_lateral,
			absf(float(trajectory.lateral_g[sample_index])))
		maximum_bank = maxf(maximum_bank, _trajectory_bank(
			trajectory.tangent[sample_index], trajectory.rider_up[sample_index]))
	return {
		"signed_heading_change_rad": signed_heading,
		"maximum_bank_rad": maximum_bank,
		"maximum_lateral_g": maximum_lateral,
		"duration_s": float(trajectory.time_s[bounds.y])
			- float(trajectory.time_s[bounds.x]),
		"distance_m": float(trajectory.distance_m[bounds.y])
			- float(trajectory.distance_m[bounds.x]),
	}


func _return_hill_evidence(
	trajectory: Dictionary, first_span: int, last_span: int, up: Vector3
) -> Dictionary:
	var bounds := _owned_span_bounds(trajectory.span_index, first_span, last_span)
	if bounds.x < 0 or bounds.y - bounds.x < 2:
		return {}
	var apex := bounds.x
	for sample_index in range(bounds.x, bounds.y + 1):
		if trajectory.position_m[sample_index].dot(up) \
				> trajectory.position_m[apex].dot(up):
			apex = sample_index
	var maximum_ascent := -INF
	for sample_index in range(bounds.x, apex + 1):
		maximum_ascent = maxf(maximum_ascent, trajectory.tangent[sample_index].dot(up))
	var minimum_descent := INF
	for sample_index in range(apex, bounds.y + 1):
		minimum_descent = minf(minimum_descent, trajectory.tangent[sample_index].dot(up))
	var apex_height: float = trajectory.position_m[apex].dot(up)
	return {
		"apex_is_interior": apex > bounds.x and apex < bounds.y,
		"entry_prominence_m": apex_height - trajectory.position_m[bounds.x].dot(up),
		"exit_prominence_m": apex_height - trajectory.position_m[bounds.y].dot(up),
		"maximum_ascent_slope": maximum_ascent,
		"minimum_descent_slope": minimum_descent,
		"low_normal_held_s": _linear_held_at_or_below(trajectory.time_s,
			trajectory.normal_g, bounds, 0.25),
	}


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


func _return_energy_is_monotonic(evidence: Dictionary) -> bool:
	return _finite_number(evidence.get("maximum_energy_rise_j_per_kg")) \
		and float(evidence.maximum_energy_rise_j_per_kg) <= 0.01 \
		and _finite_number(evidence.get("energy_loss_j_per_kg")) \
		and float(evidence.energy_loss_j_per_kg) >= 100.0


func _return_has_two_material_turns(evidence: Dictionary) -> bool:
	var turns: Variant = evidence.get("turns")
	if not turns is Array or turns.size() != 2:
		return false
	for turn in turns:
		if not turn is Dictionary \
				or not _finite_number(turn.get("signed_heading_change_rad")) \
				or absf(float(turn.signed_heading_change_rad)) < deg_to_rad(10.0) \
				or absf(float(turn.signed_heading_change_rad)) > deg_to_rad(225.0) \
				or not _finite_number(turn.get("maximum_bank_rad")) \
				or float(turn.maximum_bank_rad) < deg_to_rad(15.0) \
				or not _finite_number(turn.get("maximum_lateral_g")) \
				or float(turn.get("maximum_lateral_g", INF)) > 0.05:
			return false
	return true


func _return_has_two_material_hills(evidence: Dictionary) -> bool:
	var hills: Variant = evidence.get("hills")
	if not hills is Array or hills.size() != 2:
		return false
	for hill in hills:
		if not hill is Dictionary \
				or not hill.get("apex_is_interior", false) \
				or float(hill.get("entry_prominence_m", 0.0)) < 5.0 \
				or float(hill.get("exit_prominence_m", 0.0)) < 5.0 \
				or float(hill.get("maximum_ascent_slope", 0.0)) <= 0.05 \
				or float(hill.get("minimum_descent_slope", 0.0)) >= -0.05 \
				or float(hill.get("low_normal_held_s", 0.0)) < 0.25:
			return false
	return true


func _return_extent_is_material(evidence: Dictionary) -> bool:
	var length: Variant = evidence.get("length_m")
	var duration: Variant = evidence.get("duration_s")
	var minimum_speed: Variant = evidence.get("minimum_speed_mps")
	var turns: Variant = evidence.get("turns")
	if not _finite_number(length) or float(length) < 1100.0 or float(length) > 3000.0 \
			or not _positive_finite(duration) or not _finite_number(minimum_speed) \
			or float(minimum_speed) < 45.0 or not turns is Array or turns.size() != 2:
		return false
	for turn in turns:
		if not turn is Dictionary or not _finite_number(turn.get("duration_s")) \
				or not _finite_number(turn.get("distance_m")) \
				or float(turn.duration_s) / float(duration) > 0.55 \
				or float(turn.distance_m) / float(length) > 0.55:
			return false
	return true


func _capture_entry_is_inside_basin(evidence: Dictionary) -> bool:
	var margins: Variant = evidence.get("capture_entry_margins_m")
	if not margins is Dictionary or margins.size() != 4:
		return false
	for margin in margins.values():
		if not _finite_number(margin) or float(margin) < 0.0:
			return false
	return true


func _capture_entry_frame_is_reachable(evidence: Dictionary) -> bool:
	return _finite_number(evidence.get("capture_yaw_rad")) \
		and absf(float(evidence.capture_yaw_rad)) \
			<= float(evidence.get("capture_yaw_reach_rad", -INF)) \
		and _finite_number(evidence.get("capture_pitch_rad")) \
		and absf(float(evidence.capture_pitch_rad)) \
			<= float(evidence.get("capture_pitch_reach_rad", -INF)) \
		and _finite_number(evidence.get("capture_roll_rad")) \
		and absf(float(evidence.capture_roll_rad)) <= CAPTURE_ROLL_REACH_RAD


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
		and rim_held_bank_s >= 1.0 and rim_maximum_lateral_g <= 0.05 \
		and rim_duration_s >= 3.5 and rim_duration_s <= 6.0 \
		and rim_distance_m >= 40.0 and rim_distance_m <= 160.0 \
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
