extends GdUnitTestSuite
## The downed cannot pick up, put down, swap or use items (MVP rules and vision revision 1,
## ARCHITECTURE §7.1): no game mode in `content/modes/` accepts PickUp, PutDown, Swap or Use from
## anyone but the living, in any phase. A rule of the game, not a number, so this test loads
## `content/` like the mode check does (§9.6). The base mode's package takes both hands, its knife
## one (vision revision 1, Two hands), and Delivery has a description for the task screen.

const MODES_DIR := "res://content/modes/"
const BASE_MODE := "res://content/modes/base_mode.tres"
const ITEM_INTENTS: Array[StringName] = [
	Intents.PICK_UP, Intents.PUT_DOWN, Intents.USE, Intents.SWAP
]


func test_only_the_living_may_send_an_item_intent_in_any_mode() -> void:
	var paths := _mode_paths(MODES_DIR)
	assert_array(paths).contains([BASE_MODE])
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
	var mode := load(BASE_MODE) as GameMode
	var round_spec := mode.find_phase(&"round")
	assert_int(round_spec.senders_of(Intents.PICK_UP)).is_equal(AcceptSpec.From.LIVING)
	assert_int(round_spec.senders_of(Intents.PUT_DOWN)).is_equal(AcceptSpec.From.LIVING)
	assert_object(mode.find_item_kind(&"package")).is_not_null()


func test_the_base_mode_swaps_from_the_living_and_its_package_takes_both_hands() -> void:
	var mode := load(BASE_MODE) as GameMode
	assert_int(mode.find_phase(&"round").senders_of(Intents.SWAP)).is_equal(AcceptSpec.From.LIVING)
	assert_int(mode.find_item_kind(&"package").hands).is_equal(2)
	assert_int(mode.find_item_kind(&"knife").hands).is_equal(1)
	var swap: Rule = null
	for rule: Rule in mode.actions:
		if rule.trigger == Intents.SWAP:
			swap = rule
	assert_object(swap).is_not_null()
	assert_int(swap.conditions.size()).is_equal(2)
	assert_object(swap.conditions[0]).is_instanceof(CarriesItem)
	assert_object(swap.conditions[1]).is_instanceof(HandNotTwoHanded)
	assert_object(swap.effects[0]).is_instanceof(SwapHands)
	for type: TaskType in mode.task_types:
		assert_str(type.description.strip_edges()).is_not_empty()


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
