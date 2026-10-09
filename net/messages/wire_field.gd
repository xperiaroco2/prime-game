class_name WireField
extends RefCounted
## One field of a wire row (ARCHITECTURE §4.3): its name, which is core/'s (a MatchCommand arg or
## a key of an event's to_dict(), written as a string: net/ references no core/ class), its wire
## type, and the Variant it decodes to. write() checks a value by the decoder's rules before it
## writes it, so the encoder refuses whatever the decoder would reject; read() rejects at the
## first problem through its WireReader.

enum Type {
	U8,
	U16,
	U32,
	S32,
	S64,
	BOOL,
	F32,
	VEC3,
	COLOUR,
	PEER,
	ITEM,
	STATION,
	TICK,
	ID,
	PATH,
	TEXT,
	NOTE,
	LIST,
	MAP,
	OPUS,
	## A u8 of named bools, the first name in bit 1; any other bit set is rejected.
	FLAGS,
	## Parts in order, as one Dictionary (a roster entry, an avatar).
	RECORD,
	## A bool flag (`has_map`), then the parts when it is true.
	OPTIONAL,
	## A setting of ChangeSettings: u8 0 then s32 (a whole number), or u8 1 then list<id>.
	SETTING,
	## An Opus frame anywhere in a payload: a u16 length, then that many bytes (the batched voice
	## row's frames, M5-4b); OPUS is the rest of the payload and only a row's last field.
	SIZED_OPUS,
	## A player's name (#550): a u8 length, then that many bytes of well-formed UTF-8, at most
	## NAME_MAX_BYTES, without the characters is_name_char refuses.
	NAME,
}

## Where a decoded field goes: the payload's Dictionary, or a WireMessage slot outside it (the
## intent's `seq`, ForceRole's `peer`: wire-only fields, §4.4).
enum Slot { FIELD, SEQ, PEER }

const ID_MAX := 32
const PATH_MAX := 255
const TEXT_MAX := 64
## A name's most bytes: core/'s 16 characters at 4 UTF-8 bytes each (PlayerNames.MAX_CHARS).
const NAME_MAX_BYTES := 64
const NOTE_MAX := 320
const PATH_PREFIX := "res://"
const PEER_MAX := 0x7FFFFFFF
const U16_MAX := 0xFFFF
const U32_MAX := 0xFFFFFFFF
const S32_MIN := -0x80000000
const S32_MAX := 0x7FFFFFFF
## Per UTF-8 continuation count: the lead byte's bits of the code point, and the smallest code
## point that needs that many bytes (anything smaller is an overlong form).
const UTF8_LEAD_BITS := [0x7F, 0x1F, 0x0F, 0x07]
const UTF8_SMALLEST := [0, 0x80, 0x800, 0x10000]
## How much of a refused value a refusal line shows.
const WRONG_VALUE_MAX := 64
## The integer types and their bounds; one above the top is none (-1) where a field is optional.
const INT_BOUNDS := {
	Type.U8: [0, 0xFF],
	Type.U16: [0, U16_MAX],
	Type.U32: [0, U32_MAX],
	Type.S32: [S32_MIN, S32_MAX],
	Type.S64: [-0x7FFFFFFFFFFFFFFF - 1, 0x7FFFFFFFFFFFFFFF],
	Type.PEER: [1, PEER_MAX],
	Type.ITEM: [0, U16_MAX - 1],
	Type.STATION: [0, U16_MAX - 1],
	Type.TICK: [0, U32_MAX - 1],
}
const NUMBERS := [
	Type.U8, Type.U16, Type.U32, Type.S32, Type.S64, Type.PEER, Type.ITEM, Type.STATION, Type.TICK
]
const TEXTS := [Type.ID, Type.PATH, Type.TEXT, Type.NOTE]
const CONTAINERS := [Type.LIST, Type.MAP, Type.SETTING, Type.RECORD]
const FIXED_SIZES := {
	Type.U8: 1,
	Type.BOOL: 1,
	Type.FLAGS: 1,
	Type.U16: 2,
	Type.ITEM: 2,
	Type.STATION: 2,
	Type.U32: 4,
	Type.S32: 4,
	Type.F32: 4,
	Type.PEER: 4,
	Type.TICK: 4,
	Type.S64: 8,
	Type.VEC3: 12,
	Type.COLOUR: 16,
	Type.ID: 1 + ID_MAX,
	Type.PATH: 1 + PATH_MAX,
	Type.TEXT: 1 + TEXT_MAX,
	Type.NOTE: 2 + NOTE_MAX,
	Type.NAME: 1 + NAME_MAX_BYTES,
}
const DECODED_TYPES := {
	Type.BOOL: TYPE_BOOL,
	Type.F32: TYPE_FLOAT,
	Type.VEC3: TYPE_VECTOR3,
	Type.COLOUR: TYPE_COLOR,
	Type.PATH: TYPE_STRING,
	Type.TEXT: TYPE_STRING,
	Type.NOTE: TYPE_STRING,
	Type.NAME: TYPE_STRING,
	Type.MAP: TYPE_DICTIONARY,
	Type.RECORD: TYPE_DICTIONARY,
	Type.OPUS: TYPE_PACKED_BYTE_ARRAY,
	Type.SIZED_OPUS: TYPE_PACKED_BYTE_ARRAY,
	Type.SETTING: TYPE_NIL,
	Type.FLAGS: TYPE_NIL,
	Type.OPTIONAL: TYPE_NIL,
}

var name: String
var type: Type
var slot := Slot.FIELD
## ITEM, STATION, TICK: -1 (none) is allowed, as all ones on the wire.
var optional := false
## LIST, MAP: the most entries; SETTING: the most ids in a set; OPUS, SIZED_OPUS: the most bytes.
var max_count := 0
## LIST: each entry; MAP: each value.
var element: WireField
## MAP: each key (ID, by bytes, or PEER, by number: strictly ascending).
var key: WireField
## RECORD, OPTIONAL: the fields inside, in order.
var parts: Array[WireField] = []
## FLAGS: the bools' names, bit 1 first.
var flags := PackedStringArray()
## OPTIONAL: what the payload holds when the flag is false; empty: the parts' keys are absent.
var absent: Dictionary = {}
## ID: decodes as a String instead of a StringName, where core/ reads a String.
var as_string := false
## LIST: TYPE_ARRAY (typed by its entries when they are Dictionaries), TYPE_PACKED_INT32_ARRAY
## or TYPE_PACKED_STRING_ARRAY.
var list_type: Variant.Type = TYPE_ARRAY
## MAP: a typed Dictionary of the decoded key and value types, or an untyped one.
var typed := true


static func of(field_name: String, field_type: Type) -> WireField:
	var field := WireField.new()
	field.name = field_name
	field.type = field_type
	return field


## An ITEM, STATION or TICK that may be none (-1).
static func maybe(field_name: String, field_type: Type) -> WireField:
	var field := of(field_name, field_type)
	field.optional = true
	return field


## A RELIABLE intent's sequence number, which a Rejected names: MatchCommand.seq, not an arg.
static func seq_number() -> WireField:
	var field := of("seq", Type.U32)
	field.slot = Slot.SEQ
	return field


## ForceRole's player, which becomes the command's peer, not an arg.
static func target_peer() -> WireField:
	var field := of("peer", Type.PEER)
	field.slot = Slot.PEER
	return field


static func id(field_name: String, decodes_as_string := false) -> WireField:
	var field := of(field_name, Type.ID)
	field.as_string = decodes_as_string
	return field


static func list(
	field_name: String, entry: WireField, most: int, decoded: Variant.Type = TYPE_ARRAY
) -> WireField:
	var field := of(field_name, Type.LIST)
	field.element = entry
	field.max_count = most
	field.list_type = decoded
	return field


static func map(
	field_name: String, keys_of: WireField, values: WireField, most: int, is_typed := true
) -> WireField:
	var field := of(field_name, Type.MAP)
	field.key = keys_of
	field.element = values
	field.max_count = most
	field.typed = is_typed
	return field


static func record(field_name: String, record_parts: Array[WireField]) -> WireField:
	var field := of(field_name, Type.RECORD)
	field.parts = record_parts
	return field


static func bits(names: PackedStringArray) -> WireField:
	var field := of("flags", Type.FLAGS)
	field.flags = names
	return field


## A presence flag named `flag_name` and the parts it guards. `when_absent`: the payload's values
## when the flag is false (ForceRole's empty role); empty, the parts' keys are left out.
static func when(
	flag_name: String, guarded: Array[WireField], when_absent: Dictionary = {}
) -> WireField:
	var field := of(flag_name, Type.OPTIONAL)
	field.parts = guarded
	field.absent = when_absent
	return field


static func setting(field_name: String, most_ids: int) -> WireField:
	var field := of(field_name, Type.SETTING)
	field.max_count = most_ids
	return field


static func opus(field_name: String, most: int) -> WireField:
	var field := of(field_name, Type.OPUS)
	field.max_count = most
	return field


## An Opus frame of 1 to `most` bytes behind its u16 length, where more follows it.
static func sized_opus(field_name: String, most: int) -> WireField:
	var field := of(field_name, Type.SIZED_OPUS)
	field.max_count = most
	return field


## Whether `text` is a wire id: 1 to 32 bytes of `a-z`, `0-9` and `_`.
static func is_id(text: String) -> bool:
	if text.length() < 1 or text.length() > ID_MAX:
		return false
	for i: int in text.length():
		if not _is_id_char(text.unicode_at(i)):
			return false
	return true


## Whether `text` is a wire path: `res://` and bytes of `A-Z a-z 0-9 _ - . /`, no `..`, at most
## 255 bytes.
static func is_path(text: String) -> bool:
	if text.length() > PATH_MAX or not text.begins_with(PATH_PREFIX) or text.contains(".."):
		return false
	for i: int in range(PATH_PREFIX.length(), text.length()):
		if not _is_path_char(text.unicode_at(i)):
			return false
	return true


## Whether `text` is printable ASCII (0x20 to 0x7E) of at most `most` bytes.
static func is_printable(text: String, most: int) -> bool:
	if text.length() > most:
		return false
	for i: int in text.length():
		if not _is_printable_char(text.unicode_at(i)):
			return false
	return true


## Whether `text` is a `name` on the wire (#550): at most NAME_MAX_BYTES bytes of UTF-8, every
## character one is_name_char allows. Empty is one (the host gives a fallback).
static func is_name(text: String) -> bool:
	for i: int in text.length():
		if not is_name_char(text.unicode_at(i)):
			return false
	return text.to_utf8_buffer().size() <= NAME_MAX_BYTES


## Whether a `name` may hold the character `code`: not a C0 control, DEL or a C1 control, not a
## surrogate, not U+FEFF (a UTF-8 decoder may drop it silently, so it would not decode back to the
## same bytes) and at most U+10FFFF. core/'s PlayerNames.is_dropped refuses exactly these (net/
## names no core/ class; a test pins the two), so every name the host makes encodes.
static func is_name_char(code: int) -> bool:
	return not (
		code < 0x20
		or (code >= 0x7F and code <= 0x9F)
		or (code >= 0xD800 and code <= 0xDFFF)
		or code == 0xFEFF
		or code > 0x10FFFF
	)


## Writes `fields` from `source`; the problem, or empty. Every key of `source` must be one the
## fields fill. `message` gives the SEQ and PEER slots (null inside a record).
static func write_all(
	fields: Array[WireField], source: Dictionary, writer: WireWriter, message: WireMessage
) -> String:
	var known := {}
	for field: WireField in fields:
		for filled: String in field.keys():
			known[filled] = true
		var problem := field._write_part(source, writer, message)
		if not problem.is_empty():
			return problem
	for given: Variant in source:
		if not (given is String or given is StringName) or not known.has(str(given)):
			return "an undeclared field %s" % str(given)
	return ""


## Reads `fields` into `into` (and the SEQ and PEER slots into `message`); stops at the first
## problem, which the reader then holds.
static func read_all(
	fields: Array[WireField], reader: WireReader, into: Dictionary, message: WireMessage
) -> void:
	for field: WireField in fields:
		field._read_part(reader, into, message)
		if reader.failed:
			return


## The payload keys this field fills, the flags and guarded parts included; none for a slot.
func keys() -> PackedStringArray:
	if slot != Slot.FIELD:
		return PackedStringArray()
	match type:
		Type.FLAGS:
			return flags
		Type.OPTIONAL:
			var found := PackedStringArray()
			for part: WireField in parts:
				found.append_array(part.keys())
			return found
	return PackedStringArray([name])


## The bytes this field takes whatever its value (a number, a bool, a float, a vector, a colour or
## a set of flags); -1 when its size depends on its value.
func fixed_size() -> int:
	if type in NUMBERS or type in [Type.BOOL, Type.F32, Type.VEC3, Type.COLOUR, Type.FLAGS]:
		return FIXED_SIZES[type]
	return -1


## RECORD: where the part named `part_name` starts in every encoding of this record (as
## WireRow.fixed_offset does for a row's fields); -1 otherwise.
func fixed_offset(part_name: String) -> int:
	if type != Type.RECORD:
		return -1
	return WireRow.offset_among(parts, part_name)


## The most bytes this field can take at the wire's maxima.
func max_size() -> int:
	if FIXED_SIZES.has(type):
		return FIXED_SIZES[type]
	match type:
		Type.LIST:
			return 1 + max_count * element.max_size()
		Type.MAP:
			return 1 + max_count * (key.max_size() + element.max_size())
		Type.SETTING:
			return 1 + maxi(4, 1 + max_count * (1 + ID_MAX))
		Type.OPUS, Type.SIZED_OPUS:
			# SIZED_OPUS adds its u16 length (one arm: gdlint's max-returns).
			return max_count + (2 if type == Type.SIZED_OPUS else 0)
	var total := 1 if type == Type.OPTIONAL else 0
	for part: WireField in parts:
		total += part.max_size()
	return total


## The Variant type this field decodes to; TYPE_NIL where it varies (a SETTING).
func decoded_type() -> Variant.Type:
	if type == Type.ID:
		return TYPE_STRING if as_string else TYPE_STRING_NAME
	if type == Type.LIST:
		return list_type
	var found: Variant.Type = DECODED_TYPES.get(type, TYPE_INT)
	return found


func _write_part(source: Dictionary, writer: WireWriter, message: WireMessage) -> String:
	if slot == Slot.SEQ:
		return _write_value(message.seq, writer)
	if slot == Slot.PEER:
		return _write_value(message.peer, writer)
	if type == Type.FLAGS:
		return _write_flags(source, writer)
	if type == Type.OPTIONAL:
		return _write_optional(source, writer, message)
	if not source.has(name):
		return "a missing field %s" % name
	return _write_value(source[name], writer)


func _write_flags(source: Dictionary, writer: WireWriter) -> String:
	var value := 0
	for bit: int in flags.size():
		var flag: Variant = source.get(flags[bit])
		if not flag is bool:
			return "flag %s is not a bool" % flags[bit]
		if flag:
			value |= 1 << bit
	writer.u8(value)
	return ""


func _write_optional(source: Dictionary, writer: WireWriter, message: WireMessage) -> String:
	var guarded := keys()
	var present := false
	if absent.is_empty():
		var found := 0
		for guarded_key: String in guarded:
			if source.has(guarded_key):
				found += 1
		if found != 0 and found != guarded.size():
			return "%s: only some of its fields are given" % name
		present = found > 0
	else:
		for guarded_key: String in guarded:
			if not source.has(guarded_key):
				return "a missing field %s" % guarded_key
			if not _same(source[guarded_key], absent.get(guarded_key)):
				present = true
	writer.u8(1 if present else 0)
	if not present:
		return ""
	for part: WireField in parts:
		var problem := part._write_part(source, writer, message)
		if not problem.is_empty():
			return problem
	return ""


func _write_value(value: Variant, writer: WireWriter) -> String:
	if type in NUMBERS:
		return _write_number(value, writer)
	if type in TEXTS:
		return _write_string(value, writer)
	if type == Type.NAME:
		return _write_name(value, writer)
	if type in CONTAINERS:
		return _write_container(value, writer)
	if not _is_plain(value):
		return _wrong(value)
	match type:
		Type.BOOL:
			writer.u8(1 if value else 0)
		Type.F32:
			writer.f32(value as float)
		Type.OPUS:
			writer.raw(value as PackedByteArray)
		Type.SIZED_OPUS:
			writer.u16((value as PackedByteArray).size())
			writer.raw(value as PackedByteArray)
		Type.VEC3:
			var vector: Vector3 = value
			for axis: int in 3:
				writer.f32(vector[axis])
		Type.COLOUR:
			var colour: Color = value
			for channel: float in [colour.r, colour.g, colour.b, colour.a]:
				writer.f32(channel)
	return ""


## BOOL, F32, VEC3, COLOUR, OPUS and SIZED_OPUS: whether the decoder would take the value.
func _is_plain(value: Variant) -> bool:
	match type:
		Type.BOOL:
			return value is bool
		Type.F32:
			return value is float and is_finite(value as float) and _as_f32(value as float) == value
		Type.VEC3:
			return value is Vector3 and (value as Vector3).is_finite()
		Type.COLOUR:
			return value is Color and _is_finite_colour(value as Color)
	return value is PackedByteArray and _is_opus_size((value as PackedByteArray).size())


## Every integer type; -1 is none (all ones on the wire) where the field is optional.
func _write_number(value: Variant, writer: WireWriter) -> String:
	if not value is int:
		return _wrong(value)
	var number: int = value
	var bounds: Array = INT_BOUNDS[type]
	if number == -1 and optional:
		number = bounds[1] + 1
	elif number < bounds[0] or number > bounds[1]:
		return _wrong(value)
	match type:
		Type.U8:
			writer.u8(number)
		Type.U16, Type.ITEM, Type.STATION:
			writer.u16(number)
		Type.U32, Type.PEER, Type.TICK:
			writer.u32(number)
		Type.S32:
			writer.s32(number)
		_:
			writer.s64(number)
	return ""


func _write_container(value: Variant, writer: WireWriter) -> String:
	match type:
		Type.LIST:
			return _write_list(value, writer)
		Type.MAP:
			return _write_map(value, writer)
		Type.SETTING:
			return _write_setting(value, writer)
	if not value is Dictionary:
		return _wrong(value)
	var fields: Dictionary = value
	return write_all(parts, fields, writer, null)


func _write_string(value: Variant, writer: WireWriter) -> String:
	if not (value is String or value is StringName):
		return _wrong(value)
	var text := str(value)
	var valid := false
	match type:
		Type.ID:
			valid = is_id(text)
		Type.PATH:
			valid = is_path(text)
		Type.TEXT:
			valid = is_printable(text, TEXT_MAX)
		Type.NOTE:
			valid = is_printable(text, NOTE_MAX)
	if not valid:
		return _wrong(value)
	if type == Type.NOTE:
		writer.u16(text.length())
	else:
		writer.u8(text.length())
	writer.raw(text.to_ascii_buffer())
	return ""


func _write_name(value: Variant, writer: WireWriter) -> String:
	if not (value is String or value is StringName) or not is_name(str(value)):
		return _wrong(value)
	var bytes := str(value).to_utf8_buffer()
	writer.u8(bytes.size())
	writer.raw(bytes)
	return ""


func _write_list(value: Variant, writer: WireWriter) -> String:
	if not _is_list(value):
		return _wrong(value)
	var entries := _entries_of(value)
	if entries.size() > max_count:
		return "%s: %d entries, at most %d" % [name, entries.size(), max_count]
	writer.u8(entries.size())
	for entry: Variant in entries:
		var problem := element._write_value(entry, writer)
		if not problem.is_empty():
			return "%s: %s" % [name, problem]
	return ""


func _write_map(value: Variant, writer: WireWriter) -> String:
	if not value is Dictionary:
		return _wrong(value)
	var entries: Dictionary = value
	if entries.size() > max_count:
		return "%s: %d entries, at most %d" % [name, entries.size(), max_count]
	var ordered: Array = []
	for entry_key: Variant in entries:
		var problem := key._write_value(entry_key, WireWriter.new())
		if not problem.is_empty():
			return "%s: key %s" % [name, problem]
		ordered.append(entry_key)
	if key.type == Type.ID:
		ordered.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	else:
		ordered.sort()
	writer.u8(ordered.size())
	for entry_key: Variant in ordered:
		key._write_value(entry_key, writer)
		var problem := element._write_value(entries[entry_key], writer)
		if not problem.is_empty():
			return "%s: %s" % [name, problem]
	return ""


func _write_setting(value: Variant, writer: WireWriter) -> String:
	if value is int:
		writer.u8(0)
		return _as_s32()._write_value(value, writer)
	if not _is_list(value):
		return _wrong(value)
	var entries := _entries_of(value)
	if entries.size() > max_count:
		return "%s: %d ids, at most %d" % [name, entries.size(), max_count]
	writer.u8(1)
	writer.u8(entries.size())
	for entry: Variant in entries:
		var problem := WireField.id(name)._write_value(entry, writer)
		if not problem.is_empty():
			return problem
	return ""


func _read_part(reader: WireReader, into: Dictionary, message: WireMessage) -> void:
	if slot == Slot.SEQ:
		message.seq = reader.u32()
	elif slot == Slot.PEER:
		message.peer = _read_value(reader)
	elif type == Type.FLAGS:
		var value := reader.u8()
		if value >> flags.size() != 0:
			reader.fail("%s: unknown flag bits" % name)
			return
		for bit: int in flags.size():
			into[flags[bit]] = (value & (1 << bit)) != 0
	elif type == Type.OPTIONAL:
		var present := reader.u8()
		if present > 1:
			reader.fail("%s: not a bool" % name)
		elif present == 1:
			read_all(parts, reader, into, message)
		else:
			into.merge(absent.duplicate(true))
	else:
		var value: Variant = _read_value(reader)
		if not reader.failed:
			into[name] = value


func _read_value(reader: WireReader) -> Variant:
	if type in NUMBERS:
		return _read_number(reader)
	if type in TEXTS:
		return _read_string(reader)
	if type == Type.NAME:
		return _read_name(reader)
	if type in CONTAINERS:
		return _read_container(reader)
	if type == Type.SIZED_OPUS:
		return _read_sized_opus(reader)
	return _read_plain(reader)


func _read_number(reader: WireReader) -> int:
	var value := 0
	match type:
		Type.U8:
			value = reader.u8()
		Type.U16, Type.ITEM, Type.STATION:
			value = reader.u16()
		Type.U32, Type.PEER, Type.TICK:
			value = reader.u32()
		Type.S32:
			value = reader.s32()
		_:
			value = reader.s64()
	var bounds: Array = INT_BOUNDS[type]
	if optional and value == bounds[1] + 1:
		return -1
	if value < bounds[0] or value > bounds[1]:
		reader.fail("%s: %d is not %s" % [name, value, _a_type_name()])
	return value


func _read_plain(reader: WireReader) -> Variant:
	match type:
		Type.BOOL:
			var value := reader.u8()
			if value > 1:
				reader.fail("%s: not a bool" % name)
			return value == 1
		Type.F32:
			return reader.f32()
		Type.VEC3:
			return Vector3(reader.f32(), reader.f32(), reader.f32())
		Type.COLOUR:
			return Color(reader.f32(), reader.f32(), reader.f32(), reader.f32())
	if not _is_opus_size(reader.left()):
		reader.fail("%s: an Opus frame of %d bytes" % [name, reader.left()])
		return PackedByteArray()
	return reader.rest()


## A u16 length of 1 to max_count, then that many bytes.
func _read_sized_opus(reader: WireReader) -> PackedByteArray:
	var size := reader.u16()
	if not reader.failed and not _is_opus_size(size):
		reader.fail("%s: an Opus frame of %d bytes" % [name, size])
	if reader.failed:
		return PackedByteArray()
	return reader.raw(size)


func _read_container(reader: WireReader) -> Variant:
	match type:
		Type.LIST:
			return _read_list(reader)
		Type.MAP:
			return _read_map(reader)
		Type.SETTING:
			return _read_setting(reader)
	var fields := {}
	read_all(parts, reader, fields, null)
	return fields


func _read_string(reader: WireReader) -> Variant:
	var length := reader.u16() if type == Type.NOTE else reader.u8()
	var most: int = {Type.ID: ID_MAX, Type.PATH: PATH_MAX, Type.TEXT: TEXT_MAX}.get(type, NOTE_MAX)
	if length > most or (type == Type.ID and length < 1):
		reader.fail("%s: a length of %d" % [name, length])
	var raw := reader.raw(length)
	if reader.failed:
		return ""
	for byte: int in raw:
		if not _is_printable_char(byte):
			reader.fail("%s: a byte %d" % [name, byte])
			return ""
	var text := raw.get_string_from_ascii()
	match type:
		Type.ID:
			if not is_id(text):
				reader.fail("%s: not an id" % name)
			elif not as_string:
				return StringName(text)
		Type.PATH:
			if not is_path(text):
				reader.fail("%s: not a path" % name)
	return text


## A `name` (#550): its bytes are checked as UTF-8 by hand before any decode, since
## get_string_from_utf8 prints an engine error on malformed bytes (a peer could repeat it at will)
## and drops a byte-order mark; then the text must encode back to the same bytes.
func _read_name(reader: WireReader) -> String:
	var length := reader.u8()
	if length > NAME_MAX_BYTES:
		reader.fail("%s: a length of %d" % [name, length])
	var raw := reader.raw(length)
	if reader.failed:
		return ""
	var at := _utf8_problem(raw)
	if at >= 0:
		reader.fail("%s: not UTF-8 at byte %d" % [name, at])
		return ""
	var text := raw.get_string_from_utf8()
	if not is_name(text) or text.to_utf8_buffer() != raw:
		reader.fail("%s: not a name" % name)
		return ""
	return text


func _read_list(reader: WireReader) -> Variant:
	var count := reader.u8()
	if count > max_count:
		reader.fail("%s: %d entries, at most %d" % [name, count, max_count])
		return null
	var ints := PackedInt32Array()
	var texts := PackedStringArray()
	var entries: Array = []
	if element.decoded_type() == TYPE_DICTIONARY:
		entries = Array([], TYPE_DICTIONARY, &"", null)
	for _entry: int in count:
		var value: Variant = element._read_value(reader)
		if reader.failed:
			return null
		match list_type:
			TYPE_PACKED_INT32_ARRAY:
				ints.append(value as int)
			TYPE_PACKED_STRING_ARRAY:
				texts.append(str(value))
			_:
				entries.append(value)
	match list_type:
		TYPE_PACKED_INT32_ARRAY:
			return ints
		TYPE_PACKED_STRING_ARRAY:
			return texts
	return entries


func _read_map(reader: WireReader) -> Variant:
	var count := reader.u8()
	if count > max_count:
		reader.fail("%s: %d entries, at most %d" % [name, count, max_count])
		return null
	var entries := {}
	if typed:
		entries = Dictionary({}, key.decoded_type(), &"", null, element.decoded_type(), &"", null)
	var previous: Variant = null
	for _entry: int in count:
		var entry_key: Variant = key._read_value(reader)
		if reader.failed:
			return null
		if previous != null and not _ascending(previous, entry_key):
			reader.fail("%s: keys out of order" % name)
			return null
		previous = entry_key
		var value: Variant = element._read_value(reader)
		if reader.failed:
			return null
		entries[entry_key] = value
	return entries


func _read_setting(reader: WireReader) -> Variant:
	var tag := reader.u8()
	if tag == 0:
		return reader.s32()
	if tag != 1:
		reader.fail("%s: a setting tagged %d" % [name, tag])
		return null
	var count := reader.u8()
	if count > max_count:
		reader.fail("%s: %d ids, at most %d" % [name, count, max_count])
		return null
	var ids := PackedStringArray()
	var entry := WireField.id(name)
	for _id: int in count:
		var value: Variant = entry._read_value(reader)
		if reader.failed:
			return null
		ids.append(str(value))
	return ids


func _ascending(previous: Variant, next: Variant) -> bool:
	if key.type == Type.ID:
		return str(previous) < str(next)
	return (previous as int) < (next as int)


func _as_s32() -> WireField:
	return WireField.of(name, Type.S32)


## Why `value` was refused, in one short line: a voice bug at 50 frames a second must not flood the
## log with byte dumps, so a byte array is its size and anything else is cut.
func _wrong(value: Variant) -> String:
	var shown: String
	if value is PackedByteArray:
		shown = "%d bytes" % (value as PackedByteArray).size()
	else:
		shown = var_to_str(value)
		if shown.length() > WRONG_VALUE_MAX:
			shown = shown.left(WRONG_VALUE_MAX) + "..."
	return "%s: %s is not %s" % [name, shown, _a_type_name()]


func _type_name() -> String:
	return str(Type.keys()[type]).to_lower()


## The type name with its article, as it is read aloud ("an s32", "a u16").
func _a_type_name() -> String:
	var type_name := _type_name()
	var spoken_vowel := type_name[0] in ["a", "e", "i", "o"] or type_name in ["s32", "s64", "f32"]
	var article := "an" if spoken_vowel else "a"
	return "%s %s" % [article, type_name]


func _is_opus_size(size: int) -> bool:
	return size >= 1 and size <= max_count


static func _is_list(value: Variant) -> bool:
	return (
		typeof(value)
		in [TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY]
	)


## An Array or a packed array (_is_list) as one Array.
static func _entries_of(value: Variant) -> Array:
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


static func _is_finite_colour(colour: Color) -> bool:
	return (
		is_finite(colour.r) and is_finite(colour.g) and is_finite(colour.b) and is_finite(colour.a)
	)


static func _as_f32(value: float) -> float:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, value)
	return bytes.decode_float(0)


## Equal values of the same kind, a String and a StringName counting as one kind.
static func _same(a: Variant, b: Variant) -> bool:
	var a_text := a is String or a is StringName
	var b_text := b is String or b is StringName
	if a_text or b_text:
		return a_text and b_text and str(a) == str(b)
	return typeof(a) == typeof(b) and a == b


static func _is_id_char(c: int) -> bool:
	return (c >= 0x61 and c <= 0x7A) or (c >= 0x30 and c <= 0x39) or c == 0x5F


static func _is_path_char(c: int) -> bool:
	# A-Z, then "-", "." and "/".
	return _is_id_char(c) or (c >= 0x41 and c <= 0x5A) or c in [0x2D, 0x2E, 0x2F]


static func _is_printable_char(c: int) -> bool:
	return c >= 0x20 and c <= 0x7E


## Where `raw` stops being well-formed UTF-8 (RFC 3629: the shortest form only, no surrogate,
## nothing above U+10FFFF), or -1 when it is; a character is_name_char refuses is a problem too.
static func _utf8_problem(raw: PackedByteArray) -> int:
	var at := 0
	while at < raw.size():
		var tail := _utf8_tail(raw[at])
		if tail < 0 or at + tail >= raw.size():
			return at
		var code: int = raw[at] & UTF8_LEAD_BITS[tail]
		for i: int in range(1, tail + 1):
			var byte := raw[at + i]
			if byte & 0xC0 != 0x80:
				return at
			code = (code << 6) | (byte & 0x3F)
		if code < UTF8_SMALLEST[tail] or not is_name_char(code):
			return at
		at += tail + 1
	return -1


## How many continuation bytes follow the lead byte `lead`; -1 when it cannot lead (a continuation
## byte, C0 and C1, which only lead overlong forms, and F5 to FF, which lead nothing below
## U+110000).
static func _utf8_tail(lead: int) -> int:
	if lead < 0x80:
		return 0
	if lead >= 0xC2 and lead <= 0xDF:
		return 1
	if lead >= 0xE0 and lead <= 0xEF:
		return 2
	if lead >= 0xF0 and lead <= 0xF4:
		return 3
	return -1
