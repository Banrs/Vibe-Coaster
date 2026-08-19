class_name RideFidelity
extends RefCounted

const Verify := preload("res://verify.gd")
const Terrain := preload("res://terrain.gd")
const CanonicalData := preload("res://canonical_data.gd")

const CONFIDENCE := ["high", "medium", "low"]
const DIMENSIONS := ["loads", "geometry", "pacing", "terrain", "flow"]
const METRICS := [
	"normal_peak_positive", "normal_peak_negative",
	"normal_held_positive", "normal_held_negative",
	"lateral_peak_absolute", "longitudinal_held_positive",
	"longitudinal_peak_positive", "longitudinal_peak_negative",
]
const HOLD_SECONDS := [0.2, 0.5, 0.8, 1.0, 1.1, 1.4, 2.0, 2.4, 2.78, 3.0, 4.0, 6.8, 12.0]
const CANONICAL_FLEET := [11, 42, 20260809, 1, 3, 7, 99, 256, 555, 1234, 4096, 31337, 77777, 123456, 20250101]
const ROW_BEAT_REDUCERS := ["minimum", "maximum", "median", "time_weighted_mean"]
const SEED_REDUCERS := ["minimum", "maximum", "median"]
const ROW_OFFSET_TOLERANCE := 0.000001
const TERRAIN_HUGGING_AGL := 20.0
const TRANSITION_WINDOW_SECONDS := 0.5
const GRAVITY_MPS2 := 9.80665
const CURVATURE_ZERO_EPS := 1e-9


## Largest value a window sustains for `seconds`, signed by `polarity`. This is the same
## held-curve convention used by the load verifier and the smoke fidelity bands.
static func held(values: PackedFloat32Array, polarity: float, seconds: float) -> float:
	if not is_finite(seconds) or seconds < 0.0 or values.is_empty():
		return -INF
	var window := _hold_window_samples(seconds)
	if window > values.size():
		return -INF
	return Verify._held_curve(values, polarity)[window] * polarity


static func classify_value(value: float, target_range: Array) -> String:
	if value < float(target_range[0]):
		return "under"
	if value > float(target_range[1]):
		return "over"
	return "within"


static func normalized_miss(value: float, target_range: Array) -> float:
	var distance := 0.0
	if value < float(target_range[0]):
		distance = float(target_range[0]) - value
	elif value > float(target_range[1]):
		distance = value - float(target_range[1])
	var denominator := maxf(
		0.1,
		maxf(
			absf(float(target_range[0])),
			maxf(
				absf(float(target_range[1])),
				float(target_range[1]) - float(target_range[0])
			)
		)
	)
	return distance / denominator


static func compare_fleet(seed_measurements: Array, catalog: Dictionary) -> Dictionary:
	if not validate_catalog(catalog).is_empty():
		return {"status": "invalid-input", "reason": "catalog-invalid"}
	if not _canonical_fleet_is_valid(seed_measurements):
		return {"status": "invalid-input", "reason": "fleet-invalid"}

	for measurement_value in seed_measurements:
		if not _comparison_measurement_is_valid(measurement_value):
			return {"status": "invalid-input", "reason": "measurement-invalid"}

	var observations: Array = catalog.get("observations", [])
	var observation_by_id := _comparison_records_by_id(observations)
	var selectors: Dictionary = catalog.get("selectors", {})
	var sources: Dictionary = catalog.get("sources", {})
	var resolved_by_observation := {}
	for observation_value in observations:
		var observation: Dictionary = observation_value
		resolved_by_observation[str(observation.id)] = {}
	# Resolve every catalogued observation once before representation validation so malformed
	# consumed fields retain their documented precedence over a mixed fleet.
	for measurement_value in seed_measurements:
		var measurement: Dictionary = measurement_value
		for observation_value in observations:
			var observation: Dictionary = observation_value
			var selector: Dictionary = selectors[str(observation.get("semantic_selector_id", ""))]
			var resolved := _resolve_comparison_samples(measurement, observation, selector)
			if resolved.get("invalid", false):
				return {"status": "invalid-input", "reason": "measurement-invalid"}
			var by_seed: Dictionary = resolved_by_observation[str(observation.id)]
			by_seed[int(measurement.seed)] = resolved

	var schemas := {}
	for measurement_value in seed_measurements:
		var measurement: Dictionary = measurement_value
		schemas[int(measurement.schema_version)] = true
	if schemas.size() != 1:
		return {"status": "invalid-input", "reason": "mixed-representation"}
	var resolved_branch := "legacy" if schemas.has(1) else "compiled"

	var measurements := seed_measurements.duplicate()
	measurements.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return int(first.seed) < int(second.seed)
	)
	var fleet := []
	for measurement_value in seed_measurements:
		var measurement: Dictionary = measurement_value
		fleet.append(int(measurement.seed))

	var targets: Array = catalog.get("targets", [])
	targets = targets.duplicate()
	targets.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return str(first.get("id", "")) < str(second.get("id", ""))
	)
	var targeted_observations := {}
	var findings := []
	var evidence_gaps := []
	for target_value in targets:
		var target: Dictionary = target_value
		var observation_id := str(target.observation_id)
		targeted_observations[observation_id] = true
		var observation: Dictionary = observation_by_id[observation_id]
		var selector: Dictionary = selectors[str(target.semantic_selector_id)]
		var resolved_by_seed: Dictionary = resolved_by_observation[observation_id]
		var seed_results := []
		var gap_count := 0
		for measurement_value in measurements:
			var measurement: Dictionary = measurement_value
			var resolved: Dictionary = resolved_by_seed[int(measurement.seed)]
			if resolved.has("reason"):
				evidence_gaps.append({
					"target_id": str(target.id),
					"seed": int(measurement.seed),
					"reason": str(resolved.reason),
				})
				gap_count += 1
				continue
			var reduced := _reduce_comparison_samples(resolved.samples, target.aggregation)
			var value := float(reduced.value)
			var target_range: Array = target.target_range
			seed_results.append({
				"seed": int(measurement.seed),
				"value": value,
				"status": classify_value(value, target_range),
				"normalized_miss": normalized_miss(value, target_range),
				"retained_seconds": float(reduced.retained_seconds),
				"beat_ids": reduced.beat_ids,
				"row_ids": reduced.row_ids,
			})
		if not seed_results.is_empty():
			var resolved_anchor: Dictionary = selector["%s_anchor" % resolved_branch]
			findings.append(_build_target_finding(
				target, observation, resolved_branch, resolved_anchor, seed_results, gap_count,
				observation_by_id, sources
			))

	var observed_only := []
	var sorted_observations := observations.duplicate()
	sorted_observations.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return str(first.get("id", "")) < str(second.get("id", ""))
	)
	for observation_value in sorted_observations:
		var observation: Dictionary = observation_value
		if targeted_observations.has(str(observation.id)):
			continue
		var resolved_by_seed: Dictionary = resolved_by_observation[str(observation.id)]
		for measurement_value in measurements:
			var measurement: Dictionary = measurement_value
			var resolved: Dictionary = resolved_by_seed[int(measurement.seed)]
			if resolved.has("reason"):
				continue
			var samples: Array = resolved.samples
			for sample_value in samples:
				var sample: Dictionary = sample_value
				observed_only.append({
					"observation_id": str(observation.id),
					"source_id": str(observation.source_id),
					"metric": str(observation.metric),
					"seed": int(measurement.seed),
					"beat_id": str(sample.beat_id),
					"row_id": str(sample.row_id),
					"value": float(sample.value),
					"retained_seconds": float(sample.seconds),
				})

	observed_only.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		if str(first.observation_id) != str(second.observation_id):
			return str(first.observation_id) < str(second.observation_id)
		if int(first.seed) != int(second.seed):
			return int(first.seed) < int(second.seed)
		if str(first.beat_id) != str(second.beat_id):
			return str(first.beat_id) < str(second.beat_id)
		return str(first.row_id) < str(second.row_id)
	)
	evidence_gaps.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		if str(first.target_id) != str(second.target_id):
			return str(first.target_id) < str(second.target_id)
		return int(first.seed) < int(second.seed)
	)
	return {
		"fleet": fleet,
		"findings": findings,
		"observed_only": observed_only,
		"evidence_gaps": evidence_gaps,
		"recommendation": _comparison_recommendation(findings),
	}


static func _canonical_fleet_is_valid(seed_measurements: Array) -> bool:
	var actual := []
	for measurement_value in seed_measurements:
		if not measurement_value is Dictionary:
			return false
		var measurement: Dictionary = measurement_value
		if typeof(measurement.get("seed")) != TYPE_INT:
			return false
		actual.append(int(measurement.seed))
	actual.sort()
	var expected := CANONICAL_FLEET.duplicate()
	expected.sort()
	return actual == expected


static func _comparison_measurement_is_valid(measurement_value: Variant) -> bool:
	if not measurement_value is Dictionary:
		return false
	var measurement: Dictionary = measurement_value
	if typeof(measurement.get("schema_version")) != TYPE_INT or measurement.schema_version not in [1, 2]:
		return false
	var beats_value: Variant = measurement.get("beats")
	if not beats_value is Array:
		return false
	var discriminator_fields := ["phase", "kind"]
	if int(measurement.schema_version) == 2:
		discriminator_fields = ["story_slot_id", "window_role"]
	var beat_ids := {}
	for beat_value in beats_value:
		if not beat_value is Dictionary:
			return false
		var beat: Dictionary = beat_value
		var beat_id_value: Variant = beat.get("beat_id")
		if not _nonempty_string(beat_id_value) or beat_ids.has(beat_id_value):
			return false
		beat_ids[beat_id_value] = true
		for field in discriminator_fields:
			var discriminator_value: Variant = beat.get(field)
			if not _nonempty_string(discriminator_value):
				return false
		var rows_value: Variant = beat.get("rows")
		if not rows_value is Array:
			return false
		var row_ids := {}
		for row_value in rows_value:
			if not row_value is Dictionary:
				return false
			var row: Dictionary = row_value
			var row_id_value: Variant = row.get("row_id")
			if not _nonempty_string(row_id_value) or row_ids.has(row_id_value):
				return false
			row_ids[row_id_value] = true
	return true


static func _comparison_records_by_id(records: Array) -> Dictionary:
	var by_id := {}
	for record_value in records:
		var record: Dictionary = record_value
		by_id[str(record.id)] = record
	return by_id


static func _resolve_comparison_samples(
	measurement: Dictionary, observation: Dictionary, selector: Dictionary
) -> Dictionary:
	var branch := "legacy" if int(measurement.schema_version) == 1 else "compiled"
	var anchor: Dictionary = selector["%s_anchor" % branch]
	var selected_beats := []
	var beats: Array = measurement.beats
	if branch == "legacy":
		var occurrence := int(anchor.occurrence)
		var matched := 0
		for beat_value in beats:
			var beat: Dictionary = beat_value
			if beat.get("phase") != anchor.phase or beat.get("kind") != anchor.kind:
				continue
			if matched == occurrence:
				selected_beats.append(beat)
				break
			matched += 1
	else:
		for beat_value in beats:
			var beat: Dictionary = beat_value
			if _matches_compiled_anchor(beat, anchor):
				selected_beats.append(beat)
		selected_beats.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			return str(first.beat_id) < str(second.beat_id)
		)
	if selected_beats.is_empty():
		return {"reason": "anchor-not-found", "branch": branch, "anchor": anchor}

	var selected_pairs := []
	var alignment: Dictionary = observation.alignment
	var compatibility := str(alignment.row_compatibility)
	var first_row_gap := ""
	for beat_value in selected_beats:
		var beat: Dictionary = beat_value
		var rows: Array = beat.rows
		var selected_rows := []
		if compatibility == "row-independent":
			selected_rows = rows.duplicate()
		else:
			var row_selector: Dictionary = alignment.generated_row_selector
			for row_value in rows:
				var row: Dictionary = row_value
				var matches := false
				if row_selector.has("row_id"):
					matches = row.get("row_id") == row_selector.row_id
				elif row_selector.has("position"):
					var position_value: Variant = row.get("position")
					if position_value not in ["front", "intermediate", "rear"]:
						return {"invalid": true}
					matches = position_value == row_selector.position
				else:
					if not _finite_number(row.get("offset")):
						return {"invalid": true}
					matches = absf(float(row.offset) - float(row_selector.offset)) <= ROW_OFFSET_TOLERANCE
				if matches:
					selected_rows.append(row)
			if selected_rows.size() > 1:
				if first_row_gap == "":
					first_row_gap = "row-ambiguous"
				continue
		if selected_rows.is_empty():
			if first_row_gap == "":
				first_row_gap = "row-not-found"
			continue
		selected_rows.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			return str(first.row_id) < str(second.row_id)
		)
		for row_value in selected_rows:
			var row: Dictionary = row_value
			selected_pairs.append({"beat": beat, "row": row})
	var samples := []
	var first_metric_gap := ""
	for pair_value in selected_pairs:
		var pair: Dictionary = pair_value
		var beat: Dictionary = pair.beat
		var row: Dictionary = pair.row
		var metric_result := _resolve_comparison_metric(row, observation)
		if metric_result.get("invalid", false):
			return {"invalid": true}
		if metric_result.has("reason"):
			if first_metric_gap == "":
				first_metric_gap = str(metric_result.reason)
			continue
		samples.append({
			"beat_id": str(beat.beat_id),
			"row_id": str(row.row_id),
			"value": float(metric_result.value),
			"seconds": float(metric_result.seconds),
		})
	if first_row_gap != "":
		return {"reason": first_row_gap, "branch": branch, "anchor": anchor}
	if first_metric_gap != "":
		return {"reason": first_metric_gap, "branch": branch, "anchor": anchor}
	return {"samples": samples, "branch": branch, "anchor": anchor}


static func _matches_compiled_anchor(beat: Dictionary, anchor: Dictionary) -> bool:
	if beat.get("story_slot_id") != anchor.get("story_slot_id") \
			or beat.get("window_role") != anchor.get("window_role"):
		return false
	for field in ["kind", "occurrence", "window_id"]:
		if anchor.has(field) and beat.get(field) != anchor[field]:
			return false
	return true


static func _resolve_comparison_metric(row: Dictionary, observation: Dictionary) -> Dictionary:
	var loads_value: Variant = row.get("loads")
	var metric := str(observation.metric)
	if not loads_value is Dictionary:
		return {"invalid": true}
	var loads: Dictionary = loads_value
	if not metric.contains("_held_") and not _positive_number(row.get("window_seconds")):
		return {"invalid": true}
	if not loads.has(metric):
		return {"reason": "metric-not-found"}
	var stored_value: Variant = loads[metric]
	if metric.contains("_held_"):
		if not stored_value is Dictionary:
			return {"invalid": true}
		var held_values: Dictionary = stored_value
		var hold_key := _hold_key(float(observation.hold_seconds))
		var unavailable_value: Variant = held_values.get("_unavailable", {})
		if not unavailable_value is Dictionary:
			return {"invalid": true}
		var unavailable: Dictionary = unavailable_value
		var has_available := held_values.has(hold_key)
		var has_unavailable := unavailable.has(hold_key)
		if has_available and has_unavailable:
			return {"invalid": true}
		if has_available:
			if not _finite_number(held_values[hold_key]):
				return {"invalid": true}
			return {
				"value": float(held_values[hold_key]),
				"seconds": float(observation.hold_seconds),
			}
		if has_unavailable:
			var record_value: Variant = unavailable[hold_key]
			if not record_value is Dictionary:
				return {"invalid": true}
			var record: Dictionary = record_value
			var status_value: Variant = record.get("status")
			var reason_value: Variant = record.get("reason")
			if (
				not _nonempty_string(status_value)
				or status_value != "unavailable"
				or not _nonempty_string(reason_value)
				or str(reason_value).strip_edges() == ""
			):
				return {"invalid": true}
			return {"reason": "metric-unavailable"}
		return {"reason": "metric-not-found"}
	if not _finite_number(stored_value):
		return {"invalid": true}
	return {"value": float(stored_value), "seconds": float(row.window_seconds)}


static func _reduce_comparison_samples(samples: Array, aggregation: Dictionary) -> Dictionary:
	var by_beat := {}
	for sample_value in samples:
		var sample: Dictionary = sample_value
		var beat_id := str(sample.beat_id)
		if not by_beat.has(beat_id):
			by_beat[beat_id] = []
		by_beat[beat_id].append(sample)
	var beat_ids := by_beat.keys()
	beat_ids.sort()
	var beat_values := []
	var row_ids := {}
	for beat_id_value in beat_ids:
		var beat_samples: Array = by_beat[beat_id_value]
		beat_samples.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
			return str(first.row_id) < str(second.row_id)
		)
		var retained_seconds := 0.0
		for sample_value in beat_samples:
			var sample: Dictionary = sample_value
			row_ids[str(sample.row_id)] = true
			retained_seconds = maxf(retained_seconds, float(sample.seconds))
		beat_values.append({
			"value": _reduce_comparison_records(beat_samples, str(aggregation.row)),
			"seconds": retained_seconds,
		})
	var total_seconds := 0.0
	for beat_value in beat_values:
		var beat: Dictionary = beat_value
		total_seconds += float(beat.seconds)
	var sorted_row_ids := row_ids.keys()
	sorted_row_ids.sort()
	return {
		"value": _reduce_comparison_records(beat_values, str(aggregation.beat)),
		"retained_seconds": total_seconds,
		"beat_ids": beat_ids,
		"row_ids": sorted_row_ids,
	}


static func _reduce_comparison_records(records: Array, reducer: String) -> float:
	if reducer == "time_weighted_mean":
		var weighted_total := 0.0
		var total_seconds := 0.0
		for record_value in records:
			var record: Dictionary = record_value
			weighted_total += float(record.value) * float(record.seconds)
			total_seconds += float(record.seconds)
		if total_seconds <= 0.0:
			return 0.0
		return weighted_total / total_seconds
	var values := []
	for record_value in records:
		var record: Dictionary = record_value
		values.append(float(record.value))
	return _reduce_comparison_values(values, reducer)


static func _reduce_comparison_values(values: Array, reducer: String) -> float:
	var ordered := values.duplicate()
	ordered.sort()
	if reducer == "minimum":
		return float(ordered[0])
	if reducer == "maximum":
		return float(ordered[-1])
	return _median(ordered)


static func _build_target_finding(
	target: Dictionary, observation: Dictionary, branch: String, anchor: Dictionary,
	seed_results: Array, gap_count: int, observation_by_id: Dictionary, sources: Dictionary
) -> Dictionary:
	seed_results.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		return int(first.seed) < int(second.seed)
	)
	var seed_values := []
	var affected_misses := []
	var total_retained_seconds := 0.0
	for result_value in seed_results:
		var result: Dictionary = result_value
		seed_values.append(float(result.value))
		total_retained_seconds += float(result.retained_seconds)
		if result.status in ["under", "over"]:
			affected_misses.append(float(result.normalized_miss))
	var fleet_value := _reduce_comparison_values(seed_values, str(target.aggregation.seed))
	var normalized_median := 0.0
	if not affected_misses.is_empty():
		normalized_median = _reduce_comparison_values(affected_misses, "median")

	var primary_source_ids := _sorted_unique_strings([observation.source_id])
	var corroborating_source_ids := []
	for corroborating_id in observation.corroborating_observation_ids:
		var corroborating: Dictionary = observation_by_id[str(corroborating_id)]
		corroborating_source_ids.append(corroborating.source_id)
	corroborating_source_ids = _sorted_unique_strings(corroborating_source_ids)
	var provenance_source_ids := primary_source_ids.duplicate()
	provenance_source_ids.append_array(corroborating_source_ids)
	var caveats := []
	for source_id in provenance_source_ids:
		var source: Dictionary = sources[str(source_id)]
		caveats.append_array(source.caveats)
	caveats = _sorted_unique_strings(caveats)

	var target_range: Array = target.target_range
	return {
		"target_id": str(target.id),
		"observation_id": str(observation.id),
		"primary_source_ids": primary_source_ids,
		"corroborating_source_ids": corroborating_source_ids,
		"caveats": caveats,
		"transform_id": str(observation.transform_id),
		"semantic_selector_id": str(target.semantic_selector_id),
		"dimension": str(target.dimension),
		"metric": str(target.metric),
		"hold_seconds": target.hold_seconds,
		"resolved_branch": branch,
		"anchor": anchor.duplicate(true),
		"row_compatibility": str(observation.alignment.row_compatibility),
		"generated_row_selector": observation.alignment.generated_row_selector,
		"aggregation": target.aggregation.duplicate(true),
		"raw_range": target.raw_range.duplicate(true),
		"target_range": target_range.duplicate(true),
		"seed_results": seed_results,
		"fleet_value": fleet_value,
		"fleet_status": classify_value(fleet_value, target_range),
		"total_retained_seconds": total_retained_seconds,
		"affected_count": affected_misses.size(),
		"available_count": seed_results.size(),
		"gap_count": gap_count,
		"prevalence": float(affected_misses.size()) / float(CANONICAL_FLEET.size()),
		"normalized_median_miss": normalized_median,
		"observation_confidence": str(observation.confidence),
	}


static func _sorted_unique_strings(values: Array) -> Array:
	var seen := {}
	for value in values:
		seen[str(value)] = true
	var output := seen.keys()
	output.sort()
	return output


static func _comparison_recommendation(findings: Array) -> Dictionary:
	var eligible := []
	for finding_value in findings:
		var finding: Dictionary = finding_value
		if finding.observation_confidence in ["high", "medium"] and int(finding.affected_count) >= 8:
			eligible.append(finding)
	if eligible.is_empty():
		return {"status": "no-eligible-finding"}
	eligible.sort_custom(func(first: Dictionary, second: Dictionary) -> bool:
		if float(first.normalized_median_miss) != float(second.normalized_median_miss):
			return float(first.normalized_median_miss) > float(second.normalized_median_miss)
		if float(first.prevalence) != float(second.prevalence):
			return float(first.prevalence) > float(second.prevalence)
		if str(first.observation_confidence) != str(second.observation_confidence):
			return str(first.observation_confidence) == "high"
		return str(first.target_id) < str(second.target_id)
	)
	var selected: Dictionary = eligible[0]
	return {
		"status": "recommended",
		"target_id": str(selected.target_id),
		"normalized_median_miss": float(selected.normalized_median_miss),
		"prevalence": float(selected.prevalence),
		"confidence": str(selected.observation_confidence),
	}


static func _hold_window_samples(seconds: float) -> int:
	return ceili(seconds * Verify.SAMPLE_HZ - 1e-9) + 1


## One filtered band per native semantic role window, in compiled route order.
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
				"window_start_s": band.window_start_s,
				"window_end_s": band.window_end_s,
				"window_seconds": band.seconds,
				"loads": _load_metrics(band),
			})
		var pacing := _pacing_metrics(route, definition.first, definition.last)
		measured_beats.append({
			"beat_id": definition.beat_id,
			"story_slot_id": definition.story_slot_id,
			"window_role": definition.window_role,
			"occurrence": definition.occurrence,
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
		"schema_version": 2,
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
		"reconstruction": reconstruct_channels(route),
	}


## Raw, read-only reconstruction from the generated samples. Geometry is derived from position,
## while authored curvature and force channels remain separately labelled integrity references.
static func reconstruct_channels(route: Dictionary) -> Dictionary:
	var count: int = _validate_reconstruction_input(route)
	var distances: PackedFloat32Array = route.distances
	var times: PackedFloat32Array = route.times
	var positions: PackedVector3Array = route.positions

	var position_by_distance: Dictionary = _quadratic_vector_derivatives(distances, positions)
	var geometric_tangent := PackedVector3Array()
	geometric_tangent.resize(count)
	for index in count:
		var position_ds: Vector3 = position_by_distance.first[index]
		assert(position_ds.length_squared() > 0.0)
		geometric_tangent[index] = position_ds.normalized()

	var tangent_by_distance: Dictionary = _quadratic_vector_derivatives(
		distances, geometric_tangent
	)
	var curvature_vector: PackedVector3Array = tangent_by_distance.first
	var curvature := PackedFloat32Array()
	curvature.resize(count)
	var radius_m: Array = []
	var radius_unbounded: Array = []
	for index in count:
		var tangent: Vector3 = geometric_tangent[index]
		var raw_curvature: Vector3 = curvature_vector[index]
		var geometric_curvature: Vector3 = (
			raw_curvature - tangent * tangent.dot(raw_curvature)
		)
		curvature_vector[index] = geometric_curvature
		curvature[index] = geometric_curvature.length()
		if curvature[index] <= CURVATURE_ZERO_EPS:
			radius_m.append(null)
			radius_unbounded.append(true)
		else:
			radius_m.append(1.0 / curvature[index])
			radius_unbounded.append(false)

	var curvature_vector_derivatives: Dictionary = _quadratic_vector_derivatives(
		distances, curvature_vector
	)
	var curvature_derivatives: Dictionary = _quadratic_float_derivatives(distances, curvature)
	var authored_curvature_vector := PackedVector3Array(route.curvatures)
	var authored_curvature := PackedFloat32Array()
	authored_curvature.resize(count)
	var geometric_authored_error := PackedVector3Array()
	geometric_authored_error.resize(count)
	for index in count:
		authored_curvature[index] = authored_curvature_vector[index].length()
		geometric_authored_error[index] = (
			curvature_vector[index] - authored_curvature_vector[index]
		)
	var authored_vector_derivatives: Dictionary = _quadratic_vector_derivatives(
		distances, authored_curvature_vector
	)
	var authored_scalar_derivatives: Dictionary = _quadratic_float_derivatives(
		distances, authored_curvature
	)

	var position_by_time: Dictionary = _quadratic_vector_derivatives(times, positions)
	var inertial_acceleration: PackedVector3Array = position_by_time.second
	var jerk_derivatives: Dictionary = _quadratic_vector_derivatives(
		times, inertial_acceleration
	)
	var reconstructed_normal := PackedFloat32Array()
	var reconstructed_lateral := PackedFloat32Array()
	var reconstructed_longitudinal := PackedFloat32Array()
	var normal_error := PackedFloat32Array()
	var lateral_error := PackedFloat32Array()
	var longitudinal_error := PackedFloat32Array()
	var force_curvature_vector := PackedVector3Array()
	var force_authored_error := PackedVector3Array()
	reconstructed_normal.resize(count)
	reconstructed_lateral.resize(count)
	reconstructed_longitudinal.resize(count)
	normal_error.resize(count)
	lateral_error.resize(count)
	longitudinal_error.resize(count)
	force_curvature_vector.resize(count)
	force_authored_error.resize(count)
	var force_error_peak: float = 0.0
	var gravity: Vector3 = Vector3.DOWN * GRAVITY_MPS2
	for index in count:
		var tangent: Vector3 = route.tangents[index]
		var proper_acceleration: Vector3 = inertial_acceleration[index] - gravity
		reconstructed_normal[index] = proper_acceleration.dot(route.ups[index]) / GRAVITY_MPS2
		reconstructed_lateral[index] = proper_acceleration.dot(route.rights[index]) / GRAVITY_MPS2
		reconstructed_longitudinal[index] = proper_acceleration.dot(tangent) / GRAVITY_MPS2
		normal_error[index] = reconstructed_normal[index] - route.normal_g[index]
		lateral_error[index] = reconstructed_lateral[index] - route.lateral_g[index]
		longitudinal_error[index] = (
			reconstructed_longitudinal[index] - route.longitudinal_g[index]
		)
		force_error_peak = maxf(
			force_error_peak,
			maxf(
				absf(normal_error[index]),
				maxf(absf(lateral_error[index]), absf(longitudinal_error[index]))
			)
		)

		var authored_proper_acceleration: Vector3 = (
			route.ups[index] * route.normal_g[index]
			+ route.rights[index] * route.lateral_g[index]
			+ tangent * route.longitudinal_g[index]
		) * GRAVITY_MPS2
		var authored_inertial_acceleration: Vector3 = authored_proper_acceleration + gravity
		var transverse_acceleration: Vector3 = (
			authored_inertial_acceleration
			- tangent * tangent.dot(authored_inertial_acceleration)
		)
		var speed: float = route.speeds[index]
		assert(is_finite(speed) and speed > 0.0)
		var speed_squared := speed * speed
		force_curvature_vector[index] = transverse_acceleration / speed_squared
		force_authored_error[index] = (
			force_curvature_vector[index] - authored_curvature_vector[index]
		)

	var roll_derivatives: Dictionary = _quadratic_float_derivatives(times, route.roll_rates)
	var seam_indices: PackedInt32Array = _reconstruction_seam_indices(
		route.span_indices, count
	)
	return {
		"curvature_vector": curvature_vector,
		"curvature_vector_ds": curvature_vector_derivatives.first,
		"curvature_vector_d2s": curvature_vector_derivatives.second,
		"curvature": curvature,
		"curvature_ds": curvature_derivatives.first,
		"curvature_d2s": curvature_derivatives.second,
		"radius_m": radius_m,
		"radius_unbounded": radius_unbounded,
		"authored_curvature_vector": authored_curvature_vector,
		"authored_curvature_vector_ds": authored_vector_derivatives.first,
		"authored_curvature_vector_d2s": authored_vector_derivatives.second,
		"authored_curvature": authored_curvature,
		"authored_curvature_ds": authored_scalar_derivatives.first,
		"authored_curvature_d2s": authored_scalar_derivatives.second,
		"geometric_authored_curvature_error_vector": geometric_authored_error,
		"inertial_acceleration_mps2": inertial_acceleration,
		"jerk_mps3": jerk_derivatives.first,
		"reconstructed_normal_g": reconstructed_normal,
		"reconstructed_lateral_g": reconstructed_lateral,
		"reconstructed_longitudinal_g": reconstructed_longitudinal,
		"normal_force_error_g": normal_error,
		"lateral_force_error_g": lateral_error,
		"longitudinal_force_error_g": longitudinal_error,
		"force_error_peak_g": force_error_peak,
		"force_curvature_vector": force_curvature_vector,
		"force_authored_curvature_error_vector": force_authored_error,
		"roll_acceleration_dps2": roll_derivatives.first,
		"seam_indices": seam_indices,
		"seam_markers": _reconstruction_seam_markers(seam_indices, route),
	}


static func _validate_reconstruction_input(route: Dictionary) -> int:
	var count: int = route.positions.size()
	assert(count >= 3)
	for key in [
		"times", "distances", "speeds", "tangents", "ups", "rights", "curvatures",
		"normal_g", "lateral_g", "longitudinal_g", "roll_rates", "span_indices",
	]:
		assert(route[key].size() == count)
	for index in range(1, count):
		assert(route.distances[index] > route.distances[index - 1])
		assert(route.times[index] > route.times[index - 1])
	return count


static func _quadratic_vector_derivatives(
	coordinates: PackedFloat32Array, values: PackedVector3Array
) -> Dictionary:
	var first := PackedVector3Array()
	var second := PackedVector3Array()
	first.resize(values.size())
	second.resize(values.size())
	for index in values.size():
		var local: Vector3i = _quadratic_local_indices(index, values.size())
		var a: int = local.x
		var b: int = local.y
		var c: int = local.z
		var x: float = coordinates[index]
		var xa: float = coordinates[a]
		var xb: float = coordinates[b]
		var xc: float = coordinates[c]
		var slope_ab: Vector3 = (values[b] - values[a]) / (xb - xa)
		var slope_bc: Vector3 = (values[c] - values[b]) / (xc - xb)
		var second_divided_difference: Vector3 = (slope_bc - slope_ab) / (xc - xa)
		first[index] = slope_ab + second_divided_difference * (2.0 * x - xa - xb)
		second[index] = second_divided_difference * 2.0
	return {"first": first, "second": second}


static func _quadratic_float_derivatives(
	coordinates: PackedFloat32Array, values: PackedFloat32Array
) -> Dictionary:
	var first := PackedFloat32Array()
	var second := PackedFloat32Array()
	first.resize(values.size())
	second.resize(values.size())
	for index in values.size():
		var local: Vector3i = _quadratic_local_indices(index, values.size())
		var a: int = local.x
		var b: int = local.y
		var c: int = local.z
		var x: float = coordinates[index]
		var xa: float = coordinates[a]
		var xb: float = coordinates[b]
		var xc: float = coordinates[c]
		var slope_ab: float = (values[b] - values[a]) / (xb - xa)
		var slope_bc: float = (values[c] - values[b]) / (xc - xb)
		var second_divided_difference: float = (slope_bc - slope_ab) / (xc - xa)
		first[index] = slope_ab + second_divided_difference * (2.0 * x - xa - xb)
		second[index] = second_divided_difference * 2.0
	return {"first": first, "second": second}


static func _quadratic_local_indices(index: int, count: int) -> Vector3i:
	if index == 0:
		return Vector3i(0, 1, 2)
	if index == count - 1:
		return Vector3i(count - 3, count - 2, count - 1)
	return Vector3i(index - 1, index, index + 1)


static func _reconstruction_seam_indices(
	span_indices: PackedInt32Array, count: int
) -> PackedInt32Array:
	var seams := PackedInt32Array()
	for sample_index in range(1, count):
		if span_indices[sample_index] != span_indices[sample_index - 1]:
			seams.append(sample_index)
	return seams


static func _reconstruction_seam_markers(
	seam_indices: PackedInt32Array, route: Dictionary
) -> Array:
	var markers: Array = []
	var last: int = route.positions.size() - 1
	for sample_index in seam_indices:
		markers.append({
			"sample_index": sample_index,
			"time_s": float(route.times[sample_index]),
			"distance_m": float(route.distances[sample_index]),
			"window_start_index": maxi(sample_index - 2, 0),
			"window_end_index": mini(sample_index + 2, last),
		})
	return markers


static func _beat_definitions(route: Dictionary) -> Array:
	var beats := []
	for gesture_value in route.gesture_windows:
		var gesture: Dictionary = gesture_value
		for role_value in gesture.role_windows:
			var role: Dictionary = role_value
			var window_role := str(role.id)
			var kind := str(role.get("diagnostic_kind", window_role))
			if kind.is_empty():
				kind = window_role
			beats.append({
				"beat_id": str(role.window_id),
				"story_slot_id": str(gesture.story_slot_id),
				"window_role": window_role,
				"occurrence": int(role.occurrence),
				"kind": kind,
				"name": str(role.get("display_name", kind)),
				"first": int(role.first),
				"last": int(role.last),
			})
	return beats


static func _row_series(route: Dictionary, row_offset: float) -> Dictionary:
	var native := native_row_series(route, row_offset)
	return {
		"normal": Verify.filter(Verify.resample(route.times, native.normal_g)),
		"lateral": Verify.filter(Verify.resample(route.times, native.lateral_g)),
		"longitudinal": Verify.filter(Verify.resample(route.times, native.longitudinal_g)),
		"roll": Verify.filter(Verify.resample(route.times, native.roll_rate_dps)),
	}


## Native modeled forces for one train row, aligned one-for-one with route samples.
static func native_row_series(route: Dictionary, row_offset: float) -> Dictionary:
	var normal_g := PackedFloat32Array()
	var lateral_g := PackedFloat32Array()
	var longitudinal_g := PackedFloat32Array()
	var roll_rate_dps := PackedFloat32Array()
	if is_zero_approx(row_offset):
		normal_g = route.normal_g
		lateral_g = route.lateral_g
		longitudinal_g = route.longitudinal_g
		if route.has("roll_rates"):
			roll_rate_dps = route.roll_rates
		else:
			roll_rate_dps.resize(route.times.size())
			roll_rate_dps.fill(0.0)
	else:
		var count: int = route.times.size()
		normal_g.resize(count)
		lateral_g.resize(count)
		longitudinal_g.resize(count)
		roll_rate_dps.resize(count)
		for i in count:
			var forces: Dictionary = Verify.row_forces_at(
				route, route.distances[i], route.speeds[i], row_offset
			)
			normal_g[i] = forces.normal
			lateral_g[i] = forces.lateral
			longitudinal_g[i] = forces.longitudinal
			roll_rate_dps[i] = forces.roll_rate
	return {
		"normal_g": normal_g, "lateral_g": lateral_g,
		"longitudinal_g": longitudinal_g, "roll_rate_dps": roll_rate_dps,
	}


static func _bands_for_row(
	route: Dictionary, beats: Array, row_offset: float, series: Dictionary, include_short: bool
) -> Array:
	var normal: PackedFloat32Array = series.normal
	var lateral: PackedFloat32Array = series.lateral
	var longitudinal: PackedFloat32Array = series.longitudinal
	var roll: PackedFloat32Array = series.roll
	var bands := []
	var route_start_distance := float(route.distances[0])
	var route_end_distance := float(route.distances[-1])
	for beat_index in beats.size():
		var beat: Dictionary = beats[beat_index]
		var start_distance: float = route.distances[beat.first]
		var end_distance: float = route.distances[beat.last]
		var window_start := clampf(
			start_distance + row_offset, route_start_distance, route_end_distance
		)
		var window_end := clampf(
			end_distance + row_offset, route_start_distance, route_end_distance
		)
		var low_time: float = _value_at_coordinate(route.distances, route.times, window_start)
		var high_time: float = _value_at_coordinate(route.distances, route.times, window_end)
		if high_time <= low_time:
			continue
		# Adjacent beat windows are half-open; only a route-boundary window owns its endpoint.
		var include_end := is_equal_approx(window_end, route_end_distance)
		var band_normal := _sample_filtered_window(normal, low_time, high_time, include_end)
		if band_normal.size() < 5 and not include_short:
			continue
		if band_normal.is_empty():
			continue
		bands.append({
			"kind": beat.kind,
			"beat_id": beat.beat_id,
			"story_slot_id": beat.story_slot_id,
			"window_role": beat.window_role,
			"occurrence": beat.occurrence,
			"first": beat.first,
			"last": beat.last,
			"start_distance": route.distances[beat.first],
			"end_distance": route.distances[beat.last],
			"row_offset": row_offset,
			"window_start_distance": window_start,
			"window_end_distance": window_end,
			"window_start_s": low_time,
			"window_end_s": high_time,
			"seconds": high_time - low_time,
			"normal": band_normal,
			"lateral": _sample_filtered_window(lateral, low_time, high_time, include_end),
			"longitudinal": _sample_filtered_window(
				longitudinal, low_time, high_time, include_end
			),
			"roll": _sample_filtered_window(roll, low_time, high_time, include_end),
		})
	return bands


## Interpolate the globally filtered 100 Hz series onto a fresh grid anchored at the selected
## physical start. The half-open option gives each adjacent beat seam sample one owner.
static func _sample_filtered_window(
	values: PackedFloat32Array, start_s: float, end_s: float, include_end: bool
) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	if values.is_empty() or end_s < start_s:
		return output
	var available_end := (values.size() - 1) / Verify.SAMPLE_HZ
	var sample_end := minf(end_s, available_end)
	var count := floori(maxf(0.0, sample_end - start_s) * Verify.SAMPLE_HZ + 1e-7) + 1
	for index in count:
		var at := start_s + index / Verify.SAMPLE_HZ
		if at > sample_end + 1e-7:
			break
		if not include_end and at >= end_s - 1e-7:
			break
		var position := at * Verify.SAMPLE_HZ
		var low := clampi(floori(position), 0, values.size() - 1)
		var high := mini(low + 1, values.size() - 1)
		output.append(lerpf(values[low], values[high], position - low))
	return output


static func _value_at_coordinate(
	coordinates: PackedFloat32Array, values: PackedFloat32Array, at: float
) -> float:
	if at <= coordinates[0]:
		return values[0]
	if at >= coordinates[-1]:
		return values[-1]
	var low := 0
	var high := coordinates.size() - 1
	while low + 1 < high:
		var middle := floori((low + high) * 0.5)
		if coordinates[middle] <= at:
			low = middle
		else:
			high = middle
	return lerpf(values[low], values[high], inverse_lerp(coordinates[low], coordinates[high], at))


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
	var unavailable := {}
	var curve := Verify._held_curve(values, polarity)
	for seconds in HOLD_SECONDS:
		var key := _hold_key(seconds)
		var window := _hold_window_samples(seconds)
		if window > values.size():
			unavailable[key] = {
				"status": "unavailable",
				"reason": "insufficient_duration",
			}
		else:
			output[key] = curve[window] * polarity
	if not unavailable.is_empty():
		output["_unavailable"] = unavailable
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
	var measured_seconds := 0.0
	var dead_seconds := 0.0
	var speed_100_seconds := 0.0
	var speed_200_seconds := 0.0
	var flat_seconds := 0.0
	# Each interval is classified by its left endpoint, so every elapsed second is owned once.
	for i in range(first, last):
		var seconds: float = route.times[i + 1] - route.times[i]
		if seconds <= 0.0:
			continue
		measured_seconds += seconds
		if (
			route.normal_g[i] >= 0.75
			and route.normal_g[i] <= 1.25
			and absf(route.lateral_g[i]) <= 0.25
			and absf(route.longitudinal_g[i]) <= 0.25
		):
			dead_seconds += seconds
		if route.speeds[i] >= 100.0 / 3.6:
			speed_100_seconds += seconds
		if route.speeds[i] >= 200.0 / 3.6:
			speed_200_seconds += seconds
		if absf(_pitch_degrees(route.tangents[i])) <= 5.0 and absf(route.banks[i]) <= 5.0:
			flat_seconds += seconds
	var divisor := measured_seconds if measured_seconds > 0.0 else 1.0
	return {
		"duration": duration,
		"speed_loss": float(route.speeds[first] - route.speeds[last]),
		"average_speed": length / duration if duration > 0.0 else 0.0,
		"dead_zone_share": dead_seconds / divisor if measured_seconds > 0.0 else 0.0,
		"speed_share_100": speed_100_seconds / divisor if measured_seconds > 0.0 else 0.0,
		"speed_share_200": speed_200_seconds / divisor if measured_seconds > 0.0 else 0.0,
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
	var beat: Dictionary = definitions[beat_index]
	var output := {
		"flat_dwell": pacing.flat_seconds,
		"same_kind_adjacency": 0.0,
	}
	if beat_index + 1 >= definitions.size():
		output["status"] = "evidence-gap"
		output["reason"] = "terminal_beat"
		return output
	var next: Dictionary = definitions[beat_index + 1]
	output.same_kind_adjacency = 1.0 if beat.kind == next.kind else 0.0
	var seam_s: float = route.times[next.first]
	var before_start := seam_s - TRANSITION_WINDOW_SECONDS
	var after_end := seam_s + TRANSITION_WINDOW_SECONDS
	if before_start < route.times[0] - 1e-7 or after_end > route.times[-1] + 1e-7:
		output["status"] = "evidence-gap"
		output["reason"] = "boundary_unavailable"
		return output
	output["transition_before_s"] = [before_start, seam_s]
	output["transition_after_s"] = [seam_s, after_end]
	var swing := 0.0
	for values in [route.normal_g, route.lateral_g, route.longitudinal_g]:
		var before := _time_window_extrema(route.times, values, before_start, seam_s)
		var after := _time_window_extrema(route.times, values, seam_s, after_end)
		swing = maxf(
			swing,
			maxf(absf(before.maximum - after.minimum), absf(after.maximum - before.minimum))
		)
	output["transition_force_swing"] = swing
	output["transition_seconds"] = TRANSITION_WINDOW_SECONDS * 2.0
	output["bank_handoff"] = _seam_handoff(route.times, route.banks, seam_s)
	var roll_rates: PackedFloat32Array = route.get("roll_rates", PackedFloat32Array())
	output["roll_rate_handoff"] = (
		_seam_handoff(route.times, roll_rates, seam_s) if not roll_rates.is_empty() else 0.0
	)
	return output


static func _time_window_extrema(
	times: PackedFloat32Array, values: PackedFloat32Array, start_s: float, end_s: float
) -> Dictionary:
	# Transition windows are [start, end), so an adjacent seam sample is owned once.
	var minimum := _value_at_coordinate(times, values, start_s)
	var maximum := minimum
	for index in times.size():
		if times[index] <= start_s or times[index] >= end_s:
			continue
		minimum = minf(minimum, values[index])
		maximum = maxf(maximum, values[index])
	return {"minimum": minimum, "maximum": maximum}


static func _seam_handoff(
	times: PackedFloat32Array, values: PackedFloat32Array, seam_s: float
) -> float:
	var step := 1.0 / Verify.SAMPLE_HZ
	return absf(
		_value_at_coordinate(times, values, seam_s + step)
		- _value_at_coordinate(times, values, seam_s - step)
	)


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
		"roll_rate_handoff": 0.0,
		"flat_dwell": 0.0,
		"same_kind_adjacency": 0.0,
	}
	for beat in beats:
		for metric in output:
			if beat.flow.has(metric) and is_finite(float(beat.flow[metric])):
				output[metric] = maxf(output[metric], float(beat.flow[metric]))
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
	"raw_range", "target_range", "issues", "aggregation",
]


static func validate_catalog(catalog: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if typeof(catalog.get("schema_version")) != TYPE_INT or catalog.get("schema_version") != 2:
		errors.append("catalog schema version 2 is required")
	if not _nonempty_string(catalog.get("catalog_version")):
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
	if not value is Dictionary:
		errors.append("catalog %s must be a Dictionary" % key)
		return {}
	for collection_key in value:
		if not _nonempty_string(collection_key):
			errors.append("catalog %s has non-String id '%s'" % [key, collection_key])
	return value


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
			if (
				not _nonempty_string(legacy.get("phase"))
				or not _nonempty_string(legacy.get("kind"))
			):
				errors.append("selector '%s' has an incomplete legacy_anchor" % selector_id)
			if typeof(legacy.get("occurrence")) != TYPE_INT or int(legacy.get("occurrence", -1)) < 0:
				errors.append("selector '%s' has invalid legacy occurrence" % selector_id)
			if legacy.get("window_role") != "whole":
				errors.append("selector '%s' legacy window_role must be whole" % selector_id)
		var compiled: Variant = selector.get("compiled_anchor")
		if not compiled is Dictionary:
			errors.append("selector '%s' requires compiled_anchor" % selector_id)
		else:
			_reject_unknown_keys(compiled,
				["story_slot_id", "window_role", "kind", "occurrence", "window_id"],
				"selector '%s' compiled_anchor" % selector_id, errors)
			for key in ["story_slot_id", "window_role"]:
				if not compiled.has(key):
					errors.append("selector '%s' compiled_anchor is missing %s" % [selector_id, key])
			if (
				not _nonempty_string(compiled.get("story_slot_id"))
				or not _nonempty_string(compiled.get("window_role"))
			):
				errors.append("selector '%s' has an incomplete compiled_anchor" % selector_id)
			for key in ["kind", "window_id"]:
				if compiled.has(key) and not _nonempty_string(compiled[key]):
					errors.append("selector '%s' has invalid compiled %s" % [selector_id, key])
			if compiled.has("occurrence") and (typeof(compiled.occurrence) != TYPE_INT \
					or int(compiled.occurrence) < 0):
				errors.append("selector '%s' has invalid compiled occurrence" % selector_id)


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
		if not _nonempty_string(window.get("id")):
			errors.append("source '%s' has non-String window id '%s'" % [source_id, window_id])
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
		if not _nonempty_string(observation.get("id")):
			errors.append("observation %d has a non-String id '%s'" % [index, observation_id])
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
		if not _nonempty_string(observation.get("source_id")):
			errors.append("observation '%s' has a non-String source_id" % observation_id)
		if not _nonempty_string(observation.get("source_window_id")):
			errors.append("observation '%s' has a non-String source_window_id" % observation_id)
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
		if not _hold_seconds_is_emitted(hold_seconds):
			errors.append("observation '%s' hold_seconds must be exactly present in HOLD_SECONDS" % observation_id)
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
		if not _nonempty_string(target.get("id")):
			errors.append("target %d has a non-String id '%s'" % [index, target_id])
		_claim_id(target_id, "target", seen_ids, errors)
		if not _nonempty_string(target.get("observation_id")):
			errors.append("target '%s' has a non-String observation_id" % target_id)
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
		if str(target.get("metric", "")).contains("_held_") and not _hold_seconds_is_emitted(hold_seconds):
			errors.append("target '%s' hold_seconds must be exactly present in HOLD_SECONDS" % target_id)
		if not _ranges_close(target.get("raw_range"), observation.get("raw_range")):
			errors.append("target '%s' raw_range must match observation" % target_id)
		var expected_target := _transformed_range(observation, transforms)
		if expected_target.is_empty() or not _ranges_close(target.get("target_range"), expected_target):
			errors.append("target '%s' target_range must match the approved transform" % target_id)
		_validate_aggregation(target_id, target.get("aggregation"), errors)
		_validate_issues("target", target_id, target.get("issues"), errors)


static func _validate_aggregation(
	target_id: String, aggregation: Variant, errors: PackedStringArray
) -> void:
	if not aggregation is Dictionary:
		errors.append("target '%s' aggregation must be a Dictionary" % target_id)
		return
	_require_exact_keys(
		aggregation, ["row", "beat", "seed"], "target '%s' aggregation" % target_id, errors
	)
	if aggregation.get("row") not in ROW_BEAT_REDUCERS:
		errors.append("target '%s' aggregation has invalid row reducer" % target_id)
	if aggregation.get("beat") not in ROW_BEAT_REDUCERS:
		errors.append("target '%s' aggregation has invalid beat reducer" % target_id)
	if aggregation.get("seed") not in SEED_REDUCERS:
		errors.append("target '%s' aggregation has invalid seed reducer" % target_id)


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
		[
			"source_landmark_id", "generated_anchor", "method", "uncertainty_s",
			"row_compatibility", "generated_row_selector", "rationale",
		],
		"observation '%s' alignment" % observation_id,
		errors
	)
	var generated: Variant = alignment.get("generated_anchor")
	if not generated is Dictionary or generated.get("semantic_selector_id") != selector_id:
		errors.append("observation '%s' alignment has invalid generated_anchor" % observation_id)
	elif generated.size() != 1:
		errors.append("observation '%s' alignment generated_anchor has unsupported fields" % observation_id)
	if not _nonempty_string(alignment.get("source_landmark_id")) or not _nonempty_string(alignment.get("method")) or not _nonempty_string(alignment.get("rationale")):
		errors.append("observation '%s' has incomplete alignment" % observation_id)
	if not _nonnegative_number(alignment.get("uncertainty_s")):
		errors.append("observation '%s' alignment has invalid uncertainty_s" % observation_id)
	var compatibility: Variant = alignment.get("row_compatibility")
	var row_selector: Variant = alignment.get("generated_row_selector")
	if compatibility not in ["same-row", "explicit-row-transform", "row-independent"]:
		errors.append("observation '%s' alignment has invalid row_compatibility" % observation_id)
	elif compatibility == "row-independent":
		if row_selector != null:
			errors.append("observation '%s' alignment generated_row_selector must be null for row-independent evidence" % observation_id)
	elif not _valid_generated_row_selector(row_selector):
		errors.append("observation '%s' alignment has invalid generated_row_selector" % observation_id)


static func _valid_generated_row_selector(selector: Variant) -> bool:
	if not selector is Dictionary or selector.size() != 1:
		return false
	if selector.has("row_id"):
		return selector.row_id is String and str(selector.row_id).strip_edges() != ""
	if selector.has("position"):
		return selector.position in ["front", "intermediate", "rear"]
	if selector.has("offset"):
		return typeof(selector.offset) == TYPE_FLOAT and is_finite(float(selector.offset))
	return false


static func _hold_seconds_is_emitted(value: Variant) -> bool:
	if not _positive_number(value):
		return false
	for seconds in HOLD_SECONDS:
		if float(value) == float(seconds):
			return true
	return false


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
		if not _nonempty_string(record.get("id")):
			errors.append("%s record %d has a non-String id '%s'" % [key, index, record_id])
		_claim_id(record_id, key, seen_ids, errors)
		if not _nonempty_string(record.get("prompt", record.get("description"))):
			errors.append("%s '%s' is missing text" % [key, record_id])
		if key == "review_prompts" and not _nonempty_string(record.get("category")):
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
	var actual := CanonicalData.sha256_bytes(file.get_buffer(file.get_length()))
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
		if not _nonempty_string(referenced_id):
			errors.append("%s '%s' has a non-String %s entry" % [record_kind, record_id, key])
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


static func _nonempty_string(value: Variant) -> bool:
	return value is String and str(value) != ""


static func _positive_number(value: Variant) -> bool:
	return _finite_number(value) and float(value) > 0.0


static func _nonnegative_number(value: Variant) -> bool:
	return _finite_number(value) and float(value) >= 0.0


static func _number_close(value: Variant, expected: float) -> bool:
	return _finite_number(value) and is_equal_approx(float(value), expected)
