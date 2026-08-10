class_name RouteSampling
extends RefCounted

## The viewer's route interpolation, as a pure utility: one lower-index search, one time→distance
## lerp, and one quaternion-slerped pose. The viewer and the deterministic POV artifacts must land
## on the same sample, so this is the single implementation and neither side keeps a copy.
## The force verifier's private per-field interpolation is deliberately different and stays there.


## Index of the span containing `value`, clamped to a real span at both ends.
static func lower_index(values: PackedFloat32Array, value: float) -> int:
	var low := 0
	var high := values.size() - 1
	while high - low > 1:
		var middle := floori((low + high) * 0.5)
		if values[middle] <= value:
			low = middle
		else:
			high = middle
	return low


static func distance_at_time(route: Dictionary, time_s: float) -> float:
	var times: PackedFloat32Array = route.times
	var wrapped := fposmod(time_s, float(route.duration))
	var index := lower_index(times, wrapped)
	return lerpf(
		route.distances[index],
		route.distances[index + 1],
		inverse_lerp(times[index], times[index + 1], wrapped)
	)


static func pose_at_distance(route: Dictionary, distance_m: float) -> Transform3D:
	var distances: PackedFloat32Array = route.distances
	var wrapped := fposmod(distance_m, float(route.length))
	var index := lower_index(distances, wrapped)
	var amount := inverse_lerp(distances[index], distances[index + 1], wrapped)
	var p0: Vector3 = route.positions[index]
	var p1: Vector3 = route.positions[index + 1]
	var basis0 := Basis(route.rights[index], route.ups[index], -route.tangents[index])
	var basis1 := Basis(route.rights[index + 1], route.ups[index + 1], -route.tangents[index + 1])
	var orientation := basis0.get_rotation_quaternion().slerp(basis1.get_rotation_quaternion(), amount)
	return Transform3D(Basis(orientation).orthonormalized(), p0.lerp(p1, amount))
