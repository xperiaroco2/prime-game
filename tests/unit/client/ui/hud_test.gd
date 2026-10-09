extends GdUnitTestSuite
## The HUD's words (client/ui/, ARCHITECTURE §4.7, M4-8) from a fake
## ClientModel and the client's own mode only: the own numbers, hand and belt, the package's
## destination, the shared progress, the clock, the own role and a dissident's teammates; when the
## map and tasks screen shows (#253; its own words and its privacy rule: map_screen_test.gd). How
## they look: the `shot`s of client/dev/hud_preview.tscn and map_preview.tscn.

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
	# watches Player2, who holds a knife and wears an unknown kind ("wrench") on its belt.
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
	assert_str(shown.belt).is_equal("Belt: wrench")
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


func test_the_map_shows_in_the_round_while_open_only() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	ui.show_screen(GameFlow.Screen.LOBBY)
	ui.open_map()
	assert_bool(ui.map_is_open()).is_false()
	ui.show_screen(GameFlow.Screen.ROUND)
	assert_bool(ui.hud.visible).is_true()
	assert_bool(ui.map.visible).is_false()
	ui.toggle_map()
	assert_bool(ui.map.visible).is_true()
	assert_bool(ui.hud.crosshair.visible).is_false()
	ui.toggle_map()
	assert_bool(ui.map.visible).is_false()
	assert_bool(ui.hud.crosshair.visible).is_true()
	# Leaving the round closes it: the next round starts with it closed.
	ui.open_map()
	ui.show_screen(GameFlow.Screen.END)
	assert_bool(ui.map_is_open()).is_false()
	assert_bool(ui.map.visible).is_false()
	ui.show_screen(GameFlow.Screen.ROUND)
	assert_bool(ui.map.visible).is_false()


func test_the_map_says_when_it_opens_and_closes_once_each() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	ui.show_screen(GameFlow.Screen.ROUND)
	var heard: Array[String] = []
	ui.map_opened.connect(func() -> void: heard.append("opened"))
	ui.map_closed.connect(func() -> void: heard.append("closed"))
	ui.open_map()
	ui.open_map()
	ui.close_map()
	ui.close_map()
	ui.open_map()
	ui.show_screen(GameFlow.Screen.LOBBY)
	assert_array(heard).contains_exactly(["opened", "closed", "opened", "closed"])


func test_the_crosshair_stays_hidden_for_the_downed_whatever_the_map_does() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	ui.show_screen(GameFlow.Screen.ROUND)
	var model := _round_model()
	model.fold(&"KnockedDown", {"peer": model.own_peer, "position": Vector3.ZERO})
	ui.refresh_round(model, _mode, NOW, HudText.Local.new())
	assert_bool(ui.hud.crosshair.visible).is_false()
	ui.open_map()
	ui.close_map()
	assert_bool(ui.hud.crosshair.visible).is_false()


func test_the_map_opens_with_its_rows_and_the_esc_menu_closes_it() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	ui.show_screen(GameFlow.Screen.ROUND)
	ui.refresh_round(_round_model(), _mode, NOW, HudText.Local.new())
	ui.open_map()
	# Its rows are there on the first frame it shows, before the next refresh_round.
	assert_int(ui.map.rows_box.get_child_count()).is_equal(2)
	var closed_under_menu: Array[bool] = []
	ui.map_closed.connect(func() -> void: closed_under_menu.append(ui.esc_open()))
	ui.open_esc(false)
	assert_bool(ui.map_is_open()).is_false()
	assert_bool(ui.map.visible).is_false()
	# It closed after the menu opened, so the game leaves the mouse free.
	assert_array(closed_under_menu).contains_exactly([true])
	# Under the menu the map key does nothing.
	ui.toggle_map()
	assert_bool(ui.map_is_open()).is_false()
	ui.close_esc()
	ui.toggle_map()
	assert_bool(ui.map.visible).is_true()


func _round_model() -> ClientModel:
	var model := Preview.fake_model(_mode, true)
	Preview.fold_round(model)
	return model


## Player2 picks up an item of a kind the client has no look for (shown by its id) and then a
## knife: the knife in its hand, the other on its belt. Both slots differ from each other and from
## the own player's (a package in the hand, a knife on the belt), so a swap of the two, or of the
## target's slots with the own ones, shows.
func _arm_player2(model: ClientModel) -> void:
	model.fold(&"ItemSpawned", {"item": 20, "kind": &"wrench", "position": Vector3(2, 0, 0)})
	model.fold(&"ItemSpawned", {"item": 21, "kind": &"knife", "position": Vector3(2, 0, 1)})
	model.fold(&"ItemPickedUp", {"peer": 2, "item": 20})
	model.fold(&"ItemPickedUp", {"peer": 2, "item": 21, "belted": 20})
