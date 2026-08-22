extends SceneTree

const BoundedSolver := preload("res://bounded_solver.gd")

var _t := TestUtil.new()


func _initialize() -> void:
	_test_well_conditioned_root_converges()
	_test_malformed_inputs_are_rejected()
	_test_budget_is_hard()
	_test_repeated_results_are_byte_identical()
	_t.finish(self)


func _test_well_conditioned_root_converges() -> void:
	var result := BoundedSolver.solve(_root, [-3.0, -3.0], [3.0, 3.0], [0.0, 0.0])
	_t.expect(result.get("ok", false), "the well-conditioned 2D root converges")
	_t.expect(result.get("status", "") == "converged", "convergence reports its status")
	_t.expect(result.get("x", []).size() == 2 \
		and abs(result.x[0] - 1.25) <= 0.02 \
		and abs(result.x[1] + 0.75) <= 0.02,
		"the converged point satisfies both coordinates within solver tolerance")
	_t.expect(result.get("residuals", []).size() == 2 \
		and _max_abs(result.residuals) <= 0.02,
		"the reported residuals satisfy the convergence threshold")
	_t.expect(result.get("evaluations", 0) > 0 and result.evaluations <= 80,
		"convergence respects the evaluation budget")


func _test_malformed_inputs_are_rejected() -> void:
	var bounds := BoundedSolver.solve(_root, [0.0], [0.0], [0.0])
	_t.expect(not bounds.get("ok", true) and bounds.get("status", "") == "invalid_input",
		"zero-width bounds are rejected as invalid input")
	_t.expect(bounds.get("evaluations", -1) == 0,
		"invalid bounds do not invoke the residual callback")
	var callback := BoundedSolver.solve(_malformed_residual, [0.0], [1.0], [0.5])
	_t.expect(not callback.get("ok", true) \
		and callback.get("status", "") == "invalid_residual",
		"a non-array callback result is rejected as an invalid residual")
	_t.expect(callback.get("evaluations", 0) == 1,
		"the malformed callback consumes exactly one evaluation")


func _test_budget_is_hard() -> void:
	var result := BoundedSolver.solve(_root, [-3.0, -3.0], [3.0, 3.0], [0.0, 0.0], 1)
	_t.expect(not result.get("ok", true) \
		and result.get("status", "") == "budget_exhausted",
		"an insufficient hard budget reports budget exhaustion")
	_t.expect(result.get("evaluations", 0) == 1,
		"budget exhaustion never exceeds the requested evaluation count")


func _test_repeated_results_are_byte_identical() -> void:
	var first := BoundedSolver.solve(_root, [-3.0, -3.0], [3.0, 3.0], [0.0, 0.0])
	var second := BoundedSolver.solve(_root, [-3.0, -3.0], [3.0, 3.0], [0.0, 0.0])
	var first_bytes := JSON.stringify(first).to_utf8_buffer()
	var second_bytes := JSON.stringify(second).to_utf8_buffer()
	_t.expect(first_bytes == second_bytes,
		"identical inputs produce byte-identical serialized results")


func _root(x: Array) -> Array:
	return [float(x[0]) - 1.25, float(x[1]) + 0.75]


func _malformed_residual(_x: Array) -> String:
	return "not residuals"


func _max_abs(values: Array) -> float:
	var maximum := 0.0
	for value in values:
		maximum = max(maximum, abs(float(value)))
	return maximum

