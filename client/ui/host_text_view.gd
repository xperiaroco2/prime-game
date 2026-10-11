class_name HostTextView
extends RefCounted
## Host text in this client's language (ARCHITECTURE §4.7.47, #548): the host sends an id, its
## subject ids and whole-number arguments (core's HostText, as {id, ids, numbers}), never a
## sentence; this client owns the table from the id to a key of the UI copy deck (§4.7.26) and
## words it with tr, so two players of one lobby each read it in their own language. Pure: no node.
##
## The deck (ui-0.4.0) has a key for `players_few` only. `players_many`, `markers`, `colours` and
## `no_layout` have none: no key is invented here, so they show plain(), a neutral line of the id
## and its arguments, until the UI track's deck adds theirs (a gap the PR lists). A start held
## back must still say why.

## Shortfall id (HostText's) -> its deck key.
const SHORTFALL_KEYS: Dictionary[StringName, String] = {
	&"players_few": "lobby.need_more",
}
## Shortfall id -> the argument its key's plural form follows (tr_n's n); absent: no plural.
const PLURAL_BY: Dictionary[StringName, StringName] = {
	&"players_few": &"count",
}


## Every shortfall, one per line, in the host's order; "" for none.
static func shortfalls(texts: Array[Dictionary]) -> String:
	var lines := PackedStringArray()
	for text: Dictionary in texts:
		lines.append(shortfall(text))
	return "\n".join(lines)


## One shortfall in the current language: its deck key with the arguments as the key's
## placeholders ({count}, ...), or plain() where the deck has no key for its id.
static func shortfall(text: Dictionary) -> String:
	var id: StringName = text.get("id", &"")
	var key: String = SHORTFALL_KEYS.get(id, "")
	if key.is_empty():
		return plain(text)
	var numbers: Dictionary = text.get("numbers", {})
	var worded: String
	if PLURAL_BY.has(id):
		var count: int = numbers.get(PLURAL_BY[id], 0)
		worded = TranslationServer.translate_plural(key, key, count)
	else:
		worded = TranslationServer.translate(key)
	return worded.format(_placeholders(numbers))


## The id, its subjects and its arguments as `name=value`, space-separated: no words of any
## language, for an id the deck has no key for.
static func plain(text: Dictionary) -> String:
	var parts := PackedStringArray([str(text.get("id", ""))])
	var ids: PackedStringArray = text.get("ids", PackedStringArray())
	parts.append_array(ids)
	var numbers: Dictionary = text.get("numbers", {})
	var names: Array = numbers.keys()
	names.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for each: Variant in names:
		parts.append("%s=%d" % [each, numbers[each]])
	return " ".join(parts)


static func _placeholders(numbers: Dictionary) -> Dictionary:
	var found := {}
	for each: Variant in numbers:
		found[str(each)] = str(numbers[each])
	return found
