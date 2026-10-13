extends GdUnitTestSuite
## The photo task's checks and declarations (the photo ADR's PE5, PE12, PE14, PE16; ARCHITECTURE
## §5, §9.5): ModeCheck refuses a PhotoTask without its parts, with its numbers out of bounds or its
## item kinds' caps below the floor (one below refused, at the floor accepted); both leak lists
## name every event emits() returns; use_emits() names the events a use sends; and "the shot never
## says whether a person counted" is held apart from the declarations: ShotTaken's and
## PhotoPrinted's keys and their wire rows' fields are the lists written here (#782: a photo's
## print says no more than its shot did; PhotoHung's `counted` is the public count, PE9). Fixture
## values only.


func _errors(mode: GameMode) -> String:
	return "\n".join(ModeCheck.run(mode).errors)


func test_the_fixture_modes_pass_the_mode_check() -> void:
	assert_array(Array(ModeCheck.run(FixturePhotoModes.basic()).errors)).is_empty()
	assert_array(Array(ModeCheck.run(FixturePhotoModes.winning()).errors)).is_empty()


func test_the_mode_check_refuses_a_photo_task_without_its_parts() -> void:
	var mode := FixturePhotoModes.basic()
	var type := FixturePhotoModes.type_of(mode)
	type.camera = null
	type.board = null
	type.film = null
	type.subtasks_setting = &""
	type.frames_per_film = 0
	var errors := _errors(mode)
	assert_str(errors).contains("PhotoTask photo has no camera station kind")
	assert_str(errors).contains("PhotoTask photo has no board station kind")
	assert_str(errors).contains("PhotoTask photo has no film item kind")
	assert_str(errors).contains("PhotoTask photo has no subtasks_setting")
	assert_str(errors).contains("PhotoTask photo has 0 frames_per_film, fewer than 1")


func test_the_frames_numbers_are_bounded() -> void:
	var mode := FixturePhotoModes.basic()
	var type := FixturePhotoModes.type_of(mode)
	type.fov_deg = 0.0
	type.aspect = 5.0
	type.range_m = 0.4
	var errors := _errors(mode)
	assert_str(errors).contains("PhotoTask photo fov_deg")
	assert_str(errors).contains("PhotoTask photo aspect")
	assert_str(errors).contains("PhotoTask photo range_m")
	type.fov_deg = PhotoTask.MAX_FOV_DEG
	type.aspect = PhotoTask.MIN_ASPECT
	type.range_m = PhotoTask.MAX_RANGE_M
	assert_array(Array(ModeCheck.run(mode).errors)).is_empty()


func test_the_station_kinds_need_their_rules() -> void:
	var mode := FixturePhotoModes.basic()
	var type := FixturePhotoModes.type_of(mode)
	type.photo_spot.display = false
	type.printer.actions = []
	type.film_box.actions = [FixtureStationModes.use_rule()]
	type.board.spawn_tag = &"camera"
	var errors := _errors(mode)
	assert_str(errors).contains("photo spot kind photo_spot must be a display kind with no rule")
	assert_str(errors).contains("station kind printer has no Interact rule with UseStation")
	assert_str(errors).contains("film box kind film_box pays no Cooldown")
	assert_str(errors).contains("station kinds share the spawn tag camera")


func test_the_item_kinds_must_be_the_modes_one_handed_and_apart() -> void:
	var mode := FixturePhotoModes.basic()
	var type := FixturePhotoModes.type_of(mode)
	type.film = FixturePhotoModes.item(&"film", 99)
	type.photo.hands = 2
	type.photo.spawn_tag = &"printer"
	var errors := _errors(mode)
	assert_str(errors).contains("names item kind film, which the mode does not declare")
	assert_str(errors).contains("item kind photo is two-handed")
	assert_str(errors).contains("item kind photo shares the spawn tag printer with a station kind")


func test_a_setting_below_zero_is_refused() -> void:
	var mode := FixturePhotoModes.basic()
	mode.find_setting(&"photos").min_value = -1
	assert_str(_errors(mode)).contains("setting photos goes below 0")


func test_the_item_caps_at_the_floor_pass_and_one_below_is_refused() -> void:
	var mode := FixturePhotoModes.basic()
	var type := FixturePhotoModes.type_of(mode)
	var film_floor := 2 * mode.max_players + 1
	var photo_floor := (
		2 * mode.max_players + FixturePhotoModes.MOST_PHOTOS + FixturePhotoModes.FRAMES + 1
	)
	assert_int(type.film.max_items).is_equal(film_floor)
	assert_int(type.photo.max_items).is_equal(photo_floor)
	type.film.max_items = film_floor - 1
	type.photo.max_items = photo_floor - 1
	var errors := _errors(mode)
	assert_str(errors).contains(
		"film kind film has max_items %d, below %d" % [film_floor - 1, film_floor]
	)
	assert_str(errors).contains(
		"photo kind photo has max_items %d, below %d" % [photo_floor - 1, photo_floor]
	)


func test_use_emits_names_the_events_a_use_sends() -> void:
	(
		assert_array(_names(PhotoTask.new().use_emits()))
		. is_equal(
			[
				&"FilmLoaded",
				&"ShotTaken",
				&"PhotoPrinted",
				&"PhotoHung",
				&"ItemSpawned",
				&"ItemVanished",
				&"ItemPlaced",
				&"ItemPickedUp",
				&"TaskState",
				&"TaskProgress",
			]
		)
	)


func test_both_leak_lists_name_every_event_the_photo_task_emits() -> void:
	for event_name: StringName in _names(PhotoTask.new().emits()):
		(
			assert_bool(LeakCheck.TASK_EVENTS.has(event_name))
			. override_failure_message(event_name)
			. is_true()
		)
		(
			assert_bool(ScenarioInvariants.TASK_EVENTS.has(event_name))
			. override_failure_message(event_name)
			. is_true()
		)


func test_the_shot_never_says_whether_a_person_counted() -> void:
	var row := {
		"peer": 2,
		"position": Vector3.ZERO,
		"facing": Vector3.FORWARD,
		"downed": false,
		"crouched": false,
		"held_item": -1,
		"belt_item": -1,
	}
	var rows: Array[Dictionary] = [row]
	assert_array(ShotTakenEvent.new(1, 2, 3, rows).to_dict().keys()).is_equal(
		["station", "film", "shot", "record"]
	)
	assert_array(FilmLoadedEvent.new(1, 2).to_dict().keys()).is_equal(["station", "item"])
	assert_array(PhotoPrintedEvent.new(1, 2).to_dict().keys()).is_equal(["item", "shot"])
	var schema := WireSchema.game(false)
	assert_array(_fields(schema.row_named(&"ShotTaken"))).is_equal(
		["station", "film", "shot", "record"]
	)
	assert_array(_fields(schema.row_named(&"FilmLoaded"))).is_equal(["station", "item"])
	assert_array(_fields(schema.row_named(&"PhotoPrinted"))).is_equal(["item", "shot"])


## The event names of `scripts` (each class's global name without its `Event`).
func _names(scripts: Array[Script]) -> Array[StringName]:
	var found: Array[StringName] = []
	for script: Script in scripts:
		found.append(StringName(String(script.get_global_name()).trim_suffix("Event")))
	return found


## The payload field names of `row`, in order.
func _fields(row: WireRow) -> Array[String]:
	var found: Array[String] = []
	for field: WireField in row.fields:
		if field.slot == WireField.Slot.FIELD:
			found.append(field.name)
	return found
