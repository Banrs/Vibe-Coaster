class_name RideReturnElements
extends RefCounted

## One accepted macro assignment becomes one integrated return element. Each family authors its
## own spatial curvature and twist over arc length and hands the result to `Motion.integrate`,
## which stays the sole centreline authority: the preview below is a target, and a build that
## disagrees with it is refused rather than corrected. A builder owns nothing outside its own
## assignment - no route total, no station pose, no neighbouring role's length.
##
## Curvature basis (design 2026-08-22 section 3): world-referenced pitch/yaw, so `kappa_pitch < 0`
## at a crest and `d(psi)/ds = kappa_yaw / cos(theta)` with `psi` measured about world-up in the
## same sense `RideReturnLayout` uses. Because the basis is referenced to world-up rather than to
## rider-up, twist changes how the geometry is felt without tilting the planned turn plane, which
## is why the turn's centreline is a function of arc length alone.
##
## Two families:
##
## - `return_turn` traces one semantic span of yaw curvature - a quintic shoulder, a loaded core,
##   a quintic shoulder at 20/60/20 of the allocated arc. The two shoulders integrate to one
##   whole, so the peak needs no solve: `kappa_peak = heading_change_rad / (0.8 target_length_m)`.
##   Its one solved scalar is peak bank, and it is solved to the counter-lateral band rather than
##   to balance: `CLAUDE.md` names two overbanked turns on the return, so a laterally neutral turn
##   is a contract failure here.
## - `return_height` traces one fixed vertical plane through the entry tangent with zero yaw
##   curvature and zero twist. Its pitch curvature is one staged narrative through the knots
##   `[0, pull_up, crest, pullout, 0]`; every knot joins two quintics whose value, spatial slope
##   and spatial acceleration all agree there, so the stages are numerical knots of one motion and
##   never a pulse restart, a neutral pause or a micro-hold.
##
## Both families enter and leave at zero curvature, zero curvature slope and zero curvature
## acceleration, which is what lets adjacent elements meet the C4 seam contract.

const Motion := preload("res://motion.gd")
const BoundedSolver := preload("res://bounded_solver.gd")

const TURN_FAMILY := "return_turn"
const HEIGHT_FAMILY := "return_height"

## The shoulder each turn reserves at both ends, matching `RideReturnLayout.SHOULDER_FRACTION`:
## the macro heading bound and this family must reserve the same arc or the frame the layout
## assigns is not one this family can reach.
const SHOULDER_FRACTION := 0.2
const LOADED_ARC_FRACTION := 1.0 - SHOULDER_FRACTION
## Arc fractions of the height beat's four curvature stages: pull-up, into the crest, out of the
## crest, pullout. Half-arc and whole-arc boundaries both fall on a stage edge, which is what lets
## the nominal below be a closed-form linear solve instead of another iteration.
const HEIGHT_FRACTIONS := [0.2, 0.3, 0.3, 0.2]

## The Falcon's Flight counterpart the return turn reproduces: 77 deg of bank held at 2.39 g,
## whose balanced bank at that speed and radius would be 65.8 deg, so
## `l = (n cos(phi) - 1) / sin(phi) = -0.47 g` presses the rider down the bank. The band is the
## shape contract; it sits far inside the +-4.7 Gy envelope and is never a closure device.
const COUNTER_LATERAL_BAND_G := Vector2(0.2, 0.6)
const COUNTER_LATERAL_TARGET_G := 0.47
const COUNTER_LATERAL_TOLERANCE_G := 0.001
## The same 77 deg. It is not a free choice: the macro heading bound admits
## `v^2 kappa / g0 <= tan(66 deg) = 2.246`, and reaching -0.47 g of counter-lateral at bank `phi`
## needs `v^2 kappa / g0 <= (sin(phi) - 0.47) / cos(phi)`, which equals 2.242 at 77 deg. Any lower
## ceiling would refuse turns the layout is entitled to assign.
const TURN_BANK_CEILING_RAD := 77.0 * PI / 180.0

## The return height beat's authored airtime value, `-0.45 g` - the same value the story's first
## height beat holds before its per-seed unload scale is applied. An assignment that carries its
## own drawn `unload_g` overrides it.
const DEFAULT_UNLOAD_G := -0.45
const UNLOAD_TOLERANCE_G := 0.01
## Curvature bounds for the height solve, stated as loads rather than as radii: the pull-up and
## pullout may not ask for more than the 4.0 g held normal limit the macro stage also reasons
## against, and the crest may not unload past -1.0 g, which is twice the deepest authored airtime.
const NORMAL_CEILING_G := 4.0
const AIRTIME_FLOOR_G := -1.0

## Seam tolerances (design 2026-08-22 section 4), to be confirmed by measurement once the first
## fleet is green.
const POSITION_TOLERANCE_M := 0.001
const TANGENT_TOLERANCE := 0.0001
const CURVATURE_TOLERANCE_M_INV := 0.00001
const TWIST_TOLERANCE_RAD := 0.000001

## Endpoint tolerances the local residuals are converged against.
const PITCH_TOLERANCE_RAD := 0.0004
const ELEVATION_TOLERANCE_M := 0.1
const HEADING_TOLERANCE_RAD := 0.001
const BANK_TOLERANCE_RAD := 0.0001
## A distance span ends on its declared length to a part in 1e-6 of a metre, so the allocated arc
## is a construction result rather than a solved one; this only guards against a builder that
## stopped emitting one of its stages.
const LENGTH_TOLERANCE_M := 0.001
## Residual scales, so "converged" means one thing: 0.02 scaled is 0.0004 rad of exit pitch,
## 0.1 m of elevation and 0.01 g of crest unload.
const HEIGHT_RESIDUAL_SCALES := [0.02, 5.0, 0.5]

## Corridor compliance. Task 3 publishes a nominal centreline and a length band but no half-width,
## and the nominal models a role's net heading and net elevation rather than the crest a height
## beat rises through, so the two centrelines differ by the beat's prominence by construction.
## Five percent of the allocated arc is the stated stand-in that admits that difference at the
## declared role lengths while still refusing a centreline that has left its corridor. It is not a
## derived half-width, and it is the first thing to replace when the layout publishes one.
const CORRIDOR_TOLERANCE_FRACTION := 0.05
## Zero yaw curvature makes a height beat planar by construction, so what the planarity
## measurement can find is float32 position quantisation: one ulp at these coordinates is about
## 3e-5 m and the samples accumulate it, so the slack is stated per metre of arc rather than as a
## fixed distance that a longer beat would fail on representation alone.
const PLANARITY_TOLERANCE_FRACTION := 0.00001

## `BoundedSolver.solve` costs `1 + K(n + 1) + R` unique evaluations. The height beat's three
## controls with K <= 8 accepted iterations and R <= 8 rejections give 1 + 8*4 + 8 = 41. The turn's
## one control is a monotone bracket - lateral load falls strictly as bank rises - so it uses the
## same 32-evaluation cap the terminal's one-dimensional brake bracket declares; it converges in
## about eleven.
const MAX_HEIGHT_EVALUATIONS := 41
const MAX_TURN_EVALUATIONS := 32


## The assignment's target centreline: the same integrator with gravity and resistance removed.
## Commanded curvature makes the geometry a function of arc length alone, so the nominal speed
## this traces at cannot appear in the result.
static func preview(assignment: Dictionary, step_m: float = 1.0) -> Dictionary:
	var errors := _validate(assignment)
	if not is_finite(step_m) or step_m <= 0.0:
		errors.append({"code": "invalid_step", "step_m": step_m})
	if not errors.is_empty():
		return {"ok": false, "centerline_m": PackedVector3Array(), "end_frame": {},
			"length_m": 0.0, "heading_change_rad": 0.0, "elevation_change_m": 0.0,
			"controls": [], "errors": errors}
	var frame: Dictionary = assignment.entry_frame
	var tangent: Vector3 = (frame.tangent as Vector3).normalized()
	var length := float(assignment.target_length_m)
	var controls: Array = []
	var spans: Array = []
	if str(assignment.family) == TURN_FAMILY:
		controls = [0.0]
		spans = _turn_spans(assignment, _turn_curvature(assignment), 0.0)
	else:
		# The nominal crest sits at the middle of the allocated arc: the third geometric statement
		# that replaces the build's unload target, which no speed-free trace can measure.
		var half := _pitch_area(0.5)
		controls = _height_nominal(_pitch(tangent), length,
			float(assignment.elevation_change_m),
			[length * float(half[0]), length * float(half[1]), length * float(half[2])],
			-_pitch(tangent))
		spans = _height_spans(assignment, controls)
	var nominal_speed := 10.0
	var route := Motion.integrate({"position_m": frame.position_m, "tangent": tangent,
		"rider_up": frame.rider_up, "speed_mps": nominal_speed, "distance_m": 0.0,
		"time_s": 0.0}, spans, {"step_s": step_m / nominal_speed,
		"gravity_mps2": Vector3.ZERO, "rolling_mps2": 0.0, "aero_per_m": 0.0,
		"measure_dense_output": false})
	if not route.ok:
		return {"ok": false, "centerline_m": PackedVector3Array(), "end_frame": {},
			"length_m": 0.0, "heading_change_rad": 0.0, "elevation_change_m": 0.0,
			"controls": controls, "errors": [{"code": "preview_integration",
				"detail": str(route.errors)}]}
	return {"ok": true, "centerline_m": route.position_m.duplicate(),
		"end_frame": {"position_m": route.position_m[-1], "tangent": route.tangent[-1],
			"rider_up": route.rider_up[-1]},
		"length_m": float(route.distance_m[-1]),
		"heading_change_rad": _heading_change(tangent, route.tangent[-1]),
		"elevation_change_m": route.position_m[-1].y - route.position_m[0].y,
		"controls": controls, "errors": []}


## One assignment plus the integrated entry state becomes one accepted element, or one structured
## local failure with its margins named. A failure never moves an upstream anchor, spends another
## role's length, selects another story or enlarges a solve.
static func build(start: Dictionary, assignment: Dictionary, settings: Dictionary) -> Dictionary:
	var errors := _validate(assignment)
	if errors.is_empty():
		errors = _validate_corridor(assignment)
	if errors.is_empty():
		errors = _validate_start(start)
	if not errors.is_empty():
		return _refused(errors, 0)
	var evaluations := [0]
	var solved: Dictionary = _solve_turn(start, assignment, settings, evaluations) \
		if str(assignment.family) == TURN_FAMILY \
		else _solve_height(start, assignment, settings, evaluations)
	if not solved.ok:
		return _refused(solved.errors, evaluations[0])
	var route: Dictionary = solved.route
	var observation := _observe(assignment, solved, route)
	var margins := _margins(assignment, observation)
	for name: String in margins:
		var margin := float(margins[name])
		if not is_finite(margin) or margin < 0.0:
			errors.append({"code": "margin", "margin": name, "value": margin,
				"role_id": assignment.role_id})
	return {"ok": errors.is_empty(), "spans": solved.spans, "trajectory": route,
		"end_state": _end_state(route), "observation": observation, "margins": margins,
		"evaluation_count": evaluations[0], "errors": errors}


## The seam evidence, split by the order at which each part is measurable: position, tangent and
## the world curvature vector are compared directly from both integrated routes, while the third
## and fourth position derivatives come from each side's published analytic jets. Differencing
## float32 positions at production spacing measures rounding at those orders, so the finite
## difference below is published as a coarse sanity value and decides nothing.
static func seam_residuals(previous: Dictionary, next: Dictionary) -> Dictionary:
	var exit_jets: Dictionary = previous.observation.exit_jets
	var entry_jets: Dictionary = next.observation.entry_jets
	var before: Dictionary = _sample(previous.trajectory, previous.trajectory.time_s.size() - 1)
	var after: Dictionary = _sample(next.trajectory, 0)
	var residuals := {
		"position_m": before.position_m.distance_to(after.position_m),
		"tangent": before.tangent.distance_to(after.tangent),
		"curvature_m_inv": exit_jets.curvature.distance_to(entry_jets.curvature),
		"integrated_curvature_m_inv": before.curvature.distance_to(after.curvature),
		"curvature_slope_m2": exit_jets.curvature_slope.distance_to(entry_jets.curvature_slope),
		"curvature_acceleration_m3": exit_jets.curvature_acceleration.distance_to(
			entry_jets.curvature_acceleration),
		"twist_rad": absf(float(exit_jets.twist) - float(entry_jets.twist)),
		"twist_slope_rad_m": absf(float(exit_jets.twist_slope)
			- float(entry_jets.twist_slope)),
		"twist_acceleration_rad_m2": absf(float(exit_jets.twist_acceleration)
			- float(entry_jets.twist_acceleration)),
		"finite_difference_x3_m2": _finite_difference(previous.trajectory, next.trajectory),
	}
	residuals.ok = residuals.position_m <= POSITION_TOLERANCE_M \
		and residuals.tangent <= TANGENT_TOLERANCE \
		and maxf(residuals.curvature_m_inv, residuals.integrated_curvature_m_inv) \
			<= CURVATURE_TOLERANCE_M_INV \
		and maxf(residuals.curvature_slope_m2, residuals.curvature_acceleration_m3) \
			<= CURVATURE_TOLERANCE_M_INV \
		and maxf(residuals.twist_rad, maxf(residuals.twist_slope_rad_m,
			residuals.twist_acceleration_rad_m2)) <= TWIST_TOLERANCE_RAD
	return residuals


## `kappa_peak = heading_change_rad / (0.8 target_length_m)`: the two quintic shoulders each carry
## half their arc's turning, so the loaded fraction of the allocated arc is 0.8 and no solve is
## needed to place the peak.
static func _turn_curvature(assignment: Dictionary) -> float:
	return float(assignment.heading_change_rad) \
		/ (LOADED_ARC_FRACTION * float(assignment.target_length_m))


static func _turn_spans(assignment: Dictionary, curvature_m_inv: float,
		bank_rad: float) -> Array:
	var role_id := str(assignment.role_id)
	var length := float(assignment.target_length_m)
	var shoulder := SHOULDER_FRACTION * length
	var zero := Motion.constant(0.0)
	return [
		Motion.spatial_span("%s/roll-in" % role_id, shoulder, zero,
			Motion.quintic(0.0, curvature_m_inv), zero, Motion.quintic(0.0, bank_rad)),
		Motion.spatial_span("%s/core" % role_id, length - 2.0 * shoulder, zero,
			Motion.constant(curvature_m_inv), zero, Motion.constant(bank_rad)),
		Motion.spatial_span("%s/roll-out" % role_id, shoulder, zero,
			Motion.quintic(curvature_m_inv, 0.0), zero, Motion.quintic(bank_rad, 0.0)),
	]


static func _height_spans(assignment: Dictionary, knots: Array) -> Array:
	var role_id := str(assignment.role_id)
	var length := float(assignment.target_length_m)
	var names := ["pull-up", "crest-in", "crest-out", "pullout"]
	var values := [0.0, float(knots[0]), float(knots[1]), float(knots[2]), 0.0]
	var zero := Motion.constant(0.0)
	var spans: Array = []
	for index in HEIGHT_FRACTIONS.size():
		spans.append(Motion.spatial_span("%s/%s" % [role_id, names[index]],
			float(HEIGHT_FRACTIONS[index]) * length,
			Motion.quintic(values[index], values[index + 1]), zero, zero, zero))
	return spans


## Peak bank against the counter-lateral band, bracketed rather than optimised: for a level turn
## `l = (v^2 kappa / g0) cos(phi) - sin(phi)` falls strictly as bank rises, so the bracket over
## [0, ceiling] has one root and no warm start. The bank is signed with the curvature; a bank on
## the other side is never tried, so closure can never buy itself one.
static func _solve_turn(start: Dictionary, assignment: Dictionary, settings: Dictionary,
		evaluations: Array) -> Dictionary:
	var curvature := _turn_curvature(assignment)
	var direction := signf(curvature)
	if direction == 0.0:
		return {"ok": false, "errors": [{"code": "degenerate_turn",
			"role_id": assignment.role_id}]}
	var low := 0.0
	var high := TURN_BANK_CEILING_RAD
	var bank := 0.0
	var route := {}
	var lateral := 0.0
	var spans: Array = []
	for _iteration in MAX_TURN_EVALUATIONS:
		bank = 0.5 * (low + high)
		spans = _turn_spans(assignment, curvature, direction * bank)
		route = _integrate(start, spans, settings, evaluations)
		if not route.ok:
			return {"ok": false, "errors": [{"code": "turn_integration",
				"role_id": assignment.role_id, "detail": str(route.errors)}]}
		lateral = -direction * _peak_signed(route.lateral_g)
		if absf(lateral - COUNTER_LATERAL_TARGET_G) <= COUNTER_LATERAL_TOLERANCE_G:
			break
		if lateral < COUNTER_LATERAL_TARGET_G:
			low = bank
		else:
			high = bank
	return {"ok": true, "errors": [], "route": route, "spans": spans,
		"controls": [direction * bank], "curvature_m_inv": curvature,
		"balanced_bank_rad": direction * atan(float(start.speed_mps)
			* float(start.speed_mps) * absf(curvature) / Motion.G0)}


## The height beat's three local scalars - pull-up, crest and pullout curvature - against its own
## three endpoint conditions: exit pitch, assigned elevation change, and the drawn crest unload.
## The nominal is closed form: with the crest pinned by the unload target at the entry speed, the
## small-angle exit-pitch and elevation conditions are linear in the other two knots.
static func _solve_height(start: Dictionary, assignment: Dictionary, settings: Dictionary,
		evaluations: Array) -> Dictionary:
	var speed := float(start.speed_mps)
	var entry_pitch := _pitch((start.tangent as Vector3).normalized())
	var length := float(assignment.target_length_m)
	var elevation := float(assignment.elevation_change_m)
	var unload := float(assignment.get("unload_g", DEFAULT_UNLOAD_G))
	var crest := (unload - 1.0) * Motion.G0 / (speed * speed)
	var nominal := _height_nominal(entry_pitch, length, elevation, [0.0, 1.0, 0.0], crest)
	var ceiling := NORMAL_CEILING_G * Motion.G0 / (speed * speed)
	var floor_curvature := (AIRTIME_FLOOR_G - 1.0) * Motion.G0 / (speed * speed)
	var lower := [0.0, floor_curvature, 0.0]
	var upper := [ceiling, 0.0, ceiling]
	var residual := func(x: Array) -> Array:
		var probe := _integrate(start, _height_spans(assignment, x), settings, evaluations)
		if not probe.ok:
			return [1.0e3, 1.0e3, 1.0e3]
		var measured := _height_measurements(probe)
		return [measured.exit_pitch_rad / HEIGHT_RESIDUAL_SCALES[0],
			(measured.elevation_change_m - elevation) / HEIGHT_RESIDUAL_SCALES[1],
			(measured.crest_normal_g - unload) / HEIGHT_RESIDUAL_SCALES[2]]
	var solved := BoundedSolver.solve(residual, lower, upper, nominal, MAX_HEIGHT_EVALUATIONS)
	var spans := _height_spans(assignment, solved.x)
	var route := _integrate(start, spans, settings, evaluations)
	if not solved.ok or not route.ok:
		return {"ok": false, "errors": [{"code": "height_solve",
			"role_id": assignment.role_id, "status": str(solved.status),
			"scaled_residuals": solved.residuals.duplicate(),
			"detail": str(route.get("errors", []))}]}
	return {"ok": true, "errors": [], "route": route, "spans": spans,
		"controls": solved.x.duplicate(), "unload_g": unload}


## The staged pitch knots that satisfy three linear conditions in the small-angle nominal: exit
## pitch, the assigned elevation change, and one caller-supplied third row. `theta` is linear in
## the knots because each stage is a quintic between two of them, and `y` is its integral, so the
## nominal is a 3x3 linear solve rather than another iteration.
static func _height_nominal(entry_pitch_rad: float, length_m: float, elevation_m: float,
		third_row: Array, third_rhs: float) -> Array:
	var area := _pitch_area(1.0)
	var moment := _pitch_moment()
	var matrix := [
		[length_m * float(area[0]), length_m * float(area[1]), length_m * float(area[2])],
		[length_m * length_m * float(moment[0]), length_m * length_m * float(moment[1]),
			length_m * length_m * float(moment[2])],
		third_row.duplicate(),
	]
	var rhs := [-entry_pitch_rad, elevation_m - length_m * entry_pitch_rad, third_rhs]
	var solved := BoundedSolver.linear_solve(matrix, rhs)
	return solved.x.duplicate() if solved.ok else [0.0, 0.0, 0.0]


## `integral of K_j du` over `[0, limit]` for the three knot basis shapes. A knot appears as the
## end value of one stage and the start value of the next, and a quintic's mean over a stage is
## one half, so each stage contributes half its arc to both of its knots. `limit` must fall on a
## stage boundary, which 0.5 and 1.0 both do.
static func _pitch_area(limit: float) -> Array:
	var area := [0.0, 0.0, 0.0]
	var start := 0.0
	for stage in HEIGHT_FRACTIONS.size():
		var fraction := float(HEIGHT_FRACTIONS[stage])
		if start + fraction > limit + 0.000001:
			break
		start += fraction
		if stage > 0:
			area[stage - 1] += 0.5 * fraction
		if stage < HEIGHT_FRACTIONS.size() - 1:
			area[stage] += 0.5 * fraction
	return area


## `integral of (integral of K_j) du` over the whole arc, written as `integral of K_j (1 - u) du`.
## Over one stage with `u = U + f x` the quintic weights give `integral of h x dx = 5/14` for the
## knot the stage ramps to and `1/7` for the knot it ramps from.
static func _pitch_moment() -> Array:
	var moment := [0.0, 0.0, 0.0]
	var start := 0.0
	for stage in HEIGHT_FRACTIONS.size():
		var fraction := float(HEIGHT_FRACTIONS[stage])
		if stage > 0:
			moment[stage - 1] += fraction * (0.5 * (1.0 - start) - fraction / 7.0)
		if stage < HEIGHT_FRACTIONS.size() - 1:
			moment[stage] += fraction * (0.5 * (1.0 - start) - fraction * 5.0 / 14.0)
		start += fraction
	return moment


static func _integrate(start: Dictionary, spans: Array, settings: Dictionary,
		evaluations: Array) -> Dictionary:
	evaluations[0] += 1
	var probe := settings.duplicate()
	probe.measure_dense_output = false
	return Motion.integrate(start, spans, probe)


## The height beat's endpoint measurements, taken from the integrated route: exit pitch, net
## elevation, and the deepest crest unload the beat actually reaches.
static func _height_measurements(route: Dictionary) -> Dictionary:
	var crest := INF
	for value in route.normal_g:
		crest = minf(crest, float(value))
	return {"exit_pitch_rad": _pitch(route.tangent[-1]),
		"elevation_change_m": route.position_m[-1].y - route.position_m[0].y,
		"crest_normal_g": crest}


static func _observe(assignment: Dictionary, solved: Dictionary,
		route: Dictionary) -> Dictionary:
	var is_turn := str(assignment.family) == TURN_FAMILY
	var entry_tangent: Vector3 = route.tangent[0]
	var peak_normal := -INF
	var minimum_normal := INF
	var peak_lateral := 0.0
	var peak_roll := 0.0
	var minimum_speed := INF
	var counter_bank := 0.0
	var peak_bank := 0.0
	var roll_reversals := 0
	var roll_sign := 0.0
	var direction := signf(float(solved.get("curvature_m_inv", 0.0)))
	for index in route.time_s.size():
		peak_normal = maxf(peak_normal, float(route.normal_g[index]))
		minimum_normal = minf(minimum_normal, float(route.normal_g[index]))
		peak_lateral = maxf(peak_lateral, absf(float(route.lateral_g[index])))
		peak_roll = maxf(peak_roll, absf(float(route.roll_rate_rad_s[index])))
		minimum_speed = minf(minimum_speed, float(route.speed_mps[index]))
		var bank := _bank(route.tangent[index], route.rider_up[index])
		if absf(bank) > absf(peak_bank):
			peak_bank = bank
		counter_bank = maxf(counter_bank, -direction * bank)
		var rate := float(route.roll_rate_rad_s[index])
		if absf(rate) > 0.000001:
			if roll_sign != 0.0 and signf(rate) != roll_sign:
				roll_reversals += 1
			roll_sign = signf(rate)
	var observation := {
		"role_id": assignment.role_id, "family": assignment.family,
		"arc_length_m": float(route.distance_m[-1]) - float(route.distance_m[0]),
		"duration_s": float(route.time_s[-1]) - float(route.time_s[0]),
		"controls": solved.controls.duplicate(),
		"entry_speed_mps": float(route.speed_mps[0]),
		"exit_speed_mps": float(route.speed_mps[-1]),
		"speed_change_mps": float(route.speed_mps[-1]) - float(route.speed_mps[0]),
		"minimum_speed_mps": minimum_speed,
		"heading_change_rad": _heading_change(entry_tangent, route.tangent[-1]),
		"elevation_change_m": route.position_m[-1].y - route.position_m[0].y,
		"entry_pitch_rad": _pitch(entry_tangent), "exit_pitch_rad": _pitch(route.tangent[-1]),
		"entry_bank_rad": _bank(entry_tangent, route.rider_up[0]),
		"exit_bank_rad": _bank(route.tangent[-1], route.rider_up[-1]),
		"peak_bank_rad": peak_bank, "counter_bank_rad": counter_bank,
		"roll_reversals": roll_reversals,
		"peak_normal_g": peak_normal, "minimum_normal_g": minimum_normal,
		"peak_lateral_g": peak_lateral,
		"signed_peak_lateral_g": _peak_signed(route.lateral_g),
		"peak_roll_rate_rad_s": peak_roll,
		"corridor_offset_m": _corridor_offset(route, assignment.corridor.centerline_m),
		"entry_jets": _jets(solved.spans[0], route, 0, 0.0),
		"exit_jets": _jets(solved.spans[-1], route, route.time_s.size() - 1, 1.0),
	}
	if is_turn:
		observation.balanced_bank_rad = float(solved.balanced_bank_rad)
		observation.curvature_peak_m_inv = float(solved.curvature_m_inv)
	else:
		observation.merge(_apex(route, entry_tangent))
		observation.crest_normal_g = minimum_normal
		observation.unload_g = float(solved.unload_g)
	return observation


## The crest contract: the one downward `theta = 0` crossing, its prominence above both endpoints,
## and whether the beat climbs before it and descends after it. Both endpoints are level by
## contract, so pitch is read through a deadband of the same tolerance the exit pitch is converged
## against: a pitch excursion smaller than that is the endpoint's own float32 noise, not a crest.
static func _apex(route: Dictionary, entry_tangent: Vector3) -> Dictionary:
	var count: int = route.time_s.size()
	var crossings := 0
	var apex := -1
	var state := 0.0
	var rising := 0
	for index in count:
		var pitch_sin := float(route.tangent[index].y)
		if absf(pitch_sin) <= PITCH_TOLERANCE_RAD:
			continue
		var current := signf(pitch_sin)
		if state > 0.0 and current < 0.0:
			crossings += 1
			apex = _nearest_level(route, rising, index)
		elif state < 0.0 and current > 0.0:
			crossings += 1
		if current > 0.0:
			rising = index
		state = current
	var normal := (entry_tangent.cross(Vector3.UP)).normalized()
	var out_of_plane := 0.0
	var monotone := apex >= 0
	for index in count:
		out_of_plane = maxf(out_of_plane,
			absf((route.position_m[index] - route.position_m[0]).dot(normal)))
		var climbed := float(route.tangent[index].y)
		if index < apex:
			monotone = monotone and climbed >= -PITCH_TOLERANCE_RAD
		elif index > apex:
			monotone = monotone and climbed <= PITCH_TOLERANCE_RAD
	var apex_height: float = route.position_m[apex].y if apex >= 0 else route.position_m[0].y
	var apex_rate := 0.0
	var apex_distance := 0.0
	if apex >= 0:
		apex_rate = float(route.curvature_vector_m_inv[apex].dot(
			normal.cross(route.tangent[apex])))
		apex_distance = float(route.distance_m[apex]) - float(route.distance_m[0])
	return {"pitch_zero_crossings": crossings, "apex_distance_m": apex_distance,
		"apex_height_m": apex_height, "apex_pitch_rate_m_inv": apex_rate,
		"prominence_m": apex_height - maxf(route.position_m[0].y, route.position_m[-1].y),
		"monotone_phases": monotone, "out_of_plane_m": out_of_plane}


## The sample closest to level between the last climbing sample and the first descending one:
## the apex itself sits inside the deadband, where the crossing is detected a step or two late.
static func _nearest_level(route: Dictionary, from_index: int, to_index: int) -> int:
	var apex := from_index
	for index in range(from_index, to_index + 1):
		if absf(float(route.tangent[index].y)) < absf(float(route.tangent[apex].y)):
			apex = index
	return apex


## Every contract this element must prove, as a slack: a negative or non-finite value refuses the
## element and names itself. Load slacks are taken against the briefest-duration envelope
## ceilings, which is the conservative reading; `RideVerify`'s duration-dependent curves remain
## the authority over the assembled route.
static func _margins(assignment: Dictionary, observation: Dictionary) -> Dictionary:
	var band: Vector2 = assignment.corridor.length_band_m
	var arc: float = observation.arc_length_m
	var margins := {
		"length_band_m": minf(arc - band.x, band.y - arc),
		"target_length_m": LENGTH_TOLERANCE_M
			- absf(arc - float(assignment.target_length_m)),
		"corridor_offset_m": CORRIDOR_TOLERANCE_FRACTION * float(assignment.target_length_m)
			- float(observation.corridor_offset_m),
		"normal_positive_g": RideVerify.BRIEF_POSITIVE - float(observation.peak_normal_g),
		"normal_negative_g": RideVerify.BRIEF_NEGATIVE + float(observation.minimum_normal_g),
		"lateral_g": RideVerify.BRIEF_LATERAL - float(observation.peak_lateral_g),
		"roll_rate_deg_s": RideVerify.ROLL_RATE_LIMIT
			- rad_to_deg(float(observation.peak_roll_rate_rad_s)),
		"entry_curvature_m_inv": CURVATURE_TOLERANCE_M_INV
			- float(observation.entry_jets.curvature.length()),
		"exit_curvature_m_inv": CURVATURE_TOLERANCE_M_INV
			- float(observation.exit_jets.curvature.length()),
	}
	if str(assignment.family) == TURN_FAMILY:
		var lateral := absf(float(observation.signed_peak_lateral_g))
		var direction := signf(float(assignment.heading_change_rad))
		margins.heading_change_rad = HEADING_TOLERANCE_RAD 			- absf(float(observation.heading_change_rad)
				- float(assignment.heading_change_rad))
		margins.counter_lateral_low_g = lateral - COUNTER_LATERAL_BAND_G.x
		margins.counter_lateral_high_g = COUNTER_LATERAL_BAND_G.y - lateral
		margins.counter_lateral_sign = -direction * float(observation.signed_peak_lateral_g)
		margins.bank_sign_rad = direction * float(observation.peak_bank_rad)
		margins.bank_ceiling_rad = TURN_BANK_CEILING_RAD - absf(float(observation.peak_bank_rad))
		margins.counter_bank_rad = BANK_TOLERANCE_RAD - float(observation.counter_bank_rad)
	else:
		margins.exit_pitch_rad = PITCH_TOLERANCE_RAD - absf(float(observation.exit_pitch_rad))
		margins.elevation_change_m = ELEVATION_TOLERANCE_M 			- absf(float(observation.elevation_change_m)
				- float(assignment.elevation_change_m))
		margins.crest_unload_g = UNLOAD_TOLERANCE_G - absf(
			float(observation.crest_normal_g) - float(observation.unload_g))
		margins.apex_pitch_rate_m_inv = -float(observation.apex_pitch_rate_m_inv)
		margins.prominence_m = float(observation.prominence_m)
		margins.monotone_phases = 0.0 if observation.monotone_phases else -1.0
		margins.out_of_plane_m = PLANARITY_TOLERANCE_FRACTION * arc 			- float(observation.out_of_plane_m)
	return margins


## The analytic curvature and twist jets at one element boundary, resolved in the boundary's own
## pitch/yaw basis. The world jets are `x'' = kappa`, `x''' = d(kappa)/ds` and
## `x'''' = d2(kappa)/ds2`, and the arc-length derivatives of the basis vectors are each
## proportional to `kappa` itself - `d(yaw_normal)/ds` follows from `d(t)/ds = kappa` - so at a
## boundary where `kappa` and its slope vanish the basis terms vanish with them and the world jets
## reduce to the commanded component derivatives. That precondition is measured, not assumed: the
## published `curvature` length is a refusing margin above.
static func _jets(span: Dictionary, route: Dictionary, index: int, u: float) -> Dictionary:
	var tangent: Vector3 = route.tangent[index]
	var yaw_normal := tangent.cross(Vector3.UP).normalized()
	var pitch_normal := yaw_normal.cross(tangent)
	var length := float(span.length_m)
	var pitch := Motion.profile_sample(span.pitch_curvature_m_inv, u)
	var yaw := Motion.profile_sample(span.yaw_curvature_m_inv, u)
	var twist := Motion.profile_sample(span.twist_rad, u)
	return {
		"position_m": route.position_m[index], "tangent": tangent,
		"curvature": pitch.x * pitch_normal + yaw.x * yaw_normal,
		"curvature_slope": (pitch.y * pitch_normal + yaw.y * yaw_normal) / length,
		"curvature_acceleration": (pitch.z * pitch_normal + yaw.z * yaw_normal)
			/ (length * length),
		"twist": twist.x, "twist_slope": twist.y / length,
		"twist_acceleration": twist.z / (length * length),
	}


## The coarse sanity value the spec demotes finite differencing to: a third difference of the
## published float32 positions across the seam. It is diagnostic only and carries no threshold.
static func _finite_difference(previous: Dictionary, next: Dictionary) -> float:
	var count: int = previous.position_m.size()
	if count < 3 or next.position_m.size() < 2:
		return 0.0
	var a: Vector3 = previous.position_m[count - 3]
	var b: Vector3 = previous.position_m[count - 2]
	var c: Vector3 = previous.position_m[count - 1]
	var d: Vector3 = next.position_m[1]
	var h: float = maxf(float(next.distance_m[1]) - float(next.distance_m[0]), 0.000001)
	return (d - 3.0 * c + 3.0 * b - a).length() / (h * h * h)


## The greatest distance from any integrated sample to the assigned corridor polyline.
static func _corridor_offset(route: Dictionary, centerline: PackedVector3Array) -> float:
	if centerline.size() < 2:
		return 0.0
	var offset := 0.0
	for position: Vector3 in route.position_m:
		var nearest := INF
		for index in centerline.size() - 1:
			nearest = minf(nearest, position.distance_to(Geometry3D.get_closest_point_to_segment(
				position, centerline[index], centerline[index + 1])))
		offset = maxf(offset, nearest)
	return offset


static func _end_state(route: Dictionary) -> Dictionary:
	return {"position_m": route.position_m[-1], "tangent": route.tangent[-1],
		"rider_up": route.rider_up[-1], "speed_mps": float(route.speed_mps[-1]),
		"distance_m": float(route.distance_m[-1]), "time_s": float(route.time_s[-1])}


static func _sample(route: Dictionary, index: int) -> Dictionary:
	return {"position_m": route.position_m[index], "tangent": route.tangent[index],
		"curvature": route.curvature_vector_m_inv[index]}


static func _validate(assignment: Dictionary) -> Array:
	var family := str(assignment.get("family", ""))
	if family != TURN_FAMILY and family != HEIGHT_FAMILY:
		return [{"code": "unknown_family", "family": family}]
	var frame: Variant = assignment.get("entry_frame")
	if not frame is Dictionary or not frame.get("position_m") is Vector3 \
			or not frame.get("tangent") is Vector3 or not frame.get("rider_up") is Vector3:
		return [{"code": "malformed_entry_frame", "role_id": assignment.get("role_id", "")}]
	var length := float(assignment.get("target_length_m", 0.0))
	if not is_finite(length) or length <= 0.0:
		return [{"code": "invalid_target_length", "target_length_m": length}]
	if not is_finite(float(assignment.get("heading_change_rad", NAN))) \
			or not is_finite(float(assignment.get("elevation_change_m", NAN))):
		return [{"code": "malformed_assignment", "role_id": assignment.get("role_id", "")}]
	if family == TURN_FAMILY and absf(float(assignment.heading_change_rad)) <= 0.0:
		return [{"code": "degenerate_turn", "role_id": assignment.get("role_id", "")}]
	return []


static func _validate_corridor(assignment: Dictionary) -> Array:
	var corridor: Variant = assignment.get("corridor")
	if not corridor is Dictionary or not corridor.get("length_band_m") is Vector2 \
			or not corridor.get("centerline_m") is PackedVector3Array:
		return [{"code": "malformed_corridor", "role_id": assignment.get("role_id", "")}]
	var band: Vector2 = corridor.length_band_m
	var length := float(assignment.target_length_m)
	if band.y < band.x or length < band.x or length > band.y:
		return [{"code": "corridor_length_band", "role_id": assignment.get("role_id", ""),
			"target_length_m": length, "length_band_m": band,
			"shortfall_m": maxf(band.x - length, length - band.y)}]
	return []


static func _validate_start(start: Dictionary) -> Array:
	if not start.get("position_m") is Vector3 or not start.get("tangent") is Vector3 \
			or not start.get("rider_up") is Vector3 \
			or not is_finite(float(start.get("speed_mps", NAN))) \
			or float(start.get("speed_mps", 0.0)) < Motion.MIN_MOVING_SPEED_MPS:
		return [{"code": "malformed_start_state"}]
	return []


static func _refused(errors: Array, evaluation_count: int) -> Dictionary:
	return {"ok": false, "spans": [], "trajectory": {}, "end_state": {}, "observation": {},
		"margins": {}, "evaluation_count": evaluation_count, "errors": errors}


## Heading about world-up in the sense `RideReturnLayout` measures it: positive turns the tangent
## from the entry heading toward `entry_tangent x world-up`, which is the direction positive yaw
## curvature steers.
static func _heading_change(entry_tangent: Vector3, exit_tangent: Vector3) -> float:
	var forward := (entry_tangent - Vector3.UP * entry_tangent.dot(Vector3.UP)).normalized()
	var right := forward.cross(Vector3.UP)
	return atan2(exit_tangent.dot(right), exit_tangent.dot(forward))


static func _pitch(tangent: Vector3) -> float:
	return asin(clampf(tangent.normalized().y, -1.0, 1.0))


## Bank about the tangent: positive when rider-up has tilted toward `tangent x world-up`, the same
## side positive yaw curvature turns toward.
static func _bank(tangent: Vector3, rider_up: Vector3) -> float:
	var yaw_normal := tangent.cross(Vector3.UP).normalized()
	var level := yaw_normal.cross(tangent)
	return atan2(rider_up.dot(yaw_normal), rider_up.dot(level))


static func _peak_signed(channel: PackedFloat64Array) -> float:
	var peak := 0.0
	for value in channel:
		if absf(float(value)) > absf(peak):
			peak = float(value)
	return peak
