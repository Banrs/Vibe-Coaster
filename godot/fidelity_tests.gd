extends SceneTree

const FIDELITY_PATH := "res://fidelity.gd"
const REFERENCES_PATH := "res://fidelity_references.gd"
const GENERATOR_PATH := "res://generator.gd"
const CANONICAL_FLEET := RideFidelity.CANONICAL_FLEET


func _initialize() -> void:
	var _t := TestUtil.new()
	_t.errors = run()
	_t.finish(self)


static func run() -> PackedStringArray:
	var errors := PackedStringArray()
	if not ResourceLoader.exists(FIDELITY_PATH):
		errors.append("RideFidelity is missing")
		return errors
	var fidelity: Script = load(FIDELITY_PATH)
	_test_tolerance_oracle(errors)
	_test_native_input_boundary(fidelity, errors)
	_test_held_values(fidelity, errors)
	_test_exact_duration_hold(fidelity, errors)
	_test_time_weighted_pacing(fidelity, errors)
	_test_non_grid_measurement(fidelity, errors)
	_test_transition_windows(fidelity, errors)
	_test_straight_reconstruction(fidelity, errors)
	_test_constant_radius_reconstruction(fidelity, errors)
	_test_unclamped_radius_reconstruction(fidelity, errors)
	_test_force_integrity_mismatch(fidelity, errors)
	_test_nonuniform_quadratic_acceleration(fidelity, errors)
	_test_reconstruction_seam_channels(fidelity, errors)
	_test_route_reconstruction_embedding(fidelity, errors)
	_test_semantic_window_order(fidelity, errors)
	_test_catalog_validation(fidelity, errors)
	_test_catalog_v2_validation(fidelity, errors)
	_test_executable_promotion(fidelity, errors)
	_test_route_measurements(fidelity, errors)
	_test_reference_catalog(fidelity, errors)
	_test_comparison_catalog_contract(fidelity, errors)
	_test_target_classification(fidelity, errors)
	_test_comparison_reducers(fidelity, errors)
	_test_selector_and_row_resolution(fidelity, errors)
	_test_observed_only_and_evidence_gaps(fidelity, errors)
	_test_fleet_validation(fidelity, errors)
	_test_recommendation_eligibility(fidelity, errors)
	_test_recommendation_ranking(fidelity, errors)
	_test_comparison_determinism(fidelity, errors)
	return errors


static func _test_native_input_boundary(fidelity: Script, errors: PackedStringArray) -> void:
	if not ResourceLoader.exists(GENERATOR_PATH):
		errors.append("RideGenerator is missing")
		return
	var generator: Script = load(GENERATOR_PATH)
	var route: Variant = generator.build(42)
	_expect(errors, route is Dictionary, "generator build returns a Dictionary")
	if not route is Dictionary:
		return
	for key in ["positions", "tangents", "ups", "rights", "curvatures"]:
		_expect(errors, route.get(key) is PackedVector3Array, "generator keeps packed vector channel %s" % key)
	for key in [
		"banks", "speeds", "normal_g", "lateral_g", "longitudinal_g", "roll_rates",
		"distances", "times",
	]:
		_expect(errors, route.get(key) is PackedFloat32Array, "generator keeps packed float channel %s" % key)
	for key in ["span_indices", "gesture_indices", "propulsion_ids"]:
		_expect(errors, route.get(key) is PackedInt32Array, "generator keeps packed integer channel %s" % key)
	_expect(errors, route.get("gesture_windows") is Array, "generator exposes native gesture windows")
	_expect(errors, not route.has("sections"), "generator exposes no legacy sections")
	var before: Dictionary = route.duplicate(true)
	var measured: Dictionary = fidelity.measure_route(route, [0.0])
	_expect(errors, measured.get("schema_version") == 2, "native route measurement emits schema 2")
	_expect(errors, route == before, "native route measurement is read-only")
	for script_path in [FIDELITY_PATH, "res://_inspect.gd", "res://fidelity_tests.gd"]:
		var dependencies := ResourceLoader.get_dependencies(script_path)
		for forbidden_path in ["res://ride_route.gd", "res://motion_trajectory.gd", "res://legacy_route_adapter.gd"]:
			_expect(errors, not dependencies.has(forbidden_path), "%s does not import %s" % [script_path, forbidden_path])


static func _test_tolerance_oracle(errors: PackedStringArray) -> void:
	var oracle_errors := PackedStringArray()
	_expect_close_tol(oracle_errors, NAN, 0.0, 0.1, "non-finite actual")
	_expect(errors, oracle_errors.size() == 1, "tolerance oracle rejects a NaN actual value")


static func _test_held_values(fidelity: Script, errors: PackedStringArray) -> void:
	var positive := PackedFloat32Array([1.0, 2.0, 2.0, 2.0, 1.0])
	var negative := PackedFloat32Array([0.0, -1.0, -1.0, -1.0, 0.0])
	_expect_close(errors, fidelity.held(positive, 1.0, 0.02), 2.0, "three samples hold +2 g")
	_expect_close(errors, fidelity.held(negative, -1.0, 0.02), -1.0, "three samples hold -1 g")
	_expect(errors, is_inf(fidelity.held(positive, 1.0, 0.05)), "a hold longer than the series returns infinity")
	_expect_close(errors, fidelity.held(positive, 1.0, 0.0), 2.0, "zero-second hold retains peak semantics")


static func _test_exact_duration_hold(fidelity: Script, errors: PackedStringArray) -> void:
	var exact := PackedFloat32Array()
	exact.resize(81)
	exact.fill(-0.75)
	_expect_close(errors, fidelity.held(exact, -1.0, 0.8), -0.75, "81 samples contain exactly 0.8 seconds at 100 Hz")
	_expect(errors, fidelity.held(exact, -1.0, 0.804) == -INF, "81 samples do not contain a 0.804-second hold")
	var non_grid := PackedFloat32Array(exact)
	non_grid.append(-0.75)
	_expect_close(errors, fidelity.held(non_grid, -1.0, 0.804), -0.75, "82 samples contain the ceiling interval count for 0.804 seconds")


static func _test_time_weighted_pacing(fidelity: Script, errors: PackedStringArray) -> void:
	var measured: Dictionary = fidelity.measure_route(_irregular_pacing_route(), [0.0])
	var pacing: Dictionary = measured.beats[0].pacing
	_expect_close(errors, pacing.dead_zone_share, 0.2 / 1.3, "dead-zone share is weighted by elapsed seconds")
	_expect_close(errors, pacing.speed_share_200, 1.1 / 1.3, "speed share is weighted by elapsed seconds")


static func _test_non_grid_measurement(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _moving_window_route(false)
	var before: Dictionary = route.duplicate(true)
	var measured: Dictionary = fidelity.measure_route(route, [0.0])
	_expect(errors, route == before, "non-grid production measurement is read-only")
	if measured.get("beats", []).size() < 2:
		errors.append("moving fixture produces the selected beat")
		return
	var row: Dictionary = measured.beats[1].rows[0]
	_expect(errors, row.has("window_start_s") and row.has("window_end_s"), "row reports physical force-window bounds")
	if row.has("window_start_s"):
		_expect_close(errors, row.window_start_s, 0.003, "force grid anchors at the non-grid physical beat start")
	if row.has("window_end_s"):
		_expect_close(errors, row.window_end_s, 0.913, "force grid stops at the selected beat end")
	_expect(errors, row.window_seconds >= 0.81, "selected physical window supports a 0.804-second hold without crossing its end")
	var held_values: Dictionary = row.loads.get("normal_held_positive", {})
	var selected_held := float(held_values.get("0.80", -INF))
	_expect(errors, is_finite(selected_held) and selected_held < 2.0, "selected held value excludes the preceding higher-force beat")
	_expect(errors, not held_values.has("1.00"), "an unavailable hold never emits a numeric sentinel")
	var unavailable: Dictionary = held_values.get("_unavailable", {}).get("1.00", {})
	_expect(errors, unavailable.get("status", "") == "unavailable" and unavailable.get("reason", "") == "insufficient_duration", "an unavailable hold reports its physical-duration gap")
	var irregular_route := _moving_window_route(true)
	var irregular_before := irregular_route.duplicate(true)
	var irregular: Dictionary = fidelity.measure_route(irregular_route, [0.0])
	_expect(errors, irregular_route == irregular_before, "irregular-knot production measurement is read-only")
	if irregular.get("beats", []).size() >= 2:
		var irregular_held: Dictionary = irregular.beats[1].rows[0].loads.get("normal_held_positive", {})
		_expect_close(errors, float(irregular_held.get("0.80", -INF)), float(held_values.get("0.80", -INF)), "a collinear native knot outside the selected window leaves the held result unchanged")



static func _test_transition_windows(fidelity: Script, errors: PackedStringArray) -> void:
	var measured: Dictionary = fidelity.measure_route(_transition_route(1.5), [0.0])
	var flow: Dictionary = measured.beats[0].flow
	_expect(errors, flow.has("transition_before_s") and flow.has("transition_after_s"), "flow reports explicit before/after transition windows")
	if flow.has("transition_before_s") and flow.has("transition_after_s"):
		_expect_close(errors, flow.transition_before_s[0], 1.0, "before transition window begins 0.5 seconds before the seam")
		_expect_close(errors, flow.transition_before_s[1], 1.5, "before transition window ends at the seam")
		_expect_close(errors, flow.transition_after_s[0], 1.5, "after transition window begins at the seam")
		_expect_close(errors, flow.transition_after_s[1], 2.0, "after transition window ends 0.5 seconds after the seam")
	_expect_close(errors, flow.transition_force_swing, 4.0, "transition force swing compares before/after extrema")
	_expect_close(errors, flow.get("bank_handoff", -INF), 45.0, "transition reports the bank handoff across the seam")
	_expect_close(errors, flow.get("roll_rate_handoff", -INF), 75.0, "transition reports the roll-rate handoff across the seam")
	_expect_close(errors, flow.transition_seconds, 1.0, "full before/after transition windows span one second")
	var half_open: Dictionary = fidelity._time_window_extrema(
		PackedFloat32Array([0.0, 0.5, 1.0]), PackedFloat32Array([1.0, 1.0, 10.0]), 0.0, 1.0
	)
	_expect_close(errors, half_open.maximum, 1.0, "a transition's before window does not double-own its seam sample")
	var coarse_handoff: float = fidelity._seam_handoff(
		PackedFloat32Array([0.0, 0.99, 1.0, 1.01, 2.0]),
		PackedFloat32Array([-20.0, -20.0, 0.0, 25.0, 25.0]), 1.0
	)
	var refined_handoff: float = fidelity._seam_handoff(
		PackedFloat32Array([0.0, 0.99, 0.995, 1.0, 1.01, 2.0]),
		PackedFloat32Array([-20.0, -20.0, -10.0, 0.0, 25.0, 25.0]), 1.0
	)
	_expect_close(errors, coarse_handoff, 45.0, "transition handoff samples fixed physical offsets around the seam")
	_expect_close(errors, refined_handoff, coarse_handoff, "a collinear native knot does not change transition handoff")
	var boundary: Dictionary = fidelity.measure_route(_transition_route(0.3), [0.0])
	var boundary_flow: Dictionary = boundary.beats[0].flow
	_expect(errors, boundary_flow.get("status", "") == "evidence-gap" and boundary_flow.get("reason", "") == "boundary_unavailable", "boundary-limited transition reports unavailable evidence rather than zero")


static func _test_straight_reconstruction(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _analytic_straight_route(20.0, 2.0, 100.0)
	var before: Dictionary = route.duplicate(true)
	var channels: Dictionary = fidelity.reconstruct_channels(route)
	var repeated: Dictionary = fidelity.reconstruct_channels(route)
	_expect_close(errors, _max_abs(channels.curvature), 0.0, "straight route has zero geometric curvature")
	_expect_close(errors, _array_peak(channels.reconstructed_normal_g), 1.0, "level straight reconstructs one normal g")
	# Packed positions and times quantize independently, so raw second differences retain millig noise.
	_expect_close_tol(
		errors, _max_abs(channels.reconstructed_longitudinal_g), 0.0, 0.005,
		"constant speed reconstructs near-zero longitudinal proper g"
	)
	_expect(errors, channels.radius_m.size() == route.positions.size() and channels.radius_unbounded.size() == route.positions.size(), "straight radius arrays match the raw sample count")
	for index in route.positions.size():
		_expect(errors, channels.radius_m[index] == null and channels.radius_unbounded[index], "straight radius sample %d is JSON-safe and unbounded" % index)
	_expect(errors, not channels.has("comparison_channels"), "raw reconstruction does not invent source filtering")
	_expect(errors, route == before, "reconstruction does not mutate the route")
	_expect(errors, channels == repeated, "reconstruction is deterministic")


static func _test_constant_radius_reconstruction(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _analytic_circle_route(25.0, 50.0, 4.0, 100.0)
	route.curvatures.fill(Vector3.ZERO)
	var channels: Dictionary = fidelity.reconstruct_channels(route)
	_expect_close_tol(errors, _median_finite(channels.radius_m), 50.0, 0.75, "circle reconstructs geometric radius")
	_expect_close_tol(errors, _median_packed(channels.curvature), 0.02, 0.0003, "circle reconstructs curvature")
	_expect_close(errors, _max_abs_vector(channels.authored_curvature_vector), 0.0, "reconstruction preserves deliberately incorrect authored curvature")
	_expect_close_tol(errors, _median_vector_length(channels.geometric_authored_curvature_error_vector), 0.02, 0.0003, "geometric/authored curvature error exposes the mismatch")


static func _test_unclamped_radius_reconstruction(fidelity: Script, errors: PackedStringArray) -> void:
	var channels: Dictionary = fidelity.reconstruct_channels(
		_analytic_circle_route(100.0, 20000.0, 10.0, 20.0)
	)
	_expect_close_tol(errors, _median_finite(channels.radius_m), 20000.0, 2500.0, "large geometric radius is not clamped to 10 km")
	_expect(errors, not _any_true(channels.radius_unbounded), "large finite geometry is not labelled unbounded")


static func _test_force_integrity_mismatch(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _analytic_circle_route(25.0, 50.0, 4.0, 100.0)
	route.lateral_g.fill(0.0)
	var channels: Dictionary = fidelity.reconstruct_channels(route)
	var expected_lateral := 25.0 * 25.0 / 50.0 / 9.80665
	_expect_close_tol(errors, _median_packed(channels.normal_force_error_g), 0.0, 0.002, "normal force error keeps its axis and sign")
	_expect_close_tol(errors, _median_packed(channels.lateral_force_error_g), expected_lateral, 0.002, "lateral force error is reconstructed minus authored")
	_expect_close_tol(errors, _median_packed(channels.longitudinal_force_error_g), 0.0, 0.002, "longitudinal force error keeps its axis and sign")
	var emitted_peak := maxf(
		_max_abs(channels.normal_force_error_g),
		maxf(
			_max_abs(channels.lateral_force_error_g),
			_max_abs(channels.longitudinal_force_error_g)
		)
	)
	_expect_close(errors, channels.force_error_peak_g, emitted_peak, "force error aggregate is the largest absolute per-axis error")
	_expect_close_tol(errors, _median_vector_length(channels.force_authored_curvature_error_vector), 0.02, 0.0003, "force/authored-curvature error exposes the mismatch")
	_expect(errors, not channels.has("filtered_positions") and not channels.has("smoothed_positions"), "reconstruction never creates smoothed geometry")
	_expect(errors, channels.has("jerk_mps3") and _max_abs_vector(channels.jerk_mps3) > 0.0, "reconstruction emits raw inertial jerk")
	_expect(errors, not channels.has("comparison_channels"), "force reconstruction stays raw without an explicit source filter")


static func _test_nonuniform_quadratic_acceleration(fidelity: Script, errors: PackedStringArray) -> void:
	var channels: Dictionary = fidelity.reconstruct_channels(_nonuniform_quadratic_route())
	for acceleration in channels.inertial_acceleration_mps2:
		_expect(errors, acceleration.distance_to(Vector3(2.0, 0.0, 0.0)) < 0.001, "nonuniform quadratic positions reconstruct constant 2 m/s^2 acceleration")
	_expect(errors, _max_abs_vector(channels.jerk_mps3) < 0.001, "constant nonuniform acceleration has zero jerk")


static func _test_reconstruction_seam_channels(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _curvature_direction_seam_route()
	var seam: int = route.span_indices.find(1)
	var channels: Dictionary = fidelity.reconstruct_channels(route)
	for key in ["curvature_vector", "curvature_vector_ds", "curvature_vector_d2s", "curvature", "curvature_ds", "curvature_d2s", "authored_curvature_vector", "authored_curvature_vector_ds", "authored_curvature_vector_d2s", "authored_curvature_ds", "roll_acceleration_dps2", "seam_indices", "seam_markers", "jerk_mps3"]:
		_expect(errors, channels.has(key), "reconstruction emits raw %s" % key)
	_expect_close_tol(errors, channels.curvature[seam - 2], channels.curvature[seam + 2], 0.001, "equal curvature magnitudes survive a direction-changing seam")
	_expect(errors, channels.authored_curvature_vector_ds[seam].length() > 0.05, "unsmoothed raw curvature-vector derivative exposes the seam direction change")
	_expect(errors, _max_abs(channels.authored_curvature_ds) < 0.0001, "equal raw curvature magnitude has near-zero scalar derivative")
	_expect_close_tol(errors, _median_packed(channels.roll_acceleration_dps2), 50.0, 0.01, "roll acceleration differentiates degrees per second on physical time")
	_expect(errors, channels.seam_indices == PackedInt32Array([seam]), "reconstruction preserves each native span transition exactly once")
	_expect(errors, channels.seam_markers.size() == 1 and channels.seam_markers[0].sample_index == seam, "seam marker identifies the native span boundary exactly once")
	_expect(errors, not channels.has("comparison_channels"), "raw seam reconstruction never filters geometry")


static func _test_route_reconstruction_embedding(fidelity: Script, errors: PackedStringArray) -> void:
	var measured: Dictionary = fidelity.measure_route(_measurement_route(), [0.0])
	_expect(errors, measured.has("reconstruction"), "route measurement includes reconstruction at route scope")
	_expect(errors, _count_dictionary_key(measured, "reconstruction") == 1, "route measurement includes exactly one reconstruction payload")


static func _test_semantic_window_order(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _measurement_route()
	route.gesture_windows[0].role_windows = [
		_role_window("act1.hill", "entry", "hill-entry", "Hill entry", 0, 4),
		_role_window("act1.hill", "core", "hill", "Hill", 5, 19),
	]
	var before: Dictionary = route.duplicate(true)
	var measured: Dictionary = fidelity.measure_route(route, [0.0, 2.0])
	var beats: Array = measured.get("beats", [])
	_expect(errors, measured.get("schema_version") == 2, "native semantic measurement emits schema 2")
	_expect(errors, beats.size() == 4, "flattened role windows produce one ordered beat each")
	if beats.size() != 4:
		return
	_expect(errors, beats.map(func(beat: Dictionary): return beat.beat_id) == [
		"act1.hill/entry/00-hill-entry", "act1.hill/core/00-hill",
		"act1.transfer/whole/00-transfer",
		"return.capture/whole/00-capture",
	], "measurement preserves native role-window order and stable IDs")
	_expect(errors, beats[1].story_slot_id == "act1.hill" and beats[1].window_role == "core",
		"measurement retains compiled selector discriminators")
	_expect(errors, beats[1].occurrence == 0 and beats[1].kind == "hill"
		and beats[1].name == "Hill", "measurement retains role diagnostic metadata")
	_expect(errors, beats[1].start_distance == 5.0 and beats[1].end_distance == 19.0,
		"measurement uses the native role bounds without widening")
	_expect(errors, route == before, "semantic measurement is read-only")


static func _test_catalog_validation(fidelity: Script, errors: PackedStringArray) -> void:
	var catalog := _valid_catalog()
	_expect_contains(errors, fidelity.validate_catalog(catalog), "schema version 2", "schema-v1 catalogs are rejected")


## Cases are [readable name, diagnostic substring, exact one-mutation callable].
static func _expect_catalog_invalid_cases(
	fidelity: Script, errors: PackedStringArray, catalog: Dictionary, cases: Array
) -> void:
	for case in cases:
		var invalid := catalog.duplicate(true)
		var mutate: Callable = case[2]
		mutate.call(invalid)
		_expect_contains(errors, fidelity.validate_catalog(invalid), case[1], case[0])


static func _use_numeric_alignment_landmark(catalog: Dictionary) -> void:
	catalog.observations[0].source_window_id = 9
	catalog.observations[0].alignment.source_landmark_id = 9


static func _use_numeric_observation_source(catalog: Dictionary) -> void:
	catalog.observations[0].source_id = 7
	catalog.observations[0].corroborating_observation_ids = []


static func _test_catalog_v2_validation(fidelity: Script, errors: PackedStringArray) -> void:
	var catalog := _valid_catalog_v2()
	_expect(errors, fidelity.validate_catalog(catalog).is_empty(), "complete schema-v2 catalog validates")
	var numeric_version := catalog.duplicate(true)
	numeric_version.catalog_version = 7
	_expect_contains(errors, fidelity.validate_catalog(numeric_version), "catalog_version",
		"catalog_version requires a non-empty String")
	var coercion_catalog := _valid_promotion_catalog()
	coercion_catalog.sources["test.primary"].windows[0].id = "9"
	coercion_catalog.observations[0].source_window_id = "9"
	coercion_catalog.observations[0].alignment.source_landmark_id = "9"
	coercion_catalog.sources["7"] = coercion_catalog.sources["test.primary"].duplicate(true)
	coercion_catalog.sources["7"].initial_state = "executable"
	coercion_catalog.sources["7"].state = "executable"
	coercion_catalog.observations[0].id = "8"
	coercion_catalog.targets[0].observation_id = "8"
	coercion_catalog.sources["test.secondary"].windows.append(
		{"id": "unused.window", "window_s": [20.0, 22.0]}
	)
	coercion_catalog.review_prompts = [{
		"id": "review.coercion", "category": "feel", "prompt": "Compare the sustained force feel.",
		"source_ids": ["7"], "issues": [1],
	}]
	_expect(errors, fidelity.validate_catalog(coercion_catalog).is_empty(),
		"catalog coercion fixture validates before mutation")
	_expect_catalog_invalid_cases(fidelity, errors, coercion_catalog, [
		["schema_version requires integer 2", "schema version",
			func(value: Dictionary): value.schema_version = 2.0],
		["catalog collection IDs require non-empty Strings", "id",
			func(value: Dictionary): value.selectors[10] = value.selectors["semantic.act1.loop.core"].duplicate(true)],
		["catalog record IDs require non-empty Strings", "id",
			func(value: Dictionary): value.review_prompts[0].id = 10],
		["observation references require non-empty Strings", "source_id",
			func(value: Dictionary): _use_numeric_observation_source(value)],
		["target references require non-empty Strings", "observation_id",
			func(value: Dictionary): value.targets[0].observation_id = 8],
		["source window IDs require Strings", "window id",
			func(value: Dictionary): value.sources["test.secondary"].windows[1].id = 10],
		["auxiliary source_ids entries require Strings", "source_ids",
			func(value: Dictionary): value.review_prompts[0].source_ids[0] = 7],
		["alignment landmarks require non-empty Strings", "alignment",
			func(value: Dictionary): _use_numeric_alignment_landmark(value)],
		["alignment methods require non-empty Strings", "alignment",
			func(value: Dictionary): value.observations[0].alignment.method = 7],
		["prompt text requires a non-empty String", "text",
			func(value: Dictionary): value.review_prompts[0].prompt = 7],
		["prompt categories require non-empty Strings", "category",
			func(value: Dictionary): value.review_prompts[0].category = 7],
	])
	_expect_catalog_invalid_cases(fidelity, errors, catalog, [
		["unknown evidence state is rejected", "invalid state", func(value: Dictionary): value.sources["rideforcesdb.tormenta.6383"].state = "trusted"],
		["source state cannot exceed its initial permission ceiling", "permission ceiling", func(value: Dictionary): value.sources["rideforcesdb.tormenta.6383"].initial_state = "observation_only"],
		["non-force permitted axes are rejected", "permitted_axes", func(value: Dictionary): value.sources["rideforcesdb.tormenta.6383"].permitted_axes.append("pitch_deg")],
	])
	var malformed_source := catalog.duplicate(true)
	malformed_source.sources["rideforcesdb.tormenta.6383"].caveats = null
	malformed_source.sources["rideforcesdb.tormenta.6383"].permitted_axes = "normal_g"
	_expect_contains(errors, fidelity.validate_catalog(malformed_source), "caveats", "malformed source arrays return diagnostics")
	_expect_contains(errors, fidelity.validate_catalog(malformed_source), "permitted_axes", "malformed permitted axes return diagnostics")
	var bad_union := catalog.duplicate(true)
	bad_union.sources["rideforcesdb.tormenta.6383"].artifact_path = "docs/evidence/fidelity/rideforcesdb/6383-raw.json"
	bad_union.sources["rideforcesdb.tormenta.6383"].artifact_sha256 = "d".repeat(64)
	_expect_contains(errors, fidelity.validate_catalog(bad_union), "acquisition", "acquisition branches cannot be mixed")
	_expect_catalog_invalid_cases(fidelity, errors, catalog, [
		["unavailable raw acquisition keeps structured fallback citations", "fallback_citations", func(value: Dictionary): value.sources["rideforcesdb.tormenta.6383"].erase("fallback_citations")],
		["artifact paths cannot traverse parents", "diagnostic_path", func(value: Dictionary): value.sources["rideforcesdb.tormenta.6383"].diagnostic_path = "../6383-diagnostic.json"],
		["non-SHA-256 digest is rejected", "diagnostic_sha256", func(value: Dictionary): value.sources["rideforcesdb.tormenta.6383"].diagnostic_sha256 = "abc"],
	])
	var bad_metadata_union := catalog.duplicate(true)
	bad_metadata_union.sources["youtube.falcon.sdXGD9kMR7s"].metadata_diagnostic_path = "docs/evidence/fidelity/youtube/sdXGD9kMR7s-oembed.json"
	bad_metadata_union.sources["youtube.falcon.sdXGD9kMR7s"].metadata_diagnostic_sha256 = "d".repeat(64)
	_expect_contains(errors, fidelity.validate_catalog(bad_metadata_union), "metadata", "metadata provenance branches cannot be mixed")
	_expect_catalog_invalid_cases(fidelity, errors, catalog, [
		["selectors require compiled anchors", "compiled_anchor", func(value: Dictionary): value.selectors["semantic.act1.loop.core"].erase("compiled_anchor")],
		["legacy anchors only permit whole", "window_role", func(value: Dictionary): value.selectors["semantic.act1.loop.core"].legacy_anchor.window_role = "core"],
	])
	_expect_catalog_invalid_cases(fidelity, errors, catalog, [
		["legacy_anchor phase requires a non-empty String", "legacy_anchor", func(value: Dictionary): value.selectors["semantic.act1.loop.core"].legacy_anchor.phase = 42],
		["legacy_anchor kind requires a non-empty String", "legacy_anchor", func(value: Dictionary): value.selectors["semantic.act1.loop.core"].legacy_anchor.kind = []],
		["compiled_anchor story_slot_id requires a non-empty String", "compiled_anchor", func(value: Dictionary): value.selectors["semantic.act1.loop.core"].compiled_anchor.story_slot_id = NAN],
		["compiled_anchor window_role requires a non-empty String", "compiled_anchor", func(value: Dictionary): value.selectors["semantic.act1.loop.core"].compiled_anchor.window_role = true],
		["compiled_anchor kind requires a non-empty String", "compiled kind", func(value: Dictionary): value.selectors["semantic.act1.loop.core"].compiled_anchor.kind = ""],
		["compiled_anchor occurrence is nonnegative", "compiled occurrence", func(value: Dictionary): value.selectors["semantic.act1.loop.core"].compiled_anchor.occurrence = -1],
		["compiled_anchor window_id requires a non-empty String", "compiled window_id", func(value: Dictionary): value.selectors["semantic.act1.loop.core"].compiled_anchor.window_id = 42],
	])
	var exact_compiled_selector := catalog.duplicate(true)
	exact_compiled_selector.selectors["semantic.act1.loop.core"].compiled_anchor.merge({
		"kind": "loop", "occurrence": 1,
		"window_id": "act-one/giant-inversion/01-loop",
	}, true)
	_expect(errors, fidelity.validate_catalog(exact_compiled_selector).is_empty(),
		"compiled selectors may use stable kind, occurrence, and window identity")
	_expect_catalog_invalid_cases(fidelity, errors, catalog, [
		["unsupported positive longitudinal transform is rejected", "Gx+", func(value: Dictionary): value.transforms["fictional.gz-positive@1"].axis = "longitudinal_g"],
		["approved transform formula is immutable", "formula", func(value: Dictionary): value.transforms["fictional.gz-positive@1"].formula = "target_force_g = observed_force_g"],
		["approved transform provenance is immutable", "approval provenance", func(value: Dictionary): value.transforms["fictional.gz-positive@1"].approval = "rejected"],
		["impossible retrieval dates are rejected", "retrieved_on", func(value: Dictionary): value.sources["rideforcesdb.tormenta.6383"].retrieved_on = "2026-99-99"],
	])
	var duplicate := catalog.duplicate(true)
	duplicate.review_prompts = [
		{"id": "review.same", "category": "feel", "prompt": "First", "source_ids": [], "issues": [1]},
		{"id": "review.same", "category": "feel", "prompt": "Second", "source_ids": [], "issues": [2]},
	]
	_expect_contains(errors, fidelity.validate_catalog(duplicate), "duplicate id", "record IDs are unique across collections")
	_expect(errors, fidelity.validate_catalog_artifacts(catalog).is_empty(), "committed fixture artifacts validate offline")
	var missing_artifact := catalog.duplicate(true)
	missing_artifact.sources["rideforcesdb.tormenta.6383"].diagnostic_path = "docs/evidence/fidelity/missing.json"
	_expect_contains(errors, fidelity.validate_catalog_artifacts(missing_artifact), "missing", "missing evidence artifact is rejected")
	var mismatched_artifact := catalog.duplicate(true)
	mismatched_artifact.sources["rideforcesdb.tormenta.6383"].diagnostic_sha256 = "0".repeat(64)
	_expect_contains(errors, fidelity.validate_catalog_artifacts(mismatched_artifact), "digest mismatch", "artifact hash mismatches are rejected")


static func _test_executable_promotion(fidelity: Script, errors: PackedStringArray) -> void:
	var catalog := _valid_promotion_catalog()
	_expect(errors, fidelity.validate_catalog(catalog).is_empty(), "independently corroborated source-local observation and derived target validate")
	_expect_catalog_invalid_cases(fidelity, errors, catalog, [
		["corroborative source cannot promote alone", "requires corroboration", func(value: Dictionary): value.observations[0].corroborating_observation_ids = []],
		["an observation cannot corroborate itself", "independent", func(value: Dictionary): value.observations[0].corroborating_observation_ids = ["tormenta.loop.primary"]],
		["corroborative observations cannot carry unchecked links", "non-executable", func(value: Dictionary): value.observations[1].corroborating_observation_ids = ["missing"]],
		["observations resolve declared source-local windows", "source_window_id", func(value: Dictionary): value.observations[0].source_window_id = "invented.window"],
		["malformed ranges return diagnostics instead of raising", "invalid raw_range", func(value: Dictionary): value.observations[0].raw_range = [{}, {}]],
		["alignment resolves the selected source window", "source_landmark_id", func(value: Dictionary): value.observations[0].alignment.source_landmark_id = "invented.landmark"],
	])
	var bad_ceiling := catalog.duplicate(true)
	bad_ceiling.sources["test.primary"].initial_state = "observation_only"
	bad_ceiling.sources["test.primary"].state = "observation_only"
	_expect_contains(errors, fidelity.validate_catalog(bad_ceiling), "permission ceiling", "observation-only sources cannot promote force evidence")
	_expect_catalog_invalid_cases(fidelity, errors, catalog, [
		["target selector is derived from its observation", "must match observation", func(value: Dictionary): value.targets[0].semantic_selector_id = "missing"],
		["target raw range is derived from its observation", "raw_range", func(value: Dictionary): value.targets[0].raw_range = [2.1, 3.0]],
		["target range is derived by the approved transform", "target_range", func(value: Dictionary): value.targets[0].target_range = [999.0, 1000.0]],
		["targets require an executable observation", "unknown observation", func(value: Dictionary): value.targets[0].observation_id = "missing"],
	])


static func _test_comparison_catalog_contract(fidelity: Script, errors: PackedStringArray) -> void:
	var catalog := _valid_promotion_catalog()
	_expect(errors, fidelity.validate_catalog(catalog).is_empty(), "comparison execution policy validates")
	_expect_catalog_invalid_cases(fidelity, errors, catalog, [
		["targets require an aggregation policy", "aggregation", func(value: Dictionary): value.targets[0].erase("aggregation")],
		["row reducer sum is rejected", "aggregation", func(value: Dictionary): value.targets[0].aggregation.row = "sum"],
		["beat reducer sum is rejected", "aggregation", func(value: Dictionary): value.targets[0].aggregation.beat = "sum"],
		["row reducer time_weighted_sum is rejected", "aggregation", func(value: Dictionary): value.targets[0].aggregation.row = "time_weighted_sum"],
		["beat reducer time_weighted_sum is rejected", "aggregation", func(value: Dictionary): value.targets[0].aggregation.beat = "time_weighted_sum"],
		["row reducer unknown is rejected", "aggregation", func(value: Dictionary): value.targets[0].aggregation.row = "unknown"],
		["beat reducer unknown is rejected", "aggregation", func(value: Dictionary): value.targets[0].aggregation.beat = "unknown"],
		["seed reduction cannot be time weighted", "aggregation", func(value: Dictionary): value.targets[0].aggregation.seed = "time_weighted_mean"],
		["aggregation fields are exact", "aggregation", func(value: Dictionary): value.targets[0].aggregation = {"row": "median", "beat": "median", "seed": "median", "extra": "median"}],
		["aggregation requires row", "aggregation", func(value: Dictionary): value.targets[0].aggregation.erase("row")],
		["aggregation requires beat", "aggregation", func(value: Dictionary): value.targets[0].aggregation.erase("beat")],
		["aggregation requires seed", "aggregation", func(value: Dictionary): value.targets[0].aggregation.erase("seed")],
		["seed reducer sum is rejected", "aggregation", func(value: Dictionary): value.targets[0].aggregation.seed = "sum"],
		["seed reducer time_weighted_sum is rejected", "aggregation", func(value: Dictionary): value.targets[0].aggregation.seed = "time_weighted_sum"],
		["seed reducer time_weighted_mean is rejected", "aggregation", func(value: Dictionary): value.targets[0].aggregation.seed = "time_weighted_mean"],
		["seed reducer unknown is rejected", "aggregation", func(value: Dictionary): value.targets[0].aggregation.seed = "unknown"],
		["aggregation must be a Dictionary", "aggregation", func(value: Dictionary): value.targets[0].aggregation = ["median", "median", "median"]],
	])

	_expect_catalog_invalid_cases(fidelity, errors, catalog, [
		["alignment requires a generated row selector field", "generated_row_selector", func(value: Dictionary): value.observations[0].alignment.erase("generated_row_selector")],
		["row-independent alignment requires null row selector", "generated_row_selector", func(value: Dictionary): value.observations[0].alignment.row_compatibility = "row-independent"],
		["same-row alignment requires an exact row selector", "generated_row_selector", func(value: Dictionary): value.observations[0].alignment.generated_row_selector = null],
	])
	var transformed_without_selector := catalog.duplicate(true)
	transformed_without_selector.observations[0].alignment.row_compatibility = "explicit-row-transform"
	transformed_without_selector.observations[0].alignment.generated_row_selector = null
	_expect_contains(errors, fidelity.validate_catalog(transformed_without_selector), "generated_row_selector", "explicit-row-transform requires an exact row selector")
	var transformed_with_selector := catalog.duplicate(true)
	transformed_with_selector.observations[0].alignment.row_compatibility = "explicit-row-transform"
	_expect(errors, fidelity.validate_catalog(transformed_with_selector).is_empty(), "explicit-row-transform accepts an exact selector")
	_expect_catalog_invalid_cases(fidelity, errors, catalog, [
		["row selector has exactly one field", "generated_row_selector", func(value: Dictionary): value.observations[0].alignment.generated_row_selector = {"row_id": "row-02", "position": "rear"}],
		["row selector position is exact", "generated_row_selector", func(value: Dictionary): value.observations[0].alignment.generated_row_selector = {"position": "middle"}],
		["row selector offset is finite", "generated_row_selector", func(value: Dictionary): value.observations[0].alignment.generated_row_selector = {"offset": NAN}],
	])
	for malformed_selector in [
		[], {"unknown": "row-01"}, {"row_id": ""}, {"row_id": 2}, {"position": null},
		{"offset": 2}, {"offset": "2.0"},
	]:
		var malformed := catalog.duplicate(true)
		malformed.observations[0].alignment.generated_row_selector = malformed_selector
		_expect_contains(errors, fidelity.validate_catalog(malformed), "generated_row_selector", "malformed row selector value is rejected")
	for selector in [{"row_id": "row-02"}, {"position": "rear"}, {"offset": 2.0}]:
		var exact_selector := catalog.duplicate(true)
		exact_selector.observations[0].alignment.generated_row_selector = selector
		_expect(errors, fidelity.validate_catalog(exact_selector).is_empty(), "exact generated row selector validates")
	var independent := catalog.duplicate(true)
	independent.observations[0].alignment.row_compatibility = "row-independent"
	independent.observations[0].alignment.generated_row_selector = null
	_expect(errors, fidelity.validate_catalog(independent).is_empty(), "row-independent null selector validates")

	var non_grid_hold := catalog.duplicate(true)
	for observation in non_grid_hold.observations:
		observation.hold_seconds = 0.804
	non_grid_hold.targets[0].hold_seconds = 0.804
	_expect_contains(errors, fidelity.validate_catalog(non_grid_hold), "HOLD_SECONDS", "comparison holds must use an emitted duration")
	var long_values := PackedFloat32Array()
	long_values.resize(1301)
	long_values.fill(1.0)
	var emitted: Dictionary = fidelity._hold_values(long_values, 1.0)
	var emitted_keys := PackedStringArray(emitted.keys())
	emitted_keys.sort()
	var expected_keys := PackedStringArray(["0.20", "0.50", "0.80", "1.00", "1.10", "1.40", "2.00", "2.40", "2.78", "3.00", "4.00", "6.80", "12.00"])
	expected_keys.sort()
	_expect(errors, emitted_keys == expected_keys, "measurement emits exactly the HOLD_SECONDS lookup keys")


static func _test_route_measurements(fidelity: Script, errors: PackedStringArray) -> void:
	var measured: Dictionary = fidelity.measure_route(_measurement_route(), [0.0, 2.0])
	_expect(errors, measured.get("beats", []).size() == 3,
		"measurement retains hill, transfer, and capture role windows")
	if measured.get("beats", []).is_empty():
		return
	var beat: Dictionary = measured.beats[0]
	_expect(errors, beat.rows.size() == 2, "every requested train row is measured")
	if beat.rows.size() == 2:
		_expect_close(errors, beat.rows[1].window_start_distance, 2.0, "rear-row window starts when that row reaches the beat")
		_expect_close(errors, beat.rows[1].window_end_distance, 21.0, "rear-row window ends when that row leaves the beat")
		_expect_close(errors, beat.rows[1].loads.normal_peak_positive, 1.0, "constant synthetic normal load remains one g")
		_expect_close(errors, beat.rows[1].loads.lateral_peak_absolute, 0.0, "constant synthetic lateral load remains zero")
	_expect_close(errors, beat.geometry.length, 19.0, "beat geometry reports track length")
	_expect_close(errors, beat.geometry.height, 10.0, "beat geometry reports vertical scale")
	_expect_close(errors, beat.geometry.width, 19.0, "beat geometry reports plan displacement")
	_expect_close(errors, beat.pacing.duration, 1.9, "beat pacing reports elapsed duration")
	_expect_close(errors, beat.pacing.speed_loss, 0.0, "constant speed has no energy loss")
	_expect_close(errors, beat.terrain.agl_median, 5.0, "terrain scorecard reports median AGL")
	_expect_close(errors, beat.flow.transition_force_swing, 0.0, "constant-force seam has no transition swing")
	for dimension in ["loads", "geometry", "pacing", "terrain", "flow"]:
		_expect(errors, measured.dimensions.has(dimension), "route aggregate includes %s" % dimension)


static func _test_reference_catalog(fidelity: Script, errors: PackedStringArray) -> void:
	if not ResourceLoader.exists(REFERENCES_PATH):
		errors.append("RideFidelityReferences is missing")
		return
	var references: Script = load(REFERENCES_PATH)
	var catalog: Dictionary = references.CATALOG
	for error in fidelity.validate_catalog(catalog):
		errors.append("reference catalog: %s" % error)
	for error in fidelity.validate_catalog_artifacts(catalog):
		errors.append("reference catalog artifact: %s" % error)
	_test_manifest_parity(catalog, errors)
	_test_reviewed_live_pov_landmarks(catalog, errors)
	var covered := {}
	for collection in [catalog.get("targets", []), catalog.get("review_prompts", []), catalog.get("evidence_gaps", [])]:
		for record in collection:
			for issue in record.get("issues", []):
				covered[int(issue)] = true
	for issue in range(1, 17):
		_expect(errors, covered.has(issue), "reference catalog covers issue %d" % issue)


static func _test_reviewed_live_pov_landmarks(catalog: Dictionary, errors: PackedStringArray) -> void:
	var review_files := ["J54WKu2nU6o-review.json", "sdXGD9kMR7s-review.json", "poco8rOnW18-review.json", "0UaOSBGSx20-review.json"]
	var all_readouts := []
	for file in review_files:
		var review: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../docs/evidence/fidelity/youtube/" + file))
		_expect(errors, review is Dictionary, "%s live review parses" % file)
		if not review is Dictionary:
			continue
		var source_id := str(review.get("source_id", ""))
		var source: Dictionary = catalog.get("sources", {}).get(source_id, {})
		var expected_windows := []
		for landmark in review.get("independent_timeline", {}).get("landmarks", []):
			expected_windows.append({"id": landmark.get("id"), "time_s": landmark.get("time_s")})
			all_readouts.append_array(landmark.get("rendered_readouts", []))
		_expect(errors, source.get("windows") == expected_windows, "%s catalog mirrors reviewed point windows" % source_id)
	var expected_readouts := [
		{"label":"Long.","display_value":-0.30,"unit":"g","qualifier":"approximate-unmapped-uploader-display","adjacent_range":[]},
		{"label":"Long.","display_value":-0.19,"unit":"g","qualifier":"approximate-unmapped-uploader-display","adjacent_range":[]},
		{"label":"Long.","display_value":-0.58,"unit":"g","qualifier":"approximate-unmapped-uploader-display","adjacent_range":[-0.58,-0.57]},
	]
	_expect(errors, all_readouts == expected_readouts, "live reviews contain exactly three sign-reviewed unmapped Long. values")
	var executable_collections_empty: bool = catalog.get("selectors", {}).is_empty() and catalog.get("observations", []).is_empty() and catalog.get("targets", []).is_empty()
	_expect(errors, executable_collections_empty, "live POV review does not create selectors, observations, or targets")
	var prompt_ids := []
	for prompt in catalog.get("review_prompts", []):
		prompt_ids.append(prompt.get("id"))
	_expect(errors, prompt_ids == [
		"review.ride_feel", "review.speed_perception", "review.element_shaping", "review.support_overlap",
		"review.coastertalk_overlay_spot_checks", "review.terrain_clearance",
	], "live POV catalog has exactly the six approved prompt IDs")


static func _test_manifest_parity(catalog: Dictionary, errors: PackedStringArray) -> void:
	var manifest_text := FileAccess.get_file_as_string("res://../docs/evidence/fidelity/source-manifest.json")
	var manifest: Variant = JSON.parse_string(manifest_text)
	if not manifest is Dictionary:
		errors.append("source manifest parses as a Dictionary")
		return
	var expected_ids := PackedStringArray()
	for record in manifest.get("sources", []):
		var source_id := str(record.get("source_id", ""))
		expected_ids.append(source_id)
		var source: Dictionary = catalog.get("sources", {}).get(source_id, {})
		_expect(errors, not source.is_empty(), "reference catalog includes manifest source %s" % source_id)
		for field in ["initial_state", "permitted_contributions", "permitted_axes", "promotion_prerequisites"]:
			_expect(errors, source.get(field) == record.get(field), "%s preserves manifest %s" % [source_id, field])
		_expect(errors, source.get("state") == record.get("current_state"), "%s uses manifest current_state" % source_id)
		_expect(errors, source.get("url") == record.get("source_url"), "%s preserves manifest source_url" % source_id)
		_expect(errors, source.get("retrieved_on") == record.get("retrieved_on"), "%s preserves manifest retrieved_on" % source_id)
		for field in [
			"recording_id", "video_id", "acquisition", "artifact_path", "artifact_sha256",
			"diagnostic_path", "diagnostic_sha256", "metadata_artifact_path",
			"metadata_artifact_sha256", "metadata_diagnostic_path", "metadata_diagnostic_sha256",
			"review_path", "review_sha256",
		]:
			_expect(errors, source.has(field) == record.has(field), "%s preserves manifest %s presence" % [source_id, field])
			if record.has(field):
				_expect(errors, source.get(field) == record.get(field), "%s preserves manifest %s" % [source_id, field])
		if record.get("acquisition") == "raw_fetch_unavailable":
			var review: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../" + str(record.review_path)))
			_expect(errors, review is Dictionary, "%s review artifact parses" % source_id)
			if review is Dictionary:
				_expect(errors, source.get("fallback_citations") == review.get("acquisition", {}).get("fallback_citations"), "%s preserves reviewed fallback citations" % source_id)
	expected_ids.sort()
	var actual_ids := PackedStringArray(catalog.get("sources", {}).keys())
	actual_ids.sort()
	_expect(errors, actual_ids == expected_ids, "reference catalog source IDs exactly match the manifest")
	_expect(errors, catalog.get("selectors", {}).is_empty(), "baseline catalog has no unreferenced semantic selectors")


static func _test_target_classification(fidelity: Script, errors: PackedStringArray) -> void:
	for case in [
		{"value": 0.5, "band": [1.0, 2.0], "expected": "under"},
		{"value": 1.0, "band": [1.0, 2.0], "expected": "within"},
		{"value": 1.5, "band": [1.0, 2.0], "expected": "within"},
		{"value": 2.0, "band": [1.0, 2.0], "expected": "within"},
		{"value": 2.5, "band": [1.0, 2.0], "expected": "over"},
		{"value": -2.5, "band": [-2.0, -1.0], "expected": "under"},
		{"value": -0.5, "band": [-2.0, -1.0], "expected": "over"},
	]:
		_expect(errors, fidelity.classify_value(case.value, case.band) == case.expected, "classification %s" % case.expected)
	for case in [
		{"value": 0.5, "band": [1.0, 2.0], "expected": 0.25},
		{"value": 1.5, "band": [1.0, 2.0], "expected": 0.0},
		{"value": 2.5, "band": [1.0, 2.0], "expected": 0.25},
		{"value": 0.05, "band": [0.0, 0.0], "expected": 0.5},
		{"value": -3.0, "band": [-2.0, -1.0], "expected": 0.5},
	]:
		_expect_close(errors, fidelity.normalized_miss(case.value, case.band), case.expected, "normalized miss uses the specified denominator")


static func _test_comparison_reducers(fidelity: Script, errors: PackedStringArray) -> void:
	var reducer_fleet := _compiled_reducer_fleet(CANONICAL_FLEET)
	for case in [
		{"row": "minimum", "beat": "minimum", "expected": 1.0},
		{"row": "maximum", "beat": "maximum", "expected": 100.0},
		{"row": "median", "beat": "median", "expected": 5.0},
		{"row": "time_weighted_mean", "beat": "time_weighted_mean", "expected": ((45.0 / 7.0) * 4.0 + 21.6 * 5.0 + (624.0 / 11.0) * 6.0) / 15.0},
		{"row": "maximum", "beat": "minimum", "expected": 10.0},
		{"row": "minimum", "beat": "maximum", "expected": 4.0},
		{"row": "median", "beat": "maximum", "expected": 20.0},
		{"row": "maximum", "beat": "median", "expected": 30.0},
	]:
		var catalog := _comparison_catalog()
		catalog.observations[0].alignment.row_compatibility = "row-independent"
		catalog.observations[0].alignment.generated_row_selector = null
		catalog.targets[0].aggregation.row = case.row
		catalog.targets[0].aggregation.beat = case.beat
		var comparison: Dictionary = fidelity.compare_fleet(reducer_fleet, catalog)
		var finding := _first_finding(comparison, errors, "%s/%s reducers emit a finding" % [case.row, case.beat])
		if finding.is_empty():
			continue
		_expect_close(errors, finding.seed_results[0].value, case.expected, "%s/%s reduce row then beat values" % [case.row, case.beat])
		_expect_close(errors, finding.seed_results[0].retained_seconds, 15.0, "%s/%s keep max parallel row duration and summed beat duration" % [case.row, case.beat])
		_expect_close(errors, finding.total_retained_seconds, 225.0, "%s/%s retain stable fleet duration" % [case.row, case.beat])

	for reducer_case in [
		{"reducer": "minimum", "expected": 0.0},
		{"reducer": "maximum", "expected": 100.0},
		{"reducer": "median", "expected": 8.0},
	]:
		var catalog := _comparison_catalog()
		catalog.targets[0].aggregation.seed = reducer_case.reducer
		var comparison: Dictionary = fidelity.compare_fleet(_seed_reducer_fleet(CANONICAL_FLEET), catalog)
		var finding := _first_finding(comparison, errors, "%s seed reducer emits a finding" % reducer_case.reducer)
		if not finding.is_empty():
			_expect_close(errors, finding.fleet_value, reducer_case.expected, "%s reduces available seed values" % reducer_case.reducer)

	var held_catalog := _comparison_catalog("normal_held_positive", 0.8)
	var held_comparison: Dictionary = fidelity.compare_fleet(_held_comparison_fleet(CANONICAL_FLEET), held_catalog)
	var held_finding := _first_finding(held_comparison, errors, "held comparison emits a finding")
	if not held_finding.is_empty():
		_expect_close(errors, held_finding.seed_results[0].retained_seconds, 0.8, "held support is the requested duration")
		_expect_close(errors, held_finding.total_retained_seconds, 12.0, "held fleet support sums requested durations")

	var reordered := reducer_fleet.duplicate(true)
	for measurement in reordered:
		measurement.beats.reverse()
		for beat in measurement.beats:
			beat.rows.reverse()
	var stable_a: Dictionary = fidelity.compare_fleet(reducer_fleet, _comparison_catalog_with_aggregation("time_weighted_mean", "time_weighted_mean", "median"))
	var stable_b: Dictionary = fidelity.compare_fleet(reordered, _comparison_catalog_with_aggregation("time_weighted_mean", "time_weighted_mean", "median"))
	_expect(errors, stable_a.get("findings", []) == stable_b.get("findings", []), "weighted reduction order is stable under beat and row insertion changes")


static func _test_selector_and_row_resolution(fidelity: Script, errors: PackedStringArray) -> void:
	var occurrence_catalog := _comparison_catalog()
	occurrence_catalog.selectors["semantic.hill"].legacy_anchor.occurrence = 1
	var occurrence_result: Dictionary = fidelity.compare_fleet(_legacy_occurrence_fleet(CANONICAL_FLEET), occurrence_catalog)
	var occurrence_finding := _first_finding(occurrence_result, errors, "legacy occurrence emits a finding")
	if not occurrence_finding.is_empty():
		_expect_close(errors, occurrence_finding.seed_results[0].value, 3.0, "legacy occurrence counts exact phase-kind matches in measurement order")
		_expect(errors, occurrence_finding.seed_results[0].beat_ids == ["legacy-match-02"], "stored phase-wide ordinal is not the legacy occurrence")

	var compiled_miss: Dictionary = fidelity.compare_fleet(_compiled_fallback_trap_fleet(CANONICAL_FLEET), _comparison_catalog())
	_expect(errors, compiled_miss.get("findings", []).is_empty(), "compiled selector miss never falls back to legacy")
	_expect(errors, compiled_miss.get("evidence_gaps", []).size() == 15, "compiled selector miss gaps every seed")
	if not compiled_miss.get("evidence_gaps", []).is_empty():
		_expect(errors, compiled_miss.evidence_gaps[0].reason == "anchor-not-found", "compiled miss reports anchor-not-found")
	var wrong_role: Dictionary = fidelity.compare_fleet(_compiled_wrong_role_fleet(CANONICAL_FLEET), _comparison_catalog())
	_assert_all_gaps(errors, wrong_role, "anchor-not-found", "compiled wrong role")
	var exact_catalog := _comparison_catalog()
	exact_catalog.selectors["semantic.hill"].compiled_anchor.merge({
		"kind": "loop", "occurrence": 1, "window_id": "compiled-b",
	}, true)
	var exact_fleet := _compiled_reducer_fleet(CANONICAL_FLEET)
	for measurement: Dictionary in exact_fleet:
		for index in measurement.beats.size():
			measurement.beats[index].kind = "immelmann" if index == 0 else "loop"
			measurement.beats[index].occurrence = index
			measurement.beats[index].window_id = "compiled-%s" % ["a", "b", "c"][index]
	var exact_finding := _first_finding(
		fidelity.compare_fleet(exact_fleet, exact_catalog), errors,
		"compiled stable identity selector emits one finding")
	if not exact_finding.is_empty():
		_expect_close(errors, exact_finding.seed_results[0].value, 3.0,
			"kind, occurrence, and window identity select only the intended repeated role")

	for selector_case in [
		{"selector": {"row_id": "row-02"}, "expected": 2.0},
		{"selector": {"position": "rear"}, "expected": 2.0},
		{"selector": {"offset": 2.0000005}, "expected": 2.0},
		{"selector": {"offset": 0.000001}, "expected": 1.0},
	]:
		var catalog := _comparison_catalog()
		catalog.observations[0].alignment.generated_row_selector = selector_case.selector
		var comparison: Dictionary = fidelity.compare_fleet(_row_selection_fleet(CANONICAL_FLEET), catalog)
		var finding := _first_finding(comparison, errors, "exact row selector emits a finding")
		if not finding.is_empty():
			_expect_close(errors, finding.seed_results[0].value, selector_case.expected, "row selector resolves exactly")
	var outside_tolerance := _comparison_catalog()
	outside_tolerance.observations[0].alignment.generated_row_selector = {"offset": 0.0000011}
	_assert_all_gaps(errors, fidelity.compare_fleet(_row_selection_fleet(CANONICAL_FLEET), outside_tolerance), "row-not-found", "offset just outside tolerance")

	var independent_catalog := _comparison_catalog()
	independent_catalog.observations[0].alignment.row_compatibility = "row-independent"
	independent_catalog.observations[0].alignment.generated_row_selector = null
	independent_catalog.targets[0].aggregation.row = "maximum"
	var independent: Dictionary = fidelity.compare_fleet(_row_selection_fleet(CANONICAL_FLEET), independent_catalog)
	var independent_finding := _first_finding(independent, errors, "row-independent comparison emits a finding")
	if not independent_finding.is_empty():
		_expect_close(errors, independent_finding.seed_results[0].value, 2.0, "row-independent observes all rows before reducing")
		_expect(errors, independent_finding.seed_results[0].row_ids == ["row-01", "row-02"], "row IDs are retained and sorted")

	var missing_row_catalog := _comparison_catalog()
	missing_row_catalog.observations[0].alignment.generated_row_selector = {"row_id": "missing"}
	_assert_all_gaps(errors, fidelity.compare_fleet(_row_selection_fleet(CANONICAL_FLEET), missing_row_catalog), "row-not-found", "missing row")
	var ambiguous_catalog := _comparison_catalog()
	ambiguous_catalog.observations[0].alignment.generated_row_selector = {"position": "intermediate"}
	_assert_all_gaps(errors, fidelity.compare_fleet(_ambiguous_row_fleet(CANONICAL_FLEET), ambiguous_catalog), "row-ambiguous", "ambiguous row")

	var partial_fleet := _compiled_reducer_fleet(CANONICAL_FLEET)
	partial_fleet[0].beats[1].rows[0].loads.erase("normal_peak_positive")
	var partial: Dictionary = fidelity.compare_fleet(partial_fleet, _comparison_catalog())
	var partial_finding := _first_finding(partial, errors, "multi-beat partial fleet retains other seeds")
	if not partial_finding.is_empty():
		_expect(errors, partial_finding.seed_results.size() == 14, "one missing selected beat metric removes the whole target-seed reduction")
	_expect(errors, partial.get("evidence_gaps", []).size() == 1 and partial.evidence_gaps[0].reason == "metric-not-found", "all-or-nothing multi-beat failure emits one metric gap")

	var unavailable_fleet := _held_comparison_fleet(CANONICAL_FLEET)
	unavailable_fleet[0].beats[0].rows[0].loads.normal_held_positive = {"_unavailable": {"0.80": {"status": "unavailable", "reason": "insufficient_duration"}}}
	var unavailable: Dictionary = fidelity.compare_fleet(unavailable_fleet, _comparison_catalog("normal_held_positive", 0.8))
	_expect(errors, unavailable.get("evidence_gaps", []).size() == 1 and unavailable.evidence_gaps[0].reason == "metric-unavailable", "explicitly unavailable held metric is a gap")


static func _test_observed_only_and_evidence_gaps(fidelity: Script, errors: PackedStringArray) -> void:
	var catalog := _comparison_catalog_with_observed_only()
	var comparison: Dictionary = fidelity.compare_fleet(_observed_only_fleet(CANONICAL_FLEET), catalog)
	_expect(errors, comparison.get("findings", []).size() == 1, "target-backed comparisons stay in findings")
	_expect(errors, comparison.get("observed_only", []).size() == 75, "catalogued untargeted samples stay separate across observations, beats, rows, and seeds")
	if not comparison.get("observed_only", []).is_empty():
		var observed: Dictionary = comparison.observed_only[0]
		_expect(errors, observed.observation_id == "observed.hill.entry", "observed-only record retains observation provenance")
		_expect(errors, observed.seed == 1, "observed-only records sort by observation and numeric seed")
		_expect(errors, observed.source_id == "test.primary", "observed-only record retains source provenance")
		_expect(errors, observed.beat_id == "entry-a" and observed.row_id == "row-01", "observed-only records sort by beat and row after observation and seed")
		_expect(errors, observed.metric == "normal_peak_positive" and observed.value == 9.0, "observed-only record contains only its catalogued metric")
		var leading_keys := []
		for index in 4:
			var record: Dictionary = comparison.observed_only[index]
			leading_keys.append("%s/%s/%s/%s" % [record.observation_id, record.seed, record.beat_id, record.row_id])
		_expect(errors, leading_keys == [
			"observed.hill.entry/1/entry-a/row-01", "observed.hill.entry/1/entry-a/row-02",
			"observed.hill.entry/1/entry-b/row-01", "observed.hill.entry/1/entry-b/row-02",
		], "observed-only ordering uses the full stable tuple")
		var observation_boundary := []
		for index in [59, 60]:
			var record: Dictionary = comparison.observed_only[index]
			observation_boundary.append("%s/%s/%s/%s" % [record.observation_id, record.seed, record.beat_id, record.row_id])
		_expect(errors, observation_boundary == [
			"observed.hill.entry/20260809/entry-b/row-02",
			"observed.hill.exit/1/exit-a/row-01",
		], "observation ID sorts before seed across observed-only records")
	_expect(errors, _count_dictionary_key(comparison.get("observed_only", []), "normal_peak_negative") == 0, "uncatalogued measurement metrics are not enumerated")

	var finding := _first_finding(comparison, errors, "provenance comparison emits a finding")
	if not finding.is_empty():
		_expect(errors, finding.primary_source_ids == ["test.primary"], "finding retains sorted unique primary source IDs")
		_expect(errors, finding.corroborating_source_ids.is_empty(), "finding distinguishes absent corroborating sources")
		_expect(errors, finding.caveats == ["fixture caveat"], "finding retains sorted unique source caveats")
		_expect(errors, finding.transform_id == "observed.identity@1" and finding.semantic_selector_id == "semantic.hill", "finding retains transform and selector provenance")
		_expect(errors, finding.resolved_branch == "compiled" and finding.anchor == catalog.selectors["semantic.hill"].compiled_anchor, "finding reports its resolved branch and anchor")
		_expect(errors, finding.row_compatibility == "same-row" and finding.generated_row_selector == {"row_id": "row-01"}, "finding reports row alignment policy")
	var corroborated_catalog := _comparison_catalog()
	corroborated_catalog.sources["test.z"] = _comparison_source("z", "b".repeat(64))
	corroborated_catalog.sources["test.z"].caveats = ["z caveat", "shared caveat"]
	corroborated_catalog.sources["test.a"] = _comparison_source("a", "c".repeat(64))
	corroborated_catalog.sources["test.a"].caveats = ["shared caveat", "a caveat"]
	var corroborating_z := _comparison_observation(
		"observed.hill.z", "semantic.hill", "normal_peak_positive", null, "medium"
	)
	corroborating_z.state = "corroborative"
	corroborating_z.source_id = "test.z"
	var corroborating_a := _comparison_observation(
		"observed.hill.a", "semantic.hill", "normal_peak_positive", null, "medium"
	)
	corroborating_a.state = "corroborative"
	corroborating_a.source_id = "test.a"
	var corroborating_a_duplicate := _comparison_observation(
		"observed.hill.a.duplicate", "semantic.hill", "normal_peak_positive", null, "medium"
	)
	corroborating_a_duplicate.state = "corroborative"
	corroborating_a_duplicate.source_id = "test.a"
	corroborated_catalog.observations.append(corroborating_z)
	corroborated_catalog.observations.append(corroborating_a_duplicate)
	corroborated_catalog.observations.append(corroborating_a)
	corroborated_catalog.observations[0].corroborating_observation_ids = ["observed.hill.z", "observed.hill.a.duplicate", "observed.hill.a"]
	var corroborated: Dictionary = fidelity.compare_fleet(_comparison_fleet(CANONICAL_FLEET), corroborated_catalog)
	var corroborated_finding := _first_finding(corroborated, errors, "corroborated provenance emits a finding")
	if not corroborated_finding.is_empty():
		_expect(errors, corroborated_finding.corroborating_source_ids == ["test.a", "test.z"], "finding retains sorted unique corroborating source IDs")
		_expect(errors, corroborated_finding.caveats == ["a caveat", "fixture caveat", "shared caveat", "z caveat"], "finding deduplicates and sorts primary/corroborating caveats")

	var anchor_catalog := _comparison_catalog()
	anchor_catalog.selectors["semantic.hill"].legacy_anchor.kind = "missing"
	_assert_all_gaps(errors, fidelity.compare_fleet(_comparison_fleet(CANONICAL_FLEET), anchor_catalog), "anchor-not-found", "missing anchor")
	var gap_pairs := {}
	var anchor_gaps: Array = fidelity.compare_fleet(_comparison_fleet(CANONICAL_FLEET), anchor_catalog).get("evidence_gaps", [])
	for gap in anchor_gaps:
		gap_pairs["%s/%s" % [gap.target_id, gap.seed]] = true
	_expect(errors, gap_pairs.size() == 15, "evidence gaps contain at most one record per target and seed")
	if not anchor_gaps.is_empty():
		_expect(errors, anchor_gaps[0].seed == 1, "evidence gaps sort by target and numeric seed")


static func _test_fleet_validation(fidelity: Script, errors: PackedStringArray) -> void:
	var catalog := _comparison_catalog()
	var isolated := _held_comparison_fleet([0, 1])
	isolated[0].beats[0].rows[0].loads.normal_held_positive["0.80"] = 99.0
	_expect(errors, isolated[1].beats[0].rows[0].loads.normal_held_positive["0.80"] == 1.5, "nested seed-0 mutation does not leak into seed-1 fixture")
	var catalog_invalid := catalog.duplicate(true)
	catalog_invalid.targets[0].erase("aggregation")
	_expect(errors, fidelity.compare_fleet([], catalog_invalid) == {"status": "invalid-input", "reason": "catalog-invalid"}, "catalog validation has first precedence")
	var duplicate := _comparison_fleet(CANONICAL_FLEET)
	duplicate[-1].seed = duplicate[0].seed
	_expect_invalid_comparison(errors, fidelity.compare_fleet(duplicate, catalog), "fleet-invalid", "duplicate fleet seed")
	var missing := _comparison_fleet(CANONICAL_FLEET)
	missing.pop_back()
	_expect_invalid_comparison(errors, fidelity.compare_fleet(missing, catalog), "fleet-invalid", "missing fleet seed")
	var extra := _comparison_fleet(CANONICAL_FLEET)
	extra.append(_comparison_measurement(999, 1.5))
	_expect_invalid_comparison(errors, fidelity.compare_fleet(extra, catalog), "fleet-invalid", "extra fleet seed")
	var non_integer := _comparison_fleet(CANONICAL_FLEET)
	non_integer[0].seed = 11.0
	_expect_invalid_comparison(errors, fidelity.compare_fleet(non_integer, catalog), "fleet-invalid", "non-integer fleet seed")
	var malformed := _comparison_fleet(CANONICAL_FLEET)
	malformed[0].beats = null
	_expect_invalid_comparison(errors, fidelity.compare_fleet(malformed, catalog), "measurement-invalid", "malformed measurement")
	var duplicate_beat := _compiled_reducer_fleet(CANONICAL_FLEET)
	duplicate_beat[0].beats[1].beat_id = duplicate_beat[0].beats[0].beat_id
	_expect_invalid_comparison(errors, fidelity.compare_fleet(duplicate_beat, catalog), "measurement-invalid", "duplicate beat ID")
	var duplicate_row := _row_selection_fleet(CANONICAL_FLEET)
	duplicate_row[0].beats[0].rows[1].row_id = duplicate_row[0].beats[0].rows[0].row_id
	_expect_invalid_comparison(errors, fidelity.compare_fleet(duplicate_row, catalog), "measurement-invalid", "within-beat duplicate row ID")
	var nonfinite_metric := _comparison_fleet(CANONICAL_FLEET)
	nonfinite_metric[0].beats[0].rows[0].loads.normal_peak_positive = NAN
	_expect_invalid_comparison(errors, fidelity.compare_fleet(nonfinite_metric, catalog), "measurement-invalid", "non-finite selected metric")
	var missing_then_nonfinite := _compiled_reducer_fleet(CANONICAL_FLEET)
	missing_then_nonfinite[0].beats[0].rows[0].loads.erase("normal_peak_positive")
	missing_then_nonfinite[0].beats[1].rows[0].loads.normal_peak_positive = NAN
	_expect_invalid_comparison(errors, fidelity.compare_fleet(missing_then_nonfinite, catalog), "measurement-invalid", "a missing metric does not hide a later non-finite selected metric")
	var row_gap_then_nonfinite := _compiled_reducer_fleet(CANONICAL_FLEET)
	row_gap_then_nonfinite[0].beats[0].rows[0].row_id = "missing-row"
	row_gap_then_nonfinite[0].beats[1].rows[0].loads.normal_peak_positive = NAN
	_expect_invalid_comparison(
		errors, fidelity.compare_fleet(row_gap_then_nonfinite, catalog),
		"measurement-invalid", "a row gap does not hide a later non-finite selected metric"
	)
	var row_gap_then_missing := _compiled_reducer_fleet(CANONICAL_FLEET)
	row_gap_then_missing[0].beats[0].rows[0].row_id = "missing-row"
	row_gap_then_missing[0].beats[1].rows[0].loads.erase("normal_peak_positive")
	var row_gap_precedence: Dictionary = fidelity.compare_fleet(row_gap_then_missing, catalog)
	_expect(
		errors,
		row_gap_precedence.get("evidence_gaps", []).size() == 1
			and row_gap_precedence.evidence_gaps[0].reason == "row-not-found",
		"an ordinary row gap keeps precedence over an ordinary metric gap"
	)
	var malformed_loads := _comparison_fleet(CANONICAL_FLEET)
	malformed_loads[0].beats[0].rows[0].loads = NAN
	_expect_invalid_comparison(errors, fidelity.compare_fleet(malformed_loads, catalog), "measurement-invalid", "malformed selected loads container")
	for discriminator_case in [
		["schema-1", _comparison_fleet(CANONICAL_FLEET), ["phase", "kind"]],
		["schema-2", _compiled_reducer_fleet(CANONICAL_FLEET), ["story_slot_id", "window_role"]],
	]:
		for field in discriminator_case[2]:
			for value_case in [["missing"], ["empty", ""], ["non-string", 42], ["NaN", NAN]]:
				var malformed_discriminator: Array = discriminator_case[1].duplicate(true)
				if value_case.size() == 1:
					malformed_discriminator[0].beats[0].erase(field)
				else:
					malformed_discriminator[0].beats[0][field] = value_case[1]
				_expect_invalid_comparison(
					errors, fidelity.compare_fleet(malformed_discriminator, catalog),
					"measurement-invalid",
					"%s %s %s discriminator" % [discriminator_case[0], field, value_case[0]]
				)
	var position_catalog := _comparison_catalog()
	position_catalog.observations[0].alignment.generated_row_selector = {"position": "front"}
	for value_case in [
		["missing"], ["empty", ""], ["non-string", 42],
		["NaN", NAN], ["unsupported", "middle"],
	]:
		var malformed_position := _row_selection_fleet(CANONICAL_FLEET)
		if value_case.size() == 1:
			malformed_position[0].beats[0].rows[1].erase("position")
		else:
			malformed_position[0].beats[0].rows[1].position = value_case[1]
		_expect_invalid_comparison(
			errors, fidelity.compare_fleet(malformed_position, position_catalog),
			"measurement-invalid", "position selector rejects a %s row position" % value_case[0]
		)
	var row_id_position_control := _row_selection_fleet(CANONICAL_FLEET)
	row_id_position_control[0].beats[0].rows[1].erase("position")
	_expect(
		errors,
		fidelity.compare_fleet(row_id_position_control, catalog).get("findings", []).size() == 1,
		"a row-ID selector does not consume an unrelated row position"
	)
	var malformed_unavailable := _held_comparison_fleet(CANONICAL_FLEET)
	malformed_unavailable[0].beats[0].rows[0].loads.normal_held_positive = {"_unavailable": {"0.80": NAN}}
	_expect_invalid_comparison(errors, fidelity.compare_fleet(malformed_unavailable, _comparison_catalog("normal_held_positive", 0.8)), "measurement-invalid", "malformed selected unavailable record")
	var dual_held := _held_comparison_fleet(CANONICAL_FLEET)
	var dual_held_values: Dictionary = dual_held[0].beats[0].rows[0].loads.normal_held_positive
	dual_held_values["_unavailable"] = {"0.80": {"status": "unavailable", "reason": "insufficient_duration"}}
	_expect_invalid_comparison(
		errors, fidelity.compare_fleet(dual_held, _comparison_catalog("normal_held_positive", 0.8)),
		"measurement-invalid", "held metric cannot be both available and unavailable"
	)
	for invalid_reason in [42, [], true]:
		var non_string_reason := _held_comparison_fleet(CANONICAL_FLEET)
		non_string_reason[0].beats[0].rows[0].loads.normal_held_positive = {
			"_unavailable": {"0.80": {"status": "unavailable", "reason": invalid_reason}}
		}
		_expect_invalid_comparison(
			errors, fidelity.compare_fleet(non_string_reason, _comparison_catalog("normal_held_positive", 0.8)),
			"measurement-invalid", "held unavailability reason must be a String"
		)
	var nonfinite_duration := _comparison_fleet(CANONICAL_FLEET)
	nonfinite_duration[0].beats[0].rows[0].window_seconds = INF
	_expect_invalid_comparison(errors, fidelity.compare_fleet(nonfinite_duration, catalog), "measurement-invalid", "non-finite selected duration")
	var offset_catalog := _comparison_catalog()
	offset_catalog.observations[0].alignment.generated_row_selector = {"offset": 0.0}
	var nonfinite_offset := _comparison_fleet(CANONICAL_FLEET)
	nonfinite_offset[0].beats[0].rows[0].offset = NAN
	_expect_invalid_comparison(errors, fidelity.compare_fleet(nonfinite_offset, offset_catalog), "measurement-invalid", "non-finite selected row offset")
	var mixed := _comparison_fleet(CANONICAL_FLEET)
	mixed[0].schema_version = 2
	mixed[0].beats[0].story_slot_id = "act1.hill"
	mixed[0].beats[0].window_role = "core"
	_expect_invalid_comparison(errors, fidelity.compare_fleet(mixed, catalog), "mixed-representation", "mixed measurement schemas")
	var cross_beat_rows: Dictionary = fidelity.compare_fleet(_compiled_reducer_fleet(CANONICAL_FLEET), catalog)
	_expect(errors, cross_beat_rows.get("status", "") != "invalid-input", "row IDs may repeat across different beats")


static func _test_recommendation_eligibility(fidelity: Script, errors: PackedStringArray) -> void:
	var seven: Dictionary = fidelity.compare_fleet(_eligibility_fleet(7), _comparison_catalog())
	_expect(errors, seven.get("recommendation") == {"status": "no-eligible-finding"}, "seven affected seeds are ineligible")
	var eight: Dictionary = fidelity.compare_fleet(_eligibility_fleet(8), _comparison_catalog())
	_expect(errors, eight.get("recommendation") == {
		"status": "recommended", "target_id": "loads.hill.ejector",
		"normalized_median_miss": 0.25, "prevalence": 8.0 / 15.0,
		"confidence": "high",
	}, "eight affected seeds emit the exact compact recommendation")
	var eight_finding := _first_finding(eight, errors, "eight-seed comparison emits a finding")
	if not eight_finding.is_empty():
		_expect(errors, eight_finding.affected_count == 8 and eight_finding.available_count == 15 and eight_finding.gap_count == 0, "affected counts exclude within results and gaps")
		_expect_close(errors, eight_finding.prevalence, 8.0 / 15.0, "prevalence denominator is always fifteen")
		_expect_close(errors, eight_finding.normalized_median_miss, 0.25, "severity is the median normalized miss of affected seeds")
	var low_catalog := _comparison_catalog()
	low_catalog.observations[0].confidence = "low"
	var low: Dictionary = fidelity.compare_fleet(_eligibility_fleet(15), low_catalog)
	_expect(errors, low.get("recommendation") == {"status": "no-eligible-finding"}, "low confidence is always ineligible")
	var gap_fleet := _eligibility_fleet(8)
	gap_fleet[8].beats[0].rows[0].loads.erase("normal_peak_positive")
	var with_gap: Dictionary = fidelity.compare_fleet(gap_fleet, _comparison_catalog())
	var gap_finding := _first_finding(with_gap, errors, "gap denominator comparison emits a finding")
	if not gap_finding.is_empty():
		_expect(errors, gap_finding.affected_count == 8 and gap_finding.gap_count == 1, "gaps do not count as affected")
		_expect_close(errors, gap_finding.prevalence, 8.0 / 15.0, "gaps remain in the fifteen-seed denominator")
	var empty_catalog := _comparison_catalog()
	empty_catalog.targets = []
	var no_targets: Dictionary = fidelity.compare_fleet(_comparison_fleet(CANONICAL_FLEET), empty_catalog)
	_expect(errors, no_targets.get("recommendation") == {"status": "no-eligible-finding"}, "empty eligible set emits the exact no-result object")


static func _test_recommendation_ranking(fidelity: Script, errors: PackedStringArray) -> void:
	var fleet := _comparison_fleet([11,42,20260809,1,3,7,99,256,555,1234,4096,31337,77777,123456,20250101])
	var comparison: Dictionary = fidelity.compare_fleet(fleet, _comparison_catalog())
	_expect(errors, comparison.fleet == [11,42,20260809,1,3,7,99,256,555,1234,4096,31337,77777,123456,20250101], "canonical fleet order is preserved")
	_expect(errors, comparison.recommendation.target_id == "loads.hill.ejector", "normalized median miss wins deterministic ranking")
	var reversed := fleet.duplicate(true)
	reversed.reverse()
	var reordered: Dictionary = fidelity.compare_fleet(reversed, _comparison_catalog())
	_expect(errors, comparison.findings == reordered.findings, "finding order is independent of input map order")

	for ranking_case in [
		{"specs": [{"id": "rank.lower", "miss": 0.20, "affected": 15, "confidence": "high"}, {"id": "rank.severity", "miss": 0.30, "affected": 8, "confidence": "medium"}], "expected": "rank.severity", "message": "severity ranks first"},
		{"specs": [{"id": "rank.eight", "miss": 0.20, "affected": 8, "confidence": "high"}, {"id": "rank.prevalence", "miss": 0.20, "affected": 9, "confidence": "medium"}], "expected": "rank.prevalence", "message": "prevalence breaks severity ties"},
		{"specs": [{"id": "rank.medium", "miss": 0.20, "affected": 8, "confidence": "medium"}, {"id": "rank.high", "miss": 0.20, "affected": 8, "confidence": "high"}], "expected": "rank.high", "message": "confidence breaks prevalence ties"},
		{"specs": [{"id": "rank.z", "miss": 0.20, "affected": 8, "confidence": "high"}, {"id": "rank.a", "miss": 0.20, "affected": 8, "confidence": "high"}], "expected": "rank.a", "message": "target ID breaks complete ties"},
	]:
		var ranked: Dictionary = fidelity.compare_fleet(_ranking_fleet(ranking_case.specs), _ranking_catalog(ranking_case.specs))
		_expect(errors, ranked.get("recommendation", {}).get("target_id") == ranking_case.expected, ranking_case.message)
		var finding_ids := []
		for finding in ranked.get("findings", []):
			finding_ids.append(finding.target_id)
		var sorted_ids := finding_ids.duplicate()
		sorted_ids.sort()
		_expect(errors, finding_ids == sorted_ids, "findings sort by target ID")


static func _test_comparison_determinism(fidelity: Script, errors: PackedStringArray) -> void:
	var catalog := _comparison_catalog()
	var catalog_before := catalog.duplicate(true)
	var fleet := _comparison_fleet(CANONICAL_FLEET)
	var comparison: Dictionary = fidelity.compare_fleet(fleet, catalog)
	_expect(errors, catalog == catalog_before, "comparison does not reorder its catalog inputs")
	var expected_top_keys := PackedStringArray(["fleet", "findings", "observed_only", "evidence_gaps", "recommendation"])
	var actual_top_keys := PackedStringArray(comparison.keys())
	expected_top_keys.sort()
	actual_top_keys.sort()
	_expect(errors, actual_top_keys == expected_top_keys, "comparison emits the exact result algebra")
	var finding := _first_finding(comparison, errors, "deterministic comparison emits a finding")
	if not finding.is_empty():
		var nested_seeds := []
		for result in finding.seed_results:
			nested_seeds.append(result.seed)
		var sorted_seeds := nested_seeds.duplicate()
		sorted_seeds.sort()
		_expect(errors, nested_seeds == sorted_seeds, "nested seed results sort numerically")
		var expected_finding_keys := PackedStringArray([
			"target_id", "observation_id", "primary_source_ids", "corroborating_source_ids", "caveats",
			"transform_id", "semantic_selector_id", "dimension", "metric", "hold_seconds",
			"resolved_branch", "anchor", "row_compatibility", "generated_row_selector", "aggregation",
			"raw_range", "target_range", "seed_results", "fleet_value", "fleet_status",
			"total_retained_seconds", "affected_count", "available_count", "gap_count", "prevalence",
			"normalized_median_miss", "observation_confidence",
		])
		var actual_finding_keys := PackedStringArray(finding.keys())
		expected_finding_keys.sort()
		actual_finding_keys.sort()
		_expect(errors, actual_finding_keys == expected_finding_keys, "finding emits every required provenance and aggregation field")
	var perturbed := fleet.duplicate(true)
	for measurement in perturbed:
		var loads: Dictionary = measurement.beats[0].rows[0].loads
		var selected: Variant = loads.normal_peak_positive
		loads.erase("normal_peak_positive")
		loads["unused_metric"] = -123.0
		loads["normal_peak_positive"] = selected
	var perturbed_comparison: Dictionary = fidelity.compare_fleet(perturbed, catalog)
	_expect(errors, comparison.get("findings", []) == perturbed_comparison.get("findings", []), "dictionary insertion order does not affect findings")
	_expect(errors, _count_dictionary_key(comparison, "score") == 0, "comparison recursively forbids score")
	_expect(errors, _count_dictionary_key(comparison, "total_score") == 0, "comparison recursively forbids total_score")
	if not finding.is_empty():
		finding.anchor.kind = "mutated"
		finding.aggregation.row = "maximum"
		finding.raw_range[0] = -999.0
		finding.target_range[0] = -999.0
		_expect(errors, catalog == catalog_before, "returned finding fields cannot mutate the catalog")


static func _first_finding(comparison: Dictionary, errors: PackedStringArray, message: String) -> Dictionary:
	var findings: Variant = comparison.get("findings", [])
	if not findings is Array or findings.is_empty() or not findings[0] is Dictionary:
		errors.append(message)
		return {}
	return findings[0]


static func _assert_all_gaps(
	errors: PackedStringArray, comparison: Dictionary, reason: String, message: String
) -> void:
	var gaps: Variant = comparison.get("evidence_gaps", [])
	_expect(errors, gaps is Array and gaps.size() == 15, "%s emits one gap per seed" % message)
	if gaps is Array:
		for gap in gaps:
			_expect(errors, gap.get("reason") == reason, "%s reports %s" % [message, reason])


static func _expect_invalid_comparison(
	errors: PackedStringArray, actual: Dictionary, reason: String, message: String
) -> void:
	_expect(errors, actual == {"status": "invalid-input", "reason": reason}, "%s rejects the whole comparison" % message)


static func _measurement_route() -> Dictionary:
	var positions := PackedVector3Array()
	var distances := PackedFloat32Array()
	var times := PackedFloat32Array()
	for i in 41:
		var height := float(mini(i, 20 - i)) if i <= 20 else 0.0
		positions.append(Vector3(i, height, 0.0))
		distances.append(float(i))
		times.append(i * 0.1)
	var fixture := RouteFixture.new().seed(7).length(40.0).duration(4.0)
	fixture.points(positions).distances(distances).times(times)
	fixture.tangents(RouteFixture.flat_vector3(Vector3.RIGHT, 41))
	fixture.ups(RouteFixture.flat_vector3(Vector3.UP, 41))
	fixture.rights(RouteFixture.flat_vector3(Vector3.FORWARD, 41))
	fixture.curvatures(RouteFixture.flat_vector3(Vector3.ZERO, 41))
	fixture.banks(RouteFixture.flat_float(0.0, 41)).speeds(RouteFixture.flat_float(10.0, 41))
	fixture.channel("normal_g", RouteFixture.flat_float(1.0, 41))
	fixture.channel("lateral_g", RouteFixture.flat_float(0.0, 41))
	fixture.channel("longitudinal_g", RouteFixture.flat_float(0.0, 41))
	fixture.channel("roll_rates", RouteFixture.flat_float(0.0, 41))
	fixture.span_indices(RouteFixture.span_indices_for(41, [20, 30]))
	fixture.gesture_windows([
		_gesture_window("act1.hill", "core", "hill", "Hill", 0, 19),
		_gesture_window("act1.transfer", "whole", "transfer", "Transfer", 20, 29),
		_gesture_window("return.capture", "whole", "capture", "Capture", 30, 40),
	])
	return fixture.build()


static func _irregular_pacing_route() -> Dictionary:
	var distances := PackedFloat32Array([0.0, 2.0, 5.0, 11.0, 13.0])
	var times := PackedFloat32Array([0.0, 0.2, 0.5, 1.1, 1.3])
	var positions := PackedVector3Array()
	for index in times.size():
		positions.append(Vector3(distances[index], 5.0, 0.0))
	var count := times.size()
	var fixture := RouteFixture.new().seed(8).length(13.0).duration(1.3)
	fixture.points(positions).distances(distances).times(times)
	fixture.tangents(RouteFixture.flat_vector3(Vector3.RIGHT, count))
	fixture.ups(RouteFixture.flat_vector3(Vector3.UP, count))
	fixture.rights(RouteFixture.flat_vector3(Vector3.FORWARD, count))
	fixture.curvatures(RouteFixture.flat_vector3(Vector3.ZERO, count))
	fixture.banks(PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0]))
	fixture.speeds(PackedFloat32Array([10.0, 60.0, 60.0, 60.0, 10.0]))
	fixture.channel("normal_g", PackedFloat32Array([1.0, 2.0, 2.0, 2.0, 1.0]))
	fixture.channel("lateral_g", PackedFloat32Array([0.0, 0.5, 0.5, 0.5, 0.0]))
	fixture.channel("longitudinal_g", PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0]))
	fixture.channel("roll_rates", PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0]))
	fixture.span_indices(RouteFixture.span_indices_for(count, []))
	fixture.gesture_windows([_gesture_window(
		"act1.pacing", "whole", "pacing", "Pacing", 0, count - 1)])
	return fixture.build()


static func _moving_window_route(extra_preceding_knot: bool) -> Dictionary:
	var times := PackedFloat32Array([0.0, 0.003, 0.303, 0.613, 0.913, 0.914, 1.0])
	var normal := PackedFloat32Array([4.0, 1.5, 1.5, 1.5, 1.5, -3.0, -3.0])
	if extra_preceding_knot:
		times.insert(1, 0.0015)
		normal.insert(1, 2.75)
	var positions := PackedVector3Array()
	var distances := PackedFloat32Array()
	for index in times.size():
		var distance := times[index] * 10.0
		positions.append(Vector3(distance, 5.0, 0.0))
		distances.append(distance)
	var selected_first := 2 if extra_preceding_knot else 1
	var selected_last := selected_first + 3
	var count := times.size()
	var fixture := RouteFixture.new().seed(9).length(distances[-1]).duration(times[-1])
	fixture.points(positions).distances(distances).times(times)
	fixture.tangents(RouteFixture.flat_vector3(Vector3.RIGHT, count))
	fixture.ups(RouteFixture.flat_vector3(Vector3.UP, count))
	fixture.rights(RouteFixture.flat_vector3(Vector3.FORWARD, count))
	fixture.curvatures(RouteFixture.flat_vector3(Vector3.ZERO, count))
	fixture.banks(RouteFixture.flat_float(0.0, count)).speeds(RouteFixture.flat_float(10.0, count))
	fixture.channel("normal_g", normal)
	fixture.channel("lateral_g", RouteFixture.flat_float(0.0, count))
	fixture.channel("longitudinal_g", RouteFixture.flat_float(0.0, count))
	fixture.channel("roll_rates", RouteFixture.flat_float(0.0, count))
	fixture.span_indices(RouteFixture.span_indices_for(count, [selected_first, selected_last + 1]))
	fixture.gesture_windows([
		_gesture_window("act1.before", "whole", "before", "Before", 0, selected_first - 1),
		_gesture_window("act1.selected", "core", "selected", "Selected", selected_first, selected_last),
		_gesture_window("act1.after", "whole", "after", "After", selected_last + 1, count - 1),
	])
	return fixture.build()


static func _transition_route(seam_seconds: float) -> Dictionary:
	var route := _uniform_route(3.0)
	var seam := roundi(seam_seconds * 100.0)
	for index in route.times.size():
		if index < seam:
			route.banks[index] = -20.0
			route.roll_rates[index] = -30.0
		elif index > seam:
			route.banks[index] = 25.0
			route.roll_rates[index] = 45.0
		if index >= seam - 50 and index < seam:
			route.normal_g[index] = 3.0
		elif index > seam and index <= seam + 50:
			route.normal_g[index] = -1.0
	route.span_indices = RouteFixture.span_indices_for(route.times.size(), [seam])
	route.gesture_windows = [
		_gesture_window("act1.before", "whole", "before", "Before", 0, seam - 1),
		_gesture_window("act1.after", "whole", "after", "After", seam, route.times.size() - 1),
	]
	return route


static func _uniform_route(seconds: float) -> Dictionary:
	var count := roundi(seconds * 100.0) + 1
	var positions := PackedVector3Array()
	var distances := PackedFloat32Array()
	var times := PackedFloat32Array()
	for index in count:
		var time := index * 0.01
		positions.append(Vector3(time * 10.0, 5.0, 0.0))
		distances.append(index * 0.1)
		times.append(time)
	var fixture := RouteFixture.new().seed(10).length(distances[-1]).duration(seconds)
	fixture.points(positions).distances(distances).times(times)
	fixture.tangents(RouteFixture.flat_vector3(Vector3.RIGHT, count))
	fixture.ups(RouteFixture.flat_vector3(Vector3.UP, count))
	fixture.rights(RouteFixture.flat_vector3(Vector3.FORWARD, count))
	fixture.curvatures(RouteFixture.flat_vector3(Vector3.ZERO, count))
	fixture.banks(RouteFixture.flat_float(0.0, count)).speeds(RouteFixture.flat_float(10.0, count))
	fixture.channel("normal_g", RouteFixture.flat_float(1.0, count))
	fixture.channel("lateral_g", RouteFixture.flat_float(0.0, count))
	fixture.channel("longitudinal_g", RouteFixture.flat_float(0.0, count))
	fixture.channel("roll_rates", RouteFixture.flat_float(0.0, count))
	fixture.span_indices(RouteFixture.span_indices_for(count, []))
	fixture.gesture_windows([_gesture_window(
		"whole.route", "whole", "route", "Route", 0, count - 1)])
	return fixture.build()


static func _analytic_straight_route(speed: float, seconds: float, sample_hz: float) -> Dictionary:
	var count := roundi(seconds * sample_hz) + 1
	var positions := PackedVector3Array()
	var distances := PackedFloat32Array()
	var times := PackedFloat32Array()
	for index in count:
		var time := index / sample_hz
		positions.append(Vector3(speed * time, 0.0, 0.0))
		distances.append(speed * time)
		times.append(time)
	var zero := RouteFixture.flat_float(0.0, count)
	return _analytic_route(positions, RouteFixture.flat_vector3(Vector3.RIGHT, count),
		RouteFixture.flat_vector3(Vector3.UP, count), RouteFixture.flat_vector3(Vector3.FORWARD, count),
		RouteFixture.flat_vector3(Vector3.ZERO, count), RouteFixture.flat_float(1.0, count),
		zero, zero, zero, RouteFixture.flat_float(speed, count), distances, times, [])


static func _analytic_circle_route(speed: float, radius: float, seconds: float, sample_hz: float) -> Dictionary:
	var count := roundi(seconds * sample_hz) + 1
	var positions := PackedVector3Array()
	var tangents := PackedVector3Array()
	var rights := PackedVector3Array()
	var curvatures := PackedVector3Array()
	var lateral := PackedFloat32Array()
	var distances := PackedFloat32Array()
	var times := PackedFloat32Array()
	for index in count:
		var time := index / sample_hz
		var angle := speed * time / radius
		var inward := Vector3(-cos(angle), 0.0, -sin(angle))
		positions.append(Vector3(radius * (cos(angle) - 1.0), 0.0, radius * sin(angle)))
		tangents.append(Vector3(-sin(angle), 0.0, cos(angle)))
		rights.append(inward)
		curvatures.append(inward / radius)
		lateral.append(speed * speed / radius / 9.80665)
		distances.append(speed * time)
		times.append(time)
	var zero := RouteFixture.flat_float(0.0, count)
	return _analytic_route(positions, tangents, RouteFixture.flat_vector3(Vector3.UP, count),
		rights, curvatures, RouteFixture.flat_float(1.0, count), lateral, zero, zero,
		RouteFixture.flat_float(speed, count), distances, times, [])


static func _nonuniform_quadratic_route() -> Dictionary:
	var times := PackedFloat32Array([0.0, 0.07, 0.21, 0.5, 0.9, 1.4])
	var positions := PackedVector3Array()
	var distances := PackedFloat32Array()
	for time in times:
		var distance := 5.0 * time + time * time
		positions.append(Vector3(distance, 0.0, 0.0))
		distances.append(distance)
	var count := times.size()
	# Deliberately inconsistent: acceleration must come from raw position/time, not the speed
	# channel, so speed stays a flat 5 m/s regardless of the quadratic position/time relation.
	return _analytic_route(positions, RouteFixture.flat_vector3(Vector3.RIGHT, count),
		RouteFixture.flat_vector3(Vector3.UP, count), RouteFixture.flat_vector3(Vector3.FORWARD, count),
		RouteFixture.flat_vector3(Vector3.ZERO, count), RouteFixture.flat_float(1.0, count),
		RouteFixture.flat_float(0.0, count), RouteFixture.flat_float(2.0 / 9.80665, count),
		RouteFixture.flat_float(0.0, count), RouteFixture.flat_float(5.0, count),
		distances, times, [])


static func _curvature_direction_seam_route() -> Dictionary:
	const SPEED := 25.0
	const RADIUS := 50.0
	const SAMPLE_HZ := 100.0
	const SEAM := 100
	const COUNT := 201
	var positions := PackedVector3Array()
	var tangents := PackedVector3Array()
	var ups := PackedVector3Array()
	var rights := PackedVector3Array()
	var curvatures := PackedVector3Array()
	var normal := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	var roll_rates := PackedFloat32Array()
	var distances := PackedFloat32Array()
	var times := PackedFloat32Array()
	for index in COUNT:
		var angle := (index - SEAM) * SPEED / SAMPLE_HZ / RADIUS
		if index <= SEAM:
			var horizontal_inward := Vector3(-cos(angle), 0.0, -sin(angle))
			positions.append(Vector3(RADIUS * cos(angle), 0.0, RADIUS * sin(angle)))
			tangents.append(Vector3(-sin(angle), 0.0, cos(angle)))
			ups.append(Vector3.UP)
			rights.append(horizontal_inward)
			curvatures.append(horizontal_inward / RADIUS)
			normal.append(1.0)
			lateral.append(SPEED * SPEED / RADIUS / 9.80665)
		else:
			var vertical_inward := Vector3(0.0, cos(angle), -sin(angle))
			positions.append(Vector3(RADIUS, RADIUS - RADIUS * cos(angle), RADIUS * sin(angle)))
			tangents.append(Vector3(0.0, sin(angle), cos(angle)))
			ups.append(vertical_inward)
			rights.append(Vector3.LEFT)
			curvatures.append(vertical_inward / RADIUS)
			normal.append(SPEED * SPEED / RADIUS / 9.80665 + vertical_inward.y)
			lateral.append(0.0)
		roll_rates.append(index * 0.5)
		distances.append(index * SPEED / SAMPLE_HZ)
		times.append(index / SAMPLE_HZ)
	return _analytic_route(positions, tangents, ups, rights, curvatures, normal, lateral,
		RouteFixture.flat_float(0.0, COUNT), roll_rates, RouteFixture.flat_float(SPEED, COUNT),
		distances, times, [SEAM])


static func _analytic_route(
	positions: PackedVector3Array, tangents: PackedVector3Array, ups: PackedVector3Array,
	rights: PackedVector3Array, curvatures: PackedVector3Array, normal: PackedFloat32Array,
	lateral: PackedFloat32Array, longitudinal: PackedFloat32Array, roll_rates: PackedFloat32Array,
	speeds: PackedFloat32Array, distances: PackedFloat32Array, times: PackedFloat32Array,
	span_starts: Array
) -> Dictionary:
	var fixture := RouteFixture.new().seed(500).length(distances[-1]).duration(times[-1])
	fixture.points(positions).tangents(tangents).ups(ups).rights(rights).curvatures(curvatures)
	fixture.banks(RouteFixture.flat_float(0.0, times.size())).speeds(speeds)
	fixture.channel("normal_g", normal).channel("lateral_g", lateral)
	fixture.channel("longitudinal_g", longitudinal).channel("roll_rates", roll_rates)
	fixture.distances(distances).times(times)
	fixture.span_indices(RouteFixture.span_indices_for(times.size(), span_starts))
	fixture.gesture_windows([])
	return fixture.build()


static func _gesture_window(
	story_slot_id: String, role: String, kind: String, display_name: String,
	first: int, last: int, occurrence: int = 0
) -> Dictionary:
	return {
		"story_slot_id": story_slot_id,
		"role_windows": [_role_window(
			story_slot_id, role, kind, display_name, first, last, occurrence)],
	}


static func _role_window(
	story_slot_id: String, role: String, kind: String, display_name: String,
	first: int, last: int, occurrence: int = 0
) -> Dictionary:
	return {
		"id": role, "display_name": display_name, "diagnostic_kind": kind,
		"occurrence": occurrence,
		"window_id": "%s/%s/%02d-%s" % [story_slot_id, role, occurrence, kind],
		"first": first, "last": last,
	}


static func _comparison_catalog(
	metric: String = "normal_peak_positive", hold_seconds: Variant = null
) -> Dictionary:
	var catalog := _valid_catalog_v2()
	catalog.selectors = {
		"semantic.hill": {
			"legacy_anchor": {"phase": "act one", "kind": "hill", "occurrence": 0, "window_role": "whole"},
			"compiled_anchor": {"story_slot_id": "act1.hill", "window_role": "core"},
		},
	}
	catalog.sources = {"test.primary": _comparison_source("primary", "a".repeat(64))}
	catalog.transforms = {
		"observed.identity@1": {
			"kind": "identity", "factor": 1.0, "formula": "target_value = observed_value",
			"approval": "identity; no transform",
		},
	}
	catalog.observations = [
		_comparison_observation(
			"observed.hill", "semantic.hill", metric, hold_seconds, "high"
		),
	]
	catalog.targets = [
		_comparison_target(
			"loads.hill.ejector", "observed.hill", "semantic.hill", metric, hold_seconds
		),
	]
	catalog.review_prompts = []
	catalog.evidence_gaps = []
	return catalog


static func _comparison_catalog_with_aggregation(
	row_reducer: String, beat_reducer: String, seed_reducer: String
) -> Dictionary:
	var catalog := _comparison_catalog()
	catalog.observations[0].alignment.row_compatibility = "row-independent"
	catalog.observations[0].alignment.generated_row_selector = null
	catalog.targets[0].aggregation = {
		"row": row_reducer, "beat": beat_reducer, "seed": seed_reducer,
	}
	return catalog


static func _comparison_catalog_with_observed_only() -> Dictionary:
	var catalog := _comparison_catalog()
	catalog.selectors["semantic.entry"] = {
		"legacy_anchor": {"phase": "act one", "kind": "entry", "occurrence": 0, "window_role": "whole"},
		"compiled_anchor": {"story_slot_id": "act1.entry", "window_role": "entry"},
	}
	catalog.selectors["semantic.exit"] = {
		"legacy_anchor": {"phase": "act one", "kind": "exit", "occurrence": 0, "window_role": "whole"},
		"compiled_anchor": {"story_slot_id": "act1.exit", "window_role": "exit"},
	}
	var entry := _comparison_observation(
		"observed.hill.entry", "semantic.entry", "normal_peak_positive", null, "medium"
	)
	entry.alignment.row_compatibility = "row-independent"
	entry.alignment.generated_row_selector = null
	catalog.observations.append(_comparison_observation(
		"observed.hill.exit", "semantic.exit", "normal_peak_positive", null, "medium"
	))
	catalog.observations.append(entry)
	return catalog


static func _comparison_source(label: String, digest: String) -> Dictionary:
	var source := _synthetic_raw_source(label, digest)
	source.initial_state = "executable"
	source.state = "executable"
	source.row_seat = "provenance text: row ninety-nine; never parse"
	source.caveats = ["fixture caveat"]
	return source


static func _comparison_observation(
	observation_id: String, selector_id: String, metric: String,
	hold_seconds: Variant, confidence: String
) -> Dictionary:
	return {
		"id": observation_id, "state": "executable", "source_id": "test.primary",
		"source_window_id": "tormenta.loop", "source_axis": "vertical", "mapped_axis": "normal_g",
		"row_seat": "provenance text: row ninety-nine; never parse", "duration_s": 2.0,
		"metric": metric, "hold_seconds": hold_seconds, "raw_range": [1.0, 2.0],
		"transform_id": "observed.identity@1", "confidence": confidence,
		"confidence_rationale": "deterministic synthetic comparison fixture",
		"corroborating_observation_ids": [], "semantic_selector_id": selector_id,
		"alignment": {
			"source_landmark_id": "tormenta.loop",
			"generated_anchor": {"semantic_selector_id": selector_id},
			"method": "synthetic exact anchor", "uncertainty_s": 0.0,
			"row_compatibility": "same-row", "generated_row_selector": {"row_id": "row-01"},
			"rationale": "comparison contract fixture",
		},
	}


static func _comparison_target(
	target_id: String, observation_id: String, selector_id: String,
	metric: String, hold_seconds: Variant
) -> Dictionary:
	return {
		"id": target_id, "observation_id": observation_id,
		"semantic_selector_id": selector_id, "dimension": "loads", "metric": metric,
		"hold_seconds": hold_seconds, "raw_range": [1.0, 2.0], "target_range": [1.0, 2.0],
		"issues": [3], "aggregation": {"row": "median", "beat": "median", "seed": "median"},
	}


static func _comparison_fleet(seeds: Array) -> Array:
	var fleet := []
	for seed_value in seeds:
		var canonical_index := CANONICAL_FLEET.find(seed_value)
		var value := 0.5 if canonical_index >= 0 and canonical_index < 8 else 1.5
		fleet.append(_comparison_measurement(seed_value, value))
	return fleet


static func _eligibility_fleet(affected_count: int) -> Array:
	var affected_values := [0.9, 0.8, 0.7, 0.6, 0.4, 0.2, 0.0, -1.0, -1.2, -1.4, -1.6, -1.8, -2.0, -2.2, -2.4]
	var fleet := []
	for index in CANONICAL_FLEET.size():
		fleet.append(_comparison_measurement(CANONICAL_FLEET[index], affected_values[index] if index < affected_count else 1.5))
	return fleet


static func _comparison_measurement(seed_value: Variant, value: float) -> Dictionary:
	return {
		"schema_version": 1, "seed": seed_value,
		"beats": [
			_legacy_comparison_beat(
				"legacy-hill", "act one", "hill",
				[_comparison_row("row-01", "front", 0.0, 2.0, value)]
			),
		],
	}


static func _seed_reducer_fleet(seeds: Array) -> Array:
	var values := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 8.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0, 100.0]
	var fleet := []
	for seed_value in seeds:
		fleet.append(_comparison_measurement(seed_value, values[CANONICAL_FLEET.find(seed_value)]))
	return fleet


static func _compiled_reducer_fleet(seeds: Array) -> Array:
	var fleet := []
	for seed_value in seeds:
		fleet.append({
			"schema_version": 2, "seed": seed_value,
			"beats": [
				_compiled_comparison_beat("compiled-a", "act1.hill", "core", [
					_comparison_row("row-01", "front", 0.0, 1.0, 1.0),
					_comparison_row("row-02", "intermediate", 1.0, 2.0, 2.0),
					_comparison_row("row-03", "rear", 2.0, 4.0, 10.0),
				]),
				_compiled_comparison_beat("compiled-b", "act1.hill", "core", [
					_comparison_row("row-01", "front", 0.0, 2.0, 3.0),
					_comparison_row("row-02", "intermediate", 1.0, 3.0, 20.0),
					_comparison_row("row-03", "rear", 2.0, 5.0, 30.0),
				]),
				_compiled_comparison_beat("compiled-c", "act1.hill", "core", [
					_comparison_row("row-01", "front", 0.0, 1.0, 4.0),
					_comparison_row("row-02", "intermediate", 1.0, 4.0, 5.0),
					_comparison_row("row-03", "rear", 2.0, 6.0, 100.0),
				]),
			],
		})
	return fleet


static func _repeat_measurement_template(seeds: Array, template: Dictionary) -> Array:
	var fleet := []
	for seed_value in seeds:
		var measurement := template.duplicate(true)
		measurement.seed = seed_value
		fleet.append(measurement)
	return fleet


static func _held_comparison_fleet(seeds: Array) -> Array:
	return _repeat_measurement_template(seeds, {
		"schema_version": 1, "seed": 0,
		"beats": [_legacy_comparison_beat(
			"legacy-held", "act one", "hill",
			[_comparison_row("row-01", "front", 0.0, 5.0, 1.5, "normal_held_positive", 0.8)]
		)],
	})


static func _legacy_occurrence_fleet(seeds: Array) -> Array:
	return _repeat_measurement_template(seeds, {
		"schema_version": 1, "seed": 0,
		"beats": [
			_legacy_comparison_beat("legacy-match-01", "act one", "hill", [_comparison_row("row-01", "front", 0.0, 1.0, 1.0)], 99),
			_legacy_comparison_beat("legacy-wrong-kind", "act one", "turn", [_comparison_row("row-01", "front", 0.0, 1.0, 99.0)], 0),
			_legacy_comparison_beat("legacy-wrong-phase", "other", "hill", [_comparison_row("row-01", "front", 0.0, 1.0, 98.0)], 0),
			_legacy_comparison_beat("legacy-match-02", "act one", "hill", [_comparison_row("row-01", "front", 0.0, 1.0, 3.0)], 0),
		],
	})


static func _compiled_fallback_trap_fleet(seeds: Array) -> Array:
	var beat := _compiled_comparison_beat(
		"compiled-wrong", "wrong.slot", "core",
		[_comparison_row("row-01", "front", 0.0, 2.0, 1.5)]
	)
	beat.phase = "act one"
	beat.kind = "hill"
	return _repeat_measurement_template(seeds, {"schema_version": 2, "seed": 0, "beats": [beat]})


static func _compiled_wrong_role_fleet(seeds: Array) -> Array:
	var beat := _compiled_comparison_beat(
		"compiled-wrong-role", "act1.hill", "entry",
		[_comparison_row("row-01", "front", 0.0, 2.0, 1.5)]
	)
	beat.phase = "act one"
	beat.kind = "hill"
	return _repeat_measurement_template(seeds, {"schema_version": 2, "seed": 0, "beats": [beat]})


static func _row_selection_fleet(seeds: Array) -> Array:
	return _repeat_measurement_template(seeds, {
		"schema_version": 1, "seed": 0,
		"beats": [_legacy_comparison_beat("legacy-hill", "act one", "hill", [
			_comparison_row("row-01", "front", 0.0, 1.0, 1.0),
			_comparison_row("row-02", "rear", 2.0, 3.0, 2.0),
		])],
	})


static func _ambiguous_row_fleet(seeds: Array) -> Array:
	var fleet := _row_selection_fleet(seeds)
	for measurement in fleet:
		measurement.beats[0].rows[0].position = "intermediate"
		measurement.beats[0].rows[1].position = "intermediate"
	return fleet


static func _observed_only_fleet(seeds: Array) -> Array:
	return _repeat_measurement_template(seeds, {
		"schema_version": 2, "seed": 0,
		"beats": [
			_compiled_comparison_beat("target-hill", "act1.hill", "core", [_comparison_row("row-01", "front", 0.0, 2.0, 0.5)]),
			_compiled_comparison_beat("entry-b", "act1.entry", "entry", [
				_comparison_row("row-02", "rear", 2.0, 3.0, 6.0),
				_comparison_row("row-01", "front", 0.0, 1.0, 7.0),
			]),
			_compiled_comparison_beat("entry-a", "act1.entry", "entry", [
				_comparison_row("row-02", "rear", 2.0, 4.0, 8.0),
				_comparison_row("row-01", "front", 0.0, 2.0, 9.0),
			]),
			_compiled_comparison_beat("exit-a", "act1.exit", "exit", [_comparison_row("row-01", "front", 0.0, 1.0, 10.0)]),
		],
	})


static func _ranking_catalog(specs: Array) -> Dictionary:
	var catalog := _comparison_catalog()
	catalog.selectors = {}
	catalog.observations = []
	catalog.targets = []
	for index in specs.size():
		var spec: Dictionary = specs[index]
		var selector_id := "semantic.rank.%02d" % index
		var observation_id := "observed.rank.%02d" % index
		var kind := "rank-kind-%02d" % index
		catalog.selectors[selector_id] = {
			"legacy_anchor": {"phase": "ranking", "kind": kind, "occurrence": 0, "window_role": "whole"},
			"compiled_anchor": {"story_slot_id": "ranking.slot.%02d" % index, "window_role": "core"},
		}
		catalog.observations.append(_comparison_observation(
			observation_id, selector_id, "normal_peak_positive", null, spec.confidence
		))
		catalog.targets.append(_comparison_target(
			spec.id, observation_id, selector_id, "normal_peak_positive", null
		))
	return catalog


static func _ranking_fleet(specs: Array) -> Array:
	var fleet := []
	for seed_index in CANONICAL_FLEET.size():
		var beats := []
		for spec_index in specs.size():
			var spec: Dictionary = specs[spec_index]
			var value := 1.0 - float(spec.miss) * 2.0 if seed_index < int(spec.affected) else 1.5
			beats.append(_legacy_comparison_beat(
				"rank-beat-%02d" % spec_index, "ranking", "rank-kind-%02d" % spec_index,
				[_comparison_row("row-01", "front", 0.0, 1.0, value)]
			))
		fleet.append({"schema_version": 1, "seed": CANONICAL_FLEET[seed_index], "beats": beats})
	return fleet


static func _legacy_comparison_beat(
	beat_id: String, phase: String, kind: String, rows: Array, ordinal: int = 0
) -> Dictionary:
	return {
		"beat_id": beat_id, "phase": phase, "ordinal": ordinal, "kind": kind, "rows": rows,
	}


static func _compiled_comparison_beat(
	beat_id: String, story_slot_id: String, window_role: String, rows: Array
) -> Dictionary:
	return {
		"beat_id": beat_id, "story_slot_id": story_slot_id,
		"window_role": window_role, "rows": rows,
	}


static func _comparison_row(
	row_id: String, position: String, offset: float, seconds: float, value: float,
	metric: String = "normal_peak_positive", hold_seconds: Variant = null
) -> Dictionary:
	var loads := {"normal_peak_negative": -9.0}
	if hold_seconds == null:
		loads[metric] = value
	else:
		loads[metric] = {"%.2f" % float(hold_seconds): value}
	return {
		"row_id": row_id, "position": position, "offset": offset,
		"window_seconds": seconds, "loads": loads,
	}


static func _valid_catalog_v2() -> Dictionary:
	return {
		"schema_version": 2,
		"catalog_version": "2026-08-10.baseline.1",
		"selectors": {
			"semantic.act1.loop.core": {
				"legacy_anchor": {"phase": "act one", "kind": "loop", "occurrence": 0, "window_role": "whole"},
				"compiled_anchor": {"story_slot_id": "act1.helical_loop", "window_role": "core"},
			},
		},
		"sources": {
			"rideforcesdb.tormenta.6383": {
				"initial_state": "corroborative", "state": "corroborative",
				"permitted_contributions": ["reviewed force windows with row and device caveats"],
				"permitted_axes": ["normal_g", "lateral_g", "longitudinal_g"],
				"promotion_prerequisites": ["Requires raw provenance, complete alignment, and independent corroboration."],
				"acquisition": "raw_fetch_unavailable",
				"url": "https://rideforcesdb.com/getRec?id=6383", "recording_id": "6383",
				"retrieved_on": "2026-08-10", "retrieval_context": "RideForcesDB response",
				"diagnostic_path": "docs/evidence/fidelity/rideforcesdb/6383-diagnostic.json",
				"diagnostic_sha256": "a40a3bf86a5f12eeebcb72da2f8b7dde857d17c34b32d98ec862576176610b79",
				"metadata_artifact_path": "docs/evidence/fidelity/rideforcesdb/6383-ride-info.json",
				"metadata_artifact_sha256": "95ce0416f6cc0790c5fd5b07ba7472d240f8b17cbc06d6da6f8821b43eabda61",
				"review_path": "docs/evidence/fidelity/rideforcesdb/6383-review.json",
				"review_sha256": "40ab3696c7aaea6332fc01728987d72a67a421ba4df805c5f38bec33ddc97db6",
				"row_seat": "Row 2, Seat 8, Train 1", "device": "iPhone; exact model unverified", "sample_rate_hz": null,
				"axis_mapping": {}, "reliability": "requires corroboration",
				"processing": ["reviewed corpus windows only"],
				"caveats": ["native sample rate is unknown", "raw axis mapping is unverified", "angle channel is unavailable"],
				"windows": [{"id": "tormenta.loop", "window_s": [22.94, 27.58]}],
				"fallback_citations": [{
					"document": "docs/TELEMETRY.md", "section_id": "1.2-tormenta-per-element-cross-recording",
					"line_anchor": "lines 347-423", "columns_used": ["Element", "t (6383)"],
					"source_windows_used": [[22.94, 27.58]],
				}],
			},
			"youtube.falcon.sdXGD9kMR7s": {
				"initial_state": "observation_only", "state": "observation_only",
				"permitted_contributions": ["order", "geometry", "timing landmarks", "feel prompts"],
				"permitted_axes": [],
				"promotion_prerequisites": ["Requires reviewed source-local landmarks and complete alignment."],
				"url": "https://www.youtube.com/watch?v=sdXGD9kMR7s", "video_id": "sdXGD9kMR7s",
				"retrieved_on": "2026-08-10", "retrieval_context": "captured YouTube oEmbed response",
				"metadata_artifact_path": "docs/evidence/fidelity/youtube/sdXGD9kMR7s-oembed.json",
				"metadata_artifact_sha256": "badb63ae7143267d526a4d6d32dbdc85f280506cf2a8663280df760f87b12361",
				"review_path": "docs/evidence/fidelity/youtube/sdXGD9kMR7s-review.json",
				"review_sha256": "9dd4b8ed8f5d4bfd8b67f2218c65ed681fcb912fe55a5599e34770919d6192df",
				"row_seat": "front-row camera; exact seat unverified", "device": "camera; exact device unverified", "sample_rate_hz": null,
				"axis_mapping": {}, "reliability": "visual observation only", "processing": ["metadata capture only"],
				"caveats": ["native sample rate is unknown", "no force-axis mapping", "no reviewed source-second landmarks"],
				"windows": [],
			},
		},
		"transforms": {
			"fictional.gz-positive@1": {"kind": "scale", "axis": "normal_g", "polarity": "positive", "factor": 1.3333333333, "formula": "target_force_g = observed_force_g * 1.3333333333", "approval": "explicit user decision 2026-08-09"},
		},
		"observations": [], "targets": [], "review_prompts": [], "evidence_gaps": [],
	}


static func _valid_promotion_catalog() -> Dictionary:
	var catalog := _valid_catalog_v2()
	catalog.sources = {
		"test.primary": _synthetic_raw_source("primary", "a".repeat(64)),
		"test.secondary": _synthetic_raw_source("secondary", "b".repeat(64)),
	}
	catalog.observations = [
		_force_observation("tormenta.loop.primary", "test.primary", "executable", ["tormenta.loop.secondary"]),
		_force_observation("tormenta.loop.secondary", "test.secondary", "corroborative", []),
	]
	catalog.targets = [{
		"id": "loads.loop.positive", "observation_id": "tormenta.loop.primary",
		"semantic_selector_id": "semantic.act1.loop.core", "dimension": "loads",
		"metric": "normal_held_positive", "hold_seconds": 1.0,
		"raw_range": [2.0, 3.0], "target_range": [2.6666666666, 3.9999999999], "issues": [3],
		"aggregation": {"row": "median", "beat": "median", "seed": "median"},
	}]
	return catalog


static func _synthetic_raw_source(label: String, digest: String) -> Dictionary:
	return {
		"initial_state": "corroborative", "state": "corroborative",
		"permitted_contributions": ["synthetic force-window validation"],
		"permitted_axes": ["normal_g"], "promotion_prerequisites": ["independent compatible corroboration"],
		"acquisition": "raw", "url": "https://example.invalid/%s" % label, "recording_id": label,
		"retrieved_on": "2026-08-10", "retrieval_context": "synthetic validator fixture",
		"artifact_path": "docs/evidence/fidelity/test/%s-raw.json" % label, "artifact_sha256": digest,
		"metadata_artifact_path": "docs/evidence/fidelity/test/%s-metadata.json" % label, "metadata_artifact_sha256": digest,
		"review_path": "docs/evidence/fidelity/test/%s-review.json" % label, "review_sha256": digest,
		"row_seat": "row 2", "device": "calibrated fixture", "sample_rate_hz": 100.0,
		"axis_mapping": {"vertical": "normal_g"}, "reliability": "synthetic validator fixture",
		"processing": ["none"], "caveats": [], "windows": [{"id": "tormenta.loop", "window_s": [10.0, 12.0]}],
	}


static func _force_observation(
	observation_id: String, source_id: String, state: String, corroborating_ids: Array
) -> Dictionary:
	return {
		"id": observation_id, "state": state, "source_id": source_id,
		"source_window_id": "tormenta.loop", "source_axis": "vertical", "mapped_axis": "normal_g",
		"row_seat": "row 2", "duration_s": 2.0, "metric": "normal_held_positive", "hold_seconds": 1.0,
		"raw_range": [2.0, 3.0], "transform_id": "fictional.gz-positive@1",
		"confidence": "medium", "confidence_rationale": "synthetic exact trace window",
		"corroborating_observation_ids": corroborating_ids,
		"semantic_selector_id": "semantic.act1.loop.core",
		"alignment": {"source_landmark_id": "tormenta.loop", "generated_anchor": {"semantic_selector_id": "semantic.act1.loop.core"}, "method": "element-order-plus-force-shape", "uncertainty_s": 0.2, "row_compatibility": "same-row", "generated_row_selector": {"row_id": "row-02"}, "rationale": "matched entry and exit shoulders"},
	}


static func _valid_catalog() -> Dictionary:
	return {
		"schema_version": 1,
		"catalog_version": "test",
		"sources": {
			"source": {
				"document": "docs/TELEMETRY.md",
				"section": "test",
				"confidence": "high",
				"caveats": [],
			},
		},
		"targets": [
			{
				"id": "loads.hill.negative",
				"source_ids": ["source"],
				"confidence": "high",
				"caveats": [],
				"selector": {"kind": "hill"},
				"dimension": "loads",
				"metric": "normal_held_negative",
				"hold_seconds": 0.8,
				"recording_row": "unknown",
				"raw_range": [-1.0, -0.5],
				"transform": {"kind": "scale", "factor": 1.5},
				"target_range": [-1.5, -0.75],
				"issues": [13],
			},
		],
		"review_prompts": [],
		"evidence_gaps": [],
	}


static func _expect(errors: PackedStringArray, condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


static func _expect_close(errors: PackedStringArray, actual: float, expected: float, message: String) -> void:
	if not is_equal_approx(actual, expected):
		errors.append("%s: got %s, expected %s" % [message, actual, expected])


static func _array_peak(values: PackedFloat32Array) -> float:
	var peak := -INF
	for value in values:
		peak = maxf(peak, value)
	return peak


static func _max_abs(values: PackedFloat32Array) -> float:
	var peak := 0.0
	for value in values:
		peak = maxf(peak, absf(value))
	return peak


static func _max_abs_vector(values: PackedVector3Array) -> float:
	var peak := 0.0
	for value in values:
		peak = maxf(peak, value.length())
	return peak


static func _median_packed(values: PackedFloat32Array) -> float:
	var copy := []
	for value in values:
		copy.append(value)
	copy.sort()
	return float(copy[copy.size() / 2])


static func _median_vector_length(values: PackedVector3Array) -> float:
	var lengths := []
	for value in values:
		lengths.append(value.length())
	lengths.sort()
	return float(lengths[lengths.size() / 2])


static func _median_finite(values: Array) -> float:
	var finite := []
	for value in values:
		if value != null and is_finite(float(value)):
			finite.append(float(value))
	finite.sort()
	return float(finite[finite.size() / 2])

static func _any_true(values: Array) -> bool:
	for value in values:
		if value:
			return true
	return false


static func _count_dictionary_key(value: Variant, key: String) -> int:
	var count := 0
	if value is Dictionary:
		if value.has(key):
			count += 1
		for child in value.values():
			count += _count_dictionary_key(child, key)
	elif value is Array:
		for child in value:
			count += _count_dictionary_key(child, key)
	return count


static func _expect_close_tol(
	errors: PackedStringArray, actual: float, expected: float, tolerance: float, message: String
) -> void:
	if not is_finite(actual) or absf(actual - expected) > tolerance:
		errors.append("%s: got %s, expected %s +/- %s" % [message, actual, expected, tolerance])


static func _expect_contains(errors: PackedStringArray, values: PackedStringArray, needle: String, message: String) -> void:
	for value in values:
		if value.contains(needle):
			return
	errors.append("%s: %s" % [message, str(values)])
