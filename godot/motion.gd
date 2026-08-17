class_name RideMotion
extends RefCounted

const G0 := 9.80665
const MIN_MOVING_SPEED_MPS := 2.0
const FRAME_EPS := 0.000001
const STATION_TRANSVERSE_TOLERANCE_G := 0.00001
const PLATEAU_PULSE_AREA := 2.0 / 3.0
const STEP_FOLD_FRACTION := 0.005
const DENSE_DEFECT_U := [0.25, 0.5, 0.75]

## One RK stage's derivative, handed back through five typed slots instead of a boxed Array.
## Integration is single-threaded and never reentrant — `_rk4_derivative`
## writes the slots and its caller reads them before the next call — so the slots hold no state
## across steps and are not part of any published result.
static var _stage_position_rate: Vector3
static var _stage_tangent_rate: Vector3
static var _stage_rider_up_rate: Vector3
static var _stage_speed_rate: float
static var _stage_distance_rate: float


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


## One span's four control profiles paired with the kind each dispatches on, resolved once for
## the whole span. Both are constant across the span's thousands of samples.
static func _span_controls(motion_span: Dictionary) -> Array:
	var normal: Dictionary = motion_span.normal_g
	var lateral: Dictionary = motion_span.lateral_g
	var drive: Dictionary = motion_span.drive_g
	var roll: Dictionary = motion_span.roll_rate_rad_s
	return [normal, normal.get("kind", ""), lateral, lateral.get("kind", ""),
		drive, drive.get("kind", ""), roll, roll.get("kind", "")]


## The value component of `profile_sample`, bit-identical to its `.x`. The derivative components
## are the only part the integrator and the published channels never read, so the hot path takes
## this door and skips computing them; every surviving term is the same expression in the same
## order, including the Float32 narrowing the Vector3 return imposes.
static func _profile_value(profile: Dictionary, kind: Variant, u: float) -> float:
	match kind:
		"constant":
			return Vector3(profile.value, 0.0, 0.0).x
		"quintic":
			var h := 10.0 * u ** 3 - 15.0 * u ** 4 + 6.0 * u ** 5
			var delta: float = profile.to - profile.from
			return Vector3(profile.from + delta * h, 0.0, 0.0).x
		"compact_pulse":
			var h := 10.0 * u ** 3 - 15.0 * u ** 4 + 6.0 * u ** 5
			var scale: float = 4.0 * profile.amplitude
			return Vector3(scale * h * (1.0 - h), 0.0, 0.0).x
		"balanced_notch":
			var h := 10.0 * u ** 3 - 15.0 * u ** 4 + 6.0 * u ** 5
			var pulse := 4.0 * h * (1.0 - h)
			var balance := 4199.0 / 3100.0
			var scale: float = profile.amplitude
			return Vector3(
				profile.baseline + scale * pulse * (1.0 - balance * pulse), 0.0, 0.0).x
		"plateau_pulse":
			var edge_u := minf(u, 1.0 - u)
			if edge_u >= 1.0 / 3.0:
				return Vector3(profile.amplitude, 0.0, 0.0).x
			var shoulder_u := edge_u * 3.0
			var h := 10.0 * shoulder_u ** 3 - 15.0 * shoulder_u ** 4 \
				+ 6.0 * shoulder_u ** 5
			return Vector3(profile.amplitude * h, 0.0, 0.0).x
		"bank_balance":
			var fraction := _compact_pulse_integral(u) / (100.0 / 231.0)
			var bank_delta: float = profile.to - profile.from
			var bank: float = profile.from + bank_delta * fraction
			return Vector3(1.0 / cos(bank), 0.0, 0.0).x
	assert(false, "invalid motion profile")
	return Vector3.ZERO.x


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

	_append_native(result, time, distance, position, tangent, up, speed, 0,
		_span_controls(spans[0]), spans[0].mode, 0.0, gravity, rolling, aero)

	for span_index in spans.size():
		var motion_span: Dictionary = spans[span_index]
		# Span mode and duration are invariant across the span's steps and are passed down as typed locals.
		var span_mode: String = motion_span.mode
		var span_duration_s := float(motion_span.duration_s)
		var controls := _span_controls(motion_span)
		var span_elapsed := 0.0
		if span_index > 0:
			if span_mode == "moving" and speed < MIN_MOVING_SPEED_MPS:
				return _reject(result, "moving speed floor is 2 m/s")
			_set_native_controls(result, result.time_s.size() - 1, span_index, controls,
				span_mode, 0.0, tangent, up, speed, gravity, rolling, aero)
		while span_elapsed < span_duration_s - 0.000000000001:
			var remaining_s := span_duration_s - span_elapsed
			# Fold a sub-public-resolution remainder into the adjacent RK step. Otherwise
			# the native Float64 node can collapse when the route publishes Float32 time.
			var h := remaining_s if remaining_s <= step_s + maxf(0.000000000001,
				step_s * STEP_FOLD_FRACTION) else step_s
			var error := _rk4_derivative(position, tangent, up, speed,
				controls, span_mode, span_duration_s, span_elapsed, gravity, rolling, aero,
				false)
			if not error.is_empty():
				return _reject(result, error)
			var d0p := _stage_position_rate
			var d0t := _stage_tangent_rate
			var d0u := _stage_rider_up_rate
			var d0v := _stage_speed_rate
			var d0s := _stage_distance_rate
			error = _rk4_derivative(
				position + d0p * (0.5 * h),
				tangent + d0t * (0.5 * h),
				up + d0u * (0.5 * h), speed + d0v * (0.5 * h),
				controls, span_mode, span_duration_s, span_elapsed + 0.5 * h,
				gravity, rolling, aero, true)
			if not error.is_empty():
				return _reject(result, error)
			var d1p := _stage_position_rate
			var d1t := _stage_tangent_rate
			var d1u := _stage_rider_up_rate
			var d1v := _stage_speed_rate
			var d1s := _stage_distance_rate
			error = _rk4_derivative(
				position + d1p * (0.5 * h),
				tangent + d1t * (0.5 * h),
				up + d1u * (0.5 * h), speed + d1v * (0.5 * h),
				controls, span_mode, span_duration_s, span_elapsed + 0.5 * h,
				gravity, rolling, aero, true)
			if not error.is_empty():
				return _reject(result, error)
			var d2p := _stage_position_rate
			var d2t := _stage_tangent_rate
			var d2u := _stage_rider_up_rate
			var d2v := _stage_speed_rate
			var d2s := _stage_distance_rate
			error = _rk4_derivative(position + d2p * h,
				tangent + d2t * h, up + d2u * h,
				speed + d2v * h, controls, span_mode, span_duration_s, span_elapsed + h,
				gravity, rolling, aero, true)
			if not error.is_empty():
				return _reject(result, error)
			var d3p := _stage_position_rate
			var d3t := _stage_tangent_rate
			var d3u := _stage_rider_up_rate
			var d3v := _stage_speed_rate
			var d3s := _stage_distance_rate

			var next_position: Vector3 = position + h / 6.0 * (d0p
				+ 2.0 * d1p
				+ 2.0 * d2p + d3p)
			var next_tangent: Vector3 = tangent + h / 6.0 * (d0t
				+ 2.0 * d1t
				+ 2.0 * d2t + d3t)
			var next_up: Vector3 = up + h / 6.0 * (d0u
				+ 2.0 * d1u
				+ 2.0 * d2u + d3u)
			var next_speed: float = speed + h / 6.0 * (d0v
				+ 2.0 * d1v
				+ 2.0 * d2v + d3v)
			var distance_step: float = h / 6.0 * (d0s
				+ 2.0 * d1s + 2.0 * d2s + d3s)
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
			if span_mode == "moving" and speed < MIN_MOVING_SPEED_MPS:
				return _reject(result, "moving speed floor crossed during RK stage")
			_append_native(result, time, distance, position, tangent, up, speed, span_index,
				controls, span_mode, span_elapsed / span_duration_s, gravity, rolling, aero)
	result.dense_output = _measure_dense_output(result)
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
	position: Vector3, tangent: Vector3, up: Vector3, speed: float,
	controls: Array, mode: String, duration_s: float, elapsed: float,
	gravity: Vector3, rolling: float, aero: float, is_stage: bool
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
	if mode == "moving" and speed < MIN_MOVING_SPEED_MPS:
		return "moving speed floor crossed during RK stage"
	if mode == "station" and speed < 0.0:
		return "station RK stage has negative speed"
	if mode == "station" and is_stage and speed <= 0.0:
		return "station RK stage has nonpositive speed"
	var u: float = clampf(elapsed / duration_s, 0.0, 1.0)
	var normal := _profile_value(controls[0], controls[1], u)
	var lateral := _profile_value(controls[2], controls[3], u)
	var drive := _profile_value(controls[4], controls[5], u)
	var roll := _profile_value(controls[6], controls[7], u)
	var right := tangent.cross(up)
	var transverse := gravity - tangent * gravity.dot(tangent) + G0 * (normal * up + lateral * right)
	if mode == "station":
		if transverse.length() > G0 * STATION_TRANSVERSE_TOLERANCE_G:
			return "station transverse acceleration must be zero"
		if absf(roll) > FRAME_EPS:
			return "station roll must be zero"
		_stage_tangent_rate = Vector3.ZERO
		_stage_rider_up_rate = Vector3.ZERO
	else:
		_stage_tangent_rate = transverse / speed
		var tangent_rate := _stage_tangent_rate
		_stage_rider_up_rate = -tangent * tangent_rate.dot(up) + roll * right
	_stage_position_rate = speed * tangent
	_stage_speed_rate = gravity.dot(tangent) + G0 * drive \
		- Vector3(rolling + aero * speed * speed, 0.0, 0.0).x
	_stage_distance_rate = speed
	return ""


static func _append_native(
	result: Dictionary, time: float, distance: float, position: Vector3, tangent: Vector3,
	up: Vector3, speed: float, span_index: int, controls: Array, mode: String, u: float,
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
	_set_native_controls(result, result.time_s.size() - 1, span_index, controls, mode, u,
		tangent, up, speed, gravity, rolling, aero)


static func _set_native_controls(
	result: Dictionary, index: int, span_index: int, controls: Array, mode: String, u: float,
	tangent: Vector3, up: Vector3, speed: float, gravity: Vector3, rolling: float, aero: float
) -> void:
	var normal := _profile_value(controls[0], controls[1], u)
	var lateral := _profile_value(controls[2], controls[3], u)
	var drive := _profile_value(controls[4], controls[5], u)
	var roll := _profile_value(controls[6], controls[7], u)
	var right := tangent.cross(up)
	var transverse := gravity - tangent * gravity.dot(tangent) + G0 * (normal * up + lateral * right)
	var curvature := Vector3.ZERO if mode == "station" else transverse / (speed * speed)
	result.normal_g[index] = normal
	result.lateral_g[index] = lateral
	result.drive_g[index] = drive
	result.longitudinal_g[index] = drive \
		- Vector3(rolling + aero * speed * speed, 0.0, 0.0).x / G0
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
	return _dense_velocity_on(
		trajectory.time_s[index + 1] - trajectory.time_s[index],
		trajectory.position_m[index],
		trajectory.speed_mps[index] * trajectory.tangent[index],
		trajectory.position_m[index + 1],
		trajectory.speed_mps[index + 1] * trajectory.tangent[index + 1], u)


## The Hermite velocity of one interval, taking the interval rather than looking it up.
static func _dense_velocity_on(h: float, position_0: Vector3, velocity_0: Vector3,
	position_1: Vector3, velocity_1: Vector3, u: float
) -> Vector3:
	var u2 := u * u
	return (6.0 * u2 - 6.0 * u) / h * position_0 \
		+ (3.0 * u2 - 4.0 * u + 1.0) * velocity_0 \
		+ (-6.0 * u2 + 6.0 * u) / h * position_1 \
		+ (3.0 * u2 - 2.0 * u) * velocity_1


static func _dense_distance(trajectory: Dictionary, index: int, u: float) -> float:
	var h: float = trajectory.time_s[index + 1] - trajectory.time_s[index]
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * trajectory.distance_m[index] \
		+ (u3 - 2.0 * u2 + u) * h * trajectory.speed_mps[index] \
		+ (-2.0 * u3 + 3.0 * u2) * trajectory.distance_m[index + 1] \
		+ (u3 - u2) * h * trajectory.speed_mps[index + 1]


## Analytic d(distance)/dt of the cubic Hermite distance interpolant. Kept separate from
## `_dense_distance`: the consistency audit compares this derivative with an independently
## interpolated published speed channel rather than reading back a value derived from itself.
static func _dense_distance_rate_on(
	interval_s: float, distance_0: float, speed_0: float,
	distance_1: float, speed_1: float, u: float
) -> float:
	var u2 := u * u
	return (6.0 * u2 - 6.0 * u) / interval_s * distance_0 \
		+ (3.0 * u2 - 4.0 * u + 1.0) * speed_0 \
		+ (-6.0 * u2 + 6.0 * u) / interval_s * distance_1 \
		+ (3.0 * u2 - 2.0 * u) * speed_1


## Independent dense-output consistency measurements. The previous implementation compared one
## Hermite velocity with its own normalized direction times its own length, which is an identity
## and could not fail. These residuals compare the Hermite position/distance derivatives with a
## separately interpolated native speed/tangent channel:
##
## - position_velocity: vector d(position)/dt versus interpolated speed * tangent;
## - distance_speed: scalar d(distance)/dt versus interpolated speed;
## - velocity_channel: |d(position)/dt| versus interpolated speed.
##
## The compatibility field is the maximum real residual, not a fourth self-comparison.
static func _measure_dense_output(trajectory: Dictionary) -> Dictionary:
	var times: PackedFloat64Array = trajectory.time_s
	var distances: PackedFloat64Array = trajectory.distance_m
	var speeds: PackedFloat64Array = trajectory.speed_mps
	var tangents: PackedVector3Array = trajectory.tangent
	var positions: PackedVector3Array = trajectory.position_m
	var maximum_position_velocity := 0.0
	var maximum_distance_speed := 0.0
	var maximum_velocity_channel := 0.0
	for index in times.size() - 1:
		var interval_s: float = times[index + 1] - times[index]
		var velocity_0: Vector3 = speeds[index] * tangents[index]
		var velocity_1: Vector3 = speeds[index + 1] * tangents[index + 1]
		for u in DENSE_DEFECT_U:
			var dense_velocity := _dense_velocity_on(
				interval_s, positions[index], velocity_0,
				positions[index + 1], velocity_1, u)
			var channel_speed := lerpf(float(speeds[index]), float(speeds[index + 1]), u)
			# Native nodes are at most one integration step apart, so normalized linear
			# interpolation is the stable independent channel model. It does not use the dense
			# position derivative it is being compared against.
			var channel_tangent: Vector3 = tangents[index].lerp(tangents[index + 1], u)
			if channel_tangent.length_squared() <= FRAME_EPS * FRAME_EPS:
				channel_tangent = tangents[index]
			channel_tangent = channel_tangent.normalized()
			var channel_velocity := channel_speed * channel_tangent
			var distance_rate := _dense_distance_rate_on(
				interval_s, float(distances[index]), float(speeds[index]),
				float(distances[index + 1]), float(speeds[index + 1]), u)
			maximum_position_velocity = maxf(maximum_position_velocity,
				dense_velocity.distance_to(channel_velocity))
			maximum_distance_speed = maxf(maximum_distance_speed,
				absf(distance_rate - channel_speed))
			maximum_velocity_channel = maxf(maximum_velocity_channel,
				absf(dense_velocity.length() - channel_speed))
	var maximum := maxf(maximum_position_velocity,
		maxf(maximum_distance_speed, maximum_velocity_channel))
	return {
		"max_kinematic_defect_mps": maximum,
		"max_position_velocity_defect_mps": maximum_position_velocity,
		"max_distance_speed_defect_mps": maximum_distance_speed,
		"max_velocity_channel_defect_mps": maximum_velocity_channel,
	}


## Compatibility seam for focused tests and downstream diagnostics that called the old helper.
## It now returns the maximum independent residual published by `_measure_dense_output`.
static func _measure_dense_defect(trajectory: Dictionary) -> float:
	return float(_measure_dense_output(trajectory).max_kinematic_defect_mps)
