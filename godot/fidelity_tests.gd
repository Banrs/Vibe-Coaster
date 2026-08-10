extends SceneTree

const FIDELITY_PATH := "res://fidelity.gd"
const REFERENCES_PATH := "res://fidelity_references.gd"
const GENERATOR_PATH := "res://generator.gd"
const LEGACY_BASE_COMMIT := "3fa14885bef2daf3a7d9c0e544424cb6a296fd99"


func _initialize() -> void:
	var errors := run()
	for error in errors:
		printerr(error)
	quit(0 if errors.is_empty() else 1)


static func run() -> PackedStringArray:
	var errors := PackedStringArray()
	if not ResourceLoader.exists(FIDELITY_PATH):
		errors.append("RideFidelity is missing")
		return errors
	var fidelity: Script = load(FIDELITY_PATH)
	_test_tolerance_oracle(errors)
	_test_legacy_input_boundary(errors)
	_test_held_values(fidelity, errors)
	_test_exact_duration_hold(fidelity, errors)
	_test_time_weighted_pacing(fidelity, errors)
	_test_non_grid_measurement(fidelity, errors)
	_test_row_windows(fidelity, errors)
	_test_transition_windows(fidelity, errors)
	_test_straight_reconstruction(fidelity, errors)
	_test_constant_radius_reconstruction(fidelity, errors)
	_test_unclamped_radius_reconstruction(fidelity, errors)
	_test_force_integrity_mismatch(fidelity, errors)
	_test_nonuniform_quadratic_acceleration(fidelity, errors)
	_test_reconstruction_seam_channels(fidelity, errors)
	_test_route_reconstruction_embedding(fidelity, errors)
	_test_composite_grouping(fidelity, errors)
	_test_legacy_characterization(fidelity, errors)
	_test_catalog_validation(fidelity, errors)
	_test_catalog_v2_validation(fidelity, errors)
	_test_executable_promotion(fidelity, errors)
	_test_route_measurements(fidelity, errors)
	_test_reference_catalog(fidelity, errors)
	return errors


static func _test_legacy_input_boundary(errors: PackedStringArray) -> void:
	if not ResourceLoader.exists(GENERATOR_PATH):
		errors.append("RideGenerator is missing")
		return
	var generator: Script = load(GENERATOR_PATH)
	var route: Variant = generator.build(42)
	_expect(errors, route is Dictionary, "legacy generator build returns a Dictionary")
	if not route is Dictionary:
		return
	_expect(errors, LEGACY_BASE_COMMIT == "3fa14885bef2daf3a7d9c0e544424cb6a296fd99", "legacy report contract pins the pre-foundation commit")
	for key in ["positions", "tangents", "ups", "rights", "curvatures"]:
		_expect(errors, route.get(key) is PackedVector3Array, "legacy generator keeps packed vector channel %s" % key)
	for key in [
		"banks", "speeds", "normal_g", "lateral_g", "longitudinal_g", "roll_rates",
		"distances", "times",
	]:
		_expect(errors, route.get(key) is PackedFloat32Array, "legacy generator keeps packed float channel %s" % key)
	for key in ["section_indices", "lsm_ids"]:
		_expect(errors, route.get(key) is PackedInt32Array, "legacy generator keeps packed integer channel %s" % key)
	_expect(errors, route.get("sections") is Array, "legacy generator keeps sections")
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
	var before := route.duplicate(true)
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
	var selected_band := {}
	for band in fidelity.element_bands(route):
		if band.beat_id.ends_with("/selected"):
			selected_band = band
	if selected_band.is_empty():
		errors.append("non-grid element bands retain the selected beat")
	else:
		var arbitrary_hold: float = fidelity.held(selected_band.normal, 1.0, 0.804)
		_expect(errors, is_finite(arbitrary_hold) and arbitrary_hold < 2.0, "production's anchored force grid supports an arbitrary 0.804-second hold")
	var irregular_route := _moving_window_route(true)
	var irregular_before := irregular_route.duplicate(true)
	var irregular: Dictionary = fidelity.measure_route(irregular_route, [0.0])
	_expect(errors, irregular_route == irregular_before, "irregular-knot production measurement is read-only")
	if irregular.get("beats", []).size() >= 2:
		var irregular_held: Dictionary = irregular.beats[1].rows[0].loads.get("normal_held_positive", {})
		_expect_close(errors, float(irregular_held.get("0.80", -INF)), float(held_values.get("0.80", -INF)), "a collinear native knot outside the selected window leaves the held result unchanged")


static func _test_row_windows(fidelity: Script, errors: PackedStringArray) -> void:
	var bands: Array = fidelity.element_bands(_measurement_route(false), 2.0)
	_expect_close(errors, bands[0].window_start_distance, 2.0, "rear row begins at the shifted first-element start")
	_expect_close(errors, bands[0].window_end_distance, 12.0, "rear row ends at the shifted first-element end")
	_expect(errors, bands[-1].window_end_distance <= 40.0, "terminal row window clips instead of wrapping closure data")
	var attributed := 0
	for band in fidelity.element_bands(_row_pulse_route(), 2.0):
		if _array_peak(band.normal) > 1.5:
			attributed += 1
	_expect(errors, attributed == 1, "rear-row force pulse is attributed once across shifted element windows")


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
	if not _require_reconstruction(fidelity, errors):
		return
	var route := _analytic_straight_route(20.0, 2.0, 100.0)
	var before := route.duplicate(true)
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
	if not _require_reconstruction(fidelity, errors):
		return
	var route := _analytic_circle_route(25.0, 50.0, 4.0, 100.0)
	route.curvatures.fill(Vector3.ZERO)
	var channels: Dictionary = fidelity.reconstruct_channels(route)
	_expect_close_tol(errors, _median_finite(channels.radius_m), 50.0, 0.75, "circle reconstructs geometric radius")
	_expect_close_tol(errors, _median_packed(channels.curvature), 0.02, 0.0003, "circle reconstructs curvature")
	_expect_close(errors, _max_abs_vector(channels.authored_curvature_vector), 0.0, "reconstruction preserves deliberately incorrect authored curvature")
	_expect_close_tol(errors, _median_vector_length(channels.geometric_authored_curvature_error_vector), 0.02, 0.0003, "geometric/authored curvature error exposes the mismatch")


static func _test_unclamped_radius_reconstruction(fidelity: Script, errors: PackedStringArray) -> void:
	if not _require_reconstruction(fidelity, errors):
		return
	var channels: Dictionary = fidelity.reconstruct_channels(
		_analytic_circle_route(100.0, 20000.0, 10.0, 20.0)
	)
	_expect_close_tol(errors, _median_finite(channels.radius_m), 20000.0, 2500.0, "large geometric radius is not clamped to 10 km")
	_expect(errors, not _any_true(channels.radius_unbounded), "large finite geometry is not labelled unbounded")


static func _test_force_integrity_mismatch(fidelity: Script, errors: PackedStringArray) -> void:
	if not _require_reconstruction(fidelity, errors):
		return
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
	if not _require_reconstruction(fidelity, errors):
		return
	var channels: Dictionary = fidelity.reconstruct_channels(_nonuniform_quadratic_route())
	for acceleration in channels.inertial_acceleration_mps2:
		_expect(errors, acceleration.distance_to(Vector3(2.0, 0.0, 0.0)) < 0.001, "nonuniform quadratic positions reconstruct constant 2 m/s^2 acceleration")
	_expect(errors, _max_abs_vector(channels.jerk_mps3) < 0.001, "constant nonuniform acceleration has zero jerk")


static func _test_reconstruction_seam_channels(fidelity: Script, errors: PackedStringArray) -> void:
	if not _require_reconstruction(fidelity, errors):
		return
	var route := _curvature_direction_seam_route()
	var seam: int = route.sections[1].start_index
	var channels: Dictionary = fidelity.reconstruct_channels(route)
	for key in ["curvature_vector", "curvature_vector_ds", "curvature_vector_d2s", "curvature", "curvature_ds", "curvature_d2s", "authored_curvature_vector", "authored_curvature_vector_ds", "authored_curvature_vector_d2s", "authored_curvature_ds", "roll_acceleration_dps2", "seam_indices", "seam_markers", "jerk_mps3"]:
		_expect(errors, channels.has(key), "reconstruction emits raw %s" % key)
	_expect_close_tol(errors, channels.curvature[seam - 2], channels.curvature[seam + 2], 0.001, "equal curvature magnitudes survive a direction-changing seam")
	_expect(errors, channels.authored_curvature_vector_ds[seam].length() > 0.05, "unsmoothed raw curvature-vector derivative exposes the seam direction change")
	_expect(errors, _max_abs(channels.authored_curvature_ds) < 0.0001, "equal raw curvature magnitude has near-zero scalar derivative")
	_expect_close_tol(errors, _median_packed(channels.roll_acceleration_dps2), 50.0, 0.01, "roll acceleration differentiates degrees per second on physical time")
	_expect(errors, channels.seam_indices.has(seam), "reconstruction preserves declared seam indices")
	_expect(errors, channels.seam_markers.size() == 1 and channels.seam_markers[0].sample_index == seam, "seam marker identifies the raw section boundary exactly once")
	_expect(errors, not channels.has("comparison_channels"), "raw seam reconstruction never filters geometry")


static func _test_route_reconstruction_embedding(fidelity: Script, errors: PackedStringArray) -> void:
	if not _require_reconstruction(fidelity, errors):
		return
	var measured: Dictionary = fidelity.measure_route(_measurement_route(), [0.0])
	_expect(errors, measured.has("reconstruction"), "route measurement includes reconstruction at route scope")
	_expect(errors, _count_dictionary_key(measured, "reconstruction") == 1, "route measurement includes exactly one reconstruction payload")


static func _require_reconstruction(fidelity: Script, errors: PackedStringArray) -> bool:
	if _script_has_method(fidelity, "reconstruct_channels"):
		return true
	errors.append("RideFidelity.reconstruct_channels is missing")
	return false


static func _test_composite_grouping(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _grouping_route()
	var bands: Array = fidelity.element_bands(route)
	_expect(errors, bands.size() == 3, "two sections sharing one element form one beat")
	if bands.size() != 3:
		return
	_expect(errors, bands[0].kind == "hill", "the composite beat keeps its element kind")
	_expect(errors, bands[0].beat_id == "act-one/00/hill", "the composite beat gets a stable ID")
	_expect(errors, bands[0].first == 0 and bands[0].last == 18, "the composite beat spans both sections")
	_expect(errors, bands[1].kind == "Transfer", "a grade section is a distinct named beat")
	_expect(errors, bands[2].beat_id == "act-one/02/turn", "later beats advance the phase ordinal")


static func _test_legacy_characterization(fidelity: Script, errors: PackedStringArray) -> void:
	var route := _legacy_characterization_route()
	var before := route.duplicate(true)
	var bands: Array = fidelity.element_bands(route, 2.0)
	if bands.is_empty():
		errors.append("legacy characterization produces element bands")
		return
	_expect(errors, bands[0].beat_id == "act-one/00/hill", "legacy adapter keeps its stable beat ID")
	_expect_close(errors, bands[0].window_start_distance, 2.0, "rear row enters after its offset")
	fidelity.measure_route(route, [0.0, 2.0])
	_expect(errors, route == before, "fidelity measurement is read-only")


static func _test_catalog_validation(fidelity: Script, errors: PackedStringArray) -> void:
	var catalog := _valid_catalog()
	_expect_contains(errors, fidelity.validate_catalog(catalog), "schema version 2", "schema-v1 catalogs are rejected")


static func _test_catalog_v2_validation(fidelity: Script, errors: PackedStringArray) -> void:
	var catalog := _valid_catalog_v2()
	_expect(errors, fidelity.validate_catalog(catalog).is_empty(), "complete schema-v2 catalog validates")
	var bad_state := catalog.duplicate(true)
	bad_state.sources["rideforcesdb.tormenta.6383"].state = "trusted"
	_expect_contains(errors, fidelity.validate_catalog(bad_state), "invalid state", "unknown evidence state is rejected")
	var bad_ceiling := catalog.duplicate(true)
	bad_ceiling.sources["rideforcesdb.tormenta.6383"].initial_state = "observation_only"
	_expect_contains(errors, fidelity.validate_catalog(bad_ceiling), "permission ceiling", "source state cannot exceed its initial permission ceiling")
	var bad_permissions := catalog.duplicate(true)
	bad_permissions.sources["rideforcesdb.tormenta.6383"].permitted_axes.append("pitch_deg")
	_expect_contains(errors, fidelity.validate_catalog(bad_permissions), "permitted_axes", "non-force permitted axes are rejected")
	var malformed_source := catalog.duplicate(true)
	malformed_source.sources["rideforcesdb.tormenta.6383"].caveats = null
	malformed_source.sources["rideforcesdb.tormenta.6383"].permitted_axes = "normal_g"
	_expect_contains(errors, fidelity.validate_catalog(malformed_source), "caveats", "malformed source arrays return diagnostics")
	_expect_contains(errors, fidelity.validate_catalog(malformed_source), "permitted_axes", "malformed permitted axes return diagnostics")
	var bad_union := catalog.duplicate(true)
	bad_union.sources["rideforcesdb.tormenta.6383"].artifact_path = "docs/evidence/fidelity/rideforcesdb/6383-raw.json"
	bad_union.sources["rideforcesdb.tormenta.6383"].artifact_sha256 = "d".repeat(64)
	_expect_contains(errors, fidelity.validate_catalog(bad_union), "acquisition", "acquisition branches cannot be mixed")
	var missing_fallback := catalog.duplicate(true)
	missing_fallback.sources["rideforcesdb.tormenta.6383"].erase("fallback_citations")
	_expect_contains(errors, fidelity.validate_catalog(missing_fallback), "fallback_citations", "unavailable raw acquisition keeps structured fallback citations")
	var bad_path := catalog.duplicate(true)
	bad_path.sources["rideforcesdb.tormenta.6383"].diagnostic_path = "../6383-diagnostic.json"
	_expect_contains(errors, fidelity.validate_catalog(bad_path), "diagnostic_path", "artifact paths cannot traverse parents")
	var bad_hash := catalog.duplicate(true)
	bad_hash.sources["rideforcesdb.tormenta.6383"].diagnostic_sha256 = "abc"
	_expect_contains(errors, fidelity.validate_catalog(bad_hash), "diagnostic_sha256", "non-SHA-256 digest is rejected")
	var bad_metadata_union := catalog.duplicate(true)
	bad_metadata_union.sources["youtube.falcon.sdXGD9kMR7s"].metadata_diagnostic_path = "docs/evidence/fidelity/youtube/sdXGD9kMR7s-oembed.json"
	bad_metadata_union.sources["youtube.falcon.sdXGD9kMR7s"].metadata_diagnostic_sha256 = "d".repeat(64)
	_expect_contains(errors, fidelity.validate_catalog(bad_metadata_union), "metadata", "metadata provenance branches cannot be mixed")
	var bad_anchor := catalog.duplicate(true)
	bad_anchor.selectors["semantic.act1.loop.core"].erase("compiled_anchor")
	_expect_contains(errors, fidelity.validate_catalog(bad_anchor), "compiled_anchor", "selectors require compiled anchors")
	var bad_role := catalog.duplicate(true)
	bad_role.selectors["semantic.act1.loop.core"].legacy_anchor.window_role = "core"
	_expect_contains(errors, fidelity.validate_catalog(bad_role), "window_role", "legacy anchors only permit whole")
	var bad_transform := catalog.duplicate(true)
	bad_transform.transforms["fictional.gz-positive@1"].axis = "longitudinal_g"
	_expect_contains(errors, fidelity.validate_catalog(bad_transform), "Gx+", "unsupported positive longitudinal transform is rejected")
	var bad_formula := catalog.duplicate(true)
	bad_formula.transforms["fictional.gz-positive@1"].formula = "target_force_g = observed_force_g"
	_expect_contains(errors, fidelity.validate_catalog(bad_formula), "formula", "approved transform formula is immutable")
	var bad_approval := catalog.duplicate(true)
	bad_approval.transforms["fictional.gz-positive@1"].approval = "rejected"
	_expect_contains(errors, fidelity.validate_catalog(bad_approval), "approval provenance", "approved transform provenance is immutable")
	var bad_date := catalog.duplicate(true)
	bad_date.sources["rideforcesdb.tormenta.6383"].retrieved_on = "2026-99-99"
	_expect_contains(errors, fidelity.validate_catalog(bad_date), "retrieved_on", "impossible retrieval dates are rejected")
	var duplicate := catalog.duplicate(true)
	duplicate.review_prompts = [
		{"id": "review.same", "category": "feel", "prompt": "First", "source_ids": [], "issues": [1]},
		{"id": "review.same", "category": "feel", "prompt": "Second", "source_ids": [], "issues": [2]},
	]
	_expect_contains(errors, fidelity.validate_catalog(duplicate), "duplicate id", "record IDs are unique across collections")
	if not _script_has_method(fidelity, "validate_catalog_artifacts"):
		errors.append("RideFidelity.validate_catalog_artifacts is missing")
	else:
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
	var no_corroboration := catalog.duplicate(true)
	no_corroboration.observations[0].corroborating_observation_ids = []
	_expect_contains(errors, fidelity.validate_catalog(no_corroboration), "requires corroboration", "corroborative source cannot promote alone")
	var self_corroboration := catalog.duplicate(true)
	self_corroboration.observations[0].corroborating_observation_ids = ["tormenta.loop.primary"]
	_expect_contains(errors, fidelity.validate_catalog(self_corroboration), "independent", "an observation cannot corroborate itself")
	var dangling_corroboration := catalog.duplicate(true)
	dangling_corroboration.observations[1].corroborating_observation_ids = ["missing"]
	_expect_contains(errors, fidelity.validate_catalog(dangling_corroboration), "non-executable", "corroborative observations cannot carry unchecked links")
	var bad_window := catalog.duplicate(true)
	bad_window.observations[0].source_window_id = "invented.window"
	_expect_contains(errors, fidelity.validate_catalog(bad_window), "source_window_id", "observations resolve declared source-local windows")
	var malformed_range := catalog.duplicate(true)
	malformed_range.observations[0].raw_range = [{}, {}]
	_expect_contains(errors, fidelity.validate_catalog(malformed_range), "invalid raw_range", "malformed ranges return diagnostics instead of raising")
	var bad_alignment := catalog.duplicate(true)
	bad_alignment.observations[0].alignment.source_landmark_id = "invented.landmark"
	_expect_contains(errors, fidelity.validate_catalog(bad_alignment), "source_landmark_id", "alignment resolves the selected source window")
	var bad_ceiling := catalog.duplicate(true)
	bad_ceiling.sources["test.primary"].initial_state = "observation_only"
	bad_ceiling.sources["test.primary"].state = "observation_only"
	_expect_contains(errors, fidelity.validate_catalog(bad_ceiling), "permission ceiling", "observation-only sources cannot promote force evidence")
	var wrong_selector := catalog.duplicate(true)
	wrong_selector.targets[0].semantic_selector_id = "missing"
	_expect_contains(errors, fidelity.validate_catalog(wrong_selector), "must match observation", "target selector is derived from its observation")
	var invented_raw := catalog.duplicate(true)
	invented_raw.targets[0].raw_range = [2.1, 3.0]
	_expect_contains(errors, fidelity.validate_catalog(invented_raw), "raw_range", "target raw range is derived from its observation")
	var invented_target := catalog.duplicate(true)
	invented_target.targets[0].target_range = [999.0, 1000.0]
	_expect_contains(errors, fidelity.validate_catalog(invented_target), "target_range", "target range is derived by the approved transform")
	var missing_observation := catalog.duplicate(true)
	missing_observation.targets[0].observation_id = "missing"
	_expect_contains(errors, fidelity.validate_catalog(missing_observation), "unknown observation", "targets require an executable observation")


static func _test_route_measurements(fidelity: Script, errors: PackedStringArray) -> void:
	if not _script_has_method(fidelity, "measure_route"):
		errors.append("RideFidelity.measure_route is missing")
		return
	var measured: Dictionary = fidelity.measure_route(_measurement_route(), [0.0, 2.0])
	_expect(errors, measured.get("beats", []).size() == 3, "measurement retains composite, grade, and closure beats")
	if measured.get("beats", []).is_empty():
		return
	var beat: Dictionary = measured.beats[0]
	_expect(errors, beat.rows.size() == 2, "every requested train row is measured")
	if beat.rows.size() == 2:
		_expect_close(errors, beat.rows[1].window_start_distance, 2.0, "rear-row window starts when that row reaches the beat")
		_expect_close(errors, beat.rows[1].window_end_distance, 22.0, "rear-row window ends when that row leaves the beat")
		_expect_close(errors, beat.rows[1].loads.normal_peak_positive, 1.0, "constant synthetic normal load remains one g")
		_expect_close(errors, beat.rows[1].loads.lateral_peak_absolute, 0.0, "constant synthetic lateral load remains zero")
	_expect_close(errors, beat.geometry.length, 20.0, "beat geometry reports track length")
	_expect_close(errors, beat.geometry.height, 10.0, "beat geometry reports vertical scale")
	_expect_close(errors, beat.geometry.width, 20.0, "beat geometry reports plan displacement")
	_expect_close(errors, beat.pacing.duration, 2.0, "beat pacing reports elapsed duration")
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
	if _script_has_method(fidelity, "validate_catalog_artifacts"):
		for error in fidelity.validate_catalog_artifacts(catalog):
			errors.append("reference catalog artifact: %s" % error)
	_test_manifest_parity(catalog, errors)
	var covered := {}
	for collection in [catalog.get("targets", []), catalog.get("review_prompts", []), catalog.get("evidence_gaps", [])]:
		for record in collection:
			for issue in record.get("issues", []):
				covered[int(issue)] = true
	for issue in range(1, 17):
		_expect(errors, covered.has(issue), "reference catalog covers issue %d" % issue)


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


static func _grouping_route() -> Dictionary:
	var shared := {"kind": "hill", "rise": 12.0}
	var other := {"kind": "turn", "heading_change_deg": 30.0}
	var count := 31
	var times := PackedFloat32Array()
	var distances := PackedFloat32Array()
	var normal := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	var longitudinal := PackedFloat32Array()
	for i in count:
		times.append(i * 0.01)
		distances.append(float(i))
		normal.append(1.0)
		lateral.append(0.0)
		longitudinal.append(0.0)
	return {
		"times": times,
		"distances": distances,
		"normal_g": normal,
		"lateral_g": lateral,
		"longitudinal_g": longitudinal,
		"sections": [
			{"kind": "FVD", "name": "hill-a", "element": shared, "phase": "act one", "start_index": 0, "end_index": 9},
			{"kind": "FVD", "name": "hill-b", "element": shared, "phase": "act one", "start_index": 9, "end_index": 18},
			{"kind": "GRADE", "name": "Transfer", "element": {}, "phase": "act one", "start_index": 18, "end_index": 24},
			{"kind": "FVD", "name": "turn", "element": other, "phase": "act one", "start_index": 24, "end_index": 30},
		],
	}


static func _measurement_route(shared_element_identity: bool = true) -> Dictionary:
	var shared := {"kind": "hill", "rise": 10.0}
	var second_element: Dictionary = shared if shared_element_identity else shared.duplicate(true)
	var positions := PackedVector3Array()
	var tangents := PackedVector3Array()
	var ups := PackedVector3Array()
	var rights := PackedVector3Array()
	var curvatures := PackedVector3Array()
	var banks := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var normal := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	var longitudinal := PackedFloat32Array()
	var roll_rates := PackedFloat32Array()
	var distances := PackedFloat32Array()
	var times := PackedFloat32Array()
	for i in 41:
		var height := float(mini(i, 20 - i)) if i <= 20 else 0.0
		positions.append(Vector3(i, height, 0.0))
		tangents.append(Vector3.RIGHT)
		ups.append(Vector3.UP)
		rights.append(Vector3.FORWARD)
		curvatures.append(Vector3.ZERO)
		banks.append(0.0)
		speeds.append(10.0)
		normal.append(1.0)
		lateral.append(0.0)
		longitudinal.append(0.0)
		roll_rates.append(0.0)
		distances.append(float(i))
		times.append(i * 0.1)
	return {
		"seed": 7,
		"length": 40.0,
		"duration": 4.0,
		"positions": positions,
		"tangents": tangents,
		"ups": ups,
		"rights": rights,
		"curvatures": curvatures,
		"banks": banks,
		"speeds": speeds,
		"normal_g": normal,
		"lateral_g": lateral,
		"longitudinal_g": longitudinal,
		"roll_rates": roll_rates,
		"distances": distances,
		"times": times,
		"sections": [
			{"kind": "FVD", "name": "hill-a", "element": shared, "phase": "act one", "start_index": 0, "end_index": 10},
			{"kind": "FVD", "name": "hill-b", "element": second_element, "phase": "act one", "start_index": 10, "end_index": 20},
			{"kind": "GRADE", "name": "Transfer", "element": {}, "phase": "act one", "start_index": 20, "end_index": 30},
			{"kind": "CLOSURE", "name": "Closure", "element": {}, "phase": "run home", "start_index": 30, "end_index": 40},
		],
	}


static func _irregular_pacing_route() -> Dictionary:
	var positions := PackedVector3Array()
	var tangents := PackedVector3Array()
	var ups := PackedVector3Array()
	var rights := PackedVector3Array()
	var curvatures := PackedVector3Array()
	var banks := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	var speeds := PackedFloat32Array([10.0, 60.0, 60.0, 60.0, 10.0])
	var normal := PackedFloat32Array([1.0, 2.0, 2.0, 2.0, 1.0])
	var lateral := PackedFloat32Array([0.0, 0.5, 0.5, 0.5, 0.0])
	var longitudinal := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	var roll_rates := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
	var distances := PackedFloat32Array([0.0, 2.0, 5.0, 11.0, 13.0])
	var times := PackedFloat32Array([0.0, 0.2, 0.5, 1.1, 1.3])
	for index in times.size():
		positions.append(Vector3(distances[index], 5.0, 0.0))
		tangents.append(Vector3.RIGHT)
		ups.append(Vector3.UP)
		rights.append(Vector3.FORWARD)
		curvatures.append(Vector3.ZERO)
	return {
		"seed": 8, "length": 13.0, "duration": 1.3,
		"positions": positions, "tangents": tangents, "ups": ups, "rights": rights,
		"curvatures": curvatures, "banks": banks, "speeds": speeds,
		"normal_g": normal, "lateral_g": lateral, "longitudinal_g": longitudinal,
		"roll_rates": roll_rates, "distances": distances, "times": times,
		"sections": [{"kind": "FVD", "name": "pacing", "element": {"kind": "pacing"}, "phase": "act one", "start_index": 0, "end_index": 4}],
	}


static func _moving_window_route(extra_preceding_knot: bool) -> Dictionary:
	var times := PackedFloat32Array([0.0, 0.003, 0.303, 0.613, 0.913, 0.914, 1.0])
	var normal := PackedFloat32Array([4.0, 1.5, 1.5, 1.5, 1.5, -3.0, -3.0])
	if extra_preceding_knot:
		times.insert(1, 0.0015)
		normal.insert(1, 2.75)
	var positions := PackedVector3Array()
	var tangents := PackedVector3Array()
	var ups := PackedVector3Array()
	var rights := PackedVector3Array()
	var curvatures := PackedVector3Array()
	var banks := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	var longitudinal := PackedFloat32Array()
	var roll_rates := PackedFloat32Array()
	var distances := PackedFloat32Array()
	for index in times.size():
		var distance := times[index] * 10.0
		positions.append(Vector3(distance, 5.0, 0.0))
		tangents.append(Vector3.RIGHT)
		ups.append(Vector3.UP)
		rights.append(Vector3.FORWARD)
		curvatures.append(Vector3.ZERO)
		banks.append(0.0)
		speeds.append(10.0)
		lateral.append(0.0)
		longitudinal.append(0.0)
		roll_rates.append(0.0)
		distances.append(distance)
	var selected_first := 2 if extra_preceding_knot else 1
	var selected_last := selected_first + 3
	return {
		"seed": 9, "length": distances[-1], "duration": times[-1],
		"positions": positions, "tangents": tangents, "ups": ups, "rights": rights,
		"curvatures": curvatures, "banks": banks, "speeds": speeds,
		"normal_g": normal, "lateral_g": lateral, "longitudinal_g": longitudinal,
		"roll_rates": roll_rates, "distances": distances, "times": times,
		"sections": [
			{"kind": "FVD", "name": "before", "element": {"kind": "before"}, "phase": "act one", "start_index": 0, "end_index": selected_first},
			{"kind": "FVD", "name": "selected", "element": {"kind": "selected"}, "phase": "act one", "start_index": selected_first, "end_index": selected_last},
			{"kind": "GRADE", "name": "after", "element": {}, "phase": "act one", "start_index": selected_last, "end_index": times.size() - 1},
		],
	}


static func _row_pulse_route() -> Dictionary:
	var route := _measurement_route(false)
	# Keep the pulse off the shared section endpoint: interpolation and the causal load filter
	# legitimately spread a seam impulse across both physical windows.
	route.curvatures[11] = Vector3(0.0, 0.5, 0.0)
	return route


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
	route.sections = [
		{"kind": "FVD", "name": "before", "element": {"kind": "before"}, "phase": "act one", "start_index": 0, "end_index": seam},
		{"kind": "FVD", "name": "after", "element": {"kind": "after"}, "phase": "act one", "start_index": seam, "end_index": route.times.size() - 1},
	]
	return route


static func _uniform_route(seconds: float) -> Dictionary:
	var positions := PackedVector3Array()
	var tangents := PackedVector3Array()
	var ups := PackedVector3Array()
	var rights := PackedVector3Array()
	var curvatures := PackedVector3Array()
	var scalar := PackedFloat32Array()
	var count := roundi(seconds * 100.0) + 1
	for index in count:
		var time := index * 0.01
		positions.append(Vector3(time * 10.0, 5.0, 0.0))
		tangents.append(Vector3.RIGHT)
		ups.append(Vector3.UP)
		rights.append(Vector3.FORWARD)
		curvatures.append(Vector3.ZERO)
		scalar.append(0.0)
	var normal := PackedFloat32Array(scalar)
	normal.fill(1.0)
	var speeds := PackedFloat32Array(scalar)
	speeds.fill(10.0)
	var distances := PackedFloat32Array(scalar)
	for index in count:
		distances[index] = index * 0.1
	return {
		"seed": 10, "length": distances[-1], "duration": seconds,
		"positions": positions, "tangents": tangents, "ups": ups, "rights": rights,
		"curvatures": curvatures, "banks": PackedFloat32Array(scalar), "speeds": speeds,
		"normal_g": normal, "lateral_g": PackedFloat32Array(scalar), "longitudinal_g": PackedFloat32Array(scalar),
		"roll_rates": PackedFloat32Array(scalar), "distances": distances, "times": _times_100hz(count), "sections": [],
	}


static func _analytic_straight_route(speed: float, seconds: float, sample_hz: float) -> Dictionary:
	var count := roundi(seconds * sample_hz) + 1
	var positions := PackedVector3Array()
	var tangents := PackedVector3Array()
	var ups := PackedVector3Array()
	var rights := PackedVector3Array()
	var curvatures := PackedVector3Array()
	var scalars := PackedFloat32Array()
	var distances := PackedFloat32Array()
	var times := PackedFloat32Array()
	for index in count:
		var time := index / sample_hz
		positions.append(Vector3(speed * time, 0.0, 0.0))
		tangents.append(Vector3.RIGHT)
		ups.append(Vector3.UP)
		rights.append(Vector3.FORWARD)
		curvatures.append(Vector3.ZERO)
		scalars.append(0.0)
		distances.append(speed * time)
		times.append(time)
	var normal := PackedFloat32Array(scalars)
	normal.fill(1.0)
	var speeds := PackedFloat32Array(scalars)
	speeds.fill(speed)
	return _analytic_route(positions, tangents, ups, rights, curvatures, normal, scalars, scalars, scalars, speeds, distances, times, [])


static func _analytic_circle_route(speed: float, radius: float, seconds: float, sample_hz: float) -> Dictionary:
	var count := roundi(seconds * sample_hz) + 1
	var positions := PackedVector3Array()
	var tangents := PackedVector3Array()
	var ups := PackedVector3Array()
	var rights := PackedVector3Array()
	var curvatures := PackedVector3Array()
	var lateral := PackedFloat32Array()
	var scalars := PackedFloat32Array()
	var distances := PackedFloat32Array()
	var times := PackedFloat32Array()
	for index in count:
		var time := index / sample_hz
		var angle := speed * time / radius
		var inward := Vector3(-cos(angle), 0.0, -sin(angle))
		positions.append(Vector3(radius * (cos(angle) - 1.0), 0.0, radius * sin(angle)))
		tangents.append(Vector3(-sin(angle), 0.0, cos(angle)))
		ups.append(Vector3.UP)
		rights.append(inward)
		curvatures.append(inward / radius)
		lateral.append(speed * speed / radius / 9.80665)
		scalars.append(0.0)
		distances.append(speed * time)
		times.append(time)
	var normal := PackedFloat32Array(scalars)
	normal.fill(1.0)
	var speeds := PackedFloat32Array(scalars)
	speeds.fill(speed)
	return _analytic_route(positions, tangents, ups, rights, curvatures, normal, lateral, scalars, scalars, speeds, distances, times, [])


static func _nonuniform_quadratic_route() -> Dictionary:
	var times := PackedFloat32Array([0.0, 0.07, 0.21, 0.5, 0.9, 1.4])
	var positions := PackedVector3Array()
	var tangents := PackedVector3Array()
	var ups := PackedVector3Array()
	var rights := PackedVector3Array()
	var curvatures := PackedVector3Array()
	var normal := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	var longitudinal := PackedFloat32Array()
	var roll_rates := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var distances := PackedFloat32Array()
	for time in times:
		var distance := 5.0 * time + time * time
		positions.append(Vector3(distance, 0.0, 0.0))
		tangents.append(Vector3.RIGHT)
		ups.append(Vector3.UP)
		rights.append(Vector3.FORWARD)
		curvatures.append(Vector3.ZERO)
		normal.append(1.0)
		lateral.append(0.0)
		longitudinal.append(2.0 / 9.80665)
		roll_rates.append(0.0)
		# Deliberately inconsistent: acceleration must come from raw position/time, not this channel.
		speeds.append(5.0)
		distances.append(distance)
	return _analytic_route(positions, tangents, ups, rights, curvatures, normal, lateral, longitudinal, roll_rates, speeds, distances, times, [])


static func _curvature_direction_seam_route() -> Dictionary:
	const SPEED := 25.0
	const RADIUS := 50.0
	const SAMPLE_HZ := 100.0
	const SEAM := 100
	var positions := PackedVector3Array()
	var tangents := PackedVector3Array()
	var ups := PackedVector3Array()
	var rights := PackedVector3Array()
	var curvatures := PackedVector3Array()
	var normal := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	var longitudinal := PackedFloat32Array()
	var roll_rates := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var distances := PackedFloat32Array()
	var times := PackedFloat32Array()
	for index in 201:
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
		longitudinal.append(0.0)
		roll_rates.append(index * 0.5)
		speeds.append(SPEED)
		distances.append(index * SPEED / SAMPLE_HZ)
		times.append(index / SAMPLE_HZ)
	return _analytic_route(positions, tangents, ups, rights, curvatures, normal, lateral, longitudinal, roll_rates, speeds, distances, times, [
		{"kind": "FVD", "name": "before", "element": {"kind": "before"}, "phase": "act one", "start_index": 0, "end_index": SEAM},
		{"kind": "FVD", "name": "after", "element": {"kind": "after"}, "phase": "act one", "start_index": SEAM, "end_index": 200},
	])


static func _analytic_route(
	positions: PackedVector3Array, tangents: PackedVector3Array, ups: PackedVector3Array,
	rights: PackedVector3Array, curvatures: PackedVector3Array, normal: PackedFloat32Array,
	lateral: PackedFloat32Array, longitudinal: PackedFloat32Array, roll_rates: PackedFloat32Array,
	speeds: PackedFloat32Array, distances: PackedFloat32Array, times: PackedFloat32Array, sections: Array
) -> Dictionary:
	var banks := PackedFloat32Array()
	banks.resize(times.size())
	banks.fill(0.0)
	return {
		"seed": 500, "length": distances[-1], "duration": times[-1],
		"positions": positions, "tangents": tangents, "ups": ups, "rights": rights,
		"curvatures": curvatures, "banks": banks, "speeds": speeds,
		"normal_g": normal, "lateral_g": lateral, "longitudinal_g": longitudinal,
		"roll_rates": roll_rates, "distances": distances, "times": times, "sections": sections,
	}


static func _times_100hz(count: int) -> PackedFloat32Array:
	var times := PackedFloat32Array()
	for index in count:
		times.append(index * 0.01)
	return times


static func _legacy_characterization_route() -> Dictionary:
	var route := _measurement_route(false)
	route["sections"][0]["element"] = route.sections[1].element
	route["sections"][0]["phase"] = "act one"
	route["sections"][1]["phase"] = "act one"
	return route


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
				"review_sha256": "7fd9f1bf4a5df352c5371264f160f3bfcc30a89acacffe99a6f3ea3c47b00531",
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
		"alignment": {"source_landmark_id": "tormenta.loop", "generated_anchor": {"semantic_selector_id": "semantic.act1.loop.core"}, "method": "element-order-plus-force-shape", "uncertainty_s": 0.2, "row_compatibility": "same-row", "rationale": "matched entry and exit shoulders"},
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


static func _script_has_method(script: Script, method_name: String) -> bool:
	for method in script.get_script_method_list():
		if method.name == method_name:
			return true
	return false
