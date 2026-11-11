extends GdUnitTestSuite
## The Esc menu's Lobby page's player list (#1422): every row is the player's name as it is (the
## own "You"), and the host's row carries the roster's host tag (`hud.roster.host`, the lobby HUD's
## own, ui-2.4.0) instead of the retired host mark, which nothing reads any more.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"

var _panel: LobbyPanel
var _locale := ""


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale(Languages.ENGLISH)
	_panel = auto_free(LobbyPanel.new())
	add_child(_panel)
	_panel.set_mode(load(MODE) as GameMode)


func after_test() -> void:
	TranslationServer.set_locale(_locale)


func test_the_hosts_row_is_its_name_with_the_rosters_host_tag() -> void:
	var model := Preview.fake_model(load(MODE) as GameMode, false)
	_panel.refresh(model, -1, false)
	var host: ClientModel.Member = model.roster[NetTransport.HOST_ID]
	assert_str(LobbyPanel.row_text(model, NetTransport.HOST_ID)).is_equal(host.name)
	var tags: Array[String] = []
	var hosts := 0
	for row: Node in _panel.player_rows.get_children():
		var tag := row.find_child("HostTag", true, false)
		if tag == null:
			continue
		hosts += 1
		var text := tag.find_child("Text", true, false) as Label
		tags.append(text.text)
		var name := SettingRows.name_of(row as PanelContainer).text
		assert_str(name).is_equal(host.name)
	assert_int(hosts).is_equal(1)
	assert_array(tags).is_equal([LobbyText.HOST_TAG_KEY])


## The own row stays "You" when the own player hosts, with the tag too.
func test_the_own_row_is_you_and_a_hosting_own_row_has_the_tag() -> void:
	var model := Preview.fake_model(load(MODE) as GameMode, true)
	_panel.refresh(model, -1, true)
	assert_str(LobbyPanel.row_text(model, model.own_peer)).is_equal(tr("player.you"))
	var first := _panel.player_rows.get_child(0)
	assert_object(first.find_child("HostTag", true, false)).is_not_null()
