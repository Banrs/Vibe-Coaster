class_name RideGeometryReference
extends RefCounted

## Local-only photographic reference for element geometry (issue 24).
##
## Force tables cannot tell you that a camelback leans sideways; a photograph of the real element
## next to the generated silhouette can. This file validates a LOCAL manifest of reference frames
## and composites them against the generated element side view.
##
## POLICY, and it is not negotiable here:
##   * There is no network client in godot/ and this file adds none. Acquisition happens outside
##     the engine, via tools/fetch-reference-media.sh, into a gitignored directory.
##   * Reference media is personal-use local reference and is NEVER committed. Only the manifest's
##     landmarks, provenance and digests are ever fit to commit, and even the live manifest lives
##     beside the media rather than in the repository.
##   * Everything produced here is diagnostic. A composite image is evidence to read. It promotes
##     no source, creates no catalog target, and closes no issue.
##
## The manifest path arrives in the REF_MEDIA_MANIFEST environment variable. Absent or invalid,
## the geometry report simply declares reference overlays as a gap — that is the honest default,
## not a failure.

const MANIFEST_SCHEMA := "geometry-reference-manifest@1"
const SCHEMA := "geometry-reference-overlays@1"

const PANE_SIZE := Vector2i(1100, 700)
const FOOTER_HEIGHT := 132
const DIVIDER := 2
const BACKGROUND := Color(0.09, 0.10, 0.12)
const FOOTER_BACKGROUND := Color(0.05, 0.06, 0.07)
const DIVIDER_COLOR := Color(0.35, 0.38, 0.44)
const TEXT_COLOR := Color(0.86, 0.90, 0.95)
const LABEL_COLOR := Color(0.55, 0.95, 1.0)
const TEXT_SCALE := 2
const GLYPH_SIZE := Vector2i(5, 7)

const REQUIRED_ENTRY_KEYS := ["element_id", "image_path", "provenance"]
const REQUIRED_PROVENANCE_KEYS := ["source_id", "evidence_class", "sha256", "acquisition"]


# ---------------------------------------------------------------------------------------------
# Manifest loading and validation
# ---------------------------------------------------------------------------------------------

## Parse and validate a manifest, then resolve every entry's local file independently. One bad
## entry never disqualifies the others; only a structurally invalid manifest is rejected whole.
static func build(manifest_bytes: PackedByteArray, base_dir: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(manifest_bytes.get_string_from_utf8()) != OK or not parser.data is Dictionary:
		return _invalid(["reference manifest bytes are not a JSON object"])
	var manifest: Dictionary = parser.data
	var errors := validate(manifest)
	if not errors.is_empty():
		return _invalid(Array(errors))
	var entries := []
	var available := 0
	for entry_value in manifest.entries:
		var entry: Dictionary = entry_value
		var resolved := _resolve(entry, base_dir)
		if resolved.status == "available":
			available += 1
		entries.append(resolved)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return "%s|%s" % [a.element_id, a.image_path] < "%s|%s" % [b.element_id, b.image_path])
	return {
		"schema_version": SCHEMA,
		"status": "ok",
		"manifest_schema": MANIFEST_SCHEMA,
		"manifest_sha256": _sha(manifest_bytes),
		"manifest_version": str(manifest.get("manifest_version", "")),
		"base_dir": base_dir,
		"entry_count": entries.size(),
		"available_count": available,
		"entries": entries,
		"errors": [],
		"judgement": "report-only",
	}


static func validate(manifest: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if manifest.get("schema_version") != MANIFEST_SCHEMA:
		errors.append("reference manifest schema_version must be '%s'" % MANIFEST_SCHEMA)
	if not manifest.get("entries") is Array:
		errors.append("reference manifest entries must be an Array")
		errors.sort()
		return errors
	if manifest.entries.is_empty():
		errors.append("reference manifest declares no entries")
	var seen := {}
	for index in manifest.entries.size():
		var value: Variant = manifest.entries[index]
		if not value is Dictionary:
			errors.append("reference entry %d is not a Dictionary" % index)
			continue
		var entry: Dictionary = value
		for key in REQUIRED_ENTRY_KEYS:
			if not entry.has(key):
				errors.append("reference entry %d is missing %s" % [index, key])
		if not _text(entry.get("element_id")) or not _text(entry.get("image_path")):
			errors.append("reference entry %d has an empty element_id or image_path" % index)
			continue
		# One element id owns one composite path, so a second entry for it would silently
		# overwrite the first. Reject the ambiguity instead of picking a winner.
		if seen.has(entry.element_id):
			errors.append("reference entry %d duplicates element '%s'" % [index, entry.element_id])
		seen[entry.element_id] = true
		if entry.image_path.begins_with("/") or entry.image_path.contains(".."):
			errors.append("reference entry %d image_path must be relative and contain no '..'" % index)
		if not entry.get("provenance") is Dictionary:
			errors.append("reference entry %d provenance must be a Dictionary" % index)
			continue
		var provenance: Dictionary = entry.provenance
		for key_name in REQUIRED_PROVENANCE_KEYS:
			if not provenance.has(key_name):
				errors.append("reference entry %d provenance is missing %s" % [index, key_name])
		if not _hex(provenance.get("sha256"), 64):
			errors.append("reference entry %d provenance sha256 must be lowercase 64-hex" % index)
		if not _text(provenance.get("source_id")):
			errors.append("reference entry %d provenance source_id must be a non-empty String" % index)
		var timestamp: Variant = provenance.get("timestamp_s")
		var description: Variant = provenance.get("description")
		if timestamp == null and not _text(description):
			errors.append(
				"reference entry %d needs a timestamp_s or a photo description" % index)
		elif timestamp != null and not _number(timestamp):
			errors.append("reference entry %d timestamp_s must be a finite number or null" % index)
	errors.sort()
	return errors


static func _resolve(entry: Dictionary, base_dir: String) -> Dictionary:
	var provenance: Dictionary = entry.provenance
	var relative := str(entry.image_path)
	var absolute := relative if base_dir.is_empty() else base_dir.path_join(relative)
	var record := {
		"element_id": str(entry.element_id),
		"image_path": relative,
		"resolved_path": absolute,
		"source_id": str(provenance.get("source_id", "")),
		"source_url": str(provenance.get("source_url", "")),
		"evidence_class": str(provenance.get("evidence_class", "")),
		"acquisition": str(provenance.get("acquisition", "")),
		"timestamp_s": provenance.get("timestamp_s"),
		"description": str(provenance.get("description", "")),
		"expected_sha256": str(provenance.get("sha256", "")),
		"observed_sha256": null,
		"caveats": _strings(entry.get("caveats", [])),
		"width": null,
		"height": null,
	}
	if not FileAccess.file_exists(absolute):
		record["status"] = "file-missing"
		return record
	var bytes := FileAccess.get_file_as_bytes(absolute)
	if bytes.is_empty():
		record["status"] = "file-empty"
		return record
	record["observed_sha256"] = _sha(bytes)
	if record.observed_sha256 != record.expected_sha256:
		record["status"] = "digest-mismatch"
		return record
	var image := _load_image(absolute, bytes)
	if image == null:
		record["status"] = "not-a-readable-image"
		return record
	record["status"] = "available"
	record["width"] = image.get_width()
	record["height"] = image.get_height()
	return record


static func load_reference_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	return _load_image(path, FileAccess.get_file_as_bytes(path))


static func _load_image(path: String, bytes: PackedByteArray) -> Image:
	var image := Image.new()
	var extension := path.get_extension().to_lower()
	var error := ERR_FILE_UNRECOGNIZED
	if extension == "png":
		error = image.load_png_from_buffer(bytes)
	elif extension == "jpg" or extension == "jpeg":
		error = image.load_jpg_from_buffer(bytes)
	elif extension == "webp":
		error = image.load_webp_from_buffer(bytes)
	if error != OK or image.get_width() <= 0 or image.get_height() <= 0:
		return null
	return image


# ---------------------------------------------------------------------------------------------
# Composite rendering
# ---------------------------------------------------------------------------------------------

## Left: the local reference frame, scaled into its pane. Right: the generated element side view.
## Footer: the element's shape_ratios numbers, so the eye and the numbers are read together.
static func composite(
	reference: Image, generated: Image, footer_lines: PackedStringArray
) -> Image:
	var width := PANE_SIZE.x * 2 + DIVIDER
	var height := PANE_SIZE.y + FOOTER_HEIGHT
	var canvas := Image.create(width, height, false, Image.FORMAT_RGB8)
	canvas.fill(BACKGROUND)
	if reference != null:
		_blit_fitted(canvas, reference, Rect2i(Vector2i.ZERO, PANE_SIZE))
	if generated != null:
		_blit_fitted(canvas, generated, Rect2i(Vector2i(PANE_SIZE.x + DIVIDER, 0), PANE_SIZE))
	for x in range(PANE_SIZE.x, PANE_SIZE.x + DIVIDER):
		for y in PANE_SIZE.y:
			canvas.set_pixel(x, y, DIVIDER_COLOR)
	for y in range(PANE_SIZE.y, height):
		for x in width:
			canvas.set_pixel(x, y, FOOTER_BACKGROUND)
	_draw_text(canvas, "REFERENCE (LOCAL, NOT COMMITTED)", Vector2i(12, PANE_SIZE.y + 10),
		TEXT_SCALE, LABEL_COLOR)
	_draw_text(canvas, "GENERATED SIDE VIEW", Vector2i(PANE_SIZE.x + DIVIDER + 12, PANE_SIZE.y + 10),
		TEXT_SCALE, LABEL_COLOR)
	var line_index := 0
	for line in footer_lines:
		var y := PANE_SIZE.y + 34 + line_index * (GLYPH_SIZE.y * TEXT_SCALE + 6)
		if y + GLYPH_SIZE.y * TEXT_SCALE >= height:
			break
		_draw_text(canvas, line, Vector2i(12, y), TEXT_SCALE, TEXT_COLOR)
		line_index += 1
	return canvas


static func _blit_fitted(canvas: Image, source: Image, pane: Rect2i) -> void:
	var image := source.duplicate()
	if image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGB8)
	var scale := minf(
		float(pane.size.x) / float(image.get_width()),
		float(pane.size.y) / float(image.get_height())
	)
	var target := Vector2i(
		maxi(1, int(floor(float(image.get_width()) * scale))),
		maxi(1, int(floor(float(image.get_height()) * scale)))
	)
	if target != Vector2i(image.get_width(), image.get_height()):
		image.resize(target.x, target.y, Image.INTERPOLATE_BILINEAR)
	var origin := pane.position + (pane.size - target) / 2
	canvas.blit_rect(image, Rect2i(Vector2i.ZERO, target), origin)


## The footer text for one element, built from its shape_ratios and planarity records.
static func footer_lines(
	element_id: String, shape: Dictionary, planarity: Dictionary, provenance: Dictionary
) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("ELEMENT %s" % element_id.to_upper())
	if shape.is_empty():
		lines.append("NO GENERATED SHAPE RECORD")
	else:
		lines.append("HEIGHT %s M   HORIZ %s M   LENGTH %s M   H/L %s" % [
			_fixed(shape.get("height_extent_m"), 1), _fixed(shape.get("horizontal_extent_m"), 1),
			_fixed(shape.get("track_length_m"), 1), _fixed(shape.get("height_to_length_ratio"), 3),
		])
		lines.append("HEADING %s DEG   PITCH IN %s OUT %s   BANK IN %s OUT %s" % [
			_fixed(shape.get("total_heading_change_deg"), 1),
			_fixed(shape.get("entry_pitch_deg"), 1), _fixed(shape.get("exit_pitch_deg"), 1),
			_fixed(shape.get("entry_bank_deg"), 1), _fixed(shape.get("exit_bank_deg"), 1),
		])
	if not planarity.is_empty():
		lines.append("PLANE %s   RMS OFF-PLANE %s M   TILT OFF VERTICAL %s DEG" % [
			str(planarity.get("planarity_class", "")).to_upper(),
			_fixed(planarity.get("rms_out_of_plane_m"), 2),
			_fixed(planarity.get("vertical_plane_tilt_deg"), 2),
		])
	lines.append("REF %s   %s" % [
		str(provenance.get("source_id", "")).to_upper(),
		str(provenance.get("acquisition", "")).to_upper(),
	])
	return lines


# ---------------------------------------------------------------------------------------------
# A 5x7 bitmap font. The repository has no font resource and the images must stay self-contained,
# so the glyphs are literal pixel rows. Unknown characters render as blank.
# ---------------------------------------------------------------------------------------------

const GLYPHS := {
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
	"6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01110", "10001", "10000", "10000", "10000", "10001", "01110"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01110", "10001", "10000", "10111", "10001", "10001", "01111"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
	"J": ["00111", "00010", "00010", "00010", "00010", "10010", "01100"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	"W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
	"Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
	".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
	",": ["00000", "00000", "00000", "00000", "01100", "01100", "01000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	"+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
	":": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
	"/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
	"%": ["11001", "11010", "00010", "00100", "01000", "01011", "10011"],
	"(": ["00010", "00100", "01000", "01000", "01000", "00100", "00010"],
	")": ["01000", "00100", "00010", "00010", "00010", "00100", "01000"],
	"_": ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
	"#": ["01010", "01010", "11111", "01010", "11111", "01010", "01010"],
}


static func _draw_text(
	image: Image, text: String, origin: Vector2i, scale: int, color: Color
) -> void:
	var cursor := origin
	var advance := (GLYPH_SIZE.x + 1) * scale
	for index in text.length():
		var character := text.substr(index, 1).to_upper()
		if character != " " and GLYPHS.has(character):
			_draw_glyph(image, GLYPHS[character], cursor, scale, color)
		cursor.x += advance
		if cursor.x + GLYPH_SIZE.x * scale > image.get_width():
			return


static func _draw_glyph(
	image: Image, rows: Array, origin: Vector2i, scale: int, color: Color
) -> void:
	for row in rows.size():
		var pattern: String = rows[row]
		for column in pattern.length():
			if pattern[column] != "1":
				continue
			for dy in scale:
				for dx in scale:
					var x := origin.x + column * scale + dx
					var y := origin.y + row * scale + dy
					if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
						image.set_pixel(x, y, color)


# ---------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------

static func _invalid(errors: Array) -> Dictionary:
	var sorted := errors.duplicate()
	sorted.sort()
	return {
		"schema_version": SCHEMA, "status": "invalid-manifest",
		"manifest_schema": MANIFEST_SCHEMA, "entries": [], "entry_count": 0,
		"available_count": 0, "errors": sorted, "judgement": "report-only",
	}


static func _fixed(value: Variant, digits: int) -> String:
	if not _number(value):
		return "N/A"
	return String.num(float(value), digits)


static func _strings(value: Variant) -> Array:
	var output := []
	if value is Array:
		for item in value:
			output.append(str(item))
	return output


static func _sha(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _text(value: Variant) -> bool:
	return value is String and not str(value).is_empty()


static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


static func _hex(value: Variant, length: int) -> bool:
	if not value is String or str(value).length() != length:
		return false
	for character in str(value):
		if character not in "0123456789abcdef":
			return false
	return true
