extends GdUnitTestSuite
## The interface language at the start of the game (client/app/game.gd, #208): the player's saved
## choice is the game's locale before the first screen draws, whatever it was before.

const GAME := preload("res://client/app/game.tscn")

var _locale := ""


func before_test() -> void:
	_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_locale)


func test_the_saved_choice_is_the_locale_at_the_start() -> void:
	for language: String in [Languages.UKRAINIAN, Languages.ENGLISH]:
		TranslationServer.set_locale("de")
		var settings := UserSettings.new()
		settings.language = language
		var game := _game(settings)
		assert_str(TranslationServer.get_locale()).is_equal(language)
		assert_str(game.tr("menu.quit")).is_equal(
			"Вийти" if language == Languages.UKRAINIAN else "Quit"
		)
		await get_tree().process_frame


func test_a_game_with_no_command_line_ignores_the_machines_language() -> void:
	TranslationServer.set_locale("uk")
	var game := _game(UserSettings.new())
	assert_str(TranslationServer.get_locale()).is_equal(Languages.ENGLISH)
	assert_str(game.tr("menu.quit")).is_equal("Quit")
	await get_tree().process_frame


## A Game on the main menu with `settings`, in its own SubViewport world (client/CLAUDE.md).
func _game(settings: UserSettings) -> Game:
	var game := GAME.instantiate() as Game
	game.read_command_line = false
	game.voice_codec = FakeVoiceCodec.new()
	game.device_input = false
	game.settings = settings
	var machine := SubViewport.new()
	machine.own_world_3d = true
	machine.render_target_update_mode = SubViewport.UPDATE_DISABLED
	machine.add_child(game)
	add_child(machine)
	auto_free(game)
	auto_free(machine)
	return game
