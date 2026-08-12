class_name RideMotion
extends RefCounted

## RED-only interface shell. Task 1 GREEN supplies the physical implementation.

const G0 := 9.80665


static func constant(value: float) -> Dictionary:
	return {"kind": "constant", "value": value}


static func quintic(from: float, to: float) -> Dictionary:
	return {"kind": "quintic", "from": from, "to": to}


static func compact_pulse(amplitude: float) -> Dictionary:
	return {"kind": "compact_pulse", "amplitude": amplitude}


## Returns value, first derivative with respect to normalized profile time, and second derivative.
static func profile_sample(_profile: Dictionary, _u: float) -> Vector3:
	return Vector3.ZERO


## Returns resistance, dq/dv, and d2q/dv2.
static func resistance(_speed_mps: float, _rolling_mps2: float, _aero_per_m: float) -> Vector3:
	return Vector3.ZERO


static func span(
	span_id: String,
	duration_s: float,
	mode: String,
	normal_g: Dictionary,
	lateral_g: Dictionary,
	drive_g: Dictionary,
	roll_rate_rad_s: Dictionary
) -> Dictionary:
	return {
		"span_id": span_id,
		"duration_s": duration_s,
		"mode": mode,
		"normal_g": normal_g,
		"lateral_g": lateral_g,
		"drive_g": drive_g,
		"roll_rate_rad_s": roll_rate_rad_s,
	}


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
