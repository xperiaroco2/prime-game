extends GdUnitTestSuite
## The Esc menu's states (client/ui/esc_menu.gd, #491, #1571) against prime-game-ui's handoff s05 at
## ui-2.5.4 (docs/handoff/s05-esc-menu.md): the side panel at the left with the page of the open
## entry beside it. Each state lists what differs from BASE (the `lobby` state: the panel alone);
## a mismatch is fixed in the code or listed in the PR, never by editing these lists. Each state is
## built as the preview scenes build it (screen_preview.gd's Preview.ESC branch), on the melee
## fixture (the shipped mode with the knives placed again, #1497).

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := FixtureBaseModeWithMelee.PATH
const CODE := "K7M2QX"
const S := GameFlow.Screen
const TAB := EscMenuState.Tab
const PAGE := SettingsPage.Page

## The handoff s05 at ui-2.5.4 drawn by the built tree: the paths every state checks, shown (true)
## or not (false) in `lobby` (the panel alone in the lobby, nothing open).
const BASE: Dictionary[String, bool] = {
	"Menu/Side": true,
	"Menu/Side/V/Head": true,
	"Menu/Side/V/Head/V/Row/Copy": true,
	"Menu/Side/V/Entries/Resume": true,
	"Menu/Side/V/Entries/Guide": true,
	"Menu/Side/V/Entries/Lobby": true,
	"Menu/Side/V/Entries/Settings": true,
	"Menu/Side/V/Rule": true,
	"Menu/Side/V/Bottom/Leave": true,
	"Menu/Side/V/Bottom/Quit": true,
	"Menu/Page": false,
	"Menu/Page/V/HostRow": false,
	"Menu/Page/V/HostRow/HostNote": false,
	"Menu/Page/V/HostRow/HostOnly": false,
	"Menu/Page/V/Guide": false,
	"Menu/Page/V/Lobby": false,
	"Menu/Page/V/Settings": false,
	"ConfirmDim": false,
	"Confirm": false,
}
## The Hidden list every state in a round shares: no code head, no Lobby entry (s05 `round`).
const IN_ROUND: Array[String] = ["Menu/Side/V/Head", "Menu/Side/V/Entries/Lobby"]
## The states the menu builds: its context (screen, hosting, tutorial), the entry pressed and the
## Settings section, the host's question; then what differs from BASE. Character waits for the
## mirror (#1394, the engineer 2026-10-28) and the ship's states (no session) for #1285.
var states: Dictionary[String, Dictionary] = {
	"lobby": {},
	"lobby-page":
	{
		"tab": TAB.LOBBY,
		"shown":
		["Menu/Page", "Menu/Page/V/Lobby", "Menu/Page/V/HostRow", "Menu/Page/V/HostRow/HostNote"],
	},
	# A guest reads the settings: the lock line naming the host, no host note.
	"lobby-page-guest":
	{
		"hosting": false,
		"tab": TAB.LOBBY,
		"shown":
		["Menu/Page", "Menu/Page/V/Lobby", "Menu/Page/V/HostRow", "Menu/Page/V/HostRow/HostOnly"],
	},
	# The code service gone: no dead code in the head (the Lobby page says so).
	"lobby-no-code": {"code_gone": true, "hidden": ["Menu/Side/V/Head"]},
	"round": {"round": true, "hidden": IN_ROUND},
	"round-confirm":
	{"round": true, "question": true, "hidden": IN_ROUND, "shown": ["ConfirmDim", "Confirm"]},
	"guide":
	{
		"round": true,
		"tab": TAB.GUIDE,
		"hidden": IN_ROUND,
		"shown": ["Menu/Page", "Menu/Page/V/Guide"]
	},
	"settings-sound": _settings(PAGE.SOUND),
	"settings-controls": _settings(PAGE.CONTROLS),
	"settings-display": _settings(PAGE.DISPLAY),
	"settings-access": _settings(PAGE.ACCESS),
	"settings-language": _settings(PAGE.LANGUAGE),
	# Quit is not in the tutorial: leave it first (s05 `tutorial`).
	"tutorial": {"round": true, "tutorial": true, "hidden": IN_ROUND + ["Menu/Side/V/Bottom/Quit"]},
}
var _mode: GameMode
var _keys := RegEx.create_from_string("^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$")


func before() -> void:
	_mode = load(MODE) as GameMode


func after_test() -> void:
	TranslationServer.set_locale(Languages.ENGLISH)


func test_every_state_shows_and_hides_what_the_handoff_lists() -> void:
	assert_int(states.size()).is_equal(13)
	for id: String in states:
		var spec := states[id]
		var menu := _build(spec)
		var own := _expected(spec)
		for path: String in own:
			var node := menu.get_node_or_null(NodePath(path)) as Control
			assert_object(node).override_failure_message("%s: no %s" % [id, path]).is_not_null()
			if node == null:
				continue
			var want := _shown_with_parents(path, own)
			(
				assert_bool(node.is_visible_in_tree())
				. override_failure_message("%s: %s should be %s" % [id, path, want])
				. is_equal(want)
			)
		# Only the open entry is pressed (none in `lobby`, `round` and `tutorial`).
		var open: int = spec.get("tab", TAB.GAME)
		for tab: TAB in menu.tab_buttons:
			var button := menu.tab_buttons[tab]
			(
				assert_bool(button.button_pressed)
				. override_failure_message("%s: entry %s" % [id, button.name])
				. is_equal(tab == open)
			)
		if spec.has("page"):
			var item_name: String = SettingsPage.SUB_KEYS.keys()[spec["page"]]
			for item: Node in menu.settings.get_node(^"Nav").get_children():
				(
					assert_bool((item as Button).button_pressed)
					. override_failure_message("%s: section %s" % [id, item.name])
					. is_equal(str(item.name) == item_name)
				)
		# Leave reads the tutorial's words there.
		var leave := "esc.game.leave_tutorial" if spec.get("tutorial", false) else "esc.game.leave"
		assert_str(menu.leave_button.text).override_failure_message(id).is_equal(leave)
		# Character waits for the mirror (#1394), the Role page is the HUD's (s05).
		assert_object(menu.get_node_or_null(^"Menu/Side/V/Entries/Character")).is_null()
		assert_object(menu.get_node_or_null(^"Menu/Side/V/Entries/Role")).is_null()
		menu.free()


func test_no_state_shows_a_deck_key_as_itself_in_english_or_ukrainian() -> void:
	# A key missing from the deck shows as itself; a key set on a node that does not translate
	# (auto_translate_mode DISABLED) shows as itself too.
	for language: String in Languages.ALL:
		for id: String in states:
			TranslationServer.set_locale(language)
			var menu := _build(states[id])
			menu.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
			for raw: String in _raw_keys(menu):
				fail("%s, %s: %s shows as itself" % [language, id, raw])
			menu.free()


## The key-shaped texts `menu` shows untranslated: Labels, Buttons and OptionButton items in view.
func _raw_keys(menu: EscMenu) -> PackedStringArray:
	var raw := PackedStringArray()
	for found: Node in menu.find_children("*", "Control", true, false):
		var control := found as Control
		if not control.is_visible_in_tree():
			continue
		var texts := PackedStringArray()
		if control is Label:
			texts.append((control as Label).text)
		elif control is Button:
			texts.append((control as Button).text)
		if control is OptionButton:
			var picker := control as OptionButton
			for i in picker.item_count:
				texts.append(picker.get_item_text(i))
		for text: String in texts:
			if _keys.search(text) == null:
				continue
			var shown := (
				String(TranslationServer.translate(text)) if control.can_auto_translate() else text
			)
			if shown == text:
				raw.append("%s (%s)" % [text, control.get_path()])
	return raw


## Builds the state `spec` names, added to the tree, as the preview scenes do.
func _build(spec: Dictionary) -> EscMenu:
	var menu := EscMenu.new()
	add_child(menu)
	menu.lobby.set_mode(_mode)
	menu.guide.set_mode(_mode)
	var hosting: bool = spec.get("hosting", true)
	var model := Preview.fake_model(_mode, hosting)
	menu.show_code(JoinProgress.code_text(CODE, spec.get("code_gone", false) as bool), CODE)
	var screen := S.LOBBY
	if spec.get("round", false):
		Preview.fold_round(model, false)
		screen = S.ROUND
	menu.state.tutorial = spec.get("tutorial", false)
	menu.open(screen, model, hosting)
	if spec.has("tab"):
		menu.press(spec["tab"] as TAB)
	menu.settings.show_page(spec.get("page", PAGE.SOUND) as PAGE)
	menu.refresh(screen, model, -1, hosting, _mode)
	if spec.get("question", false):
		menu.press_leave()
	return menu


## Each checked path's own visibility in `spec`: BASE, then its Hidden and Shown lists.
func _expected(spec: Dictionary) -> Dictionary[String, bool]:
	var own: Dictionary[String, bool] = BASE.duplicate()
	for path: String in spec.get("hidden", []):
		own[path] = false
	for path: String in spec.get("shown", []):
		own[path] = true
	return own


## Shown on screen: shown itself and under no hidden node the lists name.
static func _shown_with_parents(path: String, own: Dictionary[String, bool]) -> bool:
	for other: String in own:
		if not own[other] and path.begins_with(other + "/"):
			return false
	return own[path]


static func _settings(page: PAGE) -> Dictionary:
	return {
		"round": true,
		"tab": TAB.SETTINGS,
		"page": page,
		"hidden": IN_ROUND,
		"shown": ["Menu/Page", "Menu/Page/V/Settings"],
	}
