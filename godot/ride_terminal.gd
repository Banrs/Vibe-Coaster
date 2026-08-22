class_name RideTerminal
extends RefCounted

## Neutral capture and the one-dimensional spatial brake that close the station frame (design
## 2026-08-22, "Capture and brakes"). Capture carries no steering authority at all - it is a
## zero-curvature, zero-twist, zero-drive spatial span, so the return's own element contracts must
## already deliver a near-neutral frame before this stage starts. The brake sheds speed over an
## exactly-declared distance with one solved scalar (peak negative drive_g), found by monotone
## bounded bisection; its held deceleration is a friction/hydraulic profile, not an eddy-current
## brake, so it does not decay with speed the way a real eddy-current unit's does. The physical
## 2->1 m/s station creep that follows is the same physics `RideReturnSolve` uses today, reused
## rather than reimplemented.

const Motion := preload("res://motion.gd")
const RideProgram := preload("res://ride_program.gd")
const RideReturnSolve := preload("res://ride_return_solve.gd")

const ENTRY_SPEED_BAND_MPS := Vector2(70.0, 80.0)
const BRAKE_PEAK_BOUNDS_G := Vector2(0.0, 3.6)
const BRAKE_SHOULDER_LENGTH_M := 20.0
const MOVING_BOUNDARY_SPEED_MPS := 2.0
const STATION_CREEP_TARGET_MPS := 1.0
const MAX_BRAKE_EVALUATIONS := 32
const BRAKE_SPEED_TOLERANCE_MPS := 0.00005


static func build(start: Dictionary, layout: Dictionary, settings: Dictionary) -> Dictionary:
	var validated := _validate(start, layout)
	if not validated.ok:
		return validated
	var corridor: Dictionary = layout.reserved_corridor
	var capture_length: float = float(corridor.capture_length_m)
	var capture_span := Motion.spatial_span("terminal/capture", capture_length,
		Motion.constant(0.0), Motion.constant(0.0), Motion.constant(0.0), Motion.constant(0.0))
	var creep_distance := RideReturnSolve._coast_distance(
		MOVING_BOUNDARY_SPEED_MPS, STATION_CREEP_TARGET_MPS)
	var station_duration := RideReturnSolve._coast_time(
		MOVING_BOUNDARY_SPEED_MPS, STATION_CREEP_TARGET_MPS)
	var moving_length: float = float(corridor.brake_length_m) - creep_distance
	if not is_finite(moving_length) or moving_length <= 2.0 * BRAKE_SHOULDER_LENGTH_M:
		return _failure("brake corridor cannot hold its shoulders and station creep",
			{"brake_length_m": corridor.brake_length_m, "station_creep_distance_m": creep_distance})
	var target_distance: float = float(start.distance_m) + capture_length + moving_length
	var evaluation_count := [0]
	var evaluate := func(peak_g: float) -> Dictionary:
		evaluation_count[0] += 1
		var brake_spans := _brake_spans(peak_g, BRAKE_SHOULDER_LENGTH_M,
			moving_length - 2.0 * BRAKE_SHOULDER_LENGTH_M)
		return {"route": Motion.integrate(start, [capture_span] + brake_spans, settings),
			"spans": brake_spans}
	var solved := _solve_peak(evaluate, target_distance, evaluation_count)
	if not solved.ok:
		return solved
	var creep_span := Motion.span("terminal/station-creep", station_duration, "station",
		Motion.constant(1.0), Motion.constant(0.0), Motion.constant(0.0), Motion.constant(0.0))
	var spans: Array = [capture_span] + solved.spans + [creep_span]
	var trajectory := Motion.integrate(start, spans, settings)
	if not trajectory.get("ok", false):
		return _failure("terminal trajectory failed its final integration",
			{"brake_peak_g": solved.peak_g})
	var report := {
		"capture_steering_controls": 0,
		"capture_length_m": capture_length,
		"brake_peak_g": solved.peak_g,
		"brake_peak_bound_g": BRAKE_PEAK_BOUNDS_G.y,
		"moving_length_m": moving_length,
		"moving_boundary_speed_mps": solved.moving_boundary_speed_mps,
		"station_creep_distance_m": creep_distance,
		"station_creep_duration_s": station_duration,
		"station_creep_target_mps": STATION_CREEP_TARGET_MPS,
		"unique_evaluations": evaluation_count[0],
		"max_unique_evaluations": MAX_BRAKE_EVALUATIONS,
		"positive_drive_allowed": false,
	}
	return {"ok": true, "errors": PackedStringArray(), "spans": spans,
		"trajectory": trajectory, "report": report,
		"margins": _margins(start, layout, trajectory, solved.peak_g)}


static func _validate(start: Dictionary, layout: Dictionary) -> Dictionary:
	for key in ["position_m", "tangent", "rider_up", "speed_mps", "distance_m", "time_s"]:
		if not start.has(key):
			return _failure("terminal start is missing %s" % key)
	if not start.position_m is Vector3 or not start.position_m.is_finite() \
			or not start.tangent is Vector3 or not start.tangent.is_finite() \
			or not start.rider_up is Vector3 or not start.rider_up.is_finite() \
			or not is_finite(float(start.speed_mps)) or float(start.speed_mps) < 0.0 \
			or not is_finite(float(start.distance_m)) or not is_finite(float(start.time_s)):
		return _failure("terminal start must be finite")
	if start.tangent.length_squared() <= 0.000001 or start.rider_up.length_squared() <= 0.000001:
		return _failure("terminal start frame is degenerate")
	for key in ["station_position_m", "station_tangent", "station_up", "reserved_corridor"]:
		if not layout.has(key):
			return _failure("terminal layout is missing %s" % key)
	if not layout.station_position_m is Vector3 or not layout.station_position_m.is_finite() \
			or not layout.station_tangent is Vector3 or not layout.station_tangent.is_finite() \
			or not layout.station_up is Vector3 or not layout.station_up.is_finite() \
			or layout.station_tangent.length_squared() <= 0.000001 \
			or layout.station_up.length_squared() <= 0.000001:
		return _failure("terminal layout frame is invalid")
	var corridor_value: Variant = layout.reserved_corridor
	if not corridor_value is Dictionary:
		return _failure("reserved_corridor must be a Dictionary")
	var corridor: Dictionary = corridor_value
	for field in ["capture_length_m", "brake_length_m", "entry_speed_mps"]:
		if not corridor.has(field):
			return _failure("reserved_corridor is missing %s" % field)
	if not is_finite(float(corridor.capture_length_m)) or float(corridor.capture_length_m) <= 0.0 \
			or not is_finite(float(corridor.brake_length_m)) or float(corridor.brake_length_m) <= 0.0:
		return _failure("reserved_corridor lengths must be finite and positive")
	var entry_band_value: Variant = corridor.entry_speed_mps
	if not entry_band_value is Vector2 or not entry_band_value.is_finite() \
			or entry_band_value.x <= 0.0 or entry_band_value.y < entry_band_value.x:
		return _failure("reserved_corridor entry speed band is invalid")
	var entry_band: Vector2 = entry_band_value
	if float(start.speed_mps) < entry_band.x or float(start.speed_mps) > entry_band.y:
		return _failure("terminal entry speed is outside its declared band",
			{"entry_speed_mps": start.speed_mps, "entry_speed_band_mps": entry_band})
	return {"ok": true}


## Monotone bounded bisection on the single solved scalar, peak brake g. `F(peak)` is the moving-
## boundary speed residual when the candidate reaches the declared distance, and the stopping
## shortfall (span left unused, signed negative so the residual stays monotone through the root)
## when the moving floor stops integration first - the design's "not an error case to abort on".
static func _solve_peak(evaluate: Callable, target_distance: float,
		evaluation_count: Array) -> Dictionary:
	var lo := BRAKE_PEAK_BOUNDS_G.x
	var hi := BRAKE_PEAK_BOUNDS_G.y
	var lo_observed: Dictionary = evaluate.call(lo)
	var hi_observed: Dictionary = evaluate.call(hi)
	var lo_residual := _residual(lo_observed.route, target_distance)
	var hi_residual := _residual(hi_observed.route, target_distance)
	if lo_residual < 0.0 or hi_residual > 0.0:
		return _failure("brake bracket is not monotone at its declared bounds",
			{"lo_residual": lo_residual, "hi_residual": hi_residual})
	var best_peak := lo
	var best := lo_observed
	var best_residual := lo_residual
	while evaluation_count[0] < MAX_BRAKE_EVALUATIONS and absf(best_residual) > BRAKE_SPEED_TOLERANCE_MPS \
			and hi > lo:
		var mid := 0.5 * (lo + hi)
		var observed: Dictionary = evaluate.call(mid)
		var residual := _residual(observed.route, target_distance)
		if residual >= 0.0:
			lo = mid
			best_peak = mid
			best = observed
			best_residual = residual
		else:
			hi = mid
	if not best.route.get("ok", false):
		return _failure("brake solve did not reach a completing candidate",
			{"unique_evaluations": evaluation_count[0]})
	return {"ok": true, "peak_g": best_peak, "spans": best.spans,
		"moving_boundary_speed_mps": best.route.speed_mps[-1]}


static func _residual(route: Dictionary, target_distance: float) -> float:
	if route.get("ok", false):
		return route.speed_mps[-1] - MOVING_BOUNDARY_SPEED_MPS
	var distances: PackedFloat64Array = route.get("distance_m", PackedFloat64Array())
	var achieved: float = distances[-1] if distances.size() > 0 else -INF
	return achieved - target_distance


## Held friction/hydraulic deceleration: quintic engage/release shoulders around a constant peak.
## Deliberately not an eddy-current profile - eddy-current retardation decays with speed, this
## profile's held peak does not, which is why its 2.0-2.6 g typical peak sits above measured
## eddy-current practice (1.0-1.5 g) while staying inside the 3.6 g bound.
static func _brake_spans(peak_g: float, shoulder_m: float, hold_m: float) -> Array:
	return [
		Motion.spatial_span("terminal/brake-engage", shoulder_m,
			Motion.constant(0.0), Motion.constant(0.0),
			Motion.quintic(0.0, -peak_g), Motion.constant(0.0)),
		Motion.spatial_span("terminal/brake-hold", hold_m,
			Motion.constant(0.0), Motion.constant(0.0),
			Motion.constant(-peak_g), Motion.constant(0.0)),
		Motion.spatial_span("terminal/brake-release", shoulder_m,
			Motion.constant(0.0), Motion.constant(0.0),
			Motion.quintic(-peak_g, 0.0), Motion.constant(0.0)),
	]


static func _margins(start: Dictionary, layout: Dictionary, trajectory: Dictionary,
		peak_g: float) -> Dictionary:
	var corridor: Dictionary = layout.reserved_corridor
	var entry_band: Vector2 = corridor.entry_speed_mps
	var entry_speed := float(start.speed_mps)
	var final_position: Vector3 = trajectory.position_m[-1]
	var final_tangent: Vector3 = trajectory.tangent[-1]
	var final_up: Vector3 = trajectory.rider_up[-1]
	return {
		"entry_speed_low_mps": entry_speed - entry_band.x,
		"entry_speed_high_mps": entry_band.y - entry_speed,
		"brake_peak_g": BRAKE_PEAK_BOUNDS_G.y - peak_g,
		"station_position_error_m": final_position.distance_to(layout.station_position_m),
		"station_tangent_error": final_tangent.distance_to(layout.station_tangent.normalized()),
		"station_up_error": final_up.distance_to(layout.station_up.normalized()),
	}


static func _failure(message: String, diagnostics: Dictionary = {}) -> Dictionary:
	var failure := RideProgram._failure(message, "terminal", diagnostics)
	failure["spans"] = []
	failure["trajectory"] = {}
	failure["report"] = {}
	failure["margins"] = {}
	return failure
