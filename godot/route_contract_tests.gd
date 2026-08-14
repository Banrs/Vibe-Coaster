extends SceneTree

const RouteContract := preload("res://route_contract.gd")

var _errors := PackedStringArray()


func _initialize() -> void:
	_test_smoke_has_no_legacy_authoring_dependency()
	_test_fixed_terminal_contract_accepts_matching_trajectory()
	_test_fixed_terminal_contract_rejects_endpoint_misses()
	_test_fixed_terminal_contract_rejects_invalid_tolerances()
	_test_initial_state_uses_tight_finite_tolerances()
	_test_gesture_analytic_onset_contract()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _test_smoke_has_no_legacy_authoring_dependency() -> void:
	var source := FileAccess.get_file_as_string("res://smoke.gd")
	_expect(not source.is_empty(), "the smoke gate source can be inspected")
	for forbidden in [
		"elements.gd", "Elements.", "RideElements", "FVD", "GRADE", "CLOSURE", "author_",
		"integrate_fvd", "route.sections", "route.plan", "route.lsm_ids",
	]:
		_expect(not source.contains(forbidden),
			"the smoke gate has no legacy authoring token '%s'" % forbidden)


func _test_fixed_terminal_contract_accepts_matching_trajectory() -> void:
	var fixture := _fixture()
	var route := RouteContract.build(42, fixture.terrain, fixture.initial, fixture.plan,
		fixture.compiled, fixture.trajectory)
	_expect(route.get("ok", false),
		"a matching fixed terminal contract is accepted: %s" % str(route.get("errors", [])))
	_expect(_positive_propulsion_zones(route) == PackedInt32Array([1, 2, 3]),
		"the accepted synthetic contract preserves exactly three propulsion zones")
	_expect(route.get("gesture_windows", []).size() == 1 \
		and route.gesture_windows[0].get("first", -1) == 0 \
		and route.gesture_windows[0].get("last", -1) == 3,
		"the accepted synthetic contract preserves its complete gesture window")
	_expect(route.gesture_windows[0].get("peak_profile_normal_onset_estimate_gps") == 7.875,
		"the public gesture window preserves its compiled analytic normal onset")
	_expect(route.get("span_indices") == fixture.trajectory.span_index,
		"the public route preserves native motion-span ownership")
	_expect(route.get("terrain_story_plan", {}).get("integration_frame") == "planned-world",
		"the contract labels accepted positions as direct planned-world integration")
	for legacy_field in ["sections", "section_indices", "lsm_ids", "tunnel_sections"]:
		_expect(not route.has(legacy_field),
			"the public route does not expose legacy field '%s'" % legacy_field)


func _test_fixed_terminal_contract_rejects_endpoint_misses() -> void:
	var position_fixture := _fixture()
	var positions: PackedVector3Array = position_fixture.trajectory.position_m
	positions[-1] += Vector3(0.01, 0.0, 0.0)
	position_fixture.trajectory.position_m = positions
	_expect_rejected(position_fixture, "terminal position", "terminal position outside tolerance")

	var frame_fixture := _fixture()
	var angle := 0.0002
	var tangents: PackedVector3Array = frame_fixture.trajectory.tangent
	tangents[-1] = Vector3(cos(angle), 0.0, sin(angle))
	frame_fixture.trajectory.tangent = tangents
	_expect_rejected(frame_fixture, "terminal tangent", "terminal tangent outside tolerance")

	var speed_fixture := _fixture()
	var speeds: PackedFloat64Array = speed_fixture.trajectory.speed_mps
	speeds[-1] = 1.01
	speed_fixture.trajectory.speed_mps = speeds
	_expect_rejected(speed_fixture, "terminal speed", "terminal speed outside tolerance")


func _test_fixed_terminal_contract_rejects_invalid_tolerances() -> void:
	for field in ["position_tolerance_m", "angle_tolerance_rad", "speed_tolerance_mps"]:
		var fixture := _fixture()
		fixture.compiled.terminal_contract[field] = NAN
		_expect_rejected(fixture, field, "non-finite %s" % field)
		fixture = _fixture()
		fixture.compiled.terminal_contract[field] = 0.0
		_expect_rejected(fixture, field, "nonpositive %s" % field)


func _test_initial_state_uses_tight_finite_tolerances() -> void:
	var close := _fixture()
	close.initial.position_m += Vector3(0.0000005, 0.0, 0.0)
	close.initial.speed_mps += 0.0000005
	var angle := 0.0000005
	close.initial.tangent = Vector3(cos(angle), 0.0, sin(angle))
	var accepted := RouteContract.build(42, close.terrain, close.initial, close.plan,
		close.compiled, close.trajectory)
	_expect(accepted.get("ok", false),
		"finite initial-state roundoff inside the tight tolerance is accepted")

	var far := _fixture()
	far.initial.position_m += Vector3(0.000002, 0.0, 0.0)
	_expect_rejected(far, "initial state", "initial position outside the tight tolerance")

	var nonfinite := _fixture()
	nonfinite.initial.speed_mps = NAN
	_expect_rejected(nonfinite, "finite", "a non-finite initial state")


func _test_gesture_analytic_onset_contract() -> void:
	var missing := _fixture()
	missing.compiled.gesture_spans[0].erase("peak_profile_normal_onset_estimate_gps")
	_expect_rejected(missing, "peak_profile_normal_onset_estimate_gps",
		"a gesture missing analytic normal onset")
	var nonfinite := _fixture()
	nonfinite.compiled.gesture_spans[0].peak_profile_normal_onset_estimate_gps = NAN
	_expect_rejected(nonfinite, "peak_profile_normal_onset_estimate_gps",
		"a gesture with non-finite analytic normal onset")
	var negative := _fixture()
	negative.compiled.gesture_spans[0].peak_profile_normal_onset_estimate_gps = -0.001
	_expect_rejected(negative, "peak_profile_normal_onset_estimate_gps",
		"a gesture with negative analytic normal onset")


func _fixture() -> Dictionary:
	var station_position := Vector3(3.0, 0.0, 0.0)
	var spans := [{"span_id": "one"}, {"span_id": "two"}, {"span_id": "three"}]
	var gesture := {
		"story_slot_id": "synthetic",
		"display_name": "Synthetic",
		"diagnostic_kind": "",
		"occurrence": 0,
		"window_id": "synthetic/whole/00",
		"first_span": 0,
		"last_span": 2,
		"peak_profile_normal_onset_estimate_gps": 7.875,
		"role_windows": [{
			"id": "core",
			"display_name": "Core",
			"diagnostic_kind": "",
			"occurrence": 0,
			"window_id": "synthetic/core/00",
			"first_span": 0,
			"last_span": 2,
		}],
	}
	var compiled := {
		"spans": spans,
		"gesture_spans": [gesture],
		"tunnel_span_ranges": [],
		"propulsion_by_span": PackedInt32Array([1, 2, 3]),
		"minimum_speed_by_span": PackedFloat64Array([0.0, 0.0, 0.0]),
		"generation_stats": {"accepted_integrations": 1, "repair_count": 0},
		"terminal_contract": {
			"station_position_m": station_position,
			"station_tangent": Vector3.RIGHT,
			"station_up": Vector3.UP,
			"terminal_speed_mps": 1.0,
			"position_tolerance_m": 0.001,
			"angle_tolerance_rad": 0.0001,
			"speed_tolerance_mps": 0.0001,
		},
	}
	var plan := {"schema_version": 1, "preset_id": "material-v1", "decisions": {},
		"terrain_frame": {}, "station": {}, "corridor": {},
		"route_length_m": Vector2(7800.0, 8200.0), "roles": []}
	compiled["plan"] = plan
	compiled["role_allocations_m"] = {}
	compiled["return_entry_gate"] = {}
	var zeros := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var trajectory := {
		"ok": true,
		"errors": PackedStringArray(),
		"time_s": PackedFloat64Array([0.0, 1.0, 2.0, 3.0]),
		"distance_m": PackedFloat64Array([0.0, 1.0, 2.0, 3.0]),
		"position_m": PackedVector3Array([
			Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT * 2.0, station_position,
		]),
		"tangent": PackedVector3Array([Vector3.RIGHT, Vector3.RIGHT,
			Vector3.RIGHT, Vector3.RIGHT]),
		"rider_up": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]),
		"speed_mps": PackedFloat64Array([6.0, 5.0, 2.0, 1.0]),
		"normal_g": zeros.duplicate(),
		"lateral_g": zeros.duplicate(),
		"drive_g": PackedFloat64Array([0.1, 0.1, 0.1, 0.0]),
		"longitudinal_g": zeros.duplicate(),
		"roll_rate_rad_s": zeros.duplicate(),
		"curvature_vector_m_inv": PackedVector3Array([
			Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO,
		]),
		"span_index": PackedInt32Array([0, 1, 2, 2]),
		"dense_output": {"max_kinematic_defect_mps": 0.0},
	}
	return {
		"terrain": {"kind": "synthetic"},
		"initial": {
			"position_m": Vector3.ZERO,
			"tangent": Vector3.RIGHT,
			"rider_up": Vector3.UP,
			"speed_mps": 6.0,
		},
		"plan": plan,
		"compiled": compiled,
		"trajectory": trajectory,
	}


func _expect_rejected(fixture: Dictionary, fragment: String, message: String) -> void:
	var route := RouteContract.build(42, fixture.terrain, fixture.initial, fixture.plan,
		fixture.compiled, fixture.trajectory)
	_expect(not route.get("ok", true), "%s is rejected" % message)
	_expect(_contains(route.get("errors", []), fragment),
		"%s reports a diagnostic containing '%s': %s" % [
			message, fragment, str(route.get("errors", [])),
		])


func _positive_propulsion_zones(route: Dictionary) -> PackedInt32Array:
	var result := PackedInt32Array()
	var previous := 0
	for value in route.get("propulsion_ids", PackedInt32Array()):
		if value > 0 and value != previous:
			result.append(value)
		previous = value
	return result


func _contains(values: Variant, fragment: String) -> bool:
	for value in values:
		if str(value).contains(fragment):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
