extends GdUnitTestSuite
## ContentNames (#549, ARCHITECTURE §4.7.48): every role, item kind and task type of every shipped
## game mode shows by a copy deck key with English and Ukrainian text; content the deck does not
## name shows its display name, else its id; a room by `room.<id>` where the deck has it; a map by
## its scene's file name; text() follows the language now.

const MODES := "res://content/modes"

var _locale := ""


func before_test() -> void:
	_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_locale)


func test_every_shipped_role_item_and_task_has_a_deck_key() -> void:
	var modes := 0
	for file: String in DirAccess.get_files_at(MODES):
		if not file.ends_with(".tres"):
			continue
		var mode := load(MODES.path_join(file)) as GameMode
		assert_object(mode).override_failure_message(file).is_not_null()
		modes += 1
		for role: GameRole in mode.roles:
			_assert_keyed(ContentNames.role(role.id, mode), "%s: role %s" % [file, role.id])
		for kind: ItemKind in mode.item_kinds:
			_assert_keyed(ContentNames.item(kind.id, mode), "%s: item %s" % [file, kind.id])
		for type: TaskType in mode.task_types:
			_assert_keyed(ContentNames.task(type.id, mode), "%s: task %s" % [file, type.id])
	assert_int(modes).is_greater_equal(2)


func test_every_exception_is_in_the_deck() -> void:
	for id: StringName in ContentNames.ROLE_EXCEPTIONS:
		_assert_keyed(ContentNames.ROLE_EXCEPTIONS[id], String(id))


## Content that adds a type the deck already names needs no edit in ContentNames: the key is found
## by the convention, with no mode needed.
func test_a_type_the_deck_names_resolves_by_its_convention() -> void:
	var mode := GameMode.new()
	assert_str(ContentNames.role(&"engineer", mode)).is_equal("role.engineer")
	assert_str(ContentNames.item(&"knife", mode)).is_equal("item.knife")
	assert_str(ContentNames.task(&"switches", mode)).is_equal("task.switches")
	assert_str(ContentNames.item(&"switch", null)).is_equal("item.switch")
	assert_str(ContentNames.task(&"delivery", null)).is_equal("task.delivery")


func test_both_languages_and_a_switch() -> void:
	var mode := load(MODES.path_join("base_mode.tres")) as GameMode
	TranslationServer.set_locale("en")
	assert_str(ContentNames.text(ContentNames.role(&"crew", mode))).is_equal("Engineer")
	assert_str(ContentNames.text(ContentNames.item(&"package", mode))).is_equal("Package")
	assert_str(ContentNames.text(ContentNames.task(&"delivery", mode))).is_equal("Delivery")
	assert_str(ContentNames.text(ContentNames.room(&"lounge"))).is_equal("Break room")
	TranslationServer.set_locale("uk")
	assert_str(ContentNames.text(ContentNames.role(&"crew", mode))).is_equal("Інженер")
	assert_str(ContentNames.text(ContentNames.role(&"dissident", mode))).is_equal("Дисидент")
	assert_str(ContentNames.text(ContentNames.item(&"knife", mode))).is_equal("Ніж")
	assert_str(ContentNames.text(ContentNames.task(&"delivery", mode))).is_equal("Доставка")
	assert_str(ContentNames.text(ContentNames.room(&"storage"))).is_equal("Склад")


func test_what_the_deck_does_not_name() -> void:
	var mode := GameMode.new()
	var role := GameRole.new()
	role.id = &"saboteur"
	role.display_name = "Saboteur"
	mode.roles.append(role)
	var kind := ItemKind.new()
	kind.id = &"wrench"
	mode.item_kinds.append(kind)
	assert_str(ContentNames.role(&"saboteur", mode)).is_equal("Saboteur")
	assert_str(ContentNames.item(&"wrench", mode)).is_equal("wrench")
	assert_str(ContentNames.task(&"wiring", mode)).is_equal("wiring")
	assert_str(ContentNames.role(&"crew", null)).is_equal("role.engineer")
	assert_str(ContentNames.room(&"boiler_room")).is_equal("boiler_room")
	assert_str(ContentNames.text("Saboteur")).is_equal("Saboteur")
	assert_str(ContentNames.map("res://levels/house/house.tscn")).is_equal("House")
	assert_bool(ContentNames.has_key("room.boiler_room")).is_false()
	assert_bool(ContentNames.has_key("room.lab")).is_true()


## `key` is a deck key with text in English and Ukrainian.
func _assert_keyed(key: String, what: String) -> void:
	for locale: String in ["en", "uk"]:
		var translation := load("res://client/i18n/strings.%s.translation" % locale) as Translation
		var text := String(translation.get_message(key))
		var failure := "%s: %s has no %s text" % [what, key, locale]
		assert_str(text).override_failure_message(failure).is_not_empty()
		assert_str(text).override_failure_message(failure).is_not_equal(key)
