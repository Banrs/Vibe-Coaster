class_name RouteSampling
extends RefCounted

## The viewer's accepted-route interpolation, shared by the live cameras, train and deterministic
## POV artifacts. Position and tangent come from one cubic Hermite curve over route distance:
## the rendered tangent is therefore the analytic derivative of the rendered position, rather
## than an independently slerped direction attached to a linear chord. Rider orientation is
## interpolated only to obtain an up candidate, then re-orthonormalised around that derivative.
##
## The force verifier's private row/channel interpolation answers a different measurement
## question and deliberately stays separate.

const FRAME_EPS_SQ := 0.000000000001


## Index of the span containing `value`, clamped to a real span at both ends.
static func lower_index(values: PackedFloat32Array, value: float) -> int:
	if values.size() < 2:
		return 0
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
	var times: PackedFloat32Array = route.get("times", PackedFloat32Array())
	var distances: PackedFloat32Array = route.get("distances", PackedFloat32Array())
	var duration := float(route.get("duration", 0.0))
	if times.size() < 2 or distances.size() != times.size() \
			or not is_finite(time_s) or not is_finite(duration) or duration <= 0.0:
		return 0.0
	var wrapped := fposmod(time_s, duration)
	var index := lower_index(times, wrapped)
	var interval := float(times[index + 1]) - float(times[index])
	if interval <= 0.0:
		return float(distances[index])
	return lerpf(
		distances[index],
		distances[index + 1],
		clampf((wrapped - float(times[index])) / interval, 0.0, 1.0)
	)


## Sample one internally consistent route state at a wrapped distance. The Hermite endpoint
## derivatives are the accepted unit tangents with respect to distance, so native samples are
## reproduced exactly and the interior path honours the integrated frame instead of cutting the
## corner with a chord.
static func sample_at_distance(route: Dictionary, distance_m: float) -> Dictionary:
	var distances: PackedFloat32Array = route.get("distances", PackedFloat32Array())
	var positions: PackedVector3Array = route.get("positions", PackedVector3Array())
	var tangents: PackedVector3Array = route.get("tangents", PackedVector3Array())
	var ups: PackedVector3Array = route.get("ups", PackedVector3Array())
	var rights: PackedVector3Array = route.get("rights", PackedVector3Array())
	var count := distances.size()
	var length := float(route.get("length", 0.0))
	if count < 2 or positions.size() != count or tangents.size() != count \
			or ups.size() != count or rights.size() != count \
			or not is_finite(distance_m) or not is_finite(length) or length <= 0.0:
		return {}
	var wrapped := fposmod(distance_m, length)
	var index := lower_index(distances, wrapped)
	var interval_m := float(distances[index + 1]) - float(distances[index])
	if not is_finite(interval_m) or interval_m <= 0.0:
		return {}
	var u := clampf(
		(wrapped - float(distances[index])) / interval_m, 0.0, 1.0)
	var tangent_0: Vector3 = tangents[index].normalized()
	var tangent_1: Vector3 = tangents[index + 1].normalized()
	var position := _hermite_position(
		positions[index], tangent_0, positions[index + 1], tangent_1, interval_m, u)
	var derivative := _hermite_distance_derivative(
		positions[index], tangent_0, positions[index + 1], tangent_1, interval_m, u)
	var tangent := derivative.normalized() if derivative.length_squared() > FRAME_EPS_SQ \
		else tangent_0.slerp(tangent_1, u).normalized()
	if tangent.length_squared() <= FRAME_EPS_SQ:
		return {}

	# Quaternion interpolation carries the authored twist through inversions. It does not get to
	# choose the tangent: its up axis is projected onto the Hermite derivative so position and
	# orientation remain one kinematic state.
	var basis_0 := Basis(rights[index], ups[index], -tangent_0).orthonormalized()
	var basis_1 := Basis(rights[index + 1], ups[index + 1], -tangent_1).orthonormalized()
	var orientation := basis_0.get_rotation_quaternion().slerp(
		basis_1.get_rotation_quaternion(), u)
	var up_candidate := Basis(orientation).y
	var up := up_candidate - tangent * up_candidate.dot(tangent)
	if up.length_squared() <= FRAME_EPS_SQ:
		up_candidate = ups[index].lerp(ups[index + 1], u)
		up = up_candidate - tangent * up_candidate.dot(tangent)
	if up.length_squared() <= FRAME_EPS_SQ:
		up_candidate = Vector3.UP if absf(tangent.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		up = up_candidate - tangent * up_candidate.dot(tangent)
	if up.length_squared() <= FRAME_EPS_SQ:
		return {}
	up = up.normalized()
	var right := tangent.cross(up)
	if right.length_squared() <= FRAME_EPS_SQ:
		return {}
	right = right.normalized()
	up = right.cross(tangent).normalized()
	return {
		"distance_m": wrapped,
		"sample_index": index,
		"amount": u,
		"position_m": position,
		"tangent": tangent,
		"rider_up": up,
		"right": right,
	}


static func pose_at_distance(route: Dictionary, distance_m: float) -> Transform3D:
	var sampled := sample_at_distance(route, distance_m)
	if sampled.is_empty():
		return Transform3D.IDENTITY
	return Transform3D(
		Basis(sampled.right, sampled.rider_up, -sampled.tangent).orthonormalized(),
		sampled.position_m
	)


static func _hermite_position(
	position_0: Vector3, tangent_0: Vector3,
	position_1: Vector3, tangent_1: Vector3,
	interval_m: float, u: float
) -> Vector3:
	var u2 := u * u
	var u3 := u2 * u
	var h00 := 2.0 * u3 - 3.0 * u2 + 1.0
	var h10 := u3 - 2.0 * u2 + u
	var h01 := -2.0 * u3 + 3.0 * u2
	var h11 := u3 - u2
	return h00 * position_0 + h10 * interval_m * tangent_0 \
		+ h01 * position_1 + h11 * interval_m * tangent_1


## Analytic d(position)/d(distance) of `_hermite_position`.
static func _hermite_distance_derivative(
	position_0: Vector3, tangent_0: Vector3,
	position_1: Vector3, tangent_1: Vector3,
	interval_m: float, u: float
) -> Vector3:
	var u2 := u * u
	var dh00 := 6.0 * u2 - 6.0 * u
	var dh10 := 3.0 * u2 - 4.0 * u + 1.0
	var dh01 := -6.0 * u2 + 6.0 * u
	var dh11 := 3.0 * u2 - 2.0 * u
	return (dh00 * position_0 + dh01 * position_1) / interval_m \
		+ dh10 * tangent_0 + dh11 * tangent_1
