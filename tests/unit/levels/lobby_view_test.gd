extends GdUnitTestSuite
## What a player sees in the lobby hall (#1520), before a round and again after End -> Lobby: the
## base mode's End -> Lobby row (ResetMatch, PlacePlayers on `lobby_player`) sets positions only,
## so each player stands on a lobby spawn looking along whatever yaw it had (a new player: -z).
## The greybox hall (#1354) had no light and no WorldEnvironment, and its near-black ship block
## (the Skat, albedo 0.1) stood 3 m in front of every spawn: under the engine's fallback ambient
## the view was black down to a band of floor, before the round as after it (playcheck end's
## lobby_after_end, #1520). The guards: the lobby as the client loads it is lit (an environment
## with ambient light, and a light), and from each lobby spawn at the eye no collider of the host's
## world stands within OPEN_M in any of HEADINGS directions.

const LOBBY := "res://levels/lobby/lobby.tscn"
const BASE_MODE := "res://content/modes/base_mode.tres"
const LOBBY_SPAWN := &"spawn_lobby_player"
## The headings checked from a spawn, evenly round the compass (the yaw a round leaves is any).
const HEADINGS := 8
## Nearer than this a body fills most of the view: the greybox ship block, 5 m tall at 3 m, ran
## from below the frame to 48 degrees up. A test bound, not a decision of the hall's layout.
const OPEN_M := 4.0

var _root: Node3D
var _mode: GameMode


func before() -> void:
	_mode = load(BASE_MODE) as GameMode


func before_test() -> void:
	_root = auto_free((load(_mode.lobby_level) as PackedScene).instantiate()) as Node3D


func test_the_base_mode_lobby_is_the_lobby_scene() -> void:
	assert_str(_mode.lobby_level).is_equal(LOBBY)


## The lobby in the tree, as GameLevel.sync loads it on every lobby phase (after End too), with
## the level script's _ready done: an environment that gives ambient light and a light that shines.
func test_the_lobby_the_client_loads_is_lit() -> void:
	add_child(_root)
	await get_tree().process_frame
	await get_tree().process_frame
	var ambient := 0
	for node: Node in _root.find_children("*", "WorldEnvironment", true, false):
		var environment := (node as WorldEnvironment).environment
		if environment == null:
			continue
		if environment.ambient_light_source == Environment.AMBIENT_SOURCE_DISABLED:
			continue
		if environment.ambient_light_energy > 0.0:
			ambient += 1
	(
		assert_int(ambient)
		. override_failure_message("no WorldEnvironment with ambient light in the lobby")
		. is_greater(0)
	)
	var lights := 0
	for node: Node in _root.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if light.is_visible_in_tree() and light.light_energy > 0.0:
			lights += 1
	assert_int(lights).override_failure_message("no light in the lobby").is_greater(0)
	remove_child(_root)


## From each lobby spawn at the standing eye, in each heading, the host's world (the colliders
## the player walks among) is clear for OPEN_M: no wall or block right in front of the camera.
func test_each_lobby_spawn_looks_into_open_hall_in_every_heading() -> void:
	var world := LevelWorld.build(LOBBY)
	assert_array(world.errors).is_empty()
	var eye := _mode.player_rules.eye_height_of(false)
	var spawns := 0
	for node: Node in _root.find_children("*", "Marker3D", true, false):
		if not node.is_in_group(LOBBY_SPAWN):
			continue
		spawns += 1
		var at := LevelWorld.transform_in_scene(node as Node3D, _root).origin + Vector3.UP * eye
		for i: int in HEADINGS:
			var ahead := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / HEADINGS)
			var ray := PhysicsRayQueryParameters3D.create(at, at + ahead * OPEN_M)
			var hit := world.space_state().intersect_ray(ray)
			var met: Vector3 = hit.get("position", at)
			var why := (
				"%s at %s: a collider %.1f m ahead toward %s"
				% [node.name, at, at.distance_to(met), ahead]
			)
			assert_bool(hit.is_empty()).override_failure_message(why).is_true()
	assert_int(spawns).is_greater_equal(_mode.max_players)
