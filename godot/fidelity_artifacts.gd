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

static func build_report(
	seed_measurements: Variant,
	comparison: Variant,
	catalog: Variant,
	legacy_base_commit: Variant,
	generation_counts: Variant
) -> Dictionary:
	var errors: Array[String] = []
	_validate_base_commit(legacy_base_commit, errors)
	var fleet := _validate_comparison(comparison, errors)
	var measurement_context := _validate_measurements(seed_measurements, fleet, errors)
	_validate_counts(generation_counts, fleet, errors)
	var context := _catalog_context(catalog, measurement_context.get("by_seed", {}), errors)
	var coverage := _issue_coverage(comparison, context, errors)
	if not errors.is_empty():
		return _invalid(errors)
	var summaries := []
	for seed in fleet:
		summaries.append(measurement_context.summaries[seed])
	var report := {
		"schema_version": "ride-fidelity-audit@1", "legacy_base_commit": legacy_base_commit,
		"catalog": {
			"schema_version": catalog.schema_version, "catalog_version": catalog.catalog_version,
			"canonical_sha256": catalog.canonical_sha256, "validation_status": "valid",
		},
		"fleet": fleet, "measurement_summaries": summaries,
		"findings": comparison.findings, "observed_only": comparison.observed_only,
		"evidence_gaps": comparison.evidence_gaps, "recommendation": comparison.recommendation,
		"evidence_snapshot": _evidence_snapshot(catalog),
		"pov_map": _pov_map(catalog, context),
		"checklist": _checklist(context.prompts),
		"issue_coverage": coverage,
	}
	report["render_requests"] = _render_requests(measurement_context.by_seed, report.pov_map)
	if _CANONICAL_DATA.canonical_json(report).is_empty():
		errors.append("artifact_report: completed report is not canonical JSON data")
		return _invalid(errors)
	return report
static func canonical_json(value: Variant) -> String:
	return _CANONICAL_DATA.canonical_json(value)
static func _validate_base_commit(value: Variant, errors: Array[String]) -> void:
	if typeof(value) != TYPE_STRING or value.length() != 40:
		errors.append("artifact_report: legacy_base_commit must be lowercase 40-hex")
		return
	for index in range(40):
		if not "0123456789abcdef".contains(value[index]):
			errors.append("artifact_report: legacy_base_commit must be lowercase 40-hex")
			return
static func _validate_comparison(value: Variant, errors: Array[String]) -> Array:
	if not value is Dictionary:
		errors.append("artifact_report: comparison must be a Dictionary")
		return []
	var keys: Array = value.keys()
	var expected := _COMPARISON_KEYS.duplicate()
	keys.sort()
	expected.sort()
	if keys != expected:
		errors.append("artifact_report: comparison must have the exact Task 6 members")
	var types_are_valid := (
		value.get("fleet") is Array
		and value.get("findings") is Array
		and value.get("observed_only") is Array
		and value.get("evidence_gaps") is Array
		and value.get("recommendation") is Dictionary
	)
	if not types_are_valid:
		errors.append("artifact_report: comparison members have invalid types")
		return []
	var fleet: Array = value.fleet
	var seen := {}
	for seed in fleet:
		if typeof(seed) != TYPE_INT:
			errors.append("artifact_report: comparison fleet seeds must be integers")
		elif seen.has(seed):
			errors.append("artifact_report: comparison fleet seeds must be unique")
		else:
			seen[seed] = true
	if _CANONICAL_DATA.canonical_json(value).is_empty():
		errors.append("artifact_report: comparison projections must be canonical JSON data")
	return fleet
static func _validate_measurements(value: Variant, fleet: Array, errors: Array[String]) -> Dictionary:
	var by_seed := {}
	var summaries := {}
	if not value is Array:
		errors.append("artifact_report: seed_measurements must be an Array")
		return {"by_seed": by_seed, "summaries": summaries}
	for item in value:
		if not item is Dictionary:
			errors.append("artifact_report: measurement entries must be Dictionaries")
			continue
		var seed: Variant = item.get("seed")
		if typeof(seed) != TYPE_INT:
			errors.append("artifact_report: measurement seed must be an integer")
			continue
		if by_seed.has(seed):
			errors.append("artifact_report: duplicate measurement seed %s" % seed)
			continue
		by_seed[seed] = item
		var reconstruction: Variant = item.get("reconstruction")
		if not reconstruction is Dictionary:
			errors.append("artifact_report: measurement reconstruction is invalid")
			continue
		var seams: Variant = reconstruction.get("seam_indices")
		if not (seams is Array or seams is PackedInt32Array):
			errors.append("artifact_report: measurement reconstruction is invalid")
			continue
		var summary := {
			"schema_version": item.get("schema_version"), "seed": seed,
			"length": item.get("length"), "duration": item.get("duration"),
			"dimensions": item.get("dimensions"), "beats": item.get("beats"),
			"force_error_peak_g": reconstruction.get("force_error_peak_g"),
			"reconstruction_seam_count": seams.size(),
		}
		if _CANONICAL_DATA.canonical_json(summary).is_empty():
			errors.append("artifact_report: measurement summary must contain finite canonical JSON data")
			continue
		summaries[seed] = summary
	var actual_seeds: Array = by_seed.keys()
	var expected_seeds := fleet.duplicate()
	actual_seeds.sort()
	expected_seeds.sort()
	if actual_seeds != expected_seeds:
		errors.append("artifact_report: measurement seeds must exactly match comparison fleet")
	for seed in _DEEP_SEEDS:
		if not fleet.has(seed):
			errors.append("artifact_report: deep seed %d is required" % seed)
	return {"by_seed": by_seed, "summaries": summaries}
static func _validate_counts(value: Variant, fleet: Array, errors: Array[String]) -> void:
	if not value is Dictionary:
		errors.append("artifact_report: generation_counts must be a Dictionary")
		return
	var actual := {}
	for key in value:
		if typeof(key) != TYPE_STRING:
			errors.append("artifact_report: generation_counts keys must be Strings")
			continue
		actual[key] = true
		if typeof(value[key]) != TYPE_INT:
			errors.append("artifact_report: generation_counts values must be integers")
		elif value[key] != 1:
			errors.append("artifact_report: generation_counts must record exactly one generation per seed")
	var expected := {}
	for seed in fleet:
		expected[str(seed)] = true
	var actual_keys: Array = actual.keys()
	var expected_keys: Array = expected.keys()
	actual_keys.sort()
	expected_keys.sort()
	if actual_keys != expected_keys:
		errors.append("artifact_report: generation_counts keys must exactly match the fleet")
static func _catalog_context(value: Variant, by_seed: Dictionary, errors: Array[String]) -> Dictionary:
	var context := {
		"observations": [], "observation_by_id": {}, "targets": [], "prompts": [],
		"gaps": [], "resolutions": {}, "aligned_sources": {},
	}
	if not value is Dictionary:
		errors.append("artifact_report: catalog must be a Dictionary")
		return context
	var sources_value: Variant = value.get("sources")
	var selectors_value: Variant = value.get("selectors")
	var observations_value: Variant = value.get("observations")
	var targets_value: Variant = value.get("targets")
	var prompts_value: Variant = value.get("review_prompts")
	var gaps_value: Variant = value.get("evidence_gaps")
	if not sources_value is Dictionary or not selectors_value is Dictionary:
		errors.append("artifact_report: catalog sources and selectors have invalid types")
		return context
	if not observations_value is Array or not targets_value is Array:
		errors.append("artifact_report: catalog comparison links have invalid types")
		return context
	if not prompts_value is Array or not gaps_value is Array:
		errors.append("artifact_report: catalog review links have invalid types")
		return context
	var sources: Dictionary = sources_value
	var selectors: Dictionary = selectors_value
	var observations: Array = observations_value
	var targets: Array = targets_value
	var prompts: Array = prompts_value
	var gaps: Array = gaps_value
	context.observations = observations
	context.targets = targets
	context.prompts = prompts
	context.gaps = gaps
	var observation_by_id := {}
	context.observation_by_id = observation_by_id
	for observation in observations:
		var observation_id := str(observation.get("id", ""))
		if observation_id.is_empty() or observation_by_id.has(observation_id):
			errors.append("artifact_report: observation IDs must be nonempty and unique")
		else:
			observation_by_id[observation_id] = observation
		var source_id := str(observation.get("source_id", ""))
		var selector_id := str(observation.get("semantic_selector_id", ""))
		if not sources.has(source_id):
			errors.append("artifact_report: observation source_id does not resolve: %s" % source_id)
		if not selectors.has(selector_id):
			errors.append("artifact_report: observation semantic_selector_id does not resolve: %s" % selector_id)
		if observation.has("alignment") and observation.alignment is Dictionary:
			context.aligned_sources[source_id] = true
			if sources.has(source_id) and selectors.has(selector_id) and by_seed.has(42):
				_resolve_alignment(observation, sources[source_id], selectors[selector_id],
					by_seed[42], context.resolutions, errors)
	for target in targets:
		if not observation_by_id.has(str(target.get("observation_id", ""))):
			errors.append("artifact_report: target observation_id does not resolve: %s" % target.get("id", ""))
		if not selectors.has(str(target.get("semantic_selector_id", ""))):
			errors.append("artifact_report: target semantic_selector_id does not resolve: %s" % target.get("id", ""))
		_validate_issues(target, "target", errors)
	var category_ids := {}
	for prompt in prompts:
		for source_id in prompt.source_ids:
			if not sources.has(source_id):
				errors.append("artifact_report: prompt source_id does not resolve: %s" % source_id)
		_validate_issues(prompt, "prompt", errors)
		var category_id: String = _CATEGORY_IDS.get(str(prompt.get("category", "")), "")
		if category_id.is_empty():
			errors.append("artifact_report: prompt has unknown checklist category")
		else:
			category_ids[category_id] = true
	for gap in gaps:
		for source_id in gap.source_ids:
			if not sources.has(source_id):
				errors.append("artifact_report: gap source_id does not resolve: %s" % source_id)
		_validate_issues(gap, "gap", errors)
	for spec in _CHECKLIST_SPECS:
		if not category_ids.has(spec[0]):
			errors.append("artifact_report: checklist category %s is missing" % spec[0])
	for source_id in sources:
		var seen_landmarks := {}
		for landmark in sources[source_id].get("windows", []):
			var landmark_id := str(landmark.get("id", ""))
			if landmark_id.is_empty() or seen_landmarks.has(landmark_id):
				errors.append("artifact_report: source landmark IDs must be nonempty and unique")
			seen_landmarks[landmark_id] = true
			if _source_time(landmark).is_empty():
				errors.append("artifact_report: source landmark has invalid tagged time")
	return context
static func _validate_issues(record: Dictionary, label: String, errors: Array[String]) -> void:
	var issues: Variant = record.get("issues")
	if not issues is Array:
		errors.append("artifact_report: %s issues must be an Array" % label)
		return
	for issue_id in issues:
		if typeof(issue_id) != TYPE_INT or issue_id < 1 or issue_id > 16:
			errors.append("artifact_report: %s issue ID must be an integer from 1 through 16" % label)
static func _resolve_alignment(
	observation: Dictionary,
	source: Dictionary,
	selector: Dictionary,
	measurement: Dictionary,
	resolutions: Dictionary,
	errors: Array[String]
) -> void:
	var alignment: Dictionary = observation.alignment
	var landmark_id := str(alignment.get("source_landmark_id", ""))
	var landmark_found := false
	for landmark in source.get("windows", []):
		if landmark is Dictionary and str(landmark.get("id", "")) == landmark_id:
			landmark_found = true
			break
	if not landmark_found:
		errors.append("artifact_report: source_landmark_id does not resolve: %s" % landmark_id)
	var anchor: Dictionary = selector.compiled_anchor
	var row_selector: Dictionary = alignment.generated_row_selector
	var matches := []
	for beat in measurement.get("beats", []):
		if not beat is Dictionary:
			continue
		if beat.get("story_slot_id") != anchor.get("story_slot_id"):
			continue
		if beat.get("window_role") != anchor.get("window_role"):
			continue
		for row in beat.get("rows", []):
			if row is Dictionary and row.get("row_id") == row_selector.get("row_id"):
				matches.append({"beat": beat, "row": row})
	if matches.size() != 1:
		errors.append("artifact_report: aligned observation must resolve exactly one center row")
		return
	resolutions[str(observation.get("id", ""))] = matches[0]
static func _source_time(landmark: Dictionary) -> Dictionary:
	if landmark.has("time_s") == landmark.has("window_s"):
		return {}
	if landmark.has("time_s"):
		return {"kind": "point", "time_s": landmark.time_s} if _finite_number(landmark.time_s) else {}
	var window: Variant = landmark.window_s
	if not window is Array or window.size() != 2:
		return {}
	return {"kind": "window", "window_s": window} if (
		_finite_number(window[0]) and _finite_number(window[1])) else {}
static func _finite_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(float(value)))
static func _evidence_snapshot(catalog: Dictionary) -> Array:
	var output := []
	var source_ids: Array = catalog.sources.keys()
	source_ids.sort()
	for source_id in source_ids:
		var source: Dictionary = catalog.sources[source_id]
		var snapshot := {"source_id": source_id, "state": source.get("state")}
		if source.has("acquisition"):
			snapshot["acquisition"] = source.acquisition
		for stem in _PAIR_STEMS:
			var path_key := "%s_path" % stem
			if source.has(path_key):
				snapshot[path_key] = source[path_key]
				snapshot["%s_sha256" % stem] = source.get("%s_sha256" % stem)
		if source.has("fallback_citations"):
			snapshot["fallback_citations"] = source.fallback_citations
		output.append(snapshot)
	return output
static func _pov_map(catalog: Dictionary, context: Dictionary) -> Dictionary:
	var landmarks := []
	var landmark_by_key := {}
	var gaps := []
	for source_id in catalog.sources:
		var source: Dictionary = catalog.sources[source_id]
		var landmark_ids := []
		for landmark in source.get("windows", []):
			var row := {
				"source_id": source_id, "landmark_id": landmark.id,
				"source_time": _source_time(landmark),
			}
			landmarks.append(row)
			landmark_ids.append(str(landmark.id))
			landmark_by_key["%s/%s" % [source_id, landmark.id]] = landmark
		if str(source_id).begins_with("youtube.") and not landmark_ids.is_empty():
			if not context.aligned_sources.has(source_id):
				landmark_ids.sort()
				gaps.append({
					"id": "%s/alignment-not-present" % source_id, "source_id": source_id,
					"reason": "alignment-not-present", "source_landmark_ids": landmark_ids,
				})
	landmarks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.source_id != b.source_id:
			return a.source_id < b.source_id
		return a.landmark_id < b.landmark_id)
	var records := []
	for observation in context.observations:
		var observation_id := str(observation.get("id", ""))
		if not observation.has("alignment") or not context.resolutions.has(observation_id):
			continue
		var alignment: Dictionary = observation.alignment
		var source_id := str(observation.source_id)
		var landmark_id := str(alignment.source_landmark_id)
		var resolved: Dictionary = context.resolutions[observation_id]
		var beat: Dictionary = resolved.beat
		var row: Dictionary = resolved.row
		records.append({
			"source_id": source_id, "source_landmark_id": landmark_id,
			"source_time": _source_time(landmark_by_key["%s/%s" % [source_id, landmark_id]]),
			"observation_id": observation_id, "semantic_selector_id": observation.semantic_selector_id,
			"alignment_method": alignment.get("method"), "uncertainty_s": alignment.get("uncertainty_s"),
			"row_compatibility": alignment.get("row_compatibility"), "generated_seed": 42,
			"generated_anchor": alignment.get("generated_anchor"), "generated_beat_id": beat.beat_id,
			"generated_window_s": [row.window_start_s, row.window_end_s],
			"generated_pov_path": "review/seed-42/pov/%s.png" % beat.beat_id,
		})
	records.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a.source_id != b.source_id:
			return a.source_id < b.source_id
		if a.source_landmark_id != b.source_landmark_id:
			return a.source_landmark_id < b.source_landmark_id
		return a.observation_id < b.observation_id)
	gaps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
	return {"schema_version": "fidelity-pov-map@1", "source_landmarks": landmarks,
		"records": records, "gaps": gaps}
static func _checklist(prompts: Array) -> Array:
	var by_category := {}
	for spec in _CHECKLIST_SPECS:
		by_category[spec[0]] = []
	for prompt in prompts:
		var category_id: String = _CATEGORY_IDS.get(str(prompt.category), "")
		if not category_id.is_empty():
			by_category[category_id].append({
				"id": prompt.id, "prompt": prompt.prompt,
				"evidence_ids": _sorted_unique(prompt.source_ids),
				"generated_artifact_paths": ["review/seed-42/channels.png"],
			})
	var output := []
	for spec in _CHECKLIST_SPECS:
		var rows: Array = by_category[spec[0]]
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)
		output.append({"id": spec[0], "title": spec[1], "prompts": rows})
	return output
static func _issue_coverage(
	comparison: Variant,
	context: Dictionary,
	errors: Array[String]
) -> Dictionary:
	var records := []
	if not comparison is Dictionary:
		return {"schema_version": "fidelity-issue-coverage@1", "records": records}
	var finding_targets := {}
	if comparison.get("findings") is Array:
		for finding in comparison.findings:
			if finding is Dictionary:
				finding_targets[str(finding.get("target_id", ""))] = true
	for issue_id in range(1, 17):
		var measured_measurements := []
		var measured_targets := []
		var measured_evidence := []
		var measured_artifacts := []
		for target in context.targets:
			if issue_id not in target.get("issues", []):
				continue
			var target_id := str(target.get("id", ""))
			if not finding_targets.has(target_id):
				continue
			measured_measurements.append("seed-42")
			measured_targets.append(target_id)
			var observation_id := str(target.get("observation_id", ""))
			measured_evidence.append(observation_id)
			if context.observation_by_id.has(observation_id):
				measured_evidence.append(str(context.observation_by_id[observation_id].source_id))
			measured_artifacts.append("review/seed-42/channels.png")
		var prompt_evidence := []
		var prompt_artifacts := []
		for prompt in context.prompts:
			if issue_id in prompt.get("issues", []):
				prompt_evidence.append(str(prompt.id))
				prompt_evidence.append_array(prompt.get("source_ids", []))
				prompt_artifacts.append("review/seed-42/channels.png")
		var gap_evidence := []
		for gap in context.gaps:
			if issue_id in gap.get("issues", []):
				gap_evidence.append(str(gap.id))
		if measured_targets.is_empty() and prompt_evidence.is_empty() and gap_evidence.is_empty():
			errors.append("artifact_report: issue %d has no traceability links" % issue_id)
		var record := {
			"issue_id": issue_id, "issue_text": _ISSUE_TEXT.get(issue_id, "Issue %d" % issue_id),
			"linked_measurement_ids": [], "linked_target_ids": [],
			"linked_evidence_ids": [], "generated_artifact_paths": [],
			"state": "evidence-gap",
		}
		if not measured_targets.is_empty():
			record.state = "measured"
			record.linked_measurement_ids = _sorted_unique(measured_measurements)
			record.linked_target_ids = _sorted_unique(measured_targets)
			record.linked_evidence_ids = _sorted_unique(measured_evidence)
			record.generated_artifact_paths = _sorted_unique(measured_artifacts)
		elif not prompt_evidence.is_empty():
			record.state = "review-prompt"
			record.linked_evidence_ids = _sorted_unique(prompt_evidence)
			record.generated_artifact_paths = _sorted_unique(prompt_artifacts)
		else:
			record.linked_evidence_ids = _sorted_unique(gap_evidence)
		records.append(record)
	return {"schema_version": "fidelity-issue-coverage@1", "records": records}
static func _render_requests(by_seed: Dictionary, pov_map: Dictionary) -> Array:
	var by_path := {}
	for seed in _DEEP_SEEDS:
		for kind in ["channels", "elevation", "top"]:
			var path := "review/seed-%d/%s.png" % [seed, kind]
			by_path[path] = {"path": path, "seed": seed, "artifact_kind": kind}
	for beat in by_seed[42].beats:
		var path := "review/seed-42/elements/%s.png" % beat.beat_id
		by_path[path] = {"path": path, "seed": 42, "artifact_kind": "element", "beat_id": beat.beat_id}
	for record in pov_map.records:
		var path: String = record.generated_pov_path
		by_path[path] = {"path": path, "seed": 42, "artifact_kind": "pov",
			"beat_id": record.generated_beat_id}
	var paths: Array = by_path.keys()
	paths.sort()
	var output := []
	for path in paths:
		output.append(by_path[path])
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
