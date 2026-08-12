class_name RideGenerator
extends RefCounted

## Atomic time-domain generator facade. Planning owns the deterministic terrain and station
## corridor; RideProgram owns every flown control; Motion performs the sole accepted integration;
## RouteContract is the sole public-route conversion.

const Motion := preload("res://motion.gd")
const RideProgram := preload("res://ride_program.gd")
const RouteContract := preload("res://route_contract.gd")
const Terrain := preload("res://terrain.gd")

const CONFIG_VERSION := 1
const PRESET_ID := "future-hybrid@1"
const STATION_SPEED_MPS := 6.0
const STATION_HEIGHT_M := 20.0
const INTEGRATION_STEP_S := 0.01


static func build(seed_value: int) -> Dictionary:
	var config := build_config(seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var terrain: Dictionary = Terrain.generate(rng)
	var world_layout := _layout(terrain, rng)
	var local_layout := _canonical_layout(world_layout)
	var local_initial_state := _initial_state(local_layout)
	var compiled := _compile(seed_value, config, local_layout, local_initial_state)
	if not compiled.get("ok", false):
		return _failure("ride program compilation failed", compiled.get("errors", []))
	var settings: Variant = compiled.get("settings")
	if not settings is Dictionary:
		return _failure("ride program omitted integration settings")
	settings = settings.duplicate(true)
	settings["step_s"] = INTEGRATION_STEP_S
	var accepted_integrations := 0
	var trajectory := Motion.integrate(local_initial_state, compiled.get("spans", []), settings)
	if not trajectory.get("ok", false):
		return _failure("motion integration failed", trajectory.get("errors", []))
	accepted_integrations += 1
	_place_trajectory(trajectory, world_layout)
	var accepted: Dictionary = compiled.duplicate(true)
	var terminal_contract: Dictionary = accepted.terminal_contract
	terminal_contract.station_position_m = world_layout.station_position_m
	terminal_contract.station_tangent = world_layout.station_tangent
	terminal_contract.station_up = world_layout.station_up
	accepted.terminal_contract = terminal_contract
	accepted["generation_stats"] = {
		"accepted_integrations": accepted_integrations,
		"repair_count": 0,
	}
	var route := RouteContract.build(
		seed_value, terrain, _initial_state(world_layout), accepted, trajectory)
	if not route.get("ok", false):
		return _failure("route contract rejected trajectory", route.get("errors", []))
	return route


static func build_config(seed_value: int) -> Dictionary:
	return {
		"ride_config_version": CONFIG_VERSION,
		"preset": PRESET_ID,
		"seed": seed_value,
		"sequence": {"pinned": {}},
		"constraints": {"required": [], "preferred": []},
	}


## Kept as the only compile seam while the bounded station-capture solver is upgraded.
static func _compile(
	seed_value: int,
	config: Dictionary,
	layout: Dictionary,
	initial_state: Dictionary
) -> Dictionary:
	return RideProgram.compile(seed_value, config, layout, initial_state)


static func _layout(terrain: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var inward: Vector2 = terrain.edge_normal.normalized()
	var along := Vector2(-inward.y, inward.x)
	if rng.randf() < 0.5:
		along = -along
	var station_s := -rng.randf_range(780.0, 880.0)
	var station_a := -rng.randf_range(60.0, 120.0)
	var station_2d: Vector2 = (
		inward * (station_s + float(terrain.edge_offset)) + along * station_a
	)
	var station_position := Vector3(station_2d.x, STATION_HEIGHT_M, station_2d.y)
	var tangent := Vector3(along.x, 0.0, along.y).normalized()
	var approach := RideProgram.station_approach_envelope()
	var approach_length: float = approach.minimum_length_m
	return {
		"terrain_frame": {"inward": inward, "along": along},
		"station_position_m": station_position,
		"station_tangent": tangent,
		"station_up": Vector3.UP,
		"capture_half_width_m": approach.half_width_m,
		"capture_half_height_m": approach.half_height_m,
		"reserved_corridor": {
			"approach_start_m": station_position - tangent * approach_length,
			"station_position_m": station_position,
			"station_tangent": tangent,
			"minimum_length_m": approach_length,
		},
	}


static func _initial_state(layout: Dictionary) -> Dictionary:
	return {
		"position_m": layout.station_position_m,
		"tangent": layout.station_tangent,
		"rider_up": layout.station_up,
		"speed_mps": STATION_SPEED_MPS,
		"distance_m": 0.0,
		"time_s": 0.0,
	}


## Integrate in a canonical station frame so closure does not depend on world-coordinate
## roundoff, then apply the ride's single rigid world placement to the accepted trajectory.
static func _canonical_layout(world_layout: Dictionary) -> Dictionary:
	var layout := world_layout.duplicate(true)
	layout.station_position_m = Vector3.ZERO
	layout.station_tangent = Vector3.RIGHT
	layout.station_up = Vector3.UP
	var corridor: Dictionary = layout.reserved_corridor
	corridor.approach_start_m = -Vector3.RIGHT * float(corridor.minimum_length_m)
	corridor.station_position_m = Vector3.ZERO
	corridor.station_tangent = Vector3.RIGHT
	layout.reserved_corridor = corridor
	return layout


static func _place_trajectory(trajectory: Dictionary, layout: Dictionary) -> void:
	var forward: Vector3 = layout.station_tangent.normalized()
	var station_up: Vector3 = layout.station_up
	var up: Vector3 = station_up - forward * station_up.dot(forward)
	up = up.normalized()
	var right := forward.cross(up).normalized()
	var origin: Vector3 = layout.station_position_m
	var positions: PackedVector3Array = trajectory.position_m
	var tangents: PackedVector3Array = trajectory.tangent
	var rider_ups: PackedVector3Array = trajectory.rider_up
	var curvatures: PackedVector3Array = trajectory.curvature_vector_m_inv
	for index in positions.size():
		positions[index] = origin + _place_vector(positions[index], forward, up, right)
		tangents[index] = _place_vector(tangents[index], forward, up, right)
		rider_ups[index] = _place_vector(rider_ups[index], forward, up, right)
		curvatures[index] = _place_vector(curvatures[index], forward, up, right)
	trajectory.position_m = positions
	trajectory.tangent = tangents
	trajectory.rider_up = rider_ups
	trajectory.curvature_vector_m_inv = curvatures
	var dense_output: Dictionary = trajectory.dense_output
	dense_output["measurement_frame"] = "canonical-station-before-rigid-placement"
	trajectory.dense_output = dense_output


static func _place_vector(
	local_vector: Vector3, forward: Vector3, up: Vector3, right: Vector3
) -> Vector3:
	return forward * local_vector.x + up * local_vector.y + right * local_vector.z


static func _failure(context: String, details: Variant = []) -> Dictionary:
	var errors := PackedStringArray([context])
	if details is Array or details is PackedStringArray:
		for detail in details:
			errors.append(str(detail))
	return {"ok": false, "errors": errors}
