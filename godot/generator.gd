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
	var layout := _layout(terrain, rng)
	var initial_state := _initial_state(layout)
	var compiled := _compile(seed_value, config, terrain, layout, initial_state)
	if not compiled.get("ok", false):
		return _failure("ride program compilation failed", compiled.get("errors", []))
	var settings: Variant = compiled.get("settings")
	if not settings is Dictionary:
		return _failure("ride program omitted integration settings")
	settings = settings.duplicate(true)
	settings["step_s"] = INTEGRATION_STEP_S
	var accepted_integrations := 0
	var trajectory := Motion.integrate(initial_state, compiled.get("spans", []), settings)
	if not trajectory.get("ok", false):
		return _failure("motion integration failed", trajectory.get("errors", []))
	accepted_integrations += 1
	var accepted: Dictionary = compiled.duplicate(true)
	accepted["generation_stats"] = {
		"accepted_integrations": accepted_integrations,
		"repair_count": 0,
	}
	var route := RouteContract.build(seed_value, terrain, initial_state, accepted, trajectory)
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
	terrain: Dictionary,
	layout: Dictionary,
	initial_state: Dictionary
) -> Dictionary:
	return RideProgram.compile(seed_value, config, terrain, layout, initial_state)


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
	var approach_length := 140.0
	return {
		"terrain_frame": {"inward": inward, "along": along},
		"station_position_m": station_position,
		"station_tangent": tangent,
		"station_up": Vector3.UP,
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


static func _failure(context: String, details: Variant = []) -> Dictionary:
	var errors := PackedStringArray([context])
	if details is Array or details is PackedStringArray:
		for detail in details:
			errors.append(str(detail))
	return {"ok": false, "errors": errors}
