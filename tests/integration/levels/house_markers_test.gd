extends GdUnitTestSuite
## The House map carries what the base mode asks of a map (ARCHITECTURE §9.4, §9.6): read by the
## host's marker reader in the host's world of the map, its markers raise no error (each delivery
## circle stands on a floor, no marker has two tags) and the layout check of a mode that plays on
## it finds nothing missing for the mode's maximum of players. The House is the base mode's second
## map (#626); the scenarios play only its flat first map (ARCHITECTURE §9.7).

const MAP := "res://levels/house/house.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"


func test_the_markers_read_without_errors_in_the_host_s_world() -> void:
	var read := _read(_base_mode())
	assert_array(Array(read.errors)).is_empty()


func test_a_mode_playing_on_the_house_finds_every_marker_it_needs() -> void:
	var mode := _base_mode().duplicate() as GameMode
	mode.lobby_level = ""
	mode.maps = PackedStringArray([MAP])
	var layouts: Dictionary[String, LevelLayout] = {MAP: _read(mode).layout}
	assert_array(Array(LayoutCheck.run(mode, layouts))).is_empty()


func test_the_markers_are_the_engineer_s_counts() -> void:
	var layout := _read(_base_mode()).layout
	assert_int(layout.count(&"round_player")).is_equal(10)
	assert_int(layout.count(&"package")).is_equal(10)
	assert_int(layout.count(&"circle")).is_equal(10)
	assert_int(layout.count(&"knife")).is_equal(4)
	assert_int(layout.count(&"respawn")).is_equal(4)


func _base_mode() -> GameMode:
	return load(BASE_MODE) as GameMode


func _read(mode: GameMode) -> MarkerReader.Read:
	var world := HostWorldQuery.new()
	world.add_level(LevelWorld.build(MAP))
	world.use_level(MAP)
	return MarkerReader.read_scene(MAP, world, MarkerReader.floor_tags_of(mode))
