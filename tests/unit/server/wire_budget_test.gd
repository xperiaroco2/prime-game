extends GdUnitTestSuite
## WireBudget (ARCHITECTURE §4.3, E16): every mode in content/ fits the wire, content with the
## longest ids and paths fits or is refused before the encoder would refuse an event, and a mode
## at the wire's maxima is refused with the kinds named.

const MODES_FOLDER := "res://content/modes/"
const ID_32 := "abcdefghijklmnopqrstuvwxyz_01234"


func test_every_mode_in_content_fits_the_wire() -> void:
	var checked := 0
	for file: String in DirAccess.get_files_at(MODES_FOLDER):
		if not file.ends_with(".tres"):
			continue
		var mode := load(MODES_FOLDER + file) as GameMode
		assert_object(mode).override_failure_message(file).is_not_null()
		assert_array(Array(WireBudget.check(mode))).override_failure_message(file).is_empty()
		checked += 1
	assert_int(checked).is_greater(0)


func test_the_base_mode_has_a_worst_case_of_every_content_sized_kind() -> void:
	var mode := load(MODES_FOLDER + "base_mode.tres") as GameMode
	var named: Array[StringName] = []
	for message: WireMessage in WireBudget.worst_cases(mode):
		named.append(message.name)
	var sized: Array[StringName] = []
	for each: WireRow in WireSchema.game(false).rows():
		if each.content_sized:
			sized.append(each.name)
	assert_array(named).contains_exactly_in_any_order(sized)


func test_the_longest_ids_and_paths_fit_where_the_counts_are_modest() -> void:
	var mode := _mode(10, 3, 1, 4)
	assert_array(Array(WireBudget.check(mode))).is_empty()
	var schema := WireSchema.game(false)
	for message: WireMessage in WireBudget.worst_cases(mode):
		var encoded := schema.write(message)
		assert_str(encoded.problem).override_failure_message(str(message.name)).is_empty()
		assert_int(encoded.payload.size()).is_less_equal(schema.row_named(message.name).cap)
	var welcome := schema.write(WireBudget.worst_cases(mode)[0])
	assert_int(welcome.payload.size()).is_greater(1000)


func test_a_mode_at_the_wires_maxima_is_refused_with_the_kinds_named() -> void:
	var mode := _mode(WireSchema.MAX_PLAYERS, 16, 16, WireSchema.MAX_TASK_TYPES)
	var problems := "\n".join(WireBudget.check(mode))
	assert_str(problems).contains("SettingsChanged (kind 37): ")
	assert_str(problems).contains("ChangeSettings (kind 3): ")
	assert_str(problems).contains("over its cap of 8192")
	assert_str(problems).not_contains("LoadMatch")
	assert_str(problems).not_contains("PlayersPlaced")
	# Welcome's cap is 8192 since #1404 (the hall's items): the 16-setting mode above now fits under
	# it, so the assertion that Welcome goes over it runs on a mode with the most whole-number
	# settings, 32 (its rows of a 32-character kind beside 16 players' longest names).
	var most_numbers := _mode(WireSchema.MAX_PLAYERS, WireSchema.MAX_ENTRIES, 0, 1)
	var welcome_problems := "\n".join(WireBudget.check(most_numbers))
	assert_str(welcome_problems).contains("Welcome (kind 33): ")
	assert_str(welcome_problems).contains("bytes, over its cap of 8192")


func test_more_players_than_the_wire_carries_is_refused() -> void:
	var problems := "\n".join(WireBudget.check(_mode(WireSchema.MAX_PLAYERS + 1, 1, 0, 1)))
	assert_str(problems).contains("PlayersPlaced (kind 40): ")
	assert_str(problems).contains("Teammates (kind 45): ")
	assert_str(problems).contains("entries, at most 16")


func test_demanded_tags_and_station_kinds_size_the_settings_and_the_stations() -> void:
	var mode := _demanding(_mode(10, 3, 1, 4), 3, 2)
	assert_array(Array(WireBudget.check(mode))).is_empty()
	var found := {}
	for message: WireMessage in WireBudget.worst_cases(mode):
		found[message.name] = message
	assert_bool(found.has(&"StationPlaced")).is_true()
	var placed: WireMessage = found[&"StationPlaced"]
	assert_str(str(placed.fields["kind"])).is_equal(_id(100))
	var changed: WireMessage = found[&"SettingsChanged"]
	assert_int((changed.fields["shortfalls"] as Array).size()).is_equal(3 + 2 + 2)
	# The three tags and two palettes are sized as the text Demands makes (one subject, `need` and
	# `have`), the other two as the longest host text.
	var texts: Array = changed.fields["shortfalls"]
	for i: int in 5:
		var text: Dictionary = texts[i]
		assert_int((text["ids"] as PackedStringArray).size()).is_equal(1)
		assert_int((text["numbers"] as Dictionary).size()).is_equal(2)
	assert_int(((texts[5] as Dictionary)["numbers"] as Dictionary).size()).is_equal(
		WireSchema.MAX_TEXT_NUMBERS
	)
	assert_int((changed.fields["needed_markers"] as Dictionary).size()).is_equal(3)
	assert_int((changed.fields["needed_colours"] as Dictionary).size()).is_equal(2)


func test_a_demanded_text_is_sized_by_the_modes_own_tags_and_the_demand_ids() -> void:
	# #810: the text Demands.shortfalls makes holds one of its three ids, one demanded tag or
	# palette station kind of the mode, and `need` and `have`: the longest of each, never an id the
	# content does not have (the House's 36 demanded tags with the car repair fit SettingsChanged).
	var mode := _demanding(_mode(10, 3, 1, 4), 0, 0)
	var row := mode.transitions[mode.transitions.size() - 1]
	for tag: StringName in [&"spot", &"a_longer_tag", &"short"]:
		row.actions.append(FixtureDemand.of(tag, mode.settings[0].id))
	var changed: WireMessage = null
	for message: WireMessage in WireBudget.worst_cases(mode):
		if message.name == &"SettingsChanged":
			changed = message
	assert_object(changed).is_not_null()
	if changed == null:
		return
	var text: Dictionary = (changed.fields["shortfalls"] as Array)[0]
	assert_str(str(text["id"])).is_equal(String(HostText.MARKERS_EXACT))
	assert_array(Array(text["ids"] as PackedStringArray)).is_equal(["a_longer_tag"])
	assert_array((text["numbers"] as Dictionary).keys()).is_equal([&"need", &"have"])


func test_a_demanded_text_is_sized_by_a_palette_kind_longer_than_every_tag() -> void:
	# #810's test review: a demanded palette's station kind is a subject of the text Demands makes
	# (`colours`), so a mode whose palette kind is longer than every demanded tag sizes its
	# shortfalls by that kind, or the encoder could refuse its real SettingsChanged at runtime.
	var mode := _demanding(_mode(10, 3, 1, 4), 0, 0)
	var row := mode.transitions[mode.transitions.size() - 1]
	var kind := StationKind.new()
	kind.id = &"a_long_palette_station_kind"
	row.actions.append(FixtureDemand.of(&"spot", mode.settings[0].id, kind))
	var changed: WireMessage = null
	for message: WireMessage in WireBudget.worst_cases(mode):
		if message.name == &"SettingsChanged":
			changed = message
	assert_object(changed).is_not_null()
	if changed == null:
		return
	var text: Dictionary = (changed.fields["shortfalls"] as Array)[0]
	assert_array(Array(text["ids"] as PackedStringArray)).is_equal(["a_long_palette_station_kind"])


## Thirty demanded tags and thirty demanded palettes make 62 shortfalls, under the list's cap of
## MAX_SHORTFALLS (64), so only the payload's byte cap can refuse them: the test holds that reason,
## not the entry count (#775's review).
func test_demanded_texts_over_the_byte_cap_refuse_the_settings_but_not_the_stations() -> void:
	var mode := _demanding(_mode(10, 3, 1, 4), 30, 30)
	var problems := "\n".join(WireBudget.check(mode))
	var changed: WireMessage = null
	for message: WireMessage in WireBudget.worst_cases(mode):
		if message.name == &"SettingsChanged":
			changed = message
	assert_object(changed).is_not_null()
	if changed != null:
		var shortfalls: Array = changed.fields["shortfalls"]
		assert_int(shortfalls.size()).is_less_equal(WireSchema.MAX_SHORTFALLS)
	assert_str(problems).contains("SettingsChanged (kind 37): ")
	assert_str(problems).contains("over its cap of 8192")
	assert_str(problems).not_contains("entries, at most")
	assert_str(problems).not_contains("StationPlaced")
	assert_str(problems).not_contains("ItemSpawned")


func test_an_id_outside_the_wire_alphabet_is_refused() -> void:
	var mode := _mode(4, 1, 0, 1)
	mode.roles[0].id = &"Crew"
	assert_str("\n".join(WireBudget.check(mode))).contains("Teammates (kind 45): role")


## WireBudget counts every shortfall as the longest host text the wire takes (#548): the longest
## FitCheck and Demands make (32-character ids, the largest counts, a 255-byte map path) must be
## a host text the encoder takes, one per tag and station kind plus two, or the encoder would
## refuse SettingsChanged in a lobby.
func test_the_longest_shortfall_of_each_kind_is_a_host_text_the_wire_takes() -> void:
	var mode := _mode(WireSchema.MAX_PLAYERS, 1, 0, 1)
	mode.min_players = WireSchema.MAX_PLAYERS
	var no_layouts: Dictionary[String, LevelLayout] = {}
	var game := Match.new(mode, 1, FlatWorldQuery.new(), no_layouts)
	game.state.map = mode.maps[0]
	var needed := Demands.new(null)
	for i: int in WireSchema.MAX_PLAYERS:
		needed.markers[StringName(_id(i))] = WireField.S32_MAX
		needed.colours[StringName(_id(i))] = WireField.S32_MAX
		needed.palettes[StringName(_id(i))] = WireField.S32_MIN
	var ctx := MatchContext.new(game)
	ctx.state = game.state
	ctx.mode = mode
	var found := FitCheck.shortfalls(ctx, needed)
	(
		assert_array(found.map(func(text: HostText) -> StringName: return text.id))
		. is_equal([HostText.PLAYERS_FEW, HostText.NO_LAYOUT])
	)
	var demanded := needed.shortfalls(LevelLayout.new(mode.maps[0]))
	found.append_array(demanded)
	assert_int(found.size()).is_equal(needed.markers.size() + needed.colours.size() + 2)
	# What WireBudget sizes a demanded tag or palette as (_demanded_text): one subject and the
	# two arguments `need` and `have`.
	assert_int(demanded.size()).is_equal(needed.markers.size() + needed.colours.size())
	for text: HostText in demanded:
		assert_int(text.ids.size()).override_failure_message(str(text)).is_equal(1)
		(
			assert_array(text.numbers.keys())
			. override_failure_message(str(text))
			. contains_exactly_in_any_order([&"need", &"have"])
		)
	var schema := WireSchema.game(false)
	var fields: Dictionary = {}
	for message: WireMessage in WireBudget.worst_cases(mode):
		if message.name == &"SettingsChanged":
			fields = message.fields
	for text: HostText in found:
		var one: Array[Dictionary] = [text.to_dict()]
		fields["shortfalls"] = one
		var encoded := schema.write(WireMessage.new(&"SettingsChanged", fields))
		assert_str(encoded.problem).override_failure_message(str(text)).is_empty()
		assert_int(text.ids.size()).is_less_equal(WireSchema.MAX_TEXT_IDS)
		assert_int(text.numbers.size()).is_less_equal(WireSchema.MAX_TEXT_NUMBERS)


## A mode whose every id is 32 characters and whose map path is 255 bytes: `players` at most,
## `numbers` whole-number settings, `sets` sets of task types and `types` task types.
func _mode(players: int, numbers: int, sets: int, types: int) -> GameMode:
	var mode := GameMode.new()
	mode.min_players = 1
	mode.max_players = players
	for i: int in numbers:
		mode.settings.append(_setting("n%s" % _id(i).substr(1), SettingSpec.Kind.NUMBER))
	for i: int in sets:
		mode.settings.append(_setting("s%s" % _id(i).substr(1), SettingSpec.Kind.TASK_TYPES))
	for i: int in types:
		var type := TaskType.new()
		type.id = StringName(_id(i))
		type.description = "A task."
		mode.task_types.append(type)
	var role := GameRole.new()
	role.id = StringName(ID_32)
	mode.roles.append(role)
	var kind := ItemKind.new()
	kind.id = StringName(ID_32)
	kind.hands = 1
	mode.item_kinds.append(kind)
	var phase := PhaseSpec.new()
	phase.id = StringName(ID_32)
	mode.phases.append(phase)
	mode.maps = PackedStringArray(["res://" + "m".repeat(WireField.PATH_MAX - 6)])
	return mode


func _setting(id: String, kind: SettingSpec.Kind) -> SettingSpec:
	var setting := SettingSpec.new()
	setting.id = StringName(id)
	setting.kind = kind
	return setting


## A distinct 32-character id per number.
func _id(number: int) -> String:
	var suffix := str(number)
	return ID_32.substr(0, 32 - suffix.length()) + suffix


## `mode` with one row into a map phase whose actions demand `tags` spawn tags and `stations`
## station kinds (each on the first tag), every id 32 characters (station kinds from _id(100)).
func _demanding(mode: GameMode, tags: int, stations: int) -> GameMode:
	var phase: PhaseSpec = mode.phases[0]
	phase.level = PhaseSpec.Level.MAP
	var row := Transition.new()
	row.to = phase.id
	var setting: StringName = mode.settings[0].id
	for i: int in tags:
		row.actions.append(FixtureDemand.of(StringName(_id(i)), setting))
	for i: int in stations:
		var kind := StationKind.new()
		kind.id = StringName(_id(100 + i))
		row.actions.append(FixtureDemand.of(StringName(_id(0)), setting, kind))
	mode.transitions.append(row)
	return mode


func test_station_ids_come_from_the_task_types_kinds_not_from_the_palettes() -> void:
	# The longest station id belongs to a kind no action demands a palette of: the wire still
	# carries it in a StationPlaced (DE4, #827).
	var mode := _mode(10, 3, 1, 1)
	var kind := FixtureKindsType.kind(StringName(_id(100)), &"spot")
	mode.task_types = [FixtureKindsType.of(&"kinds", [kind])]
	var found := {}
	for message: WireMessage in WireBudget.worst_cases(mode):
		found[message.name] = message
	assert_bool(found.has(&"StationPlaced")).is_true()
	var placed: WireMessage = found[&"StationPlaced"]
	assert_str(str(placed.fields["kind"])).is_equal(_id(100))
	assert_array(Array(WireBudget.check(mode))).is_empty()


func test_herbs_dealt_carries_the_cooking_herbs_and_a_mode_without_cooking_none() -> void:
	var mode := _mode(10, 3, 1, 1)
	var cases := {}
	for message: WireMessage in WireBudget.worst_cases(mode):
		cases[message.name] = message
	var empty: WireMessage = cases[&"HerbsDealt"]
	assert_array(Array(empty.fields["code"] as PackedStringArray)).is_empty()
	mode.task_types.append(_cooking(5))
	assert_array(Array(WireBudget.check(mode))).is_empty()
	for message: WireMessage in WireBudget.worst_cases(mode):
		cases[message.name] = message
	var herbs: WireMessage = cases[&"HerbsDealt"]
	assert_int((herbs.fields["code"] as PackedStringArray).size()).is_equal(5)
	assert_int((herbs.fields["beds"] as PackedStringArray).size()).is_equal(5)
	assert_str((herbs.fields["code"] as PackedStringArray)[4]).is_equal(_id(204))


func test_too_many_long_herbs_are_refused() -> void:
	var mode := _mode(10, 3, 1, 1)
	mode.task_types.append(_cooking(40))
	assert_str("\n".join(WireBudget.check(mode))).contains("HerbsDealt (kind 74): ")


## A Cooking whose `count` herbs have 32-character ids (from _id(200)).
func _cooking(count: int) -> Cooking:
	var type := Cooking.new()
	type.id = &"cooking"
	for i: int in count:
		var herb := ItemKind.new()
		herb.id = StringName(_id(200 + i))
		herb.hands = 1
		type.herbs.append(herb)
	return type


## A task type's own layout problems (TaskType.most_layout_problems, #807) are shortfalls too:
## SettingsChanged is sized with them, one more per problem the type may report.
func test_a_task_types_layout_problems_size_the_settings_shortfalls() -> void:
	var mode := _mode(10, 3, 1, 1)
	var type := FixtureKindsType.of(&"kinds", [])
	type.layout_problems_count = 3
	mode.task_types = [type]
	var changed: WireMessage = null
	for message: WireMessage in WireBudget.worst_cases(mode):
		if message.name == &"SettingsChanged":
			changed = message
	assert_object(changed).is_not_null()
	assert_int((changed.fields["shortfalls"] as Array).size()).is_equal(2 + 3)


## The longest short_axis text (two 32-character tags, need and have at the largest) is a host text
## the encoder takes, within MAX_TEXT_IDS and MAX_TEXT_NUMBERS.
func test_the_longest_short_axis_text_is_a_host_text_the_wire_takes() -> void:
	var mode := _mode(WireSchema.MAX_PLAYERS, 1, 0, 1)
	var text := HostText.of(
		HostText.SHORT_AXIS,
		PackedStringArray([ID_32, ID_32]),
		{&"need": WireField.S32_MAX, &"have": WireField.S32_MAX}
	)
	var fields: Dictionary = {}
	for message: WireMessage in WireBudget.worst_cases(mode):
		if message.name == &"SettingsChanged":
			fields = message.fields
	var one: Array[Dictionary] = [text.to_dict()]
	fields["shortfalls"] = one
	var encoded := WireSchema.game(false).write(WireMessage.new(&"SettingsChanged", fields))
	assert_str(encoded.problem).is_empty()
	assert_int(text.ids.size()).is_less_equal(WireSchema.MAX_TEXT_IDS)
	assert_int(text.numbers.size()).is_less_equal(WireSchema.MAX_TEXT_NUMBERS)


func test_world_toggle_kinds_size_the_station_ids_but_never_the_colour_maps() -> void:
	# A PlaceToggles kind demands no colour (#1295: no demand), so it never reaches SettingsChanged's
	# needed_colours or palettes, capped at MAX_ENTRIES: the estate's eight toggle kinds pushed the
	# base mode's worst case to 38 entries and refused every host (#1459). Its id still rides a
	# StationPlaced.
	var mode := _mode(10, 3, 1, 1)
	var kinds: Array[StationKind] = []
	for i: int in WireSchema.MAX_ENTRIES:
		kinds.append(FixtureKindsType.kind(StringName(_id(100 + i)), &"spot"))
	mode.task_types = [FixtureKindsType.of(&"kinds", kinds)]
	var placing := PlaceToggles.new()
	placing.kinds = [FixtureToggles.kind(StringName(_id(200)), &"cover")]
	var row := Transition.new()
	row.actions = [placing]
	mode.transitions = [row]
	var found := {}
	for message: WireMessage in WireBudget.worst_cases(mode):
		found[message.name] = message
	var changed: WireMessage = found[&"SettingsChanged"]
	(
		assert_bool((changed.fields["needed_colours"] as Dictionary).has(StringName(_id(200))))
		. is_false()
	)
	assert_int((changed.fields["palettes"] as Dictionary).size()).is_equal(WireSchema.MAX_ENTRIES)
	assert_array(Array(WireBudget.check(mode))).is_empty()


func test_station_kinds_with_no_demanded_palette_add_no_shortfall() -> void:
	# Demands.shortfalls names a station kind only for a demanded palette (`colours`): kinds that
	# demand none (the photo task's five, #784) size the station ids, never the shortfalls.
	var mode := _mode(10, 3, 1, 1)
	var kinds: Array[StationKind] = []
	for i: int in WireSchema.MAX_ENTRIES - 1:
		kinds.append(FixtureKindsType.kind(StringName(_id(100 + i)), &"spot"))
	mode.task_types = [FixtureKindsType.of(&"kinds", kinds)]
	var changed: WireMessage = null
	for message: WireMessage in WireBudget.worst_cases(mode):
		if message.name == &"SettingsChanged":
			changed = message
	assert_int((changed.fields["shortfalls"] as Array).size()).is_equal(2)
	assert_array(Array(WireBudget.check(mode))).is_empty()


## A joiner's Welcome carries the hall's items (#1404): the base mode's worst case holds the most
## rows of its longest item kind, and they fit the row's cap.
func test_the_base_mode_s_welcome_holds_the_most_items_under_its_cap() -> void:
	var mode := load(MODES_FOLDER + "base_mode.tres") as GameMode
	var welcome: WireMessage = null
	for message: WireMessage in WireBudget.worst_cases(mode):
		if message.name == &"Welcome":
			welcome = message
	assert_object(welcome).is_not_null()
	if welcome == null:
		return
	var items: Array = welcome.fields["items"]
	assert_int(items.size()).is_equal(WelcomeEvent.MAX_ITEMS)
	var schema := WireSchema.game(false)
	var encoded := schema.write(welcome)
	assert_str(encoded.problem).is_empty()
	assert_int(encoded.payload.size()).is_greater(2048)
	assert_int(encoded.payload.size()).is_less_equal(schema.row_named(&"Welcome").cap)
