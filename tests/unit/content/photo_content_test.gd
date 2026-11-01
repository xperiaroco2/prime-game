extends GdUnitTestSuite
## The photo task in `content/` (ARCHITECTURE §9.5.22; the photo ADR's P5, #784): Photography
## with §6.1's words (PD8) and PD9's placeholder numbers, its five station kinds and their rules,
## the film and photo item kinds, in the shipped base mode on House alone (PD14, GE15), its
## `photos` setting (1 to 5, default 3), `tasks` at every type a map plays (GD7 (i)), Round
## accepting `Interact` from the living, the House's fit with the photo task and the greybox's
## without it. Every map is read as the host reads it, in its own collision world
## (HostWorldQuery.for_mode), as `generator_content_test.gd` reads House. Like the mode check, this
## test loads `content/` on purpose (§9.6).

const BASE_MODE := "res://content/modes/base_mode.tres"
const GREYBOX := "res://levels/greybox/greybox.tscn"
const HOUSE := "res://levels/house/house.tscn"


func test_the_photo_task_has_the_adrs_words_and_numbers() -> void:
	var photo := _photo(_mode())
	assert_object(photo).is_not_null()
	if photo == null:
		return
	# §6.1's drafts, which the engineer took as drafted (PD8).
	assert_str(photo.id).is_equal("photo")
	assert_str(photo.display_name).is_equal("Photography")
	assert_str(photo.description).is_equal(
		(
			"Load a film into the camera, photograph a player on the spot, print the film, and"
			+ " hang the photos on the board: each one with a person in it counts."
		)
	)
	# #687's five frames; PD9's placeholders, "not a decision": 50° vertical, 4:3, 10 m.
	assert_int(photo.frames_per_film).is_equal(5)
	assert_float(photo.fov_deg).is_equal(50.0)
	assert_float(photo.aspect).is_equal_approx(4.0 / 3.0, 0.0001)
	assert_float(photo.range_m).is_equal(10.0)
	assert_array(Array(photo.maps)).is_equal([HOUSE])
	assert_str(photo.subtasks_setting).is_equal("photos")


func test_the_five_station_kinds_have_their_tags_and_placeholder_sizes() -> void:
	var photo := _photo(_mode())
	var kinds: Array[StationKind] = [
		photo.camera, photo.photo_spot, photo.film_box, photo.printer, photo.board
	]
	var ids: Array[String] = []
	for kind: StationKind in kinds:
		ids.append(String(kind.id))
		# The spawn tags P4's station scenes carry (`spawn_<id>`).
		assert_str(kind.spawn_tag).override_failure_message(kind.id).is_equal(kind.id)
		# PD9: 2 m and 2 m for every station, as the Generator's GD6.
		assert_float(kind.radius_m).override_failure_message(kind.id).is_equal(2.0)
		assert_float(kind.height_m).override_failure_message(kind.id).is_equal(2.0)
		assert_bool(kind.display).override_failure_message(kind.id).is_equal(
			kind == photo.photo_spot
		)
	assert_array(ids).is_equal(["camera", "photo_spot", "film_box", "printer", "photo_board"])
	# The photo spot is the aim, a display kind with no rule.
	assert_array(photo.photo_spot.actions).is_empty()


func test_the_camera_printer_and_board_each_take_one_interact_rule() -> void:
	var photo := _photo(_mode())
	for kind: StationKind in [photo.camera, photo.printer, photo.board]:
		assert_array(_conditions(kind)).override_failure_message(kind.id).is_equal(
			["HandNotTwoHanded", "AtStation", "StationInSight", "StationUsable"]
		)


func test_the_box_pays_its_own_cooldown_and_minds_no_busy_hands() -> void:
	var photo := _photo(_mode())
	# A take is a take (CD3 (b)): no HandNotTwoHanded. StationUsable is the mode check's for every
	# UseStation rule: the box's `unavailable` at the film cap with none loose.
	assert_array(_conditions(photo.film_box)).is_equal(
		["AtStation", "StationInSight", "StationUsable", "Cooldown"]
	)
	var cooldown := photo.film_box.actions[0].conditions[-1] as Cooldown
	assert_str(cooldown.key).is_equal("photo_take")
	# PD9: 0.25 s, the engineer's CD17 answer for cooking's sources; a placeholder.
	assert_float(cooldown.seconds).is_equal(0.25)


func test_the_film_and_photo_kinds_are_one_handed_capped_and_declared() -> void:
	var mode := _mode()
	var photo := _photo(mode)
	var expected := {&"film": ["Film", 32], &"photo": ["Photo", 64]}
	for kind: ItemKind in [photo.film, photo.photo]:
		var want: Array = expected[kind.id]
		assert_str(kind.display_name).is_equal(want[0])
		assert_str(kind.spawn_tag).is_equal(String(kind.id))
		assert_int(kind.hands).override_failure_message(kind.id).is_equal(1)
		# PE10's placeholders, "not a decision"; nothing vanishes on a timer.
		assert_int(kind.max_items).override_failure_message(kind.id).is_equal(want[1])
		assert_int(kind.vanish_seconds).override_failure_message(kind.id).is_equal(0)
		assert_object(mode.find_item_kind(kind.id)).is_same(kind)


func test_the_photos_setting_and_every_type_in_every_match() -> void:
	var mode := _mode()
	var photos := mode.find_setting(&"photos")
	assert_object(photos).is_not_null()
	if photos == null:
		return
	assert_bool(photos.is_number()).is_true()
	# PD9's placeholder, "not a decision": 1 to 5 photos (one film's worth at most), default 3.
	assert_array([photos.default_value, photos.min_value, photos.max_value]).is_equal([3, 1, 5])
	# §6.1's label (PD8).
	assert_str(photos.display_name).is_equal("Photos (Photography)")
	# `tasks` (GD7 (i)): every type that plays on the map, every match: the House's five (Delivery,
	# the Generator, the photo task, Cooking and car repair); the greybox deals its Delivery by
	# colours alone.
	var tasks := mode.find_setting(&"tasks")
	var most := 0
	for path: String in mode.maps:
		most = maxi(most, DealTasks.pool_of(mode, PackedStringArray(), path).size())
	assert_int(most).is_equal(5)
	assert_int(tasks.max_value).is_equal(most)
	# Its default deals every type of the default map: the estate's one ship's engine, the M8
	# slice's (#1496); the House's matches set `tasks` to its five.
	assert_int(tasks.default_value).is_equal(
		DealTasks.pool_of(mode, PackedStringArray(), mode.default_map()).size()
	)
	var on_house: Array[StringName] = []
	for type: TaskType in DealTasks.pool_of(mode, PackedStringArray(), HOUSE):
		on_house.append(type.id)
	assert_array(on_house).contains([&"photo"])
	var on_greybox: Array[StringName] = []
	for type: TaskType in DealTasks.pool_of(mode, PackedStringArray(), GREYBOX):
		on_greybox.append(type.id)
	assert_array(on_greybox).is_equal([&"colour_delivery"])
	assert_array(ModeCheck.run(mode).errors).is_empty()


func test_round_accepts_interact_from_the_living() -> void:
	var froms: Array[int] = []
	for accept: AcceptSpec in _mode().find_phase(&"round").accepts:
		if accept.intent == &"Interact":
			froms.append(accept.from)
	assert_array(froms).is_equal([AcceptSpec.From.LIVING])


func test_the_house_fits_the_photo_task_and_the_greybox_is_asked_for_none() -> void:
	var mode := _mode()
	var photo := _photo(mode)
	var layouts := _layouts(mode)
	var tags: Array[StringName] = [
		photo.camera.spawn_tag,
		photo.photo_spot.spawn_tag,
		photo.film_box.spawn_tag,
		photo.printer.spawn_tag,
		photo.board.spawn_tag,
		photo.film.spawn_tag,
		photo.photo.spawn_tag,
	]
	var settings := mode.default_settings()
	settings[&"photos"] = mode.find_setting(&"photos").max_value
	for path: String in mode.maps:
		var map := layouts[path]
		var demands := LayoutCheck.demands_of(
			mode, PhaseSpec.Level.MAP, settings, mode.max_players, {}, path
		)
		assert_array(Array(demands.shortfalls(map))).override_failure_message(path).is_empty()
		var on_house := path == HOUSE
		for tag: StringName in tags:
			var where := "%s: %s" % [path, tag]
			assert_int(demands.markers.get(tag, 0) as int).override_failure_message(where).is_equal(
				1 if on_house else 0
			)
			assert_bool(demands.exact.has(tag)).override_failure_message(where).is_equal(on_house)
			assert_int(map.count(tag)).override_failure_message(where).is_equal(
				1 if on_house else 0
			)
	# PE12's fit: the photo spot beyond the camera's reach on the House.
	assert_array(photo.layout_problems(layouts[HOUSE])).is_empty()
	assert_array(Array(LayoutCheck.run(mode, layouts))).is_empty()


## The global class names of the conditions of `kind`'s one rule, which is an Interact ending in
## UseStation alone.
func _conditions(kind: StationKind) -> Array[String]:
	var found: Array[String] = []
	assert_int(kind.actions.size()).override_failure_message(kind.id).is_equal(1)
	if kind.actions.size() != 1:
		return found
	var rule := kind.actions[0]
	assert_str(rule.trigger).override_failure_message(kind.id).is_equal("Interact")
	assert_int(rule.effects.size()).override_failure_message(kind.id).is_equal(1)
	assert_object(rule.effects[0]).override_failure_message(kind.id).is_instanceof(UseStation)
	for condition: Condition in rule.conditions:
		found.append((condition.get_script() as Script).get_global_name())
	return found


func _mode() -> GameMode:
	return load(BASE_MODE) as GameMode


func _photo(mode: GameMode) -> PhotoTask:
	for type: TaskType in mode.task_types:
		if type is PhotoTask:
			return type as PhotoTask
	return null


## The layouts of the mode's levels as the host reads them, each in its own collision world
## (HostWorldQuery.for_mode): the scenarios' flat fake would read House's storeys as one floor
## (#681).
func _layouts(mode: GameMode) -> Dictionary[String, LevelLayout]:
	var world := HostWorldQuery.for_mode(mode)
	assert_array(Array(world.errors)).is_empty()
	var levels := MarkerReader.read_levels(mode, world)
	assert_array(Array(levels.errors)).is_empty()
	return levels.layouts
