extends GdUnitTestSuite
## The Esc menu's Lobby tab's lobby name (ARCHITECTURE §4.7.11, #214): the host edits it, sent when
## submitted or left, cleaned and only when it changes; everyone else reads it; an empty name shows
## the default `lobby.default_name` with the host's name; the per-frame refresh never overwrites
## what the host is typing.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"

var _panel: LobbyPanel
var _sent: Array[String] = []
var _locale := ""


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale(Languages.ENGLISH)
	_panel = auto_free(LobbyPanel.new())
	add_child(_panel)
	_panel.set_mode(load(MODE) as GameMode)
	_sent.clear()
	_panel.lobby_name_changed.connect(func(text: String) -> void: _sent.append(text))


func after_test() -> void:
	TranslationServer.set_locale(_locale)


func test_the_host_edits_the_name_and_a_submit_sends_it_once() -> void:
	var model := _model(true)
	_panel.refresh(model, -1, true)
	assert_bool(_panel.name_edit.editable).is_true()
	assert_int(_panel.name_edit.max_length).is_equal(LobbyName.MAX_CHARS)
	assert_str(_panel.name_edit.text).is_empty()
	assert_str(_panel.name_edit.placeholder_text).is_equal("Player1's lobby")
	_panel.name_edit.text = "  Den" + String.chr(0x200B)
	_panel.name_edit.text_submitted.emit(_panel.name_edit.text)
	assert_array(_sent).is_equal(["Den"])
	assert_str(_panel.name_edit.text).is_equal("Den")
	# The same name again, or leaving the field, sends nothing more.
	_panel.name_edit.text_submitted.emit(_panel.name_edit.text)
	_panel.name_edit.focus_exited.emit()
	assert_array(_sent).is_equal(["Den"])
	# Clearing it asks for the default.
	model.lobby_name = "Den"
	_panel.refresh(model, -1, true)
	_panel.name_edit.text = ""
	_panel.name_edit.focus_exited.emit()
	assert_array(_sent).is_equal(["Den", ""])


func test_a_player_reads_the_name_and_sends_nothing() -> void:
	var model := _model(false)
	model.lobby_name = "Den"
	_panel.refresh(model, -1, false)
	assert_bool(_panel.name_edit.editable).is_false()
	assert_str(_panel.name_edit.text).is_equal("Den")
	_panel.name_edit.text = "Mine"
	_panel.name_edit.text_submitted.emit("Mine")
	_panel.name_edit.focus_exited.emit()
	assert_array(_sent).is_empty()
	# The next refresh shows the host's name again.
	_panel.refresh(model, -1, false)
	assert_str(_panel.name_edit.text).is_equal("Den")


func test_a_sent_name_stays_in_the_field_until_the_host_echoes_it() -> void:
	var model := _model(true)
	_panel.refresh(model, -1, true)
	_panel.name_edit.text = "Den"
	_panel.name_edit.focus_exited.emit()
	assert_array(_sent).is_equal(["Den"])
	# The echo is a round trip away: the next frames keep the sent name, and leaving the field
	# again (say after Enter) sends it no second time.
	_panel.refresh(model, -1, true)
	assert_str(_panel.name_edit.text).is_equal("Den")
	_panel.name_edit.focus_exited.emit()
	assert_array(_sent).is_equal(["Den"])
	model.lobby_name = "Den"
	_panel.refresh(model, -1, true)
	assert_str(_panel.name_edit.text).is_equal("Den")
	# Once the model has moved, a later rename by anyone shows again.
	model.lobby_name = "Attic"
	_panel.refresh(model, -1, true)
	assert_str(_panel.name_edit.text).is_equal("Attic")


func test_a_players_focused_field_still_follows_a_rename() -> void:
	var model := _model(false)
	model.lobby_name = "Den"
	_panel.refresh(model, -1, false)
	_panel.name_edit.grab_focus()
	assert_bool(_panel.name_edit.has_focus()).is_true()
	model.lobby_name = "Attic"
	_panel.refresh(model, -1, false)
	assert_str(_panel.name_edit.text).is_equal("Attic")


func test_a_refresh_keeps_what_the_host_is_typing() -> void:
	var model := _model(true)
	_panel.refresh(model, -1, true)
	_panel.name_edit.grab_focus()
	assert_bool(_panel.name_edit.has_focus()).is_true()
	_panel.name_edit.text = "Half typ"
	_panel.refresh(model, -1, true)
	assert_str(_panel.name_edit.text).is_equal("Half typ")
	assert_array(_sent).is_empty()
	# Leaving the field sends it; with no focus a refresh follows the model.
	_panel.name_edit.release_focus()
	assert_array(_sent).is_equal(["Half typ"])
	model.lobby_name = "Renamed"
	_panel.refresh(model, -1, true)
	assert_str(_panel.name_edit.text).is_equal("Renamed")


func test_the_title_is_the_hosts_name_or_the_default() -> void:
	var model := _model(false)
	assert_str(LobbyPanel.lobby_title(model)).is_equal("Player1's lobby")
	model.lobby_name = "Den"
	assert_str(LobbyPanel.lobby_title(model)).is_equal("Den")
	TranslationServer.set_locale(Languages.UKRAINIAN)
	model.lobby_name = ""
	assert_str(LobbyPanel.lobby_title(model)).is_equal("Лобі: Player1")


func _model(as_host: bool) -> ClientModel:
	return Preview.fake_model(load(MODE) as GameMode, as_host)
