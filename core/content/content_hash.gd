class_name ContentHash
extends RefCounted
## A 64-bit hash of a resource's content (ARCHITECTURE §3.3): every stored property of the resource
## and of every resource it holds, sub-resources and loaded files alike, in a canonical text
## hashed with FNV-1a. A script counts by its path, not its code. The command log records the
## game mode's hash; a replay refuses a mode whose hash differs, so an edit in `content/` (the
## knife's damage, say) cannot make a replay silently diverge.

## Properties that name where a resource came from, not what it holds.
const _SKIPPED := ["resource_path", "resource_scene_unique_id"]


static func of(resource: Resource) -> int:
	var parts := PackedStringArray()
	var seen: Dictionary[Resource, int] = {}
	_write(resource, parts, seen)
	return RngStreams.fnv1a64("\n".join(parts))


## The canonical text of `resource`, one line per value (for tests and debugging).
static func text_of(resource: Resource) -> String:
	var parts := PackedStringArray()
	var seen: Dictionary[Resource, int] = {}
	_write(resource, parts, seen)
	return "\n".join(parts)


static func _write(
	value: Variant, parts: PackedStringArray, seen: Dictionary[Resource, int]
) -> void:
	if value is Script:
		var script: Script = value
		parts.append("script %s" % script.resource_path)
	elif value is Resource:
		var resource: Resource = value
		if seen.has(resource):
			parts.append("ref %d" % seen[resource])
			return
		seen[resource] = seen.size()
		parts.append("resource %s {" % resource.get_class())
		for property: Dictionary in resource.get_property_list():
			var name: String = property["name"]
			var usage: int = property["usage"]
			if usage & PROPERTY_USAGE_STORAGE == 0 or _SKIPPED.has(name):
				continue
			parts.append("%s =" % name)
			_write(resource.get(name), parts, seen)
		parts.append("}")
	elif value is Object:
		parts.append("object" if value != null else "null")
	elif value is Array:
		var items: Array = value
		parts.append("array %d [" % items.size())
		for item: Variant in items:
			_write(item, parts, seen)
		parts.append("]")
	elif value is Dictionary:
		var table: Dictionary = value
		var keys := table.keys()
		keys.sort_custom(func(a: Variant, b: Variant) -> bool: return var_to_str(a) < var_to_str(b))
		parts.append("dictionary %d {" % keys.size())
		for key: Variant in keys:
			parts.append("key %s" % var_to_str(key))
			_write(table[key], parts, seen)
		parts.append("}")
	else:
		parts.append(var_to_str(value))
