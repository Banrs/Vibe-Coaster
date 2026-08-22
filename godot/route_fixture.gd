extends RefCounted
class_name RouteFixture

## Chainable builder for the synthetic route Dictionaries the focused-test suites hand-roll.
## `build()` returns a Dictionary containing exactly the keys a caller set — callers that only
## need a handful of the standard route-channel keys (as several suites do) get exactly that
## subset, matching the fixtures this replaces. Each setter mutates in place and returns `self`,
## so calls may chain or run as separate statements.

var _data := {}


func seed(value: int) -> RouteFixture:
	_data.seed = value
	return self


func length(value: float) -> RouteFixture:
	_data.length = value
	return self


func duration(value: float) -> RouteFixture:
	_data.duration = value
	return self


func points(value: PackedVector3Array) -> RouteFixture:
	_data.positions = value
	return self


func tangents(value: PackedVector3Array) -> RouteFixture:
	_data.tangents = value
	return self


func ups(value: PackedVector3Array) -> RouteFixture:
	_data.ups = value
	return self


func rights(value: PackedVector3Array) -> RouteFixture:
	_data.rights = value
	return self


func curvatures(value: PackedVector3Array) -> RouteFixture:
	_data.curvatures = value
	return self


func banks(value: PackedFloat32Array) -> RouteFixture:
	_data.banks = value
	return self


func speeds(value: PackedFloat32Array) -> RouteFixture:
	_data.speeds = value
	return self


## Sets one of the scalar per-sample channels by name (`normal_g`, `lateral_g`,
## `longitudinal_g`, `roll_rates`, or any other PackedFloat32Array-valued key).
func channel(name: String, value: PackedFloat32Array) -> RouteFixture:
	_data[name] = value
	return self


func distances(value: PackedFloat32Array) -> RouteFixture:
	_data.distances = value
	return self


func times(value: PackedFloat32Array) -> RouteFixture:
	_data.times = value
	return self


func span_indices(value: PackedInt32Array) -> RouteFixture:
	_data.span_indices = value
	return self


## Groups flat role-window Dictionaries (each already carrying `story_slot_id`/`first`/`last`)
## into gesture windows via `group_roles()` and sets the result.
func roles(role_windows: Array) -> RouteFixture:
	_data.gesture_windows = RouteFixture.group_roles(role_windows)
	return self


func gesture_windows(value: Array) -> RouteFixture:
	_data.gesture_windows = value
	return self


## Merges arbitrary extra keys (e.g. a `terrain` block) into the built Dictionary, overwriting
## any key already set.
func extra(values: Dictionary) -> RouteFixture:
	_data.merge(values, true)
	return self


func build() -> Dictionary:
	return _data


## A PackedVector3Array of `count` copies of `value` — the common flat per-sample channel
## (constant tangent/up/right/curvature) several fixtures share.
static func flat_vector3(value: Vector3, count: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(count)
	out.fill(value)
	return out


## A PackedFloat32Array of `count` copies of `value` — the common flat per-sample channel
## (constant bank/speed/g-load) several fixtures share.
static func flat_float(value: float, count: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(count)
	out.fill(value)
	return out


## Groups consecutive role windows that share a `story_slot_id` into one gesture window each,
## in role order.
static func group_roles(role_windows: Array) -> Array:
	var gestures := []
	for role: Dictionary in role_windows:
		var story: String = role.story_slot_id
		if gestures.is_empty() or String(gestures[-1].story_slot_id) != story:
			gestures.append({"story_slot_id": story, "first": role.first, "last": role.last,
				"role_windows": []})
		gestures[-1].role_windows.append(role)
		gestures[-1].last = role.last
	return gestures


## The span-owner channel several fixtures build by hand: `count` samples, with the owner index
## incrementing at each of `span_starts` in order.
static func span_indices_for(count: int, span_starts: Array) -> PackedInt32Array:
	var owners := PackedInt32Array()
	owners.resize(count)
	var span_index := 0
	for sample_index in count:
		if span_index < span_starts.size() and sample_index == int(span_starts[span_index]):
			span_index += 1
		owners[sample_index] = span_index
	return owners
