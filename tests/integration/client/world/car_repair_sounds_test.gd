extends GdUnitTestSuite
## The car repair's sounds (#811, the car repair ADR's RD14 (a); SoundChooser, WorldSounds,
## StationHums): LiftChanged going down crashes at the car of that panel, in the round only (the
## phase end's stop lowers the car without a kill, RE4: no crash then; the host sends that stop's
## LiftChanged before its PhaseChanged, so WorldSounds holds a crash to the next physics frame and
## drops it once the model has left the round); PartFitted plays the task's success at the car
## (#1341); FitChanged is silent everywhere and nothing sounds at the panel for a fit (RE16); each
## within the hearing range. WorldSounds plays the crash on a generated placeholder and the success
## on SfxSet's file, and the lift's motor hums at the car while it rises, keyed by the panel, until
## it is fully up or let go.

const F := preload("res://tests/fixtures/client/fixture_car_repair_client.gd")
const RANGE := SoundChooser.HEARING_RANGE_M
const CAR_AT := FixtureCarRepairModes.CAR_AT
const PANEL_AT := FixtureCarRepairModes.PANEL_AT

var _mode: GameMode
var _model: ClientModel
var _world: Node3D


func before_test() -> void:
	AudioBuses.ensure()
	_mode = FixtureCarRepairModes.basic()
	_model = F.dealt(_mode)
	_world = Node3D.new()
	add_child(_world)


func after_test() -> void:
	_world.free()


func test_the_lift_coming_down_crashes_at_the_car() -> void:
	assert_object(_choose(&"LiftChanged", _lift(true, 10), CAR_AT)).is_null()
	var sound := _choose(&"LiftChanged", _lift(false, 20), CAR_AT)
	assert_str(String(sound.id)).is_equal(String(SoundChooser.LIFT_CRASH))
	assert_that(sound.position).is_equal(CAR_AT)
	assert_that(sound.aim).is_equal(CAR_AT + Vector3.UP * SoundChooser.CAR_AIM_M)
	var far := CAR_AT + Vector3(RANGE + 1.0, 0, 0)
	assert_object(_choose(&"LiftChanged", _lift(false, 30), far)).is_null()


func test_the_phase_end_s_stop_makes_no_crash() -> void:
	# The host's order: Match stops the channels (the hold's LiftChanged down), then enters the
	# next phase (its PhaseChanged), both in one batch of events.
	var sounds := _sounds()
	_deliver(sounds, &"LiftChanged", _lift(true, 10))
	_deliver(sounds, &"LiftChanged", _lift(false, 20))
	var phase := PhaseChangedEvent.new(&"end", 2000)
	_deliver(sounds, phase.event_name(), phase.to_dict())
	await _physics_frames()
	assert_int(sounds.played()).is_equal(0)


func test_a_let_go_in_the_round_crashes_at_the_next_physics_frame() -> void:
	var sounds := _sounds()
	_deliver(sounds, &"LiftChanged", _lift(true, 10))
	_deliver(sounds, &"LiftChanged", _lift(false, 20))
	assert_int(sounds.played()).is_equal(0)
	await _physics_frames()
	assert_int(sounds.played()).is_equal(1)
	await _physics_frames()
	assert_int(sounds.played()).is_equal(1)


func test_a_part_fitted_sounds_at_the_car_and_a_fit_starting_is_silent() -> void:
	var fit := {"station": F.CAR, "fitter": F.OTHER, "tick": 50}
	assert_object(_choose(&"FitChanged", fit, CAR_AT)).is_null()
	assert_object(_choose(&"FitChanged", fit, PANEL_AT)).is_null()
	F.hold(_model, 40, &"spark_plug", F.OTHER)
	var sound := _choose(&"PartFitted", {"station": F.CAR, "item": 40}, PANEL_AT)
	assert_str(String(sound.id)).is_equal(String(SfxSet.TASK_SUCCESS))
	assert_that(sound.position).is_equal(CAR_AT)
	assert_that(sound.aim).is_equal(CAR_AT + Vector3.UP * SoundChooser.CAR_AIM_M)
	assert_bool(sound.position.is_equal_approx(PANEL_AT)).is_false()


func test_world_sounds_plays_the_crash_on_its_placeholder_and_the_fit_on_the_success() -> void:
	var sounds := _sounds()
	_deliver(sounds, &"LiftChanged", _lift(false, 20))
	F.hold(_model, 40, &"spark_plug", F.OTHER)
	_deliver(sounds, &"PartFitted", {"station": F.CAR, "item": 40})
	await _physics_frames()
	assert_int(sounds.played()).is_equal(2)
	var started := sounds.find_children("*", "AudioStreamPlayer3D", false, false)
	assert_int(started.size()).is_equal(2)
	# The fit plays at once; the crash waits for the next physics frame (held).
	var fit := started[0] as AudioStreamPlayer3D
	var crash := started[1] as AudioStreamPlayer3D
	assert_object(fit.stream).is_same(sounds.sfx.stream_for(SfxSet.TASK_SUCCESS))
	assert_object(crash.stream).is_instanceof(AudioStreamWAV)
	for player: AudioStreamPlayer3D in [fit, crash]:
		assert_float(player.max_distance).is_equal(RANGE)


func test_the_placeholder_exists() -> void:
	var blip := WorldSounds.station_blip(SoundChooser.LIFT_CRASH)
	assert_int(blip.data.size()).is_greater(0)
	assert_int(blip.loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)


func test_the_motor_hums_at_the_car_while_it_rises() -> void:
	var now := [100]
	var hums := StationHums.new()
	hums.model = _model
	hums.mode = _mode
	hums.ears = func() -> Variant: return CAR_AT + Vector3(0, 1.5, 3)
	hums.host_tick = func() -> int: return now[0] as int
	_world.add_child(hums)
	await _frames()
	assert_int(hums.hums()).is_equal(0)
	F.lift(_model, true, 100)
	await _frames()
	assert_int(hums.hums()).is_equal(1)
	var motor := hums.hum_of(F.PANEL)
	assert_that(motor.position).is_equal(CAR_AT)
	assert_float(motor.pitch_scale).is_equal_approx(StationHums.MOTOR_PITCH, 1e-6)
	now[0] = 100 + FixtureCarRepairModes.type_of(_mode).rise_ticks()
	await _frames()
	assert_int(hums.hums()).is_equal(0)
	F.lift(_model, true, now[0] as int)
	await _frames()
	assert_int(hums.hums()).is_equal(1)
	F.lift(_model, false, now[0] as int)
	await _frames()
	assert_int(hums.hums()).is_equal(0)


func _lift(up: bool, tick: int) -> Dictionary:
	return {"station": F.PANEL, "up": up, "tick": tick}


func _choose(event_name: StringName, fields: Dictionary, listener: Vector3) -> SoundChooser.Sound:
	_model.fold(event_name, fields)
	return SoundChooser.choose(event_name, fields, _model, _nobody, listener, RANGE, 0.0, _mode)


func _nobody(_peer: int) -> Variant:
	return null


## A WorldSounds hearing at the car, in the test's world (freed with it).
func _sounds() -> WorldSounds:
	var sounds := WorldSounds.new()
	sounds.model = _model
	sounds.mode = _mode
	sounds.listener = func() -> Variant: return CAR_AT
	_world.add_child(sounds)
	return sounds


## `event_name` folded into the model, then heard by `sounds`, as ClientSession emits it.
func _deliver(sounds: WorldSounds, event_name: StringName, fields: Dictionary) -> void:
	_model.fold(event_name, fields)
	sounds.on_event(event_name, fields)


func _physics_frames() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _frames() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
