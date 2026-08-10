class_name RideFidelity
extends RefCounted

const Verify := preload("res://verify.gd")
const Terrain := preload("res://terrain.gd")

const CONFIDENCE := ["high", "medium", "low"]
const DIMENSIONS := ["loads", "geometry", "pacing", "terrain", "flow"]
const METRICS := [
	"normal_peak_positive", "normal_peak_negative",
	"normal_held_positive", "normal_held_negative",
	"lateral_peak_absolute", "longitudinal_held_positive",
	"longitudinal_peak_positive", "longitudinal_peak_negative",
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


const EVIDENCE_STATES := ["review_pending", "observation_only", "corroborative", "executable"]
const FORCE_AXES := ["normal_g", "lateral_g", "longitudinal_g"]
const STATE_CEILINGS := {
	"review_pending": ["review_pending"],
	"observation_only": ["review_pending", "observation_only"],
	"corroborative": ["review_pending", "observation_only", "corroborative"],
	"executable": EVIDENCE_STATES,
}
const APPROVED_TRANSFORMS := {
	"fictional.gz-positive@1": ["normal_g", "positive", 1.3333333333, "target_force_g = observed_force_g * 1.3333333333", "explicit user decision 2026-08-09"],
	"fictional.gz-negative@1": ["normal_g", "negative", 1.5, "target_force_g = observed_force_g * 1.5", "explicit user decision 2026-08-09"],
	"fictional.gy-positive@1": ["lateral_g", "positive", 1.5666666667, "target_force_g = observed_force_g * 1.5666666667", "explicit user decision 2026-08-09"],
	"fictional.gy-negative@1": ["lateral_g", "negative", 1.5666666667, "target_force_g = observed_force_g * 1.5666666667", "explicit user decision 2026-08-09"],
	"fictional.gx-negative@1": ["longitudinal_g", "negative", 1.7142857143, "target_force_g = observed_force_g * 1.7142857143", "explicit user decision 2026-08-09"],
}
const SOURCE_FIELDS := [
	"initial_state", "state", "permitted_contributions", "permitted_axes", "promotion_prerequisites",
	"acquisition", "url", "recording_id", "video_id", "retrieved_on", "retrieval_context",
	"artifact_path", "artifact_sha256", "diagnostic_path", "diagnostic_sha256",
	"metadata_artifact_path", "metadata_artifact_sha256", "metadata_diagnostic_path",
	"metadata_diagnostic_sha256", "review_path", "review_sha256", "fallback_citations", "row_seat", "device",
	"sample_rate_hz", "axis_mapping", "reliability", "processing", "caveats", "windows",
]
const OBSERVATION_FIELDS := [
	"id", "state", "source_id", "source_window_id", "source_axis", "mapped_axis", "row_seat",
	"duration_s", "metric", "hold_seconds", "raw_range", "transform_id", "confidence",
	"confidence_rationale", "corroborating_observation_ids", "semantic_selector_id", "alignment",
]
const TARGET_FIELDS := [
	"id", "observation_id", "semantic_selector_id", "dimension", "metric", "hold_seconds",
	"raw_range", "target_range", "issues",
]


static func validate_catalog(catalog: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if catalog.get("schema_version") != 2:
		errors.append("catalog schema version 2 is required")
	if str(catalog.get("catalog_version", "")) == "":
		errors.append("catalog_version is missing")
	var selectors := _dictionary_collection(catalog, "selectors", errors)
	var sources := _dictionary_collection(catalog, "sources", errors)
	var transforms := _dictionary_collection(catalog, "transforms", errors)
	var observations := _array_collection(catalog, "observations", errors)
	var targets := _array_collection(catalog, "targets", errors)
	var review_prompts := _array_collection(catalog, "review_prompts", errors)
	var evidence_gaps := _array_collection(catalog, "evidence_gaps", errors)
	var seen_ids := {}
	_validate_selectors(selectors, seen_ids, errors)
	_validate_sources(sources, seen_ids, errors)
	_validate_transforms(transforms, seen_ids, errors)
	var observation_by_id := _validate_observations(
		observations, sources, selectors, transforms, seen_ids, errors
	)
	_validate_targets(targets, observation_by_id, selectors, transforms, seen_ids, errors)
	_validate_auxiliary_records(review_prompts, "review_prompts", sources, seen_ids, errors)
	_validate_auxiliary_records(evidence_gaps, "evidence_gaps", sources, seen_ids, errors)
	return errors


static func validate_catalog_artifacts(catalog: Dictionary) -> PackedStringArray:
	var errors := validate_catalog(catalog)
	if not errors.is_empty():
		return errors
	for source_id in catalog.sources:
		var source: Dictionary = catalog.sources[source_id]
		var pairs := []
		match str(source.get("acquisition", "")):
			"raw": pairs.append(["artifact", source.artifact_path, source.artifact_sha256])
			"raw_fetch_unavailable": pairs.append(["diagnostic", source.diagnostic_path, source.diagnostic_sha256])
		if source.has("metadata_artifact_path"):
			pairs.append(["metadata artifact", source.metadata_artifact_path, source.metadata_artifact_sha256])
		elif source.has("metadata_diagnostic_path"):
			pairs.append(["metadata diagnostic", source.metadata_diagnostic_path, source.metadata_diagnostic_sha256])
		pairs.append(["review", source.review_path, source.review_sha256])
		for pair in pairs:
			_validate_artifact(source_id, pair[0], pair[1], pair[2], errors)
	return errors


static func _dictionary_collection(
	catalog: Dictionary, key: String, errors: PackedStringArray
) -> Dictionary:
	var value: Variant = catalog.get(key)
	if value is Dictionary:
		return value
	errors.append("catalog %s must be a Dictionary" % key)
	return {}


static func _array_collection(catalog: Dictionary, key: String, errors: PackedStringArray) -> Array:
	var value: Variant = catalog.get(key)
	if value is Array:
		return value
	errors.append("catalog %s must be an Array" % key)
	return []


static func _validate_selectors(
	selectors: Dictionary, seen_ids: Dictionary, errors: PackedStringArray
) -> void:
	for selector_id in selectors:
		_claim_id(str(selector_id), "selector", seen_ids, errors)
		var selector: Variant = selectors[selector_id]
		if not selector is Dictionary:
			errors.append("selector '%s' must be a Dictionary" % selector_id)
			continue
		_require_exact_keys(selector, ["legacy_anchor", "compiled_anchor"], "selector '%s'" % selector_id, errors)
		var legacy: Variant = selector.get("legacy_anchor")
		if not legacy is Dictionary:
			errors.append("selector '%s' requires legacy_anchor" % selector_id)
		else:
			_require_exact_keys(legacy, ["phase", "kind", "occurrence", "window_role"], "selector '%s' legacy_anchor" % selector_id, errors)
			if str(legacy.get("phase", "")) == "" or str(legacy.get("kind", "")) == "":
				errors.append("selector '%s' has an incomplete legacy_anchor" % selector_id)
			if typeof(legacy.get("occurrence")) != TYPE_INT or int(legacy.get("occurrence", -1)) < 0:
				errors.append("selector '%s' has invalid legacy occurrence" % selector_id)
			if legacy.get("window_role") != "whole":
				errors.append("selector '%s' legacy window_role must be whole" % selector_id)
		var compiled: Variant = selector.get("compiled_anchor")
		if not compiled is Dictionary:
			errors.append("selector '%s' requires compiled_anchor" % selector_id)
		else:
			_require_exact_keys(compiled, ["story_slot_id", "window_role"], "selector '%s' compiled_anchor" % selector_id, errors)
			if str(compiled.get("story_slot_id", "")) == "" or str(compiled.get("window_role", "")) == "":
				errors.append("selector '%s' has an incomplete compiled_anchor" % selector_id)


static func _validate_sources(
	sources: Dictionary, seen_ids: Dictionary, errors: PackedStringArray
) -> void:
	for source_id in sources:
		_claim_id(str(source_id), "source", seen_ids, errors)
		var source: Variant = sources[source_id]
		if not source is Dictionary:
			errors.append("source '%s' must be a Dictionary" % source_id)
			continue
		_reject_unknown_keys(source, SOURCE_FIELDS, "source '%s'" % source_id, errors)
		for key in [
			"initial_state", "state", "permitted_contributions", "permitted_axes",
			"promotion_prerequisites", "url", "retrieved_on", "retrieval_context",
			"row_seat", "device", "sample_rate_hz", "axis_mapping", "reliability",
			"processing", "caveats", "windows", "review_path", "review_sha256",
		]:
			if not source.has(key):
				errors.append("source '%s' is missing %s" % [source_id, key])
		if source.get("initial_state", "") not in EVIDENCE_STATES:
			errors.append("source '%s' has invalid initial_state" % source_id)
		if source.get("state", "") not in EVIDENCE_STATES:
			errors.append("source '%s' has invalid state" % source_id)
		elif source.get("initial_state", "") in EVIDENCE_STATES and source.state not in STATE_CEILINGS[source.initial_state]:
			errors.append("source '%s' state exceeds initial_state permission ceiling" % source_id)
		_validate_string_array(source_id, "permitted_contributions", source.get("permitted_contributions"), false, errors)
		_validate_string_array(source_id, "promotion_prerequisites", source.get("promotion_prerequisites"), false, errors)
		_validate_axes(source_id, source.get("permitted_axes"), errors)
		if str(source.get("url", "")) == "" or str(source.get("retrieval_context", "")) == "":
			errors.append("source '%s' has incomplete retrieval provenance" % source_id)
		if not _valid_date(str(source.get("retrieved_on", ""))):
			errors.append("source '%s' has invalid retrieved_on" % source_id)
		if str(source.get("recording_id", source.get("video_id", ""))) == "":
			errors.append("source '%s' is missing recording_id or video_id" % source_id)
		for key in ["row_seat", "device", "reliability"]:
			if str(source.get(key, "")).strip_edges() == "":
				errors.append("source '%s' is missing %s" % [source_id, key])
		_validate_string_array(source_id, "processing", source.get("processing"), false, errors)
		_validate_string_array(source_id, "caveats", source.get("caveats"), true, errors)
		_validate_sample_rate(source_id, source, errors)
		_validate_axis_mapping(source_id, source, errors)
		_validate_windows(source_id, source, errors)
		_validate_acquisition(source_id, source, errors)
		if source.get("state") == "executable" and source.get("acquisition") != "raw":
			errors.append("source '%s' executable evidence requires raw acquisition" % source_id)
		_validate_metadata_pair(source_id, source, errors)
		_validate_path_hash_pair(source_id, source, "review_path", "review_sha256", true, errors)


static func _validate_acquisition(
	source_id: String, source: Dictionary, errors: PackedStringArray
) -> void:
	var acquisition := str(source.get("acquisition", ""))
	var has_artifact := source.has("artifact_path") or source.has("artifact_sha256")
	var has_diagnostic := source.has("diagnostic_path") or source.has("diagnostic_sha256")
	if acquisition == "":
		if has_artifact or has_diagnostic or source.has("fallback_citations"):
			errors.append("source '%s' acquisition is missing for raw provenance fields" % source_id)
		return
	if acquisition == "raw":
		_validate_path_hash_pair(source_id, source, "artifact_path", "artifact_sha256", true, errors)
		if has_diagnostic:
			errors.append("source '%s' acquisition branches are mixed" % source_id)
		if source.has("fallback_citations"):
			errors.append("source '%s' raw acquisition cannot use fallback_citations" % source_id)
	elif acquisition == "raw_fetch_unavailable":
		_validate_path_hash_pair(source_id, source, "diagnostic_path", "diagnostic_sha256", true, errors)
		if has_artifact:
			errors.append("source '%s' acquisition branches are mixed" % source_id)
		_validate_fallback_citations(source_id, source, errors)
	else:
		errors.append("source '%s' has invalid acquisition" % source_id)


static func _validate_fallback_citations(
	source_id: String, source: Dictionary, errors: PackedStringArray
) -> void:
	var citations: Variant = source.get("fallback_citations")
	if not citations is Array or citations.is_empty():
		errors.append("source '%s' raw_fetch_unavailable requires fallback_citations" % source_id)
		return
	var cited_windows := []
	for index in citations.size():
		var citation: Variant = citations[index]
		if not citation is Dictionary:
			errors.append("source '%s' fallback citation %d must be a Dictionary" % [source_id, index])
			continue
		_require_exact_keys(
			citation,
			["document", "section_id", "line_anchor", "columns_used", "source_windows_used"],
			"source '%s' fallback citation %d" % [source_id, index],
			errors
		)
		if not _valid_repository_path(citation.get("document")):
			errors.append("source '%s' fallback citation %d has invalid document" % [source_id, index])
		for key in ["section_id", "line_anchor"]:
			if str(citation.get(key, "")) == "":
				errors.append("source '%s' fallback citation %d is missing %s" % [source_id, index, key])
		_validate_citation_columns(source_id, index, citation.get("columns_used"), errors)
		var ranges: Variant = citation.get("source_windows_used")
		if not ranges is Array or ranges.is_empty():
			errors.append("source '%s' fallback citation %d has no source windows" % [source_id, index])
		else:
			for range_value in ranges:
				if _range_is_valid(range_value, true):
					cited_windows.append(range_value)
				else:
					errors.append("source '%s' fallback citation %d has invalid source window" % [source_id, index])
	var windows: Variant = source.get("windows")
	if windows is Array:
		for window in windows:
			if window is Dictionary and window.has("window_s"):
				var covered := false
				for cited in cited_windows:
					if _ranges_close(window.window_s, cited):
						covered = true
				if not covered:
					errors.append("source '%s' window '%s' lacks a fallback citation" % [source_id, window.get("id", "")])


static func _validate_citation_columns(
	source_id: String, citation_index: int, columns: Variant, errors: PackedStringArray
) -> void:
	if not columns is Array or columns.is_empty():
		errors.append("source '%s' fallback citation %d has no columns_used" % [source_id, citation_index])
		return
	for column in columns:
		if not column is String or str(column).strip_edges() == "":
			errors.append("source '%s' fallback citation %d has invalid columns_used" % [source_id, citation_index])


static func _validate_metadata_pair(
	source_id: String, source: Dictionary, errors: PackedStringArray
) -> void:
	var has_artifact := source.has("metadata_artifact_path") or source.has("metadata_artifact_sha256")
	var has_diagnostic := source.has("metadata_diagnostic_path") or source.has("metadata_diagnostic_sha256")
	if has_artifact and has_diagnostic:
		errors.append("source '%s' metadata provenance branches are mixed" % source_id)
		return
	if not has_artifact and not has_diagnostic:
		errors.append("source '%s' is missing metadata provenance" % source_id)
		return
	if has_artifact:
		_validate_path_hash_pair(source_id, source, "metadata_artifact_path", "metadata_artifact_sha256", true, errors)
	else:
		_validate_path_hash_pair(source_id, source, "metadata_diagnostic_path", "metadata_diagnostic_sha256", true, errors)


static func _validate_sample_rate(
	source_id: String, source: Dictionary, errors: PackedStringArray
) -> void:
	var sample_rate: Variant = source.get("sample_rate_hz")
	if sample_rate == null:
		var records_unknown := false
		var caveats: Variant = source.get("caveats")
		if caveats is Array:
			for caveat in caveats:
				var text := str(caveat).to_lower()
				if text.contains("sample rate") and text.contains("unknown"):
					records_unknown = true
		if source.get("state") == "executable" or not records_unknown:
			errors.append("source '%s' has unknown sample_rate_hz without a valid caveat" % source_id)
	elif not _positive_number(sample_rate):
		errors.append("source '%s' has invalid sample_rate_hz" % source_id)


static func _validate_axis_mapping(
	source_id: String, source: Dictionary, errors: PackedStringArray
) -> void:
	var mapping: Variant = source.get("axis_mapping")
	if not mapping is Dictionary:
		errors.append("source '%s' axis_mapping must be a Dictionary" % source_id)
		return
	var permitted: Variant = source.get("permitted_axes")
	for source_axis in mapping:
		var mapped_axis := str(mapping[source_axis])
		if str(source_axis) == "" or mapped_axis not in FORCE_AXES:
			errors.append("source '%s' has invalid axis_mapping" % source_id)
		elif not permitted is Array or mapped_axis not in permitted:
			errors.append("source '%s' axis_mapping exceeds permitted_axes" % source_id)
	if source.get("state") == "executable" and mapping.is_empty():
		errors.append("source '%s' executable evidence requires axis_mapping" % source_id)


static func _validate_windows(source_id: String, source: Dictionary, errors: PackedStringArray) -> void:
	var windows: Variant = source.get("windows")
	if not windows is Array:
		errors.append("source '%s' windows must be an Array" % source_id)
		return
	var seen := {}
	for index in windows.size():
		var window: Variant = windows[index]
		if not window is Dictionary:
			errors.append("source '%s' window %d must be a Dictionary" % [source_id, index])
			continue
		var window_id := str(window.get("id", ""))
		if window_id == "" or seen.has(window_id):
			errors.append("source '%s' has invalid or duplicate window id '%s'" % [source_id, window_id])
		seen[window_id] = true
		var has_range: bool = window.has("window_s")
		var has_point: bool = window.has("time_s")
		if has_range == has_point:
			errors.append("source '%s' window '%s' needs exactly one time shape" % [source_id, window_id])
		elif has_range:
			_validate_range("source window", "%s/%s" % [source_id, window_id], "window_s", window.window_s, true, errors)
		elif not _nonnegative_number(window.time_s):
			errors.append("source window '%s/%s' has invalid time_s" % [source_id, window_id])
		if window.has("uncertainty_s") and not _nonnegative_number(window.uncertainty_s):
			errors.append("source window '%s/%s' has invalid uncertainty_s" % [source_id, window_id])
		var permitted: Variant = source.get("permitted_axes")
		if window.has("axis") and (
			window.axis not in FORCE_AXES or not permitted is Array or window.axis not in permitted
		):
			errors.append("source window '%s/%s' exceeds permitted_axes" % [source_id, window_id])


static func _validate_transforms(
	transforms: Dictionary, seen_ids: Dictionary, errors: PackedStringArray
) -> void:
	for transform_id in transforms:
		_claim_id(str(transform_id), "transform", seen_ids, errors)
		var transform: Variant = transforms[transform_id]
		if not transform is Dictionary:
			errors.append("transform '%s' must be a Dictionary" % transform_id)
			continue
		if transform_id == "observed.identity@1":
			_require_exact_keys(transform, ["kind", "factor", "formula", "approval"], "transform '%s'" % transform_id, errors)
			if (
				transform.get("kind") != "identity"
				or not _number_close(transform.get("factor"), 1.0)
				or transform.get("formula") != "target_value = observed_value"
				or transform.get("approval") != "identity; no transform"
			):
				errors.append("transform '%s' has invalid identity" % transform_id)
		elif APPROVED_TRANSFORMS.has(transform_id):
			_require_exact_keys(transform, ["kind", "axis", "polarity", "factor", "formula", "approval"], "transform '%s'" % transform_id, errors)
			var approved: Array = APPROVED_TRANSFORMS[transform_id]
			if transform.get("axis") == "longitudinal_g" and transform.get("polarity") == "positive":
				errors.append("Gx+ transform is unsupported")
			if (
				transform.get("kind") != "scale"
				or transform.get("axis") != approved[0]
				or transform.get("polarity") != approved[1]
				or not _number_close(transform.get("factor"), approved[2])
			):
				errors.append("transform '%s' does not match its approved force axis, polarity, and factor" % transform_id)
			if transform.get("formula") != approved[3]:
				errors.append("transform '%s' has invalid formula" % transform_id)
			if transform.get("approval") != approved[4]:
				errors.append("transform '%s' has invalid approval provenance" % transform_id)
		else:
			errors.append("transform '%s' is not approved" % transform_id)
		if str(transform.get("formula", "")) == "" or str(transform.get("approval", "")) == "":
			errors.append("transform '%s' is missing formula or approval" % transform_id)


static func _validate_observations(
	observations: Array, sources: Dictionary, selectors: Dictionary, transforms: Dictionary,
	seen_ids: Dictionary, errors: PackedStringArray
) -> Dictionary:
	var by_id := {}
	for index in observations.size():
		var observation: Variant = observations[index]
		if not observation is Dictionary:
			errors.append("observation %d must be a Dictionary" % index)
			continue
		_reject_unknown_keys(observation, OBSERVATION_FIELDS, "observation %d" % index, errors)
		var observation_id := str(observation.get("id", ""))
		_claim_id(observation_id, "observation", seen_ids, errors)
		if observation_id != "":
			by_id[observation_id] = observation
		for key in [
			"state", "source_id", "source_window_id", "source_axis", "mapped_axis",
			"row_seat", "duration_s", "metric", "hold_seconds", "raw_range", "transform_id",
			"confidence", "confidence_rationale", "corroborating_observation_ids",
			"semantic_selector_id", "alignment",
		]:
			if not observation.has(key):
				errors.append("observation '%s' is missing %s" % [observation_id, key])
		if observation.get("state") not in ["corroborative", "executable"]:
			errors.append("observation '%s' has invalid state" % observation_id)
		if observation.get("confidence") not in CONFIDENCE or str(observation.get("confidence_rationale", "")) == "":
			errors.append("observation '%s' has invalid confidence" % observation_id)
		_validate_range("observation", observation_id, "raw_range", observation.get("raw_range"), false, errors)
		if not _positive_number(observation.get("duration_s")):
			errors.append("observation '%s' has invalid duration_s" % observation_id)
		var source_id := str(observation.get("source_id", ""))
		var source: Variant = sources.get(source_id)
		if not source is Dictionary:
			errors.append("observation '%s' references unknown source '%s'" % [observation_id, source_id])
		else:
			_validate_observation_source(observation_id, observation, source, errors)
		var selector_id := str(observation.get("semantic_selector_id", ""))
		if not selectors.has(selector_id):
			errors.append("observation '%s' references unknown semantic selector '%s'" % [observation_id, selector_id])
		var transform_id := str(observation.get("transform_id", ""))
		var transform: Variant = transforms.get(transform_id)
		if not transform is Dictionary:
			errors.append("observation '%s' references unknown transform '%s'" % [observation_id, transform_id])
		else:
			_validate_observation_metric(observation_id, observation, transform, errors)
		_validate_alignment(observation_id, observation.get("alignment"), selector_id, errors)
		var corroborating: Variant = observation.get("corroborating_observation_ids")
		if not corroborating is Array:
			errors.append("observation '%s' corroborating_observation_ids must be an Array" % observation_id)
		elif observation.get("state") != "executable" and not corroborating.is_empty():
			errors.append("observation '%s' non-executable evidence cannot declare corroboration" % observation_id)
	for observation_id in by_id:
		var observation: Dictionary = by_id[observation_id]
		if observation.get("state") == "executable":
			_validate_promotion(observation_id, observation, by_id, sources, errors)
	return by_id


static func _validate_observation_source(
	observation_id: String, observation: Dictionary, source: Dictionary,
	errors: PackedStringArray
) -> void:
	if source.get("initial_state") not in ["corroborative", "executable"] or source.get("state") not in ["corroborative", "executable"]:
		errors.append("observation '%s' exceeds the source permission ceiling" % observation_id)
	if source.get("acquisition") != "raw" or not _positive_number(source.get("sample_rate_hz")):
		errors.append("observation '%s' requires a raw sampled artifact" % observation_id)
	var permitted: Variant = source.get("permitted_axes")
	if not permitted is Array or observation.get("mapped_axis") not in permitted:
		errors.append("observation '%s' exceeds source permitted_axes" % observation_id)
	if not source.get("axis_mapping") is Dictionary or source.get("axis_mapping", {}).get(observation.get("source_axis")) != observation.get("mapped_axis"):
		errors.append("observation '%s' has incompatible axis mapping" % observation_id)
	if observation.get("row_seat") != source.get("row_seat"):
		errors.append("observation '%s' row_seat does not match its source" % observation_id)
	var window := _window_by_id(source.get("windows"), str(observation.get("source_window_id", "")))
	if window.is_empty() or not _range_is_valid(window.get("window_s"), true):
		errors.append("observation '%s' has unknown or non-duration source_window_id" % observation_id)
		return
	var duration := float(window.window_s[1]) - float(window.window_s[0])
	if not _number_close(observation.get("duration_s"), duration):
		errors.append("observation '%s' duration_s does not match source_window_id" % observation_id)
	var alignment: Variant = observation.get("alignment")
	if not alignment is Dictionary or alignment.get("source_landmark_id") != observation.get("source_window_id"):
		errors.append("observation '%s' source_landmark_id does not resolve source_window_id" % observation_id)


static func _validate_observation_metric(
	observation_id: String, observation: Dictionary, transform: Dictionary,
	errors: PackedStringArray
) -> void:
	var metric := str(observation.get("metric", ""))
	var mapped_axis := str(observation.get("mapped_axis", ""))
	if metric not in METRICS or _metric_axis(metric) != mapped_axis:
		errors.append("observation '%s' metric does not match mapped_axis" % observation_id)
	var hold_seconds: Variant = observation.get("hold_seconds")
	if metric.contains("_held_"):
		if (
			not _positive_number(hold_seconds)
			or not _positive_number(observation.get("duration_s"))
			or float(hold_seconds) > float(observation.duration_s)
		):
			errors.append("observation '%s' has invalid held duration" % observation_id)
	elif hold_seconds != null:
		errors.append("observation '%s' peak metric cannot declare hold_seconds" % observation_id)
	if transform.get("kind") == "scale" and transform.get("axis") != mapped_axis:
		errors.append("observation '%s' transform axis does not match mapped_axis" % observation_id)
	if not _range_is_valid(observation.get("raw_range"), false):
		return
	var raw_range: Array = observation.raw_range
	var polarity := _metric_polarity(metric)
	if polarity == "positive" and float(raw_range[0]) < 0.0:
		errors.append("observation '%s' applies a transform to the wrong polarity" % observation_id)
	elif polarity == "negative" and float(raw_range[1]) > 0.0:
		errors.append("observation '%s' applies a transform to the wrong polarity" % observation_id)
	if transform.get("kind") == "scale" and transform.get("polarity") != polarity:
		errors.append("observation '%s' transform polarity does not match metric" % observation_id)


static func _validate_promotion(
	observation_id: String, observation: Dictionary, observations: Dictionary,
	sources: Dictionary, errors: PackedStringArray
) -> void:
	var source: Variant = sources.get(str(observation.get("source_id", "")))
	if not source is Dictionary:
		return
	var ids: Variant = observation.get("corroborating_observation_ids")
	if not ids is Array:
		return
	if source.get("initial_state") == "corroborative" or source.get("state") == "corroborative":
		if ids.is_empty():
			errors.append("observation '%s' requires corroboration" % observation_id)
	var seen := {}
	for corroborating_id in ids:
		var other_id := str(corroborating_id)
		if other_id == observation_id:
			errors.append("observation '%s' requires independent corroboration" % observation_id)
			continue
		if other_id == "" or seen.has(other_id):
			errors.append("observation '%s' has duplicate or empty corroboration" % observation_id)
			continue
		seen[other_id] = true
		var other: Variant = observations.get(other_id)
		if not other is Dictionary:
			errors.append("observation '%s' references unknown corroborating observation '%s'" % [observation_id, other_id])
			continue
		if other.get("source_id") == observation.get("source_id"):
			errors.append("observation '%s' requires an independent source" % observation_id)
		if (
			other.get("state") not in ["corroborative", "executable"]
			or other.get("semantic_selector_id") != observation.get("semantic_selector_id")
			or other.get("mapped_axis") != observation.get("mapped_axis")
			or other.get("metric") != observation.get("metric")
			or other.get("hold_seconds") != observation.get("hold_seconds")
			or other.get("row_seat") != observation.get("row_seat")
			or not _ranges_overlap(other.get("raw_range"), observation.get("raw_range"))
		):
			errors.append("observation '%s' has incompatible corroboration '%s'" % [observation_id, other_id])


static func _validate_targets(
	targets: Array, observations: Dictionary, selectors: Dictionary, transforms: Dictionary,
	seen_ids: Dictionary, errors: PackedStringArray
) -> void:
	for index in targets.size():
		var target: Variant = targets[index]
		if not target is Dictionary:
			errors.append("target %d must be a Dictionary" % index)
			continue
		_reject_unknown_keys(target, TARGET_FIELDS, "target %d" % index, errors)
		var target_id := str(target.get("id", ""))
		_claim_id(target_id, "target", seen_ids, errors)
		var observation_id := str(target.get("observation_id", ""))
		var observation: Variant = observations.get(observation_id)
		if not observation is Dictionary or observation.get("state") != "executable":
			errors.append("target '%s' references unknown observation '%s' or one that is not executable" % [target_id, observation_id])
			observation = {}
		var selector_id := str(target.get("semantic_selector_id", ""))
		if selector_id != observation.get("semantic_selector_id"):
			errors.append("target '%s' semantic_selector_id must match observation" % target_id)
		elif not selectors.has(selector_id):
			errors.append("target '%s' references unknown semantic selector '%s'" % [target_id, selector_id])
		if target.get("dimension") not in DIMENSIONS:
			errors.append("target '%s' has unsupported dimension" % target_id)
		if target.get("dimension") != "loads" or target.get("metric") != observation.get("metric"):
			errors.append("target '%s' metric must match observation" % target_id)
		_validate_range("target", target_id, "raw_range", target.get("raw_range"), false, errors)
		_validate_range("target", target_id, "target_range", target.get("target_range"), false, errors)
		var hold_seconds: Variant = target.get("hold_seconds")
		if hold_seconds != observation.get("hold_seconds"):
			errors.append("target '%s' hold_seconds must match observation" % target_id)
		if not _ranges_close(target.get("raw_range"), observation.get("raw_range")):
			errors.append("target '%s' raw_range must match observation" % target_id)
		var expected_target := _transformed_range(observation, transforms)
		if expected_target.is_empty() or not _ranges_close(target.get("target_range"), expected_target):
			errors.append("target '%s' target_range must match the approved transform" % target_id)
		_validate_issues("target", target_id, target.get("issues"), errors)


static func _window_by_id(windows: Variant, window_id: String) -> Dictionary:
	if not windows is Array:
		return {}
	for window in windows:
		if window is Dictionary and window.get("id") == window_id:
			return window
	return {}


static func _metric_axis(metric: String) -> String:
	if metric.begins_with("normal_"):
		return "normal_g"
	if metric.begins_with("lateral_"):
		return "lateral_g"
	if metric.begins_with("longitudinal_"):
		return "longitudinal_g"
	return ""


static func _metric_polarity(metric: String) -> String:
	if metric.ends_with("_positive"):
		return "positive"
	if metric.ends_with("_negative"):
		return "negative"
	return "identity"


static func _ranges_overlap(first: Variant, second: Variant) -> bool:
	return (
		_range_is_valid(first, false)
		and _range_is_valid(second, false)
		and maxf(float(first[0]), float(second[0])) <= minf(float(first[1]), float(second[1]))
	)


static func _ranges_close(first: Variant, second: Variant) -> bool:
	return (
		_range_is_valid(first, false)
		and _range_is_valid(second, false)
		and is_equal_approx(float(first[0]), float(second[0]))
		and is_equal_approx(float(first[1]), float(second[1]))
	)


static func _transformed_range(observation: Dictionary, transforms: Dictionary) -> Array:
	var raw_range: Variant = observation.get("raw_range")
	var transform: Variant = transforms.get(str(observation.get("transform_id", "")))
	if not _range_is_valid(raw_range, false) or not transform is Dictionary:
		return []
	if not _positive_number(transform.get("factor")):
		return []
	var factor := float(transform.factor)
	if transform.get("kind") == "identity":
		factor = 1.0
	return [float(raw_range[0]) * factor, float(raw_range[1]) * factor]


static func _validate_alignment(
	observation_id: String, alignment: Variant, selector_id: String, errors: PackedStringArray
) -> void:
	if not alignment is Dictionary:
		errors.append("observation '%s' has incomplete alignment" % observation_id)
		return
	_require_exact_keys(
		alignment,
		["source_landmark_id", "generated_anchor", "method", "uncertainty_s", "row_compatibility", "rationale"],
		"observation '%s' alignment" % observation_id,
		errors
	)
	var generated: Variant = alignment.get("generated_anchor")
	if not generated is Dictionary or generated.get("semantic_selector_id") != selector_id:
		errors.append("observation '%s' alignment has invalid generated_anchor" % observation_id)
	elif generated.size() != 1:
		errors.append("observation '%s' alignment generated_anchor has unsupported fields" % observation_id)
	if str(alignment.get("source_landmark_id", "")) == "" or str(alignment.get("method", "")) == "" or str(alignment.get("rationale", "")) == "":
		errors.append("observation '%s' has incomplete alignment" % observation_id)
	if not _nonnegative_number(alignment.get("uncertainty_s")):
		errors.append("observation '%s' alignment has invalid uncertainty_s" % observation_id)
	if alignment.get("row_compatibility") not in ["same-row", "explicit-row-transform", "row-independent"]:
		errors.append("observation '%s' alignment has invalid row_compatibility" % observation_id)


static func _validate_auxiliary_records(
	records: Array, key: String, sources: Dictionary, seen_ids: Dictionary,
	errors: PackedStringArray
) -> void:
	for index in records.size():
		var record: Variant = records[index]
		if not record is Dictionary:
			errors.append("%s record %d must be a Dictionary" % [key, index])
			continue
		var record_id := str(record.get("id", ""))
		_claim_id(record_id, key, seen_ids, errors)
		if str(record.get("prompt", record.get("description", ""))) == "":
			errors.append("%s '%s' is missing text" % [key, record_id])
		if key == "review_prompts" and str(record.get("category", "")) == "":
			errors.append("review_prompts '%s' is missing category" % record_id)
		_validate_issues(key, record_id, record.get("issues"), errors)
		_referenced_ids(key, record_id, "source_ids", record.get("source_ids"), sources, true, errors)


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
	record_kind: String, record_id: String, key: String, value: Variant,
	require_span: bool, errors: PackedStringArray
) -> void:
	if not _range_is_valid(value, require_span):
		errors.append("%s '%s' has invalid %s" % [record_kind, record_id, key])


static func _range_is_valid(value: Variant, require_span: bool) -> bool:
	return (
		value is Array
		and value.size() == 2
		and _finite_number(value[0])
		and _finite_number(value[1])
		and float(value[0]) <= float(value[1])
		and (not require_span or float(value[0]) < float(value[1]))
	)


static func _validate_axes(source_id: String, value: Variant, errors: PackedStringArray) -> void:
	if not value is Array:
		errors.append("source '%s' permitted_axes must be an Array" % source_id)
		return
	var seen := {}
	for axis in value:
		if axis not in FORCE_AXES or seen.has(axis):
			errors.append("source '%s' has invalid permitted_axes" % source_id)
		seen[axis] = true


static func _validate_string_array(
	record_id: String, key: String, value: Variant, allow_empty: bool,
	errors: PackedStringArray
) -> void:
	if not value is Array or (not allow_empty and value.is_empty()):
		errors.append("source '%s' has invalid %s" % [record_id, key])
		return
	for item in value:
		if not item is String or str(item).strip_edges() == "":
			errors.append("source '%s' has invalid %s" % [record_id, key])


static func _validate_path_hash_pair(
	source_id: String, source: Dictionary, path_key: String, hash_key: String,
	required: bool, errors: PackedStringArray
) -> void:
	var has_path := source.has(path_key)
	var has_hash := source.has(hash_key)
	if not has_path and not has_hash and not required:
		return
	if not has_path or not has_hash:
		errors.append("source '%s' has incomplete %s/%s pair" % [source_id, path_key, hash_key])
		return
	if not _valid_repository_path(source[path_key]):
		errors.append("source '%s' has invalid %s" % [source_id, path_key])
	if not _valid_sha256(source[hash_key]):
		errors.append("source '%s' has invalid %s" % [source_id, hash_key])


static func _validate_artifact(
	source_id: String, label: String, repository_path: String, expected: String,
	errors: PackedStringArray
) -> void:
	var absolute_path := ProjectSettings.globalize_path("res://../" + repository_path)
	if not FileAccess.file_exists(absolute_path):
		errors.append("source '%s' %s artifact is missing: %s" % [source_id, label, repository_path])
		return
	var file := FileAccess.open(absolute_path, FileAccess.READ)
	if file == null:
		errors.append("source '%s' %s artifact is unreadable: %s" % [source_id, label, repository_path])
		return
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(file.get_buffer(file.get_length()))
	var actual := context.finish().hex_encode()
	if actual != expected:
		errors.append("source '%s' %s artifact digest mismatch: %s" % [source_id, label, repository_path])


static func _referenced_ids(
	record_kind: String, record_id: String, key: String, value: Variant,
	known: Dictionary, allow_empty: bool, errors: PackedStringArray
) -> Array:
	var output := []
	if not value is Array or (not allow_empty and value.is_empty()):
		errors.append("%s '%s' has invalid %s" % [record_kind, record_id, key])
		return output
	var seen := {}
	for referenced_id in value:
		var text := str(referenced_id)
		if text == "" or seen.has(text):
			errors.append("%s '%s' has duplicate or empty %s" % [record_kind, record_id, key])
		elif not known.has(text):
			errors.append("%s '%s' references unknown source '%s'" % [record_kind, record_id, text])
		else:
			output.append(text)
		seen[text] = true
	return output


static func _claim_id(
	record_id: String, record_kind: String, seen: Dictionary, errors: PackedStringArray
) -> void:
	if record_id == "":
		errors.append("%s is missing id" % record_kind)
	elif seen.has(record_id):
		errors.append("duplicate id '%s'" % record_id)
	else:
		seen[record_id] = record_kind


static func _require_exact_keys(
	record: Dictionary, allowed: Array, label: String, errors: PackedStringArray
) -> void:
	for key in allowed:
		if not record.has(key):
			errors.append("%s is missing %s" % [label, key])
	_reject_unknown_keys(record, allowed, label, errors)


static func _reject_unknown_keys(
	record: Dictionary, allowed: Array, label: String, errors: PackedStringArray
) -> void:
	for key in record:
		if key not in allowed:
			errors.append("%s has unsupported field %s" % [label, key])


static func _valid_repository_path(value: Variant) -> bool:
	if not value is String:
		return false
	var path := str(value)
	if path == "" or path.is_absolute_path() or path.contains("://") or path.contains("\\"):
		return false
	for part in path.split("/"):
		if part in ["", ".", ".."]:
			return false
	return true


static func _valid_sha256(value: Variant) -> bool:
	if not value is String:
		return false
	var text := str(value)
	if text.length() != 64:
		return false
	for index in text.length():
		var code := text.unicode_at(index)
		if not (code >= 48 and code <= 57) and not (code >= 97 and code <= 102):
			return false
	return true


static func _valid_date(value: String) -> bool:
	if (
		value.length() != 10
		or value[4] != "-"
		or value[7] != "-"
		or not value.substr(0, 4).is_valid_int()
		or not value.substr(5, 2).is_valid_int()
		or not value.substr(8, 2).is_valid_int()
	):
		return false
	var year := int(value.substr(0, 4))
	var month := int(value.substr(5, 2))
	var day := int(value.substr(8, 2))
	if year < 1 or month < 1 or month > 12:
		return false
	var days := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if year % 400 == 0 or (year % 4 == 0 and year % 100 != 0):
		days[1] = 29
	return day >= 1 and day <= days[month - 1]


static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _positive_number(value: Variant) -> bool:
	return _finite_number(value) and float(value) > 0.0


static func _nonnegative_number(value: Variant) -> bool:
	return _finite_number(value) and float(value) >= 0.0


static func _number_close(value: Variant, expected: float) -> bool:
	return _finite_number(value) and is_equal_approx(float(value), expected)


static func _slug(value: String) -> String:
	var output := value.strip_edges().to_lower().replace("_", "-").replace(" ", "-")
	while output.contains("--"):
		output = output.replace("--", "-")
	return output if output != "" else "unassigned"
