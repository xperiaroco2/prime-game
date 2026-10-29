extends GdUnitTestSuite
## ClearItems (ARCHITECTURE §3.2, §9.4, #1388): the `countdown_done` row's action removes every
## item of the lobby, held (a two-handed one too), on a belt or on the ground, each with
## ItemVanished to everyone in ascending id, so none reaches Loading, Pregame or Round. A cancelled
## countdown keeps them, and a mode without the action keeps them through. Driven by
## FixtureLobbyHands.

const P1 := FixtureLobbyHands.P1
const P2 := FixtureLobbyHands.P2


func test_countdown_done_removes_every_item_and_tells_everyone() -> void:
	var game := _lobby(FixtureLobbyHands.clearing(FixtureLobbyHands.mode()))
	var ids := _ids(game.state.items.keys())
	assert_int(ids.size()).is_equal(4)
	_ready_both(game)
	var from_p1 := game.view_of(P1).events.size()
	var from_p2 := game.view_of(P2).events.size()
	FixtureLobbyHands.through_countdown(game)
	assert_str(game.phase_id()).is_equal("loading")
	assert_bool(game.state.items.is_empty()).is_true()
	for peer: int in [P1, P2]:
		assert_array(Array(game.state.player(peer).places)).is_equal([-1, -1, -1])
	var vanished := _vanished(game.view_of(P1).events.slice(from_p1))
	assert_array(vanished).is_equal(ids)
	assert_array(_vanished(game.view_of(P2).events.slice(from_p2))).is_equal(ids)
	assert_array(Array(game.diagnostics)).is_empty()


func test_no_lobby_item_reaches_the_round() -> void:
	var game := _lobby(FixtureLobbyHands.clearing(FixtureLobbyHands.mode()))
	_ready_both(game)
	FixtureLobbyHands.through_countdown(game)
	for peer: int in [P1, P2]:
		FixtureBaseMode.load_ack(game, peer)
	FixtureBaseMode.through_pregame(game)
	assert_str(game.phase_id()).is_equal("round")
	assert_bool(game.state.items.is_empty()).is_true()
	for peer: int in [P1, P2]:
		assert_int(game.state.player(peer).held_item).is_equal(-1)


func test_a_cancelled_countdown_keeps_the_items() -> void:
	var game := _lobby(FixtureLobbyHands.clearing(FixtureLobbyHands.mode()))
	var package := game.state.items[game.state.player(P1).held_item]
	_ready_both(game)
	FixtureBaseMode.ready(game, P2, false)
	assert_str(game.phase_id()).is_equal("lobby")
	assert_int(game.state.items.size()).is_equal(4)
	assert_int(package.where).is_equal(ItemState.Where.HAND)
	assert_int(package.holder).is_equal(P1)
	assert_array(game.view_of(P1).events_named(&"ItemVanished")).is_empty()


func test_without_the_action_the_items_stay() -> void:
	# The control: the fixture's row without ClearItems keeps every item through to loading.
	var game := _lobby(FixtureLobbyHands.mode())
	_ready_both(game)
	FixtureLobbyHands.through_countdown(game)
	assert_str(game.phase_id()).is_equal("loading")
	assert_int(game.state.items.size()).is_equal(4)


func test_it_vanishes_in_ascending_id_whatever_the_table_order() -> void:
	var game := _lobby(FixtureLobbyHands.clearing(FixtureLobbyHands.mode()))
	var ids := _ids(game.state.items.keys())
	# The table in descending order: an order taken from it, not from the ids, fails here.
	var items: Dictionary[int, ItemState] = {}
	for id: int in _descending(ids):
		items[id] = game.state.items[id]
	game.state.items = items
	_ready_both(game)
	var from := game.view_of(P1).events.size()
	FixtureLobbyHands.through_countdown(game)
	assert_array(_vanished(game.view_of(P1).events.slice(from))).is_equal(ids)


## P1 holds a two-handed package; P2 has a tool on its belt and another in its hand; a tool lies
## on the ground.
func _lobby(made: GameMode) -> Match:
	var game := FixtureLobbyHands.in_lobby(made, [P1, P2])
	FixtureLobbyHands.give(game, P1, &"package")
	FixtureLobbyHands.give(game, P2, &"tool")
	FixtureItemModes.swap(game, P2)
	FixtureLobbyHands.give(game, P2, &"tool")
	FixtureItemModes.lay(game, &"tool", Vector3(5, 0, 5))
	assert_int(game.state.player(P1).held_item).is_greater_equal(0)
	assert_int(game.state.player(P2).held_item).is_greater_equal(0)
	assert_array(FixtureModes.rejections(game, P2)).is_empty()
	return game


func _ready_both(game: Match) -> void:
	FixtureBaseMode.ready(game, P1)
	FixtureBaseMode.ready(game, P2)
	assert_str(game.phase_id()).is_equal("countdown")


func _vanished(events: Array[MatchEvent]) -> Array[int]:
	var found: Array[int] = []
	for event: MatchEvent in events:
		if event is ItemVanishedEvent:
			found.append((event as ItemVanishedEvent).item)
	return found


static func _ids(keys: Array) -> Array[int]:
	var found: Array[int] = []
	found.assign(keys)
	found.sort()
	return found


static func _descending(ids: Array[int]) -> Array[int]:
	var found := ids.duplicate()
	found.reverse()
	return found
