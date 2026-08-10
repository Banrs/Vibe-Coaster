extends SceneTree

const Coaster := preload("res://main.gd")
const Elements := preload("res://elements.gd")
const Fidelity := preload("res://fidelity.gd")
const FidelityTests := preload("res://fidelity_tests.gd")
const Generator := preload("res://generator.gd")
const Terrain := preload("res://terrain.gd")
const Verify := preload("res://verify.gd")

const MINI_STATION := Vector3.ZERO
## Beats the pacing rule is about. Pullouts, pushovers, falls and correction turns are the grammar
## between them — a valley followed by a valley is how a ride is written, two hills in a row with
## nothing between them is not.
const THRILL_KINDS := [
	"twisted_drop", "hill", "wave_turn", "rim_turn", "overbank", "cutback", "immelmann", "loop",
]
## The plan's expectation bands are what the generator is aiming at; these are what the check will
## fail on. They sit a couple of metres outside the aim on each side, because an element solved off
## a live speed lands near its target, not on it.
const IMMELMANN_APEX_CHECK := Vector2(70.0, 98.0)
const LOOP_HEIGHT_CHECK := Vector2(50.0, 88.0)
## One circuit, and the band the generator aims at is 6.4–7.6 km. It lands here — measured across
## the fifteen-seed fleet after the corridor model was calibrated per ride: 7.6 to 10.2 km, the
## deep seeds inside 8.4–9.8. What is left over the aim is three things. The clifftop: the slow
## beat is a dozen seconds of dead-level track at crawl speed rather than a brake and a
## re-acceleration. The raceway arc: the run home is a heading reversal at eighty-five metres a
## second, and the bank it may hold is roll-rate limited rather than duration limited —
## bank·tan(bank) ≤ ROLL_BUDGET·0.16·Δ·v/g — so a 150° reversal is 800 m of track and splitting it
## in two makes it longer, not shorter. The cliff climb: it has to cross a three-hundred-metre
## escarpment at a grade a coasting train can carry, which is 800 m to 1.3 km depending on how far
## out act one leaves it. The 10 km outliers are the seeds whose bearing search cannot close the
## circuit any tighter inside the corridor band, and their surplus is flown as brake run — long,
## never short, because short is a cusp.
const LENGTH_CHECK := Vector2(7400.0, 10400.0)
## Shortest a beat may be before it reads as a kink rather than an element, and the g band each
## booster has to hold. Grammar — the pullouts, pushovers and falls that hand one beat to the next —
## is exempt from the first: a 20 m fall between a crest and its pullout is one element, not a stub.
## Arbitrary seeds, the way a rider presses N: no property beyond "the generator was handed this".
const SWEEP_SEEDS := [1, 3, 7, 99, 256, 555, 1234, 4096, 31337, 77777, 123456, 20250101]
const BEAT_FLOOR := 30.0
## Slowest the ride gets between its launches, and how long it stays there. The reference's clifftop
## slow section measures about twelve seconds dead level; ours is a crawl at a quarter of that speed
## because the dive pitches over straight off the end of it, and a pitch-over's radius is v²/0.85g.
const CREST_CRAWL_SPEED := 19.0
const CREST_CRAWL_HOLD := 10.0
const GRAMMAR_KINDS := ["pullout", "pushover", "fall"]
const TURN_KINDS := ["turn", "rim_turn", "overbank"]
## The three powered zones, read as the g each one HOLDS rather than as its mean. Zone one is the
## entry launch — a compressed-gas shot, the class Do-Dodonpa measures at 3.2–3.8 g — and zones two
## and three are LSM boosters, which is a 2 g machine. The LSM band is wide at the top because the
## launch corridor may run the cliff booster short to reach its crest.
const ENTRY_LAUNCH_G := Vector2(3.5, 4.5)
const LSM_BOOST_G := Vector2(1.6, 2.9)
const BOOST_HOLD := 0.4
## Act one, against the inversion reference scaled on the value with its hold kept. The Immelmann
## measures 4.34–4.43 g with ≥3 g held 2.5–2.7 s; the loop is a twin lobe whose apex dips but never
## unloads (3.84 → 2.52 → 3.74); the cutback is 4.20 g with ≥2 g held 1.76 s.
const IMMELMANN_HOLD_G := 3.7
const IMMELMANN_PEAK_G := 6.2
const LOOP_LOBE_G := 4.6
const LOOP_APEX_G := 2.6
const LOOP_PEAK_G := 6.8
const CUTBACK_PEAK_G := Vector2(4.6, 5.8)
const CUTBACK_HOLD_G := 2.7
## The opener's own signature, against the primary reference's twisted first drop: +1.64 → −1.35 g
## of lateral across the roll and −0.99 g of airtime over the crest, scaled ×1.567 and ×1.5.
const DROP_LATERAL_G := Vector2(1.9, 2.7)
const DROP_AIRTIME_G := -0.55
## Airtime hills: valleys 2.07–2.68 g held 1.3 s, crests −0.40…−0.73 g. Scaled, and the crest band
## is two-sided because a hill that never unloads is not an airtime hill.
const VALLEY_G := Vector2(2.6, 3.9)
const CREST_G := Vector2(-1.25, -0.5)
## The marquee pair. The camelback pulls 2.14–3.89 g with 3.32 s ≥2 g, floats ≤0.2 g for 6.8 s over
## its crest and pulls 2.16–3.44 g out; the cliff dive's pullout is 2.04–2.99 g with 1.58 s ≥2 g.
const CAMELBACK_PEAK_G := Vector2(4.7, 5.6)
## Held over a second and a half rather than the reference's 3.3: at ninety-four metres a second
## the pull-up that reaches 250 m of structure is two and a half seconds long end to end, so a
## 3.3 s hold is not a shape it has.
const CAMELBACK_HOLD_G := 4.0
const CAMELBACK_HOLD := 1.5
const CAMELBACK_EXIT_G := Vector2(3.7, 4.9)
const CAMELBACK_FLOAT_G := 0.25
const CAMELBACK_FLOAT_HOLD := 4.0
const DIVE_PULLOUT_G := Vector2(3.3, 4.7)
const DIVE_PULLOUT_HOLD_G := 3.0
## Flat grade is infrastructure, not track between beats. These are the pieces allowed to be it.
const FLAT_GRADES := [
	"Station", "LSM3 boost",
	"Holding brake", "Crest hold", "Final brakes",
]


func _initialize() -> void:
	var errors := PackedStringArray()
	errors.append_array(FidelityTests.run())
	errors.append_array(_terrain_errors())
	errors.append_array(_verify_errors())
	errors.append_array(_frame_core_errors())
	errors.append_array(_template_errors())
	errors.append_array(_rolled_template_errors())
	errors.append_array(_generator_errors())
	errors.append_array(_sweep_errors())
	## What the viewer itself does on boot: one seeded build, the viewer's validation, its meshes.
	var started := Time.get_ticks_msec()
	var route: Dictionary = Generator.build(42)
	var analysis: Dictionary = Verify.analyze(route, Elements.ROW_OFFSETS)
	errors.append_array(Coaster.validate_route(route, analysis))
	var rails: ArrayMesh = Coaster.build_rail_mesh(route)
	var terrain: ArrayMesh = Coaster.build_terrain_mesh(route)
	var elapsed := Time.get_ticks_msec() - started
	if rails.get_surface_count() != 1 or rails.surface_get_array_len(0) < 30_000:
		errors.append("rail mesh is empty or incomplete")
	if terrain.get_surface_count() != 1:
		errors.append("terrain mesh is empty")
	if floori(route.length / Coaster.TIE_SPACING) < 1000:
		errors.append("track has too few visual speed cues")
	## 20 s is the measured CI-ubuntu cost of a 9.5 km seed, not an aspiration — loading time
	## is an open issue (docs/ISSUES.md); this gate only catches regressions beyond it.
	if elapsed > 20_000:
		errors.append("the viewer build, validation and meshes took %d ms" % elapsed)
	print(
		"seed 42 viewer route: %.1f m, %.1f s, %d samples, %.1f km/h top, %d ms"
		% [route.length, route.duration, route.positions.size(), analysis.top_speed * 3.6, elapsed]
	)
	for error in errors:
		printerr(error)
	quit(0 if errors.is_empty() else 1)


## The seeded generator: one seed is one ride, the same ride every time, and every seed's ride
## passes the same parametric checks the old route does. The route-level bands are the M6a
## envelope — deliberately loose, and measured rather than wished for.
func _generator_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for seed_value in [11, 42, 20260809]:
		var started := Time.get_ticks_msec()
		var route: Dictionary = Generator.build(seed_value)
		var elapsed := Time.get_ticks_msec() - started
		var repeat: Dictionary = Generator.build(seed_value)
		var issues := PackedStringArray()
		for field in ["positions", "speeds", "times"]:
			if route[field] != repeat[field]:
				issues.append("%s are not deterministic" % field)
		Verify.validate_structure(route, issues)
		Verify.validate_seams(route, issues)
		Verify.validate_clearance(route, route.terrain, route.tunnel_sections, issues)
		Verify.validate_self_clearance(route, issues)
		var analysis: Dictionary = Verify.analyze(route, Elements.ROW_OFFSETS)
		Verify.validate_loads(analysis, issues)
		## Measured, not wished for. Act one is sized off the ladder now rather than off the drop it
		## would like to have, and the post-tunnel dogleg stopped the second act from flying the same
		## corridor out and back — between them that is where the two kilometres went.
		_expect(issues, route.length >= LENGTH_CHECK.x and route.length <= LENGTH_CHECK.y, "route is %.0f m long, outside the %s check on an aim of %s" % [route.length, str(LENGTH_CHECK), str(route.plan.expectations.route_length)])
		_expect(issues, analysis.top_speed * 3.6 >= 330.0 and analysis.top_speed * 3.6 <= 348.0, "top speed is %.1f km/h" % (analysis.top_speed * 3.6))
		_expect(issues, analysis.elevation_span >= 300.0 and analysis.elevation_span <= 400.0, "elevation span is %.0f m" % analysis.elevation_span)
		_expect_elements(route, issues)
		var lsm_runs := PackedInt32Array()
		var last_lsm := 0
		for lsm in route.lsm_ids:
			if lsm != last_lsm and lsm != 0:
				lsm_runs.append(lsm)
			last_lsm = lsm
		_expect(issues, lsm_runs == PackedInt32Array([1, 2, 3]), "LSM zones read %s, not three contiguous zones in order" % str(lsm_runs))
		var closure: Dictionary = route.sections[-1]
		_expect(issues, closure.kind == "CLOSURE", "last section is '%s', not the station closure" % closure.name)
		_expect(issues, closure.length <= route.length * 0.08, "closure is %.0f m of %.0f" % [closure.length, route.length])
		for issue in issues:
			errors.append("seed %d: %s" % [seed_value, issue])
		_expect_shape(route, issues)
		_expect_bands(route, issues)
		for issue in issues:
			errors.append("seed %d: %s" % [seed_value, issue])
		var fast := _time_share(route, 200.0)
		var quick := _time_share(route, 100.0)
		print(
			"seed %d: %.0f m, %.1f s, %.1f km/h avg, %.1f km/h top, %.0f%% of the ride over 200, %.0f%% over 100, %d ms"
			% [seed_value, route.length, route.duration, 3.6 * route.length / route.duration, analysis.top_speed * 3.6, 100.0 * fast, 100.0 * quick, elapsed]
		)
		print(
			"  %s | %s | %s"
			% [route.plan.act_note + ": " + ", ".join(route.plan.inversion_notes), route.plan.get("cutback_note", "no cutback"), route.plan.get("wave_note", "no wave")]
		)
		print(
			"  %s | %s | %s"
			% [route.plan.get("lsm2_note", "-"), route.plan.get("lsm3_note", "-"), route.plan.get("act_sweep_note", "-")]
		)
		print(
			"  %s | %s | %s"
			% [route.plan.get("bearing_note", "-"), route.plan.get("corridor_note", "-"), route.plan.get("return_note", "-")]
		)
		print(
			"  %s | %s"
			% [route.plan.get("marquee_note", "%s flown" % route.plan.return_marquee), route.plan.get("brake_note", "-")]
		)
		if seed_value == 42:
			_print_phases(route)
			_print_bands(route)
	return errors


## Every seed has to build AND place. The viewer's seed key hands the generator arbitrary numbers,
## so the three seeds above being green says nothing about the twelfth one a rider presses N onto —
## and the failure modes that hide here are not soft ones: a run home that comes home past the
## platform used to hand the closure a bezier that folds, and a launch corridor undershoot used to
## put the cliff climb through the face.
##
## Structure — finite frames, monotone distance and time, a speed that never falls through the
## floor — and placement — seam continuity, terrain clearance, self-clearance — are both gates now:
## every seed a rider can reach must be safe. Loads stay ungated here for CI time; the three deep
## seeds above gate them properly.
func _sweep_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var lengths := PackedFloat32Array()
	for seed_value in SWEEP_SEEDS:
		var route: Dictionary = Generator.build(seed_value)
		lengths.append(route.length)
		var issues := PackedStringArray()
		Verify.validate_structure(route, issues)
		Verify.validate_seams(route, issues)
		Verify.validate_clearance(route, route.terrain, route.tunnel_sections, issues)
		Verify.validate_self_clearance(route, issues)
		for issue in issues:
			errors.append("sweep seed %d: %s" % [seed_value, issue])
	lengths.sort()
	var failed := {}
	for error in errors:
		failed[error.get_slice(":", 0)] = true
	var clean: int = SWEEP_SEEDS.size() - failed.size()
	print(
		"seed sweep: %d of %d build and place clean, lengths %.1f-%.1f km (median %.1f)"
		% [
			clean, SWEEP_SEEDS.size(), lengths[0] / 1000.0, lengths[-1] / 1000.0,
			lengths[lengths.size() / 2] / 1000.0,
		]
	)
	return errors


## The reviewer's view of the ride: one line per gesture. Nothing else in this file reads phases —
## they are the generator's own account of the story it just told.
func _print_phases(route: Dictionary) -> void:
	var order := []
	var totals := {}
	for section in route.sections:
		var phase: String = section.get("phase", "?")
		if not totals.has(phase):
			totals[phase] = Vector2.ZERO
			order.append(phase)
		totals[phase] += Vector2(section.length, section.end_time - section.start_time)
	print("  seed 42 phase profile:")
	for phase in order:
		var totals_for: Vector2 = totals[phase]
		print(
			"    %-20s %6.0f m %6.1f s %6.0f km/h"
			% [phase, totals_for.x, totals_for.y, 3.6 * totals_for.x / maxf(totals_for.y, 0.01)]
		)


## Fraction of the ride's time spent at or above this speed, in km/h.
func _time_share(route: Dictionary, kmh: float) -> float:
	var held := 0.0
	for i in range(1, route.speeds.size()):
		if route.speeds[i] * 3.6 >= kmh:
			held += route.times[i] - route.times[i - 1]
	return held / maxf(route.duration, 0.01)


## The flow rules. A beat is a run of FVD sections sharing one element dictionary, so a group counts
## once; the ban is on standalone stubs, on two turns stitched together, and on flat grade used as
## track between beats rather than as the infrastructure it is.
func _expect_shape(route: Dictionary, issues: PackedStringArray) -> void:
	var beats := []
	for index in route.sections.size():
		var section: Dictionary = route.sections[index]
		if section.kind != "FVD" or not section.has("element"):
			continue
		var kind: String = section.element.get("kind", "")
		if not beats.is_empty() and is_same(beats[-1].element, section.element):
			beats[-1].length += section.length
			continue
		beats.append({
			"kind": kind, "length": section.length, "index": index, "element": section.element,
		})
	for i in beats.size():
		var beat: Dictionary = beats[i]
		if not GRAMMAR_KINDS.has(beat.kind):
			_expect(issues, beat.length >= BEAT_FLOOR, "the %s beat is only %.0f m long" % [beat.kind, beat.length])
		if i > 0 and TURN_KINDS.has(beat.kind) and TURN_KINDS.has(beats[i - 1].kind) and beats[i - 1].index == beat.index - 1:
			_expect(issues, false, "a %s runs straight into a %s" % [beats[i - 1].kind, beat.kind])
	for index in range(1, route.sections.size() - 1):
		var section: Dictionary = route.sections[index]
		if section.kind != "GRADE" or not _is_flat(section):
			continue
		if route.sections[index - 1].kind == "FVD" and route.sections[index + 1].kind == "FVD":
			_expect(issues, FLAT_GRADES.has(section.name), "flat grade '%s' sits between two beats" % section.name)
	## Three powered zones, each short. What each one holds is a held-value band rather than a mean —
	## a launch is its plateau, and its mean is whatever its onset-limited ramps leave of it.
	var boosts := []
	for section in route.sections:
		if section.lsm != 0:
			boosts.append(section)
	_expect(issues, boosts.size() == 3, "the ride has %d powered sections, not three boosters" % boosts.size())
	for boost in boosts:
		_expect(issues, boost.length <= 200.0, "'%s' is %.0f m long" % [boost.name, boost.length])


## ---------------------------------------------------------------------------- held-value bands
##
## The fidelity check. A measured counterpart is a value held for a duration, not a spike, so every
## band here is read off the filtered series the load toolkit itself uses and asked for a value the
## beat SUSTAINS: `held(t)` is the largest g the window holds continuously for t seconds, which an
## outlier sample cannot satisfy. Targets are the measured reference scaled per axis by the envelope
## stretch on the VALUE with the measured HOLD kept — Gz+ ×1.333, Gz− ×1.5, Gy ×1.567.


## `element_bands` supplies each beat's filtered 100 Hz series; `held` returns −INF when the beat
## is shorter than the requested duration, which fails any band that asks for one.
## Every band here is the measured counterpart scaled per axis on the VALUE with the measured HOLD
## kept, and every one of them asks for a value the beat SUSTAINS. That is the point: a spike cannot
## satisfy `held`, so an element cannot pass by touching its band for one sample on its way past.
func _expect_bands(route: Dictionary, issues: PackedStringArray) -> void:
	var valley := 0.0
	var seen := {}
	for band in Fidelity.element_bands(route):
		var peak: float = Fidelity.held(band.normal, 1.0, 0.0)
		seen[band.kind] = true
		match band.kind:
			"Entry launch":
				var held: float = Fidelity.held(band.longitudinal, 1.0, BOOST_HOLD)
				_expect(issues, held >= ENTRY_LAUNCH_G.x and held <= ENTRY_LAUNCH_G.y, "the entry launch holds %.2f g for %.1f s, outside %s" % [held, BOOST_HOLD, str(ENTRY_LAUNCH_G)])
			"LSM2 boost", "LSM3 boost":
				var held: float = Fidelity.held(band.longitudinal, 1.0, BOOST_HOLD)
				_expect(issues, held >= LSM_BOOST_G.x and held <= LSM_BOOST_G.y, "'%s' holds %.2f g for %.1f s, outside %s" % [band.kind, held, BOOST_HOLD, str(LSM_BOOST_G)])
			"twisted_drop":
				var lateral: float = maxf(Fidelity.held(band.lateral, 1.0, 0.0), -Fidelity.held(band.lateral, -1.0, 0.0))
				var airtime: float = Fidelity.held(band.normal, -1.0, 0.8)
				_expect(issues, lateral >= DROP_LATERAL_G.x and lateral <= DROP_LATERAL_G.y, "the twisted drop snaps to %.2f g of lateral, outside %s" % [lateral, str(DROP_LATERAL_G)])
				_expect(issues, airtime <= DROP_AIRTIME_G, "the twisted drop only unloads to %.2f g for 0.8 s" % airtime)
			"immelmann":
				var held: float = Fidelity.held(band.normal, 1.0, 2.2)
				_expect(issues, held >= IMMELMANN_HOLD_G, "the immelmann only holds %.2f g for 2.2 s" % held)
				_expect(issues, peak <= IMMELMANN_PEAK_G, "the immelmann peaks at %.2f g" % peak)
			"loop":
				var lobe: float = Fidelity.held(band.normal, 1.0, 0.8)
				var apex: float = Fidelity.held(band.normal, 1.0, 3.0)
				_expect(issues, lobe >= LOOP_LOBE_G and peak <= LOOP_PEAK_G, "the loop's entry lobe holds %.2f g and peaks at %.2f" % [lobe, peak])
				_expect(issues, apex >= LOOP_APEX_G, "the loop's apex falls to %.2f g — the dip has to stay loaded" % apex)
			"cutback":
				var held: float = Fidelity.held(band.normal, 1.0, 1.5)
				_expect(issues, peak >= CUTBACK_PEAK_G.x and peak <= CUTBACK_PEAK_G.y, "the cutback peaks at %.2f g, outside %s" % [peak, str(CUTBACK_PEAK_G)])
				_expect(issues, held >= CUTBACK_HOLD_G, "the cutback only holds %.2f g for 1.5 s" % held)
			"hill":
				var crest: float = Fidelity.held(band.normal, -1.0, 0.8)
				if band.element.has("structure_rise"):
					var float_ceiling: float = Fidelity.held(band.normal, -1.0, CAMELBACK_FLOAT_HOLD)
					_expect(issues, float_ceiling <= CAMELBACK_FLOAT_G, "the camelback crest never floats: its quietest %.0f s still reaches %.2f g" % [CAMELBACK_FLOAT_HOLD, float_ceiling])
				else:
					_expect(issues, crest <= CREST_G.y and crest >= CREST_G.x, "an airtime crest holds %.2f g for 0.8 s, outside %s" % [crest, str(CREST_G)])
			"pullout":
				if band.element.has("camelback"):
					if band.element.exit_pitch_deg > 1.0:
						_expect(issues, peak >= CAMELBACK_PEAK_G.x and peak <= CAMELBACK_PEAK_G.y, "the camelback pull-up peaks at %.2f g, outside %s" % [peak, str(CAMELBACK_PEAK_G)])
						_expect(issues, Fidelity.held(band.normal, 1.0, CAMELBACK_HOLD) >= CAMELBACK_HOLD_G, "the camelback pull-up only holds %.2f g for %.1f s" % [Fidelity.held(band.normal, 1.0, CAMELBACK_HOLD), CAMELBACK_HOLD])
					else:
						_expect(issues, peak >= CAMELBACK_EXIT_G.x and peak <= CAMELBACK_EXIT_G.y, "the camelback exit pullout peaks at %.2f g, outside %s" % [peak, str(CAMELBACK_EXIT_G)])
				elif band.element.has("cliff_dive"):
					_expect(issues, peak >= DIVE_PULLOUT_G.x and peak <= DIVE_PULLOUT_G.y, "the cliff-dive pullout peaks at %.2f g, outside %s" % [peak, str(DIVE_PULLOUT_G)])
					_expect(issues, Fidelity.held(band.normal, 1.0, 1.5) >= DIVE_PULLOUT_HOLD_G, "the cliff-dive pullout only holds %.2f g for 1.5 s" % Fidelity.held(band.normal, 1.0, 1.5))
				elif band.phase == "act one":
					valley = maxf(valley, Fidelity.held(band.normal, 1.0, 1.0))
	_expect(issues, seen.has("immelmann") or seen.has("loop"), "no inversion carries a load band")
	_expect(issues, valley >= VALLEY_G.x and valley <= VALLEY_G.y, "act one's strongest valley holds %.2f g for 1 s, outside %s" % [valley, str(VALLEY_G)])


func _print_bands(route: Dictionary) -> void:
	print("  seed 42 held-value bands (peak | held 0.5 s | held 1.5 s | held 3.0 s):")
	for band in Fidelity.element_bands(route):
		print(
			"    %-16s %4.1f s  Gz %5.2f |%5.2f |%5.2f |%5.2f   Gz- %5.2f |%5.2f   Gy %5.2f |%5.2f   Gx %5.2f |%5.2f   onset %5.1f"
			% [
				band.kind, band.seconds,
				Fidelity.held(band.normal, 1.0, 0.0), Fidelity.held(band.normal, 1.0, 0.5),
				Fidelity.held(band.normal, 1.0, 1.5), Fidelity.held(band.normal, 1.0, 3.0),
				Fidelity.held(band.normal, -1.0, 0.0), Fidelity.held(band.normal, -1.0, 1.0),
				Fidelity.held(band.lateral, 1.0, 0.0), Fidelity.held(band.lateral, -1.0, 0.0),
				Fidelity.held(band.longitudinal, 1.0, 0.0), Fidelity.held(band.longitudinal, 1.0, 0.5),
				maxf(
					Verify.peak_onset(band.normal),
					maxf(Verify.peak_onset(band.lateral), Verify.peak_onset(band.longitudinal))
				),
			]
		)


func _is_flat(section: Dictionary) -> bool:
	for key in section.pitch:
		if absf(key.y) > 0.5:
			return false
	return true


## What the generator said it was building, checked against what it built. Every band here is read
## off the element metadata the templates report, so a failure names the beat and its measurement
## rather than a route-level symptom.
func _expect_elements(route: Dictionary, issues: PackedStringArray) -> void:
	var expectations: Dictionary = route.plan.expectations
	var found := {}
	var cutbacks := 0
	var steepest_dive := 0.0
	var twisted_up := 1.0
	## Composites carry one element dictionary across their sections, so a beat is a run of sections
	## sharing that dictionary; a GRADE or the closure ends any run. Adjacent beats of the same kind
	## are the pacing failure — the same thing twice with nothing between them.
	var previous_kind := ""
	var previous_element: Variant = null
	for section in route.sections:
		if section.kind != "FVD":
			previous_kind = ""
			previous_element = null
			continue
		var element: Dictionary = section.element
		var kind: String = element.get("kind", "")
		if kind == "":
			continue
		if not found.has(kind):
			found[kind] = element
		if element.has("cliff_dive"):
			for i in range(section.start_index, section.end_index + 1):
				steepest_dive = minf(steepest_dive, _pitch_deg(route.tangents[i]))
		if kind == "twisted_drop":
			for i in range(section.start_index, section.end_index + 1):
				twisted_up = minf(twisted_up, route.ups[i].y)
		if kind == "cutback" and not is_same(element, previous_element):
			cutbacks += 1
		if previous_element != null and not is_same(element, previous_element) and THRILL_KINDS.has(kind):
			_expect(issues, kind != previous_kind, "two %s beats run back to back" % kind)
		previous_kind = kind
		previous_element = element

	var camelback: Dictionary = _structure_element(route)
	_expect(issues, not camelback.is_empty(), "no camelback structure was built")
	if not camelback.is_empty():
		_expect(issues, camelback.structure_rise >= 235.0 and camelback.structure_rise <= 265.0, "camelback stands %.1f m above its valley, not %.0f" % [camelback.structure_rise, expectations.camelback_structure])
	_expect(issues, found.has("immelmann") or found.has("loop"), "the ride has no inversion")
	if found.has("immelmann"):
		var apex: float = found.immelmann.apex_height
		_expect(issues, apex >= IMMELMANN_APEX_CHECK.x and apex <= IMMELMANN_APEX_CHECK.y, "immelmann apexes %.1f m, outside the %s check on an aim of %s" % [apex, str(IMMELMANN_APEX_CHECK), str(expectations.immelmann_apex)])
	if found.has("loop"):
		var height: float = found.loop.height
		var separation: float = found.loop.leg_separation
		_expect(issues, height >= LOOP_HEIGHT_CHECK.x and height <= LOOP_HEIGHT_CHECK.y, "loop stands %.1f m, outside the %s check on an aim of %s" % [height, str(LOOP_HEIGHT_CHECK), str(expectations.loop_height)])
		_expect(issues, separation >= expectations.loop_leg_separation, "loop legs pass %.1f m apart, under %.1f" % [separation, expectations.loop_leg_separation])
		## The pair, flown in the fixed order the story names: the loop is second and stands at the
		## reference's own fraction of the Immelmann it answers. The check is a shade wider than
		## the aim because the loop is clamped inside its lobe window before it chases the pair.
		if found.has("immelmann"):
			var pair: float = height / maxf(found.immelmann.apex_height, 1.0)
			_expect(issues, pair >= 0.75 and pair <= 0.92, "loop stands %.2f of the immelmann, outside the pair on an aim of %s" % [pair, str(expectations.loop_pair)])
	## Every kind the ride actually flies is a kind the registry knows. The registry is the seam an
	## outside slot list attaches to, and a beat missing from it is a beat nothing can select.
	for kind in found:
		_expect(issues, Generator.REGISTRY.has(kind), "'%s' is flown but has no REGISTRY entry" % kind)
	_expect(issues, steepest_dive <= expectations.dive_steepest_pitch_deg, "cliff dive only reaches %.1f° of pitch" % steepest_dive)
	_expect(issues, twisted_up > 0.2, "twisted drop rolls over (lowest up.y %.3f)" % twisted_up)
	_expect(issues, cutbacks == 1 or route.plan.get("cutback_note", "").contains("skipped"), "the %s cutback slot neither flew nor recorded a skip" % expectations.cutback_slot)
	_expect(issues, cutbacks <= 1, "the ride has %d cutbacks" % cutbacks)
	_expect(issues, _held_seconds(route) >= CREST_CRAWL_HOLD, "the crest hold only crawls for %.2f s" % _held_seconds(route))


## The camelback is the one hill the generator measured as structure rather than as rise.
func _structure_element(route: Dictionary) -> Dictionary:
	for section in route.sections:
		if section.kind == "FVD" and section.element.has("structure_rise"):
			return section.element
	return {}


## The ride's one deliberate slow beat, measured rather than named: between the first powered zone
## and the last, find the slowest the ride ever gets and then the longest contiguous run it holds
## within a couple of metres a second of it. The station approach and the brake run are slow too and
## neither is the beat, which is why the window is the two launches.
func _held_seconds(route: Dictionary) -> float:
	var from := 0
	var to: int = route.speeds.size() - 1
	for i in route.lsm_ids.size():
		if route.lsm_ids[i] == 1:
			from = i
		elif route.lsm_ids[i] == 3:
			to = mini(to, i)
	var crawl := INF
	for i in range(from, to):
		crawl = minf(crawl, route.speeds[i])
	if crawl > CREST_CRAWL_SPEED:
		return 0.0
	var longest := 0.0
	var start := -1
	for i in range(from, to):
		if route.speeds[i] <= crawl + 2.0:
			if start < 0:
				start = i
			longest = maxf(longest, route.times[i] - route.times[start])
		else:
			start = -1
	return longest


func _terrain_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for seed_value in [1, 7, 20260809]:
		var first := _terrain_for_seed(seed_value)
		var repeat := _terrain_for_seed(seed_value)
		if first != repeat:
			errors.append("terrain params are not deterministic for seed %d" % seed_value)
			continue
		var relief_reached := 0.0
		for i in 400:
			var x := float((i * 631) % 4001) - 2000.0
			var z := float((i * 269) % 4001) - 2000.0
			var h: float = Terrain.height(first, x, z)
			var h_repeat: float = Terrain.height(repeat, x, z)
			if h != h_repeat or not is_finite(h):
				errors.append("terrain heights are not deterministic for seed %d" % seed_value)
				break
			relief_reached = maxf(relief_reached, h)
		if relief_reached < first.relief * 0.95:
			errors.append("seed %d terrain never reaches its plateau relief" % seed_value)
		if absf(Terrain.height(first, 0.0, 0.0) - Terrain.height(repeat, 0.0, 0.0)) > 0.0:
			errors.append("terrain origin height differs between identical seeds")
	return errors


func _verify_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if absf(Verify.limit_at(Verify.POSITIVE_LIMIT, 0.5) - 8.0) > 0.001:
		errors.append("+Gz brief limit is not 8.0")
	if absf(Verify.limit_at(Verify.POSITIVE_LIMIT, 3.0) - 5.333) > 0.001:
		errors.append("+Gz 2-4 s plateau is not 5.333")
	if absf(Verify.limit_at(Verify.POSITIVE_LIMIT, 8.0) - 4.0) > 0.001:
		errors.append("+Gz 5-11.8 s plateau is not 4.0")
	if absf(Verify.limit_at(Verify.POSITIVE_LIMIT, 100.0) - 1.333) > 0.001:
		errors.append("+Gz long-duration tail is not 1.333")
	if absf(Verify.limit_at(Verify.LONGITUDINAL_NEGATIVE_LIMIT, 0.4) - 6.0) > 0.001:
		errors.append("-Gx brief limit is not 6.0")
	var constant := PackedFloat32Array()
	constant.resize(400)
	constant.fill(2.0)
	var filtered_constant: PackedFloat32Array = Verify.filter(constant)
	if absf(filtered_constant[-1] - 2.0) > 0.001:
		errors.append("Butterworth DC gain is not unity")
	var pulse := PackedFloat32Array()
	pulse.resize(1000)
	pulse.fill(1.0)
	for i in range(300, 700):
		pulse[i] = 5.0
	var usage: Dictionary = Verify.envelope_usage(pulse, Verify.POSITIVE_LIMIT, 1.0)
	if absf(usage.usage - 5.0 / 5.333) > 0.02 or usage.duration < 2.0 or usage.duration > 4.0:
		errors.append("held-curve usage misreads a 4 s pulse (usage %.3f at %.2f s)" % [usage.usage, usage.duration])
	var push_pull := PackedFloat32Array()
	push_pull.resize(700)
	push_pull.fill(1.0)
	for i in 400:
		push_pull[i] = -1.0
	for i in range(400, 500):
		push_pull[i] = 7.0
	if Verify.push_pull_violations(push_pull) != 1:
		errors.append("push-pull misses a 7.0 g peak after 4 s of -Gz")
	for i in range(400, 500):
		push_pull[i] = 6.0
	if Verify.push_pull_violations(push_pull) != 0:
		errors.append("push-pull flags a compliant 6.0 g peak")
	var reversal := PackedFloat32Array()
	reversal.resize(300)
	for i in 50:
		reversal[i] = 4.5
	for i in range(60, 110):
		reversal[i] = -2.0
	if Verify.reversal_violations(reversal, 8.0, 3.0) != 1:
		errors.append("reversal rule misses a 0.1 s opposite-sign pair")
	var spaced := PackedFloat32Array()
	spaced.resize(300)
	for i in 50:
		spaced[i] = 4.5
	for i in range(100, 150):
		spaced[i] = -2.0
	if Verify.reversal_violations(spaced, 8.0, 3.0) != 0:
		errors.append("reversal rule flags a 0.5 s-separated pair")
	var normal_series := PackedFloat32Array([7.0])
	var lateral_series := PackedFloat32Array([3.5])
	var longitudinal_series := PackedFloat32Array([0.0])
	if Verify.combined_usage(normal_series, lateral_series, longitudinal_series) <= 1.0:
		errors.append("pairwise ellipse accepts Gz 7.0 with Gy 3.5")
	if Verify.combined_usage(PackedFloat32Array([6.0]), PackedFloat32Array([3.0]), PackedFloat32Array([0.0])) > 1.0:
		errors.append("pairwise ellipse rejects Gz 6.0 with Gy 3.0")
	var ramp := PackedFloat32Array()
	ramp.resize(120)
	for i in 120:
		ramp[i] = clampf(i * 0.25, 0.0, 5.0)
	if absf(Verify.peak_onset(ramp) - 25.0) > 0.5:
		errors.append("least-squares onset misreads a 25 g/s ramp (%.2f)" % Verify.peak_onset(ramp))
	return errors


## The rewrite's integrator core: a closed infrastructure route through elements.gd, plus the
## explicit-frame behaviours ride_model.gd could not express (inversion, authored roll).
func _frame_core_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var route: Dictionary = _mini_route()
	var repeat: Dictionary = _mini_route()
	var closure_error: float = route.positions[-1].distance_to(MINI_STATION)
	if closure_error > 0.001:
		errors.append("mini route misses the station by %.4f m" % closure_error)
	for field in ["positions", "speeds", "times"]:
		if route[field] != repeat[field]:
			errors.append("mini route %s are not deterministic" % field)
	var issues := PackedStringArray()
	Verify.validate_structure(route, issues)
	Verify.validate_seams(route, issues)
	Verify.validate_self_clearance(route, issues)
	for issue in issues:
		errors.append("mini route: %s" % issue)

	var straight: Dictionary = _fvd_probe(30.0, Elements.fvd_section(
		"straight", 150.0,
		[Vector2(0, 1), Vector2(1, 1)],
		[Vector2(0, 0), Vector2(1, 0)],
		[Vector2(0, 0), Vector2(1, 0)]
	))
	var exit_tangent: Vector3 = straight.tangents[-1]
	var heading := absf(rad_to_deg(Vector2(exit_tangent.x, exit_tangent.z).angle_to(Vector2.UP)))
	if absf(exit_tangent.y) > 0.02 or heading > 1.0:
		errors.append("1 g support on straight track drifts (pitch %.3f, heading %.2f°)" % [exit_tangent.y, heading])

	var loop: Dictionary = _fvd_probe(42.0, Elements.fvd_section(
		"loop", 260.0,
		[Vector2(0, 1), Vector2(0.15, 4.2), Vector2(0.85, 4.2), Vector2(1, 1)],
		[Vector2(0, 0), Vector2(1, 0)],
		[Vector2(0, 0), Vector2(1, 0)]
	))
	var lowest_up := INF
	for up in loop.ups:
		lowest_up = minf(lowest_up, up.y)
	if lowest_up > -0.5:
		errors.append("sustained 4.2 g never inverts the frame (lowest up.y %.3f)" % lowest_up)
	if _frame_error(loop) > 0.002:
		errors.append("inverting frames are not orthonormal (%.5f)" % _frame_error(loop))

	var rolled: Dictionary = _fvd_probe(45.0, Elements.fvd_section(
		"roll", 90.0,
		[Vector2(0, 1), Vector2(1, 1)],
		[Vector2(0, 0), Vector2(1, 0)],
		[Vector2(0, 0), Vector2(0.3, 60), Vector2(0.7, 60), Vector2(1, 0)]
	))
	if absf(rolled.banks[-1]) < 45.0:
		errors.append("authored roll only reaches %.1f°" % rolled.banks[-1])
	if _frame_error(rolled) > 0.002:
		errors.append("rolled frames are not orthonormal (%.5f)" % _frame_error(rolled))
	var back := {
		"position": rolled.positions[-1],
		"tangent": rolled.tangents[-1],
		"up": rolled.ups[-1],
		"speed": rolled.speeds[-1],
		"distance": rolled.distances[-1],
		"time": rolled.times[-1],
	}
	Elements.integrate_fvd(rolled, back, Elements.fvd_section(
		"unroll", 90.0,
		[Vector2(0, 1), Vector2(1, 1)],
		[Vector2(0, 0), Vector2(1, 0)],
		[Vector2(0, 0), Vector2(0.3, -60), Vector2(0.7, -60), Vector2(1, 0)]
	), 0)
	if absf(rolled.banks[-1]) > 5.0:
		errors.append("mirrored roll leaves %.1f° of bank" % rolled.banks[-1])
	return errors


func _mini_route() -> Dictionary:
	var sections: Array = [
		Elements.grade_section("Station", 45.0, [Vector2(0, 0), Vector2(1, 0)], 13.9),
		Elements.grade_section("Lift", 350.0, [Vector2(0, 0), Vector2(0.5, 22), Vector2(1, 0)], 13.9),
		Elements.grade_section("Descent", 350.0, [Vector2(0, 0), Vector2(0.5, -22), Vector2(1, 0)], 24.0),
		Elements.fvd_section(
			"Turnaround",
			150.0,
			[Vector2(0, 1), Vector2(1, 1)],
			[Vector2(0, 0), Vector2(0.2, 1.5), Vector2(0.8, 1.5), Vector2(1, 0)],
			[Vector2(0, 0), Vector2(1, 0)]
		),
		Elements.grade_section("Brake", 180.0, [Vector2(0, 0), Vector2(1, 0)], 6.0, 0, 4.0),
	]
	return Elements.build_route(sections, MINI_STATION, Vector3.FORWARD, 6.0)


func _fvd_probe(speed: float, section: Dictionary) -> Dictionary:
	var state := _template_state(speed, 0.0)
	var route := _seed_route(state)
	Elements.integrate_fvd(route, state, section, 0)
	return route


func _template_state(speed: float, height: float) -> Dictionary:
	return {
		"position": Vector3(0, height, 0),
		"tangent": Vector3.FORWARD,
		"up": Vector3.UP,
		"speed": speed,
		"distance": 0.0,
		"time": 0.0,
	}


func _seed_route(state: Dictionary) -> Dictionary:
	var route: Dictionary = Elements.new_route()
	Elements.append_state(route, state, 0, 1.0, 0.0, 0.0, 0, Vector3.ZERO)
	return route


func _run_group(route: Dictionary, state: Dictionary, sections: Array, all: Array) -> void:
	for section in sections:
		section["start_index"] = route.positions.size() - 1
		Elements.integrate_fvd(route, state, section, all.size())
		section["end_index"] = route.positions.size() - 1
		all.append(section)


func _pitch_deg(tangent: Vector3) -> float:
	return rad_to_deg(asin(clampf(tangent.y, -1.0, 1.0)))


## The element templates: each author_* resolves its own targets from whatever attitude and speed
## the state carries, and hands the next element a clean group boundary.
func _template_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	errors.append_array(_dive_errors())
	errors.append_array(_hill_errors(90.0, 62.0, 5.2, 235.0, -0.3, 4.0, 3.0, 0.12, "camelback"))
	errors.append_array(_hill_errors(38.0, 30.0, 3.5, 12.0, -1.2, 1.5, 90.0, 1.0, "ejector"))

	var turn_state := _template_state(70.0, 0.0)
	var turn_route := _seed_route(turn_state)
	_run_group(turn_route, turn_state, Elements.author_turn(turn_route, turn_state, {"heading_change_deg": 180.0, "bank_deg": 70.0}), [])
	var turn_mid: float = turn_route.banks[turn_route.banks.size() / 2]
	_expect(errors, absf(Elements._heading_change_deg(turn_route, 1) - 180.0) <= 3.0, "turn sweeps %.1f°, not 180" % Elements._heading_change_deg(turn_route, 1))
	_expect(errors, absf(turn_route.banks[-1]) <= 3.0, "turn exits banked %.1f°" % turn_route.banks[-1])
	_expect(errors, absf(turn_mid) >= 60.0, "turn only holds %.1f° of bank" % turn_mid)
	_expect(errors, _frame_error(turn_route) <= 0.002, "turn frames are not orthonormal (%.5f)" % _frame_error(turn_route))

	var rim_state := _template_state(16.0, 0.0)
	var rim_route := _seed_route(rim_state)
	_run_group(rim_route, rim_state, Elements.author_rim_turn(rim_route, rim_state, {"heading_change_deg": 120.0, "outward_bank_deg": 25.0, "lateral_g": -1.0}), [])
	var rim_mid: float = rim_route.banks[rim_route.banks.size() / 2]
	_expect(errors, absf(Elements._heading_change_deg(rim_route, 1) - 120.0) <= 3.0, "rim turn sweeps %.1f°, not 120" % Elements._heading_change_deg(rim_route, 1))
	_expect(errors, rim_mid * turn_mid < 0.0, "rim turn banks %.1f°, not away from the corner" % rim_mid)

	var over_state := _template_state(55.0, 0.0)
	var over_route := _seed_route(over_state)
	_run_group(over_route, over_state, Elements.author_overbank(over_route, over_state, {"heading_change_deg": 150.0, "bank_deg": 95.0, "peak_g": 2.6}), [])
	var peak_bank := 0.0
	for bank in over_route.banks:
		peak_bank = maxf(peak_bank, absf(bank))
	_expect(errors, absf(Elements._heading_change_deg(over_route, 1) - 150.0) <= 4.0, "overbank sweeps %.1f°, not 150" % Elements._heading_change_deg(over_route, 1))
	_expect(errors, peak_bank >= 88.0, "overbank only reaches %.1f° of bank" % peak_bank)
	_expect(errors, absf(over_route.banks[-1]) <= 3.0, "overbank exits banked %.1f°" % over_route.banks[-1])
	return errors


func _dive_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var state := _template_state(12.0, 250.0)
	var route := _seed_route(state)
	var sections: Array = []
	var dive: Array = Elements.author_dive(route, state, {"height": 240.0, "peak_g": 5.5})
	_run_group(route, state, dive, sections)
	var steepest := 0.0
	for tangent in route.tangents:
		steepest = maxf(steepest, absf(_pitch_deg(tangent)))
	var drop: float = 250.0 - state.position.y
	_expect(errors, absf(drop - 240.0) <= 5.0, "dive drops %.1f m, not 240" % drop)
	_expect(errors, steepest >= 88.0, "dive only reaches %.1f° of pitch" % steepest)
	_expect(errors, absf(_pitch_deg(state.tangent)) <= 2.0, "dive exits pitched %.1f°" % _pitch_deg(state.tangent))
	_expect(errors, state.speed >= 62.0 and state.speed <= 70.0, "dive exits at %.1f m/s" % state.speed)
	_expect(errors, _frame_error(route) <= 0.002, "dive frames are not orthonormal (%.5f)" % _frame_error(route))
	route["sections"] = sections
	route["length"] = state.distance
	var issues := PackedStringArray()
	Verify.validate_seams(route, issues)
	for issue in issues:
		errors.append("dive group: %s" % issue)
	var repeat_state := _template_state(12.0, 250.0)
	var repeat: Array = Elements.author_dive(_seed_route(repeat_state), repeat_state, {"height": 240.0, "peak_g": 5.5})
	for i in dive.size():
		_expect(errors, dive[i].length == repeat[i].length, "dive section %d is not deterministic" % i)
	return errors


## Pullout into an airtime hill — the camelback and ejector shapes differ only in their numbers.
func _hill_errors(
	speed: float,
	pullout_pitch: float,
	peak_g: float,
	rise: float,
	crown_g: float,
	rise_tolerance: float,
	apex_tolerance: float,
	asymmetry: float,
	label: String
) -> PackedStringArray:
	var errors := PackedStringArray()
	var state := _template_state(speed, 0.0)
	var route := _seed_route(state)
	var sections: Array = []
	_run_group(route, state, Elements.author_pullout(route, state, {"exit_pitch_deg": pullout_pitch, "peak_g": peak_g}), sections)
	var first: int = route.positions.size()
	var entry_height: float = state.position.y
	var entry_distance: float = state.distance
	_run_group(route, state, Elements.author_hill(route, state, {"rise": rise, "crown_g": crown_g}), sections)
	var apex := first
	for i in range(first, route.positions.size()):
		if route.positions[i].y > route.positions[apex].y:
			apex = i
	var ascent: float = route.distances[apex] - entry_distance
	var descent: float = state.distance - route.distances[apex]
	var achieved: float = route.positions[apex].y - entry_height
	_expect(errors, absf(achieved - rise) <= rise_tolerance, "%s rises %.1f m, not %.0f" % [label, achieved, rise])
	_expect(errors, absf(_pitch_deg(route.tangents[apex])) <= apex_tolerance, "%s apex is pitched %.1f°" % [label, _pitch_deg(route.tangents[apex])])
	_expect(errors, absf(_pitch_deg(state.tangent) + pullout_pitch) <= 5.0, "%s exits at %.1f°, not %.0f" % [label, _pitch_deg(state.tangent), -pullout_pitch])
	_expect(errors, absf(ascent - descent) / maxf(ascent, descent) <= asymmetry, "%s ascent and descent differ by %.0f%%" % [label, 100.0 * absf(ascent - descent) / maxf(ascent, descent)])
	return errors


## The rolled and inverting templates. These are the ones the old level-up-plus-bank-angle model
## could not express at all: a bank carried through a dive, a train hanging at the top of a loop,
## and a roll taken past vertical. Each probe is built twice to prove the solves are deterministic.
func _rolled_template_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for kind in ["twisted drop", "wave turn", "loop", "immelmann", "cutback"]:
		var probe: Dictionary = _rolled_probe(kind)
		errors.append_array(_rolled_checks(kind, probe))
		if probe.route.positions != _rolled_probe(kind).route.positions:
			errors.append("%s probe is not deterministic" % kind)
	return errors


func _rolled_probe(kind: String) -> Dictionary:
	var state: Dictionary
	var route: Dictionary
	var sections: Array = []
	var first := 1
	var group: Array = []
	match kind:
		"twisted drop":
			state = _template_state(18.0, 84.0)
			route = _seed_route(state)
			group = Elements.author_twisted_drop(route, state, {
				"target_pitch_deg": -48.0, "peak_bank_deg": 50.0, "lateral_g": 0.4,
			})
		"wave turn":
			state = _template_state(33.0, 0.0)
			route = _seed_route(state)
			_run_group(route, state, Elements.author_pullout(route, state, {
				"exit_pitch_deg": 35.0, "peak_g": 3.2,
			}), sections)
			first = route.positions.size()
			group = Elements.author_wave_turn(route, state, {
				"rise": 20.0, "crown_g": 0.2, "peak_bank_deg": 60.0, "lateral_g": 0.6,
			})
		"loop":
			state = _template_state(40.0, 0.0)
			route = _seed_route(state)
			group = Elements.author_loop(route, state, {"height": 55.0, "peak_g": 4.2})
		"immelmann":
			state = _template_state(52.0, 0.0)
			route = _seed_route(state)
			group = Elements.author_immelmann(route, state, {"peak_g": 3.8, "exit_pullout_g": 2.5})
		"cutback":
			state = _pitched_state(30.0, 25.0)
			route = _seed_route(state)
			group = Elements.author_cutback(route, state, {"peak_g": 2.2, "peak_bank_deg": 140.0})
	var entry_height: float = route.positions[first - 1].y
	var entry_tangent: Vector3 = route.tangents[first - 1]
	_run_group(route, state, group, sections)
	Elements.measure_roll_rates(route)
	return {
		"route": route, "state": state, "first": first, "group": group,
		"entry_height": entry_height, "entry_tangent": entry_tangent,
	}


func _rolled_checks(kind: String, probe: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var route: Dictionary = probe.route
	var state: Dictionary = probe.state
	var first: int = probe.first
	var lowest_up := 1.0
	var peak_bank := 0.0
	var peak_rate := 0.0
	var apex := first
	for i in range(first, route.positions.size()):
		lowest_up = minf(lowest_up, route.ups[i].y)
		peak_bank = maxf(peak_bank, absf(route.banks[i]))
		peak_rate = maxf(peak_rate, absf(route.roll_rates[i]))
		if route.positions[i].y > route.positions[apex].y:
			apex = i
	var pitch := _pitch_deg(state.tangent)
	var heading: float = Elements._heading_change_deg(route, first)
	var exit_bank: float = route.banks[-1]
	var rise: float = route.positions[apex].y - probe.entry_height
	var frame := _frame_error(route)
	match kind:
		"twisted drop":
			_expect(errors, absf(pitch + 48.0) <= 2.0, "twisted drop exits pitched %.1f°, not -48" % pitch)
			_expect(errors, absf(heading) >= 35.0, "twisted drop only sweeps %.1f° of heading" % heading)
			_expect(errors, lowest_up > 0.2, "twisted drop rolls over (lowest up.y %.3f)" % lowest_up)
			_expect(errors, absf(exit_bank) <= 6.0, "twisted drop exits banked %.1f°" % exit_bank)
			_expect(errors, frame <= 0.002, "twisted drop frames are not orthonormal (%.5f)" % frame)
		"wave turn":
			_expect(errors, absf(rise - 20.0) <= 2.0, "wave turn rises %.1f m, not 20" % rise)
			_expect(errors, absf(route.banks[apex]) >= 45.0, "wave turn crests banked only %.1f°" % route.banks[apex])
			_expect(errors, absf(heading) >= 15.0, "wave turn only sweeps %.1f° of heading" % heading)
			_expect(errors, absf(pitch + 35.0) <= 6.0, "wave turn exits pitched %.1f°, not -35" % pitch)
		"loop":
			var valley := 0.0
			for i in range(first, first + maxi((route.positions.size() - first) / 5, 1)):
				valley = maxf(valley, route.curvatures[i].length())
			var apex_curvature: float = route.curvatures[apex].length()
			var closure: float = state.tangent.dot(probe.entry_tangent)
			_expect(errors, absf(rise - 55.0) <= 2.0, "loop stands %.1f m, not 55" % rise)
			_expect(errors, lowest_up < -0.9, "loop never hangs the train (lowest up.y %.3f)" % lowest_up)
			_expect(errors, closure > 0.995, "loop exit tangent misses the entry (%.4f)" % closure)
			_expect(errors, absf(pitch) <= 2.0, "loop exits pitched %.1f°" % pitch)
			_expect(errors, apex_curvature > valley, "loop is not a teardrop (apex %.4f, valley %.4f)" % [apex_curvature, valley])
		"immelmann":
			var swept: float = absf(probe.group[0].element.heading_change_deg)
			_expect(errors, absf(swept - 180.0) <= 8.0, "immelmann reverses %.1f°, not 180" % swept)
			_expect(errors, lowest_up < -0.9, "immelmann never inverts (lowest up.y %.3f)" % lowest_up)
			_expect(errors, absf(pitch) <= 3.0, "immelmann exits pitched %.1f°" % pitch)
			_expect(errors, peak_rate <= 120.0, "immelmann rolls at %.1f°/s" % peak_rate)
			_expect(errors, route.ups[-1].y > 0.9, "immelmann exits upside down (up.y %.3f)" % route.ups[-1].y)
		"cutback":
			var reversal: float = absf(probe.group[0].element.heading_change_deg)
			_expect(errors, absf(reversal - 180.0) <= 8.0, "cutback reverses %.1f°, not 180" % reversal)
			_expect(errors, peak_bank >= 110.0, "cutback only reaches %.1f° of bank" % peak_bank)
			_expect(errors, absf(exit_bank) <= 6.0, "cutback exits banked %.1f°" % exit_bank)
			_expect(errors, frame <= 0.002, "cutback frames are not orthonormal (%.5f)" % frame)
	return errors


func _pitched_state(speed: float, pitch: float) -> Dictionary:
	var state := _template_state(speed, 0.0)
	var tangent := Vector3(0, sin(deg_to_rad(pitch)), -cos(deg_to_rad(pitch))).normalized()
	state["tangent"] = tangent
	state["up"] = (Vector3.UP - tangent * tangent.y).normalized()
	return state


func _expect(errors: PackedStringArray, condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


func _frame_error(route: Dictionary) -> float:
	var worst := 0.0
	for i in route.positions.size():
		var tangent: Vector3 = route.tangents[i]
		var up: Vector3 = route.ups[i]
		var right: Vector3 = route.rights[i]
		worst = maxf(worst, absf(tangent.length_squared() - 1.0))
		worst = maxf(worst, absf(up.length_squared() - 1.0))
		worst = maxf(worst, absf(right.length_squared() - 1.0))
		worst = maxf(worst, absf(tangent.dot(up)))
		worst = maxf(worst, absf(tangent.dot(right)))
		worst = maxf(worst, absf(up.dot(right)))
	return worst


func _terrain_for_seed(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return Terrain.generate(rng)
