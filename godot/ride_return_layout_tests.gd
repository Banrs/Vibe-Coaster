extends SceneTree

## Contract tests for the pure macro return layout: bounded length allocation, the terminal gate,
## the per-turn heading feasibility bound, every legal role order, byte determinism, immunity to
## downstream failure feedback, the passive energy bound, and terrain clearance.

const Layout := preload("res://ride_return_layout.gd")
const Elements := preload("res://ride_return_elements.gd")

const RETURN_ROLE_IDS := ["return-turn-a", "return-height-a", "return-turn-b", "return-height-b"]
const ASSIGNMENT_KEYS := ["role_id", "family", "entry_frame", "exit_frame", "target_length_m",
	"corridor", "terrain_intent", "curvature_sign", "heading_change_rad", "elevation_change_m"]
const FRAME_KEYS := ["position_m", "tangent", "rider_up"]
const CORRIDOR_KEYS := ["centerline_m", "length_band_m"]
const NOMINALS := [480.0, 420.0, 500.0, 520.0]
const BANDS := [Vector2(420.0, 620.0), Vector2(290.0, 480.0),
	Vector2(430.0, 570.0), Vector2(450.0, 590.0)]
const WEIGHTS := [1.0, 1.0, 1.0, 1.0]
const STATION_POSITION_M := Vector3(0.0, 30.0, 0.0)
const APPROACH_LENGTH_M := 230.0
## The heading the synthetic chain has to unwind. It is a request the contract admits: the turn
## family's bank ceiling is the roll the envelope allows across its shoulder, so at 82 m/s the two
## turns' shortest allocable arcs carry about 1.01 rad between them, and a request past that is
## refused at the macro stage rather than handed to a local solve.
const START_HEADING_DEG := 330.0
const START_PITCH_DEG := -6.0
const START_SPEED_MPS := 82.0
const PREFIX_DISTANCE_M := 5900.0
## A start the nominal chain lands on the gate from, then displaced so the bounded solve has real
## work to do rather than confirming its own starting point. The vertical displacement is signed
## the way the contract can absorb it: the nominal split hands both height beats half the whole
## drop, which clamps them to the floor of the crest window their family publishes, so a start that
## demanded even more descent would be asking for an assignment no legal chain can make.
const BASE_START_M := Vector3(-788.0, 80.0, 1200.0)
const SOLVE_NUDGE_M := Vector3(45.0, -12.0, -30.0)

var _errors := PackedStringArray()


func _initialize() -> void:
	_test_bounded_allocation_hits_exact_sum()
	_test_bounded_allocation_rejects_impossible_sum()
	_test_terminal_gate_comes_from_station_corridor()
	_test_heading_bound_rejects_an_infeasible_turn()
	_test_all_return_orders_close_synthetic_frames()
	_test_layout_is_byte_deterministic()
	_test_local_failure_feedback_cannot_change_layout()
	_test_energy_bound_rejects_hidden_drive()
	_test_terrain_margins_refuse_a_buried_chain()
	_test_heading_shoulders_deliver_the_whole_turn()
	_test_published_tangents_are_the_chain_tangents()
	_test_a_signless_turn_is_refused()
	_test_corridor_publishes_only_derived_bounds()
	_test_the_control_box_speed_is_not_optimistic()
	_test_the_heading_box_is_built_at_the_handover_pitch()
	_test_every_accepted_assignment_builds()
	for error in _errors:
		printerr(error)
	quit(0 if _errors.is_empty() else 1)


func _test_bounded_allocation_hits_exact_sum() -> void:
	var allocation := Layout.allocate_lengths(
		[480.0, 420.0, 500.0, 520.0],
		[Vector2(420.0, 620.0), Vector2(290.0, 480.0),
		 Vector2(430.0, 570.0), Vector2(450.0, 590.0)],
		[1.0, 1.0, 1.0, 1.0], 2000.0)
	_expect(allocation.ok, "bounded allocation is feasible")
	_expect(absf(_sum(allocation.lengths) - 2000.0) <= 0.000001,
		"bounded allocation hits the exact return budget")
	for index in BANDS.size():
		var band: Vector2 = BANDS[index]
		var length: float = allocation.lengths[index]
		_expect(length >= band.x and length <= band.y,
			"allocated role %d stays inside its declared band" % index)
	var pinned := Layout.allocate_lengths(NOMINALS, BANDS, WEIGHTS, 2260.0)
	_expect(pinned.ok and absf(_sum(pinned.lengths) - 2260.0) <= 0.000001,
		"a budget at the sum of the role maxima allocates exactly")


func _test_bounded_allocation_rejects_impossible_sum() -> void:
	var short_budget := Layout.allocate_lengths(NOMINALS, BANDS, WEIGHTS, 1000.0)
	_expect(not short_budget.ok and short_budget.status == "infeasible_total",
		"a budget under the sum of role minima is refused before bisection")
	_expect(short_budget.lengths.is_empty(),
		"an infeasible budget publishes no allocation")
	_expect(absf(short_budget.remainder_m + 590.0) <= 0.000001,
		"the infeasible budget names its signed shortfall")
	var long_budget := Layout.allocate_lengths(NOMINALS, BANDS, WEIGHTS, 3000.0)
	_expect(not long_budget.ok and long_budget.status == "infeasible_total",
		"a budget over the sum of role maxima is refused before bisection")
	_expect(not Layout.allocate_lengths(NOMINALS, BANDS, [1.0, 0.0, 1.0, 1.0], 2000.0).ok,
		"a non-positive flexibility weight is invalid input")
	_expect(not Layout.allocate_lengths(NOMINALS, BANDS, [1.0, 1.0], 2000.0).ok,
		"mismatched control cardinality is invalid input")
	_expect(not Layout.allocate_lengths(NOMINALS, BANDS, WEIGHTS, NAN).ok,
		"a non-finite budget is invalid input")


func _test_terminal_gate_comes_from_station_corridor() -> void:
	var plan := _plan()
	var result := Layout.build(_seed_start(plan, RETURN_ROLE_IDS), plan, RETURN_ROLE_IDS)
	_expect(result.ok, "the canonical order lays out")
	var gate: Dictionary = result.terminal_gate
	_expect(gate.keys() == FRAME_KEYS, "the terminal gate publishes exactly a frame")
	_expect(gate.position_m.distance_to(STATION_POSITION_M
		- Vector3(1.0, 0.0, 0.0) * APPROACH_LENGTH_M) <= 0.000001,
		"the gate sits one reserved approach behind the station")
	_expect(gate.tangent.distance_to(Vector3(1.0, 0.0, 0.0)) <= 0.000001,
		"the gate is entered along the station tangent")
	_expect(gate.rider_up.distance_to(Vector3.UP) <= 0.000001,
		"the gate is entered level and unbanked")
	var last: Dictionary = result.assignments[-1].exit_frame
	_expect(last.position_m.distance_to(gate.position_m) <= 0.1,
		"the last assignment hands the gate its position inside the residual scale")
	_expect(absf(last.tangent.dot(Vector3.UP)) <= 0.000001,
		"the last assignment hands the gate a level tangent by construction")


func _test_heading_bound_rejects_an_infeasible_turn() -> void:
	var plan := _plan()
	var start := _start(BASE_START_M, 200.0)
	var result := Layout.build(start, plan, RETURN_ROLE_IDS)
	_expect(not result.ok, "a heading request past the two turns' bound is refused")
	_expect(result.assignments.is_empty(),
		"a refused heading request publishes no assignments")
	var refusal: Dictionary = result.errors[0] if not result.errors.is_empty() else {}
	_expect(refusal.get("code", "") == "heading_request",
		"the refusal names the heading feasibility contract")
	_expect(float(refusal.get("shortfall_rad", -1.0)) > 0.0
		and float(refusal.get("bound_rad", -1.0)) > 0.0,
		"the refusal names the bound and the shortfall it missed by")
	var bound := Elements.heading_bound_rad(420.0, 82.0, 0.0)
	_expect(Elements.heading_bound_rad(620.0, 82.0, 0.0) > bound
		and Elements.heading_bound_rad(420.0, 70.0, 0.0) > bound,
		"the bound loosens with allocated arc and tightens with entry speed")


func _test_all_return_orders_close_synthetic_frames() -> void:
	var plan := _plan()
	for order: Array in _permutations(RETURN_ROLE_IDS):
		var label := str(order)
		var result := Layout.build(_seed_start(plan, order), plan, order)
		if not _expect(result.ok, "return order lays out: %s %s" % [label, str(result.errors)]):
			continue
		_expect(result.assignments.size() == order.size(),
			"assignments match the planner cardinality: %s" % label)
		_expect(result.length_budget_margin_m > 0.0,
			"length allocation keeps positive band margin: %s" % label)
		_expect(float(result.energy_margins.moving_floor_mps) > 0.0,
			"the passive energy bound keeps the train moving: %s" % label)
		for scaled: float in result.report.scaled_residuals:
			_expect(absf(scaled) <= 0.02, "every scaled residual converges: %s" % label)
		for margin: float in result.report.heading_bound_margin_rad.values():
			_expect(margin > 0.0, "every turn keeps heading feasibility margin: %s" % label)
		var total := 0.0
		for index in order.size():
			var assignment: Dictionary = result.assignments[index]
			total += float(assignment.target_length_m)
			_expect(assignment.is_read_only(),
				"the accepted assignment is immutable: %s" % label)
			_expect(assignment.keys() == ASSIGNMENT_KEYS,
				"the assignment publishes exactly the declared keys: %s" % label)
			_expect(assignment.role_id == order[index],
				"assignments keep the planner order: %s" % label)
			var band: Vector2 = _role_band(str(assignment.role_id))
			_expect(assignment.target_length_m >= band.x
				and assignment.target_length_m <= band.y,
				"the assigned length respects its role band: %s" % label)
			_expect_frame(assignment.entry_frame, "entry %s %s" % [assignment.role_id, label])
			_expect_frame(assignment.exit_frame, "exit %s %s" % [assignment.role_id, label])
			if str(assignment.family) == "return_turn":
				_expect(assignment.curvature_sign == signf(assignment.heading_change_rad)
					and absf(assignment.curvature_sign) == 1.0,
					"a turn publishes a signed curvature: %s" % label)
			else:
				_expect(assignment.curvature_sign == 0.0
					and assignment.heading_change_rad == 0.0,
					"a height beat publishes no net heading: %s" % label)
		_expect(absf(total - float(result.target_total_length_m)) <= 0.000001,
			"the allocation sums to the accepted return length: %s" % label)


func _test_layout_is_byte_deterministic() -> void:
	var plan := _plan()
	var start := _seed_start(plan, RETURN_ROLE_IDS)
	var first := Layout.build(start, plan, RETURN_ROLE_IDS)
	var second := Layout.build(start, plan, RETURN_ROLE_IDS)
	_expect(first.ok and var_to_bytes(first) == var_to_bytes(second),
		"identical requests produce byte-identical layouts")


func _test_local_failure_feedback_cannot_change_layout() -> void:
	var plan := _plan()
	var start := _seed_start(plan, RETURN_ROLE_IDS)
	var first := Layout.build(start, plan, RETURN_ROLE_IDS)
	var failures := {"return-turn-b": {"code": "local_element_infeasible", "shortfall_g": 1.4}}
	failures["return-height-a"] = {"code": "local_element_infeasible", "shortfall_m": 88.0}
	var second := Layout.build(start, plan, RETURN_ROLE_IDS)
	_expect(var_to_bytes(first) == var_to_bytes(second),
		"a local element failure record cannot move the accepted layout")
	_expect(first.is_read_only() and first.assignments.is_read_only(),
		"the accepted layout is immutable, so no downstream stage can edit it")
	_expect(failures.size() == 2, "the failure record itself is untouched")


func _test_energy_bound_rejects_hidden_drive() -> void:
	var plan := _plan()
	plan.station = {"position_m": Vector3(0.0, 260.0, 0.0), "tangent": Vector3(1.0, 0.0, 0.0),
		"up": Vector3(0.0, 1.0, 0.0)}
	var start := _start(BASE_START_M, START_HEADING_DEG)
	start.speed_mps = 12.0
	var result := Layout.build(start, plan, RETURN_ROLE_IDS)
	_expect(not result.ok,
		"a climb the passive law cannot pay for is refused instead of driven")
	_expect(_codes(result.errors).has("energy_moving_floor"),
		"the refusal names the moving floor the passive energy bound missed")


func _test_terrain_margins_refuse_a_buried_chain() -> void:
	var plan := _plan()
	plan["terrain"] = _flat_terrain(0.0)
	var clear := Layout.build(_seed_start(plan, RETURN_ROLE_IDS), plan, RETURN_ROLE_IDS)
	_expect(clear.ok and clear.terrain_margins.size() == RETURN_ROLE_IDS.size(),
		"a cleared chain publishes one terrain margin per role")
	for margin: float in clear.terrain_margins.values():
		_expect(margin > 0.0, "a cleared chain keeps positive terrain margin")
	plan["terrain"] = _flat_terrain(400.0)
	var buried := Layout.build(_seed_start(plan, RETURN_ROLE_IDS), plan, RETURN_ROLE_IDS)
	_expect(not buried.ok, "a chain inside the terrain is refused at the macro stage")
	_expect(_codes(buried.errors).has("terrain_clearance"), "the refusal names terrain clearance")


## The shouldered heading profile is one shared geometry: the arc the chain leaves unloaded is
## exactly the arc the feasibility bound reserves, and the profile delivers the whole commanded
## heading change monotonically, with no jump or reversal at either shoulder knot.
func _test_heading_shoulders_deliver_the_whole_turn() -> void:
	_expect(absf(1.0 - Elements.SHOULDER_FRACTION - Elements.LEAD_FRACTION
		- Elements.LOADED_ARC_FRACTION) <= 0.000000000001,
		"the chain's shoulders reserve exactly the arc the heading bound calls unloaded")
	_expect(absf(Elements.plateau_fraction(0.0)) <= 0.000000000001,
		"no heading is delivered before the turn starts")
	_expect(absf(Elements.plateau_fraction(1.0) - 1.0) <= 0.000000000001,
		"the whole commanded heading change is delivered by the end of the turn")
	var samples := 4001
	var previous := 0.0
	var largest_step := 0.0
	var deepest_reversal := 0.0
	for index in samples:
		var fraction := Elements.plateau_fraction(float(index) / float(samples - 1))
		deepest_reversal = maxf(deepest_reversal, previous - fraction)
		largest_step = maxf(largest_step, fraction - previous)
		previous = fraction
	_expect(deepest_reversal <= 0.000000000001,
		"the heading profile never runs backwards (deepest reversal %f)" % deepest_reversal)
	_expect(largest_step <= 2.0 / float(samples - 1),
		"the heading profile has no jump at a shoulder knot (largest step %f)" % largest_step)


## One geometry, one tangent: what an assignment publishes as its exit frame is the tangent the
## chain integrated, so the terminal yaw residual and the corridor polyline cannot disagree with
## the frames handed to the local builders.
func _test_published_tangents_are_the_chain_tangents() -> void:
	var plan := _plan()
	for order: Array in _permutations(RETURN_ROLE_IDS):
		var label := str(order)
		var result := Layout.build(_seed_start(plan, order), plan, order)
		if not _expect(result.ok, "return order lays out: %s %s" % [label, str(result.errors)]):
			continue
		var last: Dictionary = result.assignments[-1].exit_frame
		_expect(absf(atan2(last.tangent.z, last.tangent.x)) <= 0.0004,
			"the published terminal tangent is the yaw the residual scale claims: %s" % label)
		for index in result.assignments.size():
			var assignment: Dictionary = result.assignments[index]
			var centerline: PackedVector3Array = assignment.corridor.centerline_m
			_expect(_angle(centerline[-1] - centerline[-2],
				assignment.exit_frame.tangent) <= 0.01,
				"the corridor ends along the published exit tangent: %s %s"
					% [assignment.role_id, label])
			_expect(_angle(centerline[1] - centerline[0],
				assignment.entry_frame.tangent) <= 0.01,
				"the corridor starts along the published entry tangent: %s %s"
					% [assignment.role_id, label])
			if index == 0:
				continue
			var previous: Dictionary = result.assignments[index - 1].exit_frame
			_expect(previous.tangent.distance_to(assignment.entry_frame.tangent) <= 0.000001
				and previous.position_m.distance_to(assignment.entry_frame.position_m) <= 0.000001,
				"the seam frames are one frame: %s %s" % [assignment.role_id, label])


## A turn whose solved heading change is exactly zero has no sign to publish, and nothing in the
## control box excludes it. The declared interface says a turn sign is exactly -1 or 1, so the
## degenerate case is refused by name rather than published without a sign.
func _test_a_signless_turn_is_refused() -> void:
	var plan := _plan()
	var context: Dictionary = Layout._context(_seed_start(plan, RETURN_ROLE_IDS), plan,
		RETURN_ROLE_IDS)
	var controls: Array = context.nominal.duplicate()
	controls[context.control_index["return-turn-a"]] = 0.0
	var refusals: Array = Layout._refusals(context, Layout._chain(context, controls))
	_expect(_codes(refusals).has("degenerate_turn"),
		"a turn with no signed heading is refused, not published without a sign")


## The corridor publishes only bounds this stage derives. A half-width with no derivation would be
## either vacuous or wrongly tight when a local builder proves corridor compliance against it.
func _test_corridor_publishes_only_derived_bounds() -> void:
	var plan := _plan()
	var result := Layout.build(_seed_start(plan, RETURN_ROLE_IDS), plan, RETURN_ROLE_IDS)
	if not _expect(result.ok, "the canonical order lays out: %s" % str(result.errors)):
		return
	for assignment: Dictionary in result.assignments:
		_expect(assignment.corridor.keys() == CORRIDOR_KEYS,
			"the corridor publishes exactly its derived bounds: %s" % assignment.role_id)


## The heading box is a feasibility contract only if the speed it is built at is not below the
## speed the chain reaches: a box built under the chain lets the solve walk into a region the
## accepted-chain check then refuses, and no retry exists to recover from that.
func _test_the_control_box_speed_is_not_optimistic() -> void:
	var plan := _plan()
	var start := _seed_start(plan, RETURN_ROLE_IDS)
	var context: Dictionary = Layout._context(start, plan, RETURN_ROLE_IDS)
	var fastest := 0.0
	for role: Dictionary in Layout._chain(context, context.nominal).roles:
		fastest = maxf(fastest, float(role.entry_speed_mps))
	var ceiling := float(context.get("speed_ceiling_mps", 0.0))
	_expect(ceiling >= fastest - 0.000001,
		"the control box is built at or above the chain's fastest role entry")
	_expect(ceiling >= float(start.speed_mps) - 0.000001,
		"the control box is never built below the accepted entry speed")
	var result := Layout.build(start, plan, RETURN_ROLE_IDS)
	_expect(result.ok and absf(float(result.report.get("speed_ceiling_mps", 0.0)) - ceiling)
		<= 0.000001, "the accepted layout publishes the speed its heading box was built at")


## The other half of the same contract: the box is built at the handover pitch as well as at the
## chain's speed. Only the first role can be handed a pitched frame - every family exits level -
## and the turn family's bound is a strong function of it, in neither one direction nor by a small
## amount, so a box built at the level bound admits a heading the first role is then refused for
## with no retry behind it. The camelback's own 33.6 deg exit is the handover this stage is
## entered on.
func _test_the_heading_box_is_built_at_the_handover_pitch() -> void:
	var plan := _plan()
	var context: Dictionary = Layout._context(
		_start(BASE_START_M, START_HEADING_DEG, -33.6), plan, RETURN_ROLE_IDS)
	if not _expect(context.ok, "the steep handover lays out a context: %s" % str(context.errors)):
		return
	var speed := float(context.speed_ceiling_mps)
	var handover := Elements.heading_bound_rad(BANDS[0].x, speed, deg_to_rad(-33.6))
	var level := Elements.heading_bound_rad(BANDS[0].x, speed, 0.0)
	_expect(absf(handover - level) > 0.01,
		"the camelback handover is a materially different bound from the level one")
	_expect(absf(float(context.upper[0]) - handover) <= 0.000001
		and absf(float(context.lower[0]) + handover) <= 0.000001,
		"the first turn's box is the bound at the pitch it is handed")
	_expect(absf(float(context.upper[2]) - Elements.heading_bound_rad(BANDS[2].x, speed, 0.0))
		<= 0.000001,
		"a later turn's box is the level bound, because every family exits level")


## The contract between the two stages: an accepted layout is a set of assignments the element
## families build. Every legal order is laid out and then chained through the real builders, each
## element entered on the last one's integrated end state, so an assignment that only the macro
## geometry believes in is a failure here rather than a refusal with no retry behind it.
func _test_every_accepted_assignment_builds() -> void:
	var plan := _plan()
	for order: Array in _permutations(RETURN_ROLE_IDS):
		var label := str(order)
		var state := _seed_start(plan, order)
		var result := Layout.build(state, plan, order)
		if not _expect(result.ok, "return order lays out: %s %s" % [label, str(result.errors)]):
			continue
		for assignment: Dictionary in result.assignments:
			var built := Elements.build(state, assignment, _settings())
			if not _expect(built.ok, "the accepted assignment builds: %s %s %s"
					% [assignment.role_id, label, str(built.errors)]):
				break
			state = built.end_state


func _settings() -> Dictionary:
	return {"step_s": 0.01, "gravity_mps2": Vector3.DOWN * 9.80665,
		"rolling_mps2": RideProgram.ROLLING_MPS2, "aero_per_m": RideProgram.AERO_PER_M}


## The synthetic start for an order is where that order's nominal chain lands on the gate,
## displaced by a fixed nudge. Each order therefore gets a frame it can physically close from -
## a single shared frame cannot serve every plan-view topology, and height is no more shareable
## than plan view, because the elevation a role may be assigned is bounded by the crest its family
## has to stand inside it - and the solve still has to absorb the nudge.
func _seed_start(plan: Dictionary, order: Array) -> Dictionary:
	var start := _start(BASE_START_M, START_HEADING_DEG)
	for _pass in 2:
		var context: Dictionary = Layout._context(start, plan, order)
		var chain: Dictionary = Layout._chain(context, context.nominal)
		start = _start(start.position_m + context.gate_position - chain.end_position,
			START_HEADING_DEG)
	return _start(start.position_m + SOLVE_NUDGE_M, START_HEADING_DEG)


func _start(position: Vector3, heading_deg: float,
		pitch_deg: float = START_PITCH_DEG) -> Dictionary:
	var heading := deg_to_rad(heading_deg)
	var pitch := deg_to_rad(pitch_deg)
	var tangent := Vector3(cos(heading) * cos(pitch), sin(pitch), sin(heading) * cos(pitch))
	return {"position_m": position, "tangent": tangent,
		"rider_up": Vector3.UP.slide(tangent).normalized(),
		"speed_mps": START_SPEED_MPS, "distance_m": PREFIX_DISTANCE_M}


func _plan() -> Dictionary:
	var roles: Array = []
	for index in RETURN_ROLE_IDS.size():
		roles.append({"id": RETURN_ROLE_IDS[index],
			"recipe_id": "return_turn" if index % 2 == 0 else "return_height",
			"length_m": BANDS[index]})
	return {
		"station": {"position_m": STATION_POSITION_M, "tangent": Vector3(1.0, 0.0, 0.0),
			"up": Vector3(0.0, 1.0, 0.0)},
		"corridor": {"approach_length_m": APPROACH_LENGTH_M,
			"entry_speed_mps": Vector2(70.0, 80.0)},
		"route_length_m": Vector2(7800.0, 8200.0),
		"roles": roles,
	}


## A constant-height field: the apron smoothstep saturates far from its edge, so `height()`
## returns `height_m` everywhere and the terrain check is exact rather than seed-dependent.
func _flat_terrain(height_m: float) -> Dictionary:
	return {"kind": "material", "relief": height_m, "face_height": 0.0,
		"apron_height": height_m, "edge_normal": Vector2(0.0, -1.0), "edge_offset": -1000000.0,
		"apron_width": 250.0, "face_width": 45.0, "wobble_amplitude": 0.0,
		"wobble_wavelength": 500.0, "detail_amplitude": 0.0, "noise_seed": 0}


func _role_band(role_id: String) -> Vector2:
	return BANDS[RETURN_ROLE_IDS.find(role_id)]


func _permutations(values: Array) -> Array:
	if values.is_empty(): return [[]]
	var result: Array = []
	for index in values.size():
		var rest := values.duplicate()
		var head: Variant = rest.pop_at(index)
		for suffix: Array in _permutations(rest):
			result.append([head] + suffix)
	return result


func _codes(errors: Array) -> Array:
	var codes: Array = []
	for error: Dictionary in errors:
		codes.append(error.get("code", ""))
	return codes


func _angle(a: Vector3, b: Vector3) -> float:
	return acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0))


func _sum(values: Array) -> float:
	var total := 0.0
	for value in values: total += float(value)
	return total


func _expect_frame(frame: Dictionary, label: String) -> void:
	_expect(frame.keys() == FRAME_KEYS, "frame publishes exactly a frame: %s" % label)
	_expect(absf(frame.tangent.length() - 1.0) <= 0.000001
		and absf(frame.rider_up.length() - 1.0) <= 0.000001
		and absf(frame.tangent.dot(frame.rider_up)) <= 0.000001,
		"frame is orthonormal: %s" % label)


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		_errors.append(message)
	return condition
