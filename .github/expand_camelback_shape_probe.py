from pathlib import Path

path = Path("godot/camelback_shape_probe.gd")
text = path.read_text()


def replace_once(source: str, old: str, new: str, label: str) -> str:
    count = source.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return source.replace(old, new)


text = replace_once(
    text,
    '''const TARGET_PROMINENCE_M := 250.0
const LENGTH_BAND_M := Vector2(900.0, 1180.0)
const CONTROL_IDS := [
	"unload_s", "crest_s", "fall_s", "pullout_g", "release_s",
]
const LOWER := [1.0, 0.5, 2.0, 3.0, 0.30]
const UPPER := [4.5, 5.0, 7.0, 7.0, 4.00]
const INITIAL := [3.01169597 * 1.15 - 0.4, 3.62587650 * 1.06, 3.40,
	5.2662035249371, 1.58]
''',
    '''const PROMINENCE_AIM_BAND_M := Vector2(247.0, 253.0)
const LENGTH_BAND_M := Vector2(900.0, 1180.0)
const EXIT_HEIGHT_AIM_M := Vector2(-0.5, 0.5)
const EXIT_PITCH_AIM_DEG := Vector2(-0.1, 0.1)
const APEX_PITCH_AIM_DEG := Vector2(-0.1, 0.1)
const ARC_IMBALANCE_AIM_M := Vector2(-5.0, 5.0)
const NEGATIVE_G_AIM := Vector2(-1.60352865073772, -1.50352865073772)
const CONTROL_IDS := [
	"pullup_s", "unload_s", "crest_s", "negative_g", "fall_s", "pullout_g",
	"release_s",
]
const LOWER := [1.5, 1.0, 0.5, -1.62, 2.0, 3.0, 0.30]
const UPPER := [3.5, 4.5, 5.0, -1.32, 7.0, 7.0, 4.00]
const INITIAL := [1.87949032 * 1.33555111055541, 3.01169597 * 1.15 - 0.4,
	3.62587650 * 1.06, -1.55352865073772, 3.40, 5.2662035249371, 1.58]
''',
    "probe constants",
)
text = replace_once(
    text,
    "var solved := BoundedSolver.solve(residual, LOWER, UPPER, INITIAL, 299)",
    "var solved := BoundedSolver.solve(residual, LOWER, UPPER, INITIAL, 499)",
    "probe evaluation budget",
)

evaluate_start = text.find("func _evaluate(")
evaluate_end = text.find("\n\nfunc _camelback_start(", evaluate_start)
if evaluate_start < 0 or evaluate_end < 0:
    raise SystemExit("probe _evaluate boundaries were not found")
evaluate = '''func _evaluate(
	entry: Dictionary, controls: Array, settings: Dictionary, cache: Dictionary
) -> Dictionary:
	var key := "%.6f:" % float(settings.step_s)
	for value in controls:
		key += "%.10f," % float(value)
	if cache.has(key):
		return cache[key]
	var route := Motion.integrate(entry, _planar_spans(controls), settings)
	if not route.get("ok", false):
		var failed := {"ok": false, "errors": route.get("errors", [])}
		cache[key] = failed
		return failed
	var measured := _measure(route, entry)
	var rise_arc := float(measured.apex_distance_m)
	var fall_arc := float(measured.length_m) - rise_arc
	var arc_imbalance := rise_arc - fall_arc
	var length_residual := (
		minf(0.0, float(measured.length_m) - LENGTH_BAND_M.x)
		+ maxf(0.0, float(measured.length_m) - LENGTH_BAND_M.y)
	)
	var exit_height_residual := (
		minf(0.0, float(measured.exit_height_delta_m) - EXIT_HEIGHT_AIM_M.x)
		+ maxf(0.0, float(measured.exit_height_delta_m) - EXIT_HEIGHT_AIM_M.y)
	)
	var exit_pitch_residual := (
		minf(0.0, float(measured.exit_pitch_deg) - EXIT_PITCH_AIM_DEG.x)
		+ maxf(0.0, float(measured.exit_pitch_deg) - EXIT_PITCH_AIM_DEG.y)
	)
	var prominence_residual := (
		minf(0.0, float(measured.prominence_m) - PROMINENCE_AIM_BAND_M.x)
		+ maxf(0.0, float(measured.prominence_m) - PROMINENCE_AIM_BAND_M.y)
	)
	var symmetry_residual := (
		minf(0.0, arc_imbalance - ARC_IMBALANCE_AIM_M.x)
		+ maxf(0.0, arc_imbalance - ARC_IMBALANCE_AIM_M.y)
	)
	var apex_pitch_residual := (
		minf(0.0, float(measured.apex_pitch_deg) - APEX_PITCH_AIM_DEG.x)
		+ maxf(0.0, float(measured.apex_pitch_deg) - APEX_PITCH_AIM_DEG.y)
	)
	var negative_g_residual := (
		minf(0.0, float(controls[3]) - NEGATIVE_G_AIM.x)
		+ maxf(0.0, float(controls[3]) - NEGATIVE_G_AIM.y)
	)
	measured["residuals"] = [
		exit_height_residual / 0.5,
		exit_pitch_residual / 0.1,
		prominence_residual,
		length_residual,
		symmetry_residual / 5.0,
		apex_pitch_residual / 0.1,
		negative_g_residual / 0.05,
	]
	measured["rise_arc_m"] = rise_arc
	measured["fall_arc_m"] = fall_arc
	measured["arc_imbalance_m"] = arc_imbalance
	measured["controls"] = controls.duplicate()
	cache[key] = measured
	return measured
'''
text = text[:evaluate_start] + evaluate + text[evaluate_end:]

spans_start = text.find("func _planar_spans(")
spans_end = text.find("\n\nfunc _measure(", spans_start)
if spans_start < 0 or spans_end < 0:
    raise SystemExit("probe _planar_spans boundaries were not found")
spans = '''func _planar_spans(controls: Array) -> Array:
	var positive_g := 4.60068864065765
	var pullup_s := float(controls[0])
	var unload_s := float(controls[1])
	var crest_s := float(controls[2])
	var negative_g := float(controls[3])
	var fall_s := float(controls[4])
	var pullout_g := float(controls[5])
	var release_s := float(controls[6])
	return [
		Motion.span("camelback/pull-up", pullup_s, "moving",
			Motion.quintic(1.0, positive_g), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
		Motion.span("camelback/rise-hold", 0.4, "moving",
			Motion.constant(positive_g), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
		Motion.span("camelback/unload", unload_s, "moving",
			Motion.quintic(positive_g, negative_g), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
		Motion.span("camelback/crest", crest_s, "moving",
			Motion.constant(negative_g), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
		Motion.span("camelback/fall", fall_s, "moving",
			Motion.quintic(negative_g, pullout_g), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
		Motion.span("camelback/pullout-release", release_s, "moving",
			Motion.quintic(pullout_g, 1.0), Motion.constant(0.0),
			Motion.constant(0.0), Motion.constant(0.0)),
	]
'''
text = text[:spans_start] + spans + text[spans_end:]

path.write_text(text)
