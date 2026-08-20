extends SceneTree

const Motion := preload("res://motion.gd")
const RideProgram := preload("res://ride_program.gd")
const RidePrefixSolve := preload("res://ride_prefix_solve.gd")
const RideReturnSolve := preload("res://ride_return_solve.gd")
const RideGenerator := preload("res://generator.gd")
const RidePlanner := preload("res://ride_planner.gd")
const GeometryMetrics := preload("res://geometry_metrics.gd")
const CAPTURE_MARGIN_IDS := [
	"coefficient_margin",
	"brake_reserve_m",
	"capture_partition_entry_m",
	"corridor_cross_m",
	"corridor_forward_high_m",
	"corridor_forward_low_m",
	"corridor_height_m",
	"entry_speed_high_mps",
	"entry_speed_low_mps",
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
const CAPTURE_COARSE_RESIDUAL_LIMITS := [0.075, 0.075, 0.0001, 0.0001, 0.0001]
## The aim bands the closure tests build around the untargeted footprint's own measurements:
## tight enough that "targeting today's geometry" means today's geometry, wide enough to hold
## the published tunnel exit's pre-seam sample offset. The record band is a real interior band
## of the smoke-gated 93.9-95.6 m/s record.
const PREFIX_SPAN_AIM_TOLERANCE_M := 3.0
const PREFIX_SUMMIT_AIM_TOLERANCE_M := 2.0
const PREFIX_RECORD_AIM_BAND_MPS := Vector2(94.2, 95.3)
## The fifth closure residual's aim band for these fixtures. Deliberately wide: these prefixes are
## built on synthetic frames, not on the production placement, so their dive arc is not the
## production role's and a tight band would test the fixture rather than the solve. The fleet
## measurement of this residual is `generator_material_tests.gd` and `smoke.gd`, on the production
## band; here it is declared, satisfied and inert, which is what keeps the other four honest.
const PREFIX_ARC_AIM_BAND_M := Vector2(200.0, 900.0)
const PREFIX_DISPLACED_RECORD_BAND_MPS := Vector2(95.05, 95.45)
const PREFIX_DISPLACED_SPAN_AIM_TOLERANCE_M := 12.0
const PREFIX_DISPLACED_SUMMIT_AIM_TOLERANCE_M := 8.0
## What these pin: `terrain_story_capability` called without a closure target must stay
## byte-identical, so an unsolved prefix - every fixture, and the seed every closure starts from -
## is exactly the authored one. Re-baselined once when production adopted the closure solve: the
## published footprint gained `tunnel_exit_step_m`, the one production step between the residual's
## terminal tunnel sample and the pre-seam sample placement consumes. A change here is a
## re-baseline, never a nudge.
const PREFIX_CAPABILITY_DIGEST := {
	-1: "7c7c20d8539f3924916218e7ccc5ea03344f766c910c4ba2d1fb2d18b48fe3b6",
	1: "076e644f7863687173f17913d473e78828b481fca6b1cee1b12ca049faa5167a",
}
var _errors := PackedStringArray()


func _initialize() -> void:
	_test_capture_accepts_varied_station_frames()
	_test_preset_return_gate_contract()
	_test_sustained_brake_closes_without_padding()
	_test_material_return_recipe()
	_test_first_return_turn_unbanks_directly()
	_test_record_release_turn_is_declared_macro_authority()
	_test_record_release_turn_has_roll_headroom()
	_test_return_aim_margins_exceed_solver_slack()
	_test_camelback_is_planar_and_continuous()
	_test_return_flow_classifier_rejects_neutral_interval()
	_test_terrain_story_capability_is_finite_and_handed()
	_test_station_local_program_compiles()
	_test_material_role_span_ownership_is_total()
	_test_malformed_capture_is_structured()
	_test_impossible_capture_is_bounded_without_fallback()
	_test_nonfinite_capture_margin_is_rejected()
	_test_return_solve_stays_inside_its_derived_budget()
	_test_untargeted_prefix_capability_is_unchanged()
	_test_prefix_closure_solve_targets_todays_geometry()
	_test_prefix_closure_solve_moves_the_record_handoff()
	_test_infeasible_prefix_closure_is_structured()
	_test_prefix_closure_solve_accepts_non_axis_aligned_outward_local()
	_test_prefix_closure_solve_converges_on_a_drawn_story()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _test_sustained_brake_closes_without_padding() -> void:
	var corridor: Dictionary = _plan(_layout()).corridor
	var brake_length_m := float(corridor.brake_length_m)
	var capture_length_m := float(corridor.capture_length_m)
	var fixtures := [
		{"id": "partial-brake-reserve",
			"remaining_m": brake_length_m - 0.2 * capture_length_m},
		{"id": "full-brake-reserve", "remaining_m": brake_length_m},
	]
	var accepted_holds := []
	for fixture: Dictionary in fixtures:
		var start := {"position_m": Vector3.ZERO, "tangent": Vector3.RIGHT,
			"rider_up": Vector3.UP, "speed_mps": 69.0,
			"distance_m": 0.0, "time_s": 0.0}
		var layout := {"station_position_m": Vector3(fixture.remaining_m, 0.0, 0.0),
			"station_tangent": Vector3.RIGHT, "station_up": Vector3.UP,
			"reserved_corridor": {"minimum_length_m": 230.0,
				"capture_length_m": 80.0, "brake_length_m": 150.0,
				"entry_speed_mps": Vector2(70.0, 80.0)}}
		var solved := RideReturnSolve._solve_brakes(start, layout)
		if not _expect(solved.get("ok", false),
				"the %s brake owner consumes its full distance: %s" % [fixture.id, str(solved)]):
			continue
		var repeated := RideReturnSolve._solve_brakes(start, layout)
		_expect(var_to_bytes(solved) == var_to_bytes(repeated),
			"the %s brake solve is byte-identical" % fixture.id)
		var parts := _terminal_program_parts(solved.get("spans", []))
		if not _expect(parts.ok,
				"the %s terminal has one active moving brake phase followed by station mode"
				% fixture.id):
			continue
		_expect(RideProgram._validate_control_seams(solved.spans).is_empty(),
			"the %s brake and station seams are C2" % fixture.id)
		var full := Motion.integrate(start, solved.spans, RideProgram._settings(0.01))
		var production := _independent_brake_observation(
			start, parts.moving_spans, 0.0, 0.01)
		if not _expect(full.get("ok", false) and production.ok,
				"the %s terminal independently integrates" % fixture.id):
			continue
		var station_distance: float = full.distance_m[-1] - production.moving_distance_m
		var report: Dictionary = solved.get("report", {})
		var projected_remaining_m: float = (layout.station_position_m - start.position_m).dot(
			layout.station_tangent.normalized())
		var moving_target: float = projected_remaining_m - station_distance
		production = _independent_brake_observation(
			start, parts.moving_spans, moving_target, 0.01)
		_expect(absf(production.moving_boundary_speed_mps - 2.0) <= 0.0001,
			"the %s native moving handoff reaches 2 m/s" % fixture.id)
		_expect(full.position_m[-1].distance_to(layout.station_position_m) <= 0.05
			and absf(float(full.speed_mps[-1]) - 1.0) <= 0.001,
			"the %s terminal reaches station at 1 m/s" % fixture.id)
		var values: Variant = report.get("accepted_values")
		_expect(report.get("parameter_bounds") == [[0.5, 5.0], [0.0, 3.6]]
			and parts.hold_duration_s >= 0.5 and parts.hold_duration_s <= 5.0
			and parts.peak_g >= 0.0 and parts.peak_g <= 3.6,
			"the %s authored hold and peak satisfy the literal recipe bounds" % fixture.id)
		_expect(values is Array and values.size() == 2
			and absf(float(values[0]) - parts.hold_duration_s) <= 0.000001
			and absf(float(values[1]) - parts.peak_g) <= 0.000001
			and absf(float(report.get("active_duration_s", -1.0))
				- parts.active_duration_s) <= 0.000001,
			"the %s report is tied to the authored brake controls" % fixture.id)
		accepted_holds.append(parts.hold_duration_s)
		for step_and_field in [[0.01, "production_observation"],
				[0.05, "coarse_observation"], [0.025, "fine_observation"]]:
			var measured := _independent_brake_observation(
				start, parts.moving_spans, moving_target, float(step_and_field[0]))
			_expect(measured.ok and _residuals_are_within(
					measured.get("residuals", []), [0.05, 0.0001]),
				"the %s %s independently satisfies both brake residuals"
				% [fixture.id, step_and_field[1]])
			_expect(_brake_report_observation_is_valid(
					report.get(step_and_field[1], {}), report),
				"the %s %s publishes finite self-consistent brake residuals"
				% [fixture.id, step_and_field[1]])
		_expect(absf(float(report.get("station_distance_m", INF)) - station_distance) <= 0.001
			and absf(float(report.get("remaining_distance_m", INF)) - fixture.remaining_m) <= 0.001
			and absf(float(report.get("distance_residual_m", INF))) <= 0.05,
			"the %s report accounts for moving, creep, and remaining distance" % fixture.id)
		_expect(int(report.get("unique_evaluations", -1)) >= 1
			and int(report.get("unique_evaluations", 25)) <= 24
			and report.get("max_unique_evaluations") == 24
			and _conditioning_matches_accepted_point(report, "accepted_values"),
			"the %s brake publishes its bounded solve diagnostics" % fixture.id)
	_expect(accepted_holds.size() == 2 and accepted_holds[1] >= accepted_holds[0] + 0.3,
		"additional distance alone materially lengthens the accepted brake hold")


func _test_camelback_is_planar_and_continuous() -> void:
	var spans: Array = []
	var metadata: Array = []
	var propulsion := PackedInt32Array()
	RideProgram._add_camelback(spans, metadata, propulsion)
	_expect(spans.size() == 5, "camelback has five meaningful FVD phases, got %d" % spans.size())
	for span: Dictionary in spans:
		_expect(str(span.span_id).find("hold") < 0,
			"camelback has no semantic hold span: %s" % str(span.span_id))
		_expect(float(span.duration_s) >= 0.30,
			"camelback phase is long enough to be geometric: %s" % str(span.span_id))
		_expect(span.lateral_g.kind == "constant" and absf(float(span.lateral_g.value)) <= 0.000001,
			"camelback lateral force is zero: %s" % str(span.span_id))
		_expect(span.roll_rate_rad_s.kind == "constant"
			and absf(float(span.roll_rate_rad_s.value)) <= 0.000001,
			"camelback roll rate is zero: %s" % str(span.span_id))
	var transition_audit := GeometryMetrics.transition_audit(spans)
	_expect(transition_audit.ok, "camelback transition audit is clean: %s"
		% str(transition_audit.errors))
	var route := RideGenerator.build(42)
	if not _expect(route.get("ok", false),
			"production seed 42 publishes a route for the camelback audit"):
		return
	var role_record: Dictionary = route.get("geometry_audit", {}).get("roles", {}).get("camelback", {})
	_expect(role_record.get("status") == "measured",
		"production camelback publishes measured role evidence")
	var lateral_range: Dictionary = role_record.get("lateral_g", {})
	var roll_range: Dictionary = role_record.get("roll_rate_dps", {})
	_expect(absf(float(lateral_range.get("minimum", INF))) <= 0.0001
		and absf(float(lateral_range.get("maximum", INF))) <= 0.0001,
		"production camelback has no lateral force shift: %s" % str(lateral_range))
	_expect(absf(float(roll_range.get("minimum", INF))) <= 0.0001
		and absf(float(roll_range.get("maximum", INF))) <= 0.0001,
		"production camelback has neutral roll rate: %s" % str(roll_range))
	var agl: Dictionary = role_record.get("agl", {})
	_expect(agl.get("status") == "measured"
		and float(agl.get("apex_m", -INF)) >= 140.0
		and float(agl.get("apex_m", INF)) <= 170.0,
		"production camelback apex stays in its 140-170 m AGL band: %s" % str(agl))


func _test_material_return_recipe() -> void:
	var spans: Array = []
	var metadata: Array = []
	var gestures: Array = []
	var propulsion := PackedInt32Array()
	RideProgram._begin_gesture(gestures, "raceway-return", 0)
	RideProgram._add_raceway(spans, metadata, propulsion)
	RideProgram._end_gesture(gestures, metadata, spans.size() - 1)
	_expect(not spans.is_empty() and metadata.size() == spans.size()
		and propulsion.size() == spans.size(),
		"every return span has semantic and propulsion ownership")
	var route := Motion.integrate({
		"position_m": Vector3.ZERO, "tangent": Vector3.RIGHT,
		"rider_up": Vector3.UP, "speed_mps": 89.0,
		"distance_m": 0.0,
		"time_s": 0.0,
	}, spans, RideProgram._settings(0.01))
	if not _expect(route.get("ok", false),
			"the public return recipe integrates from a finite level upright moving state"):
		return
	var role_ids := []
	var roles: Array = gestures[0].role_windows
	for role: Dictionary in roles:
		role_ids.append(role.id)
	_expect(role_ids == ["turn-a", "height-airtime-a", "turn-b", "height-airtime-b"],
		"the return exposes exactly four ordered nonempty semantic roles")
	var contiguous := roles.size() == 4 and int(roles[0].first_span) == 0 \
		and int(roles[-1].last_span) == spans.size() - 1
	for index in range(1, roles.size()):
		contiguous = contiguous and int(roles[index - 1].last_span) + 1 \
			== int(roles[index].first_span)
	for role: Dictionary in roles:
		contiguous = contiguous and int(role.first_span) <= int(role.last_span)
	_expect(contiguous,
		"the four physical return roles contiguously own the complete recipe")


func _test_first_return_turn_unbanks_directly() -> void:
	var spans := RideReturnSolve._return_spans(RideReturnSolve.RETURN_SEED)
	var directions := []
	var post_core_positive := false
	var in_core := false
	for span: Dictionary in spans:
		var span_id := str(span.span_id)
		if span_id == "raceway/turn-a/core":
			in_core = true
			continue
		if not span_id.begins_with("raceway/turn-a/"):
			if in_core:
				break
			continue
		var roll_rate := Motion.profile_sample(span.roll_rate_rad_s, 0.5).x
		if absf(roll_rate) <= 0.000001:
			continue
		var direction := 1 if roll_rate > 0.0 else -1
		directions.append(direction)
		if in_core and direction > 0:
			post_core_positive = true
	var reversals := 0
	for index in range(1, directions.size()):
		if directions[index] != directions[index - 1]:
			reversals += 1
	_expect(directions.size() >= 2 and directions[0] > 0 and directions[-1] < 0
		and reversals == 1 and not post_core_positive,
		"the first return turn banks in once and directly unbanks without a counter-steer: %s"
		% str(directions))


func _test_record_release_turn_is_declared_macro_authority() -> void:
	var roles := RidePlanner.canonical_role_ids()
	var release_index := roles.find("record-release-turn")
	var controls := RideReturnSolve.RETURN_SCALAR_IDS
	var residuals := RideReturnSolve.RETURN_RESIDUAL_IDS
	_expect(release_index > 0 and release_index + 1 < roles.size()
		and roles[release_index - 1] == "camelback"
		and roles[release_index - 2] == "tunnel-lsm3"
		and roles[release_index + 1] == "return-turn-a"
		and controls.has("record_release_core_duration_s")
		and residuals.has("record_release_length_band_m")
		and controls.size() == residuals.size(),
		"the record release follows the fixed camelback with a declared square macro axis: %s / %s / %s"
		% [str(roles), str(controls), str(residuals)])


func _test_record_release_turn_has_roll_headroom() -> void:
	var spans: Array = []
	var metadata: Array = []
	var propulsion := PackedInt32Array()
	RideProgram._add_record_release_turn(spans, metadata, propulsion)
	var peak_roll_dps := 0.0
	for span: Dictionary in spans:
		peak_roll_dps = maxf(peak_roll_dps,
			absf(rad_to_deg(Motion.profile_sample(span.roll_rate_rad_s, 0.5).x)))
	_expect(spans.size() == 3 and is_equal_approx(float(spans[0].duration_s), 0.8)
		and is_equal_approx(float(spans[2].duration_s), 0.8)
		and peak_roll_dps <= 120.0,
		"the release shoulders preserve role length with roll-rate headroom: %s / %.3f dps"
		% [str([spans[0].duration_s, spans[2].duration_s]), peak_roll_dps])


func _test_return_aim_margins_exceed_solver_slack() -> void:
	var route_slack_m := 0.02 * float(RideReturnSolve.RETURN_RESIDUAL_SCALES[5])
	var release_slack_m := 0.02 * float(RideReturnSolve.RETURN_RESIDUAL_SCALES[8])
	_expect(RideReturnSolve.RETURN_LENGTH_AIM_MARGIN_M > route_slack_m
		and RideReturnSolve.RECORD_RELEASE_LENGTH_AIM_MARGIN_M > release_slack_m,
		"return aim margins exceed convergence slack: %.3f/%.3f m vs %.3f/%.3f m"
		% [RideReturnSolve.RETURN_LENGTH_AIM_MARGIN_M,
			RideReturnSolve.RECORD_RELEASE_LENGTH_AIM_MARGIN_M,
			route_slack_m, release_slack_m])


func _test_return_flow_classifier_rejects_neutral_interval() -> void:
	var neutral := [Motion.span("synthetic-neutral", 0.30, "moving",
		Motion.constant(1.0), Motion.constant(0.0), Motion.constant(0.0),
		Motion.constant(0.0))]
	var route := Motion.integrate({
		"position_m": Vector3.ZERO, "tangent": Vector3.RIGHT,
		"rider_up": Vector3.UP, "speed_mps": 60.0,
		"distance_m": 0.0, "time_s": 0.0,
	}, neutral, RideProgram._settings(0.01))
	var observed := _return_flow_observation(route,
		[{"first_span": 0, "last_span": 0}], Vector2i(0, route.time_s.size() - 1), Vector3.UP)
	_expect(route.get("ok", false) and not observed.ok and observed.dead_flat_s > 0.25,
		"the trajectory classifier rejects a synthetic 0.30 s neutral filler")


func _test_terrain_story_capability_is_finite_and_handed() -> void:
	var left := RideProgram.terrain_story_capability(-1)
	var right := RideProgram.terrain_story_capability(1)
	_expect(left.get("ok", false) and right.get("ok", false)
		and left.get("planning_integrations") == 1 and right.get("planning_integrations") == 1,
		"each handed terrain capability uses one finite planning integration")
	if not left.get("ok", false) or not right.get("ok", false):
		return
	var a: Dictionary = left.role_13_entry
	var b: Dictionary = right.role_13_entry
	_expect(a.offset_m is Vector3 and b.offset_m is Vector3
		and a.offset_m.is_finite() and b.offset_m.is_finite()
		and a.tangent.is_finite() and b.tangent.is_finite()
		and a.rider_up.is_finite() and b.rider_up.is_finite()
		and _positive_finite(a.speed_mps) and _positive_finite(b.speed_mps),
		"the capability publishes a finite role-13 station-local handoff")
	_expect(absf(a.offset_m.x - b.offset_m.x) <= 0.05
		and absf(a.offset_m.y - b.offset_m.y) <= 0.05
		and absf(a.offset_m.z + b.offset_m.z) <= 0.05
		and absf(a.speed_mps - b.speed_mps) <= 0.01,
		"station handedness mirrors world placement without changing canonical scalar capability")
	var left_footprint: Variant = left.get("dive_footprint")
	var right_footprint: Variant = right.get("dive_footprint")
	_expect(left_footprint is Dictionary and right_footprint is Dictionary
		and _positive_finite(left_footprint.get("outward_delta_m"))
		and _positive_finite(right_footprint.get("outward_delta_m"))
		and left_footprint.get("dive_exit_offset_m") is Vector3
		and left_footprint.get("tunnel_exit_offset_m") is Vector3
		and right_footprint.get("dive_exit_offset_m") is Vector3
		and right_footprint.get("tunnel_exit_offset_m") is Vector3
		and left_footprint.get("positions_m") is PackedVector3Array
		and left_footprint.get("rider_up") is PackedVector3Array
		and right_footprint.get("positions_m") is PackedVector3Array
		and right_footprint.get("rider_up") is PackedVector3Array
		and left_footprint.dive_exit_offset_m.is_finite()
		and left_footprint.tunnel_exit_offset_m.is_finite()
		and right_footprint.dive_exit_offset_m.is_finite()
		and right_footprint.tunnel_exit_offset_m.is_finite()
		and not left_footprint.positions_m.is_empty()
		and left_footprint.positions_m.size() == left_footprint.rider_up.size()
		and right_footprint.positions_m.size() == right_footprint.rider_up.size()
		and absf(float(left_footprint.outward_delta_m)
			- float(right_footprint.outward_delta_m)) <= 0.05,
		"the native dive/tunnel footprint is finite, outward, and hand-invariant")
	_expect(right.scale == {"route_vertical_envelope_m": Vector2(290.0, 305.0),
		"dive_drop_m": Vector2(240.0, 250.0),
		"camel_prominence_m": Vector2(245.0, 255.0)},
		"the planning capability publishes the reviewed near-future vertical bands")


func _test_preset_return_gate_contract() -> void:
	var compiled := _compile(_layout())
	if not _expect(compiled.get("ok", false),
			"the preset return closes: %s" % str(compiled.get("failure", {}))):
		return
	var trajectory := _integrated_trajectory(compiled, _layout())
	var gesture := _compiled_gesture(compiled, "raceway-return")
	var bounds := _owned_span_bounds(trajectory.span_index, gesture.first_span, gesture.last_span)
	_expect(trajectory.get("ok", false) and bounds.x >= 0
		and trajectory.distance_m[bounds.y] - trajectory.distance_m[bounds.x] <= 2500.0,
		"the preset return fits its physical length budget")
	var report: Dictionary = compiled.get("return_plan", {})
	_expect(_return_trajectory_is_material(trajectory, gesture.role_windows, _layout()),
		"the accepted preset return satisfies the role-level physical contract")
	var accepted_parameters: Variant = report.get("accepted_values")
	var scalar_bounds: Variant = report.get("scalar_bounds")
	var parameters_are_bounded: bool = accepted_parameters is Array and scalar_bounds is Array \
		and accepted_parameters.size() == scalar_bounds.size() and not accepted_parameters.is_empty()
	if parameters_are_bounded:
		for index in accepted_parameters.size():
			parameters_are_bounded = parameters_are_bounded \
				and _finite_number(accepted_parameters[index]) \
				and scalar_bounds[index] is Array and scalar_bounds[index].size() == 2 \
				and float(accepted_parameters[index]) >= float(scalar_bounds[index][0]) \
				and float(accepted_parameters[index]) <= float(scalar_bounds[index][1])
	_expect(parameters_are_bounded,
		"every accepted return calibration remains inside its published finite bound")
	var rotated_layout := _layout()
	var rotation := Basis(Vector3.UP, deg_to_rad(53.0))
	rotated_layout.station_position_m = Vector3(120.0, 15.0, -80.0)
	rotated_layout.station_tangent = rotation * Vector3.RIGHT
	var rotated := _compile(rotated_layout)
	var base_observation: Variant = report.get("fine_observation")
	var rotated_observation: Variant = rotated.get("return_plan", {}).get("fine_observation")
	_expect(rotated.get("ok", false)
		and _return_observations_are_equivalent(base_observation, rotated_observation),
		"the accepted return is rigid-frame equivariant in station-local physical space")
	var impossible := _layout()
	impossible.reserved_corridor.minimum_length_m = 100.0
	var rejected := _compile(impossible)
	_expect(not rejected.get("ok", true) and rejected.get("failure", {}).get("stage") == "plan",
		"an infeasible reserved corridor is rejected structurally")


func _station_local_observation(state: Dictionary, layout: Dictionary) -> Array:
	var forward: Vector3 = layout.station_tangent.normalized()
	var up: Vector3 = layout.station_up.normalized()
	var right := forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	var position: Vector3 = state.position_m
	var tangent: Vector3 = state.tangent.normalized()
	var rider_up: Vector3 = state.rider_up
	var reference_up := (up - tangent * up.dot(tangent)).normalized()
	var actual_up := (rider_up - tangent * rider_up.dot(tangent)).normalized()
	return [(position - layout.station_position_m).dot(forward),
		(position - layout.station_position_m).dot(up),
		(position - layout.station_position_m).dot(right),
		atan2(tangent.dot(right), tangent.dot(forward)),
		asin(clampf(tangent.dot(up), -1.0, 1.0)),
		atan2(tangent.dot(reference_up.cross(actual_up)), reference_up.dot(actual_up))]


func _test_station_local_program_compiles() -> void:
	var compiled := _compile(_layout())
	if not _expect(compiled.get("ok", false),
			"the explicit station-local return fixture compiles: %s" % str(compiled.get("errors", []))):
		return
	_expect(_near_future_story_is_physical(compiled, _layout()),
		"the raw trajectory carries the reviewed near-future signature scale and continuous flow")
	_expect(not compiled.get("spans", []).is_empty(), "the compiled program contains motion spans")
	_expect(compiled.get("capture_plan", {}).get("unique_evaluations", 41) <= 40,
		"the accepted capture stays within its public evaluation budget")
	_expect(_return_and_terminal_drive_is_nonpositive(compiled),
		"every global-return, capture, brake, and station drive profile is nonpositive")
	_expect(_return_is_passive_and_material(compiled, _layout()),
		"the integrated return meets every public materiality and passivity threshold")
	_expect(_compiled_return_flow_is_continuous(compiled, _layout()),
		"the uninterrupted return has no dead-flat or low-activity filler")
	var return_plan: Dictionary = compiled.get("return_plan", {})
	_expect(return_plan.get("positive_drive_allowed", true) == false
		and return_plan.get("accepted_values", []) is Array
		and not return_plan.get("accepted_values", []).is_empty(),
		"the passive return publishes the calibration that satisfied its physical target")
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
	_expect(brake.get("parameter_bounds") == [[0.5, 5.0], [0.0, 3.6]]
		and float(brake.get("hold_duration_s", -1.0)) >= 0.5
		and float(brake.get("hold_duration_s", 6.0)) <= 5.0
		and float(brake.get("brake_peak_g", -1.0)) >= 0.0
		and float(brake.get("brake_peak_g", 4.0)) <= 3.6
		and _finite_number(brake.get("distance_residual_m"))
		and absf(float(brake.distance_residual_m)) <= 0.05,
		"the public brake reports a bounded hold/peak and closed distance residual")
	var terminal_gesture := _compiled_gesture(compiled, "brakes-station-capture")
	var trajectory := _integrated_trajectory(compiled, _layout())
	var observed_brake_entry_speed := INF
	for span_index in range(int(terminal_gesture.first_span), int(terminal_gesture.last_span) + 1):
		var active := false
		for u in [0.0, 0.25, 0.5, 0.75, 1.0]:
			active = active or Motion.profile_sample(
				compiled.spans[span_index].drive_g, u).x < -0.000001
		if active:
			var brake_bounds := _owned_span_bounds(trajectory.span_index, span_index, span_index)
			observed_brake_entry_speed = trajectory.speed_mps[brake_bounds.x]
			break
	_expect(_positive_finite(observed_brake_entry_speed)
		and _positive_finite(brake.get("brake_entry_speed_mps"))
		and absf(float(brake.get("brake_entry_speed_mps", INF))
			- observed_brake_entry_speed) <= 0.000001,
		"the public brake begins at its independently observed production state")
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
			Vector3(0.8, 0.0, 0.6), 75.4847075745055, 209.0,
			-0.09809875488281, 0.00093841552734,
			-0.012743739647, -0.0021031915, -28.5617102),
		_capture_fixture("rotated-mirrored-holonomy", Vector3(-260.0, 31.0, 190.0),
			Vector3(-0.6, 0.0, 0.8), 75.4847075745055, 209.0,
			0.09809875488281, 0.00093841552734,
			0.012743739647, -0.0021031915, 28.5617102),
	]
	var settings: Dictionary = RideProgram._settings(0.025)
	for fixture: Dictionary in fixtures:
		var solved: Dictionary = RideReturnSolve._solve_capture(
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
			var limits := CAPTURE_COARSE_RESIDUAL_LIMITS \
				if is_equal_approx(float(step_and_field[0]), 0.05) else CAPTURE_RESIDUAL_LIMITS
			_expect(measured.get("ok", false) and _residuals_are_within(
					measured.get("residuals", []), limits),
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
		"reserved_corridor": {"minimum_length_m": 230.0,
			"capture_length_m": 80.0, "brake_length_m": 150.0,
			"entry_speed_mps": Vector2(70.0, 80.0)},
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
		RideReturnSolve._capture_spans(coefficients), RideProgram._settings(step_s))
	if not route.get("ok", false):
		return {"ok": false, "errors": route.get("errors", [])}
	var terminal := Motion.sample_time(route, float(route.time_s[-1]))
	var observed := _station_local_observation(terminal, fixture.layout)
	return {"ok": true, "residuals": [
		observed[2], observed[1], observed[3], observed[4], observed[5]]}


func _residual_vectors_near(actual: Variant, expected: Variant, tolerance: float) -> bool:
	if not actual is Array or not expected is Array or actual.size() != expected.size():
		return false
	for index in actual.size():
		if not _finite_number(actual[index]) or not _finite_number(expected[index]) \
				or absf(float(actual[index]) - float(expected[index])) > tolerance:
			return false
	return true


func _return_observations_are_equivalent(actual: Variant, expected: Variant) -> bool:
	if not actual is Dictionary or not expected is Dictionary:
		return false
	var fields := ["station_forward_m", "cross_track_m", "height_m", "yaw_rad",
		"pitch_rad", "route_total_length_m", "speed_mps"]
	# Two independently accepted solutions may lie on opposite sides of the solver tolerance.
	for index in fields.size():
		var field: String = fields[index]
		if not _finite_number(actual.get(field)) or not _finite_number(expected.get(field)) \
				or absf(float(actual[field]) - float(expected[field])) \
				> 0.04 * float(RideReturnSolve.RETURN_RESIDUAL_SCALES[index]):
			return false
	return true


func _return_production_observations_match(actual: Variant, expected: Variant) -> bool:
	if not actual is Dictionary or not expected is Dictionary:
		return false
	for field_and_index: Array in [
		["station_forward_m", 0], ["cross_track_m", 1], ["height_m", 2],
		["yaw_rad", 3], ["pitch_rad", 4], ["roll_rad", 4],
		["route_total_length_m", 5], ["speed_mps", 6],
		["turn_b_length_m", 7], ["record_release_length_m", 8],
	]:
		var field: String = field_and_index[0]
		var tolerance_index: int = field_and_index[1]
		if not _finite_number(actual.get(field)) or not _finite_number(expected.get(field)) \
				or absf(float(actual[field]) - float(expected[field])) \
					> RideReturnSolve.RETURN_FINE_TOLERANCES[tolerance_index]:
			return false
	return true


func _test_malformed_capture_is_structured() -> void:
	var fixture := _capture_fixture("malformed", Vector3.ZERO, Vector3.RIGHT,
		75.4847075745055, 209.0, -0.09809875488281, 0.00093841552734,
		-0.012743739647, -0.0021031915, -28.5617102)
	fixture.layout["capture_seed"] = [0.0, 0.0, 0.0, 0.0]
	var solved := RideReturnSolve._solve_capture(fixture.state, fixture.layout,
		RideProgram._settings(0.025))
	_expect_capture_failure(solved, 0, 0, "a malformed capture seed fails before evaluation")


func _test_impossible_capture_is_bounded_without_fallback() -> void:
	var fixture := _capture_fixture("negative-width", Vector3.ZERO, Vector3.RIGHT,
		75.4847075745055, 209.0, -0.09809875488281, 0.00093841552734,
		-0.012743739647, -0.0021031915, -28.5617102)
	fixture.layout["capture_half_width_m"] = -1.0
	var solved := RideReturnSolve._solve_capture(fixture.state, fixture.layout,
		RideProgram._settings(0.025))
	_expect_capture_failure(solved, 1, 40,
		"an impossible negative-width capture corridor fails within the evaluation budget", true)


func _test_nonfinite_capture_margin_is_rejected() -> void:
	var fixture := _capture_fixture("nonfinite-width", Vector3.ZERO, Vector3.RIGHT,
		75.4847075745055, 209.0, -0.09809875488281, 0.00093841552734,
		-0.012743739647, -0.0021031915, -28.5617102)
	fixture.layout["capture_half_width_m"] = NAN
	var solved := RideReturnSolve._solve_capture(fixture.state, fixture.layout,
		RideProgram._settings(0.025))
	_expect_capture_failure(solved, 1, 40,
		"a nonfinite capture margin is rejected before a plan can be accepted", true)


## The fast half of the return budget claim; the cap's derivation lives at
## `RideReturnSolve.MAX_RETURN_EVALUATIONS`. Measured on the design's five-seed set (the three deep
## seeds plus 1 and 123456) rather than all fifteen: each seed costs a full compile, and the
## sweep seeds add minutes here without adding a new solve regime. `smoke.gd` carries the
## fifteen-seed half inside the builds it already pays for.
func _test_return_solve_stays_inside_its_derived_budget() -> void:
	_expect(RideReturnSolve.MAX_RETURN_EVALUATIONS == 220,
		"the return evaluation cap is the derived 220, not %d"
		% RideReturnSolve.MAX_RETURN_EVALUATIONS)
	var allowance := int(0.6 * RideReturnSolve.MAX_RETURN_EVALUATIONS)
	for seed_value in [11, 42, 20260809, 1, 123456]:
		var decisions := RidePlanner.resolve(seed_value)
		var plan := RideGenerator._plan(
			RideTerrain.generate(decisions.streams[RidePlanner.STREAM_TERRAIN]), decisions)
		if not _expect(not plan.has("ok") or plan.ok, "seed %d plans" % seed_value):
			continue
		var compiled := RideProgram.compile(plan, RideGenerator._initial_state(plan.station))
		if not _expect(compiled.get("ok", false),
				"seed %d compiles: %s" % [seed_value, str(compiled.get("failure", {}))]):
			continue
		var report: Dictionary = compiled.get("return_plan", {})
		var evaluations := int(report.get("unique_evaluations", -1))
		print("return solve seed %d: %d evaluations, %d iterations, status %s" % [seed_value,
			evaluations, int(report.get("solver_iterations", -1)),
			str(report.get("solver_status", "missing"))])
		_expect(evaluations >= 1 and evaluations <= allowance
			and report.get("max_unique_evaluations") == RideReturnSolve.MAX_RETURN_EVALUATIONS,
			"seed %d spends %d return evaluations, over the %d fleet allowance"
			% [seed_value, evaluations, allowance])
		_expect_return_closes_interior(seed_value, report)
		_expect_compiled_prefix_matches_plan(seed_value, plan, compiled)


## What `RETURN_LENGTH_AIM_MARGIN_M` buys, read off the accepted point: an accepted return sits
## interior to its route-length band by construction rather than converging onto the 8200 m ceiling
## and being refused there. Both halves are checked, because the aim margin shapes the *residual*
## only - the published margins must still measure the outer band, or acceptance would have moved
## with the aim and the ride would be gated against a band it was never built to.
func _expect_return_closes_interior(seed_value: int, report: Dictionary) -> void:
	var margins: Dictionary = report.get("margins", {})
	var high := float(margins.get("route_length_high_m", NAN))
	var low := float(margins.get("route_length_low_m", NAN))
	var aim := RideReturnSolve.RETURN_LENGTH_AIM_MARGIN_M
	var convergence_slack_m := 0.02 * float(RideReturnSolve.RETURN_RESIDUAL_SCALES[5])
	var guaranteed_margin_m := aim - convergence_slack_m
	_expect(low >= guaranteed_margin_m and high >= guaranteed_margin_m,
		"seed %d closes %.4f m above and %.4f m below its route-length band; the structural floor is %.2f m"
		% [seed_value, low, high, guaranteed_margin_m])
	var fine: Dictionary = report.get("fine_observation", {})
	var production: Dictionary = report.get("production_observation", {})
	var total := float(production.get("route_total_length_m", NAN))
	_expect(absf(high + total - RideReturnSolve.RETURN_TOTAL_LENGTH_BAND_M.y) <= 0.000001,
		"seed %d still measures its accepted %.4f m against the outer %.1f m ceiling"
		% [seed_value, total, RideReturnSolve.RETURN_TOTAL_LENGTH_BAND_M.y])
	_expect(report.get("verification_integrations") == 1
		and _return_production_observations_match(production, fine),
		"seed %d publishes one continuous production verification matching its segmented solve"
		% seed_value)


## The threading the closure needs to mean anything: `compile` must build the production span
## program from the plan's own accepted controls, or the ride would be built from `PREFIX_SEED`
## while the generator placed the solved footprint. Read off the built spans, not the call site.
func _expect_compiled_prefix_matches_plan(
	seed_value: int, plan: Dictionary, compiled: Dictionary
) -> void:
	var accepted: Array = plan.terrain_frame.planning.closure.accepted_values
	var flex_span_ids := ["climb/powered-core", "climb/pull-over", "rim/slow-crest-core",
		"dive/face-approach"]
	var built := []
	for span: Dictionary in compiled.spans:
		var index := flex_span_ids.find(str(span.span_id))
		if index >= 0:
			built.resize(maxi(built.size(), index + 1))
			built[index] = float(span.duration_s)
	var matches := built.size() == accepted.size()
	for index in mini(built.size(), accepted.size()):
		matches = matches and absf(float(built[index]) - float(accepted[index])) <= 0.000000001
	_expect(matches, "seed %d builds its prefix from the accepted closure %s, not %s"
		% [seed_value, str(accepted), str(built)])


func _test_untargeted_prefix_capability_is_unchanged() -> void:
	for side in [-1, 1]:
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(var_to_bytes(RideProgram.terrain_story_capability(side)))
		_expect(context.finish().hex_encode() == PREFIX_CAPABILITY_DIGEST[side],
			"the untargeted station_side %d capability still hashes to its pinned digest" % side)


func _test_prefix_closure_solve_targets_todays_geometry() -> void:
	var untargeted := RideProgram.terrain_story_capability(1)
	if not _expect(untargeted.get("ok", false), "the untargeted prefix capability builds"):
		return
	var target := _closure_target(untargeted, 1, PREFIX_RECORD_AIM_BAND_MPS)
	var solved := RideProgram.terrain_story_capability(1, {}, target)
	if not _expect(solved.get("ok", false),
			"the prefix closes on today's own geometry: %s" % str(solved.get("failure", {}))):
		return
	_expect_closure_report(solved.get("closure_plan", {}), "today's geometry")
	_expect(absf(float(solved.dive_footprint.outward_delta_m)
			- float(untargeted.dive_footprint.outward_delta_m))
			<= float(RidePrefixSolve.PREFIX_FINE_TOLERANCES[0]),
		"closing on today's own bands leaves the published footprint where it was")


func _test_prefix_closure_solve_moves_the_record_handoff() -> void:
	var untargeted := RideProgram.terrain_story_capability(1)
	if not _expect(untargeted.get("ok", false), "the untargeted prefix capability builds"):
		return
	var target := _closure_target(untargeted, 1, PREFIX_DISPLACED_RECORD_BAND_MPS,
		PREFIX_DISPLACED_SPAN_AIM_TOLERANCE_M, PREFIX_DISPLACED_SUMMIT_AIM_TOLERANCE_M)
	var solved := {}
	for side in [-1, 1]:
		solved[side] = RideProgram.terrain_story_capability(side, {}, target)
		_expect(solved[side].get("ok", false),
			"station_side %d closes its prefix on a displaced record band: %s"
			% [side, str(solved[side].get("failure", {}))])
	if not solved[-1].get("ok", false) or not solved[1].get("ok", false):
		return
	var report: Dictionary = solved[1].get("closure_plan", {})
	_expect_closure_report(report, "displaced record band")
	var left: Array = solved[-1].get("closure_plan", {}).get("accepted_values", [])
	var right: Array = report.get("accepted_values", [])
	var identical := left.size() == RidePrefixSolve.PREFIX_CONTROL_IDS.size() \
		and right.size() == RidePrefixSolve.PREFIX_CONTROL_IDS.size()
	for index in mini(left.size(), right.size()):
		identical = identical and absf(float(left[index]) - float(right[index])) <= 0.000000001
	_expect(identical, "both hands solve to one control vector to 1e-9: %s against %s"
		% [str(left), str(right)])
	var a: Dictionary = solved[-1].role_13_entry
	var b: Dictionary = solved[1].role_13_entry
	_expect(absf(a.offset_m.x - b.offset_m.x) <= 0.05
		and absf(a.offset_m.y - b.offset_m.y) <= 0.05
		and absf(a.offset_m.z + b.offset_m.z) <= 0.05
		and absf(float(solved[-1].dive_footprint.outward_delta_m)
			- float(solved[1].dive_footprint.outward_delta_m)) <= 0.05,
		"the solved footprint keeps the 0.05 m hand mirror")
	var fine: Array = report.get("fine_observation", [])
	var record_mps: float = float(fine[3]) \
		if fine.size() == RidePrefixSolve.PREFIX_RESIDUAL_IDS.size() else NAN
	_expect(int(report.get("unique_evaluations", 0)) > 1
		and record_mps >= PREFIX_DISPLACED_RECORD_BAND_MPS.x
			- float(RidePrefixSolve.PREFIX_FINE_TOLERANCES[3])
		and record_mps <= PREFIX_DISPLACED_RECORD_BAND_MPS.y
			+ float(RidePrefixSolve.PREFIX_FINE_TOLERANCES[3]),
		"the solve spends evaluations to move the record handoff to %.3f m/s" % record_mps)


func _test_infeasible_prefix_closure_is_structured() -> void:
	var untargeted := RideProgram.terrain_story_capability(1)
	if not _expect(untargeted.get("ok", false), "the untargeted prefix capability builds"):
		return
	var target := _closure_target(untargeted, 1, PREFIX_RECORD_AIM_BAND_MPS)
	target["summit_rise_m"] = Vector2(600.0, 620.0)
	var refused := RideProgram.terrain_story_capability(1, {}, target)
	_expect(not refused.get("ok", true),
		"a summit rise no climb can reach refuses the prefix instead of approximating it")
	var failure: Dictionary = refused.get("failure", {})
	_expect(failure.get("stage", "") == "prefix-closure",
		"the refusal names the prefix-closure stage: %s" % str(failure))
	_expect(failure.has("accepted_values") and failure.has("target_error")
		and failure.has("margins") and failure.has("solver_status"),
		"the refusal carries its accepted values, residuals and margins: %s" % str(failure))
	_expect(int(failure.get("evaluation_count", -1)) >= 1
		and int(failure.get("evaluation_count", -1)) <= RidePrefixSolve.MAX_PREFIX_EVALUATIONS,
		"the refusal spends no more than the derived evaluation cap")
	_expect(not _contains_fallback_or_repair_field(refused),
		"the refused prefix offers no fallback or repair field")


## Every other closure test's target carries the default `outward_local` (the station's own
## outward, already a unit axis), so `_solve_prefix_closure`'s `axis = axis.normalized()` line
## never runs on anything but a no-op. This one supplies a rotated, non-unit axis instead -
## 30 degrees off outward in the horizontal plane, length 1.7 - and still expects convergence,
## so the normalization path is actually exercised.
func _test_prefix_closure_solve_accepts_non_axis_aligned_outward_local() -> void:
	var untargeted := RideProgram.terrain_story_capability(1)
	if not _expect(untargeted.get("ok", false), "the untargeted prefix capability builds"):
		return
	var raw_axis := Vector2(sin(deg_to_rad(30.0)), cos(deg_to_rad(30.0))) * 1.7
	var target := _closure_target_on_axis(untargeted, raw_axis, PREFIX_RECORD_AIM_BAND_MPS)
	var solved := RideProgram.terrain_story_capability(1, {}, target)
	if not _expect(solved.get("ok", false),
			"the prefix closes on a rotated, non-unit outward_local axis: %s"
			% str(solved.get("failure", {}))):
		return
	_expect_closure_report(solved.get("closure_plan", {}), "rotated outward_local")


## Every other closure test targets `story = {}` (the canonical undrawn recipe). This one builds
## the story the way `generator.gd`'s `_plan` does in production - `sequence`/`targets` straight
## from `RidePlanner.resolve` - and asserts the closure solve still converges within the same
## fleet budget on a real drawn story, not just the canonical one.
func _test_prefix_closure_solve_converges_on_a_drawn_story() -> void:
	var decisions := RidePlanner.resolve(42)
	var story := {"sequence": decisions.sequence, "targets": decisions.targets}
	var untargeted := RideProgram.terrain_story_capability(1, story)
	if not _expect(untargeted.get("ok", false), "the seed 42 drawn-story prefix capability builds"):
		return
	var target := _closure_target(untargeted, 1, PREFIX_RECORD_AIM_BAND_MPS)
	var solved := RideProgram.terrain_story_capability(1, story, target)
	if not _expect(solved.get("ok", false),
			"the seed 42 drawn story closes within the same budget: %s"
			% str(solved.get("failure", {}))):
		return
	_expect_closure_report(solved.get("closure_plan", {}), "seed 42 drawn story")


## One target serves both hands: every control is a duration and the aim axis is the station's
## own outward, so the mirrored prefix measures the same four quantities. Deliberately omits
## `outward_local` so each hand falls back to its own mirrored default axis inside
## `_solve_prefix_closure` - do not add it here, that is what lets one target serve both `side`
## values in `_test_prefix_closure_solve_moves_the_record_handoff`.
func _closure_target(capability: Dictionary, side: int, record_band: Vector2,
	span_tolerance_m: float = PREFIX_SPAN_AIM_TOLERANCE_M,
	summit_tolerance_m: float = PREFIX_SUMMIT_AIM_TOLERANCE_M
) -> Dictionary:
	var footprint: Dictionary = capability.dive_footprint
	var entry: Vector3 = capability.role_13_entry.offset_m
	var dive_exit: Vector3 = footprint.dive_exit_offset_m
	var tunnel_exit: Vector3 = footprint.tunnel_exit_offset_m
	var axis := Vector2(0.0, float(side))
	var dive_span := Vector2(dive_exit.x - entry.x, dive_exit.z - entry.z).dot(axis)
	var tunnel_span := Vector2(tunnel_exit.x - dive_exit.x, tunnel_exit.z - dive_exit.z).dot(axis)
	return {
		"dive_edge_span_m": Vector2(dive_span - span_tolerance_m, dive_span + span_tolerance_m),
		"tunnel_edge_span_m": Vector2(tunnel_span - span_tolerance_m,
			tunnel_span + span_tolerance_m),
		"summit_rise_m": Vector2(entry.y - summit_tolerance_m, entry.y + summit_tolerance_m),
		"record_exit_speed_mps": record_band,
		"dive_arc_m": PREFIX_ARC_AIM_BAND_M,
	}


## Single-sided only (unlike `_closure_target`): builds a target around an explicit, possibly
## non-unit, non-axis-aligned outward axis, normalized the same way `_solve_prefix_closure`
## normalizes it, so the aim bands are built around the axis the solve will actually project onto.
func _closure_target_on_axis(capability: Dictionary, raw_axis: Vector2, record_band: Vector2,
	span_tolerance_m: float = PREFIX_SPAN_AIM_TOLERANCE_M,
	summit_tolerance_m: float = PREFIX_SUMMIT_AIM_TOLERANCE_M
) -> Dictionary:
	var footprint: Dictionary = capability.dive_footprint
	var entry: Vector3 = capability.role_13_entry.offset_m
	var dive_exit: Vector3 = footprint.dive_exit_offset_m
	var tunnel_exit: Vector3 = footprint.tunnel_exit_offset_m
	var axis := raw_axis.normalized()
	var dive_span := Vector2(dive_exit.x - entry.x, dive_exit.z - entry.z).dot(axis)
	var tunnel_span := Vector2(tunnel_exit.x - dive_exit.x, tunnel_exit.z - dive_exit.z).dot(axis)
	return {
		"outward_local": raw_axis,
		"dive_edge_span_m": Vector2(dive_span - span_tolerance_m, dive_span + span_tolerance_m),
		"tunnel_edge_span_m": Vector2(tunnel_span - span_tolerance_m,
			tunnel_span + span_tolerance_m),
		"summit_rise_m": Vector2(entry.y - summit_tolerance_m, entry.y + summit_tolerance_m),
		"record_exit_speed_mps": record_band,
		"dive_arc_m": PREFIX_ARC_AIM_BAND_M,
	}


func _expect_closure_report(report: Dictionary, label: String) -> void:
	_expect(RidePrefixSolve.MAX_PREFIX_EVALUATIONS == 105,
		"the prefix evaluation cap is the derived 105, not %d"
		% RidePrefixSolve.MAX_PREFIX_EVALUATIONS)
	var evaluations := int(report.get("unique_evaluations", -1))
	var allowance := int(0.6 * RidePrefixSolve.MAX_PREFIX_EVALUATIONS)
	print("prefix closure (%s): %d evaluations, status %s, controls %s, fine %s" % [label,
		evaluations, str(report.get("solver_status", "missing")),
		str(report.get("accepted_values", [])), str(report.get("fine_observation", []))])
	_expect(report.get("solver_status", "") == "converged" and evaluations >= 1
		and evaluations <= allowance
		and report.get("max_unique_evaluations") == RidePrefixSolve.MAX_PREFIX_EVALUATIONS,
		"the %s closure converges in %d evaluations, over the %d fleet allowance"
		% [label, evaluations, allowance])
	var values: Array = report.get("accepted_values", [])
	var inside := values.size() == RidePrefixSolve.PREFIX_CONTROL_IDS.size()
	for index in values.size():
		var bound: Array = RidePrefixSolve.PREFIX_CONTROL_BOUNDS[index]
		inside = inside and float(values[index]) >= float(bound[0]) \
			and float(values[index]) <= float(bound[1])
	_expect(inside, "every %s control stays inside its declared bounds: %s" % [label, str(values)])
	var coarse: Array = report.get("coarse_observation", [])
	var fine: Array = report.get("fine_observation", [])
	var agrees := coarse.size() == RidePrefixSolve.PREFIX_RESIDUAL_IDS.size() \
		and fine.size() == RidePrefixSolve.PREFIX_RESIDUAL_IDS.size()
	for index in mini(coarse.size(), fine.size()):
		agrees = agrees and absf(float(coarse[index]) - float(fine[index])) \
			<= float(RidePrefixSolve.PREFIX_FINE_TOLERANCES[index])
	_expect(agrees, "the %s closure reproduces at the production step: %s against %s"
		% [label, str(coarse), str(fine)])


func _compile(layout: Dictionary) -> Dictionary:
	return RideProgram.compile(_plan(layout), {
		"position_m": layout.station_position_m,
		"tangent": layout.station_tangent,
		"rider_up": layout.station_up,
		"speed_mps": 6.0,
		"distance_m": 0.0,
		"time_s": 0.0,
	})


func _plan(layout: Dictionary) -> Dictionary:
	var forward: Vector3 = layout.station_tangent.normalized()
	var up: Vector3 = layout.station_up.normalized()
	var along := forward
	var inward := up.cross(along).normalized()
	var right := forward.cross(up).normalized()
	var corridor: Dictionary = layout.reserved_corridor
	# The station-local fixture uses one certified production draw rather than the empty target map
	# that predates per-seed return-height authority.
	var targets: Dictionary = RidePlanner.resolve(42).targets.duplicate(true)
	return {"schema_version": 1, "preset_id": "material-v1",
		"decisions": {"station_side": 1, "station_along_m": 80.0,
			"dive_exit_apron_fraction": 0.33, "targets": targets},
		"terrain_frame": {"apron_origin_m": layout.station_position_m - along * 80.0,
			"inward": inward, "along": along, "up": up, "right": right,
			"shelf_height_m": 275.0, "planning": {
		"capability_id": "material-v1-prefix-r12@8", "planning_integrations": 1,
				"station_edge_distance_m": -800.0,
				"station_opener_maximum_edge_m": -100.0,
				"sampled_station_opener_points": 100,
				"shelf_edge_distance_m": 300.0, "dive_entry_edge_m": 320.0,
				"summit_track_agl_m": 20.0,
				"scale": {"route_vertical_envelope_m": Vector2(290.0, 305.0),
					"dive_drop_m": Vector2(240.0, 250.0),
					"camel_prominence_m": Vector2(245.0, 255.0)}}},
		"station": {"position_m": layout.station_position_m, "tangent": forward, "up": up},
		"corridor": {"approach_length_m": float(corridor.minimum_length_m),
			"capture_length_m": 80.0, "brake_length_m": 150.0,
			"half_width_m": float(layout.get("capture_half_width_m", CAPTURE_HALF_WIDTH_M)),
			"half_height_m": float(layout.get("capture_half_height_m", CAPTURE_HALF_HEIGHT_M)),
			"entry_speed_mps": Vector2(70.0, 80.0)},
		"route_length_m": Vector2(7800.0, 8200.0),
		"roles": RideGenerator._material_roles()}


func _layout() -> Dictionary:
	return {
		"station_position_m": Vector3.ZERO,
		"station_tangent": Vector3.RIGHT,
		"station_up": Vector3.UP,
		"reserved_corridor": {"minimum_length_m": 230.0,
			"capture_length_m": 80.0, "brake_length_m": 150.0,
			"entry_speed_mps": Vector2(70.0, 80.0)},
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


func _terminal_program_parts(spans: Array) -> Dictionary:
	var moving_spans := []
	var station_spans := []
	var station_started := false
	var active_duration := 0.0
	var hold_duration := 0.0
	var peak_g := 0.0
	for span: Dictionary in spans:
		var mode := str(span.get("mode", ""))
		if mode == "station":
			station_started = true
			station_spans.append(span)
			if not _profile_is_nonpositive(span.get("drive_g", {})):
				return {"ok": false}
		elif mode == "moving" and not station_started:
			moving_spans.append(span)
			active_duration += float(span.get("duration_s", 0.0))
			var active := false
			for u in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var drive: float = Motion.profile_sample(span.get("drive_g", {}), u).x
				if drive > 0.000001:
					return {"ok": false}
				active = active or drive < -0.000001
				peak_g = maxf(peak_g, -drive)
			if not active:
				return {"ok": false}
			if span.get("drive_g", {}).get("kind", "") == "constant":
				hold_duration += float(span.get("duration_s", 0.0))
		else:
			return {"ok": false}
	return {"ok": not moving_spans.is_empty() and not station_spans.is_empty()
			and absf(active_duration - hold_duration - 1.2) <= 0.000001,
		"moving_spans": moving_spans, "station_spans": station_spans,
		"active_duration_s": active_duration, "hold_duration_s": hold_duration,
		"peak_g": peak_g}


func _independent_brake_observation(
	start: Dictionary, moving_spans: Array, moving_target: float, step_s: float
) -> Dictionary:
	var route := Motion.integrate(start, moving_spans, RideProgram._settings(step_s))
	if not route.get("ok", false):
		return {"ok": false, "errors": route.get("errors", [])}
	var moving_distance: float = route.distance_m[-1] - float(start.distance_m)
	var speed: float = route.speed_mps[-1]
	return {"ok": true, "moving_distance_m": moving_distance,
		"moving_boundary_speed_mps": speed,
		"residuals": [moving_distance - moving_target, speed - 2.0]}


func _brake_report_observation_is_valid(reported: Variant, plan: Dictionary) -> bool:
	if not reported is Dictionary:
		return false
	var residuals: Variant = reported.get("residuals")
	var distance: Variant = reported.get("moving_distance_m")
	var speed: Variant = reported.get("moving_boundary_speed_mps")
	var remaining: Variant = plan.get("remaining_distance_m")
	var station: Variant = plan.get("station_distance_m")
	return residuals is Array and residuals.size() == 2 \
		and _finite_number(distance) and _finite_number(speed) and _finite_number(remaining) \
		and _finite_number(station) \
		and _residuals_are_within(residuals, [0.05, 0.0001]) \
		and float(residuals[0]) == float(distance) - (float(remaining) - float(station)) \
		and float(residuals[1]) == float(speed) - 2.0


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


func _return_and_terminal_drive_is_nonpositive(compiled: Dictionary) -> bool:
	var return_gesture := _compiled_gesture(compiled, "raceway-return")
	var terminal := _compiled_gesture(compiled, "brakes-station-capture")
	var spans: Array = compiled.get("spans", [])
	if return_gesture.is_empty() or terminal.is_empty():
		return false
	for index in range(int(return_gesture.first_span), int(terminal.last_span) + 1):
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
	var gesture := _compiled_gesture(compiled, "raceway-return")
	var terminal := _compiled_gesture(compiled, "brakes-station-capture")
	var roles: Array = gesture.get("role_windows", [])
	if terminal.is_empty() or int(gesture.get("last_span", -2)) + 1 \
			!= int(terminal.get("first_span", 0)):
		return false
	return _return_trajectory_is_material(
		_integrated_trajectory(compiled, layout), roles, layout)


func _return_trajectory_is_material(
	trajectory: Dictionary, roles: Array, layout: Dictionary
) -> bool:
	var role_ids := []
	for role: Dictionary in roles:
		role_ids.append(role.get("id", ""))
	if role_ids != ["turn-a", "height-airtime-a", "turn-b", "height-airtime-b"] \
			or not trajectory.get("ok", false):
		return false
	var bounds := _owned_span_bounds(trajectory.span_index,
		int(roles[0].first_span), int(roles[-1].last_span))
	var terminal_index := mini(bounds.y + 1, trajectory.position_m.size() - 1)
	for role_index in roles.size():
		var role: Dictionary = roles[role_index]
		var owned := _owned_span_bounds(trajectory.span_index,
			int(role.first_span), int(role.last_span))
		if owned.x < 0 or owned.y <= owned.x:
			return false
		if role_index % 2 == 0:
			var heading := _trajectory_heading_work(trajectory.tangent, owned)
			var cross_track := _trajectory_cross_track(
				trajectory.position_m, trajectory.tangent, owned)
			if heading < deg_to_rad(20.0) or heading > deg_to_rad(225.0) or cross_track < 25.0:
				print("return material turn %s: heading=%.3f deg cross=%.3f m"
					% [role.id, rad_to_deg(heading), cross_track])
				return false
		else:
			var apex := _maximum_trajectory_height(trajectory, owned)
			var nadir := _minimum_trajectory_height(trajectory, owned)
			var height: float = trajectory.position_m[apex].y - trajectory.position_m[nadir].y
			var unload_s := _linear_held_at_or_below(
				trajectory.time_s, trajectory.normal_g, owned, 0.5)
			if height < 35.0 or unload_s < 0.35:
				print("return material height %s: height=%.3f m unload=%.3f s"
					% [role.id, height, unload_s])
				return false
	var up: Vector3 = layout.station_up.normalized()
	var initial: float = 0.5 * float(trajectory.speed_mps[bounds.x]) ** 2 + Motion.G0 * (
		trajectory.position_m[bounds.x] - layout.station_position_m).dot(up)
	var previous := initial
	var minimum_speed: float = trajectory.speed_mps[bounds.x]
	for sample_index in range(bounds.x + 1, terminal_index + 1):
		if float(trajectory.drive_g[sample_index]) > 0.000001:
			return false
		minimum_speed = minf(minimum_speed, trajectory.speed_mps[sample_index])
		var energy: float = 0.5 * float(trajectory.speed_mps[sample_index]) ** 2 + Motion.G0 * (
			trajectory.position_m[sample_index] - layout.station_position_m).dot(up)
		if energy - previous > 0.05:
			return false
		previous = energy
	var length_m: float = trajectory.distance_m[terminal_index] - trajectory.distance_m[bounds.x]
	var station_forward: float = (trajectory.position_m[terminal_index] \
		- layout.station_position_m).dot(layout.station_tangent.normalized())
	var approach_length_m := float(layout.reserved_corridor.minimum_length_m)
	var accepted: bool = length_m >= 1100.0 and length_m <= 3000.0 and initial - previous >= 50.0 \
		and trajectory.speed_mps[bounds.x] - trajectory.speed_mps[terminal_index] >= 5.0 \
		and minimum_speed >= 45.0 and station_forward >= -approach_length_m \
		and station_forward <= -(approach_length_m - 45.0)
	if not accepted:
		print("return material terminal: length=%.3f energy_drop=%.3f speed=%.3f->%.3f min=%.3f forward=%.3f"
			% [length_m, initial - previous, trajectory.speed_mps[bounds.x],
				trajectory.speed_mps[terminal_index], minimum_speed, station_forward])
	return accepted


func _compiled_return_flow_is_continuous(compiled: Dictionary, layout: Dictionary) -> bool:
	var gesture := _compiled_gesture(compiled, "raceway-return")
	var trajectory := _integrated_trajectory(compiled, layout)
	if gesture.is_empty() or not trajectory.get("ok", false):
		return false
	var bounds := _owned_span_bounds(
		trajectory.span_index, int(gesture.first_span), int(gesture.last_span))
	return _return_flow_observation(
		trajectory, gesture.role_windows, bounds, layout.station_up.normalized()).ok


func _return_flow_observation(
	trajectory: Dictionary, roles: Array, bounds: Vector2i, station_up: Vector3
) -> Dictionary:
	var dead_run := 0.0
	var low_run := 0.0
	var longest_dead := 0.0
	var longest_low := 0.0
	var role_low := []
	role_low.resize(roles.size())
	role_low.fill(0.0)
	for index in range(bounds.x + 1, bounds.y + 1):
		var duration: float = trajectory.time_s[index] - trajectory.time_s[index - 1]
		var dead := _return_interval_is_inactive(trajectory, index, station_up,
			0.005, 0.005, deg_to_rad(0.5), deg_to_rad(0.1), 0.2)
		var low := _return_interval_is_inactive(trajectory, index, station_up,
			0.10, 0.05, deg_to_rad(5.0), deg_to_rad(1.0), 1.0)
		dead_run = dead_run + duration if dead else 0.0
		low_run = low_run + duration if low else 0.0
		longest_dead = maxf(longest_dead, dead_run)
		longest_low = maxf(longest_low, low_run)
		if low:
			var before_owner: int = trajectory.span_index[index - 1]
			var after_owner: int = trajectory.span_index[index]
			for role_index in roles.size():
				var role: Dictionary = roles[role_index]
				if (before_owner >= role.first_span and before_owner <= role.last_span) \
						or (after_owner >= role.first_span and after_owner <= role.last_span):
					role_low[role_index] += duration
	var accepted := longest_dead <= 0.25 and longest_low <= 0.60
	for duration in role_low:
		accepted = accepted and duration <= 0.75
	return {"ok": accepted, "dead_flat_s": longest_dead,
		"low_activity_s": longest_low, "role_low_activity_s": role_low}


func _return_interval_is_inactive(
	trajectory: Dictionary, index: int, station_up: Vector3,
	normal_tolerance: float, lateral_tolerance: float, roll_tolerance: float,
	heading_rate_limit: float, vertical_speed_limit: float
) -> bool:
	var duration: float = trajectory.time_s[index] - trajectory.time_s[index - 1]
	if duration <= 0.0:
		return false
	for sample_index in [index - 1, index]:
		if absf(float(trajectory.normal_g[sample_index]) - 1.0) > normal_tolerance \
				or absf(float(trajectory.lateral_g[sample_index])) > lateral_tolerance \
				or absf(float(trajectory.roll_rate_rad_s[sample_index])) > roll_tolerance:
			return false
	var before := Vector2(trajectory.tangent[index - 1].x, trajectory.tangent[index - 1].z)
	var after := Vector2(trajectory.tangent[index].x, trajectory.tangent[index].z)
	if before.length_squared() <= 0.000001 or after.length_squared() <= 0.000001:
		return false
	var heading_rate := acos(clampf(before.normalized().dot(after.normalized()), -1.0, 1.0)) \
		/ duration
	var vertical_speed := absf((trajectory.position_m[index] \
		- trajectory.position_m[index - 1]).dot(station_up)) / duration
	return heading_rate <= heading_rate_limit and vertical_speed <= vertical_speed_limit


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
		and plan.get("max_unique_evaluations", -1) == 40 \
		and _plan_evidence_is_within_tolerance(plan)


func _plan_evidence_is_within_tolerance(plan: Dictionary) -> bool:
	var ids: Variant = plan.get("residual_ids")
	var tolerances: Variant = plan.get("residual_tolerances")
	var coarse_tolerances: Variant = plan.get("coarse_residual_tolerances")
	var margins: Variant = plan.get("margins")
	if not ids is Array or ids.is_empty() or not tolerances is Array \
			or tolerances.size() != ids.size() or not margins is Dictionary \
			or not coarse_tolerances is Array or coarse_tolerances.size() != ids.size() \
			or margins.is_empty():
		return false
	for tolerance in tolerances:
		if not _positive_finite(tolerance):
			return false
	for field in ["residuals", "fine_residuals", "production_residuals"]:
		var residuals: Variant = plan.get(field)
		var field_tolerances: Array = coarse_tolerances if field == "residuals" else tolerances
		if not residuals is Array or residuals.size() != ids.size():
			return false
		for index in residuals.size():
			if not _finite_number(residuals[index]) \
					or absf(float(residuals[index])) > float(field_tolerances[index]):
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


func _near_future_story_is_physical(compiled: Dictionary, layout: Dictionary) -> bool:
	var trajectory := _integrated_trajectory(compiled, layout)
	if not trajectory.get("ok", false):
		return false
	var launch := _compiled_gesture(compiled, "station-launch")
	var act_one := _compiled_gesture(compiled, "act-one")
	var climb := _compiled_gesture(compiled, "escarpment-climb")
	var cliff := _compiled_gesture(compiled, "clifftop-suspense")
	var dive := _compiled_gesture(compiled, "cliff-dive")
	var lsm3 := _compiled_gesture(compiled, "tunnel-lsm3")
	var camel := _compiled_gesture(compiled, "marquee-camelback")
	var lsm2 := _compiled_role(climb, "lsm2")
	var slow_crest := _compiled_role(cliff, "slow-crest")
	var rim := _compiled_role(cliff, "outward-rim")
	if launch.is_empty() or act_one.is_empty() or climb.is_empty() or cliff.is_empty() \
			or dive.is_empty() or lsm3.is_empty() or camel.is_empty() \
			or lsm2.is_empty() or slow_crest.is_empty() or rim.is_empty():
		return false
	var climb_bounds := _trajectory_span_bounds(
		trajectory, int(climb.first_span), int(cliff.last_span))
	var cliff_bounds := _trajectory_span_bounds(
		trajectory, int(lsm2.last_span) + 1, int(cliff.last_span))
	var dive_bounds := _trajectory_span_bounds(
		trajectory, int(dive.first_span), int(dive.last_span))
	var camel_bounds := _trajectory_span_bounds(
		trajectory, int(camel.first_span), int(camel.last_span))
	var slow_bounds := _trajectory_span_bounds(
		trajectory, int(slow_crest.first_span), int(slow_crest.last_span))
	var rim_bounds := _trajectory_span_bounds(
		trajectory, int(rim.first_span), int(rim.last_span))
	var role_spans: Dictionary = compiled.get("role_spans", {})
	for role_id in ["act-one-immelmann", "act-one-cutback", "act-one-loop"]:
		if not role_spans.get(role_id) is Vector2i:
			return false
	var immel_spans: Vector2i = role_spans["act-one-immelmann"]
	var cutback_spans: Vector2i = role_spans["act-one-cutback"]
	var loop_spans: Vector2i = role_spans["act-one-loop"]
	var immel_bounds := _trajectory_span_bounds(trajectory, immel_spans.x, immel_spans.y)
	var cutback_bounds := _trajectory_span_bounds(trajectory, cutback_spans.x, cutback_spans.y)
	var loop_bounds := _trajectory_span_bounds(trajectory, loop_spans.x, loop_spans.y)
	var cliff_apex := _maximum_trajectory_height(trajectory, cliff_bounds)
	var camel_apex := _maximum_trajectory_height(trajectory, camel_bounds)
	var points := [
		[_trajectory_span_bounds(trajectory, int(launch.first_span), int(launch.last_span)).y,
			-5.0, 5.0, 75.0, 78.0, 0.05],
		[_trajectory_span_bounds(trajectory, int(act_one.first_span), int(act_one.last_span)).y,
			null, null, 40.0, 70.0, 0.18],
		[_trajectory_span_bounds(trajectory, int(lsm2.first_span), int(lsm2.last_span)).y,
			null, null, 26.0, 34.0, 0.5],
		[cliff_apex, null, null, 5.0, 22.0, 0.22],
		[dive_bounds.y, null, null, 66.0, 78.0, 0.22],
		[_trajectory_span_bounds(trajectory, int(lsm3.first_span), int(lsm3.last_span)).y,
			null, null, 90.0, 98.0, 0.16],
		[camel_apex, null, null, 42.0, 62.0, 0.12],
		[camel_bounds.y, null, null, 78.0, 92.0, 0.18],
	]
	for point in points:
		var index: int = point[0]
		var height: float = (trajectory.position_m[index] - layout.station_position_m).dot(
			layout.station_up.normalized())
		if (point[1] != null and (height < point[1] or height > point[2])) \
				or trajectory.speed_mps[index] < point[3] or trajectory.speed_mps[index] > point[4] \
				or absf(trajectory.tangent[index].dot(layout.station_up.normalized())) > point[5]:
			print("near-future point: height=%.3f speed=%.3f pitch_dot=%.6f bounds=%s"
				% [height, trajectory.speed_mps[index],
					absf(trajectory.tangent[index].dot(layout.station_up.normalized())), str(point)])
			return false
	var return_entry: int = camel_bounds.y
	var return_height: float = (trajectory.position_m[return_entry] \
		- layout.station_position_m).dot(layout.station_up.normalized())
	if 0.5 * float(trajectory.speed_mps[return_entry]) ** 2 \
			+ Motion.G0 * return_height - 0.5 <= 0.0:
		return false
	var rim_bank := PackedFloat64Array()
	rim_bank.resize(trajectory.time_s.size())
	var rim_lateral := 0.0
	for index in range(rim_bounds.x, rim_bounds.y + 1):
		rim_bank[index] = -_trajectory_bank(trajectory.tangent[index], trajectory.rider_up[index])
		rim_lateral = maxf(rim_lateral, absf(float(trajectory.lateral_g[index])))
	var rim_exit: int = rim_bounds.y
	var rim_exit_bank := _trajectory_bank(
		trajectory.tangent[rim_exit], trajectory.rider_up[rim_exit])
	var rim_exit_pitch := asin(clampf(trajectory.tangent[rim_exit].y, -1.0, 1.0))
	var rim_duration: float = trajectory.time_s[rim_bounds.y] - trajectory.time_s[rim_bounds.x]
	var rim_distance: float = trajectory.distance_m[rim_bounds.y] - trajectory.distance_m[rim_bounds.x]
	var dive_minimum_tangent: float = trajectory.tangent[dive_bounds.x].y
	var dive_minimum_normal: float = trajectory.normal_g[dive_bounds.x]
	var dive_maximum_normal: float = trajectory.normal_g[dive_bounds.x]
	var dive_maximum_step := -INF
	for index in range(dive_bounds.x + 1, dive_bounds.y + 1):
		dive_minimum_tangent = minf(dive_minimum_tangent, trajectory.tangent[index].y)
		dive_minimum_normal = minf(dive_minimum_normal, trajectory.normal_g[index])
		dive_maximum_normal = maxf(dive_maximum_normal, trajectory.normal_g[index])
		dive_maximum_step = maxf(dive_maximum_step,
			trajectory.position_m[index].y - trajectory.position_m[index - 1].y)
	var camel_start: Vector3 = trajectory.position_m[camel_bounds.x]
	var camel_end: Vector3 = trajectory.position_m[camel_bounds.y]
	var camel_prominence: float = trajectory.position_m[camel_apex].y \
		- maxf(camel_start.y, camel_end.y)
	var camel_width := Vector2(camel_end.x - camel_start.x,
		camel_end.z - camel_start.z).length()
	var slow_held := _linear_held_at_or_below(
		trajectory.time_s, trajectory.speed_mps, slow_bounds, 22.0)
	var immel_height := _trajectory_vertical_span(trajectory.position_m, immel_bounds)
	var loop_height := _trajectory_vertical_span(trajectory.position_m, loop_bounds)
	var cutback_height := _trajectory_vertical_span(trajectory.position_m, cutback_bounds)
	var climb_rise: float = trajectory.position_m[cliff_apex].y \
		- trajectory.position_m[climb_bounds.x].y
	var dive_drop: float = trajectory.position_m[dive_bounds.x].y \
		- trajectory.position_m[dive_bounds.y].y
	var route_envelope := _trajectory_vertical_span(trajectory.position_m,
		Vector2i(0, trajectory.position_m.size() - 1))
	var accepted: bool = immel_height >= 94.9 and immel_height <= 109.5 \
		and loop_height >= 94.0 and loop_height <= 100.0 \
		and cutback_height >= 40.0 \
		and slow_held >= 2.7 and slow_held <= 4.2 \
		and climb_rise >= 200.0 and climb_rise <= 225.0 \
		and _trajectory_heading_change(trajectory.tangent, rim_bounds) >= deg_to_rad(90.0) \
		and _trajectory_heading_change(trajectory.tangent, rim_bounds) <= deg_to_rad(115.0) \
		and _trajectory_cross_track(trajectory.position_m, trajectory.tangent, rim_bounds) >= 3.0 \
		and _trajectory_maximum_bank(
			trajectory.tangent, trajectory.rider_up, rim_bounds) >= deg_to_rad(20.0) \
		and _linear_held_at_or_below(
			trajectory.time_s, rim_bank, rim_bounds, -deg_to_rad(40.0)) >= 1.0 \
		and rim_lateral <= 0.050001 and rim_duration >= 3.5 and rim_duration <= 6.0 \
		and rim_distance >= 40.0 and rim_distance <= 160.0 \
		and rim_exit_bank <= deg_to_rad(2.0) \
		and rim_exit_pitch >= deg_to_rad(2.0) \
		and rim_exit_pitch <= deg_to_rad(6.0) \
		and trajectory.rider_up[rim_exit].dot(Vector3.UP) >= 0.99 \
		and dive_drop >= 238.0 and dive_drop <= 250.0 \
		and dive_minimum_tangent <= -sin(deg_to_rad(75.0)) and dive_maximum_step <= 0.05 \
		and dive_minimum_normal >= -1.300001 and dive_maximum_normal <= 5.000001 \
		and trajectory.speed_mps[_trajectory_span_bounds(
			trajectory, int(lsm3.first_span), int(lsm3.last_span)).y] > 90.278 \
		and camel_prominence >= 245.0 and camel_prominence <= 255.0 \
		and camel_width / camel_prominence >= 3.1 and camel_width / camel_prominence <= 3.9 \
		and route_envelope >= 290.0 and route_envelope <= 305.0 \
		and _linear_held_at_or_below(
			trajectory.time_s, trajectory.normal_g, camel_bounds, 0.0) >= 4.0
	if not accepted:
		print("near-future shape: immel=%.3f loop=%.3f cutback=%.3f slow=%.3f climb=%.3f rim_heading=%.3f rim_cross=%.3f rim_bank=%.3f rim_hold=%.3f rim_lateral=%.6f rim_duration=%.3f rim_distance=%.3f rim_exit_bank=%.3f rim_exit_pitch=%.3f dive_drop=%.3f dive_min_tangent=%.6f dive_normal=%.3f..%.3f dive_step=%.6f tunnel_speed=%.3f camel=%.3f ratio=%.3f envelope=%.3f camel_unload=%.3f"
			% [immel_height, loop_height, cutback_height, slow_held, climb_rise,
				rad_to_deg(_trajectory_heading_change(trajectory.tangent, rim_bounds)),
				_trajectory_cross_track(trajectory.position_m, trajectory.tangent, rim_bounds),
				rad_to_deg(_trajectory_maximum_bank(trajectory.tangent, trajectory.rider_up, rim_bounds)),
				_linear_held_at_or_below(trajectory.time_s, rim_bank, rim_bounds, -deg_to_rad(40.0)),
				rim_lateral, rim_duration, rim_distance, rad_to_deg(rim_exit_bank),
				rad_to_deg(rim_exit_pitch), dive_drop, dive_minimum_tangent, dive_minimum_normal,
				dive_maximum_normal, dive_maximum_step,
				trajectory.speed_mps[_trajectory_span_bounds(
					trajectory, int(lsm3.first_span), int(lsm3.last_span)).y],
				camel_prominence, camel_width / camel_prominence, route_envelope,
				_linear_held_at_or_below(trajectory.time_s, trajectory.normal_g, camel_bounds, 0.0)])
	return accepted


func _trajectory_vertical_span(positions: PackedVector3Array, bounds: Vector2i) -> float:
	var low := INF
	var high := -INF
	for index in range(bounds.x, bounds.y + 1):
		low = minf(low, positions[index].y)
		high = maxf(high, positions[index].y)
	return high - low


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


func _minimum_trajectory_height(trajectory: Dictionary, bounds: Vector2i) -> int:
	var result := bounds.x
	for index in range(bounds.x + 1, bounds.y + 1):
		if trajectory.position_m[index].y < trajectory.position_m[result].y:
			result = index
	return result
func _trajectory_heading_change(tangents: PackedVector3Array, bounds: Vector2i) -> float:
	var first := Vector2(tangents[bounds.x].x, tangents[bounds.x].z).normalized()
	var last := Vector2(tangents[bounds.y].x, tangents[bounds.y].z).normalized()
	return acos(clampf(first.dot(last), -1.0, 1.0))


func _trajectory_heading_work(tangents: PackedVector3Array, bounds: Vector2i) -> float:
	var result := 0.0
	var previous := Vector2(tangents[bounds.x].x, tangents[bounds.x].z).normalized()
	for index in range(bounds.x + 1, bounds.y + 1):
		var current := Vector2(tangents[index].x, tangents[index].z).normalized()
		result += acos(clampf(previous.dot(current), -1.0, 1.0))
		previous = current
	return result


func _trajectory_cross_track(
	positions: PackedVector3Array, tangents: PackedVector3Array, bounds: Vector2i
) -> float:
	var forward := Vector2(tangents[bounds.x].x, tangents[bounds.x].z).normalized()
	var right := Vector2(-forward.y, forward.x)
	var low := INF
	var high := -INF
	for index in range(bounds.x, bounds.y + 1):
		var point := Vector2(positions[index].x - positions[bounds.x].x,
			positions[index].z - positions[bounds.x].z).dot(right)
		low = minf(low, point)
		high = maxf(high, point)
	return high - low


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
	var normalized_a := a.normalized()
	var normalized_b := b.normalized()
	return atan2(normalized_a.cross(normalized_b).length(),
		clampf(normalized_a.dot(normalized_b), -1.0, 1.0))


func _test_material_role_span_ownership_is_total() -> void:
	var orphan := RideProgram.material_role_spans([
		{"span_id": "launch/ramp"}, {"span_id": "mystery/thing"},
	])
	_expect(not orphan.get("ok", true),
		"a span owned by no material role fails role-span ownership")
	_expect(_reports(orphan, "mystery/thing"),
		"the ownership failure names the unowned span: %s" % str(orphan.get("errors", [])))
	var incomplete := RideProgram.material_role_spans([{"span_id": "launch/ramp"}])
	_expect(not incomplete.get("ok", true),
		"a program that authors only one role fails role-span ownership")
	_expect(_reports(incomplete, "return-turn-a"),
		"the ownership failure names an unauthored role: %s" % str(incomplete.get("errors", [])))
	var split := RideProgram.material_role_spans([
		{"span_id": "launch/ramp"}, {"span_id": "drop/core"}, {"span_id": "launch/core"},
	])
	_expect(not split.get("ok", true),
		"a material role split into non-contiguous span blocks fails role-span ownership")


func _reports(result: Dictionary, fragment: String) -> bool:
	for error in result.get("errors", []):
		if str(error).contains(fragment):
			return true
	return false


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
