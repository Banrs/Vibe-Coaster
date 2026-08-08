extends Camera3D

var looking := false
var yaw := 0.0
var pitch := 0.0


func adopt(source: Transform3D) -> void:
	global_transform = source
	yaw = rotation.y
	pitch = rotation.x


func release_look() -> void:
	looking = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and looking:
		yaw -= event.relative.x * 0.003
		pitch = clampf(pitch - event.relative.y * 0.003, -1.5, 1.5)
		rotation = Vector3(pitch, yaw, 0)


func _process(delta: float) -> void:
	if not current:
		return
	var direction := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		direction -= transform.basis.z
	if Input.is_key_pressed(KEY_S):
		direction += transform.basis.z
	if Input.is_key_pressed(KEY_A):
		direction -= transform.basis.x
	if Input.is_key_pressed(KEY_D):
		direction += transform.basis.x
	if Input.is_key_pressed(KEY_Q):
		direction -= Vector3.UP
	if Input.is_key_pressed(KEY_E):
		direction += Vector3.UP
	if direction != Vector3.ZERO:
		var speed := 260.0 if Input.is_key_pressed(KEY_SHIFT) else 70.0
		global_position += direction.normalized() * speed * delta
