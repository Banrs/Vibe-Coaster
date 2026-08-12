class_name RideMotion
extends RefCounted

## RED-only interface shell. Task 1 GREEN supplies the physical implementation.

const G0 := 9.80665


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
			var scale: float = 16.0 * profile.amplitude
			return Vector3(
				scale * h * (1.0 - h),
				scale * dh * (1.0 - 2.0 * h),
				scale * (d2h * (1.0 - 2.0 * h) - 2.0 * dh * dh)
			)
	assert(false, "invalid motion profile")
	return Vector3.ZERO


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
			"compact_pulse": assert(profile.has("amplitude"), "invalid compact pulse profile")
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
	_initial_state: Dictionary, _spans: Array, _settings: Dictionary = {}
) -> Dictionary:
	return {
		"ok": false,
		"errors": PackedStringArray(["motion kernel not implemented"]),
		"time_s": PackedFloat64Array(),
		"distance_m": PackedFloat64Array(),
		"position_m": PackedVector3Array(),
		"tangent": PackedVector3Array(),
		"rider_up": PackedVector3Array(),
		"speed_mps": PackedFloat64Array(),
		"longitudinal_g": PackedFloat64Array(),
		"span_index": PackedInt32Array(),
		"dense_output": {},
	}


static func sample_time(_trajectory: Dictionary, _time_s: float) -> Dictionary:
	return {}


static func sample_distance(_trajectory: Dictionary, _distance_m: float) -> Dictionary:
	return {}
