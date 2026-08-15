class_name RideGeometryMetrics
extends RefCounted

## Read-only geometric measurement of a published route — the shape half of the audit.
##
## Issue 24 ("FVD++ gets the g's but not the geometry") says the force channels can be right
## while the swept shape is wrong, so nothing here reads a force target: every number is derived
## from positions, tangents, rider-up and roll rate. Four measurements:
##
##   1. seam_roll_continuity — roll-rate jump and roll-acceleration break across every role-window
##      boundary, plus a per-role roll profile that counts roll -> flat -> roll steps (issue 20).
##   2. element_planarity   — least-squares best-fit plane per role window: RMS out-of-plane
##      deviation and how far the fitted plane is tilted off vertical (issue 23).
##   3. shape_ratios        — the numeric silhouette per role window: extents, ratios, headings.
##   4. counterpart_comparison — measured generated loads against the stretched counterpart bands
##      in RideFidelityCounterparts, as within/under/over/evidence-gap labels.
##
## Everything is a pure static function of a route Dictionary and every output is canonical-JSON
## admissible (finite floats or null). These are DIAGNOSTICS, never gates: a helical element is
## expected to be non-planar and this file reports that without judging it. Nothing here promotes
## a source, creates a catalog target, or licenses closing a ride-quality issue.

const Fidelity := preload("res://fidelity.gd")
const Counterparts := preload("res://fidelity_counterparts.gd")
const Verify := preload("res://verify.gd")
const Sampling := preload("res://route_sampling.gd")

const SCHEMA := "ride-geometry-metrics@1"
const COUNTERPART_SCHEMA := "ride-geometry-counterpart-comparison@1"

## Samples on each side of a seam that the roll-acceleration least-squares fit consumes.
const SEAM_WINDOW_SAMPLES := 5
## How many worst offenders each ranking reports.
const WORST_COUNT := 12
## |roll rate| at or below this is "not rolling" for the stepping counter (deg/s).
const FLAT_ROLL_DPS := 2.0
## |bank| at or above this is "banked" — a flat-roll run inside it is a step, not a neutral stretch.
const BANKED_DEG := 10.0
## Out-of-plane RMS as a fraction of the element's bounding diagonal.
const PLANAR_RATIO := 0.02
const QUASI_PLANAR_RATIO := 0.08
## The row the counterpart comparison reads. Row 4 is the train centre (RouteContract.ROW_OFFSETS).
const COUNTERPART_ROW_ID := "row-04"
const COUNTERPART_ROW_OFFSET_M := 6.45
## A counterpart axis quoted as a single number is compared against this diagnostic tolerance.
## It is a labelling convenience for reading the report, NOT a reviewed threshold and NOT a gate.
const SCALAR_BAND_FRACTION := 0.15

const REQUIRED_FIELDS := [
	"positions", "tangents", "ups", "banks", "roll_rates", "times", "distances",
	"speeds", "gesture_windows",
]

## The compiled route publishes gesture/role windows, and several material roles are compiled into
## more than one of them (the cliff dive into five, the camelback into four, the terminal block into
## three). RideFidelityCounterparts is keyed by RideProgram.MATERIAL_ROLE_IDS, so the comparison
## needs this explicit bridge — keyed "story_slot_id/role_id/occurrence". It is validated at
## runtime: an unmapped compiled window and a material role with no window are both reported
## rather than silently dropped, so a generator change that renames a role shows up as a
## mapping gap instead of a wrong number.
const MATERIAL_ROLE_BY_WINDOW := {
	"station-launch/launch/0": "station-launch",
	"opener/twisted-drop/0": "opener-twisted-drop",
	"opener/teardrop/0": "opener-teardrop",
	"opener/release/0": "opener-release",
	"act-one/giant-inversion/0": "act-one-immelmann",
	"act-one/cutback/0": "act-one-cutback",
	"act-one/giant-inversion/1": "act-one-loop",
	"act-one/airtime-hills/0": "act-one-airtime",
	"act-one/wave-turn/0": "act-one-wave",
	"escarpment-climb/lsm2/0": "climb-lsm2",
	"escarpment-climb/unpowered-climb/0": "climb-lsm2",
	"clifftop-suspense/slow-crest/0": "clifftop-slow-crest",
	"clifftop-suspense/outward-rim/0": "clifftop-outward-rim",
	"cliff-dive/commit/0": "outward-dive",
	"cliff-dive/vertical-entry/0": "outward-dive",
	"cliff-dive/core/0": "outward-dive",
	"cliff-dive/pullout/0": "outward-dive",
	"cliff-dive/exit/0": "outward-dive",
	"tunnel-lsm3/core/0": "tunnel-lsm3",
	"marquee-camelback/rise/0": "camelback",
	"marquee-camelback/crest/0": "camelback",
	"marquee-camelback/fall/0": "camelback",
	"marquee-camelback/exit/0": "camelback",
	"raceway-return/turn-a/0": "return-turn-a",
	"raceway-return/height-airtime-a/0": "return-height-a",
	"raceway-return/turn-b/0": "return-turn-b",
	"raceway-return/height-airtime-b/0": "return-height-b",
	"brakes-station-capture/capture/0": "terminal-capture-brakes",
	"brakes-station-capture/brakes/0": "terminal-capture-brakes",
	"brakes-station-capture/station/0": "terminal-capture-brakes",
}


# ---------------------------------------------------------------------------------------------
# 1. Seam roll continuity
# ---------------------------------------------------------------------------------------------

## Roll continuity across every role-window boundary in compiled route order. A coherent roll
## crosses a seam with a small rate jump and a small change of roll acceleration; the stepping
## described in issue 20 shows up as a large jump, a large acceleration break, or a role whose
## roll arrives in several segments separated by flat.
static func seam_roll_continuity(route: Dictionary) -> Dictionary:
	var unavailable := _unavailable(route)
	if not unavailable.is_empty():
		return unavailable
	var windows := role_windows(route)
	var times: PackedFloat32Array = route.times
	var rolls: PackedFloat32Array = route.roll_rates
	var seams := []
	for index in range(1, windows.size()):
		var before: Dictionary = windows[index - 1]
		var after: Dictionary = windows[index]
		var boundary: int = int(after.first)
		if boundary <= 0 or boundary >= times.size():
			continue
		var rate_before := float(rolls[boundary - 1])
		var rate_after := float(rolls[boundary])
		var dt := float(times[boundary]) - float(times[boundary - 1])
		var slope_before: Variant = _slope(
			times, rolls, maxi(0, boundary - SEAM_WINDOW_SAMPLES), boundary - 1
		)
		var slope_after: Variant = _slope(
			times, rolls, boundary, mini(times.size() - 1, boundary + SEAM_WINDOW_SAMPLES - 1)
		)
		var across: Variant = null
		if dt > 0.0:
			across = (rate_after - rate_before) / dt
		var seam := {
			"seam_index": index - 1,
			"boundary_sample": boundary,
			"boundary_time_s": float(times[boundary]),
			"boundary_distance_m": float(route.distances[boundary]),
			"before_window_id": str(before.window_id),
			"after_window_id": str(after.window_id),
			"before_role": str(before.role_id),
			"after_role": str(after.role_id),
			"gesture_boundary": int(before.gesture_index) != int(after.gesture_index),
			"sample_interval_s": dt,
			"roll_rate_before_dps": rate_before,
			"roll_rate_after_dps": rate_after,
			"roll_rate_jump_dps": rate_after - rate_before,
			"roll_acceleration_across_dps2": across,
			"roll_acceleration_before_dps2": slope_before,
			"roll_acceleration_after_dps2": slope_after,
			"roll_acceleration_break_dps2": _break(slope_before, slope_after),
		}
		seams.append(seam)
	return {
		"schema_version": SCHEMA,
		"metric": "seam_roll_continuity",
		"judgement": "report-only",
		"seam_count": seams.size(),
		"window_samples": SEAM_WINDOW_SAMPLES,
		"flat_roll_dps": FLAT_ROLL_DPS,
		"seams": seams,
		"worst_roll_rate_jumps": _worst(seams, "roll_rate_jump_dps"),
		"worst_roll_acceleration_breaks": _worst(seams, "roll_acceleration_break_dps2"),
		"role_roll_profiles": _roll_profiles(route, windows),
	}


## Per-role roll character: how much of the window is not rolling at all, and in how many separate
## segments the roll is delivered. roll_segment_count >= 2 with a large banked_flat_share is the
## roll -> flat -> roll signature.
static func _roll_profiles(route: Dictionary, windows: Array) -> Array:
	var times: PackedFloat32Array = route.times
	var rolls: PackedFloat32Array = route.roll_rates
	var banks: PackedFloat32Array = route.banks
	var profiles := []
	for window: Dictionary in windows:
		var first: int = int(window.first)
		var last: int = int(window.last)
		var total := 0.0
		var flat := 0.0
		var banked_flat := 0.0
		var segments := 0
		var reversals := 0
		var peak := 0.0
		var previous_sign := 0
		var rolling := false
		for index in range(first, last + 1):
			var rate := float(rolls[index])
			peak = maxf(peak, absf(rate))
			var is_flat: bool = absf(rate) <= FLAT_ROLL_DPS
			if is_flat:
				rolling = false
			elif not rolling:
				rolling = true
				segments += 1
			if not is_flat:
				var sign_now: int = 1 if rate > 0.0 else -1
				if previous_sign != 0 and sign_now != previous_sign:
					reversals += 1
				previous_sign = sign_now
			if index < last:
				var dt := float(times[index + 1]) - float(times[index])
				if dt > 0.0:
					total += dt
					if is_flat:
						flat += dt
						if absf(float(banks[index])) >= BANKED_DEG:
							banked_flat += dt
		var divisor := total if total > 0.0 else 1.0
		profiles.append({
			"window_id": str(window.window_id),
			"role_id": str(window.role_id),
			"occurrence": int(window.occurrence),
			"seconds": total,
			"roll_rate_peak_dps": peak,
			"roll_segment_count": segments,
			"roll_reversal_count": reversals,
			"flat_roll_share": flat / divisor if total > 0.0 else 0.0,
			"banked_flat_roll_share": banked_flat / divisor if total > 0.0 else 0.0,
		})
	return profiles


# ---------------------------------------------------------------------------------------------
# 2. Element planarity
# ---------------------------------------------------------------------------------------------

## Least-squares best-fit plane through each role window's track points. Reports how far the
## points leave that plane and how far the plane itself is tilted off vertical.
##
## A camelback, a drop or a hill should live in a near-vertical plane, so a non-zero
## vertical_plane_tilt_deg on a planar element is the sideways tilt issue 23 describes. A loop or
## a helix is genuinely three-dimensional and its fit is meaningless — the record says so in
## planarity_class and tilt_is_meaningful rather than scoring it.
static func element_planarity(route: Dictionary) -> Dictionary:
	var unavailable := _unavailable(route)
	if not unavailable.is_empty():
		return unavailable
	var elements := []
	for window: Dictionary in role_windows(route):
		var record := {
			"window_id": str(window.window_id),
			"role_id": str(window.role_id),
			"occurrence": int(window.occurrence),
			"kind": str(window.kind),
		}
		record.merge(planarity_of(route, int(window.first), int(window.last)))
		elements.append(record)
	return {
		"schema_version": SCHEMA,
		"metric": "element_planarity",
		"judgement": "report-only",
		"note": "Helical and inverting elements are expected to be three-dimensional; the class is reported, never scored.",
		"planar_ratio": PLANAR_RATIO,
		"quasi_planar_ratio": QUASI_PLANAR_RATIO,
		"elements": elements,
		"worst_vertical_tilts": _worst(
			elements.filter(func(record: Dictionary) -> bool: return record.tilt_is_meaningful),
			"vertical_plane_tilt_deg"
		),
	}


## The plane fit for one inclusive sample span, without any identity fields.
static func planarity_of(route: Dictionary, first: int, last: int) -> Dictionary:
	var positions: PackedVector3Array = route.positions
	var count := last - first + 1
	if count >= 3:
		var centroid := Vector3.ZERO
		for index in range(first, last + 1):
			centroid += positions[index]
		centroid /= float(count)
		var covariance := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
		var low := Vector3(INF, INF, INF)
		var high := Vector3(-INF, -INF, -INF)
		for index in range(first, last + 1):
			var offset: Vector3 = positions[index] - centroid
			low = low.min(positions[index])
			high = high.max(positions[index])
			var components := [offset.x, offset.y, offset.z]
			for row in 3:
				for column in 3:
					covariance[row][column] += float(components[row]) * float(components[column])
		for row in 3:
			for column in 3:
				covariance[row][column] /= float(count)
		var eigen := _symmetric_eigen(covariance)
		var normal: Vector3 = eigen.vectors[0]
		var principal: Vector3 = eigen.vectors[2]
		var squared := 0.0
		var maximum := 0.0
		for index in range(first, last + 1):
			var deviation: float = (positions[index] - centroid).dot(normal)
			squared += deviation * deviation
			maximum = maxf(maximum, absf(deviation))
		var rms := sqrt(squared / float(count))
		var diagonal: float = (high - low).length()
		var ratio := rms / diagonal if diagonal > 1e-9 else 0.0
		var chord: Vector3 = positions[last] - positions[first]
		if principal.dot(chord) < 0.0:
			principal = -principal
		var classification := "three-dimensional"
		if ratio <= PLANAR_RATIO:
			classification = "planar"
		elif ratio <= QUASI_PLANAR_RATIO:
			classification = "quasi-planar"
		return {
			"sample_count": count,
			"status": "measured",
			"rms_out_of_plane_m": rms,
			"max_out_of_plane_m": maximum,
			"out_of_plane_ratio": ratio,
			"bounding_diagonal_m": diagonal,
			"plane_normal": [normal.x, normal.y, normal.z],
			"vertical_plane_tilt_deg": rad_to_deg(asin(clampf(absf(normal.y), 0.0, 1.0))),
			"principal_axis_pitch_deg": rad_to_deg(asin(clampf(principal.normalized().y, -1.0, 1.0))),
			"planarity_class": classification,
			"tilt_is_meaningful": classification != "three-dimensional",
		}
	return {
		"sample_count": count,
		"status": "too-few-samples", "rms_out_of_plane_m": null,
		"max_out_of_plane_m": null, "out_of_plane_ratio": null,
		"plane_normal": null, "vertical_plane_tilt_deg": null,
		"principal_axis_pitch_deg": null, "planarity_class": "unavailable",
		"tilt_is_meaningful": false, "bounding_diagonal_m": null,
	}


# ---------------------------------------------------------------------------------------------
# 3. Shape ratios
# ---------------------------------------------------------------------------------------------

## The numeric silhouette of each role window: how tall, how wide, how long, and how much heading
## it turns through. These are the numbers a photograph of the real element can be read against.
static func shape_ratios(route: Dictionary) -> Dictionary:
	var unavailable := _unavailable(route)
	if not unavailable.is_empty():
		return unavailable
	var elements := []
	for window: Dictionary in role_windows(route):
		var record := {
			"window_id": str(window.window_id),
			"role_id": str(window.role_id),
			"occurrence": int(window.occurrence),
			"kind": str(window.kind),
		}
		record.merge(shape_of(route, int(window.first), int(window.last)))
		elements.append(record)
	return {
		"schema_version": SCHEMA,
		"metric": "shape_ratios",
		"judgement": "report-only",
		"elements": elements,
	}


## The silhouette of one inclusive sample span, without any identity fields.
static func shape_of(route: Dictionary, first: int, last: int) -> Dictionary:
	var positions: PackedVector3Array = route.positions
	var tangents: PackedVector3Array = route.tangents
	if last <= first:
		return {"status": "too-few-samples"}
	var height_low := INF
	var height_high := -INF
	var plan_sum := Vector2.ZERO
	var origin := Vector2(positions[first].x, positions[first].z)
	for index in range(first, last + 1):
		height_low = minf(height_low, positions[index].y)
		height_high = maxf(height_high, positions[index].y)
		plan_sum += Vector2(positions[index].x, positions[index].z) - origin
	var heading := plan_sum.normalized()
	if heading.length_squared() < 0.5:
		heading = Vector2(tangents[first].x, tangents[first].z).normalized()
	if heading.length_squared() < 0.5:
		heading = Vector2.RIGHT
	var across := Vector2(-heading.y, heading.x)
	var along_low := INF
	var along_high := -INF
	var across_low := INF
	var across_high := -INF
	for index in range(first, last + 1):
		var plan := Vector2(positions[index].x, positions[index].z) - origin
		along_low = minf(along_low, plan.dot(heading))
		along_high = maxf(along_high, plan.dot(heading))
		across_low = minf(across_low, plan.dot(across))
		across_high = maxf(across_high, plan.dot(across))
	var height: float = height_high - height_low
	var along: float = along_high - along_low
	var sideways: float = across_high - across_low
	var horizontal := maxf(along, sideways)
	var track_length: float = float(route.distances[last]) - float(route.distances[first])
	var entry_heading := _plan_heading_deg(tangents[first])
	var exit_heading := _plan_heading_deg(tangents[last])
	var accumulated := 0.0
	for index in range(first, last):
		accumulated += rad_to_deg(angle_difference(
			deg_to_rad(_plan_heading_deg(tangents[index])),
			deg_to_rad(_plan_heading_deg(tangents[index + 1]))
		))
	return {
		"status": "measured",
		"first_sample": first,
		"last_sample": last,
		"seconds": float(route.times[last]) - float(route.times[first]),
		"height_extent_m": height,
		"horizontal_extent_m": horizontal,
		"plan_along_m": along,
		"plan_across_m": sideways,
		"track_length_m": track_length,
		"height_to_length_ratio": height / track_length if track_length > 1e-6 else null,
		"height_to_horizontal_ratio": height / horizontal if horizontal > 1e-6 else null,
		"entry_heading_deg": entry_heading,
		"exit_heading_deg": exit_heading,
		"net_heading_change_deg": rad_to_deg(
			angle_difference(deg_to_rad(entry_heading), deg_to_rad(exit_heading))
		),
		"total_heading_change_deg": accumulated,
		"entry_pitch_deg": _pitch_deg(tangents[first]),
		"exit_pitch_deg": _pitch_deg(tangents[last]),
		"entry_bank_deg": float(route.banks[first]),
		"exit_bank_deg": float(route.banks[last]),
		"entry_speed_mps": float(route.speeds[first]),
		"exit_speed_mps": float(route.speeds[last]),
		"apex_height_m": height_high,
		"base_height_m": height_low,
	}


## Resolve a manifest element id to a sample span and its geometry. The id may name a compiled
## window (`marquee-camelback/crest/00`), a material role (`camelback`), or a role id (`crest`);
## the resolution order is exactly that, and the record says which one matched.
static func element_geometry(route: Dictionary, element_id: String) -> Dictionary:
	var unavailable := _unavailable(route)
	if not unavailable.is_empty():
		return unavailable
	var windows := role_windows(route)
	for matched_by in ["window_id", "material_role", "role_id"]:
		var selected := []
		for window: Dictionary in windows:
			var key := "%s/%s/%d" % [window.story_slot_id, window.role_id, int(window.occurrence)]
			var candidate := ""
			match matched_by:
				"window_id": candidate = str(window.window_id)
				"material_role": candidate = str(MATERIAL_ROLE_BY_WINDOW.get(key, ""))
				"role_id": candidate = str(window.role_id)
			if candidate == element_id:
				selected.append(window)
		if selected.is_empty():
			continue
		var first := int(selected[0].first)
		var last := int(selected[0].last)
		var ids := []
		for window: Dictionary in selected:
			first = mini(first, int(window.first))
			last = maxi(last, int(window.last))
			ids.append(str(window.window_id))
		return {
			"status": "resolved", "element_id": element_id, "matched_by": matched_by,
			"window_ids": ids, "first": first, "last": last,
			"shape": shape_of(route, first, last), "planarity": planarity_of(route, first, last),
		}
	return {"status": "no-generated-element", "element_id": element_id}


# ---------------------------------------------------------------------------------------------
# 4. Counterpart comparison
# ---------------------------------------------------------------------------------------------

## Generated loads against the per-role stretched counterpart bands. Row 4 (train centre) is the
## one row read, and its channels are the verify-filtered 100 Hz series that RideFidelity already
## builds — a labelled catalogued-evidence comparison, which is the one place filtering is allowed.
##
## This produces LABELS, not verdicts: RideFidelityCounterparts is design-grounding data, not an
## executable catalog source, so no row here can close an issue or become a gate.
static func counterpart_comparison(route: Dictionary, row_offset: float = COUNTERPART_ROW_OFFSET_M) -> Dictionary:
	var unavailable := _unavailable(route)
	if not unavailable.is_empty():
		return unavailable
	var mapping := material_role_bands(route, row_offset)
	var counterparts: Dictionary = Counterparts.bands()
	var role_ids: Array = counterparts.keys()
	role_ids.sort()
	var rows := []
	var gaps := []
	var totals := {"within": 0, "under": 0, "over": 0, "unmapped": 0,
		"no-adopted-target": 0, "no-generated-window": 0}
	for role_value in role_ids:
		var role := str(role_value)
		var entry: Dictionary = counterparts[role]
		if bool(entry.get("evidence_gap", false)):
			gaps.append({
				"role_id": role, "status": "evidence-gap",
				"reason": str(entry.get("reason", "")),
				"closes_with": str(entry.get("closes_with", "")),
			})
			continue
		if not mapping.bands.has(role):
			totals["no-generated-window"] = int(totals["no-generated-window"]) + 1
			rows.append({
				"role_id": role, "window_ids": [], "axis": null, "label": null,
				"status": "no-generated-window", "measured_g": null, "target": null,
				"band": null, "band_source": null, "measured_hold": null,
				"counterpart": str(entry.get("counterpart", {}).get("element", "")),
			})
			continue
		var band: Dictionary = mapping.bands[role]
		for axis_value in entry.get("axes", []):
			var row := _counterpart_row(role, band, axis_value, entry)
			totals[row.status] = int(totals.get(row.status, 0)) + 1
			rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := "%s|%s|%s" % [a.role_id, str(a.axis), str(a.label)]
		var right := "%s|%s|%s" % [b.role_id, str(b.axis), str(b.label)]
		return left < right)
	gaps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.role_id < b.role_id)
	return {
		"schema_version": COUNTERPART_SCHEMA,
		"metric": "counterpart_comparison",
		"judgement": "report-only",
		"seed": int(route.get("seed", 0)),
		"row_id": COUNTERPART_ROW_ID,
		"row_offset_m": row_offset,
		"channel_label": "verify-filtered (100 Hz resample, 4-pole 5 Hz Butterworth), row-shifted material-role window",
		"derived_on": Counterparts.DERIVED_ON,
		"scalar_band_fraction": SCALAR_BAND_FRACTION,
		"scalar_band_note": "A counterpart quoted as one number is widened by this fraction purely so the row can be labelled. It is not a reviewed threshold.",
		"mapping": {
			"mapped_window_count": mapping.mapped_window_count,
			"unmapped_windows": mapping.unmapped_windows,
			"material_roles_without_window": mapping.roles_without_window,
		},
		"totals": totals,
		"rows": rows,
		"evidence_gaps": gaps,
	}


## One filtered load band per material role, built on the accepted measurement chain
## (native row forces -> 100 Hz resample -> 4-pole 5 Hz Butterworth) and windowed on the
## row-shifted distance span the role owns.
static func material_role_bands(route: Dictionary, row_offset: float) -> Dictionary:
	var spans := {}
	var order := []
	var unmapped := []
	var mapped := 0
	for window: Dictionary in role_windows(route):
		var key := "%s/%s/%d" % [window.story_slot_id, window.role_id, int(window.occurrence)]
		if not MATERIAL_ROLE_BY_WINDOW.has(key):
			unmapped.append({"window_id": str(window.window_id), "mapping_key": key})
			continue
		mapped += 1
		var role: String = MATERIAL_ROLE_BY_WINDOW[key]
		if not spans.has(role):
			spans[role] = {"first": int(window.first), "last": int(window.last), "windows": []}
			order.append(role)
		spans[role].first = mini(int(spans[role].first), int(window.first))
		spans[role].last = maxi(int(spans[role].last), int(window.last))
		spans[role].windows.append(str(window.window_id))

	var native: Dictionary = Fidelity.native_row_series(route, row_offset)
	var series := {
		"normal": Verify.filter(Verify.resample(route.times, native.normal_g)),
		"lateral": Verify.filter(Verify.resample(route.times, native.lateral_g)),
		"longitudinal": Verify.filter(Verify.resample(route.times, native.longitudinal_g)),
	}
	var bands := {}
	for role in order:
		var span: Dictionary = spans[role]
		var start_time := _time_at_distance(
			route, float(route.distances[int(span.first)]) + row_offset)
		var end_time := _time_at_distance(
			route, float(route.distances[int(span.last)]) + row_offset)
		var first := int(ceil(start_time * Verify.SAMPLE_HZ - 1e-9))
		var last := int(floor(end_time * Verify.SAMPLE_HZ + 1e-9))
		var count: int = series.normal.size()
		first = clampi(first, 0, maxi(0, count - 1))
		last = clampi(last, 0, maxi(0, count - 1))
		if last - first + 1 < 5:
			continue
		bands[role] = {
			"role_id": role,
			"window_ids": span.windows,
			"first_sample": int(span.first),
			"last_sample": int(span.last),
			"window_start_s": start_time,
			"window_end_s": end_time,
			"seconds": end_time - start_time,
			"normal": series.normal.slice(first, last + 1),
			"lateral": series.lateral.slice(first, last + 1),
			"longitudinal": series.longitudinal.slice(first, last + 1),
		}
	var missing := []
	for role in Counterparts.bands().keys():
		if not bands.has(role) and not bool(Counterparts.bands()[role].get("evidence_gap", false)):
			missing.append(str(role))
	missing.sort()
	unmapped.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.mapping_key < b.mapping_key)
	return {
		"bands": bands, "mapped_window_count": mapped, "unmapped_windows": unmapped,
		"roles_without_window": missing,
	}


static func _time_at_distance(route: Dictionary, distance_m: float) -> float:
	var distances: PackedFloat32Array = route.distances
	var times: PackedFloat32Array = route.times
	var clamped := clampf(distance_m, float(distances[0]), float(distances[-1]))
	var index := Sampling.lower_index(distances, clamped)
	var low := float(distances[index])
	var high := float(distances[index + 1])
	if high <= low:
		return float(times[index])
	return lerpf(float(times[index]), float(times[index + 1]), (clamped - low) / (high - low))


static func _counterpart_row(
	role: String, band: Dictionary, axis_value: Variant, entry: Dictionary
) -> Dictionary:
	var axis: Dictionary = axis_value
	var name := str(axis.get("axis", ""))
	var series: Dictionary = _axis_series(band, name)
	var row := {
		"role_id": role,
		"window_ids": band.window_ids,
		"window_seconds": float(band.seconds),
		"axis": name,
		"label": str(axis.get("label", "")),
		"measured_counterpart": axis.get("measured"),
		"stretch": axis.get("stretch"),
		"target": axis.get("target"),
		"counterpart": str(entry.get("counterpart", {}).get("element", "")),
		"telemetry_anchor": str(entry.get("counterpart", {}).get("telemetry_anchor", "")),
	}
	if series.is_empty():
		row.merge({
			"status": "unmapped", "measured_g": null, "band": null, "band_source": null,
			"measured_hold": null, "delta_g": null, "normalized_miss": null,
			"reason": "no generated channel is defined for counterpart axis '%s'" % name,
		})
		return row
	var band_range := _target_band(axis.get("target"))
	if band_range.is_empty():
		# A null target is deliberate: the counterpart records the measurement and explicitly
		# adopts no design target from it. Labelling it a miss would invent a band.
		var deliberate: bool = axis.get("target") == null
		row.merge({
			"status": "no-adopted-target" if deliberate else "unmapped",
			"measured_g": float(series.value), "band": null,
			"band_source": null, "measured_hold": null, "delta_g": null,
			"normalized_miss": null,
			"reason": "the counterpart adopts no target for this axis" if deliberate
				else "counterpart target is neither a number nor a range",
		})
		return row
	var measured: float = float(series.value)
	var status := Fidelity.classify_value(measured, band_range.range)
	row.merge({
		"status": status,
		"measured_g": measured,
		"generated_metric": str(series.metric),
		"band": band_range.range,
		"band_source": str(band_range.source),
		"delta_g": measured - _band_centre(band_range.range),
		"normalized_miss": Fidelity.normalized_miss(measured, band_range.range),
		"measured_hold": _measured_hold(band, name, axis.get("hold_s")),
	})
	return row


## The generated channel that answers a counterpart axis. Absolute lateral is compared against the
## counterpart's magnitude because the sources' lateral sign is recording-dependent.
static func _axis_series(band: Dictionary, axis: String) -> Dictionary:
	match axis:
		"gz_positive":
			return {"value": _maximum(band.normal), "metric": "normal_peak_positive"}
		"gz_negative":
			return {"value": _minimum(band.normal), "metric": "normal_peak_negative"}
		"gz_level":
			return {"value": _mean(band.normal), "metric": "normal_window_mean"}
		"gy":
			return {"value": _absolute_peak(band.lateral), "metric": "lateral_peak_absolute"}
		"gx_positive":
			return {"value": _maximum(band.longitudinal), "metric": "longitudinal_peak_positive"}
		"gx_negative":
			return {"value": _minimum(band.longitudinal), "metric": "longitudinal_peak_negative"}
	return {}


## The counterpart's own measured hold duration, carried through unchanged and evaluated on the
## generated channel. Never stretched: the stretch applies to values only.
static func _measured_hold(band: Dictionary, axis: String, hold_value: Variant) -> Variant:
	if not _number(hold_value) or float(hold_value) <= 0.0:
		return null
	var seconds := float(hold_value)
	var held: float
	match axis:
		"gz_positive", "gz_level":
			held = Fidelity.held(band.normal, 1.0, seconds)
		"gz_negative":
			held = Fidelity.held(band.normal, -1.0, seconds)
		"gy":
			held = maxf(
				Fidelity.held(band.lateral, 1.0, seconds),
				absf(Fidelity.held(band.lateral, -1.0, seconds))
			)
		"gx_positive":
			held = Fidelity.held(band.longitudinal, 1.0, seconds)
		"gx_negative":
			held = Fidelity.held(band.longitudinal, -1.0, seconds)
		_:
			return null
	if not is_finite(held):
		return {"seconds": seconds, "held_g": null, "status": "window-shorter-than-hold"}
	return {"seconds": seconds, "held_g": held, "status": "measured"}


static func _target_band(target: Variant) -> Dictionary:
	if _number(target):
		var value := float(target)
		var margin := absf(value) * SCALAR_BAND_FRACTION
		var low: float = minf(value - margin, value + margin)
		var high: float = maxf(value - margin, value + margin)
		return {"range": [low, high], "source": "scalar-target-with-diagnostic-tolerance"}
	if target is Array and target.size() == 2 and _number(target[0]) and _number(target[1]):
		return {
			"range": [minf(float(target[0]), float(target[1])), maxf(float(target[0]), float(target[1]))],
			"source": "counterpart-range",
		}
	return {}


# ---------------------------------------------------------------------------------------------
# Combined per-seed geometry pack (metrics 1-3)
# ---------------------------------------------------------------------------------------------

static func measure(route: Dictionary) -> Dictionary:
	var unavailable := _unavailable(route)
	if not unavailable.is_empty():
		return unavailable
	return {
		"schema_version": SCHEMA,
		"judgement": "report-only",
		"seed": int(route.get("seed", 0)),
		"sample_count": route.times.size(),
		"seam_roll_continuity": seam_roll_continuity(route),
		"element_planarity": element_planarity(route),
		"shape_ratios": shape_ratios(route),
	}


# ---------------------------------------------------------------------------------------------
# Deterministic Markdown
# ---------------------------------------------------------------------------------------------

## The per-seed geometry report. `reference` is the resolved local-media overlay record, or an
## empty Dictionary when REF_MEDIA_MANIFEST was not set — in which case the report says so, as a
## declared gap rather than a silent omission.
static func markdown(pack: Dictionary, reference: Dictionary) -> String:
	var lines := PackedStringArray()
	if pack.get("status") == "route-unavailable":
		lines.append("# Geometry metrics — route unavailable")
		lines.append("")
		lines.append("Missing route fields: %s" % ", ".join(PackedStringArray(
			pack.get("missing_fields", []).map(func(value: Variant) -> String: return str(value)))))
		return "\n".join(lines) + "\n"
	lines.append("# Geometry metrics — seed %d" % int(pack.seed))
	lines.append("")
	lines.append("Schema `%s`. Diagnostic evidence to read, never a gate: no row here closes a" \
		% SCHEMA)
	lines.append("ride-quality issue. Issue 24 is the parent — the forces can be right while the")
	lines.append("swept shape is wrong, so every number below is derived from geometry alone.")
	lines.append("")
	lines.append_array(_reference_lines(reference))

	var seams: Dictionary = pack.seam_roll_continuity
	lines.append("## Roll continuity across role seams (issue 20)")
	lines.append("")
	lines.append("%d seams. A coherent roll crosses a seam with a small rate jump; a step shows up" \
		% int(seams.seam_count))
	lines.append("as a large jump or a large change of roll acceleration.")
	lines.append("")
	lines.append(_row(["rank", "seam", "roll rate jump deg/s", "roll accel break deg/s^2",
		"before", "after", "gesture seam"]))
	lines.append(_row(["---:", "---", "---:", "---:", "---", "---", "---"]))
	for entry: Dictionary in seams.worst_roll_rate_jumps:
		var seam := _seam_by_window(seams.seams, str(entry.window_id))
		lines.append(_row([int(entry.rank), str(entry.window_id), _num(entry.value, 3),
			_num(seam.get("roll_acceleration_break_dps2"), 3),
			str(seam.get("before_role", "")), str(seam.get("after_role", "")),
			str(seam.get("gesture_boundary", ""))]))
	lines.append("")
	lines.append("### Roll delivery per role")
	lines.append("")
	lines.append("`roll segments` counts the separate runs of actual rolling inside the window;")
	lines.append("two or more with a high `banked flat share` is the roll -> flat -> roll pattern.")
	lines.append("")
	lines.append(_row(["role window", "seconds", "peak deg/s", "roll segments", "reversals",
		"flat share", "banked flat share"]))
	lines.append(_row(["---", "---:", "---:", "---:", "---:", "---:", "---:"]))
	for profile: Dictionary in seams.role_roll_profiles:
		lines.append(_row([str(profile.window_id), _num(profile.seconds, 2),
			_num(profile.roll_rate_peak_dps, 2), int(profile.roll_segment_count),
			int(profile.roll_reversal_count), _num(profile.flat_roll_share, 3),
			_num(profile.banked_flat_roll_share, 3)]))
	lines.append("")

	var planarity: Dictionary = pack.element_planarity
	lines.append("## Element planarity (issue 23)")
	lines.append("")
	lines.append("Least-squares best-fit plane per role window. `tilt off vertical` is how far the")
	lines.append("fitted plane leans out of the vertical — the sideways tilt issue 23 describes.")
	lines.append("It is only meaningful for a planar element; a loop or a helix is genuinely")
	lines.append("three-dimensional and is reported, not judged.")
	lines.append("")
	lines.append("Read the column with the element's intent in hand. A turn's plane is legitimately")
	lines.append("near-horizontal, so a tilt near 90 degrees on a turn is the metric working, not a")
	lines.append("fault. The reading bites on elements whose plane should contain the vertical —")
	lines.append("hills, drops, the camelback — where anything above a few degrees is a lean the")
	lines.append("shape should not have.")
	lines.append("")
	lines.append(_row(["role window", "class", "rms off-plane m", "max off-plane m",
		"off-plane ratio", "tilt off vertical deg", "tilt meaningful"]))
	lines.append(_row(["---", "---", "---:", "---:", "---:", "---:", "---"]))
	for element: Dictionary in planarity.elements:
		lines.append(_row([str(element.window_id), str(element.planarity_class),
			_num(element.get("rms_out_of_plane_m"), 3), _num(element.get("max_out_of_plane_m"), 3),
			_num(element.get("out_of_plane_ratio"), 4),
			_num(element.get("vertical_plane_tilt_deg"), 2), str(element.tilt_is_meaningful)]))
	lines.append("")

	var shapes: Dictionary = pack.shape_ratios
	lines.append("## Shape ratios — the numeric silhouette")
	lines.append("")
	lines.append(_row(["role window", "height m", "horizontal m", "length m", "h:l",
		"heading change deg", "entry pitch", "exit pitch", "entry bank", "exit bank"]))
	lines.append(_row(["---", "---:", "---:", "---:", "---:", "---:", "---:", "---:", "---:", "---:"]))
	for element: Dictionary in shapes.elements:
		lines.append(_row([str(element.window_id), _num(element.get("height_extent_m"), 1),
			_num(element.get("horizontal_extent_m"), 1), _num(element.get("track_length_m"), 1),
			_num(element.get("height_to_length_ratio"), 3),
			_num(element.get("total_heading_change_deg"), 1), _num(element.get("entry_pitch_deg"), 1),
			_num(element.get("exit_pitch_deg"), 1), _num(element.get("entry_bank_deg"), 1),
			_num(element.get("exit_bank_deg"), 1)]))
	return "\n".join(lines) + "\n"


static func _reference_lines(reference: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray(["## Photographic reference overlays", ""])
	if reference.is_empty():
		lines.append("**Declared gap: no reference media.** `REF_MEDIA_MANIFEST` was not set, so no")
		lines.append("real-life photographic reference was compared against these shapes. The")
		lines.append("numbers above describe the generated geometry only; they do not confirm it")
		lines.append("resembles anything. Acquire local media with `tools/fetch-reference-media.sh`")
		lines.append("and point `REF_MEDIA_MANIFEST` at the resulting manifest.")
		lines.append("")
		return lines
	if reference.get("status") == "manifest-missing":
		lines.append("**Declared gap: the reference manifest was not found.**")
		lines.append("`REF_MEDIA_MANIFEST` pointed at `%s`, which does not exist. No photographic" \
			% str(reference.get("path", "")))
		lines.append("reference was compared against these shapes.")
		lines.append("")
		return lines
	if reference.get("status") != "ok":
		lines.append("**Declared gap: the reference manifest was rejected.**")
		lines.append("")
		for error in reference.get("errors", []):
			lines.append("- %s" % str(error))
		lines.append("")
		return lines
	lines.append("Manifest `%s` (sha256 `%s`): %d entries, %d available." % [
		str(reference.get("manifest_schema", "")), str(reference.get("manifest_sha256", "")),
		int(reference.entry_count), int(reference.available_count)])
	lines.append("")
	lines.append("Reference media is local, personal-use and never committed; only these")
	lines.append("landmarks, provenance strings and digests are.")
	lines.append("")
	lines.append(_row(["element", "status", "source", "acquisition", "timestamp s", "sha256"]))
	lines.append(_row(["---", "---", "---", "---", "---:", "---"]))
	for entry: Dictionary in reference.entries:
		lines.append(_row([str(entry.element_id), str(entry.status), str(entry.source_id),
			str(entry.acquisition), _num(entry.get("timestamp_s"), 2),
			str(entry.expected_sha256).substr(0, 16)]))
	lines.append("")
	return lines


## The fleet counterpart comparison: one section per measured seed.
static func counterpart_markdown(seeds: Array) -> String:
	var lines := PackedStringArray([
		"# Counterpart comparison — generated loads against the stretched bands", "",
		"Schema `%s`. Source data: `godot/fidelity_counterparts.gd`, which is DESIGN GROUNDING," % COUNTERPART_SCHEMA,
		"not an executable catalog source. Every row below is a label, never a verdict: a miss",
		"here does not fail the ride and a hit does not close an issue.", "",
		"Channels are the accepted verify-filtered measurement chain on the row-04 (train centre)",
		"frame. Filtering is labelled because this is a catalogued evidence comparison; generated",
		"positions stay raw everywhere else.", "",
		"**Granularity caveat, and it decides how several rows read.** The measured value is the",
		"extreme (or the mean, for `gz_level`) over the WHOLE material role, because that is the",
		"unit `RideFidelityCounterparts` is keyed by. Many counterpart axes describe a sub-beat",
		"inside that role — a camelback crest, a dive pull-up, one hill of an airtime chain — and",
		"the compiled route splits those roles into several windows. Such a row answers *does this",
		"role reach that value anywhere*, not *does that beat match*. A `gz_level` row is the worst",
		"case: a crest-only float target compared against a mean taken across the rise and the fall",
		"as well, which will read `over` no matter how good the crest is. Resolving this needs a",
		"declared axis-to-sub-window mapping, which no committed source provides yet.", "",
	])
	for entry_value in seeds:
		var entry: Dictionary = entry_value
		lines.append("## Seed %d" % int(entry.get("seed", 0)))
		lines.append("")
		if entry.get("schema_version") != COUNTERPART_SCHEMA:
			lines.append("Route unavailable: %s" % str(entry.get("status", "unknown")))
			lines.append("")
			continue
		var totals: Dictionary = entry.totals
		var counts := PackedStringArray()
		var keys: Array = totals.keys()
		keys.sort()
		for key in keys:
			counts.append("%s %d" % [str(key), int(totals[key])])
		lines.append("Totals: %s." % ", ".join(counts))
		var mapping: Dictionary = entry.mapping
		lines.append("")
		lines.append("Mapping: %d compiled windows bridged, %d unmapped, %d material roles without a window." % [
			int(mapping.mapped_window_count), mapping.unmapped_windows.size(),
			mapping.material_roles_without_window.size()])
		lines.append("")
		lines.append(_row(["role", "axis", "label", "measured g", "target", "band",
			"status", "normalized miss", "held"]))
		lines.append(_row(["---", "---", "---", "---:", "---", "---", "---", "---:", "---"]))
		for row: Dictionary in entry.rows:
			var hold: Variant = row.get("measured_hold")
			var hold_text := "—"
			if hold is Dictionary:
				hold_text = "%s g / %s s" % [_num(hold.get("held_g"), 2), _num(hold.get("seconds"), 2)]
			lines.append(_row([str(row.role_id), str(row.get("axis", "")), str(row.get("label", "")),
				_num(row.get("measured_g"), 3), _value(row.get("target")), _value(row.get("band")),
				str(row.status), _num(row.get("normalized_miss"), 3), hold_text]))
		lines.append("")
		if not entry.evidence_gaps.is_empty():
			lines.append("### Evidence gaps")
			lines.append("")
			for gap: Dictionary in entry.evidence_gaps:
				lines.append("- **%s** — %s" % [str(gap.role_id), str(gap.reason)])
			lines.append("")
	return "\n".join(lines) + "\n"


static func _seam_by_window(seams: Array, window_id: String) -> Dictionary:
	for seam: Dictionary in seams:
		if str(seam.after_window_id) == window_id:
			return seam
	return {}


static func _row(cells: Array) -> String:
	var parts := PackedStringArray()
	for cell in cells:
		parts.append(str(cell))
	return "| %s |" % " | ".join(parts)


static func _num(value: Variant, digits: int) -> String:
	if not _number(value):
		return "—"
	return String.num(float(value), digits)


static func _value(value: Variant) -> String:
	if value is Array:
		var parts := PackedStringArray()
		for item in value:
			parts.append(_num(item, 3))
		return "[%s]" % ", ".join(parts)
	return _num(value, 3)


# ---------------------------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------------------------

## Every role window in compiled route order, flattened out of the gesture windows.
static func role_windows(route: Dictionary) -> Array:
	var windows := []
	var gesture_index := 0
	for gesture_value in route.get("gesture_windows", []):
		var gesture: Dictionary = gesture_value
		for role_value in gesture.get("role_windows", []):
			var role: Dictionary = role_value
			windows.append({
				"window_id": str(role.get("window_id", "")),
				"role_id": str(role.get("id", "")),
				"story_slot_id": str(gesture.get("story_slot_id", "")),
				"kind": str(role.get("diagnostic_kind", "")),
				"occurrence": int(role.get("occurrence", 0)),
				"first": int(role.get("first", 0)),
				"last": int(role.get("last", 0)),
				"gesture_index": gesture_index,
			})
		gesture_index += 1
	return windows


static func _unavailable(route: Dictionary) -> Dictionary:
	var missing := PackedStringArray()
	for field in REQUIRED_FIELDS:
		if not route.has(field):
			missing.append(field)
	if missing.is_empty() and route.times.size() < 2:
		missing.append("times(>=2 samples)")
	if missing.is_empty():
		return {}
	return {
		"schema_version": SCHEMA, "status": "route-unavailable",
		"missing_fields": Array(missing), "judgement": "report-only",
	}


## Least-squares slope of values against times over an inclusive index range.
static func _slope(
	times: PackedFloat32Array, values: PackedFloat32Array, first: int, last: int
) -> Variant:
	var count := last - first + 1
	if count < 2:
		return null
	var mean_time := 0.0
	var mean_value := 0.0
	for index in range(first, last + 1):
		mean_time += float(times[index])
		mean_value += float(values[index])
	mean_time /= float(count)
	mean_value /= float(count)
	var numerator := 0.0
	var denominator := 0.0
	for index in range(first, last + 1):
		var offset := float(times[index]) - mean_time
		numerator += offset * (float(values[index]) - mean_value)
		denominator += offset * offset
	if denominator <= 0.0:
		return null
	return numerator / denominator


static func _break(before: Variant, after: Variant) -> Variant:
	if before == null or after == null:
		return null
	return absf(float(after) - float(before))


## Deterministic worst-offender ranking: largest magnitude first, then boundary order.
static func _worst(records: Array, key: String) -> Array:
	var ranked := records.filter(func(record: Dictionary) -> bool:
		return _number(record.get(key)))
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := absf(float(a[key]))
		var right := absf(float(b[key]))
		if left != right:
			return left > right
		return str(a.get("window_id", a.get("after_window_id", ""))) \
			< str(b.get("window_id", b.get("after_window_id", "")))
	)
	var output := []
	for index in mini(WORST_COUNT, ranked.size()):
		var record: Dictionary = ranked[index]
		output.append({
			"rank": index + 1,
			"metric": key,
			"value": float(record[key]),
			"window_id": str(record.get("window_id", record.get("after_window_id", ""))),
			"role_id": str(record.get("role_id", record.get("after_role", ""))),
		})
	return output


## Cyclic Jacobi eigen-decomposition of a symmetric 3x3, eigenvalues ascending. Deterministic:
## the sweep order is fixed and the loop is capped.
static func _symmetric_eigen(matrix: Array) -> Dictionary:
	var a := [
		[float(matrix[0][0]), float(matrix[0][1]), float(matrix[0][2])],
		[float(matrix[1][0]), float(matrix[1][1]), float(matrix[1][2])],
		[float(matrix[2][0]), float(matrix[2][1]), float(matrix[2][2])],
	]
	var v := [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
	var pairs := [[0, 1], [0, 2], [1, 2]]
	for sweep in 32:
		var off := 0.0
		for pair in pairs:
			off += a[pair[0]][pair[1]] * a[pair[0]][pair[1]]
		if off <= 1e-30:
			break
		for pair in pairs:
			var p: int = pair[0]
			var q: int = pair[1]
			if absf(a[p][q]) <= 1e-300:
				continue
			var theta: float = (a[q][q] - a[p][p]) / (2.0 * a[p][q])
			var sign := 1.0 if theta >= 0.0 else -1.0
			var t: float = sign / (absf(theta) + sqrt(theta * theta + 1.0))
			var c := 1.0 / sqrt(t * t + 1.0)
			var s := t * c
			for k in 3:
				var akp: float = a[k][p]
				var akq: float = a[k][q]
				a[k][p] = c * akp - s * akq
				a[k][q] = s * akp + c * akq
			for k in 3:
				var apk: float = a[p][k]
				var aqk: float = a[q][k]
				a[p][k] = c * apk - s * aqk
				a[q][k] = s * apk + c * aqk
			for k in 3:
				var vkp: float = v[k][p]
				var vkq: float = v[k][q]
				v[k][p] = c * vkp - s * vkq
				v[k][q] = s * vkp + c * vkq
	var order := [0, 1, 2]
	order.sort_custom(func(left: int, right: int) -> bool:
		if a[left][left] != a[right][right]:
			return a[left][left] < a[right][right]
		return left < right)
	var values := []
	var vectors := []
	for index in order:
		values.append(float(a[index][index]))
		var vector := Vector3(float(v[0][index]), float(v[1][index]), float(v[2][index]))
		if vector.length_squared() <= 0.0:
			vector = Vector3.UP
		vector = vector.normalized()
		# A fixed sign convention keeps repeated runs bit-identical.
		var dominant: float = vector.x
		if absf(vector.y) > absf(dominant):
			dominant = vector.y
		if absf(vector.z) > absf(dominant):
			dominant = vector.z
		if dominant < 0.0:
			vector = -vector
		vectors.append(vector)
	return {"values": values, "vectors": vectors}


static func _plan_heading_deg(tangent: Vector3) -> float:
	var plan := Vector2(tangent.x, tangent.z)
	if plan.length_squared() <= 0.0:
		return 0.0
	return rad_to_deg(atan2(plan.y, plan.x))


static func _pitch_deg(tangent: Vector3) -> float:
	if tangent.length_squared() <= 0.0:
		return 0.0
	return rad_to_deg(asin(clampf(tangent.normalized().y, -1.0, 1.0)))


static func _maximum(values: PackedFloat32Array) -> float:
	var output := -INF
	for value in values:
		output = maxf(output, float(value))
	return output if is_finite(output) else 0.0


static func _minimum(values: PackedFloat32Array) -> float:
	var output := INF
	for value in values:
		output = minf(output, float(value))
	return output if is_finite(output) else 0.0


static func _absolute_peak(values: PackedFloat32Array) -> float:
	var output := 0.0
	for value in values:
		output = maxf(output, absf(float(value)))
	return output


static func _mean(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())


static func _band_centre(band: Array) -> float:
	return 0.5 * (float(band[0]) + float(band[1]))


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))
