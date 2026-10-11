extends GdUnitTestSuite
## Languages (#208): the first launch follows a Ukrainian system and is English otherwise, the
## player's choice wins over the system, applying sets the game's locale, a choice is written to
## the settings file and read back on the next launch, and each language is named in its own.

const PATH := "user://languages_test.cfg"

var _locale := ""


func before_test() -> void:
	_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_locale)
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)


func test_the_first_launch_is_ukrainian_only_on_a_ukrainian_system() -> void:
	assert_str(Languages.first_launch("uk")).is_equal(Languages.UKRAINIAN)
	for system: String in ["en", "ru", "pl", "de", ""]:
		assert_str(Languages.first_launch(system)).is_equal(Languages.ENGLISH)


func test_the_choice_wins_over_the_system() -> void:
	var settings := UserSettings.new()
	assert_str(Languages.shown(settings, "uk")).is_equal("uk")
	assert_str(Languages.shown(settings, "fr")).is_equal("en")
	settings.language = "en"
	assert_str(Languages.shown(settings, "uk")).is_equal("en")
	settings.language = "uk"
	assert_str(Languages.shown(settings, "en")).is_equal("uk")


func test_apply_sets_the_locale_and_the_text_follows() -> void:
	var settings := UserSettings.new()
	assert_str(Languages.apply(settings, "uk")).is_equal("uk")
	assert_str(TranslationServer.get_locale()).is_equal("uk")
	assert_str(tr("common.back")).is_equal("Назад")
	assert_str(Languages.apply(settings, "de")).is_equal("en")
	assert_str(TranslationServer.get_locale()).is_equal("en")
	assert_str(tr("common.back")).is_equal("Back")


func test_a_choice_applies_at_once_and_outlives_a_restart() -> void:
	var settings := UserSettings.new(PATH)
	assert_int(Languages.choose(settings, "uk")).is_equal(OK)
	assert_str(TranslationServer.get_locale()).is_equal("uk")
	var next_launch := UserSettings.new(PATH)
	assert_int(next_launch.read()).is_equal(OK)
	assert_str(next_launch.language).is_equal("uk")
	assert_str(Languages.apply(next_launch, "en")).is_equal("uk")
	assert_int(Languages.choose(next_launch, "en")).is_equal(OK)
	var third := UserSettings.new(PATH)
	third.read()
	assert_str(Languages.shown(third, "uk")).is_equal("en")


func test_an_unknown_language_changes_nothing() -> void:
	var settings := UserSettings.new(PATH)
	settings.language = "uk"
	TranslationServer.set_locale("uk")
	assert_int(Languages.choose(settings, "fr")).is_equal(ERR_INVALID_PARAMETER)
	assert_str(settings.language).is_equal("uk")
	assert_str(TranslationServer.get_locale()).is_equal("uk")
	assert_bool(FileAccess.file_exists(PATH)).is_false()


func test_each_language_is_named_in_its_own_in_every_locale() -> void:
	for locale: String in Languages.ALL:
		TranslationServer.set_locale(locale)
		assert_str(tr(Languages.name_key(Languages.ENGLISH))).is_equal("English")
		assert_str(tr(Languages.name_key(Languages.UKRAINIAN))).is_equal("Українська")
