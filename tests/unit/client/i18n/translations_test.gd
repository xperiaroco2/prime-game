extends GdUnitTestSuite
## The copy deck as the game's translations (#208): project.godot lists both, Godot's import of
## client/i18n/strings.csv gives every key in English and Ukrainian, Ukrainian's three plural
## forms come out right for 1, 2, 5, 11 and 21 (also through tr_n), and the deck is the one its
## lock names.

const FOLDER := "res://client/i18n/"
const DECK := FOLDER + "strings.csv"
const LOCK := FOLDER + "strings.lock.json"
const TRANSLATIONS: Dictionary[String, String] = {
	"en": FOLDER + "strings.en.translation",
	"uk": FOLDER + "strings.uk.translation",
}
## The deck's counted keys and the Ukrainian form each count takes (one for 1 and 21, few for 2,
## many for 5 and 11).
const UK_PLURALS: Dictionary[String, Array] = {
	"unit.knives": ["{count} ніж", "{count} ножі", "{count} ножів", "{count} ножів", "{count} ніж"],
	"lobby.need_more":
	[
		"Ще {count} гравець до старту",
		"Ще {count} гравці до старту",
		"Ще {count} гравців до старту",
		"Ще {count} гравців до старту",
		"Ще {count} гравець до старту",
	],
}
const COUNTS: Array[int] = [1, 2, 5, 11, 21]

var _locale := ""


func before_test() -> void:
	_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_locale)


func test_project_settings_list_both_translations() -> void:
	var listed: PackedStringArray = ProjectSettings.get_setting(
		"internationalization/locale/translations", PackedStringArray()
	)
	assert_array(Array(listed)).contains_exactly_in_any_order(TRANSLATIONS.values())
	for locale: String in TRANSLATIONS:
		assert_str(_translation(locale).locale).is_equal(locale)
	assert_array(Array(TranslationServer.get_loaded_locales())).contains(["en", "uk"])


func test_every_key_has_english_and_ukrainian_text() -> void:
	var keys := _deck_keys()
	assert_int(keys.size()).is_greater(200)
	for locale: String in TRANSLATIONS:
		var translation := _translation(locale)
		assert_array(Array(translation.get_message_list())).contains_exactly_in_any_order(keys)
		for key: String in keys:
			var text := String(translation.get_message(key))
			(
				assert_str(text)
				. override_failure_message("%s: %s is empty" % [locale, key])
				. is_not_empty()
			)
			(
				assert_str(text)
				. override_failure_message("%s: %s untranslated" % [locale, key])
				. is_not_equal(key)
			)


func test_ukrainian_plurals_for_1_2_5_11_and_21() -> void:
	var uk := _translation("uk")
	for key: String in UK_PLURALS:
		var forms: Array = UK_PLURALS[key]
		for index in COUNTS.size():
			var count := COUNTS[index]
			(
				assert_str(String(uk.get_plural_message(key, key, count)))
				. override_failure_message("%s for %d" % [key, count])
				. is_equal(forms[index])
			)


func test_tr_n_picks_the_ukrainian_form_by_the_locale() -> void:
	TranslationServer.set_locale("uk")
	var forms: Array[String] = []
	for count in COUNTS:
		forms.append(tr_n("unit.knives", "unit.knives", count).format({"count": count}))
	assert_array(forms).contains_exactly(["1 ніж", "2 ножі", "5 ножів", "11 ножів", "21 ніж"])
	TranslationServer.set_locale("en")
	forms.clear()
	for count in COUNTS:
		forms.append(tr_n("unit.knives", "unit.knives", count).format({"count": count}))
	assert_array(forms).contains_exactly(
		["1 knife", "2 knives", "5 knives", "11 knives", "21 knives"]
	)


func test_the_deck_is_the_one_its_lock_names() -> void:
	var lock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LOCK))
	assert_str(str(lock.get("repo"))).is_equal("xperiaroco2/prime-game-ui")
	var tag := RegEx.create_from_string("^ui-\\d+\\.\\d+\\.\\d+$")
	assert_object(tag.search(str(lock.get("tag")))).is_not_null()
	assert_str(str(lock.get("commit"))).has_length(40)
	var files: Dictionary = lock.get("files", {})
	assert_dict(files).contains_key_value("strings.csv", FileAccess.get_sha256(DECK))
	assert_int(files.size()).is_equal(1)


func _translation(locale: String) -> Translation:
	var translation := load(TRANSLATIONS[locale]) as Translation
	assert_object(translation).is_not_null()
	return translation


## The deck's keys: the first cell of each row that has one (a plural's other forms have none).
func _deck_keys() -> Array[String]:
	var keys: Array[String] = []
	var file := FileAccess.open(DECK, FileAccess.READ)
	assert_array(Array(file.get_csv_line())).contains_exactly(
		["keys", "en", "uk", "?plural", "?context"]
	)
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 1 and not row[0].is_empty():
			keys.append(row[0])
	return keys
