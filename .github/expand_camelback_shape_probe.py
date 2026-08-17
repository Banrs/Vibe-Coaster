from pathlib import Path

path = Path("godot/camelback_shape_probe.gd")
text = path.read_text()

replacements = {
'''const CONTROL_IDS := [
	"unload_s", "crest_s", "fall_s", "pullout_g", "release_s",
]
const LOWER := [1.0, 0.5, 2.0, 3.0, 0.30]
const UPPER := [4.5, 5.0, 7.0, 7.0, 4.00]
const INITIAL := [3.01169597 * 1.15 - 0.4, 3.62587650 * 1.06, 3.40,
	5.2662035249371, 1.58]
''':
'''const CONTROL_IDS := [
	"pullup_s", "unload_s", "crest_s", "fall_s", "pullout_g", "release_s",
]
const LOWER := [1.5, 1.0, 0.5, 2.0, 3.0, 0.30]
const UPPER := [3.5, 4.5, 5.0, 7.0, 7.0, 4.00]
const INITIAL := [1.87949032 * 1.33555111055541, 3.01169597 * 1.15 - 0.4,
	3.62587650 * 1.06, 3.40, 5.2662035249371, 1.58]
''',
'var solved := BoundedSolver.solve(residual, LOWER, UPPER, INITIAL, 299)':
'var solved := BoundedSolver.solve(residual, LOWER, UPPER, INITIAL, 399)',
'''		(rise_arc - fall_arc) / 20.0,
	]
''':
'''		(rise_arc - fall_arc) / 20.0,
		float(measured.apex_pitch_deg) / 0.25,
	]
''',
'''	var pullup_s := 1.87949032 * 1.33555111055541
	var unload_s := float(controls[0])
	var crest_s := float(controls[1])
	var fall_s := float(controls[2])
	var pullout_g := float(controls[3])
	var release_s := float(controls[4])
''':
'''	var pullup_s := float(controls[0])
	var unload_s := float(controls[1])
	var crest_s := float(controls[2])
	var fall_s := float(controls[3])
	var pullout_g := float(controls[4])
	var release_s := float(controls[5])
''',
}

for old, new in replacements.items():
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"expected one probe patch match, found {count}: {old[:80]!r}")
    text = text.replace(old, new)

path.write_text(text)
