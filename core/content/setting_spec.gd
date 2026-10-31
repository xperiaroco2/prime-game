class_name SettingSpec
extends ContentPart
## A match setting (ARCHITECTURE §9.1): a value the host changes in the lobby, declared by the
## mode with its default and bounds. A part names it in a property ending in `_setting`
## (`count_setting = &"knives"`); a part never reads another part's settings.
##
## Two kinds: a whole number (MatchState.settings, bounded by min_value and max_value), or a set
## of the mode's task type ids (MatchState.id_sets; the base mode's `banned_task_types`, #79),
## whose default is the empty set and which has no numbers.
##
## A number's default may follow the players present (#1492): `defaults_by_players` maps a player
## count to the default from that count on (default_for). The lobby keeps such a setting at
## default_for(present players) until the host names it (PlayerCountDefaults,
## MatchState.host_settings).

enum Kind {
	## A whole number within min_value and max_value.
	NUMBER,
	## A set of ids of the mode's task types, empty by default.
	TASK_TYPES,
}

@export var id: StringName
@export var display_name: String
@export var kind := Kind.NUMBER
@export var default_value := 0
@export var min_value := 0
@export var max_value := 0
## A whole number's default by the players present: player count -> the default from that count
## on (the entry with the highest key at or below the count). Fewer players than the lowest key,
## or an empty table: default_value. Keys from 1 to the mode's max_players; each value within the
## bounds. Empty for a set of task types.
@export var defaults_by_players: Dictionary[int, int] = {}


func check(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if id.is_empty():
		found.append("a setting has no id")
	if kind == Kind.TASK_TYPES:
		var numbers := default_value != 0 or min_value != 0 or max_value != 0
		if numbers or not defaults_by_players.is_empty():
			found.append("setting %s is a set of task types and has no numbers" % id)
		if mode != null and mode.task_types.is_empty():
			found.append("setting %s is a set of task types, but the mode has none" % id)
		return found
	if min_value > max_value:
		found.append("setting %s: min_value %d is above max_value %d" % [id, min_value, max_value])
	append_found(
		found, [out_of_bounds("setting %s default_value" % id, default_value, min_value, max_value)]
	)
	var counts: Array[int] = []
	counts.assign(defaults_by_players.keys())
	counts.sort()
	for players: int in counts:
		if players < 1:
			found.append("setting %s: defaults_by_players key %d is below 1 player" % [id, players])
		elif mode != null and players > mode.max_players:
			found.append(
				(
					"setting %s: defaults_by_players key %d is above max_players %d"
					% [id, players, mode.max_players]
				)
			)
		var name := "setting %s defaults_by_players[%d]" % [id, players]
		append_found(
			found, [out_of_bounds(name, defaults_by_players[players], min_value, max_value)]
		)
	return found


## The default with `players` present: the table's entry with the highest key at or below
## `players`, else default_value.
func default_for(players: int) -> int:
	var best := 0
	var value := default_value
	for from: int in defaults_by_players:
		if from <= players and from > best:
			best = from
			value = defaults_by_players[from]
	return value


func is_number() -> bool:
	return kind == Kind.NUMBER


func accepts(value: int) -> bool:
	return value >= min_value and value <= max_value
