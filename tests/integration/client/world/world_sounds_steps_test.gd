extends GdUnitTestSuite
## WorldSounds' footsteps (#525; ARCHITECTURE §4.7.43) in a small physics world: another player
## steps from how its interpolated pose moves, whatever velocity its snapshots claim; within the
## hearing range only, casting no ray beyond it; muffled behind a wall, clear in the open; not
## while downed or dead, nor off the floor; the floor's tag picks the surface. The local player
## steps from its own movement, never muffled (no ray), and not while downed. Anywhere (#792, #991,
## KD1 (b)), a step at the crouch walk's speed is quieter and heard nearer, eased to a walk's at the
## fast crouch's speed, by the speed and never the flag.

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


func test_the_local_player_steps_on_stairs_where_the_floor_flag_flickers() -> void:
	# Climbing a stair's edge is_on_floor() is false for frames at a time; the cadence must not
	# restart each time (code review).
	_world.add_stairs(30)
	var player := _world.add_player(Vector3(0, 0, 0))
	_sounds.player = player
	await _world.frames(10)
	player.move_input = Vector2(0, 1)
	var off_floor := 0
	for i: int in 120:
		await get_tree().physics_frame
		if not player.is_on_floor():
			off_floor += 1
	assert_float(player.global_position.y).is_greater(3.0)
	assert_int(off_floor).is_greater(0)
	assert_int(_sounds.steps()).is_greater_equal(3)


func test_a_step_at_crouch_speed_is_quieter_and_heard_nearer() -> void:
	# A little below crouch_speed_mps, off the edge of the measured step speed.
	var slow := Vector3.LEFT * _views.rules.crouch_speed_mps * 0.9
	await _walk(Vector3(3, 0, -2), slow, Vector3.ZERO, 150, false, true)
	assert_int(_sounds.steps()).is_greater(0)
	var step := _last()
	assert_str(step["bus"] as String).is_equal(String(AudioBuses.EFFECTS))
	assert_float(step["volume_db"] as float).is_equal_approx(FootstepCadence.QUIET_STEP_DB, 0.05)
	assert_float(step["max_distance"] as float).is_equal_approx(
		FootstepCadence.QUIET_STEP_RANGE_M, 0.05
	)


func test_a_step_at_the_fast_crouch_speed_is_a_walks() -> void:
	# #991 (KD1 (b) changed): a peer drawn crouched at crouch_fast_speed_mps (Shift while crouched)
	# sounds like a walk; it was wholly quiet before.
	var fast := Vector3.LEFT * _views.rules.crouch_fast_speed_mps
	await _walk(Vector3(3, 0, -2), fast, Vector3.ZERO, 150, false, true)
	assert_int(_sounds.steps()).is_greater(0)
	var step := _last()
	assert_float(step["volume_db"] as float).is_equal_approx(0.0, 0.15)
	assert_float(step["max_distance"] as float).is_equal_approx(SoundChooser.HEARING_RANGE_M, 0.3)


func test_a_step_at_walk_speed_is_todays_whatever_the_flag() -> void:
	# Read from the speed, never the flag: a peer drawn crouched that moves at the walk speed.
	var walk := Vector3.LEFT * _views.rules.walk_speed_mps
	await _walk(Vector3(3, 0, -2), walk, Vector3.ZERO, 120, false, true)
	assert_int(_sounds.steps()).is_greater(0)
	var step := _last()
	assert_float(step["volume_db"] as float).is_equal(0.0)
	assert_float(step["max_distance"] as float).is_equal(SoundChooser.HEARING_RANGE_M)


func test_a_step_between_the_crouch_speeds_eases() -> void:
	var rules := _views.rules
	var between := lerpf(rules.crouch_speed_mps, rules.crouch_fast_speed_mps, 0.5)
	await _walk(Vector3(4, 0, -2), Vector3.LEFT * between, Vector3.ZERO, 150)
	assert_int(_sounds.steps()).is_greater(0)
	var step := _last()
	var half_db := FootstepCadence.QUIET_STEP_DB / 2.0
	assert_float(step["volume_db"] as float).is_equal_approx(half_db, 0.3)
	var half_m := (SoundChooser.HEARING_RANGE_M + FootstepCadence.QUIET_STEP_RANGE_M) / 2.0
	assert_float(step["max_distance"] as float).is_equal_approx(half_m, 0.6)


func test_a_sneaker_at_the_crouch_walks_speed_is_silent() -> void:
	# #990: the relayed sneak bit and an honest sneak at exactly crouch_speed_mps, near the ears:
	# no step at all, whatever the interpolated pose's jitter.
	var sneak := Vector3.LEFT * _views.rules.crouch_speed_mps
	await _walk(Vector3(3, 0, -2), sneak, Vector3.ZERO, 150, false, false, true)
	assert_bool((_views.body_of(PEER) as RemotePlayerBody).is_sneaking()).is_true()
	assert_int(_sounds.steps()).is_equal(0)
	assert_int(_sounds.played()).is_equal(0)


func test_a_claimed_sneak_above_the_crouch_walks_speed_is_heard() -> void:
	# A modified client claiming the sneak at the fast crouch's or the walk's speed: heard as today.
	var rules := _views.rules
	await _walk(
		Vector3(3, 0, -2),
		Vector3.LEFT * rules.crouch_fast_speed_mps,
		Vector3.ZERO,
		150,
		false,
		false,
		true
	)
	assert_int(_sounds.steps()).is_greater(0)
	assert_float(_last()["volume_db"] as float).is_equal_approx(0.0, 0.15)
	_started.clear()
	await _walk(
		Vector3(3, 0, -2),
		Vector3.LEFT * rules.walk_speed_mps,
		Vector3.ZERO,
		120,
		false,
		false,
		true
	)
	assert_bool(_started.is_empty()).is_false()
	assert_float(_last()["volume_db"] as float).is_equal(0.0)


func test_a_slow_step_without_the_sneak_bit_is_the_quiet_step() -> void:
	var slow := Vector3.LEFT * _views.rules.crouch_speed_mps
	await _walk(Vector3(3, 0, -2), slow, Vector3.ZERO, 150)
	assert_int(_sounds.steps()).is_greater(0)
	assert_float(_last()["volume_db"] as float).is_less(-3.0)


func test_the_local_player_sneaking_is_silent() -> void:
	var player := _world.add_player(Vector3(0, 0, 0))
	_sounds.player = player
	await _world.frames(10)
	player.sneak_held = true
	player.move_input = Vector2(0, 1)
	await _world.frames(150)
	assert_bool(player.is_sneaking()).is_true()
	assert_int(_sounds.steps()).is_equal(0)
	# Let go: a walk's steps.
	player.sneak_held = false
	await _world.frames(60)
	assert_int(_sounds.steps()).is_greater(0)


func test_a_quiet_step_beyond_its_range_is_cut_where_a_walks_is_heard() -> void:
	var rules := _views.rules
	var far := FootstepCadence.QUIET_STEP_RANGE_M + 1.5
	await _walk(
		Vector3(-2, 0, -far), Vector3.RIGHT * rules.crouch_speed_mps * 0.9, Vector3.ZERO, 150
	)
	assert_object(_views.body_of(PEER)).is_not_null()
	assert_int(_sounds.played()).is_equal(0)
	assert_int(_sounds.rays()).is_equal(0)
	await _walk(Vector3(-2, 0, -far), Vector3.RIGHT * rules.walk_speed_mps, Vector3.ZERO, 120)
	assert_int(_sounds.steps()).is_greater(0)


func test_the_local_players_slow_steps_are_quiet_too() -> void:
	# 0.4 of the stick: 0.4 of the walk speed (1.8 m/s), below the crouch walk's (#991; half the
	# stick, 2.25 m/s, was below the fast crouch's before).
	var player := _world.add_player(Vector3(0, 0, 0))
	_sounds.player = player
	await _world.frames(10)
	player.move_input = Vector2(0, 0.4)
	await _world.frames(150)
	assert_int(_sounds.steps()).is_greater(0)
	var step := _last()
	assert_float(step["volume_db"] as float).is_equal_approx(FootstepCadence.QUIET_STEP_DB, 0.05)
	assert_float(step["max_distance"] as float).is_equal_approx(
		FootstepCadence.QUIET_STEP_RANGE_M, 0.05
	)


## PEER's snapshots for `frames` physics frames, one a tick: from `from` moving at `velocity`
## (m/s), each claiming `claimed`; `downed`, `crouched` and `sneaking` as the snapshot says.
func _walk(
	from: Vector3,
	velocity: Vector3,
	claimed: Vector3,
	frames: int,
	downed := false,
	crouched := false,
	sneaking := false,
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
				"crouched": crouched,
				"sneaking": sneaking,
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
