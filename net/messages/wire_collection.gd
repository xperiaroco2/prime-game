class_name WireCollection
extends RefCounted
## WireField's counted types (ARCHITECTURE §4.3): the write and the read of a LIST, a MAP (keys
## strictly ascending) and a SETTING. A part of WireField split out of wire_field.gd (#1279): each
## function takes the field and calls its entries' own _write_value and _read_value, so the checks
## and error texts are WireField's.


static func write_list(field: WireField, value: Variant, writer: WireWriter) -> String:
	if not is_list(value):
		return field._wrong(value)
	var entries := entries_of(value)
	if entries.size() > field.max_count:
		return "%s: %d entries, at most %d" % [field.name, entries.size(), field.max_count]
	writer.u8(entries.size())
	for entry: Variant in entries:
		var problem := field.element._write_value(entry, writer)
		if not problem.is_empty():
			return "%s: %s" % [field.name, problem]
	return ""


static func write_map(field: WireField, value: Variant, writer: WireWriter) -> String:
	if not value is Dictionary:
		return field._wrong(value)
	var entries: Dictionary = value
	if entries.size() > field.max_count:
		return "%s: %d entries, at most %d" % [field.name, entries.size(), field.max_count]
	# Each key is checked and written once, into `keyed`; its bytes are copied in key order.
	var keyed := WireWriter.new()
	var spans := {}
	for entry_key: Variant in entries:
		var at := keyed.bytes.size()
		var problem := field.key._write_value(entry_key, keyed)
		if not problem.is_empty():
			return "%s: key %s" % [field.name, problem]
		spans[entry_key] = Vector2i(at, keyed.bytes.size())
	var ordered := entries.keys()
	if field.key.type == WireField.Type.ID:
		ordered.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	else:
		ordered.sort()
	writer.u8(ordered.size())
	for entry_key: Variant in ordered:
		var span: Vector2i = spans[entry_key]
		writer.raw(keyed.bytes.slice(span.x, span.y))
		var problem := field.element._write_value(entries[entry_key], writer)
		if not problem.is_empty():
			return "%s: %s" % [field.name, problem]
	return ""


static func write_setting(field: WireField, value: Variant, writer: WireWriter) -> String:
	if value is int:
		writer.u8(0)
		return WireField.of(field.name, WireField.Type.S32)._write_value(value, writer)
	if not is_list(value):
		return field._wrong(value)
	var entries := entries_of(value)
	if entries.size() > field.max_count:
		return "%s: %d ids, at most %d" % [field.name, entries.size(), field.max_count]
	writer.u8(1)
	writer.u8(entries.size())
	for entry: Variant in entries:
		var problem := WireField.id(field.name)._write_value(entry, writer)
		if not problem.is_empty():
			return problem
	return ""


static func read_list(field: WireField, reader: WireReader) -> Variant:
	var count := reader.u8()
	if count > field.max_count:
		reader.fail("%s: %d entries, at most %d" % [field.name, count, field.max_count])
		return null
	var ints := PackedInt32Array()
	var texts := PackedStringArray()
	var entries: Array = []
	if field.element.decoded_type() == TYPE_DICTIONARY:
		entries = Array([], TYPE_DICTIONARY, &"", null)
	for _entry: int in count:
		var value: Variant = field.element._read_value(reader)
		if reader.failed:
			return null
		match field.list_type:
			TYPE_PACKED_INT32_ARRAY:
				ints.append(value as int)
			TYPE_PACKED_STRING_ARRAY:
				texts.append(str(value))
			_:
				entries.append(value)
	match field.list_type:
		TYPE_PACKED_INT32_ARRAY:
			return ints
		TYPE_PACKED_STRING_ARRAY:
			return texts
	return entries


static func read_map(field: WireField, reader: WireReader) -> Variant:
	var count := reader.u8()
	if count > field.max_count:
		reader.fail("%s: %d entries, at most %d" % [field.name, count, field.max_count])
		return null
	var key := field.key
	var element := field.element
	var entries := {}
	if field.typed:
		entries = Dictionary({}, key.decoded_type(), &"", null, element.decoded_type(), &"", null)
	var previous: Variant = null
	for _entry: int in count:
		var entry_key: Variant = key._read_value(reader)
		if reader.failed:
			return null
		if previous != null and not _ascending(key, previous, entry_key):
			reader.fail("%s: keys out of order" % field.name)
			return null
		previous = entry_key
		var value: Variant = element._read_value(reader)
		if reader.failed:
			return null
		entries[entry_key] = value
	return entries


static func read_setting(field: WireField, reader: WireReader) -> Variant:
	var tag := reader.u8()
	if tag == 0:
		return reader.s32()
	if tag != 1:
		reader.fail("%s: a setting tagged %d" % [field.name, tag])
		return null
	var count := reader.u8()
	if count > field.max_count:
		reader.fail("%s: %d ids, at most %d" % [field.name, count, field.max_count])
		return null
	var ids := PackedStringArray()
	var entry := WireField.id(field.name)
	for _id: int in count:
		var value: Variant = entry._read_value(reader)
		if reader.failed:
			return null
		ids.append(str(value))
	return ids


static func is_list(value: Variant) -> bool:
	return (
		typeof(value)
		in [TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY]
	)


## An Array or a packed array (is_list) as one Array.
static func entries_of(value: Variant) -> Array:
	match typeof(value):
		TYPE_PACKED_INT32_ARRAY:
			var ints: PackedInt32Array = value
			return Array(ints)
		TYPE_PACKED_INT64_ARRAY:
			var longs: PackedInt64Array = value
			return Array(longs)
		TYPE_PACKED_STRING_ARRAY:
			var texts: PackedStringArray = value
			return Array(texts)
	return value


## Whether map key `next` comes after `previous`: an ID by its bytes, a PEER by number.
static func _ascending(key: WireField, previous: Variant, next: Variant) -> bool:
	if key.type == WireField.Type.ID:
		return str(previous) < str(next)
	return (previous as int) < (next as int)
