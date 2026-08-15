extends Node3D

const RAIL_DROP := 1.05
const RAIL_GAUGE := 1.90
const TIE_SPACING := 4.0
const SUPPORT_SPACING := 32.0
const TUNNEL_SPACING := 12.0
const DEFAULT_SEED := 42
const ROW_OFFSETS := RouteContract.ROW_OFFSETS
const CAMERA_NAMES := ["POV", "Chase", "Overview", "Fly"]

var route: Dictionary
var analysis: Dictionary
var seed_picker := RandomNumberGenerator.new()
var ride_time := 0.0
var ride_top_speed := 0.0
var ride_peak_g := 0.0
var playback_rate := 1.0
var selected_row := 0
var camera_index := 0
var paused := false
var train_rows: MultiMesh
var build_thread: Thread
var cameras: Array[Camera3D]
var overview_center := Vector3.ZERO
var overview_radius := 1200.0

@onready var metrics: Label = $UI/Margin/Panel/Content/Metrics
@onready var row_picker: OptionButton = $UI/Margin/Panel/Content/Selectors/Row
@onready var rate_picker: OptionButton = $UI/Margin/Panel/Content/Selectors/Rate
@onready var controls: Label = $UI/Margin/Panel/Content/Controls


func _ready() -> void:
	_configure_world()
	_populate_controls()
	cameras = [$PovCamera, $ChaseCamera, $OverviewCamera, $FlyCamera]
	_set_camera(0)
	_rebuild(DEFAULT_SEED)


## One seed is one ride: generation runs on a worker thread (build and analyze are pure
## statics), and the world is rebuilt on the main thread when it lands.
func _rebuild(seed_value: int) -> void:
	if build_thread != null:
		return
	_clear_world()
	route = {}
	train_rows = null
	metrics.text = "Generating seed %d…" % seed_value
	build_thread = Thread.new()
	build_thread.start(func() -> void:
		var built := RideGenerator.build(seed_value)
		_finish_rebuild.call_deferred(built, RideVerify.analyze(built, ROW_OFFSETS)))


func _finish_rebuild(built: Dictionary, built_analysis: Dictionary) -> void:
	build_thread.wait_to_finish()
	build_thread = null
	route = built
	analysis = built_analysis
	ride_time = 0.0
	ride_top_speed = 0.0
	ride_peak_g = 0.0
	var errors := validate_route(route, analysis)
	if not errors.is_empty():
		metrics.text = "ROUTE INVALID\n" + "\n".join(errors)
		for error in errors:
			push_error(error)
		return
	_build_world()
	_update_ride(0.0)


func _exit_tree() -> void:
	if build_thread != null:
		build_thread.wait_to_finish()
		build_thread = null


func terrain_height(x: float, z: float) -> float:
	return RideTerrain.height(route.terrain, x, z)


static func validate_route(built: Dictionary, built_analysis: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	RideVerify.validate_structure(built, errors)
	RideVerify.validate_seams(built, errors)
	RideVerify.validate_clearance(built, built.terrain, errors)
	RideVerify.validate_self_clearance(built, errors)
	RideVerify.validate_loads(built_analysis, errors)
	if ROW_OFFSETS.size() != 7:
		errors.append("viewer requires seven selectable rows")
	return errors


static func build_rail_mesh(built: Dictionary) -> ArrayMesh:
	var positions: PackedVector3Array = built.positions
	var rights: PackedVector3Array = built.rights
	var ups: PackedVector3Array = built.ups
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var tubes := [Vector3(-RAIL_GAUGE * 0.5, -RAIL_DROP, 0.14), Vector3(RAIL_GAUGE * 0.5, -RAIL_DROP, 0.14), Vector3(0, -1.55, 0.24)]
	const SIDES := 8
	for tube in tubes:
		var base := vertices.size()
		for i in positions.size():
			for side in SIDES:
				var angle := TAU * side / SIDES
				var radial := rights[i] * cos(angle) + ups[i] * sin(angle)
				vertices.append(positions[i] + rights[i] * tube.x + ups[i] * tube.y + radial * tube.z)
				normals.append(radial)
		for i in positions.size() - 1:
			for side in SIDES:
				var next_side := (side + 1) % SIDES
				var a := base + i * SIDES + side
				var b := base + (i + 1) * SIDES + side
				var c := base + (i + 1) * SIDES + next_side
				var d := base + i * SIDES + next_side
				indices.append_array(PackedInt32Array([a, b, c, a, c, d]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func build_terrain_mesh(built: Dictionary) -> ArrayMesh:
	const STEP := 22.5
	var terrain: Dictionary = built.terrain
	var bounds: AABB = built.bounds.grow(260.0)
	var nx := ceili(bounds.size.x / STEP) + 1
	var nz := ceili(bounds.size.z / STEP) + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for z_index in nz:
		for x_index in nx:
			var x: float = bounds.position.x + x_index * STEP
			var z: float = bounds.position.z + z_index * STEP
			var height: float = RideTerrain.height(terrain, x, z)
			vertices.append(Vector3(x, height, z))
			var dx: float = RideTerrain.height(terrain, x + 1.0, z) - RideTerrain.height(terrain, x - 1.0, z)
			var dz: float = RideTerrain.height(terrain, x, z + 1.0) - RideTerrain.height(terrain, x, z - 1.0)
			normals.append(Vector3(-dx * 0.5, 1.0, -dz * 0.5).normalized())
			colors.append(Color("c7833f").lerp(Color("765038"), clampf(height / terrain.relief, 0, 1)))
	for z_index in nz - 1:
		for x_index in nx - 1:
			var a := z_index * nx + x_index
			indices.append_array(PackedInt32Array([a, a + nx, a + 1, a + 1, a + nx, a + nx + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func pose_at_distance(built: Dictionary, distance: float) -> Transform3D:
	return RouteSampling.pose_at_distance(built, distance)


static func distance_at_time(built: Dictionary, time: float) -> float:
	return RouteSampling.distance_at_time(built, time)


static func _lower_index(values: PackedFloat32Array, value: float) -> int:
	return RouteSampling.lower_index(values, value)


func _configure_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("5799c4")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b9ccd5")
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.fog_enabled = false
	$World.environment = environment
	$Sun.rotation_degrees = Vector3(-48, -28, 0)
	$Sun.light_color = Color("ffe0b0")
	$Sun.light_energy = 0.78
	$Sun.shadow_enabled = true


func _populate_controls() -> void:
	for row in ROW_OFFSETS.size():
		row_picker.add_item("Row %d%s" % [row + 1, " · Front" if row == 0 else (" · Back" if row == 6 else "")])
	for label in ["0.5×", "1×", "2×", "4×"]:
		rate_picker.add_item(label)
	rate_picker.select(1)
	row_picker.item_selected.connect(_on_row_selected)
	rate_picker.item_selected.connect(_on_rate_selected)
	controls.text += "   ·   N seed"


## Everything _build_world made, dropped before the next seed builds its own.
func _clear_world() -> void:
	train_rows = null
	$Terrain.mesh = null
	$Track/Rails.mesh = null
	for node in [$Track/Ties, $Track/Supports, $Track/LSM1, $Track/LSM2, $Track/LSM3, $Train]:
		node.multimesh = null
	for parent in [$Scenery/Station, $Scenery/Tunnel]:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()


func _build_world() -> void:
	overview_center = route.bounds.get_center()
	overview_center.y = 95.0
	overview_radius = maxf(route.bounds.size.x, route.bounds.size.z) * 0.55
	$Terrain.mesh = build_terrain_mesh(route)
	$Terrain.material_override = _material(Color.WHITE, 0.0, 0.95, true)
	$Track/Rails.mesh = build_rail_mesh(route)
	$Track/Rails.material_override = _material(Color("e7dfcf"), 0.35, 0.48)
	_build_ties()
	_build_supports()
	_build_launches()
	_build_train()
	_build_scenery()


func _build_ties() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.65, 0.12, 0.24)
	mesh.material = _material(Color("858e92"), 0.55, 0.42)
	var count := floori(route.length / TIE_SPACING)
	var multimesh := _new_multimesh(mesh, count)
	for i in count:
		var pose := pose_at_distance(route, i * TIE_SPACING)
		pose.origin -= pose.basis.y * 1.18
		multimesh.set_instance_transform(i, pose)
	$Track/Ties.multimesh = multimesh


func _build_supports() -> void:
	var transforms: Array[Transform3D] = []
	var count := floori(route.length / SUPPORT_SPACING)
	for i in count:
		var pose := pose_at_distance(route, i * SUPPORT_SPACING)
		var up := pose.basis.y
		var tangent := -pose.basis.z
		if absf(tangent.y) > 0.72:
			continue
		var rail := pose.origin - up * 1.45
		var ground := terrain_height(rail.x, rail.z)
		var height := rail.y - ground
		if height < 4.0:
			continue
		var spread := clampf(2.0 + height * 0.055, 2.5, 10.0)
		for side in [-1.0, 1.0]:
			var side_factor := float(side)
			var top: Vector3 = rail + pose.basis.x * side_factor * 0.70
			var foot_xz: Vector3 = rail + pose.basis.x * side_factor * spread
			var bottom := Vector3(foot_xz.x, terrain_height(foot_xz.x, foot_xz.z), foot_xz.z)
			transforms.append(_between(bottom, top))
	var mesh := CylinderMesh.new()
	mesh.height = 1.0
	mesh.top_radius = 0.22
	mesh.bottom_radius = 0.34
	mesh.radial_segments = 8
	mesh.rings = 1
	mesh.material = _material(Color("9c978b"), 0.35, 0.58)
	var multimesh := _new_multimesh(mesh, transforms.size())
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	$Track/Supports.multimesh = multimesh


func _build_launches() -> void:
	var material := _material(Color("29d9ff"), 0.65, 0.24)
	material.emission_enabled = true
	material.emission = Color("1589c7")
	material.emission_energy_multiplier = 1.6
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.52, 0.12, 0.85)
	mesh.material = material
	for launch in range(1, 4):
		var poses: Array[Transform3D] = []
		var distance := 0.0
		while distance < route.length:
			var index := _lower_index(route.distances, distance)
			if route.propulsion_ids[index] == launch:
				var pose := pose_at_distance(route, distance)
				pose.origin -= pose.basis.y * 0.94
				poses.append(pose)
			distance += 3.0
		var multimesh := _new_multimesh(mesh, poses.size())
		for i in poses.size():
			multimesh.set_instance_transform(i, poses[i])
		get_node("Track/LSM%d" % launch).multimesh = multimesh


func _build_train() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.30, 0.82, 1.75)
	mesh.material = _material(Color("173b72"), 0.7, 0.25)
	train_rows = _new_multimesh(mesh, ROW_OFFSETS.size())
	$Train.multimesh = train_rows
	$Train.layers = 2


func _build_scenery() -> void:
	var station := $Scenery/Station
	var forward: Vector3 = route.tangents[0]
	forward.y = 0.0
	forward = forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD
	var right := forward.cross(Vector3.UP).normalized()
	var station_basis := Basis(right, Vector3.UP, -forward)
	var center: Vector3 = route.positions[0] + station_basis * Vector3(0, -2.7, -21.0)
	_add_box(station, Vector3(4.0, 0.6, 64.0), center + station_basis * Vector3(-4.0, 0, 0), Color("b6a98f"), station_basis)
	_add_box(station, Vector3(4.0, 0.6, 64.0), center + station_basis * Vector3(4.0, 0, 0), Color("b6a98f"), station_basis)
	_add_box(station, Vector3(14.0, 0.5, 60.0), center + station_basis * Vector3(0, 9.2, 0), Color("e9e4d8"), station_basis)
	for z_offset in [-27.0, 0.0, 27.0]:
		for x_offset in [-6.0, 6.0]:
			_add_box(station, Vector3(0.55, 9.0, 0.55), center + station_basis * Vector3(x_offset, 4.5, z_offset), Color("d8d1c4"), station_basis)
	_build_tunnel()


## Crude rock boxes following the track frame through the authored tunnel ranges.
func _build_tunnel() -> void:
	var rock := Color("5c4638")
	for sample_range: Vector2i in route.tunnel_ranges:
		var start: int = sample_range.x
		var end: int = sample_range.y
		var spacing: float = route.distances[start + 1] - route.distances[start]
		var step := maxi(1, roundi(TUNNEL_SPACING / maxf(spacing, 0.1)))
		var i := start
		while i < end:
			var next := mini(i + step, end)
			var a: Vector3 = route.positions[i]
			var b: Vector3 = route.positions[next]
			var length := a.distance_to(b)
			var up: Vector3 = route.ups[i]
			var right: Vector3 = route.rights[i]
			var box_basis := Basis(right, up, -route.tangents[i])
			var middle := a.lerp(b, 0.5)
			_add_box($Scenery/Tunnel, Vector3(0.7, 6.2, length), middle - right * 3.25 + up, rock, box_basis)
			_add_box($Scenery/Tunnel, Vector3(0.7, 6.2, length), middle + right * 3.25 + up, rock, box_basis)
			_add_box($Scenery/Tunnel, Vector3(7.2, 0.7, length), middle + up * 4.0, rock, box_basis)
			i = next


func _process(delta: float) -> void:
	if route.is_empty() or train_rows == null:
		return
	if not paused:
		var advanced := fposmod(ride_time + delta * playback_rate, route.duration)
		if advanced < ride_time:
			ride_top_speed = 0.0
			ride_peak_g = 0.0
		ride_time = advanced
	_update_ride(delta)


func _update_ride(delta: float) -> void:
	var front_distance := distance_at_time(route, ride_time)
	var front_pose := pose_at_distance(route, front_distance)
	var front_sample := _lower_index(route.distances, front_distance)
	var speed: float = route.speeds[front_sample]
	for row in ROW_OFFSETS.size():
		var pose := pose_at_distance(route, front_distance - ROW_OFFSETS[row])
		pose.origin -= pose.basis.y * 0.30
		train_rows.set_instance_transform(row, pose)
	var row_distance: float = front_distance - ROW_OFFSETS[selected_row]
	var row_pose := pose_at_distance(route, row_distance)
	var row_sample := _lower_index(route.distances, fposmod(row_distance, float(route.length)))
	var force: Dictionary = RideVerify.row_forces_at(
		route, front_distance, speed, ROW_OFFSETS[selected_row]
	)
	var speed_t := clampf(speed / analysis.top_speed, 0.0, 1.0)
	var eye_origin := row_pose.origin + row_pose.basis.y * 0.35
	# Gentle look-ahead: ease the view toward the track ~0.6 s out so drops read before they hit.
	var ahead := pose_at_distance(route, row_distance + clampf(speed * 0.6, 8.0, 45.0))
	var look := ahead.origin - eye_origin
	var pov_basis := row_pose.basis
	if look.length_squared() > 1.0:
		pov_basis = pov_basis.slerp(Basis.looking_at(look.normalized(), row_pose.basis.y), 0.22)
	# Subtle deterministic speed shake — incommensurate sines, quadratic in speed, sub-4 cm.
	var shake_amp := 0.035 * speed_t * speed_t
	var shake := row_pose.basis.x * (sin(ride_time * 149.0) * 0.6 + sin(ride_time * 233.0) * 0.4) \
		* shake_amp \
		+ row_pose.basis.y * (sin(ride_time * 179.0) * 0.6 + sin(ride_time * 283.0) * 0.4) \
		* shake_amp * 0.7
	$PovCamera.global_transform = Transform3D(pov_basis, eye_origin + shake)
	$PovCamera.fov = lerpf(74.0, 102.0, pow(speed_t, 1.5))
	var chase_target := front_pose.origin + front_pose.basis.z * 24.0 + Vector3.UP * 10.0
	$ChaseCamera.global_position = chase_target if delta <= 0.0 else $ChaseCamera.global_position.lerp(
		chase_target, 1.0 - exp(-4.0 * delta)
	)
	$ChaseCamera.look_at(front_pose.origin, Vector3.UP)
	var angle := ride_time * 0.018
	$OverviewCamera.global_position = overview_center + Vector3(
		cos(angle) * overview_radius,
		maxf(500.0, overview_radius * 0.48),
		sin(angle) * overview_radius
	)
	$OverviewCamera.look_at(overview_center, Vector3.UP)
	var gesture: Dictionary = route.gesture_windows[route.gesture_indices[row_sample]]
	var role_name := str(gesture.get("diagnostic_kind", ""))
	var next_name := ""
	for role: Dictionary in gesture.get("role_windows", []):
		if row_sample >= int(role.first) and row_sample <= int(role.last):
			role_name = str(role.get("display_name", role.get("id", role_name)))
		elif int(role.first) > row_sample and next_name.is_empty():
			next_name = str(role.get("display_name", role.get("id", "")))
	if next_name.is_empty():
		var following: Dictionary = route.gesture_windows[
			(route.gesture_indices[row_sample] + 1) % route.gesture_windows.size()]
		var next_roles: Array = following.get("role_windows", [])
		next_name = str(next_roles[0].get("display_name", next_roles[0].get("id", ""))) \
			if not next_roles.is_empty() \
			else str(following.get("display_name", following.get("story_slot_id", "")))
	var altitude := row_pose.origin.y - terrain_height(row_pose.origin.x, row_pose.origin.z)
	ride_top_speed = maxf(ride_top_speed, speed)
	ride_peak_g = maxf(ride_peak_g, force.normal)
	metrics.text = (
		"Seed %d  ·  %s  ·  %s → %s\n" % [route.seed,
			gesture.get("display_name", gesture.story_slot_id), role_name, next_name]
		+ "%.0f km/h  ·  %.0f m AGL  ·  Row %d  ·  %s / %s  ·  %.1f / %.1f km\n"
		% [speed * 3.6, altitude, selected_row + 1, _clock(ride_time), _clock(route.duration),
			front_distance / 1000.0, route.length / 1000.0]
		+ "Gz %+.2f  ·  lat %.2f %s  ·  %.2f %s\n"
		% [force.normal, absf(force.lateral), "R" if force.lateral >= 0.0 else "L",
			absf(force.longitudinal), "accel" if force.longitudinal >= 0.0 else "brake"]
		+ "so far: peak Gz %+.2f  ·  top %.0f km/h  ·  %s%s"
		% [ride_peak_g, ride_top_speed * 3.6, CAMERA_NAMES[camera_index],
			"  ·  PAUSED" if paused else ""]
	)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_C:
			_set_camera((camera_index + 1) % cameras.size())
		KEY_SPACE:
			paused = not paused
		KEY_R:
			ride_time = 0.0
			ride_top_speed = 0.0
			ride_peak_g = 0.0
		KEY_N:
			_rebuild(seed_picker.randi_range(1, 1_000_000_000))
		KEY_BRACKETLEFT:
			_set_rate(maxf(0.5, playback_rate * 0.5))
		KEY_BRACKETRIGHT:
			_set_rate(minf(4.0, playback_rate * 2.0))
		_:
			if event.keycode >= KEY_1 and event.keycode <= KEY_7:
				selected_row = event.keycode - KEY_1
				row_picker.select(selected_row)


func _set_camera(index: int) -> void:
	var previous := get_viewport().get_camera_3d()
	camera_index = index
	if previous == $FlyCamera and cameras[index] != $FlyCamera:
		$FlyCamera.release_look()
	if cameras[index] == $FlyCamera and previous:
		$FlyCamera.adopt(previous.global_transform)
	cameras[index].make_current()


func _on_row_selected(index: int) -> void:
	selected_row = index


func _on_rate_selected(index: int) -> void:
	_set_rate([0.5, 1.0, 2.0, 4.0][index])


func _set_rate(rate: float) -> void:
	playback_rate = rate
	var rates := [0.5, 1.0, 2.0, 4.0]
	rate_picker.select(rates.find(rate))


static func _clock(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


func _new_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = count
	multimesh.custom_aabb = route.bounds.grow(300.0)
	return multimesh


func _between(start: Vector3, end: Vector3) -> Transform3D:
	var y := end - start
	var y_axis := y.normalized()
	var x_axis := y_axis.cross(Vector3.FORWARD)
	if x_axis.length_squared() < 0.001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	return Transform3D(Basis(x_axis, y_axis * y.length(), z_axis), start.lerp(end, 0.5))


func _add_box(
	parent: Node3D,
	size: Vector3,
	location: Vector3,
	color: Color,
	orientation: Basis = Basis.IDENTITY
) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(color, 0.1, 0.75)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.transform = Transform3D(orientation, location)
	parent.add_child(instance)


func _material(
	color: Color, metallic: float = 0.0, roughness: float = 0.65, vertex_color: bool = false
) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = vertex_color
	return material
