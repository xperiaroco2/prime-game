extends GdUnitTestSuite
## The HUD's and the task screen's words (client/ui/, ARCHITECTURE §4.7, M4-8) from a fake
## ClientModel and the client's own mode only: the own numbers, hand and belt, the package's
## destination, the shared progress, the clock, the own role and a dissident's teammates; the task
## screen's rows with no position. How they look: the `shot`s of
## client/dev/hud_preview.tscn and task_screen_preview.tscn.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
## The fake round's host tick: 271 s before the match clock ends.
const NOW := 100

var _mode: GameMode


func before() -> void:
	_mode = load(MODE) as GameMode


func test_the_hud_shows_the_own_numbers_slots_destination_progress_and_clock() -> void:
	var model := _round_model()
	var local := HudText.Local.new()
	local.stamina = 61.2
	local.hint = "E: pick up Knife"
	var shown := HudText.of(model, _mode, NOW, local)
	assert_str(shown.health).is_equal("Health 75")
	assert_str(shown.stamina).is_equal("Stamina 62")
	assert_str(shown.hand).is_equal("Hand: Package (both hands)")
	assert_str(shown.belt).is_equal("Belt: Knife")
	assert_str(shown.destination).is_not_empty()
	assert_that(shown.destination_colour).is_equal(Preview.CIRCLE_COLOUR)
	assert_str(shown.progress).is_equal("Tasks 3 / 5")
	assert_str(shown.clock).is_equal("4:31")
	assert_str(shown.hint).is_equal("E: pick up Knife")


func test_the_hud_names_the_own_role_and_only_a_dissidents_teammates() -> void:
	var model := _round_model()
	var shown := HudText.of(model, _mode, NOW, HudText.Local.new())
	assert_str(shown.role).is_equal("Role: Dissident")
	# The own player is left out; the others by their names.
	assert_str(shown.teammates).is_equal("Teammates: Player3")
	var crew := Preview.fake_model(_mode, true)
	Preview.fold_round(crew, false)
	crew.fold(&"RoleAssigned", {"role": &"crew"})
	var crew_shown := HudText.of(crew, _mode, NOW, HudText.Local.new())
	assert_str(crew_shown.role).is_equal("Role: Engineer")
	assert_str(crew_shown.teammates).is_empty()


func test_empty_slots_no_package_and_no_status_yet() -> void:
	var model := Preview.fake_model(_mode, true)
	var shown := HudText.of(model, _mode, NOW, HudText.Local.new())
	assert_str(shown.health).is_equal("Health -")
	assert_str(shown.stamina).is_equal("Stamina -")
	assert_str(shown.hand).is_equal("Hand: empty")
	assert_str(shown.belt).is_equal("Belt: empty")
	assert_str(shown.destination).is_empty()
	assert_str(shown.progress).is_empty()
	assert_str(shown.clock).is_empty()
	assert_str(shown.role).is_empty()


func test_a_delivered_package_has_no_destination_and_an_unknown_kind_shows_its_id() -> void:
	var model := _round_model()
	model.fold(&"PackageDelivered", {"item": Preview.PACKAGE, "station": Preview.CIRCLE})
	assert_int(ItemViews.destination_item(model)).is_equal(-1)
	model.fold(&"ItemSpawned", {"item": 40, "kind": &"wrench", "position": Vector3.ZERO})
	model.fold(&"ItemPickedUp", {"peer": model.own_peer, "item": 40})
	assert_str(HudText.slot_text(model, _mode, 40)).is_equal("wrench")


func test_a_dead_spectator_sees_whom_it_watches_and_the_targets_hand_and_belt() -> void:
	# #168: the own player (peer 1) holds the package with the knife on its belt and dies; it
	# watches Player2, who holds a knife and wears another on its belt.
	var model := _round_model()
	_arm_player2(model)
	model.fold(&"Died", {"peer": model.own_peer, "position": Vector3.ZERO})
	var local := HudText.Local.new()
	local.stamina = 61.2
	local.hint = "E: pick up Knife"
	local.watching = 2
	var shown := HudText.of(model, _mode, NOW, local)
	assert_str(shown.spectating).is_equal("Spectating Player2")
	assert_str(shown.hand).is_equal("Hand: Knife")
	assert_str(shown.belt).is_equal("Belt: Knife")
	# None of the spectator's own slots, numbers, destination or crosshair hint.
	assert_str(shown.health).is_empty()
	assert_str(shown.stamina).is_empty()
	assert_str(shown.destination).is_empty()
	assert_str(shown.hint).is_empty()
	# The match's lines and the spectator's own role stay; nothing names the target's role.
	assert_str(shown.clock).is_equal("4:31")
	assert_str(shown.progress).is_equal("Tasks 3 / 5")
	assert_str(shown.role).is_equal("Role: Dissident")


func test_a_dead_spectator_sees_nothing_private_of_the_target() -> void:
	# The M4 ADR's §3 item 2: no health, stamina, role, teammates or private event of the target,
	# whatever the own model holds (here its own SelfStatus, role and teammates).
	var model := _round_model()
	_arm_player2(model)
	model.fold(&"Died", {"peer": model.own_peer, "position": Vector3.ZERO})
	var local := HudText.Local.new()
	local.stamina = 61.2
	local.watching = 2
	var shown := HudText.of(model, _mode, NOW, local)
	var target_lines := "\n".join(
		[shown.spectating, shown.hand, shown.belt, shown.health, shown.stamina, shown.hint]
	)
	for word: String in ["health", "stamina", "role", "dissident", "engineer", "teammates"]:
		assert_str(target_lines.to_lower()).not_contains(word)
	# Nobody to watch: no target line and no slots at all.
	local.watching = 0
	var alone := HudText.of(model, _mode, NOW, local)
	assert_str(alone.spectating).is_empty()
	assert_str(alone.hand).is_empty()
	assert_str(alone.belt).is_empty()


func test_the_living_and_the_downed_see_their_own_slots_whatever_is_watched() -> void:
	var model := _round_model()
	_arm_player2(model)
	var local := HudText.Local.new()
	local.watching = 2
	var living := HudText.of(model, _mode, NOW, local)
	assert_str(living.spectating).is_empty()
	assert_str(living.hand).is_equal("Hand: Package (both hands)")
	model.fold(&"KnockedDown", {"peer": model.own_peer, "position": Vector3.ZERO})
	var downed := HudText.of(model, _mode, NOW, local)
	assert_str(downed.spectating).is_empty()
	assert_str(downed.belt).is_equal("Belt: Knife")
	assert_str(downed.health).is_equal("Health 75")


func test_the_hud_control_shows_the_spectating_line_with_the_slots() -> void:
	var hud: Hud = auto_free(Hud.new())
	var model := _round_model()
	_arm_player2(model)
	model.fold(&"Died", {"peer": model.own_peer, "position": Vector3.ZERO})
	var local := HudText.Local.new()
	local.watching = 2
	hud.show_hud(HudText.of(model, _mode, NOW, local))
	assert_bool(hud.spectating_label.visible).is_true()
	assert_str(hud.spectating_label.text).is_equal("Spectating Player2")
	assert_bool(hud.health_label.visible).is_false()
	assert_bool(hud.stamina_label.visible).is_false()
	hud.show_hud(HudText.of(_round_model(), _mode, NOW, HudText.Local.new()))
	assert_bool(hud.spectating_label.visible).is_false()


func test_the_hud_control_hides_empty_lines_and_paints_the_swatch() -> void:
	var hud: Hud = auto_free(Hud.new())
	var shown := HudText.of(_round_model(), _mode, NOW, HudText.Local.new())
	hud.show_hud(shown)
	assert_bool(hud.hint_label.visible).is_false()
	assert_bool(hud.hand_label.visible).is_true()
	assert_that(hud.swatch.color).is_equal(Preview.CIRCLE_COLOUR)
	# A corner with nothing to show draws no empty panel (the life preview's round before a status).
	hud.show_hud(HudText.Shown.new())
	assert_bool((hud.role_label.get_parent().get_parent() as Control).visible).is_false()
	hud.show_hud(shown)
	assert_bool((hud.role_label.get_parent().get_parent() as Control).visible).is_true()
	hud.aiming = false
	assert_bool(hud.crosshair.visible).is_false()


func test_the_task_screen_lists_each_task_by_name_description_and_progress() -> void:
	var model := _round_model()
	var rows := TaskScreen.rows(model, _mode)
	var delivery := _mode.find_task_type(&"delivery")
	assert_int(rows.size()).is_equal(2)
	assert_str(rows[0][0]).is_equal("%s  1 / 3" % delivery.display_name)
	assert_str(rows[0][1]).is_equal(delivery.description)
	assert_str(rows[1][0]).is_equal("%s  2 / 2" % delivery.display_name)
	assert_str(TaskScreen.progress_text(model)).is_equal("Shared progress: 3 / 5")
	# A task type the client's mode does not name shows its id.
	model.fold(&"TaskState", {"task": 5, "type": &"zones", "done": 0, "total": 4})
	assert_str(TaskScreen.rows(model, _mode)[2][0]).is_equal("zones  0 / 4")


func test_the_task_screen_names_no_place() -> void:
	# The M4 ADR's §3 item 4: no position of an item, a player or a spawn point, no map.
	var model := _round_model()
	var screen: TaskScreen = auto_free(TaskScreen.new())
	screen.refresh(model, _mode)
	var texts := PackedStringArray()
	for label: Node in screen.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	var all := "\n".join(texts)
	assert_str(all).contains("Shared progress: 3 / 5")
	for item: ClientModel.Item in model.items.values():
		assert_str(all).not_contains(str(item.position))
	assert_str(all).not_contains("Player")
	assert_str(all.to_lower()).not_contains("map")


func test_the_task_screen_shows_in_the_round_while_held_only() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	ui.reads_device_input = false
	ui.show_screen(GameFlow.Screen.ROUND)
	assert_bool(ui.hud.visible).is_true()
	assert_bool(ui.tasks.visible).is_false()
	ui.show_tasks(true)
	assert_bool(ui.tasks.visible).is_true()
	assert_bool(ui.hud.crosshair.visible).is_false()
	ui.show_screen(GameFlow.Screen.LOBBY)
	assert_bool(ui.tasks.visible).is_false()
	assert_bool(ui.hud.visible).is_false()


func test_the_crosshair_stays_hidden_for_the_downed_whatever_tab_does() -> void:
	# GameUi reads Tab after the game's refresh_round in the same frame: its show_tasks(false) must
	# not bring back the crosshair of a downed player.
	var ui: GameUi = auto_free(GameUi.new())
	ui.reads_device_input = false
	ui.show_screen(GameFlow.Screen.ROUND)
	var model := _round_model()
	model.fold(&"KnockedDown", {"peer": model.own_peer, "position": Vector3.ZERO})
	ui.refresh_round(model, _mode, NOW, HudText.Local.new())
	ui.show_tasks(false)
	assert_bool(ui.hud.crosshair.visible).is_false()
	ui.show_tasks(true)
	ui.show_tasks(false)
	assert_bool(ui.hud.crosshair.visible).is_false()


func test_tab_shows_the_task_screen_with_its_rows_and_never_under_the_esc_menu() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	ui.show_screen(GameFlow.Screen.ROUND)
	ui.refresh_round(_round_model(), _mode, NOW, HudText.Local.new())
	Input.action_press(&"task_screen")
	ui._process(0.0)
	assert_bool(ui.tasks.visible).is_true()
	# Its rows are there on the first frame it shows, before the next refresh_round.
	var texts := PackedStringArray()
	for label: Node in ui.tasks.find_children("*", "Label", true, false):
		texts.append((label as Label).text)
	assert_str("\n".join(texts)).contains("Shared progress: 3 / 5")
	ui.open_esc(false)
	ui._process(0.0)
	Input.action_release(&"task_screen")
	assert_bool(ui.tasks.visible).is_false()
	assert_bool(ui.hud.crosshair.visible).is_true()


func _round_model() -> ClientModel:
	var model := Preview.fake_model(_mode, true)
	Preview.fold_round(model)
	return model


## Player2 picks up two knives: one in its hand, one on its belt.
func _arm_player2(model: ClientModel) -> void:
	model.fold(&"ItemSpawned", {"item": 20, "kind": &"knife", "position": Vector3(2, 0, 0)})
	model.fold(&"ItemSpawned", {"item": 21, "kind": &"knife", "position": Vector3(2, 0, 1)})
	model.fold(&"ItemPickedUp", {"peer": 2, "item": 20})
	model.fold(&"ItemPickedUp", {"peer": 2, "item": 21, "belted": 20})
