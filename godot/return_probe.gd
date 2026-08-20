extends SceneTree

const RideProgram := preload("res://ride_program.gd")
const RidePrefixSolve := preload("res://ride_prefix_solve.gd")
const RideReturnSolve := preload("res://ride_return_solve.gd")
const Motion := preload("res://motion.gd")


func _initialize() -> void:
	var program := RidePrefixSolve._prefix_program(1, {}, RidePrefixSolve.PREFIX_SEED)
	if not program.get("ok", false):
		printerr("prefix program failed: %s" % str(program))
		quit(1)
		return
	var spans: Array = []
	var metadata: Array = []
	var gestures: Array = []
	var propulsion := PackedInt32Array()
	var hand := -1.0
	spans.append_array(program.spans)
	RideProgram._add_camelback(spans, metadata, propulsion)
	var start_route := Motion.integrate(RidePrefixSolve._prefix_initial_state(), spans,
		RideProgram._settings(RideProgram.PRODUCTION_STEP_S))
	if not start_route.get("ok", false):
		printerr("prefix failed: %s" % str(start_route))
		quit(1)
		return
	var start := RideProgram._last_state(start_route)
	var layout := {"station_position_m": Vector3.ZERO, "station_tangent": Vector3.RIGHT,
		"station_up": Vector3.UP, "reserved_corridor": {"minimum_length_m": 230.0,
			"entry_speed_mps": Vector2(70.0, 80.0)}, "capture_half_width_m": 150.0,
		"capture_half_height_m": 75.0}
	print("start position=%s tangent=%s up=%s speed=%f distance=%f" % [
		str(start.position_m), str(start.tangent), str(start.rider_up), start.speed_mps,
		start.distance_m])
	var candidates := [
		RideReturnSolve.RETURN_SEED.duplicate() + [3.8],
		[1.07, 0.55, 3.13, 1.05, 6.35, 0.42, 3.12, 3.52],
		[1.15, 4.80, 1.23, 1.09, 4.97, 1.71, 4.04, 4.60],
		[1.047, 2.5, 2.0, 1.22, 8.0, 1.0, 2.0, 3.8],
		[1.15, 6.0, 4.0, 1.35, 12.0, 2.0, 4.6, 4.6],
		[0.9, 3.0, 1.0, 1.4, 4.0, 0.5, 1.0, 3.4],
	]
	for candidate: Array in candidates:
		var result := RideReturnSolve._return_evaluation(start, layout, candidate,
			RideProgram._settings(RideProgram.PRODUCTION_STEP_S), {}, -hand, 0.0, story.targets)
		print("candidate=%s residuals=%s observation=%s" % [str(candidate),
			str(result.get("residuals", [])), str(result.get("observation", {}))])
	quit(0)
