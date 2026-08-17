extends SceneTree

const BoundedSolver := preload("res://bounded_solver.gd")
const Motion := preload("res://motion.gd")
const RideGenerator := preload("res://generator.gd")
const RidePlanner := preload("res://ride_planner.gd")
const RideProgram := preload("res://ride_program.gd")
const Terrain := preload("res://terrain.gd")

const TARGET_PROMINENCE_M := 250.0
const LENGTH_BAND_M := Vector2(900.0, 1180.0)
const CONTROL_IDS := [
	"unload_s", "crest_s", "fall_s", "pullout_g", "release_s",
]
const LOWER := [1.0, 0.5, 2.0, 3.0, 0.30]
const UPPER := [4.5, 5.0, 7.0, 7.0, 4.00]
const INITIAL := [3.01169597 * 1.15 - 0.4, 3.62587650 * 1.06, 3.40,
	5.2662035249371, 1.58]


func _initialize() -> void:
	var start := _camelback_start(42)
	if not start.get("ok", false):
		printerr("camelback shape probe could not produce the common entry state: ", start)
		quit(1)
		return
	var cache := {}
	var settings := RideProgram._settings(RideProgram.COARSE_STEP_S)
	var residual := func(candidate: Array) -> Array:
		var measured := _evaluate(start.state, candidate, settings, cache)
		return measured.residuals if measured.get("ok", false) else [INF]
	var solved := BoundedSolver.solve(residual, LOWER, UPPER, INITIAL, 299)
	var accepted: Array = solved.get("x", INITIAL)
	var coarse := _evaluate(start.state, accepted, settings, cache)
	var production := _evaluate(start.state, accepted,
		RideProgram._settings(RideProgram.PRODUCTION_STEP_S), {})
	print("planar camelback local solve: ", JSON.stringify({
		"entry": {
			"height_m": start.state.position_m.y,
			"pitch_deg": _pitch_deg(start.state.tangent),
			"speed_mps": start.state.speed_mps,
		},
		"control_ids": CONTROL_IDS,
		"control_bounds": {"lower": LOWER, "upper": UPPER},
		"initial": INITIAL,
		"solver": {
			"ok": solved.get("ok", false),
			"status": solved.get("status", ""),
			"evaluations": solved.get("evaluations", 0),
			"iterations": solved.get("iterations", 0),
			"conditioning": solved.get("conditioning", null),
			"accepted": accepted,
			"scaled_residuals": solved.get("residuals", []),
		},
		"coarse": coarse,
		"production": production,
	}))
	quit(0)


func _evaluate(
	entry: Dictionary, controls: Array, settings: Dictionary, cache: Dictionary
) -> Dictionary:
	var key := "%.6f:" % float(settings.step_s)
	for value in controls:
		key += "%.10f," % float(value)
	if cache.has(key):
		return cache[key]
	var route := Motion.integrate(entry, _planar_spans(controls), settings)
	if not route.get("ok", false):
		var failed := {"ok": false, "errors": route.get("errors", [])}
		cache[key] = failed
		return failed
	var measured := _measure(route, entry)
	var length_residual := minf(0.0, float(measured.length_m) - LENGTH_BAND_M.x) \
		+ maxf(0.0, float(measured.length_m) - LENGTH_BAND_M.y)
	var rise_arc := float(measured.apex_distance_m)
	var fall_arc := float(measured.length_m) - rise_arc
	measured["residuals"] = [
		float(measured.exit_height_delta_m) / 3.0,
		float(measured.exit_pitch_deg) / 0.25,
		(float(measured.prominence_m) - TARGET_PROMINENCE_M) / 2.0,
		length_residual / 25.0,
		(rise_arc - fall_arc) / 20.0,
	]
	measured["rise_arc_m"] = rise_arc
	measured["fall_arc_m"] = fall_arc
	measured["controls"] = controls.duplicate()
	cache[key] = measured
	return measured


func _camelback_start(seed_value: int) -> Dictionary:
	var decisions := RidePlanner.resolve(seed_value)
	var terrain := Terrain.generate(decisions.streams[RidePlanner.STREAM_TERRAIN])
	var plan := RideGenerator._plan(terrain, decisions)
	if plan.has("ok") and not plan.ok:
		return plan
	var initial_state := RideGenerator._initial_state(plan.station)
	var hand := -float(plan.decisions.station_side)
	var story := {
		"sequence": RideProgram.plan_role_ids(plan),
		"targets": plan.decisions.targets,
	}
	var spans: Array = []
	var metadata: Array = []
	var gestures: Array = []
	var propulsion := PackedInt32Array()
	RideProgram._add_story_prefix(
		spans, metadata, gestures, propulsion, hand, story,
		RideProgram._prefix_controls_from_plan(plan))
	var prefix := Motion.integrate(
		initial_state, spans, RideProgram._settings(RideProgram.PRODUCTION_STEP_S))
	if not prefix.get("ok", false):
		return prefix
	return {"ok": true, "state": RideProgram._last_state(prefix)}


func _planar_spans(controls: Array) -> Array:
	var positive_g := 4.60068864065765
	var negative_g := -1.55352865073772
	var pullup_s := 1.87949032 * 1.33555111055541
	var unload_s := float(controls[0])
	var crest_s := float(controls[1])
	var fall_s := float(controls[2])
	var pullout_g := float(controls[3])
	var release_s := float(controls[4])
	return [
		Motion.span("camelback/pull-up", pullup_s, "moving",
			Motion.quintic(1.0, positive_g), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
		Motion.span("camelback/rise-hold", 0.4, "moving",
			Motion.constant(positive_g), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
		Motion.span("camelback/unload", unload_s, "moving",
			Motion.quintic(positive_g, negative_g), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
		Motion.span("camelback/crest", crest_s, "moving",
			Motion.constant(negative_g), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
		Motion.span("camelback/fall", fall_s, "moving",
			Motion.quintic(negative_g, pullout_g), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
		Motion.span("camelback/pullout-release", release_s, "moving",
			Motion.quintic(pullout_g, 1.0), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
	]


func _measure(route: Dictionary, entry: Dictionary) -> Dictionary:
	if not route.get("ok", false):
		return {"ok": false}
	var maximum_y := -INF
	var apex_index := 0
	for index in route.position_m.size():
		if route.position_m[index].y > maximum_y:
			maximum_y = route.position_m[index].y
			apex_index = index
	var exit := RideProgram._last_state(route)
	var exit_height_delta := float(exit.position_m.y) - float(entry.position_m.y)
	var prominence := maximum_y - maxf(float(entry.position_m.y), float(exit.position_m.y))
	var length_m := float(exit.distance_m) - float(entry.distance_m)
	return {
		"ok": true,
		"exit_height_delta_m": exit_height_delta,
		"exit_pitch_deg": _pitch_deg(exit.tangent),
		"exit_speed_mps": exit.speed_mps,
		"prominence_m": prominence,
		"length_m": length_m,
		"apex_pitch_deg": _pitch_deg(route.tangent[apex_index]),
		"apex_speed_mps": route.speed_mps[apex_index],
		"apex_time_s": route.time_s[apex_index] - route.time_s[0],
		"apex_distance_m": route.distance_m[apex_index] - route.distance_m[0],
	}


func _pitch_deg(tangent: Vector3) -> float:
	return rad_to_deg(asin(clampf(tangent.normalized().y, -1.0, 1.0)))
