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
## with the join count, and the lobby's name is at most 20 characters (#214): bound both by the
## name type itself.
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
## role, item kind or station kind to name) is left out, but HerbsDealt (_herbs_dealt).
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
	found.append(_herbs_dealt(mode))
	found.append(_shot_taken())
	return found


## Cooking's HerbsDealt (#772, the cooking ADR's CE9): both lists hold the type's herbs, each once
## (the code and the beds are two permutations of them), so the type's own ids are its exact size;
## the largest over the mode's Cooking types. A mode without Cooking still gets the case, with
## empty lists, so every content-sized kind has one in every mode (as the base mode's test asks).
static func _herbs_dealt(mode: GameMode) -> WireMessage:
	var largest := PackedStringArray()
	var largest_bytes := -1
	for type: TaskType in mode.task_types:
		if not type is Cooking:
			continue
		var ids := PackedStringArray()
		var bytes := 0
		for herb: ItemKind in (type as Cooking).herbs:
			var herb_id := String(herb.id) if herb != null else ""
			ids.append(herb_id)
			bytes += 1 + herb_id.length()
		if bytes > largest_bytes:
			largest = ids
			largest_bytes = bytes
	return WireMessage.new(&"HerbsDealt", {"code": largest, "beds": largest})


## The photo camera's ShotTaken with a full record (the photo ADR §3.3): PhotoTask.MAX_RECORD rows,
## every id at its largest and both hand and belt items set. Its size does not depend on the mode.
static func _shot_taken() -> WireMessage:
	var record: Array[Dictionary] = []
	for i in PhotoTask.MAX_RECORD:
		(
			record
			. append(
				{
					"peer": WireField.PEER_MAX - i,
					"position": Vector3.ONE,
					"facing": Vector3.FORWARD,
					"downed": true,
					"crouched": true,
					"held_item": 0xFFFE,
					"belt_item": 0xFFFD,
					"belt_item2": 0xFFFC,
				}
			)
		)
	return WireMessage.new(
		&"ShotTaken", {"station": 0xFFFE, "film": 0xFFFE, "shot": 0xFFFF, "record": record}
	)


static func _welcome(content: _Content) -> WireMessage:
	var roster: Array[Dictionary] = []
	var spots := content.spots(content.mode.max_players)
	for peer: int in spots:
		roster.append(
			{
				"peer": peer,
				"name": "P".repeat(NAME_BYTES),
				"ready": true,
				"colour": PlayerColours.COUNT - 1
			}
		)
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
		"lobby_name": "L".repeat(NAME_BYTES),
		"items": _welcome_items(content),
	}
	return WireMessage.new(&"Welcome", fields)


## The hall's items (#1404): WelcomeEvent.MAX_ITEMS rows of the mode's longest item kind id; none
## when the mode has no item kind.
static func _welcome_items(content: _Content) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if content.item.is_empty():
		return rows
	for i: int in WelcomeEvent.MAX_ITEMS:
		(
			rows
			. append(
				{
					"item": MatchState.MAX_ITEM_ID - i,
					"kind": content.item,
					"where": ItemState.Where.BELT as int,
					"holder": LARGEST_U32,
					"place": 2,
					"position": Vector3.ZERO,
				}
			)
		)
	return rows


static func _settings_changed(content: _Content) -> WireMessage:
	var shortfalls: Array[Dictionary] = []
	# At most one per demanded spawn tag and demanded palette (Demands.shortfalls: a station kind
	# no action demands a palette of has none, #784), each a text of one subject and the two
	# arguments `need` and `have` (_demanded_text), plus the player count and `no_task_types`
	# (FitCheck; a missing layout, `no_layout`, comes instead of the map's shortfalls), and the
	# task types' own layout problems (TaskType.most_layout_problems, #807), each counted as the
	# longest host text the wire takes (#548).
	var others := 2
	for type: TaskType in content.mode.task_types:
		if type != null:
			others += type.most_layout_problems()
	var demanded := _demanded_text(content)
	for i: int in content.tags.size() + content.palettes.size():
		shortfalls.append(demanded)
	for i: int in others:
		shortfalls.append(_longest_text())
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
		"lobby_name": "L".repeat(NAME_BYTES),
	}
	return WireMessage.new(&"SettingsChanged", fields)


static func _change_settings(content: _Content) -> Dictionary:
	var settings := {}
	settings.merge(content.numbers)
	settings.merge(content.id_sets)
	return {"settings": settings, "map": content.map, "lobby_name": "L".repeat(NAME_BYTES)}


## The longest host text the wire takes (#548): a 32-character id, the most subject ids and
## whole-number arguments, every id 32 characters.
static func _longest_text() -> Dictionary:
	var subjects := PackedStringArray()
	for i: int in WireSchema.MAX_TEXT_IDS:
		subjects.append(_wire_id("i", i))
	var numbers: Dictionary[StringName, int] = {}
	for i: int in WireSchema.MAX_TEXT_NUMBERS:
		numbers[StringName(_wire_id("n", i))] = WireField.S32_MIN
	return {"id": StringName(_wire_id("t", 0)), "ids": subjects, "numbers": numbers}


## The longest shortfall Demands.shortfalls makes for a demanded tag or palette of `content`: the
## longest of its three text ids (`markers`, `markers_exact`, `colours`), its one subject the
## longest demanded tag or palette station kind of the mode, and its two arguments `need` and
## `have` at their widest, so a mode that demands many tags is not sized as if each text held the
## most subjects and arguments a host text may, nor ids the content does not have (the 8192 bytes
## of SettingsChanged; #810: the House's 36 demanded tags with the car repair).
static func _demanded_text(content: _Content) -> Dictionary:
	var subjects := PackedStringArray()
	for tag: StringName in content.tags:
		subjects.append(String(tag))
	for kind: StringName in content.palettes:
		subjects.append(String(kind))
	var text_ids := PackedStringArray(
		[String(HostText.MARKERS), String(HostText.MARKERS_EXACT), String(HostText.COLOURS)]
	)
	var numbers: Dictionary[StringName, int] = {
		&"need": WireField.S32_MIN, &"have": WireField.S32_MIN
	}
	return {
		"id": StringName(_Content._longest(text_ids)),
		"ids": PackedStringArray([_Content._longest(subjects)]),
		"numbers": numbers,
	}


## A wire id of WireField.ID_MAX characters: `prefix`, then `index` padded with zeros.
static func _wire_id(prefix: String, index: int) -> String:
	return prefix + str(index).pad_zeros(WireField.ID_MAX - prefix.length())


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
	## The station kinds the map demands a palette of with every setting at its maximum (a subset
	## of `stations`): one shortfall each at most.
	var palettes: Array[StringName] = []

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
		palettes.assign(demands.colours.keys())
		# The station kinds the mode's task types place (TaskType.station_kinds, DE4): a kind with
		# no palette still has an id on the wire. The palettes a map demands are kept too, for a
		# demand that names a kind no task type holds.
		for kind: StationKind in Stations.kinds_in(mode):
			if not kind.id.is_empty() and not stations.has(kind.id):
				stations.append(kind.id)
		for colour_kind: StringName in demands.colours.keys():
			if not stations.has(colour_kind):
				stations.append(colour_kind)
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
