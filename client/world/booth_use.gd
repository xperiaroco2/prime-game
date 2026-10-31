class_name BoothUse
extends RefCounted
## The photo booth's lookups in the client's own copy of the mode (#1397, ARCHITECTURE §4.7.62): the
## strip kinds its StartBooth effects print, read from the station kinds' rules as BoothCheck does.


## The strip kind ids the mode's booths print.
static func strip_kinds(mode: GameMode) -> Array[StringName]:
	var found: Array[StringName] = []
	if mode == null:
		return found
	for kind: StationKind in Stations.kinds_in(mode):
		for rule: Rule in kind.actions:
			for effect: RuleEffect in rule.effects:
				var start := effect as StartBooth
				if start != null and start.strip != null and not found.has(start.strip.id):
					found.append(start.strip.id)
	return found


## Whether kind `kind_id` is a strip a booth of the mode prints.
static func is_strip(mode: GameMode, kind_id: StringName) -> bool:
	return kind_id != &"" and strip_kinds(mode).has(kind_id)
