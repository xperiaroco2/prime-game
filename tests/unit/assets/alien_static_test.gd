extends GdUnitTestSuite
## The alien look's colour slots (assets/characters/alien_chameleon/look/alien_static.gd, #1690):
## the art's script with the game's casts (its credits entry) picks a player's colours as the art's
## slot_colours does: a skin as "#rrggbb", Color or [r, g, b], a lip colour picked or following
## the skin, the detail's switch as a bool or a number. Text, not Git LFS: it runs on CI.

const AlienStatic := preload("res://assets/characters/alien_chameleon/look/alien_static.gd")
const BASES := {
	"skin": Color(0.3, 0.6, 0.4),
	"lips": Color(0.5, 0.2, 0.2),
	"detail": Color(0.2, 0.3, 0.2),
	"front": Color(0.8, 0.85, 0.8),
	"gill_tips": Color(0.6, 0.3, 0.3),
}


func test_no_pick_keeps_every_base() -> void:
	var u := AlienStatic.slot_colours(BASES, {})
	assert_that(u["skin_color"]).is_equal(BASES["skin"])
	assert_that(u["lip_color"]).is_equal(BASES["lips"])
	assert_that(u["detail_color"]).is_equal(BASES["detail"])
	assert_that(u["front_color"]).is_equal(BASES["front"])
	assert_float(u["detail_on"] as float).is_equal(0.0)
	assert_float(u["gill_mode"] as float).is_equal(1.0)


func test_picks_as_a_hex_string_a_list_and_a_number_take() -> void:
	var picks := {"skin": "#e39c8c", "lips": [0.6, 0.3, 0.3], "detail_on": 1}
	var u := AlienStatic.slot_colours(BASES, picks)
	assert_that(u["skin_color"]).is_equal(Color("#e39c8c"))
	assert_that(u["lip_color"]).is_equal(Color(0.6, 0.3, 0.3))
	assert_float(u["detail_on"] as float).is_equal(1.0)
	# The detail follows the picked skin as its paint does: off its base, and a Color.
	assert_bool(u["detail_color"] is Color).is_true()
	assert_that(u["detail_color"]).is_not_equal(BASES["detail"])
	assert_bool(u["front_color"] is Color).is_true()


func test_a_skin_alone_moves_the_lips_with_it() -> void:
	var u := AlienStatic.slot_colours(BASES, {"skin": Color(0.9, 0.5, 0.5)})
	assert_that(u["skin_color"]).is_equal(Color(0.9, 0.5, 0.5))
	assert_bool(u["lip_color"] is Color).is_true()
	assert_that(u["lip_color"]).is_not_equal(BASES["lips"])
	assert_that(u["lip_color"]).is_equal(
		AlienStatic.recolour(BASES["lips"] as Color, BASES["skin"] as Color, Color(0.9, 0.5, 0.5))
	)
