extends GdUnitTestSuite
## The ship engine's sounds through SoundChooser and WorldSounds (#1501; ARCHITECTURE §4.7.64):
## ShipEngineViews' cue (ShipEngineSounds.EVENT) plays its own id at its place, cut at the hearing
## range, the blast and the roar at their farther one; a KnockedDown in play by a tripped breaker
## still off is its zap there, any other knockdown silent; WorldSounds plays each on its SfxSet file
## on the Effects bus with its range as max_distance; ItemWorld hands ShipEngineViews' cues to its
## WorldSounds.

const BASE_MODE := "res://content/modes/base_mode.tres"
const BOARD := 3
const BREAKER := 5
const BREAKER_AT := Vector3(6.0, 0.0, -0.2)
const AT := Vector3(1.0, 1.0, 1.0)

var _mode: GameMode
var _model: ClientModel


func before_test() -> void:
	_mode = load(BASE_MODE) as GameMode
	_model = ClientModel.new(_mode)
	_phase(&"round")
	_model.fold(&"StationPlaced", _placed(BOARD, &"breaker_board", BREAKER_AT + Vector3.RIGHT))
	_model.fold(&"StationPlaced", _placed(BREAKER, &"breaker", BREAKER_AT))


func test_each_cue_plays_its_id_where_it_says() -> void:
	for id: StringName in [
		SfxSet.ENGINE_CALL,
		SfxSet.ENGINE_BEEP,
		SfxSet.ENGINE_WAIL,
		SfxSet.ENGINE_BLAST,
		SfxSet.ENGINE_ROAR
	]:
		var sound := _choose(ShipEngineSounds.EVENT, ShipEngineSounds.cue(id, AT), Vector3.ZERO)
		assert_object(sound).is_not_null()
		assert_str(String(sound.id)).is_equal(String(id))
		assert_that(sound.position).is_equal(AT)


func test_the_blast_and_the_roar_carry_farther_than_the_rest() -> void:
	var far := Vector3(SoundChooser.HEARING_RANGE_M + 5.0, 1.0, 1.0)
	for id: StringName in [SfxSet.ENGINE_BLAST, SfxSet.ENGINE_ROAR]:
		(
			assert_object(_choose(ShipEngineSounds.EVENT, ShipEngineSounds.cue(id, AT), far))
			. is_not_null()
		)
		var beyond := Vector3(ShipEngineSounds.FAR_RANGE_M + 2.0, 1.0, 1.0)
		(
			assert_object(_choose(ShipEngineSounds.EVENT, ShipEngineSounds.cue(id, AT), beyond))
			. is_null()
		)
	for id: StringName in [SfxSet.ENGINE_CALL, SfxSet.ENGINE_BEEP, SfxSet.ENGINE_WAIL]:
		assert_object(_choose(ShipEngineSounds.EVENT, ShipEngineSounds.cue(id, AT), far)).is_null()


func test_a_knockdown_by_a_tripped_breaker_zaps_there_and_any_other_is_silent() -> void:
	var by_breaker := {"peer": 2, "position": BREAKER_AT + Vector3(0.0, 0.0, 1.0)}
	assert_object(_choose(&"KnockedDown", by_breaker, Vector3.ZERO)).is_null()
	_model.fold(
		&"EngineProblemOpened",
		{"problem": 1, "stations": PackedInt32Array([BOARD]), "deadline": 900}
	)
	_model.fold(
		&"BreakerChain",
		{"problem": 1, "breakers": PackedInt32Array([BREAKER]), "next": 0, "since": -1}
	)
	var zap := _choose(&"KnockedDown", by_breaker, Vector3.ZERO)
	assert_object(zap).is_not_null()
	assert_str(String(zap.id)).is_equal(String(SfxSet.ENGINE_ZAP))
	assert_that(zap.position).is_equal(BREAKER_AT)
	# Far from the listener: cut like every world sound.
	var far := BREAKER_AT + Vector3(SoundChooser.HEARING_RANGE_M + 1.0, 0.0, 0.0)
	assert_object(_choose(&"KnockedDown", by_breaker, far)).is_null()
	# Outside the play phase: silent.
	_phase(&"end")
	assert_object(_choose(&"KnockedDown", by_breaker, Vector3.ZERO)).is_null()


func test_world_sounds_plays_each_engine_file_on_effects_with_its_range() -> void:
	AudioBuses.ensure()
	var sounds: WorldSounds = auto_free(WorldSounds.new())
	add_child(sounds)
	sounds.model = _model
	sounds.listener = func() -> Variant: return Vector3.ZERO
	var ids: Array[StringName] = [
		SfxSet.ENGINE_CALL,
		SfxSet.ENGINE_BEEP,
		SfxSet.ENGINE_WAIL,
		SfxSet.ENGINE_BLAST,
		SfxSet.ENGINE_ROAR
	]
	for id: StringName in ids:
		sounds.on_event(ShipEngineSounds.EVENT, ShipEngineSounds.cue(id, AT))
	var started := sounds.find_children("*", "AudioStreamPlayer3D", false, false)
	assert_int(started.size()).is_equal(ids.size())
	for i in ids.size():
		var played := started[i] as AudioStreamPlayer3D
		var stream := sounds.sfx.stream_for(ids[i])
		assert_object(stream).is_not_null()
		assert_object(played.stream).is_same(stream)
		assert_str(String(played.bus)).is_equal(String(AudioBuses.EFFECTS))
		assert_float(played.max_distance).is_equal(ShipEngineSounds.range_of(ids[i]))
		assert_that(played.position).is_equal(AT)


func test_item_world_hands_the_engine_views_cues_to_its_world_sounds() -> void:
	var world: ItemWorld = auto_free(ItemWorld.new())
	add_child(world)
	var views := world.task_views.get(ShipEngine) as ShipEngineViews
	assert_object(views).is_not_null()
	assert_bool(views.sound_due.is_connected(world.sounds.on_event)).is_true()


func _choose(event_name: StringName, fields: Dictionary, listener: Vector3) -> SoundChooser.Sound:
	_model.fold(event_name, fields)
	return SoundChooser.choose(
		event_name,
		fields,
		_model,
		func(_peer: int) -> Variant: return null,
		listener,
		SoundChooser.HEARING_RANGE_M,
		0.0,
		_mode
	)


func _phase(id: StringName) -> void:
	_model.fold(&"PhaseChanged", PhaseChangedEvent.new(id, 1000).to_dict())


func _placed(id: int, kind: StringName, at: Vector3) -> Dictionary:
	return {"station": id, "kind": kind, "colour": Color.WHITE, "position": at}
