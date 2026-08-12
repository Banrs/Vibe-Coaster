extends SceneTree

const Motion := preload("res://motion.gd")
const EPS := 0.000001

var _errors := PackedStringArray()


func _initialize() -> void:
	_test_c2_profiles()
	_test_profile_peak_abs_derivative()
	_test_resistance_law()
	_test_constant_rolling_coast()
	_test_quadratic_drag_coast()
	_test_straight_coast()
	_test_straight_launch()
	_test_pitched_gravity_cancellation()
	_test_zero_gravity_circle()
	_test_banked_lateral_curvature()
	_test_roll_only_frame_twist()
	_test_low_speed_station_handoff()
	_test_exact_span_boundary_splitting()
	_test_boundary_roundoff_does_not_emit_a_sliver()
	_test_degenerate_frame_rejection()
	_test_rk4_step_halving()
	_test_dense_output_native_identity()
	_test_dense_output_distance_and_defect()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _test_c2_profiles() -> void:
	var held := Motion.constant(4.0)
	_expect_vector(Motion.profile_sample(held, 0.37), Vector3(4.0, 0.0, 0.0),
		"constant profile has its value and zero derivatives")
	var transition := Motion.quintic(2.0, 5.0)
	_expect_vector(Motion.profile_sample(transition, 0.0), Vector3(2.0, 0.0, 0.0),
		"quintic starts with exact value and zero first/second derivatives")
	_expect_vector(Motion.profile_sample(transition, 1.0), Vector3(5.0, 0.0, 0.0),
		"quintic ends with exact value and zero first/second derivatives")
	_expect_vector(Motion.profile_sample(transition, 0.25),
		Vector3(2.310546875, 3.1640625, 16.875),
		"quintic interior value and analytic first/second derivatives are exact")
	var pulse := Motion.compact_pulse(3.0)
	_expect_vector(Motion.profile_sample(pulse, 0.0), Vector3.ZERO,
		"compact pulse has a zero C2 entry jet")
	_expect_vector(Motion.profile_sample(pulse, 1.0), Vector3.ZERO,
		"compact pulse has a zero C2 exit jet")
	_expect_close(Motion.profile_sample(pulse, 0.5).x, 3.0,
		"compact pulse reaches its authored amplitude")
	var span_record := Motion.span("immutable", 1.0, "moving", held, held, held, held)
	_expect(held.is_read_only() and transition.is_read_only() and pulse.is_read_only(),
		"profile records are immutable")
	_expect(span_record.is_read_only(), "span records are immutable")


func _test_profile_peak_abs_derivative() -> void:
	_expect_close(Motion.profile_peak_abs_derivative(Motion.constant(-4.0)), 0.0,
		"constant profile has zero peak derivative")
	_expect_close(Motion.profile_peak_abs_derivative(Motion.quintic(1.0, 5.2)), 7.875,
		"rising quintic reports its exact analytic peak derivative")
	_expect_close(Motion.profile_peak_abs_derivative(Motion.quintic(5.2, 1.0)), 7.875,
		"falling quintic has the same absolute peak derivative")
	_expect_close(Motion.profile_peak_abs_derivative(Motion.compact_pulse(3.0)),
		10.699182439179779, "positive compact pulse reports its exact analytic peak derivative")
	_expect_close(Motion.profile_peak_abs_derivative(Motion.compact_pulse(-3.0)),
		10.699182439179779, "negative compact pulse has the same absolute peak derivative")


func _test_resistance_law() -> void:
	var measured := Motion.resistance(20.0, 0.15, 0.002)
	_expect_vector(measured, Vector3(0.95, 0.08, 0.004),
		"resistance and analytic derivatives follow rolling plus quadratic drag")
	var stopped := Motion.resistance(0.0, 0.15, 0.002)
	_expect_vector(stopped, Vector3(0.15, 0.0, 0.004),
		"resistance is smooth and one-sided at zero forward speed")


func _test_constant_rolling_coast() -> void:
	var rolling := 0.2
	var duration := 2.0
	var initial_speed := 12.0
	var settings := _vacuum_settings(0.01)
	settings.rolling_mps2 = rolling
	var route := Motion.integrate(_initial(initial_speed), [
		_span("rolling-coast", duration, "moving", 1.0, 0.0, 0.0, 0.0),
	], settings)
	if not _expect_route(route, "constant rolling-resistance coast integrates"):
		return
	var expected_speed := initial_speed - rolling * duration
	var expected_distance := initial_speed * duration - 0.5 * rolling * duration * duration
	_expect_close(route.speed_mps[-1], expected_speed,
		"constant rolling resistance reduces speed linearly")
	_expect_close(route.position_m[-1].x, expected_distance,
		"constant rolling resistance gives the analytic coast position", 0.00005)
	_expect_close(0.5 * (initial_speed * initial_speed - route.speed_mps[-1] * route.speed_mps[-1]),
		rolling * route.distance_m[-1], "rolling work equals mechanical energy loss per unit mass")
	_expect_close(route.longitudinal_g[-1], -rolling / Motion.G0,
		"rolling loss appears in longitudinal proper g without gravity")


func _test_quadratic_drag_coast() -> void:
	var aero_per_m := 0.01
	var duration := 1.0
	var initial_speed := 10.0
	var settings := _vacuum_settings(0.01)
	settings.aero_per_m = aero_per_m
	var route := Motion.integrate(_initial(initial_speed), [
		_span("quadratic-coast", duration, "moving", 1.0, 0.0, 0.0, 0.0),
	], settings)
	if not _expect_route(route, "quadratic-drag coast integrates"):
		return
	var factor := 1.0 + aero_per_m * initial_speed * duration
	var expected_speed := initial_speed / factor
	var expected_distance := log(factor) / aero_per_m
	_expect_close(route.speed_mps[-1], expected_speed,
		"quadratic drag gives the analytic reciprocal speed decay")
	_expect_close(route.position_m[-1].x, expected_distance,
		"quadratic drag gives the analytic logarithmic coast position")
	_expect_close(route.distance_m[-1], expected_distance,
		"quadratic-drag distance matches the analytic position")
	_expect_close(route.longitudinal_g[-1], -aero_per_m * expected_speed * expected_speed / Motion.G0,
		"quadratic drag appears in longitudinal proper g")


func _test_straight_coast() -> void:
	var route := Motion.integrate(_initial(10.0), [
		_span("coast", 2.0, "moving", 1.0, 0.0, 0.0, 0.0),
	], _vacuum_settings(0.01))
	if not _expect_route(route, "straight coast integrates"):
		return
	_expect_vector(route.position_m[-1], Vector3(20.0, 0.0, 0.0),
		"straight coast advances at constant speed", 0.00005)
	_expect_close(route.speed_mps[-1], 10.0, "straight coast preserves speed")


func _test_straight_launch() -> void:
	var route := Motion.integrate(_initial(10.0), [
		_span("launch", 2.0, "moving", 1.0, 0.0, 1.0, 0.0),
	], _vacuum_settings(0.01))
	if not _expect_route(route, "straight launch integrates"):
		return
	_expect_close(route.speed_mps[-1], 10.0 + 2.0 * Motion.G0,
		"straight launch speed follows authored drive")
	_expect_close(route.position_m[-1].x, 20.0 + 2.0 * Motion.G0,
		"straight launch position follows constant acceleration", 0.00005)
	_expect_close(route.longitudinal_g[-1], 1.0,
		"straight launch reports authored proper longitudinal g")


func _test_pitched_gravity_cancellation() -> void:
	var angle := deg_to_rad(30.0)
	var tangent := Vector3(cos(angle), sin(angle), 0.0)
	var up := Vector3(-sin(angle), cos(angle), 0.0)
	var route := Motion.integrate(_initial(20.0, tangent, up), [
		_span("pitched", 1.0, "moving", cos(angle), 0.0, sin(angle), 0.0),
	], _settings(0.01))
	if not _expect_route(route, "pitched straight gravity-cancellation case integrates"):
		return
	_expect_close(route.speed_mps[-1], 20.0,
		"drive cancels gravity along a pitched straight exactly once")
	_expect_vector(route.tangent[-1], tangent,
		"normal support cancels transverse gravity without curving the track")
	_expect_close(route.longitudinal_g[-1], sin(angle),
		"longitudinal telemetry excludes gravity")


func _test_zero_gravity_circle() -> void:
	var theta := 0.5
	var speed := 10.0
	var duration := theta * speed / Motion.G0
	var route := Motion.integrate(_initial(speed), [
		_span("circle", duration, "moving", 0.0, 1.0, 0.0, 0.0),
	], _zero_gravity_settings(0.0025))
	if not _expect_route(route, "zero-gravity circular motion integrates"):
		return
	_expect_vector(route.tangent[-1], Vector3(cos(theta), 0.0, sin(theta)),
		"constant lateral proper force produces the analytic circular tangent", 0.0001)


func _test_banked_lateral_curvature() -> void:
	var bank := deg_to_rad(45.0)
	var up := Vector3.UP.rotated(Vector3.RIGHT, bank)
	var right := Vector3.RIGHT.cross(up)
	var force_magnitude := sqrt(1.0 + 0.5 * 0.5)
	var turn_angle := Motion.G0 * force_magnitude / 20.0 * 0.1
	var acceleration_direction := (up + 0.5 * right).normalized()
	var expected_tangent := Vector3.RIGHT * cos(turn_angle) \
		+ acceleration_direction * sin(turn_angle)
	var route := Motion.integrate(_initial(20.0, Vector3.RIGHT, up), [
		_span("banked", 0.1, "moving", 1.0, 0.5, 0.0, 0.0),
	], _zero_gravity_settings(0.001))
	if not _expect_route(route, "banked lateral-curvature case integrates"):
		return
	_expect_vector(route.tangent[-1], expected_tangent,
		"banked controls produce the analytic tangent", 0.000001)
	_expect_close(route.curvature_m_inv[-1], Motion.G0 * force_magnitude / 400.0,
		"banked controls produce the analytic curvature magnitude", 0.000001)
	_expect_unit_frame(route.tangent[-1], route.rider_up[-1],
		"banked integration preserves an orthonormal rider frame")


func _test_roll_only_frame_twist() -> void:
	var route := Motion.integrate(_initial(12.0), [
		_span("roll", 1.0, "moving", 0.0, 0.0, 0.0, PI * 0.5),
	], _zero_gravity_settings(0.005))
	if not _expect_route(route, "roll-only frame twist integrates"):
		return
	_expect_vector(route.tangent[-1], Vector3.RIGHT,
		"roll-only motion does not change tangent")
	_expect_vector(route.rider_up[-1], Vector3.BACK,
		"roll-only motion twists rider up ninety degrees", 0.0001)


func _test_low_speed_station_handoff() -> void:
	var handoff_speed := 2.01
	var handoff_time := handoff_speed / (0.5 * Motion.G0)
	var route := Motion.integrate(_initial(0.0), [
		_span("station", handoff_time, "station", 1.0, 0.0, 0.5, 0.0),
		_span("moving", 0.25, "moving", 1.0, 0.0, 0.0, 0.0),
	], _vacuum_settings(0.01))
	if not _expect_route(route, "zero-speed station start and strict-above-floor handoff integrate"):
		return
	var seam: int = route.span_index.find(1)
	_expect(seam > 0, "station-to-moving boundary owns an exact native node")
	if seam > 0:
		_expect_close(route.speed_mps[seam], handoff_speed,
			"moving mode begins unambiguously above the two metre-per-second floor")
		_expect_vector(route.tangent[seam], Vector3.RIGHT,
			"station mode keeps its straight frame fixed")
	_expect_rejected(Motion.integrate(_initial(1.5), [
		_span("too-slow", 0.1, "moving", 0.0, 0.0, 0.0, 0.0),
	], _zero_gravity_settings(0.01)), "moving speed floor",
		"moving mode rejects an initial speed below 2 m/s")
	_expect_rejected(Motion.integrate(_initial(2.1), [
		_span("cross-floor", 0.1, "moving", 0.0, 0.0, -1.0, 0.0),
	], _zero_gravity_settings(0.01)), "speed floor",
		"moving RK stages reject crossing below 2 m/s")
	_expect_rejected(Motion.integrate(_initial(0.1), [
		_span("cross-negative", 0.03, "station", 0.0, 0.0, -0.5, 0.0),
	], _zero_gravity_settings(0.01)), "negative speed",
		"station RK stages reject negative speed")
	_expect_rejected(Motion.integrate(_initial(0.0), [
		_span("stalled", 0.1, "station", 0.0, 0.0, 0.0, 0.0),
	], _zero_gravity_settings(0.01)), "nonpositive speed",
		"a stalled station interval rejects before it can fail to advance distance")
	_expect_rejected(Motion.integrate(_initial(0.0), [
		_span("transverse", 0.1, "station", 1.0, 0.0, 0.5, 0.0),
	], _zero_gravity_settings(0.01)), "station transverse",
		"station mode rejects transverse controls")
	var tolerated_station := Motion.integrate(_initial(5.0), [
		_span("roundoff", 0.1, "station", 1.0,
			0.5 * Motion.STATION_TRANSVERSE_TOLERANCE_G, 0.0, 0.0),
	], _settings(0.01))
	if _expect_route(tolerated_station, "station accepts sub-tolerance transverse roundoff"):
		_expect_vector(tolerated_station.tangent[-1], Vector3.RIGHT,
			"station freezes its frame when transverse roundoff is tolerated")
	_expect_rejected(Motion.integrate(_initial(5.0), [
		_span("tilted", 0.1, "station", 1.0,
			2.0 * Motion.STATION_TRANSVERSE_TOLERANCE_G, 0.0, 0.0),
	], _settings(0.01)), "station transverse",
		"station rejects transverse acceleration above its physical tolerance")
	_expect_rejected(Motion.integrate(_initial(0.0), [
		_span("rolling", 0.1, "station", 0.0, 0.0, 0.5, 0.1),
	], _zero_gravity_settings(0.01)), "station roll",
		"station mode rejects authored roll")


func _test_exact_span_boundary_splitting() -> void:
	var first_duration := 0.015
	var second_duration := 0.017
	var first_drive := 1.0
	var second_drive := -0.5
	var route := Motion.integrate(_initial(10.0), [
		_span("first", first_duration, "moving", 1.0, 0.0, first_drive, 0.0),
		_span("second", second_duration, "moving", 1.0, 0.0, second_drive, 0.0),
	], _vacuum_settings(0.01))
	if not _expect_route(route, "non-grid span boundaries integrate"):
		return
	_expect(route.time_s == PackedFloat64Array([0.0, 0.01, 0.015, 0.025, 0.032]),
		"RK4 steps split exactly at every span boundary")
	_expect(route.span_index == PackedInt32Array([0, 0, 1, 1, 1]),
		"no RK stage crosses into the next owning span")
	_expect_close(route.longitudinal_g[1], first_drive,
		"the pre-seam native state retains the first control")
	_expect_close(route.longitudinal_g[2], second_drive,
		"the seam native state is owned by the second control")
	var seam_speed := 10.0 + Motion.G0 * first_drive * first_duration
	var expected_speed := seam_speed + Motion.G0 * second_drive * second_duration
	var expected_position := 10.0 * first_duration \
		+ 0.5 * Motion.G0 * first_drive * first_duration * first_duration \
		+ seam_speed * second_duration \
		+ 0.5 * Motion.G0 * second_drive * second_duration * second_duration
	_expect_close(route.speed_mps[-1], expected_speed,
		"discontinuous drive owns only its exact span stages")
	_expect_close(route.position_m[-1].x, expected_position,
		"boundary splitting preserves the analytic piecewise-acceleration position", 0.00005)


func _test_boundary_roundoff_does_not_emit_a_sliver() -> void:
	const DURATION_S := 0.500000000067
	var route := Motion.integrate(_initial(10.0), [
		_span("first", DURATION_S, "moving", 0.0, 0.0, 0.0, 0.0),
		_span("second", DURATION_S, "moving", 0.0, 0.0, 0.0, 0.0),
	], _zero_gravity_settings(0.01))
	if not _expect_route(route, "roundoff-adjacent span boundaries integrate"):
		return
	_expect(route.time_s.size() == 101,
		"sub-nanosecond boundary roundoff is folded into the adjacent RK step")
	_expect(route.span_index.find(1) == 50,
		"the exact boundary node remains owned by the next span")
	var public_times := PackedFloat32Array()
	var public_distances := PackedFloat32Array()
	public_times.resize(route.time_s.size())
	public_distances.resize(route.distance_m.size())
	for index in route.time_s.size():
		public_times[index] = route.time_s[index]
		public_distances[index] = route.distance_m[index]
	for index in range(1, public_times.size()):
		_expect(public_times[index] > public_times[index - 1]
			and public_distances[index] > public_distances[index - 1],
			"public-compatible time and distance stay strict at sample %d" % index)
	_expect_close(route.time_s[-1], 2.0 * DURATION_S,
		"roundoff folding retains the exact terminal time")
	_expect_close(route.position_m[-1].x, 20.0 * DURATION_S,
		"roundoff folding retains the analytic terminal position", 0.000003)


func _test_degenerate_frame_rejection() -> void:
	var invalid_span := [_span("invalid", 1.0, "moving", 1.0, 0.0, 0.0, 0.0)]
	_expect_rejected(Motion.integrate(
		_initial(10.0, Vector3.ZERO, Vector3.UP), invalid_span, _vacuum_settings(0.01)
	), "tangent", "zero tangent is rejected before integration")
	_expect_rejected(Motion.integrate(
		_initial(10.0, Vector3.RIGHT, Vector3.ZERO), invalid_span, _vacuum_settings(0.01)
	), "rider_up", "zero rider up is rejected before integration")
	_expect_rejected(Motion.integrate(
		_initial(10.0, Vector3.RIGHT, Vector3.RIGHT), invalid_span, _vacuum_settings(0.01)
	), "orthogonal", "collinear tangent and rider up are rejected before integration")
	_expect_rejected(Motion.integrate(
		_initial(10.0, Vector3(NAN, 0.0, 0.0), Vector3.UP),
		invalid_span, _vacuum_settings(0.01)
	), "finite", "non-finite frame input is rejected before integration")


func _test_rk4_step_halving() -> void:
	var theta := 2.0
	var duration := 10.0 * theta / Motion.G0
	var exact := Vector3(cos(theta), 0.0, sin(theta))
	var coarse := Motion.integrate(_initial(10.0), [
		_span("circle", duration, "moving", 0.0, 1.0, 0.0, 0.0),
	], _zero_gravity_settings(0.2))
	var fine := Motion.integrate(_initial(10.0), [
		_span("circle", duration, "moving", 0.0, 1.0, 0.0, 0.0),
	], _zero_gravity_settings(0.1))
	if not _expect_route(coarse, "coarse RK4 convergence probe integrates"):
		return
	if not _expect_route(fine, "fine RK4 convergence probe integrates"):
		return
	var coarse_error: float = coarse.tangent[-1].distance_to(exact)
	var fine_error: float = fine.tangent[-1].distance_to(exact)
	_expect(fine_error > 0.0 and coarse_error / fine_error >= 12.0,
		"step halving demonstrates fourth-order convergence")
	_expect(fine_error <= 0.00001, "fine RK4 result has bounded absolute error")
	_expect_unit_frame(fine.tangent[-1], fine.rider_up[-1],
		"projected RK4 leaves a unit orthogonal frame")


func _test_dense_output_native_identity() -> void:
	var route := Motion.integrate(_initial(10.0), [
		_span("dense", 0.035, "moving", 1.0, 0.0, 0.25, 0.2),
	], _vacuum_settings(0.01))
	if not _expect_route(route, "dense-output identity probe integrates"):
		return
	for index in route.time_s.size():
		var sampled: Dictionary = Motion.sample_time(route, route.time_s[index])
		_expect_dense_state(sampled, route, index,
			"dense output reproduces full native state %d exactly" % index)
	var analytic_route := Motion.integrate(_initial(10.0), [
		_span("analytic-dense", 0.035, "moving", 1.0, 0.0, 0.25, 0.0),
	], _vacuum_settings(0.01))
	if not _expect_route(analytic_route, "analytic dense-output probe integrates"):
		return
	var sample_time := 0.0125
	var analytic: Dictionary = Motion.sample_time(analytic_route, sample_time)
	_expect_close(analytic.get("time_s", -1.0), sample_time,
		"off-grid dense sample retains requested time")
	_expect_close(analytic.get("speed_mps", -1.0), 10.0 + 0.25 * Motion.G0 * sample_time,
		"off-grid dense speed matches analytic straight launch")
	_expect_vector(analytic.get("position_m", Vector3.INF),
		Vector3.RIGHT * (10.0 * sample_time + 0.125 * Motion.G0 * sample_time * sample_time),
		"off-grid dense position matches analytic straight launch")
	_expect_close(analytic.get("distance_m", -1.0),
		10.0 * sample_time + 0.125 * Motion.G0 * sample_time * sample_time,
		"off-grid dense distance matches analytic straight launch")
	_expect_vector(analytic.get("tangent", Vector3.ZERO), Vector3.RIGHT,
		"off-grid analytic tangent stays straight")
	_expect_vector(analytic.get("rider_up", Vector3.ZERO), Vector3.UP,
		"off-grid analytic rider frame stays level")
	_expect_close(analytic.get("longitudinal_g", -1.0), 0.25,
		"off-grid analytic state retains proper longitudinal g")


func _test_dense_output_distance_and_defect() -> void:
	var route := Motion.integrate(_initial(14.0), [
		_span("dense", 0.5, "moving", 1.2, 0.35, 0.1, 0.4),
	], _vacuum_settings(0.01))
	if not _expect_route(route, "dense-output defect probe integrates"):
		return
	var midpoint: float = 0.5 * (route.distance_m[0] + route.distance_m[-1])
	var sampled: Dictionary = Motion.sample_distance(route, midpoint)
	_expect_close(float(sampled.get("distance_m", -1.0)), midpoint,
		"dense distance inversion is monotone and returns the requested coordinate")
	var kinematic_defect: float = route.dense_output.get("max_kinematic_defect_mps", INF)
	_expect(kinematic_defect >= 0.0 and kinematic_defect <= 0.00001,
		"dense output measures its actual dr/dt minus returned vT defect")
	var by_time: Dictionary = Motion.sample_time(route, sampled.get("time_s", -1.0))
	_expect_vector(by_time.get("position_m", Vector3.INF), sampled.get("position_m", Vector3.ZERO),
		"time and distance sampling agree on position", 0.000001)
	_expect_close(by_time.get("distance_m", -1.0), sampled.get("distance_m", -2.0),
		"time and distance sampling are inverse-consistent")
	var probe_time := 0.25
	var half_width := 0.001
	var before: Dictionary = Motion.sample_time(route, probe_time - half_width)
	var center: Dictionary = Motion.sample_time(route, probe_time)
	var after: Dictionary = Motion.sample_time(route, probe_time + half_width)
	var finite_difference: Vector3 = (after.get("position_m", Vector3.ZERO)
		- before.get("position_m", Vector3.ZERO)) / (2.0 * half_width)
	var expected_velocity: Vector3 = center.get("tangent", Vector3.ZERO) \
		* float(center.get("speed_mps", 0.0))
	# PackedVector3 is Float32; the 2 ms central difference keeps its amplified position
	# quantization below this tolerance while remaining local to one 10 ms native interval.
	_expect_vector(finite_difference, expected_velocity,
		"independent finite difference bounds dense dr/dt minus vT", 0.002)


func _initial(
	speed_mps: float,
	tangent: Vector3 = Vector3.RIGHT,
	rider_up: Vector3 = Vector3.UP
) -> Dictionary:
	return {
		"position_m": Vector3.ZERO,
		"tangent": tangent,
		"rider_up": rider_up,
		"speed_mps": speed_mps,
		"distance_m": 0.0,
		"time_s": 0.0,
	}


func _span(
	id: String, duration_s: float, mode: String,
	normal_g: float, lateral_g: float, drive_g: float, roll_rate_rad_s: float
) -> Dictionary:
	return Motion.span(
		id, duration_s, mode,
		Motion.constant(normal_g), Motion.constant(lateral_g),
		Motion.constant(drive_g), Motion.constant(roll_rate_rad_s)
	)


func _settings(step_s: float) -> Dictionary:
	return {
		"step_s": step_s,
		"gravity_mps2": Vector3.DOWN * Motion.G0,
		"rolling_mps2": 0.0,
		"aero_per_m": 0.0,
	}


func _vacuum_settings(step_s: float) -> Dictionary:
	return _settings(step_s)


func _zero_gravity_settings(step_s: float) -> Dictionary:
	var settings := _settings(step_s)
	settings.gravity_mps2 = Vector3.ZERO
	return settings


func _expect_route(route: Dictionary, message: String) -> bool:
	var ok: bool = route.get("ok", false)
	_expect(ok, "%s: %s" % [message, ", ".join(route.get("errors", []))])
	var required := [
		"time_s", "distance_m", "position_m", "tangent", "rider_up", "speed_mps",
		"longitudinal_g", "span_index", "curvature_m_inv",
	]
	var schema_ok := true
	var sample_count := -1
	for key in required:
		var values: Variant = route.get(key)
		var packed_array: bool = values is PackedFloat64Array \
			or values is PackedVector3Array or values is PackedInt32Array
		if not packed_array:
			_expect(false, "%s: trajectory channel %s is a packed array" % [message, key])
			schema_ok = false
			continue
		var channel_size: int = values.size()
		if sample_count < 0:
			sample_count = channel_size
		elif channel_size != sample_count:
			_expect(false, "%s: trajectory channel %s has %d samples, expected %d"
				% [message, key, channel_size, sample_count])
			schema_ok = false
	_expect(sample_count >= 2, "%s: trajectory contains initial and final native nodes" % message)
	return ok and schema_ok and sample_count >= 2


func _expect_rejected(route: Dictionary, fragment: String, message: String) -> void:
	_expect(not route.get("ok", true), message)
	_expect(_contains(route.get("errors", []), fragment),
		"%s with a diagnostic containing '%s'" % [message, fragment])


func _expect_unit_frame(tangent: Vector3, rider_up: Vector3, message: String) -> void:
	_expect_close(tangent.length(), 1.0, "%s tangent is unit" % message, 0.000001)
	_expect_close(rider_up.length(), 1.0, "%s up is unit" % message, 0.000001)
	_expect_close(tangent.dot(rider_up), 0.0, "%s axes are orthogonal" % message, 0.000001)
	_expect_close(tangent.cross(rider_up).length(), 1.0,
		"%s right axis is unit" % message, 0.000001)


func _expect_dense_state(
	sampled: Dictionary, route: Dictionary, index: int, message: String
) -> void:
	for key in [
		"time_s", "distance_m", "position_m", "tangent", "rider_up", "speed_mps",
		"longitudinal_g", "span_index", "curvature_m_inv",
	]:
		_expect(sampled.get(key) == route[key][index], "%s: %s" % [message, key])


func _contains(values: Variant, fragment: String) -> bool:
	for value in values:
		if str(value).contains(fragment):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)


func _expect_close(actual: float, expected: float, message: String, tolerance: float = EPS) -> void:
	_expect(absf(actual - expected) <= tolerance,
		"%s: expected %.9f, got %.9f" % [message, expected, actual])


func _expect_vector(
	actual: Vector3, expected: Vector3, message: String, tolerance: float = EPS
) -> void:
	_expect(actual.distance_to(expected) <= tolerance,
		"%s: expected %s, got %s" % [message, str(expected), str(actual)])
