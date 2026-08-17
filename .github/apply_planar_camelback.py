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
	#
	# These seven values are the accepted production point of an element-local bounded solve,
	# measured on seed 42 at both 0.05 s and 0.01 s integration. The solve targeted interior
	# geometry bands rather than the station: exit height [-0.5, 0.5] m, exit/apex pitch
	# [-0.1, 0.1] deg, prominence 247-253 m inside the 245-255 m route contract, length <=1179 m
	# inside the 1180 m role ceiling, rise/fall arc imbalance <=5 m, and crest load within
	# -1.604..-1.504 g. Production measured 1178.994 m, 247.430 m prominence, -0.489 m exit
	# height, -0.096 deg exit pitch, -0.098 deg apex pitch and 3.666 m arc imbalance.
	var positive_g := 4.60068864065765
	var pullup_s := 2.39060811463344
	var unload_s := 2.53095186885577
	var crest_s := 3.84271115326828
	var negative_g := -1.52988589350247
	var fall_s := 3.30305878961966
	var pullout_g := 4.12750135859898
	var release_s := 2.71672804094249
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
	_add(spans, metadata, propulsion, "camelback/pullout-release", release_s, "moving",
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
						"pitch_tolerance_deg": 0.25,
						"bank_deg": 0.0,
						"bank_tolerance_deg": 3.0,
					},
					"exit": {
						"pitch_deg": 0.0,
						"pitch_tolerance_deg": 0.25,
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
