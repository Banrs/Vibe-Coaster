extends SceneTree

const Coaster := preload("res://main.gd")
const FidelityTests := preload("res://fidelity_tests.gd")
const FidelityArtifactTests := preload("res://fidelity_artifact_tests.gd")
const Generator := preload("res://generator.gd")
const RouteContract := preload("res://route_contract.gd")
const Terrain := preload("res://terrain.gd")
const Verify := preload("res://verify.gd")

const DEEP_SEEDS := [11, 42, 20260809]
const LAUNCH_DRIVE_BAND_G := Vector2(3.7, 4.1)
const SWEEP_SEEDS := [1, 3, 7, 99, 256, 555, 1234, 4096, 31337, 77777, 123456, 20250101]
## The fleet must not be one ride fifteen times. Measured spread on 2026-08-16 with the landed
## draw set, the closed-form placement, the rim-aimed dive and the eight-control return: 49.22 m
## of route length and 0.515 s of elapsed time across the fifteen seeds, so these floors sit at
## roughly a tenth of the length spread and a fifth of the duration spread the planner actually
## produces.
const FLEET_LENGTH_SPREAD_FLOOR_M := 5.0
const FLEET_DURATION_SPREAD_FLOOR_S := 0.1
## The fleet half of the return budget claim. `ride_program.gd` derives the cap and
## `ride_program_tests.gd` gates five seeds fast; every seed of the fifteen must stay inside
## this fraction of it, measured here because the compile is already paid.
const RETURN_EVALUATION_ALLOWANCE := 0.6
## The prefix-closure margins the whole fleet must carry, and the fraction of the closure's own
## derived cap it must converge inside — all four margins and the allowance are `generator.gd`'s
## constants, read here rather than copied, since the closure aims at the same numbers. This is the
## fifteen-seed half of the prefix convergence claim `ride_program_tests.gd` makes on the canonical
## and seed-42 stories. The closure aims inside every margin and the closed-form placement lands
## inside them by construction; measuring them on all fifteen seeds is what turns the aim into a
## gate. Measured on the grid-search placement this replaced: four seeds missed the dive-entry
## margin, nine the apron margin, and seven sat exactly on the summit band's floor. Read the summit
## margin as one-sided: `generator.gd` floors the station at the inner band's 17.99 m (the 40%
## interior of the 15.01-24.95 band) and every other clearance term can only raise it, so the low
## side carries 2.98 m by construction and only the high side can ever approach this gate. The
## fleet's tightest summit margin (+2.96 m, seed 77777) is therefore high-side evidence alone, not
## a two-sided measurement of the 1.5 m floor. The dive-entry margin reads the other way round
## since the rim aim landed: it is the *low* side that binds now (+4.30 m worst, seed 1234), which
## is the measurement of issue 22 — the dive starts at the rim end of its band on every seed.
## The viewer's POV camera bounds. Measured on seed 42 (2026-08-15): the camera stays within
## 6.3° of the tangent, the look direction stays 84.5° clear of the pose up axis, and the rumble
## moves the eye 4.41 mm between 60 fps frames at top speed. The cone and clearance are the
## limits the camera has to respect rather than the numbers it happens to hit; the shake bound
## sits at 1.8× the measurement, tight enough to catch a return to above-Nyquist frequencies.
const VIEWER_POV_TANGENT_CONE_DEG := 40.0
const VIEWER_POV_UP_CLEARANCE_DEG := 30.0
const VIEWER_POV_SHAKE_PER_FRAME_M := 0.008

var _fleet_lengths := PackedFloat64Array()
var _fleet_durations := PackedFloat64Array()


func _initialize() -> void:
	var errors := PackedStringArray()
	errors.append_array(FidelityTests.run())
	errors.append_array(FidelityArtifactTests.run())
	errors.append_array(_terrain_errors())
	errors.append_array(_verify_errors())
	for seed_value in DEEP_SEEDS:
		errors.append_array(_deep_seed_errors(seed_value))
	errors.append_array(_sweep_errors())
	errors.append_array(_diversity_errors())
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
	_validate_structure_and_placement(route, seed_value, issues)
	var analysis: Dictionary = Verify.analyze(route, RouteContract.ROW_OFFSETS)
	Verify.validate_loads(analysis, issues)
	_validate_record_launch_numbers(route, analysis, issues)
	for issue in issues:
		errors.append("seed %d: %s" % [seed_value, issue])
	_fleet_lengths.append(route.length)
	_fleet_durations.append(route.duration)
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
			_fleet_lengths.append(route.length)
			_fleet_durations.append(route.duration)
			var issues := PackedStringArray()
			_validate_structure_and_placement(route, seed_value, issues)
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


## Seeds must produce different rides, not one ride fifteen times. Determinism is checked
## per seed above; this is the companion check that nothing else asserted before the planner
## decision layer landed — a build that collapses back to a single ride fails here.
func _diversity_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if _fleet_lengths.size() < DEEP_SEEDS.size() + SWEEP_SEEDS.size():
		errors.append("the diversity gate saw only %d of %d accepted fleet rides" % [
			_fleet_lengths.size(), DEEP_SEEDS.size() + SWEEP_SEEDS.size()])
		return errors
	var lengths := _fleet_lengths.duplicate()
	var durations := _fleet_durations.duplicate()
	lengths.sort()
	durations.sort()
	var length_spread: float = lengths[-1] - lengths[0]
	var duration_spread: float = durations[-1] - durations[0]
	if length_spread < FLEET_LENGTH_SPREAD_FLOOR_M:
		errors.append("fleet route lengths span only %.2f m; required more than %.2f m"
			% [length_spread, FLEET_LENGTH_SPREAD_FLOOR_M])
	if duration_spread < FLEET_DURATION_SPREAD_FLOOR_S:
		errors.append("fleet ride durations span only %.3f s; required more than %.3f s"
			% [duration_spread, FLEET_DURATION_SPREAD_FLOOR_S])
	print("fleet diversity: %d rides, lengths span %.2f m, durations span %.3f s"
		% [lengths.size(), length_spread, duration_spread])
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
	errors.append_array(_hud_element_errors(route))
	errors.append_array(_pov_camera_errors(route, analysis))
	return errors


## The HUD's current→next element lookup, swept over the whole lap. The viewer runs it once per
## frame; nothing else would notice it going empty, naming the current element as the next one,
## or drifting out of story order.
func _hud_element_errors(route: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var story := PackedStringArray()
	for gesture: Dictionary in route.gesture_windows:
		for role: Dictionary in gesture.get("role_windows", []):
			story.append(str(role.get("display_name", role.get("id", ""))))
	var seen := PackedStringArray()
	for sample in route.positions.size():
		var names: PackedStringArray = Coaster.next_element_names(route, sample)
		if names[1].is_empty():
			errors.append("viewer HUD: sample %d has no next element" % sample)
			break
		if names[0] == names[1]:
			errors.append(
				"viewer HUD: sample %d names %s as both current and next" % [sample, names[0]])
			break
		if seen.is_empty() or seen[-1] != names[0]:
			seen.append(names[0])
	if errors.is_empty() and Array(seen) != Array(story):
		errors.append("viewer HUD: element sequence %s is not the story order %s" % [
			str(seen), str(story)])
	if errors.is_empty():
		print("seed 42 viewer HUD: %d elements named in story order" % seen.size())
	return errors


## The POV camera, swept over the whole lap. The camera must keep pointing down the track, must
## never let the look direction fall onto the pose up axis (where `Basis.looking_at` is
## undefined), and its rumble must stay rumble — a per-frame displacement at 60 fps and top
## speed measured in millimetres, not the strobe an above-Nyquist shake produces.
func _pov_camera_errors(route: Dictionary, analysis: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var top_speed: float = analysis.top_speed
	var worst_tangent_deg := 0.0
	var closest_up_deg := 180.0
	var distance := 0.0
	while distance < route.length:
		var sample: int = Coaster._lower_index(route.distances, distance)
		var pose := Coaster.pose_at_distance(route, distance)
		var camera: Transform3D = Coaster.pov_transform(
			route, distance, route.speeds[sample], top_speed, 0.0)
		var forward := -camera.basis.z
		var tangent_deg := rad_to_deg(
			acos(clampf(forward.dot(route.tangents[sample]), -1.0, 1.0)))
		var up_deg := rad_to_deg(acos(clampf(forward.dot(pose.basis.y), -1.0, 1.0)))
		worst_tangent_deg = maxf(worst_tangent_deg, tangent_deg)
		closest_up_deg = minf(closest_up_deg, minf(up_deg, 180.0 - up_deg))
		distance += 5.0
	var worst_jitter_m := 0.0
	for step in 600:
		var phase := step / 300.0
		var held := Coaster.pov_transform(route, 1000.0, top_speed, top_speed, phase)
		var next_frame := Coaster.pov_transform(
			route, 1000.0, top_speed, top_speed, phase + 1.0 / 60.0)
		worst_jitter_m = maxf(worst_jitter_m, held.origin.distance_to(next_frame.origin))
	if worst_tangent_deg > VIEWER_POV_TANGENT_CONE_DEG:
		errors.append("viewer POV: camera strays %.1f° from the tangent" % worst_tangent_deg)
	if closest_up_deg < VIEWER_POV_UP_CLEARANCE_DEG:
		errors.append("viewer POV: look direction comes %.1f° from the pose up axis"
			% closest_up_deg)
	if worst_jitter_m > VIEWER_POV_SHAKE_PER_FRAME_M:
		errors.append("viewer POV: shake moves the eye %.1f mm per 60 fps frame"
			% (worst_jitter_m * 1000.0))
	print(
		"seed 42 viewer POV: %.1f° off tangent, %.1f° clear of up, %.2f mm/frame shake"
		% [worst_tangent_deg, closest_up_deg, worst_jitter_m * 1000.0]
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


## The record-launch numbers derived on 2026-08-15: the tunnel LSM3 must reach the
## 338-344 km/h record band, and the entry launch must peak at its 3.9 g class.
func _validate_record_launch_numbers(
	route: Dictionary, analysis: Dictionary, issues: PackedStringArray
) -> void:
	var top_speed := float(analysis.top_speed)
	var band: Vector2 = Generator.RECORD_EXIT_SPEED_BAND_MPS
	if top_speed < band.x or top_speed > band.y:
		issues.append("top speed %.2f m/s is outside the record band %.1f-%.1f m/s" % [
			top_speed, band.x, band.y])
	var launch := {}
	for window in route.get("gesture_windows", []):
		if window.get("story_slot_id", "") == "station-launch":
			launch = window
			break
	if launch.is_empty():
		issues.append("station-launch window is missing")
		return
	var peak_drive := 0.0
	for index in range(int(launch.first), int(launch.last) + 1):
		peak_drive = maxf(peak_drive, float(route.drive_g[index]))
	if peak_drive < LAUNCH_DRIVE_BAND_G.x or peak_drive > LAUNCH_DRIVE_BAND_G.y:
		issues.append("station-launch peak authored drive %.3f g is outside %.1f-%.1f g" % [
			peak_drive, LAUNCH_DRIVE_BAND_G.x, LAUNCH_DRIVE_BAND_G.y])


func _validate_structure_and_placement(
	route: Dictionary, seed_value: int, issues: PackedStringArray
) -> void:
	Verify.validate_structure(route, issues)
	Verify.validate_seams(route, issues)
	Verify.validate_clearance(route, route.terrain, issues)
	Verify.validate_self_clearance(route, issues)
	var gate: Dictionary = route.get("terrain_story_plan", {}).get("return_entry_gate", {})
	var evaluations := int(gate.get("solve_evaluations", -1))
	var allowance := int(RETURN_EVALUATION_ALLOWANCE * int(gate.get("solve_evaluation_cap", 0)))
	if evaluations < 1 or evaluations > allowance:
		issues.append("the return solve spent %d evaluations against a %d fleet allowance"
			% [evaluations, allowance])
	_validate_prefix_closure(route, seed_value, issues)


## The prefix closure, measured on the built ride: the four margins of design section 6 and the
## solve's own evaluation count. Every quantity here is one the closure aimed at or the placement
## derived, so a miss means the aim did not survive the ride it produced — never a reason to widen
## a band. Printed per seed because the closure's cost is a budget claim, not a hope.
func _validate_prefix_closure(
	route: Dictionary, seed_value: int, issues: PackedStringArray
) -> void:
	var planning: Dictionary = route.get("terrain_story_plan", {}).get("planning", {})
	var terrain: Dictionary = route.get("terrain", {})
	var closure: Dictionary = planning.get("closure", {})
	var fine: Array = closure.get("fine_observation", [])
	if terrain.is_empty() or fine.size() != 4:
		issues.append("the plan publishes no measurable prefix closure")
		return
	var shelf_m := float(terrain.apron_width) + float(terrain.face_width)
	var measured := [
		["dive-entry edge", float(planning.get("dive_entry_edge_m", NAN)) - shelf_m,
			Generator.DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M, Generator.DIVE_ENTRY_EDGE_MARGIN_M],
		["dive-exit apron fraction", float(planning.get("dive_exit_apron_fraction", NAN)),
			Generator.DIVE_EXIT_APRON_BAND, Generator.DIVE_EXIT_APRON_MARGIN],
		["summit track AGL", float(planning.get("summit_track_agl_m", NAN)),
			Generator.SUMMIT_TRACK_AGL_BAND_M, Generator.PREFIX_MARGIN_SUMMIT_M],
		["record exit speed", float(fine[3]), Generator.RECORD_EXIT_SPEED_BAND_MPS,
			Generator.PREFIX_MARGIN_RECORD_MPS],
	]
	var report := PackedStringArray()
	for entry: Array in measured:
		var band: Vector2 = entry[2]
		var margin := minf(float(entry[1]) - band.x, band.y - float(entry[1]))
		report.append("%s %+.4f" % [entry[0], margin])
		if not is_finite(margin) or margin < float(entry[3]):
			issues.append("%s sits only %.4f inside %s; the fleet requires %.4f"
				% [entry[0], margin, str(band), float(entry[3])])
	var evaluations := int(closure.get("unique_evaluations", -1))
	var allowance := int(
		Generator.PREFIX_EVALUATION_ALLOWANCE * int(closure.get("max_unique_evaluations", 0)))
	if evaluations < 1 or evaluations > allowance \
			or str(closure.get("solver_status", "")) != "converged":
		issues.append("the prefix closure spent %d %s evaluations against a %d fleet allowance"
			% [evaluations, str(closure.get("solver_status", "missing")), allowance])
	print("seed %d prefix closure: %d of %d evaluations, margins %s"
		% [seed_value, evaluations, allowance, ", ".join(report)])


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
