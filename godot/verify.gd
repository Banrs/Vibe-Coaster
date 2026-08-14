class_name RideVerify
extends RefCounted

## The load-verification toolkit that survives the rewrite, extended per docs/RESEARCH.md §5:
## 100 Hz resample → 4-pole single-pass 5 Hz Butterworth → duration-dependent envelope usage via
## the held-curve, plus push-pull, the reversal rule, and pairwise combined-axis ellipses.
## Limits are proportionally stretched ASTM F2291 duration curves — never flat tables.
## Everything here is parametric over the route dictionary; no element names are hardcoded.

const G0 := 9.80665
const GRAVITY := Vector3.DOWN * G0

## limit(t) = stretch × F2291_limit(t). Points are (duration s, limit g); linear between
## points, first value below the first duration, last value beyond the last.
## +Gz: stretch 8.0/6.0 on 6.0 (0.2–1 s) → 4.0 (2–4 s) → 3.0 (5–11.8 s) → 2.0 (→40 s) → 1.0.
const POSITIVE_LIMIT := [
	Vector2(0.2, 8.0), Vector2(1.0, 8.0), Vector2(2.0, 5.333), Vector2(4.0, 5.333),
	Vector2(5.0, 4.0), Vector2(11.8, 4.0), Vector2(40.0, 2.667), Vector2(60.0, 1.333),
]
## −Gz: stretch 3.0/2.0 on −2.0 (0.2 s) → −1.5 (0.5–4 s) → −1.1 (≥7 s). Stored positive.
const NEGATIVE_LIMIT := [
	Vector2(0.2, 3.0), Vector2(0.5, 2.25), Vector2(4.0, 2.25), Vector2(7.0, 1.65),
]
## ±Gy: stretch 4.7/3.0 on ±3.0 (0.2–1 s) → ±2.0 sustained.
const LATERAL_LIMIT := [
	Vector2(0.2, 4.7), Vector2(1.0, 4.7), Vector2(2.0, 3.133),
]
## +Gx mirrors the +Gz shape with 2.5 beyond 11.8 s, stretched 8.0/6.0.
const LONGITUDINAL_POSITIVE_LIMIT := [
	Vector2(0.2, 8.0), Vector2(1.0, 8.0), Vector2(2.0, 5.333), Vector2(4.0, 5.333),
	Vector2(5.0, 4.0), Vector2(11.8, 4.0), Vector2(12.0, 3.333),
]
## −Gx: stretch 6.0/3.5 on the prone/upper-torso-restraint curve
## (−3.5 brief → −2.5 @3–4 s → −2.0 @5 s+). Stored positive.
const LONGITUDINAL_NEGATIVE_LIMIT := [
	Vector2(0.2, 6.0), Vector2(1.0, 6.0), Vector2(3.0, 4.286), Vector2(4.0, 4.286),
	Vector2(5.0, 3.429),
]
const ONSET_LIMIT := 25.0
const ROLL_RATE_LIMIT := 120.0
## Push-pull: after ≥3 s of −Gz the brief +Gz cap drops to 5.0 × 8.0/6.0.
const PUSH_PULL_CAP := 6.667
const PUSH_PULL_HOLD := 3.0
const REVERSAL_GAP := 0.2
const SAMPLE_HZ := 100.0

const BRIEF_POSITIVE := 8.0
const BRIEF_NEGATIVE := 3.0
const BRIEF_LATERAL := 4.7
const BRIEF_LONGITUDINAL_POSITIVE := 8.0
const BRIEF_LONGITUDINAL_NEGATIVE := 6.0


## ---------------------------------------------------------------- measurement chain (kept)


static func resample(times: PackedFloat32Array, values: PackedFloat32Array) -> PackedFloat32Array:
	var output := PackedFloat32Array()
	var count := floori(times[-1] * SAMPLE_HZ) + 1
	output.resize(count)
	var source := 0
	for i in count:
		var at := i / SAMPLE_HZ
		while source + 1 < times.size() and times[source + 1] < at:
			source += 1
		if source + 1 >= times.size():
			output[i] = values[-1]
		else:
			output[i] = lerpf(values[source], values[source + 1], inverse_lerp(times[source], times[source + 1], at))
	return output


static func filter(values: PackedFloat32Array) -> PackedFloat32Array:
	var output := values
	for q in [0.5411961, 1.3065630]:
		output = _biquad(output, q)
	return output


static func _biquad(values: PackedFloat32Array, q: float) -> PackedFloat32Array:
	const OMEGA := TAU * 5.0 / 100.0
	var cosine := cos(OMEGA)
	var alpha := sin(OMEGA) / (2.0 * q)
	var divisor := 1.0 + alpha
	var b0 := (1.0 - cosine) * 0.5 / divisor
	var b1 := (1.0 - cosine) / divisor
	var b2 := b0
	var a1 := -2.0 * cosine / divisor
	var a2 := (1.0 - alpha) / divisor
	var output := PackedFloat32Array()
	output.resize(values.size())
	var x1: float = values[0]
	var x2 := x1
	var y1 := x1
	var y2 := x1
	for i in values.size():
		var x: float = values[i]
		var y: float = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		output[i] = y
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
	return output


static func envelope_usage(values: PackedFloat32Array, points: Array, polarity: float) -> Dictionary:
	var worst := {"usage": 0.0, "duration": 0.0, "held": 0.0, "limit": 0.0}
	var held_curve := _held_curve(values, polarity)
	var last_window := mini(held_curve.size() - 1, roundi((points[-1] as Vector2).x * SAMPLE_HZ) + 1)
	for window in range(21, last_window + 1):
		var duration := (window - 1) / SAMPLE_HZ
		var limit := limit_at(points, duration)
		var held: float = held_curve[window]
		var usage := held / limit
		if usage > worst.usage:
			worst = {"usage": usage, "duration": duration, "held": held, "limit": limit}
	return worst


static func limit_at(points: Array, duration: float) -> float:
	if duration <= (points[0] as Vector2).x:
		return (points[0] as Vector2).y
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		if duration <= b.x:
			return lerpf(a.y, b.y, inverse_lerp(a.x, b.x, duration))
	return (points[-1] as Vector2).y


static func _held_curve(values: PackedFloat32Array, polarity: float) -> PackedFloat32Array:
	var count := values.size()
	var signed := PackedFloat32Array()
	var left := PackedInt32Array()
	var right := PackedInt32Array()
	var best := PackedFloat32Array()
	signed.resize(count)
	left.resize(count)
	right.resize(count)
	best.resize(count + 1)
	best.fill(-INF)
	for i in count:
		signed[i] = values[i] * polarity
	var stack := PackedInt32Array()
	for i in count:
		while not stack.is_empty() and signed[stack[-1]] >= signed[i]:
			stack.remove_at(stack.size() - 1)
		left[i] = -1 if stack.is_empty() else stack[-1]
		stack.append(i)
	stack.clear()
	for i in range(count - 1, -1, -1):
		while not stack.is_empty() and signed[stack[-1]] >= signed[i]:
			stack.remove_at(stack.size() - 1)
		right[i] = count if stack.is_empty() else stack[-1]
		stack.append(i)
	for i in count:
		var window := right[i] - left[i] - 1
		best[window] = maxf(best[window], signed[i])
	for window in range(count - 1, 0, -1):
		best[window] = maxf(best[window], best[window + 1])
	return best


## ------------------------------------------------------------------ new F2291 checks (§5)


## Least-squares slope over a 100 ms window on a 100 Hz series — the F2291 onset measure.
static func peak_onset(filtered: PackedFloat32Array) -> float:
	const WINDOW := 11
	if filtered.size() < WINDOW:
		return 0.0
	var denominator := 0.0
	for k in WINDOW:
		var t := (k - (WINDOW - 1) * 0.5) / SAMPLE_HZ
		denominator += t * t
	var peak := 0.0
	for i in range(0, filtered.size() - WINDOW + 1):
		var mean := 0.0
		for k in WINDOW:
			mean += filtered[i + k]
		mean /= WINDOW
		var numerator := 0.0
		for k in WINDOW:
			numerator += ((k - (WINDOW - 1) * 0.5) / SAMPLE_HZ) * (filtered[i + k] - mean)
		peak = maxf(peak, absf(numerator / denominator))
	return peak


## After ≥3 s below zero Gz, the immediately following +Gz peak (within 2 s) must stay under
## the reduced push-pull cap. Returns the count of violating events.
static func push_pull_violations(filtered_normal: PackedFloat32Array) -> int:
	var violations := 0
	var negative_run := 0
	var i := 0
	var count := filtered_normal.size()
	while i < count:
		if filtered_normal[i] < -0.05:
			negative_run += 1
		else:
			if negative_run >= roundi(PUSH_PULL_HOLD * SAMPLE_HZ):
				var peak := 0.0
				for j in range(i, mini(i + roundi(2.0 * SAMPLE_HZ), count)):
					peak = maxf(peak, filtered_normal[j])
				if peak > PUSH_PULL_CAP + 0.01:
					violations += 1
			negative_run = 0
		i += 1
	return violations


## Two opposite-sign excursions past 50% of their brief limits separated by <0.2 s: each event
## is then capped at 50%, so any such pair is a violation. Returns the count of violating pairs.
static func reversal_violations(
	filtered: PackedFloat32Array, positive_brief: float, negative_brief: float
) -> int:
	var violations := 0
	var last_sign := 0
	var last_end := -1
	var inside := 0
	for i in filtered.size():
		var sign_now := 0
		if filtered[i] > positive_brief * 0.5:
			sign_now = 1
		elif filtered[i] < -negative_brief * 0.5:
			sign_now = -1
		if sign_now == 0:
			if inside != 0:
				last_sign = inside
				last_end = i - 1
				inside = 0
			continue
		if inside == 0 and sign_now != last_sign and last_sign != 0:
			if (i - 1 - last_end) < roundi(REVERSAL_GAP * SAMPLE_HZ):
				violations += 1
		inside = sign_now
	return violations


## F2291 combines axes pairwise (X-Y, X-Z, Y-Z ellipses), never as a 3-axis sphere. Uses the
## sign-appropriate brief limits on the filtered series; returns the worst pairwise usage.
static func combined_usage(
	filtered_normal: PackedFloat32Array,
	filtered_lateral: PackedFloat32Array,
	filtered_longitudinal: PackedFloat32Array
) -> float:
	var worst := 0.0
	for i in filtered_normal.size():
		var z: float = filtered_normal[i] / (BRIEF_POSITIVE if filtered_normal[i] >= 0.0 else BRIEF_NEGATIVE)
		var y: float = filtered_lateral[i] / BRIEF_LATERAL
		var x: float = filtered_longitudinal[i] / (BRIEF_LONGITUDINAL_POSITIVE if filtered_longitudinal[i] >= 0.0 else BRIEF_LONGITUDINAL_NEGATIVE)
		worst = maxf(worst, sqrt(z * z + y * y))
		worst = maxf(worst, sqrt(z * z + x * x))
		worst = maxf(worst, sqrt(y * y + x * x))
	return worst


## ------------------------------------------------------------------- per-row load analysis


static func row_forces_at(
	route: Dictionary, front_distance: float, train_speed: float, row_offset: float
) -> Dictionary:
	var front := _sample_fields(route, front_distance)
	var row := _sample_fields(route, front_distance - row_offset)
	var tangent: Vector3 = row.tangent
	var gravity_along: float = GRAVITY.dot(tangent)
	var gravity_across := GRAVITY - tangent * gravity_along
	if train_speed <= 0.01:
		var support := -GRAVITY
		return {
			"normal": support.dot(row.up) / G0,
			"lateral": support.dot(row.right) / G0,
			"longitudinal": support.dot(tangent) / G0,
			"roll_rate": 0.0,
		}
	var proper: Vector3 = row.curvature * train_speed * train_speed - gravity_across
	var acceleration: float = GRAVITY.dot(front.tangent) + front.longitudinal * G0
	return {
		"normal": proper.dot(row.up) / G0,
		"lateral": proper.dot(row.right) / G0,
		"longitudinal": (acceleration - gravity_along) / G0,
		"roll_rate": row.roll_rate * train_speed / maxf(row.speed, 1.0),
	}


static func _sample_fields(route: Dictionary, distance: float) -> Dictionary:
	var at := fposmod(distance, route.length)
	var low := 0
	var high: int = route.distances.size() - 1
	while low + 1 < high:
		var middle := floori((low + high) * 0.5)
		if route.distances[middle] <= at:
			low = middle
		else:
			high = middle
	var span: float = route.distances[high] - route.distances[low]
	var weight: float = 0.0 if span <= 0.0 else (at - route.distances[low]) / span
	var tangent: Vector3 = route.tangents[low].lerp(route.tangents[high], weight).normalized()
	var up: Vector3 = route.ups[low].lerp(route.ups[high], weight)
	up = (up - tangent * up.dot(tangent)).normalized()
	var right := tangent.cross(up).normalized()
	up = right.cross(tangent).normalized()
	return {
		"tangent": tangent,
		"up": up,
		"right": right,
		"curvature": route.curvatures[low].lerp(route.curvatures[high], weight),
		"longitudinal": lerpf(route.longitudinal_g[low], route.longitudinal_g[high], weight),
		"roll_rate": lerpf(route.roll_rates[low], route.roll_rates[high], weight),
		"speed": lerpf(route.speeds[low], route.speeds[high], weight),
	}


static func analyze(route: Dictionary, row_offsets: Array) -> Dictionary:
	var top_speed := -INF
	var minimum_height := INF
	var maximum_height := -INF
	for i in route.positions.size():
		top_speed = maxf(top_speed, route.speeds[i])
		minimum_height = minf(minimum_height, route.positions[i].y)
		maximum_height = maxf(maximum_height, route.positions[i].y)
	var rows: Array[Dictionary] = []
	for offset in row_offsets:
		rows.append(_analyze_row(route, offset))
	return {
		"top_speed": top_speed,
		"average_speed": route.length / route.duration,
		"minimum_height": minimum_height,
		"maximum_height": maximum_height,
		"elevation_span": maximum_height - minimum_height,
		"rows": rows,
	}


static func _analyze_row(route: Dictionary, offset: float) -> Dictionary:
	var count: int = route.positions.size()
	var normal := PackedFloat32Array()
	var lateral := PackedFloat32Array()
	var longitudinal := PackedFloat32Array()
	normal.resize(count)
	lateral.resize(count)
	longitudinal.resize(count)
	var peak_positive := -INF
	var peak_negative := INF
	var peak_lateral := 0.0
	var peak_longitudinal_positive := -INF
	var peak_longitudinal_negative := INF
	var peak_roll := 0.0
	for i in count:
		var forces := row_forces_at(route, route.distances[i], route.speeds[i], offset)
		normal[i] = forces.normal
		lateral[i] = forces.lateral
		longitudinal[i] = forces.longitudinal
		peak_positive = maxf(peak_positive, normal[i])
		peak_negative = minf(peak_negative, normal[i])
		peak_lateral = maxf(peak_lateral, absf(lateral[i]))
		peak_longitudinal_positive = maxf(peak_longitudinal_positive, longitudinal[i])
		peak_longitudinal_negative = minf(peak_longitudinal_negative, longitudinal[i])
		peak_roll = maxf(peak_roll, absf(forces.roll_rate))
	var filtered_normal := filter(resample(route.times, normal))
	var filtered_lateral := filter(resample(route.times, lateral))
	var filtered_longitudinal := filter(resample(route.times, longitudinal))
	var lateral_positive := envelope_usage(filtered_lateral, LATERAL_LIMIT, 1.0)
	var lateral_negative := envelope_usage(filtered_lateral, LATERAL_LIMIT, -1.0)
	return {
		"offset": offset,
		"peak_positive": peak_positive,
		"peak_negative": peak_negative,
		"peak_lateral": peak_lateral,
		"peak_longitudinal_positive": peak_longitudinal_positive,
		"peak_longitudinal_negative": peak_longitudinal_negative,
		"peak_roll_rate": peak_roll,
		"peak_onset": maxf(
			peak_onset(filtered_normal),
			maxf(peak_onset(filtered_lateral), peak_onset(filtered_longitudinal))
		),
		"positive_envelope": envelope_usage(filtered_normal, POSITIVE_LIMIT, 1.0),
		"negative_envelope": envelope_usage(filtered_normal, NEGATIVE_LIMIT, -1.0),
		"lateral_envelope": lateral_positive if lateral_positive.usage >= lateral_negative.usage else lateral_negative,
		"longitudinal_positive_envelope": envelope_usage(filtered_longitudinal, LONGITUDINAL_POSITIVE_LIMIT, 1.0),
		"longitudinal_negative_envelope": envelope_usage(filtered_longitudinal, LONGITUDINAL_NEGATIVE_LIMIT, -1.0),
		"combined_usage": combined_usage(filtered_normal, filtered_lateral, filtered_longitudinal),
		"push_pull_violations": push_pull_violations(filtered_normal),
		"reversal_violations": reversal_violations(filtered_normal, BRIEF_POSITIVE, BRIEF_NEGATIVE)
			+ reversal_violations(filtered_lateral, BRIEF_LATERAL, BRIEF_LATERAL)
			+ reversal_violations(filtered_longitudinal, BRIEF_LONGITUDINAL_POSITIVE, BRIEF_LONGITUDINAL_NEGATIVE),
	}


## ------------------------------------------------------------------------ route validation


static func validate_structure(route: Dictionary, issues: PackedStringArray) -> void:
	var count: int = route.positions.size()
	var fields := [
		"tangents", "ups", "rights", "curvatures", "banks", "speeds", "normal_g", "lateral_g",
		"longitudinal_g", "drive_g", "roll_rates", "distances", "times", "span_indices",
		"gesture_indices", "propulsion_ids", "minimum_speeds",
	]
	_require(issues, count > 1000, "route has too few samples")
	for field in fields:
		_require(issues, route[field].size() == count, "%s sample count differs" % field)
	if not issues.is_empty():
		return
	for i in count:
		var tangent: Vector3 = route.tangents[i]
		var up: Vector3 = route.ups[i]
		var right: Vector3 = route.rights[i]
		_require(issues, route.positions[i].is_finite() and tangent.is_finite() and up.is_finite() and right.is_finite(), "non-finite frame at sample %d" % i)
		_require(issues, absf(tangent.length_squared() - 1.0) < 0.002 and absf(up.length_squared() - 1.0) < 0.002 and absf(right.length_squared() - 1.0) < 0.002, "non-unit frame at sample %d" % i)
		_require(issues, absf(tangent.dot(up)) < 0.002 and absf(tangent.dot(right)) < 0.002 and absf(up.dot(right)) < 0.002, "non-orthogonal frame at sample %d" % i)
		var minimum_speed: float = route.minimum_speeds[i]
		_require(issues, is_finite(route.speeds[i]) and route.speeds[i] > minimum_speed, "invalid or stalled speed at sample %d" % i)
		if i > 0:
			_require(issues, route.distances[i] > route.distances[i - 1] and route.times[i] > route.times[i - 1], "non-monotone route at sample %d" % i)
		if issues.size() > 20:
			return


## Independent sampled C4 and bank continuity at every native motion-span seam. The one
## exception is the brakes-to-station seam: station mode pins curvature to zero while moving
## mode derives it from transverse/v^2, so finite differences across that seam compare two
## definitions over centimetre steps. There the closure is proven directly instead: the
## moving side must arrive at near-zero curvature.
static func validate_seams(route: Dictionary, issues: PackedStringArray) -> void:
	for seam in range(1, route.span_indices.size()):
		if route.span_indices[seam] == route.span_indices[seam - 1]:
			continue
		if seam < 2 or seam + 2 >= route.positions.size():
			continue
		var context := "sample %d, span %d, %s" % [
			seam, route.span_indices[seam], _semantic_window_id(route, seam)]
		var entering_station: bool = route.minimum_speeds[seam - 1] == 2.0 \
			and route.minimum_speeds[seam] == 0.0
		if entering_station:
			_require(issues, route.curvatures[seam - 1].length() < 0.001,
				"station closure arrives curved at %s" % context)
		else:
			var ds_before: float = route.distances[seam] - route.distances[seam - 1]
			var ds_after: float = route.distances[seam + 1] - route.distances[seam]
			var first_before: Vector3 = (route.curvatures[seam] \
				- route.curvatures[seam - 1]) / ds_before
			var first_after: Vector3 = (route.curvatures[seam + 1] \
				- route.curvatures[seam]) / ds_after
			_require(issues, first_before.distance_to(first_after) < 0.0012,
				"C3 curvature slope jumps at %s" % context)
			var ds_outer_before: float = route.distances[seam - 1] - route.distances[seam - 2]
			var ds_outer_after: float = route.distances[seam + 2] - route.distances[seam + 1]
			var previous_first: Vector3 = (route.curvatures[seam - 1] \
				- route.curvatures[seam - 2]) / ds_outer_before
			var next_first: Vector3 = (route.curvatures[seam + 2] \
				- route.curvatures[seam + 1]) / ds_outer_after
			var second_before: Vector3 = (first_before - previous_first) * 2.0 \
				/ (ds_before + ds_outer_before)
			var second_after: Vector3 = (next_first - first_after) * 2.0 \
				/ (ds_after + ds_outer_after)
			_require(issues, second_before.distance_to(second_after) < 0.0025,
				"C4 curvature acceleration jumps at %s" % context)
		var bank_step: float = absf(angle_difference(deg_to_rad(route.banks[seam]), deg_to_rad(route.banks[seam - 1])))
		_require(issues, bank_step < deg_to_rad(4.0),
			"bank jumps %.1f° at %s" % [rad_to_deg(bank_step), context])


static func validate_clearance(
	route: Dictionary, terrain: Dictionary, issues: PackedStringArray
) -> void:
	const RAIL_DROP := 1.55
	const TERRAIN_CLEARANCE := 2.0
	for i in route.positions.size():
		var in_tunnel := false
		for tunnel in route.tunnel_ranges:
			if i >= tunnel.x and i <= tunnel.y:
				in_tunnel = true
				break
		if in_tunnel:
			continue
		var rail: Vector3 = route.positions[i] - route.ups[i] * RAIL_DROP
		var ground: float = RideTerrain.height(terrain, rail.x, rail.z)
		if rail.y - ground < TERRAIN_CLEARANCE:
			issues.append(
				"terrain intersects track near '%s' at (%.0f, %.0f): %.2f m clearance"
				% [_semantic_window_id(route, i), rail.x, rail.z, rail.y - ground]
			)
			return


static func _semantic_window_id(route: Dictionary, sample: int) -> String:
	var index: int = route.gesture_indices[sample]
	if index < 0 or index >= route.gesture_windows.size():
		return "unowned"
	return str(route.gesture_windows[index].get("window_id", "unowned"))


static func validate_self_clearance(route: Dictionary, issues: PackedStringArray) -> void:
	const CELL := 4.0
	const CLEARANCE := 3.0
	var cells := {}
	for i in range(0, route.positions.size(), 2):
		var position: Vector3 = route.positions[i]
		var cell := Vector3i(floori(position.x / CELL), floori(position.y / CELL), floori(position.z / CELL))
		for x in range(-1, 2):
			for y in range(-1, 2):
				for z in range(-1, 2):
					var neighbor := cell + Vector3i(x, y, z)
					for other in cells.get(neighbor, []):
						var separation: float = absf(route.distances[i] - route.distances[other])
						separation = minf(separation, route.length - separation)
						if separation > 30.0 and position.distance_to(route.positions[other]) < CLEARANCE:
							issues.append("non-adjacent track violates %.1f m self-clearance near sample %d" % [CLEARANCE, i])
							return
		if not cells.has(cell):
			cells[cell] = []
		cells[cell].append(i)


## Hard limits and the three F2291 checks for every row. Intentional-usage bands (the
## proportional-usage principle) arrive with the generator's expectations.
static func validate_loads(analysis: Dictionary, issues: PackedStringArray) -> void:
	for row in analysis.rows:
		_require(issues, row.peak_positive <= BRIEF_POSITIVE + 0.01 and row.peak_negative >= -BRIEF_NEGATIVE - 0.01, "row %.2f m exceeds raw normal-G limits" % row.offset)
		_require(issues, row.peak_lateral <= BRIEF_LATERAL + 0.01, "row %.2f m exceeds raw lateral limits" % row.offset)
		_require(issues, row.peak_longitudinal_positive <= BRIEF_LONGITUDINAL_POSITIVE + 0.01 and row.peak_longitudinal_negative >= -BRIEF_LONGITUDINAL_NEGATIVE - 0.01, "row %.2f m exceeds raw longitudinal limits" % row.offset)
		_require(issues, row.peak_onset <= ONSET_LIMIT + 0.01, "row %.2f m exceeds the %.0f g/s onset limit" % [row.offset, ONSET_LIMIT])
		_require(issues, row.peak_roll_rate <= ROLL_RATE_LIMIT + 0.01, "row %.2f m exceeds the %.0f°/s roll-rate limit" % [row.offset, ROLL_RATE_LIMIT])
		_require(issues, row.positive_envelope.usage <= 1.001 and row.negative_envelope.usage <= 1.001 and row.lateral_envelope.usage <= 1.001 and row.longitudinal_positive_envelope.usage <= 1.001 and row.longitudinal_negative_envelope.usage <= 1.001, "row %.2f m exceeds a filtered duration envelope" % row.offset)
		_require(issues, row.combined_usage <= 1.001, "row %.2f m exceeds a pairwise combined-axis ellipse" % row.offset)
		_require(issues, row.push_pull_violations == 0, "row %.2f m violates the push-pull +Gz cap" % row.offset)
		_require(issues, row.reversal_violations == 0, "row %.2f m violates the 0.2 s reversal rule" % row.offset)


static func _require(issues: PackedStringArray, condition: bool, message: String) -> void:
	if not condition:
		issues.append(message)
