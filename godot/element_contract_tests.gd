extends SceneTree

const CONTRACT_PATH := "res://element_contract.gd"
const EPS := 0.00001

var _errors := PackedStringArray()
var _contract: Variant


func _initialize() -> void:
	if not ResourceLoader.exists(CONTRACT_PATH):
		_errors.append("whole-element contract implementation is missing")
		_finish()
		return
	_contract = load(CONTRACT_PATH)
	if _contract == null:
		_errors.append("whole-element contract script did not load")
		_finish()
		return
	_test_planar_hill_passes_its_declared_intent()
	_test_tilted_hill_cannot_self_exempt_from_vertical_planarity()
	_test_wrong_exit_state_is_rejected()
	_test_incomplete_intent_is_rejected()
	_finish()


func _test_planar_hill_passes_its_declared_intent() -> void:
	var route := _hill_route()
	var measured: Dictionary = _contract.measure(route, 0, route.positions.size() - 1)
	_expect(measured.get("status") == "measured", "planar hill produces a whole-element measurement")
	_expect_close(float(measured.get("vertical_plane_tilt_deg", INF)), 0.0,
		"planar hill's best-fit plane is vertical", 0.001)
	_expect_close(float(measured.get("out_of_plane_ratio", INF)), 0.0,
		"planar hill has no out-of-plane deviation", 0.000001)
	_expect_close(float(measured.get("heading_drift_deg", INF)), 0.0,
		"planar hill does not drift in heading", 0.001)
	var errors: PackedStringArray = _contract.validate(_hill_intent(), measured)
	_expect(errors.is_empty(), "planar hill satisfies its declared intent: %s" % str(errors))


func _test_tilted_hill_cannot_self_exempt_from_vertical_planarity() -> void:
	# z follows height, so the generated points remain mathematically planar while their plane is
	# rolled 26.565 degrees away from vertical. An output-derived 'three-dimensional' label must
	# never exempt an element whose intent explicitly requires a vertical plane.
	var route := _hill_route(0.5)
	var measured: Dictionary = _contract.measure(route, 0, route.positions.size() - 1)
	var errors: PackedStringArray = _contract.validate(_hill_intent(), measured)
	_expect(float(measured.get("vertical_plane_tilt_deg", 0.0)) > 20.0,
		"tilted fixture exposes a material plane tilt")
	_expect(_contains(errors, "vertical_plane_tilt_deg"),
		"vertical-planarity intent rejects a tilted but otherwise planar output: %s" % str(errors))


func _test_wrong_exit_state_is_rejected() -> void:
	var route := _hill_route(0.0, Vector3(0.8, -0.2, 0.56).normalized(), 12.0)
	var measured: Dictionary = _contract.measure(route, 0, route.positions.size() - 1)
	var errors: PackedStringArray = _contract.validate(_hill_intent(), measured)
	_expect(_contains(errors, "exit.pitch_deg"),
		"whole-element contract rejects a wrong exit pitch: %s" % str(errors))
	_expect(_contains(errors, "exit.bank_deg"),
		"whole-element contract rejects a wrong exit bank: %s" % str(errors))


func _test_incomplete_intent_is_rejected() -> void:
	var route := _hill_route()
	var measured: Dictionary = _contract.measure(route, 0, route.positions.size() - 1)
	var malformed := _hill_intent()
	malformed.erase("exit")
	var errors: PackedStringArray = _contract.validate(malformed, measured)
	_expect(_contains(errors, "intent.exit"),
		"an adopted contract cannot silently omit its exit state: %s" % str(errors))


func _hill_route(
	plane_tilt_z_per_y: float = 0.0,
	exit_tangent_override: Vector3 = Vector3.ZERO,
	exit_bank_deg: float = 0.0
) -> Dictionary:
	const COUNT := 21
	const LENGTH_M := 100.0
	const HEIGHT_M := 40.0
	var positions := PackedVector3Array()
	var tangents := PackedVector3Array()
	var ups := PackedVector3Array()
	var banks := PackedFloat32Array()
	for index in COUNT:
		var u := float(index) / float(COUNT - 1)
		var height := HEIGHT_M * sin(PI * u)
		positions.append(Vector3(LENGTH_M * u, height, plane_tilt_z_per_y * height))
		var derivative := Vector3(
			LENGTH_M,
			HEIGHT_M * PI * cos(PI * u),
			plane_tilt_z_per_y * HEIGHT_M * PI * cos(PI * u)
		)
		var tangent := derivative.normalized()
		if index == COUNT - 1 and exit_tangent_override.length_squared() > 0.0:
			tangent = exit_tangent_override.normalized()
		tangents.append(tangent)
		var up := Vector3.UP - tangent * tangent.dot(Vector3.UP)
		if up.length_squared() <= EPS * EPS:
			up = Vector3.FORWARD - tangent * tangent.dot(Vector3.FORWARD)
		ups.append(up.normalized())
		banks.append(exit_bank_deg if index == COUNT - 1 else 0.0)
	return {
		"positions": positions,
		"tangents": tangents,
		"ups": ups,
		"banks": banks,
	}


func _hill_intent() -> Dictionary:
	var entry_pitch := rad_to_deg(atan(0.4 * PI))
	return {
		"planarity": "vertical-plane",
		"max_plane_tilt_deg": 1.0,
		"max_out_of_plane_ratio": 0.001,
		"max_heading_drift_deg": 1.0,
		"entry": {
			"pitch_deg": entry_pitch,
			"pitch_tolerance_deg": 0.1,
			"bank_deg": 0.0,
			"bank_tolerance_deg": 0.1,
		},
		"exit": {
			"pitch_deg": -entry_pitch,
			"pitch_tolerance_deg": 0.1,
			"bank_deg": 0.0,
			"bank_tolerance_deg": 0.1,
		},
	}


func _contains(errors: PackedStringArray, fragment: String) -> bool:
	for error in errors:
		if str(error).contains(fragment):
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)


func _expect_close(actual: float, expected: float, message: String, tolerance: float) -> void:
	_expect(is_finite(actual) and absf(actual - expected) <= tolerance,
		"%s: expected %.9f, got %.9f" % [message, expected, actual])


func _finish() -> void:
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)
