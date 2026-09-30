extends GdUnitTestSuite
## The base mode's Delivery in `content/` (ARCHITECTURE §9.5): its palette has a colour for every
## circle a full lobby deals with the default settings, so `all_ready`'s fit check (2b) never
## refuses the defaults for want of colours; and Round runs TaskTicks. Like the mode check, this
## test loads `content/` on purpose (§9.6).

const BASE_MODE := "res://content/modes/base_mode.tres"


func test_the_palette_covers_a_full_lobby_with_the_default_settings() -> void:
	var mode := load(BASE_MODE) as GameMode
	var settings := mode.default_settings()
	var demands := Demands.new()
	var delivery := _delivery(mode)
	assert_object(delivery).is_not_null()
	delivery.add_demands(settings, mode.max_players, settings[&"tasks_per_player"], demands)
	var needed := mode.max_players * settings[&"tasks_per_player"] * settings[&"subtasks_per_task"]
	assert_dict(demands.colours).is_equal({&"circle": needed})
	assert_int(demands.palettes[&"circle"]).is_greater_equal(needed)


func test_round_runs_task_ticks_and_the_mode_deals_delivery() -> void:
	var mode := load(BASE_MODE) as GameMode
	var round_spec := mode.find_phase(&"round")
	assert_int(round_spec.tick_systems.size()).is_equal(1)
	assert_bool(round_spec.tick_systems[0] is TaskTicks).is_true()
	assert_int(mode.task_types.size()).is_equal(1)
	assert_object(_delivery(mode).package).is_same(mode.find_item_kind(&"package"))


func _delivery(mode: GameMode) -> Delivery:
	for type: TaskType in mode.task_types:
		if type is Delivery:
			return type as Delivery
	return null
