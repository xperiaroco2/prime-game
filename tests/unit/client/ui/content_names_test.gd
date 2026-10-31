extends GdUnitTestSuite
## ContentNames (#549, ARCHITECTURE §4.7.48): every role, item kind and task type of every shipped
## game mode shows by a copy deck key with English and Ukrainian text; content the deck does not
## name shows its display name, else its id; a room by `room.<id>` where the deck has it; a map by
## its scene's file name; text() follows the language now.

const MODES := "res://content/modes"
## Shipped item kinds the deck (ui-0.8.0) has no key for yet, each with the display name it shows
## meanwhile: the photo task's film and photo (#784), Cooking's 22 kinds (#775, the cooking
## ADR's §5.1 names; the burger of #1101), car repair's three parts (#810) and the lobby bar's
## mugs (#1390). No deck key fits any and none is invented (`strings.csv` is the UI track's, byte
## for byte), so the UI track is asked for `item.<id>` of each. Self-expiring: the test fails once
## the deck carries the key, and the entry goes. An exception the engineer approves in #784's,
## #775's, #810's, #1101's and #1390's PRs, not a decision.
const ITEMS_NOT_IN_DECK_YET: Dictionary[StringName, String] = {
	&"film": "Film",
	&"photo": "Photo",
	&"bun_white": "White bun",
	&"bun_sesame": "Sesame bun",
	&"bun_dark": "Dark bun",
	&"patty_light_raw": "Raw light patty",
	&"patty_red_raw": "Raw red patty",
	&"patty_deep_red_raw": "Raw deep red patty",
	&"patty_light": "Light patty",
	&"patty_red": "Red patty",
	&"patty_deep_red": "Deep red patty",
	&"patty_burnt": "Burnt patty",
	&"basil": "Basil",
	&"dill": "Dill",
	&"rosemary": "Rosemary",
	&"chives": "Chives",
	&"mint": "Mint",
	&"box_bun_white": "Box of white buns",
	&"box_bun_sesame": "Box of sesame buns",
	&"box_bun_dark": "Box of dark buns",
	&"box_patty_light": "Box of light patties",
	&"box_patty_red": "Box of red patties",
	&"box_patty_deep_red": "Box of deep red patties",
	&"car_part_green": "Green part",
	&"car_part_blue": "Blue part",
	&"car_part_yellow": "Yellow part",
	# The ship's engine's crystals (#1461, in the base mode since #1462): the UI track's keys.
	&"crystal_spent": "Spent crystal",
	&"crystal_charged": "Charged crystal",
}
## Shipped task types the deck has no key for yet and ContentNames.TASK_EXCEPTIONS does not map,
## each with the display name it shows meanwhile: car repair (#810), which runs beside client work
## and so left `client/` alone (a TASK_EXCEPTIONS entry to the deck's `room.garage` would be the
## nearest key, as Cooking reads as `room.kitchen`). Self-expiring like the items above: the test
## fails once the deck has `task.<id>` or TASK_EXCEPTIONS maps the id. An exception the engineer
## approves in #810's PR, not a decision.
const TASKS_NOT_IN_DECK_YET: Dictionary[StringName, String] = {
	&"car_repair": "Repair the car",
}

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
			var what := "%s: item %s" % [file, kind.id]
			if ITEMS_NOT_IN_DECK_YET.has(kind.id):
				_assert_not_in_deck_yet(kind.id, mode, what)
				continue
			_assert_keyed(ContentNames.item(kind.id, mode), what)
		for type: TaskType in mode.task_types:
			var task := "%s: task %s" % [file, type.id]
			if TASKS_NOT_IN_DECK_YET.has(type.id):
				_assert_task_not_in_deck_yet(type.id, mode, task)
				continue
			_assert_keyed(ContentNames.task(type.id, mode), task)
	assert_int(modes).is_greater_equal(2)


func test_every_exception_is_in_the_deck() -> void:
	for id: StringName in ContentNames.ROLE_EXCEPTIONS:
		_assert_keyed(ContentNames.ROLE_EXCEPTIONS[id], String(id))
	for id: StringName in ContentNames.TASK_EXCEPTIONS:
		_assert_keyed(ContentNames.TASK_EXCEPTIONS[id], String(id))


## The greybox's Delivery by colours (#828, DE15 (i)) reads as the deck's Delivery, as the House's
## by meaning does: each map's players see one "Delivery".
func test_the_greyboxs_delivery_by_colours_is_the_decks_delivery() -> void:
	assert_str(ContentNames.task(&"colour_delivery", null)).is_equal("task.delivery")
	assert_str(ContentNames.task(&"colour_delivery", GameMode.new())).is_equal("task.delivery")


## The Generator (#800) reads as the deck's Switches, the one key the deck has for it, until the
## UI track adds `task.generator` (a placeholder the engineer approves in #800's PR).
func test_the_generator_is_the_decks_switches() -> void:
	assert_str(ContentNames.task(&"generator", null)).is_equal("task.switches")
	assert_str(ContentNames.task(&"generator", GameMode.new())).is_equal("task.switches")


## The photo task (#784) reads as the deck's Photo zone, the one photo key the deck has, until the
## UI track adds `task.photo` (a placeholder the engineer approves in #784's PR).
func test_the_photo_task_is_the_decks_photo_zone() -> void:
	assert_str(ContentNames.task(&"photo", null)).is_equal("room.photo_zone")
	assert_str(ContentNames.task(&"photo", GameMode.new())).is_equal("room.photo_zone")


## Cooking (#775) reads as the deck's Kitchen, the nearest key the deck has, until the UI track
## adds `task.cooking` (a placeholder the engineer approves in #775's PR).
func test_cooking_is_the_decks_kitchen() -> void:
	assert_str(ContentNames.task(&"cooking", null)).is_equal("room.kitchen")
	assert_str(ContentNames.task(&"cooking", GameMode.new())).is_equal("room.kitchen")


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
	assert_str(ContentNames.room(&"boiler_room")).is_equal("room.boiler_room")
	assert_str(ContentNames.text("Saboteur")).is_equal("Saboteur")
	assert_str(ContentNames.map("res://levels/house/house.tscn")).is_equal("House")
	assert_bool(ContentNames.has_key("room.boiler_room")).is_true()
	assert_bool(ContentNames.has_key("room.lab")).is_true()


## An item kind of ITEMS_NOT_IN_DECK_YET: still no `item.<id>` in the deck (once it lands, remove
## the entry) and the kind shows its display name.
func _assert_not_in_deck_yet(id: StringName, mode: GameMode, what: String) -> void:
	var key := ContentNames.ITEM_PREFIX + String(id)
	var landed := "%s: the deck has %s now: remove it from ITEMS_NOT_IN_DECK_YET" % [what, key]
	assert_bool(ContentNames.has_key(key)).override_failure_message(landed).is_false()
	assert_str(ContentNames.item(id, mode)).override_failure_message(what).is_equal(
		ITEMS_NOT_IN_DECK_YET[id]
	)


## A task type of TASKS_NOT_IN_DECK_YET: still no `task.<id>` in the deck and no TASK_EXCEPTIONS
## entry (once either lands, remove the entry), and the type shows its display name.
func _assert_task_not_in_deck_yet(id: StringName, mode: GameMode, what: String) -> void:
	var key := ContentNames.TASK_PREFIX + String(id)
	var landed := "%s: the deck has %s now: remove it from TASKS_NOT_IN_DECK_YET" % [what, key]
	assert_bool(ContentNames.has_key(key)).override_failure_message(landed).is_false()
	var mapped := "%s: TASK_EXCEPTIONS maps it now: remove it from TASKS_NOT_IN_DECK_YET" % what
	assert_bool(ContentNames.TASK_EXCEPTIONS.has(id)).override_failure_message(mapped).is_false()
	assert_str(ContentNames.task(id, mode)).override_failure_message(what).is_equal(
		TASKS_NOT_IN_DECK_YET[id]
	)


## `key` is a deck key with text in English and Ukrainian.
func _assert_keyed(key: String, what: String) -> void:
	for locale: String in ["en", "uk"]:
		var translation := load("res://client/i18n/strings.%s.translation" % locale) as Translation
		var text := String(translation.get_message(key))
		var failure := "%s: %s has no %s text" % [what, key, locale]
		assert_str(text).override_failure_message(failure).is_not_empty()
		assert_str(text).override_failure_message(failure).is_not_equal(key)


func test_a_station_kind_shows_its_deck_key_else_its_id() -> void:
	# #801: the deck has no station keys yet; a kind shows its id until it has.
	assert_str(ContentNames.station(&"probe_kind")).is_equal("probe_kind")
	var deck := Translation.new()
	deck.locale = TranslationServer.get_locale()
	deck.add_message(&"station.probe_kind", &"Probe")
	TranslationServer.add_translation(deck)
	var named := ContentNames.station(&"probe_kind")
	TranslationServer.remove_translation(deck)
	assert_str(named).is_equal("station.probe_kind")
