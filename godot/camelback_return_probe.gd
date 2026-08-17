extends SceneTree

const Motion := preload("res://motion.gd")
const RideGenerator := preload("res://generator.gd")
const RidePlanner := preload("res://ride_planner.gd")
const RideProgram := preload("res://ride_program.gd")
const RideReturnSolve := preload("res://ride_return_solve.gd")
const Terrain := preload("res://terrain.gd")


func _initialize() -> void:
	var seed_value := 42
	var decisions := RidePlanner.resolve(seed_value)
	var terrain := Terrain.generate(decisions.streams[RidePlanner.STREAM_TERRAIN])
	var plan := RideGenerator._plan(terrain, decisions)
	if plan.has("ok") and not plan.ok:
		printerr("handoff probe could not plan seed 42: ", plan)
		quit(1)
		return
	var initial_state := RideGenerator._initial_state(plan.station)
	var hand := -float(plan.decisions.station_side)
	var story := {
		"sequence": RideProgram.plan_role_ids(plan),
		"targets": plan.decisions.targets,
	}
	var prefix_spans: Array = []
	var prefix_metadata: Array = []
	var prefix_gestures: Array = []
	var prefix_propulsion := PackedInt32Array()
	RideProgram._add_story_prefix(
		prefix_spans, prefix_metadata, prefix_gestures, prefix_propulsion,
		hand, story, RideProgram._prefix_controls_from_plan(plan))
	var settings := RideProgram._settings(RideProgram.PRODUCTION_STEP_S)
	var prefix := Motion.integrate(initial_state, prefix_spans, settings)
	if not prefix.get("ok", false):
		printerr("handoff probe prefix integration failed: ", prefix.get("errors", []))
		quit(1)
		return
	var prefix_end := RideProgram._last_state(prefix)
	var old_route := Motion.integrate(prefix_end, _old_camelback_spans(hand), settings)
	var planar_spans: Array = []
	var planar_metadata: Array = []
	var planar_propulsion := PackedInt32Array()
	RideProgram._add_camelback(planar_spans, planar_metadata, planar_propulsion, hand)
	var planar_route := Motion.integrate(prefix_end, planar_spans, settings)
	if not old_route.get("ok", false) or not planar_route.get("ok", false):
		printerr("handoff probe camelback integration failed: old=", old_route.get("errors", []),
			" planar=", planar_route.get("errors", []))
		quit(1)
		return
	var old_state := RideProgram._last_state(old_route)
	var planar_state := RideProgram._last_state(planar_route)
	var layout := RideProgram._layout_from_plan(plan)
	var old_pose := RideReturnSolve._capture_residuals(old_state, layout)
	var planar_pose := RideReturnSolve._capture_residuals(planar_state, layout)
	var forward: Vector3 = plan.station.tangent.normalized()
	var up: Vector3 = plan.station.up.normalized()
	var right := forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	var delta: Vector3 = planar_state.position_m - old_state.position_m
	var delta_pose := []
	for index in old_pose.size():
		delta_pose.append(float(planar_pose[index]) - float(old_pose[index]))
	print("old-to-planar camelback handoff: ", JSON.stringify({
		"position_delta_station_m": {
			"forward": delta.dot(forward),
			"cross": delta.dot(right),
			"height": delta.dot(up),
		},
		"pose_delta": {
			"cross_m": delta_pose[0],
			"height_m": delta_pose[1],
			"yaw_deg": rad_to_deg(delta_pose[2]),
			"pitch_deg": rad_to_deg(delta_pose[3]),
			"roll_deg": rad_to_deg(delta_pose[4]),
		},
		"speed_delta_mps": float(planar_state.speed_mps) - float(old_state.speed_mps),
		"distance_delta_m": float(planar_state.distance_m) - float(old_state.distance_m),
		"time_delta_s": float(planar_state.time_s) - float(old_state.time_s),
		"old": _state_record(old_state, old_pose, plan.station.position_m, forward, right, up),
		"planar": _state_record(planar_state, planar_pose, plan.station.position_m, forward, right, up),
	}))

	var route := RideGenerator.build(seed_value)
	var failure: Dictionary = route.get("failure", {})
	var residuals: Array = failure.get("target_error", [])
	var mapped := {}
	for index in mini(residuals.size(), RideReturnSolve.RETURN_RESIDUAL_IDS.size()):
		mapped[RideReturnSolve.RETURN_RESIDUAL_IDS[index]] = residuals[index]
	print("planar camelback return failure: ", JSON.stringify({
		"ok": route.get("ok", false),
		"errors": Array(route.get("errors", PackedStringArray())),
		"stage": failure.get("stage"),
		"reason": failure.get("reason"),
		"solver_status": failure.get("solver_status"),
		"evaluation_count": failure.get("evaluation_count"),
		"accepted_values": failure.get("accepted_values", []),
		"scaled_target_error": mapped,
	}))
	quit(0)


func _state_record(
	state: Dictionary, pose: Array, station: Vector3,
	forward: Vector3, right: Vector3, up: Vector3
) -> Dictionary:
	var from_station: Vector3 = state.position_m - station
	return {
		"position_station_m": {
			"forward": from_station.dot(forward),
			"cross": from_station.dot(right),
			"height": from_station.dot(up),
		},
		"cross_m": pose[0],
		"height_m": pose[1],
		"yaw_deg": rad_to_deg(pose[2]),
		"pitch_deg": rad_to_deg(pose[3]),
		"roll_deg": rad_to_deg(pose[4]),
		"speed_mps": state.speed_mps,
		"distance_m": state.distance_m,
		"time_s": state.time_s,
	}


func _old_camelback_spans(hand: float) -> Array:
	var area := RideProgram.COMPACT_PULSE_AREA
	var turn := -0.25001368 * hand
	var positive_g := 4.60068864065765
	var negative_g := -1.55352865073772
	var pullout_g := 5.2662035249371
	var pullout_hold_s := 0.01
	var pullup_s := 1.87949032 * 1.33555111055541
	var unload_s := 3.01169597 * 1.15 - 0.4
	var crest_s := 3.62587650 * 1.06
	var fall_s := 3.40
	var bank := -deg_to_rad(18.0) * hand
	return [
		Motion.span("camelback/pull-up", pullup_s, "moving",
			Motion.quintic(1.0, positive_g), Motion.compact_pulse(turn),
			Motion.constant(0.0), Motion.compact_pulse(bank / (pullup_s * area))),
		Motion.span("camelback/rise-hold", 0.4, "moving",
			Motion.constant(positive_g), Motion.compact_pulse(turn),
			Motion.constant(0.0), Motion.constant(0.0)),
		Motion.span("camelback/unload", unload_s, "moving",
			Motion.quintic(positive_g, negative_g), Motion.compact_pulse(turn),
			Motion.constant(0.0), Motion.compact_pulse(-bank / (unload_s * area))),
		Motion.span("camelback/crest", crest_s, "moving",
			Motion.constant(negative_g), Motion.compact_pulse(-turn),
			Motion.constant(0.0), Motion.compact_pulse(-bank / (crest_s * area))),
		Motion.span("camelback/fall", fall_s, "moving",
			Motion.quintic(negative_g, pullout_g), Motion.compact_pulse(-turn),
			Motion.constant(0.0), Motion.compact_pulse(bank / (fall_s * area))),
		Motion.span("camelback/pullout-hold", pullout_hold_s, "moving",
			Motion.constant(pullout_g), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
		Motion.span("camelback/pullout-release", 1.58 - pullout_hold_s, "moving",
			Motion.quintic(pullout_g, 1.0), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
	]
