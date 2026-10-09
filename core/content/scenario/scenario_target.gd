class_name ScenarioTarget
extends Resource
## Where a step goes or faces, resolved from the bot's own view: the events and snapshots its
## client received (ARCHITECTURE §9.7). A target the bot cannot know fails the scenario. Data only.

## New kinds go at the end: a scenario's .tres stores the kind as its number.
enum Kind {
	PACKAGE,  ## the `index`-th package (1-based) in item-id order (tasks are shared, #79)
	CIRCLE_OF_HELD,  ## the circle of the package the bot holds
	NEAREST,  ## the nearest item of `item_kind` on the ground
	BOT,  ## where the bot last saw bot `bot`
	POINT,  ## `point`
	## the `index`-th station (1-based) of `station_kind` in station-id order, from the bot's own
	## StationPlaced events; a WalkTo to it takes `stop_m` 0 (M7-Z2)
	STATION,
}

@export var kind := Kind.POINT
@export var index := 1
@export var item_kind: StringName
## A StationKind's id (Delivery's `circle`), for STATION.
@export var station_kind: StringName
@export var bot := 1
@export var point := Vector3.ZERO


## What makes this target unusable; empty when it is fine.
func problems() -> PackedStringArray:
	var found := PackedStringArray()
	if kind == Kind.PACKAGE and index < 1:
		found.append("package index %d is below 1" % index)
	if kind == Kind.STATION and index < 1:
		found.append("station index %d is below 1" % index)
	if kind == Kind.STATION and station_kind.is_empty():
		found.append("station names no station kind")
	if kind == Kind.NEAREST and item_kind.is_empty():
		found.append("nearest names no item kind")
	if kind == Kind.BOT and bot < 1:
		found.append("bot %d is below 1" % bot)
	return found
