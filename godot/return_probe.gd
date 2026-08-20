extends SceneTree

const RideProgram := preload("res://ride_program.gd")
const RidePrefixSolve := preload("res://ride_prefix_solve.gd")
const RideReturnSolve := preload("res://ride_return_solve.gd")
const Motion := preload("res://motion.gd")


func _initialize() -> void:
	var program := RidePrefixSolve._prefix_program(1, {}, RidePrefixSolve.PREFIX_SEED)
	if not program.get("ok", false):
		printerr("prefix program failed: %s" % str(program))
		quit(1)
		return
	var spans: Array = []
	var metadata: Array = []
	var gestures: Array = []
	var propulsion := PackedInt32Array()
	var hand := -1.0
	spans.append_array(program.spans)
	RideProgram._add_camelback(spans, metadata, propulsion)
	var start_route := Motion.integrate(RidePrefixSolve._prefix_initial_state(), spans,
		RideProgram._settings(RideProgram.PRODUCTION_STEP_S))
	if not start_route.get("ok", false):
		printerr("prefix failed: %s" % str(start_route))
		quit(1)
		return
	var start := RideProgram._last_state(start_route)
	var story := {"targets": {}}
	var layout := {"station_position_m": Vector3.ZERO, "station_tangent": Vector3.RIGHT,
		"station_up": Vector3.UP, "reserved_corridor": {"minimum_length_m": 230.0,
			"entry_speed_mps": Vector2(70.0, 80.0)}, "capture_half_width_m": 150.0,
		"capture_half_height_m": 75.0}
	var initial_bank := float(RideReturnSolve._capture_residuals(start, layout)[4])
	print("start position=%s tangent=%s up=%s speed=%f distance=%f initial_bank=%f" % [
		str(start.position_m), str(start.tangent), str(start.rider_up), start.speed_mps,
		start.distance_m, initial_bank])
	var candidates := [
		RideReturnSolve.RETURN_SEED.duplicate() + [3.8],
		[1.07, 0.55, 3.13, 1.05, 6.35, 0.42, 3.12, 3.52],
		[1.15, 4.80, 1.23, 1.09, 4.97, 1.71, 4.04, 4.60],
		[1.047, 2.5, 2.0, 1.22, 8.0, 1.0, 2.0, 3.8],
		[1.15, 6.0, 4.0, 1.35, 12.0, 2.0, 4.6, 4.6],
		[0.9, 3.0, 1.0, 1.4, 4.0, 0.5, 1.0, 3.4],
	]
	for candidate: Array in candidates:
		var result := RideReturnSolve._return_evaluation(start, layout, candidate,
			RideProgram._settings(RideProgram.PRODUCTION_STEP_S), {}, -hand, initial_bank,
			story.targets)
		print("candidate=%s residuals=%s observation=%s" % [str(candidate),
			str(result.get("residuals", [])), str(result.get("observation", {}))])
	for seed: Array in [candidates[1], candidates[2], candidates[3], candidates[5]]:
		var solved := RideReturnSolve._solve_return(start, layout, -hand, seed, story.targets)
		print("solve_seed=%s result=%s" % [str(seed), str(solved)])
		var mirrored := RideReturnSolve._solve_return(start, layout, hand, seed, story.targets)
		print("mirror_seed=%s result=%s" % [str(seed), str(mirrored)])
	var rolled_spans: Array = program.spans.duplicate()
	var rolled_metadata: Array = []
	var rolled_propulsion := PackedInt32Array()
	_add_rolled_camelback(rolled_spans, rolled_metadata, rolled_propulsion, hand)
	var rolled_route := Motion.integrate(RidePrefixSolve._prefix_initial_state(), rolled_spans,
		RideProgram._settings(RideProgram.PRODUCTION_STEP_S))
	var rolled_start := RideProgram._last_state(rolled_route)
	var rolled_bank := float(RideReturnSolve._capture_residuals(rolled_start, layout)[4])
	var rolled_solve := RideReturnSolve._solve_return(rolled_start, layout, -hand, candidates[1],
		story.targets)
	print("rolled_zero_lateral start=%s bank=%f solve=%s" % [str(rolled_start.position_m),
		rolled_bank, str(rolled_solve)])
	quit(0)


func _add_rolled_camelback(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, hand: float
) -> void:
	var positive_g := 4.60068864065765
	var negative_g := -1.55352865073772
	var pullout_g := 5.2662035249371
	var pullup_s := 1.87949032 * 1.33555111055541
	var unload_s := 3.01169597 * 1.15 - 0.4
	var crest_s := 3.62587650 * 1.06
	var fall_s := 3.40
	var bank := -deg_to_rad(18.0) * hand
	RideProgram._add(spans, metadata, propulsion, "probe/pull-up", pullup_s, "moving",
		Motion.quintic(1.0, positive_g), Motion.constant(0.0), 0.0,
		Motion.compact_pulse(bank / (pullup_s * RideProgram.COMPACT_PULSE_AREA)), "probe")
	RideProgram._add(spans, metadata, propulsion, "probe/unload", unload_s, "moving",
		Motion.quintic(positive_g, negative_g), Motion.constant(0.0), 0.0,
		Motion.compact_pulse(-bank / (unload_s * RideProgram.COMPACT_PULSE_AREA)), "probe")
	RideProgram._add(spans, metadata, propulsion, "probe/crest", crest_s, "moving",
		negative_g, Motion.constant(0.0), 0.0,
		Motion.compact_pulse(-bank / (crest_s * RideProgram.COMPACT_PULSE_AREA)), "probe")
	RideProgram._add(spans, metadata, propulsion, "probe/fall", fall_s, "moving",
		Motion.quintic(negative_g, pullout_g), Motion.constant(0.0), 0.0,
		Motion.compact_pulse(bank / (fall_s * RideProgram.COMPACT_PULSE_AREA)), "probe")
	RideProgram._add(spans, metadata, propulsion, "probe/pullout", 1.58, "moving",
		Motion.quintic(pullout_g, 1.0), Motion.constant(0.0), 0.0, 0.0, "probe")
