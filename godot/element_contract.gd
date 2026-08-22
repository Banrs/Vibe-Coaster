class_name ElementContract
extends RefCounted

## Intent-aware whole-material-role geometry measurement and validation.
##
## This file deliberately does not infer an element's design family from the geometry it happened
## to generate. A camelback declared as a vertical-plane element remains subject to vertical-plane
## limits even when a broken generator produces a strongly tilted or three-dimensional result.
## Measurement describes the accepted centreline; the caller-supplied intent decides what is legal.

const FRAME_EPS_SQ := 0.000000000001
const EIGEN_EPS := 1e-30
const VALID_PLANARITY := ["vertical-plane", "free-3d"]


## Measure one inclusive whole-element sample range from a published route-like dictionary.
## Required fields are `positions`, `tangents`, and `banks`; the arrays must be aligned. The
## output is finite and canonical-data-friendly apart from the explicit status/reason strings.
static func measure(route: Dictionary, first: int, last: int) -> Dictionary:
	var positions_value: Variant = route.get("positions")
	var tangents_value: Variant = route.get("tangents")
	var banks_value: Variant = route.get("banks")
	if typeof(positions_value) != TYPE_PACKED_VECTOR3_ARRAY:
		return _unavailable("route.positions must be PackedVector3Array")
	if typeof(tangents_value) != TYPE_PACKED_VECTOR3_ARRAY:
		return _unavailable("route.tangents must be PackedVector3Array")
	if typeof(banks_value) not in [TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY]:
		return _unavailable("route.banks must be a packed float array")
	var positions: PackedVector3Array = positions_value
	var tangents: PackedVector3Array = tangents_value
	var sample_count := positions.size()
	if tangents.size() != sample_count or banks_value.size() != sample_count:
		return _unavailable("whole-element route arrays must have one aligned sample count")
	if first < 0 or last < first or last >= sample_count:
		return _unavailable("whole-element sample bounds are invalid")
	var count := last - first + 1
	if count < 3:
		return _unavailable("whole-element measurement needs at least three samples")

	var centroid := Vector3.ZERO
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for index in range(first, last + 1):
		var position: Vector3 = positions[index]
		var tangent: Vector3 = tangents[index]
		var bank := float(banks_value[index])
		if not position.is_finite() or not tangent.is_finite() or not is_finite(bank):
			return _unavailable("whole-element samples must be finite")
		if tangent.length_squared() <= FRAME_EPS_SQ:
			return _unavailable("whole-element tangents must be non-degenerate")
		centroid += position
		low = low.min(position)
		high = high.max(position)
	centroid /= float(count)

	var covariance := [
		[0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0],
		[0.0, 0.0, 0.0],
	]
	for index in range(first, last + 1):
		var offset: Vector3 = positions[index] - centroid
		var components := [offset.x, offset.y, offset.z]
		for row in 3:
			for column in 3:
				covariance[row][column] += float(components[row]) * float(components[column])
	for row in 3:
		for column in 3:
			covariance[row][column] /= float(count)

	var eigen := _symmetric_eigen(covariance)
	if not eigen.get("ok", false):
		return _unavailable("whole-element best-fit plane could not be resolved")
	var normal: Vector3 = eigen.vectors[0]
	var squared := 0.0
	var maximum := 0.0
	for index in range(first, last + 1):
		var deviation := float((positions[index] - centroid).dot(normal))
		squared += deviation * deviation
		maximum = maxf(maximum, absf(deviation))
	var rms := sqrt(squared / float(count))
	var diagonal := (high - low).length()
	var ratio := rms / diagonal if diagonal > 0.000000001 else 0.0
	var heading := _heading_metrics(tangents, first, last)
	if not heading.get("ok", false):
		return _unavailable("whole-element heading could not be measured")

	return {
		"status": "measured",
		"sample_count": count,
		"first_sample": first,
		"last_sample": last,
		"centroid_m": [centroid.x, centroid.y, centroid.z],
		"plane_normal": [normal.x, normal.y, normal.z],
		"rms_out_of_plane_m": rms,
		"max_out_of_plane_m": maximum,
		"out_of_plane_ratio": ratio,
		"bounding_diagonal_m": diagonal,
		# A vertical design plane has a horizontal normal, so its Y component is zero.
		"vertical_plane_tilt_deg": rad_to_deg(asin(clampf(absf(normal.y), 0.0, 1.0))),
		"heading_drift_deg": float(heading.maximum_drift_deg),
		"net_heading_change_deg": float(heading.net_change_deg),
		"entry_pitch_deg": _pitch_deg(tangents[first]),
		"exit_pitch_deg": _pitch_deg(tangents[last]),
		"entry_bank_deg": float(banks_value[first]),
		"exit_bank_deg": float(banks_value[last]),
	}


## Validate one measured whole element against an adopted design intent. Schema errors are
## explicit: an adopted contract cannot silently omit an entry/exit state or a geometry limit.
static func validate(intent: Dictionary, measurement: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if measurement.get("status") != "measured":
		errors.append("measurement.status must be 'measured'")
		return errors

	var planarity := str(intent.get("planarity", ""))
	if planarity not in VALID_PLANARITY:
		errors.append("intent.planarity must be one of %s" % str(VALID_PLANARITY))
	# The plane limits are enforced only for vertical-plane intents, so only they may declare
	# them: a free-3d intent carrying plane limits would read as gated when it is not.
	var maximum_tilt := NAN
	var maximum_ratio := NAN
	if planarity == "vertical-plane":
		maximum_tilt = _required_nonnegative(intent, "max_plane_tilt_deg", errors)
		maximum_ratio = _required_nonnegative(intent, "max_out_of_plane_ratio", errors)
	else:
		for key in ["max_plane_tilt_deg", "max_out_of_plane_ratio"]:
			if intent.has(key):
				errors.append("intent.%s is only meaningful for planarity 'vertical-plane'" % key)
	var maximum_heading := _required_nonnegative(intent, "max_heading_drift_deg", errors)
	var entry_value: Variant = intent.get("entry")
	var exit_value: Variant = intent.get("exit")
	if not entry_value is Dictionary:
		errors.append("intent.entry must be a Dictionary")
	if not exit_value is Dictionary:
		errors.append("intent.exit must be a Dictionary")
	if entry_value is Dictionary:
		errors.append_array(_state_intent_errors("entry", entry_value))
	if exit_value is Dictionary:
		errors.append_array(_state_intent_errors("exit", exit_value))
	if not errors.is_empty():
		return errors

	if planarity == "vertical-plane":
		var measured_tilt := _measurement_number(
			measurement, "vertical_plane_tilt_deg", errors)
		var measured_ratio := _measurement_number(
			measurement, "out_of_plane_ratio", errors)
		if is_finite(measured_tilt) and measured_tilt > maximum_tilt:
			errors.append(
				"vertical_plane_tilt_deg %.6f exceeds intent.max_plane_tilt_deg %.6f"
				% [measured_tilt, maximum_tilt])
		if is_finite(measured_ratio) and measured_ratio > maximum_ratio:
			errors.append(
				"out_of_plane_ratio %.9f exceeds intent.max_out_of_plane_ratio %.9f"
				% [measured_ratio, maximum_ratio])

	var measured_heading := _measurement_number(measurement, "heading_drift_deg", errors)
	if is_finite(measured_heading) and measured_heading > maximum_heading:
		errors.append(
			"heading_drift_deg %.6f exceeds intent.max_heading_drift_deg %.6f"
			% [measured_heading, maximum_heading])
	if entry_value is Dictionary:
		_validate_boundary_state("entry", entry_value, measurement, errors)
	if exit_value is Dictionary:
		_validate_boundary_state("exit", exit_value, measurement, errors)
	return errors


static func _validate_boundary_state(
	label: String, state: Dictionary, measurement: Dictionary, errors: PackedStringArray
) -> void:
	var expected_pitch := float(state.pitch_deg)
	var pitch_tolerance := float(state.pitch_tolerance_deg)
	var expected_bank := float(state.bank_deg)
	var bank_tolerance := float(state.bank_tolerance_deg)
	var actual_pitch := _measurement_number(measurement, "%s_pitch_deg" % label, errors)
	var actual_bank := _measurement_number(measurement, "%s_bank_deg" % label, errors)
	if is_finite(actual_pitch) and absf(actual_pitch - expected_pitch) > pitch_tolerance:
		errors.append(
			"%s.pitch_deg expected %.6f +/- %.6f, measured %.6f"
			% [label, expected_pitch, pitch_tolerance, actual_pitch])
	if is_finite(actual_bank):
		var bank_error := absf(rad_to_deg(angle_difference(
			deg_to_rad(expected_bank), deg_to_rad(actual_bank))))
		if bank_error > bank_tolerance:
			errors.append(
				"%s.bank_deg expected %.6f +/- %.6f, measured %.6f"
				% [label, expected_bank, bank_tolerance, actual_bank])


static func _state_intent_errors(label: String, state: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	for key in ["pitch_deg", "pitch_tolerance_deg", "bank_deg", "bank_tolerance_deg"]:
		var value: Variant = state.get(key)
		if not _number(value):
			errors.append("intent.%s.%s must be finite" % [label, key])
	for key in ["pitch_tolerance_deg", "bank_tolerance_deg"]:
		var value: Variant = state.get(key)
		if _number(value) and float(value) < 0.0:
			errors.append("intent.%s.%s must be nonnegative" % [label, key])
	return errors


static func _required_nonnegative(
	intent: Dictionary, key: String, errors: PackedStringArray
) -> float:
	var value: Variant = intent.get(key)
	if not _number(value):
		errors.append("intent.%s must be finite" % key)
		return NAN
	var number := float(value)
	if number < 0.0:
		errors.append("intent.%s must be nonnegative" % key)
		return NAN
	return number


static func _measurement_number(
	measurement: Dictionary, key: String, errors: PackedStringArray
) -> float:
	var value: Variant = measurement.get(key)
	if not _number(value):
		errors.append("measurement.%s must be finite" % key)
		return NAN
	return float(value)


## Maximum unwrapped plan-heading displacement from the first usable tangent. Near-vertical
## tangent samples have no stable plan heading and are skipped without resetting continuity.
static func _heading_metrics(
	tangents: PackedVector3Array, first: int, last: int
) -> Dictionary:
	var found := false
	var previous := 0.0
	var accumulated := 0.0
	var maximum := 0.0
	for index in range(first, last + 1):
		var tangent: Vector3 = tangents[index].normalized()
		var plan := Vector2(tangent.x, tangent.z)
		if plan.length_squared() <= FRAME_EPS_SQ:
			continue
		var heading := atan2(plan.y, plan.x)
		if not found:
			found = true
			previous = heading
			continue
		accumulated += angle_difference(previous, heading)
		maximum = maxf(maximum, absf(accumulated))
		previous = heading
	return {
		"ok": found,
		"maximum_drift_deg": rad_to_deg(maximum),
		"net_change_deg": rad_to_deg(accumulated),
	}


static func _pitch_deg(tangent: Vector3) -> float:
	return rad_to_deg(asin(clampf(tangent.normalized().y, -1.0, 1.0)))


static func _unavailable(reason: String) -> Dictionary:
	return {"status": "unavailable", "reason": reason}


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


## Cyclic Jacobi eigen-decomposition of a symmetric 3x3, eigenvalues ascending. Fixed sweep
## order and vector-sign convention make repeated measurements deterministic.
static func _symmetric_eigen(matrix: Array) -> Dictionary:
	var a := [
		[float(matrix[0][0]), float(matrix[0][1]), float(matrix[0][2])],
		[float(matrix[1][0]), float(matrix[1][1]), float(matrix[1][2])],
		[float(matrix[2][0]), float(matrix[2][1]), float(matrix[2][2])],
	]
	var v := [
		[1.0, 0.0, 0.0],
		[0.0, 1.0, 0.0],
		[0.0, 0.0, 1.0],
	]
	var pairs := [[0, 1], [0, 2], [1, 2]]
	for _sweep in 32:
		var off := 0.0
		for pair in pairs:
			off += float(a[pair[0]][pair[1]]) * float(a[pair[0]][pair[1]])
		if off <= EIGEN_EPS:
			break
		for pair in pairs:
			var p: int = pair[0]
			var q: int = pair[1]
			if absf(float(a[p][q])) <= 1e-300:
				continue
			var theta := (float(a[q][q]) - float(a[p][p])) / (2.0 * float(a[p][q]))
			var sign := 1.0 if theta >= 0.0 else -1.0
			var t := sign / (absf(theta) + sqrt(theta * theta + 1.0))
			var c := 1.0 / sqrt(t * t + 1.0)
			var s := t * c
			_rotate_columns(a, p, q, c, s)
			for k in 3:
				var apk := float(a[p][k])
				var aqk := float(a[q][k])
				a[p][k] = c * apk - s * aqk
				a[q][k] = s * apk + c * aqk
			_rotate_columns(v, p, q, c, s)
	var order := [0, 1, 2]
	order.sort_custom(func(left: int, right: int) -> bool:
		if float(a[left][left]) != float(a[right][right]):
			return float(a[left][left]) < float(a[right][right])
		return left < right)
	var values := []
	var vectors := []
	for index in order:
		values.append(float(a[index][index]))
		var vector := Vector3(
			float(v[0][index]), float(v[1][index]), float(v[2][index]))
		if not vector.is_finite() or vector.length_squared() <= FRAME_EPS_SQ:
			return {"ok": false, "values": [], "vectors": []}
		vector = vector.normalized()
		var dominant := vector.x
		if absf(vector.y) > absf(dominant):
			dominant = vector.y
		if absf(vector.z) > absf(dominant):
			dominant = vector.z
		if dominant < 0.0:
			vector = -vector
		vectors.append(vector)
	return {"ok": true, "values": values, "vectors": vectors}


static func _rotate_columns(matrix: Array, p: int, q: int, c: float, s: float) -> void:
	for k in 3:
		var kp := float(matrix[k][p])
		var kq := float(matrix[k][q])
		matrix[k][p] = c * kp - s * kq
		matrix[k][q] = s * kp + c * kq
