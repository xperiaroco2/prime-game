extends GdUnitTestSuite
## The dead's hall is no room of a round map (#1489): the map's rooms stay the map's, so a hall far
## off (x = 2000) does not stretch the M map's bounds. Its 40 m by 40 m room lives on the lobby's
## instance, not on the shared scene the hall piece instances.

const MAPS: Array[String] = [
	"res://levels/greybox/greybox.tscn",
	"res://levels/house/house.tscn",
	"res://levels/estate/estate.tscn",
]


func test_no_round_map_counts_the_hall_as_a_room() -> void:
	for path: String in MAPS:
		var root: Node = auto_free((load(path) as PackedScene).instantiate())
		add_child(root)
		for room: MapData.Room in MapData.rooms_of(root):
			(
				assert_float(room.rect.position.x)
				. override_failure_message("%s: room %s" % [path, room.id])
				. is_less(1000.0)
			)


func test_the_lobby_keeps_its_room() -> void:
	var root: Node = auto_free((load("res://levels/lobby/lobby.tscn") as PackedScene).instantiate())
	add_child(root)
	assert_int(MapData.rooms_of(root).size()).is_equal(1)
