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
	var story := {"targets": {}}
	var layout := {"station_position_m": Vector3.ZERO, "station_tangent": Vector3.RIGHT,
		"station_up": Vector3.UP, "reserved_corridor": {"minimum_length_m": 230.0,
			"capture_length_m": 80.0, "brake_length_m": 150.0,
			"entry_speed_mps": Vector2(70.0, 80.0)}, "capture_half_width_m": 150.0,
		"capture_half_height_m": 75.0}
	var initial_bank := float(RideReturnSolve._capture_residuals(start, layout)[4])
	print("start position=%s tangent=%s up=%s speed=%f distance=%f initial_bank=%f" % [
		str(start.position_m), str(start.tangent), str(start.rider_up), start.speed_mps,
		start.distance_m, initial_bank])
	var accepted := [
		1.25698645092423, 3.39547844224014, 6.0, 1.27965900475676,
		2.0, 0.1, 6.0, 3.818829,
	]
	var return_result := RideReturnSolve._return_evaluation(start, layout, accepted,
		RideProgram._settings(RideProgram.PRODUCTION_STEP_S), {}, -hand, initial_bank,
		story.targets)
	print("return_observation=%s" % str(return_result.get("observation", {})))
	print("return_margins=%s" % str(return_result.get("margins", {})))
	if not return_result.get("ok", false):
		print("capture_outcome=skipped_return_failure:%s" % str(return_result))
		quit(0)
		return
	var capture_start := RideProgram._last_state(return_result.route)
	var capture := RideReturnSolve._solve_capture(capture_start, layout,
		RideProgram._settings(RideProgram.FINE_STEP_S))
	print("capture_outcome=%s" % str(capture))
	quit(0)
