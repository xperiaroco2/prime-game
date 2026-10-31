extends GdUnitTestSuite
## The estate's world toggles (#1459) follow the toggle level contract (ARCHITECTURE §4.5.9,
## levels/CLAUDE.md): the base mode's PlaceToggles kinds each find their markers on the estate,
## every part in a `toggle_<key>` group builds in the host's world without an error, the marker of
## each toggle's station stands at its own part (a part's `toggle_index` is its marker's ordinal, so
## a marker out of order would open another passage), each marker can be used in sight from a
## standing spot with its toggle shut and open, and a shut toggle closes its opening while an open
## one leaves it free. The places and the kinds' numbers are an agent's draft, "not a decision",
## for the engineer's yes or no (#1459's PR).

const MAP := "res://levels/estate/estate.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## The markers each toggle kind has on the estate: the bookcase and the wine rack, each side of the
## secret stair (estate-map §5b); a manhole and its inside for the cellar, the bonfire, the well and
## the ship's west wing (§5b); the six fixed cameras (§5c); the light breaker (§6).
const MARKERS := {
	&"bookcase": 1,
	&"wine_rack": 1,
	&"bookcase_inside": 1,
	&"wine_rack_inside": 1,
	&"manhole": 4,
	&"manhole_inside": 4,
	&"fixed_camera": 6,
	&"light_breaker": 1,
}
## The estate's toggle parts: the bookcase and the wine rack, four covers, six cameras.
const PARTS := 12
## How far a toggle's station marker stands from each part of its toggle at most.
const NEAR_PART_M := 5.5
## How far from its marker a player is looked for (on it, then around it): inside the kinds' 1.5 m
## radius.
const STANDS_M: Array[float] = [0.0, 0.5, 0.9]
## How far the floor under a standing spot may lie from the marker's: a step, no storey.
const STEP_M := 0.5
## How far a marker may stand off the floor under it: float noise, no step.
const SPAWN_FLOOR_M := 0.02
## The rays through each opening (world points), from the room's side to the passage's: the
## bookcase (the house at x 68.4, z 11: the library's opening at local x 1, z -4.9), the wine rack
## (the cellar's at local x -9.1) and each cover, from above it to below it.
const OPENINGS := [
	[&"bookcase", 0, Vector3(69.4, 4.4, 6.6), Vector3(69.4, 4.4, 5.3)],
	[&"manhole", 0, Vector3(64, -2.4, 11.95), Vector3(64, -3.9, 11.95)],
	[&"manhole", 1, Vector3(63.5, 1, 51), Vector3(63.5, -0.6, 51)],
	[&"manhole", 2, Vector3(32.5, 1, 68), Vector3(32.5, -0.6, 68)],
	[&"manhole", 3, Vector3(102, 1, 70.5), Vector3(102, -0.6, 70.5)],
]
## The wine rack's opening, which the same bookcase toggle opens.
const WINE_RACK_FROM := Vector3(59.3, -2, 6.7)
const WINE_RACK_TO := Vector3(59.3, -2, 5.3)


func test_every_toggle_part_builds_without_an_error() -> void:
	var level := LevelWorld.build(MAP)
	assert_array(Array(level.errors)).is_empty()
	assert_int(level.toggle_part_count()).is_equal(PARTS)


func test_the_base_mode_places_every_toggle_kind_on_its_markers() -> void:
	var mode := _base_mode()
	var layout := _read(mode).layout
	var placed: Array[StringName] = []
	for kind: StationKind in Stations.toggle_kinds(mode):
		placed.append(kind.id)
		(
			assert_int(layout.count(kind.spawn_tag))
			. override_failure_message("%s's markers" % kind.id)
			. is_equal(MARKERS.get(kind.id, -1))
		)
	assert_array(placed).contains_exactly_in_any_order(MARKERS.keys())


func test_each_toggle_marker_stands_at_its_own_part() -> void:
	var mode := _base_mode()
	var layout := _read(mode).layout
	var parts := _parts()
	assert_int(parts.size()).is_equal(PARTS)
	for kind: StationKind in Stations.toggle_kinds(mode):
		if kind.toggle_key.is_empty():
			continue
		var spots := layout.positions(kind.spawn_tag)
		for i in spots.size():
			var nearest := INF
			var nearest_name := "none"
			for part: Part in parts:
				if part.key == kind.toggle_key and part.index == i:
					var gap := spots[i].distance_to(part.at)
					if gap < nearest:
						nearest = gap
						nearest_name = part.name
			(
				assert_float(nearest)
				. override_failure_message(
					(
						"%s's marker %d at %s: its toggle's nearest part (%s) is %.1f m away"
						% [kind.id, i, spots[i], nearest_name, nearest]
					)
				)
				. is_less_equal(NEAR_PART_M)
			)


func test_each_toggle_marker_is_used_in_sight_shut_and_open() -> void:
	var mode := _base_mode()
	var world := _world(mode)
	var layout := MarkerReader.read_scene(MAP, world, MarkerReader.floor_tags_of(mode)).layout
	var eye := mode.player_rules.eye_height_of(false)
	for kind: StationKind in Stations.toggle_kinds(mode):
		var spots := layout.positions(kind.spawn_tag)
		for i in spots.size():
			for on: bool in [false, true]:
				world.reset_toggles()
				if not kind.toggle_key.is_empty():
					world.set_toggle(kind.toggle_key, i, on)
				(
					assert_bool(_usable(world, spots[i], eye))
					. override_failure_message(
						(
							"%s's marker %d at %s: no standing spot sees it (on: %s)"
							% [kind.id, i, spots[i], on]
						)
					)
					. is_true()
				)


func test_a_shut_toggle_closes_its_opening_and_an_open_one_frees_it() -> void:
	var world := _world(_base_mode())
	for opening: Array in OPENINGS:
		var key: StringName = opening[0]
		var index: int = opening[1]
		var from: Vector3 = opening[2]
		var to: Vector3 = opening[3]
		var where := "%s %d from %s" % [key, index, from]
		world.reset_toggles()
		(
			assert_bool(world.line_of_sight(from, to))
			. override_failure_message(where + ": open while shut")
			. is_false()
		)
		world.set_toggle(key, index, true)
		(
			assert_bool(world.line_of_sight(from, to))
			. override_failure_message(where + ": shut while open")
			. is_true()
		)
	world.reset_toggles()
	assert_bool(world.line_of_sight(WINE_RACK_FROM, WINE_RACK_TO)).is_false()
	world.set_toggle(&"bookcase", 0, true)
	assert_bool(world.line_of_sight(WINE_RACK_FROM, WINE_RACK_TO)).is_true()


## Whether a player standing on `marker` or STANDS_M from it in one of eight directions, on a floor
## a step from the marker's, reaches that spot from the marker in a straight line and sees the
## marker from its eye (StationInSight's line). A part standing on the marker blocks every spot.
func _usable(world: HostWorldQuery, marker: Vector3, eye: float) -> bool:
	var target := Items.lifted(marker)
	for away: float in STANDS_M:
		for step in 8:
			var spot := marker + Vector3.FORWARD.rotated(Vector3.UP, step * TAU / 8) * away
			if away > 0.0 and not world.line_of_sight(target, Items.lifted(spot)):
				continue
			var ground := world.stand_floor_below(spot + Vector3.UP * STEP_M)
			if ground == WorldQuery.NO_FLOOR or absf(ground.y - marker.y) > STEP_M:
				continue
			if world.line_of_sight(ground + Vector3.UP * eye, target):
				return true
	return false


func test_each_toggle_marker_stands_on_the_floor() -> void:
	# PlaceToggles' kinds are no task type's, so the host reads their markers as placed
	# (MarkerReader.floor_tags_of): each must be placed on its floor.
	var mode := _base_mode()
	var world := _world(mode)
	var layout := MarkerReader.read_scene(MAP, world, MarkerReader.floor_tags_of(mode)).layout
	for kind: StationKind in Stations.toggle_kinds(mode):
		for spot: Vector3 in layout.positions(kind.spawn_tag):
			var ground := world.floor_below(Items.lifted(spot))
			(
				assert_float(absf(ground.y - spot.y))
				. override_failure_message(
					"%s's marker at %s: its floor is %s" % [kind.id, spot, ground]
				)
				. is_less_equal(SPAWN_FLOOR_M)
			)


## Each toggle part of the estate: its name, key, index and centre in the map.
func _parts() -> Array[Part]:
	var root := auto_free((load(MAP) as PackedScene).instantiate()) as Node3D
	var found: Array[Part] = []
	_collect(root, root, found)
	return found


func _collect(node: Node, root: Node3D, found: Array[Part]) -> void:
	if node is StaticBody3D:
		for group: StringName in node.get_groups():
			if String(group).begins_with(StationKind.TOGGLE_GROUP_PREFIX):
				var part := Part.new()
				part.name = String(root.get_path_to(node))
				part.key = StringName(String(group).trim_prefix(StationKind.TOGGLE_GROUP_PREFIX))
				if node.has_meta(StationKind.TOGGLE_INDEX_META):
					part.index = node.get_meta(StationKind.TOGGLE_INDEX_META) as int
				part.at = LevelWorld.transform_in_scene(node as Node3D, root).origin
				found.append(part)
	for child: Node in node.get_children():
		_collect(child, root, found)


func _base_mode() -> GameMode:
	return load(BASE_MODE) as GameMode


func _world(mode: GameMode) -> HostWorldQuery:
	var rules := mode.player_rules
	var world := HostWorldQuery.new(rules.capsule_radius_m, rules.crouch_height_m)
	world.add_level(LevelWorld.build(MAP))
	world.use_level(MAP)
	return world


func _read(mode: GameMode) -> MarkerReader.Read:
	return MarkerReader.read_scene(MAP, _world(mode), MarkerReader.floor_tags_of(mode))


## A toggle part of the estate: its path in the map, key, index and centre in the map.
class Part:
	var name := ""
	var key: StringName
	var index := -1
	var at := Vector3.ZERO
