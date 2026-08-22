extends RefCounted
class_name TestUtil

## Shared assertion/reporting harness for the focused-test suites: one `_t := TestUtil.new()`
## per suite replaces each file's local `_errors` array and `_expect*` helpers.

var errors := PackedStringArray()


func expect(condition: bool, message: String) -> bool:
	if not condition:
		errors.append(message)
	return condition


func expect_close(actual: float, expected: float, message: String, tolerance: float = 0.000001) -> bool:
	return expect(absf(actual - expected) <= tolerance,
		"%s: expected %.9f, got %.9f" % [message, expected, actual])


func expect_vector(actual: Vector3, expected: Vector3, message: String, tolerance: float = 0.000001) -> bool:
	return expect(actual.distance_to(expected) <= tolerance,
		"%s: expected %s, got %s" % [message, expected, actual])


func expect_range(value: float, low: float, high: float, message: String) -> bool:
	return expect(value >= low and value <= high,
		"%s: expected within [%.9f, %.9f], got %.9f" % [message, low, high, value])


func expect_min(value: float, minimum: float, message: String) -> bool:
	return expect(value >= minimum, "%s: expected >= %.9f, got %.9f" % [message, minimum, value])


func expect_max(value: float, maximum: float, message: String) -> bool:
	return expect(value <= maximum, "%s: expected <= %.9f, got %.9f" % [message, maximum, value])


func contains(list: Variant, item: Variant) -> bool:
	for value in list:
		if str(value).contains(str(item)):
			return true
	return false


func finish(tree: SceneTree) -> void:
	for error in errors:
		printerr(error)
	tree.quit(0 if errors.is_empty() else 1)
