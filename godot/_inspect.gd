extends SceneTree

## Inspection harness (not part of the ride or the smoke gate): dumps per-element geometry
## stats and phase tables, and renders PNGs — element side views, top/elevation, and the stacked
## ride-channel traces — for visual comparison against the measured references in
## docs/TELEMETRY.md. Every render lives in RideFidelityArtifacts, which the audit pack shares.
## Run: godot --headless --path godot --script res://_inspect.gd  [output dir via INSPECT_OUT]

const Generator := preload("res://generator.gd")
const Artifacts := preload("res://fidelity_artifacts.gd")

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
			Artifacts.side_image(route, a, b).save_png("%s/%s_%d.png" % [OUT, kind, a])
	Artifacts.top_image(route).save_png("%s/top.png" % OUT)
	Artifacts.elevation_image(route).save_png("%s/elevation.png" % OUT)
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


## Stacked strips against ride time — the "ride it yourself" trace, now eleven channels deep.
func _render_channels(route: Dictionary, path: String) -> void:
	var rendered: Dictionary = Artifacts.channels(route)
	rendered.image.save_png(path)
	for strip in rendered.strips:
		print("CHANNEL %-30s [%10.3f, %10.3f] %4d bounded %4d unbounded" % [
			strip.channel_id, strip.plot_min, strip.plot_max,
			strip.bounded_count, strip.unbounded_count,
		])


func _print_phases(route: Dictionary) -> void:
	for section in route.sections:
		var element: Dictionary = section.get("element", {})
		print("PHASE %-24s %-13s %6.0f m %6.1f s  v %5.1f -> %5.1f m/s" % [
			section.name, element.get("kind", section.kind),
			section.end_distance - section.start_distance,
			section.end_time - section.start_time,
			section.entry_speed, section.exit_speed,
		])
