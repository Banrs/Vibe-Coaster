from pathlib import Path

path = Path("godot/camelback_shape_probe.gd")
text = path.read_text()

replacements = {
'''const TARGET_PROMINENCE_M := 250.0
const LENGTH_BAND_M := Vector2(900.0, 1180.0)
''':
'''const PROMINENCE_AIM_BAND_M := Vector2(247.0, 253.0)
const LENGTH_BAND_M := Vector2(900.0, 1180.0)
const EXIT_HEIGHT_AIM_M := Vector2(-0.5, 0.5)
const EXIT_PITCH_AIM_DEG := Vector2(-0.1, 0.1)
const APEX_PITCH_AIM_DEG := Vector2(-0.1, 0.1)
const ARC_IMBALANCE_AIM_M := Vector2(-5.0, 5.0)
const NEGATIVE_G_AIM := Vector2(-1.60352865073772, -1.50352865073772)
''',
'''const CONTROL_IDS := [
	"unload_s", "crest_s", "fall_s", "pullout_g", "release_s",
]
const LOWER := [1.0, 0.5, 2.0, 3.0, 0.30]
const UPPER := [4.5, 5.0, 7.0, 7.0, 4.00]
const INITIAL := [3.01169597 * 1.15 - 0.4, 3.62587650 * 1.06, 3.40,
	5.2662035249371, 1.58]
''':
'''const CONTROL_IDS := [
	"pullup_s", "unload_s", "crest_s", "negative_g", "fall_s", "pullout_g",
	"release_s",
]
const LOWER := [1.5, 1.0, 0.5, -1.62, 2.0, 3.0, 0.30]
const UPPER := [3.5, 4.5, 5.0, -1.32, 7.0, 7.0, 4.00]
const INITIAL := [1.87949032 * 1.33555111055541, 3.01169597 * 1.15 - 0.4,
	3.62587650 * 1.06, -1.55352865073772, 3.40, 5.2662035249371, 1.58]
''',
'var solved := BoundedSolver.solve(residual, LOWER, UPPER, INITIAL, 299)':
'var solved := BoundedSolver.solve(residual, LOWER, UPPER, INITIAL, 499)',
'''	var length_residual := minf(0.0, float(measured.length_m) - LENGTH_BAND_M.x) \
		+ maxf(0.0, float(measured.length_m) - LENGTH_BAND_M.y)
	var rise_arc := float(measured.apex_distance_m)
	var fall_arc := float(measured.length_m) - rise_arc
	measured["residuals"] = [
		float(measured.exit_height_delta_m) / 3.0,
		float(measured.exit_pitch_deg) / 0.25,
		(float(measured.prominence_m) - TARGET_PROMINENCE_M) / 2.0,
		length_residual / 25.0,
		(rise_arc - fall_arc) / 20.0,
	]
''':
'''	var length_residual := minf(0.0, float(measured.length_m) - LENGTH_BAND_M.x) \
		+ maxf(0.0, float(measured.length_m) - LENGTH_BAND_M.y)
	var rise_arc := float(measured.apex_distance_m)
	var fall_arc := float(measured.length_m) - rise_arc
	var arc_imbalance := rise_arc - fall_arc
	var exit_height_residual := minf(0.0,
		float(measured.exit_height_delta_m) - EXIT_HEIGHT_AIM_M.x) \
		+ maxf(0.0, float(measured.exit_height_delta_m) - EXIT_HEIGHT_AIM_M.y)
	var exit_pitch_residual := minf(0.0,
		float(measured.exit_pitch_deg) - EXIT_PITCH_AIM_DEG.x) \
		+ maxf(0.0, float(measured.exit_pitch_deg) - EXIT_PITCH_AIM_DEG.y)
	var prominence_residual := minf(0.0,
		float(measured.prominence_m) - PROMINENCE_AIM_BAND_M.x) \
		+ maxf(0.0, float(measured.prominence_m) - PROMINENCE_AIM_BAND_M.y)
	var symmetry_residual := minf(0.0, arc_imbalance - ARC_IMBALANCE_AIM_M.x) \
		+ maxf(0.0, arc_imbalance - ARC_IMBALANCE_AIM_M.y)
	var apex_pitch_residual := minf(0.0,
		float(measured.apex_pitch_deg) - APEX_PITCH_AIM_DEG.x) \
		+ maxf(0.0, float(measured.apex_pitch_deg) - APEX_PITCH_AIM_DEG.y)
	var negative_g_residual := minf(0.0, float(controls[3]) - NEGATIVE_G_AIM.x) \
		+ maxf(0.0, float(controls[3]) - NEGATIVE_G_AIM.y)
	measured["residuals"] = [
		exit_height_residual / 0.5,
		exit_pitch_residual / 0.1,
		prominence_residual / 1.0,
		length_residual / 1.0,
		symmetry_residual / 5.0,
		apex_pitch_residual / 0.1,
		negative_g_residual / 0.05,
	]
''',
'''	var positive_g := 4.60068864065765
	var negative_g := -1.55352865073772
	var pullup_s := 1.87949032 * 1.33555111055541
	var unload_s := float(controls[0])
	var crest_s := float(controls[1])
	var fall_s := float(controls[2])
	var pullout_g := float(controls[3])
	var release_s := float(controls[4])
''':
'''	var positive_g := 4.60068864065765
	var pullup_s := float(controls[0])
	var unload_s := float(controls[1])
	var crest_s := float(controls[2])
	var negative_g := float(controls[3])
	var fall_s := float(controls[4])
	var pullout_g := float(controls[5])
	var release_s := float(controls[6])
''',
}

for old, new in replacements.items():
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one probe patch match, found {count}: {old[:80]!r}")
    text = text.replace(old, new)

path.write_text(text)
