class_name RidePrefixSolve
extends RefCounted

## The prefix capability internals: the story prefix read as a program, and the bounded closure
## solve over its four flex-span durations. Split out of `ride_program.gd` verbatim - the recipe
## these functions drive (`RideProgram._add_story_prefix`) still lives there, and
## `RideProgram.terrain_story_capability` is still the only caller.

const Motion := preload("res://motion.gd")
const BoundedSolver := preload("res://bounded_solver.gd")

## The prefix closure controls: the four flex-span durations of the story tail, every one of them
## a duration, so one solve serves both hands and no authored force value becomes a control.
const PREFIX_CONTROL_IDS := ["climb_core_s", "climb_pull_over_s", "crest_hold_s",
	"dive_approach_s"]
# Stage-2 bounds: wide enough that the solve can move real geometry, narrow enough that each span
# stays the beat it was authored as. They are not yet certified at both extremes on the fleet -
# that is the placement stage's gate.
const PREFIX_CONTROL_BOUNDS := [[6.0, 12.0], [1.6, 6.4], [0.5, 4.0], [0.4, 3.0]]
const PREFIX_SLOW_CREST_BEAT_S := 3.58159485642841
const PREFIX_SLOW_SHOULDER_S := 0.80
## Today's authored flex-span durations, verbatim: the committed seed every closure solve starts
## from, so the prefix carries no randomness of its own and an unsolved prefix is this one.
const PREFIX_SEED := [8.78838861435674, 3.20659393,
	PREFIX_SLOW_CREST_BEAT_S - 2.0 * PREFIX_SLOW_SHOULDER_S, 1.00]
const PREFIX_RESIDUAL_IDS := ["dive_edge_span_m", "tunnel_edge_span_m", "summit_rise_m",
	"record_exit_speed_mps"]
const PREFIX_RESIDUAL_SCALES := [5.0, 5.0, 5.0, 0.2]
const PREFIX_FINE_TOLERANCES := [0.25, 0.25, 0.25, 0.05]
# Derived, not guessed, exactly as MAX_RETURN_EVALUATIONS is: `BoundedSolver.solve` costs
# `1 + K*(n+1) + R` unique evaluations, so n = 4 with K <= 8 accepted iterations and R <= 8
# rejections gives 1 + 8*5 + 8 = 49; 52 carries that derivation with a three-evaluation margin,
# and `ride_program_tests.gd` gates every solve at 60% of it.
const MAX_PREFIX_EVALUATIONS := 52


## The story prefix as a program: its spans plus the span indices both the published footprint and
## the closure solve address. The act-one end is the head/tail split - every closure control lies
## downstream of it, so the head integrates once per solve and every evaluation reuses it.
static func _prefix_program(station_side: int, story: Dictionary, controls: Array) -> Dictionary:
	var spans: Array = []
	var metadata: Array = []
	var gestures: Array = []
	var propulsion := PackedInt32Array()
	RideProgram._add_story_prefix(
		spans, metadata, gestures, propulsion, -float(station_side), story, controls)
	var program := {"spans": spans, "head_end": -1, "dive_start": -1, "dive_end": -1,
		"tunnel_end": -1, "opener_end": -1, "station_end": -1}
	for gesture in gestures:
		match str(gesture.story_slot_id):
			"station-launch": program.station_end = int(gesture.last_span)
			"opener": program.opener_end = int(gesture.last_span)
			"act-one": program.head_end = int(gesture.last_span)
			"cliff-dive":
				program.dive_start = int(gesture.first_span)
				program.dive_end = int(gesture.last_span)
			"tunnel-lsm3": program.tunnel_end = int(gesture.last_span)
	program["ok"] = program.station_end >= 0 and program.opener_end > program.station_end \
		and program.head_end > program.opener_end and program.dive_start > program.head_end \
		and program.dive_end >= program.dive_start and program.tunnel_end > program.dive_end
	return program


static func _prefix_initial_state() -> Dictionary:
	return {"position_m": Vector3.ZERO, "tangent": Vector3.RIGHT, "rider_up": Vector3.UP,
		"speed_mps": 6.0, "distance_m": 0.0, "time_s": 0.0}


## The four station-local quantities the closure targets, in `PREFIX_RESIDUAL_IDS` order. Both
## spans are the outward run projected on the target's own axis; `summit_rise_m` is the dive
## entry's own height. The station height placement (`generator.gd._place_station`) is the max of
## several terrain-clearance terms; which of them binds is measured there, and every one of them is
## a function of the head and the terrain, which no control here can move. So
## `summit_agl - summit_rise_m` is a constant of the terrain and the head, and `generator.gd`
## translates the summit AGL band into this rise band through it. The tunnel exit is the
## trajectory's last sample, not the published pre-seam one, so the quantity does not move with
## the integration step; the generator aims through that one-step offset instead.
static func _prefix_observation(trajectory: Dictionary, dive_start: int, dive_end: int,
	axis: Vector2
) -> Array:
	var first: int = trajectory.span_index.find(dive_start)
	var last: int = trajectory.span_index.rfind(dive_end)
	if first < 0 or last < first or trajectory.position_m.size() < 2:
		return []
	var entry: Vector3 = trajectory.position_m[first]
	var dive_exit: Vector3 = trajectory.position_m[last]
	var tunnel_exit: Vector3 = trajectory.position_m[-1]
	return [Vector2(dive_exit.x - entry.x, dive_exit.z - entry.z).dot(axis),
		Vector2(tunnel_exit.x - dive_exit.x, tunnel_exit.z - dive_exit.z).dot(axis),
		entry.y, float(trajectory.speed_mps[-1])]


static func _prefix_tail_observation(station_side: int, story: Dictionary, controls: Array,
	head_state: Dictionary, axis: Vector2
) -> Array:
	var program := _prefix_program(station_side, story, controls)
	if not program.ok:
		return []
	var offset: int = program.head_end + 1
	var tail := Motion.integrate(head_state,
		program.spans.slice(offset, program.tunnel_end + 1),
		RideProgram._settings(RideProgram.COARSE_STEP_S))
	if not tail.get("ok", false):
		return []
	return _prefix_observation(tail, program.dive_start - offset, program.dive_end - offset, axis)


## The scaled residual vector the solver drives to zero. Called on every solver evaluation, so it
## builds nothing beyond the numbers themselves - no keyed dictionary, no format strings.
static func _prefix_residuals(observation: Array, bands: Array) -> Array:
	var scaled := []
	for index in PREFIX_RESIDUAL_IDS.size():
		scaled.append(RideProgram._band_residual(float(observation[index]), bands[index])
			/ float(PREFIX_RESIDUAL_SCALES[index]))
	return scaled


## The per-band margins every accepted or refused closure reports. Never called from the solver's
## hot loop - only once, on refusal or on the final accepted/fine observation.
static func _prefix_margins(observation: Array, bands: Array) -> Dictionary:
	var margins := {}
	for index in PREFIX_RESIDUAL_IDS.size():
		var band: Vector2 = bands[index]
		var value := float(observation[index])
		margins["%s_low" % PREFIX_RESIDUAL_IDS[index]] = value - band.x
		margins["%s_high" % PREFIX_RESIDUAL_IDS[index]] = band.y - value
	return margins


## Every prefix refusal carries the same evidence: the values it stopped on, the residual vector,
## the per-band margins and what the solver was doing. No retry, no relaxed band.
static func _prefix_refusal(reason: String, status: String, values: Array, residuals: Array,
	margins: Dictionary, evaluations: int = 0
) -> Dictionary:
	return RideProgram._failure(reason, "prefix-closure",
		{"accepted_values": values, "margins": margins,
		"solver_status": status, "target_error": residuals, "evaluation_count": evaluations})


## One bounded solve over the four flex-span durations against the target's four aim bands. Only
## the tail carries a control, so the head is integrated once at the production step and every
## evaluation re-integrates the tail alone at `COARSE_STEP_S`; the caller's own production
## integration is the fine half of the coarse/fine acceptance.
static func _solve_prefix_closure(station_side: int, story: Dictionary,
	target: Dictionary
) -> Dictionary:
	var bands := []
	for id: String in PREFIX_RESIDUAL_IDS:
		var band: Variant = target.get(id, Vector2(NAN, NAN))
		bands.append(band if band is Vector2 else Vector2(NAN, NAN))
	var supplied: Variant = target.get("outward_local", Vector2(0.0, float(station_side)))
	var axis: Vector2 = supplied if supplied is Vector2 else Vector2.ZERO
	var program := _prefix_program(station_side, story, PREFIX_SEED)
	var usable: bool = program.ok and axis.is_finite() and axis.length_squared() > 0.000001
	for band: Vector2 in bands:
		usable = usable and band.is_finite() and band.x <= band.y
	if not usable:
		return _prefix_refusal("closure target is not a usable set of station-local aim bands",
			"invalid_target", PREFIX_SEED, [], {})
	axis = axis.normalized()
	var head := Motion.integrate(_prefix_initial_state(),
		program.spans.slice(0, program.head_end + 1),
		RideProgram._settings(RideProgram.PRODUCTION_STEP_S))
	if not head.get("ok", false):
		return _prefix_refusal("prefix closure could not integrate its shared head",
			"head_integration", PREFIX_SEED, [], {})
	var head_state := RideProgram._last_state(head)
	var lower := []
	var upper := []
	for bound: Array in PREFIX_CONTROL_BOUNDS:
		lower.append(bound[0])
		upper.append(bound[1])
	var residual := func(candidate: Array) -> Array:
		var observed := _prefix_tail_observation(station_side, story, candidate, head_state, axis)
		return _prefix_residuals(observed, bands) if not observed.is_empty() else [INF]
	# Mirrors `_solve_return`: `BoundedSolver.solve`'s cap counts only its own unique
	# evaluations, but the post-solve coarse re-observation below is one more real tail
	# integration, so the cap passed here is `MAX_PREFIX_EVALUATIONS - 1` to keep the true
	# per-solve cost (solver evaluations + the one coarse re-observation) honest at the constant.
	var solved := BoundedSolver.solve(
		residual, lower, upper, PREFIX_SEED, MAX_PREFIX_EVALUATIONS - 1)
	var accepted: Array = solved.get("x", PREFIX_SEED)
	var coarse := _prefix_tail_observation(station_side, story, accepted, head_state, axis)
	if not solved.get("ok", false) or coarse.is_empty():
		return _prefix_refusal("prefix closure did not reach its terrain target",
			str(solved.get("status", "invalid")), accepted, solved.get("residuals", []),
			_prefix_margins(coarse, bands) if not coarse.is_empty() else {},
			int(solved.get("evaluations", 0)))
	return {"ok": true, "bands": bands, "axis": axis, "report": {
		"control_ids": PREFIX_CONTROL_IDS, "control_bounds": PREFIX_CONTROL_BOUNDS,
		"accepted_values": accepted, "residual_ids": PREFIX_RESIDUAL_IDS,
		"coarse_fine_tolerances": PREFIX_FINE_TOLERANCES,
		"unique_evaluations": int(solved.evaluations),
		"max_unique_evaluations": MAX_PREFIX_EVALUATIONS,
		"solver_status": str(solved.status), "solver_iterations": int(solved.iterations),
		"solver_conditioning": float(solved.conditioning),
		"coarse_observation": coarse, "target_error": solved.residuals,
		"margins": _prefix_margins(coarse, bands)}}


## The fine half: the accepted coarse solution must reproduce in the caller's own production
## integration, per residual, or the prefix is refused. Never a retry, never a widened band.
static func _accept_prefix_closure(closure: Dictionary, trajectory: Dictionary,
	program: Dictionary
) -> Dictionary:
	var report: Dictionary = closure.report
	var coarse: Array = report.coarse_observation
	var fine := _prefix_observation(trajectory, program.dive_start, program.dive_end, closure.axis)
	var agrees := fine.size() == coarse.size()
	for index in PREFIX_RESIDUAL_IDS.size():
		agrees = agrees and absf(float(fine[index]) - float(coarse[index])) \
			<= float(PREFIX_FINE_TOLERANCES[index])
	if not agrees:
		return _prefix_refusal("prefix closure coarse and fine observations disagree",
			str(report.solver_status), report.accepted_values, report.target_error,
			report.margins, int(report.unique_evaluations))
	report["fine_observation"] = fine
	report["margins"] = _prefix_margins(fine, closure.bands)
	return {"ok": true}
