extends RefCounted
## Unknown property keys in a hand-written content .tres (#1238).
##
## Godot loads `negate_ = true` or `hit_stops_ = false` without an error: it ignores the key
## and keeps the property's default. A rule setting whose default is legal (a negate, a display
## flag) then slips through the load check and ModeCheck alike. This compares every
## `key = value` line of each [resource] and [sub_resource] section with the stored properties
## (PROPERTY_USAGE_STORAGE) of a fresh object of that section's type and script, and returns one
## `<path>:<line>: ...` problem per key that is none of them. A section whose type or script
## does not load is left to the load check. check_project.gd runs it over the .tres files under
## ROOTS; tests/unit/tools/content_keys_test.gd covers it.

## The folders whose .tres files check_project.gd compares: the content (rules as data, often
## written by hand).
const ROOTS: PackedStringArray = ["res://content/"]

const _HEADER := "^\\s*\\[(\\w+)(.*)\\]\\s*(;.*)?$"
const _ATTRIBUTE := '(\\w+)="([^"]*)"'
const _KEY := '^\\s*(?:([A-Za-z_][A-Za-z0-9_/:.-]*)|"([^"]*)")\\s*='
const _EXT_RESOURCE := '^\\s*ExtResource\\(\\s*"([^"]+)"\\s*\\)'

## Stored property names (a set) per "<type> <script path>": each class is made once.
var _stored: Dictionary[String, Dictionary] = {}
var _header_re: RegEx = RegEx.create_from_string(_HEADER)
var _attribute_re: RegEx = RegEx.create_from_string(_ATTRIBUTE)
var _key_re: RegEx = RegEx.create_from_string(_KEY)
var _ext_re: RegEx = RegEx.create_from_string(_EXT_RESOURCE)


## One [resource] or [sub_resource] section: its header, type, script id and property lines.
class Section:
	extends RefCounted
	var label: String
	var type: String
	var script_id: String = ""
	var keys: PackedStringArray = []
	var lines: PackedInt32Array = []

	func _init(section_label: String, section_type: String) -> void:
		label = section_label
		type = section_type


## True for a .tres file under ROOTS.
static func applies_to(path: String) -> bool:
	if path.get_extension() != "tres":
		return false
	for root: String in ROOTS:
		if path.begins_with(root):
			return true
	return false


## The unknown keys of the .tres file at `path`, one `<path>:<line>: ...` line each.
func unknown_keys(path: String) -> PackedStringArray:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return []  # an unreadable file is the load check's error
	return unknown_keys_in(path, text)


## The unknown keys of `text`, a .tres file's content, reported against `path`.
func unknown_keys_in(path: String, text: String) -> PackedStringArray:
	var ext_paths: Dictionary[String, String] = {}
	var sections: Array[Section] = _sections(text, ext_paths)
	var problems: PackedStringArray = []
	for section: Section in sections:
		var script: Script = null
		if not section.script_id.is_empty():
			var script_path: String = _attribute(ext_paths, section.script_id)
			if script_path.is_empty() or not ResourceLoader.exists(script_path):
				continue
			script = load(script_path) as Script
			if script == null or not script.can_instantiate():
				continue
		var stored: Dictionary = _stored_names(section.type, script)
		if stored.is_empty():
			continue
		var owner: String = _class_label(section.type, script)
		for i: int in section.keys.size():
			var key: String = section.keys[i]
			if key == "script" or key.begins_with("metadata/") or stored.has(key):
				continue
			problems.append(
				(
					(
						'%s:%d: unknown property "%s" in %s (%s): Godot loads the file without an'
						+ " error, ignores the line and keeps the default; correct or delete it"
					)
					% [path, section.lines[i], key, section.label, owner]
				)
			)
	return problems


## The [resource] and [sub_resource] sections of `text`, with each line's property key; fills
## `ext_paths` (id -> path). A line counts only outside a string and outside brackets, so a
## multi-line string or dictionary value never reads as a key or a header. Like Godot's parser it
## skips leading whitespace, accepts a quoted key and ignores a `;` comment.
func _sections(text: String, ext_paths: Dictionary[String, String]) -> Array[Section]:
	var sections: Array[Section] = []
	var main_type: String = ""
	var current: Section = null
	var depth: int = 0
	var in_string: bool = false
	var escaped: bool = false
	var number: int = 0
	for line: String in text.split("\n"):
		number += 1
		if depth == 0 and not in_string:
			var header: RegExMatch = _header_re.search(line)
			if header != null:
				var tag: String = header.get_string(1)
				var attributes: Dictionary[String, String] = _attributes(header.get_string(2))
				current = null
				if tag == "gd_resource":
					main_type = _attribute(attributes, "type")
				elif tag == "ext_resource":
					ext_paths[_attribute(attributes, "id")] = _attribute(attributes, "path")
				elif tag == "sub_resource":
					current = Section.new(
						'[sub_resource id="%s"]' % _attribute(attributes, "id"),
						_attribute(attributes, "type")
					)
					sections.append(current)
				elif tag == "resource":
					current = Section.new("[resource]", main_type)
					sections.append(current)
			elif current != null:
				var key: RegExMatch = _key_re.search(line)
				if key != null:
					var name: String = key.get_string(1)
					if name.is_empty():
						name = key.get_string(2)  # a quoted key
					current.keys.append(name)
					current.lines.append(number)
					if name == "script":
						var ext: RegExMatch = _ext_re.search(line.substr(key.get_end()))
						if ext != null:
							current.script_id = ext.get_string(1)
		for character: String in line:
			if in_string:
				if escaped:
					escaped = false
				elif character == "\\":
					escaped = true
				elif character == '"':
					in_string = false
			elif character == '"':
				in_string = true
			elif character == ";":
				break  # a comment to the end of the line, as in Godot's own parser
			elif character in "[{(":
				depth += 1
			elif character in "]})":
				depth -= 1
	return sections


func _attribute(attributes: Dictionary[String, String], name: String) -> String:
	return attributes[name] if attributes.has(name) else ""


func _attributes(text: String) -> Dictionary[String, String]:
	var attributes: Dictionary[String, String] = {}
	for found: RegExMatch in _attribute_re.search_all(text):
		attributes[found.get_string(1)] = found.get_string(2)
	return attributes


## The stored property names (a set) of a fresh `type` object with `script`; empty when the
## type cannot be made.
func _stored_names(type: String, script: Script) -> Dictionary:
	var cache_key: String = "%s %s" % [type, script.resource_path if script != null else ""]
	if _stored.has(cache_key):
		return _stored[cache_key]
	var names: Dictionary = {}
	if ClassDB.class_exists(type) and ClassDB.can_instantiate(type):
		if script == null or ClassDB.is_parent_class(type, script.get_instance_base_type()):
			var object: Object = ClassDB.instantiate(type)
			if script != null:
				object.set_script(script)
			for property: Dictionary in object.get_property_list():
				if (property["usage"] as int) & PROPERTY_USAGE_STORAGE:
					names[property["name"] as String] = true
			if not object is RefCounted:
				object.free()
	_stored[cache_key] = names
	return names


func _class_label(type: String, script: Script) -> String:
	if script == null:
		return type
	var global_name: StringName = script.get_global_name()
	return String(global_name) if not global_name.is_empty() else script.resource_path
