class_name RideProgram
extends RefCounted

const Motion := preload("res://motion.gd")
const BoundedSolver := preload("res://bounded_solver.gd")
const RidePlanner := preload("res://ride_planner.gd")

const GENERATOR_VERSION := "time-domain-v1"
const ROLLING_MPS2 := 0.08
const AERO_PER_M := 0.000075
const COMPACT_PULSE_AREA := 100.0 / 231.0
const COARSE_STEP_S := 0.05
const FINE_STEP_S := 0.025
const PRODUCTION_STEP_S := 0.01
const MAX_CAPTURE_EVALUATIONS := 40
const MAX_RETURN_EVALUATIONS := 220
const RETURN_SCALAR_IDS := [
	"turn_a_bank_rad", "turn_a_core_duration_s", "height_a_recovery_duration_s",
	"turn_b_bank_rad", "turn_b_core_duration_s", "height_b_airtime_duration_s",
	"height_b_recovery_duration_s",
]
const RETURN_SCALAR_BOUNDS := [
	# Turn-a bank caps at 66 deg: the fixed 0.45 s exit rolls (bank - 45 deg) in one compact
	# pulse, so peaks stay under the 120 deg/s envelope only for bank < ~68.4 deg, and the
	# sweep seeds never run the load gate that would catch a breach.
	[50.0 * PI / 180.0, 66.0 * PI / 180.0], [0.55, 6.00],
	# The 60 deg turn-b floor is authoring intent, not a solve optimum: both return turns
	# stay strongly banked even when the solve would trade bank away for closure.
	[0.35, 4.0], [60.0 * PI / 180.0, 80.0 * PI / 180.0],
	[2.0, 12.0], [0.1, 2.0], [0.35, 4.6],
]
const RETURN_SEED := [1.04746249688937, 1.25017790590635, 1.65507763577872,
	1.0471975511966, 6.48573781566998, 0.996333175598368, 3.98838120528104]
const RETURN_HEIGHT_A_PEAK_G := 3.8
const RETURN_HEIGHT_B_PEAK_G := 3.15821137151466
const RETURN_TRANSFER_BANK_BIAS_RAD := 7.5 * PI / 180.0
const RETURN_TOTAL_LENGTH_BAND_M := Vector2(7800.0, 8200.0)
const RETURN_RESIDUAL_IDS := [
	"station_forward_m", "cross_track_m", "height_m", "tangent_right",
	"tangent_up", "route_length_band_m", "entry_speed_band_mps",
]
const RETURN_RESIDUAL_SCALES := [5.0, 5.0, 5.0, 0.02, 0.02, 125.0, 0.1]
const RETURN_FINE_TOLERANCES := [0.075, 0.075, 0.075, 0.0001, 0.0001, 0.075, 0.01]
const CAPTURE_ENTRY_SPEED_MPS := Vector2(70.0, 80.0)
const RETURN_ENTRY_SPEED_PADDING_MPS := 0.01
const RETURN_ENTRY_POSITION_PADDING_M := 0.25
const CAPTURE_HALF_WIDTH_M := 150.0
const CAPTURE_HALF_HEIGHT_M := 75.0
const CAPTURE_STEERING_DURATION_S := 0.45
const CAPTURE_TERMINAL_DURATION_S := 0.15
const CAPTURE_RESIDUAL_TOLERANCES := [0.05, 0.05, 0.000001, 0.000001, 0.0000025]
const CAPTURE_COARSE_RESIDUAL_TOLERANCES := [0.075, 0.075, 0.0001, 0.0001, 0.0001]
const BRAKE_SHOULDER_DURATION_S := 0.6
const BRAKE_PARAMETER_IDS := ["hold_duration_s", "peak_g"]
# Peak brake g caps at 3.6: the capture now enters near the widened 80 m/s corridor ceiling,
# and the fixed 150 m brake reserve needs ~3.0 g of it. 3.6 keeps real solve margin while
# staying inside the -Gx envelope, which allows 4.286 g over the ~3 s brake hold.
const BRAKE_PARAMETER_BOUNDS := [[0.5, 5.0], [0.0, 3.6]]
const MAX_BRAKE_EVALUATIONS := 24
const BRAKE_NEWTON_ITERATIONS := 7
const BRAKE_NEWTON_STEP := 0.95
const BRAKE_BOUNDARY_TOLERANCE_MPS := 0.0001
const BRAKE_BOUNDARY_INTERIOR_MPS := 2.0 + 0.5 * BRAKE_BOUNDARY_TOLERANCE_MPS
const TERMINAL_DISTANCE_TOLERANCE_M := 0.05
const CAPTURE_COEFFICIENT_BOUNDS := [
	[-1.5, 1.5], [-1.5, 1.5], [-0.45, 0.45], [-0.45, 0.45], [-1.2, 1.2],
]
## The canonical (undrawn) role order. It is the default a caller gets when no plan sequence is
## supplied; a built ride is always validated against the sequence its own plan declares.
const MATERIAL_ROLE_IDS := [
	"station-launch", "opener-twisted-drop", "opener-teardrop", "opener-release",
	"act-one-immelmann", "act-one-cutback", "act-one-loop", "act-one-airtime",
	"act-one-wave", "climb-lsm2", "clifftop-slow-crest", "clifftop-outward-rim",
	"outward-dive", "tunnel-lsm3", "camelback", "return-turn-a", "return-height-a",
	"return-turn-b", "return-height-b", "terminal-capture-brakes",
]
## Nominal role lengths, keyed by role id: a plan authors the roles its drawn sequence declares,
## so the nominal a role is checked against cannot be an index into one fixed twenty-list.
const ROLE_NOMINAL_LENGTH_M := {
	"station-launch": 180.0, "opener-twisted-drop": 620.0, "opener-teardrop": 650.0,
	"opener-release": 330.0, "act-one-immelmann": 430.0, "act-one-cutback": 310.0,
	"act-one-loop": 360.0, "act-one-airtime": 260.0, "act-one-wave": 240.0,
	"climb-lsm2": 600.0, "clifftop-slow-crest": 50.0, "clifftop-outward-rim": 90.0,
	"outward-dive": 420.0, "tunnel-lsm3": 180.0, "camelback": 1000.0,
	"return-turn-a": 480.0, "return-height-a": 420.0, "return-turn-b": 500.0,
	"return-height-b": 520.0, "terminal-capture-brakes": 230.0,
}


## The fixed story prefix, integrated once in its station-local frame so the generator can place
## the ride on terrain. `story` carries the planner's drawn sequence and resolved targets; an
## empty story reproduces the canonical undrawn recipe exactly.
static func terrain_story_capability(station_side: int, story: Dictionary = {}) -> Dictionary:
	if station_side != -1 and station_side != 1:
		return _failure("station_side must be -1 or 1", "planning")
	var spans: Array = []
	var metadata: Array = []
	var gestures: Array = []
	var propulsion := PackedInt32Array()
	_add_story_prefix(spans, metadata, gestures, propulsion, -float(station_side), story)
	var dive_start_span := -1
	var dive_end_span := -1
	var tunnel_end_span := -1
	for gesture in gestures:
		if gesture.story_slot_id == "cliff-dive":
			dive_start_span = int(gesture.first_span)
			dive_end_span = int(gesture.last_span)
		elif gesture.story_slot_id == "tunnel-lsm3":
			tunnel_end_span = int(gesture.last_span)
	if dive_start_span <= 0 or dive_end_span < dive_start_span \
			or tunnel_end_span <= dive_end_span:
		return _failure("terrain story capability omitted the cliff-dive handoff", "planning")
	var initial := {"position_m": Vector3.ZERO, "tangent": Vector3.RIGHT,
		"rider_up": Vector3.UP, "speed_mps": 6.0, "distance_m": 0.0, "time_s": 0.0}
	var trajectory := Motion.integrate(
		initial, spans.slice(0, tunnel_end_span + 1), _settings(PRODUCTION_STEP_S))
	if not trajectory.get("ok", false):
		return _failure("terrain story capability failed integration", "planning",
			{"errors": trajectory.get("errors", [])})
	var dive_start_sample: int = trajectory.span_index.find(dive_start_span)
	var dive_end_sample: int = trajectory.span_index.rfind(dive_end_span)
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
	var tunnel_exit_offset_m: Vector3 = trajectory.position_m[-2]
	var dive_outward_delta_m := float(station_side) \
		* (float(dive_exit_offset_m.z) - float(entry.position_m.z))
	if not dive_exit_offset_m.is_finite() or not tunnel_exit_offset_m.is_finite() \
			or dive_positions_m.is_empty() or dive_positions_m.size() != dive_rider_up.size() \
			or not is_finite(dive_outward_delta_m) or dive_outward_delta_m <= 0.0:
		return _failure("terrain story capability produced a non-outward dive footprint", "planning")
	var opener_end := -1
	var station_end := -1
	for gesture in gestures:
		if gesture.story_slot_id == "opener":
			opener_end = int(gesture.last_span)
		elif gesture.story_slot_id == "station-launch":
			station_end = int(gesture.last_span)
	var opener_end_sample: int = trajectory.span_index.rfind(opener_end)
	var station_end_sample: int = trajectory.span_index.rfind(station_end)
	if opener_end_sample < 0 or station_end_sample < 0 \
			or station_end_sample >= opener_end_sample:
		return _failure("terrain story capability omitted the station/opener footprint", "planning")
	return {"ok": true, "capability_id": "material-v1-prefix-r12@9",
		"planning_integrations": 1,
		"role_13_entry": {"offset_m": entry.position_m, "tangent": entry.tangent,
			"rider_up": entry.rider_up, "speed_mps": entry.speed_mps},
		"dive_footprint": {"outward_delta_m": dive_outward_delta_m,
			"dive_exit_offset_m": dive_exit_offset_m,
			"tunnel_exit_offset_m": tunnel_exit_offset_m,
			"positions_m": dive_positions_m, "rider_up": dive_rider_up},
		"station_opener": {
			"positions_m": trajectory.position_m.slice(0, opener_end_sample + 1),
			"rider_up": trajectory.rider_up.slice(0, opener_end_sample + 1),
			"station_sample_count": station_end_sample + 1,
		},
		"scale": {"route_vertical_envelope_m": Vector2(290.0, 305.0),
			"dive_drop_m": Vector2(240.0, 250.0),
			"camel_prominence_m": Vector2(245.0, 255.0)}}


static func compile(plan: Dictionary, initial_state: Dictionary) -> Dictionary:
	var plan_check := _validate_plan(plan)
	if not plan_check.ok:
		return plan_check
	var layout := _layout_from_plan(plan)
	var station_error := _validate_station_layout(layout, initial_state)
	if not station_error.is_empty():
		return _failure(station_error, "input")
	var capture_seed: Variant = layout.get("capture_seed", [0.0, 0.0, 0.0, 0.0, 0.0])
	if not capture_seed is Array or capture_seed.size() != 5:
		return _capture_failure("capture seed must contain five coefficients", 0)
	var spans: Array = []
	var metadata: Array = []
	var gestures: Array = []
	var propulsion := PackedInt32Array()
	# Canonical +Z maps outward for station_side=+1 and inward for -1. Mirror the
	# authored lateral forces so the shared story always approaches the escarpment.
	var hand := -float(plan.decisions.station_side)
	var story := _story_from_plan(plan)
	var targets: Dictionary = story.targets
	_add_story_prefix(spans, metadata, gestures, propulsion, hand, story)

	_begin_gesture(gestures, "marquee-camelback", spans.size(), "hill")
	_add_camelback(spans, metadata, propulsion, hand)
	_end_gesture(gestures, metadata, spans.size() - 1)

	var return_prefix := Motion.integrate(initial_state, spans, _settings(PRODUCTION_STEP_S))
	if not return_prefix.get("ok", false):
		return _failure("upstream return handoff failed integration", "return")
	var return_hand := -hand
	var solved_return := _solve_return(
		_last_state(return_prefix), layout, return_hand, RETURN_SEED, targets)
	if not solved_return.ok:
		return solved_return
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
	var capture := _solve_capture(capture_start, layout, _settings(FINE_STEP_S))
	if not capture.ok:
		return capture
	var capture_spans: Array = _capture_spans(capture.coefficients)
	var capture_route := Motion.integrate(capture_start, capture_spans, settings)
	if not capture_route.get("ok", false):
		return _capture_failure("accepted capture did not reintegrate",
			capture.unique_evaluations, capture.residuals, capture.margins)
	var production_residuals := _capture_residuals(_last_state(capture_route), layout)
	var production_margins := _capture_margins(capture.coefficients, capture_route, layout)
	if not _capture_converged(production_residuals):
		return _capture_failure("capture missed its production boundary",
			capture.unique_evaluations, production_residuals, production_margins)
	for margin in production_margins.values():
		if not is_finite(float(margin)) or float(margin) < 0.0:
			return _capture_failure("production capture violates an inequality",
				capture.unique_evaluations, production_residuals, production_margins)
	var brake := _solve_brakes(_last_state(capture_route), layout)
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
			"coefficient_bounds": CAPTURE_COEFFICIENT_BOUNDS,
			"unique_evaluations": capture.unique_evaluations,
			"max_unique_evaluations": MAX_CAPTURE_EVALUATIONS,
			"residual_ids": ["cross_track_m", "height_m", "yaw_rad", "pitch_rad", "roll_rad"],
			"residual_tolerances": CAPTURE_RESIDUAL_TOLERANCES,
			"coarse_residual_tolerances": CAPTURE_COARSE_RESIDUAL_TOLERANCES,
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
	story: Dictionary = {}
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
	_add(spans, metadata, propulsion, "climb/powered-core", 8.78838861435674, "moving",
		0.87362258024053, 0.0, climb_drive_g, 0.0, "lsm2", 2)
	_add(spans, metadata, propulsion, "climb/drive-release", 0.98392993, "moving",
		0.87362258024053, 0.0, Motion.quintic(climb_drive_g, 0.0), 0.0, "lsm2", 2)
	_add(spans, metadata, propulsion, "climb/pull-over", 3.20659393, "moving",
		Motion.quintic(0.87362258024053, 0.72152814), 0.0, 0.0, 0.0,
		"unpowered-climb")
	_add(spans, metadata, propulsion, "climb/level", 3.20659393, "moving",
		Motion.quintic(0.72152814, 1.0), 0.0, 0.0, 0.0, "unpowered-climb")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "clifftop-suspense", spans.size())
	var slow_bank := deg_to_rad(39.1243426617973)
	var slow_shoulder_s := 0.60483895572582
	# Drawn per seed: how firmly the crawl is held over the crest, and how far the rim turn lays
	# out over the edge. The suspense beat is reference-scale by contract, so both stay inside
	# the clifftop's declared force and heading bands rather than scaling toward the records.
	var slow_normal := RidePlanner.target(
		targets, "clifftop-slow-crest", "crest_normal_g", 1.2403722803347)
	var slow_roll := slow_bank / (slow_shoulder_s * Motion.PLATEAU_PULSE_AREA)
	_add(spans, metadata, propulsion, "rim/slow-crest-in", slow_shoulder_s, "moving",
		Motion.quintic(1.0, slow_normal), 0.0, 0.0,
		Motion.plateau_pulse(slow_roll * hand), "slow-crest")
	_add(spans, metadata, propulsion, "rim/slow-crest-core", 2.37191694497677, "moving",
		slow_normal, 0.0, 0.0, 0.0, "slow-crest")
	_add(spans, metadata, propulsion, "rim/slow-crest-out", slow_shoulder_s, "moving",
		Motion.quintic(slow_normal, 1.0), 0.0, 0.0,
		Motion.plateau_pulse(-slow_roll * hand), "slow-crest")
	var rim_bank := RidePlanner.target(
		targets, "clifftop-outward-rim", "bank_rad", deg_to_rad(49.9686662300867))
	var rim_normal := 1.0 / cos(rim_bank)
	# The roll shoulders scale with the drawn bank, so laying further over costs time instead of
	# buying a faster roll: the authored 66 deg/s roll-in rate is what the envelope was cleared
	# for, and it stays fixed at every drawn bank.
	var rim_shoulder_s := 1.0 * rim_bank / deg_to_rad(49.9686662300867)
	var rim_roll := rim_bank / (COMPACT_PULSE_AREA * rim_shoulder_s)
	_add(spans, metadata, propulsion, "rim/outward-bank", rim_shoulder_s, "moving",
		Motion.quintic(1.0, rim_normal), 0.0, 0.0,
		Motion.compact_pulse(rim_roll * hand), "outward-rim", 0, 2.0, "turn")
	_add(spans, metadata, propulsion, "rim/outward-arc", 2.01632319951879, "moving",
		rim_normal, 0.0, 0.0, 0.0, "outward-rim", 0, 2.0, "turn")
	_add(spans, metadata, propulsion, "rim/outward-release", rim_shoulder_s, "moving",
		Motion.quintic(rim_normal, 1.0), 0.0, 0.0,
		Motion.compact_pulse(-rim_roll * hand), "outward-rim", 0, 2.0, "turn")
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
	_add(spans, metadata, propulsion, "dive/face-approach", 1.0, "moving",
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



static func _add_camelback(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, hand: float
) -> void:
	var turn := -0.25001368 * hand
	var positive_g := 4.60068864065765
	var negative_g := -1.55352865073772
	var pullout_g := 5.2662035249371
	var pullout_hold_s := 0.01
	var pullup_s := 1.87949032 * 1.33555111055541
	var unload_s := 3.01169597 * 1.15 - 0.4
	var crest_s := 3.62587650 * 1.06
	# The fall is what makes the marquee stand ~250 m above its valley: at the record entry
	# speed the same normal-g ramp descends less per second, so the fall lengthens with the
	# camelback entry speed rather than the crest being scaled.
	var fall_s := 3.40
	var bank := -deg_to_rad(18.0) * hand
	_add(spans, metadata, propulsion, "camelback/pull-up",
		pullup_s, "moving",
		Motion.quintic(1.0, positive_g), Motion.compact_pulse(turn), 0.0,
		Motion.compact_pulse(bank / (pullup_s * COMPACT_PULSE_AREA)), "rise")
	_add(spans, metadata, propulsion, "camelback/rise-hold", 0.4, "moving",
		positive_g, Motion.compact_pulse(turn), 0.0, 0.0, "rise")
	_add(spans, metadata, propulsion, "camelback/unload",
		unload_s, "moving", Motion.quintic(positive_g, negative_g),
		Motion.compact_pulse(turn), 0.0,
		Motion.compact_pulse(-bank / (unload_s * COMPACT_PULSE_AREA)), "rise")
	_add(spans, metadata, propulsion, "camelback/crest", crest_s, "moving",
		negative_g, Motion.compact_pulse(-turn), 0.0,
		Motion.compact_pulse(-bank / (crest_s * COMPACT_PULSE_AREA)), "crest")
	_add(spans, metadata, propulsion, "camelback/fall", fall_s, "moving",
		Motion.quintic(negative_g, pullout_g), Motion.compact_pulse(-turn), 0.0,
		Motion.compact_pulse(bank / (fall_s * COMPACT_PULSE_AREA)), "fall")
	_add(spans, metadata, propulsion, "camelback/pullout-hold", pullout_hold_s, "moving",
		pullout_g, 0.0, 0.0, 0.0, "exit")
	_add(spans, metadata, propulsion, "camelback/pullout-release",
		1.58 - pullout_hold_s, "moving",
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
		targets, "opener-twisted-drop", "core_lateral_g", 0.6998747)
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
	_add(spans, metadata, propulsion, "drop/unbank-in", unbank_ramp_s, "moving",
		Motion.quintic(4.99988044, normal_mid_g), 0.0, 0.0,
		Motion.quintic(0.0, -unbank_peak_rad_s * hand),
		"twisted-drop", 0, 2.0, "twisted_drop")
	_add(spans, metadata, propulsion, "drop/unbank-recover", normal_recovery_s, "moving",
		Motion.quintic(normal_mid_g, 1.0), 0.0, 0.0,
		Motion.constant(-unbank_peak_rad_s * hand),
		"twisted-drop", 0, 2.0, "twisted_drop")
	_add(spans, metadata, propulsion, "drop/unbank-hold",
		unbank_hold_s - normal_recovery_s, "moving",
		1.0, 0.0, 0.0, Motion.constant(-unbank_peak_rad_s * hand),
		"twisted-drop", 0, 2.0, "twisted_drop")
	_add(spans, metadata, propulsion, "drop/unbank-out", unbank_ramp_s, "moving",
		1.0, 0.0, 0.0, Motion.quintic(-unbank_peak_rad_s * hand, 0.0),
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
	var loop_positive_g := RidePlanner.target(targets, "act-one-loop", "positive_g", 4.6)
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
	var authored := _return_spans(
		RETURN_SEED if parameters.is_empty() else parameters, hand, initial_bank_rad, targets)
	var role_ids := ["turn-a", "height-airtime-a", "turn-b", "height-airtime-b"]
	var role_ends := [8, 13, 16, 21]
	var first := 0
	for role_index in 4:
		for i in range(first, role_ends[role_index]):
			_add_record(s, m, p, authored[i], role_ids[role_index], 0, 45.0,
				"overbank" if role_index % 2 == 0 else "hill")
		first = role_ends[role_index]


static func _return_spans(
	v: Array, hand: float = 1.0, initial_bank_rad: float = 0.0, targets: Dictionary = {}
) -> Array:
	# Drawn per seed: how hard each return height beat is pulled and how deeply it unloads. The
	# solve still owns the durations, so a stronger beat is paid for in its own timing rather
	# than in closure, and the drawn pair reshapes ~1 km of authored return geometry.
	var height_a_airtime_g := -0.45 * RidePlanner.target(
		targets, "return-height-a", "unload_scale", 1.0)
	var height_b_airtime_g := -0.5 * RidePlanner.target(
		targets, "return-height-b", "unload_scale", 1.0)
	var height_a_peak_g := RidePlanner.target(
		targets, "return-height-a", "peak_g", RETURN_HEIGHT_A_PEAK_G)
	var turn_a_bank_rad := float(v[0])
	var turn_b_bank_rad := float(v[3])
	# The second beat's peak follows the first proportionally rather than drawing on its own:
	# a strongly pulled height-a paired with a weakly pulled height-b is the one corner of the
	# draw box the seven-control solve cannot close from its fixed seed (measured 2026-08-15:
	# every such corner exhausts the 220-evaluation budget while every proportional pair lands).
	var height_b_peak_g := RETURN_HEIGHT_B_PEAK_G * height_a_peak_g / RETURN_HEIGHT_A_PEAK_G
	# Drawn per seed: how far the two overbanked transfers are biased apart, which is what sets
	# how much heading the loaded arc spends before the counter-banked sweep unwinds it.
	var transfer_bank_bias_rad := RidePlanner.target(
		targets, "return-turn-a", "transfer_bank_bias_rad", RETURN_TRANSFER_BANK_BIAS_RAD)
	var transfer_bank_rad := deg_to_rad(37.5)
	var first_transfer_bank_rad := hand * (transfer_bank_rad + transfer_bank_bias_rad)
	var counter_transfer_bank_rad := -hand * (transfer_bank_rad - transfer_bank_bias_rad)
	var transfer_mid_bank_rad := lerpf(
		first_transfer_bank_rad, counter_transfer_bank_rad, 0.6 / 1.6)
	var counter_transfer_normal := 1.0 / cos(counter_transfer_bank_rad)
	var turn_a_normal := 1.0 / cos(turn_a_bank_rad)
	var turn_b_normal := 1.0 / cos(turn_b_bank_rad)
	var turn_a_entry_s := 0.75
	var turn_a_load_s := 0.65
	var turn_a_bank_rad_signed := hand * turn_a_bank_rad
	# The strongly banked turn-a cannot be reached in one compact pulse inside the roll-rate
	# envelope, so the roll-in is split at the duration ratio that equalises both stages.
	var turn_a_entry_mid_rad := turn_a_bank_rad_signed \
		* (turn_a_entry_s / (turn_a_entry_s + turn_a_load_s))
	var turn_a_entry_mid_normal := 1.0 / cos(turn_a_entry_mid_rad)
	var turn_a_roll := (turn_a_entry_mid_rad - initial_bank_rad) \
		/ (turn_a_entry_s * COMPACT_PULSE_AREA)
	var turn_b_bank_rad_signed := -hand * turn_b_bank_rad
	var turn_b_entry_mid_rad := turn_b_bank_rad_signed * (0.75 / 1.55)
	var turn_b_exit_mid_rad := turn_b_bank_rad_signed * 0.5
	var turn_b_entry_mid_normal := 1.0 / cos(turn_b_entry_mid_rad)
	var turn_b_exit_mid_normal := 1.0 / cos(turn_b_exit_mid_rad)
	return [
		Motion.span("raceway/turn-a/entry", turn_a_entry_s, "moving",
			Motion.quintic(1.0, turn_a_entry_mid_normal), Motion.constant(0.0),
			Motion.constant(0.0), Motion.compact_pulse(turn_a_roll)),
		_return_bank_span("raceway/turn-a/load", turn_a_load_s,
			turn_a_entry_mid_rad, turn_a_bank_rad_signed),
		_return_span("raceway/turn-a/core", float(v[1]), turn_a_normal, turn_a_normal),
		_return_bank_span("raceway/turn-a/exit", 0.45,
			turn_a_bank_rad_signed, first_transfer_bank_rad),
		_return_bank_span("raceway/turn-a/transfer-bank", 0.6,
			first_transfer_bank_rad, transfer_mid_bank_rad),
		_return_bank_span("raceway/turn-a/transfer-cross", 1.0,
			transfer_mid_bank_rad, counter_transfer_bank_rad),
		# The counter-banked sweep is what lets the loaded arc stay short: it spends the
		# role's remaining distance while unwinding heading instead of adding to it.
		_return_span("raceway/turn-a/counter-sweep", 1.0,
			counter_transfer_normal, counter_transfer_normal),
		_return_bank_span("raceway/turn-a/transfer-unbank", 0.7,
			counter_transfer_bank_rad, 0.0),
		_return_span("raceway/height-a/pullup", 0.75, 1.0, height_a_peak_g),
		_return_span("raceway/height-a/unload", 1.05, height_a_peak_g, height_a_airtime_g),
		_return_span("raceway/height-a/airtime", 0.75, height_a_airtime_g,
			height_a_airtime_g),
		_return_span("raceway/height-a/recovery", float(v[2]), height_a_airtime_g,
			height_a_peak_g),
		_return_span("raceway/height-a/release", 0.75, height_a_peak_g,
			turn_b_entry_mid_normal,
			turn_b_entry_mid_rad / (0.75 * COMPACT_PULSE_AREA)),
		_return_bank_span("raceway/turn-b/entry", 0.8,
			turn_b_entry_mid_rad, turn_b_bank_rad_signed),
		_return_span("raceway/turn-b/core", float(v[4]), turn_b_normal, turn_b_normal),
		_return_bank_span("raceway/turn-b/exit", 0.8,
			turn_b_bank_rad_signed, turn_b_exit_mid_rad),
		_return_span("raceway/height-b/pullup", 0.8, turn_b_exit_mid_normal, height_b_peak_g,
			-turn_b_exit_mid_rad / (0.8 * COMPACT_PULSE_AREA)),
		_return_span("raceway/height-b/unload", 1.2, height_b_peak_g, height_b_airtime_g),
		_return_span("raceway/height-b/airtime", float(v[5]), height_b_airtime_g,
			height_b_airtime_g),
		_return_span("raceway/height-b/recovery", float(v[6]), height_b_airtime_g,
			height_b_peak_g),
		_return_span("raceway/height-b/release", 0.8, height_b_peak_g, 1.0),
	]


static func _return_span(id: String, duration_s: float, from_g: float, to_g: float,
	roll_peak_rad_s: float = 0.0) -> Dictionary:
	var normal := Motion.constant(from_g) if is_equal_approx(from_g, to_g) \
		else Motion.quintic(from_g, to_g)
	var roll := Motion.constant(0.0) if absf(roll_peak_rad_s) < 0.000001 else Motion.compact_pulse(roll_peak_rad_s)
	return Motion.span(id, duration_s, "moving", normal, Motion.constant(0.0),
		Motion.constant(0.0), roll)


static func _return_bank_span(
	id: String, duration_s: float, from_bank_rad: float, to_bank_rad: float
) -> Dictionary:
	var roll_amplitude := (to_bank_rad - from_bank_rad) \
		/ (duration_s * COMPACT_PULSE_AREA)
	return Motion.span(id, duration_s, "moving",
		Motion.bank_balance(from_bank_rad, to_bank_rad), Motion.constant(0.0),
		Motion.constant(0.0), Motion.compact_pulse(roll_amplitude))


static func _solve_return(
	start: Dictionary, layout: Dictionary, hand: float = 1.0, seed: Array = RETURN_SEED,
	targets: Dictionary = {}
) -> Dictionary:
	var cache := {}
	var initial_bank_rad: float = _capture_residuals(start, layout)[4]
	var lower := []
	var upper := []
	for bound: Array in RETURN_SCALAR_BOUNDS:
		lower.append(bound[0])
		upper.append(bound[1])
	var residual := func(candidate: Array) -> Array:
		var observed := _return_evaluation(
			start, layout, candidate, _settings(PRODUCTION_STEP_S), cache, hand,
			initial_bank_rad, targets)
		return observed.scaled if observed.get("ok", false) else [INF]
	var solved := BoundedSolver.solve(
		residual, lower, upper, seed, MAX_RETURN_EVALUATIONS - 1)
	if not solved.get("ok", false):
		return _failure("return did not reach its physical target", "return",
			{"evaluation_count": solved.get("evaluations", cache.size()),
				"solver_status": solved.get("status", "invalid"),
				"accepted_values": solved.get("x", []),
				"target_error": solved.get("residuals", [])})
	var parameters: Array = solved.x
	var coarse := _return_evaluation(
		start, layout, parameters, _settings(FINE_STEP_S), cache, hand, initial_bank_rad,
		targets)
	if not coarse.get("ok", false):
		return coarse
	var fine := _return_evaluation(
		start, layout, parameters, _settings(PRODUCTION_STEP_S), cache, hand, initial_bank_rad,
		targets)
	if not fine.ok:
		return fine
	if _maximum_absolute(fine.scaled) > 0.02:
		return _failure("return fine solve misses its physical target", "return",
			{"evaluation_count": cache.size(), "accepted_values": parameters,
				"target_error": fine.scaled, "observed": fine.observation})
	if not _margins_are_valid(coarse.margins) or not _margins_are_valid(fine.margins):
		return _failure("solved return misses the capture-entry basin", "return",
			{"evaluation_count": cache.size(), "accepted_values": parameters,
				"observed": fine.observation, "margins": fine.margins})
	for index in RETURN_RESIDUAL_IDS.size():
		if absf(fine.residuals[index] - coarse.residuals[index]) \
				> RETURN_FINE_TOLERANCES[index]:
			return _failure("return coarse/fine observations disagree", "return",
				{"evaluation_count": cache.size(), "coarse": coarse.residuals,
					"fine": fine.residuals})
	var margins: Dictionary = fine.margins.duplicate(true)
	for index in parameters.size():
		margins["scalar_%s" % RETURN_SCALAR_IDS[index]] = minf(
			parameters[index] - RETURN_SCALAR_BOUNDS[index][0],
			RETURN_SCALAR_BOUNDS[index][1] - parameters[index])
	return {"ok": true, "parameters": parameters, "initial_bank_rad": initial_bank_rad,
		"report": {
		"scalar_ids": RETURN_SCALAR_IDS,
		"scalar_bounds": RETURN_SCALAR_BOUNDS, "accepted_values": parameters,
		"residual_ids": RETURN_RESIDUAL_IDS,
		"coarse_fine_tolerances": RETURN_FINE_TOLERANCES,
		"unique_evaluations": cache.size(), "max_unique_evaluations": MAX_RETURN_EVALUATIONS,
		"solver_status": solved.status, "solver_iterations": solved.iterations,
		"solver_conditioning": solved.conditioning,
		"coarse_observation": coarse.observation, "fine_observation": fine.observation,
		"margins": margins,
		"return_entry_gate": {"source": "derived-terminal-corridor",
			"position_m": start.position_m, "tangent": start.tangent,
			"up": start.rider_up, "speed_mps": start.speed_mps,
			"corridor_approach_length_m": _approach_length(layout)},
		"positive_drive_allowed": false}}


static func _maximum_absolute(values: Array) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, absf(float(value)))
	return result


static func _return_evaluation(start: Dictionary, layout: Dictionary, parameters: Array,
	settings: Dictionary, cache: Dictionary, hand: float = 1.0,
	initial_bank_rad: float = 0.0, targets: Dictionary = {}) -> Dictionary:
	var key := "%.6f:" % float(settings.step_s)
	for parameter in parameters:
		key += "%.12f," % float(parameter)
	if cache.has(key):
		return cache[key]
	if cache.size() >= MAX_RETURN_EVALUATIONS:
		return _failure("return exceeded its evaluation cap", "return",
			{"evaluation_count": cache.size()})
	var route := Motion.integrate(
		start, _return_spans(parameters, hand, initial_bank_rad, targets), settings)
	if not route.get("ok", false):
		var failed := _failure("return candidate failed integration", "return",
			{"evaluation_count": cache.size() + 1})
		cache[key] = failed
		return failed
	var result := _return_observation(route, layout)
	result["scaled"] = []
	for index in RETURN_RESIDUAL_IDS.size():
		result.scaled.append(result.residuals[index] / RETURN_RESIDUAL_SCALES[index])
	cache[key] = result
	return result


static func _return_observation(route: Dictionary, layout: Dictionary) -> Dictionary:
	var state := _last_state(route)
	var station_forward: Vector3 = layout.station_tangent.normalized()
	var station_up: Vector3 = layout.station_up.normalized()
	var station_right := station_forward.cross(station_up).normalized()
	station_up = station_right.cross(station_forward).normalized()
	var forward: float = (state.position_m - layout.station_position_m).dot(station_forward)
	var approach := _approach_length(layout)
	var capture := _capture_residuals(state, layout)
	var route_length_band: Vector2 = layout.get(
		"route_length_m", RETURN_TOTAL_LENGTH_BAND_M)
	var entry_speed_band: Vector2 = layout.get("reserved_corridor", {}).get(
		"entry_speed_mps", CAPTURE_ENTRY_SPEED_MPS)
	var total_length_m := float(route.distance_m[-1]) + approach
	var half_width: float = layout.get("capture_half_width_m", 150.0)
	var half_height: float = layout.get("capture_half_height_m", 75.0)
	var residuals := [
		forward + approach - RETURN_ENTRY_POSITION_PADDING_M, capture[0], capture[1],
		state.tangent.normalized().dot(station_right),
		state.tangent.normalized().dot(station_up),
		_band_residual(total_length_m, route_length_band),
		_band_residual(float(state.speed_mps), Vector2(
			entry_speed_band.x + RETURN_ENTRY_SPEED_PADDING_MPS,
			entry_speed_band.y - RETURN_ENTRY_SPEED_PADDING_MPS)),
	]
	var margins := {
		"corridor_forward_low_m": forward + approach,
		"corridor_forward_high_m": -0.90 * approach - forward,
		"corridor_cross_m": half_width - absf(capture[0]),
		"corridor_height_m": half_height - absf(capture[1]),
		"corridor_yaw_rad": deg_to_rad(8.0) - absf(capture[2]),
		"corridor_pitch_rad": deg_to_rad(5.0) - absf(capture[3]),
		"corridor_roll_rad": deg_to_rad(30.0) - absf(capture[4]),
		"entry_speed_low_mps": float(state.speed_mps) - entry_speed_band.x,
		"entry_speed_high_mps": entry_speed_band.y - float(state.speed_mps),
		"route_length_low_m": total_length_m - route_length_band.x,
		"route_length_high_m": route_length_band.y - total_length_m,
	}
	return {"ok": true, "residuals": residuals, "margins": margins,
		"observation": {"station_forward_m": forward, "height_m": capture[1],
			"cross_track_m": capture[0], "yaw_rad": capture[2], "pitch_rad": capture[3],
			"roll_rad": capture[4], "speed_mps": state.speed_mps,
			"return_length_m": float(route.distance_m[-1]) - float(route.distance_m[0]),
			"route_total_length_m": total_length_m}}


static func _band_residual(value: float, band: Vector2) -> float:
	return minf(0.0, value - band.x) + maxf(0.0, value - band.y)


static func _margins_are_valid(margins: Dictionary) -> bool:
	for margin in margins.values():
		if not is_finite(float(margin)) or float(margin) < 0.0:
			return false
	return true


static func _approach_length(layout: Dictionary) -> float:
	var corridor: Variant = layout.get("reserved_corridor")
	if corridor is Dictionary:
		return float(corridor.get("minimum_length_m", 0.0))
	return 0.0


static func _add_capture_and_brakes(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, coefficients: Array,
	brake: Dictionary
) -> void:
	for capture_span: Dictionary in _capture_spans(coefficients):
		_add_record(spans, metadata, propulsion, capture_span, "capture", 0, 2.0)
	for terminal_span: Dictionary in brake.spans:
		var station_mode: bool = terminal_span.mode == "station"
		_add_record(spans, metadata, propulsion, terminal_span,
			"station" if station_mode else "brakes", 0, 0.0 if station_mode else 2.0)


static func _capture_spans(coefficients: Array) -> Array:
	var roll_peak: float = coefficients[4] / (
		2.0 * CAPTURE_STEERING_DURATION_S * COMPACT_PULSE_AREA)
	return [
		Motion.span("capture/early", CAPTURE_STEERING_DURATION_S, "moving",
			Motion.quintic(1.0, 1.0 + coefficients[2]), Motion.compact_pulse(coefficients[0]),
			Motion.constant(0.0), Motion.compact_pulse(roll_peak)),
		Motion.span("capture/late", CAPTURE_STEERING_DURATION_S, "moving",
			Motion.quintic(1.0 + coefficients[2], 1.0 + coefficients[3]),
			Motion.compact_pulse(coefficients[1]), Motion.constant(0.0),
			Motion.compact_pulse(roll_peak)),
		Motion.span("capture/terminal-shoulder", CAPTURE_TERMINAL_DURATION_S, "moving",
			Motion.quintic(1.0 + coefficients[3], 1.0), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
	]


static func _solve_capture(start: Dictionary, layout: Dictionary, settings: Dictionary) -> Dictionary:
	var coefficients: Array = layout.get("capture_seed", [0.0, 0.0, 0.0, 0.0, 0.0]).duplicate()
	if coefficients.size() != 5:
		return _capture_failure("capture seed must contain five coefficients", 0)
	var corridor: Variant = layout.get("reserved_corridor")
	if not corridor is Dictionary or not corridor.get("entry_speed_mps") is Vector2:
		return _capture_failure("capture corridor contract is incomplete", 0)
	var brake_length_m: float = float(corridor.get("brake_length_m", NAN))
	var entry_speed_mps: Vector2 = corridor.entry_speed_mps
	var forward_offset_m: float = (start.position_m - layout.station_position_m).dot(
		layout.station_tangent.normalized())
	if not is_finite(forward_offset_m) or forward_offset_m < -_approach_length(layout) \
			or forward_offset_m > -brake_length_m:
		return _capture_failure("capture entry is outside its declared partition", 0)
	if float(start.speed_mps) < entry_speed_mps.x or float(start.speed_mps) > entry_speed_mps.y:
		return _capture_failure("capture entry speed is outside its declared band", 0)
	for index in 5:
		coefficients[index] = clampf(float(coefficients[index]),
			CAPTURE_COEFFICIENT_BOUNDS[index][0], CAPTURE_COEFFICIENT_BOUNDS[index][1])
	var cache := {}
	var residuals: Array = []
	var conditioning := {}
	var evaluate := func(candidate: Array) -> Dictionary:
		return _capture_evaluation(start, layout, candidate, settings, cache)
	for _iteration in 7:
		var base := _capture_evaluation(start, layout, coefficients, settings, cache)
		if not base.ok:
			return base
		residuals = base.residuals
		if _capture_converged(residuals):
			break
		var finite_difference := _finite_difference_jacobian(coefficients, base.scaled,
			CAPTURE_COEFFICIENT_BOUNDS, [0.02, 0.02, 0.02, 0.02, 0.04], evaluate)
		if not finite_difference.ok:
			return finite_difference
		conditioning = _matrix_conditioning(finite_difference.jacobian)
		conditioning["evaluated_vector"] = coefficients.duplicate()
		if not conditioning.ok:
			return _capture_failure("capture Jacobian is ill-conditioned", cache.size(),
				base.residuals, base.margins, {"conditioning": conditioning})
		var step := _linear_solve(finite_difference.jacobian, base.scaled)
		if step.is_empty():
			return _capture_failure("capture Jacobian is singular", cache.size(),
				base.residuals, base.margins)
		for index in 5:
			coefficients[index] = clampf(coefficients[index] - step[index],
				CAPTURE_COEFFICIENT_BOUNDS[index][0], CAPTURE_COEFFICIENT_BOUNDS[index][1])
	var fine := _capture_evaluation(start, layout, coefficients, settings, cache)
	if not fine.ok:
		return fine
	if not _capture_converged(fine.residuals):
		return _capture_failure("capture did not converge: %s" % str(fine.residuals),
			cache.size(), fine.residuals, fine.margins,
			{"accepted_values": coefficients})
	var coarse_settings := settings.duplicate()
	coarse_settings.step_s = COARSE_STEP_S
	var coarse := _capture_evaluation(start, layout, coefficients, coarse_settings, cache)
	if not coarse.ok:
		return coarse
	if cache.size() > MAX_CAPTURE_EVALUATIONS:
		return _capture_failure("capture exceeded %d unique evaluations" %
			MAX_CAPTURE_EVALUATIONS, cache.size(), fine.residuals, fine.margins)
	if not _capture_coarse_converged(coarse.residuals) or _maximum_residual_delta(
			coarse.residuals, fine.residuals) > 0.02:
		return _capture_failure("capture coarse/fine residuals disagree", cache.size(),
			fine.residuals, fine.margins, {"coarse_residuals": coarse.residuals.duplicate()})
	if conditioning.get("evaluated_vector") != coefficients:
		if cache.size() > MAX_CAPTURE_EVALUATIONS - coefficients.size():
			return _capture_failure("capture lacks budget for accepted-point conditioning",
				cache.size(), fine.residuals, fine.margins,
				{"accepted_values": coefficients})
		var accepted_difference := _finite_difference_jacobian(
			coefficients, fine.scaled, CAPTURE_COEFFICIENT_BOUNDS,
			[0.02, 0.02, 0.02, 0.02, 0.04], evaluate)
		if not accepted_difference.ok:
			return accepted_difference
		conditioning = _matrix_conditioning(accepted_difference.jacobian)
		conditioning["evaluated_vector"] = coefficients.duplicate()
		if not conditioning.ok:
			return _capture_failure("accepted capture Jacobian is ill-conditioned",
				cache.size(), fine.residuals, fine.margins,
				{"conditioning": conditioning, "accepted_values": coefficients})
	var margins := _capture_margins(coefficients, fine.route, layout)
	for margin in margins.values():
		if not is_finite(float(margin)) or float(margin) < 0.0:
			return _capture_failure("solved capture violates an inequality: %s" %
				str(margins), cache.size(), fine.residuals, margins,
				{"conditioning": conditioning})
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"coefficients": coefficients,
		"residuals": coarse.residuals,
		"fine_residuals": fine.residuals,
		"unique_evaluations": cache.size(),
		"margins": margins,
		"conditioning": conditioning,
	}


static func _capture_evaluation(
	start: Dictionary, layout: Dictionary, coefficients: Array, settings: Dictionary,
	cache: Dictionary
) -> Dictionary:
	var key := "%.6f:" % float(settings.step_s)
	for coefficient in coefficients:
		key += "%.12f," % float(coefficient)
	if cache.has(key):
		return cache[key]
	if cache.size() >= MAX_CAPTURE_EVALUATIONS:
		return _capture_failure("capture exceeded %d unique evaluations" %
			MAX_CAPTURE_EVALUATIONS, cache.size())
	var route := Motion.integrate(start, _capture_spans(coefficients), settings)
	if not route.get("ok", false):
		var failed := _capture_failure("capture candidate failed: %s" %
			", ".join(route.get("errors", [])), cache.size() + 1)
		cache[key] = failed
		return failed
	var margins := _capture_inequality_margins(route, layout)
	var residuals := _capture_residuals(_last_state(route), layout)
	var result := {"ok": true, "route": route, "residuals": residuals,
		"margins": margins,
		"scaled": [residuals[0] / 50.0, residuals[1] / 30.0,
			residuals[2] / 0.5, residuals[3] / 0.35, residuals[4] / 0.5]}
	cache[key] = result
	return result


static func _capture_residuals(state: Dictionary, layout: Dictionary) -> Array:
	var forward: Vector3 = layout.station_tangent.normalized()
	var station_up: Vector3 = layout.station_up.normalized()
	var right := forward.cross(station_up).normalized()
	station_up = right.cross(forward).normalized()
	var delta: Vector3 = state.position_m - layout.station_position_m
	var tangent: Vector3 = state.tangent
	var rider_up: Vector3 = state.rider_up
	var yaw := atan2(tangent.dot(right), tangent.dot(forward))
	var pitch := asin(clampf(tangent.dot(station_up), -1.0, 1.0))
	var reference_up := (station_up - tangent * station_up.dot(tangent)).normalized()
	var actual_up := (rider_up - tangent * rider_up.dot(tangent)).normalized()
	var roll := atan2(tangent.dot(reference_up.cross(actual_up)), reference_up.dot(actual_up))
	return [delta.dot(right), delta.dot(station_up), yaw, pitch, roll]


static func _capture_converged(residuals: Array) -> bool:
	if residuals.size() != CAPTURE_RESIDUAL_TOLERANCES.size():
		return false
	for index in CAPTURE_RESIDUAL_TOLERANCES.size():
		if absf(float(residuals[index])) > CAPTURE_RESIDUAL_TOLERANCES[index]:
			return false
	return true


static func _capture_coarse_converged(residuals: Array) -> bool:
	for index in CAPTURE_COARSE_RESIDUAL_TOLERANCES.size():
		if absf(float(residuals[index])) > CAPTURE_COARSE_RESIDUAL_TOLERANCES[index]:
			return false
	return true


static func _maximum_residual_delta(a: Array, b: Array) -> float:
	var result := 0.0
	for index in 5:
		var scale := 1.0 if index < 2 else 50.0
		result = maxf(result, absf(a[index] - b[index]) * scale)
	return result


static func _capture_margins(
	coefficients: Array, route: Dictionary, layout: Dictionary
) -> Dictionary:
	var coefficient_margin := INF
	for index in 5:
		coefficient_margin = minf(coefficient_margin, minf(
			coefficients[index] - CAPTURE_COEFFICIENT_BOUNDS[index][0],
			CAPTURE_COEFFICIENT_BOUNDS[index][1] - coefficients[index]))
	var result := _capture_inequality_margins(route, layout)
	var end := _last_state(route)
	var corridor: Dictionary = layout.reserved_corridor
	var entry_speed_mps: Vector2 = corridor.entry_speed_mps
	var entry_forward_m: float = (route.position_m[0] - layout.station_position_m).dot(
		layout.station_tangent.normalized())
	var remaining_along_track_m: float = (layout.station_position_m - end.position_m).dot(
		layout.station_tangent.normalized())
	result.merge({
		"coefficient_margin": coefficient_margin,
		"speed_floor_margin_mps": end.speed_mps - 2.0,
		"remaining_along_track_m": remaining_along_track_m,
		"capture_partition_entry_m": -float(corridor.brake_length_m) - entry_forward_m,
		"brake_reserve_m": float(corridor.brake_length_m) - remaining_along_track_m,
		"entry_speed_low_mps": float(route.speed_mps[0]) - entry_speed_mps.x,
		"entry_speed_high_mps": entry_speed_mps.y - float(route.speed_mps[0]),
	}, true)
	return result


static func _capture_inequality_margins(route: Dictionary, layout: Dictionary) -> Dictionary:
	var forward: Vector3 = layout.station_tangent.normalized()
	var up: Vector3 = layout.station_up.normalized()
	var right := forward.cross(up).normalized()
	var half_width: float = layout.get("capture_half_width_m", CAPTURE_HALF_WIDTH_M)
	var half_height: float = layout.get("capture_half_height_m", CAPTURE_HALF_HEIGHT_M)
	var maximum_cross := 0.0
	var maximum_height := 0.0
	var minimum_forward_low := INF
	var minimum_forward_high := INF
	var minimum_speed := INF
	var maximum_normal := 0.0
	var maximum_lateral := 0.0
	var maximum_roll := 0.0
	for index in route.position_m.size():
		var delta: Vector3 = route.position_m[index] - layout.station_position_m
		maximum_cross = maxf(maximum_cross, absf(delta.dot(right)))
		maximum_height = maxf(maximum_height, absf(delta.dot(up)))
		var forward_offset := delta.dot(forward)
		minimum_forward_low = minf(minimum_forward_low,
			_approach_length(layout) + forward_offset)
		minimum_forward_high = minf(minimum_forward_high, -forward_offset)
		minimum_speed = minf(minimum_speed, route.speed_mps[index])
		maximum_normal = maxf(maximum_normal, absf(route.normal_g[index]))
		maximum_lateral = maxf(maximum_lateral, absf(route.lateral_g[index]))
		maximum_roll = maxf(maximum_roll, absf(route.roll_rate_rad_s[index]))
	return {
		"corridor_cross_m": half_width - maximum_cross,
		"corridor_height_m": half_height - maximum_height,
		"corridor_forward_low_m": minimum_forward_low,
		"corridor_forward_high_m": minimum_forward_high,
		"speed_floor_mps": minimum_speed - 2.0,
		"normal_force_g": 8.0 - maximum_normal,
		"lateral_force_g": 4.7 - maximum_lateral,
		"roll_rate_rad_s": deg_to_rad(120.0) - maximum_roll,
	}


static func _finite_difference_jacobian(
	base_vector: Array, base_scaled: Array, bounds: Array, deltas: Array,
	evaluate: Callable
) -> Dictionary:
	var size := base_vector.size()
	var jacobian: Array = []
	for _row in size:
		var row := []
		row.resize(size)
		row.fill(0.0)
		jacobian.append(row)
	for column in size:
		var delta := float(deltas[column])
		if base_vector[column] + delta < bounds[column][0] \
				or base_vector[column] + delta > bounds[column][1]:
			delta = -delta
		if base_vector[column] + delta < bounds[column][0] \
				or base_vector[column] + delta > bounds[column][1]:
			return _failure("finite-difference probe has no bounded direction", "solve")
		var probe := base_vector.duplicate()
		probe[column] += delta
		var observed: Dictionary = evaluate.call(probe)
		if not observed.ok:
			return observed
		for row in size:
			jacobian[row][column] = (observed.scaled[row] - base_scaled[row]) / delta
	return {"ok": true, "jacobian": jacobian}


static func _linear_solve(matrix: Array, residual: Array) -> Array:
	var size := matrix.size()
	var augmented: Array = []
	for row in size:
		augmented.append(matrix[row].duplicate())
		augmented[row].append(residual[row])
	for column in size:
		var pivot := column
		for row in range(column + 1, size):
			if absf(augmented[row][column]) > absf(augmented[pivot][column]):
				pivot = row
		if absf(augmented[pivot][column]) < 0.000000001:
			return []
		var temporary = augmented[column]
		augmented[column] = augmented[pivot]
		augmented[pivot] = temporary
		var divisor: float = augmented[column][column]
		for index in range(column, size + 1):
			augmented[column][index] /= divisor
		for row in size:
			if row == column:
				continue
			var factor: float = augmented[row][column]
			for index in range(column, size + 1):
				augmented[row][index] -= factor * augmented[column][index]
	var solution := []
	for row in size:
		solution.append(augmented[row][size])
	return solution


static func _matrix_conditioning(matrix: Array) -> Dictionary:
	var work := matrix.duplicate(true)
	var low := INF
	var high := 0.0
	for column in work.size():
		var pivot := column
		for row in range(column + 1, work.size()):
			if absf(work[row][column]) > absf(work[pivot][column]):
				pivot = row
		var magnitude := absf(work[pivot][column])
		low = minf(low, magnitude)
		high = maxf(high, magnitude)
		if magnitude < 0.000001:
			return {"ok": false, "minimum_pivot": magnitude, "pivot_ratio": 0.0}
		var temporary = work[column]
		work[column] = work[pivot]
		work[pivot] = temporary
		for row in range(column + 1, work.size()):
			var factor: float = work[row][column] / work[column][column]
			for index in range(column, work.size()):
				work[row][index] -= factor * work[column][index]
	var ratio := low / high
	return {"ok": ratio >= 0.0001, "minimum_pivot": low,
		"maximum_pivot": high, "pivot_ratio": ratio}


static func _solve_brakes(start: Dictionary, layout: Dictionary) -> Dictionary:
	var remaining: float = (layout.station_position_m - start.position_m).dot(
		layout.station_tangent.normalized())
	var corridor: Variant = layout.get("reserved_corridor")
	if not corridor is Dictionary or not is_finite(float(corridor.get("brake_length_m", NAN))):
		return _failure("brake corridor contract is incomplete", "brake")
	if remaining > float(corridor.brake_length_m) + TERMINAL_DISTANCE_TOLERANCE_M:
		return _failure("brake entry exceeds its declared reserve", "brake",
			{"remaining_distance_m": remaining, "brake_length_m": corridor.brake_length_m})
	var station_duration := _coast_time(2.0, 1.0)
	var station_distance := _coast_distance(2.0, 1.0)
	var frame_residuals := _capture_residuals(start, layout)
	if absf(float(frame_residuals[2])) > CAPTURE_RESIDUAL_TOLERANCES[2] \
			or absf(float(frame_residuals[3])) > CAPTURE_RESIDUAL_TOLERANCES[3] \
			or absf(float(frame_residuals[4])) > CAPTURE_RESIDUAL_TOLERANCES[4]:
		return _failure("capture terminal frame is not the straight station frame", "brake")
	if not is_finite(remaining) or not is_finite(station_duration) \
			or not is_finite(station_distance) \
			or remaining <= station_distance:
		return _failure("station creep is infeasible in the remaining approach", "brake")
	var moving_target := remaining - station_distance
	var active_estimate := 2.0 * moving_target / (float(start.speed_mps) + 2.0)
	var resistance_loss := Motion.resistance(0.5 * (float(start.speed_mps) + 2.0),
		ROLLING_MPS2, AERO_PER_M).x * active_estimate
	var parameters := [active_estimate - 2.0 * BRAKE_SHOULDER_DURATION_S,
		0.80 * (float(start.speed_mps) - 2.0 - resistance_loss) / (
			Motion.G0 * (active_estimate - BRAKE_SHOULDER_DURATION_S))]
	for index in 2:
		if not is_finite(parameters[index]) \
				or parameters[index] <= BRAKE_PARAMETER_BOUNDS[index][0] \
				or parameters[index] >= BRAKE_PARAMETER_BOUNDS[index][1]:
			return _failure("brake initial estimate is outside its parameter bounds", "brake",
				{"remaining_distance_m": remaining, "entry_speed_mps": start.speed_mps,
					"active_estimate_s": active_estimate, "initial_values": parameters})
	var evaluation_count := [0]
	var base := {}
	var conditioning := {}
	var evaluate := func(candidate: Array) -> Dictionary:
		return _brake_evaluation(
			start, candidate, moving_target, _settings(0.01), evaluation_count)
	for iteration in BRAKE_NEWTON_ITERATIONS:
		base = evaluate.call(parameters)
		if not base.ok:
			return base
		var finite_difference := _finite_difference_jacobian(parameters, base.scaled,
			BRAKE_PARAMETER_BOUNDS, [-0.01, -0.005], evaluate)
		if not finite_difference.ok:
			return finite_difference
		conditioning = _matrix_conditioning(finite_difference.jacobian)
		conditioning["evaluated_vector"] = parameters.duplicate()
		if not conditioning.ok:
			return _brake_failure("brake Jacobian is ill-conditioned",
				evaluation_count[0], {"conditioning": conditioning})
		if _brake_converged(base.residuals):
			break
		if iteration + 1 == BRAKE_NEWTON_ITERATIONS:
			return _brake_failure(
				"brake solve exhausted its iteration budget", evaluation_count[0])
		var step := _linear_solve(finite_difference.jacobian, base.scaled)
		if step.is_empty():
			return _brake_failure("brake Jacobian is singular", evaluation_count[0])
		for index in 2:
			parameters[index] -= BRAKE_NEWTON_STEP * step[index]
			if parameters[index] <= BRAKE_PARAMETER_BOUNDS[index][0] \
					or parameters[index] >= BRAKE_PARAMETER_BOUNDS[index][1]:
				return _brake_failure("brake solve reached a parameter bound", evaluation_count[0])
	if not _brake_converged(base.get("residuals", [])):
		return _brake_failure("brake solve did not produce an accepted point", evaluation_count[0])
	var confirmations := []
	for step_s in [COARSE_STEP_S, FINE_STEP_S]:
		var observed := _brake_evaluation(
			start, parameters, moving_target, _settings(step_s), evaluation_count)
		if not observed.ok:
			return observed
		confirmations.append(observed)
		if not _brake_converged(observed.residuals) \
				or not _brake_observations_agree(base.residuals, observed.residuals):
			return _brake_failure(
				"brake production/coarse/fine verification disagrees", evaluation_count[0])
	var terminal_spans := _brake_spans(parameters)
	terminal_spans.append(Motion.span("station/creep", station_duration, "station",
		Motion.constant(1.0), Motion.constant(0.0), Motion.constant(0.0), Motion.constant(0.0)))
	return {"ok": true, "errors": PackedStringArray(), "spans": terminal_spans, "report": {
			"parameter_ids": BRAKE_PARAMETER_IDS, "parameter_bounds": BRAKE_PARAMETER_BOUNDS,
			"accepted_values": parameters, "hold_duration_s": parameters[0],
			"active_duration_s": parameters[0] + 2.0 * BRAKE_SHOULDER_DURATION_S,
			"brake_peak_g": parameters[1], "unique_evaluations": evaluation_count[0],
			"max_unique_evaluations": MAX_BRAKE_EVALUATIONS,
			"production_observation": _brake_report_observation(base, start),
			"coarse_observation": _brake_report_observation(confirmations[0], start),
			"fine_observation": _brake_report_observation(confirmations[1], start),
			"conditioning": conditioning, "brake_entry_speed_mps": float(start.speed_mps),
			"remaining_distance_m": remaining,
			"moving_distance_m": base.route.distance_m[-1] - float(start.distance_m),
			"station_distance_m": station_distance, "distance_residual_m": base.residuals[0],
			"moving_boundary_speed_mps": base.route.speed_mps[-1],
			"terminal_creep_speed_mps": 1.0, "positive_drive_allowed": false,
		}}


static func _brake_evaluation(start: Dictionary, parameters: Array,
	moving_target: float, settings: Dictionary, evaluation_count: Array
) -> Dictionary:
	if evaluation_count[0] >= MAX_BRAKE_EVALUATIONS:
		return _brake_failure("brake exceeded its evaluation cap", evaluation_count[0])
	evaluation_count[0] += 1
	var result := _brake_observation(start, parameters, moving_target, settings)
	if not result.ok:
		return _brake_failure("brake candidate failed central integration", evaluation_count[0])
	return result


static func _brake_observation(start: Dictionary, parameters: Array,
	moving_target: float, settings: Dictionary) -> Dictionary:
	var route := Motion.integrate(start, _brake_spans(parameters), settings)
	if not route.get("ok", false):
		return {"ok": false}
	var residuals := [route.distance_m[-1] - float(start.get("distance_m", 0.0)) - moving_target,
		float(route.speed_mps[-1]) - 2.0]
	return {"ok": true, "route": route, "residuals": residuals, "scaled": [
		residuals[0] / 25.0,
		(float(route.speed_mps[-1]) - BRAKE_BOUNDARY_INTERIOR_MPS) / 5.0]}


static func _brake_report_observation(observation: Dictionary, start: Dictionary) -> Dictionary:
	return {"residuals": observation.residuals.duplicate(),
		"moving_distance_m": observation.route.distance_m[-1] - float(start.distance_m),
		"moving_boundary_speed_mps": observation.route.speed_mps[-1]}


static func _brake_failure(message: String, evaluation_count: int,
	diagnostics: Dictionary = {}) -> Dictionary:
	diagnostics["evaluation_count"] = evaluation_count
	return _failure(message, "brake", diagnostics)


static func _brake_converged(residuals: Array) -> bool:
	return absf(residuals[0]) <= TERMINAL_DISTANCE_TOLERANCE_M \
		and absf(residuals[1]) <= BRAKE_BOUNDARY_TOLERANCE_MPS


static func _brake_observations_agree(a: Array, b: Array) -> bool:
	return absf(a[0] - b[0]) <= TERMINAL_DISTANCE_TOLERANCE_M \
		and absf(a[1] - b[1]) <= BRAKE_BOUNDARY_TOLERANCE_MPS


static func _brake_spans(parameters: Array) -> Array:
	var hold_duration: float = parameters[0]
	var peak_g: float = parameters[1]
	return [
		Motion.span("brakes/engage", BRAKE_SHOULDER_DURATION_S, "moving",
			Motion.constant(1.0), Motion.constant(0.0), Motion.quintic(0.0, -peak_g),
			Motion.constant(0.0)),
		Motion.span("brakes/hold", hold_duration, "moving",
			Motion.constant(1.0), Motion.constant(0.0), Motion.constant(-peak_g),
			Motion.constant(0.0)),
		Motion.span("brakes/release", BRAKE_SHOULDER_DURATION_S, "moving",
			Motion.constant(1.0), Motion.constant(0.0), Motion.quintic(-peak_g, 0.0),
			Motion.constant(0.0)),
	]


static func _coast_time(from_speed: float, to_speed: float) -> float:
	if from_speed <= to_speed or ROLLING_MPS2 <= 0.0:
		return INF
	if AERO_PER_M <= 0.0:
		return (from_speed - to_speed) / ROLLING_MPS2
	var scale := sqrt(AERO_PER_M / ROLLING_MPS2)
	return (atan(from_speed * scale) - atan(to_speed * scale)) \
		/ sqrt(ROLLING_MPS2 * AERO_PER_M)


static func _coast_distance(from_speed: float, to_speed: float) -> float:
	if from_speed <= to_speed or ROLLING_MPS2 <= 0.0:
		return INF
	if AERO_PER_M <= 0.0:
		return (from_speed * from_speed - to_speed * to_speed) / (2.0 * ROLLING_MPS2)
	return log((ROLLING_MPS2 + AERO_PER_M * from_speed * from_speed) \
		/ (ROLLING_MPS2 + AERO_PER_M * to_speed * to_speed)) / (2.0 * AERO_PER_M)


## The role ids a plan declares, in its own authored order.
static func plan_role_ids(plan: Dictionary) -> Array:
	var ids: Array = []
	for role in plan.get("roles", []):
		if not role is Dictionary:
			return []
		ids.append(str(role.get("id", "")))
	return ids


## The compiled story a plan asks for: its declared role sequence and its resolved target draws.
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
	if str(planning.get("capability_id", "")).is_empty() \
			or int(planning.get("planning_integrations", 0)) != 1 \
			or not planning.get("scale") is Dictionary:
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
	if not route_band is Vector2 or route_band != Vector2(7800.0, 8200.0) \
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


static func _last_state(route: Dictionary) -> Dictionary:
	return {
		"position_m": route.position_m[-1],
		"tangent": route.tangent[-1],
		"rider_up": route.rider_up[-1],
		"speed_mps": route.speed_mps[-1],
		"distance_m": route.distance_m[-1],
		"time_s": route.time_s[-1],
	}


static func _settings(step_s: float) -> Dictionary:
	return {"step_s": step_s, "rolling_mps2": ROLLING_MPS2,
		"aero_per_m": AERO_PER_M, "gravity_mps2": Vector3.DOWN * Motion.G0}


static func _failure(
	message: String, stage: String, diagnostics: Dictionary = {}
) -> Dictionary:
	var failure := {"stage": stage, "reason": message}
	failure.merge(diagnostics, true)
	return {"ok": false, "errors": PackedStringArray([message]), "failure": failure}


static func _capture_failure(
	message: String,
	evaluation_count: int,
	residuals: Array = [],
	margins: Dictionary = {},
	diagnostics: Dictionary = {}
) -> Dictionary:
	var evidence := diagnostics.duplicate(true)
	evidence["evaluation_count"] = evaluation_count
	if not residuals.is_empty():
		evidence["residuals"] = residuals.duplicate()
	if not margins.is_empty():
		evidence["margins"] = margins.duplicate(true)
	return _failure(message, "capture", evidence)


static func _add_record(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, motion_span: Dictionary,
	role: String, propulsion_id: int, minimum_speed_mps: float, diagnostic_kind: String = ""
) -> void:
	spans.append(motion_span)
	metadata.append({"span_id": motion_span.span_id, "role_id": role,
		"propulsion_id": propulsion_id, "minimum_speed_mps": minimum_speed_mps,
		"diagnostic_kind": diagnostic_kind})
	propulsion.append(propulsion_id)


## Reconstruct which material role owns each authored span. Ownership must be total, ordered
## and contiguous: an unowned span, a split role or an unauthored role is a hard failure, never
## a silent Vector2i(-1, -1).
static func material_role_spans(spans: Array, sequence: Array = MATERIAL_ROLE_IDS) -> Dictionary:
	var role_ids: Array = sequence if not sequence.is_empty() else MATERIAL_ROLE_IDS
	var prefixes := {
		"station-launch": ["launch/"],
		"opener-twisted-drop": ["crest/", "drop/"],
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
	diagnostic_kind: String = ""
) -> void:
	var normal_profile: Dictionary = normal if normal is Dictionary else Motion.constant(float(normal))
	var lateral_profile: Dictionary = lateral if lateral is Dictionary else Motion.constant(float(lateral))
	var drive_profile: Dictionary = drive if drive is Dictionary else Motion.constant(float(drive))
	var roll_profile: Dictionary = roll if roll is Dictionary else Motion.constant(float(roll))
	spans.append(Motion.span(span_id, duration_s, mode, normal_profile, lateral_profile,
		drive_profile, roll_profile))
	metadata.append({"span_id": span_id, "role_id": role,
		"propulsion_id": propulsion_id,
		"minimum_speed_mps": minimum_speed_mps,
		"diagnostic_kind": diagnostic_kind})
	propulsion.append(propulsion_id)
