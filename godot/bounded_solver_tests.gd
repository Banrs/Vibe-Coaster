extends SceneTree

const BoundedSolver := preload("res://bounded_solver.gd")

var _errors := PackedStringArray()


func _initialize() -> void:
	_test_well_conditioned_root_converges()
	_test_malformed_inputs_are_rejected()
	_test_budget_is_hard()
	_test_near_root_secant_polish_uses_the_remaining_budget()
	_test_repeated_results_are_byte_identical()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _test_well_conditioned_root_converges() -> void:
	var result := BoundedSolver.solve(_root, [-3.0, -3.0], [3.0, 3.0], [0.0, 0.0])
	_expect(result.get("ok", false), "the well-conditioned 2D root converges")
	_expect(result.get("status", "") == "converged", "convergence reports its status")
	_expect(result.get("x", []).size() == 2 \
		and abs(result.x[0] - 1.25) <= 0.02 \
		and abs(result.x[1] + 0.75) <= 0.02,
		"the converged point satisfies both coordinates within solver tolerance")
	_expect(result.get("residuals", []).size() == 2 \
		and _max_abs(result.residuals) <= 0.02,
		"the reported residuals satisfy the convergence threshold")
	_expect(result.get("evaluations", 0) > 0 and result.evaluations <= 80,
		"convergence respects the evaluation budget")


func _test_malformed_inputs_are_rejected() -> void:
	var bounds := BoundedSolver.solve(_root, [0.0], [0.0], [0.0])
	_expect(not bounds.get("ok", true) and bounds.get("status", "") == "invalid_input",
		"zero-width bounds are rejected as invalid input")
	_expect(bounds.get("evaluations", -1) == 0,
		"invalid bounds do not invoke the residual callback")
	var callback := BoundedSolver.solve(_malformed_residual, [0.0], [1.0], [0.5])
	_expect(not callback.get("ok", true) \
		and callback.get("status", "") == "invalid_residual",
		"a non-array callback result is rejected as an invalid residual")
	_expect(callback.get("evaluations", 0) == 1,
		"the malformed callback consumes exactly one evaluation")


func _test_budget_is_hard() -> void:
	var result := BoundedSolver.solve(_root, [-3.0, -3.0], [3.0, 3.0], [0.0, 0.0], 1)
	_expect(not result.get("ok", true) \
		and result.get("status", "") == "budget_exhausted",
		"an insufficient hard budget reports budget exhaustion")
	_expect(result.get("evaluations", 0) == 1,
		"budget exhaustion never exceeds the requested evaluation count")


func _test_near_root_secant_polish_uses_the_remaining_budget() -> void:
	var result := BoundedSolver.solve(
		_nearby_diagonal_root, [0.0, 0.0], [1.0, 1.0], [0.0, 0.0], 5)
	_expect(result.get("ok", false) and result.get("status", "") == "converged",
		"an accepted near-root step is polished before a fresh Jacobian exhausts the budget")
	_expect(result.get("evaluations", 0) == 5 and result.get("residuals", []).size() == 2
		and _max_abs(result.get("residuals", [])) <= 0.02,
		"the secant polish converges inside the unchanged hard evaluation budget")
	var headroom := BoundedSolver.solve(
		_nearby_diagonal_root, [0.0, 0.0], [1.0, 1.0], [0.0, 0.0], 80)
	_expect(headroom.get("ok", false) and headroom.get("status", "") == "converged"
		and headroom.get("evaluations", 0) == 7
		and headroom.get("residuals", []).size() == 2
		and _max_abs(headroom.get("residuals", [])) <= 0.02
		and headroom.get("x", []).size() == 2 and result.get("x", []).size() == 2
		and absf(float(headroom.x[0]) - 0.205) <= 0.0001
		and absf(float(headroom.x[1]) - 0.205) <= 0.0001,
		"the polish stays dormant when a complete Jacobian and trial still fit the budget")


func _test_repeated_results_are_byte_identical() -> void:
	var first := BoundedSolver.solve(_root, [-3.0, -3.0], [3.0, 3.0], [0.0, 0.0])
	var second := BoundedSolver.solve(_root, [-3.0, -3.0], [3.0, 3.0], [0.0, 0.0])
	var first_bytes := JSON.stringify(first).to_utf8_buffer()
	var second_bytes := JSON.stringify(second).to_utf8_buffer()
	_expect(first_bytes == second_bytes,
		"identical inputs produce byte-identical serialized results")


func _root(x: Array) -> Array:
	return [float(x[0]) - 1.25, float(x[1]) + 0.75]


func _nearby_diagonal_root(x: Array) -> Array:
	return [float(x[0]) - 0.205, float(x[1]) - 0.205]


func _malformed_residual(_x: Array) -> String:
	return "not residuals"


func _max_abs(values: Array) -> float:
	var maximum := 0.0
	for value in values:
		maximum = max(maximum, abs(float(value)))
	return maximum


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_errors.append(message)
