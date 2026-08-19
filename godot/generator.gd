class_name RideGenerator
extends RefCounted

## Material-v1 facade. Generator owns only the accepted terrain-relative story plan;
## RideProgram owns native recipes and solves; Motion performs the sole accepted integration;
## RouteContract validates and publishes the accepted native route.

const Motion := preload("res://motion.gd")
const RideConfig := preload("res://ride_config.gd")
const RidePlanner := preload("res://ride_planner.gd")
const RideProgram := preload("res://ride_program.gd")
const RideReturnSolve := preload("res://ride_return_solve.gd")
const RouteContract := preload("res://route_contract.gd")
const Terrain := preload("res://terrain.gd")

const PLAN_SCHEMA_VERSION := 1
const PRESET_ID := "material-v1"
const STATION_SPEED_MPS := 6.0
const SUMMIT_TRACK_AGL_BAND_M := Vector2(15.01, 24.95)
const INTEGRATION_STEP_S := 0.01
const DIVE_EXIT_APRON_BAND := Vector2(0.20, 0.55)
const DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M := Vector2(12.0, 40.0)
const TUNNEL_EXIT_PLAIN_OVERSHOOT_M := 8.0
const DIVE_CENTERLINE_CLEARANCE_M := 4.05
const DIVE_LOWER_SPINE_CLEARANCE_M := 2.05
const STATION_LOWER_SPINE_CLEARANCE_M := 4.05
const LOWER_SPINE_SURFACE_OFFSET_M := 1.79
const APPROACH_LENGTH_M := 230.0
const APPROACH_SAMPLE_STEP_M := 5.0
## The record the tunnel booster is authored for; `smoke.gd` gates the built top speed on it.
const RECORD_EXIT_SPEED_BAND_MPS := Vector2(93.9, 95.6)
## The margins the fifteen-seed fleet gate certifies. Placement builds its aim bands from these,
## so an accepted plan carries the margin by construction rather than hoping for it; `smoke.gd`
## measures what each seed actually achieved and fails on a miss.
const DIVE_ENTRY_EDGE_MARGIN_M := 3.0
const DIVE_EXIT_APRON_MARGIN := 0.05
## The other two fleet margins and the closure's evaluation allowance. Unlike the two above,
## placement does not build an aim band from these, so they had no home here until three readers
## wanted them: `smoke.gd` measures them on the fifteen-seed fleet, `generator_material_tests.gd`
## holds a refused story to the same bar, and both used to carry their own copy. The allowance is
## the fraction of the closure's own derived unique-evaluation cap every accepted plan stays inside.
const PREFIX_MARGIN_SUMMIT_M := 1.5
const PREFIX_MARGIN_RECORD_MPS := 0.4
const PREFIX_EVALUATION_ALLOWANCE := 0.6
## The summit and record aim bands are the middle 40% of their feasible bands, so a converged
## closure sits interior. Measured on the fleet: that 40% interior clears the certified summit and
## record margins by 2.98 m and 0.11 m/s. The dive-entry aim is deliberately not interior - issue
## 22 wants the rim end of its band, and `DIVE_ENTRY_RIM_AIM_M` cushions the certified margin
## instead; the apron fraction is then whatever those two leave, measured at +0.0565 worst.
const AIM_BAND_INTERIOR_FRACTION := 0.4
## The dive's outward edge run is aimed at a terrain-derived chord spine rather than at the middle
## of its feasible band: measured on the fleet, the 40% interior of the composed band would demand
## a 2-12 m reshape of a chord the terrain does not object to. The half-width is also what holds
## the whole chord aim under the entry's own floor (`_terrain_dive_span_m`), so widening it would
## be paid for in how far back from the rim the dive may start. Re-measured against the rim aim
## (2026-08-15): the edge wobble across the dive's own span runs -8.2 to +6.6 m over the fifteen
## seeds, so the authored chord starts inside its aim band on twelve of them and the closure walks
## the other three in - it is a head start for the solve, not a claim that the solve is unneeded.
const DIVE_SPAN_AIM_HALF_WIDTH_M := 6.0
## Issue 22 - the dive commits at the rim. The entry is aimed at the rim end of its feasible band
## instead of the middle: this is the window above that band's own floor that `placement_u` draws
## in. The 1 m cushion keeps the certified `DIVE_ENTRY_EDGE_MARGIN_M` a margin the fleet aims above
## rather than grazes, and the 4 m width is what the draw keeps to vary placement per seed.
const DIVE_ENTRY_RIM_AIM_M := Vector2(1.0, 5.0)
## How far inside the `outward-dive` role's own declared length band the closure aims its fifth
## residual. The band is judged by `route_contract.gd`, so the aim is the band inset - the same
## mechanism `RETURN_LENGTH_AIM_MARGIN_M` uses on the route total, for the same reason:
## `_band_residual` is flat inside a band and gives the solve no reason to stay interior.
## The size is derived between two measured bounds. Below, the solver's own convergence slack on
## this channel is 0.02 x the 5.0 residual scale = 0.1 m, so any inset above that leaves an
## accepted closure structurally inside the declared band rather than only measurably inside it.
## Above, the canonical fleet builds the role at 475.604-476.544 m against 350-490 (2026-08-16),
## so 13.456 m of ceiling headroom sits over the worst seed and any inset under that leaves every
## canonical observation strictly interior, this residual exactly 0.0, its Jacobian row identically
## zero and the fifteen canonical rides bit-identical rather than approximately unchanged.
##
## Two metres is 20x the slack and a fifth of the headroom, and inside that window the value is
## chosen by what builds. Measured on the act-one optional swap, whose dive is the only one this
## residual ever moves: at a 3 m inset the closure delivers the role at 486.97-487.02 m and two of
## the four gated seeds build, while 11 and 4096 refuse with their dive at 487.13-487.16 m - 2.8 m
## inside the band they are being refused for, 0.06-0.16 m outside an aim ceiling that is itself
## an inset. At 2 m all four build, the delivered role runs 487.96-488.02 m, and the 1.98 m of
## true-band interiority still exceeds the slack by 20x. Nothing in the fleet moves either way.
const DIVE_ARC_AIM_MARGIN_M := 2.0
## The two analytic yaw solutions are separated by twice the chord's cross component - tens of
## degrees - so the post-solve agreement check only has to distinguish the branch, not pin an axis
## the dive-span aim band is free to rotate by a few degrees.
const YAW_SOLUTION_AGREEMENT_DOT := 0.99


static func build(seed_value: int) -> Dictionary:
	return build_with_decisions(seed_value, RidePlanner.resolve(seed_value))


## The version-1 configuration surface: normalize preset ← file ← CLI, map the resolved document
## onto the planner's certified draw ranges, and build. Returns
## `{ok, route, resolved_config, plan, errors, report}`.
##
## `build()` above stays the preset fast path and is untouched by this: an empty configuration
## resolves to the preset base, pins nothing, and therefore takes exactly the draw sequence and
## publishes exactly the route it always did. A configured build pins its draws through the
## planner's override seam — which consumes the same number of values from the same streams — so
## the same (config, seed) is bit-identical every time.
static func build_config(file_config: Dictionary, cli_overrides: Array = []) -> Dictionary:
	var normalized: Dictionary = RideConfig.normalize(file_config, cli_overrides)
	var resolved: Dictionary = normalized.resolved
	var report: Dictionary = normalized.report
	if not normalized.ok:
		return {"ok": false, "route": {}, "resolved_config": resolved, "plan": {},
			"errors": normalized.errors, "report": report}
	var seed_value := int(resolved.seed)
	var pins: Array = RideConfig.planner_pins(resolved)
	var decisions: Dictionary = RidePlanner.resolve(seed_value,
		RideConfig.planner_overrides(pins))
	if not pins.is_empty():
		# Provenance rides with the plan only when the configuration actually pinned something,
		# so the unconfigured route stays byte-for-byte what `build()` has always published.
		decisions["draws"] = RideConfig.annotate_draws(decisions.draws, pins)
	report = RideConfig.record_achievements(report, decisions.draws, pins)
	var route := build_with_decisions(seed_value, decisions)
	if not route.get("ok", false):
		# Design §12: a failure names the preset and config version, the seed, the pins it was
		# carrying, and the invariant that failed. No silent skip, relaxation or partial route.
		var failure := {"code": "generation_failed",
			"message": "the resolved configuration did not build: %s" % str(
				route.get("errors", [])),
			"preset": str(resolved.preset),
			"ride_config_version": int(resolved.ride_config_version),
			"config_hash": str(resolved.config_hash),
			"seed": seed_value,
			"pins": pins,
			"errors": route.get("errors", PackedStringArray()),
			"failure": route.get("failure", {})}
		return {"ok": false, "route": route, "resolved_config": resolved, "plan": {},
			"errors": [failure], "report": report}
	return {"ok": true, "route": route, "resolved_config": resolved,
		"plan": route.get("terrain_story_plan", {}).get("plan", {}), "errors": [],
		"report": report}


## The certification seam: build a seed from an explicitly supplied planner decision set.
## Production always passes `RidePlanner.resolve(seed_value)`; tests use this to place a draw at
## a range extreme and prove the whole range is feasible, without a runtime candidate loop.
## Single use: `decisions.streams` holds live generators that `Terrain.generate()` and `_plan()`
## advance, so a second build off the same dictionary is a different ride — resolve again for
## a replay (see generator_material_tests.gd for the idiom).
static func build_with_decisions(seed_value: int, decisions: Dictionary) -> Dictionary:
	var terrain: Dictionary = Terrain.generate(decisions.streams[RidePlanner.STREAM_TERRAIN])
	var plan := _plan(terrain, decisions)
	if plan.has("ok") and not plan.ok:
		return plan
	var initial_state := _initial_state(plan.station)
	var compiled := RideProgram.compile(plan, initial_state)
	if not compiled.get("ok", false):
		return compiled
	var settings: Variant = compiled.get("settings")
	if not settings is Dictionary:
		return _failure("ride program omitted integration settings")
	settings = settings.duplicate(true)
	settings["step_s"] = INTEGRATION_STEP_S
	settings["measure_dense_output"] = true
	var accepted_integrations := 0
	var trajectory := Motion.integrate(initial_state, compiled.get("spans", []), settings)
	if not trajectory.get("ok", false):
		return _failure("motion integration failed", trajectory.get("errors", []))
	accepted_integrations += 1
	var accepted: Dictionary = compiled.duplicate(true)
	accepted["generation_stats"] = {
		"accepted_integrations": accepted_integrations,
		"planning_integrations": int(plan.terrain_frame.planning.planning_integrations),
		"repair_count": 0,
	}
	return RouteContract.build(seed_value, terrain, initial_state, plan, accepted, trajectory)


static func _plan(terrain: Dictionary, decisions: Dictionary) -> Dictionary:
	var inward_2d: Vector2 = terrain.edge_normal.normalized()
	var along_2d := Vector2(-inward_2d.y, inward_2d.x)
	var inward := Vector3(inward_2d.x, 0.0, inward_2d.y)
	var along := Vector3(along_2d.x, 0.0, along_2d.y)
	# The three placement draws are the one randomness outside `ride_planner.gd`'s certified
	# target draws: they are drawn here, on the planner's placement stream, and certified only by
	# the fifteen-seed fleet gate (smoke + generator_material_tests), not at range extremes. All
	# three are published in `plan.decisions` so a refusal carries its placement provenance.
	var placement_rng: RandomNumberGenerator = decisions.streams[RidePlanner.STREAM_PLACEMENT]
	var side := -1 if placement_rng.randf() < 0.5 else 1
	var along_m := placement_rng.randf_range(60.0, 120.0)
	var placement_u := placement_rng.randf()
	var sequence: Array = decisions.sequence
	var targets: Dictionary = decisions.targets
	var story := {"sequence": sequence, "targets": targets}
	var roles := _material_roles(sequence)
	var dive_role: Dictionary = _role_by_id(roles, "outward-dive")
	var dive_intent: Dictionary = dive_role.terrain
	var tunnel_length_m: Vector2 = _role_by_id(roles, "tunnel-lsm3").length_m
	# P - preflight. One integration of the authored prefix, used only to choose the yaw frame,
	# to prove the terrain can host a dive at all, and to derive the closure target below.
	var preflight := _capability_footprint(RideProgram.terrain_story_capability(side, story))
	if not preflight.ok:
		return preflight
	var apron_width_m := float(terrain.apron_width)
	var shelf_edge_m := apron_width_m + float(terrain.face_width)
	var terrain_dive_span_m := _terrain_dive_span_m(shelf_edge_m, apron_width_m)
	var minimum_total_span_m := shelf_edge_m \
		+ DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M.x + TUNNEL_EXIT_PLAIN_OVERSHOOT_M
	var outward_local := _outward_local(
		preflight, dive_intent, terrain_dive_span_m, minimum_total_span_m)
	if outward_local == Vector2.ZERO:
		return _failure("terrain story capability has no yaw solution that crosses the escarpment")
	var footprint := _terrain_footprint(
		terrain, preflight, inward, along, side, along_m, outward_local)
	if not is_finite(float(footprint.dive_edge_span_m)) \
			or not is_finite(float(footprint.tunnel_edge_span_m)) \
			or float(footprint.dive_edge_span_m) <= 0.0 \
			or float(footprint.tunnel_edge_span_m) <= 0.0:
		return _failure("terrain story capability has a non-outward native edge footprint")
	var entry_band := _entry_edge_aim_band(shelf_edge_m, apron_width_m,
		float(footprint.dive_edge_span_m), float(footprint.tunnel_edge_span_m))
	if entry_band.x > entry_band.y:
		return _failure("terrain apron cannot host the native dive footprint", [{
			"entry_edge_aim_band_m": entry_band,
			"native_dive_edge_span_m": footprint.dive_edge_span_m,
			"native_tunnel_edge_span_m": footprint.tunnel_edge_span_m,
		}])
	# S - the closure solve. The preflight placement is what turns the summit AGL band into a
	# station-local rise band: the station height is a maximum of clearance terms none of the four
	# controls can move, so the aim band is that band translated through the height this very
	# terrain imposes. Both placements below are evaluations of one closed form, not a search.
	var preflight_place := _place_station(terrain, inward, footprint, preflight,
		lerpf(entry_band.x, entry_band.y, placement_u))
	var solved := RideProgram.terrain_story_capability(side, story, _closure_target(
		footprint, outward_local, shelf_edge_m, apron_width_m, terrain_dive_span_m, entry_band,
		tunnel_length_m, float(preflight.role_13.offset_m.y),
		float(preflight_place.summit_track_agl_m), dive_role.length_m))
	var accepted := _capability_footprint(solved)
	if not accepted.ok:
		return accepted
	# F - placement. The accepted chord must still choose the yaw solution the target was aimed
	# along; a different branch would measure the closure on an axis the ride is not built in.
	var accepted_local := _outward_local(
		accepted, dive_intent, terrain_dive_span_m, minimum_total_span_m)
	if accepted_local == Vector2.ZERO:
		return _failure("the accepted prefix closure has no yaw solution", [], {
			"stage": "prefix-closure", "preflight_outward_local": outward_local})
	if accepted_local.dot(outward_local) < YAW_SOLUTION_AGREEMENT_DOT:
		return _failure("the accepted prefix closure changes the yaw solution", [], {
			"stage": "prefix-closure", "preflight_outward_local": outward_local,
			"accepted_outward_local": accepted_local})
	footprint = _terrain_footprint(terrain, accepted, inward, along, side, along_m, outward_local)
	entry_band = _entry_edge_aim_band(shelf_edge_m, apron_width_m,
		float(footprint.dive_edge_span_m), float(footprint.tunnel_edge_span_m))
	if entry_band.x > entry_band.y:
		return _failure("the accepted prefix closure leaves no placement with its margins", [], {
			"stage": "prefix-closure", "entry_edge_aim_band_m": entry_band,
			"native_dive_edge_span_m": footprint.dive_edge_span_m,
			"native_tunnel_edge_span_m": footprint.tunnel_edge_span_m,
			"closure": solved.get("closure_plan", {})})
	var target_dive_entry_edge_m := lerpf(entry_band.x, entry_band.y, placement_u)
	var placement := _place_dive(
		terrain, inward, footprint, accepted, target_dive_entry_edge_m)
	var summit_track_agl_m := float(placement.summit_track_agl_m)
	if summit_track_agl_m < SUMMIT_TRACK_AGL_BAND_M.x \
			or summit_track_agl_m > SUMMIT_TRACK_AGL_BAND_M.y:
		return _failure("the placed prefix leaves the summit track AGL band", [], {
			"stage": "prefix-closure", "summit_track_agl_m": summit_track_agl_m,
			"summit_track_agl_band_m": SUMMIT_TRACK_AGL_BAND_M,
			"dive_entry_edge_m": target_dive_entry_edge_m,
			"closure": solved.get("closure_plan", {})})
	var up := Vector3.UP
	var tangent: Vector3 = footprint.tangent
	var right: Vector3 = footprint.right
	var station_position: Vector3 = placement.station_position_m
	var exit_fraction := float(placement.dive_exit_edge_m) / apron_width_m
	var station_edge_m := Terrain.edge_distance(
		terrain, station_position.x, station_position.z)
	var maximum_opener_edge_m := -INF
	var opener_positions: PackedVector3Array = accepted.station_opener.positions_m
	var opener_rider_up: PackedVector3Array = accepted.station_opener.rider_up
	for sample_index in opener_positions.size():
		var native_position: Vector3 = opener_positions[sample_index]
		var world_position := station_position + tangent * native_position.x \
			+ up * native_position.y + right * native_position.z
		var native_up: Vector3 = opener_rider_up[sample_index]
		var world_up := tangent * native_up.x + up * native_up.y + right * native_up.z
		var lower_spine := world_position - world_up * LOWER_SPINE_SURFACE_OFFSET_M
		var edge_m := Terrain.edge_distance(terrain, lower_spine.x, lower_spine.z)
		if not world_position.is_finite() or not world_up.is_finite() or not is_finite(edge_m):
			return _failure("terrain story capability has a non-finite station/opener sample")
		maximum_opener_edge_m = maxf(maximum_opener_edge_m, edge_m)
	if maximum_opener_edge_m >= 0.0:
		return _failure("planned station/opener corridor does not remain on the plain", [{
			"maximum_opener_edge_m": maximum_opener_edge_m,
			"station_edge_m": station_edge_m,
		}])
	var planning := {
		"capability_id": str(solved.get("capability_id", "")),
		# Two prefix integrations at the production step: the preflight that chooses the frame,
		# and the accepted closure. The solve's own evaluations are coarse and tail-only, and are
		# reported by the closure plan rather than counted here.
		"planning_integrations": int(preflight.planning_integrations)
			+ int(solved.get("planning_integrations", 0)),
		"station_edge_distance_m": station_edge_m,
		"station_opener_maximum_edge_m": maximum_opener_edge_m,
		"sampled_station_opener_points": opener_positions.size(),
		"shelf_edge_distance_m": shelf_edge_m,
		"native_dive_edge_span_m": footprint.dive_edge_span_m,
		"native_tunnel_edge_span_m": footprint.tunnel_edge_span_m,
		"dive_exit_apron_fraction": exit_fraction,
		"dive_entry_edge_m": placement.dive_entry_edge_m,
		"dive_exit_edge_m": placement.dive_exit_edge_m,
		"tunnel_exit_edge_m": placement.tunnel_exit_edge_m,
		"summit_track_agl_m": summit_track_agl_m,
		"sampled_dive_points": accepted.dive_footprint.positions_m.size(),
		"planned_minimum_centerline_agl_m": placement.minimum_centerline_agl_m,
		"planned_minimum_lower_spine_agl_m": placement.minimum_lower_spine_agl_m,
		"closure": solved.get("closure_plan", {}),
		"scale": solved.get("scale", {}).duplicate(true),
	}
	var station := {"position_m": station_position, "tangent": tangent, "up": up}
	return {
		"schema_version": PLAN_SCHEMA_VERSION,
		"preset_id": PRESET_ID,
		"decisions": {"station_side": side, "station_along_m": along_m,
			"dive_entry_aim_u": placement_u, "dive_exit_apron_fraction": exit_fraction,
			"targets": targets.duplicate(true), "draws": decisions.draws.duplicate(true)},
		"terrain_frame": {"apron_origin_m": inward * float(terrain.edge_offset), "inward": inward,
			"along": along, "up": up, "right": right,
			"shelf_height_m": float(terrain.relief), "planning": planning},
		"station": station,
		"corridor": {"approach_length_m": APPROACH_LENGTH_M, "capture_length_m": 80.0,
			"brake_length_m": 150.0,
			"half_width_m": RideReturnSolve.CAPTURE_HALF_WIDTH_M,
			"half_height_m": RideReturnSolve.CAPTURE_HALF_HEIGHT_M,
			"entry_speed_mps": RideReturnSolve.CAPTURE_ENTRY_SPEED_MPS},
		"route_length_m": RideReturnSolve.RETURN_TOTAL_LENGTH_BAND_M,
		"roles": roles,
	}


## Closed-form placement, one evaluation, no search. Edge distance is exact along `inward` (the
## wobble is a function of the along-edge coordinate alone), so sliding the station until the dive
## entry lands on `entry_edge_m` is arithmetic; the station height is then the highest of the
## clearance terms every part of the ride imposes, and the summit AGL that falls out is checked by
## the caller. Which term binds is measured, not assumed: re-measured on the fifteen-seed fleet
## with the rim aim (2026-08-15), the dive corridor still never binds - 6.9 to 13.9 m of slack
## sits under it - and the height is set by the summit aim itself on 7 seeds, the station/opener
## lower spine on 7, and the reserved terminal approach on 1. All of them are functions of the
## head and the terrain, which is why the closure can treat `summit_agl - rise` as a constant.
static func _place_station(terrain: Dictionary, inward: Vector3, footprint: Dictionary,
	parts: Dictionary, entry_edge_m: float
) -> Dictionary:
	var tangent: Vector3 = footprint.tangent
	var right: Vector3 = footprint.right
	var world_entry_offset: Vector3 = footprint.world_entry_offset
	var dive_footprint: Dictionary = parts.dive_footprint
	var positions: PackedVector3Array = dive_footprint.positions_m
	var rider_up: PackedVector3Array = dive_footprint.rider_up
	var opener_positions: PackedVector3Array = parts.station_opener.positions_m
	var opener_up: PackedVector3Array = parts.station_opener.rider_up
	var station_sample_count := int(parts.station_opener.station_sample_count)
	var station_position: Vector3 = footprint.station_anchor \
		+ inward * (entry_edge_m - float(footprint.entry_edge_m))
	var entry_position := station_position \
		+ Vector3(world_entry_offset.x, 0.0, world_entry_offset.z)
	var entry_surface_m := Terrain.height(terrain, entry_position.x, entry_position.z)
	var required_station_y := entry_surface_m + _inner_band(SUMMIT_TRACK_AGL_BAND_M).x \
		- world_entry_offset.y
	for sample_index in positions.size():
		var native_position: Vector3 = positions[sample_index]
		var world_offset := tangent * native_position.x + Vector3.UP * native_position.y \
			+ right * native_position.z
		var center := station_position + world_offset
		required_station_y = maxf(required_station_y,
			Terrain.height(terrain, center.x, center.z) + DIVE_CENTERLINE_CLEARANCE_M \
			- world_offset.y)
		var native_up: Vector3 = rider_up[sample_index]
		var world_up := tangent * native_up.x + Vector3.UP * native_up.y \
			+ right * native_up.z
		var lower_offset := world_offset - world_up * LOWER_SPINE_SURFACE_OFFSET_M
		var lower := station_position + lower_offset
		required_station_y = maxf(required_station_y,
			Terrain.height(terrain, lower.x, lower.z) + DIVE_LOWER_SPINE_CLEARANCE_M \
			- lower_offset.y)
	for sample_index in opener_positions.size():
		var native_position: Vector3 = opener_positions[sample_index]
		var world_offset := tangent * native_position.x + Vector3.UP * native_position.y \
			+ right * native_position.z
		var native_up: Vector3 = opener_up[sample_index]
		var world_up := tangent * native_up.x + Vector3.UP * native_up.y \
			+ right * native_up.z
		var lower_offset := world_offset - world_up * LOWER_SPINE_SURFACE_OFFSET_M
		var lower := station_position + lower_offset
		var required_clearance := STATION_LOWER_SPINE_CLEARANCE_M \
			if sample_index < station_sample_count else DIVE_LOWER_SPINE_CLEARANCE_M
		required_station_y = maxf(required_station_y,
			Terrain.height(terrain, lower.x, lower.z) \
			+ required_clearance - lower_offset.y)
	# The reserved terminal approach is the one piece of the ride whose ground the placement
	# never sampled: the brakes and capture arrive along it, level with the station frame,
	# but they are solved long after placement. Sampling the reserved line here keeps that
	# corridor above terrain by the station's own clearance instead of leaving it to luck.
	var approach_samples := maxi(1, ceili(APPROACH_LENGTH_M / APPROACH_SAMPLE_STEP_M))
	for sample_index in approach_samples + 1:
		var back_m := APPROACH_LENGTH_M * float(sample_index) / approach_samples
		var approach := station_position - tangent * back_m
		required_station_y = maxf(required_station_y,
			Terrain.height(terrain, approach.x, approach.z) \
			+ STATION_LOWER_SPINE_CLEARANCE_M + LOWER_SPINE_SURFACE_OFFSET_M)
	station_position.y = required_station_y
	return {"station_position_m": station_position,
		"summit_track_agl_m": required_station_y + world_entry_offset.y - entry_surface_m}


## The same placement, plus the dive observations an accepted plan publishes. The preflight only
## reads the summit AGL, so it calls `_place_station` directly and skips this second terrain scan.
static func _place_dive(terrain: Dictionary, inward: Vector3, footprint: Dictionary,
	parts: Dictionary, entry_edge_m: float
) -> Dictionary:
	var station := _place_station(terrain, inward, footprint, parts, entry_edge_m)
	var station_position: Vector3 = station.station_position_m
	var tangent: Vector3 = footprint.tangent
	var right: Vector3 = footprint.right
	var world_entry_offset: Vector3 = footprint.world_entry_offset
	var placement := _dive_placement_observation(terrain, station_position, tangent, right,
		world_entry_offset, parts.dive_footprint)
	placement["summit_track_agl_m"] = station.summit_track_agl_m
	return placement


## The placement observations one prefix capability must publish. Validated once on the preflight
## and once on the accepted closure, so a malformed footprint cannot reach either placement.
static func _capability_footprint(capability: Dictionary) -> Dictionary:
	if not capability.get("ok", false):
		return capability if capability.has("failure") \
			else _failure("terrain story capability failed", capability.get("errors", []))
	var role_13: Variant = capability.get("role_13_entry")
	var station_opener: Variant = capability.get("station_opener")
	var dive_footprint: Variant = capability.get("dive_footprint")
	if not role_13 is Dictionary or not station_opener is Dictionary \
			or not dive_footprint is Dictionary \
			or not role_13.get("offset_m") is Vector3 \
			or not role_13.get("tangent") is Vector3 \
			or not role_13.get("rider_up") is Vector3 \
			or not role_13.offset_m.is_finite() or not role_13.tangent.is_finite() \
			or not role_13.rider_up.is_finite() \
			or not is_finite(float(role_13.get("speed_mps", NAN))) \
			or not station_opener.get("positions_m") is PackedVector3Array \
			or not station_opener.get("rider_up") is PackedVector3Array \
			or station_opener.positions_m.is_empty() \
			or station_opener.positions_m.size() != station_opener.rider_up.size() \
			or int(station_opener.get("station_sample_count", 0)) <= 0 \
			or int(station_opener.station_sample_count) >= station_opener.positions_m.size() \
			or not dive_footprint.get("dive_exit_offset_m") is Vector3 \
			or not dive_footprint.get("tunnel_exit_offset_m") is Vector3 \
			or not dive_footprint.get("tunnel_exit_step_m") is Vector3 \
			or not dive_footprint.get("positions_m") is PackedVector3Array \
			or not dive_footprint.get("rider_up") is PackedVector3Array \
			or not dive_footprint.dive_exit_offset_m.is_finite() \
			or not dive_footprint.tunnel_exit_offset_m.is_finite() \
			or not dive_footprint.tunnel_exit_step_m.is_finite() \
			or dive_footprint.positions_m.is_empty() \
			or dive_footprint.positions_m.size() != dive_footprint.rider_up.size():
		return _failure("terrain story capability omitted finite placement observations")
	if str(capability.get("capability_id", "")).is_empty() \
			or int(capability.get("planning_integrations", 0)) != 1 \
			or not capability.get("scale") is Dictionary:
		return _failure("terrain story capability omitted its versioned scale contract")
	return {"ok": true, "role_13": role_13, "station_opener": station_opener,
		"dive_footprint": dive_footprint,
		"planning_integrations": int(capability.planning_integrations)}


## The yaw solution for one footprint. The native chord is fixed, so rotating the frame until its
## outward projection is the terrain's own desired dive span has exactly two solutions; take the
## one whose dive-entry tangent faces outward, which targets a real apron exit and crosses the
## whole escarpment, and which leaves the station/opener corridor furthest back on the plain.
## ZERO when neither solution can host this footprint on this terrain.
static func _outward_local(parts: Dictionary, dive_intent: Dictionary,
	terrain_dive_span_m: float, minimum_total_span_m: float
) -> Vector2:
	var entry_offset_m: Vector3 = parts.role_13.offset_m
	var dive_exit_offset_m: Vector3 = parts.dive_footprint.dive_exit_offset_m
	var tunnel_exit_offset_m: Vector3 = parts.dive_footprint.tunnel_exit_offset_m
	var dive_delta := Vector2(dive_exit_offset_m.x - entry_offset_m.x,
		dive_exit_offset_m.z - entry_offset_m.z)
	var terrain_delta := Vector2(tunnel_exit_offset_m.x - entry_offset_m.x,
		tunnel_exit_offset_m.z - entry_offset_m.z)
	var entry_direction := Vector2(parts.role_13.tangent.x, parts.role_13.tangent.z)
	var maximum_cross_ratio := float(dive_intent.maximum_cross_to_outward_ratio)
	var desired_dive_span_m := maxf(terrain_dive_span_m,
		dive_delta.length() / sqrt(1.0 + maximum_cross_ratio ** 2))
	if dive_delta.length_squared() <= desired_dive_span_m * desired_dive_span_m \
			or desired_dive_span_m < dive_intent.outward_delta_m.x \
			or desired_dive_span_m > dive_intent.outward_delta_m.y \
			or entry_direction.length_squared() <= 0.000001:
		return Vector2.ZERO
	var dive_direction := dive_delta.normalized()
	var parallel := desired_dive_span_m / dive_delta.length()
	var perpendicular := sqrt(1.0 - parallel * parallel)
	var normal := Vector2(-dive_direction.y, dive_direction.x)
	entry_direction = entry_direction.normalized()
	var outward_local := Vector2.ZERO
	var best_opener_clearance_m := -INF
	for candidate: Vector2 in [dive_direction * parallel + normal * perpendicular,
			dive_direction * parallel - normal * perpendicular]:
		var candidate_right := Vector2(-candidate.y, candidate.x)
		var outward_delta_m := dive_delta.dot(candidate)
		var cross_ratio := absf(dive_delta.dot(candidate_right)) \
			/ maxf(outward_delta_m, 0.000001)
		if candidate.dot(entry_direction) < 0.25 or outward_delta_m <= 0.0 \
				or cross_ratio > maximum_cross_ratio + 0.000001 \
				or terrain_delta.dot(candidate) < minimum_total_span_m \
				or terrain_delta.normalized().dot(candidate) < 0.75:
			continue
		# Measured 2026-08-19: maximising the corridor's *minimum* projection is what keeps the
		# station/opener corridor furthest back on the plain — on every fleet seed the opposite
		# reduction (minimising the maximum) brought the corridor 85-145 m closer to the edge.
		var opener_clearance_m := INF
		for position: Vector3 in parts.station_opener.positions_m:
			opener_clearance_m = minf(opener_clearance_m,
				Vector2(position.x - entry_offset_m.x,
					position.z - entry_offset_m.z).dot(candidate))
		if opener_clearance_m > best_opener_clearance_m:
			best_opener_clearance_m = opener_clearance_m
			outward_local = candidate
	return outward_local


## One footprint measured in terrain: the world frame `outward_local` induces, the station anchor
## it hangs from, and the native edge spans — dive entry to dive exit, dive exit to tunnel exit —
## the placement works in. Every span here is invariant to the station shift, so measuring them
## once on the unshifted anchor is exact. The projections are the same two runs in the solve's own
## straight-line measure; the difference between each pair is the edge wobble across that span.
static func _terrain_footprint(terrain: Dictionary, parts: Dictionary, inward: Vector3,
	along: Vector3, side: int, along_m: float, outward_local: Vector2
) -> Dictionary:
	var up := Vector3.UP
	var entry_offset_m: Vector3 = parts.role_13.offset_m
	var dive_exit_offset_m: Vector3 = parts.dive_footprint.dive_exit_offset_m
	var tunnel_exit_offset_m: Vector3 = parts.dive_footprint.tunnel_exit_offset_m
	var tunnel_step_m: Vector3 = parts.dive_footprint.tunnel_exit_step_m
	var outward := -inward
	var outward_right := outward.cross(up).normalized()
	var tangent := (outward * outward_local.x - outward_right * outward_local.y).normalized()
	var right := tangent.cross(up).normalized()
	var world_entry_offset := tangent * entry_offset_m.x + up * entry_offset_m.y \
		+ right * entry_offset_m.z
	var station_anchor := inward * float(terrain.edge_offset) + along * (side * along_m)
	var entry := station_anchor + Vector3(world_entry_offset.x, 0.0, world_entry_offset.z)
	var dive_exit := station_anchor + tangent * dive_exit_offset_m.x \
		+ right * dive_exit_offset_m.z
	var tunnel_exit := station_anchor + tangent * tunnel_exit_offset_m.x \
		+ right * tunnel_exit_offset_m.z
	var entry_edge_m := Terrain.edge_distance(terrain, entry.x, entry.z)
	var dive_exit_edge_m := Terrain.edge_distance(terrain, dive_exit.x, dive_exit.z)
	var tunnel_exit_edge_m := Terrain.edge_distance(terrain, tunnel_exit.x, tunnel_exit.z)
	return {"tangent": tangent, "right": right, "station_anchor": station_anchor,
		"world_entry_offset": world_entry_offset, "entry_edge_m": entry_edge_m,
		"dive_edge_span_m": entry_edge_m - dive_exit_edge_m,
		"tunnel_edge_span_m": dive_exit_edge_m - tunnel_exit_edge_m,
		"dive_projection_m": Vector2(dive_exit_offset_m.x - entry_offset_m.x,
			dive_exit_offset_m.z - entry_offset_m.z).dot(outward_local),
		"tunnel_projection_m": Vector2(tunnel_exit_offset_m.x - dive_exit_offset_m.x,
			tunnel_exit_offset_m.z - dive_exit_offset_m.z).dot(outward_local),
		"tunnel_step_projection_m": Vector2(tunnel_step_m.x, tunnel_step_m.z).dot(outward_local)}


## The middle `AIM_BAND_INTERIOR_FRACTION` of a band. An empty band stays inverted, so a caller
## detects an infeasible aim the same way it detects an infeasible band.
static func _inner_band(band: Vector2) -> Vector2:
	var inset := 0.5 * (1.0 - AIM_BAND_INTERIOR_FRACTION) * (band.y - band.x)
	return Vector2(band.x + inset, band.y - inset)


## The two edge bands every placement and closure aim is built from: where the dive entry may sit
## behind the shelf edge, and where its exit may sit on the apron. Each is the declared band inset
## by the margin `smoke.gd` certifies on the fleet, so an accepted placement carries that margin.
static func _entry_edge_limits(shelf_edge_m: float) -> Vector2:
	return Vector2(
		shelf_edge_m + DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M.x + DIVE_ENTRY_EDGE_MARGIN_M,
		shelf_edge_m + DIVE_ENTRY_PLATEAU_CLEARANCE_BAND_M.y - DIVE_ENTRY_EDGE_MARGIN_M)


static func _exit_edge_limits(apron_width_m: float) -> Vector2:
	return Vector2(DIVE_EXIT_APRON_BAND.x + DIVE_EXIT_APRON_MARGIN,
		DIVE_EXIT_APRON_BAND.y - DIVE_EXIT_APRON_MARGIN) * apron_width_m


## The outward run the terrain wants from the dive: the chord that lands the exit on its apron
## floor while the entry sits on the plateau band's own floor, less the aim half-width, so the
## whole chord aim band stays under that floor and the entry's feasible floor is the plateau band
## rather than the apron. That is issue 22 in one line - where this constant puts the chord is
## where the dive starts relative to the rim. `_outward_local` rotates the frame until the native
## chord projects exactly this far, so the ride's shape does not change when it moves; only the
## angle it meets the escarpment at, and with it the ground the entry sits over, do.
static func _terrain_dive_span_m(shelf_edge_m: float, apron_width_m: float) -> float:
	return _entry_edge_limits(shelf_edge_m).x - _exit_edge_limits(apron_width_m).x \
		- DIVE_SPAN_AIM_HALF_WIDTH_M


## The dive-entry edge distances the placement may draw from: both limit bands, offset by the run
## the dive itself covers, intersected with the run the tunnel needs to clear the plain boundary,
## and narrowed to the rim end of what is left. Aiming at the rim rather than the middle is issue
## 22's fix; the cushion means the certified entry margin is aimed above, never grazed. The one
## honest narrowing: a feasible band narrower than the cushion now refuses where the inner band
## would have placed. On the fleet that band runs 18-22 m wide, so the path is unreached, not
## unreachable.
static func _entry_edge_aim_band(shelf_edge_m: float, apron_width_m: float,
	dive_edge_span_m: float, tunnel_edge_span_m: float
) -> Vector2:
	var entry_limits := _entry_edge_limits(shelf_edge_m)
	var exit_limits := _exit_edge_limits(apron_width_m)
	var rim_m := maxf(entry_limits.x, exit_limits.x + dive_edge_span_m)
	var ceiling_m := minf(entry_limits.y, minf(exit_limits.y + dive_edge_span_m,
		dive_edge_span_m + tunnel_edge_span_m - TUNNEL_EXIT_PLAIN_OVERSHOOT_M))
	return Vector2(rim_m + DIVE_ENTRY_RIM_AIM_M.x,
		minf(ceiling_m, rim_m + DIVE_ENTRY_RIM_AIM_M.y))


## The closure the prefix must hit, built only from terrain-and-frame quantities: the plateau and
## apron bands, the tunnel's plain overshoot and role length, the summit AGL band and the record
## band. Two corrections turn those terrain measurements into the station-local quantities the
## solve actually observes — the edge wobble across each span (edge distance is the wobbled signed
## distance, the residual a straight projection), and the one production step between the
## residual's terminal tunnel sample and the published pre-seam one the placement consumes. The
## summit band is translated into rise space through the height this terrain imposes: the station
## height is a maximum of clearance terms no control can move, so `summit_agl - rise` is the
## constant that maps one to the other.
static func _closure_target(footprint: Dictionary, outward_local: Vector2, shelf_edge_m: float,
	apron_width_m: float, terrain_dive_span_m: float, entry_band: Vector2,
	tunnel_length_m: Vector2, summit_rise_m: float, summit_agl_m: float,
	dive_length_m: Vector2
) -> Dictionary:
	var dive_wobble_m: float = float(footprint.dive_edge_span_m) \
		- float(footprint.dive_projection_m)
	var tunnel_offset_m: float = float(footprint.tunnel_step_projection_m) \
		- float(footprint.tunnel_edge_span_m) + float(footprint.tunnel_projection_m)
	# The dive's outward run is what makes `_entry_edge_aim_band` non-empty: it has to be long
	# enough to reach the apron band from the plateau band and short enough not to overshoot it,
	# which is exactly the difference of the two limit bands.
	var entry_limits := _entry_edge_limits(shelf_edge_m)
	var exit_limits := _exit_edge_limits(apron_width_m)
	var dive_aim := Vector2(
		maxf(terrain_dive_span_m - DIVE_SPAN_AIM_HALF_WIDTH_M, entry_limits.x - exit_limits.y),
		minf(terrain_dive_span_m + DIVE_SPAN_AIM_HALF_WIDTH_M, entry_limits.y - exit_limits.x))
	var tunnel_aim := Vector2(
		entry_band.y - dive_aim.x + TUNNEL_EXIT_PLAIN_OVERSHOOT_M, tunnel_length_m.y)
	return {
		"outward_local": outward_local,
		"dive_edge_span_m": dive_aim - Vector2.ONE * dive_wobble_m,
		"tunnel_edge_span_m": tunnel_aim + Vector2.ONE * tunnel_offset_m,
		"summit_rise_m": _inner_band(SUMMIT_TRACK_AGL_BAND_M)
			+ Vector2.ONE * (summit_rise_m - summit_agl_m),
		"record_exit_speed_mps": _inner_band(RECORD_EXIT_SPEED_BAND_MPS),
		# The one aim that is a role band rather than a terrain measurement: the dive's built arc
		# has to satisfy the same declared band the route contract judges, so the closure aims at
		# that band inset rather than at a proxy of it.
		"dive_arc_m": dive_length_m + Vector2(DIVE_ARC_AIM_MARGIN_M, -DIVE_ARC_AIM_MARGIN_M),
	}


static func _dive_placement_observation(
	terrain: Dictionary, station_position: Vector3, tangent: Vector3, right: Vector3,
	world_entry_offset: Vector3, footprint: Dictionary
) -> Dictionary:
	var positions: PackedVector3Array = footprint.positions_m
	var rider_up: PackedVector3Array = footprint.rider_up
	var minimum_centerline_agl_m := INF
	var minimum_lower_spine_agl_m := INF
	for sample_index in positions.size():
		var native_position: Vector3 = positions[sample_index]
		var world_offset := tangent * native_position.x + Vector3.UP * native_position.y \
			+ right * native_position.z
		var center := station_position + world_offset
		minimum_centerline_agl_m = minf(minimum_centerline_agl_m,
			center.y - Terrain.height(terrain, center.x, center.z))
		var native_up: Vector3 = rider_up[sample_index]
		var world_up := tangent * native_up.x + Vector3.UP * native_up.y \
			+ right * native_up.z
		var lower := center - world_up * LOWER_SPINE_SURFACE_OFFSET_M
		minimum_lower_spine_agl_m = minf(minimum_lower_spine_agl_m,
			lower.y - Terrain.height(terrain, lower.x, lower.z))
	var entry_position := station_position \
		+ Vector3(world_entry_offset.x, 0.0, world_entry_offset.z)
	var dive_exit_offset: Vector3 = footprint.dive_exit_offset_m
	var tunnel_exit_offset: Vector3 = footprint.tunnel_exit_offset_m
	var dive_exit := station_position + tangent * dive_exit_offset.x \
		+ right * dive_exit_offset.z
	var tunnel_exit := station_position + tangent * tunnel_exit_offset.x \
		+ right * tunnel_exit_offset.z
	return {
		"station_position_m": station_position,
		"dive_entry_edge_m": Terrain.edge_distance(
			terrain, entry_position.x, entry_position.z),
		"dive_exit_edge_m": Terrain.edge_distance(terrain, dive_exit.x, dive_exit.z),
		"tunnel_exit_edge_m": Terrain.edge_distance(terrain, tunnel_exit.x, tunnel_exit.z),
		"minimum_centerline_agl_m": minimum_centerline_agl_m,
		"minimum_lower_spine_agl_m": minimum_lower_spine_agl_m,
	}


## The declared roles of one plan, in the planner's drawn order. Role identity, length band and
## terrain intents come from the one table below; the per-seed resolved targets stay in
## `plan.decisions.targets` with their draw provenance, so the declared role bands remain a
## claim about the built ride rather than a mixture of bands and drawn scalars.
static func _material_roles(sequence: Array = []) -> Array:
	var roles: Array = []
	for role_id in (sequence if not sequence.is_empty() else RidePlanner.canonical_role_ids()):
		roles.append(_material_role(str(role_id)))
	return roles


static func _role_by_id(roles: Array, role_id: String) -> Dictionary:
	for role: Dictionary in roles:
		if str(role.id) == role_id:
			return role
	return {}


static func _material_role(role_id: String) -> Dictionary:
	match role_id:
		"station-launch":
			return _role("station-launch", "station_launch", Vector2(140.0, 220.0),
				{"exit_speed_mps": Vector2(75.0, 80.0)}, [], {}, 1)
		"opener-twisted-drop":
			return _role("opener-twisted-drop", "twisted_drop", Vector2(540.0, 700.0),
				{"exit_speed_mps": Vector2(70.0, 82.0),
					"vertical_excursion_m": Vector2(70.0, 115.0)})
		"opener-teardrop":
			return _role("opener-teardrop", "teardrop", Vector2(560.0, 720.0),
				{"heading_abs_rad": Vector2(deg_to_rad(110.0), deg_to_rad(190.0))})
		"opener-release":
			return _role("opener-release", "rising_release", Vector2(270.0, 390.0),
				{"height_delta_m": Vector2(25.0, 55.0)})
		"act-one-immelmann":
			return _role("act-one-immelmann", "immelmann", Vector2(370.0, 490.0),
				{"vertical_excursion_m": Vector2(100.0, 110.0)},
				[_phase(&"inverted_apex", {"rider_up_dot": Vector2(-1.0, 0.0),
					"hold_s": Vector2(1.0, 2.2)})])
		"act-one-cutback":
			return _role("act-one-cutback", "cutback", Vector2(270.0, 360.0),
				{"heading_abs_rad": Vector2(deg_to_rad(135.0), deg_to_rad(200.0))},
				[_phase(&"inverted_apex", {"rider_up_dot": Vector2(-1.0, 0.0)})])
		"act-one-loop":
			return _role("act-one-loop", "helical_loop", Vector2(310.0, 420.0),
				{"vertical_excursion_m": Vector2(94.0, 100.0)},
				[_phase(&"inverted_apex", {"rider_up_dot": Vector2(-1.0, 0.0),
					"hold_s": Vector2(1.2, 2.6)})])
		"act-one-airtime":
			return _role("act-one-airtime", "airtime_braid", Vector2(220.0, 310.0))
		"act-one-wave":
			return _role("act-one-wave", "wave_turn", Vector2(200.0, 290.0))
		"climb-lsm2":
			return _role("climb-lsm2", "lsm2_climb", Vector2(520.0, 680.0),
				{"exit_speed_mps": Vector2(14.0, 24.0), "height_delta_m": Vector2(200.0, 225.0),
					"drive_distance_fraction": Vector2(0.65, 0.80)}, [], {}, 2)
		"clifftop-slow-crest":
			return _role("clifftop-slow-crest", "slow_crest", Vector2(35.0, 80.0))
		"clifftop-outward-rim":
			return _role("clifftop-outward-rim", "outward_rim", Vector2(65.0, 120.0), {}, [],
				{"exit_tangent_outward_dot": Vector2(0.25, 1.0)})
		"outward-dive":
			# The 490 m ceiling stays, and measurement says what it is: a rim-speed budget, not a
			# cliff-geometry one. Measured per span on the production integration (2026-08-16),
			# 63% of the role is its 4.64 s pull-out run at 49-70 m/s, and both stories fall the
			# same cliff to 5.4 cm (-247.48 m against -247.42 m), so what a hotter rim entry buys
			# is length: canonical against the act-one optional swap lengthens all eight spans for
			# +2.431 m/s of rim speed, 21.467 m in total - a two-point secant of ~8.83 m per m/s
			# across every difference between the two stories, not a per-span law. Canonical builds
			# 475.604-476.544 m fleet-wide (13.456 m of headroom, ~+1.5 m/s); the swap's
			# 497.43-497.46 m is ~0.84 m/s of rim speed past this ceiling.
			# Adding that arc as a fifth closure residual was built, run and refused (2026-08-16):
			# `docs/superpowers/specs/2026-08-15-prefix-closure-solve-design.md` section 11.
			return _role("outward-dive", "cliff_dive", Vector2(350.0, 490.0),
				{"height_delta_m": Vector2(-250.0, -240.0)}, [],
				{"outward_delta_m": Vector2(70.0, 300.0),
					"maximum_cross_to_outward_ratio": 0.8,
					"minimum_centerline_agl_m": 4.0, "boundary_crossings": [
						{"boundary_id": &"shelf_edge", "from_side": 1, "to_side": -1},
						{"boundary_id": &"face", "from_side": 1, "to_side": -1}],
					"monotonic": PackedStringArray(["outward", "height_down"])})
		"tunnel-lsm3":
			return _role("tunnel-lsm3", "tunnel_lsm3", Vector2(150.0, 220.0), {}, [],
				{"boundary_crossings": [{"boundary_id": &"apron_edge", "from_side": 1,
					"to_side": -1}]}, 3)
		"camelback":
			# The record camelback is longer than the 328 km/h one: the same authored normal-g
			# profile sweeps more track per second at the 340 km/h entry, and the fall lengthens
			# to keep the marquee standing ~250 m above its valley.
			return _role("camelback", "camelback", Vector2(900.0, 1180.0))
		"return-turn-a":
			# Turn-a lengthens and height-a shortens against the old bands: the widened
			# capture-entry corridor lets the passive return carry more speed, and the solve
			# spends it in the loaded arc rather than the first airtime beat.
			return _role("return-turn-a", "return_turn", Vector2(420.0, 620.0))
		"return-height-a":
			return _role("return-height-a", "return_height", Vector2(290.0, 480.0))
		"return-turn-b":
			return _role("return-turn-b", "return_turn", Vector2(430.0, 570.0))
		"return-height-b":
			return _role("return-height-b", "return_height", Vector2(450.0, 590.0))
		"terminal-capture-brakes":
			return _role("terminal-capture-brakes", "terminal_capture_brakes",
				Vector2(200.0, 240.0))
	return {}


static func _role(
	id: String, recipe_id: String, length_m: Vector2, targets: Dictionary = {}, phases: Array = [],
	terrain: Dictionary = {}, propulsion_id: int = 0
) -> Dictionary:
	var role := {"id": id, "recipe_id": recipe_id, "length_m": length_m,
		"targets": targets}
	if not phases.is_empty(): role["phases"] = phases
	if not terrain.is_empty(): role["terrain"] = terrain
	if propulsion_id > 0: role["propulsion_id"] = propulsion_id
	return role


static func _phase(id: StringName, targets: Dictionary) -> Dictionary:
	return {"id": id, "targets": targets}


static func _initial_state(station: Dictionary) -> Dictionary:
	return {
		"position_m": station.position_m,
		"tangent": station.tangent,
		"rider_up": station.up,
		"speed_mps": STATION_SPEED_MPS,
		"distance_m": 0.0,
		"time_s": 0.0,
	}


static func _failure(
	context: String, details: Variant = [], failure: Dictionary = {}
) -> Dictionary:
	var errors := PackedStringArray([context])
	if details is Array or details is PackedStringArray:
		for detail in details:
			errors.append(str(detail))
	if failure.is_empty():
		return {"ok": false, "errors": errors}
	var structured := {"reason": context}
	structured.merge(failure, true)
	return {"ok": false, "errors": errors, "failure": structured}
