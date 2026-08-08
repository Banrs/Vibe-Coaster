class_name RideGenerator
extends RefCounted

## Seed → one ride, in one pass. Every random number is drawn up front, in a fixed order, into a
## plan dictionary; assembly afterwards reads only the plan and the live integration state, so the
## same seed replays bit for bit. Layout works in a terrain frame — s measured from the escarpment
## base line toward the plateau, a measured along the cliff — so a whole ride mirrors by flipping
## one basis vector, and every placement question is asked against the wobbled edge distance the
## clearance check itself reads.

const STATION_SPEED := 6.0
const STATION_HEIGHT := 12.0
const MARQUEE_ORDER := ["camelback", "immelmann", "loop"]
## The pitch profile a lift or launch climb holds is a septic ramp in and out, so it delivers this
## fraction of length·sin(pitch) in height. Used to size a climb before it is integrated.
const RAMP_DELIVERY := 0.86
## Roll rate a correction turn is allowed to ask for, well inside the 120°/s limit.
const ROLL_BUDGET := 90.0


## ------------------------------------------------------------------------------------ top level


static func build(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var terrain: Dictionary = RideTerrain.generate(rng)
	var plan := _plan(rng)
	var layout := _layout(terrain, plan.mirror)
	var station_position := _world(layout, plan.station_s, plan.station_a, STATION_HEIGHT)
	var station_tangent := _direction(layout, 0.0)
	var state := {
		"position": station_position,
		"tangent": station_tangent,
		"up": Vector3.UP,
		"speed": STATION_SPEED,
		"distance": 0.0,
		"time": 0.0,
	}
	var route: Dictionary = RideElements.new_route()
	RideElements.append_state(route, state, 0, 1.0, 0.0, 0.0, 0, Vector3.ZERO)
	var sections: Array = []
	var tunnel: Array = []
	_station_and_lift(plan, route, state, sections)
	_opening_drop(layout, plan, route, state, sections)
	_low_act(layout, plan, route, state, sections)
	_cliff_climb(layout, plan, route, state, sections)
	_clifftop(layout, plan, route, state, sections)
	_dive_and_tunnel(layout, plan, route, state, sections, tunnel)
	_marquee(layout, plan, route, state, sections)
	_return_run(layout, plan, route, state, sections, station_position, station_tangent)
	RideElements.append_closure(route, state, sections, station_position, station_tangent, STATION_SPEED)
	RideElements.measure_roll_rates(route)
	route["sections"] = sections
	route["length"] = state.distance
	route["duration"] = state.time
	route["bounds"] = RideElements._bounds(route.positions)
	route["seed"] = seed_value
	route["terrain"] = terrain
	route["tunnel_sections"] = tunnel
	route["plan"] = plan
	return route


## ---------------------------------------------------------------------------------------- plan


## Every draw in this function is ordered and unconditional: the branch flags are drawn, but the
## numbers behind both branches are drawn either way, so adding a branch never shifts the stream.
static func _plan(rng: RandomNumberGenerator) -> Dictionary:
	var plan := {}
	plan["mirror"] = rng.randf() < 0.5
	plan["station_s"] = -rng.randf_range(440.0, 520.0)
	plan["station_a"] = -rng.randf_range(80.0, 140.0)
	plan["lift_length"] = rng.randf_range(260.0, 320.0)
	## A constant-speed lift at Falcon's 40 km/h leaves the twisted drop a 28 m element at this
	## bank: 130°/s of roll and a curvature ramp three samples wide. Everything about that element
	## scales with the speed it is entered at, so the lift crests a little faster than the record.
	plan["lift_speed"] = rng.randf_range(15.5, 16.5)
	plan["lift_height"] = rng.randf_range(52.0, 60.0)
	plan["drop_bottom_height"] = rng.randf_range(14.0, 18.0)
	plan["drop_pitch_deg"] = -rng.randf_range(44.0, 54.0)
	plan["drop_bank_deg"] = rng.randf_range(40.0, 48.0)
	plan["drop_lateral_g"] = rng.randf_range(0.35, 0.5)
	## Onset-limited, not strength-limited: a 5 g pullout out of the twisted drop reaches its plateau
	## in 5 m of track at 30 m/s, which is 26 g/s of onset against a 25 g/s ceiling.
	plan["drop_pullout_g"] = rng.randf_range(3.6, 4.2)
	plan["low_heading_deg"] = rng.randf_range(8.0, 14.0)
	plan["low_hill_count"] = 2 if rng.randf() < 0.5 else 3
	## Four pullouts, three hills: the fourth pullout is the wave turn's entry. Both are drawn in
	## one paired loop so the stream does not move when the hill count does.
	var low_pullouts := []
	var low_hills := []
	for _i in 4:
		low_pullouts.append({
			"exit_pitch_deg": rng.randf_range(18.0, 24.0), "peak_g": rng.randf_range(2.4, 2.9),
		})
		low_hills.append({"rise": rng.randf_range(8.0, 16.0), "crown_g": -rng.randf_range(0.9, 1.3)})
	plan["low_pullouts"] = low_pullouts
	plan["low_hills"] = low_hills
	plan["wave"] = {
		"rise": rng.randf_range(14.0, 22.0),
		"crown_g": rng.randf_range(0.1, 0.3),
		"peak_bank_deg": rng.randf_range(55.0, 65.0),
		"lateral_g": rng.randf_range(0.5, 0.7),
	}
	plan["level_g"] = rng.randf_range(2.4, 2.8)
	plan["climb_pitch_deg"] = rng.randf_range(25.0, 27.0)
	## Height the crest stands above the plateau. The rim has to clear both the climb coming up
	## under it and the dive pitching over it, and both of those read the same margin.
	plan["crest_margin"] = rng.randf_range(36.0, 44.0)
	## Where the crest sits relative to the plateau edge. Far enough in that the rim turn still has
	## plateau under it, close enough that the dive's pitch-over is past the face before it drops.
	plan["crest_edge_offset"] = rng.randf_range(25.0, 40.0)
	plan["climb_bank_deg"] = rng.randf_range(40.0, 55.0)
	plan["launch_length"] = rng.randf_range(110.0, 140.0)
	plan["launch_exit_speed"] = rng.randf_range(42.0, 44.0)
	plan["climb_exit_speed"] = rng.randf_range(15.0, 17.0)
	plan["hold_brake_length"] = rng.randf_range(55.0, 70.0)
	plan["crest_hold_length"] = rng.randf_range(8.0, 12.0)
	plan["hold_release_pitch_deg"] = rng.randf_range(10.0, 14.0)
	## Speed the plateau beat is ridden at. Everything up here is solved from it, and it is squeezed
	## from both sides: below about 20 m/s a plateau-scale hill is a dozen samples long and its
	## curvature ramp lands inside one of them, while above about 20 m/s the dive's pitch-over —
	## which spends height as v² — eats the whole cliff before it is vertical. So the suspense runs
	## fast enough to have shape and a short rim brake takes it back down before the lip.
	plan["hold_release_speed"] = rng.randf_range(23.0, 25.0)
	plan["rim_brake_length"] = rng.randf_range(40.0, 60.0)
	plan["rim_brake_speed"] = rng.randf_range(15.0, 17.0)
	## The clifftop crest is a pullout up and a pullout back down, not an authored airtime hill: at
	## plateau speed a hill's rise saturates its crown-span solve and comes back as a ten-metre stub
	## whose curvature ramp lands inside one sample. The pitch is held shallow for the same reason
	## the seams care about — an element that ends at 1 g while pitched hands a pullout starting at
	## cos(pitch) a curvature step of (1−cos θ)·g/v², which is only small while θ is.
	plan["suspense_pullout"] = {
		"exit_pitch_deg": rng.randf_range(14.0, 18.0), "peak_g": rng.randf_range(1.6, 2.0),
	}
	plan["rim"] = {
		"outward_bank_deg": rng.randf_range(22.0, 30.0), "lateral_g": rng.randf_range(1.0, 1.3),
	}
	plan["dive_peak_g"] = rng.randf_range(5.0, 5.6)
	plan["dive_pitch_deg"] = -90.0
	plan["tunnel_length"] = rng.randf_range(420.0, 520.0)
	plan["tunnel_exit_speed"] = rng.randf_range(93.5, 94.8)
	## The whole return run sits on this: a past-vertical overbank at 85 m/s drops thirty metres by
	## construction, so the high-speed half of the ride has to leave the tunnel above that.
	plan["tunnel_end_height"] = rng.randf_range(28.0, 32.0)
	var order: Array = MARQUEE_ORDER.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = order[i]
		order[i] = order[j]
		order[j] = swap
	plan["marquee_order"] = order
	plan["camelback"] = {
		"exit_pitch_deg": rng.randf_range(58.0, 64.0),
		"peak_g": rng.randf_range(5.4, 5.8),
		"rise": rng.randf_range(175.0, 190.0),
		"crown_g": -rng.randf_range(0.25, 0.35),
		"exit_peak_g": rng.randf_range(4.6, 5.0),
	}
	plan["immelmann"] = {"peak_g": rng.randf_range(3.6, 4.0)}
	plan["loop"] = {"height": rng.randf_range(70.0, 80.0), "peak_g": rng.randf_range(4.0, 4.4)}
	plan["doglegs"] = [rng.randf_range(-30.0, 30.0), rng.randf_range(-30.0, 30.0)]
	plan["turnaround_deg"] = rng.randf_range(165.0, 195.0)
	plan["turnaround_bank_deg"] = rng.randf_range(65.0, 75.0)
	plan["overbank"] = {
		"heading_change_deg": rng.randf_range(80.0, 100.0),
		"bank_deg": rng.randf_range(88.0, 96.0),
		"peak_g": rng.randf_range(2.4, 2.8),
	}
	var return_pullouts := []
	var return_hills := []
	for _i in 2:
		return_pullouts.append({
			"exit_pitch_deg": rng.randf_range(12.0, 18.0), "peak_g": rng.randf_range(3.0, 3.4),
		})
		return_hills.append({"rise": rng.randf_range(10.0, 18.0), "crown_g": -rng.randf_range(0.5, 0.8)})
	plan["return_pullouts"] = return_pullouts
	plan["return_hills"] = return_hills
	plan["brake_length"] = rng.randf_range(260.0, 340.0)
	plan["approach_lead"] = rng.randf_range(180.0, 220.0)
	return plan


## ---------------------------------------------------------------------------------- story slots


static func _station_and_lift(
	plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	## The lift is sized by the height the opening drop has to spend, not by a chosen angle: a
	## constant-speed lift arrives at 41 km/h, and everything the low act runs on comes from here.
	var pitch := rad_to_deg(asin(clampf(
		plan.lift_height / (RAMP_DELIVERY * plan.lift_length), 0.05, 0.5
	)))
	_add(route, state, sections, [
		RideElements.grade_section("Station", 45.0, _flat_pitch(), 12.5, 0, 4.0),
		RideElements.grade_section(
			"LSM1 lift",
			plan.lift_length,
			[Vector2(0, 0), Vector2(0.2, pitch), Vector2(0.8, pitch), Vector2(1, 0)],
			plan.lift_speed,
			1
		),
	])


## The opening element is a non-inverting banked side-dive; the frame sign carries the seed mirror,
## so it always falls away toward the escarpment and starts the run's drift inland. The twist only
## sets the attitude — it ends on free-fall support, so a straight fall carries the height, and the
## fall is sized by the same fixed point author_dive uses: the pullout's own cost grows with the
## speed the fall delivers, so the drop cannot simply be subtracted.
static func _opening_drop(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	_add(route, state, sections, RideElements.author_twisted_drop(route, state, {
		"target_pitch_deg": plan.drop_pitch_deg,
		"peak_bank_deg": layout.turn_sign * plan.drop_bank_deg,
		"lateral_g": plan.drop_lateral_g,
	}))
	var want: float = state.position.y - plan.drop_bottom_height
	var drop := maxf(want, 0.0) * 0.6
	var fall: Dictionary = {}
	var pullout: Dictionary = {}
	for _pass in 5:
		fall = RideElements.author_fall(route, state, {"drop": drop})[0]
		var after_fall: Dictionary = RideElements._trial(route, state, fall)
		pullout = RideElements.author_pullout(after_fall.route, after_fall.state, {
			"exit_pitch_deg": 0.0, "peak_g": plan.drop_pullout_g,
		})[0]
		var landed: Dictionary = RideElements._trial(after_fall.route, after_fall.state, pullout)
		var achieved: float = state.position.y - landed.state.position.y
		if absf(achieved - want) < 0.5:
			break
		drop = maxf(drop - (achieved - want) / 1.4, 0.0)
	_add(route, state, sections, [fall, pullout])


## Terrain-hugging airtime on the plain, aimed at a shallow inland heading so the act arrives at the
## launch corridor without any of its element lengths being chosen for position.
static func _low_act(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	var heading: float = plan.low_heading_deg
	for i in plan.low_hill_count:
		_align(layout, route, state, sections, heading, plan.climb_bank_deg)
		_add(route, state, sections, RideElements.author_pullout(route, state, plan.low_pullouts[i]))
		_add(route, state, sections, RideElements.author_hill(route, state, plan.low_hills[i]))
	_align(layout, route, state, sections, heading, plan.climb_bank_deg)
	_add(route, state, sections, RideElements.author_pullout(route, state, plan.low_pullouts[3]))
	## A wave turn's length comes from its rise, not from its bank, so the roll rate it asks for is
	## whatever bank·v/(0.16·length) happens to be. Past a point the bank is what has to give.
	var span: float = 1.7 * plan.wave.rise / maxf(
		sin(deg_to_rad(absf(RideElements.exit_pitch_deg(state)))), 0.15
	)
	_add(route, state, sections, RideElements.author_wave_turn(route, state, {
		"rise": plan.wave.rise,
		"crown_g": plan.wave.crown_g,
		"peak_bank_deg": layout.turn_sign * minf(
			plan.wave.peak_bank_deg, ROLL_BUDGET * 0.16 * span / state.speed
		),
		"lateral_g": plan.wave.lateral_g,
	}))
	## The story asks for a cutback here. It is not authorable from this generator yet: author_cutback
	## reads a bank out of its own trial route at first + roundi(0.5 * count) (elements.gd:967), which
	## indexes past the end whenever its length solve collapses to a single sample, and that solve
	## collapses for most entry attitudes above roughly 22° at 30 m/s. See the report for the numbers.
	_level(route, state, sections, plan.level_g)


## LSM2: a flat launch on the plain and a straight powered climb that crosses the apron and the face
## and crests just inside the rim. The heading is solved so the crest lands at a chosen edge
## distance — the aim is against the wobbled edge, because a nominal offset is not what the terrain
## check reads. The climb pitch is then set from the height actually left to gain, and retuned once
## against the integrated rise; that single retune is the only correction in this generator.
static func _cliff_climb(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	var terrain: Dictionary = layout.terrain
	var target: float = terrain.apron_width + terrain.face_width + plan.crest_edge_offset
	var pitch: float = plan.climb_pitch_deg
	var rise: float = terrain.relief + plan.crest_margin - state.position.y
	var length: float = maxf(rise / (RAMP_DELIVERY * sin(deg_to_rad(pitch))), 100.0)
	var climb_run: float = length * cos(deg_to_rad(pitch))
	## Each align turn moves the train before the next one is aimed, so the aim is re-solved from
	## where it actually is; the residual heading a turn is allowed to leave is then absorbed by
	## the launch, which is the one straight run whose length costs the climb nothing.
	for _pass in 3:
		_align(
			layout, route, state, sections,
			_approach_heading(layout, state.position, plan.launch_length + climb_run, target),
			plan.climb_bank_deg
		)
	_add(route, state, sections, [RideElements.grade_section(
		"LSM2 launch",
		_approach_run(layout, state.position, state.tangent, climb_run, target),
		_flat_pitch(),
		plan.launch_exit_speed,
		2
	)])
	rise = terrain.relief + plan.crest_margin - state.position.y
	length = maxf(rise / (RAMP_DELIVERY * sin(deg_to_rad(pitch))), 100.0)
	var climb := _climb_section(plan, length, pitch)
	var trial := _trial_grade(route, state, climb)
	var reached: float = trial.state.position.y - state.position.y
	if absf(trial.state.position.y - terrain.relief - 16.0) > 6.0:
		pitch = rad_to_deg(asin(clampf(sin(deg_to_rad(pitch)) * rise / maxf(reached, 1.0), 0.05, 0.9)))
		climb = _climb_section(plan, length, pitch)
	_add(route, state, sections, [climb])


static func _climb_section(plan: Dictionary, length: float, pitch: float) -> Dictionary:
	return RideElements.grade_section(
		"LSM2 climb",
		length,
		[Vector2(0, 0), Vector2(0.14, pitch), Vector2(0.86, pitch), Vector2(1, 0)],
		plan.climb_exit_speed,
		2
	)


## Crest crawl and the clifftop suspense beat. The holding brake runs along the rim rather than into
## it, and the rim brake takes the speed back off before the lip, so the crest, the outward-banked
## turn and the dive all sit within a few tens of metres of the edge.
static func _clifftop(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	_align(layout, route, state, sections, 0.0, plan.climb_bank_deg)
	## Release is a ramp, not a shove: the speed the clifftop elements need comes off the plateau as
	## height, so the drive a grade section solves for is left with nothing but drag to cover.
	var release_pitch: float = plan.hold_release_pitch_deg
	var release_drop: float = (
		plan.hold_release_speed * plan.hold_release_speed - 1.9 * 1.9
	) / (2.0 * RideElements.G0)
	_add(route, state, sections, [
		RideElements.grade_section("Holding brake", plan.hold_brake_length, _flat_pitch(), 2.0, 0, 1.2),
		RideElements.grade_section("Crest hold", plan.crest_hold_length, _flat_pitch(), 1.9, 0, 1.2),
		RideElements.grade_section(
			"Hold release",
			release_drop / (RAMP_DELIVERY * sin(deg_to_rad(release_pitch))),
			[
				Vector2(0, 0), Vector2(0.3, -release_pitch),
				Vector2(0.7, -release_pitch), Vector2(1, 0),
			],
			plan.hold_release_speed,
			0,
			1.2
		),
	])
	_add(route, state, sections, RideElements.author_pullout(route, state, {
		"exit_pitch_deg": plan.suspense_pullout.exit_pitch_deg,
		"peak_g": _peak_for(
			state.speed, plan.suspense_pullout.exit_pitch_deg, plan.suspense_pullout.peak_g
		),
	}))
	## Both of the next two want level track: a grade section builds its own tangent from its pitch
	## profile, and an outward-banked turn only holds altitude from level flight — entered nose-down
	## it keeps falling, and its heading solve then chases an element diving off the cliff.
	_level(route, state, sections, plan.level_g)
	_add(route, state, sections, [RideElements.grade_section(
		"Rim brake", plan.rim_brake_length, _flat_pitch(), plan.rim_brake_speed, 0, 1.2
	)])
	var sweep := rad_to_deg(angle_difference(
		deg_to_rad(_heading_deg(layout, state.tangent)), deg_to_rad(-90.0)
	))
	_add(route, state, sections, RideElements.author_rim_turn(route, state, {
		"heading_change_deg": layout.turn_sign * sweep,
		"outward_bank_deg": plan.rim.outward_bank_deg,
		"lateral_g": plan.rim.lateral_g,
	}))
	_align(layout, route, state, sections, -90.0, 20.0, 1.0)
	_level(route, state, sections, plan.level_g)


## The cliff dive and the downhill tunnel launch. The dive lands as high above the apron as the
## tunnel needs to spend getting back to the plain, so the tunnel's own pitch is what sets the
## dive's exit attitude — a grade section builds its tangent from its pitch profile, so the two
## have to agree at the seam or the track kinks there.
static func _dive_and_tunnel(
	layout: Dictionary,
	plan: Dictionary,
	route: Dictionary,
	state: Dictionary,
	sections: Array,
	tunnel: Array
) -> void:
	var drop: float = maxf(
		layout.terrain.apron_height + 8.0 - plan.tunnel_end_height, 20.0
	)
	var pitch := -rad_to_deg(asin(clampf(
		drop / (plan.tunnel_length * (0.75 + 0.25 * 0.5)), 0.05, 0.32
	)))
	var dive: Array = RideElements.author_dive(route, state, {
		"height": state.position.y - plan.tunnel_end_height - drop,
		"max_pitch_deg": plan.dive_pitch_deg,
		"peak_g": plan.dive_peak_g,
		"exit_pitch_deg": pitch,
	})
	_add(route, state, sections, dive)
	tunnel.append(sections.size() - 1)
	_add(route, state, sections, [RideElements.grade_section(
		"Tunnel LSM3",
		plan.tunnel_length,
		[Vector2(0, pitch), Vector2(0.75, pitch), Vector2(1, 0)],
		plan.tunnel_exit_speed,
		3
	)])
	tunnel.append(sections.size() - 1)


## The record chase. Each candidate is pre-checked against the speed it would actually be entered
## at — too slow and it stalls, too fast and its authored size implies a load no envelope allows —
## and the seeded order simply rotates past anything that fails.
static func _marquee(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	var dogleg := 0
	for kind in plan.marquee_order:
		if not _marquee_feasible(kind, plan, state.speed):
			continue
		if dogleg > 0:
			_align(
				layout, route, state, sections,
				_heading_deg(layout, state.tangent) + plan.doglegs[dogleg - 1], 60.0
			)
		match kind:
			"camelback":
				_add(route, state, sections, RideElements.author_pullout(route, state, {
					"exit_pitch_deg": plan.camelback.exit_pitch_deg, "peak_g": plan.camelback.peak_g,
				}))
				_add(route, state, sections, RideElements.author_hill(route, state, {
					"rise": plan.camelback.rise, "crown_g": plan.camelback.crown_g,
				}))
				_add(route, state, sections, RideElements.author_pullout(route, state, {
					"exit_pitch_deg": 0.0, "peak_g": plan.camelback.exit_peak_g,
				}))
			"immelmann":
				_add(route, state, sections, RideElements.author_immelmann(route, state, plan.immelmann))
			"loop":
				_add(route, state, sections, RideElements.author_loop(route, state, plan.loop))
		dogleg += 1


static func _marquee_feasible(kind: String, plan: Dictionary, speed: float) -> bool:
	var g: float = RideElements.G0
	match kind:
		"camelback":
			return speed > sqrt(2.0 * g * plan.camelback.rise) + 4.0
		"immelmann":
			## Apex of a sustained-g half loop, and the load it would take to keep one human-sized.
			return speed > 55.0 and 0.42 * speed * speed / g < 150.0
		"loop":
			var radius: float = plan.loop.height / 2.6
			return speed > sqrt(2.0 * g * plan.loop.height * 1.35) and speed * speed / (g * radius) < 5.5
	return false


## Home run: turn back toward the station, a past-vertical overbank, and return airtime. The final
## heading points at a spot short of the station so the C4 closure has a straight approach.
static func _return_run(
	layout: Dictionary,
	plan: Dictionary,
	route: Dictionary,
	state: Dictionary,
	sections: Array,
	station_position: Vector3,
	station_tangent: Vector3
) -> void:
	var approach: Vector3 = station_position - station_tangent * plan.approach_lead
	var home := _aim_heading(layout, state.position, approach)
	var delta := rad_to_deg(angle_difference(
		deg_to_rad(_heading_deg(layout, state.tangent)), deg_to_rad(home)
	))
	if absf(delta) > 100.0:
		_add(route, state, sections, RideElements.author_turn(route, state, {
			"heading_change_deg": layout.turn_sign * delta, "bank_deg": plan.turnaround_bank_deg,
		}))
	else:
		_align(layout, route, state, sections, home, plan.turnaround_bank_deg)
	## Past vertical at 83 m/s the support is gone for the whole element, and the roll-rate limit
	## forces it to be long: ninety degrees of it is 480 m of track and eighty metres of descent.
	## The corridor either has that height under it or the beat does not happen here.
	_add_if_sound(layout, route, state, sections, RideElements.author_overbank(route, state, {
		"heading_change_deg": layout.turn_sign * plan.overbank.heading_change_deg,
		"bank_deg": plan.overbank.bank_deg,
		"peak_g": plan.overbank.peak_g,
	}))
	## Every element here is hundreds of metres long at 80 m/s, so the run is kept pointed home
	## between them: a corridor walked the wrong way costs a kilometre of turn to walk back. A turn
	## carries whatever pitch it is handed, so each one is entered level or it flies the ride down.
	_level(route, state, sections, plan.level_g)
	_align(layout, route, state, sections, _aim_heading(layout, state.position, approach), 60.0)
	for i in 2:
		_add(route, state, sections, RideElements.author_pullout(route, state, plan.return_pullouts[i]))
		_add(route, state, sections, RideElements.author_hill(route, state, plan.return_hills[i]))
	_level(route, state, sections, plan.level_g)
	## Aimed twice: a turn at 75 m/s is hundreds of metres long, so the point it was aimed at has
	## moved a long way behind the train by the time it comes out of the first one.
	for _pass in 2:
		_align(layout, route, state, sections, _aim_heading(layout, state.position, approach), 60.0)
	## The brake run reaches the approach point rather than being a fixed length, and comes down to
	## station height on the way, so the C4 closure is handed a short, near-level gap instead of
	## whatever the last turn happened to leave it — a closure that has to shed thirty metres of
	## potential as well as the speed cannot solve its drive and stalls short of the platform.
	var brake_length: float = clampf(
		state.position.distance_to(approach), plan.brake_length, plan.brake_length + 900.0
	)
	var brake_pitch := rad_to_deg(asin(clampf(
		(state.position.y - STATION_HEIGHT) / (RAMP_DELIVERY * brake_length), -0.35, 0.35
	)))
	_add(route, state, sections, [RideElements.grade_section(
		"Final brakes",
		brake_length,
		[
			Vector2(0, 0), Vector2(0.3, -brake_pitch), Vector2(0.7, -brake_pitch), Vector2(1, 0),
		],
		7.0
	)])


## ------------------------------------------------------------------------------ assembly helpers


## Trial-integrate a group and commit it only if it fits the ground it is being flown over. The
## templates size themselves from speed alone, and at 85 m/s several of them are simply larger than
## the corridor: this is the marquee's rotation applied to a single beat, not a correction — the
## geometry is either taken as authored or not taken.
static func _add_if_sound(
	layout: Dictionary, route: Dictionary, state: Dictionary, sections: Array, group: Array
) -> bool:
	var trial_route: Dictionary = route.duplicate(true)
	var trial_state: Dictionary = state.duplicate(true)
	var first: int = trial_route.positions.size()
	for section in group:
		if section.kind == "FVD":
			RideElements.integrate_fvd(trial_route, trial_state, section.duplicate(true), -1)
		else:
			RideElements.integrate_grade(trial_route, trial_state, section.duplicate(true), -1)
	RideElements.measure_roll_rates(trial_route)
	for i in range(first, trial_route.positions.size()):
		var point: Vector3 = trial_route.positions[i]
		if point.y < RideTerrain.height(layout.terrain, point.x, point.z) + 8.0:
			return false
		if absf(trial_route.roll_rates[i]) > ROLL_BUDGET + 20.0:
			return false
		if trial_route.speeds[i] < 4.0:
			return false
	_add(route, state, sections, group)
	return true


## The bookkeeping build_route does per section, done here instead because every author_* needs the
## live route and state to solve against, which a pre-built section list cannot provide.
static func _add(route: Dictionary, state: Dictionary, sections: Array, group: Array) -> void:
	for section in group:
		section["start_index"] = route.positions.size() - 1
		section["start_distance"] = state.distance
		section["start_time"] = state.time
		section["start_height"] = state.position.y
		section["entry_speed"] = state.speed
		if section.kind == "FVD":
			RideElements.integrate_fvd(route, state, section, sections.size())
		else:
			RideElements.integrate_grade(route, state, section, sections.size())
		section["end_index"] = route.positions.size() - 1
		section["end_distance"] = state.distance
		section["end_time"] = state.time
		section["end_height"] = state.position.y
		section["exit_speed"] = state.speed
		sections.append(section)


## A grade section builds its own tangent from its pitch profile, so anything authored has to hand
## it level track. This is that: the pullout every infrastructure piece is entered through.
static func _level(route: Dictionary, state: Dictionary, sections: Array, peak_g: float) -> void:
	var pitch := RideElements.exit_pitch_deg(state)
	if absf(pitch) <= 1.0:
		return
	if pitch > 0.0:
		## Coming back to level from a climb is a crest, not a pullout: a pullout's profile only ever
		## curves upward, so asked to take pitch off it has no length that works and its solve
		## collapses onto a stub with the whole force ramp inside one sample.
		_add(route, state, sections, RideElements.author_pushover(route, state, {
			"target_pitch_deg": 0.0, "edge_g": 0.7,
		}))
		return
	_add(route, state, sections, RideElements.author_pullout(route, state, {
		"exit_pitch_deg": 0.0, "peak_g": _peak_for(state.speed, absf(pitch), peak_g),
	}))


## Sustained g an arc of this angle can be authored at without asking for a section short enough
## that its own force ramp lands inside a sample or two: below the length floor every solve seeds
## from, they also start searching a region where the train stalls rather than turns.
static func _peak_for(speed: float, pitch_change_deg: float, wanted: float) -> float:
	var arc := deg_to_rad(maxf(pitch_change_deg, 1.0)) * speed * speed / (30.0 * RideElements.G0)
	return clampf(1.0 + arc, 1.15, wanted)


static func _align(
	layout: Dictionary,
	route: Dictionary,
	state: Dictionary,
	sections: Array,
	target_heading_deg: float,
	bank_deg: float,
	tolerance := 4.0
) -> void:
	var delta := rad_to_deg(angle_difference(
		deg_to_rad(_heading_deg(layout, state.tangent)), deg_to_rad(target_heading_deg)
	))
	if absf(delta) <= tolerance:
		return
	_add(route, state, sections, RideElements.author_turn(route, state, {
		"heading_change_deg": layout.turn_sign * delta,
		"bank_deg": _bank_for(delta, state.speed, bank_deg),
	}))


## Bank a turn of this size can be flown at. The roll-in has to deliver the full bank inside a
## fixed fraction of an arc whose length falls with the heading change, so a small correction flown
## at a big bank is a violent roll rather than a gentle one: rate ≈ bank·tan(bank)·g / (0.16·Δ·v).
static func _bank_for(delta_deg: float, speed: float, wanted: float) -> float:
	var budget := ROLL_BUDGET * 0.16 * deg_to_rad(absf(delta_deg)) * speed / RideElements.G0
	var low := 4.0
	var high: float = maxf(wanted, low)
	if low * tan(deg_to_rad(low)) >= budget:
		return low
	if high * tan(deg_to_rad(high)) <= budget:
		return high
	for _step in 16:
		var middle := (low + high) * 0.5
		if middle * tan(deg_to_rad(middle)) < budget:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


static func _trial_grade(route: Dictionary, state: Dictionary, section: Dictionary) -> Dictionary:
	var trial_route: Dictionary = route.duplicate(true)
	var trial_state: Dictionary = state.duplicate(true)
	RideElements.integrate_grade(trial_route, trial_state, section.duplicate(true), -1)
	return {"route": trial_route, "state": trial_state}


static func _flat_pitch() -> Array:
	return [Vector2(0, 0), Vector2(1, 0)]


## -------------------------------------------------------------------------------- terrain frame


## n points inland across the escarpment, e runs along it; the seed mirror flips e, which mirrors
## every layout decision at once. turn_sign converts a heading change in this frame into the world
## heading change the turn templates measure.
static func _layout(terrain: Dictionary, mirror: bool) -> Dictionary:
	var n: Vector2 = terrain.edge_normal
	var e := Vector2(-n.y, n.x)
	if mirror:
		e = -e
	return {"terrain": terrain, "n": n, "e": e, "turn_sign": e.x * n.y - e.y * n.x}


static func _world(layout: Dictionary, s: float, a: float, y: float) -> Vector3:
	var point: Vector2 = layout.n * (s + layout.terrain.edge_offset) + layout.e * a
	return Vector3(point.x, y, point.y)


## Heading is measured from +a toward +s, so 0° runs along the cliff and 90° drives straight at it.
static func _direction(layout: Dictionary, heading_deg: float) -> Vector3:
	var angle := deg_to_rad(heading_deg)
	var point: Vector2 = layout.n * sin(angle) + layout.e * cos(angle)
	return Vector3(point.x, 0.0, point.y).normalized()


static func _heading_deg(layout: Dictionary, tangent: Vector3) -> float:
	var flat := Vector2(tangent.x, tangent.z)
	return rad_to_deg(atan2(layout.n.dot(flat), layout.e.dot(flat)))


static func _aim_heading(layout: Dictionary, from: Vector3, to: Vector3) -> float:
	var flat := Vector2(to.x - from.x, to.z - from.z)
	return rad_to_deg(atan2(layout.n.dot(flat), layout.e.dot(flat)))


static func _edge(layout: Dictionary, position: Vector3) -> float:
	return RideTerrain.edge_distance(layout.terrain, position.x, position.z)


## Heading that puts a point `run` metres ahead at `target` edge distance. Monotone in the heading
## over this range, so a bisection is exact enough and cannot run away.
static func _approach_heading(
	layout: Dictionary, position: Vector3, run: float, target: float
) -> float:
	var low := 3.0
	var high := 88.0
	if _edge(layout, position + _direction(layout, high) * run) <= target:
		return high
	if _edge(layout, position + _direction(layout, low) * run) >= target:
		return low
	for _step in 30:
		var middle := (low + high) * 0.5
		if _edge(layout, position + _direction(layout, middle) * run) < target:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


## Straight run that puts the crest at `target` edge distance on the heading the train actually
## ended up with; clamped to a launch length that is still a launch.
static func _approach_run(
	layout: Dictionary, position: Vector3, tangent: Vector3, climb_run: float, target: float
) -> float:
	var direction := Vector3(tangent.x, 0.0, tangent.z).normalized()
	var low := 60.0
	var high := 420.0
	if _edge(layout, position + direction * (high + climb_run)) <= target:
		return high
	if _edge(layout, position + direction * (low + climb_run)) >= target:
		return low
	for _step in 24:
		var middle := (low + high) * 0.5
		if _edge(layout, position + direction * (middle + climb_run)) < target:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5
