class_name RouteContract
extends RefCounted

## The sole conversion from an accepted motion trajectory to the public packed route.

const GENERATOR_VERSION := "time-domain-v1"
const ROW_OFFSETS := [0.0, 2.15, 4.30, 6.45, 8.60, 10.75, 12.90]
const Terrain := preload("res://terrain.gd")
const ElementContract := preload("res://element_contract.gd")
const GeometryMetrics := preload("res://geometry_metrics.gd")
const INITIAL_POSITION_TOLERANCE_M := 0.000001
const INITIAL_FRAME_TOLERANCE := 0.000001
const INITIAL_SPEED_TOLERANCE_MPS := 0.000001
const LOWER_SPINE_SURFACE_OFFSET_M := 1.79
const TERRAIN_RELIEF_BAND_M := Vector2(270.0, 285.0)
const SUMMIT_AGL_BAND_M := Vector2(15.0, 25.0)
const DIVE_EXIT_APRON_BAND := Vector2(0.20, 0.55)
const DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M := Vector2(12.0, 40.0)
const TUNNEL_EXIT_PLAIN_OVERSHOOT_M := 8.0
# The capability is integrated in a station-local frame, then re-integrated in its planned
# world frame. Permit sub-0.5 m Float32 frame covariance while retaining the direct monotonic,
# overshoot, drop, and terrain-clearance gates below.
const TERRAIN_PLACEMENT_TOLERANCE_M := 0.35

const _TRAJECTORY_FIELDS := {
	"time_s": TYPE_PACKED_FLOAT64_ARRAY,
	"distance_m": TYPE_PACKED_FLOAT64_ARRAY,
	"position_m": TYPE_PACKED_VECTOR3_ARRAY,
	"tangent": TYPE_PACKED_VECTOR3_ARRAY,
	"rider_up": TYPE_PACKED_VECTOR3_ARRAY,
	"speed_mps": TYPE_PACKED_FLOAT64_ARRAY,
	"normal_g": TYPE_PACKED_FLOAT64_ARRAY,
	"lateral_g": TYPE_PACKED_FLOAT64_ARRAY,
	"drive_g": TYPE_PACKED_FLOAT64_ARRAY,
	"longitudinal_g": TYPE_PACKED_FLOAT64_ARRAY,
	"roll_rate_rad_s": TYPE_PACKED_FLOAT64_ARRAY,
	"curvature_vector_m_inv": TYPE_PACKED_VECTOR3_ARRAY,
	"span_index": TYPE_PACKED_INT32_ARRAY,
}


static func build(
	seed_value: int,
	terrain: Dictionary,
	initial_state: Dictionary,
	plan: Dictionary,
	compiled: Dictionary,
	trajectory: Dictionary
) -> Dictionary:
	var errors := _validate(terrain, initial_state, plan, compiled, trajectory)
	if not errors.is_empty():
		return {"ok": false, "errors": errors}

	var count: int = trajectory.time_s.size()
	var rights := PackedVector3Array()
	var banks := PackedFloat32Array()
	rights.resize(count)
	banks.resize(count)
	for index in count:
		var tangent: Vector3 = trajectory.tangent[index]
		var up: Vector3 = trajectory.rider_up[index]
		var right := tangent.cross(up).normalized()
		rights[index] = right
		banks[index] = _bank_degrees(tangent, up, banks[index - 1] if index > 0 else 0.0)

	var element_contracts := _element_contract_records(plan, compiled, trajectory, banks, terrain)
	if not element_contracts.ok:
		return {"ok": false, "errors": element_contracts.errors}

	var propulsion_ids := PackedInt32Array()
	var minimum_speeds := PackedFloat32Array()
	var gesture_indices := PackedInt32Array()
	propulsion_ids.resize(count)
	minimum_speeds.resize(count)
	gesture_indices.resize(count)
	gesture_indices.fill(-1)
	for index in count:
		var owner: int = trajectory.span_index[index]
		propulsion_ids[index] = int(compiled.propulsion_by_span[owner])
		minimum_speeds[index] = float(compiled.minimum_speed_by_span[owner])

	var gesture_windows := _gesture_windows(compiled.gesture_spans, trajectory)
	for gesture_index in gesture_windows.size():
		var window: Dictionary = gesture_windows[gesture_index]
		for sample_index in range(int(window.first), int(window.last) + 1):
			if gesture_indices[sample_index] != -1:
				return {"ok": false, "errors": PackedStringArray([
					"gesture windows overlap at sample %d" % sample_index,
				])}
			gesture_indices[sample_index] = gesture_index
	if gesture_indices.has(-1):
		return {"ok": false, "errors": PackedStringArray([
			"gesture windows do not cover every sample",
		])}

	var tunnels := _tunnel_ranges(compiled.tunnel_span_ranges, trajectory)
	var positions: PackedVector3Array = trajectory.position_m
	var terrain_proofs := _terrain_proofs(plan, compiled, trajectory, terrain)
	if not terrain_proofs.ok:
		return {"ok": false,
			"errors": PackedStringArray(terrain_proofs.get("errors", ["terrain_intent_miss"])),
			"failure": terrain_proofs.get("failure", {})}
	var planning: Dictionary = plan.terrain_frame.get("planning", {}).duplicate(true)
	planning.merge(terrain_proofs.planning, true)
	var role_bounds := {}
	var expected_role_ids := []
	var geometry_intents := {}
	for role_value in plan.get("roles", []):
		var role_id := str(role_value.get("id", ""))
		if role_id.is_empty():
			continue
		expected_role_ids.append(role_id)
		role_bounds[role_id] = _role_sample_bounds(compiled.role_spans, role_id, trajectory)
		if role_value.get("geometry") is Dictionary:
			geometry_intents[role_id] = role_value.geometry
	var measured_route := {"positions": trajectory.position_m, "tangents": trajectory.tangent,
		"banks": banks, "ups": trajectory.rider_up, "times": trajectory.time_s,
		"distances": trajectory.distance_m, "speeds": trajectory.speed_mps,
		"normal_g": trajectory.normal_g, "lateral_g": trajectory.lateral_g,
		"roll_rates": _degrees(trajectory.roll_rate_rad_s)}
	var geometry_audit := GeometryMetrics.role_audit(
		measured_route, role_bounds, expected_role_ids, terrain, geometry_intents)
	if not geometry_audit.ok:
		return {"ok": false, "errors": geometry_audit.errors}
	geometry_audit["transitions"] = GeometryMetrics.transition_audit(compiled.spans)
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"schema_version": 1,
		"generator_version": GENERATOR_VERSION,
		"seed": seed_value,
		"positions": positions,
		"tangents": trajectory.tangent,
		"ups": trajectory.rider_up,
		"rights": rights,
		"curvatures": trajectory.curvature_vector_m_inv,
		"banks": banks,
		"speeds": _float32(trajectory.speed_mps),
		"normal_g": _float32(trajectory.normal_g),
		"lateral_g": _float32(trajectory.lateral_g),
		"longitudinal_g": _float32(trajectory.longitudinal_g),
		"drive_g": _float32(trajectory.drive_g),
		"roll_rates": _degrees(trajectory.roll_rate_rad_s),
		"distances": _float32(trajectory.distance_m),
		"times": _float32(trajectory.time_s),
		"span_indices": trajectory.span_index,
		"gesture_indices": gesture_indices,
		"propulsion_ids": propulsion_ids,
		"minimum_speeds": minimum_speeds,
		"gesture_windows": gesture_windows,
		"tunnel_ranges": tunnels,
		"length": float(trajectory.distance_m[-1]),
		"duration": float(trajectory.time_s[-1]),
		"bounds": _bounds(positions),
		"terrain": terrain,
		"dense_output": trajectory.dense_output,
		"element_contracts": element_contracts.records,
		"geometry_audit": geometry_audit,
		"generation_stats": compiled.generation_stats.duplicate(true),
		"terrain_story_plan": {"plan": plan.duplicate(true),
			"integration_frame": "planned-world", "planning": planning,
			"role_allocations_m": compiled.role_allocations_m.duplicate(true),
			"return_entry_gate": compiled.return_entry_gate.duplicate(true),
			"terrain_proofs": terrain_proofs.proofs},
	}


static func window(route: Dictionary, story_id: String) -> Dictionary:
	for window in route.get("gesture_windows", []):
		if window.get("story_slot_id", "") == story_id:
			return window
	return {}


static func role(route: Dictionary, story_id: String, role_id: String) -> Dictionary:
	var window_data := window(route, story_id)
	for role_item in window_data.get("role_windows", []):
		if role_item.get("id", "") == role_id:
			return role_item
	return {}


static func _validate(
	terrain: Dictionary,
	initial_state: Dictionary,
	plan: Dictionary,
	compiled: Dictionary,
	trajectory: Dictionary
) -> PackedStringArray:
	var errors := PackedStringArray()
	if terrain.is_empty():
		errors.append("terrain is empty")
	if plan.get("preset_id") != "material-v1" \
			or var_to_bytes(compiled.get("plan", {})) != var_to_bytes(plan):
		errors.append("compiled program does not own the accepted material-v1 plan")
	_validate_initial_state(initial_state, errors)
	if not trajectory.get("ok", false):
		errors.append("motion trajectory was not accepted")
	var count := -1
	for field in _TRAJECTORY_FIELDS:
		var value: Variant = trajectory.get(field)
		if typeof(value) != int(_TRAJECTORY_FIELDS[field]):
			errors.append("trajectory %s is not the required packed array" % field)
			continue
		if count < 0:
			count = value.size()
		elif value.size() != count:
			errors.append("trajectory %s has an unaligned sample count" % field)
	if count < 2:
		errors.append("trajectory needs at least two samples")
	var dense: Variant = trajectory.get("dense_output")
	if not (dense is Dictionary):
		errors.append("trajectory dense output is missing")
	elif dense.is_empty():
		errors.append("trajectory dense output is missing")
	for key in ["spans", "gesture_spans", "tunnel_span_ranges"]:
		if not compiled.has(key) or not (compiled[key] is Array):
			errors.append("compiled program is missing %s" % key)
	if not (compiled.get("propulsion_by_span") is PackedInt32Array):
		errors.append("compiled propulsion map is not PackedInt32Array")
	if not (compiled.get("minimum_speed_by_span") is PackedFloat64Array):
		errors.append("compiled minimum-speed map is not PackedFloat64Array")
	var generation_stats: Variant = compiled.get("generation_stats")
	if not (generation_stats is Dictionary):
		errors.append("compiled program is missing generation_stats")
	else:
		if typeof(generation_stats.get("accepted_integrations")) != TYPE_INT \
				or generation_stats.accepted_integrations != 1:
			errors.append("compiled program must report exactly one accepted integration")
		if typeof(generation_stats.get("repair_count")) != TYPE_INT \
				or generation_stats.repair_count != 0:
			errors.append("compiled program must report zero repairs")
	if not errors.is_empty():
		return errors
	_validate_terminal_contract(compiled, trajectory, errors)
	if not errors.is_empty():
		return errors
	var span_count: int = compiled.spans.size()
	if span_count == 0:
		errors.append("compiled program has no spans")
	if compiled.propulsion_by_span.size() != span_count:
		errors.append("propulsion map does not align with spans")
	if compiled.minimum_speed_by_span.size() != span_count:
		errors.append("minimum-speed map does not align with spans")
	var seen_spans := {}
	var propulsion_zones := PackedInt32Array()
	var previous_propulsion := 0
	for index in count:
		var owner: int = trajectory.span_index[index]
		if owner < 0 or owner >= span_count:
			errors.append("sample %d has invalid span owner %d" % [index, owner])
			break
		seen_spans[owner] = true
		var propulsion_id: int = compiled.propulsion_by_span[owner]
		if propulsion_id < 0 or propulsion_id > 3:
			errors.append("sample %d has invalid propulsion id %d" % [index, propulsion_id])
			break
		if trajectory.drive_g[index] > 0.0 and propulsion_id == 0:
			errors.append("positive drive at sample %d has no propulsion zone" % index)
			break
		if propulsion_id != previous_propulsion:
			if propulsion_id > 0:
				propulsion_zones.append(propulsion_id)
			previous_propulsion = propulsion_id
		var tangent: Vector3 = trajectory.tangent[index]
		var up: Vector3 = trajectory.rider_up[index]
		if not trajectory.position_m[index].is_finite() or not tangent.is_finite() or not up.is_finite():
			errors.append("trajectory has a non-finite frame at sample %d" % index)
			break
		if (
			not is_finite(trajectory.speed_mps[index])
			or not is_finite(trajectory.normal_g[index])
			or not is_finite(trajectory.lateral_g[index])
			or not is_finite(trajectory.drive_g[index])
			or not is_finite(trajectory.longitudinal_g[index])
			or not is_finite(trajectory.roll_rate_rad_s[index])
			or not trajectory.curvature_vector_m_inv[index].is_finite()
		):
			errors.append("trajectory has a non-finite channel at sample %d" % index)
			break
		if absf(tangent.length_squared() - 1.0) > 0.002 or absf(up.length_squared() - 1.0) > 0.002 or absf(tangent.dot(up)) > 0.002:
			errors.append("trajectory has a degenerate frame at sample %d" % index)
			break
		if index > 0:
			if trajectory.time_s[index] <= trajectory.time_s[index - 1]:
				errors.append("trajectory time is not increasing at sample %d" % index)
				break
			if trajectory.distance_m[index] <= trajectory.distance_m[index - 1]:
				errors.append("trajectory distance is not increasing at sample %d" % index)
				break
			if owner < trajectory.span_index[index - 1]:
				errors.append("trajectory span ownership reverses at sample %d" % index)
				break
	if seen_spans.size() != span_count:
		errors.append("trajectory does not contain every compiled span")
	if propulsion_zones != PackedInt32Array([1, 2, 3]):
		errors.append("positive propulsion zones must be exactly [1, 2, 3] in order")
	if count >= 2 and not _initial_state_matches(trajectory, initial_state):
		errors.append("trajectory does not begin at the declared initial state")
	var next_gesture_span := 0
	var window_ids := {}
	for gesture in compiled.gesture_spans:
		_validate_window_record(gesture, span_count, "gesture", "", window_ids, errors)
		var peak_onset: Variant = gesture.get("peak_profile_normal_onset_estimate_gps")
		if typeof(peak_onset) != TYPE_FLOAT and typeof(peak_onset) != TYPE_INT:
			errors.append("gesture peak_profile_normal_onset_estimate_gps must be a finite nonnegative scalar")
		elif not is_finite(float(peak_onset)) or float(peak_onset) < 0.0:
			errors.append("gesture peak_profile_normal_onset_estimate_gps must be a finite nonnegative scalar")
		if int(gesture.get("first_span", -1)) != next_gesture_span:
			errors.append("gesture windows do not cover spans in order")
		next_gesture_span = int(gesture.get("last_span", -1)) + 1
		var next_role_span := int(gesture.get("first_span", -1))
		var role_occurrences := {}
		for role in gesture.get("role_windows", []):
			_validate_window_record(role, span_count, "role",
				str(gesture.get("story_slot_id", "")), window_ids, errors)
			var role_id := str(role.get("id", ""))
			var expected_occurrence := int(role_occurrences.get(role_id, 0))
			if int(role.get("occurrence", -1)) != expected_occurrence:
				errors.append("role window %s has a nondeterministic occurrence" % role_id)
			role_occurrences[role_id] = expected_occurrence + 1
			if int(role.get("first_span", -1)) != next_role_span:
				errors.append("role windows do not cover gesture spans in order")
			next_role_span = int(role.get("last_span", -1)) + 1
		if next_role_span != int(gesture.get("last_span", -1)) + 1:
			errors.append("role windows do not cover their gesture")
	if next_gesture_span != span_count:
		errors.append("gesture windows do not cover every span")
	for span_range in compiled.tunnel_span_ranges:
		_validate_span_range(span_range, span_count, "tunnel", errors)
	_validate_role_lengths(plan, compiled, trajectory, terrain, errors)
	return errors


## The one fixture seam: synthetic RouteContract fixtures carry `terrain.kind == "synthetic"`
## and skip the material gates. Production terrain is stamped `"material"` by `Terrain.generate`;
## anything else is an error, so a renamed or missing stamp can never silently disable the
## role-length, element-contract and terrain-proof gates.
static func _is_synthetic_terrain(terrain: Dictionary, errors: PackedStringArray) -> bool:
	var kind := str(terrain.get("kind", ""))
	if kind == "synthetic":
		return true
	if kind != "material":
		errors.append("terrain kind must be 'material' or 'synthetic', got '%s'" % kind)
		return true
	return false


## The declared per-role length bands are a claim about the built ride, so they are measured on
## the accepted trajectory here: the one place that holds both the plan and its geometry.
## Roles partition the route, so a role spans from its first sample to the next role's.
static func _validate_role_lengths(
	plan: Dictionary, compiled: Dictionary, trajectory: Dictionary, terrain: Dictionary,
	errors: PackedStringArray
) -> void:
	if _is_synthetic_terrain(terrain, errors):
		return
	var roles: Variant = plan.get("roles")
	if not roles is Array or roles.is_empty():
		errors.append("the accepted plan declares no role length bands")
		return
	var role_spans: Variant = compiled.get("role_spans")
	if not role_spans is Dictionary:
		errors.append("compiled program is missing role_spans")
		return
	var last_sample: int = trajectory.distance_m.size() - 1
	for role in roles:
		var role_id := str(role.get("id", "")) if role is Dictionary else ""
		var band: Variant = role.get("length_m") if role is Dictionary else null
		if role_id.is_empty() or not band is Vector2:
			errors.append("a declared role has no id and length band")
			continue
		var bounds: Variant = role_spans.get(role_id)
		if not bounds is Vector2i or bounds.x < 0 or bounds.y < bounds.x:
			errors.append("role %s has no generated span ownership" % role_id)
			continue
		var first: int = trajectory.span_index.find(bounds.x)
		var last: int = trajectory.span_index.rfind(bounds.y)
		if first < 0 or last < first:
			errors.append("role %s has no generated span ownership" % role_id)
			continue
		var length_m: float = float(trajectory.distance_m[mini(last + 1, last_sample)]) \
			- float(trajectory.distance_m[first])
		if length_m < band.x or length_m > band.y:
			errors.append("role %s generated length %.1f m is outside its declared band %.1f-%.1f m"
				% [role_id, length_m, band.x, band.y])


static func _validate_window_record(
	record: Variant, span_count: int, label: String, story_slot_id: String,
	window_ids: Dictionary, errors: PackedStringArray
) -> void:
	if not record is Dictionary:
		errors.append("%s window is not a dictionary" % label)
		return
	var id_key := "story_slot_id" if label == "gesture" else "id"
	var stable_id := str(record.get(id_key, ""))
	if not _valid_slug(stable_id):
		errors.append("%s window has no stable id" % label)
	if label == "gesture" and not (record.get("role_windows", []) is Array):
		errors.append("gesture role windows are not an array")
	var kind := str(record.get("diagnostic_kind", ""))
	if not kind.is_empty() and not _valid_slug(kind):
		errors.append("%s window has an invalid diagnostic_kind" % label)
	var occurrence: Variant = record.get("occurrence")
	if typeof(occurrence) != TYPE_INT or int(occurrence) < 0:
		errors.append("%s window has an invalid occurrence" % label)
	var owner := stable_id if label == "gesture" else story_slot_id
	var role := "whole" if label == "gesture" else stable_id
	var expected_id := _window_id(owner, role, int(occurrence), kind) \
		if typeof(occurrence) == TYPE_INT else ""
	var window_id := str(record.get("window_id", ""))
	if window_id != expected_id:
		errors.append("%s window has an invalid window_id" % label)
	elif window_ids.has(window_id):
		errors.append("duplicate diagnostic window id %s" % window_id)
	else:
		window_ids[window_id] = true
	_validate_span_range(Vector2i(record.get("first_span", -1), record.get("last_span", -1)), span_count, label, errors)


static func _validate_initial_state(
	initial_state: Dictionary, errors: PackedStringArray
) -> void:
	for key in ["position_m", "tangent", "rider_up"]:
		var value: Variant = initial_state.get(key)
		if not (value is Vector3) or not value.is_finite():
			errors.append("initial state %s must be a finite Vector3" % key)
	var speed: Variant = initial_state.get("speed_mps")
	if not _finite_number(speed):
		errors.append("initial state speed_mps must be finite")
	if not errors.is_empty():
		return
	var tangent: Vector3 = initial_state.tangent
	var rider_up: Vector3 = initial_state.rider_up
	if tangent.length_squared() <= INITIAL_FRAME_TOLERANCE * INITIAL_FRAME_TOLERANCE:
		errors.append("initial state tangent must be nonzero")
	elif (rider_up - tangent.normalized() * rider_up.dot(tangent.normalized())).length_squared() \
			<= INITIAL_FRAME_TOLERANCE * INITIAL_FRAME_TOLERANCE:
		errors.append("initial state frame must be nondegenerate")


static func _initial_state_matches(trajectory: Dictionary, initial_state: Dictionary) -> bool:
	var expected_tangent: Vector3 = initial_state.tangent.normalized()
	var expected_up: Vector3 = initial_state.rider_up \
		- expected_tangent * initial_state.rider_up.dot(expected_tangent)
	expected_up = expected_up.normalized()
	return trajectory.position_m[0].distance_to(initial_state.position_m) \
			<= INITIAL_POSITION_TOLERANCE_M \
		and trajectory.tangent[0].distance_to(expected_tangent) <= INITIAL_FRAME_TOLERANCE \
		and trajectory.rider_up[0].distance_to(expected_up) <= INITIAL_FRAME_TOLERANCE \
		and absf(trajectory.speed_mps[0] - float(initial_state.speed_mps)) \
			<= INITIAL_SPEED_TOLERANCE_MPS


static func _validate_terminal_contract(
	compiled: Dictionary, trajectory: Dictionary, errors: PackedStringArray
) -> void:
	var contract: Variant = compiled.get("terminal_contract")
	if not (contract is Dictionary):
		errors.append("compiled program is missing terminal_contract")
		return
	for key in ["station_position_m", "station_tangent", "station_up"]:
		var value: Variant = contract.get(key)
		if not (value is Vector3) or not value.is_finite():
			errors.append("terminal_contract %s must be a finite Vector3" % key)
	for key in ["terminal_speed_mps", "position_tolerance_m", "angle_tolerance_rad",
			"speed_tolerance_mps"]:
		if not _finite_number(contract.get(key)):
			errors.append("terminal_contract %s must be finite" % key)
	for key in ["position_tolerance_m", "angle_tolerance_rad", "speed_tolerance_mps"]:
		if _finite_number(contract.get(key)) and float(contract[key]) <= 0.0:
			errors.append("terminal_contract %s must be positive" % key)
	if not errors.is_empty():
		return
	var target_tangent: Vector3 = contract.station_tangent
	var target_up: Vector3 = contract.station_up
	if target_tangent.length_squared() <= 0.0 or target_up.length_squared() <= 0.0 \
			or absf(target_tangent.normalized().dot(target_up.normalized())) > 0.000001:
		errors.append("terminal_contract station frame must be nondegenerate and orthogonal")
		return
	var last: int = trajectory.position_m.size() - 1
	if trajectory.position_m[last].distance_to(contract.station_position_m) \
			> float(contract.position_tolerance_m):
		errors.append("terminal position exceeds position_tolerance_m")
	if _angle_between(trajectory.tangent[last], target_tangent) \
			> float(contract.angle_tolerance_rad):
		errors.append("terminal tangent exceeds angle_tolerance_rad")
	if _angle_between(trajectory.rider_up[last], target_up) > float(contract.angle_tolerance_rad):
		errors.append("terminal up exceeds angle_tolerance_rad")
	if absf(trajectory.speed_mps[last] - float(contract.terminal_speed_mps)) \
			> float(contract.speed_tolerance_mps):
		errors.append("terminal speed exceeds speed_tolerance_mps")


static func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))



## Measure every whole material role on the one accepted production trajectory. Unadopted roles
## are not judged, but they still publish their geometry so absence of a reviewed threshold cannot
## become absence of evidence. Adopted roles fail route construction on any contract violation.
static func _element_contract_records(
	plan: Dictionary, compiled: Dictionary, trajectory: Dictionary,
	banks: PackedFloat32Array, terrain: Dictionary
) -> Dictionary:
	var errors := PackedStringArray()
	# Synthetic RouteContract fixtures deliberately test terminal/propulsion/window
	# mechanics without a material story. Production terrain never takes this seam.
	if _is_synthetic_terrain(terrain, errors):
		return {"ok": errors.is_empty(), "records": {}, "errors": errors}
	var intents_value: Variant = compiled.get("element_intents")
	var role_spans_value: Variant = compiled.get("role_spans")
	if not intents_value is Dictionary:
		errors.append("compiled program is missing element_intents")
	if not role_spans_value is Dictionary:
		errors.append("compiled program is missing role_spans for element contracts")
	if not errors.is_empty():
		return {"ok": false, "records": {}, "errors": errors}
	var intents: Dictionary = intents_value
	var role_spans: Dictionary = role_spans_value
	var expected_ids := []
	for role_value in plan.get("roles", []):
		if not role_value is Dictionary or str(role_value.get("id", "")).is_empty():
			errors.append("plan contains a material role without an id")
			continue
		expected_ids.append(str(role_value.id))
	var actual_ids: Array = intents.keys()
	actual_ids.sort()
	var sorted_expected := expected_ids.duplicate()
	sorted_expected.sort()
	if actual_ids != sorted_expected:
		errors.append("element_intents must exactly cover the plan's material roles")
	if not errors.is_empty():
		return {"ok": false, "records": {}, "errors": errors}

	var measured_route := {
		"positions": trajectory.position_m,
		"tangents": trajectory.tangent,
		"banks": banks,
	}
	var records := {}
	for role_id_value in expected_ids:
		var role_id := str(role_id_value)
		var intent_record_value: Variant = intents.get(role_id)
		if not intent_record_value is Dictionary:
			errors.append("element intent '%s' is not a Dictionary" % role_id)
			continue
		var intent_record: Dictionary = intent_record_value
		var sample_bounds := _role_sample_bounds(role_spans, role_id, trajectory)
		if sample_bounds.x < 0 or sample_bounds.y < sample_bounds.x:
			errors.append("element '%s' has no whole-role sample bounds" % role_id)
			continue
		var measurement := ElementContract.measure(
			measured_route, sample_bounds.x, sample_bounds.y)
		if measurement.get("status") != "measured":
			errors.append("element '%s' could not be measured: %s" % [
				role_id, str(measurement.get("reason", "unknown"))])
			continue
		var status := str(intent_record.get("status", ""))
		var intent_value: Variant = intent_record.get("intent")
		if status == "unadopted":
			if not intent_value is Dictionary or not intent_value.is_empty():
				errors.append("unadopted element '%s' carries a hidden intent" % role_id)
				continue
			var reason := str(intent_record.get("reason", ""))
			if reason.is_empty():
				errors.append("unadopted element '%s' has no reason" % role_id)
				continue
			records[role_id] = {
				"status": "unadopted",
				"reason": reason,
				"intent": {},
				"measurement": measurement,
				"violations": PackedStringArray(),
			}
		elif status == "adopted":
			if not intent_value is Dictionary or intent_value.is_empty():
				errors.append("adopted element '%s' has no executable intent" % role_id)
				continue
			var violations := ElementContract.validate(intent_value, measurement)
			records[role_id] = {
				"status": "adopted",
				"reason": str(intent_record.get("reason", "")),
				"intent": intent_value.duplicate(true),
				"measurement": measurement,
				"violations": violations,
			}
			for violation in violations:
				errors.append("element '%s' geometry contract: %s" % [role_id, violation])
		else:
			errors.append("element '%s' has invalid intent status '%s'" % [role_id, status])
	return {"ok": errors.is_empty(), "records": records, "errors": errors}


static func _terrain_proofs(
	plan: Dictionary, compiled: Dictionary, trajectory: Dictionary, terrain: Dictionary
) -> Dictionary:
	var kind_errors := PackedStringArray()
	if _is_synthetic_terrain(terrain, kind_errors):
		return {"ok": kind_errors.is_empty(), "proofs": {}, "planning": {},
			"errors": kind_errors}
	var role_spans: Variant = compiled.get("role_spans")
	if not role_spans is Dictionary:
		return _terrain_failure("", "role_spans", {}, {"missing": true})
	var frame: Variant = plan.get("terrain_frame")
	var planned: Variant = frame.get("planning") if frame is Dictionary else null
	var scale: Variant = planned.get("scale") if planned is Dictionary else null
	if not frame is Dictionary or not planned is Dictionary or not scale is Dictionary:
		return _terrain_failure("", "terrain_planning", {}, {"missing": true})
	for key in ["route_vertical_envelope_m", "dive_drop_m", "camel_prominence_m"]:
		if not scale.get(key) is Vector2:
			return _terrain_failure("", "scale.%s" % key, {}, {"missing": true})
	for key in ["native_dive_edge_span_m", "native_tunnel_edge_span_m",
			"dive_exit_apron_fraction", "dive_entry_edge_m", "dive_exit_edge_m",
			"tunnel_exit_edge_m"]:
		if not _finite_number(planned.get(key)):
			return _terrain_failure("", "terrain_planning.%s" % key, {}, {"missing": true})
	var route_envelope_m := _vertical_envelope_m(trajectory.position_m)
	var scale_margin := minf(
		_band_margin(float(terrain.relief), TERRAIN_RELIEF_BAND_M),
		_band_margin(route_envelope_m, scale.route_vertical_envelope_m))
	if scale_margin < -0.0001:
		return _terrain_failure("", "native_route_scale",
			{"terrain_relief_m": TERRAIN_RELIEF_BAND_M,
				"route_vertical_envelope_m": scale.route_vertical_envelope_m},
			{"terrain_relief_m": terrain.relief,
				"route_vertical_envelope_m": route_envelope_m})
	var proofs := {}
	var rim_bounds := _role_sample_bounds(role_spans, "clifftop-outward-rim", trajectory)
	if rim_bounds.x < 0:
		return _terrain_failure("clifftop-outward-rim", "role_spans", {}, {"missing": true})
	var outward: Vector3 = -plan.terrain_frame.inward
	var rim_dot: float = trajectory.tangent[rim_bounds.y].normalized().dot(outward)
	var rim_margin := rim_dot - 0.25
	if rim_margin < 0.0:
		return _terrain_failure("clifftop-outward-rim", "exit_tangent_outward_dot",
			{"band": Vector2(0.25, 1.0)}, {"value": rim_dot, "margin": rim_margin})
	proofs["clifftop-outward-rim"] = {"ok": true, "exit_tangent_outward_dot": rim_dot,
		"minimum_margin": rim_margin}

	var dive_bounds := _role_sample_bounds(role_spans, "outward-dive", trajectory)
	if dive_bounds.x < 0:
		return _terrain_failure("outward-dive", "role_spans", {}, {"missing": true})
	var dive := _terrain_path_observation(trajectory, terrain, frame,
		dive_bounds.x, dive_bounds.y)
	var shelf_edge_m := float(terrain.apron_width) + float(terrain.face_width)
	var dive_entry_edge_m := float(dive.signed_edge_m[0])
	var dive_exit_edge_m := float(dive.signed_edge_m[-1])
	var dive_drop_m := _drop_m(trajectory.position_m, dive_bounds)
	var summit_agl_m: float = trajectory.position_m[dive_bounds.x].y - Terrain.height(terrain,
		trajectory.position_m[dive_bounds.x].x, trajectory.position_m[dive_bounds.x].z)
	var dive_intent: Dictionary = _role_terrain_intent(plan, "outward-dive")
	var cross_to_outward_ratio: float = absf(dive.cross_delta_m) \
		/ maxf(dive.outward_delta_m, 0.000001)
	var dive_margin := INF
	for term in [
		_band_margin(dive.outward_delta_m, dive_intent.outward_delta_m),
		float(dive_intent.maximum_cross_to_outward_ratio) - cross_to_outward_ratio,
		_band_margin(float(planned.dive_exit_apron_fraction), DIVE_EXIT_APRON_BAND),
		TERRAIN_PLACEMENT_TOLERANCE_M \
			- absf(float(planned.dive_exit_edge_m) \
				- float(planned.dive_exit_apron_fraction) * float(terrain.apron_width)),
		dive.minimum_agl_m - float(dive_intent.minimum_centerline_agl_m),
		minf(dive.minimum_outward_step_m, dive.minimum_height_down_step_m) + 0.05,
		_band_margin(dive_entry_edge_m,
			Vector2(shelf_edge_m + DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M.x,
				shelf_edge_m + DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M.y)),
		_band_margin(dive_exit_edge_m, DIVE_EXIT_APRON_BAND * float(terrain.apron_width)),
		TERRAIN_PLACEMENT_TOLERANCE_M - absf(dive_entry_edge_m - float(planned.dive_entry_edge_m)),
		TERRAIN_PLACEMENT_TOLERANCE_M - absf(dive_exit_edge_m - float(planned.dive_exit_edge_m)),
		TERRAIN_PLACEMENT_TOLERANCE_M \
			- absf((dive_entry_edge_m - dive_exit_edge_m) \
				- float(planned.native_dive_edge_span_m)),
		_band_margin(summit_agl_m, SUMMIT_AGL_BAND_M),
		_band_margin(dive_drop_m, scale.dive_drop_m),
	]:
		dive_margin = minf(dive_margin, term)
	var shelf_cross := _crossing_index(dive.signed_edge_m,
		shelf_edge_m)
	var face_cross := _crossing_index(dive.signed_edge_m, float(terrain.apron_width))
	if shelf_cross < 0 or face_cross <= shelf_cross:
		return _terrain_failure("outward-dive", "boundary_crossings",
			{"order": PackedStringArray(["shelf_edge", "face"])},
			{"shelf_index": shelf_cross, "face_index": face_cross})
	if dive_margin < -0.0001:
		return _terrain_failure("outward-dive", "native_monotonic_or_band", {},
			{"observation": dive, "margin": dive_margin})
	proofs["outward-dive"] = {"ok": true, "observation": dive,
		"crossings": {"shelf_edge": shelf_cross, "face": face_cross},
		"drop_m": dive_drop_m, "summit_agl_m": summit_agl_m,
		"entry_edge_m": dive_entry_edge_m, "exit_edge_m": dive_exit_edge_m,
		"minimum_margin": maxf(0.0, dive_margin)}

	var camel_bounds := _role_sample_bounds(role_spans, "camelback", trajectory)
	if camel_bounds.x < 0:
		return _terrain_failure("camelback", "role_spans", {}, {"missing": true})
	var camel_prominence_m := _prominence_m(trajectory.position_m, camel_bounds)
	var camel_margin := _band_margin(camel_prominence_m, scale.camel_prominence_m)
	if camel_margin < -0.0001:
		return _terrain_failure("camelback", "native_prominence",
			{"band_m": scale.camel_prominence_m}, {"value_m": camel_prominence_m})
	proofs["camelback"] = {"ok": true, "prominence_m": camel_prominence_m,
		"minimum_margin": maxf(0.0, camel_margin)}
	proofs["native-scale"] = {"ok": true, "terrain_relief_m": terrain.relief,
		"route_vertical_envelope_m": route_envelope_m,
		"minimum_margin": maxf(0.0, scale_margin)}

	var tunnel_bounds := _role_sample_bounds(role_spans, "tunnel-lsm3", trajectory)
	if tunnel_bounds.x < 0:
		return _terrain_failure("tunnel-lsm3", "role_spans", {}, {"missing": true})
	var tunnel := _terrain_path_observation(trajectory, terrain, frame,
		tunnel_bounds.x, tunnel_bounds.y)
	var apron_cross := _crossing_index(tunnel.signed_edge_m, 0.0)
	var tunnel_exit_edge_m := float(tunnel.signed_edge_m[-1])
	var exit_overshoot_margin_m := -tunnel_exit_edge_m - TUNNEL_EXIT_PLAIN_OVERSHOOT_M
	var planned_exit_margin_m := TERRAIN_PLACEMENT_TOLERANCE_M \
		- absf(tunnel_exit_edge_m - float(planned.tunnel_exit_edge_m))
	var planned_span_margin_m := TERRAIN_PLACEMENT_TOLERANCE_M \
		- absf((dive_exit_edge_m - tunnel_exit_edge_m) \
			- float(planned.native_tunnel_edge_span_m))
	var tunnel_drop_m: float = trajectory.position_m[tunnel_bounds.x].y \
		- trajectory.position_m[tunnel_bounds.y].y
	var tunnel_margin := exit_overshoot_margin_m
	for term in [tunnel.minimum_outward_step_m, tunnel.minimum_height_down_step_m,
			planned_exit_margin_m, planned_span_margin_m, tunnel_drop_m]:
		tunnel_margin = minf(tunnel_margin, term)
	if apron_cross < 0 or tunnel_margin < -0.0001:
		return _terrain_failure("tunnel-lsm3", "apron_edge",
			{"from_side": 1, "to_side": -1, "monotonic": ["outward", "height_down"]},
			{"crossing_index": apron_cross, "exit_signed_edge_m": tunnel_exit_edge_m,
				"drop_m": tunnel_drop_m, "margin": tunnel_margin,
				"exit_overshoot_margin_m": exit_overshoot_margin_m,
				"minimum_outward_step_m": tunnel.minimum_outward_step_m,
				"minimum_height_down_step_m": tunnel.minimum_height_down_step_m,
				"planned_exit_margin_m": planned_exit_margin_m,
				"planned_span_margin_m": planned_span_margin_m})
	proofs["tunnel-lsm3"] = {"ok": true, "crossing_index": apron_cross,
		"exit_signed_edge_m": tunnel_exit_edge_m, "drop_m": tunnel_drop_m,
		"minimum_margin": maxf(0.0, tunnel_margin)}
	var station_spine: Vector3 = trajectory.position_m[0] \
		- trajectory.rider_up[0] * LOWER_SPINE_SURFACE_OFFSET_M
	var summit_spine: Vector3 = trajectory.position_m[dive_bounds.x] \
		- trajectory.rider_up[dive_bounds.x] * LOWER_SPINE_SURFACE_OFFSET_M
	return {"ok": true, "proofs": proofs, "planning": {
		"dive_entry_edge_m": dive_entry_edge_m,
		"dive_exit_edge_m": dive_exit_edge_m,
		"tunnel_exit_edge_m": tunnel_exit_edge_m,
		"station_lower_spine_agl_m": station_spine.y \
			- Terrain.height(terrain, station_spine.x, station_spine.z),
		"summit_lower_spine_agl_m": summit_spine.y \
			- Terrain.height(terrain, summit_spine.x, summit_spine.z),
	}}


## The declared terrain intent of one role. Roles are looked up by id, never by slot: the plan's
## role order is drawn per seed inside the story grammar's cells.
static func _role_terrain_intent(plan: Dictionary, role_id: String) -> Dictionary:
	for role in plan.get("roles", []):
		if role is Dictionary and str(role.get("id", "")) == role_id \
				and role.get("terrain") is Dictionary:
			return role.terrain
	return {}


static func _terrain_path_observation(
	trajectory: Dictionary, terrain: Dictionary, frame: Dictionary, first: int, last: int
) -> Dictionary:
	var signed_edge := PackedFloat64Array()
	var minimum_agl := INF
	var maximum_agl := -INF
	var minimum_outward_step := INF
	var minimum_height_down_step := INF
	for index in range(first, last + 1):
		var position: Vector3 = trajectory.position_m[index]
		var edge := Terrain.edge_distance(terrain, position.x, position.z)
		var agl := position.y - Terrain.height(terrain, position.x, position.z)
		signed_edge.append(edge)
		minimum_agl = minf(minimum_agl, agl)
		maximum_agl = maxf(maximum_agl, agl)
		if index > first:
			minimum_outward_step = minf(minimum_outward_step,
				float(signed_edge[-2]) - edge)
			minimum_height_down_step = minf(minimum_height_down_step,
				trajectory.position_m[index - 1].y - position.y)
	var delta: Vector3 = trajectory.position_m[last] - trajectory.position_m[first]
	return {"signed_edge_m": signed_edge, "outward_delta_m": -delta.dot(frame.inward),
		"cross_delta_m": delta.dot(frame.along), "minimum_agl_m": minimum_agl,
		"maximum_agl_m": maximum_agl, "minimum_outward_step_m": minimum_outward_step,
		"minimum_height_down_step_m": minimum_height_down_step}


static func _role_sample_bounds(
	role_spans: Dictionary, role_id: String, trajectory: Dictionary
) -> Vector2i:
	var span_bounds: Variant = role_spans.get(role_id)
	if not span_bounds is Vector2i:
		return Vector2i(-1, -1)
	return Vector2i(trajectory.span_index.find(span_bounds.x),
		trajectory.span_index.rfind(span_bounds.y))


static func _crossing_index(values: PackedFloat64Array, boundary: float) -> int:
	for index in range(1, values.size()):
		if values[index - 1] > boundary and values[index] <= boundary:
			return index
	return -1


static func _vertical_envelope_m(positions: PackedVector3Array) -> float:
	var minimum_y := INF
	var maximum_y := -INF
	for position in positions:
		minimum_y = minf(minimum_y, position.y)
		maximum_y = maxf(maximum_y, position.y)
	return maximum_y - minimum_y


static func _drop_m(positions: PackedVector3Array, bounds: Vector2i) -> float:
	var minimum_y: float = positions[bounds.x].y
	for index in range(bounds.x + 1, bounds.y + 1):
		minimum_y = minf(minimum_y, positions[index].y)
	return positions[bounds.x].y - minimum_y


static func _prominence_m(positions: PackedVector3Array, bounds: Vector2i) -> float:
	var maximum_y := -INF
	for index in range(bounds.x, bounds.y + 1):
		maximum_y = maxf(maximum_y, positions[index].y)
	return maximum_y - maxf(positions[bounds.x].y, positions[bounds.y].y)


static func _band_margin(value: float, band: Vector2) -> float:
	return minf(value - band.x, band.y - value)


static func _terrain_failure(
	role_id: String, measurement: String, bounds: Dictionary, observed: Dictionary
) -> Dictionary:
	return {"ok": false, "failure": {"stage": &"contract", "role_id": role_id,
		"reason": &"terrain_intent_miss", "bounds": bounds, "observed": observed,
		"margins": {}, "evaluation_count": 0}}


static func _angle_between(first: Vector3, second: Vector3) -> float:
	var a := first.normalized()
	var b := second.normalized()
	return atan2(a.cross(b).length(), clampf(a.dot(b), -1.0, 1.0))


static func _valid_slug(value: String) -> bool:
	if value.is_empty() or value.begins_with("-") or value.begins_with("_") \
			or value.ends_with("-") or value.ends_with("_"):
		return false
	for character in value:
		if not "abcdefghijklmnopqrstuvwxyz0123456789-_".contains(character):
			return false
	return not value.contains("--") and not value.contains("__") \
		and not value.contains("-_") and not value.contains("_-")


static func _window_id(
	story_slot_id: String, role: String, occurrence: int, diagnostic_kind: String
) -> String:
	var suffix := "" if diagnostic_kind.is_empty() else "-%s" % diagnostic_kind
	return "%s/%s/%02d%s" % [story_slot_id, role, occurrence, suffix]


static func _validate_span_range(
	span_range: Variant, span_count: int, label: String, errors: PackedStringArray
) -> void:
	if not span_range is Vector2i:
		errors.append("%s span range is not Vector2i" % label)
		return
	if span_range.x < 0 or span_range.y < span_range.x or span_range.y >= span_count:
		errors.append("%s span range %s is invalid" % [label, str(span_range)])


static func _gesture_windows(gestures: Array, trajectory: Dictionary) -> Array:
	var windows := []
	for gesture in gestures:
		var window := _sample_window(gesture, trajectory)
		window["peak_profile_normal_onset_estimate_gps"] = float(
			gesture.peak_profile_normal_onset_estimate_gps)
		var roles := []
		for role in gesture.role_windows:
			roles.append(_sample_window(role, trajectory))
		window["role_windows"] = roles
		windows.append(window)
	return windows


static func _sample_window(record: Dictionary, trajectory: Dictionary) -> Dictionary:
	var first: int = trajectory.span_index.find(int(record.first_span))
	var last: int = trajectory.span_index.rfind(int(record.last_span))
	var window := {
		"display_name": str(record.get("display_name", "")),
		"diagnostic_kind": str(record.get("diagnostic_kind", "")),
		"occurrence": int(record.occurrence),
		"window_id": str(record.window_id),
		"first": first,
		"last": last,
		"start_time_s": float(trajectory.time_s[first]),
		"end_time_s": float(trajectory.time_s[last]),
		"start_distance_m": float(trajectory.distance_m[first]),
		"end_distance_m": float(trajectory.distance_m[last]),
		"first_span": int(record.first_span),
		"last_span": int(record.last_span),
	}
	if record.has("story_slot_id"):
		window["story_slot_id"] = str(record.story_slot_id)
	else:
		window["id"] = str(record.id)
	return window


static func _tunnel_ranges(span_ranges: Array, trajectory: Dictionary) -> Array:
	var ranges := []
	for span_range: Vector2i in span_ranges:
		var first: int = trajectory.span_index.find(span_range.x)
		var last: int = trajectory.span_index.rfind(span_range.y)
		ranges.append(Vector2i(first, last))
	return ranges


static func _degrees(radians: PackedFloat64Array) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	output.resize(radians.size())
	for index in radians.size():
		output[index] = rad_to_deg(radians[index])
	return output


static func _float32(values: PackedFloat64Array) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	output.resize(values.size())
	for index in values.size():
		output[index] = values[index]
	return output


static func _bank_degrees(tangent: Vector3, up: Vector3, previous: float) -> float:
	if absf(tangent.y) >= 0.999:
		return previous
	var level_up := (Vector3.UP - tangent * tangent.y).normalized()
	var right := tangent.cross(up).normalized()
	return rad_to_deg(atan2(-right.dot(level_up), up.dot(level_up)))


static func _bounds(positions: PackedVector3Array) -> AABB:
	var result := AABB(positions[0], Vector3.ZERO)
	for index in range(1, positions.size()):
		result = result.expand(positions[index])
	return result
