class_name CanonicalData
extends RefCounted


static func _is_admissible(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for item in value:
				if not _is_admissible(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING or not _is_admissible(value[key]):
					return false
			return true
	return false


static func canonical_json(value: Variant) -> String:
	if not _is_admissible(value):
		return ""
	return JSON.stringify(value, "", true, true) + "\n"


static func sha256_text(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()
