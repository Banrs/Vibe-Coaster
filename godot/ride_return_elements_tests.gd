extends SceneTree

## Contract tests for the two local return element families. Every assertion measures the
## integrated result: the preview is a target, so a claim about geometry is only accepted when
## the production integrator produced it.

const Elements := preload("res://ride_return_elements.gd")
const Layout := preload("res://ride_return_layout.gd")
const Motion := preload("res://motion.gd")

## The handover pitches each family absorbs, up to the layout's 35 deg ceiling. Two cases are
## physical refusals rather than contract cases, and each has its own test below: levelling out of
## a climb is a pushover, which no overbanked turn can hold the rider down the bank through, and
## pulling out of a 35 deg dive inside a height beat's declared arc costs more than the held normal
## limit at these speeds.
const ENTRY_PITCH_DEG := [-35.0, -20.0, -6.0, 0.0]
const HEIGHT_ENTRY_PITCH_DEG := [-20.0, -6.0, 0.0, 20.0]
const TURN_LENGTH_BAND_EDGES_M := [420.0, 620.0, 430.0, 570.0]
const HEIGHT_LENGTH_M := 380.0

var _t := TestUtil.new()


func _initialize() -> void:
	_test_turn_preview_matches_integrated_geometry_at_70_and_80_mps()
	_test_turn_bank_and_curvature_sign_agree()
	_test_turn_lateral_lands_inside_the_counter_lateral_band()
	_test_turn_absorbs_its_entry_pitch_and_hands_over_a_level_frame()
	_test_the_pitch_level_out_is_one_shared_profile()
	_test_turn_lateral_points_inward_at_every_sample()
	_test_a_climb_the_counter_lateral_band_cannot_hold_is_refused_by_name()
	_test_a_dive_too_steep_to_pull_out_of_is_refused_by_name()
	_test_the_bank_ceiling_is_the_roll_the_envelope_allows()
	_test_the_macro_heading_bound_consumes_the_bank_ceiling()
	_test_height_absorbs_its_entry_pitch_and_hands_over_a_level_frame()
	_test_height_is_vertical_plane_at_70_and_80_mps()
	_test_height_has_one_pitch_zero_apex_and_monotone_phases()
	_test_element_seams_meet_the_c4_contract()
	_test_impossible_corridor_returns_one_structured_failure()
	_t.finish(self)


## The turn authors world yaw curvature, so its centreline is a function of arc length alone:
## the same assignment traced by the preview and integrated at either end of the entry-speed
## band must land on the same place, pointing the same way, however differently it is banked.
func _test_turn_preview_matches_integrated_geometry_at_70_and_80_mps() -> void:
	var assignment := _turn_assignment(0.40)
	var traced := Elements.preview(assignment, 1.0)
	var slow := Elements.build(_state(70.0), assignment, _settings())
	var fast := Elements.build(_state(80.0), assignment, _settings())
	if not _expect_built(traced, "turn preview traces") \
			or not _expect_built(slow, "turn builds at 70 m/s") \
			or not _expect_built(fast, "turn builds at 80 m/s"):
		return
	_t.expect(_local_end(slow).position.distance_to(_local_end(fast).position) <= 0.05,
		"spatial turn identity is speed-invariant")
	_t.expect(_angle(_local_end(slow).tangent, _local_end(fast).tangent) <= 0.0001,
		"spatial turn heading is speed-invariant")
	_t.expect(traced.end_frame.position_m.distance_to(_local_end(slow).position) <= 0.05,
		"preview endpoint matches the integrated endpoint")
	_t.expect(_angle(traced.end_frame.tangent, _local_end(slow).tangent) <= 0.0001,
		"preview tangent matches the integrated tangent")
	_t.expect_close(slow.observation.heading_change_rad, 0.40,
		"the turn delivers its assigned heading change", 0.001)
	_t.expect_close(slow.observation.arc_length_m, 420.0,
		"the turn spends exactly its allocated arc", 0.000001)
	_t.expect(slow.observation.speed_change_mps < 0.0,
		"an unpowered return turn only loses speed")


## Bank sits on the same side as the horizontal curvature and the rider is pressed down that
## bank, and the roll is one narrative: in, held, out - never a restart or a counter-bank.
func _test_turn_bank_and_curvature_sign_agree() -> void:
	for heading in [0.40, -0.40]:
		var built := Elements.build(_state(75.0), _turn_assignment(heading), _settings())
		if not _expect_built(built, "turn builds at heading %.2f rad" % heading):
			continue
		var observation: Dictionary = built.observation
		_t.expect_close(signf(observation.peak_bank_rad), signf(heading),
			"bank leans into the curvature at heading %.2f rad" % heading)
		_t.expect_close(signf(observation.signed_peak_lateral_g), -signf(heading),
			"lateral load points down the bank at heading %.2f rad" % heading)
		_t.expect_max(observation.counter_bank_rad, 0.0001,
			"the turn never banks against its curvature at heading %.2f rad" % heading)
		_t.expect_max(float(observation.roll_reversals), 1.0,
			"the roll is one motion in and one motion out at heading %.2f rad" % heading)


## The measured Falcon counterpart is 77 deg of bank at 2.39 g, whose balanced bank would be
## 65.8 deg: 0.47 g of counter-lateral. A laterally neutral turn is a contract failure here.
func _test_turn_lateral_lands_inside_the_counter_lateral_band() -> void:
	for speed in [70.0, 75.0, 80.0]:
		var built := Elements.build(_state(speed), _turn_assignment(0.40), _settings())
		if not _expect_built(built, "turn builds at %.0f m/s" % speed):
			continue
		var lateral: float = absf(built.observation.signed_peak_lateral_g)
		_t.expect_range(lateral, 0.2, 0.6,
			"peak lateral sits inside the counter-lateral band at %.0f m/s" % speed)
		_t.expect_close(lateral, 0.47,
			"peak lateral reaches the measured counterpart at %.0f m/s" % speed, 0.02)
		_t.expect(built.observation.peak_bank_rad > built.observation.balanced_bank_rad,
			"the turn is overbanked, not balanced, at %.0f m/s" % speed)


## Zero yaw curvature and zero twist keep the beat in the vertical plane through its entry
## tangent at either end of the entry-speed band, whatever shape the local solve chose.
func _test_height_is_vertical_plane_at_70_and_80_mps() -> void:
	for speed in [70.0, 80.0]:
		var built := Elements.build(_state(speed), _height_assignment(-8.0), _settings())
		if not _expect_built(built, "height builds at %.0f m/s" % speed):
			continue
		_t.expect_max(built.observation.out_of_plane_m, 0.001,
			"the height beat stays in one vertical plane at %.0f m/s" % speed)
		_t.expect_max(built.observation.peak_lateral_g, 0.0001,
			"a vertical-plane beat carries no lateral load at %.0f m/s" % speed)
		_t.expect_max(absf(built.observation.exit_bank_rad), 0.0001,
			"the height beat leaves the frame unbanked at %.0f m/s" % speed)


func _test_height_has_one_pitch_zero_apex_and_monotone_phases() -> void:
	var built := Elements.build(_state(75.0), _height_assignment(-8.0), _settings())
	if not _expect_built(built, "height builds at 75 m/s"):
		return
	var observation: Dictionary = built.observation
	_t.expect_close(float(observation.pitch_zero_crossings), 1.0,
		"the beat crests exactly once")
	_t.expect(observation.apex_pitch_rate_m_inv < 0.0,
		"the apex is a downward pitch crossing")
	_t.expect(observation.monotone_phases, "the beat climbs to its apex and descends after it")
	_t.expect_min(observation.prominence_m, 3.0, "the apex stands above both endpoints")
	_t.expect_close(observation.elevation_change_m, -8.0,
		"the beat delivers its assigned elevation change", 0.1)
	_t.expect_close(observation.exit_pitch_rad, 0.0, "the beat exits level", 0.0004)
	_t.expect_close(observation.crest_normal_g, -0.45,
		"the crest reaches the planner unload target", 0.01)


## Every family absorbs the pitch it is handed and hands the next stage a level, unbanked frame:
## the first return role is entered on the record release's exit pitch, and the macro stage's
## gate contract assumes the last role closes pitch and roll by construction.
func _test_turn_absorbs_its_entry_pitch_and_hands_over_a_level_frame() -> void:
	for pitch_deg: float in ENTRY_PITCH_DEG:
		for speed: float in [70.0, 80.0]:
			var start := _state(speed, pitch_deg)
			var assignment := _turn_assignment(0.40, start)
			var built := Elements.build(start, assignment, _settings())
			var label := "%.0f deg at %.0f m/s" % [pitch_deg, speed]
			if not _expect_built(built, "the turn absorbs %s" % label):
				continue
			var observation: Dictionary = built.observation
			_t.expect_close(observation.heading_change_rad, 0.40,
				"the turn delivers its assigned heading from %s" % label, 0.001)
			_t.expect_close(observation.exit_pitch_rad, 0.0,
				"the turn hands over a level frame from %s" % label, 0.0004)
			_t.expect_close(observation.exit_bank_rad, 0.0,
				"the turn hands over an unbanked frame from %s" % label, 0.0001)
			_t.expect_close(observation.elevation_change_m,
				float(assignment.elevation_change_m),
				"the turn delivers the elevation the macro stage assigned it from %s" % label,
				5.0)


## The pitch level-out exists once: the macro elevation model evaluates the same profile the
## element commands, and the integrated track pitch follows it sample by sample.
func _test_the_pitch_level_out_is_one_shared_profile() -> void:
	for pitch_deg: float in [-35.0, -6.0, 20.0]:
		var pitch := deg_to_rad(pitch_deg)
		for index in 21:
			var u := float(index) / 20.0
			_t.expect_close(Layout._sin_pitch(pitch, 0.0, u),
				sin(Elements.level_out_pitch_rad(pitch, u)),
				"the macro elevation model is the element's pitch profile at u=%.2f" % u,
				0.000000000001)
	var start := _state(80.0, -20.0)
	var built := Elements.build(start, _turn_assignment(0.40, start), _settings())
	if not _expect_built(built, "the shared-profile turn builds"):
		return
	var route: Dictionary = built.trajectory
	var length := float(route.distance_m[-1]) - float(route.distance_m[0])
	var deepest := 0.0
	for index in route.time_s.size():
		var u := (float(route.distance_m[index]) - float(route.distance_m[0])) / length
		deepest = maxf(deepest, absf(asin(clampf(route.tangent[index].y, -1.0, 1.0))
			- Elements.level_out_pitch_rad(deg_to_rad(-20.0), u)))
	_t.expect_max(deepest, 0.0004,
		"the integrated track pitch follows the commanded level-out profile")


## The counter-lateral band is a pointwise contract: the rider is pressed down the bank at every
## sample, never outward through the roll-in or roll-out shoulder.
func _test_turn_lateral_points_inward_at_every_sample() -> void:
	for heading in [0.9, -0.9]:
		var start := _state(80.0)
		var assignment := _turn_assignment(heading, start, 590.0, Vector2(560.0, 620.0))
		var built := Elements.build(start, assignment, _settings())
		if not _expect_built(built, "the fast turn builds at heading %.2f rad" % heading):
			continue
		_t.expect_min(built.observation.inward_lateral_g, -Elements.LATERAL_SIGN_TOLERANCE_G,
			"no sample carries outward lateral at heading %.2f rad" % heading)
		_t.expect_range(absf(float(built.observation.core_lateral_g)), 0.2, 0.6,
			"the held core sits inside the counter-lateral band at heading %.2f rad" % heading)


## Levelling out of a climb is a pushover, and a pushover cannot press the rider down the bank.
## That is a physical refusal with named margins, not a silently outward turn.
func _test_a_climb_the_counter_lateral_band_cannot_hold_is_refused_by_name() -> void:
	var start := _state(80.0, 20.0)
	var built := Elements.build(start, _turn_assignment(0.40, start), _settings())
	_t.expect(not built.ok, "a turn that must push over out of a climb is refused")
	_t.expect(_t.contains(built.errors, "counter_lateral"),
		"the refusal names the counter-lateral contract it missed: %s" % str(built.errors))


## The bank a turn may reach is the roll the envelope allows across its shoulder, not the
## geometric ceiling: a quintic shoulder's peak slope is 1.875, so the roll-rate limit caps bank
## at `limit * shoulder / (1.875 v)` before the 77 deg counterpart ceiling ever binds.
func _test_the_bank_ceiling_is_the_roll_the_envelope_allows() -> void:
	_t.expect_close(Elements.max_bank_rad(420.0, 80.0),
		deg_to_rad(RideVerify.ROLL_RATE_LIMIT) * Elements.SHOULDER_FRACTION * 420.0
			/ (1.875 * 80.0),
		"the bank ceiling is the roll rate the envelope allows over the shoulder",
		0.000000000001)
	_t.expect(Elements.max_bank_rad(420.0, 80.0) < Elements.max_bank_rad(420.0, 70.0),
		"the bank ceiling falls as entry speed rises")
	_t.expect(Elements.max_bank_rad(420.0, 80.0) < Elements.max_bank_rad(620.0, 80.0),
		"the bank ceiling rises with the arc the shoulder is given")
	_t.expect_close(Elements.max_bank_rad(900.0, 70.0), Elements.TURN_BANK_CEILING_RAD,
		"a long enough shoulder reaches the counterpart's geometric ceiling")


## What the macro stage may assign is what a family can build: the heading at the bound is
## buildable at the top of the entry-speed band, at every declared turn-length band edge.
func _test_the_macro_heading_bound_consumes_the_bank_ceiling() -> void:
	var bank := Elements.max_bank_rad(420.0, 80.0)
	_t.expect_close(Layout.heading_bound_rad(420.0, 80.0),
		Elements.LOADED_ARC_FRACTION * 420.0 * Motion.G0
			* (sin(bank) - Elements.COUNTER_LATERAL_TARGET_G) / (cos(bank) * 6400.0),
		"the macro bound is the counter-lateral identity at the family's bank ceiling",
		0.000000000001)
	_t.expect(Layout.heading_bound_rad(420.0, 80.0) < Layout.heading_bound_rad(420.0, 70.0),
		"the macro heading bound falls as entry speed rises")
	for length: float in TURN_LENGTH_BAND_EDGES_M:
		var start := _state(80.0)
		var heading := Layout.heading_bound_rad(length, 80.0)
		var built := Elements.build(start, _turn_assignment(heading, start, length,
			Vector2(length - 10.0, length + 10.0)), _settings())
		if not _expect_built(built, "the heading at the bound builds over %.0f m" % length):
			continue
		_t.expect_close(built.observation.heading_change_rad, heading,
			"the turn delivers the bound's heading over %.0f m" % length, 0.001)
		_t.expect_range(absf(float(built.observation.core_lateral_g)), 0.2, 0.6,
			"the bound's turn still holds the counter-lateral band over %.0f m" % length)


func _test_height_absorbs_its_entry_pitch_and_hands_over_a_level_frame() -> void:
	for pitch_deg: float in HEIGHT_ENTRY_PITCH_DEG:
		for speed: float in [70.0, 80.0]:
			var start := _state(speed, pitch_deg)
			var assignment := _height_assignment_from(start, -8.0)
			var built := Elements.build(start, assignment, _settings())
			var label := "%.0f deg at %.0f m/s" % [pitch_deg, speed]
			if not _expect_built(built, "the height beat absorbs %s" % label):
				continue
			var observation: Dictionary = built.observation
			_t.expect_close(float(observation.pitch_zero_crossings), 1.0,
				"the beat crests exactly once from %s" % label)
			_t.expect(observation.monotone_phases,
				"the beat climbs to its apex and descends after it from %s" % label)
			_t.expect_close(observation.exit_pitch_rad, 0.0,
				"the beat hands over a level frame from %s" % label, 0.0004)
			_t.expect_close(observation.exit_bank_rad, 0.0,
				"the beat hands over an unbanked frame from %s" % label, 0.0001)
			_t.expect_close(observation.elevation_change_m,
				float(assignment.elevation_change_m),
				"the beat delivers its assigned elevation from %s" % label, 5.0)


## Pulling out of a 35 deg dive and still cresting costs more than the held normal limit inside a
## height beat's declared arc at return speeds: at 380 m the pull-up peaks at 4.5-5.1 g against a
## 4.0 g held ceiling, and an elevation shallow enough to stay inside the ceiling never lifts the
## track pitch above zero, so there is no crest to measure. The turn family absorbs that handover;
## this one names what it missed.
func _test_a_dive_too_steep_to_pull_out_of_is_refused_by_name() -> void:
	for speed: float in [70.0, 80.0]:
		var start := _state(speed, -35.0)
		var built := Elements.build(start, _height_assignment_from(start, -8.0), _settings())
		_t.expect(not built.ok,
			"a height beat handed a 35 deg dive at %.0f m/s is refused" % speed)
		_t.expect(_t.contains(built.errors, "normal_positive_g")
			or _t.contains(built.errors, "height_solve"),
			"the refusal names the load it could not pull out inside: %s" % str(built.errors))


## The seam evidence splits by order: position, tangent and the world curvature vector are
## compared directly from the integrated route; the third and fourth position derivatives come
## from each side's analytic curvature jets, because differencing float32 positions at this
## spacing measures rounding rather than geometry.
func _test_element_seams_meet_the_c4_contract() -> void:
	var turn := Elements.build(_state(75.0), _turn_assignment(0.40), _settings())
	if not _expect_built(turn, "seam turn builds"):
		return
	var height := Elements.build(turn.end_state,
		_height_assignment_from(turn.end_state, -8.0), _settings())
	if not _expect_built(height, "seam height builds"):
		return
	var seam := Elements.seam_residuals(turn, height)
	_t.expect(seam.ok, "the turn/height seam meets the C4 contract")
	_t.expect_max(seam.position_m, Elements.POSITION_TOLERANCE_M, "seam position agrees")
	_t.expect_max(seam.tangent, Elements.TANGENT_TOLERANCE, "seam tangent agrees")
	_t.expect_max(seam.curvature_m_inv, Elements.CURVATURE_TOLERANCE_M_INV,
		"seam world curvature agrees")
	_t.expect_max(seam.integrated_curvature_m_inv, Elements.CURVATURE_TOLERANCE_M_INV,
		"the integrated curvature either side of the seam agrees")
	_t.expect_max(seam.curvature_slope_m2, Elements.CURVATURE_TOLERANCE_M_INV,
		"the analytic third-order jets agree")
	_t.expect_max(seam.curvature_acceleration_m3, Elements.CURVATURE_TOLERANCE_M_INV,
		"the analytic fourth-order jets agree")
	_t.expect_max(seam.bank_rad, Elements.BANK_TOLERANCE_RAD, "seam bank agrees")
	_t.expect_max(seam.twist_slope_rad_m, 0.000001, "seam twist slope agrees")
	_t.expect_max(seam.twist_acceleration_rad_m2, 0.000001,
		"seam twist acceleration agrees")


func _test_impossible_corridor_returns_one_structured_failure() -> void:
	var assignment := _turn_assignment(0.40)
	assignment.corridor = {"centerline_m": assignment.corridor.centerline_m,
		"length_band_m": Vector2(10.0, 20.0)}
	var built := Elements.build(_state(75.0), assignment, _settings())
	_t.expect(not built.ok, "an impossible corridor is refused")
	if not _t.expect(built.errors.size() == 1,
			"the refusal is one structured failure, got %d" % built.errors.size()):
		return
	_t.expect(str(built.errors[0].code) == "corridor_length_band",
		"the refusal names the corridor band it cannot satisfy")
	_t.expect(built.spans.is_empty() and int(built.evaluation_count) == 0,
		"a refused element integrates nothing")


func _state(speed_mps: float, pitch_deg: float = 0.0) -> Dictionary:
	var pitch := deg_to_rad(pitch_deg)
	var tangent := Vector3(cos(pitch), sin(pitch), 0.0)
	return {"position_m": Vector3.ZERO, "tangent": tangent,
		"rider_up": Vector3.UP.slide(tangent).normalized(), "speed_mps": speed_mps,
		"distance_m": 0.0, "time_s": 0.0}


func _settings() -> Dictionary:
	return {"step_s": 0.01, "gravity_mps2": Vector3.DOWN * Motion.G0,
		"rolling_mps2": RideProgram.ROLLING_MPS2, "aero_per_m": RideProgram.AERO_PER_M}


func _local_end(result: Dictionary) -> Dictionary:
	var end: Dictionary = result.end_state
	return {"position": end.position_m - result.trajectory.position_m[0],
		"tangent": end.tangent}


func _angle(a: Vector3, b: Vector3) -> float:
	return acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0))


## A 420 m turn through 0.40 rad: the counter-lateral band is reachable inside the family's bank
## ceiling across the whole 70-80 m/s entry band, and its roll stays under the envelope.
func _turn_assignment(heading_change_rad: float, start: Dictionary = {},
		length_m: float = 420.0, length_band_m: Vector2 = Vector2(380.0, 460.0)) -> Dictionary:
	var state: Dictionary = start if not start.is_empty() else _state(75.0)
	return _with_corridor({
		"role_id": "return-turn-a", "family": "return_turn",
		"entry_frame": _frame(state.position_m, state.tangent, state.rider_up),
		"target_length_m": length_m, "terrain_intent": {},
		"curvature_sign": signf(heading_change_rad),
		"heading_change_rad": heading_change_rad, "elevation_change_m": 0.0,
	}, length_band_m)


func _height_assignment(extra_elevation_m: float) -> Dictionary:
	return _height_assignment_from(_state(75.0), extra_elevation_m)


## A macro assignment for one height beat, published the way the layout publishes one: the
## corridor is the macro chain's own vertical-plane trace, and the net elevation is read off the
## same model.
func _height_assignment_from(start: Dictionary, extra_elevation_m: float) -> Dictionary:
	var elevation := _height_elevation_m(start, HEIGHT_LENGTH_M, extra_elevation_m)
	return {
		"role_id": "return-height-a", "family": "return_height",
		"entry_frame": _frame(start.position_m, start.tangent, start.rider_up),
		"target_length_m": HEIGHT_LENGTH_M, "terrain_intent": {}, "curvature_sign": 0.0,
		"heading_change_rad": 0.0, "elevation_change_m": elevation, "unload_g": -0.45,
		"corridor": {"centerline_m": _macro_centerline(start, elevation),
			"length_band_m": Vector2(340.0, 420.0)},
	}


## The elevation a macro chain assigns a height beat: half the height it would spend levelling out
## of the pitch it was handed, plus the height the beat itself is asked to add or give up. The
## halving is what leaves the beat a crest: an assignment that spends the whole level-out drop
## never lifts the track pitch above zero, and one that spends none of it asks the beat to climb
## out of its own handover, which is a length request rather than a height one.
func _height_elevation_m(start: Dictionary, length_m: float, extra_m: float) -> float:
	var pitch := asin(clampf((start.tangent as Vector3).normalized().y, -1.0, 1.0))
	var total := 0.0
	for index in 401:
		var weight := (0.5 if index == 0 or index == 400 else 1.0) / 400.0
		total += weight * sin(Elements.level_out_pitch_rad(pitch, float(index) / 400.0))
	return 0.5 * length_m * total + extra_m


## The macro chain's own trace of that assignment: one vertical plane, the shared level-out plus
## the chain's symmetric elevation bump, integrated the way `RideReturnLayout` integrates it.
func _macro_centerline(start: Dictionary, elevation_m: float) -> PackedVector3Array:
	var pitch := asin(clampf((start.tangent as Vector3).normalized().y, -1.0, 1.0))
	var bump := 2.0 * elevation_m / HEIGHT_LENGTH_M - sin(pitch)
	var tangent: Vector3 = (start.tangent as Vector3).normalized()
	var forward := (tangent - Vector3.UP * tangent.dot(Vector3.UP)).normalized()
	var position: Vector3 = start.position_m
	var line := PackedVector3Array([position])
	var samples := 24
	for index in samples:
		var sin_pitch := Layout._sin_pitch(pitch, bump, (float(index) + 0.5) / samples)
		position += (HEIGHT_LENGTH_M / samples) * (forward
			* sqrt(maxf(1.0 - sin_pitch * sin_pitch, 0.0)) + Vector3.UP * sin_pitch)
		line.append(position)
	return line


func _frame(position: Vector3, tangent: Vector3, rider_up: Vector3) -> Dictionary:
	return {"position_m": position, "tangent": tangent, "rider_up": rider_up}


## The corridor and the net elevation a layout publishes are both read off its nominal chain, so
## the fixture takes them from the same target trace the macro stage would.
func _with_corridor(assignment: Dictionary, length_band_m: Vector2) -> Dictionary:
	var traced := Elements.preview(assignment, 1.0)
	assignment.corridor = {"centerline_m": traced.get("centerline_m", PackedVector3Array()),
		"length_band_m": length_band_m}
	if str(assignment.family) == "return_turn":
		assignment.elevation_change_m = float(traced.get("elevation_change_m", 0.0))
	return assignment


func _expect_built(result: Dictionary, message: String) -> bool:
	if result.get("ok", false):
		return true
	_t.expect(false, "%s: %s" % [message, str(result.get("errors", []))])
	return false
