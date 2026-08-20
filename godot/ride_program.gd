class_name RideProgram
extends RefCounted

const Motion := preload("res://motion.gd")
const RidePlanner := preload("res://ride_planner.gd")
const RidePrefixSolve := preload("res://ride_prefix_solve.gd")
const RideReturnSolve := preload("res://ride_return_solve.gd")

const GENERATOR_VERSION := "time-domain-v1"
const ROLLING_MPS2 := 0.08
const AERO_PER_M := 0.000075
const COMPACT_PULSE_AREA := Motion.COMPACT_PULSE_AREA
const COARSE_STEP_S := 0.05
const FINE_STEP_S := 0.025
const PRODUCTION_STEP_S := 0.01
## The two authored opener/act-one force literals the prefix-closure refusal evidence named
## (`ride_planner.gd`, the measured 2026-08-15 table): before the closure solve, +-0.005 on either
## moved the dive chord by over 100 m and the prefix could not be placed. They are recipe defaults
## and nothing else — the drawn target overrides them — but they are named here so the perturbation
## tests measure their offset from the authored value rather than carrying a second copy of it.
const OPENER_DROP_CORE_LATERAL_G := 0.6998747
const ACT_ONE_LOOP_POSITIVE_G := 4.6
## The canonical (undrawn) role order. It is the default a caller gets when no plan sequence is
## supplied; a built ride is always validated against the sequence its own plan declares.
const MATERIAL_ROLE_IDS := [
	"station-launch", "opener-twisted-drop", "opener-teardrop", "opener-release",
	"act-one-immelmann", "act-one-cutback", "act-one-loop", "act-one-airtime",
	"act-one-wave", "climb-lsm2", "clifftop-slow-crest", "clifftop-outward-rim",
	"outward-dive", "tunnel-lsm3", "record-release-turn", "camelback", "return-turn-a", "return-height-a",
	"return-turn-b", "return-height-b", "terminal-capture-brakes",
]
## Nominal role lengths, keyed by role id: a plan authors the roles its drawn sequence declares,
## so the nominal a role is checked against cannot be an index into one fixed role list.
const ROLE_NOMINAL_LENGTH_M := {
	"station-launch": 180.0, "opener-twisted-drop": 620.0, "opener-teardrop": 650.0,
	"opener-release": 330.0, "act-one-immelmann": 430.0, "act-one-cutback": 310.0,
	"act-one-loop": 360.0, "act-one-airtime": 260.0, "act-one-wave": 240.0,
	"climb-lsm2": 600.0, "clifftop-slow-crest": 50.0, "clifftop-outward-rim": 90.0,
	"outward-dive": 420.0, "tunnel-lsm3": 180.0, "record-release-turn": 365.0,
	"camelback": 1000.0,
	"return-turn-a": 480.0, "return-height-a": 420.0, "return-turn-b": 500.0,
	"return-height-b": 520.0, "terminal-capture-brakes": 230.0,
}


## The fixed story prefix, integrated once in its station-local frame so the generator can place
## the ride on terrain. `story` carries the planner's drawn sequence and resolved targets; an
## empty story reproduces the canonical undrawn recipe exactly. `closure_target`, when present,
## first solves the four flex-span durations against its four station-local aim bands; with no
## target the prefix is the authored one, unchanged.
static func terrain_story_capability(station_side: int, story: Dictionary = {},
	closure_target: Dictionary = {}
) -> Dictionary:
	if station_side != -1 and station_side != 1:
		return _failure("station_side must be -1 or 1", "planning")
	var closure := {}
	var controls: Array = RidePrefixSolve.PREFIX_SEED
	if not closure_target.is_empty():
		closure = RidePrefixSolve._solve_prefix_closure(station_side, story, closure_target)
		if not closure.get("ok", false):
			return closure
		controls = closure.report.accepted_values
	var program := RidePrefixSolve._prefix_program(station_side, story, controls)
	if not program.ok:
		if program.station_end < 0 or program.opener_end <= program.station_end:
			return _failure(
				"terrain story capability omitted the station/opener footprint", "planning")
		return _failure("terrain story capability omitted the cliff-dive handoff", "planning")
	var tunnel_end_span: int = program.tunnel_end
	var trajectory := Motion.integrate(
		RidePrefixSolve._prefix_initial_state(), program.spans.slice(0, tunnel_end_span + 1),
		_settings(PRODUCTION_STEP_S))
	if not trajectory.get("ok", false):
		return _failure("terrain story capability failed integration", "planning",
			{"errors": trajectory.get("errors", [])})
	var dive_start_sample: int = trajectory.span_index.find(program.dive_start)
	var dive_end_sample: int = trajectory.span_index.rfind(program.dive_end)
	if dive_start_sample < 0 or dive_end_sample < dive_start_sample \
			or trajectory.position_m.size() < 2 \
			or int(trajectory.span_index[-1]) != tunnel_end_span:
		return _failure("terrain story capability omitted the native dive footprint", "planning")
	var entry := {"position_m": trajectory.position_m[dive_start_sample],
		"tangent": trajectory.tangent[dive_start_sample],
		"rider_up": trajectory.rider_up[dive_start_sample],
		"speed_mps": trajectory.speed_mps[dive_start_sample]}
	var dive_exit_offset_m: Vector3 = trajectory.position_m[dive_end_sample]
	var dive_positions_m: PackedVector3Array = trajectory.position_m.slice(
		dive_start_sample, dive_end_sample + 1)
	var dive_rider_up: PackedVector3Array = trajectory.rider_up.slice(
		dive_start_sample, dive_end_sample + 1)
	# The full route reassigns the exact tunnel/camelback seam to the camelback.
	# Publish the preceding sample so planning and accepted role bounds use the same endpoint.
	# The closure residual measures the terminal sample instead, so that it does not move with the
	# integration step; the one production step between the two is published with the footprint,
	# because the placement that consumes the pre-seam sample has to aim through it.
	var tunnel_exit_offset_m: Vector3 = trajectory.position_m[-2]
	var tunnel_exit_step_m: Vector3 = trajectory.position_m[-1] - tunnel_exit_offset_m
	var dive_outward_delta_m := float(station_side) \
		* (float(dive_exit_offset_m.z) - float(entry.position_m.z))
	if not dive_exit_offset_m.is_finite() or not tunnel_exit_offset_m.is_finite() \
			or dive_positions_m.is_empty() or dive_positions_m.size() != dive_rider_up.size() \
			or not is_finite(dive_outward_delta_m) or dive_outward_delta_m <= 0.0:
		return _failure("terrain story capability produced a non-outward dive footprint", "planning")
	# `program.ok` above already guarantees station_end < opener_end within the fully-integrated
	# span range, so both samples are present and ordered here; the station/opener failure is
	# reported at the `program.ok` check instead of here.
	var opener_end_sample: int = trajectory.span_index.rfind(program.opener_end)
	var station_end_sample: int = trajectory.span_index.rfind(program.station_end)
	if not closure.is_empty():
		var accepted := RidePrefixSolve._accept_prefix_closure(closure, trajectory, program)
		if not accepted.get("ok", false):
			return accepted
	var published := {"ok": true, "capability_id": "material-v1-prefix-r12@9",
		"planning_integrations": 1,
		"role_13_entry": {"offset_m": entry.position_m, "tangent": entry.tangent,
			"rider_up": entry.rider_up, "speed_mps": entry.speed_mps},
		"dive_footprint": {"outward_delta_m": dive_outward_delta_m,
			"dive_exit_offset_m": dive_exit_offset_m,
			"tunnel_exit_offset_m": tunnel_exit_offset_m,
			"tunnel_exit_step_m": tunnel_exit_step_m,
			"positions_m": dive_positions_m, "rider_up": dive_rider_up},
		"station_opener": {
			"positions_m": trajectory.position_m.slice(0, opener_end_sample + 1),
			"rider_up": trajectory.rider_up.slice(0, opener_end_sample + 1),
			"station_sample_count": station_end_sample + 1,
		},
		"scale": {"route_vertical_envelope_m": Vector2(290.0, 305.0),
			"dive_drop_m": Vector2(240.0, 250.0),
			"camel_prominence_m": Vector2(245.0, 255.0)}}
	if not closure.is_empty():
		published["closure_plan"] = closure.report
	return published


static func compile(plan: Dictionary, initial_state: Dictionary) -> Dictionary:
	var plan_check := _validate_plan(plan)
	if not plan_check.ok:
		return plan_check
	var layout := _layout_from_plan(plan)
	var station_error := _validate_station_layout(layout, initial_state)
	if not station_error.is_empty():
		return _failure(station_error, "input")
	var spans: Array = []
	var metadata: Array = []
	var gestures: Array = []
	var propulsion := PackedInt32Array()
	# Canonical +Z maps outward for station_side=+1 and inward for -1. Mirror the
	# authored lateral forces so the shared story always approaches the escarpment.
	var hand := -float(plan.decisions.station_side)
	var story := _story_from_plan(plan)
	var targets: Dictionary = story.targets
	# The production span program is built from the plan's own accepted closure controls, so the
	# ride that gets built and the footprint the generator placed are the same prefix.
	_add_story_prefix(spans, metadata, gestures, propulsion, hand, story,
		_prefix_controls_from_plan(plan))
	var fixed_prefix := Motion.integrate(initial_state, spans, _settings(PRODUCTION_STEP_S))
	if not fixed_prefix.get("ok", false):
		return _failure("upstream return handoff failed integration", "return")
	var fixed_prefix_state := _last_state(fixed_prefix)
	var variable_prefix_start := spans.size()
	var return_hand := -hand

	_begin_gesture(gestures, "record-release-turn", spans.size(), "record-release-turn")
	_add_record_release_turn(spans, metadata, propulsion, return_hand)
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "marquee-camelback", spans.size(), "hill")
	_add_camelback(spans, metadata, propulsion)
	_end_gesture(gestures, metadata, spans.size() - 1)

	var variable_prefix_spans: Array = spans.slice(variable_prefix_start)
	var solved_return := RideReturnSolve._solve_return(fixed_prefix_state, layout,
		return_hand, RideReturnSolve.RETURN_SEED, targets, variable_prefix_spans)
	if not solved_return.ok:
		return solved_return
	_set_record_release_duration(spans, solved_return.parameters)
	var return_prefix := Motion.integrate(initial_state, spans, _settings(PRODUCTION_STEP_S))
	if not return_prefix.get("ok", false):
		return _failure("upstream return handoff failed integration", "return")
	var settings := _settings(PRODUCTION_STEP_S)
	_begin_gesture(gestures, "raceway-return", spans.size())
	_add_raceway(spans, metadata, propulsion, solved_return.parameters, return_hand,
		solved_return.initial_bank_rad, targets)
	_end_gesture(gestures, metadata, spans.size() - 1)

	var prefix := Motion.integrate(initial_state, spans, settings)
	if not prefix.get("ok", false):
		return _failure("prefix integration failed: %s" % ", ".join(
			prefix.get("errors", [])), "prefix")
	var capture_start := _last_state(prefix)
	var capture := RideReturnSolve._solve_capture(capture_start, layout, _settings(FINE_STEP_S))
	if not capture.ok:
		return capture
	var capture_spans: Array = RideReturnSolve._capture_spans(capture.coefficients)
	var capture_route := Motion.integrate(capture_start, capture_spans, settings)
	if not capture_route.get("ok", false):
		return RideReturnSolve._capture_failure("accepted capture did not reintegrate",
			capture.unique_evaluations, capture.residuals, capture.margins)
	var production_residuals := RideReturnSolve._capture_residuals(
		_last_state(capture_route), layout)
	var production_margins := RideReturnSolve._capture_margins(
		capture.coefficients, capture_route, layout)
	if not RideReturnSolve._capture_converged(production_residuals):
		return RideReturnSolve._capture_failure("capture missed its production boundary",
			capture.unique_evaluations, production_residuals, production_margins)
	for margin in production_margins.values():
		if not is_finite(float(margin)) or float(margin) < 0.0:
			return RideReturnSolve._capture_failure("production capture violates an inequality",
				capture.unique_evaluations, production_residuals, production_margins)
	var brake := RideReturnSolve._solve_brakes(_last_state(capture_route), layout)
	if not brake.ok:
		return brake

	_begin_gesture(gestures, "brakes-station-capture", spans.size())
	_add_capture_and_brakes(spans, metadata, propulsion, capture.coefficients, brake)
	_end_gesture(gestures, metadata, spans.size() - 1)
	var minimum_speeds := PackedFloat64Array()
	var tunnels: Array[Vector2i] = []
	for record in metadata:
		minimum_speeds.append(record.minimum_speed_mps)
	for gesture in gestures:
		gesture["peak_profile_normal_onset_estimate_gps"] = _peak_profile_normal_onset_estimate(
			spans, int(gesture.first_span), int(gesture.last_span))
		for span_index in range(int(gesture.first_span), int(gesture.last_span) + 1):
			metadata[span_index]["gesture_id"] = gesture.story_slot_id
			metadata[span_index]["story_slot_id"] = gesture.story_slot_id
		if gesture.story_slot_id == "tunnel-lsm3":
			tunnels.append(Vector2i(gesture.first_span, gesture.last_span))

	var seam_errors := _validate_control_seams(spans)
	if not seam_errors.is_empty():
		return {"ok": false, "errors": seam_errors}
	var role_spans := material_role_spans(spans, story.sequence)
	if not role_spans.ok:
		return _failure("material role span ownership is incomplete", "role_spans",
			{"observed": {"ownership_errors": role_spans.errors}})
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"generator_version": GENERATOR_VERSION,
		"plan": plan.duplicate(true),
		"spans": spans,
		"span_metadata": metadata,
		"gesture_spans": gestures,
		"role_spans": role_spans.role_spans,
		"element_intents": material_element_intents(story.sequence),
		"propulsion_by_span": propulsion,
		"minimum_speed_by_span": minimum_speeds,
		"tunnel_span_ranges": tunnels,
		"return_plan": solved_return.report,
		"return_entry_gate": solved_return.report.get("return_entry_gate", {}),
		"role_allocations_m": plan_check.allocations,
		"capture_plan": {
			"status": "solved",
			"coefficients": capture.coefficients,
			"coefficient_ids": ["early_lateral", "late_lateral", "early_normal",
				"late_normal", "roll_area_rad"],
			"coefficient_bounds": RideReturnSolve.CAPTURE_COEFFICIENT_BOUNDS,
			"unique_evaluations": capture.unique_evaluations,
			"max_unique_evaluations": RideReturnSolve.MAX_CAPTURE_EVALUATIONS,
			"residual_ids": ["cross_track_m", "height_m", "yaw_rad", "pitch_rad", "roll_rad"],
			"residual_tolerances": RideReturnSolve.CAPTURE_RESIDUAL_TOLERANCES,
			"coarse_residual_tolerances": RideReturnSolve.CAPTURE_COARSE_RESIDUAL_TOLERANCES,
			"residuals": capture.residuals,
			"fine_residuals": capture.fine_residuals,
			"production_residuals": production_residuals,
			"margins": production_margins,
			"conditioning": capture.conditioning,
			"positive_drive_allowed": false,
		},
		"brake_plan": brake.report,
		"terminal_contract": {
			"station_position_m": layout.station_position_m,
			"station_tangent": layout.station_tangent,
			"station_up": layout.station_up,
			"terminal_speed_mps": 1.0,
			"position_tolerance_m": 0.1,
			"angle_tolerance_rad": 0.00002,
			"speed_tolerance_mps": 0.001,
		},
		"settings": _settings(PRODUCTION_STEP_S),
	}


static func _add_story_prefix(
	spans: Array, metadata: Array, gestures: Array, propulsion: PackedInt32Array, hand: float,
	story: Dictionary = {}, controls: Array = RidePrefixSolve.PREFIX_SEED
) -> void:
	var targets: Dictionary = story.get("targets", {})
	var act_one_order: Array = RidePlanner.act_one_order(
		story.get("sequence", RidePlanner.canonical_role_ids()))
	_begin_gesture(gestures, "station-launch", spans.size(), "launch")
	# Do-Dodonpa-class air/hydraulic entry launch. The 2041 credit is spent on peak drive,
	# not on Delta-v: the plateau rises 3.2 -> 3.9 g and the pulse shortens to hold the same
	# drive-time integral, so the opener and act one keep their proven entry speeds while the
	# launch itself reads punchier. See
	# docs/superpowers/specs/2026-08-15-record-launch-derivation.md section 1.
	var launch_peak_g := 3.9
	var launch_core_s := 0.8038
	var launch_release_s := 1.762572
	_add(spans, metadata, propulsion, "launch/ramp", 0.3903354, "station",
		1.0, 0.0, Motion.quintic(0.0, launch_peak_g), 0.0, "launch", 1, 0.0, "launch")
	_add(spans, metadata, propulsion, "launch/core", launch_core_s, "moving",
		1.0, 0.0, launch_peak_g, 0.0, "launch", 1, 2.0, "launch")
	_add(spans, metadata, propulsion, "launch/release", launch_release_s, "moving",
		1.0, 0.0, Motion.quintic(launch_peak_g, 0.0), 0.0, "launch", 1, 2.0, "launch")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "opener", spans.size(), "twisted_drop")
	_add_opener(spans, metadata, propulsion, hand, targets)
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "act-one", spans.size())
	_add_story_act_one(spans, metadata, propulsion, hand, targets, act_one_order)
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "escarpment-climb", spans.size())
	var climb_drive_g := 0.29367873763844
	_add(spans, metadata, propulsion, "climb/pull-up", 0.98392993, "moving",
		Motion.quintic(1.0, 3.37796602), 0.0, Motion.quintic(0.0, climb_drive_g),
		0.0, "lsm2", 2)
	_add(spans, metadata, propulsion, "climb/powered-settle", 0.98392993, "moving",
		Motion.quintic(3.37796602, 0.87362258024053), 0.0, climb_drive_g, 0.0, "lsm2", 2)
	_add(spans, metadata, propulsion, "climb/powered-core", float(controls[0]), "moving",
		0.87362258024053, 0.0, climb_drive_g, 0.0, "lsm2", 2)
	_add(spans, metadata, propulsion, "climb/drive-release", 0.98392993, "moving",
		0.87362258024053, 0.0, Motion.quintic(climb_drive_g, 0.0), 0.0, "lsm2", 2)
	_add(spans, metadata, propulsion, "climb/pull-over", float(controls[1]), "moving",
		Motion.quintic(0.87362258024053, 0.72152814), 0.0, 0.0, 0.0,
		"unpowered-climb")
	_add(spans, metadata, propulsion, "climb/level", 3.20659393, "moving",
		Motion.quintic(0.72152814, 1.0), 0.0, 0.0, 0.0, "unpowered-climb")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "clifftop-suspense", spans.size())
	var slow_bank := deg_to_rad(39.1243426617973)
	# The crawl lays over across a shoulder half again as long as it used to and holds for
	# correspondingly less: issue 20's stepping showed up here as a 97 deg/s burst either side of a
	# 2.4 s flat hold. Unsolved, the crest's total time is the authored beat, so it keeps its length
	# and the downstream handoff, which the return solve will not re-converge from its fixed seed
	# without; the closure solve moves the hold and re-closes that handoff through its own record
	# residual. The shoulder cannot grow further: the clifftop's unwrapped heading work has a
	# 160 deg floor and its centreline vertical variation a 3 m one, and rolling for longer at a
	# lower average bank spends both.
	var slow_shoulder_s := RidePrefixSolve.PREFIX_SLOW_SHOULDER_S
	var slow_core_s := float(controls[2])
	# Drawn per seed: how firmly the crawl is held over the crest, and how far the rim turn lays
	# out over the edge. The suspense beat is reference-scale by contract, so both stay inside
	# the clifftop's declared force and heading bands rather than scaling toward the records.
	var slow_normal := RidePlanner.target(
		targets, "clifftop-slow-crest", "crest_normal_g", 1.2403722803347)
	var slow_roll := slow_bank / (slow_shoulder_s * Motion.PLATEAU_PULSE_AREA)
	_add(spans, metadata, propulsion, "rim/slow-crest-in", slow_shoulder_s, "moving",
		Motion.quintic(1.0, slow_normal), 0.0, 0.0,
		Motion.plateau_pulse(slow_roll * hand), "slow-crest")
	_add(spans, metadata, propulsion, "rim/slow-crest-core", slow_core_s, "moving",
		slow_normal, 0.0, 0.0, 0.0, "slow-crest")
	_add(spans, metadata, propulsion, "rim/slow-crest-out", slow_shoulder_s, "moving",
		Motion.quintic(slow_normal, 1.0), 0.0, 0.0,
		Motion.plateau_pulse(-slow_roll * hand), "slow-crest")
	var rim_bank := RidePlanner.target(
		targets, "clifftop-outward-rim", "bank_rad", deg_to_rad(49.9686662300867))
	var rim_normal := 1.0 / cos(rim_bank)
	# The roll shoulders scale with the drawn bank, so laying further over costs time instead of
	# buying a faster roll: the authored roll-in rate is what the envelope was cleared for, and it
	# stays fixed at every drawn bank. The rim lays over through a plateau pulse rather than a
	# compact one (issue 20): the same bank arrives at 75 deg/s instead of 115, held at a steady
	# rate through the middle third of the shoulder instead of spiking and dying inside it. The
	# arc is derived so the beat's total time is fixed whatever bank is drawn — the clifftop sits
	# upstream of the camelback handoff, and the return solve does not re-converge from its fixed
	# seed when that handoff moves.
	var rim_shoulder_s := 1.0 * rim_bank / deg_to_rad(49.9686662300867)
	var rim_roll := rim_bank / (Motion.PLATEAU_PULSE_AREA * rim_shoulder_s)
	var rim_arc_s := 4.01632319951879 - 2.0 * rim_shoulder_s
	_add(spans, metadata, propulsion, "rim/outward-bank", rim_shoulder_s, "moving",
		Motion.quintic(1.0, rim_normal), 0.0, 0.0,
		Motion.plateau_pulse(rim_roll * hand), "outward-rim", 0, 2.0, "turn")
	_add(spans, metadata, propulsion, "rim/outward-arc", rim_arc_s, "moving",
		rim_normal, 0.0, 0.0, 0.0, "outward-rim", 0, 2.0, "turn")
	_add(spans, metadata, propulsion, "rim/outward-release", rim_shoulder_s, "moving",
		Motion.quintic(rim_normal, 1.0), 0.0, 0.0,
		Motion.plateau_pulse(-rim_roll * hand), "outward-rim", 0, 2.0, "turn")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "cliff-dive", spans.size(), "dive")
	# Keep the car above the shelf while it commits outward; the vertical fall begins
	# only after the track has reached the escarpment face.
	var dive_bank := deg_to_rad(25.0)
	var dive_turn_normal := 1.0 / cos(dive_bank)
	var dive_roll := dive_bank / (0.8 * COMPACT_PULSE_AREA)
	_add(spans, metadata, propulsion, "dive/outward-bank", 0.8, "moving",
		Motion.quintic(1.0, dive_turn_normal), 0.0, 0.0,
		Motion.compact_pulse(dive_roll * hand), "commit")
	_add(spans, metadata, propulsion, "dive/face-approach", float(controls[3]), "moving",
		dive_turn_normal, 0.0, 0.0, 0.0, "commit")
	_add(spans, metadata, propulsion, "dive/outward-release", 0.8, "moving",
		Motion.quintic(dive_turn_normal, 1.0), 0.0, 0.0,
		Motion.compact_pulse(-dive_roll * hand), "commit")
	_add(spans, metadata, propulsion, "dive/commit", 1.08383328, "moving",
		Motion.quintic(1.0, -1.17822413), 0.0, 0.0, 0.0, "commit")
	_add(spans, metadata, propulsion, "dive/vertical-entry", 2.28378690, "moving",
		Motion.quintic(-1.17822413, 0.0), 0.0, 0.0, 0.0, "vertical-entry")
	_add(spans, metadata, propulsion, "dive/core", 1.12, "moving",
		0.0, 0.0, 0.0, 0.0, "core", 0, 2.0, "dive")
	_add(spans, metadata, propulsion, "dive/pullout", 1.58495784, "moving",
		Motion.quintic(0.0, 4.87237708), 0.0, 0.0, 0.0, "pullout")
	_add(spans, metadata, propulsion, "dive/pullout-release", 3.05526825, "moving",
		Motion.quintic(4.87237708, 1.0), 0.0, 0.0, 0.0, "exit")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "tunnel-lsm3", spans.size())
	# The record launch. 1.33 g over the 150-220 m tunnel booster lifts the dive exit to the
	# 338-344 km/h band; per-train power peaks near 15 MW at ~94 m/s, record-scale but credible
	# for 2041. See docs/superpowers/specs/2026-08-15-record-launch-derivation.md section 2.
	var lsm3_drive_g := 1.33
	_add(spans, metadata, propulsion, "tunnel/lsm3-entry", 0.30, "moving",
		Motion.constant(1.0), Motion.constant(0.0), Motion.quintic(0.0, lsm3_drive_g),
		Motion.constant(0.0), "core", 3)
	_add(spans, metadata, propulsion, "tunnel/lsm3-core", 1.633337, "moving",
		1.0, 0.0, lsm3_drive_g, 0.0, "core", 3)
	_add(spans, metadata, propulsion, "tunnel/lsm3-release", 0.30, "moving",
		1.0, 0.0, Motion.quintic(lsm3_drive_g, 0.0), 0.0, "core", 3)
	_end_gesture(gestures, metadata, spans.size() - 1)



static func _add_record_release_turn(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, hand: float = 1.0,
	core_duration_s: float = RideReturnSolve.RECORD_RELEASE_CORE_DURATION_S
) -> void:
	var bank_rad := hand * deg_to_rad(60.0)
	var banked_normal := 1.0 / cos(bank_rad)
	var roll_in := RideReturnSolve._roll_ramp([0.9], 0.0, bank_rad)
	var roll_out := RideReturnSolve._roll_ramp([0.9], bank_rad, 0.0)
	_add(spans, metadata, propulsion, "record-release-turn/roll-in", 0.9, "moving",
		Motion.quintic(1.0, banked_normal), 0.0, 0.0, roll_in.roll[0],
		"record-release-turn", 0, 2.0, "record-release-turn", "record-release-roll-in")
	_add(spans, metadata, propulsion, "record-release-turn/core", core_duration_s, "moving",
		banked_normal, 0.0, 0.0, 0.0,
		"record-release-turn", 0, 2.0, "record-release-turn", "record-release-core")
	_add(spans, metadata, propulsion, "record-release-turn/roll-out", 0.9, "moving",
		Motion.quintic(banked_normal, 1.0), 0.0, 0.0, roll_out.roll[0],
		"record-release-turn", 0, 2.0, "record-release-turn", "record-release-roll-out")


static func _set_record_release_duration(spans: Array, parameters: Array) -> void:
	var control_index := RideReturnSolve.RETURN_SCALAR_IDS.find("record_release_core_duration_s")
	if control_index < 0 or control_index >= parameters.size():
		return
	for index in spans.size():
		var span: Dictionary = spans[index]
		if str(span.get("span_id", "")) != "record-release-turn/core":
			continue
		spans[index] = Motion.span(str(span.span_id), float(parameters[control_index]),
			str(span.mode), span.normal_g, span.lateral_g, span.drive_g, span.roll_rate_rad_s,
			str(span.get("transition_id", "")))
		return


static func _add_camelback(
	spans: Array, metadata: Array, propulsion: PackedInt32Array
) -> void:
	var positive_g := 4.60068864065765
	var negative_g := -1.55352865073772
	var pullout_g := 5.2662035249371
	var pullup_s := 1.87949032 * 1.33555111055541
	var unload_s := 3.01169597 * 1.15 - 0.4
	var crest_s := 3.62587650 * 1.06
	# The fall is what makes the marquee stand ~250 m above its valley: at the record entry
	# speed the same normal-g ramp descends less per second, so the fall lengthens with the
	# camelback entry speed rather than the crest being scaled.
	var fall_s := 3.40
	_add(spans, metadata, propulsion, "camelback/pull-up",
		pullup_s, "moving",
		Motion.quintic(1.0, positive_g), 0.0, 0.0, 0.0, "rise")
	_add(spans, metadata, propulsion, "camelback/unload",
		unload_s, "moving", Motion.quintic(positive_g, negative_g),
		0.0, 0.0, 0.0, "rise")
	_add(spans, metadata, propulsion, "camelback/crest", crest_s, "moving",
		Motion.quintic(negative_g, negative_g * 0.88), 0.0, 0.0, 0.0, "crest")
	_add(spans, metadata, propulsion, "camelback/fall", fall_s, "moving",
		Motion.quintic(negative_g * 0.88, pullout_g), 0.0, 0.0, 0.0, "fall")
	_add(spans, metadata, propulsion, "camelback/pullout-release",
		1.58, "moving",
		Motion.quintic(pullout_g, 1.0), 0.0, 0.0, 0.0, "exit")


static func _add_opener(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, hand: float,
	targets: Dictionary = {}
) -> void:
	var area := COMPACT_PULSE_AREA
	var unbank_ramp_s := 0.115
	var unbank_hold_s := 0.22012288
	var normal_recovery_s := 0.18512288
	var normal_mid_g := 3.46722071542319
	var unbank_peak_rad_s := 0.6981317 / (unbank_ramp_s + unbank_hold_s)
	# Drawn per seed: how hard the twisted drop carves through its core, and how strongly the
	# teardrop is loaded over the top. Both are held constant across the spans that enter, hold
	# and leave the shape, so the C2 control seams stay exact at any drawn value.
	var drop_lateral_g := RidePlanner.target(
		targets, "opener-twisted-drop", "core_lateral_g", OPENER_DROP_CORE_LATERAL_G)
	var teardrop_normal_g := RidePlanner.target(
		targets, "opener-teardrop", "overbank_normal_g", 1.62427620902668)
	_add(spans, metadata, propulsion, "drop/rise", 0.74281671, "moving",
		Motion.quintic(1.0, 4.99988044), 0.0, 0.0, 0.0,
		"twisted-drop", 0, 2.0, "twisted_drop")
	_add(spans, metadata, propulsion, "drop/bank-unload", 1.99998272, "moving",
		Motion.quintic(4.99988044, -0.58313246),
		Motion.quintic(0.0, drop_lateral_g * hand), 0.0,
		Motion.compact_pulse(0.976431 * hand / (area * 1.99998272)),
		"twisted-drop", 0, 2.0, "twisted_drop")
	_add(spans, metadata, propulsion, "drop/core", 2.13984425, "moving",
		-0.58313246, drop_lateral_g * hand, 0.0, 0.0,
		"twisted-drop", 0, 2.0, "twisted_drop")
	_add(spans, metadata, propulsion, "drop/pullout", 3.67807081, "moving",
		Motion.quintic(-0.58313246, 4.99988044),
		Motion.quintic(drop_lateral_g * hand, 0.0), 0.0, 0.0,
		"twisted-drop", 0, 2.0, "twisted_drop")
	_add(spans, metadata, propulsion, "drop/unbank",
		2.0 * unbank_ramp_s + unbank_hold_s, "moving",
		Motion.staged([
			Motion.quintic(4.99988044, normal_mid_g), Motion.quintic(normal_mid_g, 1.0),
			Motion.constant(1.0), Motion.constant(1.0)],
			[unbank_ramp_s, normal_recovery_s, unbank_hold_s - normal_recovery_s,
				unbank_ramp_s]),
		0.0, 0.0,
		Motion.staged([
			Motion.quintic(0.0, -unbank_peak_rad_s * hand),
			Motion.constant(-unbank_peak_rad_s * hand),
			Motion.constant(-unbank_peak_rad_s * hand),
			Motion.quintic(-unbank_peak_rad_s * hand, 0.0)],
			[unbank_ramp_s, normal_recovery_s, unbank_hold_s - normal_recovery_s,
				unbank_ramp_s]),
		"twisted-drop", 0, 2.0, "twisted_drop")

	var teardrop_shoulder_s := 1.9827842973471
	var teardrop_bank_in := 1.35023678543837
	var teardrop_bank_out := 1.39946086214734
	_add(spans, metadata, propulsion, "teardrop/bank-in", teardrop_shoulder_s, "moving",
		Motion.quintic(1.0, teardrop_normal_g),
		Motion.quintic(0.0, -0.71527254431284 * hand),
		0.0, Motion.compact_pulse(teardrop_bank_in * hand / (area * teardrop_shoulder_s)),
		"teardrop", 0, 2.0, "overbank")
	_add(spans, metadata, propulsion, "teardrop/overbanked-arc", 5.13321184, "moving",
		teardrop_normal_g, -0.71527254431284 * hand, 0.0, 0.0,
		"teardrop", 0, 2.0, "overbank")
	_add(spans, metadata, propulsion, "teardrop/bank-out", teardrop_shoulder_s, "moving",
		Motion.quintic(teardrop_normal_g, 1.0),
		Motion.quintic(-0.71527254431284 * hand, 0.0),
		0.0, Motion.compact_pulse(-teardrop_bank_out * hand / (area * teardrop_shoulder_s)),
		"teardrop", 0, 2.0, "overbank")

	_add(spans, metadata, propulsion, "release/rise", 0.75, "moving",
		Motion.quintic(1.0, 3.0), 0.0, 0.0, 0.0, "release", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "release/unload", 1.25, "moving",
		Motion.quintic(3.0, -0.4), 0.0, 0.0, 0.0, "release", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "release/crest", 1.69130027908317, "moving",
		-0.4, 0.0, 0.0, 0.0, "release", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "release/fall", 1.67317387630012, "moving",
		Motion.quintic(-0.4, 3.0), 0.0, 0.0, 0.0, "release", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "release/settle", 0.4, "moving",
		Motion.quintic(3.0, 1.0), 0.0, 0.0, 0.0, "release", 0, 2.0, "hill")


## Act one, authored in the order the plan declares. The Immelmann is the fixed physics anchor
## and always opens; the remaining cells are written in their drawn order, and every cell enters
## and leaves at level 1.0 g so the order itself never breaks a control seam.
static func _add_story_act_one(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, hand: float,
	targets: Dictionary = {}, order: Array = []
) -> void:
	var authored: Array = order if not order.is_empty() \
		else RidePlanner.act_one_order(RidePlanner.canonical_role_ids())
	for role_id in authored:
		match str(role_id):
			"act-one-immelmann":
				_add_act_one_immelmann(spans, metadata, propulsion, hand)
			"act-one-cutback":
				_add_act_one_cutback(spans, metadata, propulsion, hand)
			"act-one-loop":
				_add_act_one_loop(spans, metadata, propulsion, hand, targets)
			"act-one-airtime":
				_add_act_one_airtime(spans, metadata, propulsion, hand, targets)
			"act-one-wave":
				_add_act_one_wave(spans, metadata, propulsion, hand, targets)


static func _add_act_one_immelmann(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, hand: float
) -> void:
	var area := COMPACT_PULSE_AREA
	_add(spans, metadata, propulsion, "act-one/immelmann-entry", 0.33, "moving",
		Motion.quintic(1.0, 5.2), 0.0, 0.0, 0.0, "giant-inversion", 0, 2.0, "immelmann")
	_add(spans, metadata, propulsion, "act-one/immelmann-hold", 2.93637456, "moving",
		5.2, 0.0, 0.0, 0.0, "giant-inversion", 0, 2.0, "immelmann")
	_add(spans, metadata, propulsion, "act-one/immelmann-unload", 0.49, "moving",
		Motion.quintic(5.2, -1.0), 0.0, 0.0, 0.0,
		"giant-inversion", 0, 2.0, "immelmann")
	_add(spans, metadata, propulsion, "act-one/immelmann-roll", 2.07647312, "moving",
		Motion.quintic(-1.0, 0.0), Motion.compact_pulse(1.13212909 * hand), 0.0,
		Motion.compact_pulse(PI * hand / (2.0 * area * 2.07647312)),
		"giant-inversion", 0, 2.0, "immelmann")
	_add(spans, metadata, propulsion, "act-one/immelmann-recover", 2.47289653, "moving",
		Motion.quintic(0.0, 2.28038016), Motion.compact_pulse(1.13212909 * hand), 0.0,
		Motion.compact_pulse(PI * hand / (2.0 * area * 2.47289653)),
		"giant-inversion", 0, 2.0, "immelmann")
	_add(spans, metadata, propulsion, "act-one/immelmann-settle", 0.53603802, "moving",
		Motion.quintic(2.28038016, 1.0), 0.0, 0.0, 0.0,
		"giant-inversion", 0, 2.0, "immelmann")


static func _add_act_one_cutback(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, hand: float
) -> void:
	_add(spans, metadata, propulsion, "act-one/cutback-entry", 0.80036457, "moving",
		Motion.quintic(1.0, 4.16194327), 0.0, 0.0,
		Motion.compact_pulse(deg_to_rad(108.213109) * hand), "cutback", 0, 2.0, "cutback")
	_add(spans, metadata, propulsion, "act-one/cutback-arc", 1.67497928, "moving",
		Motion.quintic(4.16194327, 2.62954854), 0.0, 0.0,
		Motion.compact_pulse(deg_to_rad(108.213109) * hand), "cutback", 0, 2.0, "cutback")
	_add(spans, metadata, propulsion, "act-one/cutback-reverse", 2.52077154, "moving",
		Motion.quintic(2.62954854, 3.82368727), 0.0, 0.0,
		Motion.compact_pulse(deg_to_rad(-50.80747228) * hand), "cutback", 0, 2.0, "cutback")
	_add(spans, metadata, propulsion, "act-one/cutback-release", 1.17767523, "moving",
		Motion.quintic(3.82368727, 1.0), 0.0, 0.0,
		Motion.compact_pulse(deg_to_rad(-50.80747228) * hand), "cutback", 0, 2.0, "cutback")
	_add(spans, metadata, propulsion, "act-one/cutback-recover", 0.3, "moving",
		Motion.quintic(1.0, 3.69449176), 0.0, 0.0, 0.0, "cutback", 0, 2.0, "cutback")
	_add(spans, metadata, propulsion, "act-one/cutback-settle", 0.3, "moving",
		Motion.quintic(3.69449176, 1.0), 0.0, 0.0, 0.0, "cutback", 0, 2.0, "cutback")


static func _add_act_one_loop(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, hand: float,
	targets: Dictionary = {}
) -> void:
	# Drawn per seed: how hard the helical loop is pulled. The lateral that keeps the leg helical
	# and the fall-side roll stay fixed, so the drawn load only tightens or opens the arc.
	var loop_positive_g := RidePlanner.target(
		targets, "act-one-loop", "positive_g", ACT_ONE_LOOP_POSITIVE_G)
	var loop_rise_s := 3.6
	var loop_fall_s := 1.925
	_add(spans, metadata, propulsion, "act-one/loop-entry", 1.0, "moving",
		Motion.quintic(1.0, loop_positive_g), Motion.compact_pulse(0.2 * hand), 0.0, 0.0,
		"giant-inversion", 0, 2.0, "loop")
	_add(spans, metadata, propulsion, "act-one/loop-rise", loop_rise_s, "moving",
		loop_positive_g, Motion.compact_pulse(0.2 * hand), 0.0, 0.0,
		"giant-inversion", 0, 2.0, "loop")
	_add(spans, metadata, propulsion, "act-one/loop-fall", loop_fall_s, "moving",
		Motion.balanced_notch(loop_positive_g, 1.1),
		Motion.compact_pulse(-0.2 * hand), 0.0,
		Motion.compact_pulse(-0.34459064718862403 * hand), "giant-inversion", 0, 2.0, "loop")
	_add(spans, metadata, propulsion, "act-one/loop-release", 1.0, "moving",
		Motion.quintic(loop_positive_g, 1.0), Motion.compact_pulse(-0.2 * hand), 0.0,
		Motion.compact_pulse(-0.34459064718862403 * hand), "giant-inversion", 0, 2.0, "loop")


static func _add_act_one_airtime(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, hand: float,
	targets: Dictionary = {}
) -> void:
	# Drawn per seed: how hard and how long the braid floats. The same crest load closes the
	# unload ramp and opens the fall ramp, so the seams stay exact at any drawn pair.
	var crest_g := RidePlanner.target(targets, "act-one-airtime", "crest_normal_g", -0.31)
	var crest_s := RidePlanner.target(targets, "act-one-airtime", "crest_duration_s", 2.0893089979)
	_add(spans, metadata, propulsion, "act-one/airtime-pull-up", 0.7246134969, "moving",
		Motion.quintic(1.0, 3.60671666363852), 0.0, 0.0, 0.0, "airtime-hills", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "act-one/airtime-unload", 0.7246134969, "moving",
		Motion.quintic(3.60671666363852, crest_g), 0.0, 0.0, 0.0, "airtime-hills", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "act-one/airtime-crest", crest_s, "moving",
		crest_g, 0.0, 0.0, 0.0, "airtime-hills", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "act-one/airtime-fall", 0.7222022717, "moving",
		Motion.quintic(crest_g, 3.60671666363852), 0.0, 0.0, 0.0, "airtime-hills", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "act-one/airtime-release", 0.7222022717, "moving",
		Motion.quintic(3.60671666363852, 1.0), 0.0, 0.0, 0.0, "airtime-hills", 0, 2.0, "hill")


static func _add_act_one_wave(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, hand: float,
	targets: Dictionary = {}
) -> void:
	var area := COMPACT_PULSE_AREA
	# Drawn per seed: how far the wave turn lays over. The roll-in duration scales with the drawn
	# bank so the roll-in rate stays at its authored 115.5 deg/s: banking further has to take
	# longer, it is not allowed to buy itself a faster roll out of the envelope.
	var wave_bank := RidePlanner.target(targets, "act-one-wave", "bank_rad", PI / 4.0)
	var wave_bank_rise_s := 0.9 * wave_bank / (PI / 4.0)
	var wave_unload_s := 0.465
	var wave_crest_s := 1.5585438924091
	var wave_recover_s := 0.424869716970738
	var wave_exit_total_s := 1.1
	var wave_exit_angle := 0.48211374457049
	var wave_bank_in := wave_bank / (area * wave_bank_rise_s)
	var wave_cross := 2.0 * wave_bank \
		/ (area * (wave_unload_s + wave_crest_s + wave_recover_s))
	var wave_bank_out := wave_exit_angle / (area * wave_exit_total_s)
	_add(spans, metadata, propulsion, "act-one/wave-bank-rise", wave_bank_rise_s, "moving",
		Motion.quintic(1.0, 5.1999981231), 0.0, 0.0,
		Motion.compact_pulse(-wave_bank_in * hand), "wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-first-peak", 0.35, "moving",
		5.1999981231, 0.0, 0.0, 0.0, "wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-unload", wave_unload_s, "moving",
		Motion.quintic(5.1999981231, -0.9999995365), 0.0, 0.0,
		Motion.compact_pulse(wave_cross * hand), "wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-crest", wave_crest_s, "moving",
		-0.9999995365, 0.0, 0.0, Motion.compact_pulse(wave_cross * hand),
		"wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-recover", wave_recover_s, "moving",
		Motion.quintic(-0.9999995365, 2.7007134553), 0.0, 0.0,
		Motion.compact_pulse(wave_cross * hand), "wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-second-peak", 0.45, "moving",
		2.7007134553, 0.0, 0.0, Motion.compact_pulse(-wave_bank_out * hand),
		"wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-release", 0.65, "moving",
		Motion.quintic(2.7007134553, 1.0), 0.0, 0.0,
		Motion.compact_pulse(-wave_bank_out * hand), "wave-turn", 0, 2.0, "wave_turn")


static func _add_raceway(
	s: Array, m: Array, p: PackedInt32Array, parameters: Array = [], hand: float = 1.0,
	initial_bank_rad: float = 0.0, targets: Dictionary = {}
) -> void:
	var authored := RideReturnSolve._return_spans(
		RideReturnSolve.RETURN_SEED if parameters.is_empty() else parameters,
		hand, initial_bank_rad, targets)
	# Roles follow the span ids the return solve authored, so a span added to or removed from
	# `_return_spans` can never be silently dropped or mis-owned here; an id outside the four
	# raceway families is authored wrongly and is refused, not guessed.
	var families := {
		"raceway/turn-a/": ["turn-a", "overbank"],
		"raceway/height-a/": ["height-airtime-a", "hill"],
		"raceway/turn-b/": ["turn-b", "overbank"],
		"raceway/height-b/": ["height-airtime-b", "hill"],
	}
	for motion_span: Dictionary in authored:
		var family: Array = []
		for prefix: String in families:
			if str(motion_span.span_id).begins_with(prefix):
				family = families[prefix]
				break
		assert(not family.is_empty(),
			"return span '%s' belongs to no raceway family" % str(motion_span.span_id))
		_add_record(s, m, p, motion_span, str(family[0]) if not family.is_empty() else "",
			0, 45.0, str(family[1]) if not family.is_empty() else "")


static func _add_capture_and_brakes(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, coefficients: Array,
	brake: Dictionary
) -> void:
	for capture_span: Dictionary in RideReturnSolve._capture_spans(coefficients):
		_add_record(spans, metadata, propulsion, capture_span, "capture", 0, 2.0)
	for terminal_span: Dictionary in brake.spans:
		var station_mode: bool = terminal_span.mode == "station"
		_add_record(spans, metadata, propulsion, terminal_span,
			"station" if station_mode else "brakes", 0, 0.0 if station_mode else 2.0)


## The role ids a plan declares, in its own authored order.
static func plan_role_ids(plan: Dictionary) -> Array:
	var ids: Array = []
	for role in plan.get("roles", []):
		if not role is Dictionary:
			return []
		ids.append(str(role.get("id", "")))
	return ids


## The compiled story a plan asks for: its declared role sequence and its resolved target draws.
## A plan may carry no closure (an unsolved fixture), but a closure it does carry must be one the
## prefix can actually be built from: four accepted durations, finite and inside their bounds.
static func _prefix_closure_is_valid(closure: Variant) -> bool:
	if not closure is Dictionary:
		return false
	if closure.is_empty():
		return true
	var values: Variant = closure.get("accepted_values", [])
	if not values is Array or values.size() != RidePrefixSolve.PREFIX_CONTROL_IDS.size():
		return false
	for index in values.size():
		var bound: Array = RidePrefixSolve.PREFIX_CONTROL_BOUNDS[index]
		var value := float(values[index])
		if not is_finite(value) or value < float(bound[0]) or value > float(bound[1]):
			return false
	return true


## The flex-span durations the plan's accepted closure carries. `_validate_plan` has already
## refused a malformed one, so the only plan without a closure is an unsolved fixture, which gets
## the authored seed - exactly the prefix `terrain_story_capability` publishes without a target.
static func _prefix_controls_from_plan(plan: Dictionary) -> Array:
	var closure: Variant = plan.terrain_frame.planning.get("closure", {})
	var values: Variant = closure.get("accepted_values", []) if closure is Dictionary else []
	return values if values is Array and not values.is_empty() else RidePrefixSolve.PREFIX_SEED


static func _story_from_plan(plan: Dictionary) -> Dictionary:
	var decisions: Dictionary = plan.get("decisions", {})
	var targets: Variant = decisions.get("targets", {})
	return {"sequence": plan_role_ids(plan),
		"targets": targets if targets is Dictionary else {}}


static func _validate_plan(plan: Dictionary) -> Dictionary:
	var expected := ["schema_version", "preset_id", "decisions", "terrain_frame", "station",
		"corridor", "route_length_m", "roles"]
	var keys: Array = plan.keys()
	keys.sort()
	var sorted_expected := expected.duplicate()
	sorted_expected.sort()
	if keys != sorted_expected or plan.get("schema_version") != 1 \
			or plan.get("preset_id") != "material-v1":
		return _failure("material-v1 plan must have exactly the reviewed eight fields", "plan")
	var decisions: Variant = plan.get("decisions")
	var terrain_frame: Variant = plan.get("terrain_frame")
	if not decisions is Dictionary or int(decisions.get("station_side", 0)) not in [-1, 1] \
			or not terrain_frame is Dictionary or not terrain_frame.get("inward") is Vector3 \
			or not terrain_frame.get("along") is Vector3 or not terrain_frame.get("up") is Vector3 \
			or not terrain_frame.get("right") is Vector3 \
			or not terrain_frame.get("planning") is Dictionary:
		return _failure("material-v1 decisions or terrain frame is incomplete", "plan")
	var planning: Dictionary = terrain_frame.planning
	# The prefix integration count is a constant of the path that produced the plan, not a budget:
	# one for a fixture built from a single capability, two for production (preflight + closure).
	if str(planning.get("capability_id", "")).is_empty() \
			or int(planning.get("planning_integrations", 0)) not in [1, 2] \
			or not planning.get("scale") is Dictionary \
			or not _prefix_closure_is_valid(planning.get("closure", {})):
		return _failure("material-v1 planning capability is incomplete", "plan")
	var corridor_value: Variant = plan.get("corridor")
	if not corridor_value is Dictionary:
		return _failure("material-v1 corridor must be a Dictionary", "plan")
	var corridor: Dictionary = corridor_value
	for field in ["approach_length_m", "capture_length_m", "brake_length_m",
			"half_width_m", "half_height_m"]:
		if not corridor.has(field) or not is_finite(float(corridor[field])) \
				or float(corridor[field]) <= 0.0:
			return _failure("material-v1 corridor field is not finite and positive", "plan",
				{"field": field})
	var entry_speed_value: Variant = corridor.get("entry_speed_mps")
	if not entry_speed_value is Vector2 or not entry_speed_value.is_finite() \
			or entry_speed_value.x <= 0.0 or entry_speed_value.y < entry_speed_value.x:
		return _failure("material-v1 corridor entry speed band is invalid", "plan")
	if absf(float(corridor.approach_length_m) - float(corridor.capture_length_m)
			- float(corridor.brake_length_m)) > 0.000001:
		return _failure("material-v1 corridor partitions do not sum to the approach", "plan")
	var roles: Variant = plan.get("roles")
	if not roles is Array or roles.is_empty():
		return _failure("material-v1 plan must declare its roles", "plan")
	var sequence := plan_role_ids(plan)
	if not RidePlanner.is_legal_sequence(sequence):
		return _failure("material-v1 role sequence is not grammar-legal", "plan",
			{"observed": {"sequence": sequence}})
	var minimum_sum := 0.0
	var maximum_sum := 0.0
	var allocations := {}
	for index in roles.size():
		var role: Dictionary = roles[index]
		var role_id := str(sequence[index])
		if not role.get("length_m") is Vector2:
			return _failure("material-v1 role order or length band is invalid", "plan",
				{"role_id": role_id})
		var band: Vector2 = role.length_m
		if not is_finite(band.x) or not is_finite(band.y) or band.x <= 0.0 or band.y < band.x:
			return _failure("material-v1 role length band is not finite", "plan",
				{"role_id": role_id})
		var nominal: float = float(ROLE_NOMINAL_LENGTH_M.get(role_id, NAN))
		if not is_finite(nominal) or nominal < band.x or nominal > band.y:
			return _failure("material-v1 nominal role length is outside its band", "plan",
				{"role_id": role_id})
		minimum_sum += band.x
		maximum_sum += band.y
		allocations[role_id] = nominal
	var route_band: Variant = plan.get("route_length_m")
	if not route_band is Vector2 or route_band != RideReturnSolve.RETURN_TOTAL_LENGTH_BAND_M \
			or minimum_sum > route_band.y or maximum_sum < route_band.x:
		return _failure("aggregate role lengths cannot satisfy the route band", "plan",
			{"bounds": {"role_sum_m": Vector2(minimum_sum, maximum_sum),
				"route_length_m": route_band}})
	var required_terrain := {
		"clifftop-outward-rim": ["exit_tangent_outward_dot"],
		"outward-dive": ["outward_delta_m", "maximum_cross_to_outward_ratio",
			"minimum_centerline_agl_m",
			"boundary_crossings", "monotonic"],
		"tunnel-lsm3": ["boundary_crossings"],
	}
	for role_id in required_terrain:
		var required_role: Dictionary = roles[sequence.find(role_id)]
		var terrain: Variant = required_role.get("terrain")
		if not terrain is Dictionary:
			return _failure("missing_required_terrain_intent", "plan", {"role_id": role_id})
		for field in required_terrain[role_id]:
			if not terrain.has(field):
				return _failure("missing_required_terrain_intent", "plan",
					{"role_id": role_id, "observed": {"missing": field}})
	var dive_terrain: Dictionary = roles[sequence.find("outward-dive")].terrain
	var outward_band: Variant = dive_terrain.outward_delta_m
	var cross_ratio: Variant = dive_terrain.maximum_cross_to_outward_ratio
	if not outward_band is Vector2 or not outward_band.is_finite() \
			or outward_band.x <= 0.0 or outward_band.y < outward_band.x \
			or not cross_ratio is float or not is_finite(cross_ratio) \
			or cross_ratio <= 0.0 or cross_ratio > 1.0:
		return _failure("invalid_outward_dive_terrain_intent", "plan")
	return {"ok": true, "allocations": allocations}


static func _layout_from_plan(plan: Dictionary) -> Dictionary:
	var station: Dictionary = plan.station
	var corridor: Dictionary = plan.corridor
	var approach_length: float = corridor.approach_length_m
	return {
		"station_position_m": station.position_m,
		"station_tangent": station.tangent,
		"station_up": station.up,
		"station_side": int(plan.decisions.station_side),
		"capture_half_width_m": corridor.half_width_m,
		"capture_half_height_m": corridor.half_height_m,
		"route_length_m": plan.route_length_m,
		# The return solve observes the two role bands its own candidate integration owns outright;
		# each is handed the plan's declared band rather than a copy of it. A plan that declares no
		# such role hands back the unbounded band and the residual it feeds is inert.
		"turn_b_length_m": _role_length_band(plan, "return-turn-b"),
		"record_release_length_m": _role_length_band(plan, "record-release-turn"),
		"reserved_corridor": {
			"approach_start_m": station.position_m - station.tangent * approach_length,
			"station_position_m": station.position_m,
			"station_tangent": station.tangent,
			"minimum_length_m": approach_length,
			"capture_length_m": corridor.capture_length_m,
			"brake_length_m": corridor.brake_length_m,
			"entry_speed_mps": corridor.entry_speed_mps,
		},
	}


static func _role_length_band(plan: Dictionary, role_id: String) -> Vector2:
	for role in plan.get("roles", []):
		if role is Dictionary and str(role.get("id", "")) == role_id \
				and role.get("length_m") is Vector2:
			return role.length_m
	return RideReturnSolve.RETURN_UNBOUNDED_BAND_M


static func _validate_station_layout(layout: Dictionary, initial_state: Dictionary) -> String:
	for key in ["station_position_m", "station_tangent", "station_up"]:
		if not layout.has(key) or not (layout[key] is Vector3) or not layout[key].is_finite():
			return "layout is missing finite %s" % key
	if layout.station_tangent.length_squared() < 0.99 or layout.station_up.length_squared() < 0.99:
		return "station frame is degenerate"
	if absf(layout.station_tangent.normalized().dot(layout.station_up.normalized())) > 0.000001:
		return "station tangent and up are not orthogonal"
	if absf(layout.station_tangent.normalized().y) > 0.000001 \
			or layout.station_up.normalized().distance_to(Vector3.UP) > 0.000001:
		return "station pose must be level with world up"
	for key in ["position_m", "tangent", "rider_up", "speed_mps"]:
		if not initial_state.has(key):
			return "initial state is missing %s" % key
	if initial_state.position_m.distance_to(layout.station_position_m) > 0.000001 \
			or initial_state.tangent.normalized().distance_to(layout.station_tangent.normalized()) > 0.000001 \
			or initial_state.rider_up.normalized().distance_to(layout.station_up.normalized()) > 0.000001:
		return "initial state does not match the station pose"
	return ""


static func _band_residual(value: float, band: Vector2) -> float:
	return minf(0.0, value - band.x) + maxf(0.0, value - band.y)


static func _last_state(route: Dictionary) -> Dictionary:
	return {
		"position_m": route.position_m[-1],
		"tangent": route.tangent[-1],
		"rider_up": route.rider_up[-1],
		"speed_mps": route.speed_mps[-1],
		"distance_m": route.distance_m[-1],
		"time_s": route.time_s[-1],
	}


## Solver and planning integrations skip the dense-output measurement; the generator's one
## accepted production integration turns it back on (`RouteContract` requires it there).
static func _settings(step_s: float) -> Dictionary:
	return {"step_s": step_s, "rolling_mps2": ROLLING_MPS2,
		"aero_per_m": AERO_PER_M, "gravity_mps2": Vector3.DOWN * Motion.G0,
		"measure_dense_output": false}


static func _failure(
	message: String, stage: String, diagnostics: Dictionary = {}
) -> Dictionary:
	var failure := {"stage": stage, "reason": message}
	failure.merge(diagnostics, true)
	return {"ok": false, "errors": PackedStringArray([message]), "failure": failure}


static func _add_record(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, motion_span: Dictionary,
	role: String, propulsion_id: int, minimum_speed_mps: float, diagnostic_kind: String = ""
) -> void:
	spans.append(motion_span)
	metadata.append({"span_id": motion_span.span_id, "role_id": role,
		"propulsion_id": propulsion_id, "minimum_speed_mps": minimum_speed_mps,
		"diagnostic_kind": diagnostic_kind})
	propulsion.append(propulsion_id)


## One explicit geometry-intent record per material role. No role is allowed to disappear from
## geometry review merely because its contract has not been researched yet: an unadopted record
## publishes that absence honestly, while an adopted record will later carry the executable
## `ElementContract` intent. The current slice adopts none; the camelback is the first planned
## promotion after its geometry is rewritten.
static func material_element_intents(sequence: Array = MATERIAL_ROLE_IDS) -> Dictionary:
	var role_ids: Array = sequence if not sequence.is_empty() else MATERIAL_ROLE_IDS
	var records := {}
	for role_value in role_ids:
		var role_id := str(role_value)
		records[role_id] = {
			"status": "unadopted",
			"reason": "no reviewed whole-element geometry intent has been adopted",
			"intent": {},
		}
	return records


## Reconstruct which material role owns each authored span. Ownership must be total, ordered
## and contiguous: an unowned span, a split role or an unauthored role is a hard failure, never
## a silent Vector2i(-1, -1).
static func material_role_spans(spans: Array, sequence: Array = MATERIAL_ROLE_IDS) -> Dictionary:
	var role_ids: Array = sequence if not sequence.is_empty() else MATERIAL_ROLE_IDS
	var prefixes := {
		"station-launch": ["launch/"],
		"opener-twisted-drop": ["drop/"],
		"opener-teardrop": ["teardrop/"],
		"opener-release": ["release/"],
		"act-one-immelmann": ["act-one/immelmann-"],
		"act-one-cutback": ["act-one/cutback-"],
		"act-one-loop": ["act-one/loop-"],
		"act-one-airtime": ["act-one/airtime-"],
		"act-one-wave": ["act-one/wave-"],
		"climb-lsm2": ["climb/"],
		"clifftop-slow-crest": ["rim/slow-crest"],
		"clifftop-outward-rim": ["rim/outward-"],
		"outward-dive": ["dive/"],
		"tunnel-lsm3": ["tunnel/"],
		"record-release-turn": ["record-release-turn/"],
		"camelback": ["camelback/"],
		"return-turn-a": ["raceway/turn-a/"],
		"return-height-a": ["raceway/height-a/"],
		"return-turn-b": ["raceway/turn-b/"],
		"return-height-b": ["raceway/height-b/"],
		"terminal-capture-brakes": ["capture/", "brakes/", "station/"],
	}
	var errors := PackedStringArray()
	var result := {}
	var block_order := PackedInt32Array()
	for index in spans.size():
		var span_id := str(spans[index].span_id)
		var owner := -1
		for role_index in role_ids.size():
			for prefix in prefixes[role_ids[role_index]]:
				if not span_id.begins_with(prefix):
					continue
				if owner >= 0 and owner != role_index:
					errors.append("span %s is claimed by both %s and %s" % [
						span_id, role_ids[owner], role_ids[role_index]])
				owner = role_index
		if owner < 0:
			errors.append("span %s is owned by no material role" % span_id)
			continue
		var role_id: String = role_ids[owner]
		if block_order.is_empty() or block_order[-1] != owner:
			if result.has(role_id):
				errors.append("material role %s owns a non-contiguous span block" % role_id)
			block_order.append(owner)
			result[role_id] = Vector2i(index, index)
		else:
			result[role_id] = Vector2i(result[role_id].x, index)
	for role_index in role_ids.size():
		if not result.has(role_ids[role_index]):
			errors.append("material role %s owns no authored span" % role_ids[role_index])
		elif role_index >= block_order.size() or block_order[role_index] != role_index:
			errors.append("material role %s is not authored in its declared order"
				% role_ids[role_index])
	return {"ok": errors.is_empty(), "role_spans": result, "errors": errors}


static func _validate_control_seams(spans: Array) -> PackedStringArray:
	var errors := PackedStringArray()
	var profile_keys := ["normal_g", "lateral_g", "drive_g", "roll_rate_rad_s"]
	for span_index in range(1, spans.size()):
		for key in profile_keys:
			var before := Motion.profile_sample(spans[span_index - 1][key], 1.0)
			var after := Motion.profile_sample(spans[span_index][key], 0.0)
			var before_duration: float = spans[span_index - 1].duration_s
			var after_duration: float = spans[span_index].duration_s
			before.y /= before_duration
			before.z /= before_duration * before_duration
			after.y /= after_duration
			after.z /= after_duration * after_duration
			if before.distance_to(after) > 0.000001:
				errors.append("control seam %d %s has mismatched C2 jets" % [span_index, key])
	var last: Dictionary = spans[-1]
	for key in profile_keys:
		var expected := 1.0 if key == "normal_g" else 0.0
		var actual := Motion.profile_sample(last[key], 1.0)
		actual.y /= last.duration_s
		actual.z /= last.duration_s * last.duration_s
		if actual.distance_to(Vector3(expected, 0.0, 0.0)) > 0.000001:
			errors.append("terminal control %s is not structural" % key)
	return errors


static func _begin_gesture(
	gestures: Array, story_slot_id: String, first_span: int, diagnostic_kind: String = ""
) -> void:
	gestures.append({"story_slot_id": story_slot_id,
		"display_name": story_slot_id.replace("-", " ").capitalize(), "first_span": first_span,
		"last_span": first_span, "role_windows": [], "diagnostic_kind": diagnostic_kind,
		"occurrence": 0,
		"window_id": _window_id(story_slot_id, "whole", 0, diagnostic_kind)})


static func _end_gesture(gestures: Array, metadata: Array, last_span: int) -> void:
	var gesture: Dictionary = gestures[-1]
	gesture.last_span = last_span
	var first := int(gesture.first_span)
	var roles: Array = []
	var occurrences := {}
	for span_index in range(first, last_span + 1):
		var role: String = metadata[span_index].role_id
		var diagnostic_kind := str(metadata[span_index].get("diagnostic_kind", ""))
		if roles.is_empty() or roles[-1].id != role \
				or roles[-1].diagnostic_kind != diagnostic_kind:
			var occurrence := int(occurrences.get(role, 0))
			occurrences[role] = occurrence + 1
			roles.append({
				"id": role,
				"display_name": (diagnostic_kind if not diagnostic_kind.is_empty() else role) \
					.replace("_", " ").replace("-", " ").capitalize(),
				"diagnostic_kind": diagnostic_kind,
				"occurrence": occurrence,
				"window_id": _window_id(
					gesture.story_slot_id, role, occurrence, diagnostic_kind),
				"first_span": span_index,
				"last_span": span_index,
			})
		else:
			roles[-1].last_span = span_index
	gesture.role_windows = roles


static func _peak_profile_normal_onset_estimate(spans: Array, first: int, last: int) -> float:
	var peak := 0.0
	for index in range(first, last + 1):
		var span: Dictionary = spans[index]
		peak = maxf(peak,
			Motion.profile_peak_abs_derivative_estimate(span.normal_g) / span.duration_s)
	return peak


static func _window_id(
	story_slot_id: String, role: String, occurrence: int, diagnostic_kind: String
) -> String:
	var suffix := "" if diagnostic_kind.is_empty() else "-%s" % diagnostic_kind
	return "%s/%s/%02d%s" % [story_slot_id, role, occurrence, suffix]


static func _add(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, span_id: String,
	duration_s: float, mode: String, normal: Variant, lateral: Variant, drive: Variant,
	roll: Variant, role: String, propulsion_id: int = 0, minimum_speed_mps: float = 2.0,
	diagnostic_kind: String = "", transition_id: String = ""
) -> void:
	var normal_profile: Dictionary = normal if normal is Dictionary else Motion.constant(float(normal))
	var lateral_profile: Dictionary = lateral if lateral is Dictionary else Motion.constant(float(lateral))
	var drive_profile: Dictionary = drive if drive is Dictionary else Motion.constant(float(drive))
	var roll_profile: Dictionary = roll if roll is Dictionary else Motion.constant(float(roll))
	var owned_transition := transition_id if not transition_id.is_empty() else diagnostic_kind
	spans.append(Motion.span(span_id, duration_s, mode, normal_profile, lateral_profile,
		drive_profile, roll_profile, owned_transition))
	metadata.append({"span_id": span_id, "role_id": role,
		"propulsion_id": propulsion_id,
		"minimum_speed_mps": minimum_speed_mps,
		"diagnostic_kind": diagnostic_kind, "transition_id": owned_transition})
	propulsion.append(propulsion_id)
