extends SceneTree

## Inspection harness (not part of the smoke gate) and the offline fidelity-audit runner: it
## generates the fixed fleet exactly once per seed, measures every seed against the committed
## evidence catalog, writes the checked baseline pack, and keeps the console/PNG diagnostics —
## per-element geometry stats, phase tables, element side views, top/elevation, and the stacked
## ride-channel traces — for visual comparison against the measured references in docs/TELEMETRY.md.
## Every render lives in RideFidelityArtifacts, which the audit pack shares.
##
## It also writes the geometry half of the audit (issue 24 — the forces can be right while the
## swept shape is wrong): review/seed-<n>/geometry-metrics.{json,md} for each deep-review seed
## and review/counterpart-comparison.{json,md} for the fleet. With REF_MEDIA_MANIFEST pointing at
## a valid LOCAL reference manifest it additionally writes review/overlays/geometry/<element>.png,
## the reference frame beside the generated element side view. Reference media is personal-use,
## gitignored, and acquired outside the engine by tools/fetch-reference-media.sh: there is no
## network client in godot/ and none may be added.
##
## Operational failures (catalog, generation, physical consistency, artifact writes) exit 1;
## fidelity and geometry findings are diagnostic and still exit 0.
## Run: godot --headless --path godot --script res://_inspect.gd  [output dir via INSPECT_OUT]

const Generator := preload("res://generator.gd")
const Artifacts := preload("res://fidelity_artifacts.gd")
const Fidelity := preload("res://fidelity.gd")
const GeometryMetrics := preload("res://geometry_metrics.gd")
const GeometryReference := preload("res://geometry_reference.gd")
const Overlay := preload("res://fidelity_overlay.gd")
const References := preload("res://fidelity_references.gd")
const RouteContract := preload("res://route_contract.gd")
const Verify := preload("res://verify.gd")

const AUDIT_SEEDS := [11, 42, 20260809, 1, 3, 7, 99, 256, 555, 1234, 4096, 31337, 77777, 123456, 20250101]
const DEEP_REVIEW_SEEDS := [11, 42, 20260809]
## The pinned pre-foundation legacy commit this baseline measures (plan Task 1, Step 0).
const LEGACY_BASE_COMMIT := "3fa14885bef2daf3a7d9c0e544424cb6a296fd99"
const OVERLAY_MANIFEST_PATH := "res://../docs/evidence/fidelity/rfdb-local-overlay-manifest.json"
## Optional local photographic reference for element geometry (issue 24). The media itself is
## personal-use, gitignored and acquired outside the engine by tools/fetch-reference-media.sh;
## nothing in godot/ fetches anything. Unset, the geometry report declares the overlays a gap.
const REFERENCE_MANIFEST_ENV := "REF_MEDIA_MANIFEST"
const GEOMETRY_OVERLAY_SEED := 42

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
	var include_generated_povs := OS.get_environment("INSPECT_GENERATED_POVS") == "1"
	var report := _artifact_report(audit, References.CATALOG, LEGACY_BASE_COMMIT, overlays,
		include_generated_povs)
	if report.get("schema_version") != "ride-fidelity-audit@1":
		for error in report.get("errors", ["artifact_report: the audit report was not built"]):
			_operational.append(str(error))
		return _fail()
	var reference := _reference_media(OS.get_environment(REFERENCE_MANIFEST_ENV))
	if reference.get("status") == "invalid-manifest":
		for error in reference.get("errors", ["reference manifest is invalid"]):
			_operational.append("reference_manifest: %s" % str(error))
		return _fail()
	var geometry := _write_geometry_pack(OUT, audit.routes_by_seed, reference)
	for error in geometry.errors:
		_operational.append(str(error))
	if not _operational.is_empty():
		return _fail()
	for error in _write_artifact_pack(OUT, report, audit.routes_by_seed, overlays,
			geometry.records):
		_operational.append(str(error))
	if not _operational.is_empty():
		return _fail()

	for line in _diagnostic_lines(report, OUT): print(line)
	for line in _geometry_lines(geometry.comparisons, reference): print(line)
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
	audit: Dictionary, catalog: Dictionary, legacy_base_commit: String, overlays: Dictionary,
	include_generated_povs: bool = false
) -> Dictionary:
	if overlays.is_empty():
		return Artifacts.build_report(audit.measurements, audit.comparison, catalog,
			legacy_base_commit, audit.generation_counts, include_generated_povs)
	return Artifacts.build_report(audit.measurements, audit.comparison, catalog,
		legacy_base_commit, audit.generation_counts, true or include_generated_povs)


static func _write_artifact_pack(
	output_dir: String, report: Dictionary, routes_by_seed: Dictionary, overlays: Dictionary,
	extra_records: Array = []
) -> PackedStringArray:
	return Artifacts.write_pack(output_dir, report, routes_by_seed, overlays, extra_records)


## The local reference manifest, if the operator supplied one. Absent is the normal case and is a
## declared gap, not a failure; only a structurally invalid manifest is operational. There is no
## network access here and none may be added: acquisition is tools/fetch-reference-media.sh.
static func _reference_media(path: String) -> Dictionary:
	if path.is_empty():
		return {}
	if not FileAccess.file_exists(path):
		return {"status": "manifest-missing", "path": path, "entries": [], "errors": []}
	return GeometryReference.build(FileAccess.get_file_as_bytes(path), path.get_base_dir())


## Geometry artifacts for the deep-review seeds, written through the same checked writers as the
## rest of the pack and handed to `write_pack` as records so `manifest.json` holds them too.
## Findings are diagnostic; only a failed write is operational. Returns
## `{errors, records, comparisons}`.
func _write_geometry_pack(
	output_dir: String, routes_by_seed: Dictionary, reference: Dictionary
) -> Dictionary:
	var errors := PackedStringArray()
	var records := []
	var root := output_dir.rstrip("/")
	var comparisons := []
	for seed_value in DEEP_REVIEW_SEEDS:
		var route: Dictionary = routes_by_seed[seed_value]
		var pack: Dictionary = GeometryMetrics.measure(route)
		var stem := "review/seed-%d" % seed_value
		var json := Artifacts.canonical_json(pack)
		if json.is_empty():
			errors.append("artifact_write: seed %d geometry pack is not canonical JSON data"
				% seed_value)
			continue
		_write_geometry_file(root, "%s/geometry-metrics.json" % stem, "geometry-metrics",
			json, seed_value, records, errors)
		_write_geometry_file(root, "%s/geometry-metrics.md" % stem, "geometry-metrics",
			GeometryMetrics.markdown(pack, reference), seed_value, records, errors)
		comparisons.append(GeometryMetrics.counterpart_comparison(route))
		if seed_value == GEOMETRY_OVERLAY_SEED:
			_write_geometry_overlays(root, route, reference, records, errors)
	var fleet := {
		"schema_version": GeometryMetrics.COUNTERPART_SCHEMA,
		"judgement": "report-only",
		"seeds": DEEP_REVIEW_SEEDS.duplicate(),
		"comparisons": comparisons,
	}
	var fleet_json := Artifacts.canonical_json(fleet)
	if fleet_json.is_empty():
		errors.append("artifact_write: the counterpart comparison is not canonical JSON data")
		return {"errors": errors, "records": records, "comparisons": comparisons}
	_write_geometry_file(root, "review/counterpart-comparison.json", "counterpart-comparison",
		fleet_json, null, records, errors)
	_write_geometry_file(root, "review/counterpart-comparison.md", "counterpart-comparison",
		GeometryMetrics.counterpart_markdown(comparisons), null, records, errors)
	return {"errors": errors, "records": records, "comparisons": comparisons}


## One checked write plus its manifest record, in the shape `write_pack` records its own files.
static func _write_geometry_file(
	root: String, path: String, artifact_kind: String, content: Variant, seed_value: Variant,
	records: Array, errors: PackedStringArray
) -> void:
	var absolute := "%s/%s" % [root, path]
	var made := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if made != OK and made != ERR_ALREADY_EXISTS:
		errors.append("artifact_write: cannot create '%s' (%s)"
			% [absolute.get_base_dir(), error_string(made)])
		return
	var failures := (
		Artifacts.save_png_checked(content, absolute) if content is Image
		else Artifacts.write_text_checked(absolute, content)
	)
	if failures.is_empty():
		records.append({
			"path": path, "artifact_kind": artifact_kind, "seed": seed_value, "beat_id": null,
		})
	errors.append_array(failures)


## Side-by-side composites: the local reference frame against the generated element side view.
## Only entries whose local file is present and hashes correctly produce an image; every other
## entry is already recorded as a gap in the manifest record the Markdown prints.
func _write_geometry_overlays(
	root: String, route: Dictionary, reference: Dictionary, records: Array,
	errors: PackedStringArray
) -> void:
	if reference.get("status") != "ok":
		return
	for entry_value in reference.entries:
		var entry: Dictionary = entry_value
		if entry.status != "available":
			continue
		var geometry: Dictionary = GeometryMetrics.element_geometry(route, str(entry.element_id))
		if geometry.get("status") != "resolved":
			continue
		var image := GeometryReference.load_reference_image(str(entry.resolved_path))
		if image == null:
			errors.append("artifact_write: reference image '%s' did not reopen"
				% str(entry.image_path))
			continue
		var generated := Artifacts.side_image(route, int(geometry.first), int(geometry.last))
		var composite := GeometryReference.composite(image, generated,
			GeometryReference.footer_lines(str(entry.element_id), geometry.shape,
				geometry.planarity, entry))
		_write_geometry_file(root, "review/overlays/geometry/%s.png"
			% str(entry.element_id).replace("/", "__"), "geometry-overlay", composite,
			GEOMETRY_OVERLAY_SEED, records, errors)


static func _geometry_lines(comparisons: Array, reference: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	for comparison: Dictionary in comparisons:
		var totals: Dictionary = comparison.get("totals", {})
		var keys: Array = totals.keys()
		keys.sort()
		var parts := PackedStringArray()
		for key in keys:
			parts.append("%s %d" % [str(key), int(totals[key])])
		lines.append("COUNTERPART seed %s  %s" % [
			str(comparison.get("seed", "")), "  ".join(parts)])
	if reference.is_empty():
		lines.append("REFERENCE none (REF_MEDIA_MANIFEST unset) — geometry overlays are a declared gap")
	else:
		lines.append("REFERENCE %s entries %d available %d" % [
			str(reference.get("status", "")), int(reference.get("entry_count", 0)),
			int(reference.get("available_count", 0))])
	return lines


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
