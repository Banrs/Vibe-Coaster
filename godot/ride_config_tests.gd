extends SceneTree

## Focused suite for the version-1 configuration surface: the registry contract, the overlay
## algebra of design §3 rules 1-7, strict rejection of everything version 1 does not register,
## and the two build properties the surface stands on — a configured build pins the certified
## draws it claims to pin, and an unconfigured one is still the preset fast path, byte for byte.

const RideConfig := preload("res://ride_config.gd")
const RideGenerator := preload("res://generator.gd")
const RidePlanner := preload("res://ride_planner.gd")
const RouteContract := preload("res://route_contract.gd")
const RideVerify := preload("res://verify.gd")

const PRESET_SEED := 42
const CONFIGURED_SEED := 11
const ROUTE_LENGTH_BAND_M := Vector2(7800.0, 8200.0)
## Recorded so the canonical form itself is pinned: a change to canonical ordering, to the
## hashed payload, or to the preset base moves this, and that must be a deliberate edit.
const EMPTY_CONFIG_HASH := "cc0fa4bc5c663ffd5a26af2dee7e0d4831f39a10c08091c6a0ebe69f3c5ab928"

var _t := TestUtil.new()


func _initialize() -> void:
	_test_registry_declares_the_version_one_contract()
	_test_normalization_is_deterministic()
	_test_overlay_precedence_and_cli_order()
	_test_duplicate_and_ambiguous_constraint_ids()
	_test_unknown_keys_and_slots_are_rejected()
	_test_explicit_null_is_rejected()
	_test_infeasible_values_are_rejected_with_scope_range_and_conflict()
	_test_hash_is_source_independent_and_value_sensitive()
	_test_intensity_maps_onto_the_certified_thirds()
	_test_configured_build_pins_reports_and_repeats()
	_test_empty_config_is_the_preset_fast_path()
	_t.finish(self)


func _test_registry_declares_the_version_one_contract() -> void:
	var keys: Array = []
	for entry: Dictionary in RideConfig.registry():
		keys.append(str(entry.key))
		for field in ["type", "unit", "scope", "scopes", "form", "operator", "domain", "owner",
				"feasibility_phase"]:
			_t.expect(entry.has(field) and str(entry[field]) != "",
				"registry entry %s declares %s" % [entry.key, field])
	_t.expect(keys == ["preset", "seed", "slot.intensity"],
		"version 1 registers exactly preset, seed and slot.intensity; observed %s" % str(keys))
	var refused: Array = []
	for entry: Dictionary in RideConfig.unregistered():
		refused.append(str(entry.key))
		_t.expect(str(entry.get("reason", "")).length() > 80 \
			and not str(entry.get("blocked_by", "")).is_empty() \
			and not str(entry.get("evidence", "")).is_empty(),
			"unregistered key %s records its measured reason, blocker and evidence" % entry.key)
	for key in ["slot.recipe", "slot.enabled", "ride.duration_s", "ride.peak_speed_mps",
			"slot.structure_height_m", "slot.airtime_character", "sequence.order"]:
		_t.expect(refused.has(key), "the registry records why '%s' is unregistered" % key)
	for scope in RideConfig.INTENSITY_SCOPES:
		for key: String in RideConfig.INTENSITY_PINNED_KEYS[scope]:
			_t.expect(RideConfig.certified_range(scope, key) != Vector2.ZERO,
				"intensity scope %s/%s names a range the planner actually certifies"
					% [scope, key])


func _test_normalization_is_deterministic() -> void:
	var document := {"seed": 11, "constraints": {"preferred": [
		{"id": "float_a", "scope": "return-height-a", "key": "slot.intensity", "choice": "low"},
	]}}
	var first := RideConfig.normalize(document, ["return-height-b/slot.intensity=high"])
	var repeat := RideConfig.normalize(document, ["return-height-b/slot.intensity=high"])
	_t.expect(first.ok and repeat.ok, "a legal document normalizes: %s"
		% str(RideConfig.error_messages(first.errors)))
	_t.expect(var_to_bytes(first.resolved) == var_to_bytes(repeat.resolved),
		"normalization of one document is bit-identical when repeated")
	_t.expect(var_to_bytes(first.report) == var_to_bytes(repeat.report),
		"the resolution report of one document is bit-identical when repeated")
	var empty := RideConfig.normalize({})
	_t.expect(empty.ok and int(empty.resolved.seed) == PRESET_SEED \
		and str(empty.resolved.preset) == RideConfig.PRESET_ID,
		"an empty document inherits the preset base whole")
	_t.expect(str(empty.resolved.config_hash) == EMPTY_CONFIG_HASH,
		"the canonical preset hash is the recorded value, observed %s"
			% str(empty.resolved.config_hash))
	_t.expect(empty.report.preferences.is_empty(),
		"an unconfigured document reports no preferences")


func _test_overlay_precedence_and_cli_order() -> void:
	var file_config := {"seed": 11, "constraints": {"preferred": [
		{"id": "float_a", "scope": "return-height-a", "key": "slot.intensity",
			"choice": "low"},
	]}}
	var result := RideConfig.normalize(file_config, ["seed=7", "seed=8",
		"float_a@return-height-a/slot.intensity=high"])
	_t.expect(result.ok, "the layered document normalizes: %s"
		% str(RideConfig.error_messages(result.errors)))
	_t.expect(int(result.resolved.seed) == 8,
		"the last CLI override wins in argument order, observed %d" % int(result.resolved.seed))
	_t.expect(str(result.resolved.sources.seed.label) == "cli[1]",
		"the effective seed retains the layer that supplied it, observed %s"
			% str(result.resolved.sources.seed.label))
	_t.expect(str(result.resolved.preset) == RideConfig.PRESET_ID \
		and str(result.resolved.sources.preset.label) == "preset",
		"an omitted field inherits the preset layer below")
	var preferred: Array = result.resolved.constraints.preferred
	_t.expect(preferred.size() == 1, "one ID over two layers stays one effective constraint")
	if preferred.size() == 1:
		var record: Dictionary = preferred[0]
		_t.expect(str(record.choice) == "high" and str(record.source_layer) == "cli",
			"a later layer replaces the same ID when scope and key are unchanged")
		_t.expect(int(record.source_argument) == 2 and int(record.source_position) == 0,
			"the effective record retains its source layer and list position")
	var ordered := RideConfig.normalize({"constraints": {"preferred": [
		{"id": "float_b", "scope": "return-height-b", "key": "slot.intensity",
			"choice": "low"},
		{"id": "float_a", "scope": "return-height-a", "key": "slot.intensity",
			"choice": "low"},
	]}}, ["float_a@return-height-a/slot.intensity=high"])
	_t.expect(ordered.ok, "the ordering document normalizes: %s"
		% str(RideConfig.error_messages(ordered.errors)))
	var ids: Array = []
	for record: Dictionary in ordered.resolved.constraints.preferred:
		ids.append(str(record.id))
	_t.expect(ids == ["float_a", "float_b"],
		"preferences order by source layer first and list position second, observed %s"
			% str(ids))


func _test_duplicate_and_ambiguous_constraint_ids() -> void:
	var duplicate := RideConfig.normalize({"constraints": {"preferred": [
		{"id": "float_a", "scope": "return-height-a", "key": "slot.intensity",
			"choice": "low"},
		{"id": "float_a", "scope": "return-height-a", "key": "slot.intensity",
			"choice": "high"},
	]}})
	_expect_error(duplicate, "duplicate_constraint_id",
		"a duplicate constraint ID inside one layer is an error")
	var rebound := RideConfig.normalize({"constraints": {"preferred": [
		{"id": "float", "scope": "return-height-a", "key": "slot.intensity", "choice": "low"},
	]}}, ["float@return-height-b/slot.intensity=high"])
	_expect_error(rebound, "constraint_id_rebound",
		"reusing an ID for a different (scope, key) across layers is an error")
	var ambiguous := RideConfig.normalize({"constraints": {"preferred": [
		{"id": "float_a", "scope": "return-height-a", "key": "slot.intensity",
			"choice": "low"},
		{"id": "float_a_again", "scope": "return-height-a", "key": "slot.intensity",
			"choice": "high"},
	]}})
	_expect_error(ambiguous, "ambiguous_constraint",
		"two effective IDs for one (scope, key) are rejected as ambiguous")


func _test_unknown_keys_and_slots_are_rejected() -> void:
	_expect_error(RideConfig.normalize({"ride": {"duration_s": 205.0}}), "unknown_key",
		"an unknown top-level field is an error, not a merge")
	var duration := RideConfig.normalize({"ride.duration_s": 205.0})
	_expect_error(duration, "unknown_key", "ride.duration_s is not a version-1 key")
	_expect_message(duration, "157.54-157.84",
		"the unknown-key error for a refused design key carries its measured reason")
	var recipe := RideConfig.normalize({"constraints": {"required": [
		{"id": "inversion_recipe", "scope": "act-one-immelmann", "key": "slot.recipe",
			"value": "giant_immelmann"},
	]}})
	_expect_error(recipe, "unknown_key", "slot.recipe is not a version-1 key")
	_expect_message(recipe, "24 act-one pool permutations",
		"the slot.recipe rejection carries the permutation sweep that refused it")
	_expect_error(RideConfig.normalize({"sequence": {"pinned": {}}}), "reserved_key",
		"sequence ordering and pins are reserved and rejected by the version-1 validator")
	var unknown_slot := RideConfig.normalize({"constraints": {"preferred": [
		{"id": "x", "scope": "act-one-carousel", "key": "slot.intensity", "choice": "low"},
	]}})
	_expect_error(unknown_slot, "unknown_slot", "an unknown story slot is an error")
	var illegal_scope := RideConfig.normalize({"constraints": {"preferred": [
		{"id": "x", "scope": "act-one-loop", "key": "slot.intensity", "choice": "low"},
	]}})
	_expect_error(illegal_scope, "scope_not_legal",
		"a real slot outside the key's legal scope is an error")
	_expect_message(illegal_scope, "return-height-a",
		"the illegal-scope error names the legal scopes")
	_expect_error(RideConfig.normalize({"constraints": {"preferred": [
		{"id": "x", "scope": "ride", "key": "seed", "choice": 3},
	]}}), "unknown_key", "a scalar field cannot be smuggled in as a constraint")
	_expect_error(RideConfig.normalize({}, ["return-height-a/slot.intensity"]),
		"cli_override_syntax", "a CLI override that is not an assignment is an error")
	_expect_error(RideConfig.normalize({}, [42]), "cli_override_type",
		"a CLI override that is neither string nor dictionary is an error")


func _test_explicit_null_is_rejected() -> void:
	_expect_error(RideConfig.normalize({"seed": null}), "null_value",
		"an explicitly null scalar is invalid; version 1 has no reset operator")
	_expect_error(RideConfig.normalize({"constraints": {"preferred": [
		{"id": "x", "scope": "return-height-a", "key": "slot.intensity", "choice": null},
	]}}), "null_value", "an explicitly null constraint field is invalid")


func _test_infeasible_values_are_rejected_with_scope_range_and_conflict() -> void:
	var uncatalogued := RideConfig.normalize({"constraints": {"preferred": [
		{"id": "float_a", "scope": "return-height-a", "key": "slot.intensity",
			"choice": "extreme"},
	]}})
	_expect_error(uncatalogued, "infeasible_value",
		"an uncatalogued enum choice is rejected")
	for fragment in ["return-height-a", "3.65000..3.95000", "0.95000..1.05000", "conflict",
			"low", "medium", "high"]:
		_expect_message(uncatalogued, fragment,
			"the infeasible-value error names %s" % fragment)
	var wrong_preset := RideConfig.normalize({"preset": "future-hybrid@1"})
	_expect_error(wrong_preset, "infeasible_value", "an unavailable preset is rejected")
	_expect_message(wrong_preset, "material-v1",
		"the preset rejection names the catalogued domain")
	_expect_error(RideConfig.normalize({"seed": 42.5}), "infeasible_value",
		"a fractional seed is rejected")
	_t.expect(RideConfig.normalize({"seed": 42.0}).ok,
		"an integral seed survives a JSON round-trip that made it a float")
	_expect_error(RideConfig.normalize({"ride_config_version": 2}), "infeasible_value",
		"a future document version is rejected rather than guessed at")
	var wrong_operator := RideConfig.normalize({"constraints": {"preferred": [
		{"id": "float_a", "scope": "return-height-a", "key": "slot.intensity",
			"target": 3.9, "tolerance": 0.05},
	]}})
	_expect_error(wrong_operator, "operator_mismatch",
		"a target/tolerance pair on a preferred-choice key is rejected")
	var wrong_bucket := RideConfig.normalize({"constraints": {"required": [
		{"id": "float_a", "scope": "return-height-a", "key": "slot.intensity",
			"choice": "high"},
	]}})
	_expect_error(wrong_bucket, "operator_mismatch",
		"a preferred-choice key declared as a required constraint is rejected")


func _test_hash_is_source_independent_and_value_sensitive() -> void:
	var from_file := RideConfig.normalize({"seed": 7})
	var from_cli := RideConfig.normalize({}, ["seed=7"])
	_t.expect(str(from_file.resolved.config_hash) == str(from_cli.resolved.config_hash),
		"the canonical hash covers effective values, not the layer they came from")
	_t.expect(var_to_bytes(from_file.resolved.sources) != var_to_bytes(from_cli.resolved.sources),
		"provenance still records which layer supplied the value")
	var low := RideConfig.normalize({"constraints": {"preferred": [
		{"id": "float_a", "scope": "return-height-a", "key": "slot.intensity",
			"choice": "low"},
	]}})
	var high := RideConfig.normalize({"constraints": {"preferred": [
		{"id": "float_a", "scope": "return-height-a", "key": "slot.intensity",
			"choice": "high"},
	]}})
	_t.expect(low.ok and high.ok, "both intensity documents normalize")
	_t.expect(str(low.resolved.config_hash) != str(high.resolved.config_hash),
		"a different catalogued choice hashes differently")
	_t.expect(str(low.resolved.config_hash) != EMPTY_CONFIG_HASH,
		"a configured document hashes differently from the bare preset")
	var both_in_file := RideConfig.normalize({"constraints": {"preferred": [
		{"id": "float_a", "scope": "return-height-a", "key": "slot.intensity",
			"choice": "low"},
		{"id": "float_b", "scope": "return-height-b", "key": "slot.intensity",
			"choice": "high"},
	]}})
	var split_over_layers := RideConfig.normalize({"constraints": {"preferred": [
		{"id": "float_a", "scope": "return-height-a", "key": "slot.intensity",
			"choice": "low"},
	]}}, ["float_b@return-height-b/slot.intensity=high"])
	_t.expect(both_in_file.ok and split_over_layers.ok, "both layered documents normalize")
	_t.expect(str(both_in_file.resolved.config_hash) == str(split_over_layers.resolved.config_hash),
		"the same effective constraint set hashes the same whichever layer supplied each record")


func _test_intensity_maps_onto_the_certified_thirds() -> void:
	for scope: String in RideConfig.INTENSITY_SCOPES:
		for choice: String in RideConfig.INTENSITY_CHOICES:
			var result := RideConfig.normalize({"constraints": {"preferred": [
				{"id": "float", "scope": scope, "key": "slot.intensity", "choice": choice},
			]}})
			_t.expect(result.ok, "%s at %s normalizes: %s"
				% [choice, scope, str(RideConfig.error_messages(result.errors))])
			var pins: Array = RideConfig.planner_pins(result.resolved)
			var expected: Array = RideConfig.INTENSITY_PINNED_KEYS[scope]
			_t.expect(pins.size() == expected.size(),
				"%s at %s pins %d certified draw(s)" % [choice, scope, expected.size()])
			var index := RideConfig.INTENSITY_CHOICES.find(choice)
			for pin: Dictionary in pins:
				var band := RideConfig.certified_range(scope, str(pin.key))
				var third_low := lerpf(band.x, band.y, float(index) / 3.0)
				var third_high := lerpf(band.x, band.y, float(index + 1) / 3.0)
				var value := float(pin.value)
				_t.expect(value > third_low and value < third_high,
					"%s pins %s/%s to %.6f, inside the %s third %.6f..%.6f"
						% [choice, scope, pin.key, value, choice, third_low, third_high])
				_t.expect(value >= band.x and value <= band.y,
					"%s pins %s/%s inside the certified range %.6f..%.6f"
						% [choice, scope, pin.key, band.x, band.y])
				_t.expect(str(pin.stream) == RidePlanner.TARGET_STREAM_PREFIX + scope,
					"the pin names the decision stream it replaces")


func _test_configured_build_pins_reports_and_repeats() -> void:
	var high := _intensity_config("high", "high")
	var built := RideGenerator.build_config(high)
	_t.expect(built.ok, "a configured build succeeds: %s"
		% str(RideConfig.error_messages(built.errors)))
	if not built.ok:
		return
	_t.expect(int(built.route.seed) == CONFIGURED_SEED, "the build uses the resolved seed")
	var targets: Dictionary = built.plan.decisions.targets
	var pins: Array = RideConfig.planner_pins(built.resolved_config)
	_t.expect(pins.size() == 3, "the two height slots pin three certified draws")
	for pin: Dictionary in pins:
		var resolved_value := float(targets[pin.role_id][pin.key])
		var band := RideConfig.certified_range(str(pin.role_id), str(pin.key))
		_t.expect(is_equal_approx(resolved_value, float(pin.value)),
			"%s/%s resolves to the pinned %.6f, observed %.6f"
				% [pin.role_id, pin.key, float(pin.value), resolved_value])
		_t.expect(resolved_value >= band.x and resolved_value <= band.y,
			"%s/%s resolves inside its certified range" % [pin.role_id, pin.key])
	var pinned_count := 0
	for draw: Dictionary in built.plan.decisions.draws:
		_t.expect(draw.has("stream") and draw.has("pinned_by_config"),
			"a configured plan records {stream, pinned_by_config} for every draw")
		if bool(draw.get("pinned_by_config", false)):
			pinned_count += 1
	_t.expect(pinned_count == 3, "exactly the pinned draws are marked, observed %d" % pinned_count)
	for entry: Dictionary in built.report.preferences:
		_t.expect(str(entry.status) == "achieved" and float(entry.delta) == 0.0 \
			and str(entry.achieved) == str(entry.request),
			"preference %s reports request, achieved, delta, status and reason: %s"
				% [entry.id, str(entry)])
	var repeat := RideGenerator.build_config(high)
	_t.expect(repeat.ok and var_to_bytes(repeat.route) == var_to_bytes(built.route),
		"the same configuration and seed build a bit-identical ride")
	_certify(built, "high/high")
	var floated := RideGenerator.build_config(_intensity_config("low", "low"))
	_t.expect(floated.ok, "the low-intensity configuration builds: %s"
		% str(RideConfig.error_messages(floated.errors)))
	if floated.ok:
		var low_peak := float(floated.plan.decisions.targets["return-height-a"].peak_g)
		var high_peak := float(built.plan.decisions.targets["return-height-a"].peak_g)
		_t.expect(low_peak < high_peak,
			"low pulls the return height beats less hard than high (%.4f vs %.4f)"
				% [low_peak, high_peak])
		_t.expect(var_to_bytes(floated.route) != var_to_bytes(built.route),
			"the intensity choice reaches the published ride")
		_certify(floated, "low/low")
	# The two height slots are separately effective: a mixed document must float height-b
	# differently from height-a rather than quietly coupling them.
	var mixed := RideGenerator.build_config(_intensity_config("low", "high"))
	_t.expect(mixed.ok, "a mixed-intensity configuration builds: %s"
		% str(RideConfig.error_messages(mixed.errors)))
	if mixed.ok:
		var targets_a := float(mixed.plan.decisions.targets["return-height-a"].unload_scale)
		var targets_b := float(mixed.plan.decisions.targets["return-height-b"].unload_scale)
		_t.expect(targets_a < targets_b,
			"each height slot takes its own catalogued choice (%.5f vs %.5f)"
				% [targets_a, targets_b])


func _test_empty_config_is_the_preset_fast_path() -> void:
	var preset := RideGenerator.build(PRESET_SEED)
	var configured := RideGenerator.build_config({})
	_t.expect(configured.ok, "the empty configuration builds: %s"
		% str(RideConfig.error_messages(configured.errors)))
	if not configured.ok:
		return
	_t.expect(var_to_bytes(configured.route) == var_to_bytes(preset),
		"build_config({}) publishes exactly the route build(%d) does" % PRESET_SEED)
	for draw: Dictionary in configured.plan.decisions.draws:
		_t.expect(not draw.has("pinned_by_config"),
			"an unconfigured build publishes the draws it always did, with no added field")
	var rejected := RideGenerator.build_config({"preset": "nope"})
	_t.expect(not rejected.ok and rejected.route.is_empty() and not rejected.errors.is_empty(),
		"an invalid configuration is rejected before anything is generated")


func _intensity_config(choice_a: String, choice_b: String) -> Dictionary:
	return {"seed": CONFIGURED_SEED, "constraints": {"preferred": [
		{"id": "float_a", "scope": "return-height-a", "key": "slot.intensity",
			"choice": choice_a},
		{"id": "float_b", "scope": "return-height-b", "key": "slot.intensity",
			"choice": choice_b},
	]}}


## A registered key claims that every catalogued choice builds an *accepted* ride, so the two
## extremes of the catalogue are validated end to end here, exactly as the planner suite
## validates the extremes of the ranges this key pins.
func _certify(built: Dictionary, label: String) -> void:
	var route: Dictionary = built.route
	var issues := PackedStringArray()
	RideVerify.validate_structure(route, issues)
	RideVerify.validate_seams(route, issues)
	RideVerify.validate_clearance(route, route.terrain, issues)
	RideVerify.validate_self_clearance(route, issues)
	var analysis: Dictionary = RideVerify.analyze(route, RouteContract.ROW_OFFSETS)
	RideVerify.validate_loads(analysis, issues)
	_t.expect(issues.is_empty(), "intensity %s on seed %d validates: %s"
		% [label, CONFIGURED_SEED, str(issues)])
	_t.expect(float(route.length) >= ROUTE_LENGTH_BAND_M.x \
		and float(route.length) <= ROUTE_LENGTH_BAND_M.y,
		"intensity %s keeps the route inside %.0f..%.0f m, observed %.2f"
			% [label, ROUTE_LENGTH_BAND_M.x, ROUTE_LENGTH_BAND_M.y, float(route.length)])


func _expect_error(result: Dictionary, code: String, message: String) -> void:
	if result.ok:
		_t.expect(false, "%s (accepted instead)" % message)
		return
	for record: Dictionary in result.errors:
		if str(record.get("code", "")) == code:
			return
	_t.expect(false, "%s; expected code '%s', observed %s"
		% [message, code, str(RideConfig.error_messages(result.errors))])


func _expect_message(result: Dictionary, fragment: String, message: String) -> void:
	for text in RideConfig.error_messages(result.errors):
		if text.contains(fragment):
			return
	_t.expect(false, "%s; no error mentioned '%s'" % [message, fragment])

