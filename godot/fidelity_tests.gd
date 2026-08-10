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
	_test_legacy_input_boundary(errors)
	_test_held_values(fidelity, errors)
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


static func _test_held_values(fidelity: Script, errors: PackedStringArray) -> void:
	var positive := PackedFloat32Array([1.0, 2.0, 2.0, 2.0, 1.0])
	var negative := PackedFloat32Array([0.0, -1.0, -1.0, -1.0, 0.0])
	_expect_close(errors, fidelity.held(positive, 1.0, 0.02), 2.0, "three samples hold +2 g")
	_expect_close(errors, fidelity.held(negative, -1.0, 0.02), -1.0, "three samples hold -1 g")
	_expect(errors, is_inf(fidelity.held(positive, 1.0, 0.05)), "a hold longer than the series returns infinity")


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
