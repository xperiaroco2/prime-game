extends GdUnitTestSuite
## Ghosts cannot pick up, carry or use items (MVP rules, ARCHITECTURE §7.1): no game mode in
## `content/modes/` accepts PickUp, PutDown or Use from anyone but the living, in any phase. A
## rule of the game, not a number, so this test loads `content/` like the mode check does (§9.6).

const MODES_DIR := "res://content/modes/"
const ITEM_INTENTS: Array[StringName] = [Intents.PICK_UP, Intents.PUT_DOWN, Intents.USE]


func test_only_the_living_may_send_an_item_intent_in_any_mode() -> void:
	var paths := _mode_paths(MODES_DIR)
	assert_array(paths).contains(["res://content/modes/base_mode.tres"])
	for path: String in paths:
		var mode := load(path) as GameMode
		# A mode file that does not load must fail here, not pass the ban vacuously.
		assert_object(mode).override_failure_message("%s is not a GameMode" % path).is_not_null()
		if mode == null:
			continue
		for spec: PhaseSpec in mode.phases:
			for intent: StringName in ITEM_INTENTS:
				var from := spec.senders_of(intent)
				(
					assert_int(from & ~AcceptSpec.From.LIVING)
					. override_failure_message(
						"%s: phase %s accepts %s from %d" % [path, spec.id, intent, from]
					)
					. is_equal(0)
				)


func test_the_base_mode_round_accepts_pick_up_and_put_down_from_the_living() -> void:
	var mode := load("res://content/modes/base_mode.tres") as GameMode
	var round_spec := mode.find_phase(&"round")
	assert_int(round_spec.senders_of(Intents.PICK_UP)).is_equal(AcceptSpec.From.LIVING)
	assert_int(round_spec.senders_of(Intents.PUT_DOWN)).is_equal(AcceptSpec.From.LIVING)
	assert_object(mode.find_item_kind(&"package")).is_not_null()


func _mode_paths(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file: String in dir.get_files():
		if file.ends_with(".tres"):
			found.append(dir_path.path_join(file))
	for sub: String in dir.get_directories():
		found.append_array(_mode_paths(dir_path.path_join(sub)))
	found.sort()
	return found
