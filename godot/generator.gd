class_name RideGenerator
extends RefCounted

## Material-v1 facade. Generator owns only the accepted terrain-relative story plan;
## RideProgram owns native recipes and solves; Motion performs the sole accepted integration;
## RouteContract validates and publishes the accepted native route.

const Motion := preload("res://motion.gd")
const RideProgram := preload("res://ride_program.gd")
const RouteContract := preload("res://route_contract.gd")
const Terrain := preload("res://terrain.gd")

const PLAN_SCHEMA_VERSION := 1
const PRESET_ID := "material-v1"
const STATION_SPEED_MPS := 6.0
const SUMMIT_TRACK_AGL_BAND_M := Vector2(15.01, 24.95)
const INTEGRATION_STEP_S := 0.01
const DIVE_EXIT_APRON_BAND := Vector2(0.20, 0.55)
const DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M := Vector2(12.0, 40.0)
const TUNNEL_EXIT_PLAIN_OVERSHOOT_M := 8.0
const DIVE_CENTERLINE_CLEARANCE_M := 4.05
const DIVE_LOWER_SPINE_CLEARANCE_M := 2.05
const STATION_LOWER_SPINE_CLEARANCE_M := 4.05
const LOWER_SPINE_SURFACE_OFFSET_M := 1.79
const TERRAIN_PLACEMENT_STEP_M := 0.25


static func build(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var terrain: Dictionary = Terrain.generate(rng)
	var plan := _plan(terrain, rng)
	if plan.has("ok") and not plan.ok:
		return plan
	var initial_state := _initial_state(plan.station)
	var compiled := RideProgram.compile(plan, initial_state)
	if not compiled.get("ok", false):
		return compiled
	var settings: Variant = compiled.get("settings")
	if not settings is Dictionary:
		return _failure("ride program omitted integration settings")
	settings = settings.duplicate(true)
	settings["step_s"] = INTEGRATION_STEP_S
	var accepted_integrations := 0
	var trajectory := Motion.integrate(initial_state, compiled.get("spans", []), settings)
	if not trajectory.get("ok", false):
		return _failure("motion integration failed", trajectory.get("errors", []))
	accepted_integrations += 1
	var accepted: Dictionary = compiled.duplicate(true)
	accepted["generation_stats"] = {
		"accepted_integrations": accepted_integrations,
		"planning_integrations": int(plan.terrain_frame.planning.planning_integrations),
		"repair_count": 0,
	}
	return RouteContract.build(seed_value, terrain, initial_state, plan, accepted, trajectory)


static func _plan(terrain: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var inward_2d: Vector2 = terrain.edge_normal.normalized()
	var along_2d := Vector2(-inward_2d.y, inward_2d.x)
	var inward := Vector3(inward_2d.x, 0.0, inward_2d.y)
	var along := Vector3(along_2d.x, 0.0, along_2d.y)
	var side := -1 if rng.randf() < 0.5 else 1
	var along_m := rng.randf_range(60.0, 120.0)
	var placement_u := rng.randf()
	var roles := _material_roles()
	var dive_intent: Dictionary = roles[12].terrain
	var capability := RideProgram.terrain_story_capability(side)
	if not capability.get("ok", false):
		return _failure("terrain story capability failed", capability.get("errors", []))
	var role_13: Variant = capability.get("role_13_entry")
	var station_opener: Variant = capability.get("station_opener")
	var dive_footprint: Variant = capability.get("dive_footprint")
	if not role_13 is Dictionary or not station_opener is Dictionary \
			or not dive_footprint is Dictionary \
			or not role_13.get("offset_m") is Vector3 \
			or not role_13.get("tangent") is Vector3 \
			or not role_13.get("rider_up") is Vector3 \
			or not role_13.offset_m.is_finite() or not role_13.tangent.is_finite() \
			or not role_13.rider_up.is_finite() \
			or not is_finite(float(role_13.get("speed_mps", NAN))) \
			or not station_opener.get("positions_m") is PackedVector3Array \
			or not station_opener.get("rider_up") is PackedVector3Array \
			or station_opener.positions_m.is_empty() \
			or station_opener.positions_m.size() != station_opener.rider_up.size() \
			or int(station_opener.get("station_sample_count", 0)) <= 0 \
			or int(station_opener.station_sample_count) >= station_opener.positions_m.size() \
			or not dive_footprint.get("dive_exit_offset_m") is Vector3 \
			or not dive_footprint.get("tunnel_exit_offset_m") is Vector3 \
			or not dive_footprint.get("positions_m") is PackedVector3Array \
			or not dive_footprint.get("rider_up") is PackedVector3Array \
			or not dive_footprint.dive_exit_offset_m.is_finite() \
			or not dive_footprint.tunnel_exit_offset_m.is_finite() \
			or dive_footprint.positions_m.is_empty() \
			or dive_footprint.positions_m.size() != dive_footprint.rider_up.size():
		return _failure("terrain story capability omitted finite placement observations")
	if str(capability.get("capability_id", "")).is_empty() \
			or int(capability.get("planning_integrations", 0)) != 1 \
			or not capability.get("scale") is Dictionary:
		return _failure("terrain story capability omitted its versioned scale contract")
	var up := Vector3.UP
	var entry_offset_m: Vector3 = role_13.offset_m
	var dive_exit_offset_m: Vector3 = dive_footprint.dive_exit_offset_m
	var tunnel_exit_offset_m: Vector3 = dive_footprint.tunnel_exit_offset_m
	var dive_delta := Vector2(dive_exit_offset_m.x - entry_offset_m.x,
		dive_exit_offset_m.z - entry_offset_m.z)
	var terrain_delta := Vector2(tunnel_exit_offset_m.x - entry_offset_m.x,
		tunnel_exit_offset_m.z - entry_offset_m.z)
	var entry_direction := Vector2(role_13.tangent.x, role_13.tangent.z)
	var apron_width_m := float(terrain.apron_width)
	var shelf_edge_m := apron_width_m + float(terrain.face_width)
	var maximum_cross_ratio := float(dive_intent.maximum_cross_to_outward_ratio)
	var terrain_dive_span_m := float(terrain.face_width) + 0.75 * apron_width_m + 24.0
	var ratio_dive_span_m := dive_delta.length() / sqrt(1.0 + maximum_cross_ratio ** 2)
	var desired_dive_span_m := maxf(terrain_dive_span_m, ratio_dive_span_m)
	if dive_delta.length_squared() <= desired_dive_span_m * desired_dive_span_m \
			or desired_dive_span_m < dive_intent.outward_delta_m.x \
			or desired_dive_span_m > dive_intent.outward_delta_m.y \
			or entry_direction.length_squared() <= 0.000001:
		return _failure("terrain story capability has no feasible horizontal terrain chord")
	var dive_direction := dive_delta.normalized()
	var parallel := desired_dive_span_m / dive_delta.length()
	var perpendicular := sqrt(1.0 - parallel * parallel)
	var normal := Vector2(-dive_direction.y, dive_direction.x)
	var outward_local_candidates := [
		dive_direction * parallel + normal * perpendicular,
		dive_direction * parallel - normal * perpendicular,
	]
	entry_direction = entry_direction.normalized()
	var outward_local := Vector2.ZERO
	var best_opener_clearance_m := -INF
	var minimum_total_span_m := shelf_edge_m \
		+ DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M.x + TUNNEL_EXIT_PLAIN_OVERSHOOT_M
	var opener_positions: PackedVector3Array = station_opener.positions_m
	for candidate: Vector2 in outward_local_candidates:
		var candidate_right := Vector2(-candidate.y, candidate.x)
		var outward_delta_m := dive_delta.dot(candidate)
		var cross_ratio := absf(dive_delta.dot(candidate_right)) \
			/ maxf(outward_delta_m, 0.000001)
		if candidate.dot(entry_direction) < 0.25 or outward_delta_m <= 0.0 \
				or cross_ratio > maximum_cross_ratio + 0.000001 \
				or terrain_delta.dot(candidate) < minimum_total_span_m \
				or terrain_delta.normalized().dot(candidate) < 0.75:
			continue
		var opener_clearance_m := INF
		for position: Vector3 in opener_positions:
			opener_clearance_m = minf(opener_clearance_m,
				Vector2(position.x - entry_offset_m.x,
					position.z - entry_offset_m.z).dot(candidate))
		if opener_clearance_m > best_opener_clearance_m:
			best_opener_clearance_m = opener_clearance_m
			outward_local = candidate
	if outward_local == Vector2.ZERO:
		return _failure("terrain story capability cannot cross the full escarpment")
	var outward := -inward
	var outward_right := outward.cross(up).normalized()
	# The two analytic yaw solutions preserve the complete native ride. Pick the one
	# whose dive-entry tangent faces outward, while targeting a real apron exit.
	var tangent := (outward * outward_local.x \
		- outward_right * outward_local.y).normalized()
	var right := tangent.cross(up).normalized()
	var world_entry_offset := tangent * entry_offset_m.x + up * entry_offset_m.y \
		+ right * entry_offset_m.z
	var world_dive_exit_offset := tangent * dive_exit_offset_m.x + right * dive_exit_offset_m.z
	var world_tunnel_exit_offset := tangent * tunnel_exit_offset_m.x \
		+ right * tunnel_exit_offset_m.z
	var apron_origin := inward * float(terrain.edge_offset)
	var station_anchor := apron_origin + along * (side * along_m)
	var unshifted_entry := station_anchor \
		+ Vector3(world_entry_offset.x, 0.0, world_entry_offset.z)
	var unshifted_dive_exit := station_anchor + world_dive_exit_offset
	var unshifted_tunnel_exit := station_anchor + world_tunnel_exit_offset
	var unshifted_entry_edge_m := Terrain.edge_distance(
		terrain, unshifted_entry.x, unshifted_entry.z)
	var unshifted_dive_exit_edge_m := Terrain.edge_distance(
		terrain, unshifted_dive_exit.x, unshifted_dive_exit.z)
	var unshifted_tunnel_exit_edge_m := Terrain.edge_distance(
		terrain, unshifted_tunnel_exit.x, unshifted_tunnel_exit.z)
	var native_dive_edge_span_m := unshifted_entry_edge_m - unshifted_dive_exit_edge_m
	var native_tunnel_edge_span_m := unshifted_dive_exit_edge_m \
		- unshifted_tunnel_exit_edge_m
	if not is_finite(native_dive_edge_span_m) or not is_finite(native_tunnel_edge_span_m) \
			or native_dive_edge_span_m <= 0.0 or native_tunnel_edge_span_m <= 0.0:
		return _failure("terrain story capability has a non-outward native edge footprint")
	var minimum_entry_edge_m := maxf(
		shelf_edge_m + DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M.x,
		DIVE_EXIT_APRON_BAND.x * apron_width_m + native_dive_edge_span_m)
	var maximum_entry_edge_m := minf(
		shelf_edge_m + DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M.y,
		minf(DIVE_EXIT_APRON_BAND.y * apron_width_m + native_dive_edge_span_m,
			native_dive_edge_span_m + native_tunnel_edge_span_m \
				- TUNNEL_EXIT_PLAIN_OVERSHOOT_M))
	if minimum_entry_edge_m > maximum_entry_edge_m:
		return _failure("terrain apron cannot host the native dive footprint", [{
			"entry_edge_band_m": Vector2(minimum_entry_edge_m, maximum_entry_edge_m),
			"native_dive_edge_span_m": native_dive_edge_span_m,
			"native_tunnel_edge_span_m": native_tunnel_edge_span_m,
		}])
	var requested_dive_entry_edge_m := lerpf(
		minimum_entry_edge_m, maximum_entry_edge_m, placement_u)
	var placement := _solve_dive_placement(terrain, station_anchor, inward, tangent, right,
		world_entry_offset, float(unshifted_entry_edge_m), minimum_entry_edge_m,
		maximum_entry_edge_m, requested_dive_entry_edge_m, dive_footprint, station_opener)
	if not placement.get("ok", false):
		return _failure("terrain apron cannot clear the sampled native dive", [
			placement.get("diagnostic", {}),
		])
	var station_position: Vector3 = placement.station_position_m
	var target_dive_entry_edge_m: float = placement.dive_entry_edge_m
	var target_dive_exit_edge_m: float = placement.dive_exit_edge_m
	var target_tunnel_exit_edge_m: float = placement.tunnel_exit_edge_m
	var exit_fraction := target_dive_exit_edge_m / apron_width_m
	var station_edge_m := Terrain.edge_distance(
		terrain, station_position.x, station_position.z)
	var maximum_opener_edge_m := -INF
	var opener_rider_up: PackedVector3Array = station_opener.rider_up
	for sample_index in opener_positions.size():
		var native_position: Vector3 = opener_positions[sample_index]
		var world_position := station_position + tangent * native_position.x \
			+ up * native_position.y + right * native_position.z
		var native_up: Vector3 = opener_rider_up[sample_index]
		var world_up := tangent * native_up.x + up * native_up.y + right * native_up.z
		var lower_spine := world_position - world_up * LOWER_SPINE_SURFACE_OFFSET_M
		var edge_m := Terrain.edge_distance(terrain, lower_spine.x, lower_spine.z)
		if not world_position.is_finite() or not world_up.is_finite() or not is_finite(edge_m):
			return _failure("terrain story capability has a non-finite station/opener sample")
		maximum_opener_edge_m = maxf(maximum_opener_edge_m, edge_m)
	if maximum_opener_edge_m >= 0.0:
		return _failure("planned station/opener corridor does not remain on the plain", [{
			"maximum_opener_edge_m": maximum_opener_edge_m,
			"station_edge_m": station_edge_m,
		}])
	var planning := {
		"capability_id": str(capability.get("capability_id", "")),
		"planning_integrations": int(capability.get("planning_integrations", 0)),
		"station_edge_distance_m": station_edge_m,
		"station_opener_maximum_edge_m": maximum_opener_edge_m,
		"sampled_station_opener_points": opener_positions.size(),
		"shelf_edge_distance_m": shelf_edge_m,
		"native_dive_edge_span_m": native_dive_edge_span_m,
		"native_tunnel_edge_span_m": native_tunnel_edge_span_m,
		"dive_exit_apron_fraction": exit_fraction,
		"dive_entry_edge_m": target_dive_entry_edge_m,
		"dive_exit_edge_m": target_dive_exit_edge_m,
		"tunnel_exit_edge_m": target_tunnel_exit_edge_m,
		"requested_dive_entry_edge_m": requested_dive_entry_edge_m,
		"summit_track_agl_m": placement.summit_track_agl_m,
		"sampled_dive_points": dive_footprint.positions_m.size(),
		"planned_minimum_centerline_agl_m": placement.minimum_centerline_agl_m,
		"planned_minimum_lower_spine_agl_m": placement.minimum_lower_spine_agl_m,
		"scale": capability.get("scale", {}).duplicate(true),
	}
	var station := {"position_m": station_position, "tangent": tangent, "up": up}
	return {
		"schema_version": PLAN_SCHEMA_VERSION,
		"preset_id": PRESET_ID,
		"decisions": {"station_side": side, "station_along_m": along_m,
			"dive_exit_apron_fraction": exit_fraction},
		"terrain_frame": {"apron_origin_m": apron_origin, "inward": inward,
			"along": along, "up": up, "right": right,
			"shelf_height_m": float(terrain.relief), "planning": planning},
		"station": station,
		"corridor": {"approach_length_m": 230.0, "capture_length_m": 80.0,
			"brake_length_m": 150.0, "half_width_m": 150.0, "half_height_m": 75.0,
			"entry_speed_mps": Vector2(70.0, 80.0)},
		"route_length_m": Vector2(7800.0, 8200.0),
		"roles": roles,
	}


static func _solve_dive_placement(
	terrain: Dictionary, station_anchor: Vector3, inward: Vector3, tangent: Vector3,
	right: Vector3, world_entry_offset: Vector3, unshifted_entry_edge_m: float,
	minimum_entry_edge_m: float, maximum_entry_edge_m: float,
	requested_entry_edge_m: float, footprint: Dictionary, station_opener: Dictionary
) -> Dictionary:
	var positions: PackedVector3Array = footprint.positions_m
	var rider_up: PackedVector3Array = footprint.rider_up
	var opener_positions: PackedVector3Array = station_opener.positions_m
	var opener_up: PackedVector3Array = station_opener.rider_up
	var station_sample_count := int(station_opener.station_sample_count)
	var candidates: Array[float] = [requested_entry_edge_m]
	var steps := maxi(1, ceili(
		(maximum_entry_edge_m - minimum_entry_edge_m) / TERRAIN_PLACEMENT_STEP_M))
	for index in steps + 1:
		candidates.append(lerpf(minimum_entry_edge_m, maximum_entry_edge_m,
			float(index) / steps))
	candidates.sort_custom(func(a: float, b: float) -> bool:
		var a_score := absf(a - requested_entry_edge_m)
		var b_score := absf(b - requested_entry_edge_m)
		return a < b if a_score == b_score else a_score < b_score)
	var lowest_required_agl_m := INF
	for entry_edge_m in candidates:
		var station_position := station_anchor + inward * (
			entry_edge_m - unshifted_entry_edge_m)
		var entry_position := station_position \
			+ Vector3(world_entry_offset.x, 0.0, world_entry_offset.z)
		var entry_surface_m := Terrain.height(terrain, entry_position.x, entry_position.z)
		var required_station_y := entry_surface_m + SUMMIT_TRACK_AGL_BAND_M.x \
			- world_entry_offset.y
		for sample_index in positions.size():
			var native_position: Vector3 = positions[sample_index]
			var world_offset := tangent * native_position.x + Vector3.UP * native_position.y \
				+ right * native_position.z
			var center := station_position + world_offset
			required_station_y = maxf(required_station_y,
				Terrain.height(terrain, center.x, center.z) + DIVE_CENTERLINE_CLEARANCE_M \
				- world_offset.y)
			var native_up: Vector3 = rider_up[sample_index]
			var world_up := tangent * native_up.x + Vector3.UP * native_up.y \
				+ right * native_up.z
			var lower_offset := world_offset - world_up * LOWER_SPINE_SURFACE_OFFSET_M
			var lower := station_position + lower_offset
			required_station_y = maxf(required_station_y,
				Terrain.height(terrain, lower.x, lower.z) + DIVE_LOWER_SPINE_CLEARANCE_M \
				- lower_offset.y)
		for sample_index in opener_positions.size():
			var native_position: Vector3 = opener_positions[sample_index]
			var world_offset := tangent * native_position.x + Vector3.UP * native_position.y \
				+ right * native_position.z
			var native_up: Vector3 = opener_up[sample_index]
			var world_up := tangent * native_up.x + Vector3.UP * native_up.y \
				+ right * native_up.z
			var lower_offset := world_offset - world_up * LOWER_SPINE_SURFACE_OFFSET_M
			var lower := station_position + lower_offset
			var required_clearance := STATION_LOWER_SPINE_CLEARANCE_M \
				if sample_index < station_sample_count else DIVE_LOWER_SPINE_CLEARANCE_M
			required_station_y = maxf(required_station_y,
				Terrain.height(terrain, lower.x, lower.z) \
				+ required_clearance - lower_offset.y)
		var summit_agl_m := required_station_y + world_entry_offset.y - entry_surface_m
		lowest_required_agl_m = minf(lowest_required_agl_m, summit_agl_m)
		if summit_agl_m > SUMMIT_TRACK_AGL_BAND_M.y:
			continue
		station_position.y = required_station_y
		var placement := _dive_placement_observation(terrain, station_position, tangent, right,
			world_entry_offset, footprint)
		placement["summit_track_agl_m"] = summit_agl_m
		placement["ok"] = true
		return placement
	return {"ok": false, "diagnostic": {
		"entry_edge_band_m": Vector2(minimum_entry_edge_m, maximum_entry_edge_m),
		"requested_entry_edge_m": requested_entry_edge_m,
		"lowest_required_summit_agl_m": lowest_required_agl_m,
		"maximum_summit_agl_m": SUMMIT_TRACK_AGL_BAND_M.y,
	}}


static func _dive_placement_observation(
	terrain: Dictionary, station_position: Vector3, tangent: Vector3, right: Vector3,
	world_entry_offset: Vector3, footprint: Dictionary
) -> Dictionary:
	var positions: PackedVector3Array = footprint.positions_m
	var rider_up: PackedVector3Array = footprint.rider_up
	var minimum_centerline_agl_m := INF
	var minimum_lower_spine_agl_m := INF
	for sample_index in positions.size():
		var native_position: Vector3 = positions[sample_index]
		var world_offset := tangent * native_position.x + Vector3.UP * native_position.y \
			+ right * native_position.z
		var center := station_position + world_offset
		minimum_centerline_agl_m = minf(minimum_centerline_agl_m,
			center.y - Terrain.height(terrain, center.x, center.z))
		var native_up: Vector3 = rider_up[sample_index]
		var world_up := tangent * native_up.x + Vector3.UP * native_up.y \
			+ right * native_up.z
		var lower := center - world_up * LOWER_SPINE_SURFACE_OFFSET_M
		minimum_lower_spine_agl_m = minf(minimum_lower_spine_agl_m,
			lower.y - Terrain.height(terrain, lower.x, lower.z))
	var entry_position := station_position \
		+ Vector3(world_entry_offset.x, 0.0, world_entry_offset.z)
	var dive_exit_offset: Vector3 = footprint.dive_exit_offset_m
	var tunnel_exit_offset: Vector3 = footprint.tunnel_exit_offset_m
	var dive_exit := station_position + tangent * dive_exit_offset.x \
		+ right * dive_exit_offset.z
	var tunnel_exit := station_position + tangent * tunnel_exit_offset.x \
		+ right * tunnel_exit_offset.z
	return {
		"station_position_m": station_position,
		"dive_entry_edge_m": Terrain.edge_distance(
			terrain, entry_position.x, entry_position.z),
		"dive_exit_edge_m": Terrain.edge_distance(terrain, dive_exit.x, dive_exit.z),
		"tunnel_exit_edge_m": Terrain.edge_distance(terrain, tunnel_exit.x, tunnel_exit.z),
		"minimum_centerline_agl_m": minimum_centerline_agl_m,
		"minimum_lower_spine_agl_m": minimum_lower_spine_agl_m,
	}


static func _material_roles() -> Array:
	return [
		_role("station-launch", "station_launch", Vector2(140.0, 220.0),
			{"exit_speed_mps": Vector2(75.0, 80.0)}, [], {}, 1),
		_role("opener-twisted-drop", "twisted_drop", Vector2(540.0, 700.0),
			{"exit_speed_mps": Vector2(70.0, 82.0), "vertical_excursion_m": Vector2(70.0, 115.0)}),
		_role("opener-teardrop", "teardrop", Vector2(560.0, 720.0),
			{"heading_abs_rad": Vector2(deg_to_rad(110.0), deg_to_rad(190.0))}),
		_role("opener-release", "rising_release", Vector2(270.0, 390.0),
			{"height_delta_m": Vector2(25.0, 55.0)}),
		_role("act-one-immelmann", "immelmann", Vector2(370.0, 490.0),
			{"vertical_excursion_m": Vector2(100.0, 110.0)},
			[_phase(&"inverted_apex", {"rider_up_dot": Vector2(-1.0, 0.0),
				"hold_s": Vector2(1.0, 2.2)})]),
		_role("act-one-cutback", "cutback", Vector2(270.0, 360.0),
			{"heading_abs_rad": Vector2(deg_to_rad(135.0), deg_to_rad(200.0))},
			[_phase(&"inverted_apex", {"rider_up_dot": Vector2(-1.0, 0.0)})]),
		_role("act-one-loop", "helical_loop", Vector2(310.0, 420.0),
			{"vertical_excursion_m": Vector2(94.0, 100.0)},
			[_phase(&"inverted_apex", {"rider_up_dot": Vector2(-1.0, 0.0),
				"hold_s": Vector2(1.2, 2.6)})]),
		_role("act-one-airtime", "airtime_braid", Vector2(220.0, 310.0)),
		_role("act-one-wave", "wave_turn", Vector2(200.0, 290.0)),
		_role("climb-lsm2", "lsm2_climb", Vector2(520.0, 680.0),
			{"exit_speed_mps": Vector2(14.0, 24.0), "height_delta_m": Vector2(200.0, 225.0),
				"drive_distance_fraction": Vector2(0.65, 0.80)}, [], {}, 2),
		_role("clifftop-slow-crest", "slow_crest", Vector2(35.0, 80.0)),
		_role("clifftop-outward-rim", "outward_rim", Vector2(65.0, 120.0), {}, [],
			{"exit_tangent_outward_dot": Vector2(0.25, 1.0)}),
		_role("outward-dive", "cliff_dive", Vector2(350.0, 490.0),
			{"height_delta_m": Vector2(-250.0, -240.0)}, [],
			{"outward_delta_m": Vector2(70.0, 300.0),
				"maximum_cross_to_outward_ratio": 0.8,
				"minimum_centerline_agl_m": 4.0, "boundary_crossings": [
					{"boundary_id": &"shelf_edge", "from_side": 1, "to_side": -1},
					{"boundary_id": &"face", "from_side": 1, "to_side": -1}],
				"monotonic": PackedStringArray(["outward", "height_down"])}),
		_role("tunnel-lsm3", "tunnel_lsm3", Vector2(150.0, 220.0), {}, [],
			{"boundary_crossings": [{"boundary_id": &"apron_edge", "from_side": 1,
				"to_side": -1}]}, 3),
		# The record camelback is longer than the 328 km/h one: the same authored normal-g
		# profile sweeps more track per second at the 340 km/h entry, and the fall lengthens
		# to keep the marquee standing ~250 m above its valley.
		_role("camelback", "camelback", Vector2(900.0, 1180.0)),
		# Turn-a lengthens and height-a shortens against the old bands: the widened capture-entry
		# corridor lets the passive return carry more speed, and the solve spends it in the
		# loaded arc rather than the first airtime beat.
		_role("return-turn-a", "return_turn", Vector2(420.0, 620.0)),
		_role("return-height-a", "return_height", Vector2(290.0, 480.0)),
		_role("return-turn-b", "return_turn", Vector2(430.0, 570.0)),
		_role("return-height-b", "return_height", Vector2(450.0, 590.0)),
		_role("terminal-capture-brakes", "terminal_capture_brakes", Vector2(200.0, 240.0)),
	]


static func _role(
	id: String, recipe_id: String, length_m: Vector2, targets: Dictionary = {}, phases: Array = [],
	terrain: Dictionary = {}, propulsion_id: int = 0
) -> Dictionary:
	var role := {"id": id, "recipe_id": recipe_id, "length_m": length_m,
		"targets": targets}
	if not phases.is_empty(): role["phases"] = phases
	if not terrain.is_empty(): role["terrain"] = terrain
	if propulsion_id > 0: role["propulsion_id"] = propulsion_id
	return role


static func _phase(id: StringName, targets: Dictionary) -> Dictionary:
	return {"id": id, "targets": targets}


static func _initial_state(station: Dictionary) -> Dictionary:
	return {
		"position_m": station.position_m,
		"tangent": station.tangent,
		"rider_up": station.up,
		"speed_mps": STATION_SPEED_MPS,
		"distance_m": 0.0,
		"time_s": 0.0,
	}


static func _failure(context: String, details: Variant = []) -> Dictionary:
	var errors := PackedStringArray([context])
	if details is Array or details is PackedStringArray:
		for detail in details:
			errors.append(str(detail))
	return {"ok": false, "errors": errors}
