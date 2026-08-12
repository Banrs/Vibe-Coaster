class_name RouteContract
extends RefCounted

## The sole conversion from an accepted motion trajectory to the public packed route.

const GENERATOR_VERSION := "time-domain-v1"
const ROW_OFFSETS := [0.0, 2.15, 4.30, 6.45, 8.60, 10.75, 12.90]

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
	compiled: Dictionary,
	trajectory: Dictionary
) -> Dictionary:
	var errors := _validate(terrain, initial_state, compiled, trajectory)
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
		"generation_stats": compiled.generation_stats.duplicate(true),
	}


static func _validate(
	terrain: Dictionary,
	initial_state: Dictionary,
	compiled: Dictionary,
	trajectory: Dictionary
) -> PackedStringArray:
	var errors := PackedStringArray()
	if terrain.is_empty():
		errors.append("terrain is empty")
	for key in ["position_m", "tangent", "rider_up", "speed_mps"]:
		if not initial_state.has(key):
			errors.append("initial state is missing %s" % key)
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
	if count >= 2 and (
		trajectory.position_m[0] != initial_state.position_m
		or trajectory.tangent[0] != initial_state.tangent
		or trajectory.rider_up[0] != initial_state.rider_up
		or trajectory.speed_mps[0] != initial_state.speed_mps
	):
		errors.append("trajectory does not begin at the declared initial state")
	var next_gesture_span := 0
	var window_ids := {}
	for gesture in compiled.gesture_spans:
		_validate_window_record(gesture, span_count, "gesture", "", window_ids, errors)
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
	return errors


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
		var roles := []
		for role in gesture.role_windows:
			roles.append(_sample_window(role, trajectory))
		window["role_windows"] = roles
		windows.append(window)
	return windows


static func _sample_window(record: Dictionary, trajectory: Dictionary) -> Dictionary:
	var first := trajectory.span_index.find(int(record.first_span))
	var last := trajectory.span_index.rfind(int(record.last_span))
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
		var first := trajectory.span_index.find(span_range.x)
		var last := trajectory.span_index.rfind(span_range.y)
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
