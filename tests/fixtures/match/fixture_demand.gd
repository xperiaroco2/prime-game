class_name FixtureDemand
extends RuleEffect
## A transition action that does nothing but demand `count_setting` markers of `tag` and, with a
## `station`, as many of its colours: it stands in for SpawnItems and a task type's deal in the
## fit check's tests (§9.4).

@export var tag: StringName
@export var count_setting: StringName
@export var station: StationKind


static func of(
	spawn_tag: StringName, setting_id: StringName, station_kind: StationKind = null
) -> FixtureDemand:
	var effect := FixtureDemand.new()
	effect.tag = spawn_tag
	effect.count_setting = setting_id
	effect.station = station_kind
	return effect


func add_demands(settings: Dictionary[StringName, int], _players: int, into: Demands) -> void:
	var count: int = settings.get(count_setting, 0)
	into.add_markers(tag, count)
	if station != null:
		into.add_colours(station, count)
