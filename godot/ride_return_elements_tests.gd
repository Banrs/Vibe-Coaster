extends SceneTree

## Contract tests for the two local return element families. Every assertion measures the
## integrated result: the preview is a target, so a claim about geometry is only accepted when
## the production integrator produced it.

const Elements := preload("res://ride_return_elements.gd")
const Motion := preload("res://motion.gd")

var _t := TestUtil.new()


func _initialize() -> void:
	_test_turn_preview_matches_integrated_geometry_at_70_and_80_mps()
	_test_turn_bank_and_curvature_sign_agree()
	_test_turn_lateral_lands_inside_the_counter_lateral_band()
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
		_t.expect_max(observation.counter_bank_rad, 0.000001,
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
		_t.expect_max(built.observation.peak_lateral_g, 0.000001,
			"a vertical-plane beat carries no lateral load at %.0f m/s" % speed)
		_t.expect_max(absf(built.observation.exit_bank_rad), 0.000001,
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
	_t.expect_max(seam.twist_rad, 0.000001, "seam twist agrees")
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


func _state(speed_mps: float) -> Dictionary:
	return {"position_m": Vector3.ZERO, "tangent": Vector3.RIGHT,
		"rider_up": Vector3.UP, "speed_mps": speed_mps,
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
func _turn_assignment(heading_change_rad: float) -> Dictionary:
	return _with_corridor({
		"role_id": "return-turn-a", "family": "return_turn",
		"entry_frame": _frame(Vector3.ZERO, Vector3.RIGHT, Vector3.UP),
		"target_length_m": 420.0, "terrain_intent": {},
		"curvature_sign": signf(heading_change_rad),
		"heading_change_rad": heading_change_rad, "elevation_change_m": 0.0,
	}, Vector2(380.0, 460.0))


func _height_assignment(elevation_change_m: float) -> Dictionary:
	return _height_assignment_from(_state(75.0), elevation_change_m)


func _height_assignment_from(start: Dictionary, elevation_change_m: float) -> Dictionary:
	return _with_corridor({
		"role_id": "return-height-a", "family": "return_height",
		"entry_frame": _frame(start.position_m, start.tangent, start.rider_up),
		"target_length_m": 380.0, "terrain_intent": {}, "curvature_sign": 0.0,
		"heading_change_rad": 0.0, "elevation_change_m": elevation_change_m,
		"unload_g": -0.45,
	}, Vector2(340.0, 420.0))


func _frame(position: Vector3, tangent: Vector3, rider_up: Vector3) -> Dictionary:
	return {"position_m": position, "tangent": tangent, "rider_up": rider_up}


## The corridor a layout publishes is the assignment's own target trace plus its length band.
func _with_corridor(assignment: Dictionary, length_band_m: Vector2) -> Dictionary:
	var traced := Elements.preview(assignment, 1.0)
	assignment.corridor = {"centerline_m": traced.get("centerline_m", PackedVector3Array()),
		"length_band_m": length_band_m}
	return assignment


func _expect_built(result: Dictionary, message: String) -> bool:
	if result.get("ok", false):
		return true
	_t.expect(false, "%s: %s" % [message, str(result.get("errors", []))])
	return false
