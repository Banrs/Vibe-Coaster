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
	var spans: Array = []
	var metadata: Array = []
	var gestures: Array = []
	var propulsion := PackedInt32Array()

	_begin_gesture(gestures, "station-launch", spans.size())
	_add(spans, metadata, propulsion, "launch/settle", 0.03, "station",
		1.0, 0.0, 4.0, 0.0, "station", 1, 0.0)
	_add(spans, metadata, propulsion, "launch/core", 1.30, "moving",
		1.0, 0.0, 4.0, 0.0, "core", 1)
	_add(spans, metadata, propulsion, "launch/release", 0.30, "moving",
		1.0, 0.0, Motion.quintic(4.0, 0.0), 0.0, "core", 1)
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "opener", spans.size(), "twisted_drop")
	_add(spans, metadata, propulsion, "opener/pull-up", 1.35, "moving",
		Motion.quintic(1.0, 3.1), Motion.constant(0.0), Motion.constant(0.0),
		Motion.constant(0.0), "entry")
	_add(spans, metadata, propulsion, "opener/rising", 2.75, "moving",
		Motion.quintic(3.1, 0.82), 0.0, 0.0, 0.0, "climb")
	_add(spans, metadata, propulsion, "opener/crest", 1.15, "moving",
		Motion.quintic(0.82, -0.55), Motion.constant(0.0), Motion.constant(0.0),
		Motion.compact_pulse(deg_to_rad(24.0)), "crest")
	_add(spans, metadata, propulsion, "opener/twisted-drop", 3.10, "moving",
		Motion.quintic(-0.55, 1.0), Motion.compact_pulse(0.62), Motion.constant(0.0),
		Motion.compact_pulse(deg_to_rad(-72.0)), "core")
	_add(spans, metadata, propulsion, "opener/pullout", 1.25, "moving",
		Motion.quintic(1.0, 3.8), Motion.constant(0.0), Motion.constant(0.0),
		Motion.constant(0.0), "exit")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "act-one", spans.size())
	_add_act_one(spans, metadata, propulsion)
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "escarpment-climb", spans.size())
	_add(spans, metadata, propulsion, "climb/lsm2-entry", 0.30, "moving",
		Motion.quintic(1.0, 2.6), Motion.constant(0.0), Motion.quintic(0.0, 1.58),
		Motion.constant(0.0), "lsm2", 2)
	_add(spans, metadata, propulsion, "climb/lsm2-core", 1.70, "moving",
		2.6, 0.0, 1.58, 0.0, "lsm2", 2)
	_add(spans, metadata, propulsion, "climb/lsm2-release", 0.30, "moving",
		2.6, 0.0, Motion.quintic(1.58, 0.0), 0.0, "lsm2", 2)
	_add(spans, metadata, propulsion, "climb/pull-up", 1.30, "moving",
		Motion.quintic(2.6, 0.84), Motion.constant(0.0), Motion.constant(0.0),
		Motion.constant(0.0), "unpowered-climb")
	_add(spans, metadata, propulsion, "climb/coast", 8.80, "moving",
		0.84, 0.0, 0.0, 0.0, "unpowered-climb")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "clifftop-suspense", spans.size())
	_add(spans, metadata, propulsion, "rim/slow-crest", 1.30, "moving",
		Motion.quintic(0.84, 0.12), Motion.constant(0.0), Motion.constant(0.0),
		Motion.compact_pulse(deg_to_rad(18.0)), "slow-crest")
	_add(spans, metadata, propulsion, "rim/outward", 4.60, "moving",
		Motion.quintic(0.12, 0.62), Motion.compact_pulse(0.34), 0.0,
		Motion.compact_pulse(deg_to_rad(36.0)), "outward-rim", 0, 2.0, "turn")
	_add(spans, metadata, propulsion, "rim/dive-entry", 1.30, "moving",
		Motion.quintic(0.62, -0.20), Motion.constant(0.0), Motion.constant(0.0),
		Motion.quintic(0.0, deg_to_rad(-18.0)), "exit")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "cliff-dive", spans.size(), "dive")
	_add(spans, metadata, propulsion, "dive/rotate", 1.40, "moving",
		Motion.quintic(-0.20, 0.05), Motion.constant(0.0), Motion.constant(0.0),
		Motion.quintic(deg_to_rad(-18.0), 0.0), "entry")
	_add(spans, metadata, propulsion, "dive/core", 4.10, "moving",
		0.05, 0.0, 0.0, 0.0, "core")
	_add(spans, metadata, propulsion, "dive/pullout", 1.50, "moving",
		Motion.quintic(0.05, 4.1), Motion.constant(0.0), Motion.constant(0.0),
		Motion.constant(0.0), "exit")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "tunnel-lsm3", spans.size())
	_add(spans, metadata, propulsion, "tunnel/lsm3-entry", 0.30, "moving",
		Motion.quintic(4.1, 1.0), Motion.constant(0.0), Motion.quintic(0.0, 1.45),
		Motion.constant(0.0), "core", 3)
	_add(spans, metadata, propulsion, "tunnel/lsm3-core", 1.50, "moving",
		1.0, 0.0, 1.45, 0.0, "core", 3)
	_add(spans, metadata, propulsion, "tunnel/lsm3-release", 0.30, "moving",
		1.0, 0.0, Motion.quintic(1.45, 0.0), 0.0, "core", 3)
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "marquee-camelback", spans.size(), "hill")
	_add(spans, metadata, propulsion, "camelback/pull-up", 1.35, "moving",
		Motion.quintic(1.0, 3.8), Motion.constant(0.0), Motion.constant(0.0),
		Motion.constant(0.0), "entry")
	_add(spans, metadata, propulsion, "camelback/rise", 2.35, "moving",
		Motion.quintic(3.8, 0.52), 0.0, 0.0, 0.0, "rise")
	_add(spans, metadata, propulsion, "camelback/crest", 1.75, "moving",
		Motion.quintic(0.52, -0.35), Motion.constant(0.0), Motion.constant(0.0),
		Motion.constant(0.0), "crest")
	_add(spans, metadata, propulsion, "camelback/fall", 1.90, "moving",
		Motion.quintic(-0.35, 0.52), 0.0, 0.0, 0.0, "fall")
	_add(spans, metadata, propulsion, "camelback/pullout-rise", 0.325, "moving",
		Motion.quintic(0.52, 3.8), Motion.constant(0.0), Motion.constant(0.0),
		Motion.constant(0.0), "exit")
	_add(spans, metadata, propulsion, "camelback/pullout-release", 0.325, "moving",
		Motion.quintic(3.8, 1.0), Motion.constant(0.0), Motion.constant(0.0),
		Motion.constant(0.0), "exit")
	_end_gesture(gestures, metadata, spans.size() - 1)

	_begin_gesture(gestures, "raceway-return", spans.size())
	_add_raceway(spans, metadata, propulsion)
	_end_gesture(gestures, metadata, spans.size() - 1)

	var settings := _settings(COARSE_STEP_S)
	var prefix := Motion.integrate(initial_state, spans, settings)
	if not prefix.get("ok", false):
		return _failure("prefix integration failed: %s" % ", ".join(
			prefix.get("errors", [])), "prefix")
	var capture_start := _last_state(prefix)
	var capture := _solve_capture(capture_start, layout, settings)
	if not capture.ok:
		return capture
	var capture_spans: Array = _capture_spans(capture.coefficients)
	var capture_route := Motion.integrate(capture_start, capture_spans, settings)
	if not capture_route.get("ok", false):
		return _capture_failure("accepted capture did not reintegrate",
			capture.unique_evaluations, capture.residuals, capture.margins)
	var brake := _solve_brakes(_last_state(capture_route), layout, settings)
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
			"residuals": capture.residuals,
			"fine_residuals": capture.fine_residuals,
			"margins": capture.margins,
			"positive_drive_allowed": false,
		},
		"brake_plan": brake.report,
		"settings": _settings(0.01),
	}


static func _add_act_one(spans: Array, metadata: Array, propulsion: PackedInt32Array) -> void:
	_add(spans, metadata, propulsion, "act-one/immelmann-entry", 2.2, "moving",
		Motion.quintic(3.8, 4.2), Motion.constant(0.0), Motion.constant(0.0),
		Motion.compact_pulse(deg_to_rad(52.0)), "giant-inversion", 0, 2.0, "immelmann")
	_add(spans, metadata, propulsion, "act-one/immelmann-apex", 2.6, "moving",
		Motion.quintic(4.2, 0.25), Motion.constant(0.0), Motion.constant(0.0),
		Motion.compact_pulse(deg_to_rad(74.0)), "giant-inversion", 0, 2.0, "immelmann")
	_add(spans, metadata, propulsion, "act-one/cutback-rise", 1.6, "moving",
		Motion.quintic(0.25, 3.6), Motion.compact_pulse(-0.85), Motion.constant(0.0),
		Motion.compact_pulse(deg_to_rad(-88.0)), "cutback", 0, 2.0, "cutback")
	_add(spans, metadata, propulsion, "act-one/cutback-release", 1.6, "moving",
		Motion.quintic(3.6, 1.0), Motion.compact_pulse(0.85), Motion.constant(0.0),
		Motion.compact_pulse(deg_to_rad(88.0)), "cutback", 0, 2.0, "cutback")
	_add(spans, metadata, propulsion, "act-one/loop-rise", 2.7, "moving",
		Motion.quintic(1.0, 4.7), Motion.compact_pulse(0.42), Motion.constant(0.0),
		Motion.constant(0.0), "giant-inversion", 0, 2.0, "loop")
	_add(spans, metadata, propulsion, "act-one/loop-release", 2.7, "moving",
		Motion.quintic(4.7, 1.0), Motion.compact_pulse(-0.42), Motion.constant(0.0),
		Motion.constant(0.0), "giant-inversion", 0, 2.0, "loop")
	_add(spans, metadata, propulsion, "act-one/hills-rise", 3.2, "moving",
		Motion.quintic(1.0, -0.75), Motion.constant(0.0), Motion.constant(0.0),
		Motion.compact_pulse(deg_to_rad(34.0)), "airtime-hills", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "act-one/hills-release", 3.2, "moving",
		Motion.quintic(-0.75, 1.0), Motion.constant(0.0), Motion.constant(0.0),
		Motion.compact_pulse(deg_to_rad(-34.0)), "airtime-hills", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "act-one/wave-turn-rise", 2.0, "moving",
		Motion.quintic(1.0, 2.4), Motion.compact_pulse(0.72), Motion.constant(0.0),
		Motion.compact_pulse(deg_to_rad(-62.0)), "wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/wave-turn-release", 2.0, "moving",
		Motion.quintic(2.4, 1.0), Motion.compact_pulse(-0.72), Motion.constant(0.0),
		Motion.compact_pulse(deg_to_rad(62.0)), "wave-turn", 0, 2.0, "wave_turn")
	_add(spans, metadata, propulsion, "act-one/release", 2.2, "moving",
		Motion.quintic(1.0, 1.0), Motion.constant(0.0), Motion.constant(0.0),
		Motion.constant(0.0), "exit")


static func _add_raceway(spans: Array, metadata: Array, propulsion: PackedInt32Array) -> void:
	_add(spans, metadata, propulsion, "raceway/overbank", 10.0, "moving",
		Motion.quintic(1.0, 1.0), Motion.compact_pulse(0.52), Motion.constant(0.0),
		Motion.compact_pulse(deg_to_rad(48.0)), "overbank", 0, 2.0, "overbank")
	_add(spans, metadata, propulsion, "raceway/airtime-one", 9.0, "moving",
		Motion.quintic(1.0, 1.0), Motion.constant(0.0), Motion.constant(0.0),
		Motion.constant(0.0), "airtime-release", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "raceway/turn", 12.0, "moving",
		Motion.quintic(1.0, 1.0), Motion.compact_pulse(-0.38), Motion.constant(0.0),
		Motion.compact_pulse(deg_to_rad(-38.0)), "raceway-arc", 0, 2.0, "turn")
	_add(spans, metadata, propulsion, "raceway/airtime-two", 9.0, "moving",
		Motion.quintic(1.0, 1.0), Motion.constant(0.0), Motion.constant(0.0),
		Motion.constant(0.0), "airtime-release", 0, 2.0, "hill")
	_add(spans, metadata, propulsion, "raceway/home", 14.0, "moving",
		Motion.quintic(1.0, 1.0), Motion.compact_pulse(0.28), Motion.constant(0.0),
		Motion.compact_pulse(deg_to_rad(24.0)), "raceway-arc", 0, 2.0, "turn")


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
	for _iteration in 6:
		var base := _capture_evaluation(start, layout, coefficients, settings, cache)
		if not base.ok:
			return base
		residuals = base.residuals
		if _capture_converged(residuals):
			break
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
		var step := _linear_solve(jacobian, base.scaled)
		if step.is_empty():
			return _capture_failure("capture Jacobian is singular", cache.size(),
				base.residuals, base.margins)
		for index in 5:
			coefficients[index] = clampf(coefficients[index] - 0.7 * step[index],
				CAPTURE_COEFFICIENT_BOUNDS[index][0], CAPTURE_COEFFICIENT_BOUNDS[index][1])
		if cache.size() >= MAX_CAPTURE_EVALUATIONS - 1:
			break
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
	for margin in fine.margins.values():
		if float(margin) < 0.0:
			return _capture_failure("solved capture violates an inequality: %s" %
				str(fine.margins), cache.size(), fine.residuals, fine.margins)
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"coefficients": coefficients,
		"residuals": coarse.residuals,
		"fine_residuals": fine.residuals,
		"unique_evaluations": cache.size(),
		"margins": _capture_margins(coefficients, fine.route, layout),
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
	var minimum_speed := INF
	var maximum_normal := 0.0
	var maximum_lateral := 0.0
	var maximum_roll := 0.0
	for index in route.position_m.size():
		var delta: Vector3 = route.position_m[index] - layout.station_position_m
		maximum_cross = maxf(maximum_cross, absf(delta.dot(right)))
		maximum_height = maxf(maximum_height, absf(delta.dot(up)))
		minimum_speed = minf(minimum_speed, route.speed_mps[index])
		maximum_normal = maxf(maximum_normal, absf(route.normal_g[index]))
		maximum_lateral = maxf(maximum_lateral, absf(route.lateral_g[index]))
		maximum_roll = maxf(maximum_roll, absf(route.roll_rate_rad_s[index]))
	return {
		"corridor_cross_m": half_width - maximum_cross,
		"corridor_height_m": half_height - maximum_height,
		"speed_floor_mps": minimum_speed - 2.0,
		"normal_force_g": 8.0 - maximum_normal,
		"lateral_force_g": 4.7 - maximum_lateral,
		"roll_rate_rad_s": deg_to_rad(120.0) - maximum_roll,
	}


static func _linear_solve(matrix: Array, residual: Array) -> Array:
	var augmented: Array = []
	for row in 5:
		augmented.append(matrix[row].duplicate())
		augmented[row].append(residual[row])
	for column in 5:
		var pivot := column
		for row in range(column + 1, 5):
			if absf(augmented[row][column]) > absf(augmented[pivot][column]):
				pivot = row
		if absf(augmented[pivot][column]) < 0.000000001:
			return []
		var temporary = augmented[column]
		augmented[column] = augmented[pivot]
		augmented[pivot] = temporary
		var divisor: float = augmented[column][column]
		for index in range(column, 6):
			augmented[column][index] /= divisor
		for row in 5:
			if row == column:
				continue
			var factor: float = augmented[row][column]
			for index in range(column, 6):
				augmented[row][index] -= factor * augmented[column][index]
	var solution := []
	for row in 5:
		solution.append(augmented[row][5])
	return solution


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
	if wanted_moving < low.distance_m - 0.05 or wanted_moving > high.distance_m + 0.05:
		return _failure("reserved moving-brake distance %.3f m is outside [%.3f, %.3f] m" %
			[wanted_moving, low.distance_m, high.distance_m], "brake")
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
