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
	assert_str(problems).contains("Welcome (kind 33): ")
	assert_str(problems).contains("over its cap of 8192")
	assert_str(problems).not_contains("LoadMatch")
	assert_str(problems).not_contains("PlayersPlaced")


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
	assert_int((changed.fields["shortfalls"] as PackedStringArray).size()).is_equal(3 + 2 + 2)
	assert_int((changed.fields["needed_markers"] as Dictionary).size()).is_equal(3)
	assert_int((changed.fields["needed_colours"] as Dictionary).size()).is_equal(2)


func test_the_most_demanded_tags_refuse_the_settings_but_not_the_stations() -> void:
	var problems := "\n".join(WireBudget.check(_demanding(_mode(10, 3, 1, 4), 16, 16)))
	assert_str(problems).contains("SettingsChanged (kind 37): ")
	assert_str(problems).not_contains("StationPlaced")
	assert_str(problems).not_contains("ItemSpawned")


func test_an_id_outside_the_wire_alphabet_is_refused() -> void:
	var mode := _mode(4, 1, 0, 1)
	mode.roles[0].id = &"Crew"
	assert_str("\n".join(WireBudget.check(mode))).contains("Teammates (kind 45): role")


## WireBudget counts every shortfall as one full note: the longest line FitCheck and Demands write
## (32-character ids, the largest counts, a 255-byte map path) must fit NOTE_MAX, one per tag and
## station kind plus two, or the encoder would refuse SettingsChanged in a lobby.
func test_the_longest_shortfall_of_each_kind_fits_a_note() -> void:
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
	assert_int(found.size()).is_equal(2)
	assert_str(found[1]).contains(mode.maps[0])
	found.append_array(needed.shortfalls(LevelLayout.new(mode.maps[0])))
	assert_int(found.size()).is_equal(needed.markers.size() + needed.colours.size() + 2)
	for line: String in found:
		(
			assert_bool(WireField.is_printable(line, WireField.NOTE_MAX))
			. override_failure_message("%d characters: %s" % [line.length(), line])
			. is_true()
		)


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
		mode.task_types.append(type)
	var role := GameRole.new()
	role.id = StringName(ID_32)
	mode.roles.append(role)
	var kind := ItemKind.new()
	kind.id = StringName(ID_32)
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
