extends SceneTree

const RideGenerator := preload("res://generator.gd")
const RideReturnSolve := preload("res://ride_return_solve.gd")


func _initialize() -> void:
	var route := RideGenerator.build(42)
	var failure: Dictionary = route.get("failure", {})
	var residuals: Array = failure.get("target_error", [])
	var mapped := {}
	for index in mini(residuals.size(), RideReturnSolve.RETURN_RESIDUAL_IDS.size()):
		mapped[RideReturnSolve.RETURN_RESIDUAL_IDS[index]] = residuals[index]
	print("planar camelback return failure: ", JSON.stringify({
		"ok": route.get("ok", false),
		"errors": Array(route.get("errors", PackedStringArray())),
		"stage": failure.get("stage"),
		"reason": failure.get("reason"),
		"solver_status": failure.get("solver_status"),
		"evaluation_count": failure.get("evaluation_count"),
		"accepted_values": failure.get("accepted_values", []),
		"scaled_target_error": mapped,
	}))
	quit(0)
