extends SceneTree

const Coaster := preload("res://main.gd")
const Model := preload("res://ride_model.gd")

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
