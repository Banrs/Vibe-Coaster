extends Camera3D
## Free-fly camera: hold right mouse to look, WASD moves, Q/E down/up,
## Shift is fast.

var looking := false


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		looking = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and looking:
		rotate_y(-event.relative.x * 0.003)
		rotate_object_local(Vector3.RIGHT, -event.relative.y * 0.003)


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
		var speed := 400.0 if Input.is_key_pressed(KEY_SHIFT) else 80.0
		global_position += direction.normalized() * speed * delta
