class_name RideReturnLayout
extends RefCounted

## Pure macro return layout: the accepted post-camelback state plus immutable plan facts become
## one ordered set of return assignments. Geometry only - no RNG, no force profile, no drive, no
## integration. What it publishes is a target and a feasibility contract; the production
## integration remains the sole centreline authority and rejects a candidate that disagrees.
##
## Curvature basis (design 2026-08-22 section 3): world-referenced pitch/yaw, so track pitch obeys
## `d(theta)/ds = kappa_pitch` - `kappa_pitch < 0` at a crest - and plan-view heading obeys
## `d(psi)/ds = kappa_yaw / cos(theta)`. The nominal chain authors `theta` and `psi` through
## quintic shoulders whose value, spatial slope and spatial acceleration vanish at both ends, so
## every role leaves the chain level and unbanked. That is why the gate's pitch and roll are not
## residuals: the element contracts close them by construction.

const Motion := preload("res://motion.gd")  # `G0` only; this stage never integrates.
const BoundedSolver := preload("res://bounded_solver.gd")

## The shoulder each role reserves at both of its ends, and the fraction of the allocated arc that
## therefore carries loaded curvature. One shoulder geometry serves the nominal chain, the heading
## feasibility bound, and the local turn family, so the frame this stage assigns is a frame that
## family can reach: two quintic shoulders of `SHOULDER_FRACTION` plus a plateau integrate to
## `LOADED_ARC_FRACTION`, the 0.8 of the bound.
const SHOULDER_FRACTION := 0.2
const LOADED_ARC_FRACTION := 1.0 - SHOULDER_FRACTION
## The return turn family's bank ceiling: the same 66 deg the existing turn-a bank bound holds,
## taken for both turns because the conservative ceiling is the one a feasibility bound may use.
const TURN_BANK_CEILING_RAD := 66.0 * PI / 180.0
## The camelback's ~33.6 deg is the steepest pitch the prefix hands over and the return stays
## inside it; 35 deg is the ceiling that admits that handover and nothing steeper.
const PITCH_CEILING_RAD := 35.0 * PI / 180.0
const MOVING_FLOOR_MPS := 2.0
## Cross, vertical and forward in metres, terminal yaw in radians. A scaled residual of 0.02 is
## therefore 0.1 m of position error and 0.0004 rad of yaw error at the gate.
const RESIDUAL_SCALES := [5.0, 5.0, 5.0, 0.02]
const CHAIN_SAMPLES_PER_ROLE := 24
const ALLOCATION_TOLERANCE_M := 0.000001
const ALLOCATION_ITERATIONS := 200
const TURN_FAMILY := "return_turn"
const HEIGHT_FAMILY := "return_height"


## Bounded water-filling: `L_i(lambda) = clamp(N_i + lambda w_i, lower_i, upper_i)` summed to
## `total_m`. The sum is monotone in the single scalar `lambda`, so deterministic bisection finds
## it; an infeasible total is refused before any bisection runs.
static func allocate_lengths(nominals: Array, bands: Array, weights: Array,
		total_m: float) -> Dictionary:
	var count := nominals.size()
	if count == 0 or bands.size() != count or weights.size() != count or not is_finite(total_m):
		return _allocation(false, "invalid_input", [], 0.0, 0.0)
	var lower_sum := 0.0
	var upper_sum := 0.0
	var low := INF
	var high := -INF
	for index in count:
		var nominal := float(nominals[index])
		var band: Vector2 = bands[index]
		var weight := float(weights[index])
		if not is_finite(nominal) or not is_finite(band.x) or not is_finite(band.y) \
				or band.y < band.x or not is_finite(weight) or weight <= 0.0:
			return _allocation(false, "invalid_input", [], 0.0, 0.0)
		lower_sum += band.x
		upper_sum += band.y
		low = minf(low, (band.x - nominal) / weight)
		high = maxf(high, (band.y - nominal) / weight)
	if total_m < lower_sum - ALLOCATION_TOLERANCE_M or total_m > upper_sum + ALLOCATION_TOLERANCE_M:
		return _allocation(false, "infeasible_total", [], 0.0,
			total_m - clampf(total_m, lower_sum, upper_sum))
	var lambda_value := 0.0
	var lengths := _projected(nominals, bands, weights, high)
	for _iteration in ALLOCATION_ITERATIONS:
		lambda_value = 0.5 * (low + high)
		lengths = _projected(nominals, bands, weights, lambda_value)
		var error := _sum(lengths) - total_m
		if absf(error) <= ALLOCATION_TOLERANCE_M:
			return _allocation(true, "allocated", lengths, lambda_value, error)
		if error < 0.0: low = lambda_value
		else: high = lambda_value
	return _allocation(false, "unconverged", lengths, lambda_value, _sum(lengths) - total_m)


## The one macro solve: five bounded controls - signed heading change per turn, signed net
## elevation per height beat, and the bounded return total length - against four station-frame
## residuals. Underdetermined on purpose; `BoundedSolver`'s damping resolves the extra freedom
## deterministically from the nominal control vector, and the two elevation controls split the
## vertical residual by their bound widths rather than degenerating into each other.
static func build(start: Dictionary, plan: Dictionary, ordered_roles: Array) -> Dictionary:
	var context := _context(start, plan, ordered_roles)
	if not context.ok:
		return _refused(context.errors)
	var residual := func(x: Array) -> Array: return _residuals(context, x)
	var solved := BoundedSolver.solve(residual, context.lower, context.upper, context.nominal,
		RideReturnSolve.MAX_RETURN_EVALUATIONS)
	var chain := _chain(context, solved.x)
	var errors := _refusals(context, chain)
	if not solved.ok:
		errors.append({"code": "macro_solve_unconverged", "status": str(solved.status),
			"scaled_residuals": solved.residuals.duplicate()})
	if not errors.is_empty():
		return _refused(errors, _report(context, chain, solved))
	return _freeze({
		"ok": true,
		"assignments": _assignments(context, chain),
		"terminal_gate": _frame(context.gate_position, context.gate_tangent, context.gate_up),
		"target_total_length_m": float(solved.x[context.length_index]),
		"length_budget_margin_m": _length_margin(context, chain),
		"terrain_margins": chain.terrain_margins,
		"energy_margins": {"moving_floor_mps": chain.minimum_speed_mps - MOVING_FLOOR_MPS},
		"report": _report(context, chain, solved),
		"errors": [],
	})


## The macro feasibility contract on a turn's heading change: its allocated arc, its entry speed
## and the family's bank ceiling bound it, checked here rather than handed to a local solve that
## would have to break the bank or force envelope to deliver it. A 180 deg reversal is refused by
## this bound, which is why no reversal topology exists.
static func heading_bound_rad(length_m: float, speed_mps: float) -> float:
	return LOADED_ARC_FRACTION * length_m * Motion.G0 * tan(TURN_BANK_CEILING_RAD) \
		/ (speed_mps * speed_mps)


static func _context(start: Dictionary, plan: Dictionary, ordered_roles: Array) -> Dictionary:
	var errors: Array = []
	var station: Variant = plan.get("station")
	var corridor: Variant = plan.get("corridor")
	var route_band: Variant = plan.get("route_length_m")
	if not station is Dictionary or not corridor is Dictionary or not route_band is Vector2 \
			or not plan.get("roles") is Array:
		return {"ok": false, "errors": [{"code": "malformed_plan"}]}
	var start_position: Variant = start.get("position_m")
	var start_tangent: Variant = start.get("tangent")
	var start_up: Variant = start.get("rider_up")
	var start_speed := float(start.get("speed_mps", 0.0))
	var start_distance := float(start.get("distance_m", -1.0))
	if not start_position is Vector3 or not start_tangent is Vector3 or not start_up is Vector3 \
			or not start_speed > MOVING_FLOOR_MPS or start_distance < 0.0:
		return {"ok": false, "errors": [{"code": "malformed_start_state"}]}
	var gate_tangent: Vector3 = (station.tangent as Vector3).normalized()
	var gate_position: Vector3 = (station.position_m as Vector3) \
		- gate_tangent * float(corridor.approach_length_m)
	var forward := (gate_tangent - Vector3.UP * gate_tangent.dot(Vector3.UP)).normalized()
	var right := forward.cross(Vector3.UP)
	var tangent: Vector3 = (start_tangent as Vector3).normalized()
	var order: Array = []
	var families: Array = []
	var nominal_lengths: Array = []
	var length_bands: Array = []
	var terrain_intents: Array = []
	var control_index := {}
	var lower: Array = []
	var upper: Array = []
	var nominal: Array = []
	var control_ids: Array = []
	var turns := 0
	var heights := 0
	for role_id: String in ordered_roles:
		var role := _role(plan.roles, role_id)
		var family := str(role.get("recipe_id", ""))
		if role.is_empty() or control_index.has(role_id) \
				or (family != TURN_FAMILY and family != HEIGHT_FAMILY):
			errors.append({"code": "unknown_return_role", "role_id": role_id})
			continue
		var band: Vector2 = role.length_m
		order.append(role_id)
		families.append(family)
		terrain_intents.append(role.get("terrain", {}))
		length_bands.append(band)
		nominal_lengths.append(0.5 * (band.x + band.y))
		control_index[role_id] = control_ids.size()
		if family == TURN_FAMILY:
			turns += 1
			control_ids.append("%s/heading_change_rad" % role_id)
		else:
			heights += 1
			control_ids.append("%s/elevation_change_m" % role_id)
	if turns != 2 or heights != 2:
		errors.append({"code": "return_family_count", "turns": turns, "heights": heights})
	if not errors.is_empty():
		return {"ok": false, "errors": errors}
	var budget := _budget(route_band, start_distance, float(corridor.approach_length_m),
		length_bands)
	if budget.x >= budget.y:
		return {"ok": false, "errors": [{"code": "infeasible_return_budget",
			"lower_m": budget.x, "upper_m": budget.y}]}
	var psi_start := atan2(tangent.dot(right), tangent.dot(forward))
	var heading_request := wrapf(-psi_start, -PI, PI)
	var drop := (gate_position - (start_position as Vector3)).dot(Vector3.UP)
	for index in order.size():
		nominal.append(0.5 * heading_request if families[index] == TURN_FAMILY else 0.5 * drop)
	control_ids.append("return_total_length_m")
	nominal.append(0.5 * (budget.x + budget.y))
	var context := {"ok": true, "errors": errors, "order": order, "families": families,
		"terrain_intents": terrain_intents,
		"nominal_lengths": nominal_lengths, "length_bands": length_bands,
		"length_weights": _ones(order.size()), "control_index": control_index,
		"control_ids": control_ids, "lower": lower, "upper": upper, "nominal": nominal,
		"length_index": order.size(), "budget_m": budget, "forward": forward,
		"right": right, "gate_position": gate_position,
		"gate_tangent": gate_tangent, "gate_up": _orthonormal_up(gate_tangent, station.up),
		"start_position": start_position, "start_tangent": tangent, "start_up": start_up,
		"start_speed_mps": start_speed, "start_psi_rad": psi_start,
		"speed_ceiling_mps": start_speed, "terrain": plan.get("terrain", {})}
	# The heading box is a feasibility bound, so it is built at the shortest allocable arc and at
	# a speed the chain reaches rather than at the speed handed over: a descending role enters
	# faster than the start, and a box built under that would let the solve walk into a region the
	# accepted chain is then refused from, with no retry to recover. The nominal chain measures
	# that speed. It is not an upper bound over the whole control box - the elevation controls can
	# descend further than the nominal split - so the accepted chain is still re-checked against
	# each turn's own allocated arc and entry speed, and names the shortfall if it drifts past.
	for role: Dictionary in _chain(context, nominal).roles:
		context.speed_ceiling_mps = maxf(float(context.speed_ceiling_mps),
			float(role.entry_speed_mps))
	var heading_budget := 0.0
	for index in order.size():
		var band: Vector2 = length_bands[index]
		var bound := 0.5 * band.x * sin(PITCH_CEILING_RAD)
		if families[index] == TURN_FAMILY:
			bound = heading_bound_rad(band.x, float(context.speed_ceiling_mps))
			heading_budget += bound
		lower.append(-bound)
		upper.append(bound)
		nominal[index] = clampf(float(nominal[index]), -bound, bound)
	lower.append(budget.x)
	upper.append(budget.y)
	if absf(heading_request) > heading_budget:
		return {"ok": false, "errors": [{"code": "heading_request",
			"requested_rad": heading_request, "bound_rad": heading_budget,
			"shortfall_rad": absf(heading_request) - heading_budget}]}
	return context


## The return budget is a band, not a number: the route band gives it bounds once the prefix
## distance and the reserved terminal approach are subtracted, intersected with what the role
## bands can actually absorb so every proposed total is allocatable.
static func _budget(route_band: Vector2, prefix_m: float, approach_m: float,
		length_bands: Array) -> Vector2:
	var lower := 0.0
	var upper := 0.0
	for band: Vector2 in length_bands:
		lower += band.x
		upper += band.y
	return Vector2(maxf(route_band.x - prefix_m - approach_m, lower),
		minf(route_band.y - prefix_m - approach_m, upper))


## One nominal spatial chain in the planner's order. Turn roles consume signed heading change and
## height roles signed net elevation; both leave the chain level, so `sin(theta)` and the heading
## fraction below are all the geometry a macro target needs.
##
## The chain's own tangent is the single authority: every frame it publishes, the heading it
## carries into the next role, and the terminal yaw residual are all read from `_tangent` at
## `u = 1`. Nothing accumulates a commanded heading alongside it, so a published frame cannot
## drift away from the geometry the corridor polyline traces.
static func _chain(context: Dictionary, controls: Array) -> Dictionary:
	var allocation := allocate_lengths(context.nominal_lengths, context.length_bands,
		context.length_weights, float(controls[context.length_index]))
	var position: Vector3 = context.start_position
	var tangent: Vector3 = context.start_tangent
	var psi: float = context.start_psi_rad
	var energy := 0.5 * float(context.start_speed_mps) * float(context.start_speed_mps)
	var minimum_energy := energy
	var maximum_pitch := absf(asin(clampf(tangent.dot(Vector3.UP), -1.0, 1.0)))
	var terrain: Dictionary = context.terrain
	var terrain_margins := {}
	var roles: Array = []
	for index in context.order.size():
		var length: float = allocation.lengths[index] if allocation.ok \
			else context.nominal_lengths[index]
		var is_turn: bool = context.families[index] == TURN_FAMILY
		var control := float(controls[context.control_index[context.order[index]]])
		var heading_change := control if is_turn else 0.0
		var entry_position := position
		var entry_tangent := tangent
		var entry_sin_pitch := tangent.dot(Vector3.UP)
		var bump := 0.0 if is_turn else 2.0 * control / length - entry_sin_pitch
		var entry_speed := sqrt(2.0 * energy)
		var step := length / CHAIN_SAMPLES_PER_ROLE
		var centerline := PackedVector3Array([position])
		var minimum_agl := INF
		for sample in CHAIN_SAMPLES_PER_ROLE:
			var u0 := float(sample) / CHAIN_SAMPLES_PER_ROLE
			var u1 := float(sample + 1) / CHAIN_SAMPLES_PER_ROLE
			var pitch0 := _sin_pitch(entry_sin_pitch, bump, u0)
			var pitch1 := _sin_pitch(entry_sin_pitch, bump, u1)
			position += step / 6.0 * (
				_tangent(context, psi, heading_change, entry_sin_pitch, bump, u0)
				+ 4.0 * _tangent(context, psi, heading_change, entry_sin_pitch, bump,
					0.5 * (u0 + u1))
				+ _tangent(context, psi, heading_change, entry_sin_pitch, bump, u1))
			var rate0 := _energy_rate(pitch0, energy)
			energy += 0.5 * step * (rate0 + _energy_rate(pitch1, energy + step * rate0))
			minimum_energy = minf(minimum_energy, energy)
			maximum_pitch = maxf(maximum_pitch, absf(asin(clampf(pitch1, -1.0, 1.0))))
			centerline.append(position)
			if not terrain.is_empty():
				minimum_agl = minf(minimum_agl,
					position.y - RideTerrain.height(terrain, position.x, position.z))
		tangent = _tangent(context, psi, heading_change, entry_sin_pitch, bump, 1.0)
		psi = atan2(tangent.dot(context.right), tangent.dot(context.forward))
		if not terrain.is_empty():
			terrain_margins[context.order[index]] = minimum_agl
		roles.append({"length_m": length, "entry_position": entry_position,
			"entry_tangent": entry_tangent, "entry_speed_mps": entry_speed,
			"exit_position": position, "exit_tangent": tangent,
			"centerline": centerline, "heading_change_rad": heading_change,
			"elevation_change_m": position.y - entry_position.y})
	return {"ok": allocation.ok, "allocation": allocation, "roles": roles,
		"end_position": position, "end_tangent": tangent, "terrain_margins": terrain_margins,
		"maximum_pitch_rad": maximum_pitch, "gate_speed_mps": sqrt(2.0 * maxf(energy, 0.0)),
		"minimum_speed_mps": sqrt(2.0 * maxf(minimum_energy, 0.0))}


## All four residuals are read off one geometry: the chain's own end position and end tangent.
static func _residuals(context: Dictionary, controls: Array) -> Array:
	var chain := _chain(context, controls)
	var offset: Vector3 = chain.end_position - context.gate_position
	var end_tangent: Vector3 = chain.end_tangent
	return [offset.dot(context.right) / RESIDUAL_SCALES[0],
		offset.dot(Vector3.UP) / RESIDUAL_SCALES[1],
		offset.dot(context.forward) / RESIDUAL_SCALES[2],
		atan2(end_tangent.dot(context.right), end_tangent.dot(context.forward))
			/ RESIDUAL_SCALES[3]]


## Every macro contract that refuses a candidate, named with its shortfall. Nothing here is a
## residual: the solve may not spend bank, energy or terrain to reach the gate.
static func _refusals(context: Dictionary, chain: Dictionary) -> Array:
	var errors: Array = []
	if not chain.ok:
		errors.append({"code": "length_allocation", "status": str(chain.allocation.status),
			"remainder_m": float(chain.allocation.remainder_m)})
	for index in context.order.size():
		var role: Dictionary = chain.roles[index]
		if context.families[index] != TURN_FAMILY:
			continue
		var bound := heading_bound_rad(role.length_m, role.entry_speed_mps)
		if absf(role.heading_change_rad) > bound:
			errors.append({"code": "heading_bound", "role_id": context.order[index],
				"bound_rad": bound, "shortfall_rad": absf(role.heading_change_rad) - bound})
		# A turn whose heading change is exactly zero has no side to bank toward, so it cannot
		# publish the signed curvature the local turn family and its bank/curvature agreement
		# check require. Refuse it by name rather than publish a signless turn.
		if absf(role.heading_change_rad) <= 0.0:
			errors.append({"code": "degenerate_turn", "role_id": context.order[index],
				"margin_rad": absf(role.heading_change_rad)})
	if chain.maximum_pitch_rad > PITCH_CEILING_RAD:
		errors.append({"code": "pitch_ceiling",
			"shortfall_rad": chain.maximum_pitch_rad - PITCH_CEILING_RAD})
	if chain.minimum_speed_mps < MOVING_FLOOR_MPS:
		errors.append({"code": "energy_moving_floor",
			"shortfall_mps": MOVING_FLOOR_MPS - chain.minimum_speed_mps})
	for role_id: String in chain.terrain_margins:
		if float(chain.terrain_margins[role_id]) < 0.0:
			errors.append({"code": "terrain_clearance", "role_id": role_id,
				"shortfall_m": -float(chain.terrain_margins[role_id])})
	return errors


## The corridor publishes only what this stage derives: the nominal centreline a local build is
## measured against and the band its length must stay inside. A lateral or vertical half-width
## has no derivation here - the macro chain models net elevation, not a height beat's crest - so
## none is published until the measurement that consumes it is defined.
static func _assignments(context: Dictionary, chain: Dictionary) -> Array:
	var assignments: Array = []
	for index in context.order.size():
		var role: Dictionary = chain.roles[index]
		var is_turn: bool = context.families[index] == TURN_FAMILY
		assignments.append({
			"role_id": context.order[index],
			"family": context.families[index],
			"entry_frame": _frame(role.entry_position, role.entry_tangent,
				context.start_up if index == 0 else Vector3.UP),
			"exit_frame": _frame(role.exit_position, role.exit_tangent, Vector3.UP),
			"target_length_m": role.length_m,
			"corridor": {"centerline_m": role.centerline,
				"length_band_m": context.length_bands[index]},
			"terrain_intent": context.terrain_intents[index],
			"curvature_sign": signf(role.heading_change_rad) if is_turn else 0.0,
			"heading_change_rad": role.heading_change_rad,
			"elevation_change_m": role.elevation_change_m,
		})
	return assignments


static func _report(context: Dictionary, chain: Dictionary, solved: Dictionary) -> Dictionary:
	var controls := {}
	var heading_bounds := {}
	var entry_speeds := {}
	for index in context.control_ids.size():
		controls[context.control_ids[index]] = float(solved.x[index])
	for index in context.order.size():
		var role: Dictionary = chain.roles[index]
		entry_speeds[context.order[index]] = role.entry_speed_mps
		if context.families[index] == TURN_FAMILY:
			heading_bounds[context.order[index]] = heading_bound_rad(role.length_m,
				role.entry_speed_mps) - absf(role.heading_change_rad)
	return {"status": str(solved.status), "evaluations": int(solved.evaluations),
		"gate_offset_m": chain.end_position - context.gate_position,
		"iterations": int(solved.iterations), "max_evaluations": RideReturnSolve.MAX_RETURN_EVALUATIONS,
		"controls": controls, "scaled_residuals": solved.residuals.duplicate(),
		"return_length_band_m": context.budget_m, "heading_bound_margin_rad": heading_bounds,
		"role_entry_speed_mps": entry_speeds, "speed_ceiling_mps": context.speed_ceiling_mps,
		"gate_speed_mps": chain.gate_speed_mps,
		"minimum_speed_mps": chain.minimum_speed_mps, "maximum_pitch_rad": chain.maximum_pitch_rad}


static func _length_margin(context: Dictionary, chain: Dictionary) -> float:
	var budget: Vector2 = context.budget_m
	var total: float = _sum(chain.allocation.lengths) if chain.ok else budget.x
	var margin := minf(total - budget.x, budget.y - total)
	for index in context.order.size():
		var band: Vector2 = context.length_bands[index]
		var length: float = chain.roles[index].length_m
		margin = minf(margin, minf(length - band.x, band.y - length))
	return margin


## A refusal publishes the same measurement a success does, so the shortfall that refused it is
## named rather than inferred.
static func _refused(errors: Array, report: Dictionary = {}) -> Dictionary:
	return _freeze({"ok": false, "assignments": [], "terminal_gate": {},
		"target_total_length_m": 0.0, "length_budget_margin_m": 0.0, "terrain_margins": {},
		"energy_margins": {}, "report": report, "errors": errors})


static func _tangent(context: Dictionary, psi: float, heading_change: float,
		entry_sin_pitch: float, bump: float, u: float) -> Vector3:
	var sin_pitch := _sin_pitch(entry_sin_pitch, bump, u)
	var cos_pitch := sqrt(maxf(1.0 - sin_pitch * sin_pitch, 0.0))
	var heading := psi + heading_change * _heading_fraction(u)
	return ((context.forward as Vector3) * cos(heading)
		+ (context.right as Vector3) * sin(heading)) * cos_pitch + Vector3.UP * sin_pitch


## `sin(theta)` over one role: a quintic ramp from the entry pitch to a level exit plus a
## symmetric quintic bump. Both terms have zero value, slope and curvature at `u = 1`, and each
## integrates to half its amplitude, so the bump that delivers a net elevation change is closed
## form rather than another solve.
static func _sin_pitch(entry_sin_pitch: float, bump: float, u: float) -> float:
	return clampf(entry_sin_pitch * (1.0 - _quintic(u)) + bump * _bump(u), -1.0, 1.0)


static func _energy_rate(sin_pitch: float, energy: float) -> float:
	return -Motion.G0 * sin_pitch - RideProgram.ROLLING_MPS2 - 2.0 * RideProgram.AERO_PER_M * energy


static func _quintic(u: float) -> float:
	var c := clampf(u, 0.0, 1.0)
	return c * c * c * (10.0 + c * (-15.0 + 6.0 * c))


static func _quintic_integral(u: float) -> float:
	var c := clampf(u, 0.0, 1.0)
	return c * c * c * c * (2.5 + c * (-3.0 + c))


static func _bump(u: float) -> float:
	return _quintic(2.0 * u) if u <= 0.5 else _quintic(2.0 - 2.0 * u)


## The fraction of a role's heading change delivered by arc `u`: the integral of a shouldered
## plateau, so `kappa_yaw = cos(theta) d(psi)/ds` starts and ends at zero with zero slope.
static func _heading_fraction(u: float) -> float:
	var c := clampf(u, 0.0, 1.0)
	var area := 0.0
	if c <= SHOULDER_FRACTION:
		area = SHOULDER_FRACTION * _quintic_integral(c / SHOULDER_FRACTION)
	elif c <= 1.0 - SHOULDER_FRACTION:
		area = 0.5 * SHOULDER_FRACTION + c - SHOULDER_FRACTION
	else:
		area = 1.0 - 1.5 * SHOULDER_FRACTION \
			+ SHOULDER_FRACTION * (0.5 - _quintic_integral((1.0 - c) / SHOULDER_FRACTION))
	return area / LOADED_ARC_FRACTION


static func _frame(position: Vector3, tangent: Vector3, up: Vector3) -> Dictionary:
	return {"position_m": position, "tangent": tangent.normalized(),
		"rider_up": _orthonormal_up(tangent.normalized(), up)}


static func _orthonormal_up(tangent: Vector3, up: Variant) -> Vector3:
	var candidate: Vector3 = up if up is Vector3 else Vector3.UP
	return (candidate - tangent * candidate.dot(tangent)).normalized()


static func _role(roles: Array, role_id: String) -> Dictionary:
	for role: Dictionary in roles:
		if str(role.get("id", "")) == role_id:
			return role
	return {}


static func _projected(nominals: Array, bands: Array, weights: Array,
		lambda_value: float) -> Array:
	var lengths: Array = []
	for index in nominals.size():
		var band: Vector2 = bands[index]
		lengths.append(clampf(float(nominals[index]) + lambda_value * float(weights[index]),
			band.x, band.y))
	return lengths


static func _allocation(ok: bool, status: String, lengths: Array, lambda_value: float,
		remainder_m: float) -> Dictionary:
	return {"ok": ok, "status": status, "lengths": lengths, "lambda": lambda_value,
		"remainder_m": remainder_m}


static func _ones(count: int) -> Array:
	var values: Array = []
	for _index in count:
		values.append(1.0)
	return values


static func _sum(values: Array) -> float:
	var total := 0.0
	for value in values:
		total += float(value)
	return total


static func _freeze(value: Variant) -> Variant:
	if value is Dictionary:
		for key in value:
			_freeze(value[key])
		value.make_read_only()
	elif value is Array:
		for item in value:
			_freeze(item)
		value.make_read_only()
	return value
