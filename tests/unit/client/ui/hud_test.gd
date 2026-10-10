extends GdUnitTestSuite
## What the round's HUD shows (client/ui/HudText, ARCHITECTURE §4.7.37, #489; M4-8 first) from a
## fake ClientModel and the client's own mode only: the time, the own role's key, the own health
## and stamina as fractions, the microphone, the own hand and belt, the item under the crosshair
## and the own raise; nothing of another player, no player list, destination or task progress;
## a dead spectator's watched name and that player's public slots (#168). When the map and tasks
## screen shows (#253; its own words and its privacy rule: map_screen_test.gd). How the Hud draws
## it: hud_layout_test.gd and the `shot`s of client/dev/hud_preview.tscn.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"
## The fake round's host tick: 271 s before the match clock ends.
const NOW := 100

var _mode: GameMode


func before() -> void:
	_mode = load(MODE) as GameMode


func test_the_hud_shows_the_own_time_role_vitals_and_slots() -> void:
	var model := _round_model()
	var local := HudText.Local.new()
	local.stamina = 61.0
	local.mic = true
	var shown := HudText.of(model, _mode, NOW, local)
	assert_str(shown.time).is_equal("04:31")
	assert_str(shown.role).is_equal("role.dissident")
	assert_bool(shown.vitals).is_true()
	# SelfStatus's 75 of the mode's 100 health; the predicted 61 of 100 stamina.
	assert_float(shown.health).is_equal_approx(0.75, 0.0001)
	assert_float(shown.stamina).is_equal_approx(0.61, 0.0001)
	assert_bool(shown.mic).is_true()
	assert_bool(shown.slots).is_true()
	# The package in both hands: its key, the pack's `item` icon, wide; the knife on the belt.
	assert_str(shown.hand.item).is_equal("item.package")
	assert_str(shown.hand.icon).is_equal("item")
	assert_bool(shown.hand.two_handed).is_true()
	assert_str(shown.belt.item).is_equal("item.knife")
	assert_str(shown.belt.icon).is_equal("knife")
	assert_bool(shown.belt.two_handed).is_false()
	assert_str(shown.aim).is_empty()
	assert_float(shown.raising).is_negative()
	assert_str(shown.watching).is_empty()


func test_the_timer_is_mm_ss_and_holds_the_widest_time() -> void:
	assert_str(HudText.clock_text(442)).is_equal("07:22")
	assert_str(HudText.clock_text(0)).is_equal("00:00")
	assert_str(HudText.clock_text(44 * 60 + 44)).is_equal("44:44")


func test_the_role_is_its_deck_key_and_an_unknown_role_its_id() -> void:
	var crew := Preview.fake_model(_mode, true)
	Preview.fold_round(crew, false)
	crew.fold(&"RoleAssigned", {"role": &"crew"})
	assert_str(HudText.of(crew, _mode, NOW, HudText.Local.new()).role).is_equal("role.engineer")
	crew.fold(&"RoleAssigned", {"role": &"saboteur"})
	assert_str(HudText.role_key(crew, _mode)).is_equal("saboteur")


func test_a_dissident_and_an_engineer_see_the_same_hud_but_the_role() -> void:
	# Nothing hidden on the HUD (#489): a dissident's own Teammates knowledge changes nothing on it
	# (no player list; its teammates show only as the name plates' mark, #257).
	var local := HudText.Local.new()
	local.stamina = 50.0
	local.aim = Preview.KNIFE
	var dissident := HudText.of(_round_model(), _mode, NOW, local)
	var crew_model := _round_model()
	crew_model.fold(&"RoleAssigned", {"role": &"crew"})
	crew_model.teammates.clear()
	var crew := HudText.of(crew_model, _mode, NOW, local)
	assert_str(dissident.role).is_not_equal(crew.role)
	assert_str(_fields(dissident)).is_equal(_fields(crew))
	for word: String in ["Player2", "Player3", "teammate"]:
		assert_str(_fields(dissident)).not_contains(word)


func test_nothing_carried_before_the_first_status_and_no_role() -> void:
	var model := Preview.fake_model(_mode, true)
	var shown := HudText.of(model, _mode, NOW, HudText.Local.new())
	# Full bars before the first SelfStatus and the first predicted stamina.
	assert_float(shown.health).is_equal(1.0)
	assert_float(shown.stamina).is_equal(1.0)
	assert_bool(shown.hand.is_empty()).is_true()
	assert_bool(shown.belt.is_empty()).is_true()
	assert_str(shown.time).is_empty()
	assert_str(shown.role).is_empty()
	assert_bool(shown.mic).is_false()


func test_an_unknown_kind_shows_its_id_and_no_icon() -> void:
	var model := _round_model()
	model.fold(&"ItemSpawned", {"item": 40, "kind": &"wrench", "position": Vector3.ZERO})
	var slot := HudText.slot_of(model, _mode, 40)
	assert_str(slot.item).is_equal("wrench")
	assert_str(slot.icon).is_empty()
	assert_bool(HudText.slot_of(model, _mode, 99).is_empty()).is_true()


func test_aim_names_the_item_under_the_crosshair_and_the_raise_replaces_it() -> void:
	var model := _round_model()
	model.fold(&"ItemSpawned", {"item": 41, "kind": &"package", "position": Vector3(1, 0, 1)})
	var local := HudText.Local.new()
	local.aim = 41
	assert_str(HudText.of(model, _mode, NOW, local).aim).is_equal("item.package")
	local.raising = 0.6
	var raising := HudText.of(model, _mode, NOW, local)
	assert_float(raising.raising).is_equal(0.6)
	assert_str(raising.aim).is_empty()
	local.aim = -1
	local.raising = -1.0
	assert_str(HudText.of(model, _mode, NOW, local).aim).is_empty()


func test_a_dead_spectator_sees_whom_it_watches_and_the_targets_hand_and_belt() -> void:
	# #168: the own player (peer 1) holds the package with the knife on its belt and dies; it
	# watches Player2, who holds a knife and wears an unknown kind ("wrench") on its belt.
	var model := _round_model()
	_arm_player2(model)
	model.fold(&"Died", {"peer": model.own_peer, "position": Vector3.ZERO})
	var local := HudText.Local.new()
	local.stamina = 61.2
	local.aim = Preview.KNIFE
	local.mic = true
	local.raising = 0.5
	local.watching = 2
	var shown := HudText.of(model, _mode, NOW, local)
	assert_str(shown.watching).is_equal("Player2")
	assert_bool(shown.slots).is_true()
	assert_str(shown.hand.item).is_equal("item.knife")
	assert_str(shown.belt.item).is_equal("wrench")
	# None of the spectator's own vitals, aim, raise, role or time (the handoff s09's `dead`).
	assert_bool(shown.vitals).is_false()
	assert_bool(shown.mic).is_false()
	assert_str(shown.aim).is_empty()
	assert_float(shown.raising).is_negative()
	assert_str(shown.role).is_empty()
	assert_str(shown.time).is_empty()


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
	for word: String in ["role", "dissident", "engineer", "player3"]:
		assert_str(_fields(shown).to_lower()).not_contains(word)
	# Nobody to watch: no name and no slots at all.
	local.watching = 0
	var alone := HudText.of(model, _mode, NOW, local)
	assert_str(alone.watching).is_empty()
	assert_bool(alone.slots).is_false()


func test_the_living_and_the_downed_see_their_own_slots_whatever_is_watched() -> void:
	var model := _round_model()
	_arm_player2(model)
	var local := HudText.Local.new()
	local.watching = 2
	var living := HudText.of(model, _mode, NOW, local)
	assert_str(living.watching).is_empty()
	assert_str(living.hand.item).is_equal("item.package")
	model.fold(&"KnockedDown", {"peer": model.own_peer, "position": Vector3.ZERO})
	var downed := HudText.of(model, _mode, NOW, local)
	assert_str(downed.watching).is_empty()
	assert_str(downed.belt.item).is_equal("item.knife")
	assert_float(downed.health).is_equal_approx(0.75, 0.0001)


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
	assert_bool(ui.hud.cross.visible).is_false()
	ui.toggle_map()
	assert_bool(ui.map.visible).is_false()
	assert_bool(ui.hud.cross.visible).is_true()
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
	assert_bool(ui.hud.cross.visible).is_false()
	ui.open_map()
	ui.close_map()
	assert_bool(ui.hud.cross.visible).is_false()


func test_the_map_opens_with_its_rows_and_the_esc_menu_closes_it() -> void:
	var ui: GameUi = auto_free(GameUi.new())
	ui.show_screen(GameFlow.Screen.ROUND)
	ui.refresh_round(_round_model(), _mode, NOW, HudText.Local.new())
	ui.open_map()
	# Its rows are there on the first frame it shows, before the next refresh_round: one per task
	# type (#490), so the fake round's two Delivery tasks share one.
	assert_int(ui.map.rows_box.get_child_count()).is_equal(1)
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


func test_the_role_chip_hides_while_the_map_is_open_and_comes_back_after() -> void:
	# The engineer on #652 (carried to #491): the HUD's role line hides while the map is open, at
	# once, not at the next refresh_round, and a refresh under the map keeps it hidden.
	var ui: GameUi = auto_free(GameUi.new())
	ui.show_screen(GameFlow.Screen.ROUND)
	ui.refresh_round(_round_model(), _mode, NOW, HudText.Local.new())
	assert_bool(ui.hud.role.visible).is_true()
	ui.open_map()
	assert_bool(ui.hud.role.visible).is_false()
	ui.refresh_round(_round_model(), _mode, NOW, HudText.Local.new())
	assert_bool(ui.hud.role.visible).is_false()
	ui.close_map()
	assert_bool(ui.hud.role.visible).is_true()


## Every field of `shown` but the role, as one line.
func _fields(shown: HudText.Shown) -> String:
	var parts: Array = [
		shown.time,
		shown.vitals,
		shown.health,
		shown.stamina,
		shown.mic,
		shown.slots,
		shown.aim,
		shown.raising,
		shown.watching
	]
	for slot: HudText.Slot in [shown.hand, shown.belt]:
		parts.append_array([slot.item, slot.icon, slot.two_handed])
	return " | ".join(parts.map(func(part: Variant) -> String: return str(part)))


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
