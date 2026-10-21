class_name GameSettings
extends RefCounted
## Game's wiring of the two Settings pages (#491: the Esc menu's and the main menu's SettingsPage),
## out of game.gd to keep it under lint's 1000 lines: both pages show the player's UserSettings,
## Controls and window, and what either picks is applied at once and saved in the player's file.
## Large text swaps GameUi's theme, reduced motion sets UiPrefs, the window mode goes to
## GameWindow, the language to Languages.choose (saved only when picked, #208). The saved large
## text and reduced motion apply at the start; the saved window mode only with the command line
## read and no runner window asked for (a test's or a runner's window keeps its window as it is).
## Game's _ready sets up its settings, its own voice and its controls here too (#1249).

## The environment variable a runner launch sets (tools/offscreen/offscreen.gd ENV, #1141): the
## window script places its window off-screen, and a restored fullscreen would cover the screen.
const RUNNER_WINDOW := "PRIME_WINDOW"


## Game's settings, and their interface language applied (#208): the player's choice, or on a
## first launch the system's when it is Ukrainian and English otherwise. A Game with no command
## line (a test, a playcheck window) ignores the machine's language: it speaks English unless its
## settings say otherwise, so a run reads the same on every machine.
static func ready_settings(game: Game) -> void:
	if game.settings == null:
		# A Game with no command line (a test, a playcheck window) keeps its settings in memory: the
		# player's file in user:// would set the process's buses and take an opening mark.
		game.settings = (
			UserSettings.for_this_window() if game.read_command_line else UserSettings.new()
		)
	Languages.apply(
		game.settings, OS.get_locale_language() if game.read_command_line else Languages.ENGLISH
	)


## The buses (D15), the voices' node under `world`, and the own voice: the sender, Game's settings
## applied, and both Sound and voice pages (the Esc menu's, the main menu's, #301) wired to them.
## Returns the VoiceControl, started.
static func start_voice(game: Game, world: Node3D) -> VoiceControl:
	AudioBuses.ensure()
	if game.voice_codec == null:
		game.voice_codec = TwoVoipCodec.new()
	world.add_child(game.voices())
	var sender := game.sender()
	sender.codec = game.voice_codec
	game.add_child(sender)
	var control := VoiceControl.new(game.settings, sender)
	wire_voice(game, control)
	control.start()
	return control


## The player's controls applied (a test's or a playcheck window's stay the project's: the player's
## file in user:// would rebind the process's keys), and both Settings pages wired (setup).
static func ready_controls(game: Game) -> void:
	if game.controls == null:
		game.controls = Controls.for_this_player() if game.read_command_line else Controls.new()
		if game.read_command_line:
			game.controls.apply()
	setup(game)


## Both Settings pages: the Esc menu's and the main menu's.
static func pages(game: Game) -> Array[SettingsPage]:
	return [game.ui.esc.settings, game.ui.menu.settings_page]


## At Game's _ready, once its settings and controls are set: the saved choices applied, both
## pages bound and listened to.
static func setup(game: Game) -> void:
	var saved := game.settings
	game.ui.set_large_text(saved.large_text)
	UiPrefs.reduced_motion = (
		UiPrefs.from_system_answer(saved.reduced_motion)
		if saved.reduced_motion >= 0
		else UiPrefs.system_reduced_motion()
	)
	if restores_window(
		saved.window_mode, game.read_command_line, OS.get_environment(RUNNER_WINDOW)
	):
		game.window.set_mode(_window_mode(saved.window_mode == UserSettings.WINDOW_FULLSCREEN))
	for page: SettingsPage in pages(game):
		page.bind(saved, game.window, func() -> bool: return game.ui.large_text)
		page.controls.setup(game.controls)
		page.large_text_toggled.connect(set_large_text.bind(game))
		page.reduced_motion_toggled.connect(set_reduced_motion.bind(game))
		page.window_mode_picked.connect(set_fullscreen.bind(game))
		page.language_chosen.connect(choose_language.bind(game))
	# The Lobby tab's own preset (Save your own) is the player's too.
	game.ui.esc.lobby.set_own_preset(saved.own_preset)
	game.ui.esc.lobby.preset_saved.connect(save_own_preset.bind(game))


## Whether the saved window mode is restored at the start: only with the command line read, a
## saved mode, and no `runner_window` (PRIME_WINDOW; #1175). The other saved settings apply anyway.
static func restores_window(
	saved_mode: String, read_command_line: bool, runner_window: String
) -> bool:
	return read_command_line and not saved_mode.is_empty() and runner_window.is_empty()


static func save_own_preset(values: Dictionary, game: Game) -> void:
	game.settings.own_preset = values
	_save(game)


## Both pages' Sound and voice wired to `control` (the game's VoiceControl).
static func wire_voice(game: Game, control: VoiceControl) -> void:
	for page: SettingsPage in pages(game):
		var panel := page.voice
		panel.device_picked.connect(control.pick_device)
		panel.mode_picked.connect(control.set_mode)
		panel.threshold_changed.connect(control.set_threshold)
		panel.denoise_toggled.connect(control.set_denoise)
		panel.volume_changed.connect(control.set_volume)
		panel.sliders_settled.connect(control.save_sliders)
		panel.tone_toggled.connect(control.set_tone)
		panel.mute_toggled.connect(control.set_muted)


static func set_large_text(on: bool, game: Game) -> void:
	game.ui.set_large_text(on)
	game.settings.large_text = on
	_save(game)


static func set_reduced_motion(on: bool, game: Game) -> void:
	UiPrefs.reduced_motion = on
	game.settings.reduced_motion = 1 if on else 0
	_save(game)


static func set_fullscreen(on: bool, game: Game) -> void:
	game.window.set_mode(_window_mode(on))
	_store_window(game, on)


## Alt+Enter (`toggle_fullscreen`): the window flips, and the pages and the file follow it.
static func toggle_window(game: Game) -> void:
	game.window.toggle_fullscreen()
	_store_window(
		game, GameWindow.toggled(game.window.mode()) == DisplayServer.WINDOW_MODE_WINDOWED
	)


static func choose_language(language: String, game: Game) -> void:
	var saved := Languages.choose(game.settings, language)
	if saved != OK:
		push_warning("settings: the language is not saved: %s" % error_string(saved))


## A Settings page's Controls captures a key: the keys bind, the talk key must not speak.
static func capturing(game: Game) -> bool:
	for page: SettingsPage in pages(game):
		if page.is_capturing():
			return true
	return false


## The Sound and voice rows on screen now, the game feeds them: the Esc menu's on its Settings
## tab, the main menu's in its open Settings panel; null for none.
static func shown_voice(game: Game) -> VoicePanel:
	var ui := game.ui
	if ui.esc_open():
		var on_settings := ui.esc.state.selected == EscMenuState.Tab.SETTINGS
		return (
			ui.esc.voice
			if on_settings and ui.esc.settings.shown == SettingsPage.Page.SOUND
			else null
		)
	var page := ui.menu.settings_page
	if ui.screen == GameFlow.Screen.MENU and ui.menu.settings_open():
		return ui.menu.voice if page.shown == SettingsPage.Page.SOUND else null
	return null


static func _store_window(game: Game, fullscreen: bool) -> void:
	game.settings.window_mode = (
		UserSettings.WINDOW_FULLSCREEN if fullscreen else UserSettings.WINDOW_WINDOWED
	)
	for page: SettingsPage in pages(game):
		page.show_values()
	_save(game)


static func _window_mode(fullscreen: bool) -> DisplayServer.WindowMode:
	return (
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)


static func _save(game: Game) -> void:
	var saved := game.settings.write()
	if saved != OK:
		push_warning("settings: not saved: %s" % error_string(saved))
