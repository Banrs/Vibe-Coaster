extends SceneTree

const Coaster := preload("res://main.gd")
const Model := preload("res://ride_model.gd")
const Terrain := preload("res://terrain.gd")
const Verify := preload("res://verify.gd")

const DETERMINISTIC_FIELDS := [
	"positions", "tangents", "ups", "rights", "curvatures", "banks", "speeds",
	"normal_g", "lateral_g", "longitudinal_g", "roll_rates", "distances", "times",
	"section_indices", "lsm_ids",
]
const SECTION_FIELDS := [
	"name", "kind", "length", "lsm", "start_index", "end_index", "start_distance",
	"end_distance", "start_time", "end_time", "start_height", "end_height", "entry_speed",
	"exit_speed",
]


func _initialize() -> void:
	var started := Time.get_ticks_msec()
	var route: Dictionary = Model.build()
	var repeat: Dictionary = Model.build()
	var errors: PackedStringArray = Model.validate(route)
	for error in Coaster.validate_route(route):
		if not errors.has(error):
			errors.append(error)
	if not _same_route(route, repeat):
		errors.append("route generation is not deterministic")
	errors.append_array(_terrain_errors())
	errors.append_array(_verify_errors())
	var rails: ArrayMesh = Coaster.build_rail_mesh(route)
	var terrain: ArrayMesh = Coaster.build_terrain_mesh(route)
	var elapsed := Time.get_ticks_msec() - started
	if rails.get_surface_count() != 1 or rails.surface_get_array_len(0) < 30_000:
		errors.append("rail mesh is empty or incomplete")
	if terrain.get_surface_count() != 1:
		errors.append("terrain mesh is empty")
	if floori(route.length / Coaster.TIE_SPACING) < 1000:
		errors.append("track has too few visual speed cues")
	if elapsed > 10_000:
		errors.append("two model builds and meshes took %d ms" % elapsed)
	print(
		"route: %.1f m, %.1f s, %d samples, %.1f km/h top, %.1f km/h average, %d ms"
		% [
			route.length,
			route.duration,
			route.positions.size(),
			route.analysis.top_speed * 3.6,
			route.analysis.average_speed * 3.6,
			elapsed,
		]
	)
	for error in errors:
		printerr(error)
	quit(0 if errors.is_empty() else 1)


func _terrain_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for seed_value in [1, 7, 20260809]:
		var first := _terrain_for_seed(seed_value)
		var repeat := _terrain_for_seed(seed_value)
		if first != repeat:
			errors.append("terrain params are not deterministic for seed %d" % seed_value)
			continue
		var relief_reached := 0.0
		for i in 400:
			var x := float((i * 631) % 4001) - 2000.0
			var z := float((i * 269) % 4001) - 2000.0
			var h: float = Terrain.height(first, x, z)
			var h_repeat: float = Terrain.height(repeat, x, z)
			if h != h_repeat or not is_finite(h):
				errors.append("terrain heights are not deterministic for seed %d" % seed_value)
				break
			relief_reached = maxf(relief_reached, h)
		if relief_reached < first.relief * 0.95:
			errors.append("seed %d terrain never reaches its plateau relief" % seed_value)
		if absf(Terrain.height(first, 0.0, 0.0) - Terrain.height(repeat, 0.0, 0.0)) > 0.0:
			errors.append("terrain origin height differs between identical seeds")
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
	for i in range(300, 700):
		pulse[i] = 5.0
	var usage: Dictionary = Verify.envelope_usage(pulse, Verify.POSITIVE_LIMIT, 1.0)
	if absf(usage.usage - 5.0 / 5.333) > 0.02 or usage.duration < 2.0 or usage.duration > 4.0:
		errors.append("held-curve usage misreads a 4 s pulse (usage %.3f at %.2f s)" % [usage.usage, usage.duration])
	var push_pull := PackedFloat32Array()
	push_pull.resize(700)
	push_pull.fill(1.0)
	for i in 400:
		push_pull[i] = -1.0
	for i in range(400, 500):
		push_pull[i] = 7.0
	if Verify.push_pull_violations(push_pull) != 1:
		errors.append("push-pull misses a 7.0 g peak after 4 s of -Gz")
	for i in range(400, 500):
		push_pull[i] = 6.0
	if Verify.push_pull_violations(push_pull) != 0:
		errors.append("push-pull flags a compliant 6.0 g peak")
	var reversal := PackedFloat32Array()
	reversal.resize(300)
	for i in 50:
		reversal[i] = 4.5
	for i in range(60, 110):
		reversal[i] = -2.0
	if Verify.reversal_violations(reversal, 8.0, 3.0) != 1:
		errors.append("reversal rule misses a 0.1 s opposite-sign pair")
	var spaced := PackedFloat32Array()
	spaced.resize(300)
	for i in 50:
		spaced[i] = 4.5
	for i in range(100, 150):
		spaced[i] = -2.0
	if Verify.reversal_violations(spaced, 8.0, 3.0) != 0:
		errors.append("reversal rule flags a 0.5 s-separated pair")
	var normal_series := PackedFloat32Array([7.0])
	var lateral_series := PackedFloat32Array([3.5])
	var longitudinal_series := PackedFloat32Array([0.0])
	if Verify.combined_usage(normal_series, lateral_series, longitudinal_series) <= 1.0:
		errors.append("pairwise ellipse accepts Gz 7.0 with Gy 3.5")
	if Verify.combined_usage(PackedFloat32Array([6.0]), PackedFloat32Array([3.0]), PackedFloat32Array([0.0])) > 1.0:
		errors.append("pairwise ellipse rejects Gz 6.0 with Gy 3.0")
	var ramp := PackedFloat32Array()
	ramp.resize(120)
	for i in 120:
		ramp[i] = clampf(i * 0.25, 0.0, 5.0)
	if absf(Verify.peak_onset(ramp) - 25.0) > 0.5:
		errors.append("least-squares onset misreads a 25 g/s ramp (%.2f)" % Verify.peak_onset(ramp))
	return errors


func _terrain_for_seed(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return Terrain.generate(rng)


func _same_route(first: Dictionary, second: Dictionary) -> bool:
	if first.length != second.length or first.duration != second.duration:
		return false
	for field in DETERMINISTIC_FIELDS:
		if first[field] != second[field]:
			return false
	if first.sections.size() != second.sections.size():
		return false
	for i in first.sections.size():
		for field in SECTION_FIELDS:
			if first.sections[i][field] != second.sections[i][field]:
				return false
	return first.analysis == second.analysis
