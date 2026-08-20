class_name RidePlanner
extends RefCounted

## The material-v1 planner decision layer: named decision streams, the story grammar as data,
## and the conservatively certified target ranges drawn on those streams.
##
## Everything random about a ride is drawn on the streams minted here, before compilation:
## `RideProgram`, `Motion` and `RouteContract` never see a `RandomNumberGenerator`. One generator
## per *named* decision keeps the draws independent — adding a stream, or appending a draw to one
## stream, never disturbs the values another stream produces for the same seed. Two draws happen
## outside this file, on streams it hands out: the terrain draws in `Terrain.generate()` and the
## three station-placement draws in `RideGenerator._plan()`; both are certified by the
## fifteen-seed fleet gate rather than at range extremes.
##
## There are no candidate loops anywhere downstream. A target draw range is a claim that every
## value in it builds an accepted ride, certified at both extremes by `ride_planner_tests.gd`; a
## failed solve is a structured error carrying its draw provenance, never a retry.

const STREAM_TERRAIN := "terrain"
const STREAM_PLACEMENT := "placement"
const STREAM_STORY_ACT_ONE := "story.act1"
const STREAM_STORY_RETURN := "story.return"
const TARGET_STREAM_PREFIX := "targets."

# FNV-1a, 64-bit. The offset basis 14695981039346656037 written as the signed 64-bit value
# GDScript integers carry; the prime fits directly. Multiplication wraps modulo 2^64, which is
# exactly the mixing the algorithm asks for.
const STREAM_HASH_BASIS := -3750763034362895579
const STREAM_HASH_PRIME := 1099511628211
const STREAM_HASH_MASK := 0x7FFFFFFFFFFFFFFF

## The story spine. Only the act-one cell and (from the return cell) the ordering of the two
## turn/height pairs may vary; every other role keeps its reviewed slot.
const SPINE_OPENER := ["station-launch", "opener-twisted-drop", "opener-teardrop",
	"opener-release"]
const ACT_ONE_ANCHOR := "act-one-immelmann"
## The act-one pool the grammar permits to permute. The two inversions are structural (the loop
## needs act one's honest entry speed, the cutback needs the Immelmann exit); only a hill or the
## wave turn may be dropped, and never both.
##
## Nothing draws an order yet, and that is a measured verdict rather than an unfinished step. The
## prefix closure solve that was named as this draw's blocker has landed, and it moved the verdict
## without lifting it: re-measured on 2026-08-15 across all 24 grammar-legal orders, exactly one
## non-canonical order - the pool's two optional members exchanged - now closes its prefix and
## places it inside every fleet margin, on all fifteen seeds, and that is gated in
## `generator_material_tests.gd`. The other 22 are still refused before the solve runs, because the
## preflight frames the yaw solution from the *unsolved* prefix. What no reordered story does yet
## is build end to end: the seven-control return solve does not re-converge from its fixed seed on
## the moved camelback handoff. The full matrix, including what each order costs, is recorded with
## that gate. Drawing an order needs the return's seed or budget, not a wider range here.
const ACT_ONE_POOL := ["act-one-cutback", "act-one-loop", "act-one-airtime", "act-one-wave"]
const ACT_ONE_OPTIONAL := ["act-one-airtime", "act-one-wave"]
const SPINE_TAIL := ["climb-lsm2", "clifftop-slow-crest", "clifftop-outward-rim",
	"outward-dive", "tunnel-lsm3", "record-release-turn", "camelback"]
const RETURN_CELL := ["return-turn-a", "return-height-a", "return-turn-b", "return-height-b"]
const SPINE_CLOSE := ["terminal-capture-brakes"]

## Certified per-seed target draws, in fixed order. Each entry declares the stream it is drawn
## on (`targets.<role-id>`), the recipe key it resolves, and the closed range certified for it:
## every value in the range builds an accepted ride on the whole fleet, proven at both extremes
## by `ride_planner_tests.gd`, so nothing downstream ever needs a retry.
##
## Records are deliberately undrawn — the launch, both LSM drives, the camelback, the dive and
## the Immelmann are the ride's fixed identity. The opener and act one are undrawn for a
## *measured* reason, not a stylistic one: the story prefix is one rigid energy chain, authored
## as fixed-duration force profiles, so its terminal geometry is violently sensitive to any
## force change upstream of the escarpment climb. Measured on seed 42 (2026-08-15), with the
## native summit rise at 285.7 m, the dive chord at 300.8 m and the dive entry at 18.85 m/s:
##
##   twisted-drop core lateral 0.700 -> 0.705 : rise -16.5 m, chord +114.8 m, entry +8.40 m/s
##   helical-loop positive g   4.60  -> 4.58  : rise -17.2 m, chord +120.5 m, entry +8.84 m/s
##   airtime crest g          -0.31  -> -0.32 : rise  -4.7 m, chord  +40.1 m, entry +2.95 m/s
##
## The placement budget those had to fit in was a few metres of rise and roughly [-8, +40] m of
## chord, so a certifiable act-one range was ~0.3% wide — indistinguishable variety bought at real
## risk. The closure solve those numbers called for has since landed, and re-measuring the same
## perturbations on 2026-08-15 splits the verdict rather than lifting it: the helical loop's
## positive g now closes and places on the whole fleet at -0.005 (7 of 15 seeds at +0.005), while
## the twisted drop's core lateral still fails every seed in both directions, refused at the
## preflight before the solve is ever reached. Nothing built end to end at either perturbation —
## the return solve does not re-converge from its fixed seed. The measured matrix is recorded with
## its gate in `generator_material_tests.gd`; see also `docs/ISSUES.md` issue 24. This layer is
## built so adding these draws later disturbs no other stream.
## The clifftop suspense beat is undrawn for a second measured reason: at 46-54 deg of rim bank
## it barely moves the dive handoff (under 0.9 m of summit rise), but it does move where the
## camelback hands over to the return, and the return's bounded solve does not re-converge from
## its fixed seed when that handoff moves (measured: budget_exhausted at 219 evaluations, or a
## converged solve with turn-a 48 m past its declared band). Drawing it needs a seeded or
## continued return solve, not a wider range.
const TARGET_DRAWS := [
	# The return is downstream of every placement observation and closes through its own bounded
	# nine-control solve, so its beats can be drawn properly: how hard each height beat is pulled
	# and how deeply it floats.
	# One draw sets how hard both height beats are pulled: height-b's peak follows height-a's
	# proportionally, because the strong-a/weak-b diagonal is the one corner of the draw box the
	# return solve cannot close from its fixed seed. See `_return_spans` in `ride_program.gd`.
	{"role_id": "return-height-a", "key": "peak_g", "range": Vector2(3.65, 3.95)},
	{"role_id": "return-height-a", "key": "unload_scale", "range": Vector2(0.95, 1.05)},
	{"role_id": "return-height-b", "key": "unload_scale", "range": Vector2(0.95, 1.05)},
]


## Every material role id the grammar can author, in canonical (undrawn) order.
static func canonical_role_ids() -> Array:
	var ids: Array = []
	ids.append_array(SPINE_OPENER)
	ids.append(ACT_ONE_ANCHOR)
	ids.append_array(ACT_ONE_POOL)
	ids.append_array(SPINE_TAIL)
	ids.append_array(RETURN_CELL)
	ids.append_array(SPINE_CLOSE)
	return ids


## Every named decision stream, in a fixed order that never depends on Dictionary iteration.
static func stream_ids() -> Array:
	var ids: Array = [STREAM_TERRAIN, STREAM_PLACEMENT, STREAM_STORY_ACT_ONE,
		STREAM_STORY_RETURN]
	for role_id in canonical_role_ids():
		ids.append(TARGET_STREAM_PREFIX + str(role_id))
	return ids


## Deterministic, cross-platform stream seed: FNV-1a over the stream name's UTF-8 bytes followed
## by the eight bytes of the ride seed. `String.hash()` is deliberately unused — it is an
## engine-internal 32-bit hash with no documented stability across versions or platforms.
static func stream_seed(seed_value: int, stream_name: String) -> int:
	var hashed := STREAM_HASH_BASIS
	for byte in stream_name.to_utf8_buffer():
		hashed = (hashed ^ int(byte)) * STREAM_HASH_PRIME
	for shift in 8:
		hashed = (hashed ^ ((seed_value >> (shift * 8)) & 0xFF)) * STREAM_HASH_PRIME
	return hashed & STREAM_HASH_MASK


## One generator per named decision stream. Construction order is the fixed `stream_ids()` order,
## and each generator's seed depends only on (ride seed, stream name).
static func streams(seed_value: int) -> Dictionary:
	var result := {}
	for stream_name in stream_ids():
		var rng := RandomNumberGenerator.new()
		rng.seed = stream_seed(seed_value, str(stream_name))
		result[str(stream_name)] = rng
	return result


## The single planning entry point: draw the story sequence and every resolved target for a seed.
## `overrides` is a certification seam — it replaces a drawn value with an explicit one (keyed
## "<role-id>/<key>") without changing how many values each stream produces, so provenance and
## stream alignment stay exactly as they are in production.
static func resolve(seed_value: int, overrides: Dictionary = {}) -> Dictionary:
	var rngs := streams(seed_value)
	var sequence := _draw_sequence(rngs)
	var draws: Array = []
	var targets := {}
	var indices := {}
	for specification: Dictionary in TARGET_DRAWS:
		var role_id := str(specification.role_id)
		if not sequence.has(role_id):
			continue
		var stream_name: String = TARGET_STREAM_PREFIX + role_id
		var rng: RandomNumberGenerator = rngs[stream_name]
		var draw_index := int(indices.get(stream_name, 0))
		indices[stream_name] = draw_index + 1
		var band: Vector2 = specification.range
		var value := rng.randf_range(band.x, band.y)
		var key := str(specification.key)
		var override_key := "%s/%s" % [role_id, key]
		if overrides.has(override_key):
			value = clampf(float(overrides[override_key]), band.x, band.y)
		if not targets.has(role_id):
			targets[role_id] = {}
		targets[role_id][key] = value
		draws.append({"stream": stream_name, "index": draw_index, "role_id": role_id,
			"key": key, "value": value, "range": band})
	return {"seed": seed_value, "streams": rngs, "sequence": sequence, "targets": targets,
		"draws": draws}


## The act-one grammar cell. This checkpoint draws no order (see `ACT_ONE_POOL` for the measured
## reason), so `story.act1` stays unconsumed and the pool keeps its canonical order. Because
## every decision owns its own generator, consuming that stream later moves no other draw.
static func _draw_sequence(_rngs: Dictionary) -> Array:
	var pool: Array = ACT_ONE_POOL.duplicate()
	var sequence: Array = []
	sequence.append_array(SPINE_OPENER)
	sequence.append(ACT_ONE_ANCHOR)
	sequence.append_array(pool)
	sequence.append_array(SPINE_TAIL)
	sequence.append_array(RETURN_CELL)
	sequence.append_array(SPINE_CLOSE)
	return sequence


## The grammar-legality check shared by production plan validation and the tests: the spine is
## ordered, act one opens on its Immelmann anchor, the rest of act one is a permutation of the
## pool with at most one optional member dropped, and the return cell keeps its declared order.
static func is_legal_sequence(ids: Array) -> bool:
	var fixed_count := SPINE_OPENER.size() + 1 + SPINE_TAIL.size() + RETURN_CELL.size() \
		+ SPINE_CLOSE.size()
	var pool_count := ids.size() - fixed_count
	if pool_count < ACT_ONE_POOL.size() - 1 or pool_count > ACT_ONE_POOL.size():
		return false
	var cursor := 0
	for role_id in SPINE_OPENER:
		if ids[cursor] != role_id:
			return false
		cursor += 1
	if ids[cursor] != ACT_ONE_ANCHOR:
		return false
	cursor += 1
	var drawn: Array = []
	for index in pool_count:
		var role_id: Variant = ids[cursor + index]
		if not ACT_ONE_POOL.has(role_id) or drawn.has(role_id):
			return false
		drawn.append(role_id)
	for role_id in ACT_ONE_POOL:
		if drawn.has(role_id):
			continue
		if not ACT_ONE_OPTIONAL.has(role_id):
			return false
	cursor += pool_count
	var tail: Array = []
	tail.append_array(SPINE_TAIL)
	tail.append_array(RETURN_CELL)
	tail.append_array(SPINE_CLOSE)
	for role_id in tail:
		if ids[cursor] != role_id:
			return false
		cursor += 1
	return cursor == ids.size()


## The act-one roles of a declared sequence, in their authored order.
static func act_one_order(sequence: Array) -> Array:
	var order: Array = []
	for role_id in sequence:
		if role_id == ACT_ONE_ANCHOR or ACT_ONE_POOL.has(role_id):
			order.append(role_id)
	return order


## The resolved value for one recipe key, or its authored default when the plan carries no draw.
static func target(targets: Dictionary, role_id: String, key: String, fallback: float) -> float:
	var role: Variant = targets.get(role_id)
	if not role is Dictionary:
		return fallback
	var value: Variant = role.get(key)
	if not (value is float or value is int) or not is_finite(float(value)):
		return fallback
	return float(value)
