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
const MAX_RETURN_EVALUATIONS := 42
const RETURN_BANK_TRANSITION_S := 1.25
const RETURN_SETTLE_S := 1.0
const RETURN_HILL_NORMAL_G := 3.0
const RETURN_HILL_AIR_G := -1.0
const BRAKE_ENVELOPE_MARGIN_M := 50.0
const RETURN_RESIDUAL_TOLERANCES := [2.0, 2.0, 1.0, 0.01, 0.01]
const CAPTURE_RESIDUAL_TOLERANCES := [0.05, 0.05, 0.00001, 0.00001, 0.00001]
const RETURN_VARIABLE_BOUNDS := [
	[-0.75, 0.75], [2.0, 14.0], [2.0, 5.0], [-0.75, 0.75], [2.0, 14.0],
]
const CAPTURE_COEFFICIENT_BOUNDS := [
	[-0.55, 0.55], [-0.55, 0.55], [-0.45, 0.45], [-0.45, 0.45], [-1.2, 1.2],
]


static func compile(
	seed: int, config: Dictionary, terrain: Dictionary, layout: Dictionary,
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
	_add(spans, metadata, propulsion, "climb/ballistic", 3.289977, "moving",
		0.0, 0.0, 0.0, 0.0, "unpowered-climb")
	_add(spans, metadata, propulsion, "climb/level", 0.307367, "moving",
		Motion.quintic(0.0, 1.0), 0.0, 0.0, 0.0, "unpowered-climb")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "clifftop-suspense", spans.size())
	_add(spans, metadata, propulsion, "rim/slow-crest", 2.90, "moving",
		1.0, 0.0, 0.0, 0.0, "slow-crest")
	_add(spans, metadata, propulsion, "rim/outward-bank", 1.40, "moving",
		Motion.quintic(1.0, 1.493674785), Motion.compact_pulse(0.05), 0.0,
		Motion.compact_pulse(deg_to_rad(84.15)), "outward-rim")
	_add(spans, metadata, propulsion, "rim/outward-arc", 1.0, "moving",
		1.493674785, 0.0, 0.0, 0.0, "outward-rim")
	_add(spans, metadata, propulsion, "rim/outward-release", 1.40, "moving",
		Motion.quintic(1.493674785, 1.0), Motion.compact_pulse(-0.05), 0.0,
		Motion.compact_pulse(deg_to_rad(-84.15)), "outward-rim")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "cliff-dive", spans.size(), "dive")
	_add(spans, metadata, propulsion, "dive/commit", 1.068877, "moving",
		Motion.quintic(1.0, -1.3), 0.0, 0.0, 0.0, "commit")
	_add(spans, metadata, propulsion, "dive/vertical-entry", 0.679547, "moving",
		Motion.quintic(-1.3, 0.0), 0.0, 0.0, 0.0, "vertical-entry")
	_add(spans, metadata, propulsion, "dive/core", 2.027297, "moving",
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

	var settings := _settings(COARSE_STEP_S)
	var upstream := Motion.integrate(initial_state, spans, settings)
	if not upstream.get("ok", false):
		return _failure("upstream integration failed: %s" % ", ".join(
			upstream.get("errors", [])), "prefix")
	var return_plan := _solve_return(_last_state(upstream), layout, settings)
	if not return_plan.get("ok", false):
		return return_plan
	_begin_gesture(gestures, "raceway-return", spans.size())
	_add_raceway(spans, metadata, propulsion, return_plan.variables)
	_end_gesture(gestures, metadata, spans.size() - 1)

	var prefix := Motion.integrate(initial_state, spans, settings)
	if not prefix.get("ok", false):
		return _failure("prefix integration failed: %s" % ", ".join(
			prefix.get("errors", [])), "prefix")
	var landmark_report := _landmark_report(prefix, gestures, metadata,
		initial_state.position_m)
	var landmark_errors := _validate_landmark_report(landmark_report)
	if not landmark_errors.is_empty():
		return _failure("upstream landmark solve missed its physical envelope: %s" \
			% str(landmark_errors), "landmarks",
			{"landmark_report": landmark_report, "misses": landmark_errors})
	var capture_start := _last_state(prefix)
	var capture := _solve_capture(capture_start, layout, settings)
	if not capture.ok:
		capture["landmark_report"] = landmark_report
		return capture
	var capture_spans: Array = _capture_spans(capture.coefficients)
	var capture_route := Motion.integrate(capture_start, capture_spans, settings)
	if not capture_route.get("ok", false):
		var capture_failure := _capture_failure("accepted capture did not reintegrate",
			capture.unique_evaluations, capture.residuals, capture.margins)
		capture_failure["landmark_report"] = landmark_report
		return capture_failure
	var brake := _solve_brakes(_last_state(capture_route), layout, settings)
	if not brake.ok:
		brake["landmark_report"] = landmark_report
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
		"terrain": terrain,
		"layout": layout,
		"spans": spans,
		"span_metadata": metadata,
		"gesture_spans": gestures,
		"propulsion_by_span": propulsion,
		"minimum_speed_by_span": minimum_speeds,
		"tunnel_span_ranges": tunnels,
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
			"margins": capture.margins,
			"conditioning": capture.conditioning,
			"positive_drive_allowed": false,
		},
		"return_plan": return_plan.plan,
		"brake_plan": brake.report,
		"landmark_report": landmark_report,
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
	_add(spans, metadata, propulsion, "act-one/airtime-crest", 1.7936931571445, "moving",
		-0.45, 0.0, 0.0, 0.0, "airtime-hills", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "act-one/airtime-fall", 0.579759539647, "moving",
		Motion.quintic(-0.45, 5.199946698098), 0.0, 0.0, 0.0,
		"airtime-hills", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "act-one/airtime-release", 0.579759539647, "moving",
		Motion.quintic(5.199946698098, 1.0), 0.0, 0.0, 0.0,
		"airtime-hills", 0, 2.0, "hill")

	_add(spans, metadata, propulsion, "act-one/wave-rise", 0.500000000067, "moving",
		Motion.quintic(1.0, 2.000380212), Motion.compact_pulse(1.083606852), 0.0,
		Motion.compact_pulse(deg_to_rad(120.0)), "wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-unload", 0.500000000067, "moving",
		Motion.quintic(2.000380212, -0.599999972), Motion.compact_pulse(1.083606852), 0.0,
		Motion.compact_pulse(deg_to_rad(120.0)), "wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-crest", 2.199999528604, "moving",
		-0.599999972, Motion.compact_pulse(1.083606852), 0.0, 0.0,
		"wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-fall", 1.299999999316, "moving",
		Motion.quintic(-0.599999972, 5.2), Motion.compact_pulse(1.083606852), 0.0,
		Motion.compact_pulse(deg_to_rad(-33.272585436)), "wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-release", 1.299999999316, "moving",
		Motion.quintic(5.2, 1.0), Motion.compact_pulse(1.083606852), 0.0,
		Motion.compact_pulse(deg_to_rad(-33.272585436)), "wave-turn", 0, 2.0, "wave_turn")


static func _add_raceway(s: Array, m: Array, p: PackedInt32Array, v: Array) -> void:
	var roles := ["arc-a", "arc-a", "arc-a", "hill-a", "hill-a", "arc-b", "arc-b",
		"arc-b", "hill-b", "hill-b", "exit"]
	var kinds := ["overbank", "overbank", "overbank", "hill", "hill", "turn", "turn",
		"turn", "hill", "hill", ""]
	var authored := _return_spans(v)
	for i in 11:
		_add_record(s, m, p, authored[i], roles[i], 0, 2.0, kinds[i])


static func _return_spans(v: Array) -> Array:
	var a := 1.0 / cos(float(v[0])); var b := 1.0 / cos(float(v[3])); var h := float(v[2])
	var air_a := RETURN_HILL_AIR_G - 0.5 * RETURN_BANK_TRANSITION_S * (
		a + 2.0 * RETURN_HILL_NORMAL_G + b - 4.0) / h
	var air_b := RETURN_HILL_AIR_G - (0.5 * RETURN_BANK_TRANSITION_S * (
		b + RETURN_HILL_NORMAL_G - 2.0) + 0.5 * RETURN_SETTLE_S * (
		RETURN_HILL_NORMAL_G - 1.0)) / h
	return [
		_return_span("raceway/bank-in-a", RETURN_BANK_TRANSITION_S, 1.0, a, v[0]),
		_return_span("raceway/arc-a", v[1], a, a),
		_return_span("raceway/bank-out-a", RETURN_BANK_TRANSITION_S, a,
			RETURN_HILL_NORMAL_G, -float(v[0])),
		_return_span("raceway/hill-a-rise", h, RETURN_HILL_NORMAL_G, air_a),
		_return_span("raceway/hill-a-release", h, air_a, RETURN_HILL_NORMAL_G),
		_return_span("raceway/bank-in-b", RETURN_BANK_TRANSITION_S,
			RETURN_HILL_NORMAL_G, b, v[3]), _return_span("raceway/arc-b", v[4], b, b),
		_return_span("raceway/bank-out-b", RETURN_BANK_TRANSITION_S, b,
			RETURN_HILL_NORMAL_G, -float(v[3])),
		_return_span("raceway/hill-b-rise", h, RETURN_HILL_NORMAL_G, air_b),
		_return_span("raceway/hill-b-release", h, air_b, RETURN_HILL_NORMAL_G),
		_return_span("raceway/roll-settle", RETURN_SETTLE_S, RETURN_HILL_NORMAL_G, 1.0)]


static func _return_span(id: String, t: float, a: float, b: float, area: float = 0.0) -> Dictionary:
	var roll := Motion.constant(0.0) if absf(area) < 0.000001 else Motion.compact_pulse(
		area / (t * COMPACT_PULSE_AREA))
	return Motion.span(id, t, "moving", Motion.quintic(a, b), Motion.constant(0.0),
		Motion.constant(0.0), roll)


static func _solve_return(start: Dictionary, layout: Dictionary, settings: Dictionary) -> Dictionary:
	var v := _return_seed(start, layout); var cache := {}; var conditioning := {}
	for iteration in 6:
		var base := _return_evaluation(start, layout, v, settings, cache)
		if not base.ok:
			return base
		var jacobian := [[0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0],
			[0.0, 0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 0.0, 0.0],
			[0.0, 0.0, 0.0, 0.0, 0.0]]
		for column in 5:
			var probe := v.duplicate(); var delta: float = [0.02, 0.2, 0.1, 0.02, 0.2][column]
			if probe[column] + delta > RETURN_VARIABLE_BOUNDS[column][1]:
				delta = -delta
			probe[column] += delta
			var evaluated := _return_evaluation(start, layout, probe, settings, cache)
			if not evaluated.ok:
				return evaluated
			for row in 5:
				jacobian[row][column] = (evaluated.scaled[row] - base.scaled[row]) / delta
		conditioning = _matrix_conditioning(jacobian)
		conditioning["evaluated_vector"] = v.duplicate()
		if not conditioning.ok:
			return _return_failure("return Jacobian is ill-conditioned", cache, conditioning)
		if _residuals_within(base.residuals, RETURN_RESIDUAL_TOLERANCES):
			break
		if iteration == 5:
			break
		var step := _linear_solve(jacobian, base.scaled)
		if step.is_empty():
			return _return_failure("return Jacobian is singular", cache, conditioning)
		for i in 5:
			v[i] = clampf(v[i] - 0.7 * step[i], RETURN_VARIABLE_BOUNDS[i][0],
				RETURN_VARIABLE_BOUNDS[i][1])
	var coarse := _return_evaluation(start, layout, v, settings, cache)
	var fine_settings := settings.duplicate(); fine_settings.step_s = FINE_STEP_S
	var fine := _return_evaluation(start, layout, v, fine_settings, cache)
	if not coarse.ok:
		return coarse
	if not fine.ok:
		return fine
	if not _residuals_within(coarse.residuals, RETURN_RESIDUAL_TOLERANCES) \
			or not _residuals_within(fine.residuals, RETURN_RESIDUAL_TOLERANCES) \
			or _maximum_normalized_delta(coarse.residuals, fine.residuals,
				RETURN_RESIDUAL_TOLERANCES) > 0.02:
		return _return_failure("return solve missed its coarse/fine contract", cache,
			conditioning, fine.residuals)
	for margin in fine.margins.values():
		if not is_finite(float(margin)) or float(margin) < 0.0:
			return _return_failure("return solve violates an inequality", cache, conditioning,
				fine.residuals, fine.margins)
	return {"ok": true, "variables": v, "plan": {"status": "solved", "variables": v,
		"variable_bounds": RETURN_VARIABLE_BOUNDS, "residual_ids": ["along_track_m",
			"cross_track_m", "height_m", "yaw_rad", "roll_rad"],
		"residual_tolerances": RETURN_RESIDUAL_TOLERANCES, "residuals": coarse.residuals,
		"fine_residuals": fine.residuals, "margins": fine.margins,
		"conditioning": conditioning, "unique_evaluations": cache.size(),
		"max_unique_evaluations": MAX_RETURN_EVALUATIONS, "positive_drive_allowed": false}}


static func _return_failure(message: String, cache: Dictionary, conditioning: Dictionary = {},
	residuals: Array = [], margins: Dictionary = {}) -> Dictionary:
	return _failure(message, "return", {"evaluation_count": cache.size(),
		"conditioning": conditioning, "residuals": residuals, "margins": margins})


static func _return_seed(start: Dictionary, layout: Dictionary) -> Array:
	var up: Vector3 = layout.station_up.normalized(); var forward: Vector3 = layout.station_tangent.normalized()
	var target: Vector3 = layout.station_position_m - forward * _approach_length(layout)
	var desired: Vector3 = target - start.position_m; desired -= up * desired.dot(up)
	desired = forward if desired.length_squared() < 0.000001 else desired.normalized()
	var heading: Vector3 = start.tangent - up * start.tangent.dot(up); heading = heading.normalized()
	var bank := deg_to_rad(32.0); var a := atan2(heading.cross(desired).dot(up), heading.dot(desired))
	var b := atan2(desired.cross(forward).dot(up), desired.dot(forward))
	var rate := Motion.G0 * tan(bank) / maxf(start.speed_mps, 45.0)
	var ta := clampf(absf(a) / rate, 2.0, 14.0); var tb := clampf(absf(b) / rate, 2.0, 14.0)
	var hill := clampf(0.25 * (start.position_m.distance_to(target) / maxf(start.speed_mps, 45.0)
		- 3.0 * RETURN_BANK_TRANSITION_S - RETURN_SETTLE_S - ta - tb), 2.0, 5.0)
	return [-signf(a) * bank if absf(a) > 0.01 else bank, ta, hill,
		-signf(b) * bank if absf(b) > 0.01 else -bank, tb]


static func _return_evaluation(start: Dictionary, layout: Dictionary, v: Array,
	settings: Dictionary, cache: Dictionary) -> Dictionary:
	var key := "%.6f:%s" % [float(settings.step_s), str(v)]
	if cache.has(key):
		return cache[key]
	if cache.size() >= MAX_RETURN_EVALUATIONS:
		return _return_failure("return exceeded its evaluation budget", cache)
	var route := Motion.integrate(start, _return_spans(v), settings)
	if not route.get("ok", false):
		cache[key] = {}
		var rejected := _return_failure("return candidate failed", cache)
		cache[key] = rejected
		return rejected
	var end := _last_state(route); var forward: Vector3 = layout.station_tangent.normalized()
	var up: Vector3 = layout.station_up.normalized(); var right := forward.cross(up).normalized()
	var delta: Vector3 = end.position_m - (layout.station_position_m - forward * _approach_length(layout))
	var reference_up: Vector3 = (up - end.tangent * up.dot(end.tangent)).normalized()
	var actual_up: Vector3 = (end.rider_up - end.tangent * end.rider_up.dot(end.tangent)).normalized()
	var r := [delta.dot(forward), delta.dot(right), delta.dot(up),
		atan2(end.tangent.dot(right), end.tangent.dot(forward)),
		atan2(end.tangent.dot(reference_up.cross(actual_up)), reference_up.dot(actual_up))]
	var result := {"ok": true, "residuals": r, "scaled": [r[0] / 500.0, r[1] / 500.0,
		r[2] / 100.0, r[3] / 0.5, r[4] / 0.5], "margins": _return_margins(route, v, layout)}
	cache[key] = result; return result


static func _return_margins(route: Dictionary, v: Array, layout: Dictionary) -> Dictionary:
	var bound := INF; var min_speed := INF; var min_normal := INF; var max_normal := 0.0
	var max_roll := 0.0
	var first_energy := 0.0; var previous_energy := 0.0; var energy_step := INF
	for i in v.size():
		bound = minf(bound, minf(v[i] - RETURN_VARIABLE_BOUNDS[i][0],
			RETURN_VARIABLE_BOUNDS[i][1] - v[i]))
	for i in route.position_m.size():
		var energy: float = 0.5 * route.speed_mps[i] ** 2 + Motion.G0 * (
			route.position_m[i] - layout.station_position_m).dot(layout.station_up)
		if i == 0:
			first_energy = energy
		else:
			energy_step = minf(energy_step, previous_energy - energy)
		previous_energy = energy; min_speed = minf(min_speed, route.speed_mps[i])
		min_normal = minf(min_normal, route.normal_g[i])
		max_normal = maxf(max_normal, absf(route.normal_g[i])); max_roll = maxf(max_roll,
			absf(route.roll_rate_rad_s[i]))
	var pitch := asin(clampf(route.tangent[-1].dot(layout.station_up.normalized()), -1.0, 1.0))
	return {"variable_bounds": bound, "material_bank_rad": minf(absf(v[0]), absf(v[3]))
		- deg_to_rad(15.0), "speed_floor_mps": min_speed - 45.0,
		"material_arc_s": minf(v[1], v[4]) - 2.0, "airtime_normal_g": 0.25 - min_normal,
		"exit_speed_low_mps": route.speed_mps[-1] - 48.0,
		"exit_speed_high_mps": 82.0 - route.speed_mps[-1], "capture_pitch_rad": 0.15 - absf(pitch),
		"normal_force_g": 4.5 - max_normal, "roll_rate_rad_s": deg_to_rad(120.0) - max_roll,
		"monotone_energy_j_per_kg": energy_step + 0.001,
		"total_energy_loss_j_per_kg": first_energy - previous_energy - 100.0}


static func _approach_length(layout: Dictionary) -> float:
	var corridor: Variant = layout.get("reserved_corridor")
	if corridor is Dictionary:
		return float(corridor.get("minimum_length_m", 0.0))
	return 8.0 * 92.0 + (92.0 ** 2 - 2.0 ** 2) / (
		2.0 * Motion.G0 * 1.2 * COMPACT_PULSE_AREA) + _coast_distance(2.0, 1.0) + 100.0


static func _add_capture_and_brakes(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, coefficients: Array,
	brake: Dictionary
) -> void:
	for capture_span: Dictionary in _capture_spans(coefficients):
		_add_record(spans, metadata, propulsion, capture_span, "capture", 0, 2.0)
	if brake.coast_duration_s > 0.000001:
		_add(spans, metadata, propulsion, "brakes/coast", brake.coast_duration_s, "moving",
			brake.support_normal_g, brake.support_lateral_g, 0.0, 0.0, "brakes")
	_add(spans, metadata, propulsion, "brakes/moving", brake.brake_duration_s, "moving",
		brake.support_normal_g, brake.support_lateral_g,
		Motion.compact_pulse(brake.brake_peak_g), 0.0, "brakes")
	_add(spans, metadata, propulsion, "station/creep", brake.station_duration_s, "station",
		brake.support_normal_g, brake.support_lateral_g, 0.0, 0.0, "station", 0, 0.0)


static func _capture_spans(coefficients: Array) -> Array:
	var roll_peak: float = coefficients[4] / (7.0 * COMPACT_PULSE_AREA)
	return [
		Motion.span("capture/early", 3.5, "moving",
			Motion.quintic(1.0, 1.0 + coefficients[2]), Motion.compact_pulse(coefficients[0]),
			Motion.constant(0.0), Motion.compact_pulse(roll_peak)),
		Motion.span("capture/late", 3.5, "moving",
			Motion.quintic(1.0 + coefficients[2], 1.0 + coefficients[3]),
			Motion.compact_pulse(coefficients[1]), Motion.constant(0.0),
			Motion.compact_pulse(roll_peak)),
		Motion.span("capture/terminal-shoulder", 1.0, "moving",
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
	for iteration in 6:
		var base := _capture_evaluation(start, layout, coefficients, settings, cache)
		if not base.ok:
			return base
		residuals = base.residuals
		var jacobian: Array = []
		for row in 5:
			jacobian.append([0.0, 0.0, 0.0, 0.0, 0.0])
		for column in 5:
			var probe := coefficients.duplicate()
			var delta := 0.02 if column < 4 else 0.04
			if probe[column] + delta > CAPTURE_COEFFICIENT_BOUNDS[column][1]:
				delta = -delta
			probe[column] += delta
			var evaluated := _capture_evaluation(start, layout, probe, settings, cache)
			if not evaluated.ok:
				return evaluated
			for row in 5:
				jacobian[row][column] = (evaluated.scaled[row] - base.scaled[row]) / delta
		conditioning = _matrix_conditioning(jacobian)
		conditioning["evaluated_vector"] = coefficients.duplicate()
		if not conditioning.ok:
			return _capture_failure("capture Jacobian is ill-conditioned", cache.size(),
				base.residuals, base.margins, {"conditioning": conditioning})
		if _capture_converged(residuals):
			break
		if iteration == 5:
			break
		var step := _linear_solve(jacobian, base.scaled)
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
	var half_width: float = layout.get("capture_half_width_m", 150.0)
	var half_height: float = layout.get("capture_half_height_m", 75.0)
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


static func _residuals_within(residuals: Array, tolerances: Array) -> bool:
	for index in residuals.size():
		if not is_finite(float(residuals[index])) \
				or absf(float(residuals[index])) > float(tolerances[index]):
			return false
	return residuals.size() == tolerances.size()


static func _maximum_normalized_delta(a: Array, b: Array, scales: Array) -> float:
	var result := 0.0
	for index in a.size():
		result = maxf(result, absf(float(a[index]) - float(b[index])) / float(scales[index]))
	return result


static func _solve_brakes(
	start: Dictionary, layout: Dictionary, _coarse_settings: Dictionary
) -> Dictionary:
	var forward: Vector3 = layout.station_tangent.normalized()
	var remaining: float = (layout.station_position_m - start.position_m).dot(forward)
	if remaining <= 0.0:
		return _failure("station lies behind the solved capture", "brake")
	var support := Vector2(1.0, 0.0)
	var station_duration := _coast_time(2.0, 1.0)
	var station_distance := _coast_distance(2.0, 1.0)
	if not is_finite(station_duration) or not is_finite(station_distance):
		return _failure("station creep is infeasible under central resistance", "brake")
	if absf(start.tangent.normalized().dot(forward) - 1.0) > 0.00001 \
			or start.rider_up.normalized().distance_to(layout.station_up.normalized()) > 0.00001:
		return _failure("capture terminal frame is not the straight station frame", "brake")
	var wanted_moving := remaining - station_distance
	if wanted_moving <= 0.0:
		return _failure("reserved approach is shorter than the station creep", "brake")
	var production := _settings(0.01)
	var low := _brake_for_coast(start, 0.0, production)
	if not low.ok:
		return low
	var natural_time := _coast_time(start.speed_mps, 2.0)
	if not is_finite(natural_time) or natural_time <= 0.02:
		return _failure("capture exit has no moving-brake envelope", "brake")
	var high_coast := maxf(natural_time - 0.02, 0.0)
	var high := _brake_for_coast(start, high_coast, production)
	if not high.ok:
		return high
	if wanted_moving < low.distance_m + BRAKE_ENVELOPE_MARGIN_M \
			or wanted_moving > high.distance_m - BRAKE_ENVELOPE_MARGIN_M:
		return _failure("reserved moving-brake distance %.3f m is outside [%.3f, %.3f] m" %
			[wanted_moving, low.distance_m + BRAKE_ENVELOPE_MARGIN_M,
				high.distance_m - BRAKE_ENVELOPE_MARGIN_M], "brake")
	var chosen := low
	var coast_low := 0.0
	var coast_high := high_coast
	for _iteration in 42:
		var coast := 0.5 * (coast_low + coast_high)
		var candidate := _brake_for_coast(start, coast, production)
		if not candidate.ok:
			return candidate
		chosen = candidate
		if candidate.distance_m < wanted_moving:
			coast_low = coast
		else:
			coast_high = coast
	var distance_error: float = chosen.distance_m + station_distance - remaining
	if absf(distance_error) > 0.05 or absf(chosen.exit_speed_mps - 2.0) > 0.0001:
		return _failure("brake solve missed distance/speed boundary", "brake")
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"coast_duration_s": chosen.coast_duration_s,
		"brake_duration_s": chosen.brake_duration_s,
		"brake_peak_g": -1.2,
		"station_duration_s": station_duration,
		"support_normal_g": support.x,
		"support_lateral_g": support.y,
		"report": {
			"moving_boundary_speed_mps": chosen.exit_speed_mps,
			"terminal_creep_speed_mps": 1.0,
			"remaining_distance_m": remaining,
			"moving_distance_m": chosen.distance_m,
			"station_distance_m": station_distance,
			"distance_residual_m": distance_error,
			"lower_envelope_margin_m": wanted_moving - low.distance_m,
			"upper_envelope_margin_m": high.distance_m - wanted_moving,
			"positive_drive_allowed": false,
		},
	}


static func _brake_for_coast(
	start: Dictionary, coast_duration: float, settings: Dictionary
) -> Dictionary:
	var duration_low := 0.0001
	var duration_high := 1.0
	var high_route := _scalar_brake(start.speed_mps, coast_duration, duration_high, settings.step_s)
	while high_route.ok and high_route.speed_mps > 2.0 and duration_high < 90.0:
		duration_high *= 2.0
		high_route = _scalar_brake(start.speed_mps, coast_duration, duration_high, settings.step_s)
	if duration_high >= 90.0 and high_route.ok and high_route.speed_mps > 2.0:
		return _failure("brake pulse cannot reach the 2 m/s boundary", "brake")
	var chosen := {}
	for _iteration in 48:
		var duration := 0.5 * (duration_low + duration_high)
		var route := _scalar_brake(start.speed_mps, coast_duration, duration, settings.step_s)
		if route.ok and route.speed_mps >= 2.0:
			duration_low = duration
			chosen = route
		else:
			duration_high = duration
	if chosen.is_empty():
		return _failure("brake duration has no valid speed-floor side", "brake")
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"coast_duration_s": coast_duration,
		"brake_duration_s": duration_low,
		"exit_speed_mps": float(chosen.speed_mps),
		"distance_m": float(chosen.distance_m),
	}


static func _scalar_brake(
	initial_speed: float, coast_duration: float, brake_duration: float, step_s: float
) -> Dictionary:
	var state := Vector2(initial_speed, 0.0)
	if coast_duration > 0.000001:
		state = _scalar_span(state, coast_duration, Motion.constant(0.0), step_s)
	state = _scalar_span(state, brake_duration, Motion.compact_pulse(-1.2), step_s)
	return {"ok": state.x >= 2.0, "speed_mps": state.x, "distance_m": state.y}


static func _scalar_span(
	initial: Vector2, duration: float, drive: Dictionary, step_s: float
) -> Vector2:
	var speed := initial.x
	var distance := initial.y
	var elapsed := 0.0
	while elapsed < duration - 0.000000000001:
		var h := minf(step_s, duration - elapsed)
		var k1 := _scalar_derivative(speed, drive, elapsed / duration)
		var k2 := _scalar_derivative(speed + 0.5 * h * k1.x, drive,
			(elapsed + 0.5 * h) / duration)
		var k3 := _scalar_derivative(speed + 0.5 * h * k2.x, drive,
			(elapsed + 0.5 * h) / duration)
		var k4 := _scalar_derivative(speed + h * k3.x, drive, (elapsed + h) / duration)
		speed += h / 6.0 * (k1.x + 2.0 * k2.x + 2.0 * k3.x + k4.x)
		distance += h / 6.0 * (k1.y + 2.0 * k2.y + 2.0 * k3.y + k4.y)
		elapsed += h
	return Vector2(speed, distance)


static func _scalar_derivative(speed: float, drive: Dictionary, u: float) -> Vector2:
	var resistance := ROLLING_MPS2 + AERO_PER_M * speed * speed
	return Vector2(Motion.G0 * Motion.profile_sample(drive, clampf(u, 0.0, 1.0)).x
		- resistance, speed)


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


static func _landmark_report(
	trajectory: Dictionary, gestures: Array, metadata: Array, station_position: Vector3
) -> Dictionary:
	var gesture_ranges := {}
	for gesture in gestures:
		gesture_ranges[gesture.story_slot_id] = Vector2i(
			int(gesture.first_span), int(gesture.last_span))
	var lsm2_exit_span := -1
	var slow_crest_span := -1
	var rim_first_span := -1
	for index in metadata.size():
		if metadata[index].span_id == "climb/lsm2-release":
			lsm2_exit_span = index
		elif metadata[index].span_id == "rim/slow-crest":
			slow_crest_span = index
		elif metadata[index].span_id == "rim/outward-bank":
			rim_first_span = index
	var cliff_range: Vector2i = gesture_ranges["clifftop-suspense"]
	var climb_range: Vector2i = gesture_ranges["escarpment-climb"]
	var dive_range: Vector2i = gesture_ranges["cliff-dive"]
	var camel_range: Vector2i = gesture_ranges["marquee-camelback"]
	var cliff_samples := _span_sample_bounds(
		trajectory.span_index, lsm2_exit_span + 1, cliff_range.y)
	var dive_samples := _span_sample_bounds(
		trajectory.span_index, dive_range.x, dive_range.y)
	var camel_samples := _span_sample_bounds(
		trajectory.span_index, camel_range.x, camel_range.y)
	var slow_crest_samples := _span_sample_bounds(
		trajectory.span_index, slow_crest_span, slow_crest_span)
	var rim_samples := _span_sample_bounds(
		trajectory.span_index, rim_first_span, cliff_range.y)
	var cliff_apex := _maximum_height_sample(trajectory.position_m, cliff_samples)
	var camel_apex := _maximum_height_sample(trajectory.position_m, camel_samples)
	var targets := {
		"launch_exit": {"sample": _span_end_sample(trajectory.span_index,
			gesture_ranges["station-launch"].y), "height_m": [-5.0, 5.0],
			"speed_mps": [85.0, 98.0], "maximum_abs_tangent_y": 0.05},
		"act_one_exit": {"sample": _span_end_sample(trajectory.span_index,
			gesture_ranges["act-one"].y), "height_m": [-40.0, 40.0],
			"speed_mps": [40.0, 70.0], "maximum_abs_tangent_y": 0.18},
		"lsm2_exit": {"sample": _span_end_sample(trajectory.span_index, lsm2_exit_span),
			"height_m": [-20.0, 20.0],
			"speed_mps": [57.0, 64.0], "maximum_abs_tangent_y": 0.12},
		"cliff_crest": {"sample": cliff_apex,
			"height_m": null, "speed_mps": [5.0, 22.0],
			"maximum_abs_tangent_y": 0.22},
		"dive_exit": {"sample": dive_samples.y, "height_m": [-20.0, 20.0],
			"speed_mps": [55.0, 70.0]},
		"lsm3_exit": {"sample": _span_end_sample(trajectory.span_index,
			gesture_ranges["tunnel-lsm3"].y), "height_m": [-20.0, 20.0],
			"speed_mps": [90.0, 98.0]},
		"camelback_apex": {"sample": camel_apex, "height_m": null,
			"speed_mps": [50.0, 68.0]},
		"return_entry": {"sample": camel_samples.y,
			"height_m": [-20.0, 20.0], "speed_mps": [78.0, 92.0],
			"maximum_abs_tangent_y": 0.18},
	}
	var report := {}
	for landmark_id in targets.keys():
		var target: Dictionary = targets[landmark_id]
		var sample_index: int = target.sample
		var position: Vector3 = trajectory.position_m[sample_index]
		var tangent: Vector3 = trajectory.tangent[sample_index]
		var rider_up: Vector3 = trajectory.rider_up[sample_index]
		report[landmark_id] = {
			"span_index": trajectory.span_index[sample_index],
			"sample_index": sample_index,
			"height_m": position.y - station_position.y,
			"position_m": position,
			"speed_mps": trajectory.speed_mps[sample_index],
			"tangent": tangent.normalized(),
			"rider_up": rider_up.normalized(),
			"tangent_y": tangent.y,
			"time_s": trajectory.time_s[sample_index],
			"target_height_m": target.height_m,
			"target_speed_mps": target.speed_mps,
			"maximum_abs_tangent_y": target.get("maximum_abs_tangent_y", null),
		}
	var return_entry: Dictionary = report.return_entry
	return_entry["energy_headroom_j_per_kg"] = (
		0.5 * float(return_entry.speed_mps) ** 2
		+ Motion.G0 * float(return_entry.height_m) - 0.5
	)
	var dive_start_y: float = trajectory.position_m[dive_samples.x].y
	var dive_end_y: float = trajectory.position_m[dive_samples.y].y
	var camel_start: Vector3 = trajectory.position_m[camel_samples.x]
	var camel_end: Vector3 = trajectory.position_m[camel_samples.y]
	var prominence: float = trajectory.position_m[camel_apex].y \
		- maxf(camel_start.y, camel_end.y)
	var width := Vector2(camel_end.x - camel_start.x,
		camel_end.z - camel_start.z).length()
	var rim_exit := rim_samples.y
	var rim_exit_tangent: Vector3 = trajectory.tangent[rim_exit]
	var rim_exit_up: Vector3 = trajectory.rider_up[rim_exit]
	report["shape_evidence"] = {
		"crest_held_at_or_below_22_mps_s": _held_at_or_below(
			trajectory.time_s, trajectory.speed_mps, slow_crest_samples, 22.0),
		"cliff_prominence_m": trajectory.position_m[cliff_apex].y
			- trajectory.position_m[_span_sample_bounds(
				trajectory.span_index, climb_range.x, climb_range.x).x].y,
		"rim_heading_change_rad": _heading_change(trajectory.tangent, rim_samples),
		"rim_cross_track_m": _cross_track_displacement(
			trajectory.position_m, trajectory.tangent, rim_samples),
		"rim_maximum_bank_rad": _maximum_world_bank(
			trajectory.tangent, trajectory.rider_up, rim_samples),
		"rim_exit_bank_rad": _world_bank(rim_exit_tangent, rim_exit_up),
		"rim_exit_pitch_rad": asin(clampf(rim_exit_tangent.y, -1.0, 1.0)),
		"rim_exit_up_dot": rim_exit_up.dot(Vector3.UP),
		"dive_drop_m": dive_start_y - dive_end_y,
		"dive_minimum_tangent_y": _minimum_tangent_y(trajectory.tangent, dive_samples),
		"dive_maximum_height_step_m": _maximum_height_step(
			trajectory.position_m, dive_samples),
		"dive_minimum_normal_g": _minimum_value(trajectory.normal_g, dive_samples),
		"dive_maximum_normal_g": _maximum_value(trajectory.normal_g, dive_samples),
		"camelback_prominence_m": prominence,
		"camelback_width_m": width,
		"camelback_width_height_ratio": width / prominence,
		"camelback_negative_normal_duration_s": _held_below_zero(
			trajectory.time_s, trajectory.normal_g, camel_samples),
	}
	return report


static func _span_sample_bounds(
	span_indices: PackedInt32Array, first_span: int, last_span: int
) -> Vector2i:
	var first := 0
	while first < span_indices.size() - 1 and span_indices[first] < first_span:
		first += 1
	return Vector2i(first, _span_end_sample(span_indices, last_span))


static func _maximum_height_sample(
	positions: PackedVector3Array, bounds: Vector2i
) -> int:
	var result := bounds.x
	for index in range(bounds.x + 1, bounds.y + 1):
		if positions[index].y > positions[result].y:
			result = index
	return result


static func _minimum_tangent_y(tangents: PackedVector3Array, bounds: Vector2i) -> float:
	var result := INF
	for index in range(bounds.x, bounds.y + 1):
		result = minf(result, tangents[index].y)
	return result


static func _minimum_value(values: PackedFloat64Array, bounds: Vector2i) -> float:
	var result := INF
	for index in range(bounds.x, bounds.y + 1):
		result = minf(result, values[index])
	return result


static func _maximum_value(values: PackedFloat64Array, bounds: Vector2i) -> float:
	var result := -INF
	for index in range(bounds.x, bounds.y + 1):
		result = maxf(result, values[index])
	return result


static func _maximum_height_step(positions: PackedVector3Array, bounds: Vector2i) -> float:
	var result := -INF
	for index in range(bounds.x + 1, bounds.y + 1):
		result = maxf(result, positions[index].y - positions[index - 1].y)
	return result


static func _held_below_zero(
	times: PackedFloat64Array, values: PackedFloat64Array, bounds: Vector2i
) -> float:
	var result := 0.0
	for index in range(bounds.x + 1, bounds.y + 1):
		if 0.5 * (values[index - 1] + values[index]) < 0.0:
			result += times[index] - times[index - 1]
	return result


static func _held_at_or_below(
	times: PackedFloat64Array, values: PackedFloat64Array, bounds: Vector2i, threshold: float
) -> float:
	var result := 0.0
	for index in range(bounds.x + 1, bounds.y + 1):
		if 0.5 * (values[index - 1] + values[index]) <= threshold:
			result += times[index] - times[index - 1]
	return result


static func _heading_change(tangents: PackedVector3Array, bounds: Vector2i) -> float:
	var first := Vector2(tangents[bounds.x].x, tangents[bounds.x].z).normalized()
	var last := Vector2(tangents[bounds.y].x, tangents[bounds.y].z).normalized()
	return acos(clampf(first.dot(last), -1.0, 1.0))


static func _cross_track_displacement(
	positions: PackedVector3Array, tangents: PackedVector3Array, bounds: Vector2i
) -> float:
	var forward := Vector2(tangents[bounds.x].x, tangents[bounds.x].z).normalized()
	var right := Vector2(-forward.y, forward.x)
	var delta := Vector2(positions[bounds.y].x - positions[bounds.x].x,
		positions[bounds.y].z - positions[bounds.x].z)
	return absf(delta.dot(right))


static func _maximum_world_bank(
	tangents: PackedVector3Array, rider_ups: PackedVector3Array, bounds: Vector2i
) -> float:
	var result := 0.0
	for index in range(bounds.x, bounds.y + 1):
		result = maxf(result, _world_bank(tangents[index], rider_ups[index]))
	return result


static func _world_bank(tangent: Vector3, rider_up: Vector3) -> float:
	var level_up := Vector3.UP - tangent * tangent.y
	if level_up.length_squared() <= 0.000001:
		return INF
	return acos(clampf(rider_up.dot(level_up.normalized()), -1.0, 1.0))


static func _span_end_sample(span_indices: PackedInt32Array, span_index: int) -> int:
	for sample_index in span_indices.size():
		if span_indices[sample_index] > span_index:
			return sample_index
	return span_indices.size() - 1


static func _validate_landmark_report(report: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for landmark_id in report.keys():
		if landmark_id == "shape_evidence":
			continue
		var record: Dictionary = report[landmark_id]
		if record.target_height_m != null and (record.height_m < record.target_height_m[0] \
				or record.height_m > record.target_height_m[1]):
			errors.append("%s height %.3f m" % [landmark_id, record.height_m])
		if record.speed_mps < record.target_speed_mps[0] \
				or record.speed_mps > record.target_speed_mps[1]:
			errors.append("%s speed %.3f m/s" % [landmark_id, record.speed_mps])
		if record.maximum_abs_tangent_y != null \
				and absf(record.tangent_y) > record.maximum_abs_tangent_y:
			errors.append("%s tangent_y %.5f" % [landmark_id, record.tangent_y])
	var shape: Dictionary = report.shape_evidence
	if shape.crest_held_at_or_below_22_mps_s < 2.7 \
			or shape.crest_held_at_or_below_22_mps_s > 4.2:
		errors.append("crest held <=22 m/s %.3f s" \
			% shape.crest_held_at_or_below_22_mps_s)
	if shape.cliff_prominence_m < 150.0 or shape.cliff_prominence_m > 175.0:
		errors.append("cliff prominence %.3f m" % shape.cliff_prominence_m)
	if shape.rim_heading_change_rad < deg_to_rad(15.0) \
			or shape.rim_cross_track_m < 3.0 \
			or shape.rim_maximum_bank_rad < deg_to_rad(20.0):
		errors.append("rim shape heading %.1f deg, cross-track %.2f m, bank %.1f deg" % [
			rad_to_deg(shape.rim_heading_change_rad), shape.rim_cross_track_m,
			rad_to_deg(shape.rim_maximum_bank_rad)])
	if shape.rim_exit_bank_rad > deg_to_rad(2.0) \
			or absf(shape.rim_exit_pitch_rad) > deg_to_rad(3.0) \
			or shape.rim_exit_up_dot < 0.99:
		errors.append("rim exit bank %.2f deg, pitch %.2f deg, up-dot %.5f" % [
			rad_to_deg(shape.rim_exit_bank_rad), rad_to_deg(shape.rim_exit_pitch_rad),
			shape.rim_exit_up_dot])
	if shape.dive_drop_m < 140.0 or shape.dive_drop_m > 175.0:
		errors.append("dive drop %.3f m" % shape.dive_drop_m)
	if shape.dive_minimum_tangent_y > -sin(deg_to_rad(75.0)):
		errors.append("dive minimum tangent_y %.5f" % shape.dive_minimum_tangent_y)
	if shape.dive_maximum_height_step_m > 0.01:
		errors.append("dive rises %.5f m in one sample" % shape.dive_maximum_height_step_m)
	if shape.dive_minimum_normal_g < -1.300001 or shape.dive_maximum_normal_g > 5.000001:
		errors.append("dive normal range %.3f..%.3f g" % [
			shape.dive_minimum_normal_g, shape.dive_maximum_normal_g])
	if shape.camelback_prominence_m < 240.0 or shape.camelback_prominence_m > 260.0:
		errors.append("camelback prominence %.3f m" % shape.camelback_prominence_m)
	if shape.camelback_width_height_ratio < 3.1 \
			or shape.camelback_width_height_ratio > 3.9:
		errors.append("camelback width:height %.3f" % shape.camelback_width_height_ratio)
	if shape.camelback_negative_normal_duration_s < 4.0:
		errors.append("camelback negative normal duration %.3f s" \
			% shape.camelback_negative_normal_duration_s)
	return errors


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
