class_name Languages
extends RefCounted
## The interface languages (#208): English and Ukrainian, the copy deck's columns
## (client/i18n/strings.csv, imported by `tools\run.cmd ui-copy`). The player's choice lives in
## UserSettings.language; before any choice the game speaks the system's language when it is
## Ukrainian and English otherwise. choose() switches at once: Godot retranslates every Control
## whose text is a key, and a screen that builds its text in code rebuilds it on
## NOTIFICATION_TRANSLATION_CHANGED.

const ENGLISH := "en"
const UKRAINIAN := "uk"
## Every language, in the order a picker lists them.
const ALL: Array[String] = [ENGLISH, UKRAINIAN]


## The copy deck's key of a language's name, written in that language in every locale
## ("English", "Українська").
static func name_key(language: String) -> String:
	return "lang." + language


## The language before the player chose one: Ukrainian on a Ukrainian system, English otherwise.
## `system` is a language code (OS.get_locale_language()).
static func first_launch(system: String) -> String:
	return UKRAINIAN if system == UKRAINIAN else ENGLISH


## The language the game speaks: the player's choice, else first_launch(system).
static func shown(settings: UserSettings, system := OS.get_locale_language()) -> String:
	if ALL.has(settings.language):
		return settings.language
	return first_launch(system)


## Sets the game's locale to shown(settings) and returns it.
static func apply(settings: UserSettings, system := OS.get_locale_language()) -> String:
	var language := shown(settings, system)
	TranslationServer.set_locale(language)
	return language


## The player picks `language` (one of ALL; any other is ignored): it is applied now and written
## to the settings file. Returns the file's error, or ERR_INVALID_PARAMETER for an unknown one.
static func choose(settings: UserSettings, language: String) -> Error:
	if not ALL.has(language):
		return ERR_INVALID_PARAMETER
	settings.language = language
	apply(settings)
	return settings.write()
