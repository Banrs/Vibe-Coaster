class_name RideReturnElements
extends RefCounted

## One accepted macro assignment becomes one integrated return element. Each family authors its
## own spatial curvature and twist over arc length and hands the result to `Motion.integrate`,
## which stays the sole centreline authority: the preview below is a target, and a build that
## disagrees with it is refused rather than corrected. A builder owns nothing outside its own
## assignment - no route total, no station pose, no neighbouring role's length.
##
## Curvature basis (design 2026-08-22 section 3): world-referenced pitch/yaw, so `kappa_pitch < 0`
## at a crest. Reading `Motion._stage_commands` and `_rk4_derivative` back into the frame ODE with
## `t = cos(theta) f + sin(theta) e_y` gives `d(theta)/ds = kappa_pitch` and
## `d(psi)/ds = kappa_yaw / cos(theta)`, so the `1 / cos(theta)` factor is the production
## integrator's, not the specification's prose. Because the basis is referenced to world-up rather
## than to rider-up, twist changes how the geometry is felt without tilting the planned turn plane,
## which is why the centreline of both families is a function of arc length alone.
##
## Both families are handed the pitch the previous element left them - up to the macro stage's
## 35 deg handover ceiling - and both hand the next stage a level, unbanked frame. Pitch is levelled
## through `level_out_pitch_rad`, the one profile the macro elevation model also evaluates; roll is
## closed by cancelling the frame's own geometric drift rather than by another solved scalar.
##
## Two families:
##
## - `return_turn` traces one semantic span of yaw curvature over a shouldered plateau. The bank
##   leads the curvature into and out of that plateau, because a shoulder that rolls and turns in
##   step carries the rider outward through the roll-in - the opposite of what this family is for.
##   Its one solved scalar is peak bank, and it is solved to the counter-lateral band rather than
##   to balance: `CLAUDE.md` names two overbanked turns on the return, so a laterally neutral turn
##   is a contract failure here.
## - `return_height` traces one fixed vertical plane through the entry tangent with zero yaw
##   curvature and zero twist. Its pitch curvature is one staged narrative through the knots
##   `[0, pull_up, crest, pullout, 0]`; every knot joins two quintics whose value, spatial slope
##   and spatial acceleration all agree there, so the stages are numerical knots of one motion and
##   never a pulse restart, a neutral pause or a micro-hold. `elevation_bound_m` publishes the net
##   elevation it can crest through, so the macro stage may not assign an elevation this family
##   would then refuse.
##
## Both families enter and leave at zero curvature, zero curvature slope and zero curvature
## acceleration, which is what lets adjacent elements meet the C4 seam contract.

const Motion := preload("res://motion.gd")
const BoundedSolver := preload("res://bounded_solver.gd")

const TURN_FAMILY := "return_turn"
const HEIGHT_FAMILY := "return_height"

## The shoulder each role reserves at both ends, and the lead the twist takes inside it. The bank
## reaches `TWIST_LEAD_FRACTION` of its peak over the first `TWIST_LEAD_FRACTION` of the shoulder,
## where no curvature is commanded at all, and the curvature ramp then has the whole remaining
## shoulder. Two consequences are load-bearing:
##
## - each pair of twist stages carries the same peak roll rate - `0.35 phi` over `0.35` of the
##   shoulder has the slope `phi` over the whole shoulder has - so the peak is exactly
##   `1.875 v max(|phi|, |phi - phi_exit|) / shoulder`, where `phi_exit` cancels the frame's own
##   bank drift. Bounding the whole of that with one number is what `max_bank_rad` is for: it is a
##   ceiling on the bank the rider measures, `phi` plus the drift, taken at the fastest speed the
##   role reaches. `_solve_turn` brackets the commanded `phi` a further `|drift|` below it, so the
##   entry pair rolls through at most `ceiling - |drift|` and the exit pair through at most
##   `ceiling`, whichever side the drift falls on. The macro heading bound consumes the same
##   ceiling at the same handover pitch; and
## - the shoulder never carries outward lateral. Sharing one quintic between curvature and twist
##   does: with `c = v^2 kappa / g0` and bank `phi`, `l = c h cos(phi h) - sin(phi h)` is outward
##   for small `h` whenever `c > phi` in radians, which the counter-lateral identity reaches at
##   about 67.6 deg and which peaks at +0.26 g of outward lateral at the 77 deg ceiling. Leading
##   the bank replaces that with `c h <= tan(phi (p + (1 - p) h))`; `p = 0.25` still leaves
##   +0.004 g near `h = 0.5` at the ceiling, and `p = 0.35` clears it by more than a fifth at
##   every `h`.
const SHOULDER_FRACTION := 0.2
const TWIST_LEAD_FRACTION := 0.35
const LEAD_FRACTION := SHOULDER_FRACTION * TWIST_LEAD_FRACTION
## The fraction of the allocated arc that carries loaded curvature once both shoulders and both
## leads are reserved. The macro heading bound reserves the same arc, so the frame the layout
## assigns is a frame this family can reach.
const LOADED_ARC_FRACTION := 1.0 - SHOULDER_FRACTION - LEAD_FRACTION
## Peak of `d(h)/du` for the quintic shoulder `h = 10u^3 - 15u^4 + 6u^5`: `30/16`.
const QUINTIC_PEAK_SLOPE := 1.875
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
## Noise floor for the pointwise inward-lateral check. Lateral is identically zero at both
## endpoints, where the frame carries neither bank nor curvature, so what the pointwise minimum
## finds there is the frame's own float32 quantisation - measured at or below 6e-6 g across the
## whole handover-pitch range. The outward shoulder transient this check exists to refuse is
## +0.26 g, three orders above it and above the band floor.
const LATERAL_SIGN_TOLERANCE_G := 0.0001
## The same 77 deg, as the family's geometric ceiling. `max_bank_rad` takes the roll-rate ceiling
## below it whenever the shoulder is too short to roll that far inside the envelope.
const TURN_BANK_CEILING_RAD := 77.0 * PI / 180.0

## The return height beat's authored airtime value, `-0.45 g` - the same value the story's first
## height beat holds before its per-seed unload scale is applied. An assignment that carries its
## own drawn `unload_g` overrides it.
const DEFAULT_UNLOAD_G := -0.45
const UNLOAD_TOLERANCE_G := 0.01
## The height a beat's crest must stand above its endpoints before it is a height beat at all,
## derived from the same counterpart row the unload above comes from. Intimidator 305's last
## airtime pop - the `return-height-a` row's own class corroboration - measures -0.45 g held below
## 0 g for 0.78 s. A crest that unloads a rider to `n` at speed `v` curves at `(1 - n) g0 / v^2`,
## so the apex of the arc holding that stands `(1 - n) g0 T^2 / 8` above the ends of the window,
## which is speed-free: 0.746 m at the 0 g threshold across the measured 0.78 s. The element's own
## endpoints sit below the ends of that window, so this is a floor on the published prominence
## rather than a target for it, and geometry is never scaled off the counterpart.
const PROMINENCE_FLOOR_M := 0.7458
## The bounds' quadrature: steps per curvature stage - which is also the sample count of the scan
## that finds the deepest crest, and of the turn bound's own trace - corrections of the crest knot,
## and bisections of each window edge. Nothing here integrates a trajectory: these are counts on a
## commanded analytic profile, evaluated once per role by the macro stage and never inside a solve.
const BOUND_SAMPLES := 24
const BOUND_CREST_PASSES := 3
const BOUND_BISECTIONS := 16
const TURN_BOUND_SAMPLES := 384
## What a bound's analytic profile and the production integration of the same assignment were
## measured to disagree by at each published edge. A bound published at its own zero-margin point
## is a bound whose edge does not build, so every window and ceiling below holds this much margin
## on the trace - the macro stage may sit a control on its bound, and there is no retry behind it.
##
## The prominence figure is not quadrature. An accepted build sits anywhere inside the height
## solve's own converged residuals - 0.1 m of net elevation against the 5 m scale, and 0.01 g of
## crest unload against the 0.5 g scale - and at a window edge with positive net elevation both
## spend straight out of prominence, which is measured from the exit there: the shallower crest
## flattens the apex over the crest arc while the elevation residual moves the exit under it. The
## crest term dominates and grows with arc, so it was measured over the whole declared span of
## both role bands (290-590 m x 70-80 m/s x -10 to +20 deg of handover): the worst edge
## disagreement is 0.084 m, and every one of those 144 published edges builds with this margin.
const BOUND_AGREEMENT_G := 0.002
const BOUND_AGREEMENT_M := 0.11
## Curvature bounds for the height solve, stated as loads rather than as radii: no stage's own
## `v^2 kappa / g0` may pass the 4.0 g held normal limit the macro stage also reasons against, and
## none may unload past -1.0 g, which is twice the deepest authored airtime. Both signs are open on
## the first stage because a beat handed a climbing entry pitches down into its crest, exactly as
## one handed a descending entry pitches up. These bound curvature, not the peak normal load: with
## the `cos(theta)` term an accepted build reaches 5.157 g of peak normal at 290 m and 80 m/s from
## a -20 deg handover, which is inside the duration envelope at its ~3.6 s and refused by the
## `normal_positive_g` margin rather than by these.
const NORMAL_CEILING_G := 4.0
const AIRTIME_FLOOR_G := -1.0
## How far inside those bounds a traced knot must sit before the elevation window admits it. The
## three-control height solve converges in 6 evaluations against its 41-evaluation cap where its
## controls have room and needs 27-42 where one of them is pinned, so a window edge that pins a
## control is an edge that does not build. Measured: 0.02 g leaves every published edge converging
## in 6.
const KNOT_INTERIOR_G := 0.02

## Seam tolerances (design 2026-08-22 section 4), to be confirmed by measurement once the first
## fleet is green.
const POSITION_TOLERANCE_M := 0.001
const TANGENT_TOLERANCE := 0.0001
const CURVATURE_TOLERANCE_M_INV := 0.00001

## Endpoint tolerances the local residuals are converged against. Exit pitch is the height solve's
## converged residual - 0.02 scaled against the 0.02 rad scale - and the turn delivers it by
## construction; bank is the seam frame tolerance.
const PITCH_TOLERANCE_RAD := 0.0004
const BANK_TOLERANCE_RAD := 0.0001
const HEADING_TOLERANCE_RAD := 0.001
## Net elevation is compared against the macro stage's own vertical residual scale: the assignment
## is a target read off a nominal chain, not a solved endpoint, and 5 m is the scale that chain is
## converged at.
const ELEVATION_TOLERANCE_M := 5.0
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
## This fraction of the allocated arc is the stated stand-in: it admits that difference at the
## declared role lengths while still refusing a centreline that has left its corridor. It is not a
## derived half-width, and Task 6 must replace it with the one the layout derives.
const CORRIDOR_TOLERANCE_FRACTION := 0.05
## Zero yaw curvature makes a height beat planar by construction, so what the planarity
## measurement can find is float32 position quantisation: one ulp at these coordinates is about
## 3e-5 m and the samples accumulate it, so the slack is stated per metre of arc rather than as a
## fixed distance that a longer beat would fail on representation alone.
const PLANARITY_TOLERANCE_FRACTION := 0.00001

## `BoundedSolver.solve` costs `1 + K(n + 1) + R` unique evaluations. The height beat's three
## controls with K <= 8 accepted iterations and R <= 8 rejections give 1 + 8*4 + 8 = 41. The turn's
## one control is a monotone bracket - core lateral load falls strictly as bank rises - so it uses
## the same 32-evaluation cap the terminal's one-dimensional brake bracket declares: one unbanked
## integration that settles the bank ceiling, then 31 bisections of the bracket it opens.
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
		spans = _turn_spans(assignment, _turn_geometry(assignment, _pitch(tangent)), 0.0)
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


## The ceiling on the bank one role's rider measures: the geometric counterpart ceiling, or the
## roll the envelope allows across the shoulder that has to establish it, whichever is lower. A
## quintic shoulder's peak slope is 1.875, so rolling through `phi` over `SHOULDER_FRACTION * L`
## at `v` peaks at `1.875 phi v / (SHOULDER_FRACTION L)`, and holding that at or below the
## envelope's roll-rate limit is the inequality below. `speed_mps` is the fastest speed the role
## reaches, not the speed it was handed: a descending role leaves faster than it entered, and its
## exit shoulder rolls at that speed. The macro heading bound consumes this same ceiling, so no
## layout may assign a heading this family would have to break the roll envelope to deliver.
static func max_bank_rad(length_m: float, speed_mps: float) -> float:
	return minf(TURN_BANK_CEILING_RAD, deg_to_rad(RideVerify.ROLL_RATE_LIMIT)
		* SHOULDER_FRACTION * length_m / (QUINTIC_PEAK_SLOPE * speed_mps))


static func _speed_ceiling(speeds: PackedFloat64Array) -> float:
	var ceiling := 0.0
	for speed in speeds:
		ceiling = maxf(ceiling, float(speed))
	return ceiling


## The heading a turn can be assigned and still press the rider down the bank at every sample: the
## family's counterpart to `elevation_bound_m`, published so no layout may assign a heading this
## family then refuses. It is a function of the handover pitch, not only of arc and entry speed,
## and the dependence is neither small nor one-signed: a descending role gains speed, so `v^2
## kappa / g0` rises across a core the bank is held constant through, while the frame's own bank
## drift leans against that bank exactly where the speed is highest - the turn goes from
## overbanked to underbanked before its exit shoulder. Against that, the same descent pitches the
## track up, and `v^2 kappa_pitch / g0` adds to the load the bank resolves, which on a short arc
## buys more heading than a level handover does.
##
## No closed form survives all of that, so the ceiling is bisected over the family's own analytic
## profile - the same trace `elevation_bound_m` uses, and no integration. For a candidate heading
## the core's counter-lateral condition fixes the bank in closed form at every core sample, the
## smallest of those is the bank the build's bracket converges to, and the candidate is held only
## if that bank is inside `max_bank_rad` and no sample carries outward lateral.
static func heading_bound_rad(length_m: float, speed_mps: float,
		entry_pitch_rad: float) -> float:
	var trace := _turn_trace(length_m, speed_mps, entry_pitch_rad)
	var ceiling := max_bank_rad(length_m, float(trace.speed_ceiling_mps))
	var low := 0.0
	var high := PI
	if _turn_holds(trace, ceiling, high):
		return high
	for _iteration in BOUND_BISECTIONS:
		var heading := 0.5 * (low + high)
		if _turn_holds(trace, ceiling, heading):
			low = heading
		else:
			high = heading
	return low if low > 0.0 and _turn_holds(trace, ceiling, low) else 0.0


## One candidate heading against the family's own contract, on the commanded profile. With
## `l = c cos(bank) - B sin(bank)`, `B = v^2 kappa_pitch / g0 + cos(theta)` and `c = v^2 kappa_yaw
## / g0`, the inward lateral at bank `beta` is `R sin(beta - delta)` for `R = hypot(B, c)` and
## `delta = atan2(c, B)`, so the bank that holds the counterpart's 0.47 g at one core sample is
## exact. The core's own samples do not agree on it - speed and pitch both move across the core -
## and the build's bracket converges on the largest core lateral, which is the smallest of those
## banks.
static func _turn_holds(trace: Dictionary, ceiling_rad: float, heading_rad: float) -> bool:
	# `_solve_turn` brackets the commanded twist below the measured ceiling by the drift the frame
	# adds to it, so that is the bracket this candidate has to fit inside as well.
	var ceiling := ceiling_rad - absf(heading_rad * float(trace.drift))
	var bank := INF
	for sample: Array in trace.samples:
		if float(sample[0]) < SHOULDER_FRACTION or float(sample[0]) > 1.0 - SHOULDER_FRACTION:
			continue
		var lateral := heading_rad * float(sample[3])
		var radius := sqrt(float(sample[4]) * float(sample[4]) + lateral * lateral)
		if radius <= COUNTER_LATERAL_TARGET_G:
			return false
		bank = minf(bank, asin(COUNTER_LATERAL_TARGET_G / radius)
			+ atan2(lateral, float(sample[4])) - heading_rad * float(sample[2]))
	if not (bank > 0.0) or bank > ceiling:
		return false
	for sample: Array in trace.samples:
		if float(sample[3]) <= 0.0:
			continue
		var angle := float(sample[1]) * bank + heading_rad * float(sample[2])
		if float(sample[4]) * sin(angle) - heading_rad * float(sample[3]) * cos(angle) \
				< BOUND_AGREEMENT_G:
			return false
	return true


## The turn profile the ceiling is measured on: `[u, twist fraction, bank drift per rad of
## heading, c per rad of heading, B]` at each sample, plus the fastest speed the role reaches,
## which is the speed `max_bank_rad` is taken at on both sides. Track pitch is the shared
## level-out, speed follows the same arc-length energy equation the production integrator does,
## and the bank is the
## commanded twist plus the frame's own geometric drift - with zero commanded twist a transported
## frame keeps its roll while the world level frame rotates about the tangent at
## `-d(psi)/ds sin(theta)`, which is the drift `_turn_geometry` cancels at the exit and which no
## measurement of the commanded twist alone would see.
static func _turn_trace(length_m: float, speed_mps: float,
		entry_pitch_rad: float) -> Dictionary:
	var secant := LOADED_ARC_FRACTION
	var drift := 0.0
	if not is_zero_approx(entry_pitch_rad):
		var gudermannian := _inverse_gudermannian(entry_pitch_rad)
		secant = LOADED_ARC_FRACTION * gudermannian / entry_pitch_rad
		drift = -log(cos(entry_pitch_rad)) / gudermannian
	var pitch_peak := -entry_pitch_rad / (LOADED_ARC_FRACTION * length_m)
	var energy := 0.5 * speed_mps * speed_mps
	var step := length_m / TURN_BOUND_SAMPLES
	var accumulated := 0.0
	var ceiling := speed_mps
	var trace: Array = []
	for index in TURN_BOUND_SAMPLES + 1:
		var u := float(index) / TURN_BOUND_SAMPLES
		var shape := _turn_shape(u)
		var squared := 2.0 * maxf(energy, 1.0)
		ceiling = maxf(ceiling, sqrt(squared))
		trace.append([u, _twist_fraction(u), accumulated - _exit_fraction(u) * drift,
			squared * shape / (Motion.G0 * length_m * secant),
			squared * pitch_peak * shape / Motion.G0
				+ cos(level_out_pitch_rad(entry_pitch_rad, u))])
		if index < TURN_BOUND_SAMPLES:
			var midpoint := u + 0.5 / TURN_BOUND_SAMPLES
			var pitch := level_out_pitch_rad(entry_pitch_rad, midpoint)
			accumulated += _turn_shape(midpoint) * tan(pitch) \
				/ (secant * TURN_BOUND_SAMPLES)
			energy += step * (-Motion.G0 * sin(pitch) - RideProgram.ROLLING_MPS2
				- 2.0 * RideProgram.AERO_PER_M * energy)
	return {"samples": trace, "drift": drift, "speed_ceiling_mps": ceiling}


## The commanded curvature shape: zero through each lead, one quintic shoulder either side, flat
## across the core. `plateau_fraction` is its normalized integral.
static func _turn_shape(u: float) -> float:
	var width := SHOULDER_FRACTION - LEAD_FRACTION
	if u <= LEAD_FRACTION or u >= 1.0 - LEAD_FRACTION:
		return 0.0
	if u < SHOULDER_FRACTION:
		return _quintic((u - LEAD_FRACTION) / width)
	if u <= 1.0 - SHOULDER_FRACTION:
		return 1.0
	return _quintic((1.0 - LEAD_FRACTION - u) / width)


## The commanded twist as `twist = _twist_fraction(u) phi + _exit_fraction(u) phi_exit`: the two
## coefficients of the five stages `_turn_spans` emits, so the bound reads the bank the build
## commands rather than a second description of it.
static func _twist_fraction(u: float) -> float:
	var width := SHOULDER_FRACTION - LEAD_FRACTION
	if u <= LEAD_FRACTION:
		return TWIST_LEAD_FRACTION * _quintic(u / LEAD_FRACTION)
	if u < SHOULDER_FRACTION:
		return TWIST_LEAD_FRACTION + (1.0 - TWIST_LEAD_FRACTION) \
			* _quintic((u - LEAD_FRACTION) / width)
	if u <= 1.0 - SHOULDER_FRACTION:
		return 1.0
	if u <= 1.0 - LEAD_FRACTION:
		return 1.0 - (1.0 - TWIST_LEAD_FRACTION) \
			* _quintic((u - 1.0 + SHOULDER_FRACTION) / width)
	return TWIST_LEAD_FRACTION * (1.0 - _quintic((u - 1.0 + LEAD_FRACTION) / LEAD_FRACTION))


static func _exit_fraction(u: float) -> float:
	var width := SHOULDER_FRACTION - LEAD_FRACTION
	if u <= 1.0 - SHOULDER_FRACTION:
		return 0.0
	if u <= 1.0 - LEAD_FRACTION:
		return (1.0 - TWIST_LEAD_FRACTION) * _quintic((u - 1.0 + SHOULDER_FRACTION) / width)
	return 1.0 - TWIST_LEAD_FRACTION + TWIST_LEAD_FRACTION \
		* _quintic((u - 1.0 + LEAD_FRACTION) / LEAD_FRACTION)


## The fraction of a shouldered-plateau channel delivered by arc `u`: the normalized integral of
## the commanded shape - zero through each lead, one quintic shoulder either side, flat across the
## core - so it starts and ends with zero value, slope and acceleration. One shape serves the
## turn's heading, both families' pitch level-out, and the macro chain that models them.
static func plateau_fraction(u: float) -> float:
	var c := clampf(u, 0.0, 1.0)
	var width := SHOULDER_FRACTION - LEAD_FRACTION
	var area := LOADED_ARC_FRACTION
	if c <= LEAD_FRACTION:
		area = 0.0
	elif c <= SHOULDER_FRACTION:
		area = width * _quintic_integral((c - LEAD_FRACTION) / width)
	elif c <= 1.0 - SHOULDER_FRACTION:
		area = 0.5 * width + c - SHOULDER_FRACTION
	elif c <= 1.0 - LEAD_FRACTION:
		var x := (c - (1.0 - SHOULDER_FRACTION)) / width
		area = 0.5 * width + 1.0 - 2.0 * SHOULDER_FRACTION + width * (x - _quintic_integral(x))
	return area / LOADED_ARC_FRACTION


## Track pitch over one role: the entry pitch decays to exactly zero and stays there, through the
## same shouldered plateau of pitch curvature the heading uses. This is the single definition of
## that ramp - `RideReturnLayout` evaluates it as its macro elevation model, and the spans below
## command the curvature whose integral it is - so a role's assigned elevation and the elevation
## it is built at cannot come from two different shapes.
static func level_out_pitch_rad(entry_pitch_rad: float, u: float) -> float:
	return entry_pitch_rad * (1.0 - plateau_fraction(u))


## The fraction of a turn's heading delivered by arc `u`. Heading obeys
## `d(psi)/ds = kappa_yaw / cos(theta)`, so a plateau of yaw curvature delivers heading weighted by
## `sec(theta)` and the plateau's own fraction is only the level case. Under the level-out above
## that weighting integrates in closed form: substituting `p = plateau_fraction(u)` turns the
## quadrature into `integral of sec(theta0 (1 - p)) dp`, whose antiderivative is the inverse
## Gudermannian `G(x) = ln|sec(x) + tan(x)|`. This is therefore the whole shared heading profile,
## exact at every entry pitch, and `_turn_geometry` normalizes the commanded curvature by the same
## `G(theta0) / theta0` its denominator is.
static func heading_fraction(entry_pitch_rad: float, u: float) -> float:
	if is_zero_approx(entry_pitch_rad):
		return plateau_fraction(u)
	return 1.0 - _inverse_gudermannian(entry_pitch_rad * (1.0 - plateau_fraction(u))) \
		/ _inverse_gudermannian(entry_pitch_rad)


## The net elevation a height beat can be assigned and still be one: the family's counterpart to
## `heading_bound_rad`, published so no layout may assign an elevation this family then refuses.
## The height solve's own bounds fix the pull-up knot's range, the exit-pitch condition fixes the
## pullout knot from it, and the crest is pinned by the authored unload, so the whole profile -
## and with it the net elevation, the crest prominence, the peak normal load and the room the
## solve's three controls have - is a function of that one knot. The window is the elevation
## either side of the deepest crest at which the prominence floor, the load envelope or the
## solve's own bounds are first missed. A handover this family cannot crest out of publishes an
## inverted, empty window rather than a bound.
static func elevation_bound_m(length_m: float, speed_mps: float, entry_pitch_rad: float,
		unload_g: float = DEFAULT_UNLOAD_G) -> Vector2:
	var box := _knot_bounds(speed_mps)
	var deepest := INF
	var prominence := -INF
	for index in BOUND_SAMPLES + 1:
		var knot := lerpf(box.x, box.y, float(index) / BOUND_SAMPLES)
		var traced := _height_profile(length_m, speed_mps, entry_pitch_rad, knot, unload_g)
		if _height_crests(traced) and float(traced.prominence_m) > prominence:
			prominence = float(traced.prominence_m)
			deepest = knot
	if not is_finite(deepest):
		return Vector2(INF, -INF)
	return Vector2(
		_height_edge(length_m, speed_mps, entry_pitch_rad, unload_g, box.x, deepest),
		_height_edge(length_m, speed_mps, entry_pitch_rad, unload_g, box.y, deepest))


## The seam evidence, split by the order at which each part is measurable: position, tangent and
## the world curvature vector are compared directly from both integrated routes, while the third
## and fourth position derivatives come from each side's published analytic jets. Differencing
## float32 positions at production spacing measures rounding at those orders, so the finite
## difference below is published as a coarse sanity value and decides nothing. Roll is compared as
## measured bank, not as commanded twist: twist is each element's own gauge relative to its
## transported frame, and two elements that agree on rider-up may hold different twist values.
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
		"bank_rad": absf(float(exit_jets.bank) - float(entry_jets.bank)),
		"twist_slope_rad_m": absf(float(exit_jets.twist_slope)
			- float(entry_jets.twist_slope)),
		"twist_acceleration_rad_m2": absf(float(exit_jets.twist_acceleration)
			- float(entry_jets.twist_acceleration)),
		"finite_difference_x3_m2": _finite_difference(next.trajectory),
	}
	residuals.ok = residuals.position_m <= POSITION_TOLERANCE_M \
		and residuals.tangent <= TANGENT_TOLERANCE \
		and maxf(residuals.curvature_m_inv, residuals.integrated_curvature_m_inv) \
			<= CURVATURE_TOLERANCE_M_INV \
		and maxf(residuals.curvature_slope_m2, residuals.curvature_acceleration_m3) \
			<= CURVATURE_TOLERANCE_M_INV \
		and residuals.bank_rad <= BANK_TOLERANCE_RAD \
		and maxf(residuals.twist_slope_rad_m, residuals.twist_acceleration_rad_m2) \
			<= BANK_TOLERANCE_RAD
	return residuals


## Everything about a turn that follows from the assignment alone: the two commanded curvature
## peaks and the bank the frame will drift by. All three are closed form.
##
## `d(psi)/ds = kappa_yaw / cos(theta)` is the integrator's own identity, so a heading change of
## `delta_psi` needs `integral of kappa_yaw sec(theta) ds = delta_psi`. Commanding the plateau
## shape and normalizing its peak by `J = integral of plateau(u) sec(theta(u)) du` delivers that
## exactly, for any entry pitch and with no extra solve; the `sec(theta)` factor rides on the
## heading-rate shape rather than on the commanded curvature, which keeps the curvature channel
## inside the integrator's own profile vocabulary. `J` is `heading_fraction`'s own denominator in
## closed form, so the shape the layout traces and the peak commanded here come from one identity.
##
## The bank drift is the same integral against `tan`, and closes the same way: with zero commanded
## twist the rider frame is transported with no rotation about the tangent, while the world level
## frame rotates about it at `-d(psi)/ds sin(theta)`, so measured bank accumulates
## `integral of d(psi)/ds sin(theta) ds` - `-ln(cos(theta0))` against `G(theta0)`. Ending the twist
## at minus that closes the frame analytically instead of with a second solved scalar.
##
## The entry pitch is the caller's, not the assignment's: `build` reads it from the integrated
## state it is entered on and `preview` from the frame the assignment publishes, so the pitch this
## geometry levels out of is always the pitch the element is actually handed. Reading the
## assignment inside a build would command the wrong level-out whenever a macro-nominal frame and
## the accepted end state before it differ, and only the exit-pitch margin would catch it.
static func _turn_geometry(assignment: Dictionary, entry_pitch: float) -> Dictionary:
	var length := float(assignment.target_length_m)
	var heading := float(assignment.heading_change_rad)
	var secant := LOADED_ARC_FRACTION
	var drift := 0.0
	if not is_zero_approx(entry_pitch):
		var gudermannian := _inverse_gudermannian(entry_pitch)
		secant = LOADED_ARC_FRACTION * gudermannian / entry_pitch
		drift = -heading * log(cos(entry_pitch)) / gudermannian
	return {"entry_pitch_rad": entry_pitch,
		"yaw_peak_m_inv": heading / (length * secant),
		"pitch_peak_m_inv": -entry_pitch / (LOADED_ARC_FRACTION * length),
		"bank_drift_rad": drift}


## One turn: five stages of one motion. The two leads carry bank alone, the two shoulders ramp
## curvature under a bank that is already leaning, and the core holds all three. Every knot joins
## two quintics whose value, spatial slope and spatial acceleration agree, so no stage restarts a
## pulse or pauses one.
static func _turn_spans(assignment: Dictionary, geometry: Dictionary, bank_rad: float) -> Array:
	var role_id := str(assignment.role_id)
	var length := float(assignment.target_length_m)
	var lead := LEAD_FRACTION * length
	var shoulder := (SHOULDER_FRACTION - LEAD_FRACTION) * length
	var pitch := float(geometry.pitch_peak_m_inv)
	var yaw := float(geometry.yaw_peak_m_inv)
	var exit_bank := -float(geometry.bank_drift_rad)
	var entry_lead := TWIST_LEAD_FRACTION * bank_rad
	var exit_lead := exit_bank + TWIST_LEAD_FRACTION * (bank_rad - exit_bank)
	var zero := Motion.constant(0.0)
	return [
		Motion.spatial_span("%s/roll-in" % role_id, lead, zero, zero, zero,
			Motion.quintic(0.0, entry_lead)),
		Motion.spatial_span("%s/entry" % role_id, shoulder, Motion.quintic(0.0, pitch),
			Motion.quintic(0.0, yaw), zero, Motion.quintic(entry_lead, bank_rad)),
		Motion.spatial_span("%s/core" % role_id, length - 2.0 * (lead + shoulder),
			Motion.constant(pitch), Motion.constant(yaw), zero, Motion.constant(bank_rad)),
		Motion.spatial_span("%s/exit" % role_id, shoulder, Motion.quintic(pitch, 0.0),
			Motion.quintic(yaw, 0.0), zero, Motion.quintic(bank_rad, exit_lead)),
		Motion.spatial_span("%s/roll-out" % role_id, lead, zero, zero, zero,
			Motion.quintic(exit_lead, exit_bank)),
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


## Peak bank against the counter-lateral band, bracketed rather than optimised: with
## `B = v^2 kappa_pitch / g0 + cos(theta)` the held core carries `l = c cos(phi) - B sin(phi)`,
## which falls strictly as bank rises for any B above zero, so the bracket over
## `[0, max_bank_rad]` has one root and needs no warm start. The band is measured on the held core
## rather than on the largest sample: a role that is still levelling out of a steep entry carries
## its deepest lateral where it is banked under pitch curvature, and that sample is not the shape
## this family is authored to hold. The bank is signed with the curvature; a bank on the other side
## is never tried, so closure can never buy itself one.
static func _solve_turn(start: Dictionary, assignment: Dictionary, settings: Dictionary,
		evaluations: Array) -> Dictionary:
	var geometry := _turn_geometry(assignment,
		_pitch((start.tangent as Vector3).normalized()))
	var curvature := float(geometry.yaw_peak_m_inv)
	var direction := signf(curvature)
	if direction == 0.0:
		return {"ok": false, "errors": [{"code": "degenerate_turn",
			"role_id": assignment.role_id}]}
	var length := float(assignment.target_length_m)
	# Bank never moves the centreline, so the speed history is the same at every candidate: one
	# unbanked integration settles the ceiling before the bracket opens, and the fastest sample of
	# it - the exit of a descending role, the entry of a climbing one - is the speed both twist
	# pairs are held against. The published ceiling bounds the bank the rider measures; the bracket
	# gives up the drift the frame adds to the commanded twist, so the entry pair rolls through at
	# most `ceiling - |drift|` and the exit pair through at most `ceiling`, both at or under the
	# envelope's roll rate at the fastest sample. That is what makes `bank_ceiling_rad` and
	# `roll_rate_deg_s` contracts the bracket cannot break rather than margins measured afterward.
	var unbanked := _integrate(start, _turn_spans(assignment, geometry, 0.0), settings,
		evaluations)
	if not unbanked.ok:
		return {"ok": false, "errors": [{"code": "turn_integration",
			"role_id": assignment.role_id, "detail": str(unbanked.errors)}]}
	var ceiling := max_bank_rad(length, _speed_ceiling(unbanked.speed_mps))
	var low := 0.0
	var high := maxf(0.0, ceiling - absf(float(geometry.bank_drift_rad)))
	var bank := 0.0
	var route := {}
	var spans: Array = []
	for _iteration in MAX_TURN_EVALUATIONS - 1:
		bank = 0.5 * (low + high)
		spans = _turn_spans(assignment, geometry, direction * bank)
		route = _integrate(start, spans, settings, evaluations)
		if not route.ok:
			return {"ok": false, "errors": [{"code": "turn_integration",
				"role_id": assignment.role_id, "detail": str(route.errors)}]}
		var lateral := -direction * _core_peak_signed(route, length)
		if absf(lateral - COUNTER_LATERAL_TARGET_G) <= COUNTER_LATERAL_TOLERANCE_G:
			break
		if lateral < COUNTER_LATERAL_TARGET_G:
			low = bank
		else:
			high = bank
	return {"ok": true, "errors": [], "route": route, "spans": spans,
		"controls": [direction * bank], "curvature_m_inv": curvature,
		"bank_ceiling_rad": ceiling,
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
	var crest := _crest_curvature_m_inv(unload, speed)
	var nominal := _height_nominal(entry_pitch, length, elevation, [0.0, 1.0, 0.0], crest)
	var box := _knot_bounds(speed)
	var lower := [box.x, box.x, 0.0]
	var upper := [box.y, 0.0, box.y]
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


## `G(x) = ln|sec(x) + tan(x)|`, the antiderivative of `sec` and so of the heading a pitched
## plateau delivers.
static func _inverse_gudermannian(pitch_rad: float) -> float:
	return log(absf(1.0 / cos(pitch_rad) + tan(pitch_rad)))


## The crest curvature one authored unload asks for: `n = v^2 kappa / g0 + cos(theta)` is exactly
## `1 + v^2 kappa / g0` at the apex, where the track is level.
static func _crest_curvature_m_inv(unload_g: float, speed_mps: float) -> float:
	return (unload_g - 1.0) * Motion.G0 / (speed_mps * speed_mps)


## The three curvature knots one pull-up knot implies: the crest is the authored unload, and the
## pullout is whatever levels the exit pitch, so the family's own endpoint conditions leave exactly
## one free knot.
static func _height_knots(length_m: float, entry_pitch_rad: float, pull_up_m_inv: float,
		crest_m_inv: float) -> Array:
	var area := _pitch_area(1.0)
	return [0.0, pull_up_m_inv, crest_m_inv,
		(-entry_pitch_rad / length_m - float(area[0]) * pull_up_m_inv
			- float(area[1]) * crest_m_inv) / float(area[2]), 0.0]


## One candidate profile, converged the way the build converges it: the crest the height solve
## targets is the deepest unload over the whole beat, not the load at one nominal station, and the
## speed there is not the entry speed. The crest knot is therefore corrected from the traced
## minimum - `dn = v^2 dkappa / g0` makes that exact to first order - until the two agree.
static func _height_profile(length_m: float, speed_mps: float, entry_pitch_rad: float,
		pull_up_m_inv: float, unload_g: float) -> Dictionary:
	var crest := _crest_curvature_m_inv(unload_g, speed_mps)
	var traced := _height_trace(length_m, speed_mps, entry_pitch_rad, pull_up_m_inv, crest)
	for _pass in BOUND_CREST_PASSES:
		crest += (unload_g - float(traced.minimum_normal_g)) * Motion.G0 \
			/ float(traced.minimum_speed_squared)
		traced = _height_trace(length_m, speed_mps, entry_pitch_rad, pull_up_m_inv, crest)
	traced.knot_slack_g = _knot_slack(_knot_bounds(speed_mps), traced.knots) \
		* speed_mps * speed_mps / Motion.G0
	return traced


## The height solve's own curvature bounds at one entry speed, and the room a traced profile's
## knots keep inside them. `NORMAL_CEILING_G` and `AIRTIME_FLOOR_G` are the two, stated as loads;
## the crest knot is bounded above by zero and the pullout below by it, so a knot's slack is its
## distance to whichever of those it is nearest.
static func _knot_bounds(speed_mps: float) -> Vector2:
	var scale := Motion.G0 / (speed_mps * speed_mps)
	return Vector2((AIRTIME_FLOOR_G - 1.0) * scale, NORMAL_CEILING_G * scale)


static func _knot_slack(bounds: Vector2, knots: Array) -> float:
	return minf(minf(float(knots[1]) - bounds.x, bounds.y - float(knots[1])),
		minf(minf(float(knots[2]) - bounds.x, -float(knots[2])),
			minf(float(knots[3]), bounds.y - float(knots[3]))))


## One candidate height profile, traced from the family's own commanded curvature: track pitch is
## exactly the integral of that curvature and height exactly the integral of its sine, and speed
## follows the same arc-length energy equation the production integrator does, so this is the
## profile the build lands on rather than a small-angle sketch of it. A profile with no interior
## crest publishes no prominence.
static func _height_trace(length_m: float, speed_mps: float, entry_pitch_rad: float,
		pull_up_m_inv: float, crest_m_inv: float) -> Dictionary:
	var knots := _height_knots(length_m, entry_pitch_rad, pull_up_m_inv, crest_m_inv)
	var pitch := entry_pitch_rad
	var height := 0.0
	var energy := 0.5 * speed_mps * speed_mps
	var apex_height := INF
	var peak_normal := -INF
	var minimum_normal := INF
	var minimum_squared := 2.0 * energy
	var duration := 0.0
	# Every stage ends on the knot the next one starts from, so the curvature at a step's far node
	# is the near node of the step after it and is carried rather than evaluated twice.
	var curvature := 0.0
	for stage in HEIGHT_FRACTIONS.size():
		var step: float = float(HEIGHT_FRACTIONS[stage]) * length_m / BOUND_SAMPLES
		for index in BOUND_SAMPLES:
			var u1 := float(index + 1) / BOUND_SAMPLES
			var ahead := _height_curvature(knots, stage, u1)
			var next := pitch + step / 6.0 * (curvature + 4.0
				* _height_curvature(knots, stage, u1 - 0.5 / BOUND_SAMPLES) + ahead)
			curvature = ahead
			height += 0.5 * step * (sin(pitch) + sin(next))
			energy += step * (-Motion.G0 * sin(0.5 * (pitch + next))
				- RideProgram.ROLLING_MPS2 - 2.0 * RideProgram.AERO_PER_M * energy)
			var squared := maxf(2.0 * energy, 1.0)
			duration += step / sqrt(squared)
			var normal := squared * ahead / Motion.G0 + cos(next)
			peak_normal = maxf(peak_normal, normal)
			if normal < minimum_normal:
				minimum_normal = normal
				minimum_squared = squared
			if is_inf(apex_height) and pitch > 0.0 and next <= 0.0:
				apex_height = height
			pitch = next
	return {"elevation_m": height, "minimum_normal_g": minimum_normal, "knots": knots,
		"minimum_speed_squared": minimum_squared,
		"prominence_m": -INF if is_inf(apex_height) else apex_height - maxf(0.0, height),
		"load_slack_g": RideVerify.limit_at(RideVerify.POSITIVE_LIMIT, duration) - peak_normal}


## One edge of the window: bisect the pull-up knot between the deepest crest and a knot outside
## the contract, and publish the net elevation of the last knot still inside it.
static func _height_edge(length_m: float, speed_mps: float, entry_pitch_rad: float,
		unload_g: float, outside: float, inside: float) -> float:
	for _iteration in BOUND_BISECTIONS:
		var knot := 0.5 * (outside + inside)
		if _height_crests(_height_profile(length_m, speed_mps, entry_pitch_rad, knot,
				unload_g)):
			inside = knot
		else:
			outside = knot
	return float(_height_profile(length_m, speed_mps, entry_pitch_rad, inside,
		unload_g).elevation_m)


## What a traced profile has to hold before the window admits its elevation: the counterpart
## prominence, the load envelope, and room for the solve's own three controls - each with the
## margin the trace and the production integration were measured to disagree by, so the edge the
## macro stage may sit a control on is an edge that builds.
static func _height_crests(traced: Dictionary) -> bool:
	return float(traced.prominence_m) >= PROMINENCE_FLOOR_M + BOUND_AGREEMENT_M \
		and float(traced.load_slack_g) >= BOUND_AGREEMENT_G \
		and float(traced.knot_slack_g) >= KNOT_INTERIOR_G


static func _height_curvature(knots: Array, stage: int, u: float) -> float:
	return lerpf(float(knots[stage]), float(knots[stage + 1]), _quintic(u))


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
	var inward_lateral := INF
	var roll_reversals := 0
	var roll_sign := 0.0
	var direction := signf(float(solved.get("curvature_m_inv", 0.0)))
	for index in route.time_s.size():
		peak_normal = maxf(peak_normal, float(route.normal_g[index]))
		minimum_normal = minf(minimum_normal, float(route.normal_g[index]))
		peak_lateral = maxf(peak_lateral, absf(float(route.lateral_g[index])))
		peak_roll = maxf(peak_roll, absf(float(route.roll_rate_rad_s[index])))
		minimum_speed = minf(minimum_speed, float(route.speed_mps[index]))
		inward_lateral = minf(inward_lateral, -direction * float(route.lateral_g[index]))
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
		observation.bank_ceiling_rad = float(solved.bank_ceiling_rad)
		observation.curvature_peak_m_inv = float(solved.curvature_m_inv)
		observation.core_lateral_g = _core_peak_signed(route,
			float(assignment.target_length_m))
		observation.inward_lateral_g = inward_lateral
	else:
		observation.merge(_apex(route, entry_tangent))
		observation.crest_normal_g = minimum_normal
		observation.unload_g = float(solved.unload_g)
	return observation


## The crest contract, measured from the pitch-zero crossing: the apex is the one downward
## `theta = 0` crossing strictly inside the role, height is monotone up to it and monotone down
## after it. A beat handed a descending frame is measured rather than refused outright - it may
## lose height while it is still nose-down, so the monotone climb is required only from where the
## climb starts - but prominence is the design's own `y_apex - max(y_entry, y_exit)`, measured
## from the entry the design names and not from that later climb start. That is the stricter
## reading of the two, and it is the acceptance formula: a beat that never gets its apex back
## above the frame it was handed does not stand above its own endpoints, whatever it does in
## between. `elevation_bound_m` publishes the same measurement, so a handover this family cannot
## crest back over publishes no window at all rather than refusing every elevation inside one.
static func _apex(route: Dictionary, entry_tangent: Vector3) -> Dictionary:
	var count: int = route.time_s.size()
	var climb_start := _climb_start(route)
	var crossings := 0
	var apex := -1
	var state := 0.0
	var rising := climb_start
	for index in count:
		var pitch_sin := float(route.tangent[index].y)
		if absf(pitch_sin) <= PITCH_TOLERANCE_RAD:
			continue
		var current := signf(pitch_sin)
		if state > 0.0 and current < 0.0:
			crossings += 1
			apex = _nearest_level(route, rising, index)
		if current > 0.0:
			rising = index
		state = current
	var normal := (entry_tangent.cross(Vector3.UP)).normalized()
	var out_of_plane := 0.0
	var monotone := apex > 0 and apex < count - 1
	for index in count:
		out_of_plane = maxf(out_of_plane,
			absf((route.position_m[index] - route.position_m[0]).dot(normal)))
		var climbed := float(route.tangent[index].y)
		if index < climb_start or index > apex:
			monotone = monotone and climbed <= PITCH_TOLERANCE_RAD
		elif index < apex:
			monotone = monotone and climbed >= -PITCH_TOLERANCE_RAD
	var apex_height: float = route.position_m[apex].y if apex >= 0 else route.position_m[0].y
	var apex_rate := 0.0
	var apex_distance := 0.0
	if apex >= 0:
		apex_rate = float(route.curvature_vector_m_inv[apex].dot(
			normal.cross(route.tangent[apex])))
		apex_distance = float(route.distance_m[apex]) - float(route.distance_m[0])
	return {"pitch_zero_crossings": crossings, "apex_distance_m": apex_distance,
		"apex_height_m": apex_height, "apex_pitch_rate_m_inv": apex_rate,
		"prominence_m": apex_height - maxf(route.position_m[0].y,
			route.position_m[-1].y),
		"monotone_phases": monotone, "out_of_plane_m": out_of_plane}


## Where the beat starts climbing: the entry when it is handed a level or climbing frame, the
## upward pitch-zero crossing when it is handed a descending one.
static func _climb_start(route: Dictionary) -> int:
	if float(route.tangent[0].y) >= -PITCH_TOLERANCE_RAD:
		return 0
	for index in route.time_s.size():
		if float(route.tangent[index].y) >= -PITCH_TOLERANCE_RAD:
			return index
	return route.time_s.size() - 1


## The sample closest to level between the last climbing sample and the first descending one:
## the apex itself sits inside the deadband, where the crossing is detected a step or two late.
static func _nearest_level(route: Dictionary, from_index: int, to_index: int) -> int:
	var apex := from_index
	for index in range(from_index, to_index + 1):
		if absf(float(route.tangent[index].y)) < absf(float(route.tangent[apex].y)):
			apex = index
	return apex


## Every contract this element must prove, as a slack: a negative or non-finite value refuses the
## element and names itself. Load slacks are taken against the duration-dependent envelope at the
## element's own integrated duration, which is the conservative reading of a curve whose brief
## ceilings are its most permissive points; `RideVerify`'s held-curve measurement over the
## assembled route remains the authority.
static func _margins(assignment: Dictionary, observation: Dictionary) -> Dictionary:
	var band: Vector2 = assignment.corridor.length_band_m
	var arc: float = observation.arc_length_m
	var duration: float = observation.duration_s
	var margins := {
		"length_band_m": minf(arc - band.x, band.y - arc),
		"target_length_m": LENGTH_TOLERANCE_M
			- absf(arc - float(assignment.target_length_m)),
		"corridor_offset_m": CORRIDOR_TOLERANCE_FRACTION * float(assignment.target_length_m)
			- float(observation.corridor_offset_m),
		"normal_positive_g": RideVerify.limit_at(RideVerify.POSITIVE_LIMIT, duration)
			- float(observation.peak_normal_g),
		"normal_negative_g": RideVerify.limit_at(RideVerify.NEGATIVE_LIMIT, duration)
			+ float(observation.minimum_normal_g),
		"lateral_g": RideVerify.limit_at(RideVerify.LATERAL_LIMIT, duration)
			- float(observation.peak_lateral_g),
		"roll_rate_deg_s": RideVerify.ROLL_RATE_LIMIT
			- rad_to_deg(float(observation.peak_roll_rate_rad_s)),
		"exit_pitch_rad": PITCH_TOLERANCE_RAD - absf(float(observation.exit_pitch_rad)),
		"exit_bank_rad": BANK_TOLERANCE_RAD - absf(float(observation.exit_bank_rad)),
		"elevation_change_m": ELEVATION_TOLERANCE_M - absf(
			float(observation.elevation_change_m) - float(assignment.elevation_change_m)),
		"entry_curvature_m_inv": CURVATURE_TOLERANCE_M_INV
			- float(observation.entry_jets.curvature.length()),
		"exit_curvature_m_inv": CURVATURE_TOLERANCE_M_INV
			- float(observation.exit_jets.curvature.length()),
	}
	if str(assignment.family) == TURN_FAMILY:
		var lateral := absf(float(observation.core_lateral_g))
		var direction := signf(float(assignment.heading_change_rad))
		margins.heading_change_rad = HEADING_TOLERANCE_RAD - absf(
			float(observation.heading_change_rad) - float(assignment.heading_change_rad))
		margins.counter_lateral_low_g = lateral - COUNTER_LATERAL_BAND_G.x
		margins.counter_lateral_high_g = COUNTER_LATERAL_BAND_G.y - lateral
		margins.counter_lateral_inward_g = float(observation.inward_lateral_g) \
			+ LATERAL_SIGN_TOLERANCE_G
		margins.bank_sign_rad = direction * float(observation.peak_bank_rad)
		margins.bank_ceiling_rad = float(observation.bank_ceiling_rad) \
			- absf(float(observation.peak_bank_rad))
		margins.counter_bank_rad = BANK_TOLERANCE_RAD - float(observation.counter_bank_rad)
	else:
		margins.crest_unload_g = UNLOAD_TOLERANCE_G - absf(
			float(observation.crest_normal_g) - float(observation.unload_g))
		margins.apex_pitch_rate_m_inv = -float(observation.apex_pitch_rate_m_inv)
		margins.prominence_m = float(observation.prominence_m) - PROMINENCE_FLOOR_M
		margins.pitch_zero_crossings = 0.0 if observation.pitch_zero_crossings == 1 else -1.0
		margins.monotone_phases = 0.0 if observation.monotone_phases else -1.0
		margins.out_of_plane_m = PLANARITY_TOLERANCE_FRACTION * arc \
			- float(observation.out_of_plane_m)
	return margins


## The analytic curvature jets at one element boundary, resolved in the boundary's own pitch/yaw
## basis, plus the measured bank and the commanded twist rates. The world jets are `x'' = kappa`,
## `x''' = d(kappa)/ds` and `x'''' = d2(kappa)/ds2`, and the arc-length derivatives of the basis
## vectors are each proportional to `kappa` itself - `d(yaw_normal)/ds` follows from
## `d(t)/ds = kappa` - so at a boundary where `kappa` and its slope vanish the basis terms vanish
## with them and the world jets reduce to the commanded component derivatives. That precondition is
## measured, not assumed: the published `curvature` length is a refusing margin above.
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
		"bank": _bank(tangent, route.rider_up[index]), "twist_slope": twist.y / length,
		"twist_acceleration": twist.z / (length * length),
	}


## The coarse sanity value the spec demotes finite differencing to: the integrated path's own
## reading of `|x'''|` at the seam, to be compared with the analytic jets published either side of
## it. It is diagnostic only, carries no threshold and vetoes nothing.
##
## It is differenced on one route's own spacing, and that is the whole reason it can read anything.
## A spatial span's last step is truncated to end exactly on its declared length, so the interval
## before a seam is a fraction of the one before that - 0.470 m against 0.722 m on the measured
## turn/height seam - and a third difference taken across that change reads the spacing, not the
## geometry: 1.339 against 1.013e-4 on the same seam. The four samples below all sit on full steps
## of the arriving element, the first of which is the seam point itself.
static func _finite_difference(next: Dictionary) -> float:
	if next.position_m.size() < 4:
		return 0.0
	var h: float = maxf(float(next.distance_m[1]) - float(next.distance_m[0]), 0.000001)
	return (next.position_m[3] - 3.0 * next.position_m[2] + 3.0 * next.position_m[1]
		- next.position_m[0]).length() / (h * h * h)


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


## The deepest lateral the turn holds through its loaded core - the samples between the two
## shoulders. The shoulders carry their own transient shape, and the band is a contract on the
## held value; the pointwise inward margin is what governs everything outside the core.
static func _core_peak_signed(route: Dictionary, length_m: float) -> float:
	var peak := 0.0
	for index in route.time_s.size():
		var u := (float(route.distance_m[index]) - float(route.distance_m[0])) / length_m
		if u < SHOULDER_FRACTION or u > 1.0 - SHOULDER_FRACTION:
			continue
		if absf(float(route.lateral_g[index])) > absf(peak):
			peak = float(route.lateral_g[index])
	return peak


static func _quintic(u: float) -> float:
	var c := clampf(u, 0.0, 1.0)
	return c * c * c * (10.0 + c * (-15.0 + 6.0 * c))


static func _quintic_integral(u: float) -> float:
	var c := clampf(u, 0.0, 1.0)
	return c * c * c * c * (2.5 + c * (-3.0 + c))
