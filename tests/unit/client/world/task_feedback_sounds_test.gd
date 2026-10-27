extends GdUnitTestSuite
## Every task's success and error (#1341, ARCHITECTURE §4.7.60; SoundChooser, WorldSounds): a done
## subtask plays SfxSet.TASK_SUCCESS and a miss by the task's own rules SfxSet.TASK_ERROR, at the
## station of the event, only within the hearing range. A delivery at its circle or drop-off, a
## zone or the generator done (a done ZoneProgress; one still filling is silent); both silent when
## done at the deal, outside the play phase. WorldSounds plays them on SfxSet's files, the
## engineer's U2 and P1, on the Effects bus with the range as max_distance. Cooking's serve and
## burnt patty, the car repair's fit and the photo's hang are in their own sounds tests.

const C := preload("res://tests/fixtures/client/fixture_cooking_client.gd")
const RANGE := SoundChooser.HEARING_RANGE_M
const CIRCLE := 4
const ZONE := 5
const GENERATOR := 6
const PACKAGE := 30
const CIRCLE_AT := Vector3(3, 0, -2)
const ZONE_AT := Vector3(-4, 0, 1)
const GENERATOR_AT := Vector3(0, 0, 6)

var _model: ClientModel


func before_test() -> void:
	# The base mode's phases (its deal runs at loading -> pregame, as content's), its round the play
	# phase whose clock runs, as content's.
	var mode := FixtureBaseMode.mode()
	mode.find_phase(&"round").clock_runs = true
	_model = ClientModel.new(mode)
	_phase(&"round")
	_station(CIRCLE, &"circle", CIRCLE_AT)
	_station(ZONE, &"zone", ZONE_AT)
	_station(GENERATOR, &"generator", GENERATOR_AT)
	_model.fold(&"ItemSpawned", {"item": PACKAGE, "kind": &"package", "position": CIRCLE_AT})


func test_a_done_subtask_and_a_miss_each_pick_the_right_id() -> void:
	var done := _choose(&"PackageDelivered", _delivered(), Vector3.ZERO)
	assert_str(String(done.id)).is_equal(String(SfxSet.TASK_SUCCESS))
	# A miss by a task's own rules: Cooking's wrong burger served (#1101: checked only at a serve).
	var cooking := FixtureCookingModes.basic(2)
	var kitchen := C.dealt(2, cooking)
	var at := FixtureCookingModes.ORDER_BOARD_AT
	var fields := {"station": C.FIRST_PLACE, "right": false}
	kitchen.fold(&"BurgerServed", fields)
	var miss := SoundChooser.choose(
		&"BurgerServed", fields, kitchen, _nobody, at, RANGE, 0.0, cooking
	)
	assert_str(String(miss.id)).is_equal(String(SfxSet.TASK_ERROR))
	assert_str(String(SfxSet.TASK_SUCCESS)).is_not_equal(String(SfxSet.TASK_ERROR))


func test_a_delivery_plays_the_success_at_its_circle_within_the_range() -> void:
	var sound := _choose(&"PackageDelivered", _delivered(), Vector3.ZERO)
	assert_that(sound.position).is_equal(CIRCLE_AT)
	assert_that(sound.aim).is_equal(CIRCLE_AT + Vector3.UP * SoundChooser.DELIVERY_AIM_M)
	var edge := CIRCLE_AT + Vector3(RANGE, 0, 0)
	assert_object(_choose(&"PackageDelivered", _delivered(), edge)).is_not_null()
	var far := CIRCLE_AT + Vector3(RANGE + 0.01, 0, 0)
	assert_object(_choose(&"PackageDelivered", _delivered(), far)).is_null()
	# A circle the model never placed makes no sound.
	var unknown := {"item": PACKAGE, "station": 42}
	assert_object(_choose(&"PackageDelivered", unknown, Vector3.ZERO)).is_null()


func test_a_zone_or_the_charge_plays_the_success_only_when_done() -> void:
	for station: int in [ZONE, GENERATOR]:
		var at := ZONE_AT if station == ZONE else GENERATOR_AT
		var filling := _choose(&"ZoneProgress", _progress(station, 40, 100, true), at)
		assert_object(filling).is_null()
		var stopped := _choose(&"ZoneProgress", _progress(station, 40, 100, false), at)
		assert_object(stopped).is_null()
		var done := _choose(&"ZoneProgress", _progress(station, 100, 100, false), at)
		assert_str(String(done.id)).is_equal(String(SfxSet.TASK_SUCCESS))
		assert_that(done.position).is_equal(at)
		assert_that(done.aim).is_equal(at + Vector3.UP * SoundChooser.ZONE_AIM_M)
		var far := at + Vector3(0, 0, RANGE + 0.01)
		assert_object(_choose(&"ZoneProgress", _progress(station, 100, 100, false), far)).is_null()
	# Nothing needed is nothing done; an unknown station is silent.
	assert_object(_choose(&"ZoneProgress", _progress(ZONE, 0, 0, false), ZONE_AT)).is_null()
	assert_object(_choose(&"ZoneProgress", _progress(42, 100, 100, false), ZONE_AT)).is_null()


func test_a_delivery_or_a_charge_done_at_the_deal_is_silent() -> void:
	# The deal runs before the play phase: a package spawned in its circle, a generator dealt with
	# no switch (GE9) is done there, by nobody.
	_phase(&"pregame")
	assert_object(_choose(&"PackageDelivered", _delivered(), CIRCLE_AT)).is_null()
	var full := _progress(GENERATOR, 100, 100, false)
	assert_object(_choose(&"ZoneProgress", full, GENERATOR_AT)).is_null()
	_phase(&"round")
	assert_object(_choose(&"PackageDelivered", _delivered(), CIRCLE_AT)).is_not_null()
	assert_object(_choose(&"ZoneProgress", full, GENERATOR_AT)).is_not_null()


func test_world_sounds_plays_the_task_s_files_on_the_effects_bus() -> void:
	AudioBuses.ensure()
	var sounds: WorldSounds = auto_free(WorldSounds.new())
	add_child(sounds)
	sounds.model = _model
	sounds.listener = func() -> Variant: return Vector3.ZERO
	sounds.on_event(&"PackageDelivered", _delivered())
	sounds.on_event(&"ZoneProgress", _progress(ZONE, 100, 100, false))
	assert_int(sounds.played()).is_equal(2)
	var started := sounds.find_children("*", "AudioStreamPlayer3D", false, false)
	assert_int(started.size()).is_equal(2)
	var success := sounds.sfx.stream_for(SfxSet.TASK_SUCCESS)
	assert_object(success).is_not_null()
	assert_int(success.streams_count).is_equal(1)
	for i: int in 2:
		var played := started[i] as AudioStreamPlayer3D
		assert_object(played.stream).is_same(success)
		assert_str(String(played.bus)).is_equal(String(AudioBuses.EFFECTS))
		assert_float(played.max_distance).is_equal(RANGE)
	assert_that((started[0] as AudioStreamPlayer3D).position).is_equal(CIRCLE_AT)
	assert_that((started[1] as AudioStreamPlayer3D).position).is_equal(ZONE_AT)
	# The error has its own file.
	var error := sounds.sfx.stream_for(SfxSet.TASK_ERROR)
	assert_object(error).is_not_null()
	assert_object(error).is_not_same(success)


func _delivered() -> Dictionary:
	return {"item": PACKAGE, "station": CIRCLE}


func _progress(station: int, ticks: int, needed: int, counting: bool) -> Dictionary:
	return {"station": station, "ticks": ticks, "needed": needed, "counting": counting, "tick": 900}


func _phase(id: StringName) -> void:
	_model.fold(&"PhaseChanged", PhaseChangedEvent.new(id, 1000).to_dict())


func _station(id: int, kind: StringName, at: Vector3) -> void:
	_model.fold(
		&"StationPlaced", {"station": id, "kind": kind, "colour": Color.WHITE, "position": at}
	)


func _nobody(_peer: int) -> Variant:
	return null


func _choose(event_name: StringName, fields: Dictionary, listener: Vector3) -> SoundChooser.Sound:
	_model.fold(event_name, fields)
	return SoundChooser.choose(event_name, fields, _model, _nobody, listener, RANGE)
