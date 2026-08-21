extends SceneTree

## Temporary CI-only diagnostic. It deliberately fails after emitting every candidate result so
## Task 2 can collect a ruling before any solver change is retained.

const RideGenerator := preload("res://generator.gd")
const RidePlanner := preload("res://ride_planner.gd")
const RideProgram := preload("res://ride_program.gd")
const Terrain := preload("res://terrain.gd")

const NORMALIZED_DIFFERENCE_STEPS := [0.005, 0.0025, 0.001]
const SMOKE_FLEET := [11, 42, 20260809, 1, 3, 7, 99, 256, 555, 1234, 4096, 31337,
	77777, 123456, 20250101]


func _initialize() -> void:
	for normalized_difference_step in NORMALIZED_DIFFERENCE_STEPS:
		for seed_value in SMOKE_FLEET:
			var diagnostics := {}
			var compiled := _compile_optional_swap(
				seed_value, float(normalized_difference_step), diagnostics)
			print("SOLVER_EVIDENCE " + JSON.stringify({
				"normalized_difference_step": normalized_difference_step,
				"seed": seed_value,
				"compile_ok": compiled.get("ok", false),
				"failure": compiled.get("failure", {}),
				"return_solver": diagnostics,
			}))
	assert(false, "SOLVER_EVIDENCE_COMPLETE: deliberate Task 2 evidence failure")
	quit(1)


func _compile_optional_swap(
	seed_value: int, normalized_difference_step: float, diagnostics: Dictionary
) -> Dictionary:
	var decisions := RidePlanner.resolve(seed_value)
	decisions["sequence"] = _act_one_optional_swap()
	var terrain: Dictionary = Terrain.generate(decisions.streams[RidePlanner.STREAM_TERRAIN])
	var plan: Dictionary = RideGenerator._plan(terrain, decisions)
	if plan.has("ok") and not plan.ok:
		return {"ok": false, "failure": {"stage": "planning", "errors": plan.get("errors", [])}}
	return RideProgram.compile(plan, RideGenerator._initial_state(plan.station),
		normalized_difference_step, diagnostics)


func _act_one_optional_swap() -> Array:
	var pool: Array = RidePlanner.ACT_ONE_POOL.duplicate()
	var first_index := pool.find(str(RidePlanner.ACT_ONE_OPTIONAL[0]))
	var second_index := pool.find(str(RidePlanner.ACT_ONE_OPTIONAL[1]))
	var first: Variant = pool[first_index]
	pool[first_index] = pool[second_index]
	pool[second_index] = first
	var sequence: Array = []
	sequence.append_array(RidePlanner.SPINE_OPENER)
	sequence.append(RidePlanner.ACT_ONE_ANCHOR)
	sequence.append_array(pool)
	sequence.append_array(RidePlanner.SPINE_TAIL)
	sequence.append_array(RidePlanner.RETURN_CELL)
	sequence.append_array(RidePlanner.SPINE_CLOSE)
	return sequence
