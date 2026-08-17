from pathlib import Path

path = Path("godot/ride_program.gd")
text = path.read_text()

start = text.find("static func _add_camelback(")
end = text.find("\n\nstatic func _add_opener(", start)
if start < 0 or end < 0:
    raise SystemExit("camelback function boundaries were not found")

replacement = '''static func _add_camelback(
	spans: Array, metadata: Array, propulsion: PackedInt32Array, _hand: float
) -> void:
	# Default marquee camelback: one vertical-plane force narrative. The previous recipe mixed
	# four lateral pulses with alternating +/-18 degree rolls, turning the hill 48 degrees in plan
	# and handing the return an 11 degree residual bank. A three-dimensional hill, if added later,
	# is a separate named family; the default record camelback is not allowed to acquire heading
	# or bank as an accidental consequence of closure.
	var positive_g := 4.60068864065765
	var negative_g := -1.55352865073772
	var pullout_g := 5.2662035249371
	var pullup_s := 1.87949032 * 1.33555111055541
	var unload_s := 3.01169597 * 1.15 - 0.4
	var crest_s := 3.62587650 * 1.06
	# The fall remains the prominence authority. Removing bank restores the full normal-load
	# component to the vertical plane; production geometry/prominence gates decide whether these
	# inherited timings remain valid rather than a hidden lateral or roll correction doing so.
	var fall_s := 3.40
	_add(spans, metadata, propulsion, "camelback/pull-up",
		pullup_s, "moving", Motion.quintic(1.0, positive_g), 0.0, 0.0, 0.0, "rise")
	_add(spans, metadata, propulsion, "camelback/rise-hold", 0.4, "moving",
		positive_g, 0.0, 0.0, 0.0, "rise")
	_add(spans, metadata, propulsion, "camelback/unload",
		unload_s, "moving", Motion.quintic(positive_g, negative_g),
		0.0, 0.0, 0.0, "rise")
	_add(spans, metadata, propulsion, "camelback/crest", crest_s, "moving",
		negative_g, 0.0, 0.0, 0.0, "crest")
	_add(spans, metadata, propulsion, "camelback/fall", fall_s, "moving",
		Motion.quintic(negative_g, pullout_g), 0.0, 0.0, 0.0, "fall")
	# One continuous release replaces the one-integration-step 0.01 s pseudo-hold.
	_add(spans, metadata, propulsion, "camelback/pullout-release", 1.58, "moving",
		Motion.quintic(pullout_g, 1.0), 0.0, 0.0, 0.0, "exit")
'''
text = text[:start] + replacement + text[end:]

old = '''		records[role_id] = {
			"status": "unadopted",
			"reason": "no reviewed whole-element geometry intent has been adopted",
			"intent": {},
		}
	return records
'''
new = '''		records[role_id] = {
			"status": "unadopted",
			"reason": "no reviewed whole-element geometry intent has been adopted",
			"intent": {},
		}
		if role_id == "camelback":
			records[role_id] = {
				"status": "adopted",
				"reason": "the default marquee camelback is a near-vertical-plane hill",
				"intent": {
					"planarity": "vertical-plane",
					"max_plane_tilt_deg": 3.0,
					"max_out_of_plane_ratio": 0.02,
					"max_heading_drift_deg": 5.0,
					"entry": {
						"pitch_deg": -2.0,
						"pitch_tolerance_deg": 1.0,
						"bank_deg": 0.0,
						"bank_tolerance_deg": 3.0,
					},
					"exit": {
						"pitch_deg": 0.0,
						"pitch_tolerance_deg": 2.0,
						"bank_deg": 0.0,
						"bank_tolerance_deg": 3.0,
					},
				},
			}
	return records
'''
if text.count(old) != 1:
    raise SystemExit(f"material-element intent insertion point expected once, found {text.count(old)}")
text = text.replace(old, new)
path.write_text(text)
