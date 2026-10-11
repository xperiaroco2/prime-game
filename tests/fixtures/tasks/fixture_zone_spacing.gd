extends RefCounted
## ZE9's spacing of the zone task's markers on a map (the zone task ADR, ZE9; `levels/CLAUDE.md`),
## shared by `zone_content_test.gd` (every map of the base mode) and the House map's marker test
## (#651): any two zone markers at least twice the zone's radius apart; each zone marker at least
## its radius plus 1 m (the respawn point's free space) from every `round_player` and `respawn`
## marker, and at least its radius plus the circle's from every delivery circle's marker. Markers
## on different storeys (more than the taller cylinder's height apart in y) are not compared.

## The respawn point's free space (PlayerRules.respawn_free_m in the base mode), ZE9's 1 m.
const FREE_M := 1.0


## One line for each pair of markers on `layout` closer than ZE9 allows; empty when it keeps it.
static func faults(
	path: String, layout: LevelLayout, zone: StationKind, circle: StationKind
) -> PackedStringArray:
	var found := PackedStringArray()
	var zones := layout.positions(zone.spawn_tag)
	for i in zones.size():
		for j in range(i + 1, zones.size()):
			_check(found, path, zones[i], zones[j], 2.0 * zone.radius_m, zone.height_m)
		for tag: StringName in [&"round_player", &"respawn"]:
			for at: Vector3 in layout.positions(tag):
				_check(found, path, zones[i], at, zone.radius_m + FREE_M, zone.height_m)
		var height := maxf(zone.height_m, circle.height_m)
		for at: Vector3 in layout.positions(circle.spawn_tag):
			_check(found, path, zones[i], at, zone.radius_m + circle.radius_m, height)
	return found


## Whether `a` and `b` are at least `at_least` apart horizontally, or on different storeys (more
## than `height` apart in y).
static func apart(a: Vector3, b: Vector3, at_least: float, height: float) -> bool:
	if absf(a.y - b.y) > height:
		return true
	return Vector2(a.x - b.x, a.z - b.z).length() >= at_least


## The mode's zone task, or null.
static func zone_task(mode: GameMode) -> ZoneTask:
	for type: TaskType in mode.task_types:
		if type is ZoneTask:
			return type as ZoneTask
	return null


## The mode's delivery circle, or null.
static func circle(mode: GameMode) -> StationKind:
	for type: TaskType in mode.task_types:
		if type is Delivery:
			return (type as Delivery).circle
	return null


static func _check(
	found: PackedStringArray, path: String, a: Vector3, b: Vector3, at_least: float, height: float
) -> void:
	if not apart(a, b, at_least, height):
		found.append("%s: markers at %s and %s are closer than %.2f m" % [path, a, b, at_least])
