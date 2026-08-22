extends SceneTree

## Contract tests for the two local return element families. Every assertion measures the
## integrated result: the preview is a target, so a claim about geometry is only accepted when
## the production integrator produced it.

const Elements := preload("res://ride_return_elements.gd")
const Layout := preload("res://ride_return_layout.gd")
const Motion := preload("res://motion.gd")

## The handover pitches the turn family absorbs, up to the layout's 35 deg ceiling and including
## the camelback's own 33.6 deg exit. Levelling out of a climb is the family's one physical
## refusal - a pushover cannot press the rider down the bank - and it has its own test below.
const ENTRY_PITCH_DEG := [-35.0, -33.6, -20.0, -6.0, 0.0]
## The handovers the height family absorbs. It is a narrower set than the turn's: a beat entered
## nose-down has to get its apex back above the frame it was handed, and past about -10 deg it
## cannot inside its declared arc at return speeds. Those are refusals with no window at all - the
## test below measures them - not elevations that build badly.
const HEIGHT_ENTRY_PITCH_DEG := [-10.0, -6.0, 0.0, 20.0]
const HEIGHT_REFUSED_PITCH_DEG := [-35.0, -20.0]
const TURN_LENGTH_BAND_EDGES_M := [420.0, 620.0, 430.0, 570.0]
const HEIGHT_LENGTH_M := 380.0
## The declared return height band edges - 290-480 m for the first beat and 450-590 m for the
## second - at both ends of the entry-speed band and at every handover the family accepts,
## climbing included. The macro stage builds its elevation box at the shortest allocable arc and
## at the fastest role entry, but water-filling can hand a role any length inside its band, so the
## whole span of both bands is a corner the contract has to hold at.
const ELEVATION_PROBES := [[290.0, 80.0, 0.0], [290.0, 70.0, 0.0], [450.0, 80.0, 0.0],
	[450.0, 70.0, 0.0], [290.0, 80.0, -6.0], [450.0, 70.0, -10.0], [290.0, 70.0, 20.0],
	[380.0, 80.0, 20.0], [450.0, 70.0, 20.0], [590.0, 70.0, -6.0], [590.0, 75.0, -6.0],
	[590.0, 80.0, 0.0]]
## What the macro chain and the build may differ by. Both trace the same profiles; what is left is
## the chain's 24-interval Simpson quadrature against the integrator's own pitch tracking, and the
## sum is three orders inside the 5 m residual scale the macro stage converges its chain at.
const HEADING_CHAIN_TOLERANCE_M := 0.05
## The corners the macro corridor is measured at: the top of each declared height band, where a
## corridor that modelled a net-elevation ramp instead of the family's crest disagrees most,
## because that disagreement is the beat's own prominence and prominence scales with arc.
const CORRIDOR_PROBES := [[590.0, 70.0, -6.0], [590.0, 80.0, 0.0], [480.0, 70.0, 0.0]]
## What the corridor's crest and the built crest may stand apart by. The corridor traces the knots
## the local solve starts from and the build traces the knots it converged to, so what is left is
## that convergence read as a height: measured at 0.30 m over the corners above, against
## prominences of 0.8-63 m.
const CORRIDOR_PROMINENCE_TOLERANCE_M := 0.5

var _t := TestUtil.new()


func _initialize() -> void:
	_test_turn_preview_matches_integrated_geometry_at_70_and_80_mps()
	_test_turn_bank_and_curvature_sign_agree()
	_test_turn_lateral_lands_inside_the_counter_lateral_band()
	_test_turn_absorbs_its_entry_pitch_and_hands_over_a_level_frame()
	_test_the_pitch_level_out_is_one_shared_profile()
	_test_turn_lateral_points_inward_at_every_sample()
	_test_a_climb_the_counter_lateral_band_cannot_hold_is_refused_by_name()
	_test_a_descending_handover_the_beat_cannot_crest_over_is_refused_by_name()
	_test_the_bank_ceiling_is_the_roll_the_envelope_allows()
	_test_the_macro_heading_bound_is_buildable_at_the_handover_pitch()
	_test_the_heading_profile_is_one_shared_profile()
	_test_the_roll_ceiling_covers_the_exit_shoulder()
	_test_height_absorbs_its_entry_pitch_and_hands_over_a_level_frame()
	_test_height_is_vertical_plane_at_70_and_80_mps()
	_test_height_has_one_pitch_zero_apex_and_monotone_phases()
	_test_the_elevation_window_is_what_the_family_crests_through()
	_test_the_macro_corridor_is_the_crest_the_beat_stands()
	_test_the_elevation_window_follows_the_drawn_unload()
	_test_prominence_is_measured_from_the_frame_the_beat_was_handed()
	_test_a_hump_the_counterpart_would_not_call_a_beat_is_refused()
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
		var built := Elements.build(_state(speed), _height_assignment(0.35), _settings())
		if not _expect_built(built, "height builds at %.0f m/s" % speed):
			continue
		_t.expect_max(built.observation.out_of_plane_m, 0.001,
			"the height beat stays in one vertical plane at %.0f m/s" % speed)
		_t.expect_max(built.observation.peak_lateral_g, 0.0001,
			"a vertical-plane beat carries no lateral load at %.0f m/s" % speed)
		_t.expect_max(absf(built.observation.exit_bank_rad), 0.0001,
			"the height beat leaves the frame unbanked at %.0f m/s" % speed)


func _test_height_has_one_pitch_zero_apex_and_monotone_phases() -> void:
	var built := Elements.build(_state(75.0), _height_assignment(0.35), _settings())
	if not _expect_built(built, "height builds at 75 m/s"):
		return
	var observation: Dictionary = built.observation
	_t.expect_close(float(observation.pitch_zero_crossings), 1.0,
		"the beat crests exactly once")
	_t.expect(observation.apex_pitch_rate_m_inv < 0.0,
		"the apex is a downward pitch crossing")
	_t.expect(observation.monotone_phases, "the beat climbs to its apex and descends after it")
	_t.expect_min(observation.prominence_m, 3.0, "the apex stands above both endpoints")
	_t.expect_close(observation.elevation_change_m,
		float(_height_assignment(0.35).elevation_change_m),
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


## What the macro stage may assign is what a family can build, and the macro stage may sit a
## control on its bound: the heading at the bound builds at every declared turn-length band edge,
## at both ends of the entry-speed band, and at every handover pitch the family absorbs. The bound
## is a function of that handover, not of arc and speed alone - the level bound is a different
## number, and assigning it under a pitched handover is a build the family refuses.
func _test_the_macro_heading_bound_is_buildable_at_the_handover_pitch() -> void:
	for pitch_deg: float in ENTRY_PITCH_DEG:
		for speed: float in [70.0, 80.0]:
			for length: float in TURN_LENGTH_BAND_EDGES_M:
				_expect_bound_builds(length, speed, pitch_deg)
	_t.expect(Elements.heading_bound_rad(420.0, 80.0, 0.0)
		< Elements.heading_bound_rad(420.0, 70.0, 0.0),
		"the macro heading bound falls as entry speed rises")
	_t.expect(Elements.heading_bound_rad(420.0, 80.0, 0.0)
		< Elements.heading_bound_rad(620.0, 80.0, 0.0),
		"the macro heading bound rises with the arc it is given")
	var start := _state(70.0, -33.6)
	var level := Elements.heading_bound_rad(420.0, 70.0, 0.0)
	_t.expect(Elements.heading_bound_rad(420.0, 70.0, deg_to_rad(-33.6)) < level,
		"the camelback handover buys less heading than the level bound admits")
	_t.expect(not Elements.build(start, _turn_assignment(level, start, 420.0,
		Vector2(410.0, 430.0)), _settings()).ok,
		"the level bound is not a heading the camelback handover can build")


## One corner of the macro control box: the bound is buildable at its own edge, or it is zero and
## the macro stage has no heading to assign there at all.
func _expect_bound_builds(length_m: float, speed_mps: float, pitch_deg: float) -> void:
	var start := _state(speed_mps, pitch_deg)
	var bound := Elements.heading_bound_rad(length_m, speed_mps, _entry_pitch(start))
	var label := "%.0f m at %.0f m/s from %.1f deg" % [length_m, speed_mps, pitch_deg]
	if bound <= 0.0:
		_t.expect(not Elements.build(start, _turn_assignment(0.40, start, length_m,
			Vector2(length_m - 10.0, length_m + 10.0)), _settings()).ok,
			"a zero bound is a handover this family refuses over %s" % label)
		return
	var built := Elements.build(start, _turn_assignment(bound, start, length_m,
		Vector2(length_m - 10.0, length_m + 10.0)), _settings())
	if not _expect_built(built, "the heading at the bound builds over %s" % label):
		return
	_t.expect_close(built.observation.heading_change_rad, bound,
		"the turn delivers the bound's heading over %s" % label, 0.001)
	_t.expect_range(absf(float(built.observation.core_lateral_g)), 0.2, 0.6,
		"the bound's turn still holds the counter-lateral band over %s" % label)


func _test_height_absorbs_its_entry_pitch_and_hands_over_a_level_frame() -> void:
	for pitch_deg: float in HEIGHT_ENTRY_PITCH_DEG:
		for speed: float in [70.0, 80.0]:
			var start := _state(speed, pitch_deg)
			var assignment := _height_assignment_from(start, 0.35)
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


## The macro chain traces the same centreline the family builds. Heading is delivered against
## `sec(theta)`, so the plateau's own fraction is the level case only, and a chain that used it
## under the handover pitch drifted metres from the built path while still agreeing at both ends.
func _test_the_heading_profile_is_one_shared_profile() -> void:
	for index in 21:
		var u := float(index) / 20.0
		_t.expect_close(Elements.heading_fraction(0.0, u), Elements.plateau_fraction(u),
			"a level role delivers heading on the plateau fraction at u=%.2f" % u,
			0.000000000001)
	for pitch_deg: float in ENTRY_PITCH_DEG:
		var start := _state(80.0, pitch_deg)
		var built := Elements.build(start, _turn_assignment(0.40, start), _settings())
		if not _expect_built(built, "the shared-heading turn builds from %.0f deg" % pitch_deg):
			continue
		_t.expect_max(_chain_end(start, 0.40, 420.0).distance_to(built.end_state.position_m),
			HEADING_CHAIN_TOLERANCE_M,
			"the macro chain lands where the turn builds from %.0f deg" % pitch_deg)


## The published bank ceiling is a contract the bracket cannot break, not a margin measured
## afterward: it bounds the bank the rider measures - commanded twist plus the frame's own drift -
## and it is taken at the fastest speed the role reaches, because that is the speed the exit
## shoulder rolls at. A descending role therefore carries a lower ceiling than its entry speed
## alone would give it, and both shoulders stay inside the roll envelope either way.
func _test_the_roll_ceiling_covers_the_exit_shoulder() -> void:
	var length: float = TURN_LENGTH_BAND_EDGES_M[0]
	for pitch_deg: float in [-33.6, -20.0, 0.0, 10.0, 20.0]:
		var start := _state(80.0, pitch_deg)
		var built := Elements.build(start, _turn_assignment(0.40, start, length,
			Vector2(length - 10.0, length + 10.0)), _settings())
		var observation: Dictionary = built.observation
		if not _t.expect(not observation.is_empty(),
				"the turn is measured from %.1f deg: %s" % [pitch_deg, built.errors]):
			continue
		_t.expect_max(rad_to_deg(float(observation.peak_roll_rate_rad_s)),
			RideVerify.ROLL_RATE_LIMIT,
			"the roll stays inside the envelope from %.1f deg" % pitch_deg)
		_t.expect_max(absf(float(observation.peak_bank_rad)),
			float(observation.bank_ceiling_rad),
			"the measured bank stays inside the published ceiling from %.1f deg" % pitch_deg)
		if pitch_deg < 0.0:
			_t.expect(float(observation.bank_ceiling_rad)
				< Elements.max_bank_rad(length, 80.0),
				"a descending role's ceiling is taken at the speed it leaves at, not the speed"
					+ " it entered at, from %.1f deg" % pitch_deg)


## What the macro stage may assign is what this family can build: every net elevation inside the
## published window crests, stands the counterpart prominence above its endpoints and stays inside
## the load envelope - at the declared role lengths, entry speeds and handover pitches.
func _test_the_elevation_window_is_what_the_family_crests_through() -> void:
	for probe: Array in ELEVATION_PROBES:
		var length := float(probe[0])
		var speed := float(probe[1])
		var pitch_deg := float(probe[2])
		var window := Elements.elevation_bound_m(length, speed, deg_to_rad(pitch_deg))
		var label := "%.0f m at %.0f m/s from %.0f deg" % [length, speed, pitch_deg]
		if not _t.expect(window.x < window.y, "the family publishes a window for %s" % label):
			continue
		# The edges themselves, not a point just inside them: `BOUND_AGREEMENT_M` exists so that a
		# macro control sitting exactly on its bound still builds, and there is no retry behind a
		# bound. A claim made only near an edge would leave the edge itself untested, which is
		# precisely the region the macro stage clamps its controls into.
		for fraction: float in [0.0, 0.5, 1.0]:
			var start := _state(speed, pitch_deg)
			var elevation := lerpf(window.x, window.y, fraction)
			var assignment := _height_assignment_of(start, length, elevation)
			# What this test measures is the elevation contract, so it publishes no corridor
			# centreline: the macro corridor is a stated stand-in that models net elevation
			# rather than the crest, and the fixtures that carry one measure it.
			assignment.corridor = {"centerline_m": PackedVector3Array(),
				"length_band_m": assignment.corridor.length_band_m}
			var built := Elements.build(start, assignment, _settings())
			if not _expect_built(built,
					"%.1f m inside the window builds over %s" % [elevation, label]):
				continue
			_t.expect_min(built.observation.prominence_m, Elements.PROMINENCE_FLOOR_M,
				"the beat stands its counterpart prominence at %.1f m over %s"
					% [elevation, label])
			_t.expect_close(built.observation.elevation_change_m, elevation,
				"the beat delivers the elevation the window admits at %.1f m over %s"
					% [elevation, label], 0.1)


## The corridor the macro stage publishes is the shape this family builds on. Both stages trace one
## crest - the same staged curvature through the same knots - so the corridor stands the prominence
## the beat stands and the built centreline never leaves it. A corridor that modelled a
## net-elevation ramp instead would disagree by that whole prominence, and the disagreement grows
## with arc, so an accepted layout would carry an assignment the build refuses with no retry behind
## it.
func _test_the_macro_corridor_is_the_crest_the_beat_stands() -> void:
	for probe: Array in CORRIDOR_PROBES:
		var length := float(probe[0])
		var speed := float(probe[1])
		var pitch_deg := float(probe[2])
		var start := _state(speed, pitch_deg)
		var window := Elements.elevation_bound_m(length, speed, deg_to_rad(pitch_deg))
		for fraction: float in [0.1, 0.5, 0.9]:
			var elevation := lerpf(window.x, window.y, fraction)
			var assignment := _height_assignment_of(start, length, elevation)
			var built := Elements.build(start, assignment, _settings())
			var label := "%.1f m over %.0f m at %.0f m/s from %.0f deg" \
				% [elevation, length, speed, pitch_deg]
			if not _expect_built(built, "the beat builds on its macro corridor at %s" % label):
				continue
			_t.expect_min(built.margins.corridor_offset_m, 0.0,
				"the built centreline stays inside its macro corridor at %s" % label)
			_t.expect_close(_prominence(assignment.corridor.centerline_m),
				float(built.observation.prominence_m),
				"the macro corridor stands the prominence the beat stands at %s" % label,
				CORRIDOR_PROMINENCE_TOLERANCE_M)


## The crest a beat is authored to hold is a drawn value, so the window the macro stage reads is a
## function of it: a shallower unload curves the crest less and moves the elevation the family can
## crest through. The bound and the build are handed the same draw, and every elevation the window
## admits under it builds and reaches it.
func _test_the_elevation_window_follows_the_drawn_unload() -> void:
	var default_window := Elements.elevation_bound_m(HEIGHT_LENGTH_M, 75.0, 0.0)
	var drawn := -0.30
	var window := Elements.elevation_bound_m(HEIGHT_LENGTH_M, 75.0, 0.0, drawn)
	_t.expect(window.x < window.y, "the family publishes a window for the drawn unload")
	_t.expect(absf(window.x - default_window.x) > 0.1
		or absf(window.y - default_window.y) > 0.1,
		"the drawn unload moves the window the macro stage reads")
	for fraction: float in [0.0, 0.5, 1.0]:
		var start := _state(75.0)
		var elevation := lerpf(window.x, window.y, fraction)
		var assignment := _height_assignment_of(start, HEIGHT_LENGTH_M, elevation)
		assignment.unload_g = drawn
		assignment.corridor = {"centerline_m": PackedVector3Array(),
			"length_band_m": assignment.corridor.length_band_m}
		var built := Elements.build(start, assignment, _settings())
		if not _expect_built(built,
				"%.1f m inside the drawn window builds" % elevation):
			continue
		_t.expect_close(built.observation.crest_normal_g, drawn,
			"the beat holds the unload it was drawn at %.1f m" % elevation, 0.01)


## Prominence is the design's own `y_apex - max(y_entry, y_exit)`, measured from the frame the beat
## was handed. The two readings only differ on a descending handover, where the beat gives up
## height before it climbs, and taking the later climb start as the entry is the looser of the two.
## The published value is the stricter one, and it is what the macro window is built from.
func _test_prominence_is_measured_from_the_frame_the_beat_was_handed() -> void:
	for pitch_deg: float in HEIGHT_ENTRY_PITCH_DEG:
		var start := _state(75.0, pitch_deg)
		var built := Elements.build(start, _height_assignment_from(start, 0.5), _settings())
		if not _expect_built(built, "the beat builds from %.0f deg" % pitch_deg):
			continue
		var route: Dictionary = built.trajectory
		_t.expect_close(built.observation.prominence_m,
			float(built.observation.apex_height_m) - maxf(float(route.position_m[0].y),
				float(route.position_m[-1].y)),
			"prominence is the apex above the higher endpoint from %.0f deg" % pitch_deg,
			0.000001)


## A handover the beat cannot crest back over is refused where the macro stage reads it, not at
## the build: pulling out of a 35 deg dive and still cresting costs more than the held normal
## limit inside a height beat's declared arc at return speeds, and from 20 deg the beat gives up
## more height to the pull-out than its arc can win back. The family publishes no window at all
## there, so no macro stage can assign one; an assignment made anyway is refused by name. The turn
## family absorbs those handovers.
func _test_a_descending_handover_the_beat_cannot_crest_over_is_refused_by_name() -> void:
	for pitch_deg: float in HEIGHT_REFUSED_PITCH_DEG:
		for speed: float in [70.0, 80.0]:
			var start := _state(speed, pitch_deg)
			var label := "%.0f deg at %.0f m/s" % [pitch_deg, speed]
			_t.expect(Elements.elevation_bound_m(HEIGHT_LENGTH_M, speed,
				deg_to_rad(pitch_deg)).x > Elements.elevation_bound_m(HEIGHT_LENGTH_M, speed,
				deg_to_rad(pitch_deg)).y,
				"the family publishes no crest window from %s" % label)
			var built := Elements.build(start,
				_height_assignment_of(start, HEIGHT_LENGTH_M, -8.0), _settings())
			_t.expect(not built.ok, "a height beat handed %s is refused" % label)
			_t.expect(not built.errors.is_empty(),
				"the refusal from %s names the contract it missed" % label)


## A crest that stands centimetres above its endpoints satisfies every curvature condition a beat
## has - crest unload is `v^2 kappa / g0 + cos(theta)`, which a hill of any height reaches - and is
## still not a height beat. The measured case is one the macro stage used to assign: -23.64 m over
## 358 m at 78.2 m/s builds a 9.5 cm hump at exactly the authored unload.
func _test_a_hump_the_counterpart_would_not_call_a_beat_is_refused() -> void:
	var start := _state(78.2)
	var built := Elements.build(start, _height_assignment_of(start, 358.0, -23.64),
		_settings())
	_t.expect(not built.ok, "a hump below the counterpart prominence is not a height beat")
	_t.expect(_t.contains(built.errors, "prominence_m"),
		"the refusal names the prominence it missed: %s" % str(built.errors))
	_t.expect_close(built.observation.crest_normal_g, -0.45,
		"the hump reaches the authored unload, which is why the crest g cannot refuse it", 0.01)
	_t.expect(float(built.observation.prominence_m) < Elements.PROMINENCE_FLOOR_M,
		"the hump stands below the counterpart floor")
	_t.expect(-23.64 < Elements.elevation_bound_m(358.0, 78.2, 0.0).x,
		"the macro stage's own window would never have assigned it")


## The seam evidence splits by order: position, tangent and the world curvature vector are
## compared directly from the integrated route; the third and fourth position derivatives come
## from each side's analytic curvature jets, because differencing float32 positions at this
## spacing measures rounding rather than geometry.
func _test_element_seams_meet_the_c4_contract() -> void:
	var turn := Elements.build(_state(75.0), _turn_assignment(0.40), _settings())
	if not _expect_built(turn, "seam turn builds"):
		return
	var height := Elements.build(turn.end_state,
		_height_assignment_from(turn.end_state, 0.35), _settings())
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
	# The coarse sanity value decides nothing, but it has to read the seam rather than a step
	# spacing that changed under it. A spatial span truncates its last step onto its declared
	# length, so a difference taken across that boundary reads 1.339 m^-2 on this very seam -
	# six orders above the float32 quantisation of a third difference at this spacing, and above
	# any disagreement it could ever be asked to flag. Differenced on the arriving element's own
	# full steps it reads 1.0e-4, against analytic jets that are exactly zero either side.
	_t.expect_max(seam.finite_difference_x3_m2, 0.001,
		"the coarse finite difference reads the seam, not a step-spacing change")


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


## The macro chain's own trace of one turn, integrated the way `RideReturnLayout._chain` does:
## Simpson over the shared pitch and heading profiles, with the chain's heading measured from the
## start's own horizontal direction.
func _chain_end(start: Dictionary, heading_change_rad: float, length_m: float) -> Vector3:
	var tangent: Vector3 = (start.tangent as Vector3).normalized()
	var forward := (tangent - Vector3.UP * tangent.dot(Vector3.UP)).normalized()
	var context := {"forward": forward, "right": forward.cross(Vector3.UP)}
	var pitch := _entry_pitch(start)
	var position: Vector3 = start.position_m
	var samples := 24
	var step := length_m / samples
	for index in samples:
		var u0 := float(index) / samples
		var u1 := float(index + 1) / samples
		position += step / 6.0 * (
			Layout._tangent(context, 0.0, heading_change_rad, pitch, 0.0, u0)
			+ 4.0 * Layout._tangent(context, 0.0, heading_change_rad, pitch, 0.0,
				0.5 * (u0 + u1))
			+ Layout._tangent(context, 0.0, heading_change_rad, pitch, 0.0, u1))
	return position


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


func _height_assignment(fraction: float) -> Dictionary:
	return _height_assignment_from(_state(75.0), fraction)


## A macro assignment for one height beat, published the way the layout publishes one: the net
## elevation is read off the family's own crest window - `fraction` places it inside that window,
## and an assignment outside it is one the macro stage may not make - and the corridor is the
## macro chain's own trace of it.
func _height_assignment_from(start: Dictionary, fraction: float) -> Dictionary:
	return _height_assignment_at(start, HEIGHT_LENGTH_M, fraction)


func _height_assignment_at(start: Dictionary, length_m: float, fraction: float) -> Dictionary:
	var window := Elements.elevation_bound_m(length_m, float(start.speed_mps),
		_entry_pitch(start))
	return _height_assignment_of(start, length_m, lerpf(window.x, window.y, fraction))


func _height_assignment_of(start: Dictionary, length_m: float,
		elevation_m: float) -> Dictionary:
	return {
		"role_id": "return-height-a", "family": "return_height",
		"entry_frame": _frame(start.position_m, start.tangent, start.rider_up),
		"target_length_m": length_m, "terrain_intent": {}, "curvature_sign": 0.0,
		"heading_change_rad": 0.0, "elevation_change_m": elevation_m, "unload_g": -0.45,
		"corridor": {"centerline_m": _macro_centerline(start, length_m, elevation_m),
			"length_band_m": Vector2(length_m - 40.0, length_m + 40.0)},
	}


## The macro chain's own trace of that assignment: one vertical plane, the shared level-out plus
## the chain's symmetric elevation bump, integrated the way `RideReturnLayout` integrates it.
func _macro_centerline(start: Dictionary, length_m: float,
		elevation_m: float) -> PackedVector3Array:
	var pitch := _entry_pitch(start)
	var bump := 2.0 * elevation_m / length_m - sin(pitch)
	var tangent: Vector3 = (start.tangent as Vector3).normalized()
	var forward := (tangent - Vector3.UP * tangent.dot(Vector3.UP)).normalized()
	var position: Vector3 = start.position_m
	var line := PackedVector3Array([position])
	var samples := 24
	for index in samples:
		var sin_pitch := Layout._sin_pitch(pitch, bump, (float(index) + 0.5) / samples)
		position += (length_m / samples) * (forward
			* sqrt(maxf(1.0 - sin_pitch * sin_pitch, 0.0)) + Vector3.UP * sin_pitch)
		line.append(position)
	return line


## The design's own prominence, read off a polyline: the apex above the higher of its endpoints.
func _prominence(line: PackedVector3Array) -> float:
	var apex := -INF
	for point: Vector3 in line:
		apex = maxf(apex, point.y)
	return apex - maxf(line[0].y, line[-1].y)


func _entry_pitch(start: Dictionary) -> float:
	return asin(clampf((start.tangent as Vector3).normalized().y, -1.0, 1.0))


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
