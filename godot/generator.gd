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
## The inversions live in act one and nowhere else. Measured: a 75 m loop entered at the 94 m/s the
## tunnel delivers is a 31 g element, and an Immelmann at that speed apexes 380 m up. Both shapes
## cost height and load as v², so the only stretch of this ride that can carry a record-class
## inversion is the plain, at the forty-odd metres a second the opening drop hands it.
const INVERSION_ORDER := ["immelmann", "loop"]
## The pitch profile a lift or launch climb holds is a septic ramp in and out, so it delivers this
## fraction of length·sin(pitch) in height. Used to size a climb before it is integrated.
const RAMP_DELIVERY := 0.86
## The cliff climb ramps in harder than a lift does, and delivers that much more of its length in
## height. It has to: the apron it crosses rises at up to 20°, and a climb that spends its first
## hundred and thirty metres getting to 26° grazes the slope it is supposed to be climbing out of.
const CLIMB_RAMP := 0.07
const CLIMB_DELIVERY := 0.93
## Roll rate a correction turn is allowed to ask for, well inside the 120°/s limit.
const ROLL_BUDGET := 90.0
## A cutback that solves longer than this, or that misses the reversal by more than this much
## heading, has landed on author_cutback's giant-arc root rather than on the beat that was asked
## for. Its entry speed is capped for the same reason: length grows as v², and past the cap the
## reversal is a kilometre of track no corridor here has room for.
const CUTBACK_MAX_LENGTH := 500.0
const CUTBACK_HEADING_TOLERANCE := 12.0
const CUTBACK_MAX_SPEED := 46.0
## How tall a loop this ride is willing to call a loop. Outside it the shape is out of scale for the
## beat, and the act rotates past it rather than flying something else under its name.
const LOOP_BAND := Vector2(58.0, 78.0)

## What each element is for, what it may not share with another headline beat, and which act it is
## allowed to appear in. Pure data — nothing in this file reads it. It is the seam a configurable
## generator attaches to: a slot list plus a size class is enough to drive element selection from
## outside, and the signature is what stops two marquee beats from telling the same story.
const REGISTRY := {
	"twisted_drop": {
		"size_class": "marquee",
		"signature": "opening banked side-dive",
		"slots": ["opening"],
	},
	"immelmann": {
		"size_class": "inversion",
		"signature": "half loop rolled upright",
		"slots": ["inversion"],
	},
	"loop": {
		"size_class": "inversion",
		"signature": "vertical teardrop",
		"slots": ["inversion"],
	},
	"cutback": {
		"size_class": "inversion",
		"signature": "past-vertical heading reversal",
		"slots": ["low", "return"],
	},
	"hill": {
		"size_class": "reference",
		"signature": "airtime crest",
		"slots": ["low", "camelback", "return"],
	},
	"wave_turn": {
		"size_class": "reference",
		"signature": "airtime crest on edge",
		"slots": ["low"],
	},
	"turn": {
		"size_class": "reference",
		"signature": "coordinated corridor turn",
		"slots": ["low", "inversion", "clifftop", "return"],
	},
	"rim_turn": {
		"size_class": "reference",
		"signature": "outward-banked rim suspense",
		"slots": ["clifftop"],
	},
	"overbank": {
		"size_class": "marquee",
		"signature": "past-vertical descending turn",
		"slots": ["return"],
	},
	"camelback": {
		"size_class": "marquee",
		"signature": "post-tunnel structure hill",
		"slots": ["camelback"],
	},
	"dive": {
		"size_class": "marquee",
		"signature": "vertical cliff face drop",
		"slots": ["cliff"],
	},
}


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
	_inversion_act(layout, plan, route, state, sections)
	_low_act(layout, plan, route, state, sections)
	_cliff_climb(layout, plan, route, state, sections)
	_clifftop(layout, plan, route, state, sections)
	_dive_and_tunnel(layout, plan, route, state, sections, tunnel)
	_camelback(plan, route, state, sections)
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
	plan["station_s"] = -rng.randf_range(900.0, 1050.0)
	plan["station_a"] = -rng.randf_range(80.0, 140.0)
	## The lift is a chosen grade of a chosen height, not a chosen length: the crest is what the
	## inversion act is paid out of, so it is the plan value and the length follows from it.
	plan["lift_pitch_deg"] = rng.randf_range(21.0, 24.0)
	## A constant-speed lift at Falcon's 40 km/h leaves the twisted drop a 28 m element at this
	## bank: 130°/s of roll and a curvature ramp three samples wide. Everything about that element
	## scales with the speed it is entered at, so the lift crests a little faster than the record.
	plan["lift_speed"] = rng.randf_range(15.5, 16.5)
	## Height the crest stands at. Everything downstream of the twisted drop is bought with it: the
	## drop to the plain is crest − drop_bottom_height, and the valley speed that sizes the loop and
	## the Immelmann is the square root of twice g times that.
	plan["lift_crest_height"] = rng.randf_range(156.0, 162.0)
	plan["drop_bottom_height"] = rng.randf_range(18.0, 22.0)
	plan["drop_pitch_deg"] = -rng.randf_range(44.0, 54.0)
	plan["drop_bank_deg"] = rng.randf_range(40.0, 48.0)
	plan["drop_lateral_g"] = rng.randf_range(0.35, 0.5)
	## Onset-limited, not strength-limited: a 5 g pullout out of the twisted drop reaches its plateau
	## in 5 m of track at 30 m/s, which is 26 g/s of onset against a 25 g/s ceiling.
	plan["drop_pullout_g"] = rng.randf_range(3.6, 4.2)
	var inversions: Array = INVERSION_ORDER.duplicate()
	for i in range(inversions.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap = inversions[i]
		inversions[i] = inversions[j]
		inversions[j] = swap
	plan["inversion_order"] = inversions
	## Jog between the two inversions so the second is not flown down the first's own corridor.
	plan["dogleg"] = rng.randf_range(-20.0, 20.0)
	plan["immelmann"] = {"peak_g": rng.randf_range(3.6, 4.0)}
	plan["loop"] = {"height": rng.randf_range(60.0, 72.0), "peak_g": rng.randf_range(4.0, 4.4)}
	## An Immelmann is half a loop: it exits level but ninety metres up and twenty metres a second
	## slower, and nothing downstream of it works from there. The act gives that altitude back as a
	## drop, which is also what puts the airtime hills back at the speed they are sized for. The
	## crest is shallow because a pushover's arc grows as v² and the train doubles its speed inside
	## one: measured, a −54° crest at 30 m/s spends 190 m of height before the fall has started,
	## which is more than twice what the Immelmann borrowed.
	plan["inversion_exit"] = {
		"pitch_deg": -rng.randf_range(26.0, 32.0), "peak_g": rng.randf_range(3.2, 3.8),
	}
	## Outward now, not inland: act one is three kilometres long with the inversions in it, and at the
	## old eight to fourteen degrees toward the escarpment it arrives at the launch corridor already
	## on the apron — which starts the cliff climb inside the slope it is supposed to be climbing.
	plan["low_heading_deg"] = -rng.randf_range(4.0, 10.0)
	## Three pullouts, two hills: the third pullout is the wave turn's entry. Both are drawn in one
	## paired loop so the two sequences stay in step.
	var low_pullouts := []
	var low_hills := []
	for _i in 3:
		low_pullouts.append({
			"exit_pitch_deg": rng.randf_range(18.0, 24.0), "peak_g": rng.randf_range(2.4, 2.9),
		})
		low_hills.append({"rise": rng.randf_range(12.0, 22.0), "crown_g": -rng.randf_range(0.9, 1.3)})
	plan["low_pullouts"] = low_pullouts
	plan["low_hills"] = low_hills
	plan["wave"] = {
		"rise": rng.randf_range(14.0, 22.0),
		"crown_g": rng.randf_range(0.1, 0.3),
		"peak_bank_deg": rng.randf_range(55.0, 65.0),
		"lateral_g": rng.randf_range(0.5, 0.7),
	}
	## Exactly one cutback per ride, in one of the two places a heading reversal is worth flying:
	## the tail of the low act, or the return run's turnaround. The entry pullout is held to
	## author_cutback's 22° caller contract in both.
	plan["cutback_slot"] = "low" if rng.randf() < 0.5 else "return"
	plan["cutback"] = {
		"exit_pitch_deg": rng.randf_range(20.0, 22.0),
		"pullout_g": rng.randf_range(2.4, 2.8),
		"peak_g": rng.randf_range(2.8, 3.2),
		## Held just past vertical rather than well past it: every degree beyond ninety turns more of
		## the support downward, and the height that costs is the whole of what decides whether the
		## beat fits under the Immelmann it is flown off.
		"peak_bank_deg": rng.randf_range(112.0, 120.0),
	}
	plan["level_g"] = rng.randf_range(2.4, 2.8)
	plan["climb_pitch_deg"] = rng.randf_range(25.0, 27.0)
	## Height the crest stands above the plateau. The rim has to clear both the climb coming up
	## under it and the dive pitching over it, and both of those read the same margin.
	plan["crest_margin"] = rng.randf_range(46.0, 56.0)
	## Where the crest sits relative to the plateau edge. Far enough in that the rim turn still has
	## plateau under it, close enough that the dive's pitch-over is past the face before it drops.
	plan["crest_edge_offset"] = rng.randf_range(6.0, 14.0)
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
	## Apex above the valley the entry pullout was entered from, not the rise handed to author_hill:
	## at 90 m/s the pullout alone climbs a hundred metres, so a rise target says nothing about how
	## tall the structure ends up. The rise is solved from this once the pullout is integrated.
	plan["camelback"] = {
		"exit_pitch_deg": rng.randf_range(58.0, 64.0),
		"peak_g": rng.randf_range(5.4, 5.8),
		"structure": rng.randf_range(245.0, 255.0),
		"crown_g": -rng.randf_range(0.25, 0.35),
		"exit_peak_g": rng.randf_range(4.6, 5.0),
	}
	plan["turnaround_bank_deg"] = rng.randf_range(65.0, 75.0)
	plan["overbank"] = {
		"heading_change_deg": rng.randf_range(80.0, 100.0),
		"bank_deg": rng.randf_range(88.0, 96.0),
		"peak_g": rng.randf_range(2.4, 2.8),
	}
	## One pair. At 80 m/s a pullout and a hill are four hundred metres between them, and the return
	## run has a turnaround, an overbank and a brake run to fit into the same corridor.
	plan["return_pullout"] = {
		"exit_pitch_deg": rng.randf_range(12.0, 18.0), "peak_g": rng.randf_range(3.0, 3.4),
	}
	plan["return_hill"] = {"rise": rng.randf_range(10.0, 18.0), "crown_g": -rng.randf_range(0.5, 0.8)}
	plan["brake_length"] = rng.randf_range(220.0, 280.0)
	plan["approach_lead"] = rng.randf_range(180.0, 220.0)
	## What the assembly is aiming for, in the units the checks read. Written here rather than
	## measured afterwards so a failure reads as a miss against an intention, not as a moved band.
	plan["expectations"] = {
		"camelback_structure": plan.camelback.structure,
		"immelmann_apex": [88.0, 118.0],
		"loop_height": [LOOP_BAND.x, LOOP_BAND.y],
		"dive_steepest_pitch_deg": -88.0,
		"cutback_slot": plan.cutback_slot,
	}
	return plan


## ---------------------------------------------------------------------------------- story slots


static func _station_and_lift(
	plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	## The lift is sized by the crest it has to reach at the grade it is allowed to hold, the same
	## way the cliff climb is: pitch and the ramp's delivery fix the length. It is still a
	## constant-speed lift — it arrives at 41 km/h — but it now arrives a hundred metres up,
	## because that height is what the inversion act on the plain is paid out of.
	var pitch: float = plan.lift_pitch_deg
	var length: float = (plan.lift_crest_height - STATION_HEIGHT) / (
		RAMP_DELIVERY * sin(deg_to_rad(pitch))
	)
	_add(route, state, sections, [
		RideElements.grade_section("Station", 45.0, _flat_pitch(), 12.5, 0, 4.0),
		RideElements.grade_section(
			"LSM1 lift",
			length,
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


## The inversion act, flown on the plain at the speed the opening drop delivers. Each candidate is
## pre-checked against the speed it would actually be entered at — too slow and it stalls at its
## apex, too fast and its authored size implies an apex or a load nothing here can carry — and the
## seeded order rotates past anything that fails. An Immelmann exits directly above its entry
## heading reversed, so the corridor is handed back to the low act, whose first alignment turn is
## what walks the run off its own line: a 180° turn at this speed displaces the track by its own
## diameter, which is the clearance the retrace would otherwise not have.
static func _inversion_act(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	## The act is aimed so that the Immelmann's reversal is the turn the corridor wanted, not a turn
	## to be undone: with one of them in the running order, act one starts pointed away from the
	## escarpment and the half loop is what points it back. Undoing it instead costs a 180° turn at
	## act-one speed — measured, 520 m — and leaves the launch that much further out, which the
	## brake run pays for a second time on the way home.
	_align(layout, route, state, sections, plan.low_heading_deg, plan.climb_bank_deg)
	var placed: Array = []
	var notes: Array = []
	plan["inversion_notes"] = notes
	## Two rounds, because the act is its own speed schedule: a loop entered at the valley is over
	## the envelope and a loop entered off the Immelmann's drop is not, so a candidate the order
	## reaches too early is offered the act again once the elements ahead of it have been flown.
	for _round in 2:
		for kind in plan.inversion_order:
			if placed.has(kind):
				continue
			_settle_to_plain(plan, route, state, sections)
			if not _inversion_feasible(kind, plan, state.speed):
				notes.append("%s not feasible at %.1f m/s" % [kind, state.speed])
				continue
			if not placed.is_empty():
				_align(
					layout, route, state, sections,
					plan.low_heading_deg + plan.dogleg, plan.climb_bank_deg
				)
			match kind:
				"immelmann":
					_add(route, state, sections, RideElements.author_immelmann(route, state, plan.immelmann))
					## The cutback is a descending element — measured, it spends eighty metres
					## reversing at act-one speed — so it is flown here, off the Immelmann's ninety,
					## and nowhere else in act one: over the plain it finishes underground. It also
					## undoes the Immelmann's own reversal, which is a turn the act does not then
					## have to fly.
					if plan.cutback_slot == "low":
						_cutback(layout, plan, route, state, sections, "act one")
				"loop":
					if not _add_if_sound(
						layout, route, state, sections,
						RideElements.author_loop(route, state, {
							"height": _loop_height(plan, state.speed),
							"peak_g": plan.loop.peak_g,
						})
					):
						notes.append("loop rejected by the corridor at %.1f m/s" % state.speed)
						continue
			## An Immelmann exits reversed, and the corridor is walked back here rather than later
			## because here is the slowest the act ever runs: a turn costs v², so the same reversal
			## is half the track before the drop pays the altitude back and twice it afterwards.
			_align(layout, route, state, sections, plan.low_heading_deg, plan.climb_bank_deg)
			notes.append("%s flown" % kind)
			placed.append(kind)
	_settle_to_plain(plan, route, state, sections)


## Give back whatever altitude the act is still holding. A loop returns to the height it left, so
## this is a no-op after one; an Immelmann does not, and the drop that follows it is what hands the
## next inversion the speed its own feasibility check is about to ask for.
static func _settle_to_plain(
	plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	var owed: float = state.position.y - plan.drop_bottom_height
	if owed < 20.0:
		return
	## The crest angle is solved from the height, not chosen. A pushover and the pullout that closes
	## it each spend r·(1 − cos θ), and r is v² over half a g, so a pitch picked flat overshoots by
	## the square of whatever speed it is entered at: measured, a −29° crest at 43 m/s spends 80 m
	## before the fall has started, against fifteen owed.
	var pitch := rad_to_deg(acos(clampf(
		1.0 - owed * RideElements.G0 / (4.0 * state.speed * state.speed), -1.0, 1.0
	)))
	var group: Array = RideElements.author_dive(route, state, {
		"height": owed,
		"max_pitch_deg": -clampf(pitch, 6.0, absf(plan.inversion_exit.pitch_deg)),
		"peak_g": plan.inversion_exit.peak_g,
	})
	## The estimate is a first guess, and the two shaped ends have a floor the fall cannot go under:
	## the train doubles its speed inside the crest, so what the pullout costs is settled after the
	## drop is chosen. A drop that cannot be made small enough is not taken — the act simply carries
	## its altitude into the low run rather than digging the hole the overshoot would.
	if group[0].element.dive_height > owed + 10.0:
		return
	_add(route, state, sections, group)


## A loop is sized by the speed it is entered at, not chosen. Sustained g rides on the ratio
## v²/(g·h) — measured across these seeds, 3.50 reads 5.0 g, 4.07 reads 6.3 and 5.15 reads 8.4 —
## and the duration envelope allows 4.0 over the five seconds a loop holds, so 3.5 is the ceiling.
## Below 2.7 the train has nothing left over the top. Between the two the plan's height stands; the
## same 66 m loop reads a ratio of 3600 at the tunnel's 94 m/s, which is the 31 g that moved the
## inversions into act one in the first place.
static func _loop_height(plan: Dictionary, speed: float) -> float:
	var g: float = RideElements.G0
	var height: float = clampf(
		plan.loop.height, speed * speed / (g * 3.5), speed * speed / (g * 2.7)
	)
	return height if height >= LOOP_BAND.x and height <= LOOP_BAND.y else -1.0


static func _inversion_feasible(kind: String, plan: Dictionary, speed: float) -> bool:
	match kind:
		"immelmann":
			## Apex of a sustained-g half loop, from the three seeds' own measurements rather than
			## the textbook 0.42 v²/g: at 3.6–4.0 g the shape stands 0.038 v². Below the floor the
			## train hangs too slowly to carry the inverted seam; above the ceiling it is the 380 m
			## element the post-tunnel run measured.
			return speed > 34.0 and 0.038 * speed * speed < 130.0
		"loop":
			return _loop_height(plan, speed) > 0.0
	return false


## Terrain-hugging airtime on the plain, aimed at a shallow inland heading so the act arrives at the
## launch corridor without any of its element lengths being chosen for position.
static func _low_act(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	var heading: float = plan.low_heading_deg
	for i in 2:
		_align(layout, route, state, sections, heading, plan.climb_bank_deg)
		_add(route, state, sections, RideElements.author_pullout(route, state, plan.low_pullouts[i]))
		_add(route, state, sections, RideElements.author_hill(route, state, plan.low_hills[i]))
	_align(layout, route, state, sections, heading, plan.climb_bank_deg)
	_add(route, state, sections, RideElements.author_pullout(route, state, plan.low_pullouts[2]))
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
	_level(route, state, sections, plan.level_g)


## The one cutback the ride is allowed. It is entered off a pullout held to author_cutback's 22°
## contract, and it is solved before it is committed: the template's length solve has a second root
## — a giant arc that also sweeps 180° — and the only way to tell the two apart is to read the
## length and the heading its own trial reports. Anything off either measure is skipped rather than
## flown, and the plan records which, so a missing beat reads as a decision instead of a bug.
static func _cutback(
	layout: Dictionary,
	plan: Dictionary,
	route: Dictionary,
	state: Dictionary,
	sections: Array,
	slot: String
) -> bool:
	if state.speed > CUTBACK_MAX_SPEED:
		plan["cutback_note"] = "%s cutback skipped: %.1f m/s entry, cap %.0f" % [
			slot, state.speed, CUTBACK_MAX_SPEED
		]
		return false
	var entry: Array = RideElements.author_pullout(route, state, {
		"exit_pitch_deg": plan.cutback.exit_pitch_deg,
		"peak_g": _peak_for(state.speed, plan.cutback.exit_pitch_deg, plan.cutback.pullout_g),
	})
	var climbing: Dictionary = RideElements._trial(route, state, entry[0])
	var group: Array = RideElements.author_cutback(climbing.route, climbing.state, {
		"heading_change_deg": layout.turn_sign * 180.0,
		"peak_g": plan.cutback.peak_g,
		"peak_bank_deg": plan.cutback.peak_bank_deg,
	})
	var swept: float = absf(group[0].element.heading_change_deg)
	if group[0].length > CUTBACK_MAX_LENGTH or absf(swept - 180.0) > CUTBACK_HEADING_TOLERANCE:
		plan["cutback_note"] = "%s cutback skipped: %.0f m sweeping %.0f°" % [
			slot, group[0].length, swept
		]
		return false
	## The beat owns its own exit. It leaves the train pitched down out of the past-vertical roll, and
	## the pullout that takes that back out is half the height the reversal itself spends — so the
	## headroom it has to be entered with is measured across both, not across the cutback alone.
	var landed: Dictionary = RideElements._trial(climbing.route, climbing.state, group[0])
	var level: Array = RideElements.author_pullout(landed.route, landed.state, {
		"exit_pitch_deg": 0.0,
		"peak_g": _peak_for(
			landed.state.speed, absf(RideElements.exit_pitch_deg(landed.state)), plan.level_g
		),
	})
	var settled: Dictionary = RideElements._trial(landed.route, landed.state, level[0])
	if settled.state.position.y < plan.drop_bottom_height:
		plan["cutback_note"] = "%s cutback skipped: spends %.0f m against %.0f m of headroom" % [
			slot, climbing.state.position.y - settled.state.position.y,
			climbing.state.position.y - plan.drop_bottom_height,
		]
		return false
	_add(route, state, sections, entry)
	_add(route, state, sections, group)
	_add(route, state, sections, level)
	plan["cutback_note"] = "%s cutback flown: %.0f m sweeping %.0f°, spending %.0f m" % [
		slot, group[0].length, swept, climbing.state.position.y - settled.state.position.y
	]
	return true


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
	var length: float = maxf(rise / (CLIMB_DELIVERY * sin(deg_to_rad(pitch))), 100.0)
	var climb_run: float = length * cos(deg_to_rad(pitch))
	## Each align turn moves the train before the next one is aimed, so the aim is re-solved from
	## where it actually is; the residual heading a turn is allowed to leave is then absorbed by
	## the launch, which is the one straight run whose length costs the climb nothing.
	## Tight, because the climb is three quarters of a kilometre long: four degrees of residual
	## heading — the tolerance a corridor turn is normally allowed — walks the crest a hundred metres
	## further inland than it was aimed, and the dive that follows has to pitch over that much
	## plateau before it reaches the lip.
	for step in 4:
		_align(
			layout, route, state, sections,
			_approach_heading(layout, state.position, plan.launch_length + climb_run, target),
			plan.climb_bank_deg,
			4.0 if step == 0 else 1.0
		)
	## The climb is solved before the launch that carries it, not after: the launch is flat, so it
	## changes neither the height the climb starts from nor the heading it leaves on, and a grade
	## section's shape comes from its pitch profile rather than its speed. Solved the other way round
	## the launch is sized against a run the retune then changes, and the crest lands seventy metres
	## inside the aim — which puts the whole clifftop beat, and the dive that follows it, that far
	## back from the lip.
	rise = terrain.relief + plan.crest_margin - state.position.y
	length = maxf(rise / (CLIMB_DELIVERY * sin(deg_to_rad(pitch))), 100.0)
	var climb := _climb_section(plan, length, pitch)
	var trial := _trial_grade(route, state, climb)
	var reached: float = trial.state.position.y - state.position.y
	if absf(reached - rise) > 6.0:
		pitch = rad_to_deg(asin(clampf(sin(deg_to_rad(pitch)) * rise / maxf(reached, 1.0), 0.05, 0.9)))
		climb = _climb_section(plan, length, pitch)
	climb_run = length * cos(deg_to_rad(pitch))
	_add(route, state, sections, [RideElements.grade_section(
		"LSM2 launch",
		_approach_run(layout, state.position, state.tangent, climb_run, target),
		_flat_pitch(),
		plan.launch_exit_speed,
		2
	)])
	_add(route, state, sections, [climb])


static func _climb_section(plan: Dictionary, length: float, pitch: float) -> Dictionary:
	return RideElements.grade_section(
		"LSM2 climb",
		length,
		[
			Vector2(0, 0), Vector2(CLIMB_RAMP, pitch),
			Vector2(1.0 - CLIMB_RAMP, pitch), Vector2(1, 0),
		],
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
	## Two groups on this ride are dives. Only this one is the cliff.
	for section in dive:
		section.element["cliff_dive"] = true
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


## The record chase, on the only stretch fast enough to carry it. The camelback is sized as
## structure and not as rise: at 90 m/s the entry pullout alone climbs a hundred metres before the
## hill has started, so what the ride is judged on is the apex above the valley it left, and the
## rise handed to author_hill is whatever is left of that once the pullout has been integrated.
static func _camelback(
	plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	var target: float = plan.camelback.structure
	if state.speed < sqrt(2.0 * RideElements.G0 * target) + 4.0:
		return
	## The apex is not something author_hill's rise can be asked for. Both halves of the structure
	## are arcs of a radius fixed by the speed and the g they are authored at, so the whole of it is
	## (R + r)·(1 − cos θ) in the entry pitch θ and nothing else: at 60° the crest alone stands
	## 245 m and a 128 m rise request is simply not a shape it has. One trial pins the constant, and
	## the pitch solved from it is exact — this is the entry attitude, not a correction to geometry.
	var pitch: float = plan.camelback.exit_pitch_deg
	var versine: float = 1.0 - cos(deg_to_rad(pitch))
	var measured: float = _camelback_structure(plan, route, state, pitch)
	var last_versine := versine
	var last := measured
	versine = clampf(versine * target / maxf(measured, 1.0), 0.02, 0.9)
	for _pass in 2:
		pitch = rad_to_deg(acos(1.0 - versine))
		measured = _camelback_structure(plan, route, state, pitch)
		if absf(measured - target) < 3.0 or absf(measured - last) < 0.5:
			break
		var step: float = versine + (target - measured) * (versine - last_versine) / (measured - last)
		last_versine = versine
		last = measured
		versine = clampf(step, 0.02, 0.9)
	pitch = rad_to_deg(acos(1.0 - versine))
	var valley: float = state.position.y
	_add(route, state, sections, RideElements.author_pullout(route, state, {
		"exit_pitch_deg": pitch, "peak_g": plan.camelback.peak_g,
	}))
	var hill: Array = RideElements.author_hill(route, state, {
		"rise": maxf(target - (state.position.y - valley), 10.0),
		"crown_g": plan.camelback.crown_g,
	})
	_add(route, state, sections, hill)
	var apex := valley
	for i in range(hill[0].start_index, hill[0].end_index + 1):
		apex = maxf(apex, route.positions[i].y)
	hill[0].element["structure_rise"] = apex - valley
	hill[0].element["structure_target"] = target
	hill[0].element["structure_pitch_deg"] = pitch
	_add(route, state, sections, RideElements.author_pullout(route, state, {
		"exit_pitch_deg": 0.0, "peak_g": plan.camelback.exit_peak_g,
	}))


## Apex above the valley an entry pullout at this pitch would reach, measured off trials rather
## than a formula, because the hill's own two-knob solve is part of the answer.
static func _camelback_structure(
	plan: Dictionary, route: Dictionary, state: Dictionary, pitch: float
) -> float:
	var valley: float = state.position.y
	var first: int = route.positions.size()
	var pullout: Dictionary = RideElements.author_pullout(route, state, {
		"exit_pitch_deg": pitch, "peak_g": plan.camelback.peak_g,
	})[0]
	var crest: Dictionary = RideElements._trial(route, state, pullout)
	var hill: Dictionary = RideElements.author_hill(crest.route, crest.state, {
		"rise": maxf(plan.camelback.structure - (crest.state.position.y - valley), 10.0),
		"crown_g": plan.camelback.crown_g,
	})[0]
	var top: Dictionary = RideElements._trial(crest.route, crest.state, hill)
	var apex := valley
	for i in range(first, top.route.positions.size()):
		apex = maxf(apex, top.route.positions[i].y)
	return apex - valley


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
	## The turnaround is a heading reversal, which is the one thing a cutback is: given the slot it
	## is offered the beat first, and a plain turn takes it only if the cutback will not solve.
	var turned: bool = (
		plan.cutback_slot == "return"
		and _cutback(layout, plan, route, state, sections, "return run")
	)
	if not turned:
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
	## Aimed loosely between the beats and tightly only before the brake run. A correction turn at
	## 84 m/s costs three hundred metres per ten degrees, and ten degrees of heading is something the
	## next aim absorbs for nothing — so the run is pointed roughly home here and squared up later.
	_align(layout, route, state, sections, _aim_heading(layout, state.position, approach), 60.0, 12.0)
	_add(route, state, sections, RideElements.author_pullout(route, state, plan.return_pullout))
	_add(route, state, sections, RideElements.author_hill(route, state, plan.return_hill))
	_level(route, state, sections, plan.level_g)
	## Aimed twice, and tightly: a turn at 75 m/s is hundreds of metres long, so the point it was
	## aimed at has moved a long way behind the train by the time it comes out of the first one — and
	## the brake run that follows is a kilometre and a half of straight track, so four degrees of
	## residual puts its end a hundred metres to one side of the approach. The C4 closure then has to
	## take that out in its own length, which is where the lateral limit goes.
	for _pass in 2:
		_align(layout, route, state, sections, _aim_heading(layout, state.position, approach), 60.0, 1.5)
	## The brake run covers whatever the corridor leaves, less one approach lead, and comes down to
	## station height on the way — a closure that has to shed thirty metres of potential as well as
	## the speed cannot solve its drive and stalls short of the platform. Both ends of the length
	## matter: stopped a kilometre out, the C4 closure — a bezier across the gap, not a solved-length
	## element — grows past its own 8 % budget; run all the way onto the approach point, the same
	## bezier has only the lead left to take out the heading it was handed, and a nine-control curve
	## asked to turn inside its own handles folds into a cusp the lateral limit reads at seven g.
	var brake_length: float = maxf(
		state.position.distance_to(approach) - plan.approach_lead, plan.brake_length
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
## the corridor: this is the inversion act's rotation applied to a single beat, not a correction — the
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
		## A planar element can cross itself: a teardrop loop's ascending and descending legs meet
		## below it whenever the shape is pinched enough, and no authored height separates them.
		## The margin is the route check's own, so a beat is dropped exactly when it would fail there.
		for j in range(first + ((i - first) % 2), i - 20, 2):
			if absf(trial_route.distances[i] - trial_route.distances[j]) <= 30.0:
				continue
			if point.distance_to(trial_route.positions[j]) < 3.0:
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
