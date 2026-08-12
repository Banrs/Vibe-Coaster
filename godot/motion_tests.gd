extends SceneTree

const Motion := preload("res://motion.gd")
const EPS := 0.000001

var _errors := PackedStringArray()


func _initialize() -> void:
	_test_c2_profiles()
	_test_resistance_law()
	_test_straight_coast()
	_test_straight_launch()
	_test_pitched_gravity_cancellation()
	_test_zero_gravity_circle()
	_test_banked_lateral_curvature()
	_test_roll_only_frame_twist()
	_test_low_speed_station_handoff()
	_test_exact_span_boundary_splitting()
	_test_degenerate_frame_rejection()
	_test_rk4_step_halving()
	_test_dense_output_native_identity()
	_test_dense_output_distance_and_defect()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _test_c2_profiles() -> void:
	var transition := Motion.quintic(2.0, 5.0)
	_expect_vector(Motion.profile_sample(transition, 0.0), Vector3(2.0, 0.0, 0.0),
		"quintic starts with exact value and zero first/second derivatives")
	_expect_vector(Motion.profile_sample(transition, 1.0), Vector3(5.0, 0.0, 0.0),
		"quintic ends with exact value and zero first/second derivatives")
	var pulse := Motion.compact_pulse(3.0)
	_expect_vector(Motion.profile_sample(pulse, 0.0), Vector3.ZERO,
		"compact pulse has a zero C2 entry jet")
	_expect_vector(Motion.profile_sample(pulse, 1.0), Vector3.ZERO,
		"compact pulse has a zero C2 exit jet")
	_expect_close(Motion.profile_sample(pulse, 0.5).x, 3.0,
		"compact pulse reaches its authored amplitude")


func _test_resistance_law() -> void:
	var measured := Motion.resistance(20.0, 0.15, 0.002)
	_expect_vector(measured, Vector3(0.95, 0.08, 0.004),
		"resistance and analytic derivatives follow rolling plus quadratic drag")
	var stopped := Motion.resistance(0.0, 0.15, 0.002)
	_expect_vector(stopped, Vector3(0.15, 0.0, 0.004),
		"resistance is smooth and one-sided at zero forward speed")


func _test_straight_coast() -> void:
	var route := Motion.integrate(_initial(10.0), [
		_span("coast", 2.0, "moving", 1.0, 0.0, 0.0, 0.0),
	], _vacuum_settings(0.01))
	if not _expect_route(route, "straight coast integrates"):
		return
	_expect_vector(route.position_m[-1], Vector3(20.0, 0.0, 0.0),
		"straight coast advances at constant speed")
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
		"straight launch position follows constant acceleration")
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
	var route := Motion.integrate(_initial(20.0, Vector3.RIGHT, up), [
		_span("banked", 0.1, "moving", 1.0, 0.5, 0.0, 0.0),
	], _zero_gravity_settings(0.001))
	if not _expect_route(route, "banked lateral-curvature case integrates"):
		return
	_expect(route.tangent[-1].y > 0.02 and route.tangent[-1].z > 0.0,
		"banked normal and lateral controls curve in their transported rider-frame directions")


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
	var handoff_time := 2.0 / (0.5 * Motion.G0)
	var route := Motion.integrate(_initial(0.0), [
		_span("station", handoff_time, "station", 0.0, 0.0, 0.5, 0.0),
		_span("moving", 0.25, "moving", 1.0, 0.0, 0.0, 0.0),
	], _vacuum_settings(0.01))
	if not _expect_route(route, "zero-speed station start and exact 2 m/s handoff integrate"):
		return
	var seam := route.span_index.find(1)
	_expect(seam > 0, "station-to-moving boundary owns an exact native node")
	if seam > 0:
		_expect_close(route.speed_mps[seam], 2.0,
			"moving mode begins at the exact two metre-per-second boundary")
		_expect_vector(route.tangent[seam], Vector3.RIGHT,
			"station mode keeps its straight frame fixed")


func _test_exact_span_boundary_splitting() -> void:
	var route := Motion.integrate(_initial(10.0), [
		_span("first", 0.015, "moving", 1.0, 0.0, 0.0, 0.0),
		_span("second", 0.017, "moving", 1.0, 0.0, 0.0, 0.0),
	], _vacuum_settings(0.01))
	if not _expect_route(route, "non-grid span boundaries integrate"):
		return
	_expect(route.time_s == PackedFloat64Array([0.0, 0.01, 0.015, 0.025, 0.032]),
		"RK4 steps split exactly at every span boundary")
	_expect(route.span_index == PackedInt32Array([0, 0, 1, 1, 1]),
		"no RK stage crosses into the next owning span")


func _test_degenerate_frame_rejection() -> void:
	var route := Motion.integrate(_initial(10.0, Vector3.ZERO, Vector3.UP), [
		_span("invalid", 1.0, "moving", 1.0, 0.0, 0.0, 0.0),
	], _vacuum_settings(0.01))
	_expect(not route.get("ok", true), "zero tangent is rejected before integration")
	_expect(_contains(route.get("errors", []), "tangent"),
		"degenerate-frame rejection identifies the tangent")


func _test_rk4_step_halving() -> void:
	var theta := 1.0
	var duration := 10.0 / Motion.G0
	var exact := Vector3(cos(theta), 0.0, sin(theta))
	var coarse := Motion.integrate(_initial(10.0), [
		_span("circle", duration, "moving", 0.0, 1.0, 0.0, 0.0),
	], _zero_gravity_settings(0.04))
	var fine := Motion.integrate(_initial(10.0), [
		_span("circle", duration, "moving", 0.0, 1.0, 0.0, 0.0),
	], _zero_gravity_settings(0.02))
	if not _expect_route(coarse, "coarse RK4 convergence probe integrates"):
		return
	if not _expect_route(fine, "fine RK4 convergence probe integrates"):
		return
	var coarse_error: float = coarse.tangent[-1].distance_to(exact)
	var fine_error: float = fine.tangent[-1].distance_to(exact)
	_expect(fine_error > 0.0 and coarse_error / fine_error >= 12.0,
		"step halving demonstrates fourth-order convergence")


func _test_dense_output_native_identity() -> void:
	var route := Motion.integrate(_initial(10.0), [
		_span("dense", 0.035, "moving", 1.0, 0.0, 0.25, 0.2),
	], _vacuum_settings(0.01))
	if not _expect_route(route, "dense-output identity probe integrates"):
		return
	for index in route.time_s.size():
		var sampled: Dictionary = Motion.sample_time(route, route.time_s[index])
		_expect(sampled.get("position_m") == route.position_m[index]
			and sampled.get("speed_mps") == route.speed_mps[index],
			"dense output reproduces native node %d exactly" % index)


func _test_dense_output_distance_and_defect() -> void:
	var route := Motion.integrate(_initial(14.0), [
		_span("dense", 0.5, "moving", 1.2, 0.35, 0.1, 0.4),
	], _vacuum_settings(0.01))
	if not _expect_route(route, "dense-output defect probe integrates"):
		return
	var midpoint := 0.5 * (route.distance_m[0] + route.distance_m[-1])
	var sampled: Dictionary = Motion.sample_distance(route, midpoint)
	_expect_close(float(sampled.get("distance_m", -1.0)), midpoint,
		"dense distance inversion is monotone and returns the requested coordinate")
	_expect(route.dense_output.get("max_kinematic_defect_mps", INF) <= 0.001,
		"dense output quantifies a bounded dr/dt minus vT defect")


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
	return ok


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
