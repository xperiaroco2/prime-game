extends GdUnitTestSuite
## The Esc menu's Role tab (client/ui/role_facts.gd, role_page.gd; #491, #175's update of
## 2026-10-03): the own role and its goal from the own ClientModel, and for a dissident the
## teammates its own Teammates event named, in join order, the own player and a player who left not
## among them. Nothing else of the model, and nothing of core/.

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"

var _mode: GameMode


func before() -> void:
	_mode = load(MODE) as GameMode


func test_an_engineer_sees_the_role_and_the_goal_and_no_team() -> void:
	var model := Preview.fake_model(_mode, false)
	assert_str(RoleFacts.of(model, _mode).role_key).is_empty()
	model.fold(&"RoleAssigned", {"role": &"crew"})
	var facts := RoleFacts.of(model, _mode)
	assert_str(facts.role_key).is_equal("role.engineer")
	assert_str(facts.goal_key).is_equal("role.goal.engineer")
	assert_array(Array(facts.team)).is_empty()
	var page: RolePage = auto_free(RolePage.new())
	page.show_facts(facts)
	assert_str(page.role_label.text).is_equal("role.engineer")
	assert_str(page.goal_label.text).is_equal("role.goal.engineer")
	assert_bool(page.team.visible).is_false()


func test_a_dissident_sees_its_teammates_in_join_order_without_itself() -> void:
	var model := Preview.fake_model(_mode, false)
	model.fold(&"RoleAssigned", {"role": &"dissident"})
	# The own player is 2; 3 and 1, in any order; 9 left the session (not in the roster).
	model.fold(&"Teammates", {"role": &"dissident", "peers": PackedInt32Array([3, 2, 9, 1])})
	var facts := RoleFacts.of(model, _mode)
	assert_str(facts.goal_key).is_equal("role.goal.dissident")
	assert_array(Array(facts.team)).contains_exactly(["Player1", "Player3"])
	var page: RolePage = auto_free(RolePage.new())
	page.show_facts(facts)
	assert_bool(page.team.visible).is_true()
	assert_int(page.grid.get_child_count()).is_equal(2)
	assert_str(page.count_label.text).is_equal(tr("esc.role.teammates").format({"count": 2}))
	assert_int(page.count_label.auto_translate_mode).is_equal(Node.AUTO_TRANSLATE_MODE_DISABLED)


func test_teammates_of_another_role_never_show() -> void:
	# Only model.teammates[model.role]: a list under another role (none reaches a crew member's
	# client; a hand-folded one here) is not this player's team.
	var model := Preview.fake_model(_mode, false)
	model.fold(&"RoleAssigned", {"role": &"crew"})
	model.fold(&"Teammates", {"role": &"dissident", "peers": PackedInt32Array([1, 3])})
	assert_array(Array(RoleFacts.of(model, _mode).team)).is_empty()


func test_a_long_team_scrolls_in_its_250_px_view() -> void:
	# More names than any match has, so the list must outgrow the view.
	var page: RolePage = auto_free(RolePage.new())
	page.theme = GameUi.THEME
	add_child(page)
	var facts := RoleFacts.new()
	facts.role_key = "role.dissident"
	for index: int in 30:
		facts.team.append("Teammate%d" % index)
	page.show_facts(facts)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(page.grid.columns).is_equal(2)
	assert_float(page.scroll.size.y).is_equal(250.0)
	assert_bool(page.grid.size.y > page.scroll.size.y).is_true()
	assert_int(page.scroll.horizontal_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_DISABLED)
	# A smaller team rebuilds the list.
	facts.team = PackedStringArray(["Taras"])
	page.show_facts(facts)
	assert_int(page.grid.get_child_count()).is_equal(1)


func test_the_role_page_reads_nothing_of_core_state() -> void:
	# client/CLAUDE.md: the client knows only what server/ sent it.
	for path: String in ["res://client/ui/role_facts.gd", "res://client/ui/role_page.gd"]:
		var source := FileAccess.get_file_as_string(path)
		for word: String in ["MatchState", "PeerView", "Match.", "HostSession", "res://core"]:
			assert_str(source).override_failure_message("%s: %s" % [path, word]).not_contains(word)
