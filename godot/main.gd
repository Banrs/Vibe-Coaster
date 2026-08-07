extends Node3D
## The rideable checkpoint: generate in-engine, then ride what came out.
## All scene construction lives here; the extension hands over arrays only.

const BASE_FOV := 75.0
const TRAIN_SIZE := Vector3(3.0, 2.2, 12.0)

var times: PackedFloat32Array
var positions: PackedVector3Array
var tangents: PackedVector3Array
var ups: PackedVector3Array
var speeds: PackedFloat32Array
var dists: PackedFloat32Array
var gn: PackedFloat32Array
var gl: PackedFloat32Array
var gx: PackedFloat32Array
var element_index: PackedInt32Array
var element_names: PackedStringArray
var element_top: PackedFloat32Array
var element_bottom: PackedFloat32Array
var duration := 0.0
var total_length := 0.0
var max_speed := 0.0
var base_y := 0.0
var span := 0.0
var t := 0.0
var riding := false
var generator: RideGenerator

@onready var cameras: Array[Camera3D] = [$PovCamera, $ChaseCamera, $FlyCamera]


func _ready() -> void:
	$Sun.rotation_degrees = Vector3(-55, 30, 0)
	$UI/GenerateButton.pressed.connect(_on_generate)
	var box := BoxMesh.new()
	box.size = TRAIN_SIZE
	box.material = _material(Color(0.15, 0.15, 0.2))
	$Train.mesh = box
	$Train.visible = false


func _on_generate() -> void:
	# The solve runs a minute or more. The extension carries it on a Rust
	# thread — engine calls stay on this one — and poll() collects it.
	$UI/Status.text = "solving… (takes a minute or two)"
	$UI/GenerateButton.disabled = true
	generator = RideGenerator.new()
	generator.start()


func _apply(ride: Dictionary) -> void:
	positions = ride.positions
	tangents = ride.tangents
	ups = ride.ups
	times = ride.times
	speeds = ride.speeds
	dists = ride.dists
	total_length = ride.length
	gn = ride.gn
	gl = ride.gl
	gx = ride.gx
	element_index = ride.element_index
	element_names = ride.element_names
	element_top = ride.element_top
	element_bottom = ride.element_bottom
	duration = ride.duration
	max_speed = 0.0
	for v in speeds:
		max_speed = maxf(max_speed, v)
	var top_y := -INF
	base_y = INF
	for p in positions:
		base_y = minf(base_y, p.y)
		top_y = maxf(top_y, p.y)
	span = top_y - base_y
	_build_track()
	_build_terrain(ride.terrain_vertices, ride.terrain_nx, ride.terrain_ny)
	$UI/Status.text = "%s — %s   [C] cycles camera" % [ride.note, ride.stats]
	$UI/GenerateButton.disabled = false
	$Train.visible = true
	t = 0.0
	riding = true


func _process(delta: float) -> void:
	if generator:
		var ride: Dictionary = generator.poll()
		if not ride.is_empty():
			generator = null
			_apply(ride)
	if not riding:
		return
	t = fmod(t + delta, duration)
	var i := clampi(times.bsearch(t), 1, times.size() - 1)
	var f := inverse_lerp(times[i - 1], times[i], t)
	var pos := positions[i - 1].lerp(positions[i], f)
	var tangent := tangents[i - 1].lerp(tangents[i], f).normalized()
	var up := ups[i - 1].lerp(ups[i], f).normalized()
	var right := tangent.cross(up).normalized()
	up = right.cross(tangent)
	var speed := lerpf(speeds[i - 1], speeds[i], f)

	$Train.global_transform = Transform3D(Basis(right, up, -tangent), pos)
	var e := element_index[i]
	$UI/Debug.text = (
		"element  %s\n" % element_names[e]
		+ "speed    %.0f km/h  (avg %.0f, max %.0f)\n"
		% [speed * 3.6, total_length / duration * 3.6, max_speed * 3.6]
		+ "g        n %+.2f   lat %+.2f   long %+.2f\n"
		% [lerpf(gn[i - 1], gn[i], f), lerpf(gl[i - 1], gl[i], f), lerpf(gx[i - 1], gx[i], f)]
		+ "pitch    %+.1f deg\n" % rad_to_deg(asin(clampf(tangent.y, -1.0, 1.0)))
		+ "distance %.0f / %.0f m\n" % [lerpf(dists[i - 1], dists[i], f), total_length]
		+ "height   %.0f m up  (element spans %.0f m, ride spans %.0f m)"
		% [pos.y - base_y, element_top[e] - element_bottom[e], span]
	)
	# Seat just ahead of the train box, so the box reads as the car in front.
	$PovCamera.global_transform = Transform3D(
		Basis(right, up, -tangent), pos + tangent * (TRAIN_SIZE.z * 0.5 + 1.0)
	)
	$PovCamera.fov = BASE_FOV + clampf(speed, 0.0, 110.0) * 0.25
	var chase_target := pos - tangent * 30.0 + Vector3.UP * 10.0
	$ChaseCamera.global_position = $ChaseCamera.global_position.lerp(
		chase_target, 1.0 - exp(-5.0 * delta)
	)
	$ChaseCamera.look_at(pos, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		var next := (cameras.find(get_viewport().get_camera_3d()) + 1) % cameras.size()
		if cameras[next] == $FlyCamera:
			$FlyCamera.global_transform = get_viewport().get_camera_3d().global_transform
		cameras[next].current = true


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _build_track() -> void:
	var rail := SurfaceTool.new()
	rail.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	rail.set_material(_material(Color(0.85, 0.2, 0.1)))
	var ties := SurfaceTool.new()
	ties.begin(Mesh.PRIMITIVE_TRIANGLES)
	ties.set_material(_material(Color(0.25, 0.12, 0.08)))
	for i in positions.size():
		var right := tangents[i].cross(ups[i]).normalized()
		rail.set_normal(ups[i])
		rail.add_vertex(positions[i] - right * 1.5)
		rail.set_normal(ups[i])
		rail.add_vertex(positions[i] + right * 1.5)
		# A crosstie per sample: the near-field cue that makes speed read.
		var c := positions[i] - ups[i] * 0.35
		var a := tangents[i] * 0.35
		var b := right * 2.2
		for v in [c - a - b, c - a + b, c + a - b, c - a + b, c + a + b, c + a - b]:
			ties.set_normal(ups[i])
			ties.add_vertex(v)
	$Track.mesh = rail.commit()
	$Ties.mesh = ties.commit()


func _build_terrain(vertices: PackedVector3Array, nx: int, ny: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_material(Color(0.45, 0.5, 0.35)))
	var base := INF
	for j in ny - 1:
		for i in nx - 1:
			var a := j * nx + i
			for k in [a, a + 1, a + nx, a + 1, a + nx + 1, a + nx]:
				st.add_vertex(vertices[k])
				base = minf(base, vertices[k].y)
	st.generate_normals()
	$Terrain.mesh = st.commit()

	# A wide ground plane under everything, so there is always a floor.
	var plane := PlaneMesh.new()
	plane.size = Vector2(40000, 40000)
	plane.material = _material(Color(0.55, 0.5, 0.38))
	$Ground.mesh = plane
	$Ground.global_position = Vector3(0, base - 1.0, 0)
