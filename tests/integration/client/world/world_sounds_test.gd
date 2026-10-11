extends GdUnitTestSuite
## WorldSounds' occlusion (the M5 ADR §1.6 and §3 item 9, E42 (a), D13 (a); M5-7) against fixture
## boxes in its own physics space: each sound started casts exactly one ray from the ears to it;
## behind a wall it plays 8 dB quieter on the muffled Effects bus, in the open at full volume on
## Effects; a box on the LIVING or DOWNED layer (a player's capsule) muffles nothing, nor do the
## floor under a put-down package and a curb in front of it (the ray aims above the sound), while a
## wall just in front of the ears does; a sound out of range casts no ray and plays nothing.

const EARS := Vector3(0, 1.5, 0)
const WALL_AT := Vector3(0, 1.5, -1.5)
const WALL_SIZE := Vector3(4, 3, 0.2)

var _world: Node3D
var _sounds: WorldSounds


func before_test() -> void:
	AudioBuses.ensure()
	_world = Node3D.new()
	add_child(_world)
	_sounds = WorldSounds.new()
	_sounds.model = ClientModel.new(FixtureBaseMode.mode())
	_sounds.listener = func() -> Variant: return EARS
	_world.add_child(_sounds)


func after_test() -> void:
	_world.free()


func test_a_sound_behind_a_wall_plays_muffled() -> void:
	_box(WALL_AT, WALL_SIZE)
	await _physics(2)
	var sound := _put_down(Vector3(0, 1.0, -3))
	assert_int(_sounds.played()).is_equal(1)
	assert_int(_sounds.rays()).is_equal(1)
	assert_int(_sounds.muffled()).is_equal(1)
	assert_str(String(sound.bus)).is_equal(String(AudioBuses.EFFECTS_MUFFLED))
	assert_float(sound.volume_db).is_equal(Muffle.QUIET_DB)
	assert_float(sound.max_distance).is_equal(SoundChooser.HEARING_RANGE_M)


func test_a_sound_in_the_open_plays_clear() -> void:
	_box(Vector3(3, 1.5, -1.5), WALL_SIZE)
	await _physics(2)
	var sound := _put_down(Vector3(0, 1.0, -3))
	assert_int(_sounds.rays()).is_equal(1)
	assert_int(_sounds.muffled()).is_equal(0)
	assert_str(String(sound.bus)).is_equal(String(AudioBuses.EFFECTS))
	assert_float(sound.volume_db).is_equal(0.0)


func test_each_sound_casts_one_ray_and_a_capsule_muffles_none() -> void:
	_box(Vector3(0, 1.4, -2.0), Vector3(1, 1, 0.2), PhysicsLayers.LIVING)
	_box(Vector3(0, 1.4, -1.0), Vector3(1, 1, 0.2), PhysicsLayers.DOWNED)
	_box(EARS, Vector3(0.8, 1.8, 0.8), PhysicsLayers.LIVING)
	await _physics(2)
	var at := Vector3(0, 1.3, -3)
	var space := _world.get_world_3d().direct_space_state
	for mask: int in [PhysicsLayers.LIVING, PhysicsLayers.DOWNED]:
		# The line does cross them: a ray that also looked at those layers would hit.
		var query := PhysicsRayQueryParameters3D.create(EARS + Vector3(0, 0, -0.5), at, mask)
		assert_dict(space.intersect_ray(query)).is_not_empty()
	for i: int in 3:
		var sound := _put_down(at)
		assert_str(String(sound.bus)).is_equal(String(AudioBuses.EFFECTS))
	assert_int(_sounds.played()).is_equal(3)
	assert_int(_sounds.rays()).is_equal(3)
	assert_int(_sounds.muffled()).is_equal(0)


func test_the_floor_under_a_put_down_package_does_not_muffle_it() -> void:
	# The floor's top at y = 0, the package put down a little into it far off, so the line to the
	# sound itself runs into the floor more than SightHider's slack short of it: only the ray's aim
	# above the sound keeps it clear.
	_box(Vector3(0, -0.1, -5), Vector3(10, 0.2, 30))
	await _physics(2)
	var at := Vector3(0, -0.03, -10)
	assert_bool(Muffle.blocked(_world.get_world_3d().direct_space_state, EARS, at)).is_true()
	var sound := _put_down(at)
	assert_int(_sounds.rays()).is_equal(1)
	assert_int(_sounds.muffled()).is_equal(0)
	assert_str(String(sound.bus)).is_equal(String(AudioBuses.EFFECTS))


func test_a_curb_in_front_of_a_sound_on_the_floor_does_not_muffle_it() -> void:
	# A 0.15 m curb just in front of a sound on the floor 8 m off: it hides the floor point from the
	# ears, but not the sound (the ray aims above it, as at a swinger's chest).
	_box(Vector3(0, 0.075, -7.5), Vector3(4, 0.15, 0.1))
	await _physics(2)
	var at := Vector3(0, 0, -8)
	assert_bool(Muffle.blocked(_world.get_world_3d().direct_space_state, EARS, at)).is_true()
	var sound := _put_down(at)
	assert_int(_sounds.muffled()).is_equal(0)
	assert_str(String(sound.bus)).is_equal(String(AudioBuses.EFFECTS))
	assert_float(sound.volume_db).is_equal(0.0)


func test_a_wall_just_in_front_of_the_ears_muffles() -> void:
	# The ray runs from the ears to the sound: SightHider's slack is at the sound's end, so a wall
	# 5 cm in front of the ears counts.
	_box(Vector3(0, 1.5, -0.05), Vector3(4, 3, 0.02))
	await _physics(2)
	var sound := _put_down(Vector3(0, 1.0, -3))
	assert_int(_sounds.muffled()).is_equal(1)
	assert_str(String(sound.bus)).is_equal(String(AudioBuses.EFFECTS_MUFFLED))


func test_a_sound_out_of_range_casts_no_ray() -> void:
	_sounds.on_event(
		&"ItemPlaced",
		{"item": 5, "position": Vector3(0, 1, -SoundChooser.HEARING_RANGE_M - 1), "cause": &"x"}
	)
	assert_int(_sounds.played()).is_equal(0)
	assert_int(_sounds.rays()).is_equal(0)


func test_a_launch_behind_a_wall_plays_muffled_and_none_plays_beyond_the_range() -> void:
	# #645: ItemThrown's launch sound, at the thrower's eye, is cut and muffled like the others.
	_box(WALL_AT, WALL_SIZE)
	await _physics(2)
	var launch := {
		"item": 5,
		"peer": 2,
		"origin": Vector3(0, 1.6, -3),
		"velocity": Vector3(0, 4, -8),
		"gravity": Vector3(0, -9.8, 0),
		"tick": 30,
	}
	_sounds.on_event(&"ItemThrown", launch)
	assert_int(_sounds.played()).is_equal(1)
	assert_int(_sounds.rays()).is_equal(1)
	assert_int(_sounds.muffled()).is_equal(1)
	var sound := _sounds.get_child(_sounds.get_child_count() - 1) as AudioStreamPlayer3D
	assert_str(String(sound.bus)).is_equal(String(AudioBuses.EFFECTS_MUFFLED))
	assert_float(sound.max_distance).is_equal(SoundChooser.HEARING_RANGE_M)
	assert_object(sound.stream).is_not_null()
	launch["origin"] = Vector3(0, 1.6, -SoundChooser.HEARING_RANGE_M - 2)
	_sounds.on_event(&"ItemThrown", launch)
	assert_int(_sounds.played()).is_equal(1)
	assert_int(_sounds.rays()).is_equal(1)


## An ItemPlaced at `at`; returns the player it started.
func _put_down(at: Vector3) -> AudioStreamPlayer3D:
	var before := _sounds.played()
	_sounds.on_event(&"ItemPlaced", {"item": 5, "position": at, "cause": &"put_down"})
	assert_int(_sounds.played()).is_equal(before + 1)
	return _sounds.get_child(_sounds.get_child_count() - 1) as AudioStreamPlayer3D


func _box(at: Vector3, size: Vector3, layer := PhysicsLayers.WORLD) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	_world.add_child(body)


func _physics(count: int) -> void:
	for i: int in count:
		await get_tree().physics_frame
