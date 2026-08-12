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
	_expect(_dive_core_descends_monotonically(route),
		"the cliff-dive core loses height monotonically")
	_expect(_lsm3_feeds_camelback(route),
		"LSM3 materially raises speed and directly feeds the marquee camelback")
	_expect(_public_arrays_are_shaped(route),
		"all public trajectory arrays are packed, aligned, and nontrivial")
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
		if window.get("story_slot_id", "") != STORY_IDS[index] or first > last or first <= previous_last:
			return false
		previous_last = last
	return true


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
	return _all_propulsion_zero(route, first, int(crest.last)) \
		and route.speeds[last] < route.speeds[first] - 10.0 \
		and route.speeds[int(crest.first)] <= 22.0


func _dive_core_descends_monotonically(route: Dictionary) -> bool:
	var core := _role(route, "cliff-dive", "core")
	if core.is_empty():
		return false
	for index in range(int(core.first) + 1, int(core.last) + 1):
		if route.positions[index].y >= route.positions[index - 1].y:
			return false
	return true


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
	return route.speeds[last] >= route.speeds[first] + 20.0 and int(camel.first) <= last + 1


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
