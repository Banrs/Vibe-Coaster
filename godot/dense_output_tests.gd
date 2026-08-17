extends SceneTree

const Motion := preload("res://motion.gd")

var _errors := PackedStringArray()


func _initialize() -> void:
	_test_exact_straight_dense_output_is_consistent()
	_test_independent_speed_channel_corruption_is_detected()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _test_exact_straight_dense_output_is_consistent() -> void:
	var route := _straight_route()
	if not _expect(route.get("ok", false), "straight dense-output fixture integrates"):
		return
	var defect := float(Motion._measure_dense_defect(route))
	_expect(is_finite(defect) and defect <= 0.00001,
		"an exact straight trajectory has negligible dense-output defect, got %.9f" % defect)


func _test_independent_speed_channel_corruption_is_detected() -> void:
	var route := _straight_route()
	if not _expect(route.get("ok", false), "corruption fixture integrates before mutation"):
		return
	var baseline := float(Motion._measure_dense_defect(route))
	var corrupted := route.duplicate(true)
	var speeds: PackedFloat64Array = corrupted.speed_mps.duplicate()
	var middle := speeds.size() / 2
	speeds[middle] += 5.0
	corrupted.speed_mps = speeds
	var defect := float(Motion._measure_dense_defect(corrupted))
	_expect(defect >= baseline + 0.5,
		"dense measurement detects a 5 m/s channel corruption independently of position; "
		+ "baseline %.9f, corrupted %.9f" % [baseline, defect])


func _straight_route() -> Dictionary:
	return Motion.integrate(
		{
			"position_m": Vector3.ZERO,
			"tangent": Vector3.RIGHT,
			"rider_up": Vector3.UP,
			"speed_mps": 20.0,
			"distance_m": 0.0,
			"time_s": 0.0,
		},
		[
			Motion.span(
				"dense/straight", 0.05, "moving",
				Motion.constant(0.0), Motion.constant(0.0),
				Motion.constant(0.0), Motion.constant(0.0)
			),
		],
		{
			"step_s": 0.01,
			"gravity_mps2": Vector3.ZERO,
			"rolling_mps2": 0.0,
			"aero_per_m": 0.0,
		}
	)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_errors.append(message)
	return condition
