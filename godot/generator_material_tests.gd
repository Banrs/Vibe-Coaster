extends SceneTree

const RideGenerator := preload("res://generator.gd")
const G0 := 9.80665

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
	_expect(_lsm2_speed_matches_the_default_vision(route),
		"LSM2 reaches its explicit near-future speed class")
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
	_check_station_launch_contract(route)
	_check_opener_contract(route)
	_check_act_one_contract(route)
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


func _lsm2_speed_matches_the_default_vision(route: Dictionary) -> bool:
	var lsm2 := _role(route, "escarpment-climb", "lsm2")
	if lsm2.is_empty():
		return false
	var lsm2_speed := float(route.speeds[int(lsm2.last)])
	return lsm2_speed >= 57.0 and lsm2_speed <= 64.0


func _public_arrays_are_shaped(route: Dictionary) -> bool:
	var keys := ["times", "distances", "positions", "tangents", "ups", "rights", "curvatures",
		"banks", "speeds", "normal_g", "lateral_g", "longitudinal_g", "drive_g", "roll_rates",
		"span_indices", "gesture_indices", "propulsion_ids", "minimum_speeds"]
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


func _check_station_launch_contract(route: Dictionary) -> void:
	var launch := _window(route, "station-launch")
	if launch.is_empty():
		_expect(false, "station-launch public window is missing"); return
	var roles: Array = launch.get("role_windows", [])
	_expect(roles.size() == 1, "station-launch has %d roles; required 1" % roles.size())
	if roles.size() == 1:
		var role: Dictionary = roles[0]
		_expect([role.get("id"), role.get("diagnostic_kind"), role.get("window_id")] == [
			"launch", "launch", "station-launch/launch/00-launch"],
			"station-launch role identity observed %s; required launch/launch/station-launch/launch/00-launch" %
				str([role.get("id"), role.get("diagnostic_kind"), role.get("window_id")]))
		_expect(int(role.first) == int(launch.first) and int(role.last) == int(launch.last) \
			and int(role.first_span) == int(launch.first_span) \
			and int(role.last_span) == int(launch.last_span),
			"station-launch role must contiguously own the whole window")
	var first := int(launch.first); var last := int(launch.last)
	_expect_range("station-launch start speed", float(route.speeds[first]), 5.999, 6.001, "m/s")
	_expect_range("station-launch exit speed", float(route.speeds[last]), 75.0, 78.0, "m/s")
	var bad_id := -1; var peak_drive := 0.0; var minimum_drive := INF
	var maximum_height_delta := 0.0; var maximum_abs_tangent_y := 0.0; var minimum_up_dot := INF
	var forward := Vector3(route.tangents[first].x, 0.0, route.tangents[first].z).normalized()
	var right := forward.cross(Vector3.UP); var maximum_lateral := 0.0
	for index in range(first, last + 1):
		peak_drive = maxf(peak_drive, float(route.drive_g[index]))
		minimum_drive = minf(minimum_drive, float(route.drive_g[index]))
		maximum_height_delta = maxf(maximum_height_delta,
			absf(route.positions[index].y - route.positions[first].y))
		maximum_abs_tangent_y = maxf(maximum_abs_tangent_y, absf(route.tangents[index].y))
		maximum_lateral = maxf(maximum_lateral,
			absf((route.positions[index] - route.positions[first]).dot(right)))
		minimum_up_dot = minf(minimum_up_dot, route.ups[index].dot(Vector3.UP))
		if bad_id < 0 and int(route.propulsion_ids[index]) != 1:
			bad_id = index
	_expect(bad_id < 0, "station-launch sample %d uses propulsion ID %d; required ID 1" % [
		bad_id, int(route.propulsion_ids[bad_id]) if bad_id >= 0 else 1])
	_expect_range("station-launch peak drive", peak_drive, 3.8, 4.2, "g")
	_expect_min("station-launch minimum drive", minimum_drive, 0.0, "g")
	_expect_min("station-launch contiguous drive >= 3.8 g hold",
		_held_at_least(route.drive_g, route.times, launch, 3.8), 1.3, "s")
	_expect_max("station-launch vertical deviation", maximum_height_delta, 0.1, "m")
	_expect_max("station-launch absolute tangent vertical component",
		maximum_abs_tangent_y, sin(deg_to_rad(1.0)), "ratio")
	_expect_max("station-launch lateral deviation", maximum_lateral, 0.1, "m")
	_expect_max("station-launch heading excursion", _turn_measure(route, launch).x, 1.0, "deg")
	_expect_min("station-launch minimum rider-up dot world-up", minimum_up_dot, 0.999, "ratio")
	_expect_max("station-launch sampled normal/lateral/drive onset magnitude",
		_sampled_peak_vector_onset(route, first, last), 24.5, "g/s")


func _check_opener_contract(route: Dictionary) -> void:
	var whole := _window(route, "opener")
	if whole.is_empty():
		_expect(false, "opener public window is missing"); return
	var roles: Array = whole.get("role_windows", [])
	var expected := [
		["twisted-drop", "twisted_drop", "opener/twisted-drop/00-twisted_drop"],
		["teardrop", "overbank", "opener/teardrop/00-overbank"],
		["release", "hill", "opener/release/00-hill"],
	]
	_expect(roles.size() == expected.size(), "opener has %d roles; required %d" % [
		roles.size(), expected.size()])
	if roles.size() != expected.size():
		return
	var next_sample := int(whole.first); var next_span := int(whole.first_span)
	for index in roles.size():
		var role: Dictionary = roles[index]
		_expect([role.get("id"), role.get("diagnostic_kind"), role.get("window_id")] \
			== expected[index], "opener role %d identity observed %s; required %s" % [
			index, str([role.get("id"), role.get("diagnostic_kind"), role.get("window_id")]),
			str(expected[index])])
		_expect(int(role.first) == next_sample and int(role.first_span) == next_span,
			"opener role %d starts sample/span %d/%d; required %d/%d" % [index,
				int(role.first), int(role.first_span), next_sample, next_span])
		next_sample = int(role.last) + 1; next_span = int(role.last_span) + 1
	_expect(next_sample == int(whole.last) + 1 and next_span == int(whole.last_span) + 1,
		"opener roles do not contiguously cover the whole window")
	var first := int(whole.first); var last := int(whole.last)
	var drop: Dictionary = roles[0]
	var apex := _maximum_height_index(route, int(drop.first), int(drop.last)); var nadir := apex
	for index in range(apex + 1, int(drop.last) + 1):
		if route.positions[index].y < route.positions[nadir].y:
			nadir = index
	var non_descent := -1
	var min_normal := INF; var max_normal := -INF; var peak_lateral := 0.0
	var peak_drive := 0.0; var peak_roll := 0.0; var maximum_energy_excess := -INF
	var initial_energy := 0.5 * float(route.speeds[first]) ** 2 + G0 * route.positions[first].y
	var previous_energy := initial_energy
	var resistance_work := 0.0
	for index in range(first, last + 1):
		min_normal = minf(min_normal, float(route.normal_g[index]))
		max_normal = maxf(max_normal, float(route.normal_g[index]))
		peak_lateral = maxf(peak_lateral, absf(float(route.lateral_g[index])))
		peak_drive = maxf(peak_drive, absf(float(route.drive_g[index])))
		peak_roll = maxf(peak_roll, absf(float(route.roll_rates[index])))
		if index > apex and index <= nadir and non_descent < 0 \
				and route.positions[index].y >= route.positions[index - 1].y:
			non_descent = index
		if index > first:
			var energy := 0.5 * float(route.speeds[index]) ** 2 + G0 * route.positions[index].y
			var interval_work := -0.5 * G0 * (float(route.longitudinal_g[index - 1]) \
				+ float(route.longitudinal_g[index])) \
				* (float(route.distances[index]) - float(route.distances[index - 1]))
			maximum_energy_excess = maxf(maximum_energy_excess,
				energy - previous_energy - maxf(0.5, interval_work * 0.001))
			previous_energy = energy
			resistance_work += interval_work
	_expect(_all_propulsion_zero(route, first, last), "opener propulsion IDs must all be 0")
	_expect_max("opener absolute drive", peak_drive, 0.000001, "g")
	_expect_range("twisted-drop prominence", _prominence(route, drop), 100.0, 140.0, "m")
	_expect_min("twisted-drop apex-to-nadir drop",
		route.positions[apex].y - route.positions[nadir].y, 100.0, "m")
	_expect(non_descent < 0, "twisted-drop apex-to-nadir descent stops being strict at sample %d" % non_descent)
	_expect_min("twisted-drop lateral range", _turn_measure(route, drop).y, 5.0, "m")
	_expect_min("opener minimum rider-up dot world-up", _minimum_up_dot(route, first, last), 0.15, "ratio")
	_expect_range("opener unwrapped heading excursion", _turn_measure(route, whole).x, 60.0, 160.0, "deg")
	_expect_range("opener handoff speed", float(route.speeds[last]), 61.5, 62.5, "m/s")
	_expect_max("opener handoff height delta", absf(route.positions[last].y - route.positions[first].y), 10.0, "m")
	_expect_max("opener handoff pitch", absf(rad_to_deg(asin(clampf(route.tangents[last].y, -1.0, 1.0)))), 3.0, "deg")
	_expect_min("opener handoff up-dot", route.ups[last].dot(Vector3.UP), 0.99, "ratio")
	_expect_min("opener minimum normal", min_normal, -1.0, "g")
	_expect_max("opener maximum normal", max_normal, 5.2, "g")
	_expect_max("opener peak absolute lateral", peak_lateral, 1.5, "g")
	_expect_max("opener peak absolute roll rate", peak_roll, 120.0, "deg/s")
	_expect_max("opener sampled normal/lateral/drive onset magnitude",
		_sampled_peak_vector_onset(route, first, last), 24.5, "g/s")
	var analytic_onset: Variant = whole.get("peak_analytic_normal_onset_gps")
	_expect(typeof(analytic_onset) == TYPE_FLOAT and is_finite(float(analytic_onset)),
		"opener exposes finite peak_analytic_normal_onset_gps; observed %s" % str(analytic_onset))
	if typeof(analytic_onset) == TYPE_FLOAT:
		_expect_max("opener analytic normal onset", float(analytic_onset), 24.5, "g/s")
	_expect_max("opener monotonic specific-energy excess", maximum_energy_excess, 0.0, "J/kg")
	var energy_loss := initial_energy - previous_energy
	_expect_min("opener specific-energy loss", energy_loss, 800.0, "J/kg")
	_expect_max("opener resistance-work closure", absf(energy_loss - resistance_work),
		maxf(0.5, resistance_work * 0.001), "J/kg")
	var launch := _window(route, "station-launch")
	var sequence_duration := float(route.times[last]) - float(route.times[int(launch.first)])
	var sequence_distance := float(route.distances[last]) - float(route.distances[int(launch.first)])
	var sequence_roles: Array = launch.get("role_windows", []) + roles
	for role in sequence_roles:
		_expect_max("launch/opener %s time share" % role.id,
			(float(route.times[int(role.last)]) - float(route.times[int(role.first)])) / sequence_duration,
			0.5, "ratio")
		_expect_max("launch/opener %s distance share" % role.id,
			(float(route.distances[int(role.last)]) - float(route.distances[int(role.first)])) / sequence_distance,
			0.5, "ratio")


func _check_act_one_contract(route: Dictionary) -> void:
	var whole := _window(route, "act-one")
	if whole.is_empty():
		_expect(false, "act-one public window is missing"); return
	var roles: Array = whole.get("role_windows", [])
	var expected := [
		["giant-inversion", "immelmann", "act-one/giant-inversion/00-immelmann"],
		["cutback", "cutback", "act-one/cutback/00-cutback"],
		["giant-inversion", "loop", "act-one/giant-inversion/01-loop"],
		["airtime-hills", "hill", "act-one/airtime-hills/00-hill"],
		["wave-turn", "wave_turn", "act-one/wave-turn/00-wave_turn"],
	]
	_expect(roles.size() == expected.size(), "act-one has %d roles; required %d" % [
		roles.size(), expected.size()])
	if roles.size() != expected.size():
		return
	var next_sample := int(whole.first); var next_span := int(whole.first_span)
	for index in roles.size():
		var role: Dictionary = roles[index]; var identity: Array = expected[index]
		_expect([role.get("id"), role.get("diagnostic_kind"), role.get("window_id")] == identity,
			"act-one role %d identity observed %s; required %s" % [index, str([
				role.get("id"), role.get("diagnostic_kind"), role.get("window_id")]), str(identity)])
		_expect(int(role.first) == next_sample and int(role.first_span) == next_span,
			"act-one role %d starts sample/span %d/%d; required %d/%d" % [index,
				int(role.first), int(role.first_span), next_sample, next_span])
		next_sample = int(role.last) + 1; next_span = int(role.last_span) + 1
	_expect(next_sample == int(whole.last) + 1 and next_span == int(whole.last_span) + 1,
		"act-one roles end sample/span %d/%d; whole ends %d/%d" % [next_sample - 1,
			next_span - 1, int(whole.last), int(whole.last_span)])
	var first := int(whole.first); var last := int(whole.last)
	var entry: Vector3 = route.positions[first]; var exit: Vector3 = route.positions[last]
	_expect_range("act-one entry speed", float(route.speeds[first]), 61.5, 62.5, "m/s")
	_expect_max("act-one entry pitch", absf(rad_to_deg(asin(clampf(route.tangents[first].y,
		-1.0, 1.0)))), 3.0, "deg")
	_expect_min("act-one entry up-dot", route.ups[first].dot(Vector3.UP), 0.99, "ratio")
	_expect_range("act-one exit speed", float(route.speeds[last]), 50.0, 57.0, "m/s")
	_expect_max("act-one entry/exit height delta", absf(exit.y - entry.y), 5.0, "m")
	_expect_max("act-one exit pitch", absf(rad_to_deg(asin(clampf(route.tangents[last].y, -1.0, 1.0)))), 3.0, "deg")
	_expect_min("act-one exit up-dot", route.ups[last].dot(Vector3.UP), 0.99, "ratio")
	var minimum_normal := INF; var maximum_normal := -INF
	var peak_lateral := 0.0; var peak_roll_deg_s := 0.0; var peak_drive := 0.0
	var bad_propulsion_sample := -1; var bad_propulsion_id := 0
	for index in range(first, last + 1):
		minimum_normal = minf(minimum_normal, float(route.normal_g[index]))
		maximum_normal = maxf(maximum_normal, float(route.normal_g[index]))
		peak_lateral = maxf(peak_lateral, absf(float(route.lateral_g[index])))
		peak_roll_deg_s = maxf(peak_roll_deg_s, absf(float(route.roll_rates[index])))
		peak_drive = maxf(peak_drive, absf(float(route.drive_g[index])))
		if bad_propulsion_sample < 0 and int(route.propulsion_ids[index]) != 0:
			bad_propulsion_sample = index; bad_propulsion_id = int(route.propulsion_ids[index])
	_expect(bad_propulsion_sample < 0, "act-one sample %d propulsion ID %d; required 0" % [
		bad_propulsion_sample, bad_propulsion_id])
	_expect_max("act-one absolute drive", peak_drive, 0.000001, "g")
	_expect_min("act-one minimum normal", minimum_normal, -1.0, "g")
	_expect_max("act-one maximum normal", maximum_normal, 5.2, "g")
	_expect_max("act-one peak absolute lateral", peak_lateral, 1.5, "g")
	_expect_max("act-one peak absolute roll rate", peak_roll_deg_s, 120.0, "deg/s")
	var maximum_onset := 0.0
	for index in range(maxi(first, 1), last + 1):
		maximum_onset = maxf(maximum_onset,
			absf(float(route.normal_g[index]) - float(route.normal_g[index - 1])) \
			/ (float(route.times[index]) - float(route.times[index - 1])))
	_expect_max("act-one sampled normal onset including its entry boundary", maximum_onset, 24.5, "g/s")
	var analytic_onset: Variant = whole.get("peak_analytic_normal_onset_gps")
	_expect(typeof(analytic_onset) == TYPE_FLOAT and is_finite(float(analytic_onset)),
		"act-one exposes finite peak_analytic_normal_onset_gps; observed %s" % str(analytic_onset))
	if typeof(analytic_onset) == TYPE_FLOAT:
		_expect_max("act-one analytic normal onset", float(analytic_onset), 24.5, "g/s")
	var immelmann: Dictionary = roles[0]; var cutback: Dictionary = roles[1]
	var loop: Dictionary = roles[2]; var airtime: Dictionary = roles[3]; var wave: Dictionary = roles[4]
	_expect_range("Immelmann prominence", _prominence(route, immelmann), 90.0, 110.0, "m")
	_expect_min("Immelmann substantially inverted hold",
		_held_at_most(route, immelmann, true, -0.5), 1.5, "s")
	var cutback_turn := _turn_measure(route, cutback)
	_expect_range("cutback unwrapped heading excursion", cutback_turn.x, 140.0, 210.0, "deg")
	_expect_range("cutback lateral range", cutback_turn.y, 50.0, 160.0, "m")
	_expect_range("helical-loop prominence", _prominence(route, loop), 60.0, 90.0, "m")
	_expect_min("helical-loop substantially inverted hold",
		_held_at_most(route, loop, true, -0.5), 1.0, "s")
	_expect_min("helical-loop conservative nonlocal segment clearance",
		_nonlocal_clearance(route, loop, 30.0), 10.0, "m")
	_expect_range("airtime-hill prominence", _prominence(route, airtime), 10.0, 40.0, "m")
	_expect_min("airtime-hill normal <= -0.3 g hold",
		_held_at_most(route, airtime, false, -0.3), 1.5, "s")
	var wave_turn := _turn_measure(route, wave)
	_expect_range("wave-turn prominence", _prominence(route, wave), 5.0, 30.0, "m")
	_expect_range("wave-turn unwrapped heading excursion", wave_turn.x, 20.0, 80.0, "deg")
	_expect_range("wave-turn lateral range", wave_turn.y, 10.0, 150.0, "m")


func _prominence(route: Dictionary, window: Dictionary) -> float:
	var first := int(window.first)
	var last := int(window.last)
	return _maximum_height(route, first, last) \
		- maxf(route.positions[first].y, route.positions[last].y)


func _sampled_peak_vector_onset(route: Dictionary, first: int, last: int) -> float:
	var peak := 0.0
	for index in range(maxi(first, 1), last + 1):
		var delta := Vector3(
			float(route.normal_g[index]) - float(route.normal_g[index - 1]),
			float(route.lateral_g[index]) - float(route.lateral_g[index - 1]),
			float(route.drive_g[index]) - float(route.drive_g[index - 1]))
		peak = maxf(peak, delta.length() \
			/ (float(route.times[index]) - float(route.times[index - 1])))
	return peak


func _held_at_least(values: Variant, times: Variant, window: Dictionary, limit: float) -> float:
	var held := 0.0; var longest := 0.0
	for index in range(int(window.first) + 1, int(window.last) + 1):
		var before := float(values[index - 1]); var after := float(values[index])
		var duration := float(times[index]) - float(times[index - 1])
		if before >= limit and after >= limit:
			held += duration
		elif before >= limit:
			held += duration * (before - limit) / (before - after)
			longest = maxf(longest, held); held = 0.0
		elif after >= limit:
			held = duration * (after - limit) / (after - before)
		else:
			longest = maxf(longest, held); held = 0.0
	return maxf(longest, held)


func _held_at_most(route: Dictionary, window: Dictionary, use_up_dot: bool, limit: float) -> float:
	var held := 0.0; var longest := 0.0
	for index in range(int(window.first) + 1, int(window.last) + 1):
		var before: float = route.ups[index - 1].dot(Vector3.UP) \
			if use_up_dot else float(route.normal_g[index - 1])
		var after: float = route.ups[index].dot(Vector3.UP) \
			if use_up_dot else float(route.normal_g[index])
		var duration: float = float(route.times[index]) - float(route.times[index - 1])
		if before <= limit and after <= limit:
			held += duration
		elif before <= limit:
			held += duration * (limit - before) / (after - before)
			longest = maxf(longest, held); held = 0.0
		elif after <= limit:
			held = duration * (after - limit) / (after - before)
		else:
			longest = maxf(longest, held); held = 0.0
	return maxf(longest, held)


func _turn_measure(route: Dictionary, window: Dictionary) -> Vector2:
	var first := int(window.first)
	var previous := Vector2(route.tangents[first].x, route.tangents[first].z)
	if previous.length_squared() <= 0.000001:
		return Vector2(NAN, NAN)
	previous = previous.normalized()
	var right := Vector2(-previous.y, previous.x)
	var origin: Vector3 = route.positions[first]
	var heading := 0.0; var heading_range := Vector2.ZERO
	var lateral := Vector2.ZERO
	for index in range(first + 1, int(window.last) + 1):
		var current := Vector2(route.tangents[index].x, route.tangents[index].z)
		if current.length_squared() > 0.000001:
			current = current.normalized()
			heading += atan2(previous.cross(current), previous.dot(current))
			heading_range = Vector2(minf(heading_range.x, heading),
				maxf(heading_range.y, heading))
			previous = current
		var offset: float = Vector2(route.positions[index].x - origin.x,
			route.positions[index].z - origin.z).dot(right)
		lateral = Vector2(minf(lateral.x, offset), maxf(lateral.y, offset))
	return Vector2(rad_to_deg(heading_range.y - heading_range.x), lateral.y - lateral.x)

func _nonlocal_clearance(route: Dictionary, window: Dictionary, excluded_track_m: float) -> float:
	var result := INF
	for left in range(int(window.first), int(window.last)):
		for right in range(left + 2, int(window.last)):
			if float(route.distances[right]) - float(route.distances[left + 1]) > excluded_track_m:
				result = minf(result, _segment_clearance_lower_bound(route.positions[left],
					route.positions[left + 1], route.positions[right], route.positions[right + 1]))
	return result if is_finite(result) else -INF


func _segment_clearance_lower_bound(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> float:
	return maxf(0.0, 0.5 * (a + b).distance_to(c + d) \
		- 0.5 * a.distance_to(b) - 0.5 * c.distance_to(d))


func _expect_range(label: String, value: float, minimum: float, maximum: float, unit: String) -> void:
	_expect(value >= minimum and value <= maximum,
		"%s observed %.3f %s; required %.3f..%.3f %s" % [
			label, value, unit, minimum, maximum, unit])


func _expect_min(label: String, value: float, minimum: float, unit: String) -> void:
	_expect(value >= minimum, "%s observed %.3f %s; required >= %.3f %s" % [
		label, value, unit, minimum, unit])


func _expect_max(label: String, value: float, maximum: float, unit: String) -> void:
	_expect(value <= maximum, "%s observed %.3f %s; required <= %.3f %s" % [
		label, value, unit, maximum, unit])


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
