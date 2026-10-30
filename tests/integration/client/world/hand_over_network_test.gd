extends GdUnitTestSuite
## E aimed at a living player hands the hand item over (#1411; ARCHITECTURE §4.1 `HandOver`,
## §4.7.10): in the lobby a joined Game's player holds a handable `gift`, walks at the host's
## player aiming at its eye, and the moment its HandOverUse names the host it stops and presses E,
## as a player would. The host accepts the HandOver (no Rejected) and the gift is in the host
## player's hand on both Games. The prompt shows only with a handable item in the hand and a living
## player in reach under the crosshair.

const NetPair := preload("res://tests/integration/client/player/net_pair.gd")
## The most physics frames a walk takes.
const WALK_FRAMES := 600
## The most physics frames the host's answer takes to arrive.
const ANSWER_FRAMES := 30

var _pair: NetPair
var _rejected: Array[StringName] = []


func before_test() -> void:
	_pair = NetPair.new()
	var mode := _pair.mode
	mode.item_kinds.append(_gift())
	mode.actions.append(FixtureHandOverModes.hand_over_rule(FixtureHandOverModes.conditions()))
	mode.find_phase(&"lobby").accepts.append(
		AcceptSpec.of(Intents.HAND_OVER, AcceptSpec.From.LIVING)
	)
	add_child(_pair)
	_rejected.clear()


func after_test() -> void:
	_pair.free()


func test_e_aimed_at_a_living_player_in_the_lobby_hands_the_gift_over() -> void:
	assert_bool(await _pair.start()).is_true()
	var session := _pair.client.client()
	session.event_received.connect(_on_event)
	var joiner := _pair.peer_of(_pair.client)
	var host := _pair.peer_of(_pair.host)
	var gift := await _give_gift(joiner)
	var player := _pair.client.player()
	var keys := _pair.client.items().hand_over
	assert_bool(await _walk_in(player, keys, host)).is_true()
	assert_str(keys.cue()).is_not_empty()
	assert_int(keys.hand_over()).is_greater(0)
	for i: int in ANSWER_FRAMES:
		if _held_on_both(host, gift) or not _rejected.is_empty():
			break
		await _pair.frames(1)
	assert_array(_rejected).is_empty()
	for game: Game in [_pair.host, _pair.client]:
		assert_int(game.client().model.hand_item(host)).is_equal(gift)
		assert_int(game.client().model.hand_item(joiner)).is_equal(-1)
	# The hand is empty: nothing more to hand over, no prompt.
	await _pair.frames(2)
	assert_int(keys.target()).is_equal(0)
	assert_str(keys.cue()).is_empty()
	await _pair.stop()


func test_the_prompt_shows_only_for_a_handable_hand_item_and_a_player_in_reach() -> void:
	assert_bool(await _pair.start()).is_true()
	var joiner := _pair.peer_of(_pair.client)
	var host := _pair.peer_of(_pair.host)
	var player := _pair.client.player()
	var keys := _pair.client.items().hand_over
	# An empty hand, the host in reach under the crosshair: nothing to hand over.
	assert_bool(await _pair.walk_to(player, Vector3(0, 0, -1.2))).is_true()
	_pair.aim(player, _eye_of(_pair.host.player()))
	await _pair.frames(3)
	assert_int(keys.target()).is_equal(0)
	assert_str(keys.cue()).is_empty()
	assert_int(keys.hand_over()).is_equal(-1)
	await _give_gift(joiner)
	_pair.aim(player, _eye_of(_pair.host.player()))
	await _pair.frames(3)
	assert_int(keys.target()).is_equal(host)
	assert_str(keys.cue()).is_not_empty()
	# Aimed past the host: no player under the crosshair.
	_pair.aim(player, _eye_of(_pair.host.player()) + Vector3(2, 0, 0))
	await _pair.frames(3)
	assert_int(keys.target()).is_equal(0)
	assert_str(keys.cue()).is_empty()
	# Aimed at the host from out of reach.
	assert_bool(await _pair.walk_to(player, Vector3(0, 0, -3.5))).is_true()
	_pair.aim(player, _eye_of(_pair.host.player()))
	await _pair.frames(3)
	assert_int(keys.target()).is_equal(0)
	assert_str(keys.cue()).is_empty()
	await _pair.stop()


## A one-handed, handable kind, as the full mug is.
func _gift() -> ItemKind:
	var kind := FixtureItemModes.item_kind(&"gift", [])
	kind.handable = true
	return kind


## Puts a new gift in `peer`'s hand on the host (reaching into its Match as NetPair.knock_down
## does: the lobby of the fixture has no bar), announced as a deal announces an item; waits until
## the joiner's Game sees it in that hand and returns its id.
func _give_gift(peer: int) -> int:
	var node := _pair.host.get_node("HostNode") as HostNode
	var played := (node.get("_session") as HostSession).game
	var ctx := MatchContext.new(played)
	ctx.state = played.state
	ctx.mode = played.mode
	ctx.world = FlatWorldQuery.new()
	ctx.tick = played.ticked_through()
	var feet := played.state.player(peer).position
	var item := Items.spawn(ctx, played.mode.find_item_kind(&"gift"), feet)
	ctx.emit(ItemSpawnedEvent.new(item.id, item.kind.id, item.position))
	Items.give(ctx, peer, item)
	var model := _pair.client.client().model
	for i: int in ANSWER_FRAMES:
		if model.hand_item(peer) == item.id:
			break
		await _pair.frames(1)
	assert_int(model.hand_item(peer)).is_equal(item.id)
	return item.id


## Walks `player` at `peer`'s player, aiming at its eye every frame, until `keys` names it; then
## stops. False when it never did.
func _walk_in(player: PlayerController, keys: HandOverUse, peer: int) -> bool:
	var other := _pair.host.player()
	for i: int in WALK_FRAMES:
		await _pair.frames(1)
		if keys.target() == peer:
			player.move_input = Vector2.ZERO
			return true
		_pair.aim(player, _eye_of(other))
		player.move_input = Vector2(0.0, 1.0)
	player.move_input = Vector2.ZERO
	return false


func _eye_of(body: PlayerController) -> Vector3:
	return body.global_position + Vector3.UP * _pair.mode.player_rules.eye_height_of(false)


func _held_on_both(peer: int, item: int) -> bool:
	for game: Game in [_pair.host, _pair.client]:
		if game.client().model.hand_item(peer) != item:
			return false
	return true


func _on_event(event_name: StringName, fields: Dictionary) -> void:
	if event_name == &"Rejected":
		_rejected.append(fields.get("reason", &"") as StringName)
