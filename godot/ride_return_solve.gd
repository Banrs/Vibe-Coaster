class_name RideReturnSolve
extends RefCounted

## The bounded solves that close the ride: the force-authored return, the station-frame capture,
## and the brakes. Split out of `ride_program.gd` verbatim - `RideProgram.compile` is still the
## only caller, and the span bookkeeping these solves feed still lives there.

const Motion := preload("res://motion.gd")
const BoundedSolver := preload("res://bounded_solver.gd")
const RidePlanner := preload("res://ride_planner.gd")

const MAX_CAPTURE_EVALUATIONS := 40
# The planar camelback handoff is a different solve regime from the former banked handoff: its
# bounded LM path needs room for up to twenty accepted/rejected steps across nine controls. The
# 220 cap is finite and derived from that fixed iteration allowance, not an open-ended retry.
const MAX_RETURN_EVALUATIONS := 220
const RETURN_SCALAR_IDS := [
	"turn_a_bank_rad", "turn_a_core_duration_s", "height_a_recovery_duration_s",
	"turn_b_bank_rad", "turn_b_core_duration_s", "height_b_airtime_duration_s",
	"height_b_recovery_duration_s", "height_a_peak_g", "record_release_core_duration_s",
]
const RETURN_SCALAR_BOUNDS := [
	# The continuous return ramps spread the turn over 1.6-1.75 s, so the previous compact-pulse
	# 66 deg ceiling no longer describes the authored rate envelope. The 80 deg ceiling keeps the
	# loaded turn inside a real overbank band without relying on a lateral shortcut.
	[50.0 * PI / 180.0, 80.0 * PI / 180.0], [0.55, 6.00],
	# The 0.35 s height-a recovery floor stays where it is. Trimming it to ~0.30 was this stage's
	# proposed second spend and measurement refused it (2026-08-15): at a 0.30 floor the act-one
	# optional swap on seed 20260809 does converge its return - and the accepted point runs the
	# `return-height-a` role to 277.6 m against its declared 290-480 m band, so the shorter recovery
	# buys closure with a beat the route contract then rejects. What binds below the floor is that
	# role band, not the bound: a solve pinning at 0.35 is asking for a height beat shorter than the
	# story allows, and the certifiable floor is therefore above today's value, never below it.
	#
	# The second return sweep is a recovery turn after the planar camelback; a 45 deg floor keeps
	# it decisively banked without forcing an unnecessary overbank when the solved handoff needs
	# to unwind heading.
	[0.35, 6.0], [45.0 * PI / 180.0, 80.0 * PI / 180.0],
	[2.0, 16.0], [0.1, 2.0], [0.35, 6.0],
	# Height authority (2026-08-16): how hard both height beats are pulled is the eighth solved
	# control, not a fixed constant, because all seven other controls are durations and banks and
	# none of them can move the capture-gate height without moving everything else - the honest-drag
	# refusal (spec 2026-08-15-honest-drag-derivation.md section 7.2) and issue 24's floor-pinned
	# swap exhaustions both measured the solve short of that degree of freedom. Measured through
	# the production compile seam (2026-08-16, spec 2026-08-16-return-height-authority-design.md):
	# on the fifteen canonical seeds the solve settles the peak 3.725-3.941 - inside the certified
	# 3.65-3.95 draw band on every seed, never on a bound - and on the act-one optional swap it
	# clears the height_a_recovery floor-pinning on all four gated seeds (solved peaks 3.678-3.704).
	# At honest drag the freed control shrinks the capture-gate height miss (seed 11 best stall
	# -50.6 m pinned vs -13.1 m freed) but no vector closes the pose, so the bounds' ceiling is
	# exercised only by diagnostic probes. The bounds hold the beat to its authored character: the
	# 3.4 floor sits 0.25 g under the certified draw band's floor, and the 4.6 ceiling is where
	# height-b's proportional peak (x0.831) reaches 3.82, still under height-a's own draw band.
	[3.4, 4.6],
	# The record-release turn is a real banked release, not a neutral interval: its 0.8 s shoulders
	# and 2.29 s nominal core fit the 340-390 m material band while leaving the macro duration enough
	# authority to move the downstream station-local closure.
	[2.0, 2.6],
]
# Seven entries for nine controls, on purpose: this is the CI-measured seed-42 anchor for the
# in-band balanced-release branch. `_solve_return` still appends each story's certified height-a
# draw and nominal release duration.
const RETURN_SEED := [1.3798757147036, 0.89065905906544, 0.82334682821035,
	1.16271742418136, 5.69417469170743, 0.87789825123723, 4.50407852707821]
const RETURN_HEIGHT_A_PEAK_G := 3.8
const RETURN_HEIGHT_B_PEAK_G := 3.15821137151466
const RECORD_RELEASE_CORE_DURATION_S := 2.29
## The one owner of the route-length band: the generator writes it into the plan and the program
## validator checks the plan against this same constant.
const RETURN_TOTAL_LENGTH_BAND_M := Vector2(7800.0, 8200.0)
## Three metres exceeds the unchanged 0.02 * 125.0 = 2.5 m convergence slack, so this is a
## structural tightening of the route-length aim rather than a tolerance-sized suggestion.
const RETURN_LENGTH_AIM_MARGIN_M := 3.0
## The same mechanism as `RETURN_LENGTH_AIM_MARGIN_M`, applied to the one role band the return's
## own geometry owns outright. `return-turn-b` is the role whose length the solve moves most - the
## loaded arc is where a moved handoff is paid for - and it is the role the route contract refuses
## when it is paid for too heavily. Aiming this far inside the declared band is what turns "the
## contract may refuse the built turn" into a residual the solve can see while it still has
## controls to spend.
##
## Three metres, measured (2026-08-16): the canonical fleet builds the role 39-83 m inside its
## 430-570 m band on every one of the fifteen seeds, so a 3 m inset leaves every canonical
## observation strictly interior, this residual exactly 0.0, its Jacobian row identically zero,
## and the fifteen published rides bit-identical. It is also above the solver's own convergence
## slack on this channel (0.02 x the 125.0 scale = 2.5 m), so unlike the route-length margin the
## interiority an accepted point carries here is structural rather than only measured.
const RETURN_TURN_B_AIM_MARGIN_M := 3.0
## Three metres exceeds the unchanged 0.02 * 125.0 = 2.5 m convergence slack, tightening this
## role band by the same structural margin as the route-length aim.
const RECORD_RELEASE_LENGTH_AIM_MARGIN_M := 3.0
## The band a caller that declares none: no role band supplied, no constraint. `_band_residual` is
## exactly 0.0 against it, so fixed-layout fixtures keep both role-band rows inert in the
## nine-residual solve.
const RETURN_UNBOUNDED_BAND_M := Vector2(-INF, INF)
const RETURN_RESIDUAL_IDS := [
	"station_forward_m", "cross_track_m", "height_m", "tangent_right",
	"tangent_up", "route_length_band_m", "entry_speed_band_mps", "turn_b_length_band_m",
	"record_release_length_band_m",
]
const RETURN_RESIDUAL_SCALES := [5.0, 5.0, 5.0, 0.02, 0.02, 125.0, 0.1, 125.0, 125.0]
const RETURN_FINE_TOLERANCES := [0.075, 0.075, 0.075, 0.0001, 0.0001, 0.075, 0.01, 0.075, 0.075]
## The `return-turn-b` role, by the same span-id prefix `RideProgram.material_role_spans` owns it
## with. Named here rather than re-derived so the residual and the route contract cannot drift
## apart about which spans the role is.
const RETURN_TURN_B_SPAN_PREFIX := "raceway/turn-b/"
const RECORD_RELEASE_SPAN_PREFIX := "record-release-turn/"
const CAPTURE_ENTRY_SPEED_MPS := Vector2(70.0, 80.0)
## A normal-g span whose ends differ by no more than this is authored as a constant profile. It
## is an absolute tolerance well inside the 1e-6 seam gate, so no pair can be flattened here and
## still be reported as a C2 seam mismatch downstream.
const CONSTANT_PROFILE_TOLERANCE_G := 1e-9
const RETURN_ENTRY_SPEED_PADDING_MPS := 0.01
const RETURN_ENTRY_POSITION_PADDING_M := 0.25
const CAPTURE_HALF_WIDTH_M := 150.0
const CAPTURE_HALF_HEIGHT_M := 75.0
const CAPTURE_STEERING_DURATION_S := 0.45
const CAPTURE_TERMINAL_DURATION_S := 0.15
const CAPTURE_RESIDUAL_TOLERANCES := [0.05, 0.05, 0.000001, 0.000001, 0.0000025]
const CAPTURE_COARSE_RESIDUAL_TOLERANCES := [0.075, 0.075, 0.0001, 0.0001, 0.0001]
const BRAKE_SHOULDER_DURATION_S := 0.6
const BRAKE_PARAMETER_IDS := ["hold_duration_s", "peak_g"]
# Peak brake g caps at 3.6: the capture now enters near the widened 80 m/s corridor ceiling,
# and the fixed 150 m brake reserve needs ~3.0 g of it. 3.6 keeps real solve margin while
# staying inside the -Gx envelope, which allows 4.286 g over the ~3 s brake hold.
const BRAKE_PARAMETER_BOUNDS := [[0.5, 5.0], [0.0, 3.6]]
const MAX_BRAKE_EVALUATIONS := 24
const BRAKE_NEWTON_ITERATIONS := 7
const BRAKE_NEWTON_STEP := 0.95
const BRAKE_BOUNDARY_TOLERANCE_MPS := 0.0001
const BRAKE_BOUNDARY_INTERIOR_MPS := 2.0 + 0.5 * BRAKE_BOUNDARY_TOLERANCE_MPS
const TERMINAL_DISTANCE_TOLERANCE_M := 0.05
const CAPTURE_COEFFICIENT_BOUNDS := [
	[-1.5, 1.5], [-1.5, 1.5], [-0.45, 0.45], [-0.45, 0.45], [-1.2, 1.2],
]


static func _return_spans(
	v: Array, hand: float = 1.0, initial_bank_rad: float = 0.0, targets: Dictionary = {}
) -> Array:
	# Drawn per seed: how hard each return height beat is pulled and how deeply it unloads. The
	# solve still owns the durations, so a stronger beat is paid for in its own timing rather
	# than in closure, and the drawn pair reshapes ~1 km of authored return geometry.
	var height_a_airtime_g := -0.45 * RidePlanner.target(
		targets, "return-height-a", "unload_scale", 1.0)
	var height_b_airtime_g := -0.5 * RidePlanner.target(
		targets, "return-height-b", "unload_scale", 1.0)
	# The eighth control is the height-a peak; direct recipe callers may omit it and receive its
	# deterministic authored value. The ninth control is consumed by the production prefix seam.
	var height_a_peak_g := float(v[7]) if v.size() > 7 else \
		RidePlanner.target(targets, "return-height-a", "peak_g", RETURN_HEIGHT_A_PEAK_G)
	var turn_a_bank_rad := float(v[0])
	var turn_b_bank_rad := float(v[3])
	# The second beat's peak follows the first proportionally rather than drawing on its own:
	# a strongly pulled height-a paired with a weakly pulled height-b is the one corner of the
	# draw box the seven-control solve cannot close from its fixed seed (measured 2026-08-15:
	# every such corner exhausts the 220-evaluation budget while every proportional pair lands).
	var height_b_peak_g := RETURN_HEIGHT_B_PEAK_G * height_a_peak_g / RETURN_HEIGHT_A_PEAK_G
	var turn_a_normal := 1.0 / cos(turn_a_bank_rad)
	var turn_b_normal := 1.0 / cos(turn_b_bank_rad)
	var turn_a_bank_rad_signed := hand * turn_a_bank_rad
	var turn_b_bank_rad_signed := -hand * turn_b_bank_rad
	# Every bank change on the return is one continuous roll, not one saturated pulse per span
	# with flat either side (issue 20). Both return turns lay over through a ramped plateau that
	# spans the whole transition, so the peak rate is roughly half what the burst authoring spent
	# and the rider never feels the roll stop and restart inside a transition.
	var turn_a_in_s := [0.85, 0.75]
	var turn_a_in := _roll_ramp(turn_a_in_s, initial_bank_rad, turn_a_bank_rad_signed)
	# The direct unbank stays one continuous roll from the solved turn bank to level while its
	# two semantic spans retain the turn-a transition ownership.
	var turn_a_out_s := [0.85, 0.90]
	var turn_a_out := _roll_ramp(turn_a_out_s, turn_a_bank_rad_signed, 0.0)
	# Turn-b's roll-in and roll-out each span a role seam: the release into it and the pull-up out
	# of it already carried half the bank change, so blending the two halves into one roll is what
	# the real rides do through a transition.
	var turn_b_in_s := [0.70, 0.85]
	var turn_b_in := _roll_ramp(turn_b_in_s, 0.0, turn_b_bank_rad_signed)
	var turn_b_out_s := [0.85, 0.75]
	var turn_b_out := _roll_ramp(turn_b_out_s, turn_b_bank_rad_signed, 0.0)
	var spans := _roll_bank_spans(
		["raceway/turn-a/entry", "raceway/turn-a/load"], turn_a_in_s, turn_a_in, 1.0, NAN)
	spans.append(_return_span("raceway/turn-a/core", float(v[1]), turn_a_normal, turn_a_normal))
	spans.append_array(_roll_bank_spans(
		["raceway/turn-a/exit", "raceway/turn-a/unbank"],
		turn_a_out_s, turn_a_out))
	spans.append_array([
		_return_span("raceway/height-a/pullup", 0.75, 1.0, height_a_peak_g),
		_return_span("raceway/height-a/unload", 1.05, height_a_peak_g, height_a_airtime_g),
		_return_span("raceway/height-a/airtime", 0.75, height_a_airtime_g,
			height_a_airtime_g),
		_return_span("raceway/height-a/recovery", float(v[2]), height_a_airtime_g,
			height_a_peak_g),
	])
	spans.append_array(_roll_bank_spans(
		["raceway/height-a/release", "raceway/turn-b/entry"], turn_b_in_s, turn_b_in,
		height_a_peak_g))
	spans.append(_return_span("raceway/turn-b/core", float(v[4]), turn_b_normal, turn_b_normal))
	spans.append_array(_roll_bank_spans(
		["raceway/turn-b/exit", "raceway/height-b/pullup"], turn_b_out_s, turn_b_out,
		NAN, height_b_peak_g))
	# The second height beat pays for the longer turn-b roll out of its own ramps, so the return's
	# authored time is unchanged overall and the bounded solve still closes from its fixed seed.
	spans.append_array([
		_return_span("raceway/height-b/unload", 1.2, height_b_peak_g, height_b_airtime_g),
		_return_span("raceway/height-b/airtime", float(v[5]), height_b_airtime_g,
			height_b_airtime_g),
		_return_span("raceway/height-b/recovery", float(v[6]), height_b_airtime_g,
			height_b_peak_g),
		_return_span("raceway/height-b/release", 0.8, height_b_peak_g, 1.0),
	])
	return spans


## One continuous roll spread across consecutive spans: the rate ramps up, holds, and ramps back
## down as a single motion, so the bank arrives without the roll ever returning to zero between
## the spans that deliver it. Issue 20: authoring one self-contained pulse per span is what
## produced the roll -> flat -> roll stepping, and a compact pulse pays a 1.5x peak rate for the
## same bank that a ramped plateau delivers gently. The bank standing at every span boundary comes
## back with the profiles so the caller can author the matching sec(bank) load.
static func _roll_ramp(durations: Array, from_bank_rad: float, to_bank_rad: float) -> Dictionary:
	var count := durations.size()
	assert(count >= 1, "a roll ramp needs at least one span")
	var weight := 0.0
	for index in count:
		var duration := float(durations[index])
		weight += duration if index > 0 and index < count - 1 else 0.5 * duration
	if count == 1:
		# A single span cannot ramp and return, so the plateau pulse carries it: its flat centre
		# is the same held roll rate, at two thirds of the compact pulse's peak.
		weight = float(durations[0]) * Motion.PLATEAU_PULSE_AREA
	var rate := (to_bank_rad - from_bank_rad) / weight
	var profiles := []
	var banks := [from_bank_rad]
	for index in count:
		var duration := float(durations[index])
		var gained := rate * duration
		if count == 1:
			profiles.append(Motion.plateau_pulse(rate))
			gained = to_bank_rad - from_bank_rad
		elif index == 0:
			profiles.append(Motion.quintic(0.0, rate))
			gained = 0.5 * rate * duration
		elif index == count - 1:
			profiles.append(Motion.quintic(rate, 0.0))
			gained = 0.5 * rate * duration
		else:
			profiles.append(Motion.constant(rate))
		banks.append(float(banks[-1]) + gained)
	banks[count] = to_bank_rad
	return {"roll": profiles, "banks": banks, "rate_rad_s": rate}


## The spans of one continuous roll: the shared roll motion, plus the sec(bank) normal ramp each
## span needs to hold its own share of the bank change level. `entry_normal`/`exit_normal` override
## the first and last loads where the chain has to meet a neighbour that is not a level bank.
static func _roll_bank_spans(
	ids: Array, durations: Array, ramp: Dictionary, entry_normal: float = NAN,
	exit_normal: float = NAN
) -> Array:
	var banks: Array = ramp.banks
	var spans := []
	for index in ids.size():
		var from_normal := 1.0 / cos(float(banks[index]))
		var to_normal := 1.0 / cos(float(banks[index + 1]))
		if index == 0 and is_finite(entry_normal):
			from_normal = entry_normal
		if index == ids.size() - 1 and is_finite(exit_normal):
			to_normal = exit_normal
		var normal := Motion.constant(from_normal) \
			if absf(from_normal - to_normal) <= CONSTANT_PROFILE_TOLERANCE_G \
			else Motion.quintic(from_normal, to_normal)
		var transition_id := str(ids[index]).get_slice("/", 1)
		spans.append(Motion.span(str(ids[index]), float(durations[index]), "moving", normal,
			Motion.constant(0.0), Motion.constant(0.0), ramp.roll[index], transition_id))
	return spans


static func _return_span(id: String, duration_s: float, from_g: float, to_g: float,
	roll_peak_rad_s: float = 0.0) -> Dictionary:
	var normal := Motion.constant(from_g) if absf(from_g - to_g) <= CONSTANT_PROFILE_TOLERANCE_G \
		else Motion.quintic(from_g, to_g)
	var roll := Motion.constant(0.0) if absf(roll_peak_rad_s) < 0.000001 else Motion.compact_pulse(roll_peak_rad_s)
	return Motion.span(id, duration_s, "moving", normal, Motion.constant(0.0),
		Motion.constant(0.0), roll, id.get_slice("/", 1))


static func _solve_return(
	start: Dictionary, layout: Dictionary, hand: float = 1.0, seed: Array = RETURN_SEED,
	targets: Dictionary = {}, prefix_spans: Array = []
) -> Dictionary:
	var cache := {}
	var prefix_cache := {}
	var initial_bank_rad: float = _capture_residuals(start, layout)[4]
	# Ownership of the height-a peak and record-release macro, resolved: the certified per-seed draw
	# initialises the eighth control, while the ninth is the nominal macro duration. The solve owns
	# closure from the full prefix when production supplies `prefix_spans`. Each draw stays inside
	# its control's derived bounds; no randomness enters here, and the seven-entry seed is completed
	# deterministically from the build's own targets and the authored macro.
	var initial: Array = seed.duplicate()
	if initial.size() == RETURN_SCALAR_IDS.size() - 2:
		initial.append(RidePlanner.target(
			targets, "return-height-a", "peak_g", RETURN_HEIGHT_A_PEAK_G))
		initial.append(RECORD_RELEASE_CORE_DURATION_S)
	elif initial.size() == RETURN_SCALAR_IDS.size() - 1:
		initial.append(RECORD_RELEASE_CORE_DURATION_S)
	var lower := []
	var upper := []
	for bound: Array in RETURN_SCALAR_BOUNDS:
		lower.append(bound[0])
		upper.append(bound[1])
	var residual := func(candidate: Array) -> Array:
		var observed := _return_evaluation(
			start, layout, candidate, RideProgram._settings(RideProgram.PRODUCTION_STEP_S), cache,
			hand, initial_bank_rad, targets, prefix_spans, prefix_cache)
		return observed.scaled if observed.get("ok", false) else [INF]
	var solved := BoundedSolver.solve(
		residual, lower, upper, initial, MAX_RETURN_EVALUATIONS - 1)
	if not solved.get("ok", false):
		return RideProgram._failure("return did not reach its physical target", "return",
			{"evaluation_count": solved.get("evaluations", cache.size()),
				"solver_status": solved.get("status", "invalid"),
				"accepted_values": solved.get("x", []),
				"target_error": solved.get("residuals", [])})
	var parameters: Array = solved.x
	var coarse := _return_evaluation(
		start, layout, parameters, RideProgram._settings(RideProgram.FINE_STEP_S), cache, hand,
		initial_bank_rad, targets, prefix_spans, prefix_cache)
	if not coarse.get("ok", false):
		return coarse
	var fine := _return_evaluation(
		start, layout, parameters, RideProgram._settings(RideProgram.PRODUCTION_STEP_S), cache,
		hand, initial_bank_rad, targets, prefix_spans, prefix_cache)
	if not fine.ok:
		return fine
	if _maximum_absolute(fine.scaled) > 0.02:
		return RideProgram._failure("return fine solve misses its physical target", "return",
			{"evaluation_count": cache.size(), "accepted_values": parameters,
				"target_error": fine.scaled, "observed": fine.observation})
	if not _margins_are_valid(coarse.margins) or not _margins_are_valid(fine.margins):
		return RideProgram._failure("solved return misses the capture-entry basin", "return",
			{"evaluation_count": cache.size(), "accepted_values": parameters,
				"observed": fine.observation, "margins": fine.margins})
	for index in RETURN_RESIDUAL_IDS.size():
		if absf(fine.residuals[index] - coarse.residuals[index]) \
				> RETURN_FINE_TOLERANCES[index]:
			return RideProgram._failure("return coarse/fine observations disagree", "return",
				{"evaluation_count": cache.size(), "coarse": coarse.residuals,
					"fine": fine.residuals})
	var accepted_initial_bank_rad := initial_bank_rad
	var return_entry_gate_state: Dictionary = start
	var production_observation: Dictionary = fine.observation.duplicate(true)
	var production_margins: Dictionary = fine.margins.duplicate(true)
	var verification_integrations := 0
	if not prefix_spans.is_empty():
		var record_index := RETURN_SCALAR_IDS.find("record_release_core_duration_s")
		var record_duration_s := float(parameters[record_index])
		var prefix_key := "%.6f:%.12f" % [RideProgram.PRODUCTION_STEP_S, record_duration_s]
		if not prefix_cache.has(prefix_key):
			return RideProgram._failure("return production verification lacks accepted prefix cache",
				"return", {"evaluation_count": cache.size()})
		var prefix_result: Dictionary = prefix_cache[prefix_key]
		if not prefix_result.get("ok", false):
			return RideProgram._failure("return production verification has no accepted prefix",
				"return", {"evaluation_count": cache.size()})
		var accepted_prefix := _prefix_with_record_release_duration(prefix_spans, record_duration_s)
		if accepted_prefix.size() != prefix_spans.size():
			return RideProgram._failure("return production verification prefix shape mismatches",
				"return", {"evaluation_count": cache.size()})
		accepted_initial_bank_rad = float(prefix_result.initial_bank_rad)
		return_entry_gate_state = prefix_result.candidate_start
		var accepted_return_spans := _return_spans(
			parameters, hand, accepted_initial_bank_rad, targets)
		var verification_spans := accepted_prefix.duplicate()
		verification_spans.append_array(accepted_return_spans)
		var verification_route := Motion.integrate(
			start, verification_spans, RideProgram._settings(RideProgram.PRODUCTION_STEP_S))
		verification_integrations = 1
		if not verification_route.get("ok", false):
			return RideProgram._failure("return production verification failed integration", "return",
				{"evaluation_count": cache.size()})
		var production := _return_observation(verification_route, layout, verification_spans)
		production["scaled"] = []
		for index in RETURN_RESIDUAL_IDS.size():
			production.scaled.append(production.residuals[index] / RETURN_RESIDUAL_SCALES[index])
		if _maximum_absolute(production.scaled) > 0.02:
			return RideProgram._failure(
				"return production verification misses its physical target", "return",
				{"evaluation_count": cache.size(), "target_error": production.scaled,
					"observed": production.observation})
		if not _margins_are_valid(production.margins):
			return RideProgram._failure("return production verification misses true margins", "return",
				{"evaluation_count": cache.size(), "observed": production.observation,
					"margins": production.margins})
		for segmented: Dictionary in [coarse, fine]:
			for index in RETURN_RESIDUAL_IDS.size():
				if absf(production.residuals[index] - segmented.residuals[index]) \
						> RETURN_FINE_TOLERANCES[index]:
					return RideProgram._failure(
						"return segmented/production observations disagree", "return",
						{"evaluation_count": cache.size(), "segmented": segmented.residuals,
							"production": production.residuals})
			for field_and_index: Array in [
				["station_forward_m", 0], ["cross_track_m", 1], ["height_m", 2],
				["yaw_rad", 3], ["pitch_rad", 4], ["roll_rad", 4],
				["route_total_length_m", 5], ["speed_mps", 6],
				["turn_b_length_m", 7], ["record_release_length_m", 8],
			]:
				var field: String = field_and_index[0]
				var tolerance_index: int = field_and_index[1]
				if absf(float(production.observation[field])
						- float(segmented.observation[field])) \
						> RETURN_FINE_TOLERANCES[tolerance_index]:
					return RideProgram._failure(
						"return segmented/production raw observations disagree", "return",
						{"evaluation_count": cache.size(), "field": field,
							"segmented": segmented.observation[field],
							"production": production.observation[field]})
		production_observation = production.observation
		production_margins = production.margins
	var margins: Dictionary = production_margins.duplicate(true)
	for index in parameters.size():
		margins["scalar_%s" % RETURN_SCALAR_IDS[index]] = minf(
			parameters[index] - RETURN_SCALAR_BOUNDS[index][0],
			RETURN_SCALAR_BOUNDS[index][1] - parameters[index])
	return {"ok": true, "parameters": parameters, "initial_bank_rad": accepted_initial_bank_rad,
		"report": {
		"scalar_ids": RETURN_SCALAR_IDS,
		"scalar_bounds": RETURN_SCALAR_BOUNDS, "accepted_values": parameters,
		"residual_ids": RETURN_RESIDUAL_IDS,
		"coarse_fine_tolerances": RETURN_FINE_TOLERANCES,
		"unique_evaluations": cache.size(), "max_unique_evaluations": MAX_RETURN_EVALUATIONS,
		"solver_status": solved.status, "solver_iterations": solved.iterations,
		"solver_conditioning": solved.conditioning,
		"coarse_observation": coarse.observation, "fine_observation": fine.observation,
		"production_observation": production_observation,
		"verification_integrations": verification_integrations,
		"margins": margins,
		"return_entry_gate": {"source": "derived-terminal-corridor",
			"position_m": return_entry_gate_state.position_m,
			"tangent": return_entry_gate_state.tangent,
			"up": return_entry_gate_state.rider_up,
			"speed_mps": return_entry_gate_state.speed_mps,
			"corridor_approach_length_m": _approach_length(layout),
			# The one solve field that reaches the published route: it lets smoke measure this
			# budget on all fifteen seeds inside the compiles it already pays for. It repeats the
			# report's own `unique_evaluations` under a second name on purpose - the report stays
			# in the compiled program for `ride_program_tests.gd`, only the gate is published,
			# and dropping either name would change what one of those two consumers reads. The
			# gate is deep-copied into the published route (route_contract.gd) and therefore into
			# the route's SHA-256 - deleting this key breaks bit-identity, not just a reader.
			"solve_evaluations": cache.size(),
			"solve_evaluation_cap": MAX_RETURN_EVALUATIONS},
		"positive_drive_allowed": false}}


static func _maximum_absolute(values: Array) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, absf(float(value)))
	return result


static func _return_evaluation(start: Dictionary, layout: Dictionary, parameters: Array,
	settings: Dictionary, cache: Dictionary, hand: float = 1.0,
	initial_bank_rad: float = 0.0, targets: Dictionary = {}, prefix_spans: Array = [],
	prefix_cache: Dictionary = {}) -> Dictionary:
	var key := "%.6f:" % float(settings.step_s)
	for parameter in parameters:
		key += "%.12f," % float(parameter)
	if cache.has(key):
		return cache[key]
	if cache.size() >= MAX_RETURN_EVALUATIONS:
		return RideProgram._failure("return exceeded its evaluation cap", "return",
			{"evaluation_count": cache.size()})
	var candidate_start := start
	var spans := _return_spans(parameters, hand, initial_bank_rad, targets)
	var record_release_length_m := NAN
	if not prefix_spans.is_empty():
		var record_index := RETURN_SCALAR_IDS.find("record_release_core_duration_s")
		var record_duration_s := float(parameters[record_index])
		var prefix_key := "%.6f:%.12f" % [float(settings.step_s), record_duration_s]
		var prefix_result: Dictionary
		if prefix_cache.has(prefix_key):
			prefix_result = prefix_cache[prefix_key]
		else:
			var candidate_prefix := _prefix_with_record_release_duration(prefix_spans, record_duration_s)
			var prefix_route := Motion.integrate(start, candidate_prefix, settings)
			if not prefix_route.get("ok", false):
				prefix_result = {"ok": false, "errors": prefix_route.get("errors", [])}
			else:
				var prefix_start := RideProgram._last_state(prefix_route)
				prefix_result = {"ok": true, "candidate_start": prefix_start,
					"initial_bank_rad": _capture_residuals(prefix_start, layout)[4],
					"record_release_length_m": _role_arc_m(prefix_route, candidate_prefix,
						RECORD_RELEASE_SPAN_PREFIX)}
			prefix_cache[prefix_key] = prefix_result
		if not prefix_result.get("ok", false):
			var prefix_failed := RideProgram._failure("return candidate prefix failed integration", "return",
				{"evaluation_count": cache.size() + 1})
			cache[key] = prefix_failed
			return prefix_failed
		candidate_start = prefix_result.candidate_start
		initial_bank_rad = float(prefix_result.initial_bank_rad)
		record_release_length_m = float(prefix_result.record_release_length_m)
		spans = _return_spans(parameters, hand, initial_bank_rad, targets)
	var route := Motion.integrate(candidate_start, spans, settings)
	if not route.get("ok", false):
		var failed := RideProgram._failure("return candidate failed integration", "return",
			{"evaluation_count": cache.size() + 1})
		cache[key] = failed
		return failed
	var result := _return_observation(route, layout, spans, record_release_length_m)
	result["scaled"] = []
	for index in RETURN_RESIDUAL_IDS.size():
		result.scaled.append(result.residuals[index] / RETURN_RESIDUAL_SCALES[index])
	cache[key] = result
	return result


static func _prefix_with_record_release_duration(prefix_spans: Array, duration_s: float) -> Array:
	var result := prefix_spans.duplicate()
	for index in result.size():
		var span: Dictionary = result[index]
		if str(span.get("span_id", "")) != "record-release-turn/core":
			continue
		result[index] = Motion.span(str(span.span_id), duration_s, str(span.mode),
			span.normal_g, span.lateral_g, span.drive_g, span.roll_rate_rad_s,
			str(span.get("transition_id", "")))
		return result
	return []


## One role's built arc, read over exactly the window `route_contract.gd:_validate_role_lengths`
## measures: the role's first sample to the sample after its last span. The return integrates its
## own spans from index zero, so the span indices the role owns are the ones this scan finds.
static func _role_arc_m(route: Dictionary, spans: Array, prefix: String) -> float:
	var first_span := -1
	var last_span := -1
	for index in spans.size():
		if str(spans[index].span_id).begins_with(prefix):
			if first_span < 0:
				first_span = index
			last_span = index
	var first: int = route.span_index.find(first_span)
	var last: int = route.span_index.rfind(last_span)
	if first_span < 0 or first < 0 or last < first:
		return NAN
	return float(route.distance_m[mini(last + 1, route.distance_m.size() - 1)]) \
		- float(route.distance_m[first])


static func _return_observation(
	route: Dictionary, layout: Dictionary, spans: Array,
	record_release_length_m: float = NAN
) -> Dictionary:
	var state := RideProgram._last_state(route)
	var station_forward: Vector3 = layout.station_tangent.normalized()
	var station_up: Vector3 = layout.station_up.normalized()
	var station_right := station_forward.cross(station_up).normalized()
	station_up = station_right.cross(station_forward).normalized()
	var forward: float = (state.position_m - layout.station_position_m).dot(station_forward)
	var approach := _approach_length(layout)
	var capture := _capture_residuals(state, layout)
	var route_length_band: Vector2 = layout.get(
		"route_length_m", RETURN_TOTAL_LENGTH_BAND_M)
	var entry_speed_band: Vector2 = layout.get("reserved_corridor", {}).get(
		"entry_speed_mps", CAPTURE_ENTRY_SPEED_MPS)
	var total_length_m := float(route.distance_m[-1]) + approach
	var turn_b_band: Vector2 = layout.get("turn_b_length_m", RETURN_UNBOUNDED_BAND_M)
	var turn_b_length_m := _role_arc_m(route, spans, RETURN_TURN_B_SPAN_PREFIX)
	var record_release_band: Vector2 = layout.get(
		"record_release_length_m", RETURN_UNBOUNDED_BAND_M)
	if not is_finite(record_release_length_m):
		record_release_length_m = _role_arc_m(route, spans, RECORD_RELEASE_SPAN_PREFIX)
	var half_width: float = layout.get("capture_half_width_m", CAPTURE_HALF_WIDTH_M)
	var half_height: float = layout.get("capture_half_height_m", CAPTURE_HALF_HEIGHT_M)
	var residuals := [
		forward + approach - RETURN_ENTRY_POSITION_PADDING_M, capture[0], capture[1],
		state.tangent.normalized().dot(station_right),
		state.tangent.normalized().dot(station_up),
		RideProgram._band_residual(total_length_m, Vector2(
			route_length_band.x + RETURN_LENGTH_AIM_MARGIN_M,
			route_length_band.y - RETURN_LENGTH_AIM_MARGIN_M)),
		RideProgram._band_residual(float(state.speed_mps), Vector2(
			entry_speed_band.x + RETURN_ENTRY_SPEED_PADDING_MPS,
			entry_speed_band.y - RETURN_ENTRY_SPEED_PADDING_MPS)),
		RideProgram._band_residual(turn_b_length_m, Vector2(
			turn_b_band.x + RETURN_TURN_B_AIM_MARGIN_M,
			turn_b_band.y - RETURN_TURN_B_AIM_MARGIN_M)),
		0.0 if record_release_band == RETURN_UNBOUNDED_BAND_M else
			RideProgram._band_residual(record_release_length_m, Vector2(
				record_release_band.x + RECORD_RELEASE_LENGTH_AIM_MARGIN_M,
				record_release_band.y - RECORD_RELEASE_LENGTH_AIM_MARGIN_M)),
	]
	var margins := {
		"corridor_forward_low_m": forward + approach,
		"corridor_forward_high_m": -0.90 * approach - forward,
		"corridor_cross_m": half_width - absf(capture[0]),
		"corridor_height_m": half_height - absf(capture[1]),
		"corridor_yaw_rad": deg_to_rad(8.0) - absf(capture[2]),
		"corridor_pitch_rad": deg_to_rad(5.0) - absf(capture[3]),
		"corridor_roll_rad": deg_to_rad(30.0) - absf(capture[4]),
		"entry_speed_low_mps": float(state.speed_mps) - entry_speed_band.x,
		"entry_speed_high_mps": entry_speed_band.y - float(state.speed_mps),
		"route_length_low_m": total_length_m - route_length_band.x,
		"route_length_high_m": route_length_band.y - total_length_m,
	}
	return {"ok": true, "residuals": residuals, "margins": margins,
		"observation": {"station_forward_m": forward, "height_m": capture[1],
			"cross_track_m": capture[0], "yaw_rad": capture[2], "pitch_rad": capture[3],
			"roll_rad": capture[4], "speed_mps": state.speed_mps,
			"return_length_m": float(route.distance_m[-1]) - float(route.distance_m[0]),
			"turn_b_length_m": turn_b_length_m,
			"record_release_length_m": record_release_length_m,
			"route_total_length_m": total_length_m}}


static func _margins_are_valid(margins: Dictionary) -> bool:
	for margin in margins.values():
		if not is_finite(float(margin)) or float(margin) < 0.0:
			return false
	return true


static func _approach_length(layout: Dictionary) -> float:
	var corridor: Variant = layout.get("reserved_corridor")
	if corridor is Dictionary:
		return float(corridor.get("minimum_length_m", 0.0))
	return 0.0


static func _capture_spans(coefficients: Array) -> Array:
	var roll_peak: float = coefficients[4] / (
		2.0 * CAPTURE_STEERING_DURATION_S * RideProgram.COMPACT_PULSE_AREA)
	return [
		Motion.span("capture/early", CAPTURE_STEERING_DURATION_S, "moving",
			Motion.quintic(1.0, 1.0 + coefficients[2]), Motion.compact_pulse(coefficients[0]),
			Motion.constant(0.0), Motion.compact_pulse(roll_peak)),
		Motion.span("capture/late", CAPTURE_STEERING_DURATION_S, "moving",
			Motion.quintic(1.0 + coefficients[2], 1.0 + coefficients[3]),
			Motion.compact_pulse(coefficients[1]), Motion.constant(0.0),
			Motion.compact_pulse(roll_peak)),
		Motion.span("capture/terminal-shoulder", CAPTURE_TERMINAL_DURATION_S, "moving",
			Motion.quintic(1.0 + coefficients[3], 1.0), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
	]


static func _solve_capture(start: Dictionary, layout: Dictionary, settings: Dictionary) -> Dictionary:
	var coefficients: Array = layout.get("capture_seed", [0.0, 0.0, 0.0, 0.0, 0.0]).duplicate()
	if coefficients.size() != 5:
		return _capture_failure("capture seed must contain five coefficients", 0)
	var corridor: Variant = layout.get("reserved_corridor")
	if not corridor is Dictionary or not corridor.get("entry_speed_mps") is Vector2:
		return _capture_failure("capture corridor contract is incomplete", 0)
	var brake_length_m: float = float(corridor.get("brake_length_m", NAN))
	var entry_speed_mps: Vector2 = corridor.entry_speed_mps
	var forward_offset_m: float = (start.position_m - layout.station_position_m).dot(
		layout.station_tangent.normalized())
	if not is_finite(forward_offset_m) or forward_offset_m < -_approach_length(layout) \
			or forward_offset_m > -brake_length_m:
		return _capture_failure("capture entry is outside its declared partition", 0)
	if float(start.speed_mps) < entry_speed_mps.x or float(start.speed_mps) > entry_speed_mps.y:
		return _capture_failure("capture entry speed is outside its declared band", 0)
	for index in 5:
		coefficients[index] = clampf(float(coefficients[index]),
			CAPTURE_COEFFICIENT_BOUNDS[index][0], CAPTURE_COEFFICIENT_BOUNDS[index][1])
	var cache := {}
	var residuals: Array = []
	var conditioning := {}
	var evaluate := func(candidate: Array) -> Dictionary:
		return _capture_evaluation(start, layout, candidate, settings, cache)
	for _iteration in 7:
		var base := _capture_evaluation(start, layout, coefficients, settings, cache)
		if not base.ok:
			return base
		residuals = base.residuals
		if _capture_converged(residuals):
			break
		var finite_difference := _finite_difference_jacobian(coefficients, base.scaled,
			CAPTURE_COEFFICIENT_BOUNDS, [0.02, 0.02, 0.02, 0.02, 0.04], evaluate)
		if not finite_difference.ok:
			return finite_difference
		var solved := BoundedSolver.linear_solve(finite_difference.jacobian, base.scaled)
		conditioning = _conditioning(solved, coefficients)
		if not conditioning.ok:
			return _capture_failure("capture Jacobian is ill-conditioned", cache.size(),
				base.residuals, base.margins, {"conditioning": conditioning})
		var step: Array = solved.x
		for index in 5:
			coefficients[index] = clampf(coefficients[index] - step[index],
				CAPTURE_COEFFICIENT_BOUNDS[index][0], CAPTURE_COEFFICIENT_BOUNDS[index][1])
	var fine := _capture_evaluation(start, layout, coefficients, settings, cache)
	if not fine.ok:
		return fine
	if not _capture_converged(fine.residuals):
		return _capture_failure("capture did not converge: %s" % str(fine.residuals),
			cache.size(), fine.residuals, fine.margins,
			{"accepted_values": coefficients})
	var coarse_settings := settings.duplicate()
	coarse_settings.step_s = RideProgram.COARSE_STEP_S
	var coarse := _capture_evaluation(start, layout, coefficients, coarse_settings, cache)
	if not coarse.ok:
		return coarse
	if cache.size() > MAX_CAPTURE_EVALUATIONS:
		return _capture_failure("capture exceeded %d unique evaluations" %
			MAX_CAPTURE_EVALUATIONS, cache.size(), fine.residuals, fine.margins)
	if not _capture_coarse_converged(coarse.residuals) or _maximum_residual_delta(
			coarse.residuals, fine.residuals) > 0.02:
		return _capture_failure("capture coarse/fine residuals disagree", cache.size(),
			fine.residuals, fine.margins, {"coarse_residuals": coarse.residuals.duplicate()})
	if conditioning.get("evaluated_vector") != coefficients:
		if cache.size() > MAX_CAPTURE_EVALUATIONS - coefficients.size():
			return _capture_failure("capture lacks budget for accepted-point conditioning",
				cache.size(), fine.residuals, fine.margins,
				{"accepted_values": coefficients})
		var accepted_difference := _finite_difference_jacobian(
			coefficients, fine.scaled, CAPTURE_COEFFICIENT_BOUNDS,
			[0.02, 0.02, 0.02, 0.02, 0.04], evaluate)
		if not accepted_difference.ok:
			return accepted_difference
		# The accepted point needs the pivot record, not another step: the solution is discarded.
		conditioning = _conditioning(
			BoundedSolver.linear_solve(accepted_difference.jacobian, fine.scaled), coefficients)
		if not conditioning.ok:
			return _capture_failure("accepted capture Jacobian is ill-conditioned",
				cache.size(), fine.residuals, fine.margins,
				{"conditioning": conditioning, "accepted_values": coefficients})
	var margins := _capture_margins(coefficients, fine.route, layout)
	for margin in margins.values():
		if not is_finite(float(margin)) or float(margin) < 0.0:
			return _capture_failure("solved capture violates an inequality: %s" %
				str(margins), cache.size(), fine.residuals, margins,
				{"conditioning": conditioning})
	return {
		"ok": true,
		"errors": PackedStringArray(),
		"coefficients": coefficients,
		"residuals": coarse.residuals,
		"fine_residuals": fine.residuals,
		"unique_evaluations": cache.size(),
		"margins": margins,
		"conditioning": conditioning,
	}


static func _capture_evaluation(
	start: Dictionary, layout: Dictionary, coefficients: Array, settings: Dictionary,
	cache: Dictionary
) -> Dictionary:
	var key := "%.6f:" % float(settings.step_s)
	for coefficient in coefficients:
		key += "%.12f," % float(coefficient)
	if cache.has(key):
		return cache[key]
	if cache.size() >= MAX_CAPTURE_EVALUATIONS:
		return _capture_failure("capture exceeded %d unique evaluations" %
			MAX_CAPTURE_EVALUATIONS, cache.size())
	var route := Motion.integrate(start, _capture_spans(coefficients), settings)
	if not route.get("ok", false):
		var failed := _capture_failure("capture candidate failed: %s" %
			", ".join(route.get("errors", [])), cache.size() + 1)
		cache[key] = failed
		return failed
	var margins := _capture_inequality_margins(route, layout)
	var residuals := _capture_residuals(RideProgram._last_state(route), layout)
	var result := {"ok": true, "route": route, "residuals": residuals,
		"margins": margins,
		"scaled": [residuals[0] / 50.0, residuals[1] / 30.0,
			residuals[2] / 0.5, residuals[3] / 0.35, residuals[4] / 0.5]}
	cache[key] = result
	return result


static func _capture_residuals(state: Dictionary, layout: Dictionary) -> Array:
	var forward: Vector3 = layout.station_tangent.normalized()
	var station_up: Vector3 = layout.station_up.normalized()
	var right := forward.cross(station_up).normalized()
	station_up = right.cross(forward).normalized()
	var delta: Vector3 = state.position_m - layout.station_position_m
	var tangent: Vector3 = state.tangent
	var rider_up: Vector3 = state.rider_up
	var yaw := atan2(tangent.dot(right), tangent.dot(forward))
	var pitch := asin(clampf(tangent.dot(station_up), -1.0, 1.0))
	var reference_up := (station_up - tangent * station_up.dot(tangent)).normalized()
	var actual_up := (rider_up - tangent * rider_up.dot(tangent)).normalized()
	var roll := atan2(tangent.dot(reference_up.cross(actual_up)), reference_up.dot(actual_up))
	return [delta.dot(right), delta.dot(station_up), yaw, pitch, roll]


static func _capture_converged(residuals: Array) -> bool:
	if residuals.size() != CAPTURE_RESIDUAL_TOLERANCES.size():
		return false
	for index in CAPTURE_RESIDUAL_TOLERANCES.size():
		if absf(float(residuals[index])) > CAPTURE_RESIDUAL_TOLERANCES[index]:
			return false
	return true


static func _capture_coarse_converged(residuals: Array) -> bool:
	for index in CAPTURE_COARSE_RESIDUAL_TOLERANCES.size():
		if absf(float(residuals[index])) > CAPTURE_COARSE_RESIDUAL_TOLERANCES[index]:
			return false
	return true


static func _maximum_residual_delta(a: Array, b: Array) -> float:
	var result := 0.0
	for index in 5:
		var scale := 1.0 if index < 2 else 50.0
		result = maxf(result, absf(a[index] - b[index]) * scale)
	return result


static func _capture_margins(
	coefficients: Array, route: Dictionary, layout: Dictionary
) -> Dictionary:
	var coefficient_margin := INF
	for index in 5:
		coefficient_margin = minf(coefficient_margin, minf(
			coefficients[index] - CAPTURE_COEFFICIENT_BOUNDS[index][0],
			CAPTURE_COEFFICIENT_BOUNDS[index][1] - coefficients[index]))
	var result := _capture_inequality_margins(route, layout)
	var end := RideProgram._last_state(route)
	var corridor: Dictionary = layout.reserved_corridor
	var entry_speed_mps: Vector2 = corridor.entry_speed_mps
	var entry_forward_m: float = (route.position_m[0] - layout.station_position_m).dot(
		layout.station_tangent.normalized())
	var remaining_along_track_m: float = (layout.station_position_m - end.position_m).dot(
		layout.station_tangent.normalized())
	result.merge({
		"coefficient_margin": coefficient_margin,
		"speed_floor_margin_mps": end.speed_mps - 2.0,
		"remaining_along_track_m": remaining_along_track_m,
		"capture_partition_entry_m": -float(corridor.brake_length_m) - entry_forward_m,
		"brake_reserve_m": float(corridor.brake_length_m) - remaining_along_track_m,
		"entry_speed_low_mps": float(route.speed_mps[0]) - entry_speed_mps.x,
		"entry_speed_high_mps": entry_speed_mps.y - float(route.speed_mps[0]),
	}, true)
	return result


static func _capture_inequality_margins(route: Dictionary, layout: Dictionary) -> Dictionary:
	var forward: Vector3 = layout.station_tangent.normalized()
	var up: Vector3 = layout.station_up.normalized()
	var right := forward.cross(up).normalized()
	var half_width: float = layout.get("capture_half_width_m", CAPTURE_HALF_WIDTH_M)
	var half_height: float = layout.get("capture_half_height_m", CAPTURE_HALF_HEIGHT_M)
	var maximum_cross := 0.0
	var maximum_height := 0.0
	var minimum_forward_low := INF
	var minimum_forward_high := INF
	var minimum_speed := INF
	var maximum_normal := 0.0
	var maximum_lateral := 0.0
	var maximum_roll := 0.0
	for index in route.position_m.size():
		var delta: Vector3 = route.position_m[index] - layout.station_position_m
		maximum_cross = maxf(maximum_cross, absf(delta.dot(right)))
		maximum_height = maxf(maximum_height, absf(delta.dot(up)))
		var forward_offset := delta.dot(forward)
		minimum_forward_low = minf(minimum_forward_low,
			_approach_length(layout) + forward_offset)
		minimum_forward_high = minf(minimum_forward_high, -forward_offset)
		minimum_speed = minf(minimum_speed, route.speed_mps[index])
		maximum_normal = maxf(maximum_normal, absf(route.normal_g[index]))
		maximum_lateral = maxf(maximum_lateral, absf(route.lateral_g[index]))
		maximum_roll = maxf(maximum_roll, absf(route.roll_rate_rad_s[index]))
	return {
		"corridor_cross_m": half_width - maximum_cross,
		"corridor_height_m": half_height - maximum_height,
		"corridor_forward_low_m": minimum_forward_low,
		"corridor_forward_high_m": minimum_forward_high,
		"speed_floor_mps": minimum_speed - 2.0,
		"normal_force_g": 8.0 - maximum_normal,
		"lateral_force_g": 4.7 - maximum_lateral,
		"roll_rate_rad_s": deg_to_rad(120.0) - maximum_roll,
	}


static func _finite_difference_jacobian(
	base_vector: Array, base_scaled: Array, bounds: Array, deltas: Array,
	evaluate: Callable
) -> Dictionary:
	var size := base_vector.size()
	var jacobian: Array = []
	for _row in size:
		var row := []
		row.resize(size)
		row.fill(0.0)
		jacobian.append(row)
	for column in size:
		var delta := float(deltas[column])
		if base_vector[column] + delta < bounds[column][0] \
				or base_vector[column] + delta > bounds[column][1]:
			delta = -delta
		if base_vector[column] + delta < bounds[column][0] \
				or base_vector[column] + delta > bounds[column][1]:
			return RideProgram._failure("finite-difference probe has no bounded direction", "solve")
		var probe := base_vector.duplicate()
		probe[column] += delta
		var observed: Dictionary = evaluate.call(probe)
		if not observed.ok:
			return observed
		for row in size:
			jacobian[row][column] = (observed.scaled[row] - base_scaled[row]) / delta
	return {"ok": true, "jacobian": jacobian}


## The pivot record `BoundedSolver.linear_solve` returns, read as the conditioning of the Newton
## step it just produced. An ill-conditioned Jacobian is a structural failure of the solve, so
## the verdict is published beside the vector it was measured at.
static func _conditioning(solved: Dictionary, vector: Array) -> Dictionary:
	var low := float(solved.get("minimum_pivot", 0.0))
	var high := float(solved.get("maximum_pivot", 0.0))
	var ratio := low / high if high > 0.0 else 0.0
	return {"ok": bool(solved.get("ok", false)) and low >= 0.000001 and ratio >= 0.0001,
		"minimum_pivot": low, "maximum_pivot": high, "pivot_ratio": ratio,
		"evaluated_vector": vector.duplicate()}


static func _solve_brakes(start: Dictionary, layout: Dictionary) -> Dictionary:
	var remaining: float = (layout.station_position_m - start.position_m).dot(
		layout.station_tangent.normalized())
	var corridor: Variant = layout.get("reserved_corridor")
	if not corridor is Dictionary or not is_finite(float(corridor.get("brake_length_m", NAN))):
		return RideProgram._failure("brake corridor contract is incomplete", "brake")
	if remaining > float(corridor.brake_length_m) + TERMINAL_DISTANCE_TOLERANCE_M:
		return RideProgram._failure("brake entry exceeds its declared reserve", "brake",
			{"remaining_distance_m": remaining, "brake_length_m": corridor.brake_length_m})
	var station_duration := _coast_time(2.0, 1.0)
	var station_distance := _coast_distance(2.0, 1.0)
	var frame_residuals := _capture_residuals(start, layout)
	if absf(float(frame_residuals[2])) > CAPTURE_RESIDUAL_TOLERANCES[2] \
			or absf(float(frame_residuals[3])) > CAPTURE_RESIDUAL_TOLERANCES[3] \
			or absf(float(frame_residuals[4])) > CAPTURE_RESIDUAL_TOLERANCES[4]:
		return RideProgram._failure(
			"capture terminal frame is not the straight station frame", "brake")
	if not is_finite(remaining) or not is_finite(station_duration) \
			or not is_finite(station_distance) \
			or remaining <= station_distance:
		return RideProgram._failure(
			"station creep is infeasible in the remaining approach", "brake")
	var moving_target := remaining - station_distance
	var active_estimate := 2.0 * moving_target / (float(start.speed_mps) + 2.0)
	var resistance_loss := Motion.resistance(0.5 * (float(start.speed_mps) + 2.0),
		RideProgram.ROLLING_MPS2, RideProgram.AERO_PER_M).x * active_estimate
	var parameters := [active_estimate - 2.0 * BRAKE_SHOULDER_DURATION_S,
		0.80 * (float(start.speed_mps) - 2.0 - resistance_loss) / (
			Motion.G0 * (active_estimate - BRAKE_SHOULDER_DURATION_S))]
	for index in 2:
		if not is_finite(parameters[index]) \
				or parameters[index] <= BRAKE_PARAMETER_BOUNDS[index][0] \
				or parameters[index] >= BRAKE_PARAMETER_BOUNDS[index][1]:
			return RideProgram._failure("brake initial estimate is outside its parameter bounds",
				"brake",
				{"remaining_distance_m": remaining, "entry_speed_mps": start.speed_mps,
					"active_estimate_s": active_estimate, "initial_values": parameters})
	var evaluation_count := [0]
	var base := {}
	var conditioning := {}
	var evaluate := func(candidate: Array) -> Dictionary:
		return _brake_evaluation(start, candidate, moving_target,
			RideProgram._settings(0.01), evaluation_count)
	for iteration in BRAKE_NEWTON_ITERATIONS:
		base = evaluate.call(parameters)
		if not base.ok:
			return base
		var finite_difference := _finite_difference_jacobian(parameters, base.scaled,
			BRAKE_PARAMETER_BOUNDS, [-0.01, -0.005], evaluate)
		if not finite_difference.ok:
			return finite_difference
		var solved := BoundedSolver.linear_solve(finite_difference.jacobian, base.scaled)
		conditioning = _conditioning(solved, parameters)
		if not conditioning.ok:
			return _brake_failure("brake Jacobian is ill-conditioned",
				evaluation_count[0], {"conditioning": conditioning})
		if _brake_converged(base.residuals):
			break
		if iteration + 1 == BRAKE_NEWTON_ITERATIONS:
			return _brake_failure(
				"brake solve exhausted its iteration budget", evaluation_count[0])
		var step: Array = solved.x
		for index in 2:
			parameters[index] -= BRAKE_NEWTON_STEP * step[index]
			if parameters[index] <= BRAKE_PARAMETER_BOUNDS[index][0] \
					or parameters[index] >= BRAKE_PARAMETER_BOUNDS[index][1]:
				return _brake_failure("brake solve reached a parameter bound", evaluation_count[0])
	if not _brake_converged(base.get("residuals", [])):
		return _brake_failure("brake solve did not produce an accepted point", evaluation_count[0])
	var confirmations := []
	for step_s in [RideProgram.COARSE_STEP_S, RideProgram.FINE_STEP_S]:
		var observed := _brake_evaluation(start, parameters, moving_target,
			RideProgram._settings(step_s), evaluation_count)
		if not observed.ok:
			return observed
		confirmations.append(observed)
		if not _brake_converged(observed.residuals) \
				or not _brake_observations_agree(base.residuals, observed.residuals):
			return _brake_failure(
				"brake production/coarse/fine verification disagrees", evaluation_count[0])
	var terminal_spans := _brake_spans(parameters)
	terminal_spans.append(Motion.span("station/creep", station_duration, "station",
		Motion.constant(1.0), Motion.constant(0.0), Motion.constant(0.0), Motion.constant(0.0)))
	return {"ok": true, "errors": PackedStringArray(), "spans": terminal_spans, "report": {
			"parameter_ids": BRAKE_PARAMETER_IDS, "parameter_bounds": BRAKE_PARAMETER_BOUNDS,
			"accepted_values": parameters, "hold_duration_s": parameters[0],
			"active_duration_s": parameters[0] + 2.0 * BRAKE_SHOULDER_DURATION_S,
			"brake_peak_g": parameters[1], "unique_evaluations": evaluation_count[0],
			"max_unique_evaluations": MAX_BRAKE_EVALUATIONS,
			"production_observation": _brake_report_observation(base, start),
			"coarse_observation": _brake_report_observation(confirmations[0], start),
			"fine_observation": _brake_report_observation(confirmations[1], start),
			"conditioning": conditioning, "brake_entry_speed_mps": float(start.speed_mps),
			"remaining_distance_m": remaining,
			"moving_distance_m": base.route.distance_m[-1] - float(start.distance_m),
			"station_distance_m": station_distance, "distance_residual_m": base.residuals[0],
			"moving_boundary_speed_mps": base.route.speed_mps[-1],
			"terminal_creep_speed_mps": 1.0, "positive_drive_allowed": false,
		}}


static func _brake_evaluation(start: Dictionary, parameters: Array,
	moving_target: float, settings: Dictionary, evaluation_count: Array
) -> Dictionary:
	if evaluation_count[0] >= MAX_BRAKE_EVALUATIONS:
		return _brake_failure("brake exceeded its evaluation cap", evaluation_count[0])
	evaluation_count[0] += 1
	var result := _brake_observation(start, parameters, moving_target, settings)
	if not result.ok:
		return _brake_failure("brake candidate failed central integration", evaluation_count[0])
	return result


static func _brake_observation(start: Dictionary, parameters: Array,
	moving_target: float, settings: Dictionary) -> Dictionary:
	var route := Motion.integrate(start, _brake_spans(parameters), settings)
	if not route.get("ok", false):
		return {"ok": false}
	var residuals := [route.distance_m[-1] - float(start.get("distance_m", 0.0)) - moving_target,
		float(route.speed_mps[-1]) - 2.0]
	return {"ok": true, "route": route, "residuals": residuals, "scaled": [
		residuals[0] / 25.0,
		(float(route.speed_mps[-1]) - BRAKE_BOUNDARY_INTERIOR_MPS) / 5.0]}


static func _brake_report_observation(observation: Dictionary, start: Dictionary) -> Dictionary:
	return {"residuals": observation.residuals.duplicate(),
		"moving_distance_m": observation.route.distance_m[-1] - float(start.distance_m),
		"moving_boundary_speed_mps": observation.route.speed_mps[-1]}


static func _brake_failure(message: String, evaluation_count: int,
	diagnostics: Dictionary = {}) -> Dictionary:
	diagnostics["evaluation_count"] = evaluation_count
	return RideProgram._failure(message, "brake", diagnostics)


static func _brake_converged(residuals: Array) -> bool:
	return absf(residuals[0]) <= TERMINAL_DISTANCE_TOLERANCE_M \
		and absf(residuals[1]) <= BRAKE_BOUNDARY_TOLERANCE_MPS


static func _brake_observations_agree(a: Array, b: Array) -> bool:
	return absf(a[0] - b[0]) <= TERMINAL_DISTANCE_TOLERANCE_M \
		and absf(a[1] - b[1]) <= BRAKE_BOUNDARY_TOLERANCE_MPS


static func _brake_spans(parameters: Array) -> Array:
	var hold_duration: float = parameters[0]
	var peak_g: float = parameters[1]
	return [
		Motion.span("brakes/engage", BRAKE_SHOULDER_DURATION_S, "moving",
			Motion.constant(1.0), Motion.constant(0.0), Motion.quintic(0.0, -peak_g),
			Motion.constant(0.0)),
		Motion.span("brakes/hold", hold_duration, "moving",
			Motion.constant(1.0), Motion.constant(0.0), Motion.constant(-peak_g),
			Motion.constant(0.0)),
		Motion.span("brakes/release", BRAKE_SHOULDER_DURATION_S, "moving",
			Motion.constant(1.0), Motion.constant(0.0), Motion.quintic(-peak_g, 0.0),
			Motion.constant(0.0)),
	]


static func _coast_time(from_speed: float, to_speed: float) -> float:
	if from_speed <= to_speed or RideProgram.ROLLING_MPS2 <= 0.0:
		return INF
	if RideProgram.AERO_PER_M <= 0.0:
		return (from_speed - to_speed) / RideProgram.ROLLING_MPS2
	var scale := sqrt(RideProgram.AERO_PER_M / RideProgram.ROLLING_MPS2)
	return (atan(from_speed * scale) - atan(to_speed * scale)) \
		/ sqrt(RideProgram.ROLLING_MPS2 * RideProgram.AERO_PER_M)


static func _coast_distance(from_speed: float, to_speed: float) -> float:
	if from_speed <= to_speed or RideProgram.ROLLING_MPS2 <= 0.0:
		return INF
	if RideProgram.AERO_PER_M <= 0.0:
		return (from_speed * from_speed - to_speed * to_speed) / (2.0 * RideProgram.ROLLING_MPS2)
	return log((RideProgram.ROLLING_MPS2 + RideProgram.AERO_PER_M * from_speed * from_speed) \
		/ (RideProgram.ROLLING_MPS2 + RideProgram.AERO_PER_M * to_speed * to_speed)) \
		/ (2.0 * RideProgram.AERO_PER_M)


static func _capture_failure(
	message: String,
	evaluation_count: int,
	residuals: Array = [],
	margins: Dictionary = {},
	diagnostics: Dictionary = {}
) -> Dictionary:
	var evidence := diagnostics.duplicate(true)
	evidence["evaluation_count"] = evaluation_count
	if not residuals.is_empty():
		evidence["residuals"] = residuals.duplicate()
	if not margins.is_empty():
		evidence["margins"] = margins.duplicate(true)
	return RideProgram._failure(message, "capture", evidence)
