extends SceneTree

const OVERLAY_PATH := "res://fidelity_overlay.gd"
const MANIFEST_PATH := "res://../docs/evidence/fidelity/rfdb-local-overlay-manifest.json"
const CanonicalData := preload("res://canonical_data.gd")
const Fidelity := preload("res://fidelity.gd")
const Generator := preload("res://generator.gd")
const References := preload("res://fidelity_references.gd")
const RouteContract := preload("res://route_contract.gd")
var _t := TestUtil.new()


func _initialize() -> void:
	if not ResourceLoader.exists(OVERLAY_PATH):
		_t.expect(false, "RideFidelityOverlay is missing")
	else:
		var overlay: Script = load(OVERLAY_PATH)
		_test_valid_semantic_overlay(overlay)
		_test_source_failures_keep_generated_lane(overlay)
		_test_exact_anchor_resolution(overlay)
		_test_manifest_validation(overlay)
		_test_exact_manifest_digest(overlay)
		_test_transform_authority(overlay)
		_test_committed_manifest(overlay)
		_test_optional_local_exports(overlay)
	_t.finish(self)


func _test_valid_semantic_overlay(overlay: Script) -> void:
	var path := "user://rfdb-overlay-valid.csv"
	var csv := "Time,Lateral,Vertical,Longitudinal\n0.00,1.0,2.0,-1.0\n0.02,-2.0,-1.0,1.0\n0.04,0.5,3.0,0.5\n0.06,0.0,1.0,0.0\n"
	_write(path, csv)
	var manifest := _manifest(csv)
	var result := _build(overlay, manifest, {"test-source": path}, _measurement(), _route())
	_t.expect(result.get("status") == "ok", "valid bytes produce an overlay: %s" % str(result))
	if result.get("status") != "ok": return
	_t.expect(result.get("schema_version") == "fidelity-semantic-overlays@1",
		"overlay declares its schema")
	_t.expect(result.recordings[0].validation_status == "available"
		and result.recordings[0].observed_sha256 == _sha(csv),
		"recording is accepted by content, independent of filename")
	var comparison: Dictionary = result.comparisons[0]
	_t.expect(comparison.alignment_status == "semantic_only", "alignment is semantic only")
	_t.expect(comparison.source.window_s == [0.0, 0.06]
		and comparison.source.sample_count == 3,
		"source selection is native and half-open")
	_t.expect(comparison.generated.window_s == [20.0, 21.0]
		and comparison.generated.sample_count == 2
		and comparison.generated.row_id == "row-04"
		and is_equal_approx(comparison.generated.row_offset_m, 6.45),
		"generated selection uses the recording-mapped row and measured half-open window")
	var row_two_manifest := manifest.duplicate(true)
	row_two_manifest.recordings[0].generated_row_id = "row-02"
	var row_two_comparison: Dictionary = _build(overlay, row_two_manifest, {"test-source": path},
		_measurement(), _route()).comparisons[0]
	var row_two: Dictionary = row_two_comparison.generated
	var row_two_lane: Dictionary = _lane(row_two_comparison, "generated_raw")
	_t.expect(row_two.window_s == [20.0, 21.0] and row_two.sample_count == 2
		and row_two.row_id == "row-02" and is_equal_approx(row_two.row_offset_m, 2.15),
		"a source row maps to its corresponding modeled row instead of the center row")
	var source: Dictionary = _lane(comparison, "source_observed_smoothed")
	var target: Dictionary = _lane(comparison, "approved_scaled_target")
	var generated: Dictionary = _lane(comparison, "generated_raw")
	_t.expect(_times(source.samples) == [0.0, 0.02, 0.04]
		and _times(target.samples) == [0.0, 0.02, 0.04]
		and _times(generated.samples) == [20.0, 20.5],
		"each lane retains its independent native clock")
	var route := _route()
	var row_four_series := Fidelity.native_row_series(route, 6.45)
	var row_two_series := Fidelity.native_row_series(route, 2.15)
	_t.expect(is_equal_approx(generated.samples[0].normal_g, row_four_series.normal_g[1])
		and is_equal_approx(row_two_lane.samples[0].normal_g, row_two_series.normal_g[1]),
		"generated lanes use the selected row's modeled native force samples")
	_t.expect(not is_equal_approx(generated.samples[0].normal_g, row_two_lane.samples[0].normal_g),
		"changing the selected modeled row changes generated force values")
	_t.expect(not source.samples[1].eligible and source.samples[0].eligible,
		"masked samples remain present and ineligible")
	_t.expect(is_equal_approx(target.samples[0].normal_g, 2.0 * 1.3333333333)
		and is_equal_approx(target.samples[1].normal_g, -1.5),
		"normal transforms are sign-aware")
	_t.expect(is_equal_approx(target.samples[0].lateral_g, 1.5666666667)
		and is_equal_approx(target.samples[1].lateral_g, -2.0 * 1.5666666667),
		"lateral transforms preserve sign")
	_t.expect(is_equal_approx(target.samples[0].longitudinal_g, -1.7142857143)
		and target.samples[1].longitudinal_g == null,
		"negative longitudinal is scaled while positive longitudinal is a gap")
	_t.expect(is_equal_approx(generated.samples[1].normal_g, row_four_series.normal_g[2])
		and is_equal_approx(generated.samples[0].lateral_g, row_four_series.lateral_g[1])
		and is_equal_approx(generated.samples[0].longitudinal_g,
			row_four_series.longitudinal_g[1]),
		"generated arrays consistently use the selected modeled row")
	_t.expect(is_equal_approx(source.summary.axes.normal_g.denominator_s, 0.04)
		and source.summary.axes.normal_g.metric_label == "normal_g"
		and is_equal_approx(source.summary.axes.normal_g.mean, 2.5)
		and is_equal_approx(source.summary.axes.normal_g.rms, sqrt(6.5))
		and source.summary.axes.normal_g.peak_positive_g == 3.0
		and source.summary.axes.normal_g.peak_negative_g == null
		and source.summary.axes.normal_g.longest_positive_hold_s == 0.02
		and source.summary.axes.normal_g.longest_negative_hold_s == 0.0,
		"source summary excludes the retained masked interval")
	_t.expect(is_equal_approx(generated.summary.axes.normal_g.denominator_s, 1.0)
		and is_equal_approx(generated.summary.axes.normal_g.mean,
			(row_four_series.normal_g[1] + row_four_series.normal_g[2]) * 0.5)
		and generated.summary.axes.normal_g.peak_negative_g == null
		and is_equal_approx(generated.summary.axes.normal_g.longest_positive_hold_s, 1.0)
		and is_equal_approx(generated.summary.axes.normal_g.longest_negative_hold_s, 0.0),
		"generated summary uses its own native window")
	_t.expect(is_equal_approx(target.summary.axes.normal_g.denominator_s, 0.04)
		and is_equal_approx(target.summary.axes.longitudinal_g.denominator_s, 0.02)
		and target.summary.axes.lateral_g.metric_label == "lateral_g"
		and target.summary.axes.longitudinal_g.longest_negative_hold_s == 0.02,
		"scaled target reports each axis against its own retained denominator: %s" \
			% str(target.summary))
	_t.expect(comparison.markers.size() == 3
		and comparison.markers.map(func(marker: Dictionary): return marker.id)
		== ["entry", "apex", "exit"],
		"one loop window may carry three uncertain markers without subwindows")
	var reversed: Dictionary = _reverse_dictionaries(manifest)
	var repeat := _build(overlay, reversed, {"test-source": path}, _measurement(), _route())
	_t.expect(JSON.stringify(result) == JSON.stringify(repeat),
		"dictionary insertion order cannot change the deterministic result")
	_t.expect(not JSON.stringify(result).contains(path), "local absolute paths are never serialized")
	for comparison_key in comparison.keys():
		_t.expect(str(comparison_key) not in ["aligned_time", "normalized_time", "common_time"],
			"no common clock field is emitted")


func _test_source_failures_keep_generated_lane(overlay: Script) -> void:
	var valid_csv := "Time,Lateral,Vertical,Longitudinal\n0.00,0,1,-1\n0.02,0,1,-1\n0.04,0,1,-1\n0.06,0,1,-1\n"
	var cases := {
		"missing": null,
		"wrong-digest": "Time,Lateral,Vertical,Longitudinal\n0.00,0,9,-1\n0.02,0,1,-1\n0.04,0,1,-1\n0.06,0,1,-1\n",
		"header": "Time,Lateral,Normal,Longitudinal\n0.00,0,1,-1\n0.02,0,1,-1\n0.04,0,1,-1\n0.06,0,1,-1\n",
		"count": "Time,Lateral,Vertical,Longitudinal\n0.00,0,1,-1\n0.02,0,1,-1\n",
		"cadence": "Time,Lateral,Vertical,Longitudinal\n0.00,0,1,-1\n0.03,0,1,-1\n0.04,0,1,-1\n0.06,0,1,-1\n",
		"nonfinite": "Time,Lateral,Vertical,Longitudinal\n0.00,0,1,-1\n0.02,0,nan,-1\n0.04,0,1,-1\n0.06,0,1,-1\n",
		"decreasing": "Time,Lateral,Vertical,Longitudinal\n0.00,0,1,-1\n0.02,0,1,-1\n0.01,0,1,-1\n0.06,0,1,-1\n",
	}
	for case_id in cases:
		var path := ""
		var manifest := _manifest(valid_csv)
		if cases[case_id] != null:
			path = "user://rfdb-overlay-%s.csv" % case_id
			_write(path, str(cases[case_id]))
			if case_id != "wrong-digest":
				manifest.recordings[0].expected_sha256 = _sha(str(cases[case_id]))
				manifest.recordings[0].expected_byte_size = str(cases[case_id]).to_utf8_buffer().size()
		var result := _build(overlay, manifest,
			{} if path.is_empty() else {"test-source": path}, _measurement(), _route())
		_t.expect(result.get("status") == "ok"
			and result.recordings[0].validation_status == "source_trace_unavailable",
			"%s input is a deterministic optional-source gap" % case_id)
		var comparison: Dictionary = result.comparisons[0]
		_t.expect(_lane(comparison, "source_observed_smoothed").samples.is_empty(),
			"%s input fabricates no source samples" % case_id)
		_t.expect(_lane(comparison, "generated_raw").samples.size() == 2,
			"%s input preserves the generated lane" % case_id)


func _test_exact_anchor_resolution(overlay: Script) -> void:
	var csv := "Time,Lateral,Vertical,Longitudinal\n0.00,0,1,-1\n0.02,0,1,-1\n0.04,0,1,-1\n0.06,0,1,-1\n"
	var path := "user://rfdb-overlay-anchor.csv"
	_write(path, csv)
	for beats in [[], [_measurement().beats[0], _measurement().beats[0].duplicate(true)]]:
		var measurement := _measurement()
		measurement.beats = beats
		var manifest := _manifest(csv)
		var result := _build(overlay, manifest, {"test-source": path}, measurement, _route())
		var comparison: Dictionary = result.comparisons[0]
		_t.expect(comparison.generated.status == "generated_window_unavailable"
			and _lane(comparison, "generated_raw").samples.is_empty(),
			"zero or duplicate exact anchors do not use fuzzy fallback")
		_t.expect(_lane(comparison, "source_observed_smoothed").samples.size() == 3,
			"generated anchor gaps do not discard valid source evidence")


func _test_manifest_validation(overlay: Script) -> void:
	for manifest in [{}, {"schema_version": "wrong", "recordings": []},
		{"schema_version": "rfdb-local-overlay-manifest@1", "recordings": [{"source_id": "x"}]}]:
		var result := _build(overlay, manifest, {}, _measurement(), _route())
		_t.expect(result.get("status") == "invalid-input" and not result.get("errors", []).is_empty(),
			"malformed committed manifest is operationally invalid")
	var path_shaped := _manifest("Time,Lateral,Vertical,Longitudinal\n0.00,0,1,0\n0.02,0,1,0\n0.04,0,1,0\n0.06,0,1,0\n")
	path_shaped.recordings[0].comparisons[0].comparison_id = "../local-secret"
	_t.expect(_build(overlay, path_shaped, {}, _measurement(), _route()).status == "invalid-input",
		"artifact-facing identifiers cannot contain path syntax")
	var base := _manifest("Time,Lateral,Vertical,Longitudinal\n0.00,0,1,0\n0.02,0,1,0\n0.04,0,1,0\n0.06,0,1,0\n")
	var cases := []
	for key in ["source_url", "ride_window_s", "processing_label", "smoothing", "device",
		"row_seat", "reliability", "derivation"]:
		var missing := base.duplicate(true)
		missing.recordings[0].erase(key)
		cases.append(missing)
	var bad_mask := base.duplicate(true)
	bad_mask.recordings[0].masks = [{"window_s": [0.02, 0.04]}]
	cases.append(bad_mask)
	var bad_window := base.duplicate(true)
	bad_window.recordings[0].comparisons[0].source_window_s = [2.0, 3.0]
	cases.append(bad_window)
	var bad_marker := base.duplicate(true)
	bad_marker.recordings[0].comparisons[0].markers = [{"id": "apex", "time_s": "0.02"}]
	cases.append(bad_marker)
	var bad_anchor := base.duplicate(true)
	bad_anchor.recordings[0].comparisons[0].generated_anchor.occurrence = "0"
	cases.append(bad_anchor)
	var bad_row := base.duplicate(true)
	bad_row.recordings[0].generated_row_id = "row/02"
	cases.append(bad_row)
	for malformed: Dictionary in cases:
		var result := _build(overlay, malformed, {}, _measurement(), _route())
		_t.expect(result.status == "invalid-input" and not result.errors.is_empty(),
			"nested malformed evidence is rejected before dereference")


func _test_exact_manifest_digest(overlay: Script) -> void:
	var bytes := FileAccess.get_file_as_bytes(MANIFEST_PATH)
	var manifest: Dictionary = JSON.parse_string(bytes.get_string_from_utf8())
	var result: Dictionary = overlay.build(manifest, bytes, {}, _measurement(), _route(),
		References.CATALOG.transforms)
	_t.expect(result.manifest_sha256 == FileAccess.get_sha256(MANIFEST_PATH),
		"manifest_sha256 authenticates the exact committed JSON bytes")
	var different_bytes := CanonicalData.canonical_json(manifest).to_utf8_buffer()
	if different_bytes != bytes:
		_t.expect(overlay.build(manifest, different_bytes, {}, _measurement(), _route(),
			References.CATALOG.transforms).manifest_sha256 != result.manifest_sha256,
			"byte formatting changes the manifest digest")
	var mismatched := different_bytes.get_string_from_utf8().replace("test-never", "changed")
	_t.expect(overlay.build({}, mismatched.to_utf8_buffer(), {}, _measurement(), _route(),
		References.CATALOG.transforms).status == "invalid-input",
		"manifest bytes and parsed data must describe the same evidence")


func _test_transform_authority(overlay: Script) -> void:
	var csv := "Time,Lateral,Vertical,Longitudinal\n0.00,1,2,-1\n0.02,1,2,-1\n0.04,1,2,-1\n0.06,1,2,-1\n"
	var path := "user://rfdb-overlay-authority.csv"
	_write(path, csv)
	var manifest := _manifest(csv)
	var authority: Dictionary = References.CATALOG.transforms.duplicate(true)
	authority["fictional.gz-positive@1"].factor = 2.0
	var bytes := CanonicalData.canonical_json(manifest).to_utf8_buffer()
	var result: Dictionary = overlay.build(manifest, bytes, {"test-source": path},
		_measurement(), _route(), authority)
	_t.expect(_lane(result.comparisons[0], "approved_scaled_target").samples[0].normal_g == 4.0,
		"scaled lane consumes the supplied authoritative transform registry")
	var malformed_authority := References.CATALOG.transforms.duplicate(true)
	malformed_authority["fictional.gz-positive@1"].axis = "lateral_g"
	_t.expect(overlay.build(manifest, bytes, {}, _measurement(), _route(),
		malformed_authority).status == "invalid-input",
		"transform authority must match the manifest axis and polarity")


func _test_committed_manifest(overlay: Script) -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	_t.expect(manifest is Dictionary, "committed overlay manifest reopens as JSON")
	if not manifest is Dictionary:
		return
	var result: Dictionary = overlay.build(manifest, FileAccess.get_file_as_bytes(MANIFEST_PATH), {},
		_measurement(), _route(), References.CATALOG.transforms)
	_t.expect(result.status == "ok" and result.recordings.size() == 2
		and result.comparisons.size() == 4,
		"committed sample-free manifest validates two recordings and four comparisons: %s" % str(result))
	var route: Dictionary = Generator.build(42)
	var measurement: Dictionary = Fidelity.measure_route(route, RouteContract.ROW_OFFSETS)
	var anchored: Dictionary = overlay.build(manifest, FileAccess.get_file_as_bytes(MANIFEST_PATH),
		{}, measurement, route, References.CATALOG.transforms)
	var unavailable: Array = anchored.get("comparisons", []).filter(
		func(comparison: Dictionary): return comparison.generated.status != "available")
	_t.expect(unavailable.is_empty() and anchored.get("comparisons", []).size() == 4,
		"every committed RFDB anchor resolves exactly once against the current seed-42 route")


func _test_optional_local_exports(overlay: Script) -> void:
	var files := {"rfdb-4804": OS.get_environment("RFDB_4804_CSV"),
		"rfdb-6383": OS.get_environment("RFDB_6383_CSV")}
	if str(files["rfdb-4804"]).is_empty() or str(files["rfdb-6383"]).is_empty():
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	var result: Dictionary = overlay.build(manifest, FileAccess.get_file_as_bytes(MANIFEST_PATH),
		files, _measurement(), _route(), References.CATALOG.transforms)
	_t.expect(result.recordings.map(func(record: Dictionary): return record.validation_status)
		== ["available", "available"],
		"digest-matched optional local RFDB exports validate at native cadence")
	var counts: Array = result.comparisons.map(
		func(comparison: Dictionary): return comparison.source.sample_count)
	_t.expect(counts == [338, 115, 165, 232],
		"four source windows retain their native half-open samples: %s" % str(counts))


func _manifest(csv: String) -> Dictionary:
	return {
		"schema_version": "rfdb-local-overlay-manifest@1",
		"recordings": [{
			"source_id": "test-source", "source_url": "https://example.invalid/source",
			"expected_sha256": _sha(csv), "expected_byte_size": csv.to_utf8_buffer().size(),
			"header": ["Time", "Lateral", "Vertical", "Longitudinal"],
			"sample_count": 4, "cadence_s": 0.02,
			"full_window_s": [0.0, 0.06], "ride_window_s": [0.0, 0.06],
			"processing_label": "source_observed_smoothed",
			"smoothing": "reviewed export", "row_seat": "test row",
			"generated_row_id": "row-04",
			"device": "test device", "reliability": "low",
			"masks": [{"window_s": [0.02, 0.04], "reason": "test-mask"}],
			"transforms": {"normal_g": {"positive": "fictional.gz-positive@1",
				"negative": "fictional.gz-negative@1"},
				"lateral_g": {"positive": "fictional.gy-positive@1",
					"negative": "fictional.gy-negative@1"},
				"longitudinal_g": {"positive": null,
					"negative": "fictional.gx-negative@1"}},
			"derivation": {"tool": "RideFidelityOverlay", "version": 1},
			"comparisons": [{
				"comparison_id": "test-loop", "source_window_s": [0.0, 0.06],
				"identity_confidence": "medium-low", "evidence_class": "corroborative",
				"generated_anchor": {"story_slot_id": "story", "window_role": "role",
					"kind": "loop", "occurrence": 0},
				"markers": [{"id": "entry", "time_s": 0.0, "uncertainty_s": 0.2},
					{"id": "apex", "time_s": 0.02, "uncertainty_s": 0.5},
					{"id": "exit", "time_s": 0.06, "uncertainty_s": 0.2}],
				"caveats": ["no attitude channel"],
			}],
		}],
	}


func _measurement() -> Dictionary:
	return {"seed": 42, "beats": [{
		"beat_id": "story/role/00-loop", "story_slot_id": "story", "window_role": "role",
		"kind": "loop", "occurrence": 0,
		"rows": [{"row_id": "row-02", "offset": 2.15,
			"window_start_s": 20.0, "window_end_s": 21.0},
			{"row_id": "row-04", "offset": 6.45,
				"window_start_s": 20.0, "window_end_s": 21.0}],
	}]}


func _route() -> Dictionary:
	return {"times": PackedFloat32Array([19.5, 20.0, 20.5, 21.0]),
		"length": 50.0, "distances": PackedFloat32Array([0.0, 20.0, 30.0, 40.0]),
		"speeds": PackedFloat32Array([20.0, 20.0, 20.0, 20.0]),
		"tangents": PackedVector3Array([Vector3.RIGHT, Vector3.RIGHT,
			Vector3.RIGHT, Vector3.RIGHT]),
		"ups": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP]),
		"curvatures": PackedVector3Array([Vector3.UP * 0.01, Vector3.UP * 0.02,
			Vector3.UP * 0.03, Vector3.UP * 0.04]),
		"roll_rates": PackedFloat32Array([0.0, 0.0, 0.0, 0.0]),
		"normal_g": PackedFloat32Array([1.0, 4.0, -2.0, 1.0]),
		"lateral_g": PackedFloat32Array([0.0, -0.25, 0.5, 0.0]),
		"longitudinal_g": PackedFloat32Array([0.0, 0.125, -0.75, 0.0])}


func _build(
	overlay: Script, manifest: Dictionary, files: Dictionary,
	measurement: Dictionary, route: Dictionary
) -> Dictionary:
	return overlay.build(manifest, CanonicalData.canonical_json(manifest).to_utf8_buffer(), files,
		measurement, route, References.CATALOG.transforms)


func _lane(comparison: Dictionary, role: String) -> Dictionary:
	for lane: Dictionary in comparison.lanes:
		if lane.role == role:
			return lane
	return {}


func _times(samples: Array) -> Array:
	return samples.map(func(sample: Dictionary): return sample.time_s)


func _sha(text: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(text.to_utf8_buffer())
	return context.finish().hex_encode()


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)


func _reverse_dictionaries(value: Variant) -> Variant:
	if value is Dictionary:
		var output := {}
		var keys: Array = value.keys()
		keys.reverse()
		for key in keys:
			output[key] = _reverse_dictionaries(value[key])
		return output
	if value is Array:
		return value.map(func(item: Variant): return _reverse_dictionaries(item))
	return value

