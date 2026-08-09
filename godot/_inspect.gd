extends SceneTree

## Inspection harness (not part of the ride or the smoke gate): dumps per-element geometry
## stats and phase tables, and renders PNGs — element side views, top/elevation, and 6-channel
## ride traces (speed/normal g/lateral g/pitch/roll rate/AGL) — for visual comparison against
## the measured references in docs/TELEMETRY.md.
## Run: godot --headless --path godot --script res://_inspect.gd  [output dir via INSPECT_OUT]

const Generator := preload("res://generator.gd")
const Terrain := preload("res://terrain.gd")

var OUT: String = OS.get_environment("INSPECT_OUT") if OS.get_environment("INSPECT_OUT") != "" else OS.get_user_data_dir() + "/inspect"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	for seed_value in [11, 20260809]:
		var extra: Dictionary = Generator.build(seed_value)
		_render_channels(extra, "%s/channels_%d.png" % [OUT, seed_value])
	var route: Dictionary = Generator.build(42)
	_render_channels(route, "%s/channels_42.png" % OUT)
	_print_phases(route)
	var groups := _element_groups(route)
	for g in groups:
		var kind: String = g.kind
		var a: int = g.first
		var b: int = g.last
		var stats := _stats(route, a, b)
		print("ELEM %-14s len %6.0f m  v %5.1f->%5.1f  pitch [%6.1f, %6.1f]  bank max %5.1f  nG [%5.2f, %5.2f]  W %5.0f H %5.0f  Rapex %5.0f Rvalley %5.0f" % [
			kind, route.distances[b] - route.distances[a], route.speeds[a], route.speeds[b],
			stats.min_pitch, stats.max_pitch, stats.max_bank, stats.min_n, stats.max_n,
			stats.width, stats.height, stats.r_apex, stats.r_valley,
		])
		if kind in ["hill", "immelmann", "loop", "cutback", "twisted_drop", "dive", "wave_turn", "overbank", "turn"]:
			_render_side(route, a, b, "%s/%s_%d.png" % [OUT, kind, a])
	_render_top(route, "%s/top.png" % OUT)
	_render_elevation(route, "%s/elevation.png" % OUT)
	quit(0)


func _element_groups(route: Dictionary) -> Array:
	var groups := []
	var current := {}
	for i in route.sections.size():
		var section: Dictionary = route.sections[i]
		var element: Dictionary = section.get("element", {})
		var kind: String = element.get("kind", section.get("kind", "?"))
		if section.get("kind") == "GRADE" or section.get("kind") == "CLOSURE":
			kind = section.name
		if current.get("element_id") == element.get("kind", "") + str(element.get("rise", element.get("apex_height", element.get("height", i)))):
			current.last = section.end_index
			continue
		current = {
			"kind": kind,
			"first": section.start_index,
			"last": section.end_index,
			"element_id": element.get("kind", "") + str(element.get("rise", element.get("apex_height", element.get("height", i)))),
		}
		groups.append(current)
	return groups


func _stats(route: Dictionary, a: int, b: int) -> Dictionary:
	var min_pitch := INF
	var max_pitch := -INF
	var max_bank := 0.0
	var min_n := INF
	var max_n := -INF
	var top := -INF
	var bottom := INF
	var apex := a
	var valley := a
	for i in range(a, b + 1):
		var pitch := rad_to_deg(asin(clampf(route.tangents[i].y, -1.0, 1.0)))
		min_pitch = minf(min_pitch, pitch)
		max_pitch = maxf(max_pitch, pitch)
		max_bank = maxf(max_bank, absf(route.banks[i]))
		min_n = minf(min_n, route.normal_g[i])
		max_n = maxf(max_n, route.normal_g[i])
		if route.positions[i].y > top:
			top = route.positions[i].y
			apex = i
		if route.positions[i].y < bottom:
			bottom = route.positions[i].y
			valley = i
	var width: float = Vector2(route.positions[b].x - route.positions[a].x, route.positions[b].z - route.positions[a].z).length()
	return {
		"min_pitch": min_pitch, "max_pitch": max_pitch, "max_bank": max_bank,
		"min_n": min_n, "max_n": max_n, "width": width, "height": top - bottom,
		"r_apex": 1.0 / maxf(route.curvatures[apex].length(), 0.0001),
		"r_valley": 1.0 / maxf(route.curvatures[valley].length(), 0.0001),
	}


func _render_side(route: Dictionary, a: int, b: int, path: String) -> void:
	var direction := Vector2.ZERO
	for i in range(a, b + 1):
		direction += Vector2(route.positions[i].x - route.positions[a].x, route.positions[i].z - route.positions[a].z)
	if direction.length() < 1.0:
		direction = Vector2(route.tangents[a].x, route.tangents[a].z)
	direction = direction.normalized()
	var points := PackedVector2Array()
	for i in range(a, b + 1):
		var p: Vector3 = route.positions[i]
		points.append(Vector2(Vector2(p.x - route.positions[a].x, p.z - route.positions[a].z).dot(direction), p.y))
	_plot(points, path)


func _render_top(route: Dictionary, path: String) -> void:
	var points := PackedVector2Array()
	for i in route.positions.size():
		points.append(Vector2(route.positions[i].x, route.positions[i].z))
	_plot(points, path)


func _render_elevation(route: Dictionary, path: String) -> void:
	var points := PackedVector2Array()
	for i in route.positions.size():
		points.append(Vector2(route.distances[i], route.positions[i].y))
	_plot(points, path)


## Stacked strips against ride time: speed km/h · normal g · lateral g · pitch° · roll°/s ·
## height AGL. Section boundaries ticked. This is the "ride it yourself" trace.
func _render_channels(route: Dictionary, path: String) -> void:
	var count: int = route.positions.size()
	var channels := [
		{"label": "speed", "values": PackedFloat32Array()},
		{"label": "normal g", "values": PackedFloat32Array()},
		{"label": "lateral g", "values": PackedFloat32Array()},
		{"label": "pitch", "values": PackedFloat32Array()},
		{"label": "roll rate", "values": PackedFloat32Array()},
		{"label": "AGL", "values": PackedFloat32Array()},
	]
	for i in count:
		channels[0].values.append(route.speeds[i] * 3.6)
		channels[1].values.append(route.normal_g[i])
		channels[2].values.append(route.lateral_g[i])
		channels[3].values.append(rad_to_deg(asin(clampf(route.tangents[i].y, -1.0, 1.0))))
		channels[4].values.append(route.roll_rates[i])
		channels[5].values.append(route.positions[i].y - Terrain.height(route.terrain, route.positions[i].x, route.positions[i].z))
	var marks := PackedFloat32Array()
	for section in route.sections:
		marks.append(section.start_time)
	const W := 1400
	const STRIP := 150
	var image := Image.create(W, STRIP * channels.size(), false, Image.FORMAT_RGB8)
	image.fill(Color(0.09, 0.10, 0.12))
	var t_max: float = route.times[-1]
	for c in channels.size():
		var values: PackedFloat32Array = channels[c].values
		var low := INF
		var high := -INF
		for v in values:
			low = minf(low, v)
			high = maxf(high, v)
		var span := maxf(high - low, 0.001)
		var y0 := c * STRIP
		for x in W:
			image.set_pixel(x, y0, Color(0.25, 0.25, 0.30))
		if low < 0.0 and high > 0.0:
			var zero_y := y0 + STRIP - 8 - int((0.0 - low) / span * (STRIP - 16))
			for x in range(0, W, 2):
				image.set_pixel(x, zero_y, Color(0.28, 0.24, 0.24))
		for mark in marks:
			var mx := clampi(int(mark / t_max * (W - 1)), 0, W - 1)
			for y in range(y0, y0 + STRIP, 4):
				image.set_pixel(mx, y, Color(0.30, 0.27, 0.20))
		for i in range(1, values.size()):
			var x0 := int(route.times[i - 1] / t_max * (W - 1))
			var x1 := int(route.times[i] / t_max * (W - 1))
			var py0 := y0 + STRIP - 8 - int((values[i - 1] - low) / span * (STRIP - 16))
			var py1 := y0 + STRIP - 8 - int((values[i] - low) / span * (STRIP - 16))
			var steps := maxi(absi(x1 - x0) + absi(py1 - py0), 1)
			for s in steps + 1:
				var x := clampi(roundi(lerpf(x0, x1, float(s) / steps)), 0, W - 1)
				var y := clampi(roundi(lerpf(py0, py1, float(s) / steps)), y0 + 1, y0 + STRIP - 1)
				image.set_pixel(x, y, Color(0.55, 0.95, 1.0))
		print("CHANNEL %-10s [%8.2f, %8.2f]" % [channels[c].label, low, high])
	image.save_png(path)


func _print_phases(route: Dictionary) -> void:
	for section in route.sections:
		var element: Dictionary = section.get("element", {})
		print("PHASE %-24s %-13s %6.0f m %6.1f s  v %5.1f -> %5.1f m/s" % [
			section.name, element.get("kind", section.kind),
			section.end_distance - section.start_distance,
			section.end_time - section.start_time,
			section.entry_speed, section.exit_speed,
		])


func _plot(points: PackedVector2Array, path: String, marks: PackedFloat32Array = PackedFloat32Array()) -> void:
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for p in points:
		low = low.min(p)
		high = high.max(p)
	var span: Vector2 = (high - low).max(Vector2(1, 1))
	const W := 1100
	const H := 700
	const M := 40.0
	var scale: float = minf((W - 2.0 * M) / span.x, (H - 2.0 * M) / span.y)
	var image := Image.create(W, H, false, Image.FORMAT_RGB8)
	image.fill(Color(0.09, 0.10, 0.12))
	for mark in marks:
		var mx := clampi(int((mark - low.x) * scale + M), 0, W - 1)
		for y in range(0, H, 3):
			image.set_pixel(mx, y, Color(0.35, 0.30, 0.20))
	for i in range(1, points.size()):
		var p0: Vector2 = (points[i - 1] - low) * scale
		var p1: Vector2 = (points[i] - low) * scale
		var steps := maxi(ceili(p0.distance_to(p1)), 1)
		for s in steps + 1:
			var q: Vector2 = p0.lerp(p1, float(s) / steps)
			var x := clampi(int(q.x + M), 1, W - 2)
			var y := clampi(H - 1 - int(q.y + M), 1, H - 2)
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					image.set_pixel(x + dx, y + dy, Color(0.55, 0.95, 1.0))
	image.save_png(path)
