extends SceneTree

const Metrics := preload("res://geometry_metrics.gd")
const Motion := preload("res://motion.gd")

var _errors := PackedStringArray()


func _initialize() -> void:
	_test_continuous_transition_is_clean()
	_test_roll_restart_is_rejected()
	_test_lateral_restart_is_rejected()
	_test_short_semantic_span_is_reported()
	_test_unowned_transition_is_not_guessed()
	_test_role_audit_covers_expected_roles()
	_test_role_audit_measures_shifted_shape()
	_test_role_audit_reports_missing_terrain()
	_test_role_audit_measures_apex_agl()
	_test_role_audit_is_deterministic()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _test_continuous_transition_is_clean() -> void:
	var first := Motion.span("test/roll-a", 0.5, "moving", Motion.constant(1.0),
		Motion.constant(0.0), Motion.constant(0.0), Motion.quintic(0.0, 1.0), "roll")
	var second := Motion.span("test/roll-b", 0.5, "moving", Motion.constant(1.0),
		Motion.constant(0.0), Motion.constant(0.0), Motion.quintic(1.0, 0.0), "roll")
	var result := Metrics.transition_audit([first, second])
	_expect(result.ok, "one continuous roll transition must pass: %s" % str(result.errors))
	_expect(result.seams.is_empty(), "continuous transition has no restart seam")


func _test_roll_restart_is_rejected() -> void:
	var first := Motion.span("test/restart-a", 0.5, "moving", Motion.constant(1.0),
		Motion.constant(0.0), Motion.constant(0.0), Motion.compact_pulse(1.0), "gesture")
	var second := Motion.span("test/restart-b", 0.5, "moving", Motion.constant(1.0),
		Motion.constant(0.0), Motion.constant(0.0), Motion.compact_pulse(1.0), "gesture")
	var result := Metrics.transition_audit([first, second])
	_expect(not result.ok, "a pulse/restart must fail the transition audit")
	_expect(result.seams.size() == 1 and result.seams[0].restarted_channels == ["roll_rate_rad_s"],
		"the failing seam identifies the restarted roll channel: %s" % str(result.seams))


func _test_lateral_restart_is_rejected() -> void:
	var first := Motion.span("test/lateral-a", 0.5, "moving", Motion.constant(1.0),
		Motion.compact_pulse(0.5), Motion.constant(0.0), Motion.constant(0.0), "gesture")
	var second := Motion.span("test/lateral-b", 0.5, "moving", Motion.constant(1.0),
		Motion.compact_pulse(0.5), Motion.constant(0.0), Motion.constant(0.0), "gesture")
	var result := Metrics.transition_audit([first, second])
	_expect(not result.ok and result.seams[0].restarted_channels == ["lateral_g"],
		"the failing seam identifies the restarted lateral channel")


func _test_short_semantic_span_is_reported() -> void:
	var span := Motion.span("test/connector", 0.15, "moving", Motion.constant(1.0),
		Motion.constant(0.0), Motion.constant(0.0), Motion.constant(0.0))
	var mutable := span.duplicate(true)
	mutable["semantic"] = true
	var result := Metrics.transition_audit([mutable])
	_expect(not result.ok, "a semantic span under 0.30 s must fail")
	_expect(result.short_spans.size() == 1 and result.short_spans[0].span_id == "test/connector",
		"the short span is named in the audit")


func _test_unowned_transition_is_not_guessed() -> void:
	var first := Motion.span("test/unknown-a", 0.5, "moving", Motion.constant(1.0),
		Motion.constant(0.0), Motion.constant(0.0), Motion.compact_pulse(1.0))
	var second := Motion.span("test/unknown-b", 0.5, "moving", Motion.constant(1.0),
		Motion.constant(0.0), Motion.constant(0.0), Motion.compact_pulse(1.0))
	var result := Metrics.transition_audit([first, second])
	_expect(result.ok, "unowned spans are not guessed into one transition")
	_expect(result.seams.is_empty(), "unowned spans have no invented seam")
	_expect(result.unowned.size() == 2, "unowned motion is reported as an evidence gap")


func _test_role_audit_covers_expected_roles() -> void:
	var route := _route(12)
	var result := Metrics.role_audit(route, {"alpha": Vector2i(0, 5), "beta": Vector2i(6, 11)},
		["alpha", "beta"])
	_expect(result.ok, "expected role bounds are measured: %s" % str(result.errors))
	_expect(result.roles.keys() == ["alpha", "beta"], "role audit is sorted and complete")
	_expect(result.roles.alpha.status == "measured" and result.roles.beta.status == "measured",
		"each expected role carries evidence")


func _test_role_audit_reports_missing_terrain() -> void:
	var result := Metrics.role_audit(_route(6), {"alpha": Vector2i(0, 5)}, ["alpha"])
	_expect(result.ok, "missing terrain is an evidence gap, not a geometry failure")
	_expect(result.roles.alpha.agl.status == "unavailable",
		"missing terrain is explicit in the role record")


func _test_role_audit_measures_shifted_shape() -> void:
	var route := _route(12)
	for index in route.positions.size():
		route.positions[index] = Vector3(float(index), sin(float(index) * 0.2),
			0.3 * sin(float(index) * 0.7))
	var result := Metrics.role_audit(route, {"shifted": Vector2i(0, 11)}, ["shifted"])
	_expect(result.ok, "a shifted role still produces evidence")
	_expect(float(result.roles.shifted.measurement.out_of_plane_ratio) >= 0.0,
		"a shifted role reports a finite planarity ratio")


func _test_role_audit_is_deterministic() -> void:
	var route := _route(10)
	var first := Metrics.role_audit(route, {"alpha": Vector2i(0, 9)}, ["alpha"])
	var second := Metrics.role_audit(route, {"alpha": Vector2i(0, 9)}, ["alpha"])
	_expect(var_to_bytes(first) == var_to_bytes(second), "role audit is byte-deterministic")


func _test_role_audit_measures_apex_agl() -> void:
	var terrain := {"kind": "material", "relief": 0.0, "face_height": 0.0,
		"apron_height": 0.0, "edge_normal": Vector2.RIGHT, "edge_offset": 0.0,
		"apron_width": 1.0, "face_width": 1.0, "wobble_amplitude": 0.0,
		"wobble_wavelength": 1.0, "detail_amplitude": 0.0, "noise_seed": 0}
	var route := _route(6)
	for index in route.positions.size():
		route.positions[index].y = float(index) * 20.0
	var result := Metrics.role_audit(route, {"hill": Vector2i(0, 5)}, ["hill"], terrain,
		{"hill": {"apex_agl_m": Vector2(90.0, 110.0)}})
	_expect(result.ok, "a measured AGL target inside its band passes")
	_expect(absf(float(result.roles.hill.agl.apex_m) - 100.0) < 0.001,
		"the apex AGL is measured at the role apex")


func _route(count: int) -> Dictionary:
	var positions := PackedVector3Array()
	var tangents := PackedVector3Array()
	var banks := PackedFloat32Array()
	var times := PackedFloat32Array()
	var distances := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var normals := PackedFloat32Array()
	var laterals := PackedFloat32Array()
	var rolls := PackedFloat32Array()
	for index in count:
		positions.append(Vector3(float(index), sin(float(index) * 0.2), 0.0))
		tangents.append(Vector3.RIGHT)
		banks.append(0.0)
		times.append(float(index) * 0.1)
		distances.append(float(index))
		speeds.append(50.0)
		normals.append(1.0)
		laterals.append(0.0)
		rolls.append(0.0)
	return {"positions": positions, "tangents": tangents, "banks": banks,
		"times": times, "distances": distances, "speeds": speeds, "normal_g": normals,
		"lateral_g": laterals, "roll_rates": rolls}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
