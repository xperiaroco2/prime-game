class_name DispenserCapCheck
extends RefCounted
## ModeCheck's check of the kinds a station dispenses (#1416; ARCHITECTURE §9.4.2): a kind that a
## GiveItem in a rule of a station no task type owns (the lobby's tap) hands out must be capped at
## `2 x max_players + 1` or more, the rule the task types' own checks keep for their dispensers
## (two hands' worth for every player, and one to spare), so a few hoarders never leave a pour
## `unavailable` for the rest.


## The problems of `mode`'s station-dispensed kinds, empty when none.
static func problems(mode: GameMode) -> PackedStringArray:
	var found := PackedStringArray()
	var least := least_cap(mode)
	for station: StationKind in Stations.kinds_in(mode):
		if Stations.owner_of(mode, station) != null:
			continue
		for rule: Rule in station.actions:
			if rule == null:
				continue
			for effect: RuleEffect in rule.effects:
				var give := effect as GiveItem
				if give == null or give.kind == null or give.kind.max_items >= least:
					continue
				var text := "station kind %s gives %s, whose max_items %d is below %d (2 x %d players + 1)"
				found.append(
					text % [station.id, give.kind.id, give.kind.max_items, least, mode.max_players]
				)
	return found


## The smallest cap a station-dispensed kind may have in `mode`: 2 x max_players + 1.
static func least_cap(mode: GameMode) -> int:
	return 2 * mode.max_players + 1
