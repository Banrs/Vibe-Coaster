extends SceneTree

const Generator := preload("res://generator.gd")
const RidePlanner := preload("res://ride_planner.gd")
const Terrain := preload("res://terrain.gd")
const RideProgram := preload("res://ride_program.gd")
const RideReturnSolve := preload("res://ride_return_solve.gd")
const Motion := preload("res://motion.gd")


func _initialize() -> void:
	var decisions := RidePlanner.resolve(42)
	var plan := Generator._plan(Terrain.generate(decisions.streams[RidePlanner.STREAM_TERRAIN]), decisions)
	if not plan.get("ok", false):
		printerr("plan failed: %s" % str(plan))
		quit(1)
		return
	var spans: Array = []
	var metadata: Array = []
	var gestures: Array = []
	var propulsion := PackedInt32Array()
	var hand := -float(plan.decisions.station_side)
	var story := RideProgram._story_from_plan(plan)
	RideProgram._add_story_prefix(spans, metadata, gestures, propulsion, hand, story,
		RideProgram._prefix_controls_from_plan(plan))
	RideProgram._add_camelback(spans, metadata, propulsion)
	var start_route := Motion.integrate(Generator._initial_state(plan.station), spans,
		RideProgram._settings(RideProgram.PRODUCTION_STEP_S))
	if not start_route.get("ok", false):
		printerr("prefix failed: %s" % str(start_route))
		quit(1)
		return
	var start := RideProgram._last_state(start_route)
	var layout := RideProgram._layout_from_plan(plan)
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
