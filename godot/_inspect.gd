extends SceneTree

## Inspection harness (not part of the smoke gate) and the offline fidelity-audit runner: it
## generates the fixed fleet exactly once per seed, measures every seed against the committed
## evidence catalog, writes the checked baseline pack, and keeps the console/PNG diagnostics —
## per-element geometry stats, phase tables, element side views, top/elevation, and the stacked
## ride-channel traces — for visual comparison against the measured references in docs/TELEMETRY.md.
## Every render lives in RideFidelityArtifacts, which the audit pack shares.
## Operational failures (catalog, generation, physical consistency, artifact writes) exit 1;
## fidelity misses are diagnostic and still exit 0.
## Run: godot --headless --path godot --script res://_inspect.gd  [output dir via INSPECT_OUT]

const Generator := preload("res://generator.gd")
const Artifacts := preload("res://fidelity_artifacts.gd")
const Fidelity := preload("res://fidelity.gd")
const References := preload("res://fidelity_references.gd")
const Elements := preload("res://elements.gd")
const Verify := preload("res://verify.gd")

const AUDIT_SEEDS := [11, 42, 20260809, 1, 3, 7, 99, 256, 555, 1234, 4096, 31337, 77777, 123456, 20250101]
const DEEP_REVIEW_SEEDS := [11, 42, 20260809]
## The pinned pre-foundation legacy commit this baseline measures (plan Task 1, Step 0).
const LEGACY_BASE_COMMIT := "3fa14885bef2daf3a7d9c0e544424cb6a296fd99"

var OUT: String = OS.get_environment("INSPECT_OUT") if OS.get_environment("INSPECT_OUT") != "" else OS.get_user_data_dir() + "/inspect"

## Operational failures collected across the run; fidelity findings never land here.
var _operational: Array[String] = []


func _initialize() -> void:
	quit(_audit())


func _audit() -> int:
	_operational.append_array(_catalog_errors())
	_operational.append_array(_artifact_root_errors())
	if not _operational.is_empty():
		return _fail()

	var build := func(seed_value: int) -> Dictionary: return _built(seed_value)
	var measure := func(route: Dictionary) -> Dictionary: return _measured(route)
	var compare := func(measurements: Array) -> Dictionary: return _compared(measurements)
	var audit := _run_audit(AUDIT_SEEDS, build, measure, compare)
	if not _operational.is_empty():
		return _fail()

	_print_diagnostics(audit.routes_by_seed)
	if not _operational.is_empty():
		return _fail()
	var report: Dictionary = Artifacts.build_report(
		audit.measurements, audit.comparison, References.CATALOG,
		LEGACY_BASE_COMMIT, audit.generation_counts
	)
	if report.get("schema_version") != "ride-fidelity-audit@1":
		for error in report.get("errors", ["artifact_report: the audit report was not built"]):
			_operational.append(str(error))
		return _fail()
	for error in Artifacts.write_pack(OUT, report, audit.routes_by_seed):
		_operational.append(str(error))
	if not _operational.is_empty():
		return _fail()

	_print_findings(report)
	print("AUDIT %d seeds, %d render requests, pack written to %s" % [
		AUDIT_SEEDS.size(), report.render_requests.size(), OUT])
	return 0


## The orchestration seam: every dependency is injected so the one-build-per-seed contract is
## observable without generating a ride. Deep-review routes are retained for artifact rendering.
static func _run_audit(
	seeds: Array, build_route: Callable, measure_route: Callable, compare_fleet: Callable
) -> Dictionary:
	var measurements := []
	var routes_by_seed := {}
	var generation_counts := {}
	for seed_value in seeds:
		var route: Dictionary = build_route.call(seed_value)
		generation_counts[str(seed_value)] = int(generation_counts.get(str(seed_value), 0)) + 1
		measurements.append(measure_route.call(route))
		if seed_value in DEEP_REVIEW_SEEDS:
			routes_by_seed[seed_value] = route
	var comparison: Dictionary = compare_fleet.call(measurements)
	return {
		"fleet": seeds.duplicate(), "measurements": measurements, "comparison": comparison,
		"routes_by_seed": routes_by_seed, "generation_counts": generation_counts,
	}


## One generation per seed, checked for physical coherence before anything measures it.
func _built(seed_value: int) -> Dictionary:
	var catalog_version := str(References.CATALOG.get("catalog_version", ""))
	var route: Dictionary = Generator.build(seed_value)
	if not route.has("positions") or route.positions.is_empty():
		_operational.append("generation: catalog %s seed %d produced no route" % [
			catalog_version, seed_value])
		return {"seed": seed_value}
	var issues := PackedStringArray()
	Verify.validate_structure(route, issues)
	Verify.validate_seams(route, issues)
	for issue in issues:
		_operational.append("physical_consistency: catalog %s seed %d: %s" % [
			catalog_version, seed_value, issue])
	return route


func _measured(route: Dictionary) -> Dictionary:
	if not route.has("positions"):
		return {"schema_version": 1, "seed": int(route.get("seed", 0)), "beats": []}
	return Fidelity.measure_route(route, Elements.ROW_OFFSETS)


func _compared(measurements: Array) -> Dictionary:
	return Fidelity.compare_fleet(measurements, References.CATALOG)


func _catalog_errors() -> Array[String]:
	var errors: Array[String] = []
	for error in Fidelity.validate_catalog_artifacts(References.CATALOG):
		errors.append("catalog: %s" % error)
	return errors


## The artifact root has to exist and accept a checked write before a single seed is generated.
func _artifact_root_errors() -> Array[String]:
	DirAccess.make_dir_recursive_absolute(OUT)
	if not DirAccess.dir_exists_absolute(OUT):
		return ["artifact_write: cannot create the artifact root '%s'" % OUT]
	var probe := "%s/.write-probe" % OUT
	var errors: Array[String] = []
	for error in Artifacts.write_text_checked(probe, "probe"):
		errors.append(str(error))
	DirAccess.remove_absolute(probe)
	return errors


func _fail() -> int:
	for error in _operational:
		printerr(error)
	printerr("AUDIT failed with %d operational error(s)" % _operational.size())
	return 1


## Fidelity misses are reported, never gated: this is the whole point of the baseline.
func _print_findings(report: Dictionary) -> void:
	var by_status := {}
	for finding in report.findings:
		var status: String = finding.fleet_status
		by_status[status] = int(by_status.get(status, 0)) + 1
		print("FINDING %-44s %-13s fleet %10.3f target [%.3f, %.3f]  %d/%d seeds miss" % [
			finding.target_id, status, finding.fleet_value,
			float(finding.target_range[0]), float(finding.target_range[1]),
			finding.affected_count, finding.available_count,
		])
	for status in by_status.keys():
		print("FINDINGS %-14s %d" % [status, by_status[status]])
	print("EVIDENCE gaps %d  observed-only samples %d  recommendation %s" % [
		report.evidence_gaps.size(), report.observed_only.size(),
		report.recommendation.get("status", "none"),
	])


func _print_diagnostics(routes_by_seed: Dictionary) -> void:
	for seed_value in DEEP_REVIEW_SEEDS:
		var deep: Dictionary = routes_by_seed[seed_value]
		_render_channels(deep, "%s/channels_%d.png" % [OUT, seed_value])
	var route: Dictionary = routes_by_seed[42]
	_print_phases(route)
	for g in _element_groups(route):
		var kind: String = g.kind
		var a: int = g.first
		var b: int = g.last
		var stats := _stats(route, a, b)
		print("ELEM %-14s len %6.0f m  v %5.1f->%5.1f  pitch [%6.1f, %6.1f]  bank max %5.1f  nG [%5.2f, %5.2f]  W %5.0f H %5.0f  Rapex %5.0f Rvalley %5.0f" % [
			kind, route.distances[b] - route.distances[a], route.speeds[a], route.speeds[b],
			stats.min_pitch, stats.max_pitch, stats.max_bank, stats.min_n, stats.max_n,
			stats.width, stats.height, stats.r_apex, stats.r_valley,
		])
		if kind in ["hill", "immelmann", "loop", "cutback", "twisted_drop", "dive", "wave_turn", "overbank", "turn"]:
			_save(Artifacts.side_image(route, a, b), "%s/%s_%d.png" % [OUT, kind, a])
	_save(Artifacts.top_image(route), "%s/top.png" % OUT)
	_save(Artifacts.elevation_image(route), "%s/elevation.png" % OUT)


func _save(image: Image, path: String) -> void:
	for error in Artifacts.save_png_checked(image, path):
		_operational.append(str(error))


func _element_groups(route: Dictionary) -> Array:
	var groups := []
	var current := {}
	for i in route.sections.size():
		var section: Dictionary = route.sections[i]
		var element: Dictionary = section.get("element", {})
		var kind: String = element.get("kind", section.get("kind", "?"))
		if section.get("kind") == "GRADE" or section.get("kind") == "CLOSURE":
			kind = section.name
		if current.get("element_id") == element.get("kind", "") + str(element.get("rise", element.get("apex_height", element.get("height", i)))):
			current.last = section.end_index
			continue
		current = {
			"kind": kind,
			"first": section.start_index,
			"last": section.end_index,
			"element_id": element.get("kind", "") + str(element.get("rise", element.get("apex_height", element.get("height", i)))),
		}
		groups.append(current)
	return groups


func _stats(route: Dictionary, a: int, b: int) -> Dictionary:
	var min_pitch := INF
	var max_pitch := -INF
	var max_bank := 0.0
	var min_n := INF
	var max_n := -INF
	var top := -INF
	var bottom := INF
	var apex := a
	var valley := a
	for i in range(a, b + 1):
		var pitch := rad_to_deg(asin(clampf(route.tangents[i].y, -1.0, 1.0)))
		min_pitch = minf(min_pitch, pitch)
		max_pitch = maxf(max_pitch, pitch)
		max_bank = maxf(max_bank, absf(route.banks[i]))
		min_n = minf(min_n, route.normal_g[i])
		max_n = maxf(max_n, route.normal_g[i])
		if route.positions[i].y > top:
			top = route.positions[i].y
			apex = i
		if route.positions[i].y < bottom:
			bottom = route.positions[i].y
			valley = i
	var width: float = Vector2(route.positions[b].x - route.positions[a].x, route.positions[b].z - route.positions[a].z).length()
	return {
		"min_pitch": min_pitch, "max_pitch": max_pitch, "max_bank": max_bank,
		"min_n": min_n, "max_n": max_n, "width": width, "height": top - bottom,
		"r_apex": 1.0 / maxf(route.curvatures[apex].length(), 0.0001),
		"r_valley": 1.0 / maxf(route.curvatures[valley].length(), 0.0001),
	}


## Stacked strips against ride time — the "ride it yourself" trace, now eleven channels deep.
func _render_channels(route: Dictionary, path: String) -> void:
	var rendered: Dictionary = Artifacts.channels(route)
	_save(rendered.image, path)
	for strip in rendered.strips:
		print("CHANNEL %-30s [%10.3f, %10.3f] %4d bounded %4d unbounded" % [
			strip.channel_id, strip.plot_min, strip.plot_max,
			strip.bounded_count, strip.unbounded_count,
		])


func _print_phases(route: Dictionary) -> void:
	for section in route.sections:
		var element: Dictionary = section.get("element", {})
		print("PHASE %-24s %-13s %6.0f m %6.1f s  v %5.1f -> %5.1f m/s" % [
			section.name, element.get("kind", section.kind),
			section.end_distance - section.start_distance,
			section.end_time - section.start_time,
			section.entry_speed, section.exit_speed,
		])
