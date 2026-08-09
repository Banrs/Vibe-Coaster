class_name RideGenerator
extends RefCounted

## Seed → one ride, in one pass. Every random number is drawn up front, in a fixed order, into a
## plan dictionary; assembly afterwards reads only the plan and the live integration state, so the
## same seed replays bit for bit. Layout works in a terrain frame — s measured from the escarpment
## base line toward the plateau, a measured along the cliff — so a whole ride mirrors by flipping
## one basis vector, and every placement question is asked against the wobbled edge distance the
## clearance check itself reads.

const STATION_SPEED := 6.0
const STATION_HEIGHT := 20.0
## Speed the station section hands the entry launch. Everything about that launch's length follows
## from it: a 4 g shot is Δ(v²)/(2·4g) metres of plateau plus what its own ramps and grade cost.
const STATION_EXIT_SPEED := 8.0
## The ride has three powered zones and they are not the same machine. Zone one is the entry
## launch: a compressed-gas shot off the platform, the ride's hardest hit and the only thing on it
## that is not an LSM — the class Do-Dodonpa measures at 3.2–3.8 g, with the near-future credit on
## top. Zones two and three are LSM boosters, and an LSM is a 2 g machine: the reference's own two
## launches peak at 0.96 and 1.78 g, and near-future stator gets that to about two. So the record
## launch in the tunnel is a 2 g booster and it is short anyway, because the cliff has already done
## the work — a 300 m dive arrives at seventy-seven metres a second and the last twenty to the
## record costs eighty-five metres of stator.
const ENTRY_LAUNCH_G := 4.0
## How much of the opener's climb pitch the entry launch ends already holding. A launch does not
## have to be flat — the reference's first launch pulls 1.98 g of vertical mid-boost as it runs onto
## the opener's climb — and blending is what stops the climb from opening with a five-g corner at
## fifty metres a second: the pitch-up is spent where the train is still slow instead.
const LAUNCH_BLEND := 0.25
## The same for the cliff booster, and steeper: the escarpment's apron rises under the launch track,
## so a booster that ends shallower than the apron runs into it. Blended this far it leaves the base
## already climbing across the slope — and it pulls three g of vertical doing it, which is what the
## reference's own second launch measures at 2.96.
const CLIFF_BLEND := 0.55
## Longest a booster is allowed to be. Past this it is not a booster, it is a powered straight.
const LSM_MAX_LENGTH := 200.0
## Onset a booster may engage its thrust at, inside the envelope's 25 g/s. This is the number that
## decides how hard a launch may hit: a quintic engagement peaks at 1.875× its own mean slope, so a
## booster holding G at v metres a second needs 1.875·G·v/budget metres of stator before the
## plateau. Read as a fraction of section length instead — which is what the integrator used to do —
## the ramp at the tunnel's seventy-seven metres a second is a fifth of a second and a 4 g launch
## ramps at 67 g/s. Read as a length, the same launch is legal and sixty-odd metres long.
const LSM_ONSET := 20.0
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
## Asymmetric, and it has to be: the coast is entered at eighty-five metres a second and left at
## sixteen, and what a pitch ramp costs in normal g is v² times its curvature. Measured, the old
## seven per cent ramp read 17 g at the base — the ramp in is now a third of the climb, and the ramp
## out, where the train is crawling, stays short so the crest is a crest.
const CLIMB_RAMP_IN := 0.24
const CLIMB_RAMP_OUT := 0.06
const CLIMB_DELIVERY := 0.81
## Most a valley's ground reference may rise across its own look-ahead. Past this the look-ahead has
## stopped reading the plain act one flies over and started reading the escarpment it flies at.
const VALLEY_LOOKAHEAD_RISE := 40.0
## Steepest the opening drop may end up rolled. Past about eighty degrees the frame is on its side
## and the element reads as a barrel roll rather than a banked side-dive, which is a different beat.
const DROP_MAX_BANK := 58.0
## Roll rate a turn is allowed to ask for, inside the 120°/s limit with the margin the measured
## rate needs — `_correct_roll` rescales the amplitude against the bank it actually reaches, so the
## flown rate lands a little either side of this. It is also the ride's main length lever: bank·tan
## (bank) rides on it linearly, and the raceway arc at eighty-five metres a second is the longest
## single piece of track on the ride.
const ROLL_BUDGET := 96.0
## A cutback that solves longer than this, or that misses the reversal by more than this much
## heading, has landed on author_cutback's giant-arc root rather than on the beat that was asked
## for. Its entry speed is capped for the same reason: length grows as v², and past the cap the
## reversal is a kilometre of track no corridor here has room for.
const CUTBACK_MAX_LENGTH := 500.0
const CUTBACK_HEADING_TOLERANCE := 12.0
const CUTBACK_MAX_SPEED := 46.0
## How tall a loop this ride is willing to call a loop. Outside it the shape is out of scale for the
## beat, and the act rotates past it rather than flying something else under its name. The band is
## the ladder's, not the old provisional one: act one is entered forty-odd metres a second now, and
## a loop sized off that speed at the 3.5 g ceiling lands here.
const LOOP_BAND := Vector2(55.0, 84.0)
## The one sweep act one is allowed. Below this much heading it is not a gesture, it is a kink, and
## the act simply arrives at the cliff a few degrees off — which the launch corridor absorbs by
## trading booster length against climb grade rather than by turning. Forced long, because a sweep
## is the arc between two beats and not a correction: bank comes off until the arc is this long.
const ACT_SWEEP_MIN_DEG := 25.0
const ACT_SWEEP_MIN_LENGTH := 160.0
## The run home is one rotation, not a turn and then some turns. The raceway arc is solved for the
## heading the whole gesture — arc, marquee, hills — has to end on, so only a real miss is corrected.
const RETURN_AIM_TOLERANCE := 15.0
## Past this the aim point is behind the train, and a turn to it is not a square-up but a second
## reversal at eighty metres a second. The closure takes it instead.
const RETURN_AIM_LIMIT := 60.0
## Speed a pullout-and-hill pair covers per second of the run home, used to aim the arc past beats
## that have not been solved yet. Measured across these seeds at eighty-odd metres a second.
const RETURN_PAIR_SECONDS := 4.6
## Ground the camelback covers, as a fraction of v². Both of its arcs are radii fixed by the speed
## and the g they are authored at, so the whole structure scales that way and nothing else.
const CAMELBACK_REACH := 0.112
## What the run home is flown at relative to the tunnel's record, once the camelback has been paid
## for. The corridor solve needs a speed before there is one to measure.
const RETURN_SPEED_SHARE := 0.9
## Headings the marquee corridor may be aimed on, measured in the terrain frame. Turned further back
## than this it runs along the apron rather than out over the plain; turned less, the second act flies
## out and back down one line and the run home has a kilometre of nothing in it.
const CORRIDOR_BAND := Vector2(-165.0, -25.0)
## Bank the raceway arc may be flown at. The low end is a floor, not a preference: the corridor
## search will happily buy closure with a looser arc, and at eighty-five metres a second every ten
## degrees of bank it gives away is half a kilometre of track. The high end is what the envelope
## allows a short one: 1/cos(78°) is 4.8 g against the 5.3 allowed over three seconds.
## `_duration_bank` is what decides where inside the band a given arc actually lands, because the
## hold and the radius set each other.
const RETURN_BANK_BAND := Vector2(62.0, 78.0)
## What dropping a speed hill off the run home is worth in metres of closure miss. Below this the
## beat stays and the brake run takes the difference.
const RETURN_PAIR_PENALTY := 120.0
## What a metre of raceway arc is worth against a metre the run home came home short by. A shortfall
## is a cusp and banked track at eighty-five metres a second is the most expensive thing the ride
## builds, so the arc is worth a third of the shortfall — pushed nearer parity the search starts
## buying tighter reversals with shortfalls, which is the one trade that has no recovery.
const RETURN_ARC_COST := 0.3
## What a metre of surplus corridor is worth against a metre the run home came home short by. Cheap,
## because a surplus is flown as brake run: straight, and it is the only thing on the ride that can
## give the height back before the closure has to.
const RETURN_SURPLUS_COST := 0.15
## A metre of sideways miss costs more than a metre short: the brake run absorbs the one and the C4
## closure has to turn out the other, and a bezier asked to turn inside its own handles cusps.
const RETURN_ASIDE_COST := 2.5
## Slack the corridor search leaves on top of the brake run. The model behind it is arcs and straight
## runs and it lands within a couple of hundred metres — fine to be long by, fatal to be short by,
## because short means the brake run is driven past the station. Small, because the brake run now
## covers whatever the model was long by: the slack is track the ride has to fly either way, and it
## used to be flown at six metres a second as closure rather than as brake run.
const CLOSURE_MARGIN := 80.0
## Corridor the C4 closure needs per degree of heading it has to take out, on top of the station
## approach itself. A nine-control bezier turns inside its own handles, and the handles are a fixed
## fraction of the gap — so the gap is what decides whether ninety degrees comes out as an arc or as
## a cusp. Measured: under about two metres a degree it folds.
const CLOSURE_TURN_COST := 2.2
## Neither marquee shape lays down the arc its authored load implies — both are shorter, because
## both spend part of their length rolling. Measured across these seeds, by this much.
const MARQUEE_TIGHTNESS := 1.4
## Where the marquee corridor starts, relative to the station: the opener's ground run laid down on
## the station's own bearing, plus a fixed reach in act one's frame for everything from the crest
## turn to the tunnel mouth. Measured across these seeds — act one, the launch corridor, the plateau
## beat and the dive are one rigid shape once the heading act one runs on is known.
## Ground the marquee beat covers. Both shapes are of the same order at this speed.
## Corridor a marquee beat has to leave behind it: enough for a brake run at eighty-five metres a
## second plus the station approach. Short of this the brake run cannot shed the speed and the
## closure inherits it, and a bezier asked to turn at speed folds into a cusp.
const CLOSURE_FLOOR := 260.0
## Deepest the brake run's own entry crest may unload the train. Everything about the grade follows
## from it: what that crest costs is Δθ·v² over the length it is ramped across, and the brake run is
## entered at eighty metres a second, so a fifth of grade ramped symmetrically reads −4.8 g of
## ejector where a brake run should read one. The grade itself is then solved per brake run rather
## than capped by a constant — and it matters that it can be steep, because the height the run home
## is still carrying is the brake run's to give back and whatever it cannot the closure has to,
## while a closure at station speed cannot absorb any of it without stalling.
const BRAKE_CREST_G := -0.6
## Brake run a metre of carried height costs, at the grade the crest rule above allows and the two
## thirds of it the profile's ramps deliver. Measured across these seeds.
const BRAKE_RUN_PER_METRE := 4.5
const MARQUEE_REACH := 320.0
const OPENER_REACH := 280.0
const ACT_REACH := 1070.0
const ACT_SIDE := 170.0
## How much longer a real banked turn is than the arc its held bank implies. Measured.
const TURN_ARC_FACTOR := 1.5
## Drag an unpowered climb spends, in v² per metre of track. Measured over the cliff climb, where
## the train crosses it at fifty to eighty metres a second; the opener's is smaller and the single
## deterministic re-check each climb runs takes the difference out.
const CLIMB_DRAG := 0.42
## What the opener spends between the booster's exit and the bottom of the twisted drop, in v².
## Measured across these seeds; the drop's own solve then lands the valley height exactly, so an
## error here shows up only as a fraction of a metre a second on the speed act one is entered at.
const OPENER_DRAG := 120.0

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
		"slots": ["low", "return"],
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
		"slots": ["cliff", "payback"],
	},
	## The grammar between the beats. Nothing selects these — a template emits them to hand the next
	## element the attitude it needs — but they are flown, so they are listed: the check is that
	## every kind on the built ride is a kind this table knows.
	"pushover": {
		"size_class": "grammar",
		"signature": "crest onto free-fall support",
		"slots": ["any"],
	},
	"fall": {
		"size_class": "grammar",
		"signature": "straight held attitude",
		"slots": ["any"],
	},
	"pullout": {
		"size_class": "grammar",
		"signature": "sustained-g arc to an attitude",
		"slots": ["any"],
	},
}


## ------------------------------------------------------------------------------------ top level


static func build(seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var terrain: Dictionary = RideTerrain.generate(rng)
	var plan := _plan(rng)
	var layout := _layout(terrain, plan.mirror)
	_bearing(layout, plan)
	var station_position := _world(layout, plan.station_s, plan.station_a, STATION_HEIGHT)
	var station_tangent := _direction(layout, plan.start_bearing_deg)
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
	_station_and_boost(plan, route, state, sections)
	_opening_drop(layout, plan, route, state, sections)
	_mark(sections, "opener")
	_act_one(layout, plan, route, state, sections)
	_mark(sections, "act one")
	_cliff_launch(layout, plan, route, state, sections)
	_mark(sections, "LSM2 + cliff climb")
	_clifftop(layout, plan, route, state, sections)
	_mark(sections, "clifftop")
	_dive_and_tunnel(layout, plan, route, state, sections, tunnel)
	_mark(sections, "dive + LSM3")
	_camelback(layout, plan, route, state, sections, station_position, station_tangent)
	_mark(sections, "camelback")
	_return_run(layout, plan, route, state, sections, station_position, station_tangent)
	RideElements.append_closure(route, state, sections, station_position, station_tangent, STATION_SPEED)
	_mark(sections, "run home")
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
	plan["station_s"] = -rng.randf_range(780.0, 880.0)
	plan["station_a"] = -rng.randf_range(60.0, 120.0)
	## How far off the reverse of act one's own heading the station is aimed. The ride marches better
	## than a kilometre along the escarpment through act one and walks it back through the second, so
	## the run home arrives on roughly the line act one left on, reversed — but not exactly on it: the
	## second act also crosses a kilometre of plain outward, and the yaw is what leans the run home
	## back in against that. It costs nothing, because the turn that pays for it is at the crest.
	plan["station_yaw_deg"] = -rng.randf_range(30.0, 55.0)
	## The opener is a booster and then a coast, not a lift. The booster is 2 g of flat track and the
	## climb over it is unpowered, so the crest speed is what the ride paid for and the crest height
	## is solved from it — the same way the cliff climb is solved, one gesture later and one act
	## smaller. Nothing here is a chosen length.
	plan["opening_climb_pitch_deg"] = rng.randf_range(21.0, 25.0)
	## The crest is ridden over, not crawled over. Measured on the reference, the opener's crest is
	## an airtime crest at speed — and the ejector the drop behind it is famous for is only available
	## at speed: an airtime crest holding −0.7 g has radius v²/1.7g, so at sixteen metres a second the
	## whole twisted drop is a fifteen-metre stub and at twenty-three it is a beat.
	plan["opening_crest_speed"] = rng.randf_range(26.0, 29.0)
	## Speed act one is entered at, and the whole reason the opener exists. Both inversions are sized
	## off it: below about 44 m/s the Immelmann's apex falls out of the record class it is chasing,
	## above about 48 the loop's own 3.5 g ceiling puts it out of scale. So the booster's exit speed
	## is derived from this rather than drawn, and the crest height follows from the booster.
	## Both inversions are sized off it and both are flown harder now: an Immelmann's apex goes as
	## v²/(n+1), so the act is entered faster to keep the tallest inversion in its 75–95 m class while
	## it holds the four-odd g its measured counterpart does.
	plan["act_entry_speed"] = rng.randf_range(48.5, 50.0)
	plan["drop_bottom_height"] = rng.randf_range(32.0, 40.0)
	plan["drop_pitch_deg"] = -rng.randf_range(54.0, 60.0)
	plan["drop_bank_deg"] = rng.randf_range(40.0, 48.0)
	plan["drop_lateral_g"] = rng.randf_range(0.35, 0.5)
	## The ride's lateral signature, and the one place it is loud: the reference measures +1.64 g
	## snapping to −1.35 g across the roll, half a second apart, over a floor of a few tenths. Scaled
	## on the value with the hold kept, that is this pair of brief pulses — the base lobe above is
	## what still carries the drift inland, and these are the snap that sits on top of it.
	plan["drop_snap_g"] = rng.randf_range(2.1, 2.6)
	## Ejector over the crest, the deepest on the ride. Held any deeper than this and the crest radius
	## v²/(1+|g|)g turns the whole drop into a sub-30 m stub at the speed the opener crests at.
	plan["drop_hold_g"] = -rng.randf_range(0.70, 1.00)
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
	## Measured on the inversion reference: 4.34–4.43 g peak with ≥3 g held 2.5–2.7 s. Scaled on the
	## value with the hold kept, the half loop holds this and the front lobe brief-peaks above it.
	## The reference's inversion pair stands loop = 0.82 × Immelmann, and both are sized off the same
	## act-one speed here: an Immelmann's apex goes as v²/(n+1) and a teardrop loop's height times its
	## lobe is 0.165 v², so the ratio between them is bought entirely with the g each one holds. This
	## is the Immelmann's side of that — held a little lower than the loop's lobe, which is what makes
	## it the taller of the two and the tallest-inversion chase.
	plan["immelmann"] = {"peak_g": rng.randf_range(3.95, 4.20), "entry_lobe": 1.10}
	## lateral_g is what stops the two legs crossing: threaded through the shape it walks the exit leg
	## off the entry leg, which is the offset a real loop's legs are built with. The amplitude is set
	## by what the clearance check reads — measured, leg separation runs about 13 m per g of it, so
	## this band is the four metres the corridor wants with margin to spare.
	plan["loop"] = {
		"height": rng.randf_range(60.0, 80.0),
		"peak_g": rng.randf_range(5.4, 5.8),
		"lateral_g": rng.randf_range(0.50, 0.65),
	}
	## An Immelmann is half a loop: it exits level but ninety metres up and twenty metres a second
	## slower, and nothing downstream of it works from there. The act gives that altitude back as a
	## drop, which is also what puts the airtime hills back at the speed they are sized for. The
	## crest is shallow because a pushover's arc grows as v² and the train doubles its speed inside
	## one: measured, a −54° crest at 30 m/s spends 190 m of height before the fall has started,
	## which is more than twice what the Immelmann borrowed.
	plan["inversion_exit"] = {
		"pitch_deg": -rng.randf_range(26.0, 32.0), "peak_g": rng.randf_range(3.2, 3.8),
	}
	## Three pullouts, two hills: the third pullout is the wave turn's entry. Both are drawn in one
	## paired loop so the two sequences stay in step.
	var low_pullouts := []
	var low_hills := []
	for _i in 3:
		low_pullouts.append({
			"exit_pitch_deg": rng.randf_range(18.0, 24.0), "peak_g": rng.randf_range(2.9, 3.6),
		})
		low_hills.append({"rise": rng.randf_range(12.0, 22.0), "crown_g": -rng.randf_range(0.6, 1.1)})
	plan["low_pullouts"] = low_pullouts
	plan["low_hills"] = low_hills
	## The wave turn carries the largest single share of act one's heading budget: it is the beat that
	## points the run at the escarpment, so its sweep is a target and its lateral load is solved to
	## reach it. Sign comes from the budget, not from the draw.
	plan["wave"] = {
		"rise": rng.randf_range(14.0, 22.0),
		## Unloaded on edge, which is the reference's own airtime-hill signature: −0.73 g while the
		## angle channel reads 66–88° of bank. Scaled, an ejector crest flown at sixty degrees of it.
		"crown_g": -rng.randf_range(0.3, 0.8),
		"peak_bank_deg": rng.randf_range(55.0, 65.0),
		"lateral_g": rng.randf_range(0.6, 0.9),
		"sweep_deg": rng.randf_range(40.0, 65.0),
	}
	## Exactly one cutback per ride, and act one is the only place it can be flown: the beat's length
	## grows as v², and measured, past about 46 m/s the reversal is a kilometre of track no corridor
	## here has room for. The run home is flown at eighty-five, so the slot the old plan offered it
	## there was one the physics never once accepted.
	plan["cutback_slot"] = "low"
	plan["cutback"] = {
		"exit_pitch_deg": rng.randf_range(13.0, 17.0),
		"pullout_g": rng.randf_range(2.4, 2.8),
		## Measured 4.20 g with ≥2 g held 1.76 s and ≥3 g 0.96 s — the shortest of the big elements
		## and the hardest for its length. Scaled on the value, the hump peaks here.
		"peak_g": rng.randf_range(5.0, 5.5),
		## Held just past vertical rather than well past it: every degree beyond ninety turns more of
		## the support downward, and the height that costs is the whole of what decides whether the
		## beat fits under the Immelmann it is flown off.
		"peak_bank_deg": rng.randf_range(112.0, 120.0),
	}
	plan["level_g"] = rng.randf_range(2.4, 2.8)
	## Heading act one has to arrive on, and the bank the one sweep it is allowed may use.
	## Steep, and that is a layout decision rather than a comfort one: the launch corridor is the one
	## stretch that can walk back the kilometre and a half act one marches along the escarpment, and
	## it only walks it back if it climbs across the face rather than along it.
	plan["climb_aim_deg"] = rng.randf_range(68.0, 82.0)
	plan["act_sweep_bank_deg"] = rng.randf_range(45.0, 60.0)
	## Height the crest stands above the plateau. The rim has to clear both the climb coming up
	## under it and the dive pitching over it, and both of those read the same margin.
	plan["crest_margin"] = rng.randf_range(54.0, 64.0)
	## Where the crest sits relative to the top of the face, and it is OUTBOARD of it — the crest is
	## carried over the face on structure. Measured: the plateau beat drifts fifty-odd metres inland
	## across its own turns, so the rim turn still has plateau under it, and the dive's pitch-over then
	## has to spend its own reach getting back out. Sited at the rim instead, the pitch-over ends
	## inland of the lip and the fall behind it drops into the plateau rather than down the face.
	plan["crest_edge_offset"] = -rng.randf_range(40.0, 70.0)
	## Shallow, and that is a clearance decision rather than a comfort one: this is the bank the
	## traverse back along the rim is flown at, and its radius is what displaces the clifftop — and
	## with it the whole dive — along the cliff from the line the climb came up on. Measured, the two
	## share the apron at the base of the face, and at fifty-five degrees they pass inside two metres.
	plan["climb_bank_deg"] = rng.randf_range(26.0, 36.0)
	## LSM2 is a booster at the base and then three hundred metres of unpowered climb. The g the
	## booster holds is the plan value; its length is Δ(v²)/(2·g) against the speed the climb needs,
	## flexed inside a quarter either way so the crest still lands where the rim wants it.
	plan["lsm2_g"] = rng.randf_range(1.9, 2.1)
	## Speed the clifftop beat is ridden at, and the climb is sized to deliver it. The suspense and the
	## rim turn are flown on it before anything slows down — which is the order the reference runs in:
	## climb, then twenty-odd seconds of upper-cliff turns and hills AT SPEED, and only then the slow
	## beat. Below about fifteen a plateau-scale element is a dozen samples long; above about
	## twenty-two the outward-banked rim turn wants more plateau than there is.
	plan["climb_exit_speed"] = rng.randf_range(19.0, 22.0)
	## The one deliberate slow beat, and it sits at the END of the clifftop rather than the middle of
	## it: the brake bites after the suspense, the hold is a dozen seconds of dead-level track, and the
	## dive pitches over off the end of it. There is no release beat at all — the ride never
	## re-accelerates up here, which is what the twelve seconds the reference measures actually is.
	plan["hold_brake_length"] = rng.randf_range(26.0, 36.0)
	## Speed the crawl holds, and it is a crawl rather than a stop. A pitch-over's radius is v²/0.85g,
	## so the lip is a nine-metre arc at this speed and a half-metre one at walking pace — and half a
	## metre is smaller than the integrator's own sample spacing. This is the slowest the dive can be
	## entered from and still be a curve rather than a corner.
	plan["crest_hold_speed"] = rng.randf_range(15.0, 18.0)
	## Twelve seconds of it, measured the way the reference's is: length over the speed above.
	plan["crest_hold_seconds"] = rng.randf_range(11.0, 14.0)
	## The clifftop crest is a pullout up and a pushover back down, not an authored airtime hill: at
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
	## Measured cliff-dive pullout: 2.04–2.99 g with 1.58 s ≥2 g. Scaled on the value, this — the
	## near-free-fall down the face above it is already right and is not touched.
	plan["dive_peak_g"] = rng.randf_range(3.6, 4.4)
	plan["dive_pitch_deg"] = -90.0
	## How much support the pitch-over holds as it goes over the lip, and it is generous rather than
	## the default because of what is behind it: the dive is entered off the crawl now, and a
	## pitch-over's radius is v²/(1−edge)g, so at crawl speed the default reads a nine-metre lip that
	## the rear car takes at eight g and that reaches barely thirty metres out past the rim. Held
	## here the lip is a sixty-metre arc, the train rolls over it, and the fall behind it lands clear
	## of the face rather than in it. The floor further down is untouched — it still goes vertical.
	plan["dive_edge_g"] = rng.randf_range(0.28, 0.38)
	## The record launch, and an LSM rather than the entry launch's gas shot, so it is a 2 g machine.
	## The cliff hands the tunnel seventy-seven metres a second, so the last twenty to the record is
	## Δ(v²) ≈ 3350 — eighty-five metres of stator at 2 g, still shorter than the reference's own
	## booster sections. The engagement at each end is a length sized off the onset limit rather than
	## a fraction of the section, which is what used to turn this into a 1.2 g mean over 120 m.
	plan["lsm3_g"] = rng.randf_range(1.9, 2.1)
	plan["tunnel_exit_speed"] = rng.randf_range(93.5, 94.8)
	## The record launch sits on the descent, not on a flat. The reference's tunnel launch is on the
	## falling tail of the cliff drop's pullout, so the dive is told to exit nose-down at this grade
	## and the booster rides it out to level — the same blend the cliff booster uses, mirrored. Flat
	## track between a 90° drop and a launch is a beat the real ride does not have.
	plan["tunnel_grade_deg"] = rng.randf_range(6.0, 9.0)
	## Where the dive's pullout stops, measured before the tunnel: the booster holds the falling grade
	## and the pullout out of the tunnel mouth takes it back to level, so the marquee corridor starts
	## some thirty metres under this. The whole return run sits on that number — a past-vertical
	## overbank at 85 m/s drops thirty metres by construction — so the dive stops this high.
	plan["tunnel_end_height"] = rng.randf_range(58.0, 66.0)
	## The marquee corridor turns off the dive's line as soon as the tunnel ends. Run straight out,
	## the camelback and the run home are the same corridor twice — the return leg retraces the
	## outbound one and the whole second act reads as one line. Doglegged, the camelback runs
	## diagonally across the plain and the run home comes back on the offset line beside it. The sign
	## is fixed in the terrain frame, which is what makes the seed mirror flip it.
	plan["post_tunnel_dogleg"] = rng.randf_range(22.0, 32.0)
	## Apex above the valley the entry pullout was entered from, not the rise handed to author_hill:
	## at 90 m/s the pullout alone climbs a hundred metres, so a rise target says nothing about how
	## tall the structure ends up. The rise is solved from this once the pullout is integrated.
	## Measured: 3.32 s ≥2 g into a 3.89 g peak, then 6.8 s essentially unloaded over the crest,
	## then 2.32 s ≥2 g out. Scaled on the value with the holds kept — and the crest is deep rather
	## than shallow, which is also what makes the structure narrow: a float crest's radius is
	## v²/(1+|crown|)g, and that radius is most of what sets the flank angle.
	plan["camelback"] = {
		"exit_pitch_deg": rng.randf_range(58.0, 64.0),
		"peak_g": rng.randf_range(5.0, 5.4),
		"structure": rng.randf_range(245.0, 255.0),
		## Deep, and that is the measurement rather than a taste: the reference's crest bottoms at
		## −0.87 g with 2.8 s below zero, which scaled on the value is −1.3, and the stretched envelope
		## allows −1.65 sustained. It is also what makes the structure a parabola rather than a table —
		## a float crest's radius is v²/(1+|crown|)g, and that radius is most of what sets the flank.
		"crown_g": -rng.randf_range(0.90, 1.15),
		"exit_peak_g": rng.randf_range(4.0, 4.6),
	}
	plan["turnaround_bank_deg"] = rng.randf_range(60.0, 68.0)
	## One marquee beat opens the run home, and which one is the seed's. Both parameter sets are
	## drawn either way so the branch cannot shift the stream.
	plan["return_marquee"] = "overbank" if rng.randf() < 0.5 else "wave_turn"
	plan["overbank"] = {
		"heading_change_deg": rng.randf_range(60.0, 85.0),
		"bank_deg": rng.randf_range(88.0, 96.0),
		"peak_g": rng.randf_range(2.4, 2.8),
	}
	plan["return_wave_entry"] = {
		"exit_pitch_deg": rng.randf_range(14.0, 18.0), "peak_g": rng.randf_range(3.0, 3.4),
	}
	plan["return_wave"] = {
		"rise": rng.randf_range(14.0, 22.0),
		"crown_g": rng.randf_range(0.1, 0.3),
		"peak_bank_deg": rng.randf_range(45.0, 55.0),
		"lateral_g": rng.randf_range(0.5, 0.7),
	}
	## Two pairs. The run home was a marquee beat and then two and a half kilometres of nothing —
	## a pacing failure, not a length saving. The length comes back off the post-tunnel dogleg and
	## the shorter act one, so the beats stay.
	var return_pullouts := []
	var return_hills := []
	for _i in 2:
		return_pullouts.append({
			"exit_pitch_deg": rng.randf_range(12.0, 18.0), "peak_g": rng.randf_range(3.0, 3.4),
		})
		return_hills.append({
			"rise": rng.randf_range(10.0, 18.0), "crown_g": -rng.randf_range(0.5, 0.8),
		})
	plan["return_pullouts"] = return_pullouts
	plan["return_hills"] = return_hills
	plan["brake_length"] = rng.randf_range(200.0, 260.0)
	## How much track is left for the C4 closure, and it is a station approach rather than a corridor.
	## The closure is the one element on the ride whose length is not solved — it is a bezier across
	## whatever gap is left — so left to absorb the residual geometry it becomes four hundred metres
	## of six-metres-a-second nothing, which is over a minute of ride time and most of what drags the
	## elapsed average down. The brake run is driven all the way onto the approach point instead, and
	## this is what remains: the reference's own station approach is of this order.
	plan["approach_lead"] = rng.randf_range(110.0, 150.0)
	## What the assembly is aiming for, in the units the checks read. Written here rather than
	## measured afterwards so a failure reads as a miss against an intention, not as a moved band.
	plan["expectations"] = {
		"camelback_structure": plan.camelback.structure,
		"route_length": [6400.0, 7600.0],
		"immelmann_apex": [75.0, 95.0],
		"loop_height": [LOOP_BAND.x, LOOP_BAND.y],
		"loop_leg_separation": 4.0,
		"dive_steepest_pitch_deg": -88.0,
		"cutback_slot": plan.cutback_slot,
	}
	return plan


## ---------------------------------------------------------------------------------- story slots


## The two headings the whole layout hangs off, measured before anything is integrated. A twisted
## drop sweeps the same arc at any speed — its length and its curvature both scale as v², so the
## angle between them does not — which makes the heading act one will inherit knowable in advance.
## Act one's own heading is fixed by what has to happen at the end of it: the wave turn is the beat
## that points the run at the escarpment, so the act runs on the climb's aim less the wave's sweep,
## less the reversals its inversions supply. The station is then aimed at the reverse of that,
## because that is the line the run home comes back on.
static func _bearing(layout: Dictionary, plan: Dictionary) -> void:
	var probe_state := {
		"position": Vector3.ZERO,
		"tangent": Vector3.FORWARD,
		"up": Vector3.UP,
		"speed": plan.opening_crest_speed,
		"distance": 0.0,
		"time": 0.0,
	}
	var probe_route: Dictionary = RideElements.new_route()
	RideElements.append_state(probe_route, probe_state, 0, 1.0, 0.0, 0.0, 0, Vector3.ZERO)
	var probe: Array = _twisted_drop(layout, plan, probe_route, probe_state)
	var reversals := 2.0 if plan.cutback_slot == "low" else 1.0
	plan["drop_sweep_deg"] = layout.turn_sign * probe[0].element.heading_change_deg
	plan["act_heading_deg"] = _wrap(
		plan.climb_aim_deg - plan.wave.sweep_deg - 180.0 * reversals
	)
	plan["crest_heading_deg"] = _wrap(plan.act_heading_deg - plan.drop_sweep_deg)
	## Which way the station points, searched rather than drawn. Everything from the crest turn to the
	## tunnel mouth is rigid in act one's own frame — the terrain only anchors how far in it sits —
	## so where the marquee corridor starts can be dead-reckoned off the station before a metre of it
	## is integrated, and the bearing that makes the circuit close is the one the same analytic model
	## of the run home says leaves a brake run's length and nothing to one side. The drawn yaw only
	## picks where the search starts, so a seed still owns its answer.
	var station: Vector3 = _world(layout, plan.station_s, plan.station_a, STATION_HEIGHT)
	var best := INF
	var bearing: float = _wrap(plan.act_heading_deg + 180.0 + plan.station_yaw_deg)
	for step in 37:
		var home: float = bearing + lerpf(-90.0, 90.0, step / 36.0)
		var origin: Vector3 = (
			station
			+ _direction(layout, home) * OPENER_REACH
			+ _direction(layout, plan.act_heading_deg) * ACT_REACH
			+ _direction(layout, plan.act_heading_deg + 90.0) * ACT_SIDE
		)
		var trial: Dictionary = _corridor_search(
			layout,
			plan,
			origin,
			-90.0,
			plan.tunnel_exit_speed,
			station - _direction(layout, home) * plan.approach_lead,
			home
		)
		if trial.error < best:
			best = trial.error
			plan["start_bearing_deg"] = _wrap(home)
	plan["bearing_note"] = "station aimed %.0f°, %.0f° off the reverse of act one" % [
		plan.start_bearing_deg,
		_wrap(plan.start_bearing_deg - plan.act_heading_deg - 180.0),
	]


## Station, the first booster, and the coast over the opener's crest. The booster is 2 g of flat
## track — its length is Δ(v²)/(2·2g) and nothing else — and the climb behind it is unpowered, so
## the crest speed is what the booster paid for. Height is therefore solved, not chosen: the crest
## stands wherever a coast from the booster's exit speed runs out at the speed the drop wants.
static func _station_and_boost(
	plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	## Exit speed the booster has to reach so that the drop off the crest hands act one the speed the
	## two inversions are both in scale at. Energy from the booster's exit at station height to the
	## valley at drop_bottom_height, plus what drag spends on the way over.
	var exit_speed: float = sqrt(maxf(
		plan.act_entry_speed * plan.act_entry_speed
		+ 2.0 * RideElements.G0 * (plan.drop_bottom_height - STATION_HEIGHT)
		+ OPENER_DRAG,
		STATION_EXIT_SPEED * STATION_EXIT_SPEED + 100.0
	))
	plan["launch_speed"] = exit_speed
	var pitch: float = plan.opening_climb_pitch_deg
	var blend: float = pitch * LAUNCH_BLEND
	var ramp: Vector2 = _lsm_ramp(ENTRY_LAUNCH_G, STATION_EXIT_SPEED, exit_speed)
	## The launch climbs while it accelerates, and the height it gains is stator it has to pay for:
	## the pitch ramps across the whole section, so it averages half the blend and the extra length
	## closes in one line rather than a loop.
	var boost_length: float = (
		_lsm_length(ENTRY_LAUNCH_G, STATION_EXIT_SPEED, exit_speed, ramp)
		/ (1.0 - 0.5 * sin(deg_to_rad(blend)) / ENTRY_LAUNCH_G)
	)
	plan["launch_note"] = "entry launch %.0f m at %.1f g to %.0f km/h, onto %.0f° of grade" % [
		boost_length, ENTRY_LAUNCH_G, exit_speed * 3.6, blend
	]
	_add(route, state, sections, [
		RideElements.grade_section("Station", 45.0, _flat_pitch(), STATION_EXIT_SPEED, 0, 4.0),
		RideElements.grade_section(
			"Entry launch",
			boost_length,
			[Vector2(0, 0), Vector2(1, blend)],
			exit_speed,
			1,
			4.0,
			{},
			ramp
		),
	])
	var crest: float = plan.opening_crest_speed
	var rise: float = (
		(exit_speed * exit_speed - crest * crest) / (2.0 * RideElements.G0)
		- (state.position.y - STATION_HEIGHT)
	)
	var climb: Dictionary = _coast_climb("Opening climb", rise, pitch, blend)
	## One deterministic re-check, the same shape the cliff climb's is: the coast is integrated, the
	## crest speed read off it, and the height moved by exactly the energy the reading was out by.
	for _pass in 2:
		var trial := _trial_grade(route, state, climb)
		if absf(trial.state.speed - crest) < 0.3:
			break
		rise += (trial.state.speed * trial.state.speed - crest * crest) / (2.0 * RideElements.G0)
		climb = _coast_climb("Opening climb", maxf(rise, 20.0), pitch, blend)
	_add(route, state, sections, [climb])
	plan["crest_height"] = state.position.y
	plan["crest_speed"] = state.speed


## An unpowered grade from the attitude the launch behind it left, up to `pitch`, gaining `rise`.
## The ramp in is long — nearly half the climb — because it is ridden at fifty metres a second and
## what a pitch ramp costs in normal g is v² times its curvature: measured, a fifth of the length
## reads 4.8 g at the base and nearly half reads 2.4. The height that costs is put back by the same
## re-check the crest speed rides on, so the delivery constant is only ever the first guess.
static func _coast_climb(name: String, rise: float, pitch: float, entry_pitch: float) -> Dictionary:
	return RideElements.grade_section(
		name,
		maxf(rise / (RAMP_DELIVERY * sin(deg_to_rad(pitch))), 40.0),
		[Vector2(0, entry_pitch), Vector2(0.45, pitch), Vector2(0.85, pitch), Vector2(1, 0)],
		-1.0,
		0
	)


## Height act one flies its valleys at, measured over the ground under them rather than over the
## datum. The plain is not flat where the escarpment's apron starts, and act one marches better than
## a kilometre toward it: a valley authored as an absolute height clears the plain by twenty-five
## metres at the start of the act and digs into the apron by the end of it. Sampled forward over the
## next eight hundred metres rather than underfoot — that is the whole rhythm section, and it is the
## right window because the run also sags across it: every pullout-and-hill pair leaves the valley a
## few metres lower than it found it, so the beat that digs in is the last one and not the first.
static func _valley_height(layout: Dictionary, plan: Dictionary, state: Dictionary) -> float:
	var forward: Vector3 = _ground(state.tangent)
	var here: float = RideTerrain.height(layout.terrain, state.position.x, state.position.z)
	var ground := here
	for step in range(1, 7):
		var at: Vector3 = state.position + forward * (130.0 * step)
		ground = maxf(ground, RideTerrain.height(layout.terrain, at.x, at.z))
	## Bounded, because the same look-ahead that reads the apron also reads the face behind it: eight
	## hundred metres out from the last beat of act one is the escarpment itself, and a valley told to
	## clear three hundred metres of it is a valley above the crest it is supposed to fall from. What
	## the rhythm section actually needs is the apron's local rise, which is this much.
	return plan.drop_bottom_height + minf(ground, here + VALLEY_LOOKAHEAD_RISE)


## The opening element is a non-inverting banked side-dive; the frame sign carries the seed mirror,
## so it always falls away toward the escarpment and starts the run's drift inland. The twist only
## sets the attitude — it ends on free-fall support, so a straight fall carries the height, and the
## fall is sized by the same fixed point author_dive uses: the pullout's own cost grows with the
## speed the fall delivers, so the drop cannot simply be subtracted.
static func _opening_drop(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	_crest_turn(layout, plan, route, state, sections)
	## The bank is solved against the length the drop comes out at, not drawn flat. The ejector over
	## the crest is what sets that length — a deeper hold is a tighter crest and a shorter element —
	## and the same bank asked for over a shorter element is a faster roll. Measured: at the old
	## sixteen metres a second the drawn bank always fitted; at the speed the crest is ridden now it
	## does not always, and asked for anyway the roll goes past vertical and the drop inverts.
	var group: Array = _twisted_drop(layout, plan, route, state)
	plan["drop_note"] = "twisted drop %.0f m at %.0f° of bank, sweeping %.0f°" % [
		group[0].length, group[0].element.peak_bank_deg, group[0].element.heading_change_deg
	]
	_add(route, state, sections, group)
	var want: float = state.position.y - _valley_height(layout, plan, state)
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


## The opener's own element, solved the same way wherever it is asked for — the bearing probe reads
## the heading it sweeps before anything is integrated, so the two have to be the same element.
static func _twisted_drop(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary
) -> Array:
	var bank: float = plan.drop_bank_deg
	var group: Array = []
	for _pass in 4:
		group = RideElements.author_twisted_drop(route, state, {
			"target_pitch_deg": plan.drop_pitch_deg,
			"peak_bank_deg": -layout.turn_sign * bank,
			"lateral_g": plan.drop_lateral_g,
			"snap_g": plan.drop_snap_g,
			"hold_g": plan.drop_hold_g,
		})
		var peak: float = group[0].element.peak_bank_deg
		var allowed: float = ROLL_BUDGET * 0.16 * group[0].length / state.speed
		if peak <= DROP_MAX_BANK and bank <= allowed:
			break
		## The bank asked for is not the bank reached: a diving turn gains roll from its own path and
		## the lateral snap adds to it, so the element is solved against the bank it measures.
		bank = minf(bank * DROP_MAX_BANK / maxf(peak, 1.0), allowed)
	return group


## The inversion act, flown on the plain at the speed the opening drop delivers. Each candidate is
## pre-checked against the speed it would actually be entered at — too slow and it stalls at its
## apex, too fast and its authored size implies an apex or a load nothing here can carry — and the
## seeded order rotates past anything that fails. An Immelmann exits directly above its entry
## heading reversed, so the corridor is handed back to the low act, whose first alignment turn is
## what walks the run off its own line: a 180° turn at this speed displaces the track by its own
## diameter, which is the clearance the retrace would otherwise not have.
## Act one is one arc, not a chain. Nothing in it is aimed: every beat is entered on the attitude the
## beat in front of it left, the inversions supply their own reversals, and the wave turn — the last
## beat before the escarpment — is solved to whatever heading the run still owes. The station was
## aimed for this, so what is left over at the end is an estimate error rather than a whole turn, and
## it is either one long sweep or nothing at all.
static func _act_one(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	var notes: Array = []
	plan["inversion_notes"] = notes
	plan["act_note"] = "act one entered at %.1f m/s" % state.speed
	for kind in plan.inversion_order:
		_settle_to_plain(layout, plan, route, state, sections)
		if not _inversion_feasible(kind, plan, state.speed):
			notes.append("%s not feasible at %.1f m/s" % [kind, state.speed])
			continue
		match kind:
			"immelmann":
				_add(route, state, sections, RideElements.author_immelmann(route, state, plan.immelmann))
				## The cutback is a descending element — measured, it spends eighty metres reversing
				## at act-one speed — so it is flown here, off the Immelmann's ninety, and nowhere
				## else in act one: over the plain it finishes underground.
				## The reversal is not optional: act one's whole heading budget is written around the
				## two the act supplies, and a missing one is 180° the wave turn cannot absorb. So
				## when the cutback will not clear the track it is flown off, the beat is replaced
				## rather than dropped — the same reversal, flown as a banked arc instead of a roll.
				if plan.cutback_slot == "low" and not _cutback(
					layout, plan, route, state, sections, "act one"
				):
					_flowing_turn(layout, plan, route, state, sections, layout.turn_sign * 180.0)
				notes.append("immelmann flown")
			"loop":
				if _add_if_sound(
					layout, route, state, sections,
					RideElements.author_loop(route, state, {
						"height": _loop_height(plan, state.speed),
						"peak_g": plan.loop.peak_g,
						"lateral_g": layout.turn_sign * plan.loop.lateral_g,
					})
				):
					notes.append("loop flown")
				else:
					notes.append("loop rejected by the corridor at %.1f m/s" % state.speed)
	_settle_to_plain(layout, plan, route, state, sections)
	## The rhythm section, flown straight off the last inversion's exit. Two pullout-and-hill pairs
	## and then the wave turn, which is where the run turns to face the escarpment.
	for i in 2:
		_add(route, state, sections, RideElements.author_pullout(route, state, plan.low_pullouts[i]))
		_add(route, state, sections, RideElements.author_hill(route, state, plan.low_hills[i]))
	_add(route, state, sections, RideElements.author_pullout(route, state, plan.low_pullouts[2]))
	var run: float = _launch_run(layout, plan, state)
	var target: float = (
		layout.terrain.apron_width + layout.terrain.face_width + plan.crest_edge_offset
	)
	_act_wave(layout, plan, route, state, sections, _owed_heading(layout, plan, state, run, target))
	_level(route, state, sections, plan.level_g)
	## Nothing normally reaches this: the lead sweep put act one on the heading its own reversals
	## bring back, and the wave turn is solved for the rest. It fires when an inversion was not flown
	## — a reversal missing is 180° missing — and it says so when it does.
	_act_sweep(layout, plan, route, state, sections, run, target)


## The turn out of the crest, and the only steering act one gets. The opener climbs on the line the
## run home comes back down, so the ride has a hundred and eighty degrees to find between the two —
## and the one place it is cheap is here, at the top, where the train is doing sixteen metres a
## second and a turn's length goes as v². Measured, the same reversal costs eighty metres here and
## seven hundred at the bottom of the drop.
static func _crest_turn(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	var owed := rad_to_deg(angle_difference(
		deg_to_rad(_heading_deg(layout, state.tangent)), deg_to_rad(plan.crest_heading_deg)
	))
	if absf(owed) < 6.0:
		plan["act_sweep_note"] = "no crest turn: %.0f° left" % owed
		return
	_add(route, state, sections, RideElements.author_turn(route, state, {
		"heading_change_deg": layout.turn_sign * owed,
		"bank_deg": _bank_for(owed, state.speed, plan.act_sweep_bank_deg),
	}))
	plan["act_sweep_note"] = "crest turn %.0f° onto %.0f° over %.0f m" % [
		owed, plan.crest_heading_deg, sections[-1].length
	]


## A turn flown as a gesture rather than as a correction: bank comes off until the arc is at least
## ACT_SWEEP_MIN_LENGTH long, so what the run reads is an arc between two beats.
static func _flowing_turn(
	layout: Dictionary,
	plan: Dictionary,
	route: Dictionary,
	state: Dictionary,
	sections: Array,
	owed: float
) -> void:
	var flowing := rad_to_deg(atan(
		deg_to_rad(absf(owed)) * state.speed * state.speed
		/ (ACT_SWEEP_MIN_LENGTH * RideElements.G0)
	))
	var bank: float = minf(
		minf(plan.act_sweep_bank_deg, flowing), _bank_for(owed, state.speed, plan.act_sweep_bank_deg)
	)
	_add(route, state, sections, RideElements.author_turn(route, state, {
		"heading_change_deg": layout.turn_sign * owed, "bank_deg": maxf(bank, 8.0),
	}))


## Heading the run still owes the escarpment, measured from where a turn of that size would leave it.
## A turn moves the train before its own aim is read, so the answer is a fixed point rather than an
## angle: six passes of an analytic arc endpoint settle it without integrating anything.
static func _owed_heading(
	layout: Dictionary, plan: Dictionary, state: Dictionary, run: float, target: float
) -> float:
	var heading := _heading_deg(layout, state.tangent)
	var owed := 0.0
	for _pass in 6:
		var landed := _arc_endpoint(
			layout, state.position, heading, owed, state.speed, plan.act_sweep_bank_deg
		)
		var residual := rad_to_deg(angle_difference(
			deg_to_rad(heading + owed),
			deg_to_rad(_approach_heading(layout, landed, run, target))
		))
		if absf(residual) < 0.25:
			break
		owed += residual
	return owed


## The wave turn, solved to the heading the act still owes. Its plan curve comes from the lateral
## load threaded through the crest, and the sweep that load buys is very nearly linear in it, so two
## rescales land the target; the drawn sweep is the cap, because past it the crest is a lateral beat
## rather than an airtime one.
static func _act_wave(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary,
	sections: Array, owed: float
) -> void:
	var want: float = clampf(owed, -plan.wave.sweep_deg, plan.wave.sweep_deg)
	if absf(want) < 12.0:
		want = 12.0 * (layout.turn_sign if is_zero_approx(want) else signf(want))
	var span: float = 1.7 * plan.wave.rise / maxf(
		sin(deg_to_rad(absf(RideElements.exit_pitch_deg(state)))), 0.15
	)
	var bank: float = signf(want) * layout.turn_sign * minf(
		plan.wave.peak_bank_deg, ROLL_BUDGET * 0.16 * span / state.speed
	)
	var lateral: float = plan.wave.lateral_g
	var group: Array = []
	var swept := 0.0
	for _pass in 3:
		group = RideElements.author_wave_turn(route, state, {
			"rise": plan.wave.rise,
			"crown_g": plan.wave.crown_g,
			"peak_bank_deg": bank,
			"lateral_g": lateral,
		})
		swept = layout.turn_sign * group[0].element.heading_change_deg
		if absf(swept - want) < 3.0:
			break
		lateral = clampf(lateral * want / (swept if absf(swept) > 1.0 else signf(want)), 0.3, 1.8)
	plan["wave_note"] = "wave turn sweeps %.0f° of the %.0f° owed at %.2f g lateral" % [
		swept, owed, lateral
	]
	_add(route, state, sections, group)


## The one sweep act one is allowed, and only when there is a real heading left to fly. It is forced
## long: bank comes off until the arc is at least ACT_SWEEP_MIN_LENGTH, so what the run reads is a
## banked arc between two beats rather than a correction snapped in between them.
static func _act_sweep(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary,
	sections: Array, run: float, target: float
) -> void:
	var owed: float = _owed_heading(layout, plan, state, run, target)
	if absf(owed) < ACT_SWEEP_MIN_DEG:
		return
	_flowing_turn(layout, plan, route, state, sections, owed)
	plan["act_sweep_note"] = "%s, plus a recovery sweep of %.0f° over %.0f m" % [
		plan.act_sweep_note, owed, sections[-1].length
	]


## Give back whatever altitude the act is still holding. A loop returns to the height it left, so
## this is a no-op after one; an Immelmann does not, and the drop that follows it is what hands the
## next inversion the speed its own feasibility check is about to ask for.
static func _settle_to_plain(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	## Eight metres, not twenty. A helical loop exits ten to twenty-four metres above the valley it
	## left, and that height is exactly the four metres a second the next inversion is then missing:
	## an Immelmann's apex is measured from its own entry, so altitude carried into it buys nothing
	## and the speed it cost is the whole of what sizes the shape.
	var owed: float = state.position.y - _valley_height(layout, plan, state)
	if owed < 8.0:
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
## v²/(g·h), and the shape is now the reference's twin-lobe one rather than a flat hold: the entry
## and exit lobes carry the load and the apex dips well under them, so the five-second held value the
## duration envelope reads is the dip and the window the ratio may sit in moves up with it. Below
## The window is narrow and it is the lobe that fixes it: measured, the lobe a teardrop with a dipped
## apex solves to is 1.62 times this ratio, so 3.35 to 3.85 is the entry leg held between 5.4 and
## 6.2 g whatever speed the act is entered at. Height then floats with v² rather than being chosen,
## which is also what keeps the loop the shorter of the two inversions: an Immelmann's apex goes as
## v²/(n+1) at the lower g it holds, so the pair sits at about the 0.82 the reference measures. The same 60 m loop reads a ratio of 3600 at the tunnel's 94 m/s,
## which is the 31 g that moved the inversions into act one in the first place.
static func _loop_height(plan: Dictionary, speed: float) -> float:
	var g: float = RideElements.G0
	var height: float = clampf(
		plan.loop.height, speed * speed / (g * 3.85), speed * speed / (g * 3.35)
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
	## The reversal wraps its own approach — that is what a cutback is — so how far past vertical it
	## is rolled decides whether it wraps it or hits it. Every degree beyond ninety turns more of the
	## support downward and pulls the exit leg in toward the entry, so a beat that will not clear is
	## offered a shallower roll before it is dropped.
	var group: Array = []
	var swept := 0.0
	var cleared := false
	for attempt in 3:
		group = RideElements.author_cutback(climbing.route, climbing.state, {
			"heading_change_deg": layout.turn_sign * 180.0,
			"peak_g": plan.cutback.peak_g,
			"peak_bank_deg": plan.cutback.peak_bank_deg - 6.0 * attempt,
		})
		swept = absf(group[0].element.heading_change_deg)
		if group[0].length > CUTBACK_MAX_LENGTH or absf(swept - 180.0) > CUTBACK_HEADING_TOLERANCE:
			continue
		cleared = _clears_route(route, RideElements._trial(climbing.route, climbing.state, group[0]).route)
		if cleared:
			break
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
	var floor_height: float = _valley_height(layout, plan, state)
	if settled.state.position.y < floor_height:
		plan["cutback_note"] = "%s cutback skipped: spends %.0f m against %.0f m of headroom" % [
			slot, climbing.state.position.y - settled.state.position.y,
			climbing.state.position.y - floor_height,
		]
		return false
	_add(route, state, sections, entry)
	_add(route, state, sections, group)
	_add(route, state, sections, level)
	plan["cutback_note"] = "%s cutback flown: %.0f m sweeping %.0f°, spending %.0f m" % [
		slot, group[0].length, swept, climbing.state.position.y - settled.state.position.y
	]
	return true


## Ground the launch corridor covers before the crest: one booster at 2 g and the coast up the face.
## Used by act one to aim, before either is solved, so it is the mid-window estimate rather than a
## measurement — which is exactly why the window exists.
static func _launch_run(layout: Dictionary, plan: Dictionary, state: Dictionary) -> float:
	var terrain: Dictionary = layout.terrain
	var rise: float = terrain.relief + plan.crest_margin - plan.drop_bottom_height
	var base: float = sqrt(
		plan.climb_exit_speed * plan.climb_exit_speed + 2.0 * RideElements.G0 * rise + CLIMB_DRAG * 900.0
	)
	var boost: float = (base * base - state.speed * state.speed) / (2.0 * plan.lsm2_g * RideElements.G0)
	return clampf(boost, 100.0, LSM_MAX_LENGTH) + rise / (CLIMB_DELIVERY * tan(deg_to_rad(29.0)))


## LSM2: a booster at the cliff base and then three hundred metres of unpowered coast up the face,
## decelerating the whole way, which is what the real ride does. The booster's exit speed is solved
## from the climb — enough energy to crest at a crawl and no more — and its length from the g it is
## allowed to hold. Only two things are then free, and both of them are how far the corridor reaches:
## the booster may run an eighth long or short of its nominal g — any more and it is not the booster
## the story asked for — and the climb may be steepened or shallowed inside a wide range. The shallow
## end of that range is a safety valve rather than a preference: act one aims itself at the corridor's
## estimated length, and on a seed that ends a couple of hundred metres further out than the estimate,
## a climb that cannot reach any further tops out inside the face. Between them they cover the heading act one arrived a little off
## by, which is why act one is allowed to arrive a little off.
static func _cliff_launch(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	var terrain: Dictionary = layout.terrain
	var target: float = terrain.apron_width + terrain.face_width + plan.crest_edge_offset
	var rise: float = terrain.relief + plan.crest_margin - state.position.y
	var nominal: float = rise / (CLIMB_DELIVERY * sin(deg_to_rad(29.0)))
	var base: float = sqrt(
		plan.climb_exit_speed * plan.climb_exit_speed
		+ 2.0 * RideElements.G0 * rise + CLIMB_DRAG * nominal
	)
	var square: float = (2.0 * plan.lsm2_g * RideElements.G0)
	var ramp: Vector2 = _lsm_ramp(plan.lsm2_g, state.speed, base)
	var stator: float = 0.5 * (ramp.x + ramp.y)
	var window := Vector2(
		clampf((base * base - state.speed * state.speed) * 0.88 / square + stator, 80.0, LSM_MAX_LENGTH),
		clampf((base * base - state.speed * state.speed) * 1.12 / square + stator, 90.0, LSM_MAX_LENGTH)
	)
	## Both levers move the same quantity — how much ground the corridor covers before the crest — so
	## they are bisected together on one parameter. Longer booster and shallower climb reach further.
	var reach := func(t: float) -> Vector2:
		var length: float = lerpf(nominal * 0.95, nominal * 1.60, t)
		var pitch: float = rad_to_deg(asin(clampf(rise / (CLIMB_DELIVERY * length), 0.05, 0.9)))
		return Vector2(lerpf(window.x, window.y, t), length * cos(deg_to_rad(pitch)))
	var low := 0.0
	var high := 1.0
	for _step in 22:
		var middle := (low + high) * 0.5
		var run: Vector2 = reach.call(middle)
		if _edge(layout, state.position + _ground(state.tangent) * (run.x + run.y)) < target:
			low = middle
		else:
			high = middle
	var solved: Vector2 = reach.call((low + high) * 0.5)
	var boost_length: float = solved.x
	var length: float = lerpf(nominal * 0.95, nominal * 1.60, (low + high) * 0.5)
	var pitch: float = rad_to_deg(asin(clampf(rise / (CLIMB_DELIVERY * length), 0.05, 0.9)))
	var blend: float = pitch * CLIFF_BLEND
	var climb := _climb_section(length, pitch, blend)
	## One deterministic re-check across both sections: the booster is solved for `base`, the coast is
	## integrated off it, and whatever the crest speed reads out by is put back as energy.
	var boost: Dictionary = {}
	for _pass in 2:
		## The booster runs onto the face rather than up to it: it ends already holding a quarter of
		## the climb's grade, which spends the pitch-up where the train is slowest and takes the pull
		## at the base of the cliff from five g down to three.
		boost = RideElements.grade_section(
			"LSM2 boost", boost_length, [Vector2(0, 0), Vector2(1, blend)], base, 2, 4.0, {}, ramp
		)
		var launched := _trial_grade(route, state, boost)
		var crested := _trial_grade(launched.route, launched.state, climb)
		var reached: float = crested.state.position.y - launched.state.position.y
		if absf(reached - rise) > 5.0:
			pitch = rad_to_deg(asin(clampf(
				sin(deg_to_rad(pitch)) * rise / maxf(reached, 1.0), 0.05, 0.9
			)))
			climb = _climb_section(length, pitch, blend)
		if absf(crested.state.speed - plan.climb_exit_speed) < 0.5:
			break
		base = sqrt(maxf(
			base * base
			+ plan.climb_exit_speed * plan.climb_exit_speed
			- crested.state.speed * crested.state.speed,
			state.speed * state.speed + 400.0
		))
	plan["lsm2_note"] = "LSM2 boost %.0f m at %.2f g to %.0f km/h, coast %.0f m at %.1f°" % [
		boost_length,
		(base * base - state.speed * state.speed) / (2.0 * boost_length * RideElements.G0),
		base * 3.6,
		length,
		pitch,
	]
	_add(route, state, sections, [boost])
	_add(route, state, sections, [climb])


static func _climb_section(length: float, pitch: float, entry_pitch: float) -> Dictionary:
	return RideElements.grade_section(
		"Cliff climb",
		length,
		[
			Vector2(0, entry_pitch), Vector2(CLIMB_RAMP_IN, pitch),
			Vector2(1.0 - CLIMB_RAMP_OUT, pitch), Vector2(1, 0),
		],
		-1.0,
		0
	)


## The clifftop, in the order the reference flies it: the climb tops out and the ride keeps its
## speed through the suspense and the rim turn, and only then does it slow down. The slow beat is
## the last thing before the drop — brake, then a dozen seconds of dead-level crawl that ends where
## the pitch-over starts. There is no release: the ride never re-accelerates up here, and the twelve
## seconds the reference measures at 0.98–1.00 g is exactly this hold and nothing else.
static func _clifftop(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	## The plateau beat runs back along the rim, not on along it. Act one already marched better than
	## a kilometre in one direction with nothing steering it and the climb added half of that again;
	## turned the other way here, the traverse takes four hundred metres of it back for a fifty-metre
	## turn at plateau speed, which is the cheapest corridor on the ride.
	_align(layout, route, state, sections, 180.0, plan.climb_bank_deg)
	_add(route, state, sections, RideElements.author_pullout(route, state, {
		"exit_pitch_deg": plan.suspense_pullout.exit_pitch_deg,
		"peak_g": _peak_for(
			state.speed, plan.suspense_pullout.exit_pitch_deg, plan.suspense_pullout.peak_g
		),
	}))
	## An outward-banked turn only holds altitude from level flight — entered nose-down it keeps
	## falling, and its heading solve then chases an element diving off the cliff.
	_level(route, state, sections, plan.level_g)
	var sweep := rad_to_deg(angle_difference(
		deg_to_rad(_heading_deg(layout, state.tangent)), deg_to_rad(-90.0)
	))
	_add(route, state, sections, RideElements.author_rim_turn(route, state, {
		"heading_change_deg": layout.turn_sign * sweep,
		"outward_bank_deg": plan.rim.outward_bank_deg,
		"lateral_g": plan.rim.lateral_g,
	}))
	_align(layout, route, state, sections, -90.0, 20.0, 1.0)
	## The brake and the crawl close the beat, and both want level track under them: a grade section
	## builds its own tangent from its pitch profile, so anything authored has to hand it level.
	_level(route, state, sections, plan.level_g)
	_add(route, state, sections, [
		RideElements.grade_section(
			"Holding brake", plan.hold_brake_length, _flat_pitch(), plan.crest_hold_speed, 0, 1.2
		),
		RideElements.grade_section(
			"Crest hold",
			plan.crest_hold_seconds * plan.crest_hold_speed,
			_flat_pitch(),
			plan.crest_hold_speed,
			0,
			1.2
		),
	])


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
	## The pullout is told to stop short of level: the booster behind it rides the falling tail out to
	## flat, which is where the reference's tunnel launch actually sits.
	var dive: Array = RideElements.author_dive(route, state, {
		"height": state.position.y - plan.tunnel_end_height,
		"max_pitch_deg": plan.dive_pitch_deg,
		"exit_pitch_deg": -plan.tunnel_grade_deg,
		"edge_g": plan.dive_edge_g,
		"peak_g": plan.dive_peak_g,
	})
	## Two groups on this ride are dives. Only this one is the cliff.
	for section in dive:
		section.element["cliff_dive"] = true
	_add(route, state, sections, dive)
	## The tunnel is the pullout and the booster inside it, and that is all it ever was: the dive
	## arrives at the plain already doing seventy-six metres a second, so the last twenty to the
	## record is a short stretch of stator rather than half a kilometre of powered downhill.
	tunnel.append(sections.size() - 1)
	var grade: float = RideElements.exit_pitch_deg(state)
	var ramp: Vector2 = _lsm_ramp(plan.lsm3_g, state.speed, plan.tunnel_exit_speed)
	## Boosting downhill, gravity pays for part of the speed, so the same 2 g of stator needs less of
	## it, and the length that holds the plan's g closes in one line the way the entry launch's does.
	## The booster holds the grade rather than ramping out of it: at ninety metres a second the pull
	## back to level inside the booster's own eighty metres reads six g, where the pullout that opens
	## the marquee corridor takes the same twelve degrees out at under three over four times the arc.
	var length: float = clampf(
		_lsm_length(plan.lsm3_g, state.speed, plan.tunnel_exit_speed, ramp)
		/ (1.0 + sin(deg_to_rad(absf(grade))) / plan.lsm3_g),
		30.0,
		LSM_MAX_LENGTH
	)
	plan["lsm3_note"] = "LSM3 boost %.0f m on %.0f° of falling grade, %.0f -> %.0f km/h holding %.2f g over %.0f m of plateau" % [
		length,
		-grade,
		state.speed * 3.6,
		plan.tunnel_exit_speed * 3.6,
		plan.lsm3_g,
		length - 0.5 * (ramp.x + ramp.y),
	]
	_add(route, state, sections, [RideElements.grade_section(
		"LSM3 boost",
		length,
		[Vector2(0, grade), Vector2(1, grade)],
		plan.tunnel_exit_speed,
		3,
		4.0,
		{},
		ramp
	)])
	tunnel.append(sections.size() - 1)


## The record chase, on the only stretch fast enough to carry it. The camelback is sized as
## structure and not as rise: at 90 m/s the entry pullout alone climbs a hundred metres before the
## hill has started, so what the ride is judged on is the apex above the valley it left, and the
## rise handed to author_hill is whatever is left of that once the pullout has been integrated.
static func _camelback(
	layout: Dictionary,
	plan: Dictionary,
	route: Dictionary,
	state: Dictionary,
	sections: Array,
	station_position: Vector3,
	station_tangent: Vector3
) -> void:
	## The dogleg off the dive's line, and the one place in the ride where the circuit is closed.
	## The tunnel leaves pointed straight out from the escarpment, and everything after it — the
	## camelback, the raceway arc, the run home — lives on whatever line is chosen here. Act one
	## marches better than a kilometre along the cliff with nothing steering it, so this is the
	## angle that walks that back: it is solved, against an analytic model of the marquee corridor
	## and the whole run home, so that what is left for the brake run is a brake run's length. The
	## drawn dogleg is what it falls back on when the solve runs out of corridor at either end.
	## Level first, then aim. The tunnel leaves on the dive's falling grade — the booster holds it
	## rather than pulling out of it — so the pullout that takes it back to level is the first thing
	## out of the tunnel mouth, and the corridor turn is solved from where that leaves the train.
	_level(route, state, sections, plan.level_g)
	_camelback_corridor(layout, plan, route, state, sections, station_position, station_tangent)
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
	var entry: Array = RideElements.author_pullout(route, state, {
		"exit_pitch_deg": pitch, "peak_g": plan.camelback.peak_g,
	})
	entry[0].element["camelback"] = true
	_add(route, state, sections, entry)
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
	var out: Array = RideElements.author_pullout(route, state, {
		"exit_pitch_deg": 0.0, "peak_g": plan.camelback.exit_peak_g,
	})
	out[0].element["camelback"] = true
	_add(route, state, sections, out)


## The heading the marquee corridor runs on, solved so that the run home closes. Everything after
## this point is a straight-ish shot and one rotation, both of which have analytic models, so the
## whole of the second act's geometry can be asked the only question that matters: how much corridor
## is left when the airtime runs out. Bisected because that answer falls monotonically as the
## corridor is turned back along the escarpment.
static func _camelback_corridor(
	layout: Dictionary,
	plan: Dictionary,
	route: Dictionary,
	state: Dictionary,
	sections: Array,
	station_position: Vector3,
	station_tangent: Vector3
) -> void:
	var approach: Vector3 = station_position - station_tangent * plan.approach_lead
	var home: float = _heading_deg(layout, station_tangent)
	var solved: Dictionary = _corridor_search(
		layout, plan, state.position, _heading_deg(layout, state.tangent), state.speed, approach, home
	)
	plan["return_arc_bank"] = solved.bank
	plan["return_pairs"] = solved.pairs
	plan["corridor_note"] = (
		"marquee corridor %.0f°, raceway arc at %.0f° of bank, %d pairs, brake approach %.0f m ahead and %.0f m aside"
		% [solved.aim, solved.bank, solved.pairs, solved.ahead, solved.aside]
	)
	_align(layout, route, state, sections, solved.aim, plan.turnaround_bank_deg, 3.0)


## Where the marquee corridor should run and how tight the raceway arc should be, decided against an
## analytic model of everything downstream: the corridor turn, the camelback, the arc, the marquee,
## and the airtime. Three dofs — corridor, radius, and how many speed hills there is room for — and
## two misses to answer, so it is searched on a coarse grid and refined twice rather than bisected:
## both dofs move both misses, and solving them one at a time walks in circles.
static func _corridor_search(
	layout: Dictionary,
	plan: Dictionary,
	position: Vector3,
	heading: float,
	speed: float,
	approach: Vector3,
	home: float
) -> Dictionary:
	var forward: Vector3 = _direction(layout, home)
	var across: Vector3 = _direction(layout, home + 90.0)
	var structure: float = CAMELBACK_REACH * speed * speed
	var return_speed: float = speed * RETURN_SPEED_SHARE
	var marquee: Dictionary = _marquee_arc(layout, plan, return_speed)
	## A dictionary because GDScript lambdas capture by value, and the count is the one thing the
	## search changes underneath the model.
	var beats := {"pairs": 2}
	var landed := func(aim: float, bank: float) -> Vector3:
		var turned := _arc_endpoint(
			layout, position, heading, aim - heading, speed, plan.turnaround_bank_deg
		)
		return _home_endpoint(
			layout,
			_run_endpoint(layout, turned, aim, structure),
			aim,
			return_speed,
			marquee,
			bank,
			beats["pairs"],
			home
		)
	var best := INF
	var chosen := {
		"aim": -90.0 - plan.post_tunnel_dogleg,
		"bank": plan.turnaround_bank_deg,
		"pairs": 2,
		"ahead": 0.0,
		"aside": 0.0,
		"error": INF,
	}
	for count in [2, 1, 0]:
		beats["pairs"] = count
		var aim_low: float = CORRIDOR_BAND.x
		var aim_high: float = CORRIDOR_BAND.y
		var bank_low: float = RETURN_BANK_BAND.x
		var bank_high: float = RETURN_BANK_BAND.y
		var aim := aim_low
		var bank := bank_low
		for _refine in 3:
			var best_here := INF
			for i in 17:
				for j in 9:
					var try_aim: float = lerpf(aim_low, aim_high, i / 16.0)
					var try_bank: float = lerpf(bank_low, bank_high, j / 8.0)
					var miss: Vector3 = approach - landed.call(try_aim, try_bank)
					var ahead: float = miss.dot(forward)
					var aside: float = miss.dot(across)
					## The arc's own length is part of the cost, not just the miss it leaves: a corridor
					## aimed back along the escarpment leaves ninety degrees to fly instead of a hundred
					## and eighty, and at eighty-five metres a second that is a kilometre of track.
					## Long and short are not the same mistake. What the run home comes home with in
					## hand is brake run — straight track that sheds speed and gives back height —
					## and what it comes home without is a cusp. So a shortfall is charged at full
					## weight and a surplus at a fraction of what a metre of banked arc costs, which
					## is what lets the search buy a tighter reversal with a longer brake run.
					var owed: float = plan.brake_length + CLOSURE_MARGIN
					var error: float = (
						maxf(owed - ahead, 0.0)
						+ RETURN_SURPLUS_COST * maxf(ahead - owed, 0.0)
						+ RETURN_ASIDE_COST * absf(aside)
						+ RETURN_ARC_COST * (
							_arc_length(
								_return_sweep_deg(try_aim, marquee.sweep, home), return_speed, try_bank
							)
							+ _arc_length(try_aim - heading, speed, plan.turnaround_bank_deg)
						)
					)
					if error < best_here:
						best_here = error
						aim = try_aim
						bank = try_bank
					if error + RETURN_PAIR_PENALTY * (2 - count) < best:
						best = error + RETURN_PAIR_PENALTY * (2 - count)
						chosen = {
							"aim": try_aim, "bank": try_bank, "pairs": count,
							"ahead": ahead, "aside": aside, "error": error,
						}
			var aim_step: float = (aim_high - aim_low) / 16.0
			var bank_step: float = (bank_high - bank_low) / 8.0
			aim_low = maxf(aim - aim_step, CORRIDOR_BAND.x)
			aim_high = minf(aim + aim_step, CORRIDOR_BAND.y)
			bank_low = maxf(bank - bank_step, RETURN_BANK_BAND.x)
			bank_high = minf(bank + bank_step, RETURN_BANK_BAND.y)
	return chosen


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


## Home run: turn back toward the station, one seeded marquee beat, and up to two pullout-and-hill
## pairs of return airtime. The final heading points at a spot short of the station so the C4
## closure has a straight approach, and every beat is gated on the corridor still left to it.
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
	## One rotation, solved once. The arc, the marquee it hands to and the airtime that follows are a
	## single gesture, so the arc is aimed past all three: what it is solved for is the heading the
	## whole run has to leave on, not the heading the next element wants. That is the difference
	## between a raceway arc with beats in it and a turn followed by corrections.
	var bank: float = plan.return_arc_bank
	var marquee: Dictionary = _marquee_arc(layout, plan, state.speed)
	var home: float = _heading_deg(layout, station_tangent)
	var swept: float = _return_sweep(layout, state, marquee, home)
	plan["arc_entry_heading"] = _heading_deg(layout, state.tangent)

	## The arc's radius is the last thing standing between the gesture and the platform, and the
	## analytic model that chose it is arcs and straight runs — good to a couple of hundred metres,
	## which is not good enough when being short means the closure bezier is asked to turn back
	## inside its own handles. So it is measured: the turn is integrated at the modelled bank and at
	## one either side of it, and the bank that leaves the marquee, the airtime and the brake run
	## their own lengths is the one flown.
	var want: float = MARQUEE_REACH + plan.brake_length + CLOSURE_MARGIN
	var pairs: int = plan.return_pairs
	var used := 0
	if absf(swept) > 6.0:
		var reach := func(candidate: float) -> float:
			var trial: Dictionary = RideElements._trial(route, state, RideElements.author_turn(
				route, state, {
					"heading_change_deg": layout.turn_sign * swept,
					"bank_deg": _bank_for(swept, state.speed, candidate),
				}
			)[0])
			return trial.state.position.distance_to(approach)
		var first: float = reach.call(bank)
		var probe: float = clampf(bank - 10.0, RETURN_BANK_BAND.x, RETURN_BANK_BAND.y)
		if absf(first - want) > 40.0 and absf(probe - bank) > 1.0:
			var second: float = reach.call(probe)
			if absf(second - first) > 1.0:
				## Only ever a little looser than the model chose, and as tight as the envelope allows.
				## A secant given the whole band answers "fly a wider circle" to any shortfall, and a
				## wider circle at eighty-five metres a second is three kilometres of track.
				bank = clampf(
					bank + (want - first) * (probe - bank) / (second - first),
					maxf(RETURN_BANK_BAND.x, bank - 4.0),
					RETURN_BANK_BAND.y
				)
		## The reference's run home is not one rotation: turn, float, turn, then a long sweep. Flown
		## the same way here it is both shorter and more faithful, because the duration envelope pays
		## for it — a reversal split in two holds each half for half as long, and the limit at three
		## seconds is 5.3 g against 4.0 at five, which is four more degrees of bank and a radius a
		## fifth tighter. The float between the halves is the first return pair, moved forward.
		## Measured, and against the reference's own turn-float-turn-sweep shape: splitting the
		## reversal in two makes the run home LONGER here, because the bank a turn may hold is
		## roll-rate limited rather than duration limited. `_bank_for` allows bank·tan(bank) ≤
		## ROLL_BUDGET·0.16·Δ·v/g, so halving the sweep halves the budget — 125° at 73° of bank lays
		## down 737 m, two halves at the 66° their own budgets allow lay down 1072. So the reversal
		## stays one arc, and the length comes off the roll budget instead.
		bank = minf(bank, _duration_bank(swept, state.speed))
		_add(route, state, sections, RideElements.author_turn(route, state, {
			"heading_change_deg": layout.turn_sign * swept,
			"bank_deg": _bank_for(swept, state.speed, bank),
		}))
	plan["return_note"] = "raceway arc sweeps %.0f° at %.0f° of bank over %.0f m, %.0f m left" % [
		swept, bank, sections[-1].length, _corridor_left(state, approach)
	]
	## The marquee is the second half of the same rotation. Past vertical at 83 m/s the support is
	## gone for the whole element, and the roll-rate limit forces it to be long: ninety degrees of it
	## is 480 m of track and eighty metres of descent. On the seeds that draw the wave turn instead,
	## the beat is an airtime crest flown on edge, which costs the corridor nothing but the hill.
	## Gated on measured room, not on the model: the beat is solved, trial-integrated, and taken only
	## if what it leaves behind it is still a closure's worth of corridor. A run home that lands on
	## top of the platform hands the C4 bezier a hundred metres to take out a heading and an offset
	## in, and it takes them out as a cusp.
	if _marquee_room(layout, plan, route, state, approach) < maxf(
		CLOSURE_FLOOR, _run_in_needed(plan, state)
	):
		plan["marquee_note"] = "%s skipped: %.0f m of corridor left" % [
			plan.return_marquee, _corridor_left(state, approach)
		]
	elif plan.return_marquee == "overbank":
		## Entered climbing, because past vertical there is no support at all: ninety degrees of
		## overbank at eighty-five metres a second is most of four seconds of free fall, and the plain
		## is thirty metres under the camelback's valley. The entry pullout is what buys the headroom.
		_add(route, state, sections, RideElements.author_pullout(route, state, {
			"exit_pitch_deg": plan.return_wave_entry.exit_pitch_deg,
			"peak_g": _peak_for(
				state.speed, plan.return_wave_entry.exit_pitch_deg, plan.return_wave_entry.peak_g
			),
		}))
		if not _add_if_sound(
			layout, route, state, sections, RideElements.author_overbank(route, state, {
				"heading_change_deg": layout.turn_sign * plan.overbank.heading_change_deg,
				"bank_deg": plan.overbank.bank_deg,
				"peak_g": plan.overbank.peak_g,
			})
		):
			plan["marquee_note"] = "overbank rejected by the corridor"
	else:
		_return_wave(layout, plan, route, state, sections)
	## The airtime rides inside the arc: each pair is entered on the attitude the beat in front of it
	## left, so nothing between them is aimed. The pair is still trialled before it is committed,
	## because what matters is not its length but the corridor it leaves for the brake run.
	while used < pairs:
		if not _return_pair(plan, route, state, sections, used, approach):
			break
		used += 1
	_level(route, state, sections, plan.level_g)
	## The one safety valve on the run home. The arc was aimed through a model of the beats behind
	## it, and a model is a model: if the gesture really has landed pointing somewhere else, it is
	## squared up once. Anything under the tolerance is left for the brake run and the closure.
	var aim: float = _aim_heading(layout, state.position, approach)
	var off := absf(rad_to_deg(angle_difference(
		deg_to_rad(_heading_deg(layout, state.tangent)), deg_to_rad(aim)
	)))
	## Past the limit the aim point is behind the train and a turn to it is a second reversal, so what
	## the run squares up on instead is the station's own bearing: the C4 closure cusps on a tangent
	## mismatch, not on an offset — matched tangents it takes out as an S.
	if _corridor_left(state, approach) < CLOSURE_FLOOR:
		off = 0.0
	elif off > RETURN_AIM_LIMIT:
		aim = home
		plan["return_note"] = "%s, aim %.0f° off so squared on the station's bearing" % [
			plan.return_note, off
		]
	## Nothing squares up straight off the arc. The arc was already solved for the heading the whole
	## gesture had to leave on, so a turn immediately behind it is not a square-up — it is one rotation
	## flown as two elements, which is the correction chaining the run home is written against and
	## which the flow rule reads as a turn running into a turn.
	##
	## What decides it is the closure, not the turn's own cost. A bezier takes out heading inside its
	## own handles and the handles are a fraction of the gap, so what it needs is corridor in
	## proportion to the heading it is handed — and when the corridor already covers that, squaring up
	## is a correction the run home does not need. When it does not, the square-up is not optional: a
	## turn is track and it can be long, while a bezier asked to take out seventy degrees inside a
	## station approach is a cusp, and there is no recovering from one of those.
	## Measured against the platform along the heading the train is actually on, which is the same
	## number the brake run behind this reads — the two used to answer to different reference points
	## and disagree about whether there was room.
	var left: float = _station_run(state, station_position)
	var needed: float = plan.approach_lead + CLOSURE_TURN_COST * off
	if off > 0.0 and left >= needed + 60.0:
		plan["return_note"] = "%s, %.0f° left for the closure: %.0f m of run-in against %.0f needed" % [
			plan.return_note, off, left, needed
		]
	elif off > 0.0 and not (sections[-1].kind == "FVD" and sections[-1].element.get("kind", "") == "turn"):
		_align(layout, route, state, sections, aim, 60.0, RETURN_AIM_TOLERANCE)
	plan["return_note"] = "%s, %d of %d pairs flown" % [plan.return_note, used, pairs]
	## The brake run covers what the corridor leaves, less one approach lead, and comes down to
	## station height on the way — a closure that has to shed thirty metres of potential as well as
	## the speed cannot solve its drive and stalls short of the platform. Both ends of the length
	## matter: stopped a kilometre out, the C4 closure — a bezier across the gap, not a solved-length
	## element — grows past its own 8 % budget; run all the way onto the approach point, the same
	## bezier has only the lead left to take out the heading it was handed, and a nine-control curve
	## asked to turn inside its own handles folds into a cusp the lateral limit reads at seven g.
	var run_home: float = state.position.distance_to(approach)
	## The brake run covers what the corridor actually left, and never a metre more. Driven past the
	## approach point the closure is a nine-control bezier asked to turn back inside its own handles,
	## which it does as a cusp — measured, eight hundred g of lateral. So when the gesture comes home
	## short the brake run is simply not built and the closure sheds the speed itself: it solves its
	## own drive, and a three-hundred-metre bezier from seventy metres a second is under a g of it.
	## Long enough to do both jobs, and never long enough to run past the platform. The brake run has
	## to shed the speed and give back the height the run home is carrying, and what it cannot give
	## back the C4 closure has to — a closure asked to lose forty metres of potential as well as
	## seventy metres a second solves a drive that stalls the train halfway across it.
	var descent: float = maxf(state.position.y - STATION_HEIGHT, 0.0)
	## All of it. Whatever the corridor model was long by is the brake run's, not the closure's: a
	## brake run is straight track that sheds speed and gives back height, and a closure is a bezier
	## at station speed that can do neither. Driven onto the approach point the closure is exactly
	## the lead, which is what a station approach is.
	## Measured along the heading the run home actually leaves on, not as a distance to a point: the
	## brake run is straight track, so what it can cover is the projection. What it stops short of is
	## the lead the closure needs, and that is not a constant — a bezier takes a lateral offset out as
	## an S for nothing, but it has to turn out whatever heading it is handed inside its own handles,
	## and asked to do that in too short a gap it folds into a cusp. So the lead grows with the
	## heading the run home really came home on.
	var aim_error := absf(rad_to_deg(angle_difference(
		deg_to_rad(_heading_deg(layout, state.tangent)), deg_to_rad(home)
	)))
	var lead: float = plan.approach_lead + CLOSURE_TURN_COST * aim_error
	var brake_length: float = _station_run(state, station_position) - lead
	if brake_length < 60.0:
		plan["brake_note"] = "no brake run: %.0f m along its own heading, %.0f° off the platform" % [
			brake_length, aim_error
		]
		return
	var grade: float = _brake_grade(state.speed, brake_length)
	var brake_pitch := rad_to_deg(asin(clampf(
		descent / (RAMP_DELIVERY * brake_length), -grade, grade
	)))
	plan["brake_note"] = "brake run %.0f m at up to %.0f°, giving back %.0f of the %.0f m it carries, %.0f m of lead left %.0f° off" % [
		brake_length, rad_to_deg(asin(grade)),
		RAMP_DELIVERY * brake_length * sin(deg_to_rad(brake_pitch)), descent, lead, aim_error
	]
	_add(route, state, sections, [RideElements.grade_section(
		"Final brakes",
		brake_length,
		## Ramped across the whole first half: what the crest into a brake run costs is v² times its
		## curvature, and this is the fastest grade on the ride at the moment it starts.
		[
			Vector2(0, 0), Vector2(0.55, -brake_pitch), Vector2(0.85, -brake_pitch), Vector2(1, 0),
		],
		7.0
	)])


## Steepest a brake run of this length may be pitched, solved rather than capped. The profile ramps
## the pitch on over the first half of the run, and by a quarter of the way in the brakes have
## already taken a fifth of the speed out — which is where the crest is steepest and where the load
## is read: n − 1 = −v²·Δθ·2.1875/(0.55·L·g), inverted for the crest the ride will take.
static func _brake_grade(entry_speed: float, length: float) -> float:
	var speed2: float = 0.73 * entry_speed * entry_speed + 13.0
	return clampf(
		absf(BRAKE_CREST_G - 1.0) * 0.55 * length * RideElements.G0 / (2.1875 * maxf(speed2, 1.0)),
		0.02,
		0.35
	)


## Corridor the run home has to leave behind it, and height is half of that number. A brake run
## sheds the speed in its own length, but the height the run home is still carrying is the brake
## run's to give back too — and at the grade its own entry crest allows, a metre of height costs
## some four and a half metres of run. What it cannot give back the closure inherits, and a closure
## at station speed asked to lose fifty metres of potential stalls inside itself. So every beat on
## the run home is gated on both.
static func _run_in_needed(plan: Dictionary, state: Dictionary) -> float:
	return maxf(
		plan.brake_length * 0.8,
		(state.position.y - STATION_HEIGHT) * BRAKE_RUN_PER_METRE
	)


## Track between the train and the platform along the heading the train is on. Everything the tail of
## the run home decides answers to this one number: what the brake run can cover, and what is left
## for the closure after it. Negative means the platform is behind the train.
static func _station_run(state: Dictionary, station_position: Vector3) -> float:
	return (station_position - state.position).dot(_ground(state.tangent))


## Corridor still ahead of the train, measured along the heading it is actually on. A distance to
## the approach point is not the same thing and never was: past the platform the distance starts
## growing again, so a beat gated on it flies happily out the far side and hands the closure a
## bezier that has to come back — which it does as a cusp. Everything downstream of the raceway arc
## is gated on this instead.
static func _corridor_left(state: Dictionary, approach: Vector3) -> float:
	return (approach - state.position).dot(_ground(state.tangent))


## One pullout-and-hill pair of return airtime, entered on the attitude the beat in front of it
## left. Trialled before it is committed, because what matters is not its length but the corridor it
## leaves for the brake run — and refused rather than shortened when there is not room.
static func _return_pair(
	plan: Dictionary,
	route: Dictionary,
	state: Dictionary,
	sections: Array,
	index: int,
	approach: Vector3
) -> bool:
	if index >= plan.return_pullouts.size():
		return false
	var pullout: Dictionary = RideElements.author_pullout(route, state, plan.return_pullouts[index])[0]
	var crest: Dictionary = RideElements._trial(route, state, pullout)
	var hill: Dictionary = RideElements.author_hill(crest.route, crest.state, plan.return_hills[index])[0]
	var landed: Dictionary = RideElements._trial(crest.route, crest.state, hill)
	if _corridor_left(landed.state, approach) < _run_in_needed(plan, landed.state):
		return false
	_add(route, state, sections, [pullout])
	_add(route, state, sections, [hill])
	return true


## Bank a raceway arc of this sweep may hold. The duration envelope falls with the hold and the hold
## is most of the arc's own length over its speed — the roll goes on and comes off at the ends, and
## measured, four fifths of a raceway arc is spent at the bank it is named for. The two are solved
## against each other rather than capped by a constant: three passes settle it, because the arc
## shortens as fast as the limit rises.
## Nine tenths of the limit, which is the margin between an authored plateau and the filtered,
## duration-read value the check itself measures.
static func _duration_bank(sweep_deg: float, speed: float) -> float:
	var bank: float = RETURN_BANK_BAND.y
	for _pass in 3:
		var held: float = 0.8 * _arc_length(sweep_deg, speed, bank) / speed
		var ceiling: float = 0.9 * RideVerify.limit_at(RideVerify.POSITIVE_LIMIT, held)
		bank = clampf(
			rad_to_deg(acos(clampf(1.0 / maxf(ceiling, 1.05), 0.0, 1.0))),
			RETURN_BANK_BAND.x,
			RETURN_BANK_BAND.y
		)
	return bank


## The marquee beat, as an arc the model can see through. Neither shape holds altitude, so the radius
## is not the bank's: an overbank turns on its authored normal load, v²/(peak·g), and a wave turn on
## the lateral threaded through its crest.
static func _marquee_arc(_layout: Dictionary, plan: Dictionary, speed: float) -> Dictionary:
	if plan.return_marquee == "overbank":
		return {
			"sweep": plan.overbank.heading_change_deg,
			"bank": rad_to_deg(atan(MARQUEE_TIGHTNESS * plan.overbank.peak_g)),
		}
	var span: float = 1.7 * plan.return_wave.rise / 0.3
	return {
		"sweep": rad_to_deg(
			plan.return_wave.lateral_g * RideElements.G0 * span / (speed * speed)
		),
		"bank": rad_to_deg(atan(MARQUEE_TIGHTNESS * plan.return_wave.lateral_g)),
	}


## How far the raceway arc sweeps. Not an aim at a point — a rotation onto the heading the station
## itself sits on, with the marquee counted as the second half of it. Everything after the marquee
## flies straight, so this is the whole of the run home's steering in one number.
static func _return_sweep(
	layout: Dictionary, state: Dictionary, marquee: Dictionary, home_heading: float
) -> float:
	return rad_to_deg(angle_difference(
		deg_to_rad(_heading_deg(layout, state.tangent) + marquee.sweep), deg_to_rad(home_heading)
	))


## Heading the raceway arc has to sweep from a given corridor, and the track that costs.
static func _return_sweep_deg(heading: float, marquee_sweep: float, home_heading: float) -> float:
	return rad_to_deg(angle_difference(
		deg_to_rad(heading + marquee_sweep), deg_to_rad(home_heading)
	))


static func _arc_length(sweep_deg: float, speed: float, bank_deg: float) -> float:
	return TURN_ARC_FACTOR * deg_to_rad(absf(sweep_deg)) * speed * speed / (
		RideElements.G0 * maxf(tan(deg_to_rad(clampf(bank_deg, 4.0, 80.0))), 0.05)
	)


## Where the run home ends up, modelled: arc, marquee, then the airtime flown straight. Analytic
## because it is asked hundreds of times while the marquee corridor is being chosen, and integrating
## candidate turns costs more than the turns being chosen between.
static func _home_endpoint(
	layout: Dictionary,
	position: Vector3,
	heading: float,
	speed: float,
	marquee: Dictionary,
	bank: float,
	pairs: int,
	home_heading: float
) -> Vector3:
	var owed := rad_to_deg(angle_difference(
		deg_to_rad(heading + marquee.sweep), deg_to_rad(home_heading)
	))
	var after_arc := _arc_endpoint(layout, position, heading, owed, speed, bank)
	var after_marquee := _arc_endpoint(
		layout, after_arc, heading + owed, marquee.sweep, speed, marquee.bank
	)
	return _run_endpoint(
		layout, after_marquee, home_heading, pairs * RETURN_PAIR_SECONDS * speed
	)


## What the marquee beat would leave behind it, measured by solving and trial-integrating the real
## thing rather than by asking the model that chose the corridor.
static func _marquee_room(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, approach: Vector3
) -> float:
	var group: Array
	if plan.return_marquee == "overbank":
		var entry: Array = RideElements.author_pullout(route, state, {
			"exit_pitch_deg": plan.return_wave_entry.exit_pitch_deg,
			"peak_g": _peak_for(
				state.speed, plan.return_wave_entry.exit_pitch_deg, plan.return_wave_entry.peak_g
			),
		})
		var climbing: Dictionary = RideElements._trial(route, state, entry[0])
		group = RideElements.author_overbank(climbing.route, climbing.state, {
			"heading_change_deg": layout.turn_sign * plan.overbank.heading_change_deg,
			"bank_deg": plan.overbank.bank_deg,
			"peak_g": plan.overbank.peak_g,
		})
		return _corridor_left(
			RideElements._trial(climbing.route, climbing.state, group[0]).state, approach
		)
	var entry: Array = RideElements.author_pullout(route, state, {
		"exit_pitch_deg": plan.return_wave_entry.exit_pitch_deg,
		"peak_g": _peak_for(
			state.speed, plan.return_wave_entry.exit_pitch_deg, plan.return_wave_entry.peak_g
		),
	})
	var climbing: Dictionary = RideElements._trial(route, state, entry[0])
	var span: float = 1.7 * plan.return_wave.rise / maxf(
		sin(deg_to_rad(absf(RideElements.exit_pitch_deg(climbing.state)))), 0.15
	)
	group = RideElements.author_wave_turn(climbing.route, climbing.state, {
		"rise": plan.return_wave.rise,
		"crown_g": plan.return_wave.crown_g,
		"peak_bank_deg": layout.turn_sign * minf(
			plan.return_wave.peak_bank_deg, ROLL_BUDGET * 0.16 * span / climbing.state.speed
		),
		"lateral_g": plan.return_wave.lateral_g,
	})
	return _corridor_left(
		RideElements._trial(climbing.route, climbing.state, group[0]).state, approach
	)


## The wave turn's half of the return marquee: an airtime crest flown on edge. It has to be entered
## climbing — handed level track its rise solve has nothing to work against — and the bank it can
## hold is whatever the roll budget leaves once the rise has fixed its length.
static func _return_wave(
	layout: Dictionary, plan: Dictionary, route: Dictionary, state: Dictionary, sections: Array
) -> void:
	_add(route, state, sections, RideElements.author_pullout(route, state, {
		"exit_pitch_deg": plan.return_wave_entry.exit_pitch_deg,
		"peak_g": _peak_for(
			state.speed, plan.return_wave_entry.exit_pitch_deg, plan.return_wave_entry.peak_g
		),
	}))
	var span: float = 1.7 * plan.return_wave.rise / maxf(
		sin(deg_to_rad(absf(RideElements.exit_pitch_deg(state)))), 0.15
	)
	_add(route, state, sections, RideElements.author_wave_turn(route, state, {
		"rise": plan.return_wave.rise,
		"crown_g": plan.return_wave.crown_g,
		"peak_bank_deg": layout.turn_sign * minf(
			plan.return_wave.peak_bank_deg, ROLL_BUDGET * 0.16 * span / state.speed
		),
		"lateral_g": plan.return_wave.lateral_g,
	}))


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


## Which gesture a section belongs to. Stamped after each slot rather than passed into it, so the
## story skeleton names the phases in one place and the phase profile the checks print reads back
## exactly the five long gestures the ride is written as.
static func _mark(sections: Array, phase: String) -> void:
	for section in sections:
		if not section.has("phase"):
			section["phase"] = phase


## Whether the samples a trial added clear the track that was already there. The route check reads a
## three-metre corridor between any two points more than thirty metres apart along the track, and a
## beat that wraps its own approach — which is the whole of what a cutback is — is exactly the beat
## that can fail it.
static func _clears_route(route: Dictionary, trial: Dictionary) -> bool:
	var first: int = route.positions.size()
	for i in range(first, trial.positions.size()):
		var point: Vector3 = trial.positions[i]
		for j in first:
			if absf(trial.distances[i] - trial.distances[j]) <= 30.0:
				continue
			if point.distance_to(trial.positions[j]) < 3.6:
				return false
	return true


## The bookkeeping build_route does per section, done here instead because every author_* needs the
## live route and state to solve against, which a pre-built section list cannot provide.
static func _add(route: Dictionary, state: Dictionary, sections: Array, group: Array) -> void:
	for section in group:
		## A section shorter than a handful of samples is not track, it is the residue of someone's
		## fixed point — a fall that had a metre left to give, a pullout handed a tenth of a degree.
		## Flown, it puts a whole section seam inside six samples and its own force ramp inside two,
		## which the C4 seam check reads as a curvature jump — the check wants the first samples inside
		## a section to land where its own force ramp is still nearly flat, and a ramp is a fifth of a
		## short section's length. Skipped, it moves the route by a few metres of pitch. Grades are
		## exempt: a short flat grade carries no curvature at all, and the crest hold is deliberately
		## a hundred-odd metres of exactly that.
		if section.kind == "FVD" and section.length < 16.0:
			continue
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


static func _wrap(degrees: float) -> float:
	return rad_to_deg(angle_difference(0.0, deg_to_rad(degrees)))


## Stator a booster spends engaging and disengaging, in metres of track at each end. Both ends are
## sized off the speed they are ridden at, so the ramp is asymmetric whenever the launch is.
static func _lsm_ramp(g: float, entry_speed: float, exit_speed: float) -> Vector2:
	return Vector2(entry_speed, exit_speed) * 1.875 * g / LSM_ONSET


## Length a booster holding `g` needs to make the speed, plateau plus the half of each ramp that
## engagement does not deliver.
static func _lsm_length(g: float, entry_speed: float, exit_speed: float, ramp: Vector2) -> float:
	return (
		(exit_speed * exit_speed - entry_speed * entry_speed) / (2.0 * g * RideElements.G0)
		+ 0.5 * (ramp.x + ramp.y)
	)


static func _flat_pitch() -> Array:
	return [Vector2(0, 0), Vector2(1, 0)]


static func _ground(tangent: Vector3) -> Vector3:
	return Vector3(tangent.x, 0.0, tangent.z).normalized()


## Where a coordinated turn of this size ends up, without integrating it. A turn is an arc of radius
## v²/(g·tan bank), so its chord is 2R·sin(Δ/2) laid down on the bisecting heading — accurate enough
## to aim with, which is the whole point: an aim that has to integrate its own candidate turns costs
## more than the turns it is choosing between.
static func _arc_endpoint(
	layout: Dictionary,
	position: Vector3,
	heading_deg: float,
	delta_deg: float,
	speed: float,
	bank_deg: float
) -> Vector3:
	## A turn is not a circle of the radius its held bank implies: the roll goes on over the first
	## third and comes back off over the last, so most of a third of the element turns at less than
	## the bank it is named for. Measured across these seeds, the arc it really lays down is half as
	## long again as the textbook one, and the aim reads the arc it really lays down.
	var radius: float = TURN_ARC_FACTOR * speed * speed / (
		RideElements.G0 * maxf(tan(deg_to_rad(clampf(bank_deg, 4.0, 80.0))), 0.05)
	)
	var chord: float = 2.0 * radius * sin(deg_to_rad(absf(delta_deg)) * 0.5)
	return position + _direction(layout, heading_deg + delta_deg * 0.5) * chord


## The same estimate for a run of straight-ish beats: they hold their heading, so they only move the
## aim point along it.
static func _run_endpoint(
	layout: Dictionary, position: Vector3, heading_deg: float, distance: float
) -> Vector3:
	return position + _direction(layout, heading_deg) * distance


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
