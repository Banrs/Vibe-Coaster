extends SceneTree

const Coaster := preload("res://main.gd")
const FidelityTests := preload("res://fidelity_tests.gd")
const FidelityArtifactTests := preload("res://fidelity_artifact_tests.gd")
const Generator := preload("res://generator.gd")
const RouteContract := preload("res://route_contract.gd")
const Terrain := preload("res://terrain.gd")
const Verify := preload("res://verify.gd")

const DEEP_SEEDS := [11, 42, 20260809]
const SWEEP_SEEDS := [1, 3, 7, 99, 256, 555, 1234, 4096, 31337, 77777, 123456, 20250101]


func _initialize() -> void:
	var errors := PackedStringArray()
	errors.append_array(FidelityTests.run())
	errors.append_array(FidelityArtifactTests.run())
	errors.append_array(_terrain_errors())
	errors.append_array(_verify_errors())
	for seed_value in DEEP_SEEDS:
		errors.append_array(_deep_seed_errors(seed_value))
	errors.append_array(_sweep_errors())
	errors.append_array(_viewer_errors())
	for error in errors:
		printerr(error)
	quit(0 if errors.is_empty() else 1)


func _deep_seed_errors(seed_value: int) -> PackedStringArray:
	var errors := PackedStringArray()
	var route: Dictionary = Generator.build(seed_value)
	var repeat: Dictionary = Generator.build(seed_value)
	if not _accepted_route(route, seed_value, errors):
		return errors
	if not _accepted_route(repeat, seed_value, errors, "repeat "):
		return errors
	if var_to_bytes(route) != var_to_bytes(repeat):
		errors.append("seed %d: repeated builds are not bit-identical" % seed_value)
	var issues := PackedStringArray()
	_validate_structure_and_placement(route, issues)
	var analysis: Dictionary = Verify.analyze(route, RouteContract.ROW_OFFSETS)
	Verify.validate_loads(analysis, issues)
	for issue in issues:
		errors.append("seed %d: %s" % [seed_value, issue])
	print(
		"deep seed %d: %.0f m, %.1f s, %d samples, %.1f km/h top"
		% [seed_value, route.length, route.duration, route.positions.size(),
			analysis.top_speed * 3.6]
	)
	return errors


func _sweep_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var lengths := PackedFloat32Array()
	var clean := 0
	for seed_value in SWEEP_SEEDS:
		var seed_errors := PackedStringArray()
		var route: Dictionary = Generator.build(seed_value)
		if _accepted_route(route, seed_value, seed_errors):
			lengths.append(route.length)
			var issues := PackedStringArray()
			_validate_structure_and_placement(route, issues)
			for issue in issues:
				seed_errors.append("sweep seed %d: %s" % [seed_value, issue])
		if seed_errors.is_empty():
			clean += 1
		else:
			errors.append_array(seed_errors)
	if lengths.is_empty():
		print("seed sweep: 0 of %d build and place clean" % SWEEP_SEEDS.size())
	else:
		lengths.sort()
		print(
			"seed sweep: %d of %d build and place clean, lengths %.1f-%.1f km"
			% [clean, SWEEP_SEEDS.size(), lengths[0] / 1000.0, lengths[-1] / 1000.0]
		)
	return errors


func _viewer_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var started := Time.get_ticks_msec()
	var route: Dictionary = Generator.build(42)
	if not _accepted_route(route, 42, errors, "viewer "):
		return errors
	var analysis: Dictionary = Verify.analyze(route, RouteContract.ROW_OFFSETS)
	errors.append_array(Coaster.validate_route(route, analysis))
	var rails: ArrayMesh = Coaster.build_rail_mesh(route)
	var terrain: ArrayMesh = Coaster.build_terrain_mesh(route)
	var elapsed := Time.get_ticks_msec() - started
	if rails.get_surface_count() != 1 or rails.surface_get_array_len(0) < 30_000:
		errors.append("rail mesh is empty or incomplete")
	if terrain.get_surface_count() != 1:
		errors.append("terrain mesh is empty")
	if floori(route.length / Coaster.TIE_SPACING) < 1000:
		errors.append("track has too few visual speed cues")
	if elapsed > 20_000:
		errors.append("the viewer build, validation and meshes took %d ms" % elapsed)
	print(
		"seed 42 viewer route: %.1f m, %.1f s, %d samples, %.1f km/h top, %d ms"
		% [route.length, route.duration, route.positions.size(),
			analysis.top_speed * 3.6, elapsed]
	)
	return errors


func _accepted_route(
	route: Dictionary,
	seed_value: int,
	errors: PackedStringArray,
	label: String = ""
) -> bool:
	if not route.is_empty() and route.get("ok", true) and route.get("errors", []).is_empty():
		return true
	errors.append("seed %d: %sbuild failed: errors=%s failure=%s" % [
		seed_value, label, str(route.get("errors", [])), str(route.get("failure", {})),
	])
	return false


func _validate_structure_and_placement(route: Dictionary, issues: PackedStringArray) -> void:
	Verify.validate_structure(route, issues)
	Verify.validate_seams(route, issues)
	Verify.validate_clearance(route, route.terrain, issues)
	Verify.validate_self_clearance(route, issues)


func _terrain_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for seed_value in [1, 7, 20260809]:
		var first := _terrain_for_seed(seed_value)
		var repeat := _terrain_for_seed(seed_value)
		if first != repeat:
			errors.append("terrain params are not deterministic for seed %d" % seed_value)
			continue
		var relief_reached := 0.0
		for index in 400:
			var x := float((index * 631) % 4001) - 2000.0
			var z := float((index * 269) % 4001) - 2000.0
			var height: float = Terrain.height(first, x, z)
			if height != Terrain.height(repeat, x, z) or not is_finite(height):
				errors.append("terrain heights are not deterministic for seed %d" % seed_value)
				break
			relief_reached = maxf(relief_reached, height)
		if relief_reached < first.relief * 0.95:
			errors.append("seed %d terrain never reaches its plateau relief" % seed_value)
	return errors


func _verify_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if absf(Verify.limit_at(Verify.POSITIVE_LIMIT, 0.5) - 8.0) > 0.001:
		errors.append("+Gz brief limit is not 8.0")
	if absf(Verify.limit_at(Verify.POSITIVE_LIMIT, 3.0) - 5.333) > 0.001:
		errors.append("+Gz 2-4 s plateau is not 5.333")
	if absf(Verify.limit_at(Verify.POSITIVE_LIMIT, 8.0) - 4.0) > 0.001:
		errors.append("+Gz 5-11.8 s plateau is not 4.0")
	if absf(Verify.limit_at(Verify.POSITIVE_LIMIT, 100.0) - 1.333) > 0.001:
		errors.append("+Gz long-duration tail is not 1.333")
	if absf(Verify.limit_at(Verify.LONGITUDINAL_NEGATIVE_LIMIT, 0.4) - 6.0) > 0.001:
		errors.append("-Gx brief limit is not 6.0")
	var constant := PackedFloat32Array()
	constant.resize(400)
	constant.fill(2.0)
	var filtered_constant: PackedFloat32Array = Verify.filter(constant)
	if absf(filtered_constant[-1] - 2.0) > 0.001:
		errors.append("Butterworth DC gain is not unity")
	var pulse := PackedFloat32Array()
	pulse.resize(1000)
	pulse.fill(1.0)
	for index in range(300, 700):
		pulse[index] = 5.0
	var usage: Dictionary = Verify.envelope_usage(pulse, Verify.POSITIVE_LIMIT, 1.0)
	if absf(usage.usage - 5.0 / 5.333) > 0.02 or usage.duration < 2.0 or usage.duration > 4.0:
		errors.append("held-curve usage misreads a 4 s pulse")
	var push_pull := PackedFloat32Array()
	push_pull.resize(700)
	push_pull.fill(1.0)
	for index in 400:
		push_pull[index] = -1.0
	for index in range(400, 500):
		push_pull[index] = 7.0
	if Verify.push_pull_violations(push_pull) != 1:
		errors.append("push-pull misses a 7.0 g peak after 4 s of -Gz")
	for index in range(400, 500):
		push_pull[index] = 6.0
	if Verify.push_pull_violations(push_pull) != 0:
		errors.append("push-pull flags a compliant 6.0 g peak")
	var reversal := PackedFloat32Array()
	reversal.resize(300)
	for index in 50:
		reversal[index] = 4.5
	for index in range(60, 110):
		reversal[index] = -2.0
	if Verify.reversal_violations(reversal, 8.0, 3.0) != 1:
		errors.append("reversal rule misses a 0.1 s opposite-sign pair")
	var spaced := PackedFloat32Array()
	spaced.resize(300)
	for index in 50:
		spaced[index] = 4.5
	for index in range(100, 150):
		spaced[index] = -2.0
	if Verify.reversal_violations(spaced, 8.0, 3.0) != 0:
		errors.append("reversal rule flags a 0.5 s-separated pair")
	if Verify.combined_usage(PackedFloat32Array([7.0]), PackedFloat32Array([3.5]),
			PackedFloat32Array([0.0])) <= 1.0:
		errors.append("pairwise ellipse accepts Gz 7.0 with Gy 3.5")
	if Verify.combined_usage(PackedFloat32Array([6.0]), PackedFloat32Array([3.0]),
			PackedFloat32Array([0.0])) > 1.0:
		errors.append("pairwise ellipse rejects Gz 6.0 with Gy 3.0")
	var ramp := PackedFloat32Array()
	ramp.resize(120)
	for index in 120:
		ramp[index] = clampf(index * 0.25, 0.0, 5.0)
	if absf(Verify.peak_onset(ramp) - 25.0) > 0.5:
		errors.append("least-squares onset misreads a 25 g/s ramp")
	return errors


func _terrain_for_seed(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return Terrain.generate(rng)
