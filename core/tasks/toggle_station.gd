class_name ToggleStation
extends RuleEffect
## Flips the world toggle whose station the intent names (#1295, ARCHITECTURE §9.4.2): the bookcase
## swings open or shut, a cover lifts or drops, the breaker is thrown. A toggle is every station of
## the kinds that share the station's `toggle_key` and its `index` (the bookcase's book and the wine
## rack's bottle are one); a kind with no key is a toggle of its own stations, one by one. Each
## station of the toggle takes the new state, in id order, and SwitchChanged (everyone: a toggle is
## public, it names no player) tells it; with a key the host's world follows (WorldQuery.set_toggle,
## once). Requires AtStation and StationInSight in its rule (ModeCheck), so only a player in reach
## and in sight flips it, and only in a toggle kind's rule (a kind PlaceToggles places).
##
## Emits: SwitchChanged (everyone), one per station of the toggle.


func run(ctx: MatchContext) -> void:
	var station := Stations.target_of(ctx)
	if station == null or not Stations.toggle_kinds(ctx.mode).has(station.kind):
		ctx.error("ToggleStation: the intent names no toggle station of the mode")
		return
	var now := not station.on
	var key := station.kind.toggle_key
	var ids: Array[int] = []
	ids.assign(ctx.state.stations.keys())
	ids.sort()
	for id: int in ids:
		var each := ctx.state.stations[id]
		if each == station or (not key.is_empty() and _same_toggle(each, station)):
			each.on = now
			ctx.emit(SwitchChangedEvent.new(id, now))
	if not key.is_empty():
		ctx.world.set_toggle(key, station.index, now)


## The condition classes its rule must hold, not negated (ModeCheck).
func required_conditions() -> Array[Script]:
	return [AtStation, StationInSight]


func emits() -> Array[Script]:
	return [SwitchChangedEvent]


static func _same_toggle(a: StationState, b: StationState) -> bool:
	return a.kind.toggle_key == b.kind.toggle_key and a.index == b.index
