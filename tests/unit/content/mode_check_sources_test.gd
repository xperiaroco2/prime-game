extends GdUnitTestSuite
## ModeCheck's errors name where they come from (#1253): each starts with the mode's file, and a
## part's index path carries its own file or its sub-resource id in the mode's file (4.7 gives a
## sub-resource loaded from a .tres the path "<file>::<id>").

const MODE_PATH := "res://tests/fixtures/match/sourced_mode.tres"
const STRAY := "phase round accepts MoveClaim from bits 64, which name no sender"


func test_an_error_of_a_sub_resource_names_the_file_and_the_sub_resource_id() -> void:
	var mode := _with_a_stray_bit()
	mode.resource_path = MODE_PATH
	mode.phases[1].resource_path = MODE_PATH + "::Phase_round"
	assert_array(Array(ModeCheck.run(mode).errors)).contains(
		["%s: mode.phases[1] (::Phase_round): %s" % [MODE_PATH, STRAY]]
	)


func test_an_error_of_a_part_in_its_own_file_names_that_file() -> void:
	var mode := _with_a_stray_bit()
	mode.resource_path = MODE_PATH.replace("sourced", "sourced_own")
	mode.phases[1].resource_path = "res://tests/fixtures/match/round_phase.tres"
	assert_array(Array(ModeCheck.run(mode).errors)).contains(
		[
			(
				"%s: mode.phases[1] (res://tests/fixtures/match/round_phase.tres): %s"
				% [mode.resource_path, STRAY]
			)
		]
	)


func test_a_mode_built_in_code_keeps_the_bare_index_path() -> void:
	assert_array(Array(ModeCheck.run(_with_a_stray_bit()).errors)).contains(
		["mode.phases[1]: " + STRAY]
	)


## FixtureModes.basic() whose round accepts MoveClaim from a bit that names no sender: one error
## of the round's PhaseSpec, found by the walk.
func _with_a_stray_bit() -> GameMode:
	var mode := FixtureModes.basic()
	mode.phases[1].accepts[1].from = AcceptSpec.From.LIVING | 64
	return mode
