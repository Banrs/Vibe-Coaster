extends SceneTree

const RideGenerator := preload("res://generator.gd")

const STORY_IDS := [
	"station-launch",
	"opener",
	"act-one",
	"escarpment-climb",
	"clifftop-suspense",
	"cliff-dive",
	"tunnel-lsm3",
	"marquee-camelback",
	"raceway-return",
	"brakes-station-capture",
]

# Preserved seed-42 audit and raw-channel-sidecar values. The sidecars preserve no
# raw-array fingerprints, so the gate uses explicit effect sizes across independent dimensions.
const LEGACY_LENGTH_M := 9519.225842
const LEGACY_DURATION_S := 232.618384
const LEGACY_HEIGHT_SPAN_M := 381.6006
const LEGACY_TOP_SPEED_MPS := 338.525299 / 3.6
const LEGACY_PEAK_ABS_FORCE_G := 5.727871417999268

var _errors := PackedStringArray()


func _initialize() -> void:
	var route := RideGenerator.build(42)
	_expect(not route.is_empty() and route.get("ok", true) and route.get("errors", []).is_empty(),
		"seed 42 generates successfully: errors=%s failure=%s" % [
			str(route.get("errors", [])), str(route.get("failure", {})),
		])
	_expect(route.get("generator_version", "") == "time-domain-v1",
		"the public route identifies the time-domain generator")
	_expect(_story_windows_are_complete(route),
		"ten stable, ordered, non-empty story windows are public")
	_expect(_diagnostic_windows_are_stable(route),
		"diagnostic windows have unique stable IDs and distinguish repeated roles")
	_expect(_propulsion_and_work_are_honest(route),
		"propulsion IDs are exactly 1/2/3 and generation integrates once without repair")
	_expect(_has_material_legacy_delta(route),
		"seed 42 materially differs from legacy in at least three measured dimensions")
	_expect(_climb_is_unpowered_and_slows(route),
		"the post-LSM2 escarpment climb is unpowered and decelerates into the slow crest")
	_expect(_dive_is_physical(route),
		"the full cliff dive is monotonic and steep while its literal core stays unloaded")
	_expect(_lsm3_feeds_camelback(route),
		"LSM3 reaches the 340 km/h class and directly feeds the marquee camelback")
	_expect(_launch_speeds_match_the_default_vision(route),
		"the entry launch and LSM2 reach their explicit near-future speed classes")
	_expect(_public_arrays_are_shaped(route),
		"all public trajectory arrays are packed, aligned, and nontrivial")
	_expect(_public_trajectory_is_physical(route),
		"public arrays form a finite monotone coherent trajectory and orthonormal frame")
	_expect(_vertical_features_are_material(route),
		"the climb, dive, and camelback have material rise-apex-fall geometry")
	_expect(_inversions_are_material(route),
		"at least two distinct inversion windows put rider-up substantially below world-up")
	_expect(_turning_features_are_material(route),
		"the cutback, wave turn, and return create real lateral displacement and heading change")
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _story_windows_are_complete(route: Dictionary) -> bool:
	var windows: Array = route.get("gesture_windows", [])
	if windows.size() != STORY_IDS.size():
		return false
	var previous_last := -1
	for index in windows.size():
		var window: Dictionary = windows[index]
		var first := int(window.get("first", -1))
		var last := int(window.get("last", -1))
		if window.get("story_slot_id", "") != STORY_IDS[index] or first > last \
				or first != previous_last + 1:
			return false
		previous_last = last
	return previous_last == route.get("times", []).size() - 1


func _diagnostic_windows_are_stable(route: Dictionary) -> bool:
	var seen := {}
	var retained := {}
	var giant_inversions := []
	for gesture in route.get("gesture_windows", []):
		for window in [gesture] + gesture.get("role_windows", []):
			var window_id := str(window.get("window_id", ""))
			if window_id.is_empty() or seen.has(window_id):
				return false
			seen[window_id] = true
			var kind := str(window.get("diagnostic_kind", ""))
			if not kind.is_empty():
				retained[kind] = true
			if gesture.get("story_slot_id") == "act-one" \
					and window.get("id") == "giant-inversion":
				giant_inversions.append(window)
	if not retained.has_all([
		"hill", "immelmann", "loop", "cutback", "twisted_drop", "dive",
		"wave_turn", "overbank", "turn",
	]):
		return false
	return giant_inversions.size() == 2 \
		and giant_inversions[0].get("occurrence") == 0 \
		and giant_inversions[0].get("diagnostic_kind") == "immelmann" \
		and giant_inversions[0].get("window_id") \
			== "act-one/giant-inversion/00-immelmann" \
		and giant_inversions[1].get("occurrence") == 1 \
		and giant_inversions[1].get("diagnostic_kind") == "loop" \
		and giant_inversions[1].get("window_id") == "act-one/giant-inversion/01-loop"


func _propulsion_and_work_are_honest(route: Dictionary) -> bool:
	var ids: Variant = route.get("propulsion_ids", PackedInt32Array())
	var positive := PackedInt32Array()
	for value in ids:
		if value > 0 and not positive.has(value):
			positive.append(value)
	var stats: Dictionary = route.get("generation_stats", {})
	return positive == PackedInt32Array([1, 2, 3]) \
		and stats.get("accepted_integrations", -1) == 1 and stats.get("repair_count", -1) == 0


func _has_material_legacy_delta(route: Dictionary) -> bool:
	if not _public_arrays_are_shaped(route):
		return false
	var height_span := _height_span(route.positions)
	var peak_speed := _max_abs(route.speeds)
	var peak_force := maxf(_max_abs(route.normal_g),
		maxf(_max_abs(route.lateral_g), _max_abs(route.longitudinal_g)))
	var changed := 0
	changed += int(absf(float(route.get("length", 0.0)) - LEGACY_LENGTH_M) >= 100.0)
	changed += int(absf(float(route.get("duration", 0.0)) - LEGACY_DURATION_S) >= 2.0)
	changed += int(absf(height_span - LEGACY_HEIGHT_SPAN_M) >= 5.0)
	changed += int(absf(peak_speed - LEGACY_TOP_SPEED_MPS) >= 0.5)
	changed += int(absf(peak_force - LEGACY_PEAK_ABS_FORCE_G) >= 0.1)
	return changed >= 3


func _climb_is_unpowered_and_slows(route: Dictionary) -> bool:
	var climb := _role(route, "escarpment-climb", "unpowered-climb")
	var crest := _role(route, "clifftop-suspense", "slow-crest")
	if climb.is_empty() or crest.is_empty():
		return false
	var first := int(climb.first)
	var last := int(climb.last)
	var crest_duration := float(route.times[int(crest.last)]) - float(route.times[int(crest.first)])
	return _all_propulsion_zero(route, first, int(crest.last)) \
		and route.speeds[last] < route.speeds[first] - 10.0 \
		and route.speeds[int(crest.first)] <= 22.0 \
		and crest_duration >= 2.9 and crest_duration <= 4.2

func _dive_is_physical(route: Dictionary) -> bool:
	var dive := _window(route, "cliff-dive")
	var core := _role(route, "cliff-dive", "core")
	if dive.is_empty() or core.is_empty():
		return false
	var dive_first := int(dive.first)
	var dive_last := int(dive.last)
	for index in range(dive_first + 1, dive_last + 1):
		if route.positions[index].y >= route.positions[index - 1].y:
			return false
	var drop_m := float(route.positions[dive_first].y - route.positions[dive_last].y)
	var minimum_tangent_y := 1.0
	for index in range(dive_first, dive_last + 1):
		minimum_tangent_y = minf(minimum_tangent_y, route.tangents[index].y)
	var maximum_abs_normal_g := 0.0
	for index in range(int(core.first), int(core.last) + 1):
		maximum_abs_normal_g = maxf(maximum_abs_normal_g, absf(float(route.normal_g[index])))
	return drop_m >= 140.0 and drop_m <= 175.0 \
		and minimum_tangent_y <= -sin(deg_to_rad(75.0)) \
		and maximum_abs_normal_g <= 0.35


func _lsm3_feeds_camelback(route: Dictionary) -> bool:
	var boost := _role(route, "tunnel-lsm3", "core")
	var camel := _window(route, "marquee-camelback")
	if boost.is_empty() or camel.is_empty():
		return false
	var first := int(boost.first)
	var last := int(boost.last)
	for index in range(first, last + 1):
		if route.propulsion_ids[index] != 3:
			return false
	return route.speeds[last] >= 90.0 and route.speeds[last] <= 98.0 \
		and route.speeds[last] >= route.speeds[first] + 20.0 and int(camel.first) == last + 1


func _launch_speeds_match_the_default_vision(route: Dictionary) -> bool:
	var launch := _window(route, "station-launch")
	var lsm2 := _role(route, "escarpment-climb", "lsm2")
	if launch.is_empty() or lsm2.is_empty():
		return false
	var launch_speed := float(route.speeds[int(launch.last)])
	var lsm2_speed := float(route.speeds[int(lsm2.last)])
	return launch_speed >= 85.0 and launch_speed <= 98.0 \
		and lsm2_speed >= 57.0 and lsm2_speed <= 64.0


func _public_arrays_are_shaped(route: Dictionary) -> bool:
	var keys := ["times", "distances", "positions", "tangents", "ups", "rights", "curvatures",
		"banks", "speeds", "normal_g", "lateral_g", "longitudinal_g", "drive_g", "roll_rates",
		"gesture_indices", "propulsion_ids", "minimum_speeds"]
	var count := -1
	for key in keys:
		var values: Variant = route.get(key)
		if not _is_packed(values):
			return false
		if count < 0:
			count = values.size()
		elif values.size() != count:
			return false
	return count >= 2


func _public_trajectory_is_physical(route: Dictionary) -> bool:
	if not _public_arrays_are_shaped(route):
		return false
	var count: int = route.times.size()
	var duration := float(route.times[-1]) - float(route.times[0])
	var distance_length := float(route.distances[-1]) - float(route.distances[0])
	if not _near(float(route.get("duration", NAN)), duration, maxf(0.0001, duration * 0.000001)) \
			or not _near(float(route.get("length", NAN)), distance_length,
				maxf(0.01, distance_length * 0.000001)):
		return false
	var chord_length := 0.0
	for index in count:
		if not route.positions[index].is_finite() or not route.tangents[index].is_finite() \
				or not route.ups[index].is_finite() or not route.rights[index].is_finite() \
				or not route.curvatures[index].is_finite():
			return false
		for values in [route.times, route.distances, route.banks, route.speeds,
				route.normal_g, route.lateral_g, route.longitudinal_g, route.drive_g,
				route.roll_rates, route.minimum_speeds]:
			if not is_finite(float(values[index])):
				return false
		var tangent: Vector3 = route.tangents[index]
		var up: Vector3 = route.ups[index]
		var right: Vector3 = route.rights[index]
		if absf(tangent.length_squared() - 1.0) > 0.002 \
				or absf(up.length_squared() - 1.0) > 0.002 \
				or absf(right.length_squared() - 1.0) > 0.002 \
				or absf(tangent.dot(up)) > 0.002 \
				or absf(tangent.dot(right)) > 0.002 or absf(up.dot(right)) > 0.002 \
				or right.distance_to(tangent.cross(up).normalized()) > 0.002 \
				or float(route.speeds[index]) < 0.0:
			return false
		if index == 0:
			continue
		var dt := float(route.times[index]) - float(route.times[index - 1])
		var ds := float(route.distances[index]) - float(route.distances[index - 1])
		var chord: Vector3 = route.positions[index] - route.positions[index - 1]
		chord_length += chord.length()
		var integrated_ds := 0.5 * (float(route.speeds[index - 1]) \
			+ float(route.speeds[index])) * dt
		if dt <= 0.0 or ds < 0.0 \
				or absf(ds - integrated_ds) > maxf(0.005, integrated_ds * 0.01) \
				or chord.length() > ds + maxf(0.005, ds * 0.01) \
				or (chord.length_squared() > 0.00000001 \
					and chord.normalized().dot(
						(route.tangents[index - 1] + route.tangents[index]).normalized()) < 0.995):
			return false
	return absf(chord_length - distance_length) <= maxf(0.05, distance_length * 0.0001)


func _vertical_features_are_material(route: Dictionary) -> bool:
	var climb := _window(route, "escarpment-climb")
	var crest := _window(route, "clifftop-suspense")
	var dive := _role(route, "cliff-dive", "core")
	var camel := _window(route, "marquee-camelback")
	if climb.is_empty() or crest.is_empty() or dive.is_empty() or camel.is_empty():
		return false
	var climb_start := float(route.positions[int(climb.first)].y)
	var crest_high := _maximum_height(route, int(crest.first), int(crest.last))
	var dive_drop := float(route.positions[int(dive.first)].y) \
		- float(route.positions[int(dive.last)].y)
	var camel_first := int(camel.first)
	var camel_last := int(camel.last)
	var apex := _maximum_height_index(route, camel_first, camel_last)
	var span := camel_last - camel_first
	var prominence := float(route.positions[apex].y) \
		- maxf(float(route.positions[camel_first].y), float(route.positions[camel_last].y))
	var horizontal_delta: Vector3 = route.positions[camel_last] - route.positions[camel_first]
	horizontal_delta.y = 0.0
	var width_height_ratio := horizontal_delta.length() / prominence if prominence > 0.0 else 0.0
	return crest_high - climb_start >= 100.0 and dive_drop >= 100.0 \
		and apex >= camel_first + maxi(1, int(span / 5.0)) \
		and apex <= camel_last - maxi(1, int(span / 5.0)) \
		and prominence >= 240.0 and prominence <= 260.0 \
		and width_height_ratio >= 3.1 and width_height_ratio <= 3.9


func _inversions_are_material(route: Dictionary) -> bool:
	if not _public_arrays_are_shaped(route):
		return false
	var named_physical := 0
	for role in _window(route, "act-one").get("role_windows", []):
		if role.get("diagnostic_kind", "") in ["immelmann", "loop"] \
				and _minimum_up_dot(route, int(role.first), int(role.last)) <= -0.5:
			named_physical += 1
	var actual_windows := 0
	var inverted_start := -1
	for index in route.ups.size():
		var inverted: bool = route.ups[index].dot(Vector3.UP) <= -0.5
		if inverted and inverted_start < 0:
			inverted_start = index
		elif not inverted and inverted_start >= 0:
			if float(route.times[index - 1]) - float(route.times[inverted_start]) >= 0.1:
				actual_windows += 1
			inverted_start = -1
	if inverted_start >= 0 \
			and float(route.times[-1]) - float(route.times[inverted_start]) >= 0.1:
		actual_windows += 1
	return named_physical >= 2 and actual_windows >= 2


func _turning_features_are_material(route: Dictionary) -> bool:
	var cutback := _diagnostic_role(route, "act-one", "cutback")
	var wave := _diagnostic_role(route, "act-one", "wave_turn")
	var raceway := _window(route, "raceway-return")
	return _window_turns(route, cutback, 5.0, deg_to_rad(20.0)) \
		and _window_turns(route, wave, 10.0, deg_to_rad(20.0)) \
		and _window_turns(route, raceway, 25.0, deg_to_rad(25.0))


func _window_turns(
	route: Dictionary, window: Dictionary, minimum_lateral_m: float, minimum_heading_rad: float
) -> bool:
	if window.is_empty():
		return false
	var first := int(window.first)
	var last := int(window.last)
	var forward := Vector3(route.tangents[first].x, 0.0, route.tangents[first].z)
	if forward.length_squared() <= 0.000001:
		return false
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var origin: Vector3 = route.positions[first]
	var maximum_lateral := 0.0
	var maximum_heading := 0.0
	for index in range(first, last + 1):
		maximum_lateral = maxf(maximum_lateral,
			absf((route.positions[index] - origin).dot(right)))
		var heading := Vector3(route.tangents[index].x, 0.0, route.tangents[index].z)
		if heading.length_squared() > 0.000001:
			maximum_heading = maxf(maximum_heading,
				acos(clampf(forward.dot(heading.normalized()), -1.0, 1.0)))
	return maximum_lateral >= minimum_lateral_m and maximum_heading >= minimum_heading_rad


func _diagnostic_role(route: Dictionary, story_id: String, kind: String) -> Dictionary:
	for role in _window(route, story_id).get("role_windows", []):
		if role.get("diagnostic_kind", "") == kind:
			return role
	return {}


func _maximum_height(route: Dictionary, first: int, last: int) -> float:
	return float(route.positions[_maximum_height_index(route, first, last)].y)


func _maximum_height_index(route: Dictionary, first: int, last: int) -> int:
	var result := first
	for index in range(first + 1, last + 1):
		if route.positions[index].y > route.positions[result].y:
			result = index
	return result


func _minimum_up_dot(route: Dictionary, first: int, last: int) -> float:
	var result := INF
	for index in range(first, last + 1):
		result = minf(result, route.ups[index].dot(Vector3.UP))
	return result


func _near(a: float, b: float, tolerance: float) -> bool:
	return is_finite(a) and is_finite(b) and absf(a - b) <= tolerance


func _role(route: Dictionary, story_id: String, role_id: String) -> Dictionary:
	var window := _window(route, story_id)
	for role in window.get("role_windows", []):
		if role.get("id", "") == role_id:
			return role
	return {}


func _window(route: Dictionary, story_id: String) -> Dictionary:
	for window in route.get("gesture_windows", []):
		if window.get("story_slot_id", "") == story_id:
			return window
	return {}


func _all_propulsion_zero(route: Dictionary, first: int, last: int) -> bool:
	for index in range(first, last + 1):
		if route.propulsion_ids[index] != 0:
			return false
	return true


func _height_span(positions: PackedVector3Array) -> float:
	var low := positions[0].y
	var high := low
	for position in positions:
		low = minf(low, position.y)
		high = maxf(high, position.y)
	return high - low


func _max_abs(values: Variant) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, absf(float(value)))
	return result


func _is_packed(value: Variant) -> bool:
	return value is PackedFloat32Array or value is PackedFloat64Array \
		or value is PackedInt32Array or value is PackedVector3Array


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
