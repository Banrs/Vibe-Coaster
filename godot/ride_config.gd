class_name RideConfig
extends RefCounted

## The version-1 public configuration surface: the key registry, the overlay algebra of design
## §3 rules 1-7, and the mapping from a catalogued intensity choice onto the planner's certified
## draw ranges.
##
## The design's honesty rule governs what lives here: "a key is absent from the public schema
## until tests prove that contract." Only three keys clear that bar today — `preset`, `seed`, and
## `slot.intensity` on the two return-height slots, whose ranges `ride_planner_tests.gd` certifies
## at both extremes. Every key the design listed but measurement refused is recorded in
## `UNREGISTERED` with the measurement that refused it, so the next session inherits the reason
## instead of rediscovering it.
##
## This module decides; it never generates. `RideGenerator.build_config()` turns a resolved
## document into planner pins, and the planner's existing override seam applies them without
## changing how many values any stream produces.

const RidePlannerScript := preload("res://ride_planner.gd")
const CanonicalDataScript := preload("res://canonical_data.gd")

const VERSION := 1
const PRESET_ID := "material-v1"
## The preset's own declared demo seed: the base layer must supply every scalar, because rule 2
## says an omitted field inherits the layer below rather than defaulting late.
const PRESET_SEED := 42

const LAYER_PRESET := "preset"
const LAYER_FILE := "file"
const LAYER_CLI := "cli"

const BUCKET_REQUIRED := "required"
const BUCKET_PREFERRED := "preferred"

const KEY_PRESET := "preset"
const KEY_SEED := "seed"
const KEY_SLOT_INTENSITY := "slot.intensity"
const DOCUMENT_VERSION_FIELD := "ride_config_version"

const INTENSITY_CHOICES := ["low", "medium", "high"]
## low/medium/high name the bottom, middle and top third of a certified range; the pinned value is
## the centre of the named third, so no choice ever sits on a range boundary.
const INTENSITY_FRACTIONS := {"low": 1.0 / 6.0, "medium": 0.5, "high": 5.0 / 6.0}

## Which certified draws each legal `slot.intensity` scope pins. `return-height-b` has no `peak_g`
## draw of its own on purpose: its peak follows height-a's proportionally, because the
## strong-a/weak-b diagonal is the one corner of the draw box the return solve cannot close from
## its fixed seed (see `_return_spans` in `ride_program.gd`).
const INTENSITY_SCOPES := ["return-height-a", "return-height-b"]
const INTENSITY_PINNED_KEYS := {
	"return-height-a": ["peak_g", "unload_scale"],
	"return-height-b": ["unload_scale"],
}

## The version-1 key registry. Each entry declares value type, unit, legal scope, legal operator,
## domain, owner, and feasibility phase, exactly as design §3 requires.
const REGISTRY := [
	{
		"key": KEY_PRESET, "type": "string", "unit": "preset-id",
		"scope": "ride", "scopes": ["ride"], "form": "scalar",
		"operator": "required equality", "domain": [PRESET_ID],
		"owner": "RideGenerator", "feasibility_phase": "planning",
		"notes": "The one shipped preset. A second preset ID enters the domain when a second "
			+ "preset exists and is gated.",
	},
	{
		"key": KEY_SEED, "type": "int", "unit": "none",
		"scope": "ride", "scopes": ["ride"], "form": "scalar",
		"operator": "required equality", "domain": "signed 64-bit integer",
		"owner": "RidePlanner.streams", "feasibility_phase": "planning",
		"notes": "Selects every named decision stream. Certified by the fifteen-seed fleet gate "
			+ "in smoke.gd, not by a per-value check.",
	},
	{
		"key": KEY_SLOT_INTENSITY, "type": "catalogued enum", "unit": "none",
		"scope": "story slot", "scopes": INTENSITY_SCOPES, "form": "constraint",
		"operator": "preferred choice", "domain": INTENSITY_CHOICES,
		"owner": "RidePlanner.TARGET_DRAWS", "feasibility_phase": "planning",
		"notes": "A planning-phase preferred choice: it pins the slot's certified draws at the "
			+ "centre of the named third of their ranges instead of drawing them. Legal only on "
			+ "the two return-height slots, the only slots whose ranges are certified at both "
			+ "extremes.",
	},
]

## Keys the design listed for version 1 that measurement refused, each with the measurement.
## This list is data, not prose: it is what a later session reads before proposing a key again.
const UNREGISTERED := [
	{
		"key": "slot.recipe", "design_phase": "planning",
		"reason": "No slot has a second certified recipe, and the one grammar cell that could "
			+ "vary was measured shut. All 24 act-one pool permutations were built on "
			+ "2026-08-15: twelve cannot complete the capability preflight at all, and the two "
			+ "that land within metres of the canonical prefix then fail the whole fleet — the "
			+ "reordered act one hands the dive over 2.5-4.4 m/s faster, running the dive role "
			+ "to 499 m against its 350-490 m band and moving the camelback handoff far enough "
			+ "that the seven-control return solve stops closing on 12 of 15 seeds.",
		"blocked_by": "the prefix closure solve tracked as docs/ISSUES.md issue 24",
		"evidence": "commit abaae42",
	},
	{
		"key": "slot.enabled", "design_phase": "planning",
		"reason": "The grammar declares exactly two optional slots (act-one-airtime, "
			+ "act-one-wave) and both single-drop variants were built in the same 2026-08-15 "
			+ "sweep. The airtime-drop variant fails the fleet in the same way as the "
			+ "permutations, so no optional slot has a certified enabled/disabled pair to expose.",
		"blocked_by": "the prefix closure solve tracked as docs/ISSUES.md issue 24",
		"evidence": "commit abaae42",
	},
	{
		"key": "ride.duration_s", "design_phase": "compilation",
		"reason": "No control authority exists to spend. Across the fifteen-seed fleet the "
			+ "measured duration spans 157.54-157.84 s — 0.31 s total — because every element is "
			+ "an authored fixed-duration force profile and the only bounded solve in the ride "
			+ "targets the capture corridor, the route-length band and the entry-speed band. A "
			+ "duration preference could only be reported as unresolved for any tolerance "
			+ "narrower than the fleet spread it cannot move.",
		"blocked_by": "a re-timing solve that owns element durations",
		"evidence": "commit 5e0fec4 fleet measurement",
	},
	{
		"key": "ride.peak_speed_mps", "design_phase": "compilation",
		"reason": "Peak speed is the ride's fixed identity, not a preference. The record launch "
			+ "is derived, the records are deliberately undrawn, and the fleet holds top speed at "
			+ "94.554-94.555 m/s. Accepting a target here would either be a no-op or move the "
			+ "record the contract pins.",
		"blocked_by": "a decision to make the record configurable at all",
		"evidence": "docs/superpowers/specs/2026-08-15-record-launch-derivation.md",
	},
	{
		"key": "slot.structure_height_m", "design_phase": "compilation",
		"reason": "No slot exposes a certifiable height range. The story prefix is one rigid "
			+ "energy chain: on seed 42 a 0.02 g change in the helical loop moves the native "
			+ "summit rise 17.2 m, the dive chord 120.5 m and the dive entry 8.84 m/s, against a "
			+ "placement budget of a few metres of rise. A certifiable range there would be "
			+ "~0.3% wide — indistinguishable variety bought at real risk.",
		"blocked_by": "the prefix closure solve tracked as docs/ISSUES.md issue 24",
		"evidence": "commit 5e0fec4 sensitivity table, quoted in ride_planner.gd",
	},
	{
		"key": "slot.airtime_character", "design_phase": "planning",
		"reason": "The only certified float control is `unload_scale` on the two return-height "
			+ "slots, and `slot.intensity` already owns it. A separate airtime-character "
			+ "catalogue would need its own measured choices on its own certified range; none "
			+ "has been measured.",
		"blocked_by": "a measured choice catalogue distinct from intensity",
		"evidence": "RidePlanner.TARGET_DRAWS",
	},
	{
		"key": "sequence.order", "design_phase": "planning",
		"reason": "Reserved by design §3 for a future version and rejected by the version-1 "
			+ "validator. The act-one permutation sweep independently shows there is nothing "
			+ "legal to order yet.",
		"blocked_by": "a future sandbox version",
		"evidence": "design §3, commit abaae42",
	},
	{
		"key": "sequence.pinned", "design_phase": "planning",
		"reason": "A recipe pin map is the document form of `slot.recipe`; it is refused for the "
			+ "same measured reason.",
		"blocked_by": "the prefix closure solve tracked as docs/ISSUES.md issue 24",
		"evidence": "commit abaae42",
	},
]

const _DOCUMENT_FIELDS := [DOCUMENT_VERSION_FIELD, KEY_PRESET, KEY_SEED, "constraints"]
const _CONSTRAINT_FIELDS := ["id", "scope", "key", "choice", "value", "target", "tolerance"]
const _VALUE_FIELDS := ["choice", "value", "target", "tolerance"]


## The registry, as plain data a caller may keep.
static func registry() -> Array:
	return REGISTRY.duplicate(true)


## The refused keys and the measurement that refused each of them.
static func unregistered() -> Array:
	return UNREGISTERED.duplicate(true)


## The base layer of the overlay: the preset's own complete document.
static func preset_base() -> Dictionary:
	return {
		DOCUMENT_VERSION_FIELD: VERSION, KEY_PRESET: PRESET_ID, KEY_SEED: PRESET_SEED,
		"constraints": {BUCKET_REQUIRED: [], BUCKET_PREFERRED: []},
	}


## Resolve preset ← file ← CLI (last wins, in argument order) into one canonical document.
##
## Returns `{ok, resolved, errors, report}`. `errors` is an array of structured records, each
## carrying the code, the offending layer, and a message that names the scope, the conservative
## capability range or choices, and the conflict. `report.preferences` starts every preference at
## status `pending`; `record_achievements()` fills `achieved`, `delta`, `status` and `reason` once
## planning has actually resolved the draws.
static func normalize(file_config: Dictionary, cli_overrides: Array = []) -> Dictionary:
	var errors: Array = []
	var layers := _layers(file_config, cli_overrides, errors)
	var scalars := {}
	var sources := {}
	var by_id := {}
	var first_seen: Array = []
	for layer: Dictionary in layers:
		_read_layer(layer, scalars, sources, by_id, first_seen, errors)
	var effective: Array = []
	var claimed := {}
	for id: String in first_seen:
		var record: Dictionary = by_id[id]
		if not _validate_constraint(record, errors):
			continue
		var claim := "%s\t%s" % [record.scope, record.key]
		if claimed.has(claim):
			_error(errors, "ambiguous_constraint",
				("constraints '%s' and '%s' are both effective for scope '%s' key '%s'; " +
				"version 1 rejects two effective IDs for one (scope, key) rather than " +
				"guessing which one wins") % [claimed[claim], id, record.scope, record.key],
				{"scope": record.scope, "key": record.key})
			continue
		claimed[claim] = id
		effective.append(record)
	_validate_scalars(scalars, errors)
	effective.sort_custom(_precedence_before)
	var required: Array = []
	var preferred: Array = []
	for record: Dictionary in effective:
		if str(record.bucket) == BUCKET_REQUIRED:
			required.append(_public_constraint(record))
		else:
			preferred.append(_public_constraint(record))
	var resolved := {
		DOCUMENT_VERSION_FIELD: int(scalars.get(DOCUMENT_VERSION_FIELD, VERSION)),
		KEY_PRESET: str(scalars.get(KEY_PRESET, PRESET_ID)),
		KEY_SEED: int(scalars.get(KEY_SEED, PRESET_SEED)),
		"constraints": {BUCKET_REQUIRED: required, BUCKET_PREFERRED: preferred},
		"sources": sources,
	}
	resolved["config_hash"] = config_hash(resolved)
	return {"ok": errors.is_empty(), "resolved": resolved, "errors": errors,
		"report": _initial_report(resolved)}


## The canonical hash of a resolved document: SHA-256 over the canonical JSON of its *effective*
## values only. Provenance is deliberately excluded, so the same effective configuration hashes
## the same whether the seed arrived from the file or from a CLI override.
static func config_hash(resolved: Dictionary) -> String:
	var payload := {
		DOCUMENT_VERSION_FIELD: int(resolved.get(DOCUMENT_VERSION_FIELD, VERSION)),
		KEY_PRESET: str(resolved.get(KEY_PRESET, "")), KEY_SEED: int(resolved.get(KEY_SEED, 0)),
		"constraints": {BUCKET_REQUIRED: [], BUCKET_PREFERRED: []},
	}
	var constraints: Dictionary = resolved.get("constraints", {})
	for bucket in [BUCKET_REQUIRED, BUCKET_PREFERRED]:
		var canonical: Array = []
		for record: Dictionary in constraints.get(bucket, []):
			canonical.append(_with_values(
				{"id": str(record.id), "scope": str(record.scope), "key": str(record.key)},
				record))
		payload.constraints[bucket] = canonical
	var text := CanonicalDataScript.canonical_json(payload)
	if text.is_empty():
		return ""
	return CanonicalDataScript.sha256_text(text)


## The planner pins a resolved document asks for, in canonical order: one record per certified
## draw an intensity choice replaces.
static func planner_pins(resolved: Dictionary) -> Array:
	var pins: Array = []
	var constraints: Dictionary = resolved.get("constraints", {})
	for record: Dictionary in constraints.get(BUCKET_PREFERRED, []):
		if str(record.get("key", "")) != KEY_SLOT_INTENSITY:
			continue
		var scope := str(record.scope)
		var choice := str(record.choice)
		var fraction := intensity_fraction(choice)
		if not is_finite(fraction):
			continue
		for key: String in INTENSITY_PINNED_KEYS.get(scope, []):
			var band := certified_range(scope, key)
			if band == Vector2.ZERO:
				continue
			pins.append({
				"id": str(record.id), "scope": scope, "role_id": scope, "key": key,
				"choice": choice, "stream": RidePlannerScript.TARGET_STREAM_PREFIX + scope,
				"value": lerpf(band.x, band.y, fraction), "range": [band.x, band.y],
			})
	return pins


## The planner override dictionary those pins become. The planner's override seam replaces a drawn
## value without changing how many values any stream produces, so a pinned build stays aligned
## with an unpinned one draw for draw.
static func planner_overrides(pins: Array) -> Dictionary:
	var overrides := {}
	for pin: Dictionary in pins:
		overrides["%s/%s" % [pin.role_id, pin.key]] = float(pin.value)
	return overrides


## The draw provenance a configured build publishes: every draw states its stream and whether the
## configuration pinned it. Only a configured build carries the field, so the unconfigured
## `build(seed)` path stays byte-for-byte what it was.
static func annotate_draws(draws: Array, pins: Array) -> Array:
	var pinned := {}
	for pin: Dictionary in pins:
		pinned["%s/%s" % [pin.role_id, pin.key]] = true
	var annotated: Array = []
	for draw: Dictionary in draws:
		var record: Dictionary = draw.duplicate(true)
		record["pinned_by_config"] = pinned.has("%s/%s" % [draw.role_id, draw.key])
		annotated.append(record)
	return annotated


## Fill the resolution report from what planning actually resolved. A preference is achieved only
## when every draw it pinned came back at the pinned value; anything else is reported unresolved
## with its measured delta, never as achieved-outside-tolerance.
static func record_achievements(report: Dictionary, draws: Array, pins: Array) -> Dictionary:
	var filled: Dictionary = report.duplicate(true)
	var resolved_values := {}
	for draw: Dictionary in draws:
		resolved_values["%s/%s" % [draw.role_id, draw.key]] = float(draw.value)
	var preferences: Array = filled.get("preferences", [])
	for entry: Dictionary in preferences:
		var id := str(entry.id)
		var achieved := {}
		var delta := 0.0
		var missing: Array = []
		var count := 0
		for pin: Dictionary in pins:
			if str(pin.id) != id:
				continue
			count += 1
			var target_key := "%s/%s" % [pin.role_id, pin.key]
			if not resolved_values.has(target_key):
				missing.append(target_key)
				continue
			achieved[target_key] = resolved_values[target_key]
			delta = maxf(delta, absf(float(resolved_values[target_key]) - float(pin.value)))
		entry["achieved_targets"] = achieved
		if count == 0:
			entry.merge({"status": "unresolved", "achieved": null, "delta": null,
				"reason": "the preference mapped onto no certified draw"}, true)
			continue
		if not missing.is_empty() or delta > 1e-9:
			entry.merge({"status": "unresolved", "achieved": null, "delta": delta,
				"reason": ("planning did not resolve the pinned draws to the requested "
					+ "values (missing %s, worst delta %.9f)") % [str(missing), delta]}, true)
			continue
		entry.merge({"status": "achieved", "achieved": str(entry.request), "delta": 0.0,
			"reason": ("pinned %d certified draw(s) at the centre of the %s third of their "
				+ "certified ranges") % [count, str(entry.request)]}, true)
	return filled


## The certified range one slot draw carries, read from the planner so this module can never
## drift from the ranges the planner tests certify.
static func certified_range(role_id: String, key: String) -> Vector2:
	for specification: Dictionary in RidePlannerScript.TARGET_DRAWS:
		if str(specification.role_id) == role_id and str(specification.key) == key:
			return specification.range
	return Vector2.ZERO


static func intensity_fraction(choice: String) -> float:
	return float(INTENSITY_FRACTIONS.get(choice, NAN))


## The flat messages of a structured error array, for logs and test assertions.
static func error_messages(errors: Array) -> PackedStringArray:
	var messages := PackedStringArray()
	for record: Dictionary in errors:
		messages.append(str(record.get("message", "")))
	return messages


static func registry_entry(key: String) -> Dictionary:
	for entry: Dictionary in REGISTRY:
		if str(entry.key) == key:
			return entry
	return {}


# -- layers ---------------------------------------------------------------------------------

static func _layers(file_config: Dictionary, cli_overrides: Array, errors: Array) -> Array:
	var layers: Array = [
		{"layer": LAYER_PRESET, "label": LAYER_PRESET, "order": 0, "argument": -1,
			"document": preset_base()},
		{"layer": LAYER_FILE, "label": LAYER_FILE, "order": 1, "argument": -1,
			"document": file_config},
	]
	for index in cli_overrides.size():
		var override: Variant = cli_overrides[index]
		var label := "cli[%d]" % index
		var document := {}
		if override is Dictionary:
			document = override
		elif override is String or override is StringName:
			document = _parse_cli(str(override), label, errors)
			if document.is_empty():
				continue
		else:
			_error(errors, "cli_override_type",
				("CLI override %d is not usable; version 1 accepts a '<key>=<value>' or " +
				"'[<id>@]<scope>/<key>=<value>' string, or a partial config dictionary") % index,
				{"layer": label})
			continue
		layers.append({"layer": LAYER_CLI, "label": label, "order": 2 + index,
			"argument": index, "document": document})
	return layers


static func _parse_cli(text: String, label: String, errors: Array) -> Dictionary:
	var equals := text.find("=")
	if equals <= 0:
		_error(errors, "cli_override_syntax",
			("CLI override %s ('%s') is not an assignment; version 1 accepts " +
			"'<key>=<value>' or '[<id>@]<scope>/<key>=<value>'") % [label, text], {"layer": label})
		return {}
	var left := text.substr(0, equals).strip_edges()
	var right := text.substr(equals + 1).strip_edges()
	var id := ""
	var at := left.find("@")
	if at >= 0:
		id = left.substr(0, at).strip_edges()
		left = left.substr(at + 1).strip_edges()
		if id.is_empty():
			_error(errors, "cli_override_syntax",
				"CLI override %s ('%s') declares an empty constraint ID" % [label, text],
				{"layer": label})
			return {}
	var slash := left.rfind("/")
	if slash < 0:
		var value: Variant = right
		if left == KEY_SEED or left == DOCUMENT_VERSION_FIELD:
			if not right.is_valid_int():
				_error(errors, "cli_override_value",
					"CLI override %s ('%s') must assign an integer to '%s'" % [label, text, left],
					{"layer": label, "key": left})
				return {}
			value = int(right)
		return {left: value}
	var scope := left.substr(0, slash).strip_edges()
	var key := left.substr(slash + 1).strip_edges()
	var entry := registry_entry(key)
	var bucket := BUCKET_PREFERRED
	if not entry.is_empty() and str(entry.operator) == "required equality":
		bucket = BUCKET_REQUIRED
	var field := _value_field(entry)
	var record := {"id": id if not id.is_empty() else _auto_id(scope, key), "scope": scope,
		"key": key}
	record[field] = right
	return {"constraints": {bucket: [record]}}


static func _auto_id(scope: String, key: String) -> String:
	return "auto:%s/%s" % [scope, key]


## Required equality reads 'value'; every other operator, and an unregistered key, reads 'choice'.
static func _value_field(entry: Dictionary) -> String:
	return "value" if not entry.is_empty() and str(entry.operator) == "required equality" \
		else "choice"


static func _read_layer(layer: Dictionary, scalars: Dictionary, sources: Dictionary,
		by_id: Dictionary, first_seen: Array, errors: Array) -> void:
	var document: Dictionary = layer.document
	var label := str(layer.label)
	var fields := document.keys()
	fields.sort()
	for field_name: Variant in fields:
		var field := str(field_name)
		var value: Variant = document[field_name]
		if value == null:
			_error(errors, "null_value",
				("'%s' is explicitly null in layer %s; version 1 has no reset operator, so an " +
				"omitted field inherits the layer below instead") % [field, label],
				{"layer": label, "key": field})
			continue
		if field == "sequence":
			_error(errors, "reserved_key",
				("layer %s sets 'sequence'; whole-ride ordering and recipe pins are reserved " +
				"for a future version and rejected by the version-1 validator (%s)") %
				[label, _unregistered_reason("sequence.order")],
				{"layer": label, "key": "sequence"})
			continue
		if not _DOCUMENT_FIELDS.has(field):
			_error(errors, "unknown_key",
				("layer %s sets unknown key '%s'; version 1 accepts %s and there is no generic " +
				"catalog-key escape hatch%s") %
				[label, field, str(_DOCUMENT_FIELDS), _unregistered_suffix(field)],
				{"layer": label, "key": field})
			continue
		if field == "constraints":
			_read_constraints(layer, value, by_id, first_seen, errors)
			continue
		scalars[field] = value
		sources[field] = {"layer": str(layer.layer), "label": label,
			"argument": int(layer.argument)}


static func _read_constraints(layer: Dictionary, value: Variant, by_id: Dictionary,
		first_seen: Array, errors: Array) -> void:
	var label := str(layer.label)
	if not value is Dictionary:
		_error(errors, "constraints_shape",
			("layer %s declares 'constraints' as a %s; it must be a dictionary of 'required' " +
			"and 'preferred' lists") % [label, type_string(typeof(value))], {"layer": label})
		return
	var buckets: Array = (value as Dictionary).keys()
	buckets.sort()
	var seen_in_layer := {}
	for bucket_name: Variant in buckets:
		var bucket := str(bucket_name)
		if bucket != BUCKET_REQUIRED and bucket != BUCKET_PREFERRED:
			_error(errors, "unknown_key",
				("layer %s declares constraint bucket '%s'; version 1 has only 'required' and " +
				"'preferred'") % [label, bucket], {"layer": label})
			continue
		var entries: Variant = (value as Dictionary)[bucket_name]
		if not entries is Array:
			_error(errors, "constraints_shape",
				"layer %s declares constraints.%s as a %s; it must be a list" %
				[label, bucket, type_string(typeof(entries))], {"layer": label})
			continue
		for position in (entries as Array).size():
			var raw: Variant = (entries as Array)[position]
			if not raw is Dictionary:
				_error(errors, "constraints_shape",
					"layer %s declares constraints.%s[%d] as a %s; it must be a record" %
					[label, bucket, position, type_string(typeof(raw))], {"layer": label})
				continue
			var record := _read_constraint(layer, bucket, position, raw, errors)
			if record.is_empty():
				continue
			var id := str(record.id)
			if seen_in_layer.has(id):
				_error(errors, "duplicate_constraint_id",
					("layer %s declares constraint ID '%s' twice; duplicate IDs inside one " +
					"layer are errors, not merges") % [label, id], {"layer": label, "id": id})
				continue
			seen_in_layer[id] = true
			if by_id.has(id):
				var prior: Dictionary = by_id[id]
				if str(prior.scope) != str(record.scope) or str(prior.key) != str(record.key):
					_error(errors, "constraint_id_rebound",
						("layer %s reuses constraint ID '%s' for (scope '%s', key '%s') after " +
						"layer %s used it for (scope '%s', key '%s'); a later layer " +
						"replaces an earlier record only when scope and key are unchanged") %
						[label, id, record.scope, record.key, prior.source_label, prior.scope, prior.key],
						{"layer": label, "id": id})
					continue
			else:
				first_seen.append(id)
			by_id[id] = record


static func _read_constraint(layer: Dictionary, bucket: String, position: int,
		raw: Dictionary, errors: Array) -> Dictionary:
	var label := str(layer.label)
	var where := "layer %s constraints.%s[%d]" % [label, bucket, position]
	var fields: Array = raw.keys()
	fields.sort()
	for field_name: Variant in fields:
		var field := str(field_name)
		if not _CONSTRAINT_FIELDS.has(field):
			_error(errors, "unknown_key",
				"%s declares unknown field '%s'; a version-1 constraint carries %s" %
				[where, field, str(_CONSTRAINT_FIELDS)], {"layer": label})
			return {}
		if raw[field_name] == null:
			_error(errors, "null_value",
				"%s sets '%s' to null; explicit null is invalid in version 1" % [where, field],
				{"layer": label})
			return {}
	if not raw.has("scope") or not raw.scope is String or str(raw.scope).is_empty():
		_error(errors, "constraints_shape",
			"%s declares no scope; every constraint names the story slot or 'ride' it binds to" %
			where, {"layer": label})
		return {}
	if not raw.has("key") or not raw.key is String or str(raw.key).is_empty():
		_error(errors, "constraints_shape", "%s declares no key" % where, {"layer": label})
		return {}
	var scope := str(raw.scope)
	var key := str(raw.key)
	var id := str(raw.get("id", _auto_id(scope, key)))
	if id.is_empty():
		_error(errors, "constraints_shape", "%s declares an empty constraint ID" % where,
			{"layer": label})
		return {}
	var record := {
		"id": id, "scope": scope, "key": key, "bucket": bucket,
		"source_layer": str(layer.layer), "source_label": label,
		"source_order": int(layer.order), "source_argument": int(layer.argument),
		"source_position": position, "where": where,
	}
	return _with_values(record, raw)


# -- validation -----------------------------------------------------------------------------

static func _validate_scalars(scalars: Dictionary, errors: Array) -> void:
	var version: Variant = scalars.get(DOCUMENT_VERSION_FIELD, VERSION)
	if not _is_integer(version) or int(version) != VERSION:
		_error(errors, "infeasible_value",
			"ride_config_version is %s; this build speaks version %d only" %
			[str(version), VERSION], {"key": DOCUMENT_VERSION_FIELD})
	var preset: Variant = scalars.get(KEY_PRESET, PRESET_ID)
	if not preset is String or str(preset) != PRESET_ID:
		_error(errors, "infeasible_value",
			("preset '%s' is not available at scope 'ride'; the catalogued domain is %s " +
			"(conflict: only one preset is shipped and gated)") % [str(preset), str([PRESET_ID])],
			{"key": KEY_PRESET, "scope": "ride"})
	var seed_value: Variant = scalars.get(KEY_SEED, PRESET_SEED)
	if not _is_integer(seed_value):
		_error(errors, "infeasible_value",
			("seed '%s' is not an integer at scope 'ride'; the domain is a signed 64-bit " +
			"integer (conflict: the seed selects every named decision stream and cannot " +
			"be fractional)") % str(seed_value), {"key": KEY_SEED, "scope": "ride"})
	else:
		scalars[KEY_SEED] = int(seed_value)


static func _validate_constraint(record: Dictionary, errors: Array) -> bool:
	var key := str(record.key)
	var scope := str(record.scope)
	var where := str(record.where)
	var entry := registry_entry(key)
	if entry.is_empty():
		return _error(errors, "unknown_key",
			"%s constrains unknown key '%s'; version 1 registers %s%s" %
			[where, key, str(_registered_keys()), _unregistered_suffix(key)],
			{"key": key, "scope": scope})
	if str(entry.form) != "constraint":
		return _error(errors, "unknown_key",
			("%s constrains '%s', which is a scalar document field rather than a constraint " +
			"key; set it as '%s: <value>' instead") % [where, key, key],
			{"key": key, "scope": scope})
	var operator := str(entry.operator)
	var expected_bucket := BUCKET_REQUIRED if operator == "required equality" \
		else BUCKET_PREFERRED
	if str(record.bucket) != expected_bucket:
		return _error(errors, "operator_mismatch",
			("%s declares '%s' as a %s constraint; the registry declares operator '%s', so it " +
			"belongs in constraints.%s") % [where, key, record.bucket, operator, expected_bucket],
			{"key": key, "scope": scope})
	if not _slot_exists(scope):
		return _error(errors, "unknown_slot",
			("%s names slot '%s', which the %s grammar does not author; the legal scopes for " +
			"'%s' are %s") % [where, scope, PRESET_ID, key, str(entry.scopes)],
			{"key": key, "scope": scope})
	if not (entry.scopes as Array).has(scope):
		return _error(errors, "scope_not_legal",
			("%s binds '%s' to slot '%s', which is not a legal scope for that key; the legal " +
			"scopes are %s (conflict: no other slot has a draw range certified at both " +
			"extremes)") % [where, key, scope, str(entry.scopes)], {"key": key, "scope": scope})
	var field := _value_field(entry)
	for other in _VALUE_FIELDS:
		if other != field and record.has(other):
			return _error(errors, "operator_mismatch",
				("%s supplies '%s' for key '%s'; its registered operator is '%s', which reads " +
				"'%s' only (no version-1 key takes a target/tolerance pair)") %
				[where, other, key, operator, field], {"key": key, "scope": scope})
	if not record.has(field):
		return _error(errors, "operator_mismatch",
			"%s supplies no '%s' for key '%s' (registered operator '%s')" %
			[where, field, key, operator], {"key": key, "scope": scope})
	if key == KEY_SLOT_INTENSITY:
		return _validate_intensity(record, entry, errors)
	return true


static func _validate_intensity(record: Dictionary, entry: Dictionary, errors: Array) -> bool:
	var scope := str(record.scope)
	var choice: Variant = record.choice
	if choice is String and (entry.domain as Array).has(str(choice)):
		return true
	return _error(errors, "infeasible_value",
		("%s requests intensity '%s' at scope '%s', which is not catalogued; the catalogued " +
		"choices are %s and that scope's conservative capability is %s " +
		"(conflict: an uncatalogued choice has no certified mapping onto those ranges)") %
		[str(record.where), str(choice), scope, str(entry.domain), _capability_text(scope)],
		{"key": KEY_SLOT_INTENSITY, "scope": scope, "capability": _capability(scope)})


static func _capability(scope: String) -> Array:
	var ranges: Array = []
	for key: String in INTENSITY_PINNED_KEYS.get(scope, []):
		var band := certified_range(scope, key)
		ranges.append({"key": key, "range": [band.x, band.y]})
	return ranges


static func _capability_text(scope: String) -> String:
	var parts := PackedStringArray()
	for record: Dictionary in _capability(scope):
		var band: Array = record.range
		parts.append("%s/%s %.5f..%.5f" % [scope, record.key, band[0], band[1]])
	if parts.is_empty():
		return "no certified draw"
	return String(", ").join(parts)


static func _slot_exists(scope: String) -> bool:
	if scope == "ride":
		return true
	return RidePlannerScript.canonical_role_ids().has(scope)


static func _registered_keys() -> Array:
	var keys: Array = []
	for entry: Dictionary in REGISTRY:
		keys.append(str(entry.key))
	return keys


static func _unregistered_reason(key: String) -> String:
	for entry: Dictionary in UNREGISTERED:
		if str(entry.key) == key:
			return str(entry.reason)
	return ""


static func _unregistered_suffix(key: String) -> String:
	var reason := _unregistered_reason(key)
	if reason.is_empty():
		return ""
	return "; '%s' is deliberately unregistered: %s" % [key, reason]


# -- ordering and output --------------------------------------------------------------------

## Design §3 rule 5: source layer from highest to lowest precedence, then original list position,
## then the stable ID as the final tie-breaker.
static func _precedence_before(left: Dictionary, right: Dictionary) -> bool:
	if int(left.source_order) != int(right.source_order):
		return int(left.source_order) > int(right.source_order)
	if int(left.source_position) != int(right.source_position):
		return int(left.source_position) < int(right.source_position)
	return str(left.id) < str(right.id)


static func _public_constraint(record: Dictionary) -> Dictionary:
	var public := _with_values(
		{"id": str(record.id), "scope": str(record.scope), "key": str(record.key)}, record)
	public.merge({"source_layer": str(record.source_layer),
		"source_label": str(record.source_label),
		"source_argument": int(record.source_argument),
		"source_position": int(record.source_position)}, true)
	return public


## Copy whichever operator value fields the source carries, in declared order.
static func _with_values(target: Dictionary, source: Dictionary) -> Dictionary:
	for field in _VALUE_FIELDS:
		if source.has(field):
			target[field] = source[field]
	return target


static func _initial_report(resolved: Dictionary) -> Dictionary:
	var preferences: Array = []
	var constraints: Dictionary = resolved.get("constraints", {})
	for record: Dictionary in constraints.get(BUCKET_PREFERRED, []):
		preferences.append({
			"id": str(record.id), "scope": str(record.scope), "key": str(record.key),
			"request": record.get("choice", record.get("target")),
			"achieved": null, "delta": null, "status": "pending",
			"reason": "achieved value is filled after planning", "achieved_targets": {},
		})
	return {
		"config_hash": str(resolved.get("config_hash", "")),
		"preset": str(resolved.get(KEY_PRESET, "")), "seed": int(resolved.get(KEY_SEED, 0)),
		"required": constraints.get(BUCKET_REQUIRED, []).duplicate(true),
		"preferences": preferences,
	}


static func _is_integer(value: Variant) -> bool:
	if value is bool:
		return false
	if value is int:
		return true
	# A JSON round-trip can hand an integral document value back as a float; accept that, and
	# only that, so `seed: 42.5` stays the error it should be.
	return value is float and is_finite(float(value)) and float(value) == floor(float(value))


## Append one structured error and report the failure, so a validator reads `return _error(...)`.
static func _error(errors: Array, code: String, message: String, extra: Dictionary = {}) -> bool:
	var record := {"code": code, "message": message}
	record.merge(extra, true)
	errors.append(record)
	return false
