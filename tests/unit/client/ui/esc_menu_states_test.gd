extends GdUnitTestSuite
## The Esc menu's states (client/ui/esc_menu.gd, #491) against prime-game-ui's handoff s05 at
## ui-0.4.0 (docs/handoff/s05-esc-menu.md). The handoff draws `lobby-host` whole and every other
## state as what differs from it: its Hidden list, its Changed lines and the roots of its Shown
## subtrees. BASE and STATES copy those lists verbatim, with the handoff's paths; `ours()` maps a
## handoff path onto the built tree (the differences the PR lists), and NOT_BUILT names the paths
## the menu does not build, each with its reason. A mismatch is fixed in the code or listed in the
## PR, never by editing these lists. Character and character-round wait for #73 (M7): not built.
## Each state is built as the preview scenes build it (screen_preview.gd's Preview.ESC branch).

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
const CODE := "K7M2QX"
const S := GameFlow.Screen
const TAB := EscMenuState.Tab
const PAGE := SettingsPage.Page

## `lobby-host`, the handoff's whole tree: the nodes it draws (true) and those it lacks that other
## states show (false).
const BASE: Dictionary[String, bool] = {
	"Menu/H/Tabs/Game": true,
	"Menu/H/Tabs/Role": false,
	"Menu/H/Tabs/Guide": true,
	"Menu/H/Tabs/Lobby": true,
	"Menu/H/Tabs/Settings": true,
	"Menu/H/Page/TitleRow/Title": true,
	"Menu/H/Page/TitleRow/HostNote": true,
	"Menu/H/Page/TitleRow/HostOnly": false,
	"Menu/H/Page/Actions": false,
	"Menu/H/Page/Role": false,
	"Menu/H/Page/Role/Team": false,
	"Menu/H/Page/Guide": false,
	"Menu/H/Page/Lobby": true,
	"Menu/H/Page/Lobby/Presets": true,
	"Menu/H/Page/Lobby/Preset": false,
	"Menu/H/Page/Lobby/Body/SettingList/Name/H/Field": true,
	"Menu/H/Page/Lobby/Body/SettingList/Duration/H/Stepper/Less": true,
	"Menu/H/Page/Lobby/Body/SettingList/Duration/H/Stepper/More": true,
	"Menu/H/Page/Lobby/Body/SettingList/Packages/H/Stepper/Less": true,
	"Menu/H/Page/Lobby/Body/SettingList/Packages/H/Stepper/More": true,
	"Menu/H/Page/Lobby/Body/SettingList/Dissidents/H/Stepper/Less": true,
	"Menu/H/Page/Lobby/Body/SettingList/Dissidents/H/Stepper/More": true,
	"Menu/H/Page/Lobby/Body/SettingList/Knives/H/Stepper/Less": true,
	"Menu/H/Page/Lobby/Body/SettingList/Knives/H/Stepper/More": true,
	"Menu/H/Page/Lobby/Body/SettingList/Tasks/H/Allowed": true,
	"Menu/H/Page/Lobby/Body/SettingList/Tasks/H/Shown": false,
	"Menu/H/Page/Lobby/Body/Side/CodeRow": true,
	"Menu/H/Page/Lobby/Body/Side/CodeGone": false,
	"Menu/H/Page/Lobby/Body/Side/Players": true,
	"Menu/H/Page/Lobby/Body/Side/Ready": true,
	"Menu/H/Page/Settings": false,
	"ConfirmDim": false,
	"Confirm": false,
}
## Handoff paths the menu does not build: the players' rows are named after the handoff's sample
## players (the rows follow the roster, LobbyPanel), SwitchSteps waits for a mode that declares a
## step count (#256), Character for #73.
const NOT_BUILT: Array[String] = [
	"Menu/H/Page/Lobby/Body/Side/Players/Scroll/Rows/",
	"Menu/H/Page/Lobby/Body/SettingList/SwitchSteps/",
	"Menu/H/Tabs/Character",
]
const LOBBY_GUEST_HIDDEN: Array[String] = [
	"Menu/H/Page/TitleRow/HostNote",
	"Menu/H/Page/Lobby/Presets",
	"Menu/H/Page/Lobby/Body/SettingList/Duration/H/Stepper/Less",
	"Menu/H/Page/Lobby/Body/SettingList/Duration/H/Stepper/More",
	"Menu/H/Page/Lobby/Body/SettingList/Packages/H/Stepper/Less",
	"Menu/H/Page/Lobby/Body/SettingList/Packages/H/Stepper/More",
	"Menu/H/Page/Lobby/Body/SettingList/Dissidents/H/Stepper/Less",
	"Menu/H/Page/Lobby/Body/SettingList/Dissidents/H/Stepper/More",
	"Menu/H/Page/Lobby/Body/SettingList/Knives/H/Stepper/Less",
	"Menu/H/Page/Lobby/Body/SettingList/Knives/H/Stepper/More",
	"Menu/H/Page/Lobby/Body/SettingList/Tasks/H/Allowed",
	"Menu/H/Page/Lobby/Body/SettingList/SwitchSteps/H/Stepper/Less",
	"Menu/H/Page/Lobby/Body/SettingList/SwitchSteps/H/Stepper/More",
	"Menu/H/Page/Lobby/Body/Side/Players/Scroll/Rows/Ivan",
	"Menu/H/Page/Lobby/Body/Side/Players/Scroll/Rows/Marko/H/Ready",
	"Menu/H/Page/Lobby/Body/Side/Players/Scroll/Rows/Oksana",
	"Menu/H/Page/Lobby/Body/Side/Players/Scroll/Rows/Solomiia",
	"Menu/H/Page/Lobby/Body/Side/Players/Scroll/Rows/Bohdan",
	"Menu/H/Page/Lobby/Body/Side/Players/Scroll/Rows/Iryna",
	"Menu/H/Page/Lobby/Body/Side/Players/Scroll/Rows/Dmytro",
	"Menu/H/Page/Lobby/Body/Side/Players/Scroll/Rows/Lesia",
]
## The Hidden list every state off the Lobby tab shares.
const OFF_LOBBY: Array[String] = ["Menu/H/Page/TitleRow/HostNote", "Menu/H/Page/Lobby"]
## The 15 states the menu builds: its context (screen, hosting, role, tutorial, the code service
## gone), the tab and the Settings sub-page pressed, the host's question; then the handoff's lists.
## `pressed` and `title` are its Changed lines (lobby-host: Lobby, esc.tab.lobby).
var states: Dictionary[String, Dictionary] = {
	"lobby-host": {},
	"lobby-guest":
	{
		"hosting": false,
		"hidden": LOBBY_GUEST_HIDDEN,
		"shown":
		[
			"Menu/H/Page/TitleRow/HostOnly",
			"Menu/H/Page/Lobby/Preset",
			"Menu/H/Page/Lobby/Body/SettingList/Tasks/H/Shown",
			"Menu/H/Page/Lobby/Body/Side/Players/Scroll/Rows/Host/H/Ready",
			"Menu/H/Page/Lobby/Body/Side/Players/Scroll/Rows/You",
		]
	},
	"lobby-no-code":
	{
		"code_gone": true,
		"hidden": ["Menu/H/Page/Lobby/Body/Side/CodeRow"],
		"shown": ["Menu/H/Page/Lobby/Body/Side/CodeGone"],
	},
	"game-host": _off_lobby(TAB.GAME, ["Menu/H/Tabs/Role", "Menu/H/Page/Actions"]),
	"game-guest":
	_off_lobby(TAB.GAME, ["Menu/H/Tabs/Role", "Menu/H/Page/Actions"], {"hosting": false}),
	"game-confirm":
	_off_lobby(
		TAB.GAME,
		["Menu/H/Tabs/Role", "Menu/H/Page/Actions", "ConfirmDim", "Confirm"],
		{"question": true},
	),
	"role-engineer":
	_off_lobby(TAB.ROLE, ["Menu/H/Tabs/Role", "Menu/H/Page/Role"], {"role": &"crew"}),
	# Team is in role-dissident's Shown subtree under Menu/H/Page/Role, not in role-engineer's.
	"role-dissident":
	_off_lobby(TAB.ROLE, ["Menu/H/Tabs/Role", "Menu/H/Page/Role", "Menu/H/Page/Role/Team"]),
	"guide": _off_lobby(TAB.GUIDE, ["Menu/H/Tabs/Role", "Menu/H/Page/Guide"]),
	"settings-sound": _settings(PAGE.SOUND),
	"settings-controls": _settings(PAGE.CONTROLS),
	"settings-display": _settings(PAGE.DISPLAY),
	"settings-access": _settings(PAGE.ACCESS),
	"settings-language": _settings(PAGE.LANGUAGE),
	"tutorial-game":
	{
		"round": true,
		"tutorial": true,
		"tab": TAB.GAME,
		"hidden":
		[
			"Menu/H/Tabs/Lobby",
			"Menu/H/Tabs/Character",
			"Menu/H/Page/TitleRow/HostNote",
			"Menu/H/Page/Lobby",
		],
		"shown": ["Menu/H/Page/Actions"],
	},
}
var _mode: GameMode
var _keys := RegEx.create_from_string("^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$")


func before() -> void:
	_mode = load(MODE) as GameMode


func after_test() -> void:
	TranslationServer.set_locale(Languages.ENGLISH)


## A handoff path in the built tree: raised parts sit in their `<Name>Raised` wrapper, and the
## mode's setting rows in SettingList's `Settings` box (LobbyPanel rebuilds it per mode).
static func ours(path: String) -> String:
	if path == "Confirm":
		return "ConfirmRaised/Confirm"
	var mapped := "MenuRaised/" + path if path.begins_with("Menu/") else path
	for row: String in ["Duration", "Packages", "Dissidents", "Knives", "Tasks", "SwitchSteps"]:
		mapped = mapped.replace("/SettingList/%s/" % row, "/SettingList/Settings/%s/" % row)
	return mapped.replace("/Side/Ready", "/Side/ReadyRaised/Ready")


func test_every_state_shows_and_hides_what_the_handoff_lists() -> void:
	assert_int(states.size()).is_equal(15)
	for id: String in states:
		var spec := states[id]
		var menu := _build(spec)
		var own := _expected(spec)
		for path: String in own:
			if _not_built(path):
				continue
			var node := menu.get_node_or_null(NodePath(ours(path))) as Control
			assert_object(node).override_failure_message("%s: no %s" % [id, path]).is_not_null()
			if node == null:
				continue
			var want := _shown_with_parents(path, own)
			(
				assert_bool(node.is_visible_in_tree())
				. override_failure_message("%s: %s should be %s" % [id, path, want])
				. is_equal(want)
			)
		var pressed := str(EscMenu.TABS[spec.get("tab", TAB.LOBBY)][0])
		for tab: TAB in menu.tab_buttons:
			var button := menu.tab_buttons[tab]
			(
				assert_bool(button.button_pressed)
				. override_failure_message("%s: tab %s" % [id, button.name])
				. is_equal(str(button.name) == pressed)
			)
		var title := str(EscMenu.TABS[spec.get("tab", TAB.LOBBY)][1])
		assert_str(menu.title_label.text).override_failure_message(id).is_equal(title)
		if spec.has("page"):
			var chip_name: String = SettingsPage.SUB_KEYS.keys()[spec["page"]]
			for chip: Node in menu.settings.get_node(^"Sub").get_children():
				(
					assert_bool((chip as Button).button_pressed)
					. override_failure_message("%s: chip %s" % [id, chip.name])
					. is_equal(str(chip.name) == chip_name)
				)
		# Character waits for #73: no tab, no placeholder.
		assert_object(menu.get_node_or_null(^"MenuRaised/Menu/H/Tabs/Character")).is_null()
		assert_object(menu.get_node_or_null(^"MenuRaised/Menu/H/Page/Character")).is_null()
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
	menu.lobby.show_code(JoinProgress.code_text(CODE, spec.get("code_gone", false) as bool), CODE)
	var screen := S.LOBBY
	if spec.get("round", false):
		# The own player a dissident with one teammate (fold_round's), or `role` alone.
		Preview.fold_round(model, false)
		screen = S.ROUND
		if spec.has("role"):
			model.fold(&"RoleAssigned", {"role": spec["role"]})
	menu.state.tutorial = spec.get("tutorial", false)
	menu.open(screen, model, hosting)
	menu.press(spec.get("tab", TAB.LOBBY) as TAB)
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


static func _not_built(path: String) -> bool:
	for prefix: String in NOT_BUILT:
		if path == prefix or path.begins_with(prefix):
			return true
	return false


## A state off the Lobby tab, in a round (Role is shown in each): `tab` pressed, `shown` its
## Shown roots.
static func _off_lobby(tab: TAB, shown: Array[String], more: Dictionary = {}) -> Dictionary:
	var spec := {"round": true, "tab": tab, "hidden": OFF_LOBBY, "shown": shown}
	spec.merge(more, true)
	return spec


static func _settings(page: PAGE) -> Dictionary:
	return _off_lobby(TAB.SETTINGS, ["Menu/H/Tabs/Role", "Menu/H/Page/Settings"], {"page": page})
