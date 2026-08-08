class_name RideModel
extends RefCounted

const G0 := 9.80665
const GRAVITY := Vector3.DOWN * G0
const SAMPLE_SPACING := 1.5
const STATION_POSITION := Vector3(690.0, 14.0, -80.0)
const STATION_TANGENT := Vector3.FORWARD
const STATION_SPEED := 6.0
const TARGET_TOP_SPEED := 320.0 / 3.6
const DRAG_FACTOR := 0.000085
const ROLLING_FACTOR := 0.0015

const POSITIVE_LIMIT := [Vector2(0.2, 7.0), Vector2(1.0, 7.0), Vector2(2.0, 6.0), Vector2(4.0, 5.0), Vector2(8.0, 4.0), Vector2(15.0, 3.2)]
const NEGATIVE_LIMIT := [Vector2(0.2, 2.5), Vector2(1.0, 2.5), Vector2(2.0, 2.2), Vector2(5.0, 1.8), Vector2(8.0, 1.4)]
const LATERAL_LIMIT := [Vector2(0.2, 4.0), Vector2(1.0, 4.0), Vector2(2.0, 3.0), Vector2(4.0, 2.5)]
const LONGITUDINAL_LIMIT := [Vector2(0.2, 7.0), Vector2(1.0, 7.0), Vector2(2.0, 5.0), Vector2(5.0, 4.0)]
const JERK_LIMIT := 15.0
const ROLL_RATE_LIMIT := 110.0
const ROW_OFFSETS := [0.0, 2.15, 4.30, 6.45, 8.60, 10.75, 12.90]


static func build() -> Dictionary:
	var route := _empty_route()
	var state := {
		"position": STATION_POSITION,
		"tangent": STATION_TANGENT,
		"speed": STATION_SPEED,
		"distance": 0.0,
		"time": 0.0,
	}
	_append_state(route, state, 0, 0.0, 1.0, 0.0, 0.0, 0, Vector3.ZERO)
	var sections := _sections()
	for index in sections.size():
		var section: Dictionary = sections[index]
		section["start_index"] = route.positions.size() - 1
		section["start_distance"] = state.distance
		section["start_time"] = state.time
		section["start_height"] = state.position.y
		section["entry_speed"] = state.speed
		if section.kind == "FVD":
			if is_finite(section.exit_pitch):
				section["trim"] = _solve_trim(route, state, section)
			_integrate_fvd(route, state, section, index)
		else:
			_integrate_grade(route, state, section, index)
		section["end_index"] = route.positions.size() - 1
		section["end_distance"] = state.distance
		section["end_time"] = state.time
		section["end_height"] = state.position.y
		section["exit_speed"] = state.speed
		sections[index] = section
	_append_closure(route, state, sections)
	_measure_roll_rates(route)
	route["sections"] = sections
	route["length"] = state.distance
	route["duration"] = state.time
	route["bounds"] = _bounds(route.positions)
	route["analysis"] = analyze(route)
	return route


static func _sections() -> Array[Dictionary]:
	return [
		_grade("Station · LSM 1", 45.0, [Vector2(0, 0), Vector2(1, 0)], 13.9, 1),
		_grade("LSM 1 · record lift", 290.0, [Vector2(0, 0), Vector2(0.18, 24), Vector2(0.82, 24), Vector2(1, 0)], 13.9, 1),
		_fvd(
			"Twisted 84 m side-drop",
			195.0,
			[Vector2(0, 1), Vector2(0.18, 0.10), Vector2(0.56, 0.10), Vector2(0.82, 3.8), Vector2(1, 1)],
			[Vector2(0, 0), Vector2(0.28, 0.12), Vector2(0.62, 0.0), Vector2(1, 0)],
			[Vector2(0, 0), Vector2(0.24, 50), Vector2(0.52, 24), Vector2(0.70, 0), Vector2(1, 0)],
			true,
			false,
			0.0
		),
		_fvd(
			"Lower-park airtime sequence",
			290.0,
			[Vector2(0, 1), Vector2(0.10, 3.2), Vector2(0.24, -0.45), Vector2(0.38, 3.4), Vector2(0.51, -1.85), Vector2(0.64, 3.1), Vector2(0.78, -0.55), Vector2(0.90, 2.7), Vector2(1, 1)],
			[Vector2(0, 0), Vector2(1, 0)],
			[Vector2(0, 0), Vector2(0.35, 0), Vector2(0.46, 35), Vector2(0.58, 0), Vector2(0.70, -38), Vector2(0.82, 0), Vector2(1, 0)],
			false,
			false,
			0.0
		),
		_fvd(
			"Lower-park high-speed banked turn",
			285.0,
			[Vector2(0, 1), Vector2(1, 1)],
			[Vector2(0, 0), Vector2(1, 0)],
			[Vector2(0, 0), Vector2(0.25, 65), Vector2(0.75, 65), Vector2(1, 0)],
			false,
			true,
			0.0,
			true
		),
		_grade("LSM 2 · cliff launch", 130.0, [Vector2(0, 0), Vector2(1, 0)], 52.1, 2),
		_grade("LSM 2 · powered cliff climb", 560.0, [Vector2(0, 0), Vector2(0.20, 28), Vector2(0.80, 28), Vector2(1, 0)], 52.1, 2),
		_fvd(
			"Cliff-top speed hills",
			150.0,
			[Vector2(0, 1), Vector2(0.22, 2.6), Vector2(0.48, -0.4), Vector2(0.74, 2.7), Vector2(1, 1)],
			[Vector2(0, 0), Vector2(0.5, 0.08), Vector2(1, 0)],
			[Vector2(0, 0), Vector2(0.38, 24), Vector2(0.68, -20), Vector2(1, 0)],
			true,
			false,
			0.0
		),
		_fvd(
			"Outward-bank rim turn",
			280.0,
			[Vector2(0, 1), Vector2(1, 1)],
			[Vector2(0, 0), Vector2(0.24, -1.6), Vector2(0.76, -1.6), Vector2(1, 0)],
			[Vector2(0, 0), Vector2(0.24, 30), Vector2(0.76, 30), Vector2(1, 0)],
			false,
			true,
			0.0,
			false,
			true
		),
		_grade("Holding brake", 65.0, [Vector2(0, 0), Vector2(1, 0)], 2.0),
		_grade("Cliff hold crawl", 14.0, [Vector2(0, 0), Vector2(1, 0)], 2.0),
		_grade("Holding release", 6.0, [Vector2(0, 0), Vector2(1, 0)], 5.0),
		_fvd(
			"198 m cliff dive",
			35.0,
			[Vector2(0, 1), Vector2(0.20, 0.06), Vector2(0.80, 0.06), Vector2(1, 1)],
			[Vector2(0, 0), Vector2(1, 0)],
			[Vector2(0, 0), Vector2(1, 0)],
			true,
			true,
			-58.0
		),
		_grade("Tunnel · downhill LSM 3", 101.0, [Vector2(0, -58), Vector2(1, -58)], 79.45, 3),
		_fvd(
			"6.9 g record pullout",
			200.0,
			[Vector2(0, 0.5299), Vector2(0.35, 6.84), Vector2(0.62, 6.84), Vector2(1, 1)],
			[Vector2(0, 0), Vector2(1, 0)],
			[Vector2(0, 0), Vector2(1, 0)],
			false
		),
		_fvd(
			"206 m record camelback",
			712.0,
			[Vector2(0, 1), Vector2(0.085, 6.15), Vector2(0.125, 6.15), Vector2(0.46, -2.25), Vector2(0.54, -2.25), Vector2(0.875, 3.18), Vector2(0.915, 3.18), Vector2(1, 1)],
			[Vector2(0, 0), Vector2(1, 0)],
			[Vector2(0, 0), Vector2(1, 0)],
			false
		),
		_fvd(
			"320 km/h banked turnaround",
			700.0,
			[Vector2(0, 1), Vector2(0.22, 3.24), Vector2(0.78, 3.24), Vector2(1, 1)],
			[Vector2(0, 0), Vector2(1, 0)],
			[Vector2(0, 0), Vector2(0.22, 72), Vector2(0.78, 72), Vector2(1, 0)],
			false,
			false,
			0.0,
			true
		),
		_fvd(
			"Elongated return hills",
			220.0,
			[Vector2(0, 1), Vector2(0.18, 3.1), Vector2(0.40, -0.7), Vector2(0.62, 3.3), Vector2(0.80, -0.45), Vector2(1, 1)],
			[Vector2(0, 0), Vector2(1, 0)],
			[Vector2(0, 0), Vector2(1, 0)],
			false,
			false,
			0.0
		),
		_fvd(
			"Raceway banked return",
			300.0,
			[Vector2(0, 1), Vector2(0.25, 2.7), Vector2(0.75, 2.7), Vector2(1, 1)],
			[Vector2(0, 0), Vector2(1, 0)],
			[Vector2(0, 0), Vector2(0.33, 53.5), Vector2(0.67, 53.5), Vector2(1, 0)],
			false,
			false,
			0.0,
			true
		),
		_fvd(
			"Final airtime wave",
			100.0,
			[Vector2(0, 1), Vector2(0.22, 2.0), Vector2(0.48, -0.3), Vector2(0.74, 1.8), Vector2(1, 1)],
			[Vector2(0, 0), Vector2(0.5, 0.10), Vector2(1, 0)],
			[Vector2(0, 0), Vector2(1, 0)],
			false,
			true,
			0.0
		),
		_grade("Final brakes", 460.0, [Vector2(0, 0), Vector2(1, 0)], 25.0),
	]


static func _fvd(
	name: String,
	length: float,
	normal: Array,
	lateral: Array,
	bank: Array,
	gate_in: bool = false,
	gate_out: bool = false,
	exit_pitch: float = NAN,
	coordinated: bool = false,
	level_turn: bool = false
) -> Dictionary:
	return {
		"name": name,
		"kind": "FVD",
		"length": length,
		"normal": PackedVector2Array(normal),
		"lateral": PackedVector2Array(lateral),
		"bank": PackedVector2Array(bank),
		"gate_in": gate_in,
		"gate_out": gate_out,
		"exit_pitch": exit_pitch,
		"coordinated": coordinated,
		"level_turn": level_turn,
		"trim": 0.0,
		"lsm": 0,
	}


static func _grade(
	name: String,
	length: float,
	pitch: Array,
	exit_speed: float,
	lsm: int = 0
) -> Dictionary:
	return {
		"name": name,
		"kind": "GRADE",
		"length": length,
		"pitch": PackedVector2Array(pitch),
		"exit_speed_target": exit_speed,
		"lsm": lsm,
	}


static func _empty_route() -> Dictionary:
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


static func _integrate_fvd(
	route: Dictionary,
	state: Dictionary,
	section: Dictionary,
	section_index: int
) -> void:
	var steps := ceili(section.length / SAMPLE_SPACING)
	var step: float = section.length / steps
	for i in steps:
		var u0 := float(i) / steps
		var u1 := float(i + 1) / steps
		var um := (u0 + u1) * 0.5
		var d0 := _fvd_derivative(route, state, section, u0)
		var middle := {
			"position": state.position + state.tangent * step * 0.5,
			"tangent": (state.tangent + d0.curvature * step * 0.5).normalized(),
			"speed": sqrt(maxf(0.04, state.speed * state.speed + 2.0 * d0.energy * step * 0.5)),
			"distance": state.distance + step * 0.5,
		}
		var dm := _fvd_derivative(route, middle, section, um)
		var next_tangent: Vector3 = (state.tangent + dm.curvature * step).normalized()
		state.position += middle.tangent * step
		state.tangent = next_tangent
		state.speed = sqrt(maxf(0.04, state.speed * state.speed + 2.0 * dm.energy * step))
		state.distance += step
		state.time += step / maxf(dm.speed, 1.0)
		var sample := _fvd_derivative(route, state, section, u1)
		_append_state(
			route,
			state,
			section_index,
			sample.bank,
			sample.normal,
			sample.lateral,
			sample.longitudinal,
			section.lsm,
			sample.curvature
		)


static func _solve_trim(route: Dictionary, start: Dictionary, section: Dictionary) -> float:
	var trim: float = section.trim
	for _iteration in 10:
		section["trim"] = trim
		var state: Dictionary = start.duplicate(true)
		_integrate_fvd(route.duplicate(true), state, section, -1)
		var error: float = rad_to_deg(asin(clampf(state.tangent.y, -1.0, 1.0))) - section.exit_pitch
		if absf(error) < 0.0005:
			break
		section["trim"] = trim + 0.04
		var shifted: Dictionary = start.duplicate(true)
		_integrate_fvd(route.duplicate(true), shifted, section, -1)
		var shifted_pitch: float = rad_to_deg(asin(clampf(shifted.tangent.y, -1.0, 1.0)))
		var derivative: float = (shifted_pitch - (error + section.exit_pitch)) / 0.04
		if absf(derivative) < 0.01:
			break
		trim = clampf(trim - error / derivative, -2.5, 2.5)
	return trim


static func _fvd_derivative(route: Dictionary, state: Dictionary, section: Dictionary, u: float) -> Dictionary:
	var normal_eval := _profile(section.normal, u, false)
	var lateral_eval := _profile(section.lateral, u, false)
	var bank_eval := _profile(section.bank, u, true)
	var gate := 1.0
	if section.gate_in:
		gate *= _smooth5(clampf(u / 0.16, 0.0, 1.0))
	if section.gate_out:
		gate *= _smooth5(clampf((1.0 - u) / 0.16, 0.0, 1.0))
	var bank: float = deg_to_rad(bank_eval.x * gate)
	var rider_up: Vector3 = _level_up(state.tangent).rotated(state.tangent, bank)
	var right: Vector3 = state.tangent.cross(rider_up).normalized()
	rider_up = right.cross(state.tangent).normalized()
	var gravity_across: Vector3 = GRAVITY - state.tangent * GRAVITY.dot(state.tangent)
	var equilibrium: Vector3 = -gravity_across
	var trim_window := _smooth5(clampf(u / 0.12, 0.0, 1.0)) * _smooth5(clampf((1.0 - u) / 0.12, 0.0, 1.0))
	var normal: float = normal_eval.x + section.trim * trim_window
	if section.coordinated:
		normal = 1.0 / maxf(cos(bank), 0.15) + section.trim * trim_window
	elif section.level_turn:
		normal = (1.0 + lateral_eval.x * sin(bank)) / maxf(cos(bank), 0.15)
	var target: Vector3 = (rider_up * normal + right * lateral_eval.x) * G0
	var proper: Vector3 = equilibrium.lerp(target, gate)
	var speed2: float = maxf(state.speed * state.speed, 0.04)
	var curvature: Vector3 = (proper + gravity_across) / speed2
	var drag: float = DRAG_FACTOR * speed2 + ROLLING_FACTOR * absf(proper.dot(rider_up))
	var energy: float = _mean_train_gravity(route, state.distance, state.tangent) - drag
	return {
		"curvature": curvature,
		"energy": energy,
		"speed": state.speed,
		"normal": proper.dot(rider_up) / G0,
		"lateral": proper.dot(right) / G0,
		"longitudinal": (energy - GRAVITY.dot(state.tangent)) / G0,
		"bank": rad_to_deg(bank),
	}


static func _integrate_grade(
	route: Dictionary, state: Dictionary, section: Dictionary, section_index: int
) -> void:
	var steps := ceili(section.length / SAMPLE_SPACING)
	var step: float = section.length / steps
	var heading: Vector2 = Vector2(state.tangent.x, state.tangent.z).normalized()
	var entry_speed: float = state.speed
	var mean_gravity: float = 0.0
	for i in 64:
		var pitch := deg_to_rad(_profile(section.pitch, (i + 0.5) / 64.0, true).x)
		mean_gravity += GRAVITY.dot(Vector3(heading.x * cos(pitch), sin(pitch), heading.y * cos(pitch))) / 64.0
	var average_speed2: float = 0.5 * (entry_speed * entry_speed + section.exit_speed_target * section.exit_speed_target)
	var average_drag: float = DRAG_FACTOR * average_speed2 + ROLLING_FACTOR * G0
	var delivered: float = 1.0 - minf(60.0 / section.length, 0.45)
	var drive: float = (0.5 * (section.exit_speed_target * section.exit_speed_target - entry_speed * entry_speed) - mean_gravity * section.length + average_drag * section.length) / (section.length * delivered)
	for i in steps:
		var u1 := float(i + 1) / steps
		var um := (i + 0.5) / steps
		var pitch_mid: float = deg_to_rad(_profile(section.pitch, um, true).x)
		var pitch_end_eval := _profile(section.pitch, u1, true)
		var pitch_end: float = deg_to_rad(pitch_end_eval.x)
		var tangent_mid: Vector3 = Vector3(heading.x * cos(pitch_mid), sin(pitch_mid), heading.y * cos(pitch_mid)).normalized()
		var next_tangent: Vector3 = Vector3(heading.x * cos(pitch_end), sin(pitch_end), heading.y * cos(pitch_end)).normalized()
		var lift: Vector3 = (Vector3.UP - tangent_mid * Vector3.UP.dot(tangent_mid)).normalized()
		var curvature: Vector3 = lift * deg_to_rad(_profile(section.pitch, um, true).y) / section.length
		var gravity_along := _mean_train_gravity(route, state.distance + step * 0.5, tangent_mid)
		var proper_mid: Vector3 = curvature * state.speed * state.speed - (GRAVITY - tangent_mid * gravity_along)
		var drag: float = DRAG_FACTOR * state.speed * state.speed + ROLLING_FACTOR * absf(proper_mid.dot(lift))
		var propulsion: float = drive * _engagement(um, section.length)
		var speed_end: float = sqrt(maxf(0.04, state.speed * state.speed + 2.0 * (gravity_along + propulsion - drag) * step))
		var average_speed: float = 0.5 * (state.speed + speed_end)
		state.position += tangent_mid * step
		state.tangent = next_tangent
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
		_append_state(
			route,
			state,
			section_index,
			0.0,
			proper.dot(_level_up(next_tangent)) / G0,
			proper.dot(next_tangent.cross(_level_up(next_tangent))) / G0,
			longitudinal,
			section.lsm,
			end_curvature
		)


static func _engagement(u: float, length: float) -> float:
	var fraction := minf(60.0 / length, 0.45)
	return _smooth5(clampf(u / fraction, 0.0, 1.0)) * _smooth5(clampf((1.0 - u) / fraction, 0.0, 1.0))


static func _append_closure(route: Dictionary, state: Dictionary, sections: Array[Dictionary]) -> void:
	var start: Vector3 = state.position
	var gap := start.distance_to(STATION_POSITION)
	var handle := clampf(gap * 0.72, 45.0, 350.0)
	var controls := PackedVector3Array()
	for i in 5:
		controls.append(start + state.tangent * handle * i / 9.0)
	for i in range(4, -1, -1):
		controls.append(STATION_POSITION - STATION_TANGENT * handle * i / 9.0)
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
	var drive := -4.0
	for _iteration in 6:
		var error := _closure_exit_speed2(route, controls, count, section.entry_speed, drive, state.distance) - STATION_SPEED * STATION_SPEED
		if absf(error) < 0.01:
			break
		var shifted := _closure_exit_speed2(route, controls, count, section.entry_speed, drive + 0.05, state.distance)
		var gradient := (shifted - error - STATION_SPEED * STATION_SPEED) / 0.05
		if absf(gradient) < 0.01:
			break
		drive -= error / gradient
	previous = start
	for i in range(1, count + 1):
		var u0 := float(i - 1) / count
		var u := float(i) / count
		var um := (u0 + u) * 0.5
		var point := _bezier9(controls, u)
		var derivative := _bezier9_derivative(controls, u)
		var tangent := derivative.normalized()
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
		state.speed = speed_end
		state.distance += chord
		state.time += chord / maxf(0.5 * (speed_start + speed_end), 1.0)
		gravity_across = GRAVITY - tangent * GRAVITY.dot(tangent)
		var proper: Vector3 = curvature * speed_end * speed_end - gravity_across
		var level_up := _level_up(tangent)
		var right: Vector3 = tangent.cross(level_up).normalized()
		var end_drag := DRAG_FACTOR * speed_end * speed_end + ROLLING_FACTOR * absf(proper.dot(level_up))
		var end_gravity := _mean_train_gravity(route, state.distance, tangent)
		var longitudinal := (end_gravity - GRAVITY.dot(tangent) + drive * _engagement(u, estimate) - end_drag) / G0
		_append_state(route, state, index, 0.0, proper.dot(level_up) / G0, proper.dot(right) / G0, longitudinal, 0, curvature)
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


static func _append_state(
	route: Dictionary,
	state: Dictionary,
	section: int,
	bank: float,
	normal: float,
	lateral: float,
	longitudinal: float,
	lsm: int,
	curvature: Vector3
) -> void:
	var up: Vector3 = _level_up(state.tangent).rotated(state.tangent, deg_to_rad(bank))
	var right: Vector3 = state.tangent.cross(up).normalized()
	up = right.cross(state.tangent).normalized()
	route.positions.append(state.position)
	route.tangents.append(state.tangent)
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


static func _level_up(tangent: Vector3) -> Vector3:
	return (Vector3.UP - tangent * tangent.y).normalized()


static func _measure_roll_rates(route: Dictionary) -> void:
	route.roll_rates[0] = 0.0
	for i in range(1, route.positions.size()):
		var previous: Vector3 = _transport_up(route.ups[i - 1], route.tangents[i - 1], route.tangents[i])
		var angle := atan2(route.tangents[i].dot(previous.cross(route.ups[i])), previous.dot(route.ups[i]))
		var dt: float = route.times[i] - route.times[i - 1]
		route.roll_rates[i] = rad_to_deg(angle) / maxf(dt, 0.0001)


static func row_forces_at(
	route: Dictionary, front_distance: float, train_speed: float, row_offset: float
) -> Dictionary:
	var front := _sample_fields(route, front_distance)
	var row := _sample_fields(route, front_distance - row_offset)
	var tangent: Vector3 = row.tangent
	var gravity_along: float = GRAVITY.dot(tangent)
	var gravity_across := GRAVITY - tangent * gravity_along
	if train_speed <= 0.01:
		var support := -GRAVITY
		return {
			"normal": support.dot(row.up) / G0,
			"lateral": support.dot(row.right) / G0,
			"longitudinal": support.dot(tangent) / G0,
			"roll_rate": 0.0,
		}
	var proper: Vector3 = row.curvature * train_speed * train_speed - gravity_across
	var acceleration: float = GRAVITY.dot(front.tangent) + front.longitudinal * G0
	return {
		"normal": proper.dot(row.up) / G0,
		"lateral": proper.dot(row.right) / G0,
		"longitudinal": (acceleration - gravity_along) / G0,
		"roll_rate": row.roll_rate * train_speed / maxf(row.speed, 1.0),
	}


static func _sample_fields(route: Dictionary, distance: float) -> Dictionary:
	var at := fposmod(distance, route.length)
	var low := 0
	var high: int = route.distances.size() - 1
	while low + 1 < high:
		var middle := floori((low + high) * 0.5)
		if route.distances[middle] <= at:
			low = middle
		else:
			high = middle
	var span: float = route.distances[high] - route.distances[low]
	var weight: float = 0.0 if span <= 0.0 else (at - route.distances[low]) / span
	var tangent: Vector3 = route.tangents[low].lerp(route.tangents[high], weight).normalized()
	var up: Vector3 = route.ups[low].lerp(route.ups[high], weight)
	up = (up - tangent * up.dot(tangent)).normalized()
	var right := tangent.cross(up).normalized()
	up = right.cross(tangent).normalized()
	return {
		"tangent": tangent,
		"up": up,
		"right": right,
		"curvature": route.curvatures[low].lerp(route.curvatures[high], weight),
		"longitudinal": lerpf(route.longitudinal_g[low], route.longitudinal_g[high], weight),
		"roll_rate": lerpf(route.roll_rates[low], route.roll_rates[high], weight),
		"speed": lerpf(route.speeds[low], route.speeds[high], weight),
	}


static func _mean_train_gravity(
	route: Dictionary, front_distance: float, front_tangent: Vector3
) -> float:
	if route.is_empty() or not route.has("distances") or route.distances.is_empty():
		return GRAVITY.dot(front_tangent)
	var total := GRAVITY.dot(front_tangent)
	for row in range(1, ROW_OFFSETS.size()):
		var at: float = front_distance - ROW_OFFSETS[row]
		var tangent := STATION_TANGENT if at <= 0.0 else _history_tangent(route, at)
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


static func _transport_up(up: Vector3, old_tangent: Vector3, new_tangent: Vector3) -> Vector3:
	var axis := old_tangent.cross(new_tangent)
	if axis.length_squared() > 0.0000000001:
		up = up.rotated(axis.normalized(), atan2(axis.length(), clampf(old_tangent.dot(new_tangent), -1.0, 1.0)))
	return (up - new_tangent * up.dot(new_tangent)).normalized()


static func _profile(keys: PackedVector2Array, u: float, septic: bool) -> Vector2:
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


static func validate(route: Dictionary) -> PackedStringArray:
	var issues := PackedStringArray()
	var count: int = route.positions.size()
	var fields := ["tangents", "ups", "rights", "curvatures", "banks", "speeds", "normal_g", "lateral_g", "longitudinal_g", "roll_rates", "distances", "times", "section_indices", "lsm_ids"]
	_require(issues, count > 1000, "route has too few samples")
	for field in fields:
		_require(issues, route[field].size() == count, "%s sample count differs" % field)
	if not issues.is_empty():
		return issues
	for i in count:
		var position: Vector3 = route.positions[i]
		var tangent: Vector3 = route.tangents[i]
		var up: Vector3 = route.ups[i]
		var right: Vector3 = route.rights[i]
		_require(issues, position.is_finite() and tangent.is_finite() and up.is_finite() and right.is_finite(), "non-finite frame at sample %d" % i)
		_require(issues, absf(tangent.length_squared() - 1.0) < 0.002 and absf(up.length_squared() - 1.0) < 0.002 and absf(right.length_squared() - 1.0) < 0.002, "non-unit frame at sample %d" % i)
		_require(issues, absf(tangent.dot(up)) < 0.002 and absf(tangent.dot(right)) < 0.002 and absf(up.dot(right)) < 0.002, "non-orthogonal frame at sample %d" % i)
		_require(issues, up.dot(Vector3.UP) > 0.02, "inverted rider frame at sample %d" % i)
		var slow_infrastructure: bool = route.sections[route.section_indices[i]].name in ["Holding brake", "Cliff hold crawl", "Holding release"]
		var minimum_speed := 1.8 if slow_infrastructure else 4.95
		_require(issues, is_finite(route.speeds[i]) and route.speeds[i] > minimum_speed, "invalid or stalled speed at sample %d" % i)
		if i > 0:
			_require(issues, route.distances[i] > route.distances[i - 1] and route.times[i] > route.times[i - 1], "non-monotone route at sample %d" % i)
		if issues.size() > 20:
			return issues
	var analysis: Dictionary = route.analysis
	_require(issues, route.length >= 5400.0 and route.length <= 5600.0, "length %.1f m is outside 5.4–5.6 km" % route.length)
	_require(issues, route.duration >= 158.0 and route.duration <= 165.0, "elapsed time %.1f s is outside 158–165 s" % route.duration)
	_require(issues, analysis.average_speed > 120.0 / 3.6, "elapsed average %.1f km/h does not exceed 120" % (analysis.average_speed * 3.6))
	_require(issues, analysis.top_speed >= 319.0 / 3.6 and analysis.top_speed <= 321.0 / 3.6, "top speed %.1f km/h is not about 320" % (analysis.top_speed * 3.6))
	_require(issues, analysis.elevation_span >= 243.75 and analysis.elevation_span <= 320.0, "elevation span %.1f m misses the record-scale band" % analysis.elevation_span)
	_require(issues, route.positions[0].distance_to(STATION_POSITION) < 0.001 and route.positions[-1].distance_to(STATION_POSITION) < 0.001, "route does not close exactly at the station")
	_require(issues, route.tangents[0].dot(route.tangents[-1]) > 0.99999 and route.ups[0].dot(route.ups[-1]) > 0.99999, "station frame does not close")
	_validate_continuity_kernels(issues)
	_validate_route_seams(route, issues)
	var twisted := _section_named(route, "Twisted 84 m side-drop")
	var pullout := _section_named(route, "6.9 g record pullout")
	var camelback := _section_named(route, "206 m record camelback")
	if not twisted.is_empty():
		var twisted_range := _height_range(route, twisted.start_index, twisted.end_index)
		var twisted_drop: float = route.positions[twisted.start_index].y - twisted_range.x
		_require(issues, twisted_drop >= 82.0 and twisted_drop <= 90.0, "twisted side-drop is %.1f m" % twisted_drop)
		var heading_change := absf(rad_to_deg(atan2(route.tangents[twisted.start_index].cross(route.tangents[twisted.end_index]).y, route.tangents[twisted.start_index].dot(route.tangents[twisted.end_index]))))
		_require(issues, heading_change > 35.0, "twisted side-drop does not change heading")
	if not pullout.is_empty():
		var drop_range := _height_range(route, _section_named(route, "198 m cliff dive").start_index, pullout.end_index)
		var main_drop: float = route.positions[_section_named(route, "198 m cliff dive").start_index].y - drop_range.x
		_require(issues, main_drop >= 195.0 and main_drop <= 202.0, "main drop is %.1f m, not about 197.5 m" % main_drop)
	if not camelback.is_empty():
		var camel_range := _height_range(route, camelback.start_index, camelback.end_index)
		_require(issues, camel_range.y - camel_range.x >= 205.5 and camel_range.y - camel_range.x <= 211.0, "camelback rise is %.1f m, not about 206 m" % (camel_range.y - camel_range.x))
	var grade_names := ["Station · LSM 1", "LSM 1 · record lift", "LSM 2 · cliff launch", "LSM 2 · powered cliff climb", "Holding brake", "Cliff hold crawl", "Holding release", "Tunnel · downhill LSM 3", "Final brakes"]
	var fvd_length := 0.0
	for section in route.sections:
		var section_length: float = section.end_distance - section.start_distance
		if section.name in grade_names:
			_require(issues, section.kind == "GRADE", "infrastructure section '%s' is not grade-driven" % section.name)
		if section.kind == "FVD":
			fvd_length += section_length
		else:
			_require(issues, section.kind == "CLOSURE" or section.name in grade_names, "thrill section '%s' is geometry-driven" % section.name)
		var lower_name: String = section.name.to_lower()
		_require(issues, "inversion" not in lower_name and "helix" not in lower_name and "barrel" not in lower_name, "forbidden inversion/helix element '%s'" % section.name)
		_require(issues, absf(_section_heading_change(route, section)) < 270.0, "section '%s' forms a helix" % section.name)
	_require(issues, fvd_length / route.length > 0.60, "less than 60% of the route is force-vector designed")
	var high_turn := _section_named(route, "320 km/h banked turnaround")
	_require(issues, not high_turn.is_empty() and high_turn.kind == "FVD", "320 km/h turnaround is not FVD")
	var lsm_runs := PackedInt32Array()
	var last_lsm := 0
	for lsm in route.lsm_ids:
		if lsm != last_lsm and lsm != 0:
			lsm_runs.append(lsm)
		last_lsm = lsm
	_require(issues, lsm_runs == PackedInt32Array([1, 2, 3]), "route does not contain exactly three contiguous LSM zones")
	var hold_crawl := _section_named(route, "Cliff hold crawl")
	_require(issues, not hold_crawl.is_empty() and hold_crawl.end_time - hold_crawl.start_time >= 6.5 and hold_crawl.exit_speed <= 2.1, "cliff holding brake does not sustain a physical low-speed hold")
	var closure: Dictionary = route.sections[-1]
	_require(issues, closure.kind == "CLOSURE" and closure.end_distance - closure.start_distance <= route.length * 0.08, "station closure exceeds 8% of route length")
	_require(issues, absf(closure.exit_speed - STATION_SPEED) < 0.1, "station closure does not physically return to station speed")
	var controls: PackedVector3Array = closure.controls
	var start_step: Vector3 = controls[1] - controls[0]
	var end_step: Vector3 = controls[9] - controls[8]
	for i in 4:
		_require(issues, (controls[i + 1] - controls[i]).distance_to(start_step) < 0.0001, "closure start is not C4")
		_require(issues, (controls[9 - i] - controls[8 - i]).distance_to(end_step) < 0.0001, "closure end is not C4")
	var max_positive_usage := 0.0
	var max_negative_usage := 0.0
	var max_combined_usage := 0.0
	var max_jerk := 0.0
	var max_roll_rate := 0.0
	for row in analysis.rows:
		max_positive_usage = maxf(max_positive_usage, row.positive_envelope.usage)
		max_negative_usage = maxf(max_negative_usage, row.negative_envelope.usage)
		max_combined_usage = maxf(max_combined_usage, row.combined_usage)
		max_jerk = maxf(max_jerk, row.peak_jerk)
		max_roll_rate = maxf(max_roll_rate, row.peak_roll_rate)
		_require(issues, row.peak_positive <= 7.01 and row.peak_negative >= -2.51, "row %.2f m exceeds raw normal-G limits" % row.offset)
		_require(issues, row.peak_lateral <= 4.01 and row.peak_longitudinal <= 7.01, "row %.2f m exceeds raw lateral/longitudinal limits" % row.offset)
		_require(issues, row.peak_jerk <= JERK_LIMIT + 0.01 and row.peak_roll_rate <= ROLL_RATE_LIMIT + 0.01, "row %.2f m exceeds jerk/roll limits" % row.offset)
		_require(issues, row.positive_envelope.usage <= 1.001 and row.negative_envelope.usage <= 1.001 and row.lateral_envelope.usage <= 1.001 and row.longitudinal_envelope.usage <= 1.001 and row.combined_usage <= 1.001, "row %.2f m exceeds a filtered force envelope" % row.offset)
	_require(issues, max_positive_usage >= 0.95 and max_negative_usage >= 0.90, "normal-force envelopes are not intentionally used")
	_require(issues, max_combined_usage >= 0.97, "combined-axis envelope is not intentionally used")
	_require(issues, max_jerk >= JERK_LIMIT * 0.93, "force onset frontier is not intentionally used")
	_require(issues, max_roll_rate >= ROLL_RATE_LIMIT * 0.97, "roll-rate frontier is not intentionally used")
	for i in count:
		if route.sections[route.section_indices[i]].kind == "FVD":
			var tangent: Vector3 = route.tangents[i]
			var proper: Vector3 = (route.ups[i] * route.normal_g[i] + route.rights[i] * route.lateral_g[i]) * G0
			var reconstructed: Vector3 = (proper + GRAVITY - tangent * GRAVITY.dot(tangent)) / (route.speeds[i] * route.speeds[i])
			_require(issues, reconstructed.distance_to(route.curvatures[i]) < 0.00002, "FVD force equation mismatch at sample %d" % i)
			if issues.size() > 20:
				break
	_validate_self_clearance(route, issues)
	return issues


static func _require(issues: PackedStringArray, condition: bool, message: String) -> void:
	if not condition:
		issues.append(message)


static func _section_named(route: Dictionary, name: String) -> Dictionary:
	for section in route.sections:
		if section.name == name:
			return section
	return {}


static func _height_range(route: Dictionary, first: int, last: int) -> Vector2:
	var low := INF
	var high := -INF
	for i in range(first, last + 1):
		low = minf(low, route.positions[i].y)
		high = maxf(high, route.positions[i].y)
	return Vector2(low, high)


static func _validate_continuity_kernels(issues: PackedStringArray) -> void:
	for x in [0.0, 1.0]:
		var s5_d1: float = 30.0 * x * x * (1.0 - x) * (1.0 - x)
		var s5_d2: float = 60.0 * x * (1.0 - x) * (1.0 - 2.0 * x)
		var s7_d1: float = 140.0 * pow(x, 3) * pow(1.0 - x, 3)
		var s7_d2: float = 420.0 * x * x - 1680.0 * pow(x, 3) + 2100.0 * pow(x, 4) - 840.0 * pow(x, 5)
		var s7_d3: float = 840.0 * x - 5040.0 * x * x + 8400.0 * pow(x, 3) - 4200.0 * pow(x, 4)
		_require(issues, absf(s5_d1) < 0.000001 and absf(s5_d2) < 0.000001, "quintic force kernel is not C2 at an endpoint")
		_require(issues, absf(s7_d1) < 0.000001 and absf(s7_d2) < 0.000001 and absf(s7_d3) < 0.000001, "septic grade kernel is not C3 at an endpoint")


static func _validate_route_seams(route: Dictionary, issues: PackedStringArray) -> void:
	for section_index in range(1, route.sections.size()):
		var section: Dictionary = route.sections[section_index]
		var seam: int = section.start_index
		var tangent: Vector3 = route.tangents[seam]
		var outgoing_curvature := Vector3.ZERO
		var outgoing_bank := 0.0
		if section.kind == "FVD":
			var state := {
				"tangent": tangent,
				"speed": route.speeds[seam],
				"distance": route.distances[seam],
			}
			var derivative: Dictionary = _fvd_derivative(route, state, section, 0.0)
			outgoing_curvature = derivative.curvature
			outgoing_bank = derivative.bank
		elif section.kind == "GRADE":
			var pitch := _profile(section.pitch, 0.0, true)
			var heading := Vector2(tangent.x, tangent.z).normalized()
			var angle := deg_to_rad(pitch.x)
			var authored_tangent := Vector3(heading.x * cos(angle), sin(angle), heading.y * cos(angle)).normalized()
			_require(issues, rad_to_deg(tangent.angle_to(authored_tangent)) < 0.001, "grade entry tangent jumps at '%s'" % section.name)
			var lift := (Vector3.UP - authored_tangent * authored_tangent.y).normalized()
			outgoing_curvature = lift * deg_to_rad(pitch.y) / section.length
		else:
			outgoing_curvature = _bezier_curvature(section.controls, 0.0)
			_require(issues, _bezier9_derivative(section.controls, 0.0).normalized().dot(tangent) > 0.999999, "closure entry tangent jumps")
		_require(issues, route.curvatures[seam].distance_to(outgoing_curvature) < 0.00005, "curvature jumps at '%s'" % section.name)
		_require(issues, absf(route.banks[seam] - outgoing_bank) < 0.001, "bank jumps at '%s'" % section.name)
		var ds_before: float = route.distances[seam] - route.distances[seam - 1]
		var ds_after: float = route.distances[seam + 1] - route.distances[seam]
		var first_before: Vector3 = (route.curvatures[seam] - route.curvatures[seam - 1]) / ds_before
		var first_after: Vector3 = (route.curvatures[seam + 1] - route.curvatures[seam]) / ds_after
		_require(issues, first_before.distance_to(first_after) < 0.0012, "C3 curvature slope jumps at '%s'" % section.name)
		var ds_outer_before: float = route.distances[seam - 1] - route.distances[seam - 2]
		var ds_outer_after: float = route.distances[seam + 2] - route.distances[seam + 1]
		var previous_first: Vector3 = (route.curvatures[seam - 1] - route.curvatures[seam - 2]) / ds_outer_before
		var next_first: Vector3 = (route.curvatures[seam + 2] - route.curvatures[seam + 1]) / ds_outer_after
		var second_before: Vector3 = (first_before - previous_first) * 2.0 / (ds_before + ds_outer_before)
		var second_after: Vector3 = (next_first - first_after) * 2.0 / (ds_after + ds_outer_after)
		_require(issues, second_before.distance_to(second_after) < 0.0025, "C4 curvature acceleration jumps at '%s'" % section.name)


static func _section_heading_change(route: Dictionary, section: Dictionary) -> float:
	var total := 0.0
	for i in range(section.start_index + 1, section.end_index + 1):
		var before := Vector2(route.tangents[i - 1].x, route.tangents[i - 1].z).normalized()
		var after := Vector2(route.tangents[i].x, route.tangents[i].z).normalized()
		total += atan2(before.x * after.y - before.y * after.x, before.dot(after))
	return rad_to_deg(total)


static func _validate_self_clearance(route: Dictionary, issues: PackedStringArray) -> void:
	const CELL := 4.0
	const CLEARANCE := 3.0
	var cells := {}
	for i in range(0, route.positions.size(), 2):
		var position: Vector3 = route.positions[i]
		var cell := Vector3i(floori(position.x / CELL), floori(position.y / CELL), floori(position.z / CELL))
		for x in range(-1, 2):
			for y in range(-1, 2):
				for z in range(-1, 2):
					var neighbor := cell + Vector3i(x, y, z)
					for other in cells.get(neighbor, []):
						var separation: float = absf(route.distances[i] - route.distances[other])
						separation = minf(separation, route.length - separation)
						if separation > 30.0 and position.distance_to(route.positions[other]) < CLEARANCE:
							issues.append("non-adjacent track violates %.1f m self-clearance near sample %d" % [CLEARANCE, i])
							return
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(i)


static func analyze(route: Dictionary) -> Dictionary:
	var top_speed := _maximum(route.speeds)
	var minimum_height := INF
	var maximum_height := -INF
	var peak_positive := -INF
	var peak_negative := INF
	var peak_lateral := 0.0
	var peak_longitudinal := 0.0
	var peak_roll := 0.0
	var peak_jerk := 0.0
	for i in route.positions.size():
		minimum_height = minf(minimum_height, route.positions[i].y)
		maximum_height = maxf(maximum_height, route.positions[i].y)
		peak_positive = maxf(peak_positive, route.normal_g[i])
		peak_negative = minf(peak_negative, route.normal_g[i])
		peak_lateral = maxf(peak_lateral, absf(route.lateral_g[i]))
		peak_longitudinal = maxf(peak_longitudinal, absf(route.longitudinal_g[i]))
		peak_roll = maxf(peak_roll, absf(route.roll_rates[i]))
		if i > 0:
			var dt: float = route.times[i] - route.times[i - 1]
			if dt > 0:
				var delta := Vector3(route.lateral_g[i] - route.lateral_g[i - 1], route.normal_g[i] - route.normal_g[i - 1], route.longitudinal_g[i] - route.longitudinal_g[i - 1])
				peak_jerk = maxf(peak_jerk, delta.length() / dt)
	var filtered_normal := _filter(_resample(route.times, route.normal_g))
	var filtered_lateral := _filter(_resample(route.times, route.lateral_g))
	var filtered_longitudinal := _filter(_resample(route.times, route.longitudinal_g))
	var positive := _envelope_usage(filtered_normal, POSITIVE_LIMIT, 1.0)
	var negative := _envelope_usage(filtered_normal, NEGATIVE_LIMIT, -1.0)
	var lateral_positive := _envelope_usage(filtered_lateral, LATERAL_LIMIT, 1.0)
	var lateral_negative := _envelope_usage(filtered_lateral, LATERAL_LIMIT, -1.0)
	var longitudinal_positive := _envelope_usage(filtered_longitudinal, LONGITUDINAL_LIMIT, 1.0)
	var longitudinal_negative := _envelope_usage(filtered_longitudinal, LONGITUDINAL_LIMIT, -1.0)
	var combined := 0.0
	for i in filtered_normal.size():
		var normal_limit := 7.0 if filtered_normal[i] >= 0.0 else 2.5
		var n: float = absf(filtered_normal[i]) / normal_limit
		var l: float = absf(filtered_lateral[i]) / 4.0
		var x: float = absf(filtered_longitudinal[i]) / 7.0
		combined = maxf(combined, maxf(sqrt(n * n + l * l), maxf(sqrt(n * n + x * x), sqrt(l * l + x * x))))
	var rows := _analyze_rows(route)
	return {
		"top_speed": top_speed,
		"average_speed": route.length / route.duration,
		"minimum_height": minimum_height,
		"maximum_height": maximum_height,
		"elevation_span": maximum_height - minimum_height,
		"peak_positive": peak_positive,
		"peak_negative": peak_negative,
		"peak_lateral": peak_lateral,
		"peak_longitudinal": peak_longitudinal,
		"peak_roll_rate": peak_roll,
		"peak_jerk": peak_jerk,
		"positive_envelope": positive,
		"negative_envelope": negative,
		"lateral_envelope": lateral_positive if lateral_positive.usage >= lateral_negative.usage else lateral_negative,
		"longitudinal_envelope": longitudinal_positive if longitudinal_positive.usage >= longitudinal_negative.usage else longitudinal_negative,
		"combined_usage": combined,
		"rows": rows,
	}


static func _analyze_rows(route: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for offset in ROW_OFFSETS:
		var normal := PackedFloat32Array()
		var lateral := PackedFloat32Array()
		var longitudinal := PackedFloat32Array()
		var roll := PackedFloat32Array()
		var count: int = route.positions.size()
		normal.resize(count)
		lateral.resize(count)
		longitudinal.resize(count)
		roll.resize(count)
		var peak_positive := -INF
		var peak_negative := INF
		var peak_lateral := 0.0
		var peak_longitudinal := 0.0
		var peak_roll := 0.0
		var peak_jerk := 0.0
		for i in count:
			var forces := row_forces_at(route, route.distances[i], route.speeds[i], offset)
			normal[i] = forces.normal
			lateral[i] = forces.lateral
			longitudinal[i] = forces.longitudinal
			roll[i] = forces.roll_rate
			peak_positive = maxf(peak_positive, normal[i])
			peak_negative = minf(peak_negative, normal[i])
			peak_lateral = maxf(peak_lateral, absf(lateral[i]))
			peak_longitudinal = maxf(peak_longitudinal, absf(longitudinal[i]))
			peak_roll = maxf(peak_roll, absf(roll[i]))
			if i > 0:
				var dt: float = route.times[i] - route.times[i - 1]
				var delta := Vector3(lateral[i] - lateral[i - 1], normal[i] - normal[i - 1], longitudinal[i] - longitudinal[i - 1])
				peak_jerk = maxf(peak_jerk, delta.length() / maxf(dt, 0.0001))
		var filtered_normal := _filter(_resample(route.times, normal))
		var filtered_lateral := _filter(_resample(route.times, lateral))
		var filtered_longitudinal := _filter(_resample(route.times, longitudinal))
		var positive := _envelope_usage(filtered_normal, POSITIVE_LIMIT, 1.0)
		var negative := _envelope_usage(filtered_normal, NEGATIVE_LIMIT, -1.0)
		var lateral_positive := _envelope_usage(filtered_lateral, LATERAL_LIMIT, 1.0)
		var lateral_negative := _envelope_usage(filtered_lateral, LATERAL_LIMIT, -1.0)
		var longitudinal_positive := _envelope_usage(filtered_longitudinal, LONGITUDINAL_LIMIT, 1.0)
		var longitudinal_negative := _envelope_usage(filtered_longitudinal, LONGITUDINAL_LIMIT, -1.0)
		var combined := 0.0
		for i in filtered_normal.size():
			var normal_limit := 7.0 if filtered_normal[i] >= 0.0 else 2.5
			var n: float = absf(filtered_normal[i]) / normal_limit
			var l: float = absf(filtered_lateral[i]) / 4.0
			var x: float = absf(filtered_longitudinal[i]) / 7.0
			combined = maxf(combined, maxf(sqrt(n * n + l * l), maxf(sqrt(n * n + x * x), sqrt(l * l + x * x))))
		result.append({
			"offset": offset,
			"peak_positive": peak_positive,
			"peak_negative": peak_negative,
			"peak_lateral": peak_lateral,
			"peak_longitudinal": peak_longitudinal,
			"peak_roll_rate": peak_roll,
			"peak_jerk": peak_jerk,
			"positive_envelope": positive,
			"negative_envelope": negative,
			"lateral_envelope": lateral_positive if lateral_positive.usage >= lateral_negative.usage else lateral_negative,
			"longitudinal_envelope": longitudinal_positive if longitudinal_positive.usage >= longitudinal_negative.usage else longitudinal_negative,
			"combined_usage": combined,
		})
	return result


static func _resample(times: PackedFloat32Array, values: PackedFloat32Array) -> PackedFloat32Array:
	const HZ := 100.0
	var output := PackedFloat32Array()
	var count := floori(times[-1] * HZ) + 1
	output.resize(count)
	var source := 0
	for i in count:
		var at := i / HZ
		while source + 1 < times.size() and times[source + 1] < at:
			source += 1
		if source + 1 >= times.size():
			output[i] = values[-1]
		else:
			output[i] = lerpf(values[source], values[source + 1], inverse_lerp(times[source], times[source + 1], at))
	return output


static func _filter(values: PackedFloat32Array) -> PackedFloat32Array:
	var output := values
	for q in [0.5411961, 1.3065630]:
		output = _biquad(output, q)
	return output


static func _biquad(values: PackedFloat32Array, q: float) -> PackedFloat32Array:
	const OMEGA := TAU * 5.0 / 100.0
	var cosine := cos(OMEGA)
	var alpha := sin(OMEGA) / (2.0 * q)
	var divisor := 1.0 + alpha
	var b0 := (1.0 - cosine) * 0.5 / divisor
	var b1 := (1.0 - cosine) / divisor
	var b2 := b0
	var a1 := -2.0 * cosine / divisor
	var a2 := (1.0 - alpha) / divisor
	var output := PackedFloat32Array()
	output.resize(values.size())
	var x1: float = values[0]
	var x2 := x1
	var y1 := x1
	var y2 := x1
	for i in values.size():
		var x: float = values[i]
		var y: float = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		output[i] = y
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
	return output


static func _envelope_usage(values: PackedFloat32Array, points: Array, polarity: float) -> Dictionary:
	var worst := {"usage": 0.0, "duration": 0.0, "held": 0.0, "limit": 0.0}
	var held_curve := _held_curve(values, polarity)
	var last_window := mini(held_curve.size() - 1, roundi((points[-1] as Vector2).x * 100.0) + 1)
	for window in range(21, last_window + 1):
		var duration := (window - 1) / 100.0
		var limit := _limit_at(points, duration)
		var held: float = held_curve[window]
		var usage := held / limit
		if usage > worst.usage:
			worst = {"usage": usage, "duration": duration, "held": held, "limit": limit}
	return worst


static func _limit_at(points: Array, duration: float) -> float:
	if duration <= (points[0] as Vector2).x:
		return (points[0] as Vector2).y
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		if duration <= b.x:
			return lerpf(a.y, b.y, inverse_lerp(a.x, b.x, duration))
	return (points[-1] as Vector2).y


static func _held_curve(values: PackedFloat32Array, polarity: float) -> PackedFloat32Array:
	var count := values.size()
	var signed := PackedFloat32Array()
	var left := PackedInt32Array()
	var right := PackedInt32Array()
	var best := PackedFloat32Array()
	signed.resize(count)
	left.resize(count)
	right.resize(count)
	best.resize(count + 1)
	best.fill(-INF)
	for i in count:
		signed[i] = values[i] * polarity
	var stack := PackedInt32Array()
	for i in count:
		while not stack.is_empty() and signed[stack[-1]] >= signed[i]:
			stack.remove_at(stack.size() - 1)
		left[i] = -1 if stack.is_empty() else stack[-1]
		stack.append(i)
	stack.clear()
	for i in range(count - 1, -1, -1):
		while not stack.is_empty() and signed[stack[-1]] >= signed[i]:
			stack.remove_at(stack.size() - 1)
		right[i] = count if stack.is_empty() else stack[-1]
		stack.append(i)
	for i in count:
		var window := right[i] - left[i] - 1
		best[window] = maxf(best[window], signed[i])
	for window in range(count - 1, 0, -1):
		best[window] = maxf(best[window], best[window + 1])
	return best


static func _maximum(values: PackedFloat32Array) -> float:
	var result := -INF
	for value in values:
		result = maxf(result, value)
	return result
