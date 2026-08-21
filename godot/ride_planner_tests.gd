extends SceneTree

## Focused suite for the planner decision layer: stream determinism and independence, grammar
## legality, draw provenance, and — the expensive half — feasibility of every certified range at
## both of its extremes, built and validated end to end so no runtime retry is ever needed.

const RideGenerator := preload("res://generator.gd")
const RidePlanner := preload("res://ride_planner.gd")
const RideProgram := preload("res://ride_program.gd")
const RouteContract := preload("res://route_contract.gd")
const RideVerify := preload("res://verify.gd")
## TEMPORARY CI-32442427378 DIAGNOSTIC dependency: remove with the diagnostic helpers below.
const Terrain := preload("res://terrain.gd")

const FEASIBILITY_SEEDS := [11, 20260809]
const ROUTE_LENGTH_BAND_M := Vector2(7800.0, 8200.0)
const CAMEL_PROMINENCE_BAND_M := Vector2(245.0, 255.0)

var _errors := PackedStringArray()


func _initialize() -> void:
	_test_streams_are_deterministic_and_independent()
	_test_stream_seeds_are_stable_integers()
	_test_grammar_legality()
	_test_draw_provenance_is_recorded()
	_test_overrides_do_not_disturb_stream_alignment()
	_test_undrawn_story_reproduces_the_authored_recipe()
	_test_certified_ranges_are_feasible_at_both_extremes()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _test_streams_are_deterministic_and_independent() -> void:
	var first := RidePlanner.streams(42)
	var repeat := RidePlanner.streams(42)
	var other := RidePlanner.streams(43)
	_expect(first.size() == RidePlanner.stream_ids().size(),
		"streams() builds one generator per declared stream")
	var seeds := {}
	for stream_name in RidePlanner.stream_ids():
		var name := str(stream_name)
		_expect(first[name].seed == repeat[name].seed,
			"stream %s is the same for a repeated resolve of one seed" % name)
		_expect(first[name].seed != other[name].seed,
			"stream %s moves when the ride seed moves" % name)
		_expect(not seeds.has(first[name].seed),
			"stream %s does not collide with another stream on the same seed" % name)
		seeds[first[name].seed] = name
		var draws := PackedFloat64Array()
		for _index in 4:
			draws.append(first[name].randf())
		var repeated := PackedFloat64Array()
		for _index in 4:
			repeated.append(repeat[name].randf())
		_expect(draws == repeated, "stream %s produces the same sequence twice" % name)


## Appending a draw to one stream must not move any other stream's values: that is the whole
## reason each named decision owns a generator instead of sharing one cursor.
func _test_stream_seeds_are_stable_integers() -> void:
	_expect(RidePlanner.stream_seed(0, "terrain") == RidePlanner.stream_seed(0, "terrain"),
		"stream_seed is a pure function of (seed, name)")
	_expect(RidePlanner.stream_seed(0, "terrain") != RidePlanner.stream_seed(0, "placement"),
		"stream_seed separates two names on the same seed")
	_expect(RidePlanner.stream_seed(1, "terrain") != RidePlanner.stream_seed(2, "terrain"),
		"stream_seed separates two seeds on the same name")
	for seed_value in [-2147483648, -7, 0, 1, 42, 2147483647, 9007199254740993]:
		var hashed := RidePlanner.stream_seed(seed_value, "targets.return-height-a")
		_expect(hashed >= 0, "stream_seed stays a nonnegative 63-bit value for seed %d"
			% seed_value)
	# The recorded values pin the hash itself: a change here changes every seed's ride, so it
	# has to be a deliberate edit rather than an accident of refactoring.
	_expect(RidePlanner.stream_seed(42, "terrain") == 5363867731558424324,
		"the terrain stream seed for ride seed 42 is the recorded value, observed %d"
			% RidePlanner.stream_seed(42, "terrain"))


func _test_grammar_legality() -> void:
	var canonical := RidePlanner.canonical_role_ids()
	_expect(canonical.size() == 21, "the canonical grammar authors twenty-one roles")
	_expect(RidePlanner.is_legal_sequence(canonical),
		"the canonical sequence is grammar-legal")
	_expect(RidePlanner.is_legal_sequence(RidePlanner.resolve(42).sequence),
		"a resolved plan sequence is grammar-legal")
	var swapped: Array = canonical.duplicate()
	swapped[5] = canonical[6]
	swapped[6] = canonical[5]
	_expect(RidePlanner.is_legal_sequence(swapped),
		"permuting inside the act-one pool stays legal")
	var anchor_moved: Array = canonical.duplicate()
	anchor_moved[4] = canonical[5]
	anchor_moved[5] = canonical[4]
	_expect(not RidePlanner.is_legal_sequence(anchor_moved),
		"moving the Immelmann anchor off the front of act one is illegal")
	var spine_moved: Array = canonical.duplicate()
	spine_moved[1] = canonical[2]
	spine_moved[2] = canonical[1]
	_expect(not RidePlanner.is_legal_sequence(spine_moved),
		"permuting the opener spine is illegal")
	var return_moved: Array = canonical.duplicate()
	return_moved[16] = canonical[18]
	return_moved[18] = canonical[16]
	_expect(not RidePlanner.is_legal_sequence(return_moved),
		"permuting the return cell is illegal at this checkpoint")
	var dropped_optional: Array = canonical.duplicate()
	dropped_optional.erase("act-one-wave")
	_expect(RidePlanner.is_legal_sequence(dropped_optional),
		"dropping one optional act-one member stays legal")
	var dropped_inversion: Array = canonical.duplicate()
	dropped_inversion.erase("act-one-loop")
	_expect(not RidePlanner.is_legal_sequence(dropped_inversion),
		"dropping an act-one inversion is illegal")
	var dropped_both: Array = canonical.duplicate()
	dropped_both.erase("act-one-wave")
	dropped_both.erase("act-one-airtime")
	_expect(not RidePlanner.is_legal_sequence(dropped_both),
		"dropping both optional act-one members is illegal")
	var duplicated: Array = canonical.duplicate()
	duplicated[5] = "act-one-loop"
	_expect(not RidePlanner.is_legal_sequence(duplicated),
		"repeating an act-one member is illegal")


func _test_draw_provenance_is_recorded() -> void:
	var decisions := RidePlanner.resolve(42)
	_expect(decisions.draws.size() == RidePlanner.TARGET_DRAWS.size(),
		"every declared draw is resolved and recorded")
	var indices := {}
	for index in decisions.draws.size():
		var draw: Dictionary = decisions.draws[index]
		var specification: Dictionary = RidePlanner.TARGET_DRAWS[index]
		var band: Vector2 = specification.range
		var stream_name: String = RidePlanner.TARGET_STREAM_PREFIX + str(specification.role_id)
		_expect(draw.stream == stream_name and draw.role_id == specification.role_id \
			and draw.key == specification.key and draw.range == band,
			"draw %d records the stream, role, key and range it came from" % index)
		_expect(int(draw.index) == int(indices.get(stream_name, 0)),
			"draw %d records its position in its own stream" % index)
		indices[stream_name] = int(indices.get(stream_name, 0)) + 1
		var value := float(draw.value)
		_expect(value >= band.x and value <= band.y,
			"draw %s is inside its certified range" % draw.key)
		_expect(is_equal_approx(RidePlanner.target(decisions.targets, str(draw.role_id),
			str(draw.key), NAN), value),
			"draw %s resolves to the value the recipes read" % draw.key)
	var plan: Dictionary = RideGenerator.build(42).get(
		"terrain_story_plan", {}).get("plan", {})
	_expect(var_to_bytes(plan.get("decisions", {}).get("draws", [])) == var_to_bytes(decisions.draws),
		"the published plan carries the same draw provenance the planner recorded")


func _test_overrides_do_not_disturb_stream_alignment() -> void:
	var plain := RidePlanner.resolve(42)
	var specification: Dictionary = RidePlanner.TARGET_DRAWS[0]
	var key := "%s/%s" % [specification.role_id, specification.key]
	var band: Vector2 = specification.range
	var overridden := RidePlanner.resolve(42, {key: band.x})
	_expect(overridden.draws.size() == plain.draws.size(),
		"an override consumes the same number of draws as production")
	_expect(is_equal_approx(float(overridden.draws[0].value), band.x),
		"an override replaces the value it names")
	for index in range(1, plain.draws.size()):
		_expect(is_equal_approx(float(plain.draws[index].value),
			float(overridden.draws[index].value)),
			"an override leaves draw %d alone" % index)
	var clamped := RidePlanner.resolve(42, {key: band.y + 10.0})
	_expect(is_equal_approx(float(clamped.draws[0].value), band.y),
		"an override outside the certified range is clamped back into it")


## A story with no draws must compile the authored recipe unchanged, so the parameterisation
## itself can never be the thing that moved a number.
func _test_undrawn_story_reproduces_the_authored_recipe() -> void:
	var bare := RideProgram.terrain_story_capability(-1)
	var declared := RideProgram.terrain_story_capability(-1,
		{"sequence": RidePlanner.canonical_role_ids(), "targets": {}})
	_expect(bare.get("ok", false) and declared.get("ok", false),
		"the capability preflight accepts both the bare and the declared story")
	if not bare.get("ok", false) or not declared.get("ok", false):
		return
	_expect(var_to_bytes(bare) == var_to_bytes(declared),
		"an undrawn declared story is bit-identical to the authored recipe")


## The certification the no-retry rule rests on: each declared range must build, validate and
## keep every record band at both of its extremes. Interior values are never tested at runtime,
## so the extremes are where the claim has to hold.
func _test_certified_ranges_are_feasible_at_both_extremes() -> void:
	for specification: Dictionary in RidePlanner.TARGET_DRAWS:
		var key := "%s/%s" % [specification.role_id, specification.key]
		var band: Vector2 = specification.range
		for value in [band.x, band.y]:
			for seed_value in FEASIBILITY_SEEDS:
				_check_extreme(seed_value, key, value)


func _check_extreme(seed_value: int, key: String, value: float) -> void:
	var label := "seed %d with %s = %.5f" % [seed_value, key, value]
	var decisions := RidePlanner.resolve(seed_value, {key: value})
	var route: Dictionary = RideGenerator.build_with_decisions(seed_value, decisions)
	if not route.get("ok", false):
		_expect(false, "%s builds: errors=%s failure=%s" % [label,
			str(route.get("errors", [])), str(route.get("failure", {}))])
		return
	var issues := PackedStringArray()
	RideVerify.validate_structure(route, issues)
	RideVerify.validate_seams(route, issues)
	RideVerify.validate_clearance(route, route.terrain, issues)
	RideVerify.validate_self_clearance(route, issues)
	var analysis: Dictionary = RideVerify.analyze(route, RouteContract.ROW_OFFSETS)
	RideVerify.validate_loads(analysis, issues)
	_temporary_print_endpoint_diagnostic(label, route, analysis, issues)
	_expect(issues.is_empty(), "%s validates: %s" % [label, str(issues)])
	_expect_range("%s route length" % label, float(route.length),
		ROUTE_LENGTH_BAND_M, "m")
	_expect_range("%s top speed" % label, float(analysis.top_speed),
		RideGenerator.RECORD_EXIT_SPEED_BAND_MPS, "m/s")
	var prominence := float(route.terrain_story_plan.terrain_proofs.camelback.prominence_m)
	_expect_range("%s camelback prominence" % label, prominence,
		CAMEL_PROMINENCE_BAND_M, "m")
	var stats: Dictionary = route.get("generation_stats", {})
	_expect(int(stats.get("accepted_integrations", -1)) == 1 \
		and int(stats.get("repair_count", -1)) == 0,
		"%s integrates once without repair" % label)


## TEMPORARY CI-32442427378 DIAGNOSTIC: remove after the power4 clearance experiment.
## One compact line per existing endpoint route; test code only, no production diagnostics.
func _temporary_print_endpoint_diagnostic(
	label: String, route: Dictionary, analysis: Dictionary, issues: PackedStringArray
) -> void:
	var rows: Array = analysis.get("rows", [])
	var row0: Dictionary = rows[0] if not rows.is_empty() else {}
	var worst: Dictionary = _temporary_worst_power4_clearance(route)
	print("[TEMP CI-32442427378 endpoint] label=%s row0_positive=%s row0_negative=%s "
		+ "row0_lateral=%s row0_longitudinal_positive=%s row0_longitudinal_negative=%s "
		+ "combined_usage=%s issues=%s worst_clearance=%s" % [
			label, str(row0.positive_envelope), str(row0.negative_envelope),
			str(row0.lateral_envelope), str(row0.longitudinal_positive_envelope),
			str(row0.longitudinal_negative_envelope), str(row0.combined_usage),
			str(issues), str(worst)])


## TEMPORARY CI-32442427378 DIAGNOSTIC: remove with the endpoint print above.
func _temporary_worst_power4_clearance(route: Dictionary) -> Dictionary:
	var terrain_value: Variant = route.get("terrain")
	if not terrain_value is Dictionary:
		return {}
	var terrain: Dictionary = terrain_value.duplicate(true)
	var terrace_value: Variant = terrain.get("return_terrace")
	if not terrace_value is Dictionary:
		return {}
	var terrace: Dictionary = terrace_value
	terrain.erase("return_terrace")
	var positions: PackedVector3Array = route.get("positions", PackedVector3Array())
	var ups: PackedVector3Array = route.get("ups", PackedVector3Array())
	var tunnels: Array = route.get("tunnel_ranges", [])
	var gesture_indices: PackedInt32Array = route.get("gesture_indices", PackedInt32Array())
	var gesture_windows: Array = route.get("gesture_windows", [])
	var worst_clearance_m := INF
	var worst: Dictionary = {}
	for index in positions.size():
		var in_tunnel := false
		for tunnel in tunnels:
			if index >= tunnel.x and index <= tunnel.y:
				in_tunnel = true
				break
		if in_tunnel:
			continue
		var rail: Vector3 = positions[index] - ups[index] * 1.55
		var base_clearance_m := rail.y - Terrain.height(terrain, rail.x, rail.z)
		var point := Vector2(rail.x, rail.z)
		var delta := point - terrace.center_m
		var cross := Vector2(-terrace.along.y, terrace.along.x)
		var along_distance := delta.dot(terrace.along)
		var cross_distance := delta.dot(cross)
		var r2 := (along_distance / float(terrace.half_length_m)) ** 2 \
			+ (cross_distance / float(terrace.half_width_m)) ** 2
		var u := clampf(1.0 - r2, 0.0, 1.0)
		var cubic := u * u * (3.0 - 2.0 * u)
		var contribution_m := float(terrace.elevation_m) * cubic * cubic * cubic * cubic
		var final_clearance_m := base_clearance_m - contribution_m
		if final_clearance_m < worst_clearance_m:
			worst_clearance_m = final_clearance_m
			var gesture_index := int(gesture_indices[index])
			var window_id := "unknown"
			if gesture_index >= 0 and gesture_index < gesture_windows.size():
				window_id = str(gesture_windows[gesture_index].get("window_id", "unknown"))
			worst = {"sample": index, "window": window_id, "base_clearance_m": base_clearance_m,
				"r2": r2, "u": u, "power4_contribution_m": contribution_m,
				"final_clearance_m": final_clearance_m}
	return worst


func _expect_range(label: String, value: float, band: Vector2, unit: String) -> void:
	_expect(value >= band.x and value <= band.y,
		"%s observed %.3f %s; required %.3f..%.3f %s" % [label, value, unit, band.x, band.y,
			unit])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
