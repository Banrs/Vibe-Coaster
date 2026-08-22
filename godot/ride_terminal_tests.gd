extends SceneTree

## Contract tests for the neutral capture and one-dimensional spatial brake (design 2026-08-22,
## "Capture and brakes"): capture carries no steering controls, the brake's only solved scalar is
## the peak brake g inside its 32-evaluation cap, the moving boundary lands on 2.0 m/s, the built
## path never authors positive drive, and the station pose it reaches is exact by construction.

const Terminal := preload("res://ride_terminal.gd")
const RideProgram := preload("res://ride_program.gd")

const ENTRY_SPEEDS_MPS := [70.0, 75.0, 80.0]
const SWEEP_SPEED_COUNT := 21
const ROTATION_ANGLE_RAD := 0.6435011088 # atan2(3, 4): an arbitrary, non-axis-aligned yaw.

var _t := TestUtil.new()


func _initialize() -> void:
	_test_terminal_builds_across_entry_band()
	_test_terminal_holds_its_boundary_across_the_entry_band()
	_test_brake_solve_refuses_an_unconverged_bracket()
	_test_terminal_builds_on_rotated_station_frame()
	_test_terminal_rejects_entry_speed_below_band()
	_test_terminal_rejects_entry_speed_above_band()
	_test_terminal_rejects_malformed_corridor()
	_t.finish(self)


func _test_terminal_builds_across_entry_band() -> void:
	for speed in ENTRY_SPEEDS_MPS:
		var built: Dictionary = Terminal.build(_capture_start(speed), _layout(), _settings())
		_expect_valid_build(built, _layout(), "axis-aligned %.1f m/s" % speed)


## The boundary claim is a band claim: every entry speed the corridor declares must land on the
## moving boundary inside the solve tolerance without spending more than the declared evaluations.
func _test_terminal_holds_its_boundary_across_the_entry_band() -> void:
	for index in SWEEP_SPEED_COUNT:
		var speed: float = 70.0 + index * (10.0 / float(SWEEP_SPEED_COUNT - 1))
		var built: Dictionary = Terminal.build(_capture_start(speed), _layout(), _settings())
		if not _t.expect(built.get("ok", false), "terminal builds at %.2f m/s" % speed):
			continue
		var report: Dictionary = built.report
		_t.expect_max(absf(float(report.moving_boundary_speed_mps)
				- Terminal.MOVING_BOUNDARY_SPEED_MPS), Terminal.BRAKE_SPEED_TOLERANCE_MPS,
			"brake converges on the moving boundary at %.2f m/s" % speed)
		_t.expect_max(float(report.unique_evaluations), float(Terminal.MAX_BRAKE_EVALUATIONS),
			"brake stays inside its evaluation cap at %.2f m/s" % speed)


## A bracket the solve cannot satisfy - here a residual that steps straight across the root - must
## be refused. Spending the evaluation cap is not convergence, and an under-braked candidate must
## never be published with an arbitrary moving-boundary residual.
func _test_brake_solve_refuses_an_unconverged_bracket() -> void:
	var evaluation_count := [0]
	var evaluate := func(peak_g: float) -> Dictionary:
		evaluation_count[0] += 1
		return {"route": {"ok": true,
				"speed_mps": PackedFloat64Array([3.0 if peak_g < 1.8 else 1.0])},
			"spans": [], "shape_integral_m": 100.0}
	var solved: Dictionary = Terminal._solve_peak(evaluate, 0.0, evaluation_count)
	_t.expect(not solved.get("ok", true), "an unconverged brake solve is refused")
	_t.expect(solved.get("errors", PackedStringArray()).size() > 0,
		"an unconverged brake solve reports a structured error")
	_t.expect_max(float(evaluation_count[0]), float(Terminal.MAX_BRAKE_EVALUATIONS),
		"an unconverged brake solve stops at its evaluation cap")


func _test_terminal_builds_on_rotated_station_frame() -> void:
	for speed in ENTRY_SPEEDS_MPS:
		var rotated_layout := _rotated_layout(ROTATION_ANGLE_RAD)
		var built: Dictionary = Terminal.build(
			_rotated_capture_start(speed, ROTATION_ANGLE_RAD), rotated_layout, _settings())
		_expect_valid_build(built, rotated_layout, "rotated %.1f m/s" % speed)


func _test_terminal_rejects_entry_speed_below_band() -> void:
	var built: Dictionary = Terminal.build(_capture_start(65.0), _layout(), _settings())
	_expect_rejected(built, "terminal entry speed below its band")


func _test_terminal_rejects_entry_speed_above_band() -> void:
	var built: Dictionary = Terminal.build(_capture_start(85.0), _layout(), _settings())
	_expect_rejected(built, "terminal entry speed above its band")


func _test_terminal_rejects_malformed_corridor() -> void:
	var missing_field := _layout()
	missing_field.reserved_corridor.erase("brake_length_m")
	_expect_rejected(Terminal.build(_capture_start(75.0), missing_field, _settings()),
		"corridor missing brake_length_m")

	var inverted_band := _layout()
	inverted_band.reserved_corridor.entry_speed_mps = Vector2(80.0, 70.0)
	_expect_rejected(Terminal.build(_capture_start(75.0), inverted_band, _settings()),
		"corridor with an inverted entry speed band")

	var negative_length := _layout()
	negative_length.reserved_corridor.brake_length_m = -1.0
	_expect_rejected(Terminal.build(_capture_start(75.0), negative_length, _settings()),
		"corridor with a negative brake length")


func _expect_valid_build(built: Dictionary, layout: Dictionary, label: String) -> void:
	_t.expect(built.get("ok", false), "terminal builds: %s" % label)
	if not built.get("ok", false):
		return
	var report: Dictionary = built.report
	_t.expect(report.capture_steering_controls == 0,
		"capture has no visible steering solve: %s" % label)
	_t.expect_close(report.moving_boundary_speed_mps, Terminal.MOVING_BOUNDARY_SPEED_MPS,
		"spatial brake reaches the moving boundary speed: %s" % label,
		Terminal.BRAKE_SPEED_TOLERANCE_MPS)
	_t.expect(report.unique_evaluations <= 32,
		"one-dimensional brake stays inside its cap: %s" % label)
	_t.expect(report.brake_peak_g >= 0.0 and report.brake_peak_g <= 3.6,
		"brake peak stays inside its bound: %s" % label)
	var trajectory: Dictionary = built.trajectory
	for drive in trajectory.drive_g:
		_t.expect(float(drive) <= 0.0000001, "terminal never authors positive drive: %s" % label)
	_t.expect_vector(trajectory.position_m[-1], layout.station_position_m,
		"terminal reaches the exact station position: %s" % label, 0.001)
	_t.expect_vector(trajectory.tangent[-1], layout.station_tangent.normalized(),
		"terminal reaches the exact station tangent: %s" % label, 0.000001)
	_t.expect_vector(trajectory.rider_up[-1], layout.station_up.normalized(),
		"terminal reaches the exact station up: %s" % label, 0.000001)


func _expect_rejected(built: Dictionary, message: String) -> void:
	_t.expect(not built.get("ok", true), message)
	_t.expect(built.get("errors", PackedStringArray()).size() > 0,
		"%s reports a structured error" % message)


func _capture_start(speed_mps: float) -> Dictionary:
	return {"position_m": Vector3.ZERO, "tangent": Vector3.RIGHT,
		"rider_up": Vector3.UP, "speed_mps": speed_mps,
		"distance_m": 0.0, "time_s": 0.0}


func _rotated_capture_start(speed_mps: float, angle: float) -> Dictionary:
	return {"position_m": Vector3.ZERO, "tangent": Vector3.RIGHT.rotated(Vector3.UP, angle),
		"rider_up": Vector3.UP, "speed_mps": speed_mps, "distance_m": 0.0, "time_s": 0.0}


func _layout() -> Dictionary:
	return {"station_position_m": Vector3(230.0, 0.0, 0.0),
		"station_tangent": Vector3.RIGHT, "station_up": Vector3.UP,
		"reserved_corridor": {"minimum_length_m": 230.0,
			"capture_length_m": 80.0, "brake_length_m": 150.0,
			"entry_speed_mps": Vector2(70.0, 80.0)}}


func _rotated_layout(angle: float) -> Dictionary:
	return {"station_position_m": Vector3(230.0, 0.0, 0.0).rotated(Vector3.UP, angle),
		"station_tangent": Vector3.RIGHT.rotated(Vector3.UP, angle), "station_up": Vector3.UP,
		"reserved_corridor": {"minimum_length_m": 230.0,
			"capture_length_m": 80.0, "brake_length_m": 150.0,
			"entry_speed_mps": Vector2(70.0, 80.0)}}


func _settings() -> Dictionary:
	return RideProgram._settings(0.01)
