extends GdUnitTestSuite
## The tutorial's room against its design (#600; docs/design/tutorial.md §4, D33, D34) and the level
## piece conventions (#607): the map places one room, at the origin with no rotation, about 12 x
## 10 m; the room passes the host's level check (#112: layer-1 colliders, no CSG collision); its
## markers are the design's stations, each on the floor inside the room, no `lobby_player` and
## no `circle` (#900: the tutorial deals no task); the respawn marker is farther than the
## mode's respawn_free_m from the corner's stand-in and within the voice radius of it; no throw at
## the mode's Throw numbers leaves the room (#901, the throw checks as in #746).

const MAP := "res://levels/tutorial/tutorial.tscn"
const ROOM := "res://levels/tutorial/rooms/tutorial_room.tscn"
const MODE := "res://content/modes/tutorial_mode.tres"


func test_the_map_places_one_room_at_the_origin() -> void:
	var map: Node3D = auto_free((load(MAP) as PackedScene).instantiate())
	assert_int(map.get_child_count()).is_equal(1)
	var room := map.get_child(0) as Node3D
	assert_str(room.scene_file_path).is_equal(ROOM)
	assert_bool(room.transform.is_equal_approx(Transform3D.IDENTITY)).is_true()
	assert_vector(room.get_meta(&"size_m") as Vector2i).is_equal(Vector2i(12, 10))
	assert_str((room.get_node(^"Name") as Label3D).text).is_equal("Tutorial")


func test_the_room_passes_the_host_s_level_check() -> void:
	var world := LevelWorld.build(MAP)
	assert_array(Array(world.errors)).is_empty()
	assert_int(world.body_count()).is_greater(0)


func test_the_markers_are_the_design_s_stations_on_the_floor() -> void:
	var layout := _layout()
	var counts := {}
	for tag: StringName in layout.tags():
		counts[tag] = layout.count(tag)
		for at: Vector3 in layout.positions(tag):
			assert_float(at.y).override_failure_message(str(tag)).is_equal_approx(0.0, 1e-6)
			var inside := at.x > 0.0 and at.x < 12.0 and at.z > 0.0 and at.z < 10.0
			assert_bool(inside).override_failure_message("%s at %s" % [tag, at]).is_true()
	assert_dict(counts).is_equal({&"round_player": 3, &"package": 1, &"knife": 1, &"respawn": 1})


func test_the_respawn_is_free_of_the_corner_and_within_its_voice_radius() -> void:
	var mode := load(MODE) as GameMode
	var layout := _layout()
	var corner := layout.positions(&"round_player")[2]
	var respawn := layout.positions(&"respawn")[0]
	var radius := (mode.find_phase(&"death_stage").voice_rule as RoundVoice).living_m
	var apart := corner.distance_to(respawn)
	assert_float(apart).is_greater(mode.player_rules.respawn_free_m)
	assert_float(apart).is_less(radius)


func test_the_markers_read_without_errors_in_the_host_s_world() -> void:
	# What a real session does: the room's own colliders (shelf, table) in the host's world.
	var mode := load(MODE) as GameMode
	var world := HostWorldQuery.new()
	world.add_level(LevelWorld.build(MAP))
	world.use_level(MAP)
	var read := MarkerReader.read_scene(MAP, world, MarkerReader.floor_tags_of(mode))
	assert_array(Array(read.errors)).is_empty()
	var layouts: Dictionary[String, LevelLayout] = {MAP: read.layout}
	assert_array(Array(LayoutCheck.run(mode, layouts))).is_empty()


func test_no_throw_at_the_mode_s_numbers_leaves_the_room() -> void:
	# Every spot a player stands on (the floor every 2 m, the table's top) throws the fan; each
	# throw rests inside the room or on a wall's top. A flight that clears a wall ends over no
	# floor and rests at its fallback, the floor below the thrower (Items.fallback_rest, TD11 (a)).
	# Known, not a failure (the engineer's answer,
	# https://github.com/xperiaroco2/prime-game/issues/901#issuecomment-6163854335): from the table
	# against the 3 m north wall, 9 of the 648 throws per spot at 5 m/s rest on the wall's top,
	# 2.25 m from the nearest standable spot (PickUp reaches 2.0 m); the room stays as it is until
	# the tutorial map's rework (#911). An item there blocks no later lesson (LD3).
	var throws := _room_throws(_world(false), _throw_of(load(MODE) as GameMode).speed_mps)
	assert_int(throws.spots).is_greater(30)
	assert_array(throws.left).override_failure_message(str(throws.left)).is_empty()
	# The known rests on a wall's top stay at 9 per table spot (an item there is out of reach).
	var on_wall: int = throws.on_wall
	var table_spots: int = throws.table_spots
	var msg := "%d throws rest on a wall's top" % on_wall
	assert_int(on_wall).override_failure_message(msg).is_less_equal(9 * table_spots)


func test_a_throw_over_a_wall_onto_ground_outside_leaves_the_room() -> void:
	# The check above is not blind: with ground around the room, a throw from the table that
	# clears the north wall rests outside.
	var speed := _throw_of(load(MODE) as GameMode).speed_mps
	assert_array(_room_throws(_world(true), speed).left).is_not_empty()


## The fan (a yaw every 10 degrees, a pitch every 5 from level to 85 up: 648 throws) from every
## spot, flown as FlightTicks flies it (house_throws.gd's rest_of): the first contact or the
## longest flight stops it, then the floor below the stop lifted, or the fallback below the
## thrower's feet. `left`: each rest with no floor or outside the room's 12 x 10 m; `on_wall`:
## how many rest on a wall's top; `table_spots`: the spots above the floor.
func _room_throws(world: HostWorldQuery, speed: float) -> Dictionary:
	var mode := load(MODE) as GameMode
	var rules := mode.player_rules
	var throw := _throw_of(mode)
	var down := Vector3(0.0, -throw.gravity_mps2, 0.0)
	var max_ticks := maxi(1, Ticks.from_seconds(throw.longest_flight_s))
	var left: Array[String] = []
	var on_wall := 0
	var table_spots := 0
	var spots := _room_spots(world, rules.jump_height_m)
	for feet: Vector3 in spots:
		if feet.y > 0.1:
			table_spots += 1
		var eye := feet + Vector3.UP * rules.eye_height_m
		var fallback := world.floor_below(Items.lifted(feet))
		for yaw_deg in range(0, 360, 10):
			for pitch_deg in range(0, 86, 5):
				var yaw := deg_to_rad(yaw_deg)
				var pitch := deg_to_rad(pitch_deg)
				var facing := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
				var stop := eye
				for n in range(1, max_ticks + 1):
					var from := ItemFlight.point(eye, facing * speed, down, n - 1)
					var to := ItemFlight.point(eye, facing * speed, down, n)
					stop = world.sweep(from, to, throw.radius_m)
					if stop != to:
						break
				var rest := world.floor_below(Items.lifted(stop))
				if rest == WorldQuery.NO_FLOOR:
					rest = fallback
				var inside := rest.x > 0.0 and rest.x < 12.0 and rest.z > 0.0 and rest.z < 10.0
				if rest == WorldQuery.NO_FLOOR or not inside:
					left.append("from %s at %d/%d to %s" % [feet, yaw_deg, pitch_deg, rest])
				elif rest.y > 3.0 - 0.05:
					on_wall += 1
	return {"spots": spots.size(), "left": left, "on_wall": on_wall, "table_spots": table_spots}


## The tutorial map's host world; `ground_outside`: with a 40 x 40 m floor under the room.
func _world(ground_outside: bool) -> HostWorldQuery:
	var root := (load(MAP) as PackedScene).instantiate()
	if ground_outside:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(40.0, 0.2, 40.0)
		shape.shape = box
		body.add_child(shape)
		body.position = Vector3(6.0, -0.1, 5.0)
		root.add_child(body)
	var level := LevelWorld.from_scene(root, MAP)
	root.free()
	var world := HostWorldQuery.new((load(MODE) as GameMode).player_rules.capsule_radius_m)
	world.add_level(level)
	world.use_level(MAP)
	return world


## The floor every 2 m and the table's top: in each column, the highest floor under the walls'
## top a player's jump (PlayerRules.jump_height_m) reaches from the ground, so not the shelf's top.
func _room_spots(world: HostWorldQuery, jump: float) -> Array[Vector3]:
	var columns: Array[Vector2] = []
	for x in range(1, 12, 2):
		for z in range(1, 10, 2):
			columns.append(Vector2(x, z))
	for x: float in [7.9, 8.5, 9.1]:
		for z: float in [0.3, 0.7]:
			columns.append(Vector2(x, z))
	var spots: Array[Vector3] = []
	for column in columns:
		var at := world.floor_below(Vector3(column.x, 2.9, column.y))
		if at != WorldQuery.NO_FLOOR and at.y <= jump:
			spots.append(at)
	return spots


func _throw_of(mode: GameMode) -> ThrowItem:
	for rule: Rule in mode.actions:
		if rule.trigger == Intents.THROW:
			for effect: RuleEffect in rule.effects:
				if effect is ThrowItem:
					return effect as ThrowItem
	return null


func _layout() -> LevelLayout:
	var levels := MarkerReader.read_levels(load(MODE) as GameMode, FlatWorldQuery.new())
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts[MAP]


func test_the_room_has_its_record_and_the_map_screen_names_it() -> void:
	# #715 (#306): id `tutorial`, the deck's `room.tutorial` in English and Ukrainian, the outline
	# from size_m.
	var map: Node3D = auto_free((load(MAP) as PackedScene).instantiate())
	var rooms := MapData.rooms_of(map)
	assert_int(rooms.size()).is_equal(1)
	assert_str(String(rooms[0].id)).is_equal("tutorial")
	assert_str(rooms[0].name_key).is_equal("room.tutorial")
	assert_object(rooms[0].rect).is_equal(Rect2(0, 0, 12, 10))
	for locale: String in ["en", "uk"]:
		var translation := load("res://client/i18n/strings.%s.translation" % locale) as Translation
		var text := String(translation.get_message("room.tutorial"))
		assert_str(text).is_not_empty()
		assert_str(text).is_not_equal("room.tutorial")
