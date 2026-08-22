extends SceneTree

const Sampling := preload("res://route_sampling.gd")
const POSITION_EPS := 0.00001
const DIRECTION_EPS := 0.0001

var _t := TestUtil.new()


func _initialize() -> void:
	_test_distance_time_mapping()
	_test_curved_interval_uses_endpoint_tangents()
	_test_rendered_tangent_is_position_derivative()
	_test_distance_wrap_is_deterministic()
	_t.finish(self)


func _test_distance_time_mapping() -> void:
	var route := _curved_route()
	_t.expect_close(Sampling.distance_at_time(route, 0.25), 2.5,
		"time-to-distance mapping interpolates the accepted distance channel", POSITION_EPS)
	_t.expect_close(Sampling.distance_at_time(route, 1.25), 2.5,
		"time-to-distance mapping wraps one complete lap", POSITION_EPS)


func _test_curved_interval_uses_endpoint_tangents() -> void:
	var route := _curved_route()
	var pose := Sampling.pose_at_distance(route, 5.0)
	# Cubic Hermite at u=0.5 with ds=10, p0=(0,0,0), p1=(10,0,0),
	# dp/ds|0=(1,0,0), dp/ds|1=(0,0,-1):
	# 0.5*p0 + 0.125*ds*t0 + 0.5*p1 - 0.125*ds*t1.
	_t.expect_vector(pose.origin, Vector3(6.25, 0.0, 1.25),
		"distance sampling follows the accepted endpoint tangents instead of the chord", POSITION_EPS)


func _test_rendered_tangent_is_position_derivative() -> void:
	var route := _curved_route()
	var distance_m := 5.0
	var half_width_m := 0.001
	var before := Sampling.pose_at_distance(route, distance_m - half_width_m)
	var center := Sampling.pose_at_distance(route, distance_m)
	var after := Sampling.pose_at_distance(route, distance_m + half_width_m)
	var position_derivative := (after.origin - before.origin) / (2.0 * half_width_m)
	var rendered_tangent := -center.basis.z
	_t.expect(position_derivative.length_squared() > 0.0,
		"sampled path has a non-degenerate distance derivative")
	if position_derivative.length_squared() > 0.0:
		_t.expect_vector(position_derivative.normalized(), rendered_tangent.normalized(),
			"rendered tangent is the derivative of rendered position", DIRECTION_EPS)
	_t.expect_close(center.basis.x.length(), 1.0, "sampled right axis is unit", POSITION_EPS)
	_t.expect_close(center.basis.y.length(), 1.0, "sampled up axis is unit", POSITION_EPS)
	_t.expect_close(center.basis.z.length(), 1.0, "sampled tangent axis is unit", POSITION_EPS)
	_t.expect_close(absf(center.basis.x.dot(center.basis.y)), 0.0,
		"sampled right and up axes are orthogonal", POSITION_EPS)
	_t.expect_close(absf(center.basis.y.dot(center.basis.z)), 0.0,
		"sampled up and tangent axes are orthogonal", POSITION_EPS)


func _test_distance_wrap_is_deterministic() -> void:
	var route := _curved_route()
	var first := Sampling.pose_at_distance(route, 2.75)
	var wrapped := Sampling.pose_at_distance(route, 12.75)
	_t.expect_vector(wrapped.origin, first.origin, "distance sampling wraps position exactly", POSITION_EPS)
	_t.expect_vector(wrapped.basis.x, first.basis.x, "distance sampling wraps right exactly", POSITION_EPS)
	_t.expect_vector(wrapped.basis.y, first.basis.y, "distance sampling wraps up exactly", POSITION_EPS)
	_t.expect_vector(wrapped.basis.z, first.basis.z, "distance sampling wraps tangent exactly", POSITION_EPS)


func _curved_route() -> Dictionary:
	var tangent_0 := Vector3.RIGHT
	var tangent_1 := Vector3.FORWARD
	var up_0 := Vector3.UP
	var up_1 := Vector3.UP
	return {
		"length": 10.0,
		"duration": 1.0,
		"times": PackedFloat32Array([0.0, 1.0]),
		"distances": PackedFloat32Array([0.0, 10.0]),
		"positions": PackedVector3Array([Vector3.ZERO, Vector3(10.0, 0.0, 0.0)]),
		"tangents": PackedVector3Array([tangent_0, tangent_1]),
		"ups": PackedVector3Array([up_0, up_1]),
		"rights": PackedVector3Array([
			tangent_0.cross(up_0).normalized(),
			tangent_1.cross(up_1).normalized(),
		]),
	}
