extends SceneTree

const Motion := preload("res://motion.gd")
const RideGenerator := preload("res://generator.gd")
const RidePlanner := preload("res://ride_planner.gd")
const RideProgram := preload("res://ride_program.gd")
const RideReturnSolve := preload("res://ride_return_solve.gd")
const RideTerrain := preload("res://terrain.gd")

const SEED := 42
const BANK_RAD := PI / 3.0
const ROLL_DURATION_S := 0.9
const CORE_DURATIONS_S := [0.0, 1.5, 3.0, 4.5]


func _initialize() -> void:
	var decisions := RidePlanner.resolve(SEED)
	var terrain: Dictionary = RideTerrain.generate(
		decisions.streams[RidePlanner.STREAM_TERRAIN])
	var plan: Dictionary = RideGenerator._plan(terrain, decisions)
	if plan.has("ok") and not plan.ok:
		print("return heading probe planning failed: %s" % str(plan))
		quit(1)
		return
	var initial_state := RideGenerator._initial_state(plan.station)
	var hand := -float(plan.decisions.station_side)
	var story := RideProgram._story_from_plan(plan)
	var layout := RideProgram._layout_from_plan(plan)
	var return_hand := -hand
	var targets: Dictionary = story.targets
	var controls := RideProgram._prefix_controls_from_plan(plan)
	for direction in [-1, 1]:
		for core_duration_s in CORE_DURATIONS_S:
			_run_lane(direction, float(core_duration_s), initial_state, story, controls,
				layout, hand, return_hand, targets)
	quit(1)


func _run_lane(direction: int, core_duration_s: float, initial_state: Dictionary,
	story: Dictionary, controls: Array, layout: Dictionary, hand: float, return_hand: float,
	targets: Dictionary
) -> void:
	var spans: Array = []
	var metadata: Array = []
	var gestures: Array = []
	var propulsion := PackedInt32Array()
	RideProgram._add_story_prefix(
		spans, metadata, gestures, propulsion, hand, story, controls)
	spans.append_array(_heading_transition_spans(direction, core_duration_s))
	var camelback_spans: Array = []
	var camelback_metadata: Array = []
	var camelback_propulsion := PackedInt32Array()
	RideProgram._add_camelback(
		camelback_spans, camelback_metadata, camelback_propulsion)
	spans.append_array(camelback_spans)
	var route := Motion.integrate(
		initial_state, spans, RideProgram._settings(RideProgram.PRODUCTION_STEP_S))
	if not route.get("ok", false):
		print("return heading probe integration=%s" % str({
			"direction": direction,
			"core_duration_s": core_duration_s,
			"result": route,
		}))
		return
	var post_camelback := RideProgram._last_state(route)
	var capture := RideReturnSolve._capture_residuals(post_camelback, layout)
	print("return heading probe handoff=%s" % str({
		"direction": direction,
		"core_duration_s": core_duration_s,
		"station_local_pose": _station_local_pose(post_camelback, layout),
		"capture_residuals": {
			"cross_track_m": capture[0],
			"height_m": capture[1],
			"yaw_rad": capture[2],
			"pitch_rad": capture[3],
			"roll_rad": capture[4],
		},
		"speed_mps": post_camelback.speed_mps,
	}))
	var solved_return := RideReturnSolve._solve_return(
		post_camelback, layout, return_hand, RideReturnSolve.RETURN_SEED, targets)
	print("return heading probe solve=%s" % str({
		"direction": direction,
		"core_duration_s": core_duration_s,
		"result": solved_return,
	}))


func _heading_transition_spans(direction: int, core_duration_s: float) -> Array:
	var bank_rad := float(direction) * BANK_RAD
	var durations := [ROLL_DURATION_S]
	var roll_in := RideReturnSolve._roll_ramp(durations, 0.0, bank_rad)
	var spans := RideReturnSolve._roll_bank_spans(
		["heading-sweep/roll-in"], durations, roll_in)
	if core_duration_s > 0.0:
		spans.append(Motion.span(
			"heading-sweep/core", core_duration_s, "moving",
			Motion.constant(1.0 / cos(bank_rad)), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0), "heading-sweep"))
	var roll_out := RideReturnSolve._roll_ramp(durations, bank_rad, 0.0)
	spans.append_array(RideReturnSolve._roll_bank_spans(
		["heading-sweep/roll-out"], durations, roll_out))
	return spans


func _station_local_pose(state: Dictionary, layout: Dictionary) -> Dictionary:
	var forward: Vector3 = layout.station_tangent.normalized()
	var up: Vector3 = layout.station_up.normalized()
	var right := forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	var offset: Vector3 = state.position_m - layout.station_position_m
	var tangent: Vector3 = state.tangent.normalized()
	var rider_up: Vector3 = state.rider_up.normalized()
	return {
		"position_m": Vector3(offset.dot(forward), offset.dot(up), offset.dot(right)),
		"tangent": Vector3(tangent.dot(forward), tangent.dot(up), tangent.dot(right)),
		"rider_up": Vector3(rider_up.dot(forward), rider_up.dot(up), rider_up.dot(right)),
	}
