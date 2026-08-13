class_name RideProgram
extends RefCounted

const Motion := preload("res://motion.gd")

const GENERATOR_VERSION := "time-domain-v1"
const ROLLING_MPS2 := 0.08
const AERO_PER_M := 0.000075
const COMPACT_PULSE_AREA := 100.0 / 231.0
const COARSE_STEP_S := 0.05
const FINE_STEP_S := 0.025
const MAX_CAPTURE_EVALUATIONS := 40
const MAX_RETURN_EVALUATIONS := 24
const RETURN_PARAMETER_IDS := [
	"turn_a_bank_rad", "turn_a_core_s", "height_a_half_s",
	"turn_b_bank_rad", "turn_b_core_s", "height_b_recovery_s",
]
const RETURN_PARAMETER_BOUNDS := [
	[0.349065850398866, 0.8377580409572781], [2.5, 7.0], [6.0, 11.0],
	[1.0471975511965976, 1.3599968197358412], [1.5, 5.0], [0.9, 3.5],
]
const RETURN_SEED := [0.4886921905584123, 4.5, 8.4, 1.3439035240356338, 2.9, 1.8]
const RETURN_OUTPUT_IDS := [
	"station_forward_m", "height_m", "cross_track_m", "yaw_rad", "pitch_rad", "roll_rad",
]
const RETURN_OUTPUT_BOUNDS := [
	[-450.0, -405.0], [-30.0, 30.0], [-50.0, 50.0],
	[-0.13962634015954636, 0.13962634015954636],
	[-0.08726646259971647, 0.08726646259971647],
	[-0.13962634015954636, 0.13962634015954636],
]
const RETURN_OUTPUT_SCALES := [
	15.0, 15.0, 25.0, 0.06981317007977318, 0.04363323129985824, 0.06981317007977318,
]
const RETURN_TARGET := [
	-413.8176585379036, 3.542414464340024, -0.9589346302880815,
	0.01954530591190462, -0.004588670638026367, 0.04616595364095083,
]
const RETURN_TARGET_TOLERANCE := 0.02
const RETURN_FINE_TOLERANCES := [0.01, 0.01, 0.01, 0.0001, 0.0001, 0.0001]
const STATION_APPROACH_LENGTH_M := 450.0
const CAPTURE_HALF_WIDTH_M := 150.0
const CAPTURE_HALF_HEIGHT_M := 75.0
const CAPTURE_STEERING_DURATION_S := 1.3276187084937188
const CAPTURE_TERMINAL_DURATION_S := 0.5
const BRAKE_SHOULDER_DURATION_S := 0.6
const BRAKE_PARAMETER_IDS := ["hold_duration_s", "peak_g"]
const BRAKE_PARAMETER_BOUNDS := [[2.0, 5.0], [0.0, 2.25]]
const MAX_BRAKE_EVALUATIONS := 24
const BRAKE_NEWTON_ITERATIONS := 7
const BRAKE_NEWTON_STEP := 0.95
const BRAKE_BOUNDARY_TOLERANCE_MPS := 0.0001
const BRAKE_BOUNDARY_INTERIOR_MPS := 2.0 + 0.5 * BRAKE_BOUNDARY_TOLERANCE_MPS
const TERMINAL_DISTANCE_TOLERANCE_M := 0.05
const CAPTURE_RESIDUAL_TOLERANCES := [0.05, 0.05, 0.00001, 0.00001, 0.00001]
const CAPTURE_COEFFICIENT_BOUNDS := [
	[-0.9, 0.9], [-0.9, 0.9], [-0.45, 0.45], [-0.45, 0.45], [-1.2, 1.2],
]


static func compile(
	seed: int, config: Dictionary, layout: Dictionary,
	initial_state: Dictionary
) -> Dictionary:
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

	_begin_gesture(gestures, "station-launch", spans.size(), "launch")
	_add(spans, metadata, propulsion, "launch/ramp", 0.31, "station",
		1.0, 0.0, Motion.quintic(0.0, 4.0), 0.0, "launch", 1, 0.0, "launch")
	_add(spans, metadata, propulsion, "launch/core", 1.4928103277564437, "moving",
		1.0, 0.0, 4.0, 0.0, "launch", 1, 2.0, "launch")
	_add(spans, metadata, propulsion, "launch/release", 0.31, "moving",
		1.0, 0.0, Motion.quintic(4.0, 0.0), 0.0, "launch", 1, 2.0, "launch")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "opener", spans.size(), "twisted_drop")
	_add(spans, metadata, propulsion, "crest/rise-shoulder", 1.2, "moving",
		Motion.quintic(1.0, 3.7), 0.0, 0.0, 0.0,
		"twisted-drop", 0, 2.0, "twisted_drop")
	_add(spans, metadata, propulsion, "crest/twist-in", 1.2, "moving",
		Motion.quintic(3.7, 1.0), Motion.compact_pulse(0.2), 0.0,
		Motion.compact_pulse(0.43676864531157017),
		"twisted-drop", 0, 2.0, "twisted_drop")
	_add(spans, metadata, propulsion, "drop/commit", 4.79999999999999, "moving",
		Motion.quintic(1.0, -0.9), Motion.compact_pulse(-0.2), 0.0,
		Motion.compact_pulse(0.43676864531157017),
		"twisted-drop", 0, 2.0, "twisted_drop")
	_add(spans, metadata, propulsion, "drop/core", 3.094817391662892, "moving",
		Motion.quintic(-0.9, 1.0), Motion.compact_pulse(0.2), 0.0,
		Motion.compact_pulse(-0.6784482475514162),
		"twisted-drop", 0, 2.0, "twisted_drop")
	_add(spans, metadata, propulsion, "drop/pullout", 0.8000000000000002, "moving",
		Motion.quintic(1.0, 3.7), Motion.compact_pulse(-0.2), 0.0,
		Motion.compact_pulse(-0.6784482475514162),
		"twisted-drop", 0, 2.0, "twisted_drop")
	_add(spans, metadata, propulsion, "drop/release", 1.9672258362758237, "moving",
		Motion.quintic(3.7, 1.0), 0.0, 0.0, 0.0,
		"twisted-drop", 0, 2.0, "twisted_drop")
	_add(spans, metadata, propulsion, "teardrop/bank-in", 1.5000000000043456, "moving",
		Motion.quintic(1.0, 1.235677199441744), 0.0, 0.0,
		Motion.compact_pulse(0.966940012289401), "teardrop", 0, 2.0, "overbank")
	_add(spans, metadata, propulsion, "teardrop/overbanked-arc", 11.232051014082609,
		"moving", 1.235677199441744, 0.0, 0.0, 0.0,
		"teardrop", 0, 2.0, "overbank")
	_add(spans, metadata, propulsion, "teardrop/bank-out", 1.5000000000043456, "moving",
		Motion.quintic(1.235677199441744, 1.0), 0.0, 0.0,
		Motion.compact_pulse(-0.966940012289401), "teardrop", 0, 2.0, "overbank")
	_add(spans, metadata, propulsion, "release/rise-shoulder", 1.0, "moving",
		Motion.quintic(1.0, 3.0), 0.0, 0.0, 0.0, "release", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "release/unload", 1.0, "moving",
		Motion.quintic(3.0, 1.0), 0.0, 0.0, 0.0, "release", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "release/crest", 2.434565445080618, "moving",
		Motion.quintic(1.0, -0.55), 0.0, 0.0, 0.0, "release", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "release/fall", 2.4562596640024132, "moving",
		Motion.quintic(-0.55, 1.0), 0.0, 0.0, 0.0, "release", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "release/pullout", 1.0, "moving",
		Motion.quintic(1.0, 3.0), 0.0, 0.0, 0.0, "release", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "release/settle", 1.0, "moving",
		Motion.quintic(3.0, 1.0), 0.0, 0.0, 0.0, "release", 0, 2.0, "hill")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "act-one", spans.size())
	_add_act_one(spans, metadata, propulsion)
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "escarpment-climb", spans.size())
	_add(spans, metadata, propulsion, "climb/lsm2-entry", 0.30, "moving",
		Motion.constant(1.0), Motion.constant(0.0), Motion.quintic(0.0, 1.3),
		Motion.constant(0.0), "lsm2", 2)
	_add(spans, metadata, propulsion, "climb/lsm2-core", 0.190736, "moving",
		1.0, 0.0, 1.3, 0.0, "lsm2", 2)
	_add(spans, metadata, propulsion, "climb/lsm2-release", 0.30, "moving",
		1.0, 0.0, Motion.quintic(1.3, 0.0), 0.0, "lsm2", 2)
	_add(spans, metadata, propulsion, "climb/pull-up", 2.219925, "moving",
		Motion.quintic(1.0, 3.894889), 0.0, 0.0, 0.0, "unpowered-climb")
	_add(spans, metadata, propulsion, "climb/unload", 2.186308, "moving",
		Motion.quintic(3.894889, 0.0), 0.0, 0.0, 0.0, "unpowered-climb")
	_add(spans, metadata, propulsion, "climb/ballistic", 3.34, "moving",
		0.0, 0.0, 0.0, 0.0, "unpowered-climb")
	_add(spans, metadata, propulsion, "climb/level", 0.307367, "moving",
		Motion.quintic(0.0, 1.0), 0.0, 0.0, 0.0, "unpowered-climb")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "clifftop-suspense", spans.size())
	_add(spans, metadata, propulsion, "rim/slow-crest", 2.90, "moving",
		1.0, 0.0, 0.0, 0.0, "slow-crest")
	_add(spans, metadata, propulsion, "rim/outward-bank", 1.45, "moving",
		Motion.quintic(1.0, 1.493674785), Motion.compact_pulse(0.05), 0.0,
		Motion.compact_pulse(deg_to_rad(84.15)), "outward-rim")
	_add(spans, metadata, propulsion, "rim/outward-arc", 1.0, "moving",
		1.493674785, 0.0, 0.0, 0.0, "outward-rim")
	_add(spans, metadata, propulsion, "rim/outward-release", 1.45, "moving",
		Motion.quintic(1.493674785, 1.0), Motion.compact_pulse(-0.05), 0.0,
		Motion.compact_pulse(deg_to_rad(-84.15)), "outward-rim")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "cliff-dive", spans.size(), "dive")
	_add(spans, metadata, propulsion, "dive/commit", 1.068877, "moving",
		Motion.quintic(1.0, -1.3), 0.0, 0.0, 0.0, "commit")
	_add(spans, metadata, propulsion, "dive/vertical-entry", 0.86, "moving",
		Motion.quintic(-1.3, 0.0), 0.0, 0.0, 0.0, "vertical-entry")
	_add(spans, metadata, propulsion, "dive/core", 1.76, "moving",
		0.0, 0.0, 0.0, 0.0, "core")
	_add(spans, metadata, propulsion, "dive/pullout", 1.330518, "moving",
		Motion.quintic(0.0, 4.895984), 0.0, 0.0, 0.0, "pullout")
	_add(spans, metadata, propulsion, "dive/pullout-release", 2.159790, "moving",
		Motion.quintic(4.895984, 1.0), 0.0, 0.0, 0.0, "exit")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "tunnel-lsm3", spans.size())
	_add(spans, metadata, propulsion, "tunnel/lsm3-entry", 0.30, "moving",
		Motion.constant(1.0), Motion.constant(0.0), Motion.quintic(0.0, 2.0),
		Motion.constant(0.0), "core", 3)
	_add(spans, metadata, propulsion, "tunnel/lsm3-core", 1.633337, "moving",
		1.0, 0.0, 2.0, 0.0, "core", 3)
	_add(spans, metadata, propulsion, "tunnel/lsm3-release", 0.30, "moving",
		1.0, 0.0, Motion.quintic(2.0, 0.0), 0.0, "core", 3)
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "marquee-camelback", spans.size(), "hill")
	_add(spans, metadata, propulsion, "camelback/pull-up", 1.997005, "moving",
		Motion.quintic(1.0, 4.933250), 0.0, 0.0, 0.0, "rise")
	_add(spans, metadata, propulsion, "camelback/unload", 3.2, "moving",
		Motion.quintic(4.933250, -1.286153), 0.0, 0.0, 0.0, "rise")
	_add(spans, metadata, propulsion, "camelback/crest", 3.852550, "moving",
		-1.286153, 0.0, 0.0, 0.0, "crest")
	_add(spans, metadata, propulsion, "camelback/fall", 4.566536, "moving",
		Motion.quintic(-1.286153, 4.785225), 0.0, 0.0, 0.0, "fall")
	_add(spans, metadata, propulsion, "camelback/pullout-release", 0.794140, "moving",
		Motion.quintic(4.785225, 1.0), 0.0, 0.0, 0.0, "exit")
	_end_gesture(gestures, metadata, spans.size() - 1)

	var return_prefix := Motion.integrate(initial_state, spans, _settings(COARSE_STEP_S))
	if not return_prefix.get("ok", false):
		return _failure("upstream return handoff failed integration", "return")
	var solved_return := _solve_return(_last_state(return_prefix), layout)
	if not solved_return.ok:
		return solved_return
	var settings := _settings(0.01)
	_begin_gesture(gestures, "raceway-return", spans.size())
	_add_raceway(spans, metadata, propulsion, solved_return.parameters)
	_end_gesture(gestures, metadata, spans.size() - 1)

	var prefix := Motion.integrate(initial_state, spans, settings)
	if not prefix.get("ok", false):
		return _failure("prefix integration failed: %s" % ", ".join(
			prefix.get("errors", [])), "prefix")
	var capture_start := _last_state(prefix)
	var capture := _solve_capture(capture_start, layout, _settings(COARSE_STEP_S))
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
		gesture["peak_analytic_normal_onset_gps"] = _peak_analytic_normal_onset(
			spans, int(gesture.first_span), int(gesture.last_span))
		for span_index in range(int(gesture.first_span), int(gesture.last_span) + 1):
			metadata[span_index]["gesture_id"] = gesture.story_slot_id
			metadata[span_index]["story_slot_id"] = gesture.story_slot_id
		if gesture.story_slot_id == "tunnel-lsm3":
			tunnels.append(Vector2i(gesture.first_span, gesture.last_span))

	var seam_errors := _validate_control_seams(spans)
	if not seam_errors.is_empty():
		return {"ok": false, "errors": seam_errors}
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"generator_version": GENERATOR_VERSION,
		"seed": seed,
		"config": config,
		"spans": spans,
		"span_metadata": metadata,
		"gesture_spans": gestures,
		"propulsion_by_span": propulsion,
		"minimum_speed_by_span": minimum_speeds,
		"tunnel_span_ranges": tunnels,
		"return_plan": solved_return.report,
		"capture_plan": {
			"status": "solved",
			"coefficients": capture.coefficients,
			"coefficient_ids": ["early_lateral", "late_lateral", "early_normal",
				"late_normal", "roll_area_rad"],
			"coefficient_bounds": CAPTURE_COEFFICIENT_BOUNDS,
			"unique_evaluations": capture.unique_evaluations,
			"max_unique_coarse_evaluations": MAX_CAPTURE_EVALUATIONS,
			"residual_ids": ["cross_track_m", "height_m", "yaw_rad", "pitch_rad", "roll_rad"],
			"residual_tolerances": CAPTURE_RESIDUAL_TOLERANCES,
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
		"settings": _settings(0.01),
	}


static func _add_act_one(spans: Array, metadata: Array, propulsion: PackedInt32Array) -> void:
	_add(spans, metadata, propulsion, "act-one/immelmann-entry", 0.33, "moving",
		Motion.quintic(1.0, 5.2), 0.0, 0.0, 0.0, "giant-inversion", 0, 2.0, "immelmann")
	_add(spans, metadata, propulsion, "act-one/immelmann-hold", 2.838395758344, "moving",
		5.2, 0.0, 0.0, 0.0, "giant-inversion", 0, 2.0, "immelmann")
	_add(spans, metadata, propulsion, "act-one/immelmann-unload", 0.49, "moving",
		Motion.quintic(5.2, -1.0), 0.0, 0.0, 0.0,
		"giant-inversion", 0, 2.0, "immelmann")
	_add(spans, metadata, propulsion, "act-one/immelmann-roll", 1.75, "moving",
		Motion.quintic(-1.0, 0.0), Motion.compact_pulse(1.5), 0.0,
		Motion.compact_pulse(deg_to_rad(118.8)), "giant-inversion", 0, 2.0, "immelmann")
	_add(spans, metadata, propulsion, "act-one/immelmann-recover", 1.75, "moving",
		Motion.quintic(0.0, 1.0), Motion.compact_pulse(1.5), 0.0,
		Motion.compact_pulse(deg_to_rad(118.8)), "giant-inversion", 0, 2.0, "immelmann")

	_add(spans, metadata, propulsion, "act-one/cutback-entry", 0.80036457, "moving",
		Motion.quintic(1.0, 4.16194327), 0.0, 0.0,
		Motion.compact_pulse(deg_to_rad(108.213109)), "cutback", 0, 2.0, "cutback")
	_add(spans, metadata, propulsion, "act-one/cutback-arc", 1.67497928, "moving",
		Motion.quintic(4.16194327, 2.62954854), 0.0, 0.0,
		Motion.compact_pulse(deg_to_rad(108.213109)), "cutback", 0, 2.0, "cutback")
	_add(spans, metadata, propulsion, "act-one/cutback-reverse", 2.52077154, "moving",
		Motion.quintic(2.62954854, 3.82368727), 0.0, 0.0,
		Motion.compact_pulse(deg_to_rad(-50.80747228)), "cutback", 0, 2.0, "cutback")
	_add(spans, metadata, propulsion, "act-one/cutback-release", 1.17767523, "moving",
		Motion.quintic(3.82368727, 1.0), 0.0, 0.0,
		Motion.compact_pulse(deg_to_rad(-50.80747228)), "cutback", 0, 2.0, "cutback")

	_add(spans, metadata, propulsion, "act-one/loop-entry", 0.3, "moving",
		Motion.quintic(1.0, 4.40341684728708), Motion.compact_pulse(0.9), 0.0, 0.0,
		"giant-inversion", 0, 2.0, "loop")
	_add(spans, metadata, propulsion, "act-one/loop-lower-hold", 0.25, "moving",
		4.40341684728708, Motion.compact_pulse(0.9), 0.0, 0.0,
		"giant-inversion", 0, 2.0, "loop")
	_add(spans, metadata, propulsion, "act-one/loop-rise", 2.4780474553844765, "moving",
		Motion.quintic(4.40341684728708, 5.2), Motion.compact_pulse(0.9), 0.0, 0.0,
		"giant-inversion", 0, 2.0, "loop")
	_add(spans, metadata, propulsion, "act-one/loop-fall", 2.4780474553844765, "moving",
		Motion.quintic(5.2, 4.40341684728708), Motion.compact_pulse(-0.9), 0.0, 0.0,
		"giant-inversion", 0, 2.0, "loop")
	_add(spans, metadata, propulsion, "act-one/loop-upper-hold", 0.25, "moving",
		4.40341684728708, Motion.compact_pulse(-0.9), 0.0,
		Motion.compact_pulse(deg_to_rad(-84.344531055)), "giant-inversion", 0, 2.0, "loop")
	_add(spans, metadata, propulsion, "act-one/loop-release", 0.3, "moving",
		Motion.quintic(4.40341684728708, 1.0), Motion.compact_pulse(-0.9), 0.0,
		Motion.compact_pulse(deg_to_rad(-84.344531055)), "giant-inversion", 0, 2.0, "loop")

	_add(spans, metadata, propulsion, "act-one/airtime-pull-up", 0.48089366108653, "moving",
		Motion.quintic(1.0, 5.19999979865927), 0.0, 0.0, 0.0,
		"airtime-hills", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "act-one/airtime-unload", 0.48089366108653, "moving",
		Motion.quintic(5.19999979865927, -0.45), 0.0, 0.0, 0.0,
		"airtime-hills", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "act-one/airtime-crest", 2.40, "moving",
		-0.45, 0.0, 0.0, 0.0, "airtime-hills", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "act-one/airtime-fall", 0.52, "moving",
		Motion.quintic(-0.45, 5.199946698098), 0.0, 0.0, 0.0,
		"airtime-hills", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "act-one/airtime-release", 0.52, "moving",
		Motion.quintic(5.199946698098, 1.0), 0.0, 0.0, 0.0,
		"airtime-hills", 0, 2.0, "hill")

	_add(spans, metadata, propulsion, "act-one/wave-rise", 0.500000000067, "moving",
		Motion.quintic(1.0, 4.42), Motion.compact_pulse(0.50), 0.0,
		Motion.compact_pulse(deg_to_rad(120.0)), "wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-unload", 0.500000000067, "moving",
		Motion.quintic(4.42, -0.599999972), Motion.compact_pulse(0.50), 0.0,
		Motion.compact_pulse(deg_to_rad(120.0)), "wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-crest", 2.52, "moving",
		-0.599999972, Motion.compact_pulse(0.50), 0.0, 0.0,
		"wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-fall", 1.14, "moving",
		Motion.quintic(-0.599999972, 5.2), Motion.compact_pulse(0.50), 0.0,
		Motion.compact_pulse(deg_to_rad(-44.56)), "wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-release", 1.14, "moving",
		Motion.quintic(5.2, 1.0), Motion.compact_pulse(0.50), 0.0,
		Motion.compact_pulse(deg_to_rad(-44.56)), "wave-turn", 0, 2.0, "wave_turn")


static func _add_raceway(
	s: Array, m: Array, p: PackedInt32Array, parameters: Array = []
) -> void:
	var authored := _return_spans(RETURN_SEED if parameters.is_empty() else parameters)
	var role_ids := ["turn-a", "height-airtime-a", "turn-b", "height-airtime-b"]
	var role_ends := [3, 7, 10, 15]
	var first := 0
	for role_index in 4:
		for i in range(first, role_ends[role_index]):
			_add_record(s, m, p, authored[i], role_ids[role_index], 0, 45.0,
				"overbank" if role_index % 2 == 0 else "hill")
		first = role_ends[role_index]


static func _return_spans(v: Array) -> Array:
	var normal_a := 1.0 / cos(float(v[0]))
	var normal_b := 1.0 / cos(float(v[3]))
	var low_a := 0.5 - 0.25 / float(v[2])
	var roll_a := float(v[0]) / (1.5 * COMPACT_PULSE_AREA)
	var roll_b := float(v[3]) / (1.5 * COMPACT_PULSE_AREA)
	return [
		_return_span("raceway/turn-a/entry", 1.5, 1.0, normal_a, roll_a),
		_return_span("raceway/turn-a/core", v[1], normal_a, normal_a),
		_return_span("raceway/turn-a/exit", 1.5, normal_a, 1.0, -roll_a),
		_return_span("raceway/height-a/pullup", 0.5, 1.0, 1.5),
		_return_span("raceway/height-a/unload", v[2], 1.5, low_a),
		_return_span("raceway/height-a/recovery", v[2], low_a, 1.5),
		_return_span("raceway/height-a/release", 0.5, 1.5, 1.0),
		_return_span("raceway/turn-b/entry", 1.5, 1.0, normal_b, roll_b),
		_return_span("raceway/turn-b/core", v[4], normal_b, normal_b),
		_return_span("raceway/turn-b/exit", 1.5, normal_b, 1.0, -roll_b),
		_return_span("raceway/height-b/pullup", 0.4, 1.0, 2.5),
		_return_span("raceway/height-b/unload", 1.4, 2.5, -0.6),
		_return_span("raceway/height-b/crest", 0.4, -0.6, -0.6),
		_return_span("raceway/height-b/recovery", v[5], -0.6, 2.5),
		_return_span("raceway/height-b/release", 0.4, 2.5, 1.0),
	]


static func _return_span(id: String, duration_s: float, from_g: float, to_g: float,
	roll_peak_rad_s: float = 0.0) -> Dictionary:
	var normal := Motion.constant(from_g) if is_equal_approx(from_g, to_g) \
		else Motion.quintic(from_g, to_g)
	var roll := Motion.constant(0.0) if absf(roll_peak_rad_s) < 0.000001 else Motion.compact_pulse(roll_peak_rad_s)
	return Motion.span(id, duration_s, "moving", normal, Motion.constant(0.0),
		Motion.constant(0.0), roll)


static func _solve_return(start: Dictionary, layout: Dictionary) -> Dictionary:
	var parameters := RETURN_SEED.duplicate()
	var cache := {}
	var deltas := []
	for index in 6:
		deltas.append(maxf(0.00001, 0.001 * (
			RETURN_PARAMETER_BOUNDS[index][1] - RETURN_PARAMETER_BOUNDS[index][0])))
	var evaluate := func(candidate: Array) -> Dictionary:
		return _return_evaluation(
			start, layout, candidate, _settings(COARSE_STEP_S), cache)
	for _update in 2:
		var base: Dictionary = evaluate.call(parameters)
		if not base.ok:
			return base
		var finite_difference := _finite_difference_jacobian(
			parameters, base.scaled, RETURN_PARAMETER_BOUNDS, deltas, evaluate)
		if not finite_difference.ok:
			return finite_difference
		_normalize_return_jacobian(finite_difference.jacobian)
		var step := _linear_solve(finite_difference.jacobian, base.scaled)
		if step.is_empty():
			return _failure("return Jacobian is singular", "return",
				{"evaluation_count": cache.size()})
		var normalized_size := 0.0
		for value in step:
			normalized_size = maxf(normalized_size, absf(float(value)))
		var step_scale := minf(1.0, 0.5 / normalized_size) if normalized_size > 0.0 else 1.0
		for index in 6:
			var half_range: float = 0.5 * (
				RETURN_PARAMETER_BOUNDS[index][1] - RETURN_PARAMETER_BOUNDS[index][0])
			parameters[index] = clampf(parameters[index] - step_scale * step[index] * half_range,
				RETURN_PARAMETER_BOUNDS[index][0], RETURN_PARAMETER_BOUNDS[index][1])
	var coarse: Dictionary = evaluate.call(parameters)
	if not coarse.ok:
		return coarse
	var accepted_difference := _finite_difference_jacobian(
		parameters, coarse.scaled, RETURN_PARAMETER_BOUNDS, deltas, evaluate)
	if not accepted_difference.ok:
		return accepted_difference
	_normalize_return_jacobian(accepted_difference.jacobian)
	var conditioning := _matrix_conditioning(accepted_difference.jacobian)
	conditioning["evaluated_vector"] = parameters.duplicate()
	if not conditioning.ok:
		return _failure("return Jacobian is ill-conditioned", "return",
			{"evaluation_count": cache.size(), "conditioning": conditioning})
	var fine := _return_evaluation(
		start, layout, parameters, _settings(FINE_STEP_S), cache)
	if not fine.ok:
		return fine
	if not _margins_are_valid(coarse.margins) or not _margins_are_valid(fine.margins):
		return _failure("solved return misses the capture-entry basin", "return",
			{"evaluation_count": cache.size(), "margins": fine.margins})
	if _maximum_absolute(coarse.scaled) > RETURN_TARGET_TOLERANCE:
		return _failure("return did not reach its fixed station-local target", "return",
			{"evaluation_count": cache.size(), "target_error": coarse.scaled})
	for index in 6:
		if absf(fine.residuals[index] - coarse.residuals[index]) \
				> RETURN_FINE_TOLERANCES[index]:
			return _failure("return coarse/fine observations disagree", "return",
				{"evaluation_count": cache.size(), "coarse": coarse.residuals,
				"fine": fine.residuals})
	var margins: Dictionary = fine.margins.duplicate(true)
	for index in 6:
		margins["parameter_%s" % RETURN_PARAMETER_IDS[index]] = minf(
			parameters[index] - RETURN_PARAMETER_BOUNDS[index][0],
			RETURN_PARAMETER_BOUNDS[index][1] - parameters[index])
	return {"ok": true, "parameters": parameters, "report": {
		"parameter_ids": RETURN_PARAMETER_IDS,
		"parameter_bounds": RETURN_PARAMETER_BOUNDS, "accepted_values": parameters,
		"residual_ids": RETURN_OUTPUT_IDS, "residual_bounds": RETURN_OUTPUT_BOUNDS,
		"coarse_fine_tolerances": RETURN_FINE_TOLERANCES,
		"unique_evaluations": cache.size(), "max_unique_evaluations": MAX_RETURN_EVALUATIONS,
		"coarse_observation": coarse.residuals, "fine_observation": fine.residuals,
		"conditioning": conditioning, "margins": margins,
		"positive_drive_allowed": false}}


static func _return_target_error(observation: Array) -> Array:
	var result := []
	for index in 6:
		var difference: float = observation[index] - RETURN_TARGET[index]
		if index >= 3:
			difference = wrapf(difference, -PI, PI)
		result.append(difference / RETURN_OUTPUT_SCALES[index])
	return result


static func _normalize_return_jacobian(jacobian: Array) -> void:
	for column in 6:
		var half_range: float = 0.5 * (
			RETURN_PARAMETER_BOUNDS[column][1] - RETURN_PARAMETER_BOUNDS[column][0])
		for row in 6:
			jacobian[row][column] *= half_range


static func _maximum_absolute(values: Array) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, absf(float(value)))
	return result


static func _return_evaluation(start: Dictionary, layout: Dictionary, parameters: Array,
	settings: Dictionary, cache: Dictionary) -> Dictionary:
	var key := "%.6f:" % float(settings.step_s)
	for parameter in parameters:
		key += "%.12f," % float(parameter)
	if cache.has(key):
		return cache[key]
	if cache.size() >= MAX_RETURN_EVALUATIONS:
		return _failure("return exceeded its evaluation cap", "return",
			{"evaluation_count": cache.size()})
	var route := Motion.integrate(start, _return_spans(parameters), settings)
	if not route.get("ok", false):
		var failed := _failure("return candidate failed integration", "return",
			{"evaluation_count": cache.size() + 1})
		cache[key] = failed
		return failed
	var result := _return_observation(route, layout)
	result["scaled"] = _return_target_error(result.residuals)
	cache[key] = result
	return result


static func _return_observation(route: Dictionary, layout: Dictionary) -> Dictionary:
	var state := _last_state(route)
	var capture := _capture_residuals(state, layout)
	var residuals := [(state.position_m - layout.station_position_m).dot(
		layout.station_tangent.normalized()), capture[1], capture[0], capture[2], capture[3], capture[4]]
	var margins := {}
	for index in 6:
		margins["basin_%s" % RETURN_OUTPUT_IDS[index]] = minf(
			residuals[index] - RETURN_OUTPUT_BOUNDS[index][0],
			RETURN_OUTPUT_BOUNDS[index][1] - residuals[index])
	return {"ok": true, "residuals": residuals, "margins": margins}


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


static func station_approach_envelope() -> Dictionary:
	return {
		"minimum_length_m": STATION_APPROACH_LENGTH_M,
		"half_width_m": CAPTURE_HALF_WIDTH_M,
		"half_height_m": CAPTURE_HALF_HEIGHT_M,
	}


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
	for index in 5:
		coefficients[index] = clampf(float(coefficients[index]),
			CAPTURE_COEFFICIENT_BOUNDS[index][0], CAPTURE_COEFFICIENT_BOUNDS[index][1])
	var cache := {}
	var residuals: Array = []
	var conditioning := {}
	var evaluate := func(candidate: Array) -> Dictionary:
		return _capture_evaluation(start, layout, candidate, settings, cache)
	for _iteration in 6:
		var base := _capture_evaluation(start, layout, coefficients, settings, cache)
		if not base.ok:
			return base
		residuals = base.residuals
		var finite_difference := _finite_difference_jacobian(coefficients, base.scaled,
			CAPTURE_COEFFICIENT_BOUNDS, [0.02, 0.02, 0.02, 0.02, 0.04], evaluate)
		if not finite_difference.ok:
			return finite_difference
		conditioning = _matrix_conditioning(finite_difference.jacobian)
		conditioning["evaluated_vector"] = coefficients.duplicate()
		if not conditioning.ok:
			return _capture_failure("capture Jacobian is ill-conditioned", cache.size(),
				base.residuals, base.margins, {"conditioning": conditioning})
		if _capture_converged(residuals):
			break
		var step := _linear_solve(finite_difference.jacobian, base.scaled)
		if step.is_empty():
			return _capture_failure("capture Jacobian is singular", cache.size(),
				base.residuals, base.margins)
		for index in 5:
			coefficients[index] = clampf(coefficients[index] - step[index],
				CAPTURE_COEFFICIENT_BOUNDS[index][0], CAPTURE_COEFFICIENT_BOUNDS[index][1])
	var coarse := _capture_evaluation(start, layout, coefficients, settings, cache)
	if not coarse.ok:
		return coarse
	if not _capture_converged(coarse.residuals):
		return _capture_failure("capture did not converge: %s" % str(coarse.residuals),
			cache.size(), coarse.residuals, coarse.margins)
	var fine_settings := settings.duplicate()
	fine_settings.step_s = FINE_STEP_S
	var fine := _capture_evaluation(start, layout, coefficients, fine_settings, cache)
	if not fine.ok:
		return fine
	if cache.size() > MAX_CAPTURE_EVALUATIONS:
		return _capture_failure("capture exceeded %d unique evaluations" %
			MAX_CAPTURE_EVALUATIONS, cache.size(), fine.residuals, fine.margins)
	if not _capture_converged(fine.residuals) or _maximum_residual_delta(
		coarse.residuals, fine.residuals) > 0.02:
		return _capture_failure("capture coarse/fine residuals disagree", cache.size(),
			fine.residuals, fine.margins, {"coarse_residuals": coarse.residuals.duplicate()})
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
	return absf(residuals[0]) <= 0.05 and absf(residuals[1]) <= 0.05 \
		and absf(residuals[2]) <= 0.00001 and absf(residuals[3]) <= 0.00001 \
		and absf(residuals[4]) <= 0.00001


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
	result.merge({
		"coefficient_margin": coefficient_margin,
		"speed_floor_margin_mps": end.speed_mps - 2.0,
		"remaining_along_track_m": (layout.station_position_m - end.position_m).dot(
			layout.station_tangent.normalized()),
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
		var delta := absf(float(deltas[column]))
		if base_vector[column] + delta > bounds[column][1]:
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
	var station_duration := _coast_time(2.0, 1.0)
	var station_distance := _coast_distance(2.0, 1.0)
	if absf(start.tangent.normalized().dot(layout.station_tangent.normalized()) - 1.0) > 0.00001 \
			or start.rider_up.normalized().distance_to(layout.station_up.normalized()) > 0.00001:
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
		0.98 * (float(start.speed_mps) - 2.0 - resistance_loss) / (
			Motion.G0 * (active_estimate - BRAKE_SHOULDER_DURATION_S))]
	for index in 2:
		if not is_finite(parameters[index]) \
				or parameters[index] <= BRAKE_PARAMETER_BOUNDS[index][0] \
				or parameters[index] >= BRAKE_PARAMETER_BOUNDS[index][1]:
			return _failure("brake initial estimate is outside its parameter bounds", "brake")
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
			BRAKE_PARAMETER_BOUNDS, [0.01, 0.005], evaluate)
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


static func _peak_analytic_normal_onset(spans: Array, first: int, last: int) -> float:
	var peak := 0.0
	for index in range(first, last + 1):
		var span: Dictionary = spans[index]
		peak = maxf(peak, Motion.profile_peak_abs_derivative(span.normal_g) / span.duration_s)
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
