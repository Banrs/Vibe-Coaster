extends SceneTree

const Motion := preload("res://motion.gd")
const RideGenerator := preload("res://generator.gd")
const RidePlanner := preload("res://ride_planner.gd")
const RideProgram := preload("res://ride_program.gd")
const RideReturnSolve := preload("res://ride_return_solve.gd")
const Terrain := preload("res://terrain.gd")

const SEEDS := [11, 42, 20260809]


func _initialize() -> void:
	for seed_value in SEEDS:
		_probe_seed(seed_value)
	quit(0)


func _probe_seed(seed_value: int) -> void:
	var decisions := RidePlanner.resolve(seed_value)
	if not decisions is Dictionary or not decisions.get("streams") is Dictionary:
		_emit_error(seed_value, -1, "resolve", decisions)
		return
	var terrain_rng: Variant = decisions.streams.get(RidePlanner.STREAM_TERRAIN)
	if not terrain_rng is RandomNumberGenerator:
		_emit_error(seed_value, -1, "terrain_rng", decisions)
		return
	var terrain: Dictionary = Terrain.generate(terrain_rng)
	var plan := RideGenerator._plan(terrain, decisions)
	if not plan.get("ok", true):
		_emit_error(seed_value, -1, "plan", plan)
		return
	var plan_decisions: Dictionary = plan.get("decisions", {})
	var station_side := int(plan_decisions.get("station_side", 0))
	var station_along_m := float(plan_decisions.get("station_along_m", NAN))
	var placement_u := float(plan_decisions.get("dive_entry_aim_u", NAN))
	if station_side not in [-1, 1] or not is_finite(station_along_m) \
			or not is_finite(placement_u):
		_emit_error(seed_value, -1, "plan_decisions", plan_decisions)
		return

	var sequence: Array = decisions.sequence
	var story := {"sequence": sequence, "targets": decisions.targets}
	var inward_2d: Vector2 = terrain.edge_normal.normalized()
	var along_2d := Vector2(-inward_2d.y, inward_2d.x)
	var inward := Vector3(inward_2d.x, 0.0, inward_2d.y)
	var along := Vector3(along_2d.x, 0.0, along_2d.y)
	var roles := RideGenerator._material_roles(sequence)
	var dive_role: Dictionary = RideGenerator._role_by_id(roles, "outward-dive")
	var dive_intent: Dictionary = dive_role.get("terrain", {})
	var tunnel_length_m: Vector2 = RideGenerator._role_by_id(roles, "tunnel-lsm3").length_m
	var preflight := RideGenerator._capability_footprint(
		RideProgram.terrain_story_capability(station_side, story))
	if not preflight.get("ok", false):
		_emit_error(seed_value, -1, "preflight", preflight)
		return

	var apron_width_m := float(terrain.apron_width)
	var shelf_edge_m := apron_width_m + float(terrain.face_width)
	var terrain_dive_span_m := RideGenerator._terrain_dive_span_m(shelf_edge_m, apron_width_m)
	var minimum_total_span_m := shelf_edge_m \
		+ RideGenerator.DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M.x \
		+ RideGenerator.TUNNEL_EXIT_PLAIN_OVERSHOOT_M
	var current_outward_local := RideGenerator._outward_local(
		preflight, dive_intent, terrain_dive_span_m, minimum_total_span_m)
	var preflight_footprint := RideGenerator._terrain_footprint(
		terrain, preflight, inward, along, station_side, station_along_m, current_outward_local)
	var preflight_entry_band := RideGenerator._entry_edge_aim_band(
		shelf_edge_m, apron_width_m, float(preflight_footprint.dive_edge_span_m),
		float(preflight_footprint.tunnel_edge_span_m))
	if current_outward_local == Vector2.ZERO or preflight_entry_band.x > preflight_entry_band.y:
		_emit_error(seed_value, -1, "preflight_footprint", {
			"outward_local": _vec2(current_outward_local), "entry_band": _vec2(preflight_entry_band)})
		return
	var preflight_place := RideGenerator._place_station(terrain, inward, preflight_footprint,
		preflight, lerpf(preflight_entry_band.x, preflight_entry_band.y, placement_u))
	var closure_target := RideGenerator._closure_target(
		preflight_footprint, current_outward_local, shelf_edge_m, apron_width_m,
		terrain_dive_span_m, preflight_entry_band, tunnel_length_m,
		float(preflight.role_13.offset_m.y), float(preflight_place.summit_track_agl_m),
		dive_role.length_m)
	var accepted_capability := RideGenerator._capability_footprint(
		RideProgram.terrain_story_capability(station_side, story, closure_target))
	if not accepted_capability.get("ok", false):
		_emit_error(seed_value, -1, "accepted_prefix", accepted_capability)
		return

	var synthetic_plan: Dictionary = plan.duplicate(true)
	var synthetic_terrain: Dictionary = synthetic_plan.terrain.duplicate(true)
	synthetic_terrain["kind"] = "synthetic"
	synthetic_plan["terrain"] = synthetic_terrain
	var initial_state := RideGenerator._initial_state(synthetic_plan.station)
	var compiled := RideProgram.compile(synthetic_plan, initial_state)
	var accepted_outward_local := RideGenerator._outward_local(
		accepted_capability, dive_intent, terrain_dive_span_m, minimum_total_span_m)
	var accepted_outward_dot_preflight := accepted_outward_local.dot(current_outward_local)
	var accepted_outward_agrees_with_preflight := accepted_outward_local != Vector2.ZERO \
		and current_outward_local != Vector2.ZERO \
		and accepted_outward_dot_preflight >= RideGenerator.YAW_SOLUTION_AGREEMENT_DOT
	var roots := _analytic_roots(accepted_capability, dive_intent,
		terrain_dive_span_m, minimum_total_span_m)
	if roots.is_empty():
		_emit_error(seed_value, -1, "analytic_roots", {
			"preflight_outward_local": _vec2(current_outward_local),
			"accepted_outward_local": _vec2(accepted_outward_local)})
		return
	if not compiled.get("ok", false):
		for root_index in roots.size():
			_emit_root_error(seed_value, root_index, roots[root_index],
				"synthetic_compile", compiled, current_outward_local, accepted_outward_local,
				accepted_outward_dot_preflight, accepted_outward_agrees_with_preflight)
		return
	var return_report: Dictionary = compiled.return_plan.duplicate(true)
	return_report["ok"] = compiled.get("ok", false)
	var trajectory := Motion.integrate(initial_state, compiled.spans,
		RideProgram._settings(RideGenerator.INTEGRATION_STEP_S))
	if not trajectory.get("ok", false):
		for root_index in roots.size():
			_emit_root_error(seed_value, root_index, roots[root_index],
				"production_integration", trajectory, current_outward_local, accepted_outward_local,
				accepted_outward_dot_preflight, accepted_outward_agrees_with_preflight)
		return
	var local_apex := _camelback_local_apex(trajectory, compiled.spans, plan.station)
	if not local_apex.get("ok", false):
		for root_index in roots.size():
			_emit_root_error(seed_value, root_index, roots[root_index],
				"camelback_apex", local_apex, current_outward_local, accepted_outward_local,
				accepted_outward_dot_preflight, accepted_outward_agrees_with_preflight)
		return

	for root_index in roots.size():
		var root_record: Dictionary = roots[root_index]
		var first := _root_observation(seed_value, root_index, root_record.root,
			root_record.valid, root_record.validity, root_record.reasons,
			current_outward_local, accepted_outward_local,
			accepted_outward_dot_preflight, accepted_outward_agrees_with_preflight,
			terrain, inward, along, station_side, station_along_m, placement_u,
			shelf_edge_m, apron_width_m, accepted_capability, local_apex.offset_m,
			return_report)
		var repeat := _root_observation(seed_value, root_index, root_record.root,
			root_record.valid, root_record.validity, root_record.reasons,
			current_outward_local, accepted_outward_local,
			accepted_outward_dot_preflight, accepted_outward_agrees_with_preflight,
			terrain, inward, along, station_side, station_along_m, placement_u,
			shelf_edge_m, apron_width_m, accepted_capability, local_apex.offset_m,
			return_report)
		first["repeat_match"] = JSON.stringify(first) == JSON.stringify(repeat)
		print("TERRAIN_MACRO " + JSON.stringify(first))


func _analytic_roots(parts: Dictionary, dive_intent: Dictionary,
	terrain_dive_span_m: float, minimum_total_span_m: float) -> Array:
	var entry_offset_m: Vector3 = parts.role_13.offset_m
	var dive_exit_offset_m: Vector3 = parts.dive_footprint.dive_exit_offset_m
	var tunnel_exit_offset_m: Vector3 = parts.dive_footprint.tunnel_exit_offset_m
	var dive_delta := Vector2(dive_exit_offset_m.x - entry_offset_m.x,
		dive_exit_offset_m.z - entry_offset_m.z)
	var terrain_delta := Vector2(tunnel_exit_offset_m.x - entry_offset_m.x,
		tunnel_exit_offset_m.z - entry_offset_m.z)
	var entry_direction := Vector2(parts.role_13.tangent.x, parts.role_13.tangent.z)
	var maximum_cross_ratio := float(dive_intent.maximum_cross_to_outward_ratio)
	var desired_dive_span_m := maxf(terrain_dive_span_m,
		dive_delta.length() / sqrt(1.0 + maximum_cross_ratio ** 2))
	if dive_delta.length_squared() <= desired_dive_span_m * desired_dive_span_m \
			or desired_dive_span_m < dive_intent.outward_delta_m.x \
			or desired_dive_span_m > dive_intent.outward_delta_m.y \
			or entry_direction.length_squared() <= 0.000001:
		return []
	var dive_direction := dive_delta.normalized()
	var parallel := desired_dive_span_m / dive_delta.length()
	var perpendicular := sqrt(1.0 - parallel * parallel)
	var normal := Vector2(-dive_direction.y, dive_direction.x)
	entry_direction = entry_direction.normalized()
	var roots := []
	for candidate: Vector2 in [dive_direction * parallel + normal * perpendicular,
			dive_direction * parallel - normal * perpendicular]:
		var candidate_right := Vector2(-candidate.y, candidate.x)
		var outward_delta_m := dive_delta.dot(candidate)
		var cross_ratio := absf(dive_delta.dot(candidate_right)) \
			/ maxf(outward_delta_m, 0.000001)
		var entry_direction_dot := candidate.dot(entry_direction)
		var terrain_total_span_projection_m := terrain_delta.dot(candidate)
		var terrain_direction_dot := terrain_delta.normalized().dot(candidate)
		var validity := {
			"entry_direction": {"ok": entry_direction_dot >= 0.25,
				"value": entry_direction_dot, "minimum": 0.25},
			"outward_delta": {"ok": outward_delta_m > 0.0,
				"value": outward_delta_m, "minimum_exclusive": 0.0},
			"cross_ratio": {"ok": cross_ratio <= maximum_cross_ratio + 0.000001,
				"value": cross_ratio, "maximum": maximum_cross_ratio + 0.000001},
			"terrain_total_span": {"ok": terrain_total_span_projection_m >= minimum_total_span_m,
				"value": terrain_total_span_projection_m, "minimum": minimum_total_span_m},
			"terrain_direction": {"ok": terrain_direction_dot >= 0.75,
				"value": terrain_direction_dot, "minimum": 0.75},
		}
		var reasons := []
		for predicate in validity:
			if not validity[predicate].get("ok", false):
				reasons.append(str(predicate))
		roots.append({"root": candidate, "valid": reasons.is_empty(),
			"validity": validity, "reasons": reasons})
	return roots


func _camelback_local_apex(trajectory: Dictionary, spans: Array,
	station: Dictionary) -> Dictionary:
	var maximum_index := -1
	var maximum_y := -INF
	for index in trajectory.position_m.size():
		var span_index := int(trajectory.span_index[index])
		if span_index < 0 or span_index >= spans.size() \
				or not str(spans[span_index].get("span_id", "")).begins_with("camelback/"):
			continue
		var position: Vector3 = trajectory.position_m[index]
		if position.y > maximum_y:
			maximum_y = position.y
			maximum_index = index
	if maximum_index < 0:
		return {"ok": false, "reason": "no camelback samples"}
	var world_apex: Vector3 = trajectory.position_m[maximum_index]
	var delta: Vector3 = world_apex - station.position_m
	var tangent: Vector3 = station.tangent.normalized()
	var right: Vector3 = station.tangent.cross(station.up).normalized()
	var offset := Vector3(delta.dot(tangent), delta.y, delta.dot(right))
	if not offset.is_finite():
		return {"ok": false, "reason": "camelback apex is non-finite"}
	return {"ok": true, "offset_m": offset, "world_position_m": world_apex}


func _root_observation(seed_value: int, root_index: int, root: Vector2,
	root_valid: bool, root_validity: Dictionary, root_reasons: Array,
	current_outward_local: Vector2, accepted_outward_local: Vector2,
	accepted_outward_dot_preflight: float, accepted_outward_agrees_with_preflight: bool,
	terrain: Dictionary, inward: Vector3, along: Vector3, station_side: int,
	station_along_m: float, placement_u: float, shelf_edge_m: float, apron_width_m: float,
	parts: Dictionary, local_apex: Vector3, return_report: Dictionary) -> Dictionary:
	var footprint := RideGenerator._terrain_footprint(
		terrain, parts, inward, along, station_side, station_along_m, root)
	var dive_edge_span_m := float(footprint.get("dive_edge_span_m", NAN))
	var tunnel_edge_span_m := float(footprint.get("tunnel_edge_span_m", NAN))
	var edge_spans_finite_positive := is_finite(dive_edge_span_m) \
		and dive_edge_span_m > 0.0 and is_finite(tunnel_edge_span_m) \
		and tunnel_edge_span_m > 0.0
	var entry_band := RideGenerator._entry_edge_aim_band(shelf_edge_m, apron_width_m,
		dive_edge_span_m, tunnel_edge_span_m)
	var entry_band_finite := is_finite(entry_band.x) and is_finite(entry_band.y)
	var entry_band_valid := entry_band_finite and entry_band.x <= entry_band.y
	var ids: Array = return_report.get("scalar_ids", [])
	var residual_ids: Array = return_report.get("residual_ids", [])
	var values: Array = return_report.get("accepted_values", [])
	var duration_index := ids.find("record_release_core_duration_s")
	var bank_index := ids.find("record_release_bank_rad")
	var row := {"seed": seed_value, "root_index": root_index, "root_local": _vec2(root),
		"root_valid": root_valid, "root_validity": root_validity,
		"root_reasons": root_reasons,
		"selected_by_current_outward_local": root.dot(current_outward_local) > 0.999999,
		"selected_by_current_outward_local_dot": root.dot(current_outward_local),
		"preflight_outward_local": _vec2(current_outward_local),
		"accepted_outward_local": _vec2(accepted_outward_local),
		"accepted_outward_local_dot_to_preflight": accepted_outward_dot_preflight,
		"accepted_outward_local_agrees_with_preflight": accepted_outward_agrees_with_preflight,
		"station_side": station_side, "station_along_m": station_along_m,
		"placement_u": placement_u,
		"return": {"ok": return_report.get("ok", false),
			"evaluations": int(return_report.get("unique_evaluations", -1)),
			"control_count": values.size(),
			"residual_count": residual_ids.size()
				- (1 if residual_ids.has("camelback_apex_agl_band_m") else 0)},
		"accepted_release_duration_s": null,
		"accepted_release_bank_deg": null,
		"nominal_release_bank_deg": rad_to_deg(RideReturnSolve.RECORD_RELEASE_BANK_RAD),
		"root_observation_valid": false,
		"root_observation_reasons": [],
		"validity": {"edge_spans_finite_positive": edge_spans_finite_positive,
			"entry_band_finite": entry_band_finite, "entry_band_valid": entry_band_valid},
		"edge_spans_m": {"dive": dive_edge_span_m, "tunnel": tunnel_edge_span_m},
		"entry_band_m": _vec2(entry_band)}
	if duration_index >= 0 and bank_index >= 0 and duration_index < values.size() \
			and bank_index < values.size():
		row["accepted_release_duration_s"] = float(values[duration_index])
		row["accepted_release_bank_deg"] = rad_to_deg(float(values[bank_index]))
	else:
		row["root_observation_reasons"].append("return_report_release_controls_missing")

	var plain := {"valid": false, "reason": "not_derivable"}
	if entry_band_finite:
		var placement := RideGenerator._place_dive(terrain, inward, footprint, parts,
			lerpf(entry_band.x, entry_band.y, placement_u))
		var station_position: Vector3 = placement.station_position_m
		var apex_world := station_position + footprint.tangent * local_apex.x \
			+ Vector3.UP * local_apex.y + footprint.right * local_apex.z
		var apex_terrain := Terrain.height(terrain, apex_world.x, apex_world.z)
		var apex_edge := Terrain.edge_distance(terrain, apex_world.x, apex_world.z)
		plain = _plain_margins(terrain, parts, footprint, station_position)
		row["camel_apex"] = {"track_y": apex_world.y, "terrain": apex_terrain,
			"edge_distance": apex_edge, "agl": apex_world.y - apex_terrain}
		row["dive"] = {"entry_edge_distance": placement.dive_entry_edge_m,
			"exit_edge_distance": placement.dive_exit_edge_m,
			"tunnel_edge_distance": placement.tunnel_exit_edge_m}
	else:
		row["root_observation_reasons"].append("entry_band_nonfinite")
	row["station_opener_plain"] = plain
	row["validity"]["station_opener_plain"] = plain.get("valid", false)
	var geometry_valid := accepted_outward_agrees_with_preflight \
		and edge_spans_finite_positive and entry_band_valid \
		and plain.get("valid", false)
	var return_ok: bool = return_report.get("ok", true)
	row["root_observation_valid"] = root_valid and geometry_valid \
		and return_ok and row.get("accepted_release_duration_s") != null
	if not root_valid:
		row["root_observation_reasons"].append("generator_yaw_predicate_invalid")
	if not accepted_outward_agrees_with_preflight:
		row["root_observation_reasons"].append("accepted_outward_branch_disagrees")
	if not edge_spans_finite_positive:
		row["root_observation_reasons"].append("edge_spans_not_finite_positive")
	if not entry_band_valid:
		row["root_observation_reasons"].append("entry_band_invalid")
	if not plain.get("valid", false):
		row["root_observation_reasons"].append("station_opener_plain_invalid")
	if not return_ok:
		row["root_observation_reasons"].append("return_report_not_ok")
	return row


func _plain_margins(terrain: Dictionary, parts: Dictionary, footprint: Dictionary,
	station_position: Vector3) -> Dictionary:
	var station_edge := Terrain.edge_distance(terrain, station_position.x, station_position.z)
	var maximum_opener_edge := -INF
	for index in parts.station_opener.positions_m.size():
		var native_position: Vector3 = parts.station_opener.positions_m[index]
		var native_up: Vector3 = parts.station_opener.rider_up[index]
		var world_offset := footprint.tangent * native_position.x + Vector3.UP * native_position.y \
			+ footprint.right * native_position.z
		var world_up := footprint.tangent * native_up.x + Vector3.UP * native_up.y \
			+ footprint.right * native_up.z
		var lower := station_position + world_offset \
			- world_up * RideGenerator.LOWER_SPINE_SURFACE_OFFSET_M
		maximum_opener_edge = maxf(maximum_opener_edge,
			Terrain.edge_distance(terrain, lower.x, lower.z))
	var station_finite := is_finite(station_edge)
	var opener_finite := is_finite(maximum_opener_edge)
	return {"station_margin_m": -station_edge, "opener_margin_m": -maximum_opener_edge,
		"station_plain": station_finite and station_edge < 0.0,
		"opener_plain": opener_finite and maximum_opener_edge < 0.0,
		"valid": station_finite and opener_finite and maximum_opener_edge < 0.0}


func _vec2(value: Vector2) -> Array:
	return [value.x, value.y]


func _emit_error(seed_value: int, root_index: int, stage: String, details: Variant) -> void:
	print("TERRAIN_MACRO " + JSON.stringify({"seed": seed_value, "root_index": root_index,
		"error": {"stage": stage, "details": str(details)}}))


func _emit_root_error(seed_value: int, root_index: int, root_record: Dictionary,
	stage: String, details: Variant, current_outward_local: Vector2,
	accepted_outward_local: Vector2, accepted_outward_dot_preflight: float,
	accepted_outward_agrees_with_preflight: bool) -> void:
	print("TERRAIN_MACRO " + JSON.stringify({"seed": seed_value, "root_index": root_index,
		"root_local": _vec2(root_record.root), "root_valid": root_record.valid,
		"root_validity": root_record.validity, "root_reasons": root_record.reasons,
		"preflight_outward_local": _vec2(current_outward_local),
		"accepted_outward_local": _vec2(accepted_outward_local),
		"accepted_outward_local_dot_to_preflight": accepted_outward_dot_preflight,
		"accepted_outward_local_agrees_with_preflight": accepted_outward_agrees_with_preflight,
		"root_observation_valid": false,
		"error": {"stage": stage, "details": str(details)}}))
