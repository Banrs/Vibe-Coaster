class_name RideTerrain
extends RefCounted

## Seeded analytic heightfield: a desert plain meeting one escarpment of ~275 m-class relief.
## The rise is two-part, like the real Tuwaiq-class escarpments: a gentle lower apron carrying
## ~20% of the relief, then a near-vertical upper face carrying the rest — the cliff the dive
## uses is deliberately smaller than the total elevation change. Everything is a pure function
## of the params dictionary, so the same seed gives bit-identical terrain and any caller
## (generator placement, clearance checks, meshes) shares one height field.


static func generate(rng: RandomNumberGenerator) -> Dictionary:
	var edge_angle := rng.randf_range(-0.35, 0.35)
	var relief := rng.randf_range(270.0, 285.0)
	var face_share := rng.randf_range(0.78, 0.85)
	return {
		"kind": "material",
		"relief": relief,
		"face_height": relief * face_share,
		"apron_height": relief * (1.0 - face_share),
		"edge_normal": Vector2(sin(edge_angle), -cos(edge_angle)),
		"edge_offset": rng.randf_range(-40.0, 40.0),
		"apron_width": rng.randf_range(240.0, 280.0),
		"face_width": rng.randf_range(38.0, 58.0),
		"wobble_amplitude": rng.randf_range(14.0, 28.0),
		"wobble_wavelength": rng.randf_range(420.0, 700.0),
		"detail_amplitude": rng.randf_range(1.8, 3.2),
		"noise_seed": rng.randi(),
	}


## Signed distance from the (wobbled) apron base line: negative on the plain, positive toward
## the plateau. The apron spans [0, apron_width], the steep face the next face_width beyond it.
static func edge_distance(terrain: Dictionary, x: float, z: float) -> float:
	var normal: Vector2 = terrain.edge_normal
	var along := Vector2(-normal.y, normal.x).dot(Vector2(x, z))
	var wobble: float = terrain.wobble_amplitude * _value_noise(
		along / terrain.wobble_wavelength, 0.37, terrain.noise_seed
	)
	return normal.dot(Vector2(x, z)) - terrain.edge_offset + wobble


static func height(terrain: Dictionary, x: float, z: float) -> float:
	var s := edge_distance(terrain, x, z)
	var apron: float = terrain.apron_height * _smoothstep01(s / terrain.apron_width)
	var face: float = terrain.face_height * _smoothstep01(
		(s - terrain.apron_width) / terrain.face_width
	)
	var detail: float = terrain.detail_amplitude * (
		_value_noise(x / 71.0, z / 71.0, terrain.noise_seed + 1)
		+ 0.4 * _value_noise(x / 23.0, z / 23.0, terrain.noise_seed + 2)
	)
	return apron + face + detail + _return_terrace_height(terrain, Vector2(x, z))


## Optional authored return terrace: one compact, deterministic elliptical bump over the existing
## heightfield. It is deliberately local; all other terrain remains the original analytic field.
static func _return_terrace_height(terrain: Dictionary, point_m: Vector2) -> float:
	var terrace_value: Variant = terrain.get("return_terrace")
	if not terrace_value is Dictionary:
		return 0.0
	var terrace: Dictionary = terrace_value
	var center_m: Vector2 = terrace.center_m
	var along: Vector2 = terrace.along
	var cross := Vector2(-along.y, along.x)
	var delta := point_m - center_m
	var along_distance := delta.dot(along)
	var cross_distance := delta.dot(cross)
	var r2 := (along_distance / float(terrace.half_length_m)) ** 2 \
		+ (cross_distance / float(terrace.half_width_m)) ** 2
	if r2 >= 1.0:
		return 0.0
	return float(terrace.elevation_m) * _smoothstep01(1.0 - r2)


static func _smoothstep01(x: float) -> float:
	var t := clampf(x, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Deterministic two-octave-free value noise in [-1, 1]; hand-rolled integer hash so results
## are identical across platforms and engine versions.
static func _value_noise(x: float, y: float, seed_value: int) -> float:
	var x0 := floori(x)
	var y0 := floori(y)
	var fx := x - x0
	var fy := y - y0
	var wx := fx * fx * (3.0 - 2.0 * fx)
	var wy := fy * fy * (3.0 - 2.0 * fy)
	var a := _hash01(x0, y0, seed_value)
	var b := _hash01(x0 + 1, y0, seed_value)
	var c := _hash01(x0, y0 + 1, seed_value)
	var d := _hash01(x0 + 1, y0 + 1, seed_value)
	return lerpf(lerpf(a, b, wx), lerpf(c, d, wx), wy) * 2.0 - 1.0


static func _hash01(ix: int, iy: int, seed_value: int) -> float:
	var h := ix * 374761393 + iy * 668265263 + seed_value * 2246822519
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)
