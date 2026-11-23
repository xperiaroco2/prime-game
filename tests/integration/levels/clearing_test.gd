extends GdUnitTestSuite
## The clearing (#1687, the engineer's "hide" of 2026-11-23): the M8 round's map, the estate's ship
## on its clearing in the estate's coordinates, then fog and an invisible boundary; the estate
## itself is no map of the base mode. Read by the host's marker reader in the host's world of the
## map, its markers raise no error and the base mode finds every marker it needs for its maximum
## of players; everything the round uses (its starts, the respawns, the engine's stations) stands
## inside the boundary on a floor, and the boundary is closed all round at a player's height. The
## clearing's size and the fog are looks, "not a decision" (the engineer's to tune).

const MAP := "res://levels/clearing/clearing.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
## The ship's origin, the clearing's middle (the estate's, docs/design/estate-map.md §5a).
const MIDDLE := Vector3(116, 0, 72)
## The tags the round places at, on the ground or the ship's deck: none may stand outside.
const ROUND_TAGS: Array[StringName] = [
	&"round_player",
	&"respawn",
	&"engine_console",
	&"gill_button",
	&"breaker_board",
	&"breaker",
	&"cartridge_socket",
	&"cartridge_charger",
	# Not the shipped round's: the knives the melee fixture's Loading spawns (as the estate held).
	&"knife",
]
## How far a marker may stand off the floor under it: float noise, no step.
const SPAWN_FLOOR_M := 0.02


func test_the_markers_read_without_errors_and_the_base_mode_finds_every_one() -> void:
	var mode := _base_mode()
	var read := _read(mode)
	assert_array(Array(read.errors)).is_empty()
	assert_array(Array(mode.player_maps())).contains_exactly([MAP])
	var layouts: Dictionary[String, LevelLayout] = {MAP: read.layout}
	var alone := mode.duplicate() as GameMode
	alone.lobby_level = ""
	alone.maps = PackedStringArray([MAP])
	alone.bench_maps = PackedStringArray()
	assert_array(Array(LayoutCheck.run(alone, layouts))).is_empty()
	assert_int(read.layout.count(&"round_player")).is_greater_equal(mode.max_players)


func test_the_round_s_markers_stand_inside_the_boundary_on_a_floor() -> void:
	var mode := _base_mode()
	var level := LevelWorld.build(MAP)
	var layout := _read(mode).layout
	var radius := _boundary_radius()
	for tag: StringName in ROUND_TAGS:
		assert_int(layout.count(tag)).override_failure_message(String(tag)).is_greater(0)
		for at: Vector3 in layout.positions(tag):
			var where := "%s at %s" % [tag, at]
			var flat := Vector2(at.x - MIDDLE.x, at.z - MIDDLE.z)
			assert_float(flat.length()).override_failure_message(where).is_less(radius - 1.0)
			var ray := PhysicsRayQueryParameters3D.create(
				at + Vector3.UP * 0.5, at + Vector3.DOWN * 2.0
			)
			var hit := level.space_state().intersect_ray(ray)
			assert_bool(hit.is_empty()).override_failure_message(where).is_false()
			if not hit.is_empty():
				var floor_y := (hit["position"] as Vector3).y
				assert_float(floor_y).override_failure_message(where).is_equal_approx(
					at.y, SPAWN_FLOOR_M
				)
	# The blast's box (its two corners, in the air) stands inside too.
	assert_int(layout.count(&"engine_aboard")).is_equal(2)
	for at: Vector3 in layout.positions(&"engine_aboard"):
		var flat := Vector2(at.x - MIDDLE.x, at.z - MIDDLE.z)
		assert_float(flat.length()).override_failure_message(str(at)).is_less(radius - 1.0)


func test_the_boundary_closes_the_clearing_all_round() -> void:
	var level := LevelWorld.build(MAP)
	var radius := _boundary_radius()
	for step: int in 144:
		var angle := TAU * step / 144.0
		var out := Vector3(sin(angle), 0, cos(angle))
		for height: float in [0.3, 1.0, 1.8, 6.0]:
			# From outside the ship's outline (its corners about 17 m out): the wall's inner face, a chord,
			# lies at radius_m and at most 1 % further between two walls' middles.
			var from := MIDDLE + out * (radius - 12.0) + Vector3.UP * height
			var ray := PhysicsRayQueryParameters3D.create(from, from + out * 15.0)
			var hit := level.space_state().intersect_ray(ray)
			var where := "%.1f degrees, %.1f m up" % [rad_to_deg(angle), height]
			assert_bool(hit.is_empty()).override_failure_message(where).is_false()
			if not hit.is_empty():
				var at := (hit["position"] as Vector3) - MIDDLE
				var far := Vector2(at.x, at.z).length()
				assert_float(far).override_failure_message(where).is_between(
					radius - 0.05, radius * 1.01
				)
	# Nothing of it shows: the walls have no mesh.
	var scene: Node = auto_free((load(MAP) as PackedScene).instantiate())
	var boundary := scene.get_node(^"Boundary")
	assert_array(boundary.find_children("*", "VisualInstance3D", true, false)).is_empty()


func test_the_map_is_the_ship_on_its_clearing_in_fog_and_no_estate_lot() -> void:
	var scene: Node = auto_free((load(MAP) as PackedScene).instantiate())
	var names: Array[String] = []
	for child: Node in scene.get_children():
		names.append(String(child.name))
	assert_array(names).contains_exactly_in_any_order(
		["Ground", "Ship", "Boundary", "Sky", "Markers", "DeadHall"]
	)
	for piece: String in ["Ship", "Ground", "Boundary"]:
		var placed := (scene.get_node(NodePath(piece)) as Node3D).position
		assert_vector(placed).override_failure_message(piece).is_equal(MIDDLE)
	var sky := scene.get_node(^"Sky") as WorldEnvironment
	assert_bool(sky.environment.fog_enabled).is_true()
	assert_float(sky.environment.fog_density).is_greater(0.0)
	# The fog fades into the sky's colour, so its far edge shows no line.
	assert_that(sky.environment.fog_light_color).is_equal(sky.environment.background_color)


func _base_mode() -> GameMode:
	return load(BASE_MODE) as GameMode


## The boundary's inner radius (its piece's `radius_m`).
func _boundary_radius() -> float:
	var scene := load("res://levels/clearing/rooms/boundary.tscn") as PackedScene
	var boundary: Node = auto_free(scene.instantiate())
	return boundary.get_meta(&"radius_m") as float


func _read(mode: GameMode) -> MarkerReader.Read:
	var world := HostWorldQuery.new(
		mode.player_rules.capsule_radius_m, mode.player_rules.crouch_height_m
	)
	world.add_level(LevelWorld.build(MAP))
	world.use_level(MAP)
	return MarkerReader.read_scene(MAP, world, MarkerReader.floor_tags_of(mode))
