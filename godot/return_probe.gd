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
			"entry_speed_mps": Vector2(70.0, 80.0)}, "capture_half_width_m": 150.0,
		"capture_half_height_m": 75.0}
	var initial_bank := float(RideReturnSolve._capture_residuals(start, layout)[4])
	print("start position=%s tangent=%s up=%s speed=%f distance=%f initial_bank=%f" % [
		str(start.position_m), str(start.tangent), str(start.rider_up), start.speed_mps,
		start.distance_m, initial_bank])
	var random := RandomNumberGenerator.new()
	random.seed = 20260820
	var best_candidate: Array = []
	var best_score := INF
	var best_result := {}
	for attempt in 160:
		var candidate := []
		for bound: Array in RideReturnSolve.RETURN_SCALAR_BOUNDS:
			candidate.append(random.randf_range(float(bound[0]), float(bound[1])))
		var result := RideReturnSolve._return_evaluation(start, layout, candidate,
			RideProgram._settings(RideProgram.PRODUCTION_STEP_S), {}, -hand, initial_bank,
			story.targets)
		var score := 0.0
		for value in result.get("scaled", []):
			score += float(value) * float(value)
		if score < best_score:
			best_score = score
			best_candidate = candidate
			best_result = result
	print("random_best score=%f candidate=%s result=%s" % [best_score,
		str(best_candidate), str(best_result)])
	var solved := RideReturnSolve._solve_return(start, layout, -hand, best_candidate, story.targets)
	print("random_best_solve=%s" % str(solved))
	quit(0)
