class_name RideFidelityOverlay
extends RefCounted

const CanonicalData := preload("res://canonical_data.gd")
const Fidelity := preload("res://fidelity.gd")
const SCHEMA := "fidelity-semantic-overlays@1"
const MANIFEST_SCHEMA := "rfdb-local-overlay-manifest@1"
const HEADER := ["Time", "Lateral", "Vertical", "Longitudinal"]
const AXES := ["normal_g", "lateral_g", "longitudinal_g"]
const ROW_ROUTE_ARRAYS := [
	"times", "distances", "speeds", "tangents", "ups", "curvatures", "roll_rates",
	"normal_g", "lateral_g", "longitudinal_g",
]


static func build(
	manifest: Dictionary, manifest_bytes: PackedByteArray, local_files: Dictionary,
	measurement: Dictionary, route: Dictionary, transforms: Dictionary
) -> Dictionary:
	var errors := _errors(manifest, manifest_bytes, transforms)
	var output := {"schema_version": SCHEMA, "manifest_sha256": _sha(manifest_bytes),
		"recordings": [], "comparisons": [], "gaps": [], "errors": Array(errors)}
	if not errors.is_empty():
		output["status"] = "invalid-input"
		return output
	output["status"] = "ok"
	var recordings: Array = manifest.recordings.duplicate(true)
	recordings.sort_custom(func(a: Dictionary, b: Dictionary): return a.source_id < b.source_id)
	for recording: Dictionary in recordings:
		var loaded := _load(recording, local_files.get(recording.source_id))
		output.recordings.append({"source_id": recording.source_id,
			"source_url": recording.source_url, "expected_sha256": recording.expected_sha256,
			"observed_sha256": loaded.sha256, "validation_status": loaded.status,
			"processing_label": recording.processing_label, "row_seat": recording.row_seat,
			"generated_row_id": recording.generated_row_id,
			"device": recording.device, "reliability": recording.reliability,
			"masks": recording.masks.duplicate(true)})
		var specs: Array = recording.comparisons.duplicate(true)
		specs.sort_custom(func(a: Dictionary, b: Dictionary): return a.comparison_id < b.comparison_id)
		for spec: Dictionary in specs:
			output.comparisons.append(_compare(recording, loaded, spec, measurement, route,
				transforms, output.gaps))
	output.gaps.sort_custom(func(a: Dictionary, b: Dictionary):
		return "%s/%s" % [a.comparison_id, a.role] < "%s/%s" % [b.comparison_id, b.role])
	return output


static func _compare(
	recording: Dictionary, loaded: Dictionary, spec: Dictionary, measurement: Dictionary,
	route: Dictionary, transforms: Dictionary, gaps: Array
) -> Dictionary:
	var source := []
	if loaded.status == "available":
		for sample: Dictionary in loaded.samples:
			if _inside(sample.time_s, spec.source_window_s):
				var retained := sample.duplicate()
				retained["eligible"] = not _masked(sample.time_s, recording.masks)
				source.append(retained)
	else:
		gaps.append(_gap(spec.comparison_id, "source_observed_smoothed", loaded.status))
	var generated := _generated(
		spec.generated_anchor, measurement, route, recording.generated_row_id)
	if generated.status != "available":
		gaps.append(_gap(spec.comparison_id, "generated_raw", generated.status))
	gaps.append(_gap(spec.comparison_id, "source_observed_raw", "unsmoothed-source-unavailable"))
	gaps.append(_gap(spec.comparison_id, "approved_scaled_target",
		"unsupported-positive-longitudinal-transform"))
	var scaled := _scaled(source, recording.transforms, transforms)
	return {"comparison_id": spec.comparison_id, "alignment_status": "semantic_only",
		"evidence_class": spec.evidence_class, "source_id": recording.source_id,
		"source": {"status": loaded.status, "clock": "source-local-seconds",
			"window_s": spec.source_window_s.duplicate(),
			"duration_s": spec.source_window_s[1] - spec.source_window_s[0],
			"sample_count": source.size()},
		"generated": {"status": generated.status, "clock": "generated-route-seconds",
			"seed": measurement.get("seed"), "beat_id": generated.get("beat_id"),
			"row_id": generated.get("row_id"), "row_offset_m": generated.get("row_offset_m"),
			"story_slot_id": spec.generated_anchor.story_slot_id,
			"window_role": spec.generated_anchor.window_role,
			"window_s": generated.get("window_s"), "duration_s": generated.get("duration_s"),
			"sample_count": generated.samples.size()},
		"lanes": [{"role": "source_observed_raw", "status": "evidence_gap", "samples": []},
			{"role": "source_observed_smoothed", "status": loaded.status, "clock": "source",
				"samples": source, "summary": _summary(source, spec.source_window_s)},
			{"role": "approved_scaled_target", "status": loaded.status, "clock": "source",
				"samples": scaled, "transforms": recording.transforms.duplicate(true),
				"gaps": ["unsupported-positive-longitudinal-transform"],
				"summary": _summary(scaled, spec.source_window_s)},
			{"role": "generated_raw", "status": generated.status, "clock": "generated",
				"samples": generated.samples,
				"summary": _summary(generated.samples, generated.get("window_s", [0.0, 0.0]))}],
		"markers": spec.markers.duplicate(true), "caveats": spec.caveats.duplicate(),
		"artifact_path": "review/overlays/%s.png" % spec.comparison_id}


static func _load(recording: Dictionary, path_value: Variant) -> Dictionary:
	if not path_value is String or str(path_value).is_empty() or not FileAccess.file_exists(path_value):
		return _unavailable(null)
	var bytes := FileAccess.get_file_as_bytes(path_value)
	var digest := _sha(bytes)
	if bytes.size() != int(recording.expected_byte_size) or digest != recording.expected_sha256:
		return _unavailable(digest)
	var lines := bytes.get_string_from_utf8().split("\n", false)
	if lines.is_empty() or lines[0].trim_suffix("\r") != ",".join(recording.header):
		return _unavailable(digest)
	var samples := []
	for index in range(1, lines.size()):
		var fields := lines[index].trim_suffix("\r").split(",", true)
		if fields.size() != 4: return _unavailable(digest)
		var values := []
		for field in fields:
			if not str(field).is_valid_float() or not is_finite(float(field)):
				return _unavailable(digest)
			values.append(float(field))
		if not samples.is_empty() and not is_equal_approx(
			values[0] - samples[-1].time_s, recording.cadence_s): return _unavailable(digest)
		samples.append({"time_s": values[0], "lateral_g": values[1],
			"normal_g": values[2], "longitudinal_g": values[3], "eligible": true})
	if samples.size() != int(recording.sample_count) or samples.is_empty() \
			or not is_equal_approx(samples[0].time_s, recording.full_window_s[0]) \
			or not is_equal_approx(samples[-1].time_s, recording.full_window_s[1]):
		return _unavailable(digest)
	return {"status": "available", "sha256": digest, "samples": samples}


static func _generated(
	anchor: Dictionary, measurement: Dictionary, route: Dictionary, row_id: String
) -> Dictionary:
	var matches := []
	for beat: Dictionary in measurement.get("beats", []):
		if beat.story_slot_id == anchor.story_slot_id and beat.window_role == anchor.window_role \
				and beat.kind == anchor.kind and beat.occurrence == anchor.occurrence: matches.append(beat)
	if matches.size() != 1 or not route.has_all(ROW_ROUTE_ARRAYS + ["length"]):
		return {"status": "generated_window_unavailable", "samples": []}
	var rows: Array = matches[0].rows.filter(
		func(row: Dictionary): return row.get("row_id") == row_id)
	if rows.size() != 1 or ROW_ROUTE_ARRAYS.any(
		func(field: String): return route[field].size() != route.times.size()
	) or not _positive(route.length):
		return {"status": "generated_window_unavailable", "samples": []}
	if not _number(rows[0].get("offset")):
		return {"status": "generated_window_unavailable", "samples": []}
	var window := [rows[0].window_start_s, rows[0].window_end_s]
	var row_series := Fidelity.native_row_series(route, float(rows[0].offset))
	var samples := []
	for index in route.times.size():
		if _inside(route.times[index], window):
			samples.append({"time_s": float(route.times[index]),
				"normal_g": float(row_series.normal_g[index]),
				"lateral_g": float(row_series.lateral_g[index]),
				"longitudinal_g": float(row_series.longitudinal_g[index]), "eligible": true})
	if samples.is_empty(): return {"status": "generated_window_unavailable", "samples": []}
	return {"status": "available", "beat_id": matches[0].beat_id,
		"row_id": row_id, "row_offset_m": rows[0].offset, "window_s": window,
		"duration_s": window[1] - window[0], "samples": samples}


static func _scaled(source: Array, ids: Dictionary, transforms: Dictionary) -> Array:
	var output := []
	for sample: Dictionary in source:
		var target := {"time_s": sample.time_s, "eligible": sample.eligible}
		for axis in AXES:
			var value: float = sample[axis]
			var id: Variant = ids[axis]["positive" if value > 0.0 else "negative"]
			target[axis] = null if id == null else value * transforms[id].factor
		output.append(target)
	return output


static func _summary(samples: Array, window: Array) -> Dictionary:
	var axes := {}
	for axis in AXES:
		var total := 0.0; var squares := 0.0; var positive := -INF; var negative := INF
		var positive_held := 0.0; var negative_held := 0.0
		var longest_positive := 0.0; var longest_negative := 0.0; var denominator := 0.0
		for index in samples.size():
			var sample: Dictionary = samples[index]
			if not sample.eligible or sample[axis] == null:
				positive_held = 0.0; negative_held = 0.0
				continue
			var end: float = minf(window[1], samples[index + 1].time_s) \
				if index + 1 < samples.size() else window[1]
			var dt := maxf(0.0, end - sample.time_s)
			var value: float = sample[axis]
			denominator += dt; total += value * dt; squares += value * value * dt
			if value > 0.0:
				positive = maxf(positive, value)
				positive_held += dt; negative_held = 0.0
				longest_positive = maxf(longest_positive, positive_held)
			elif value < 0.0:
				negative = minf(negative, value)
				negative_held += dt; positive_held = 0.0
				longest_negative = maxf(longest_negative, negative_held)
			else:
				positive_held = 0.0; negative_held = 0.0
		axes[axis] = {"metric_label": axis, "denominator_s": denominator,
			"mean": null if denominator == 0.0 else total / denominator,
			"rms": null if denominator == 0.0 else sqrt(squares / denominator),
			"peak_positive_g": null if positive == -INF else positive,
			"peak_negative_g": null if negative == INF else negative,
			"longest_positive_hold_s": longest_positive,
			"longest_negative_hold_s": longest_negative}
	return {"window_s": window.duplicate(), "mask_policy": "exclude-ineligible-retain-time",
		"axes": axes}


static func _errors(
	manifest: Dictionary, manifest_bytes: PackedByteArray, transforms: Dictionary
) -> PackedStringArray:
	var errors := PackedStringArray()
	var parsed: Variant = JSON.parse_string(manifest_bytes.get_string_from_utf8())
	if not parsed is Dictionary or not _equivalent(parsed, manifest):
		errors.append("manifest bytes do not match parsed manifest")
	if manifest.get("schema_version") != MANIFEST_SCHEMA or not manifest.get("recordings") is Array:
		errors.append("manifest has invalid top-level schema")
		return errors
	var ids := {}
	for value in manifest.recordings:
		if not value is Dictionary:
			errors.append("recording is not a Dictionary"); continue
		var r: Dictionary = value
		for key in ["source_id", "source_url", "expected_sha256", "expected_byte_size", "header",
			"sample_count", "cadence_s", "full_window_s", "ride_window_s", "processing_label",
			"smoothing", "row_seat", "generated_row_id", "device", "reliability", "masks", "transforms",
			"derivation", "comparisons"]:
			if not r.has(key): errors.append("recording is missing %s" % key)
		if not errors.is_empty(): continue
		if not _slug(r.source_id) or ids.has(r.source_id) or not _text(r.source_url) \
				or not _sha_valid(r.expected_sha256) or not _positive(r.expected_byte_size) \
				or r.header != HEADER or not _positive(r.sample_count) or not _positive(r.cadence_s) \
				or not _window(r.full_window_s) or not _contained(r.ride_window_s, r.full_window_s) \
				or r.processing_label != "source_observed_smoothed" or not _text(r.smoothing) \
				or not _text(r.row_seat) or not _slug(r.generated_row_id) \
				or not _text(r.device) or not _text(r.reliability) \
				or not r.masks is Array or not r.comparisons is Array or not r.transforms is Dictionary \
				or not r.derivation is Dictionary:
			errors.append("recording has invalid required fields"); continue
		ids[r.source_id] = true
		for mask in r.masks:
			if not mask is Dictionary or not _text(mask.get("reason")) \
					or not _contained(mask.get("window_s"), r.full_window_s): errors.append("invalid mask")
		if not _transform_ids_valid(r.transforms, transforms): errors.append("invalid transforms")
		if r.derivation.get("tool") != "RideFidelityOverlay" or r.derivation.get("version") != 1:
			errors.append("invalid derivation")
		for comparison in r.comparisons:
			if not _comparison_valid(comparison, r.full_window_s, ids): errors.append("invalid comparison")
			elif ids.has(comparison.comparison_id): errors.append("duplicate comparison id")
			else: ids[comparison.comparison_id] = true
	errors.sort()
	return errors


static func _comparison_valid(value: Variant, bounds: Array, ids: Dictionary) -> bool:
	if not value is Dictionary or not _slug(value.get("comparison_id")) \
			or not _contained(value.get("source_window_s"), bounds) or not _text(value.get("evidence_class")) \
			or not _text(value.get("identity_confidence")) or not value.get("caveats") is Array \
			or not value.get("markers") is Array or not value.get("generated_anchor") is Dictionary: return false
	for caveat in value.caveats:
		if not _text(caveat): return false
	for marker in value.markers:
		if not marker is Dictionary or not _slug(marker.get("id")) or not _number(marker.get("time_s")) \
				or marker.time_s < value.source_window_s[0] or marker.time_s > value.source_window_s[1] \
				or not _positive(marker.get("uncertainty_s")): return false
	var a: Dictionary = value.generated_anchor
	return _slug(a.get("story_slot_id")) and _slug(a.get("window_role")) and _slug(a.get("kind")) \
		and _integer(a.get("occurrence")) and a.occurrence >= 0


static func _transform_ids_valid(ids: Dictionary, transforms: Dictionary) -> bool:
	for axis in AXES:
		if not ids.get(axis) is Dictionary: return false
		for polarity in ["positive", "negative"]:
			var id: Variant = ids[axis].get(polarity)
			if id == null and axis == "longitudinal_g" and polarity == "positive": continue
			var record: Variant = transforms.get(id)
			if not record is Dictionary or record.get("kind") != "scale" \
					or record.get("axis") != axis or record.get("polarity") != polarity \
					or not _positive(record.get("factor")): return false
	return true


static func _equivalent(first: Variant, second: Variant) -> bool:
	if _number(first) and _number(second): return float(first) == float(second)
	if typeof(first) != typeof(second): return false
	if first is Dictionary:
		if first.keys().size() != second.keys().size(): return false
		for key in first:
			if not second.has(key) or not _equivalent(first[key], second[key]): return false
		return true
	if first is Array:
		if first.size() != second.size(): return false
		for index in first.size():
			if not _equivalent(first[index], second[index]): return false
		return true
	return first == second


static func _inside(value: float, window: Array) -> bool: return value >= window[0] and value < window[1]
static func _contained(value: Variant, bounds: Array) -> bool:
	return _window(value) and value[0] >= bounds[0] and value[1] <= bounds[1]
static func _masked(value: float, masks: Array) -> bool:
	for mask: Dictionary in masks:
		if _inside(value, mask.window_s): return true
	return false
static func _window(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1]) \
		and value[0] < value[1]
static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
static func _positive(value: Variant) -> bool: return _number(value) and value > 0.0
static func _integer(value: Variant) -> bool: return _number(value) and value == floorf(value)
static func _text(value: Variant) -> bool: return value is String and not str(value).is_empty()
static func _slug(value: Variant) -> bool:
	if not _text(value): return false
	for character in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789-": return false
	return true
static func _sha_valid(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true
static func _gap(id: String, role: String, reason: String) -> Dictionary:
	return {"comparison_id": id, "role": role, "reason": reason}
static func _unavailable(digest: Variant) -> Dictionary:
	return {"status": "source_trace_unavailable", "sha256": digest, "samples": []}
static func _sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(bytes)
	return context.finish().hex_encode()
