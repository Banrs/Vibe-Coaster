class_name RideElements
extends RefCounted

## Integrator core for the generator rewrite. The rider frame is carried explicitly through every
## step instead of being rebuilt from a level-up plus an authored bank angle, so inversions and
## vertical track are representable. FVD sections author normal/lateral g and a roll rate; grade
## sections author pitch and a solved drive; the closure is the C4 bezier return to the station.

const G0 := 9.80665
const GRAVITY := Vector3.DOWN * G0
const SAMPLE_SPACING := 1.5
const DRAG_FACTOR := 0.000064
const ROLLING_FACTOR := 0.0015
const ROW_OFFSETS := [0.0, 2.15, 4.30, 6.45, 8.60, 10.75, 12.90]
const ROLL_SHAPE := [
	Vector2(0, 0), Vector2(0.18, 1), Vector2(0.32, 0),
	Vector2(0.68, 0), Vector2(0.82, -1), Vector2(1, 0),
]
const TURN_KEYS := [0.0, 0.08, 0.16, 0.24, 0.32, 0.68, 0.76, 0.84, 0.92, 1.0]


## ------------------------------------------------------------------------ section constructors


static func fvd_section(
	name: String,
	length: float,
	normal: Array,
	lateral: Array,
	roll_rate: Array,
	element: Dictionary = {},
	lsm: int = 0
) -> Dictionary:
	return {
		"name": name,
		"kind": "FVD",
		"length": length,
		"normal": PackedVector2Array(normal),
		"lateral": PackedVector2Array(lateral),
		"roll_rate": PackedVector2Array(roll_rate),
		"lsm": lsm,
		"element": element,
	}


static func grade_section(
	name: String,
	length: float,
	pitch: Array,
	exit_speed_target: float,
	lsm: int = 0,
	minimum_speed: float = 4.0,
	element: Dictionary = {}
) -> Dictionary:
	return {
		"name": name,
		"kind": "GRADE",
		"length": length,
		"pitch": PackedVector2Array(pitch),
		"exit_speed_target": exit_speed_target,
		"lsm": lsm,
		"minimum_speed": minimum_speed,
		"element": element,
	}


## ------------------------------------------------------------------------------- route buffers


static func new_route() -> Dictionary:
	return {
		"positions": PackedVector3Array(),
		"tangents": PackedVector3Array(),
		"ups": PackedVector3Array(),
		"rights": PackedVector3Array(),
		"curvatures": PackedVector3Array(),
		"banks": PackedFloat32Array(),
		"speeds": PackedFloat32Array(),
		"normal_g": PackedFloat32Array(),
		"lateral_g": PackedFloat32Array(),
		"longitudinal_g": PackedFloat32Array(),
		"roll_rates": PackedFloat32Array(),
		"distances": PackedFloat32Array(),
		"times": PackedFloat32Array(),
		"section_indices": PackedInt32Array(),
		"lsm_ids": PackedInt32Array(),
	}


## Bank is HUD-only here: the frame is authoritative, so the angle is read back out of it.
static func append_state(
	route: Dictionary,
	state: Dictionary,
	section: int,
	normal: float,
	lateral: float,
	longitudinal: float,
	lsm: int,
	curvature: Vector3
) -> void:
	var tangent: Vector3 = state.tangent
	var up: Vector3 = (state.up - tangent * tangent.dot(state.up)).normalized()
	var right: Vector3 = tangent.cross(up).normalized()
	up = right.cross(tangent).normalized()
	var bank: float = 0.0 if route.banks.is_empty() else route.banks[-1]
	if absf(tangent.y) < 0.99:
		bank = rad_to_deg(atan2(-right.y, up.y))
	route.positions.append(state.position)
	route.tangents.append(tangent)
	route.ups.append(up)
	route.rights.append(right)
	route.curvatures.append(curvature)
	route.banks.append(bank)
	route.speeds.append(state.speed)
	route.normal_g.append(normal)
	route.lateral_g.append(lateral)
	route.longitudinal_g.append(longitudinal)
	route.roll_rates.append(0.0)
	route.distances.append(state.distance)
	route.times.append(state.time)
	route.section_indices.append(section)
	route.lsm_ids.append(lsm)


static func measure_roll_rates(route: Dictionary) -> void:
	route.roll_rates[0] = 0.0
	for i in range(1, route.positions.size()):
		var previous: Vector3 = _transport_up(route.ups[i - 1], route.tangents[i - 1], route.tangents[i])
		var angle := atan2(route.tangents[i].dot(previous.cross(route.ups[i])), previous.dot(route.ups[i]))
		var dt: float = route.times[i] - route.times[i - 1]
		route.roll_rates[i] = rad_to_deg(angle) / maxf(dt, 0.0001)


## ----------------------------------------------------------------------------------- top level


static func build_route(
	sections: Array, station_position: Vector3, station_tangent: Vector3, station_speed: float
) -> Dictionary:
	var route := new_route()
	var tangent := station_tangent.normalized()
	var state := {
		"position": station_position,
		"tangent": tangent,
		"up": _level_up(tangent),
		"speed": station_speed,
		"distance": 0.0,
		"time": 0.0,
	}
	append_state(route, state, 0, 1.0, 0.0, 0.0, 0, Vector3.ZERO)
	for index in sections.size():
		var section: Dictionary = sections[index]
		section["start_index"] = route.positions.size() - 1
		section["start_distance"] = state.distance
		section["start_time"] = state.time
		section["start_height"] = state.position.y
		section["entry_speed"] = state.speed
		if section.kind == "FVD":
			integrate_fvd(route, state, section, index)
		else:
			integrate_grade(route, state, section, index)
		section["end_index"] = route.positions.size() - 1
		section["end_distance"] = state.distance
		section["end_time"] = state.time
		section["end_height"] = state.position.y
		section["exit_speed"] = state.speed
		sections[index] = section
	append_closure(route, state, sections, station_position, station_tangent.normalized(), station_speed)
	measure_roll_rates(route)
	route["sections"] = sections
	route["length"] = state.distance
	route["duration"] = state.time
	route["bounds"] = _bounds(route.positions)
	return route


## ------------------------------------------------------------------------------ force-vector design


static func integrate_fvd(
	route: Dictionary, state: Dictionary, section: Dictionary, section_index: int
) -> void:
	var steps := ceili(section.length / SAMPLE_SPACING)
	var step: float = section.length / steps
	for i in steps:
		var u0 := float(i) / steps
		var u1 := float(i + 1) / steps
		var um := (u0 + u1) * 0.5
		var d0 := _fvd_derivative(route, state, section, u0)
		var half := _rotate_frame(state.tangent, state.up, d0.curvature, step * 0.5)
		var middle_speed: float = sqrt(maxf(0.04, state.speed * state.speed + d0.energy * step))
		var half_dt: float = step * 0.5 / maxf(middle_speed, 1.0)
		var middle := {
			"position": state.position + state.tangent * step * 0.5,
			"tangent": half.tangent,
			"up": _roll_frame(half.tangent, half.up, d0.roll_rate, half_dt),
			"speed": middle_speed,
			"distance": state.distance + step * 0.5,
		}
		var dm := _fvd_derivative(route, middle, section, um)
		var dt: float = step / maxf(middle_speed, 1.0)
		var frame := _rotate_frame(state.tangent, state.up, dm.curvature, step)
		state.position += middle.tangent * step
		state.tangent = frame.tangent
		state.up = _roll_frame(frame.tangent, frame.up, dm.roll_rate, dt)
		state.speed = sqrt(maxf(0.04, state.speed * state.speed + 2.0 * dm.energy * step))
		state.distance += step
		state.time += dt
		var sample := _fvd_derivative(route, state, section, u1)
		append_state(
			route,
			state,
			section_index,
			sample.normal,
			sample.lateral,
			sample.longitudinal,
			section.lsm,
			sample.curvature
		)


static func _fvd_derivative(
	route: Dictionary, state: Dictionary, section: Dictionary, u: float
) -> Dictionary:
	var normal: float = _profile(section.normal, u).x
	var lateral: float = _profile(section.lateral, u).x
	var tangent: Vector3 = state.tangent
	var up: Vector3 = state.up
	var right: Vector3 = tangent.cross(up).normalized()
	var proper: Vector3 = (up * normal + right * lateral) * G0
	var gravity_across: Vector3 = GRAVITY - tangent * GRAVITY.dot(tangent)
	var speed2: float = maxf(state.speed * state.speed, 0.04)
	var drag: float = DRAG_FACTOR * speed2 + ROLLING_FACTOR * absf(proper.dot(up))
	var energy: float = _mean_train_gravity(route, state.distance, tangent) - drag
	return {
		"curvature": (proper + gravity_across) / speed2,
		"energy": energy,
		"roll_rate": _profile(section.roll_rate, u).x,
		"normal": normal,
		"lateral": lateral,
		"longitudinal": (energy - GRAVITY.dot(tangent)) / G0,
	}


## Rotate the frame by the rotation the curvature applies to the tangent over ds — the same proper
## rotation is applied to the up vector, which is what keeps inversions representable.
static func _rotate_frame(tangent: Vector3, up: Vector3, curvature: Vector3, ds: float) -> Dictionary:
	var axis := tangent.cross(curvature)
	if axis.length_squared() < 1e-18:
		return {"tangent": tangent, "up": up}
	var angle := curvature.length() * ds
	axis = axis.normalized()
	return {"tangent": tangent.rotated(axis, angle), "up": up.rotated(axis, angle)}


static func _roll_frame(tangent: Vector3, up: Vector3, roll_rate: float, dt: float) -> Vector3:
	var rolled: Vector3 = up.rotated(tangent, deg_to_rad(roll_rate) * dt)
	return (rolled - tangent * tangent.dot(rolled)).normalized()


## ------------------------------------------------------------------------------ authored grade


static func integrate_grade(
	route: Dictionary, state: Dictionary, section: Dictionary, section_index: int
) -> void:
	var steps := ceili(section.length / SAMPLE_SPACING)
	var step: float = section.length / steps
	var heading: Vector2 = Vector2(state.tangent.x, state.tangent.z).normalized()
	var entry_speed: float = state.speed
	var mean_gravity := 0.0
	for i in 64:
		var pitch := deg_to_rad(_profile_septic(section.pitch, (i + 0.5) / 64.0).x)
		mean_gravity += GRAVITY.dot(Vector3(heading.x * cos(pitch), sin(pitch), heading.y * cos(pitch))) / 64.0
	var average_speed2: float = 0.5 * (entry_speed * entry_speed + section.exit_speed_target * section.exit_speed_target)
	var average_drag: float = DRAG_FACTOR * average_speed2 + ROLLING_FACTOR * G0
	var delivered: float = 1.0 - minf(60.0 / section.length, 0.45)
	var drive: float = (0.5 * (section.exit_speed_target * section.exit_speed_target - entry_speed * entry_speed) - mean_gravity * section.length + average_drag * section.length) / (section.length * delivered)
	for i in steps:
		var u1 := float(i + 1) / steps
		var um := (i + 0.5) / steps
		var pitch_mid_eval := _profile_septic(section.pitch, um)
		var pitch_end_eval := _profile_septic(section.pitch, u1)
		var pitch_mid: float = deg_to_rad(pitch_mid_eval.x)
		var pitch_end: float = deg_to_rad(pitch_end_eval.x)
		var tangent_mid: Vector3 = Vector3(heading.x * cos(pitch_mid), sin(pitch_mid), heading.y * cos(pitch_mid)).normalized()
		var next_tangent: Vector3 = Vector3(heading.x * cos(pitch_end), sin(pitch_end), heading.y * cos(pitch_end)).normalized()
		var lift: Vector3 = (Vector3.UP - tangent_mid * Vector3.UP.dot(tangent_mid)).normalized()
		var curvature: Vector3 = lift * deg_to_rad(pitch_mid_eval.y) / section.length
		var gravity_along := _mean_train_gravity(route, state.distance + step * 0.5, tangent_mid)
		var proper_mid: Vector3 = curvature * state.speed * state.speed - (GRAVITY - tangent_mid * gravity_along)
		var drag: float = DRAG_FACTOR * state.speed * state.speed + ROLLING_FACTOR * absf(proper_mid.dot(lift))
		var propulsion: float = drive * _engagement(um, section.length)
		var speed_end: float = sqrt(maxf(0.04, state.speed * state.speed + 2.0 * (gravity_along + propulsion - drag) * step))
		var average_speed: float = 0.5 * (state.speed + speed_end)
		var previous_tangent: Vector3 = state.tangent
		state.position += tangent_mid * step
		state.tangent = next_tangent
		state.up = _transport_up(state.up, previous_tangent, next_tangent)
		state.speed = speed_end
		state.distance += step
		state.time += step / maxf(average_speed, 1.0)
		var end_lift: Vector3 = (Vector3.UP - next_tangent * Vector3.UP.dot(next_tangent)).normalized()
		var end_curvature: Vector3 = end_lift * deg_to_rad(pitch_end_eval.y) / section.length
		var gravity_across: Vector3 = GRAVITY - next_tangent * GRAVITY.dot(next_tangent)
		var proper: Vector3 = end_curvature * speed_end * speed_end - gravity_across
		var end_drag: float = DRAG_FACTOR * speed_end * speed_end + ROLLING_FACTOR * absf(proper.dot(end_lift))
		var end_gravity := _mean_train_gravity(route, state.distance, next_tangent)
		var longitudinal: float = (end_gravity - GRAVITY.dot(next_tangent) + drive * _engagement(u1, section.length) - end_drag) / G0
		var up: Vector3 = state.up
		var right: Vector3 = next_tangent.cross(up).normalized()
		append_state(
			route,
			state,
			section_index,
			proper.dot(up) / G0,
			proper.dot(right) / G0,
			longitudinal,
			section.lsm,
			end_curvature
		)


static func _engagement(u: float, length: float) -> float:
	var fraction := minf(60.0 / length, 0.45)
	return _smooth5(clampf(u / fraction, 0.0, 1.0)) * _smooth5(clampf((1.0 - u) / fraction, 0.0, 1.0))


## ---------------------------------------------------------------------------- station closure


static func append_closure(
	route: Dictionary,
	state: Dictionary,
	sections: Array,
	station_position: Vector3,
	station_tangent: Vector3,
	station_speed: float
) -> void:
	var start: Vector3 = state.position
	var gap := start.distance_to(station_position)
	var handle := clampf(gap * 0.72, 45.0, 350.0)
	var controls := PackedVector3Array()
	for i in 5:
		controls.append(start + state.tangent * handle * i / 9.0)
	for i in range(4, -1, -1):
		controls.append(station_position - station_tangent * handle * i / 9.0)
	var estimate := 0.0
	var previous := start
	for i in range(1, 101):
		var point := _bezier9(controls, i / 100.0)
		estimate += previous.distance_to(point)
		previous = point
	var count := ceili(estimate / SAMPLE_SPACING)
	var index := sections.size()
	var section := {
		"name": "C4 station return",
		"kind": "CLOSURE",
		"length": estimate,
		"controls": controls,
		"lsm": 0,
		"start_index": route.positions.size() - 1,
		"start_distance": state.distance,
		"start_time": state.time,
		"start_height": state.position.y,
		"entry_speed": state.speed,
	}
	## Seed the Newton solve the way the grade sections do, so any entry speed converges.
	var mean_gravity: float = G0 * (start.y - station_position.y) / estimate
	var average_drag: float = DRAG_FACTOR * 0.5 * (state.speed * state.speed + station_speed * station_speed) + ROLLING_FACTOR * G0
	var delivered: float = 1.0 - minf(60.0 / estimate, 0.45)
	var drive: float = (0.5 * (station_speed * station_speed - state.speed * state.speed) - mean_gravity * estimate + average_drag * estimate) / (estimate * delivered)
	for _iteration in 6:
		var error := _closure_exit_speed2(route, controls, count, section.entry_speed, drive, state.distance) - station_speed * station_speed
		if absf(error) < 0.01:
			break
		var shifted := _closure_exit_speed2(route, controls, count, section.entry_speed, drive + 0.05, state.distance)
		var gradient := (shifted - error - station_speed * station_speed) / 0.05
		if absf(gradient) < 0.01:
			break
		drive -= error / gradient
	previous = start
	for i in range(1, count + 1):
		var u0 := float(i - 1) / count
		var u := float(i) / count
		var um := (u0 + u) * 0.5
		var point := _bezier9(controls, u)
		var tangent := _bezier9_derivative(controls, u).normalized()
		var chord := previous.distance_to(point)
		var middle_tangent := _bezier9_derivative(controls, um).normalized()
		var middle_curvature := _bezier_curvature(controls, um)
		var front_gravity := GRAVITY.dot(middle_tangent)
		var gravity_along := _mean_train_gravity(route, state.distance + chord * 0.5, middle_tangent)
		var gravity_across := GRAVITY - middle_tangent * front_gravity
		var middle_up := _level_up(middle_tangent)
		var middle_proper: Vector3 = middle_curvature * state.speed * state.speed - gravity_across
		var drag: float = DRAG_FACTOR * state.speed * state.speed + ROLLING_FACTOR * absf(middle_proper.dot(middle_up))
		var acceleration: float = gravity_along + drive * _engagement(um, estimate) - drag
		var speed_start: float = state.speed
		var speed_end := sqrt(maxf(0.04, state.speed * state.speed + 2.0 * acceleration * chord))
		var curvature := _bezier_curvature(controls, u)
		state.position = point
		state.tangent = tangent
		state.up = _level_up(tangent)
		state.speed = speed_end
		state.distance += chord
		state.time += chord / maxf(0.5 * (speed_start + speed_end), 1.0)
		gravity_across = GRAVITY - tangent * GRAVITY.dot(tangent)
		var proper: Vector3 = curvature * speed_end * speed_end - gravity_across
		var up: Vector3 = state.up
		var right: Vector3 = tangent.cross(up).normalized()
		var end_drag := DRAG_FACTOR * speed_end * speed_end + ROLLING_FACTOR * absf(proper.dot(up))
		var end_gravity := _mean_train_gravity(route, state.distance, tangent)
		var longitudinal := (end_gravity - GRAVITY.dot(tangent) + drive * _engagement(u, estimate) - end_drag) / G0
		append_state(route, state, index, proper.dot(up) / G0, proper.dot(right) / G0, longitudinal, 0, curvature)
		previous = point
	section["end_index"] = route.positions.size() - 1
	section["end_distance"] = state.distance
	section["end_time"] = state.time
	section["end_height"] = state.position.y
	section["exit_speed"] = state.speed
	section["length"] = state.distance - section.start_distance
	sections.append(section)


static func _closure_exit_speed2(
	route: Dictionary,
	controls: PackedVector3Array,
	count: int,
	entry_speed: float,
	drive: float,
	start_distance: float
) -> float:
	var history: Dictionary = route.duplicate(true)
	var speed2 := entry_speed * entry_speed
	var previous := controls[0]
	var length := 0.0
	for i in range(1, 101):
		var point := _bezier9(controls, i / 100.0)
		length += previous.distance_to(point)
		previous = point
	previous = controls[0]
	var distance := start_distance
	for i in range(1, count + 1):
		var u := float(i) / count
		var um := (float(i) - 0.5) / count
		var point := _bezier9(controls, u)
		var chord := previous.distance_to(point)
		var tangent := _bezier9_derivative(controls, um).normalized()
		var curvature := _bezier_curvature(controls, um)
		var up := _level_up(tangent)
		var front_gravity := GRAVITY.dot(tangent)
		var gravity_along := _mean_train_gravity(history, distance + chord * 0.5, tangent)
		var proper := curvature * speed2 - (GRAVITY - tangent * front_gravity)
		var drag := DRAG_FACTOR * speed2 + ROLLING_FACTOR * absf(proper.dot(up))
		speed2 = maxf(0.04, speed2 + 2.0 * (gravity_along + drive * _engagement(um, length) - drag) * chord)
		distance += chord
		history.distances.append(distance)
		history.tangents.append(_bezier9_derivative(controls, u).normalized())
		previous = point
	return speed2


static func _bezier9(points: PackedVector3Array, u: float) -> Vector3:
	var work := Array(points)
	for level in range(9, 0, -1):
		for i in level:
			work[i] = (work[i] as Vector3).lerp(work[i + 1], u)
	return work[0]


static func _bezier9_derivative(points: PackedVector3Array, u: float) -> Vector3:
	var derivative := PackedVector3Array()
	for i in 9:
		derivative.append((points[i + 1] - points[i]) * 9.0)
	return _bezier(derivative, u)


static func _bezier_curvature(points: PackedVector3Array, u: float) -> Vector3:
	var first := PackedVector3Array()
	var second := PackedVector3Array()
	for i in 9:
		first.append((points[i + 1] - points[i]) * 9.0)
	for i in 8:
		second.append((first[i + 1] - first[i]) * 8.0)
	var dp := _bezier(first, u)
	var ddp := _bezier(second, u)
	var speed := maxf(dp.length(), 0.001)
	var tangent := dp / speed
	return (ddp - tangent * tangent.dot(ddp)) / (speed * speed)


static func _bezier(points: PackedVector3Array, u: float) -> Vector3:
	var work := Array(points)
	for level in range(points.size() - 1, 0, -1):
		for i in level:
			work[i] = (work[i] as Vector3).lerp(work[i + 1], u)
	return work[0]


## ------------------------------------------------------------------------- scalar closure solve


static func exit_pitch_deg(state: Dictionary) -> float:
	return rad_to_deg(asin(clampf(state.tangent.y, -1.0, 1.0)))


static func _trial(route: Dictionary, state: Dictionary, section: Dictionary) -> Dictionary:
	var trial_route: Dictionary = route.duplicate(true)
	var trial_state: Dictionary = state.duplicate(true)
	integrate_fvd(trial_route, trial_state, section, -1)
	return {"route": trial_route, "state": trial_state}


## Secant on a single scalar k. `factory` turns k into an FVD section, `measure` reads the quantity
## being closed off the trial route and state. Replaces the old per-section trim hack.
static func solve_scalar(
	route: Dictionary,
	state: Dictionary,
	factory: Callable,
	measure: Callable,
	target: float,
	k0: float,
	k1: float,
	tolerance: float
) -> float:
	var a := k0
	var trial := _trial(route, state, factory.call(a))
	var fa: float = measure.call(trial.route, trial.state) - target
	var best := a
	var best_error := absf(fa)
	var b := k1
	for _iteration in 12:
		if best_error <= tolerance:
			break
		trial = _trial(route, state, factory.call(b))
		var fb: float = measure.call(trial.route, trial.state) - target
		if absf(fb) < best_error:
			best_error = absf(fb)
			best = b
		var denominator := fb - fa
		if absf(denominator) < 0.000001:
			break
		var next: float = b - fb * (b - a) / denominator
		if not is_finite(next):
			break
		a = b
		fa = fb
		## Keep a runaway secant inside a band around the seed: k is always a length here, and an
		## unreachable target must fail as "closest we got", not as an unbounded integration.
		b = clampf(next, maxf(k0, 1.0) * 0.05, maxf(k0, 1.0) * 30.0)
	return best


## ----------------------------------------------------------------------------- element templates
##
## Every author_* returns solved FVD sections ready to integrate in order. Group boundaries hold
## normal 1.0, lateral 0.0 and roll rate 0.0 (bank angle may carry, its rate may not); sections
## inside a group match values exactly at the seam, which the zero-slope quintic keys turn into C2
## force and C4 position. Nothing is speed- or pitch-specific: curvature scales as g/v² by itself.


## Crest that pitches the train over from its current attitude toward target_pitch_deg. The last
## key sits at cos(target) — free-fall support — so a fall can continue it without a force step.
static func author_pushover(route: Dictionary, state: Dictionary, p: Dictionary) -> Array:
	var target: float = p.target_pitch_deg
	var edge_g: float = p.get("edge_g", 0.15)
	var cos_target := cos(deg_to_rad(target))
	## Support has to stay under cos(pitch) all the way down or the crest stalls where the two
	## meet, and the train speeds up as it falls, so a near-vertical target needs real margin.
	var floor_g: float = minf(edge_g, cos_target - 1.2 * (1.0 - cos_target) * (1.0 - cos_target))
	var normal := [
		Vector2(0, 1),
		Vector2(0.3, edge_g),
		Vector2(0.72, floor_g),
		Vector2(1, cos_target),
	]
	var entry := exit_pitch_deg(state)
	var heading := Vector2(state.tangent.x, state.tangent.z).normalized()
	var seed: float = maxf(deg_to_rad(absf(target - entry)) * state.speed * state.speed / (0.45 * G0), 20.0)
	var factory := func(k: float) -> Dictionary:
		return fvd_section("pushover", k, normal, _flat(0.0), _flat(0.0))
	## asin folds at vertical, which turns the solve into a search across a crease; measuring
	## against the entry heading keeps past-vertical readings monotone.
	var measure := func(_trial_route: Dictionary, trial_state: Dictionary) -> float:
		var tangent: Vector3 = trial_state.tangent
		return rad_to_deg(atan2(tangent.y, Vector2(tangent.x, tangent.z).dot(heading)))
	var length := solve_scalar(route, state, factory, measure, target, seed, seed * 1.4, 0.5)
	var element := {"kind": "pushover", "target_pitch_deg": target, "edge_g": edge_g}
	return [fvd_section("pushover", length, normal, _flat(0.0), _flat(0.0), element)]


## Straight segment held at the attitude the state already has: normal cos(pitch) cancels exactly.
static func author_fall(_route: Dictionary, state: Dictionary, p: Dictionary) -> Array:
	var pitch := deg_to_rad(exit_pitch_deg(state))
	var length: float = p.drop / maxf(absf(sin(pitch)), 0.05)
	var element := {"kind": "fall", "drop": p.drop, "pitch_deg": rad_to_deg(pitch)}
	return [fvd_section("fall", maxf(length, 1.0), _flat(cos(pitch)), _flat(0.0), _flat(0.0), element)]


## Sustained-g arc back to exit_pitch_deg, ending at 1 g so it can close a group.
static func author_pullout(route: Dictionary, state: Dictionary, p: Dictionary) -> Array:
	var target: float = p.exit_pitch_deg
	var peak: float = p.peak_g
	var entry := exit_pitch_deg(state)
	var normal := [Vector2(0, cos(deg_to_rad(entry))), Vector2(0.3, peak), Vector2(0.7, peak), Vector2(1, 1)]
	var seed: float = maxf(deg_to_rad(absf(target - entry)) * state.speed * state.speed / (maxf(peak - 1.0, 0.3) * G0), 20.0)
	var factory := func(k: float) -> Dictionary:
		return fvd_section("pullout", k, normal, _flat(0.0), _flat(0.0))
	var measure := func(_trial_route: Dictionary, trial_state: Dictionary) -> float:
		return exit_pitch_deg(trial_state)
	var length := solve_scalar(route, state, factory, measure, target, seed, seed * 1.4, 0.5)
	var element := {"kind": "pullout", "exit_pitch_deg": target, "peak_g": peak}
	return [fvd_section("pullout", length, normal, _flat(0.0), _flat(0.0), element)]


## Pushover → fall → pullout sized so the group loses `height` in total. The fall absorbs whatever
## the two shaped ends do not, measured from trial integrations rather than assumed.
static func author_dive(route: Dictionary, state: Dictionary, p: Dictionary) -> Array:
	var height: float = p.height
	var max_pitch: float = p.get("max_pitch_deg", -90.0)
	var exit_pitch: float = p.get("exit_pitch_deg", 0.0)
	var pushover: Dictionary = author_pushover(route, state, {"target_pitch_deg": max_pitch})[0]
	var after_push := _trial(route, state, pushover)
	var crest_loss: float = state.position.y - after_push.state.position.y
	var fall: Dictionary = {}
	var pullout: Dictionary = {}
	var after_pullout: Dictionary = after_push
	## The pullout's own height cost grows with the speed the fall delivers, so the drop is a
	## fixed point, not a subtraction. d(total)/d(drop) is near 1.4, which Newtons it out fast.
	var drop := maxf(height - crest_loss, 0.0) * 0.6
	var achieved := 0.0
	for _pass in 6:
		fall = author_fall(after_push.route, after_push.state, {"drop": drop})[0]
		var after_fall := _trial(after_push.route, after_push.state, fall)
		pullout = author_pullout(
			after_fall.route, after_fall.state, {"exit_pitch_deg": exit_pitch, "peak_g": p.peak_g}
		)[0]
		after_pullout = _trial(after_fall.route, after_fall.state, pullout)
		achieved = state.position.y - after_pullout.state.position.y
		if absf(achieved - height) < 0.5:
			break
		drop = maxf(drop - (achieved - height) / 1.4, 0.0)
	var group := [pushover, fall, pullout]
	for section in group:
		section.element["dive_height"] = achieved
		section.element["dive_target_height"] = height
	return group


## Airtime hill entered pitched up. Length alone cannot hold both a target rise and a symmetric
## profile, so the length closes on symmetry (exit pitch mirrors entry) and the crown span — how
## much of the section is spent ramping into the crown — closes on the rise.
static func author_hill(route: Dictionary, state: Dictionary, p: Dictionary) -> Array:
	var rise: float = p.rise
	var crown: float = p.crown_g
	var first: int = route.positions.size()
	var entry_height: float = state.position.y
	var entry_pitch := exit_pitch_deg(state)
	var shape := {"length": maxf(2.0 * rise / maxf(sin(deg_to_rad(entry_pitch)), 0.1), 20.0)}
	var symmetry := func(_trial_route: Dictionary, trial_state: Dictionary) -> float:
		return exit_pitch_deg(trial_state)
	var rise_of := func(trial_route: Dictionary, _trial_state: Dictionary) -> float:
		return trial_route.positions[_apex_index(trial_route, first)].y - entry_height
	var factory := func(span: float) -> Dictionary:
		var inner := func(k: float) -> Dictionary:
			return _hill_section(k, span, crown, {})
		shape["length"] = solve_scalar(
			route, state, inner, symmetry, -entry_pitch, shape["length"], shape["length"] * 1.15, 0.5
		)
		return _hill_section(shape["length"], span, crown, {})
	var span := solve_scalar(route, state, factory, rise_of, rise, 0.25, 0.33, maxf(0.5, rise * 0.01))
	var solved: Dictionary = factory.call(span)
	var apex := _trial(route, state, solved)
	var apex_index := _apex_index(apex.route, first)
	solved["element"] = {
		"kind": "hill",
		"rise": apex.route.positions[apex_index].y - entry_height,
		"target_rise": rise,
		"crown_g": crown,
		"crown_span": span,
		"apex_pitch_deg": rad_to_deg(asin(clampf(apex.route.tangents[apex_index].y, -1.0, 1.0))),
	}
	return [solved]


static func _hill_section(length: float, span: float, crown: float, element: Dictionary) -> Dictionary:
	var edge := clampf(span, 0.05, 0.48)
	var normal := [Vector2(0, 1), Vector2(edge, crown), Vector2(1.0 - edge, crown), Vector2(1, 1)]
	return fvd_section("hill", length, normal, _flat(0.0), _flat(0.0), element)


## Coordinated turn: the bank carries the whole load, so the rider feels no lateral g.
static func author_turn(route: Dictionary, state: Dictionary, p: Dictionary) -> Array:
	var bank: float = absf(p.bank_deg) * signf(p.heading_change_deg)
	return _banked_turn(route, state, "turn", p.heading_change_deg, bank, 0.0, 0.0, true, 1.5, {
		"kind": "turn", "heading_change_deg": p.heading_change_deg, "bank_deg": bank,
	})


## Suspense turn: banked away from the corner, the lateral load carries the turn and the normal
## drops to whatever holds altitude at that bank. The heading sign owns the direction; the bank
## and lateral parameters contribute magnitude only.
static func author_rim_turn(route: Dictionary, state: Dictionary, p: Dictionary) -> Array:
	var direction := signf(p.heading_change_deg)
	var bank: float = -absf(p.outward_bank_deg) * direction
	var lateral: float = absf(p.lateral_g) * direction
	return _banked_turn(route, state, "rim turn", p.heading_change_deg, bank, lateral, 0.0, true, 1.5, {
		"kind": "rim_turn", "heading_change_deg": p.heading_change_deg, "bank_deg": bank,
		"lateral_g": lateral,
	})


## Past-vertical turn. No bank holds altitude beyond 90°, so the normal peak is authored directly
## and the element descends by construction.
static func author_overbank(route: Dictionary, state: Dictionary, p: Dictionary) -> Array:
	var bank: float = absf(p.bank_deg) * signf(p.heading_change_deg)
	return _banked_turn(route, state, "overbank", p.heading_change_deg, bank, 0.0, p.peak_g, false, 2.0, {
		"kind": "overbank", "heading_change_deg": p.heading_change_deg, "bank_deg": bank,
		"peak_normal_g": p.peak_g,
	})


## Shared turn body. Normal and lateral keys are placed on the roll schedule itself, so support
## tracks the bank as it builds instead of leaving a vertical imbalance across the roll-in; the
## roll amplitude is carried as bank·speed per unit length so solving the length cannot disturb
## the bank it reaches. Length closes on heading change, roll amplitude on the bank measured.
static func _banked_turn(
	route: Dictionary,
	state: Dictionary,
	name: String,
	heading_change: float,
	bank: float,
	lateral: float,
	peak_normal: float,
	hold_altitude: bool,
	tolerance: float,
	element: Dictionary
) -> Array:
	var normal := []
	var lateral_keys := []
	for u in TURN_KEYS:
		var f := _bank_fraction(u)
		normal.append(Vector2(u, _turn_normal(f, bank, lateral, peak_normal, hold_altitude)))
		lateral_keys.append(Vector2(u, lateral * f))
	var tuning := {"in": 0.0, "out": 0.0}
	var first: int = route.positions.size()
	var factory := func(k: float) -> Dictionary:
		return fvd_section(name, k, normal, lateral_keys, [
			Vector2(0, 0), Vector2(0.18, tuning["in"] / k), Vector2(0.32, 0),
			Vector2(0.68, 0), Vector2(0.82, tuning["out"] / k), Vector2(1, 0),
		])
	var measure := func(trial_route: Dictionary, _trial_state: Dictionary) -> float:
		return _heading_change_deg(trial_route, first)
	var hold: float = _turn_normal(1.0, bank, lateral, peak_normal, hold_altitude)
	var load := absf(hold * sin(deg_to_rad(bank)) + lateral * cos(deg_to_rad(bank)))
	var length: float = maxf(deg_to_rad(absf(heading_change)) * state.speed * state.speed / (maxf(load, 0.05) * G0), 20.0)
	tuning["in"] = bank * state.speed / 0.16
	tuning["out"] = -tuning["in"]
	for _pass in 3:
		length = solve_scalar(route, state, factory, measure, heading_change, length, length * 1.3, tolerance)
		_correct_roll(route, state, factory, tuning, bank, first, length)
	length = solve_scalar(route, state, factory, measure, heading_change, length, length * 1.05, tolerance)
	for _pass in 2:
		_correct_roll(route, state, factory, tuning, bank, first, length)
	element["peak_normal_g"] = hold
	element["roll_rate_in"] = tuning["in"] / length
	element["roll_rate_out"] = tuning["out"] / length
	var section: Dictionary = factory.call(length)
	section["element"] = element
	return [section]


## Rescale roll-in against the bank actually held and roll-out against the bank it actually takes
## back out. Heading change and speed both couple into the frame, so this is measured, not derived.
static func _correct_roll(
	route: Dictionary,
	state: Dictionary,
	factory: Callable,
	tuning: Dictionary,
	bank: float,
	first: int,
	length: float
) -> void:
	var trial := _trial(route, state, factory.call(length))
	var count: int = trial.route.banks.size() - first
	var hold: float = trial.route.banks[first + roundi(0.32 * count)]
	var release: float = trial.route.banks[first + roundi(0.68 * count)]
	var exit_bank: float = trial.route.banks[-1]
	if absf(hold) > 1.0:
		tuning["in"] *= bank / hold
	if absf(exit_bank - release) > 1.0:
		tuning["out"] *= -release / (exit_bank - release)


## Support that keeps a banked turn level, or a plain ramp to an authored peak when no bank can.
static func _turn_normal(
	fraction: float, bank: float, lateral: float, peak_normal: float, hold_altitude: bool
) -> float:
	if not hold_altitude:
		return 1.0 + (peak_normal - 1.0) * fraction
	var angle := deg_to_rad(bank * fraction)
	return (1.0 + lateral * fraction * sin(angle)) / maxf(cos(angle), 0.15)


## Fraction of full bank reached at u, from the canonical roll shape. Zero at both ends, so the
## normal and lateral keys derived from it honour the group boundary contract exactly.
static func _bank_fraction(u: float) -> float:
	const STEPS := 400
	var keys := PackedVector2Array(ROLL_SHAPE)
	var partial := 0.0
	var total := 0.0
	for i in STEPS:
		var x := (i + 0.5) / STEPS
		var value: float = _profile(keys, x).x / STEPS
		if x <= 0.5:
			total += value
		if x <= u:
			partial += value
	return partial / maxf(total, 0.000001)


static func _flat(value: float) -> Array:
	return [Vector2(0, value), Vector2(1, value)]


static func _apex_index(route: Dictionary, first: int) -> int:
	var best := first
	for i in range(first, route.positions.size()):
		if route.positions[i].y > route.positions[best].y:
			best = i
	return best


## Signed heading swept from sample `first - 1` onward, accumulated so turns past 180° read true.
static func _heading_change_deg(route: Dictionary, first: int) -> float:
	var total := 0.0
	for i in range(first, route.tangents.size()):
		var a := Vector2(route.tangents[i - 1].x, route.tangents[i - 1].z).normalized()
		var b := Vector2(route.tangents[i].x, route.tangents[i].z).normalized()
		total += atan2(a.x * b.y - a.y * b.x, a.dot(b))
	return rad_to_deg(total)


## ---------------------------------------------------------------------------------- primitives


static func _level_up(tangent: Vector3) -> Vector3:
	return (Vector3.UP - tangent * tangent.y).normalized()


static func _transport_up(up: Vector3, old_tangent: Vector3, new_tangent: Vector3) -> Vector3:
	var axis := old_tangent.cross(new_tangent)
	if axis.length_squared() > 0.0000000001:
		up = up.rotated(axis.normalized(), atan2(axis.length(), clampf(old_tangent.dot(new_tangent), -1.0, 1.0)))
	return (up - new_tangent * up.dot(new_tangent)).normalized()


static func _mean_train_gravity(
	route: Dictionary, front_distance: float, front_tangent: Vector3
) -> float:
	if route.is_empty() or not route.has("distances") or route.distances.is_empty():
		return GRAVITY.dot(front_tangent)
	var total := GRAVITY.dot(front_tangent)
	for row in range(1, ROW_OFFSETS.size()):
		var at: float = front_distance - ROW_OFFSETS[row]
		var tangent: Vector3 = route.tangents[0] if at <= 0.0 else _history_tangent(route, at)
		total += GRAVITY.dot(tangent)
	return total / ROW_OFFSETS.size()


static func _history_tangent(route: Dictionary, distance: float) -> Vector3:
	var last: int = route.distances.size() - 1
	if distance >= route.distances[last]:
		return route.tangents[last]
	var low := 0
	var high := last
	while low + 1 < high:
		var middle := floori((low + high) * 0.5)
		if route.distances[middle] <= distance:
			low = middle
		else:
			high = middle
	var weight: float = inverse_lerp(route.distances[low], route.distances[high], distance)
	return route.tangents[low].lerp(route.tangents[high], weight).normalized()


static func _profile(keys: PackedVector2Array, u: float) -> Vector2:
	return _evaluate(keys, u, false)


static func _profile_septic(keys: PackedVector2Array, u: float) -> Vector2:
	return _evaluate(keys, u, true)


static func _evaluate(keys: PackedVector2Array, u: float, septic: bool) -> Vector2:
	var index := 0
	while index + 1 < keys.size() and keys[index + 1].x <= u:
		index += 1
	if index + 1 >= keys.size():
		return Vector2(keys[-1].y, 0.0)
	var a := keys[index]
	var b := keys[index + 1]
	var width := b.x - a.x
	var x := clampf((u - a.x) / width, 0.0, 1.0)
	var span := b.y - a.y
	var value: float
	var slope: float
	if septic:
		value = x * x * x * x * (35.0 + x * (-84.0 + x * (70.0 - 20.0 * x)))
		slope = 140.0 * x * x * x * pow(1.0 - x, 3)
	else:
		value = _smooth5(x)
		slope = 30.0 * x * x * (1.0 - x) * (1.0 - x)
	return Vector2(a.y + span * value, span * slope / width)


static func _smooth5(x: float) -> float:
	return x * x * x * (10.0 + x * (-15.0 + 6.0 * x))


static func _bounds(positions: PackedVector3Array) -> AABB:
	var box := AABB(positions[0], Vector3.ZERO)
	for position in positions:
		box = box.expand(position)
	return box
