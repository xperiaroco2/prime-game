extends GdUnitTestSuite
## The pinball's sounds (#1674, client/audio/pinball_sounds.gd): from the own ClientPinball's public
## state alone, at the table's place: a flipper raised, a ball launched and lost, points scored, a
## new best; edges only within one game, so the first state seen, a new game and the same state
## told again (a join, ResetMatch) play nothing.

const AT := Vector3(4, 1, -2)

var _pinball: ClientPinball
var _sounds: PinballSounds


func before_test() -> void:
	_pinball = ClientPinball.new()
	_sounds = PinballSounds.new()


func test_the_first_state_seen_only_seeds() -> void:
	_state({"left": true, "in_play": true, "score": 500, "best": 900})
	assert_array(_due()).is_empty()


func test_each_change_of_one_game_plays_its_sound_at_the_table() -> void:
	_state({})
	_due()
	_state({"left": true})
	assert_array(_due()).contains_exactly([SfxSet.PINBALL_FLIPPER])
	# Held, then released: no sound; the right one raised: one.
	_state({"left": true})
	assert_array(_due()).is_empty()
	_state({"right": true})
	assert_array(_due()).contains_exactly([SfxSet.PINBALL_FLIPPER])
	_state({"in_play": true})
	assert_array(_due()).contains_exactly([SfxSet.PINBALL_LAUNCH])
	_state({"in_play": true, "score": 100})
	assert_array(_due()).contains_exactly([SfxSet.PINBALL_BUMPER])
	_state({"score": 100})
	assert_array(_due()).contains_exactly([SfxSet.PINBALL_DRAIN])
	_state({"score": 100, "best": 100})
	assert_array(_due()).contains_exactly([SfxSet.PINBALL_BEST])
	_state({"right": true})
	var cues := _sounds.due(_pinball, AT)
	assert_that(cues[0]["position"]).is_equal(AT)


func test_a_new_game_and_a_state_told_again_play_nothing() -> void:
	_state({"in_play": true, "score": 300})
	_due()
	# The same state again (a join, ResetMatch).
	_state({"in_play": true, "score": 300})
	assert_array(_due()).is_empty()
	# A new game: its score starts again, its ball comes in with it.
	_state({"game": 2, "in_play": false, "score": 0})
	assert_array(_due()).is_empty()
	_state({"game": 3, "in_play": true, "score": 50})
	assert_array(_due()).is_empty()


func test_clear_forgets_the_state() -> void:
	_state({"best": 100})
	_due()
	_sounds.clear()
	_state({"best": 400})
	assert_array(_due()).is_empty()


func _due() -> Array[StringName]:
	var ids: Array[StringName] = []
	for cue: Dictionary in _sounds.due(_pinball, AT):
		ids.append(cue["id"] as StringName)
	return ids


func _state(changed: Dictionary) -> void:
	var fields := {
		"game": 1,
		"player": 2,
		"left": false,
		"right": false,
		"in_play": false,
		"score": 0,
		"balls_left": 3,
		"best": 0,
		"best_name": "",
	}
	fields.merge(changed, true)
	_pinball.fold(&"PinballState", fields)
