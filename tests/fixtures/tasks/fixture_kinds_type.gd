class_name FixtureKindsType
extends TaskType
## A task type that holds its station kinds in a list instead of StationKind properties and
## overrides station_kinds() to name them (the delivery-by-meaning ADR's DE4, #827): the readers
## of a type's kinds (MarkerReader, ModeCheck's ZE3, CircleViews, WireBudget) must see them.

var held: Array[StationKind] = []


## A type `type_id` holding one kind per (id, spawn tag) pair.
static func of(type_id: StringName, kinds: Array[StationKind]) -> FixtureKindsType:
	var type := FixtureKindsType.new()
	type.id = type_id
	type.description = "Hold the kinds."
	type.held = kinds
	return type


## A station kind of `kind_id` standing on markers of `tag`.
static func kind(kind_id: StringName, tag: StringName) -> StationKind:
	var made := StationKind.new()
	made.id = kind_id
	made.spawn_tag = tag
	return made


func station_kinds() -> Array[StationKind]:
	return held
