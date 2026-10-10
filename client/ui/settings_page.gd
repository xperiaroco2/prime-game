class_name SettingsPage
extends VBoxContainer
## Settings (#491; prime-game-ui handoff s05 `settings-*` at ui-0.4.0): one scene the Esc menu's
## Settings tab and the main menu's Settings panel (s2) each instance. Sub: the sub-page chips in
## one ButtonGroup (Sound and voice, the default; Controls; Display; Accessibility; Language);
## Scroll (follow_focus): Rows, holding each sub-page's box, the selected one shown:
## - Sound: VoicePanel (the game feeds it and listens to it).
## - Controls: ControlsPanel (the game gives it the player's Controls).
## - Display: Window, fullscreen or windowed (GameWindow).
## - Access: LargeText (GameUi's large-text theme) and ReducedMotion (UiPrefs).
## - Language: one chip per language (Languages.ALL), each named in itself.
## The page shows what `bind` gives it each time it shows (the other page may have changed it),
## and says what the player picked through its signals; GameSettings applies and saves it.

signal large_text_toggled(on: bool)
signal reduced_motion_toggled(on: bool)
signal window_mode_picked(fullscreen: bool)
signal language_chosen(language: String)

enum Page { SOUND, CONTROLS, DISPLAY, ACCESS, LANGUAGE }

## Each sub-page's chip: its node name and deck key, in Page's order.
const SUB_KEYS: Dictionary[String, String] = {
	"Sound": "settings.tab.sound",
	"Controls": "settings.tab.controls",
	"Display": "settings.tab.display",
	"Access": "settings.tab.accessibility",
	"Language": "settings.tab.language",
}
const OFF_ON: Dictionary[String, String] = {"Off": "common.off", "On": "common.on"}
## Each language's chip name, in the handoff's order.
const LANGUAGE_CHIPS: Dictionary[String, String] = {
	"Ukrainian": Languages.UKRAINIAN,
	"English": Languages.ENGLISH,
}

var sub: HBoxContainer
var scroll := UiParts.scroll()
var rows := VBoxContainer.new()
var voice := VoicePanel.new()
var controls := ControlsPanel.new()
var display := VBoxContainer.new()
var access := VBoxContainer.new()
var language := VBoxContainer.new()
var window_chips: HBoxContainer
var large_text_chips: HBoxContainer
var motion_chips: HBoxContainer
var language_chips: HBoxContainer
## The sub-page shown.
var shown := Page.SOUND

## What the chips show (bind()): the player's settings and the window; null shows the defaults.
var _settings: UserSettings
var _window: GameWindow
var _large_text := func() -> bool: return false


func _init() -> void:
	name = "Settings"
	theme_type_variation = &"ToyColumnSixteen"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	sub = SettingRows.chips("Sub", SUB_KEYS, _on_sub)
	sub.custom_minimum_size = Vector2.ZERO
	add_child(sub)
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	rows.name = "Rows"
	rows.theme_type_variation = &"ToyColumnEight"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	rows.add_child(voice)
	rows.add_child(controls)
	window_chips = SettingRows.chips(
		"Mode",
		{"Fullscreen": "settings.window.fullscreen", "Windowed": "settings.window.windowed"},
		func(chip: String) -> void: window_mode_picked.emit(chip == "Fullscreen")
	)
	_box(display, "Display", [SettingRows.row("Window", "settings.window", window_chips)])
	large_text_chips = SettingRows.chips(
		"Toggle", OFF_ON, func(chip: String) -> void: large_text_toggled.emit(chip == "On")
	)
	motion_chips = SettingRows.chips(
		"Toggle", OFF_ON, func(chip: String) -> void: reduced_motion_toggled.emit(chip == "On")
	)
	_box(
		access,
		"Access",
		[
			SettingRows.row("LargeText", "settings.large_text", large_text_chips),
			SettingRows.row("ReducedMotion", "settings.reduced_motion", motion_chips),
		]
	)
	var language_keys: Dictionary[String, String] = {}
	for chip_name: String in LANGUAGE_CHIPS:
		language_keys[chip_name] = KeyLabel.word(Languages.name_key(LANGUAGE_CHIPS[chip_name]))
	language_chips = SettingRows.chips(
		"Choice",
		language_keys,
		func(chip: String) -> void: language_chosen.emit(LANGUAGE_CHIPS[chip])
	)
	# Each language is named in itself, the same in every locale.
	for chip: Node in language_chips.get_children():
		(chip as Button).auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_box(
		language,
		"Language",
		[SettingRows.row("Language", "settings.language.title", language_chips)]
	)
	show_page(Page.SOUND)


## The page shows `settings`, `window` and `large_text` (a Callable answering whether GameUi has
## the large text now) from the next time it shows on.
func bind(settings: UserSettings, window: GameWindow, large_text: Callable) -> void:
	_settings = settings
	_window = window
	_large_text = large_text
	show_values()


## Shows `page` alone, its chip pressed, scrolled to the top.
func show_page(page: Page) -> void:
	shown = page
	SettingRows.show_chip(sub, str(SUB_KEYS.keys()[page]))
	var boxes: Array[Control] = [voice, controls, display, access, language]
	for at: int in boxes.size():
		boxes[at].visible = at == page
	scroll.scroll_vertical = 0


## The chips show the values now: the window's mode, large text, reduced motion, the language.
func show_values() -> void:
	var fullscreen := (
		_window != null and GameWindow.toggled(_window.mode()) == DisplayServer.WINDOW_MODE_WINDOWED
	)
	SettingRows.show_chip(window_chips, "Fullscreen" if fullscreen else "Windowed")
	SettingRows.show_chip(large_text_chips, "On" if _large_text.call() else "Off")
	SettingRows.show_chip(motion_chips, "On" if UiPrefs.reduced_motion else "Off")
	var spoken := TranslationServer.get_locale().get_slice("_", 0)
	if _settings != null:
		spoken = Languages.shown(_settings)
	for chip_name: String in LANGUAGE_CHIPS:
		if LANGUAGE_CHIPS[chip_name] == spoken:
			SettingRows.show_chip(language_chips, chip_name)


## The control focus starts on: the selected sub-page's chip.
func first_focus() -> Control:
	return sub.get_child(shown) as Control


## Whether Controls captures a key (the keys bind then, the talk key must not speak).
func is_capturing() -> bool:
	return controls.is_capturing()


## Whether the Sound and voice rows are on screen (the game feeds them then).
func voice_shown() -> bool:
	return voice.is_visible_in_tree()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree() and sub != null:
		show_values()


func _on_sub(chip: String) -> void:
	show_page(SUB_KEYS.keys().find(chip) as Page)


func _box(box: VBoxContainer, box_name: String, children: Array[PanelContainer]) -> void:
	box.name = box_name
	box.theme_type_variation = &"ToyColumnEight"
	for child: PanelContainer in children:
		box.add_child(child)
	rows.add_child(box)
