extends GdUnitTestSuite
## The own role's facts (client/ui/role_facts.gd; #491, #175's update of 2026-10-03): the own role
## and its goal from the own ClientModel, and for a dissident the teammates its own Teammates event
## named, in join order, the own player and a player who left not among them. Nothing else of the
## model, and nothing of core/. (The Esc menu's Role page that drew them went with #1422: no menu
## has shown it since #1571.)

const Preview := preload("res://client/dev/screen_preview.gd")
const MODE := "res://content/modes/base_mode.tres"

var _mode: GameMode


func before() -> void:
	_mode = load(MODE) as GameMode


func test_an_engineer_has_the_role_and_the_goal_and_no_team() -> void:
	var model := Preview.fake_model(_mode, false)
	assert_str(RoleFacts.of(model, _mode).role_key).is_empty()
	model.fold(&"RoleAssigned", {"role": &"crew"})
	var facts := RoleFacts.of(model, _mode)
	assert_str(facts.role_key).is_equal("role.engineer")
	assert_str(facts.goal_key).is_equal("role.goal.engineer")
	assert_array(Array(facts.team)).is_empty()


func test_a_dissident_has_its_teammates_in_join_order_without_itself() -> void:
	var model := Preview.fake_model(_mode, false)
	model.fold(&"RoleAssigned", {"role": &"dissident"})
	# The own player is 2; 3 and 1, in any order; 9 left the session (not in the roster).
	model.fold(&"Teammates", {"role": &"dissident", "peers": PackedInt32Array([3, 2, 9, 1])})
	var facts := RoleFacts.of(model, _mode)
	assert_str(facts.goal_key).is_equal("role.goal.dissident")
	assert_array(Array(facts.team)).contains_exactly(["Player1", "Player3"])


func test_teammates_of_another_role_never_show() -> void:
	# Only model.teammates[model.role]: a list under another role (none reaches a crew member's
	# client; a hand-folded one here) is not this player's team.
	var model := Preview.fake_model(_mode, false)
	model.fold(&"RoleAssigned", {"role": &"crew"})
	model.fold(&"Teammates", {"role": &"dissident", "peers": PackedInt32Array([1, 3])})
	assert_array(Array(RoleFacts.of(model, _mode).team)).is_empty()


func test_the_role_facts_read_nothing_of_core_state() -> void:
	# client/CLAUDE.md: the client knows only what server/ sent it.
	var source := FileAccess.get_file_as_string("res://client/ui/role_facts.gd")
	for word: String in ["MatchState", "PeerView", "Match.", "HostSession", "res://core"]:
		assert_str(source).override_failure_message(word).not_contains(word)
