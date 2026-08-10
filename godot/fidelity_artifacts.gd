class_name RideFidelityArtifacts
extends RefCounted

const _CANONICAL_DATA = preload("res://canonical_data.gd")

const _DEEP_SEEDS := [11, 42, 20260809]
const _COMPARISON_KEYS := ["fleet", "findings", "observed_only", "evidence_gaps", "recommendation"]
const _PAIR_STEMS := ["artifact", "diagnostic", "metadata_artifact", "metadata_diagnostic", "review"]
const _CHECKLIST_SPECS := [
	["shaping", "Shaping"],
	["feel", "Feel"],
	["speed-perception", "Speed perception"],
	["terrain-clearance", "Terrain / clearance"],
	["support-overlap", "Support overlap"],
]
const _CATEGORY_IDS := {
	"shaping": "shaping", "element shaping": "shaping",
	"feel": "feel", "ride feel": "feel",
	"speed perception": "speed-perception",
	"terrain/clearance": "terrain-clearance",
	"support overlap": "support-overlap",
}
const _ISSUE_TEXT := {
	9: "Entry-launch speed", 12: "Flats",
	14: "Multidimensional scaling", 15: "Transition jerk",
}
const _SIDE_VIEW_KINDS := [
	"hill", "immelmann", "loop", "cutback", "twisted_drop",
	"dive", "wave_turn", "overbank", "turn",
]

static func build_report(
	seed_measurements: Variant,
	comparison: Variant,
	catalog: Variant,
	legacy_base_commit: Variant,
	generation_counts: Variant
) -> Dictionary:
	var errors: Array[String] = []
	_validate_base_commit(legacy_base_commit, errors)
	var comparison_projection := _validate_comparison(comparison, errors)
	var fleet: Array = comparison_projection.fleet
	var by_seed := _validate_measurements(seed_measurements, fleet, errors)
	var counts_projection := _validate_counts(generation_counts, fleet, errors)
	var catalog_context := _catalog_context(catalog, by_seed, comparison_projection, errors)
	var pov_map := {
		"schema_version": "fidelity-pov-map@1", "source_landmarks": catalog_context.source_landmarks,
		"records": catalog_context.pov_records, "gaps": catalog_context.pov_gaps,
	}
	var render_requests := _render_requests(by_seed, pov_map, errors)
	var catalog_text := _CANONICAL_DATA.canonical_json(catalog)
	if catalog_text.is_empty():
		errors.append("artifact_report: catalog canonical data is invalid")
	if not errors.is_empty():
		return _invalid(errors)

	var summaries := fleet.map(func(seed: int): return by_seed[seed])
	var report := {
		"schema_version": "ride-fidelity-audit@1", "legacy_base_commit": legacy_base_commit,
		"catalog": {
			"schema_version": catalog_context.identity.schema_version,
			"catalog_version": catalog_context.identity.catalog_version,
			"canonical_sha256": _CANONICAL_DATA.sha256_text(catalog_text), "validation_status": "valid",
		},
		"fleet": comparison_projection.fleet, "generation_counts": counts_projection,
		"measurement_summaries": summaries, "findings": comparison_projection.findings,
		"observed_only": comparison_projection.observed_only, "evidence_gaps": comparison_projection.evidence_gaps,
		"recommendation": comparison_projection.recommendation, "evidence_snapshot": catalog_context.evidence_snapshot,
		"pov_map": pov_map, "checklist": catalog_context.checklist, "issue_coverage": catalog_context.issue_coverage,
		"render_requests": render_requests,
	}
	if _CANONICAL_DATA.canonical_json(report).is_empty():
		errors.append("artifact_report: completed report is not canonical JSON data")
		return _invalid(errors)
	return report

static func canonical_json(value: Variant) -> String:
	return _CANONICAL_DATA.canonical_json(value)

static func _validate_base_commit(value: Variant, errors: Array[String]) -> void:
	if typeof(value) != TYPE_STRING:
		errors.append("artifact_report: legacy_base_commit must be lowercase 40-hex")
		return
	var commit: String = value
	if commit.length() != 40:
		errors.append("artifact_report: legacy_base_commit must be lowercase 40-hex")
		return
	for index in range(40):
		if not "0123456789abcdef".contains(commit[index]):
			errors.append("artifact_report: legacy_base_commit must be lowercase 40-hex")
			return

static func _validate_comparison(value: Variant, errors: Array[String]) -> Dictionary:
	var projection := {
		"fleet": [], "findings": [], "observed_only": [],
		"evidence_gaps": [], "recommendation": {},
	}
	if not value is Dictionary:
		errors.append("artifact_report: comparison must be a Dictionary")
		return projection
	var comparison: Dictionary = value
	var keys: Array = value.keys()
	var expected := _COMPARISON_KEYS.duplicate()
	keys.sort()
	expected.sort()
	if keys != expected:
		errors.append("artifact_report: comparison must have the exact Task 6 members")
	var fleet_value: Variant = comparison.get("fleet")
	var findings_value: Variant = comparison.get("findings")
	var observed_value: Variant = comparison.get("observed_only")
	var gaps_value: Variant = comparison.get("evidence_gaps")
	var recommendation_value: Variant = comparison.get("recommendation")
	if (not fleet_value is Array or not findings_value is Array
		or not observed_value is Array or not gaps_value is Array
		or not recommendation_value is Dictionary):
		errors.append("artifact_report: comparison members have invalid types")
		return projection
	projection.findings = findings_value.duplicate(true)
	projection.observed_only = observed_value.duplicate(true)
	projection.evidence_gaps = gaps_value.duplicate(true)
	projection.recommendation = recommendation_value.duplicate(true)
	var seen := {}
	var safe_fleet := []
	for seed_value in fleet_value:
		if typeof(seed_value) != TYPE_INT:
			errors.append("artifact_report: comparison fleet seeds must be integers")
		elif seen.has(seed_value):
			errors.append("artifact_report: comparison fleet seeds must be unique")
		else:
			seen[seed_value] = true
			safe_fleet.append(seed_value)
	projection["fleet"] = safe_fleet
	if _CANONICAL_DATA.canonical_json(projection).is_empty():
		errors.append("artifact_report: comparison projections must be canonical JSON data")
	return projection

static func _validate_measurements(value: Variant, fleet: Array, errors: Array[String]) -> Dictionary:
	var by_seed := {}
	var seen := {}
	if not value is Array:
		errors.append("artifact_report: seed_measurements must be an Array")
		return by_seed
	for item_value in value:
		if not item_value is Dictionary:
			errors.append("artifact_report: measurement entries must be Dictionaries")
			continue
		var item: Dictionary = item_value
		var entry_error_count := errors.size()
		var schema_version: Variant = item.get("schema_version")
		if typeof(schema_version) != TYPE_INT or schema_version not in [1, 2]:
			errors.append("artifact_report: measurement schema_version must be integer 1 or 2")
		var seed: Variant = item.get("seed")
		if typeof(seed) != TYPE_INT:
			errors.append("artifact_report: measurement seed must be an integer")
			continue
		if seen.has(seed):
			errors.append("artifact_report: duplicate measurement seed %s" % seed)
			continue
		seen[seed] = true
		var length: Variant = item.get("length")
		var duration: Variant = item.get("duration")
		if not _finite_number(length) or not _finite_number(duration):
			errors.append("artifact_report: measurement length and duration must be finite numbers")
		var dimensions: Variant = item.get("dimensions")
		var beats: Variant = item.get("beats")
		if not dimensions is Dictionary:
			errors.append("artifact_report: measurement dimensions must be a Dictionary")
		if not beats is Array:
			errors.append("artifact_report: measurement beats must be an Array")
		var reconstruction: Variant = item.get("reconstruction")
		if not reconstruction is Dictionary:
			errors.append("artifact_report: measurement reconstruction must be a Dictionary")
			continue
		var force_peak: Variant = reconstruction.get("force_error_peak_g")
		if not _finite_number(force_peak):
			errors.append("artifact_report: measurement force_error_peak_g must be finite numeric")
		var seams: Variant = reconstruction.get("seam_indices")
		if not (seams is Array or seams is PackedInt32Array):
			errors.append("artifact_report: measurement seam_indices must be an Array or PackedInt32Array")
		if not beats is Array or not dimensions is Dictionary:
			continue
		var beat_ids := {}
		for beat_value in beats:
			if not beat_value is Dictionary:
				errors.append("artifact_report: measurement beat must be a Dictionary")
				continue
			var beat: Dictionary = beat_value
			var beat_id := _required_string(beat, "beat_id", "measurement beat", errors)
			if beat_ids.has(beat_id):
				errors.append("artifact_report: duplicate measurement beat_id %s" % beat_id)
				continue
			if not beat_id.is_empty():
				beat_ids[beat_id] = true
			_required_string(beat, "kind", "measurement beat", errors)
		if errors.size() != entry_error_count:
			continue
		var summary := {
			"schema_version": schema_version, "seed": seed,
			"length": length, "duration": duration,
			"dimensions": dimensions.duplicate(true), "beats": beats.duplicate(true),
			"force_error_peak_g": force_peak, "reconstruction_seam_count": seams.size(),
		}
		if _CANONICAL_DATA.canonical_json(summary).is_empty():
			errors.append("artifact_report: measurement summary must contain finite canonical JSON data")
			continue
		by_seed[seed] = summary
	var actual_seeds: Array = seen.keys()
	var expected_seeds := fleet.duplicate()
	actual_seeds.sort()
	expected_seeds.sort()
	if actual_seeds != expected_seeds:
		errors.append("artifact_report: measurement seeds must exactly match comparison fleet")
	for seed in _DEEP_SEEDS:
		if not fleet.has(seed):
			errors.append("artifact_report: deep seed %d is required" % seed)
	return by_seed

static func _validate_counts(value: Variant, fleet: Array, errors: Array[String]) -> Dictionary:
	var projection := {}
	if not value is Dictionary:
		errors.append("artifact_report: generation_counts must be a Dictionary")
		return projection
	var counts: Dictionary = value
	for key_value in counts:
		if typeof(key_value) != TYPE_STRING:
			errors.append("artifact_report: generation_counts keys must be Strings")
			continue
		var key: String = key_value
		var count: Variant = counts[key]
		if typeof(count) != TYPE_INT:
			errors.append("artifact_report: generation_counts values must be integers")
		elif count != 1:
			errors.append("artifact_report: generation_counts must record exactly one generation per seed")
		else:
			projection[key] = count
	var expected_keys := []
	for seed in fleet:
		expected_keys.append(str(seed))
	var actual_keys: Array = projection.keys()
	actual_keys.sort()
	expected_keys.sort()
	if actual_keys != expected_keys:
		errors.append("artifact_report: generation_counts keys must exactly match the fleet")
	return projection

static func _catalog_context(
	value: Variant, by_seed: Dictionary, comparison: Dictionary, errors: Array[String]
) -> Dictionary:
	var context := {
		"identity": {"schema_version": 0, "catalog_version": ""},
		"evidence_snapshot": [], "source_landmarks": [], "source_times": {},
		"unaligned_candidates": {}, "pov_records": [], "pov_gaps": [],
		"checklist": [], "issue_coverage": {},
	}
	var checklist_rows := {}
	for spec in _CHECKLIST_SPECS:
		checklist_rows[spec[0]] = []
	var coverage_records := []
	for issue_id in range(1, 17):
		coverage_records.append({
			"issue_id": issue_id, "issue_text": _ISSUE_TEXT.get(issue_id, "Issue %d" % issue_id),
			"linked_measurement_ids": [], "linked_target_ids": [],
			"linked_evidence_ids": [], "generated_artifact_paths": [], "state": "evidence-gap",
		})
	if not value is Dictionary:
		errors.append("artifact_report: catalog must be a Dictionary")
		return context
	var catalog: Dictionary = value
	var schema_version: Variant = catalog.get("schema_version")
	var catalog_version := _required_string(catalog, "catalog_version", "catalog", errors)
	if typeof(schema_version) != TYPE_INT or schema_version != 2:
		errors.append("artifact_report: catalog schema_version must be integer 2")
	else:
		context.identity = {"schema_version": schema_version, "catalog_version": catalog_version}
	var sources_value: Variant = catalog.get("sources")
	var selectors_value: Variant = catalog.get("selectors")
	if not sources_value is Dictionary or not selectors_value is Dictionary:
		errors.append("artifact_report: catalog sources and selectors have invalid types")
		return context
	var sources: Dictionary = sources_value
	var selectors: Dictionary = selectors_value
	for source_id_value in sources:
		if typeof(source_id_value) != TYPE_STRING:
			errors.append("artifact_report: catalog source IDs must be nonempty Strings")
			continue
		var source_id: String = source_id_value
		if source_id.is_empty():
			errors.append("artifact_report: catalog source IDs must be nonempty Strings")
			continue
		_source_projection(source_id, sources[source_id], context, errors)
	context.evidence_snapshot.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a.source_id < b.source_id)
	context.source_landmarks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.source_id != b.source_id:
			return a.source_id < b.source_id
		return a.landmark_id < b.landmark_id)

	var finding_targets := {}
	for finding_value in comparison.findings:
		if finding_value is Dictionary:
			var target_id: Variant = finding_value.get("target_id")
			if typeof(target_id) == TYPE_STRING:
				finding_targets[target_id] = true
	var observation_sources := {}
	var compiled_anchors := {}
	for observation in _dictionary_records(catalog.get("observations"), "catalog observations", errors):
		var entry_errors := errors.size()
		var observation_id := _required_string(observation, "id", "observation", errors)
		var source_id := _required_string(observation, "source_id", "observation", errors)
		var selector_id := _required_string(observation, "semantic_selector_id", "observation", errors)
		if observation_id.is_empty() or observation_sources.has(observation_id):
			errors.append("artifact_report: observation IDs must be nonempty and unique")
			continue
		observation_sources[observation_id] = source_id
		if not sources.has(source_id):
			errors.append("artifact_report: observation source_id does not resolve: %s" % source_id)
		if not selectors.has(selector_id):
			errors.append("artifact_report: observation semantic_selector_id does not resolve: %s" % selector_id)
		if not observation.has("alignment"):
			continue
		var alignment_value: Variant = observation.get("alignment")
		if not alignment_value is Dictionary:
			errors.append("artifact_report: observation alignment must be a Dictionary")
			continue
		var alignment: Dictionary = alignment_value
		var landmark_id := _required_string(alignment, "source_landmark_id", "alignment", errors)
		var method := _required_string(alignment, "method", "alignment", errors)
		var row_compatibility := _required_string(alignment, "row_compatibility", "alignment", errors)
		var uncertainty: Variant = alignment.get("uncertainty_s")
		if not _finite_number(uncertainty):
			errors.append("artifact_report: alignment uncertainty_s must be finite numeric")
		var generated_anchor: Variant = alignment.get("generated_anchor")
		if not generated_anchor is Dictionary:
			errors.append("artifact_report: alignment generated_anchor must be a Dictionary")
		var landmark_key := "%s/%s" % [source_id, landmark_id]
		if not context.source_times.has(landmark_key):
			errors.append("artifact_report: source_landmark_id does not resolve: %s" % landmark_id)
		if selectors.has(selector_id) and not compiled_anchors.has(selector_id):
			var selector_value: Variant = selectors[selector_id]
			if not selector_value is Dictionary:
				errors.append("artifact_report: selector records must be Dictionaries")
			else:
				var selector: Dictionary = selector_value
				var anchor_value: Variant = selector.get("compiled_anchor")
				if not anchor_value is Dictionary:
					errors.append("artifact_report: selector compiled anchor must be a Dictionary")
				else:
					var anchor: Dictionary = anchor_value
					var story_slot := _required_string(anchor, "story_slot_id", "compiled anchor", errors)
					var window_role := _required_string(anchor, "window_role", "compiled anchor", errors)
					if not story_slot.is_empty() and not window_role.is_empty():
						compiled_anchors[selector_id] = {
							"story_slot_id": story_slot, "window_role": window_role,
						}
		if errors.size() != entry_errors or not by_seed.has(42) or not compiled_anchors.has(selector_id):
			continue
		var resolution := _center_row_resolution(by_seed[42], compiled_anchors[selector_id], errors)
		if resolution.is_empty():
			continue
		var generated_time := (float(resolution.window_start_s) + float(resolution.window_end_s)) * 0.5
		context.pov_records.append({
			"source_id": source_id, "source_landmark_id": landmark_id,
			"source_time": context.source_times[landmark_key], "observation_id": observation_id,
			"semantic_selector_id": selector_id, "alignment_method": method,
			"uncertainty_s": uncertainty, "row_compatibility": row_compatibility,
			"generated_seed": 42, "generated_anchor": generated_anchor.duplicate(true),
			"generated_beat_id": resolution.beat_id, "generated_time_s": generated_time,
			"generated_window_s": [resolution.window_start_s, resolution.window_end_s],
			"generated_pov_path": "review/seed-42/pov/%s.png" % resolution.beat_id,
		})
		context.unaligned_candidates.erase(source_id)

	for target in _dictionary_records(catalog.get("targets"), "catalog targets", errors):
		var target_id := _required_string(target, "id", "target", errors)
		var observation_id := _required_string(target, "observation_id", "target", errors)
		var selector_id := _required_string(target, "semantic_selector_id", "target", errors)
		var issues := _validated_issues(target.get("issues"), "target", errors)
		if not observation_sources.has(observation_id):
			errors.append("artifact_report: target observation_id does not resolve: %s" % target_id)
		if not selectors.has(selector_id):
			errors.append("artifact_report: target semantic_selector_id does not resolve: %s" % target_id)
		if not finding_targets.has(target_id) or not observation_sources.has(observation_id):
			continue
		for issue_id in issues:
			var record: Dictionary = coverage_records[issue_id - 1]
			record.state = "measured"
			record.linked_measurement_ids.append("seed-42")
			record.linked_target_ids.append(target_id)
			record.linked_evidence_ids.append_array([observation_id, observation_sources[observation_id]])
			record.generated_artifact_paths.append("review/seed-42/channels.png")

	for prompt in _dictionary_records(catalog.get("review_prompts"), "catalog review_prompts", errors):
		var prompt_id := _required_string(prompt, "id", "prompt", errors)
		var category := _required_string(prompt, "category", "prompt", errors)
		var prompt_text := _required_string(prompt, "prompt", "prompt", errors)
		var source_ids := _validated_source_ids(prompt.get("source_ids"), "prompt", sources, errors)
		var issues := _validated_issues(prompt.get("issues"), "prompt", errors)
		var category_id: String = _CATEGORY_IDS.get(category, "")
		if category_id.is_empty():
			errors.append("artifact_report: prompt has unknown checklist category")
		else:
			checklist_rows[category_id].append({
				"id": prompt_id, "prompt": prompt_text,
				"evidence_ids": _sorted_unique(source_ids),
				"generated_artifact_paths": ["review/seed-42/channels.png"],
			})
		for issue_id in issues:
			var record: Dictionary = coverage_records[issue_id - 1]
			if record.state == "measured":
				continue
			record.state = "review-prompt"
			record.linked_evidence_ids.append_array([prompt_id] + source_ids)
			record.generated_artifact_paths.append("review/seed-42/channels.png")

	for gap in _dictionary_records(catalog.get("evidence_gaps"), "catalog evidence_gaps", errors):
		var gap_id := _required_string(gap, "id", "gap", errors)
		_validated_source_ids(gap.get("source_ids"), "gap", sources, errors)
		for issue_id in _validated_issues(gap.get("issues"), "gap", errors):
			var record: Dictionary = coverage_records[issue_id - 1]
			if record.state == "evidence-gap":
				record.linked_evidence_ids.append(gap_id)

	for spec in _CHECKLIST_SPECS:
		var rows: Array = checklist_rows[spec[0]]
		if rows.is_empty():
			errors.append("artifact_report: checklist category %s is missing" % spec[0])
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
		context.checklist.append({"id": spec[0], "title": spec[1], "prompts": rows})
	for record in coverage_records:
		for field in ["linked_measurement_ids", "linked_target_ids",
			"linked_evidence_ids", "generated_artifact_paths"]:
			record[field] = _sorted_unique(record[field])
		if record.linked_evidence_ids.is_empty() and record.generated_artifact_paths.is_empty():
			errors.append("artifact_report: issue %d has no traceability links" % record.issue_id)
	context.issue_coverage = {"schema_version": "fidelity-issue-coverage@1", "records": coverage_records}
	context.pov_records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.source_id != b.source_id:
			return a.source_id < b.source_id
		if a.source_landmark_id != b.source_landmark_id:
			return a.source_landmark_id < b.source_landmark_id
		return a.observation_id < b.observation_id)
	context.pov_gaps = context.unaligned_candidates.values()
	context.pov_gaps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return context

static func _required_string(record: Dictionary, key: String, label: String, errors: Array[String]) -> String:
	var value: Variant = record.get(key)
	if typeof(value) == TYPE_STRING:
		var text: String = value
		if not text.is_empty():
			return text
	errors.append("artifact_report: %s %s must be a nonempty String" % [label, key])
	return ""

static func _dictionary_records(value: Variant, label: String, errors: Array[String]) -> Array:
	var output := []
	if not value is Array:
		errors.append("artifact_report: %s must be an Array" % label)
		return output
	for record_value in value:
		if not record_value is Dictionary:
			errors.append("artifact_report: %s entries must be Dictionaries" % label)
		else:
			output.append(record_value)
	return output

static func _validated_source_ids(
	value: Variant, label: String, sources: Dictionary, errors: Array[String]
) -> Array:
	var output := []
	if not value is Array:
		errors.append("artifact_report: %s source_ids must be an Array" % label)
		return output
	for source_id_value in value:
		if typeof(source_id_value) != TYPE_STRING:
			errors.append("artifact_report: %s source_ids must contain Strings" % label)
			continue
		var source_id: String = source_id_value
		output.append(source_id)
		if not sources.has(source_id):
			errors.append("artifact_report: %s source_id does not resolve: %s" % [label, source_id])
	return output

static func _validated_issues(value: Variant, label: String, errors: Array[String]) -> Array:
	var output := []
	if not value is Array:
		errors.append("artifact_report: %s issues must be an Array" % label)
		return output
	for issue_id in value:
		if typeof(issue_id) != TYPE_INT or issue_id < 1 or issue_id > 16:
			errors.append("artifact_report: %s issue ID must be an integer from 1 through 16" % label)
		else:
			output.append(issue_id)
	return output

static func _source_projection(
	source_id: String, value: Variant, context: Dictionary, errors: Array[String]
) -> void:
	if not value is Dictionary:
		errors.append("artifact_report: source records must be Dictionaries")
		return
	var source: Dictionary = value
	var snapshot := {"source_id": source_id, "state": _required_string(source, "state", "source", errors)}
	if source.has("acquisition"):
		snapshot["acquisition"] = _required_string(source, "acquisition", "source", errors)
	for stem in _PAIR_STEMS:
		var path_key := "%s_path" % stem
		if source.has(path_key):
			snapshot[path_key] = _required_string(source, path_key, "source", errors)
			var hash_key := "%s_sha256" % stem
			snapshot[hash_key] = _required_string(source, hash_key, "source", errors)
	if source.has("fallback_citations"):
		var citations: Variant = source.get("fallback_citations")
		if not citations is Array:
			errors.append("artifact_report: source fallback_citations must be an Array")
		else:
			snapshot["fallback_citations"] = citations.duplicate(true)
	context.evidence_snapshot.append(snapshot)
	var landmark_ids := []
	var windows: Variant = source.get("windows")
	if not windows is Array:
		errors.append("artifact_report: source windows must be an Array")
		return
	var seen := {}
	for landmark_value in windows:
		if not landmark_value is Dictionary:
			errors.append("artifact_report: source window entries must be Dictionaries")
			continue
		var landmark: Dictionary = landmark_value
		var landmark_id := _required_string(landmark, "id", "source landmark", errors)
		if landmark_id.is_empty() or seen.has(landmark_id):
			errors.append("artifact_report: source landmark IDs must be nonempty and unique")
			continue
		seen[landmark_id] = true
		var source_time := _source_time(landmark)
		if source_time.is_empty():
			errors.append("artifact_report: source landmark has invalid tagged time")
			continue
		landmark_ids.append(landmark_id)
		context.source_landmarks.append({
			"source_id": source_id, "landmark_id": landmark_id, "source_time": source_time,
		})
		context.source_times["%s/%s" % [source_id, landmark_id]] = source_time
	if source_id.begins_with("youtube.") and not landmark_ids.is_empty():
		landmark_ids.sort()
		context.unaligned_candidates[source_id] = {
			"id": "%s/alignment-not-present" % source_id, "source_id": source_id,
			"reason": "alignment-not-present", "source_landmark_ids": landmark_ids,
		}

static func _center_row_resolution(measurement: Dictionary, anchor: Dictionary, errors: Array[String]) -> Dictionary:
	var matches := []
	var duration: Variant = measurement.duration
	var beats: Array = measurement.beats
	for beat in beats:
		if beat.get("story_slot_id") != anchor.get("story_slot_id"):
			continue
		if beat.get("window_role") != anchor.get("window_role"):
			continue
		var rows_value: Variant = beat.get("rows")
		if not rows_value is Array:
			errors.append("artifact_report: measurement beat rows must be an Array")
			continue
		for row_value in rows_value:
			if not row_value is Dictionary:
				errors.append("artifact_report: measurement row must be a Dictionary")
				continue
			var row: Dictionary = row_value
			var offset: Variant = row.get("offset")
			if not _finite_number(offset):
				errors.append("artifact_report: measurement row offset must be finite numeric")
				continue
			if absf(float(offset)) > 0.000001:
				continue
			var window_start: Variant = row.get("window_start_s")
			var window_end: Variant = row.get("window_end_s")
			if not _finite_number(window_start) or not _finite_number(window_end):
				errors.append("artifact_report: measurement row window must be finite numeric")
				continue
			if float(window_start) < 0.0 or float(window_start) >= float(window_end) or float(window_end) > float(duration):
				errors.append("artifact_report: measurement row window must be ordered within duration")
				continue
			matches.append({
				"beat_id": beat.get("beat_id"), "window_start_s": window_start, "window_end_s": window_end,
			})
	if matches.size() != 1:
		errors.append("artifact_report: aligned observation must resolve exactly one center row")
		return {}
	return matches[0]

static func _source_time(landmark: Dictionary) -> Dictionary:
	if landmark.has("time_s") == landmark.has("window_s"):
		return {}
	if landmark.has("time_s"):
		var time: Variant = landmark.get("time_s")
		return {"kind": "point", "time_s": time} if _finite_number(time) else {}
	var window: Variant = landmark.get("window_s")
	if (not window is Array or window.size() != 2
		or not _finite_number(window[0]) or not _finite_number(window[1])):
		return {}
	return {"kind": "window", "window_s": [window[0], window[1]]}

static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(float(value)))

static func _render_requests(
	by_seed: Dictionary, pov_map: Dictionary, errors: Array[String]
) -> Array:
	var candidates: Array[Dictionary] = []
	for seed in _DEEP_SEEDS:
		for kind in ["channels", "elevation", "top"]:
			var path := "review/seed-%d/%s.png" % [seed, kind]
			candidates.append({"path": path, "seed": seed, "artifact_kind": kind})
	if by_seed.has(42):
		var seed_42: Dictionary = by_seed[42]
		for beat in seed_42.beats:
			if beat.kind not in _SIDE_VIEW_KINDS:
				continue
			var path := "review/seed-42/elements/%s.png" % beat.beat_id
			candidates.append({
				"path": path, "seed": 42, "artifact_kind": "element", "beat_id": beat.beat_id,
			})
	for record in pov_map.records:
		var path: String = record.generated_pov_path
		candidates.append({
			"path": path, "seed": 42, "artifact_kind": "pov",
			"beat_id": record.generated_beat_id, "generated_time_s": record.generated_time_s,
		})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.path < b.path)
	var output: Array[Dictionary] = []
	for candidate in candidates:
		if not output.is_empty() and output[-1].path == candidate.path:
			if output[-1] != candidate:
				errors.append("artifact_report: render request path has conflicting payload: %s" % candidate.path)
			continue
		output.append(candidate)
	return output

static func _sorted_unique(values: Array) -> Array:
	var seen := {}
	for value in values:
		seen[str(value)] = true
	var output: Array = seen.keys()
	output.sort()
	return output

static func _invalid(errors: Array[String]) -> Dictionary:
	return {"status": "invalid-input", "errors": _sorted_unique(errors)}

static func markdown(report: Dictionary) -> String:
	var lines := PackedStringArray(["# Ride fidelity audit", "", "## Identity"])
	lines.append("Schema: %s" % report.schema_version)
	lines.append("Legacy base: %s" % report.legacy_base_commit)
	lines.append("Catalog: %s (schema %s, %s)" % [
		report.catalog.catalog_version, report.catalog.schema_version, report.catalog.validation_status,
	])
	lines.append_array(["", "## Fleet"])
	var fleet := PackedStringArray()
	for seed in report.fleet:
		fleet.append(str(seed))
	lines.append(", ".join(fleet))
	lines.append_array(["", "## Measurements", "| seed | length | duration | force error | seams |",
		"| ---: | ---: | ---: | ---: | ---: |"])
	for measurement in report.measurement_summaries:
		lines.append(_markdown_row([
			measurement.seed, _f6(measurement.length), _f6(measurement.duration),
			_f6(measurement.force_error_peak_g), measurement.reconstruction_seam_count,
		]))
	lines.append_array(["", "## Findings", "| target | metric |", "| --- | --- |"])
	for finding in report.findings:
		lines.append(_markdown_row([finding.get("target_id", ""), finding.get("metric", "")]))
	lines.append_array(["", "## Observed only", "| observation | seed | value |",
		"| --- | ---: | ---: |"])
	for observed in report.observed_only:
		lines.append(_markdown_row([
			observed.get("observation_id", ""), observed.get("seed", ""),
			_f6(observed.get("value", 0.0)),
		]))
	lines.append_array(["", "## Evidence gaps", "| target | seed | reason |",
		"| --- | ---: | --- |"])
	for gap in report.evidence_gaps:
		lines.append(_markdown_row([
			gap.get("target_id", ""), gap.get("seed", ""), gap.get("reason", ""),
		]))
	lines.append_array(["", "## Recommendation"])
	var recommendation: Dictionary = report.recommendation
	var recommendation_text := str(recommendation.get("status", ""))
	if recommendation.has("target_id"):
		recommendation_text += ": %s" % recommendation.target_id
	lines.append(recommendation_text)
	lines.append_array(["", "## Evidence snapshot", "| source | state | acquisition |",
		"| --- | --- | --- |"])
	for snapshot in report.evidence_snapshot:
		lines.append(_markdown_row([
			snapshot.source_id, snapshot.state, snapshot.get("acquisition", ""),
		]))
	lines.append_array(["", "## POV map",
		"| source | landmark | observation | generated beat | source time |",
		"| --- | --- | --- | --- | --- |"])
	for record in report.pov_map.records:
		lines.append(_markdown_row([
			record.source_id, record.source_landmark_id, record.observation_id,
			record.generated_beat_id, _source_time_text(record.source_time),
		]))
	for gap in report.pov_map.gaps:
		lines.append("Gap: %s — %s (%s)" % [
			gap.source_id, gap.reason, ", ".join(PackedStringArray(gap.source_landmark_ids)),
		])
	lines.append_array(["", "## Checklist"])
	for section in report.checklist:
		lines.append("### %s" % section.title)
		for prompt in section.prompts:
			lines.append("- %s: %s [%s] -> %s" % [
				prompt.id, prompt.prompt, ", ".join(PackedStringArray(prompt.evidence_ids)),
				", ".join(PackedStringArray(prompt.generated_artifact_paths)),
			])
	lines.append_array(["", "## Issue coverage",
		"| issue | text | state | targets | evidence | artifacts |",
		"| ---: | --- | --- | --- | --- | --- |"])
	for record in report.issue_coverage.records:
		lines.append(_markdown_row([
			record.issue_id, record.issue_text, record.state,
			", ".join(PackedStringArray(record.linked_target_ids)),
			", ".join(PackedStringArray(record.linked_evidence_ids)),
			", ".join(PackedStringArray(record.generated_artifact_paths)),
		]))
	lines.append_array(["", "## Render requests", "| path | kind | seed | beat |",
		"| --- | --- | ---: | --- |"])
	for request in report.render_requests:
		lines.append(_markdown_row([
			request.path, request.artifact_kind, request.seed, request.get("beat_id", ""),
		]))
	return "\n".join(lines) + "\n"

static func _source_time_text(source_time: Dictionary) -> String:
	if source_time.kind == "point":
		return "point %s" % _f6(source_time.time_s)
	return "window %s–%s" % [_f6(source_time.window_s[0]), _f6(source_time.window_s[1])]

static func _f6(value: Variant) -> String:
	var number := float(value)
	if number == 0.0:
		number = 0.0
	return "%.6f" % number

static func _markdown_row(cells: Array) -> String:
	var text := PackedStringArray()
	for cell in cells:
		text.append(str(cell))
	return "| %s |" % " | ".join(text)
