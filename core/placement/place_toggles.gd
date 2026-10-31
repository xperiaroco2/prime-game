class_name PlaceToggles
extends RuleEffect
## Places the map's world toggles (#1295, ARCHITECTURE §9.4.3): a transition row's action, after
## the deal's DealTasks in Loading -> Pregame (Match runs a row's actions after use_level of the
## phase it enters, so the world and the layout are the map's). First every toggle part of the
## level goes back to off (WorldQuery.reset_toggles: the host's level world outlives a match), then
## for each kind in list order a station stands on every marker of its `spawn_tag`, in the level's
## marker order: off, its `index` the marker's ordinal (StationState.index), its colour the kind's
## first palette colour, else white; StationPlaced (everyone) tells each. A level with no marker of
## a kind places none of it (a map may lack a toggle): no error and no demand. ClearStations takes
## them at the next match's Countdown -> Loading. Kinds that share a `toggle_key` pair their
## stations by index, so their marker counts on one level should agree (an unpaired station is a
## toggle alone).
##
## A joiner in Lobby or Countdown learns an open toggle from JoinRules' replay (StationPlaced, then
## SwitchChanged), so a mode may place toggles in a row into either too.
##
## Emits: StationPlaced (everyone). Demands: none.

## The toggle kinds placed, each with a ToggleStation rule (check).
@export var kinds: Array[StationKind] = []


func run(ctx: MatchContext) -> void:
	ctx.world.reset_toggles()
	if ctx.layout == null:
		ctx.error("PlaceToggles: the phase has no level layout")
		return
	for kind: StationKind in kinds:
		if kind == null:
			continue
		var spots := ctx.layout.positions(kind.spawn_tag)
		var colour := kind.palette[0] if not kind.palette.is_empty() else Color.WHITE
		for i in spots.size():
			var station := ctx.state.add_station(kind, spots[i], colour)
			station.index = i
			ctx.emit(StationPlacedEvent.new(station.id, kind.id, station.colour, station.position))


func emits() -> Array[Script]:
	return [StationPlacedEvent]


func check(_mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	if kinds.is_empty():
		found.append("PlaceToggles places no station kind")
	for i in kinds.size():
		var kind := kinds[i]
		if kind == null:
			found.append("PlaceToggles.kinds[%d] is empty" % i)
			continue
		if kinds.find(kind) != i:
			found.append("PlaceToggles lists station kind %s twice" % kind.id)
		if kind.display:
			found.append("PlaceToggles places station kind %s, a display kind" % kind.id)
		if not _toggles(kind):
			found.append(
				"PlaceToggles places station kind %s, which holds no ToggleStation rule" % kind.id
			)
	return found


static func _toggles(kind: StationKind) -> bool:
	for rule: Rule in kind.actions:
		if rule == null:
			continue
		for effect: RuleEffect in rule.effects:
			if effect is ToggleStation:
				return true
	return false
