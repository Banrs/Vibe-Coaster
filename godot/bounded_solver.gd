class_name BoundedSolver
extends RefCounted
static func solve(residual: Callable, lower: Array, upper: Array, initial: Array,
		max_evaluations: int = 80) -> Dictionary:
	var n := lower.size()
	if not residual.is_valid() or n == 0 or upper.size() != n or initial.size() != n \
			or max_evaluations <= 0:
		return _result(false, "invalid_input", initial.duplicate(), [], 0, 0, INF)
	var widths: Array[float] = []
	var z: Array[float] = []
	for i in range(n):
		if not _finite_number(lower[i]) or not _finite_number(upper[i]) \
				or not _finite_number(initial[i]):
			return _result(false, "invalid_input", initial.duplicate(), [], 0, 0, INF)
		var width := float(upper[i]) - float(lower[i])
		if not is_finite(width) or width <= 0.0:
			return _result(false, "invalid_input", initial.duplicate(), [], 0, 0, INF)
		widths.append(width)
		z.append(clampf((float(initial[i]) - float(lower[i])) / width, 0.0, 1.0))
	var cache := {}
	var evaluation_count := [0]
	var current := _evaluate(residual, z, lower, widths, cache, evaluation_count, max_evaluations)
	if not current.ok:
		return _result(false, current.status, _to_x(z, lower, widths), [], evaluation_count[0], 0, INF)
	var values: Array = current.values
	var sse := _sse(values)
	if not is_finite(sse):
		return _result(false, "invalid_residual", _to_x(z, lower, widths), values, evaluation_count[0], 0, INF)
	if _max_abs(values) <= 0.02:
		return _result(true, "converged", _to_x(z, lower, widths), values, evaluation_count[0], 0, 1.0)
	var damping := 0.01
	var radius := 0.25
	var iterations := 0
	var conditioning := INF
	var status := "iteration_limit"
	while iterations < max(8, max_evaluations * 2):
		iterations += 1
		var jacobian: Array = []
		for row_index in range(values.size()):
			var row: Array[float] = []
			row.resize(n)
			row.fill(0.0)
			jacobian.append(row)
		for column in range(n):
			var delta := 0.005 if z[column] <= 0.995 else -0.005
			var probe := z.duplicate()
			probe[column] = clampf(probe[column] + delta, 0.0, 1.0)
			var sampled := _evaluate(residual, probe, lower, widths, cache, evaluation_count, max_evaluations)
			if not sampled.ok:
				return _result(false, sampled.status, _to_x(z, lower, widths), values, evaluation_count[0], iterations, conditioning)
			if sampled.values.size() != values.size():
				return _result(false, "invalid_residual", _to_x(z, lower, widths), values, evaluation_count[0], iterations, conditioning)
			for row_index in range(values.size()):
				jacobian[row_index][column] = (sampled.values[row_index] - values[row_index]) / delta
		var normal: Array = []
		var gradient: Array[float] = []
		for i in range(n):
			var row: Array[float] = []
			for j in range(n):
				var sum := 0.0
				for k in range(values.size()):
					sum += jacobian[k][i] * jacobian[k][j]
				row.append(sum + (damping if i == j else 0.0))
			normal.append(row)
			var component := 0.0
			for k in range(values.size()):
				component -= jacobian[k][i] * values[k]
			gradient.append(component)
		var solved := linear_solve(normal, gradient)
		if not solved.ok:
			return _result(false, "numerical_failure", _to_x(z, lower, widths), values, evaluation_count[0], iterations, INF)
		conditioning = solved.conditioning
		var step: Array = solved.x
		var step_norm := sqrt(_sse(step))
		if step_norm > radius:
			for i in range(n):
				step[i] *= radius / step_norm
		var candidate := z.duplicate()
		for i in range(n):
			candidate[i] = clampf(candidate[i] + step[i], 0.0, 1.0)
		if candidate == z:
			status = "stalled"
			break
		var trial := _evaluate(residual, candidate, lower, widths, cache, evaluation_count, max_evaluations)
		if not trial.ok:
			return _result(false, trial.status, _to_x(z, lower, widths), values, evaluation_count[0], iterations, conditioning)
		if trial.values.size() != values.size():
			return _result(false, "invalid_residual", _to_x(z, lower, widths), values, evaluation_count[0], iterations, conditioning)
		var trial_sse := _sse(trial.values)
		if is_finite(trial_sse) and trial_sse < sse:
			z = candidate
			values = trial.values
			sse = trial_sse
			damping = max(damping * 0.3, 1e-12)
			radius = min(radius * 1.5, 1.0)
			if _max_abs(values) <= 0.02:
				return _result(true, "converged", _to_x(z, lower, widths), values, evaluation_count[0], iterations, conditioning)
		else:
			damping = min(damping * 10.0, 1e12)
			radius = max(radius * 0.5, 1e-8)
			if radius <= 1e-8:
				status = "stalled"
				break
	return _result(false, status, _to_x(z, lower, widths), values, evaluation_count[0], iterations, conditioning)
static func _evaluate(residual: Callable, z: Array, lower: Array, widths: Array, cache: Dictionary,
		count: Array, budget: int) -> Dictionary:
	var key := PackedFloat64Array(z).to_byte_array().hex_encode()
	if cache.has(key):
		return {"ok": true, "values": cache[key].duplicate()}
	if count[0] >= budget:
		return {"ok": false, "status": "budget_exhausted"}
	var raw: Variant = residual.call(_to_x(z, lower, widths))
	count[0] += 1
	if typeof(raw) not in [TYPE_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY] or raw.size() == 0:
		return {"ok": false, "status": "invalid_residual"}
	var values: Array[float] = []
	for item in raw:
		if not _finite_number(item):
			return {"ok": false, "status": "invalid_residual"}
		values.append(float(item))
	cache[key] = values.duplicate()
	return {"ok": true, "values": values}
## The one partial-pivot linear solve, shared with `ride_program.gd`'s capture and brake Newton
## steps. Returns the solution together with the pivot record those solves report as
## conditioning, so an ill-conditioned system is measured once, in one place.
static func linear_solve(matrix: Array, rhs: Array) -> Dictionary:
	var n := rhs.size()
	var a := matrix.duplicate(true)
	var b := rhs.duplicate()
	var smallest := INF
	var largest := 0.0
	for column in range(n):
		var pivot := column
		for row in range(column + 1, n):
			if abs(a[row][column]) > abs(a[pivot][column]):
				pivot = row
		var magnitude: float = abs(a[pivot][column])
		smallest = min(smallest, magnitude)
		largest = max(largest, magnitude)
		if not is_finite(magnitude) or magnitude <= 1e-14:
			return {"ok": false, "minimum_pivot": smallest, "maximum_pivot": largest}
		if pivot != column:
			var row_swap: Variant = a[column]
			a[column] = a[pivot]
			a[pivot] = row_swap
			var value_swap: Variant = b[column]
			b[column] = b[pivot]
			b[pivot] = value_swap
		for row in range(column + 1, n):
			var factor: float = a[row][column] / a[column][column]
			for j in range(column + 1, n):
				a[row][j] -= factor * a[column][j]
			b[row] -= factor * b[column]
	var x: Array[float] = []
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var value: float = b[i]
		for j in range(i + 1, n):
			value -= a[i][j] * x[j]
		x[i] = value / a[i][i]
		if not is_finite(x[i]):
			return {"ok": false}
	return {"ok": true, "x": x, "conditioning": largest / smallest,
		"minimum_pivot": smallest, "maximum_pivot": largest}
static func _finite_number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
static func _to_x(z: Array, lower: Array, widths: Array) -> Array:
	var x: Array[float] = []
	for i in range(z.size()):
		x.append(float(lower[i]) + widths[i] * z[i])
	return x
static func _sse(values: Array) -> float:
	var total := 0.0
	for value in values:
		total += value * value
	return total
static func _max_abs(values: Array) -> float:
	var maximum := 0.0
	for value in values:
		maximum = max(maximum, abs(value))
	return maximum
static func _result(ok: bool, status: String, x: Array, residuals: Array,
		evaluations: int, iterations: int, conditioning: float) -> Dictionary:
	return {"ok": ok, "status": status, "x": x, "residuals": residuals, "evaluations": evaluations,
		"iterations": iterations, "conditioning": conditioning}
