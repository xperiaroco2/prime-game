extends GdUnitTestSuite
## What the lobby HUD shows (client/ui/LobbyText, #495; ARCHITECTURE §4.7.42): the rows in join
## order with the host first, the status (the ready count, the players missing, the countdown from
## 5 to 1), the count against the mode's limit, the lobby's name and each row's name, in English
## and Ukrainian (the plural of `lobby.need_more` for 1, 2, 5, 11 and 21); and nothing that is not
## the whole lobby's to see.

const MODE := "res://content/modes/base_mode.tres"
const NOW := 100

var _mode: GameMode
var _locale := ""


func before() -> void:
	_mode = load(MODE) as GameMode


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")


func after_test() -> void:
	TranslationServer.set_locale(_locale)


func test_the_rows_are_the_host_first_then_the_join_order() -> void:
	# The Welcome's roster in the host's order (a later joiner may come before the host in it).
	var model := _model(3, [[7, "Taras", true], [1, "Olena", true], [3, "Ivan", false]])
	model.fold(&"PlayerJoined", {"peer": 2, "name": "Marko", "spot": Vector3.ZERO})
	var rows := LobbyText.of(model, _mode, NOW).rows
	var order: Array[int] = []
	for row in rows:
		order.append(row.peer)
	assert_array(order).is_equal([1, 7, 3, 2])
	assert_bool(rows[0].host).is_true()
	assert_bool(rows[2].own).is_true()
	assert_bool(rows[2].ready).is_false()
	assert_bool(rows[1].ready).is_true()
	assert_str(rows[3].name).is_equal("Marko")


func test_waiting_counts_the_ready_players_of_all() -> void:
	var shown := LobbyText.of(_handoff_lobby(), _mode, NOW)
	assert_int(shown.status).is_equal(LobbyText.Status.WAITING)
	assert_int(shown.count).is_equal(3)
	assert_int(shown.total).is_equal(4)
	assert_int(shown.players).is_equal(4)
	assert_int(shown.limit).is_equal(_mode.max_players)
	assert_bool(shown.own_ready).is_false()
	assert_str(LobbyText.status_text(shown)).is_equal("3 of 4 ready")
	assert_str(LobbyText.head_text(shown)).is_equal("Players 4 / 10")
	TranslationServer.set_locale("uk")
	assert_str(LobbyText.status_text(shown)).is_equal("Готові 3 з 4")
	assert_str(LobbyText.head_text(shown)).is_equal("Гравці 4 / 10")


func test_short_says_how_many_more_the_mode_needs() -> void:
	var mode := _mode.duplicate() as GameMode
	mode.min_players = 4
	var shown := LobbyText.of(_model(3, [[1, "Olena", true], [2, "Taras", true]]), mode, NOW)
	assert_int(shown.status).is_equal(LobbyText.Status.SHORT)
	assert_int(shown.count).is_equal(2)
	assert_str(LobbyText.status_text(shown)).is_equal("2 more players to start")
	# The mode's own bounds: a full lobby is not short.
	mode.min_players = 2
	assert_int(LobbyText.of(_handoff_lobby(), mode, NOW).status).is_equal(LobbyText.Status.WAITING)


func test_the_ukrainian_plurals_of_need_more_for_1_2_5_11_and_21() -> void:
	var forms: Array[String] = []
	for missing: int in [1, 2, 5, 11, 21]:
		var mode := _mode.duplicate() as GameMode
		mode.min_players = 1 + missing
		mode.max_players = maxi(mode.max_players, mode.min_players)
		TranslationServer.set_locale("uk")
		forms.append(
			LobbyText.status_text(LobbyText.of(_model(1, [[1, "Olena", false]]), mode, NOW))
		)
		TranslationServer.set_locale("en")
		var english := LobbyText.status_text(
			LobbyText.of(_model(1, [[1, "Olena", false]]), mode, NOW)
		)
		assert_str(english).is_equal(
			"%d more player%s to start" % [missing, "" if missing == 1 else "s"]
		)
	(
		assert_array(forms)
		. is_equal(
			[
				"Ще 1 гравець до старту",
				"Ще 2 гравці до старту",
				"Ще 5 гравців до старту",
				"Ще 11 гравців до старту",
				"Ще 21 гравець до старту",
			]
		)
	)


func test_the_countdown_reads_5_to_1_and_comes_before_short() -> void:
	var mode := _mode.duplicate() as GameMode
	mode.min_players = 8
	var model := _handoff_lobby()
	model.fold(&"PhaseChanged", {"phase": &"countdown", "end_tick": NOW + 5 * Ticks.RATE})
	var counted: Array[int] = []
	for second in 6:
		var shown := LobbyText.of(model, mode, NOW + second * Ticks.RATE)
		assert_int(shown.status).is_equal(LobbyText.Status.COUNTDOWN)
		counted.append(shown.count)
	assert_array(counted).is_equal([5, 4, 3, 2, 1, 1])
	var first := LobbyText.of(model, mode, NOW)
	assert_str(LobbyText.status_text(first)).is_equal("Starting in 5")
	TranslationServer.set_locale("uk")
	assert_str(LobbyText.status_text(first)).is_equal("Старт через 5")
	# No host tick known yet: no countdown.
	assert_int(LobbyText.of(model, mode, -1).status).is_not_equal(LobbyText.Status.COUNTDOWN)


func test_the_lobby_name_is_the_hosts_or_the_default_with_its_name() -> void:
	var model := _handoff_lobby()
	var shown := LobbyText.of(model, _mode, NOW)
	assert_str(LobbyText.title_text(shown)).is_equal("Olena's lobby")
	TranslationServer.set_locale("uk")
	assert_str(LobbyText.title_text(shown)).is_equal("Лобі: Olena")
	model.lobby_name = "Friday night"
	assert_str(LobbyText.title_text(LobbyText.of(model, _mode, NOW))).is_equal("Friday night")
	# No host in the roster yet: no "'s lobby".
	var hostless := _model(3, [[3, "Ivan", false]])
	assert_str(LobbyText.title_text(LobbyText.of(hostless, _mode, NOW))).is_empty()


func test_a_row_reads_you_the_host_mark_or_the_name() -> void:
	var rows := LobbyText.of(_handoff_lobby(), _mode, NOW).rows
	var texts: Array[String] = []
	for row in rows:
		texts.append(LobbyText.row_text(row))
	assert_array(texts).is_equal(["Olena · host", "Taras", "You", "Marko"])
	TranslationServer.set_locale("uk")
	assert_str(LobbyText.row_text(rows[0])).is_equal("Olena · хост")
	assert_str(LobbyText.row_text(rows[2])).is_equal("Ти")
	# The host's own row reads `player.you`, as every own row does.
	var own_host := LobbyText.of(_model(1, [[1, "Olena", false]]), _mode, NOW).rows[0]
	assert_str(LobbyText.row_text(own_host)).is_equal("Ти")


func test_a_rename_or_a_ready_changes_the_rows_value() -> void:
	var model := _handoff_lobby()
	var before := LobbyText.of(model, _mode, NOW).rows_key()
	assert_str(LobbyText.of(model, _mode, NOW + 3).rows_key()).is_equal(before)
	model.fold(&"ReadyChanged", {"peer": 3, "ready": true})
	var readied := LobbyText.of(model, _mode, NOW).rows_key()
	assert_str(readied).is_not_equal(before)
	model.roster[2].name = "Taras K"
	assert_str(LobbyText.of(model, _mode, NOW).rows_key()).is_not_equal(readied)


func test_a_role_or_teammates_known_change_nothing_shown() -> void:
	# Only what the whole lobby sees: a role or teammates a client may still hold show nowhere.
	var plain := LobbyText.of(_handoff_lobby(), _mode, NOW)
	var knowing := _handoff_lobby()
	knowing.fold(&"RoleAssigned", {"role": &"dissident"})
	knowing.fold(&"Teammates", {"role": &"dissident", "peers": PackedInt32Array([3, 4])})
	var shown := LobbyText.of(knowing, _mode, NOW)
	assert_str(shown.rows_key()).is_equal(plain.rows_key())
	assert_str(LobbyText.status_text(shown)).is_equal(LobbyText.status_text(plain))
	assert_str(LobbyText.head_text(shown)).is_equal(LobbyText.head_text(plain))
	assert_str(LobbyText.title_text(shown)).is_equal(LobbyText.title_text(plain))


## The handoff's lobby seen by a code joiner (peer 3): Olena hosts, three of four ready.
func _handoff_lobby() -> ClientModel:
	return _model(
		3, [[1, "Olena", true], [2, "Taras", true], [3, "Ivan", false], [4, "Marko", true]]
	)


## A lobby welcomed as `own`, its roster [peer, name, ready] in the Welcome's order.
func _model(own: int, roster: Array) -> ClientModel:
	var model := ClientModel.new(_mode)
	var welcome := WelcomeEvent.new(own, Vector3.ZERO, 1)
	for entry: Array in roster:
		welcome.roster.append({"peer": entry[0], "name": entry[1], "ready": entry[2]})
	welcome.settings = _mode.default_settings()
	welcome.map = "res://levels/greybox/greybox.tscn"
	welcome.phase = &"lobby"
	model.fold(&"Welcome", welcome.to_dict())
	return model
