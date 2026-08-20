extends SceneTree

const BoundedSolver := preload("res://bounded_solver.gd")
const Motion := preload("res://motion.gd")
const RideGenerator := preload("res://generator.gd")
const RidePlanner := preload("res://ride_planner.gd")
const RideProgram := preload("res://ride_program.gd")
const RideReturnSolve := preload("res://ride_return_solve.gd")
const RideTerrain := preload("res://terrain.gd")

const SEED := 42
const MAX_EVALUATIONS := 219


func _initialize() -> void:
	var decisions := RidePlanner.resolve(SEED)
	var terrain: Dictionary = RideTerrain.generate(
		decisions.streams[RidePlanner.STREAM_TERRAIN])
	var plan: Dictionary = RideGenerator._plan(terrain, decisions)
	if plan.has("ok") and not plan.ok:
		print("return basin probe planning failed: %s" % str(plan))
		quit(1)
		return
	var initial_state := RideGenerator._initial_state(plan.station)
	var spans: Array = []
	var metadata: Array = []
	var gestures: Array = []
	var propulsion := PackedInt32Array()
	var hand := -float(plan.decisions.station_side)
	var story := RideProgram._story_from_plan(plan)
	RideProgram._add_story_prefix(spans, metadata, gestures, propulsion, hand, story,
		RideProgram._prefix_controls_from_plan(plan))
	RideProgram._add_camelback(spans, metadata, propulsion)
	var prefix := Motion.integrate(initial_state, spans,
		RideProgram._settings(RideProgram.PRODUCTION_STEP_S))
	if not prefix.get("ok", false):
		print("return basin probe prefix integration failed: %s" % str(prefix))
		quit(1)
		return
	var start := RideProgram._last_state(prefix)
	var layout := RideProgram._layout_from_plan(plan)
	var return_hand := -hand
	var targets: Dictionary = story.targets
	var production_seed := RideReturnSolve.RETURN_SEED.duplicate()
	production_seed.append(RidePlanner.target(
		targets, "return-height-a", "peak_g", RideReturnSolve.RETURN_HEIGHT_A_PEAK_G))
	var midpoint_seed := _midpoint_seed()

	_run_lane("production/actual-seed", [0.85, 0.90], production_seed, start, layout,
		return_hand, targets)
	_run_lane("production/all-bound-midpoint", [0.85, 0.90], midpoint_seed, start, layout,
		return_hand, targets)
	var continuation_seed := midpoint_seed.duplicate()
	for profile: Array in [[0.65, 0.70], [0.75, 0.80], [0.85, 0.90]]:
		var solved := _run_lane("continuation", profile, continuation_seed, start, layout,
			return_hand, targets)
		continuation_seed = solved.x.duplicate()
	quit(1)


func _midpoint_seed() -> Array:
	var seed := []
	for bound: Array in RideReturnSolve.RETURN_SCALAR_BOUNDS:
		seed.append(0.5 * (float(bound[0]) + float(bound[1])))
	return seed


func _run_lane(lane: String, profile: Array, seed: Array, start: Dictionary,
	layout: Dictionary, hand: float, targets: Dictionary) -> Dictionary:
	RideReturnSolve.PROBE_UNBANK_PROFILE = profile.duplicate()
	var cache := {}
	var initial_bank_rad: float = RideReturnSolve._capture_residuals(start, layout)[4]
	var residual := func(candidate: Array) -> Array:
		var observed := RideReturnSolve._return_evaluation(
			start, layout, candidate, RideProgram._settings(RideProgram.PRODUCTION_STEP_S), cache,
			hand, initial_bank_rad, targets)
		return observed.get("scaled", [INF]) if observed.get("ok", false) else [INF]
	var solved: Dictionary = BoundedSolver.solve(
		residual, _lower_bounds(), _upper_bounds(), seed, MAX_EVALUATIONS)
	print(("return basin probe lane=%s profile=%s start=%s status=%s evaluations=%d x=%s "
		+ "scaled_residuals=%s") % [lane, str(profile), str(seed), str(solved.status),
		int(solved.evaluations), str(solved.x), str(solved.residuals)])
	if solved.ok:
		var production := RideReturnSolve._return_evaluation(
			start, layout, solved.x, RideProgram._settings(RideProgram.PRODUCTION_STEP_S), cache,
			hand, initial_bank_rad, targets)
		var fine := RideReturnSolve._return_evaluation(
			start, layout, solved.x, RideProgram._settings(RideProgram.FINE_STEP_S), cache,
			hand, initial_bank_rad, targets)
		print(("return basin probe lane=%s profile=%s production_observation=%s "
			+ "fine_observation=%s production_margins=%s fine_margins=%s") % [lane,
			str(profile),
			str(production.get("observation", {})), str(fine.get("observation", {})),
			str(production.get("margins", {})), str(fine.get("margins", {}))])
	return solved


func _lower_bounds() -> Array:
	var lower := []
	for bound: Array in RideReturnSolve.RETURN_SCALAR_BOUNDS:
		lower.append(bound[0])
	return lower


func _upper_bounds() -> Array:
	var upper := []
	for bound: Array in RideReturnSolve.RETURN_SCALAR_BOUNDS:
		upper.append(bound[1])
	return upper
