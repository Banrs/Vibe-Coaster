extends SceneTree

const Motion := preload("res://motion.gd")
const RideGenerator := preload("res://generator.gd")
const RidePlanner := preload("res://ride_planner.gd")
const RideProgram := preload("res://ride_program.gd")
const Terrain := preload("res://terrain.gd")

const TARGET_PROMINENCE_M := 250.0
const TARGET_EXIT_HEIGHT_DELTA_M := 0.0
const TARGET_EXIT_PITCH_DEG := 0.0
const TARGET_LENGTH_M := 1000.0


func _initialize() -> void:
	var start := _camelback_start(42)
	if not start.get("ok", false):
		printerr("camelback shape probe could not produce the common entry state: ", start)
		quit(1)
		return
	var candidates := []
	var settings := RideProgram._settings(RideProgram.COARSE_STEP_S)
	for fall_index in 19:
		var fall_s := 2.50 + 0.25 * fall_index
		for peak_index in 13:
			var pullout_g := 3.50 + 0.25 * peak_index
			for release_index in 11:
				var release_s := 0.50 + 0.25 * release_index
				var route := Motion.integrate(
					start.state, _planar_spans(fall_s, pullout_g, release_s), settings)
				if not route.get("ok", false):
					continue
				var measured := _measure(route, start.state)
				measured["fall_s"] = fall_s
				measured["pullout_g"] = pullout_g
				measured["release_s"] = release_s
				measured["score"] = _score(measured)
				candidates.append(measured)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.score) < float(b.score))
	var top := []
	for index in mini(12, candidates.size()):
		var coarse: Dictionary = candidates[index]
		var production := Motion.integrate(start.state,
			_planar_spans(coarse.fall_s, coarse.pullout_g, coarse.release_s),
			RideProgram._settings(RideProgram.PRODUCTION_STEP_S))
		var measured := _measure(production, start.state)
		measured.merge({
			"fall_s": coarse.fall_s,
			"pullout_g": coarse.pullout_g,
			"release_s": coarse.release_s,
			"coarse_score": coarse.score,
			"production_score": _score(measured),
		}, true)
		top.append(measured)
	print("planar camelback shape sweep: ", JSON.stringify({
		"entry": {
			"speed_mps": start.state.speed_mps,
			"pitch_deg": _pitch_deg(start.state.tangent),
			"height_m": start.state.position_m.y,
		},
		"candidate_count": candidates.size(),
		"top": top,
	}))
	quit(0)


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


func _planar_spans(fall_s: float, pullout_g: float, release_s: float) -> Array:
	var positive_g := 4.60068864065765
	var negative_g := -1.55352865073772
	var pullup_s := 1.87949032 * 1.33555111055541
	var unload_s := 3.01169597 * 1.15 - 0.4
	var crest_s := 3.62587650 * 1.06
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


func _score(measured: Dictionary) -> float:
	var height_error := (float(measured.exit_height_delta_m) - TARGET_EXIT_HEIGHT_DELTA_M) / 5.0
	var pitch_error := (float(measured.exit_pitch_deg) - TARGET_EXIT_PITCH_DEG) / 0.5
	var prominence_error := (float(measured.prominence_m) - TARGET_PROMINENCE_M) / 3.0
	var length_error := (float(measured.length_m) - TARGET_LENGTH_M) / 50.0
	return height_error * height_error + pitch_error * pitch_error \
		+ prominence_error * prominence_error + 0.1 * length_error * length_error


func _pitch_deg(tangent: Vector3) -> float:
	return rad_to_deg(asin(clampf(tangent.normalized().y, -1.0, 1.0)))
