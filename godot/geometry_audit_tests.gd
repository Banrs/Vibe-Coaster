extends SceneTree

const Metrics := preload("res://geometry_metrics.gd")
const Motion := preload("res://motion.gd")

var _errors := PackedStringArray()


func _initialize() -> void:
	_test_continuous_transition_is_clean()
	_test_roll_restart_is_rejected()
	_test_short_semantic_span_is_reported()
	_test_unowned_transition_is_not_guessed()
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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
