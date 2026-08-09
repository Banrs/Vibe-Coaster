class_name RideFidelity
extends RefCounted

const Verify := preload("res://verify.gd")

const CONFIDENCE := ["high", "medium", "low"]
const DIMENSIONS := ["loads", "geometry", "pacing", "terrain", "flow"]
const METRICS := [
	"normal_peak_positive", "normal_peak_negative",
	"normal_held_positive", "normal_held_negative",
	"lateral_peak_absolute", "longitudinal_held_positive", "longitudinal_peak_negative",
	"onset_peak", "roll_rate_peak",
	"length", "height", "width", "min_pitch", "max_pitch", "max_bank",
	"apex_radius", "valley_radius", "entry_speed", "exit_speed",
	"duration", "speed_loss", "average_speed", "dead_zone_share",
	"speed_share_100", "speed_share_200", "flat_seconds", "beat_count",
	"agl_min", "agl_median", "agl_max", "terrain_hugging_share",
	"transition_force_swing", "transition_seconds", "bank_handoff",
	"flat_dwell", "same_kind_adjacency",
]


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
	var normal: PackedFloat32Array = Verify.filter(Verify.resample(route.times, route.normal_g))
	var lateral: PackedFloat32Array = Verify.filter(Verify.resample(route.times, route.lateral_g))
	var longitudinal: PackedFloat32Array = Verify.filter(
		Verify.resample(route.times, route.longitudinal_g)
	)
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
			"element": element,
			"phase": phase,
			"beat_id": "%s/%02d/%s" % [_slug(phase), ordinal, _slug(kind)],
			"first": section.start_index,
			"last": section.end_index,
		})

	var bands := []
	for beat in beats:
		var low_time: float = route.times[beat.first]
		var high_time: float = route.times[beat.last]
		var low: int = mini(floori(low_time * Verify.SAMPLE_HZ), normal.size() - 1)
		var high: int = mini(floori(high_time * Verify.SAMPLE_HZ), normal.size() - 1)
		if high - low < 4:
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
			"seconds": high_time - low_time,
			"normal": normal.slice(low, high + 1),
			"lateral": lateral.slice(low, high + 1),
			"longitudinal": longitudinal.slice(low, high + 1),
		})
	return bands


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
		for key in ["source_ids", "confidence", "selector", "dimension", "metric", "raw_range", "target_range", "issues"]:
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
		_validate_range(target_id, "raw_range", target.get("raw_range"), errors)
		_validate_range(target_id, "target_range", target.get("target_range"), errors)
		var source_ids: Variant = target.get("source_ids")
		if not source_ids is Array or source_ids.is_empty():
			errors.append("target '%s' has no source_ids" % target_id)
		else:
			for source_id in source_ids:
				if not sources.has(source_id):
					errors.append("target '%s' references unknown source '%s'" % [target_id, source_id])
		var issues: Variant = target.get("issues")
		if not issues is Array or issues.is_empty():
			errors.append("target '%s' has no issue mappings" % target_id)
		else:
			for issue in issues:
				if typeof(issue) != TYPE_INT or issue < 1 or issue > 16:
					errors.append("target '%s' has invalid issue '%s'" % [target_id, issue])
	return errors


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
