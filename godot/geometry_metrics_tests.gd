extends SceneTree

## Focused suite for RideGeometryMetrics and RideGeometryReference.
##
## Every case is a synthetic route with a known answer, so a regression in the fit, the seam
## differencing or the silhouette shows up as a wrong number rather than a plausible one. The
## reference-manifest cases cover the local-media contract: a bad digest is rejected, an absent
## file is isolated to its own entry, and a valid manifest is accepted.

const Metrics := preload("res://geometry_metrics.gd")
const Reference := preload("res://geometry_reference.gd")
const CanonicalData := preload("res://canonical_data.gd")

var _errors := PackedStringArray()


func _initialize() -> void:
	_test_planar_circle_is_planar()
	_test_tilted_ellipse_reports_its_tilt()
	_test_helix_is_reported_not_judged()
	_test_stepped_roll_reports_the_seam_jump()
	_test_roll_profile_counts_the_steps()
	_test_shape_ratios_measure_the_silhouette()
	_test_near_vertical_tangents_do_not_invent_heading()
	_test_degenerate_window_is_unavailable_not_planar()
	_test_element_geometry_resolution()
	_test_missing_fields_are_reported()
	_test_determinism()
	_test_counterpart_comparison_labels()
	_test_manifest_accepts_a_valid_entry()
	_test_manifest_rejects_a_bad_digest()
	_test_manifest_isolates_an_absent_file()
	_test_manifest_structural_rejection()
	_test_composite_is_deterministic()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


# ---------------------------------------------------------------------------------------------
# Planarity
# ---------------------------------------------------------------------------------------------

func _test_planar_circle_is_planar() -> void:
	# A circle drawn in the world XY plane: every point lies exactly on that plane, and the plane
	# contains the vertical, so both the deviation and the tilt off vertical are ~0.
	var points := _circle(40.0, 1.0, 0.0, 96)
	var route := _route(points, [_role("marquee-camelback", "crest", 0, 0, points.size() - 1)])
	var result := Metrics.element_planarity(route)
	var element: Dictionary = result.elements[0]
	_expect(element.status == "measured", "a circle is measurable")
	_expect(absf(float(element.rms_out_of_plane_m)) < 1e-4,
		"a planar circle has ~0 out-of-plane RMS, got %s" % str(element.rms_out_of_plane_m))
	_expect(element.planarity_class == "planar",
		"a planar circle classifies as planar, got %s" % str(element.planarity_class))
	_expect(absf(float(element.vertical_plane_tilt_deg)) < 0.05,
		"a vertical circle has ~0 tilt off vertical, got %s" % str(element.vertical_plane_tilt_deg))
	_expect(element.tilt_is_meaningful, "a planar element's tilt is meaningful")


func _test_tilted_ellipse_reports_its_tilt() -> void:
	# The same closed curve, stretched into an ellipse and rotated 20 degrees about the travel
	# axis. It stays perfectly planar; only the plane leans.
	for expected in [12.0, 20.0, 35.0]:
		var points := _circle(60.0, 2.0, deg_to_rad(expected), 120)
		var route := _route(points, [_role("marquee-camelback", "crest", 0, 0, points.size() - 1)])
		var element: Dictionary = Metrics.element_planarity(route).elements[0]
		_expect(absf(float(element.rms_out_of_plane_m)) < 1e-3,
			"a tilted ellipse is still planar, got RMS %s" % str(element.rms_out_of_plane_m))
		_expect(absf(float(element.vertical_plane_tilt_deg) - expected) < 0.05,
			"a %s degree tilt is reported as %s" % [expected, str(element.vertical_plane_tilt_deg)])


func _test_helix_is_reported_not_judged() -> void:
	# A helix genuinely leaves every plane. The record must say so and must withdraw the tilt
	# rather than scoring a meaningless fit.
	var points := PackedVector3Array()
	for index in 160:
		var angle := TAU * float(index) / 40.0
		points.append(Vector3(cos(angle) * 40.0, sin(angle) * 40.0 + 50.0, float(index) * 1.0))
	var route := _route(points, [_role("act-one", "giant-inversion", 1, 0, points.size() - 1)])
	var element: Dictionary = Metrics.element_planarity(route).elements[0]
	_expect(element.planarity_class == "three-dimensional",
		"a helix is three-dimensional, got %s" % str(element.planarity_class))
	_expect(not element.tilt_is_meaningful, "a three-dimensional element withdraws its tilt claim")
	_expect(Metrics.element_planarity(route).worst_vertical_tilts.is_empty(),
		"a three-dimensional element never enters the worst-tilt ranking")


# ---------------------------------------------------------------------------------------------
# Seam roll continuity
# ---------------------------------------------------------------------------------------------

func _test_stepped_roll_reports_the_seam_jump() -> void:
	var points := _line(400)
	var rolls := PackedFloat32Array()
	rolls.resize(points.size())
	# Roll hard through the first role, stop dead at the seam: the classic stepped handoff.
	for index in points.size():
		rolls[index] = 60.0 if index < 200 else 0.0
	var route := _route(points, [
		_role("opener", "twisted-drop", 0, 0, 199), _role("opener", "teardrop", 0, 200, 399),
	], rolls)
	var result := Metrics.seam_roll_continuity(route)
	_expect(result.seam_count == 1, "two role windows make one seam, got %d" % int(result.seam_count))
	var seam: Dictionary = result.seams[0]
	_expect(absf(float(seam.roll_rate_jump_dps) + 60.0) < 1e-3,
		"the seam jump is -60 deg/s, got %s" % str(seam.roll_rate_jump_dps))
	_expect(seam.boundary_sample == 200, "the seam is at the first sample of the later role")
	_expect(seam.gesture_boundary == false, "roles inside one gesture are not a gesture seam")
	_expect(float(seam.roll_acceleration_across_dps2) < -700.0,
		"a step across one sample is a huge roll acceleration, got %s"
			% str(seam.roll_acceleration_across_dps2))
	_expect(result.worst_roll_rate_jumps.size() == 1
		and str(result.worst_roll_rate_jumps[0].window_id) == "opener/teardrop/00",
		"the worst-offender list names the window entered at the seam")

	var smooth := PackedFloat32Array()
	smooth.resize(points.size())
	smooth.fill(60.0)
	var continuous := _route(points, [
		_role("opener", "twisted-drop", 0, 0, 199), _role("opener", "teardrop", 0, 200, 399),
	], smooth)
	var clean: Dictionary = Metrics.seam_roll_continuity(continuous).seams[0]
	_expect(absf(float(clean.roll_rate_jump_dps)) < 1e-6,
		"a continuous roll crosses the seam with no jump, got %s" % str(clean.roll_rate_jump_dps))


func _test_roll_profile_counts_the_steps() -> void:
	var points := _line(600)
	var rolls := PackedFloat32Array()
	var banks := PackedFloat32Array()
	rolls.resize(points.size())
	banks.resize(points.size())
	# roll -> flat -> roll inside ONE window, while banked throughout: issue 20's signature.
	for index in points.size():
		var block := index / 200
		rolls[index] = 0.0 if block == 1 else 45.0
		banks[index] = 55.0
	var route := _route(points, [_role("opener", "twisted-drop", 0, 0, 599)], rolls, banks)
	var profile: Dictionary = Metrics.seam_roll_continuity(route).role_roll_profiles[0]
	_expect(profile.roll_segment_count == 2,
		"roll -> flat -> roll is two segments, got %d" % int(profile.roll_segment_count))
	_expect(absf(float(profile.flat_roll_share) - 1.0 / 3.0) < 0.01,
		"a third of the window is flat, got %s" % str(profile.flat_roll_share))
	_expect(absf(float(profile.banked_flat_roll_share) - 1.0 / 3.0) < 0.01,
		"the flat third is banked throughout, got %s" % str(profile.banked_flat_roll_share))
	_expect(absf(float(profile.roll_rate_peak_dps) - 45.0) < 1e-3, "the peak roll rate is 45 deg/s")


# ---------------------------------------------------------------------------------------------
# Shape ratios
# ---------------------------------------------------------------------------------------------

func _test_shape_ratios_measure_the_silhouette() -> void:
	# A symmetric hill 40 m tall over 200 m of ground, in a straight line.
	var points := PackedVector3Array()
	for index in 201:
		var fraction := float(index) / 200.0
		points.append(Vector3(float(index), sin(fraction * PI) * 40.0, 0.0))
	var route := _route(points, [_role("raceway-return", "height-airtime-a", 0, 0, 200)])
	var element: Dictionary = Metrics.shape_ratios(route).elements[0]
	_expect(absf(float(element.height_extent_m) - 40.0) < 0.01,
		"the hill is 40 m tall, got %s" % str(element.height_extent_m))
	_expect(absf(float(element.plan_along_m) - 200.0) < 0.01,
		"the hill is 200 m long in plan, got %s" % str(element.plan_along_m))
	_expect(absf(float(element.plan_across_m)) < 1e-6, "a straight hill has no plan width")
	_expect(float(element.track_length_m) > 200.0,
		"the swept length exceeds the plan length, got %s" % str(element.track_length_m))
	_expect(absf(float(element.total_heading_change_deg)) < 1e-3,
		"a straight hill turns through no heading, got %s" % str(element.total_heading_change_deg))
	_expect(float(element.entry_pitch_deg) > 20.0 and float(element.exit_pitch_deg) < -20.0,
		"the hill pitches up on entry and down on exit")

	# A quarter turn must report ~90 degrees of accumulated heading.
	var turn := PackedVector3Array()
	for index in 91:
		var angle := deg_to_rad(float(index))
		turn.append(Vector3(sin(angle) * 100.0, 0.0, 100.0 - cos(angle) * 100.0))
	var turn_route := _route(turn, [_role("raceway-return", "turn-a", 0, 0, 90)])
	var turn_element: Dictionary = Metrics.shape_ratios(turn_route).elements[0]
	_expect(absf(absf(float(turn_element.total_heading_change_deg)) - 90.0) < 1.5,
		"a quarter turn accumulates ~90 degrees, got %s"
			% str(turn_element.total_heading_change_deg))


func _test_element_geometry_resolution() -> void:
	var points := _line(300)
	var route := _route(points, [
		_role("marquee-camelback", "rise", 0, 0, 99),
		_role("marquee-camelback", "crest", 0, 100, 199),
		_role("marquee-camelback", "fall", 0, 200, 299),
	])
	var by_window := Metrics.element_geometry(route, "marquee-camelback/crest/00")
	_expect(by_window.status == "resolved" and by_window.matched_by == "window_id"
		and by_window.first == 100 and by_window.last == 199,
		"a compiled window id resolves to exactly its span")
	var by_role := Metrics.element_geometry(route, "camelback")
	_expect(by_role.status == "resolved" and by_role.matched_by == "material_role"
		and by_role.first == 0 and by_role.last == 299
		and by_role.window_ids.size() == 3,
		"a material role resolves to the union of its compiled windows")
	_expect(Metrics.element_geometry(route, "nonexistent").status == "no-generated-element",
		"an unknown element id is reported, never guessed")


func _test_missing_fields_are_reported() -> void:
	var result := Metrics.seam_roll_continuity({"positions": PackedVector3Array()})
	_expect(result.status == "route-unavailable", "an incomplete route is declared unavailable")
	_expect(result.missing_fields.size() > 1, "every missing field is named")


# ---------------------------------------------------------------------------------------------
# Determinism
# ---------------------------------------------------------------------------------------------

func _test_determinism() -> void:
	var points := _circle(50.0, 1.4, deg_to_rad(17.0), 111)
	var rolls := PackedFloat32Array()
	rolls.resize(points.size())
	for index in points.size():
		rolls[index] = sin(float(index) * 0.37) * 40.0
	var route := _route(points, [
		_role("opener", "twisted-drop", 0, 0, 54), _role("opener", "teardrop", 0, 55, 110),
	], rolls)
	var first := CanonicalData.canonical_json(Metrics.measure(route))
	var second := CanonicalData.canonical_json(Metrics.measure(_route(points, [
		_role("opener", "twisted-drop", 0, 0, 54), _role("opener", "teardrop", 0, 55, 110),
	], rolls)))
	_expect(not first.is_empty(), "the pack is canonical-JSON admissible (no INF, no NaN)")
	_expect(first == second, "the same input measures identically twice")
	_expect(not Metrics.markdown(Metrics.measure(route), {}).is_empty(),
		"the Markdown renders without a reference manifest")
	_expect(Metrics.markdown(Metrics.measure(route), {})
		== Metrics.markdown(Metrics.measure(route), {}),
		"the Markdown is byte-identical across runs")
	_expect(Metrics.markdown(Metrics.measure(route), {}).contains("Declared gap"),
		"an absent reference manifest is declared, not silently omitted")


# ---------------------------------------------------------------------------------------------
# Counterpart comparison
# ---------------------------------------------------------------------------------------------

func _test_counterpart_comparison_labels() -> void:
	var points := _line(1200)
	var route := _route(points, [
		_role("marquee-camelback", "rise", 0, 0, 399),
		_role("marquee-camelback", "crest", 0, 400, 799),
		_role("marquee-camelback", "fall", 0, 800, 1199),
	])
	var result := Metrics.counterpart_comparison(route, 0.0)
	_expect(result.schema_version == Metrics.COUNTERPART_SCHEMA, "the comparison declares its schema")
	_expect(result.mapping.mapped_window_count == 3, "every compiled window is bridged")
	_expect(result.mapping.unmapped_windows.is_empty(), "no compiled window is left unmapped")
	_expect(result.mapping.material_roles_without_window.size() == 17,
		"the eighteen non-gap roles minus the one present role are reported missing, got %d"
			% result.mapping.material_roles_without_window.size())
	var gap_roles := []
	for gap: Dictionary in result.evidence_gaps:
		gap_roles.append(str(gap.role_id))
	_expect(gap_roles == ["act-one-wave", "clifftop-outward-rim"],
		"the counterpart evidence gaps are carried through verbatim, got %s" % str(gap_roles))
	var camelback := []
	for row: Dictionary in result.rows:
		if row.role_id == "camelback":
			camelback.append(row)
	_expect(not camelback.is_empty(), "the camelback role produces comparison rows")
	for row: Dictionary in camelback:
		_expect(row.status in ["within", "under", "over", "unmapped", "no-adopted-target"],
			"every row carries a label, got %s" % str(row.status))
		_expect(row.window_ids.size() == 3, "the camelback row names its three compiled windows")
	_expect(CanonicalData.canonical_json(result) == CanonicalData.canonical_json(
		Metrics.counterpart_comparison(route, 0.0)),
		"the counterpart comparison is deterministic")
	_expect(not Metrics.counterpart_markdown([result]).is_empty(), "the fleet Markdown renders")


# ---------------------------------------------------------------------------------------------
# Reference manifest and composites
# ---------------------------------------------------------------------------------------------

func _test_manifest_accepts_a_valid_entry() -> void:
	var image_path := "user://geometry-reference-valid.png"
	var digest := _write_png(image_path, 64, 48)
	var manifest := _manifest([_entry("camelback", "geometry-reference-valid.png", digest)])
	var result := Reference.build(_bytes(manifest), "user://")
	_expect(result.status == "ok", "a valid manifest is accepted: %s" % str(result.get("errors")))
	_expect(result.entry_count == 1 and result.available_count == 1, "the entry resolves")
	var entry: Dictionary = result.entries[0]
	_expect(entry.status == "available" and entry.observed_sha256 == digest,
		"the entry is accepted by content, got %s" % str(entry.status))
	_expect(entry.width == 64 and entry.height == 48, "the reference image dimensions are recorded")


func _test_manifest_rejects_a_bad_digest() -> void:
	var image_path := "user://geometry-reference-baddigest.png"
	_write_png(image_path, 32, 32)
	var wrong := "0".repeat(64)
	var manifest := _manifest([_entry("camelback", "geometry-reference-baddigest.png", wrong)])
	var result := Reference.build(_bytes(manifest), "user://")
	_expect(result.status == "ok", "a wrong digest is an entry finding, not a manifest failure")
	_expect(result.entries[0].status == "digest-mismatch",
		"a wrong digest is rejected, got %s" % str(result.entries[0].status))
	_expect(result.available_count == 0, "a rejected entry is not available for compositing")


func _test_manifest_isolates_an_absent_file() -> void:
	var image_path := "user://geometry-reference-present.png"
	var digest := _write_png(image_path, 40, 30)
	var manifest := _manifest([
		_entry("camelback", "geometry-reference-present.png", digest),
		_entry("outward-dive", "geometry-reference-absent.png", "a".repeat(64)),
	])
	var result := Reference.build(_bytes(manifest), "user://")
	_expect(result.status == "ok", "one absent file does not reject the manifest")
	_expect(result.available_count == 1, "the present entry survives its neighbour's absence")
	var by_element := {}
	for entry: Dictionary in result.entries:
		by_element[entry.element_id] = entry
	_expect(by_element["camelback"].status == "available", "the present entry is available")
	_expect(by_element["outward-dive"].status == "file-missing",
		"the absent entry is isolated, got %s" % str(by_element["outward-dive"].status))


func _test_manifest_structural_rejection() -> void:
	var cases := [
		[{"schema_version": "wrong@9", "entries": []}, "schema_version"],
		[{"schema_version": Reference.MANIFEST_SCHEMA, "entries": {}}, "entries must be an Array"],
		[{"schema_version": Reference.MANIFEST_SCHEMA, "entries": []}, "declares no entries"],
	]
	for case in cases:
		var errors := Reference.validate(case[0])
		_expect(not errors.is_empty(), "a malformed manifest is rejected: %s" % str(case[1]))
	var manifest := _manifest([_entry("camelback", "frame.png", "not-hex")])
	_expect(not Reference.validate(manifest).is_empty(), "a non-hex digest is rejected")
	var escaping := _manifest([_entry("camelback", "../../etc/passwd", "b".repeat(64))])
	_expect(not Reference.validate(escaping).is_empty(), "an escaping image path is rejected")
	var undated := _manifest([_entry("camelback", "frame.png", "c".repeat(64))])
	undated.entries[0].provenance.erase("timestamp_s")
	undated.entries[0].provenance.erase("description")
	_expect(not Reference.validate(undated).is_empty(),
		"an entry with neither a timestamp nor a description is rejected")
	_expect(Reference.build(PackedByteArray([1, 2, 3]), "user://").status == "invalid-manifest",
		"non-JSON manifest bytes are rejected")


func _test_composite_is_deterministic() -> void:
	var reference := Image.create(200, 120, false, Image.FORMAT_RGB8)
	reference.fill(Color(0.2, 0.4, 0.6))
	var generated := Image.create(300, 200, false, Image.FORMAT_RGB8)
	generated.fill(Color(0.6, 0.2, 0.2))
	var lines := Reference.footer_lines("camelback",
		{"height_extent_m": 251.4, "horizontal_extent_m": 800.0, "track_length_m": 1000.0,
			"height_to_length_ratio": 0.2514, "total_heading_change_deg": -3.2,
			"entry_pitch_deg": 12.0, "exit_pitch_deg": -12.0, "entry_bank_deg": 1.0,
			"exit_bank_deg": -1.0},
		{"planarity_class": "planar", "rms_out_of_plane_m": 0.4,
			"vertical_plane_tilt_deg": 8.75},
		{"source_id": "youtube.falcon.forward.cuurkqyn4zs", "acquisition": "thumbnail-fallback"})
	_expect(lines.size() >= 4, "the footer carries the element's shape numbers")
	_expect(str(lines[1]).contains("251.4"), "the footer prints the measured height")
	var first := Reference.composite(reference, generated, lines)
	var second := Reference.composite(reference, generated, lines)
	_expect(first.get_size() == Vector2i(
		Reference.PANE_SIZE.x * 2 + Reference.DIVIDER,
		Reference.PANE_SIZE.y + Reference.FOOTER_HEIGHT),
		"the composite is two panes plus a footer")
	_expect(first.get_data() == second.get_data(), "the composite is byte-identical across runs")
	_expect(Reference.composite(null, generated, lines).get_data() != first.get_data(),
		"a missing reference pane still composites, without inventing imagery")


# ---------------------------------------------------------------------------------------------
# Synthetic route construction
# ---------------------------------------------------------------------------------------------

## A closed curve in the world XY plane, optionally stretched and rotated about the X axis by
## `tilt`. Rotating about X sends the plane normal (0,0,1) to (0, -sin tilt, cos tilt), so the
## expected reported tilt off vertical is exactly `tilt`.
func _circle(radius: float, stretch: float, tilt: float, count: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for index in count:
		var angle := TAU * float(index) / float(count - 1)
		var local := Vector3(cos(angle) * radius * stretch, sin(angle) * radius + radius + 5.0, 0.0)
		points.append(Vector3(
			local.x, local.y * cos(tilt) - local.z * sin(tilt),
			local.y * sin(tilt) + local.z * cos(tilt)))
	return points


func _line(count: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for index in count:
		points.append(Vector3(float(index) * 2.0, 30.0, 0.0))
	return points


func _role(story: String, role: String, occurrence: int, first: int, last: int) -> Dictionary:
	return {
		"story_slot_id": story, "id": role, "occurrence": occurrence,
		"window_id": "%s/%s/%02d" % [story, role, occurrence],
		"diagnostic_kind": "", "first": first, "last": last,
	}


## Assemble a route Dictionary with exactly the fields the metrics read. Times come from a
## constant 25 m/s so the resample grid is well defined.
func _route(
	points: PackedVector3Array, roles: Array,
	rolls: PackedFloat32Array = PackedFloat32Array(),
	banks: PackedFloat32Array = PackedFloat32Array()
) -> Dictionary:
	var count := points.size()
	var speed := 25.0
	var tangents := PackedVector3Array()
	var ups := PackedVector3Array()
	var distances := PackedFloat32Array()
	var times := PackedFloat32Array()
	var speeds := PackedFloat32Array()
	var normal := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	var longitudinal := PackedFloat32Array()
	tangents.resize(count)
	ups.resize(count)
	distances.resize(count)
	times.resize(count)
	speeds.resize(count)
	normal.resize(count)
	lateral.resize(count)
	longitudinal.resize(count)
	var travelled := 0.0
	for index in count:
		if index > 0:
			travelled += points[index].distance_to(points[index - 1])
		distances[index] = travelled
		times[index] = travelled / speed
		speeds[index] = speed
		normal[index] = 1.0
		lateral[index] = 0.0
		longitudinal[index] = 0.0
		var forward: Vector3 = (
			points[mini(index + 1, count - 1)] - points[maxi(index - 1, 0)]
		)
		if forward.length_squared() <= 0.0:
			forward = Vector3.RIGHT
		tangents[index] = forward.normalized()
		var right := tangents[index].cross(Vector3.UP)
		if right.length_squared() <= 0.0:
			right = Vector3.RIGHT
		ups[index] = right.normalized().cross(tangents[index]).normalized()
	var roll_rates := rolls
	if roll_rates.size() != count:
		roll_rates = PackedFloat32Array()
		roll_rates.resize(count)
	var bank_degrees := banks
	if bank_degrees.size() != count:
		bank_degrees = PackedFloat32Array()
		bank_degrees.resize(count)
	return {
		"seed": 4242, "positions": points, "tangents": tangents, "ups": ups,
		"banks": bank_degrees, "roll_rates": roll_rates, "times": times, "distances": distances,
		"speeds": speeds, "normal_g": normal, "lateral_g": lateral,
		"longitudinal_g": longitudinal, "length": travelled,
		"duration": times[count - 1],
		"gesture_windows": _gestures(roles),
	}


func _gestures(roles: Array) -> Array:
	var gestures := []
	for role: Dictionary in roles:
		var story: String = role.story_slot_id
		if gestures.is_empty() or str(gestures[-1].story_slot_id) != story:
			gestures.append({"story_slot_id": story, "first": role.first, "last": role.last,
				"role_windows": []})
		gestures[-1].role_windows.append(role)
		gestures[-1].last = role.last
	return gestures


# ---------------------------------------------------------------------------------------------
# Reference manifest fixtures
# ---------------------------------------------------------------------------------------------

func _manifest(entries: Array) -> Dictionary:
	return {
		"schema_version": Reference.MANIFEST_SCHEMA,
		"manifest_version": "test",
		"entries": entries,
	}


func _entry(element_id: String, image_path: String, digest: String) -> Dictionary:
	return {
		"element_id": element_id,
		"image_path": image_path,
		"provenance": {
			"source_id": "youtube.falcon.forward.cuurkqyn4zs",
			"source_url": "https://www.youtube.com/watch?v=cUURkqyn4Zs",
			"evidence_class": "observation_only",
			"acquisition": "test-fixture",
			"timestamp_s": 61.5,
			"description": "synthetic fixture",
			"sha256": digest,
		},
		"caveats": ["synthetic fixture"],
	}


func _write_png(path: String, width: int, height: int) -> String:
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	image.fill(Color(float(width) / 255.0, float(height) / 255.0, 0.5))
	image.save_png(path)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(FileAccess.get_file_as_bytes(path))
	return context.finish().hex_encode()


func _bytes(manifest: Dictionary) -> PackedByteArray:
	return JSON.stringify(manifest).to_utf8_buffer()


## A 90° dive: the horizontal projection of a near-vertical tangent carries float noise whose
## direction is meaningless; the heading must carry through it, not sum the noise.
func _test_near_vertical_tangents_do_not_invent_heading() -> void:
	var tangents := PackedVector3Array([
		Vector3(1.0, 0.0, 0.0),
		Vector3(0.7, -0.7141, 0.0).normalized(),
		Vector3(0.00001, -1.0, -0.000007).normalized(),
		Vector3(-0.000004, -1.0, 0.000009).normalized(),
		Vector3(0.000008, -1.0, 0.000002).normalized(),
		Vector3(0.7, -0.7141, 0.0).normalized(),
		Vector3(1.0, 0.0, 0.0),
	])
	var headings := Metrics._plan_headings_deg(tangents, 0, tangents.size() - 1)
	_expect(headings.size() == tangents.size(), "one heading per sample")
	var accumulated := 0.0
	for index in range(1, headings.size()):
		accumulated += absf(rad_to_deg(angle_difference(
			deg_to_rad(headings[index - 1]), deg_to_rad(headings[index]))))
	_expect(accumulated < 0.001,
		"a vertical dive with no plan turn accumulates no heading change, got %.6f" % accumulated)
	var leading := PackedVector3Array([
		Vector3(0.00001, -1.0, 0.0).normalized(), Vector3(0.0, -0.7, 0.7141).normalized()])
	var led := Metrics._plan_headings_deg(leading, 0, 1)
	_expect(absf(led[0] - led[1]) < 0.001,
		"a window that opens near-vertical takes the first measurable heading")


## Coincident samples have no plane; the diagnostic says so instead of reporting 0° tilt.
func _test_degenerate_window_is_unavailable_not_planar() -> void:
	var positions := PackedVector3Array()
	for index in 8:
		positions.append(Vector3(100.0, 20.0, -5.0) + Vector3.ONE * 0.0001 * float(index % 2))
	var planarity := Metrics.planarity_of({"positions": positions}, 0, positions.size() - 1)
	_expect(planarity.status == "degenerate-extent" and planarity.planarity_class == "unavailable"
		and planarity.vertical_plane_tilt_deg == null and not planarity.tilt_is_meaningful,
		"a degenerate window is reported unavailable, got %s" % str(planarity))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
