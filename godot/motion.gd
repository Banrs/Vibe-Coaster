class_name RideMotion
extends RefCounted

const G0 := 9.80665
const MIN_MOVING_SPEED_MPS := 2.0
const FRAME_EPS := 0.000001
const STATION_TRANSVERSE_TOLERANCE_G := 0.00001
const PLATEAU_PULSE_AREA := 2.0 / 3.0
const STEP_FOLD_FRACTION := 0.005

const DP := 0
const DT := 1
const DU := 2
const DV := 3
const DS := 4


static func constant(value: float) -> Dictionary:
	var profile := {"kind": "constant", "value": value}
	profile.make_read_only()
	return profile


static func quintic(from: float, to: float) -> Dictionary:
	var profile := {"kind": "quintic", "from": from, "to": to}
	profile.make_read_only()
	return profile


static func compact_pulse(amplitude: float) -> Dictionary:
	var profile := {"kind": "compact_pulse", "amplitude": amplitude}
	profile.make_read_only()
	return profile


## C2 load notch whose perturbation has zero area and zero first moment.
static func balanced_notch(baseline: float, depth: float) -> Dictionary:
	var profile := {"kind": "balanced_notch", "baseline": baseline,
		"amplitude": depth * 3100.0 / 1099.0}
	profile.make_read_only()
	return profile


## C2 wide pulse with one-third-duration quintic shoulders and a flat center.
static func plateau_pulse(amplitude: float) -> Dictionary:
	var profile := {"kind": "plateau_pulse", "amplitude": amplitude}
	profile.make_read_only()
	return profile


## Proper normal load for a level bank transition driven by compact-pulse roll.
static func bank_balance(from_bank_rad: float, to_bank_rad: float) -> Dictionary:
	var profile := {"kind": "bank_balance", "from": from_bank_rad, "to": to_bank_rad}
	profile.make_read_only()
	return profile


## Returns value, first derivative with respect to normalized profile time, and second derivative.
static func profile_sample(profile: Dictionary, u: float) -> Vector3:
	match profile.get("kind", ""):
		"constant":
			return Vector3(profile.value, 0.0, 0.0)
		"quintic":
			var h := 10.0 * u ** 3 - 15.0 * u ** 4 + 6.0 * u ** 5
			var dh := 30.0 * u ** 2 - 60.0 * u ** 3 + 30.0 * u ** 4
			var d2h := 60.0 * u - 180.0 * u ** 2 + 120.0 * u ** 3
			var delta: float = profile.to - profile.from
			return Vector3(profile.from + delta * h, delta * dh, delta * d2h)
		"compact_pulse":
			var h := 10.0 * u ** 3 - 15.0 * u ** 4 + 6.0 * u ** 5
			var dh := 30.0 * u ** 2 - 60.0 * u ** 3 + 30.0 * u ** 4
			var d2h := 60.0 * u - 180.0 * u ** 2 + 120.0 * u ** 3
			var scale: float = 4.0 * profile.amplitude
			return Vector3(
				scale * h * (1.0 - h),
				scale * dh * (1.0 - 2.0 * h),
				scale * (d2h * (1.0 - 2.0 * h) - 2.0 * dh * dh)
			)
		"balanced_notch":
			var h := 10.0 * u ** 3 - 15.0 * u ** 4 + 6.0 * u ** 5
			var dh := 30.0 * u ** 2 - 60.0 * u ** 3 + 30.0 * u ** 4
			var d2h := 60.0 * u - 180.0 * u ** 2 + 120.0 * u ** 3
			var pulse := 4.0 * h * (1.0 - h)
			var pulse_derivative := 4.0 * dh * (1.0 - 2.0 * h)
			var pulse_second := 4.0 * (
				d2h * (1.0 - 2.0 * h) - 2.0 * dh * dh)
			var balance := 4199.0 / 3100.0
			var scale: float = profile.amplitude
			return Vector3(
				profile.baseline + scale * pulse * (1.0 - balance * pulse),
				scale * pulse_derivative * (1.0 - 2.0 * balance * pulse),
				scale * (pulse_second * (1.0 - 2.0 * balance * pulse)
					- 2.0 * balance * pulse_derivative * pulse_derivative)
			)
		"plateau_pulse":
			var edge_u := minf(u, 1.0 - u)
			if edge_u >= 1.0 / 3.0:
				return Vector3(profile.amplitude, 0.0, 0.0)
			var shoulder_u := edge_u * 3.0
			var h := 10.0 * shoulder_u ** 3 - 15.0 * shoulder_u ** 4 \
				+ 6.0 * shoulder_u ** 5
			var dh := 30.0 * shoulder_u ** 2 - 60.0 * shoulder_u ** 3 \
				+ 30.0 * shoulder_u ** 4
			var d2h := 60.0 * shoulder_u - 180.0 * shoulder_u ** 2 \
				+ 120.0 * shoulder_u ** 3
			var direction := 1.0 if u <= 0.5 else -1.0
			return Vector3(profile.amplitude * h,
				profile.amplitude * dh * 3.0 * direction,
				profile.amplitude * d2h * 9.0)
		"bank_balance":
			var h := 10.0 * u ** 3 - 15.0 * u ** 4 + 6.0 * u ** 5
			var dh := 30.0 * u ** 2 - 60.0 * u ** 3 + 30.0 * u ** 4
			var d2h := 60.0 * u - 180.0 * u ** 2 + 120.0 * u ** 3
			var pulse := 4.0 * h * (1.0 - h)
			var pulse_derivative := 4.0 * dh * (1.0 - 2.0 * h)
			var fraction := _compact_pulse_integral(u) / (100.0 / 231.0)
			var bank_delta: float = profile.to - profile.from
			var bank: float = profile.from + bank_delta * fraction
			var bank_derivative := bank_delta * pulse / (100.0 / 231.0)
			var bank_second := bank_delta * pulse_derivative / (100.0 / 231.0)
			var secant := 1.0 / cos(bank)
			var tangent := tan(bank)
			return Vector3(secant, secant * tangent * bank_derivative,
				secant * ((tangent * tangent + secant * secant)
					* bank_derivative * bank_derivative + tangent * bank_second))
	assert(false, "invalid motion profile")
	return Vector3.ZERO


static func profile_peak_abs_derivative_estimate(profile: Dictionary) -> float:
	match profile.get("kind", ""):
		"constant":
			return 0.0
		"quintic":
			return 1.875 * absf(float(profile.to) - float(profile.from))
		"compact_pulse":
			return 3.5663941463932597 * absf(float(profile.amplitude))
		"balanced_notch":
			var peak := 0.0
			for index in 257:
				peak = maxf(peak, absf(profile_sample(profile, float(index) / 256.0).y))
			return peak
		"plateau_pulse":
			return 5.625 * absf(float(profile.amplitude))
		"bank_balance":
			var peak := 0.0
			for index in 257:
				peak = maxf(peak, absf(profile_sample(profile, float(index) / 256.0).y))
			return peak
	assert(false, "invalid motion profile")
	return 0.0


## Returns resistance, dq/dv, and d2q/dv2.
static func resistance(speed_mps: float, rolling_mps2: float, aero_per_m: float) -> Vector3:
	return Vector3(
		rolling_mps2 + aero_per_m * speed_mps * speed_mps,
		2.0 * aero_per_m * speed_mps,
		2.0 * aero_per_m
	)


static func span(
	span_id: String,
	duration_s: float,
	mode: String,
	normal_g: Dictionary,
	lateral_g: Dictionary,
	drive_g: Dictionary,
	roll_rate_rad_s: Dictionary
) -> Dictionary:
	assert(is_finite(duration_s) and duration_s > 0.0, "span duration must be positive and finite")
	assert(mode == "moving" or mode == "station", "invalid span mode")
	for profile in [normal_g, lateral_g, drive_g, roll_rate_rad_s]:
		assert(profile.has("kind"), "invalid span profile")
		match profile.kind:
			"constant": assert(profile.has("value"), "invalid constant profile")
			"quintic": assert(profile.has("from") and profile.has("to"), "invalid quintic profile")
			"compact_pulse":
				assert(profile.has("amplitude") and is_finite(float(profile.amplitude)),
					"invalid compact pulse profile")
			"balanced_notch": assert(profile.has("baseline") and profile.has("amplitude")
				and is_finite(float(profile.baseline)) and is_finite(float(profile.amplitude))
				and float(profile.amplitude) >= 0.0, "invalid balanced notch profile")
			"plateau_pulse": assert(profile.has("amplitude")
				and is_finite(float(profile.amplitude)), "invalid plateau pulse profile")
			"bank_balance": assert(profile.has("from") and profile.has("to")
				and absf(float(profile.from)) < PI * 0.5
				and absf(float(profile.to)) < PI * 0.5, "invalid bank balance profile")
			_: assert(false, "invalid span profile kind")
	var record := {
		"span_id": span_id,
		"duration_s": duration_s,
		"mode": mode,
		"normal_g": normal_g,
		"lateral_g": lateral_g,
		"drive_g": drive_g,
		"roll_rate_rad_s": roll_rate_rad_s,
	}
	record.make_read_only()
	return record


static func integrate(
	initial_state: Dictionary, spans: Array, settings: Dictionary = {}
) -> Dictionary:
	var result := _empty_trajectory()
	if spans.is_empty():
		return _reject(result, "at least one motion span is required")
	var step_s: float = settings.get("step_s", 0.01)
	var gravity: Vector3 = settings.get("gravity_mps2", Vector3.DOWN * G0)
	var rolling: float = settings.get("rolling_mps2", 0.0)
	var aero: float = settings.get("aero_per_m", 0.0)
	if not is_finite(step_s) or step_s <= 0.0:
		return _reject(result, "step_s must be positive and finite")
	if not _finite_vector(gravity) or not is_finite(rolling) or not is_finite(aero) \
			or rolling < 0.0 or aero < 0.0:
		return _reject(result, "motion settings must be finite and nonnegative")

	var position: Vector3 = initial_state.get("position_m", Vector3.ZERO)
	var tangent: Vector3 = initial_state.get("tangent", Vector3.ZERO)
	var up: Vector3 = initial_state.get("rider_up", Vector3.ZERO)
	var speed: float = initial_state.get("speed_mps", NAN)
	var distance: float = initial_state.get("distance_m", 0.0)
	var time: float = initial_state.get("time_s", 0.0)
	if not _finite_vector(position) or not _finite_vector(tangent) \
			or not _finite_vector(up) or not is_finite(speed) \
			or not is_finite(distance) or not is_finite(time):
		return _reject(result, "initial motion state must be finite")
	if tangent.length_squared() <= FRAME_EPS * FRAME_EPS:
		return _reject(result, "initial tangent must be nonzero")
	if up.length_squared() <= FRAME_EPS * FRAME_EPS:
		return _reject(result, "initial rider_up must be nonzero")
	tangent = tangent.normalized()
	up -= tangent * tangent.dot(up)
	if up.length_squared() <= FRAME_EPS * FRAME_EPS:
		return _reject(result, "initial tangent and rider_up must be orthogonal")
	up = up.normalized()
	if speed < 0.0:
		return _reject(result, "initial speed must be nonnegative")
	if spans[0].mode == "moving" and speed < MIN_MOVING_SPEED_MPS:
		return _reject(result, "moving speed floor is 2 m/s")

	var derivatives := [[], [], [], []]
	for derivative in derivatives:
		derivative.resize(5)
	_append_native(result, time, distance, position, tangent, up, speed, 0, spans[0], 0.0,
		gravity, rolling, aero)

	for span_index in spans.size():
		var motion_span: Dictionary = spans[span_index]
		var span_elapsed := 0.0
		if span_index > 0:
			if motion_span.mode == "moving" and speed < MIN_MOVING_SPEED_MPS:
				return _reject(result, "moving speed floor is 2 m/s")
			_set_native_controls(result, result.time_s.size() - 1, span_index, motion_span,
				0.0, tangent, up, speed, gravity, rolling, aero)
		while span_elapsed < float(motion_span.duration_s) - 0.000000000001:
			var remaining_s: float = float(motion_span.duration_s) - span_elapsed
			# Fold a sub-public-resolution remainder into the adjacent RK step. Otherwise
			# the native Float64 node can collapse when the route publishes Float32 time.
			var h := remaining_s if remaining_s <= step_s + maxf(0.000000000001,
				step_s * STEP_FOLD_FRACTION) else step_s
			var error := _rk4_derivative(derivatives[0], position, tangent, up, speed,
				motion_span, span_elapsed, gravity, rolling, aero, false)
			if not error.is_empty():
				return _reject(result, error)
			error = _rk4_derivative(derivatives[1],
				position + derivatives[0][DP] * (0.5 * h),
				tangent + derivatives[0][DT] * (0.5 * h),
				up + derivatives[0][DU] * (0.5 * h), speed + derivatives[0][DV] * (0.5 * h),
				motion_span, span_elapsed + 0.5 * h, gravity, rolling, aero, true)
			if not error.is_empty():
				return _reject(result, error)
			error = _rk4_derivative(derivatives[2],
				position + derivatives[1][DP] * (0.5 * h),
				tangent + derivatives[1][DT] * (0.5 * h),
				up + derivatives[1][DU] * (0.5 * h), speed + derivatives[1][DV] * (0.5 * h),
				motion_span, span_elapsed + 0.5 * h, gravity, rolling, aero, true)
			if not error.is_empty():
				return _reject(result, error)
			error = _rk4_derivative(derivatives[3], position + derivatives[2][DP] * h,
				tangent + derivatives[2][DT] * h, up + derivatives[2][DU] * h,
				speed + derivatives[2][DV] * h, motion_span, span_elapsed + h,
				gravity, rolling, aero, true)
			if not error.is_empty():
				return _reject(result, error)

			var next_position: Vector3 = position + h / 6.0 * (derivatives[0][DP]
				+ 2.0 * derivatives[1][DP]
				+ 2.0 * derivatives[2][DP] + derivatives[3][DP])
			var next_tangent: Vector3 = tangent + h / 6.0 * (derivatives[0][DT]
				+ 2.0 * derivatives[1][DT]
				+ 2.0 * derivatives[2][DT] + derivatives[3][DT])
			var next_up: Vector3 = up + h / 6.0 * (derivatives[0][DU]
				+ 2.0 * derivatives[1][DU]
				+ 2.0 * derivatives[2][DU] + derivatives[3][DU])
			var next_speed: float = speed + h / 6.0 * (derivatives[0][DV]
				+ 2.0 * derivatives[1][DV]
				+ 2.0 * derivatives[2][DV] + derivatives[3][DV])
			var distance_step: float = h / 6.0 * (derivatives[0][DS]
				+ 2.0 * derivatives[1][DS] + 2.0 * derivatives[2][DS] + derivatives[3][DS])
			var next_distance := distance + distance_step
			var next_time := time + h
			if not _finite_vector(next_position) or not _finite_vector(next_tangent) \
					or not _finite_vector(next_up) or not is_finite(next_speed) \
					or not is_finite(distance_step) or not is_finite(next_distance) \
					or not is_finite(next_time):
				return _reject(result, "weighted RK state and distance must remain finite")
			if distance_step <= 0.0:
				return _reject(result, "every accepted station interval must advance distance")
			if next_tangent.length_squared() <= FRAME_EPS * FRAME_EPS \
					or next_up.length_squared() <= FRAME_EPS * FRAME_EPS:
				return _reject(result, "weighted RK frame became degenerate")
			position = next_position
			tangent = next_tangent
			up = next_up
			speed = next_speed
			distance = next_distance
			tangent = tangent.normalized()
			up -= tangent * tangent.dot(up)
			if up.length_squared() <= FRAME_EPS * FRAME_EPS:
				return _reject(result, "integrated rider_up became degenerate")
			up = up.normalized()
			span_elapsed += h
			time = next_time
			if speed < 0.0:
				return _reject(result, "station speed became negative")
			if speed <= 0.0 and time > float(initial_state.get("time_s", 0.0)):
				return _reject(result, "station reached nonpositive speed")
			if motion_span.mode == "moving" and speed < MIN_MOVING_SPEED_MPS:
				return _reject(result, "moving speed floor crossed during RK stage")
			_append_native(result, time, distance, position, tangent, up, speed, span_index,
				motion_span, span_elapsed / float(motion_span.duration_s), gravity, rolling, aero)
	result.dense_output = {
		"max_kinematic_defect_mps": _measure_dense_defect(result),
	}
	result.ok = true
	return result


static func _compact_pulse_integral(u: float) -> float:
	return 10.0 * u ** 4 - 12.0 * u ** 5 + 4.0 * u ** 6 \
		- (400.0 / 7.0) * u ** 7 + 150.0 * u ** 8 \
		- (460.0 / 3.0) * u ** 9 + 72.0 * u ** 10 - (144.0 / 11.0) * u ** 11


static func _empty_trajectory() -> Dictionary:
	return {
		"ok": false,
		"errors": PackedStringArray(),
		"time_s": PackedFloat64Array(),
		"distance_m": PackedFloat64Array(),
		"position_m": PackedVector3Array(),
		"tangent": PackedVector3Array(),
		"rider_up": PackedVector3Array(),
		"speed_mps": PackedFloat64Array(),
		"normal_g": PackedFloat64Array(),
		"lateral_g": PackedFloat64Array(),
		"drive_g": PackedFloat64Array(),
		"longitudinal_g": PackedFloat64Array(),
		"roll_rate_rad_s": PackedFloat64Array(),
		"curvature_vector_m_inv": PackedVector3Array(),
		"curvature_m_inv": PackedFloat64Array(),
		"span_index": PackedInt32Array(),
		"dense_output": {},
	}


static func _reject(result: Dictionary, message: String) -> Dictionary:
	result.errors.append(message)
	return result


static func _finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


static func _rk4_derivative(
	out: Array, position: Vector3, tangent: Vector3, up: Vector3, speed: float,
	motion_span: Dictionary, elapsed: float, gravity: Vector3, rolling: float, aero: float,
	is_stage: bool
) -> String:
	if not _finite_vector(position) or not _finite_vector(tangent) or not _finite_vector(up) \
			or not is_finite(speed):
		return "RK stage must remain finite"
	if tangent.length_squared() <= FRAME_EPS * FRAME_EPS or up.length_squared() <= FRAME_EPS * FRAME_EPS:
		return "RK stage frame became degenerate"
	tangent = tangent.normalized()
	up -= tangent * tangent.dot(up)
	if up.length_squared() <= FRAME_EPS * FRAME_EPS:
		return "RK stage frame lost orthogonal rider_up"
	up = up.normalized()
	if motion_span.mode == "moving" and speed < MIN_MOVING_SPEED_MPS:
		return "moving speed floor crossed during RK stage"
	if motion_span.mode == "station" and speed < 0.0:
		return "station RK stage has negative speed"
	if motion_span.mode == "station" and is_stage and speed <= 0.0:
		return "station RK stage has nonpositive speed"
	var u: float = clampf(elapsed / float(motion_span.duration_s), 0.0, 1.0)
	var normal: float = profile_sample(motion_span.normal_g, u).x
	var lateral: float = profile_sample(motion_span.lateral_g, u).x
	var drive: float = profile_sample(motion_span.drive_g, u).x
	var roll: float = profile_sample(motion_span.roll_rate_rad_s, u).x
	var right := tangent.cross(up)
	var transverse := gravity - tangent * gravity.dot(tangent) + G0 * (normal * up + lateral * right)
	if motion_span.mode == "station":
		if transverse.length() > G0 * STATION_TRANSVERSE_TOLERANCE_G:
			return "station transverse acceleration must be zero"
		if absf(roll) > FRAME_EPS:
			return "station roll must be zero"
		out[DT] = Vector3.ZERO
		out[DU] = Vector3.ZERO
	else:
		out[DT] = transverse / speed
		var tangent_rate: Vector3 = out[DT]
		out[DU] = -tangent * tangent_rate.dot(up) + roll * right
	out[DP] = speed * tangent
	out[DV] = gravity.dot(tangent) + G0 * drive - resistance(speed, rolling, aero).x
	out[DS] = speed
	return ""


static func _append_native(
	result: Dictionary, time: float, distance: float, position: Vector3, tangent: Vector3,
	up: Vector3, speed: float, span_index: int, motion_span: Dictionary, u: float,
	gravity: Vector3, rolling: float, aero: float
) -> void:
	result.time_s.append(time)
	result.distance_m.append(distance)
	result.position_m.append(position)
	result.tangent.append(tangent)
	result.rider_up.append(up)
	result.speed_mps.append(speed)
	result.normal_g.append(0.0)
	result.lateral_g.append(0.0)
	result.drive_g.append(0.0)
	result.longitudinal_g.append(0.0)
	result.roll_rate_rad_s.append(0.0)
	result.curvature_vector_m_inv.append(Vector3.ZERO)
	result.curvature_m_inv.append(0.0)
	result.span_index.append(span_index)
	_set_native_controls(result, result.time_s.size() - 1, span_index, motion_span, u,
		tangent, up, speed, gravity, rolling, aero)


static func _set_native_controls(
	result: Dictionary, index: int, span_index: int, motion_span: Dictionary, u: float,
	tangent: Vector3, up: Vector3, speed: float, gravity: Vector3, rolling: float, aero: float
) -> void:
	var normal: float = profile_sample(motion_span.normal_g, u).x
	var lateral: float = profile_sample(motion_span.lateral_g, u).x
	var drive: float = profile_sample(motion_span.drive_g, u).x
	var roll: float = profile_sample(motion_span.roll_rate_rad_s, u).x
	var right := tangent.cross(up)
	var transverse := gravity - tangent * gravity.dot(tangent) + G0 * (normal * up + lateral * right)
	var curvature := Vector3.ZERO if motion_span.mode == "station" else transverse / (speed * speed)
	result.normal_g[index] = normal
	result.lateral_g[index] = lateral
	result.drive_g[index] = drive
	result.longitudinal_g[index] = drive - resistance(speed, rolling, aero).x / G0
	result.roll_rate_rad_s[index] = roll
	result.curvature_vector_m_inv[index] = curvature
	result.curvature_m_inv[index] = curvature.length()
	result.span_index[index] = span_index


static func sample_time(trajectory: Dictionary, time_s: float) -> Dictionary:
	var count: int = trajectory.get("time_s", PackedFloat64Array()).size()
	if count == 0 or not is_finite(time_s):
		return {}
	if time_s <= float(trajectory.time_s[0]):
		return _native_sample(trajectory, 0)
	if time_s >= float(trajectory.time_s[count - 1]):
		return _native_sample(trajectory, count - 1)
	var index := _lower_interval(trajectory.time_s, time_s)
	if time_s == float(trajectory.time_s[index]):
		return _native_sample(trajectory, index)
	if time_s == float(trajectory.time_s[index + 1]):
		return _native_sample(trajectory, index + 1)
	var h: float = trajectory.time_s[index + 1] - trajectory.time_s[index]
	return _dense_sample(trajectory, index, (time_s - trajectory.time_s[index]) / h)


static func sample_distance(trajectory: Dictionary, distance_m: float) -> Dictionary:
	var count: int = trajectory.get("distance_m", PackedFloat64Array()).size()
	if count == 0 or not is_finite(distance_m):
		return {}
	if distance_m <= float(trajectory.distance_m[0]):
		return _native_sample(trajectory, 0)
	if distance_m >= float(trajectory.distance_m[count - 1]):
		return _native_sample(trajectory, count - 1)
	var index := _lower_interval(trajectory.distance_m, distance_m)
	if distance_m == float(trajectory.distance_m[index]):
		return _native_sample(trajectory, index)
	if distance_m == float(trajectory.distance_m[index + 1]):
		return _native_sample(trajectory, index + 1)
	var low := 0.0
	var high := 1.0
	for _iteration in 48:
		var middle := 0.5 * (low + high)
		if _dense_distance(trajectory, index, middle) < distance_m:
			low = middle
		else:
			high = middle
	var sampled := _dense_sample(trajectory, index, 0.5 * (low + high))
	sampled.distance_m = distance_m
	return sampled


static func _native_sample(trajectory: Dictionary, index: int) -> Dictionary:
	return {
		"time_s": trajectory.time_s[index],
		"distance_m": trajectory.distance_m[index],
		"position_m": trajectory.position_m[index],
		"tangent": trajectory.tangent[index],
		"rider_up": trajectory.rider_up[index],
		"speed_mps": trajectory.speed_mps[index],
		"normal_g": trajectory.normal_g[index],
		"lateral_g": trajectory.lateral_g[index],
		"drive_g": trajectory.drive_g[index],
		"longitudinal_g": trajectory.longitudinal_g[index],
		"roll_rate_rad_s": trajectory.roll_rate_rad_s[index],
		"curvature_vector_m_inv": trajectory.curvature_vector_m_inv[index],
		"curvature_m_inv": trajectory.curvature_m_inv[index],
		"span_index": trajectory.span_index[index],
	}


static func _lower_interval(coordinates: PackedFloat64Array, coordinate: float) -> int:
	var low := 0
	var high := coordinates.size() - 1
	while high - low > 1:
		var middle := (low + high) / 2
		if coordinates[middle] <= coordinate:
			low = middle
		else:
			high = middle
	return low


static func _dense_sample(trajectory: Dictionary, index: int, u: float) -> Dictionary:
	var h: float = trajectory.time_s[index + 1] - trajectory.time_s[index]
	var u2 := u * u
	var u3 := u2 * u
	var h00 := 2.0 * u3 - 3.0 * u2 + 1.0
	var h10 := u3 - 2.0 * u2 + u
	var h01 := -2.0 * u3 + 3.0 * u2
	var h11 := u3 - u2
	var velocity_0: Vector3 = trajectory.speed_mps[index] * trajectory.tangent[index]
	var velocity_1: Vector3 = trajectory.speed_mps[index + 1] * trajectory.tangent[index + 1]
	var position: Vector3 = h00 * trajectory.position_m[index] + h10 * h * velocity_0 \
		+ h01 * trajectory.position_m[index + 1] + h11 * h * velocity_1
	var velocity := _dense_velocity(trajectory, index, u)
	var tangent := velocity.normalized()
	var up: Vector3 = trajectory.rider_up[index].lerp(trajectory.rider_up[index + 1], u)
	up -= tangent * tangent.dot(up)
	up = up.normalized()
	return {
		"time_s": lerpf(trajectory.time_s[index], trajectory.time_s[index + 1], u),
		"distance_m": _dense_distance(trajectory, index, u),
		"position_m": position,
		"tangent": tangent,
		"rider_up": up,
		"speed_mps": velocity.length(),
		"normal_g": lerpf(trajectory.normal_g[index], trajectory.normal_g[index + 1], u),
		"lateral_g": lerpf(trajectory.lateral_g[index], trajectory.lateral_g[index + 1], u),
		"drive_g": lerpf(trajectory.drive_g[index], trajectory.drive_g[index + 1], u),
		"longitudinal_g": lerpf(
			trajectory.longitudinal_g[index], trajectory.longitudinal_g[index + 1], u),
		"roll_rate_rad_s": lerpf(
			trajectory.roll_rate_rad_s[index], trajectory.roll_rate_rad_s[index + 1], u),
		"curvature_vector_m_inv": trajectory.curvature_vector_m_inv[index].lerp(
			trajectory.curvature_vector_m_inv[index + 1], u),
		"curvature_m_inv": lerpf(
			trajectory.curvature_m_inv[index], trajectory.curvature_m_inv[index + 1], u),
		"span_index": trajectory.span_index[index],
}


static func _dense_velocity(trajectory: Dictionary, index: int, u: float) -> Vector3:
	var h: float = trajectory.time_s[index + 1] - trajectory.time_s[index]
	var u2 := u * u
	var velocity_0: Vector3 = trajectory.speed_mps[index] * trajectory.tangent[index]
	var velocity_1: Vector3 = trajectory.speed_mps[index + 1] * trajectory.tangent[index + 1]
	return (6.0 * u2 - 6.0 * u) / h * trajectory.position_m[index] \
		+ (3.0 * u2 - 4.0 * u + 1.0) * velocity_0 \
		+ (-6.0 * u2 + 6.0 * u) / h * trajectory.position_m[index + 1] \
		+ (3.0 * u2 - 2.0 * u) * velocity_1


static func _dense_distance(trajectory: Dictionary, index: int, u: float) -> float:
	var h: float = trajectory.time_s[index + 1] - trajectory.time_s[index]
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * trajectory.distance_m[index] \
		+ (u3 - 2.0 * u2 + u) * h * trajectory.speed_mps[index] \
		+ (-2.0 * u3 + 3.0 * u2) * trajectory.distance_m[index + 1] \
		+ (u3 - u2) * h * trajectory.speed_mps[index + 1]


static func _measure_dense_defect(trajectory: Dictionary) -> float:
	var maximum := 0.0
	for index in trajectory.time_s.size() - 1:
		for u in [0.25, 0.5, 0.75]:
			var sample := _dense_sample(trajectory, index, u)
			var derivative := _dense_velocity(trajectory, index, u)
			maximum = maxf(maximum, derivative.distance_to(
				sample.tangent * sample.speed_mps))
	return maximum
