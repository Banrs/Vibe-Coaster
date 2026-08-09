class_name RideFidelity
extends RefCounted

const Verify := preload("res://verify.gd")
const Terrain := preload("res://terrain.gd")

const CONFIDENCE := ["high", "medium", "low"]
const DIMENSIONS := ["loads", "geometry", "pacing", "terrain", "flow"]
const METRICS := [
	"normal_peak_positive", "normal_peak_negative",
	"normal_held_positive", "normal_held_negative",
	"lateral_peak_absolute", "longitudinal_held_positive", "longitudinal_peak_positive",
	"longitudinal_peak_negative",
	"onset_peak", "roll_rate_peak",
	"length", "height", "width", "min_pitch", "max_pitch", "max_bank",
	"apex_radius", "valley_radius", "entry_speed", "exit_speed",
	"duration", "speed_loss", "average_speed", "dead_zone_share",
	"speed_share_100", "speed_share_200", "flat_seconds", "beat_count",
	"agl_min", "agl_median", "agl_max", "terrain_hugging_share",
	"transition_force_swing", "transition_seconds", "bank_handoff",
	"flat_dwell", "same_kind_adjacency",
]
const HOLD_SECONDS := [0.2, 0.5, 0.8, 1.0, 1.1, 1.4, 2.0, 2.4, 2.78, 3.0, 4.0, 6.8, 12.0]
const TERRAIN_HUGGING_AGL := 20.0


## Largest value a window sustains for `seconds`, signed by `polarity`. This is the same
## held-curve convention used by the load verifier and the smoke fidelity bands.
static func held(values: PackedFloat32Array, polarity: float, seconds: float) -> float:
	var window := roundi(seconds * Verify.SAMPLE_HZ) + 1
	if window >= values.size():
		return -INF
	return Verify._held_curve(values, polarity)[window] * polarity


## One filtered band per flown beat. Consecutive FVD sections that carry the same element
## Dictionary are one composite beat; grades and the closure remain named beats of their own.
static func element_bands(route: Dictionary, row_offset: float = 0.0) -> Array:
	return _bands_for_row(
		route, _beat_definitions(route), row_offset, _row_series(route, row_offset), false
	)


## JSON-safe measurements for one generated route. The route is only read; all row force series
## and shifted beat windows are derived locally and discarded after this call.
static func measure_route(route: Dictionary, row_offsets: Array) -> Dictionary:
	var definitions := _beat_definitions(route)
	var bands_by_row := []
	for offset_value in row_offsets:
		var offset := float(offset_value)
		var by_id := {}
		for band in _bands_for_row(route, definitions, offset, _row_series(route, offset), true):
			by_id[band.beat_id] = band
		bands_by_row.append(by_id)

	var measured_beats := []
	for beat_index in definitions.size():
		var definition: Dictionary = definitions[beat_index]
		var rows := []
		for row_index in row_offsets.size():
			var row_bands: Dictionary = bands_by_row[row_index]
			if not row_bands.has(definition.beat_id):
				continue
			var band: Dictionary = row_bands[definition.beat_id]
			rows.append({
				"row_id": "row-%02d" % (row_index + 1),
				"position": _row_position(row_index, row_offsets.size()),
				"offset": float(row_offsets[row_index]),
				"window_start_distance": band.window_start_distance,
				"window_end_distance": band.window_end_distance,
				"window_seconds": band.seconds,
				"loads": _load_metrics(band),
			})
		var pacing := _pacing_metrics(route, definition.first, definition.last)
		measured_beats.append({
			"beat_id": definition.beat_id,
			"phase": definition.phase,
			"ordinal": definition.ordinal,
			"kind": definition.kind,
			"name": definition.name,
			"start_distance": float(route.distances[definition.first]),
			"end_distance": float(route.distances[definition.last]),
			"geometry": _geometry_metrics(route, definition.first, definition.last),
			"pacing": pacing,
			"terrain": _terrain_metrics(route, definition.first, definition.last),
			"flow": _flow_metrics(route, definitions, beat_index, pacing),
			"rows": rows,
		})

	var route_geometry := _geometry_metrics(route, 0, route.positions.size() - 1)
	var route_pacing := _pacing_metrics(route, 0, route.positions.size() - 1)
	route_pacing["beat_count"] = measured_beats.size()
	return {
		"schema_version": 1,
		"seed": int(route.get("seed", 0)),
		"length": float(route.get("length", route.distances[-1])),
		"duration": float(route.get("duration", route.times[-1])),
		"dimensions": {
			"loads": _aggregate_loads(measured_beats),
			"geometry": route_geometry,
			"pacing": route_pacing,
			"terrain": _terrain_metrics(route, 0, route.positions.size() - 1),
			"flow": _aggregate_flow(measured_beats),
		},
		"beats": measured_beats,
	}


static func _beat_definitions(route: Dictionary) -> Array:
	var beats := []
	var ordinals := {}
	for section in route.sections:
		var element: Dictionary = section.get("element", {})
		var kind: String = element.get("kind", "") if section.kind == "FVD" else section.name
		if kind == "":
			continue
		if (
			not beats.is_empty()
			and section.kind == "FVD"
			and beats[-1].kind == kind
			and is_same(beats[-1].element, element)
		):
			beats[-1].last = section.end_index
			continue
		var phase: String = section.get("phase", "unassigned")
		var ordinal: int = ordinals.get(phase, 0)
		ordinals[phase] = ordinal + 1
		beats.append({
			"kind": kind,
			"name": str(section.get("name", kind)),
			"element": element,
			"phase": phase,
			"ordinal": ordinal,
			"beat_id": "%s/%02d/%s" % [_slug(phase), ordinal, _slug(kind)],
			"first": section.start_index,
			"last": section.end_index,
		})
	return beats


static func _row_series(route: Dictionary, row_offset: float) -> Dictionary:
	var normal := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	var longitudinal := PackedFloat32Array()
	var roll := PackedFloat32Array()
	if is_zero_approx(row_offset):
		normal = route.normal_g
		lateral = route.lateral_g
		longitudinal = route.longitudinal_g
		if route.has("roll_rates"):
			roll = route.roll_rates
		else:
			roll.resize(route.times.size())
			roll.fill(0.0)
	else:
		var count: int = route.times.size()
		normal.resize(count)
		lateral.resize(count)
		longitudinal.resize(count)
		roll.resize(count)
		for i in count:
			var forces: Dictionary = Verify.row_forces_at(
				route, route.distances[i], route.speeds[i], row_offset
			)
			normal[i] = forces.normal
			lateral[i] = forces.lateral
			longitudinal[i] = forces.longitudinal
			roll[i] = forces.roll_rate
	return {
		"normal": Verify.filter(Verify.resample(route.times, normal)),
		"lateral": Verify.filter(Verify.resample(route.times, lateral)),
		"longitudinal": Verify.filter(Verify.resample(route.times, longitudinal)),
		"roll": Verify.filter(Verify.resample(route.times, roll)),
	}


static func _bands_for_row(
	route: Dictionary, beats: Array, row_offset: float, series: Dictionary, include_short: bool
) -> Array:
	var normal: PackedFloat32Array = series.normal
	var lateral: PackedFloat32Array = series.lateral
	var longitudinal: PackedFloat32Array = series.longitudinal
	var roll: PackedFloat32Array = series.roll
	var bands := []
	var route_length := float(route.get("length", route.distances[-1]))
	for beat in beats:
		var start_distance: float = route.distances[beat.first]
		var end_distance: float = route.distances[beat.last]
		var window_start := minf(start_distance + row_offset, route_length)
		var window_end := minf(end_distance + row_offset, route_length)
		var low_time: float = _time_at_distance(route, window_start)
		var high_time: float = _time_at_distance(route, window_end)
		var low: int = mini(floori(low_time * Verify.SAMPLE_HZ), normal.size() - 1)
		var high: int = mini(floori(high_time * Verify.SAMPLE_HZ), normal.size() - 1)
		if high - low < 4:
			if not include_short:
				continue
			high = mini(maxi(low + 1, high), normal.size() - 1)
		if high <= low:
			continue
		bands.append({
			"kind": beat.kind,
			"element": beat.element,
			"phase": beat.phase,
			"beat_id": beat.beat_id,
			"first": beat.first,
			"last": beat.last,
			"start_distance": route.distances[beat.first],
			"end_distance": route.distances[beat.last],
			"row_offset": row_offset,
			"window_start_distance": window_start,
			"window_end_distance": window_end,
			"seconds": high_time - low_time,
			"normal": normal.slice(low, high + 1),
			"lateral": lateral.slice(low, high + 1),
			"longitudinal": longitudinal.slice(low, high + 1),
			"roll": roll.slice(low, high + 1),
		})
	return bands


static func _time_at_distance(route: Dictionary, distance: float) -> float:
	if distance <= route.distances[0]:
		return route.times[0]
	if distance >= route.distances[-1]:
		return route.times[-1]
	var low := 0
	var high: int = route.distances.size() - 1
	while low + 1 < high:
		var middle := floori((low + high) * 0.5)
		if route.distances[middle] <= distance:
			low = middle
		else:
			high = middle
	return lerpf(
		route.times[low],
		route.times[high],
		inverse_lerp(route.distances[low], route.distances[high], distance)
	)


static func _row_position(index: int, count: int) -> String:
	if index == 0:
		return "front"
	if index == count - 1:
		return "rear"
	return "intermediate"


static func _load_metrics(band: Dictionary) -> Dictionary:
	var normal: PackedFloat32Array = band.normal
	var lateral: PackedFloat32Array = band.lateral
	var longitudinal: PackedFloat32Array = band.longitudinal
	var roll: PackedFloat32Array = band.roll
	return {
		"normal_peak_positive": _maximum(normal),
		"normal_peak_negative": _minimum(normal),
		"normal_held_positive": _hold_values(normal, 1.0),
		"normal_held_negative": _hold_values(normal, -1.0),
		"lateral_peak_absolute": _absolute_peak(lateral),
		"longitudinal_held_positive": _hold_values(longitudinal, 1.0),
		"longitudinal_peak_positive": _maximum(longitudinal),
		"longitudinal_peak_negative": _minimum(longitudinal),
		"onset_peak": maxf(
			Verify.peak_onset(normal),
			maxf(Verify.peak_onset(lateral), Verify.peak_onset(longitudinal))
		),
		"roll_rate_peak": _absolute_peak(roll),
	}


static func _hold_values(values: PackedFloat32Array, polarity: float) -> Dictionary:
	var output := {}
	for seconds in HOLD_SECONDS:
		if roundi(seconds * Verify.SAMPLE_HZ) + 1 < values.size():
			output[_hold_key(seconds)] = held(values, polarity, seconds)
	return output


static func _hold_key(seconds: float) -> String:
	return "%.2f" % seconds


static func _geometry_metrics(route: Dictionary, first: int, last: int) -> Dictionary:
	var minimum_height := INF
	var maximum_height := -INF
	var minimum_pitch := INF
	var maximum_pitch := -INF
	var maximum_bank := 0.0
	var apex := first
	var valley := first
	for i in range(first, last + 1):
		var height: float = route.positions[i].y
		var pitch := _pitch_degrees(route.tangents[i])
		if height > maximum_height:
			maximum_height = height
			apex = i
		if height < minimum_height:
			minimum_height = height
			valley = i
		minimum_pitch = minf(minimum_pitch, pitch)
		maximum_pitch = maxf(maximum_pitch, pitch)
		maximum_bank = maxf(maximum_bank, absf(route.banks[i]))
	var plan_delta := Vector2(
		route.positions[last].x - route.positions[first].x,
		route.positions[last].z - route.positions[first].z
	)
	return {
		"length": float(route.distances[last] - route.distances[first]),
		"height": maximum_height - minimum_height,
		"width": plan_delta.length(),
		"min_pitch": minimum_pitch,
		"max_pitch": maximum_pitch,
		"max_bank": maximum_bank,
		"apex_radius": 1.0 / maxf(route.curvatures[apex].length(), 0.0001),
		"valley_radius": 1.0 / maxf(route.curvatures[valley].length(), 0.0001),
		"entry_speed": float(route.speeds[first]),
		"exit_speed": float(route.speeds[last]),
	}


static func _pacing_metrics(route: Dictionary, first: int, last: int) -> Dictionary:
	var duration: float = route.times[last] - route.times[first]
	var length: float = route.distances[last] - route.distances[first]
	var dead_count := 0
	var speed_100_count := 0
	var speed_200_count := 0
	var flat_seconds := 0.0
	var count := last - first + 1
	for i in range(first, last + 1):
		if (
			route.normal_g[i] >= 0.75
			and route.normal_g[i] <= 1.25
			and absf(route.lateral_g[i]) <= 0.25
			and absf(route.longitudinal_g[i]) <= 0.25
		):
			dead_count += 1
		if route.speeds[i] >= 100.0 / 3.6:
			speed_100_count += 1
		if route.speeds[i] >= 200.0 / 3.6:
			speed_200_count += 1
		if i < last and absf(_pitch_degrees(route.tangents[i])) <= 5.0 and absf(route.banks[i]) <= 5.0:
			flat_seconds += route.times[i + 1] - route.times[i]
	return {
		"duration": duration,
		"speed_loss": float(route.speeds[first] - route.speeds[last]),
		"average_speed": length / maxf(duration, 0.0001),
		"dead_zone_share": float(dead_count) / maxi(count, 1),
		"speed_share_100": float(speed_100_count) / maxi(count, 1),
		"speed_share_200": float(speed_200_count) / maxi(count, 1),
		"flat_seconds": flat_seconds,
	}


static func _terrain_metrics(route: Dictionary, first: int, last: int) -> Dictionary:
	var values := []
	var hugging := 0
	var has_terrain: bool = route.has("terrain") and route.terrain is Dictionary
	for i in range(first, last + 1):
		var position: Vector3 = route.positions[i]
		var ground := 0.0
		if has_terrain:
			ground = Terrain.height(route.terrain, position.x, position.z)
		var agl := position.y - ground
		values.append(agl)
		if agl <= TERRAIN_HUGGING_AGL:
			hugging += 1
	values.sort()
	return {
		"agl_min": float(values[0]),
		"agl_median": _median(values),
		"agl_max": float(values[-1]),
		"terrain_hugging_share": float(hugging) / maxi(values.size(), 1),
	}


static func _flow_metrics(
	route: Dictionary, definitions: Array, beat_index: int, pacing: Dictionary
) -> Dictionary:
	if beat_index + 1 >= definitions.size():
		return {
			"transition_force_swing": 0.0,
			"transition_seconds": 0.0,
			"bank_handoff": 0.0,
			"flat_dwell": pacing.flat_seconds,
			"same_kind_adjacency": 0.0,
		}
	var beat: Dictionary = definitions[beat_index]
	var next: Dictionary = definitions[beat_index + 1]
	var a: int = beat.last
	var b: int = next.first
	var swing := maxf(
		absf(route.normal_g[b] - route.normal_g[a]),
		maxf(
			absf(route.lateral_g[b] - route.lateral_g[a]),
			absf(route.longitudinal_g[b] - route.longitudinal_g[a])
		)
	)
	return {
		"transition_force_swing": swing,
		"transition_seconds": maxf(0.0, route.times[b] - route.times[a]),
		"bank_handoff": absf(route.banks[b] - route.banks[a]),
		"flat_dwell": pacing.flat_seconds,
		"same_kind_adjacency": 1.0 if beat.kind == next.kind else 0.0,
	}


static func _aggregate_loads(beats: Array) -> Dictionary:
	var output := {
		"normal_peak_positive": -INF,
		"normal_peak_negative": INF,
		"lateral_peak_absolute": 0.0,
		"longitudinal_peak_positive": -INF,
		"longitudinal_peak_negative": INF,
		"onset_peak": 0.0,
		"roll_rate_peak": 0.0,
	}
	for beat in beats:
		for row in beat.rows:
			var loads: Dictionary = row.loads
			output.normal_peak_positive = maxf(output.normal_peak_positive, loads.normal_peak_positive)
			output.normal_peak_negative = minf(output.normal_peak_negative, loads.normal_peak_negative)
			output.lateral_peak_absolute = maxf(output.lateral_peak_absolute, loads.lateral_peak_absolute)
			output.longitudinal_peak_positive = maxf(output.longitudinal_peak_positive, loads.longitudinal_peak_positive)
			output.longitudinal_peak_negative = minf(output.longitudinal_peak_negative, loads.longitudinal_peak_negative)
			output.onset_peak = maxf(output.onset_peak, loads.onset_peak)
			output.roll_rate_peak = maxf(output.roll_rate_peak, loads.roll_rate_peak)
	if is_inf(output.normal_peak_positive):
		output.normal_peak_positive = 0.0
		output.normal_peak_negative = 0.0
		output.longitudinal_peak_positive = 0.0
		output.longitudinal_peak_negative = 0.0
	return output


static func _aggregate_flow(beats: Array) -> Dictionary:
	var output := {
		"transition_force_swing": 0.0,
		"transition_seconds": 0.0,
		"bank_handoff": 0.0,
		"flat_dwell": 0.0,
		"same_kind_adjacency": 0.0,
	}
	for beat in beats:
		for metric in output:
			output[metric] = maxf(output[metric], beat.flow[metric])
	return output


static func _maximum(values: PackedFloat32Array) -> float:
	var result := -INF
	for value in values:
		result = maxf(result, value)
	return result


static func _minimum(values: PackedFloat32Array) -> float:
	var result := INF
	for value in values:
		result = minf(result, value)
	return result


static func _absolute_peak(values: PackedFloat32Array) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, absf(value))
	return result


static func _median(sorted_values: Array) -> float:
	var count := sorted_values.size()
	if count % 2 == 1:
		return float(sorted_values[floori(count * 0.5)])
	var middle := floori(count * 0.5)
	return (float(sorted_values[middle - 1]) + float(sorted_values[middle])) * 0.5


static func _pitch_degrees(tangent: Vector3) -> float:
	return rad_to_deg(asin(clampf(tangent.y, -1.0, 1.0)))


static func validate_catalog(catalog: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if catalog.get("schema_version") != 1:
		errors.append("catalog schema_version must be 1")
	if str(catalog.get("catalog_version", "")) == "":
		errors.append("catalog_version is missing")
	var sources: Variant = catalog.get("sources")
	if not sources is Dictionary:
		errors.append("catalog sources must be a Dictionary")
		return errors
	for source_id in sources:
		var source: Variant = sources[source_id]
		if not source is Dictionary:
			errors.append("source '%s' must be a Dictionary" % source_id)
			continue
		for key in ["document", "section", "confidence", "caveats"]:
			if not source.has(key):
				errors.append("source '%s' is missing %s" % [source_id, key])
		if source.get("confidence", "") not in CONFIDENCE:
			errors.append("source '%s' has invalid confidence" % source_id)

	var targets: Variant = catalog.get("targets")
	if not targets is Array:
		errors.append("catalog targets must be an Array")
		return errors
	var seen := {}
	for index in targets.size():
		var target: Variant = targets[index]
		if not target is Dictionary:
			errors.append("target %d must be a Dictionary" % index)
			continue
		var target_id: String = str(target.get("id", ""))
		if target_id == "":
			errors.append("target %d is missing id" % index)
		elif seen.has(target_id):
			errors.append("duplicate target id '%s'" % target_id)
		else:
			seen[target_id] = true
		for key in [
			"source_ids", "confidence", "caveats", "selector", "dimension", "metric",
			"recording_row", "raw_range", "transform", "hold_seconds", "target_range", "issues",
		]:
			if not target.has(key):
				errors.append("target '%s' is missing %s" % [target_id, key])
		if target.get("confidence", "") not in CONFIDENCE:
			errors.append("target '%s' has invalid confidence" % target_id)
		if target.get("dimension", "") not in DIMENSIONS:
			errors.append("target '%s' has unsupported dimension" % target_id)
		if target.get("metric", "") not in METRICS:
			errors.append("target '%s' has unsupported metric '%s'" % [target_id, target.get("metric", "")])
		if not target.get("selector") is Dictionary or target.get("selector").is_empty():
			errors.append("target '%s' has invalid selector" % target_id)
		if not target.get("caveats") is Array:
			errors.append("target '%s' caveats must be an Array" % target_id)
		if str(target.get("recording_row", "")) == "":
			errors.append("target '%s' is missing recording_row" % target_id)
		var transform: Variant = target.get("transform")
		if not transform is Dictionary or transform.get("kind", "") not in ["identity", "scale"]:
			errors.append("target '%s' has invalid transform" % target_id)
		elif typeof(transform.get("factor")) not in [TYPE_INT, TYPE_FLOAT] or float(transform.factor) <= 0.0:
			errors.append("target '%s' has invalid transform factor" % target_id)
		var hold_seconds: Variant = target.get("hold_seconds")
		if hold_seconds != null and (
			typeof(hold_seconds) not in [TYPE_INT, TYPE_FLOAT] or float(hold_seconds) <= 0.0
		):
			errors.append("target '%s' has invalid hold_seconds" % target_id)
		_validate_range(target_id, "raw_range", target.get("raw_range"), errors)
		_validate_range(target_id, "target_range", target.get("target_range"), errors)
		var source_ids: Variant = target.get("source_ids")
		if not source_ids is Array or source_ids.is_empty():
			errors.append("target '%s' has no source_ids" % target_id)
		else:
			for source_id in source_ids:
				if not sources.has(source_id):
					errors.append("target '%s' references unknown source '%s'" % [target_id, source_id])
		_validate_issues("target", target_id, target.get("issues"), errors)
	_validate_auxiliary_records(catalog, "review_prompts", sources, errors)
	_validate_auxiliary_records(catalog, "evidence_gaps", sources, errors)
	return errors


static func _validate_auxiliary_records(
	catalog: Dictionary, key: String, sources: Dictionary, errors: PackedStringArray
) -> void:
	var records: Variant = catalog.get(key)
	if not records is Array:
		errors.append("catalog %s must be an Array" % key)
		return
	var seen := {}
	for index in records.size():
		var record: Variant = records[index]
		if not record is Dictionary:
			errors.append("%s record %d must be a Dictionary" % [key, index])
			continue
		var record_id := str(record.get("id", ""))
		if record_id == "":
			errors.append("%s record %d is missing id" % [key, index])
		elif seen.has(record_id):
			errors.append("duplicate %s id '%s'" % [key, record_id])
		else:
			seen[record_id] = true
		if str(record.get("prompt", record.get("description", ""))) == "":
			errors.append("%s '%s' is missing text" % [key, record_id])
		_validate_issues(key, record_id, record.get("issues"), errors)
		var source_ids: Variant = record.get("source_ids", [])
		if not source_ids is Array:
			errors.append("%s '%s' source_ids must be an Array" % [key, record_id])
		else:
			for source_id in source_ids:
				if not sources.has(source_id):
					errors.append("%s '%s' references unknown source '%s'" % [key, record_id, source_id])


static func _validate_issues(
	record_kind: String, record_id: String, issues: Variant, errors: PackedStringArray
) -> void:
	if not issues is Array or issues.is_empty():
		errors.append("%s '%s' has no issue mappings" % [record_kind, record_id])
		return
	for issue in issues:
		if typeof(issue) != TYPE_INT or issue < 1 or issue > 16:
			errors.append("%s '%s' has invalid issue '%s'" % [record_kind, record_id, issue])


static func _validate_range(
	target_id: String, key: String, value: Variant, errors: PackedStringArray
) -> void:
	if not value is Array or value.size() != 2:
		errors.append("target '%s' has invalid %s" % [target_id, key])
		return
	if typeof(value[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(value[1]) not in [TYPE_INT, TYPE_FLOAT]:
		errors.append("target '%s' has invalid %s" % [target_id, key])
		return
	if float(value[0]) > float(value[1]):
		errors.append("target '%s' has invalid %s ordering" % [target_id, key])


static func _slug(value: String) -> String:
	var output := value.strip_edges().to_lower().replace("_", "-").replace(" ", "-")
	while output.contains("--"):
		output = output.replace("--", "-")
	return output if output != "" else "unassigned"
