class_name RideFidelityArtifacts
extends RefCounted

const _CANONICAL_DATA = preload("res://canonical_data.gd")
const _FIDELITY = preload("res://fidelity.gd")
const _TERRAIN = preload("res://terrain.gd")
const _SAMPLING = preload("res://route_sampling.gd")

## Eleven ordered strips, in the order the legend and the stacked image both publish them.
const _CHANNEL_SPECS := [
	["speed_kmh", "Speed", "km/h"],
	["normal_g", "Normal proper acceleration", "g"],
	["lateral_g", "Lateral proper acceleration", "g"],
	["longitudinal_proper_g", "Longitudinal proper acceleration", "g"],
	["pitch_deg", "Pitch", "deg"],
	["roll_rate_dps", "Roll rate", "deg/s"],
	["agl_m", "Height above ground", "m"],
	["reconstructed_curvature_inv_m", "Reconstructed curvature", "1/m"],
	["radius_m", "Radius", "m"],
	["roll_acceleration_dps2", "Roll acceleration", "deg/s^2"],
	["jerk_mps3", "Inertial jerk magnitude", "m/s^3"],
]
const _TRACE_RGBA := [0.55, 0.95, 1.0, 1.0]
const _TRACE_COLOR := Color(0.55, 0.95, 1.0)
const _CHANNEL_WIDTH := 1400
const _STRIP_HEIGHT := 150
const _PLOT_SIZE := Vector2i(1100, 700)
const _PLOT_MARGIN := 40.0
const _POV_SIZE := Vector2i(1440, 900)
const _POV_FOV_DEG := 72.0
const _POV_NEAR_M := 0.08
const _POV_FAR_M := 5000.0
const _POV_EYE_UP_M := 0.35
const _POV_ROW_ID := "row-04"
const _POV_ROW_OFFSET_M := 6.45
const _OVERLAY_SIZE := Vector2i(1200, 900)
const _OVERLAY_LEFT := 50
const _OVERLAY_RIGHT := 1149
const _OVERLAY_SOURCE_COLOR := Color(0.55, 0.95, 1.0)
const _OVERLAY_TARGET_COLOR := Color(0.95, 0.75, 0.35)
const _OVERLAY_GENERATED_COLOR := Color(0.95, 0.55, 0.95)
const _OVERLAY_MARKER_COLOR := Color(0.75, 0.62, 0.25)

const _DEEP_SEEDS := _FIDELITY.DEEP_SEEDS
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
## The sixteen legacy issue ids the audit covers, with the titles docs/ISSUES.md §12 gives them
## (that table is the one source; VC-010 tracks replacing these ids with the VC-* register).
const ISSUE_TEXT := {
	1: "Missing micro-elements",
	2: "Cheated pacing / near-zero-loss coasting",
	3: "Underused G envelope",
	4: "Oversmoothing",
	5: "Poor FVD implementation",
	6: "Poor terrain awareness",
	7: "Supports / poor shaping",
	8: "Poor speed sense",
	9: "Launch speed low",
	10: "Bank → flat → bank",
	11: "Leisurely ride",
	12: "Flats",
	13: "Tame airtime",
	14: "Scale / geometry wrong",
	15: "Jerky transitions",
	16: "Nebulous feel gaps",
}
const _SIDE_VIEW_KINDS := [
	"hill", "immelmann", "loop", "cutback", "twisted_drop",
	"dive", "wave_turn", "overbank", "turn", "slow-crest",
	"rise", "crest", "fall", "commit", "vertical-entry", "pullout", "exit",
]

static func build_report(
	seed_measurements: Variant,
	comparison: Variant,
	catalog: Variant,
	legacy_base_commit: Variant,
	generation_counts: Variant,
	include_generated_povs: bool = false
) -> Dictionary:
	var errors: Array[String] = []
	_validate_base_commit(legacy_base_commit, errors)
	var comparison_projection := _validate_comparison(comparison, errors)
	var fleet: Array = comparison_projection.fleet
	var by_seed := _validate_measurements(seed_measurements, fleet, errors)
	var counts_projection := _validate_counts(generation_counts, fleet, errors)
	var catalog_projectable := false
	if not catalog is Dictionary:
		errors.append("artifact_report: catalog must be a Dictionary")
	else:
		var catalog_errors := _FIDELITY.validate_catalog(catalog)
		catalog_projectable = catalog_errors.is_empty()
		for error in catalog_errors:
			errors.append("artifact_report: %s" % error)
	if not catalog_projectable:
		return _invalid(errors)
	var catalog_context := _catalog_context(catalog, by_seed, comparison_projection, errors)
	var pov_map := {
		"schema_version": "fidelity-pov-map@1", "source_landmarks": catalog_context.source_landmarks,
		"records": catalog_context.pov_records, "gaps": catalog_context.pov_gaps,
	}
	var render_requests := _render_requests(by_seed, pov_map, errors, include_generated_povs)
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
		"catalog_evidence_gaps": catalog_context.catalog_evidence_gaps,
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


## Every artifact write is verified by reopening it; a failed write is operational, never advisory.
static func write_text_checked(path: String, content: String) -> PackedStringArray:
	var errors := PackedStringArray()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		errors.append("artifact_write: cannot open '%s': %s" % [
			path, error_string(FileAccess.get_open_error())])
		return errors
	file.store_string(content)
	file.close()
	if FileAccess.get_file_as_string(path) != content:
		errors.append("artifact_write: byte verification failed for '%s'" % path)
	return errors


static func save_png_checked(image: Image, path: String) -> PackedStringArray:
	var error := image.save_png(path)
	if error == OK and FileAccess.file_exists(path):
		var reopened := Image.new()
		if reopened.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK \
				and reopened.get_width() == image.get_width() \
				and reopened.get_height() == image.get_height():
			return PackedStringArray()
		return PackedStringArray(["artifact_write: '%s' did not reopen as a PNG" % path])
	return PackedStringArray(["artifact_write: PNG failed '%s' (%s)" % [path, error_string(error)]])

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
	if comparison.size() != _COMPARISON_KEYS.size() or not comparison.has_all(_COMPARISON_KEYS):
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
			if schema_version == 2:
				_required_string(beat, "story_slot_id", "schema-2 measurement beat", errors)
				_required_string(beat, "window_role", "schema-2 measurement beat", errors)
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
	catalog: Dictionary, by_seed: Dictionary, comparison: Dictionary, errors: Array[String]
) -> Dictionary:
	var context := {
		"identity": {
			"schema_version": catalog.schema_version, "catalog_version": catalog.catalog_version,
		},
		"evidence_snapshot": [], "source_landmarks": [], "source_times": {},
		"unaligned_candidates": {}, "pov_records": [], "pov_gaps": [],
		"checklist": [], "issue_coverage": {}, "catalog_evidence_gaps": [],
	}
	var checklist_rows := {}
	for spec in _CHECKLIST_SPECS:
		checklist_rows[spec[0]] = []
	var coverage_records := []
	for issue_id in range(1, 17):
		coverage_records.append({
			"issue_id": issue_id, "issue_text": ISSUE_TEXT[issue_id],
			"linked_measurement_ids": [], "linked_target_ids": [],
			"linked_evidence_ids": [], "generated_artifact_paths": [], "state": "evidence-gap",
		})
	var sources: Dictionary = catalog.sources
	var selectors: Dictionary = catalog.selectors
	for source_id_value in sources:
		var source_id: String = source_id_value
		var source: Dictionary = sources[source_id]
		_source_projection(source_id, source, context)
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
	for observation_value in catalog.observations:
		var observation: Dictionary = observation_value
		var observation_id: String = observation.id
		var source_id: String = observation.source_id
		var selector_id: String = observation.semantic_selector_id
		observation_sources[observation_id] = source_id
		var alignment: Dictionary = observation.alignment
		var landmark_id: String = alignment.source_landmark_id
		var landmark_key := "%s/%s" % [source_id, landmark_id]
		if not compiled_anchors.has(selector_id):
			var anchor: Dictionary = selectors[selector_id].compiled_anchor
			compiled_anchors[selector_id] = anchor.duplicate(true)
		if not by_seed.has(42):
			continue
		var resolution := _center_row_resolution(by_seed[42], compiled_anchors[selector_id], errors)
		if resolution.is_empty():
			continue
		var generated_time := (float(resolution.window_start_s) + float(resolution.window_end_s)) * 0.5
		context.pov_records.append({
			"source_id": source_id, "source_landmark_id": landmark_id,
			"source_time": context.source_times[landmark_key].duplicate(true), "observation_id": observation_id,
			"semantic_selector_id": selector_id, "alignment_method": alignment.method,
			"uncertainty_s": alignment.uncertainty_s,
			"row_compatibility": alignment.row_compatibility,
			"generated_seed": 42, "generated_anchor": {"semantic_selector_id": selector_id},
			"generated_beat_id": resolution.beat_id, "generated_time_s": generated_time,
			"generated_window_s": [resolution.window_start_s, resolution.window_end_s],
			"row_id": resolution.row_id, "row_offset_m": resolution.row_offset_m,
			"generated_pov_path": "review/seed-42/pov/%s.png" % resolution.beat_id.replace("/", "__"),
		})
		context.unaligned_candidates.erase(source_id)

	for target_value in catalog.targets:
		var target: Dictionary = target_value
		var target_id: String = target.id
		var observation_id: String = target.observation_id
		if not finding_targets.has(target_id):
			continue
		for issue_id in target.issues:
			var record: Dictionary = coverage_records[issue_id - 1]
			record.state = "measured"
			record.linked_measurement_ids.append("seed-42")
			record.linked_target_ids.append(target_id)
			record.linked_evidence_ids.append_array([observation_id, observation_sources[observation_id]])
			record.generated_artifact_paths.append("review/seed-42/channels.png")

	for prompt_value in catalog.review_prompts:
		var prompt: Dictionary = prompt_value
		var source_ids: Array = prompt.source_ids
		var category_id: String = _CATEGORY_IDS.get(prompt.category, "")
		if category_id.is_empty():
			errors.append("artifact_report: prompt has unknown checklist category")
		else:
			checklist_rows[category_id].append({
				"id": prompt.id, "prompt": prompt.prompt,
				"evidence_ids": _sorted_unique(source_ids),
				"generated_artifact_paths": ["review/seed-42/channels.png"],
			})
		for issue_id in prompt.issues:
			var record: Dictionary = coverage_records[issue_id - 1]
			if record.state == "measured":
				continue
			record.state = "review-prompt"
			record.linked_evidence_ids.append_array([prompt.id] + source_ids)
			record.generated_artifact_paths.append("review/seed-42/channels.png")

	## A declared gap is published whatever else covers its issues: a measured target or a review
	## prompt narrows a gap, it does not retire the catalogued statement that no band exists.
	for gap_value in catalog.evidence_gaps:
		var gap: Dictionary = gap_value
		context.catalog_evidence_gaps.append({
			"id": gap.id, "description": gap.description,
			"source_ids": gap.source_ids.duplicate(true), "issues": gap.issues.duplicate(true),
		})
		for issue_id in gap.issues:
			var record: Dictionary = coverage_records[issue_id - 1]
			record.linked_evidence_ids.append(gap.id)
	context.catalog_evidence_gaps.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a.id < b.id)

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

static func _source_projection(
	source_id: String, source: Dictionary, context: Dictionary
) -> void:
	var snapshot := {"source_id": source_id, "state": source.state}
	if source.has("acquisition"):
		snapshot["acquisition"] = source.acquisition
	for stem in _PAIR_STEMS:
		var path_key := "%s_path" % stem
		if source.has(path_key):
			snapshot[path_key] = source[path_key]
			var hash_key := "%s_sha256" % stem
			snapshot[hash_key] = source[hash_key]
	if source.has("fallback_citations"):
		snapshot["fallback_citations"] = source.fallback_citations.duplicate(true)
	context.evidence_snapshot.append(snapshot)
	var landmark_ids := []
	for landmark_value in source.windows:
		var landmark: Dictionary = landmark_value
		var landmark_id: String = landmark.id
		var source_time := _source_time(landmark)
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
		if not _FIDELITY._matches_compiled_anchor(beat, anchor):
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
			if row.get("row_id") != _POV_ROW_ID \
					or absf(float(offset) - _POV_ROW_OFFSET_M) > 0.000001:
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
				"beat_id": beat.get("beat_id"), "window_start_s": window_start,
				"window_end_s": window_end, "row_id": row.row_id,
				"row_offset_m": float(offset),
			})
	if matches.size() != 1:
		errors.append("artifact_report: aligned observation must resolve exactly one row-04")
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
	by_seed: Dictionary, pov_map: Dictionary, errors: Array[String], include_generated_povs: bool
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
			var escaped: String = beat.beat_id.replace("/", "__")
			var path := "review/seed-42/elements/%s.png" % escaped
			candidates.append({
				"path": path, "seed": 42, "artifact_kind": "element", "beat_id": beat.beat_id,
			})
			if include_generated_povs:
				var centers := []
				var rows_value: Variant = beat.get("rows")
				if rows_value is Array:
					for row_value in rows_value:
						if not row_value is Dictionary:
							continue
						var row: Dictionary = row_value
						if row.get("row_id") != _POV_ROW_ID \
								or not _finite_number(row.get("offset")) \
								or absf(float(row.offset) - _POV_ROW_OFFSET_M) > 0.000001:
							continue
						if (_finite_number(row.get("window_start_s"))
							and _finite_number(row.get("window_end_s"))
							and float(row.window_start_s) >= 0.0
							and float(row.window_start_s) < float(row.window_end_s)
							and float(row.window_end_s) <= float(seed_42.duration)):
							centers.append(row)
				if centers.size() != 1:
					errors.append("artifact_report: midpoint POV requires exactly one row-04: %s" % beat.beat_id)
					continue
				candidates.append({"path": "review/seed-42/pov/%s.png" % escaped,
					"seed": 42, "artifact_kind": "pov", "beat_id": beat.beat_id,
					"row_id": centers[0].row_id, "row_offset_m": float(centers[0].offset),
					"generated_time_s": (float(centers[0].window_start_s)
						+ float(centers[0].window_end_s)) * 0.5})
	for record in pov_map.records:
		var path: String = record.generated_pov_path
		candidates.append({
			"path": path, "seed": 42, "artifact_kind": "pov",
			"beat_id": record.generated_beat_id, "generated_time_s": record.generated_time_s,
			"row_id": record.row_id, "row_offset_m": record.row_offset_m,
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
	lines.append_array(["", "## Catalog evidence gaps", "| gap | issues | sources | description |",
		"| --- | --- | --- | --- |"])
	for gap in report.catalog_evidence_gaps:
		lines.append(_markdown_row([
			gap.id, ", ".join(PackedStringArray(gap.issues.map(func(issue): return str(issue)))),
			", ".join(PackedStringArray(gap.source_ids)), gap.description,
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
	lines.append_array(["", "## POV map"])
	lines.append_array(_pov_map_lines(report.pov_map))
	lines.append_array(["", "## Checklist"])
	lines.append_array(_checklist_lines(report.checklist))
	lines.append_array(["", "## Issue coverage"])
	lines.append_array(_issue_coverage_lines(report.issue_coverage))
	lines.append_array(["", "## Render requests", "| path | kind | seed | beat |",
		"| --- | --- | ---: | --- |"])
	for request in report.render_requests:
		lines.append(_markdown_row([
			request.path, request.artifact_kind, request.seed, request.get("beat_id", ""),
		]))
	return "\n".join(lines) + "\n"

## One body per review projection, shared by the aggregate audit and its standalone file.
static func _pov_map_lines(pov_map: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray([
		"| source | landmark | observation | generated beat | source time |",
		"| --- | --- | --- | --- | --- |"])
	for record in pov_map.records:
		lines.append(_markdown_row([
			record.source_id, record.source_landmark_id, record.observation_id,
			record.generated_beat_id, _source_time_text(record.source_time),
		]))
	for gap in pov_map.gaps:
		lines.append("Gap: %s — %s (%s)" % [
			gap.source_id, gap.reason, ", ".join(PackedStringArray(gap.source_landmark_ids)),
		])
	return lines


static func _checklist_lines(checklist: Array) -> PackedStringArray:
	var lines := PackedStringArray()
	for section in checklist:
		lines.append("### %s" % section.title)
		for prompt in section.prompts:
			lines.append("- %s: %s [%s] -> %s" % [
				prompt.id, prompt.prompt, ", ".join(PackedStringArray(prompt.evidence_ids)),
				", ".join(PackedStringArray(prompt.generated_artifact_paths)),
			])
	return lines


static func _issue_coverage_lines(issue_coverage: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray([
		"| issue | text | state | targets | evidence | artifacts |",
		"| ---: | --- | --- | --- | --- | --- |"])
	for record in issue_coverage.records:
		lines.append(_markdown_row([
			record.issue_id, record.issue_text, record.state,
			", ".join(PackedStringArray(record.linked_target_ids)),
			", ".join(PackedStringArray(record.linked_evidence_ids)),
			", ".join(PackedStringArray(record.generated_artifact_paths)),
		]))
	return lines


static func _standalone(title: String, body: PackedStringArray) -> String:
	return "# %s\n\n%s\n" % [title, "\n".join(body)]


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


## One shared descriptor per channel feeds both the stacked image and the legend record, so the
## plotted extent a reviewer reads is by construction the extent that was drawn.
static func channels(route: Dictionary) -> Dictionary:
	var descriptors := _channel_descriptors(route)
	var strips := []
	for descriptor in descriptors:
		strips.append(descriptor.strip)
	return {"image": _channels_image(route, descriptors), "strips": strips}


static func _channel_descriptors(route: Dictionary) -> Array:
	var columns := _channel_columns(route)
	var descriptors := []
	for index in _CHANNEL_SPECS.size():
		var spec: Array = _CHANNEL_SPECS[index]
		var values: Array = columns[index]
		var low := INF
		var high := -INF
		var bounded := 0
		for value in values:
			if not _finite_number(value):
				continue
			bounded += 1
			low = minf(low, float(value))
			high = maxf(high, float(value))
		if bounded == 0:
			low = 0.0
			high = 1.0
		elif high == low:
			high = low + 0.001
		descriptors.append({"values": values, "strip": {
			"index": index, "channel_id": spec[0], "label": spec[1], "unit": spec[2],
			"plot_min": low, "plot_max": high, "bounded_count": bounded,
			"unbounded_count": values.size() - bounded,
			"series": [{"role": "raw_generated", "color_rgba": _TRACE_RGBA.duplicate()}],
		}})
	return descriptors


## Raw generated samples plus the contracted reconstruction; nothing here is filtered or refitted.
static func _channel_columns(route: Dictionary) -> Array:
	var reconstruction: Dictionary = _FIDELITY.reconstruct_channels(route)
	var speed := []
	var pitch := []
	var agl := []
	var jerk := []
	for index in route.positions.size():
		var position: Vector3 = route.positions[index]
		speed.append(float(route.speeds[index]) * 3.6)
		pitch.append(rad_to_deg(asin(clampf(route.tangents[index].y, -1.0, 1.0))))
		agl.append(position.y - _TERRAIN.height(route.terrain, position.x, position.z))
		jerk.append(reconstruction.jerk_mps3[index].length())
	return [
		speed, Array(route.normal_g), Array(route.lateral_g), Array(route.longitudinal_g),
		pitch, Array(route.roll_rates), agl, Array(reconstruction.curvature),
		reconstruction.radius_m, Array(reconstruction.roll_acceleration_dps2), jerk,
	]


static func _channels_image(route: Dictionary, descriptors: Array) -> Image:
	var times: PackedFloat32Array = route.times
	var duration := maxf(float(times[-1]), 0.000001)
	var image := Image.create(
		_CHANNEL_WIDTH, _STRIP_HEIGHT * descriptors.size(), false, Image.FORMAT_RGB8
	)
	image.fill(Color(0.09, 0.10, 0.12))
	for strip_index in descriptors.size():
		var strip: Dictionary = descriptors[strip_index].strip
		var values: Array = descriptors[strip_index].values
		var low: float = strip.plot_min
		var span: float = maxf(float(strip.plot_max) - low, 0.000001)
		var top := strip_index * _STRIP_HEIGHT
		var bounds := Rect2i(
			Vector2i(0, top + 1), Vector2i(_CHANNEL_WIDTH - 1, _STRIP_HEIGHT - 2)
		)
		for x in _CHANNEL_WIDTH:
			image.set_pixel(x, top, Color(0.25, 0.25, 0.30))
		if low < 0.0 and float(strip.plot_max) > 0.0:
			var zero_y := top + _STRIP_HEIGHT - 8 - int(-low / span * (_STRIP_HEIGHT - 16))
			for x in range(0, _CHANNEL_WIDTH, 2):
				image.set_pixel(x, clampi(zero_y, top + 1, top + _STRIP_HEIGHT - 1), Color(0.28, 0.24, 0.24))
		for gesture in route.get("gesture_windows", []):
			var marks := [float(gesture.start_time_s)]
			for window in gesture.get("role_windows", []):
				if not marks.has(float(window.start_time_s)):
					marks.append(float(window.start_time_s))
			for start_time in marks:
				var mark := clampi(int(start_time / duration * (_CHANNEL_WIDTH - 1)),
					0, _CHANNEL_WIDTH - 1)
				for y in range(top, top + _STRIP_HEIGHT, 4):
					image.set_pixel(mark, y, Color(0.30, 0.27, 0.20))
		for index in range(1, values.size()):
			if not _finite_number(values[index]) or not _finite_number(values[index - 1]):
				continue
			_draw_line(image,
				_strip_point(float(times[index - 1]), duration, float(values[index - 1]), low, span, top),
				_strip_point(float(times[index]), duration, float(values[index]), low, span, top),
				_TRACE_COLOR, bounds)
	return image


static func _strip_point(
	at: float, duration: float, value: float, low: float, span: float, top: int
) -> Vector2:
	return Vector2(
		at / duration * (_CHANNEL_WIDTH - 1),
		top + _STRIP_HEIGHT - 8 - (value - low) / span * (_STRIP_HEIGHT - 16)
	)


static func top_image(route: Dictionary) -> Image:
	var points := PackedVector2Array()
	for position in route.positions:
		points.append(Vector2(position.x, position.z))
	return _plot_image(points)


static func elevation_image(route: Dictionary) -> Image:
	var points := PackedVector2Array()
	for index in route.positions.size():
		points.append(Vector2(route.distances[index], route.positions[index].y))
	return _plot_image(points)


## The inspector's per-element side view: the span flattened onto its own dominant ground heading.
static func side_image(route: Dictionary, first: int, last: int) -> Image:
	var origin: Vector3 = route.positions[first]
	var heading := Vector2.ZERO
	for index in range(first, last + 1):
		heading += Vector2(route.positions[index].x - origin.x, route.positions[index].z - origin.z)
	if heading.length() < 1.0:
		heading = Vector2(route.tangents[first].x, route.tangents[first].z)
	heading = heading.normalized()
	var points := PackedVector2Array()
	for index in range(first, last + 1):
		var position: Vector3 = route.positions[index]
		points.append(Vector2(
			Vector2(position.x - origin.x, position.z - origin.z).dot(heading), position.y
		))
	return _plot_image(points)


static func _plot_image(points: PackedVector2Array) -> Image:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in points:
		low = low.min(point)
		high = high.max(point)
	var span: Vector2 = (high - low).max(Vector2.ONE)
	var scale := minf(
		(_PLOT_SIZE.x - 2.0 * _PLOT_MARGIN) / span.x, (_PLOT_SIZE.y - 2.0 * _PLOT_MARGIN) / span.y
	)
	var image := Image.create(_PLOT_SIZE.x, _PLOT_SIZE.y, false, Image.FORMAT_RGB8)
	image.fill(Color(0.09, 0.10, 0.12))
	var bounds := Rect2i(Vector2i.ONE, _PLOT_SIZE - Vector2i(3, 3))
	for index in range(1, points.size()):
		_draw_line(image, _plot_point(points[index - 1], low, scale),
			_plot_point(points[index], low, scale), _TRACE_COLOR, bounds, 1)
	return image


static func _plot_point(point: Vector2, low: Vector2, scale: float) -> Vector2:
	var placed: Vector2 = (point - low) * scale + Vector2(_PLOT_MARGIN, _PLOT_MARGIN)
	return Vector2(placed.x, _PLOT_SIZE.y - 1 - placed.y)


## A fixed neutral inspection camera on the row-04 frame: no speed-dependent widening, no
## source imagery, just the generated track against the generated ground.
static func pov_image(route: Dictionary, time_s: float, row_offset_m: float) -> Image:
	var at := _SAMPLING.distance_at_time(route, time_s) - row_offset_m
	var pose := _SAMPLING.pose_at_distance(route, at)
	var view := Transform3D(
		pose.basis, pose.origin + pose.basis.y * _POV_EYE_UP_M
	).affine_inverse()
	var image := Image.create(_POV_SIZE.x, _POV_SIZE.y, false, Image.FORMAT_RGB8)
	image.fill(Color(0.09, 0.10, 0.12))
	var bounds := Rect2i(Vector2i.ZERO, _POV_SIZE - Vector2i.ONE)
	const GROUND_STEP := 40.0
	var base_x := floorf(pose.origin.x / GROUND_STEP) * GROUND_STEP
	var base_z := floorf(pose.origin.z / GROUND_STEP) * GROUND_STEP
	for line in range(-8, 9):
		var along_x := PackedVector3Array()
		var along_z := PackedVector3Array()
		for step in range(-8, 9):
			var x := base_x + step * GROUND_STEP
			var z := base_z + step * GROUND_STEP
			var fixed_z := base_z + line * GROUND_STEP
			var fixed_x := base_x + line * GROUND_STEP
			along_x.append(Vector3(x, _TERRAIN.height(route.terrain, x, fixed_z), fixed_z))
			along_z.append(Vector3(fixed_x, _TERRAIN.height(route.terrain, fixed_x, z), z))
		_draw_projected(image, view, along_x, Color(0.45, 0.36, 0.26), bounds)
		_draw_projected(image, view, along_z, Color(0.45, 0.36, 0.26), bounds)
	var spine := PackedVector3Array()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var offset := -400.0
	while offset <= 400.0:
		var sample := _SAMPLING.pose_at_distance(route, at + offset)
		spine.append(sample.origin - sample.basis.y * 1.55)
		left.append(sample.origin - sample.basis.x * 0.95 - sample.basis.y * 1.05)
		right.append(sample.origin + sample.basis.x * 0.95 - sample.basis.y * 1.05)
		offset += 2.0
	_draw_projected(image, view, spine, Color(0.62, 0.58, 0.52), bounds)
	_draw_projected(image, view, left, _TRACE_COLOR, bounds)
	_draw_projected(image, view, right, _TRACE_COLOR, bounds)
	return image


## Camera-space polyline: clipped at the near plane, then clipped to the frame, so nothing that
## left the view is smeared back onto an edge.
static func _draw_projected(
	image: Image, view: Transform3D, points: PackedVector3Array, color: Color, bounds: Rect2i
) -> void:
	var previous := Vector3.ZERO
	var has_previous := false
	for point in points:
		var local: Vector3 = view * point
		if has_previous:
			var from := previous
			var to := local
			if from.z <= -_POV_NEAR_M or to.z <= -_POV_NEAR_M:
				if from.z > -_POV_NEAR_M:
					from = _clipped_to_near(to, from)
				elif to.z > -_POV_NEAR_M:
					to = _clipped_to_near(from, to)
				if minf(from.length(), to.length()) <= _POV_FAR_M:
					var segment := _clipped_to_frame(_projected(from), _projected(to), bounds)
					if not segment.is_empty():
						_draw_line(image, segment[0], segment[1], color, bounds)
		previous = local
		has_previous = true


static func _clipped_to_near(inside: Vector3, outside: Vector3) -> Vector3:
	return inside.lerp(outside, (-_POV_NEAR_M - inside.z) / (outside.z - inside.z))


static func _projected(local: Vector3) -> Vector2:
	var focal := 1.0 / tan(deg_to_rad(_POV_FOV_DEG) * 0.5)
	return Vector2(
		(local.x / -local.z * focal / (float(_POV_SIZE.x) / _POV_SIZE.y) * 0.5 + 0.5) * _POV_SIZE.x,
		(0.5 - local.y / -local.z * focal * 0.5) * _POV_SIZE.y
	)


static func _clipped_to_frame(from: Vector2, to: Vector2, bounds: Rect2i) -> PackedVector2Array:
	var delta := to - from
	var low := 0.0
	var high := 1.0
	var edges := [
		[-delta.x, from.x - bounds.position.x], [delta.x, bounds.end.x - from.x],
		[-delta.y, from.y - bounds.position.y], [delta.y, bounds.end.y - from.y],
	]
	for edge in edges:
		var scale: float = edge[0]
		var distance: float = edge[1]
		if absf(scale) < 0.000001:
			if distance < 0.0:
				return PackedVector2Array()
			continue
		var crossing := distance / scale
		if scale < 0.0:
			low = maxf(low, crossing)
		else:
			high = minf(high, crossing)
	if low > high:
		return PackedVector2Array()
	return PackedVector2Array([from.lerp(to, low), from.lerp(to, high)])


static func _draw_line(
	image: Image, from: Vector2, to: Vector2, color: Color, bounds: Rect2i, thickness: int = 0
) -> void:
	var steps := maxi(ceili(from.distance_to(to)), 1)
	for step in steps + 1:
		var point: Vector2 = from.lerp(to, float(step) / steps)
		for dx in range(-thickness, thickness + 1):
			for dy in range(-thickness, thickness + 1):
				image.set_pixel(
					clampi(roundi(point.x) + dx, bounds.position.x, bounds.end.x),
					clampi(roundi(point.y) + dy, bounds.position.y, bounds.end.y),
					color
				)


## The whole checked pack: text, renders, sidecars, then the manifest from the reopened bytes.
## `extra_records` are files the caller already wrote through the checked writers (the geometry
## pack) as `{path, artifact_kind, seed, beat_id}`; they are reopened, hashed and manifested with
## the rest, so the manifest holds one record per written file.
static func write_pack(
	output_dir: String, report: Dictionary, routes_by_seed: Dictionary, overlays: Dictionary = {},
	extra_records: Array = []
) -> PackedStringArray:
	var errors := PackedStringArray()
	if report.get("schema_version") != "ride-fidelity-audit@1":
		errors.append("artifact_write: input is not a completed ride-fidelity-audit@1 report")
		return errors
	if not overlays.is_empty():
		errors = _validate_overlays_for_write(overlays)
		if not errors.is_empty():
			return errors
	var root := output_dir.rstrip("/")
	var records: Array = []
	for case in [
		["audit.json", "audit", canonical_json(report)],
		["audit.md", "audit", markdown(report)],
		["review/pov-map.json", "pov-map", canonical_json(report.pov_map)],
		["review/pov-map.md", "pov-map", _standalone("POV map", _pov_map_lines(report.pov_map))],
		["review/checklist.md", "checklist",
			_standalone("Checklist", _checklist_lines(report.checklist))],
		["review/issue-coverage.json", "issue-coverage", canonical_json(report.issue_coverage)],
		["review/issue-coverage.md", "issue-coverage",
			_standalone("Issue coverage", _issue_coverage_lines(report.issue_coverage))],
	]:
		_write(root, case[0], case[1], case[2], null, null, records, errors)
	var beats := {}
	for summary in report.measurement_summaries:
		var by_id := {}
		for beat in summary.beats:
			by_id[beat.beat_id] = beat
		beats[summary.seed] = by_id
	for request in report.render_requests:
		_write_render(root, request, routes_by_seed, beats, records, errors)
	if not overlays.is_empty():
		_write_overlays(root, overlays, records, errors)
	records.append_array(extra_records)
	var files := _manifest_files(root, records, errors)
	if not errors.is_empty():
		return errors
	errors.append_array(write_text_checked("%s/manifest.json" % root, canonical_json({
		"schema_version": "fidelity-artifact-manifest@1",
		"generation_counts": report.generation_counts, "files": files,
	})))
	return errors


static func _validate_overlays_for_write(overlays: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if overlays.get("schema_version") != "fidelity-semantic-overlays@1": errors.append("artifact_write: overlay schema_version is invalid")
	if overlays.get("status") != "ok": errors.append("artifact_write: overlay status is invalid")
	if not _lower_hex(overlays.get("manifest_sha256"), 64): errors.append("artifact_write: overlay manifest_sha256 is invalid")
	for key in ["recordings", "comparisons", "gaps", "errors"]:
		if not overlays.get(key) is Array: errors.append("artifact_write: overlay %s must be an Array" % key)
	if overlays.get("comparisons") is Array:
		var ids := {}
		for index in overlays.comparisons.size():
			var value: Variant = overlays.comparisons[index]
			if value is Dictionary: _validate_overlay_comparison(value, index, ids, errors)
			else: errors.append("artifact_write: overlay comparison %d must be a Dictionary" % index)
	if overlays.get("gaps") is Array:
		for index in overlays.gaps.size():
			var value: Variant = overlays.gaps[index]
			if not value is Dictionary:
				errors.append("artifact_write: overlay gap %d must be a Dictionary" % index)
				continue
			for key in ["comparison_id", "role", "reason"]:
				if not value.get(key) is String:
					errors.append("artifact_write: overlay gap %d %s must be a String" % [index, key])
	if canonical_json(overlays).is_empty(): errors.append("artifact_write: overlay projection is not canonical JSON data")
	errors.sort(); return errors
static func _validate_overlay_comparison(comparison: Dictionary, index: int,
	ids: Dictionary, errors: PackedStringArray) -> void:
	var label := "comparison %d" % index; var id: Variant = comparison.get("comparison_id")
	if not _lower_slug(id): errors.append("artifact_write: overlay %s comparison_id is invalid" % label)
	elif ids.has(id): errors.append("artifact_write: overlay comparison_id '%s' is duplicated" % id)
	else: ids[id] = true
	if comparison.get("artifact_path") != "review/overlays/%s.png" % str(id): errors.append("artifact_write: overlay %s artifact_path is invalid" % label)
	for key in ["source", "generated"]:
		if not comparison.get(key) is Dictionary: errors.append("artifact_write: overlay %s %s must be a Dictionary" % [label, key])
	for key in ["lanes", "markers", "caveats"]:
		if not comparison.get(key) is Array: errors.append("artifact_write: overlay %s %s must be an Array" % [label, key])
	if not comparison.get("source") is Dictionary or not comparison.get("generated") is Dictionary: return
	var source: Dictionary = comparison.source; var generated: Dictionary = comparison.generated
	_validate_overlay_side(source, true, label, errors); _validate_overlay_side(generated, false, label, errors)
	if comparison.get("lanes") is Array: _validate_overlay_lanes(comparison.lanes, source, generated, label, errors)
	if comparison.get("markers") is Array: _validate_overlay_markers(comparison.markers, source.get("window_s"), label, errors)
	if comparison.get("caveats") is Array:
		for caveat in comparison.caveats:
			if not caveat is String: errors.append("artifact_write: overlay %s caveat must be a String" % label)
static func _validate_overlay_side(side: Dictionary, source_side: bool,
	label: String, errors: PackedStringArray) -> void:
	var name := "source" if source_side else "generated"
	var unavailable := "source_trace_unavailable" if source_side else "generated_window_unavailable"
	var status: Variant = side.get("status")
	if status not in ["available", unavailable]: errors.append("artifact_write: overlay %s %s status is invalid" % [label, name])
	if side.get("clock") != ("source-local-seconds" if source_side else "generated-route-seconds"): errors.append("artifact_write: overlay %s %s clock is invalid" % [label, name])
	var count: Variant = side.get("sample_count")
	if typeof(count) != TYPE_INT or int(count) < 0: errors.append("artifact_write: overlay %s %s sample_count is invalid" % [label, name])
	if not source_side and status == unavailable:
		if side.get("window_s") != null or side.get("duration_s") != null or count != 0: errors.append("artifact_write: overlay %s unavailable generated side has a window" % label)
		return
	var window: Variant = side.get("window_s")
	if not _native_window(window):
		errors.append("artifact_write: overlay %s %s window_s is invalid" % [label, name]); return
	if not _finite_number(side.get("duration_s")) or not is_equal_approx(float(side.duration_s), float(window[1]) - float(window[0])): errors.append("artifact_write: overlay %s %s duration_s is invalid" % [label, name])
static func _validate_overlay_lanes(lanes: Array, source: Dictionary, generated: Dictionary,
	label: String, errors: PackedStringArray) -> void:
	var by_role := {}
	for index in lanes.size():
		var value: Variant = lanes[index]
		if not value is Dictionary:
			errors.append("artifact_write: overlay %s lane %d must be a Dictionary" % [label, index]); continue
		var lane: Dictionary = value; var role: Variant = lane.get("role")
		if role not in ["source_observed_raw", "source_observed_smoothed", "approved_scaled_target", "generated_raw"] or by_role.has(role):
			errors.append("artifact_write: overlay %s lane role is missing, duplicated, or invalid" % label); continue
		by_role[role] = lane
		if not lane.get("status") is String: errors.append("artifact_write: overlay %s lane '%s' status must be a String" % [label, role])
		if not lane.get("samples") is Array: errors.append("artifact_write: overlay %s lane '%s' samples must be an Array" % [label, role])
	for role in ["source_observed_raw", "source_observed_smoothed", "approved_scaled_target", "generated_raw"]:
		if not by_role.has(role): errors.append("artifact_write: overlay %s lane '%s' is missing" % [label, role])
	if by_role.size() != 4: return
	if by_role.source_observed_raw.get("status") != "evidence_gap" or by_role.source_observed_raw.get("samples") != []: errors.append("artifact_write: overlay %s source_observed_raw must be an empty evidence gap" % label)
	for role in ["source_observed_smoothed", "approved_scaled_target"]:
		var lane: Dictionary = by_role[role]
		if lane.get("clock") != "source" or lane.get("status") != source.get("status"): errors.append("artifact_write: overlay %s lane '%s' disagrees with source" % [label, role])
		if source.get("status") != "available" and lane.get("samples") is Array and not lane.samples.is_empty(): errors.append("artifact_write: overlay %s unavailable source lane is not empty" % label)
	var observed: Dictionary = by_role.source_observed_smoothed; var generated_lane: Dictionary = by_role.generated_raw
	if generated_lane.get("clock") != "generated" or generated_lane.get("status") != generated.get("status"): errors.append("artifact_write: overlay %s generated lane disagrees with generated side" % label)
	if generated.get("status") != "available" and generated_lane.get("samples") is Array and not generated_lane.samples.is_empty(): errors.append("artifact_write: overlay %s unavailable generated lane is not empty" % label)
	if observed.get("samples") is Array and typeof(source.get("sample_count")) == TYPE_INT and observed.samples.size() != source.sample_count: errors.append("artifact_write: overlay %s source sample_count disagrees with lane" % label)
	if generated_lane.get("samples") is Array and typeof(generated.get("sample_count")) == TYPE_INT and generated_lane.samples.size() != generated.sample_count: errors.append("artifact_write: overlay %s generated sample_count disagrees with lane" % label)
	_validate_overlay_samples(observed, source.get("window_s"), false, label, errors)
	_validate_overlay_samples(by_role.approved_scaled_target, source.get("window_s"), true, label, errors)
	_validate_overlay_samples(generated_lane, generated.get("window_s"), false, label, errors)
static func _validate_overlay_samples(lane: Dictionary, window: Variant, allow_null_axes: bool,
	label: String, errors: PackedStringArray) -> void:
	if not lane.get("samples") is Array: return
	var previous := -INF
	for index in lane.samples.size():
		var value: Variant = lane.samples[index]
		if not value is Dictionary:
			errors.append("artifact_write: overlay %s lane sample %d must be a Dictionary" % [label, index]); continue
		var sample: Dictionary = value; var time: Variant = sample.get("time_s")
		if not _finite_number(time) or float(time) <= previous: errors.append("artifact_write: overlay %s lane sample time is invalid" % label)
		else:
			previous = float(time)
			if _native_window(window) and (float(time) < float(window[0]) or float(time) >= float(window[1])): errors.append("artifact_write: overlay %s lane sample time is outside its native window" % label)
		if typeof(sample.get("eligible")) != TYPE_BOOL: errors.append("artifact_write: overlay %s lane sample eligible must be Boolean" % label)
		for axis in ["normal_g", "lateral_g", "longitudinal_g"]:
			var axis_value: Variant = sample.get(axis)
			if not _finite_number(axis_value) and not (allow_null_axes and axis_value == null): errors.append("artifact_write: overlay %s lane sample %s is invalid" % [label, axis])
static func _validate_overlay_markers(markers: Array, window: Variant,
	label: String, errors: PackedStringArray) -> void:
	for index in markers.size():
		var value: Variant = markers[index]
		if not value is Dictionary:
			errors.append("artifact_write: overlay %s marker %d must be a Dictionary" % [label, index]); continue
		var marker: Dictionary = value; var time: Variant = marker.get("time_s")
		if not _lower_slug(marker.get("id")) or not _finite_number(time) or not _finite_number(marker.get("uncertainty_s")) or float(marker.get("uncertainty_s", 0.0)) <= 0.0: errors.append("artifact_write: overlay %s marker %d is invalid" % [label, index])
		elif _native_window(window) and (float(time) < float(window[0]) or float(time) > float(window[1]) or (float(time) == float(window[1]) and marker.get("id") != "exit")): errors.append("artifact_write: overlay %s marker %d is outside source window" % [label, index])

static func _native_window(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _finite_number(value[0]) and _finite_number(value[1]) and float(value[0]) < float(value[1])
static func _lower_slug(value: Variant) -> bool:
	if not value is String or value.is_empty(): return false
	for character in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789-": return false
	return true
static func _lower_hex(value: Variant, length: int) -> bool:
	if not value is String or value.length() != length: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true

static func _write_overlays(root: String, overlays: Dictionary,
	records: Array, errors: PackedStringArray) -> void:
	var json := canonical_json(overlays)
	_write(root, "review/overlays/index.json", "telemetry-overlay", json, null, null, records, errors)
	_write(root, "review/overlays/index.md", "telemetry-overlay", _overlay_markdown(overlays),
		null, null, records, errors)
	var comparisons: Array = overlays.comparisons.duplicate(true)
	comparisons.sort_custom(func(a: Dictionary, b: Dictionary): return a.comparison_id < b.comparison_id)
	for comparison: Dictionary in comparisons: _write(root, comparison.artifact_path, "telemetry-overlay", _overlay_image(comparison), null, comparison.comparison_id, records, errors)

static func _overlay_markdown(overlays: Dictionary) -> String:
	var lines := PackedStringArray(["# Semantic telemetry overlays", "",
		"Manifest: `%s`" % overlays.manifest_sha256, "",
		"| comparison | source | generated | artifact |",
		"| --- | --- | --- | --- |"])
	var comparisons: Array = overlays.comparisons.duplicate(true)
	comparisons.sort_custom(func(a: Dictionary, b: Dictionary): return a.comparison_id < b.comparison_id)
	for comparison: Dictionary in comparisons:
		lines.append(_markdown_row([comparison.comparison_id,
			"%s (%s)" % [comparison.source.status, comparison.source.clock],
			"%s (%s)" % [comparison.generated.status, comparison.generated.clock],
			comparison.artifact_path]))
	lines.append_array(["", "## Gaps", ""])
	var gaps: Array = overlays.gaps.duplicate(true)
	gaps.sort_custom(func(a: Dictionary, b: Dictionary):
		return "%s/%s" % [a.get("comparison_id", ""), a.get("role", "")] \
			< "%s/%s" % [b.get("comparison_id", ""), b.get("role", "")])
	if gaps.is_empty(): lines.append("None.")
	for gap: Dictionary in gaps:
		lines.append("- %s / %s: %s" % [gap.get("comparison_id", ""),
			gap.get("role", ""), gap.get("reason", "")])
	return "\n".join(lines) + "\n"

static func _overlay_image(comparison: Dictionary) -> Image:
	var image := Image.create(_OVERLAY_SIZE.x, _OVERLAY_SIZE.y, false, Image.FORMAT_RGB8); image.fill(Color(0.09, 0.10, 0.12))
	var by_role := {}
	for lane: Dictionary in comparison.lanes: by_role[lane.role] = lane
	for axis_index in 3:
		var axis: String = ["normal_g", "lateral_g", "longitudinal_g"][axis_index]
		var source_rect := Rect2i(_OVERLAY_LEFT, axis_index * 300 + 20, _OVERLAY_RIGHT - _OVERLAY_LEFT + 1, 110)
		var generated_rect := Rect2i(_OVERLAY_LEFT, axis_index * 300 + 160, _OVERLAY_RIGHT - _OVERLAY_LEFT + 1, 110)
		_overlay_frame(image, source_rect); _overlay_frame(image, generated_rect)
		var extent := _overlay_extent(axis, [by_role.source_observed_smoothed, by_role.approved_scaled_target, by_role.generated_raw])
		if comparison.source.status != "source_trace_unavailable":
			_overlay_lane(image, by_role.source_observed_smoothed, axis, comparison.source.window_s, extent, source_rect, _OVERLAY_SOURCE_COLOR)
			_overlay_lane(image, by_role.approved_scaled_target, axis, comparison.source.window_s, extent, source_rect, _OVERLAY_TARGET_COLOR)
		for marker: Dictionary in comparison.markers:
			var marker_x := _overlay_x(marker.time_s, comparison.source.window_s, source_rect)
			_draw_line(image, Vector2(marker_x, source_rect.position.y), Vector2(marker_x, source_rect.end.y - 1), _OVERLAY_MARKER_COLOR, source_rect)
		if comparison.generated.status == "available": _overlay_lane(image, by_role.generated_raw, axis, comparison.generated.window_s, extent, generated_rect, _OVERLAY_GENERATED_COLOR)
	return image

static func _overlay_frame(image: Image, rect: Rect2i) -> void:
	var color := Color(0.25, 0.27, 0.30)
	_draw_line(image, rect.position, Vector2(rect.end.x - 1, rect.position.y), color, rect)
	_draw_line(image, Vector2(rect.position.x, rect.end.y - 1), Vector2(rect.end.x - 1, rect.end.y - 1), color, rect)
	_draw_line(image, rect.position, Vector2(rect.position.x, rect.end.y - 1), color, rect)
	_draw_line(image, Vector2(rect.end.x - 1, rect.position.y), Vector2(rect.end.x - 1, rect.end.y - 1), color, rect)

static func _overlay_extent(axis: String, lanes: Array) -> Vector2:
	var low := INF; var high := -INF
	for lane: Dictionary in lanes:
		for sample: Dictionary in lane.samples:
			var value: Variant = sample.get(axis)
			if _finite_number(value): low = minf(low, float(value)); high = maxf(high, float(value))
	if low == INF: return Vector2(-1.0, 1.0)
	if low == high: return Vector2(low - 1.0, high + 1.0)
	return Vector2(low, high)

static func _overlay_lane(image: Image, lane: Dictionary, axis: String, window: Array,
	extent: Vector2, rect: Rect2i, color: Color) -> void:
	for index in range(1, lane.samples.size()):
		var first: Dictionary = lane.samples[index - 1]; var second: Dictionary = lane.samples[index]
		if not first.eligible or not second.eligible or first.get(axis) == null or second.get(axis) == null: continue
		_draw_line(image, _overlay_point(first.time_s, first[axis], window, extent, rect), _overlay_point(second.time_s, second[axis], window, extent, rect), color, rect)

static func _overlay_point(time: float, value: float, window: Array, extent: Vector2, rect: Rect2i) -> Vector2:
	return Vector2(_overlay_x(time, window, rect), rect.end.y - 1 - (value - extent.x) / (extent.y - extent.x) * (rect.size.y - 1))
static func _overlay_x(time: float, window: Array, rect: Rect2i) -> float:
	return rect.position.x + (time - float(window[0])) / (float(window[1]) - float(window[0])) * (rect.size.x - 1)

static func _write_render(
	root: String, request: Dictionary, routes_by_seed: Dictionary,
	beats: Dictionary, records: Array, errors: PackedStringArray
) -> void:
	var seed_value: int = request.seed
	var kind: String = request.artifact_kind
	var beat_id: Variant = request.get("beat_id")
	var stem := "review/seed-%d" % seed_value
	var expected := "%s/%s.png" % [stem, kind]
	if kind == "element" or kind == "pov":
		expected = "%s/%s/%s.png" % [
			stem, "elements" if kind == "element" else "pov", str(beat_id).replace("/", "__")
		]
	if request.path != expected:
		errors.append("artifact_write: render request '%s' does not project '%s'" % [
			request.path, expected])
		return
	if not routes_by_seed.has(seed_value):
		errors.append("artifact_write: no generated route for seed %d" % seed_value)
		return
	var route: Dictionary = routes_by_seed[seed_value]
	match kind:
		"top":
			_write(root, expected, kind, top_image(route), seed_value, null, records, errors)
		"elevation":
			_write(root, expected, kind, elevation_image(route), seed_value, null, records, errors)
		"channels":
			_write_channels(root, expected, seed_value, route, records, errors)
		"element":
			var beat: Dictionary = beats.get(seed_value, {}).get(beat_id, {})
			if not _finite_number(beat.get("start_distance")) or not _finite_number(beat.get("end_distance")):
				errors.append("artifact_write: beat '%s' has no measured span for seed %d" % [
					beat_id, seed_value])
				return
			_write(root, expected, kind, side_image(route,
				_sample_index(route.distances, float(beat.start_distance)),
				_sample_index(route.distances, float(beat.end_distance))
			), seed_value, beat_id, records, errors)
		"pov":
			if not _finite_number(request.get("generated_time_s")):
				errors.append("artifact_write: POV request '%s' has no generated time" % request.path)
				return
			if request.get("row_id") != _POV_ROW_ID \
					or not _finite_number(request.get("row_offset_m")) \
					or absf(float(request.row_offset_m) - _POV_ROW_OFFSET_M) > 0.000001:
				errors.append("artifact_write: POV request '%s' has no row-04 placement" % request.path)
				return
			_write(root, expected, kind, pov_image(route, float(request.generated_time_s),
				float(request.row_offset_m)),
				seed_value, beat_id, records, errors)
		_:
			errors.append("artifact_write: unknown render kind '%s'" % kind)


static func _write_channels(
	root: String, path: String, seed_value: int, route: Dictionary,
	records: Array, errors: PackedStringArray
) -> void:
	var rendered := channels(route)
	_write(root, path, "channels", rendered.image, seed_value, null, records, errors)
	var legend_path := "review/seed-%d/channels.json" % seed_value
	_write(root, legend_path, "channels", canonical_json({
		"schema_version": "fidelity-channel-legend@1", "image_path": path, "seed": seed_value,
		"width": _CHANNEL_WIDTH, "height": _STRIP_HEIGHT * _CHANNEL_SPECS.size(),
		"strips": rendered.strips,
	}), seed_value, null, records, errors)
	var reopened: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("%s/%s" % [root, legend_path]))
	if not reopened is Dictionary:
		errors.append("artifact_write: channel legend for seed %d did not reopen" % seed_value)
		return
	_write(root, "review/seed-%d/channels.md" % seed_value, "channels",
		_channels_markdown(reopened), seed_value, null, records, errors)


static func _channels_markdown(legend: Dictionary) -> String:
	var lines := PackedStringArray([
		"# Channel legend — seed %d" % int(legend.seed), "",
		"Image: %s (%dx%d)" % [legend.image_path, int(legend.width), int(legend.height)], "",
		"| index | channel | label | unit | plot min | plot max | bounded | unbounded | series | color |",
		"| ---: | --- | --- | --- | ---: | ---: | ---: | ---: | --- | --- |",
	])
	for strip in legend.strips:
		var series: Dictionary = strip.series[0]
		var color := PackedStringArray()
		for component in series.color_rgba:
			color.append(_f6(component))
		lines.append(_markdown_row([
			int(strip.index), strip.channel_id, strip.label, strip.unit,
			_f6(strip.plot_min), _f6(strip.plot_max),
			int(strip.bounded_count), int(strip.unbounded_count),
			series.role, ", ".join(color),
		]))
	return "\n".join(lines) + "\n"


static func _write(
	root: String, path: String, artifact_kind: String, content: Variant,
	seed_value: Variant, beat_id: Variant, records: Array, errors: PackedStringArray
) -> void:
	var absolute := "%s/%s" % [root, path]
	var made := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if made != OK and made != ERR_ALREADY_EXISTS:
		errors.append("artifact_write: cannot create '%s' (%s)"
			% [absolute.get_base_dir(), error_string(made)])
		return
	var failures := (
		save_png_checked(content, absolute) if content is Image
		else write_text_checked(absolute, content)
	)
	if failures.is_empty():
		records.append({
			"path": path, "artifact_kind": artifact_kind, "seed": seed_value, "beat_id": beat_id,
		})
	errors.append_array(failures)


static func write_recorded(
	root: String, path: String, artifact_kind: String, content: Variant,
	seed_value: Variant, records: Array, errors: PackedStringArray
) -> void:
	_write(root, path, artifact_kind, content, seed_value, null, records, errors)


static func _manifest_files(root: String, records: Array, errors: PackedStringArray) -> Array:
	var files := []
	for record in records:
		var bytes := FileAccess.get_file_as_bytes("%s/%s" % [root, record.path])
		if bytes.is_empty():
			errors.append("artifact_write: cannot reopen '%s'" % record.path)
			continue
		var width: Variant = null
		var height: Variant = null
		var kind := "png"
		if record.path.ends_with(".json"):
			kind = "json"
		elif record.path.ends_with(".md"):
			kind = "markdown"
		else:
			var image := Image.new()
			if image.load_png_from_buffer(bytes) != OK:
				errors.append("artifact_write: '%s' did not reopen as a PNG" % record.path)
				continue
			width = image.get_width()
			height = image.get_height()
		files.append({
			"path": record.path, "kind": kind, "artifact_kind": record.artifact_kind,
			"byte_size": bytes.size(), "sha256": _CANONICAL_DATA.sha256_bytes(bytes),
			"seed": record.seed, "beat_id": record.beat_id, "width": width, "height": height,
		})
	files.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.path < b.path)
	return files


static func _sample_index(distances: PackedFloat32Array, at: float) -> int:
	var index := _SAMPLING.lower_index(distances, at)
	if absf(distances[index + 1] - at) < absf(distances[index] - at):
		return index + 1
	return index
