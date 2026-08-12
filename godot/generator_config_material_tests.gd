extends SceneTree

const RideGenerator := preload("res://generator.gd")

const SEED := 42
const SPEED_LOW_MPS := 91.0
const SPEED_HIGH_MPS := 97.0
const SPEED_TOLERANCE_MPS := 0.25
const HEIGHT_LOW_M := 244.0
const HEIGHT_HIGH_M := 258.0
const HEIGHT_TOLERANCE_M := 1.0

var _errors := PackedStringArray()


func _initialize() -> void:
	_check_peak_speed_control()
	_check_structure_height_control()
	_check_invalid_controls_are_rejected()
	_check_default_build_equivalence()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _check_peak_speed_control() -> void:
	var low_result := _build(_preference_document(
		"test-peak-speed", "ride", "ride.peak_speed_mps",
		SPEED_LOW_MPS, SPEED_TOLERANCE_MPS))
	var repeated_result := _build(_reordered_preference_document(
		"test-peak-speed", "ride", "ride.peak_speed_mps",
		SPEED_LOW_MPS, SPEED_TOLERANCE_MPS))
	var high_result := _build(_preference_document(
		"test-peak-speed", "ride", "ride.peak_speed_mps",
		SPEED_HIGH_MPS, SPEED_TOLERANCE_MPS))
	var low := _configured_route(low_result, "91 m/s peak-speed config")
	var repeated := _configured_route(repeated_result, "reordered 91 m/s peak-speed config")
	var high := _configured_route(high_result, "97 m/s peak-speed config")

	_expect(_same_trajectory(low, repeated),
		"same normalized config and seed must produce identical real trajectory arrays")
	var low_lsm3 := _lsm3_exit_speed(low)
	var high_lsm3 := _lsm3_exit_speed(high)
	var low_peak := _route_peak_speed(low)
	var high_peak := _route_peak_speed(high)
	_expect(absf(low_lsm3 - SPEED_LOW_MPS) <= SPEED_TOLERANCE_MPS,
		"91 m/s preference produced LSM3 exit %.3f m/s" % low_lsm3)
	_expect(absf(high_lsm3 - SPEED_HIGH_MPS) <= SPEED_TOLERANCE_MPS,
		"97 m/s preference produced LSM3 exit %.3f m/s" % high_lsm3)
	_expect(high_lsm3 > low_lsm3 and high_lsm3 - low_lsm3 >= 5.0,
		"higher peak-speed preference must raise LSM3 exit by >=5 m/s; observed %.3f -> %.3f m/s" % [
			low_lsm3, high_lsm3])
	_expect(absf(low_peak - SPEED_LOW_MPS) <= SPEED_TOLERANCE_MPS,
		"91 m/s preference produced route peak %.3f m/s" % low_peak)
	_expect(absf(high_peak - SPEED_HIGH_MPS) <= SPEED_TOLERANCE_MPS,
		"97 m/s preference produced route peak %.3f m/s" % high_peak)
	_expect(high_peak > low_peak and high_peak - low_peak >= 5.0,
		"higher peak-speed preference must raise route peak by >=5 m/s; observed %.3f -> %.3f m/s" % [
			low_peak, high_peak])


func _check_structure_height_control() -> void:
	var low_result := _build(_preference_document(
		"test-camelback-height", "marquee-camelback", "slot.structure_height_m",
		HEIGHT_LOW_M, HEIGHT_TOLERANCE_M))
	var high_result := _build(_preference_document(
		"test-camelback-height", "marquee-camelback", "slot.structure_height_m",
		HEIGHT_HIGH_M, HEIGHT_TOLERANCE_M))
	var low := _configured_route(low_result, "244 m camelback-height config")
	var high := _configured_route(high_result, "258 m camelback-height config")
	var low_shape := _camelback_shape(low)
	var high_shape := _camelback_shape(high)

	_expect(absf(low_shape.x - HEIGHT_LOW_M) <= HEIGHT_TOLERANCE_M,
		"244 m structure preference produced %.3f m prominence" % low_shape.x)
	_expect(absf(high_shape.x - HEIGHT_HIGH_M) <= HEIGHT_TOLERANCE_M,
		"258 m structure preference produced %.3f m prominence" % high_shape.x)
	_expect(high_shape.x > low_shape.x and high_shape.x - low_shape.x >= 10.0,
		"higher structure-height preference must raise actual prominence by >=10 m; observed %.3f -> %.3f m" % [
			low_shape.x, high_shape.x])
	_expect(low_shape.y >= 3.1 and low_shape.y <= 3.9,
		"244 m camelback width:height observed %.3f; required 3.1..3.9" % low_shape.y)
	_expect(high_shape.y >= 3.1 and high_shape.y <= 3.9,
		"258 m camelback width:height observed %.3f; required 3.1..3.9" % high_shape.y)


func _check_invalid_controls_are_rejected() -> void:
	var cases := [
		["unknown key", "ride", "ride.unknown_speed_mps", 94.0, 0.25],
		["speed below capability", "ride", "ride.peak_speed_mps", 90.99, 0.25],
		["speed above capability", "ride", "ride.peak_speed_mps", 97.01, 0.25],
		["height below capability", "marquee-camelback", "slot.structure_height_m", 243.99, 1.0],
		["height above capability", "marquee-camelback", "slot.structure_height_m", 258.01, 1.0],
	]
	for index in cases.size():
		var case: Array = cases[index]
		var record := _preference_record(
			"invalid-%d" % index, str(case[1]), str(case[2]),
			float(case[3]), float(case[4]))
		var layer: Dictionary = {"constraints": {"preferred": [record]}}
		var overrides: Array[Dictionary] = [layer]
		var result := _call_build_config(_default_document(), overrides)
		_expect(not result.get("ok", true), "%s must be rejected" % case[0])
		_expect(result.get("route", null) == null,
			"%s must not return a partial route" % case[0])
		_expect(not result.get("errors", []).is_empty(),
			"%s rejection must explain the configuration error" % case[0])


func _check_default_build_equivalence() -> void:
	var direct := RideGenerator.build(SEED)
	var configured := _configured_route(_build(_default_document()), "default config")
	_expect(_same_trajectory(direct, configured),
		"build(seed) and the explicit default config must produce identical real trajectory arrays")


func _build(document: Dictionary) -> Dictionary:
	var overrides: Array[Dictionary] = []
	return _call_build_config(document, overrides)


func _call_build_config(document: Dictionary, overrides: Array[Dictionary]) -> Dictionary:
	var method := {}
	for candidate in RideGenerator.get_script_method_list():
		if candidate.get("name", "") == "build_config":
			method = candidate
			break
	if method.is_empty() or method.get("args", []).size() < 2:
		return _api_failure("RideGenerator.build_config(document, overrides) is unavailable")
	var entrypoint: Callable = RideGenerator.build_config
	if not entrypoint.is_valid():
		return _api_failure("RideGenerator.build_config(document, overrides) is not callable")
	var result: Variant = entrypoint.callv([document, overrides])
	if not result is Dictionary:
		return _api_failure("RideGenerator.build_config(document, overrides) returned no result")
	return result


func _api_failure(message: String) -> Dictionary:
	return {"ok": false, "route": null, "errors": PackedStringArray([message])}


func _configured_route(result: Dictionary, label: String) -> Dictionary:
	_expect(result.get("ok", false), "%s builds successfully: %s" % [
		label, str(result.get("errors", []))])
	var route: Variant = result.get("route", null)
	_expect(route is Dictionary and not route.is_empty(), "%s returns a public route" % label)
	return route if route is Dictionary else {}


func _default_document() -> Dictionary:
	return {
		"ride_config_version": 1,
		"preset": "future-hybrid@1",
		"seed": SEED,
		"sequence": {"pinned": {}},
		"constraints": {"required": [], "preferred": []},
	}


func _preference_document(
	id: String, scope: String, key: String, target: float, tolerance: float
) -> Dictionary:
	var document := _default_document()
	document.constraints.preferred = [_preference_record(id, scope, key, target, tolerance)]
	return document


func _reordered_preference_document(
	id: String, scope: String, key: String, target: float, tolerance: float
) -> Dictionary:
	var record := {"tolerance": tolerance, "target": target, "key": key,
		"scope": scope, "id": id}
	var document := {}
	document["constraints"] = {"preferred": [record], "required": []}
	document["sequence"] = {"pinned": {}}
	document["seed"] = SEED
	document["preset"] = "future-hybrid@1"
	document["ride_config_version"] = 1
	return document


func _preference_record(
	id: String, scope: String, key: String, target: float, tolerance: float
) -> Dictionary:
	return {"id": id, "scope": scope, "key": key,
		"target": target, "tolerance": tolerance}


func _same_trajectory(left: Dictionary, right: Dictionary) -> bool:
	if left.is_empty() or right.is_empty() or left.get("positions", []).is_empty() \
			or right.get("positions", []).is_empty():
		return false
	return left.positions == right.positions and left.speeds == right.speeds \
		and left.normal_g == right.normal_g and left.gesture_windows == right.gesture_windows


func _lsm3_exit_speed(route: Dictionary) -> float:
	var window := _window(route, "tunnel-lsm3")
	return float(route.speeds[int(window.last)]) if not window.is_empty() else NAN


func _route_peak_speed(route: Dictionary) -> float:
	var peak := -INF
	for speed in route.get("speeds", []):
		peak = maxf(peak, float(speed))
	return peak


func _camelback_shape(route: Dictionary) -> Vector2:
	var window := _window(route, "marquee-camelback")
	if window.is_empty():
		return Vector2(NAN, NAN)
	var first := int(window.first)
	var last := int(window.last)
	var apex_height := -INF
	for index in range(first, last + 1):
		apex_height = maxf(apex_height, route.positions[index].y)
	var prominence := apex_height - maxf(route.positions[first].y, route.positions[last].y)
	var horizontal: Vector3 = route.positions[last] - route.positions[first]
	horizontal.y = 0.0
	return Vector2(prominence, horizontal.length() / prominence)


func _window(route: Dictionary, story_id: String) -> Dictionary:
	for window in route.get("gesture_windows", []):
		if window.get("story_slot_id", "") == story_id:
			return window
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
