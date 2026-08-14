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
const Overlay := preload("res://fidelity_overlay.gd")
const References := preload("res://fidelity_references.gd")
const RouteContract := preload("res://route_contract.gd")
const Verify := preload("res://verify.gd")

const AUDIT_SEEDS := [11, 42, 20260809, 1, 3, 7, 99, 256, 555, 1234, 4096, 31337, 77777, 123456, 20250101]
const DEEP_REVIEW_SEEDS := [11, 42, 20260809]
## The pinned pre-foundation legacy commit this baseline measures (plan Task 1, Step 0).
const LEGACY_BASE_COMMIT := "3fa14885bef2daf3a7d9c0e544424cb6a296fd99"
const OVERLAY_MANIFEST_PATH := "res://../docs/evidence/fidelity/rfdb-local-overlay-manifest.json"

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

	var seed_42_measurement: Dictionary = {}
	for measurement: Dictionary in audit.measurements:
		if measurement.get("seed") == 42: seed_42_measurement = measurement
	var local_files := _local_rfdb_files(func(name: String): return OS.get_environment(name))
	var overlays := {}
	if not local_files.is_empty():
		var manifest_bytes := FileAccess.get_file_as_bytes(OVERLAY_MANIFEST_PATH)
		overlays = _build_overlays(manifest_bytes, local_files, seed_42_measurement,
			audit.routes_by_seed.get(42, {}), References.CATALOG.transforms,
			Callable(Overlay, "build"))
	if overlays.get("status") == "invalid-input":
		for error in overlays.get("errors", ["overlay manifest is invalid"]):
			_operational.append(str(error))
		return _fail()
	var report := _artifact_report(audit, References.CATALOG, LEGACY_BASE_COMMIT, overlays)
	if report.get("schema_version") != "ride-fidelity-audit@1":
		for error in report.get("errors", ["artifact_report: the audit report was not built"]):
			_operational.append(str(error))
		return _fail()
	for error in _write_artifact_pack(OUT, report, audit.routes_by_seed, overlays):
		_operational.append(str(error))
	if not _operational.is_empty():
		return _fail()

	for line in _diagnostic_lines(report, OUT): print(line)
	_print_findings(report)
	print("AUDIT %d seeds, %d render requests, pack written to %s" % [
		AUDIT_SEEDS.size(), report.render_requests.size(), OUT])
	return 0


static func _build_overlays(
	manifest_bytes: PackedByteArray, local_files: Dictionary,
	measurement: Dictionary, route: Dictionary, transforms: Dictionary, overlay_build: Callable
) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(manifest_bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return {"status": "invalid-input", "errors": ["overlay manifest bytes are not JSON"]}
	var parsed: Dictionary = parser.data
	return overlay_build.call(parsed, manifest_bytes, local_files, measurement, route, transforms)


static func _local_rfdb_files(environment_lookup: Callable) -> Dictionary:
	var local_files := {}
	for pair in [["RFDB_4804_CSV", "rfdb-4804"], ["RFDB_6383_CSV", "rfdb-6383"]]:
		var path: Variant = environment_lookup.call(pair[0])
		if path is String and not path.is_empty(): local_files[pair[1]] = path
	return local_files


static func _artifact_report(
	audit: Dictionary, catalog: Dictionary, legacy_base_commit: String, overlays: Dictionary
) -> Dictionary:
	if overlays.is_empty():
		return Artifacts.build_report(audit.measurements, audit.comparison, catalog,
			legacy_base_commit, audit.generation_counts)
	return Artifacts.build_report(audit.measurements, audit.comparison, catalog,
		legacy_base_commit, audit.generation_counts, true)


static func _write_artifact_pack(
	output_dir: String, report: Dictionary, routes_by_seed: Dictionary, overlays: Dictionary
) -> PackedStringArray:
	if overlays.is_empty(): return Artifacts.write_pack(output_dir, report, routes_by_seed)
	return Artifacts.write_pack(output_dir, report, routes_by_seed, overlays)


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
	return Fidelity.measure_route(route, RouteContract.ROW_OFFSETS)


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
	print("EVIDENCE comparison gaps %d  catalogued gaps %d  observed-only samples %d  recommendation %s" % [
		report.evidence_gaps.size(), report.catalog_evidence_gaps.size(), report.observed_only.size(),
		report.recommendation.get("status", "none"),
	])


static func _diagnostic_lines(report: Dictionary, output_dir: String) -> PackedStringArray:
	var lines := PackedStringArray()
	for summary: Dictionary in report.get("measurement_summaries", []):
		if summary.get("seed") != 42: continue
		for beat: Dictionary in summary.get("beats", []):
			lines.append("BEAT %s %s %s" % [beat.get("beat_id", ""), beat.get("kind", ""),
				str(beat.get("window_s", []))])
	for seed_value in DEEP_REVIEW_SEEDS:
		var path := "%s/review/seed-%d/channels.json" % [output_dir.rstrip("/"), seed_value]
		var legend: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not legend is Dictionary: continue
		for strip: Dictionary in legend.get("strips", []):
			lines.append("CHANNEL %d %s %s %s" % [seed_value, strip.get("channel_id", ""),
				str(strip.get("plot_min", "")), str(strip.get("plot_max", ""))])
	return lines
