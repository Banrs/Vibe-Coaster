extends SceneTree

const RideGenerator := preload("res://generator.gd")
const RideTerrain := preload("res://terrain.gd")
const RideProgram := preload("res://ride_program.gd")
const RouteContract := preload("res://route_contract.gd")

const SEED := 42
const LOWER_SPINE_SURFACE_OFFSET_M := 1.79
const MINIMUM_EXPOSED_SPINE_CLEARANCE_M := 2.0
const STORY_CLEARANCE_MINIMUM_M := 8.0
const STORY_CLEARANCE_MAXIMUM_M := 36.0
const STATION_CLEARANCE_MINIMUM_M := 4.0
const TERRAIN_RELIEF_MINIMUM_M := 270.0
const TERRAIN_RELIEF_MAXIMUM_M := 285.0
const ROUTE_VERTICAL_ENVELOPE_MINIMUM_M := 290.0
const ROUTE_VERTICAL_ENVELOPE_MAXIMUM_M := 305.0
const DIVE_DROP_MINIMUM_M := 240.0
const DIVE_DROP_MAXIMUM_M := 250.0
const CAMEL_PROMINENCE_MINIMUM_M := 245.0
const CAMEL_PROMINENCE_MAXIMUM_M := 255.0
const MAXIMUM_DIVE_RISE_M := 0.05

const ZONE_PLAIN := 0
const ZONE_APRON := 1
const ZONE_FACE := 2
const ZONE_PLATEAU := 3

var _errors := PackedStringArray()


func _initialize() -> void:
	var route := RideGenerator.build(SEED)
	if not route.get("ok", false):
		_expect(false, "seed 42 must build through RideGenerator.build before terrain story checks: %s" \
			% str(route.get("errors", [])))
	else:
		_check_public_terrain_story(route)
	_check_terrain_story_plan_contract(route)
	_test_return_terrace_tracks_actual_camelback_apex(route)
	_test_route_contract_return_terrace_proof(route)
	_test_return_terrace_heightfield()
	_test_malformed_return_terrace_is_rejected(route)
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _check_public_terrain_story(route: Dictionary) -> void:
	var terrain: Dictionary = route.get("terrain", {})
	var station := _window(route, "station-launch")
	var opener := _window(route, "opener")
	var climb := _window(route, "escarpment-climb")
	var rim := _role(route, "clifftop-suspense", "outward-rim")
	var dive := _window(route, "cliff-dive")
	var tunnel := _window(route, "tunnel-lsm3")
	if terrain.is_empty() or station.is_empty() or opener.is_empty() or climb.is_empty() \
			or rim.is_empty() or dive.is_empty() or tunnel.is_empty():
		_expect(false, "seed 42 must publish terrain and all terrain-story semantic windows")
		return

	_expect(_window_is_plain_with_clearance(route, terrain, station),
		"station-launch lower spine must stay on plain with 4..36 m rendered clearance")
	_expect(_window_is_plain_and_exposed(route, terrain, opener),
		"opener lower spine must stay on plain with at least 2 m rendered clearance")
	var entry_position: Vector3 = route.positions[int(dive.first)]
	var tunnel_exit_position: Vector3 = route.positions[int(tunnel.last)]
	var terrain_chord := Vector3(tunnel_exit_position.x - entry_position.x, 0.0,
		tunnel_exit_position.z - entry_position.z).normalized()
	var outward := -Vector3(terrain.edge_normal.x, 0.0, terrain.edge_normal.y).normalized()
	_expect(terrain_chord.dot(outward) >= 0.75,
		"cliff-dive and tunnel horizontal chord must progress predominantly outward")
	_expect(_climb_crosses_the_escarpment(route, terrain, climb),
		"escarpment-climb must progress plain/apron -> face -> plateau without lower-spine intersection")
	_expect(_rim_hugs_the_plateau_edge(route, terrain, rim),
		"clifftop-suspense lower spine must stay 8..30 m above plateau or edge terrain")
	_expect(_dive_crosses_outward_monotonically(route, terrain, dive),
		"cliff-dive terrain zones must progress from plateau through face to apron/plain without intersection")
	var maximum_dive_rise_m := _maximum_adjacent_height_rise_m(route, dive)
	_expect(is_finite(maximum_dive_rise_m) and maximum_dive_rise_m <= MAXIMUM_DIVE_RISE_M,
		"cliff-dive maximum adjacent centerline rise observed %.5f m; required <= %.3f m" % [
			maximum_dive_rise_m, MAXIMUM_DIVE_RISE_M,
		])
	_expect(_tunnel_uses_the_face_to_plain_corridor(route, terrain, tunnel),
		"tunnel-lsm3 must run monotonically outward from apron to its plain-side portal")
	var maximum_tunnel_plateau_excess_m := _maximum_plateau_excess_m(
		route, terrain, tunnel)
	_expect(is_finite(maximum_tunnel_plateau_excess_m) \
			and maximum_tunnel_plateau_excess_m < 0.0,
		"tunnel-lsm3 lower-spine maximum plateau-height excess observed %.3f m; required < 0.000 m" \
			% maximum_tunnel_plateau_excess_m)
	var stats: Dictionary = route.get("generation_stats", {})
	_expect(stats.get("accepted_integrations", -1) == 1 \
			and stats.get("planning_integrations", -1) == 2 \
			and stats.get("repair_count", -1) == 0,
		"terrain placement must report two planning integrations, one accepted integration, and zero repairs")
	_expect(float(terrain.relief) >= TERRAIN_RELIEF_MINIMUM_M \
			and float(terrain.relief) <= TERRAIN_RELIEF_MAXIMUM_M,
		"terrain relief stays in the 270..285 m support band")
	var route_envelope := float(route.bounds.size.y)
	_expect(route_envelope >= ROUTE_VERTICAL_ENVELOPE_MINIMUM_M \
			and route_envelope <= ROUTE_VERTICAL_ENVELOPE_MAXIMUM_M,
		"native route vertical envelope observed %.3f m; required 270..285 m" % route_envelope)
	var dive_drop := _window_drop_m(route, dive)
	_expect(dive_drop >= DIVE_DROP_MINIMUM_M and dive_drop <= DIVE_DROP_MAXIMUM_M,
		"native cliff-dive loss observed %.3f m; required 240..250 m" % dive_drop)
	var camel := _window(route, "marquee-camelback")
	var camel_prominence := _window_prominence_m(route, camel)
	_expect(camel_prominence >= CAMEL_PROMINENCE_MINIMUM_M \
			and camel_prominence <= CAMEL_PROMINENCE_MAXIMUM_M,
		"native camelback prominence observed %.3f m; required 245..255 m" % camel_prominence)


func _window_is_plain_with_clearance(
	route: Dictionary, terrain: Dictionary, window: Dictionary
) -> bool:
	for index in range(int(window.first), int(window.last) + 1):
		var clearance := _lower_spine_clearance_m(route, terrain, index)
		if _zone(terrain, _lower_spine(route, index)) != ZONE_PLAIN \
				or clearance < STATION_CLEARANCE_MINIMUM_M \
				or clearance > STORY_CLEARANCE_MAXIMUM_M:
			return false
	return true


func _window_is_plain_and_exposed(
	route: Dictionary, terrain: Dictionary, window: Dictionary
) -> bool:
	for index in range(int(window.first), int(window.last) + 1):
		if _zone(terrain, _lower_spine(route, index)) != ZONE_PLAIN \
				or _lower_spine_clearance_m(route, terrain, index) \
				< MINIMUM_EXPOSED_SPINE_CLEARANCE_M:
			return false
	return true


func _climb_crosses_the_escarpment(
	route: Dictionary, terrain: Dictionary, window: Dictionary
) -> bool:
	var zones := _compressed_zones(route, terrain, window)
	if zones.is_empty() or zones[0] > ZONE_APRON or zones[-1] < ZONE_FACE \
			or not zones.has(ZONE_FACE) or not _nondecreasing(zones):
		return false
	for index in range(int(window.first), int(window.last) + 1):
		if _lower_spine_clearance_m(route, terrain, index) \
				< MINIMUM_EXPOSED_SPINE_CLEARANCE_M:
			return false
	return true


func _rim_hugs_the_plateau_edge(
	route: Dictionary, terrain: Dictionary, window: Dictionary
) -> bool:
	for index in range(int(window.first), int(window.last) + 1):
		var zone := _zone(terrain, _lower_spine(route, index))
		var clearance := _lower_spine_clearance_m(route, terrain, index)
		if zone < ZONE_FACE or clearance < STORY_CLEARANCE_MINIMUM_M \
				or clearance > STORY_CLEARANCE_MAXIMUM_M:
			return false
	return true


func _dive_crosses_outward_monotonically(
	route: Dictionary, terrain: Dictionary, window: Dictionary
) -> bool:
	var zones := _compressed_zones(route, terrain, window)
	if zones.is_empty() or zones[0] != ZONE_PLATEAU or not zones.has(ZONE_FACE) \
			or zones[-1] > ZONE_APRON or not _nonincreasing(zones):
		return false
	for index in range(int(window.first), int(window.last) + 1):
		if _lower_spine_clearance_m(route, terrain, index) \
				< MINIMUM_EXPOSED_SPINE_CLEARANCE_M:
			return false
	return true


func _tunnel_uses_the_face_to_plain_corridor(
	route: Dictionary, terrain: Dictionary, window: Dictionary
) -> bool:
	var zones := _compressed_zones(route, terrain, window)
	if zones.is_empty() or zones[0] < ZONE_APRON or zones[0] > ZONE_FACE \
			or zones[-1] != ZONE_PLAIN or not _nonincreasing(zones):
		return false
	var has_apron := false
	for index in range(int(window.first), int(window.last) + 1):
		has_apron = has_apron or _zone(terrain, _lower_spine(route, index)) == ZONE_APRON
	var exit_spine := _lower_spine(route, int(window.last))
	var exit_distance := RideTerrain.edge_distance(terrain, exit_spine.x, exit_spine.z)
	return has_apron and exit_distance <= -8.0 \
		and exit_distance >= -float(terrain.apron_width)


func _maximum_adjacent_height_rise_m(route: Dictionary, window: Dictionary) -> float:
	var result := 0.0
	for index in range(int(window.first) + 1, int(window.last) + 1):
		result = maxf(result, route.positions[index].y - route.positions[index - 1].y)
	return result


func _maximum_plateau_excess_m(
	route: Dictionary, terrain: Dictionary, window: Dictionary
) -> float:
	var result := -INF
	for index in range(int(window.first), int(window.last) + 1):
		var spine := _lower_spine(route, index)
		var plateau_elevation_m := _plateau_elevation_m(terrain, spine)
		if not is_finite(plateau_elevation_m):
			return INF
		result = maxf(result, spine.y - plateau_elevation_m)
	return result


func _plateau_elevation_m(terrain: Dictionary, corridor_position: Vector3) -> float:
	var plateau_start_m := float(terrain.apron_width) + float(terrain.face_width)
	var distance_m := RideTerrain.edge_distance(
		terrain, corridor_position.x, corridor_position.z)
	var inward: Vector2 = terrain.edge_normal
	inward = inward.normalized()
	var plateau_position := Vector2(corridor_position.x, corridor_position.z) \
		+ inward * maxf(0.0, plateau_start_m - distance_m)
	return RideTerrain.height(terrain, plateau_position.x, plateau_position.y)


func _check_terrain_story_plan_contract(route: Dictionary) -> void:
	var story: Dictionary = route.get("terrain_story_plan", {})
	_expect(not story.is_empty(),
		"the public route must publish its resolved terrain-story plan")
	_expect(story.get("integration_frame", "") == "planned-world",
		"the accepted trajectory must be integrated directly in its planned world frame")
	var planning: Dictionary = story.get("planning", {})
	_expect(planning.get("capability_id", "") != "" \
			and planning.get("planning_integrations", -1) == 2,
		"the plan publishes two deterministic planning integrations: frame preflight and accepted closure")
	for key in ["station_edge_distance_m", "shelf_edge_distance_m",
			"dive_entry_edge_m", "dive_exit_edge_m", "tunnel_exit_edge_m",
			"station_lower_spine_agl_m", "summit_lower_spine_agl_m",
			"station_opener_maximum_edge_m", "sampled_station_opener_points"]:
		_expect(planning.has(key), "terrain-story planning report publishes %s" % key)
	_expect(float(planning.get("station_opener_maximum_edge_m", INF)) < 0.0 \
			and int(planning.get("sampled_station_opener_points", 0)) > 1,
		"planned sampled station/opener lower spine remains on the plain")
	var terrain: Dictionary = route.get("terrain", {})
	if not terrain.is_empty():
		var shelf_m := float(terrain.apron_width) + float(terrain.face_width)
		_expect(float(planning.get("dive_entry_edge_m", -INF)) >= shelf_m + 12.0,
			"planned role-13 entry stays at least 12 m behind the shelf edge")
		_expect(float(planning.get("dive_exit_edge_m", -INF)) \
				>= 0.20 * float(terrain.apron_width) \
				and float(planning.get("dive_exit_edge_m", INF)) \
				<= 0.55 * float(terrain.apron_width),
			"native role-13 exit stays elevated in the middle apron")
		_expect(float(planning.get("tunnel_exit_edge_m", INF)) <= -8.0,
			"the graded tunnel exits across the apron boundary onto the plain")
	var plan: Dictionary = story.get("plan", {})
	var plan_terrain: Dictionary = plan.get("terrain", {})
	var return_terrace: Dictionary = plan_terrain.get("return_terrace", {})
	var terrace_evidence: Dictionary = planning.get("return_terrace", {})
	_expect(var_to_bytes(plan_terrain) == var_to_bytes(terrain)
		and return_terrace.get("center_m") is Vector2
		and return_terrace.get("along") is Vector2
		and return_terrace.get("half_length_m") == 240.0
		and return_terrace.get("half_width_m") == 140.0
		and is_finite(float(return_terrace.get("elevation_m", NAN)))
		and float(return_terrace.get("elevation_m", 0.0)) > 0.0
		and float(return_terrace.get("elevation_m", INF)) <= 160.0,
		"the material plan carries the stamped deterministic return terrace")
	_expect(terrace_evidence.get("accepted_apex_world_m") is Vector3
		and is_finite(float(terrace_evidence.get("base_terrain_height_m", NAN)))
		and terrace_evidence.get("target_agl_m") == 155.0
		and terrace_evidence.get("elevation_m") == return_terrace.get("elevation_m")
		and terrace_evidence.get("half_length_m") == 240.0
		and terrace_evidence.get("half_width_m") == 140.0,
		"planning evidence records the actual apex, base terrain, target AGL, elevation, and dimensions")
	var decisions: Dictionary = plan.get("decisions", {})
	_expect(not decisions.has("station_inset_m"),
		"the material plan has no random fixed station inset")
	var frame: Dictionary = plan.get("terrain_frame", {})
	var station: Dictionary = plan.get("station", {})
	if frame.get("right") is Vector3 and station.get("tangent") is Vector3 \
			and station.get("up") is Vector3:
		_expect(frame.right.is_equal_approx(station.tangent.cross(station.up).normalized()),
			"terrain right uses the canonical T cross U handedness")
	var source := FileAccess.get_file_as_string("res://generator.gd")
	_expect(not source.contains("_canonical_layout") and not source.contains("_place_trajectory"),
		"production must not fit an accepted trajectory to terrain after integration")
	_expect(source.contains("RideProgram.terrain_story_capability"),
		"generator resolves station pose from the route owner's fixed-prefix capability")
	_expect(not source.contains("candidates") and not source.contains("sort_custom")
			and not source.contains("TERRAIN_PLACEMENT_STEP_M"),
		"placement is closed-form: no candidate list, no grid step, no scored search")


func _test_return_terrace_heightfield() -> void:
	var base := _terrain_fixture()
	var stamped := base.duplicate(true)
	stamped["return_terrace"] = {
		"center_m": Vector2(100.0, -40.0), "along": Vector2.RIGHT,
		"half_length_m": 240.0, "half_width_m": 140.0, "elevation_m": 80.0}
	var center := stamped.return_terrace.center_m
	var center_height := RideTerrain.height(stamped, center.x, center.y)
	var base_height := RideTerrain.height(base, center.x, center.y)
	_expect(center_height == base_height + 80.0,
		"return terrace center adds its exact authored elevation")
	_expect(RideTerrain.height(stamped, center.x + 240.0, center.y)
		== RideTerrain.height(base, center.x + 240.0, center.y)
		and RideTerrain.height(stamped, center.x, center.y + 140.0)
		== RideTerrain.height(base, center.x, center.y + 140.0),
		"return terrace support is exactly unchanged at and beyond its ellipse boundary")
	var repeated := stamped.duplicate(true)
	for point in [Vector2(100.0, -40.0), Vector2(220.0, -40.0), Vector2(100.0, 30.0)]:
		_expect(RideTerrain.height(stamped, point.x, point.y)
			== RideTerrain.height(repeated, point.x, point.y),
			"return terrace height is deterministic at %s" % point)
	var shoulder_r2 := 0.75
	var shoulder_point := center + Vector2(240.0 * sqrt(shoulder_r2), 0.0)
	var shoulder_input := 1.0 - shoulder_r2
	var cubic_smoothstep := shoulder_input * shoulder_input \
		* (3.0 - 2.0 * shoulder_input)
	var shoulder_weight := cubic_smoothstep * cubic_smoothstep
	var shoulder_height := RideTerrain.height(stamped, shoulder_point.x, shoulder_point.y) \
		- RideTerrain.height(base, shoulder_point.x, shoulder_point.y)
	_expect(absf(shoulder_height - 80.0 * shoulder_weight) <= 0.000001
		and shoulder_height < 80.0 * cubic_smoothstep,
		"return terrace uses pointwise-lower cubic-smoothstep-squared at known r2=%.2f" % shoulder_r2)
	var offsets := [0.0, 60.0, 120.0, 180.0, 220.0, 239.0]
	var previous_bump := INF
	for offset in offsets:
		var point := center + Vector2(offset, 0.0)
		var bump := RideTerrain.height(stamped, point.x, point.y) \
			- RideTerrain.height(base, point.x, point.y)
		_expect(bump <= previous_bump,
			"return terrace bump is monotone from center toward its boundary at %.1f m" % offset)
		previous_bump = bump
	var boundary_x := center.x + 240.0
	var inner_step := 0.1
	var inner_near := RideTerrain.height(stamped, boundary_x - inner_step, center.y) \
		- RideTerrain.height(base, boundary_x - inner_step, center.y)
	var inner_far := RideTerrain.height(stamped, boundary_x - 2.0 * inner_step, center.y) \
		- RideTerrain.height(base, boundary_x - 2.0 * inner_step, center.y)
	var inner_first_difference := inner_near / inner_step
	var inner_second_difference := (inner_far - 2.0 * inner_near) / (inner_step * inner_step)
	_expect(absf(inner_first_difference) <= 0.0001 and absf(inner_second_difference) <= 0.0001
		and RideTerrain.height(stamped, boundary_x + inner_step, center.y)
			== RideTerrain.height(base, boundary_x + inner_step, center.y),
		"return terrace cubic-smoothstep-squared shoulder is C2 at its near-boundary support transition")


func _test_return_terrace_tracks_actual_camelback_apex(route: Dictionary) -> void:
	var camelback := _window(route, "marquee-camelback")
	var terrain_story: Dictionary = route.get("terrain_story_plan", {})
	var plan: Dictionary = terrain_story.get("plan", {})
	var terrain: Dictionary = route.get("terrain", {})
	var terrace: Dictionary = plan.get("terrain", {}).get("return_terrace", {})
	var evidence: Dictionary = terrain_story.get("planning", {}).get("return_terrace", {})
	if camelback.is_empty() or plan.is_empty() or terrain.is_empty() or terrace.is_empty():
		_expect(false, "the published route must expose an accepted camelback and return terrace")
		return
	var apex_index := int(camelback.first)
	for index in range(int(camelback.first) + 1, int(camelback.last) + 1):
		if route.positions[index].y > route.positions[apex_index].y:
			apex_index = index
	var actual_apex: Vector3 = route.positions[apex_index]
	var actual_agl_m := actual_apex.y - RideTerrain.height(terrain, actual_apex.x, actual_apex.z)
	_expect(terrace.center_m.is_equal_approx(Vector2(actual_apex.x, actual_apex.z))
		and evidence.accepted_apex_world_m.is_equal_approx(actual_apex),
		"the published terrace center and evidence must use the actual final camelback maximum sample")
	_expect(absf(actual_agl_m - 155.0) <= 0.000001,
		"the actual final camelback maximum sample must be exactly 155 m AGL within production precision")


func _test_route_contract_return_terrace_proof(route: Dictionary) -> void:
	var story: Dictionary = route.get("terrain_story_plan", {})
	var plan: Dictionary = story.get("plan", {})
	var terrain: Dictionary = route.get("terrain", {})
	var camelback := _window(route, "marquee-camelback")
	if plan.is_empty() or terrain.is_empty() or camelback.is_empty():
		_expect(false, "seed 42 must publish inputs for the RouteContract return terrace proof")
		return
	var trajectory := {"position_m": route.positions, "tangent": route.tangents}
	var camelback_bounds := Vector2i(int(camelback.first), int(camelback.last))
	var accepted := RouteContract._return_terrace_proof(
		plan, trajectory, terrain, camelback_bounds)
	_expect(accepted.get("ok", false),
		"the RouteContract return terrace proof accepts the built seed-42 route")
	var corrupted_plan: Dictionary = plan.duplicate(true)
	var rotated_along: Vector2 = corrupted_plan.terrain.return_terrace.along.rotated(PI / 2.0)
	corrupted_plan.terrain.return_terrace.along = rotated_along
	corrupted_plan.terrain_frame.planning.return_terrace.along = rotated_along
	var rejected := RouteContract._return_terrace_proof(
		corrupted_plan, trajectory, corrupted_plan.terrain, camelback_bounds)
	_expect(not rejected.get("ok", true),
		"the RouteContract return terrace proof rejects jointly rotated terrace and evidence directions")


func _test_malformed_return_terrace_is_rejected(route: Dictionary) -> void:
	var plan: Dictionary = route.get("terrain_story_plan", {}).get("plan", {}).duplicate(true)
	if plan.is_empty():
		return
	var missing := plan.duplicate(true)
	missing.terrain.erase("return_terrace")
	_expect(not RideProgram._validate_plan(missing).get("ok", true),
		"a material plan missing its return terrace is rejected")
	var wrong_dimensions := plan.duplicate(true)
	wrong_dimensions.terrain.return_terrace.half_length_m = 241.0
	_expect(not RideProgram._validate_plan(wrong_dimensions).get("ok", true),
		"a return terrace with non-authored dimensions is rejected")
	var too_high := plan.duplicate(true)
	too_high.terrain.return_terrace.elevation_m = 160.000001
	_expect(not RideProgram._validate_plan(too_high).get("ok", true),
		"a return terrace above the elevation ceiling is rejected")
	var wrong_center := plan.duplicate(true)
	wrong_center.terrain.return_terrace.center_m += Vector2.RIGHT
	_expect(not RideProgram._validate_plan(wrong_center).get("ok", true),
		"a return terrace whose center misses the actual apex is rejected")
	var wrong_equation := plan.duplicate(true)
	wrong_equation.terrain_frame.planning.return_terrace.base_terrain_height_m += 1.0
	_expect(not RideProgram._validate_plan(wrong_equation).get("ok", true),
		"return terrace evidence with the wrong AGL equation is rejected")
	var coupled_height := plan.duplicate(true)
	coupled_height.terrain.return_terrace.elevation_m -= 1.0
	coupled_height.terrain_frame.planning.return_terrace.base_terrain_height_m += 1.0
	coupled_height.terrain_frame.planning.return_terrace.elevation_m -= 1.0
	_expect(not RideProgram._validate_plan(coupled_height).get("ok", true),
		"return terrace evidence rejects coupled base/elevation corruption")
	var malformed := plan.duplicate(true)
	malformed.terrain.return_terrace.half_width_m = 0.0
	var result := RideProgram._validate_plan(malformed)
	_expect(not result.get("ok", true),
		"a material plan with a nonpositive return terrace width is rejected")


func _terrain_fixture() -> Dictionary:
	return {"kind": "material", "edge_normal": Vector2.RIGHT, "edge_offset": 0.0,
		"wobble_amplitude": 1.0, "wobble_wavelength": 100.0, "apron_height": 50.0,
		"apron_width": 250.0, "face_height": 225.0, "face_width": 50.0,
		"detail_amplitude": 2.0, "noise_seed": 1}


func _window_drop_m(route: Dictionary, window: Dictionary) -> float:
	if window.is_empty():
		return NAN
	var low := INF
	for index in range(int(window.first), int(window.last) + 1):
		low = minf(low, float(route.positions[index].y))
	return float(route.positions[int(window.first)].y) - low


func _window_prominence_m(route: Dictionary, window: Dictionary) -> float:
	if window.is_empty():
		return NAN
	var high := -INF
	for index in range(int(window.first), int(window.last) + 1):
		high = maxf(high, float(route.positions[index].y))
	return high - maxf(float(route.positions[int(window.first)].y),
		float(route.positions[int(window.last)].y))


func _compressed_zones(
	route: Dictionary, terrain: Dictionary, window: Dictionary
) -> Array[int]:
	var result: Array[int] = []
	for index in range(int(window.first), int(window.last) + 1):
		var zone := _zone(terrain, _lower_spine(route, index))
		if result.is_empty() or result[-1] != zone:
			result.append(zone)
	return result


func _zone(terrain: Dictionary, position: Vector3) -> int:
	var distance := RideTerrain.edge_distance(terrain, position.x, position.z)
	if distance < 0.0:
		return ZONE_PLAIN
	if distance < float(terrain.apron_width):
		return ZONE_APRON
	if distance < float(terrain.apron_width) + float(terrain.face_width):
		return ZONE_FACE
	return ZONE_PLATEAU


func _nondecreasing(values: Array[int]) -> bool:
	for index in range(1, values.size()):
		if values[index] < values[index - 1]:
			return false
	return true


func _nonincreasing(values: Array[int]) -> bool:
	for index in range(1, values.size()):
		if values[index] > values[index - 1]:
			return false
	return true


func _lower_spine_clearance_m(route: Dictionary, terrain: Dictionary, index: int) -> float:
	var spine := _lower_spine(route, index)
	return spine.y - RideTerrain.height(terrain, spine.x, spine.z)


func _lower_spine(route: Dictionary, index: int) -> Vector3:
	# Main.build_rail_mesh renders the central spine at -1.55 m with 0.24 m tube radius.
	return route.positions[index] - route.ups[index] * LOWER_SPINE_SURFACE_OFFSET_M


func _window(route: Dictionary, story_id: String) -> Dictionary:
	for window in route.get("gesture_windows", []):
		if window.get("story_slot_id", "") == story_id:
			return window
	return {}


func _role(route: Dictionary, story_id: String, role_id: String) -> Dictionary:
	var window := _window(route, story_id)
	for role in window.get("role_windows", []):
		if role.get("id", "") == role_id:
			return role
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
