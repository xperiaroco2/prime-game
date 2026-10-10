extends GdUnitTestSuite
## A dead player cycling between two living targets (ARCHITECTURE §4.7, Spectating; #168), without
## the network: a LifeView over AvatarViews and ItemViews of a hand-folded ClientModel with two
## other living players. The target watched from its eyes has its meshes undrawn by the spectate
## camera, its hand item in the spectate camera's first-person hand and its item looks at its body
## hidden; the target it leaves is drawn again with its items in the next physics step.

const World := preload("res://tests/integration/client/player/player_test_world.gd")
const MODE := "res://content/modes/base_mode.tres"
const OWN := 1
const FIRST := 2
const SECOND := 3
const TICK_USEC := 50000
const SEED := 168
## FIRST's items: a knife in its hand and an item of a kind with no look on its belt; SECOND's: a
## package in both hands.
const FIRST_HAND := 10
const FIRST_BELT := 11
const SECOND_HAND := 12

var _mode: GameMode
var _model: ClientModel
var _world: Node3D
var _avatars: AvatarViews
var _items: ItemViews
var _life: LifeView
var _now := 1000000


func before_test() -> void:
	_mode = load(MODE) as GameMode
	_model = ClientModel.new(_mode)
	_model.own_peer = OWN
	for peer: int in [OWN, FIRST, SECOND]:
		var member := ClientModel.Member.new()
		member.name = "Player%d" % peer
		_model.roster[peer] = member
	_world = World.new()
	add_child(_world)
	var player := _world.call(&"add_player", Vector3(0, 0, 5)) as PlayerController
	_avatars = AvatarViews.new()
	_avatars.model = _model
	_avatars.buffer = SnapshotBuffer.new()
	_avatars.rules = _mode.player_rules
	_avatars.clock = func() -> int: return _now
	_world.add_child(_avatars)
	_items = ItemViews.new()
	_items.model = _model
	_items.mode = _mode
	_items.avatars = _avatars
	_items.player = player
	_world.add_child(_items)
	_life = LifeView.new()
	_life.model = _model
	_life.mode = _mode
	_life.avatars = _avatars
	_life.player = player
	_life.items = _items
	_life.reads_device_input = false
	_life.rng.seed = SEED
	_world.add_child(_life)


func after_test() -> void:
	_world.free()


func test_cycling_shows_the_left_target_and_its_items_again() -> void:
	_others_at({FIRST: Vector3(4, 0, 0), SECOND: Vector3(-4, 0, 0)})
	_spawn(FIRST_HAND, &"knife")
	_spawn(FIRST_BELT, &"wrench")
	_spawn(SECOND_HAND, &"package")
	_model.fold(&"ItemPickedUp", {"peer": FIRST, "item": FIRST_BELT})
	_model.fold(&"ItemPickedUp", {"peer": FIRST, "item": FIRST_HAND, "belted": FIRST_BELT})
	_model.fold(&"ItemPickedUp", {"peer": SECOND, "item": SECOND_HAND})
	_model.lives[OWN] = ClientModel.Life.DEAD
	await _drawn()
	assert_int(_life.view()).is_equal(LifeView.View.SPECTATE_EYES)
	# Whichever the seed drew first, cycle to the other one and back.
	var watched := _life.target()
	assert_array([FIRST, SECOND]).contains([watched])
	_assert_watched(watched)
	_life.cycle_target(1)
	var next := _life.target()
	assert_int(next).is_equal(SECOND if watched == FIRST else FIRST)
	await _drawn()
	_assert_watched(next)
	_life.cycle_target(-1)
	assert_int(_life.target()).is_equal(watched)
	await _drawn()
	_assert_watched(watched)


func test_only_the_players_own_switch_is_announced() -> void:
	# The tutorial's lesson 7 (#602, docs/design/tutorial.md §1): the first target drawn at the
	# death, a lost target replaced, a cycle with one candidate, a living player and reset() are no
	# switch.
	var switched: Array[int] = []
	_life.target_switched.connect(func(peer: int) -> void: switched.append(peer))
	_others_at({FIRST: Vector3(4, 0, 0), SECOND: Vector3(-4, 0, 0)})
	_model.lives[OWN] = ClientModel.Life.DEAD
	await _drawn()
	var watched := _life.target()
	assert_int(watched).is_not_equal(0)
	assert_array(switched).is_empty()
	_life.cycle_target(1)
	var next := _life.target()
	assert_int(next).is_not_equal(watched)
	assert_array(switched).is_equal([next])
	# The watched one dies: the view draws the other, by itself.
	_model.lives[next] = ClientModel.Life.DEAD
	await _drawn()
	assert_int(_life.target()).is_equal(watched)
	# One candidate left: cycling keeps it.
	_life.cycle_target(1)
	_life.cycle_target(-1)
	assert_int(_life.target()).is_equal(watched)
	_model.lives.erase(OWN)
	_life.cycle_target(1)
	_life.reset()
	assert_array(switched).is_equal([next])


## `peer` is watched from its eyes as it sees itself, and the other target is drawn as any other
## player: its body by the spectate camera, its items at its body.
func _assert_watched(peer: int) -> void:
	var other := SECOND if peer == FIRST else FIRST
	var camera := _life.spectate_camera()
	assert_bool(camera.current).is_true()
	assert_bool(_drawn_by(_avatars.body_of(peer), camera)).is_false()
	assert_bool(_drawn_by(_avatars.body_of(other), camera)).is_true()
	var hand_kind := &"knife" if peer == FIRST else &"package"
	assert_str(String(_life.spectate_hand().shown_kind())).is_equal(String(hand_kind))
	for item_id: int in _items_of(peer):
		assert_bool(_items.view_of(item_id).is_look_shown()).is_false()
	for item_id: int in _items_of(other):
		assert_bool(_items.view_of(item_id).is_look_shown()).is_true()


func _items_of(peer: int) -> Array[int]:
	if peer == FIRST:
		return [FIRST_HAND, FIRST_BELT]
	return [SECOND_HAND]


func _spawn(item: int, kind: StringName) -> void:
	_model.fold(&"ItemSpawned", {"item": item, "kind": kind, "position": Vector3.ZERO})


## Snapshots placing the other players at `at` (peer to feet), standing still and facing -Z.
func _others_at(at: Dictionary[int, Vector3]) -> void:
	for tick: int in range(1, 4):
		_now += TICK_USEC
		var avatars := {}
		for peer: int in at:
			avatars[peer] = {
				"position": at[peer],
				"velocity": Vector3.ZERO,
				"facing": Vector3.FORWARD,
				"downed": false,
				"held_item": -1,
			}
		var fields := {"tick": tick, "avatars": avatars}
		_model.fold_snapshot(fields)
		_avatars.buffer.add(tick, avatars, _now)
	_now += TICK_USEC * 10


## Whether any mesh of `body` would be drawn by `camera`: a visible mesh on a render layer of the
## camera's cull mask.
func _drawn_by(body: RemotePlayerBody, camera: Camera3D) -> bool:
	for node: Node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.is_visible_in_tree() and (mesh.layers & camera.cull_mask) != 0:
			return true
	return false


func _drawn() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
