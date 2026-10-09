extends GdUnitTestSuite
## WorldSounds' footsteps (#525; ARCHITECTURE §4.7.38) in a small physics world: another player
## steps from how its interpolated pose moves, whatever velocity its snapshots claim; within the
## hearing range only, casting no ray beyond it; muffled behind a wall, clear in the open; not
## while downed or dead, nor off the floor; the floor's tag picks the surface. The local player
## steps from its own movement, never muffled (no ray), and not while downed.

const PlayerTestWorld := preload("res://tests/integration/client/player/player_test_world.gd")
const PEER := 2
const EARS := Vector3(0, 1.5, 0)
const FRAME_USEC := 16667
const TICK_USEC := 50000

var _world: PlayerTestWorld
var _model: ClientModel
var _views: AvatarViews
var _sounds: WorldSounds
var _now := 1000000
var _tick := 0
var _started: Array[Dictionary] = []


func before_test() -> void:
	AudioBuses.ensure()
	_world = PlayerTestWorld.new()
	add_child(_world)
	_model = ClientModel.new(FixtureBaseMode.mode())
	_model.own_peer = 1
	_views = AvatarViews.new()
	_views.model = _model
	_views.buffer = SnapshotBuffer.new()
	_views.rules = FixtureModes.player_rules()
	_views.clock = func() -> int: return _now
	_world.add_child(_views)
	_sounds = WorldSounds.new()
	_sounds.model = _model
	_sounds.avatars = _views
	_sounds.listener = func() -> Variant: return EARS
	_sounds.child_entered_tree.connect(_on_started)
	_world.add_child(_sounds)


func after_test() -> void:
	_world.free()


func test_a_walker_steps_from_its_poses_not_its_claimed_velocity() -> void:
	# Its snapshots claim it stands (velocity zero) while it walks 2 s at walk speed.
	await _walk(Vector3(3, 0, -2), Vector3.LEFT * _views.rules.walk_speed_mps, Vector3.ZERO, 120)
	# Two seconds at walk speed: about one step per WALK_INTERVAL_S (the first comes later, as the
	# poses lag the snapshots by the interpolation delay).
	assert_int(_sounds.steps()).is_between(2, 5)
	assert_int(_sounds.rays()).is_equal(_sounds.steps())
	assert_int(_sounds.muffled()).is_equal(0)
	var step := _last()
	assert_str(step["bus"] as String).is_equal(String(AudioBuses.EFFECTS))
	assert_float(step["volume_db"] as float).is_equal(0.0)
	assert_float(step["max_distance"] as float).is_equal(SoundChooser.HEARING_RANGE_M)
	assert_float((step["position"] as Vector3).y).is_equal_approx(0.0, 0.01)
	var concrete := _sounds.sfx.stream_for(SfxSet.footstep(FootstepSurface.DEFAULT))
	assert_object(step["stream"] as AudioStream).is_same(concrete)


func test_a_claimed_run_standing_still_makes_no_step() -> void:
	await _walk(Vector3(3, 0, -2), Vector3.ZERO, Vector3.LEFT * 7.0, 120)
	assert_object(_views.body_of(PEER)).is_not_null()
	assert_int(_sounds.steps()).is_equal(0)


func test_a_walker_beyond_the_range_makes_no_sound_and_casts_no_ray() -> void:
	var far := SoundChooser.HEARING_RANGE_M + 3.0
	await _walk(Vector3(0, 0, -far), Vector3.RIGHT * _views.rules.walk_speed_mps, Vector3.ZERO, 90)
	assert_object(_views.body_of(PEER)).is_not_null()
	assert_int(_sounds.played()).is_equal(0)
	assert_int(_sounds.rays()).is_equal(0)


func test_a_walker_behind_a_wall_steps_muffled() -> void:
	_world.add_box(Vector3(0, 1.5, -2), Vector3(12, 3, 0.2))
	await _walk(Vector3(3, 0, -4), Vector3.LEFT * _views.rules.walk_speed_mps, Vector3.ZERO, 120)
	assert_int(_sounds.steps()).is_greater(0)
	assert_int(_sounds.muffled()).is_equal(_sounds.steps())
	var step := _last()
	assert_str(step["bus"] as String).is_equal(String(AudioBuses.EFFECTS_MUFFLED))
	assert_float(step["volume_db"] as float).is_equal(Muffle.QUIET_DB)


func test_a_downed_or_dead_walker_makes_no_step() -> void:
	var walk := Vector3.LEFT * _views.rules.walk_speed_mps
	await _walk(Vector3(3, 0, -2), walk, Vector3.ZERO, 120, true)
	assert_object(_views.body_of(PEER)).is_not_null()
	assert_int(_sounds.steps()).is_equal(0)
	_model.lives[PEER] = ClientModel.Life.DEAD
	await _walk(Vector3(3, 0, -2), walk, Vector3.ZERO, 120)
	assert_int(_sounds.steps()).is_equal(0)


func test_a_walker_off_the_floor_makes_no_step() -> void:
	await _walk(Vector3(3, 4, -2), Vector3.LEFT * _views.rules.walk_speed_mps, Vector3.ZERO, 120)
	assert_object(_views.body_of(PEER)).is_not_null()
	assert_int(_sounds.steps()).is_equal(0)


func test_the_floors_tag_picks_the_surface() -> void:
	var floor_body := _world.find_children("*", "StaticBody3D", false, false)[0] as StaticBody3D
	floor_body.set_meta(FootstepSurface.META, &"wood")
	await _walk(Vector3(3, 0, -2), Vector3.LEFT * _views.rules.walk_speed_mps, Vector3.ZERO, 120)
	assert_int(_sounds.steps()).is_greater(0)
	var wood := _sounds.sfx.stream_for(SfxSet.footstep(&"wood"))
	assert_object(_last()["stream"] as AudioStream).is_same(wood)


func test_the_local_player_steps_never_muffled_and_not_while_downed() -> void:
	var player := _world.add_player(Vector3(0, 0, 0))
	_sounds.player = player
	await _world.frames(10)
	player.move_input = Vector2(0, 1)
	await _world.frames(120)
	assert_int(_sounds.steps()).is_between(2, 6)
	assert_int(_sounds.rays()).is_equal(0)
	assert_str(_last()["bus"] as String).is_equal(String(AudioBuses.EFFECTS))
	player.move_input = Vector2.ZERO
	await _world.frames(30)
	var standing := _sounds.steps()
	await _world.frames(60)
	assert_int(_sounds.steps()).is_equal(standing)
	player.life = ClientModel.Life.DOWNED
	player.move_input = Vector2(0, 1)
	await _world.frames(120)
	assert_int(_sounds.steps()).is_equal(standing)


## PEER's snapshots for `frames` physics frames, one a tick: from `from` moving at `velocity`
## (m/s), each claiming `claimed`; `downed` as the snapshot says.
func _walk(
	from: Vector3, velocity: Vector3, claimed: Vector3, frames: int, downed := false
) -> void:
	for i: int in frames:
		_now += FRAME_USEC
		if i % 3 == 0:
			_tick += 1
			var at := from + velocity * (i * FRAME_USEC / 1000000.0)
			var avatar := {
				"position": at,
				"velocity": claimed,
				"facing": Vector3.FORWARD,
				"downed": downed,
				"invulnerable": false,
				"held_item": -1,
			}
			var fields := {"tick": _tick, "avatars": {PEER: avatar}}
			_model.fold_snapshot(fields)
			_views.buffer.add(_tick, fields["avatars"] as Dictionary, _now)
		await get_tree().physics_frame


## What the player WorldSounds started last was set to (it frees itself when it ends).
func _last() -> Dictionary:
	assert_array(_started).is_not_empty()
	return _started.back() if not _started.is_empty() else {}


func _on_started(node: Node) -> void:
	var player := node as AudioStreamPlayer3D
	(
		_started
		. append(
			{
				"bus": String(player.bus),
				"volume_db": player.volume_db,
				"max_distance": player.max_distance,
				"position": player.position,
				"stream": player.stream,
			}
		)
	)
