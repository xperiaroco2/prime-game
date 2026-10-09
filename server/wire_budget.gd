class_name WireBudget
extends RefCounted
## Whether a game mode's content fits the wire (ARCHITECTURE §4.3, E16). The wire's maxima bound
## the decoder, not the payload: with the longest ids and paths some kinds would exceed their caps
## (SettingsChanged's `id_sets` alone could reach about 18 KB), and the encoder refuses a payload
## over its cap, so a reliable event would go missing in a playtest. This builds the worst case of
## every kind whose size the content sets (WireRow.content_sized) from the mode's own ids,
## settings, map paths, max_players and shortfalls, and encodes each. The host refuses a mode with
## a problem when it starts; a test runs it over every mode in content/, so `verify` catches a
## content edit first.

## A joiner's name is its own (at most 16 characters of UTF-8) or the host's Player<n>, which grows
## with the join count: bound it by the name type itself.
const NAME_BYTES := WireField.NAME_MAX_BYTES
const LARGEST_U32 := WireField.U32_MAX


## Every kind that does not fit, named with its worst case; empty when the mode fits the wire.
static func check(mode: GameMode) -> PackedStringArray:
	var schema := WireSchema.game(false)
	var found := PackedStringArray()
	for message: WireMessage in worst_cases(mode):
		var encoded := schema.write(message)
		if not encoded.problem.is_empty():
			found.append(
				"%s (kind %d): %s" % [message.name, schema.kind_of(message.name), encoded.problem]
			)
	return found


## The largest payload the mode can give each content-sized kind. A kind the mode never sends (no
## role, item kind or station kind to name) is left out.
static func worst_cases(mode: GameMode) -> Array[WireMessage]:
	var content := _Content.new(mode)
	var found: Array[WireMessage] = [
		_welcome(content),
		_settings_changed(content),
		WireMessage.new(
			&"LoadMatch", {"match_id": LARGEST_U32, "map": content.map, "settings": content.numbers}
		),
		WireMessage.new(&"ChangeSettings", _change_settings(content), LARGEST_U32),
		WireMessage.new(&"PlayersPlaced", {"spots": content.spots(mode.max_players)}),
	]
	if not content.role.is_empty():
		var peers := PackedInt32Array(content.spots(mode.max_players).keys())
		found.append(WireMessage.new(&"Teammates", {"role": content.role, "peers": peers}))
	if not content.station.is_empty():
		var placed := {
			"station": 0, "kind": content.station, "colour": Color.WHITE, "position": Vector3.ZERO
		}
		found.append(WireMessage.new(&"StationPlaced", placed))
	if not content.item.is_empty():
		var spawned := {
			"item": 0,
			"kind": content.item,
			"position": Vector3.ZERO,
			"station": 0,
			"colour": Color.WHITE,
		}
		found.append(WireMessage.new(&"ItemSpawned", spawned))
	return found


static func _welcome(content: _Content) -> WireMessage:
	var roster: Array[Dictionary] = []
	var spots := content.spots(content.mode.max_players)
	for peer: int in spots:
		roster.append({"peer": peer, "name": "P".repeat(NAME_BYTES), "ready": true})
	var others := content.spots(content.mode.max_players - 1)
	var fields := {
		"peer": 1,
		"spot": Vector3.ZERO,
		"epoch": LARGEST_U32,
		"roster": roster,
		"settings": content.numbers,
		"map": content.map,
		"phase": content.phase,
		"positions": others,
	}
	return WireMessage.new(&"Welcome", fields)


static func _settings_changed(content: _Content) -> WireMessage:
	var shortfalls := PackedStringArray()
	# At most one per demanded spawn tag and station kind, plus the player count and the layout.
	for i: int in content.tags.size() + content.stations.size() + 2:
		shortfalls.append("s".repeat(WireField.NOTE_MAX))
	var fields := {
		"settings": content.numbers,
		"id_sets": content.id_sets,
		"map": content.map,
		"players": content.mode.max_players,
		"needed_markers": content.counts(content.tags),
		"map_markers": content.counts(content.tags),
		"needed_colours": content.counts(content.stations),
		"palettes": content.counts(content.stations),
		"shortfalls": shortfalls,
	}
	return WireMessage.new(&"SettingsChanged", fields)


static func _change_settings(content: _Content) -> Dictionary:
	var settings := {}
	settings.merge(content.numbers)
	settings.merge(content.id_sets)
	return {"settings": settings, "map": content.map}


## What the worst cases are built from.
class _Content:
	var mode: GameMode
	## Every whole-number setting, and every set setting holding every task type.
	var numbers: Dictionary[StringName, int] = {}
	var id_sets: Dictionary[StringName, PackedStringArray] = {}
	## The longest map path, phase, role, item kind and station kind ("" when there is none).
	var map := ""
	var phase := ""
	var role := ""
	var item := ""
	var station := ""
	## The spawn tags and station kinds the map demands with every setting at its maximum.
	var tags: Array[StringName] = []
	var stations: Array[StringName] = []

	func _init(of_mode: GameMode) -> void:
		mode = of_mode
		var task_types := PackedStringArray()
		for type: TaskType in mode.task_types:
			if type != null:
				task_types.append(type.id)
		var largest: Dictionary[StringName, int] = {}
		for setting: SettingSpec in mode.settings:
			if setting == null:
				continue
			if setting.is_number():
				numbers[setting.id] = setting.default_value
				largest[setting.id] = setting.max_value
			else:
				id_sets[setting.id] = task_types
		map = _longest(mode.maps)
		phase = _longest(_ids(mode.phases))
		role = _longest(_ids(mode.roles))
		item = _longest(_ids(mode.item_kinds))
		var demands := LayoutCheck.demands_of(mode, PhaseSpec.Level.MAP, largest, mode.max_players)
		tags.assign(demands.markers.keys())
		stations.assign(demands.colours.keys())
		station = _longest(PackedStringArray(stations))

	## `count` distinct players (peer ids 2 and up) at the origin.
	func spots(count: int) -> Dictionary[int, Vector3]:
		var found: Dictionary[int, Vector3] = {}
		for i: int in maxi(count, 0):
			found[i + 2] = Vector3.ZERO
		return found

	func counts(ids: Array[StringName]) -> Dictionary[StringName, int]:
		var found: Dictionary[StringName, int] = {}
		for id: StringName in ids:
			found[id] = WireField.S32_MAX
		return found

	static func _ids(parts: Array) -> PackedStringArray:
		var found := PackedStringArray()
		for part: Variant in parts:
			if part != null:
				found.append(str((part as Object).get("id")))
		return found

	static func _longest(texts: PackedStringArray) -> String:
		var found := ""
		for text: String in texts:
			if text.length() > found.length():
				found = text
		return found
